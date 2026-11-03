"""Offline integration checks for scheduling, BIN layout and unchanged CT/STL."""

import io
import json
from pathlib import Path
import struct
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stdout
from unittest.mock import Mock, patch

import numpy as np

from src.fullnet import (NetworkPlan, coefficient_image, decode_logits, classify,
                        pack_input, prepare_session, run_plane, TASKS, ROOT)
from src.ct_pipeline import (check_copied_sources, prepare_sample, native_plane, infer)
from src.io.prediction_io import write_packed_prediction, read_prediction, file_sha256
from src.io.preprocess import write_int8_input
from src.volume_bin import quantize_hu
from src.op_client import RELEASE
from src.protocol import (build_frame, parse_frame, build_ack_body, parse_image_begin,
                          check_fpga_requirements, MSG_ACK, MSG_IMAGE_BEGIN, MSG_TRANSFER_ABORT)


class CTPipelineChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        image = coefficient_image()
        cls.plans = {name: NetworkPlan(name,image,fuse_dw_add=False) for name,*_ in TASKS}
        cls.fused_plans = {name: NetworkPlan(name,image,fuse_up_concat=False) for name,*_ in TASKS}

    def test_fused_descriptors_preserve_frozen_operations_and_live_tensors(self):
        for task, plan in self.fused_plans.items():
            legacy = {s["name"]: s for s in self.plans[task].stages}
            self.assertEqual(len(plan.stages),45)
            self.assertEqual(sum(s["op"]==11 for s in plan.stages),7)
            self.assertFalse(any(s["op"] in (8,9) for s in plan.stages))
            for index,stage in enumerate(plan.stages):
                actual = bytearray(stage["descriptor"])
                expected = bytearray(legacy[stage["name"]]["descriptor"])
                if stage["op"]==11:
                    block = stage["name"].rsplit(".",1)[0]
                    dw3,dw5 = (legacy[block+"."+dw]["descriptor"] for dw in ("dw3","dw5"))
                    # 其余配置必须与已验证的 mix 相同；两路权重地址来自旧 DW 描述符。
                    expected[0]=11
                    expected[28:32]=dw5[32:36]
                    expected[32:36]=dw3[32:36]
                    self.assertEqual(stage["reads"],[block+".expand"])
                    self.assertEqual(struct.unpack_from("<I",actual,16)[0],plan.tensors[block+".expand"]["address"])
                    self.assertEqual((stage["format"],stage["bytes"]),(0,legacy[stage["name"]]["bytes"]))
                for start,end in ((16,28),(48,52)):
                    actual[start:end]=expected[start:end]=bytes(end-start)
                self.assertEqual(actual,expected,(task,stage["name"]))
                live = [t for t in plan.tensors.values() if t["produced"]<=index<=t["last"]]
                for i,a in enumerate(live):
                    self.assertEqual(a["address"]%32,0)
                    for b in live[i+1:]:
                        self.assertFalse(a["address"]<b["address"]+b["bytes"] and
                                         b["address"]<a["address"]+a["bytes"],(task,index))
            self.assertLessEqual(plan.arena_end,self.plans[task].arena_end)

    def test_original_ct_stl_sources_are_byte_identical(self):
        self.assertEqual(check_copied_sources(),16)

    @unittest.skipUnless((ROOT/"sim/xsim/tests/fullnet/vessel/512x512/vectors/tasks.txt").exists(),
                         "未随仓库提供 fullnet 512x512 冻结向量")
    def test_descriptors_match_verified_vessel512_except_addresses_identity(self):
        root = ROOT/"sim/xsim/tests/fullnet/vessel/512x512/vectors"
        for stage, line in zip(self.plans["vessel"].stages,(root/"tasks.txt").read_text().splitlines()):
            name,size,descriptor_file,_ = line.split()
            self.assertEqual(stage["name"],name.split("_",1)[1])
            expected = bytearray.fromhex((root/descriptor_file).read_text())
            # 冻结向量的普通INT16头为P4；本版仅将其外部存储粒度改成P8。
            expected_size = int(size)
            if expected[0] == 1 and expected[1] & 8 and not expected[1] & 6:
                width,height = struct.unpack_from("<HH",expected,4)
                cout = struct.unpack_from("<H",expected,54)[0] or expected[3]
                expected_size = ((cout+7)//8)*width*height*16
            self.assertEqual(stage["bytes"],expected_size)
            actual = bytearray(stage["descriptor"])
            for start,end in ((16,32),(48,52)):
                expected[start:end] = actual[start:end] = bytes(end-start)
            self.assertEqual(actual,expected,name)

    def test_lifetimes_skips_ranges_and_tumor_extended_channels(self):
        for plan in self.plans.values():
            self.assertEqual(len(plan.stages),59)
            self.assertLessEqual(plan.arena_end,0x20000000)
            for index,stage in enumerate(plan.stages):
                live = [(n,t) for n,t in plan.tensors.items() if t["produced"]<=index<=t["last"]]
                for i,(name,a) in enumerate(live):
                    self.assertEqual(a["address"]%32,0)
                    for other,b in live[i+1:]:
                        self.assertFalse(a["address"]<b["address"]+b["bytes"] and b["address"]<a["address"]+a["bytes"],(plan.task,index,name,other))
            self.assertEqual(plan.tensors["e1.out"]["last"],50)
            self.assertEqual(plan.tensors["e2.out"]["last"],41)
            self.assertEqual(plan.tensors["e3.out"]["last"],32)
        d = next(s["descriptor"] for s in self.plans["tumor"].stages if s["name"]=="d3.expand")
        self.assertEqual(struct.unpack_from("<HH",d,52),(768,256))
        self.assertEqual(len(self.plans["tumor"].parameters),1457216)

    def test_quantization_exactly_matches_original_preprocessor(self):
        hu = np.array([-2000,-1024,-1023,-1000,-500,0,400,999,1000,1500],np.float32)[None,None,:]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/"neighbors.bin"
            write_int8_input(hu,path,-1024.,1000.)
            original = np.fromfile(path,np.int8).reshape(1,3,1,-1)[:,1]
            np.testing.assert_array_equal(quantize_hu(hu),original)

    def test_orientation_repeat_edges_padding_and_inverse(self):
        centers = np.arange(3*5*7,dtype=np.int8).reshape(3,5,7)
        for orientation in ("native","transpose","nifti-ras"):
            for direction in (-1,1):
                for index in (0,1,2):
                    sample = prepare_sample(centers,index,orientation,direction)
                    logit = np.where(sample[1]>40,10,-10).astype(np.int16)[None]
                    np.testing.assert_array_equal(native_plane(logit,orientation,centers.shape),centers[index]>40)
                    # Spatial transforms never reorder channels; inferior/superior
                    # reversal applies only to the lobe neighbor addresses.
                    a = sample[0].sum(dtype=np.int64)
                    b = sample[2].sum(dtype=np.int64)
                    if index==1:
                        self.assertEqual(np.sign(b-a),direction if orientation=="nifti-ras" else 1)

    def test_signed_p8_logits_tail_padding_zero_threshold_ties_and_uint16(self):
        values = np.array([[[-1,0,9]], [[-2,0,9]], [[-3,-1,1]], [[-4,-2,2]], [[-5,0,12]]],np.int16)
        side = 8
        padded = np.full((8,side,side),-32768,np.int16)
        padded[:5,:1,:3] = values
        wire = padded.reshape(1,8,side,side).transpose(0,2,3,1).astype("<i2").tobytes()
        logits = decode_logits(wire,5,side)
        self.assertEqual(classify(logits)[0,:3].tolist(),[0,1,5])
        packed = np.zeros((2,side,side),np.uint16)
        packed[:,0,1] = (1<<0)|(1<<5)|(1<<6)|(1<<8)
        with tempfile.TemporaryDirectory() as folder:
            write_packed_prediction(folder,packed,np.eye(4),{})
            actual,meta = read_prediction(folder)
            np.testing.assert_array_equal(actual,packed)
            self.assertEqual(meta["dtype"],"uint16")
            self.assertEqual((Path(folder)/meta["file"]).read_bytes()[2:4],b"\x61\x01")
            del actual

    def test_p8_logits_channel_group_boundary_and_wire_length(self):
        for channels in (1,5,8,9,16,17):
            side = 3
            values = (np.arange(channels*side*side)-70).astype(np.int16).reshape(channels,side,side)
            padded = np.full(((channels+7)//8*8,side,side),-32768,np.int16)
            padded[:channels] = values
            wire = padded.reshape(-1,8,side,side).transpose(0,2,3,1).astype("<i2").tobytes()
            np.testing.assert_array_equal(decode_logits(wire,channels,side),values)
            with self.assertRaises(ValueError):
                decode_logits(wire[:-2],channels,side)

    def test_runner_reads_only_head_releases_every_stage_and_preserves_failure(self):
        sample = np.zeros((3,512,512),np.int8)
        for plan,failed in ((p,f) for p in (self.plans["vessel"],self.fused_plans["vessel"]) for f in (None,3)):
            client = Mock()
            index = -1
            def run(desc):
                nonlocal index
                index += 1
                self.assertEqual(desc[:48],plan.stages[index]["descriptor"][:48])
                return struct.unpack_from("<I",desc,48)[0]
            def wait(identity,timeout):
                s = plan.stages[index]
                return dict(op=s["op"],format=99 if index==failed else s["format"],bytes=s["bytes"],mac_bytes=0)
            client.run.side_effect=run
            client.wait.side_effect=wait
            client.read.return_value=bytes(plan.tensors["head"]["bytes"])
            record={}
            if failed is not None:
                with self.assertRaisesRegex(RuntimeError,"unexpected FPGA STATUS"):
                    run_plane(client,plan,sample,600,record)
                self.assertEqual(index,failed)
                self.assertEqual(client.rpc.call_count,failed)
                self.assertEqual(record["active_stage"],plan.stages[failed]["name"])
                client.read.assert_not_called()
            else:
                logits=run_plane(client,plan,sample,600,record)
                self.assertEqual(logits.shape,(2,512,512))
                self.assertEqual(client.rpc.call_count,len(plan.stages))
                self.assertTrue(all(c.args[0]==RELEASE for c in client.rpc.call_args_list))
                client.read.assert_called_once()
                self.assertEqual(len(record["completed_stages"]),len(plan.stages))
                self.assertEqual([s["op"] for s in record["completed_stages"]],[s["op"] for s in plan.stages])
                for saved,stage in zip(record["completed_stages"],plan.stages):
                    self.assertEqual(bytes.fromhex(saved["descriptor_hex"])[:48],stage["descriptor"][:48])
            client.upload.assert_called_once_with(plan.tensors["input"]["address"],pack_input(sample))

    def test_session_matches_rtl_ack_sequence_wrap_and_preserves_held_run(self):
        for sequence in (0,0xfffffffe):
            client = Mock(sequence=sequence,retries=1,peer=("127.0.0.1",8080))
            client.rpc.return_value = dict(state=0)
            client.socket.gettimeout.return_value = .1
            sent=[]
            def send(packet,peer):
                frame = parse_frame(packet)
                sent.append(frame)
                if frame.msg_type == MSG_IMAGE_BEGIN:
                    self.assertIsNone(check_fpga_requirements(parse_image_begin(frame.body)))
                    ack = build_ack_body(MSG_IMAGE_BEGIN,0,acked_sequence=frame.sequence)
                    reply = build_frame(MSG_ACK,frame.transfer_id,(frame.sequence+1)&0xffffffff,ack)
                    client.socket.recvfrom.return_value = (reply,peer)
            client.socket.sendto.side_effect = send
            prepare_session(client)
            self.assertEqual([f.msg_type for f in sent],[MSG_IMAGE_BEGIN,MSG_TRANSFER_ABORT])
            self.assertEqual(sent[0].transfer_id,sent[1].transfer_id)
        client = Mock()
        client.rpc.return_value = dict(state=2,run_id=123)
        with self.assertRaisesRegex(RuntimeError,"holds run"):
            prepare_session(client)
        client.socket.sendto.assert_not_called()

    def test_full_volume_failure_resume_and_final_uint16_publication(self):
        with tempfile.TemporaryDirectory() as folder, redirect_stdout(io.StringIO()):
            root = Path(folder)
            (root/"input").mkdir()
            volume = np.zeros((3,512,512),np.int8)
            path = root/"input/ct_volume_int8.bin"
            volume.tofile(path)
            metadata = dict(shape_z_y_x=list(volume.shape),anatomical_z_direction=1,
                affine_z_y_x_to_lps_mm=[[0,0,1,0],[0,1,0,0],[1,0,0,0],[0,0,0,1]],
                model_input=dict(dtype="int8",layout="Z,Y,X",shape=list(volume.shape),
                                 hu_clip=[-1024.,1000.],sha256=file_sha256(path)))
            (root/"input/metadata.json").write_text(json.dumps(metadata),encoding="utf-8")
            args = Namespace(case_dir=root,run_timeout=600,host="127.0.0.1",port=8080,bind="127.0.0.1")
            client = Mock()
            calls=[]
            def fake_plane(client,plan,sample,timeout,record):
                calls.append((plan.task,record["model_slice"]))
                record.update(upload_seconds=.001,run_wait_seconds=.002,download_seconds=.003,elapsed_seconds=.006)
                logits = np.full((plan.channels,512,512),-1,np.int16)
                logits[0]=0
                return logits
            def interrupted(*args):
                if len(calls)==1:
                    raise RuntimeError("injected transfer failure")
                return fake_plane(*args)
            with patch("src.ct_pipeline.connect",return_value=client), patch("src.ct_pipeline.run_plane",side_effect=interrupted):
                with self.assertRaisesRegex(RuntimeError,"injected"):
                    infer(args,self.plans)
            self.assertFalse((root/"prediction/metadata.json").exists())
            saved=json.loads((root/"prediction/progress/lobe.json").read_text())
            self.assertEqual(saved["completed"],1)
            calls.clear()
            with patch("src.ct_pipeline.connect",return_value=client), patch("src.ct_pipeline.run_plane",side_effect=fake_plane):
                infer(args,self.plans)
            self.assertEqual(calls[0],("lobe",1))
            prediction,contract=read_prediction(root/"prediction")
            self.assertTrue(np.all(prediction==353))  # bits 0,5,6,8, with cross-task overlap
            self.assertEqual(set(contract["provenance"]["tasks"]),{t[0] for t in TASKS})
            del prediction
            with patch("src.ct_pipeline.connect") as connect:
                infer(args,self.plans)
                connect.assert_not_called()
            # Export a complete lobe volume from existing checkpoints, without UDP
            # or publishing it as the complete four-model result.
            full_hash=file_sha256(root/"prediction/segmentation_uint16.bin")
            args.lobe_only=True
            with patch("src.ct_pipeline.connect") as connect, patch("src.ct_pipeline.run_plane") as run:
                infer(args,self.plans)
                connect.assert_not_called()
                run.assert_not_called()
            lobes,lobe_contract=read_prediction(root/"prediction_lobe")
            self.assertTrue(np.all(lobes==1))
            self.assertEqual(lobe_contract["provenance"]["inferred_tasks"],["lobe"])
            self.assertEqual(lobe_contract["provenance"]["not_inferred_tasks"],["airway","vessel","tumor"])
            self.assertEqual(file_sha256(root/"prediction/segmentation_uint16.bin"),full_hash)
            del lobes
            args.lobe_only=False
            metadata_path = root/"prediction/metadata.json"
            contract["provenance"]["tasks"]["vessel"]["export_sha256"] = "stale-weights"
            metadata_path.write_text(json.dumps(contract),encoding="utf-8")
            with patch("src.ct_pipeline.connect") as connect:
                with self.assertRaisesRegex(ValueError,"different run"):
                    infer(args,self.plans)
                connect.assert_not_called()


if __name__=="__main__":
    unittest.main()
