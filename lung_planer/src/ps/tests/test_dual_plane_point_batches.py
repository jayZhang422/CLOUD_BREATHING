"""Oversized point sets must retain full-input statistics and fail atomically."""
import unittest
from unittest.mock import patch

import numpy as np

from cas_frontend.pl_metrics import PlMetrics


class PointBatchTests(unittest.TestCase):
    def setUp(self):
        self.evaluator = PlMetrics()
        self.calls = []
        self.candidates = np.zeros((3, 4, 3))
        self.candidates[:, 0, 0] = [-1., 0., 1.]
        self.evaluator._evaluate_dual_plane_filter_chunk = self.hardware

    def hardware(self, points, candidates, margin, **kwargs):
        self.calls.append((points.copy(), kwargs['timeout_seconds']))
        self.assertLessEqual(len(points), 4096)
        rows = []
        for index, candidate in enumerate(candidates):
            clearance = points[:, 0] - candidate[0, 0]
            accepted = int(np.count_nonzero(clearance >= margin))
            rows.append(dict(ok=True, index=index, processed=len(points), accepted=accepted,
                             coverage_percent=100. * accepted / len(points),
                             clearance_mm=float(clearance.min()), errors=0, cpu_fallback_count=0))
        return dict(ok=True, candidates=rows, candidate_count=len(rows),
                    processed=len(points) * len(rows), accepted=sum(r['accepted'] for r in rows),
                    coverage_percent=min(r['coverage_percent'] for r in rows),
                    clearance_mm=min(r['clearance_mm'] for r in rows),
                    cycles=10, pl_calls=1, dma_input_bytes=len(points) * 16,
                    dma_output_bytes=len(rows) * 16, dma_input_transfers=1,
                    dma_output_transfers=1, job_id=len(self.calls), cpu_fallback_count=0,
                    points_pack_reused=False, points_resident_reused=False,
                    quantization_tolerance_mm=.001)

    def test_boundaries_duplicates_and_original_coverage(self):
        for count in (4096, 4097, 8192, 9672, 16385):
            with self.subTest(count=count):
                self.calls.clear()
                points = np.zeros((count, 3))
                points[:, 0] = np.arange(count) % 7 - 3
                points[-1, 0] = -100.
                result = self.evaluator.evaluate_dual_plane_filter_batch(points, self.candidates, .5)
                self.assertTrue(result['ok'], result)
                np.testing.assert_array_equal(np.concatenate([p for p, _ in self.calls]), points)
                for row, candidate in zip(result['candidates'], self.candidates):
                    clearances = points[:, 0] - candidate[0, 0]
                    accepted = int(np.count_nonzero(clearances >= .5))
                    self.assertEqual(row['processed'], count)
                    self.assertEqual(row['accepted'], accepted)
                    self.assertEqual(row['coverage_percent'], 100. * accepted / count)
                    self.assertEqual(row['clearance_mm'], clearances.min())
                self.assertEqual(result['processed'], count * 3)
                self.assertEqual(result['pl_calls'], (count + 4095) // 4096)
                self.assertEqual(result['cpu_fallback_count'], 0)

    def test_single_candidate_api_uses_full_counts(self):
        result = self.evaluator.evaluate_dual_plane_filter(
            np.ones((4494, 3)), self.candidates[0], 0.)
        self.assertTrue(result['ok'])
        self.assertEqual(result['accepted'], 4494)
        self.assertEqual(result['coverage_percent'], 100.)
        self.assertEqual(result['pl_calls'], 2)

    def test_cancel_between_batches_discards_partial_result(self):
        result = self.evaluator.evaluate_dual_plane_filter_batch(
            np.ones((8193, 3)), self.candidates, 0., cancel=lambda: len(self.calls) == 1)
        self.assertFalse(result['ok'])
        self.assertIn('cancelled', result['error'])
        self.assertNotIn('candidates', result)
        self.assertEqual(len(self.calls), 1)

    def test_failed_chunk_discards_partial_result(self):
        original = self.hardware
        def fail(points, candidates, margin, **kwargs):
            if self.calls:
                return dict(ok=False, error='hardware timeout', cpu_fallback_count=0)
            return original(points, candidates, margin, **kwargs)
        self.evaluator._evaluate_dual_plane_filter_chunk = fail
        result = self.evaluator.evaluate_dual_plane_filter_batch(
            np.ones((8193, 3)), self.candidates, 0.)
        self.assertFalse(result['ok'])
        self.assertEqual(result['error'], 'hardware timeout')
        self.assertNotIn('candidates', result)

    def test_one_deadline_for_all_batches(self):
        with patch('cas_frontend.pl_metrics.time.monotonic', side_effect=[0., .2, 2.]):
            result = self.evaluator.evaluate_dual_plane_filter_batch(
                np.ones((8193, 3)), self.candidates, 0., timeout_seconds=1.)
        self.assertFalse(result['ok'])
        self.assertIn('timeout', result['error'])
        self.assertEqual(len(self.calls), 1)
        self.assertAlmostEqual(self.calls[0][1], .8)

    def test_invalid_input_does_not_start_hardware(self):
        points = np.ones((4097, 3))
        points[-1, 0] = np.nan
        result = self.evaluator.evaluate_dual_plane_filter_batch(points, self.candidates, 0.)
        self.assertFalse(result['ok'])
        self.assertEqual(self.calls, [])


if __name__ == '__main__':
    unittest.main()
