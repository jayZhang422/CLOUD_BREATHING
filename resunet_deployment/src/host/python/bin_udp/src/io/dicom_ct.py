"""Read one DICOM CT series into an HU volume with its spatial geometry."""

from hashlib import sha256
from pathlib import Path
from zipfile import ZipFile
from io import BytesIO

import numpy as np
import pydicom


def load_ct_series(data_dir: Path, series_uid: str | None = None) -> tuple[np.ndarray, dict]:
    if data_dir.is_file() and data_dir.suffix.lower() == ".zip":
        with ZipFile(data_dir) as archive:
            files = sorted(name for name in archive.namelist() if name.lower().endswith(".dcm"))
            datasets = [pydicom.dcmread(BytesIO(archive.read(name))) for name in files]
    else:
        files = sorted(path for path in data_dir.iterdir() if path.suffix.lower() == ".dcm")
        datasets = [pydicom.dcmread(path) for path in files]
    if not files:
        raise ValueError(f"No .dcm files found in {data_dir}")

    series: dict[str, list] = {}
    for path, ds in zip(files, datasets):
        if getattr(ds, "Modality", None) != "CT" or "PixelData" not in ds:
            continue
        if int(getattr(ds, "NumberOfFrames", 1)) != 1:
            raise ValueError(f"Multi-frame DICOM is not supported: {path}")
        uid = str(ds.SeriesInstanceUID)
        series.setdefault(uid, []).append(ds)

    if not series:
        raise ValueError("No single-frame CT image series found")
    if series_uid is None:
        if len(series) != 1:
            raise ValueError(
                f"Found multiple CT series; specify --series-uid from: {', '.join(series)}"
            )
        series_uid = next(iter(series))
    if series_uid not in series:
        raise ValueError(f"Series UID {series_uid} was not found")

    slices = series[series_uid]
    if len(slices) < 2:
        raise ValueError("At least two CT slices are required to determine slice spacing")

    first = slices[0]
    orientation = np.asarray(first.ImageOrientationPatient, dtype=np.float64)
    pixel_spacing = np.asarray(first.PixelSpacing, dtype=np.float64)
    if orientation.shape != (6,) or pixel_spacing.shape != (2,):
        raise ValueError("Invalid DICOM orientation or pixel spacing")
    column_axis, row_axis = orientation[:3], orientation[3:]
    normal = np.cross(column_axis, row_axis)
    if (not np.allclose(np.linalg.norm(orientation.reshape(2, 3), axis=1), 1, atol=1e-3)
            or not np.isclose(np.linalg.norm(normal), 1, atol=1e-3)
            or np.any(pixel_spacing <= 0)):
        raise ValueError("Invalid DICOM direction vectors or pixel spacing")

    positions = []
    for ds in slices:
        if (int(ds.Rows) != int(first.Rows) or int(ds.Columns) != int(first.Columns)
                or not np.allclose(ds.ImageOrientationPatient, orientation, atol=1e-4)
                or not np.allclose(ds.PixelSpacing, pixel_spacing, atol=1e-4)):
            raise ValueError("Inconsistent CT image shape, orientation or pixel spacing")
        position = np.asarray(ds.ImagePositionPatient, dtype=np.float64)
        if position.shape != (3,):
            raise ValueError("Invalid DICOM image position")
        positions.append(position)

    order = np.argsort(np.asarray(positions) @ normal)
    slices = [slices[i] for i in order]
    positions = np.asarray(positions)[order]
    steps = np.diff(positions, axis=0)
    slice_step = steps.mean(axis=0)
    projected_spacing = float(slice_step @ normal)
    if projected_spacing <= 0 or not np.allclose(
        steps, slice_step, atol=max(0.1, projected_spacing * 0.02)
    ):
        raise ValueError("Duplicate or unevenly spaced CT slices; inspect the DICOM series")

    hu_slices = []
    slopes = []
    intercepts = []
    for ds in slices:
        pixels = ds.pixel_array.astype(np.float32)
        slope = float(getattr(ds, "RescaleSlope", 1))
        intercept = float(getattr(ds, "RescaleIntercept", 0))
        hu_slices.append(pixels * slope + intercept)
        slopes.append(slope)
        intercepts.append(intercept)
    volume = np.stack(hu_slices)

    # Array axes are (slice, row, column); DICOM patient coordinates are LPS millimetres.
    affine = np.eye(4, dtype=np.float64)
    affine[:3, 0] = slice_step
    affine[:3, 1] = row_axis * pixel_spacing[0]
    affine[:3, 2] = column_axis * pixel_spacing[1]
    affine[:3, 3] = positions[0]
    metadata = {
        "series_id": sha256(series_uid.encode()).hexdigest()[:16],
        "shape_z_y_x": list(volume.shape),
        "dtype": "float32",
        "value_unit": "HU",
        "coordinate_system": "DICOM LPS",
        "affine_z_y_x_to_lps_mm": affine.tolist(),
        "spacing_z_y_x_mm": [projected_spacing, *pixel_spacing.tolist()],
        "slice_positions_lps_mm": positions.tolist(),
        "rescale_slope_by_slice": slopes,
        "rescale_intercept_by_slice": intercepts,
        "resampled": False,
        "cropped": False,
        "anatomical_z_direction": 1 if slice_step[2] > 0 else -1,
        "slice_order_basis": "DICOM ImagePositionPatient projected onto ImageOrientationPatient normal",
        "source_dicom": str(data_dir.resolve()),
    }
    return volume, metadata
