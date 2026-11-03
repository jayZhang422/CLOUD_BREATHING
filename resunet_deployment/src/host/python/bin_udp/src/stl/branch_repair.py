"""Reconnect short same-class gaps; keep unsupported branches for separate review."""

import numpy as np
from scipy import ndimage
from skimage.graph import MCP_Geometric


def repair_branches(mask, allowed, spacing, maximum_mm=6.0, retain_unconnected_minimum_mm3=None):
    structure = ndimage.generate_binary_structure(3, 1)
    labels, count = ndimage.label(mask, structure)
    if not count:
        return mask.copy(), np.zeros_like(mask), {"accepted_bridges": [], "unresolved_components": 0,
            "withheld_voxels": 0, "retained_prediction_voxels": 0, "added_bridge_voxels": 0,
            "retained_unconnected_components": 0, "retained_unconnected_voxels": 0,
            "remaining_face_connected_components": 0,
            "retain_unconnected_minimum_mm3": retain_unconnected_minimum_mm3,
            "maximum_bridge_distance_mm": maximum_mm}
    counts = np.bincount(labels.ravel())
    main_id = 1 + np.argmax(counts[1:])
    anchor = labels == main_id
    parents = np.arange(count + 1)
    eligible = counts * np.prod(spacing) >= (retain_unconnected_minimum_mm3 or np.inf)
    eligible[0] = False
    eligible[main_id] = True

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    boxes = ndimage.find_objects(labels)
    pending = [i for i in np.argsort(counts[1:])[::-1] + 1 if i != main_id]
    padding = np.ceil(maximum_mm / spacing).astype(int) + 2
    bridges = []
    # A 1-voxel line can disappear during Gaussian surface extraction.
    radius = max(1.3, float(np.max(spacing)) + .05)
    for _ in range(4):
        progress = False
        for index in pending[:]:
            box = boxes[index - 1]
            region = tuple(slice(max(0, s.start - int(p)), min(mask.shape[k], s.stop + int(p)))
                           for k, (s, p) in enumerate(zip(box, padding)))
            candidate = labels[region] == index
            target = anchor[region]
            if retain_unconnected_minimum_mm3 is not None:
                # A peripheral branch may join another peripheral branch before
                # either has a supported path to the main trunk. Avoid cycles.
                groups = np.array([root(i) for i in range(count + 1)])
                local_labels = labels[region]
                target = eligible[local_labels] & (groups[local_labels] != root(index))
            if not target.any():
                continue
            distances = ndimage.distance_transform_edt(~target, sampling=spacing)
            distances[~candidate] = np.inf
            point = np.array(np.unravel_index(distances.argmin(), distances.shape))
            gap = float(distances[tuple(point)])
            if gap > maximum_mm:
                continue
            local = tuple(slice(0, n) for n in candidate.shape)
            support = allowed[region] | candidate | target
            # Search all facing points: the Euclidean-nearest pair may cross air
            # even when another short, CT-supported route exists nearby.
            starts = np.argwhere(candidate & ~ndimage.binary_erosion(candidate))
            ends = np.argwhere(target & ~ndimage.binary_erosion(target))
            costs = np.where(support, 1., np.inf)
            finder = MCP_Geometric(costs, fully_connected=False, sampling=tuple(spacing))
            cumulative, _ = finder.find_costs(starts, ends, find_all_ends=False)
            end_costs = cumulative[tuple(ends.T)]
            if not np.isfinite(end_costs).any():
                continue
            end = tuple(ends[np.argmin(end_costs)])
            path = np.asarray(finder.traceback(end))
            start = tuple(path[0])
            length = float(np.linalg.norm(np.diff(path, axis=0) * spacing, axis=1).sum())
            if length > maximum_mm * 1.8:
                continue
            centerline = np.zeros(support.shape, dtype=bool)
            centerline[tuple(path.T)] = True
            tube = ndimage.distance_transform_edt(~centerline, sampling=spacing) <= radius
            tube &= support
            combined = target[local] | candidate[local] | tube
            local_labels, _ = ndimage.label(combined, structure)
            if local_labels[start] != local_labels[end]:
                continue
            anchor[region] |= candidate
            anchor[region][local] |= tube
            if retain_unconnected_minimum_mm3 is not None:
                parents[root(index)] = root(int(labels[region][end]))
            pending.remove(index)
            bridges.append({"component_voxels": int(counts[index]), "gap_mm": gap,
                            "path_length_mm": length, "tube_radius_mm": radius})
            progress = True
        if not progress:
            break
    # A missing CT-supported route does not establish that a predicted branch is false.
    retained_unconnected = []
    if retain_unconnected_minimum_mm3 is not None:
        retained_unconnected = [i for i in pending
                               if counts[i] * np.prod(spacing) >= retain_unconnected_minimum_mm3]
        keep = np.zeros(len(counts), dtype=bool)
        keep[retained_unconnected] = True
        anchor |= keep[labels]
    rejected = mask & ~anchor
    _, unresolved = ndimage.label(rejected, structure)
    final_labels, remaining = ndimage.label(anchor, structure)
    largest = 1 + np.argmax(np.bincount(final_labels.ravel())[1:])
    disconnected = anchor & (final_labels != largest)
    return anchor, rejected, {"accepted_bridges": bridges, "unresolved_components": int(unresolved),
                              "withheld_voxels": int(rejected.sum()),
                              "retained_prediction_voxels": int((mask & anchor).sum()),
                              "added_bridge_voxels": int((anchor & ~mask).sum()),
                              "retained_unconnected_components": max(0, int(remaining) - 1),
                              "remaining_face_connected_components": int(remaining),
                              "retained_unconnected_voxels": int((mask & disconnected).sum()),
                              "retain_unconnected_minimum_mm3": retain_unconnected_minimum_mm3,
                              "maximum_bridge_distance_mm": maximum_mm}


def filter_vein_islands(mask, spacing):
    """Display cleanup: keep substantial components or long slender branches."""
    labels, count = ndimage.label(mask, ndimage.generate_binary_structure(3, 3))
    counts = np.bincount(labels.ravel())
    keep = np.zeros(count + 1, dtype=bool)
    if count:
        keep[1 + np.argmax(counts[1:])] = True
    for index, box in enumerate(ndimage.find_objects(labels), 1):
        if keep[index] or counts[index] * np.prod(spacing) >= 500:
            keep[index] = True
        elif max((s.stop - s.start - 1) * d for s, d in zip(box, spacing)) >= 25:
            points = np.argwhere(labels[box] == index) * spacing
            eigenvalues = np.linalg.eigvalsh(np.cov(points.T))
            keep[index] = np.sqrt(eigenvalues[-1] / max(eigenvalues[-2], .001)) >= 3
    result = keep[labels]
    return result, {"operation": "remove small isolated candidates; protect long slender branches",
                    "minimum_volume_mm3": 500, "protected_branch_minimum_extent_mm": 25,
                    "protected_branch_minimum_pca_elongation": 3,
                    "components_before": int(count), "components_after": int(keep.sum()),
                    "removed_components": int(count - keep.sum()),
                    "removed_voxels": int((mask & ~result).sum())}
