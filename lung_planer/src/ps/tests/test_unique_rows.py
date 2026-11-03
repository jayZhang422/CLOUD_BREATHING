"""unique_rows must return what np.unique(axis=0, return_inverse=True) returns."""
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.mesh_triangle import mesh_is_watertight, unique_rows


def numpy_reference(rows):
    vertices, inverse = np.unique(rows, axis=0, return_inverse=True)
    return vertices, inverse.reshape(-1)


class UniqueRowsTests(unittest.TestCase):
    def assert_same(self, rows):
        expected_vertices, expected_inverse = numpy_reference(rows)
        vertices, inverse = unique_rows(rows)
        np.testing.assert_array_equal(vertices, expected_vertices)
        np.testing.assert_array_equal(inverse, expected_inverse)
        np.testing.assert_array_equal(vertices[inverse], rows)

    def test_matches_numpy_on_float_and_integer_rows(self):
        rng = np.random.default_rng(5)
        triangles = rng.uniform(-50., 50., (4000, 3))
        # Shared vertices, as in a real mesh: every vertex appears in several faces.
        shared = triangles[rng.integers(0, 1500, 12000)]
        for rows in (shared,
                     rng.integers(-3, 3, (3000, 3)).astype(np.int64),
                     rng.integers(0, 40, (5000, 2)).astype(np.int64),
                     rng.normal(0., 1e-9, (500, 3)),
                     triangles[:1]):
            with self.subTest(shape=rows.shape, dtype=str(rows.dtype)):
                self.assert_same(rows)

    def test_signed_zero_is_one_row_like_numpy(self):
        rows = np.array([[0., 1., 2.], [-0., 1., 2.], [0., -0., 2.], [0., 0., 2.]])
        vertices, inverse = unique_rows(rows)
        expected_vertices, expected_inverse = numpy_reference(rows)
        self.assertEqual(len(vertices), len(expected_vertices))
        np.testing.assert_array_equal(inverse, expected_inverse)
        np.testing.assert_array_equal(vertices, expected_vertices)

    def test_empty_and_nonfinite_use_numpy_semantics(self):
        for rows in (np.empty((0, 3)), np.array([[np.nan, 0., 1.], [np.nan, 0., 1.], [1., 2., 3.]])):
            with self.subTest(rows=rows.tolist()):
                vertices, inverse = unique_rows(rows)
                expected_vertices, expected_inverse = numpy_reference(rows)
                np.testing.assert_array_equal(vertices, expected_vertices)
                np.testing.assert_array_equal(inverse, expected_inverse)

    def test_watertight_check_unchanged(self):
        # A closed tetrahedron is watertight; dropping a face opens it.
        a, b, c, d = (0., 0., 0.), (1., 0., 0.), (0., 1., 0.), (0., 0., 1.)
        closed = np.array([(a, c, b), (a, b, d), (b, c, d), (c, a, d)], dtype=float)
        self.assertTrue(mesh_is_watertight(closed))
        self.assertFalse(mesh_is_watertight(closed[:3]))
        doubled = np.concatenate((closed, closed))
        self.assertFalse(mesh_is_watertight(doubled))


if __name__ == '__main__':
    unittest.main()
