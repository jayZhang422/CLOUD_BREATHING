#!/usr/bin/env python3
"""Headless privileged PL helper. It serves only its parent's stdin/stdout."""
import argparse
import base64
import hashlib
import json
import os
import shutil
import sys
import queue
import threading
from time import perf_counter
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np

MAX_LINE = 20 * 1024 * 1024


class CancellableInput:
    """Keep reading the private parent pipe while a hardware job is running."""
    def __init__(self, source):
        self.source = source
        self.lines = queue.Queue(maxsize=2)
        self.lock = threading.Lock()
        self.active = {}
        self.disconnected = threading.Event()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        try:
            while True:
                line = self.source.readline(MAX_LINE + 1)
                if not line:
                    break
                try:
                    job = json.loads(line) if len(line) <= MAX_LINE else {}
                    token = job.get('request_id')
                    if job.get('op') == 'cancel_dual_plane_mesh':
                        with self.lock:
                            event = self.active.get(token)
                            if event is not None:
                                event.set()
                        continue  # No extra response can contaminate the next job.
                    if job.get('op') == 'evaluate_dual_plane_mesh_batch' and isinstance(token, str):
                        with self.lock:
                            self.active[token] = threading.Event()
                except (ValueError, TypeError, AttributeError):
                    pass  # The worker emits the normal protocol error.
                self.lines.put(line)
                if len(line) > MAX_LINE:
                    break
        finally:
            self.disconnected.set()
            self.lines.put('')

    def readline(self, limit):
        return self.lines.get()

    def cancelled(self, token):
        with self.lock:
            event = self.active.get(token)
            return self.disconnected.is_set() or (event is not None and event.is_set())

    def completed(self, token):
        with self.lock:
            self.active.pop(token, None)


def serve(client, source, destination):
    points, points_key = None, None
    mesh, mesh_key, mesh_solid_ids = None, None, None
    mesh_cache = None
    request_id = None

    def reply(value):
        if request_id is not None:
            value = dict(value, request_id=request_id)
        destination.write(json.dumps(value, allow_nan=False) + '\n')
        destination.flush()
        if request_id is not None and hasattr(source, 'completed'):
            source.completed(request_id)

    reply({'ready': True, 'protocol': 1})
    try:
        while True:
            line = source.readline(MAX_LINE + 1)
            if not line:
                break
            if len(line) > MAX_LINE:
                reply({'ok': False, 'error': 'PL request exceeds size limit'})
                break
            try:
                request_id = None
                started = perf_counter()
                job = json.loads(line)
                request_id = job.get('request_id')
                parsed = perf_counter()
                driver_started = None
                driver_finished = None
                phase_timings = {}
                operation = job.get('op')
                if operation == 'prepare_strict':
                    if not client.require_strict_pl:
                        raise RuntimeError('Service is not configured for strict stage three')
                    with redirect_stdout(sys.stderr):
                        client.prepare()
                    # Dual-plane-only overlays have no legacy mesh_ray core.
                    if client._mesh_mmio is not None:
                        abi = client._mesh_mmio.read(0x02c)
                    else:
                        abi = client._dual_mesh_mmio.read(0x014)
                    result = dict(ok=True, abi='0x%08x' % abi, clock_mhz=client.clock_mhz)
                elif operation == 'evaluate_mask_distances':
                    from cas_frontend.voxel_mask import VoxelMask, SCHEMA
                    phase_started = perf_counter()
                    metadata = job['metadata']
                    if (metadata['schema'] != SCHEMA or metadata['layout'] != 'C-xyz-z-fastest'
                            or metadata['coordinate_frame'] != 'stl-mm' or metadata['units'] != 'mm'
                            or metadata['index_location'] != 'voxel-center'):
                        raise ValueError('Invalid shared mask metadata')
                    shape = metadata['shape_xyz']
                    if (not isinstance(shape, list) or len(shape) != 3
                            or any(not isinstance(v, int) or v < 1 or v > 1024 for v in shape)):
                        raise ValueError('Invalid mask shape')
                    size = int(np.prod(shape))
                    if size > 48_000_000:
                        raise ValueError('Mask exceeds volume capacity')
                    phase_timings['metadata_validation'] = (perf_counter() - phase_started) * 1000.
                    phase_started = perf_counter()
                    packed = base64.b64decode(job['mask_bits'], validate=True)
                    if (len(packed) != (size+7)//8
                            or hashlib.sha256(packed).hexdigest() != job['mask_bits_sha256']):
                        raise ValueError('Invalid packed mask payload')
                    phase_timings['mask_decode_hash'] = (perf_counter() - phase_started) * 1000.
                    phase_started = perf_counter()
                    mask = np.unpackbits(np.frombuffer(packed, dtype='u1'), bitorder='little', count=size).reshape(shape)
                    # unpackbits guarantees binary values; carry that proof past VoxelMask validation.
                    mask = mask.view(np.bool_)
                    phase_timings['mask_unpack'] = (perf_counter() - phase_started) * 1000.
                    phase_started = perf_counter()
                    raw_coords = base64.b64decode(job['coordinates'], validate=True)
                    if not raw_coords or len(raw_coords)%6:
                        raise ValueError('Invalid mask query payload')
                    coordinates = np.frombuffer(raw_coords, dtype='<u2').reshape(-1, 3)
                    phase_timings['coordinates_decode'] = (perf_counter() - phase_started) * 1000.
                    phase_started = perf_counter()
                    volume = VoxelMask(mask, metadata['spacing_mm'], metadata['origin_mm'],
                                       metadata['direction'], metadata['source'])
                    phase_timings['mask_validate_copy'] = (perf_counter() - phase_started) * 1000.
                    driver_started = perf_counter()
                    with redirect_stdout(sys.stderr):
                        result = client.evaluate_mask_distances(volume, coordinates,
                            max_radius=int(job.get('max_radius', 64)),
                            timeout_seconds=float(job.get('timeout_seconds', 30.)))
                    driver_finished = perf_counter()
                elif operation == 'evaluate':
                    key = job['points_key']
                    if 'points' in job:
                        raw = base64.b64decode(job['points'], validate=True)
                        if not raw or len(raw) % 24 or hashlib.sha256(raw).hexdigest() != key:
                            raise ValueError('Invalid tumor point payload')
                        points = np.frombuffer(raw, dtype='<f8').reshape(-1, 3)
                        points_key = key
                    elif points is None or key != points_key:
                        raise ValueError('Tumor point cache is missing')
                    vertices = np.asarray(job['vertices'], dtype=np.float64).reshape(4, 3)
                    margin = float(job['minimum_clearance'])
                    if (not np.isfinite(points).all() or not np.isfinite(vertices).all()
                            or not np.isfinite(margin)):
                        raise ValueError('Nonfinite PL input')
                    # Library diagnostics go to the application log, leaving the
                    # stdout pipe dedicated to JSON responses.
                    with redirect_stdout(sys.stderr):
                        result = client.evaluate(points, vertices, margin)
                elif operation in ('evaluate_dual_plane_filter', 'evaluate_dual_plane_filter_batch'):
                    key = job['points_key']
                    if 'points' in job:
                        raw = base64.b64decode(job['points'], validate=True)
                        if not raw or len(raw) % 24 or hashlib.sha256(raw).hexdigest() != key:
                            raise ValueError('Invalid dual-plane point payload')
                        points = np.frombuffer(raw, dtype='<f8').reshape(-1, 3)
                        points_key = key
                    elif points is None or key != points_key:
                        raise ValueError('Tumor point cache is missing')
                    candidates = (np.asarray(job['candidates'], dtype=np.float64).reshape(-1, 4, 3)
                                  if operation.endswith('_batch') else
                                  np.asarray(job['vertices'], dtype=np.float64).reshape(1, 4, 3))
                    margin = float(job['minimum_clearance'])
                    timeout_seconds = float(job.get('timeout_seconds', 5.0))
                    if (not np.isfinite(points).all() or not np.isfinite(candidates).all()
                            or len(points) == 0 or len(candidates) == 0
                            or not np.isfinite(margin) or margin < 0
                            or not np.isfinite(timeout_seconds) or timeout_seconds <= 0):
                        raise ValueError('Invalid dual-plane filter input')
                    with redirect_stdout(sys.stderr):
                        if operation.endswith('_batch'):
                            result = client.evaluate_dual_plane_filter_batch(
                                points, candidates, margin, timeout_seconds=timeout_seconds)
                        else:
                            result = client.evaluate_dual_plane_filter(
                                points, candidates[0], margin, timeout_seconds=timeout_seconds)
                elif operation == 'evaluate_dual_plane_mesh_batch':
                    mesh_started = perf_counter()
                    raw = (base64.b64decode(job['triangles'], validate=True)
                           if 'triangles' in job else None)
                    mesh_key = str(job.get('mesh_key', ''))
                    if raw is not None:
                        if not raw or len(raw) % (9 * 8) or hashlib.sha256(raw).hexdigest() != mesh_key:
                            raise ValueError('Invalid dual-plane mesh payload')
                        triangles = np.frombuffer(raw, dtype='<f8').reshape(-1, 3, 3)
                    elif mesh_cache is None or mesh_cache[0] != mesh_key:
                        raise ValueError('Dual-plane mesh cache is missing')
                    else:
                        triangles = mesh_cache[1]
                    mesh_finished = perf_counter()
                    candidates = np.asarray(job['candidates'], dtype=np.float64).reshape(-1, 4, 3)
                    margin = float(job.get('minimum_clearance', 0.))
                    if (not len(triangles) or not len(candidates) or
                            (raw is not None and not np.isfinite(triangles).all()) or
                            not np.isfinite(candidates).all() or
                            not np.isfinite(margin) or margin < 0):
                        raise ValueError('Invalid dual-plane mesh input')
                    if raw is not None:
                        mesh_cache = (mesh_key, triangles)
                    validation_finished = perf_counter()
                    if not job.get('reference_only'):
                        # Root owns the PYNQ MMIO/CMA buffers.  Keep the
                        # unprivileged protocol as a thin transport layer so
                        # the same ABI-0x00050000 implementation is exercised
                        # on the board instead of silently running a CPU copy.
                        with redirect_stdout(sys.stderr):
                            driver_started = perf_counter()
                            result = client.evaluate_dual_plane_mesh_batch(
                                triangles, candidates, margin,
                                timeout_seconds=float(job.get('timeout_seconds', 60.)),
                                cancel=(lambda: source.cancelled(request_id))
                                    if hasattr(source, 'cancelled') else None,
                                reference_only=False, _verified_mesh_key=mesh_key)
                            driver_finished = perf_counter()
                        mesh_cache = (mesh_key, triangles)
                        result['server_timings_ms'] = dict(
                            json_parse=(parsed-started)*1000.,
                            mesh_decode_validate=(mesh_finished-mesh_started)*1000.,
                            candidate_decode_validate=(validation_finished-mesh_finished)*1000.,
                            driver=(driver_finished-driver_started)*1000.,
                            total=(perf_counter()-started)*1000.)
                        reply(result)
                        continue
                    with redirect_stdout(sys.stderr):
                        result = client.evaluate_dual_plane_mesh_batch(
                            triangles, candidates, margin,
                            timeout_seconds=float(job.get('timeout_seconds', 60.)),
                            reference_only=True)

                elif operation == 'evaluate_rays':
                    raw = base64.b64decode(job['records'], validate=True)
                    record_count = int(job['record_count'])
                    timeout_cycles = int(job.get('timeout_cycles', 50_000_000))
                    timeout_seconds = float(job.get('timeout_seconds', 5.0))
                    if record_count <= 0 or len(raw) != record_count * 80:
                        raise ValueError('Invalid ray record payload')
                    if timeout_cycles <= 0 or timeout_cycles > 0xFFFFFFFF:
                        raise ValueError('Invalid ray timeout_cycles')
                    if not np.isfinite(timeout_seconds) or timeout_seconds <= 0:
                        raise ValueError('Invalid ray timeout_seconds')
                    with redirect_stdout(sys.stderr):
                        result = client.evaluate_rays(
                            raw, record_count, timeout_cycles=timeout_cycles,
                            timeout_seconds=timeout_seconds)
                elif operation == 'evaluate_mesh_rays':
                    from cas_frontend.ray_mesh import RAY_BYTES, TRIANGLE_BYTES
                    from cas_frontend.mesh_bvh import MAX_SOLIDS
                    triangle_count = int(job['triangle_count'])
                    ray_count = int(job['ray_count'])
                    key = str(job['mesh_key'])
                    if 'mesh' in job:
                        mesh_raw = base64.b64decode(job['mesh'], validate=True)
                        if (len(mesh_raw) != triangle_count * TRIANGLE_BYTES
                                or hashlib.sha256(mesh_raw).hexdigest() != key):
                            raise ValueError('Invalid mesh payload')
                        # Decode the wire words before reshaping.  Chaining
                        # ``reshape`` after the scalar division is a subtle
                        # precedence bug: NumPy can end up applying it to a
                        # float scalar instead of to the 9-word triangle
                        # array.  Keep the intermediate explicitly typed so
                        # the privileged service and the unprivileged client
                        # use the same Q16.16 layout.
                        mesh_words = np.frombuffer(mesh_raw, dtype='<u4')
                        mesh_words = mesh_words.reshape(triangle_count, 12)
                        mesh_solid_ids = mesh_words[:, 9].copy()
                        requested_solid_count = int(job.get('solid_count', 1))
                        if requested_solid_count < 1 or requested_solid_count > MAX_SOLIDS:
                            raise ValueError('Invalid solid count')
                        if int(mesh_solid_ids.max()) + 1 != requested_solid_count:
                            raise ValueError('Mesh solid labels disagree with solid count')
                        if job.get('solid_ids') is not None and list(map(int, job['solid_ids'])) != mesh_solid_ids.tolist():
                            raise ValueError('Mesh labels disagree with request metadata')
                        mesh = (mesh_words[:, :9].view('<i4').astype(np.float64) / 65536.0)
                        mesh = mesh.reshape(triangle_count, 3, 3)
                        from cas_frontend.frozen_mesh import FrozenMesh
                        resource = FrozenMesh(mesh, mesh_solid_ids)
                        mesh, mesh_solid_ids = resource.triangles, resource.solid_ids
                        client.cache_mesh_resource(resource)
                        mesh_key = key
                    elif mesh is None or key != mesh_key:
                        raise ValueError('Mesh cache is missing')
                    if triangle_count != len(mesh) or int(job.get('solid_count', 1)) != int(mesh_solid_ids.max()) + 1:
                        raise ValueError('Cached mesh dimensions or solid count disagree')
                    if job.get('solid_ids') is not None and list(map(int, job['solid_ids'])) != mesh_solid_ids.tolist():
                        raise ValueError('Cached mesh labels disagree with request metadata')
                    raw = base64.b64decode(job['rays'], validate=True)
                    if ray_count <= 0 or len(raw) != ray_count * RAY_BYTES:
                        raise ValueError('Invalid mesh ray payload')
                    words = np.frombuffer(raw, dtype='<u4').reshape(ray_count, 8)
                    origin_words = words[:, 1:4]
                    direction_words = words[:, 4:7]
                    origins = origin_words.view('<i4').astype(np.float64) / 65536.0
                    directions = direction_words.view('<i4').astype(np.float64) / 65536.0
                    lengths = words[:,7].view('<i4').astype(np.float64)/65536.0 if job.get('volume') else None
                    timeout_cycles = int(job.get('timeout_cycles', 50_000_000))
                    timeout_seconds = float(job.get('timeout_seconds', 10.0))
                    driver_started = perf_counter()
                    with redirect_stdout(sys.stderr):
                        result = client.evaluate_mesh_rays(
                            mesh, origins, directions, timeout_cycles=timeout_cycles,
                            timeout_seconds=timeout_seconds, max_hits=int(job.get('max_hits', 128)), lengths=lengths,
                            solid_ids=mesh_solid_ids,
                            **({"_distance": True} if job.get("distance") else {}))
                    driver_finished = perf_counter()
                else:
                    raise ValueError('Unsupported PL operation')
                if driver_started is not None:
                    result['server_timings_ms'] = dict(
                        json_parse=(parsed - started) * 1000.,
                        unpack_validation=(driver_started - parsed) * 1000.,
                        driver=(driver_finished - driver_started) * 1000.,
                        total=(perf_counter() - started) * 1000.)
                    result['server_timings_ms'].update(phase_timings)
                reply(result)
            except Exception as exc:
                reply({'ok': False, 'error': '%s: %s' % (type(exc).__name__, exc)})
    finally:
        with redirect_stdout(sys.stderr):
            client.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bit', required=True, type=Path)
    parser.add_argument('--strict-pl', action='store_true')
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise PermissionError('PL service must be authorized as root')
    os.environ['LUNG_PL_BIT'] = str(args.bit.resolve())
    os.environ['OPENBLAS_NUM_THREADS'] = '1'
    try:
        with redirect_stdout(sys.stderr):
            if not os.environ.get('XILINX_XRT'):
                raise RuntimeError('XILINX_XRT missing before PYNQ import; use start_pl_service.sh')
            from cas_frontend.pl_metrics import PlMetrics, _import_pynq
            _import_pynq()
            from pynq.pl_server import Device
            devices = Device.devices
            firmware = Path('/sys/class/fpga_manager/fpga0/firmware').is_file()
            print('PL_DEVICE_PROBE ' + json.dumps(dict(
                uid=os.geteuid(), xrt=os.environ.get('XILINX_XRT'),
                xbutil=shutil.which('xbutil'), fpga_manager=firmware,
                devices=[type(device).__name__ for device in devices])), flush=True)
            if not devices:
                raise RuntimeError('No PYNQ devices after XRT initialization; '
                                   'check /sys/class/fpga_manager/fpga0/firmware and zocl driver')
            from tools.check_xclbinutil import check_xclbinutil
            check_xclbinutil()
            client = PlMetrics(require_strict_pl=args.strict_pl)
    except Exception as exc:
        print(json.dumps(dict(ready=False, startup_error=str(exc))), flush=True)
        return 1
    serve(client, CancellableInput(sys.stdin), sys.stdout)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
