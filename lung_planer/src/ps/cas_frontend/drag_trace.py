"""Monotonic, revision-bound timings for one released vertex edit."""
import hashlib
import json
import logging
import os
from pathlib import Path
import platform
from threading import Lock
import time
from time import perf_counter_ns

import numpy as np


def geometry_identity(vertices):
    values = np.ascontiguousarray(vertices, dtype='<f8')
    return hashlib.sha256(values.tobytes()).hexdigest()


def capture_system_environment():
    """Capture read-only board conditions outside the measured operation."""
    def read(path):
        try:
            return Path(path).read_text().strip()
        except (OSError, UnicodeError):
            return None

    frequencies = {}
    for path in sorted(Path('/sys/devices/system/cpu/cpufreq').glob('policy*/scaling_cur_freq')):
        value = read(path)
        if value is not None:
            try:
                frequencies[path.parent.name] = int(value) * 1000
            except ValueError:
                continue

    temperatures = {}
    for path in sorted(Path('/sys/class/thermal').glob('thermal_zone*/temp')):
        value = read(path)
        if value is not None:
            try:
                temperatures[path.parent.name] = dict(
                    type=read(path.parent / 'type'), milli_celsius=int(value))
            except ValueError:
                continue

    firmware_path = os.environ.get('LUNG_PL_BIT')
    firmware = None
    if firmware_path:
        try:
            digest = hashlib.sha256()
            with Path(firmware_path).open('rb') as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(block)
            firmware = dict(path=firmware_path, sha256=digest.hexdigest())
        except OSError:
            firmware = dict(path=firmware_path, sha256=None)

    processes = []
    proc = Path('/proc')
    if proc.is_dir():
        for path in proc.iterdir():
            if path.name.isdigit():
                name = read(path / 'comm')
                if name and any(token in name.lower() for token in ('python', 'cloud-breathing', 'pl_server')):
                    processes.append(dict(pid=int(path.name), name=name))

    return dict(
        wall_time_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        wall_time_local=time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        monotonic_ns=perf_counter_ns(),
        os=platform.platform(),
        cpu_count=os.cpu_count(),
        cpu_online=read('/sys/devices/system/cpu/online'),
        cpu_frequency_hz=frequencies,
        temperatures=temperatures,
        loadavg=read('/proc/loadavg'),
        desktop=dict(qt_qpa_platform=os.environ.get('QT_QPA_PLATFORM'),
                     display=os.environ.get('DISPLAY'),
                     wayland_display=os.environ.get('WAYLAND_DISPLAY'),
                     xdg_session_type=os.environ.get('XDG_SESSION_TYPE')),
        relevant_processes=processes,
        firmware=firmware)


class DragTrace:
    def __init__(self, revision, vertices, release_ns=None):
        self.release_ns = perf_counter_ns() if release_ns is None else release_ns
        self.revision = int(revision)
        self.geometry_id = geometry_identity(vertices)
        self._events = []
        self._lock = Lock()

    def mark(self, name, *, at_ns=None, **fields):
        now = perf_counter_ns() if at_ns is None else at_ns
        with self._lock:
            row = dict(event=name, monotonic_ns=now,
                       elapsed_ms=(now-self.release_ns)/1_000_000,
                       revision=self.revision, geometry_id=self.geometry_id, **fields)
            self._events.append(row)
        return row

    def set_revision(self, revision):
        with self._lock:
            self.revision = int(revision)
            for row in self._events:
                row['revision'] = self.revision

    def snapshot(self):
        with self._lock:
            events = sorted((dict(row) for row in self._events),
                            key=lambda row: row['monotonic_ns'])
            revision = self.revision
        return dict(revision=revision, geometry_id=self.geometry_id,
                    clock='perf_counter_ns', events=events)

    def log_snapshot(self, boundary):
        snapshot = self.snapshot()
        snapshot['boundary'] = boundary
        logging.getLogger(__name__).warning(
            'DRAG_TRACE %s', json.dumps(snapshot, ensure_ascii=False, separators=(',', ':')))
