"""Infer a segmentation BIN, or independently repair that BIN and export chest STLs."""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
from scipy import ndimage

from . import lung_ct_to_stl as core
from ..io.prediction_io import read_prediction, write_prediction, prediction_mask
from .branch_repair import repair_branches, filter_vein_islands


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CASE = Path("data/ct_stl_work/01")
LOBE_NAMES = ["LeftUpperLobe", "LeftLowerLobe", "RightUpperLobe", "RightMiddleLobe", "RightLowerLobe"]
COLORS = [(0.38, .76, .91), (.38, .51, .88), (.98, .75, .35), (.42, .79, .51), (.81, .48, .78),
          (.92, .82, .55), (.92, .22, .22), (.22, .39, .88), (1., .28, .7)]
NAMES = LOBE_NAMES + ["Bronchus", "PulmonaryArtery", "PulmonaryVenous", "LungTumor"]
TASKS = [("lobe", 5, "nifti-ras", 1.5), ("airway", 1, "transpose", 0),
         ("vessel", 2, "native", 0), ("tumor", 1, "transpose", 0)]


def remove_small(mask, minimum):
    labels, _ = ndimage.label(mask, ndimage.generate_binary_structure(3, 3))
    counts = np.bincount(labels.ravel())
    keep = counts >= minimum
    keep[0] = False
    return keep[labels]


def connect_nearby(mask, allowed, spacing, maximum_mm=2.5):
    """Bridge nearest same-class fragments locally, only through allowed CT voxels."""
    result = mask.copy()
    labels, number = ndimage.label(mask, ndimage.generate_binary_structure(3, 1))
    counts = np.bincount(labels.ravel())
    boxes = ndimage.find_objects(labels)
    padding = np.ceil(maximum_mm / spacing).astype(int) + 1
    connected = 0
    # Process small fragments; the main trunk remains the anchor.
    for index in np.argsort(counts[1:])[::-1][1:] + 1:
        box = boxes[index - 1]
        region = tuple(slice(max(0, axis.start - int(p)), min(mask.shape[k], axis.stop + int(p)))
                       for k, (axis, p) in enumerate(zip(box, padding)))
        local_labels = labels[region]
        candidate = local_labels == index
        target = result[region] & ~candidate
        if not target.any():
            continue
        distances, nearest = ndimage.distance_transform_edt(~target, sampling=spacing, return_indices=True)
        distances[~candidate] = np.inf
        point = np.array(np.unravel_index(distances.argmin(), distances.shape))
        if distances[tuple(point)] > maximum_mm:
            continue
        endpoint = nearest[(slice(None),) + tuple(point)]
        samples = np.rint(np.linspace(point, endpoint, 1 + int(np.max(abs(endpoint - point)) * 4))).astype(int)
        path = np.zeros(candidate.shape, dtype=bool)
        current = point.copy()
        path[tuple(current)] = True
        for next_point in samples[1:]:
            # Include face-adjacent steps so a voxel corner contact is not counted as a repaired tube.
            for axis in np.argsort(-abs(next_point - current) * spacing):
                while current[axis] != next_point[axis]:
                    current[axis] += 1 if next_point[axis] > current[axis] else -1
                    path[tuple(current)] = True
        new = path & ~result[region]
        if not np.all(allowed[region][new]):
            continue
        result[region] |= path
        connected += 1
    return result, connected


def reference_components(raw, reference, fallback_largest=True):
    """Keep predicted components with reference support; never copy reference voxels."""
    labels, number = ndimage.label(raw, ndimage.generate_binary_structure(3, 3))
    sizes = np.bincount(labels.ravel(), minlength=number + 1)
    support = np.bincount(labels[reference].ravel(), minlength=number + 1)
    keep = (sizes >= 5) & (support >= 3)
    keep[0] = False
    if fallback_largest and number and not keep.any():
        keep[1 + np.argmax(sizes[1:])] = True
    return keep[labels]


def adjust_lobe_boundaries(raw_masks, references, spacing):
    """Relabel tiny internal boundary patches; preserve the model lung union."""
    labels = np.zeros(raw_masks[0].shape, dtype=np.uint8)
    for index, mask in enumerate(raw_masks):
        labels[mask] = index + 1
    original = labels.copy()
    counts = np.bincount(original.ravel(), minlength=6)
    budgets = (counts * .01).astype(int)
    used = np.zeros(6, dtype=np.int64)
    moved = np.zeros(labels.shape, dtype=bool)
    band = core.ellipsoid(1.5, spacing)
    interior = ndimage.binary_erosion(original > 0, band)
    notes = {"maximum_boundary_move_mm": 1.5, "maximum_changed_fraction_per_lobe": .01,
             "lung_union_unchanged": True, "targets": {}}
    for index, name in enumerate(LOBE_NAMES, 1):
        if name not in references.files or not counts[index]:
            continue
        coarse = ndimage.binary_erosion(references[name], ndimage.generate_binary_structure(3, 1))
        reference_inside = ndimage.zoom(coarse, np.asarray(labels.shape) / coarse.shape, order=0, prefilter=False)
        same_lung = ((original == 1) | (original == 2)) if index <= 2 else (original >= 3)
        nearby = ndimage.binary_dilation(original == index, band)
        candidate = interior & reference_inside & same_lung & nearby & (original != index) & ~moved
        changes = np.bincount(original[candidate], minlength=6)
        changes[index] = int(candidate.sum())
        accepted = bool(np.all(used[1:] + changes[1:] <= budgets[1:]))
        notes["targets"][name] = {"candidate_voxels": int(candidate.sum()),
                                  "accepted_voxels": int(candidate.sum()) if accepted else 0,
                                  "skipped_for_size_limit": not accepted}
        if accepted:
            labels[candidate] = index
            moved |= candidate
            used += changes
    notes["changed_voxels"] = int(moved.sum())
    notes["changed_fraction_of_model_lung"] = int(moved.sum()) / max(1, int(counts[1:].sum()))
    return [labels == index for index in range(1, 6)], notes


def repair_mask(name, raw, body, spacing, hu=None, reference=None):
    """Repair small gaps; use the largest connected tumor candidate for display."""
    raw = np.asarray(raw, dtype=bool) & body
    if reference is not None:
        raw = reference_components(raw, reference, fallback_largest=name != "LungTumor")
    if name in LOBE_NAMES:
        mask = core.keep_largest(raw, 1) if reference is None else raw
        mask |= ndimage.binary_closing(mask, core.ellipsoid(1.0, spacing)) & body
        return ndimage.binary_fill_holes(mask) & body, {
            "operation": ("reference-supported predicted components" if reference is not None else "largest lobe") + ", 1.0 mm closing, hole fill", "minimum_component_voxels": 1,
            "closing_radius_mm": 1.0,
        }
    if name == "LungTumor":
        # Repair nearby fragments before selecting the main candidate for display.
        labels, _ = ndimage.label(raw, ndimage.generate_binary_structure(3, 3))
        counts = np.bincount(labels.ravel())
        major = counts >= 50
        major[0] = False
        near = ndimage.binary_dilation(major[labels], core.ellipsoid(3.0, spacing))
        nearby = np.unique(labels[near])
        nearby = nearby[nearby != 0]
        major[nearby[counts[nearby] >= 5]] = True
        mask = major[labels]
        mask |= ndimage.binary_closing(mask, core.ellipsoid(1.5, spacing)) & body
        mask, bridges = connect_nearby(mask, body & ((hu > -250) if hu is not None else True), spacing, 3.0)
        mask = remove_small(mask, 5)
        candidate_voxels = int(mask.sum())
        labels, components = ndimage.label(mask, ndimage.generate_binary_structure(3, 3))
        if components and reference is None:
            mask = labels == (1 + np.argmax(np.bincount(labels.ravel())[1:]))
        return mask, {
            "operation": "close and bridge small gaps, then " + ("retain reference-supported predicted candidates" if reference is not None else "display only the largest connected tumor candidate"),
            "minimum_component_voxels": 5, "distant_component_minimum_voxels": 50,
            "closing_radius_mm": 1.5, "maximum_bridge_distance_mm": 3.0, "accepted_bridges": bridges,
            "display_largest_candidate_only": reference is None,
            "removed_disconnected_components": max(0, components - 1) if reference is None else 0,
            "removed_disconnected_voxels": candidate_voxels - int(mask.sum()),
        }
    # A small closing bridges branch gaps while preserving separated branches.
    allowed = body if hu is None else body & ((hu < -400) if name == "Bronchus" else ((hu > -200) & (hu < 700)))
    additions = ndimage.binary_closing(raw, core.ellipsoid(1.5, spacing)) & allowed
    mask, bridges = connect_nearby(raw | additions, allowed, spacing)
    return remove_small(mask, 50), {
        "operation": "CT-constrained 1.5 mm closing and local bridges; retain branches >=50 voxels",
        "minimum_component_voxels": 50, "closing_radius_mm": 1.5,
        "maximum_bridge_distance_mm": 2.5, "accepted_bridges": bridges,
    }


def repair_joint_lobes(raw_masks, body, spacing, hu, references=None):
    from .lobe_surface import repair_lobe_envelope
    masks, repairs = [], []
    for name, raw in zip(LOBE_NAMES, raw_masks):
        reference = None
        if references is not None and name in references.files:
            coarse = references[name]
            coarse_spacing = spacing * (np.asarray(raw.shape) - 1) / (np.asarray(coarse.shape) - 1)
            nearby = ndimage.binary_dilation(coarse, core.ellipsoid(2., coarse_spacing))
            reference = ndimage.zoom(nearby, np.asarray(raw.shape) / coarse.shape, order=0, prefilter=False)
        mask, repair = repair_mask(name, raw, body, spacing, hu, reference)
        repair["reference_supported_component_selection"] = reference is not None
        masks.append(mask)
        repairs.append(repair)
    masks, envelope = repair_lobe_envelope(masks, body, spacing, hu)
    return masks, repairs, envelope


def scene_actors(directory):
    import vtkmodules.vtkRenderingOpenGL2
    from vtkmodules.vtkIOGeometry import vtkSTLReader
    from vtkmodules.vtkFiltersCore import vtkPolyDataNormals
    from vtkmodules.vtkRenderingCore import vtkActor, vtkPolyDataMapper

    actors = {}
    for name, color in zip(NAMES, COLORS):
        path = directory / f"{name}.stl"
        if not path.exists():
            continue
        reader = vtkSTLReader()
        reader.SetFileName(str(path))
        normals = vtkPolyDataNormals()
        normals.SetInputConnection(reader.GetOutputPort())
        normals.SplittingOff()
        normals.ConsistencyOn()
        normals.AutoOrientNormalsOn()
        mapper = vtkPolyDataMapper()
        mapper.SetInputConnection(normals.GetOutputPort())
        actor = vtkActor()
        actor.SetMapper(mapper)
        actor.GetProperty().SetColor(*color)
        actor.GetProperty().SetInterpolationToPhong()
        actor.GetProperty().SetSpecular(.18)
        actors[name] = actor
    return actors


def save_scene(directory):
    import vtkmodules.vtkRenderingOpenGL2  # Register before creating vtkRenderWindow.
    from vtkmodules.vtkRenderingCore import vtkRenderer, vtkRenderWindow, vtkWindowToImageFilter
    from vtkmodules.util.numpy_support import vtk_to_numpy
    from PIL import Image, ImageDraw

    # Reuse one scene for the four viewpoints.
    renderer = vtkRenderer()
    renderer.SetUseOIT(False)
    renderer.SetBackground(.965, .975, .985)
    window = vtkRenderWindow()
    window.SetOffScreenRendering(True)
    window.SetSize(900, 650)
    window.AddRenderer(renderer)
    actors = scene_actors(directory)
    panels = []
    for index, title in enumerate(("Five lobes - anterior", "Five lobes - posterior",
                                   "Airway / artery / vein / tumor prediction", "All structures - transparent lobes")):
        renderer.RemoveAllViewProps()
        for name, actor in actors.items():
            if index < 2 and name not in LOBE_NAMES:
                continue
            actor.GetProperty().SetOpacity((.035 if index == 2 else .13)
                if name in LOBE_NAMES and index >= 2 else 1.)
            renderer.AddActor(actor)
        renderer.ResetCamera()
        camera = renderer.GetActiveCamera()
        center = np.array(camera.GetFocalPoint())
        bounds = renderer.ComputeVisiblePropBounds()
        radius = max(bounds[i + 1] - bounds[i] for i in (0, 2, 4))
        camera.SetPosition(*(center + radius * np.array([.18, 3 if index == 1 else -3, .12])))
        camera.SetViewUp(0, 0, 1)
        camera.ParallelProjectionOn()
        camera.SetParallelScale(radius * .59)
        renderer.ResetCameraClippingRange()
        print(f"[preview] panel {index + 1}/4", flush=True)
        window.Render()
        capture = vtkWindowToImageFilter()
        capture.SetInput(window)
        capture.ReadFrontBufferOff()
        capture.Update()
        pixels = vtk_to_numpy(capture.GetOutput().GetPointData().GetScalars())
        panel = Image.fromarray(pixels.reshape(650, 900, -1)[::-1].copy())
        ImageDraw.Draw(panel).text((22, 615), title, fill=(30, 40, 50), font_size=20)
        panels.append(np.asarray(panel))
    combined = np.concatenate((np.concatenate(panels[:2], axis=1),
                               np.concatenate(panels[2:], axis=1)), axis=0)
    Image.fromarray(combined).save(directory / "chest_surface_preview.png")
    window.Finalize()


def save_overlays(q, masks, spacing, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import ListedColormap
    from matplotlib.patches import Patch

    fig, axes = plt.subplots(3, 3, figsize=(15, 14))
    for index, (name, color) in enumerate(zip(NAMES, COLORS)):
        mask = masks[name]
        counts = mask.sum(axis=(1, 2))
        z = int(counts.argmax()) if counts.max() else q.shape[0] // 2
        image = (q[z, 1].astype(np.float32) + 128) * 2024 / 255 - 1024
        axis = axes.ravel()[index]
        axis.imshow(image, cmap="gray", vmin=-1000, vmax=400, origin="lower", aspect=spacing[1] / spacing[2])
        axis.imshow(np.ma.masked_where(~mask[z], np.ones(mask[z].shape)),
                    cmap=ListedColormap([color]), alpha=.52, origin="lower")
        axis.set_title(f"{name} | z={z} | {int(mask.sum()):,} voxels")
        axis.axis("off")
    fig.legend(handles=[Patch(color=color, label=name) for name, color in zip(NAMES, COLORS)],
               loc="lower center", ncol=5)
    fig.tight_layout(rect=(0, .05, 1, 1))
    fig.savefig(path, dpi=130)
    plt.close(fig)


def save_tumor_detail(out, mask, affine):
    labels, _ = ndimage.label(mask, ndimage.generate_binary_structure(3, 3))
    sizes = np.bincount(labels.ravel())
    if len(sizes) <= 1:
        return
    region = ndimage.find_objects(labels)[int(np.argmax(sizes[1:]))]
    corners = np.array(np.meshgrid(*[(s.start, s.stop - 1) for s in region], indexing="ij")).reshape(3, -1).T
    points = corners @ affine[:3, :3].T + affine[:3, 3]
    low, high = points.min(axis=0) - 5, points.max(axis=0) + 5
    bounds = np.column_stack((low, high)).ravel()
    core.save_surface_preview(out / "LungTumor.stl", out / "tumor_detail_preview.png", bounds)


def argument_parser(stage="convert"):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-bin", type=Path, default=None)
    parser.add_argument("--metadata", type=Path, default=None)
    if stage != "infer":
        parser.add_argument("--output-dir", type=Path, default=DEFAULT_CASE / "work")
        parser.add_argument("--view-dir", type=Path, default=ROOT / "stl_vessels_refined/01", help="Separate folder for final STL copies and colored GLB")
        parser.add_argument("--no-previews", action="store_true", help="Skip CT overlays and preview images")
        parser.add_argument("--smooth-only", action="store_true", help="Keep all BIN foreground; only extract and smooth meshes")
        parser.add_argument("--reference-support", type=Path, help="CT-aligned partial reference masks for predicted-component review")
    if stage != "postprocess":
        parser.add_argument("--device", choices=("auto", "cpu", "cuda"), default="auto")
        parser.add_argument("--batch-size", type=int, default=2)
        parser.add_argument("--threads", type=int, default=12)
        parser.add_argument("--reuse-masks", action="store_true", help="Reuse only matching saved inference masks")
    parser.add_argument("--prediction-dir", type=Path, default=DEFAULT_CASE / "prediction")
    return parser


def infer_case(args):
    if args.batch_size < 1 or args.threads < 1:
        raise ValueError("batch-size and threads must be positive")
    if args.device == "cuda" and not torch.cuda.is_available():
        raise RuntimeError("CUDA is unavailable in this Python environment")
    device = torch.device("cuda" if args.device == "cuda" or (
        args.device == "auto" and torch.cuda.is_available()) else "cpu")
    torch.set_num_threads(args.threads)
    args.input_bin = args.input_bin or DEFAULT_CASE / "input/input_int8.bin"
    args.metadata = args.metadata or DEFAULT_CASE / "input/metadata.json"
    out = args.prediction_dir / "cache"
    out.mkdir(parents=True, exist_ok=True)
    q, metadata = core.load_input(args.input_bin, args.metadata)
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"], dtype=np.float64)
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    axes = affine[:3, :3] / spacing
    if (not np.allclose(axes[:2], [[0, 0, 1], [0, 1, 0]], atol=1e-3)
            or not np.allclose(abs(axes[2]), [1, 0, 0], atol=1e-3)):
        raise ValueError("Expected axial L/P in-plane axes and either native slice direction")
    started = time.perf_counter()
    run = {"status": "running", "device": str(device), "input_bin": str(args.input_bin),
           "input_sha256": core.sha256_file(args.input_bin), "input_shape": list(q.shape),
           "coordinate_system": "DICOM LPS millimetres; common affine for every object",
           "affine_z_y_x_to_lps_mm": affine.tolist(), "tasks": {}, "objects": {}}
    predictions = {}
    for task, channels, orientation, model_spacing in TASKS:
        checkpoint = ROOT / f"model_assets/{task}_best.pt"
        cache_key = {"input_sha256": run["input_sha256"], "checkpoint_sha256": core.sha256_file(checkpoint),
                     "model_slice_order": metadata.get("model_slice_order", "existing_bin_indices"),
                     "orientation": orientation, "model_spacing_mm": model_spacing, "logit_threshold": 0.0}
        if task == "lobe":
            if metadata.get("source_nifti") and "anatomical_z_direction" not in metadata:
                raise ValueError("NIfTI anatomical slice order is unverified; record anatomical_z_direction from reliable DICOM before lobe inference")
            cache_key["anatomical_z_direction"] = metadata.get("anatomical_z_direction", int(np.sign(affine[2, 0])))
            cache_key["adapter_revision"] = "physical-lobe-neighbors-v3"
        mask_path, key_path = out / f"{task}_raw_uint8.npy", out / f"{task}_inference.json"
        label_path = out / f"{task}_exclusive_labels.npy" if channels > 1 else None
        reuse = args.reuse_masks and mask_path.exists() and key_path.exists()
        reuse = reuse and json.loads(key_path.read_text(encoding="utf-8")) == cache_key
        reuse = reuse and (label_path is None or label_path.exists())
        print(f"[task] {task}: {'reuse' if reuse else 'infer'} {checkpoint.name}", flush=True)
        if not reuse:
            model = core.load_model(checkpoint, device)
            assert model.head.out_channels == channels
        run["tasks"][task] = {**cache_key, "checkpoint": str(checkpoint),
                               "outputs": channels}
        if not reuse:
            core.infer(model, q, device, args.batch_size, 0., mask_path, orientation,
                       spacing, model_spacing, exclusive_path=label_path,
                       anatomical_z_direction=cache_key.get("anatomical_z_direction", 1))
            key_path.write_text(json.dumps(cache_key, indent=2), encoding="utf-8")
        if not reuse:
            del model
        predictions[task] = np.load(mask_path, mmap_mode="r")
        counts = [int(m.sum()) for m in predictions[task]]
        run["tasks"][task]["raw_channel_voxels"] = counts
        run["tasks"][task]["output_classes"] = {"lobe": LOBE_NAMES, "airway": ["Bronchus"],
            "vessel": ["PulmonaryArtery", "PulmonaryVenous"], "tumor": ["LungTumor"]}[task]
        print(f"[prediction] {task}: {counts}", flush=True)
    lobe_labels = np.load(out / "lobe_exclusive_labels.npy", mmap_mode="r")
    vessel_labels = np.load(out / "vessel_exclusive_labels.npy", mmap_mode="r")
    raw_masks = [lobe_labels == k + 1 for k in range(5)] + [predictions["airway"][0],
                 vessel_labels == 1, vessel_labels == 2, predictions["tumor"][0]]
    provenance = {"input_bin": str(args.input_bin.resolve()), "input_metadata": str(args.metadata.resolve()),
                  "input_sha256": run["input_sha256"], "input_shape": list(q.shape),
                  "input_metadata_content": metadata, "tasks": run["tasks"], "device": str(device)}
    write_prediction(args.prediction_dir, raw_masks, affine, provenance)
    print(f"[inference BIN] {args.prediction_dir}; {time.perf_counter() - started:.1f}s", flush=True)


def infer_main():
    infer_case(argument_parser("infer").parse_args())


def postprocess_main():
    postprocess_case(argument_parser("postprocess").parse_args())


def main():
    args = argument_parser().parse_args()
    infer_case(args)
    postprocess_case(args)


def postprocess_case(args):
    started = time.perf_counter()
    smooth_only = getattr(args, "smooth_only", False)
    prediction, contract = read_prediction(args.prediction_dir)
    provenance = contract["provenance"]
    input_bin = args.input_bin or Path(provenance["input_bin"])
    input_metadata = args.metadata or Path(provenance["input_metadata"])
    if contract["format"] == "ct-segmentation-bitmask-v2":
        from ..io.fpga_volume_io import load_volume
        centers, metadata = load_volume(input_bin, input_metadata)
        # Central-channel view for existing CT repair/preview helpers; no triplet BIN is created.
        q = np.broadcast_to(centers[:, None], (len(centers), 3, *centers.shape[1:]))
        input_shape, prediction_shape = list(centers.shape), tuple(prediction.shape)
    else:
        q, metadata = core.load_input(input_bin, input_metadata)
        input_shape = list(q.shape)
        prediction_shape = (prediction.shape[0], *prediction.shape[2:])
    affine = np.asarray(contract["affine_z_y_x_to_lps_mm"], dtype=np.float64)
    if (input_shape != provenance["input_shape"] or prediction_shape != (q.shape[0], *q.shape[2:]) or
            not np.allclose(affine, metadata["affine_z_y_x_to_lps_mm"]) or
            core.sha256_file(input_bin) != provenance["input_sha256"]):
        raise ValueError("CT reference does not match the segmentation BIN grid or SHA256")
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    body = None if smooth_only else core.body_mask(q, metadata["model_input"]["hu_clip"])
    hu_min, hu_max = metadata["model_input"]["hu_clip"]
    hu = None if smooth_only else (q[:, 1].astype(np.float32) + 128.) * (hu_max - hu_min) / 255. + hu_min
    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    (out / "surfaces_before_reduction").mkdir(exist_ok=True)
    (out / "review_withheld").mkdir(exist_ok=True)
    run = {"status": "running", "stage": "postprocess_only_no_model_loading",
           "postprocess_mode": "smooth_only" if smooth_only else "repair",
           "input_bin": str(input_bin), "input_sha256": provenance["input_sha256"],
           "input_shape": input_shape, "device": "cpu postprocessing",
           "coordinate_system": contract["coordinate_system"],
           "affine_z_y_x_to_lps_mm": affine.tolist(), "tasks": provenance["tasks"],
           "prediction_bin": str((args.prediction_dir / contract["file"]).resolve()),
           "prediction_sha256": contract["sha256"], "objects": {}}
    masks = {}
    raw_masks = [prediction_mask(prediction, index) for index in range(len(NAMES))]
    original_counts = [int(mask.sum()) for mask in raw_masks]
    reference_path = getattr(args, "reference_support", None)
    references = np.load(reference_path, allow_pickle=False) if reference_path else None
    if references is not None and not smooth_only:
        raw_masks[:5], run["minor_lobe_boundary_adjustment"] = adjust_lobe_boundaries(raw_masks[:5], references, spacing)
    if not smooth_only:
        from .lobe_surface import write_joint_lobes
        lobe_masks, lobe_repairs, run["joint_lobe_repair"] = repair_joint_lobes(raw_masks[:5], body, spacing, hu, references)
        joint_surfaces = write_joint_lobes(lobe_masks, affine, out)
    for index, (name, raw) in enumerate(zip(NAMES, raw_masks)):
        reference = None
        if references is not None and name in references.files:
            coarse = references[name]
            coarse_spacing = spacing * (np.asarray(raw.shape) - 1) / (np.asarray(coarse.shape) - 1)
            nearby = ndimage.binary_dilation(coarse, core.ellipsoid(2., coarse_spacing))
            reference = ndimage.zoom(nearby, np.asarray(raw.shape) / coarse.shape, order=0, prefilter=False)
        if smooth_only:
            mask, repair = raw, {"operation": "unchanged BIN mask; mesh smoothing only", "minimum_component_voxels": 0}
        elif index < 5:
            mask, repair = lobe_masks[index], lobe_repairs[index]
        else:
            mask, repair = repair_mask(name, raw, body, spacing, hu, reference)
            repair["reference_supported_component_selection"] = reference is not None
        branch = not smooth_only and name in ("Bronchus", "PulmonaryArtery", "PulmonaryVenous")
        if branch:
            allowed = body & ((hu < -300) if name == "Bronchus" else ((hu > -400) & (hu < 700)))
            if name != "Bronchus":
                allowed &= ~raw_masks[7 if name == "PulmonaryArtery" else 6]
            before_branch_repair = int(mask.sum())
            before_connections = mask
            mask, rejected, connections = repair_branches(mask, allowed, spacing,
                retain_unconnected_minimum_mm3=20.0 if name == "PulmonaryVenous" or reference is not None else None)
            if name == "PulmonaryVenous":
                mask, cleanup = filter_vein_islands(mask, spacing)
                if reference is not None:
                    protected = reference_components(before_connections, reference, fallback_largest=False)
                    mask |= protected
                    cleanup["reference_protected_prediction_voxels"] = int(protected.sum())
                rejected = before_connections & ~mask
                connections["withheld_voxels"] = int(rejected.sum())
                connections["unresolved_components"] = int(ndimage.label(rejected)[1])
                connections["retained_prediction_voxels"] = int((before_connections & mask).sum())
                connections["added_bridge_voxels"] = int((mask & ~before_connections).sum())
                labels, components = ndimage.label(mask)
                sizes = np.bincount(labels.ravel())
                disconnected = mask & (labels != (1 + np.argmax(sizes[1:]))) if components else mask
                connections["remaining_face_connected_components"] = int(components)
                connections["retained_unconnected_components"] = max(0, int(components) - 1)
                connections["retained_unconnected_voxels"] = int((before_connections & disconnected).sum())
                repair["island_cleanup"] = cleanup
                print(f"[islands] {name}: {cleanup['removed_components']} small isolated components removed; "
                      f"{cleanup['components_after']} components retained", flush=True)
            withheld_path = out / "review_withheld" / f"{name}_withheld.npz"
            np.savez_compressed(withheld_path, mask=rejected.astype(np.uint8), affine=affine)
            repair["connected_display"] = connections
            repair["connected_display"]["before_voxels"] = before_branch_repair
            repair["connected_display"]["withheld_mask"] = str(withheld_path)
            print(f"[repair] {name}: {len(connections['accepted_bridges'])} reinforced bridges; "
                  f"{connections['retained_unconnected_components']} unconnected components retained; "
                  f"{int(rejected.sum()):,} voxels withheld for review", flush=True)
        if index < 5:
            sigma, iterations, budget = .9, 10, 30000
        else:
            sigma, iterations, budget = (.45, 5, 60000) if name != "LungTumor" else (2.0, 10, 30000)
        masks[name] = mask
        np.save(out / f"{name}_mask.npy", mask.astype(np.uint8), allow_pickle=False)
        info = {"raw_voxels": original_counts[index], "processed_voxels": int(mask.sum()),
                "voxel_volume_mm3": float(mask.sum() * np.prod(spacing)),
                "minimum_component_voxels": repair["minimum_component_voxels"],
                "largest_component_only": not smooth_only and index >= 5 and name != "PulmonaryVenous" and reference is None}
        info["repair"] = repair
        destination = out / f"{name}.stl"
        if not mask.any():
            destination.unlink(missing_ok=True)
            info["status"] = "no_positive_prediction_after_postprocessing"
        elif index < 5 and not smooth_only:
            info["stl"] = joint_surfaces[name]
            info["surface"] = {"algorithm": joint_surfaces[name]["algorithm"],
                               "triangles": joint_surfaces[name]["output_faces"],
                               "volume_mm3": joint_surfaces[name]["output_quality"]["volume_mm3"]}
            info["status"] = "exported_joint_repaired_display_prediction"
        elif smooth_only:
            print(f"[smooth-only] {name}: {info['processed_voxels']:,} unchanged voxels", flush=True)
            source = out / "surfaces_before_reduction" / f"{name}.stl"
            sigma = .9 if index < 5 else (2.0 if name == "LungTumor" else .45)
            info["surface"] = core.write_stl(mask, affine, source, 1, 10, sigma,
                                               preserve_voxels=name in ("Bronchus", "PulmonaryArtery", "PulmonaryVenous"),
                                               preserve_volume=name == "LungTumor")
            # Equal triangle budget disables reduction; keep every extracted shell.
            info["stl"] = core.decimate_stl(source, destination, info["surface"]["triangles"],
                                           largest_surface=False, minimum_surface_volume_mm3=0)
            info["status"] = "exported_smoothing_only_prediction"
        else:
            source = out / "surfaces_before_reduction" / f"{name}.stl"
            print(f"[surface] {name}: {info['processed_voxels']:,} voxels", flush=True)
            info["surface"] = core.write_stl(mask, affine, source, 1, iterations, sigma,
                                               preserve_voxels=branch, preserve_volume=name == "LungTumor")
            info["stl"] = core.decimate_stl(source, destination, budget,
                largest_surface=name != "PulmonaryVenous" and reference is None,
                minimum_surface_volume_mm3=0 if index < 5 else (5.0 if name == "LungTumor" else 20.0))
            quality = info["stl"]["output_quality"]
            if (name != "PulmonaryVenous" and reference is None and quality["surface_components"] != 1) or quality["boundary_nonmanifold_edges"]:
                raise ValueError(f"{name}: disconnected or invalid final STL")
            info["status"] = "exported_repaired_display_prediction"
        if name in ("PulmonaryArtery", "PulmonaryVenous") and destination.exists():
            from .vessel_surface import refine_stl
            info["vessel_smoothing"] = refine_stl(destination, destination, mask, affine)
            info["stl"]["output_quality"] = info["vessel_smoothing"]["after"]
            info["stl"]["volume_change_percent"] = 100 * (
                info["stl"]["output_quality"]["volume_mm3"] / info["stl"]["source_quality"]["volume_mm3"] - 1)
        run["objects"][name] = info
        (out / "run_metadata.json").write_text(json.dumps(run, ensure_ascii=False, indent=2), encoding="utf-8")
    if not args.no_previews:
        save_overlays(q, masks, spacing, out / "ct_prediction_overlays.png")
        save_scene(out)
        if (out / "LungTumor.stl").exists():
            core.save_surface_preview(out / "LungTumor.stl", out / "tumor_surface_preview.png")
            save_tumor_detail(out, masks["LungTumor"], affine)
    run["status"] = "complete"
    if references is not None:
        references.close()
        run["reference_support"] = str(reference_path)
        run["reference_policy"] = "CT-aligned partial reference protects or selects predicted components only; reference voxels are never copied into predictions"
    run["elapsed_seconds"] = time.perf_counter() - started
    run["notes"] = ["Five lobe and artery/vein overlaps are assigned to the maximum positive logit before mesh smoothing.",
                    "Lobes use a joint categorical map, CT-supported shallow pit repair and shared-vertex Windowed Sinc smoothing, capped at 2.5 mm.",
                    "Airway/tumor transpose Y,X to source-native cache X,Y; vessel uses DICOM BIN Y,X; all retain native spacing.",
                    "Airway/tumor original NIfTI direction signs vary or are unavailable; no fixed RAS sign is inferred for these tasks.",
                    "Paired reference STLs are partial software outputs, not certified ground-truth labels.",
                    "The airway model provides a single airway class, without bronchopulmonary segment labels.",
                    "Raw channel masks are preserved; raw logits are not stored.",
                    "Tumor STL retains reference-supported candidates when available; otherwise it displays the largest repaired candidate.",
                    "Pulmonary vein joins CT-supported gaps between peripheral components as well as the main trunk. No forced CT-unsupported connection.",
                    "Vein display removes isolated components below 500 mm3 unless extent >=25 mm and PCA elongation >=3; raw predictions are unchanged.",
                    "Original model output BIN is never changed by postprocessing; withheld branch counts are recorded in the run metadata."]
    if smooth_only:
        run["notes"] = ["Every foreground voxel in the prediction BIN is used without mask changes.",
                        "No body clipping, island removal, largest-component selection, hole filling, bridging or decimation.",
                        "Independent component Gaussian surface fields: lobes 0.9 mm, tumor 2.0 mm, branches 0.45 mm (thin-branch protection).",
                        "Tumor contour level compensates Gaussian shrinkage using the original per-component voxel count; exact mesh volume may still differ.",
                        "Marching cubes step=1, 10 Taubin iterations and 15 Windowed Sinc iterations in source CT coordinates.",
                        "Source-header affine is retained for CT overlay alignment; inconsistent anatomical direction in source headers is not silently overwritten.",
                        "No explicit component filter is applied; Gaussian surface extraction can remove sub-resolution fragments or change topology.",
                        "Smoothing does not correct model false positives or anatomical labels."]
    if any("vessel_smoothing" in info for info in run["objects"].values()):
        run["notes"].append("Vessels receive thickness-adaptive Taubin / Windowed Sinc refinement; "
                            "saved connectivity, component volume, displacement and skeleton clearance are checked.")
    (out / "run_metadata.json").write_text(json.dumps(run, ensure_ascii=False, indent=2), encoding="utf-8")
    from .export_results import export_results
    export_results(out, args.view_dir or out.parent / "STL查看")
    print(f"[done] {out}; {run['elapsed_seconds']:.1f}s", flush=True)


if __name__ == "__main__":
    main()
