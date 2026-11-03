import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cas_frontend.ray_mesh import (ABI_VERSION, RAY_BYTES, RESULT_BYTES,
                                   TRIANGLE_BYTES, decode_results, pack_mesh,
                                   pack_ray, pack_rays, validate_results)


class MeshRayAbiTests(unittest.TestCase):
    def test_mesh_and_ray_sizes_are_dma_friendly(self):
        mesh = pack_mesh([((0, 0, 0), (1, 0, 0), (0, 1, 0))])
        ray = pack_ray(7, (0, 0, 1), (0, 0, -1))
        self.assertEqual(len(mesh), TRIANGLE_BYTES)
        self.assertEqual(len(ray), RAY_BYTES)
        self.assertEqual(len(pack_rays([(0, 0, 1)], [(0, 0, -1)])), RAY_BYTES)

    def test_result_decode_and_order_validation(self):
        raw = (1).to_bytes(4, 'little') + (2).to_bytes(4, 'little') \
            + (3 * 65536).to_bytes(4, 'little') + (4 * 65536).to_bytes(4, 'little')
        values = decode_results(raw, 1)
        self.assertEqual(values[0].ray_id, 1)
        self.assertEqual(values[0].t_near_mm, 3.)
        self.assertEqual(values[0].t_far_mm, 4.)
        self.assertEqual(validate_results(values, 1)[0].hit_count, 2)
        self.assertEqual(ABI_VERSION, 0x00030000)
        self.assertEqual(RESULT_BYTES, 16)

    def test_ddr_capacity_packing(self):
        triangle = ((-1, -1, 0), (1, -1, 0), (-1, 1, 0))
        for count in (8002, 100000):
            raw = pack_mesh([triangle] * count)
            self.assertEqual(len(raw), count * TRIANGLE_BYTES)


if __name__ == '__main__':
    unittest.main()
