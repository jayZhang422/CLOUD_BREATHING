"""Admission and per-request checks for the opt-in RTL mesh planning path."""
import hashlib
import json
import os
from pathlib import Path
from time import perf_counter

import numpy as np

from .planning_cancel import PlanningCancelled, checkpoint

TOLERANCE = 1e-5
ADMISSION_CASE = 'cube'  # synthetic unit cube; see tools/verify_dual_plane_board.py
SOURCE_FILES = (
    'cas_frontend/pl_metrics.py', 'cas_frontend/pl_privileged.py', 'tools/pl_service.py',
    'cas_frontend/dual_plane_mesh_protocol.py', 'cas_frontend/dual_plane_mesh_bvh.py',
    'cas_frontend/dual_plane_reference.py', 'cas_frontend/planning_models.py',
    'cas_frontend/dual_plane_mesh_gate.py', 'tools/verify_dual_plane_board.py',
    'cas_frontend/mesh_union.py', 'cas_frontend/planning_run.py',
    'cas_frontend/planning_cancel.py', 'cas_frontend/planner.py',
    'cas_frontend/planning_constraints.py', 'cas_frontend/planning_geometry.py',
    'cas_frontend/planner_reference.py', 'cas_frontend/mesh_triangle.py')
ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def verify_admission(path, bit_path):
    """Only a complete board parity report can unlock formal PL ranking.

    The receipt binds the bitstream/HWH and software, and records board parity and
    cancellation/timeout recovery on the synthetic cube. It does not restrict which lung
    may be planned. Every PL result is still reviewed by the PS Manifold gate.
    """
    report = json.loads(Path(path).read_text(encoding='utf-8'))
    if (report.get('kind') != 'dual_plane_mesh_hardware_parity'
            or report.get('board_validated') is not True or report.get('full') is not True
            or report.get('abi') != '0x00050000'):
        raise RuntimeError('mesh PL admission requires complete board parity')
    recovery = report.get('control_recovery', {})
    if (recovery.get('cancelled_then_recovered') is not True
            or recovery.get('timed_out_then_recovered') is not True
            or recovery.get('cpu_fallback_count') != 0):
        raise RuntimeError('mesh PL admission requires board cancellation/timeout recovery')
    if report.get('bit_sha256') != sha256(bit_path) or report.get('hwh_sha256') != sha256(Path(bit_path).with_suffix('.hwh')):
        raise RuntimeError('mesh PL admission bitstream/HWH hash mismatch')
    for name in SOURCE_FILES:
        if report.get('source_sha256', {}).get(name) != sha256(ROOT / name):
            raise RuntimeError('mesh PL admission software hash mismatch: ' + name)
    cases = {row['name']: row for row in report.get('cases', [])}
    row = cases.get(ADMISSION_CASE, {})
    result = row.get('result', {})
    count = row.get('candidate_count')
    if (row.get('parity_pass') is not True or not isinstance(count, int) or count < 1
            or row.get('resident_reuse_verified') is not True
            or result.get('reference_only') is not False
            or result.get('execution_backend') != 'dual_plane_pl_mesh'
            or result.get('cpu_fallback_count') != 0 or result.get('errors') != 0
            or result.get('ok') is not True or result.get('abi') != '0x00050000'
            or not np.isfinite(result.get('clock_mhz', np.nan))
            or abs(result.get('clock_mhz', 0.) - 100.) > 1.
            or result.get('candidate_count') != count
            or len(result.get('candidates', [])) != count):
        raise RuntimeError('mesh PL admission missing complete case: ' + ADMISSION_CASE)
    for index, candidate in enumerate(result['candidates']):
        values = [candidate.get(metric, np.nan) for metric in
                  ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2')]
        if (candidate.get('index') != index or candidate.get('ok') is not True
                or candidate.get('flags') != 0 or candidate.get('errors') != 0
                or candidate.get('cpu_fallback_count') != 0
                or not np.isfinite(values).all()
                or bool(candidate.get('valid')) != bool(values[0] > 1e-6)):
            raise RuntimeError('mesh PL admission contains invalid candidate: ' + ADMISSION_CASE)
    deltas = row.get('max_abs_delta', {})
    for metric in ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2'):
        value = deltas.get(metric, float('inf'))
        if not np.isfinite(value) or not 0 <= value <= TOLERANCE:
            raise RuntimeError('mesh PL admission parity tolerance failed')
    return sha256(path)


class MeshPlanningSession:
    """Evaluate coarse AND subsequent optimized candidates in pure RTL.

    Shadow mode compares every candidate but retains Manifold's values for
    search decisions. Production mode requires a matching full board receipt;
    the planner independently performs full Manifold checks on its finalists.
    Hardware errors always stop this path, without a CPU substitute.
    """
    def __init__(self, evaluator, union, *, shadow, cancelled):
        self.evaluator, self.union = evaluator, union
        self.shadow, self.cancelled = shadow, cancelled
        self.cache = {}
        self.calls = self.cycles = self.input_bytes = self.output_bytes = 0
        self.checked_candidates = 0
        self.call_timings = []
        mesh_bytes = np.asarray(union.triangles, dtype='<f8').tobytes()
        self.mesh_triangles = np.frombuffer(mesh_bytes, dtype='<f8').reshape(-1, 3, 3)
        self.mesh_sha256 = hashlib.sha256(mesh_bytes).hexdigest()
        self.receipt_sha256 = None
        if not shadow:
            receipt = os.environ.get('DUAL_PLANE_MESH_ACCEPTANCE')
            if not receipt:
                raise RuntimeError('DUAL_PLANE_MESH_ACCEPTANCE must name a full board parity report')
            self.receipt_sha256 = verify_admission(receipt, evaluator.bit_path)

    def check(self):
        checkpoint()
        if self.cancelled():
            raise PlanningCancelled('规划已停止')

    def evaluate(self, candidates, *, phase='single_candidate'):
        started = perf_counter()
        self.check()
        candidates = np.asarray(candidates, dtype='<f8').reshape(-1, 4, 3)
        keys = [row.tobytes() for row in candidates]
        missing = list(dict.fromkeys(key for key in keys if key not in self.cache))
        for begin in range(0, len(missing), 1023):
            self.check()
            batch_keys = missing[begin:begin+1023]
            vertices = np.frombuffer(b''.join(batch_keys), dtype='<f8').reshape(-1, 4, 3)
            call_started = perf_counter()
            result = self.evaluator.evaluate_dual_plane_mesh_batch(
                self.mesh_triangles, vertices, cancel=self.cancelled, reference_only=False)
            frontend_call_ms = (perf_counter() - call_started) * 1000.
            self.check()  # Cancellation/revision invalidation wins over a late completion.
            rows = result.get('candidates', [])
            if (not result.get('ok') or result.get('abi') != '0x00050000'
                    or result.get('execution_backend') != 'dual_plane_pl_mesh'
                    or result.get('reference_only') is not False
                    or result.get('cpu_fallback_count') != 0 or result.get('errors') != 0
                    or result.get('candidate_count') != len(batch_keys) or len(rows) != len(batch_keys)):
                raise RuntimeError('mesh PL batch failed: ' + str(result.get('error', 'invalid hardware response')))
            admitted = {}
            for index, (key, row) in enumerate(zip(batch_keys, rows)):
                self.check()
                metrics = np.asarray([row.get(name, np.nan) for name in
                    ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2')])
                if (row.get('index') != index or not row.get('ok') or row.get('flags') != 0
                        or row.get('cpu_fallback_count') != 0 or row.get('errors') != 0
                        or not np.isfinite(metrics).all()
                        or metrics[0] < 0 or metrics[1] < 0 or metrics[2] < -TOLERANCE
                        or bool(row.get('valid')) != bool(metrics[0] > 1e-6)):
                    raise RuntimeError('mesh PL candidate diagnostics failed: ' + str(index))
                checked = dict(row)
                if self.shadow:
                    from .dual_plane_reference import manifold_volume_metrics
                    reference = manifold_volume_metrics(self.union.solid, vertices[index])
                    reference_metrics = np.asarray([reference[name] for name in
                        ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2')])
                    delta = np.abs(metrics-reference_metrics)
                    if not np.isfinite(delta).all() or np.any(delta > TOLERANCE):
                        raise RuntimeError('mesh PL shadow Manifold parity failed: ' + str(delta))
                    checked.update(parity_delta=delta.tolist(), parity_verified=True,
                                   ranking_volume_mm3=float(reference['volume_mm3']))
                else:
                    checked.update(parity_verified=True, ranking_volume_mm3=float(metrics[0]))
                admitted[key] = checked
            self.check()
            self.cache.update(admitted)
            self.calls += 1
            self.cycles += int(result.get('cycles', 0))
            self.input_bytes += int(result.get('dma_input_bytes', 0))
            self.output_bytes += int(result.get('dma_output_bytes', 0))
            self.checked_candidates += len(rows)
            self.call_timings.append(dict(phase=phase, candidate_count=len(rows),
                end_to_end_ms=(perf_counter()-started)*1000.,
                frontend_call_ms=frontend_call_ms,
                service_ms=result.get('service_ms'), job_ms=result.get('job_ms'),
                cycles=result.get('cycles'), clock_mhz=result.get('clock_mhz'),
                resident_mesh_reused=result.get('resident_mesh_reused'),
                scratch_buffers_reused=result.get('scratch_buffers_reused'),
                transport_timings_ms=result.get('transport_timings_ms'),
                server_timings_ms=result.get('server_timings_ms'),
                mesh_timings_ms=result.get('mesh_timings_ms')))
            started = perf_counter()
        return [self.cache[key] for key in keys]
