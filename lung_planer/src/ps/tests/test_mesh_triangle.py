import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cas_frontend.mesh_triangle import (
    closest_point_on_mesh,
    mesh_is_watertight,
    triangle_mesh_min_distance,
    triangle_triangle_distance,
)


class TriangleMeshDistanceTests(unittest.TestCase):
    def test_parallel_triangles_have_exact_surface_gap(self):
        first = np.asarray(((0., 0., 0.), (2., 0., 0.), (0., 2., 0.)))
        second = np.asarray(((0., 0., 2.), (2., 0., 2.), (0., 2., 2.)))
        self.assertAlmostEqual(triangle_triangle_distance(first, second), 2.)

    def test_crossing_and_coplanar_overlap_have_zero_distance(self):
        first = np.asarray(((0., 0., 0.), (2., 0., 0.), (0., 2., 0.)))
        crossing = np.asarray(((.5, .5, -1.), (.5, .5, 1.), (1.5, .5, 0.)))
        coplanar = np.asarray(((.5, .5, 0.), (2., .5, 0.), (.5, 2., 0.)))
        self.assertEqual(triangle_triangle_distance(first, crossing), 0.)
        self.assertEqual(triangle_triangle_distance(first, coplanar), 0.)

    def test_patch_to_mesh_prunes_by_triangle_bounds(self):
        patch = np.asarray(((0., 0., 0.), (1., 0., 0.), (0., 1., 0.)))
        mesh = np.asarray((
            ((0., 0., 3.), (1., 0., 3.), (0., 1., 3.)),
            ((0., 0., 1.25), (1., 0., 1.25), (0., 1., 1.25)),
        ))
        bounds = (mesh.min(axis=1), mesh.max(axis=1))
        self.assertAlmostEqual(triangle_mesh_min_distance(patch, mesh, bounds), 1.25)

    def test_closest_point_returns_face_and_location(self):
        mesh = np.asarray((((0., 0., 0.), (2., 0., 0.), (0., 2., 0.)),))
        point, face = closest_point_on_mesh((.5, .5, 2.), mesh)
        np.testing.assert_allclose(point, (.5, .5, 0.))
        self.assertEqual(face, 0)

    def test_watertight_check_rejects_open_surface(self):
        tetrahedron = np.asarray((
            ((0., 0., 0.), (1., 0., 0.), (0., 1., 0.)),
            ((0., 0., 0.), (0., 0., 1.), (1., 0., 0.)),
            ((0., 0., 0.), (0., 1., 0.), (0., 0., 1.)),
            ((1., 0., 0.), (0., 0., 1.), (0., 1., 0.)),
        ))
        self.assertTrue(mesh_is_watertight(tetrahedron))
        self.assertFalse(mesh_is_watertight(tetrahedron[:3]))


if __name__ == '__main__':
    unittest.main()
