"""Regression tests for the optional ray_batch geometry backend."""
import struct
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from cas_frontend.planning_geometry import PlanningCase


def make_case(evaluator, *, chunk_records=4096):
    """Build the ray portion of a case without requiring an STL fixture."""
    case = object.__new__(PlanningCase)
    case.triangles = np.asarray((
        ((0., 0., 1.), (1., 0., 1.), (0., 1., 1.)),
        ((0., 0., 3.), (1., 0., 3.), (0., 1., 3.)),
    ), dtype=np.float64)
    case.a = case.triangles[:, 0]
    case.e1 = case.triangles[:, 1] - case.a
    case.e2 = case.triangles[:, 2] - case.a
    case._ray_evaluator = evaluator
    case._mesh_evaluator = None
    case._mesh_disabled = False
    case._mesh_error = ''
    case._mesh_stats = dict(calls=0, rays=0, hits=0, job_ms=0.,
                            service_ms=0., cycles=0)
    case._ray_mode = 'pl'
    case._ray_disabled = False
    case._ray_error = ''
    case._ray_sequence = 0
    case._ray_cache = {}
    case._ray_cache_limit = 16
    case._ray_chunk_records = chunk_records
    case._ray_bulk_limit = 100000
    case._ray_stats = dict(calls=0, records=0, hits=0, job_ms=0.,
                           service_ms=0., cycles=0, skipped_records=0)
    return case


def make_mesh_case(evaluator):
    case = make_case(None)
    case._mesh_evaluator = evaluator
    case._ray_mode = 'auto'
    return case


class RayGeometryTests(unittest.TestCase):
    def test_mesh_resident_results_are_used_without_ray_triangle_records(self):
        calls = []

        def evaluate(triangles, origins, directions):
            calls.append((np.asarray(triangles).shape,
                          np.asarray(origins).shape,
                          np.asarray(directions).shape))
            return dict(ok=True, results=[dict(ray_id=index + 1, hit_count=2,
                                               t_near_q16=1 << 16,
                                               t_far_q16=3 << 16)
                                          for index in range(len(origins))],
                        hits=2 * len(origins), job_ms=0.5, cycles=23)

        case = make_mesh_case(evaluate)
        origins = np.asarray(((0.25, 0.25, 0.), (0.25, 0.25, 0.)), dtype=np.float64)
        directions = np.asarray(((0., 0., 1.), (0., 0., 1.)), dtype=np.float64)
        values = case._ray_hits_many(origins, directions)

        self.assertEqual([value.tolist() for value in values], [[1.0, 3.0], [1.0, 3.0]])
        self.assertEqual(calls, [((2, 3, 3), (2, 3), (2, 3))])
        self.assertEqual(case.ray_summary()['mesh_pl_rays'], 2)
        self.assertEqual(case.ray_summary()['ray_pl_records'], 0)

    def test_mesh_failure_falls_back_to_cpu_reference(self):
        case = make_mesh_case(lambda triangles, origins, directions:
                              dict(ok=False, error='synthetic mesh failure'))
        # Diagnostic summary requests may attempt PL; complete crossings
        # bypass the summary-only ABI without duplicating the CPU work.
        case._ray_hits_many([(0.25, 0.25, 0.)], [(0., 0., 1.)])
        result = case.hits((0.25, 0.25, 0.), (0., 0., 1.))
        self.assertEqual(result.tolist(), [1.0, 3.0])
        self.assertTrue(case._mesh_disabled)
        self.assertIn('fallback', case.ray_summary()['ray_backend'])
        self.assertEqual(case.ray_summary()['ray_error'], 'synthetic mesh failure')

    def test_pl_hits_are_used_and_batches_are_chunked(self):
        calls = []

        def evaluate(raw, count):
            calls.append((bytes(raw), count))
            results = []
            for index in range(count):
                ray_id, triangle_id = struct.unpack_from('<II', raw, index * 80)
                results.append(dict(ray_id=ray_id, triangle_id=triangle_id,
                                    hit=triangle_id == 0, error=0,
                                    t_q16=1 << 16, u_q16=1 << 15, v_q16=1 << 15))
            return dict(ok=True, results=results, hits=count // 2,
                        job_ms=0.25, cycles=17)

        case = make_case(evaluate, chunk_records=2)
        origins = np.asarray(((0.25, 0.25, 0.), (0.25, 0.25, 0.)), dtype=np.float64)
        directions = np.asarray(((0., 0., 1.), (0., 0., 1.)), dtype=np.float64)
        values = case._ray_hits_many(origins, directions)

        self.assertEqual([value.tolist() for value in values], [[1.0], [1.0]])
        self.assertEqual(len(calls), 2)
        self.assertEqual([count for _, count in calls], [2, 2])
        self.assertEqual(case.ray_summary()['ray_pl_records'], 4)
        self.assertEqual(case.hits(origins[0], directions[0]).tolist(), [1.0])
        # The scalar call above has a different cache key from the batch call,
        # but its result still comes from the fake PL response.
        self.assertEqual(case.ray_summary()['ray_pl_calls'], 3)

    def test_pl_failure_falls_back_to_cpu_intersection(self):
        def evaluate(raw, count):
            return dict(ok=False, error='synthetic ray failure')

        case = make_case(evaluate)
        result = case.hits((0.25, 0.25, 0.), (0., 0., 1.))

        self.assertEqual(result.tolist(), [1.0, 3.0])
        summary = case.ray_summary()
        self.assertEqual(summary['ray_pl_calls'], 1)
        self.assertEqual(summary['ray_pl_records'], 2)
        self.assertIn('fallback', summary['ray_backend'])
        self.assertEqual(summary['ray_error'], 'synthetic ray failure')

    def test_allow_pl_false_skips_evaluator_and_cache(self):
        calls = []

        def evaluate(raw, count):
            calls.append(count)
            results = []
            for index in range(count):
                ray_id, triangle_id = struct.unpack_from('<II', raw, index * 80)
                results.append(dict(ray_id=ray_id, triangle_id=triangle_id,
                                    hit=False, error=0, t_q16=0,
                                    u_q16=0, v_q16=0))
            return dict(ok=True, results=results, hits=0)

        case = make_case(evaluate)
        point = (0.25, 0.25, 0.)
        direction = (0., 0., 1.)
        # Populate a PL cache entry, then explicitly require a CPU-only call.
        self.assertEqual(case.hits(point, direction).tolist(), [])
        self.assertEqual(case.hits(point, direction, allow_pl=False).tolist(), [1.0, 3.0])
        self.assertEqual(calls, [2])

    def test_empty_result_batch_falls_back(self):
        case = make_case(lambda raw, count: dict(ok=True, results=[], hits=0))
        self.assertEqual(case.hits((0.25, 0.25, 0.), (0., 0., 1.)).tolist(), [1.0, 3.0])
        self.assertIn('fallback', case.ray_summary()['ray_backend'])

    def test_duplicate_result_batch_falls_back(self):
        def evaluate(raw, count):
            ray_id, triangle_id = struct.unpack_from('<II', raw, 0)
            item = dict(ray_id=ray_id, triangle_id=triangle_id, hit=False,
                        error=0, t_q16=0, u_q16=0, v_q16=0)
            return dict(ok=True, results=[item, item], hits=0)

        case = make_case(evaluate)
        self.assertEqual(case.hits((0.25, 0.25, 0.), (0., 0., 1.)).tolist(), [1.0, 3.0])
        self.assertIn('duplicate', case.ray_summary()['ray_error'])

    def test_non_hit_error_is_accepted_but_hit_error_falls_back(self):
        def evaluate(raw, count):
            results = []
            for index in range(count):
                ray_id, triangle_id = struct.unpack_from('<II', raw, index * 80)
                results.append(dict(ray_id=ray_id, triangle_id=triangle_id,
                                    hit=triangle_id == 0, error=1,
                                    t_q16=1 << 16, u_q16=0, v_q16=0))
            return dict(ok=True, results=results, hits=1, errors=1)

        case = make_case(evaluate)
        # The first triangle is incorrectly marked as a hit with a parallel
        # error, so the complete batch must be rejected and use the reference.
        self.assertEqual(case.hits((0.25, 0.25, 0.), (0., 0., 1.)).tolist(), [1.0, 3.0])
        self.assertIn('fatal error', case.ray_summary()['ray_error'])

        def valid_miss(raw, count):
            results = []
            for index in range(count):
                ray_id, triangle_id = struct.unpack_from('<II', raw, index * 80)
                results.append(dict(ray_id=ray_id, triangle_id=triangle_id,
                                    hit=False, error=1, t_q16=0,
                                    u_q16=0, v_q16=0))
            return dict(ok=True, results=results, hits=0, errors=1)

        case = make_case(valid_miss)
        self.assertEqual(case.hits((0.25, 0.25, 0.), (0., 0., 1.)).tolist(), [])
        self.assertFalse(case._ray_disabled)

    def test_unmatched_aggregate_error_falls_back(self):
        def evaluate(raw, count):
            results = []
            for index in range(count):
                ray_id, triangle_id = struct.unpack_from('<II', raw, index * 80)
                results.append(dict(ray_id=ray_id, triangle_id=triangle_id,
                                    hit=False, error=0, t_q16=0,
                                    u_q16=0, v_q16=0))
            return dict(ok=True, results=results, hits=0, errors=1)

        case = make_case(evaluate)
        self.assertEqual(case.hits((0.25, 0.25, 0.), (0., 0., 1.)).tolist(), [1.0, 3.0])
        self.assertIn('no matching miss record', case.ray_summary()['ray_error'])


if __name__ == '__main__':
    unittest.main()
