"""Display-only lobe selection in STL coordinates; never filters planning input."""
from time import perf_counter

import numpy as np

from .planning_inputs import is_lesion
from .mesh_cpu import CpuMeshIndex
from .mesh_triangle import _points_triangles_distance2
from .ray_golden import inside_from_crossings
from . import planner_reference as ref


def is_lobe(name):
    text = name.lower()
    return not is_lesion(name) and ('lobe' in text or ('肺' in text and '叶' in text))


def lobe_side(name):
    text = name.lower()
    if 'left' in text or '左' in text:
        return 'left'
    if 'right' in text or '右' in text:
        return 'right'
    return ''


# STL source units (about 0.7 mm per unit here): how close a lesion centre outside
# every lobe may be and still be attributed to the nearest lobe.
NEAREST_LOBE_TOLERANCE = 15.


def find_lobe_focus(surfaces):
    """Name the lobe that holds each primary lesion, for the status line only.

    A lobe is its lobe STL or, without one, the union of its segment STLs
    (e.g. Bronchus_plan_0_seg_3RU.stl). The largest closed component per
    lesion STL matches the default planner's primary-component convention.
    A lesion centre outside every lobe is attributed to the nearest lobe only
    within NEAREST_LOBE_TOLERANCE; otherwise it is reported as not located.
    """
    from .resection_choice import LOBE_LABELS, lobe_key

    started = perf_counter()
    groups = {}
    for name, vertices in surfaces:
        key = lobe_key(name)
        if key:
            members = groups.setdefault(key, dict(lobe=[], segments=[]))
            members['lobe' if is_lobe(name) else 'segments'].append((name, np.asarray(vertices, dtype=np.float64)))
    lobes = {key: members['lobe'] or members['segments'] for key, members in groups.items()}
    lesions = []
    for name, vertices in surfaces:
        if not is_lesion(name):
            continue
        triangles = [ref.Triangle(*map(tuple, t)) for t in vertices]
        components = ref.connected_components(triangles)
        if not components:
            continue
        component = max(components, key=ref.closed_mesh_volume)
        points = np.asarray(ref.all_points(component), dtype=np.float64)
        lesions.append((name, (points.min(axis=0) + points.max(axis=0)) / 2))
    result = dict(selected=[], selected_lobes=[], lobes=[name for parts in lobes.values() for name, _ in parts],
                  lesions=[], unlocated=[],
                  method='primary lesion bbox center; containing lobe (or its segments) first, '
                         f'nearest surface within {NEAREST_LOBE_TOLERANCE:g} source units; all lobes on that side')
    if lobes and lesions:
        direction = np.asarray([1., .371390676, .127831])
        direction /= np.linalg.norm(direction)
        indexes = {key: [(name, mesh, CpuMeshIndex(mesh)) for name, mesh in parts] for key, parts in lobes.items()}
        for name, center in lesions:
            candidates = []
            for key, parts in indexes.items():
                inside = any(bool(inside_from_crossings(index.hits(center + direction * 1e-5, direction)))
                             for _, _, index in parts)
                distance = 0. if inside else min(float(np.sqrt(np.min(_points_triangles_distance2(center, mesh))))
                                                 for _, mesh, _ in parts)
                candidates.append(dict(lobe=key, label=LOBE_LABELS[key], contains_center=inside, distance=distance))
            nearest = min(candidates, key=lambda c: (not c['contains_center'], c['distance'], c['lobe']))
            entry = dict(file=name, center_mm=center.tolist(), candidates=candidates)
            if not nearest['contains_center'] and nearest['distance'] > NEAREST_LOBE_TOLERANCE:
                result['unlocated'].append(name)
                result['lesions'].append(dict(entry, selected=''))
                continue
            side = nearest['lobe'][0]
            same_side = [key for key in lobes if key[0] == side]
            for key in same_side:
                for part, _ in lobes[key]:
                    if part not in result['selected']:
                        result['selected'].append(part)
            if nearest['label'] not in result['selected_lobes']:
                result['selected_lobes'].append(nearest['label'])
            result['lesions'].append(dict(entry, selected=nearest['lobe'], selected_label=nearest['label'],
                                          side='left' if side == 'L' else 'right'))
    result['elapsed_ms'] = (perf_counter() - started) * 1000
    return result
