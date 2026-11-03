"""KV260 mesh-kernel acceptance on the synthetic cube vectors.

This is a hardware parity test, not the end-to-end planner benchmark. It never
enables the production planning gate and has no CPU/reference fallback mode.
Run under the board's PYNQ Python as root after reviewing the deployment files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import sys
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from cas_frontend.dual_plane_mesh_gate import ADMISSION_CASE, SOURCE_FILES

METRICS = ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2')
TOLERANCE = 1e-5


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_vectors(directory):
    manifest = json.loads((directory / 'manifest.json').read_text(encoding='utf-8'))
    if manifest['label'] != ADMISSION_CASE:
        raise ValueError('unapproved case')
    if manifest['abi'] != '0x00050000':
        raise ValueError('vector ABI mismatch')
    for name, digest in manifest['sha256'].items():
        if Path(name).name != name or sha256(directory / name) != digest:
            raise ValueError('vector integrity failure: ' + name)
    with np.load(directory / 'board_vectors.npz', allow_pickle=False) as archive:
        triangles, candidates, expected = [archive[key].copy()
                                          for key in ('triangles', 'candidates', 'expected')]
    if (triangles.shape != (manifest['triangles'], 3, 3)
            or candidates.shape != (manifest['candidate_count'], 4, 3)
            or expected.shape != (len(candidates), 3)):
        raise ValueError('vector shape mismatch')
    if any(array.dtype != np.dtype('<f8') or not np.isfinite(array).all()
           for array in (triangles, candidates, expected)):
        raise ValueError('vectors must be finite float64')
    if sha256_bytes(triangles.tobytes()) != manifest['mesh_sha256']:
        raise ValueError('normalized mesh identity mismatch')
    return manifest, triangles, candidates, expected


def sha256_bytes(raw):
    return hashlib.sha256(raw).hexdigest()


def compare_hardware(result, expected):
    """Validate provenance and every metric before reporting parity."""
    if (not result.get('ok') or result.get('reference_only') is not False
            or result.get('execution_backend') != 'dual_plane_pl_mesh'
            or result.get('abi') != '0x00050000'
            or result.get('cpu_fallback_count') != 0 or result.get('errors') != 0
            or not np.isfinite(result.get('clock_mhz', np.nan))
            or abs(result.get('clock_mhz', 0.) - 100.) > 1.):
        raise RuntimeError('hardware batch rejected: ' + str(result.get('error', result)))
    rows = result.get('candidates', [])
    if result.get('candidate_count') != len(expected) or len(rows) != len(expected):
        raise RuntimeError('hardware candidate count mismatch')
    for index, row in enumerate(rows):
        if (row.get('index') != index or not row.get('ok') or row.get('flags') != 0
                or row.get('cpu_fallback_count') != 0 or row.get('errors') != 0
                or bool(row.get('valid')) != bool(expected[index, 0] > 1e-6)):
            raise RuntimeError(f'candidate {index} identity/diagnostics/validity mismatch')
    actual = np.asarray([[row[key] for key in METRICS] for row in rows])
    delta = np.abs(actual - expected)
    if not np.isfinite(actual).all() or np.any(delta > TOLERANCE):
        raise RuntimeError('Manifold parity failure; maximum deltas=' + str(delta.max(axis=0)))
    return dict(max_abs_delta=dict(zip(METRICS, map(float, delta.max(axis=0)))),
                candidate_count=len(rows), tolerance=TOLERANCE, parity_pass=True)


def check_control_recovery(engine, mesh, candidates, expected, timeout):
    """Cancel after launch, force a host deadline, then verify fresh results."""
    polls = 0
    def cancel_after_launch():
        nonlocal polls
        polls += 1
        # Driver checks once before starting, then again while hardware runs.
        return polls > 1
    cancelled = engine.evaluate_dual_plane_mesh_batch(mesh, candidates,
        timeout_seconds=timeout, cancel=cancel_after_launch, reference_only=False)
    if (cancelled.get('ok') or 'cancelled' not in cancelled.get('error','')
            or cancelled.get('cpu_fallback_count') != 0):
        raise RuntimeError('hardware cancellation was not acknowledged')
    resumed = engine.evaluate_dual_plane_mesh_batch(mesh, candidates,
        timeout_seconds=timeout, reference_only=False)
    compare_hardware(resumed, expected)
    timed_out = engine.evaluate_dual_plane_mesh_batch(mesh, candidates,
        timeout_seconds=1e-9, reference_only=False)
    if (timed_out.get('ok') or 'timeout' not in timed_out.get('error','').lower()
            or timed_out.get('cpu_fallback_count') != 0):
        raise RuntimeError('hardware deadline/abort was not acknowledged')
    resumed_again = engine.evaluate_dual_plane_mesh_batch(mesh, candidates,
        timeout_seconds=timeout, reference_only=False)
    compare_hardware(resumed_again, expected)
    return dict(cancelled_then_recovered=True, timed_out_then_recovered=True,
                cpu_fallback_count=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vectors', type=Path, required=True, help='Root containing the cube/ vector directory')
    parser.add_argument('--bit', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=600.)
    args = parser.parse_args()
    if sys.platform != 'linux' or not hasattr(os, 'geteuid') or os.geteuid() != 0:
        parser.error('run on KV260 as root with the PYNQ Python interpreter')
    bit = args.bit.resolve()
    hwh = bit.with_suffix('.hwh')
    if not bit.is_file() or not hwh.is_file():
        parser.error('both matching .bit and .hwh files are required')
    os.environ['LUNG_PL_BIT'] = str(bit)
    os.environ['LUNG_PL_ENABLE'] = '1'
    from cas_frontend.pl_metrics import PlMetrics
    report = dict(schema=1, kind='dual_plane_mesh_hardware_parity',
                  full=True, board_validated=False, production_gate_enabled=False,
                  abi='0x00050000', machine=platform.machine(),
                  bit_sha256=sha256(bit), hwh_sha256=sha256(hwh),
                  source_sha256={name: sha256(ROOT / name) for name in SOURCE_FILES},
                  cases=[], timestamp_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
    engine = PlMetrics()
    try:
        for name in (ADMISSION_CASE,):
            directory = args.vectors / name
            manifest, mesh, candidates, expected = load_vectors(directory)
            selection = list(range(len(candidates)))
            started = time.perf_counter()
            result = engine.evaluate_dual_plane_mesh_batch(mesh, candidates,
                timeout_seconds=args.timeout, reference_only=False)
            elapsed = time.perf_counter() - started
            checked = compare_hardware(result, expected)
            # Re-submit the first candidate to prove resident reuse and fresh
            # completion identity on the same engine, without reloading it.
            repeat = engine.evaluate_dual_plane_mesh_batch(mesh, candidates[:1],
                timeout_seconds=args.timeout, reference_only=False)
            compare_hardware(repeat, expected[:1])
            if not repeat.get('resident_mesh_reused') or repeat['job_id'] == result['job_id']:
                raise RuntimeError('resident reuse or fresh job identity failed')
            if not repeat.get('scratch_buffers_reused'):
                raise RuntimeError('single-candidate retry unexpectedly reallocated DDR scratch')
            if name == ADMISSION_CASE:
                report['control_recovery'] = check_control_recovery(
                    engine, mesh, candidates, expected, args.timeout)
            report['cases'].append(dict(name=name, mesh_sha256=manifest['mesh_sha256'],
                vector_manifest_sha256=sha256(directory / 'manifest.json'),
                selected_candidate_indices=[index+1 for index in selection],
                provenance=manifest['provenance'], **checked,
                hardware_call_wall_s=elapsed, resident_reuse_verified=True,
                scratch_reuse_verified=True,
                result=result))
            print(f'{name}: {len(candidates)} candidates PASS, hardware call {elapsed:.3f} s', flush=True)
        report['board_validated'] = True
    except Exception as error:
        report['error'] = str(error)
        raise
    finally:
        try:
            engine.close()
        except Exception as error:
            report.update(board_validated=False, cleanup_error=str(error))
            raise
        finally:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False), encoding='utf-8')


if __name__ == '__main__':
    main()
