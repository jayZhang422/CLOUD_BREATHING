"""NumPy implementation of the prototype's geometry in CT physical mm.

Coverage/clearance use all triangle vertices of the largest lesion component.
Automatic search adapts to lesion location and fits a safety envelope. Surface
area and CPU resection volume use a float64 Boolean lung-union intersection when
closed solids are available; PL keeps its deterministic ray integration path.

STL coordinates are source-space voxel coordinates. ``ct_spacing`` is supplied
by the loaded DICOM study; all distance, area, volume, and PL calculations use
the resulting physical-mm coordinates, while exported/display geometry is
converted back to source space.
"""
from pathlib import Path
from dataclasses import dataclass
from time import perf_counter
import math
import logging
import os

import numpy as np
from .planning_constraints import (base_clearance, separate_constraints,
                                   cut_plane_margin, constraint_report)

from . import planner_reference as ref
from .ray_golden import collapse_crossings, inside_from_crossings, volume_fraction
from .mesh_bvh import build_mesh_image
from .mesh_triangle import closest_point_on_mesh, mesh_is_watertight, triangle_mesh_min_distance, unique_rows
from .mesh_cpu import CpuMeshIndex, union_crossings
from .mesh_union import LungUnion
from .ray_batch import (RayTriangleInput, input_pairs,
                        validate_result_records)
from .planning_inputs import anatomical_lung_side
from .pl_telemetry import PlTelemetry
from .surface_clip import clipped_surface


def _ordered_mesh_volume(triangles):
    """Same per-triangle FP64 expression and sequential sum as the reference."""
    a, b, c = triangles[:, 0], triangles[:, 1], triangles[:, 2]
    cross_x = b[:, 1] * c[:, 2] - b[:, 2] * c[:, 1]
    cross_y = b[:, 2] * c[:, 0] - b[:, 0] * c[:, 2]
    cross_z = b[:, 0] * c[:, 1] - b[:, 1] * c[:, 0]
    terms = ((a[:, 0] * cross_x + a[:, 1] * cross_y) + a[:, 2] * cross_z) / 6.0
    return float(abs(np.add.accumulate(terms)[-1])) if len(terms) else 0.0


@dataclass(frozen=True)
class _BaseValidation:
    signature: tuple
    result: tuple


class PlanningCase:
    def __init__(self, directory, lung_files, tumor_file, mirror=False, mirror_plane=None,
                 ray_evaluator=None, mesh_evaluator=None, ray_mode=None, strict_pl=False, distance_evaluator=None,
                 tumor_triangles=None, ct_spacing=None, whole_lung_files=None):
        self._strict_pl = strict_pl
        self._pl_telemetry = PlTelemetry()
        self._validation_stats = {}
        self._validation_identity = object()
        self._distance_evaluator = distance_evaluator
        self._distance_stats = dict(calls=0,points=0,job_ms=0.,service_ms=0.,cycles=0,
                                    mesh_uploads=0,dma_buffer_reuses=0)
        root = Path(directory)
        spacing = np.asarray(ct_spacing if ct_spacing is not None else (1., 1., 1.), dtype=np.float64)
        if spacing.shape != (3,) or not np.isfinite(spacing).all() or np.any(spacing <= 0):
            raise ValueError('CT 标尺无效：需要三个正的物理间距')
        self.ct_spacing = spacing
        load_started = perf_counter()
        target_lung_files = list(lung_files)
        whole_lung_files = list(dict.fromkeys(whole_lung_files or target_lung_files))
        raw_meshes = {}
        for name in dict.fromkeys(target_lung_files + whole_lung_files):
            raw_meshes[name] = ref.read_stl_array(root / name)
        meshes = [raw_meshes[name] for name in target_lung_files]
        tumor = (list(tumor_triangles) if tumor_triangles is not None else
                 ref.largest_component(ref.read_stl(root / tumor_file)))
        if not meshes or any(len(mesh) == 0 for mesh in meshes) or not tumor:
            raise ValueError('肺或最大连通病灶 STL 为空')
        # Scale each source once in FP64. Target, whole and surgical unions
        # reuse these arrays without changing triangle or reduction order.
        scaled_meshes = {name: mesh * spacing for name, mesh in raw_meshes.items()}
        meshes = [scaled_meshes[name] for name in target_lung_files]
        whole_meshes = [scaled_meshes[name] for name in whole_lung_files]
        tumor_array = np.asarray([t.points for t in tumor], dtype=np.float64) * spacing
        tumor = [ref.Triangle(*map(tuple, tri)) for tri in tumor_array]
        self.tumor_triangles = tumor
        self.target_lung_files = list(target_lung_files)
        self.whole_lung_files = list(whole_lung_files)
        self.load_timings_ms = {'stl_parse': (perf_counter() - load_started) * 1000.}
        self.points = np.asarray(ref.all_points(tumor), dtype=np.float64)
        triangles = np.concatenate(meshes, axis=0)
        self.lung_volume = sum(_ordered_mesh_volume(mesh) for mesh in meshes)
        self.whole_lung_volume = sum(_ordered_mesh_volume(mesh) for mesh in whole_meshes)
        self.triangles = np.asarray(triangles, dtype=np.float64)
        self._triangle_groups = np.repeat(np.arange(len(meshes)), [len(mesh) for mesh in meshes])
        self._group_count = len(meshes)
        if not np.isfinite(self.triangles).all() or not np.isfinite(self.points).all():
            raise ValueError('STL 含非有限坐标')
        self.mirror_x = None
        if mirror:
            both = np.concatenate((self.triangles.reshape(-1, 3), self.points))
            # Match the reference bounds, including discarded tumor fragments.
            entire_tumor = np.asarray(ref.all_points(ref.read_stl(root / tumor_file)))
            both = np.concatenate((both, entire_tumor))
            self.mirror_x = float((both[:, 0].min() + both[:, 0].max()) / 2)
            if mirror_plane is not None:
                self.mirror_x = float(mirror_plane)
            self.triangles[:, :, 0] = 2 * self.mirror_x - self.triangles[:, :, 0]
        if strict_pl:
            from .frozen_mesh import FrozenMesh
            self._mesh_resource = FrozenMesh(self.triangles, self._triangle_groups)
            self.triangles = self._mesh_resource.triangles
            self._triangle_groups = self._mesh_resource.solid_ids
        self.lung = [ref.Triangle(*map(tuple, t)) for t in self.triangles]
        self.mesh_image = None
        try:
            if ray_mode != 'cpu':
                self.mesh_image = build_mesh_image(self.triangles, solid_ids=self._triangle_groups)
            if self.mesh_image is not None:
                self.load_timings_ms.update(bvh_build=self.mesh_image.build_ms,
                                            mesh_pack=self.mesh_image.pack_ms)
        except ValueError as exc:
            if strict_pl:
                raise RuntimeError('PL mesh preparation failed: ' + str(exc)) from exc
            # CPU geometry remains usable when the fixed-point ABI cannot
            # represent a case; the PL client will report its own failure.
            self.load_timings_ms.update(bvh_build=0., mesh_pack=0.)
            logging.getLogger(__name__).warning('PL_BVH_CPU_FALLBACK %s', exc)
        self.a = self.triangles[:, 0]
        self.e1 = self.triangles[:, 1] - self.a
        self.e2 = self.triangles[:, 2] - self.a
        # Mesh invariants are reused by the many base samples checked during
        # automatic search. Recomputing them for every sample is costly on ARM.
        self._normal = np.cross(self.e1, self.e2)
        self._n2 = np.einsum('ij,ij->i', self._normal, self._normal)
        self._d00 = np.einsum('ij,ij->i', self.e1, self.e1)
        self._d01 = np.einsum('ij,ij->i', self.e1, self.e2)
        self._d11 = np.einsum('ij,ij->i', self.e2, self.e2)
        self._edge = np.stack((self.e1, self.e2 - self.e1, -self.e2), axis=1)
        self._edge_len2 = np.einsum('tki,tki->tk', self._edge, self._edge)
        self._triangle_min = self.triangles.min(axis=1)
        self._triangle_max = self.triangles.max(axis=1)
        # Each selected STL is a solid. Shared segment interfaces need not
        # make the concatenated triangle soup a two-face-per-edge manifold.
        self._lung_watertight = all(mesh_is_watertight(mesh) for mesh in meshes)
        self._lung_union = None
        # The planning boundary follows the STL(s) containing the selected
        # lesion. The broader same-side union is context for display/contact;
        # resection and branch analysis must stay clipped to this boundary.
        self._planning_lung_union = None
        self._whole_lung_union = None
        self._surgical_lung_union = None
        self._display_contact_meshes = {}
        # The strict legacy-tetra path owns all quantitative geometry in PL and
        # deliberately avoids constructing a PS Boolean union.  The dual-plane
        # PL path is different: PL only prefilters half-space candidates while
        # the authoritative surface/volume result still comes from the exact
        # Manifold union, so bvh_pl must not suppress these unions.
        if not strict_pl:
            # The three PS quantitative values are defined on the geometric
            # union.  A per-file sum or clipped input triangles would count
            # shared/internal interfaces again, so never silently substitute
            # that approximation when an input solid is open.
            if not self._lung_watertight:
                raise ValueError('纯 PS 三项量化需要所有肺 STL 都是闭合实体；'
                                 '当前存在开放网格，无法可靠计算并集总体积、肺外表面积和新切除面面积')
            union_started = perf_counter()
            self._lung_union = LungUnion(
                [mesh for mesh in meshes], lung_files,
                cache_dir=root / '.cloud_breathing_union_cache')
            self._planning_lung_union = self._lung_union
            self.lung_volume = self._lung_union.volume_mm3
            self.load_timings_ms['lung_union'] = (perf_counter() - union_started) * 1000.
            self.load_timings_ms['lung_union_cache_hit'] = bool(self._lung_union.cache_hit)
            if whole_lung_files == target_lung_files:
                self._whole_lung_union = self._lung_union
                self.whole_lung_volume = self.lung_volume
                self.load_timings_ms['whole_lung_union_cache_hit'] = bool(self._lung_union.cache_hit)
            else:
                whole_union_started = perf_counter()
                if not all(mesh_is_watertight(mesh)
                           for mesh in whole_meshes):
                    raise ValueError('整肺双侧量化需要所有肺 STL 都是闭合实体')
                self._whole_lung_union = LungUnion(
                    [mesh for mesh in whole_meshes], whole_lung_files,
                    cache_dir=root / '.cloud_breathing_union_cache')
                self.whole_lung_volume = self._whole_lung_union.volume_mm3
                self.load_timings_ms['whole_lung_union'] = (perf_counter() - whole_union_started) * 1000.
                self.load_timings_ms['whole_lung_union_cache_hit'] = bool(self._whole_lung_union.cache_hit)
            target_sides = {anatomical_lung_side(name) for name in target_lung_files}
            target_sides.discard(None)
            side_files = [name for name in whole_lung_files
                          if anatomical_lung_side(name) in target_sides]
            contact_files = (side_files if side_files else whole_lung_files)
            self._display_contact_meshes = {
                name: scaled_meshes[name] for name in contact_files
                if name not in target_lung_files and len(scaled_meshes[name])}
            if side_files and set(side_files) != set(target_lung_files):
                side_meshes = [scaled_meshes[name] for name in side_files]
                side_union_started = perf_counter()
                self._surgical_lung_union = LungUnion(
                    side_meshes, side_files,
                    cache_dir=root / '.cloud_breathing_union_cache')
                self.load_timings_ms['surgical_lung_union'] = (perf_counter() - side_union_started) * 1000.
                self.load_timings_ms['surgical_lung_union_cache_hit'] = bool(self._surgical_lung_union.cache_hit)
                self.surgical_lung_files = side_files
            else:
                self._surgical_lung_union = self._lung_union
                self.surgical_lung_files = list(target_lung_files)

        self._target_side_origin = None
        self._target_side_normal = None
        side_centers = {'left': [], 'right': []}
        for name, mesh in zip(lung_files, meshes):
            side = anatomical_lung_side(name)
            if side:
                points = mesh.reshape(-1, 3)
                side_centers[side].append(points.mean(axis=0))
        if side_centers['left'] and side_centers['right']:
            left_center = np.mean(side_centers['left'], axis=0)
            right_center = np.mean(side_centers['right'], axis=0)
            separation = left_center - right_center
            separation_length = float(np.linalg.norm(separation))
            if separation_length > 1e-6:
                normal = separation / separation_length
                origin = (left_center + right_center) * .5
                lesion_side = float(np.dot(self.points.mean(axis=0) - origin, normal))
                if abs(lesion_side) >= 10.:
                    self._target_side_origin = origin
                    self._target_side_normal = normal * (1. if lesion_side > 0. else -1.)
        self._cpu_index = None
        if ray_mode == 'cpu':
            index_started = perf_counter()
            self._cpu_index = CpuMeshIndex(self.triangles, self._triangle_groups)
            self.load_timings_ms['cpu_index_build'] = (perf_counter() - index_started) * 1000.
        self._fit_points = unique_rows(self.points)[0]
        self.center = self._fit_points.mean(axis=0)
        self._base_gap_cache = {}
        self.alternatives = []
        self.lung_files = list(lung_files)
        self.tumor_file = tumor_file
        self.sources = {name: (root / name).stat().st_mtime_ns
                        for name in self.lung_files + [tumor_file]}

        # The first ray RTL exposes a PS-streamed ray/triangle ABI. Keep the
        # backend optional so the same geometry remains usable on a PC and so
        # large bulk jobs can stay on NumPy until a data-resident mesh kernel
        # is available.
        mode = ray_mode or os.environ.get('LUNG_PL_RAY_MODE', 'auto').strip().lower()
        if strict_pl and (mode != 'bvh_pl' or mesh_evaluator is None):
            raise RuntimeError('Strict PL requires the BVH mesh evaluator')
        self._ray_evaluator = ray_evaluator if mode not in ('cpu', '0', 'off', 'false', 'no') else None
        self._mesh_evaluator = mesh_evaluator if mode not in ('cpu', 'ray_pl', '0', 'off', 'false', 'no') else None
        self._ray_mode = mode
        self._ray_disabled = False
        self._mesh_disabled = False
        self._ray_error = ''
        self._mesh_error = ''
        self._ray_sequence = 0
        self._ray_cache = {}
        self._surface_hit_cache = {}
        self._ray_cache_limit = max(0, int(os.environ.get('LUNG_PL_RAY_CACHE', '256')))
        self._ray_chunk_records = max(1, int(os.environ.get('LUNG_PL_RAY_CHUNK_RECORDS', '4096')))
        self._ray_bulk_limit = max(self._ray_chunk_records,
                                   int(os.environ.get('LUNG_PL_RAY_BULK_RECORDS', '65536')))
        self._ray_stats = dict(calls=0, records=0, hits=0, job_ms=0.0,
                               service_ms=0.0, cycles=0, skipped_records=0)
        self._mesh_stats = dict(calls=0, rays=0, hits=0, job_ms=0.0,
                                service_ms=0.0, cycles=0, abi=None,
                                solid_count=0, union_events=0, union_boundaries=0,
                                mesh_uploads=0, dma_buffer_reuses=0)

    def to_physical_vertices(self, vertices):
        return np.asarray(vertices, dtype=np.float64) * self.ct_spacing

    def to_source_vertices(self, vertices):
        return np.asarray(vertices, dtype=np.float64) / self.ct_spacing

    def to_source_points(self, points):
        return np.asarray(points, dtype=np.float64) / self.ct_spacing

    @staticmethod
    def _angles_for_direction(direction):
        direction = np.asarray(direction, dtype=np.float64)
        direction /= max(float(np.linalg.norm(direction)), 1e-12)
        # Invert direction_for, choosing the representation with |pitch|<=90.
        z_before_pitch = math.copysign(math.hypot(direction[1], direction[2]), direction[2])
        initial = ref.direction_for(0., 0.)
        yaw = math.degrees(math.atan2(initial[2], initial[0]) -
                           math.atan2(z_before_pitch, direction[0]))
        pitch = math.degrees(math.atan2(-direction[1] / z_before_pitch,
                                      direction[2] / z_before_pitch)) if abs(z_before_pitch) > 1e-12 else 0.
        return (yaw + 180.) % 360. - 180., pitch

    def _candidate_directions(self):
        # Center the search on the nearest lung-to-lesion direction, then fan
        # out in a deterministic cone so cases at different lung locations
        # receive different candidate corridors.
        lesion_point = self.center
        surface_point, _ = closest_point_on_mesh(lesion_point, self.triangles)
        axis = surface_point - lesion_point
        length = float(np.linalg.norm(axis))
        if length <= 1e-8:
            axis = self.center - self.triangles.mean(axis=(0, 1))
            length = float(np.linalg.norm(axis))
        if length <= 1e-8:
            axis = np.asarray(ref.direction_for(-34., -44.))
        else:
            axis /= length
        u, v = map(np.asarray, ref.basis(tuple(axis)))
        directions = [axis]
        for polar in (15., 30., 45., 60.):
            theta = math.radians(polar)
            for azimuth in range(0, 360, 60):
                phi = math.radians(azimuth)
                direction = (axis * math.cos(theta) +
                             (u * math.cos(phi) + v * math.sin(phi)) * math.sin(theta))
                directions.append(direction / np.linalg.norm(direction))
        # Global coverage avoids restricting a new case to the nearest patch.
        for i in range(24):
            z = 1. - 2. * (i + .5) / 24.
            phi = i * math.pi * (3. - math.sqrt(5.))
            radius = math.sqrt(1. - z * z)
            directions.append(np.asarray((radius * math.cos(phi), radius * math.sin(phi), z)))
        unique = {}
        for direction in directions:
            yaw, pitch = self._angles_for_direction(direction)
            key = (round(yaw, 5), round(pitch, 5))
            unique[key] = (yaw, pitch)
        return [unique[key] for key in sorted(unique)]

    def ray_summary(self):
        """Return JSON-friendly ray backend diagnostics for the planner UI/log."""
        stats = dict(self._ray_stats)
        mesh_stats = self._mesh_stats
        mesh_calls = mesh_stats.get('calls', 0)
        attempted = stats['calls'] > 0 or mesh_calls > 0 or self._mesh_disabled
        if attempted and self._mesh_disabled:
            backend = 'FPGA PL mesh-resident ray failed; CPU / NumPy fallback'
        elif attempted and self._ray_disabled:
            backend = 'FPGA PL ray_batch failed; CPU / NumPy fallback'
        elif mesh_calls and getattr(self, '_strict_pl', False):
            backend = 'FPGA PL DDR/BVH (strict)'
        elif mesh_calls and not self._mesh_disabled:
            backend = 'FPGA PL mesh-resident ray + CPU / NumPy'
        elif attempted and stats['skipped_records']:
            backend = 'FPGA PL ray_batch + CPU / NumPy bulk fallback'
        elif attempted:
            backend = 'FPGA PL ray_batch'
        else:
            backend = 'CPU / NumPy'
        return dict(ray_backend=backend, ray_mode=self._ray_mode,
                    ray_pl_calls=stats['calls'], ray_pl_records=stats['records'],
                    ray_pl_hits=stats['hits'], ray_pl_job_ms=stats['job_ms'],
                    ray_pl_service_ms=stats['service_ms'], ray_pl_cycles=stats['cycles'],
                    ray_cpu_skipped_records=stats['skipped_records'],
                    ray_error=self._ray_error or self._mesh_error or None,
                    mesh_pl_calls=mesh_calls,
                    mesh_pl_rays=mesh_stats.get('rays', 0),
                    mesh_pl_hits=mesh_stats.get('hits', 0),
                    mesh_pl_job_ms=mesh_stats.get('job_ms', 0.0),
                    mesh_pl_service_ms=mesh_stats.get('service_ms', 0.0),
                    mesh_pl_cycles=mesh_stats.get('cycles', 0),
                    mesh_pl_abi=mesh_stats.get('abi'),
                    mesh_pl_solid_count=mesh_stats.get('solid_count', 0),
                    mesh_pl_union_events=mesh_stats.get('union_events', 0),
                    mesh_pl_union_boundaries=mesh_stats.get('union_boundaries', 0))

    @staticmethod
    def _ray_key(point, direction):
        # Match the Q16.16 wire representation, so cache keys describe the
        # actual hardware request rather than insignificant Python float noise.
        values = tuple(int(round(float(value) * 65536.0))
                       for value in (*np.asarray(point).reshape(3),
                                     *np.asarray(direction).reshape(3)))
        return values

    def _record_ray_stats(self, response):
        self._ray_stats['hits'] += int(response.get('hits', 0))
        self._ray_stats['job_ms'] += float(response.get('job_ms', 0.0) or 0.0)
        self._ray_stats['service_ms'] += float(response.get('service_ms', 0.0) or 0.0)
        self._ray_stats['cycles'] += int(response.get('cycles', 0) or 0)

    def _ray_hits_many(self, points, directions, *, force=False, allow_pl=True,
                       require_complete=False, lengths=None):
        """Return crossings per ray, or ``None`` for CPU fallback.

        The bvh_pl mode returns complete sorted/merged crossings.
        Legacy summary overlays remain available for diagnostics; they cannot
        satisfy require_complete and callers keep the CPU fallback.
        """
        strict = getattr(self, '_strict_pl', False)
        if strict and (not allow_pl or self._mesh_evaluator is None or self._mesh_disabled):
            raise RuntimeError('PL ray calculation is required; CPU fallback is forbidden')
        if not allow_pl:
            return None
        points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
        directions = np.asarray(directions, dtype=np.float64).reshape(-1, 3)
        if len(points) != len(directions):
            raise ValueError('ray point/direction count mismatch')
        if not len(points):
            return []
        total_records = len(points) * len(self.triangles)

        # Explicit bvh_pl enables complete requests after board validation.
        if self._mesh_evaluator is not None and not self._mesh_disabled and (not require_complete or getattr(self, '_ray_mode', '') == 'bvh_pl'):
            try:
                kwargs = {'lengths': lengths} if lengths is not None else {}
                groups = getattr(self, '_triangle_groups', None)
                if groups is not None:
                    kwargs['solid_ids'] = groups
                request_started = perf_counter()
                response = self._mesh_evaluator(self.triangles, points, directions, **kwargs)
                if hasattr(self, '_pl_telemetry'):
                    self._pl_telemetry.record('volume' if lengths is not None else 'ray',
                        getattr(self, '_request_context', 'geometry'), len(points), response or {},
                        (perf_counter() - request_started) * 1000.)
                if response and response.get('ok'):
                    values = response.get('results', [])
                    if len(values) != len(points):
                        raise RuntimeError('mesh ray returned %d/%d results' % (len(values), len(points)))
                    self._mesh_stats['calls'] += 1
                    self._mesh_stats['rays'] += len(points)
                    self._mesh_stats['hits'] += sum(int(item.get('hit_count', 0)) for item in values)
                    self._mesh_stats['job_ms'] += float(response.get('job_ms', 0.) or 0.)
                    self._mesh_stats['service_ms'] += float(response.get('service_ms', 0.) or 0.)
                    if response.get('mesh_reused') is False:
                        self._mesh_stats['mesh_uploads'] = self._mesh_stats.get('mesh_uploads', 0) + 1
                    self._mesh_stats['dma_buffer_reuses'] = self._mesh_stats.get('dma_buffer_reuses', 0) + int(bool(response.get('dma_buffer_reused')))
                    self._mesh_stats['cycles'] += int(response.get('cycles', 0) or 0)
                    self._mesh_stats['abi'] = response.get('abi') or self._mesh_stats.get('abi')
                    self._mesh_stats['solid_count'] = max(self._mesh_stats.get('solid_count', 0),
                                                          int(response.get('solid_count', 0) or 0))
                    self._mesh_stats['union_events'] = self._mesh_stats.get('union_events', 0) + int(response.get('union_event_count', 0) or 0)
                    self._mesh_stats['union_boundaries'] = self._mesh_stats.get('union_boundaries', 0) + int(response.get('union_boundary_count', 0) or 0)
                    if response.get('complete_crossings'):
                        if any(int(item.get('errors', 0)) for item in values):
                            raise RuntimeError('complete crossing result contains hardware errors')
                        if strict:
                            self._last_mesh_inside = np.asarray([item['inside'] for item in values], dtype=bool)
                        if lengths is not None:
                            mean = response.get('volume_mean_q30')
                            count = response.get('volume_valid_rays')
                            if (not response.get('pl_volume') or count != len(points)
                                    or not isinstance(mean, int) or not 0 <= mean <= (1 << 30)):
                                raise RuntimeError('PL volume (ray integral) result is required')
                            self._last_volume_mean = mean / float(1 << 30)
                        return [np.asarray(item['crossings_q16'], dtype=np.float64)/65536. for item in values]
                    if strict:
                        raise RuntimeError('Complete crossing ABI is required')
                    if require_complete:
                        return None
                    output = []
                    for item in values:
                        count = int(item.get('hit_count', 0))
                        near = float(item.get('t_near_q16', 0)) / 65536. if 't_near_q16' in item else float(item.get('t_near_mm', 0.))
                        far = float(item.get('t_far_q16', 0)) / 65536. if 't_far_q16' in item else float(item.get('t_far_mm', 0.))
                        if count <= 0:
                            output.append(np.empty(0, dtype=np.float64))
                        elif count == 1 or abs(far - near) <= 1.e-5:
                            output.append(np.asarray([near], dtype=np.float64))
                        else:
                            output.append(np.asarray([near, far], dtype=np.float64))
                    return output
                raise RuntimeError((response or {}).get('error', 'mesh ray PL service failed'))
            except Exception as exc:
                if strict:
                    raise RuntimeError('PL ray calculation failed (no CPU fallback): ' + str(exc)) from exc
                self._mesh_disabled = True
                self._mesh_error = str(exc)
                logging.getLogger(__name__).warning('PL_MESH_GEOMETRY_FALLBACK %s', exc)

        if strict:
            raise RuntimeError('PL ray path unavailable; CPU fallback is forbidden')
        if self._ray_evaluator is None or self._ray_disabled:
            return None
        if not force and self._ray_mode != 'pl' and total_records > self._ray_bulk_limit:
            self._ray_stats['skipped_records'] += total_records
            return None

        self._ray_sequence = (self._ray_sequence + 1) & 0x7FFFFFFF or 1
        ray_ids = [self._ray_sequence + index for index in range(len(points))]
        collected = [[] for _ in points]
        pending = []

        def flush():
            if not pending:
                return
            self._ray_stats['calls'] += 1
            self._ray_stats['records'] += len(pending)
            records = b''.join(pending)
            response = self._ray_evaluator(records, len(pending))
            if not response or not response.get('ok'):
                raise RuntimeError((response or {}).get('error', 'ray PL service failed'))
            results = validate_result_records(
                response.get('results', []), input_pairs(records, len(pending)),
                response.get('errors', 0))
            self._record_ray_stats(response)
            by_id = {ray_id: index for index, ray_id in enumerate(ray_ids)}
            for item in results:
                if item.ray_id not in by_id:
                    raise RuntimeError('ray PL returned an unknown ray id')
                if item.hit:
                    collected[by_id[item.ray_id]].append(item)
            pending.clear()

        try:
            for ray_index, (point, direction) in enumerate(zip(points, directions)):
                for triangle_index, triangle in enumerate(self.triangles):
                    pending.append(RayTriangleInput(
                        ray_ids[ray_index], triangle_index, point, direction, triangle).pack())
                    if len(pending) >= self._ray_chunk_records:
                        flush()
            flush()
            return [collapse_crossings([hit.t_mm for hit in items]) for items in collected]
        except Exception as exc:
            self._ray_disabled = True
            self._ray_error = str(exc)
            logging.getLogger(__name__).warning('PL_RAY_GEOMETRY_FALLBACK %s', exc)
            return None

    def _hits_cpu(self, point, direction):
        if getattr(self, '_strict_pl', False):
            raise RuntimeError('CPU ray intersection forbidden in PL mode')
        if getattr(self, '_cpu_index', None) is not None:
            return self._cpu_index.hits(point, direction)
        h = np.cross(direction, self.e2)
        det = np.einsum('ij,ij->i', self.e1, h)
        inv = np.divide(1.0, det, out=np.zeros_like(det), where=np.abs(det) >= 1e-9)
        s = np.asarray(point) - self.a
        u = inv * np.einsum('ij,ij->i', s, h)
        q = np.cross(s, self.e1)
        v = inv * (q @ np.asarray(direction))
        t = inv * np.einsum('ij,ij->i', self.e2, q)
        mask = ((np.abs(det) >= 1e-9) & (u >= -1e-7) & (u <= 1.0000001)
                & (v >= -1e-7) & (u + v <= 1.0000001) & (t >= 0))
        if getattr(self, '_group_count', 1) > 1:
            return union_crossings(t[mask], self._triangle_groups[mask], self._group_count)
        return collapse_crossings(t[mask])

    def hits(self, point, direction, *, allow_pl=True):
        key = self._ray_key(point, direction)
        if allow_pl and not getattr(self, '_strict_pl', False) and key in self._ray_cache:
            return self._ray_cache[key].copy()
        values = self._ray_hits_many([point], [direction], force=True,
                                     allow_pl=allow_pl, require_complete=True)
        result = self._hits_cpu(point, direction) if values is None else values[0]
        if self._ray_evaluator is not None and not self._ray_disabled and self._ray_cache_limit:
            if len(self._ray_cache) >= self._ray_cache_limit:
                self._ray_cache.pop(next(iter(self._ray_cache)))
            self._ray_cache[key] = np.asarray(result, dtype=np.float64).copy()
        return np.asarray(result, dtype=np.float64)

    def inside(self, point, *, allow_pl=True):
        direction = np.asarray(ref.unit((1.0, .371, .217)))
        if getattr(self, '_strict_pl', False):
            self.hits(np.asarray(point) + direction * 1e-5, direction, allow_pl=allow_pl)
            return bool(self._last_mesh_inside[0])
        return inside_from_crossings(self.hits(np.asarray(point) + direction * 1e-5, direction,
                                               allow_pl=allow_pl))

    def surface_hit(self, point, direction, *, allow_pl=True):
        cache = None
        if getattr(self, '_strict_pl', False) and allow_pl:
            cache = getattr(self, '_surface_hit_cache', None)
            if cache is None:
                cache = self._surface_hit_cache = {}
            key = (np.asarray(point, dtype=np.float64).tobytes(),
                   np.asarray(direction, dtype=np.float64).tobytes())
            if key in cache:
                return np.asarray(point) + np.asarray(direction) * cache[key]
        hits = self.hits(point, direction, allow_pl=allow_pl)
        if not len(hits):
            raise ValueError('当前方向未找到肺表面入口；请检查 STL 坐标或调整方向')
        if cache is not None:
            if len(cache) >= 256:
                cache.pop(next(iter(cache)))
            cache[key] = float(hits[0])
        return np.asarray(point) + np.asarray(direction) * hits[0]

    def distance(self, point):
        """Exact minimum point-to-triangle distance, including edge regions."""
        if getattr(self, '_strict_pl', False):
            return float(self._distance_many([point])[0])
        if getattr(self, '_cpu_index', None) is not None:
            return self._cpu_index.distance(point)
        p = np.asarray(point)
        ap = p - self.a
        signed = np.einsum('ij,ij->i', ap, self._normal)
        proj = ap - self._normal * np.divide(signed, self._n2,
                                              out=np.zeros_like(signed),
                                              where=self._n2 > 1e-20)[:, None]
        d00, d01, d11 = self._d00, self._d01, self._d11
        d20 = np.einsum('ij,ij->i', proj, self.e1)
        d21 = np.einsum('ij,ij->i', proj, self.e2)
        den = d00 * d11 - d01 * d01
        inv = np.divide(1., den, out=np.zeros_like(den), where=den > 1e-20)
        u = (d11 * d20 - d01 * d21) * inv
        v = (d00 * d21 - d01 * d20) * inv
        interior = (den > 1e-20) & (u >= 0) & (v >= 0) & (u + v <= 1)
        dist2 = np.where(interior, np.divide(signed ** 2, self._n2,
                         out=np.full_like(self._n2, np.inf), where=self._n2 > 1e-20), np.inf)
        for index in range(3):
            a = self.triangles[:, index]
            edge = self._edge[:, index]
            length2 = self._edge_len2[:, index]
            t = np.clip(np.divide(np.einsum('ij,ij->i', p - a, edge), length2,
                        out=np.zeros_like(length2), where=length2 > 1e-20), 0, 1)
            delta = p - a - edge * t[:, None]
            dist2 = np.minimum(dist2, np.einsum('ij,ij->i', delta, delta))
        return float(np.sqrt(dist2.min()))

    def _inside_many_cpu(self, points):
        """Parity test for many points along the same non-axis ray."""
        if getattr(self, '_strict_pl', False):
            raise RuntimeError('CPU mesh classification forbidden in PL mode')
        points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
        direction = np.asarray(ref.unit((1.0, .371, .217)))
        if getattr(self, '_cpu_index', None) is not None:
            return np.asarray([inside_from_crossings(self._cpu_index.hits(point + direction * 1e-5, direction))
                               for point in points], dtype=bool)
        h = np.cross(direction, self.e2)
        det = np.einsum('ij,ij->i', self.e1, h)
        inv = np.divide(1.0, det, out=np.zeros_like(det), where=np.abs(det) >= 1e-9)
        output = np.empty(len(points), dtype=bool)
        chunk_size = max(1, min(32, 131072 // max(1, len(self.triangles))))
        for start in range(0, len(points), chunk_size):
            # Match inside(): offset ray origin and collapse repeated hits at
            # shared edges/faces before taking parity. Counting raw triangle
            # hits would misclassify rays on shared boundaries.
            chunk = points[start:start + chunk_size] + direction * 1e-5
            s = chunk[:, None, :] - self.a[None, :, :]
            u = inv[None, :] * np.einsum('mti,ti->mt', s, h)
            q = np.cross(s, self.e1[None, :, :])
            v = inv[None, :] * np.einsum('mti,i->mt', q, direction)
            t = inv[None, :] * np.einsum('mti,ti->mt', q, self.e2)
            mask = ((np.abs(det)[None, :] >= 1e-9) & (u >= -1e-7) & (u <= 1.0000001)
                    & (v >= -1e-7) & (u + v <= 1.0000001) & (t >= 0))
            for index in range(len(chunk)):
                hits = t[index, mask[index]]
                if getattr(self, '_group_count', 1) > 1:
                    hits = union_crossings(hits, self._triangle_groups[mask[index]], self._group_count)
                output[start + index] = inside_from_crossings(hits)
        return output

    def _inside_many(self, points):
        started = perf_counter()
        points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
        direction = np.asarray(ref.unit((1.0, .371, .217)))
        values = self._ray_hits_many(points + direction * 1e-5,
                                     np.repeat(direction[None, :], len(points), axis=0),
                                     require_complete=True)
        if values is not None and getattr(self, '_strict_pl', False):
            output = self._last_mesh_inside.copy() if len(points) else np.empty(0, dtype=bool)
        elif values is not None:
            output = np.asarray([len(hits) % 2 == 1 for hits in values], dtype=bool)
        else:
            output = self._inside_many_cpu(points)
        self._record_phase_timing('inside_many', started)
        return output

    def _distance_many(self, points, chunk_size=64):
        started = perf_counter()
        points = np.asarray(points, dtype=np.float64).reshape(-1,3)
        if not getattr(self, '_strict_pl', False):
            return self._distance_many_cpu(points, chunk_size)
        if not len(points):return np.empty(0,dtype=float)
        evaluator=getattr(self,'_distance_evaluator',None)
        if evaluator is None:raise RuntimeError('PL distance evaluator required; CPU fallback forbidden')
        request_started = perf_counter()
        response=evaluator(self.triangles,points)
        if hasattr(self, '_pl_telemetry'):
            self._pl_telemetry.record('distance', getattr(self, '_request_context', 'geometry'),
                                      len(points), response or {},
                                      (perf_counter() - request_started) * 1000.)
        if not response.get('ok') or response.get('errors',0) or not response.get('pl_distance'):
            raise RuntimeError('PL distance failed; CPU fallback forbidden: '+str(response.get('error','invalid backend')))
        rows=response.get('results',[])
        if response.get('processed')!=len(points) or response.get('distance_valid_points')!=len(points) or len(rows)!=len(points):
            raise RuntimeError('PL distance counter mismatch')
        squares=[]
        for i,row in enumerate(rows):
            if row.get('point_id')!=i+1 or row.get('errors') or not row.get('distance_valid'):
                raise RuntimeError('PL distance frame invalid')
            square=int(row['distance_squared_q32'])
            if not 0 <= square <= 3*((1<<32)-1)**2:
                raise RuntimeError('PL distance square out of range')
            squares.append(square)
        if min(squares)!=response.get('distance_min_squared_q32'):
            raise RuntimeError('PL distance batch minimum mismatch')
        self._last_distance_min_mm=math.sqrt(response['distance_min_squared_q32'])/65536.
        stats=self._distance_stats
        stats['calls']+=1;stats['points']+=len(points)
        if response.get('mesh_reused') is False:
            stats['mesh_uploads'] = stats.get('mesh_uploads', 0) + 1
        stats['dma_buffer_reuses'] = stats.get('dma_buffer_reuses', 0) + int(bool(response.get('dma_buffer_reused')))
        for key in ('job_ms','service_ms','cycles'):stats[key]+=response.get(key,0.) or 0.
        self._record_phase_timing('distance_many',started)
        return np.sqrt(np.asarray(squares,dtype=np.float64))/65536.

    def _distance_many_cpu(self, points, chunk_size=64):
        """Exact point-to-mesh distance in bounded vectorized chunks."""
        if getattr(self,'_strict_pl',False):raise RuntimeError('CPU mesh distance forbidden in PL mode')
        started = perf_counter()
        points = np.asarray(points, dtype=np.float64).reshape(-1, 3)
        if getattr(self, '_cpu_index', None) is not None:
            output = np.asarray([self._cpu_index.distance(point) for point in points])
            self._record_phase_timing('distance_many', started)
            return output
        chunk_size = max(1, min(chunk_size, 131072 // max(1, len(self.triangles))))
        output = np.empty(len(points), dtype=np.float64)
        d00, d01, d11 = self._d00, self._d01, self._d11
        den = d00 * d11 - d01 * d01
        inv = np.divide(1., den, out=np.zeros_like(den), where=den > 1e-20)
        for start in range(0, len(points), chunk_size):
            chunk = points[start:start + chunk_size]
            ap = chunk[:, None, :] - self.a[None, :, :]
            signed = np.einsum('mti,ti->mt', ap, self._normal)
            proj = ap - self._normal[None, :, :] * np.divide(
                signed, self._n2[None, :], out=np.zeros_like(signed),
                where=self._n2[None, :] > 1e-20)[:, :, None]
            d20 = np.einsum('mti,ti->mt', proj, self.e1)
            d21 = np.einsum('mti,ti->mt', proj, self.e2)
            u = (d11[None, :] * d20 - d01[None, :] * d21) * inv[None, :]
            v = (d00[None, :] * d21 - d01[None, :] * d20) * inv[None, :]
            interior = ((den[None, :] > 1e-20) & (u >= 0) & (v >= 0) & (u + v <= 1))
            dist2 = np.where(interior, np.divide(
                signed ** 2, self._n2[None, :], out=np.full_like(signed, np.inf),
                where=self._n2[None, :] > 1e-20), np.inf)
            for index in range(3):
                a = self.triangles[:, index]
                edge = self._edge[:, index]
                length2 = self._edge_len2[:, index]
                delta0 = chunk[:, None, :] - a[None, :, :]
                t = np.clip(np.divide(np.einsum('mti,ti->mt', delta0, edge),
                                      length2[None, :], out=np.zeros_like(dist2),
                                      where=length2[None, :] > 1e-20), 0, 1)
                delta = delta0 - edge[None, :, :] * t[:, :, None]
                dist2 = np.minimum(dist2, np.einsum('mti,mti->mt', delta, delta))
            output[start:start + len(chunk)] = np.sqrt(np.min(dist2, axis=1))
        self._record_phase_timing('distance_many', started)
        return output

    def _record_phase_timing(self, name, started):
        """Accumulate geometry phase timing without imposing test fixtures."""
        timings = getattr(self, '_phase_timings', None)
        if timings is not None:
            timings[name] = timings.get(name, 0.0) + (perf_counter() - started) * 1000.0

    def validate_base(self, base, minimum, early=False, edge_steps=24, interior_steps=8,
                      allow_pl=True):
        """Validate completely; only a successful coarse result can be reused."""
        self._last_base_validation = None
        stats = getattr(self, '_validation_stats', None)
        if stats is None:
            stats = self._validation_stats = {}
        name = 'coarse' if early else 'full'
        stats[name + '_calls'] = stats.get(name + '_calls', 0) + 1
        previous = getattr(self, '_request_context', 'geometry')
        self._request_context = 'base_' + name
        started = perf_counter()
        try:
            result = self._validate_base(base, minimum, early, edge_steps, interior_steps, allow_pl)
            outcome = name + ('_success' if result[0] else '_failure')
            stats[outcome] = stats.get(outcome, 0) + 1
            if result[0] and early and edge_steps == 8 and interior_steps == 3:
                self._last_base_validation = _BaseValidation(
                    self._base_validation_signature(base, minimum, allow_pl), result)
            return result
        finally:
            stats[name + '_ms'] = stats.get(name + '_ms', 0.) + (perf_counter() - started) * 1000.
            self._request_context = previous

    def _base_validation_signature(self, base, minimum, allow_pl=True):
        # Verify content, not just array identity or its writeable flag. This
        # also covers entity relabeling and in-place changes by other owners.
        import hashlib
        if not hasattr(self, '_validation_identity'):
            self._validation_identity = object()
        groups = getattr(self, '_triangle_groups', None)
        resource = getattr(self, '_mesh_resource', None)
        if resource is not None and resource.matches(self.triangles, groups):
            content_key = resource.key
        else:
            digest = hashlib.sha256(np.asarray(self.triangles, dtype='<f8').tobytes())
            if groups is not None:
                digest.update(np.asarray(groups, dtype='<i8').tobytes())
            content_key = digest.digest()
        sides = tuple(None if getattr(self, name, None) is None else
                      np.asarray(getattr(self, name), dtype='<f8').tobytes()
                      for name in ('_target_side_origin', '_target_side_normal'))
        return (self._validation_identity, content_key,
                np.asarray(base, dtype='<f8').reshape(3, 3).tobytes(),
                np.float64(minimum).tobytes(), bool(allow_pl),
                bool(getattr(self, '_strict_pl', False)), getattr(self, '_ray_mode', ''),
                bool(self._lung_watertight), sides, id(getattr(self, '_mesh_evaluator', None)),
                id(getattr(self, '_distance_evaluator', None)), 'early/8/3/continuous-v1')

    def _validate_base(self, base, minimum, early, edge_steps, interior_steps, allow_pl):
        samples = ref.base_sample_points(list(map(tuple, base)),
                                         edge_steps=edge_steps,
                                         interior_steps=interior_steps)
        # Preserve the early-out behavior used to reject most candidates. It
        # avoids allocating a point-by-triangle distance matrix for plans that
        # already violate the first few samples.
        if early:
            closest, inside = float('inf'), 0
            if getattr(self, '_strict_pl', False):
                # Classify the entire coarse sample grid in one hardware job.
                # Distances also use PL; inspect their prefix in the original
                # order so the first failing sample retains the same meaning.
                samples = np.asarray(samples, dtype=np.float64).reshape(-1, 3)
                flags = self._inside_many(samples)
                first_inside = np.flatnonzero(flags)
                stop = int(first_inside[0]) + 1 if len(first_inside) else len(samples)
                stats = self._validation_stats
                stats['classified_samples'] = stats.get('classified_samples', 0) + len(samples)
                for start in range(0, stop, 8):
                    distances = self._distance_many(samples[start:min(start + 8, stop)])
                    stats['distance_submitted'] = stats.get('distance_submitted', 0) + len(distances)
                    for offset, distance in enumerate(distances):
                        stats['distance_used'] = stats.get('distance_used', 0) + 1
                        inside += int(flags[start + offset])
                        closest = min(closest, float(distance))
                        if inside or closest < minimum:
                            stats['distance_unused'] = stats.get('distance_unused', 0) + len(distances) - offset - 1
                            failures = stats.setdefault('first_failure_index', {})
                            position = str(start + offset)
                            failures[position] = failures.get(position, 0) + 1
                            return False, closest, inside
                valid, gap = self._base_mesh_clearance(base, minimum)
                return valid, gap, inside
            if getattr(self, '_cpu_index', None) is None:
                # Preserve the scalar callback contract used by lightweight
                # callers and test doubles that do not own a CPU index.
                for point in samples:
                    inside += int(self.inside(point, allow_pl=allow_pl))
                    closest = min(closest, self.distance(point))
                    if inside or closest < minimum:
                        return False, closest, inside
                valid, gap = self._base_mesh_clearance(base, minimum)
                return valid, gap, inside
            # CPU search candidates use the same ray parity and exact point
            # distance implementations, but evaluate the fixed sample grid
            # in batches.  Iterate the resulting arrays in the original order
            # so the first-failure and tolerance semantics remain unchanged.
            inside_mask = self._inside_many_cpu(samples)
            first_inside = np.flatnonzero(inside_mask)
            if len(first_inside):
                # The continuous triangle-to-mesh distance below is exact for
                # the entry face; only the first parity failure needs a point
                # distance for the legacy diagnostic value.
                index = int(first_inside[0])
                closest = float(self._distance_many_cpu(samples[index:index + 1])[0])
                return False, closest, 1
            valid, gap = self._base_mesh_clearance(base, minimum)
            closest = gap
            if closest < minimum:
                return False, closest, 0
            return valid, gap, 0
            return valid, gap, inside
        samples = np.asarray(samples, dtype=np.float64)
        if not allow_pl and not getattr(self, '_strict_pl', False):
            inside_mask = self._inside_many_cpu(samples)
        else:
            inside_mask = self._inside_many(samples)
        distances = self._distance_many(samples)
        inside = int(np.count_nonzero(inside_mask))
        closest = (self._last_distance_min_mm if getattr(self,'_strict_pl',False) else float(np.min(distances))) if len(distances) else float('inf')
        valid, gap = self._base_mesh_clearance(base, minimum)
        return inside == 0 and valid and closest >= minimum, gap, inside

    def _base_mesh_clearance(self, base, minimum):
        """Check the continuous triangle, including crossings between samples."""
        key = np.asarray(base, dtype=np.float64).tobytes()
        gap = self._base_gap_cache.get(key)
        if gap is None:
            gap = triangle_mesh_min_distance(
                base, self.triangles, (self._triangle_min, self._triangle_max))
            if len(self._base_gap_cache) >= 256:
                self._base_gap_cache.pop(next(iter(self._base_gap_cache)))
            self._base_gap_cache[key] = gap
        side_valid = self._base_stays_on_target_side(base, minimum)
        return bool(self._lung_watertight and gap > 1e-7 and gap >= minimum
                    and side_valid), gap

    def _base_stays_on_target_side(self, base, minimum):
        side_origin = getattr(self, '_target_side_origin', None)
        side_normal = getattr(self, '_target_side_normal', None)
        if side_origin is None or side_normal is None:
            return True
        # Keep the complete entry face on the lesion's side of the
        # midsagittal separator, clear of the inter-lung corridor.
        side_gap = (np.asarray(base, dtype=np.float64) - side_origin) @ side_normal
        return bool(np.all(side_gap >= max(minimum, 10.)))

    def build(self, params, *, allow_pl=True):
        self._request_context = 'entry'
        direction = np.asarray(ref.direction_for(params['yaw'], params['pitch']))
        base_center = self.surface_hit(self.center, direction, allow_pl=allow_pl) + direction * params['baseOffset']
        depth = np.max((self.points - base_center) @ -direction)
        safety = float(params['minClearance']) + .01 if params.get('safetyFit') else 0.
        # A safety cube projected from a point almost on the apex plane has an
        # ill-conditioned perspective projection and can create a kilometre-
        # scale entry face.  Keep the same cube containment rule, while
        # reserving an additional half-cube depth so every offset remains well
        # inside the finite projection cone.
        safety_depth = 1.5 * math.sqrt(3.) * safety + .01
        apex = base_center - direction * (depth + max(params['margin'], safety_depth))
        # Fit the same equilateral triangle as the scalar reference, using
        # cached arrays so slider previews can run in the GUI thread quickly.
        height = max(1e-6, float(np.dot(apex - base_center, -direction)))
        u, v = map(np.asarray, ref.basis(tuple(direction)))
        angle = math.radians(params['rotation'])
        u2 = u * math.cos(angle) + v * math.sin(angle)
        v2 = v * math.cos(angle) - u * math.sin(angle)
        # Each cube contains a ball of radius safety around a lesion vertex.
        # Containment of their convex hull guarantees the requested distance
        # from the complete lesion triangle surface to all tetrahedron faces.
        fit_points = self._fit_points
        if safety:
            offsets = np.asarray([(x, y, z) for x in (-safety, safety)
                                  for y in (-safety, safety) for z in (-safety, safety)])
            fit_points = (fit_points[:, None, :] + offsets).reshape(-1, 3)
        delta = fit_points - apex
        depth = delta @ direction
        if np.any(depth <= 1e-8):
            raise ValueError('病灶点位于深部尖点后方；请增加尖点余量')
        projected = apex + delta * (height / depth)[:, None] - base_center
        xs, ys = projected @ u2, projected @ v2
        plus, minus = np.max(xs + math.sqrt(3) * ys), np.max(xs - math.sqrt(3) * ys)
        bound = max(float(xs.max()), float((plus + minus) / 2))
        cx = (bound + 2 * float(xs.min())) / 3
        cy = (plus - minus) / (2 * math.sqrt(3))
        radius = (2 * bound - 2 * float(xs.min())) / 3 * params['padding']
        fitted = base_center + u2 * cx + v2 * cy
        base = np.asarray((fitted + u2 * radius,
                           fitted - .5 * u2 * radius + .8660254 * v2 * radius,
                           fitted - .5 * u2 * radius - .8660254 * v2 * radius))
        if params.get('baseArea', 0) > 0:
            area = ref.tri_area(*map(tuple, base)) / 100
            base = np.asarray(fitted) + (base - fitted) * math.sqrt(params['baseArea'] / area)
        return np.vstack((base, apex))

    def coverage(self, vertices):
        if getattr(self, '_strict_pl', False):
            raise RuntimeError('CPU tumor metrics forbidden in PL mode')
        started = perf_counter()
        base, apex = list(map(tuple, vertices[:3])), tuple(vertices[3])
        if ref.tetrahedron_volume(base, apex) < 1e-6:
            raise ValueError('四面体退化；请恢复规划或调整顶点')
        faces = ref.tetra_faces(base, apex)
        a = np.asarray([f[0] for f in faces])
        n = np.asarray([f[3] for f in faces])
        distances = (self.points[:, None, :] - a[None, :, :])
        distances = -np.einsum('nfi,fi->nf', distances, n)
        inside = int(np.count_nonzero(np.all(distances >= -1e-5, axis=1)))
        output = inside / len(self.points) * 100., float(distances.min()), faces
        self._record_phase_timing('cpu_metrics', started)
        return output

    def surface(self, faces):
        source = (self._lung_union.triangles if getattr(self, '_lung_union', None) is not None
                  else self.triangles)
        return clipped_surface(source, faces)

    def preview_resection_surfaces(self, vertices):
        """Build current wedge display meshes without computing plan metrics."""
        union = getattr(self, '_planning_lung_union', None)
        if union is None:
            union = getattr(self, '_lung_union', None)
        if union is None:
            raise ValueError('当前后端未提供精确肺并集，无法生成切除面预览')
        return union.preview_surfaces(vertices)

    def volume(self, vertices, steps=18, coarse=None):
        started = perf_counter()
        # Keep the historical two-argument call contract for test doubles and
        # external callers.  Three-ray estimates are only used by the coarse
        # search path, so the step count is an unambiguous fallback here.
        if coarse is None:
            coarse = (steps == 3)
        base, apex = vertices[:3], vertices[3]
        tetra_volume = float(ref.tetrahedron_volume(list(map(tuple, base)), tuple(apex)))
        # Candidate ranking only needs a deterministic estimate.  The exact
        # Manifold intersection is reserved for the final full evaluation;
        # using the same union ray crossings here preserves multi-solid parity
        # semantics without rebuilding a Boolean mesh for every candidate.
        if getattr(self, '_lung_union', None) is not None and not coarse:
            removed = self._lung_union.intersect(vertices)['volume_mm3']
            self._record_phase_timing('volume', started)
            return tetra_volume, removed
        strict = getattr(self, '_strict_pl', False)
        apex_inside = None if strict else self.inside(apex)
        fractions = []
        rays = []
        lengths = []
        for i in range(steps + 1):
            for j in range(steps + 1 - i):
                u, v = i / steps, j / steps
                point = base[0] * (1 - u - v) + base[1] * u + base[2] * v
                ray = point - apex
                length = np.linalg.norm(ray)
                if length <= 1e-9:
                    continue
                rays.append(ray / length)
                lengths.append(float(length))
        ray_hits = self._ray_hits_many(
            [apex] * len(rays), rays, require_complete=True,
            lengths=lengths if strict else None) if rays else []
        if strict:
            mean = self._last_volume_mean if rays else 0.
            output = tetra_volume, float(tetra_volume * mean)
            self._record_phase_timing('volume', started)
            return output
        if ray_hits is None:
            ray_hits = [self._hits_cpu(apex, direction) for direction in rays]
        postprocess_started = perf_counter()
        for hits, length in zip(ray_hits, lengths):
            # Integrate every inside interval, also valid for a concave
            # lung or a manually moved apex outside the lung.
            fractions.append(volume_fraction(hits, length, apex_inside,
                                            presorted=getattr(self, '_strict_pl', False)))
        output = tetra_volume, float(tetra_volume * (float(np.mean(fractions)) if fractions else 0.))
        self._record_phase_timing('cpu_postprocess', postprocess_started)
        self._record_phase_timing('volume', started)
        return output

    def evaluate(self, vertices, params, coarse=False, metric_result=None, base_validation=None):
        started = perf_counter()
        self._request_context = 'evaluate_coarse' if coarse else 'evaluate_full'
        self._phase_timings = {}
        vertices = np.asarray(vertices, dtype=np.float64)
        if (vertices.shape != (4, 3) or not np.isfinite(vertices).all()
                or ref.tetrahedron_volume(list(map(tuple, vertices[:3])), tuple(vertices[3])) < 1e-6):
            raise ValueError('四面体顶点无效或退化')
        if getattr(self, '_strict_pl', False) and (not metric_result or not metric_result.get('ok')):
            raise RuntimeError('PL tumor metrics required; CPU fallback is forbidden')
        if metric_result is None:
            coverage, clearance, faces = self.coverage(vertices)
            pl_feasible = True
        else:
            coverage = float(metric_result['coverage_percent'])
            clearance = float(metric_result['clearance_mm'])
            faces = ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3]))
            pl_feasible = (bool(metric_result.get('feasible', True))
                           and not metric_result.get('errors', 0)
                           and metric_result.get('inside', len(self.points)) == len(self.points)
                           and metric_result.get('processed', len(self.points)) == len(self.points))
        coverage_finished = perf_counter()
        self._record_phase_timing('coverage', started)
        # PL retains its four-plane coverage and legacy clearance ABI. The
        # additional cut-plane metric is explicitly owned by PS float64.
        tumor_margin = cut_plane_margin(self.points, faces if len(faces) == 4 else
            ref.tetra_faces(list(map(tuple, vertices[:3])), tuple(vertices[3])))
        required_base_gap = base_clearance(params)
        constraint_margin = tumor_margin if separate_constraints(params) else clearance
        if (coarse and isinstance(base_validation, _BaseValidation) and base_validation.result[0]
                and base_validation.signature == self._base_validation_signature(vertices[:3], required_base_gap)):
            valid_base, base_gap, inside_samples = base_validation.result
            stats = self._validation_stats
            stats['coarse_reused'] = stats.get('coarse_reused', 0) + 1
        else:
            valid_base, base_gap, inside_samples = self.validate_base(
                vertices[:3], required_base_gap, early=coarse,
                edge_steps=8 if coarse else 24, interior_steps=3 if coarse else 8)
        apex_inside = self.inside(vertices[3])
        validation_finished = perf_counter()
        self._record_phase_timing('lung_validation', coverage_finished)
        if coarse:
            area, surface = 0., np.empty((0, 3, 3), dtype=np.float64)
        elif getattr(self, '_lung_union', None) is not None:
            boolean = self._lung_union.intersect(vertices)
            area, surface = boolean['surface_area_mm2'] / 100., boolean['surface']
        else:
            area, surface = self.surface(faces)
        area_finished = perf_counter()
        self._record_phase_timing('surface', validation_finished)
        total, removed = self.volume(vertices, 3 if coarse else 18)
        volume_finished = perf_counter()
        valid = (valid_base and apex_inside and pl_feasible and coverage >= 100.0
                 and constraint_margin >= params['minClearance'])
        whole_lung_volume = getattr(self, 'whole_lung_volume', self.lung_volume)
        target_lung_files = getattr(self, 'target_lung_files', self.lung_files)
        whole_lung_files = getattr(self, 'whole_lung_files', self.lung_files)
        risk = min(100, max(0, round((100 - coverage) * .8 + max(0., params['minClearance'] - constraint_margin) * 20
                       + (removed / self.lung_volume * 100 if self.lung_volume > 0 else 0) * 6
                       + area * .25 + (40 if not valid_base or not apex_inside else 0))))
        result = {
            'base_vertices': vertices[:3].tolist(), 'apex': vertices[3].tolist(),
            'base_center': vertices[:3].mean(axis=0).tolist(),
            'coverage_percent': coverage, 'clearance_mm': clearance,
            'tumor_margin_mm': tumor_margin,
            'tumor_margin_method': 'minimum signed distance to three cutting side supporting planes; conservative model margin',
            'tumor_margin_backend': 'PS / NumPy float64 (explicit additional metric; not PL fallback)',
            'legacy_clearance_scope': 'all four tetrahedron supporting planes, including external base',
            'required_tumor_margin_mm': params['minClearance'],
            'required_base_clearance_mm': required_base_gap,
            'surface_area_cm2': area, 'base_area_cm2': ref.tri_area(*map(tuple, vertices[:3])) / 100.,
            'resection_volume_cm3': removed / 1000.,
            'lung_volume_cm3': whole_lung_volume / 1000.,
            'whole_lung_volume_cm3': whole_lung_volume / 1000.,
            'target_lung_volume_cm3': self.lung_volume / 1000.,
            'tetrahedron_volume_cm3': total / 1000.,
            'resection_ratio_percent': removed / whole_lung_volume * 100 if whole_lung_volume > 1e-9 else None,
            'whole_lung_resection_ratio_percent': removed / whole_lung_volume * 100 if whole_lung_volume > 1e-9 else None,
            'target_lung_resection_ratio_percent': removed / self.lung_volume * 100 if self.lung_volume > 1e-9 else None,
            'base_outside_valid': valid_base, 'min_base_clearance_mm': base_gap,
            'base_inside_samples': inside_samples, 'apex_inside_lung': apex_inside,
            'base_validation_method': 'continuous triangle-mesh distance + inside classification',
            'base_validation_backend': 'PS / NumPy float64 (additional continuous check)',
            'lung_edge_closed': self._lung_watertight,
            'lesion_component_policy': 'largest connected component only',
            'lung_solid_count': getattr(self, '_group_count', 1),
            'entry_side_constraint': ('all base vertices at least 10 mm on the lesion side of the bilateral separator'
                                      if getattr(self, '_target_side_origin', None) is not None else 'not inferred'),
            'lung_inside_method': ('Boolean union of closed lung solids' if getattr(self, '_lung_union', None) is not None else
                                  ('union of per-STL closed solids' if getattr(self, '_cpu_index', None) is not None else 'mesh crossing parity')),
            'lung_volume_method': ('Manifold float64 Boolean union of all left and right lung solids'
                                   if getattr(self, '_whole_lung_union', None) is not None else
                                   'sum of all left and right closed lung STL volumes'),
            'target_lung_volume_method': ('Manifold float64 Boolean union of selected target lung solids'
                                          if getattr(self, '_lung_union', None) is not None else
                                          'sum of selected target lung STL volumes'),
            'surface_area_method': ('source lung faces of Boolean lung-union/tetra intersection'
                                    if getattr(self, '_lung_union', None) is not None else
                                    'clipped input triangles; may include internal interfaces'),
            'cut_area_method': self.cut_area_method(),
            'quantitative_backend': ('PS / Manifold float64 mesh Boolean'
                                     if getattr(self, '_lung_union', None) is not None else 'legacy'),
            'required_clearance_mm': 0. if separate_constraints(params) else params['minClearance'],
            'valid': bool(valid), 'risk_score': risk, 'units': 'mm',
            'tumor_points': len(self.points), 'lung_triangles': len(self.lung),
            'lung_files': self.lung_files, 'target_lung_files': target_lung_files,
            'whole_lung_files': whole_lung_files, 'tumor_file': self.tumor_file,
            'lung_volume_scope': 'bilateral whole lung (left + right)',
            'surgical_lung_files': getattr(self, 'surgical_lung_files', self.lung_files),
            'surgical_lung_volume_scope': 'complete lung on lesion side',
            'mirror_plane_x': self.mirror_x, 'mirror_lung': self.mirror_x is not None,
            'volume_method': ('Manifold float64 Boolean intersection'
                              if getattr(self, '_lung_union', None) is not None else
                              'deterministic ray quadrature, 18 subdivisions (estimate)'),
            'distance_backend': 'FPGA PL BVH Q32 squared distance' if getattr(self,'_strict_pl',False) else 'PS / NumPy',
            'volume_backend': ('FPGA PL Q2.30 integration and mean' if getattr(self, '_strict_pl', False) else
                             ('PS / Manifold float64 Boolean' if getattr(self, '_lung_union', None) is not None else 'PS / NumPy')), 
            'metric_backend': 'CPU / NumPy', 'evaluation_ms': (perf_counter() - started) * 1000.,
            'yaw': params['yaw'], 'pitch': params['pitch'], 'margin_mm': params['margin'],
            'base_rotation_deg': params['rotation'],
            'timings_ms': {**getattr(self, '_phase_timings', {}),
                           'coverage': (coverage_finished - started) * 1000,
                           'lung_validation': (validation_finished - coverage_finished) * 1000,
                           'surface': (area_finished - validation_finished) * 1000,
                           'volume': (volume_finished - area_finished) * 1000},
        }
        result.update(constraint_report(params, tumor_margin, valid))
        return result, surface

    def _check_planning_overlap(self):
        """Reject disjoint bounds without guessing registration or mirroring.

        Overlapping bounds are only a necessary condition. A centroid may be
        outside a concave lung, so do not use centroid parity as a rejection.
        """
        lung_min, lung_max = self._triangle_min.min(axis=0), self._triangle_max.max(axis=0)
        lesion_min, lesion_max = self.points.min(axis=0), self.points.max(axis=0)
        separation = np.maximum(np.maximum(lung_min - lesion_max, lesion_min - lung_max), 0.)
        axes = np.flatnonzero(separation > 1e-7)
        self.search_diagnostics['input_bounds'] = dict(
            lung=[lung_min.tolist(), lung_max.tolist()],
            lesion=[lesion_min.tolist(), lesion_max.tolist()],
            separation_mm=separation.tolist(), mirrored=self.mirror_x is not None)
        if len(axes):
            descriptions = [f'{"XYZ"[i]}：病灶 {lesion_min[i]:.1f}–{lesion_max[i]:.1f} mm，'
                            f'肺 {lung_min[i]:.1f}–{lung_max[i]:.1f} mm'
                            for i in axes]
            raise ValueError('病灶与所选肺模型的坐标范围不重叠（' + '；'.join(descriptions)
                             + '）。已停止搜索；请核对肺侧、参与规划的肺段以及坐标配准。'
                               '增大底面或留边不能修复坐标对应关系。')

    @staticmethod
    def cut_area(interior):
        """Area estimate of tessellated cutting faces retained inside lung."""
        if not len(interior):
            return 0.
        cross = np.cross(interior[:, 1] - interior[:, 0], interior[:, 2] - interior[:, 0])
        return float(np.linalg.norm(cross, axis=1).sum() / 200.)

    def cut_area_method(self):
        return ('source tetrahedron faces of Boolean lung-union/tetra intersection'
                if getattr(self, '_lung_union', None) is not None else
                'interior face tessellation, 16 subdivisions (estimate)')
