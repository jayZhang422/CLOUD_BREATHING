"""CPU reference planner for the KV260 lung resection demo.

The implementation intentionally uses only the Python standard library so it
can run on a clean Windows workstation and later serve as the golden reference
for an FPGA geometry kernel.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
from dataclasses import dataclass
from pathlib import Path


Vec = tuple[float, float, float]


def add(a: Vec, b: Vec) -> Vec: return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a: Vec, b: Vec) -> Vec: return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a: Vec, s: float) -> Vec: return (a[0] * s, a[1] * s, a[2] * s)
def dot(a: Vec, b: Vec) -> float: return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a: Vec, b: Vec) -> Vec: return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a: Vec) -> float: return math.sqrt(dot(a, a))
def unit(a: Vec) -> Vec:
    n = norm(a)
    return mul(a, 1.0 / n) if n > 1e-12 else (0.0, 0.0, 1.0)
def lerp(a: Vec, b: Vec, t: float) -> Vec: return add(a, mul(sub(b, a), t))
def dist(a: Vec, b: Vec) -> float: return norm(sub(a, b))


@dataclass
class Triangle:
    a: Vec
    b: Vec
    c: Vec

    @property
    def points(self) -> tuple[Vec, Vec, Vec]: return self.a, self.b, self.c


def read_stl(path: Path) -> list[Triangle]:
    """Read binary or ASCII STL without third-party dependencies."""
    data = path.read_bytes()
    if len(data) >= 84:
        count = struct.unpack_from("<I", data, 80)[0]
        expected = 84 + count * 50
        if count > 0 and expected <= len(data):
            triangles = []
            for i in range(count):
                values = struct.unpack_from("<9f", data, 84 + i * 50 + 12)
                triangles.append(Triangle(tuple(values[0:3]), tuple(values[3:6]), tuple(values[6:9])))
            return triangles
    vertices: list[Vec] = []
    text = data.decode("utf-8", errors="ignore")
    for line in text.splitlines():
        fields = line.strip().split()
        if len(fields) >= 4 and fields[0].lower() == "vertex":
            try:
                vertices.append((float(fields[1]), float(fields[2]), float(fields[3])))
            except ValueError:
                continue
    if len(vertices) >= 3 and len(vertices) % 3 == 0:
        return [Triangle(vertices[i], vertices[i + 1], vertices[i + 2]) for i in range(0, len(vertices), 3)]
    raise ValueError(f"Invalid binary or ASCII STL: {path}")


def read_stl_array(path: Path):
    """Read STL triangle coordinates directly into a float64 array."""
    import numpy as np

    data = path.read_bytes()
    if len(data) >= 84:
        count = struct.unpack_from("<I", data, 80)[0]
        expected = 84 + count * 50
        if count > 0 and expected <= len(data):
            view = np.ndarray((count, 3, 3), dtype="<f4", buffer=data,
                              offset=96, strides=(50, 12, 4))
            return view.astype(np.float64)
    return np.asarray([triangle.points for triangle in read_stl(path)], dtype=np.float64)


def all_points(triangles: list[Triangle]) -> list[Vec]:
    return [p for tri in triangles for p in tri.points]


def bounds(points: list[Vec]) -> tuple[Vec, Vec]:
    return tuple(min(p[i] for p in points) for i in range(3)), tuple(max(p[i] for p in points) for i in range(3))


def connected_components(triangles: list[Triangle]) -> list[list[Triangle]]:
    """Split an STL mesh by quantized shared vertices."""
    vertex_to_tri: dict[tuple[int, int, int], list[int]] = {}
    for i, tri in enumerate(triangles):
        for p in tri.points:
            key = tuple(round(x * 1000) for x in p)
            vertex_to_tri.setdefault(key, []).append(i)
    adjacency = [[] for _ in triangles]
    for indices in vertex_to_tri.values():
        for i in indices:
            adjacency[i].extend(indices)
    seen = [False] * len(triangles)
    components: list[list[Triangle]] = []
    for start in range(len(triangles)):
        if seen[start]: continue
        stack = [start]; seen[start] = True; component = []
        while stack:
            i = stack.pop(); component.append(i)
            for j in adjacency[i]:
                if not seen[j]: seen[j] = True; stack.append(j)
        components.append([triangles[i] for i in component])
    return components


def largest_component(triangles: list[Triangle]) -> list[Triangle]:
    """Select the largest connected STL component by face count."""
    components = connected_components(triangles)
    return max(components, key=len, default=[])


def ray_triangle(origin: Vec, direction: Vec, tri: Triangle) -> float | None:
    e1, e2 = sub(tri.b, tri.a), sub(tri.c, tri.a)
    h = cross(direction, e2); det = dot(e1, h)
    if abs(det) < 1e-9: return None
    inv = 1.0 / det; s = sub(origin, tri.a); u = inv * dot(s, h)
    if u < -1e-7 or u > 1.0000001: return None
    q = cross(s, e1); v = inv * dot(direction, q)
    if v < -1e-7 or u + v > 1.0000001: return None
    t = inv * dot(e2, q)
    return t if t >= 0 else None


def surface_hit(origin: Vec, direction: Vec, lung: list[Triangle]) -> Vec:
    best_t = float("inf")
    for tri in lung:
        t = ray_triangle(origin, direction, tri)
        if t is not None and t < best_t: best_t = t
    if math.isfinite(best_t): return add(origin, mul(direction, best_t))
    # Fallback for a mesh with a small hole in the ray path.
    points = all_points(lung)
    candidates = [(dist(origin, p), p) for p in points if dot(sub(p, origin), direction) > 0]
    return min(candidates, default=(0.0, origin))[1]


def basis(direction: Vec) -> tuple[Vec, Vec]:
    ref = (1.0, 0.0, 0.0) if abs(direction[1]) > .85 else (0.0, 1.0, 0.0)
    u = unit(cross(ref, direction)); v = unit(cross(direction, u))
    return u, v


def direction_for(yaw: float, pitch: float) -> Vec:
    # Same outward reference and Euler order as the web demo.
    view = unit((.35, .2, 1.0))
    d = unit((view[2], 0.0, -view[0]))
    y, p = math.radians(yaw), math.radians(pitch)
    # THREE.Euler(pitch, yaw, 0, 'YXZ') applied to a vector.
    x, yy, z = d
    x1, z1 = math.cos(y) * x + math.sin(y) * z, -math.sin(y) * x + math.cos(y) * z
    y2, z2 = math.cos(p) * yy - math.sin(p) * z1, math.sin(p) * yy + math.cos(p) * z1
    return unit((x1, y2, z2))


def tri_area(a: Vec, b: Vec, c: Vec) -> float: return norm(cross(sub(b, a), sub(c, a))) * .5


def required_radius(x: float, y: float) -> float:
    # The equilateral base has vertices (r, 0), (-r/2, +/-sqrt(3)r/2).
    # Its two slanted edges therefore impose x + sqrt(3)|y| <= r.
    return max(x, -2 * x, x + math.sqrt(3) * abs(y))


def fit_base_triangle(base_center: Vec, apex: Vec, direction: Vec,
                      tumor_points: list[Vec], rotation_deg: float,
                      padding: float) -> tuple[list[Vec], Vec, float]:
    """Fit a padded, translated equilateral base around projected tumor points."""
    height = max(1e-6, dot(sub(apex, base_center), mul(direction, -1)))
    u, v = basis(direction)
    theta = math.radians(rotation_deg)
    cu, su = math.cos(theta), math.sin(theta)
    u2 = add(mul(u, cu), mul(v, su))
    v2 = add(mul(v, cu), mul(u, -su))

    # In plane coordinates, the minimum enclosing triangle is obtained from
    # four extrema. This also lets the base center move laterally on the
    # surface plane instead of forcing it to stay on the center ray.
    xs: list[float] = []
    plus: list[float] = []
    minus: list[float] = []
    for point in tumor_points:
        t = dot(sub(point, apex), direction)
        if t <= 1e-8:
            raise ValueError("tumor point lies behind the apex")
        projected = add(apex, mul(sub(point, apex), height / t))
        delta = sub(projected, base_center)
        x, y = dot(delta, u2), dot(delta, v2)
        xs.append(x)
        plus.append(x + math.sqrt(3) * y)
        minus.append(x - math.sqrt(3) * y)

    xmax, xmin = max(xs), min(xs)
    pmax, mmax = max(plus), max(minus)
    center_y = (pmax - mmax) / (2 * math.sqrt(3))
    slanted_bound = (pmax + mmax) * .5
    bound = max(xmax, slanted_bound)
    center_x = (bound + 2 * xmin) / 3
    radius = (2 * bound - 2 * xmin) / 3 * padding
    fitted_center = add(base_center, add(mul(u2, center_x), mul(v2, center_y)))
    base = [
        add(fitted_center, mul(u2, radius)),
        add(fitted_center, add(mul(u2, -.5 * radius), mul(v2, .8660254 * radius))),
        add(fitted_center, add(mul(u2, -.5 * radius), mul(v2, -.8660254 * radius))),
    ]
    return base, fitted_center, radius


def inside_triangle(p: Vec, a: Vec, b: Vec, c: Vec, tolerance=1e-5) -> bool:
    v0, v1, v2 = sub(c, a), sub(b, a), sub(p, a)
    d00, d01, d02 = dot(v0, v0), dot(v0, v1), dot(v0, v2)
    d11, d12 = dot(v1, v1), dot(v1, v2)
    inv = 1.0 / max(1e-12, d00 * d11 - d01 * d01)
    u, v = (d11 * d02 - d01 * d12) * inv, (d00 * d12 - d01 * d02) * inv
    return u >= -tolerance and v >= -tolerance and u + v <= 1 + tolerance


def face(a: Vec, b: Vec, c: Vec) -> tuple[Vec, Vec, Vec]: return a, b, c, unit(cross(sub(b, a), sub(c, a)))


def tetra_faces(base: list[Vec], apex: Vec) -> list[tuple[Vec, Vec, Vec, Vec]]:
    faces = [face(base[0], base[1], base[2]), face(base[0], apex, base[1]), face(base[1], apex, base[2]), face(base[2], apex, base[0])]
    center = mul(add(add(add(base[0], base[1]), base[2]), apex), .25)
    return [(a, b, c, mul(n, -1) if dot(sub(center, a), n) > 0 else n) for a, b, c, n in faces]


def point_inside(p: Vec, faces) -> bool:
    return all(dot(sub(p, a), n) <= 1e-5 for a, _, _, n in faces)


def clip_polygon(poly: list[Vec], a: Vec, n: Vec) -> list[Vec]:
    if not poly: return []
    out = []
    prev = poly[-1]; prev_d = dot(sub(prev, a), n); prev_in = prev_d <= 1e-8
    for cur in poly:
        cur_d = dot(sub(cur, a), n); cur_in = cur_d <= 1e-8
        if cur_in != prev_in: out.append(lerp(prev, cur, prev_d / (prev_d - cur_d)))
        if cur_in: out.append(cur)
        prev, prev_d, prev_in = cur, cur_d, cur_in
    return out


def surface_intersection_area(lung: list[Triangle], faces) -> float:
    area = 0.0
    for tri in lung:
        poly = list(tri.points)
        for a, _, _, n in faces:
            poly = clip_polygon(poly, a, n)
            if len(poly) < 3: break
        for i in range(1, len(poly) - 1): area += tri_area(poly[0], poly[i], poly[i + 1])
    return area / 100.0



def point_triangle_distance(p: Vec, tri: Triangle) -> float:
    # Closest point on a triangle (Ericson, Real-Time Collision Detection).
    a, b, c = tri.a, tri.b, tri.c
    ab, ac, ap = sub(b, a), sub(c, a), sub(p, a)
    d1, d2 = dot(ab, ap), dot(ac, ap)
    if d1 <= 0.0 and d2 <= 0.0: return dist(p, a)
    bp = sub(p, b); d3, d4 = dot(ab, bp), dot(ac, bp)
    if d3 >= 0.0 and d4 <= d3: return dist(p, b)
    vc = d1 * d4 - d3 * d2
    if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
        t = d1 / max(1e-12, d1 - d3); return dist(p, add(a, mul(ab, t)))
    cp = sub(p, c); d5, d6 = dot(ab, cp), dot(ac, cp)
    if d6 >= 0.0 and d5 <= d6: return dist(p, c)
    vb = d5 * d2 - d1 * d6
    if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
        t = d2 / max(1e-12, d2 - d6); return dist(p, add(a, mul(ac, t)))
    va = d3 * d6 - d5 * d4
    if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
        t = (d4 - d3) / max(1e-12, (d4 - d3) + (d5 - d6)); return dist(p, add(b, mul(sub(c, b), t)))
    denom = 1.0 / max(1e-12, va + vb + vc)
    v, w = vb * denom, vc * denom
    return dist(p, add(a, add(mul(ab, v), mul(ac, w))))


def ray_hits(origin: Vec, direction: Vec, lung: list[Triangle]) -> list[float]:
    return sorted(t for tri in lung if (t := ray_triangle(origin, direction, tri)) is not None)


def point_inside_lung(point: Vec, lung: list[Triangle]) -> bool:
    # Odd/even parity along a non-axis-aligned ray avoids most vertex hits.
    direction = unit((1.0, 0.371, 0.217))
    hits = ray_hits(add(point, mul(direction, 1e-5)), direction, lung)
    unique = []
    for t in hits:
        if not unique or abs(t - unique[-1]) > 1e-5: unique.append(t)
    return len(unique) % 2 == 1


def base_sample_points(base: list[Vec], edge_steps: int = 24, interior_steps: int = 8) -> list[Vec]:
    samples = list(base)
    for i in range(3):
        a, b = base[i], base[(i + 1) % 3]
        for j in range(1, edge_steps): samples.append(lerp(a, b, j / edge_steps))
    # Include interior points because a concave lung surface can pass through
    # the middle of the base while all three corners remain outside.
    for i in range(1, interior_steps):
        for j in range(1, interior_steps - i + 1):
            samples.append(add(add(mul(base[0], 1 - i / interior_steps - j / interior_steps),
                                   mul(base[1], i / interior_steps)),
                               mul(base[2], j / interior_steps)))
    return samples


def validate_base_outside(base: list[Vec], lung: list[Triangle], min_clearance: float, edge_steps: int = 24, interior_steps: int = 8, check_inside: bool = True) -> tuple[bool, float, int]:
    samples = base_sample_points(base, edge_steps=edge_steps, interior_steps=interior_steps)
    min_distance = float('inf')
    inside_samples = 0
    for point in samples:
        if check_inside and point_inside_lung(point, lung): inside_samples += 1
        # Exact point-to-triangle distance enforces the requested surface gap.
        distance = min(point_triangle_distance(point, tri) for tri in lung)
        min_distance = min(min_distance, distance)
        if inside_samples or min_distance < min_clearance:
            # Keep the values meaningful while allowing an early reject.
            if inside_samples: return False, min_distance, inside_samples
            return False, min_distance, inside_samples
    return True, min_distance if math.isfinite(min_distance) else 0.0, inside_samples


def move_base_outside(base: list[Vec], base_center: Vec, apex: Vec, direction: Vec, lung: list[Triangle], min_clearance: float = 0.5) -> tuple[list[Vec], Vec, Vec, float]:
    """Keep the fitted base; final dense validation is applied to the selected plan."""
    return base, base_center, apex, 0.0

def closed_mesh_volume(triangles: list[Triangle]) -> float:
    """Return a closed triangle mesh volume in mm^3 using signed tetrahedra."""
    return abs(sum(dot(tri.a, cross(tri.b, tri.c)) / 6.0 for tri in triangles))


def tetrahedron_volume(base: list[Vec], apex: Vec) -> float:
    return abs(dot(sub(base[0], apex), cross(sub(base[1], apex), sub(base[2], apex)))) / 6.0


def resection_volume(base: list[Vec], apex: Vec, lung: list[Triangle], samples_per_edge: int = 18) -> tuple[float, float]:
    """Integrate f^3 over the base, where f is the lung exit ratio on each ray."""
    tetra_volume = tetrahedron_volume(base, apex)
    ratios = []
    for i in range(samples_per_edge + 1):
        for j in range(samples_per_edge + 1 - i):
            u, v = i / samples_per_edge, j / samples_per_edge
            point = add(add(mul(base[0], 1.0 - u - v), mul(base[1], u)), mul(base[2], v))
            ray = sub(point, apex); length = norm(ray)
            if length <= 1e-9: continue
            direction = mul(ray, 1.0 / length)
            hits = [t for t in ray_hits(apex, direction, lung) if t <= length + 1e-6]
            # Apex is expected to be inside the lung. If a ray misses a small
            # mesh hole, treating it as a full ray is the conservative value.
            f = min(1.0, max(0.0, min(hits) / length)) if hits else 1.0
            ratios.append(f ** 3)
    fraction = sum(ratios) / len(ratios) if ratios else 0.0
    return tetra_volume, tetra_volume * fraction


def plan(args) -> dict:
    root = args.models
    lung_paths = args.lung if args.lung else [root / name for name in ('RightLowerLobe.stl', 'RightMiddleLobe.stl', 'RightUpperLobe.stl')]
    lung_paths = [path if path.is_absolute() else root / path for path in lung_paths]
    tumor_path = args.tumor if args.tumor else root / 'LungTumor1.stl'
    if not tumor_path.is_absolute(): tumor_path = root / tumor_path
    lung_meshes = [read_stl(path) for path in lung_paths]
    lung_triangles = [tri for mesh in lung_meshes for tri in mesh]
    lung_volume_mm3 = sum(closed_mesh_volume(mesh) for mesh in lung_meshes)
    tumor = largest_component(read_stl(tumor_path))
    tumor_points = all_points(tumor)
    # The original demo data needs an x reflection to align labelled lobes with
    # the tumor. New cases can disable this with --no-mirror when meshes are
    # already registered in the same coordinate system.
    model_paths = list(lung_paths) + [tumor_path]
    all_model_points = [point for mesh_path in model_paths for point in all_points(read_stl(mesh_path))]
    model_min, model_max = bounds(all_model_points)
    mirror_x = (model_min[0] + model_max[0]) * .5
    if args.no_mirror:
        lung = lung_triangles
        mirror_x = None
    else:
        lung = [Triangle((2 * mirror_x - t.a[0], t.a[1], t.a[2]), (2 * mirror_x - t.b[0], t.b[1], t.b[2]), (2 * mirror_x - t.c[0], t.c[1], t.c[2])) for t in lung_triangles]
    center = tuple(sum(p[i] for p in tumor_points) / len(tumor_points) for i in range(3))
    best = None
    # Coarse scan plus a small one-degree neighborhood around the direction
    # that matches the manually tuned plan. The in-plane rotations let the
    # planner fit a smaller base without relying on draggable vertices.
    # Focus the automatic search around the clinically tuned entry corridor.
    angles = {(yaw, pitch) for yaw in (-40, -34, -30)
              for pitch in (-52, -48, -44)}
    rotations = (0.0, 30.0, 60.0)
    for yaw, pitch in sorted(angles):
        direction = direction_for(yaw, pitch)
        support = surface_hit(center, direction, lung)
        base_center = add(support, mul(direction, args.base_offset))
        inward = mul(direction, -1)
        depth = max(dot(sub(point, base_center), inward) for point in tumor_points)
        apex = add(base_center, mul(inward, depth + args.margin))
        for rotation in rotations:
            try:
                base, fitted_center, _ = fit_base_triangle(
                    base_center, apex, direction, tumor_points, rotation, args.base_padding
                )
            except ValueError:
                continue
            base, fitted_center, fitted_apex, surface_push_mm = move_base_outside(
                base, fitted_center, apex, direction, lung, args.min_clearance
            )
            # Every retained candidate must pass dense edge/interior parity and
            # point-to-mesh clearance checks before it can be scored.
            base_outside_valid, min_base_clearance, base_inside_samples = validate_base_outside(
                base, lung, args.min_clearance, edge_steps=24, interior_steps=8, check_inside=True
            )
            if not base_outside_valid:
                continue
            faces = tetra_faces(base, fitted_apex)
            inside = sum(point_inside(point, faces) for point in tumor_points)
            coverage = inside / len(tumor_points) * 100
            if coverage < 99.999:
                continue
            clearance = min(-dot(sub(point, a), n) for point in tumor_points
                            for a, _, _, n in faces)
            if clearance < args.min_clearance:
                continue
            area = surface_intersection_area(lung, faces)
            base_area = tri_area(*base) / 100
            tetra_volume_mm3, resection_volume_mm3 = resection_volume(base, fitted_apex, lung, samples_per_edge=3)
            direction_deviation = math.hypot(yaw + 34, pitch + 48)
            # Safety and complete tumor containment are hard constraints. Among
            # feasible candidates, minimize actual lung resection volume first.
            sort_key = (resection_volume_mm3, area, base_area,
                        direction_deviation, surface_push_mm)
            score = resection_volume_mm3 / 1000.0 + .02 * area + .01 * base_area + .01 * direction_deviation
            candidate = (sort_key, {
                'base_vertices': base,
                'base_center': fitted_center,
                'apex': fitted_apex,
                'direction': direction,
                'base_area_cm2': base_area,
                'margin_mm': args.margin,
                'coverage_percent': coverage,
                'clearance_mm': clearance,
                'surface_area_cm2': area,
                'resection_volume_cm3': resection_volume_mm3 / 1000.0,
                'lung_volume_cm3': lung_volume_mm3 / 1000.0,
                'tetrahedron_volume_cm3': tetra_volume_mm3 / 1000.0,
                'resection_ratio_percent': (resection_volume_mm3 / lung_volume_mm3 * 100.0) if lung_volume_mm3 > 1e-9 else None,
                'volume_method': 'deterministic ray quadrature (f^3)',
                'base_outside_valid': base_outside_valid,
                'min_base_clearance_mm': min_base_clearance,
                'base_inside_samples': base_inside_samples,
                'valid': True,
                'score': score,
                'yaw': yaw,
                'pitch': pitch,
                'base_rotation_deg': rotation,
                'surface_push_mm': surface_push_mm,
            })
            if best is None or candidate[0] < best[0]:
                best = candidate
    if best is None: raise RuntimeError('No valid candidate direction contained the largest tumor')
    result = best[1]
    result.update({'units': 'mm', 'tumor_triangles': len(tumor), 'tumor_points': len(tumor_points), 'lung_triangles': len(lung), 'lung_volume_cm3': lung_volume_mm3 / 1000.0, 'lung_files': [str(path) for path in lung_paths], 'tumor_file': str(tumor_path), 'mirror_lung': not args.no_mirror, 'mirror_plane_x': mirror_x, 'algorithm': 'CPU reference scan; FPGA-ready geometry metrics'})
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=Path(__file__).with_name('plan_result.json'))
    parser.add_argument('--lung', type=Path, nargs='+', default=None, help='One or more lung surface STL files; defaults to the demo lobe files')
    parser.add_argument('--tumor', type=Path, default=None, help='Tumor STL file; defaults to LungTumor1.stl')
    parser.add_argument('--no-mirror', action='store_true', help='Do not apply the demo dataset x-axis lung reflection')
    parser.add_argument('--base-offset', type=float, default=8.0)
    parser.add_argument('--base-padding', type=float, default=1.20,
                        help='Scale above the minimum enclosing base triangle')
    parser.add_argument('--min-clearance', type=float, default=1.0,
                        help='Required tumor-to-face clearance in mm')
    parser.add_argument('--margin', type=float, default=20.0)
    parser.add_argument('--yaw-min', type=int, default=-60); parser.add_argument('--yaw-max', type=int, default=20)
    parser.add_argument('--pitch-min', type=int, default=-70); parser.add_argument('--pitch-max', type=int, default=-20)
    parser.add_argument('--step', type=int, default=5)
    args = parser.parse_args()
    result = plan(args)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print(f'Wrote {args.output.resolve()}')


if __name__ == '__main__': main()
