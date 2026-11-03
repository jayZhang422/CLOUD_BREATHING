"""PL vs PS timing of the dual-plane mesh kernel on a synthetic lung-like mesh.

Both sides compute the same quantity for the same candidates: volume, surface area and cut area
of (mesh intersect wedge) for N wedge candidates.  No patient data is used.

  gen   build the synthetic mesh and candidates (numpy only)          -> inputs.npz
  ps    PS baseline: exact float64 Manifold Boolean per candidate,    -> ps.json
        i.e. the planner's CPU path (run in the app venv, needs manifold3d)
  pl    PL ABI 0x00050000 batch, cold then warm (run as root via      -> pl.json
        tools/start_pl_service.sh in the PYNQ venv)
  compare  parity and speedup from the two JSON files

PS and PL must run on the same board (ARM Cortex-A53) for the comparison to be meaningful.
This times the kernel only; it is not the end-to-end planning time, which also includes
candidate generation, BVH build and final review on the PS.
"""
import argparse
import json
import os
import statistics
import sys
import time
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
METRICS = ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2')


def icosphere(subdivisions):
    t = (1 + 5 ** .5) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
         (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
         (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    verts = [np.asarray(p, float) / np.linalg.norm(p) for p in v]
    for _ in range(subdivisions):
        cache, faces = {}, []

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                m = verts[a] + verts[b]
                verts.append(m / np.linalg.norm(m))
                cache[key] = len(verts) - 1
            return cache[key]
        for a, b, c in f:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            faces += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        f = faces
    return np.asarray(verts), np.asarray(f)


def lung_like_mesh(subdivisions, seed):
    """Closed, deformed ellipsoid (about 2 x 3 x 4 cm scale factors in mm), smooth lobulation."""
    rng = np.random.default_rng(seed)
    v, f = icosphere(subdivisions)
    phase = rng.uniform(0, 2 * np.pi, (3, 3))
    bump = sum(.06 * np.sin(k * v[:, [0]] * 2 + phase[k - 1, 0]) * np.cos(k * v[:, [1]] * 2 + phase[k - 1, 1])
               * np.sin(k * v[:, [2]] * 2 + phase[k - 1, 2]) for k in (1, 2, 3))
    v = v * (1 + bump) * np.array([60., 90., 120.])
    tri = v[f]
    normal = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    if (np.einsum('ij,ij->i', normal, tri.mean(axis=1))).sum() < 0:
        tri = tri[:, ::-1]
    return np.ascontiguousarray(tri)


def make_candidates(count, seed):
    """Dual-plane wedges as the planner builds them: tetra = (base0, base1, base2, apex).

    The two physical planes are faces (base0, apex, base1) and (base1, apex, base2); they meet along
    the ridge base1-apex, which passes near the mesh centre.  The other two faces are auxiliary caps
    and lie far outside the mesh, so (mesh intersect tetra) equals the two-plane wedge that the PL
    kernel integrates.
    """
    rng = np.random.default_rng(seed + 1)
    ridge_half, reach = 400., 900.
    out = []
    for _ in range(count):
        r = rng.normal(size=3)
        r /= np.linalg.norm(r)
        u = np.cross(r, rng.normal(size=3))
        u /= np.linalg.norm(u)
        v = np.cross(r, u)
        centre = rng.uniform(-25, 25, 3)
        heading = rng.uniform(0, 2 * np.pi)
        half_angle = np.radians(rng.uniform(20, 65))
        d1 = np.cos(heading + half_angle) * u + np.sin(heading + half_angle) * v
        d2 = np.cos(heading - half_angle) * u + np.sin(heading - half_angle) * v
        base1, apex = centre - r * ridge_half, centre + r * ridge_half
        out.append(np.vstack([base1 + reach * d1, base1, base1 + reach * d2, apex]))
    return np.asarray(out)


def percentile(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def cmd_gen(args):
    tri = lung_like_mesh(args.subdivisions, args.seed)
    cand = make_candidates(args.candidates, args.seed)
    np.savez(args.inputs, triangles=tri, candidates=cand)
    print('GEN triangles=%d candidates=%d' % (len(tri), len(cand)))


def cmd_ps(args):
    from cas_frontend.dual_plane_reference import manifold_volume_metrics
    from cas_frontend.mesh_union import _solid
    data = np.load(args.inputs)
    tri, cand = data['triangles'], data['candidates'][:args.limit]
    started = time.perf_counter()
    solid = _solid(tri, 'synthetic')
    build_s = time.perf_counter() - started
    rows, times, totals = [], [], []
    for run in range(args.repeats):
        rows, times = [], []
        for vertices in cand:
            started = time.perf_counter()
            m = manifold_volume_metrics(solid, vertices)
            times.append(time.perf_counter() - started)
            rows.append([float(m[k]) for k in METRICS])
        totals.append(float(sum(times)))
        print('PS run %d total=%.3f s' % (run, totals[-1]), flush=True)
    total = float(statistics.median(totals))
    out = dict(side='ps', platform=os.uname().machine, cpu_threads=os.cpu_count(), triangles=len(tri),
               candidates=len(cand), solid_build_s=build_s, total_s=total, runs_total_s=totals,
               per_candidate_ms=dict(mean=1e3 * total / len(cand), p50=1e3 * statistics.median(times),
                                     p95=1e3 * percentile(times, .95)),
               metrics=rows)
    Path(args.out).write_text(json.dumps(out, indent=1))
    print('PS candidates=%d total=%.3f s mean=%.1f ms/candidate' % (len(cand), total, out['per_candidate_ms']['mean']))


def cmd_pl(args):
    os.environ['LUNG_PL_BIT'] = str(Path(args.bit).resolve())
    os.environ['LUNG_PL_ENABLE'] = '1'
    from cas_frontend.pl_metrics import PlMetrics
    data = np.load(args.inputs)
    tri, cand = data['triangles'], data['candidates'][:args.limit]
    engine = PlMetrics()
    try:
        runs = []
        for index in range(args.repeats):
            started = time.perf_counter()
            result = engine.evaluate_dual_plane_mesh_batch(tri, cand, timeout_seconds=600., reference_only=False)
            wall = time.perf_counter() - started
            # Per-candidate flags (e.g. 0x20 BINDING_CAP) are reported, not fatal: compare() counts them.
            if (not result.get('ok') or result.get('cpu_fallback_count') != 0 or result.get('errors') != 0
                    or result.get('reference_only') is not False):
                raise RuntimeError('PL batch rejected: ' + str(result.get('error', result))[:300])
            runs.append(dict(wall_s=wall, cycles=result['cycles'], core_s=result['cycles'] / (result['clock_mhz'] * 1e6),
                             resident_mesh_reused=bool(result.get('resident_mesh_reused')),
                             clock_mhz=result['clock_mhz'], metrics=[[c[k] for k in METRICS] for c in result['candidates']],
                             flags=[int(c.get('flags', 0)) for c in result['candidates']]))
            print('PL run %d wall=%.3f s core=%.3f s reused=%s' % (index, wall, runs[-1]['core_s'], runs[-1]['resident_mesh_reused']), flush=True)
    finally:
        engine.close()
    warm = [r['wall_s'] for r in runs[1:]] or [runs[0]['wall_s']]
    out = dict(side='pl', bit=Path(args.bit).name, triangles=len(tri), candidates=len(cand),
               cold_wall_s=runs[0]['wall_s'], warm_wall_s_median=statistics.median(warm), core_s=runs[0]['core_s'],
               clock_mhz=runs[0]['clock_mhz'], runs=[{k: v for k, v in r.items() if k != 'metrics'} for r in runs],
               metrics=runs[-1]['metrics'], flags=runs[-1]['flags'])
    Path(args.out).write_text(json.dumps(out, indent=1))
    print('PL candidates=%d cold=%.3f s warm=%.3f s core=%.3f s' % (len(cand), out['cold_wall_s'], out['warm_wall_s_median'], out['core_s']))


def cmd_compare(args):
    ps, pl = json.loads(Path(args.ps).read_text()), json.loads(Path(args.pl).read_text())
    n = min(ps['candidates'], pl['candidates'])
    a, b = np.asarray(ps['metrics'][:n]), np.asarray(pl['metrics'][:n])
    flags = np.asarray(pl['flags'][:n])
    ok = flags == 0
    # A candidate the PL flags must come back with all-zero metrics: it may never return a wrong number.
    flagged_zero = bool((b[~ok] == 0).all()) if (~ok).any() else True
    delta = np.abs(a[ok] - b[ok]).max(axis=0)
    ps_per = ps['total_s'] / ps['candidates']
    ps_extrap = ps_per * pl['candidates']
    rows = dict(triangles=ps['triangles'], candidates=n, compared=int(ok.sum()), tolerance=1e-5,
                pl_flagged=dict(count=int((~ok).sum()), indices=[int(i) for i in np.where(~ok)[0]],
                                flags=sorted({hex(int(f)) for f in flags[~ok]}), returned_all_zero=flagged_zero),
                max_abs_delta=dict(zip(METRICS, map(float, delta))),
                parity_pass=bool((delta <= 1e-5).all() and flagged_zero),
                ps_runs_total_s=ps.get('runs_total_s', [ps['total_s']]), ps_per_candidate_ms=1e3 * ps_per,
                ps_total_s=ps_extrap, pl_candidates=pl['candidates'], pl_cold_wall_s=pl['cold_wall_s'],
                pl_warm_wall_s=pl['warm_wall_s_median'], pl_core_s=pl['core_s'], pl_clock_mhz=pl['clock_mhz'],
                speedup_cold=ps_extrap / pl['cold_wall_s'], speedup_warm=ps_extrap / pl['warm_wall_s_median'],
                speedup_core_only=ps_extrap / pl['core_s'])
    Path(args.out).write_text(json.dumps(rows, indent=1))
    print(json.dumps(rows, indent=1))
    return 0 if rows['parity_pass'] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='cmd', required=True)
    g = sub.add_parser('gen'); g.add_argument('--inputs', required=True)
    g.add_argument('--subdivisions', type=int, default=5); g.add_argument('--candidates', type=int, default=780)
    g.add_argument('--seed', type=int, default=20261104); g.set_defaults(func=cmd_gen)
    p = sub.add_parser('ps'); p.add_argument('--inputs', required=True); p.add_argument('--out', required=True)
    p.add_argument('--limit', type=int, default=10 ** 9); p.add_argument('--repeats', type=int, default=3)
    p.set_defaults(func=cmd_ps)
    q = sub.add_parser('pl'); q.add_argument('--inputs', required=True); q.add_argument('--out', required=True)
    q.add_argument('--bit', required=True); q.add_argument('--limit', type=int, default=10 ** 9)
    q.add_argument('--repeats', type=int, default=3); q.set_defaults(func=cmd_pl)
    c = sub.add_parser('compare'); c.add_argument('--ps', required=True); c.add_argument('--pl', required=True)
    c.add_argument('--out', required=True); c.set_defaults(func=cmd_compare)
    args = parser.parse_args()
    sys.exit(args.func(args) or 0)


if __name__ == '__main__':
    main()
