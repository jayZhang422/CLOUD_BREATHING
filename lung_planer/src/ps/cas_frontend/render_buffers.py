"""Prepare float32 display buffers without touching Qt objects or analysis data."""
import numpy as np


def prepare_mesh(triangles, center, scale):
    triangles = np.asarray(triangles, dtype=np.float32).reshape(-1, 3, 3)
    if not len(triangles):
        return dict(data=b'', minimum=(0., 0., 0.), maximum=(0., 0., 0.))
    points = (triangles - np.asarray(center, dtype=np.float32)) * np.float32(scale)
    normals = np.cross(points[:, 1] - points[:, 0], points[:, 2] - points[:, 0])
    normals /= np.maximum(np.linalg.norm(normals, axis=1), 1e-12)[:, None]
    data = np.empty((len(points), 3, 6), dtype='<f4')
    data[:, :, :3], data[:, :, 3:] = points, normals[:, None, :]
    return dict(data=data.tobytes(), minimum=tuple(map(float, points.min(axis=(0, 1)))),
                maximum=tuple(map(float, points.max(axis=(0, 1)))))
