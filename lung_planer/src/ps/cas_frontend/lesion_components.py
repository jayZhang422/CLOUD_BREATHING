"""Deterministic, explicit STL component selection shared by UI and workers."""
import hashlib
from pathlib import Path

import numpy as np

from . import planner_reference as ref


def max_feret_diameter(points):
    """Largest distance between any two points: the lesion's 3D maximum diameter.

    Only convex-hull vertices can be an extreme pair, so the pairwise search
    runs on the hull. A flat or collinear set has no hull; every point is used
    then, and a set too large for that falls back to the bounding-box diagonal
    (an upper bound).
    """
    points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
    if len(points) < 2:
        return 0.
    try:
        from scipy.spatial import ConvexHull
        points = points[ConvexHull(points).vertices]
    except Exception:
        pass
    if len(points) > 20000:
        return float(np.linalg.norm(np.ptp(points, axis=0)))
    best = 0.
    for begin in range(0, len(points), 512):
        delta = points[begin:begin + 512, None, :] - points[None, :, :]
        best = max(best, float(np.sqrt(np.einsum('ijk,ijk->ij', delta, delta).max())))
    return best


def inspect_components(path):
    path = Path(path)
    source_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
    ranked = []
    for triangles in ref.connected_components(ref.read_stl(path)):
        volume = ref.closed_mesh_volume(triangles)
        if not np.isfinite(volume) or volume <= 1e-9:
            continue
        points = np.asarray(ref.all_points(triangles), dtype='<f8')
        # Fingerprint the complete component, not its rank or a rounded volume.
        identifier = hashlib.sha256(points.tobytes()).hexdigest()
        ranked.append(dict(id=identifier, volume_cm3=volume / 1000.,
            triangle_count=len(triangles), bounds_min_mm=points.min(axis=0).tolist(),
            bounds_max_mm=points.max(axis=0).tolist(),
            center_mm=((points.min(axis=0) + points.max(axis=0)) / 2.).tolist(),
            size_mm=np.ptp(points, axis=0).tolist(),
            # STL source units; the planner scales it by the CT voxel size.
            max_diameter_src=max_feret_diameter(points), triangles=triangles))
    ranked.sort(key=lambda row: (-row['volume_cm3'], row['id']))
    for rank, row in enumerate(ranked, 1):
        row['rank'] = rank
        row['label'] = f"连通块 {rank} · {row['volume_cm3']:.4f} cm³"
    return dict(source_sha256=source_sha256, components=ranked)


def selected_components(catalog, identifiers=None, count=1):
    rows = catalog['components']
    if identifiers is not None:
        identifiers = list(identifiers)
        if not identifiers or len(identifiers) != len(set(identifiers)):
            raise ValueError('请选择至少一个病灶，且不能重复选择')
        known = {r['id'] for r in rows}
        if any(identifier not in known for identifier in identifiers):
            raise ValueError('病灶模型已变化，请重新检查并选择连通块')
        requested = set(identifiers)
        return [row for row in rows if row['id'] in requested]
    count = int(count)
    if not 1 <= count <= len(rows):
        raise ValueError(f'请求规划 {count} 个病灶，但 STL 中只识别到 {len(rows)} 个连通病灶')
    return rows[:count]
