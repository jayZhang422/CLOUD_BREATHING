"""整卷清单、启动等待、真实回读身份与失败发布边界。"""
from pathlib import Path
import hashlib
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch

import numpy as np

from pc_fpga.ethernet.volume import (build_program, q16_coordinates, nearest_coordinates,
    reason_volume, receive_result, START, QUERY, RELEASE, STATUS, RESULT_BASE, SCRIPT_BASE, MAP_BASE)
from pc_fpga.ethernet.transfer import send_volume
from pc_fpga.files import write_json, read_json
from test_pipeline import create_ct
from test_vol2_transpose import hardware_gather
from pc_fpga.ct.convert import prepare, make_job


class VolumeChecks(unittest.TestCase):
    def fixture(self, root):
        create_ct(root/'dicom');prepare(root/'dicom',root/'case')
        case=root/'case';job=make_job(case,0x00400000,1)
        program,maps,header,summary=build_program(job,read_json(case/'input/metadata.json'))
        write_json(case/'handoff/program.json',dict(input_sha256=job['input']['sha256'],compact_sha256=job['compact_bin']['sha256'],header_hex=header.hex(),
            commands=len(program)//96,schedule_sha256=hashlib.sha256(program).hexdigest()))
        write_json(case/'handoff/send_receipt.json',dict(transfer_id=123,input_sha256=job['input']['sha256'],
            compact_sha256=job['compact_bin']['sha256']))
        return case,job,program,maps,header,summary

    def test_integer_maps_and_full_program_layout(self):
        self.assertEqual(q16_coordinates(4,3).tolist(),[0,98304,196608])
        self.assertEqual(nearest_coordinates(3,4).tolist(),[0,1,1,2])
        with tempfile.TemporaryDirectory() as temp:
            case,job,program,maps,header,summary=self.fixture(Path(temp))
            count=len(program)//96
            self.assertEqual(struct.unpack('<8I',header[:32]),(0x324c4f56,2,SCRIPT_BASE,count,0x00400000,2,RESULT_BASE,1048576))
            self.assertEqual(program[-96:],bytes([255])+bytes(95))
            self.assertLessEqual(SCRIPT_BASE+len(program),MAP_BASE)
            self.assertLessEqual(MAP_BASE+len(maps),0x09000000)
            self.assertEqual([row['model'] for row in summary],job['models'])
            output_slices={0:[],5:[],6:[],8:[]}
            gather_commands=0
            for offset in range(0,len(program)-96,96):
                kind=program[offset];cmd=program[offset+32:offset+96]
                if kind==4:
                    gather_commands+=1
                    self.assertEqual(cmd[0],4)
                    self.assertIn(cmd[1],(0,1,2,4,5,6))
                    # lobe/airway/tumor 使用朝向等价的预转置视图并以朝向 0 读取；vessel 本就是朝向 0。
                    names={1:'lobe_t',2:'lobe_t',3:'native_t',4:'native_t',5:'native',6:'native',7:'native_t',8:'native_t'}
                    view=next(v for v in job['compact_bin']['views'] if v['name']==names[gather_commands])
                    self.assertEqual(cmd[1]&3,0)
                    self.assertEqual(struct.unpack_from('<I',cmd,4)[0],view['base'])
                    self.assertEqual(struct.unpack_from('<I',cmd,12)[0],view['planes'])
                    self.assertEqual(struct.unpack_from('<I',cmd,16)[0],view['bytes'])
                    self.assertEqual(struct.unpack_from('<HHII',cmd,20),
                        (view['width'],view['height'],view['row_stride'],view['plane_stride']))
                elif kind==1:
                    self.assertIn(cmd[0],(1,2,5,10,11,12,13))
                    self.assertFalse(cmd[1]&1)
                    self.assertGreaterEqual(struct.unpack_from('<I',cmd,16)[0],0x0a000000)
                    self.assertLess(struct.unpack_from('<I',cmd,24)[0],RESULT_BASE)
                elif kind==3:
                    output_slices[cmd[3]].append((struct.unpack_from('<I',cmd,8)[0]-RESULT_BASE)//524288)
            self.assertEqual(output_slices,{0:[0,1],5:[0,1],6:[0,1],8:[0,1]})
            self.assertEqual(gather_commands,4*2)

    def test_vol2_upload_sends_each_aligned_section_and_records_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp))
            client=Mock();client.rpc.return_value={'state':0}
            with patch('pc_fpga.ethernet.transfer.OpClient',return_value=client):
                receipt=send_volume(case,job,'host',8080,'bind')
            client.rpc.assert_called_once_with(STATUS)
            self.assertEqual(len(client.upload_file.call_args_list),len(job['compact_bin']['views']))
            for call,view in zip(client.upload_file.call_args_list,job['compact_bin']['views']):
                self.assertEqual(call.args[:4],(view['base'],case/job['compact_bin']['file'],
                    view['file_offset'],view['bytes']))
                self.assertEqual(view['base']%32,0)
                self.assertEqual(view['file_offset']%32,0)
            self.assertEqual(receipt['compact_sha256'],job['compact_bin']['sha256'])
            self.assertEqual(read_json(case/'handoff/send_receipt.json'),receipt)

    def test_vol2_send_releases_previous_terminal_run_before_retry(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp))
            write_json(case/'handoff/send_receipt.json',dict(transfer_id=77,
                input_sha256=job['input']['sha256'],compact_sha256=job['compact_bin']['sha256']))
            client=Mock();client.rpc.side_effect=[{'state':3},{'state':0},{'state':0}]
            with patch('pc_fpga.ethernet.transfer.OpClient',return_value=client):
                send_volume(case,job,'host',8080,'bind')
            self.assertEqual(client.rpc.call_args_list[1].args,(RELEASE,77))
            self.assertEqual(client.rpc.call_args_list[2].args,(STATUS,))

    def test_start_wait_read_release_and_release_ack_recovery(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));client=Mock()
            size=job['result_contract']['bytes']
            client.rpc.side_effect=[dict(state=1,run_id=123,bytes=size,mac_bytes=1),dict(state=2,run_id=123,bytes=size,mac_bytes=4)]
            with patch('pc_fpga.ethernet.volume.time.sleep'):
                manifest=reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            self.assertEqual([c.args[0] for c in client.rpc.call_args_list],[START,QUERY])
            data=(np.zeros(size//2,dtype='<u2')+353).tobytes()
            client=Mock();client.rpc.side_effect=[dict(state=2,run_id=123,bytes=size),TimeoutError('lost ACK')]
            client.read.side_effect=lambda identity,address,count:data[address-RESULT_BASE:address-RESULT_BASE+count]
            with self.assertRaises(TimeoutError):
                receive_result(case,manifest,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            self.assertFalse(read_json(case/'prediction/metadata.json')['ddr_released'])
            retry=Mock()
            metadata=receive_result(case,manifest,'host',8080,'bind',client_factory=lambda *a,**kw:retry)
            retry.rpc.assert_called_once_with(RELEASE,123);retry.read.assert_not_called()
            self.assertTrue(metadata['ddr_released'])
            self.assertEqual((case/'prediction/segmentation_uint16.bin').read_bytes(),data)

    def test_query_extended_debug_payload_is_parsed_without_unpack_error(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));client=Mock()
            debug=struct.pack('<4I',0x31474456,12,10,0x0d00)+bytes(32)
            client.rpc.side_effect=[
                dict(state=1,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=1,data=debug),
                dict(state=2,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=257,data=debug)]
            with patch('pc_fpga.ethernet.volume.time.sleep'):
                manifest=reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            self.assertTrue(manifest.exists())
            status=read_json(case/'handoff/inference_status.json')
            self.assertEqual(status['hardware']['input_words'],10)

    def test_vdg2_debug_fields_match_rtl_word_order(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));client=Mock()
            debug=struct.pack('<16I',0x32474456,0x0d21,12,8,3,4,5,6,7,9,0,0,0,0,9,7)
            client.rpc.side_effect=[
                dict(state=1,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=1,data=debug),
                dict(state=2,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=257,data=debug)]
            with patch('pc_fpga.ethernet.volume.time.sleep'):
                manifest=reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            status=read_json(case/'handoff/inference_status.json')
            self.assertTrue(manifest.exists())
            self.assertEqual(status['hardware']['gather_read_requests'],12)
            self.assertEqual(status['hardware']['gather_write_requests'],8)
            self.assertEqual(status['hardware']['gather_request_stall_cycles'],3)
            self.assertEqual(status['hardware']['gather_response_wait_cycles'],4)
            self.assertEqual(status['volume_cycles'],dict(fetch=5,operator=6,gather=7,classify=9))

    def test_vdg3_reports_kind4_cycles_cache_and_ddr_queue(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));client=Mock()
            debug=struct.pack('<16I',0x33474456,0x0d21,120,64,3,4,5,6,70,9,
                0x89abcdef,0x12,45,75,0x00000032,184)
            client.rpc.side_effect=[
                dict(state=1,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=1,data=debug),
                dict(state=2,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=257,data=debug)]
            with patch('pc_fpga.ethernet.volume.time.sleep'):
                manifest=reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            status=read_json(case/'handoff/inference_status.json')
            self.assertTrue(manifest.exists())
            self.assertEqual(status['hardware']['diagnostic_version'],3)
            self.assertEqual(status['hardware']['compact_cache_hits'],45)
            self.assertEqual(status['hardware']['compact_cache_misses'],75)
            self.assertEqual(status['hardware']['gather_pending'],2)
            self.assertEqual(status['hardware']['gather_pending_peak'],3)
            self.assertEqual(status['hardware']['gather_response_count'],184)
            self.assertEqual(status['volume_cycles']['kind4'],0x1289abcdef)

    def test_vdg4_combines_64bit_counter_high_words(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));client=Mock()
            debug=struct.pack('<16I',0x34474456,0x0d21,120,64,3,4,5,6,70,9,
                0x89abcdef,0x12,45,75,0x00000032,184)
            debug+=struct.pack('<8I',1,2,3,4,5,6,7,8)
            client.rpc.side_effect=[
                dict(state=1,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=1,data=debug),
                dict(state=2,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=257,data=debug)]
            with patch('pc_fpga.ethernet.volume.time.sleep'):
                reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            status=read_json(case/'handoff/inference_status.json')
            self.assertEqual(status['hardware']['diagnostic_version'],4)
            self.assertEqual(status['volume_cycles'],dict(fetch=5|1<<32,operator=6|2<<32,
                gather=70|3<<32,classify=9|4<<32,kind4=0x1289abcdef))
            self.assertEqual(status['hardware']['gather_response_wait_cycles'],4|5<<32)
            self.assertEqual(status['hardware']['gather_read_requests'],120|6<<32)
            self.assertEqual(status['hardware']['gather_write_requests'],64|7<<32)
            self.assertEqual(status['hardware']['gather_response_count'],184|8<<32)

    def test_transposed_views_gather_identically_to_source_orientation(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp))
            compact=job['compact_bin'];views={v['name']:v for v in compact['views']}
            blob=(case/compact['file']).read_bytes()
            # 视图不得与 0x1E000000..0x20000000 的 skip 兼容区相交，且不超过 RTL 视图上限。
            self.assertTrue(all(v['base']%32==0 and v['base']+v['bytes']<=0x30000000 and
                                (v['base']+v['bytes']<=0x1E000000 or v['base']>=0x20000000) for v in compact['views']))
            for name in ('lobe_t','native_t'):
                derived=views[name];source=views[derived['source']]
                for z in range(source['planes']):
                    src=np.frombuffer(blob,np.uint8,source['plane_stride'],source['file_offset']+z*source['plane_stride'])
                    dst=np.frombuffer(blob,np.uint8,derived['plane_stride'],derived['file_offset']+z*derived['plane_stride'])
                    np.testing.assert_array_equal(
                        hardware_gather(dst,derived['row_stride'],derived['width'],derived['height'],0),
                        hardware_gather(src,source['row_stride'],source['width'],source['height'],derived['orientation']))

    def test_no_transpose_keeps_original_orientation_commands(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);create_ct(root/'dicom');prepare(root/'dicom',root/'case')
            job=make_job(root/'case',0x00400000,1,transpose=False)
            self.assertEqual([v['name'] for v in job['compact_bin']['views']],['native','lobe'])
            program,*_=build_program(job,read_json(root/'case/input/metadata.json'))
            orientations=[program[o+33]&3 for o in range(0,len(program)-96,96) if program[o]==4]
            self.assertEqual(orientations,[2,2,1,1,0,0,1,1])

    def test_failed_busy_identity_and_invalid_labels_never_publish(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));size=job['result_contract']['bytes']
            for state,identity in ((3,123),(2,124)):
                client=Mock();client.rpc.return_value=dict(state=state,run_id=identity,bytes=size,mac_bytes=2)
                with self.assertRaises(RuntimeError):
                    reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
                self.assertFalse((case/'handoff/result_ready.json').exists())
            client=Mock();client.rpc.return_value=dict(state=2,run_id=123,bytes=size,mac_bytes=4)
            manifest=reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            for payload in (bytes(8),b'\xff'*size):
                client.read.return_value=payload
                with self.assertRaises(ValueError):
                    receive_result(case,manifest,'host',8080,'bind',client_factory=lambda *a,**kw:client)
                self.assertFalse((case/'prediction/metadata.json').exists())

    def test_stalled_command_reports_before_total_timeout_and_preserves_board(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));client=Mock()
            client.rpc.return_value=dict(state=1,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=2,
                data=struct.pack('<4I',0x31474456,100,112,8 | (7 << 4) | 512 | 2048))
            with patch('pc_fpga.ethernet.volume.time.sleep'), patch('pc_fpga.ethernet.volume.time.monotonic',side_effect=[0.,0.,60.,121.]):
                with self.assertRaisesRegex(TimeoutError,'进度连续 120s 未变化'):
                    reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            status=read_json(case/'handoff/inference_status.json')
            self.assertEqual(status['completed_commands'],2)
            self.assertEqual(status['current_command'],dict(model='lobe',slice=0,stage='e1.mix',opcode=11))
            self.assertEqual(status['no_progress_seconds'],121.)
            self.assertEqual(status['status'],'failed')
            self.assertEqual(status['hardware'],dict(engine_state=8,scheduler_state=7,input_words=112,output_words=100,
                read_idle=False,memory_pending=True,core_done=False,core_reset_n=True))
            self.assertEqual([c.args[0] for c in client.rpc.call_args_list],[START,QUERY,QUERY])
            self.assertFalse((case/'handoff/result_ready.json').exists())

    def test_live_hardware_counts_prevent_false_stall_for_long_command(self):
        with tempfile.TemporaryDirectory() as temp:
            case,job,*_=self.fixture(Path(temp));client=Mock()
            client.rpc.side_effect=[dict(state=state,run_id=123,bytes=job['result_contract']['bytes'],mac_bytes=count,
                data=struct.pack('<4I',0x31474456,words,words,8|2048))
                for state,count,words in ((1,2,16),(1,2,32),(1,2,48),(2,4,48))]
            with patch('pc_fpga.ethernet.volume.time.sleep'), patch('pc_fpga.ethernet.volume.time.monotonic',
                    side_effect=[0.,0.,121.,242.,363.,364.]):
                manifest=reason_volume(case,'host',8080,'bind',client_factory=lambda *a,**kw:client)
            self.assertTrue(manifest.exists())
            self.assertEqual(read_json(case/'handoff/inference_status.json')['hardware']['input_words'],48)


if __name__=='__main__':unittest.main(verbosity=2)
