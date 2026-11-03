import tempfile
import unittest
from unittest.mock import Mock, patch
from copy import deepcopy
from hashlib import sha256
import json
from pathlib import Path

import numpy as np

from cas_frontend.centerlines import grade_forest, graph_from_mask
from cas_frontend.mask_centerlines import extract_volume_cached, extract_source_cached, _preserve_stl_roots
from cas_frontend.voxel_mask import (VoxelMask, distance_queries_reference,
                                    distance_queries_ps_sparse)


class MaskCenterlineTests(unittest.TestCase):
    def volume(self):
        mask = np.zeros((31, 31, 15), bool)
        grid = np.indices(mask.shape).transpose(1, 2, 3, 0)
        for t in np.linspace(0, 1, 80):
            for a, b in [((3, 15, 7), (15, 15, 7)), ((15, 15, 7), (27, 5, 7)),
                         ((15, 15, 7), (27, 25, 7))]:
                point = np.asarray(a)*(1-t)+np.asarray(b)*t
                mask |= ((grid-point)**2).sum(axis=3) <= 4.
        return VoxelMask(mask, [.8]*3, [10, 20, 30], np.eye(3), dict(synthetic=True))

    def test_sparse_oracle_preserves_reference_forest_and_cache_is_backend_specific(self):
        volume = self.volume()
        query = Mock(side_effect=lambda coords: distance_queries_reference(volume, coords))
        with tempfile.TemporaryDirectory() as folder:
            ps = extract_volume_cached(volume, folder)
            sparse = extract_volume_cached(volume, folder, backend='pl', distance_queries=query)
            self.assertEqual(query.call_count, 1)
            self.assertNotEqual(ps['cache_key'], sparse['cache_key'])
            self.assertEqual(ps['nodes'], sparse['nodes'])
            self.assertEqual(ps['branches'], sparse['branches'])
            self.assertEqual(ps['roots'], sparse['roots'])
            cached = extract_volume_cached(volume, folder, backend='pl', distance_queries=query)
            self.assertTrue(cached['cache_hit'])
            self.assertEqual(query.call_count, 1)
            self.assertEqual(cached['execution']['pl_calls'], 0)
            self.assertEqual(cached['geometry_smoothing'], 'mask-constrained-gaussian-v1')
            self.assertEqual(cached['repaired_gap_count'], 0)
            with self.assertRaisesRegex(RuntimeError, '没有 CPU 回退'):
                extract_volume_cached(volume, folder, backend='pl')

    def test_sparse_ps_distances_are_exact_for_anisotropic_and_boundary_queries(self):
        from scipy.ndimage import distance_transform_edt

        rng = np.random.default_rng(4421)
        data = rng.random((19, 17, 13)) > .37
        data[[0, -1], :, :] = False
        data[:, [0, -1], :] = False
        data[:, :, [0, -1]] = False
        volume = VoxelMask(data, [.5, .8, 2.3], [3., 4., 5.], np.eye(3), {})
        coords = np.indices(data.shape).reshape(3, -1).T
        edt, nearest_indices = distance_transform_edt(
            data, sampling=volume.spacing, return_indices=True)
        expected = edt[tuple(coords.T)]
        actual = distance_queries_ps_sparse(volume, coords)
        np.testing.assert_allclose(actual, expected, rtol=0, atol=1e-10)
        nearest = nearest_indices[:, coords[:, 0], coords[:, 1], coords[:, 2]].T
        exact_formula = np.sqrt(np.sum(((nearest - coords) * volume.spacing) ** 2, axis=1))
        np.testing.assert_array_equal(actual, exact_formula)

    def test_vectorized_adjacency_and_sparse_ps_match_v11_graph(self):
        volume = self.volume()
        reference = grade_forest(graph_from_mask(
            volume.data, volume.origin, volume.spacing, adjacency_backend='python'))
        optimized = grade_forest(graph_from_mask(
            volume.data, volume.origin, volume.spacing,
            distance_queries=lambda coords: distance_queries_ps_sparse(volume, coords),
            adjacency_backend='vectorized'))
        for key in ('skeleton_voxels', 'component_count', 'cyclic_components', 'roots'):
            self.assertEqual(reference[key], optimized[key])
        self.assertEqual(len(reference['nodes']), len(optimized['nodes']))
        self.assertEqual(len(reference['branches']), len(optimized['branches']))
        for a, b in zip(reference['nodes'], optimized['nodes']):
            self.assertEqual(a['id'], b['id'])
            np.testing.assert_allclose(a['point'], b['point'], rtol=0, atol=1e-10)
            self.assertAlmostEqual(a['radius_mm'], b['radius_mm'], delta=1e-10)
        for a, b in zip(reference['branches'], optimized['branches']):
            for key in ('id', 'start', 'end', 'generation', 'parent', 'children',
                        'root', 'component', 'provisional'):
                self.assertEqual(a[key], b[key])
            for key in ('points', 'radii_mm', 'length_mm', 'diameter_mm'):
                np.testing.assert_allclose(a[key], b[key], rtol=0, atol=1e-10)

    def test_world_direction_changes_geometry_without_changing_connectivity(self):
        volume = self.volume()
        direction = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]])
        base = grade_forest(graph_from_mask(volume.data, [0, 0, 0], volume.spacing))
        transformed = grade_forest(graph_from_mask(volume.data, volume.origin, volume.spacing,
                                                   direction=direction))
        for a, b in zip(base['branches'], transformed['branches']):
            self.assertEqual((a['start'], a['end'], a['generation']), (b['start'], b['end'], b['generation']))
            np.testing.assert_allclose(np.asarray(a['points']) @ direction.T+volume.origin, b['points'])
            self.assertAlmostEqual(a['length_mm'], b['length_mm'])
        with self.assertRaisesRegex(ValueError, '没有 CPU 回退'):
            graph_from_mask(volume.data, volume.origin, volume.spacing,
                            distance_queries=lambda c: np.zeros(len(c)))

    def test_source_index_avoids_revoxelization_and_rejects_changed_source(self):
        volume = self.volume()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'Bronchus.stl'
            path.write_bytes(b'synthetic-stl-source')
            volume.source['sha256'] = sha256(path.read_bytes()).hexdigest()
            with patch('cas_frontend.mask_centerlines.from_stl', return_value=volume) as voxelize:
                first = extract_source_cached(path, folder)
                cached = extract_source_cached(path, folder)
                self.assertFalse(first['cache_hit'])
                self.assertTrue(cached['cache_hit'])
                self.assertEqual(voxelize.call_count, 1)
                self.assertEqual(cached['hardware_runs'], [])
                path.write_bytes(b'changed-source')
                volume.source['sha256'] = sha256(path.read_bytes()).hexdigest()
                extract_source_cached(path, folder)
                self.assertEqual(voxelize.call_count, 2)

    def test_legacy_roots_migrate_only_when_entire_paths_match(self):
        volume = self.volume()
        tree = grade_forest(graph_from_mask(volume.data, volume.origin, volume.spacing))
        tree.update(source_sha256='synthetic', cache_key='new-graph')
        old_key = sha256(f'centerlines-lee-v2|synthetic|0.8'.encode()).hexdigest()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/(old_key+'.roots.json')).write_text(json.dumps(dict(roots=tree['roots'])))
            modified = deepcopy(tree)
            modified['branches'][0]['points'][1][0] += 1
            old_path = root/(old_key+'.json')
            old_path.write_text(json.dumps(modified))
            _preserve_stl_roots(tree, root/'Bronchus.stl', .8, folder)
            target = root/'new-graph.roots.json'
            self.assertFalse(target.exists())
            modified = deepcopy(tree)
            modified['branches'][0]['points'][1][0] += .1
            old_path.write_text(json.dumps(modified))
            _preserve_stl_roots(tree, root/'Bronchus.stl', .8, folder)
            self.assertEqual(json.loads(target.read_text())['roots'], tree['roots'])


if __name__ == '__main__':
    unittest.main()
