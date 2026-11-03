"""Validated shared STL/NPY mask contract, in the application's STL mm frame.

Canonical arrays are uint8 C-order [x,y,z], z contiguous. Grid indices denote
voxel centres: world = origin + (index * spacing) @ direction.T. Direction
columns are the physical grid axes; reflections are permitted, shear is not.
No resampling, hole filling, smoothing or coordinate guessing is performed.
"""
from dataclasses import dataclass, field
from hashlib import sha256
import json
from pathlib import Path
from time import perf_counter

import numpy as np

SCHEMA = 'centerline-mask-v1'


@dataclass(frozen=True)
class VoxelMask:
    data: np.ndarray
    spacing: np.ndarray
    origin: np.ndarray
    direction: np.ndarray
    source: dict
    timings: dict = field(default=None, repr=False, compare=False)

    def __post_init__(self):
        timings = self.timings
        started = perf_counter()
        data = np.asarray(self.data)
        if data.ndim != 3 or any(n < 1 for n in data.shape):
            raise ValueError('分割掩膜必须为非空三维数组')
        if data.dtype.kind not in 'buif':
            raise ValueError('掩膜必须为有限数值或布尔数组')
        if data.dtype.kind == 'f' and not np.isfinite(data).all():
            raise ValueError('掩膜必须为有限数值或布尔数组')
        if timings is not None:
            timings['mask_type_validation_ms'] = (perf_counter() - started) * 1000.
        started = perf_counter()
        if data.dtype.kind != 'b' and not np.isin(data, (0, 1)).all():
            raise ValueError('统一掩膜只能含 0 和 1；必须先明确选择标签')
        if timings is not None:
            timings['mask_binary_validation_ms'] = (perf_counter() - started) * 1000.
        started = perf_counter()
        spacing = np.array(self.spacing, dtype=np.float64, copy=True)
        origin = np.array(self.origin, dtype=np.float64, copy=True)
        direction = np.array(self.direction, dtype=np.float64, copy=True)
        if spacing.shape != (3,) or not np.isfinite(spacing).all() or np.any(spacing <= 0):
            raise ValueError('spacing_mm 必须为三个有限正数')
        if origin.shape != (3,) or not np.isfinite(origin).all():
            raise ValueError('origin_mm 必须为三个有限数')
        if (direction.shape != (3, 3) or not np.isfinite(direction).all()
                or not np.allclose(direction.T @ direction, np.eye(3), rtol=0, atol=1e-10)):
            raise ValueError('direction 必须为正交方向矩阵；不支持剪切')
        if timings is not None:
            timings['mask_transform_validation_copy_ms'] = (perf_counter() - started) * 1000.
        started = perf_counter()
        data = np.array(data, dtype=np.uint8, order='C', copy=True)
        if timings is not None:
            timings['mask_canonical_copy_ms'] = (perf_counter() - started) * 1000.
        for name, value in (('data', data), ('spacing', spacing), ('origin', origin),
                            ('direction', direction)):
            value.setflags(write=False)
            object.__setattr__(self, name, value)

    def world(self, indices):
        return self.origin + (np.asarray(indices) * self.spacing) @ self.direction.T

    def metadata(self):
        return dict(schema=SCHEMA, shape_xyz=list(self.data.shape), layout='C-xyz-z-fastest',
                    spacing_mm=self.spacing.tolist(), origin_mm=self.origin.tolist(),
                    direction=self.direction.tolist(), coordinate_frame='stl-mm',
                    units='mm', index_location='voxel-center', source=self.source)

    def fingerprint(self):
        digest = sha256(self.data.tobytes(order='C'))
        digest.update(json.dumps(self.metadata(), sort_keys=True, allow_nan=False).encode())
        return digest.hexdigest()


def from_stl(path, spacing=.8, *, timings=None, source_sha256=None,
             stencil_workers=1):
    from .centerlines import voxelize
    path = Path(path)
    mask, origin, actual, triangles = voxelize(
        path, spacing, timings=timings, stencil_workers=stencil_workers)
    if source_sha256 is None:
        started = perf_counter()
        source_sha256 = sha256(path.read_bytes()).hexdigest()
        if timings is not None:
            timings['stl_source_hash_ms'] = (perf_counter() - started) * 1000.
    started = perf_counter()
    volume = VoxelMask(mask, [actual] * 3, origin, np.eye(3),
                       dict(format='stl', file=path.name, sha256=source_sha256,
                            triangles=triangles, requested_spacing_mm=float(spacing)),
                       timings=timings)
    if timings is not None:
        timings['mask_validate_copy_ms'] = (perf_counter() - started) * 1000.
    return volume


def distance_queries_ps_sparse(volume, coordinates, *, timings=None):
    """Exact sparse radii from a KD-tree over the six-connected background shell."""
    if not isinstance(volume, VoxelMask):
        raise TypeError('需要经过校验的 VoxelMask')
    coords = np.asarray(coordinates)
    shape = np.asarray(volume.data.shape)
    if (coords.ndim != 2 or coords.shape[1] != 3 or coords.dtype.kind not in 'iu'
            or np.any(coords < 0) or np.any(coords >= shape)):
        raise ValueError('距离查询坐标必须为范围内的 N×3 整数数组')
    if not len(coords):
        return np.empty(0, dtype=np.float64)

    foreground = volume.data.view(np.bool_)
    in_foreground = foreground[tuple(coords.T)]
    radii = np.zeros(len(coords), dtype=np.float64)
    if not np.any(in_foreground):
        return radii

    from scipy.ndimage import binary_dilation, generate_binary_structure
    from scipy.spatial import cKDTree

    started = perf_counter()
    dilated = binary_dilation(foreground, structure=generate_binary_structure(3, 1),
                              border_value=0)
    boundary = dilated & ~foreground
    boundary_coords = np.argwhere(boundary)
    if timings is not None:
        timings['distance_boundary_build_ms'] = (perf_counter() - started) * 1000.
        timings['distance_boundary_voxels'] = len(boundary_coords)
    if not len(boundary_coords):
        raise ValueError('精确稀疏距离查询要求掩膜中存在背景体素')

    started = perf_counter()
    tree = cKDTree(boundary_coords * volume.spacing, compact_nodes=True,
                   balanced_tree=True, copy_data=False)
    if timings is not None:
        timings['distance_tree_build_ms'] = (perf_counter() - started) * 1000.
    started = perf_counter()
    query_points = coords[in_foreground].astype(np.int64, copy=False)
    nearest_indices = tree.query(query_points * volume.spacing,
                                 k=1, eps=0., p=2, workers=1)[1]
    deltas = boundary_coords[nearest_indices].astype(np.int64) - query_points
    radii[in_foreground] = np.sqrt(np.sum((deltas * volume.spacing) ** 2, axis=1))
    if timings is not None:
        timings['distance_query_ms'] = (perf_counter() - started) * 1000.
    return radii


def from_npy(path, metadata_path=None):
    path = Path(path)
    metadata_path = Path(metadata_path) if metadata_path else path.with_suffix(path.suffix + '.json')
    if not metadata_path.is_file():
        raise ValueError('NPY 缺少空间元数据文件：' + str(metadata_path))
    meta = json.loads(metadata_path.read_text(encoding='utf-8'))
    required = {'schema', 'spacing_mm', 'origin_mm', 'direction', 'axis_order',
                'foreground_labels', 'coordinate_frame', 'units', 'index_location'}
    missing = required - meta.keys()
    if missing:
        raise ValueError('NPY 元数据缺项：' + ', '.join(sorted(missing)))
    if (meta['schema'] != SCHEMA or meta['units'] != 'mm'
            or meta['coordinate_frame'] != 'stl-mm' or meta['index_location'] != 'voxel-center'):
        raise ValueError('NPY 必须明确使用 centerline-mask-v1、毫米、STL 坐标系和体素中心')
    order = meta['axis_order']
    if not isinstance(order, str) or sorted(order) != ['x', 'y', 'z']:
        raise ValueError('axis_order 必须为 xyz 的排列')
    labels = meta['foreground_labels']
    if (not isinstance(labels, list) or not labels
            or any(isinstance(v, bool) or not isinstance(v, int) or v == 0 for v in labels)
            or len(set(labels)) != len(labels)):
        raise ValueError('foreground_labels 必须为不含背景 0 的非重复整数标签列表')
    array = np.load(path, allow_pickle=False)
    if not isinstance(array, np.ndarray) or array.ndim != 3 or array.dtype.kind not in 'bui':
        raise ValueError('NPY 必须为三维布尔或整数分割标签；不接受概率场')
    if not set(labels).issubset(set(np.unique(array).tolist())):
        raise ValueError('请求的前景标签在 NPY 中不存在')
    mask = np.isin(array, labels).transpose(tuple(order.index(axis) for axis in 'xyz'))
    return VoxelMask(mask, meta['spacing_mm'], meta['origin_mm'], meta['direction'],
                     dict(format='npy', file=path.name, sha256=sha256(path.read_bytes()).hexdigest(),
                          metadata_sha256=sha256(metadata_path.read_bytes()).hexdigest(), labels=labels))


def distance_queries_reference(volume, coordinates, *, max_radius=None):
    """Exact sparse EDT oracle using successive cube shells and a lower bound.

    Only in-array zero voxels are background. Once every point in [-r,r]^3
    has been inspected, any unseen point has physical distance at least
    (r+1)*min(spacing). Stop only when that bound proves the minimum. A radius
    limit produces an explicit error, never an approximate/truncated radius.
    This intentionally simple oracle is for verification, not the PS baseline.
    """
    mask = volume.data
    coords = np.asarray(coordinates)
    if coords.ndim != 2 or coords.shape[1] != 3 or coords.dtype.kind not in 'iu':
        raise ValueError('距离查询坐标必须为 N×3 整数数组')
    if np.any(coords < 0) or np.any(coords >= np.asarray(mask.shape)):
        raise ValueError('距离查询坐标越界')
    if np.all(mask):
        raise ValueError('精确距离查询要求掩膜中至少有一个背景体素')
    limit = max(mask.shape) if max_radius is None else int(max_radius)
    if limit < 1:
        raise ValueError('max_radius 必须为正整数')
    squared_spacing = volume.spacing ** 2
    answers = []
    for point in coords.astype(np.int64):
        if not mask[tuple(point)]:
            answers.append(0.)
            continue
        best = np.inf
        for radius in range(1, limit + 1):
            offsets = np.indices((2 * radius + 1,) * 3).reshape(3, -1).T - radius
            offsets = offsets[np.max(np.abs(offsets), axis=1) == radius]
            candidates = offsets + point
            valid = np.all((candidates >= 0) & (candidates < mask.shape), axis=1)
            offsets, candidates = offsets[valid], candidates[valid]
            background = mask[tuple(candidates.T)] == 0
            if np.any(background):
                best = min(best, float(np.min((offsets[background] ** 2) @ squared_spacing)))
            fully_scanned = np.all(point - radius <= 0) and np.all(point + radius >= np.asarray(mask.shape) - 1)
            if np.isfinite(best) and (best <= ((radius + 1) * np.min(volume.spacing)) ** 2 or fully_scanned):
                answers.append(np.sqrt(best))
                break
        else:
            raise RuntimeError('精确距离查询未收敛：半径限制不足')
    return np.asarray(answers, dtype=np.float64)


def integer_axis_weights(spacing):
    """Exactly represent decimal spacing ratios without quantizing geometry.

    The hardware accepts three uint32 squared-distance weights. Common
    isotropic and decimal anisotropic voxel sizes reduce to small integers.
    An unrepresentable ratio is an explicit capability error in strict PL.
    """
    from fractions import Fraction
    from functools import reduce
    from math import gcd, lcm
    values = np.asarray(spacing, dtype=np.float64)
    if values.shape != (3,) or not np.isfinite(values).all() or np.any(values <= 0):
        raise ValueError('体素间距必须为三个有限正数')
    fractions = [Fraction(str(float(v))) for v in values]
    ratios = [(v / fractions[0]) ** 2 for v in fractions]
    denominator = lcm(*(v.denominator for v in ratios))
    weights = [v.numerator * (denominator // v.denominator) for v in ratios]
    divisor = reduce(gcd, weights)
    weights = [v // divisor for v in weights]
    if max(weights) > 0xffffffff:
        raise ValueError('PL 不支持该间距的精确整数比例；没有量化或 CPU 回退')
    return np.asarray(weights, dtype=np.uint32)
