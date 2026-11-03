"""ABI helpers for the mesh-resident ray accelerator.

The mesh is loaded once as Q16.16 millimetre triangles.  A ray request then
contains only an id, origin and direction; the PL walks the resident mesh and
returns the number of intersections plus the nearest and farthest distances.
All records are little-endian 32-bit words so the format is identical on the
ARM, DMA and Verilog sides.
"""
from __future__ import annotations

from dataclasses import dataclass
import struct
from typing import Iterable, Sequence

Q16_SCALE = 1 << 16
TRIANGLE_WORDS = 12  # three 128-bit beats; last beat has three pad words
TRIANGLE_BYTES = TRIANGLE_WORDS * 4
RAY_WORDS = 8
RAY_BYTES = RAY_WORDS * 4
RESULT_WORDS = 4
RESULT_BYTES = RESULT_WORDS * 4
# DDR mesh ABI.  The older BRAM image remains readable by software
# through the compatibility version check in pl_metrics.py.
ABI_VERSION = 0x00030000


def q16(value: float) -> int:
    raw = int(round(float(value) * Q16_SCALE))
    if raw < -0x80000000 or raw > 0x7FFFFFFF:
        raise ValueError("mesh coordinate is outside signed Q16.16 range")
    return raw


def _u32(value: int) -> int:
    return int(value) & 0xFFFFFFFF


def pack_triangle(triangle: Sequence[Sequence[float]]) -> bytes:
    if len(triangle) != 3 or any(len(point) != 3 for point in triangle):
        raise ValueError("triangle must contain three 3D points")
    words = [q16(value) & 0xFFFFFFFF for point in triangle for value in point]
    return struct.pack("<12I", *(words + [0, 0, 0]))


def pack_mesh(triangles: Iterable[Sequence[Sequence[float]]]) -> bytes:
    return b"".join(pack_triangle(triangle) for triangle in triangles)


def pack_ray(ray_id: int, origin: Sequence[float], direction: Sequence[float]) -> bytes:
    if len(origin) != 3 or len(direction) != 3:
        raise ValueError("ray origin and direction must be 3D")
    words = [_u32(ray_id)]
    words.extend(q16(value) & 0xFFFFFFFF for value in origin)
    words.extend(q16(value) & 0xFFFFFFFF for value in direction)
    words.append(0)
    return struct.pack("<8I", *words)


def pack_rays(origins: Sequence[Sequence[float]], directions: Sequence[Sequence[float]],
              first_ray_id: int = 1, lengths=None) -> bytes:
    if len(origins) != len(directions):
        raise ValueError("ray origin/direction count mismatch")
    if lengths is not None and len(lengths) != len(origins):
        raise ValueError('ray length count mismatch')
    output = bytearray()
    for index, (origin, direction) in enumerate(zip(origins, directions)):
        record = bytearray(pack_ray(first_ray_id + index, origin, direction))
        if lengths is not None:
            length = q16(lengths[index])
            if length <= 0:
                raise ValueError('ray length must be positive in Q16.16')
            struct.pack_into('<I', record, 28, length)
        output.extend(record)
    return bytes(output)


def _signed32(value: int) -> int:
    value &= 0xFFFFFFFF
    return value - 0x100000000 if value & 0x80000000 else value


@dataclass(frozen=True)
class MeshRayResult:
    ray_id: int
    hit_count: int
    t_near_q16: int
    t_far_q16: int

    @property
    def t_near_mm(self) -> float:
        return self.t_near_q16 / Q16_SCALE

    @property
    def t_far_mm(self) -> float:
        return self.t_far_q16 / Q16_SCALE


def decode_result(data: bytes, offset: int = 0) -> MeshRayResult:
    if offset < 0 or offset + RESULT_BYTES > len(data):
        raise ValueError("mesh ray result buffer is truncated")
    ray_id, hit_count, near, far = struct.unpack_from("<4I", data, offset)
    return MeshRayResult(ray_id, hit_count, _signed32(near), _signed32(far))


def decode_results(data: bytes, ray_count: int) -> list[MeshRayResult]:
    if ray_count < 0 or len(data) < ray_count * RESULT_BYTES:
        raise ValueError("mesh ray result buffer is shorter than ray_count")
    return [decode_result(data, index * RESULT_BYTES) for index in range(ray_count)]


def validate_results(results: Iterable[MeshRayResult], ray_count: int,
                     first_ray_id: int = 1) -> list[MeshRayResult]:
    values = list(results)
    if len(values) != int(ray_count):
        raise RuntimeError("mesh ray returned %d/%d results" % (len(values), ray_count))
    expected = list(range(int(first_ray_id), int(first_ray_id) + len(values)))
    actual = [int(value.ray_id) for value in values]
    if actual != expected:
        raise RuntimeError("mesh ray result ids are not ordered or unique")
    return values
