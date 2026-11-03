"""CPU Boolean metrics on the original, double precision STL geometry.

Manifold tracks source faces through intersection, separating the removed
pleural surface from the newly exposed cutting faces without point sampling.
No voxelization, convex hull, or automatic hole filling is performed.
"""
import hashlib
from pathlib import Path
from time import perf_counter

import numpy as np

from .mesh_triangle import unique_rows


def _library():
    try:
        import manifold3d
    except ImportError as exc:
        raise ValueError('纯 PS 并集量化需要 manifold3d；请运行 python -m pip install manifold3d==3.5.4') from exc
    return manifold3d


def _solid(triangles, label):
    m = _library()
    triangles = np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
    if not len(triangles) or not np.isfinite(triangles).all():
        raise ValueError(f'{label}：网格为空或含非有限坐标')
    vertices, indices = unique_rows(triangles.reshape(-1, 3))
    faces = indices.reshape(-1, 3).astype(np.uint64)
    # A consistently reversed STL is still the same enclosed solid. Do not
    # merge nearby vertices or repair topology: that could alter a safety gap.
    centered = triangles - vertices.mean(axis=0)
    signed = np.einsum('ij,ij->i', centered[:, 0],
                       np.cross(centered[:, 1], centered[:, 2])).sum()
    if signed < 0:
        faces = np.ascontiguousarray(faces[:, ::-1])
    solid = m.Manifold(m.Mesh64(vertices, faces))
    if solid.status() != m.Error.NoError or solid.is_empty() or solid.volume() <= 0:
        raise ValueError(f'{label}：无法构造闭合有向实体（{solid.status()}）；请检查网格拓扑和面朝向')
    return solid


def _triangles(solid):
    mesh = solid.to_mesh64()
    return np.asarray(mesh.vert_properties)[:, :3][np.asarray(mesh.tri_verts)].copy()


def _area(triangles):
    return float(np.linalg.norm(np.cross(triangles[:, 1] - triangles[:, 0],
                                         triangles[:, 2] - triangles[:, 0]), axis=1).sum() * .5)


def _stable_triangle_order(triangles):
    triangles = np.asarray(triangles, dtype=np.float64).reshape(-1, 3, 3)
    if len(triangles) < 2:
        return triangles
    first = np.lexsort((triangles[:, :, 2], triangles[:, :, 1],
                        triangles[:, :, 0]), axis=1)[:, 0]
    indices = (first[:, None] + np.arange(3)[None, :]) % 3
    triangles = np.take_along_axis(triangles, indices[:, :, None], axis=1)
    keys = triangles.reshape(len(triangles), 9)[:, ::-1].T
    return triangles[np.lexsort(keys)]


class LungUnion:
    def __init__(self, meshes, labels, cache_dir=None):
        m = _library()
        meshes = [np.asarray(mesh, dtype=np.float64).reshape(-1, 3, 3) for mesh in meshes]
        if not meshes or any(not len(mesh) for mesh in meshes):
            raise ValueError('没有参与量化的肺实体')
        cache_file = self._cache_file(meshes, labels, cache_dir)
        self.cache_hit = False
        if cache_file is not None:
            try:
                with np.load(cache_file, allow_pickle=False) as cached:
                    cached_triangles = np.asarray(cached['triangles'], dtype=np.float64)
                self.solid = _solid(cached_triangles, '缓存肺并集').as_original()
                self.cache_hit = True
            except (OSError, KeyError, ValueError, TypeError):
                self.solid = None
        else:
            self.solid = None
        if self.solid is None:
            solids = [_solid(mesh, label) for mesh, label in zip(meshes, labels)]
            self.solid = m.Manifold.batch_boolean(solids, m.OpType.Add).as_original()
            if self.solid.status() != m.Error.NoError or self.solid.is_empty():
                raise ValueError(f'肺实体布尔并集失败：{self.solid.status()}')
            if cache_file is not None:
                try:
                    cache_file.parent.mkdir(parents=True, exist_ok=True)
                    triangles = _triangles(self.solid)
                    temporary = cache_file.with_name(cache_file.name + '.tmp.npz')
                    np.savez(temporary, triangles=triangles)
                    temporary.replace(cache_file)
                except (OSError, ValueError):
                    try:
                        temporary.unlink(missing_ok=True)
                    except (OSError, UnboundLocalError):
                        pass
        self.volume_mm3 = float(self.solid.volume())
        self.triangles = _triangles(self.solid)
        self.bounds_min = self.triangles.reshape(-1, 3).min(axis=0)
        self.bounds_max = self.triangles.reshape(-1, 3).max(axis=0)
        self._last_key = None
        self._last = None
        self._volume_key = None
        self._volume_manifold = None
        self._volume_tetra_original_id = None
        self._volume_timings_ms = None

    @staticmethod
    def _tetrahedron(vertices):
        """Build the oriented tetrahedron used by the exact wedge Boolean."""
        m = _library()
        vertices = np.asarray(vertices, dtype=np.float64).reshape(4, 3)
        faces = np.asarray(((0, 1, 2), (0, 3, 1), (1, 3, 2), (2, 3, 0)))
        for i, face in enumerate(faces):
            a, b, c = vertices[face]
            opposite = next(j for j in range(4) if j not in face)
            if np.dot(np.cross(b - a, c - a), vertices[opposite] - a) > 0:
                faces[i] = face[::-1]
        return _solid(vertices[faces], '规划四面体').as_original()

    def intersect_volume(self, vertices):
        """Evaluate only the authoritative float64 intersection volume.

        Search ranking does not need source-face triangles or surface areas.
        Keep the resulting Manifold so a later full intersection for a winning
        candidate can reuse the exact Boolean object without rebuilding it.
        """
        total_started = perf_counter()
        m = _library()
        vertices = np.asarray(vertices, dtype=np.float64).reshape(4, 3)
        key = vertices.tobytes()
        if key == self._volume_key and self._volume_manifold is not None:
            return dict(volume_mm3=float(self._volume_manifold.volume()),
                        _manifold=self._volume_manifold,
                        _volume_only_cache_hit=True)
        setup_started = perf_counter()
        tetra = self._tetrahedron(vertices)
        setup_ms = (perf_counter() - setup_started) * 1000.
        boolean_started = perf_counter()
        clipped = m.Manifold.batch_boolean([self.solid, tetra], m.OpType.Intersect)
        boolean_ms = (perf_counter() - boolean_started) * 1000.
        status_started = perf_counter()
        if clipped.status() != m.Error.NoError:
            raise ValueError(f'肺与四面体布尔交集失败：{clipped.status()}')
        status_ms = (perf_counter() - status_started) * 1000.
        volume_started = perf_counter()
        volume_mm3 = float(clipped.volume())
        volume_ms = (perf_counter() - volume_started) * 1000.
        self._volume_key = key
        self._volume_manifold = clipped
        self._volume_tetra_original_id = tetra.original_id()
        self._volume_timings_ms = dict(cache_hit=False, volume_only=True,
            tetra_solid_setup_ms=setup_ms, boolean_kernel_ms=boolean_ms,
            boolean_status_ms=status_ms, volume_eval_ms=volume_ms,
            total_ms=(perf_counter() - total_started) * 1000.)
        return dict(volume_mm3=volume_mm3, _manifold=clipped,
                    _volume_only_cache_hit=False)

    def preview_surfaces(self, vertices):
        """Return exact in-lung and cut-face meshes without metric reductions."""
        m = _library()
        vertices = np.asarray(vertices, dtype=np.float64).reshape(4, 3)
        tetra = self._tetrahedron(vertices)
        clipped = m.Manifold.batch_boolean([self.solid, tetra], m.OpType.Intersect)
        tetra_original_id = tetra.original_id()
        if clipped.status() != m.Error.NoError:
            raise ValueError(f'肺与四面体布尔交集失败：{clipped.status()}')
        mesh = clipped.to_mesh64()
        triangles = np.asarray(mesh.vert_properties)[:, :3][np.asarray(mesh.tri_verts)].copy()
        is_cut = np.zeros(len(triangles), dtype=bool)
        is_lung = np.zeros(len(triangles), dtype=bool)
        runs = np.asarray(mesh.run_index) // 3
        for start, stop, original in zip(runs[:-1], runs[1:], mesh.run_original_id):
            if original == tetra_original_id:
                is_cut[int(start):int(stop)] = True
            elif original == self.solid.original_id():
                is_lung[int(start):int(stop)] = True
            else:
                raise ValueError('布尔交集表面来源不明')
        if not np.all(is_cut | is_lung):
            raise ValueError('布尔交集缺少表面来源')
        return _stable_triangle_order(triangles[is_lung]), _stable_triangle_order(triangles[is_cut])

    def intersect_dual_plane_pl_reference(self, vertices, *, return_surface=False,
                                          authoritative=True, strict_independent=False):
        """Float64 golden model for the dual-plane mesh accelerator.

        The method is intentionally separate from ``intersect`` so callers
        can compare the PL candidate result against Manifold before allowing
        it into the planning ranking.  It consumes the resident normalized
        union triangles and performs no decimation or sampling.
        """
        from .dual_plane_reference import (clip_mesh_by_tetra,
                                           manifold_volume_metrics)
        if authoritative:
            result = manifold_volume_metrics(self.solid, vertices)
        else:
            result = clip_mesh_by_tetra(self.triangles, vertices,
                                        return_surface=return_surface,
                                        strict_independent=strict_independent)
        result['backend'] = 'PS float64 dual-plane mesh reference'
        result['source_triangle_count'] = int(len(self.triangles))
        return result

    @staticmethod
    def _cache_file(meshes, labels, cache_dir):
        if cache_dir is None:
            return None
        digest = hashlib.sha256(b'lung-union-cache-v1')
        for mesh, label in zip(meshes, labels):
            values = np.ascontiguousarray(mesh, dtype='<f8')
            digest.update(str(label).encode('utf-8'))
            digest.update(np.asarray(values.shape, dtype='<u8').tobytes())
            digest.update(values.tobytes())
        return Path(cache_dir) / (digest.hexdigest() + '.npz')

    def intersect(self, vertices):
        """Return volume and the two disjoint source-face classes, in mm."""
        total_started = perf_counter()
        m = _library()
        vertices = np.asarray(vertices, dtype=np.float64).reshape(4, 3)
        key = vertices.tobytes()
        if key == self._last_key:
            self._last_timings_ms = dict(cache_hit=True, total_ms=(perf_counter()-total_started)*1000.)
            return self._last
        volume_cache_hit = key == self._volume_key and self._volume_manifold is not None
        if volume_cache_hit:
            clipped = self._volume_manifold
            tetra_original_id = self._volume_tetra_original_id
            setup_ms = 0.
            boolean_ms = 0.
        else:
            setup_started = perf_counter()
            tetra = self._tetrahedron(vertices)
            setup_ms = (perf_counter()-setup_started)*1000.
            boolean_started = perf_counter()
            clipped = m.Manifold.batch_boolean([self.solid, tetra], m.OpType.Intersect)
            tetra_original_id = tetra.original_id()
            boolean_ms = (perf_counter()-boolean_started)*1000.
        status_started = perf_counter()
        if clipped.status() != m.Error.NoError:
            raise ValueError(f'肺与四面体布尔交集失败：{clipped.status()}')
        status_ms = (perf_counter()-status_started)*1000.
        extraction_started = perf_counter()
        mesh_convert_started = perf_counter()
        mesh = clipped.to_mesh64()
        mesh_convert_ms = (perf_counter()-mesh_convert_started)*1000.
        triangles = np.asarray(mesh.vert_properties)[:, :3][np.asarray(mesh.tri_verts)].copy()
        is_cut = np.zeros(len(triangles), dtype=bool)
        is_lung = np.zeros(len(triangles), dtype=bool)
        runs = np.asarray(mesh.run_index) // 3
        for start, stop, original in zip(runs[:-1], runs[1:], mesh.run_original_id):
            if original == tetra_original_id:
                is_cut[int(start):int(stop)] = True
            elif original == self.solid.original_id():
                is_lung[int(start):int(stop)] = True
            else:
                raise ValueError('布尔交集表面来源不明')
        if not np.all(is_cut | is_lung):
            raise ValueError('布尔交集缺少表面来源')
        extraction_ms = (perf_counter()-extraction_started)*1000.
        cut = _stable_triangle_order(triangles[is_cut])
        surface = _stable_triangle_order(triangles[is_lung])
        reduction_started = perf_counter()
        volume_started = perf_counter()
        volume_mm3 = float(clipped.volume())
        volume_eval_ms = (perf_counter()-volume_started)*1000.
        area_started = perf_counter()
        surface_area_mm2 = _area(surface)
        surface_area_ms = (perf_counter()-area_started)*1000.
        cut_area_started = perf_counter()
        cut_area_mm2 = _area(cut)
        cut_area_ms = (perf_counter()-cut_area_started)*1000.
        reduction_ms = (perf_counter()-reduction_started)*1000.
        self._last_key = key
        self._last = dict(volume_mm3=volume_mm3, surface=surface, interior=cut,
                          surface_area_mm2=surface_area_mm2, cut_area_mm2=cut_area_mm2,
                          _manifold=clipped)
        self._last_timings_ms = dict(cache_hit=False, tetra_solid_setup_ms=setup_ms,
            boolean_kernel_ms=boolean_ms,
            boolean_status_ms=status_ms, mesh_convert_ms=mesh_convert_ms,
            triangle_extract_classify_ms=extraction_ms, area_volume_reduce_ms=reduction_ms,
            volume_eval_ms=volume_eval_ms, surface_area_reduce_ms=surface_area_ms,
            cut_area_reduce_ms=cut_area_ms,
            output_triangles=len(triangles), lung_surface_triangles=len(surface),
            cut_surface_triangles=len(cut), total_ms=(perf_counter()-total_started)*1000.)
        return self._last
