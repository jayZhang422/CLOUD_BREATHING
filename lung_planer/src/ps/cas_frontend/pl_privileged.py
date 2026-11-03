"""Persistent PYNQ subprocess, authorized by the desktop's PolicyKit agent."""
import base64
import hashlib
import json
import os
import queue
import shutil
import subprocess
import threading
import time
import uuid
from pathlib import Path

import numpy as np


class PrivilegedPlClient:
    def __init__(self, bit_path, *, require_strict_pl=False):
        self.require_strict_pl = require_strict_pl
        self.bit_path = Path(bit_path).resolve()
        self._io_lock = threading.RLock()
        self.process = None
        self._responses = queue.Queue()
        self._points_key = None
        self._mesh_key = None
        self._mesh_wire_cache = None
        self._dual_mesh_source_cache = None
        self._mesh_resource = None

    def cache_mesh_resource(self, resource):
        from .frozen_mesh import FrozenMesh
        if not isinstance(resource, FrozenMesh) or not resource.matches(resource.triangles, resource.solid_ids):
            raise ValueError('Expected an intact immutable mesh resource')
        with self._io_lock:
            cached = self._mesh_wire_cache
            # Independent lesions own distinct snapshots of the same lung.
            # Their content key includes exact coordinates AND solid labels;
            # reuse the wire image only while both snapshots remain intact.
            if (cached is not None and cached[0].key == resource.key
                    and cached[0].matches(cached[0].triangles, cached[0].solid_ids)):
                self._mesh_wire_cache = (resource, cached[1], cached[2])
            self._mesh_resource = resource

    def _command(self):
        authorization = os.environ.get('CLOUD_BREATHING_PL_AUTH', 'pkexec')
        if authorization == 'sudo':
            sudo = shutil.which('sudo')
            if not sudo:
                raise RuntimeError('Explicit sudo PL authorization requested, but sudo is missing')
            prefix = [sudo, '-n']
        elif authorization == 'pkexec':
            pkexec = shutil.which('pkexec')
            if not pkexec:
                raise RuntimeError('FPGA access requires root: pkexec is missing. '
                                   'Install policykit-1 on the board.')
            prefix = [pkexec, '--disable-internal-agent']
        else:
            raise ValueError('CLOUD_BREATHING_PL_AUTH must be pkexec or sudo')
        python = Path(os.environ.get('PYNQ_PYTHON', '/usr/local/share/pynq-venv/bin/python'))
        if not python.is_file():
            raise FileNotFoundError('PYNQ interpreter not found: ' + str(python))
        helper = Path(__file__).resolve().parents[1] / 'tools' / 'pl_service.py'
        bootstrap = helper.with_name('start_pl_service.sh')
        return prefix + ['/bin/bash', str(bootstrap),
                str(python), str(helper), os.environ.get('XILINX_XRT', ''),
                '--bit', str(self.bit_path)] + (['--strict-pl'] if self.require_strict_pl else [])

    def _read_output(self, process, responses):
        try:
            for line in process.stdout:
                responses.put(line)
        finally:
            responses.put(None)

    def _receive(self, timeout, *, cancel=None, request_id=None):
        deadline = time.monotonic() + timeout
        cancelled = False
        try:
            while True:
                if cancel is not None and cancel() and not cancelled:
                    self.process.stdin.write((json.dumps(dict(op='cancel_dual_plane_mesh',
                        request_id=request_id)) + '\n').encode())
                    self.process.stdin.flush()
                    cancelled = True
                remaining = deadline-time.monotonic()
                if remaining <= 0:
                    raise queue.Empty
                try:
                    line = self._responses.get(timeout=min(.05, remaining) if cancel else remaining)
                    break
                except queue.Empty:
                    if time.monotonic() >= deadline:
                        raise
        except queue.Empty:
            raise TimeoutError('PL service timeout. Check the desktop authorization dialog '
                               'and the FPGA startup log.') from None
        if line is None:
            try:
                code = self.process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                code = self.process.poll()
            raise RuntimeError('PL service exited (code %s). Authorization may have been '
                               'cancelled or no desktop PolicyKit agent is available; '
                               'see the preceding terminal log.' % code)
        result = json.loads(line)
        if request_id is not None and result.get('request_id') != request_id:
            raise RuntimeError('PL service stale mesh response')
        if cancelled or (cancel is not None and cancel()):
            raise RuntimeError('dual-plane mesh job cancelled')
        return result

    def _start(self):
        if self.process is not None and self.process.poll() is None:
            return
        self.close()
        self._responses = queue.Queue()
        # No root GUI and no public socket. Only this frontend holds the pipes.
        self.process = subprocess.Popen(self._command(), stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE)
        threading.Thread(target=self._read_output,
                         args=(self.process, self._responses), daemon=True).start()
        ready = self._receive(120)
        if ready.get('startup_error'):
            raise RuntimeError(ready['startup_error'])
        if ready != {'ready': True, 'protocol': 1}:
            raise RuntimeError('Invalid PL service handshake: ' + str(ready))

    def prepare(self):
        with self._io_lock:
            try:
                self._start()
                if self.require_strict_pl:
                    self.process.stdin.write(b'{"op":"prepare_strict"}\n')
                    self.process.stdin.flush()
                    result = self._receive(60)
                    if not result.get('ok'):
                        raise RuntimeError(result.get('error', 'Strict PL startup failed'))
                    if result.get('abi') not in ('0x00040000','0x00050000','0x00060000','0x00070000') or abs(result.get('clock_mhz', 0.) - 100.) > 1.:
                        raise RuntimeError('Strict PL ABI/100 MHz confirmation failed')
                    return result
            except Exception:
                self.close()
                raise

    def evaluate_mask_distances(self, volume, coordinates, *, max_radius=64, timeout_seconds=30.):
        with self._io_lock:
            started = time.perf_counter()
            try:
                startup_started = time.perf_counter()
                self._start()
                service_startup_ms = (time.perf_counter() - startup_started) * 1000.
                mask_pack_started = time.perf_counter()
                packed = np.packbits(volume.data.ravel(order='C'), bitorder='little').tobytes()
                mask_pack_ms = (time.perf_counter() - mask_pack_started) * 1000.
                coordinates_started = time.perf_counter()
                coords = np.asarray(coordinates, dtype='<u2').reshape(-1, 3)
                coordinate_bytes = coords.tobytes()
                coordinates_pack_ms = (time.perf_counter() - coordinates_started) * 1000.
                encoding_started = time.perf_counter()
                request = dict(op='evaluate_mask_distances', metadata=volume.metadata(),
                               mask_bits=base64.b64encode(packed).decode('ascii'),
                               mask_bits_sha256=hashlib.sha256(packed).hexdigest(),
                               coordinates=base64.b64encode(coordinate_bytes).decode('ascii'),
                               max_radius=int(max_radius), timeout_seconds=float(timeout_seconds))
                encoded_request = (json.dumps(request, allow_nan=False)+'\n').encode()
                request_encode_ms = (time.perf_counter() - encoding_started) * 1000.
                write_started = time.perf_counter()
                self.process.stdin.write(encoded_request)
                self.process.stdin.flush()
                request_write_ms = (time.perf_counter() - write_started) * 1000.
                response_started = time.perf_counter()
                result = self._receive(max(60., timeout_seconds+10))
                response_wait_parse_ms = (time.perf_counter() - response_started) * 1000.
                result['service_ms'] = (time.perf_counter()-started)*1000
                result['transport_timings_ms'] = dict(
                    service_startup=service_startup_ms, mask_pack=mask_pack_ms,
                    coordinate_pack=coordinates_pack_ms, request_encode=request_encode_ms,
                    request_write=request_write_ms, response_wait_parse=response_wait_parse_ms,
                    total=(time.perf_counter()-started)*1000)
                result['transport_bytes'] = dict(request=len(encoded_request),
                                                 packed_mask=len(packed),
                                                 coordinates=len(coordinate_bytes))
                return result
            except Exception:
                self.close()
                raise

    def evaluate(self, points, vertices, minimum_clearance):
        with self._io_lock:
            started = time.perf_counter()
            try:
                self._start()
                points = np.asarray(points, dtype='<f8').reshape(-1, 3)
                data = points.tobytes()
                key = hashlib.sha256(data).hexdigest()
                request = dict(op='evaluate', points_key=key,
                               vertices=np.asarray(vertices, dtype=float).reshape(4, 3).tolist(),
                               minimum_clearance=float(minimum_clearance))
                if key != self._points_key:
                    request['points'] = base64.b64encode(data).decode('ascii')
                self.process.stdin.write((json.dumps(request, allow_nan=False) + '\n').encode())
                self.process.stdin.flush()
                result = self._receive(30)
                if result.get('ok'):
                    self._points_key = key
                result['service_ms'] = (time.perf_counter() - started) * 1000
                return result
            except Exception:
                self.close()
                raise

    def evaluate_dual_plane_filter_batch(self, points, candidates, minimum_clearance, *, timeout_seconds=30.0):
        with self._io_lock:
            started = time.perf_counter()
            try:
                self._start()
                points = np.asarray(points, dtype='<f8').reshape(-1, 3)
                data = points.tobytes()
                key = hashlib.sha256(data).hexdigest()
                candidates = np.asarray(candidates, dtype=float).reshape(-1, 4, 3)
                request = dict(op='evaluate_dual_plane_filter_batch', points_key=key,
                               candidates=candidates.tolist(),
                               minimum_clearance=float(minimum_clearance),
                               timeout_seconds=float(timeout_seconds))
                if key != self._points_key:
                    request['points'] = base64.b64encode(data).decode('ascii')
                self.process.stdin.write((json.dumps(request, allow_nan=False) + '\n').encode())
                self.process.stdin.flush()
                result = self._receive(max(30.0, float(timeout_seconds) + 5.0))
                if result.get('ok'):
                    self._points_key = key
                result['service_ms'] = (time.perf_counter() - started) * 1000.0
                result['transport_bytes'] = dict(points=len(data))
                return result
            except Exception:
                self.close()
                raise

    def evaluate_dual_plane_filter(self, points, vertices, minimum_clearance, *, timeout_seconds=30.0):
        return self.evaluate_dual_plane_filter_batch(
            points, np.asarray(vertices, dtype=float).reshape(1, 4, 3),
            minimum_clearance, timeout_seconds=timeout_seconds)

    def evaluate_dual_plane_mesh_batch(self, triangles, candidates, minimum_clearance=0., *,
                                       timeout_seconds=60.0, reference_only=False, cancel=None):
        """Send resident union triangles and wedge descriptors to the mesh ABI."""
        from .dual_plane_mesh_bvh import is_bytes_backed_mesh

        with self._io_lock:
            started = time.perf_counter()
            try:
                self._start()
                startup_finished = time.perf_counter()
                source = triangles
                triangles = np.asarray(triangles, dtype='<f8').reshape(-1, 3, 3)
                candidates = np.asarray(candidates, dtype='<f8').reshape(-1, 4, 3)
                cached = self._dual_mesh_source_cache
                same = (cached is not None and source is cached[0]
                        and triangles.shape == cached[2] and triangles.flags.c_contiguous
                        and is_bytes_backed_mesh(triangles))
                raw = None if same else triangles.tobytes()
                key = cached[1] if same else hashlib.sha256(raw).hexdigest()
                mesh_finished = time.perf_counter()
                request_id = uuid.uuid4().hex
                request = dict(op='evaluate_dual_plane_mesh_batch', mesh_key=key, request_id=request_id,
                               candidates=candidates.tolist(),
                               minimum_clearance=float(minimum_clearance),
                               timeout_seconds=float(timeout_seconds),
                               reference_only=bool(reference_only))
                if key != getattr(self, '_mesh_key', None):
                    if raw is None:
                        raw = triangles.tobytes()
                    request['triangles'] = base64.b64encode(raw).decode('ascii')
                request_finished = time.perf_counter()
                encoded = (json.dumps(request, allow_nan=False) + '\n').encode()
                encode_finished = time.perf_counter()
                self.process.stdin.write(encoded)
                self.process.stdin.flush()
                write_finished = time.perf_counter()
                result = self._receive(max(60.0, float(timeout_seconds) + 5.0),
                                       cancel=cancel, request_id=request_id)
                receive_finished = time.perf_counter()
                if result.get('ok'):
                    self._mesh_key = key
                    self._dual_mesh_source_cache = (source, key, triangles.shape) if is_bytes_backed_mesh(triangles) else None
                result['service_ms'] = (time.perf_counter() - started) * 1000.0
                result['transport_timings_ms'] = dict(
                    startup=(startup_finished-started)*1000.,
                    mesh_identity=(mesh_finished-startup_finished)*1000.,
                    request_pack=(request_finished-mesh_finished)*1000.,
                    json_encode=(encode_finished-request_finished)*1000.,
                    pipe_write=(write_finished-encode_finished)*1000.,
                    response_wait_parse=(receive_finished-write_finished)*1000.)
                result['transport_bytes'] = dict(triangles=triangles.nbytes if raw is not None else 0,
                                                 request=len(encoded))
                return result
            except Exception:
                self.close()
                raise

    def evaluate_rays(self, packed_records, record_count, *,
                      timeout_cycles=50_000_000, timeout_seconds=5.0):
        """Send a packed ray batch through the already running PL service."""
        with self._io_lock:
            started = time.perf_counter()
            try:
                self._start()
                raw = bytes(packed_records)
                count = int(record_count)
                if count <= 0 or len(raw) != count * 80:
                    raise ValueError('ray record buffer size mismatch')
                request = dict(op='evaluate_rays',
                               records=base64.b64encode(raw).decode('ascii'),
                               record_count=count,
                               timeout_cycles=int(timeout_cycles),
                               timeout_seconds=float(timeout_seconds))
                self.process.stdin.write((json.dumps(request, allow_nan=False) + '\n').encode())
                self.process.stdin.flush()
                result = self._receive(max(30.0, float(timeout_seconds) + 5.0))
                result['service_ms'] = (time.perf_counter() - started) * 1000
                return result
            except Exception:
                self.close()
                raise

    def evaluate_mesh_rays(self, triangles, origins, directions, *,
                           timeout_cycles=50_000_000, timeout_seconds=10.0, max_hits=128,
                           lengths=None, _distance=False, solid_ids=None):
        """Use the mesh-resident ABI through the persistent root helper."""
        with self._io_lock:
            started = time.perf_counter()
            try:
                self._start()
                resource = self._mesh_resource
                resource = resource if resource is not None and resource.matches(triangles, solid_ids) else None
                triangles = resource.triangles if resource else np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
                startup_finished = time.perf_counter()
                from .mesh_bvh import build_mesh_image, _solid_ids
                from .ray_mesh import pack_mesh, pack_rays
                ids = resource.solid_ids if resource else _solid_ids(solid_ids, len(triangles))
                solid_count = resource.solid_count if resource else int(ids.max()) + 1
                cached = self._mesh_wire_cache
                same = resource is not None and cached is not None and cached[0] is resource
                if same:
                    mesh_raw, mesh_key = cached[1], cached[2]
                else:
                    mesh_raw = (pack_mesh(triangles) if solid_count == 1 else
                                build_mesh_image(triangles, solid_ids=ids).triangle_bytes)
                    mesh_key = hashlib.sha256(mesh_raw).hexdigest()
                    self._mesh_wire_cache = (resource, mesh_raw, mesh_key) if resource else None
                mesh_finished = time.perf_counter()
                ray_raw = pack_rays(origins, directions, first_ray_id=1, lengths=lengths)
                request = dict(op='evaluate_mesh_rays', mesh_key=mesh_key, max_hits=int(max_hits),
                               solid_count=solid_count,
                               triangle_count=len(triangles), ray_count=len(origins),
                               rays=base64.b64encode(ray_raw).decode('ascii'),
                               timeout_cycles=int(timeout_cycles),
                               timeout_seconds=float(timeout_seconds))
                request['volume'] = lengths is not None
                request['distance'] = bool(_distance)
                # BVH packing reorders triangles, so protocol labels must use
                # the same wire order as the packed triangle records.
                if mesh_key != self._mesh_key:
                    wire_ids = np.frombuffer(mesh_raw, dtype='<u4').reshape(-1, 12)[:, 9]
                    request['solid_ids'] = wire_ids.tolist()
                    request['mesh'] = base64.b64encode(mesh_raw).decode('ascii')
                packing_finished = time.perf_counter()
                self.process.stdin.write((json.dumps(request, allow_nan=False) + '\n').encode())
                self.process.stdin.flush()
                write_finished = time.perf_counter()
                result = self._receive(max(60.0, float(timeout_seconds) + 10.0))
                receive_finished = time.perf_counter()
                if result.get('ok'):
                    self._mesh_key = mesh_key
                result['service_ms'] = (time.perf_counter() - started) * 1000
                result['transport_timings_ms'] = dict(
                    startup=(startup_finished - started) * 1000.,
                    mesh_validation_pack=(mesh_finished - startup_finished) * 1000.,
                    request_pack=(packing_finished - mesh_finished) * 1000.,
                    encode_write=(write_finished - packing_finished) * 1000.,
                    wait_decode=(receive_finished - write_finished) * 1000.)
                return result
            except Exception:
                self.close()
                raise

    def close(self):
        with self._io_lock:
            process, self.process = self.process, None
            self._points_key = None
            self._mesh_key = None
            self._mesh_wire_cache = None
            self._dual_mesh_source_cache = None
            if process is None:
                return
            # EOF asks the privileged helper to free DMA buffers and exit. The
            # unprivileged parent cannot assume it can signal the root process.
            if process.stdin is not None:
                try:
                    process.stdin.close()
                except (BrokenPipeError, OSError):
                    pass
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            if process.poll() is not None and process.stdout is not None:
                process.stdout.close()
