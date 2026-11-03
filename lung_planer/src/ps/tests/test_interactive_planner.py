import unittest
from unittest.mock import patch

import numpy as np

from cas_frontend.interactive_planner import external_patch


class _Index:
    low = np.zeros(3)
    high = np.ones(3)


class _Case:
    lung_files = ['lung.stl']
    triangles = np.asarray([[[0., 0., 0.], [10., 0., 0.], [0., 10., 0.]]])
    _triangle_groups = np.asarray([0])

    def to_physical_vertices(self, vertices):
        return np.asarray(vertices, dtype=float) * np.asarray((2., 3., 4.))

    def to_source_vertices(self, vertices):
        return np.asarray(vertices, dtype=float) / np.asarray((2., 3., 4.))


class InteractivePlannerCoordinateTests(unittest.TestCase):
    def test_external_patch_converts_viewer_source_vertices_to_physical_mm(self):
        source_vertices = np.asarray(((1., 2., 3.), (2., 2., 3.),
                                      (1., 3., 3.), (1., 2., 4.)))
        faces_seen = []

        def clipped(source, faces):
            faces_seen.append(np.asarray(faces))
            return 1., np.ones((1, 3, 3))

        with patch('cas_frontend.interactive_planner.CpuMeshIndex', return_value=_Index()), \
             patch('cas_frontend.interactive_planner.clipped_surface', side_effect=clipped), \
             patch('cas_frontend.interactive_planner._exposed_patch', side_effect=lambda patch, indices, tolerance: patch):
            _, display_patch = external_patch(_Case(), source_vertices)

        self.assertEqual(len(faces_seen), 1)
        np.testing.assert_allclose(faces_seen[0][0][0], (2., 6., 12.))
        np.testing.assert_allclose(faces_seen[0][0][1], (4., 6., 12.))
        np.testing.assert_allclose(faces_seen[0][0][2], (2., 9., 12.))
        np.testing.assert_allclose(faces_seen[0][1][1], (2., 6., 16.))
        np.testing.assert_allclose(display_patch[0], np.ones((3, 3)) / (2., 3., 4.))


if __name__ == '__main__':
    unittest.main()
