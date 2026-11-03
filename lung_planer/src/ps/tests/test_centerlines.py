"""Geometry and topology contracts for desktop branch analysis."""
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import numpy as np

from cas_frontend.centerlines import (structure_kind, grade_forest, graph_from_mask,
    clip_segments, analyze_resection, extract_cached, merge_intervals, tube_mesh, voxelize)
from cas_frontend.centerlines import (_connect_short_endpoint_gaps,
    _connect_short_endpoints_to_branches, validate_tree)


def tree_fixture():
    points = [(-3, 0, 0), (0, 0, 0), (3, 2, 0), (3, -2, 0)]
    nodes = [dict(id=i, point=list(p), radius_mm=2. if i == 0 else 1.) for i, p in enumerate(points)]
    branches = []
    for start, end in ((0, 1), (1, 2), (1, 3)):
        p = np.asarray([points[start], points[end]], dtype=float)
        branches.append(dict(id=len(branches), start=start, end=end, points=p.tolist(),
            radii_mm=[1., 1.], length_mm=float(np.linalg.norm(p[1] - p[0])), diameter_mm=2.))
    return grade_forest(dict(nodes=nodes, branches=branches))


TETRA = np.asarray(((0., 0., 0.), (4., 0., 0.), (0., 4., 0.), (0., 0., 4.)))


class CenterlineTests(unittest.TestCase):
    def test_merge_intervals_accepts_numpy_rows_and_merges_in_order(self):
        intervals = np.asarray(((4., 6.), (1., 2.), (2., 3.), (8., 8.)))
        self.assertEqual(merge_intervals(intervals), [(1., 3.), (4., 6.)])

    def test_filename_roles_exclude_lung_segment_surfaces(self):
        for name, kind in [('PulmonaryArtery.STL', 'artery'), ('PulmonaryVenous.stl', 'vein'),
                           ('Bronchus.stl', 'airway'), ('支气管.stl', 'airway'),
                           ('Bronchus_plan_0_seg_1LU.stl', None), ('RightLung.stl', None)]:
            self.assertEqual(structure_kind(name), kind)

    def test_rooted_y_tree_grades_and_parent_ids(self):
        tree = tree_fixture()
        self.assertEqual(tree['roots'], [0])
        self.assertEqual([b['generation'] for b in tree['branches']], [1, 2, 2])
        self.assertEqual(tree['branches'][0]['children'], [1, 2])
        grade_forest(tree, [2])
        self.assertEqual(tree['roots'], [2])
        self.assertEqual(tree['branches'][1]['start'], 2)
        self.assertEqual(tree['branches'][1]['points'][0], tree['nodes'][2]['point'])
        grade_forest(tree, [0])
        self.assertEqual([b['generation'] for b in tree['branches']], [1, 2, 2])

    def test_cycle_preserved_and_provisional_instead_of_claimed_tree(self):
        tree = tree_fixture()
        p = [tree['nodes'][2]['point'], tree['nodes'][3]['point']]
        tree['branches'].append(dict(id=3, start=2, end=3, points=p, radii_mm=[1., 1.],
                                     length_mm=4., diameter_mm=2.))
        grade_forest(tree)
        self.assertEqual(tree['cyclic_components'], 1)
        self.assertTrue(all(b['provisional'] for b in tree['branches']))
        self.assertEqual(sum(b['generation'] == 0 for b in tree['branches']), 1)

    def test_disconnected_roots_do_not_create_connections(self):
        tree = tree_fixture()
        tree['nodes'].extend([dict(id=4, point=[20, 0, 0], radius_mm=1),
                              dict(id=5, point=[22, 0, 0], radius_mm=1)])
        tree['branches'].append(dict(id=3, start=4, end=5, points=[[20, 0, 0], [22, 0, 0]],
                                     radii_mm=[1, 1], length_mm=2., diameter_mm=2.))
        grade_forest(tree)
        self.assertEqual(tree['component_count'], 2)
        self.assertEqual(tree['branches'][3]['generation'], 1)

    def test_outside_endpoints_crossing_is_detected(self):
        segments = np.asarray([[(-2., 1., 1.), (5., 1., 1.)]])
        valid, clipped, low, high = clip_segments(segments, TETRA)
        self.assertTrue(valid[0])
        np.testing.assert_allclose(clipped[0], [(0, 1, 1), (2, 1, 1)], atol=1e-10)
        self.assertAlmostEqual(low[0], 2 / 7)
        self.assertAlmostEqual(high[0], 4 / 7)

    def test_parallel_outside_inside_tangent_and_zero_length(self):
        segments = [[(.2, .2, .2), (.4, .4, .4)], [(-1, 0, 0), (-1, 4, 0)],
                    [(-1, 1, 0), (1, -1, 0)], [(1, 1, 1), (1, 1, 1)]]
        flags, *_ = clip_segments(segments, TETRA)
        self.assertEqual(flags.tolist()[:3], [True, False, False])
        # Zero-length segments cannot add any removed length.
        self.assertEqual(float(np.linalg.norm(np.diff(np.asarray(segments[-1]), axis=0))), 0.)

    def test_radius_expansion_is_only_a_possible_contact(self):
        segments = [[(-.2, .5, .5), (-.2, 1.5, .5)]]
        self.assertFalse(clip_segments(segments, TETRA)[0][0])
        self.assertTrue(clip_segments(segments, TETRA, .3)[0][0])

    def test_degenerate_and_nonfinite_tetra_rejected(self):
        for vertices in (np.zeros((4, 3)), TETRA * np.nan):
            with self.assertRaises(ValueError):
                clip_segments([[(0, 0, 0), (1, 1, 1)]], vertices)

    def test_downstream_connectivity_and_removed_lengths(self):
        tree = tree_fixture()
        # A tetra crossing only the root stem disconnects both distal arms.
        tetra = np.asarray([(-2., -2., -2.), (-2., 4., -2.), (-2., -2., 4.), (-.5, 0., 0.)])
        result = analyze_resection(tree, tetra)
        self.assertEqual(result['rows'][0]['status'], 'partial')
        self.assertGreater(result['rows'][0]['removed_length_mm'], 0)
        self.assertTrue(all(r['downstream_affected'] for r in result['rows'][1:]))

    def test_lung_intervals_exclude_extra_pulmonary_tetra_portion_and_are_cached(self):
        tree = tree_fixture()
        # The entire tree lies inside this large tetrahedron, but only x>1
        # on the two distal branches belongs to this synthetic lung region.
        tetra = np.asarray([(-20., -20., -20.), (80., -20., -20.),
                            (-20., 80., -20.), (-20., -20., 80.)])
        class Lung:
            calls = 0
            def hits(self, origin, direction):
                self.calls += 1
                if direction[0] <= 0:
                    return np.empty(0)
                entry = (1. - origin[0]) / direction[0]
                return np.asarray([entry, entry + 100.]) if entry >= 0 else np.asarray([100.])
        lung, cache = Lung(), {}
        result = analyze_resection(tree, tetra, lung, cache)
        self.assertEqual(result['rows'][0]['status'], 'outside')
        self.assertEqual(result['rows'][0]['removed_length_mm'], 0.)
        self.assertTrue(all(r['status'] == 'partial' for r in result['rows'][1:]))
        self.assertTrue(all(np.asarray(segment)[:, 0].min() >= 1 - 1e-6 for segment in result['removed_segments']))
        calls = lung.calls
        analyze_resection(tree, tetra, lung, cache)
        self.assertEqual(lung.calls, calls)

    def test_voxel_skeleton_of_known_y_has_a_branching_component(self):
        mask = np.zeros((31, 31, 15), dtype=bool)
        grid = np.indices(mask.shape).transpose(1, 2, 3, 0)
        for t in np.linspace(0, 1, 80):
            for a, b in [((3, 15, 7), (15, 15, 7)), ((15, 15, 7), (27, 5, 7)),
                         ((15, 15, 7), (27, 25, 7))]:
                point = np.asarray(a) * (1 - t) + np.asarray(b) * t
                mask |= ((grid - point) ** 2).sum(axis=3) <= 4.
        tree = grade_forest(graph_from_mask(mask, (0, 0, 0), 1.))
        self.assertEqual(tree['component_count'], 1)
        self.assertEqual(tree['cyclic_components'], 0)
        self.assertEqual(len(tree['branches']), 3)
        self.assertEqual(sorted(b['generation'] for b in tree['branches']), [1, 2, 2])

    def test_straight_oblique_lumen_skeleton_is_smoothed_without_changing_topology(self):
        x, y, z = np.indices((55, 35, 17))
        mask = (((y - (.42 * x + 5.)) ** 2 + (z - 8.) ** 2) <= 3.5 ** 2)
        mask &= (x >= 4) & (x <= 50)
        tree = grade_forest(graph_from_mask(mask, (0, 0, 0), .8))

        self.assertEqual(tree['geometry_smoothing'], 'mask-constrained-gaussian-v1')
        self.assertEqual(tree['component_count'], 1)
        self.assertEqual(len(tree['branches']), 1)
        points = np.asarray(tree['branches'][0]['points'])
        vectors = np.diff(points, axis=0)
        vectors /= np.maximum(np.linalg.norm(vectors, axis=1)[:, None], 1e-12)
        turns = np.arccos(np.clip(np.sum(vectors[:-1] * vectors[1:], axis=1), -1., 1.))
        self.assertLess(np.degrees(turns).sum(), 1620.)
        self.assertLess(tree['branches'][0]['length_mm'] /
                        np.linalg.norm(points[-1] - points[0]), 1.06)

    def test_single_slice_lumen_gap_is_repaired_without_touching_skeleton_topology(self):
        x, y, z = np.indices((45, 21, 21))
        mask = (((y - 10) ** 2 + (z - 10) ** 2) <= 3 ** 2)
        mask &= ((x >= 3) & (x <= 18)) | ((x >= 20) & (x <= 41))
        tree = grade_forest(graph_from_mask(mask, (0, 0, 0), .8))

        self.assertEqual(tree['component_count'], 1)
        self.assertEqual(tree['repaired_gap_count'], 1)
        self.assertEqual(sum(bool(b.get('gap_bridge')) for b in tree['branches']), 1)
        bridges = [b for b in tree['branches'] if b.get('gap_bridge')]
        self.assertLessEqual(bridges[0]['length_mm'], 4 * .8 + 1e-9)
        self.assertEqual(bridges[0]['gap_bridge_method'], 'mutual-directed-mask-support-v2')
        self.assertGreaterEqual(bridges[0]['mask_support_fraction'], .55)

    def test_endpoint_direction_uses_local_path_trend_instead_of_one_voxel_step(self):
        nodes = [dict(point=[8., 10., 2.]), dict(point=[5., 10., 2.]),
                 dict(point=[18., 10., 2.]), dict(point=[13., 10., 2.])]
        branches = [
            dict(id=0, start=0, end=1,
                 points=[[8., 10., 2.], [7.4, 10.8, 2.], [6., 10.3, 2.], [5., 10., 2.]],
                 radii_mm=[1.] * 4, length_mm=3.4, diameter_mm=2.),
            dict(id=1, start=2, end=3,
                 points=[[18., 10., 2.], [16., 10., 2.], [13., 10., 2.]],
                 radii_mm=[1.] * 3, length_mm=5., diameter_mm=2.)]
        mask = np.ones((24, 20, 5), dtype=bool)

        repaired = _connect_short_endpoint_gaps(nodes, branches, 1., mask, (0., 0., 0.))

        self.assertEqual(repaired, 1)
        self.assertEqual(branches[-1]['gap_bridge_method'], 'mutual-directed-mask-support-v2')
        self.assertGreaterEqual(branches[-1]['mask_support_fraction'], .55)

    def test_facing_fragment_attaches_to_trunk_interior_and_splits_branch(self):
        nodes = [dict(id=0, point=[3., 10., 2.], radius_mm=2.),
                 dict(id=1, point=[25., 10., 2.], radius_mm=2.),
                 dict(id=2, point=[14., 16., 2.], radius_mm=1.),
                 dict(id=3, point=[14., 18., 2.], radius_mm=1.)]
        branches = [
            dict(id=0, start=0, end=1,
                 points=[[3., 10., 2.], [14., 10., 2.], [25., 10., 2.]],
                 radii_mm=[2.] * 3, length_mm=22., diameter_mm=4.),
            dict(id=1, start=2, end=3,
                 points=[[14., 16., 2.], [14., 17., 2.], [14., 18., 2.]],
                 radii_mm=[1.] * 3, length_mm=2., diameter_mm=2.)]
        mask = np.ones((30, 24, 5), dtype=bool)

        repaired = _connect_short_endpoints_to_branches(nodes, branches, 1., mask, (0., 0., 0.))

        self.assertEqual(repaired, 1)
        tree = grade_forest(dict(nodes=nodes, branches=branches))
        self.assertEqual(tree['component_count'], 1)
        self.assertEqual(len(tree['branches']), 4)
        self.assertEqual(sum(b['length_mm'] for b in tree['branches'][:2]), 22.)
        self.assertEqual(tree['branches'][-1]['gap_bridge_method'],
                         'directed-mask-supported-tree-attachment-v2')
        self.assertEqual({tree['branches'][-1]['start'], tree['branches'][-1]['end']}, {2, 4})
        np.testing.assert_allclose(tree['nodes'][4]['point'], [14., 10., 2.])
        validate_tree(tree)

    def test_mask_supported_tip_attaches_across_a_wider_short_gap(self):
        nodes = [dict(id=0, point=[3., 10., 2.], radius_mm=3.),
                 dict(id=1, point=[25., 10., 2.], radius_mm=3.),
                 dict(id=2, point=[14., 17.2, 2.], radius_mm=1.),
                 dict(id=3, point=[14., 19.2, 2.], radius_mm=1.)]
        branches = [
            dict(id=0, start=0, end=1, points=[[3., 10., 2.], [25., 10., 2.]],
                 radii_mm=[3., 3.], length_mm=22., diameter_mm=6.),
            dict(id=1, start=2, end=3, points=[[14., 17.2, 2.], [14., 19.2, 2.]],
                 radii_mm=[1., 1.], length_mm=2., diameter_mm=2.)]
        mask = np.ones((30, 24, 5), dtype=bool)

        repaired = _connect_short_endpoints_to_branches(nodes, branches, 1., mask, (0., 0., 0.))

        self.assertEqual(repaired, 1)
        self.assertEqual(branches[-1]['gap_bridge_method'],
                         'directed-mask-supported-tree-attachment-v2')
        self.assertAlmostEqual(branches[-1]['length_mm'], 7.2)

    def test_wider_gap_still_requires_source_mask_support(self):
        nodes = [dict(id=0, point=[3., 10., 2.], radius_mm=3.),
                 dict(id=1, point=[25., 10., 2.], radius_mm=3.),
                 dict(id=2, point=[14., 17.2, 2.], radius_mm=1.),
                 dict(id=3, point=[14., 19.2, 2.], radius_mm=1.)]
        branches = [
            dict(id=0, start=0, end=1, points=[[3., 10., 2.], [25., 10., 2.]],
                 radii_mm=[3., 3.], length_mm=22., diameter_mm=6.),
            dict(id=1, start=2, end=3, points=[[14., 17.2, 2.], [14., 19.2, 2.]],
                 radii_mm=[1., 1.], length_mm=2., diameter_mm=2.)]
        mask = np.zeros((30, 24, 5), dtype=bool)

        repaired = _connect_short_endpoints_to_branches(nodes, branches, 1., mask, (0., 0., 0.))

        self.assertEqual(repaired, 0)

    def test_parallel_endpoint_away_from_trunk_is_not_attached(self):
        nodes = [dict(id=0, point=[3., 10., 2.], radius_mm=2.),
                 dict(id=1, point=[25., 10., 2.], radius_mm=2.),
                 dict(id=2, point=[14., 16., 2.], radius_mm=1.),
                 dict(id=3, point=[18., 16., 2.], radius_mm=1.)]
        branches = [
            dict(id=0, start=0, end=1,
                 points=[[3., 10., 2.], [25., 10., 2.]],
                 radii_mm=[2., 2.], length_mm=22., diameter_mm=4.),
            dict(id=1, start=2, end=3,
                 points=[[14., 16., 2.], [16., 16., 2.], [18., 16., 2.]],
                 radii_mm=[1.] * 3, length_mm=4., diameter_mm=2.)]
        mask = np.ones((30, 24, 5), dtype=bool)

        repaired = _connect_short_endpoints_to_branches(nodes, branches, 1., mask, (0., 0., 0.))

        self.assertEqual(repaired, 0)
        self.assertEqual(grade_forest(dict(nodes=nodes, branches=branches))['component_count'], 2)

    def test_two_slice_gap_is_repaired_only_with_mask_supported_facing_endpoints(self):
        x, y, z = np.indices((45, 21, 21))
        mask = (((y - 10) ** 2 + (z - 10) ** 2) <= 3 ** 2)
        mask &= ((x >= 3) & (x <= 18)) | ((x >= 21) & (x <= 41))
        tree = grade_forest(graph_from_mask(mask, (0, 0, 0), .8))

        bridges = [b for b in tree['branches'] if b.get('gap_bridge')]
        self.assertEqual(tree['component_count'], 1)
        self.assertEqual(len(bridges), 1)
        self.assertGreater(bridges[0]['length_mm'], 2 * .8)
        self.assertGreaterEqual(bridges[0]['mask_support_fraction'], .55)

    def test_near_endpoints_with_misaligned_tangents_are_not_repaired(self):
        mask = np.zeros((35, 35, 17), dtype=bool)
        mask[3:15, 14:21, 7:10] = True
        mask[17:29, 20:27, 7:10] = True
        tree = grade_forest(graph_from_mask(mask, (0, 0, 0), .8))

        self.assertGreater(tree['component_count'], 1)
        self.assertEqual(tree['repaired_gap_count'], 0)

    def test_content_cache_hit_changed_file_spacing_and_corruption(self):
        tree = tree_fixture()
        tree['skeleton_voxels'] = 4
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'Artery.stl'; source.write_bytes(b'source1')
            with patch('cas_frontend.centerlines.voxelize', return_value=(np.ones((3, 3, 3), bool), np.zeros(3), .8, 10)), \
                 patch('cas_frontend.centerlines.graph_from_mask', side_effect=lambda *a: deepcopy(tree)) as build:
                a = extract_cached(source, Path(folder) / 'cache')
                self.assertFalse(a['cache_hit'])
                b = extract_cached(source, Path(folder) / 'cache')
                self.assertTrue(b['cache_hit']); self.assertEqual(build.call_count, 1)
                source.write_bytes(b'source2')
                extract_cached(source, Path(folder) / 'cache')
                extract_cached(source, Path(folder) / 'cache', .4)
                self.assertEqual(build.call_count, 3)
                (Path(folder) / 'cache' / (a['cache_key'] + '.json')).write_text('{broken')
                source.write_bytes(b'source1'); extract_cached(source, Path(folder) / 'cache')
                self.assertEqual(build.call_count, 4)

    def test_legacy_root_selection_migrates_when_geometry_is_smoothed(self):
        from hashlib import sha256
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            source = folder/'Bronchus.stl'
            source.write_bytes(b'root-migration-fixture')
            digest = sha256(source.read_bytes()).hexdigest()
            old_key = sha256(f'centerlines-lee-v2|{digest}|0.8'.encode()).hexdigest()
            old = tree_fixture()
            old.update(source_sha256=digest)
            first = old['branches'][0]
            points = np.asarray(first['points'])
            first['points'] = [points[0].tolist(), ((points[0] + points[1]) / 2).tolist(),
                               points[1].tolist()]
            first['radii_mm'] = [1., 1., 1.]
            (folder/(old_key+'.json')).write_text(json.dumps(old))
            (folder/(old_key+'.roots.json')).write_text(json.dumps(dict(roots=[0])))
            tree = deepcopy(old)
            tree['branches'][0]['points'][1][1] += .1
            tree.update(source_sha256=digest, cache_key='smoothed-graph')
            from cas_frontend.centerlines import _preserve_smoothed_roots
            _preserve_smoothed_roots(tree, source, .8, folder)
            migrated = Path(folder)/(tree['cache_key']+'.roots.json')
            self.assertTrue(migrated.exists())
            self.assertEqual(json.loads(migrated.read_text())['roots'], [0])

    def test_extraction_cancellation_before_work(self):
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'Artery.stl'; source.write_bytes(b'test')
            with self.assertRaisesRegex(RuntimeError, '取消'):
                extract_cached(source, Path(folder) / 'cache', cancelled=lambda: True)

    def test_tube_geometry_is_finite_and_aligned(self):
        mesh = tube_mesh([[(1, 2, 3), (4, 2, 3)]], .2)
        self.assertEqual(mesh.shape, (12, 3, 3))
        self.assertTrue(np.isfinite(mesh).all())
        self.assertAlmostEqual(mesh[:, :, 0].min(), 1.)
        self.assertAlmostEqual(mesh[:, :, 0].max(), 4.)

    def test_real_stl_voxelization_preserves_coordinates_and_rejects_open_surface(self):
        import vtk
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'Artery.stl'
            sphere = vtk.vtkSphereSource(); sphere.SetCenter(20, 30, 40); sphere.SetRadius(4)
            sphere.SetThetaResolution(24); sphere.SetPhiResolution(24); sphere.Update()
            writer = vtk.vtkSTLWriter(); writer.SetFileName(str(path)); writer.SetInputConnection(sphere.GetOutputPort()); writer.Write()
            mask, origin, spacing, _ = voxelize(path, .5)
            centroid = origin + np.argwhere(mask).mean(axis=0) * spacing
            np.testing.assert_allclose(centroid, [20, 30, 40], atol=.4)
            plane = vtk.vtkPlaneSource(); plane.Update()
            triangles = vtk.vtkTriangleFilter(); triangles.SetInputConnection(plane.GetOutputPort()); triangles.Update()
            writer.SetInputConnection(triangles.GetOutputPort()); writer.Write()
            with self.assertRaises(ValueError):
                voxelize(path, .5)


if __name__ == '__main__':
    unittest.main()


class DisplayFilterTests(unittest.TestCase):
    def test_short_detached_fragments_are_hidden_but_the_main_tree_stays(self):
        from cas_frontend.branch_presentation import displayed_branches, display_rows
        tree = tree_fixture()
        # A detached 2 mm piece next to a tiny main tree: only the main tree is kept.
        tree['nodes'] += [dict(id=4, point=[50, 0, 0], radius_mm=.5), dict(id=5, point=[52, 0, 0], radius_mm=.5)]
        tree['branches'].append(dict(id=3, start=4, end=5, points=[[50, 0, 0], [52, 0, 0]], radii_mm=[.5, .5],
                                     length_mm=2., diameter_mm=1., generation=1, parent=None, root=4, component=99))
        kept = displayed_branches(tree)
        self.assertEqual([b['id'] for b in kept], [0, 1, 2])
        rows, _ = display_rows([dict(tree, file='a.stl', kind='artery')])
        self.assertEqual(len(rows), 3)
        self.assertTrue(rows[0]['label'].startswith('动脉 · 第 '))
