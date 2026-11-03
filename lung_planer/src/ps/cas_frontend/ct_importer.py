from datetime import datetime
from pathlib import Path, PureWindowsPath

from PySide6.QtCore import QObject, Property, QThread, QUrl, Signal, Slot
from PySide6.QtWidgets import QFileDialog

from .database import initialize_database, open_database, save_ct_result


class CtWorker(QObject):
    completed = Signal(object)
    failed = Signal(str)

    @Slot(str, str)
    def convert(self, source: str, destination: str) -> None:
        try:
            from .dicom import convert_ct_series

            self.completed.emit(convert_ct_series(source, destination))
        except Exception as exc:
            self.failed.emit(str(exc))


class CtImporter(QObject):
    changed = Signal()
    imported = Signal()
    calibrationChanged = Signal(object)
    convertRequested = Signal(str, str)

    def __init__(self, project_directory: Path) -> None:
        super().__init__()
        initialize_database()
        self._project_directory = project_directory
        self._busy = False
        self._status = "尚未导入 CT 序列"
        self._preview_path = ""
        self._coronal_path = ""
        self._sagittal_path = ""
        self._coronal_directory = None
        self._sagittal_directory = None
        self._png_directory = None
        self._plane_paths = {"axial": [], "coronal": [], "sagittal": []}
        self._slice_index = 0
        self._slice_count = 0
        self._coronal_index = 0
        self._sagittal_index = 0
        self._coronal_count = 0
        self._sagittal_count = 0
        self._metadata_text = "选择包含 .dcm 切片的文件夹，系统将生成 PNG 预览和脱敏技术信息。"
        self._patient_text = "未载入患者"
        self._institution_text = "未载入机构"
        self._study_text = ""
        self._calibration = {}
        self._source_directory = ""
        self._study_id = -1
        self._thread = QThread(self)
        self._worker = CtWorker()
        self._worker.moveToThread(self._thread)
        self.convertRequested.connect(self._worker.convert)
        self._worker.completed.connect(self._completed)
        self._worker.failed.connect(self._failed)
        self._thread.start()

    busy = Property(bool, lambda self: self._busy, notify=changed)
    status = Property(str, lambda self: self._status, notify=changed)
    previewPath = Property(str, lambda self: self._preview_path, notify=changed)
    coronalPath = Property(str, lambda self: self._coronal_path, notify=changed)
    sagittalPath = Property(str, lambda self: self._sagittal_path, notify=changed)
    coronalIndex = Property(int, lambda self: self._coronal_index, notify=changed)
    sagittalIndex = Property(int, lambda self: self._sagittal_index, notify=changed)
    coronalCount = Property(int, lambda self: self._coronal_count, notify=changed)
    sagittalCount = Property(int, lambda self: self._sagittal_count, notify=changed)
    metadataText = Property(str, lambda self: self._metadata_text, notify=changed)
    patientText = Property(str, lambda self: self._patient_text, notify=changed)
    institutionText = Property(str, lambda self: self._institution_text, notify=changed)
    studyText = Property(str, lambda self: self._study_text, notify=changed)
    sliceIndex = Property(int, lambda self: self._slice_index, notify=changed)
    sliceCount = Property(int, lambda self: self._slice_count, notify=changed)
    calibration = Property('QVariantMap', lambda self: dict(self._calibration), notify=calibrationChanged)
    # DICOM folder of the open study; ctfpga uses it as --data-dir.
    sourceDirectory = Property(str, lambda self: self._source_directory, notify=changed)
    # Database id of the open study (-1 before one is loaded); the UI maps it to an alias.
    studyId = Property(int, lambda self: self._study_id, notify=changed)

    @Slot()
    def chooseDirectory(self) -> None:
        if getattr(self, "dialogs", None):
            self.dialogs.directory("选择 CT DICOM 文件夹", str(Path.home()), self.importDirectory)
            return
        directory = QFileDialog.getExistingDirectory(None, "选择 CT DICOM 文件夹")
        self.importDirectory(directory)

    @Slot(str)
    def importDirectory(self, directory: str) -> None:
        if self._busy:
            return
        if not directory:
            return
        # Reopening the same study should only read the indexed PNG paths.
        # The conversion output is immutable and remains valid until the source
        # directory changes; this avoids rebuilding 1,200+ MPR files on every use.
        source = str(Path(directory).expanduser().resolve())
        with open_database() as connection:
            cached = connection.execute(
                "SELECT id, output_directory FROM ct_studies "
                "WHERE source_directory = ? ORDER BY id DESC LIMIT 1", (source,)
            ).fetchone()
        if cached is not None:
            output = Path(cached["output_directory"])
            if (output / "metadata.json").is_file() and (output / "png").is_dir():
                self.loadStudy(int(cached["id"]))
                self._status = f"已从缓存加载病例 #{int(cached['id'])}"
                self.changed.emit()
                return
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        output = self._project_directory / "data" / "converted_ct" / timestamp
        self._busy = True
        self._status = "正在转换 DICOM 切片，请稍候..."
        self.changed.emit()
        self.convertRequested.emit(directory, str(output))

    @Slot(int)
    def loadStudy(self, study_id: int) -> None:
        with open_database() as connection:
            study = connection.execute("SELECT * FROM ct_studies WHERE id = ?", (study_id,)).fetchone()
            if study is None:
                self._status = "未找到病例记录"
                self.changed.emit()
                return
            axial = connection.execute(
                "SELECT slice_index, image_path FROM ct_slices WHERE study_id = ? AND plane = 'axial' ORDER BY slice_index",
                (study_id,),
            ).fetchall()
            coronal = connection.execute(
                "SELECT slice_index, image_path FROM ct_slices WHERE study_id = ? AND plane = 'coronal' ORDER BY slice_index",
                (study_id,),
            ).fetchall()
            sagittal = connection.execute(
                "SELECT slice_index, image_path FROM ct_slices WHERE study_id = ? AND plane = 'sagittal' ORDER BY slice_index",
                (study_id,),
            ).fetchall()

        if not axial:
            self._status = "病例没有可用的轴位 PNG"
            self.changed.emit()
            return

        axial_paths = [self._resolve_image_path(row["image_path"]) for row in axial]
        coronal_paths = [self._resolve_image_path(row["image_path"]) for row in coronal]
        sagittal_paths = [self._resolve_image_path(row["image_path"]) for row in sagittal]
        self._plane_paths = {"axial": axial_paths, "coronal": coronal_paths, "sagittal": sagittal_paths}

        self._slice_count = len(axial)
        self._png_directory = axial_paths[0].parent
        self._coronal_directory = coronal_paths[0].parent if coronal_paths else None
        self._sagittal_directory = sagittal_paths[0].parent if sagittal_paths else None
        self._slice_index = max(0, self._slice_count // 2)
        self._coronal_count = len(coronal)
        self._sagittal_count = len(sagittal)
        self._coronal_index = max(0, self._coronal_count // 2)
        self._sagittal_index = max(0, self._sagittal_count // 2)
        self._preview_path = QUrl.fromLocalFile(str(axial_paths[self._slice_index])).toString()
        self._coronal_path = QUrl.fromLocalFile(str(coronal_paths[self._coronal_index])).toString() if coronal_paths else ""
        self._sagittal_path = QUrl.fromLocalFile(str(sagittal_paths[self._sagittal_index])).toString() if sagittal_paths else ""
        self._study_id = int(study_id)
        self._patient_text = f"{study['patient_name']}  ·  ID {study['patient_id']}"
        self._institution_text = study["institution_name"]
        self._study_text = study["study_description"] or study["series_description"]
        self._source_directory = study["source_directory"] or ""
        self._metadata_text = (
            f"序列：{study['series_description']}\n"
            f"尺寸：{study['columns']} × {study['rows']} px\n"
            f"切片：{study['slice_count']} 张\n"
            f"数据库病例：#{study_id}"
        )
        try:
            import json
            self._calibration = json.loads(study["metadata_json"] or "{}")
        except (TypeError, ValueError):
            self._calibration = {}
        self.calibrationChanged.emit(dict(self._calibration))
        self._status = f"已从数据库加载病例 #{study_id}"
        self.changed.emit()

    def _resolve_image_path(self, stored_path: str) -> Path:
        original = Path(stored_path)
        if original.is_file():
            return original
        parts = PureWindowsPath(stored_path).parts if "\\" in stored_path else original.parts
        for index in range(len(parts) - 1):
            if parts[index].casefold() == "data" and parts[index + 1].casefold() == "converted_ct":
                candidate = self._project_directory.joinpath(*parts[index:])
                if candidate.is_file():
                    return candidate
        return original

    @Slot(object)
    def _completed(self, result: object) -> None:
        self._busy = False
        self._preview_path = QUrl.fromLocalFile(result.preview_path).toString()
        self._png_directory = Path(result.output_directory) / "png"
        self._coronal_directory = Path(result.coronal_directory)
        self._sagittal_directory = Path(result.sagittal_directory)
        self._plane_paths = {"axial": [], "coronal": [], "sagittal": []}
        self._slice_count = result.slice_count
        self._slice_index = max(0, result.slice_count // 2)
        self._coronal_count = result.metadata["columns"]
        self._sagittal_count = result.metadata["rows"]
        self._coronal_index = self._coronal_count // 2
        self._sagittal_index = self._sagittal_count // 2
        self._preview_path = self._slice_url(self._slice_index)
        self._coronal_path = self._mpr_url(self._coronal_directory, self._coronal_index, self._coronal_count)
        self._sagittal_path = self._mpr_url(self._sagittal_directory, self._sagittal_index, self._sagittal_count)
        self._status = f"已完成：{result.slice_count} 张 PNG 切片"
        try:
            study_id = save_ct_result(result)
            self._study_id = int(study_id)
            self._status += f" · 已写入数据库 #{study_id}"
            self.imported.emit()
        except Exception as exc:
            self._status += f" · 数据库写入失败：{exc}"
        metadata = result.metadata
        self._calibration = dict(metadata)
        self.calibrationChanged.emit(dict(self._calibration))
        self._patient_text = f"{metadata['patient_name']}  ·  ID {metadata['patient_id']}"
        self._institution_text = metadata["institution_name"]
        self._study_text = metadata["study_description"]
        self._source_directory = str(metadata.get("source_directory") or "")
        spacing = " × ".join(str(item) for item in metadata["pixel_spacing_mm"]) or "未提供"
        self._metadata_text = (
            f"序列：{metadata['series_description']}\n"
            f"尺寸：{metadata['columns']} × {metadata['rows']} px\n"
            f"切片：{metadata['slice_count']} 张 · 厚度 {metadata['slice_thickness_mm']} mm\n"
            f"像素间距：{spacing} mm\n"
            f"窗位 / 窗宽：{metadata['window_center_hu']} / {metadata['window_width_hu']} HU\n"
            f"输出：{result.output_directory}"
        )
        self.changed.emit()

    def _slice_url(self, index: int) -> str:
        if self._png_directory is None or self._slice_count <= 0:
            return ""
        index = max(0, min(self._slice_count - 1, index))
        return QUrl.fromLocalFile(str(self._png_directory / f"slice_{index + 1:04d}.png")).toString()

    def _mpr_url(self, directory: Path | None, index: int, count: int) -> str:
        if directory is None or count <= 0:
            return ""
        index = max(0, min(count - 1, index))
        return QUrl.fromLocalFile(str(directory / f"slice_{index + 1:04d}.png")).toString()

    @Slot(str, int, result=str)
    def slicePath(self, plane: str, index: int) -> str:
        paths = self._plane_paths.get(plane, [])
        if paths and 0 <= index < len(paths):
            return QUrl.fromLocalFile(str(paths[index])).toString()
        if plane == "axial" and 0 <= index < self._slice_count:
            return self._slice_url(index)
        if plane == "coronal" and 0 <= index < self._coronal_count:
            return self._mpr_url(self._coronal_directory, index, self._coronal_count)
        if plane == "sagittal" and 0 <= index < self._sagittal_count:
            return self._mpr_url(self._sagittal_directory, index, self._sagittal_count)
        return ""

    @Slot()
    def nextSlice(self) -> None:
        if self._slice_count:
            self._slice_index = min(self._slice_count - 1, self._slice_index + 1)
            self._preview_path = self._slice_url(self._slice_index)
            self.changed.emit()

    @Slot()
    def previousSlice(self) -> None:
        if self._slice_count:
            self._slice_index = max(0, self._slice_index - 1)
            self._preview_path = self._slice_url(self._slice_index)
            self.changed.emit()

    @Slot(int)
    def setSlice(self, index: int) -> None:
        if self._slice_count:
            self._slice_index = max(0, min(self._slice_count - 1, index))
            self._preview_path = self._slice_url(self._slice_index)
            self.changed.emit()

    @Slot()
    def nextCoronal(self) -> None:
        if self._coronal_count:
            self._coronal_index = min(self._coronal_count - 1, self._coronal_index + 1)
            self._coronal_path = self._mpr_url(self._coronal_directory, self._coronal_index, self._coronal_count)
            self.changed.emit()

    @Slot()
    def previousCoronal(self) -> None:
        if self._coronal_count:
            self._coronal_index = max(0, self._coronal_index - 1)
            self._coronal_path = self._mpr_url(self._coronal_directory, self._coronal_index, self._coronal_count)
            self.changed.emit()

    @Slot()
    def nextSagittal(self) -> None:
        if self._sagittal_count:
            self._sagittal_index = min(self._sagittal_count - 1, self._sagittal_index + 1)
            self._sagittal_path = self._mpr_url(self._sagittal_directory, self._sagittal_index, self._sagittal_count)
            self.changed.emit()

    @Slot()
    def previousSagittal(self) -> None:
        if self._sagittal_count:
            self._sagittal_index = max(0, self._sagittal_index - 1)
            self._sagittal_path = self._mpr_url(self._sagittal_directory, self._sagittal_index, self._sagittal_count)
            self.changed.emit()

    @Slot(str)
    def _failed(self, message: str) -> None:
        self._busy = False
        self._status = f"转换失败：{message}"
        self.changed.emit()

    def shutdown(self) -> None:
        self._thread.quit()
        self._thread.wait(2000)
