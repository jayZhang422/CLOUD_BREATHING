"""PYNQ bridge for the existing lung_metrics AXI/DMA PL block.

The Qt application remains usable on a PC and on a board without PYNQ.  On a
KV260 the overlay is loaded once per planning worker and reused for subsequent
interactive evaluations. The point ABI computes coverage and signed clearance.
The separately discovered mesh ABI computes float64 dual-plane intersection
volume and surface/cut area.
"""
import asyncio
import hashlib
import logging
import os
import json
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

import numpy as np


def _hardware_locked(method):
    """Serialize MMIO/DMA transactions while allowing recovery to re-enter."""
    def wrapped(self, *args, **kwargs):
        with self._hardware_lock:
            return method(self, *args, **kwargs)
    wrapped.__name__ = method.__name__
    wrapped.__doc__ = method.__doc__
    return wrapped


METRICS_BASE = 0xA0010000
METRICS_RANGE = 0x1000
ABI_VERSION = 0x00010000
MAGIC = 0x4C504C31
CONTROL = 0x000
POINT_COUNT = 0x004
MARGIN_Q16 = 0x008
JOB_ID = 0x00C
VERSION = 0x014
ERRORS = 0x018
IRQ_ACK = 0x01C
PLANES = 0x100
MESH_RAY_BASE = 0xA0040000
MESH_RAY_RANGE = 0x1000
MESH_RAY_ABI_VERSION = 0x00030000
MESH_RAY_BVH_ABI_VERSION = 0x00040000
MESH_RAY_VOLUME_ABI_VERSION = 0x00050000
MESH_DISTANCE_ABI_VERSION = 0x00060000
MESH_UNION_ABI_VERSION = 0x00070000
MESH_RAY_COMPAT_ABI_VERSIONS = (0x00020000, MESH_RAY_ABI_VERSION, MESH_RAY_BVH_ABI_VERSION, MESH_RAY_VOLUME_ABI_VERSION, MESH_DISTANCE_ABI_VERSION, MESH_UNION_ABI_VERSION)
DUAL_PLANE_BASE = 0xA0011000
DUAL_PLANE_RANGE = 0x1000
DUAL_PLANE_ABI_VERSION = 0x00030000
DUAL_PLANE_DMA_CHUNK_BYTES = 16368
# Mesh clipping/volume ABI.  The descriptor stream is intentionally separate
# from the point-only ABI so an older point-filter-only bitstream can never be mistaken for a
# geometry-capable accelerator.
DUAL_PLANE_MESH_ABI_VERSION = 0x00050000
DUAL_PLANE_MESH_BASE = 0xA0012000
DUAL_PLANE_MESH_RANGE = 0x1000
DUAL_MESH_CONTROL = 0x000
DUAL_MESH_TRIANGLE_COUNT = 0x004
DUAL_MESH_CANDIDATE_COUNT = 0x008
DUAL_MESH_JOB_ID = 0x00c
DUAL_MESH_VERSION = 0x014
DUAL_MESH_ERRORS = 0x018
DUAL_MESH_MESH_LO = 0x020
DUAL_MESH_MESH_HI = 0x024
DUAL_MESH_CANDIDATES_LO = 0x028
DUAL_MESH_CANDIDATES_HI = 0x02c
DUAL_MESH_SEGMENTS_LO = 0x030
DUAL_MESH_SEGMENTS_HI = 0x034
DUAL_MESH_RESULTS_LO = 0x038
DUAL_MESH_RESULTS_HI = 0x03c
DUAL_MESH_SEGMENT_CAPACITY = 0x040
DUAL_MESH_RESULT_COUNT = 0x044
DUAL_MESH_CYCLES = 0x048
DUAL_MESH_SEGMENT_BYTES = 64
DUAL_MESH_RESULT_BYTES = 64


def dual_plane_dma_chunks(payload_bytes):
    payload_bytes = int(payload_bytes)
    if payload_bytes < 0:
        raise ValueError('dual-plane DMA payload size cannot be negative')
    return [(begin, min(DUAL_PLANE_DMA_CHUNK_BYTES, payload_bytes - begin))
            for begin in range(0, payload_bytes, DUAL_PLANE_DMA_CHUNK_BYTES)]


def _q16(value):
    value = float(value)
    raw = int(round(value * 65536.0))
    if raw < -0x80000000 or raw > 0x7FFFFFFF:
        raise ValueError("value is outside signed Q16.16 range")
    return raw


def _signed32(value):
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def _pynq_site_candidates():
    configured = os.environ.get("PYNQ_SITE_PACKAGES")
    candidates = [configured] if configured else []
    candidates.extend((
        "/usr/local/share/pynq-venv/lib/python3.10/site-packages",
        "/usr/local/share/pynq-venv/lib/python3.11/site-packages",
    ))
    # PYNQ's venv may inherit /usr/lib/python3/dist-packages. A single
    # site-packages directory loses system-installed cffi/dffi dependencies.
    # Ask the working interpreter for its package directories, while keeping
    # the Qt environment first (in particular its tested NumPy version).
    interpreter = Path(os.environ.get('PYNQ_PYTHON', '/usr/local/share/pynq-venv/bin/python'))
    if interpreter.is_file():
        try:
            output = subprocess.check_output([str(interpreter), '-c',
                'import json,sys; print(json.dumps(dict(version=list(sys.version_info[:2]), '
                'paths=sys.path)))'], text=True, timeout=10)
            info = json.loads(output)
            if info['version'] == list(sys.version_info[:2]):
                candidates.extend(path for path in info['paths']
                                  if path and ('site-packages' in Path(path).parts
                                               or 'dist-packages' in Path(path).parts))
        except (OSError, ValueError, KeyError, subprocess.SubprocessError):
            pass
    candidates = list(dict.fromkeys(candidates))
    return [Path(path) for path in candidates if path]


def _import_pynq():
    # Defer real optional notebook and XSA tool modules until first access.
    # HWH parsing, device programming, MMIO and DMA remain eager.
    import importlib.machinery
    import importlib.util

    class OptionalToolsFinder:
        def find_spec(self, fullname, path=None, target=None):
            if fullname not in ('pynqmetadata.frontends.visualisations',
                                'pynqutils.build_utils'):
                return None
            spec = importlib.machinery.PathFinder.find_spec(fullname, path)
            if spec is not None and hasattr(spec.loader, 'exec_module'):
                spec.loader = importlib.util.LazyLoader(spec.loader)
            return spec

    finder = OptionalToolsFinder()
    sys.meta_path.insert(0, finder)
    try:
        try:
            from pynq import Overlay, allocate
            from pynq.mmio import MMIO
        except (ImportError, OSError):
            for path in _pynq_site_candidates():
                if path.is_dir() and str(path) not in sys.path:
                    sys.path.append(str(path))
            from pynq import Overlay, allocate
            from pynq.mmio import MMIO
        return Overlay, allocate, MMIO
    finally:
        sys.meta_path.remove(finder)


class PlMetrics:
    """Persistent, optional client for lung_metrics_axi."""

    def __init__(self, *, require_strict_pl=False):
        self.require_strict_pl = require_strict_pl
        self.clock_mhz = None
        self._hardware_lock = threading.RLock()
        self._overlay = None
        self._dma = None
        self._mmio = None
        # The ray batch path is owned by this same overlay/service. Keeping
        # its DMA and buffers here prevents two PYNQ Overlay instances from
        # competing for the KV260 fabric.
        self._ray_dma = None
        self._ray_mmio = None
        self._ray_input_buf = None
        self._ray_output_buf = None
        self._ray_capacity = 0
        self._ray_job_id = 0
        self._mesh_mmio = None
        self._mesh_dma = None
        self._mesh_ray_dma = None
        self._mesh_result_dma = None
        self._mesh_ddr_mode = False
        self._mesh_buf = None
        self._bvh_buf = None
        self._mesh_image = None
        self._mesh_metadata = False
        self._mesh_complete = False
        self._mesh_volume = False
        self._mesh_result_stride = 16
        self._mesh_ray_input_buf = None
        self._mesh_result_buf = None
        self._mesh_io_pool = {}
        self._mesh_capacity = 0
        self._mesh_ray_capacity = 0
        self._mesh_key = None
        self._mesh_job_id = 0
        self._point_buf = None
        self._result_buf = None
        self._point_capacity = 0
        self._packed_points_cache = None
        self._job_id = 0
        self._load_seconds = 0.0
        self._centerline_dma = self._centerline_mmio = None
        self._centerline_buffers = []
        self._dual_dma = self._dual_mmio = None
        self._dual_input_buf = self._dual_output_buf = None
        self._dual_capacity = 0
        self._dual_job_id = 0
        self._dual_points_hardware_key = None
        self._dual_mesh_mmio = self._dual_mesh_dma = None
        self._dual_mesh_key = None
        self._dual_mesh_buf = self._dual_mesh_candidates_buf = None
        self._dual_mesh_segments_buf = self._dual_mesh_results_buf = None
        self._dual_mesh_job_id = 0
        self._dual_mesh_bvh_buf = None
        self._dual_mesh_image = None
        self._dual_mesh_source = None
        self._dual_mesh_frontend_source = None
        self._dual_mesh_mmio = None
        self._dual_mesh_dma = None
        self._dual_mesh_key = None
        self._event_loop = None
        self._privileged = None
        self._hardware_reset_failed = False
        self.last_error = ""

    def _reset_hardware_state(self):
        """Drop DMA buffers and the Overlay so the next call starts cleanly."""
        # PYNQ stop() waits for HALTED and can hang under stream backpressure.
        # Submit Run/Stop=0 directly; fabric download below is the completion
        # barrier before any CMA buffer is released.
        for channel_owner in (self._dma, self._ray_dma, self._mesh_dma,
                              self._mesh_ray_dma, self._mesh_result_dma, self._centerline_dma):
            for channel_name in ('sendchannel', 'recvchannel'):
                channel = getattr(channel_owner, channel_name, None)
                if channel is not None:
                    try:
                        dma_mmio = getattr(channel, '_mmio', None)
                        dma_offset = getattr(channel, '_offset', None)
                        if dma_mmio is not None and dma_offset in (0, 0x30):
                            dma_mmio.write(dma_offset, 0)
                        elif self._overlay is None:
                            channel.stop()
                    except Exception:
                        pass
        # Reset the fabric master before releasing any DDR memory it could
        # still access after a stalled/aborted read transaction.
        if self._overlay is not None and callable(getattr(self._overlay, 'download', None)):
            self._hardware_reset_failed = True
            self._overlay.download()
        self._hardware_reset_failed = False
        for buffer in (self._point_buf, self._result_buf,
                       self._ray_input_buf, self._ray_output_buf,
                       self._dual_input_buf, self._dual_output_buf,
                       self._dual_mesh_buf, self._dual_mesh_candidates_buf,
                       self._dual_mesh_segments_buf, self._dual_mesh_results_buf,
                       self._dual_mesh_bvh_buf,
                       self._mesh_buf, self._mesh_ray_input_buf,
                       self._mesh_result_buf, self._bvh_buf,
                       *self._centerline_buffers,
                       *(buffer for pair in self._mesh_io_pool.values() for buffer in pair)):
            if buffer is not None:
                try:
                    buffer.freebuffer()
                except Exception:
                    pass
        self._point_buf = self._result_buf = None
        self._ray_input_buf = self._ray_output_buf = None
        self._point_capacity = self._ray_capacity = 0
        self._mesh_buf = self._mesh_ray_input_buf = self._mesh_result_buf = None
        self._mesh_io_pool.clear()
        self._mesh_capacity = self._mesh_ray_capacity = 0
        self._mesh_key = None
        self._bvh_buf = self._mesh_image = None
        self._mesh_metadata = False
        self._mesh_complete = False
        self._mesh_volume = False
        self._mesh_result_stride = 16
        self._mesh_ddr_mode = False
        self._overlay = self._dma = self._mmio = None
        self._ray_dma = self._ray_mmio = None
        self._mesh_mmio = self._mesh_dma = self._mesh_ray_dma = self._mesh_result_dma = None
        self._centerline_dma = self._centerline_mmio = None
        self._centerline_buffers = []
        self._dual_dma = self._dual_mmio = None
        self._dual_input_buf = self._dual_output_buf = None
        self._dual_capacity = 0
        self._dual_points_hardware_key = None
        self._dual_mesh_mmio = self._dual_mesh_dma = None
        self._dual_mesh_key = None
        self._dual_mesh_buf = self._dual_mesh_candidates_buf = None
        self._dual_mesh_segments_buf = self._dual_mesh_results_buf = None
        self._dual_mesh_job_id = 0
        self._dual_mesh_bvh_buf = None
        self._dual_mesh_image = None
        self._dual_mesh_source = None
        self._dual_mesh_frontend_source = None

    @property
    def configured(self):
        mode = os.environ.get("LUNG_PL_ENABLE", "auto").strip().lower()
        return mode not in ("0", "false", "off", "no")

    @property
    def bit_path(self):
        configured = os.environ.get("LUNG_PL_BIT")
        if configured:
            return Path(configured)
        return Path(__file__).resolve().parents[1] / "fpga" / "lung_planner.bit"

    @property
    def status(self):
        if self._privileged is not None and not self.last_error:
            return 'ready'
        if self._overlay is not None:
            return "ready"
        if self.last_error:
            return "unavailable"
        return "not_loaded"

    def prepare(self):
        """Authorize and check hardware access before expensive geometry work."""
        try:
            if not self.configured:
                if self.require_strict_pl:
                    raise RuntimeError('PL disabled; strict PL cannot fall back to CPU')
                return
            if sys.platform == 'linux' and os.geteuid() != 0:
                from .pl_privileged import PrivilegedPlClient
                if self._privileged is None:
                    self._privileged = PrivilegedPlClient(self.bit_path, require_strict_pl=self.require_strict_pl)
                confirmation = self._privileged.prepare()
                if self.require_strict_pl:
                    self.clock_mhz = confirmation['clock_mhz']
            elif self.require_strict_pl:
                self._load()
            self.last_error = ''
        except Exception as exc:
            self.last_error = str(exc)
            logging.getLogger(__name__).exception('PL_PREPARE_FAILED')
            if self.require_strict_pl:
                raise RuntimeError('Strict PL startup failed: ' + str(exc)) from exc

    def _load(self):
        if self._hardware_reset_failed:
            self._reset_hardware_state()
        # Qt-created QThreads appear as Dummy-* to Python. PYNQ's interrupt
        # setup uses asyncio.get_event_loop(), which only has a default loop
        # on the main thread. Register one on the calling worker before any
        # PYNQ import/Overlay/IP initialization. DMA below still uses polling;
        # it does not call wait_async() or run this loop alongside Qt.
        try:
            loop = asyncio.get_event_loop()
        except RuntimeError:
            loop = None
        if loop is None or loop.is_closed():
            self._event_loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._event_loop)
        if self._overlay is not None:
            return
        if not self.configured:
            raise RuntimeError("PL disabled by LUNG_PL_ENABLE")
        bit = self.bit_path
        if not bit.is_file():
            raise FileNotFoundError("PL bitstream not found: " + str(bit))
        Overlay, allocate, MMIO = _import_pynq()
        started = time.perf_counter()
        overlay = Overlay(str(bit), download=True, ignore_version=True)
        if self.require_strict_pl or getattr(overlay, 'dual_plane_mesh', None) is not None:
            # The delivered implementation is timed at 100 MHz. Overlay's HWH
            # may request 150 MHz: correct it before initializing/running DMA,
            # including direct mesh acceptance clients without require_strict_pl.
            from pynq import Clocks
            Clocks.fclk0_mhz = 100.0
            self.clock_mhz = float(Clocks.fclk0_mhz)
            if abs(self.clock_mhz - 100.0) > 1.0:
                raise RuntimeError('PL clock could not be set to 100 MHz')
        # The legacy metrics/ray cores are absent from dual-plane-only overlays,
        # so they are discovered by name and stay None there.
        dma = getattr(overlay, "dma", None)
        mmio = None
        if dma is not None:
            mmio = MMIO(METRICS_BASE, METRICS_RANGE)
            if mmio.read(VERSION) != ABI_VERSION:
                raise RuntimeError("lung_metrics ABI version mismatch")
        elif getattr(overlay, 'dual_plane_mesh', None) is None and getattr(overlay, 'centerline_dma', None) is None:
            raise RuntimeError("overlay has no DMA named 'dma'")
        self._overlay, self._dma, self._mmio = overlay, dma, mmio
        self._ray_dma = getattr(overlay, "ray_dma", None)
        if self._ray_dma is not None:
            self._ray_mmio = MMIO(0xA0030000, 0x1000)
        # Optional mesh-resident ray path.  It is intentionally discovered by
        # name so old overlays remain usable through the legacy ray_dma IP.
        self._mesh_mmio = None
        self._mesh_dma = getattr(overlay, "mesh_dma", None)
        self._mesh_ray_dma = getattr(overlay, "mesh_ray_dma", None)
        self._mesh_result_dma = getattr(overlay, "mesh_result_dma", None)
        if (self._mesh_ray_dma is not None and self._mesh_result_dma is not None):
            self._mesh_mmio = MMIO(MESH_RAY_BASE, MESH_RAY_RANGE)
            abi = self._mesh_mmio.read(0x02C)
            if abi not in MESH_RAY_COMPAT_ABI_VERSIONS:
                self._mesh_mmio = None
            elif abi == MESH_UNION_ABI_VERSION and not (self._mesh_mmio.read(0x050) & 64):
                self._mesh_mmio = None
            else:
                self._mesh_ddr_mode = abi in (MESH_RAY_ABI_VERSION, MESH_RAY_BVH_ABI_VERSION, MESH_RAY_VOLUME_ABI_VERSION, MESH_DISTANCE_ABI_VERSION, MESH_UNION_ABI_VERSION)
                self._mesh_complete = abi in (MESH_RAY_BVH_ABI_VERSION, MESH_RAY_VOLUME_ABI_VERSION, MESH_DISTANCE_ABI_VERSION, MESH_UNION_ABI_VERSION) and (self._mesh_mmio.read(0x050) & 12) == 12
                self._mesh_volume = abi in (MESH_RAY_VOLUME_ABI_VERSION, MESH_DISTANCE_ABI_VERSION, MESH_UNION_ABI_VERSION) and bool(self._mesh_mmio.read(0x050) & 16)
                if self._mesh_volume and self._mesh_mmio.read(0x07c) != 30:
                    raise RuntimeError('unsupported PL fraction format')
                self._mesh_result_stride = self._mesh_mmio.read(0x064) if self._mesh_complete else 16
                if self._mesh_complete and (self._mesh_result_stride != 576 or self._mesh_mmio.read(0x060) != 128):
                    raise RuntimeError("unsupported BVH crossing frame configuration")
                self._mesh_metadata = self._mesh_ddr_mode and bool(self._mesh_mmio.read(0x050) & 2)
        dual_plane_only = (getattr(overlay, 'mesh_ray', None) is None
                           and getattr(overlay, 'dual_plane_mesh', None) is not None)
        if (self.require_strict_pl and not dual_plane_only
                and not (self._mesh_complete and self._mesh_metadata and self._mesh_ddr_mode)):
            self._overlay = None
            raise RuntimeError('Strict PL requires ABI 0x00040000 and complete crossings')
        self._load_seconds = time.perf_counter() - started
        self._centerline_dma = getattr(overlay, 'centerline_dma', None)
        self._centerline_mmio = None
        if self._centerline_dma is not None:
            self._centerline_mmio = MMIO(0xA0090000, 0x1000)
            if (self._centerline_mmio.read(4) != 0x434c4431
                    or self._centerline_mmio.read(8) != 0x00010000
                    or self._centerline_mmio.read(12) & 7 != 7):
                raise RuntimeError('Centreline distance ABI/capability mismatch')
        self._dual_dma = getattr(overlay, 'dual_plane_dma', None)
        self._dual_mmio = None
        dual_filter = getattr(overlay, 'dual_plane_filter', None)
        if self._dual_dma is not None and dual_filter is not None:
            candidate = MMIO(DUAL_PLANE_BASE, DUAL_PLANE_RANGE)
            if candidate.read(0x014) == DUAL_PLANE_ABI_VERSION:
                self._dual_mmio = candidate
        # Mesh ABI 0x00050000 is optional and discovered by name. Keeping it
        # separate from the point filter protects deployments that still use
        # the resident point path while a new overlay is staged.
        # Mesh ABI 0x00050000 is a memory-mapped RTL kernel: it has no AXI-stream
        # DMA companion.  The overlay object is still required as an explicit
        # capability marker so a point-filter-only overlay cannot be mistaken for
        # this geometry engine.
        self._dual_mesh_dma = getattr(overlay, 'dual_plane_mesh_dma', None)
        dual_mesh = getattr(overlay, 'dual_plane_mesh', None)
        if dual_mesh is not None:
            candidate = MMIO(DUAL_PLANE_MESH_BASE, DUAL_PLANE_MESH_RANGE)
            if candidate.read(0x014) == DUAL_PLANE_MESH_ABI_VERSION:
                self._dual_mesh_mmio = candidate

    @_hardware_locked
    def evaluate_mask_distances(self, volume, coordinates, *, max_radius=64,
                                timeout_seconds=30.):
        from .pl_distance import evaluate_mask_distances
        return evaluate_mask_distances(self, volume, coordinates, max_radius=max_radius,
                                       timeout_seconds=timeout_seconds)

    def _allocate_buffers(self, point_count, allocate):
        required = int(point_count) * 16
        if self._point_buf is not None and self._point_capacity == required:
            return
        if self._point_buf is not None:
            self._point_buf.freebuffer()
        if self._result_buf is not None:
            self._result_buf.freebuffer()
        self._point_buf = allocate(shape=(max(16, required),), dtype="u1")
        self._result_buf = allocate(shape=(32,), dtype="u1")
        self._point_capacity = max(16, required)

    @staticmethod
    def _plane_words(vertices):
        # lung_metrics uses nx*x + ny*y + nz*z + d <= 0 for each face.
        import math
        from . import planner_reference as ref

        words = []
        for a, _, _, normal in ref.tetra_faces(
                [tuple(row) for row in np.asarray(vertices[:3])],
                tuple(np.asarray(vertices[3]))):
            words.append((_q16(normal[0]), _q16(normal[1]), _q16(normal[2]),
                          _q16(-sum(float(normal[i]) * float(a[i]) for i in range(3)))))
        return words

    def _pack_points(self, points):
        """Reuse immutable case input, while still executing every PL job."""
        cached = self._packed_points_cache
        if (not points.flags.writeable and cached is not None and
                cached[0].shape == points.shape and cached[0].strides == points.strides and
                cached[0].ctypes.data == points.ctypes.data):
            return cached[1], True
        # Same bytes as packing '<iiiI' per point with _q16, in one numpy pass:
        # a Python loop here cost ~70 ms for 6000 points on the board.
        scaled = np.rint(np.asarray(points, dtype=np.float64).reshape(-1, 3) * 65536.0)
        if len(scaled) and (not np.isfinite(scaled).all()
                            or scaled.min() < -0x80000000 or scaled.max() > 0x7FFFFFFF):
            raise ValueError("value is outside signed Q16.16 range")
        packed = np.zeros((len(scaled), 4), dtype='<i4')
        packed[:, :3] = scaled.astype('<i8')
        raw = packed.tobytes()
        self._packed_points_cache = (points, raw) if not points.flags.writeable else None
        return raw, False

    @staticmethod
    def _dual_plane_words(vertices):
        # The wedge's physical planes are faces 1 and 2.  The RTL accepts
        # -(n*x+n*y+n*z+d), so its positive margin is the same signed
        # clearance used by the CPU constraint report.
        import numpy as _np
        from . import planner_reference as ref
        faces = ref.tetra_faces([tuple(row) for row in _np.asarray(vertices[:3])],
                                tuple(_np.asarray(vertices[3])))
        words = []
        for a, _, _, normal in (faces[1], faces[2]):
            d = -sum(float(normal[i]) * float(a[i]) for i in range(3))
            words.append((_q16(-normal[0]), _q16(-normal[1]), _q16(-normal[2]), _q16(-d)))
        return words

    def _allocate_dual_buffers(self, input_bytes, output_bytes, allocate):
        input_required = max(16, int(input_bytes))
        output_required = max(16, int(output_bytes))
        if (self._dual_input_buf is not None and self._dual_capacity == input_required
                and len(self._dual_output_buf) == output_required):
            return
        for buffer in (self._dual_input_buf, self._dual_output_buf):
            if buffer is not None:
                buffer.freebuffer()
        self._dual_input_buf = allocate(shape=(input_required,), dtype='u1')
        self._dual_output_buf = allocate(shape=(output_required,), dtype='u1')
        self._dual_capacity = input_required

    @_hardware_locked
    def evaluate_dual_plane_filter_batch(self, points, candidates, minimum_clearance,
                                         *, timeout_seconds=30.0, cancel=None):
        """Keep source-point coverage semantics across bounded PL point batches."""
        started = time.monotonic()
        try:
            points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
            candidates = np.asarray(candidates, dtype=np.float64).reshape(-1, 4, 3)
            if len(points) <= 4096:
                return self._evaluate_dual_plane_filter_chunk(
                    points, candidates, minimum_clearance,
                    timeout_seconds=timeout_seconds, cancel=cancel)
            if (not np.isfinite(points).all() or not len(candidates)
                    or len(candidates) > 1023 or not np.isfinite(candidates).all()):
                raise ValueError('dual-plane batch input is invalid or exceeds candidate capacity')
            if not np.isfinite(timeout_seconds) or timeout_seconds <= 0:
                raise ValueError('dual-plane timeout must be finite and positive')
            merged = None
            for begin in range(0, len(points), 4096):
                if cancel is not None and cancel():
                    raise RuntimeError('dual-plane PL job cancelled')
                remaining = float(timeout_seconds) - (time.monotonic() - started)
                if remaining <= 0:
                    raise TimeoutError('dual-plane PL point batches timeout')
                result = self._evaluate_dual_plane_filter_chunk(
                    points[begin:begin + 4096], candidates, minimum_clearance,
                    timeout_seconds=remaining, cancel=cancel)
                if not result.get('ok'):
                    return result
                rows = result['candidates']
                count = min(4096, len(points) - begin)
                if (len(rows) != len(candidates) or any(
                        not row.get('ok') or row.get('index') != index
                        or row.get('processed') != count
                        or not 0 <= row.get('accepted', -1) <= count
                        or row.get('errors', 0) or row.get('cpu_fallback_count', 0)
                        for index, row in enumerate(rows))):
                    raise RuntimeError('dual-plane point batch result invalid')
                if merged is None:
                    merged = dict(result, candidates=[dict(row) for row in rows],
                                  point_batch_count=1, input_point_count=len(points))
                else:
                    for target, row in zip(merged['candidates'], rows):
                        target['processed'] += row['processed']
                        target['accepted'] += row['accepted']
                        target['clearance_mm'] = min(target['clearance_mm'], row['clearance_mm'])
                    for key in ('cycles', 'dma_input_bytes', 'dma_output_bytes',
                                'dma_input_transfers', 'dma_output_transfers', 'pl_calls'):
                        merged[key] = merged.get(key, 0) + result.get(key, 0)
                    for key in ('points_pack_reused', 'points_resident_reused'):
                        merged[key] = bool(merged.get(key) and result.get(key))
                    merged['quantization_tolerance_mm'] = max(
                        merged.get('quantization_tolerance_mm', 0.),
                        result.get('quantization_tolerance_mm', 0.))
                    merged['job_id'] = result.get('job_id')
                    merged['point_batch_count'] += 1
            for row in merged['candidates']:
                row['coverage_percent'] = 100.0 * row['accepted'] / row['processed']
            merged.update(processed=len(points) * len(candidates),
                          accepted=sum(row['accepted'] for row in merged['candidates']),
                          coverage_percent=min(row['coverage_percent'] for row in merged['candidates']),
                          clearance_mm=min(row['clearance_mm'] for row in merged['candidates']),
                          job_ms=(time.monotonic() - started) * 1000.)
            self.last_error = ''
            return merged
        except Exception as exc:
            self._dual_points_hardware_key = None
            self.last_error = str(exc)
            logging.getLogger(__name__).exception('DUAL_PLANE_FILTER_FAILED')
            return dict(ok=False, error=self.last_error, execution_backend='dual_plane_pl',
                        cpu_fallback_count=0)

    def _evaluate_dual_plane_filter_chunk(self, points, candidates, minimum_clearance,
                                          *, timeout_seconds=30.0, cancel=None):
        """Filter many candidate wedges against one resident tumor point set."""
        try:
            points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
            candidates = np.asarray(candidates, dtype=np.float64).reshape(-1, 4, 3)
            if (len(points) == 0 or len(candidates) == 0 or not np.isfinite(points).all()
                    or not np.isfinite(candidates).all()):
                raise ValueError('dual-plane batch input is empty or nonfinite')
            if len(points) > 4096 or len(candidates) > 1023:
                raise ValueError('dual-plane batch exceeds hardware capacity')
            if not np.isfinite(float(minimum_clearance)) or float(minimum_clearance) < 0:
                raise ValueError('dual-plane margin is invalid')
            if not self.configured:
                raise RuntimeError('PL disabled by LUNG_PL_ENABLE')
            if sys.platform == 'linux' and os.geteuid() != 0:
                from .pl_privileged import PrivilegedPlClient
                if self._privileged is None:
                    self._privileged = PrivilegedPlClient(self.bit_path, require_strict_pl=False)
                result = self._privileged.evaluate_dual_plane_filter_batch(
                    points, candidates, minimum_clearance, timeout_seconds=timeout_seconds)
                self.last_error = '' if result.get('ok') else result.get('error', 'dual-plane PL service failed')
                return result
            self._load()
            if self._dual_mmio is None or self._dual_dma is None:
                raise RuntimeError('overlay has no dual_plane_filter/dual_plane_dma ABI 0x00030000')
            from pynq import allocate
            raw_points, reused = self._pack_points(points)
            point_key = hashlib.sha256(raw_points).hexdigest()
            points_resident = point_key == self._dual_points_hardware_key
            descriptors = bytearray()
            for vertices in candidates:
                for plane in self._dual_plane_words(vertices):
                    descriptors.extend(struct.pack('<4i', *plane))
            payload = (b'' if points_resident else raw_points) + bytes(descriptors)
            self._allocate_dual_buffers(len(payload), len(candidates) * 16, allocate)
            self._dual_input_buf[:len(payload)] = np.frombuffer(payload, dtype=np.uint8)
            self._dual_output_buf[:] = 0
            self._dual_input_buf.flush(); self._dual_output_buf.flush()
            self._dual_job_id = (self._dual_job_id + 1) & 0xffffffff or 1
            mmio = self._dual_mmio
            mmio.write(0x004, len(points)); mmio.write(0x008, _q16(minimum_clearance) & 0xffffffff)
            mmio.write(0x00c, self._dual_job_id)
            mmio.write(0x010, max(1, int(timeout_seconds * 100_000_000)))
            mmio.write(0x030, len(candidates))
            mmio.write(0x034, 1 if points_resident else 0)
            mmio.write(0x01c, 1)
            started = time.perf_counter()
            self._dual_dma.recvchannel.transfer(self._dual_output_buf)
            mmio.write(0x000, 1)
            chunks = dual_plane_dma_chunks(len(payload))
            for begin, count in chunks:
                if cancel is not None and cancel():
                    mmio.write(0x000, 2)
                    self._reset_hardware_state()
                    raise RuntimeError('dual-plane PL job cancelled')
                self._dual_dma.sendchannel.transfer(self._dual_input_buf,
                                                    start=begin, nbytes=count)
                self._dual_dma.sendchannel.wait()
            deadline = time.monotonic() + float(timeout_seconds)
            while not self._dual_dma.recvchannel.idle:
                if cancel is not None and cancel():
                    mmio.write(0x000, 2)
                    self._reset_hardware_state()
                    raise RuntimeError('dual-plane PL job cancelled')
                if time.monotonic() >= deadline:
                    mmio.write(0x000, 2)
                    self._reset_hardware_state()
                    raise TimeoutError('dual-plane PL DMA timeout')
                time.sleep(0.0005)
            self._dual_dma.recvchannel.wait(); self._dual_dma.sendchannel.wait()
            self._dual_output_buf.invalidate()
            rows = []
            for index in range(len(candidates)):
                flags_raw, margin_raw, processed, accepted = struct.unpack_from(
                    '<4I', self._dual_output_buf, index * 16)
                errors = flags_raw & 0xff
                if errors or processed != len(points) or accepted > processed:
                    raise RuntimeError('dual-plane batch result invalid at candidate %d' % index)
                rows.append(dict(ok=True, index=index, processed=processed, accepted=accepted,
                    coverage_percent=100.0 * accepted / processed,
                    clearance_mm=_signed32(margin_raw) / 65536.0, errors=errors,
                    cpu_fallback_count=0))
            errors |= mmio.read(0x018) & 0xff
            if errors:
                raise RuntimeError('dual-plane PL hardware errors: 0x%02x' % errors)
            self._dual_points_hardware_key = point_key
            coordinate_bound = float(np.max(np.abs(points)))
            quantization_tolerance = (8.0 * (coordinate_bound + 1.0) / 65536.0)
            self.last_error = ''
            return dict(ok=True, abi='0x%08x' % DUAL_PLANE_ABI_VERSION,
                execution_backend='dual_plane_pl_batch', exact_geometry_backend='CPU / Manifold float64',
                candidate_count=len(rows), candidates=rows,
                processed=len(points) * len(rows), accepted=sum(row['accepted'] for row in rows),
                coverage_percent=min(row['coverage_percent'] for row in rows),
                clearance_mm=min(row['clearance_mm'] for row in rows),
                cycles=mmio.read(0x02c), errors=errors,
                job_id=self._dual_job_id, clock_mhz=self.clock_mhz,
                dma_input_bytes=len(payload), dma_output_bytes=len(rows) * 16,
                dma_input_transfers=len(chunks),
                dma_output_transfers=1, pl_calls=1, cpu_fallback_count=0,
                points_pack_reused=reused, points_resident_reused=points_resident,
                job_ms=(time.perf_counter() - started) * 1000.0,
                quantization_tolerance_mm=quantization_tolerance)
        except Exception as exc:
            self._dual_points_hardware_key = None
            self.last_error = str(exc)
            logging.getLogger(__name__).exception('DUAL_PLANE_FILTER_FAILED')
            return {'ok': False, 'error': self.last_error, 'execution_backend': 'dual_plane_pl',
                    'cpu_fallback_count': 0}

    @_hardware_locked
    def evaluate_dual_plane_mesh_batch(self, triangles, candidates, minimum_clearance=0.,
                                       *, timeout_seconds=60., cancel=None,
                                       reference_only=False, _verified_mesh_key=None):
        """Evaluate exact mesh/wedge metrics through ABI 0x00050000.

        ``triangles`` is the normalized, resident lung union image and
        ``candidates`` contains four vertices per wedge.  The new hardware
        ABI is discovered independently from the point filter.  Until an
        ABI-0x00050000 overlay is installed, ``reference_only=True`` provides
        the deterministic PS golden implementation used for parity gates; it
        is explicitly marked as a reference result and never silently counts
        as a hardware fallback.
        """
        started = time.perf_counter()
        try:
            triangles = np.asarray(triangles, dtype=np.float64)
            if triangles.ndim != 3 or triangles.shape[1:] != (3, 3):
                triangles = triangles.reshape(-1, 3, 3)
            candidates = np.asarray(candidates, dtype=np.float64).reshape(-1, 4, 3)
            frontend_reuse = triangles is self._dual_mesh_frontend_source
            if (not len(triangles) or not len(candidates) or
                    (_verified_mesh_key is None and not frontend_reuse
                     and not np.isfinite(triangles).all()) or
                    not np.isfinite(candidates).all()):
                raise ValueError('dual-plane mesh input is empty or nonfinite')
            if _verified_mesh_key is not None and (reference_only or
                    not isinstance(_verified_mesh_key, str) or
                    len(_verified_mesh_key) != 64):
                raise ValueError('invalid verified mesh request')
            if _verified_mesh_key is not None:
                from .dual_plane_mesh_bvh import is_bytes_backed_mesh
                if not triangles.flags.c_contiguous or not is_bytes_backed_mesh(triangles):
                    raise ValueError('verified mesh requires an immutable bytes-backed service snapshot')
            if len(triangles) > 1_000_000 or len(candidates) > 1023:
                raise ValueError('dual-plane mesh input exceeds ABI capacity')
            if float(minimum_clearance) < 0 or not np.isfinite(float(minimum_clearance)):
                raise ValueError('dual-plane mesh margin is invalid')
            if not np.isfinite(timeout_seconds) or timeout_seconds <= 0:
                raise ValueError('dual-plane mesh timeout must be finite and positive')
            if cancel is not None and cancel():
                raise RuntimeError('dual-plane mesh job cancelled')
            if sys.platform == 'linux' and os.geteuid() != 0 and not reference_only:
                if self._privileged is None:
                    from .pl_privileged import PrivilegedPlClient
                    self._privileged = PrivilegedPlClient(self.bit_path, require_strict_pl=False)
                result = self._privileged.evaluate_dual_plane_mesh_batch(
                    triangles, candidates, minimum_clearance,
                    timeout_seconds=timeout_seconds, reference_only=False, cancel=cancel)
                if result.get('ok'):
                    from .dual_plane_mesh_bvh import is_bytes_backed_mesh
                    self._dual_mesh_frontend_source = triangles if is_bytes_backed_mesh(triangles) else None
                self.last_error = '' if result.get('ok') else result.get('error', 'dual-plane mesh service failed')
                return result
            # The RTL ABI uses resident DDR pointers, so no stream DMA is
            # needed.  Every result still passes the Manifold gate in the
            # planner before it can affect ranking.
            if not reference_only:
                if self._dual_mesh_mmio is None:
                    self._load()
            if self._dual_mesh_mmio is not None and not reference_only:
                result = self._evaluate_dual_plane_mesh_hardware(
                    triangles, candidates, timeout_seconds=timeout_seconds,
                    cancel=cancel, verified_mesh_key=_verified_mesh_key)
                self.last_error = ''
                return result
            if not reference_only:
                raise RuntimeError('dual-plane mesh accelerator ABI 0x00050000 is unavailable')
            from .dual_plane_reference import clip_mesh_by_dual_plane
            rows = []
            for index, vertices in enumerate(candidates):
                if cancel is not None and cancel():
                    raise RuntimeError('dual-plane mesh job cancelled')
                row = clip_mesh_by_dual_plane(triangles, vertices)
                row.update(index=index, ok=bool(row['valid']), processed=len(triangles),
                          accepted=int(bool(row['valid'])),
                          clearance_mm=None, errors=0,
                          cpu_fallback_count=0)
                rows.append(row)
            return dict(ok=True, abi='0x%08x' % DUAL_PLANE_MESH_ABI_VERSION,
                        execution_backend='dual_plane_pl_mesh_reference' if reference_only
                        else 'dual_plane_pl_mesh', reference_only=bool(reference_only),
                        candidate_count=len(rows), candidates=rows,
                        cycles=0, errors=0, job_id=0, dma_input_bytes=0,
                        dma_output_bytes=len(rows) * 64, dma_input_transfers=0,
                        dma_output_transfers=0, pl_calls=1,
                        cpu_fallback_count=0, points_resident_reused=False,
                        resident_mesh_reused=(self._dual_mesh_key is not None),
                        mesh_triangle_count=len(triangles),
                        job_ms=(time.perf_counter() - started) * 1000.)
        except Exception as exc:
            self.last_error = str(exc)
            # Any MMIO or decoding exception must not leave an active master
            # using buffers that the next call could replace.
            if not reference_only and self._dual_mesh_mmio is not None:
                try:
                    if self._dual_mesh_mmio.read(DUAL_MESH_CONTROL) & 2:
                        self._reset_hardware_state()
                except Exception as reset_error:
                    self._hardware_reset_failed = True
                    self.last_error += '; hardware recovery failed: ' + str(reset_error)
            return dict(ok=False, error=self.last_error,
                        execution_backend='dual_plane_pl_mesh', cpu_fallback_count=0)

    def _evaluate_dual_plane_mesh_hardware(self, triangles, candidates, *,
                                           timeout_seconds, cancel, verified_mesh_key=None):
        """Run ABI 0x00050000's DDR-resident RTL kernel."""
        Overlay, allocate, MMIO = _import_pynq()
        from . import planner_reference as ref
        started = time.perf_counter()
        phase_started = started
        timings = {}

        def mark(name):
            nonlocal phase_started
            now = time.perf_counter()
            timings[name] = (now - phase_started) * 1000.
            phase_started = now

        count = len(candidates)
        if self._hardware_reset_failed:
            raise RuntimeError('hardware recovery required before replacing DDR buffers')
        if self._dual_mesh_mmio.read(DUAL_MESH_CONTROL) & 2:
            raise RuntimeError('dual-plane mesh hardware is still busy')
        mark('precheck_ms')
        from .dual_plane_mesh_bvh import build_mesh_bvh
        trusted_reuse = (verified_mesh_key is not None and
                         triangles is self._dual_mesh_source and
                         self._dual_mesh_image is not None and
                         self._dual_mesh_image.source_sha256 == verified_mesh_key)
        if trusted_reuse:
            mesh_key = verified_mesh_key
        else:
            source_raw = np.ascontiguousarray(triangles, dtype='<f8').view(np.uint8).reshape(-1)
            mesh_key = hashlib.sha256(source_raw.tobytes()).hexdigest()
            if verified_mesh_key is not None and mesh_key != verified_mesh_key:
                raise ValueError('verified mesh identity does not match source bytes')
        mark('mesh_key_ms')
        if self._dual_mesh_image is None or self._dual_mesh_image.source_sha256 != mesh_key:
            self._dual_mesh_image = build_mesh_bvh(triangles)
            if self._dual_mesh_image.source_sha256 != mesh_key:
                raise ValueError('verified mesh identity changed during BVH build')
        self._dual_mesh_source = triangles if verified_mesh_key is not None else None
        mark('bvh_build_ms')
        image = self._dual_mesh_image
        mesh_raw = image.triangles.view(np.uint8).reshape(-1)
        bvh_raw = image.nodes.view(np.uint8).reshape(-1)
        from .dual_plane_mesh_protocol import pack_candidates, decode_results
        mesh_center = image.center
        candidate_raw = pack_candidates(candidates, mesh_center)
        segment_capacity = min(131072, max(4096, len(triangles) * 4))
        mark('candidate_pack_ms')
        mesh_reused = (self._dual_mesh_buf is not None and self._dual_mesh_bvh_buf is not None
                       and self._dual_mesh_key == mesh_key)
        if not mesh_reused:
            new_mesh = new_bvh = None
            try:
                new_mesh = allocate(shape=(mesh_raw.size + 16,), dtype='u1')
                # The last 72-byte triangle is fetched in aligned 16-byte beats.
                new_mesh[:] = 0
                new_mesh[:mesh_raw.size] = mesh_raw
                new_mesh.flush()
                new_bvh = allocate(shape=(bvh_raw.size,), dtype='u1')
                new_bvh[:] = bvh_raw
                new_bvh.flush()
            except Exception:
                for buffer in (new_mesh, new_bvh):
                    if buffer is not None:
                        buffer.freebuffer()
                raise
            old_mesh, old_bvh = self._dual_mesh_buf, self._dual_mesh_bvh_buf
            self._dual_mesh_buf, self._dual_mesh_bvh_buf = new_mesh, new_bvh
            self._dual_mesh_key = mesh_key
            for buffer in (old_mesh, old_bvh):
                if buffer is not None:
                    buffer.freebuffer()
        mark('resident_allocate_upload_ms')
        # Powell submits individual candidates after the coarse batch. Keep
        # capacity across calls instead of allocating/clearing several MB of
        # segment scratch for each candidate. RTL overwrites every segment it
        # consumes; PS never reads scratch, so no zero-fill is required.
        scratch_reused = True
        for name, required in (
                ('_dual_mesh_candidates_buf', len(candidate_raw)),
                ('_dual_mesh_segments_buf', segment_capacity * DUAL_MESH_SEGMENT_BYTES),
                ('_dual_mesh_results_buf', count * DUAL_MESH_RESULT_BYTES)):
            previous = getattr(self, name)
            if previous is None or previous.size < required:
                replacement = allocate(shape=(required,), dtype='u1')
                setattr(self, name, replacement)
                if previous is not None:
                    previous.freebuffer()
                scratch_reused = False
        mark('scratch_allocate_ms')
        self._dual_mesh_candidates_buf[:len(candidate_raw)] = candidate_raw
        self._dual_mesh_candidates_buf.flush()
        # Poison the active output range with zero identity before START.
        # A partial DMA write cannot accidentally reuse a previous good row.
        self._dual_mesh_results_buf[:count * DUAL_MESH_RESULT_BYTES] = 0
        self._dual_mesh_results_buf.flush()
        mark('candidate_upload_ms')
        mmio = self._dual_mesh_mmio
        def address(buffer, alignment=16):
            value = int(getattr(buffer, 'device_address',
                                getattr(buffer, 'physical_address', 0)))
            if not value or value % alignment:
                raise RuntimeError('dual-plane mesh DDR buffer is not %d-byte aligned' % alignment)
            return value
        pointers = [address(self._dual_mesh_buf), address(self._dual_mesh_candidates_buf),
                    address(self._dual_mesh_segments_buf, 64), address(self._dual_mesh_results_buf, 64)]
        for lo, hi, value in zip((DUAL_MESH_MESH_LO, DUAL_MESH_CANDIDATES_LO,
                                  DUAL_MESH_SEGMENTS_LO, DUAL_MESH_RESULTS_LO),
                                 (DUAL_MESH_MESH_HI, DUAL_MESH_CANDIDATES_HI,
                                  DUAL_MESH_SEGMENTS_HI, DUAL_MESH_RESULTS_HI), pointers):
            mmio.write(lo, value & 0xffffffff); mmio.write(hi, value >> 32)
        job_id = (self._dual_mesh_job_id + 1) & 0xffffffff or 1
        self._dual_mesh_job_id = job_id
        mmio.write(DUAL_MESH_TRIANGLE_COUNT, len(triangles))
        mmio.write(DUAL_MESH_CANDIDATE_COUNT, count)
        mmio.write(DUAL_MESH_JOB_ID, job_id)
        mmio.write(DUAL_MESH_SEGMENT_CAPACITY, segment_capacity)
        mmio.write(DUAL_MESH_RESULT_COUNT, count)
        bvh_address = address(self._dual_mesh_bvh_buf, 128)
        mmio.write(0x050, bvh_address & 0xffffffff)
        mmio.write(0x054, bvh_address >> 32)
        mmio.write(0x058, len(image.nodes))
        center_words = np.asarray(mesh_center, dtype='<f8').view('<u4')
        for index, word in enumerate(center_words):
            mmio.write(0x060 + index * 4, int(word))
        mmio.write(DUAL_MESH_CONTROL, 1)
        mark('mmio_setup_ms')
        deadline = time.monotonic() + float(timeout_seconds)
        def abort_and_drain():
            mmio.write(DUAL_MESH_CONTROL, 2)
            drain_deadline = time.monotonic() + 2.
            while not (mmio.read(DUAL_MESH_CONTROL) & 4):
                if time.monotonic() >= drain_deadline:
                    self._reset_hardware_state()
                    return
                time.sleep(0.001)
        while True:
            if cancel is not None and cancel():
                abort_and_drain()
                raise RuntimeError('dual-plane mesh job cancelled')
            status = mmio.read(DUAL_MESH_CONTROL)
            if status & 4:
                break
            if time.monotonic() >= deadline:
                abort_and_drain()
                raise TimeoutError('dual-plane mesh hardware timeout')
            time.sleep(0.001)
        mark('mmio_wait_ms')
        errors = mmio.read(DUAL_MESH_ERRORS) & 0xff
        if mmio.read(DUAL_MESH_JOB_ID) != job_id:
            raise RuntimeError('dual-plane mesh stale job result')
        self._dual_mesh_results_buf.invalidate()
        raw = bytes(self._dual_mesh_results_buf[:count * DUAL_MESH_RESULT_BYTES])
        if errors:
            raise RuntimeError('dual-plane mesh hardware errors: 0x%02x' % errors)
        decoded = decode_results(raw, count, job_id)
        rows = []
        for index, item in enumerate(decoded):
            flags = int(item['flags'])
            valid = not flags and float(item['volume']) > 1e-6
            rows.append(dict(index=index, ok=not flags, valid=valid,
                             volume_mm3=float(item['volume']),
                             source_area_mm2=float(item['source_area']),
                             surface_area_mm2=float(item['source_area']),
                             cut_area_mm2=float(item['cut_area']),
                             source_triangles=int(item['source_triangles']),
                             cut_triangles=int(item['cut_triangles']),
                             boundary_segments=int(item['boundary_segments']),
                             cap_loops=int(item['cap_loops']), flags=flags,
                             processed=len(triangles), accepted=int(valid),
                             errors=errors, cpu_fallback_count=0))
        mark('result_decode_ms')
        self._dual_mesh_key = mesh_key
        return dict(ok=True, abi='0x%08x' % DUAL_PLANE_MESH_ABI_VERSION,
                    execution_backend='dual_plane_pl_mesh', reference_only=False,
                    candidate_count=count, candidates=rows, errors=errors,
                    job_id=job_id, cycles=mmio.read(DUAL_MESH_CYCLES),
                    clock_mhz=self.clock_mhz,
                    dma_input_bytes=(0 if mesh_reused else len(mesh_raw) + len(bvh_raw)) + len(candidate_raw),
                    dma_output_bytes=count * DUAL_MESH_RESULT_BYTES,
                    pl_calls=1, cpu_fallback_count=0,
                    resident_mesh_reused=mesh_reused, mesh_triangle_count=len(triangles),
                    scratch_buffers_reused=scratch_reused,
                    bvh_node_count=len(image.nodes),
                    mesh_timings_ms=timings,
                    job_ms=(time.perf_counter() - started) * 1000.)

    def evaluate_dual_plane_filter(self, points, vertices, minimum_clearance,
                                   *, timeout_seconds=30.0, cancel=None):
        result = self.evaluate_dual_plane_filter_batch(
            points, np.asarray(vertices, dtype=np.float64).reshape(1, 4, 3),
            minimum_clearance, timeout_seconds=timeout_seconds, cancel=cancel)
        if not result.get('ok'):
            return result
        row = dict(result['candidates'][0])
        row.update({key: value for key, value in result.items() if key != 'candidates'})
        return row

    @_hardware_locked
    def evaluate(self, points, vertices, minimum_clearance):
        """Run one PL job and return ABI-normalized metrics.

        Failures are converted to ``ok=False`` so a board without a usable
        overlay can continue with the CPU reference result and expose the
        reason in the UI.
        """
        try:
            points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
            if len(points) == 0:
                raise ValueError("PL requires at least one tumor point")
            if not self.configured:
                raise RuntimeError('PL disabled by LUNG_PL_ENABLE')
            if sys.platform == 'linux' and os.geteuid() != 0:
                if self.last_error and self._privileged is not None and self._privileged.process is None:
                    return dict(ok=False, error=self.last_error)
                from .pl_privileged import PrivilegedPlClient
                if self._privileged is None:
                    self._privileged = PrivilegedPlClient(self.bit_path, require_strict_pl=self.require_strict_pl)
                result = self._privileged.evaluate(points, vertices, minimum_clearance)
                self.last_error = '' if result.get('ok') else result.get('error', 'PL service failed')
                return result
            self._load()
            from pynq import allocate  # imported by _load in the normal path
            self._allocate_buffers(len(points), allocate)
            raw, points_reused = self._pack_points(points)
            self._point_buf[:len(raw)] = np.frombuffer(raw, dtype=np.uint8)
            self._result_buf[:] = 0
            self._point_buf.flush()
            self._result_buf.flush()

            self._job_id = (self._job_id + 1) & 0xFFFFFFFF or 1
            mmio = self._mmio
            planes = self._plane_words(vertices)
            for face, plane in enumerate(planes):
                for component, value in enumerate(plane):
                    mmio.write(PLANES + 16 * face + 4 * component, value & 0xFFFFFFFF)
            mmio.write(POINT_COUNT, len(points))
            mmio.write(MARGIN_Q16, _q16(minimum_clearance) & 0xFFFFFFFF)
            mmio.write(JOB_ID, self._job_id)
            mmio.write(IRQ_ACK, 1)

            started = time.perf_counter()
            self._dma.recvchannel.transfer(self._result_buf)
            mmio.write(CONTROL, 1)
            self._dma.sendchannel.transfer(self._point_buf)
            timeout = float(os.environ.get("LUNG_PL_TIMEOUT", "5"))
            deadline = time.monotonic() + timeout
            while not self._dma.recvchannel.idle or not self._dma.sendchannel.idle:
                if time.monotonic() > deadline:
                    self._reset_hardware_state()
                    raise TimeoutError("PL DMA result timeout")
                time.sleep(0.0005)
            self._dma.recvchannel.wait()
            self._dma.sendchannel.wait()
            self._result_buf.invalidate()
            words = struct.unpack_from("<8I", self._result_buf)
            magic, status, processed, inside, clearance_raw, cycles, job_id, abi = words
            errors = mmio.read(ERRORS) & 0xFF
            if (magic != MAGIC or abi != ABI_VERSION or processed != len(points)
                    or job_id != self._job_id or inside > processed):
                raise RuntimeError("invalid PL result record")
            if errors:
                raise RuntimeError("PL reported hardware errors: 0x%02x" % errors)
            self.last_error = ""
            return {
                "ok": True,
                "feasible": bool(status & 1) and errors == 0,
                "coverage_percent": 100.0 * inside / processed if processed else 0.0,
                "clearance_mm": _signed32(clearance_raw) / 65536.0,
                "processed": processed,
                "inside": inside,
                "errors": errors,
                "cycles": cycles,
                "job_id": job_id,
                "job_ms": (time.perf_counter() - started) * 1000.0,
                "overlay_load_s": self._load_seconds,
                "points_pack_reused": points_reused,
            }
        except Exception as exc:  # optional accelerator must not kill the UI
            self.last_error = str(exc)
            logging.getLogger(__name__).exception("PL_METRICS_FAILED")
            return {"ok": False, "error": self.last_error}

    def _allocate_ray_buffers(self, record_count, allocate):
        required = int(record_count)
        if self._ray_input_buf is not None and self._ray_capacity == required:
            return
        for buffer in (self._ray_input_buf, self._ray_output_buf):
            if buffer is not None:
                buffer.freebuffer()
        self._ray_input_buf = allocate(shape=(max(80, required * 80),), dtype="u1")
        self._ray_output_buf = allocate(shape=(max(32, required * 32),), dtype="u1")
        self._ray_capacity = required

    @_hardware_locked
    def evaluate_rays(self, packed_records, record_count, *,
                      timeout_cycles=50_000_000, timeout_seconds=5.0):
        """Evaluate packed ray/triangle records through the shared overlay.

        The wire format is defined by ``cas_frontend.ray_batch``. Results are
        returned as JSON-friendly dictionaries so the privileged service can
        forward them without importing NumPy in the unprivileged process.
        """
        try:
            record_count = int(record_count)
            if record_count < 0 or record_count > 0xFFFFFFFF:
                raise ValueError("record_count must fit unsigned 32-bit register")
            if record_count == 0:
                return {"ok": True, "results": [], "processed": 0,
                        "hits": 0, "cycles": 0, "errors": 0}
            if timeout_cycles <= 0 or timeout_cycles > 0xFFFFFFFF:
                raise ValueError("timeout_cycles must fit unsigned 32-bit register")
            raw = bytes(packed_records)
            if len(raw) != record_count * 80:
                raise ValueError("ray input buffer size mismatch")
            if not self.configured:
                raise RuntimeError("PL disabled by LUNG_PL_ENABLE")
            if sys.platform == 'linux' and os.geteuid() != 0:
                if self._privileged is None:
                    from .pl_privileged import PrivilegedPlClient
                    self._privileged = PrivilegedPlClient(self.bit_path, require_strict_pl=self.require_strict_pl)
                result = self._privileged.evaluate_rays(
                    raw, record_count, timeout_cycles=timeout_cycles,
                    timeout_seconds=timeout_seconds)
                self.last_error = '' if result.get('ok') else result.get(
                    'error', 'PL ray service failed')
                return result
            self._load()
            if self._ray_dma is None or self._ray_mmio is None:
                raise RuntimeError("overlay has no ray_dma/ray_batch path")
            from pynq import allocate  # imported by _load in the normal path
            self._allocate_ray_buffers(record_count, allocate)
            self._ray_input_buf[:len(raw)] = np.frombuffer(raw, dtype=np.uint8)
            self._ray_output_buf[:] = 0
            self._ray_input_buf.flush()
            self._ray_output_buf.flush()

            self._ray_job_id = (self._ray_job_id + 1) & 0xFFFFFFFF or 1
            mmio = self._ray_mmio
            mmio.write(0x004, record_count)
            mmio.write(0x008, int(timeout_cycles))
            mmio.write(0x00C, self._ray_job_id)
            mmio.write(0x01C, 1)
            started = time.perf_counter()
            self._ray_dma.recvchannel.transfer(self._ray_output_buf)
            mmio.write(0x000, 1)
            self._ray_dma.sendchannel.transfer(self._ray_input_buf)
            deadline = time.monotonic() + float(timeout_seconds)
            while not self._ray_dma.recvchannel.idle or not self._ray_dma.sendchannel.idle:
                if time.monotonic() >= deadline:
                    self._reset_hardware_state()
                    raise TimeoutError("ray batch DMA result timeout")
                time.sleep(0.0005)
            self._ray_dma.recvchannel.wait()
            self._ray_dma.sendchannel.wait()
            self._ray_output_buf.invalidate()
            result_data = bytes(self._ray_output_buf[:record_count * 32])
            errors = mmio.read(0x018) & 0xFF
            processed = mmio.read(0x010)
            if processed != record_count:
                raise RuntimeError("ray batch processed %d/%d records" %
                                   (processed, record_count))
            from .ray_batch import decode_result_buffer
            results = decode_result_buffer(result_data, record_count)
            from .ray_batch import input_pairs, validate_result_records
            validate_result_records(results, input_pairs(raw, record_count), errors)
            self.last_error = ""
            return {
                "ok": True,
                "results": [dict(ray_id=item.ray_id,
                                  triangle_id=item.triangle_id,
                                  hit=item.hit, error=item.error,
                                  t_q16=item.t_q16, u_q16=item.u_q16,
                                  v_q16=item.v_q16) for item in results],
                "processed": processed,
                "hits": mmio.read(0x014),
                "cycles": mmio.read(0x020),
                "errors": errors,
                "job_id": self._ray_job_id,
                "job_ms": (time.perf_counter() - started) * 1000.0,
                "overlay_load_s": self._load_seconds,
            }
        except Exception as exc:
            self.last_error = str(exc)
            logging.getLogger(__name__).exception("PL_RAY_FAILED")
            return {"ok": False, "error": self.last_error}

    @_hardware_locked
    def cache_mesh_image(self, image):
        """Reuse the image already constructed during local case loading."""
        if self._hardware_reset_failed:
            self._reset_hardware_state()
        if image is not None and (self._mesh_image is None or self._mesh_image.key != image.key):
            self._mesh_image = image
            self._mesh_key = None
            if self._bvh_buf is not None:
                self._bvh_buf.freebuffer()
                self._bvh_buf = None

    @_hardware_locked
    def cache_mesh_resource(self, resource):
        from .frozen_mesh import FrozenMesh
        if not isinstance(resource, FrozenMesh) or not resource.matches(resource.triangles, resource.solid_ids):
            raise ValueError('Expected an intact immutable mesh resource')
        self._mesh_resource = resource

    def _select_mesh_io_buffers(self, ray_count, result_bytes, allocate):
        from .ray_mesh import RAY_BYTES

        size = ray_count * result_bytes
        if (self._mesh_ray_input_buf is not None and self._mesh_ray_capacity == ray_count
                and self._mesh_result_buf is not None and len(self._mesh_result_buf) == size):
            return True
        if self._mesh_ray_input_buf is not None and self._mesh_result_buf is not None:
            if self._mesh_ray_capacity <= 32:
                key = (self._mesh_ray_capacity, len(self._mesh_result_buf))
                self._mesh_io_pool[key] = (self._mesh_ray_input_buf, self._mesh_result_buf)
            else:
                self._mesh_ray_input_buf.freebuffer()
                self._mesh_result_buf.freebuffer()
        self._mesh_ray_input_buf = self._mesh_result_buf = None
        self._mesh_ray_capacity = 0
        pair = self._mesh_io_pool.pop((ray_count, size), None)
        reused = pair is not None
        if pair is None:
            input_buf = allocate(shape=(ray_count * RAY_BYTES,), dtype='u1')
            try:
                result_buf = allocate(shape=(size,), dtype='u1')
            except Exception:
                input_buf.freebuffer()
                raise
            pair = (input_buf, result_buf)
        self._mesh_ray_input_buf, self._mesh_result_buf = pair
        self._mesh_ray_capacity = ray_count
        return reused

    @_hardware_locked
    def evaluate_mesh_rays(self, triangles, origins, directions, *,
                           timeout_cycles=50_000_000, timeout_seconds=10.0, max_hits=128,
                           lengths=None, _distance=False, solid_ids=None):
        """Load a mesh once and evaluate a batch of ray origins/directions.

        DDR mesh overlays expose mesh_ray_dma and mesh_result_dma.
        mesh_dma is optional and is only used when an older BRAM ABI is detected.
        """
        try:
            timings = {}
            diagnostic = None
            phase = time.perf_counter()
            from .ray_mesh import (TRIANGLE_BYTES, RAY_BYTES, RESULT_BYTES,
                                   decode_results, pack_mesh, pack_rays,
                                   validate_results)
            resource = getattr(self, '_mesh_resource', None)
            resource = resource if resource is not None and resource.matches(triangles, solid_ids) else None
            triangles = resource.triangles if resource else np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
            from .mesh_bvh import MAX_SOLIDS, _solid_ids
            solid_ids = resource.solid_ids if resource else _solid_ids(solid_ids, len(triangles))
            solid_count = resource.solid_count if resource else int(solid_ids.max()) + 1
            if solid_count > MAX_SOLIDS:
                raise ValueError('solid count exceeds PL capacity')
            origins = np.asarray(origins, dtype=np.float64).reshape(-1, 3)
            directions = np.asarray(directions, dtype=np.float64).reshape(-1, 3)
            if not len(triangles) or len(origins) != len(directions):
                raise ValueError("mesh ray input is empty or has mismatched rays")
            if not len(origins):
                raise ValueError('mesh ray batch is empty')
            if not np.isfinite(timeout_seconds) or timeout_seconds <= 0 or not 0 < int(timeout_cycles) <= 0xffffffff:
                raise ValueError('mesh ray timeout must be finite and positive')
            if (resource is None and not np.isfinite(triangles).all()) or not np.isfinite(origins).all() \
                    or not np.isfinite(directions).all():
                raise ValueError("mesh ray input contains nonfinite values")
            if not self.configured:
                raise RuntimeError("PL disabled by LUNG_PL_ENABLE")
            if sys.platform == 'linux' and os.geteuid() != 0:
                if self._privileged is None:
                    from .pl_privileged import PrivilegedPlClient
                    self._privileged = PrivilegedPlClient(self.bit_path, require_strict_pl=self.require_strict_pl)
                frontend_validated = time.perf_counter()
                if resource is not None:
                    self._privileged.cache_mesh_resource(resource)
                result = self._privileged.evaluate_mesh_rays(
                    triangles, origins, directions, timeout_cycles=timeout_cycles,
                    timeout_seconds=timeout_seconds, max_hits=max_hits, lengths=lengths,
                    solid_ids=solid_ids,
                    **({"_distance": True} if _distance else {}))
                result['frontend_timings_ms'] = dict(
                    validation=(frontend_validated - phase) * 1000.,
                    privileged=(time.perf_counter() - frontend_validated) * 1000.)
                if result.get('ok') and int(result.get('solid_count', 0)) != solid_count:
                    result = dict(result, ok=False, error=(
                        'PL solid count mismatch: requested %d, received %s' %
                        (solid_count, result.get('solid_count'))))
                self.last_error = '' if result.get('ok') else result.get('error', 'PL mesh ray service failed')
                return result
            self._load()
            if self._mesh_mmio is None:
                raise RuntimeError("overlay has no mesh-resident ray path")
            if solid_count > 1 and self._mesh_mmio.read(0x02c) != MESH_UNION_ABI_VERSION:
                raise RuntimeError('multi-solid PL rays require ABI 0x00070000')
            complete = self._mesh_complete
            volume = lengths is not None
            if _distance and (volume or self._mesh_mmio.read(0x02c) not in (MESH_DISTANCE_ABI_VERSION, MESH_UNION_ABI_VERSION) or not self._mesh_mmio.read(0x050)&32):
                raise RuntimeError('PL distance requires ABI 0x00060000 and distance capability')
            if _distance and (self._mesh_mmio.read(0x090)!=32 or self._mesh_mmio.read(0x094)!=32):
                raise RuntimeError('unsupported PL distance format')
            if volume and not self._mesh_volume:
                raise RuntimeError('PL volume integration requires ABI 0x00050000')
            if not 1 <= int(max_hits) <= 128 or (not complete and int(max_hits) != 128):
                raise ValueError('unsupported runtime crossing limit')
            if complete:
                from .ray_bvh import RESULT_BYTES, decode_results
            if _distance:
                from .mesh_distance import RESULT_BYTES, decode_results
            from pynq import allocate
            from .mesh_bvh import build_mesh_image, mesh_key
            mesh_key_value = resource.key if resource else mesh_key(triangles, solid_ids)
            timings['mesh_validation_key'] = (time.perf_counter() - phase) * 1000.
            reused = self._mesh_key == mesh_key_value
            rebuilt = self._mesh_image is None or self._mesh_image.key != mesh_key_value
            if rebuilt:
                self._mesh_image = build_mesh_image(triangles, solid_ids=solid_ids)
            image = self._mesh_image
            timings['bvh_build'] = image.build_ms if rebuilt else 0.
            mesh_raw = image.triangle_bytes if self._mesh_ddr_mode else pack_mesh(triangles)
            ray_raw = pack_rays(origins, directions, first_ray_id=1, lengths=lengths)
            ray_count = len(origins)
            mesh_key = mesh_key_value
            timings['prepare'] = (time.perf_counter() - phase) * 1000.
            phase = time.perf_counter()
            if self._mesh_ddr_mode and self._mesh_metadata and (rebuilt or self._bvh_buf is None):
                if self._bvh_buf is not None:
                    self._bvh_buf.freebuffer()
                    self._bvh_buf = None
                self._bvh_buf = allocate(shape=(len(image.node_bytes),), dtype='u1')
                self._bvh_buf[:] = np.frombuffer(image.node_bytes, dtype=np.uint8)
                self._bvh_buf.flush()
            if self._mesh_buf is None or self._mesh_capacity != len(mesh_raw):
                if self._mesh_buf is not None:
                    self._mesh_buf.freebuffer()
                    self._mesh_buf = None
                self._mesh_buf = allocate(shape=(len(mesh_raw),), dtype='u1')
                self._mesh_capacity = len(mesh_raw)
            dma_buffer_reused = self._select_mesh_io_buffers(ray_count, RESULT_BYTES, allocate)
            if mesh_key != self._mesh_key:
                self._mesh_buf[:len(mesh_raw)] = np.frombuffer(mesh_raw, dtype=np.uint8)
                self._mesh_buf.flush()
                mmio = self._mesh_mmio
                mmio.write(0x004, len(triangles))
                if self._mesh_mmio.read(0x02c) == MESH_UNION_ABI_VERSION:
                    mmio.write(0x098, solid_count)
                mmio.write(0x030, int(timeout_cycles))
                mmio.write(0x01C, 1)
                deadline = time.monotonic() + float(timeout_seconds)
                if self._mesh_ddr_mode:
                    physical = getattr(self._mesh_buf, 'device_address',
                                       getattr(self._mesh_buf, 'physical_address', 0))
                    if not physical:
                        raise RuntimeError('mesh DDR buffer has no physical address')
                    if int(physical) & 0xF:
                        raise RuntimeError('mesh DDR buffer is not 16-byte aligned')
                    if len(triangles) > 0xffffffff:
                        raise ValueError('triangle count exceeds DDR ABI limit')
                    mmio.write(0x034, int(physical) & 0xffffffff)
                    mmio.write(0x038, (int(physical) >> 32) & 0xffffffff)
                    if self._mesh_metadata:
                        bvh_physical = int(getattr(self._bvh_buf, 'device_address',
                                                   getattr(self._bvh_buf, 'physical_address', 0)))
                        if not bvh_physical or bvh_physical & 0xf:
                            raise RuntimeError('BVH buffer has no aligned physical address')
                        mmio.write(0x040, bvh_physical & 0xffffffff)
                        mmio.write(0x044, bvh_physical >> 32)
                        mmio.write(0x048, len(image.nodes))
                    mmio.write(0x03c, 3 if complete else 1)
                    mmio.write(0x000, 4)  # arm the DDR resident mesh
                else:
                    if self._mesh_dma is None:
                        raise RuntimeError('overlay has no BRAM mesh DMA')
                    self._mesh_dma.sendchannel.transfer(self._mesh_buf)
                    mmio.write(0x000, 4)
                    while not self._mesh_dma.sendchannel.idle:
                        if time.monotonic() >= deadline:
                            raise TimeoutError("mesh load DMA timeout")
                        time.sleep(0.0005)
                while mmio.read(0x024) != len(triangles):
                    if time.monotonic() >= deadline:
                        raise TimeoutError("mesh load completion timeout")
                    time.sleep(0.0005)
                self._mesh_key = mesh_key
            timings['mesh_upload'] = (time.perf_counter() - phase) * 1000.
            self._mesh_ray_input_buf[:len(ray_raw)] = np.frombuffer(ray_raw, dtype=np.uint8)
            self._mesh_result_buf[:] = 0
            self._mesh_ray_input_buf.flush(); self._mesh_result_buf.flush()
            self._mesh_job_id = (self._mesh_job_id + 1) & 0xFFFFFFFF or 1
            mmio = self._mesh_mmio
            mmio.write(0x004, len(triangles)); mmio.write(0x008, ray_count)
            if self._mesh_ddr_mode and self._mesh_mmio.read(0x02c) == MESH_UNION_ABI_VERSION:
                mmio.write(0x098, solid_count)
            if self._mesh_ddr_mode:
                mmio.write(0x03c, 9 if _distance else (7 if volume else (3 if complete else 1)))
            if complete:
                mmio.write(0x058, int(max_hits))
            mmio.write(0x00C, self._mesh_job_id); mmio.write(0x030, int(timeout_cycles)); mmio.write(0x01C, 1)
            started = time.perf_counter()
            self._mesh_result_dma.recvchannel.transfer(self._mesh_result_buf)
            mmio.write(0x000, 1)
            self._mesh_ray_dma.sendchannel.transfer(self._mesh_ray_input_buf)
            deadline = time.monotonic() + float(timeout_seconds)
            while not self._mesh_result_dma.recvchannel.idle or not self._mesh_ray_dma.sendchannel.idle:
                if time.monotonic() >= deadline:
                    raise TimeoutError("mesh ray result DMA timeout")
                errors = mmio.read(0x018) & 0xff
                if errors & 0x84:
                    raise TimeoutError('mesh ray hardware timeout/abort: 0x%02x' % errors)
                time.sleep(0.0005)
            self._mesh_result_dma.recvchannel.wait(); self._mesh_ray_dma.sendchannel.wait()
            timings['dma_wait'] = (time.perf_counter() - started) * 1000.
            phase = time.perf_counter()
            self._mesh_result_buf.invalidate()
            raw_result = bytes(self._mesh_result_buf[:ray_count * RESULT_BYTES])
            try:
                union_abi = self._mesh_mmio.read(0x02c) == MESH_UNION_ABI_VERSION
                if _distance:
                    decoded = decode_results(raw_result, ray_count)
                elif complete:
                    decoded = decode_results(raw_result, ray_count, volume=volume, union=union_abi,
                                             expected_solid_count=solid_count if solid_count > 1 else None)
                else:
                    decoded = decode_results(raw_result, ray_count)
            except ValueError as exc:
                raise RuntimeError('Invalid PL result frame: '+str(exc)) from exc
            values = decoded if complete else validate_results(decoded, ray_count)
            result_rows = values if complete else [dict(ray_id=item.ray_id, hit_count=item.hit_count,
                t_near_q16=item.t_near_q16, t_far_q16=item.t_far_q16) for item in values]
            errors = mmio.read(0x018) & 0xFF
            if complete:
                frame_errors = 0
                for row in result_rows:
                    frame_errors |= int(row['errors'])
                if frame_errors != errors:
                    raise RuntimeError('complete result errors disagree with hardware status')
            if errors:
                diagnostic = dict(results=result_rows,
                    errors=errors, processed=mmio.read(0x010), cycles=mmio.read(0x020))
                if volume:
                    diagnostic.update(volume_sum_q30=mmio.read(0x06c)|(mmio.read(0x070)<<32),
                                      volume_valid_rays=mmio.read(0x074),volume_mean_q30=mmio.read(0x078))
                raise RuntimeError("mesh ray hardware errors: 0x%02x" % errors)
            if mmio.read(0x010) != ray_count or mmio.read(0x00c) != self._mesh_job_id:
                raise RuntimeError('mesh result job/counter mismatch')
            volume_result = {}
            if volume:
                expected_lengths = np.frombuffer(ray_raw, dtype='<u4').reshape(-1, 8)[:, 7]
                if any(row['length_q16'] != int(length) for row, length in zip(result_rows, expected_lengths)):
                    raise RuntimeError('PL volume integration lengths disagree with request')
                total = mmio.read(0x06c) | (mmio.read(0x070) << 32)
                valid = mmio.read(0x074)
                mean = mmio.read(0x078)
                if valid != ray_count or total != sum(row['volume_fraction_q30'] for row in result_rows) or mean != total // valid:
                    raise RuntimeError('PL volume batch counters/mean disagree with frames')
                volume_result = dict(pl_volume=True, volume_sum_q30=total, volume_valid_rays=valid,
                                     volume_mean_q30=mean, volume_mean=mean/(1<<30))
            if _distance:
                valid=mmio.read(0x08c)
                minimum=mmio.read(0x080)|(mmio.read(0x084)<<32)|(mmio.read(0x088)<<64)
                if valid!=ray_count or minimum!=min(row['distance_squared_q32'] for row in result_rows):
                    raise RuntimeError('PL distance batch minimum/count disagree with frames')
                volume_result=dict(pl_distance=True,distance_valid_points=valid,
                    distance_min_squared_q32=minimum,distance_fraction_bits=32)
            timings['result_decode'] = (time.perf_counter() - phase) * 1000.
            timings['pl_compute'] = mmio.read(0x020) / ((self.clock_mhz or 100.) * 1000.)
            self.last_error = ''
            return dict(ok=True, results=result_rows,
                processed=mmio.read(0x010), hits=mmio.read(0x014), cycles=mmio.read(0x020),
                errors=errors, job_id=self._mesh_job_id,
                job_ms=(time.perf_counter() - started) * 1000., overlay_load_s=self._load_seconds,
                timings_ms=timings, mesh_reused=reused, dma_buffer_reused=dma_buffer_reused,
                bvh_nodes=len(image.nodes),
                complete_crossings=complete and not _distance, clock_mhz=self.clock_mhz,
                abi='0x%08x' % self._mesh_mmio.read(0x02c), solid_count=solid_count,
                union_event_count=sum(int(row.get('event_count', 0)) for row in result_rows),
                union_boundary_count=sum(int(row.get('union_boundary_count', 0)) for row in result_rows),
                operation='bvh_distance_pl' if _distance else ('bvh_volume_pl' if volume else ('bvh_pl' if complete else 'ddr_flat')), **volume_result)
        except Exception as exc:
            # Arithmetic errors after a fully drained job require CPU
            # fallback but leave a valid resident mesh and idle channels.
            drained_arithmetic = diagnostic is not None and not (diagnostic['errors'] & 0x8f)
            if isinstance(exc, (TimeoutError, RuntimeError, MemoryError)) and not drained_arithmetic:
                try:
                    if self._mesh_mmio is not None:
                        self._mesh_mmio.write(0x000, 2)
                except Exception:
                    pass
                try:
                    self._reset_hardware_state()
                except Exception as reset_exc:
                    exc = RuntimeError('%s; fabric reset failed: %s' % (exc, reset_exc))
            self.last_error = str(exc)
            logging.getLogger(__name__).exception("PL_MESH_RAY_FAILED")
            result = {"ok": False, "error": self.last_error}
            if diagnostic is not None:
                result['diagnostic'] = diagnostic
            return result

    def evaluate_mesh_distances(self, triangles, points, *, timeout_cycles=900_000_000,
                                timeout_seconds=15.0, solid_ids=None):
        return self.evaluate_mesh_rays(triangles, points, np.zeros_like(points),
            timeout_cycles=timeout_cycles, timeout_seconds=timeout_seconds,
            _distance=True, solid_ids=solid_ids)

    @_hardware_locked
    def close(self):
        self._packed_points_cache = None
        if self._privileged is not None:
            self._privileged.close()
            self._privileged = None
        if self._hardware_reset_failed:
            self._reset_hardware_state()
        if self._dual_mesh_mmio is not None and self._dual_mesh_mmio.read(DUAL_MESH_CONTROL) & 2:
            self._dual_mesh_mmio.write(DUAL_MESH_CONTROL, 2)
            self._reset_hardware_state()
        if self._mesh_mmio is not None and self._mesh_mmio.read(0x000) & 2:
            self._mesh_mmio.write(0x000, 2)
            self._reset_hardware_state()
        if self._centerline_mmio is not None and self._centerline_mmio.read(0) & 1:
            self._reset_hardware_state()
        for buffer in (self._point_buf, self._result_buf):
            if buffer is not None:
                try:
                    buffer.freebuffer()
                except Exception:
                    pass
        for buffer in (self._ray_input_buf, self._ray_output_buf,
                       self._mesh_buf, self._mesh_ray_input_buf,
                       self._mesh_result_buf, self._bvh_buf,
                       self._dual_input_buf, self._dual_output_buf,
                       self._dual_mesh_buf, self._dual_mesh_candidates_buf,
                       self._dual_mesh_segments_buf, self._dual_mesh_results_buf,
                       self._dual_mesh_bvh_buf,
                       *self._centerline_buffers,
                       *(buffer for pair in self._mesh_io_pool.values() for buffer in pair)):
            if buffer is not None:
                try:
                    buffer.freebuffer()
                except Exception:
                    pass
        self._point_buf = self._result_buf = None
        self._ray_input_buf = self._ray_output_buf = None
        self._mesh_buf = self._mesh_ray_input_buf = self._mesh_result_buf = None
        self._dual_input_buf = self._dual_output_buf = None
        self._dual_mesh_buf = self._dual_mesh_candidates_buf = None
        self._dual_mesh_segments_buf = self._dual_mesh_results_buf = None
        self._dual_mesh_bvh_buf = self._dual_mesh_image = None
        self._dual_mesh_source = None
        self._dual_mesh_frontend_source = None
        self._dual_mesh_mmio = self._dual_mesh_dma = None
        self._dual_mesh_key = None
        self._dual_mesh_job_id = 0
        self._mesh_io_pool.clear()
        self._point_capacity = self._ray_capacity = 0
        self._mesh_capacity = self._mesh_ray_capacity = 0
        self._mesh_key = None
        self._mesh_ddr_mode = False
        self._bvh_buf = self._mesh_image = None
        self._mesh_metadata = False
        self._mesh_complete = False
        self._mesh_volume = False
        self._mesh_result_stride = 16
        self._overlay = self._dma = self._mmio = None
        self._ray_dma = self._ray_mmio = None
        self._mesh_mmio = self._mesh_dma = self._mesh_ray_dma = self._mesh_result_dma = None
        self._centerline_dma = self._centerline_mmio = None
        self._centerline_buffers = []
        # PlannerController closes after its QThread has stopped; the
        # diagnostic closes on that worker. This loop is never run here.
        if self._event_loop is not None:
            self._event_loop.close()
            self._event_loop = None
