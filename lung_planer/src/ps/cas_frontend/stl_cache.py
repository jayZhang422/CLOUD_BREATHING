"""Optional, source-verified decimated STL preview cache."""

import hashlib
import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from time import perf_counter
from zipfile import BadZipFile

import numpy as np


CACHE_VERSION = 1


def face_targets(face_counts: list[int], budget: int) -> list[int]:
    if budget < len(face_counts):
        raise ValueError("预览面数上限小于 STL 结构数量")
    if sum(face_counts) <= budget:
        return face_counts.copy()
    targets = [max(1, min(count, count * budget // sum(face_counts))) for count in face_counts]
    remaining = budget - sum(targets)
    while remaining:
        eligible = [i for i, count in enumerate(face_counts) if targets[i] < count]
        if not eligible:
            break
        for i in eligible:
            if not remaining:
                break
            targets[i] += 1
            remaining -= 1
    return targets


def _source_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _cache_path(path: Path, root: Path, cache_dir: Path, target_faces: int) -> Path:
    relative = path.relative_to(root).as_posix()
    key = hashlib.sha256(relative.encode("utf-8")).hexdigest()[:20]
    return cache_dir / f"{key}-{target_faces}.npz"


def _normals(vertices: np.ndarray) -> np.ndarray:
    calculated = np.cross(vertices[:, 1] - vertices[:, 0], vertices[:, 2] - vertices[:, 0])
    lengths = np.linalg.norm(calculated, axis=1)
    if not np.all(np.isfinite(lengths)) or np.any(lengths <= 1e-8):
        raise ValueError("减面结果包含无效三角形")
    return (calculated / lengths[:, None]).astype(np.float32)


def load_preview(path: Path, root: Path, cache_dir: Path, target_faces: int, read_stl):
    """Return triangle soup, original bounds, timing data, and cache-hit flag."""
    started = perf_counter()
    digest = _source_digest(path)
    cache_path = _cache_path(path, root, cache_dir, target_faces)
    timings = {"hash_ms": (perf_counter() - started) * 1000, "read_ms": 0.0,
               "simplify_ms": 0.0, "cache_ms": 0.0}
    started = perf_counter()
    try:
        with np.load(cache_path, allow_pickle=False) as cached:
            if (int(cached["version"]) == CACHE_VERSION
                    and str(cached["source_digest"]) == digest
                    and int(cached["target_faces"]) == target_faces):
                vertices = cached["vertices"].astype(np.float32, copy=True)
                normals = cached["normals"].astype(np.float32, copy=True)
                lower = cached["lower"].astype(np.float32, copy=True)
                upper = cached["upper"].astype(np.float32, copy=True)
                if (vertices.ndim == 3 and vertices.shape[1:] == (3, 3)
                        and 0 < len(vertices) <= target_faces
                        and normals.shape == (len(vertices), 3)
                        and lower.shape == upper.shape == (3,)
                        and np.isfinite(vertices).all() and np.isfinite(normals).all()
                        and np.isfinite(lower).all() and np.isfinite(upper).all()):
                    timings["cache_ms"] = (perf_counter() - started) * 1000
                    return vertices, normals, lower, upper, timings, True
    except (OSError, KeyError, ValueError, TypeError, EOFError, BadZipFile):
        pass
    timings["cache_ms"] = (perf_counter() - started) * 1000

    try:
        import fast_simplification
    except ImportError as exc:
        raise RuntimeError(
            "未找到有效减面缓存；首次生成需要 fast-simplification。"
            "可在桌面环境安装并生成缓存，再复制 data/stl_cache 到板端"
        ) from exc

    started = perf_counter()
    vertices, _ = read_stl(path)
    lower = vertices.min(axis=(0, 1))
    upper = vertices.max(axis=(0, 1))
    timings["read_ms"] = (perf_counter() - started) * 1000
    started = perf_counter()
    points, inverse = np.unique(vertices.reshape(-1, 3), axis=0, return_inverse=True)
    reduced_points, reduced_faces = fast_simplification.simplify(
        points.astype(np.float64), inverse.reshape(-1, 3).astype(np.int32),
        target_count=target_faces, preserve_border=True,
    )
    if len(reduced_faces) == 0 or len(reduced_faces) > target_faces:
        raise ValueError(f"{path.name} 无法安全减到 {target_faces:,} 面，请提高预览上限")
    reduced = np.asarray(reduced_points[reduced_faces], dtype=np.float32)
    normals = _normals(reduced)
    timings["simplify_ms"] = (perf_counter() - started) * 1000

    timings["cache_write_failed"] = False
    started = perf_counter()
    temp_path = None
    try:
        cache_dir.mkdir(parents=True, exist_ok=True)
        with NamedTemporaryFile(dir=cache_dir, suffix=".npz", delete=False) as stream:
            temp_path = Path(stream.name)
            np.savez(stream, version=CACHE_VERSION, source_digest=digest,
                     target_faces=target_faces, vertices=reduced, normals=normals,
                     lower=lower, upper=upper)
        os.replace(temp_path, cache_path)
    except OSError:
        timings["cache_write_failed"] = True
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)
    timings["cache_ms"] += (perf_counter() - started) * 1000
    return reduced, normals, lower, upper, timings, False
