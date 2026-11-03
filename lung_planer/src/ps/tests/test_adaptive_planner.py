"""Geometry regressions for complete lesion and continuous base constraints."""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import planner_reference as ref
from cas_frontend.planning_geometry import PlanningCase
from cas_frontend.mesh_triangle import triangle_mesh_min_distance, triangle_triangle_distance


def box(center, half):
    vertices = np.asarray([(x, y, z) for x in (-1., 1.)
                           for y in (-1., 1.) for z in (-1., 1.)]) * half + center
    faces = ((0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5),
             (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6),
             (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3))
    return [ref.Triangle(*map(tuple, vertices[list(face)])) for face in faces]


PARAMS = dict(yaw=-34., pitch=-44., margin=2.5, baseOffset=2.,
              padding=1.05, minClearance=.4, rotation=60., baseArea=0.)


class AdaptivePlannerTests(unittest.TestCase):
    def test_connected_lesions_rank_by_enclosed_volume(self):
        small = box(np.asarray((0., 0., 0.)), 1.)
        large = box(np.asarray((20., 0., 0.)), 2.)
        components = ref.connected_components(small + large)
        ranked = sorted(components, key=ref.closed_mesh_volume, reverse=True)
        self.assertEqual(len(components), 2)
        self.assertAlmostEqual(ref.closed_mesh_volume(ranked[0]), 64.)
        self.assertAlmostEqual(ref.closed_mesh_volume(ranked[1]), 8.)
        self.assertEqual(len(ref.largest_component(small + large)), len(small))

    def make_case(self, center=(7., 1., 1.), fragment=False, open_lung=False):
        lung = box(np.zeros(3), 10.)
        if open_lung:
            lung.pop()
        tumor = box(np.asarray(center), .8)
        if fragment:
            tumor += [ref.Triangle((50., 50., 50.), (51., 50., 50.), (50., 51., 50.))]
        with tempfile.TemporaryDirectory() as directory:
            for name in ('lung.stl', 'tumor.stl'):
                (Path(directory) / name).touch()
            with patch.object(ref, 'read_stl', side_effect=lambda path: tumor if path.name == 'tumor.stl' else lung):
                return PlanningCase(directory, ['lung.stl'], 'tumor.stl', ray_mode='cpu')

    def test_load_keeps_only_largest_lesion_component(self):
        case = self.make_case(fragment=True)
        self.assertEqual(len(case.points), 36)
        self.assertLess(case.points.max(), 10.)

    def test_overlapping_bounds_do_not_reject_by_centroid(self):
        case = self.make_case((10.2, 1., 1.))
        case.search_diagnostics = {}
        # The center is outside but part of the lesion crosses the boundary;
        # bounds preflight must leave geometric feasibility to the search.
        self.assertFalse(case.inside(case.center))
        case._check_planning_overlap()

    def test_nearest_direction_moves_with_lesion_location(self):
        for x, sign in ((7., 1.), (-7., -1.)):
            case = self.make_case((x, 1., 1.))
            directions = [np.asarray(ref.direction_for(*angles)) for angles in case._candidate_directions()]
            self.assertTrue(any(np.dot(direction, (sign, 0., 0.)) > .999999 for direction in directions))
            # The local 25 directions must follow the nearest surface, beyond
            # the common 24 global directions.
            near = sum(np.dot(direction, (sign, 0., 0.)) > .49 for direction in directions)
            far = sum(np.dot(direction, (-sign, 0., 0.)) > .49 for direction in directions)
            self.assertGreater(near, far + 15)

    def test_continuous_check_rejects_crossing_between_samples(self):
        case = self.make_case()
        base = np.asarray(((-25., -25., 0.), (25., -25., 0.), (0., 25., 0.)))
        # Even if all legacy samples are incorrectly reported outside and
        # distant, continuous geometry must reject the crossing.
        with patch.object(case, '_inside_many', return_value=np.zeros(121, dtype=bool)), \
             patch.object(case, '_distance_many', return_value=np.full(121, 5.)):
            valid, gap, _ = case.validate_base(base, .4)
        self.assertFalse(valid)
        self.assertEqual(gap, 0.)

    def test_enclosed_triangle_and_insufficient_gap_are_rejected(self):
        case = self.make_case()
        base = np.asarray(((0., 0., 0.), (1., 0., 0.), (0., 1., 0.)))
        self.assertFalse(case.validate_base(base, .4)[0])
        outside = base + (0., 0., 10.2)
        self.assertFalse(case.validate_base(outside, .4)[0])
        self.assertTrue(case.validate_base(base + (0., 0., 11.), .4)[0])

    def test_tiny_coverage_shortfall_and_clearance_shortfall_are_invalid(self):
        case = self.make_case()
        pose = dict(PARAMS, yaw=case._angles_for_direction((1., 0., 0.))[0], pitch=0., safetyFit=True)
        vertices = case.build(pose)
        for coverage, clearance in ((99.99999, 1.), (100., .4 - 5e-8)):
            with patch.object(case, 'coverage', return_value=(coverage, clearance,
                    ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3])))):
                result, _ = case.evaluate(vertices, pose)
            self.assertFalse(result['valid'])

    def test_vectorized_continuous_distance_matches_scalar_feature_reference(self):
        rng = np.random.default_rng(125)
        for _ in range(50):
            base = rng.normal(size=(3, 3))
            mesh = rng.normal(size=(8, 3, 3)) + rng.uniform(-3., 3., size=(1, 1, 3))
            expected = min(triangle_triangle_distance(base, tri) for tri in mesh)
            self.assertAlmostEqual(triangle_mesh_min_distance(base, mesh), expected, places=8)


if __name__ == '__main__':
    unittest.main()
