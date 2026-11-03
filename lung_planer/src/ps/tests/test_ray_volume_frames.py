"""Ray volume wire format, aggregate integrity and strict ownership checks."""
import io, json, os, struct, sys, types, unittest
from pathlib import Path
from unittest.mock import patch
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from cas_frontend.ray_mesh import pack_rays
from cas_frontend.ray_bvh import decode_results
from cas_frontend.pl_metrics import PlMetrics
from test_ray_crossing_frames import frame
from test_pl_metrics_recovery import Buffer,Dma
import test_strict_planner as strict_tests

def volume_frame(index=1,length=10<<16,fraction=1<<30,error=0):
    raw=bytearray(frame([20<<16],error=error))
    for offset,value in ((0,index),(32,fraction),(44,length),(48,int(not error))):
        struct.pack_into('<I',raw,offset,value)
    return bytes(raw)

class RayVolumeFrameTests(unittest.TestCase):
    def setUp(self):
        direct = patch('cas_frontend.pl_metrics.os.geteuid', return_value=0, create=True)
        direct.start(); self.addCleanup(direct.stop)

    def test_lengths_wire_quantization_and_rejection(self):
        raw=pack_rays([[0,0,0]]*2,[[0,0,1]]*2,lengths=[1.25,32767.])
        self.assertEqual(struct.unpack_from('<I',raw,28)[0],81920)
        self.assertEqual(struct.unpack_from('<I',raw,60)[0],32767<<16)
        self.assertEqual(struct.unpack_from('<I',pack_rays([[0,0,0]],[[0,0,1]]),28)[0],0)
        for lengths in ([],[0],[-1],[1e-9],[32768],[float('nan')]):
            with self.assertRaises((ValueError,OverflowError)):
                pack_rays([[0,0,0]],[[0,0,1]],lengths=lengths)

    def test_volume_decoder_rejects_corrupt_fields(self):
        good=volume_frame()
        self.assertEqual(decode_results(good,1,volume=True)[0]['volume_fraction'],1.)
        for offset,value in ((32,(1<<30)+1),(44,0),(48,0),(48,2)):
            raw=bytearray(good);struct.pack_into('<I',raw,offset,value)
            with self.assertRaises(ValueError):decode_results(raw,1,volume=True)
        self.assertFalse(decode_results(volume_frame(fraction=0,error=16),1,volume=True)[0]['volume_valid'])
        with self.assertRaises(ValueError):decode_results(volume_frame(error=16),1,volume=True)

    def test_wide_batch_sum_cache_mode_switch_and_corrupt_mean(self):
        client=PlMetrics();count=6
        output=b''.join(volume_frame(i+1) for i in range(count))
        class Mmio:
            def __init__(self):self.words={};self.bad=False
            def write(self,offset,value):self.words[offset]=value
            def read(self,offset):
                return {0x024:self.words.get(4,0),0x010:self.words.get(8,0),0x014:count,0x020:111,
                        0x018:0,0x06c:(count<<30)&0xffffffff,0x070:(count<<30)>>32,
                        0x074:count,0x078:(1<<30)-int(self.bad)}.get(offset,self.words.get(offset,0))
        def load():
            if client._overlay is not None:return
            client._overlay=types.SimpleNamespace(download=lambda:None)
            client._mesh_complete=client._mesh_metadata=client._mesh_ddr_mode=client._mesh_volume=True
            client._mesh_mmio=Mmio();client._mesh_ray_dma=Dma(True);client._mesh_result_dma=Dma(True,output)
        tri=np.array([[[-10,-10,0],[10,-10,0],[-10,10,0]]])
        with patch.dict(os.environ,{'LUNG_PL_ENABLE':'1'}),patch.object(client,'_load',side_effect=load),patch.dict(sys.modules,{'pynq':types.SimpleNamespace(allocate=lambda shape,dtype:Buffer(shape[0]))}):
            result=client.evaluate_mesh_rays(tri,[[0,0,20]]*count,[[0,0,-1]]*count,lengths=[10]*count)
            self.assertTrue(result['ok'],result);self.assertEqual(result['volume_sum_q30'],count<<30)
            self.assertEqual(client._mesh_mmio.words[0x03c],7)
            second=client.evaluate_mesh_rays(tri,[[0,0,20]]*count,[[0,0,-1]]*count)
            self.assertTrue(second['mesh_reused']);self.assertEqual(client._mesh_mmio.words[0x03c],3)
            client._mesh_mmio.bad=True
            with patch.object(client,'_reset_hardware_state') as reset:
                bad=client.evaluate_mesh_rays(tri,[[0,0,20]]*count,[[0,0,-1]]*count,lengths=[10]*count)
                self.assertFalse(bad['ok']);self.assertIn('mean disagree',bad['error']);reset.assert_called_once()
            client.close()

    def test_strict_volume_uses_pl_mean_and_requires_volume_abi(self):
        helper=strict_tests.StrictPlannerTests()
        seen=[]
        def evaluate(triangles,origins,directions,**kw):
            seen.append(kw['lengths']);return strict_tests.response(origins,kw['lengths'])
        case=helper.strict_case(evaluate)
        vertices=np.array([[0,0,2],[5,0,2],[0,5,2],[1,1,0]],float)
        with patch('cas_frontend.planning_geometry.volume_fraction',side_effect=AssertionError('CPU integral')),patch.object(case,'inside',side_effect=AssertionError('extra apex query')):
            total,removed=case.volume(vertices)
        self.assertEqual(removed,total*.5);self.assertEqual(len(seen),1);self.assertEqual(len(seen[0]),190)
        case._mesh_evaluator=lambda *a,**kw:strict_tests.response(a[1])
        with self.assertRaisesRegex(RuntimeError,'PL volume'):case.volume(vertices)

    def test_privileged_wire_preserves_lengths_and_volume_flag(self):
        from cas_frontend.pl_privileged import PrivilegedPlClient
        import base64
        client=PrivilegedPlClient('unused.bit')
        client.process=types.SimpleNamespace(stdin=io.BytesIO())
        tri=np.array([[[0,0,0],[1,0,0],[0,1,0]]])
        with patch.object(client,'_start'),patch.object(client,'_receive',return_value=dict(ok=True)):
            client.evaluate_mesh_rays(tri,[[0,0,1]],[[0,0,-1]],lengths=[3.25])
        request=json.loads(client.process.stdin.getvalue());self.assertTrue(request['volume'])
        self.assertEqual(struct.unpack_from('<I',base64.b64decode(request['rays']),28)[0],int(3.25*65536))

if __name__=='__main__':unittest.main()
