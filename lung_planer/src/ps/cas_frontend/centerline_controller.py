"""Asynchronous desktop extraction and a cached, independent planning overlay."""
import json
import logging
import os
from collections import OrderedDict
from copy import deepcopy
from pathlib import Path
from time import perf_counter

import numpy as np
from PySide6.QtCore import QObject, Property, QThread, QTimer, Signal, Slot
from PySide6.QtGui import QVector3D

from .centerlines import (KINDS, structure_kind, extract_cached, grade_forest,
                          preload, tube_mesh)
from .planner import PlanGeometry
from .branch_analysis import BranchAnalysisEngine, AnalysisCancelled, mesh_identity
from .branch_list_model import BranchListModel, BranchFilterModel
from .branch_presentation import display_rows, displayed_branches, displayed_components
from .render_buffers import prepare_mesh
from .drag_trace import geometry_identity

COLORS = {'artery': '#ff6472', 'vein': '#55baff', 'airway': '#7de5ab'}
STATUS = {'full': '中心线整支在切除区', 'partial': '中心线部分进入切除区',
          'near': '管壁邻近（待复核）', 'outside': '中心线在切除区外'}


class CenterlineWorker(QObject):
    completed = Signal(object)
    progress = Signal(int, str)

    def __init__(self, pl=None):
        super().__init__()
        self.pl = pl
        self._owns_pl = pl is None

    @Slot()
    def warm(self):
        # Runs on the worker thread; a later extract() queues behind it.
        try:
            preload()
        except Exception:
            logging.getLogger(__name__).warning('Centerline preload failed', exc_info=True)

    @Slot(object)
    def run(self, job):
        trees, errors = [], []
        started = perf_counter()
        for i, source in enumerate(job['sources']):
            if QThread.currentThread().isInterruptionRequested():
                break
            prefix = f'{i + 1}/{len(job["sources"])} · {KINDS[source["kind"]]}'
            try:
                backend = job.get('centerline_backend', os.environ.get('LUNG_CENTERLINE_BACKEND', 'legacy'))
                path = Path(job['directory']) / source['file']
                progress = lambda msg: self.progress.emit(job['revision'], prefix + ' · ' + msg)
                if backend == 'legacy' and path.suffix.lower() == '.stl':
                    tree = extract_cached(path, job['cache'], job['spacing'],
                        QThread.currentThread().isInterruptionRequested, progress)
                else:
                    from .mask_centerlines import extract_source_cached
                    if backend == 'pl' and self.pl is None:
                        from .pl_metrics import PlMetrics
                        self.pl = PlMetrics(require_strict_pl=True)
                    tree = extract_source_cached(path, job['cache'], job['spacing'],
                        backend='ps' if backend=='legacy' else backend, pl=self.pl,
                        metadata_path=source.get('metadata_path'),
                        cancelled=QThread.currentThread().isInterruptionRequested, progress=progress)
                tree.update(file=source['file'], kind=source['kind'])
                try:
                    settings = json.loads((Path(job['cache']) / (tree['cache_key'] + '.roots.json')).read_text(encoding='utf-8'))
                    roots = settings['roots']
                    if all(isinstance(v, int) and 0 <= v < len(tree['nodes']) for v in roots):
                        grade_forest(tree, roots)
                        tree['root_confirmed'] = True
                except (OSError, ValueError, KeyError, TypeError):
                    tree['root_confirmed'] = False
                trees.append(tree)
            except Exception as exc:
                errors.append(source['file'] + '：' + (
                    '缺少中心线依赖，请用启动程序的 Python 安装 requirements-centerlines.txt'
                    if isinstance(exc, ModuleNotFoundError) else str(exc)))
        rendered = {}
        if 'center' in job:
            for kind in KINDS:
                segments = [pair for tree in trees if tree['kind'] == kind
                    for b in displayed_branches(tree) for pair in zip(b['points'][:-1], b['points'][1:])]
                rendered[kind] = prepare_mesh(tube_mesh(segments, .32), job['center'], job['scale'])
        self.completed.emit(dict(revision=job['revision'], trees=trees, errors=errors, rendered=rendered,
                                 elapsed_ms=(perf_counter() - started) * 1000.))


class BranchAnalysisWorker(QObject):
    completed = Signal(object)

    def __init__(self, pl=None):
        super().__init__()
        self.engine, self.pl = BranchAnalysisEngine(), pl

    @Slot(object)
    def run(self, job):
        payload = dict(signature=job['signature'], job=job)
        trace = job.get('_drag_trace')
        try:
            if trace is not None:
                trace.mark('branch_worker_started')
            if len(job.get('cases', [])) > 1:
                identities = {mesh_identity(case) for case in job['cases']}
                if len(identities) != 1:
                    raise ValueError('联合分析要求各病灶使用相同坐标和肺实体，请统一肺表面后重新规划')
            spacing = np.asarray(getattr(job['case'], 'ct_spacing', (1., 1., 1.)), dtype=float)
            payload['output'] = self.engine.run(job['case'], job['backend'],
                job['trees'], np.asarray(job['vertices']) * spacing, pl=self.pl,
                cancelled=lambda: job['cancel']['value'])
            output = payload['output']
            if trace is not None:
                trace.mark('branch_compute_complete',
                           branch_count=sum(len(tree.get('branches', [])) for tree in job['trees']),
                           query_ms=output['timing']['query_ms'],
                           elapsed_ms=output['timing']['total_ms'])
            output['report'].update(job.get('report_metadata', {}))
            output['display_rows'] = display_rows(job['trees'], output['analyses'])
            if 'center' in job:
                output['rendered'] = {name: prepare_mesh(output.pop(name + '_mesh') / spacing, job['center'], job['scale'])
                    for name in ('removed', 'near')}
        except AnalysisCancelled:
            payload['cancelled'] = True
            if trace is not None:
                trace.mark('branch_cancelled')
        except Exception as exc:
            logging.getLogger(__name__).exception('Centerline branch analysis failed')
            payload['error'] = str(exc)
        self.completed.emit(payload)


class CenterlineController(QObject):
    busyChanged = Signal()
    statusChanged = Signal()
    summaryChanged = Signal()
    spacingChanged = Signal()
    sourcesChanged = Signal()
    treesChanged = Signal()
    displayChanged = Signal()
    sourceSelectionChanged = Signal()
    selectionChanged = Signal()
    selectionIndexChanged = Signal()
    filterChanged = Signal()
    rowsChanged = Signal()
    rootsChanged = Signal()
    rootPreviewChanged = Signal()
    relationChanged = Signal()
    planStateChanged = Signal()
    request = Signal(object)
    requestWarm = Signal()
    requestRelation = Signal(object)
    analysisStateChanged = Signal()
    scopeChanged = Signal()

    def __init__(self, viewer, planner, root):
        super().__init__()
        self.viewer, self.planner = viewer, planner
        self._cache = Path(root) / 'data' / 'centerlines'
        self._directory, self._sources, self._trees = '', [], []
        self._rows, self._affected, self._analysis = [], [], []
        self._row_indexes = {}
        self._branch_model = BranchListModel(self)
        self._branch_filter = BranchFilterModel(self._branch_model, self)
        self._selection_meshes = OrderedDict()
        self._unplanned_rows = None
        self._unplanned_revision = -1
        self._source_errors = []
        self._analysis_scope = 'current'
        self._root_options, self._root_points, self._cut_points = [], [], []
        self._selected_source, self._selected_branch = 0, ''
        self._revision, self._busy, self._spacing = 0, False, .8
        self._visible, self._xray = True, True
        self._only_affected = True
        self._root_candidate = None
        self._status = '加载模型后提取动静脉与支气管中心线'
        self._summary, self._signature, self._last_error = '', None, ''
        self._lung_index_identity, self._lung_caches = None, {}
        self._tree_revision = 0
        self._relation_busy, self._relation_status = False, '生成或重算规划后显示肺内切除分支关系。'
        self._relation_results, self._relation_jobs = OrderedDict(), {}
        self._report = None
        self._observed_signature = None
        self._geometries = {key: PlanGeometry() for key in (*KINDS, 'removed', 'near', 'selected')}
        for geometry in self._geometries.values():
            geometry.setParent(self)
        self._thread = QThread(self)
        self._worker = CenterlineWorker(getattr(getattr(planner, '_worker', None), 'pl', None))
        self._worker.moveToThread(self._thread)
        self.request.connect(self._worker.run)
        self.requestWarm.connect(self._worker.warm)
        self._warmed = False
        self._worker.completed.connect(self._completed)
        self._worker.progress.connect(self._progress)
        self._thread.finished.connect(self._worker.deleteLater)
        self._thread.start()
        # Serialize hardware access and case statistics with planning itself.
        self._owns_relation_thread = not hasattr(planner, '_thread')
        self._relation_thread = QThread(self) if self._owns_relation_thread else planner._thread
        self._relation_worker = BranchAnalysisWorker(getattr(getattr(planner, '_worker', None), 'pl', None))
        self._relation_worker.moveToThread(self._relation_thread)
        self.requestRelation.connect(self._relation_worker.run)
        self._relation_worker.completed.connect(self._relation_completed)
        self._relation_thread.finished.connect(self._relation_worker.deleteLater)
        if self._owns_relation_thread:
            self._relation_thread.start()
        self._timer = QTimer(self); self._timer.setSingleShot(True); self._timer.setInterval(140)
        self._timer.timeout.connect(self._refresh)
        viewer.loadStarted.connect(self._reset)
        viewer.rowsChanged.connect(self._loaded)
        planner.changed.connect(self._plan_changed)

    busy = Property(bool, lambda s: s._busy, notify=busyChanged)
    ready = Property(bool, lambda s: bool(s._trees), notify=treesChanged)
    status = Property(str, lambda s: s._status, notify=statusChanged)
    summary = Property(str, lambda s: s._summary, notify=summaryChanged)
    spacing = Property(float, lambda s: s._spacing, notify=spacingChanged)
    visible = Property(bool, lambda s: s._visible, notify=displayChanged)
    xray = Property(bool, lambda s: s._xray and bool(s._trees) and s._visible, notify=displayChanged)
    sourceCount = Property(int, lambda s: len(s._sources), notify=sourcesChanged)
    sourceLabels = Property('QStringList', lambda s: [f'{KINDS[t["kind"]]} · {t["file"]}' for t in s._trees], notify=treesChanged)
    selectedSource = Property(int, lambda s: s._selected_source, notify=sourceSelectionChanged)
    selectedBranch = Property(str, lambda s: s._selected_branch, notify=selectionChanged)
    selectedRow = Property(int, lambda s: s._row_indexes.get(s._selected_branch, -1), notify=selectionIndexChanged)
    onlyAffected = Property(bool, lambda s: s._only_affected, notify=filterChanged)
    rows = Property('QVariantList', lambda s: s._affected if s._only_affected else s._rows, notify=rowsChanged)
    branchModel = Property(QObject, lambda s: s._branch_filter, constant=True)
    analysisScope = Property(str, lambda s: s._analysis_scope, notify=scopeChanged)
    unionAvailable = Property(bool, lambda s: len(getattr(s.planner, '_lesion_plans', [])) > 1,
                              notify=analysisStateChanged)
    affectedCount = Property(int, lambda s: len(s._affected), notify=relationChanged)
    enteredCount = Property(int, lambda s: sum(r['status'] in ('partial', 'full') for r in s._rows),
                            notify=relationChanged)
    nearCount = Property(int, lambda s: sum(r['status'] == 'near' for r in s._rows),
                         notify=relationChanged)
    downstreamCount = Property(int, lambda s: sum(r['downstream_affected'] for r in s._rows),
                               notify=relationChanged)
    planCurrent = Property(bool, lambda s: s._plan_is_current() and s._signature == s._plan_signature()
                           and s._report is not None, notify=planStateChanged)
    analysisBusy = Property(bool, lambda s: s._relation_busy, notify=analysisStateChanged)
    analysisStatus = Property(str, lambda s: s._relation_status, notify=analysisStateChanged)
    arteryGeometry = Property(QObject, lambda s: s._geometries['artery'], constant=True)
    veinGeometry = Property(QObject, lambda s: s._geometries['vein'], constant=True)
    airwayGeometry = Property(QObject, lambda s: s._geometries['airway'], constant=True)
    removedGeometry = Property(QObject, lambda s: s._geometries['removed'], constant=True)
    nearGeometry = Property(QObject, lambda s: s._geometries['near'], constant=True)
    selectedGeometry = Property(QObject, lambda s: s._geometries['selected'], constant=True)

    @Property('QVariantList', notify=relationChanged)
    def cutPoints(self):
        if not self.planCurrent:
            return []
        return self._cut_points

    @Property('QVariantList', notify=rootPreviewChanged)
    def rootCandidatePoints(self):
        if self._root_candidate is None or not self._trees:
            return []
        tree = self._trees[self._selected_source]
        if not 0 <= self._root_candidate < len(tree['nodes']):
            return []
        point = np.asarray(tree['nodes'][self._root_candidate]['point'])
        return [QVector3D(*map(float, (point - np.asarray(self.viewer.sceneCenterMm)) * self.viewer.sceneScale))]

    @Property('QVariantList', notify=rootsChanged)
    def roots(self):
        return self._root_options

    def _update_roots(self):
        self._root_options, self._root_points = [], []
        if not self._trees:
            self.rootsChanged.emit()
            return
        tree = self._trees[self._selected_source]
        degree = [0] * len(tree['nodes'])
        for b in tree['branches']:
            degree[b['start']] += 1; degree[b['end']] += 1
        self._root_options = [dict(id=n['id'], label=f'端点 {n["id"]} · 半径 {n["radius_mm"]:.1f} mm'
                     + f' · ({n["point"][0]:.0f}, {n["point"][1]:.0f}, {n["point"][2]:.0f})'
                     + (' · 当前根部' if n['id'] in tree['roots'] else ''))
                for n in tree['nodes'] if degree[n['id']] == 1]

        center, scale = np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale
        for tree in self._trees:
            lengths = {}
            for branch in tree['branches']:
                lengths[branch['root']] = lengths.get(branch['root'], 0.) + branch['length_mm']
            primary_root = max(lengths, key=lambda root: (lengths[root], -root), default=None)
            self._root_points.extend(dict(
                point=QVector3D(*map(float, (np.asarray(tree['nodes'][root]['point']) - center) * scale)),
                color=COLORS[tree['kind']]) for root in tree['roots']
                if root == primary_root and lengths.get(root, 0.) >= 8.)
        self.rootsChanged.emit()

    rootPoints = Property('QVariantList', lambda s: s._root_points, notify=rootsChanged)

    def _update_row_indexes(self):
        self._branch_model.replace(self._rows)
        self._branch_filter.set_only_affected(self._only_affected)
        self._row_indexes = {row['key']: i for i, row in enumerate(self.rows)}
        self.rowsChanged.emit()
        self.selectionIndexChanged.emit()

    def _plan_is_current(self):
        return bool(self.planner.hasPlan and self.planner.geometryCurrent and not self.planner.metricsPending
                    and not getattr(self.planner, 'busy', False)
                    and self.planner._preview_case is not None)

    def _capture_plans(self, scope):
        if not self._plan_is_current():
            return []
        if scope == 'union':
            return self.planner.planSnapshots()
        return [dict(case=self.planner._preview_case,
            vertices=np.asarray(self.planner._vertices).copy(), result=dict(self.planner._result))]

    def _snapshot_signature(self, plans, scope):
        identities = []
        for plan in plans:
            case = plan['case']
            if not hasattr(case, '_branch_case_token'):
                case._branch_case_token = object()
            identities.append((case._branch_case_token, np.asarray(plan['vertices']).tobytes(),
                plan['result'].get('lesion_component_id'), plan['result'].get('lesion_index')))
        return scope, self.planner.executionBackend, self._tree_revision, tuple(identities)

    def _plan_signature(self):
        plans = self._capture_plans(self._analysis_scope)
        return self._snapshot_signature(plans, self._analysis_scope) if plans else None

    @Slot(str)
    def setAnalysisScope(self, scope):
        if scope not in ('current', 'union') or scope == self._analysis_scope:
            return
        if scope == 'union' and not self.unionAvailable:
            return
        self._analysis_scope = scope
        self._invalidate_relation()
        self.scopeChanged.emit()
        self._timer.stop(); self._refresh()

    def _invalidate_relation(self):
        for job in self._relation_jobs.values():
            if not job['callbacks']:
                job['cancel']['value'] = True
        self._signature, self._report = None, None
        self._relation_busy = False
        self._publish(None)

    @Slot()
    def _reset(self):
        self._invalidate_relation()
        self._observed_signature = None
        self._tree_revision += 1
        self._relation_results.clear()
        self._revision += 1; self._timer.stop()
        self._trees, self._rows, self._affected, self._analysis = [], [], [], []
        self._selection_meshes.clear()
        self._source_errors = []
        self._cut_points = []
        self._sources, self._directory = [], ''
        self._selected_source, self._selected_branch = 0, ''
        self._root_candidate = None
        self._summary, self._signature = '', None
        self._lung_index_identity, self._lung_caches = None, {}
        self._status = '等待模型加载'
        self._draw_all()
        self._update_roots(); self._update_row_indexes()
        self.treesChanged.emit(); self.sourcesChanged.emit()
        self.sourceSelectionChanged.emit(); self.selectionChanged.emit()
        self.rootPreviewChanged.emit(); self.relationChanged.emit()
        self.planStateChanged.emit(); self.displayChanged.emit()
        self.summaryChanged.emit(); self.statusChanged.emit()

    @Slot()
    def _loaded(self):
        self._directory = self.viewer.directory
        root = Path(self._directory)
        self._sources = [dict(file=p.relative_to(root).as_posix(), kind=structure_kind(p.name))
                         for p in sorted(root.rglob('*')) if p.suffix.lower() in ('.stl', '.npy')
                         and structure_kind(p.name)
                         and not (p.suffix.lower()=='.stl' and p.with_suffix('.npy').exists())]
        self._status = f'识别 {len(self._sources)} 个管道模型，点击提取中心线'
        self.sourcesChanged.emit(); self.statusChanged.emit()
        if self._sources and not self._warmed:
            self._warmed = True
            self.requestWarm.emit()

    @Slot(float)
    def setSpacing(self, value):
        if not self._busy and np.isfinite(value):
            value = max(.2, min(2., float(value)))
            if value != self._spacing:
                self._spacing = value; self.spacingChanged.emit()

    @Slot(bool)
    def setVisible(self, value):
        if self._visible != value:
            self._visible = value; self.displayChanged.emit()

    @Slot(bool)
    def setXray(self, value):
        if self._xray != value:
            self._xray = value; self.displayChanged.emit()

    @Slot(bool)
    def setOnlyAffected(self, value):
        if self._only_affected != value:
            self._only_affected = value
            self._update_row_indexes(); self.filterChanged.emit()

    @Slot(int)
    def selectSource(self, value):
        if 0 <= value < len(self._trees) and value != self._selected_source:
            self._selected_source = value; self._root_candidate = None
            self._update_roots()
            self.sourceSelectionChanged.emit(); self.rootPreviewChanged.emit()

    @Slot(int)
    def previewRoot(self, node):
        candidate = node if node >= 0 else None
        if self._root_candidate != candidate:
            self._root_candidate = candidate; self.rootPreviewChanged.emit()

    @Slot(int)
    def setRoot(self, node):
        if not self._trees or self._busy:
            return
        # Pending jobs retain immutable trees, including their original roots.
        tree = deepcopy(self._trees[self._selected_source])
        allowed = {item['id'] for item in self.roots}
        if node not in allowed:
            return
        # Replace only the root belonging to this component.
        component = next(b['component'] for b in tree['branches'] if node in (b['start'], b['end']))
        previous = {b['root'] for b in tree['branches'] if b['component'] == component}
        roots = [r for r in tree['roots'] if r not in previous] + [node]
        grade_forest(tree, roots)
        self._trees = list(self._trees)
        self._trees[self._selected_source] = tree
        self._tree_revision += 1
        self._lung_caches = {}  # Rerooting reverses polylines and segment indices.
        tree['root_confirmed'] = True
        try:
            target = self._cache / (tree['cache_key'] + '.roots.json')
            target.write_text(json.dumps(dict(roots=tree['roots'])), encoding='utf-8')
            self._status = '根部已保存，拓扑级数已更新'
        except OSError as exc:
            self._status = '根部已更新，保存失败：' + str(exc)
        self._update_roots(); self.statusChanged.emit()
        self._signature = None; self._refresh()

    @Slot()
    def extract(self):
        if self._busy or not self._sources or self.viewer.busy:
            return
        self._revision += 1; self._busy = True
        self._invalidate_relation()
        self._status = '正在准备中心线分析…'
        self.request.emit(dict(revision=self._revision, directory=self._directory,
            sources=list(self._sources), spacing=self._spacing, cache=str(self._cache),
            center=list(self.viewer.sceneCenterMm), scale=self.viewer.sceneScale))
        self.busyChanged.emit(); self.statusChanged.emit()

    @Slot(int, str)
    def _progress(self, revision, text):
        if revision == self._revision:
            self._status = text; self.statusChanged.emit()

    @Slot(object)
    def _completed(self, payload):
        self._busy = False; self.busyChanged.emit()
        if payload['revision'] != self._revision:
            return
        self._trees = payload['trees']
        self._tree_revision += 1
        self._lung_caches = {}
        self._selected_source, self._selected_branch = 0, ''
        self._last_error = '；'.join(payload['errors'])
        self._source_errors = list(payload['errors'])
        self._selection_meshes.clear()
        count = sum(len(t['branches']) for t in self._trees)
        hits = sum(t['cache_hit'] for t in self._trees)
        # Only failures are worth a line here; counts and timings stay in the log.
        self._status = self._last_error if self._last_error else ('' if self._trees else '未提取到中心线')
        logging.getLogger(__name__).info('CENTERLINES %d trees, %d branches, cache %d/%d, %.2f s',
            len(self._trees), count, hits, len(self._trees), payload['elapsed_ms'] / 1000)
        if self._trees:
            def spacing_label(tree):
                values = np.asarray(tree['spacing_mm']).reshape(-1)
                label = ' × '.join(f'{value:.2f}' for value in values)
                return f'{KINDS[tree["kind"]]} {label} mm'
            spacing = ' / '.join(spacing_label(t) for t in self._trees)
            cycles = sum(t['cyclic_components'] for t in self._trees)
            self._summary = spacing + f'\n{sum(t["component_count"] for t in self._trees)} 个独立连通分量，各自起算；根部为较粗端点，金色标记，可校正。'
            repaired = sum(t.get('repaired_gap_count', 0) for t in self._trees)
            if repaired:
                self._summary += f'\n已按端点方向、半径和间距补接 {repaired} 处短断点；其余断裂保留。'
            self._summary += '\n中心线已做掩膜约束平滑；小碎片的一级不代表近端主干。'
            if cycles:
                self._summary += f'\n{cycles} 个含环分量为暂定级数，非树边未分级。'
        else:
            self._summary = ''
        self._root_candidate = None
        self._update_roots()
        self.treesChanged.emit(); self.sourceSelectionChanged.emit()
        self.selectionChanged.emit(); self.rootPreviewChanged.emit()
        self.displayChanged.emit(); self.statusChanged.emit(); self.summaryChanged.emit()
        self._draw_all(payload.get('rendered')); self._signature = None; self._refresh()

    def _draw_all(self, rendered=None):
        center, scale = np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale
        for kind in KINDS:
            if rendered and kind in rendered:
                self._geometries[kind].setPrepared(rendered[kind])
                continue
            segments = []
            for tree in self._trees:
                if tree['kind'] == kind:
                    for b in displayed_branches(tree):
                        p = np.asarray(b['points'])
                        segments.extend(np.stack((p[:-1], p[1:]), axis=1))
            self._geometries[kind].setMesh(tube_mesh(segments, .32), center, scale)
        for name in ('removed', 'near', 'selected'):
            self._geometries[name].setMesh([], center, scale)

    @Slot()
    def _plan_changed(self):
        if self._analysis_scope == 'union' and not self.unionAvailable:
            self._analysis_scope = 'current'
            self.scopeChanged.emit()
        signature = self._plan_signature()
        if signature != self._observed_signature:
            self._observed_signature = signature
            if self._report is not None or self._relation_busy:
                self._invalidate_relation()
            self._relation_status = '正在等待分支分析…' if signature else '生成或重算规划后显示肺内切除分支关系。'
            trace = getattr(self.planner, '_active_drag_trace', None)
            current_drag = (signature is not None and trace is not None
                            and trace.revision == self.planner._revision
                            and trace.geometry_id == geometry_identity(self.planner._vertices))
            if current_drag:
                trace.mark('branch_association_invalidated')
            self.analysisStateChanged.emit()
            if current_drag:
                self._timer.stop()
                trace.mark('branch_debounce_bypassed')
                self._refresh()
            else:
                self._timer.start()

    @Slot()
    def _refresh(self):
        signature = self._plan_signature()
        self._observed_signature = signature
        if signature is None or not self._trees or self._busy:
            self._publish(None)
            return
        if signature in self._relation_results:
            trace = getattr(self.planner, '_active_drag_trace', None)
            if (trace is not None and trace.revision == self.planner._revision
                    and trace.geometry_id == geometry_identity(self.planner._vertices)):
                trace.mark('branch_cache_hit')
            self._apply_output(signature, self._relation_results[signature], cached=True)
            return
        self._relation_busy = True
        self._relation_status = '正在后台分析切除分支（' + self.planner.executionBackend.upper() + '）…'
        self.analysisStateChanged.emit()
        self._queue_analysis(self._capture_plans(self._analysis_scope), self._analysis_scope, signature)

    def _queue_analysis(self, plans, scope, signature=None, callback=None):
        signature = signature or self._snapshot_signature(plans, scope)
        cached = self._relation_results.get(signature)
        if cached is not None:
            if callback:
                callback(cached['report'], '')
            return
        job = self._relation_jobs.get(signature)
        if job is None or job['cancel']['value']:
            trace = getattr(self.planner, '_active_drag_trace', None)
            if (trace is None or trace.revision != self.planner._revision
                    or trace.geometry_id != geometry_identity(plans[0]['vertices'])):
                trace = None
            job = dict(signature=signature, case=plans[0]['case'], cases=[p['case'] for p in plans],
                backend=self.planner.executionBackend, trees=tuple(self._trees),
                vertices=(np.stack([p['vertices'] for p in plans]) if scope == 'union' else
                          np.asarray(plans[0]['vertices']).copy()),
                center=list(self.viewer.sceneCenterMm), scale=self.viewer.sceneScale,
                report_metadata=dict(analysis_scope=scope,
                    lesions=[{k: p['result'].get(k) for k in ('lesion_index', 'lesion_component_id', 'lesion_source_rank')}
                             for p in plans],
                    source_completeness=dict(complete=not bool(self._source_errors),
                        expected_files=[s['file'] for s in self._sources],
                        analyzed_files=[t['file'] for t in self._trees], errors=list(self._source_errors))),
                cancel={'value': False}, callbacks=[callback] if callback else [],
                _drag_trace=trace)
            self._relation_jobs[signature] = job
            if trace is not None:
                trace.mark('branch_task_submitted')
            self.requestRelation.emit(job)
        elif callback:
            job['callbacks'].append(callback)

    @Slot(object)
    def _relation_completed(self, payload):
        signature, job = payload['signature'], payload['job']
        trace = job.get('_drag_trace')
        if trace is not None:
            trace.mark('branch_result_received',
                       current_signature=signature == self._plan_signature(),
                       cancelled=bool(job['cancel']['value']))
        if self._relation_jobs.get(signature) is job:
            del self._relation_jobs[signature]
        output = payload.get('output')
        if output is not None:
            self._relation_results[signature] = output
            self._relation_results.move_to_end(signature)
            while len(self._relation_results) > 8:
                self._relation_results.popitem(last=False)
        if signature == self._plan_signature() and not job['cancel']['value']:
            if output is not None:
                self._apply_output(signature, output)
            elif 'error' in payload:
                self._relation_busy = False
                self._relation_status = '切除分支分析失败：' + payload['error']
                self.analysisStateChanged.emit(); self.planStateChanged.emit()
        elif job.get('_drag_trace') is not None:
            job['_drag_trace'].mark('stale_branch_result_rejected')
        for callback in job['callbacks']:
            callback(output['report'] if output else None,
                     '' if output else payload.get('error', '分支分析已取消'))

    def _apply_output(self, signature, output, cached=False):
        trace = getattr(self.planner, '_active_drag_trace', None)
        current_drag = (trace is not None and trace.revision == self.planner._revision
                        and self.planner._vertices is not None
                        and trace.geometry_id == geometry_identity(self.planner._vertices))
        if current_drag:
            trace.mark('branch_gui_submit_start', cached=cached)
        self._signature, self._report = signature, output['report']
        self._relation_busy = False
        timing = output['timing']
        self._relation_status = '联合切除' if output['report'].get('analysis_scope') == 'union' else ''
        self._publish(output)
        self.analysisStateChanged.emit()
        if current_drag:
            trace.mark('branch_result_submitted')
            trace.mark('full_result_ready')
            trace.log_snapshot('full_result_ready')

    def _publish(self, output):
        current = output is not None
        if current:
            self._rows, self._affected = (output['display_rows'] if 'display_rows' in output else
                display_rows(self._trees, output['analyses']))
        else:
            if self._unplanned_revision != self._tree_revision or self._unplanned_rows is None:
                self._unplanned_rows = display_rows(self._trees)
                self._unplanned_revision = self._tree_revision
            self._rows, self._affected = self._unplanned_rows
        self._analysis = output['report']['trees'] if current else []
        center, scale = np.asarray(self.viewer.sceneCenterMm), self.viewer.sceneScale
        for name in ('removed', 'near'):
            if current and output.get('rendered'):
                self._geometries[name].setPrepared(output['rendered'][name])
            else:
                self._geometries[name].setMesh(output[name + '_mesh'] if current else [], center, scale)
        self._draw_selection()
        spacing = np.asarray(output['report'].get('ct_spacing_mm') or (1., 1., 1.), dtype=float) if current else 1.
        # Cut points are in CT millimetres; the scene uses STL source units.
        shown = [displayed_components(tree) for tree in self._trees] if current else []
        self._cut_points = [QVector3D(*map(float, (np.asarray(p) / spacing - center) * scale))
            for tree, keep in zip(self._analysis, shown) for row in tree['rows']
            if row['component'] in keep for p in row['cut_points']]
        self._update_row_indexes()
        self.relationChanged.emit(); self.planStateChanged.emit()

    @Slot(str)
    def selectBranch(self, key):
        try:
            i, j = map(int, key.split(':'))
            if not (0 <= i < len(self._trees) and 0 <= j < len(self._trees[i]['branches'])):
                return
        except (ValueError, TypeError):
            return
        self._selected_branch = '' if self._selected_branch == key else key
        self._draw_selection()
        self.selectionChanged.emit(); self.selectionIndexChanged.emit()

    def _draw_selection(self):
        segments = []
        if self._selected_branch:
            i, j = map(int, self._selected_branch.split(':'))
            if i < len(self._trees) and j < len(self._trees[i]['branches']):
                points = np.asarray(self._trees[i]['branches'][j]['points'])
                segments = np.stack((points[:-1], points[1:]), axis=1)
        key = self._tree_revision, self._selected_branch, tuple(self.viewer.sceneCenterMm), self.viewer.sceneScale
        if key not in self._selection_meshes:
            self._selection_meshes[key] = prepare_mesh(tube_mesh(segments, .85),
                self.viewer.sceneCenterMm, self.viewer.sceneScale)
        self._selection_meshes.move_to_end(key)
        while len(self._selection_meshes) > 24 or sum(len(v['data']) for v in self._selection_meshes.values()) > 16_000_000:
            if len(self._selection_meshes) == 1:
                break
            self._selection_meshes.popitem(last=False)
        self._geometries['selected'].setPrepared(self._selection_meshes[key])

    def export_report(self):
        return self._report if self.planCurrent else None

    def request_report(self, callback, *, scope=None):
        """Save a snapshot without blocking the GUI or exporting stale relations."""
        scope = scope or self._analysis_scope
        if self.planCurrent and scope == self._analysis_scope:
            callback(self._report, '')
            return
        if not self._plan_is_current() or not self._trees or self._busy:
            callback(None, '')
            return
        self._queue_analysis(self._capture_plans(scope), scope, callback=callback)

    def request_bundle(self, plans, callback):
        if not self._trees:
            callback([None] * len(plans), None, '')
            return
        if self._busy:
            callback([], None, '中心线正在重新提取，请完成后导出')
            return
        state = dict(remaining=len(plans) + 1, failed=False, reports=[None] * len(plans), union=None)

        def received(index, report, error):
            if state['failed']:
                return
            if error:
                state['failed'] = True
                callback([], None, error)
                return
            if index is None:
                state['union'] = report
            else:
                state['reports'][index] = report
            state['remaining'] -= 1
            if state['remaining'] == 0:
                callback(state['reports'], state['union'], '')

        for index, plan in enumerate(plans):
            self._queue_analysis([plan], 'current', callback=lambda report, error, i=index: received(i, report, error))
        self._queue_analysis(plans, 'union', callback=lambda report, error: received(None, report, error))

    def shutdown(self):
        for job in self._relation_jobs.values():
            job['cancel']['value'] = True
        self._timer.stop(); self._thread.requestInterruption()
        self._thread.quit(); self._thread.wait()
        if self._worker._owns_pl and self._worker.pl is not None:
            self._worker.pl.close()
        if self._owns_relation_thread:
            self._relation_thread.quit(); self._relation_thread.wait()
