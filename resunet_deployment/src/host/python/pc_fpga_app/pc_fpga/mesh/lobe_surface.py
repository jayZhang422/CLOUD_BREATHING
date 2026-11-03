"""Joint, displacement-constrained lung lobe surfaces with shared interfaces."""

from pathlib import Path

import numpy as np
from scipy import ndimage

from . import reference as core


def repair_lobe_envelope(masks, body, spacing, hu):
    """Fill shallow CT-supported pits and small enclosed gaps, preserving labels."""
    labels = np.zeros(masks[0].shape, np.uint8)
    for index, mask in enumerate(masks, 1):
        labels[mask] = index
    original = labels.copy()
    details = {"maximum_fill_distance_mm": 2.5, "closing_radius_mm": 3.0,
               "maximum_added_fraction_per_lobe": .01, "boundary_sigma_mm": 1.5,
               "maximum_boundary_change_fraction_per_lobe": .01, "lungs": []}
    for ids in ((1, 2), (3, 4, 5)):
        lung = np.isin(original, ids)
        if not lung.any():
            continue
        occupied = np.where(lung)
        pad = np.ceil(5 / spacing).astype(int)
        box = tuple(slice(max(0, int(p.min()) - int(r)), min(lung.shape[a], int(p.max()) + int(r) + 1))
                    for a, (p, r) in enumerate(zip(occupied, pad)))
        local = lung[box]
        # A categorical Gaussian vote removes thin label spikes without filling
        # the fissure with a second, independently expanded lobe.
        local_labels = original[box]
        best = np.zeros(local.shape, np.float32)
        winner = local_labels.copy()
        own = np.zeros(local.shape, np.float32)
        for i in ids:
            field = ndimage.gaussian_filter((local_labels == i).astype(np.float32), 1.5 / spacing)
            own[local_labels == i] = field[local_labels == i]
            take = field > best
            best[take] = field[take]
            winner[take] = i
        candidate_boundary = local & (winner != local_labels) & (own < .4) & (best > .45)
        used_boundary = {i: 0 for i in ids}
        budgets_boundary = {i: int(np.count_nonzero(original == i) * .01) for i in ids}
        for target in ids:
            distance_to_target = ndimage.distance_transform_edt(local_labels != target, sampling=spacing)
            for donor in ids:
                if donor == target:
                    continue
                patches, count = ndimage.label(candidate_boundary & (winner == target) & (local_labels == donor)
                                               & (distance_to_target <= 1.5))
                sizes_boundary = np.bincount(patches.ravel())
                accepted_boundary = np.zeros(count + 1, bool)
                for component in np.argsort(sizes_boundary[1:]) + 1:
                    size = int(sizes_boundary[component])
                    if (size * np.prod(spacing) <= 1000 and
                            used_boundary[target] + size <= budgets_boundary[target] and
                            used_boundary[donor] + size <= budgets_boundary[donor]):
                        accepted_boundary[component] = True
                        used_boundary[target] += size
                        used_boundary[donor] += size
                labels[box][accepted_boundary[patches]] = target
        distance, nearest = ndimage.distance_transform_edt(~local, sampling=spacing, return_indices=True)
        closed = ndimage.binary_closing(local, structure=core.ellipsoid(3., spacing))
        enclosed = ndimage.binary_fill_holes(local)
        target = (closed & (hu[box] < -300)) | enclosed
        candidate = target & ~local & (original[box] == 0) & body[box] & (distance <= 2.5)
        components, count = ndimage.label(candidate)
        sizes = np.bincount(components.ravel()) * np.prod(spacing)
        nearest_labels = original[box][tuple(nearest)]
        budgets = {i: int(np.count_nonzero(original == i) * .01) for i in ids}
        used = {i: 0 for i in ids}
        counts = {i: np.bincount(components[nearest_labels == i], minlength=count + 1) for i in ids}
        accepted = np.zeros(count + 1, bool)
        for component in np.argsort(sizes[1:]) + 1:
            if sizes[component] > 1000.:
                continue
            changes = {i: int(counts[i][component]) for i in ids}
            if all(used[i] + changes[i] <= budgets[i] for i in ids):
                accepted[component] = True
                used = {i: used[i] + changes[i] for i in ids}
        patch = accepted[components]
        labels[box][patch] = nearest_labels[patch]
        details["lungs"].append({"labels": list(ids), "candidate_voxels": int(candidate.sum()),
                                 "added_voxels_per_lobe": used, "boundary_changed_voxels_per_lobe": used_boundary})
    details["added_voxels"] = int(np.count_nonzero((labels > 0) & (original == 0)))
    details["changed_existing_labels"] = int(np.count_nonzero((original > 0) & (labels != original)))
    return [labels == index for index in range(1, 6)], details


def write_joint_lobes(masks, affine, directory, iterations=60, maximum_move_mm=2.5):
    """Fair shared label-map vertices, then export closed individual lung lobes."""
    from vtkmodules.vtkCommonCore import vtkPoints
    from vtkmodules.vtkCommonDataModel import vtkImageData, vtkPolyData, vtkCellArray
    from vtkmodules.vtkFiltersGeneral import vtkDiscreteMarchingCubes
    from vtkmodules.vtkFiltersCore import vtkWindowedSincPolyDataFilter, vtkCleanPolyData
    from vtkmodules.vtkIOGeometry import vtkSTLReader, vtkSTLWriter
    from vtkmodules.util.numpy_support import numpy_to_vtk, vtk_to_numpy, numpy_to_vtkIdTypeArray

    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    labels = np.zeros(masks[0].shape, np.uint8)
    for index, mask in enumerate(masks, 1):
        labels[mask] = index
    if not labels.any():
        return {}
    image = vtkImageData()
    padded = np.pad(labels, 1)
    image.SetDimensions(*padded.shape[::-1])
    image.SetOrigin(-1, -1, -1)
    image.GetPointData().SetScalars(numpy_to_vtk(padded.ravel(), deep=True))
    surface = vtkDiscreteMarchingCubes()
    surface.SetInputData(image)
    surface.GenerateValues(5, 1, 5)
    surface.ComputeNormalsOff()
    surface.Update()
    mesh = surface.GetOutput()
    original = vtk_to_numpy(mesh.GetPoints().GetData()).astype(np.float64)
    original = original[:, ::-1] @ affine[:3, :3].T + affine[:3, 3]
    mesh.GetPoints().SetData(numpy_to_vtk(np.ascontiguousarray(original), deep=True))
    smoother = vtkWindowedSincPolyDataFilter()
    smoother.SetInputData(mesh)
    smoother.SetNumberOfIterations(iterations)
    smoother.SetPassBand(.001)
    smoother.NonManifoldSmoothingOn()
    smoother.NormalizeCoordinatesOn()
    smoother.BoundarySmoothingOff()
    smoother.FeatureEdgeSmoothingOff()
    if iterations:
        smoother.Update()
        smoothed = smoother.GetOutput()
    else:
        # BIN→STL 阶段只提取共享表面，60 轮联合平滑留到 Smooth。
        smoothed = mesh
    delta = vtk_to_numpy(smoothed.GetPoints().GetData()) - original
    distance = np.linalg.norm(delta, axis=1)
    delta *= np.minimum(1., maximum_move_mm / np.maximum(distance, 1e-8))[:, None]
    points = np.ascontiguousarray(original + delta)
    faces = vtk_to_numpy(smoothed.GetPolys().GetConnectivityArray()).reshape(-1, 3)
    classes = vtk_to_numpy(smoothed.GetCellData().GetScalars())
    names = ["LeftUpperLobe", "LeftLowerLobe", "RightUpperLobe", "RightMiddleLobe", "RightLowerLobe"]
    objects = {}
    for label, name in enumerate(names, 1):
        selected = np.ascontiguousarray(faces[classes == label], dtype=np.int64)
        if not len(selected):
            continue
        if np.linalg.det(affine[:3, :3][:, ::-1]) < 0:
            selected = selected[:, [0, 2, 1]].copy()
        vtk_points = vtkPoints()
        vtk_points.SetData(numpy_to_vtk(points, deep=True))
        cells = vtkCellArray()
        cells.SetData(numpy_to_vtkIdTypeArray(np.arange(0, 3 * len(selected) + 1, 3, dtype=np.int64), deep=True),
                      numpy_to_vtkIdTypeArray(selected.ravel(), deep=True))
        single = vtkPolyData()
        single.SetPoints(vtk_points)
        single.SetPolys(cells)
        clean = vtkCleanPolyData()
        clean.SetInputData(single)
        clean.Update()
        filtered, fragments = core.remove_small_surfaces(clean.GetOutput(), 5.)
        path = directory / f"{name}.stl"
        writer = vtkSTLWriter()
        writer.SetFileName(str(path))
        writer.SetFileTypeToBinary()
        writer.SetInputData(filtered)
        if not writer.Write():
            raise OSError(f"Could not write {path}")
        reader = vtkSTLReader()
        reader.SetFileName(str(path))
        reader.Update()
        quality = core.mesh_quality(reader.GetOutput())
        if quality["boundary_nonmanifold_edges"] or quality["volume_mm3"] <= 0:
            raise ValueError(f"{name}: invalid joint surface: {quality}")
        objects[name] = {"path": str(path), "algorithm": "Joint discrete marching cubes + Windowed Sinc",
                         "surface_smoothing_iterations": iterations, "surface_smoothing_passband": .001,
                         "maximum_move_mm": maximum_move_mm, "measured_maximum_move_mm": float(np.linalg.norm(delta, axis=1).max()),
                         "surface_fragment_filter": fragments,
                         "output_faces": quality["triangles"], "output_quality": quality}
    return objects
