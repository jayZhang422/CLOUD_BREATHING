"""Shared validated mask-to-forest entry; hardware selection is explicit."""
from hashlib import sha256
import json
import os
from pathlib import Path
import tempfile
from time import perf_counter

import numpy as np

from .centerlines import graph_from_mask, grade_forest, validate_tree
from .voxel_mask import (VoxelMask, from_stl, from_npy,
                         distance_queries_ps_sparse)

REVISION = 'centerlines-lee-mask-exact-smooth-gap-v11'


def _preserve_stl_roots(tree, path, spacing, cache_directory):
    """Carry explicit roots only after proving the indexed graph is unchanged."""
    if path.suffix.lower() != '.stl':
        return
    target = Path(cache_directory)/(tree['cache_key']+'.roots.json')
    if target.exists():
        return
    import numpy as np
    old_key = sha256(f'centerlines-lee-v2|{tree["source_sha256"]}|{float(spacing):.9g}'.encode()).hexdigest()
    candidates = [Path(cache_directory), Path(__file__).resolve().parents[1]/'data/centerlines']
    for folder in candidates:
        try:
            roots = json.loads((folder/(old_key+'.roots.json')).read_text(encoding='utf-8'))
            old = json.loads((folder/(old_key+'.json')).read_text(encoding='utf-8'))
            if old['source_sha256'] != tree['source_sha256'] or len(old['nodes']) != len(tree['nodes']):
                continue
            if len(old['branches']) > len(tree['branches']):
                continue
            if not np.allclose([n['point'] for n in old['nodes']], [n['point'] for n in tree['nodes']], rtol=0, atol=1e-10):
                continue
            # Root grading can reverse an edge, but cannot change its node pair.
            if any({a['start'], a['end']}!={b['start'], b['end']}
                   for a,b in zip(old['branches'],tree['branches'])):
                continue
            paths_match = True
            for a, b in zip(old['branches'], tree['branches']):
                points = np.asarray(a['points'])
                other = np.asarray(b['points'])
                if points.shape != other.shape:
                    paths_match = False
                    break
                allowed_displacement = max(float(a['radii_mm'][0]),
                                           float(a['radii_mm'][-1]), 1.) * .46
                if (np.max(np.linalg.norm(points - other, axis=1)) > allowed_displacement
                        and np.max(np.linalg.norm(points - other[::-1], axis=1)) > allowed_displacement):
                    paths_match = False
                    break
            if not paths_match:
                continue
            if not all(isinstance(v,int) and 0<=v<len(tree['nodes']) for v in roots['roots']):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('x', encoding='utf-8') as out:
                json.dump(dict(roots=roots['roots'], migrated_from=old_key,
                               source_sha256=tree['source_sha256']), out)
            return
        except (OSError, ValueError, KeyError, TypeError, IndexError):
            continue


def extract_volume_cached(volume, cache_directory, *, backend='ps', distance_queries=None,
                          distance_mode=None, adjacency_backend='python',
                          cancelled=lambda: False, timings=None):
    if not isinstance(volume, VoxelMask):
        raise TypeError('需要经过校验的 VoxelMask')
    if backend not in ('ps', 'pl'):
        raise ValueError('中心线后端必须明确为 ps 或 pl')
    if distance_mode is None:
        distance_mode = 'pl' if backend == 'pl' else 'edt'
    if backend == 'pl' and distance_mode != 'pl':
        raise ValueError('PL 后端必须使用真实 PL 精确距离查询')
    if backend == 'ps' and distance_mode not in ('edt', 'sparse'):
        raise ValueError('PS 距离模式必须为 edt 或 sparse')
    if backend == 'pl' and distance_queries is None:
        raise RuntimeError('严格 PL 中心线模式缺少真实距离查询接口；没有 CPU 回退')
    if backend == 'ps' and distance_mode == 'edt' and distance_queries is not None:
        raise ValueError('PS 基线不能注入另一种距离后端')
    started = perf_counter()
    fingerprint_started = perf_counter()
    fingerprint = volume.fingerprint()
    if timings is not None:
        timings['mask_fingerprint_ms'] = (perf_counter() - fingerprint_started) * 1000.
    legacy_mode = 'pl' if backend == 'pl' else 'edt'
    variant = '' if distance_mode == legacy_mode and adjacency_backend == 'python' else \
        '|' + distance_mode + '|' + adjacency_backend
    key = sha256(f'{REVISION}|{backend}{variant}|{fingerprint}'.encode()).hexdigest()
    cache = Path(cache_directory) / (key + '.json')
    if cancelled():
        raise RuntimeError('中心线分析已取消')
    cache_read_started = perf_counter()
    try:
        tree = json.loads(cache.read_text(encoding='utf-8'))
        if timings is not None:
            timings['geometry_cache_read_ms'] = (perf_counter() - cache_read_started) * 1000.
        if tree['cache_key'] != key or tree['revision'] != REVISION or tree['centerline_backend'] != backend:
            raise ValueError('cache identity')
        if (tree.get('distance_mode', legacy_mode) != distance_mode
                or tree.get('adjacency_backend', 'python') != adjacency_backend):
            raise ValueError('cache algorithm identity')
        validate_started = perf_counter()
        validate_tree(tree)
        if timings is not None:
            timings['cache_tree_validation_ms'] = (perf_counter() - validate_started) * 1000.
        grading_started = perf_counter()
        grade_forest(tree)
        if timings is not None:
            timings['root_and_grading_ms'] = (perf_counter() - grading_started) * 1000.
        tree.update(cache_hit=True, elapsed_ms=(perf_counter()-started)*1000,
                    execution=dict(ps=['cache-read', 'grade'], pl_calls=0, cpu_fallback_count=0))
        return tree
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        if timings is not None and 'geometry_cache_read_ms' not in timings:
            timings['geometry_cache_read_ms'] = (perf_counter() - cache_read_started) * 1000.
        pass
    if distance_mode == 'sparse':
        distance_queries = lambda coords: distance_queries_ps_sparse(
            volume, coords, timings=timings)
    mask_view_started = perf_counter()
    graph_mask = volume.data.view(np.bool_)
    if timings is not None:
        timings['graph_mask_view_ms'] = (perf_counter() - mask_view_started) * 1000.
    tree = graph_from_mask(graph_mask, volume.origin, volume.spacing,
                           cancelled, timings=timings, distance_queries=distance_queries,
                           direction=volume.direction, adjacency_backend=adjacency_backend)
    grading_started = perf_counter()
    grade_forest(tree)
    if timings is not None:
        timings['root_and_grading_ms'] = (perf_counter() - grading_started) * 1000.
    tree.update(revision=REVISION, cache_key=key, centerline_backend=backend,
                source_sha256=volume.source.get('sha256'), mask_metadata=volume.metadata(),
                spacing_mm=volume.spacing.tolist(), occupied_voxels=int(volume.data.sum()),
                coordinate_space=('source_stl' if volume.source.get('format') == 'stl'
                                  else 'physical_mm'),
                distance_mode=distance_mode, adjacency_backend=adjacency_backend,
                cache_hit=False, elapsed_ms=(perf_counter()-started)*1000,
                execution=dict(ps=['lee', 'graph', 'smooth', 'gap-repair', 'grade', 'display'],
                               pl_operation='exact-skeleton-background-distance' if backend=='pl' else None,
                               cpu_fallback_count=0))
    if cancelled():
        raise RuntimeError('中心线分析已取消')
    cache.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    write_started = perf_counter()
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=cache.parent,
                                          suffix='.tmp', delete=False) as out:
            temporary = out.name
            # json.dump streams through the pure-Python encoder; dumps uses the C one (same bytes).
            out.write(json.dumps(tree, ensure_ascii=False, separators=(',', ':'), allow_nan=False))
        os.replace(temporary, cache)
    except OSError as exc:
        tree['cache_warning'] = str(exc)
    finally:
        if temporary and Path(temporary).exists():
            Path(temporary).unlink()
    if timings is not None:
        timings['centerline_cache_write_ms'] = (perf_counter() - write_started) * 1000.
    return tree


def extract_source_cached(path, cache_directory, spacing=.8, *, backend='ps', pl=None,
                          metadata_path=None, cancelled=lambda: False,
                          progress=lambda message: None, timings=None,
                          distance_mode=None, adjacency_backend='vectorized',
                          stencil_workers=4):
    """STL and NPY converge before Lee/EDT/graph processing.

    NPY spacing always comes from its required sidecar, never the STL GUI's
    scalar spacing preference. Cached root selections stay backend-specific.
    """
    started = perf_counter()
    path = Path(path)
    if backend not in ('ps', 'pl'):
        raise ValueError('中心线后端必须明确为 ps 或 pl')
    if distance_mode is None:
        distance_mode = 'pl' if backend == 'pl' else 'edt'
    if ((backend == 'pl' and distance_mode != 'pl')
            or (backend == 'ps' and distance_mode not in ('edt', 'sparse'))):
        raise ValueError('中心线距离模式与所选后端不匹配')
    source_hash_started = perf_counter()
    source_sha = sha256(path.read_bytes()).hexdigest()
    sidecar_sha = ''
    if path.suffix.lower() == '.npy':
        sidecar = Path(metadata_path) if metadata_path else path.with_suffix('.npy.json')
        if not sidecar.is_file():
            raise ValueError('NPY 缺少空间元数据文件：'+str(sidecar))
        sidecar_sha = sha256(sidecar.read_bytes()).hexdigest()
    if timings is not None:
        timings['source_hash_ms'] = (perf_counter() - source_hash_started) * 1000.
    legacy_mode = 'pl' if backend == 'pl' else 'edt'
    variant = '' if distance_mode == legacy_mode and adjacency_backend == 'python' else \
        '|' + distance_mode + '|' + adjacency_backend
    source_key = sha256(
        f'{REVISION}|source|{source_sha}|{sidecar_sha}|{backend}{variant}|{float(spacing):.9g}'.encode()
    ).hexdigest()
    index_path = Path(cache_directory) / (source_key+'.source.json')
    if cancelled():
        raise RuntimeError('中心线分析已取消')
    cache_read_started = perf_counter()
    try:
        index = json.loads(index_path.read_text(encoding='utf-8'))
        key = index['cache_key']
        if not isinstance(key, str) or len(key)!=64 or any(c not in '0123456789abcdef' for c in key):
            raise ValueError('Invalid source cache key')
        tree = json.loads((Path(cache_directory)/(key+'.json')).read_text(encoding='utf-8'))
        if timings is not None:
            timings['source_cache_read_ms'] = (perf_counter() - cache_read_started) * 1000.
        if (tree['cache_key']!=key or tree['revision']!=REVISION
                or tree['centerline_backend']!=backend or tree['source_sha256']!=source_sha):
            raise ValueError('Source cache identity')
        if (tree.get('distance_mode', legacy_mode) != distance_mode
                or tree.get('adjacency_backend', 'python') != adjacency_backend):
            raise ValueError('Source cache algorithm identity')
        validate_started = perf_counter()
        validate_tree(tree)
        if timings is not None:
            timings['cache_tree_validation_ms'] = (perf_counter() - validate_started) * 1000.
        grading_started = perf_counter()
        grade_forest(tree)
        if timings is not None:
            timings['root_and_grading_ms'] = (perf_counter() - grading_started) * 1000.
        tree.update(cache_hit=True, hardware_runs=[], elapsed_ms=(perf_counter()-started)*1000,
                    elapsed_scope='source-read-through-cache-read',
                    execution=dict(ps=['cache-read', 'grade'], pl_calls=0, cpu_fallback_count=0))
        root_started = perf_counter()
        _preserve_stl_roots(tree, path, spacing, cache_directory)
        if timings is not None:
            timings['root_migration_ms'] = (perf_counter() - root_started) * 1000.
        return tree
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        if timings is not None and 'source_cache_read_ms' not in timings:
            timings['source_cache_read_ms'] = (perf_counter() - cache_read_started) * 1000.
        pass
    progress('读取分割掩膜' if path.suffix.lower()=='.npy' else '表面检查与体素化')
    if path.suffix.lower() == '.npy':
        volume = from_npy(path, metadata_path)
    elif path.suffix.lower() == '.stl':
        volume = from_stl(path, spacing, timings=timings, source_sha256=source_sha,
                          stencil_workers=stencil_workers)
    else:
        raise ValueError('中心线源必须为 STL 或 NPY 分割掩膜')
    metrics = []

    def query(coords):
        if distance_mode == 'sparse':
            return distance_queries_ps_sparse(volume, coords, timings=timings)
        if pl is None:
            raise RuntimeError('严格 PL 中心线缺少硬件客户端；没有 CPU 回退')
        result = pl.evaluate_mask_distances(volume, coords)
        if not result.get('ok') or result.get('pl_calls', 0) <= 0 or result.get('cpu_fallback_count') != 0:
            raise RuntimeError('中心线距离查询缺少真实 PL 计数；没有 CPU 回退')
        metrics.append({k: v for k, v in result.items() if k not in ('radii_mm', 'deltas_xyz')})
        return result['radii_mm']

    progress('Lee 骨架与精确距离查询 · '+backend.upper())
    tree = extract_volume_cached(volume, cache_directory, backend=backend,
        distance_queries=query if distance_mode in ('pl', 'sparse') else None,
        distance_mode=distance_mode, adjacency_backend=adjacency_backend,
        cancelled=cancelled, timings=timings)
    tree['hardware_runs'] = metrics
    tree['execution']['pl_calls'] = sum(m['pl_calls'] for m in metrics)
    root_started = perf_counter()
    _preserve_stl_roots(tree, path, spacing, cache_directory)
    if timings is not None:
        timings['root_migration_ms'] = (perf_counter() - root_started) * 1000.
    index_write_started = perf_counter()
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=index_path.parent,
                                          suffix='.tmp', delete=False) as out:
            temporary = out.name
            json.dump(dict(cache_key=tree['cache_key']), out)
        os.replace(temporary, index_path)
    except OSError as exc:
        tree['cache_warning'] = str(exc)
        if 'temporary' in locals() and Path(temporary).exists():
            Path(temporary).unlink()
    if timings is not None:
        timings['source_index_write_ms'] = (perf_counter() - index_write_started) * 1000.
    tree['elapsed_ms'] = (perf_counter()-started)*1000
    tree['elapsed_scope'] = 'source-read-through-cache-write'
    return tree
