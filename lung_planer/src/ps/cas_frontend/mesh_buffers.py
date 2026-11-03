"""Display-only GLES2-safe buffers; source triangles are never modified."""

import os
import numpy as np


DISPLAY_BUFFER_ALGORITHM_VERSION = 1


def prepare_display_buffers(vertices, normals, center, scale, shading="flat"):
    """Keep every triangle position/order while optionally sharing smooth normals.

    GLES2 does not require 32-bit element indices, so this function uses U16
    only. More than 65,536 unique vertices, or no byte saving, keeps the
    original flat triangle buffer. Smoothing changes lighting, not geometry.
    """
    points = np.asarray((vertices - center) * scale, dtype="<f4").reshape(-1, 3)
    face_normals = np.asarray(normals, dtype="<f4")
    if shading == "smooth":
        # Sanitize only the display copy, including when U16 limits later
        # require flat fallback. Never alter normals read by the PL backend.
        source = face_normals.astype(np.float64)
        invalid = ~np.isfinite(source).all(axis=1) | (np.linalg.norm(source, axis=1) <= 1e-12)
        if invalid.any():
            triangle_points = points.reshape(-1, 3, 3).astype(np.float64)
            calculated = np.cross(triangle_points[:, 1] - triangle_points[:, 0],
                                  triangle_points[:, 2] - triangle_points[:, 0])
            lengths = np.linalg.norm(calculated, axis=1)
            valid = np.isfinite(calculated).all(axis=1) & (lengths > 1e-12)
            calculated[valid] /= lengths[valid, None]
            calculated[~valid] = (0., 0., 1.)
            source[invalid] = calculated[invalid]
        face_normals = source.astype("<f4")
    flat = np.empty((len(points), 6), dtype="<f4")
    flat[:, :3] = points
    flat.reshape(-1, 3, 6)[:, :, 3:] = face_normals[:, None, :]
    data = flat
    index_data = b""
    effective = "flat"
    reason = "requested-flat"
    if shading == "flat" and os.environ.get("CLOUD_BREATHING_EXACT_INDEX", "0") == "1":
        # Compare all 24 bytes: preserve hard normals, signed zero, winding
        # and original triangle order. Never weld positions alone.
        keys = flat.view(np.dtype((np.void, 24))).reshape(-1)
        _, first, inverse = np.unique(keys, return_index=True, return_inverse=True)
        if len(first) <= 65536 and len(first) * 24 + len(inverse) * 2 < flat.nbytes:
            data = flat[first]
            index_data = inverse.astype("<u2").tobytes()
            reason = "exact-indexed"
        else:
            reason = "exact-index-fallback"

    if shading == "smooth":
        positions, first, inverse = np.unique(points, axis=0, return_index=True, return_inverse=True)
        if len(positions) > 65536:
            reason = "uint16-limit"
        elif len(positions) * 24 + len(inverse) * 2 >= flat.nbytes:
            reason = "no-byte-saving"
        else:
            source_lengths = np.linalg.norm(source, axis=1)
            source /= source_lengths[:, None]
            corner_normals = np.repeat(source, 3, axis=0)
            averaged = np.zeros((len(positions), 3), dtype=np.float64)
            np.add.at(averaged, inverse, corner_normals)
            lengths = np.linalg.norm(averaged, axis=1)
            valid = lengths > 1e-12
            averaged[valid] /= lengths[valid, None]
            averaged[~valid] = corner_normals[first[~valid]]
            data = np.column_stack((positions, averaged)).astype("<f4")
            index_data = inverse.astype("<u2").tobytes()
            effective = "smooth"
            reason = "indexed"

    return {
        "vertex_data": data.tobytes(), "index_data": index_data,
        "low": points.min(axis=0), "high": points.max(axis=0),
        "triangle_count": len(points) // 3, "vertex_count": len(data),
        "upload_bytes": data.nbytes + len(index_data), "soup_bytes": flat.nbytes,
        "shading": effective, "reason": reason,
    }
