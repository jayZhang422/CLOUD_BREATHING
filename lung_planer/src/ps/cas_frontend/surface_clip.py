"""Batched float64 form of the reference Sutherland-Hodgman surface clip."""
import numpy as np


def triangles_overlapping_bounds(source, bounds_min, bounds_max, tolerance=1e-8):
    """Keep a conservative superset of triangles intersecting an AABB."""
    source = np.asarray(source, dtype=np.float64).reshape(-1, 3, 3)
    bounds_min = np.asarray(bounds_min, dtype=np.float64).reshape(3)
    bounds_max = np.asarray(bounds_max, dtype=np.float64).reshape(3)
    source_min = source.min(axis=1)
    source_max = source.max(axis=1)
    return source[np.all(source_max >= bounds_min - tolerance, axis=1)
                  & np.all(source_min <= bounds_max + tolerance, axis=1)]


def clipped_surface(source, faces):
    source = np.asarray(source, dtype=np.float64)
    faces = tuple(faces)
    # Keep the existing conservative triangle rejection, including its epsilon.
    valid = np.ones(len(source), dtype=bool)
    for a, _, _, n in faces:
        d = np.einsum('nti,i->nt', source - a, n)
        valid &= np.any(d <= 1e-8, axis=1)
    polygons = source[valid].copy()
    lengths = np.full(len(polygons), 3, dtype=np.intp)
    for a, _, _, n in faces:
        if not len(polygons):
            break
        width = polygons.shape[1]
        rows = np.arange(len(polygons))[:, None]
        columns = np.arange(width)[None, :]
        active = columns < lengths[:, None]
        delta = polygons - a
        # Same operation order as ref.dot, without a BLAS/reduction reorder.
        distances = delta[..., 0] * n[0] + delta[..., 1] * n[1] + delta[..., 2] * n[2]
        previous = (columns - 1) % lengths[:, None]
        prev_d = distances[rows, previous]
        inside = (distances <= 1e-8) & active
        crossing = ((distances <= 1e-8) != (prev_d <= 1e-8)) & active
        counts = inside.astype(np.intp) + crossing
        ends = np.cumsum(counts, axis=1)
        new_lengths = ends[:, -1]
        # Allocate from actual emission counts, rather than assuming a maximum
        # convex-polygon size near the reference's tolerance boundary.
        result = np.zeros((len(polygons), max(1, int(new_lengths.max())), 3), dtype=np.float64)
        ri, ci = np.nonzero(crossing)
        prev = polygons[ri, previous[ri, ci]]
        cur = polygons[ri, ci]
        ratio = prev_d[ri, ci] / (prev_d[ri, ci] - distances[ri, ci])
        result[ri, ends[ri, ci] - inside[ri, ci] - 1] = prev + (cur - prev) * ratio[:, None]
        ri, ci = np.nonzero(inside)
        result[ri, ends[ri, ci] - 1] = polygons[ri, ci]
        keep = new_lengths >= 3  # The scalar reference stops these polygons here.
        polygons, lengths = result[keep], new_lengths[keep]
    if not len(polygons):
        return 0., np.empty((0, 3, 3), dtype=np.float32)
    fan = np.arange(1, polygons.shape[1] - 1)[None, :]
    ri, fi = np.nonzero(fan < lengths[:, None] - 1)
    j = fi + 1
    triangles = np.stack((polygons[ri, 0], polygons[ri, j], polygons[ri, j + 1]), axis=1)
    first = triangles[:, 1] - triangles[:, 0]
    second = triangles[:, 2] - triangles[:, 0]
    cross = np.cross(first, second)
    areas = np.sqrt(cross[:, 0] * cross[:, 0] + cross[:, 1] * cross[:, 1] + cross[:, 2] * cross[:, 2]) * .5
    # Preserve the reference's triangle order and sequential accumulation.
    area = float(np.add.accumulate(areas)[-1]) if len(areas) else 0.
    return area / 100., triangles.astype(np.float32)
