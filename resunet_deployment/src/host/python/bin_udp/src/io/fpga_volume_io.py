"""Single-volume INT8 BIN and fixed-point input-grid adaptation."""

import json
from pathlib import Path

import numpy as np

from .prediction_io import file_sha256


def load_volume(path, metadata_path):
    metadata = json.loads(Path(metadata_path).read_text(encoding="utf-8"))
    spec = metadata["model_input"]
    shape = spec["shape"]
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"])
    if (spec["dtype"] != "int8" or spec["layout"] != "Z,Y,X" or len(shape) != 3
            or any(type(n) is not int or n < 1 for n in shape) or shape[1:] != [512, 512]
            or metadata["shape_z_y_x"] != shape or spec["hu_clip"] != [-1024.0, 1000.0]
            or affine.shape != (4, 4) or not np.isfinite(affine).all()
            or not np.allclose(affine[3], [0, 0, 0, 1]) or abs(np.linalg.det(affine[:3, :3])) < 1e-10):
        raise ValueError("Expected signed INT8 [Z,512,512] with verified physical coordinates")
    path = Path(path)
    if path.stat().st_size != int(np.prod(shape)) or spec["sha256"] != file_sha256(path):
        raise ValueError("CT volume BIN size/SHA256 mismatch")
    return np.memmap(path, mode="r", dtype=np.int8, shape=tuple(shape)), metadata


def prepare_volume(legacy_directory, destination):
    """Reuse existing quantized center slices; never duplicate source CT archives."""
    source = Path(legacy_directory)
    metadata = json.loads((source / "metadata.json").read_text(encoding="utf-8"))
    spec = metadata["model_input"]
    if spec["dtype"] != "int8" or spec["layout"] != "Z,C,H,W" or spec["shape"][1:] != [3, 512, 512]:
        raise ValueError("Expected existing three-neighbor INT8 input")
    original = source / spec["file"]
    if original.stat().st_size != int(np.prod(spec["shape"])):
        raise ValueError("Existing input BIN size mismatch")
    volume = np.memmap(original, mode="r", dtype=np.int8, shape=tuple(spec["shape"]))[:, 1]
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    path = destination / "ct_volume_int8.bin"
    temporary = path.with_suffix(".bin.tmp")
    volume.tofile(temporary)
    temporary.replace(path)
    metadata["model_input"] = {**spec, "file": path.name, "layout": "Z,Y,X",
        "shape": list(volume.shape), "sha256": file_sha256(path),
        "bytes": path.stat().st_size, "status": "FPGA volume storage; three neighbors gathered on demand"}
    metadata["derived_from"] = {"input_bin": str(original), "sha256": file_sha256(original)}
    metadata["anatomical_z_direction"] = metadata.get("anatomical_z_direction", int(np.sign(metadata["affine_z_y_x_to_lps_mm"][2][0])))
    metadata_path = destination / "metadata.json"
    metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    return path, metadata_path


def round_even_numpy(value, shift):
    magnitude = np.abs(value)
    whole, remainder = magnitude >> shift, magnitude & ((1 << shift) - 1)
    half = 1 << (shift - 1)
    increment = (remainder > half) | ((remainder == half) & ((whole & 1) != 0))
    return (whole + increment) * np.sign(value)


def resample_int8(volume, shape):
    """Align-corners trilinear interpolation, Q16 coordinates, one final RNE.

    This is explicitly fixed-point preprocessing, not the original SciPy FP32 interpolation.
    The three coefficient products and INT8 samples fit in signed INT64 (<2**56).
    """
    if tuple(shape) == volume.shape:
        return volume
    value = volume
    shifts = 0
    for axis in (2, 1, 0):
        old, new = value.shape[axis], int(shape[axis])
        if old == new:
            continue
        numerator = np.arange(new, dtype=np.int64) * (old - 1) * 65536
        denominator = max(new - 1, 1)
        coordinate, remainder = np.divmod(numerator, denominator)
        coordinate += (remainder * 2 > denominator) | ((remainder * 2 == denominator) & ((coordinate & 1) != 0))
        low, fraction = coordinate >> 16, coordinate & 65535
        high = np.minimum(low + 1, old - 1)
        weights_shape = [1] * 3
        weights_shape[axis] = new
        fraction = fraction.reshape(weights_shape)
        first = np.take(value, low, axis=axis).astype(np.int64)
        second = np.take(value, high, axis=axis).astype(np.int64)
        value = first * (65536 - fraction) + second * fraction
        shifts += 16
    return round_even_numpy(value, shifts).clip(-128, 127).astype(np.int8)


def restore_labels(labels, shape):
    """Nearest-neighbor return to source CT grid, integer address calculation."""
    for axis in (2, 1, 0):
        old, new = labels.shape[axis], int(shape[axis])
        if old != new:
            denominator = max(new - 1, 1)
            indices = (2 * np.arange(new, dtype=np.int64) * (old - 1) + denominator) // (2 * denominator)
            labels = np.take(labels, indices, axis=axis)
    return labels
