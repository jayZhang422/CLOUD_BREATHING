"""Validated mesh snapshots; immutable storage allows safe content-key reuse."""
from dataclasses import dataclass

import numpy as np

from .mesh_bvh import _solid_ids, mesh_key


@dataclass(frozen=True, init=False, eq=False)
class FrozenMesh:
    triangles: np.ndarray
    solid_ids: np.ndarray
    key: str
    solid_count: int
    triangle_count: int

    def __init__(self, triangles, solid_ids=None):
        values = np.asarray(triangles, dtype='<f8').reshape(-1, 3, 3)
        ids = _solid_ids(solid_ids, len(values))
        # A mere setflags(write=False) can be reversed by another owner.
        # bytes-backed snapshots cannot regain write access through any view.
        frozen = np.frombuffer(values.tobytes(), dtype='<f8').reshape(-1, 3, 3)
        labels = np.frombuffer(ids.astype('<u4').tobytes(), dtype='<u4')
        key = mesh_key(frozen, labels)
        object.__setattr__(self, 'triangles', frozen)
        object.__setattr__(self, 'solid_ids', labels)
        object.__setattr__(self, 'key', key)
        object.__setattr__(self, 'solid_count', int(labels.max()) + 1)
        object.__setattr__(self, 'triangle_count', len(frozen))

    def matches(self, triangles, solid_ids):
        # Identity is meaningful only for these owned immutable snapshots.
        # Check metadata too, since NumPy permits editing an array's header.
        return (triangles is self.triangles and solid_ids is self.solid_ids
                and triangles.shape == (self.triangle_count, 3, 3)
                and triangles.dtype == np.dtype('<f8') and triangles.flags.c_contiguous
                and not triangles.flags.writeable
                and solid_ids.shape == (self.triangle_count,)
                and solid_ids.dtype == np.dtype('<u4') and solid_ids.flags.c_contiguous
                and not solid_ids.flags.writeable)
