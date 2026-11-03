"""Ownership regressions: fail if CPU executes an accelerated calculation."""
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import pl_metrics, planner_reference as ref, ray_golden
from test_planning_geometry_ray import make_mesh_case
from tools.pl_service import serve


def response(origins, lengths=None):
    result = dict(ok=True, complete_crossings=True, processed=len(origins),
                results=[dict(errors=0, hit_count=3, inside=True,
                              crossings_q16=[1 << 16, 3 << 16, 5 << 16]) for _ in origins],
                job_ms=.25, cycles=25000)
    if lengths is not None:
        result.update(pl_volume=True, volume_mean_q30=1 << 29,
                      volume_valid_rays=len(origins))
    return result


class StrictPlannerTests(unittest.TestCase):
    def strict_case(self, evaluator):
        case = make_mesh_case(evaluator)
        case._strict_pl = True
        case._ray_mode = 'bvh_pl'
        return case

    def test_complete_rays_and_hardware_inside_skip_cpu_and_dedup(self):
        case = self.strict_case(lambda triangles, origins, directions: response(origins))
        with patch.object(case, '_hits_cpu', side_effect=AssertionError('CPU ray')), \
             patch.object(case, '_inside_many_cpu', side_effect=AssertionError('CPU parity')), \
             patch('cas_frontend.planning_geometry.inside_from_crossings', side_effect=AssertionError('CPU parity')):
            self.assertEqual(case.hits([.2, .2, 0], [0, 0, 1]).tolist(), [1, 3, 5])
            self.assertTrue(case.inside([.2, .2, 0]))
            np.testing.assert_array_equal(case._inside_many([[.2, .2, 0]]), [True])

    def test_strict_surface_hit_reuses_same_ray_without_changing_direction(self):
        calls = []

        def evaluate(triangles, origins, directions):
            calls.append(np.asarray(directions).copy())
            return response(origins)

        case = self.strict_case(evaluate)
        point = np.array([.2, .2, 0.])
        first = np.array([0., 0., 1.])
        second = np.array([0., 1., 0.])
        with patch.object(case, '_hits_cpu', side_effect=AssertionError('CPU ray')):
            np.testing.assert_array_equal(case.surface_hit(point, first), point + first)
            np.testing.assert_array_equal(case.surface_hit(point, first), point + first)
            np.testing.assert_array_equal(case.surface_hit(point, second), point + second)
            self.assertEqual(len(calls), 2)
            self.assertEqual(case._mesh_stats['calls'], 2)

        case._mesh_evaluator = lambda *args: dict(ok=False, error='ray failed')
        with self.assertRaisesRegex(RuntimeError, 'ray failed'):
            case.surface_hit(point, -first)
        self.assertNotIn((point.tobytes(), (-first).tobytes()), case._surface_hit_cache)

    def test_timeout_overflow_and_old_abi_never_fall_back(self):
        for value in (dict(ok=False, error='timeout'), dict(ok=False, error='overflow 0x20'),
                      dict(ok=True, results=[dict(hit_count=2, errors=0)])):
            case = self.strict_case(lambda *args: value)
            with patch.object(case, '_hits_cpu', side_effect=AssertionError('CPU fallback')):
                with self.assertRaises(RuntimeError):
                    case.hits([.2, .2, 0], [0, 0, 1])

    def test_cpu_preview_and_metrics_are_forbidden_on_strict_case(self):
        case = self.strict_case(lambda *args: None)
        for operation in (lambda: case.hits([0, 0, 0], [0, 0, 1], allow_pl=False),
                          lambda: case.coverage(np.zeros((4, 3))),
                          lambda: case._inside_many_cpu([[0, 0, 0]])):
            with self.assertRaises(RuntimeError):
                operation()

    def test_pl_intervals_do_not_sort_or_dedup_again(self):
        with patch.object(ray_golden, 'collapse_crossings', side_effect=AssertionError('CPU sort/dedup')):
            self.assertAlmostEqual(ray_golden.volume_fraction([2, 5, 7, 10], 10, False,
                                                               presorted=True), .774)
            self.assertEqual(ray_golden.path_entry([2, 5, 7, 10], 8, presorted=True), 7)

    def test_batched_coarse_validation_preserves_first_failure_and_prefix(self):
        samples = np.column_stack((np.arange(19), np.zeros((19, 2))))
        for inside_at, close_at in ((None, None), (0, None), (10, None),
                                    (None, 0), (None, 9), (15, 2), (2, 15)):
            flags = np.zeros(19, dtype=bool)
            distances = np.full(19, 2.)
            if inside_at is not None:
                flags[inside_at] = True
            if close_at is not None:
                distances[close_at] = .25
            strict = self.strict_case(None)
            scalar = make_mesh_case(None)
            strict._base_mesh_clearance = scalar._base_mesh_clearance = lambda *args: (True, 2.)
            strict._inside_many = Mock(return_value=flags)
            strict._distance_many = Mock(side_effect=lambda points: distances[np.asarray(points)[:, 0].astype(int)])
            strict.inside = Mock(side_effect=AssertionError('scalar PL request'))
            strict.distance = Mock(side_effect=AssertionError('scalar distance scan'))
            scalar.inside = lambda point, **kwargs: bool(flags[int(point[0])])
            scalar.distance = lambda point: float(distances[int(point[0])])
            with patch.object(ref, 'base_sample_points', return_value=samples):
                actual = strict.validate_base(np.zeros((3, 3)), 1., early=True)
                expected = scalar.validate_base(np.zeros((3, 3)), 1., early=True)
            self.assertEqual(actual, expected, (inside_at, close_at))
            strict._inside_many.assert_called_once()
            self.assertTrue(all(len(call.args[0]) <= 8 for call in strict._distance_many.call_args_list))

    def test_coarse_batch_still_uses_hardware_inside_and_fails_without_fallback(self):
        seen = []
        def evaluate(triangles, origins, directions):
            seen.append(len(origins))
            value = response(origins)
            for row in value['results']:
                row.update(inside=False, hit_count=2, crossings_q16=[1 << 16, 3 << 16])
            return value
        case = self.strict_case(evaluate)
        case._base_mesh_clearance = lambda *args: (True, 2.)
        samples = np.column_stack((np.arange(19), np.zeros((19, 2))))
        case._distance_many = lambda points: np.full(len(points), 2.)
        with patch.object(ref, 'base_sample_points', return_value=samples), \
             patch.object(case, '_inside_many_cpu', side_effect=AssertionError('CPU inside')), \
             patch.object(case, '_hits_cpu', side_effect=AssertionError('CPU ray')):
            self.assertEqual(case.validate_base(np.zeros((3, 3)), 1., early=True), (True, 2., 0))
            self.assertEqual(seen, [19])
            case._mesh_evaluator = lambda *args: dict(ok=False, error='batch timeout')
            with self.assertRaisesRegex(RuntimeError, 'batch timeout'):
                case.validate_base(np.zeros((3, 3)), 1., early=True)

    def test_immutable_points_reuse_input_words_only_and_mutable_points_repack(self):
        client = pl_metrics.PlMetrics()
        points = np.arange(12, dtype=float).reshape(4, 3)
        points.setflags(write=False)
        # np.rint is the quantization step of one packing pass.
        with patch.object(pl_metrics.np, 'rint', wraps=np.rint) as quantize:
            first, reused = client._pack_points(points)
            self.assertFalse(reused)
            self.assertEqual(quantize.call_count, 1)
            second, reused = client._pack_points(points.reshape(4, 3))
            self.assertTrue(reused)
            self.assertIs(first, second)
            self.assertEqual(quantize.call_count, 1)
            changed = points.copy() + 1
            changed.setflags(write=False)
            third, reused = client._pack_points(changed)
            self.assertFalse(reused)
            self.assertEqual(quantize.call_count, 2)
            self.assertNotEqual(first, third)
        mutable = points.copy()
        before, reused = client._pack_points(mutable)
        mutable[0, 0] = 42.
        after, reused = client._pack_points(mutable)
        self.assertFalse(reused)
        self.assertNotEqual(before, after)
        client.close()
        self.assertIsNone(client._packed_points_cache)

    def test_service_confirms_strict_pl_and_clock_or_reports_failure(self):
        client = Mock(require_strict_pl=True, clock_mhz=100.)
        client._mesh_mmio.read.return_value = 0x50000
        output = io.StringIO()
        serve(client, io.StringIO('{"op":"prepare_strict"}\n'), output)
        self.assertEqual(json.loads(output.getvalue().splitlines()[1])['clock_mhz'], 100.)
        client.prepare.side_effect = RuntimeError('Wrong ABI')
        output = io.StringIO()
        serve(client, io.StringIO('{"op":"prepare_strict"}\n'), output)
        self.assertFalse(json.loads(output.getvalue().splitlines()[1])['ok'])

    def test_immutable_mesh_is_packed_once_but_new_case_is_repacked(self):
        from cas_frontend.pl_privileged import PrivilegedPlClient
        from cas_frontend.ray_mesh import pack_mesh
        from cas_frontend.frozen_mesh import FrozenMesh
        client = PrivilegedPlClient('unused.bit')
        client.process = types.SimpleNamespace(stdin=io.BytesIO())
        mesh = np.array([[[0., 0., 0.], [1., 0., 0.], [0., 1., 0.]]])
        first = FrozenMesh(mesh)
        changed = FrozenMesh(mesh + 1)
        with patch.object(client, '_start'), patch.object(client, '_receive', return_value=dict(ok=True)), \
             patch('cas_frontend.ray_mesh.pack_mesh', wraps=pack_mesh) as packed:
            client.cache_mesh_resource(first)
            client.evaluate_mesh_rays(first.triangles, [[0, 0, 1]], [[0, 0, -1]], solid_ids=first.solid_ids)
            client.evaluate_mesh_rays(first.triangles, [[0, 0, 1]], [[0, 0, -1]], solid_ids=first.solid_ids)
            client.cache_mesh_resource(changed)
            client.evaluate_mesh_rays(changed.triangles, [[0, 0, 1]], [[0, 0, -1]], solid_ids=changed.solid_ids)
            self.assertEqual(packed.call_count, 2)
        requests = [json.loads(line) for line in client.process.stdin.getvalue().splitlines()]
        self.assertIn('mesh', requests[0])
        self.assertNotIn('mesh', requests[1])
        self.assertIn('mesh', requests[2])

    def test_strict_loader_sets_clock_and_rejects_old_abi(self):
        client = pl_metrics.PlMetrics(require_strict_pl=True)
        clocks = types.SimpleNamespace(fclk0_mhz=150.)
        overlay = types.SimpleNamespace(dma=object(), mesh_ray_dma=object(), mesh_result_dma=object())
        class MMIO:
            def __init__(self, address, size): self.address = address
            def read(self, offset):
                if self.address == pl_metrics.METRICS_BASE: return pl_metrics.ABI_VERSION
                return {0x02c: 0x00040000, 0x050: 15, 0x064: 576, 0x060: 128}.get(offset, 0)
        with patch.dict(os.environ, {'LUNG_PL_BIT': __file__, 'LUNG_PL_ENABLE': '1'}), \
             patch.object(pl_metrics, '_import_pynq', return_value=(lambda *a, **kw: overlay, None, MMIO)), \
             patch.dict(sys.modules, {'pynq': types.SimpleNamespace(Clocks=clocks)}):
            client._load()
            self.assertEqual(clocks.fclk0_mhz, 100.)
            self.assertTrue(client._mesh_complete)
            client.close()
            del overlay.mesh_ray_dma
            with self.assertRaisesRegex(RuntimeError, 'ABI'):
                client._load()
        client.close()


if __name__ == '__main__':
    unittest.main()
