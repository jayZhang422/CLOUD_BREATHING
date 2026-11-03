"""Software-side ABI helpers for the RTL ray/triangle batch block.

The FPGA returns one result per ray/triangle pair.  A closed mesh can return
the same geometric crossing for several triangles sharing an edge or vertex,
so callers must sort and collapse the returned ``t`` values before applying
parity or interval integration.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
import struct
from typing import Iterable, Mapping, Sequence


Q16_SCALE = 1 << 16
INPUT_WORDS = 20
INPUT_BYTES = INPUT_WORDS * 4
OUTPUT_BYTES = 32
# One Q16.16 LSB is about 15.3 micrometres.  Two LSBs absorb signed
# division/truncation on adjacent triangles while remaining far below mesh
# dimensions used by the planner.
DEFAULT_HIT_TOLERANCE_MM = max(1.0e-5, 2.0 / Q16_SCALE)
# The current RTL reports these conditions on records that are known misses.
# They are valid per-record outcomes, while any other error (or an error on a
# hit) means that the hardware result cannot be trusted.
RAY_ERR_PARALLEL = 0x01
RAY_ERR_MISS_OVERFLOW = 0x02
RAY_NON_HIT_ERRORS = frozenset((RAY_ERR_PARALLEL, RAY_ERR_MISS_OVERFLOW))
RAY_KNOWN_ERROR_MASK = RAY_ERR_PARALLEL | RAY_ERR_MISS_OVERFLOW


def q16(value: float) -> int:
    raw = int(round(float(value) * Q16_SCALE))
    if raw < -0x80000000 or raw > 0x7FFFFFFF:
        raise ValueError("ray value is outside signed Q16.16 range")
    return raw


def _u32(value: int) -> int:
    return int(value) & 0xFFFFFFFF


@dataclass(frozen=True)
class RayTriangleInput:
    """One floating-point ray/triangle pair before Q16.16 packing."""

    ray_id: int
    triangle_id: int
    origin: Sequence[float]
    direction: Sequence[float]
    triangle: Sequence[Sequence[float]]

    def pack(self) -> bytes:
        if len(self.origin) != 3 or len(self.direction) != 3 or len(self.triangle) != 3:
            raise ValueError("ray input must contain 3D origin, direction and triangle")
        coordinates = [*self.origin, *self.direction,
                       *self.triangle[0], *self.triangle[1], *self.triangle[2]]
        words = [_u32(self.ray_id), _u32(self.triangle_id)]
        words.extend(q16(value) & 0xFFFFFFFF for value in coordinates)
        words.extend((0, 0, 0))
        return struct.pack("<20I", *words)


@dataclass(frozen=True)
class RayHit:
    ray_id: int
    triangle_id: int
    hit: bool
    error: int
    t_q16: int
    u_q16: int
    v_q16: int

    @property
    def t_mm(self) -> float:
        return self.t_q16 / Q16_SCALE

    @property
    def u(self) -> float:
        return self.u_q16 / Q16_SCALE

    @property
    def v(self) -> float:
        return self.v_q16 / Q16_SCALE


def _signed32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


def decode_result_record(data: bytes, offset: int = 0) -> RayHit:
    """Decode one 32-byte two-beat result from the AXI DMA buffer."""
    if offset < 0 or offset + OUTPUT_BYTES > len(data):
        raise ValueError("ray result buffer is truncated")
    ray_id, triangle_id, flags, t_q16 = struct.unpack_from("<4I", data, offset)
    u_q16, v_q16 = struct.unpack_from("<2I", data, offset + 16)
    return RayHit(ray_id=ray_id, triangle_id=triangle_id,
                  hit=bool(flags & 1), error=(flags >> 1) & 0xFF,
                  t_q16=_signed32(t_q16), u_q16=_signed32(u_q16),
                  v_q16=_signed32(v_q16))


def decode_result_buffer(data: bytes, record_count: int) -> list[RayHit]:
    if record_count < 0 or len(data) < record_count * OUTPUT_BYTES:
        raise ValueError("ray result buffer is shorter than record_count")
    return [decode_result_record(data, index * OUTPUT_BYTES)
            for index in range(record_count)]


def input_pairs(data: bytes, record_count: int) -> list[tuple[int, int]]:
    """Return the ray/triangle identity for every packed input record."""
    if record_count < 0 or len(data) != record_count * INPUT_BYTES:
        raise ValueError("ray input buffer is shorter than record_count")
    return [struct.unpack_from("<II", data, index * INPUT_BYTES)
            for index in range(record_count)]


def validate_result_records(results: Iterable[RayHit | Mapping[str, object]],
                            expected_pairs: Iterable[tuple[int, int]],
                            aggregate_errors: int = 0) -> list[RayHit]:
    """Validate one-for-one correspondence and classify per-record errors."""
    expected = list(expected_pairs)
    actual = [_coerce_hit(item) for item in results]
    if len(actual) != len(expected):
        raise RuntimeError("ray batch returned %d/%d result records" %
                           (len(actual), len(expected)))
    expected_set = set(expected)
    seen = set()
    for item in actual:
        key = (item.ray_id, item.triangle_id)
        if key not in expected_set:
            raise RuntimeError("ray batch returned unknown record (%d,%d)" % key)
        if key in seen:
            raise RuntimeError("ray batch returned duplicate record (%d,%d)" % key)
        seen.add(key)
        if item.error and (item.error not in RAY_NON_HIT_ERRORS or item.hit):
            raise RuntimeError("ray batch returned fatal error 0x%02x" % item.error)
    if seen != expected_set or len(expected_set) != len(expected):
        raise RuntimeError("ray batch input record identities are not unique")
    aggregate_errors = int(aggregate_errors) & 0xFF
    if aggregate_errors & ~RAY_KNOWN_ERROR_MASK:
        raise RuntimeError("ray batch hardware errors: 0x%02x" % aggregate_errors)
    represented_errors = 0
    for item in actual:
        if not item.hit:
            represented_errors |= item.error
    if aggregate_errors & ~represented_errors:
        raise RuntimeError("ray batch aggregate error 0x%02x has no matching miss record" %
                           (aggregate_errors & ~represented_errors))
    return actual


def _coerce_hit(value: RayHit | Mapping[str, object]) -> RayHit:
    if isinstance(value, RayHit):
        return value
    # Do not use value.get("t_q16", fallback) here: Python evaluates the
    # fallback before calling get, so the legacy fallback would still try to
    # read a missing floating-point "t" field from hardware-style records.
    t_q16 = value.get("t_q16")
    if t_q16 is None:
        t_q16 = round(float(value["t"]) * Q16_SCALE)
    return RayHit(ray_id=int(value["ray_id"]), triangle_id=int(value["triangle_id"]),
                  hit=bool(value["hit"]), error=int(value.get("error", 0)),
                  t_q16=int(t_q16),
                  u_q16=int(value.get("u_q16", 0)), v_q16=int(value.get("v_q16", 0)))


def collapse_hits(results: Iterable[RayHit | Mapping[str, object]],
                  *, ray_id: int | None = None,
                  tolerance_mm: float = DEFAULT_HIT_TOLERANCE_MM) -> list[RayHit]:
    """Return sorted, unique geometric crossings for one ray.

    Fatal hardware errors are rejected instead of being silently converted
    into a miss. A representative triangle is kept for each crossing.
    """
    if tolerance_mm < 0 or not math.isfinite(tolerance_mm):
        raise ValueError("tolerance_mm must be finite and non-negative")
    hits = [_coerce_hit(item) for item in results]
    if ray_id is not None:
        hits = [item for item in hits if item.ray_id == ray_id]
    errors = [item for item in hits
              if item.error and (item.error not in RAY_NON_HIT_ERRORS or item.hit)]
    if errors:
        raise RuntimeError("ray batch returned fatal error 0x%02x" % errors[0].error)
    hits = [item for item in hits if item.hit and math.isfinite(item.t_mm)
            and item.t_mm >= 0.0]
    hits.sort(key=lambda item: (item.t_mm, item.triangle_id))
    unique: list[RayHit] = []
    for item in hits:
        if not unique or item.t_mm - unique[-1].t_mm > tolerance_mm:
            unique.append(item)
    return unique


def inside_from_results(results: Iterable[RayHit | Mapping[str, object]], *,
                        ray_id: int | None = None,
                        tolerance_mm: float = DEFAULT_HIT_TOLERANCE_MM) -> bool:
    return bool(len(collapse_hits(results, ray_id=ray_id,
                                  tolerance_mm=tolerance_mm)) & 1)


def ray_intervals(results: Iterable[RayHit | Mapping[str, object]],
                  ray_length_mm: float, *, origin_inside: bool,
                  ray_id: int | None = None,
                  tolerance_mm: float = DEFAULT_HIT_TOLERANCE_MM) -> list[tuple[float, float]]:
    """Return inside intervals clipped to ``[0, ray_length_mm]``."""
    if not math.isfinite(ray_length_mm) or ray_length_mm < 0:
        raise ValueError("ray_length_mm must be finite and non-negative")
    crossings = [item.t_mm for item in collapse_hits(
        results, ray_id=ray_id, tolerance_mm=tolerance_mm)
        if item.t_mm > tolerance_mm and item.t_mm < ray_length_mm + tolerance_mm]
    boundaries = [0.0, *crossings, ray_length_mm]
    intervals: list[tuple[float, float]] = []
    for index, (start, end) in enumerate(zip(boundaries, boundaries[1:])):
        if end <= start + tolerance_mm:
            continue
        inside = origin_inside if index % 2 == 0 else not origin_inside
        if inside:
            intervals.append((start, min(end, ray_length_mm)))
    return intervals


def group_results(results: Iterable[RayHit | Mapping[str, object]],
                  *, tolerance_mm: float = DEFAULT_HIT_TOLERANCE_MM) -> dict[int, list[RayHit]]:
    grouped: dict[int, list[RayHit]] = {}
    for item in results:
        hit = _coerce_hit(item)
        grouped.setdefault(hit.ray_id, []).append(hit)
    return {ray_id: collapse_hits(items, tolerance_mm=tolerance_mm)
            for ray_id, items in grouped.items()}
