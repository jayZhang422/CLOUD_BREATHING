"""CPU centerline forests and exact polyline/tetrahedron clipping, in STL mm.

An even-odd scanline rasterizes the supplied surface (the VTK stencil is the
fallback); Lee thinning preserves its voxel topology.
Generation means graph depth from an explicitly recorded root, not an anatomical
name. Disconnected components remain disconnected. Cyclic graphs are flagged.
"""
from collections import deque
from hashlib import sha256
import json
import math
from pathlib import Path
from time import perf_counter
import os
import tempfile

import numpy as np

REVISION = 'centerlines-lee-smooth-gap-v11'
KINDS = {'artery': '动脉', 'vein': '静脉', 'airway': '支气管'}


def structure_kind(name):
    name = Path(name).stem.lower()
    # Bronchus_plan files in this application are lung segment surfaces.
    if 'plan' in name or '肺段' in name:
        return None
    if any(s in name for s in ('venous', 'vein', '静脉')):
        return 'vein'
    if any(s in name for s in ('artery', 'arterial', '动脉')):
        return 'artery'
    if any(s in name for s in ('bronch', 'airway', 'trachea', '支气管', '气管')):
        return 'airway'
    return None


def _check(cancelled):
    if cancelled():
        raise RuntimeError('中心线分析已取消')


def _phase(timings, name, started):
    now = perf_counter()
    if timings is not None:
        timings[name] = (now - started) * 1000.
    return now


def _add_phase(timings, name, started):
    now = perf_counter()
    if timings is not None:
        timings[name] = timings.get(name, 0.) + (now - started) * 1000.
    return now


def _smooth_path_in_mask(path, radii, mask, spacing):
    """Dampen voxel stair-steps without moving endpoints or leaving the lumen mask."""
    path = np.asarray(path, dtype=np.float64)
    if len(path) < 6:
        return path
    from scipy.ndimage import gaussian_filter1d
    spacing = np.broadcast_to(np.asarray(spacing, dtype=np.float64), (3,))
    physical = path * spacing
    filtered = gaussian_filter1d(physical, sigma=1.1, axis=0, mode='nearest') / spacing
    taper = np.minimum(1., np.minimum(np.arange(len(path)), np.arange(len(path))[::-1]) / 2.)
    delta = (filtered - path) * taper[:, None]
    radii = np.asarray(radii, dtype=np.float64)
    displacement = np.linalg.norm(delta * spacing, axis=1)
    limit = .45 * np.maximum(radii, 0.)
    delta *= np.minimum(1., limit / np.maximum(displacement, 1e-12))[:, None]

    # Back off the whole path together so one constrained voxel cannot create a new kink.
    for strength in (1., .75, .5, .25, 0.):
        candidate = path + strength * delta
        indices = np.rint(candidate).astype(np.int64)
        inside = np.ones(len(indices), dtype=bool)
        for axis, size in enumerate(mask.shape):
            inside &= (indices[:, axis] >= 0) & (indices[:, axis] < size)
        valid = np.flatnonzero(inside)
        if len(valid) == len(indices):
            inside[:] = mask[tuple(indices.T)]
        elif len(valid):
            inside[valid] = mask[tuple(indices[valid].T)]
        if inside.all():
            return candidate
    return path


def _endpoint_inward_tangent(points, from_start, window_mm):
    """Estimate endpoint direction across a bounded physical arc-length window."""
    points = np.asarray(points, dtype=np.float64)
    if not from_start:
        points = points[::-1]
    if len(points) < 2:
        return np.zeros(3, dtype=np.float64)
    lengths = np.linalg.norm(np.diff(points, axis=0), axis=1)
    cumulative = np.concatenate(([0.], np.cumsum(lengths)))
    target = min(float(window_mm), float(cumulative[-1]))
    segment = min(int(np.searchsorted(cumulative, target, side='right') - 1),
                  len(lengths) - 1)
    fraction = (target - cumulative[segment]) / max(float(lengths[segment]), 1e-12)
    sample = points[segment] + fraction * (points[segment + 1] - points[segment])
    tangent = sample - points[0]
    norm = float(np.linalg.norm(tangent))
    return tangent / norm if norm > 1e-9 else np.zeros(3, dtype=np.float64)


def _mask_bridge_support(start, end, mask, origin, spacing, direction):
    if mask is None or origin is None:
        return 0.
    spacing = np.broadcast_to(np.asarray(spacing, dtype=np.float64), (3,))
    step = float(np.min(spacing))
    count = max(3, int(np.linalg.norm(end - start) / step * 4.) + 1)
    samples = np.linspace(start, end, count)
    axes = np.eye(3) if direction is None else np.asarray(direction, dtype=np.float64)
    indices = np.rint(((samples - np.asarray(origin)) @ axes) / spacing).astype(np.int64)
    valid = np.ones(len(indices), dtype=bool)
    for axis, size in enumerate(mask.shape):
        valid &= (indices[:, axis] >= 0) & (indices[:, axis] < size)
    inside = np.zeros(len(indices), dtype=bool)
    inside[valid] = mask[tuple(indices[valid].T)]
    return float(inside.mean())


def _connect_short_endpoint_gaps(nodes, branches, spacing, mask=None, origin=None,
                                 direction=None, timings=None):
    """Join unique, facing endpoints only when the source mask supports their bridge."""
    spacing = np.broadcast_to(np.asarray(spacing, dtype=np.float64), (3,))
    step = float(np.min(spacing))
    adjacency = [[] for _ in nodes]
    endpoint_data = {}
    for branch in branches:
        start, end = branch['start'], branch['end']
        adjacency[start].append(end); adjacency[end].append(start)
        points = np.asarray(branch['points'], dtype=np.float64)
        radii = np.asarray(branch['radii_mm'], dtype=np.float64)
        if len(points) < 2:
            continue
        for node, at_start, radius in ((start, True, radii[0]),
                                       (end, False, radii[-1])):
            window = max(2. * step, min(3.2, 3. * max(float(radius), step)))
            tangent = _endpoint_inward_tangent(points, at_start, window)
            if np.linalg.norm(tangent) > 1e-9:
                endpoint_data[node] = (tangent, float(radius))

    component = [-1] * len(nodes)
    component_id = 0
    for initial in range(len(nodes)):
        if component[initial] >= 0 or not adjacency[initial]:
            continue
        component[initial] = component_id
        queue = [initial]
        while queue:
            node = queue.pop()
            for other in adjacency[node]:
                if component[other] < 0:
                    component[other] = component_id
                    queue.append(other)
        component_id += 1

    endpoints = [node for node, neighbors in enumerate(adjacency)
                 if len(neighbors) == 1 and node in endpoint_data]
    candidates = {node: [] for node in endpoints}
    grid_direction = None if direction is None else np.asarray(direction, dtype=np.float64)
    possible_pairs = len(endpoints) * (len(endpoints) - 1) // 2

    if len(endpoints) > 1:
        from scipy.spatial import cKDTree
        endpoint_points = np.asarray([nodes[node]['point'] for node in endpoints], dtype=np.float64)
        max_radius = max(endpoint_data[node][1] for node in endpoints)
        search_radius = min(12. * step, max(4. * step, 7. * max(max_radius, step)))
        search_radius += max(1e-12, step * 1e-9)
        nearby_pairs = sorted(cKDTree(endpoint_points).query_pairs(search_radius))
    else:
        nearby_pairs = []
    if timings is not None:
        timings.update(gap_repair_endpoint_count=len(endpoints),
                       gap_repair_possible_pair_count=possible_pairs,
                       gap_repair_candidate_pair_count=len(nearby_pairs))

    for first_index, second_index in nearby_pairs:
        first, second = endpoints[first_index], endpoints[second_index]
        if component[first] == component[second]:
            continue
        p = np.asarray(nodes[first]['point'], dtype=np.float64)
        q = np.asarray(nodes[second]['point'], dtype=np.float64)
        gap = q - p
        distance = float(np.linalg.norm(gap))
        if distance <= 1e-9:
            continue
        inward_a, radius_a = endpoint_data[first]
        inward_b, radius_b = endpoint_data[second]
        direction = gap / distance
        facing_a = float(-inward_a @ direction)
        facing_b = float(inward_b @ direction)
        opposition = float(-inward_a @ inward_b)
        radius_delta = abs(radius_a - radius_b)
        local_radius = max(radius_a, radius_b, step)
        max_gap = min(12. * step, max(4. * step, 7. * local_radius))
        if (distance > max_gap or min(facing_a, facing_b, opposition) < .85
                or radius_delta > max(.5, .6 * local_radius)):
            continue
        support = _mask_bridge_support(p, q, mask, origin, spacing, grid_direction)
        if support < .55:
            continue
        score = distance + step * (2. - facing_a - facing_b) + step * (1. - support)
        candidates[first].append((score, second, radius_a, radius_b, support))
        candidates[second].append((score, first, radius_b, radius_a, support))

    best = {}
    for node, options in candidates.items():
        options.sort(key=lambda item: (item[0], item[1]))
        if (options and (len(options) == 1
                or options[1][0] - options[0][0] >= .35 * step)):
            best[node] = options[0]

    repaired = 0
    paired = set()
    for first in sorted(best):
        _, second, radius_a, radius_b, support = best[first]
        if (first in paired or second in paired or second not in best
                or best[second][1] != first):
            continue
        p = nodes[first]['point']; q = nodes[second]['point']
        length = float(np.linalg.norm(np.asarray(q) - np.asarray(p)))
        branches.append(dict(id=len(branches), start=first, end=second,
            points=[p, q], radii_mm=[radius_a, radius_b], length_mm=length,
            diameter_mm=2. * float(np.median([radius_a, radius_b])), gap_bridge=True,
            gap_bridge_method='mutual-directed-mask-support-v2',
            mask_support_fraction=support))
        paired.update((first, second))
        repaired += 1
    return repaired


def _connect_short_endpoints_to_branches(nodes, branches, spacing, mask=None,
                                         origin=None, direction=None):
    """Attach a credible fragment tip to the main tree's interior, splitting its path."""
    spacing = np.broadcast_to(np.asarray(spacing, dtype=np.float64), (3,))
    step = float(np.min(spacing))
    adjacency = [[] for _ in nodes]
    for branch_index, branch in enumerate(branches):
        adjacency[branch['start']].append(branch_index)
        adjacency[branch['end']].append(branch_index)

    components = [-1] * len(nodes)
    branch_component = [-1] * len(branches)
    component_lengths = []
    for initial in range(len(nodes)):
        if components[initial] >= 0 or not adjacency[initial]:
            continue
        component_id = len(component_lengths)
        components[initial] = component_id
        queue = [initial]
        found_branches = set()
        while queue:
            node = queue.pop()
            for branch_index in adjacency[node]:
                branch_component[branch_index] = component_id
                found_branches.add(branch_index)
                branch = branches[branch_index]
                other = branch['end'] if branch['start'] == node else branch['start']
                if components[other] < 0:
                    components[other] = component_id
                    queue.append(other)
        component_lengths.append(sum(float(branches[i]['length_mm']) for i in found_branches))
    if not component_lengths:
        return 0
    main_component = int(np.argmax(component_lengths))

    target_segments = []
    for branch_index, branch in enumerate(branches):
        if branch_component[branch_index] != main_component or branch.get('gap_bridge'):
            continue
        points = np.asarray(branch['points'], dtype=np.float64)
        radii = np.asarray(branch['radii_mm'], dtype=np.float64)
        segment_lengths = np.linalg.norm(np.diff(points, axis=0), axis=1)
        cumulative = np.concatenate(([0.], np.cumsum(segment_lengths)))
        for segment_index, length in enumerate(segment_lengths):
            if length <= 1e-9:
                continue
            target_segments.append((branch_index, segment_index, points[segment_index],
                points[segment_index + 1], float(radii[segment_index]),
                float(radii[segment_index + 1]), cumulative[segment_index], length))
    if not target_segments:
        return 0

    from scipy.spatial import cKDTree
    midpoints = np.asarray([(item[2] + item[3]) * .5 for item in target_segments])
    half_lengths = np.asarray([item[7] * .5 for item in target_segments])
    target_tree = cKDTree(midpoints)
    max_half_length = float(half_lengths.max())
    endpoints = []
    for node, incident in enumerate(adjacency):
        if len(incident) != 1 or components[node] == main_component:
            continue
        branch_index = incident[0]
        branch = branches[branch_index]
        at_start = branch['start'] == node
        radius = float(branch['radii_mm'][0 if at_start else -1])
        window = max(2. * step, min(3.2, 3. * max(radius, step)))
        tangent = _endpoint_inward_tangent(branch['points'], at_start, window)
        if np.linalg.norm(tangent) > 1e-9:
            endpoints.append((node, components[node], tangent, radius))

    choices_by_component = {}
    for node, component_id, inward, radius in endpoints:
        point = np.asarray(nodes[node]['point'], dtype=np.float64)
        # A slightly wider capture window recovers short breaks when the mask
        # supports the bridge; tangent and radius checks still reject crossings.
        max_gap = min(8. * step, max(4. * step, 8. * max(radius, step)))
        options = []
        for target_index in target_tree.query_ball_point(point, max_gap + max_half_length):
            (branch_index, segment_index, first, second, radius_a, radius_b,
             segment_start, segment_length) = target_segments[target_index]
            segment = second - first
            fraction = float(np.clip((point - first) @ segment /
                                     max(segment_length * segment_length, 1e-12), 0., 1.))
            target_point = first + fraction * segment
            target_radius = radius_a + fraction * (radius_b - radius_a)
            target_arc = segment_start + fraction * segment_length
            target_branch = branches[branch_index]
            target_total = float(target_branch['length_mm'])
            target_node = None
            if target_arc <= .25 * step:
                target_node = target_branch['start']
                target_point = np.asarray(nodes[target_node]['point'], dtype=np.float64)
                target_radius = float(nodes[target_node]['radius_mm'])
                target_arc = 0.
            elif target_total - target_arc <= .25 * step:
                target_node = target_branch['end']
                target_point = np.asarray(nodes[target_node]['point'], dtype=np.float64)
                target_radius = float(nodes[target_node]['radius_mm'])
                target_arc = target_total

            gap = target_point - point
            distance = float(np.linalg.norm(gap))
            if distance <= 1e-9 or distance > max_gap:
                continue
            bridge_direction = gap / distance
            facing = float(-inward @ bridge_direction)
            local_radius = max(radius, target_radius, step)
            if (facing < .85 or abs(radius - target_radius) > max(.5, .7 * local_radius)):
                continue
            support = _mask_bridge_support(point, target_point, mask, origin, spacing, direction)
            if support < .55:
                continue
            score = distance + step * (1. - facing) + step * (1. - support)
            options.append(dict(score=score, node=node, component=component_id,
                point=point, radius=radius, target_branch=branch_index,
                target_arc=target_arc, target_node=target_node,
                target_point=target_point, target_radius=target_radius,
                distance=distance, support=support))

        options.sort(key=lambda item: (item['score'], item['target_branch'], item['target_arc']))
        distinct = []
        for option in options:
            if any(np.linalg.norm(option['target_point'] - previous['target_point']) < .5 * step
                   for previous in distinct):
                continue
            distinct.append(option)
        if distinct and (len(distinct) == 1
                or distinct[1]['score'] - distinct[0]['score'] >= .35 * step):
            choices_by_component.setdefault(component_id, []).append(distinct[0])

    choices = []
    for options in choices_by_component.values():
        options.sort(key=lambda item: (item['score'], item['node']))
        if (len(options) == 1
                or options[1]['score'] - options[0]['score'] >= .35 * step):
            choices.append(options[0])
    choices.sort(key=lambda item: (item['score'], item['target_branch'], item['target_arc']))
    selected = []
    for option in choices:
        separation = max(2. * step, option['target_radius'])
        if any(np.linalg.norm(option['target_point'] - other['target_point'])
               < max(separation, other['target_radius']) for other in selected):
            continue
        selected.append(option)
    if not selected:
        return 0

    splits = {}
    for option in selected:
        if option['target_node'] is None:
            node = len(nodes)
            nodes.append(dict(id=node, point=option['target_point'].tolist(),
                              radius_mm=float(option['target_radius'])))
            option['target_node'] = node
            splits.setdefault(option['target_branch'], []).append(
                (option['target_arc'], node, option['target_point'], option['target_radius']))

    rewritten = []
    for branch_index, branch in enumerate(branches):
        branch_splits = sorted(splits.get(branch_index, []), key=lambda item: item[0])
        if not branch_splits:
            rewritten.append(branch)
            continue
        points = np.asarray(branch['points'], dtype=np.float64)
        radii = np.asarray(branch['radii_mm'], dtype=np.float64)
        segment_lengths = np.linalg.norm(np.diff(points, axis=0), axis=1)
        cumulative = np.concatenate(([0.], np.cumsum(segment_lengths)))

        boundaries = [(0., branch['start'], points[0], float(radii[0]))]
        boundaries.extend(branch_splits)
        boundaries.append((float(cumulative[-1]), branch['end'], points[-1], float(radii[-1])))
        for left, right in zip(boundaries, boundaries[1:]):
            start_distance, start_node, start_point, start_radius = left
            end_distance, end_node, end_point, end_radius = right
            interior = np.flatnonzero((cumulative[1:-1] > start_distance + 1e-9)
                                      & (cumulative[1:-1] < end_distance - 1e-9)) + 1
            piece_points = np.vstack((start_point, points[interior], end_point))
            piece_radii = [start_radius, *radii[interior].tolist(), end_radius]
            length = float(end_distance - start_distance)
            if length <= 1e-9:
                continue
            piece = dict(branch)
            piece.update(start=start_node, end=end_node, points=piece_points.tolist(),
                         radii_mm=piece_radii, length_mm=length,
                         diameter_mm=2. * float(np.median(piece_radii)))
            rewritten.append(piece)
    branches[:] = rewritten
    for branch_index, branch in enumerate(branches):
        branch['id'] = branch_index

    for option in selected:
        length = float(np.linalg.norm(option['target_point'] - option['point']))
        branches.append(dict(id=len(branches), start=option['node'], end=option['target_node'],
            points=[option['point'].tolist(), option['target_point'].tolist()],
            radii_mm=[option['radius'], option['target_radius']], length_mm=length,
            diameter_mm=2. * float(np.median([option['radius'], option['target_radius']])),
            gap_bridge=True, gap_bridge_method='directed-mask-supported-tree-attachment-v2',
            mask_support_fraction=option['support']))
    return len(selected)


def _preserve_smoothed_roots(tree, path, spacing, cache_directory):
    """Migrate confirmed roots when only bounded smoothing/gap repair changed geometry."""
    path = Path(path)
    if path.suffix.lower() != '.stl':
        return
    target = Path(cache_directory) / (tree['cache_key'] + '.roots.json')
    if target.exists():
        return
    old_key = sha256(f'centerlines-lee-v2|{tree["source_sha256"]}|{float(spacing):.9g}'.encode()).hexdigest()
    for folder in (Path(cache_directory), Path(__file__).resolve().parents[1] / 'data/centerlines'):
        try:
            roots = json.loads((folder / (old_key + '.roots.json')).read_text(encoding='utf-8'))
            old = json.loads((folder / (old_key + '.json')).read_text(encoding='utf-8'))
            if (old.get('source_sha256') != tree['source_sha256']
                    or len(old['nodes']) != len(tree['nodes'])
                    or len(old['branches']) > len(tree['branches'])):
                continue
            if not np.allclose([n['point'] for n in old['nodes']],
                               [n['point'] for n in tree['nodes']], rtol=0, atol=1e-10):
                continue
            paths_match = True
            for before, after in zip(old['branches'], tree['branches']):
                if {before['start'], before['end']} != {after['start'], after['end']}:
                    paths_match = False
                    break
                points, smoothed = np.asarray(before['points']), np.asarray(after['points'])
                if points.shape != smoothed.shape:
                    paths_match = False
                    break
                limit = .46 * max(float(before['radii_mm'][0]),
                                  float(before['radii_mm'][-1]), 1.)
                if (np.max(np.linalg.norm(points - smoothed, axis=1)) > limit
                        and np.max(np.linalg.norm(points - smoothed[::-1], axis=1)) > limit):
                    paths_match = False
                    break
            if (not paths_match or not all(isinstance(root, int)
                    and 0 <= root < len(tree['nodes']) for root in roots['roots'])):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('x', encoding='utf-8') as out:
                json.dump(dict(roots=roots['roots'], migrated_from=old_key,
                               source_sha256=tree['source_sha256']), out)
            return
        except (OSError, ValueError, KeyError, TypeError, IndexError):
            continue


def _vtk():
    """Only the VTK modules voxelize uses; `import vtk` loads every module (~3.8 s on the board)."""
    from types import SimpleNamespace
    from vtkmodules.vtkCommonCore import VTK_UNSIGNED_CHAR
    from vtkmodules.vtkCommonDataModel import vtkImageData
    from vtkmodules.vtkFiltersCore import vtkFeatureEdges
    from vtkmodules.vtkImagingStencil import vtkImageStencil, vtkPolyDataToImageStencil
    from vtkmodules.vtkIOGeometry import vtkSTLReader
    return SimpleNamespace(VTK_UNSIGNED_CHAR=VTK_UNSIGNED_CHAR, vtkImageData=vtkImageData,
                           vtkFeatureEdges=vtkFeatureEdges, vtkImageStencil=vtkImageStencil,
                           vtkPolyDataToImageStencil=vtkPolyDataToImageStencil,
                           vtkSTLReader=vtkSTLReader)


def preload():
    """Import the extraction modules ahead of the first click; safe to call repeatedly."""
    _vtk()
    from vtkmodules.util.numpy_support import vtk_to_numpy  # noqa: F401
    from scipy.ndimage import distance_transform_edt, gaussian_filter1d  # noqa: F401
    from scipy.spatial import cKDTree  # noqa: F401
    from .lee import _load_native
    _load_native()


def voxelize(path, spacing, max_voxels=48_000_000, *, timings=None, stencil_workers=1):
    started = perf_counter()
    vtk = _vtk()
    from vtkmodules.util.numpy_support import vtk_to_numpy
    reader = vtk.vtkSTLReader()
    reader.SetFileName(str(Path(path).resolve()))
    reader.Update()
    read_finished = perf_counter()
    poly = reader.GetOutput()
    if not poly.GetNumberOfCells():
        raise ValueError('STL 为空或无法读取')
    check_started = perf_counter()
    bounds = np.asarray(poly.GetBounds()).reshape(3, 2)
    if not np.isfinite(bounds).all() or np.any(bounds[:, 1] <= bounds[:, 0]):
        raise ValueError('STL 坐标无效或不是三维管状结构')
    edges = vtk.vtkFeatureEdges()
    edges.SetInputData(poly)
    edges.BoundaryEdgesOn(); edges.NonManifoldEdgesOn()
    edges.FeatureEdgesOff(); edges.ManifoldEdgesOff()
    edges.Update()
    if edges.GetOutput().GetNumberOfCells():
        raise ValueError('管道 STL 存在开放边或非流形边，请先提供封闭管腔模型；未自动补洞')
    check_finished = perf_counter()
    if timings is not None:
        timings.update(stl_read_ms=(read_finished - started) * 1000.,
                       stl_mesh_check_ms=(check_finished - check_started) * 1000.,
                       stl_read_check_ms=(check_finished - started) * 1000.)
    voxelize_started = check_finished
    started = check_finished
    spacing = float(spacing)
    if not math.isfinite(spacing) or not .1 <= spacing <= 5:
        raise ValueError('体素间距必须在 0.1–5 mm')
    span = bounds[:, 1] - bounds[:, 0]
    shape = np.ceil(span / spacing).astype(int) + 5
    while math.prod(map(int, shape)) > max_voxels:
        spacing *= 1.08
        shape = np.ceil(span / spacing).astype(int) + 5
    origin = bounds[:, 0] - spacing * 2
    shape = tuple(map(int, shape))
    if int(stencil_workers) < 1:
        raise ValueError('VTK stencil worker 数必须至少为 1')
    started = perf_counter()
    mask = None
    surface = _triangle_arrays(poly, vtk_to_numpy)
    if surface is not None:
        mask = _scanline_mask(*surface, origin, spacing, shape)
    if timings is not None:
        timings['scanline_ms'] = (perf_counter() - started) * 1000.
        timings['voxelize_method'] = 'scanline' if mask is not None else 'vtk-stencil'
    if mask is None:
        mask = _stencil_mask(vtk, vtk_to_numpy, poly, origin, spacing, shape,
                             stencil_workers, timings)
    _phase(timings, 'voxelize_ms', voxelize_started)
    if timings is not None:
        timings.update(shape_xyz=list(mask.shape), mask_bytes=mask.nbytes,
                       occupied_voxels=int(np.count_nonzero(mask)), spacing_mm=spacing)
    return mask, origin, spacing, poly.GetNumberOfCells()


def _triangle_arrays(poly, vtk_to_numpy):
    """Float64 points and (T, 3) vertex ids, or None when any cell is not a triangle."""
    polys = poly.GetPolys()
    if polys.GetNumberOfCells() != poly.GetNumberOfCells():
        return None
    offsets = vtk_to_numpy(polys.GetOffsetsArray())
    if len(offsets) < 2 or np.any(np.diff(offsets) != 3):
        return None
    points = vtk_to_numpy(poly.GetPoints().GetData()).astype(np.float64)
    triangles = vtk_to_numpy(polys.GetConnectivityArray()).astype(np.int64).reshape(-1, 3)
    return points, triangles


def _edge_side(value, dx, dy):
    # Side of the edge for the query point nudged by (+eps, +eps^2): an exact
    # zero takes the edge direction's sign, so a ray through a shared edge or
    # vertex is counted by exactly one of the triangles around it.
    return np.where(value != 0, np.sign(value), np.sign(np.where(dy != 0, -dy, dx)))


def _scanline_mask(points, triangles, origin, spacing, shape):
    """Voxel centres inside the closed surface, by even-odd crossings along +z.

    Each (x, y) voxel column is one ray. Shared edges are evaluated from one
    canonical endpoint order, so adjacent triangles agree bit-for-bit and a
    closed surface is crossed an even number of times. Returns None if any
    column is odd, leaving that surface to the VTK stencil.
    """
    nx, ny, nz = shape
    p = (points - origin) / spacing  # index space: voxel centre i sits at i
    tri = p[triangles]
    lo = np.ceil(tri[:, :, :2].min(axis=1)).astype(np.int64)
    hi = np.floor(tri[:, :, :2].max(axis=1)).astype(np.int64)
    count_x = np.maximum(hi[:, 0] - lo[:, 0] + 1, 0)
    counts = count_x * np.maximum(hi[:, 1] - lo[:, 1] + 1, 0)
    hit = counts > 0
    owner = np.repeat(np.flatnonzero(hit), counts[hit])
    if not len(owner):
        return np.zeros(shape, dtype=bool)
    local = np.arange(len(owner)) - np.repeat(np.cumsum(counts[hit]) - counts[hit], counts[hit])
    qx = lo[owner, 0] + local % count_x[owner]
    qy = lo[owner, 1] + local // count_x[owner]

    sides, weights = [], []
    for k in range(3):  # edge k runs from vertex k to vertex k + 1
        a, b = triangles[owner, k], triangles[owner, (k + 1) % 3]
        flip = a > b
        first, second = np.where(flip, b, a), np.where(flip, a, b)
        dx, dy = p[second, 0] - p[first, 0], p[second, 1] - p[first, 1]
        value = dx * (qy - p[first, 1]) - dy * (qx - p[first, 0])
        side = _edge_side(value, dx, dy)
        sides.append(np.where(flip, -side, side))
        weights.append(np.abs(value))
    total = weights[0] + weights[1] + weights[2]
    inside = (sides[0] == sides[1]) & (sides[1] == sides[2]) & (total > 0)
    owner, qx, qy = owner[inside], qx[inside], qy[inside]
    w = [weight[inside] / total[inside] for weight in weights]
    # Edge k's weight is the barycentric weight of the vertex opposite it.
    z = w[0] * tri[owner, 2, 2] + w[1] * tri[owner, 0, 2] + w[2] * tri[owner, 1, 2]

    column = qx * ny + qy
    order = np.lexsort((z, column))
    column, z = column[order], z[order]
    breaks = np.flatnonzero(np.diff(column)) + 1
    if np.any(np.diff(np.concatenate(([0], breaks, [len(column)]))) % 2):
        return None
    first = np.clip(np.ceil(z[0::2]).astype(np.int64), 0, nz)
    last = np.clip(np.ceil(z[1::2]).astype(np.int64), 0, nz)
    lengths = np.maximum(last - first, 0)
    run_starts = np.cumsum(lengths) - lengths
    offsets = np.arange(int(lengths.sum())) - np.repeat(run_starts, lengths)
    mask = np.zeros(nx * ny * nz, dtype=bool)
    mask[np.repeat(column[0::2] * nz + first, lengths) + offsets] = True
    return mask.reshape(shape)


def _stencil_mask(vtk, vtk_to_numpy, poly, origin, spacing, shape, stencil_workers, timings):
    started = perf_counter()
    image = vtk.vtkImageData()
    image.SetOrigin(*origin); image.SetSpacing(spacing, spacing, spacing)
    image.SetDimensions(*map(int, shape))
    image.AllocateScalars(vtk.VTK_UNSIGNED_CHAR, 1)
    vtk_to_numpy(image.GetPointData().GetScalars())[:] = 1
    if timings is not None:
        timings['image_allocate_initialize_ms'] = (perf_counter() - started) * 1000.
    worker_count = int(stencil_workers)
    if worker_count < 1:
        raise ValueError('VTK stencil worker 数必须至少为 1')
    worker_count = min(worker_count, os.cpu_count() or 1, int(shape[2]))
    if timings is not None:
        timings['voxelize_workers'] = worker_count

    full_extent = tuple(image.GetExtent())
    if worker_count == 1:
        started = perf_counter()
        stencil = vtk.vtkPolyDataToImageStencil()
        stencil.SetInputData(poly); stencil.SetOutputOrigin(*origin)
        stencil.SetOutputSpacing(spacing, spacing, spacing)
        stencil.SetOutputWholeExtent(full_extent); stencil.Update()
        if timings is not None:
            timings['polydata_stencil_ms'] = (perf_counter() - started) * 1000.
        started = perf_counter()
        apply = vtk.vtkImageStencil()
        apply.SetInputData(image); apply.SetStencilConnection(stencil.GetOutputPort())
        apply.SetBackgroundValue(0); apply.Update()
        if timings is not None:
            timings['image_stencil_apply_ms'] = (perf_counter() - started) * 1000.
        started = perf_counter()
        mask = vtk_to_numpy(apply.GetOutput().GetPointData().GetScalars()).reshape(
            tuple(shape[::-1])).transpose(2, 1, 0).astype(bool)
    else:
        from concurrent.futures import ThreadPoolExecutor

        bounds_z = np.linspace(0, int(shape[2]), worker_count + 1, dtype=int)
        extents = [(0, int(shape[0]) - 1, 0, int(shape[1]) - 1,
                    int(bounds_z[i]), int(bounds_z[i + 1]) - 1)
                   for i in range(worker_count)]

        def build_stencil(extent):
            stencil = vtk.vtkPolyDataToImageStencil()
            stencil.SetInputData(poly); stencil.SetOutputOrigin(*origin)
            stencil.SetOutputSpacing(spacing, spacing, spacing)
            stencil.SetOutputWholeExtent(full_extent)
            started = perf_counter()
            if not stencil.UpdateExtent(extent):
                raise RuntimeError('VTK 分片 stencil 更新失败')
            return extent, stencil, (perf_counter() - started) * 1000.

        def apply_stencil(item):
            extent, stencil, _ = item
            apply = vtk.vtkImageStencil()
            apply.SetInputData(image); apply.SetStencilData(stencil.GetOutput())
            apply.SetBackgroundValue(0)
            started = perf_counter()
            if not apply.UpdateExtent(extent):
                raise RuntimeError('VTK 分片图像 stencil 更新失败')
            elapsed_ms = (perf_counter() - started) * 1000.
            output = apply.GetOutput()
            output_extent = tuple(output.GetExtent())
            x_size = output_extent[1] - output_extent[0] + 1
            y_size = output_extent[3] - output_extent[2] + 1
            z_size = output_extent[5] - output_extent[4] + 1
            slab = vtk_to_numpy(output.GetPointData().GetScalars()).reshape(
                (z_size, y_size, x_size)).transpose(2, 1, 0).astype(bool)
            return extent, slab, elapsed_ms, output_extent

        with ThreadPoolExecutor(max_workers=worker_count) as pool:
            started = perf_counter()
            stencils = list(pool.map(build_stencil, extents))
            stencil_wall_ms = (perf_counter() - started) * 1000.
            started = perf_counter()
            slabs = list(pool.map(apply_stencil, stencils))
            apply_wall_ms = (perf_counter() - started) * 1000.

        started = perf_counter()
        mask = np.empty(tuple(map(int, shape)), dtype=bool)
        for extent, slab, _, output_extent in slabs:
            x0, x1, y0, y1, z0, z1 = extent
            if output_extent != extent or slab.shape != (x1 - x0 + 1, y1 - y0 + 1, z1 - z0 + 1):
                raise RuntimeError('VTK 分片输出 extent 与请求不一致')
            mask[x0:x1 + 1, y0:y1 + 1, z0:z1 + 1] = slab
        if timings is not None:
            timings.update(polydata_stencil_ms=stencil_wall_ms,
                           image_stencil_apply_ms=apply_wall_ms,
                           polydata_stencil_worker_sum_ms=sum(item[2] for item in stencils),
                           image_stencil_apply_worker_sum_ms=sum(item[2] for item in slabs),
                           parallel_stencil_wall_ms=stencil_wall_ms + apply_wall_ms)
    _add_phase(timings, 'mask_export_cast_ms', started)
    return mask


def _build_adjacency(coords, shape, cancelled, backend):
    offsets = [(x, y, z) for x in (-1, 0, 1) for y in (-1, 0, 1)
               for z in (-1, 0, 1) if x or y or z]
    adjacency = [set() for _ in coords]
    if backend == 'python':
        lookup = {tuple(point): index for index, point in enumerate(coords)}
        for i, point in enumerate(coords):
            if i % 4096 == 0:
                _check(cancelled)
            for offset in offsets:
                other = lookup.get(tuple(point + offset))
                if other is None or other <= i:
                    continue
                steps = np.flatnonzero(offset)
                if len(steps) > 1 and any(
                        tuple(point + np.eye(3, dtype=int)[axis] * offset[axis]) in lookup
                        for axis in steps):
                    continue
                adjacency[i].add(other)
                adjacency[other].add(i)
        return adjacency, sum(map(len, adjacency)) // 2
    if backend != 'vectorized':
        raise ValueError('邻接后端必须为 python 或 vectorized')

    dimensions = np.asarray(shape, dtype=np.int64)
    strides = np.asarray((shape[1] * shape[2], shape[2], 1), dtype=np.int64)
    keys = coords @ strides
    if len(keys) > 1 and np.any(keys[1:] <= keys[:-1]):
        raise ValueError('骨架坐标必须按 C 顺序唯一排列')
    edge_chunks = []
    for offset in offsets:
        _check(cancelled)
        delta = np.asarray(offset, dtype=np.int64)
        valid = np.all((coords + delta >= 0) & (coords + delta < dimensions), axis=1)
        indices = np.flatnonzero(valid)
        if not len(indices):
            continue
        target_keys = keys[indices] + int(delta @ strides)
        neighbors = np.searchsorted(keys, target_keys)
        in_range = neighbors < len(keys)
        exists = np.zeros(len(indices), dtype=bool)
        exists[in_range] = keys[neighbors[in_range]] == target_keys[in_range]
        keep = exists & (neighbors > indices)
        steps = np.flatnonzero(delta)
        if len(steps) > 1 and np.any(keep):
            shortcut = np.zeros(len(indices), dtype=bool)
            for axis in steps:
                middle_keys = keys[indices] + int(delta[axis] * strides[axis])
                middle = np.searchsorted(keys, middle_keys)
                middle_in_range = middle < len(keys)
                connected = np.zeros(len(indices), dtype=bool)
                connected[middle_in_range] = keys[middle[middle_in_range]] == middle_keys[middle_in_range]
                shortcut |= connected
            keep &= ~shortcut
        if np.any(keep):
            edge_chunks.append(np.column_stack((indices[keep], neighbors[keep])))
    if edge_chunks:
        for first, second in np.concatenate(edge_chunks, axis=0):
            adjacency[first].add(int(second))
            adjacency[second].add(int(first))
    return adjacency, sum(map(len, adjacency)) // 2


def graph_from_mask(mask, origin, spacing, cancelled=lambda: False, *, timings=None,
                    distance_queries=None, direction=None, adjacency_backend='python'):
    """Contract connected junction voxels, retaining maximal degree-two paths."""
    from scipy.ndimage import distance_transform_edt
    from .lee import skeletonize_lee
    _check(cancelled)
    started = perf_counter()
    distance = None
    if distance_queries is None:
        distance = distance_transform_edt(mask, sampling=spacing)
        started = _phase(timings, 'edt_ms', started)
    skeleton = skeletonize_lee(mask, timings=timings)
    started = _phase(timings, 'lee_ms', started)
    _check(cancelled)
    coords = np.argwhere(skeleton)
    if not len(coords):
        raise ValueError('未提取到中心线；请减小体素间距或检查管腔模型')
    started = _phase(timings, 'skeleton_coordinates_ms', started)
    queried_radii = None
    if distance_queries is not None:
        queried_radii = np.asarray(distance_queries(coords), dtype=np.float64)
        if (queried_radii.shape != (len(coords),) or not np.isfinite(queried_radii).all()
                or np.any(queried_radii <= 0)):
            raise ValueError('骨架距离查询结果无效；没有 CPU 回退')
        started = _phase(timings, 'distance_queries_ms', started)
    adj, edge_count = _build_adjacency(coords, mask.shape, cancelled, adjacency_backend)
    started = _phase(timings, 'adjacency_ms', started)
    if timings is not None:
        timings['adjacency_edges'] = edge_count
    radii = distance[tuple(coords.T)] if queried_radii is None else queried_radii
    positions = coords * spacing
    if direction is not None:
        positions = positions @ np.asarray(direction).T
    positions = np.asarray(origin) + positions
    del distance, skeleton
    node_started = perf_counter()
    node_for, nodes = {}, []
    for i, neighbors in enumerate(adj):
        if i in node_for or len(neighbors) == 2:
            continue
        group, queue = [], [i]
        node_index = len(nodes)
        node_for[i] = node_index
        while queue:
            v = queue.pop(); group.append(v)
            if len(adj[v]) >= 3:
                for j in sorted(adj[v]):
                    if len(adj[j]) >= 3 and j not in node_for:
                        node_for[j] = node_index; queue.append(j)
        nodes.append(dict(id=node_index, point=positions[group].mean(axis=0).tolist(),
                          radius_mm=float(np.max(radii[group]))))
    _phase(timings, 'node_contraction_ms', node_started)
    # A closed degree-two loop has no endpoint; insert an explicit node and
    # retain it as an ungraded cycle instead of inventing a rooted tree.
    cycle_started = perf_counter()
    seen_components = set()
    for i in range(len(adj)):
        if i in seen_components:
            continue
        component, queue = [], [i]; seen_components.add(i)
        while queue:
            v = queue.pop(); component.append(v)
            for j in adj[v]:
                if j not in seen_components:
                    seen_components.add(j); queue.append(j)
        if not any(v in node_for for v in component):
            v = min(component); node_for[v] = len(nodes)
            nodes.append(dict(id=len(nodes), point=positions[v].tolist(), radius_mm=float(radii[v])))
    _phase(timings, 'cycle_detection_ms', cycle_started)
    visited, branches = set(), []
    path_started = perf_counter()
    path_tracing_ms = 0.
    smoothing_ms = 0.
    geometry_ms = 0.
    for start in sorted(node_for):
        for nxt in sorted(adj[start]):
            edge = tuple(sorted((start, nxt)))
            if edge in visited or node_for.get(nxt) == node_for[start]:
                continue
            visited.add(edge)
            path = [start, nxt]; prev, cur = start, nxt
            trace_started = perf_counter()
            while cur not in node_for:
                candidates = adj[cur] - {prev}
                if len(candidates) != 1:
                    raise ValueError('中心线图连接异常')
                new = next(iter(candidates)); visited.add(tuple(sorted((cur, new))))
                path.append(new); prev, cur = cur, new
            path_tracing_ms += (perf_counter() - trace_started) * 1000.
            smooth_started = perf_counter()
            smooth_path = _smooth_path_in_mask(coords[path], radii[path], mask, spacing)
            smoothing_ms += (perf_counter() - smooth_started) * 1000.
            geometry_started = perf_counter()
            points = positions[path].copy()
            delta = (smooth_path - coords[path]) * spacing
            if direction is not None:
                delta = delta @ np.asarray(direction).T
            points += delta
            points[0] = nodes[node_for[start]]['point']
            points[-1] = nodes[node_for[cur]]['point']
            length = float(np.linalg.norm(np.diff(points, axis=0), axis=1).sum())
            if length <= 1e-9:
                continue
            branches.append(dict(id=len(branches), start=node_for[start], end=node_for[cur],
                points=points.tolist(), radii_mm=radii[path].tolist(), length_mm=length,
                diameter_mm=float(2 * np.median(radii[path]))))
            geometry_ms += (perf_counter() - geometry_started) * 1000.
    _phase(timings, 'path_smoothing_and_geometry_ms', path_started)
    if timings is not None:
        timings['path_tracing_ms'] = path_tracing_ms
        timings['smoothing_ms'] = smoothing_ms
        timings['branch_geometry_ms'] = geometry_ms
    if not branches:
        raise ValueError('中心线过短，未形成可分析分支；请减小体素间距')
    repair_started = perf_counter()
    repaired_gaps = _connect_short_endpoint_gaps(
        nodes, branches, spacing, mask, origin, direction, timings=timings)
    _phase(timings, 'gap_repair_endpoint_pairs_ms', repair_started)
    repair_started = perf_counter()
    repaired_gaps += _connect_short_endpoints_to_branches(
        nodes, branches, spacing, mask, origin, direction)
    _phase(timings, 'gap_repair_endpoint_branch_ms', repair_started)
    _phase(timings, 'junctions_paths_ms', started)
    if timings is not None:
        timings.update(skeleton_voxels=len(coords), branch_count=len(branches),
                       repaired_gaps=repaired_gaps)
    return dict(nodes=nodes, branches=branches, skeleton_voxels=len(coords),
                geometry_smoothing='mask-constrained-gaussian-v1',
                repaired_gap_count=repaired_gaps)


def validate_tree(tree):
    """Reject incomplete/corrupt cache geometry before it enters the planner."""
    nodes, branches = tree['nodes'], tree['branches']
    if not nodes or not branches:
        raise ValueError('empty cached graph')
    for i, node in enumerate(nodes):
        if (node['id'] != i or np.asarray(node['point']).shape != (3,)
                or not np.isfinite(node['point']).all()
                or not np.isfinite(node['radius_mm']) or node['radius_mm'] < 0):
            raise ValueError('invalid cached node')
    for i, b in enumerate(branches):
        points, radii = np.asarray(b['points']), np.asarray(b['radii_mm'])
        if (b['id'] != i or not 0 <= b['start'] < len(nodes) or not 0 <= b['end'] < len(nodes)
                or points.shape != (len(radii), 3) or len(points) < 2
                or not np.isfinite(points).all() or not np.isfinite(radii).all()
                or np.any(radii < 0) or not np.isfinite(b['diameter_mm']) or b['diameter_mm'] < 0
                or not np.isfinite(b['length_mm']) or b['length_mm'] <= 0):
            raise ValueError('invalid cached branch')
        length = np.linalg.norm(np.diff(points, axis=0), axis=1).sum()
        if not np.isclose(length, b['length_mm'], rtol=1e-8, atol=1e-8):
            raise ValueError('cached length disagrees with polyline')


def grade_forest(tree, roots=None):
    """BFS generations; cyclic components provisional, non-tree edges ungraded."""
    nodes, branches = tree['nodes'], tree['branches']
    adj = [[] for _ in nodes]
    for b in branches:
        adj[b['start']].append((b['end'], b['id']))
        adj[b['end']].append((b['start'], b['id']))
        b.update(generation=0, parent=None, children=[], root=None, provisional=False)
    seen, root_list, cyclic = set(), [], 0
    requested = set(roots or [])
    for initial in range(len(nodes)):
        if initial in seen or not adj[initial]:
            continue
        component, edges, queue = set([initial]), set(), [initial]
        seen.add(initial)
        while queue:
            v = queue.pop()
            for other, edge in adj[v]:
                edges.add(edge)
                if other not in seen:
                    seen.add(other); component.add(other); queue.append(other)
        endpoints = [v for v in component if len(adj[v]) == 1]
        chosen = sorted(requested & component)
        root = chosen[0] if chosen else max(endpoints or sorted(component),
            key=lambda v: (nodes[v]['radius_mm'], -v))
        root_list.append(root)
        has_cycle = len(edges) != len(component) - 1
        if has_cycle:
            cyclic += 1
        for edge in edges:
            branches[edge].update(component=len(root_list), root=root, provisional=has_cycle)
        queue = deque([(root, None, 0)])
        done = {root}
        while queue:
            v, parent_branch, depth = queue.popleft()
            for other, edge in sorted(adj[v]):
                if other in done:
                    continue
                done.add(other)
                b = branches[edge]
                if b['start'] != v:
                    b['start'], b['end'] = b['end'], b['start']
                    b['points'].reverse(); b['radii_mm'].reverse()
                b.update(generation=depth + 1, parent=parent_branch,
                         component=len(root_list), root=root)
                if parent_branch is not None:
                    branches[parent_branch]['children'].append(edge)
                queue.append((other, edge, depth + 1))
    tree.update(roots=root_list, component_count=len(root_list), cyclic_components=cyclic)
    return tree


def extract_cached(path, cache_directory, spacing=.8, cancelled=lambda: False, progress=lambda s: None,
                   *, timings=None):
    path = Path(path)
    started = perf_counter()
    source_digest = sha256(path.read_bytes()).hexdigest()
    key = sha256(f'{REVISION}|{source_digest}|{float(spacing):.9g}'.encode()).hexdigest()
    cache = Path(cache_directory) / (key + '.json')
    phase_started = _phase(timings, 'source_hash_ms', started)
    _check(cancelled)
    try:
        tree = json.loads(cache.read_text(encoding='utf-8'))
        if tree['cache_key'] != key or tree['revision'] != REVISION:
            raise ValueError('cache version')
        validate_tree(tree)
        phase_started = _phase(timings, 'cache_read_validate_ms', phase_started)
        grade_forest(tree)
        _phase(timings, 'grading_ms', phase_started)
        _preserve_smoothed_roots(tree, path, spacing, cache_directory)
        tree.update(cache_hit=True, elapsed_ms=(perf_counter() - started) * 1000.)
        return tree
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        pass
    _phase(timings, 'cache_lookup_ms', phase_started)
    progress('表面体素化')
    options = {} if timings is None else dict(timings=timings)
    mask, origin, actual_spacing, triangles = voxelize(path, spacing, **options)
    _check(cancelled)
    progress(f'中心线细化 · {actual_spacing:.2f} mm · {mask.size / 1e6:.1f}M 体素')
    tree = graph_from_mask(mask, origin, actual_spacing, cancelled, **options)
    phase_started = perf_counter()
    grade_forest(tree)
    phase_started = _phase(timings, 'grading_ms', phase_started)
    tree.update(revision=REVISION, source_sha256=source_digest, cache_key=key,
                requested_spacing_mm=float(spacing), spacing_mm=actual_spacing,
                source_triangles=triangles, occupied_voxels=int(mask.sum()),
                coordinate_space='source_stl',
                cache_hit=False, elapsed_ms=(perf_counter() - started) * 1000.)
    _preserve_smoothed_roots(tree, path, spacing, cache_directory)
    _check(cancelled)
    cache.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=cache.parent,
                                          suffix='.tmp', delete=False) as out:
            temporary = out.name
            # json.dump streams through the pure-Python encoder; dumps uses the C one (same bytes).
            out.write(json.dumps(tree, ensure_ascii=False, separators=(',', ':'), allow_nan=False))
        os.replace(temporary, cache)
    except OSError as exc:
        tree['cache_warning'] = str(exc)
    finally:
        if temporary and Path(temporary).exists():
            Path(temporary).unlink()
    _phase(timings, 'metadata_cache_write_ms', phase_started)
    return tree


def clip_segments(segments, vertices, expansion=0.):
    """Clip closed segments to the four halfspaces, including outside/outside crossings."""
    from .planner_reference import tetra_faces, tetrahedron_volume
    vertices = np.asarray(vertices, dtype=float)
    if vertices.shape != (4, 3) or not np.isfinite(vertices).all():
        raise ValueError('四面体顶点无效')
    if tetrahedron_volume(list(map(tuple, vertices[:3])), tuple(vertices[3])) < 1e-6:
        raise ValueError('四面体退化')
    segments = np.asarray(segments, dtype=float).reshape(-1, 2, 3)
    faces = tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3]))
    a, normals = np.asarray([f[0] for f in faces]), np.asarray([f[3] for f in faces])
    start = (segments[:, 0, None] - a) * normals
    distances = start.sum(axis=2) - np.broadcast_to(np.asarray(expansion), (len(segments),))[:, None]
    delta = (segments[:, 1] - segments[:, 0]) @ normals.T
    low, high, valid = np.zeros(len(segments)), np.ones(len(segments)), np.ones(len(segments), bool)
    for face in range(4):
        d, v = distances[:, face], delta[:, face]
        parallel = np.abs(v) < 1e-12
        valid &= ~(parallel & (d > 1e-8))
        t = -d / np.where(parallel, 1., v)
        low = np.where(v < -1e-12, np.maximum(low, t), low)
        high = np.where(v > 1e-12, np.minimum(high, t), high)
    valid &= high - low > 1e-9
    low, high = np.clip(low, 0, 1), np.clip(high, 0, 1)
    valid &= high - low > 1e-9
    clipped = segments[:, :1] + (segments[:, 1:2] - segments[:, :1]) * np.stack((low, high), axis=1)[:, :, None]
    return valid, clipped, low, high


def prepare_tree(tree):
    """Flatten once per immutable tree/root configuration; analysis stays float64."""
    branches = tree['branches']
    point_arrays = [np.asarray(b['points'], dtype=float) for b in branches]
    counts = np.asarray([len(p) - 1 for p in point_arrays], dtype=np.int64)
    segments = (np.concatenate([np.stack((p[:-1], p[1:]), axis=1) for p in point_arrays])
                if len(branches) else np.empty((0, 2, 3)))
    radii = (np.concatenate([np.maximum(b['radii_mm'][:-1], b['radii_mm'][1:]) for b in branches])
             if len(branches) else np.empty(0))
    owners = np.repeat(np.arange(len(branches)), counts)
    lengths = np.linalg.norm(segments[:, 1] - segments[:, 0], axis=1)
    directions = (segments[:, 1] - segments[:, 0]) / np.maximum(lengths, 1e-30)[:, None]
    result = dict(segments=segments, radii=radii, owners=owners, lengths=lengths, directions=directions)
    for value in result.values():
        value.setflags(write=False)
    return result


def merge_intervals(intervals, tolerance=1e-9):
    """Merge overlaps without bridging separate cut regions or counting twice."""
    result = []
    pairs = sorted((float(low), float(high)) for low, high in intervals)
    for low, high in pairs:
        if high - low <= tolerance:
            continue
        if result and low <= result[-1][1] + tolerance:
            result[-1] = (result[-1][0], max(result[-1][1], high))
        else:
            result.append((float(low), float(high)))
    return result


def _region_intervals(segments, tetrahedra, expansion=0.):
    clips = [clip_segments(segments, tetra, expansion) for tetra in tetrahedra]
    active = np.logical_or.reduce([c[0] for c in clips])
    intervals = [()] * len(segments)
    for i in np.flatnonzero(active):
        intervals[i] = merge_intervals((c[2][i], c[3][i]) for c in clips if c[0][i])
    return active, intervals


def analyze_resection(tree, vertices, lung_index=None, lung_cache=None, prepared=None):
    """Intersect centerlines with the exact union of one or more cut tetrahedra."""
    started = perf_counter()
    tetrahedra = np.asarray(vertices, dtype=float)
    if tetrahedra.shape == (4, 3):
        tetrahedra = tetrahedra[None]
    if tetrahedra.ndim != 3 or tetrahedra.shape[1:] != (4, 3) or not len(tetrahedra):
        raise ValueError('切除区域必须包含至少一个有效四面体')
    data = prepare_tree(tree) if prepared is None else prepared
    segments, radii, owners = data['segments'], data['radii'], data['owners']
    lengths, directions = data['lengths'], data['directions']
    valid, cut_intervals = _region_intervals(segments, tetrahedra)
    near, near_intervals = _region_intervals(segments, tetrahedra, radii)
    active = np.flatnonzero((valid | near) & (lengths > 1e-9))
    cache = {} if lung_cache is None else lung_cache
    if lung_index is not None:
        pending = [int(i) for i in active if int(i) not in cache]
        if pending and hasattr(lung_index, 'intervals_many'):
            intervals = lung_index.intervals_many(segments[pending], lengths[pending])
            if len(intervals) != len(pending):
                raise RuntimeError('Incomplete lung interval batch')
            cache.update(zip(pending, intervals))
    from .planner_reference import tetra_faces
    faces = [face for tetra in tetrahedra for face in
             tetra_faces(list(map(tuple, tetra[:3])), tuple(tetra[3]))]
    normals = np.asarray([f[3] for f in faces])
    offsets = np.einsum('ij,ij->i', np.asarray([f[0] for f in faces]), normals)
    cut_lengths = np.zeros(len(segments))
    removed_segments, cuts_by_branch = [], [[] for _ in tree['branches']]
    near[:] = False
    for idx in active:
        length, direction = lengths[idx], directions[idx]
        intervals = [(0., length)] if lung_index is None else cache.get(int(idx))
        if intervals is None:
            from .ray_golden import inside_intervals
            offset = 1e-6
            hits = lung_index.hits(segments[idx, 0] + direction * offset, direction)
            intervals = inside_intervals(np.asarray(hits) + offset, length, len(hits) % 2 == 1)
            cache[int(idx)] = intervals
        # Even non-overlapping input lung intervals are normalized defensively.
        intervals = merge_intervals(intervals)
        for entry, exit_ in intervals:
            for low, high in cut_intervals[idx]:
                first, last = max(entry, low * length), min(exit_, high * length)
                if last - first <= 1e-7:
                    continue
                piece = segments[idx, 0] + np.asarray([first, last])[:, None] * direction
                removed_segments.append(piece)
                cut_lengths[idx] += last - first
                cuts = cuts_by_branch[owners[idx]]
                on_boundary = np.min(np.abs(piece @ normals.T - offsets), axis=1) < 1e-6
                for point in piece[on_boundary]:
                    if not any(np.linalg.norm(point - old) < 1e-6 for old in cuts):
                        cuts.append(point)
            near[idx] |= any(min(exit_, high * length) - max(entry, low * length) > 1e-7
                             for low, high in near_intervals[idx])
    valid = cut_lengths > 1e-7
    removed_by_branch = np.bincount(owners, weights=cut_lengths, minlength=len(tree['branches']))
    near_by_branch = np.bincount(owners[near], minlength=len(tree['branches']))
    rows = []
    for b in tree['branches']:
        removed = float(removed_by_branch[b['id']])
        status = ('full' if removed >= b['length_mm'] - 1e-6 else 'partial') if removed > 1e-7 else (
            'near' if near_by_branch[b['id']] else 'outside')
        rows.append(dict(id=b['id'], generation=b['generation'], parent=b['parent'],
            provisional=b.get('provisional', False), root=b['root'],
            component=b['component'], diameter_mm=b['diameter_mm'], length_mm=b['length_mm'],
            removed_length_mm=removed, status=status,
            cut_points=[p.tolist() for p in cuts_by_branch[b['id']]], downstream_affected=False))
    # Remove intersected edges and test actual root connectivity. This also
    # respects alternative paths in a cyclic graph; parent traversal would not.
    adjacency = [[] for _ in tree['nodes']]
    for b in tree['branches']:
        if rows[b['id']]['status'] not in ('partial', 'full'):
            adjacency[b['start']].append(b['end'])
            adjacency[b['end']].append(b['start'])
    reachable, queue = set(tree['roots']), list(tree['roots'])
    while queue:
        v = queue.pop()
        for other in adjacency[v]:
            if other not in reachable:
                reachable.add(other); queue.append(other)
    for b in tree['branches']:
        rows[b['id']]['downstream_affected'] = bool(
            rows[b['id']]['status'] not in ('partial', 'full')
            and b['start'] not in reachable and b['end'] not in reachable)
    return dict(rows=rows, removed_segments=np.asarray(removed_segments).reshape(-1, 2, 3),
                near_segments=segments[near & ~valid],
                elapsed_ms=(perf_counter() - started) * 1000.)


def tube_mesh(segments, radius=.35, sides=6):
    # Display-only data: retain float64 for all clipping and length statistics.
    segments = np.asarray(segments, dtype=np.float32).reshape(-1, 2, 3)
    if not len(segments):
        return np.empty((0, 3, 3), dtype=np.float32)
    direction = segments[:, 1] - segments[:, 0]
    lengths = np.linalg.norm(direction, axis=1)
    segments, direction, lengths = segments[lengths > 1e-9], direction[lengths > 1e-9], lengths[lengths > 1e-9]
    direction /= lengths[:, None]
    axis = np.zeros_like(direction); axis[:, 0] = 1
    axis[np.abs(direction[:, 0]) > .9] = (0, 1, 0)
    u = np.cross(direction, axis); u /= np.linalg.norm(u, axis=1)[:, None]
    v = np.cross(direction, u)
    angles = np.arange(sides, dtype=np.float32) * np.float32(2 * np.pi / sides)
    ring = radius * (u[:, None] * np.cos(angles)[None, :, None] + v[:, None] * np.sin(angles)[None, :, None])
    a, b = segments[:, 0, None] + ring, segments[:, 1, None] + ring
    nxt = np.roll(np.arange(sides), -1)
    output = np.empty((len(segments), sides, 2, 3, 3), dtype=np.float32)
    output[:, :, 0, 0], output[:, :, 0, 1], output[:, :, 0, 2] = a, b, b[:, nxt]
    output[:, :, 1, 0], output[:, :, 1, 1], output[:, :, 1, 2] = a, b[:, nxt], a[:, nxt]
    return output.reshape(-1, 3, 3)
