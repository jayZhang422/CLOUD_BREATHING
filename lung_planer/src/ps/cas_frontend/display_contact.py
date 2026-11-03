"""Batched CPU display-only proximity/parity queries; no PL mesh changes."""
import numpy as np
import os
from time import perf_counter
from .mesh_triangle import _points_triangles_distance2
from .ray_golden import HIT_TOLERANCE_MM
from .planning_cancel import checkpoint


def _leaf_pairs(index, points, accept):
    """Traverse BVH point/node pairs together; bound callers to small chunks."""
    children, leaf, members, width = index.display_contact_arrays()
    p, n = np.arange(len(points)), np.zeros(len(points), dtype=int)
    while len(n):
        checkpoint()
        valid = accept(points[p], index.low[n], index.high[n])
        p, n = p[valid], n[valid]
        terminal = leaf[n]
        if np.any(terminal):
            triangles = members[n[terminal]].ravel()
            point_ids = np.repeat(p[terminal], width)
            keep = triangles >= 0
            yield point_ids[keep], triangles[keep]
        p, n = np.repeat(p[~terminal],2), children[n[~terminal]].ravel()


def numpy_contact_mask(index, points, tolerance=1.):
    """Match scalar distance<=tolerance OR ray parity, in bounded batches."""
    started = perf_counter()
    points = np.asarray(points, dtype=float).reshape(-1,3)
    result = np.zeros(len(points), dtype=bool)
    direction = np.array([1., .371390676, .127831])
    direction /= np.linalg.norm(direction)
    inv = 1./direction
    stats = getattr(index, '_display_contact_stats', None)
    if stats is None:
        stats = dict(calls=0, points=0, distance_triangle_pairs=0,
                     ray_triangle_pairs=0, proximity_ms=0., parity_ms=0., total_ms=0.)
        index._display_contact_stats = stats
    stats['calls'] += 1
    stats['points'] += len(points)
    def close(p, low, high):
        delta = np.maximum(np.maximum(low-p,p-high),0.)
        return np.einsum('ij,ij->i',delta,delta) <= tolerance*tolerance
    def ray_box(p, low, high):
        a, b = (low-1e-7-p)*inv, (high+1e-7-p)*inv
        return np.maximum(a,b).min(axis=1) >= np.maximum(np.minimum(a,b).max(axis=1),0.)
    try:
        chunk_points = int(os.environ.get('CLOUD_BREATHING_DISPLAY_BATCH_POINTS', '1024'))
    except ValueError:
        chunk_points = 1024
    chunk_points = min(16384, max(1, chunk_points))
    for start in range(0,len(points),chunk_points):
        checkpoint()
        chunk = points[start:start+chunk_points]
        mask = np.zeros(len(chunk),dtype=bool)
        phase_started = perf_counter()
        for p,t in _leaf_pairs(index,chunk,close):
            stats['distance_triangle_pairs'] += len(t)
            valid = _points_triangles_distance2(chunk[p],index.triangles[t]) <= tolerance*tolerance
            mask[p[valid]] = True
        stats['proximity_ms'] += (perf_counter()-phase_started)*1000.
        remaining = np.flatnonzero(~mask)
        origins = chunk[remaining] + direction*1e-5
        hit_p, hit_t = [], []
        phase_started = perf_counter()
        for p,t in _leaf_pairs(index,origins,ray_box):
            stats['ray_triangle_pairs'] += len(t)
            tri = index.triangles[t]
            a = tri[:,0]
            e1,e2 = tri[:,1]-a, tri[:,2]-a
            h = np.cross(direction,e2)
            det = np.einsum('ij,ij->i',e1,h)
            reciprocal = np.divide(1.,det,out=np.zeros_like(det),where=np.abs(det)>=1e-9)
            offset = origins[p]-a
            u = reciprocal*np.einsum('ij,ij->i',offset,h)
            q = np.cross(offset,e1)
            v = reciprocal*np.einsum('ij,j->i',q,direction)
            distance = reciprocal*np.einsum('ij,ij->i',e2,q)
            valid = ((np.abs(det)>=1e-9)&(u>=-1e-7)&(u<=1.0000001)&(v>=-1e-7)
                     &(u+v<=1.0000001)&(distance>=0.))
            hit_p.append(p[valid]); hit_t.append(distance[valid])
        if hit_p:
            ids, distances = np.concatenate(hit_p), np.concatenate(hit_t)
            order = np.lexsort((distances,ids))
            ids, distances = ids[order],distances[order]
            if len(ids):
                unique = np.r_[True,(np.diff(ids)!=0)|(np.diff(distances)>HIT_TOLERANCE_MM)]
                count = np.bincount(ids[unique],minlength=len(origins))
                mask[remaining] |= (count%2).astype(bool)
        stats['parity_ms'] += (perf_counter()-phase_started)*1000.
        result[start:start+len(chunk)] = mask
    stats['total_ms'] += (perf_counter()-started)*1000.
    return result


def contact_mask(index, points, tolerance=1.):
    """Use native PS queries when installed; preserve NumPy at FP boundaries."""
    backend = os.environ.get('CLOUD_BREATHING_DISPLAY_CONTACT_BACKEND', 'auto')
    if backend not in ('auto', 'numpy', 'native'):
        raise ValueError('Unknown display contact backend: ' + backend)
    if backend == 'numpy':
        return numpy_contact_mask(index, points, tolerance)
    from .display_contact_native import library, query
    try:
        library()
    except OSError:
        if backend == 'native':
            raise
        return numpy_contact_mask(index, points, tolerance)
    points = np.ascontiguousarray(points, dtype=np.float64).reshape(-1, 3)
    if not np.isfinite(points).all() or not np.isfinite(tolerance) or tolerance < 0.:
        return numpy_contact_mask(index, points, tolerance)
    started = perf_counter()
    stats = getattr(index, '_display_contact_stats', None)
    if stats is None:
        stats = dict(calls=0, points=0, distance_triangle_pairs=0,
                     ray_triangle_pairs=0, proximity_ms=0., parity_ms=0., total_ms=0.)
        index._display_contact_stats = stats
    stats['calls'] += 1
    stats['points'] += len(points)
    result = np.zeros(len(points), dtype=bool)
    direction = np.array([1., .371390676, .127831])
    direction /= np.linalg.norm(direction)
    # Bounded work and cooperative cancellation between calls, with no task queue.
    guard_ms = 0.
    for start in range(0, len(points), 256):
        checkpoint()
        chunk = points[start:start+256]
        native_started = perf_counter()
        mask, guard, counters = query(index, chunk, tolerance, direction, HIT_TOLERANCE_MM)
        stats['native_compute_ms'] = stats.get('native_compute_ms', 0.) + (perf_counter()-native_started)*1000.
        stats['distance_triangle_pairs'] += int(counters[0])
        stats['ray_triangle_pairs'] += int(counters[1])
        stats['native_calls'] = stats.get('native_calls', 0) + 1
        stats['native_points'] = stats.get('native_points', 0) + len(chunk)
        if np.any(guard):
            # The original predicate decides ambiguous points; never change
            # ray sorting, adjacent-hit deduplication, parity, or tolerances.
            guard_started = perf_counter()
            mask[guard] = numpy_contact_mask(index, chunk[guard], tolerance)
            guard_ms += (perf_counter()-guard_started)*1000.
            stats['numpy_guard_points'] = stats.get('numpy_guard_points', 0) + int(guard.sum())
        result[start:start+len(chunk)] = mask
    checkpoint()
    elapsed_ms = (perf_counter()-started)*1000.
    stats['numpy_guard_ms'] = stats.get('numpy_guard_ms', 0.) + guard_ms
    stats['total_ms'] += max(0., elapsed_ms-guard_ms)
    return result
