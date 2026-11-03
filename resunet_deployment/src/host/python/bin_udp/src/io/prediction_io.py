"""Headerless segmentation BIN contract, independent of network weights and STL."""

import hashlib
import json
from pathlib import Path

import numpy as np


CHANNELS = ["LeftUpperLobe", "LeftLowerLobe", "RightUpperLobe", "RightMiddleLobe", "RightLowerLobe",
            "Bronchus", "PulmonaryArtery", "PulmonaryVenous", "LungTumor"]


def file_sha256(path):
    with Path(path).open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def write_prediction(directory, masks, affine, provenance):
    """Write native CT masks in Z,C,Y,X order; publish metadata last."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    shape = masks[0].shape
    if len(masks) != len(CHANNELS) or len(shape) != 3 or any(m.shape != shape for m in masks):
        raise ValueError("Expected nine masks on the same Z,Y,X grid")
    temporary = directory / "segmentation_uint8.bin.tmp"
    with temporary.open("wb") as file:
        for z in range(shape[0]):
            plane = np.stack([m[z] for m in masks])
            if not np.isin(plane, [0, 1]).all():
                raise ValueError("Segmentation BIN accepts only 0/1 masks")
            plane.astype(np.uint8).tofile(file)
    path = directory / "segmentation_uint8.bin"
    temporary.replace(path)
    metadata = {"format": "ct-segmentation-v1", "file": path.name, "dtype": "uint8",
                "layout": "Z,C,Y,X", "order": "C", "shape": [shape[0], len(CHANNELS), *shape[1:]],
                "channels": CHANNELS, "values": {"background": 0, "foreground": 1},
                "coordinate_system": "DICOM LPS millimetres",
                "affine_z_y_x_to_lps_mm": np.asarray(affine).tolist(),
                "bytes": path.stat().st_size, "sha256": file_sha256(path),
                "semantics": "thresholded model masks; lobe/artery-vein overlaps resolved within each task; no repair or smoothing",
                "provenance": provenance}
    temporary = directory / "metadata.json.tmp"
    temporary.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(directory / "metadata.json")
    return metadata


def read_prediction(directory):
    directory = Path(directory)
    metadata = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
    if metadata.get("format") == "ct-segmentation-bitmask-v2":
        return read_packed_prediction(directory, metadata)
    if (metadata.get("format") != "ct-segmentation-v1" or metadata.get("dtype") != "uint8"
            or metadata.get("layout") != "Z,C,Y,X" or metadata.get("order") != "C"
            or metadata.get("channels") != CHANNELS
            or metadata.get("coordinate_system") != "DICOM LPS millimetres"):
        raise ValueError("Unsupported segmentation BIN format, channels or coordinate system")
    shape = metadata.get("shape", [])
    if (len(shape) != 4 or any(type(n) is not int or n <= 0 for n in shape)
            or shape[1] != len(CHANNELS)):
        raise ValueError("Invalid segmentation BIN dimensions")
    affine = np.asarray(metadata.get("affine_z_y_x_to_lps_mm"), dtype=np.float64)
    if (affine.shape != (4, 4) or not np.isfinite(affine).all()
            or not np.allclose(affine[3], [0, 0, 0, 1]) or abs(np.linalg.det(affine[:3, :3])) < 1e-10):
        raise ValueError("Invalid CT affine")
    path = directory / "segmentation_uint8.bin"
    if path.stat().st_size != int(np.prod(shape)) or metadata.get("bytes") != path.stat().st_size:
        raise ValueError("Segmentation BIN byte count does not match dimensions")
    if file_sha256(path) != metadata.get("sha256"):
        raise ValueError("Segmentation BIN SHA256 mismatch")
    masks = np.memmap(path, dtype=np.uint8, mode="r", shape=tuple(shape))
    if any(np.any(plane > 1) for plane in masks):
        raise ValueError("Segmentation BIN contains values other than 0/1")
    return masks, metadata


def validate_bits(plane):
    lobes = plane & 31
    if (np.any(plane > 511) or np.any(lobes & (lobes - 1)) or
            np.any((plane & 192) == 192)):
        raise ValueError("Invalid reserved bits or overlapping lobe/artery-vein labels")


def write_packed_prediction(directory, packed, affine, provenance):
    """Nine independent mask bits per voxel, little-endian UINT16 Z,Y,X."""
    if packed.dtype != np.uint16 or packed.ndim != 3 or min(packed.shape) < 1:
        raise ValueError("Expected UINT16 Z,Y,X segmentation")
    for plane in packed:
        validate_bits(plane)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    temporary = directory / "segmentation_uint16.bin.tmp"
    packed.astype("<u2", copy=False).tofile(temporary)
    path = directory / "segmentation_uint16.bin"
    temporary.replace(path)
    metadata = {"format": "ct-segmentation-bitmask-v2", "file": path.name,
                "dtype": "uint16", "byte_order": "little_endian", "layout": "Z,Y,X",
                "order": "C", "shape": list(packed.shape), "channels": CHANNELS,
                "channel_bits": list(range(9)), "reserved_bits": list(range(9, 16)),
                "coordinate_system": "DICOM LPS millimetres",
                "affine_z_y_x_to_lps_mm": np.asarray(affine).tolist(),
                "bytes": path.stat().st_size, "sha256": file_sha256(path),
                "semantics": "INT16 logits >=0; maximum nonnegative logit within lobe/vessel tasks; no repair or smoothing",
                "provenance": provenance}
    temporary = directory / "metadata.json.tmp"
    temporary.write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(directory / "metadata.json")
    return metadata


def read_packed_prediction(directory, metadata):
    shape = metadata.get("shape", [])
    affine = np.asarray(metadata.get("affine_z_y_x_to_lps_mm"), dtype=np.float64)
    if (metadata.get("dtype") != "uint16" or metadata.get("byte_order") != "little_endian"
            or metadata.get("layout") != "Z,Y,X" or metadata.get("order") != "C"
            or metadata.get("channels") != CHANNELS or metadata.get("channel_bits") != list(range(9))
            or metadata.get("coordinate_system") != "DICOM LPS millimetres"
            or len(shape) != 3 or any(type(n) is not int or n <= 0 for n in shape)
            or affine.shape != (4, 4) or not np.isfinite(affine).all()
            or not np.allclose(affine[3], [0, 0, 0, 1]) or abs(np.linalg.det(affine[:3, :3])) < 1e-10):
        raise ValueError("Unsupported packed segmentation contract or CT affine")
    path = directory / "segmentation_uint16.bin"
    if path.stat().st_size != int(np.prod(shape)) * 2 or metadata.get("bytes") != path.stat().st_size:
        raise ValueError("Packed segmentation byte count does not match dimensions")
    if file_sha256(path) != metadata.get("sha256"):
        raise ValueError("Packed segmentation SHA256 mismatch")
    packed = np.memmap(path, dtype="<u2", mode="r", shape=tuple(shape))
    for plane in packed:
        validate_bits(plane)
    return packed, metadata


def prediction_mask(prediction, channel):
    if prediction.ndim == 3:
        return (prediction & (1 << channel)) != 0
    return prediction[:, channel].astype(bool)
