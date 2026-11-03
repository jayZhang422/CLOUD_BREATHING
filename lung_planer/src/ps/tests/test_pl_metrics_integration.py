"""Tests that full planning consumes PL tumor metrics without recomputing them."""
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cas_frontend import pl_metrics
from cas_frontend.planning_geometry import PlanningCase


class PlMetricIntegrationTests(unittest.TestCase):
    def make_case(self):
        case = object.__new__(PlanningCase)
        case.points = np.asarray(((0., 0., 0.), (1., 0., 0.)))
        case.triangles = np.asarray((((0., 0., 0.), (1., 0., 0.), (0., 1., 0.)),))
        case.lung = [object()]
        case.lung_volume = 1000.
        case.lung_files = ['lung.stl']
        case.tumor_file = 'tumor.stl'
        case.mirror_x = None
        case._lung_watertight = True
        case.validate_base = lambda *args, **kwargs: (True, 2., 0)
        case.inside = lambda *args, **kwargs: True
        case.surface = lambda faces: (1., np.zeros((0, 3, 3), dtype=np.float32))
        case.volume = lambda *args, **kwargs: (100., 20.)
        return case

    def test_pl_metrics_skip_arm_coverage_calculation(self):
        case = self.make_case()
        vertices = np.asarray(((0., 0., 2.), (1., 0., 2.),
                               (0., 1., 2.), (0., 0., 1.)))
        metrics = dict(ok=True, feasible=True, coverage_percent=100.,
                       clearance_mm=1.25)
        params = dict(minClearance=1., yaw=0., pitch=0., margin=1., rotation=0.)
        with patch.object(case, 'coverage', side_effect=AssertionError('ARM coverage ran')):
            result, _ = case.evaluate(vertices, params,
                                      metric_result=metrics)
        self.assertEqual(result['coverage_percent'], 100.)
        self.assertEqual(result['clearance_mm'], 1.25)
        self.assertTrue(result['valid'])
        self.assertLess(result['timings_ms']['coverage'], 1.)

    def test_cpu_fallback_keeps_existing_coverage_path(self):
        case = self.make_case()
        vertices = np.asarray(((0., 0., 2.), (1., 0., 2.),
                               (0., 1., 2.), (0., 0., 1.)))
        case.coverage = lambda _: (80., -0.2, [])
        params = dict(minClearance=1., yaw=0., pitch=0., margin=1., rotation=0.)
        result, _ = case.evaluate(vertices, params)
        self.assertEqual(result['coverage_percent'], 80.)
        self.assertEqual(result['clearance_mm'], -0.2)
        self.assertFalse(result['valid'])

    def test_privileged_mesh_call_forwards_labels_and_checks_solid_count(self):
        client = pl_metrics.PlMetrics()
        client._privileged = Mock()
        client._privileged.evaluate_mesh_rays.return_value = dict(ok=True, solid_count=2)
        triangles = np.tile(np.eye(3, dtype=float), (2, 1, 1))
        labels = np.asarray((0, 1), dtype=np.uint8)
        origins = np.asarray(((0., 0., 0.),))
        directions = np.asarray(((0., 0., 1.),))

        with patch.object(pl_metrics.sys, 'platform', 'linux'), \
                patch.object(pl_metrics.os, 'geteuid', return_value=1000, create=True):
            result = client.evaluate_mesh_rays(
                triangles, origins, directions, solid_ids=labels)

        self.assertTrue(result['ok'])
        np.testing.assert_array_equal(
            client._privileged.evaluate_mesh_rays.call_args.kwargs['solid_ids'], labels)

    def test_privileged_mesh_call_rejects_solid_count_mismatch(self):
        client = pl_metrics.PlMetrics()
        client._privileged = Mock()
        client._privileged.evaluate_mesh_rays.return_value = dict(ok=True, solid_count=1)
        triangles = np.tile(np.eye(3, dtype=float), (2, 1, 1))
        origins = np.asarray(((0., 0., 0.),))
        directions = np.asarray(((0., 0., 1.),))

        with patch.object(pl_metrics.sys, 'platform', 'linux'), \
                patch.object(pl_metrics.os, 'geteuid', return_value=1000, create=True):
            result = client.evaluate_mesh_rays(
                triangles, origins, directions, solid_ids=np.asarray((0, 1)))

        self.assertFalse(result['ok'])
        self.assertIn('solid count mismatch', result['error'])

    def test_distance_request_keeps_mesh_labels(self):
        client = pl_metrics.PlMetrics()
        client.evaluate_mesh_rays = Mock(return_value=dict(ok=True, solid_count=2))
        triangles = np.zeros((2, 3, 3))
        points = np.zeros((1, 3))
        labels = np.asarray((0, 1))

        client.evaluate_mesh_distances(triangles, points, solid_ids=labels)

        call = client.evaluate_mesh_rays.call_args
        np.testing.assert_array_equal(call.kwargs['solid_ids'], labels)
        self.assertTrue(call.kwargs['_distance'])


if __name__ == '__main__':
    unittest.main()
