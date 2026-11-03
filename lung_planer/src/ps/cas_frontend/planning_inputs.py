"""Filename roles used consistently by the planner and its check tools."""
from pathlib import Path
import re

import numpy as np

from . import planner_reference as ref
from .mesh_triangle import closest_point_on_mesh
from .mesh_cpu import CpuMeshIndex
from .planning_cancel import checkpoint
from .ray_golden import HIT_TOLERANCE_MM, inside_from_crossings


def is_lesion(name):
    name = Path(name).name.lower()
    return any(word in name for word in ('tumor', '病灶', '肿瘤', '囊肿'))


def is_lung_surface(name):
    name = Path(name).name.lower()
    return (not is_lesion(name)
            and (any(word in name for word in ('lobe', 'lung', '肺')) or 'bronchus_plan' in name)
            and not any(word in name for word in ('artery', 'venous', 'vessel', '血管')))


def anatomical_lung_side(name):
    """Return an explicit left/right lung label when the STL name has one."""
    stem = Path(name).stem.lower()
    left = 'left' in stem or re.search(r'\d+l[ul]', stem)
    right = 'right' in stem or re.search(r'\d+r[uml]', stem)
    if bool(left) == bool(right):
        return None
    return 'left' if left else 'right'


_BOX_MARGIN_MM = 1e-3
_RAY_CHUNK = 512


def _inside_many(index, origins, direction):
    """Parity inside test for many rays sharing one direction.

    Same BVH pruning, Moller-Trumbore tests and crossing merge as
    ``index.hits`` + ``inside_from_crossings``, but each BVH level and each
    leaf batch is one numpy call for the whole chunk of rays instead of one
    per ray.
    """
    origins = np.asarray(origins, dtype=np.float64)
    direction = np.asarray(direction, dtype=np.float64)
    children, leaf, members, width = index.display_contact_arrays()
    moving = np.abs(direction) > 1e-14
    inv_dir = np.divide(1., direction, out=np.zeros(3), where=moving)
    inside = np.zeros(len(origins), dtype=bool)
    for start in range(0, len(origins), _RAY_CHUNK):
        checkpoint()
        chunk = origins[start:start + _RAY_CHUNK]
        ray = np.arange(len(chunk))
        node = np.zeros(len(chunk), dtype=np.int64)
        leaf_ray, leaf_node = [], []
        while len(ray):
            low, high = index.low[node] - 1e-7, index.high[node] + 1e-7
            origin = chunk[ray]
            valid = np.all(moving | ((origin >= low) & (origin <= high)), axis=1)
            first, second = (low - origin) * inv_dir, (high - origin) * inv_dir
            near = np.where(moving, np.minimum(first, second), -np.inf).max(axis=1)
            far = np.where(moving, np.maximum(first, second), np.inf).min(axis=1)
            keep = valid & (far >= np.maximum(near, 0.))
            ray, node = ray[keep], node[keep]
            is_leaf = leaf[node]
            leaf_ray.append(ray[is_leaf])
            leaf_node.append(node[is_leaf])
            inner_ray, inner_node = ray[~is_leaf], node[~is_leaf]
            ray = np.repeat(inner_ray, 2)
            node = children[inner_node].reshape(-1).astype(np.int64)
        pair_ray = np.concatenate(leaf_ray)
        pair_node = np.concatenate(leaf_node)
        if not len(pair_ray):
            continue
        tri_ray = np.repeat(pair_ray, width)
        tri_id = members[pair_node].reshape(-1)
        real = tri_id >= 0
        tri_ray, tri_id = tri_ray[real], tri_id[real]
        triangles = index.triangles[tri_id]
        a = triangles[:, 0]
        e1, e2 = triangles[:, 1] - a, triangles[:, 2] - a
        h = np.cross(direction, e2)
        det = np.einsum('ij,ij->i', e1, h)
        inv = np.divide(1., det, out=np.zeros_like(det), where=np.abs(det) >= 1e-9)
        offset = chunk[tri_ray] - a
        u = inv * np.einsum('ij,ij->i', offset, h)
        q = np.cross(offset, e1)
        v = inv * np.einsum('ij,j->i', q, direction)
        t = inv * np.einsum('ij,ij->i', e2, q)
        hit = ((np.abs(det) >= 1e-9) & (u >= -1e-7) & (u <= 1.0000001)
               & (v >= -1e-7) & (u + v <= 1.0000001) & (t >= 0.))
        hit_ray, hit_t = tri_ray[hit], t[hit]
        if not np.isfinite(hit_t).all():
            raise ValueError('nonfinite crossing')
        order = np.lexsort((hit_t, hit_ray))
        hit_ray, hit_t = hit_ray[order], hit_t[order]
        # collapse_crossings per ray: keep a hit unless it is within the
        # tolerance of the previous hit on the same ray.
        keep = np.ones(len(hit_t), dtype=bool)
        keep[1:] = (hit_ray[1:] != hit_ray[:-1]) | (np.diff(hit_t) > HIT_TOLERANCE_MM)
        counts = np.bincount(hit_ray[keep], minlength=len(chunk))
        inside[start:start + len(chunk)] = counts % 2 == 1
    return inside


def auto_select_target_lung(directory, lung_files, tumor_file, *,
                            tumor_triangles=None, tumor_component_ids=None,
                            ct_spacing=None):
    """Choose the smallest lesion-boundary STL set that covers the lesion.

    A lobe STL may contain a more specific segment STL.  Selecting every
    enclosing surface would make a planning Boolean use the larger outer
    surface and add an unnecessary margin.  Prefer the smallest enclosing
    surface; retain multiple partial surfaces only when the lesion samples
    span them, which preserves the existing multi-STL behavior.
    """
    files = list(lung_files)
    if len(files) <= 1:
        return files
    root = Path(directory)
    spacing = np.asarray(ct_spacing if ct_spacing is not None else (1., 1., 1.), dtype=np.float64)
    try:
        if tumor_component_ids:
            # The tumour STL can contain several disconnected lesions.  The
            # old path always used the largest component, which selected the
            # wrong lung when the user chose component 2 or later.
            from .lesion_components import inspect_components
            catalog = inspect_components(root / tumor_file)
            wanted = set(tumor_component_ids)
            rows = [row for row in catalog['components'] if row['id'] in wanted]
            if not rows:
                return files
            point_sets = [np.asarray(ref.all_points(row['triangles']), dtype=np.float64)
                          for row in rows]
        else:
            tumor = (list(tumor_triangles) if tumor_triangles is not None else
                     ref.largest_component(ref.read_stl(root / tumor_file)))
            point_sets = [np.asarray(ref.all_points(tumor), dtype=np.float64)]
        points = np.concatenate(point_sets, axis=0) * spacing
        if points.size == 0 or spacing.shape != (3,) or not np.isfinite(spacing).all():
            return files
        centers = [part.mean(axis=0) * spacing for part in point_sets
                   if part.size]
        # A bounded deterministic sample catches a lesion crossing a lobe
        # seam without making automatic selection scale with every STL face.
        if len(points) > 2048:
            sample_indices = np.linspace(0, len(points) - 1, 2048,
                                         dtype=np.int64)
            sample_indices = np.unique(np.r_[sample_indices,
                np.argmin(points, axis=0), np.argmax(points, axis=0)])
            probe_points = points[sample_indices]
        else:
            probe_points = points
        probe_direction = np.asarray(ref.unit((1.0, .371, .217)))
        containing, distances, masks, names = [], [], [], []
        for name in files:
            checkpoint()
            triangles = ref.read_stl(root / name)
            mesh = np.asarray([tri.points for tri in triangles], dtype=np.float64) * spacing
            if not len(mesh):
                continue
            distances.append((min(float(np.linalg.norm(closest_point_on_mesh(point, mesh)[0] - point))
                                  for point in centers), name))
            # A closed surface cannot contain a point outside its bounding box,
            # so only the points inside the box need the expensive ray cast.
            low = mesh.reshape(-1, 3).min(axis=0) - _BOX_MARGIN_MM
            high = mesh.reshape(-1, 3).max(axis=0) + _BOX_MARGIN_MM
            in_box = np.all((probe_points >= low) & (probe_points <= high), axis=1)
            inside = np.zeros(len(probe_points), dtype=bool)
            if in_box.any():
                index = CpuMeshIndex(mesh)
                inside[in_box] = _inside_many(
                    index, probe_points[in_box] + probe_direction * 1e-5, probe_direction)
            if np.any(inside):
                masks.append(inside)
                names.append(name)
                if np.all(inside):
                    containing.append((float(np.prod(np.ptp(mesh.reshape(-1, 3), axis=0))), name))
        if masks:
            # If several partial surfaces together cover the lesion, it is a
            # genuine multi-STL lesion.  Nested full containers are excluded
            # from this union so an outer lobe does not defeat a segment STL.
            full_names = {name for _, name in containing}
            partial = [(name, mask) for name, mask in zip(names, masks)
                       if name not in full_names]
            if partial:
                covered = np.logical_or.reduce([mask for _, mask in partial])
                if np.all(covered):
                    return sorted(name for name, _ in partial)
            if containing:
                return [min(containing, key=lambda row: (row[0], row[1]))[1]]
            return sorted(names)
        if distances:
            nearest, name = min(distances)
            if nearest <= 2.0 * max(float(np.linalg.norm(np.ptp(points, axis=0))), 1.0):
                return [name]
    except (OSError, ValueError, TypeError):
        return files
    return files
