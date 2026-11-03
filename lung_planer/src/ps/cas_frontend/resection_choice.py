"""Choose lobectomy or wedge per lesion from its maximum diameter.

Lesions with a maximum diameter >= LOBECTOMY_MIN_DIAMETER_MM resect the whole
lobe that contains them; smaller lesions keep the dual-plane wedge planner.
This module only reads STL files and never changes wedge planning geometry.
"""
import re
from pathlib import Path

import numpy as np

from . import planner_reference as ref
from .lobe_focus import is_lobe
from .planning_inputs import is_lung_surface
from .mesh_cpu import CpuMeshIndex
from .mesh_triangle import _points_triangles_distance2
from .planning_cancel import checkpoint
from .ray_golden import inside_from_crossings

LOBECTOMY_MIN_DIAMETER_MM = 15.
# A lesion centre outside every lobe surface may only fall back to a lobe this close.
NEAREST_LOBE_TOLERANCE_MM = 10.
# Lesion vertices sampled for the lobectomy coverage/margin figures.
MAX_METRIC_POINTS = 4000
# Segment faces this close to a sibling segment are internal seams, not lobe surface.
SEAM_TOLERANCE_MM = .5
_PROBE_DIRECTION = np.asarray([1., .371390676, .127831]) / np.linalg.norm([1., .371390676, .127831])
LOBE_LABELS = dict(LU='左肺上叶', LL='左肺下叶', RU='右肺上叶', RM='右肺中叶', RL='右肺下叶')
_LOBE_WORDS = (
    (('left', 'upper'), 'LU'), (('left', 'lower'), 'LL'), (('right', 'upper'), 'RU'),
    (('right', 'middle'), 'RM'), (('right', 'lower'), 'RL'),
    (('左', '上'), 'LU'), (('左', '下'), 'LL'), (('右', '上'), 'RU'), (('右', '中'), 'RM'), (('右', '下'), 'RL'))
# Segment territories such as Bronchus_plan_0_seg_3RU.stl belong to lobe RU.
_SEGMENT = re.compile(r'seg_?\d+([lr][ulm])$')


def needs_lobectomy(diameter_mm):
    return bool(np.isfinite(diameter_mm)) and float(diameter_mm) >= LOBECTOMY_MIN_DIAMETER_MM


def lobe_key(name):
    """Lobe code (LU/LL/RU/RM/RL) of a lobe or segment STL, or '' for anything else."""
    stem = Path(name).stem.lower()
    if is_lobe(Path(name).name):
        return next((key for words, key in _LOBE_WORDS if all(word in stem for word in words)), '')
    match = _SEGMENT.search(stem)
    return match.group(1).upper() if match and is_lung_surface(name) else ''


def lobe_label(name):
    return LOBE_LABELS.get(lobe_key(name), Path(name).stem)


def lobe_groups(files):
    """{lobe code: {'lobe': [lobe STL], 'segments': [segment STLs]}} for every recognised lobe."""
    groups = {}
    for name in files:
        key = lobe_key(name)
        if key:
            groups.setdefault(key, dict(lobe=[], segments=[]))['lobe' if is_lobe(Path(name).name) else 'segments'].append(name)
    return groups


def component_diameter_mm(row, spacing_mm):
    """Maximum 3D diameter of one catalog row; STL units scaled by CT pixel size."""
    size = float(row.get('max_diameter_src', 0.))
    if spacing_mm is None or not np.isfinite(size) or size <= 0.:
        return 0.
    return round(size * float(spacing_mm), 1)


def _read_surface(path, spacing):
    triangles = ref.read_stl_array(Path(path)) * spacing
    # Signed tetrahedra; each lobe or segment STL is a closed surface.
    volume = abs(float(np.einsum('ij,ij->i', triangles[:, 0],
                                 np.cross(triangles[:, 1], triangles[:, 2])).sum()) / 6.)
    return dict(triangles=triangles, volume=volume, index=None,
                low=triangles.reshape(-1, 3).min(axis=0), high=triangles.reshape(-1, 3).max(axis=0))


def _contains(surface, point):
    if not (np.all(point >= surface['low']) and np.all(point <= surface['high'])):
        return False
    if surface['index'] is None:
        surface['index'] = CpuMeshIndex(surface['triangles'])
    return inside_from_crossings(surface['index'].hits(point + _PROBE_DIRECTION * 1e-5, _PROBE_DIRECTION))


def _surface_area(triangles):
    return float(np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0],
                                         triangles[:, 2] - triangles[:, 0]), axis=1).sum() / 2.)


def _chunk(triangle_count):
    """Points per batch so one point x triangle block stays near 8 MB per float64 array."""
    return max(1, min(512, 1_000_000 // max(1, triangle_count)))


def _ray_parity(points, triangles, direction):
    """Odd/even crossing count of one fixed ray per point against a closed surface.

    Triangles are first culled by their bounding box in the plane normal to
    the ray, so the exact Moller-Trumbore test only runs on real candidates.
    """
    axis_u = np.cross(direction, [0., 0., 1.])
    axis_u /= np.linalg.norm(axis_u)
    axis_v = np.cross(direction, axis_u)
    projected = np.stack((triangles @ axis_u, triangles @ axis_v), axis=-1)
    tri_low, tri_high = projected.min(axis=1), projected.max(axis=1)
    order = np.argsort(tri_low[:, 0])
    sorted_low = tri_low[order, 0]
    point_uv = np.stack((points @ axis_u, points @ axis_v), axis=-1)
    width = float((tri_high[:, 0] - tri_low[:, 0]).max()) if len(triangles) else 0.
    odd = np.zeros(len(points), dtype=bool)
    for begin in range(0, len(points), 64):
        checkpoint()
        uv = point_uv[begin:begin + 64]
        # Triangles whose u-range can contain any point of this batch.
        first = np.searchsorted(sorted_low, uv[:, 0].min() - width, 'left')
        last = np.searchsorted(sorted_low, uv[:, 0].max(), 'right')
        ids = order[first:last]
        if not len(ids):
            continue
        low, high = tri_low[ids], tri_high[ids]
        pi, ti = np.nonzero((low[None, :, 0] <= uv[:, None, 0]) & (high[None, :, 0] >= uv[:, None, 0])
                            & (low[None, :, 1] <= uv[:, None, 1]) & (high[None, :, 1] >= uv[:, None, 1]))
        if not len(pi):
            continue
        tri = triangles[ids[ti]]
        origin = points[begin + pi]
        a = tri[:, 0]
        e1, e2 = tri[:, 1] - a, tri[:, 2] - a
        h = np.cross(direction, e2)
        det = np.einsum('ij,ij->i', e1, h)
        usable = np.abs(det) >= 1e-12
        inv = np.divide(1., det, out=np.zeros_like(det), where=usable)
        offset = origin - a
        u = np.einsum('ij,ij->i', offset, h) * inv
        q = np.cross(offset, e1)
        v = (q @ direction) * inv
        t = np.einsum('ij,ij->i', e2, q) * inv
        hit = usable & (u >= 0.) & (v >= 0.) & (u + v <= 1.) & (t > 1e-9)
        odd[begin:begin + 64] = np.bincount(pi[hit], minlength=len(uv)) % 2 == 1
    return odd


def _distances(points, triangles):
    """Exact point-to-triangle-set distance for each point, in batches."""
    out = np.empty(len(points))
    step = _chunk(len(triangles))
    for begin in range(0, len(points), step):
        checkpoint()
        out[begin:begin + step] = np.sqrt(_points_triangles_distance2(
            points[begin:begin + step, None, :], triangles[None]).min(axis=1))
    return out


def _box_gap(low, high, tri_low, tri_high):
    """Distance from the box [low, high] to each face's bounding box (a lower bound)."""
    delta = np.maximum(np.maximum(tri_low - high, low - tri_high), 0.)
    return np.sqrt(np.einsum('ij,ij->i', delta, delta))


class _OuterSurface:
    """Lobe surface for margin queries; seam faces between its own segments are dropped lazily."""

    def __init__(self, triangles):
        self.parts = [np.asarray(t, dtype=np.float64) for t in triangles]
        self.low = [t.min(axis=1) for t in self.parts]
        self.high = [t.max(axis=1) for t in self.parts]
        # 1 outer, 0 seam, -1 not classified yet.
        self.state = [np.full(len(t), -1 if len(self.parts) > 1 else 1, dtype=np.int8) for t in self.parts]

    def _classify(self, k, ids):
        ids = ids[self.state[k][ids] < 0]
        if not len(ids):
            return
        centers = self.parts[k][ids].mean(axis=1)
        seam = np.zeros(len(ids), dtype=bool)
        # Sort by a projection so each batch of centres is spatially compact and
        # only meets the sibling faces right around it.
        order = np.argsort(centers @ (np.ptp(centers, axis=0) + 1e-9))
        for begin in range(0, len(order), 32):
            rows = order[begin:begin + 32]
            batch = centers[rows]
            low, high = batch.min(axis=0), batch.max(axis=0)
            for j, other in enumerate(self.parts):
                if j == k:
                    continue
                checkpoint()
                close = other[_box_gap(low, high, self.low[j], self.high[j]) <= SEAM_TOLERANCE_MM]
                if len(close):
                    seam[rows] |= _distances(batch, close) < SEAM_TOLERANCE_MM
        self.state[k][ids] = np.where(seam, 0, 1)

    def nearest(self, points, low, high, reach):
        """Distance from the points to the closest outer face within `reach`, or inf.

        Candidate faces are ranked by their exact distance and classified
        (outer or seam) lazily in that order, so far-away faces are never
        classified at all.
        """
        best = np.inf
        for k, part in enumerate(self.parts):
            ids = np.flatnonzero((_box_gap(low, high, self.low[k], self.high[k]) <= reach)
                                 & (self.state[k] != 0))
            if not len(ids):
                continue
            face_distance = _face_distances(points, part[ids])
            order = np.argsort(face_distance)
            for begin in range(0, len(order), 16):
                rows = order[begin:begin + 16]
                if face_distance[rows[0]] >= best:
                    break
                self._classify(k, ids[rows])
                outer = rows[self.state[k][ids[rows]] == 1]
                if len(outer):
                    best = min(best, float(face_distance[outer].min()))
                    break
        return best

    def span(self):
        points = np.concatenate([part.reshape(-1, 3) for part in self.parts])
        return float(np.linalg.norm(np.ptp(points, axis=0)))


def _face_distances(points, faces):
    """For each face, its exact distance to the nearest of the points."""
    out = np.full(len(faces), np.inf)
    step = _chunk(len(points))
    for begin in range(0, len(faces), step):
        checkpoint()
        out[begin:begin + step] = np.sqrt(_points_triangles_distance2(
            points[:, None, :], faces[None, begin:begin + step]).min(axis=0))
    return out


def _margin(points, surface):
    """Exact smallest distance from the points to the outer surface.

    A face closer than r to a point has a bounding-box gap below r, so each
    spatial cluster of points only needs the faces within the best margin found
    so far; a growing search around one probe point supplies that bound.
    """
    if len(points) > 1:
        points = points[np.argsort(points @ np.ptp(points, axis=0))]
    probe = points[len(points) // 2][None]
    radius, limit, best = 2., surface.span() + 1., np.inf
    while True:
        best = surface.nearest(probe, probe[0], probe[0], radius)
        if best <= radius or radius > limit:
            break
        radius *= 2.
    if not np.isfinite(best):
        return 0.
    for begin in range(0, len(points), 64):
        cluster = points[begin:begin + 64]
        best = min(best, surface.nearest(cluster, cluster.min(axis=0), cluster.max(axis=0), best))
    return best


def _lesion_metrics(points, lobe):
    """Wedge-style figures for a lesion resected with its whole lobe.

    Coverage is the share of lesion vertices inside the lobe; the margin is the
    smallest distance from a covered vertex to the lobe's outer surface (the
    resection boundary). A lobe built from segment STLs ignores the seams
    between its own segments, which lie inside the lobe. CT millimetres.
    All work is vectorized so this worker thread does not starve the GUI.
    """
    points = np.unique(np.asarray(points, dtype=np.float64).reshape(-1, 3), axis=0)
    if len(points) > MAX_METRIC_POINTS:
        points = points[np.linspace(0, len(points) - 1, MAX_METRIC_POINTS).astype(int)]
    if not len(points):
        return dict(coverage_percent=0., tumor_margin_mm=0.)
    triangles = [surface['triangles'] for surface in lobe['surfaces']]
    inside = np.zeros(len(points), dtype=bool)
    for surface in triangles:
        inside |= _ray_parity(points, surface, _PROBE_DIRECTION)
    if not inside.any():
        return dict(coverage_percent=0., tumor_margin_mm=0.)
    if '_outer_surface' not in lobe:
        lobe['_outer_surface'] = _OuterSurface(triangles)
    return dict(coverage_percent=float(inside.mean() * 100.),
                tumor_margin_mm=_margin(points[inside], lobe['_outer_surface']))


def locate_lobes(directory, files, lesions, spacing_mm):
    """Return lobe volumes and, per lesion, the lobe that contains its centre.

    A lobe is its lobe STL or, when the case only has segment STLs for it,
    the union of those segments. lesions: [{'id', 'center_src'}] in STL
    source units; the bounding-box centre is the probe, matching lobe_focus.
    """
    root = Path(directory)
    spacing = float(spacing_mm)
    lobes = {}
    for key, members in lobe_groups(files).items():
        checkpoint()
        # A lobe STL already encloses its segments; use segments only without one.
        names = members['lobe'] or members['segments']
        surfaces = [surface for surface in (_read_surface(root / name, spacing) for name in names)
                    if len(surface['triangles'])]
        if surfaces:
            lobes[key] = dict(label=LOBE_LABELS[key], files=names, surfaces=surfaces,
                              volume_cm3=sum(surface['volume'] for surface in surfaces) / 1000.,
                              surface_area_cm2=sum(_surface_area(surface['triangles'])
                                                   for surface in surfaces) / 100.)
    if not lobes:
        raise ValueError('未找到肺叶或肺段 STL（如 RightUpperLobe.stl、Bronchus_plan_0_seg_1RU.stl），无法规划肺叶切除')
    placements = {}
    for lesion in lesions:
        checkpoint()
        center = np.asarray(lesion['center_src'], dtype=np.float64) * spacing
        candidates = []
        for key, lobe in lobes.items():
            inside = any(_contains(surface, center) for surface in lobe['surfaces'])
            distance = 0. if inside else min(
                float(np.sqrt(np.min(_points_triangles_distance2(center, surface['triangles']))))
                for surface in lobe['surfaces'])
            candidates.append((not inside, distance, key))
        outside, distance, key = min(candidates)
        if outside and distance > NEAREST_LOBE_TOLERANCE_MM:
            raise ValueError(f'病灶 {lesion.get("index", "")} 中心不在任何肺叶内，最近的{LOBE_LABELS[key]}'
                             f'距 {distance:.1f} mm；请检查肺叶 STL 是否齐全')
        placements[lesion['id']] = dict(lobe=key, contains_center=not outside, distance_mm=distance)
        if lesion.get('points_src') is not None:
            placements[lesion['id']].update(_lesion_metrics(
                np.asarray(lesion['points_src'], dtype=np.float64) * spacing, lobes[key]))
    total = sum(lobe['volume_cm3'] for lobe in lobes.values())
    volumes = {key: dict(label=lobe['label'], files=lobe['files'], volume_cm3=lobe['volume_cm3'],
                         surface_area_cm2=lobe['surface_area_cm2'])
               for key, lobe in lobes.items()}
    return dict(lobes=volumes, total_lobe_volume_cm3=total, placements=placements)


def split_lesions(lesions, located):
    """Group lesions into lobectomies and the wedge lesions left to plan.

    A wedge-sized lesion inside a lobe that is already resected is covered by
    that lobectomy and is not planned again.
    """
    resected = {}
    for lesion in lesions:
        if needs_lobectomy(lesion['diameter_mm']):
            placement = located['placements'][lesion['id']]
            resected.setdefault(placement['lobe'], []).append(dict(lesion, **placement))
    wedge, covered = [], []
    for lesion in lesions:
        if needs_lobectomy(lesion['diameter_mm']):
            continue
        placement = located['placements'].get(lesion['id'])
        if placement and placement['lobe'] in resected:
            resected[placement['lobe']].append(dict(lesion, **placement))
            covered.append(lesion['id'])
        else:
            wedge.append(lesion['id'])
    total = located['total_lobe_volume_cm3']
    plans = []
    for key, members in resected.items():
        lobe = located['lobes'][key]
        plans.append(dict(
            lobe=key, files=list(lobe['files']), label=lobe['label'], volume_cm3=lobe['volume_cm3'],
            ratio_percent=(lobe['volume_cm3'] / total * 100. if total > 0. else 0.),
            total_volume_cm3=total, surface_area_cm2=lobe.get('surface_area_cm2'),
            lesions=[dict(id=m['id'], index=m['index'], diameter_mm=m['diameter_mm'],
                          volume_cm3=m['volume_cm3'], contains_center=m['contains_center'],
                          distance_mm=m['distance_mm'],
                          # The whole lobe is removed, so a lesion placed in it is covered; the
                          # vertex-parity figure (mesh noise at the pleura) stays as raw_coverage_percent.
                          coverage_percent=(100. if m.get('contains_center') else m.get('coverage_percent')),
                          raw_coverage_percent=m.get('coverage_percent'), tumor_margin_mm=m.get('tumor_margin_mm'),
                          reason=(f'≥{LOBECTOMY_MIN_DIAMETER_MM:g} mm，切除所在肺叶' if needs_lobectomy(m['diameter_mm'])
                                  else f'<{LOBECTOMY_MIN_DIAMETER_MM:g} mm，位于同一切除肺叶内'))
                     for m in sorted(members, key=lambda m: m['index'])]))
    plans.sort(key=lambda plan: min(item['index'] for item in plan['lesions']))
    return plans, wedge, covered
