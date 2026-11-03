"""Check batching against the independent scalar clipping reference."""
import unittest

import numpy as np

from cas_frontend import planner_reference as ref
from cas_frontend.surface_clip import clipped_surface


def scalar_surface(source, faces):
    valid = np.ones(len(source), dtype=bool)
    for a, _, _, n in faces:
        valid &= np.any(np.einsum('nti,i->nt', source - a, n) <= 1e-8, axis=1)
    area, triangles = 0., []
    for tri in source[valid]:
        polygon = list(map(tuple, tri))
        for a, _, _, n in faces:
            polygon = ref.clip_polygon(polygon, a, n)
            if len(polygon) < 3:
                break
        for i in range(1, len(polygon) - 1):
            triangle = (polygon[0], polygon[i], polygon[i + 1])
            area += ref.tri_area(*triangle)
            triangles.append(triangle)
    return area / 100., np.asarray(triangles, dtype=np.float32).reshape(-1, 3, 3)


class SurfaceClipTests(unittest.TestCase):
    def compare(self, source, faces):
        expected_area, expected_triangles = scalar_surface(source, faces)
        area, triangles = clipped_surface(source, faces)
        self.assertEqual(area, expected_area)
        np.testing.assert_array_equal(triangles, expected_triangles)

    def test_random_tetrahedra_exact_area_and_triangle_order(self):
        rng = np.random.default_rng(20261016)
        source = rng.normal(size=(1200, 3, 3)) * 100.
        for _ in range(20):
            vertices = rng.normal(size=(4, 3)) * 80.
            faces = ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3]))
            self.compare(source, faces)

    def test_threshold_degenerate_and_empty_polygons(self):
        rng = np.random.default_rng(7016)
        source = rng.normal(size=(400, 3, 3))
        # Exercise exact boundary, both adjacent floating-point values, and
        # positive distances that are inside the original tolerance.
        source[..., 0] = rng.choice([0., 1e-8, np.nextafter(1e-8, 0.),
                                    np.nextafter(1e-8, np.inf), -1e-8, 2e-8], (400, 3))
        source[0] = 0.
        source[1, 1:] = source[1, 0]
        faces = [(np.zeros(3), None, None, np.array(n, dtype=float))
                 for n in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, 0, 1))]
        for count in range(1, 5):
            self.compare(source, faces[:count])
        self.compare(np.empty((0, 3, 3)), faces)
        self.compare(np.full((2, 3, 3), 10.), faces)

    def test_no_planes_and_inside_triangles(self):
        source = np.arange(90, dtype=float).reshape(-1, 3, 3)
        self.compare(source, [])
        self.compare(source, [(np.ones(3) * 100, None, None, np.ones(3))])


if __name__ == '__main__':
    unittest.main()
