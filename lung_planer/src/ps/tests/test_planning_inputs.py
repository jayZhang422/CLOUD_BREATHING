import tempfile
import unittest
from pathlib import Path
import sys
from unittest.mock import patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import planner_reference as ref
from cas_frontend.mesh_cpu import CpuMeshIndex
from cas_frontend.planning_inputs import _inside_many, auto_select_target_lung
from cas_frontend.ray_golden import inside_from_crossings


def box(center, half):
    vertices = np.asarray([(x, y, z) for x in (-1., 1.)
                           for y in (-1., 1.) for z in (-1., 1.)]) * half + center
    faces = ((0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5),
             (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6),
             (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3))
    return [ref.Triangle(*map(tuple, vertices[list(face)])) for face in faces]


class TargetLungSelectionTests(unittest.TestCase):
    def test_auto_selection_keeps_only_surface_containing_tumor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('near.stl', 'far.stl', 'tumor.stl'):
                (root / name).touch()
            near = box((0., 0., 0.), 10.)
            far = box((30., 0., 0.), 10.)
            tumor = box((2., 0., 0.), 1.)
            with patch.object(ref, 'read_stl', side_effect=lambda path:
                              tumor if path.name == 'tumor.stl' else
                              near if path.name == 'near.stl' else far):
                selected = auto_select_target_lung(root, ['near.stl', 'far.stl'],
                                                   'tumor.stl')
            self.assertEqual(selected, ['near.stl'])

    def test_box_prefilter_skips_ray_casts_without_changing_result(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('near.stl', 'far.stl', 'tumor.stl'):
                (root / name).touch()
            meshes = dict(near=box((0., 0., 0.), 10.), far=box((30., 0., 0.), 10.),
                          tumor=box((2., 0., 0.), 1.))
            module = auto_select_target_lung.__globals__
            original = module['_inside_many']

            def run(margin):
                calls = []

                def counting(index, origins, direction):
                    calls.append(len(origins))
                    return original(index, origins, direction)

                with patch.object(ref, 'read_stl', side_effect=lambda path: meshes[path.stem]), \
                     patch.dict(module, _inside_many=counting, _BOX_MARGIN_MM=margin):
                    selected = auto_select_target_lung(root, ['near.stl', 'far.stl'], 'tumor.stl')
                return selected, sum(calls)

            filtered, filtered_calls = run(1e-3)
            unfiltered, unfiltered_calls = run(1e6)
            self.assertEqual(filtered, unfiltered)
            self.assertEqual(filtered, ['near.stl'])
            # Only the near lung's box holds tumor points; the far lung is never ray-cast.
            self.assertGreater(filtered_calls, 0)
            self.assertEqual(unfiltered_calls, 2 * filtered_calls)

    def test_batched_inside_matches_per_ray_hits(self):
        # A UV sphere with several hundred faces spans many BVH leaves.
        rows, cols, radius = 24, 32, 10.
        grid = [[(radius * np.sin(np.pi * i / rows) * np.cos(2 * np.pi * j / cols),
                  radius * np.sin(np.pi * i / rows) * np.sin(2 * np.pi * j / cols),
                  radius * np.cos(np.pi * i / rows)) for j in range(cols + 1)]
                for i in range(rows + 1)]
        triangles = []
        for i in range(rows):
            for j in range(cols):
                a, b, c, d = grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1]
                triangles += [(a, b, c), (a, c, d)]
        mesh = np.asarray(triangles, dtype=np.float64)
        index = CpuMeshIndex(mesh)
        direction = np.asarray(ref.unit((1.0, .371, .217)))
        rng = np.random.default_rng(7)
        origins = rng.uniform(-13., 13., size=(1200, 3))
        # Rays through a vertex and along a face edge hit shared edges twice.
        origins[:3] = [(0., 0., 0.), (10., 0., 0.), (0., 0., 10.)]
        expected = np.asarray([inside_from_crossings(index.hits(p, direction)) for p in origins])
        with patch.dict(_inside_many.__globals__, _RAY_CHUNK=97):
            got = _inside_many(index, origins, direction)
        np.testing.assert_array_equal(got, expected)
        self.assertTrue(expected.any() and not expected.all())
        self.assertEqual(len(_inside_many(index, origins[:0], direction)), 0)

    def test_unreadable_or_ambiguous_input_keeps_explicit_list(self):
        self.assertEqual(auto_select_target_lung('.', ['a.stl', 'b.stl'], 'tumor.stl'),
                         ['a.stl', 'b.stl'])


if __name__ == '__main__':
    unittest.main()
