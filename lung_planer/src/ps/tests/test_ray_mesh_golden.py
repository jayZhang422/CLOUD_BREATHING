import sys
import unittest
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.mesh_bvh import build_mesh_image
from cas_frontend.ray_golden import collapse_crossings, inside_intervals, volume_fraction
from cas_frontend.planning_geometry import PlanningCase


class RayMeshGoldenTests(unittest.TestCase):
    def test_nonconvex_intervals_and_shared_crossings(self):
        crossings = collapse_crossings([4, 1, 2, 3, 2.000001])
        np.testing.assert_allclose(crossings, [1, 2, 3, 4])
        np.testing.assert_allclose(inside_intervals(crossings, 5, False), [[1, 2], [3, 4]])
        self.assertAlmostEqual(volume_fraction(crossings, 5, False), (8-1+64-27)/125)
        np.testing.assert_allclose(inside_intervals([2, 4], 5, True), [[0, 2], [4, 5]])

    def test_closed_mesh_golden_geometry(self):
        from tools.prepare_ray_mesh_golden import box, crossings
        convex = box((-1,-1,-1), (1,1,1))
        raw, hits = crossings(convex, [-6,0,0], [1,0,0])
        self.assertEqual(len(raw), 4)
        np.testing.assert_allclose(hits, [5,7])
        _, inside_hits = crossings(convex, [0,0,0], [1,0,0])
        np.testing.assert_allclose(inside_hits, [1])
        nonconvex = np.concatenate([box((-4,-1,-1),(-1,1,1)), box((1,-1,-1),(4,1,1))])
        _, hits = crossings(nonconvex, [-6,0,0], [1,0,0])
        np.testing.assert_allclose(hits, [2,5,7,10])
        np.testing.assert_allclose(inside_intervals(hits,12,False), [[2,5],[7,10]])

    def test_fixed_triangle_edge_parallel_and_degenerate(self):
        from tools.prepare_ray_mesh_golden import ray_triangle_fixed
        tri = [[-65536,-65536,0],[65536,-65536,0],[-65536,65536,0]]
        hit = ray_triangle_fixed([0,0,65536],[0,0,-65536],tri)
        self.assertTrue(hit['hit'])
        self.assertEqual(hit['t_q16'],65536)
        parallel = ray_triangle_fixed([0,0,65536],[65536,0,0],tri)
        self.assertFalse(parallel['hit'])
        self.assertEqual(parallel['error'],1)
        degenerate = ray_triangle_fixed([0,0,65536],[0,0,-65536],[[0,0,0]]*3)
        self.assertEqual(degenerate['error'],1)

    def test_bvh_bounds_order_and_layout(self):
        rng = np.random.default_rng(19)
        triangles = rng.uniform(-100, 100, (129, 3, 3))
        image = build_mesh_image(triangles)
        second = build_mesh_image(triangles)
        self.assertEqual(image.node_bytes, second.node_bytes)
        self.assertEqual(len(image.node_bytes), len(image.nodes)*48)
        self.assertEqual(len(image.triangle_bytes), len(triangles)*48)
        np.testing.assert_array_equal(np.sort(image.order), np.arange(len(triangles)))
        signed = image.nodes[:, :6].view('<i4')
        packed = np.frombuffer(image.triangle_bytes, '<i4').reshape(-1, 12)[:, :9].reshape(-1, 3, 3)
        leaves = []
        for index, node in enumerate(image.nodes):
            if node[10] == 1:
                start, count = map(int, node[8:10])
                leaves.extend(range(start, start+count))
                self.assertTrue((packed[start:start+count] >= signed[index, :3]).all())
                self.assertTrue((packed[start:start+count] <= signed[index, 3:]).all())
            else:
                for child in node[6:8]:
                    self.assertGreater(int(child), index)
                    self.assertTrue((signed[int(child), :3] >= signed[index, :3]).all())
                    self.assertTrue((signed[int(child), 3:] <= signed[index, 3:]).all())
        self.assertEqual(sorted(leaves), list(range(len(triangles))))

    def test_solid_ids_follow_bvh_reordering_and_cache_identity(self):
        from cas_frontend.mesh_bvh import mesh_key
        triangles = np.asarray([
            [[0,0,0],[1,0,0],[0,1,0]],
            [[10,0,0],[11,0,0],[10,1,0]],
            [[2,0,0],[3,0,0],[2,1,0]],
        ], dtype=float)
        groups = np.asarray([0, 1, 0])
        image = build_mesh_image(triangles, leaf_size=1, solid_ids=groups)
        packed = np.frombuffer(image.triangle_bytes, '<i4').reshape(-1, 12)
        np.testing.assert_array_equal(packed[:, 9], groups[image.order])
        self.assertEqual(image.solid_count, 2)
        self.assertNotEqual(mesh_key(triangles, groups), mesh_key(triangles, [0, 0, 1]))

    def test_single_solid_word9_remains_zero(self):
        tri=np.asarray([[[-1,-1,0],[1,-1,0],[-1,1,0]]],dtype=float)
        words=np.frombuffer(build_mesh_image(tri).triangle_bytes,'<i4').reshape(-1,12)
        self.assertEqual(int(words[0,9]),0)

    def test_complete_requests_do_not_use_mesh_summary(self):
        case = object.__new__(PlanningCase)
        case.triangles = np.zeros((1, 3, 3))
        case._mesh_disabled = False
        case._mesh_evaluator = lambda *args: self.fail('summary ABI was called')
        case._ray_evaluator = None
        case._ray_disabled = False
        self.assertIsNone(case._ray_hits_many([[0,0,0]], [[0,0,1]], require_complete=True))

    def test_capacity_and_overflow_rejection(self):
        tri = np.asarray([[[-1,-1,0],[1,-1,0],[-1,1,0]]], dtype=float)
        image = build_mesh_image(np.repeat(tri, 100000, axis=0))
        self.assertEqual(len(image.triangle_bytes), 4800000)
        with self.assertRaises(ValueError):
            build_mesh_image(tri+40000)

    def test_capacity_hit_survives_at_reordered_ddr_tail(self):
        from tools.verify_ray_mesh_board import capacity_mesh
        image=build_mesh_image(capacity_mesh(8193))
        self.assertEqual(int(image.order[-1]),8192)


if __name__ == '__main__':
    unittest.main()
