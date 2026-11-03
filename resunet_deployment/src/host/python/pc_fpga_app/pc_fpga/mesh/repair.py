"""Model 掩膜修补算法快照；只处理派生掩膜，不导入推理模型。"""
import numpy as np
from scipy import ndimage
from . import reference as core
from .branch_repair import repair_branches, filter_vein_islands
from ..ct.prediction_io import CHANNELS
LOBE_NAMES = CHANNELS[:5]

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


def prepare_masks(raw_masks, body, spacing, hu, affine, out, references=None, progress=lambda text: None):
    """与 Model postprocess_case 使用同一修补顺序；保存被暂缓显示的分支。"""
    masks, repairs, details = [], [], {}
    (out / "review_withheld").mkdir(exist_ok=True)
    if references is not None:
        raw_masks[:5], details["minor_lobe_boundary_adjustment"] = adjust_lobe_boundaries(raw_masks[:5], references, spacing)
    lobe_masks, lobe_repairs, details["joint_lobe_repair"] = repair_joint_lobes(raw_masks[:5], body, spacing, hu, references)
    for index, (name, raw) in enumerate(zip(CHANNELS, raw_masks)):
        reference = None
        if references is not None and name in references.files:
            coarse = references[name]
            coarse_spacing = spacing * (np.asarray(raw.shape) - 1) / (np.asarray(coarse.shape) - 1)
            nearby = ndimage.binary_dilation(coarse, core.ellipsoid(2., coarse_spacing))
            reference = ndimage.zoom(nearby, np.asarray(raw.shape) / coarse.shape, order=0, prefilter=False)
        if index < 5:
            mask, repair = lobe_masks[index], lobe_repairs[index]
        else:
            mask, repair = repair_mask(name, raw, body, spacing, hu, reference)
            repair["reference_supported_component_selection"] = reference is not None
        branch = name in ("Bronchus", "PulmonaryArtery", "PulmonaryVenous")
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
                progress(f"{name}: removed {cleanup['removed_components']} islands; retained {cleanup['components_after']} components")
            withheld_path = out / "review_withheld" / f"{name}_withheld.npz"
            np.savez_compressed(withheld_path, mask=rejected.astype(np.uint8), affine=affine)
            repair["connected_display"] = connections
            repair["connected_display"]["before_voxels"] = before_branch_repair
            repair["connected_display"]["withheld_mask"] = str(withheld_path)
            progress(f"[repair] {name}: {len(connections['accepted_bridges'])} reinforced bridges; "
                  f"{connections['retained_unconnected_components']} unconnected components retained; "
                  f"{int(rejected.sum()):,} voxels withheld for review")
        masks.append(mask)
        repairs.append(repair)
    return masks, repairs, details
