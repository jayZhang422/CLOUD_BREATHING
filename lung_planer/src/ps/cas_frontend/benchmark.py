"""Comparable UI timing events without patient identifiers or file paths."""

import json
import os
import platform
from datetime import datetime, timezone
from pathlib import Path
from statistics import median
from time import perf_counter_ns

from PySide6 import __version__ as pyside_version
from PySide6.QtCore import QObject, Property, Signal, Slot, Qt, qVersion


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    if not ordered:
        return 0.0
    position = (len(ordered) - 1) * fraction
    lower = int(position)
    upper = min(lower + 1, len(ordered) - 1)
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


class _WindowFrames(QObject):
    """A queued QObject slot with an identity guard for stale window events."""

    def __init__(self, recorder, rotation_only: bool):
        super().__init__(recorder)
        self.recorder = recorder
        self.rotation_only = rotation_only

    @Slot()
    def presented(self):
        # QObject.sender() can become null for events queued before disconnect.
        # Relay identity remains unambiguous, even for those delayed events.
        if self.rotation_only:
            if self.recorder._rotation_frames is self:
                self.recorder._rotation_frame_swapped()
        elif self.recorder._main_frames is self:
            self.recorder._frame_swapped()


class BenchmarkRecorder(QObject):
    changed = Signal()

    def __init__(self, project_directory: Path, stl_viewer, output_directory: Path | None = None):
        super().__init__()
        self._run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        self._case_label = os.environ.get("CLOUD_BREATHING_BENCH_CASE", "unlabeled")
        self._environment = os.environ.get("CLOUD_BREATHING_BENCH_ENV", platform.system().lower())
        self._output = (output_directory or project_directory / "data" / "benchmarks") / f"run-{self._run_id}.jsonl"
        self._window = None
        self._presentation_window = None
        self._rotation_connected_window = None
        self._main_frames = None
        self._rotation_frames = None
        self._page = None
        self._ct = {}
        self._stl_started = None
        self._stl_ready = False
        self._rotation_started = None
        self._rotation_previous = None
        self._rotation_intervals = []
        self._last_metric = ""
        self._stl_viewer = stl_viewer
        stl_viewer.loadStarted.connect(self._begin_stl_load)
        stl_viewer.rowsChanged.connect(self._stl_geometry_ready)
        stl_viewer.statusChanged.connect(self._stl_status_changed)

    outputPath = Property(str, lambda self: str(self._output), constant=True)
    lastMetric = Property(str, lambda self: self._last_metric, notify=changed)

    def attach(self, window) -> None:
        if self._window is window:
            return
        previous_main = self._window
        if self._window is not None:
            try:
                self._window.frameSwapped.disconnect(self._main_frames.presented)
            except (RuntimeError, TypeError):
                pass
            self._main_frames.deleteLater()
        self._window = window
        # Keep filesystem reporting and Python state on the GUI thread.
        self._main_frames = _WindowFrames(self, False)
        window.frameSwapped.connect(self._main_frames.presented, Qt.ConnectionType.QueuedConnection)
        if self._presentation_window is None or self._presentation_window is previous_main:
            self.attachPresentationWindow(window)

    @Slot(QObject)
    def attachPresentationWindow(self, window) -> None:
        if window is None or not hasattr(window, "frameSwapped") or window is self._presentation_window:
            return
        # Finish a measurement against its original target before switching.
        # Ordinary page/CT/STL events always remain attached to the main window.
        self.endRotation()
        if self._rotation_connected_window is not None:
            try:
                self._rotation_connected_window.frameSwapped.disconnect(self._rotation_frames.presented)
            except (RuntimeError, TypeError):
                pass
            self._rotation_frames.deleteLater()
            self._rotation_connected_window = None
            self._rotation_frames = None
        self._presentation_window = window
        if window is not self._window:
            self._rotation_frames = _WindowFrames(self, True)
            window.frameSwapped.connect(self._rotation_frames.presented, Qt.ConnectionType.QueuedConnection)
            self._rotation_connected_window = window

    def _record(self, kind: str, window=None, **fields) -> None:
        target = window if window is not None else self._window
        if target is None:
            return
        try:
            graphics_api = str(target.rendererInterface().graphicsApi()).split(".")[-1]
        except (AttributeError, RuntimeError):
            graphics_api = "unknown"
        screen = target.screen()
        event = {
            "schema": 1,
            "kind": kind,
            "utc": datetime.now(timezone.utc).isoformat(),
            "run_id": self._run_id,
            "case_label": self._case_label,
            "platform": platform.system().lower(),
            "environment": self._environment,
            "python": platform.python_version(),
            "qt": qVersion(),
            "pyside": pyside_version,
            "graphics_api": graphics_api,
            "screen_hz": round(screen.refreshRate(), 2) if screen else 0,
            "viewport": [int(target.width()), int(target.height())],
            **fields,
        }
        self._output.parent.mkdir(parents=True, exist_ok=True)
        with self._output.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
        if "duration_ms" in fields:
            self._last_metric = f"{kind}: {fields['duration_ms']:.1f} ms"
            self.changed.emit()

    @Slot(int, bool)
    def beginPageSwitch(self, page: int, cold: bool) -> None:
        self._page = (perf_counter_ns(), page, cold)

    @Slot(str, str)
    def beginCtFrame(self, plane: str, source: str) -> None:
        if source:
            self._ct[plane] = {"start": perf_counter_ns(), "source": source, "ready": False}
        else:
            self._ct.pop(plane, None)

    @Slot(str, str)
    def ctImageReady(self, plane: str, source: str) -> None:
        pending = self._ct.get(plane)
        if pending and pending["source"] == source:
            pending["ready"] = True

    @Slot()
    def _begin_stl_load(self) -> None:
        self._stl_started = perf_counter_ns()
        self._stl_ready = False

    @Slot()
    def _stl_geometry_ready(self) -> None:
        if self._stl_started is not None:
            self._stl_ready = True

    @Slot()
    def _stl_status_changed(self) -> None:
        if self._stl_started is not None and not self._stl_viewer.busy and not self._stl_ready:
            self._stl_started = None

    @Slot()
    def beginRotation(self) -> None:
        if self._rotation_started is None:
            self._rotation_started = perf_counter_ns()
            self._rotation_previous = None
            self._rotation_intervals = []

    @Slot()
    def endRotation(self) -> None:
        if self._rotation_started is None:
            return
        elapsed = (perf_counter_ns() - self._rotation_started) / 1_000_000
        intervals = self._rotation_intervals
        self._rotation_started = None
        self._rotation_previous = None
        self._rotation_intervals = []
        if intervals:
            self._record("rotation_present_intervals", duration_ms=round(elapsed, 3),
                         window=self._presentation_window,
                         frame_count=len(intervals) + 1,
                         median_ms=round(median(intervals), 3),
                         p95_ms=round(percentile(intervals, 0.95), 3),
                         max_ms=round(max(intervals), 3),
                         over_33ms=sum(value > 33.3 for value in intervals),
                         triangle_count=self._stl_viewer.triangleCount)

    @Slot()
    def _frame_swapped(self) -> None:
        now = perf_counter_ns()
        if self._presentation_window is self._window:
            self._record_rotation_frame(now)
        if self._page is not None:
            started, page, cold = self._page
            self._page = None
            self._record("page_switch_frame", duration_ms=round((now - started) / 1_000_000, 3),
                         page=page, cold=cold)
        for plane, pending in list(self._ct.items()):
            if pending["ready"]:
                self._record("ct_first_frame", duration_ms=round((now - pending["start"]) / 1_000_000, 3),
                             plane=plane)
                del self._ct[plane]
        if self._stl_started is not None and self._stl_ready:
            elapsed = (now - self._stl_started) / 1_000_000
            self._stl_started = None
            self._stl_ready = False
            timings = self._stl_viewer.loadTimings
            self._record("stl_load_frame", duration_ms=round(elapsed, 3),
                         original_faces=timings.get("original_faces", 0),
                         preview_faces=timings.get("preview_faces", 0),
                         cache_hits=timings.get("cache_hits", 0),
                         read_ms=round(timings.get("read_ms", 0), 3),
                         geometry_ms=round(timings.get("geometry_ms", 0), 3))

    @Slot()
    def _rotation_frame_swapped(self) -> None:
        self._record_rotation_frame(perf_counter_ns())

    def _record_rotation_frame(self, now: int) -> None:
        if self._rotation_started is not None:
            if self._rotation_previous is not None and len(self._rotation_intervals) < 10_000:
                self._rotation_intervals.append((now - self._rotation_previous) / 1_000_000)
            self._rotation_previous = now
