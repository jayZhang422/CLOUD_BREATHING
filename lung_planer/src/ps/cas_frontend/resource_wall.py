"""Reversible CPU-affinity profile for KV260-oriented desktop testing."""

import psutil
from PySide6.QtCore import QObject, Property, Signal, Slot


class ResourceWall(QObject):
    changed = Signal()
    enabledChanged = Signal()

    TRIANGLE_WARNING_THRESHOLD = 30_000
    LOGICAL_CORE_LIMIT = 4

    def __init__(self, process=None):
        super().__init__()
        self._process = process or psutil.Process()
        self._enabled = False
        self._original_affinity = None
        self._triangles = 0
        self._affinity_note = ""

    enabled = Property(bool, lambda self: self._enabled, notify=changed)
    overBudget = Property(bool, lambda self: self._enabled and (
        self._triangles > self.TRIANGLE_WARNING_THRESHOLD
    ), notify=changed)

    @Property(str, notify=changed)
    def status(self):
        if not self._enabled:
            return ""
        warnings = []
        if self._triangles > self.TRIANGLE_WARNING_THRESHOLD:
            warnings.append(f"高面数场景：{self._triangles:,} 面")
        if self._affinity_note:
            warnings.append(self._affinity_note)
        return "KV260 模拟 · " + (" / ".join(warnings) if warnings else "4 核 · 内存无固定上限")

    @Slot(bool)
    def setEnabled(self, enabled):
        if self._enabled == enabled:
            return
        if enabled:
            try:
                affinity = self._process.cpu_affinity()
                if len(affinity) > self.LOGICAL_CORE_LIMIT:
                    self._process.cpu_affinity(affinity[:self.LOGICAL_CORE_LIMIT])
                    self._original_affinity = affinity
                self._affinity_note = ""
            except (AttributeError, psutil.Error, OSError):
                self._affinity_note = "CPU 亲和性不可用"
        else:
            self.restore_affinity()
            self._affinity_note = ""
        self._enabled = enabled
        self.changed.emit()
        self.enabledChanged.emit()

    @Slot()
    def restore_affinity(self):
        if self._original_affinity is not None:
            try:
                self._process.cpu_affinity(self._original_affinity)
            except (AttributeError, psutil.Error, OSError):
                self._affinity_note = "CPU 亲和性恢复失败"
            else:
                self._original_affinity = None

    @Slot(int)
    def updateTriangles(self, triangles):
        if self._triangles != triangles:
            self._triangles = triangles
            if self._enabled:
                self.changed.emit()
