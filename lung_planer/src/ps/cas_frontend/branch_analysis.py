"""Backend-neutral branch post-processing; strict PL lung-union queries.

Run on the planner's worker thread, which owns its case and PL client.
No centerline extraction or branch grading is performed by the FPGA.
"""
from collections import OrderedDict
from copy import copy
import hashlib
from time import perf_counter

import numpy as np

from .centerlines import analyze_resection, tube_mesh, prepare_tree
from .ray_golden import inside_intervals


def _tree_is_source_space(tree):
    """Return whether STL/source coordinates need the case CT transform.

    Older legacy centerline caches have no mask metadata, so they are treated
    as source coordinates.  NPY masks carry world coordinates already and do
    not go through the STL-to-CT transform.
    """
    metadata = tree.get('mask_metadata') or {}
    source = metadata.get('source') if isinstance(metadata, dict) else None
    if isinstance(source, dict) and source.get('format') == 'npy':
        return False
    return tree.get('coordinate_space') != 'physical_mm'


def _tree_in_case_space(tree, case):
    """Convert a centerline tree to the immutable PlanningCase physical frame."""
    spacing = np.asarray(getattr(case, 'ct_spacing', (1., 1., 1.)), dtype=np.float64)
    if spacing.shape != (3,) or np.allclose(spacing, 1., rtol=0., atol=1e-12) \
            or not _tree_is_source_space(tree):
        return tree

    # The source centerline is generated from the STL voxel frame while the
    # planning mesh and resection vertices are in CT physical millimetres.
    # Keep the original tree immutable for rendering and cache the converted
    # geometry only for this analysis call.
    radius_scale = float(np.cbrt(np.prod(spacing)))
    nodes = []
    for node in tree['nodes']:
        item = dict(node)
        item['point'] = (np.asarray(node['point'], dtype=np.float64) * spacing).tolist()
        if 'radius_mm' in node:
            item['radius_mm'] = float(node['radius_mm']) * radius_scale
        nodes.append(item)
    branches = []
    for branch in tree['branches']:
        item = dict(branch)
        points = np.asarray(branch['points'], dtype=np.float64) * spacing
        radii = np.asarray(branch['radii_mm'], dtype=np.float64) * radius_scale
        item['points'] = points.tolist()
        item['radii_mm'] = radii.tolist()
        item['length_mm'] = float(np.linalg.norm(np.diff(points, axis=0), axis=1).sum())
        item['diameter_mm'] = float(2. * np.median(radii)) if len(radii) else 0.
        branches.append(item)
    converted = dict(tree, nodes=nodes, branches=branches,
                     coordinate_space='physical_mm',
                     source_coordinate_space='stl_source')
    return converted


class AnalysisCancelled(RuntimeError):
    pass


def branch_case(case, backend):
    """Use the exact planning boundary for wedge analysis, with branch-only PL strictness.

    The planning case stays non-strict because its final Boolean uses Manifold.
    A separate view reuses the strict crossing decoder without enabling any
    fallback or changing the planner's selected-segment mesh.
    """
    if getattr(case, '_planning_model', '') != 'plane_wedge':
        return case
    # The planning Boolean clips the two effective planes to this exact STL
    # union. Using the larger same-side surgical union here would count vessels
    # inside the infinite wedge but outside the resection that was planned.
    union = getattr(case, '_planning_lung_union', None)
    if union is None:
        raise RuntimeError('双平面分支分析缺少规划使用的病灶边界肺并集')
    key = '_branch_case_' + backend
    cached = getattr(case, key, None)
    if cached is not None:
        return cached
    from .frozen_mesh import FrozenMesh
    view = copy(case)
    resource = FrozenMesh(union.triangles)
    view.triangles = resource.triangles
    view._triangle_groups = resource.solid_ids
    view._mesh_resource = resource
    view.__dict__.pop('_branch_mesh_identity', None)
    if backend == 'pl':
        if (getattr(case, '_ray_mode', '') != 'bvh_pl'
                or getattr(case, '_mesh_evaluator', None) is None):
            raise RuntimeError('分支分析需要严格 PL 完整交点接口，禁止 CPU 回退')
        view._strict_pl = True
        view._mesh_stats = dict(calls=0, rays=0, hits=0, job_ms=0., service_ms=0., cycles=0)
    else:
        from .mesh_cpu import CpuMeshIndex
        view._cpu_index = CpuMeshIndex(view.triangles)
    setattr(case, key, view)
    return view


class PlLungQuery:
    def __init__(self, case, cancelled=lambda: False, batch_size=256):
        if not (getattr(case, '_strict_pl', False)
                and getattr(case, '_ray_mode', '') == 'bvh_pl'):
            raise RuntimeError('分支分析需要严格 PL 完整交点接口，禁止 CPU 回退')
        self.case, self.cancelled, self.batch_size = case, cancelled, batch_size
        self.rays = self.calls = self.cycles = 0
        self.query_ms = 0.

    def intervals_many(self, segments, lengths):
        output = []
        for first in range(0, len(segments), self.batch_size):
            if self.cancelled():
                raise AnalysisCancelled()
            batch = segments[first:first + self.batch_size]
            sizes = lengths[first:first + self.batch_size]
            directions = (batch[:, 1] - batch[:, 0]) / sizes[:, None]
            # Same surface offset and interval convention as the CPU reference.
            offset = 1e-6
            before = dict(self.case._mesh_stats)
            started = perf_counter()
            hits = self.case._ray_hits_many(batch[:, 0] + directions * offset,
                directions, require_complete=True)
            self.query_ms += (perf_counter() - started) * 1000.
            if hits is None or len(hits) != len(batch):
                raise RuntimeError('PL 未返回完整中心线交点，禁止 CPU 回退')
            self.calls += self.case._mesh_stats.get('calls', 0) - before.get('calls', 0)
            self.cycles += self.case._mesh_stats.get('cycles', 0) - before.get('cycles', 0)
            self.rays += len(batch)
            for crossings, length in zip(hits, sizes):
                crossings = np.asarray(crossings)
                if not np.isfinite(crossings).all():
                    raise RuntimeError('PL 中心线交点包含无效数值')
                output.append(inside_intervals(crossings + offset, length, len(crossings) % 2 == 1))
        return output


class CpuLungQuery:
    def __init__(self, index, cancelled=lambda: False):
        self.index, self.cancelled = index, cancelled
        self.rays = self.calls = self.cycles = 0
        self.query_ms = 0.

    def intervals_many(self, segments, lengths):
        started = perf_counter()
        output = []
        for segment, length in zip(segments, lengths):
            if self.cancelled():
                raise AnalysisCancelled()
            direction = (segment[1] - segment[0]) / length
            offset = 1e-6
            hits = self.index.hits(segment[0] + direction * offset, direction)
            output.append(inside_intervals(np.asarray(hits) + offset, length, len(hits) % 2 == 1))
        self.query_ms += (perf_counter() - started) * 1000.
        self.rays += len(segments)
        return output


def mesh_identity(case):
    """Immutable source coordinates include lung-solid labels and transforms."""
    if getattr(case, '_planning_model', '') == 'plane_wedge':
        union = getattr(case, '_planning_lung_union', None)
        if union is None:
            raise RuntimeError('双平面分支分析缺少规划使用的病灶边界肺并集')
        return hashlib.sha256(np.ascontiguousarray(union.triangles, dtype='<f8').tobytes()).hexdigest()
    key = getattr(case, '_branch_mesh_identity', None)
    if key is None:
        digest = hashlib.sha256()
        digest.update(np.ascontiguousarray(case.triangles, dtype='<f8').tobytes())
        groups = getattr(case, '_triangle_groups', np.zeros(len(case.triangles), dtype=int))
        digest.update(np.ascontiguousarray(groups, dtype='<i8').tobytes())
        key = digest.hexdigest()
        case._branch_mesh_identity = key
    return key


class BranchAnalysisEngine:
    def __init__(self):
        self.caches = OrderedDict()
        self.prepared = OrderedDict()
        self.converted = OrderedDict()

    def run(self, case, backend, trees, vertices, *, pl=None,
            cancelled=lambda: False, build_meshes=True):
        started = perf_counter()
        if cancelled():
            raise AnalysisCancelled()
        case = branch_case(case, backend)
        # Bind the selected lesion's immutable mesh before querying shared PL.
        if backend == 'pl' and pl is not None and hasattr(case, '_mesh_resource'):
            pl.cache_mesh_resource(case._mesh_resource)
        query = (PlLungQuery(case, cancelled) if backend == 'pl' else
                 CpuLungQuery(case._cpu_index, cancelled))
        if backend == 'cpu' and query.index is None:
            raise RuntimeError('PS 肺网格索引不可用')
        key = (backend, mesh_identity(case))
        caches = self.caches.setdefault(key, OrderedDict())
        self.caches.move_to_end(key)
        while len(self.caches) > 4:
            self.caches.popitem(last=False)
        case_token = id(case)
        spacing = tuple(np.asarray(getattr(case, 'ct_spacing', (1., 1., 1.)),
                                   dtype=np.float64).round(12))
        analysis_trees = []
        for original in trees:
            converted_key = (case_token, original['cache_key'], tuple(original['roots']), spacing)
            converted = self.converted.get(converted_key)
            if converted is None:
                converted = _tree_in_case_space(original, case)
                self.converted[converted_key] = converted
                self.converted.move_to_end(converted_key)
                while len(self.converted) > 12:
                    self.converted.popitem(last=False)
            else:
                self.converted.move_to_end(converted_key)
            analysis_trees.append(converted)
        analyses, removed, near = [], [], []
        for tree in analysis_trees:
            if cancelled():
                raise AnalysisCancelled()
            tree_key = (tree['cache_key'], tuple(tree['roots']), spacing,
                        tree.get('coordinate_space', 'source_stl'))
            if tree_key not in self.prepared:
                self.prepared[tree_key] = prepare_tree(tree)
            self.prepared.move_to_end(tree_key)
            while len(self.prepared) > 12:
                self.prepared.popitem(last=False)
            cache = caches.setdefault(tree_key, {})
            caches.move_to_end(tree_key)
            while len(caches) > 12:
                caches.popitem(last=False)
            analysis = analyze_resection(tree, vertices, query, cache, self.prepared[tree_key])
            analyses.append(analysis)
            removed.extend(analysis['removed_segments'])
            near.extend(analysis['near_segments'])
        timing = dict(elapsed_ms=(perf_counter() - started) * 1000.,
            query_ms=query.query_ms, queried_segments=query.rays,
            pl_calls=query.calls, pl_cycles=query.cycles, cpu_fallback_count=0,
            lung_backend=backend, postprocess_backend='ps',
            interval_cache_hit=query.rays == 0)
        report = dict(method='PS voxel Lee skeleton / PS polyline-halfspace clipping / '
            + ('PL' if backend == 'pl' else 'PS') + ' lung-union ray intervals',
            grading='topological generation from selected component root; not anatomical labels',
            scope='centerline intersection with the planning tetrahedron AND exact planning lung STL union; radius-expanded halfspaces only flag possible wall proximity',
            planning_backend=backend, timing=timing, trees=[],
            analysis_scope='union' if np.asarray(vertices).ndim == 3 else 'current',
            region_count=len(vertices) if np.asarray(vertices).ndim == 3 else 1,
            analysis_coordinate_space='physical_mm',
            ct_spacing_mm=list(spacing),
            union_method='merge continuous intervals before measuring length; each source branch listed once')
        for tree, analysis in zip(analysis_trees, analyses):
            report['trees'].append(dict(file=tree['file'], kind=tree['kind'],
                source_sha256=tree['source_sha256'], spacing_mm=tree['spacing_mm'],
                root_confirmed=tree.get('root_confirmed', False), roots=tree['roots'],
                rows=analysis['rows'], elapsed_ms=analysis['elapsed_ms']))
        output = dict(analyses=analyses, report=report, timing=timing)
        if build_meshes:
            mesh_started = perf_counter()
            output.update(removed_mesh=tube_mesh(removed, .65), near_mesh=tube_mesh(near, .44))
            timing['highlight_mesh_ms'] = (perf_counter() - mesh_started) * 1000.
        timing['total_ms'] = (perf_counter() - started) * 1000.
        return output
