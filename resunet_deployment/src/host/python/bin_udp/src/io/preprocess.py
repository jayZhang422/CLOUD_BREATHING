"""Create a provisional 2.5D INT8 input stream from an HU volume."""

from pathlib import Path

import numpy as np


def write_int8_input(volume: np.ndarray, path: Path, hu_min: float, hu_max: float) -> dict:
    if not np.isfinite([hu_min, hu_max]).all() or hu_min >= hu_max:
        raise ValueError("HU range must contain two finite, increasing values")

    quantized = np.empty(volume.shape, dtype=np.int8)
    for index, image in enumerate(volume):
        clipped = np.clip(image, hu_min, hu_max)
        quantized[index] = (
            np.rint((clipped - hu_min) * 255 / (hu_max - hu_min)).astype(np.int16) - 128
        )

    depth, height, width = volume.shape
    with path.open("wb") as stream:
        for index in range(depth):
            neighbors = np.clip(np.arange(index - 1, index + 2), 0, depth - 1)
            stream.write(quantized[neighbors].tobytes(order="C"))

    expected_bytes = depth * 3 * height * width
    if path.stat().st_size != expected_bytes:
        raise OSError(f"Input size mismatch: expected {expected_bytes} bytes")

    return {
        "file": path.name,
        "dtype": "int8",
        "layout": "Z,C,H,W",
        "shape": [depth, 3, height, width],
        "slice_index_range": [0, depth - 1],
        "channel_offsets_z": [-1, 0, 1],
        "edge_policy": "repeat_boundary_slice",
        "byte_order": "not_applicable_to_int8",
        "hu_clip": [hu_min, hu_max],
        "mapping": "round((clip(HU)-hu_min)*255/(hu_max-hu_min))-128",
        "status": (
            "provisional; train and quantize the model with this exact "
            "preprocessing before FPGA use"
        ),
    }
