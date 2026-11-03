"""Distance transport, buffer mode changes, integrity and strict ownership."""
import base64,io,json,os,struct,sys,types,unittest
from pathlib import Path
from unittest.mock import patch,Mock
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from cas_frontend.mesh_distance import decode_results
from cas_frontend.pl_metrics import PlMetrics
from cas_frontend.pl_privileged import PrivilegedPlClient
from tools.pl_service import serve
from test_pl_metrics_recovery import Buffer,Dma
from test_ray_volume_frames import volume_frame
import test_strict_planner as strict_tests

def frame(index=1,square=4<<32,errors=0,valid=1):
 return struct.pack('<8I',index,errors,square&0xffffffff,(square>>32)&0xffffffff,
                    square>>64,valid,0,32)

class MeshDistanceFrameTests(unittest.TestCase):
 def setUp(self):
  direct = patch('cas_frontend.pl_metrics.os.geteuid', return_value=0, create=True)
  direct.start(); self.addCleanup(direct.stop)

 def test_decoder_full_width_zero_and_corrupt_fields(self):
  for value in (0,1,4<<32,3*((1<<32)-1)**2):
   self.assertEqual(decode_results(frame(square=value),1)[0]['distance_squared_q32'],value)
  for offset,value in ((0,2),(4,256),(20,0),(20,2),(24,1),(28,30)):
   raw=bytearray(frame());struct.pack_into('<I',raw,offset,value)
   with self.assertRaises(ValueError):decode_results(raw,1)
  with self.assertRaises(ValueError):decode_results(frame(errors=16),1)
  self.assertFalse(decode_results(frame(errors=16,valid=0),1)[0]['distance_valid'])

 def test_strict_distance_never_scans_cpu_and_consumes_global_min(self):
  case=strict_tests.StrictPlannerTests().strict_case(None)
  case._distance_stats=dict(calls=0,points=0,job_ms=0.,service_ms=0.,cycles=0)
  good=dict(ok=True,pl_distance=True,errors=0,processed=2,distance_valid_points=2,
       distance_min_squared_q32=1<<32,results=[dict(point_id=1,errors=0,distance_valid=True,distance_squared_q32=4<<32),
       dict(point_id=2,errors=0,distance_valid=True,distance_squared_q32=1<<32)])
  case._distance_evaluator=Mock(return_value=good)
  with patch.object(case,'_distance_many_cpu',side_effect=AssertionError('CPU distance')):
   np.testing.assert_array_equal(case._distance_many([[0,0,0],[1,1,1]]),[2.,1.])
   self.assertEqual(case._last_distance_min_mm,1.)
   for bad in (dict(ok=False,error='timeout'),dict(good,distance_min_squared_q32=0),dict(good,distance_valid_points=1),dict(good,pl_distance=False)):
    case._distance_evaluator.return_value=bad
    with self.assertRaises(RuntimeError):case._distance_many([[0,0,0],[1,1,1]])
  with self.assertRaises(RuntimeError):case._distance_many_cpu([[0,0,0]])

 def test_privileged_distance_and_volume_flags_with_cached_mesh(self):
  client=PrivilegedPlClient('unused.bit');client.process=types.SimpleNamespace(stdin=io.BytesIO())
  tri=np.array([[[0,0,0],[1,0,0],[0,1,0]]],float)
  with patch.object(client,'_start'),patch.object(client,'_receive',return_value=dict(ok=True)):
   client.evaluate_mesh_rays(tri,[[0,0,2]],[[0,0,0]],_distance=True)
   client.evaluate_mesh_rays(tri,[[0,0,2]],[[0,0,0]],_distance=True)
  jobs=[json.loads(line) for line in client.process.stdin.getvalue().splitlines()]
  self.assertTrue(jobs[0]['distance']);self.assertFalse(jobs[0]['volume']);self.assertNotIn('mesh',jobs[1])
  fake=Mock();fake.evaluate_mesh_rays.return_value=dict(ok=True)
  destination=io.StringIO();serve(fake,io.StringIO(''.join(json.dumps(x)+'\n' for x in jobs)),destination)
  self.assertTrue(all(json.loads(x)['ok'] for x in destination.getvalue().splitlines()[1:]))
  self.assertTrue(fake.evaluate_mesh_rays.call_args.kwargs['_distance'])
  np.testing.assert_array_equal(fake.evaluate_mesh_rays.call_args.args[1],[[0,0,2]])

 def test_direct_distance_volume_distance_buffer_switch_corrupt_min_and_old_abi(self):
  client=PlMetrics();square=(1<<65)+7
  class Mmio:
   def __init__(self):self.words={};self.bad=False;self.abi=0x60000
   def write(self,o,v):self.words[o]=v
   def read(self,o):return {0x024:self.words.get(4,0),0x010:self.words.get(8,0),0x018:0,
       0x020:100,0x02c:self.abi,0x050:63,0x090:32,0x094:32,0x080:(square&0xffffffff)+self.bad,
       0x084:(square>>32)&0xffffffff,0x088:square>>64,0x08c:1,0x06c:1<<30,0x070:0,0x074:1,0x078:1<<30}.get(o,self.words.get(o,0))
  def load():
   if client._overlay is not None:return
   client._overlay=types.SimpleNamespace(download=lambda:None)
   client._mesh_complete=client._mesh_metadata=client._mesh_ddr_mode=client._mesh_volume=True
   client._mesh_mmio=Mmio();client._mesh_ray_dma=Dma(True);client._mesh_result_dma=Dma(True,frame(square=square))
  tri=np.array([[[0,0,0],[1,0,0],[0,1,0]]],float)
  with patch.dict(os.environ,{'LUNG_PL_ENABLE':'1'}),patch.object(client,'_load',side_effect=load),patch.dict(sys.modules,{'pynq':types.SimpleNamespace(allocate=lambda shape,dtype:Buffer(shape[0]))}):
   distance=client.evaluate_mesh_distances(tri,[[0,0,2]])
   self.assertTrue(distance['ok'],distance);self.assertEqual(distance['distance_min_squared_q32'],square)
   self.assertEqual(client._mesh_mmio.words[0x03c],9);self.assertEqual(len(client._mesh_result_buf),32)
   client._mesh_result_dma=Dma(True,volume_frame(length=3<<16))
   volume=client.evaluate_mesh_rays(tri,[[0,0,2]],[[0,0,-1]],lengths=[3])
   self.assertTrue(volume['ok'],volume);self.assertTrue(volume['mesh_reused']);self.assertEqual(len(client._mesh_result_buf),576)
   client._mesh_result_dma=Dma(True,frame(square=square))
   self.assertTrue(client.evaluate_mesh_distances(tri,[[0,0,2]])['ok']);self.assertEqual(len(client._mesh_result_buf),32)
   client._mesh_mmio.bad=True
   with patch.object(client,'_reset_hardware_state') as reset:
    result=client.evaluate_mesh_distances(tri,[[0,0,2]])
    self.assertFalse(result['ok']);self.assertIn('minimum/count',result['error']);reset.assert_called_once()
   client._mesh_mmio.abi=0x50000
   with patch.object(client,'_reset_hardware_state'):
    self.assertFalse(client.evaluate_mesh_distances(tri,[[0,0,2]])['ok'])
   client.close()
if __name__=='__main__':unittest.main()
