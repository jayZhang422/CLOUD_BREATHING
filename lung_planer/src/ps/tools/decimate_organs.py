"""Organ-aware, component-preserving display STL simplification. No network IO.

Binary STL input only; exact-coordinate welding, no smoothing or alignment.
MeshLab QEM explicitly preserves topology; exported files are checked again.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import time
import zipfile
from pathlib import Path

import numpy as np
import pymeshlab
import trimesh
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

STL_DTYPE = np.dtype([('normal', '<f4', (3,)), ('vertices', '<f4', (3, 3)), ('attribute', '<u2')])


def allocate(capacities, budget, weights=None, minimums=None, quantum=2):
    """Capped weighted allocation; even budgets respect closed-mesh parity."""
    caps = np.asarray(capacities, dtype=np.int64)
    mins = np.zeros(len(caps), dtype=np.int64) if minimums is None else np.asarray(minimums, dtype=np.int64)
    if np.any(caps % quantum) or np.any(mins % quantum):
        raise ValueError('Allocation capacity/minimum violates face parity')
    budget = min(int(budget), int(caps.sum())) // quantum * quantum
    if mins.sum() > budget:
        raise ValueError(f'Budget {budget} cannot preserve components: minimum {mins.sum()}')
    out = mins.copy()
    w = np.asarray(capacities if weights is None else weights, dtype=float)
    while out.sum() < budget:
        room = (caps - out) // quantum
        eligible = room > 0
        if not eligible.any():
            break
        remaining = (budget - out.sum()) // quantum
        fractions = np.where(eligible, w, 0)
        shares = fractions / fractions.sum() * remaining
        steps = np.minimum(room, np.floor(shares).astype(np.int64))
        if not steps.any():
            order = np.argsort(-np.where(eligible, shares - np.floor(shares), -1), kind='stable')
            steps[order[:min(int(remaining), int(eligible.sum()))]] = 1
        out += steps * quantum
    return out.tolist()


def read_stl(data):
    if len(data) < 84:
        raise ValueError('Truncated STL')
    n, = struct.unpack_from('<I', data, 80)
    if len(data) != 84 + 50 * n:
        raise ValueError('Expected binary STL with exact declared length')
    triangles = np.frombuffer(data, STL_DTYPE, count=n, offset=84)['vertices']
    if not np.isfinite(triangles).all():
        raise ValueError('Nonfinite input coordinates')
    points, inverse = np.unique(triangles.reshape(-1, 3), axis=0, return_inverse=True)
    mesh = trimesh.Trimesh(points.astype(float), inverse.reshape(-1, 3), process=False)
    if np.any(mesh.area_faces <= 1e-12):
        raise ValueError('Degenerate source faces; repair separately, never silently discard')
    return mesh


def components(mesh):
    f = mesh.faces
    edges = np.concatenate((f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]))
    graph = coo_matrix((np.ones(len(edges), dtype=np.int8), (edges[:, 0], edges[:, 1])),
                       shape=(len(mesh.vertices), len(mesh.vertices))).tocsr()
    count, labels = connected_components(graph, directed=False)
    face_labels = labels[f[:, 0]]
    result = []
    for label in range(count):
        selected = f[face_labels == label]
        if not len(selected):
            continue
        ids, local = np.unique(selected, return_inverse=True)
        result.append(trimesh.Trimesh(mesh.vertices[ids], local.reshape(-1, 3), process=False))
    return result


def quality(mesh):
    f = mesh.faces
    edges = np.sort(np.concatenate((f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]])), axis=1)
    unique_edges, counts = np.unique(edges, axis=0, return_counts=True)
    return dict(faces=len(f), vertices=len(mesh.vertices), components=len(components(mesh)),
                boundary_edges=int(np.sum(counts == 1)), nonmanifold_edges=int(np.sum(counts > 2)),
                euler=int(len(mesh.vertices) - len(unique_edges) + len(f)),
                winding_consistent=bool(mesh.is_winding_consistent),
                degenerate_faces=int(np.sum(mesh.area_faces <= 1e-12)),
                volume=float(mesh.volume), area=float(mesh.area), bounds=mesh.bounds.tolist())


def same_topology(before, after):
    return all(before[k] == after[k] for k in (
        'components', 'boundary_edges', 'nonmanifold_edges', 'euler', 'winding_consistent', 'degenerate_faces'))


def reduce_component(mesh, target):
    if target >= len(mesh.faces):
        return mesh.copy()
    baseline = quality(mesh)
    filters = pymeshlab.MeshSet()
    filters.add_mesh(pymeshlab.Mesh(mesh.vertices, mesh.faces))
    filters.meshing_decimation_quadric_edge_collapse(
        targetfacenum=int(target), preservetopology=True, preservenormal=True,
        preserveboundary=True, optimalplacement=True, qualitythr=0.3, autoclean=True)
    result = filters.current_mesh()
    reduced = trimesh.Trimesh(result.vertex_matrix().astype(np.float32).astype(float),
                             result.face_matrix(), process=False)
    reduced.remove_unreferenced_vertices()
    if len(reduced.faces) and len(reduced.faces) <= target and same_topology(baseline, quality(reduced)):
        return reduced
    raise ValueError(f'Cannot safely meet {target} faces from {len(mesh.faces)}; '
                     f'baseline={baseline}; output={quality(reduced)}')


def simplify(mesh, target, group):
    parts = components(mesh)
    counts = [len(p.faces) for p in parts]
    # Tiny structures are unchanged, never deleted by a largest-component filter.
    mins = [c if c <= 256 else 64 for c in counts]
    weights = [float(c) ** 0.80 for c in counts]
    targets = allocate(counts, target, weights, mins)
    results = []
    details = []
    for index, (part, part_target) in enumerate(zip(parts, targets)):
        reduced = reduce_component(part, part_target)
        results.append(reduced)
        details.append(dict(component=index, source_faces=len(part.faces), budget=part_target,
                            output_faces=len(reduced.faces), unchanged=part_target == len(part.faces)))
    return trimesh.util.concatenate(results), details


def pad_exact(mesh, target):
    """Resolve a QEM parity shortfall by coplanar subdivision, never deleting faces.

    This does not improve detail. It changes neither the surface nor the volume.
    Recorded explicitly so 150k does not hide reduced effective QEM face counts.
    """
    shortfall = int(target - len(mesh.faces))
    if shortfall < 0 or shortfall % 2:
        raise ValueError('Cannot resolve target parity without changing topology')
    if not shortfall:
        return mesh, 0
    vertices = mesh.vertices.tolist()
    faces = mesh.faces.tolist()
    for _ in range(shortfall // 2):
        array = np.asarray(faces)
        pts = np.asarray(vertices)[array]
        i = int(np.argmax(np.linalg.norm(np.cross(pts[:, 1]-pts[:, 0], pts[:, 2]-pts[:, 0]), axis=1)))
        a, b, c = faces.pop(i)
        center = len(vertices)
        vertices.append(((np.asarray(vertices[a])+vertices[b]+vertices[c])/3).tolist())
        faces.extend(((a, b, center), (b, c, center), (c, a, center)))
    return trimesh.Trimesh(np.asarray(vertices, dtype=np.float32).astype(float), faces, process=False), shortfall


def write_stl(path, mesh):
    records = np.zeros(len(mesh.faces), dtype=STL_DTYPE)
    records['vertices'] = mesh.vertices[mesh.faces]
    triangles = records['vertices'].astype(float)
    normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    lengths = np.linalg.norm(normals, axis=1)
    if np.any(lengths <= 1e-12):
        raise ValueError('Export would introduce degenerate faces')
    records['normal'] = normals / lengths[:, None]
    with path.open('wb') as stream:
        stream.write(b'Cloud Breathing organ-aware display mesh; original coordinates'.ljust(80, b' '))
        stream.write(struct.pack('<I', len(records)))
        stream.write(records.tobytes())


def surface_samples(mesh, n, rng):
    ids = rng.choice(len(mesh.faces), size=n, p=mesh.area_faces / mesh.area)
    bary = rng.random((n, 2))
    flip = bary.sum(axis=1) > 1
    bary[flip] = 1 - bary[flip]
    triangles = mesh.vertices[mesh.faces[ids]]
    samples = triangles[:, 0] + bary[:, :1]*(triangles[:, 1]-triangles[:, 0]) + bary[:, 1:]*(triangles[:, 2]-triangles[:, 0])
    vertices = mesh.vertices[rng.choice(len(mesh.vertices), min(n, len(mesh.vertices)), replace=False)]
    # Include extrema of every component to catch some small-branch/tip losses.
    extremes = []
    for part in components(mesh):
        extremes.extend(part.vertices[np.concatenate((part.vertices.argmin(axis=0), part.vertices.argmax(axis=0)))])
    return np.vstack((samples, vertices, extremes))


def distance_report(source, reduced, n, seed):
    rng = np.random.default_rng(seed)
    result = {}
    for name, a, b in (('source_to_output', source, reduced), ('output_to_source', reduced, source)):
        samples = surface_samples(a, n, rng)
        distances = []
        for start in range(0, len(samples), 256):
            _, d, _ = trimesh.proximity.closest_point(b, samples[start:start+256])
            distances.extend(d.tolist())
        d = np.asarray(distances)
        result[name] = dict(samples=len(d), mean=float(d.mean()), p95=float(np.percentile(d, 95)),
                            p99=float(np.percentile(d, 99)), maximum_sampled=float(d.max()))
    return result


def category(name):
    name = name.lower()
    if 'tumor' in name or '肿瘤' in name:
        return 'tumor'
    if any(x in name for x in ('arter', 'venous', 'vein', 'vessel', '血管')):
        return 'vessel'
    if any(x in name for x in ('bronch', 'trache', '气管')):
        return 'airway'
    if 'lobe' in name or '肺叶' in name:
        return 'lobe'
    raise ValueError(f'Unknown organ {name}; explicitly classify it rather than guessing')


def run(args):
    started = time.perf_counter()
    destination = Path(args.output).resolve()
    if destination.exists():
        raise FileExistsError(f'Use a NEW output directory: {destination}')
    destination.mkdir(parents=True)
    originals = destination / 'original_stl'
    output = destination / 'stl_150k'
    originals.mkdir()
    output.mkdir()
    source = Path(args.input).resolve()
    if source.is_dir():
        if destination.is_relative_to(source):
            raise ValueError('Output must be outside the input folder')
        paths = sorted(p for p in source.rglob('*') if p.is_file() and p.suffix.lower() == '.stl')
        names = [p.name for p in paths]
        if len(set(n.casefold() for n in names)) != len(names):
            raise ValueError('Duplicate STL basenames in input folder')
        if sum(p.stat().st_size for p in paths) > 2_000_000_000:
            raise ValueError('STL content too large (2 GB limit)')
        for path in paths:
            shutil.copy2(path, originals / path.name)
    else:
      with zipfile.ZipFile(args.input) as archive:
        members = [i for i in archive.infolist() if i.filename.lower().endswith('.stl')]
        names = [Path(i.filename.replace('\\', '/')).name for i in members]
        if len(set(n.lower() for n in names)) != len(names):
            raise ValueError('Duplicate STL names inside ZIP')
        if sum(i.file_size for i in members) > 2_000_000_000:
            raise ValueError('Archive STL content too large')
        for info, name in zip(members, names):
            if not name or ':' in name:
                raise ValueError('Unsafe STL basename')
            (originals / name).write_bytes(archive.read(info))
    meshes = {name: read_stl((originals / name).read_bytes()) for name in sorted(names)}
    if not meshes:
        raise ValueError('No STL files')
    groups = {name: category(name) for name in meshes}
    original_counts = {name: len(mesh.faces) for name, mesh in meshes.items()}
    tumor_total = sum(original_counts[n] for n in meshes if groups[n] == 'tumor')
    if args.faces < tumor_total:
        raise ValueError(f'Target {args.faces} is below the preserved tumor face count {tumor_total}')
    remaining = args.faces - tumor_total
    group_order = ['vessel', 'airway', 'lobe']
    group_caps = [sum(original_counts[n] for n in meshes if groups[n] == group) for group in group_order]
    # At 150k: tumor=3932, vessel=120000, airway=12000, lobes=14068.
    group_mins = [sum(sum(len(p.faces) if len(p.faces) <= 256 else 64 for p in components(meshes[n]))
                      for n in meshes if groups[n] == group) for group in group_order]
    group_targets = allocate(group_caps, remaining, [120000, 12000, 14068], group_mins)
    targets = {n: c for n, c in original_counts.items() if groups[n] == 'tumor'}
    for group, budget in zip(group_order, group_targets):
        organ_names = [n for n in meshes if groups[n] == group]
        caps = [original_counts[n] for n in organ_names]
        weights = [meshes[n].area if group == 'lobe' else original_counts[n] ** .85 for n in organ_names]
        mins = [sum(len(p.faces) if len(p.faces) <= 256 else 64 for p in components(meshes[n])) for n in organ_names]
        for name, target in zip(organ_names, allocate(caps, budget, weights, mins)):
            targets[name] = target
    report = dict(target_faces=args.faces, source_faces=sum(original_counts.values()),
                  source_path=str(source),
                  algorithm='Component-wise MeshLab QEM; preserve topology, normals and boundaries; no smoothing',
                  units='Source coordinate units; bundled source reports label these as millimetres',
                  limitations=['Sampled distances are not a Hausdorff bound or clinical validation',
                               'Component/Euler checks do not prove preservation of every thin connected branch',
                               'Reduced geometry affects planning/centerline accuracy; validate results independently',
                               'Source STL files were already simplified before this run'], organs=[])
    for index, (name, mesh) in enumerate(meshes.items()):
        tick = time.perf_counter()
        group = groups[name]
        print(f'{name}: {len(mesh.faces):,} -> budget {targets[name]:,}', flush=True)
        if group == 'tumor' or targets[name] == len(mesh.faces):
            reduced = mesh.copy()
            details = []
        else:
            reduced, details = simplify(mesh, targets[name], group)
        qem_faces = len(reduced.faces)
        reduced, padded = pad_exact(reduced, targets[name])
        if group == 'tumor':
            shutil.copy2(originals / name, output / name)
        else:
            write_stl(output / name, reduced)
        exported = read_stl((output / name).read_bytes())
        before, after = quality(mesh), quality(exported)
        if not same_topology(before, after):
            raise ValueError(f'Export topology changed: {name}: {before} -> {after}')
        if group == 'tumor':
            distances = {'byte_identical': (originals / name).read_bytes() == (output / name).read_bytes()}
        else:
            distances = distance_report(mesh, exported, args.samples, 20261020 + index)
        row = dict(name=name, category=group, target=targets[name], source=before, output=after,
                   retained_percent=100*len(exported.faces)/len(mesh.faces), qem_faces=qem_faces,
                   coplanar_padding_faces=padded, components=details, distance=distances,
                   volume_change_percent=100*(after['volume']/before['volume']-1) if before['volume'] else None,
                   source_sha256=hashlib.sha256((originals/name).read_bytes()).hexdigest(),
                   output_sha256=hashlib.sha256((output/name).read_bytes()).hexdigest(),
                   seconds=time.perf_counter()-tick)
        report['organs'].append(row)
        (destination / 'report.partial.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
        print(f'  exported {after["faces"]:,}; topology unchanged; {row["seconds"]:.1f}s', flush=True)
    report['output_faces'] = sum(r['output']['faces'] for r in report['organs'])
    report['seconds'] = time.perf_counter()-started
    expected = min(args.faces, report['source_faces'])
    if report['output_faces'] != expected:
        raise ValueError(f'Expected {expected}, got {report["output_faces"]}')
    (destination / 'report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
    # Publish only after all organs pass validation. All application modules use
    # this reduced folder when selected; originals remain available separately.
    manifest = dict(version=1, original_directory='../original_stl',
                    organs=[dict(name=r['name'], source_sha256=r['source_sha256'],
                                 output_sha256=r['output_sha256']) for r in report['organs']])
    (output / 'display_source.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['# 分器官 STL 减面报告', '',
             f'输入 {report["source_faces"]:,} 面 → 输出 **{report["output_faces"]:,} 面**。', '',
             '| 文件 | 原始面数 | 输出面数 | 保留率 | 体积变化 | 双向采样最大误差* |',
             '|---|---:|---:|---:|---:|---:|']
    for r in report['organs']:
        distance = r['distance']
        maximum = max((v['maximum_sampled'] for v in distance.values() if isinstance(v, dict)), default=0)
        lines.append(f'| {r["name"]} | {r["source"]["faces"]:,} | {r["output"]["faces"]:,} | {r["retained_percent"]:.2f}% | {r["volume_change_percent"]:+.3f}% | {maximum:.4f} |')
    lines.extend(['', '*误差单位为源坐标单位，包内历史报告标为 mm；不是严格 Hausdorff 上界。', '',
                  '肿瘤 STL 字节完全一致；所有独立结构均保留。输出经重新读盘检查连通数、Euler 数、孔洞边、非流形边、绕序及退化面。',
                  '小于等于 256 面的独立组件原样保留；其余组件保留至少 64 面。QEM 不额外平滑，不调整配准坐标。',
                  'QEM 偶有少量低于预算，使用同平面三角形细分补齐；补齐数量见 JSON，不代表增加细节。',
                  '体积变化和采样误差用于工程核对，不等于临床合格。不能保证所有细分支直径完全不变。',
                  '载入减面结果时，显示、规划和中心线统一使用减面数据。减面误差进入计算结果，需要单独验证精度。原始模型另存以便恢复。', '',
                  '详细逐组件数据、SHA256、双向距离分布及耗时见 report.json。'])
    (destination / 'REPORT.md').write_text('\n'.join(lines), encoding='utf-8')
    print(f'DONE: {report["output_faces"]:,} faces in {report["seconds"]:.1f}s -> {output}', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True, help='Folder or ZIP containing named binary STL organs')
    parser.add_argument('--output', required=True, help='New directory, must not exist')
    parser.add_argument('--faces', type=int, default=150000)
    parser.add_argument('--samples', type=int, default=4000, help='Surface samples per direction + vertex samples/extrema')
    args = parser.parse_args()
    if args.faces <= 0 or args.faces % 2 or args.samples < 100:
        parser.error('faces must be positive/even, samples >= 100')
    run(args)
