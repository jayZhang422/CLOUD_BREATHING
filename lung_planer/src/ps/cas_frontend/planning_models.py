"""CPU research planners on unchanged source meshes and explicit halfspaces.

The two-plane model has no artificial surgical base or single deep apex. Its
four vertices are only a compatible clipping/branch-analysis container: both
auxiliary caps must be strictly outside the entire selected lung, so they cannot
change the region defined by the two cutting planes and the original lung.
"""
from pathlib import Path
from time import perf_counter
from concurrent.futures import ThreadPoolExecutor
import copy
import math
import os

import numpy as np

from . import planner_reference as ref
from .planning_cancel import checkpoint, PlanningCancelled
from .planning_constraints import base_clearance, constraint_report
from .mesh_triangle import triangle_mesh_min_distance
from .mesh_union import _area, _solid, _library
from .surface_clip import clipped_surface, triangles_overlapping_bounds

MODELS = ('plane_wedge',)
NAMES = dict(plane_wedge='双平面楔形')


def _timing_summary(records):
    """Summarize per-candidate phase timings without hiding individual rows."""
    fields = ('candidate_generation_ms', 'pl_filter_ms', 'container_validation_ms',
              'boolean_total_ms', 'tetra_solid_setup_ms', 'boolean_kernel_ms', 'boolean_status_ms',
              'mesh_convert_ms', 'triangle_extract_classify_ms',
              'area_volume_reduce_ms', 'volume_eval_ms', 'surface_area_reduce_ms',
              'cut_area_reduce_ms', 'ranking_sort_ms', 'candidate_total_ms')
    summary = {}
    for field in fields:
        values = [float(row[field]) for row in records
                  if row.get(field) is not None and math.isfinite(float(row[field]))]
        summary[field] = dict(count=len(values), total_ms=float(sum(values)),
                              median_ms=float(np.percentile(values, 50)) if values else None,
                              p95_ms=float(np.percentile(values, 95)) if values else None,
                              max_ms=float(max(values)) if values else None)
    return summary


def _exact_wedge_volume(union, vertices):
    """Return exact float64 Manifold volume without extracting candidate faces."""
    evaluator = getattr(union, 'intersect_volume', None)
    if evaluator is not None:
        return evaluator(vertices)
    # Preserve the historical adapter contract used by callers that provide a
    # lightweight union test double.
    return union.intersect(vertices)


def model_name(params):
    return params.get('planningModel', 'plane_wedge')


def resection_union(case, params):
    """Use the lesion-boundary STL union for a plane-wedge entry."""
    if model_name(params) == 'plane_wedge':
        # The planning Boolean is bounded by the STL(s) containing the
        # lesion.  The broader same-side union remains available to branch
        # analysis through ``_surgical_lung_union``.
        union = getattr(case, '_planning_lung_union', None)
        if union is None:
            union = getattr(case, '_lung_union', None)
        if union is None:
            raise ValueError('双平面楔形缺少病灶边界肺 STL 并集')
        return union
    return case._lung_union


def planes(vertices):
    faces = ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3]))
    normals = np.asarray([f[3] for f in faces])
    offsets = np.einsum('ij,ij->i', normals, np.asarray([f[0] for f in faces]))
    return normals, offsets


def build_region(case, params, x=None):
    """Tangent supporting planes use a Euclidean ball, not axis-aligned cubes."""
    if model_name(params) not in MODELS:
        raise ValueError('未知研究规划模型')
    x = (np.asarray(x, dtype=float) if x is not None else
         np.asarray([params['yaw'], params['pitch'], params['rotation']] +
                    list(params.get('cutTilts', [params.get('wedgeAngle', 90.) / 2.] * 2))))
    d = np.asarray(ref.direction_for(x[0], x[1]))
    u, v = map(np.asarray, ref.basis(tuple(d)))
    roll = math.radians(x[2])
    u, v = u*math.cos(roll)+v*math.sin(roll), v*math.cos(roll)-u*math.sin(roll)
    center = case.center
    points = case._fit_points-center
    margin = float(params['minClearance']) + 1e-5  # construction guard, never a relaxed threshold
    angles = np.radians(x[3:])
    normals = np.asarray([-math.sin(angles[0])*d + math.cos(angles[0])*u,
                         -math.sin(angles[1])*d - math.cos(angles[1])*u])
    offsets = (points@normals.T).max(axis=0) + margin
    ridge = np.linalg.lstsq(normals, offsets, rcond=None)[0]
    q = np.cross(normals[0], normals[1]); q /= np.linalg.norm(q)
    delta = case.triangles.reshape(-1,3)-center-ridge
    height = 8.*(float(np.abs(delta@d).max())+base_clearance(params)+1.)
    length = 8.*(float(np.abs(delta@q).max())+base_clearance(params)+1.)
    # Faces 1 and 2 are physical cuts. Faces 0 and 3 are nonbinding caps.
    return center + np.asarray((ridge+height*d+height*math.tan(angles[0])*u,
        ridge-length*q, ridge+height*d-height*math.tan(angles[1])*u, ridge+length*q))


def cut_boundary_segments(interior):
    triangles = np.asarray(interior, dtype=float).reshape(-1,3,3)
    if not len(triangles):
        return np.empty((0,2,3))
    vertices, ids = np.unique(triangles.reshape(-1,3), axis=0, return_inverse=True)
    ids = ids.reshape(-1,3)
    edges = np.sort(np.concatenate((ids[:,[0,1]], ids[:,[1,2]], ids[:,[2,0]])), axis=1)
    unique, counts = np.unique(edges, axis=0, return_counts=True)
    return vertices[unique[counts == 1]]


def _validate_container(case, vertices, params, *, prefilter=None,
                        fast_cap_check=False):
    vertices = np.asarray(vertices, dtype=float)
    if vertices.shape != (4,3) or not np.isfinite(vertices).all():
        raise ValueError('规划几何无效')
    if ref.tetrahedron_volume(list(map(tuple, vertices[:3])), tuple(vertices[3])) < 1e-6:
        raise ValueError('规划几何已退化')
    normals, offsets = planes(vertices)
    active, caps = (1,2), (0,3)
    envelope = resection_union(case, params)
    cap_gap = None
    if fast_cap_check and hasattr(envelope, 'bounds_min'):
        cap_normals = normals[list(caps)]
        support = np.where(cap_normals >= 0., envelope.bounds_max,
                           envelope.bounds_min)
        conservative_gap = offsets[list(caps)] - np.einsum(
            'ij,ij->i', cap_normals, support)
        if float(conservative_gap.min()) > 1e-4:
            cap_gap = float(conservative_gap.min())
    if cap_gap is None:
        cap_gap = float(min((offsets[i]-envelope.triangles.reshape(-1, 3)@normals[i]).min()
                            for i in caps))
    if cap_gap <= 1e-4:
        raise ValueError('平面楔形的辅助包围面进入肺模型；拒绝截断真实切除区域')
    certified = (prefilter and prefilter.get('ok')
        and int(prefilter.get('accepted', -1)) == len(case.points)
        and float(prefilter.get('clearance_mm', -math.inf)) -
            float(prefilter.get('quantization_tolerance_mm', math.inf)) >= params['minClearance'])
    if certified:
        coverage = 100.0
        margin = float(prefilter['clearance_mm'])
    else:
        signed = offsets[None,:]-case.points@normals.T
        coverage = float(np.all(signed >= -1e-8, axis=1).mean()*100.)
        margin = float(signed[:,active].min())
    return active, cap_gap, coverage, margin


def _topology(case, vertices, union=None, region=None):
    m = _library()
    if region is None:
        faces = ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3]))
        cutter = _solid(np.asarray([f[:3] for f in faces]), '研究规划区域')
        source_union = union if union is not None else case._lung_union
        region = m.Manifold.batch_boolean([source_union.solid, cutter], m.OpType.Intersect)
    if region.status() != m.Error.NoError:
        raise ValueError('切除区域拓扑检查失败')
    return len(region.decompose())


def _finite_margin(case, interior):
    tumor = np.asarray([t.points for t in case.tumor_triangles], dtype=float)
    bounds = tumor.min(axis=1), tumor.max(axis=1)
    from scipy.spatial import cKDTree
    vertex_tree = cKDTree(tumor.reshape(-1, 3))
    value = float('inf')
    for triangle in interior:
        checkpoint()
        value = min(value, triangle_mesh_min_distance(
            triangle, tumor, bounds, nearest_vertex_tree=vertex_tree,
            upper_bound=value))
    if not math.isfinite(value):
        raise ValueError('缺少实际肺内切面，无法验证有限切面切缘')
    return value


def structure_review(case, vertices, active):
    """Surface involvement only; branch connectivity remains in existing engine."""
    rows = []
    normals, offsets = planes(vertices)
    faces = ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3]))
    for path in sorted(Path(case._research_directory).glob('*.stl')):
        key = path.stem.lower()
        if not any(k in key for k in ('pulmonaryarter', 'pulmonaryven', 'bronchus')) or '_plan_' in key:
            continue
        checkpoint()
        triangles = ref.read_stl_array(path)
        candidate_triangles = triangles_overlapping_bounds(
            triangles, vertices.min(axis=0), vertices.max(axis=0))
        _, patch = clipped_surface(candidate_triangles, faces)
        rows.append(dict(file=path.name, region_surface_area_mm2=_area(patch) if len(patch) else 0.,
            cut_planes_touching_surface=[i for i in active if len(patch) and
                bool(np.any(np.abs(patch@normals[i]-offsets[i]) < 1e-6))]))
    return dict(status='REVIEW_REQUIRED' if rows else 'NO_STRUCTURE_STL', files=rows,
        scope='source structure surface involvement; does not infer anatomy or approve preservation',
        branch_analysis='centerline analysis uses the planning STL boundary and identical effective cutting planes')


def evaluate_region(case, vertices, params, *, review=True, boolean=None):
    phase_timings = {}
    if case._strict_pl or case._lung_union is None:
        raise ValueError('新规划模型目前仅支持电脑 CPU 布尔几何路径')
    phase_started = perf_counter()
    active, cap_gap, coverage, support_margin = _validate_container(case, vertices, params)
    phase_timings['container_validation_ms'] = (perf_counter()-phase_started)*1000.
    mode = model_name(params)
    union = resection_union(case, params)
    phase_started = perf_counter()
    if boolean is None:
        boolean = union.intersect(vertices)
    phase_timings['lung_surface_boolean_total_ms'] = (perf_counter()-phase_started)*1000.
    phase_timings.update({'boolean_' + key: value for key, value in
                          getattr(union, '_last_timings_ms', {}).items()})
    if not len(boolean['interior']) or not len(boolean['surface']):
        raise ValueError('规划没有同时连接真实肺表面和肺内切面')
    phase_started = perf_counter()
    boundary = cut_boundary_segments(boolean['interior'])
    normals, offsets = planes(vertices)
    accessible = [bool(len(boundary) and np.any(np.all(
        np.abs(boundary@normals[i]-offsets[i]) < 1e-6, axis=1))) for i in active]
    if not all(accessible):
        raise ValueError('存在没有肺表面入口的切割平面')
    phase_timings['cut_boundary_and_access_check_ms'] = (perf_counter()-phase_started)*1000.
    phase_started = perf_counter()
    finite_margin = _finite_margin(case, boolean['interior'])
    phase_timings['finite_margin_ms'] = (perf_counter()-phase_started)*1000.
    phase_started = perf_counter()
    component_count = _topology(case, vertices, union, region=boolean.get('_manifold'))
    phase_timings['topology_check_ms'] = (perf_counter()-phase_started)*1000.
    whole_lung_volume = getattr(case, 'whole_lung_volume', case.lung_volume)
    target_lung_files = getattr(case, 'target_lung_files', case.lung_files)
    whole_lung_files = getattr(case, 'whole_lung_files', case.lung_files)
    result = dict(valid=coverage >= 100. and finite_margin >= params['minClearance'],
        coverage_percent=coverage, clearance_mm=float((offsets-case.points@normals.T).min()),
        tumor_margin_mm=finite_margin, base_area_cm2=0., base_outside_valid=True,
        min_base_clearance_mm=None, required_base_clearance_mm=None,
        base_inside_samples=0, apex_inside_lung=None, required_clearance_mm=0.,
        required_tumor_margin_mm=params['minClearance'], risk_score=None,
        lung_files=list(case.lung_files), tumor_file=case.tumor_file, units='mm',
        base_vertices=vertices[:3].tolist(), apex=vertices[3].tolist())
    result.update(planning_model=mode, planning_model_name=NAMES[mode],
        tumor_margin_mm=finite_margin, supporting_plane_margin_mm=support_margin,
        tumor_margin_method='minimum distance between complete tumor triangles and finite in-lung cutting triangles',
        tumor_margin_backend='CPU float64 triangle features',
        base_constraint_applicable=False, auxiliary_cap_min_lung_gap_mm=cap_gap,
        cutting_planes=[dict(normal=normals[i].tolist(), offset_mm=float(offsets[i])) for i in active],
        geometric_surface_access=accessible, instrument_access_status='PENDING_CONFIRMATION',
        region_component_count=component_count,
        volume_method='Manifold float64 intersection of selected lung union and cutting halfspaces',
        quantitative_backend='CPU / Manifold float64 mesh Boolean',
        volume_backend='CPU / Manifold float64 Boolean', distance_backend='CPU / float64 triangle features',
        resection_volume_cm3=boolean['volume_mm3']/1000.,
        lung_volume_cm3=whole_lung_volume/1000.,
        whole_lung_volume_cm3=whole_lung_volume/1000.,
        target_lung_volume_cm3=case.lung_volume/1000.,
        resection_ratio_percent=boolean['volume_mm3']/whole_lung_volume*100.,
        whole_lung_resection_ratio_percent=boolean['volume_mm3']/whole_lung_volume*100.,
        target_lung_resection_ratio_percent=boolean['volume_mm3']/case.lung_volume*100.,
        lung_volume_scope='bilateral whole lung (left + right)',
        target_lung_files=list(target_lung_files), whole_lung_files=list(whole_lung_files),
        planning_boundary_files=list(target_lung_files),
        planning_boundary_scope='lesion-containing STL union',
        surgical_lung_files=list(getattr(case, 'surgical_lung_files', case.lung_files)),
        surgical_lung_volume_scope='complete lung on lesion side',
        surface_area_cm2=boolean['surface_area_mm2']/100., cut_area_cm2=boolean['cut_area_mm2']/100.,
        cut_area_method='source-tagged in-lung Boolean cut faces', strict_pl=False,
        execution_backend='cpu', metric_backend='CPU / research geometry', pl_status='disabled',
        cpu_fallback_count=0, software_revision='desktop-research-models-v1-20261025')
    # Both full coverage and the requested finite-cut margin remain mandatory.
    result['valid'] = bool(result['valid'] and coverage >= 100. and finite_margin >= params['minClearance'])
    result.update(constraint_report(params, finite_margin, result['valid']))
    phase_started = perf_counter()
    if review:
        result['structure_review'] = structure_review(case, vertices, active)
    phase_timings['structure_review_ms'] = (perf_counter()-phase_started)*1000.
    result['full_validation_phase_timings_ms'] = phase_timings
    return dict(vertices=np.asarray(vertices).copy(), params=dict(params), result=result,
        surface=boolean['surface'], interior=boolean['interior'],
        path=boundary,
        points=case.points, case=case, alternatives=[])


def _research_preparation_key(case, job):
    import hashlib
    import json
    digest = hashlib.sha256()
    for value in (case.triangles, case.points, case._fit_points, case.center,
                  resection_union(case, job['params']).triangles):
        array = np.ascontiguousarray(value, dtype=np.float64)
        digest.update(str(array.shape).encode('ascii'))
        digest.update(array.tobytes())
    digest.update(json.dumps(job['params'], sort_keys=True, allow_nan=False).encode('utf-8'))
    return job.get('revision'), digest.digest()


def prepare_research_candidates(case, job):
    """Pure preparation; no hardware, candidate pruning or search decisions."""
    if (job.get('mode') != 'auto' or job.get('backend') != 'pl' or
            model_name(job.get('params', {})) != 'plane_wedge'):
        return
    from scipy.optimize import minimize  # Real import while overlay initializes.
    checkpoint()
    key = _research_preparation_key(case, job)
    params = job['params']
    directions = set(case._candidate_directions())
    directions.add((params['yaw'], params['pitch']))
    coarse = {}
    for yaw, pitch in sorted(directions):
        for roll in (0., 60., 120.):
            for angle in (30., 45., 60.):
                checkpoint()
                values = np.asarray([yaw, pitch, roll, angle, angle], dtype=float)
                started = perf_counter()
                vertices = build_region(case, params, values)
                generation_ms = (perf_counter() - started) * 1000.
                try:
                    validation = _validate_container(case, vertices, params, fast_cap_check=True)
                    error = None
                except (ValueError, np.linalg.LinAlgError) as exc:
                    validation, error = None, str(exc)
                vertices.setflags(write=False)
                coarse[tuple(float(value) for value in values)] = dict(
                    vertices=vertices, candidate_generation_ms=generation_ms,
                    prepared_validation=validation, prepared_validation_error=error)
    checkpoint()
    # Publish only a complete immutable generation; partial/cancelled work is
    # never consumed. run_research rechecks revision, parameters and geometry.
    case._research_prepared = (key, directions, coarse)


def run_research(case, job, progress=lambda message: None, cancelled=lambda: False):
    from scipy.optimize import minimize
    backend = job.get('backend', 'cpu')
    if backend not in ('cpu', 'pl') or (case._strict_pl and model_name(job.get('params', {})) != 'plane_wedge'):
        raise ValueError('研究模型后端不受支持')
    case.search_diagnostics = {}
    case._check_planning_overlap()
    case._research_directory = job['directory']
    params = dict(job['params'])
    mode = model_name(params)
    params.setdefault('wedgeAngle', 90.)
    params.setdefault('cutTilts', [params['wedgeAngle'] / 2.] * 2)
    started = perf_counter()
    evaluations, rejected = 0, {}
    candidate_timings = []
    final_timings = []
    dual_pl_calls = dual_pl_cycles = dual_pl_input_bytes = dual_pl_output_bytes = 0
    dual_pl_fallbacks = 0
    def check():
        checkpoint()
        if cancelled():
            raise PlanningCancelled('规划已停止')
    mesh_session = None
    if backend == 'pl':
        mesh_mode = os.environ.get('DUAL_PLANE_MESH_ENABLE', '0').strip().lower()
        if mesh_mode not in ('0', 'false', 'no', 'off', '1', 'true', 'yes', 'on', 'shadow'):
            raise RuntimeError('invalid DUAL_PLANE_MESH_ENABLE mode')
        if mesh_mode in ('1', 'true', 'yes', 'on', 'shadow'):
            from .dual_plane_mesh_gate import MeshPlanningSession
            evaluator = getattr(case, '_dual_plane_pl', None)
            if evaluator is None:
                raise RuntimeError('双平面 PL 网格加速器不可用')
            mesh_session = MeshPlanningSession(evaluator, resection_union(case, params),
                shadow=mesh_mode=='shadow', cancelled=cancelled)
    if job['mode'] == 'auto':
        best = []
        seen = set()
        coarse_prefilters = {}
        evaluation_cache = {}
        prepared = getattr(case, '_research_prepared', None)
        case._research_prepared = None
        if prepared is not None and prepared[0] == _research_preparation_key(case, job):
            directions, prepared_coarse = prepared[1:]
        else:
            directions = set(case._candidate_directions())
            directions.add((params['yaw'], params['pitch']))
            prepared_coarse = {}

        if backend == 'pl':
            evaluator = getattr(case, '_dual_plane_pl', None)
            if evaluator is None:
                raise RuntimeError('双平面严格 PL 预筛选不可用')
            coarse = []
            for yaw, pitch in sorted(directions):
                for roll in (0., 60., 120.):
                    for angle in (30., 45., 60.):
                        values = np.asarray([yaw, pitch, roll, angle, angle], dtype=float)
                        check()
                        key = tuple(float(value) for value in values)
                        if key in prepared_coarse:
                            coarse_prefilters[key] = dict(prepared_coarse[key])
                            vertices = coarse_prefilters[key]['vertices']
                        else:
                            phase_started = perf_counter()
                            vertices = build_region(case, params, values)
                            generation_ms = (perf_counter() - phase_started) * 1000.
                            coarse_prefilters[key] = dict(vertices=vertices,
                                candidate_generation_ms=generation_ms)
                        coarse.append((key, vertices))
            if coarse:
                phase_started = perf_counter()
                batch = evaluator.evaluate_dual_plane_filter_batch(
                    case.points, np.asarray([row[1] for row in coarse]),
                    params['minClearance'], cancel=cancelled)
                elapsed_ms = (perf_counter() - phase_started) * 1000.
                dual_pl_calls += 1
                dual_pl_cycles += int(batch.get('cycles', 0) or 0)
                dual_pl_input_bytes += int(batch.get('dma_input_bytes', 0) or 0)
                dual_pl_output_bytes += int(batch.get('dma_output_bytes', 0) or 0)
                if not batch.get('ok') or int(batch.get('cpu_fallback_count', 0) or 0) != 0:
                    raise RuntimeError('双平面 PL 批量预筛选失败：' + str(batch.get('error', 'unknown')))
                batch_rows = batch.get('candidates', ())
                if len(batch_rows) != len(coarse):
                    raise RuntimeError('双平面 PL 批量结果数量不匹配')
                tolerance = float(batch.get('quantization_tolerance_mm', 0.) or 0.)
                for index, ((key, _), row) in enumerate(zip(coarse, batch_rows)):
                    if not row.get('ok', True) or int(row.get('cpu_fallback_count', 0) or 0) != 0:
                        raise RuntimeError('双平面 PL 批量候选失败：' + str(index))
                    coarse_prefilters[key].update(
                        prefilter={**row, 'quantization_tolerance_mm': tolerance},
                        pl_filter_ms=elapsed_ms / len(coarse),
                        pl_cycles=(int(batch.get('cycles', 0) or 0) // len(coarse)
                                   + (1 if index < int(batch.get('cycles', 0) or 0) % len(coarse) else 0)),
                        pl_input_bytes=int(batch.get('dma_input_bytes', 0) or 0) if index == 0 else 0,
                        pl_output_bytes=int(batch.get('dma_output_bytes', 0) or 0) if index == 0 else 0,
                        pl_batch_elapsed_ms=elapsed_ms if index == 0 else 0.)
            if mesh_session is not None:
                check()
                mesh_rows = mesh_session.evaluate(np.asarray([row[1] for row in coarse]),
                                                  phase='coarse_batch')
                for (key, _), row in zip(coarse, mesh_rows):
                    coarse_prefilters[key]['pl_mesh'] = row
        def objective(x):
            nonlocal evaluations, dual_pl_calls, dual_pl_cycles
            nonlocal dual_pl_input_bytes, dual_pl_output_bytes, dual_pl_fallbacks
            check()
            evaluations += 1
            candidate_index = evaluations
            candidate_started = perf_counter()
            timing = dict(candidate_index=candidate_index, backend=backend, model=mode,
                          parameters=[float(value) for value in np.asarray(x).reshape(-1)],
                          status='RUNNING', candidate_generation_ms=None,
                          pl_filter_ms=0., container_validation_ms=None,
                          boolean_total_ms=None, boolean_kernel_ms=None,
                          triangle_extract_classify_ms=None, area_volume_reduce_ms=None)
            if candidate_index % 10 == 1:
                progress(f'{NAMES[mode]} · 评价 {candidate_index} · 可行 {len(best)} · {perf_counter()-started:.1f}s')
            try:
                key = tuple(float(value) for value in np.asarray(x).reshape(-1))
                coarse_row = coarse_prefilters.get(key)
                cached_volume = evaluation_cache.get(key)
                if cached_volume is not None:
                    timing.update(status='CACHE_HIT', cache_hit=True,
                                  candidate_generation_ms=0., candidate_total_ms=0.)
                    candidate_timings.append(timing)
                    return cached_volume
                if coarse_row is None:
                    phase_started = perf_counter()
                    vertices = build_region(case, params, x)
                    timing['candidate_generation_ms'] = (perf_counter()-phase_started)*1000.
                else:
                    vertices = coarse_row['vertices']
                    timing['candidate_generation_ms'] = coarse_row['candidate_generation_ms']
                prefilter = None
                if backend == 'pl':
                    evaluator = getattr(case, '_dual_plane_pl', None)
                    if evaluator is None:
                        raise RuntimeError('双平面严格 PL 预筛选不可用')
                    if coarse_row is not None:
                        prefilter = dict(coarse_row['prefilter'])
                        timing['pl_filter_ms'] = coarse_row['pl_filter_ms']
                        timing['pl_cycles'] = coarse_row['pl_cycles']
                        timing['pl_dma_input_bytes'] = coarse_row['pl_input_bytes']
                        timing['pl_dma_output_bytes'] = coarse_row['pl_output_bytes']
                        timing['pl_batch_elapsed_ms'] = coarse_row['pl_batch_elapsed_ms']
                    else:
                        phase_started = perf_counter()
                        prefilter = evaluator.evaluate_dual_plane_filter(
                            case.points, vertices, params['minClearance'], cancel=cancelled)
                        timing['pl_filter_ms'] = (perf_counter()-phase_started)*1000.
                        timing.update(pl_cycles=int(prefilter.get('cycles', 0) or 0),
                                      pl_dma_input_bytes=int(prefilter.get('dma_input_bytes', 0) or 0),
                                      pl_dma_output_bytes=int(prefilter.get('dma_output_bytes', 0) or 0),
                                      pl_service_ms=float(prefilter.get('service_ms', 0.) or 0.),
                                      pl_job_ms=float(prefilter.get('job_ms', 0.) or 0.),
                                      pl_cpu_fallback_count=int(prefilter.get('cpu_fallback_count', 0) or 0))
                        dual_pl_calls += 1
                        dual_pl_cycles += int(prefilter.get('cycles', 0) or 0)
                        dual_pl_input_bytes += int(prefilter.get('dma_input_bytes', 0) or 0)
                        dual_pl_output_bytes += int(prefilter.get('dma_output_bytes', 0) or 0)
                    dual_pl_fallbacks += int(prefilter.get('cpu_fallback_count', 0) or 0)
                    if not prefilter.get('ok') or int(prefilter.get('cpu_fallback_count', 0) or 0) != 0:
                        raise RuntimeError('双平面 PL 预筛选失败：' + str(prefilter.get('error', 'unknown')))
                phase_started = perf_counter()
                if coarse_row is not None and 'prepared_validation' in coarse_row:
                    if coarse_row['prepared_validation_error'] is not None:
                        raise ValueError(coarse_row['prepared_validation_error'])
                    _, _, coverage, margin = coarse_row['prepared_validation']
                    # Preserve the exact old certified-PL reporting behavior.
                    if (prefilter and prefilter.get('ok') and
                            int(prefilter.get('accepted', -1)) == len(case.points) and
                            float(prefilter.get('clearance_mm', -math.inf)) -
                            float(prefilter.get('quantization_tolerance_mm', math.inf)) >= params['minClearance']):
                        coverage, margin = 100., float(prefilter['clearance_mm'])
                else:
                    _, _, coverage, margin = _validate_container(
                        case, vertices, params, prefilter=prefilter,
                        fast_cap_check=True)
                timing['container_validation_ms'] = (perf_counter()-phase_started)*1000.
                if coverage < 100. or margin < params['minClearance']:
                    raise ValueError('覆盖或切缘不足')
                phase_started = perf_counter()
                union = resection_union(case, params)
                if mesh_session is not None:
                    mesh_row = mesh_session.evaluate(np.asarray([vertices]))[0]
                    volume = float(mesh_row['ranking_volume_mm3'])
                    timing.update(pl_mesh_volume_mm3=float(mesh_row['volume_mm3']),
                                  pl_mesh_parity_verified=mesh_row['parity_verified'],
                                  pl_mesh_parity_delta=mesh_row.get('parity_delta'),
                                  pl_mesh_source_triangles=mesh_row.get('source_triangles'),
                                  pl_mesh_cut_triangles=mesh_row.get('cut_triangles'),
                                  pl_mesh_boundary_segments=mesh_row.get('boundary_segments'))
                    boolean = dict(volume_mm3=volume)
                elif backend == 'pl':
                    boolean = _exact_wedge_volume(union, vertices)
                    volume = boolean['volume_mm3']
                else:
                    boolean = union.intersect(vertices)
                    volume = boolean['volume_mm3']
                timing['boolean_total_ms'] = (perf_counter()-phase_started)*1000.
                boolean_timing = (getattr(union, '_volume_timings_ms', None)
                                  if backend == 'pl'
                                  else getattr(union, '_last_timings_ms', {})) or {}
                timing['boolean_kernel_ms'] = boolean_timing.get('boolean_kernel_ms')
                timing['tetra_solid_setup_ms'] = boolean_timing.get('tetra_solid_setup_ms')
                timing['boolean_status_ms'] = boolean_timing.get('boolean_status_ms')
                timing['mesh_convert_ms'] = boolean_timing.get('mesh_convert_ms')
                timing['lung_surface_intersection_ms'] = boolean_timing.get('boolean_kernel_ms')
                timing['triangle_extract_classify_ms'] = boolean_timing.get('triangle_extract_classify_ms')
                timing['area_volume_reduce_ms'] = boolean_timing.get('area_volume_reduce_ms')
                timing['volume_eval_ms'] = boolean_timing.get('volume_eval_ms')
                timing['surface_area_reduce_ms'] = boolean_timing.get('surface_area_reduce_ms')
                timing['cut_area_reduce_ms'] = boolean_timing.get('cut_area_reduce_ms')
                timing['boolean_output_triangles'] = boolean_timing.get('output_triangles')
                if volume <= 1e-6:
                    raise ValueError('区域没有有效肺表面入口')
                key = tuple(np.round(x, 5))
                if key not in seen:
                    sort_started = perf_counter()
                    best.append((volume, np.asarray(x).copy(), vertices,
                                 None if backend == 'pl'
                                 else boolean))
                    best.sort(key=lambda row: row[0]); del best[12:]
                    timing['ranking_sort_ms'] = (perf_counter()-sort_started)*1000.
                    seen.add(key)
                timing['status'] = 'ACCEPTED'
                return volume
            except (ValueError, np.linalg.LinAlgError) as exc:
                name = str(exc)
                rejected[name] = rejected.get(name, 0)+1
                timing['status'] = 'REJECTED'
                return 1e12
            finally:
                timing['candidate_total_ms'] = (perf_counter()-candidate_started)*1000.
                candidate_timings.append(timing)
        if mesh_session is not None:
            # Coarse metrics have already been evaluated in one RTL batch.
            # The same objective sends every new Powell candidate through RTL.
            for key, _ in coarse:
                objective(key)
        elif backend == 'pl' and coarse:
            def evaluate_initial_pl(item):
                key, vertices = item
                candidate_started = perf_counter()
                coarse_row = coarse_prefilters[key]
                timing = dict(candidate_index=None, backend=backend, model=mode,
                              parameters=list(key), status='RUNNING',
                              candidate_generation_ms=coarse_row['candidate_generation_ms'],
                              pl_filter_ms=coarse_row['pl_filter_ms'],
                              container_validation_ms=None, boolean_total_ms=None,
                              boolean_kernel_ms=None, triangle_extract_classify_ms=None,
                              area_volume_reduce_ms=None)
                try:
                    prefilter = dict(coarse_row['prefilter'])
                    timing.update(pl_cycles=coarse_row['pl_cycles'],
                                  pl_dma_input_bytes=coarse_row['pl_input_bytes'],
                                  pl_dma_output_bytes=coarse_row['pl_output_bytes'],
                                  pl_batch_elapsed_ms=coarse_row['pl_batch_elapsed_ms'])
                    phase_started = perf_counter()
                    _, _, coverage, margin = _validate_container(
                        case, vertices, params, prefilter=prefilter,
                        fast_cap_check=True)
                    timing['container_validation_ms'] = (perf_counter()-phase_started)*1000.
                    if coverage < 100. or margin < params['minClearance']:
                        raise ValueError('覆盖或切缘不足')
                    phase_started = perf_counter()
                    union = copy.copy(resection_union(case, params))
                    union._last_key, union._last = None, None
                    union._volume_key, union._volume_manifold = None, None
                    union._volume_tetra_original_id = None
                    union._volume_timings_ms = {}
                    union._last_timings_ms = {}
                    boolean = _exact_wedge_volume(union, vertices)
                    timing['boolean_total_ms'] = (perf_counter()-phase_started)*1000.
                    boolean_timing = (getattr(union, '_volume_timings_ms', None)
                                      or getattr(union, '_last_timings_ms', {}))
                    for name in ('boolean_kernel_ms', 'tetra_solid_setup_ms',
                                 'boolean_status_ms', 'mesh_convert_ms',
                                 'triangle_extract_classify_ms', 'area_volume_reduce_ms',
                                 'volume_eval_ms', 'surface_area_reduce_ms',
                                 'cut_area_reduce_ms', 'output_triangles'):
                        timing[name] = boolean_timing.get(name)
                    timing['lung_surface_intersection_ms'] = boolean_timing.get('boolean_kernel_ms')
                    volume = boolean['volume_mm3']
                    if volume <= 1e-6:
                        raise ValueError('区域没有有效肺表面入口')
                    timing['status'] = 'ACCEPTED'
                    return key, volume, np.asarray(vertices), boolean, timing, None
                except (ValueError, np.linalg.LinAlgError) as exc:
                    timing['status'] = 'REJECTED'
                    return key, 1e12, np.asarray(vertices), None, timing, str(exc)
                finally:
                    timing['candidate_total_ms'] = (perf_counter()-candidate_started)*1000.

            requested_workers = int(os.environ.get('DUAL_PL_BOOLEAN_WORKERS', '2'))
            workers = max(1, min(requested_workers, 4, os.cpu_count() or 1))
            with ThreadPoolExecutor(max_workers=workers,
                                    thread_name_prefix='dual-plane-exact') as pool:
                for offset in range(0, len(coarse), workers):
                    check()
                    batch_rows = list(pool.map(
                        evaluate_initial_pl, coarse[offset:offset+workers]))
                    check()
                    for key, volume, vertices, boolean, timing, reject_reason in batch_rows:
                        evaluations += 1
                        timing['candidate_index'] = evaluations
                        if evaluations % 10 == 1:
                            progress(f'{NAMES[mode]} · 评价 {evaluations} · 可行 {len(best)} · {perf_counter()-started:.1f}s')
                        candidate_timings.append(timing)
                        evaluation_cache[key] = volume
                        if reject_reason is not None:
                            rejected[reject_reason] = rejected.get(reject_reason, 0) + 1
                            continue
                        seen_key = tuple(np.round(key, 5))
                        if seen_key not in seen:
                            sort_started = perf_counter()
                            best.append((volume, np.asarray(key).copy(), vertices, None))
                            best.sort(key=lambda row: row[0]); del best[12:]
                            seen.add(seen_key)
                            timing['ranking_sort_ms'] = (perf_counter()-sort_started)*1000.
            if not coarse:
                raise ValueError('双平面 PL 初始候选批次为空')
        else:
            for yaw, pitch in sorted(directions):
                for roll in (0.,60.,120.):
                    for angle in (30.,45.,60.):
                        objective([yaw,pitch,roll]+[angle]*2)
        seeds = [row[1] for row in best[:3]]
        for seed in seeds:
            check()
            bounds = [(seed[0]-20.,seed[0]+20.),
                      (max(-88.,seed[1]-15.),min(88.,seed[1]+15.)),
                      (seed[2]-30.,seed[2]+30.)]+[(12.,78.)]*2
            seed = np.asarray([np.clip(value,*bound) for value,bound in zip(seed,bounds)])
            minimize(objective, seed, method='Powell', bounds=bounds,
                     options=dict(maxfev=110, xtol=.1, ftol=1e-4))
        if not best:
            raise ValueError('在当前切缘要求下未找到可行研究方案：'+str(rejected))
        # Full checks may reject a coarse candidate. Never expose it to QML.
        payload = None
        for ranked_volume, x, vertices, candidate_boolean in best:
            check()
            tilts = x[3:]
            current = dict(params, yaw=(float(x[0])+180.)%360.-180., pitch=float(x[1]), rotation=float(x[2])%360.,
                           cutTilts=tilts.tolist(), wedgeAngle=float(2.*np.mean(tilts)))
            try:
                final_started = perf_counter()
                candidate = evaluate_region(case, vertices, current,
                                            boolean=candidate_boolean)
                if mesh_session is not None:
                    exact = candidate['result']
                    reference_metrics = np.asarray([exact['resection_volume_cm3']*1000.,
                        exact['surface_area_cm2']*100., exact['cut_area_cm2']*100.])
                    mesh_row = mesh_session.evaluate(np.asarray([vertices]),
                                                     phase='final_review')[0]
                    hardware_metrics = np.asarray([mesh_row[key] for key in
                        ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2')])
                    if np.any(np.abs(hardware_metrics-reference_metrics)>1e-5):
                        raise RuntimeError('双平面 PL 最优候选未通过 Manifold 完整复核')
                full_timing = dict(candidate_index=len(final_timings) + 1,
                                   full_validation_ms=(perf_counter()-final_started)*1000.,
                                   phases_ms=candidate['result'].get('full_validation_phase_timings_ms', {}),
                                   status='PASS')
            except ValueError as exc:
                full_timing = dict(candidate_index=len(final_timings) + 1,
                                   full_validation_ms=(perf_counter()-final_started)*1000.,
                                   status='REJECTED')
                rejected[str(exc)] = rejected.get(str(exc),0)+1
                final_timings.append(full_timing)
                continue
            final_timings.append(full_timing)
            if candidate['result']['valid']:
                payload = candidate
                break
        if payload is None:
            raise ValueError('候选未通过完整几何校验：'+str(rejected))
    else:
        check()
        vertices = job.get('vertices')
        vertices = build_region(case, params) if vertices is None else np.asarray(vertices, dtype=float).copy()
        if backend == 'pl':
            evaluator = getattr(case, '_dual_plane_pl', None)
            if evaluator is None:
                raise RuntimeError('双平面严格 PL 预筛选不可用')
            prefilter = evaluator.evaluate_dual_plane_filter(
                case.points, vertices, params['minClearance'])
            dual_pl_calls += 1
            dual_pl_cycles += int(prefilter.get('cycles', 0) or 0)
            dual_pl_input_bytes += int(prefilter.get('dma_input_bytes', 0) or 0)
            dual_pl_output_bytes += int(prefilter.get('dma_output_bytes', 0) or 0)
            # A hardware or service failure is still fatal. A conservative-margin
            # shortfall is not: the Q16.16 prefilter subtracts its quantization
            # tolerance, so a candidate whose exact margin equals the target
            # (build_region sets it to minClearance + 1e-5) always looks short.
            # evaluate_region below re-decides coverage and margin in float64.
            if not prefilter.get('ok') or prefilter.get('cpu_fallback_count') != 0:
                detail = str(prefilter.get('error') or 'PL 预筛选调用失败')
                raise ValueError('PL 双平面预筛选调用失败：' + detail)
        mesh_row = None
        if mesh_session is not None:
            mesh_row = mesh_session.evaluate(np.asarray([vertices]))[0]
        payload = evaluate_region(case, vertices, params)
        if mesh_row is not None:
            exact = payload['result']
            actual = np.asarray([mesh_row[key] for key in
                ('volume_mm3', 'surface_area_mm2', 'cut_area_mm2')])
            reference = np.asarray([exact['resection_volume_cm3']*1000.,
                exact['surface_area_cm2']*100., exact['cut_area_cm2']*100.])
            if np.any(np.abs(actual-reference)>1e-5):
                raise RuntimeError('双平面 PL 手动候选未通过 Manifold 完整复核')
    payload['result']['algorithm'] = ('independent supporting cuts, Euclidean tumor margin, '
        'bounded multistart search minimizing exact lesion-boundary-STL intersection volume')
    check()
    payload['result'].update(search_evaluations=evaluations, search_rejected=rejected,
        search_candidate_timings=candidate_timings,
        search_phase_timing=_timing_summary(candidate_timings),
        full_validation_timings=final_timings,
        full_validation_total_ms=float(sum(row['full_validation_ms'] for row in final_timings)),
        search_orchestration_ms=max(0., (perf_counter()-started)*1000.
                                     - sum(row.get('candidate_total_ms', 0.) for row in candidate_timings)
                                     - sum(row.get('full_validation_ms', 0.) for row in final_timings)),
        dual_plane_pl_calls=dual_pl_calls, dual_plane_pl_cycles=dual_pl_cycles,
        dual_plane_pl_input_bytes=dual_pl_input_bytes,
        dual_plane_pl_output_bytes=dual_pl_output_bytes,
        dual_plane_pl_cpu_fallback_count=dual_pl_fallbacks,
        dual_plane_pl_candidates=(dual_pl_calls and
            sum(int(row.get('pl_filter_ms', 0.) > 0.) for row in candidate_timings) or 0),
        dual_plane_filter_backend='FPGA PL Q16.16 half-space prefilter' if backend == 'pl' else 'disabled',
        exact_geometry_backend='CPU / Manifold float64',
        execution_backend='dual_plane_pl_filter+ps_exact' if backend == 'pl' else 'cpu',
        metric_backend='FPGA PL Q16.16 prefilter + CPU / Manifold float64' if backend == 'pl' else 'CPU / research geometry',
        pl_status='ready' if backend == 'pl' else 'disabled',
        cpu_fallback_count=dual_pl_fallbacks,
        workload_ms=(perf_counter()-started)*1000., geometry_ms=(perf_counter()-started)*1000.)
    if mesh_session is not None:
        payload['result'].update(
            execution_backend=('dual_plane_pl_mesh_shadow' if mesh_session.shadow
                               else 'dual_plane_pl_mesh+ps_final_review'),
            exact_geometry_backend='FPGA PL float64 + Manifold float64 final review',
            metric_backend='FPGA PL float64 mesh metrics + Manifold float64 final review',
            dual_plane_mesh_calls=mesh_session.calls,
            dual_plane_mesh_candidates=mesh_session.checked_candidates,
            dual_plane_mesh_cycles=mesh_session.cycles,
            dual_plane_mesh_call_timings=mesh_session.call_timings,
            dual_plane_mesh_input_bytes=mesh_session.input_bytes,
            dual_plane_mesh_output_bytes=mesh_session.output_bytes,
            dual_plane_mesh_admission_sha256=mesh_session.receipt_sha256,
            dual_plane_mesh_shadow=mesh_session.shadow)
    return payload
