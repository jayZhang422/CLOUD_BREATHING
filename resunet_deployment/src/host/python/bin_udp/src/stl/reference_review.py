"""Read paired reference STLs in memory and compare them on the CT grid."""

import json
import struct
from itertools import product
from pathlib import Path
from zipfile import ZipFile

import numpy as np
from scipy import ndimage

from . import lung_ct_to_stl as core
from ..io.prediction_io import CHANNELS


def binary_triangles(data):
    count = struct.unpack_from("<I", data, 80)[0]
    if len(data) != 84 + 50 * count:
        raise ValueError("Not a standard binary STL")
    records = np.frombuffer(data, offset=84, count=count, dtype=np.dtype([
        ("normal", "<f4", (3,)), ("vertices", "<f4", (3, 3)), ("attribute", "<u2")]))
    return records["vertices"].copy()


def reference_triangles(archive_path):
    result = {}
    with ZipFile(archive_path) as archive:
        for member in archive.namelist():
            name = Path(member).stem
            if not member.lower().endswith(".stl") or "plan_" in name:
                continue
            if name.startswith("LungTumor"):
                name = "LungTumor"
            if name not in CHANNELS:
                continue
            data = archive.read(member)
            triangles = binary_triangles(data)
            result[name] = np.concatenate((result[name], triangles)) if name in result else triangles
    return result


def voxelize(triangles, shape, reference_to_index):
    from vtkmodules.vtkCommonCore import vtkPoints
    from vtkmodules.vtkCommonDataModel import vtkPolyData, vtkCellArray
    from vtkmodules.vtkFiltersCore import vtkStaticCleanPolyData
    from vtkmodules.vtkImagingStencil import vtkPolyDataToImageStencil, vtkImageStencilToImage
    from vtkmodules.util.numpy_support import numpy_to_vtk, numpy_to_vtkIdTypeArray, vtk_to_numpy

    points = triangles.reshape(-1, 3).astype(np.float64)
    points = points @ reference_to_index[:3, :3].T + reference_to_index[:3, 3]
    vtk_points = vtkPoints()
    vtk_points.SetData(numpy_to_vtk(np.ascontiguousarray(points[:, ::-1]), deep=True))
    cells = vtkCellArray()
    cells.SetData(numpy_to_vtkIdTypeArray(np.arange(0, len(points) + 1, 3, dtype=np.int64), deep=True),
                  numpy_to_vtkIdTypeArray(np.arange(len(points), dtype=np.int64), deep=True))
    mesh = vtkPolyData()
    mesh.SetPoints(vtk_points)
    mesh.SetPolys(cells)
    clean = vtkStaticCleanPolyData()
    clean.SetInputData(mesh)
    clean.SetTolerance(0.)
    stencil = vtkPolyDataToImageStencil()
    stencil.SetInputConnection(clean.GetOutputPort())
    stencil.SetOutputOrigin(0, 0, 0)
    stencil.SetOutputSpacing(1, 1, 1)
    stencil.SetOutputWholeExtent(0, shape[2] - 1, 0, shape[1] - 1, 0, shape[0] - 1)
    image = vtkImageStencilToImage()
    image.SetInputConnection(stencil.GetOutputPort())
    image.SetInsideValue(1)
    image.SetOutsideValue(0)
    image.SetOutputScalarTypeToUnsignedChar()
    image.Update()
    return vtk_to_numpy(image.GetOutput().GetPointData().GetScalars()).reshape(shape).astype(bool)


def reference_affine(metadata, pixel_units, flip_y, flip_z):
    """Candidate software coordinates: isotropic pixels or millimetres, zero origin."""
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"])
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    shape = np.asarray(metadata["shape_z_y_x"])
    unit = spacing[2] if pixel_units else 1.
    result = np.eye(4)
    result[:3, :3] = np.diag([unit, -unit if flip_y else unit, -unit if flip_z else unit])
    result[:3, 3] = affine[:3, 3]
    if flip_y:
        result[:3, 3] += affine[:3, 1] * (shape[1] - 1)
    if flip_z:
        result[:3, 3] += affine[:3, 0] * (shape[0] - 1)
    return result


def review_grid(q, metadata, step_mm=2.):
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"])
    shape = np.asarray(q.shape)[[0, 2, 3]]
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    target = np.maximum(2, np.rint((shape - 1) * spacing / step_mm).astype(int) + 1)
    centers = ndimage.zoom(q[:, 1], target / shape, order=0, prefilter=False)
    hu = (centers.astype(np.float32) + 128) * 2024 / 255 - 1024
    grid_affine = affine.copy()
    grid_affine[:3, :3] *= ((shape - 1) / (target - 1))[None, :]
    return hu, grid_affine


def find_reference_alignment(triangles, hu, grid_affine, metadata):
    name = "Bronchus" if "Bronchus" in triangles else next(n for n in triangles if "Lobe" in n)
    inverse = np.linalg.inv(grid_affine)
    trials = []
    for pixel_units, flip_y, flip_z in product((True, False), repeat=3):
        affine = reference_affine(metadata, pixel_units, flip_y, flip_z)
        mask = voxelize(triangles[name], hu.shape, inverse @ affine)
        foreground = int(mask.sum())
        air_fraction = float(np.mean(hu[mask] < -350)) if foreground else 0.
        v = triangles[name].astype(np.float64)
        volume = abs(np.einsum("ij,ij->i", v[:, 0], np.cross(v[:, 1], v[:, 2])).sum() / 6)
        volume *= abs(np.linalg.det(affine[:3, :3]))
        raster_volume = foreground * abs(np.linalg.det(grid_affine[:3, :3]))
        coverage = float(min(1., raster_volume / max(volume, 1.)))
        trials.append({"pixel_units": pixel_units, "flip_y": flip_y, "flip_z": flip_z,
                       "air_fraction": air_fraction, "coverage": coverage,
                       "score": float(air_fraction * coverage)})
        print(f"[reference alignment] {trials[-1]}", flush=True)
        if trials[-1]["score"] >= .90:
            break
    best = max(trials, key=lambda row: row["score"])
    return reference_affine(metadata, best["pixel_units"], best["flip_y"], best["flip_z"]), {
        "method": "CT airway attenuation and in-scan coverage; no fitted translation, scaling or prediction-based registration",
        "best": best, "trials": trials, "usable": bool(best["score"] >= .85),
        "reference_to_lps_mm": reference_affine(metadata, best["pixel_units"], best["flip_y"], best["flip_z"]).tolist()}


def agreement(prediction, reference):
    intersection = int(np.count_nonzero(prediction & reference))
    count, expected = int(prediction.sum()), int(reference.sum())
    return {"prediction_voxels": count, "reference_voxels": expected,
            "dice": 2 * intersection / max(1, count + expected),
            "precision": intersection / max(1, count), "recall": intersection / max(1, expected)}


def prepare_reference_support(case, reference_path):
    record_path = case / "reference_alignment.json"
    fingerprint = {"archive_sha256": core.sha256_file(reference_path),
                   "input_metadata_sha256": core.sha256_file(case / "input/metadata.json")}
    if record_path.exists() and (case / "reference_support.npz").exists():
        cached = json.loads(record_path.read_text(encoding="utf-8"))
        if all(cached.get(key) == value for key, value in fingerprint.items()):
            return case / "reference_support.npz"
    q, metadata = core.load_input(case / "input/input_int8.bin", case / "input/metadata.json")
    hu, grid_affine = review_grid(q, metadata)
    triangles = reference_triangles(reference_path)
    affine, alignment = find_reference_alignment(triangles, hu, grid_affine, metadata)
    support = {}
    if alignment["usable"]:
        for name, mesh in triangles.items():
            support[name] = voxelize(mesh, hu.shape, np.linalg.inv(grid_affine) @ affine)
            print(f"[reference mask] {name}: {int(support[name].sum()):,} review voxels", flush=True)
    np.savez_compressed(case / "reference_support.npz", **support)
    record = {"archive": str(reference_path), **fingerprint,
              "alignment": alignment, "grid_affine": grid_affine.tolist(),
              "grid_shape": list(hu.shape), "missing_reference_lobes": [n for n in CHANNELS[:5] if n not in triangles]}
    (case / "reference_alignment.json").write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding="utf-8")
    return case / "reference_support.npz"


def review_case(case, reference_path, final, out):
    from .chest_ct_to_stl import COLORS
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import ListedColormap

    out.mkdir(parents=True, exist_ok=True)
    q, metadata = core.load_input(case / "input/input_int8.bin", case / "input/metadata.json")
    hu, grid_affine = review_grid(q, metadata)
    record = json.loads((case / "reference_alignment.json").read_text(encoding="utf-8"))
    alignment = record["alignment"]
    with np.load(case / "reference_support.npz", allow_pickle=False) as packed:
        references = {name: packed[name] for name in packed.files}
    contract = json.loads((case / "prediction/metadata.json").read_text(encoding="utf-8"))
    prediction = np.memmap(case / "prediction/segmentation_uint8.bin", dtype=np.uint8,
                           mode="r", shape=tuple(contract["shape"]))
    report = {"reference_archive": str(reference_path), "alignment": alignment,
              "comparison_grid_spacing_mm": np.linalg.norm(grid_affine[:3, :3], axis=0).tolist(),
              "missing_reference_lobes": record["missing_reference_lobes"],
              "raw_lung_end_slice_voxels": [int(prediction[0, :5].sum()), int(prediction[-1, :5].sum())],
              "reference_is_partial_and_not_certified_ground_truth": True, "objects": {}}
    figure, axes = plt.subplots(3, 3, figsize=(15, 14))
    lobes = np.zeros(hu.shape, dtype=np.uint8)
    for index, (name, color) in enumerate(zip(CHANNELS, COLORS)):
        raw = ndimage.zoom(
            prediction[:, index], np.asarray(hu.shape) / np.asarray(prediction[:, index].shape), order=0, prefilter=False).astype(bool)
        processed = np.load(case / "work" / f"{name}_mask.npy", mmap_mode="r")
        processed = ndimage.zoom(processed, np.asarray(hu.shape) / processed.shape, order=0, prefilter=False).astype(bool)
        if index < 5:
            lobes[processed] = index + 1
        reference = references.get(name)
        info = {"raw_components": int(ndimage.label(raw)[1]), "processed_components": int(ndimage.label(processed)[1]),
                "removed_voxels": int((raw & ~processed).sum()), "added_voxels": int((processed & ~raw).sum())}
        if reference is not None:
            info["raw_reference_agreement"] = agreement(raw, reference)
            info["processed_reference_agreement"] = agreement(processed, reference)
        report["objects"][name] = info
        z = int((reference if reference is not None else processed).sum(axis=(1, 2)).argmax())
        axis = axes.ravel()[index]
        axis.imshow(hu[z], cmap="gray", vmin=-1000, vmax=400)
        axis.imshow(np.ma.masked_where(~processed[z], np.ones(hu[z].shape)),
                    cmap=ListedColormap([color]), alpha=.45)
        if reference is not None and reference[z].any():
            axis.contour(reference[z], levels=[.5], colors=["lime"], linewidths=.9)
        axis.set_title(f"{name} | z={z}" + (f" | ref Dice={info['processed_reference_agreement']['dice']:.3f}" if reference is not None else " | reference unavailable"))
        axis.axis("off")
    figure.suptitle("Prediction on CT; green contours = aligned partial reference STL", fontsize=14)
    figure.tight_layout()
    figure.savefig(out / "ct_reference_comparison.png", dpi=130)
    plt.close(figure)
    final_lobes, final_counts = final_lobe_grid(final, hu.shape, grid_affine)
    save_lung_overview(hu, final_lobes, grid_affine, out / "final_lung_three_planes.png")
    report["final_lobe_stl_voxels_on_comparison_grid"] = final_counts
    report["processed_vs_final_lung_union"] = agreement(final_lobes > 0, lobes > 0)
    report["final_lung_end_slice_voxels_on_comparison_grid"] = [int(np.count_nonzero(final_lobes[0])), int(np.count_nonzero(final_lobes[-1]))]
    (out / "reference_review.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    for filename in ("ct_prediction_overlays.png", "chest_surface_preview.png"):
        import shutil
        shutil.copy2(case / "work" / filename, out / filename)
    return {"alignment_usable": alignment["usable"], "alignment_score": alignment["best"]["score"],
            "report": str(out / "reference_review.json"), "missing_reference_lobes": report["missing_reference_lobes"]}


def final_lobe_grid(final, shape, affine):
    lobes = np.zeros(shape, dtype=np.uint8)
    counts = {}
    for index, name in enumerate(CHANNELS[:5]):
        triangles = binary_triangles((final / f"{name}.stl").read_bytes())
        if not len(triangles) or not np.isfinite(triangles).all():
            raise ValueError(f"Invalid final lung STL: {name}")
        mask = voxelize(triangles, shape, np.linalg.inv(affine))
        counts[name] = int(mask.sum())
        lobes[mask] = index + 1
        print(f"[final STL on CT] {name}: {counts[name]:,} review voxels", flush=True)
    return lobes, counts


def save_lung_overview(hu, lobes, affine, path):
    """Check lung coverage in three planes, including superior and inferior regions."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import ListedColormap
    from .chest_ct_to_stl import COLORS

    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    occupied = np.where(lobes)
    figure, axes = plt.subplots(3, 3, figsize=(13, 13))
    for dimension, name in enumerate(("Axial", "Coronal", "Sagittal")):
        low, high = int(occupied[dimension].min()), int(occupied[dimension].max())
        remaining = [d for d in range(3) if d != dimension]
        for column, fraction in enumerate((.25, .5, .75)):
            index = round(low + fraction * (high - low))
            ct, labels = np.take(hu, index, axis=dimension), np.take(lobes, index, axis=dimension)
            axis = axes[dimension, column]
            options = {"origin": "upper" if dimension == 0 else "lower",
                       "aspect": spacing[remaining[0]] / spacing[remaining[1]]}
            axis.imshow(ct, cmap="gray", vmin=-1000, vmax=400, **options)
            axis.imshow(np.ma.masked_where(labels == 0, labels), cmap=ListedColormap(COLORS[:5]),
                        vmin=1, vmax=5, alpha=.45, **options)
            axis.set_title(f"{name} | index={index}")
            axis.axis("off")
    figure.suptitle("Final five lobe STLs on CT: three planes", fontsize=14)
    figure.tight_layout()
    figure.savefig(path, dpi=130)
    plt.close(figure)
