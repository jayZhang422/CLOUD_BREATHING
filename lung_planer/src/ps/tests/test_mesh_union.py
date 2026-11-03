"""Analytic union and cut-face checks, independent of the old sampler."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

from cas_frontend.mesh_union import LungUnion
from cas_frontend.planning_geometry import PlanningCase
from cas_frontend import planner_reference as ref
import test_adaptive_planner as fixtures


def box(center=(0., 0., 0.), half=1.):
    return np.asarray([t.points for t in fixtures.box(np.asarray(center), half)])


class UnionMetricTests(unittest.TestCase):
    def test_union_volume_and_exterior_area_for_overlap_contact_nested_duplicate_and_disjoint(self):
        scenarios = [
            (box(), box((1., 0., 0.)), 12., 32.),
            (box(), box((2., 0., 0.)), 16., 40.),
            (box(), box(half=.5), 8., 24.),
            (box(), box(), 8., 24.),
            (box(), box((4., 0., 0.)), 16., 48.),
        ]
        enclosing = np.asarray(((-20., -20., -20.), (100., -20., -20.),
                                (-20., 100., -20.), (-20., -20., 100.)))
        for a, b, volume, area in scenarios:
            with self.subTest(volume=volume, area=area):
                union = LungUnion([a, b], ['lung-a', 'lung-b'])
                self.assertAlmostEqual(union.volume_mm3, volume, places=9)
                clipped = union.intersect(enclosing)
                self.assertAlmostEqual(clipped['volume_mm3'], volume, places=9)
                self.assertAlmostEqual(clipped['surface_area_mm2'], area, places=9)
                self.assertAlmostEqual(clipped['cut_area_mm2'], 0., places=9)

    def test_union_cache_reloads_exact_union_without_batch_boolean(self):
        with tempfile.TemporaryDirectory() as directory:
            first = LungUnion([box(), box((1., 0., 0.))], ['a', 'b'], cache_dir=directory)
            self.assertFalse(first.cache_hit)
            second = LungUnion([box(), box((1., 0., 0.))], ['a', 'b'], cache_dir=directory)
            self.assertTrue(second.cache_hit)
            self.assertAlmostEqual(second.volume_mm3, first.volume_mm3, places=9)
            np.testing.assert_allclose(second.triangles, first.triangles)

    def test_partial_triangle_cut_and_provenance_are_exact_for_cube_octant(self):
        union = LungUnion([box(), box()], ['lung', 'duplicate'])
        tetra = np.asarray(((10., 0., 0.), (0., 10., 0.), (0., 0., 10.), (0., 0., 0.)))
        result = union.intersect(tetra)
        # The intersection is [0,1]^3: three pleural faces and three cut faces.
        self.assertAlmostEqual(result['volume_mm3'], 1., places=9)
        self.assertAlmostEqual(result['surface_area_mm2'], 3., places=9)
        self.assertAlmostEqual(result['cut_area_mm2'], 3., places=9)
        self.assertAlmostEqual(PlanningCase.cut_area(result['interior']), .03, places=9)
        self.assertIs(result, union.intersect(tetra.copy()))

    def test_oblique_cut_plane_area(self):
        union = LungUnion([box(center=(.5, .5, .5), half=.5)], ['lung'])
        tetra = np.asarray(((1., 0., 0.), (0., 1., 0.), (0., 0., 1.), (0., 0., 0.)))
        result = union.intersect(tetra)
        self.assertAlmostEqual(result['volume_mm3'], 1. / 6., places=9)
        self.assertAlmostEqual(result['surface_area_mm2'], 1.5, places=9)
        self.assertAlmostEqual(result['cut_area_mm2'], np.sqrt(3.) / 2., places=9)

    def test_fully_contained_tetra_and_empty_intersection(self):
        union = LungUnion([box(half=10.)], ['lung'])
        tetra = np.asarray(((1., 0., 0.), (0., 1., 0.), (0., 0., 1.), (0., 0., 0.)))
        result = union.intersect(tetra)
        self.assertAlmostEqual(result['volume_mm3'], 1. / 6., places=9)
        self.assertEqual(result['surface_area_mm2'], 0.)
        self.assertAlmostEqual(result['cut_area_mm2'], 1.5 + np.sqrt(3.) / 2., places=9)
        result = union.intersect(tetra + 30.)
        self.assertEqual(result['volume_mm3'], 0.)
        self.assertEqual(result['surface_area_mm2'], 0.)
        self.assertEqual(result['cut_area_mm2'], 0.)

    def test_reversed_winding_is_supported_but_open_mesh_is_rejected(self):
        self.assertAlmostEqual(LungUnion([box()[:, ::-1]], ['lung']).volume_mm3, 8.)
        with self.assertRaisesRegex(ValueError, '闭合有向实体'):
            LungUnion([box()[:-1]], ['open'])

    def test_cpu_case_consumes_union_metrics_and_does_not_sample_cutting_faces(self):
        lungs = fixtures.box(np.zeros(3), 1.)
        tumor = fixtures.box(np.asarray((.5, .5, .5)), .1)
        with tempfile.TemporaryDirectory() as directory:
            for name in ('lung.stl', 'lung_duplicate.stl', 'tumor.stl'):
                (Path(directory) / name).touch()
            with patch.object(ref, 'read_stl', side_effect=lambda p: tumor if p.name == 'tumor.stl' else lungs):
                case = PlanningCase(directory, ['lung.stl', 'lung_duplicate.stl'], 'tumor.stl', ray_mode='cpu')
        self.assertAlmostEqual(case.lung_volume, 8.)
        tetra = np.asarray(((10., 0., 0.), (0., 10., 0.), (0., 0., 10.), (0., 0., 0.)))
        self.assertAlmostEqual(case.volume(tetra)[1], 1.)
        self.assertIn('Boolean', case.cut_area_method())

    def test_cpu_case_reports_bilateral_volume_and_uses_it_as_resection_ratio_denominator(self):
        target = fixtures.box(np.zeros(3), 1.)
        other_lung = fixtures.box(np.asarray((10., 0., 0.)), 1.)
        tumor = fixtures.box(np.asarray((.5, .5, .5)), .1)
        with tempfile.TemporaryDirectory() as directory:
            for name in ('target.stl', 'other.stl', 'tumor.stl'):
                (Path(directory) / name).touch()
            with patch.object(ref, 'read_stl', side_effect=lambda p: {
                    'target.stl': target, 'other.stl': other_lung,
                    'tumor.stl': tumor}[p.name]):
                case = PlanningCase(directory, ['target.stl'], 'tumor.stl', ray_mode='cpu',
                                    whole_lung_files=['target.stl', 'other.stl'])
        self.assertAlmostEqual(case.lung_volume, 8.)
        self.assertAlmostEqual(case.whole_lung_volume, 16.)
        tetra = np.asarray(((10., 0., 0.), (0., 10., 0.), (0., 0., 10.), (0., 0., 0.)))
        result, _ = case.evaluate(tetra, dict(
            yaw=0., pitch=0., margin=1., baseOffset=1., padding=1.,
            minClearance=.1, rotation=0., baseArea=0., baseClearance=.1))
        self.assertAlmostEqual(result['lung_volume_cm3'], .016)
        self.assertAlmostEqual(result['target_lung_volume_cm3'], .008)
        self.assertAlmostEqual(result['resection_ratio_percent'],
                               result['resection_volume_cm3'] / .016 * 100.)
        self.assertAlmostEqual(result['target_lung_resection_ratio_percent'],
                               result['resection_volume_cm3'] / .008 * 100.)

    def test_coarse_volume_uses_union_crossings_without_boolean_rebuild(self):
        lungs = fixtures.box(np.zeros(3), 10.)
        tumor = fixtures.box(np.asarray((.5, .5, .5)), .1)
        with tempfile.TemporaryDirectory() as directory:
            for name in ('lung.stl', 'tumor.stl'):
                (Path(directory) / name).touch()
            with patch.object(ref, 'read_stl', side_effect=lambda p: tumor if p.name == 'tumor.stl' else lungs):
                case = PlanningCase(directory, ['lung.stl'], 'tumor.stl', ray_mode='cpu')
        tetra = np.asarray(((1., 0., 0.), (0., 1., 0.), (0., 0., 1.), (0., 0., 0.)))
        with patch.object(case._lung_union, 'intersect', side_effect=AssertionError('coarse path rebuilt Boolean mesh')):
            total, removed = case.volume(tetra, steps=3, coarse=True)
        self.assertAlmostEqual(total, 1. / 6., places=9)
        self.assertGreaterEqual(removed, 0.)

    def test_cpu_case_rejects_open_lung_before_reporting_approximate_metrics(self):
        open_lung = fixtures.box(np.zeros(3), 1.)[:-1]
        tumor = fixtures.box(np.asarray((.5, .5, .5)), .1)
        with tempfile.TemporaryDirectory() as directory:
            for name in ('open-lung.stl', 'tumor.stl'):
                (Path(directory) / name).touch()
            with patch.object(ref, 'read_stl', side_effect=lambda p: tumor if p.name == 'tumor.stl' else open_lung):
                with self.assertRaisesRegex(ValueError, '闭合实体'):
                    PlanningCase(directory, ['open-lung.stl'], 'tumor.stl', ray_mode='cpu')


if __name__ == '__main__':
    unittest.main()
