"""Optional resident shell geometry for interaction; source meshes stay intact.

The full mesh remains the still-image and planning source. This module only
prepares a second flat display buffer for large lung/lobe shells, and leaves
selection of that buffer to the viewport. Cache misses use real decimation,
never a sample of the original triangles.
"""

from dataclasses import dataclass
import math
import os
from pathlib import Path
from time import perf_counter

import numpy as np

from .mesh_buffers import prepare_display_buffers
from .stl_cache import load_preview


MIN_SOURCE_FACES = 1024
MIN_TARGET_FACES = 512
FLAT_FACE_BYTES = 3 * 6 * 4
_PROTECTED_NAMES = (
    "tumor", "tumour", "artery", "arterial", "venous", "vein", "vessel",
    "bronchus", "bronch", "airway", "plan",
)


@dataclass(frozen=True)
class InteractionLodConfig:
    mode: str = "off"
    ratio: float = 0.5
    budget_bytes: int = 32 * 1024 * 1024

    @property
    def enabled(self) -> bool:
        return self.mode == "shells"

    @classmethod
    def from_environment(cls, environ=None):
        """Parse optional settings without letting invalid values break loads."""
        values = os.environ if environ is None else environ
        mode = str(values.get("CLOUD_BREATHING_INTERACTION_LOD", "off")).strip().lower()
        if mode not in ("off", "shells"):
            mode = "off"
        try:
            ratio = float(values.get("CLOUD_BREATHING_INTERACTION_LOD_RATIO", "0.5"))
            if not math.isfinite(ratio) or not 0.0 < ratio < 1.0:
                raise ValueError("ratio must reduce geometry")
        except (TypeError, ValueError, OverflowError):
            ratio = 0.5
        try:
            mib = float(values.get("CLOUD_BREATHING_INTERACTION_LOD_MIB", "32"))
            if not math.isfinite(mib) or mib <= 0:
                raise ValueError("budget must be positive")
            budget_bytes = int(mib * 1024 * 1024)
            if budget_bytes <= 0:
                raise ValueError("budget is smaller than one byte")
        except (TypeError, ValueError, OverflowError):
            budget_bytes = 32 * 1024 * 1024
        return cls(mode=mode, ratio=ratio, budget_bytes=budget_bytes)


def _valid_triangles(vertices, normals):
    return (
        vertices.ndim == 3 and vertices.shape[1:] == (3, 3)
        and normals.shape == (len(vertices), 3) and len(vertices) > 0
        and np.isfinite(vertices).all() and np.isfinite(normals).all()
        and np.all(np.linalg.norm(
            np.cross(vertices[:, 1] - vertices[:, 0], vertices[:, 2] - vertices[:, 0]),
            axis=1,
        ) > 1e-8)
    )


def prepare_interaction_lod(path, root, vertices, normals, center, scale,
                            cache_directory, config, remaining_bytes):
    """Return (optional flat display buffers, diagnostics), with safe fallback.

    ``remaining_bytes`` is the caller's remaining shared resident-payload
    budget. The config cap also applies. Temporary simplification workspace
    is not included in this payload budget; it is released after generation.
    Original bounds are copied to the result so changing display detail does
    not move the model or alter camera fitting.
    """
    started = perf_counter()
    metrics = {
        "enabled": config.enabled, "status": "skipped", "reason": "disabled",
        "original_faces": len(vertices), "target_faces": 0, "actual_faces": 0,
        "estimated_payload_bytes": 0, "extra_payload_bytes": 0,
        "cache_hit": False, "cache_write_failed": False,
        "hash_ms": 0.0, "read_ms": 0.0, "simplify_ms": 0.0,
        "cache_ms": 0.0, "prepare_ms": 0.0, "total_ms": 0.0,
    }

    def finish(buffers=None, reason=None):
        if reason is not None:
            metrics["reason"] = reason
        metrics["total_ms"] = (perf_counter() - started) * 1000
        return buffers, metrics

    if not config.enabled:
        return finish()
    name = Path(path).stem.lower()
    if any(token in name for token in _PROTECTED_NAMES):
        return finish(reason="protected-structure")
    if "lobe" not in name and "lung" not in name:
        return finish(reason="not-shell")
    if len(vertices) < MIN_SOURCE_FACES:
        return finish(reason="small-model")

    try:
        if not math.isfinite(config.ratio) or not 0.0 < config.ratio < 1.0:
            return finish(reason="invalid-config")
        target = max(MIN_TARGET_FACES, int(len(vertices) * config.ratio))
        metrics["target_faces"] = target
        if target >= len(vertices):
            return finish(reason="no-reduction")
        available = min(int(remaining_bytes), int(config.budget_bytes))
        metrics["estimated_payload_bytes"] = target * FLAT_FACE_BYTES
        if available < metrics["estimated_payload_bytes"]:
            return finish(reason="memory-budget")
        if not cache_directory:
            return finish(reason="no-cache-directory")

        source_vertices = np.asarray(vertices)
        source_normals = np.asarray(normals)
        center_array = np.asarray(center)
        if (not _valid_triangles(source_vertices, source_normals)
                or center_array.shape != (3,) or not np.isfinite(center_array).all()
                or not math.isfinite(scale) or scale <= 0):
            return finish(reason="invalid-source-geometry")

        # load_preview verifies the file digest even on a hit. On a miss,
        # provide private copies of already-loaded geometry instead of reading
        # it again or exposing the planning arrays to a simplifier.
        def source_copy(_path):
            return source_vertices.copy(), source_normals.copy()

        reduced, reduced_normals, _low, _high, stages, hit = load_preview(
            Path(path), Path(root), Path(cache_directory) / "interaction_shells",
            target, source_copy,
        )
        for key in ("hash_ms", "read_ms", "simplify_ms", "cache_ms"):
            metrics[key] = float(stages.get(key, 0.0))
        metrics["cache_hit"] = bool(hit)
        metrics["cache_write_failed"] = bool(stages.get("cache_write_failed", False))
        if metrics["cache_write_failed"]:
            return finish(reason="cache-write-failed")
        reduced = np.asarray(reduced)
        reduced_normals = np.asarray(reduced_normals)
        if (not _valid_triangles(reduced, reduced_normals)
                or len(reduced) > target or len(reduced) >= len(source_vertices)
                or np.any(np.linalg.norm(reduced_normals, axis=1) <= 1e-8)):
            return finish(reason="invalid-preview-geometry")
        metrics["actual_faces"] = len(reduced)

        prepare_started = perf_counter()
        buffers = prepare_display_buffers(
            reduced, reduced_normals, center_array, scale, shading="flat",
        )
        metrics["prepare_ms"] = (perf_counter() - prepare_started) * 1000
        payload_bytes = len(buffers["vertex_data"]) + len(buffers["index_data"])
        if payload_bytes > available:
            return finish(reason="memory-budget-after-generation")
        source_lower = source_vertices.min(axis=(0, 1))
        source_upper = source_vertices.max(axis=(0, 1))
        buffers["low"] = np.asarray((source_lower - center_array) * scale, dtype="<f4")
        buffers["high"] = np.asarray((source_upper - center_array) * scale, dtype="<f4")
        metrics.update(status="ready", reason="prepared", extra_payload_bytes=payload_bytes)
        return finish(buffers)
    except Exception as exc:
        # Display acceleration must never prevent the full source from loading.
        metrics.update(status="fallback", error_type=type(exc).__name__, error=str(exc))
        return finish(reason="prepare-failed")
