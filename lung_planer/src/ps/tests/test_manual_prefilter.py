"""A manual PL recompute must not be rejected by the quantized prefilter's conservative margin."""
import os
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import planning_models as models

VERTICES = np.arange(12, dtype=float).reshape(4, 3)


def prefilter(**fields):
    row = dict(ok=True, cpu_fallback_count=0, accepted=5995, processed=6000,
               clearance_mm=1.00001, quantization_tolerance_mm=0.09,
               cycles=1, dma_input_bytes=1, dma_output_bytes=1)
    row.update(fields)
    return row


def run_manual(filter_result):
    evaluator = Mock()
    evaluator.evaluate_dual_plane_filter.return_value = filter_result
    case = SimpleNamespace(_strict_pl=False, _dual_plane_pl=evaluator, points=np.zeros((6000, 3)),
                           _check_planning_overlap=lambda: None)
    exact = dict(result=dict(valid=True))
    job = dict(mode='manual', backend='pl', directory='.', vertices=VERTICES,
               params=dict(planningModel='plane_wedge', minClearance=1.0, wedgeAngle=90.))
    with patch.dict(os.environ, {'DUAL_PLANE_MESH_ENABLE': '0'}), \
         patch.object(models, 'evaluate_region', return_value=exact) as evaluate:
        payload = models.run_research(case, job)
    return payload, evaluate


class ManualPrefilterTests(unittest.TestCase):
    def test_short_conservative_margin_is_decided_by_exact_review(self):
        # 1.00001 - 0.09 < 1.0: the old code raised before any exact check.
        payload, evaluate = run_manual(prefilter())
        evaluate.assert_called_once()
        self.assertTrue(payload['result']['valid'])
        self.assertEqual(payload['result']['dual_plane_pl_calls'], 1)

    def test_exact_review_can_still_reject(self):
        evaluator = Mock()
        evaluator.evaluate_dual_plane_filter.return_value = prefilter()
        case = SimpleNamespace(_strict_pl=False, _dual_plane_pl=evaluator, points=np.zeros((6000, 3)),
                               _check_planning_overlap=lambda: None)
        job = dict(mode='manual', backend='pl', directory='.', vertices=VERTICES,
                   params=dict(planningModel='plane_wedge', minClearance=1.0, wedgeAngle=90.))
        with patch.dict(os.environ, {'DUAL_PLANE_MESH_ENABLE': '0'}), \
             patch.object(models, 'evaluate_region', side_effect=ValueError('规划没有同时连接真实肺表面和肺内切面')):
            with self.assertRaisesRegex(ValueError, '真实肺表面'):
                models.run_research(case, job)

    def test_hardware_failure_is_still_fatal(self):
        for bad in (prefilter(ok=False, error='DMA timeout'), prefilter(cpu_fallback_count=1)):
            with self.subTest(bad=bad):
                with self.assertRaisesRegex(ValueError, 'PL 双平面预筛选调用失败'):
                    run_manual(bad)


if __name__ == '__main__':
    unittest.main()
