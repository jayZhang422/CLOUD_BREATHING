"""Strict complete-crossing contract and backend parity for branch clipping."""
from copy import deepcopy
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import numpy as np

from cas_frontend.branch_analysis import BranchAnalysisEngine, PlLungQuery, AnalysisCancelled, branch_case, mesh_identity
from cas_frontend.mesh_cpu import CpuMeshIndex
from cas_frontend.planning_geometry import PlanningCase
from test_centerlines import tree_fixture, TETRA


def cube(low=-1., high=2.):
    points = np.asarray([(x, y, z) for x in (low, high) for y in (low, high) for z in (low, high)])
    faces = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5),
             (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6),
             (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]
    return points[np.asarray(faces)]


def cases():
    triangles = cube()
    index = CpuMeshIndex(triangles)
    cpu = SimpleNamespace(triangles=triangles, _cpu_index=index)
    pl = SimpleNamespace(triangles=triangles, _strict_pl=True, _ray_mode='bvh_pl',
        _mesh_stats={'calls': 0, 'cycles': 0}, _cpu_index=None)

    def hits(points, directions, **kwargs):
        assert kwargs['require_complete']
        pl._mesh_stats['calls'] += 1
        pl._mesh_stats['cycles'] += 100
        # Quantize the reference intersections to the real PL ABI precision.
        return [np.round(index.hits(p, d) * 65536.) / 65536. for p, d in zip(points, directions)]
    pl._ray_hits_many = Mock(side_effect=hits)
    return cpu, pl


def tree():
    result = tree_fixture()
    result.update(kind='airway', file='Bronchus.stl', cache_key='fixture',
                  source_sha256='synthetic', spacing_mm=.8)
    return result


class BranchPlTests(unittest.TestCase):
    def test_worker_converts_scene_region_and_highlights_in_opposite_directions(self):
        from cas_frontend.centerline_controller import BranchAnalysisWorker
        spacing = np.array([.7, .8, 1.25])
        case = SimpleNamespace(ct_spacing=spacing)
        worker = BranchAnalysisWorker()
        physical_mesh = np.ones((1, 3, 3)) * spacing
        worker.engine.run = Mock(return_value=dict(report={}, analyses=[], timing={},
            removed_mesh=physical_mesh.copy(), near_mesh=physical_mesh.copy()))
        results = []
        worker.completed.connect(results.append)
        with patch('cas_frontend.centerline_controller.prepare_mesh', return_value={}) as render:
            worker.run(dict(signature='test', case=case, backend='pl', trees=[],
                vertices=np.stack([TETRA, TETRA]), cancel={'value': False}, center=[0,0,0], scale=1.))
        self.assertNotIn('error', results[0])
        np.testing.assert_allclose(worker.engine.run.call_args.args[3], np.stack([TETRA, TETRA])*spacing)
        for call in render.call_args_list:
            np.testing.assert_allclose(call.args[0], np.ones((1, 3, 3)))

    def wedge(self, response):
        case = PlanningCase.__new__(PlanningCase)
        case._planning_model = 'plane_wedge'
        case._strict_pl, case._ray_mode = False, 'bvh_pl'
        case._mesh_disabled, case._mesh_error = False, ''
        case._mesh_stats = dict(calls=0, rays=0, hits=0, job_ms=0., service_ms=0., cycles=0)
        case.triangles = cube(10, 11)
        case._planning_lung_union = SimpleNamespace(triangles=cube(-2, 3))
        case._mesh_evaluator = Mock(return_value=response)
        return case

    def test_wedge_uses_complete_side_envelope_without_mutating_planning_case(self):
        case = self.wedge(dict(ok=True, complete_crossings=True, results=[
            dict(errors=0, inside=True, crossings_q16=[3*65536])]))
        view = branch_case(case, 'pl')
        self.assertTrue(view._strict_pl)
        self.assertFalse(case._strict_pl)
        self.assertIs(branch_case(case, 'pl'), view)
        self.assertFalse(np.array_equal(view.triangles, case.triangles))
        intervals = PlLungQuery(view).intervals_many(np.array([[[0.,0,0],[1.,0,0]]]), np.ones(1))
        np.testing.assert_allclose(intervals[0], [[0, 1]])
        np.testing.assert_array_equal(case._mesh_evaluator.call_args.args[0], case._planning_lung_union.triangles)
        self.assertEqual(case._mesh_stats['calls'], 0)
        self.assertEqual(view._mesh_stats['calls'], 1)

    def test_wedge_failure_incomplete_and_overflow_never_fall_back(self):
        for response in [dict(ok=False, error='timeout'),
                         dict(ok=True, complete_crossings=False, results=[{}]),
                         dict(ok=True, complete_crossings=True, results=[dict(errors=32)]),
                         dict(ok=True, complete_crossings=True, results=[])]:
            with self.subTest(response=response):
                case = self.wedge(response)
                with self.assertRaisesRegex(RuntimeError, 'no CPU fallback'):
                    PlLungQuery(branch_case(case, 'pl')).intervals_many(np.array([[[0.,0,0],[1.,0,0]]]), np.ones(1))
                self.assertFalse(case._strict_pl)
                self.assertFalse(case._mesh_disabled)

    def test_wedge_cache_identity_tracks_whole_side_not_selected_segment(self):
        first, second = self.wedge({}), self.wedge({})
        second.triangles = cube(20, 21)
        self.assertEqual(mesh_identity(first), mesh_identity(second))
        second._planning_lung_union.triangles = cube(-3, 4)
        self.assertNotEqual(mesh_identity(first), mesh_identity(second))

    def test_source_centerlines_are_scaled_into_ct_physical_frame(self):
        # PlanningCase stores the resection in CT millimetres, while legacy
        # STL centerline caches remain in source voxel coordinates.
        mesh = cube(-10., 40.)
        case = SimpleNamespace(triangles=mesh, _cpu_index=CpuMeshIndex(mesh),
                               ct_spacing=np.asarray((2., 1.5, .75)))
        region = TETRA * np.asarray((2., 1.5, .75))
        output = BranchAnalysisEngine().run(case, 'cpu', [tree()], region)
        rows = output['analyses'][0]['rows']
        self.assertTrue(any(row['status'] != 'outside' for row in rows))
        self.assertEqual(output['report']['analysis_coordinate_space'], 'physical_mm')
        self.assertEqual(output['report']['ct_spacing_mm'], [2., 1.5, .75])

    def test_union_ps_pl_parity_deduplicates_identical_region(self):
        cpu, pl = cases()
        regions = np.stack([TETRA, TETRA, TETRA + np.array([1., 0., 0.])])
        a = BranchAnalysisEngine().run(cpu, 'cpu', [tree()], regions)
        b = BranchAnalysisEngine().run(pl, 'pl', [tree()], regions)
        self.assertEqual(b['report']['region_count'], 3)
        for x, y in zip(a['analyses'][0]['rows'], b['analyses'][0]['rows']):
            self.assertEqual(x['status'], y['status'])
            self.assertEqual(x['downstream_affected'], y['downstream_affected'])
            self.assertAlmostEqual(x['removed_length_mm'], y['removed_length_mm'], delta=5e-5)
            self.assertLessEqual(x['removed_length_mm'], x['length_mm'] + 1e-6)
        self.assertGreater(b['timing']['pl_calls'], 0)
        self.assertEqual(b['timing']['cpu_fallback_count'], 0)

    def test_ps_pl_same_lung_clipped_lengths_and_status(self):
        cpu, pl = cases()
        a = BranchAnalysisEngine().run(cpu, 'cpu', [tree()], TETRA)
        b = BranchAnalysisEngine().run(pl, 'pl', [tree()], TETRA)
        for x, y in zip(a['analyses'][0]['rows'], b['analyses'][0]['rows']):
            self.assertEqual(x['status'], y['status'])
            self.assertEqual(x['downstream_affected'], y['downstream_affected'])
            self.assertAlmostEqual(x['removed_length_mm'], y['removed_length_mm'], delta=5e-5)
        self.assertGreater(b['timing']['pl_calls'], 0)
        self.assertEqual(b['timing']['cpu_fallback_count'], 0)
        self.assertGreater(b['removed_mesh'].size, 0)

    def test_interval_cache_reused_across_lesions_but_not_backend_or_mesh(self):
        cpu, pl = cases()
        engine = BranchAnalysisEngine()
        first = engine.run(pl, 'pl', [tree()], TETRA)
        second = engine.run(deepcopy(pl), 'pl', [tree()], TETRA)
        self.assertGreater(first['timing']['queried_segments'], 0)
        self.assertEqual(second['timing']['queried_segments'], 0)
        ps = engine.run(cpu, 'cpu', [tree()], TETRA)
        self.assertGreater(ps['timing']['queried_segments'], 0)
        cpu.triangles = cube(-10, 10)
        del cpu._branch_mesh_identity
        cpu._cpu_index = CpuMeshIndex(cpu.triangles)
        self.assertGreater(engine.run(cpu, 'cpu', [tree()], TETRA)['timing']['queried_segments'], 0)

    def test_failure_is_not_replaced_by_cpu_or_cached_as_outside(self):
        _, pl = cases()
        pl._ray_hits_many = Mock(side_effect=RuntimeError('hardware timeout'))
        engine = BranchAnalysisEngine()
        with self.assertRaisesRegex(RuntimeError, 'timeout'):
            engine.run(pl, 'pl', [tree()], TETRA)
        with self.assertRaisesRegex(RuntimeError, 'timeout'):
            engine.run(pl, 'pl', [tree()], TETRA)
        self.assertEqual(pl._ray_hits_many.call_count, 2)

    def test_incomplete_or_non_strict_queries_rejected(self):
        _, pl = cases()
        pl._ray_hits_many = Mock(return_value=None)
        with self.assertRaisesRegex(RuntimeError, '完整'):
            BranchAnalysisEngine().run(pl, 'pl', [tree()], TETRA)
        pl._strict_pl = False
        with self.assertRaisesRegex(RuntimeError, '禁止 CPU'):
            PlLungQuery(pl)

    def test_pl_requests_are_batched_and_cancellable(self):
        _, pl = cases()
        query = PlLungQuery(pl, batch_size=2)
        segments = np.asarray([[[0, 0, 0], [1, 0, 0]]] * 5, dtype=float)
        self.assertEqual(len(query.intervals_many(segments, np.ones(5))), 5)
        self.assertEqual(pl._ray_hits_many.call_count, 3)
        with self.assertRaises(AnalysisCancelled):
            PlLungQuery(pl, cancelled=lambda: True).intervals_many(segments, np.ones(5))

    def test_real_strict_case_rejects_hardware_error(self):
        # Exercise the existing strict decoder, not only the adapter mock.
        case = PlanningCase.__new__(PlanningCase)
        case._strict_pl, case._ray_mode = True, 'bvh_pl'
        case._mesh_disabled, case._mesh_error = False, ''
        case._mesh_stats = {}
        case.triangles = cube()
        case._mesh_evaluator = Mock(return_value={'ok': False, 'error': 'test failure'})
        with self.assertRaisesRegex(RuntimeError, 'no CPU fallback'):
            PlLungQuery(case).intervals_many(np.asarray([[[0, 0, 0], [1, 0, 0]]]), np.ones(1))

    def test_identical_lung_snapshots_share_wire_image_but_labels_do_not(self):
        import io
        from unittest.mock import patch
        from cas_frontend.pl_privileged import PrivilegedPlClient
        from cas_frontend.frozen_mesh import FrozenMesh
        from cas_frontend.mesh_bvh import build_mesh_image
        triangles = cube()
        labels = np.asarray([0] * 6 + [1] * 6)
        first = FrozenMesh(triangles, labels)
        second = FrozenMesh(triangles.copy(), labels.copy())
        relabelled = FrozenMesh(triangles, labels[::-1])
        client = PrivilegedPlClient('unused.bit')
        client.process = SimpleNamespace(stdin=io.BytesIO())
        with patch.object(client, '_start'), patch.object(client, '_receive', return_value={'ok': True}), \
                patch('cas_frontend.mesh_bvh.build_mesh_image', wraps=build_mesh_image) as packed:
            for resource in (first, second, relabelled):
                client.cache_mesh_resource(resource)
                client.evaluate_mesh_rays(resource.triangles, [[0, 0, 0]], [[1, 0, 0]], solid_ids=resource.solid_ids)
            self.assertEqual(packed.call_count, 2)


if __name__ == '__main__':
    unittest.main()
