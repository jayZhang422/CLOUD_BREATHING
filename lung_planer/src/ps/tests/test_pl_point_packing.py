"""The vectorized point packer must emit the exact bytes of the per-point reference."""
import struct
import unittest

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.pl_metrics import PlMetrics, _q16


def reference_pack(points):
    raw = bytearray()
    for point in points:
        raw.extend(struct.pack('<iiiI', _q16(point[0]), _q16(point[1]), _q16(point[2]), 0))
    return bytes(raw)


class PointPackingTests(unittest.TestCase):
    def setUp(self):
        self.evaluator = PlMetrics()

    def pack(self, points):
        return self.evaluator._pack_points(np.asarray(points, dtype=np.float64))[0]

    def test_matches_reference_bytes(self):
        rng = np.random.default_rng(1)
        step = 1. / 65536.
        cases = [
            rng.uniform(-6., 6., (6000, 3)),
            rng.uniform(-30000., 30000., (5000, 3)),
            rng.normal(0., 1e-6, (100, 3)),
            # Exact half-way ties must round to even like Python's round().
            np.array([[.5 * step, 1.5 * step, 2.5 * step], [-.5 * step, -1.5 * step, -2.5 * step]]),
            # Both edges of the signed Q16.16 range.
            np.array([[32767.99998, -32768., 0.]]),
            np.empty((0, 3)),
        ]
        for index, points in enumerate(cases):
            with self.subTest(case=index):
                self.assertEqual(self.pack(points), reference_pack(points))

    def test_rejects_out_of_range_and_nonfinite_like_reference(self):
        for bad in ([[40000., 0., 0.]], [[0., -40000., 0.]], [[np.nan, 0., 0.]], [[0., np.inf, 0.]]):
            with self.subTest(bad=bad):
                with self.assertRaises((ValueError, OverflowError)):
                    reference_pack(np.asarray(bad))
                with self.assertRaises(ValueError):
                    self.pack(bad)

    def test_immutable_input_is_cached_and_reused(self):
        points = np.random.default_rng(2).uniform(-5., 5., (50, 3))
        points.setflags(write=False)
        first, reused_first = self.evaluator._pack_points(points)
        second, reused_second = self.evaluator._pack_points(points)
        self.assertEqual(first, reference_pack(points))
        self.assertFalse(reused_first)
        self.assertTrue(reused_second)
        self.assertIs(first, second)


if __name__ == '__main__':
    unittest.main()
