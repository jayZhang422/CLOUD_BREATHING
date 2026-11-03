"""Optional, system-wide GPU utilization providers."""

import os
import re
import shutil
import subprocess
from pathlib import Path

from PySide6.QtCore import QObject, Property, QThread, QTimer, Signal, Slot


def _gpu_source():
    configured = os.environ.get("CLOUD_BREATHING_GPU_LOAD_PATH")
    if configured:
        path = Path(configured)
        return ("sysfs", path) if path.is_file() else None
    executable = shutil.which("nvidia-smi")
    if not executable and Path("/usr/lib/wsl/lib/nvidia-smi").is_file():
        executable = "/usr/lib/wsl/lib/nvidia-smi"
    if executable:
        return "nvidia-smi", executable
    devfreq = Path("/sys/class/devfreq")
    if devfreq.is_dir():
        for path in devfreq.glob("*/load"):
            if any(token in path.parent.name.lower() for token in ("gpu", "mali")):
                return "sysfs", path
    return None


def read_gpu_percent(source) -> float:
    kind, target = source
    if kind == "nvidia-smi":
        completed = subprocess.run(
            [target, "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, check=True, timeout=2,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        values = [float(line.strip()) for line in completed.stdout.splitlines() if line.strip()]
        if not values:
            raise ValueError("GPU driver returned no utilization")
        value = max(values)
    else:
        raw = Path(target).read_text(encoding="ascii").strip()
        if not re.fullmatch(r"\d+(?:\.\d+)?%?", raw):
            raise ValueError("GPU load file must contain a percentage")
        value = float(raw.rstrip("%"))
    if not 0 <= value <= 100:
        raise ValueError("GPU utilization is outside 0-100%")
    return value


class GpuWorker(QObject):
    sampled = Signal(object)

    def __init__(self, source):
        super().__init__()
        self.source = source

    @Slot()
    def sample(self):
        try:
            self.sampled.emit(read_gpu_percent(self.source))
        except (OSError, ValueError, subprocess.SubprocessError):
            self.sampled.emit(None)


class GpuMonitor(QObject):
    changed = Signal()
    sampleRequested = Signal()

    def __init__(self, parent=None, *, sampling_enabled=True):
        super().__init__(parent)
        self._sampling_enabled = bool(sampling_enabled)
        self._source = None
        self._percent = 0.0
        self._available = False
        self._pending = False
        self._thread = None
        self._timer = None
        if not self._sampling_enabled:
            return
        self._source = _gpu_source()
        if self._source is None:
            return
        self._thread = QThread(self)
        self._worker = GpuWorker(self._source)
        self._worker.moveToThread(self._thread)
        self.sampleRequested.connect(self._worker.sample)
        self._worker.sampled.connect(self._sampled)
        self._thread.start()
        self._timer = QTimer(self)
        self._timer.setInterval(3000)
        self._timer.timeout.connect(self._request_sample)
        self._timer.start()
        self._request_sample()

    percent = Property(float, lambda self: self._percent, notify=changed)
    available = Property(bool, lambda self: self._available, notify=changed)
    samplingEnabled = Property(bool, lambda self: self._sampling_enabled, constant=True)
    samplingActive = Property(bool, lambda self: self._timer is not None and self._timer.isActive(), notify=changed)

    def _request_sample(self):
        if self._sampling_enabled and self._source is not None and not self._pending:
            self._pending = True
            self.sampleRequested.emit()

    @Slot(object)
    def _sampled(self, value):
        self._pending = False
        previous = (self._available, self._percent)
        self._available = value is not None
        if value is not None:
            self._percent = value
        if previous != (self._available, self._percent):
            self.changed.emit()

    def shutdown(self):
        if self._timer is not None:
            self._timer.stop()
        if self._thread is not None:
            self._thread.quit()
            self._thread.wait(3000)
