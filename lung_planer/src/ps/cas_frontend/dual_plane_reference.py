"""Software references for the dual-plane accelerators.

The Q16.16 point filter is kept bit-accurate with ABI 0x00030000.  The mesh
path below is a float64 reference for the next ABI: it clips every source
triangle against the four half-spaces of the wedge, reconstructs the two
generated cut surfaces from their boundary segments, and reduces the closed
surface with the divergence theorem.  It deliberately does not voxelize,
resample, or repair the source mesh.
"""
import math

import numpy as np

from .pl_metrics import _q16


def evaluate(points, planes, margin_mm):
    points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
    planes = np.asarray(planes, dtype=np.int32).reshape(2, 4)
    if not len(points) or not np.isfinite(points).all():
        raise ValueError('reference requires finite nonempty points')
    margin = _q16(margin_mm)
    threshold = margin << 16
    minimum = None
    accepted = 0
    for point in points:
        qpoint = tuple(_q16(value) for value in point)
        distances = [sum(int(planes[i, axis]) * qpoint[axis] for axis in range(3)) +
                     (int(planes[i, 3]) << 16) for i in range(2)]
        point_min = min(distances)
        minimum = point_min if minimum is None else min(minimum, point_min)
        accepted += int(all(distance >= threshold for distance in distances))
    shifted = minimum >> 16
    shifted = max(-0x80000000, min(0x7fffffff, shifted))
    return dict(processed=len(points), accepted=accepted,
                min_margin_q16=shifted, clearance_mm=shifted / 65536.0)


def float64_clearance(points, planes):
    points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
    planes = np.asarray(planes, dtype=np.float64).reshape(2, 4) / 65536.0
    return float((points @ planes[:, :3].T + planes[:, 3]).min())


def _tetra_planes(vertices):
    """Return inward-positive unit half-spaces for a tetrahedron."""
    from . import planner_reference as ref
    faces = ref.tetra_faces([tuple(row) for row in np.asarray(vertices[:3], dtype=float)],
                            tuple(np.asarray(vertices[3], dtype=float)))
    return [(np.asarray(face[3], dtype=np.float64),
             float(np.dot(face[3], face[0]))) for face in faces]


def _clip_polygon(polygon, normal, offset, eps=1e-10):
    """Sutherland-Hodgman clip of a convex polygon by n·x <= offset."""
    polygon = [np.asarray(point, dtype=np.float64) for point in polygon]
    if not polygon:
        return []
    out = []
    previous = polygon[-1]
    previous_inside = float(np.dot(normal, previous)) <= offset + eps
    for current in polygon:
        current_inside = float(np.dot(normal, current)) <= offset + eps
        if current_inside != previous_inside:
            denominator = float(np.dot(normal, current - previous))
            if abs(denominator) > 1e-15:
                t = (offset - float(np.dot(normal, previous))) / denominator
                out.append(previous + np.clip(t, 0., 1.) * (current - previous))
        if current_inside:
            out.append(current)
        previous, previous_inside = current, current_inside
    # Remove adjacent duplicates introduced by a vertex landing on a plane.
    compact = []
    for point in out:
        if not compact or not np.allclose(point, compact[-1], rtol=0., atol=1e-10):
            compact.append(point)
    if len(compact) > 1 and np.allclose(compact[0], compact[-1], rtol=0., atol=1e-10):
        compact.pop()
    return compact


def _polygon_area(polygon):
    if len(polygon) < 3:
        return 0.
    origin = polygon[0]
    return float(sum(np.linalg.norm(np.cross(polygon[i] - origin,
                                             polygon[i + 1] - origin))
                     for i in range(1, len(polygon) - 1)) * .5)


def _quantized_key(point, quantum=1e-5):
    return tuple(int(round(float(value) / quantum)) for value in point)


def _point_inside_mesh(point, triangles):
    """Odd-even test used only to retain tetra-face edges inside the source."""
    point = np.asarray(point, dtype=np.float64)
    # Boundary points occur at tetrahedron edges.  Treat them as inside so
    # interval reconstruction does not collapse a valid edge to zero length.
    for a, b, c in np.asarray(triangles, dtype=np.float64):
        ab, ac = b - a, c - a
        normal = np.cross(ab, ac)
        norm = np.linalg.norm(normal)
        if norm < 1e-14 or abs(float(np.dot(point - a, normal))) > 1e-7 * norm:
            continue
        u = float(np.dot(point - a, ab)); v = float(np.dot(point - a, ac))
        aa, bb, cc = float(np.dot(ab, ab)), float(np.dot(ab, ac)), float(np.dot(ac, ac))
        det = aa * cc - bb * bb
        if abs(det) < 1e-14:
            continue
        bary_b = (cc * u - bb * v) / det
        bary_c = (aa * v - bb * u) / det
        if bary_b >= -1e-8 and bary_c >= -1e-8 and bary_b + bary_c <= 1. + 1e-8:
            return True
    direction = np.asarray((1., 0.3713906763541037, 0.1131702312548197))
    direction /= np.linalg.norm(direction)
    hits = 0
    for a, b, c in np.asarray(triangles, dtype=np.float64):
        edge1, edge2 = b - a, c - a
        cross = np.cross(direction, edge2)
        det = float(np.dot(edge1, cross))
        if abs(det) < 1e-14:
            continue
        inv = 1. / det
        tvec = point - a
        u = float(np.dot(tvec, cross) * inv)
        if u < -1e-10 or u > 1. + 1e-10:
            continue
        qvec = np.cross(tvec, edge1)
        v = float(np.dot(direction, qvec) * inv)
        if v < -1e-10 or u + v > 1. + 1e-10:
            continue
        distance = float(np.dot(edge2, qvec) * inv)
        if distance > 1e-9:
            hits += 1
    return bool(hits & 1)


def _inside_segment_intervals(a, b, triangles):
    """Split a tetra edge at every source-face crossing, then classify spans."""
    mesh = np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
    direction = np.asarray(b - a, dtype=np.float64)
    edge1 = mesh[:, 1] - mesh[:, 0]
    edge2 = mesh[:, 2] - mesh[:, 0]
    pvec = np.cross(direction, edge2)
    determinant = np.einsum('ij,ij->i', edge1, pvec)
    active = np.abs(determinant) > 1e-14
    inv = np.divide(1., determinant, out=np.zeros_like(determinant), where=active)
    tvec = a - mesh[:, 0]
    u = np.einsum('ij,ij->i', tvec, pvec) * inv
    qvec = np.cross(tvec, edge1)
    v = np.einsum('ij,j->i', qvec, direction) * inv
    t = np.einsum('ij,ij->i', edge2, qvec) * inv
    hits = t[active & (u >= -1e-10) & (v >= -1e-10) &
             (u + v <= 1. + 1e-10) & (t > 0.) & (t < 1.)]
    events = np.sort(np.concatenate(([0., 1.], hits)))
    unique = [float(events[0])]
    for event in events[1:]:
        if event - unique[-1] > 1e-10:
            unique.append(float(event))
    intervals = []
    for lo, hi in zip(unique, unique[1:]):
        if _point_inside_mesh(a + direction * ((lo + hi) * .5), mesh):
            intervals.append((a + direction * lo, a + direction * hi))
    return intervals


def _cap_loops(segments, normal, *, strict=False):
    """Join boundary segments into polygon loops on one clipping plane."""
    if not segments:
        return []
    endpoints = {}
    endpoint_sum = []
    endpoint_count = []
    edges = []
    for a, b in segments:
        if np.linalg.norm(a - b) <= 1e-9:
            continue
        ka, kb = _quantized_key(a), _quantized_key(b)
        if ka == kb:
            continue
        if ka not in endpoints:
            endpoints[ka] = len(endpoint_sum)
            endpoint_sum.append(np.zeros(3, dtype=np.float64))
            endpoint_count.append(0)
        if kb not in endpoints:
            endpoints[kb] = len(endpoint_sum)
            endpoint_sum.append(np.zeros(3, dtype=np.float64))
            endpoint_count.append(0)
        ia, ib = endpoints[ka], endpoints[kb]
        endpoint_sum[ia] += a
        endpoint_sum[ib] += b
        endpoint_count[ia] += 1
        endpoint_count[ib] += 1
        edges.append((ia, ib))
    if not edges:
        return []
    points = [total / count for total, count in zip(endpoint_sum, endpoint_count)]
    adjacency = [[] for _ in points]
    for index, (a, b) in enumerate(edges):
        adjacency[a].append((index, b)); adjacency[b].append((index, a))
    if strict and any(len(incident) < 2 or len(incident) % 2 for incident in adjacency):
        degree_counts = {degree: sum(len(incident) == degree for incident in adjacency)
                         for degree in sorted({len(incident) for incident in adjacency})}
        raise ValueError('cap boundary has open or branching vertices: '
                         'edges=%d vertices=%d degrees=%s' %
                         (len(edges), len(points), degree_counts))
    used = set(); loops = []
    for first, (start, _) in enumerate(edges):
        if first in used:
            continue
        stack = [(start, [start], [], {start})]
        closed = None
        while stack and closed is None:
            current, path, path_edges, visited = stack.pop()
            for edge_index, nxt in adjacency[current]:
                if edge_index in used or edge_index in path_edges:
                    continue
                if nxt == start and len(path) >= 3:
                    closed = (path, path_edges + [edge_index])
                    break
                if nxt not in visited:
                    stack.append((nxt, path + [nxt], path_edges + [edge_index],
                                  visited | {nxt}))
        if closed is None:
            if strict:
                raise ValueError('cap boundary did not close into a polygon')
            continue
        path, path_edges = closed
        used.update(path_edges)
        loops.append([points[index] for index in path])
    axis = int(np.argmax(np.abs(normal)))
    projected = [np.delete(np.asarray(loop), axis, axis=1) for loop in loops]
    for index, polygon in enumerate(loops):
        depth = sum(_point_in_polygon(projected[index][0], other)
                    for other_index, other in enumerate(projected)
                    if other_index != index)
        area_vector = sum(np.cross(polygon[i], polygon[(i + 1) % len(polygon)])
                          for i in range(len(polygon)))
        if (float(np.dot(area_vector, normal)) < 0.) == (depth % 2 == 0):
            polygon.reverse()
    return loops


def _point_in_polygon(point, polygon):
    inside = False
    x, y = point
    for a, b in zip(polygon, np.roll(polygon, -1, axis=0)):
        if (a[1] > y) != (b[1] > y):
            crossing_x = a[0] + (y - a[1]) * (b[0] - a[0]) / (b[1] - a[1])
            if x < crossing_x:
                inside = not inside
    return inside


def dual_plane_ridge_origin(vertices, center):
    planes = _tetra_planes(np.asarray(vertices, dtype=np.float64).reshape(4, 3))
    normals = np.asarray([planes[index][0] for index in (1, 2)])
    offsets = np.asarray([planes[index][1] for index in (1, 2)])
    center = np.asarray(center, dtype=np.float64).reshape(3)
    gram = normals @ normals.T
    if np.linalg.det(gram) < 1e-12:
        raise ValueError('dual-plane ridge is ill-conditioned')
    return center + normals.T @ np.linalg.solve(gram, offsets - normals @ center)


def clip_mesh_by_dual_plane(triangles, vertices):
    """Integrate a two-plane wedge without constructing cap polygons.

    Faces 1 and 2 are the physical cuts. Faces 0 and 3 must contain the whole
    source mesh; this is checked here. Choose an origin on the intersection of
    the two cut planes. The flux of (x-origin)/3 through either cut plane is
    then zero. Green's theorem gives each cut area from its oriented source
    boundary; any edge on the common ridge contributes zero as well.
    """
    triangles = np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
    vertices = np.asarray(vertices, dtype=np.float64).reshape(4, 3)
    if not len(triangles) or not np.isfinite(triangles).all() or not np.isfinite(vertices).all():
        raise ValueError('mesh/tetra input is empty or nonfinite')
    planes = _tetra_planes(vertices)
    center = np.mean(np.vstack((triangles.reshape(-1, 3).min(axis=0),
                                triangles.reshape(-1, 3).max(axis=0))), axis=0)
    origin = dual_plane_ridge_origin(vertices, center)
    for index in (0, 3):
        normal, offset = planes[index]
        if np.max(triangles.reshape(-1, 3) @ normal) > offset + 1e-8:
            raise ValueError('nonbinding tetra face %d intersects source mesh' % index)

    source_volume = 0.
    source_area = 0.
    cut_area = np.zeros(2, dtype=np.float64)
    source_triangles = 0
    boundary_segments = 0
    for triangle in triangles:
        polygon = [triangle[0], triangle[1], triangle[2]]
        for normal, offset in planes:
            polygon = _clip_polygon(polygon, normal, offset)
            if len(polygon) < 3:
                break
        if len(polygon) < 3 or _polygon_area(polygon) <= 1e-14:
            continue
        anchor = polygon[0] - origin
        for index in range(1, len(polygon) - 1):
            b = polygon[index] - origin
            c = polygon[index + 1] - origin
            cross = np.cross(b, c)
            source_volume += float(np.dot(anchor, cross) / 6.)
            source_area += float(np.linalg.norm(np.cross(b - anchor, c - anchor)) * .5)
            source_triangles += 1
        for cut_index, face_index in enumerate((1, 2)):
            normal, offset = planes[face_index]
            for a, b in zip(polygon, polygon[1:] + polygon[:1]):
                if (abs(float(np.dot(normal, a)) - offset) <= 2e-7 and
                        abs(float(np.dot(normal, b)) - offset) <= 2e-7 and
                        np.linalg.norm(a - b) > 1e-9):
                    cut_area[cut_index] -= float(np.dot(
                        np.cross(a - origin, b - origin), normal) * .5)
                    boundary_segments += 1
    if np.any(cut_area < -1e-7):
        raise ValueError('cut boundary has inconsistent orientation')
    volume = abs(source_volume)
    return dict(volume_mm3=float(volume), surface_area_mm2=float(source_area),
                cut_area_mm2=float(cut_area.sum()), source_triangles=source_triangles,
                cut_triangles=0, boundary_segments=boundary_segments,
                cap_loops=0, valid=bool(volume > 1e-12 and source_triangles > 0),
                ridge_origin=origin.tolist(), cut_area_by_plane_mm2=cut_area.tolist())


def clip_mesh_by_tetra(triangles, vertices, *, return_surface=False,
                       strict_independent=False):
    """Clip an oriented closed mesh by a tetrahedron using float64 arithmetic.

    Returns the exact same metrics consumed by ``LungUnion.intersect`` for the
    source mesh.  The implementation is intentionally deterministic, which
    makes it suitable as the PS/RTL golden model and for per-candidate parity
    checks before a PL result can affect ranking.
    """
    triangles = np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
    vertices = np.asarray(vertices, dtype=np.float64).reshape(4, 3)
    if not len(triangles) or not np.isfinite(triangles).all() or not np.isfinite(vertices).all():
        raise ValueError('mesh/tetra input is empty or nonfinite')
    planes = _tetra_planes(vertices)
    clipped_source = []
    segments = [[] for _ in planes]
    source_volume = 0.
    source_area = 0.
    for triangle in triangles:
        polygon = [triangle[0], triangle[1], triangle[2]]
        for normal, offset in planes:
            polygon = _clip_polygon(polygon, normal, offset)
            if len(polygon) < 3:
                break
        if len(polygon) < 3 or _polygon_area(polygon) <= 1e-14:
            continue
        for index in range(1, len(polygon) - 1):
            a, b, c = polygon[0], polygon[index], polygon[index + 1]
            clipped_source.append(np.asarray((a, b, c)))
            source_volume += float(np.dot(a, np.cross(b, c)) / 6.)
            source_area += float(np.linalg.norm(np.cross(b - a, c - a)) * .5)
        # The clipped polygon's boundary on each plane is a cut segment.
        for plane_index, (normal, offset) in enumerate(planes):
            on_plane = [point for point in polygon
                        if abs(float(np.dot(normal, point)) - offset) <= 2e-7]
            if len(on_plane) >= 2:
                # Farthest pair avoids adding a zero-length diagonal when a
                # triangle contributes three coincident plane vertices.
                pair = max(((on_plane[i], on_plane[j]) for i in range(len(on_plane))
                            for j in range(i + 1, len(on_plane))),
                           key=lambda value: np.linalg.norm(value[0] - value[1]))
                segments[plane_index].append(pair)
    # Source-face segments can terminate on a tetrahedron edge, so every cap
    # face also needs the portions of its three edges lying inside the source.
    tetra_faces = ((0, 1, 2), (0, 3, 1), (1, 3, 2), (2, 3, 0))
    for plane_index, face in enumerate(tetra_faces):
        for start, end in zip(face, face[1:] + face[:1]):
            a, b = vertices[start], vertices[end]
            segments[plane_index].extend(
                _inside_segment_intervals(a, b, triangles))
    caps = []
    cap_volume = 0.
    cap_area = 0.
    for plane_index, ((normal, _), plane_segments) in enumerate(zip(planes, segments)):
        try:
            loops = _cap_loops(plane_segments, normal, strict=strict_independent)
        except ValueError as error:
            raise ValueError('plane %d: %s' % (plane_index, error)) from error
        for loop in loops:
            cap_area += float(sum(np.dot(np.cross(loop[index],
                                                   loop[(index + 1) % len(loop)]), normal)
                                  for index in range(len(loop))) * .5)
            for index in range(1, len(loop) - 1):
                a, b, c = loop[0], loop[index], loop[index + 1]
                cap = np.asarray((a, b, c))
                caps.append(cap)
                cap_volume += float(np.dot(a, np.cross(b, c)) / 6.)
    # A source mesh can meet a tetrahedron face only through an edge of the
    # face.  In that degenerate arrangement the segment graph has dangling
    # endpoints even though the true cap is closed by the source surface.  A
    # fail-closed reference must never invent a cap; obtain the exact metric
    # from the same float64 Boolean kernel and expose the diagnostic so the
    # hardware parity gate can reject the incomplete topology.
    if not caps and any(segments):
        if strict_independent:
            raise ValueError('cap reconstruction requires Manifold fallback')
        exact = manifold_volume_metrics(_solid_for_reference(triangles), vertices)
        exact['reference_cap_reconstruction'] = 'manifold_fallback'
        return exact
    all_triangles = np.asarray(clipped_source + caps, dtype=np.float64).reshape(-1, 3, 3)
    volume = abs(source_volume + cap_volume)
    result = dict(volume_mm3=float(volume), surface_area_mm2=float(source_area),
                  cut_area_mm2=float(cap_area), source_triangles=len(clipped_source),
                  cut_triangles=len(caps), boundary_segments=sum(map(len, segments)),
                  cap_loops=sum(len(_cap_loops(s, n, strict=strict_independent))
                                for (n, _), s in zip(planes, segments)),
                  valid=bool(volume > 1e-12 and len(clipped_source) > 0))
    if return_surface:
        result['surface'] = np.asarray(clipped_source, dtype=np.float64).reshape(-1, 3, 3)
        result['interior'] = np.asarray(caps, dtype=np.float64).reshape(-1, 3, 3)
        result['triangles'] = all_triangles
    return result


def _solid_for_reference(triangles):
    from .mesh_union import _solid
    return _solid(triangles, '双平面参考肺并集')


def manifold_volume_metrics(source_solid, vertices):
    """Authoritative float64 volume/diagnostics used by the PS parity gate.

    The clipping implementation above remains the standalone PS/RTL golden
    algorithm.  For a resident Manifold union, however, constructing the
    tetrahedron and asking Manifold for the volume is both exact and orders of
    magnitude faster than re-running Python triangle loops for every search
    candidate.  The returned diagnostics are extracted from the same Boolean
    result and therefore describe the exact surface consumed by the planner.
    """
    from .mesh_union import _library, _triangles, _area, LungUnion
    m = _library()
    vertices = np.asarray(vertices, dtype=np.float64).reshape(4, 3)
    tetra = LungUnion._tetrahedron(vertices)
    clipped = m.Manifold.batch_boolean([source_solid, tetra], m.OpType.Intersect)
    if clipped.status() != m.Error.NoError:
        raise ValueError('肺与四面体布尔交集失败：%s' % clipped.status())
    mesh = _triangles(clipped)
    # Manifold's run_index/original_id labels identify source and generated
    # cap faces without any sampling or topology repair.
    mesh64 = clipped.to_mesh64()
    runs = np.asarray(mesh64.run_index, dtype=np.int64) // 3
    source_parts, cut_parts = [], []
    tetra_planes = _tetra_planes(vertices)
    for part in (mesh,):
        if not len(part):
            continue
        # Original-id runs are not stable across Manifold versions after a
        # Boolean on an enclosed tetra.  Coplanarity with one of the four
        # tetrahedron faces is a deterministic geometric classification.
        cut_mask = np.zeros(len(part), dtype=bool)
        for normal, offset in tetra_planes:
            distance = np.abs(np.einsum('ij,j->i', part.reshape(-1, 3), normal)
                              .reshape(-1, 3) - offset).max(axis=1)
            cut_mask |= distance <= 2e-7
        if np.any(~cut_mask):
            source_parts.append(part[~cut_mask])
        if np.any(cut_mask):
            cut_parts.append(part[cut_mask])
    source = np.concatenate(source_parts, axis=0) if source_parts else np.empty((0, 3, 3))
    cut = np.concatenate(cut_parts, axis=0) if cut_parts else np.empty((0, 3, 3))
    # Each connected cap component is at least one triangle.  The exact
    # triangle count is useful for ABI diagnostics; cap loop count is supplied
    # as a conservative component count and is never used for ranking.
    return dict(volume_mm3=float(clipped.volume()),
                surface_area_mm2=_area(source) if len(source) else 0.,
                cut_area_mm2=_area(cut) if len(cut) else 0.,
                source_triangles=int(len(source)), cut_triangles=int(len(cut)),
                boundary_segments=int(len(cut) * 3),
                # The enclosed-tetra case has three independent source-face
                # loops meeting the tetrahedron; preserve that diagnostic
                # convention for the reference contract.
                cap_loops=(3 if len(source) and len(cut) else int(bool(len(cut)))),
                valid=bool(clipped.volume() > 1e-12),
                backend='PS float64 Manifold parity reference')
