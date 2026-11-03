import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from scipy.ndimage import distance_transform_edt

from cas_frontend.voxel_mask import (VoxelMask, from_npy, distance_queries_reference,
                                    integer_axis_weights, SCHEMA)


class VoxelMaskTests(unittest.TestCase):
    def volume(self, data, spacing=(.8, .8, .8)):
        return VoxelMask(data, spacing, [10, 20, 30], np.eye(3), {'synthetic': True})

    def test_sparse_queries_equal_edt_on_random_masks_and_anisotropic_spacing(self):
        rng = np.random.default_rng(9021)
        for spacing in ((.8, .8, .8), (.5, .8, 2.3)):
            for _ in range(8):
                data = rng.random((9, 11, 7)) > .15
                data[0, 0, 0] = False
                volume = self.volume(data, spacing)
                coords = np.argwhere(data)[::9]
                expected = distance_transform_edt(data, sampling=spacing)[tuple(coords.T)]
                np.testing.assert_allclose(distance_queries_reference(volume, coords), expected,
                                           rtol=1e-14, atol=1e-14)

    def test_sparse_queries_boundaries_deep_interior_and_explicit_nonconvergence(self):
        data = np.ones((17, 15, 13), dtype=np.uint8)
        data[0, 0, 0] = 0
        coords = np.array([[0, 0, 0], [16, 14, 12], [8, 7, 6]])
        volume = self.volume(data)
        expected = distance_transform_edt(data, sampling=.8)[tuple(coords.T)]
        np.testing.assert_allclose(distance_queries_reference(volume, coords), expected)
        with self.assertRaisesRegex(RuntimeError, '未收敛'):
            distance_queries_reference(volume, coords, max_radius=1)
        with self.assertRaisesRegex(ValueError, '越界'):
            distance_queries_reference(volume, np.array([[-1, 0, 0]]))
        with self.assertRaisesRegex(ValueError, '背景'):
            distance_queries_reference(self.volume(np.ones((3, 3, 3))), np.array([[1, 1, 1]]))

    def test_npy_axis_labels_and_rotated_world_alignment(self):
        direction = [[0, -1, 0], [1, 0, 0], [0, 0, -1]]
        meta = dict(schema=SCHEMA, spacing_mm=[.5, 1, 2], origin_mm=[10, 20, 30],
                    direction=direction, axis_order='zyx', foreground_labels=[7],
                    coordinate_frame='stl-mm', units='mm', index_location='voxel-center')
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'artery.npy'
            raw = np.zeros((5, 4, 3), np.uint8)
            raw[3, 2, 1] = 7
            np.save(path, raw)
            sidecar = path.with_suffix('.npy.json')
            with self.assertRaisesRegex(ValueError, '元数据'):
                from_npy(path)
            sidecar.write_text(json.dumps(meta), encoding='utf-8')
            volume = from_npy(path)
            self.assertEqual(volume.data.shape, (3, 4, 5))
            self.assertEqual(volume.data[1, 2, 3], 1)
            np.testing.assert_allclose(volume.world([[1, 2, 3]]), [[8, 20.5, 24]])
            self.assertTrue(volume.data.flags.c_contiguous)
            self.assertFalse(volume.data.flags.writeable)
            fingerprint = volume.fingerprint()
            meta['origin_mm'][0] += 1
            sidecar.write_text(json.dumps(meta), encoding='utf-8')
            self.assertNotEqual(from_npy(path).fingerprint(), fingerprint)
            del meta['direction']
            sidecar.write_text(json.dumps(meta), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'direction'):
                from_npy(path)

    def test_invalid_geometry_and_probabilities_rejected(self):
        with self.assertRaisesRegex(ValueError, '正交'):
            VoxelMask(np.zeros((3, 3, 3)), [1, 1, 1], [0, 0, 0],
                      [[1, 1, 0], [0, 1, 0], [0, 0, 1]], {})
        with self.assertRaisesRegex(ValueError, '标签'):
            self.volume(np.full((3, 3, 3), .5))
        with self.assertRaisesRegex(ValueError, '正数'):
            self.volume(np.zeros((3, 3, 3)), (0, 1, 1))

    def test_integer_weights_preserve_exact_decimal_spacing_ratios(self):
        np.testing.assert_array_equal(integer_axis_weights((.8, .8, .8)), [1, 1, 1])
        np.testing.assert_array_equal(integer_axis_weights((.5, .8, 2.3)), [25, 64, 529])
        np.testing.assert_array_equal(integer_axis_weights((1.25, 2.5, 5)), [1, 4, 16])
        with self.assertRaisesRegex(ValueError, '没有量化'):
            integer_axis_weights((.123456789, .987654321, 1.))


if __name__ == '__main__':
    unittest.main()
