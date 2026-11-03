"""Deterministic DDR mesh/BVH layout shared by software and the PL BVH traversal."""
from dataclasses import dataclass
from time import perf_counter
import hashlib
import numpy as np

NODE_BYTES = 48
INVALID = 0xffffffff
LEAF_SIZE = 8
MAX_SOLIDS = 32


@dataclass(frozen=True)
class MeshImage:
    key: str
    triangle_bytes: bytes
    node_bytes: bytes
    order: np.ndarray
    nodes: np.ndarray
    solid_ids: np.ndarray
    build_ms: float
    pack_ms: float
    solid_count: int


def mesh_key(triangles, solid_ids=None):
    values = np.ascontiguousarray(triangles, dtype='<f8').reshape(-1, 3, 3)
    if not len(values) or not np.isfinite(values).all():
        raise ValueError('mesh must contain finite triangles')
    ids = _solid_ids(solid_ids, len(values))
    digest = hashlib.sha256()
    digest.update(b'mesh-bvh-layout-v2\0')
    digest.update(values.tobytes())
    digest.update(ids.astype('<u4', copy=False).tobytes())
    return digest.hexdigest()


def _solid_ids(solid_ids, triangle_count):
    if solid_ids is None:
        return np.zeros(triangle_count, dtype='<u4')
    ids = np.ascontiguousarray(solid_ids, dtype=np.int64).reshape(-1)
    if len(ids) != triangle_count or np.any(ids < 0) or np.any(ids >= MAX_SOLIDS):
        raise ValueError('solid IDs must match triangles and fit MAX_SOLIDS')
    present = np.unique(ids)
    if not len(present) or not np.array_equal(present, np.arange(len(present))):
        raise ValueError('solid IDs must be contiguous from zero')
    return ids.astype('<u4')


def build_mesh_image(triangles, leaf_size=LEAF_SIZE, solid_ids=None):
    """Build a balanced median BVH with outward-rounded Q16.16 bounds.

    Node words: min xyz, max xyz, left, right, first, count, type, reserved.
    Leaves address the reordered triangle buffer; root is node zero.
    """
    started = perf_counter()
    values = np.ascontiguousarray(triangles, dtype='<f8').reshape(-1, 3, 3)
    ids = _solid_ids(solid_ids, len(values))
    key = mesh_key(values, ids)
    if leaf_size < 1:
        raise ValueError('leaf size must be positive')
    rounded = np.rint(values * 65536.)
    if np.any(rounded < -2147483648) or np.any(rounded > 2147483647):
        raise ValueError('mesh is outside signed Q16.16 range')
    # Include both original and quantized geometry in each node bound.
    low = np.minimum(np.floor(values.min(axis=1) * 65536.), rounded.min(axis=1))
    high = np.maximum(np.ceil(values.max(axis=1) * 65536.), rounded.max(axis=1))
    if np.any(low < -2147483648) or np.any(high > 2147483647):
        raise ValueError('outward BVH bounds exceed signed Q16.16 range')
    centers = values.mean(axis=1)
    nodes, order = [], []

    def split(indices):
        index = len(nodes)
        node = [*low[indices].min(axis=0).astype(np.int64),
                *high[indices].max(axis=0).astype(np.int64),
                INVALID, INVALID, 0, 0, 0, 0]
        nodes.append(node)
        if len(indices) <= leaf_size:
            node[8:11] = [len(order), len(indices), 1]
            order.extend(indices.tolist())
        else:
            axis = int(np.argmax(np.ptp(centers[indices], axis=0)))
            sorted_indices = indices[np.argsort(centers[indices, axis], kind='stable')]
            mid = len(indices) // 2
            node[6], node[7] = split(sorted_indices[:mid]), split(sorted_indices[mid:])
        return index

    split(np.arange(len(values)))
    order = np.asarray(order, dtype=np.int64)
    node_words = np.asarray(nodes, dtype=np.int64).astype('<u4')
    build_ms = (perf_counter() - started) * 1000.
    started = perf_counter()
    words = np.zeros((len(values), 12), dtype='<i4')
    words[:, :9] = rounded[order].reshape(-1, 9).astype('<i4')
    words[:, 9] = ids[order].astype('<i4')
    triangle_bytes, node_bytes = words.tobytes(), node_words.tobytes()
    pack_ms = (perf_counter() - started) * 1000.
    node_words.setflags(write=False)
    order.setflags(write=False)
    packed_ids = ids[order].copy()
    packed_ids.setflags(write=False)
    return MeshImage(key, triangle_bytes, node_bytes, order, node_words, packed_ids,
                     build_ms, pack_ms, int(ids.max()) + 1)
