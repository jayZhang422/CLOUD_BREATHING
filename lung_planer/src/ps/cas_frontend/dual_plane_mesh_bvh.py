"""Lossless FP64 stackless BVH image for the dual-plane RTL engine.

Nodes are preorder records. `escape` skips the entire subtree; an internal
node's first child is the next record. Triangles remain exact and only change
order. Aggregate volume is relative to the mesh bounds center and is paired
with the vector flux, allowing translation to any candidate ridge origin.
"""
from dataclasses import dataclass
import hashlib
from functools import lru_cache
import numpy as np

NODE_BYTES = 128
DEFAULT_LEAF_SIZE = 4


def is_bytes_backed_mesh(triangles):
    owner = triangles
    while isinstance(owner, np.ndarray):
        if owner.flags.writeable:
            return False
        owner = owner.base
    return isinstance(owner, bytes) or (isinstance(owner, memoryview)
        and owner.readonly and isinstance(owner.obj, bytes))
NODE_DTYPE = np.dtype(dict(
    names=['lower', 'upper', 'escape', 'first', 'count', 'leaf',
           'volume', 'area', 'flux', 'reserved'],
    formats=[('<f8', 3), ('<f8', 3), '<u4', '<u4', '<u4', '<u4',
             '<f8', '<f8', ('<f8', 3), ('<u8', 3)],
    offsets=[0, 24, 48, 52, 56, 60, 64, 72, 80, 104], itemsize=NODE_BYTES))


@dataclass
class MeshBvhImage:
    triangles: np.ndarray
    nodes: np.ndarray
    center: np.ndarray
    source_sha256: str


def build_mesh_bvh(triangles, leaf_size=DEFAULT_LEAF_SIZE):
    triangles=np.ascontiguousarray(triangles,dtype='<f8').reshape(-1,3,3)
    if not len(triangles) or not np.isfinite(triangles).all():
        raise ValueError('BVH requires finite nonempty triangles')
    if not 1<=leaf_size<=64:raise ValueError('BVH leaf size outside 1..64')
    lower,upper=triangles.min(axis=1),triangles.max(axis=1)
    center=(lower.min(axis=0)+upper.max(axis=0))*.5
    centroids=(lower+upper)*.5
    cross=np.cross(triangles[:,1]-triangles[:,0],triangles[:,2]-triangles[:,0])
    flux=cross/6.
    volumes=np.einsum('ij,ij->i',triangles[:,0]-center,flux)
    areas=np.linalg.norm(cross,axis=1)*.5
    @lru_cache(None)
    def size(n):return 1 if n<=leaf_size else 1+size(n//2)+size(n-n//2)
    nodes=np.zeros(size(len(triangles)),dtype=NODE_DTYPE)
    order=np.empty(len(triangles),dtype=np.int64)
    # Batches have equal-length rows; no padding or altered sum order.
    pending=[(np.arange(len(triangles))[None,:],np.array([0]),np.array([0]))]
    while pending:
        groups={}
        for ids,index,first in pending:
            n=ids.shape[1]
            nodes['lower'][index]=lower[ids].min(axis=1)
            nodes['upper'][index]=upper[ids].max(axis=1)
            nodes['escape'][index]=index+size(n)
            nodes['first'][index]=first
            nodes['count'][index]=n
            nodes['leaf'][index]=n<=leaf_size
            nodes['volume'][index]=volumes[ids].sum(axis=1,dtype=np.float64)
            nodes['area'][index]=areas[ids].sum(axis=1,dtype=np.float64)
            nodes['flux'][index]=flux[ids].sum(axis=1,dtype=np.float64)
            if n<=leaf_size:
                order[first[:,None]+np.arange(n)]=ids
            else:
                axis=np.argmax(np.ptp(centroids[ids],axis=1),axis=1)
                keys=centroids[ids,axis[:,None]]
                sorted_ids=np.take_along_axis(ids,np.argsort(keys,axis=1,kind='stable'),axis=1)
                mid=n//2
                for child,ni,fi in [(sorted_ids[:,:mid],index+1,first),
                                    (sorted_ids[:,mid:],index+1+size(mid),first+mid)]:
                    groups.setdefault(child.shape[1],[]).append((child,ni,fi))
        pending=[tuple(np.concatenate([p[k] for p in parts],axis=0) for k in range(3))
                 for parts in groups.values()]
    return MeshBvhImage(triangles[order],nodes,center,hashlib.sha256(triangles.tobytes()).hexdigest())

