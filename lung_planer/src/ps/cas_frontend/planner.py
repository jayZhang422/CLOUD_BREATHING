"""Native QML planner state, worker queue and interactive tetrahedron editing."""
import json
import hashlib
import logging
import os
import traceback
from datetime import datetime, timezone
from pathlib import Path
from time import perf_counter
from threading import Event

import numpy as np
from PySide6.QtCore import QObject, Property, QRunnable, QThread, QThreadPool, QTimer, Signal, Slot
from PySide6.QtGui import QVector3D
from PySide6.QtQuick3D import QQuick3DGeometry
from PySide6.QtWidgets import QFileDialog

from . import planner_reference as ref
from .planning_geometry import PlanningCase
from .planning_inputs import is_lung_surface, is_lesion, auto_select_target_lung
from .pl_metrics import PlMetrics
from .planning_run import make_case, run_case, diagnostics
from .lesion_components import inspect_components, selected_components
from .render_buffers import prepare_mesh
from .planning_cancel import checkpoint, cancellable_job, PlanningCancelled
from .drag_trace import geometry_identity
from .planning_constraints import (default_parameters, restore_parameters,
    margin_reference, constraint_report, LESION_TYPES, MARGIN_RULES, NUMERIC_LIMITS,
    WEDGE_SCHEMA)


def planning_case_identity(case):
    """Identify the exact selected lung and lesion geometry used by a plan."""
    digest = hashlib.sha256()
    spacing = getattr(case, 'ct_spacing', None)
    if spacing is None:
        spacing = (1., 1., 1.)
    digest.update(json.dumps(dict(lung_files=list(case.lung_files),
                                  tumor_file=case.tumor_file,
                                  ct_spacing=np.asarray(spacing, dtype=np.float64).tolist()),
                             sort_keys=True, separators=(',', ':')).encode('utf-8'))
    for values in (case.triangles, case.points):
        array = np.ascontiguousarray(values, dtype='<f8')
        digest.update(np.asarray(array.shape, dtype='<u8').tobytes())
        digest.update(memoryview(array).cast('B'))
    return digest.hexdigest()


class PlanGeometry(QQuick3DGeometry):
    def __init__(self, parent=None):
        super().__init__()
        if parent is not None:
            self.setParent(parent)
        self._prepared = None

    def setMesh(self, triangles, center, scale):
        self.setPrepared(prepare_mesh(triangles, center, scale))

    def setPrepared(self, prepared):
        if prepared is self._prepared:
            return
        self._prepared = prepared
        self.clear()
        if not prepared['data']:
            self.setBounds(QVector3D(), QVector3D())
            super().update()
            return
        self.setVertexData(prepared['data'])
        self.setStride(24)
        self.setPrimitiveType(QQuick3DGeometry.PrimitiveType.Triangles)
        self.addAttribute(QQuick3DGeometry.Attribute.Semantic.PositionSemantic, 0, QQuick3DGeometry.Attribute.ComponentType.F32Type)
        self.addAttribute(QQuick3DGeometry.Attribute.Semantic.NormalSemantic, 12, QQuick3DGeometry.Attribute.ComponentType.F32Type)
        self.setBounds(QVector3D(*prepared['minimum']), QVector3D(*prepared['maximum']))
        super().update()


class _WedgePreviewSignals(QObject):
    finished = Signal(int, object, object, str)


class _WedgePreviewTask(QRunnable):
    def __init__(self, generation, case, vertices, signals):
        super().__init__()
        self.generation = generation
        self.case = case
        self.vertices = vertices
        self.signals = signals

    @Slot()
    def run(self):
        try:
            surface, interior = self.case.preview_resection_surfaces(self.vertices)
        except Exception as exc:
            self.signals.finished.emit(self.generation, None, None, str(exc))
        else:
            self.signals.finished.emit(self.generation, surface, interior, '')


def _write_source_stl(path, meshes):
    """Write complete plan geometry in the STL/source coordinate frame."""
    triangles = [np.asarray(mesh, dtype=np.float64).reshape(-1, 3, 3)
                 for mesh in meshes if np.asarray(mesh).size]
    triangles = np.concatenate(triangles) if triangles else np.empty((0, 3, 3))
    if not len(triangles) or not np.isfinite(triangles).all():
        raise ValueError('规划 STL 几何为空或含非有限坐标')
    with path.open('w', encoding='ascii', newline='\n') as stream:
        stream.write('solid planning_result\n')
        for triangle in triangles:
            stream.write('facet normal 0 0 0\nouter loop\n')
            for point in triangle:
                stream.write('vertex %.17g %.17g %.17g\n' % tuple(point))
            stream.write('endloop\nendfacet\n')
        stream.write('endsolid planning_result\n')
    return len(triangles)


class PlanEdges(QQuick3DGeometry):
    def setEdges(self, vertices, center, scale):
        self.clear()
        if vertices is None:
            return
        pairs = ((0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3))
        points = np.asarray([vertices[i] for pair in pairs for i in pair], dtype='<f4')
        points = np.asarray((points - center) * scale, dtype='<f4')
        self.setVertexData(points.tobytes())
        self.setStride(12)
        self.setPrimitiveType(QQuick3DGeometry.PrimitiveType.Lines)
        self.addAttribute(QQuick3DGeometry.Attribute.Semantic.PositionSemantic, 0, QQuick3DGeometry.Attribute.ComponentType.F32Type)
        self.setBounds(QVector3D(*map(float, points.min(axis=0))), QVector3D(*map(float, points.max(axis=0))))
        super().update()

    def setSegments(self, segments, center, scale):
        """Upload line segments such as the three entry-to-apex paths."""
        self.clear()
        segments = np.asarray(segments, dtype=np.float32).reshape(-1, 2, 3)
        if not len(segments):
            return
        points = ((segments - center) * scale).reshape(-1, 3)
        self.setVertexData(np.asarray(points, dtype='<f4').tobytes())
        self.setStride(12)
        self.setPrimitiveType(QQuick3DGeometry.PrimitiveType.Lines)
        self.addAttribute(QQuick3DGeometry.Attribute.Semantic.PositionSemantic, 0, QQuick3DGeometry.Attribute.ComponentType.F32Type)
        self.setBounds(QVector3D(*map(float, points.min(axis=0))), QVector3D(*map(float, points.max(axis=0))))
        super().update()


class PlanningWorker(QObject):
    completed = Signal(object)
    cancelled = Signal(int)
    failed = Signal(int, str)
    progress = Signal(int, str)
    catalogCompleted = Signal(object)

    def __init__(self):
        super().__init__()
        self.case, self.key = None, None
        self.pl = PlMetrics(require_strict_pl=True)
        self._component_source, self._component_catalog = None, None
        self._lung_selection_key, self._lung_selection = None, None

    def _catalog(self, path, expected_sha=None):
        path = Path(path)
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if expected_sha and digest != expected_sha:
            raise ValueError('病灶 STL 已变化，请重新加载并选择病灶')
        key = str(path.resolve()), digest
        if key != self._component_source:
            self._component_catalog = inspect_components(path)
            self._component_source = key
        return self._component_catalog

    @Slot(object)
    def scanLesions(self, job):
        try:
            catalog = self._catalog(Path(job['directory']) / job['tumor'])
            rows, previews = [], {}
            for row in catalog['components']:
                rows.append({k: v for k, v in row.items() if k != 'triangles'})
                previews[row['id']] = prepare_mesh(np.asarray(ref.all_points(row['triangles'])).reshape(-1, 3, 3),
                    job['center'], job['scale'])
            self.catalogCompleted.emit(dict(signature=job['signature'], rows=rows,
                previews=previews, source_sha256=catalog['source_sha256']))
        except Exception as exc:
            self.catalogCompleted.emit(dict(signature=job['signature'], error=str(exc)))

    def _progress_callback(self, revision, prefix=''):
        def report(message):
            checkpoint()
            self.progress.emit(revision, f'{prefix} · {message}' if prefix else message)
        return report

    def _select_lung(self, job):
        """Pick the lesion-containing lung surface; the result is cached per case."""
        root = Path(job['directory'])
        stamps = tuple((name, (root / name).stat().st_mtime_ns, (root / name).stat().st_size)
                       for name in dict.fromkeys(list(job['lung']) + [job['tumor']]))
        ids = job.get('lesion_component_ids')
        key = (str(root), stamps, tuple(job['lung']), tuple(ids) if ids else None,
               tuple(job.get('ct_spacing') or ()))
        if key == self._lung_selection_key:
            selected = list(self._lung_selection)
        else:
            self._progress_callback(job['revision'])('正在判断病灶所在肺叶...')
            selected = auto_select_target_lung(
                job['directory'], list(job['lung']), job['tumor'],
                tumor_component_ids=list(ids) if job.get('lesion_source_sha256') and ids else None,
                ct_spacing=job.get('ct_spacing'))
            self._lung_selection_key, self._lung_selection = key, list(selected)
        if selected == list(job['lung']):
            return job
        return dict(job, lung=selected, lung_selection_policy='lesion-containing-surface')

    def _execute(self, job, backend, *, fresh=False, progress_prefix=''):
        checkpoint()
        trace = job.get('_drag_trace')
        if trace is not None:
            trace.mark('worker_started', worker_thread=QThread.currentThread().objectName())
        if job.get('lesion_source_sha256'):
            self._catalog(Path(job['directory']) / job['tumor'], job['lesion_source_sha256'])
        if job.get('lesion_component_ids') is not None and job.get('tumor_triangles') is None:
            catalog = self._catalog(Path(job['directory']) / job['tumor'], job.get('lesion_source_sha256'))
            rows = selected_components(catalog, job['lesion_component_ids'])
            if len(rows) != 1:
                raise ValueError('多个病灶请先运行自动规划，再选择病灶微调')
            row = rows[0]
            job = dict(job, tumor_triangles=row['triangles'], lesion_component_id=row['id'],
                lesion_source_rank=row['rank'], lesion_source_sha256=catalog['source_sha256'],
                lesion_index=1, lesion_count=1, lesion_volume_cm3=row['volume_cm3'])
        started = perf_counter()
        progress = self._progress_callback(job['revision'], progress_prefix)
        if backend == 'pl':
            if trace is not None:
                trace.mark('pl_prepare_start')
            progress('正在加载 PL 并检查 100 MHz 时钟，如出现系统授权请完成...')
            self.pl.prepare()
            if trace is not None:
                trace.mark('pl_prepare_complete')
        files = list(dict.fromkeys(job['lung'] + job.get('source_lung', job['lung'])
                                   + job.get('whole_lung', job.get('source_lung', job['lung']))
                                   + [job['tumor']]))
        stamps = tuple((name, (Path(job['directory']) / name).stat().st_mtime_ns,
                        (Path(job['directory']) / name).stat().st_size) for name in files)
        key = (job['directory'], stamps, backend, tuple(job.get('ct_spacing') or ()))
        build_case = (fresh or job.get('expected_case_identity') is not None
                      or job.get('tumor_triangles') is not None or key != self.key)
        if trace is not None:
            trace.mark('case_prepare_start', reused=not build_case)
        if build_case:
            progress('正在读取 STL 和准备规划数据...')
            case = make_case(job, backend, self.pl)
            if not fresh:
                self.case, self.key = case, key
        else:
            case = self.case
        expected_identity = job.get('expected_case_identity')
        case_identity = getattr(case, '_planning_case_identity', None)
        if case_identity is None:
            case_identity = planning_case_identity(case)
            case._planning_case_identity = case_identity
        if expected_identity is not None and case_identity != expected_identity:
            raise ValueError('所选 STL 几何与已保存规划不一致，请确认肺叶、病灶和 STL 文件')
        if backend == 'pl':
            checkpoint()
            self.pl.cache_mesh_image(case.mesh_image)
        setup_ms = (perf_counter() - started) * 1000.
        if trace is not None:
            trace.mark('case_prepare_complete', setup_ms=setup_ms,
                       case_triangles=len(case.triangles))
        payload = run_case(case, job, backend, self.pl, progress,
                           lambda: QThread.currentThread().isInterruptionRequested())
        if case_identity is not None:
            payload['planning_case_identity'] = case_identity
        if expected_identity is not None:
            payload['restored_plan'] = True
        payload['result'].update(setup_ms=setup_ms, job_ms=(perf_counter() - started) * 1000.,
                                 mode=job['mode'],
                                 lung_selection_policy=job.get('lung_selection_policy', 'explicit'),
                                 source_lung_files=job.get('source_lung', job.get('lung', [])))
        if job.get('lesion_index'):
            payload['result'].update(lesion_index=job['lesion_index'],
                                     lesion_count=job['lesion_count'],
                                     lesion_volume_cm3=job['lesion_volume_cm3'])
        for name in ('lesion_component_id', 'lesion_source_rank', 'lesion_source_sha256'):
            if job.get(name) is not None:
                payload['result'][name] = job[name]
        if trace is not None:
            payload['_drag_trace'] = trace
        identity = {name: payload['result'][name] for name in (
            'lesion_index', 'lesion_count', 'lesion_volume_cm3', 'lesion_component_id',
            'lesion_source_rank', 'lesion_source_sha256') if name in payload['result']}
        for alternative in payload.get('alternatives', []):
            alternative['result'].update(identity)
        logging.getLogger(__name__).warning('PLANNER_TIMING %s', json.dumps(
            diagnostics(payload['result']), ensure_ascii=False))
        return payload

    def _execute_multiple_lesions(self, job):
        catalog = self._catalog(Path(job['directory']) / job['tumor'], job.get('lesion_source_sha256'))
        chosen = selected_components(catalog, job.get('lesion_component_ids'), job.get('lesion_count', 1))
        count = len(chosen)
        if count > 1 and (job['params'].get('lesionType', 'unconfirmed') != 'unconfirmed'
                          or job['params'].get('lesionDiameter', 0.) > 0.
                          or job['params'].get('marginRule', 'manual') != 'manual'):
            raise ValueError('病灶类型和 CT 直径需逐病灶设置；请每次仅选择一个病灶进行参考规则规划')
        results = []
        for index, row in enumerate(chosen):
            if QThread.currentThread().isInterruptionRequested():
                raise RuntimeError('规划已取消')
            single = dict(job, tumor_triangles=row['triangles'], lesion_index=index + 1,
                lesion_count=count, lesion_volume_cm3=row['volume_cm3'],
                lesion_component_id=row['id'], lesion_source_rank=row['rank'],
                lesion_source_sha256=catalog['source_sha256'])
            payload = self._execute(single, job['backend'], fresh=True,
                                    progress_prefix=f'病灶 {index + 1}/{count}')
            results.append(payload)
        selected = dict(results[0])
        selected['lesion_plans'] = results
        return selected

    @Slot(object)
    @cancellable_job
    def run(self, job):
        try:
            trace = job.get('_drag_trace')
            if trace is not None:
                trace.mark('worker_slot_started')
            if job.get('select_lung'):
                job = self._select_lung(job)
            payload = (self._execute_multiple_lesions(job)
                       if job['mode'] == 'auto' and (int(job.get('lesion_count', 1)) > 1
                                                   or job.get('lesion_component_ids') is not None)
                       else self._execute(job, job['backend']))
            payload['revision'] = job['revision']
            if job.get('select_lung'):
                payload['active_lung_files'] = list(job['lung'])
            trace = job.get('_drag_trace')
            if trace is not None:
                trace.mark('worker_result_complete',
                           pl_calls=int(payload['result'].get('metrics_totals', {}).get('calls', 0)),
                           pl_cycles=int(payload['result'].get('pl_cycles', 0)),
                           cpu_fallback_count=int(payload['result'].get('cpu_fallback_count', 0)),
                           strict_pl=bool(payload['result'].get('strict_pl', False)),
                           result_valid=bool(payload['result'].get('valid', False)))
                payload['_drag_trace'] = trace
            checkpoint()
            if trace is not None:
                trace.mark('worker_emit')
            self.completed.emit(payload)
        except PlanningCancelled:
            trace = job.get('_drag_trace')
            if trace is not None:
                trace.mark('worker_cancelled')
            self.cancelled.emit(job['revision'])
        except Exception as exc:
            # Existing search cancellation uses RuntimeError; keep it distinct
            # from a genuine hardware or geometry failure when stop was asked.
            if job.get('_cancel_token') is not None and job['_cancel_token'].is_set():
                trace = job.get('_drag_trace')
                if trace is not None:
                    trace.mark('worker_cancelled')
                self.cancelled.emit(job['revision'])
                return
            logging.getLogger(__name__).error('PLANNER_JOB_CONTEXT %s', json.dumps(dict(
                directory=job.get('directory'), lung=job.get('lung'), tumor=job.get('tumor'),
                mirror=job.get('mirror'), backend=job.get('backend'), params=job.get('params'),
                search=getattr(self.case, 'search_diagnostics', None)), ensure_ascii=False))
            logging.getLogger(__name__).exception('PLANNER_JOB_FAILED')
            try:
                failure_path = Path(__file__).resolve().parents[1] / 'data' / 'planner_failures.jsonl'
                failure_path.parent.mkdir(parents=True, exist_ok=True)
                with failure_path.open('a', encoding='utf-8') as stream:
                    stream.write(json.dumps(dict(
                        utc=datetime.now(timezone.utc).isoformat(), kind='worker_exception',
                        revision=int(job.get('revision', -1)), backend=job.get('backend'),
                        directory=job.get('directory'), lung=job.get('lung'), tumor=job.get('tumor'),
                        planning_model=job.get('params', {}).get('planningModel'),
                        message=str(exc), traceback=traceback.format_exc()), ensure_ascii=False) + '\n')
            except OSError:
                pass
            self.failed.emit(job['revision'], str(exc))


class PlannerController(QObject):
    changed = Signal()
    # Parameter/vertex bindings only.  Every full ``changed`` also emits it;
    # slider drags emit only this, so result-bound QML is not re-evaluated.
    parametersChanged = Signal()
    request = Signal(object)
    scanRequest = Signal(object)
    lesionCatalogChanged = Signal()
    lesionPreviewChanged = Signal()

    def __init__(self, stl_viewer):
        super().__init__()
        self.viewer = stl_viewer
        self._backend = os.environ.get('CLOUD_BREATHING_PLANNER_BACKEND', 'pl' if os.environ.get('CLOUD_BREATHING_KV260') == '1' else 'cpu')
        if self._backend not in ('pl', 'cpu'):
            raise ValueError('CLOUD_BREATHING_PLANNER_BACKEND must be pl or cpu')
        self._directory = ''
        self._files, self._lung, self._tumor = [], [], ''
        self._lung_user_modified = False
        self._active_lung_files = None
        self._params = default_parameters()
        self._apply_model_defaults()
        self._ct_calibration = {}
        self._result, self._vertices, self._points = {}, None, None
        self._plan_case_identity = None
        self._expected_case_identity = None
        self._alternatives, self._selected_candidate = [], -1
        self._lesion_plans, self._selected_lesion = [], -1
        self._lesion_count = 1
        self._lesion_components, self._component_ids = [], []
        self._catalog_previews, self._catalog_sha = {}, ''
        self._catalog_signature, self._catalog_busy, self._catalog_error = None, False, ''
        self._preview_component = ''
        self._lesion_preview = PlanGeometry(self)
        self._preview_case = None
        self._preview_generation = 0
        self._preview_inflight = False
        self._preview_pending = None
        self._preview_pool = QThreadPool(self)
        self._preview_pool.setMaxThreadCount(1)
        self._preview_signals = _WedgePreviewSignals(self)
        self._preview_signals.finished.connect(self._wedge_preview_completed)
        self.changed.connect(self.parametersChanged.emit)
        self._preview_timer = QTimer(self)
        self._preview_timer.setSingleShot(True)
        # Drag preview throttle, about 30 per second. One preview costs ~10 ms of
        # Manifold work off the GUI thread plus ~16 ms to publish on the board.
        self._preview_timer.setInterval(33)
        self._preview_timer.timeout.connect(self._start_wedge_preview_if_idle)
        self._geometry_current = False
        self._needs_refit = False
        self._preview_error = ''
        self._surface = np.empty((0, 3, 3))
        self._interior_data = np.empty((0, 3, 3))
        self._status = '加载 STL 后，选择肺叶与病灶，再计算规划'
        self._busy, self._pending, self._revision = False, None, 0
        self._parameter_dragging = False
        self._parameter_drag_changed = False
        self._drag_state = None
        self._stopping = False
        self._active_cancel = None
        self._stale = True
        self._tetra = PlanGeometry()
        self._patch = PlanGeometry()
        self._edges = PlanEdges()
        self._path = PlanEdges()
        self._interior = PlanGeometry()
        self._tetra.setParent(self)
        self._patch.setParent(self)
        self._edges.setParent(self)
        self._path.setParent(self)
        self._interior.setParent(self)
        self._thread = QThread(self)
        self._worker = PlanningWorker()
        self._worker.moveToThread(self._thread)
        self.request.connect(self._worker.run)
        self.scanRequest.connect(self._worker.scanLesions)
        self._worker.catalogCompleted.connect(self._catalog_completed)
        self._worker.completed.connect(self._completed)
        self._worker.failed.connect(self._failed)
        self._worker.cancelled.connect(self._cancelled)
        self._worker.progress.connect(self._progress)
        self._thread.finished.connect(self._worker.deleteLater)
        self._thread.start()
        self._timer = QTimer(self)
        self._timer.setSingleShot(True)
        self._timer.setInterval(160)
        self._timer.timeout.connect(self.recompute)
        self.viewer.rowsChanged.connect(self._loaded)
        self.viewer.loadStarted.connect(self._model_reset)
        self.viewer.statusChanged.connect(self.changed)

    executionBackend = Property(str, lambda s: s._backend, notify=changed)
    result = Property('QVariantMap', lambda s: {key: value for key, value in s._result.items()
        if not (key.endswith('_timings') and isinstance(value, list))}, notify=changed)
    candidates = Property('QVariantList', lambda s: [dict(
        label=f"方案 {i + 1} · {item['result']['resection_volume_cm3']:.2f} cm³ · "
              f"切面 {item['result']['cut_area_cm2']:.2f} cm²")
        for i, item in enumerate(s._alternatives)], notify=changed)
    selectedCandidate = Property(int, lambda s: s._selected_candidate, notify=changed)
    parameters = Property('QVariantMap', lambda s: s._params, notify=parametersChanged)
    ctReady = Property(bool, lambda s: bool(s._ct_calibration.get('pixel_spacing_mm')) and bool(s._ct_calibration.get('slice_spacing_mm', s._ct_calibration.get('slice_thickness_mm'))), notify=changed)
    ctCalibration = Property('QVariantMap', lambda s: dict(s._ct_calibration), notify=changed)
    planningModel = Property(str, lambda s: 'plane_wedge', notify=changed)
    # Vertex handles belonged to the removed tetrahedron models; the wedge has none.
    vertexHandlesAvailable = Property(bool, lambda s: False, notify=changed)
    marginReference = Property('QVariantMap', lambda s: margin_reference(s._params), notify=changed)
    status = Property(str, lambda s: s._status, notify=changed)
    busy = Property(bool, lambda s: s._busy, notify=changed)
    stopping = Property(bool, lambda s: s._stopping, notify=changed)
    metricsPending = Property(bool, lambda s: s._stale, notify=changed)
    hasPlan = Property(bool, lambda s: s._vertices is not None, notify=changed)
    geometryCurrent = Property(bool, lambda s: s._geometry_current, notify=changed)
    planningSurfaceVisible = Property(bool,
        lambda s: s._geometry_current and not s._parameter_dragging, notify=changed)
    ready = Property(bool, lambda s: bool(s._directory and s._lung and s._tumor)
        and not s.viewer.busy and not s._catalog_busy
        and (bool(s._component_ids) if s._catalog_signature is not None else True), notify=changed)
    directory = Property(str, lambda s: s._directory, notify=changed)
    files = Property('QStringList', lambda s: s._files, notify=changed)
    lungFiles = Property('QStringList', lambda s: s._lung, notify=changed)
    tumorFile = Property(str, lambda s: s._tumor, notify=changed)
    tetraGeometry = Property(QObject, lambda s: s._tetra, constant=True)
    surfaceGeometry = Property(QObject, lambda s: s._patch, constant=True)
    edgeGeometry = Property(QObject, lambda s: s._edges, constant=True)
    pathGeometry = Property(QObject, lambda s: s._path, constant=True)
    interiorTetraGeometry = Property(QObject, lambda s: s._interior, constant=True)
    lesionPreviewGeometry = Property(QObject, lambda s: s._lesion_preview, constant=True)
    lesionPreviewVisible = Property(bool, lambda s: bool(s._preview_component), notify=lesionPreviewChanged)
    previewComponentId = Property(str, lambda s: s._preview_component, notify=lesionPreviewChanged)
    lesionCatalogBusy = Property(bool, lambda s: s._catalog_busy, notify=lesionCatalogChanged)
    lesionCatalogStatus = Property(str, lambda s: ('正在识别病灶连通块…' if s._catalog_busy else
        s._catalog_error or f'识别 {len(s._lesion_components)} 个连通块，已选择 {len(s._component_ids)} 个。请定位确认小连通块。'), notify=lesionCatalogChanged)

    @Property('QVariantList', notify=lesionCatalogChanged)
    def lesionComponents(self):
        selected = set(self._component_ids)
        return [dict(row, selected=row['id'] in selected) for row in self._lesion_components]

    @Property('QVariantList', notify=parametersChanged)
    def sceneVertices(self):
        if self._vertices is None:
            return []
        center = np.asarray(self.viewer.sceneCenterMm)
        return [QVector3D(*map(float, p)) for p in (self._vertices - center) * self.viewer.sceneScale]

    lesionCount = Property(int, lambda s: s._lesion_count, notify=changed)
    lesionPlans = Property('QVariantList', lambda s: [dict(
        label=f"病灶 {item['result']['lesion_index']} · {item['result']['lesion_volume_cm3']:.2f} cm³ · "
              + (f"连通块 {item['result']['lesion_source_rank']} · " if item['result'].get('lesion_source_rank') else '')
              + f"{item['result'].get('resection_volume_cm3', 0.):.2f} cm³切除")
        for item in s._lesion_plans], notify=changed)
    selectedLesion = Property(int, lambda s: s._selected_lesion, notify=changed)

    def _draw(self, update_surface=False, preview_path=True):
        center = np.asarray(self.viewer.sceneCenterMm)
        scale = self.viewer.sceneScale
        # Auxiliary caps/ridge endpoints are outside the lung; display only
        # physical in-lung cut surfaces, never the numerical container.
        self._tetra.clear()
        self._edges.clear()
        self._tetra.update()
        self._edges.update()
        if update_surface:
            self._patch.setMesh(self._surface, center, scale)
        if self._vertices is None:
            self._path.setSegments([], center, scale)
            self._interior.setMesh([], center, scale)

    @Slot()
    def _invalidate(self):
        self._alternatives, self._selected_candidate = [], -1
        self._lesion_plans, self._selected_lesion = [], -1
        self._plan_case_identity = None
        self._expected_case_identity = None
        self._revision += 1
        self._timer.stop()
        self._preview_generation += 1
        self._preview_pending = None
        self._preview_timer.stop()
        self._pending = None
        self._vertices, self._points, self._result = None, None, {}
        self._preview_case = None
        self._geometry_current, self._needs_refit, self._preview_error = False, False, ''
        self._surface = np.empty((0, 3, 3))
        self._interior_data = np.empty((0, 3, 3))
        self._stale = True
        self._draw(update_surface=True)
        self.changed.emit()

    @Slot()
    def _model_reset(self):
        self._invalidate()
        self._directory, self._files, self._lung, self._tumor = '', [], [], ''
        self._lung_user_modified = False
        self._active_lung_files = None
        self._catalog_signature = None
        self._lesion_components, self._component_ids = [], []
        self._catalog_previews, self._catalog_sha = {}, ''
        self._catalog_busy, self._catalog_error = False, ''
        self._preview_component = ''
        self._lesion_preview.setMesh([], np.zeros(3), 1.)
        self.lesionCatalogChanged.emit()
        self.lesionPreviewChanged.emit()
        self.changed.emit()

    @Slot()
    def _loaded(self):
        self._invalidate()
        self._directory = self.viewer.directory
        root = Path(self._directory)
        self._files = sorted(p.relative_to(root).as_posix() for p in root.rglob('*') if p.suffix.lower() == '.stl')
        self._lung = [name for name in self._files if is_lung_surface(name)]
        self._lung_user_modified = False
        self._active_lung_files = None
        tumors = [name for name in self._files if is_lesion(name)]
        self._tumor = tumors[0] if tumors else ''
        self._lesion_count = 1
        self._params['baseArea'] = 0.
        self._params.update(lesionType='unconfirmed', marginRule='manual', lesionDiameter=0.)
        self._status = '请选择肺与病灶并点击自动规划；坐标不重叠时请核对肺侧及配准设置'
        self._scan_lesions()
        self.changed.emit()

    def _scan_lesions(self):
        self._lesion_components, self._component_ids = [], []
        self._catalog_previews, self._catalog_sha, self._catalog_error = {}, '', ''
        self._preview_component = ''
        self._lesion_preview.setMesh([], np.zeros(3), 1.)
        self.lesionPreviewChanged.emit()
        self._catalog_signature = (self._directory, self._tumor, self._revision)
        self._catalog_busy = bool(self._directory and self._tumor)
        self.lesionCatalogChanged.emit()
        if self._catalog_busy:
            self.scanRequest.emit(dict(signature=self._catalog_signature, directory=self._directory,
                tumor=self._tumor, center=list(self.viewer.sceneCenterMm), scale=self.viewer.sceneScale))

    @Slot(object)
    def _catalog_completed(self, payload):
        if payload['signature'] != self._catalog_signature:
            return
        self._catalog_busy = False
        self._catalog_error = payload.get('error', '')
        self._lesion_components = payload.get('rows', [])
        self._catalog_previews = payload.get('previews', {})
        self._catalog_sha = payload.get('source_sha256', '')
        self._component_ids = [row['id'] for row in self._lesion_components[:self._lesion_count]]
        self._lesion_count = len(self._component_ids)
        self._fill_lesion_diameter()
        if not self._lesion_components and not self._catalog_error:
            self._catalog_error = '未识别到有效病灶连通块，请检查 STL'
        self.lesionCatalogChanged.emit(); self.changed.emit()

    @Slot(str, bool)
    def setLesionComponentSelected(self, identifier, selected):
        if self._busy or self._catalog_busy or identifier not in self._catalog_previews:
            return
        identifiers = set(self._component_ids)
        if selected:
            identifiers.add(identifier)
        else:
            identifiers.discard(identifier)
        chosen = [row['id'] for row in self._lesion_components if row['id'] in identifiers]
        if chosen == self._component_ids:
            return
        self._component_ids, self._lesion_count = chosen, len(chosen)
        self._params.update(lesionType='unconfirmed', marginRule='manual', lesionDiameter=0.)
        self._fill_lesion_diameter()
        self._invalidate()
        self.lesionCatalogChanged.emit()

    @Slot(str)
    def previewLesionComponent(self, identifier):
        if identifier and identifier not in self._catalog_previews:
            return
        self._preview_component = '' if identifier == self._preview_component else identifier
        if self._preview_component:
            self._lesion_preview.setPrepared(self._catalog_previews[self._preview_component])
        else:
            self._lesion_preview.setMesh([], np.zeros(3), 1.)
        self.lesionPreviewChanged.emit()

    @Slot(str)
    def setTumorFile(self, name):
        if name in self._files and name != self._tumor:
            self._tumor = name
            self._params.update(lesionType='unconfirmed', marginRule='manual', lesionDiameter=0.)
            self._invalidate()
            self._scan_lesions()

    @Slot(int)
    def setLesionCount(self, count):
        count = max(1, min(10, int(count)))
        if count != self._lesion_count:
            self._lesion_count = count
            self._params.update(lesionType='unconfirmed', marginRule='manual', lesionDiameter=0.)
            if self._lesion_components:
                self._component_ids = [row['id'] for row in self._lesion_components[:count]]
                self._lesion_count = len(self._component_ids)
            self._fill_lesion_diameter()
            self._invalidate()
            self.lesionCatalogChanged.emit()

    @Slot(str, bool)
    def setLungFile(self, name, selected):
        if name not in self._files:
            return
        selected_names = set(self._lung)
        if selected:
            selected_names.add(name)
        else:
            selected_names.discard(name)
        self._lung = sorted(selected_names)
        self._lung_user_modified = True
        self._active_lung_files = None
        self._invalidate()

    def _edited(self):
        self._alternatives, self._selected_candidate = [], -1
        self._revision += 1  # Reject in-flight calculations immediately.
        self._stale = True
        if self._preview_case is not None:
            self._update_wedge_preview()
        self._status = (self._preview_error + '；当前参数尚未生成有效几何' if self._preview_error else
                        '范围预览 · 松开鼠标后计算指标' if self._parameter_dragging else
                        '正在更新面积、切除体积和肺外校验...')
        self._draw(update_surface=True)
        self._emit_drag_update()
        if self._parameter_dragging:
            self._parameter_drag_changed = True
        else:
            self._timer.start()

    def _emit_drag_update(self):
        """During a drag, re-evaluate result-bound QML only when its inputs change."""
        if not self._parameter_dragging:
            self.changed.emit()
            return
        state = (self._status, self._preview_error, self._vertices is None,
                 self._geometry_current, self._stale, self._busy, id(self._result))
        if state != self._drag_state:
            self._drag_state = state
            self.changed.emit()
        else:
            self.parametersChanged.emit()

    @Slot(str)
    def beginParameterEdit(self, name):
        if self._busy or self._parameter_dragging:
            return
        self._parameter_dragging = True
        self._parameter_drag_changed = False
        self._drag_state = None
        self._preview_generation += 1
        self._preview_pending = None
        self._preview_timer.stop()
        self._timer.stop()
        self._patch.setMesh([], np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale)
        self._interior_data = np.empty((0, 3, 3))
        self._interior.setMesh([], np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale)
        if getattr(self, '_highlight_lobe', None):
            self._highlight_lobe = ''
            signal = getattr(self, 'highlightChanged', None)
            if signal is not None:
                signal.emit()
        self.changed.emit()

    @Slot(str)
    def endParameterEdit(self, name):
        if not self._parameter_dragging:
            return
        changed = self._parameter_drag_changed
        self._parameter_dragging = False
        self._parameter_drag_changed = False
        self._preview_generation += 1
        self._preview_pending = None
        self._preview_timer.stop()
        if changed:
            self._status = '正在更新面积、切除体积和肺外校验...'
            self._timer.start()
        self.changed.emit()

    def _update_wedge_preview(self):
        """Queue a latest-only exact mesh preview without blocking the GUI."""
        from .planning_models import build_region
        center, scale = np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale
        try:
            physical_vertices = build_region(self._preview_case, self._params)
            to_source = getattr(self._preview_case, 'to_source_vertices', lambda value: value)
            vertices = to_source(physical_vertices)
        except (ValueError, np.linalg.LinAlgError) as exc:
            self._vertices = None
            self._surface = np.empty((0, 3, 3))
            self._preview_error = '当前参数无法生成切除范围预览：' + str(exc)
            self._path.setSegments([], center, scale)
            self._interior.setMesh([], center, scale)
            return False
        self._vertices = np.asarray(vertices, dtype=np.float64).copy()
        self._surface = np.empty((0, 3, 3))
        self._interior_data = np.empty((0, 3, 3))
        self._preview_error = ''
        self._path.setSegments([], center, scale)
        if not self._parameter_dragging:
            self._interior.setMesh([], center, scale)
            return True
        # While dragging, the last computed cut face stays on screen until the
        # newest pose replaces it, so the preview follows the slider.
        self._preview_generation += 1
        self._preview_pending = (self._preview_generation, self._preview_case,
                                 np.asarray(physical_vertices, dtype=np.float64).copy())
        # Throttle, not debounce: a continuous drag still refreshes every
        # interval; completion immediately starts the newest pending pose.
        if not self._preview_inflight and not self._preview_timer.isActive():
            self._preview_timer.start()
        return True

    def _start_wedge_preview_if_idle(self):
        if self._preview_inflight or self._preview_pending is None:
            return
        generation, case, vertices = self._preview_pending
        self._preview_pending = None
        self._preview_inflight = True
        self._preview_pool.start(_WedgePreviewTask(
            generation, case, vertices, self._preview_signals))

    @Slot(int, object, object, str)
    def _wedge_preview_completed(self, generation, surface, interior, error):
        self._preview_inflight = False
        if generation == self._preview_generation and self._parameter_dragging:
            if error:
                self._preview_error = '切除范围预览失败：' + error
            else:
                to_source = getattr(self._preview_case, 'to_source_vertices', lambda value: value)
                self._surface = to_source(surface)
                self._interior_data = to_source(interior)
                self._interior.setMesh(self._interior_data,
                    np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale)
                self._preview_error = ''
            self._emit_drag_update()
        if (self._parameter_dragging and self._preview_pending is not None
                and self._preview_pending[0] == self._preview_generation):
            self._start_wedge_preview_if_idle()

    @Slot(str, float)
    def setParameter(self, name, value):
        limits = dict(NUMERIC_LIMITS, wedgeAngle=(20.,160.), rotation=(0., 360.))
        if name not in limits or not np.isfinite(value):
            return
        value = min(limits[name][1], max(limits[name][0], value))
        if name == 'lesionDiameter':
            self._set_reference_parameter(name, float(value))
            return
        previous = self._params.get(name, value)
        if abs(previous - value) < 1e-8:
            return
        self._params[name] = float(value)
        if name == 'wedgeAngle':
            self._params['cutTilts'] = [value / 2.] * 2
        self._needs_refit, self._geometry_current = True, False
        self._edited()

    def _set_reference_parameter(self, name, value):
        """Metadata edits do not re-run geometry or claim clinical approval."""
        if self._busy or self._params.get(name) == value:
            return
        self._params[name] = value
        fields = {key: self._params.get(key) for key in
                  ('lesionType', 'marginRule', 'lesionDiameter')}
        for item in self._alternatives:
            item['params'].update(fields)
            item['result'].update(constraint_report(item['params'],
                item['result'].get('tumor_margin_mm', 0.), item['result'].get('valid', False)))
        if self._result:
            self._result.update(constraint_report(self._params,
                self._result.get('tumor_margin_mm', 0.), self._result.get('valid', False)))
        if self._lesion_plans and 0 <= self._selected_lesion < len(self._lesion_plans):
            self._lesion_plans[self._selected_lesion]['params'].update(fields)
            self._lesion_plans[self._selected_lesion]['result'] = dict(self._result)
        self.changed.emit()
        # Type, diameter or rule changed: the rule's reference defines the target.
        self._sync_margin_to_rule()

    def _auto_lesion_diameter(self):
        """3D maximum diameter of the one selected lesion, in mm; 0 when unknown.

        Several selected lesions have no single diameter (types, diameters and
        rules are set per lesion), and without the CT scale STL units are not mm.
        """
        spacing = self._ct_spacing()
        if spacing is None or len(self._component_ids) != 1:
            return 0.
        row = next((r for r in self._lesion_components if r['id'] == self._component_ids[0]), None)
        size = float(row.get('max_diameter_src', 0.)) if row else 0.
        if not np.isfinite(size) or size <= 0.:
            return 0.
        return min(NUMERIC_LIMITS['lesionDiameter'][1], round(size * spacing[0], 1))

    def _fill_lesion_diameter(self):
        self._params['lesionDiameter'] = self._auto_lesion_diameter()

    def _sync_margin_to_rule(self):
        """Fill the cut-margin target from the selected rule; manual leaves it alone."""
        reference = margin_reference(self._params)
        if not reference['available']:
            return
        if self._vertices is None and not self._geometry_current:
            # No plan to re-fit yet: record the target without queueing a calculation.
            self._params['minClearance'] = float(reference['suggestedMm'])
            self.changed.emit()
        else:
            self.setParameter('minClearance', reference['suggestedMm'])

    @Slot(str)
    def setLesionType(self, value):
        if value in LESION_TYPES:
            self._set_reference_parameter('lesionType', value)

    @Slot(str)
    def setMarginRule(self, value):
        if value in MARGIN_RULES:
            self._set_reference_parameter('marginRule', value)

    @Slot()
    def applyMarginReference(self):
        reference = margin_reference(self._params)
        if not self._busy and reference['available']:
            self.setParameter('minClearance', reference['suggestedMm'])

    def _ct_spacing(self):
        pixel = self._ct_calibration.get('pixel_spacing_mm', [])
        if not isinstance(pixel, (list, tuple)) or len(pixel) < 2:
            return None
        # These STL exports use an isotropic resampled voxel coordinate system.
        # CT PixelSpacing supplies its millimetre scale; native slice thickness
        # describes acquisition spacing and is not the STL z-coordinate unit.
        values = [float(pixel[0])] * 3
        if not np.isfinite(values).all() or min(values) <= 0:
            return None
        return values

    def _ct_ready_for_operation(self):
        # Real controllers always own _ct_calibration.  The permissive branch
        # keeps lightweight test doubles usable without weakening the desktop
        # controller's CT gate.
        if not hasattr(self, '_ct_calibration'):
            return True
        ready = getattr(self, 'ctReady', None)
        return bool(ready) if ready is not None else self._ct_spacing() is not None

    @Slot(object)
    def setCtCalibration(self, metadata):
        previous_spacing = self._ct_spacing()
        previous_auto_diameter = self._auto_lesion_diameter()
        metadata = dict(metadata or {})
        spacing = metadata.get('pixel_spacing_mm')
        z = metadata.get('slice_spacing_mm', metadata.get('slice_thickness_mm'))
        if not isinstance(spacing, (list, tuple)) or len(spacing) < 2 or z is None:
            self._ct_calibration = {}
        else:
            self._ct_calibration = dict(metadata)
        current_spacing = self._ct_spacing()
        if previous_spacing != current_spacing:
            self._timer.stop()
            self._pending = None
            self._revision += 1
            if self._active_cancel is not None:
                self._active_cancel.set()
            self._result = {}
            self._geometry_current = False
            self._stale = True
            self._preview_case = None
            self._plan_case_identity = None
            self._expected_case_identity = None
            self._status = ('CT 物理标尺已更新，请重新计算规划' if current_spacing is not None
                            else '请先在二维阅片中导入并加载 CT，获取物理标尺后再量化分析')
            # Only follow the new scale while the field still holds the value
            # this code filled in; a diameter the doctor typed is kept.
            if float(self._params.get('lesionDiameter', 0.)) in (0., previous_auto_diameter):
                self._params['lesionDiameter'] = self._auto_lesion_diameter()
        self.changed.emit()

    def _enqueue(self, mode):
        if self._stopping:
            self._timer.stop()
            return
        if not self.ready:
            self._status = '请加载 STL 并选择至少一个肺表面与一个病灶'
            self.changed.emit()
            return
        if not PlannerController._ct_ready_for_operation(self):
            self._status = '请先在二维阅片中导入并加载 CT，获取物理标尺后再量化分析'
            self.changed.emit()
            return
        self._timer.stop()
        if mode == 'auto':
            self._alternatives, self._selected_candidate = [], -1
        self._revision += 1
        drag_trace = getattr(self, '_pending_drag_trace', None) if mode == 'manual' else None
        if mode == 'manual':
            self._pending_drag_trace = None
        if drag_trace is not None:
            drag_trace.set_revision(self._revision)
            drag_trace.mark('task_queued', mode=mode,
                            task_revision=self._revision)
        lung_files = list(self._lung)
        lung_policy = 'explicit'
        # The lesion-containing surface is chosen on the worker thread; doing
        # it here froze the UI for the whole STL read and ray-cast.
        select_lung = mode == 'auto' and not self._lung_user_modified
        if select_lung:
            self._active_lung_files = None
        elif mode == 'manual' and self._active_lung_files and not self._lung_user_modified:
            lung_files = list(self._active_lung_files)
            lung_policy = 'active-auto-selection'
        job = dict(_cancel_token=Event(), revision=self._revision, mode=mode, backend=self._backend, directory=self._directory,
                   lung=lung_files, source_lung=list(self._lung), select_lung=select_lung,
                   whole_lung=[name for name in self._files if is_lung_surface(name)],
                   lung_selection_policy=lung_policy,
                   tumor=self._tumor, mirror=False,
                   mirror_plane=None,
                   lesion_count=self._lesion_count,
                   lesion_component_ids=(list(self._component_ids) if self._catalog_sha else None),
                   lesion_source_sha256=self._catalog_sha or None,
                   tumor_triangles=None,
                   lesion_index=(self._selected_lesion + 1 if self._lesion_plans and mode != 'auto' else None),
                   lesion_volume_cm3=(self._result.get('lesion_volume_cm3') if self._lesion_plans and mode != 'auto' else None),
                   params=dict(self._params),
                   vertices=None if self._needs_refit or self._vertices is None else self._vertices.copy(),
                   vertices_space=('physical' if self._expected_case_identity is not None else 'source'),
                   ct_spacing=self._ct_spacing())
        if mode == 'manual' and self._expected_case_identity is not None:
            job['expected_case_identity'] = self._expected_case_identity
            self._expected_case_identity = None
        if drag_trace is not None:
            job['_drag_trace'] = drag_trace
        if mode != 'auto':
            prior = (self._lesion_plans[self._selected_lesion]['result']
                if self._lesion_plans and 0 <= self._selected_lesion < len(self._lesion_plans)
                else self._result)
            for name in ('lesion_component_id', 'lesion_source_rank', 'lesion_source_sha256'):
                if prior.get(name) is not None:
                    job[name] = prior[name]
            if prior.get('lesion_component_id'):
                job['lesion_component_ids'] = [prior['lesion_component_id']]
        self._stale = True
        if self._busy:
            previous = self._pending
            self._pending = job  # Keep only the latest manual change.
            if previous is not None and previous.get('_drag_trace') is not None:
                previous['_drag_trace'].mark('task_superseded', by_revision=self._revision)
            if drag_trace is not None:
                drag_trace.mark('task_pending_latest_only')
        else:
            self._busy = True
            self._active_cancel = job['_cancel_token']
            if drag_trace is not None:
                drag_trace.mark('worker_dispatched')
            self.request.emit(job)
        self._status = '自动搜索可行方案...' if mode == 'auto' else '正在更新规划...'
        self.changed.emit()

    def _apply_model_defaults(self):
        """Parameters of the dual-plane wedge, the only planning model."""
        self._params['planningModel'] = 'plane_wedge'
        self._params.setdefault('wedgeAngle', 90.)
        self._params['cutTilts'] = [self._params['wedgeAngle'] / 2.] * 2

    @Slot(str)
    def setExecutionBackend(self, backend):
        if self._busy or backend not in ('cpu', 'pl') or backend == self._backend:
            return
        self._backend = backend
        self._alternatives, self._selected_candidate = [], -1
        self._timer.stop()
        self._result = {}
        self._stale = True
        self._preview_case = None
        self._plan_case_identity = None
        self._expected_case_identity = None
        self._status = '已选择 ' + ('PL 严格模式' if backend == 'pl' else '纯 PS 模式') + '，请重算'
        self.changed.emit()

    @Slot()
    def autoPlan(self):
        self._enqueue('auto')

    @Slot()
    def recompute(self):
        self._enqueue('manual')

    @Slot()
    def stopCalculation(self):
        if not self._busy or self._stopping:
            return
        self._timer.stop()
        self._pending = None
        self._stopping = True
        self._revision += 1  # Reject even an already-queued completion signal.
        if self._active_cancel is not None:
            self._active_cancel.set()  # Thread-safe; no queued worker slot.
        self._stale = True
        self._status = '正在停止计算，等待当前计算或硬件调用安全结束...'
        self.changed.emit()

    @Slot(int)
    def _cancelled(self, revision):
        self._status = '计算已停止，可调整参数后重新计算'
        self._next()

    def _next(self):
        if self._stopping:
            self._pending = None
            self._timer.stop()
            self._status = '计算已停止，可调整参数后重新计算'
        self._stopping = False
        self._active_cancel = None
        self._busy = False
        if self._pending:
            job, self._pending = self._pending, None
            if job['revision'] == self._revision:
                self._busy = True
                self._active_cancel = job['_cancel_token']
                trace = job.get('_drag_trace')
                if trace is not None:
                    trace.mark('worker_dispatched')
                self.request.emit(job)
        self.changed.emit()

    @Slot(object)
    def _completed(self, payload):
        trace = payload.get('_drag_trace')
        if payload['revision'] == self._revision:
            if trace is not None and trace.revision == payload['revision']:
                if geometry_identity(payload['vertices']) == trace.geometry_id:
                    trace.mark('gui_result_received')
                    self._active_drag_trace = trace
            if 'lesion_plans' in payload:
                self._lesion_plans = payload['lesion_plans']
                self._selected_lesion = 0 if self._lesion_plans else -1
            elif self._lesion_plans and 0 <= self._selected_lesion < len(self._lesion_plans):
                self._lesion_plans[self._selected_lesion] = payload
            self._alternatives = payload.get('alternatives', [])
            self._selected_candidate = 0 if self._alternatives else -1
            if payload.get('active_lung_files') is not None:
                self._active_lung_files = list(payload['active_lung_files'])
            self._result = payload['result']
            self._params = dict(payload['params'])
            self._params['baseArea'] = 0.
            self._vertices = payload['vertices'].copy()
            self._points = payload['points']
            self._preview_case = payload['case']
            self._geometry_current = True
            self._needs_refit = False
            self._preview_error = ''
            self._surface = payload['surface']
            self._interior_data = np.asarray(payload['interior'], dtype=np.float64)
            if payload.get('planning_case_identity'):
                self._plan_case_identity = payload['planning_case_identity']
            self._path.setSegments(payload['path'], np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale)
            self._interior.setMesh(payload['interior'], np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale)
            self._stale = False
            self._status = ('已加载并重新校验保存的规划' if payload.get('restored_plan') and self._result['valid'] else
                            '加载的规划未通过当前完整校验' if payload.get('restored_plan') else
                            '几何约束通过；临床条件待确认' if self._result['valid'] else '几何约束未通过，请调整；临床条件待确认')
            self._draw(update_surface=True, preview_path=False)
            if trace is not None and trace.revision == payload['revision']:
                trace.mark('gui_geometry_submitted', surface_triangles=len(self._surface),
                           interior_triangles=len(payload['interior']))
        elif trace is not None:
            trace.mark('stale_planner_result_rejected',
                       payload_revision=payload['revision'], current_revision=self._revision,
                       payload_geometry_id=geometry_identity(payload['vertices']))
        self._next()

    @Slot(int)
    def selectLesion(self, index):
        if self._busy or self._stale or not 0 <= index < len(self._lesion_plans):
            return
        if not self._ct_ready_for_operation():
            self._status = '请先在二维阅片中导入并加载 CT，获取物理标尺后再量化分析'
            self.changed.emit()
            return
        payload = self._lesion_plans[index]
        self._selected_lesion = index
        self._alternatives = payload.get('alternatives', [])
        self._selected_candidate = payload.get('selected_candidate', 0) if self._alternatives else -1
        self._result = payload['result']
        self._plan_case_identity = payload.get('planning_case_identity', self._plan_case_identity)
        self._params = dict(payload['params'])
        self._vertices = payload['vertices'].copy()
        self._points = payload['points']
        self._preview_case = payload['case']
        self._geometry_current, self._needs_refit = True, False
        self._surface = payload['surface']
        self._interior_data = np.asarray(payload['interior'], dtype=np.float64)
        center, scale = np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale
        self._path.setSegments(payload['path'], center, scale)
        self._interior.setMesh(payload['interior'], center, scale)
        self._status = f"病灶 {index + 1}：方案已通过完整几何校验"
        self._draw(update_surface=True, preview_path=False)
        self.changed.emit()

    @Slot(int)
    def selectCandidate(self, index):
        if self._busy or self._stale or not 0 <= index < len(self._alternatives):
            return
        item = self._alternatives[index]
        self._timer.stop()
        self._revision += 1
        self._selected_candidate = index
        self._params = dict(item['params'], baseArea=0.)
        self._vertices = item['vertices'].copy()
        self._result = dict(item['result'])
        if self._lesion_plans and 0 <= self._selected_lesion < len(self._lesion_plans):
            plan = self._lesion_plans[self._selected_lesion]
            plan.update(vertices=self._vertices.copy(), params=dict(self._params), result=dict(self._result),
                        surface=item['surface'], path=item['path'], interior=item['interior'],
                        alternatives=self._alternatives, selected_candidate=index)
        self._surface = item['surface']
        self._interior_data = np.asarray(item['interior'], dtype=np.float64)
        self._geometry_current, self._needs_refit = True, False
        center, scale = np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale
        self._path.setSegments(item['path'], center, scale)
        self._interior.setMesh(item['interior'], center, scale)
        self._status = f'方案 {index + 1} 已通过完整几何校验'
        self._draw(update_surface=True, preview_path=False)
        self.changed.emit()

    @Slot(int, str)
    def _failed(self, revision, message):
        try:
            failure_path = Path(__file__).resolve().parents[1] / 'data' / 'planner_failures.jsonl'
            failure_path.parent.mkdir(parents=True, exist_ok=True)
            record = dict(utc=datetime.now(timezone.utc).isoformat(),
                          revision=int(revision), backend=self._backend,
                          planning_model=self._params.get('planningModel'),
                          message=str(message))
            with failure_path.open('a', encoding='utf-8') as stream:
                stream.write(json.dumps(record, ensure_ascii=False) + '\n')
        except OSError:
            pass
        if revision == self._revision:
            self._stale = True
            self._status = '计算失败：' + message
        self._next()

    @Slot(int, str)
    def _progress(self, revision, status):
        if revision == self._revision:
            self._status = status
            self.changed.emit()

    @Slot()
    def savePlan(self):
        if self._stale or self._busy or not self._geometry_current or not self._result.get('valid'):
            return
        suffix = f'_lesion_{self._selected_lesion + 1}' if self._lesion_plans else ''
        default = str(Path(self._directory) / f'planning_result{suffix}.json')
        if getattr(self, 'dialogs', None):
            self.dialogs.save('保存可恢复规划', default, self.saveToPath)
            return
        path, _ = QFileDialog.getSaveFileName(None, '保存可恢复规划', default, 'JSON (*.json)')
        self.saveToPath(path)

    @Slot(str)
    def saveToPath(self, path):
        if self._stale or self._busy or not self._geometry_current or not self._result.get('valid'):
            return
        if not PlannerController._ct_ready_for_operation(self):
            self._status = '无法保存：请先在二维阅片中加载 CT 物理标尺'
            self.changed.emit()
            return
        if not self._plan_case_identity:
            self._status = '无法保存：请先完成自动规划以记录病例身份'
            self.changed.emit()
            return
        if path:
            component_id = self._result.get('lesion_component_id')
            component_ids = [component_id] if component_id else list(self._component_ids)
            if len(component_ids) != 1:
                self._status = '请先为当前方案选择一个病灶连通块再保存'
                self.changed.emit()
                return
            save_schema = WEDGE_SCHEMA
            saved_params = restore_parameters(self._params, save_schema)
            preview_case = getattr(self, '_preview_case', None)
            spacing_value = self._ct_spacing() if hasattr(self, '_ct_calibration') else (1., 1., 1.)
            spacing = np.asarray(spacing_value or (1., 1., 1.), dtype=np.float64)
            source_vertices = np.asarray(self._vertices, dtype=np.float64)
            if preview_case is not None and hasattr(preview_case, 'to_physical_vertices'):
                vertices_mm = preview_case.to_physical_vertices(source_vertices)
            else:
                vertices_mm = source_vertices * spacing
            result = dict(self._result, schema=save_schema,
                result=dict(self._result), parameters=saved_params, model_directory=self._directory,
                planning_backend=self._backend, lung_files=list(self._lung),
                tumor_file=self._tumor, tumor_source_sha256=self._catalog_sha,
                lesion_component_ids=component_ids,
                planning_case_identity=self._plan_case_identity,
                vertices_mm=np.asarray(vertices_mm, dtype=np.float64).tolist(),
                coordinate_space='physical_mm',
                ct_spacing_mm=list(spacing))

            def write(report=None, error=''):
                try:
                    if error:
                        self._status = '保存失败（分支分析未完成）：' + error
                        self.changed.emit()
                        return
                    if report:
                        result['branch_analysis'] = report
                    target = Path(path)
                    if target.suffix.lower() != '.json':
                        target = target.with_suffix('.json')
                    temporary = target.with_name(target.name + '.tmp')
                    temporary.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
                    temporary.replace(target)
                    meshes = (getattr(self, '_surface', np.empty((0, 3, 3))),
                              getattr(self, '_interior_data', np.empty((0, 3, 3))))
                    triangle_count = 0
                    if any(np.asarray(mesh).size for mesh in meshes):
                        stl_target = target.with_suffix('.stl')
                        stl_temporary = stl_target.with_name(stl_target.name + '.tmp')
                        triangle_count = _write_source_stl(stl_temporary, meshes)
                        stl_temporary.replace(stl_target)
                    self._status = ('已保存可恢复规划及源坐标 STL：' + str(target)
                                    + (f'（{triangle_count} 面）' if triangle_count else ''))
                except OSError as exc:
                    self._status = '保存失败：' + str(exc)
                except ValueError as exc:
                    self._status = '保存失败：' + str(exc)
                self.changed.emit()

            if getattr(self, 'centerlines', None):
                self.centerlines.request_report(write, scope='current')
            else:
                write()

    @Slot()
    def loadPlan(self):
        if not self.ready or self._busy:
            return
        initial = str(Path(self._directory) / 'planning_result.json')
        if getattr(self, 'dialogs', None):
            self.dialogs.open('加载规划 JSON', initial, self.loadPlanFromPath)
            return
        path, _ = QFileDialog.getOpenFileName(None, '加载规划 JSON', initial, 'JSON (*.json)')
        self.loadPlanFromPath(path)

    @Slot(str)
    def loadPlanFromPath(self, path):
        if not path:
            return
        if not self.ready or self._busy:
            self._status = '请等待模型与病灶准备完成后再加载规划'
            self.changed.emit()
            return
        try:
            saved = json.loads(Path(path).read_text(encoding='utf-8'))
            if not isinstance(saved, dict):
                raise ValueError('规划文件必须是 JSON 对象')
            if saved.get('schema') != WEDGE_SCHEMA:
                raise ValueError('文件不是双平面楔形规划，或版本不受支持')
            if saved.get('planning_backend') != self._backend:
                raise ValueError('规划后端不一致，请切换到保存时使用的后端后再加载')
            if hasattr(self, '_ct_calibration'):
                if saved.get('coordinate_space') != 'physical_mm':
                    raise ValueError('旧规划文件没有 CT 物理标尺，请重新加载 CT 后规划')
                if saved.get('ct_spacing_mm') != self._ct_spacing():
                    raise ValueError('规划文件的 CT 标尺与当前加载 CT 不一致')
            if saved.get('lung_files') != self._lung or saved.get('tumor_file') != self._tumor:
                raise ValueError('肺叶或病灶 STL 选择与保存规划不一致')
            if not self._catalog_sha or saved.get('tumor_source_sha256') != self._catalog_sha:
                raise ValueError('病灶 STL 已变化或尚未完成识别，请重新加载病例')
            identity = saved.get('planning_case_identity', '')
            if (not isinstance(identity, str) or len(identity) != 64
                    or any(char not in '0123456789abcdef' for char in identity.lower())):
                raise ValueError('规划文件缺少有效的病例几何指纹')
            identity = identity.lower()
            result = saved.get('result')
            if not isinstance(result, dict) or result.get('valid') is not True:
                raise ValueError('只允许加载通过完整校验的规划')
            vertices = np.asarray(saved.get('vertices_mm'), dtype=np.float64)
            if vertices.shape != (4, 3) or not np.isfinite(vertices).all():
                raise ValueError('规划文件中的切除区域顶点无效')
            if ref.tri_area(*map(tuple, vertices[:3])) <= 0.:
                raise ValueError('规划文件中的切除区域已退化')
            restored_params = restore_parameters(saved.get('parameters'), saved['schema'])
            component_ids = saved.get('lesion_component_ids', [])
            if (not isinstance(component_ids, list) or len(component_ids) != 1
                    or component_ids[0] not in {row['id'] for row in self._lesion_components}):
                raise ValueError('保存的病灶连通块与当前选择不匹配')
        except (OSError, UnicodeError, json.JSONDecodeError, TypeError, ValueError) as exc:
            self._status = '加载规划失败：' + str(exc)
            self.changed.emit()
            return

        self._invalidate()
        self._component_ids = component_ids
        self._lesion_count = 1
        self._params = restored_params
        # Saved vertices are persisted in CT physical millimetres, while the
        # interactive scene and planner state use immutable STL/source
        # coordinates.  Convert back before publishing or centerline analysis.
        preview_case = getattr(self, '_preview_case', None)
        if preview_case is not None and hasattr(preview_case, 'to_source_vertices'):
            source_vertices = preview_case.to_source_vertices(vertices)
        else:
            spacing_value = self._ct_spacing() if hasattr(self, '_ct_spacing') else None
            spacing = np.asarray(spacing_value or (1., 1., 1.), dtype=np.float64)
            source_vertices = vertices / spacing
        self._vertices = np.asarray(source_vertices, dtype=np.float64).copy()
        self._result = {}
        self._geometry_current = False
        self._needs_refit = False
        self._stale = True
        self._expected_case_identity = identity
        self._status = '正在加载并完整校验保存的规划...'
        self.lesionCatalogChanged.emit()
        self._draw(update_surface=True)
        self._enqueue('manual')

    def planSnapshots(self):
        """Capture each lesion's selected candidate before queuing any analysis."""
        from copy import deepcopy
        if self._stale or self._busy or not self._geometry_current:
            return []
        plans = list(self._lesion_plans) or [dict(case=self._preview_case,
            result=self._result, params=self._params, vertices=self._vertices)]
        if self._lesion_plans and 0 <= self._selected_lesion < len(plans):
            plans[self._selected_lesion] = dict(plans[self._selected_lesion],
                case=self._preview_case, result=self._result, params=self._params, vertices=self._vertices)
        return [dict(case=p['case'], result=deepcopy(p['result']), params=dict(p['params']),
                     vertices=np.asarray(p['vertices']).copy()) for p in plans]

    @Slot()
    def saveAllPlans(self):
        if not self.planSnapshots():
            return
        default = str(Path(self._directory) / 'qt_plans_all.json')
        if getattr(self, 'dialogs', None):
            self.dialogs.save('导出全部病灶与联合分支清单', default, self.saveAllToPath)
        else:
            path, _ = QFileDialog.getSaveFileName(None, '导出全部病灶与联合分支清单', default, 'JSON (*.json)')
            self.saveAllToPath(path)

    @Slot(str)
    def saveAllToPath(self, path):
        plans = self.planSnapshots()
        if not path or not plans or not all(p['result'].get('valid') for p in plans):
            return
        bundle = dict(schema='cloud-breathing-multilesion-v1', model_directory=self._directory,
            planning_backend=self._backend, lesion_count=len(plans),
            lesions=[dict(p['result'], parameters=p['params'], base_vertices=p['vertices'][:3].tolist(),
                          apex=p['vertices'][3].tolist()) for p in plans])
        unavailable_status = self.centerlines.status if getattr(self, 'centerlines', None) else '未提取中心线'

        def write(reports, union, error=''):
            if error:
                self._status = '导出失败：' + error
            else:
                for lesion, report in zip(bundle['lesions'], reports):
                    if report is not None:
                        lesion['branch_analysis'] = report
                bundle['union_branch_analysis'] = union
                bundle['branch_analysis_available'] = union is not None
                if getattr(self, 'centerlines', None) and union is None:
                    bundle['branch_analysis_status'] = unavailable_status
                try:
                    Path(path).write_text(json.dumps(bundle, ensure_ascii=False, indent=2), encoding='utf-8')
                    self._status = '已导出全部病灶与联合清单：' + path
                except OSError as exc:
                    self._status = '导出失败：' + str(exc)
            self.changed.emit()

        if getattr(self, 'centerlines', None):
            self.centerlines.request_bundle(plans, write)
        else:
            write([None] * len(plans), None)

    def shutdown(self):
        self._timer.stop()
        self._pending = None
        if self._active_cancel is not None:
            self._active_cancel.set()
        self._thread.requestInterruption()
        self._thread.quit()
        self._thread.wait()
        self._worker.pl.close()
