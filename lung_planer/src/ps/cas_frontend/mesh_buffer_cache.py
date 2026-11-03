"""Opt-in, bounded display-buffer cache; no source mesh or PL data is cached."""

import hashlib
import json
import os
from pathlib import Path
import struct
from tempfile import NamedTemporaryFile
from time import perf_counter

import numpy as np

from .mesh_buffers import DISPLAY_BUFFER_ALGORITHM_VERSION, prepare_display_buffers


CACHE_FORMAT_VERSION = 1
MAGIC = b"CBMBUF1\n"
PREFIX = struct.Struct("<8sI")
MAX_HEADER_BYTES = 4096
MAX_PAYLOAD_BYTES = 64 * 1024 * 1024


def _hash_array(digest, value):
    array = np.asarray(value)
    if array.dtype.hasobject or array.dtype.kind not in "biuf":
        raise ValueError("Display cache requires numeric arrays")
    descriptor = json.dumps([array.dtype.str, array.shape], separators=(",", ":")).encode("ascii")
    digest.update(struct.pack("<I", len(descriptor)))
    digest.update(descriptor)
    digest.update(memoryview(np.ascontiguousarray(array)).cast("B"))


def _source_key(vertices, normals, center, scale, shading):
    """Hash exact input bytes and transform types, not filenames or timestamps."""
    digest = hashlib.sha256()
    descriptor = json.dumps([CACHE_FORMAT_VERSION, DISPLAY_BUFFER_ALGORITHM_VERSION, shading],
                            separators=(",", ":")).encode("ascii")
    digest.update(struct.pack("<I", len(descriptor)))
    digest.update(descriptor)
    for value in (vertices, normals, center, scale):
        _hash_array(digest, value)
    return digest.hexdigest()


def _payload_digest(vertex_data, index_data):
    digest = hashlib.sha256(vertex_data)
    digest.update(index_data)
    return digest.hexdigest()


def _integer(header, key):
    value = header[key]
    if type(value) is not int or value < 0:
        raise ValueError(f"Invalid display cache {key}")
    return value


def _read_entry(path, key, triangle_count):
    """Validate lengths against trusted input before reading any payload."""
    maximum_payload = min(triangle_count * 72, MAX_PAYLOAD_BYTES)
    with path.open("rb") as stream:
        file_size = os.fstat(stream.fileno()).st_size
        if file_size > PREFIX.size + MAX_HEADER_BYTES + maximum_payload:
            raise ValueError("Display cache payload exceeds input-derived limit")
        prefix = stream.read(PREFIX.size)
        if len(prefix) != PREFIX.size:
            raise ValueError("Truncated display cache prefix")
        magic, header_size = PREFIX.unpack(prefix)
        if magic != MAGIC or not 0 < header_size <= MAX_HEADER_BYTES:
            raise ValueError("Invalid display cache prefix")
        header_data = stream.read(header_size)
        if len(header_data) != header_size:
            raise ValueError("Truncated display cache header")
        header = json.loads(header_data)
        if not isinstance(header, dict) or header.get("key") != key:
            raise ValueError("Display cache input mismatch")
        if (_integer(header, "format_version") != CACHE_FORMAT_VERSION
                or _integer(header, "algorithm_version") != DISPLAY_BUFFER_ALGORITHM_VERSION
                or header.get("shading_request") != "smooth"
                or _integer(header, "triangle_count") != triangle_count):
            raise ValueError("Stale display cache")
        vertex_count = _integer(header, "vertex_count")
        vertex_bytes = _integer(header, "vertex_bytes")
        index_bytes = _integer(header, "index_bytes")
        if not 0 < vertex_count <= triangle_count * 3 or vertex_bytes != vertex_count * 24:
            raise ValueError("Invalid display cache vertex count")
        if header.get("shading") == "smooth":
            if (vertex_count > 65536 or index_bytes != triangle_count * 6
                    or header.get("reason") != "indexed"):
                raise ValueError("Invalid GLES2 display cache indices")
        elif header.get("shading") == "flat":
            if (vertex_count != triangle_count * 3 or index_bytes != 0
                    or header.get("reason") not in ("uint16-limit", "no-byte-saving")):
                raise ValueError("Invalid display cache fallback")
        else:
            raise ValueError("Invalid display cache shading")
        payload_bytes = vertex_bytes + index_bytes
        if (_integer(header, "upload_bytes") != payload_bytes
                or _integer(header, "soup_bytes") != triangle_count * 72
                or payload_bytes > maximum_payload
                or file_size != PREFIX.size + header_size + payload_bytes):
            raise ValueError("Invalid display cache payload length")
        vertex_data = stream.read(vertex_bytes)
        index_data = stream.read(index_bytes)
        if len(vertex_data) != vertex_bytes or len(index_data) != index_bytes:
            raise ValueError("Truncated display cache payload")
    if header.get("payload_sha256") != _payload_digest(vertex_data, index_data):
        raise ValueError("Corrupt display cache payload")
    packed = np.frombuffer(vertex_data, dtype="<f4").reshape(-1, 6)
    if not np.isfinite(packed).all():
        raise ValueError("Non-finite display cache data")
    if index_data:
        indices = np.frombuffer(index_data, dtype="<u2")
        if int(indices.max()) >= vertex_count:
            raise ValueError("Display cache index outside vertex buffer")
    low = np.asarray(header["low"], dtype="<f4")
    high = np.asarray(header["high"], dtype="<f4")
    if (low.shape != (3,) or high.shape != (3,)
            or not np.array_equal(low, packed[:, :3].min(axis=0))
            or not np.array_equal(high, packed[:, :3].max(axis=0))):
        raise ValueError("Invalid display cache bounds")
    return {"vertex_data": vertex_data, "index_data": index_data, "low": low, "high": high,
            "triangle_count": triangle_count, "vertex_count": vertex_count,
            "upload_bytes": payload_bytes, "soup_bytes": triangle_count * 72,
            "shading": header["shading"], "reason": header["reason"]}


def _write_entry(path, key, buffers):
    vertex_data, index_data = buffers["vertex_data"], buffers["index_data"]
    header = dict(format_version=CACHE_FORMAT_VERSION,
                  algorithm_version=DISPLAY_BUFFER_ALGORITHM_VERSION, key=key,
                  shading_request="smooth", vertex_bytes=len(vertex_data),
                  index_bytes=len(index_data), payload_sha256=_payload_digest(vertex_data, index_data),
                  low=list(map(float, buffers["low"])), high=list(map(float, buffers["high"])))
    for name in ("triangle_count", "vertex_count", "upload_bytes", "soup_bytes", "shading", "reason"):
        header[name] = buffers[name]
    encoded = json.dumps(header, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
    if len(encoded) > MAX_HEADER_BYTES:
        raise ValueError("Display cache metadata exceeds limit")
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with NamedTemporaryFile(dir=path.parent, prefix=".display-", suffix=".tmp", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(PREFIX.pack(MAGIC, len(encoded)))
            stream.write(encoded)
            stream.write(vertex_data)
            stream.write(index_data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass


def load_display_buffers(vertices, normals, center, scale, shading="flat", cache_directory=None,
                         enabled=False):
    """Return display buffers and separate cache/setup metrics; caching is opt-in.

    A missing/stale/corrupt/unwritable entry only causes recomputation. Neither
    this function nor the cache reader returns source geometry to planning.
    """
    use_cache = bool(enabled and shading == "smooth" and cache_directory is not None)
    metrics = dict(display_cache_enabled=use_cache, display_cache_hash_ms=0.0,
                   display_cache_read_ms=0.0, display_cache_write_ms=0.0,
                   display_cache_failure_ms=0.0, display_cache_hits=0,
                   display_cache_misses=0, display_cache_read_failed=0,
                   display_cache_writes=0, display_cache_write_failed=0,
                   display_cache_skipped=0, prepare_buffers_compute_ms=0.0)
    entry = None
    if use_cache:
        started = perf_counter()
        try:
            key = _source_key(vertices, normals, center, scale, shading)
            entry = Path(cache_directory) / f"{key}.cbmb"
        except (ValueError, TypeError, OSError):
            metrics["display_cache_skipped"] = 1
        metrics["display_cache_hash_ms"] = (perf_counter() - started) * 1000
        if entry is not None:
            started = perf_counter()
            try:
                buffers = _read_entry(entry, key, len(vertices))
            except FileNotFoundError:
                metrics["display_cache_misses"] = 1
            except (OSError, ValueError, TypeError, KeyError, OverflowError, RecursionError):
                metrics["display_cache_misses"] = 1
                metrics["display_cache_read_failed"] = 1
            else:
                metrics["display_cache_hits"] = 1
                metrics["display_cache_read_ms"] = (perf_counter() - started) * 1000
                return buffers, metrics
            metrics["display_cache_read_ms"] = (perf_counter() - started) * 1000
            if metrics["display_cache_read_failed"]:
                metrics["display_cache_failure_ms"] += metrics["display_cache_read_ms"]
    started = perf_counter()
    buffers = prepare_display_buffers(vertices, normals, center, scale, shading)
    metrics["prepare_buffers_compute_ms"] = (perf_counter() - started) * 1000
    if entry is not None:
        if buffers["upload_bytes"] > MAX_PAYLOAD_BYTES:
            metrics["display_cache_skipped"] = 1
        else:
            started = perf_counter()
            try:
                _write_entry(entry, key, buffers)
            except (OSError, ValueError, TypeError):
                metrics["display_cache_write_failed"] = 1
            else:
                metrics["display_cache_writes"] = 1
            metrics["display_cache_write_ms"] = (perf_counter() - started) * 1000
            if metrics["display_cache_write_failed"]:
                metrics["display_cache_failure_ms"] += metrics["display_cache_write_ms"]
    return buffers, metrics
