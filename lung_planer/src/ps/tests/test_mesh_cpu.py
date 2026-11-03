import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.mesh_cpu import CpuMeshIndex, union_crossings
from cas_frontend.mesh_triangle import _point_triangle_distance
from cas_frontend.planning_geometry import PlanningCase
from cas_frontend.planning_inputs import anatomical_lung_side, is_lung_surface, is_lesion
from cas_frontend import planner_reference as ref
import test_adaptive_planner as fixtures


class CpuMeshTests(unittest.TestCase):
    def test_filename_roles_include_segment_solids_and_exclude_airways_vessels_lesion(self):
        for name in ('LeftUpperLobe.stl', 'Bronchus_plan_0_seg_1RU.stl',
                     'sub/BRONCHUS_PLAN_0_seg_6RL.STL', '肺叶.stl'):
            self.assertTrue(is_lung_surface(name), name)
        for name in ('Bronchus.stl', 'PulmonaryArtery.stl', 'PulmonaryVenous.stl',
                     'LungTumor1.stl', 'Bronchus_plan_tumor.stl', '肺囊肿.stl'):
            self.assertFalse(is_lung_surface(name), name)
        self.assertTrue(is_lesion('肺囊肿.stl'))

    def test_anatomical_side_detects_lobe_and_segment_labels(self):
        for name in ('LeftUpperLobe.stl', 'Bronchus_plan_0_seg_1LU.stl',
                     'Bronchus_plan_0_seg_5LL.stl'):
            self.assertEqual(anatomical_lung_side(name), 'left')
        for name in ('RightLowerLobe.stl', 'Bronchus_plan_0_seg_1RU.stl',
                     'Bronchus_plan_0_seg_4RM.stl'):
            self.assertEqual(anatomical_lung_side(name), 'right')
        for name in ('Bronchus.stl', 'PulmonaryArtery.stl', 'LungTumor1.stl'):
            self.assertIsNone(anatomical_lung_side(name))

    def test_bilateral_entry_base_must_stay_on_lesion_side_of_midline(self):
        case = object.__new__(PlanningCase)
        case._target_side_origin = np.zeros(3)
        case._target_side_normal = np.asarray((1., 0., 0.))
        self.assertTrue(case._base_stays_on_target_side(
            ((12., 0., 0.), (18., 1., 0.), (15., -1., 1.)), 1.))
        self.assertFalse(case._base_stays_on_target_side(
            ((12., 0., 0.), (18., 1., 0.), (-3., -1., 1.)), 1.))
        self.assertFalse(case._base_stays_on_target_side(
            ((9.9, 0., 0.), (18., 1., 0.), (15., -1., 1.)), 1.))
        case._target_side_origin = None
        self.assertTrue(case._base_stays_on_target_side(
            ((-5., 0., 0.), (2., 1., 0.), (3., -1., 1.)), 1.))

    def test_index_matches_original_single_solid_ray_and_distance(self):
        case = fixtures.AdaptivePlannerTests().make_case()
        accelerated = case._cpu_index
        case._cpu_index = None
        rng = np.random.default_rng(543)
        for _ in range(60):
            origin = rng.uniform(-20., 20., size=3)
            direction = rng.normal(size=3)
            direction /= np.linalg.norm(direction)
            np.testing.assert_allclose(accelerated.hits(origin, direction), case._hits_cpu(origin, direction), atol=1e-7)
            self.assertAlmostEqual(accelerated.distance(origin), case.distance(origin), places=8)
        for direction in ((1., 0., 0.), (-1., 0., 0.), (0., 1., 0.), (0., 0., -1.)):
            for origin in ((0., 0., 0.), (25., 0., 0.), (25., 11., 0.)):
                np.testing.assert_allclose(accelerated.hits(origin, direction), case._hits_cpu(origin, direction))

    def test_index_distance_agrees_with_scalar_all_triangle_reference(self):
        rng = np.random.default_rng(91)
        mesh = rng.normal(size=(200, 3, 3)) * 10.
        index = CpuMeshIndex(mesh, leaf_size=8)
        for point in rng.uniform(-20., 20., size=(12, 3)):
            expected = min(_point_triangle_distance(point, triangle) for triangle in mesh)
            self.assertAlmostEqual(index.distance(point), expected, places=8)

    def test_union_merges_touching_and_overlapping_segment_interfaces(self):
        for second_center in (np.asarray((2., 0., 0.)), np.asarray((1., 0., 0.))):
            first, second = fixtures.box(np.zeros(3), 1.), fixtures.box(second_center, 1.)
            mesh = np.asarray([t.points for t in first + second])
            index = CpuMeshIndex(mesh, np.r_[np.zeros(12, dtype=int),np.ones(12, dtype=int)], leaf_size=4)
            end = second_center[0] + 1.
            np.testing.assert_allclose(index.hits((-3., .2, .3), (1., 0., 0.)), (2., end + 3.))
            np.testing.assert_allclose(index.hits((0., .2, .3), (1., 0., 0.)), (end,))
            # A point in both solids is in their union, rather than outside
            # from even parity of concatenated surface crossings.
            if second_center[0] == 1.:
                self.assertEqual(len(index.hits((.5, .2, .3), (1., 0., 0.))) % 2, 1)

    def test_union_keeps_air_gap_between_disjoint_lobes(self):
        values = union_crossings(np.asarray((1., 2., 4., 5.)), np.asarray((0, 0, 1, 1)), 2)
        np.testing.assert_array_equal(values, (1., 2., 4., 5.))


if __name__ == '__main__':
    unittest.main()
