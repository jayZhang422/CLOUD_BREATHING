"""Frontend load adapter: focus lesion lobes without modifying PL release code."""
from PySide6.QtCore import QObject, Property, Signal, Slot

from .lobe_focus import find_lobe_focus
from .stl import StlViewer


class LobeFocusPreparation(QObject):
    completed = Signal(object)

    @Slot(object)
    def prepare(self, payload):
        surfaces, _, _, _, timings = payload
        try:
            timings['lobe_focus'] = find_lobe_focus([(name, vertices) for name, vertices, _, _ in surfaces])
            timings['worker_ms'] += timings['lobe_focus']['elapsed_ms']
        except Exception as exc:
            # A display convenience must never discard the patient's models.
            timings['lobe_focus'] = dict(selected=[], lobes=[], error=str(exc))
        self.completed.emit(payload)


class FocusedStlViewer(StlViewer):
    focusReportChanged = Signal()
    manualOpacityChanged = Signal()
    def __init__(self, cache_directory=None):
        super().__init__(cache_directory)
        self._focus_report = {}
        self._manual_opacity_names = []
        self._focus_preparation = LobeFocusPreparation()
        self._focus_preparation.moveToThread(self._thread)
        self._worker.completed.disconnect(self._completed)
        self._worker.completed.connect(self._focus_preparation.prepare)
        self._focus_preparation.completed.connect(self._completed)
        self._thread.finished.connect(self._focus_preparation.deleteLater)

    focusReport = Property('QVariantMap', lambda s: s._focus_report, notify=focusReportChanged)
    manualOpacityNames = Property('QStringList', lambda s: s._manual_opacity_names, notify=manualOpacityChanged)

    @Slot(int, float)
    def setOpacity(self, index, opacity):
        if not 0 <= index < len(self._rows):
            return
        name = self._rows[index].name
        if name not in self._manual_opacity_names:
            self._manual_opacity_names.append(name)
            self.manualOpacityChanged.emit()
        super().setOpacity(index, opacity)

    @Slot(object)
    def _completed(self, payload):
        self._manual_opacity_names = []
        self.manualOpacityChanged.emit()
        self._focus_report = payload[4].get('lobe_focus', {})
        self.focusReportChanged.emit()
        super()._completed(payload)
        located = self._focus_report.get('selected_lobes', [])
        if located:
            # Report only: every lobe keeps its default opacity on load.
            self._status += ' · 病灶所在肺叶：' + '、'.join(located)
        if self._focus_report.get('unlocated'):
            self._status += ' · 病灶不在已识别的肺叶内'
        elif not located and self._focus_report.get('error'):
            self._status += ' · 肺叶定位失败，保留全部显示'
        print('STL_LOBE_FOCUS:', self._focus_report, flush=True)
        self.statusChanged.emit()
