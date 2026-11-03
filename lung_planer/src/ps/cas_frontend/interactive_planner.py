"""Display/edit policy around the unchanged, validated PL planner release.

No kernels, quantitative meshes, validation rules or exported metrics change.
"""
import hashlib
import json
import logging
import os
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event

import numpy as np
from PySide6.QtCore import Property, QObject, QRunnable, QThreadPool, Signal, Slot, QEvent, Qt, QTimer
from PySide6.QtGui import QVector3D, QGuiApplication

from .planner import PlannerController as ReleasePlanner
from . import planner_reference as ref
from .mesh_cpu import CpuMeshIndex
from .ray_golden import inside_from_crossings
from .surface_clip import clipped_surface
from .display_contact import contact_mask
from .planning_cancel import checkpoint, cancellation_scope, PlanningCancelled
from .drag_trace import DragTrace, geometry_identity
from .resection_choice import (LOBECTOMY_MIN_DIAMETER_MM, component_diameter_mm, lobe_label,
                               locate_lobes, needs_lobectomy, split_lesions)


def target_lobe(case):
    """Containing lobe first, then nearest surface, in source coordinates."""
    cached = getattr(case, '_display_target_lobe', None)
    if cached is not None:
        return cached
    direction = np.array([1., .371390676, .127831])
    direction /= np.linalg.norm(direction)
    candidates = []
    for group, name in enumerate(case.lung_files):
        mesh = case.triangles[case._triangle_groups == group]
        if not len(mesh):
            continue
        index = CpuMeshIndex(mesh)
        inside = bool(inside_from_crossings(index.hits(case.center + direction*1e-5, direction)))
        candidates.append((not inside, index.distance(case.center), name, mesh))
    if not candidates:
        return '', np.empty((0, 3, 3))
    chosen = min(candidates, key=lambda row: row[:3])
    case._display_target_lobe = chosen[2], chosen[3]
    return case._display_target_lobe


def tumor_digest(triangles):
    values = np.asarray([t.points for t in triangles], dtype='<f8')
    return hashlib.sha256(values.tobytes()).hexdigest()


def external_patch(case, vertices, contact_mm=1.0):
    """Combine exposed wedge patches from ALL intersected lobes.

    ``PlanningCase`` stores its mesh and all geometric predicates in CT
    physical millimetres.  Convert the viewer/source vertices to physical
    millimetres for clipping and proximity tests, then convert the resulting
    display triangles back to STL/source coordinates before returning them to
    QML.  Keeping both conversions explicit prevents non-unit CT spacing from
    moving the displayed patch away from the validated tetrahedron.

    Split once before classification to localize contact boundaries. Require
    centroid and three edge samples to be clear of every other lobe. The
    1 mm tolerance treats segmentation gaps as contacts, not exposed pleura.
    This is a conservative geometric display approximation, not anatomy.
    """
    checkpoint()
    physical_vertices = case.to_physical_vertices(vertices)
    faces = ref.tetra_faces(list(map(tuple, physical_vertices[:3])),
                            tuple(physical_vertices[3]))
    # The patch starts on the exact planning boundary. Other same-side source
    # STLs are used to remove contact interfaces from that patch.
    use_union_surface = (getattr(case, 'planning_model', None) == 'plane_wedge'
                         or getattr(case, '_planning_model', None) == 'plane_wedge')
    planning_union = getattr(case, '_planning_lung_union', None)
    if planning_union is None:
        planning_union = getattr(case, '_surgical_lung_union', None)
    if planning_union is None:
        planning_union = getattr(case, '_lung_union', None)
    if use_union_surface and planning_union is not None:
        _, raw = clipped_surface(np.asarray(planning_union.triangles, dtype=np.float64), faces)
        patch = raw
        contact_meshes = getattr(case, '_display_contact_meshes', {})
        if len(raw) and contact_meshes:
            signature = tuple((name, id(mesh)) for name, mesh in sorted(contact_meshes.items()))
            cache = getattr(case, '_display_contact_indices', None)
            if cache is None or cache[0] != signature:
                cache = (signature, [(name, CpuMeshIndex(mesh))
                                     for name, mesh in sorted(contact_meshes.items())])
                case._display_contact_indices = cache
            indices = [index for _, index in cache[1]]
            patch = _exposed_patch(raw, indices, contact_mm)
        display_patch = case.to_source_vertices(patch) if len(patch) else patch
        audits = getattr(case, '_display_patch_audits', {})
        audits[np.asarray(vertices).tobytes()] = [dict(
            lobe='planning-boundary-exposed-surface', raw_triangles=len(raw),
            exterior_triangles=len(patch), display_subtriangles=4*len(raw),
            contact_queries=sum(getattr(index, '_display_contact_stats', {}).get('calls', 0)
                                for index in (indices if len(raw) and contact_meshes else [])))]
        case._display_patch_audits = audits
        return 'planning-boundary-exposed-surface', display_patch

    indices = getattr(case, '_display_lobe_indices', None)
    if indices is None:
        indices = []
        for group, name in enumerate(case.lung_files):
            checkpoint()
            mesh = case.triangles[case._triangle_groups == group]
            if len(mesh):
                indices.append((name, mesh, CpuMeshIndex(mesh)))
        case._display_lobe_indices = indices
    names, patches, counts = [], [], []
    for name, source, own_index in indices:
        checkpoint()
        query_before = {id(index): getattr(index, '_display_contact_stats', {}).get('calls', 0)
                        for other, _, index in indices if other != name}
        _, raw = clipped_surface(source, faces)
        if not len(raw):
            continue
        patch = _exposed_patch(raw, [index for other, _, index in indices if other != name], contact_mm)
        counts.append(dict(lobe=name, raw_triangles=len(raw), exterior_triangles=len(patch),
                           display_subtriangles=4*len(raw),
                           contact_queries=sum(
                               getattr(index, '_display_contact_stats', {}).get('calls', 0)
                               - query_before.get(id(index), 0)
                               for other, _, index in indices if other != name)))
        if len(patch):
            names.append(name)
            patches.append(patch)
    # The clipping and contact predicates above are evaluated in physical mm.
    # QML, however, renders the original STL/source coordinate space.  Keep
    # the cache key in the source vertex space and convert the resulting
    # triangles at this boundary so a non-unit CT spacing cannot translate or
    # scale the yellow patch away from the lesion.
    combined = np.concatenate(patches) if patches else np.empty((0, 3, 3))
    display_patch = case.to_source_vertices(combined) if len(combined) else combined
    # Per-result audit is keyed by geometry; caller caches the combined mesh.
    audits = getattr(case, '_display_patch_audits', {})
    audits[np.asarray(vertices).tobytes()] = counts
    case._display_patch_audits = audits
    return '; '.join(names), display_patch


def _exposed_patch(patch, indices, contact_mm):
    """Remove a lobe's interfaces against every other lobe, symmetrically."""
    a,b,c = patch[:,0], patch[:,1], patch[:,2]
    ab,bc,ca = (a+b)/2, (b+c)/2, (c+a)/2
    patch = np.concatenate([np.stack(t,axis=1) for t in
                            ((a,ab,ca),(ab,b,bc),(ca,bc,c),(ab,bc,ca))])
    samples = np.stack((patch.mean(axis=1), (patch[:,0]+patch[:,1])/2,
                        (patch[:,1]+patch[:,2])/2, (patch[:,2]+patch[:,0])/2), axis=1)
    keep = np.ones(len(patch), dtype=bool)
    for index in indices:
        checkpoint()
        # AABB rejects remote samples without any BVH queries.
        near = np.any(np.all((samples >= index.low[0]-contact_mm) &
                             (samples <= index.high[0]+contact_mm), axis=2), axis=1)
        rows = np.flatnonzero(keep & near)
        if len(rows):
            contact = contact_mask(index,samples[rows].reshape(-1,3),contact_mm)
            keep[rows] &= ~contact.reshape(-1,4).any(axis=1)
    return patch[keep]


def _display_query_snapshot(case):
    snapshot = {}
    for _, _, index in getattr(case, '_display_lobe_indices', []):
        stats = getattr(index, '_display_contact_stats', {})
        snapshot[id(index)] = dict(
            builds=index._display_contact_array_builds,
            build_ms=index._display_contact_array_build_ms,
            calls=stats.get('calls', 0), points=stats.get('points', 0),
            proximity_ms=stats.get('proximity_ms', 0.),
            parity_ms=stats.get('parity_ms', 0.),
            distance_pairs=stats.get('distance_triangle_pairs', 0),
            ray_pairs=stats.get('ray_triangle_pairs', 0),
            **{key: stats.get(key, 0) for key in ('native_calls', 'native_points',
                'native_compute_ms', 'numpy_guard_points', 'numpy_guard_ms')})
    return snapshot


def _display_query_delta(case, before):
    indexes = [index for _, _, index in getattr(case, '_display_lobe_indices', [])]
    totals = dict(bvh_array_builds=0, bvh_array_build_ms=0., contact_queries=0,
                  contact_points=0, proximity_ms=0., parity_ms=0.,
                  distance_triangle_pairs=0, ray_triangle_pairs=0)
    for key in ('native_calls', 'native_points', 'native_compute_ms',
                'numpy_guard_points', 'numpy_guard_ms'):
        totals[key] = 0
    for index in indexes:
        old = before.get(id(index), {})
        stats = getattr(index, '_display_contact_stats', {})
        totals['bvh_array_builds'] += index._display_contact_array_builds - old.get('builds', 0)
        totals['bvh_array_build_ms'] += index._display_contact_array_build_ms - old.get('build_ms', 0.)
        totals['contact_queries'] += stats.get('calls', 0) - old.get('calls', 0)
        totals['contact_points'] += stats.get('points', 0) - old.get('points', 0)
        totals['proximity_ms'] += stats.get('proximity_ms', 0.) - old.get('proximity_ms', 0.)
        totals['parity_ms'] += stats.get('parity_ms', 0.) - old.get('parity_ms', 0.)
        totals['distance_triangle_pairs'] += stats.get('distance_triangle_pairs', 0) - old.get('distance_pairs', 0)
        totals['ray_triangle_pairs'] += stats.get('ray_triangle_pairs', 0) - old.get('ray_pairs', 0)
        for key in ('native_calls', 'native_points', 'native_compute_ms',
                    'numpy_guard_points', 'numpy_guard_ms'):
            totals[key] += stats.get(key, 0) - old.get(key, 0)
    totals['bvh_cached_arrays'] = sum(index._display_contact_arrays is not None for index in indexes)
    try:
        batch_points = int(os.environ.get('CLOUD_BREATHING_DISPLAY_BATCH_POINTS', '1024'))
    except ValueError:
        batch_points = 1024
    totals['batch_points'] = min(16384, max(1, batch_points))
    return totals


def _compute_external_patch(case, vertices, cancel_token=None):
    before = _display_query_snapshot(case)
    started = time.perf_counter()
    with cancellation_scope(cancel_token):
        patch = external_patch(case, vertices)
    completed_ns = time.perf_counter_ns()
    metrics = _display_query_delta(case, before)
    metrics.update(duration_ms=(time.perf_counter()-started)*1000.,
                   exterior_triangles=len(patch[1]))
    # The EGLFS/desktop launcher may not provide a valid stdout handle.
    # Logging must never turn a completed geometry calculation into a failed
    # planning job (Windows reports OSError 22 for print() in that case).
    logger = logging.getLogger(__name__)
    logger.info('EXTERNAL_PATCH %s %d ms %.2f', patch[0], len(patch[1]),
                metrics['duration_ms'])
    logger.info('EXTERNAL_PATCH_TIMING %s', json.dumps(
        dict(geometry_id=geometry_identity(vertices), lobes=patch[0], **metrics),
        separators=(',', ':')))
    return patch, metrics, completed_ns


def install_case_reuse(worker):
    """Reuse only the existing worker case when files and lesion bytes match.

    The release reconstructs any job carrying tumor_triangles. Strip that
    redundant override only after exact equivalence to its cached case; clear
    component resolution for this invocation to avoid reintroducing it.
    The bound hook runs exclusively on the existing serial worker thread.
    """
    execute = worker._execute

    def reused(job, backend, *, fresh=False, progress_prefix=''):
        checkpoint()
        case = worker.case
        execute_job = job
        if not fresh and case is not None:
            files = job['lung'] + [job['tumor']]
            stamps = tuple((name, (Path(job['directory'])/name).stat().st_mtime_ns,
                            (Path(job['directory'])/name).stat().st_size) for name in files)
            same_case = (job['directory'], stamps, backend) == worker.key
            override = job.get('tumor_triangles')
            same_lesion = (override is None or
                           tumor_digest(override) == tumor_digest(case.tumor_triangles))
            if same_case and same_lesion and override is not None:
                execute_job = dict(job, tumor_triangles=None, lesion_component_ids=None)

        trace = execute_job.get('_drag_trace')
        parallel_case = None
        parallel_key = None
        parallel_future = None
        parallel_enabled = os.environ.get('CLOUD_BREATHING_DISPLAY_PARALLEL', '1') != '0'
        vertices = execute_job.get('vertices')
        if (parallel_enabled and backend == 'pl' and not fresh and case is not None
                and execute_job.get('mode') == 'manual' and vertices is not None
                and execute_job.get('lesion_component_ids') is None
                and (execute_job.get('tumor_triangles') is None
                     or execute_job is not job)):
            # Worker jobs restored from a saved plan carry physical-mm
            # vertices, while the display cache is keyed by the source/STL
            # coordinates returned to QML.  Normalize before submitting the
            # parallel display calculation so a restored plan cannot be
            # scaled a second time and cannot populate a cache under a key
            # that the GUI will never use.
            vertices_snapshot = np.asarray(vertices, dtype=np.float64).copy()
            if execute_job.get('vertices_space', 'source') == 'physical':
                vertices_snapshot = case.to_source_vertices(vertices_snapshot)
            parallel_key = vertices_snapshot.tobytes()
            existing = getattr(case, '_display_patch_cache', {})
            if parallel_key not in existing:
                parallel_case = case
                executor = getattr(worker, '_display_executor', None)
                if executor is None:
                    executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix='display-patch')
                    worker._display_executor = executor
                    worker.destroyed.connect(
                        lambda *_args, pool=executor: pool.shutdown(wait=False, cancel_futures=True))
                if trace is not None:
                    trace.mark('external_geometry_start', cache_hit=False, parallel=True,
                               batch_points=os.environ.get('CLOUD_BREATHING_DISPLAY_BATCH_POINTS', '1024'))
                parallel_future = executor.submit(
                    _compute_external_patch, case, vertices_snapshot, execute_job.get('_cancel_token'))

        try:
            payload = execute(execute_job, backend, fresh=fresh, progress_prefix=progress_prefix)
        except BaseException:
            if parallel_future is not None:
                parallel_future.cancel()
                if not parallel_future.cancelled():
                    try:
                        parallel_future.result()
                    except BaseException:
                        pass
            raise
        if isinstance(payload, dict) and payload.get('case') is not None and payload.get('vertices') is not None:
            case = payload['case']
            cache = getattr(case, '_display_patch_cache', {})
            parallel_result = None
            if parallel_future is not None:
                try:
                    result, metrics, completed_ns = parallel_future.result()
                except BaseException:
                    raise
                if (case is parallel_case
                        and np.asarray(payload['vertices']).tobytes() == parallel_key
                        and trace is not None
                        and trace.geometry_id == geometry_identity(payload['vertices'])
                        and trace.revision == execute_job.get('revision')):
                    cache[parallel_key] = result
                    parallel_result = (metrics, completed_ns)
                    trace.mark('external_geometry_complete', at_ns=completed_ns,
                               cache_hit=False, parallel=True, **metrics)
                elif (case is parallel_case
                      and np.asarray(payload['vertices']).tobytes() == parallel_key):
                    cache[parallel_key] = result
                elif trace is not None:
                    trace.mark('external_geometry_candidate_discarded',
                               parallel_geometry_id=hashlib.sha256(parallel_key).hexdigest())
            plans = [payload] + list(payload.get('alternatives', []))
            for plan in plans:
                checkpoint()
                key = np.asarray(plan['vertices']).tobytes()
                plan_trace = trace if plan is payload else None
                cache_hit = key in cache
                used_parallel = plan is payload and parallel_result is not None and key == parallel_key
                if key not in cache:
                    if not used_parallel:
                        if plan_trace is not None:
                            plan_trace.mark('external_geometry_start', cache_hit=False, parallel=False,
                                            batch_points=os.environ.get('CLOUD_BREATHING_DISPLAY_BATCH_POINTS', '1024'))
                        result, metrics, completed_ns = _compute_external_patch(
                            case, plan['vertices'], execute_job.get('_cancel_token'))
                        cache[key] = result
                        if plan_trace is not None:
                            plan_trace.mark('external_geometry_complete', at_ns=completed_ns,
                                            cache_hit=False, parallel=False, **metrics)
                elif plan_trace is not None and not used_parallel:
                    plan_trace.mark('external_geometry_start', cache_hit=True, parallel=False,
                                    batch_points=os.environ.get('CLOUD_BREATHING_DISPLAY_BATCH_POINTS', '1024'))
                    plan_trace.mark('external_geometry_complete', cache_hit=True, parallel=False,
                                    elapsed_ms=0., exterior_triangles=len(cache[key][1]),
                                    bvh_cached_arrays=sum(index._display_contact_arrays is not None
                                        for _, _, index in getattr(case, '_display_lobe_indices', [])))
                # Touch reused entries too, so eviction cannot drop a current
                # candidate just because it was first computed long ago.
                cache[key] = cache.pop(key)
            # Keep all current candidate surfaces and a bounded recent history.
            while len(cache) > max(8, len(plans)):
                del cache[next(iter(cache))]
            audits = getattr(case, '_display_patch_audits', {})
            case._display_patch_audits = {key: audits[key] for key in cache if key in audits}
            case._display_patch_cache = cache
            key = np.asarray(payload['vertices']).tobytes()
            case._display_external_patch = (key, cache[key])
        return payload
    worker._execute = reused


class _LobeTaskSignals(QObject):
    finished = Signal(int, object, str)


class _PlPreloader(QObject):
    """Load the bitstream at startup on the planning thread, before any plan."""
    finished = Signal(str)

    def __init__(self, worker):
        super().__init__()
        self.worker = worker

    @Slot()
    def run(self):
        try:
            self.worker.pl.prepare()
        except Exception as exc:
            self.finished.emit(str(exc) or type(exc).__name__)
        else:
            self.finished.emit('')


class _LobeTask(QRunnable):
    """Read lobe STLs and place lesions off the GUI thread."""

    def __init__(self, revision, cancel, job, signals):
        super().__init__()
        self.revision, self.cancel, self.job, self.signals = revision, cancel, job, signals

    @Slot()
    def run(self):
        try:
            with cancellation_scope(self.cancel):
                lesions = self.job['lesions']
                tumor = self.job.get('tumor')
                if tumor and any(item.get('points_src') is None for item in lesions):
                    from .lesion_components import inspect_components
                    rows = {row['id']: row for row in
                            inspect_components(Path(self.job['directory']) / tumor)['components']}
                    lesions = [dict(item, points_src=ref.all_points(rows[item['id']]['triangles']))
                               if item.get('points_src') is None and item['id'] in rows else item
                               for item in lesions]
                located = locate_lobes(self.job['directory'], self.job['files'],
                                       lesions, self.job['spacing'])
        except PlanningCancelled:
            self.signals.finished.emit(self.revision, None, '')
        except Exception as exc:
            self.signals.finished.emit(self.revision, None, str(exc) or type(exc).__name__)
        else:
            self.signals.finished.emit(self.revision, located, '')


class InteractivePlannerController(ReleasePlanner):
    vertexGestureChanged = Signal()
    highlightChanged = Signal()
    vertexReleaseRequested = Signal()
    resectionChanged = Signal()
    plPreloadRequested = Signal()

    def __init__(self, viewer):
        self._vertex_gesture = None
        self._gesture_dirty = False
        self._release_detected_ns = None
        self._pending_drag_trace = None
        self._active_drag_trace = None
        self._drag_frame_window = None
        self._watched_drag_trace = None
        self._drag_presentation_logged = False
        self._highlight_lobe = ''
        self._resections = []
        self._wedge_index_map = {}
        self._lobe_revision = 0
        self._lobe_task_active = False
        super().__init__(viewer)
        self._lobe_pool = QThreadPool(self)
        self._lobe_pool.setMaxThreadCount(1)
        self._lobe_signals = _LobeTaskSignals(self)
        self._lobe_signals.finished.connect(self._lobe_task_finished)
        install_case_reuse(self._worker)
        self._pl_preloader = _PlPreloader(self._worker)
        self._pl_preloader.moveToThread(self._thread)
        self._pl_preloader.finished.connect(self._pl_preloaded)
        self.plPreloadRequested.connect(self._pl_preloader.run)
        if self._backend == 'pl' and self._worker.pl.configured:
            self._status = '正在加载 PL 比特流...'
            self.plPreloadRequested.emit()
        app = QGuiApplication.instance()
        if app is not None:
            app.installEventFilter(self)

    @Slot(str)
    def _pl_preloaded(self, error):
        if self._busy:
            return
        self._status = ('PL 比特流加载失败：' + error) if error else 'PL 比特流已加载'
        self.changed.emit()

    def eventFilter(self, obj, event):
        if self._vertex_gesture is not None:
            kind = event.type()
            release = (kind == QEvent.MouseButtonRelease and event.button() == Qt.LeftButton)
            missing = kind == QEvent.MouseMove and not (event.buttons() & Qt.LeftButton)
            if release or missing or kind in (QEvent.ApplicationDeactivate, QEvent.WindowDeactivate):
                gesture = self._vertex_gesture
                if getattr(self, '_release_detected_ns', None) is None:
                    self._release_detected_ns = time.perf_counter_ns()
                    self._release_event_kind = int(kind)
                # Deliver after the MouseArea has flushed its release position.
                def finish():
                    if self._vertex_gesture is gesture:
                        self.vertexReleaseRequested.emit()
                        self.endVertexDrag()
                QTimer.singleShot(0, finish)
        return False

    vertexEditing = Property(bool, lambda s: s._vertex_gesture is not None,
                             notify=vertexGestureChanged)
    highlightLobe = Property(str, lambda s: s._highlight_lobe, notify=highlightChanged)
    # Lobectomy for lesions >= 15 mm; the wedge planner keeps the smaller ones.
    resectionPlans = Property('QVariantList', lambda s: s._resections, notify=resectionChanged)
    resectionLobeNames = Property('QStringList', lambda s: [Path(name).name for plan in s._resections for name in plan['files']],
                                  notify=resectionChanged)
    @staticmethod
    def _short_lobe(label):
        return label.replace('肺', '')

    def _resection_summary(self):
        parts = [self._short_lobe(plan['label']) + '肺叶切除' for plan in self._resections]
        if self._vertices is not None and self._preview_case is not None:
            try:
                name = target_lobe(self._preview_case)[0]
                if name:
                    parts.append(self._short_lobe(lobe_label(name)) + '楔形切')
            except Exception:
                logging.getLogger(__name__).exception('wedge lobe label failed')
        return '、'.join(parts)

    resectionSummary = Property(str, _resection_summary, notify=resectionChanged)
    lobectomyOnly = Property(bool, lambda s: bool(s._resections) and s._vertices is None, notify=resectionChanged)
    lobectomyThresholdMm = Property(float, lambda s: LOBECTOMY_MIN_DIAMETER_MM, constant=True)

    def _clear_resections(self):
        if self._lobe_task_active and self._active_cancel is not None:
            self._active_cancel.set()  # The STL or lesion selection changed under the task.
        self._lobe_revision += 1
        self._wedge_index_map = {}
        if self._resections:
            self._resections = []
            self.resectionChanged.emit()

    def _catalog_points(self, identifier):
        """Lesion vertices from the worker's cached catalog, so the lobe task need not re-read the STL."""
        catalog = getattr(getattr(self, '_worker', None), '_component_catalog', None)
        row = next((r for r in (catalog or {}).get('components', []) if r['id'] == identifier), None)
        return ref.all_points(row['triangles']) if row is not None else None

    def _selected_lesions(self):
        """Selected catalog rows with their index and maximum diameter in mm."""
        spacing = self._ct_spacing()
        chosen = [row for row in self._lesion_components if row['id'] in set(self._component_ids)]
        typed = float(self._params.get('lesionDiameter', 0.))
        lesions = []
        for index, row in enumerate(chosen, 1):
            # One lesion: the field holds its diameter (auto-filled, or the doctor's value).
            diameter = typed if len(chosen) == 1 and typed > 0. else component_diameter_mm(
                row, spacing[0] if spacing else None)
            lesions.append(dict(id=row['id'], index=index, diameter_mm=diameter,
                                volume_cm3=float(row.get('volume_cm3', 0.)), center_src=row['center_mm']))
        return lesions

    @Slot()
    def autoPlan(self):
        if self._busy or self._stopping:
            return
        self._clear_resections()
        lesions = self._selected_lesions()
        if not any(needs_lobectomy(lesion['diameter_mm']) for lesion in lesions):
            ReleasePlanner.autoPlan(self)
            return
        if not self.ready:
            self._status = '请加载 STL 并选择至少一个肺表面与一个病灶'
            self.changed.emit()
            return
        spacing = self._ct_spacing()
        if not self._ct_ready_for_operation() or spacing is None:
            self._status = '请先在二维阅片中导入并加载 CT，获取物理标尺后再量化分析'
            self.changed.emit()
            return
        self._timer.stop()
        self._invalidate()
        self._lobe_revision += 1
        self._busy, self._lobe_task_active = True, True
        self._active_cancel = Event()
        self._lobe_lesions = lesions
        self._status = f'病灶 ≥{LOBECTOMY_MIN_DIAMETER_MM:g} mm，正在判断所在肺叶...'
        job = dict(directory=self._directory, files=list(self._files), tumor=getattr(self, '_tumor', ''),
                   lesions=[dict(id=item['id'], index=item['index'], center_src=item['center_src'],
                                 points_src=InteractivePlannerController._catalog_points(self, item['id'])) for item in lesions],
                   spacing=spacing[0])
        self._lobe_pool.start(_LobeTask(self._lobe_revision, self._active_cancel, job, self._lobe_signals))
        self.changed.emit()

    @Slot(int, object, str)
    def _lobe_task_finished(self, revision, located, error):
        if not self._lobe_task_active:
            return
        self._lobe_task_active = False
        stopped = self._stopping or revision != self._lobe_revision
        self._busy, self._stopping, self._active_cancel = False, False, None
        if stopped or (located is None and not error):
            self._status = '计算已停止，可调整参数后重新计算'
            self.changed.emit()
            return
        if error:
            self._status = '肺叶切除规划失败：' + error
            self.changed.emit()
            return
        plans, wedge, covered = split_lesions(self._lobe_lesions, located)
        self._resections = plans
        self.resectionChanged.emit()
        labels = '、'.join(plan['label'] for plan in plans)
        if not wedge:
            self._status = f'肺叶切除：{labels}；无需楔形切除'
            self.changed.emit()
            return
        # Plan the remaining <15 mm lesions with the unchanged wedge planner.
        self._wedge_index_map = {lesion['id']: lesion['index'] for lesion in self._lobe_lesions
                                 if lesion['id'] in wedge}
        selected, count, diameter = list(self._component_ids), self._lesion_count, self._params.get('lesionDiameter', 0.)
        self._component_ids, self._lesion_count = list(wedge), len(wedge)
        # Same rule as the release planner: one lesion carries its own diameter, several carry none.
        self._params['lesionDiameter'] = (next(lesion['diameter_mm'] for lesion in self._lobe_lesions
                                               if lesion['id'] == wedge[0]) if len(wedge) == 1 else 0.)
        try:
            ReleasePlanner.autoPlan(self)
        finally:
            self._component_ids, self._lesion_count = selected, count
            self._params['lesionDiameter'] = diameter
        if self._busy:
            self._status = f'肺叶切除：{labels}；正在规划 {len(wedge)} 个 <{LOBECTOMY_MIN_DIAMETER_MM:g} mm 病灶的楔形切除...'
        self.changed.emit()

    def _completed(self, payload):
        if self._wedge_index_map and payload.get('revision') == self._revision:
            for item in payload.get('lesion_plans') or [payload]:
                index = self._wedge_index_map.get(item['result'].get('lesion_component_id'))
                if index is not None:
                    item['result']['lesion_index'] = index
        super()._completed(payload)
        self.resectionChanged.emit()
        if self._resections:
            labels = '、'.join(plan['label'] for plan in self._resections)
            self._status = f'肺叶切除：{labels} · 楔形切除：{self._status}'
            self.resectionChanged.emit()
            self.changed.emit()

    @Slot()
    def recompute(self):
        if self._resections and self._vertices is None:
            # A lobectomy has no parameters to recompute; re-run auto planning.
            self._timer.stop()
            return
        super().recompute()

    def shutdown(self):
        super().shutdown()
        self._lobe_pool.waitForDone()

    def _draw(self, update_surface=False, preview_path=True):
        super()._draw(update_surface=False, preview_path=preview_path)
        if update_surface:
            surface = np.empty((0, 3, 3))
            name = ''
            dragging_wedge = self._parameter_dragging
            if not dragging_wedge and self._vertices is not None and self._preview_case is not None:
                key = np.asarray(self._vertices).tobytes()
                cached = getattr(self._preview_case, '_display_patch_cache', {}).get(key)
                if cached is not None:
                    name, surface = cached
                # Missing worker cache must never show internal interfaces.
            self._patch.setMesh(surface, np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale)
            if name != self._highlight_lobe:
                self._highlight_lobe = name
                self.highlightChanged.emit()

    def _invalidate(self):
        self._stop_drag_presentation_watch()
        self._vertex_gesture = None
        self._gesture_dirty = False
        self._clear_resections()
        super()._invalidate()
        self.vertexGestureChanged.emit()

    def _stop_drag_presentation_watch(self):
        window = getattr(self, '_drag_frame_window', None)
        if window is not None:
            try:
                window.frameSwapped.disconnect(self._on_drag_frame_swapped)
            except (RuntimeError, TypeError):
                pass
        self._drag_frame_window = None
        self._watched_drag_trace = None

    def _watch_drag_presentation(self, trace):
        app = QGuiApplication.instance()
        if app is None:
            return
        window = app.focusWindow()
        if window is None:
            window = next((candidate for candidate in app.topLevelWindows()
                          if candidate.isVisible()), None)
        if window is None or not hasattr(window, 'frameSwapped'):
            return
        self._stop_drag_presentation_watch()
        try:
            window.frameSwapped.connect(self._on_drag_frame_swapped,
                                        Qt.ConnectionType.QueuedConnection)
        except (RuntimeError, TypeError):
            return
        self._drag_frame_window = window
        self._watched_drag_trace = trace
        self._drag_presentation_logged = False

    @Slot()
    def _on_drag_frame_swapped(self):
        trace = self._watched_drag_trace
        if trace is None:
            self._stop_drag_presentation_watch()
            return
        events = trace.snapshot()['events']
        names = {event['event'] for event in events}
        if 'full_result_ready' not in names:
            return
        if (trace.revision != self._revision or self._vertices is None
                or trace.geometry_id != geometry_identity(self._vertices)):
            self._stop_drag_presentation_watch()
            return
        if 'first_qt_frame_swapped' not in names:
            trace.mark('first_qt_frame_swapped')
        if not self._drag_presentation_logged:
            trace.log_snapshot('first_qt_frame_swapped')
            self._drag_presentation_logged = True
        self._stop_drag_presentation_watch()

    def _edited(self):
        if self._vertex_gesture is not None and not self._gesture_dirty:
            active_cancel = getattr(self, '_active_cancel', None)
            if active_cancel is not None:
                active_cancel.set()
        super()._edited()
        if self._vertex_gesture is not None:
            self._timer.stop()
            self._gesture_dirty = True

    def _enqueue(self, mode):
        if self._vertex_gesture is not None:
            self._gesture_dirty = True
            return
        super()._enqueue(mode)

    def _source_ray(self, origin, end):
        center = np.asarray(self.viewer.sceneCenterMm)
        scale = self.viewer.sceneScale
        start = np.array([origin.x(), origin.y(), origin.z()])/scale + center
        finish = np.array([end.x(), end.y(), end.z()])/scale + center
        return start, finish-start

    @Slot(int, QVector3D, QVector3D, result=bool)
    def beginVertexDrag(self, index, origin, end):
        if self._params.get('planningModel') == 'plane_wedge':
            return False
        if self._vertices is None or not self._geometry_current or index not in (0, 1, 2):
            return False
        self._stop_drag_presentation_watch()
        normal = np.cross(self._vertices[1]-self._vertices[0], self._vertices[2]-self._vertices[0])
        length = np.linalg.norm(normal)
        if not np.isfinite(length) or length < 1e-9:
            return False
        normal /= length
        start, ray = self._source_ray(origin, end)
        denominator = float(np.dot(ray, normal))
        if abs(denominator) < np.linalg.norm(ray)*1e-5:
            return False
        anchor = self._vertices[0].copy()
        hit = start + ray*np.dot(anchor-start, normal)/denominator
        self._timer.stop()
        self._pending = None
        self._revision += 1  # Discard an older in-flight result, if any.
        self._release_detected_ns = None
        self._pending_drag_trace = None
        self._active_drag_trace = None
        self._vertex_gesture = (index, anchor, normal, self._vertices[index]-hit)
        self._gesture_dirty = False
        self.vertexGestureChanged.emit()
        return True

    @Slot(int, QVector3D, QVector3D)
    def dragVertex(self, index, origin, end):
        if self._vertex_gesture is None:
            return
        selected, anchor, normal, offset = self._vertex_gesture
        if selected != index:
            return
        start, ray = self._source_ray(origin, end)
        denominator = float(np.dot(ray, normal))
        if abs(denominator) < np.linalg.norm(ray)*1e-5:
            return
        point = start + ray*np.dot(anchor-start, normal)/denominator + offset
        candidate = self._vertices.copy()
        candidate[index] = point
        if (not np.isfinite(candidate).all()
                or np.dot(np.cross(candidate[1]-candidate[0], candidate[2]-candidate[0]), normal) <= 0
                or ref.tri_area(*map(tuple, candidate[:3])) < 100):
            return
        if np.allclose(candidate, self._vertices, rtol=0, atol=1e-7):
            return
        self._vertices = candidate
        self._params['baseArea'] = ref.tri_area(*map(tuple, candidate[:3]))/100
        self._edited()

    @Slot()
    def endVertexDrag(self):
        if self._vertex_gesture is None:
            return
        dirty = self._gesture_dirty
        self._vertex_gesture = None
        self._gesture_dirty = False
        self.vertexGestureChanged.emit()
        if dirty:
            released = self._release_detected_ns or time.perf_counter_ns()
            trace = DragTrace(self._revision, self._vertices, released)
            trace.mark('mouse_release', at_ns=released,
                       release_detection='application_event_filter',
                       event_type=getattr(self, '_release_event_kind', None))
            trace.mark('release_handler', release_detection='event_filter_deferred_until_qt_flush')
            self._pending_drag_trace = trace
            self._watch_drag_presentation(trace)
            trace.mark('recompute_submitted')
            self._timer.stop()
            self.recompute()


PlannerController = InteractivePlannerController
