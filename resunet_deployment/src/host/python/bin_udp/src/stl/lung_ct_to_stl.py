"""Run the frozen 2.5D mkdc-ResUNet lobe model and export a smoothed lung STL."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from scipy import ndimage
from scipy import sparse
from skimage.measure import marching_cubes


ROOT = Path(__file__).resolve().parents[2]
LOBES = [
    "lung_upper_lobe_left",
    "lung_lower_lobe_left",
    "lung_upper_lobe_right",
    "lung_middle_lobe_right",
    "lung_lower_lobe_right",
]


class MKDCBlock(nn.Module):
    def __init__(self, in_ch: int, out_ch: int):
        super().__init__()
        self.expand = nn.Sequential(
            nn.Conv2d(in_ch, out_ch, 1, bias=False),
            nn.BatchNorm2d(out_ch),
            nn.ReLU6(inplace=True),
        )
        self.k3 = nn.Conv2d(out_ch, out_ch, 3, padding=1, groups=out_ch, bias=False)
        self.k5 = nn.Conv2d(out_ch, out_ch, 5, padding=2, groups=out_ch, bias=False)
        self.project = nn.Sequential(
            nn.BatchNorm2d(out_ch),
            nn.ReLU6(inplace=True),
            nn.Conv2d(out_ch, out_ch, 1, bias=False),
            nn.BatchNorm2d(out_ch),
        )
        self.skip = (
            nn.Identity()
            if in_ch == out_ch
            else nn.Sequential(nn.Conv2d(in_ch, out_ch, 1, bias=False), nn.BatchNorm2d(out_ch))
        )

    @staticmethod
    def channel_shuffle(x: torch.Tensor) -> torch.Tensor:
        b, c, h, w = x.shape
        if c % 2:
            return x
        return x.reshape(b, 2, c // 2, h, w).transpose(1, 2).reshape(b, c, h, w)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        y = self.expand(x)
        y = self.channel_shuffle(self.k3(y) + self.k5(y))
        return F.relu6(self.project(y) + self.skip(x), inplace=True)


class ResUNet(nn.Module):
    def __init__(self, out_channels: int = 5, base: int = 16):
        super().__init__()
        c = [base, base * 2, base * 4, base * 8]
        self.e1 = MKDCBlock(3, c[0])
        self.e2 = MKDCBlock(c[0], c[1])
        self.e3 = MKDCBlock(c[1], c[2])
        self.mid = MKDCBlock(c[2], c[3])
        self.pool = nn.MaxPool2d(2)
        self.d3 = MKDCBlock(c[3] + c[2], c[2])
        self.d2 = MKDCBlock(c[2] + c[1], c[1])
        self.d1 = MKDCBlock(c[1] + c[0], c[0])
        self.head = nn.Conv2d(c[0], out_channels, 1)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        e1 = self.e1(x)
        e2 = self.e2(self.pool(e1))
        e3 = self.e3(self.pool(e2))
        y = self.mid(self.pool(e3))
        y = self.d3(torch.cat((F.interpolate(y, size=e3.shape[-2:], mode="nearest"), e3), 1))
        y = self.d2(torch.cat((F.interpolate(y, size=e2.shape[-2:], mode="nearest"), e2), 1))
        y = self.d1(torch.cat((F.interpolate(y, size=e1.shape[-2:], mode="nearest"), e1), 1))
        return self.head(y)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_input(bin_path: Path, metadata_path: Path) -> tuple[np.memmap, dict]:
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    spec = metadata["model_input"]
    shape = tuple(int(v) for v in spec["shape"])
    if spec["dtype"] != "int8" or spec["layout"] != "Z,C,H,W" or len(shape) != 4:
        raise ValueError("Expected signed INT8 Z,C,H,W input metadata")
    z, channels, height, width = shape
    if channels != 3 or (height, width) != (512, 512):
        raise ValueError(f"Expected [Z,3,512,512], got {shape}")
    expected = int(np.prod(shape))
    if bin_path.stat().st_size != expected:
        raise ValueError(f"BIN size {bin_path.stat().st_size} != {expected}")
    if metadata.get("shape_z_y_x") != [z, height, width]:
        raise ValueError("BIN and spatial metadata shapes differ")
    if spec["hu_clip"] != [-1024.0, 1000.0]:
        raise ValueError("This model requires HU [-1024,1000]; the legacy BIN window is incompatible")
    if spec["channel_offsets_z"] != [-1, 0, 1] or spec["edge_policy"] != "repeat_boundary_slice":
        raise ValueError("Expected neighboring slices [z-1,z,z+1] with repeated boundaries")
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"], dtype=np.float64)
    if affine.shape != (4, 4) or not np.isfinite(affine).all() or abs(np.linalg.det(affine[:3, :3])) < 1e-8:
        raise ValueError("Invalid voxel-to-LPS affine")
    q = np.memmap(bin_path, dtype=np.int8, mode="r", shape=shape, order="C")
    for index in range(z):
        if (not np.array_equal(q[index, 0], q[max(0, index - 1), 1])
                or not np.array_equal(q[index, 2], q[min(z - 1, index + 1), 1])):
            raise ValueError(f"BIN neighbor order is inconsistent at slice {index}")
    return q, metadata


def load_model(checkpoint: Path, device: torch.device) -> ResUNet:
    state = torch.load(checkpoint, map_location=device, weights_only=False)
    weights = state["model"] if isinstance(state, dict) and "model" in state else state
    base = int(weights["e1.expand.0.weight"].shape[0])
    outputs = int(weights["head.weight"].shape[0])
    model = ResUNet(outputs, base).to(device)
    model.load_state_dict(weights, strict=True)
    model.eval()
    return model


def infer(
    model: ResUNet,
    q: np.memmap,
    device: torch.device,
    batch_size: int,
    threshold: float,
    output_path: Path,
    orientation: str = "nifti-ras",
    spacing: np.ndarray | None = None,
    target_spacing_mm: float = 1.5,
    exclusive_path: Path | None = None,
    anatomical_z_direction: int = 1,
) -> np.memmap:
    if anatomical_z_direction not in (-1, 1):
        raise ValueError("Anatomical slice direction must be +1 (foot to head) or -1 (head to foot)")
    z, _, h, w = q.shape
    centers = q[:, 1]
    if target_spacing_mm > 0:
        if spacing is None:
            raise ValueError("Physical spacing is required for model resampling")
        model_shape = np.maximum(
            2, np.rint((np.asarray((z, h, w)) - 1) * spacing / target_spacing_mm).astype(int) + 1
        )
        centers = np.rint(ndimage.zoom(
            centers.astype(np.float32), model_shape / np.asarray(centers.shape),
            order=1, prefilter=False,
        )).astype(np.int8)
        print(f"[input] training-spacing grid {tuple(centers.shape)}; BIN unchanged", flush=True)
    depth, height, width = centers.shape
    if max(height, width) > 512:
        raise ValueError("Model-space plane exceeds 512; inspect scan size and model spacing")
    outputs = model.head.out_channels if hasattr(model, "head") else len(LOBES)
    native_masks = np.zeros((outputs, depth, height, width), dtype=np.uint8)
    native_labels = np.zeros((depth, height, width), dtype=np.uint8) if exclusive_path else None
    pad_h, pad_w = (512 - height) // 2, (512 - width) // 2
    started = time.perf_counter()
    with torch.inference_mode():
        for start in range(0, depth, batch_size):
            stop = min(start + batch_size, depth)
            offsets = np.array([-1, 0, 1])
            if orientation == "nifti-ras":
                offsets *= anatomical_z_direction
            indices = np.clip(np.arange(start, stop)[:, None] + offsets, 0, depth - 1)
            batch = np.full((stop - start, 3, 512, 512), -128, dtype=np.float32)
            batch[:, :, pad_h:pad_h + height, pad_w:pad_w + width] = centers[indices]
            if orientation == "nifti-ras":
                # Training q.npy is [Z,NIfTI-X,NIfTI-Y], predominantly R,A,S.
                # This DICOM BIN is [Z,Y,X] with L,P,S directions.
                batch = np.ascontiguousarray(batch[..., ::-1, ::-1].swapaxes(-1, -2))
            elif orientation == "transpose":
                # Source-native NIfTI cache H=X,W=Y; keep this CT's LPS signs.
                batch = np.ascontiguousarray(batch.swapaxes(-1, -2))
            logits = model(torch.from_numpy(batch).to(device, non_blocking=True))
            if native_labels is not None:
                maximum, winner = logits.max(dim=1)
                labels = torch.where(maximum >= threshold, winner + 1, 0).cpu().numpy()
                if orientation == "nifti-ras":
                    labels = labels.swapaxes(-1, -2)[..., ::-1, ::-1]
                elif orientation == "transpose":
                    labels = labels.swapaxes(-1, -2)
                native_labels[start:stop] = labels[:, pad_h:pad_h + height, pad_w:pad_w + width]
            prediction = (logits >= threshold).cpu().numpy()
            if orientation == "nifti-ras":
                prediction = prediction.swapaxes(-1, -2)[..., ::-1, ::-1]
            elif orientation == "transpose":
                prediction = prediction.swapaxes(-1, -2)
            prediction = prediction[:, :, pad_h:pad_h + height, pad_w:pad_w + width]
            native_masks[:, start:stop] = prediction.transpose(1, 0, 2, 3)
            if stop % 25 == 0 or stop == depth:
                print(f"[infer] {stop}/{depth} model slices", flush=True)
    masks = np.lib.format.open_memmap(
        output_path, mode="w+", dtype=np.uint8, shape=(outputs, z, h, w)
    )
    for index, native in enumerate(native_masks):
        masks[index] = ndimage.zoom(
            native, np.asarray((z, h, w)) / np.asarray(native.shape), order=0, prefilter=False
        ) if native.shape != (z, h, w) else native
    masks.flush()
    if native_labels is not None:
        labels = ndimage.zoom(native_labels, np.asarray((z, h, w)) / native_labels.shape,
                              order=0, prefilter=False) if native_labels.shape != (z, h, w) else native_labels
        np.save(exclusive_path, labels, allow_pickle=False)
    print(f"[infer] finished in {time.perf_counter() - started:.1f}s", flush=True)
    return masks


def ellipsoid(radius_mm: float, spacing: np.ndarray) -> np.ndarray:
    if radius_mm <= 0:
        return np.ones((1, 1, 1), dtype=bool)
    radii = np.ceil(radius_mm / spacing).astype(int)
    axes = [np.arange(-r, r + 1) * step for r, step in zip(radii, spacing)]
    zz, yy, xx = np.meshgrid(*axes, indexing="ij")
    return (zz * zz + yy * yy + xx * xx <= radius_mm * radius_mm).astype(bool)


def keep_largest(mask: np.ndarray, count: int = 2) -> np.ndarray:
    structure = ndimage.generate_binary_structure(3, 2)
    labels, number = ndimage.label(mask, structure=structure)
    if number <= count:
        return mask
    sizes = ndimage.sum(mask, labels, range(1, number + 1))
    selected = 1 + np.argsort(sizes)[-count:]
    return np.isin(labels, selected)


def body_mask(q: np.memmap, hu_clip: list[float]) -> np.ndarray:
    hu_min, hu_max = hu_clip
    hu = (np.asarray(q[:, 1], dtype=np.float32) + 128.0) * (hu_max - hu_min) / 255.0 + hu_min
    result = np.zeros(hu.shape, dtype=bool)
    structure = ndimage.generate_binary_structure(2, 2)
    for z, image in enumerate(hu):
        foreground = image > -200.0
        labels, count = ndimage.label(foreground, structure=structure)
        if count:
            sizes = ndimage.sum(foreground, labels, range(1, count + 1))
            largest = 1 + int(np.argmax(sizes))
            result[z] = ndimage.binary_fill_holes(labels == largest)
    return result


def smooth_mask(
    raw: np.ndarray,
    spacing: np.ndarray,
    sigma_mm: float,
    closing_mm: float,
    body: np.ndarray,
    minimum_component_voxels: int,
) -> np.ndarray:
    sigma = np.maximum(float(sigma_mm) / spacing, 0.0)
    structure = ndimage.generate_binary_structure(3, 2)
    seeds, count = ndimage.label(keep_largest(raw, 2), structure=structure)
    parts = []
    for index in range(1, count + 1):
        smoothed = ndimage.gaussian_filter(
            (seeds == index).astype(np.float32), sigma=sigma, mode="nearest"
        ) >= 0.5
        if closing_mm > 0:
            smoothed = ndimage.binary_closing(smoothed, structure=ellipsoid(closing_mm, spacing))
        smoothed = ndimage.binary_fill_holes(smoothed) & body
        labels, number = ndimage.label(smoothed, structure=structure)
        if number:
            sizes = ndimage.sum(smoothed, labels, range(1, number + 1))
            smoothed = np.isin(labels, np.flatnonzero(sizes >= minimum_component_voxels) + 1)
        parts.append(keep_largest(smoothed, 1).astype(bool))
    if len(parts) == 2:
        # Preserve the raw prediction's separate lungs through closing and smoothing.
        adjacent = ndimage.generate_binary_structure(3, 3)
        a, b = parts
        parts = [a & ~ndimage.binary_dilation(b, structure=adjacent),
                 b & ~ndimage.binary_dilation(a, structure=adjacent)]
    return np.logical_or.reduce(parts)


def taubin_smooth(vertices: np.ndarray, faces: np.ndarray, iterations: int) -> np.ndarray:
    """Smooth in millimetres; alternate positive/negative steps to limit shrinkage."""
    if iterations == 0:
        return vertices
    edges = np.concatenate((faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]))
    edges = np.unique(np.sort(edges, axis=1), axis=0)
    rows = np.concatenate((edges[:, 0], edges[:, 1]))
    cols = np.concatenate((edges[:, 1], edges[:, 0]))
    adjacency = sparse.csr_matrix(
        (np.ones(len(rows), dtype=np.float64), (rows, cols)),
        shape=(len(vertices), len(vertices)),
    )
    degree = np.asarray(adjacency.sum(axis=1)).ravel()
    average = sparse.diags(1.0 / np.maximum(degree, 1)) @ adjacency
    for _ in range(iterations):
        for factor in (0.5, -0.53):
            vertices = vertices + factor * (average @ vertices - vertices)
    return vertices


def write_stl(
    mask: np.ndarray, affine: np.ndarray, path: Path, step_size: int, iterations: int = 0,
    surface_sigma_mm: float = 0.0, preserve_voxels: bool = False, preserve_volume: bool = False,
) -> dict:
    if not mask.any() or mask.all():
        raise ValueError("Cannot export an empty or all-foreground mask")
    if surface_sigma_mm > 0:
        # Interpolate the continuous field, not a re-thresholded staircase.
        # Extract each lung separately so filtering cannot bridge the mediastinum.
        spacing = np.linalg.norm(affine[:3, :3], axis=0)
        sigma = surface_sigma_mm / spacing
        padding = np.ceil(4 * sigma).astype(int) + step_size
        labels, _ = ndimage.label(mask, ndimage.generate_binary_structure(3, 3))
        vertex_parts, face_parts, offset = [], [], 0
        for index, region in enumerate(ndimage.find_objects(labels), 1):
            starts = np.array([axis.start for axis in region])
            field = np.pad((labels[region] == index).astype(np.float32),
                           [(int(p), int(p)) for p in padding])
            voxel_count = int(np.count_nonzero(field))
            field = ndimage.gaussian_filter(field, sigma, mode="constant")
            if preserve_voxels:
                # Keep thin repaired bridges above the isovalue during field smoothing.
                original = np.pad((labels[region] == index).astype(np.float32),
                                  [(int(p), int(p)) for p in padding])
                field = np.maximum(field, original * .55)
            level = 0.5
            if preserve_volume:
                # Select the contour enclosing the original number of voxels instead
                # of letting a fixed 0.5 contour shrink small lesions under smoothing.
                split = field.size - voxel_count
                ordered = np.partition(field.ravel(), (split - 1, split))
                level = float((ordered[split - 1] + ordered[split]) / 2)
            if field.max() <= level:
                # Keep a small predicted component when the Gaussian would erase it.
                field = np.pad((labels[region] == index).astype(np.float32),
                               [(int(p), int(p)) for p in padding])
                level = 0.5
            v, f, _, _ = marching_cubes(field, level=level, step_size=step_size,
                                        allow_degenerate=False)
            vertex_parts.append(v - padding + starts)
            face_parts.append(f + offset)
            offset += len(v)
        vertices, faces = np.concatenate(vertex_parts), np.concatenate(face_parts)
    else:
        # Padding closes surfaces at scan edges; remove its offset before the affine.
        padding = step_size
        vertices, faces, _, _ = marching_cubes(
            np.pad(mask.astype(np.float32), padding), level=0.5, spacing=(1.0, 1.0, 1.0),
            step_size=step_size, allow_degenerate=False,
        )
        vertices -= padding
    vertices = (affine[:3, :3] @ vertices.T).T + affine[:3, 3]
    faces = faces.astype(np.int32, copy=False)
    vertices = taubin_smooth(vertices, faces, iterations)
    triangles = vertices[faces].astype(np.float32, copy=False)
    signed_volume = np.einsum(
        "ij,ij->i", triangles[:, 0], np.cross(triangles[:, 1], triangles[:, 2])
    ).sum() / 6.0
    if signed_volume < 0:
        faces = faces[:, [0, 2, 1]]
        triangles = vertices[faces].astype(np.float32, copy=False)
    normals = np.cross(triangles[:, 1] - triangles[:, 0], triangles[:, 2] - triangles[:, 0])
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    normals = np.divide(normals, lengths, out=np.zeros_like(normals), where=lengths > 0)
    records = np.empty(len(faces), dtype=np.dtype([
        ("normal", "<f4", (3,)), ("vertices", "<f4", (3, 3)), ("attribute", "<u2")
    ]))
    records["normal"] = normals
    records["vertices"] = triangles
    records["attribute"] = 0
    header = b"CT lung STL (DICOM LPS millimetres)"[:80].ljust(80, b" ")
    with path.open("wb") as stream:
        stream.write(header)
        stream.write(struct.pack("<I", len(records)))
        records.tofile(stream)
    return {
        "path": str(path), "triangles": int(len(records)), "vertices": int(len(vertices)),
        "mesh_smoothing_iterations": iterations,
        "surface_gaussian_sigma_mm": surface_sigma_mm,
        "preserve_voxel_connectivity": preserve_voxels,
        "volume_compensated_surface_field": preserve_volume,
        "bounds_lps_mm": [vertices.min(axis=0).tolist(), vertices.max(axis=0).tolist()],
        "volume_mm3": float(abs(np.einsum(
            "ij,ij->i", triangles[:, 0], np.cross(triangles[:, 1], triangles[:, 2])
        ).sum() / 6.0)),
    }


def mesh_quality(mesh) -> dict:
    from vtkmodules.vtkFiltersCore import vtkConnectivityFilter, vtkFeatureEdges, vtkMassProperties

    edge_counts = {}
    for name, boundary, nonmanifold in (("boundary_edges", True, False),
                                        ("nonmanifold_edges", False, True)):
        edges = vtkFeatureEdges()
        edges.SetInputData(mesh)
        edges.SetBoundaryEdges(boundary)
        edges.SetNonManifoldEdges(nonmanifold)
        edges.FeatureEdgesOff()
        edges.ManifoldEdgesOff()
        edges.Update()
        edge_counts[name] = int(edges.GetOutput().GetNumberOfCells())
    components = vtkConnectivityFilter()
    components.SetInputData(mesh)
    components.SetExtractionModeToAllRegions()
    components.Update()
    mass = vtkMassProperties()
    mass.SetInputData(mesh)
    mass.Update()
    bounds = mesh.GetBounds()
    return {
        "triangles": int(mesh.GetNumberOfPolys()),
        "vertices": int(mesh.GetNumberOfPoints()),
        "surface_components": int(components.GetNumberOfExtractedRegions()),
        **edge_counts,
        "boundary_nonmanifold_edges": sum(edge_counts.values()),
        "volume_mm3": float(mass.GetVolume()),
        "bounds_lps_mm": [[bounds[0], bounds[2], bounds[4]], [bounds[1], bounds[3], bounds[5]]],
    }


def remove_small_surfaces(mesh, minimum_mm3):
    """Remove tiny closed shells introduced by surface extraction/smoothing."""
    from vtkmodules.vtkFiltersCore import vtkPolyDataConnectivityFilter, vtkCleanPolyData
    from vtkmodules.vtkCommonCore import vtkPoints
    from vtkmodules.vtkCommonDataModel import vtkPolyData, vtkCellArray
    from vtkmodules.util.numpy_support import vtk_to_numpy, numpy_to_vtkIdTypeArray

    regions = vtkPolyDataConnectivityFilter()
    regions.SetInputData(mesh)
    regions.SetExtractionModeToAllRegions()
    regions.ColorRegionsOn()
    regions.Update()
    colored = regions.GetOutput()
    vertices = vtk_to_numpy(colored.GetPoints().GetData()).astype(np.float64)
    labels = vtk_to_numpy(colored.GetPointData().GetArray("RegionId"))
    faces = vtk_to_numpy(colored.GetPolys().GetConnectivityArray()).reshape(-1, 3)
    count = regions.GetNumberOfExtractedRegions()
    sizes = np.bincount(labels, minlength=count)
    centers = np.stack([np.bincount(labels, weights=vertices[:, axis], minlength=count) /
                        np.maximum(sizes, 1) for axis in range(3)], axis=1)
    face_labels = labels[faces[:, 0]]
    triangles = vertices[faces] - centers[face_labels, None]
    volumes = abs(np.bincount(face_labels, weights=np.einsum(
        "ij,ij->i", triangles[:, 0], np.cross(triangles[:, 1], triangles[:, 2])) / 6,
        minlength=count))
    keep = volumes >= minimum_mm3
    # Always preserve the main object even for a very small predicted lesion.
    keep[np.argmax(volumes)] = True
    selected = np.ascontiguousarray(faces[keep[face_labels]], dtype=np.int64)
    cells = vtkCellArray()
    cells.SetData(numpy_to_vtkIdTypeArray(np.arange(0, 3 * len(selected) + 1, 3, dtype=np.int64), deep=True),
                  numpy_to_vtkIdTypeArray(selected.ravel(), deep=True))
    points = vtkPoints()
    points.SetData(colored.GetPoints().GetData())
    filtered = vtkPolyData()
    filtered.SetPoints(points)
    filtered.SetPolys(cells)
    cleaner = vtkCleanPolyData()
    cleaner.SetInputData(filtered)
    cleaner.Update()
    result = vtkPolyData()
    result.DeepCopy(cleaner.GetOutput())
    return result, {"minimum_surface_volume_mm3": minimum_mm3,
                    "surface_components_before_filter": count,
                    "removed_surface_components": int((~keep).sum()),
                    "removed_surface_volume_mm3": float(volumes[~keep].sum())}


def decimate_stl(input_path: Path, output_path: Path, target_faces: int,
                 largest_surface: bool = False, minimum_surface_volume_mm3: float = 0.0) -> dict:
    """Reduce and lightly smooth an STL using the reference VTK mesh filters."""
    from vtkmodules.vtkFiltersCore import vtkCleanPolyData
    from vtkmodules.vtkFiltersCore import vtkQuadricDecimation
    from vtkmodules.vtkFiltersCore import vtkWindowedSincPolyDataFilter
    from vtkmodules.vtkIOGeometry import vtkSTLReader, vtkSTLWriter

    reader = vtkSTLReader()
    reader.SetFileName(str(input_path))
    cleaner = vtkCleanPolyData()
    cleaner.SetInputConnection(reader.GetOutputPort())
    cleaner.Update()
    original_faces = cleaner.GetOutput().GetNumberOfPolys()
    if largest_surface:
        from vtkmodules.vtkFiltersCore import vtkConnectivityFilter
        outer = vtkConnectivityFilter()
        outer.SetInputConnection(reader.GetOutputPort())
        outer.SetExtractionModeToLargestRegion()
        cleaner.SetInputConnection(outer.GetOutputPort())
        cleaner.Update()
    source = cleaner.GetOutput()
    surface_filter = {}
    if minimum_surface_volume_mm3 > 0:
        source, surface_filter = remove_small_surfaces(source, minimum_surface_volume_mm3)
    source_faces = source.GetNumberOfPolys()
    if source_faces == 0:
        raise ValueError(f"STL has no triangles: {input_path}")

    source_quality = mesh_quality(source)
    removed_internal_faces = 0
    if source_quality["nonmanifold_edges"]:
        from vtkmodules.vtkCommonDataModel import vtkCellArray, vtkPolyData
        from vtkmodules.util.numpy_support import vtk_to_numpy, numpy_to_vtkIdTypeArray
        faces = vtk_to_numpy(source.GetPolys().GetConnectivityArray()).reshape(-1, 3)
        _, groups, counts = np.unique(np.sort(faces, axis=1), axis=0, return_inverse=True, return_counts=True)
        odd = (faces[:, 0] > faces[:, 1]) ^ (faces[:, 0] > faces[:, 2]) ^ (faces[:, 1] > faces[:, 2])
        winding_sum = np.bincount(groups, weights=np.where(odd, -1, 1))
        # Cancel exact opposite faces on a shared internal wall; leave outer shells intact.
        keep = ~((counts[groups] == 2) & (winding_sum[groups] == 0))
        removed_internal_faces = int((~keep).sum())
        if removed_internal_faces:
            selected = np.ascontiguousarray(faces[keep], dtype=np.int64)
            cells = vtkCellArray()
            cells.SetData(numpy_to_vtkIdTypeArray(np.arange(0, 3 * len(selected) + 1, 3, dtype=np.int64), deep=True),
                          numpy_to_vtkIdTypeArray(selected.ravel(), deep=True))
            cleaned = vtkPolyData()
            cleaned.SetPoints(source.GetPoints())
            cleaned.SetPolys(cells)
            source = cleaned
            source_faces = len(selected)
            source_quality = mesh_quality(source)

    reduction = vtkQuadricDecimation()
    reduction.SetInputData(source)
    reduction.SetTargetReduction(max(0.0, 1.0 - target_faces / source_faces))
    reduction.SetVolumePreservation(True)
    reduction.Update()
    algorithm = "VTK Quadric Decimation"
    reduced_quality = mesh_quality(reduction.GetOutput())
    if (reduced_quality["boundary_nonmanifold_edges"] or
            reduced_quality["surface_components"] != source_quality["surface_components"]):
        # Prefer a closed surface to meeting an exact triangle budget.
        from vtkmodules.vtkCommonExecutionModel import vtkTrivialProducer
        reduction = vtkTrivialProducer()
        reduction.SetOutput(source)
        algorithm = "Unreduced surface (quadric reduction failed mesh quality check)"
    smoother = vtkWindowedSincPolyDataFilter()
    smoother.SetInputConnection(reduction.GetOutputPort())
    smoother.SetNumberOfIterations(15)
    smoother.SetPassBand(0.08)
    smoother.NormalizeCoordinatesOn()
    smoother.FeatureEdgeSmoothingOff()
    smoother.BoundarySmoothingOff()
    smoother.NonManifoldSmoothingOff()
    smoother.Update()

    writer = vtkSTLWriter()
    writer.SetFileName(str(output_path))
    writer.SetFileTypeToBinary()
    writer.SetInputConnection(smoother.GetOutputPort())
    if not writer.Write():
        raise OSError(f"VTK could not write STL: {output_path}")
    # Check the saved STL, including float32 storage and re-merged vertices.
    check = vtkSTLReader()
    check.SetFileName(str(output_path))
    check.Update()
    result = check.GetOutput()
    before, after = mesh_quality(source), mesh_quality(result)
    saved_source_fallback = False
    if (after["boundary_nonmanifold_edges"] or
            after["surface_components"] != before["surface_components"]):
        # Float32 STL serialization can merge previously separate vertices.
        # Preserve the verified source surface when reduction/smoothing causes that.
        writer.SetInputData(source)
        if not writer.Write():
            raise OSError(f"VTK could not write source STL: {output_path}")
        check.Modified()
        check.Update()
        result = check.GetOutput()
        after = mesh_quality(result)
        algorithm = "Unreduced surface (saved reduced STL failed mesh quality check)"
        saved_source_fallback = True
        if (after["boundary_nonmanifold_edges"] or
                after["surface_components"] != before["surface_components"]):
            raise ValueError("Source STL failed surface topology checks; inspect source and output")
    return {
        "path": str(output_path),
        "algorithm": algorithm,
        "volume_preservation": algorithm == "VTK Quadric Decimation",
        "surface_smoothing": "VTK Windowed Sinc",
        "surface_smoothing_iterations": 0 if saved_source_fallback else 15,
        "surface_smoothing_passband": 0.08,
        "source_faces": int(source_faces),
        "original_source_faces": int(original_faces),
        "removed_coincident_internal_faces": removed_internal_faces,
        "largest_surface_only": largest_surface,
        "surface_fragment_filter": surface_filter,
        "target_faces": int(target_faces),
        "output_faces": int(result.GetNumberOfPolys()),
        "source_quality": before,
        "output_quality": after,
        "volume_change_percent": 100.0 * (after["volume_mm3"] / before["volume_mm3"] - 1.0),
    }


def save_preview(q: np.memmap, metadata: dict, mask: np.ndarray, path: Path) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    hu_min, hu_max = (float(v) for v in metadata["model_input"]["hu_clip"])
    hu = (np.asarray(q[:, 1], dtype=np.float32) + 128.0) * (hu_max - hu_min) / 255.0 + hu_min
    z, y, x = (np.asarray(mask.shape) // 2).tolist()
    images = [hu[z], hu[:, y, :], hu[:, :, x]]
    masks = [mask[z], mask[:, y, :], mask[:, :, x]]
    titles = [f"axial z={z}", f"coronal y={y}", f"sagittal x={x}"]
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    spacing = np.linalg.norm(np.asarray(metadata["affine_z_y_x_to_lps_mm"])[:3, :3], axis=0)
    aspects = [spacing[1] / spacing[2], spacing[0] / spacing[2], spacing[0] / spacing[1]]
    for axis, image, overlay, title, aspect in zip(axes, images, masks, titles, aspects):
        axis.imshow(image, cmap="gray", vmin=-1000, vmax=400, origin="lower", aspect=aspect)
        axis.imshow(np.ma.masked_where(~overlay, overlay), cmap="autumn", alpha=0.32,
                    origin="lower", aspect=aspect)
        axis.set_title(title)
        axis.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def save_surface_preview(stl_path: Path, path: Path, focus_bounds: np.ndarray | None = None) -> None:
    """Render the actual exported STL from anterior and posterior oblique views."""
    import vtkmodules.vtkRenderingOpenGL2  # Registers the renderer backend.
    import vtkmodules.vtkRenderingFreeType
    from vtkmodules.vtkFiltersCore import vtkPolyDataNormals
    from vtkmodules.vtkIOGeometry import vtkSTLReader
    from vtkmodules.vtkIOImage import vtkPNGWriter
    from vtkmodules.vtkRenderingCore import (
        vtkActor, vtkPolyDataMapper, vtkRenderer, vtkRenderWindow,
        vtkTextActor, vtkWindowToImageFilter,
    )

    reader = vtkSTLReader()
    reader.SetFileName(str(stl_path))
    reader.Update()
    normals = vtkPolyDataNormals()
    normals.SetInputConnection(reader.GetOutputPort())
    normals.SplittingOff()
    normals.ConsistencyOn()
    normals.AutoOrientNormalsOn()
    normals.Update()
    bounds = reader.GetOutput().GetBounds() if focus_bounds is None else focus_bounds
    center = np.array([(bounds[i] + bounds[i + 1]) / 2 for i in (0, 2, 4)])
    radius = max(bounds[i + 1] - bounds[i] for i in (0, 2, 4))
    window = vtkRenderWindow()
    window.SetOffScreenRendering(True)
    window.SetSize(1600, 900)
    for index, side in enumerate((-1, 1)):
        renderer = vtkRenderer()
        renderer.SetViewport(index / 2, 0, (index + 1) / 2, 1)
        renderer.SetBackground(0.96, 0.97, 0.99)
        mapper = vtkPolyDataMapper()
        mapper.SetInputConnection(normals.GetOutputPort())
        actor = vtkActor()
        actor.SetMapper(mapper)
        actor.GetProperty().SetColor(0.48, 0.72, 0.84)
        actor.GetProperty().SetInterpolationToPhong()
        actor.GetProperty().SetSpecular(0.22)
        actor.GetProperty().SetSpecularPower(25)
        renderer.AddActor(actor)
        label = vtkTextActor()
        label.SetInput("Anterior oblique" if side < 0 else "Posterior oblique")
        label.SetPosition(30, 30)
        label.GetTextProperty().SetColor(0.15, 0.18, 0.22)
        label.GetTextProperty().SetFontSize(24)
        renderer.AddViewProp(label)
        camera = renderer.GetActiveCamera()
        camera.SetFocalPoint(*center)
        camera.SetPosition(*(center + radius * np.array([0.3, side * 3, 0.18])))
        camera.SetViewUp(0, 0, 1)
        camera.ParallelProjectionOn()
        camera.SetParallelScale(radius * 0.62)
        renderer.ResetCameraClippingRange()
        window.AddRenderer(renderer)
    window.Render()
    screenshot = vtkWindowToImageFilter()
    screenshot.SetInput(window)
    screenshot.ReadFrontBufferOff()
    screenshot.Update()
    writer = vtkPNGWriter()
    writer.SetFileName(str(path))
    writer.SetInputConnection(screenshot.GetOutputPort())
    writer.Write()
    window.Finalize()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-bin", type=Path, default=Path("data/ct_stl_work/01/input/input_int8.bin"))
    parser.add_argument("--metadata", type=Path, default=Path("data/ct_stl_work/01/input/metadata.json"))
    parser.add_argument("--checkpoint", type=Path, default=ROOT / "model_assets/lobe_best.pt")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "output/lung_final")
    parser.add_argument("--batch-size", type=int, default=4)
    parser.add_argument("--threshold", type=float, default=0.0, help="Logit threshold; 0 means sigmoid 0.5")
    parser.add_argument("--sigma-mm", type=float, default=1.0)
    parser.add_argument("--closing-mm", type=float, default=1.5)
    parser.add_argument("--min-component-voxels", type=int, default=5000)
    parser.add_argument("--step-size", type=int, default=2,
                        help="Marching cubes stride for the smoothed surface")
    parser.add_argument("--surface-sigma-mm", type=float, default=1.2,
                        help="Continuous surface field smoothing in millimetres")
    parser.add_argument("--mesh-iterations", type=int, default=10)
    parser.add_argument("--target-faces", type=int, default=150000,
                        help="Target faces for the reference-style reduced STL")
    parser.add_argument("--orientation", choices=("nifti-ras", "native"), default="nifti-ras",
                        help="Adapt current LPS DICOM plane to training NIfTI RAS axes")
    parser.add_argument("--model-spacing-mm", type=float, default=1.5,
                        help="Training cache spacing; 0 disables internal resampling")
    parser.add_argument("--device", choices=("auto", "cpu", "cuda"), default="auto")
    parser.add_argument("--threads", type=int, default=20)
    parser.add_argument("--no-preview", action="store_true")
    args = parser.parse_args()
    if args.batch_size < 1 or args.step_size < 1 or args.min_component_voxels < 1 or args.target_faces < 4:
        raise ValueError("batch-size, step-size, min-component-voxels and target-faces must be positive")
    if (args.mesh_iterations < 0 or args.threads < 0
            or not np.isfinite([args.threshold, args.sigma_mm, args.closing_mm,
                                args.model_spacing_mm, args.surface_sigma_mm]).all()
            or min(args.sigma_mm, args.closing_mm, args.model_spacing_mm, args.surface_sigma_mm) < 0):
        raise ValueError("Smoothing values and threads must be finite and nonnegative")
    if args.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA was requested but is not available")
    device = torch.device("cuda" if args.device == "cuda" or (
        args.device == "auto" and torch.cuda.is_available()) else "cpu")
    if args.threads > 0:
        torch.set_num_threads(args.threads)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    q, metadata = load_input(args.input_bin, args.metadata)
    if args.orientation == "nifti-ras":
        axes = np.asarray(metadata["affine_z_y_x_to_lps_mm"])[:3, :3]
        directions = axes / np.linalg.norm(axes, axis=0)
        if (not np.allclose(directions[:2], [[0, 0, 1], [0, 1, 0]], atol=1e-3)
                or not np.allclose(abs(directions[2]), [1, 0, 0], atol=1e-3)):
            raise ValueError("RAS adapter requires axial L/P planes and a reliable slice direction")
        if metadata.get("source_nifti") and "anatomical_z_direction" not in metadata:
            raise ValueError("NIfTI anatomical slice order is unverified; check against reliable DICOM")
    model = load_model(args.checkpoint, device)
    print(f"[run] device={device}, input={tuple(q.shape)}, checkpoint={args.checkpoint}", flush=True)
    lobe_path = args.output_dir / "lobe_mask_uint8.npy"
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"], dtype=np.float64)
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    lobe_masks = infer(model, q, device, args.batch_size, args.threshold, lobe_path,
                       args.orientation, spacing, args.model_spacing_mm,
                       anatomical_z_direction=metadata.get("anatomical_z_direction", int(np.sign(affine[2, 0]))))
    raw = np.any(lobe_masks, axis=0)
    np.save(args.output_dir / "lung_mask_raw.npy", raw.astype(np.uint8), allow_pickle=False)

    body = body_mask(q, metadata["model_input"]["hu_clip"])
    np.save(args.output_dir / "body_mask.npy", body.astype(np.uint8), allow_pickle=False)
    smooth = smooth_mask(
        raw, spacing, args.sigma_mm, args.closing_mm, body, args.min_component_voxels
    )
    np.save(args.output_dir / "lung_mask_smooth.npy", smooth.astype(np.uint8), allow_pickle=False)

    raw_stl = write_stl(raw, affine, args.output_dir / "lung_raw.stl", 1)
    smooth_stl = write_stl(
        smooth, affine, args.output_dir / "lung_smooth.stl", args.step_size, args.mesh_iterations,
        args.surface_sigma_mm,
    )
    simplified_stl = decimate_stl(
        args.output_dir / "lung_smooth.stl",
        args.output_dir / "lung_bilateral.stl",
        args.target_faces,
    )
    if not args.no_preview:
        save_preview(q, metadata, smooth, args.output_dir / "lung_preview.png")
        save_surface_preview(Path(simplified_stl["path"]),
                             args.output_dir / "lung_surface_preview.png")
    run = {
        "status": "complete",
        "device": str(device),
        "model": "2.5D ResUNet + mkdc + ReLU6 + MaxPool2d",
        "classes": LOBES,
        "input": {
            "path": str(args.input_bin),
            "sha256": sha256_file(args.input_bin),
            "shape": list(q.shape),
            "dtype": "int8",
            "layout": "Z,C,H,W",
            "channels": "z-1,z,z+1 with repeat edge",
        },
        "checkpoint": {"path": str(args.checkpoint), "sha256": sha256_file(args.checkpoint)},
        "postprocess": {
            "model_orientation": args.orientation,
            "orientation_evidence": "training compact q.npy [Z,NIfTI-X,NIfTI-Y]; R,A,S affine",
            "model_spacing_mm": args.model_spacing_mm,
            "spacing_evidence": "all 1203 archived TotalSegmentator lobe cases have 1.5 mm spacing",
            "logit_threshold": args.threshold,
            "gaussian_sigma_mm": args.sigma_mm,
            "binary_closing_radius_mm": args.closing_mm,
            "body_restriction": "largest per-slice region above -200 HU, filled interior",
            "minimum_component_voxels": args.min_component_voxels,
            "kept_largest_components": 2,
            "lung_separation": "smooth raw components independently; maintain a 26-neighbor voxel gap",
            "taubin_mesh_iterations": args.mesh_iterations,
            "surface_gaussian_sigma_mm": args.surface_sigma_mm,
            "surface_marching_cubes_step": args.step_size,
        },
        "spacing_z_y_x_mm": spacing.tolist(),
        "coordinate_system": "DICOM LPS",
        "raw_voxels": int(raw.sum()),
        "smooth_voxels": int(smooth.sum()),
        "raw_stl": raw_stl,
        "smooth_stl": smooth_stl,
        "simplified_stl": simplified_stl,
        "output_files": [p.name for p in sorted(args.output_dir.iterdir()) if p.is_file()],
    }
    (args.output_dir / "run_metadata.json").write_text(
        json.dumps(run, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(json.dumps(run, indent=2, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
