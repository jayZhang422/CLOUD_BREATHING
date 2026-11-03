"""Board check: oversized PL point batches against Q16.16 integer arithmetic."""
import argparse
import json
import os
from pathlib import Path
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from cas_frontend.pl_metrics import PlMetrics, _q16


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    engine = PlMetrics()
    candidates = np.array([[[0., 0., 0.], [20., 0., 0.], [0., 20., 0.],
                            [shift, 2., 20.]] for shift in (0., 5., -5.)])
    report = dict(status='RUNNING', cases=[], cpu_fallback_count=0)
    try:
        rng = np.random.default_rng(20261030)
        for count in (4096, 4097, 4494, 8192, 9672, 16385):
            points = rng.uniform(-5., 25., (count, 3))
            points[::11] = points[0]
            points[-1] = [-100., -100., -100.]
            result = engine.evaluate_dual_plane_filter_batch(points, candidates, .5)
            assert result.get('ok'), result
            assert result['cpu_fallback_count'] == 0
            assert result['pl_calls'] == (count + 4095) // 4096
            quantized = np.array([[_q16(v) for v in p] for p in points], dtype=np.int64)
            for index, (vertices, row) in enumerate(zip(candidates, result['candidates'])):
                planes = np.asarray(engine._dual_plane_words(vertices), dtype=np.int64)
                distances = quantized @ planes[:, :3].T + (planes[:, 3] << 16)
                accepted = int(np.count_nonzero(np.all(distances >= (_q16(.5) << 16), axis=1)))
                clearance = np.clip(distances.min() >> 16, -2147483648, 2147483647) / 65536.
                assert row['index'] == index and row['processed'] == count
                assert row['accepted'] == accepted, (count, index, row, accepted)
                assert row['clearance_mm'] == clearance, (count, index, row, clearance)
                assert row['coverage_percent'] == 100. * accepted / count
            report['cases'].append(dict(point_count=count, candidates=len(candidates),
                                        pl_calls=result['pl_calls'], parity_pass=True))
            print('POINT_BATCH_PASS', count, result['pl_calls'], flush=True)
        cancelled = engine.evaluate_dual_plane_filter_batch(
            points, candidates, .5, cancel=lambda: True)
        assert not cancelled['ok'] and 'cancelled' in cancelled['error']
        timed_out = engine.evaluate_dual_plane_filter_batch(
            points, candidates, .5, timeout_seconds=1e-9)
        assert not timed_out['ok'] and 'timeout' in timed_out['error']
        recovered = engine.evaluate_dual_plane_filter_batch(points[:4097], candidates, .5)
        assert recovered['ok'] and recovered['cpu_fallback_count'] == 0
        report.update(status='PASS', cancelled_then_recovered=True, timed_out_then_recovered=True)
    except Exception as exc:
        report.update(status='FAIL', error=repr(exc))
        raise
    finally:
        engine.close()
        args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('POINT_BATCH_HARDWARE_PASS', flush=True)


if __name__ == '__main__':
    main()
