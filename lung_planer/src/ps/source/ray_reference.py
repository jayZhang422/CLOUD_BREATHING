"""Software oracle and deterministic vectors for the ray/triangle RTL.

The arithmetic oracle mirrors ``lung_ray_triangle_core.v``.  Coordinates and
directions are signed Q16.16.  Cross products are Q32.32, dot products are
Q48.48, and the returned barycentric parameters and ray distance are Q16.16.
The script uses only the Python standard library so it can run on the Windows
development host and on the board when needed.
"""
from __future__ import annotations

import argparse
import json
import math
import random
import struct
from pathlib import Path


FRACTION_BITS = 16
SCALE = 1 << FRACTION_BITS
DET_FRACTION_BITS = 48
DET_EPS_REAL = 1.0e-9
DET_EPS_Q48 = round(DET_EPS_REAL * (1 << DET_FRACTION_BITS))
BARY_TOL_Q16 = 1
ONE_PLUS_TOL_Q16 = SCALE + BARY_TOL_Q16
Q16_MIN = -(1 << 31)
Q16_MAX = (1 << 31) - 1


Vec = tuple[float, float, float]
Tri = tuple[Vec, Vec, Vec]


def sub(a: Vec, b: Vec) -> Vec:
    return tuple(x - y for x, y in zip(a, b))  # type: ignore[return-value]


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def norm(a: Vec) -> float:
    return math.sqrt(dot(a, a))


def unit(a: Vec) -> Vec:
    length = norm(a)
    if length <= 1.0e-15:
        raise ValueError("zero direction")
    return tuple(value / length for value in a)  # type: ignore[return-value]


def quantize(value: float) -> int:
    if not math.isfinite(value):
        raise ValueError("non-finite geometry")
    result = round(value * SCALE)
    if not Q16_MIN <= result <= Q16_MAX:
        raise ValueError(f"Q16.16 overflow: {value}")
    return result


def dequantize(value: int) -> float:
    return value / SCALE


def trunc_div(numerator: int, denominator: int) -> int:
    """Signed division with Verilog/C truncation toward zero."""
    if denominator == 0:
        raise ZeroDivisionError
    sign = -1 if (numerator < 0) != (denominator < 0) else 1
    return sign * (abs(numerator) // abs(denominator))


def saturate_q16(value: int) -> tuple[int, int]:
    if value > Q16_MAX:
        return Q16_MAX, 0x02
    if value < Q16_MIN:
        return Q16_MIN, 0x02
    return value, 0


def ray_triangle_float(origin: Vec, direction: Vec, triangle: Tri) -> dict:
    """Floating reference matching PlanningCase.hits() for one triangle."""
    a, b, c = triangle
    e1, e2 = sub(b, a), sub(c, a)
    h = cross(direction, e2)
    det = dot(e1, h)
    if abs(det) < DET_EPS_REAL:
        return {"hit": False, "t": None, "u": None, "v": None, "det": det}
    inv = 1.0 / det
    s = sub(origin, a)
    u = inv * dot(s, h)
    if u < -1.0e-7 or u > 1.0000001:
        return {"hit": False, "t": None, "u": u, "v": None, "det": det}
    q = cross(s, e1)
    v = inv * dot(direction, q)
    if v < -1.0e-7 or u + v > 1.0000001:
        return {"hit": False, "t": None, "u": u, "v": v, "det": det}
    t = inv * dot(e2, q)
    if t < 0:
        return {"hit": False, "t": t, "u": u, "v": v, "det": det}
    return {"hit": True, "t": t, "u": u, "v": v, "det": det}


def dot_q16_q32(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def ray_triangle_fixed(origin: tuple[int, int, int],
                       direction: tuple[int, int, int],
                       triangle: tuple[tuple[int, int, int],
                                       tuple[int, int, int],
                                       tuple[int, int, int]]) -> dict:
    """Integer oracle using the exact widths and comparisons of the RTL."""
    a, b, c = triangle
    e1 = tuple(b[i] - a[i] for i in range(3))
    e2 = tuple(c[i] - a[i] for i in range(3))
    h = (direction[1] * e2[2] - direction[2] * e2[1],
         direction[2] * e2[0] - direction[0] * e2[2],
         direction[0] * e2[1] - direction[1] * e2[0])
    det = dot_q16_q32(e1, h)
    if abs(det) <= DET_EPS_Q48:
        return {"hit": False, "t_q16": 0, "u_q16": 0, "v_q16": 0,
                "error": 0x01, "det_q48": det}
    s = tuple(origin[i] - a[i] for i in range(3))
    u_num = dot_q16_q32(s, h)
    q = (s[1] * e1[2] - s[2] * e1[1],
         s[2] * e1[0] - s[0] * e1[2],
         s[0] * e1[1] - s[1] * e1[0])
    v_num = dot_q16_q32(direction, q)
    t_num = dot_q16_q32(e2, q)
    u_q16 = trunc_div(u_num << FRACTION_BITS, det)
    v_q16 = trunc_div(v_num << FRACTION_BITS, det)
    t_q16 = trunc_div(t_num << FRACTION_BITS, det)
    u_out, error_u = saturate_q16(u_q16)
    v_out, error_v = saturate_q16(v_q16)
    t_out, error_t = saturate_q16(t_q16)
    error = error_u | error_v | error_t
    hit = (error == 0 and u_q16 >= -BARY_TOL_Q16 and
           u_q16 <= ONE_PLUS_TOL_Q16 and v_q16 >= -BARY_TOL_Q16 and
           v_q16 <= ONE_PLUS_TOL_Q16 and u_q16 + v_q16 <= ONE_PLUS_TOL_Q16 and
           t_q16 >= 0)
    return {"hit": bool(hit), "t_q16": t_out, "u_q16": u_out,
            "v_q16": v_out, "error": error, "det_q48": det,
            "raw_t_q16": t_q16, "raw_u_q16": u_q16, "raw_v_q16": v_q16}


def read_stl(path: Path) -> list[Tri]:
    data = path.read_bytes()
    if len(data) >= 84:
        count = struct.unpack_from("<I", data, 80)[0]
        if count and 84 + count * 50 == len(data):
            result = []
            for index in range(count):
                values = struct.unpack_from("<9f", data, 84 + index * 50 + 12)
                result.append((tuple(values[0:3]), tuple(values[3:6]),
                               tuple(values[6:9])))
            return result  # type: ignore[return-value]
    vertices = []
    for line in data.decode("utf-8", errors="ignore").splitlines():
        fields = line.strip().split()
        if len(fields) >= 4 and fields[0].lower() == "vertex":
            vertices.append(tuple(float(value) for value in fields[1:4]))
    if not vertices or len(vertices) % 3:
        raise ValueError(f"invalid STL: {path}")
    return [tuple(vertices[index:index + 3])  # type: ignore[return-value]
            for index in range(0, len(vertices), 3)]


def largest_component(triangles: list[Tri]) -> list[Tri]:
    links: dict[tuple[int, int, int], list[int]] = {}
    for index, triangle in enumerate(triangles):
        for point in triangle:
            key = tuple(round(value * 1000) for value in point)
            links.setdefault(key, []).append(index)
    seen: set[int] = set()
    best: list[int] = []
    for start in range(len(triangles)):
        if start in seen:
            continue
        stack, component = [start], []
        seen.add(start)
        while stack:
            current = stack.pop()
            component.append(current)
            for point in triangles[current]:
                key = tuple(round(value * 1000) for value in point)
                for other in links[key]:
                    if other not in seen:
                        seen.add(other)
                        stack.append(other)
        if len(component) > len(best):
            best = component
    return [triangles[index] for index in best]


def add_case(cases: list[dict], name: str, origin: Vec, direction: Vec,
             triangle: Tri) -> None:
    direction = unit(direction)
    q_origin = tuple(quantize(value) for value in origin)
    q_direction = tuple(quantize(value) for value in direction)
    q_triangle = tuple(tuple(quantize(value) for value in point)
                       for point in triangle)
    fixed = ray_triangle_fixed(q_origin, q_direction, q_triangle)
    floating = ray_triangle_float(origin, direction, triangle)
    cases.append({
        "name": name,
        "origin": origin,
        "direction": direction,
        "triangle": triangle,
        "q_origin": q_origin,
        "q_direction": q_direction,
        "q_triangle": q_triangle,
        "expected": fixed,
        "floating": floating,
    })


def make_synthetic(cases: list[dict]) -> None:
    tri = ((-10.0, -10.0, 0.0), (10.0, -10.0, 0.0),
           (-10.0, 10.0, 0.0))
    add_case(cases, "interior_hit", (0.0, 0.0, 20.0), (0.0, 0.0, -1.0), tri)
    add_case(cases, "outside_miss", (20.0, 20.0, 20.0), (0.0, 0.0, -1.0), tri)
    add_case(cases, "edge_hit", (-10.0, 0.0, 20.0), (0.0, 0.0, -1.0), tri)
    add_case(cases, "vertex_hit", (-10.0, -10.0, 20.0), (0.0, 0.0, -1.0), tri)
    add_case(cases, "parallel", (0.0, 0.0, 20.0), (1.0, 0.0, 0.0), tri)
    add_case(cases, "negative_direction_t", (0.0, 0.0, -20.0), (0.0, 0.0, -1.0), tri)
    add_case(cases, "origin_on_triangle", (0.0, 0.0, 0.0), (0.0, 0.0, 1.0), tri)
    add_case(cases, "negative_coordinates", (-20.0, -20.0, -4.0),
             (0.3, 0.4, 1.0), ((-30.0, -30.0, 0.0), (0.0, -30.0, 0.0),
                               (-30.0, 0.0, 0.0)))
    add_case(cases, "degenerate_triangle", (0.0, 0.0, 20.0),
             (0.0, 0.0, -1.0), ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0),
                                (2.0, 2.0, 2.0)))
    # A translated and rotated triangle exercises all three cross-product axes.
    add_case(cases, "rotated_hit", (15.0, -8.0, 40.0),
             (-0.2, 0.5, -1.0), ((-3.0, 4.0, 2.0), (12.0, 3.0, 7.0),
                                 (1.0, 17.0, -2.0)))
    # Quantized determinants just below and above the 1e-9 Q48.48 cutoff.
    # The tiny z component survives direction normalization as one Q16 LSB;
    # these cases catch accidental changes to the parallel-ray threshold.
    q = SCALE
    add_case(cases, "determinant_below_epsilon", (0.0, 0.0, 10.0),
             (1.0, 0.0, 1.0 / q),
             ((0.0, 0.0, 0.0), (65535.0 / q, 1.0, 0.0),
              (1.0, 65533.0 / q, 0.0)))
    add_case(cases, "determinant_above_epsilon", (0.0, 0.0, 10.0),
             (1.0, 0.0, 1.0 / q),
             ((0.0, 0.0, 0.0), (65535.0 / q, 1.0, 0.0),
              (1.0, 65531.0 / q, 0.0)))


def make_actual(cases: list[dict], stl_dir: Path, count: int) -> dict:
    lung_names = ("RightUpperLobe.stl", "RightMiddleLobe.stl",
                  "RightLowerLobe.stl")
    lung = [triangle for name in lung_names
            for triangle in read_stl(stl_dir / name)]
    tumor = largest_component(read_stl(stl_dir / "LungTumor1.stl"))
    tumor_points = [point for triangle in tumor for point in triangle]
    origin = tuple(sum(point[index] for point in tumor_points) / len(tumor_points)
                   for index in range(3))
    rng = random.Random(0x26010)
    indices = list(range(len(lung)))
    rng.shuffle(indices)
    selected = indices[:max(1, min(count, len(indices)))]
    for serial, index in enumerate(selected):
        triangle = lung[index]
        centroid = tuple(sum(point[axis] for point in triangle) / 3
                         for axis in range(3))
        add_case(cases, f"stl_hit_{serial:02d}", origin,
                 tuple(centroid[axis] - origin[axis] for axis in range(3)),
                 triangle)
    # Pair the same lung data with directions that are deliberately unrelated
    # to the selected triangle. These cases normally reject on barycentrics.
    for serial, index in enumerate(selected[:max(1, count // 2)]):
        triangle = lung[index]
        direction = tuple(rng.uniform(-1.0, 1.0) for _ in range(3))
        add_case(cases, f"stl_random_{serial:02d}", origin, direction, triangle)
    return {"lung_triangles": len(lung), "tumor_component_triangles": len(tumor),
            "tumor_point_count": len(tumor_points), "origin_mm": origin}


def write_vectors(output: Path, cases: list[dict], metadata: dict) -> None:
    output.mkdir(parents=True, exist_ok=True)
    vector_file = output / "ray_vectors.txt"
    with vector_file.open("w", encoding="ascii") as handle:
        handle.write(f"{len(cases)}\n")
        for case_id, case in enumerate(cases, 1):
            expected = case["expected"]
            words = [case_id, int(expected["hit"]), expected["error"],
                     expected["t_q16"] & 0xffffffff,
                     expected["u_q16"] & 0xffffffff,
                     expected["v_q16"] & 0xffffffff]
            words.extend(value & 0xffffffff for value in case["q_origin"])
            words.extend(value & 0xffffffff for value in case["q_direction"])
            for point in case["q_triangle"]:
                words.extend(value & 0xffffffff for value in point)
            handle.write(f"{words[0]} {words[1]} {words[2]} "
                         f"{words[3]:08x} {words[4]:08x} {words[5]:08x} "
                         + " ".join(f"{value:08x}" for value in words[6:]) + "\n")
    summary = {"constants": {
                   "fraction_bits": FRACTION_BITS,
                   "det_fraction_bits": DET_FRACTION_BITS,
                   "det_eps_real": DET_EPS_REAL,
                   "det_eps_q48": DET_EPS_Q48,
                   "bary_tol_q16": BARY_TOL_Q16,
                   "one_plus_tol_q16": ONE_PLUS_TOL_Q16,
               },
               "metadata": metadata,
               "cases": []}
    for case in cases:
        summary["cases"].append({
            "name": case["name"],
            "expected": case["expected"],
            "floating": case["floating"],
        })
    (output / "ray_reference_results.json").write_text(
        json.dumps(summary, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    (output / "ray_generation_summary.json").write_text(
        json.dumps({"case_count": len(cases), **metadata}, indent=2) + "\n",
        encoding="utf-8")


def generate(output: Path, stl_dir: Path | None = None, actual_count: int = 12) -> None:
    cases: list[dict] = []
    make_synthetic(cases)
    metadata = {"synthetic_cases": len(cases)}
    if stl_dir is not None:
        metadata.update(make_actual(cases, stl_dir, actual_count))
    write_vectors(output, cases, metadata)
    print(f"Generated {len(cases)} ray cases in {output}")
    print(json.dumps(metadata, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).parent / "generated")
    parser.add_argument("--stl-dir", type=Path)
    parser.add_argument("--actual-count", type=int, default=12)
    args = parser.parse_args()
    generate(args.output, args.stl_dir, args.actual_count)


if __name__ == "__main__":
    main()
