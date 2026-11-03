"""纯 PC 自校验：所有网络对端均为内存替身，不连接 FPGA。"""
import contextlib
import hashlib
import io
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import Mock, patch
import zlib

import numpy as np
from pydicom.dataset import FileDataset, FileMetaDataset
from pydicom.uid import ExplicitVRLittleEndian, CTImageStorage, generate_uid

from pc_fpga.ct.convert import prepare, make_job, quantize_hu
from pc_fpga.ct.prediction_io import CHANNELS, file_sha256, read_prediction, write_packed_prediction
from pc_fpga.ethernet import protocol as p
from pc_fpga.ethernet.op_client import OpClient, READ, WRITE
from pc_fpga.ethernet.sender import VolumeSender, SenderConfig, TransferError
from pc_fpga.ethernet.transfer import receive_volume, validate_result_manifest
from pc_fpga.files import read_json, write_json
from pc_fpga.mesh.stages import bin_to_stl, process_meshes, read_stl
from pc_fpga.mesh.reference import mesh_quality
from main import main, demo_prediction


def create_ct(directory):
    directory.mkdir()
    uid = generate_uid()
    for index in (1,0):
        meta = FileMetaDataset()
        meta.TransferSyntaxUID = ExplicitVRLittleEndian
        meta.MediaStorageSOPClassUID = CTImageStorage
        meta.MediaStorageSOPInstanceUID = generate_uid()
        ds = FileDataset(str(directory/f'{1-index}.dcm'), {}, file_meta=meta, preamble=bytes(128))
        ds.Modality, ds.SeriesInstanceUID = 'CT', uid
        ds.SOPClassUID, ds.SOPInstanceUID = meta.MediaStorageSOPClassUID, meta.MediaStorageSOPInstanceUID
        ds.Rows = ds.Columns = 512
        ds.ImageOrientationPatient = [1,0,0,0,1,0]
        ds.ImagePositionPatient, ds.PixelSpacing = [10,20,index*2.], [.8,.8]
        ds.SamplesPerPixel, ds.PhotometricInterpretation = 1, 'MONOCHROME2'
        ds.BitsAllocated, ds.BitsStored, ds.HighBit, ds.PixelRepresentation = 16,16,15,1
        ds.RescaleSlope, ds.RescaleIntercept = 2,-1024
        ds.PixelData = np.full((512,512),index*400,dtype='<i2').tobytes()
        ds.save_as(ds.filename,enforce_file_format=True)


class MemoryLink:
    """真实 V1 帧交互，首批故意丢一个包，验证缺包位图重传。"""
    peer = ('127.0.0.1',45678)
    def __init__(self, corrupt_ready=False):
        self.queue, self.packets, self.frames = [], {}, []
        self.dropped, self.corrupt_ready = False, corrupt_ready

    def sendto(self, data, peer):
        assert peer == self.peer
        f = p.parse_frame(data)
        self.frames.append(f)
        body, message = None, None
        if f.msg_type == p.MSG_IMAGE_BEGIN:
            self.begin = p.parse_image_begin(f.body)
            message, body = p.MSG_ACK,p.build_ack_body(p.MSG_IMAGE_BEGIN,0,acked_sequence=f.sequence)
        elif f.msg_type == p.MSG_IMAGE_DATA:
            z,packet,_,payload = p.parse_image_data_body(f.body)
            if not self.dropped and (z,packet) == (0,7):
                self.dropped = True
            else:
                self.packets[z,packet] = payload
        elif f.msg_type == p.MSG_BATCH_END:
            bid,first,count,expected,crc = p.parse_batch_end_body(f.body)
            missing = [i for i in range(expected) if (first+i//256,i%256) not in self.packets]
            if not missing:
                payload = b''.join(self.packets[z,i] for z in range(first,first+count) for i in range(256))
                assert zlib.crc32(payload) == crc
            body = p.build_batch_status_body(bid,p.BATCH_MISSING if missing else p.BATCH_COMPLETE,
                                            expected,expected-len(missing),p.missing_to_bitmap(missing,expected) if missing else None)
            message = p.MSG_BATCH_STATUS
        elif f.msg_type == p.MSG_IMAGE_END:
            payload = b''.join(self.packets[z,i] for z in range(self.begin.total_slices) for i in range(256))
            crc = zlib.crc32(payload) ^ int(self.corrupt_ready)
            message,body = p.MSG_IMAGE_READY,p.build_image_ready_body(0,self.begin.total_slices,
                self.begin.expected_packets,len(payload),crc,self.begin.image_base_addr)
        if message is not None:
            frame = p.build_frame(message,f.transfer_id,f.sequence+1,body)
            self.queue.extend([(frame,('127.0.0.2',45678)),(frame,self.peer)])

    def recvfrom(self, timeout):
        return self.queue.pop(0) if self.queue else None


class PipelineChecks(unittest.TestCase):
    def test_ct_zip_geometry_quantization_and_job(self):
        import zipfile
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            create_ct(root/'dicom')
            with zipfile.ZipFile(root/'ct.zip','w') as archive:
                for f in (root/'dicom').glob('*.dcm'):
                    archive.write(f,f'nested/{f.name}')
            case = root/'case'
            metadata = prepare(root/'ct.zip',case)
            actual = np.fromfile(case/'input/ct_volume_int8.bin',np.int8).reshape(2,512,512)
            np.testing.assert_array_equal(actual[:,0,0],quantize_hu(np.array([-1024,-224],np.float32)))
            self.assertEqual(metadata['affine_z_y_x_to_lps_mm'],[[0.,0.,.8,10.],[0.,.8,0.,20.],[2.,0.,0.,0.],[0.,0.,0.,1.]])
            job = make_job(case,0x00400000,1)
            self.assertEqual(job['result_contract']['bytes'],2*512*512*2)
            self.assertEqual(job['compact_bin']['views'][0]['base'],0x00400000)
            self.assertEqual(job['compact_bin']['views'][0]['row_stride'],512)
            self.assertEqual(job['compact_bin']['views'][1]['row_stride'] % 32,0)
            container=(case/job['compact_bin']['file']).read_bytes()
            views=job['compact_bin']['views']
            self.assertEqual([v['name'] for v in views],['native','lobe','lobe_t','native_t'])
            self.assertEqual(struct.unpack_from('<4sHHII',container),(b'VOL2',2,len(views),2,16+40*len(views)))
            native=struct.unpack_from('<8sBBHIIIIHHII',container,16)
            self.assertEqual(native[0],b'native\0\0')
            self.assertEqual(native[8:],(512,512,512,512*512))
            self.assertEqual(prepare(root/'ct.zip',case),metadata)
            with self.assertRaises(ValueError):
                make_job(case,0x1ffff000,1)
            with self.assertRaises(ValueError):
                make_job(case,0x10000000,1)

    def test_v1_upload_loss_retransmit_ready_crc_and_peer_filter(self):
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'input.bin'
            payload=np.arange(2*512*512,dtype=np.int32).astype(np.int8).tobytes()
            path.write_bytes(payload)
            begin=p.ImageBegin(total_slices=2,total_bytes=len(payload),expected_packets=512,
                               whole_crc32=zlib.crc32(payload),image_base_addr=0x10000000,batch_slices=2)
            for corrupt in (False,True):
                link=MemoryLink(corrupt)
                sender=VolumeSender(link,link.peer,path,begin,123,SenderConfig())
                if corrupt:
                    with self.assertRaisesRegex(TransferError,'metadata/CRC'):
                        sender.run()
                else:
                    result=sender.run()
                    self.assertEqual(result['retransmitted'],1)
                    self.assertGreater(result['rx_stray'],0)
                    self.assertEqual(result['ready']['received_bytes'],len(payload))
                    repeats=[f for f in link.frames if f.msg_type==p.MSG_IMAGE_DATA and p.parse_image_data_body(f.body)[:2]==(0,7)]
                    self.assertEqual(repeats[0],repeats[1])
                self.assertFalse(any(f.msg_type==p.MSG_INFER_TRIGGER for f in link.frames))

    def test_existing_rpc_framing_and_little_endian_read_write(self):
        class Socket:
            def bind(self,addr): pass
            def settimeout(self,value): self.timeout=value
            def gettimeout(self): return self.timeout
            def close(self): pass
            def sendto(self,packet,peer):
                self.sent = p.parse_frame(packet)
                f=self.sent
                data=b'\x80\xff'*16 if f.msg_type==READ else b''
                self.reply=p.build_frame(f.msg_type|0x80,f.transfer_id,f.sequence,
                                        struct.pack('<BBBBIII',0,0,0,0,f.transfer_id,0,0)+data)
                self.peer=peer
            def recvfrom(self,size): return self.reply,self.peer
        sock=Socket()
        with patch('pc_fpga.ethernet.op_client.socket.socket',return_value=sock):
            client=OpClient('127.0.0.1')
            client.upload(0x10000000,b'abc')
            self.assertEqual(sock.sent.msg_type,WRITE)
            self.assertEqual(struct.unpack_from('<IHH',sock.sent.body),(0x10000000,32,0))
            self.assertEqual(client.read(0,0x18000000,3,diagnostic=True),b'\x80\xff\x80')
            self.assertEqual(struct.unpack('<IHH',sock.sent.body),(0x18000000,32,1))
            client.close()

    def test_upload_uses_four_sequenced_frames_in_flight(self):
        class Socket:
            def __init__(self):
                self.timeout=1.;self.frames=[];self.replies=[];self.outstanding=set();self.max_outstanding=0
            def bind(self,addr): pass
            def settimeout(self,value): self.timeout=value
            def gettimeout(self): return self.timeout
            def close(self): pass
            def sendto(self,packet,peer):
                frame=p.parse_frame(packet);self.frames.append(frame);self.outstanding.add(frame.sequence)
                self.max_outstanding=max(self.max_outstanding,len(self.outstanding))
                body=struct.pack('<BBBBIII',0,0,0,0,0,0,0)
                self.replies.append((p.build_frame(frame.msg_type|0x80,frame.transfer_id,frame.sequence,body),peer))
            def recvfrom(self,size):
                reply=self.replies.pop() if len(self.frames)>=2 and self.replies else self.replies.pop(0)
                frame=p.parse_frame(reply[0]);self.outstanding.discard(frame.sequence)
                return reply
        sock=Socket();payload=bytes((i&255 for i in range(4096)))
        with patch('pc_fpga.ethernet.op_client.socket.socket',return_value=sock):
            client=OpClient('127.0.0.1')
            client.upload(0x10000000,payload,block_size=8*1024)
            client.close()
        self.assertEqual(sock.max_outstanding,4)
        self.assertEqual([struct.unpack_from('<IHH',f.body)[:2] for f in sock.frames],
                         [(0x10000000+i*1024,1024) for i in range(4)])
        self.assertEqual(len({f.sequence for f in sock.frames}),4)

    def test_read_pipelines_four_requests_and_reorders_replies(self):
        class Socket:
            def __init__(self):
                self.timeout=1.;self.frames=[];self.replies=[];self.outstanding=set();self.max_outstanding=0
            def bind(self,addr): pass
            def settimeout(self,value): self.timeout=value
            def gettimeout(self): return self.timeout
            def close(self): pass
            def sendto(self,packet,peer):
                frame=p.parse_frame(packet);self.frames.append(frame);self.outstanding.add(frame.sequence)
                self.max_outstanding=max(self.max_outstanding,len(self.outstanding))
                address,count,_=struct.unpack_from('<IHH',frame.body)
                data=bytes(((address+i)>>5)&255 for i in range(count))
                body=struct.pack('<BBBBIII',0,2,0,0,frame.transfer_id,count,0)+data
                self.replies.append((p.build_frame(frame.msg_type|0x80,frame.transfer_id,frame.sequence,body),peer))
            def recvfrom(self,size):
                reply=self.replies.pop()   # 后发先回：验证按序号重组
                self.outstanding.discard(p.parse_frame(reply[0]).sequence)
                return reply
        sock=Socket()
        with patch('pc_fpga.ethernet.op_client.socket.socket',return_value=sock):
            client=OpClient('127.0.0.1')
            data=client.read(0x1234,0x10000000,6*1024+64)
            client.close()
        self.assertEqual(sock.max_outstanding,4)
        self.assertEqual(len(sock.frames),7)
        self.assertEqual(data,bytes(((0x10000000+i)>>5)&255 for i in range(6*1024+64)))
        self.assertEqual(client.read.__func__.__name__,'read')

    def result_fixture(self,root):
        create_ct(root/'dicom')
        prepare(root/'dicom',root/'case')
        job=make_job(root/'case',0x00400000,1)
        labels=np.zeros((2,512,512),dtype='<u2')
        labels[:,100:200,100:200]=1|32|64|256
        data=labels.tobytes()
        ready=dict(format='pc-fpga-result-ready-v1',state='complete',input_sha256=job['input']['sha256'],
                   tasks=job['models'],result={**job['result_contract'],'ddr_base':0x18000000,'sha256':hashlib.sha256(data).hexdigest()})
        path=root/'ready.json';write_json(path,ready)
        return root/'case',path,ready,data

    def test_receive_exact_result_identity_and_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            case,path,ready,data=self.result_fixture(Path(temp))
            client=Mock()
            client.rpc.return_value={'state':0}
            client.read.side_effect=lambda identity,address,size,diagnostic: data[address-0x18000000:address-0x18000000+size]
            receive_volume(case,path,'127.0.0.1',8080,'127.0.0.1',client_factory=lambda *a,**kw:client)
            prediction,metadata=read_prediction(case/'prediction')
            self.assertEqual(metadata['sha256'],ready['result']['sha256'])
            self.assertEqual(int(prediction[0,150,150]),353)
            client.close.assert_called_once()
            self.assertTrue(all(call.kwargs['diagnostic'] for call in client.read.call_args_list))
            del prediction
            ready['result']['bytes']//=2;write_json(path,ready)
            with self.assertRaisesRegex(ValueError,'bytes'):
                validate_result_manifest(case,path)

    def test_corrupt_result_and_busy_board_never_publish_prediction(self):
        with tempfile.TemporaryDirectory() as temp:
            case,path,ready,data=self.result_fixture(Path(temp))
            for state in (1,0):
                client=Mock();client.rpc.return_value={'state':state}
                client.read.side_effect=lambda identity,address,size,diagnostic: bytes(size)
                with self.assertRaises((ValueError,RuntimeError)):
                    receive_volume(case,path,'127.0.0.1',8080,'127.0.0.1',client_factory=lambda *a,**kw:client)
                self.assertFalse((case/'prediction/metadata.json').exists())
                client.close.assert_called_once()

    def test_bin_stl_smooth_cut_geometry_topology_and_original_immutable(self):
        with tempfile.TemporaryDirectory() as temp:
            case=Path(temp);demo_prediction(case)
            original=file_sha256(case/'prediction/segmentation_uint16.bin')
            bin_to_stl(case/'prediction',case/'raw')
            process_meshes(case/'raw',case/'smooth','Smooth')
            result=process_meshes(case/'smooth',case/'cut','Cut',max_faces=500)
            self.assertEqual(len(result['objects']),9)
            for entry in result['objects']:
                quality=mesh_quality(read_stl(case/'cut'/entry['file']))
                self.assertEqual(quality['boundary_nonmanifold_edges'],0)
                self.assertEqual(quality['surface_components'],1)
                self.assertLessEqual(entry['triangles'],500)
                self.assertLessEqual(abs(entry['volume_change_percent']),5.)
            self.assertEqual(file_sha256(case/'prediction/segmentation_uint16.bin'),original)
            self.assertEqual({e['category'] for e in result['objects']},{'lobes','airway','vessels','tumor'})

    def test_main_all_runs_upload_start_receive_and_mesh_in_order(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);create_ct(root/'dicom')
            calls=[]
            def record(name, result=None):
                def run(*args,**kwargs):
                    calls.append(name)
                    return result
                return run
            with patch('socket.socket',side_effect=AssertionError('Network forbidden')),contextlib.redirect_stdout(io.StringIO()), \
                 patch('pc_fpga.ethernet.transfer.send_volume',side_effect=record('upload',{})), \
                 patch('pc_fpga.ethernet.volume.upload_program',side_effect=record('program',{})), \
                 patch('pc_fpga.ethernet.volume.reason_volume',side_effect=record('start_wait',root/'ready.json')), \
                 patch('pc_fpga.ethernet.volume.receive_result',side_effect=record('receive',{})), \
                 patch('pc_fpga.mesh.stages.bin_to_stl',side_effect=record('stl',{})), \
                 patch('pc_fpga.mesh.stages.process_meshes',side_effect=record('postprocess',{})):
                write_json(root/'ready.json',{'format':'pc-fpga-result-ready-v2'})
                code=main(['--data-dir',str(root/'dicom'),'--case-dir',str(root/'case'),'--plain'])
            self.assertEqual(code,0,read_json(root/'case/run_report.json'))
            self.assertEqual(calls,['upload','program','start_wait','receive','stl','postprocess','postprocess'])
            self.assertEqual(read_json(root/'case/run_report.json')['status'],'complete')
            self.assertTrue(read_json(root/'case/run_report.json')['hardware_used'])


if __name__=='__main__':
    unittest.main(verbosity=2)
