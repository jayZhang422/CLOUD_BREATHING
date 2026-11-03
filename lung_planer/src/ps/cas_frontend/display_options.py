"""Display-only geometry and AA policy; never alters PL/analysis inputs.

Original geometry remains attached as a reference/fallback. Work is performed
only when the extracted forest changes, never on camera updates.
"""
import os
from time import perf_counter

import numpy as np
from PySide6.QtCore import QObject, Property, QThread, Signal, Slot, Qt

from .centerlines import KINDS, tube_mesh
from .branch_presentation import displayed_branches
from .planner import PlanGeometry
from .render_buffers import prepare_mesh


def marker_mesh(points, radius=.85, rings=8, sectors=16):
    """Same radius as Qt #Sphere (50) scaled by .017; 224 triangles/ball."""
    lat = np.linspace(0, np.pi, rings + 1)
    lon = np.arange(sectors) * (2 * np.pi / sectors)
    sphere = np.stack(np.broadcast_arrays(np.sin(lat[:, None]) * np.cos(lon),
                        np.cos(lat[:, None]) + np.zeros(sectors),
                        np.sin(lat[:, None]) * np.sin(lon)), axis=-1) * radius
    triangles = []
    for i in range(rings):
        for j in range(sectors):
            k = (j + 1) % sectors
            if i > 0:
                triangles.append([sphere[i, j], sphere[i, k], sphere[i+1, j]])
            if i < rings - 1:
                triangles.append([sphere[i, k], sphere[i+1, k], sphere[i+1, j]])
    unit = np.asarray(triangles, dtype=np.float32)
    points = np.asarray(points, dtype=np.float32).reshape(-1, 3)
    return (unit[None] + points[:, None, None]).reshape(-1, 3, 3)


class DisplayWorker(QObject):
    completed = Signal(object)

    @Slot(object)
    def build(self, job):
        started = perf_counter()
        try:
            rendered, counts = [], []
            for kind in KINDS:
                segments = [pair for tree in job['trees'] if tree['kind'] == kind
                            for b in displayed_branches(tree) for pair in zip(b['points'][:-1], b['points'][1:])]
                rendered.append(prepare_mesh(tube_mesh(segments, .32, sides=4), job['center'], job['scale']))
                counts.append(len(segments))
            self.completed.emit(dict(key=job['key'], meshes=rendered, segments=counts,
                                     prepare_ms=(perf_counter()-started)*1000))
        except Exception as exc:
            self.completed.emit(dict(key=job['key'], error=str(exc)))


class DisplayOptions(QObject):
    changed = Signal()
    aaChanged = Signal()
    buildRequested = Signal(object)

    def __init__(self, controller, viewer, parent=None):
        super().__init__(parent)
        self.controller, self.viewer = controller, viewer
        self._aa = 'on' if os.environ.get('CLOUD_BREATHING_SCENE_AA', 'none') == 'ssaa' else 'off'
        self._roots = PlanGeometry(self)
        self._lines = [PlanGeometry(self) for _ in KINDS]
        self._key = None
        self._ready = False
        self._report = {}
        self._thread = QThread(self)
        self._worker = DisplayWorker()
        self._worker.moveToThread(self._thread)
        self.buildRequested.connect(self._worker.build)
        self._worker.completed.connect(self._completed, Qt.QueuedConnection)
        self._thread.finished.connect(self._worker.deleteLater)
        self._thread.start()
        controller.rootsChanged.connect(self.refresh)

    aaMode = Property(str, lambda s: s._aa, notify=aaChanged)
    rootGeometry = Property(QObject, lambda s: s._roots, constant=True)
    lineGeometries = Property('QVariantList', lambda s: s._lines, constant=True)
    ready = Property(bool, lambda s: s._ready, notify=changed)
    report = Property('QVariantMap', lambda s: s._report, notify=changed)

    @Slot(str)
    def setAAMode(self, mode):
        if mode in ('on', 'drag', 'off') and mode != self._aa:
            self._aa = mode
            self.aaChanged.emit()

    @Slot()
    def refresh(self):
        points = [(p['point'].x(), p['point'].y(), p['point'].z()) for p in self.controller.rootPoints]
        self._roots.setPrepared(prepare_mesh(marker_mesh(points), (0, 0, 0), 1))
        trees = self.controller._trees
        # Cache identity is display-only and includes changed forest identity.
        key = (self.controller._tree_revision, tuple(self.viewer.sceneCenterMm), self.viewer.sceneScale)
        if key != self._key:
            self._key, self._ready = key, False
            self.buildRequested.emit(dict(key=key, trees=trees, center=self.viewer.sceneCenterMm,
                                          scale=self.viewer.sceneScale))
        self.changed.emit()

    @Slot(object)
    def _completed(self, result):
        if result['key'] != self._key:
            return
        if 'error' in result:
            self._report = result
        else:
            for geometry, prepared in zip(self._lines, result.pop('meshes')):
                geometry.setPrepared(prepared)
            self._ready = True
            self._report = dict(segments=result['segments'], prepare_ms=result['prepare_ms'],
                                root_triangles=len(bytes(self._roots.vertexData())) // 72,
                                line_triangles=sum(result['segments']) * 8)
        self.changed.emit()

    @Slot()
    def shutdown(self):
        self._thread.quit()
        self._thread.wait()
