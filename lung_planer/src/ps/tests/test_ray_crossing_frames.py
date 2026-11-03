import struct,sys,unittest,types,os
from pathlib import Path
from unittest.mock import patch
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from cas_frontend.ray_bvh import decode_results,RESULT_BYTES
from cas_frontend.pl_metrics import PlMetrics
from test_pl_metrics_recovery import Buffer,Dma

def frame(hits,raw=None,error=0):
    inside=len(hits)%2
    words=[1,error,len(hits) if raw is None else raw,len(hits),(0 if inside else hits[0]) if hits else 0x7fffffff,hits[-1] if hits else 0,inside,(len(hits)+1)//2,0,1,0,0,0,0,0,0]+hits+[0]*(128-len(hits))
    return struct.pack('<144I',*words)
class RayCrossingFrameTests(unittest.TestCase):
    def setUp(self):
        direct = patch('cas_frontend.pl_metrics.os.geteuid', return_value=0, create=True)
        direct.start(); self.addCleanup(direct.stop)

    def test_union_frame_diagnostic_counters(self):
        words=[1,0,4,2,10,30,0,1,0,0,0,0,0,4,2,2]+[10,30]+[0]*126
        item=decode_results(struct.pack('<144I',*words),1,union=True)[0]
        self.assertEqual(item['raw_hit_count'],4)
        self.assertEqual(item['event_count'],4)
        self.assertEqual(item['union_boundary_count'],2)
        self.assertEqual(item['solid_count'],2)
        self.assertEqual(decode_results(struct.pack('<144I',*words),1,union=True,
                                        expected_solid_count=2)[0]['solid_count'],2)
        with self.assertRaisesRegex(ValueError,'solid count'):
            decode_results(struct.pack('<144I',*words),1,union=True,
                           expected_solid_count=11)

    def test_nonconvex_and_inside_intervals(self):
        item=decode_results(frame([2,5,7,10]),1)[0]
        self.assertEqual(item['intervals_q16'],[[2,5],[7,10]])
        self.assertFalse(item['inside'])
        item=decode_results(frame([2,4,6]),1)[0]
        self.assertEqual(item['intervals_q16'],[[0,2],[4,6]])
        self.assertTrue(item['inside'])
    def test_corrupt_count_order_and_parity(self):
        with self.assertRaises(ValueError):decode_results(frame([2,2]),1)
        bad=bytearray(frame([2,5]));struct.pack_into('<I',bad,12,129)
        with self.assertRaises(ValueError):decode_results(bad,1)
        with self.assertRaises(ValueError):decode_results(bytes(16),1)
    def test_overflow_payload_keeps_error(self):
        item=decode_results(frame([20],raw=129,error=32),1)[0]
        self.assertEqual(item['hit_count'],129);self.assertEqual(item['errors'],32)
    def test_planning_complete_crossings_and_failed_cpu_result(self):
        from test_planning_geometry_ray import make_mesh_case
        case=make_mesh_case(lambda *args:dict(ok=True,complete_crossings=True,results=[dict(errors=0,hit_count=4,crossings_q16=[1<<16,2<<16,3<<16,4<<16])]))
        case._ray_mode='bvh_pl'
        self.assertEqual(case.hits([.25,.25,0],[0,0,1]).tolist(),[1,2,3,4])
        case._mesh_evaluator=lambda *args:dict(ok=False,error='crossing overflow')
        self.assertEqual(case.hits([.2,.25,0],[0,0,1]).tolist(),[1,3])
        self.assertTrue(case._mesh_disabled)
    def test_complete_mesh_service_and_cpu_fallback(self):
        client=PlMetrics();output=[frame([2<<16,5<<16,7<<16,10<<16])]
        class Mmio:
            def __init__(self):self.words={}
            def write(self,offset,value):self.words[offset]=value
            def read(self,offset):
                return {0x024:self.words.get(4,0),0x010:self.words.get(8,0),0x014:4,0x020:111,0x018:output[0][4]}.get(offset,self.words.get(offset,0))
        def load():
            if client._overlay is not None:return
            client._overlay=types.SimpleNamespace(download=lambda:None)
            client._mesh_complete=client._mesh_metadata=client._mesh_ddr_mode=True
            client._mesh_mmio=Mmio();client._mesh_ray_dma=Dma(True)
            client._mesh_result_dma=Dma(True,output[0])
        tri=np.array([[[-10,-10,0],[10,-10,0],[-10,10,0]]])
        with patch.dict(os.environ,{'LUNG_PL_ENABLE':'1'}),patch.object(client,'_load',side_effect=load),patch.dict(sys.modules,{'pynq':types.SimpleNamespace(allocate=lambda shape,dtype:Buffer(shape[0]))}):
            result=client.evaluate_mesh_rays(tri,[[0,0,20]],[[0,0,-1]])
            self.assertTrue(result['ok'],result);self.assertTrue(result['complete_crossings']);self.assertEqual(result['operation'],'bvh_pl')
            self.assertEqual(len(client._mesh_result_buf),RESULT_BYTES)
            self.assertEqual(client._mesh_mmio.words[0x03c],3)
            self.assertEqual(client._mesh_mmio.words[0x058],128)
            second=client.evaluate_mesh_rays(tri,[[0,0,20]],[[0,0,-1]])
            self.assertTrue(second['mesh_reused'])
            output[0]=frame([20],raw=129,error=32);client._mesh_result_dma.recvchannel.output_data=output[0]
            failed=client.evaluate_mesh_rays(tri,[[0,0,20]],[[0,0,-1]])
            self.assertFalse(failed['ok']);self.assertEqual(failed['diagnostic']['errors'],32)
            self.assertIsNotNone(client._mesh_buf)
            client.close()
if __name__=='__main__':unittest.main()
