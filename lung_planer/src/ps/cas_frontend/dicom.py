"""Convert a DICOM CT series into windowed PNG slices and safe metadata."""

import json
import os
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import pydicom
from PIL import Image


@dataclass(frozen=True)
class ConversionResult:
    source_directory: str
    output_directory: str
    slice_count: int
    preview_path: str
    coronal_path: str
    sagittal_path: str
    coronal_directory: str
    sagittal_directory: str
    metadata_path: str
    metadata: dict[str, Any]


def _text(value: Any, fallback: str = "未提供") -> str:
    return str(value) if value not in (None, "") else fallback


def _number(value: Any, default: float) -> float:
    if isinstance(value, (list, tuple)):
        value = value[0]
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _series_files(source_directory: Path) -> list[Path]:
    files = sorted(source_directory.rglob("*.dcm"))
    if not files:
        raise ValueError("未在所选目录中找到 .dcm 文件")

    def position(path: Path) -> float:
        try:
            dataset = pydicom.dcmread(path, stop_before_pixels=True, specific_tags=["ImagePositionPatient", "InstanceNumber"])
            image_position = getattr(dataset, "ImagePositionPatient", None)
            if image_position and len(image_position) >= 3:
                return float(image_position[2])
            return float(getattr(dataset, "InstanceNumber", 0))
        except Exception:
            return 0.0

    return sorted(files, key=position)


def _render_slice(dataset: pydicom.Dataset, window_center: float, window_width: float) -> Image.Image:
    pixels = dataset.pixel_array.astype(np.float32)
    pixels = pixels * _number(getattr(dataset, "RescaleSlope", 1), 1) + _number(getattr(dataset, "RescaleIntercept", 0), 0)
    low = window_center - window_width / 2
    high = window_center + window_width / 2
    pixels = np.clip((pixels - low) / (high - low), 0, 1)
    return Image.fromarray((pixels * 255).astype(np.uint8), mode="L")


def convert_ct_series(source: str | Path, destination: str | Path, *, window_center: float | None = None, window_width: float | None = None) -> ConversionResult:
    source_directory = Path(source).expanduser().resolve()
    destination_directory = Path(destination).expanduser().resolve()
    if not source_directory.is_dir():
        raise ValueError("选择的 CT 目录不存在")

    files = _series_files(source_directory)
    first = pydicom.dcmread(files[0], stop_before_pixels=True)
    center = window_center if window_center is not None else _number(getattr(first, "WindowCenter", 40), 40)
    width = window_width if window_width is not None else _number(getattr(first, "WindowWidth", 400), 400)
    if width <= 0:
        raise ValueError("窗宽必须大于 0")

    png_directory = destination_directory / "png"
    png_directory.mkdir(parents=True, exist_ok=True)
    volume_slices = []
    for index, path in enumerate(files, start=1):
        dataset = pydicom.dcmread(path)
        rendered = _render_slice(dataset, center, width)
        rendered.save(png_directory / f"slice_{index:04d}.png", optimize=False, compress_level=1)
        volume_slices.append(np.asarray(rendered))

    volume = np.stack(volume_slices, axis=0)
    pixel_spacing = [float(item) for item in getattr(first, "PixelSpacing", [1, 1])]
    slice_spacing = _number(getattr(first, "SpacingBetweenSlices", None), _number(getattr(first, "SliceThickness", 1), 1))
    mpr_height = max(1, round(len(files) * slice_spacing / max(pixel_spacing[0], 0.001)))
    coronal = Image.fromarray(volume[:, volume.shape[1] // 2, :], mode="L").resize((volume.shape[2], mpr_height), Image.Resampling.BILINEAR)
    sagittal = Image.fromarray(volume[:, :, volume.shape[2] // 2], mode="L").resize((volume.shape[1], mpr_height), Image.Resampling.BILINEAR)
    coronal_path = destination_directory / "coronal_mid.png"
    sagittal_path = destination_directory / "sagittal_mid.png"
    coronal.save(coronal_path, optimize=False, compress_level=1)
    sagittal.save(sagittal_path, optimize=False, compress_level=1)

    coronal_directory = destination_directory / "coronal"
    sagittal_directory = destination_directory / "sagittal"
    coronal_directory.mkdir(exist_ok=True)
    sagittal_directory.mkdir(exist_ok=True)
    def save_coronal(index: int) -> None:
        plane = Image.fromarray(volume[:, :, index], mode="L").resize((volume.shape[1], mpr_height), Image.Resampling.BILINEAR)
        plane.save(coronal_directory / f"slice_{index + 1:04d}.png", optimize=False, compress_level=1)

    def save_sagittal(index: int) -> None:
        plane = Image.fromarray(volume[:, index, :], mode="L").resize((volume.shape[2], mpr_height), Image.Resampling.BILINEAR)
        plane.save(sagittal_directory / f"slice_{index + 1:04d}.png", optimize=False, compress_level=1)

    worker_count = max(1, min(4, int(os.environ.get("CLOUD_BREATHING_CT_WORKERS", "4"))))
    with ThreadPoolExecutor(max_workers=worker_count) as pool:
        list(pool.map(save_coronal, range(volume.shape[2])))
        list(pool.map(save_sagittal, range(volume.shape[1])))

    preview_index = len(files) // 2 + 1
    metadata = {
        "format": "DICOM CT",
        "slice_count": len(files),
        "rows": int(getattr(first, "Rows", 0)),
        "columns": int(getattr(first, "Columns", 0)),
        "pixel_spacing_mm": pixel_spacing,
        "slice_spacing_mm": slice_spacing,
        "slice_thickness_mm": _number(getattr(first, "SliceThickness", None), 0),
        "series_description": _text(getattr(first, "SeriesDescription", None)),
        "modality": _text(getattr(first, "Modality", None)),
        "manufacturer": _text(getattr(first, "Manufacturer", None)),
        "patient_name": _text(getattr(first, "PatientName", None)),
        "patient_id": _text(getattr(first, "PatientID", None)),
        "institution_name": _text(getattr(first, "InstitutionName", None)),
        "station_name": _text(getattr(first, "StationName", None)),
        "study_description": _text(getattr(first, "StudyDescription", None)),
        "window_center_hu": center,
        "window_width_hu": width,
        "preview_slice": preview_index,
        "source_directory": str(source_directory),
        "privacy_note": "metadata.json 包含本地病例显示所需的 PatientName、PatientID 和 InstitutionName，请勿对外传输。",
    }
    metadata_path = destination_directory / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    return ConversionResult(
        source_directory=str(source_directory),
        output_directory=str(destination_directory),
        slice_count=len(files),
        preview_path=str(png_directory / f"slice_{preview_index:04d}.png"),
        coronal_path=str(coronal_path),
        sagittal_path=str(sagittal_path),
        coronal_directory=str(coronal_directory),
        sagittal_directory=str(sagittal_directory),
        metadata_path=str(metadata_path),
        metadata=metadata,
    )
