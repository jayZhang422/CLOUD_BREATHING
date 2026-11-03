"""Load a group of STL surfaces for a Qt Quick 3D preview."""

import os
from pathlib import Path
from time import perf_counter

import numpy as np
from PySide6.QtCore import QObject, Property, QThread, Signal, Slot
from PySide6.QtGui import QVector3D
from PySide6.QtQuick3D import QQuick3DGeometry
from PySide6.QtWidgets import QColorDialog, QFileDialog

from .stl_cache import face_targets, load_preview
from .planning_inputs import is_lung_surface, is_lesion
from .mesh_buffers import prepare_display_buffers
from .mesh_buffer_cache import load_display_buffers
from .interaction_lod import InteractionLodConfig, prepare_interaction_lod


PALETTE = ("#a8bec5", "#d66a6a", "#e5b56e", "#72a9c3", "#9dc989", "#b69ac6")


def count_stl_faces(path: Path) -> int:
    with path.open("rb") as stream:
        header = stream.read(84)
        if len(header) < 84:
            raise ValueError(f"STL 文件不完整：{path.name}")
        count = int.from_bytes(header[80:84], "little")
        if path.stat().st_size == 84 + count * 50:
            return count
        stream.seek(0)
        vertices = sum(line.lstrip().lower().startswith(b"vertex ") for line in stream)
    if vertices == 0 or vertices % 3:
        raise ValueError(f"STL 顶点数无效：{path.name}")
    return vertices // 3


def read_stl(path: Path) -> tuple[np.ndarray, np.ndarray]:
    with path.open("rb") as stream:
        header = stream.read(84)
        if len(header) < 84:
            raise ValueError(f"STL 文件不完整：{path.name}")
        count = int.from_bytes(header[80:84], "little")
        binary = path.stat().st_size == 84 + count * 50
    if binary:
        triangle_dtype = np.dtype([("normal", "<f4", 3), ("vertices", "<f4", (3, 3)), ("attribute", "<u2")])
        triangles = np.memmap(path, dtype=triangle_dtype, mode="r", offset=84, shape=(count,))
        vertices = np.asarray(triangles["vertices"], dtype=np.float32).copy()
        normals = np.asarray(triangles["normal"], dtype=np.float32).copy()
    else:
        vertices_list = []
        with path.open("r", encoding="utf-8", errors="replace") as stream:
            for line in stream:
                parts = line.split()
                if len(parts) == 4 and parts[0].lower() == "vertex":
                    vertices_list.append(tuple(map(float, parts[1:])))
        vertices = np.asarray(vertices_list, dtype=np.float32).reshape(-1, 3, 3)
        normals = np.zeros((len(vertices), 3), dtype=np.float32)
    if len(vertices) == 0 or not np.isfinite(vertices).all():
        raise ValueError(f"STL 几何数据无效：{path.name}")
    edges = vertices[:, 1] - vertices[:, 0]
    calculated = np.cross(edges, vertices[:, 2] - vertices[:, 0])
    lengths = np.linalg.norm(calculated, axis=1)
    valid = lengths > 1e-8
    calculated[valid] /= lengths[valid, None]
    invalid_normal = np.linalg.norm(normals, axis=1) < 0.1
    normals[invalid_normal] = calculated[invalid_normal]
    return vertices, normals


class SurfaceGeometry(QQuick3DGeometry):
    def __init__(self, vertices: np.ndarray, normals: np.ndarray, center: np.ndarray,
                 scale: float, parent=None, prepared=None):
        super().__init__(parent)
        buffers = prepared if prepared is not None else prepare_display_buffers(vertices, normals, center, scale)
        self.setVertexData(buffers["vertex_data"])
        self.setStride(24)
        self.setPrimitiveType(QQuick3DGeometry.PrimitiveType.Triangles)
        self.addAttribute(QQuick3DGeometry.Attribute.Semantic.PositionSemantic, 0, QQuick3DGeometry.Attribute.ComponentType.F32Type)
        self.addAttribute(QQuick3DGeometry.Attribute.Semantic.NormalSemantic, 12, QQuick3DGeometry.Attribute.ComponentType.F32Type)
        if buffers["index_data"]:
            self.setIndexData(buffers["index_data"])
            self.addAttribute(QQuick3DGeometry.Attribute.Semantic.IndexSemantic, 0,
                              QQuick3DGeometry.Attribute.ComponentType.U16Type)
        low, high = buffers["low"], buffers["high"]
        self.setBounds(QVector3D(*map(float, low)), QVector3D(*map(float, high)))


class StlWorker(QObject):
    completed = Signal(object)
    failed = Signal(str)

    @Slot(str, int, int, str)
    def load(self, directory: str, triangle_limit: int = 0,
             preview_faces: int = 0, cache_directory: str = "") -> None:
        try:
            started = perf_counter()
            root = Path(directory)
            paths = sorted(root.rglob("*.stl"))
            if not paths:
                raise ValueError("文件夹中没有 STL 文件")
            counts = [count_stl_faces(path) for path in paths] if preview_faces or triangle_limit else []
            if triangle_limit > 0 and not preview_faces and sum(counts) > triangle_limit:
                raise ValueError(
                    f"KV260 约束为 {triangle_limit:,} 面；文件夹超过预算。"
                    "请启用减面预览，或关闭约束模式后加载原模型"
                )
            budget = min(preview_faces, triangle_limit) if preview_faces and triangle_limit else preview_faces
            targets = face_targets(counts, budget) if budget else counts
            timings = {"scan_ms": (perf_counter() - started) * 1000,
                       "read_ms": 0.0, "hash_ms": 0.0, "simplify_ms": 0.0,
                       "cache_ms": 0.0, "bounds_ms": 0.0, "cache_hits": 0,
                       "cache_write_failed": 0}
            surfaces = []
            lowers = []
            uppers = []
            for index, path in enumerate(paths):
                if budget and counts[index] > targets[index]:
                    if not cache_directory:
                        raise ValueError("减面预览需要缓存目录")
                    vertices, normals, low, high, stages, hit = load_preview(
                        path, root, Path(cache_directory), targets[index], read_stl,
                    )
                    for stage, duration in stages.items():
                        timings[stage] += duration
                    timings["cache_hits"] += int(hit)
                else:
                    read_started = perf_counter()
                    vertices, normals = read_stl(path)
                    timings["read_ms"] += (perf_counter() - read_started) * 1000
                    low = vertices.min(axis=(0, 1))
                    high = vertices.max(axis=(0, 1))
                surfaces.append((path.name, vertices, normals))
                lowers.append(low)
                uppers.append(high)
            bounds_started = perf_counter()
            lower = np.min(lowers, axis=0)
            upper = np.max(uppers, axis=0)
            size = float(np.max(upper - lower))
            if size <= 0:
                raise ValueError("模型尺寸无效")
            timings["bounds_ms"] = (perf_counter() - bounds_started) * 1000
            timings["original_faces"] = sum(counts) if counts else sum(len(v) for _, v, _ in surfaces)
            timings["preview_faces"] = sum(len(v) for _, v, _ in surfaces)
            center, scale = (lower + upper) / 2, 180.0 / size
            shading = os.environ.get("CLOUD_BREATHING_MESH_SHADING", "flat").lower()
            shading = shading if shading in ("flat", "smooth") else "flat"
            display_cache = os.environ.get("CLOUD_BREATHING_SMOOTH_CACHE", "0").lower() in ("1", "true", "yes")
            display_cache_directory = Path(cache_directory) / "display_buffers" if cache_directory else None
            prepare_started = perf_counter()
            prepared_surfaces = []
            lod_config = InteractionLodConfig.from_environment()
            lod_remaining = lod_config.budget_bytes
            lod_metrics = []
            for surface_index, (name, vertices, normals) in enumerate(surfaces):
                buffers, cache_metrics = load_display_buffers(
                    vertices, normals, center, scale, shading, display_cache_directory, display_cache)
                for key, value in cache_metrics.items():
                    if key == "display_cache_enabled":
                        timings[key] = value
                    else:
                        timings[key] = timings.get(key, 0) + value
                lod_buffers, lod_info = prepare_interaction_lod(
                    paths[surface_index], root, vertices, normals, center, scale,
                    Path(cache_directory) if cache_directory else None, lod_config, lod_remaining)
                lod_info["name"] = name
                lod_metrics.append(lod_info)
                if lod_buffers is not None:
                    lod_remaining -= lod_info["extra_payload_bytes"]
                    buffers["interaction_lod"] = lod_buffers
                prepared_surfaces.append((name, vertices, normals, buffers))
            timings["prepare_buffers_ms"] = (perf_counter() - prepare_started) * 1000
            timings.update(
                mesh_shading_request=shading,
                upload_bytes=sum(buffers["upload_bytes"] for _, _, _, buffers in prepared_surfaces),
                soup_bytes=sum(buffers["soup_bytes"] for _, _, _, buffers in prepared_surfaces),
                vertex_count=sum(buffers["vertex_count"] for _, _, _, buffers in prepared_surfaces),
                indexed_models=sum(bool(buffers["index_data"]) for _, _, _, buffers in prepared_surfaces),
                smooth_models=sum(buffers["shading"] == "smooth" for _, _, _, buffers in prepared_surfaces),
                smooth_fallback_models=sum(buffers["shading"] != "smooth" for _, _, _, buffers in prepared_surfaces) if shading == "smooth" else 0,
                interaction_lod_mode=lod_config.mode,
                interaction_lod_ratio=lod_config.ratio,
                interaction_lod_budget_bytes=lod_config.budget_bytes,
                interaction_lod_extra_bytes=lod_config.budget_bytes - lod_remaining,
                interaction_lod_faces=sum(info["actual_faces"] for info in lod_metrics if info["status"] == "ready"),
                interaction_lod_models=sum(info["status"] == "ready" for info in lod_metrics),
                interaction_lod_prepare_ms=sum(info["total_ms"] for info in lod_metrics),
                interaction_lod_layers=lod_metrics,
            )
            timings["worker_ms"] = (perf_counter() - started) * 1000
            self.completed.emit((prepared_surfaces, center, scale, directory, timings))
        except Exception as exc:
            self.failed.emit(str(exc))


class SurfaceLayer(QObject):
    appearanceChanged = Signal()

    def __init__(self, name: str, geometry: SurfaceGeometry, triangle_count: int,
                 color: str, opacity: float, visible: bool, parent=None, interaction_geometry=None,
                 interaction_faces=0):
        super().__init__(parent)
        self._name = name
        self._geometry = geometry
        self._geometry.setParent(self)
        self._triangle_count = triangle_count
        self._color = color
        self._opacity = opacity
        self._visible = visible
        self._interaction_geometry = interaction_geometry or geometry
        if interaction_geometry is not None:
            interaction_geometry.setParent(self)
        self._interaction_faces = interaction_faces or triangle_count

    name = Property(str, lambda self: self._name, constant=True)
    geometry = Property(QObject, lambda self: self._geometry, constant=True)
    interactionGeometry = Property(QObject, lambda self: self._interaction_geometry, constant=True)
    interactionTriangleCount = Property(int, lambda self: self._interaction_faces, constant=True)
    hasInteractionLod = Property(bool, lambda self: self._interaction_geometry is not self._geometry, constant=True)
    boundsMin = Property(QVector3D, lambda self: self._geometry.boundsMin(), constant=True)
    boundsMax = Property(QVector3D, lambda self: self._geometry.boundsMax(), constant=True)
    triangleCount = Property(int, lambda self: self._triangle_count, constant=True)
    triangleCountText = Property(str, lambda self: f"{self._triangle_count:,}", constant=True)
    color = Property(str, lambda self: self._color, notify=appearanceChanged)
    opacity = Property(float, lambda self: self._opacity, notify=appearanceChanged)
    visible = Property(bool, lambda self: self._visible, notify=appearanceChanged)

    def set_color(self, color: str):
        if color != self._color:
            self._color = color
            self.appearanceChanged.emit()

    def set_opacity(self, opacity: float):
        opacity = max(0.0, min(1.0, opacity))
        if opacity != self._opacity:
            self._opacity = opacity
            self.appearanceChanged.emit()

    def set_visible(self, visible: bool):
        if visible != self._visible:
            self._visible = visible
            self.appearanceChanged.emit()


class StlViewer(QObject):
    rowsChanged = Signal()
    statusChanged = Signal()
    loadStarted = Signal()
    loadRequested = Signal(str, int, int, str)

    def __init__(self, cache_directory: Path | None = None):
        super().__init__()
        self._rows = []
        self._busy = False
        self._status = "未加载 STL"
        self._directory = ""
        self._scene_center = np.zeros(3)
        self._scene_scale = 1.0
        self._triangle_limit = int(os.environ.get("CLOUD_BREATHING_TRIANGLE_LIMIT", "0"))
        # Show the full original STL by default on both PC and KV260.
        self._preview_faces = 0
        self._timings = {}
        self._cache_directory = cache_directory or Path(__file__).resolve().parents[1] / "data" / "stl_cache"
        self._thread = QThread(self)
        self._worker = StlWorker()
        self._worker.moveToThread(self._thread)
        self.loadRequested.connect(self._worker.load)
        self._worker.completed.connect(self._completed)
        self._worker.failed.connect(self._failed)
        self._thread.start()

    rows = Property("QVariantList", lambda self: self._rows, notify=rowsChanged)
    triangleCount = Property(int, lambda self: sum(row.triangleCount for row in self._rows), notify=rowsChanged)
    triangleCountText = Property(str, lambda self: f"{self.triangleCount:,}", notify=rowsChanged)
    status = Property(str, lambda self: self._status, notify=statusChanged)
    busy = Property(bool, lambda self: self._busy, notify=statusChanged)
    directory = Property(str, lambda self: self._directory, notify=statusChanged)
    sceneCenter = Property(QVector3D, lambda self: QVector3D(*map(float, self._scene_center)), notify=rowsChanged)
    sceneCenterMm = Property('QVariantList', lambda self: list(map(float, self._scene_center)), notify=rowsChanged)
    sceneScale = Property(float, lambda self: self._scene_scale, notify=rowsChanged)
    previewFaces = Property(int, lambda self: self._preview_faces, notify=statusChanged)
    loadTimings = Property("QVariantMap", lambda self: self._timings, notify=statusChanged)
    timingText = Property(str, lambda self: (
        f"扫描 {self._timings['scan_ms']:.0f} · 读取 {self._timings['read_ms']:.0f} · "
        f"减面 {self._timings['simplify_ms']:.0f} · 缓存 {self._timings['cache_ms']:.0f} · "
        f"几何 {self._timings['geometry_ms']:.0f} ms"
    ) if self._timings else "", notify=statusChanged)

    @Slot(int)
    def setPreviewFaces(self, faces: int):
        # This deployment must retain all original triangles, including when
        # stale settings or a UI callback requests a display preview.
        self._preview_faces = 0
        self.statusChanged.emit()

    @Slot(int)
    def setTriangleLimit(self, triangle_limit):
        self._triangle_limit = max(0, triangle_limit)
        if self._triangle_limit and self.triangleCount > self._triangle_limit:
            self._status = "现有 STL 超过 KV260 预算；下次载入将受限"
            self.statusChanged.emit()

    @Slot()
    def chooseDirectory(self):
        if getattr(self, "dialogs", None):
            self.dialogs.directory("选择同一患者的 STL 文件夹", self._directory or str(Path.home()), self.loadDirectory)
            return
        directory = QFileDialog.getExistingDirectory(None, "选择同一患者的 STL 文件夹", self._directory)
        if directory:
            self.loadDirectory(directory)

    @Slot(str)
    def loadDirectory(self, directory: str):
        if self._busy:
            return
        self._busy = True
        self._status = "正在读取 STL..."
        self.statusChanged.emit()
        self.loadStarted.emit()
        self.loadRequested.emit(directory, self._triangle_limit, self._preview_faces, str(self._cache_directory))

    @Slot(object)
    def _completed(self, result):
        surfaces, center, scale, self._directory, timings = result
        self._scene_center, self._scene_scale = center, scale
        previous_rows = self._rows
        rows = []
        geometry_started = perf_counter()
        for index, (name, vertices, normals, buffers) in enumerate(surfaces):
            lower = name.lower()
            planned = "plan" in lower and not is_lung_surface(name)
            if is_lesion(name):
                color, opacity = "#e5b56e", 1.0
            elif "artery" in lower:
                color, opacity = "#d66a6a", 1.0
            elif "venous" in lower:
                color, opacity = "#72a9c3", 1.0
            elif is_lung_surface(name):
                color, opacity = "#a8bec5", 0.28
            else:
                color, opacity = PALETTE[index % len(PALETTE)], 1.0
            lod_buffers = buffers.get("interaction_lod")
            lod_geometry = (SurfaceGeometry(vertices, normals, center, scale, prepared=lod_buffers)
                            if lod_buffers is not None else None)
            rows.append(SurfaceLayer(name, SurfaceGeometry(vertices, normals, center, scale, prepared=buffers),
                                     len(vertices), color, opacity, not planned, self,
                                     interaction_geometry=lod_geometry,
                                     interaction_faces=lod_buffers["triangle_count"] if lod_buffers else 0))
        self._rows = rows
        timings["geometry_ms"] = (perf_counter() - geometry_started) * 1000
        timings["total_ms"] = timings["worker_ms"] + timings["geometry_ms"]
        self._timings = timings
        print("STL_INTERACTION_LOD:", {key: value for key, value in timings.items()
                                       if key.startswith("interaction_lod_")}, flush=True)
        print("STL_DISPLAY_BUFFERS:", {key: timings[key] for key in (
            "mesh_shading_request", "prepare_buffers_ms", "upload_bytes", "soup_bytes",
            "vertex_count", "indexed_models", "smooth_models", "smooth_fallback_models",
            "prepare_buffers_compute_ms", "display_cache_enabled", "display_cache_hash_ms",
            "display_cache_read_ms", "display_cache_write_ms", "display_cache_failure_ms",
            "display_cache_hits", "display_cache_misses", "display_cache_read_failed",
            "display_cache_writes", "display_cache_write_failed", "display_cache_skipped")}, flush=True)
        self._busy = False
        self._status = (f"已加载 {len(self._rows)} 个 STL 结构 · "
                        f"{timings['preview_faces']:,}/{timings['original_faces']:,} 面 · "
                        f"缓存命中 {timings['cache_hits']} 项 · 总计 {timings['total_ms']:.0f} ms")
        if timings["cache_write_failed"]:
            self._status += " · 缓存写入失败"
        self.rowsChanged.emit()
        self.statusChanged.emit()
        for row in previous_rows:
            row.deleteLater()

    @Slot(str)
    def _failed(self, message: str):
        self._busy = False
        self._status = f"加载失败：{message}"
        self.statusChanged.emit()

    @Slot(int, str)
    def setColor(self, index: int, color: str):
        if 0 <= index < len(self._rows):
            self._rows[index].set_color(color)

    @Slot(int)
    def chooseColor(self, index: int):
        if 0 <= index < len(self._rows):
            if getattr(self, "dialogs", None):
                row = self._rows[index]
                # Hold the object identity: reloading rows during a dialog must
                # never recolor a different structure at the same index.
                def apply_color(color):
                    if row in self._rows:
                        row.set_color(color)
                self.dialogs.color("选择结构颜色", row.color, apply_color)
                return
            from PySide6.QtGui import QColor
            selected = QColorDialog.getColor(QColor(self._rows[index].color), None, "选择结构颜色")
            if selected.isValid():
                self.setColor(index, selected.name())

    @Slot(int, float)
    def setOpacity(self, index: int, opacity: float):
        if 0 <= index < len(self._rows):
            self._rows[index].set_opacity(opacity)

    @Slot(int, bool)
    def setVisible(self, index: int, visible: bool):
        if 0 <= index < len(self._rows):
            self._rows[index].set_visible(visible)

    def shutdown(self):
        self._thread.quit()
        self._thread.wait(2000)
