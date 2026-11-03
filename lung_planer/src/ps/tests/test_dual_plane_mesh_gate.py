import os
import copy
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import manifold3d as m
import numpy as np

from cas_frontend.dual_plane_mesh_gate import MeshPlanningSession, verify_admission
from cas_frontend.dual_plane_reference import manifold_volume_metrics
from cas_frontend.mesh_union import _triangles
from cas_frontend.planning_cancel import PlanningCancelled


class MeshAdmissionTests(unittest.TestCase):
    def setUp(self):
        solid = m.Manifold.cube((1.,1.,1.))
        self.union = SimpleNamespace(solid=solid, triangles=_triangles(solid))
        self.candidates = np.asarray([[[.5,20.5,0],[.5,.5,-20],[20.5,.5,0],[.5,.5,20]]])
        reference = manifold_volume_metrics(solid, self.candidates[0])
        self.result = dict(ok=True, abi='0x00050000', execution_backend='dual_plane_pl_mesh',
            reference_only=False, clock_mhz=100., cpu_fallback_count=0, errors=0, candidate_count=1,
            candidates=[dict(reference, index=0, ok=True, valid=True, flags=0, errors=0, cpu_fallback_count=0)])
        self.evaluator = Mock()
        self.evaluator.evaluate_dual_plane_mesh_batch.return_value = self.result

    def test_shadow_compares_all_metrics_and_caches_identical_candidates(self):
        session = MeshPlanningSession(self.evaluator, self.union, shadow=True, cancelled=lambda:False)
        rows = session.evaluate(self.candidates, phase='coarse_batch')
        self.assertEqual(rows[0]['ranking_volume_mm3'], self.result['candidates'][0]['volume_mm3'])
        self.assertEqual(session.call_timings[0]['phase'], 'coarse_batch')
        self.assertEqual(session.call_timings[0]['candidate_count'], 1)
        self.assertGreaterEqual(session.call_timings[0]['end_to_end_ms'],
                                session.call_timings[0]['frontend_call_ms'])
        session.evaluate(self.candidates)
        self.assertEqual(session.calls, 1)
        self.assertEqual(len(session.call_timings), 1)
        self.assertEqual(session.checked_candidates, 1)
        self.result['candidates'][0]['cut_area_mm2'] += .01
        fresh = MeshPlanningSession(self.evaluator, self.union, shadow=True, cancelled=lambda:False)
        with self.assertRaisesRegex(RuntimeError, 'parity'):
            fresh.evaluate(self.candidates)
        self.assertFalse(fresh.cache)

    def test_cancelled_completion_never_enters_cache(self):
        cancelled = [False]
        def late(*args, **kwargs):
            cancelled[0] = True
            return self.result
        self.evaluator.evaluate_dual_plane_mesh_batch.side_effect = late
        session = MeshPlanningSession(self.evaluator, self.union, shadow=True, cancelled=lambda:cancelled[0])
        with self.assertRaises(PlanningCancelled):
            session.evaluate(self.candidates)
        self.assertFalse(session.cache)

    def test_no_receipt_no_formal_ranking(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaisesRegex(RuntimeError, 'ACCEPTANCE'):
            MeshPlanningSession(self.evaluator, self.union, shadow=False, cancelled=lambda:False)
        self.evaluator.evaluate_dual_plane_mesh_batch.assert_not_called()
        with TemporaryDirectory() as temporary:
            path = Path(temporary)/'report.json'
            path.write_text('{"board_validated": true, "full": false}')
            with self.assertRaisesRegex(RuntimeError, 'complete board parity'):
                verify_admission(path, 'unused.bit')

    def test_full_receipt_binds_artifacts_software_mesh_and_every_candidate(self):
        from cas_frontend.dual_plane_mesh_gate import sha256
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            bit, hwh, source, receipt = [root/name for name in ('test.bit','test.hwh','code.py','receipt.json')]
            bit.write_bytes(b'unit-test hardware artifact')
            hwh.write_bytes(b'unit-test metadata')
            source.write_bytes(b'unit-test software source')
            result = copy.deepcopy(self.result)
            result['candidate_count'] = 4
            result['candidates'] = [dict(self.result['candidates'][0], index=index) for index in range(4)]
            cases = [dict(name='cube', mesh_sha256='mesh', parity_pass=True, candidate_count=4,
                selected_candidate_indices=[1,2,3,4], provenance=dict(population='analytic_cube'),
                resident_reuse_verified=True, result=copy.deepcopy(result),
                max_abs_delta=dict(volume_mm3=0.,surface_area_mm2=0.,cut_area_mm2=0.))]
            report = dict(kind='dual_plane_mesh_hardware_parity', board_validated=True,
                control_recovery=dict(cancelled_then_recovered=True,timed_out_then_recovered=True,cpu_fallback_count=0),
                full=True, abi='0x00050000', bit_sha256=sha256(bit),hwh_sha256=sha256(hwh),
                source_sha256={'code.py':sha256(source)},cases=cases)
            def write(value):
                receipt.write_text(json.dumps(value),encoding='utf-8')
            with patch('cas_frontend.dual_plane_mesh_gate.ROOT',root), \
                 patch('cas_frontend.dual_plane_mesh_gate.SOURCE_FILES',('code.py',)):
                write(report)
                self.assertEqual(verify_admission(receipt,bit),sha256(receipt))
                for frequency in (150., float('nan')):
                    changed=copy.deepcopy(report)
                    changed['cases'][0]['result']['clock_mhz']=frequency;write(changed)
                    with self.assertRaisesRegex(RuntimeError,'complete case'):
                        verify_admission(receipt,bit)
                write(report)
                # Admission no longer depends on which lung is loaded.
                self.assertEqual(verify_admission(receipt,bit),sha256(receipt))
                for field in ('bit_sha256','hwh_sha256'):
                    changed=copy.deepcopy(report);changed[field]='wrong';write(changed)
                    with self.assertRaisesRegex(RuntimeError,'hash mismatch'):
                        verify_admission(receipt,bit)
                changed=copy.deepcopy(report)
                changed['source_sha256']['code.py']='wrong';write(changed)
                with self.assertRaisesRegex(RuntimeError,'software hash'):
                    verify_admission(receipt,bit)
                changed=copy.deepcopy(report)
                changed['cases'][0]['result']['candidates'][3]['flags']=4;write(changed)
                with self.assertRaisesRegex(RuntimeError,'invalid candidate'):
                    verify_admission(receipt,bit)
                changed=copy.deepcopy(report);changed['cases'].pop();write(changed)
                with self.assertRaisesRegex(RuntimeError,'complete case'):
                    verify_admission(receipt,bit)
                changed=copy.deepcopy(report);changed['cases'][0]['result']['candidates'].pop();write(changed)
                with self.assertRaisesRegex(RuntimeError,'complete case'):
                    verify_admission(receipt,bit)
                changed=copy.deepcopy(report);changed['cases'][0]['max_abs_delta']['volume_mm3']=1e-3;write(changed)
                with self.assertRaisesRegex(RuntimeError,'tolerance'):
                    verify_admission(receipt,bit)


if __name__ == '__main__':
    unittest.main()
