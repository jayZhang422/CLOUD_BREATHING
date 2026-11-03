"""DICOM CT series -> single signed-int8 volume BIN per the frozen contract.

Output layout (doc §3.3): raw [N, 512, 512] Z,Y,X row-major, dtype int8,
no file header; byte_offset = z*262144 + y*512 + x.
"""

from hashlib import sha256
import json
from pathlib import Path
from time import perf_counter
import zlib

import numpy as np
import pydicom

from src.protocol import HEIGHT, HU_MAX, HU_MIN, SLICE_BYTES, WIDTH

QUANTIZATION_FORMULA = "int8(rint((clip(HU, -1024, 1000) + 1024) * 255 / 2024) - 128)"


def quantize_hu(hu: np.ndarray) -> np.ndarray:
    """Frozen HU -> signed int8 rule; uint8 reinterpretation is not allowed."""
    clipped = np.clip(hu, HU_MIN, HU_MAX)
    rounded = np.rint((clipped + 1024) * 255 / 2024)
    quantized = rounded.astype(np.int16) - 128
    return quantized.astype(np.int8)


def load_ct_series(data_dir: Path, series_uid: str | None = None
                   ) -> tuple[np.ndarray, dict]:
    """Read one single-frame CT series as a float32 HU volume [N, rows, cols]."""
    files = sorted(path for path in data_dir.iterdir() if path.suffix.lower() == ".dcm")
    if not files:
        raise ValueError(f"no .dcm files found in {data_dir}")

    series: dict[str, list] = {}
    for path in files:
        dataset = pydicom.dcmread(path)
        if getattr(dataset, "Modality", None) != "CT" or "PixelData" not in dataset:
            continue
        if int(getattr(dataset, "NumberOfFrames", 1)) != 1:
            raise ValueError(f"multi-frame DICOM is not supported: {path.name}")
        series.setdefault(str(dataset.SeriesInstanceUID), []).append(dataset)

    if not series:
        raise ValueError("no single-frame CT image series found")
    if series_uid is None:
        if len(series) != 1:
            raise ValueError(
                "multiple CT series found; pass --series-uid from: "
                + ", ".join(series)
            )
        series_uid = next(iter(series))
    if series_uid not in series:
        raise ValueError(f"series UID {series_uid} was not found")

    slices = series[series_uid]
    first = slices[0]
    rows, cols = int(first.Rows), int(first.Columns)
    if (rows, cols) != (HEIGHT, WIDTH):
        raise ValueError(f"protocol requires {HEIGHT}x{WIDTH} pixels, series is {rows}x{cols}")

    orientation = np.asarray(first.ImageOrientationPatient, dtype=np.float64)
    normal = np.cross(orientation[:3], orientation[3:])
    positions = []
    for dataset in slices:
        if (int(dataset.Rows), int(dataset.Columns)) != (rows, cols) or not np.allclose(
            dataset.ImageOrientationPatient, orientation, atol=1e-4
        ):
            raise ValueError("inconsistent image shape or orientation inside the series")
        positions.append(
            np.asarray(dataset.ImagePositionPatient, dtype=np.float64) @ normal
        )

    order = np.argsort(np.asarray(positions))
    slices = [slices[i] for i in order]
    steps = np.diff(np.asarray(positions)[order])
    # A single slice has no measured inter-slice spacing.
    spacing_z = None
    if steps.size:
        spacing_z = float(steps.mean())
        if spacing_z <= 0 or not np.allclose(steps, spacing_z, atol=max(0.1, spacing_z * 0.02)):
            raise ValueError("duplicate or unevenly spaced slices; inspect the series")

    hu_volume = np.stack([
        dataset.pixel_array.astype(np.float32) * float(getattr(dataset, "RescaleSlope", 1))
        + float(getattr(dataset, "RescaleIntercept", 0))
        for dataset in slices
    ])
    metadata = {
        "series_uid": series_uid,
        "slice_count": int(hu_volume.shape[0]),
        "rows": rows,
        "columns": cols,
        "spacing_z_y_x_mm": [spacing_z, float(first.PixelSpacing[0]), float(first.PixelSpacing[1])],
    }
    return hu_volume, metadata


def crc32_file(path: Path, limit_bytes: int | None = None) -> int:
    """Stream CRC-32/ISO-HDLC over (optionally the first limit_bytes of) a file."""
    crc = 0
    with path.open("rb") as stream:
        remaining = limit_bytes
        while True:
            chunk_len = 4 * 1024 * 1024 if remaining is None else min(4 * 1024 * 1024, remaining)
            if chunk_len == 0:
                break
            chunk = stream.read(chunk_len)
            if not chunk:
                break
            crc = zlib.crc32(chunk, crc)
            if remaining is not None:
                remaining -= len(chunk)
    return crc & 0xFFFFFFFF


def sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def make_volume_bin(data_dir: Path, out_path: Path,
                    series_uid: str | None = None) -> dict:
    """Write the [N,512,512] int8 BIN plus a sidecar metadata JSON.

    Quantization happens slice by slice to keep peak memory around one
    float32 slice plus one int8 volume.
    """
    started = perf_counter()
    hu_volume, series_meta = load_ct_series(data_dir, series_uid)
    stage_read_s = perf_counter() - started

    quant_start = perf_counter()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    slice_count = series_meta["slice_count"]
    hu_min = float(hu_volume.min())
    hu_max = float(hu_volume.max())
    with out_path.open("wb") as stream:
        for z in range(slice_count):
            stream.write(quantize_hu(hu_volume[z]).tobytes(order="C"))
    stage_write_s = perf_counter() - quant_start

    verify_start = perf_counter()
    total_bytes = out_path.stat().st_size
    if total_bytes != slice_count * SLICE_BYTES:
        raise OSError(f"BIN size mismatch: {total_bytes} != {slice_count} * {SLICE_BYTES}")
    crc = crc32_file(out_path)
    digest = sha256_file(out_path)

    metadata = {
        "source_dir": str(data_dir),
        "file": out_path.name,
        "dtype": "int8",
        "layout": "Z,Y,X row-major",
        "shape": [slice_count, series_meta["rows"], series_meta["columns"]],
        "total_bytes": total_bytes,
        "crc32": crc,
        "sha256": digest,
        "hu_window": [HU_MIN, HU_MAX],
        "quantization": QUANTIZATION_FORMULA,
        "hu_range_in_source": [hu_min, hu_max],
        **series_meta,
        "created": out_path.stat().st_mtime,
        "stage_timings_s": {
            "read_dicom": round(stage_read_s, 3),
            "quantize_write": round(stage_write_s, 3),
            "verify": round(perf_counter() - verify_start, 3),
        },
    }
    sidecar = out_path.with_suffix(".meta.json")
    sidecar.write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
                       encoding="utf-8")
    metadata["meta_file"] = str(sidecar)
    return metadata
