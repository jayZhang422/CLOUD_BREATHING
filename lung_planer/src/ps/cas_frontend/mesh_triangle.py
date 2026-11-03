"""Continuous triangle separation queries in float64 STL coordinates."""
import numpy as np


def unique_rows(rows):
    """``np.unique(rows, axis=0, return_inverse=True)`` without the void-dtype sort.

    Same sorted unique rows and the same inverse indices. ``axis=0`` sorts a
    structured view row by row, which was ~6x slower than a column lexsort on
    the board. Rows are compared exactly, so -0.0 and 0.0 stay one row, as in
    numpy. Non-finite input falls back to numpy (NaN ordering is not ours to
    redefine).
    """
    rows = np.asarray(rows)
    if rows.ndim != 2 or not len(rows) or (rows.dtype.kind == 'f' and not np.isfinite(rows).all()):
        vertices, inverse = np.unique(rows, axis=0, return_inverse=True)
        return vertices, inverse.reshape(-1)
    order = np.lexsort(rows.T[::-1])
    ordered = rows[order]
    first = np.empty(len(ordered), dtype=bool)
    first[0] = True
    np.any(ordered[1:] != ordered[:-1], axis=1, out=first[1:])
    inverse = np.empty(len(rows), dtype=np.intp)
    inverse[order] = np.cumsum(first) - 1
    return ordered[first], inverse


def _point_triangle_distance(point, triangle):
    a, b, c = triangle
    ab, ac, ap = b - a, c - a, point - a
    d1, d2 = np.dot(ab, ap), np.dot(ac, ap)
    if d1 <= 0.0 and d2 <= 0.0:
        return float(np.linalg.norm(ap))
    bp = point - b
    d3, d4 = np.dot(ab, bp), np.dot(ac, bp)
    if d3 >= 0.0 and d4 <= d3:
        return float(np.linalg.norm(bp))
    vc = d1 * d4 - d3 * d2
    if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
        t = d1 / (d1 - d3)
        return float(np.linalg.norm(point - (a + t * ab)))
    cp = point - c
    d5, d6 = np.dot(ab, cp), np.dot(ac, cp)
    if d6 >= 0.0 and d5 <= d6:
        return float(np.linalg.norm(cp))
    vb = d5 * d2 - d1 * d6
    if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
        t = d2 / (d2 - d6)
        return float(np.linalg.norm(point - (a + t * ac)))
    va = d3 * d6 - d5 * d4
    if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
        t = (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return float(np.linalg.norm(point - (b + t * (c - b))))
    denom = va + vb + vc
    if abs(denom) <= 1e-24:
        return min(_segment_segment_distance(a, b, c, c),
                   _segment_segment_distance(b, c, a, a),
                   _segment_segment_distance(c, a, b, b))
    v, w = vb / denom, vc / denom
    return float(np.linalg.norm(point - (a + ab * v + ac * w)))


def _segment_segment_distance(p0, p1, q0, q1):
    u, v, w = p1 - p0, q1 - q0, p0 - q0
    aa, bb, cc = np.dot(u, u), np.dot(u, v), np.dot(v, v)
    dd, ee = np.dot(u, w), np.dot(v, w)
    denom = aa * cc - bb * bb
    small = 1e-24
    s_num, s_den = denom, denom
    t_num, t_den = denom, denom
    if denom <= small:
        s_num, s_den = 0.0, 1.0
        t_num, t_den = ee, cc
    else:
        s_num, t_num = bb * ee - cc * dd, aa * ee - bb * dd
        if s_num < 0.0:
            s_num, t_num, t_den = 0.0, ee, cc
        elif s_num > s_den:
            s_num, t_num, t_den = s_den, ee + bb, cc
    if t_num < 0.0:
        t_num = 0.0
        if -dd < 0.0:
            s_num = 0.0
        elif -dd > aa:
            s_num = s_den
        else:
            s_num, s_den = -dd, aa
    elif t_num > t_den:
        t_num = t_den
        if -dd + bb < 0.0:
            s_num = 0.0
        elif -dd + bb > aa:
            s_num = s_den
        else:
            s_num, s_den = -dd + bb, aa
    sc = 0.0 if abs(s_num) <= small else s_num / s_den
    tc = 0.0 if abs(t_num) <= small else t_num / t_den
    return float(np.linalg.norm(w + sc * u - tc * v))


def _segment_intersects_triangle(start, end, triangle, tolerance=1e-10):
    a, b, c = triangle
    direction = end - start
    e1, e2 = b - a, c - a
    h = np.cross(direction, e2)
    det = float(np.dot(e1, h))
    if abs(det) <= tolerance:
        return False
    inv = 1.0 / det
    s = start - a
    u = inv * float(np.dot(s, h))
    if u < -tolerance or u > 1.0 + tolerance:
        return False
    q = np.cross(s, e1)
    v = inv * float(np.dot(direction, q))
    if v < -tolerance or u + v > 1.0 + tolerance:
        return False
    t = inv * float(np.dot(e2, q))
    return -tolerance <= t <= 1.0 + tolerance


def triangle_triangle_distance(first, second, tolerance=1e-9):
    """Return the minimum Euclidean distance between two closed triangles."""
    first, second = np.asarray(first, dtype=np.float64), np.asarray(second, dtype=np.float64)
    for i in range(3):
        if _segment_intersects_triangle(first[i], first[(i + 1) % 3], second):
            return 0.0
        if _segment_intersects_triangle(second[i], second[(i + 1) % 3], first):
            return 0.0
    distances = [_point_triangle_distance(point, second) for point in first]
    distances.extend(_point_triangle_distance(point, first) for point in second)
    for i in range(3):
        for j in range(3):
            distances.append(_segment_segment_distance(
                first[i], first[(i + 1) % 3], second[j], second[(j + 1) % 3]))
    result = min(distances)
    return 0.0 if result <= tolerance else result


def triangle_mesh_min_distance(triangle, mesh_triangles, mesh_bounds=None,
                               nearest_vertex_tree=None, upper_bound=None):
    """Check complete triangles, using AABBs and vectorized feature pairs.

    This is a floating-point geometric query, not an exact-predicate kernel.
    Vertex/face and edge/edge distances cover disjoint triangles; segment/face
    intersection checks also detect transverse crossings through face interiors.
    With upper_bound, the result is capped there for minimum-distance searches.
    """
    triangle = np.asarray(triangle, dtype=np.float64).reshape(3, 3)
    mesh = np.asarray(mesh_triangles, dtype=np.float64).reshape(-1, 3, 3)
    if not len(mesh):
        return float('inf')
    if mesh_bounds is None:
        mesh_min, mesh_max = mesh.min(axis=1), mesh.max(axis=1)
    else:
        mesh_min, mesh_max = mesh_bounds
    patch_min, patch_max = triangle.min(axis=0), triangle.max(axis=0)
    delta = np.maximum(np.maximum(mesh_min - patch_max, patch_min - mesh_max), 0.0)
    lower2 = np.einsum('ij,ij->i', delta, delta)
    # The distance to the patch's infinite plane is another valid lower
    # bound, much tighter than its box for large tilted exterior bases.
    normal = np.cross(triangle[1] - triangle[0], triangle[2] - triangle[0])
    length = float(np.linalg.norm(normal))
    if length > 1e-12:
        signed = np.einsum('tki,i->tk', mesh - triangle[0], normal / length)
        plane_gap = np.maximum(np.maximum(signed.min(axis=1), -signed.max(axis=1)), 0.)
        lower2 = np.maximum(lower2, plane_gap * plane_gap)
    if nearest_vertex_tree is None:
        mesh_vertices = mesh.reshape(-1, 3)
        upper = min(float(np.linalg.norm(point - mesh_vertices, axis=1).min())
                    for point in triangle)
    else:
        upper = float(np.min(nearest_vertex_tree.query(triangle, k=1)[0]))
        # Keep the spatial query conservative at the floating-point boundary.
        upper = float(np.nextafter(upper + 1e-12, np.inf))
    if upper_bound is not None and np.isfinite(upper_bound):
        upper = min(upper, float(np.nextafter(upper_bound + 1e-9, np.inf)))
    if upper <= 1e-9:
        upper = 0.0
    candidates = np.flatnonzero(lower2 <= upper * upper + 1e-18)
    if not len(candidates):
        return upper
    mesh = mesh[candidates]
    # The same 3 vertex/face and 9 edge/edge features, evaluated together.
    # Bounds, candidate membership, tolerances and the scalar upper cap above
    # are unchanged. Broadcasting adds feature axes, never drops triangles.
    p0 = triangle
    p1 = triangle[[1, 2, 0]]
    q0 = mesh
    q1 = mesh[:, [1, 2, 0]]
    if (np.any(_segments_hit_triangles(p0, p1, mesh[:, None])) or
            np.any(_segments_hit_triangles(q0, q1, triangle))):
        return 0.
    best2 = np.full(len(mesh), upper * upper)
    best2 = np.minimum(best2, _points_triangles_distance2(p0, mesh[:, None]).min(axis=1))
    best2 = np.minimum(best2, _points_triangles_distance2(q0, triangle).min(axis=1))
    edge2 = _segments_distance2(p0[None, :, None], p1[None, :, None],
                               q0[:, None], q1[:, None])
    best2 = np.minimum(best2, edge2.min(axis=(1, 2)))
    gap = float(np.sqrt(np.min(best2)))
    return 0. if gap <= 1e-9 else gap




def _points_segments_distance2(point, start, end):
    edge = end - start
    length2 = np.sum(edge * edge, axis=-1)
    numerator = np.sum((point - start) * edge, axis=-1)
    t = np.clip(np.divide(numerator, length2,
                          out=np.zeros_like(numerator), where=length2 > 1e-24), 0., 1.)
    delta = point - start - np.asarray(t)[..., None] * edge
    return np.sum(delta * delta, axis=-1)


def _points_triangles_distance2(point, triangles):
    a, b, c = triangles[..., 0, :], triangles[..., 1, :], triangles[..., 2, :]
    ab, ac, ap = b - a, c - a, point - a
    normal = np.cross(ab, ac)
    n2 = np.sum(normal * normal, axis=-1)
    signed = np.sum(ap * normal, axis=-1)
    d00, d01, d11 = np.sum(ab * ab, axis=-1), np.sum(ab * ac, axis=-1), np.sum(ac * ac, axis=-1)
    d20, d21 = np.sum(ap * ab, axis=-1), np.sum(ap * ac, axis=-1)
    denom = d00 * d11 - d01 * d01
    inv = np.divide(1., denom, out=np.zeros_like(denom), where=denom > 1e-24)
    v, w = (d11 * d20 - d01 * d21) * inv, (d00 * d21 - d01 * d20) * inv
    inside = (denom > 1e-24) & (v >= 0.) & (w >= 0.) & (v + w <= 1.)
    face2 = np.divide(signed * signed, n2, out=np.full_like(signed, np.inf), where=n2 > 1e-24)
    best = np.where(inside, face2, np.inf)
    for start, end in ((a, b), (b, c), (c, a)):
        best = np.minimum(best, _points_segments_distance2(point, start, end))
    return best


def _segments_distance2(p0, p1, q0, q1):
    u, v, w = p1 - p0, q1 - q0, p0 - q0
    aa, bb, cc = np.sum(u * u, axis=-1), np.sum(u * v, axis=-1), np.sum(v * v, axis=-1)
    dd, ee = np.sum(u * w, axis=-1), np.sum(v * w, axis=-1)
    denom = aa * cc - bb * bb
    usable = denom > 1e-14 * np.maximum(aa * cc, 1e-24)
    s = np.divide(bb * ee - cc * dd, denom, out=np.zeros_like(denom), where=usable)
    t = np.divide(aa * ee - bb * dd, denom, out=np.zeros_like(denom), where=usable)
    interior = usable & (s >= 0.) & (s <= 1.) & (t >= 0.) & (t <= 1.)
    delta = w + s[..., None] * u - t[..., None] * v
    best = np.where(interior, np.sum(delta * delta, axis=-1), np.inf)
    for point, start, end in ((p0, q0, q1), (p1, q0, q1), (q0, p0, p1), (q1, p0, p1)):
        best = np.minimum(best, _points_segments_distance2(point, start, end))
    return best


def _segments_hit_triangles(start, end, triangles):
    a, b, c = triangles[..., 0, :], triangles[..., 1, :], triangles[..., 2, :]
    direction, e1, e2 = end - start, b - a, c - a
    h = np.cross(direction, e2)
    det = np.sum(e1 * h, axis=-1)
    usable = np.abs(det) > 1e-10
    inv = np.divide(1., det, out=np.zeros_like(det), where=usable)
    offset = start - a
    u = inv * np.sum(offset * h, axis=-1)
    q = np.cross(offset, e1)
    v = inv * np.sum(direction * q, axis=-1)
    t = inv * np.sum(e2 * q, axis=-1)
    tol = 1e-10
    return usable & (u >= -tol) & (v >= -tol) & (u + v <= 1. + tol) & (t >= -tol) & (t <= 1. + tol)


def closest_point_on_mesh(point, mesh_triangles):
    """Return the closest point and face index on a triangle mesh."""
    point = np.asarray(point, dtype=np.float64).reshape(3)
    mesh = np.asarray(mesh_triangles, dtype=np.float64).reshape(-1, 3, 3)
    if not len(mesh):
        raise ValueError('cannot find closest point on an empty mesh')
    a, b, c = mesh[:, 0], mesh[:, 1], mesh[:, 2]
    e1, e2 = b - a, c - a
    normal = np.cross(e1, e2)
    n2 = np.einsum('ij,ij->i', normal, normal)
    signed = np.einsum('ij,ij->i', point - a, normal)
    projected = a + (point - a) - normal * np.divide(
        signed, n2, out=np.zeros_like(signed), where=n2 > 1e-24)[:, None]
    d00 = np.einsum('ij,ij->i', e1, e1)
    d01 = np.einsum('ij,ij->i', e1, e2)
    d11 = np.einsum('ij,ij->i', e2, e2)
    d20 = np.einsum('ij,ij->i', projected - a, e1)
    d21 = np.einsum('ij,ij->i', projected - a, e2)
    denom = d00 * d11 - d01 * d01
    inv = np.divide(1., denom, out=np.zeros_like(denom), where=denom > 1e-24)
    v = (d11 * d20 - d01 * d21) * inv
    w = (d00 * d21 - d01 * d20) * inv
    inside = (denom > 1e-24) & (v >= 0.) & (w >= 0.) & (v + w <= 1.)
    best = np.where(inside[:, None], projected, np.inf)
    for start, edge in ((a, e1), (b, c - b), (c, a - c)):
        length2 = np.einsum('ij,ij->i', edge, edge)
        t = np.clip(np.divide(np.einsum('ij,ij->i', point - start, edge), length2,
                              out=np.zeros_like(length2), where=length2 > 1e-24), 0., 1.)
        candidate = start + edge * t[:, None]
        improve = np.einsum('ij,ij->i', point - candidate, point - candidate) < np.einsum(
            'ij,ij->i', point - best, point - best)
        best[improve] = candidate[improve]
    distances2 = np.einsum('ij,ij->i', point - best, point - best)
    index = int(np.argmin(distances2))
    return best[index].copy(), index


def mesh_is_watertight(mesh_triangles, tolerance=1e-5):
    """Check that every quantized undirected mesh edge belongs to two faces."""
    triangles = np.asarray(mesh_triangles, dtype=np.float64).reshape(-1, 3, 3)
    if not len(triangles) or not np.isfinite(triangles).all():
        return False
    vertices = np.rint(triangles / tolerance).astype(np.int64)
    _, ids = unique_rows(vertices.reshape(-1, 3))
    ids = ids.reshape(-1, 3)
    if np.any(ids[:, 0] == ids[:, 1]) or np.any(ids[:, 1] == ids[:, 2]) or np.any(ids[:, 2] == ids[:, 0]):
        return False
    if np.any(np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0],
                                     triangles[:, 2] - triangles[:, 0]), axis=1) <= 1e-12):
        return False
    edges = np.concatenate((ids[:, (0, 1)], ids[:, (1, 2)], ids[:, (2, 0)]), axis=0)
    edges.sort(axis=1)
    _, edge_ids = unique_rows(edges)
    counts = np.bincount(edge_ids)
    return bool(len(counts) and np.all(counts == 2))
