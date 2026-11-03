"""Resource sampling with independently paced status-bar publication.

Sampling stays at 1.5 seconds. Published numbers are a separate snapshot at
the precision displayed by QML; process RSS and system available RAM are
telemetry only and do not impose an application memory limit. The existing
psutil probes remain synchronous on the GUI thread in this step.
"""

import os
from time import monotonic

import psutil
from PySide6.QtCore import QObject, Property, QTimer, Signal, Slot


class PerformanceMonitor(QObject):
    changed = Signal()
    sampled = Signal(float)

    SAMPLE_INTERVAL_MS = 1500
    RENDER_PUBLISH_INTERVAL_MS = 4500

    def __init__(self, parent=None, *, sampling_enabled=True, publication_mode=None):
        super().__init__(parent)
        self._sampling_enabled = bool(sampling_enabled)
        mode = publication_mode or os.environ.get("CLOUD_BREATHING_PERF_PUBLICATION", "throttled")
        if mode not in ("baseline", "throttled"):
            raise ValueError("CLOUD_BREATHING_PERF_PUBLICATION must be baseline or throttled")
        self._publication_mode = mode
        self._presentation_visible = True
        self._render_active = False
        self._sample_count = 0
        self._publication_count = 0
        self._presentation_change_count = 0
        self._started_at = monotonic()
        self._last_sample_time = None
        self._last_sample_duration_ms = None
        self._last_publication_time = None
        self._published_signature = None
        self._process = None
        self._core_count = 1
        self._cpu_percent = 0.0
        self._memory_mb = 0.0
        self._system_cpu_percent = 0.0
        self._system_memory_percent = 0.0
        self._system_available_memory_mb = 0.0
        self._thread_count = 0
        self._read_mb_s = 0.0
        self._write_mb_s = 0.0
        self._available = False
        self._latest_sample = None
        self._last_time = monotonic()
        self._last_io = None
        self._timer = None
        # Tests may pause telemetry before any process probes or timer work.
        # The context object remains present so normal QML bindings are valid.
        if not self._sampling_enabled:
            return
        self._process = psutil.Process()
        self._core_count = psutil.cpu_count(logical=True) or 1
        self._last_io = self._io_counters()
        self._process.cpu_percent(interval=None)
        psutil.cpu_percent(interval=None)
        self._timer = QTimer(self)
        self._timer.setInterval(self.SAMPLE_INTERVAL_MS)
        self._timer.timeout.connect(self._sample)
        self._timer.start()
        self._sample()

    cpuPercent = Property(float, lambda self: self._cpu_percent, notify=changed)
    memoryMb = Property(float, lambda self: self._memory_mb, notify=changed)
    systemCpuPercent = Property(float, lambda self: self._system_cpu_percent, notify=changed)
    systemMemoryPercent = Property(float, lambda self: self._system_memory_percent, notify=changed)
    systemAvailableMemoryMb = Property(float, lambda self: self._system_available_memory_mb, notify=changed)
    threadCount = Property(int, lambda self: self._thread_count, notify=changed)
    readMbS = Property(float, lambda self: self._read_mb_s, notify=changed)
    writeMbS = Property(float, lambda self: self._write_mb_s, notify=changed)
    available = Property(bool, lambda self: self._available, notify=changed)
    samplingEnabled = Property(bool, lambda self: self._sampling_enabled, constant=True)
    samplingActive = Property(bool, lambda self: self._timer is not None and self._timer.isActive(), notify=changed)

    @Slot(bool, bool)
    def setPresentationState(self, visible, render_active):
        """Pace telemetry only; never change application or renderer FPS."""
        previous_visible = self._presentation_visible
        previous_interval = self._publish_interval_ms()
        state = (bool(visible), bool(render_active))
        if state == (self._presentation_visible, self._render_active):
            return
        self._presentation_visible, self._render_active = state
        self._presentation_change_count += 1
        # Restoring the window or leaving a 3D page shows the latest sample
        # immediately rather than waiting for another sampling deadline.
        if self._presentation_visible and (not previous_visible or self._publish_interval_ms() < previous_interval):
            self._publish()

    @Slot()
    def requestPublication(self):
        """Explicit refresh for a user action, without another psutil probe."""
        self._publish()

    def _publish_interval_ms(self):
        if self._publication_mode == "throttled" and self._render_active:
            return self.RENDER_PUBLISH_INTERVAL_MS
        return self.SAMPLE_INTERVAL_MS

    @Slot(result="QVariantMap")
    def getPublicationDiagnostics(self):
        def elapsed_ms(value):
            return None if value is None else (value - self._started_at) * 1000.0

        return {
            "publication_mode": self._publication_mode,
            "sample_interval_ms": self.SAMPLE_INTERVAL_MS,
            "publish_interval_ms": self._publish_interval_ms(),
            "presentation_visible": self._presentation_visible,
            "render_active": self._render_active,
            "sample_count": self._sample_count,
            "publication_count": self._publication_count,
            "presentation_change_count": self._presentation_change_count,
            "last_sample_elapsed_ms": elapsed_ms(self._last_sample_time),
            "last_publication_elapsed_ms": elapsed_ms(self._last_publication_time),
            "last_sample_monotonic_ms": None if self._last_sample_time is None else self._last_sample_time * 1000.0,
            "last_publication_monotonic_ms": None if self._last_publication_time is None else self._last_publication_time * 1000.0,
            "last_sample_duration_ms": self._last_sample_duration_ms,
            "sampling_thread": "gui",
        }

    def _publish(self):
        if self._latest_sample is None:
            return
        # Match the precision already used by the status bar. Both A/B modes
        # use this same quantization; their only difference is publication pace.
        sample = self._latest_sample
        values = (
            round(sample["cpu_percent"], 1), round(sample["memory_mb"]),
            round(sample["system_cpu_percent"]), round(sample["system_memory_percent"]),
            round(sample["system_available_memory_mb"]),
            sample["thread_count"], round(sample["read_mb_s"], 1), round(sample["write_mb_s"], 1),
            sample["available"],
        )
        # A no-change publish attempt still consumes its deadline. Otherwise
        # it would allow a later sample to appear sooner than the chosen pace.
        self._last_publication_time = monotonic()
        if values == self._published_signature:
            return
        (self._cpu_percent, self._memory_mb, self._system_cpu_percent,
         self._system_memory_percent, self._system_available_memory_mb,
         self._thread_count, self._read_mb_s,
         self._write_mb_s, self._available) = values
        self._published_signature = values
        self._publication_count += 1
        self.changed.emit()

    def _io_counters(self):
        try:
            return self._process.io_counters()
        except (AttributeError, psutil.Error, OSError):
            return None

    def _sample(self):
        if not self._sampling_enabled:
            return
        started_at = monotonic()
        try:
            now = monotonic()
            elapsed = max(now - self._last_time, 0.001)
            io = self._io_counters()
            virtual_memory = psutil.virtual_memory()
            sample = {
                "cpu_percent": self._process.cpu_percent(interval=None) / self._core_count,
                "memory_mb": self._process.memory_info().rss / (1024 * 1024),
                "system_cpu_percent": psutil.cpu_percent(interval=None),
                "system_memory_percent": virtual_memory.percent,
                "system_available_memory_mb": virtual_memory.available / (1024 * 1024),
                "thread_count": self._process.num_threads(),
                "read_mb_s": 0.0, "write_mb_s": 0.0, "available": True,
            }
            if io is not None and self._last_io is not None:
                sample["read_mb_s"] = max(io.read_bytes - self._last_io.read_bytes, 0) / elapsed / (1024 * 1024)
                sample["write_mb_s"] = max(io.write_bytes - self._last_io.write_bytes, 0) / elapsed / (1024 * 1024)
            self._last_time = now
            self._last_io = io
        except (psutil.Error, OSError):
            # Keep the last numeric readings but report provider failure now.
            sample = dict(self._latest_sample or {
                "cpu_percent": 0.0, "memory_mb": 0.0, "system_cpu_percent": 0.0,
                "system_memory_percent": 0.0, "system_available_memory_mb": 0.0,
                "thread_count": 0,
                "read_mb_s": 0.0, "write_mb_s": 0.0,
            })
            sample["available"] = False
            now = monotonic()
        self._latest_sample = sample
        self._last_sample_time = now
        self._last_sample_duration_ms = (monotonic() - started_at) * 1000.0
        self._sample_count += 1
        if sample["available"]:
            self.sampled.emit(sample["memory_mb"])
        critical_change = sample["available"] != self._available
        # QTimer is a coarse timer by default and may fire up to 5% early.
        # Allow that scheduling tolerance so 1500/4500 ms are not accidentally
        # doubled by an early timeout. Publication still occurs only on samples.
        due = self._last_publication_time is None or (now - self._last_publication_time) * 1000.0 >= self._publish_interval_ms() * 0.95
        if critical_change or (self._presentation_visible and due):
            self._publish()
