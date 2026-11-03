"""Smooth vessel trunks more strongly while retaining narrow predicted branches."""

import argparse
import json
from pathlib import Path
import shutil
import tempfile

import numpy as np
from scipy import ndimage, sparse
from scipy.spatial import cKDTree
from skimage.morphology import skeletonize
from vtkmodules.util.numpy_support import numpy_to_vtk, vtk_to_numpy
from vtkmodules.vtkCommonDataModel import vtkPolyData
from vtkmodules.vtkFiltersCore import (
    vtkImplicitPolyDataDistance, vtkPolyDataConnectivityFilter, vtkWindowedSincPolyDataFilter,
)
from vtkmodules.vtkIOGeometry import vtkSTLReader, vtkSTLWriter

from .lung_ct_to_stl import mesh_quality, sha256_file, taubin_smooth


VESSELS = ("PulmonaryArtery", "PulmonaryVenous")


def read_stl(path):
    reader = vtkSTLReader()
    reader.SetFileName(str(path))
    reader.Update()
    mesh = vtkPolyData()
    mesh.DeepCopy(reader.GetOutput())
    return mesh


def skeleton_geometry(mask, affine):
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    region = ndimage.find_objects(mask.astype(np.uint8), max_label=1)[0]
    offset = np.array([axis.start for axis in region]) - 1
    cropped = np.pad(mask[region].astype(bool), 1)
    distance = ndimage.distance_transform_edt(cropped, sampling=spacing)
    indices = np.argwhere(skeletonize(cropped))
    if not len(indices):
        indices = np.array([np.unravel_index(distance.argmax(), distance.shape)])
    radii = distance[tuple(indices.T)]
    centers = (affine[:3, :3] @ (indices + offset).T).T + affine[:3, 3]
    return centers, radii, spacing


def interior_clearance(mesh, centers):
    distance = vtkImplicitPolyDataDistance()
    distance.SetInput(mesh)
    return -np.array([distance.EvaluateFunction(point) for point in centers])


def component_volumes(mesh):
    regions = vtkPolyDataConnectivityFilter()
    regions.SetInputData(mesh)
    regions.SetExtractionModeToAllRegions()
    regions.ColorRegionsOn()
    regions.Update()
    colored = regions.GetOutput()
    points = vtk_to_numpy(colored.GetPoints().GetData()).astype(float)
    faces = vtk_to_numpy(colored.GetPolys().GetConnectivityArray()).reshape(-1, 3)
    labels = vtk_to_numpy(colored.GetPointData().GetArray("RegionId"))
    centers = np.stack([np.bincount(labels, weights=points[:, k]) / np.bincount(labels)
                        for k in range(3)], axis=1)
    face_labels = labels[faces[:, 0]]
    triangles = points[faces] - centers[face_labels, None]
    return abs(np.bincount(face_labels, weights=np.einsum(
        "ij,ij->i", triangles[:, 0], np.cross(triangles[:, 1], triangles[:, 2])) / 6))


def refine_stl(source_path, destination, mask, affine, *, gentle_iterations=15,
               strong_iterations=60, strong_passband=.01, strength=1.):
    """Refine an existing STL; the prediction mask is only a thickness constraint."""
    source = read_stl(source_path)
    before = mesh_quality(source)
    if before["boundary_nonmanifold_edges"] or not before["triangles"] or not mask.any():
        raise ValueError("Vessel smoothing needs a closed STL and its nonempty prediction mask")
    points = vtk_to_numpy(source.GetPoints().GetData()).astype(float)
    faces = vtk_to_numpy(source.GetPolys().GetConnectivityArray()).reshape(-1, 3)
    centers, skeleton_radii, spacing = skeleton_geometry(mask, affine)
    _, nearest = cKDTree(centers).query(points, workers=-1)
    radius = skeleton_radii[nearest].copy()
    tree = cKDTree(points)
    # Approximate local thickness by the largest nearby inscribed skeleton sphere.
    # The half-voxel margin accounts for the extracted surface between voxel centers.
    for center, r in zip(centers, skeleton_radii):
        if r > 1.5:
            chosen = tree.query_ball_point(center, r + .5 * spacing.max())
            radius[chosen] = np.maximum(radius[chosen], r)
    edges = np.unique(np.sort(np.concatenate(
        (faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]])), axis=1), axis=0)
    rows = np.r_[edges[:, 0], edges[:, 1]]
    cols = np.r_[edges[:, 1], edges[:, 0]]
    adjacency = sparse.csr_matrix((np.ones(len(rows)), (rows, cols)),
                                 shape=(len(points), len(points)))
    average = sparse.diags(1 / np.asarray(adjacency.sum(axis=1)).ravel()) @ adjacency
    for _ in range(15):
        radius = .5 * radius + .5 * (average @ radius)

    def transition(lower, upper):
        t = np.clip((radius - lower) / (upper - lower), 0, 1)
        return t * t * (3 - 2 * t)

    gentle = taubin_smooth(points.copy(), faces, gentle_iterations)
    smooth = vtkWindowedSincPolyDataFilter()
    smooth.SetInputData(source)
    smooth.SetNumberOfIterations(strong_iterations)
    smooth.SetPassBand(strong_passband)
    smooth.NormalizeCoordinatesOn()
    smooth.FeatureEdgeSmoothingOff()
    smooth.BoundarySmoothingOff()
    smooth.NonManifoldSmoothingOff()
    smooth.Update()
    strong = vtk_to_numpy(smooth.GetOutput().GetPoints().GetData()).astype(float)
    refined = (points + transition(1.5, 2.5)[:, None] * (gentle - points)
               + transition(3., 6.)[:, None] * (strong - gentle))
    refined = points + strength * (refined - points)
    mesh = vtkPolyData()
    mesh.DeepCopy(source)
    original_clearance = interior_clearance(source, centers)
    supported = original_clearance > .25
    if not supported.any():
        raise ValueError("Prediction skeleton does not lie inside the source STL")
    protected = set()
    for _ in range(5):
        mesh.GetPoints().SetData(numpy_to_vtk(refined, deep=True))
        clearance = interior_clearance(mesh, centers)
        narrow = np.flatnonzero(supported & (clearance < .8 * original_clearance - 1e-4))
        if not len(narrow):
            break
        taper = np.ones(len(points))
        for index in narrow:
            protected.add(int(index))
            sigma = max(2., 2 * original_clearance[index])
            chosen = np.array(tree.query_ball_point(centers[index], 3 * sigma), dtype=int)
            distance_squared = ((points[chosen] - centers[index]) ** 2).sum(axis=1)
            taper[chosen] = np.minimum(taper[chosen],
                                      1 - np.exp(-distance_squared / (2 * sigma * sigma)))
        # Reduce motion smoothly near threatened branches, without clipping individual vertices.
        refined = points + taper[:, None] * (refined - points)
    mesh.GetPoints().SetData(numpy_to_vtk(refined, deep=True))

    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as folder:
        temporary = Path(folder) / destination.name
        writer = vtkSTLWriter()
        writer.SetFileName(str(temporary))
        writer.SetFileTypeToBinary()
        writer.SetInputData(mesh)
        if not writer.Write():
            raise OSError(f"Could not write {destination}")
        saved = read_stl(temporary)
        after = mesh_quality(saved)
        if (after["boundary_nonmanifold_edges"] or
                any(after[key] != before[key] for key in ("triangles", "vertices", "surface_components"))):
            raise ValueError("Vessel refinement changed saved mesh connectivity")
        # STL readers reorder points; unchanged triangle order supplies exact correspondence.
        saved_faces = vtk_to_numpy(saved.GetPolys().GetConnectivityArray()).reshape(-1, 3)
        saved_points = np.empty_like(points)
        saved_points[faces.ravel()] = vtk_to_numpy(saved.GetPoints().GetData())[saved_faces.ravel()]
        displacement = np.linalg.norm(saved_points - points, axis=1)
        volumes_before, volumes_after = component_volumes(source), component_volumes(saved)
        volume_changes = 100 * (volumes_after / volumes_before - 1)
        clearance = interior_clearance(saved, centers)
        if (displacement.max() > 2.0 or np.max(abs(volume_changes)) > 5.0 or
                np.any(clearance[supported] < .8 * original_clearance[supported] - 1e-4)):
            raise ValueError("Vessel refinement exceeded limits: "
                             f"displacement={displacement.max():.3f} mm, "
                             f"component_volume_change={np.max(abs(volume_changes)):.3f}%, "
                             f"minimum_clearance_ratio={np.min(clearance[supported] / original_clearance[supported]):.3f}")
        thin = supported & (skeleton_radii <= 2.5)
        report = {
            "algorithm": "Thickness-adaptive Taubin / VTK Windowed Sinc; local branch backoff",
            "gentle_taubin_iterations": gentle_iterations, "strong_sinc_iterations": strong_iterations,
            "strong_sinc_passband": strong_passband, "smoothing_strength": strength,
            "gentle_radius_transition_mm": [1.5, 2.5], "strong_radius_transition_mm": [3., 6.],
            "radius_field_averaging_iterations": 15, "before": before, "after": after,
            "volume_change_percent": 100 * (after["volume_mm3"] / before["volume_mm3"] - 1),
            "component_volume_changes_percent": volume_changes.tolist(),
            "displacement_p50_p90_p99_max_mm": np.percentile(displacement, [50, 90, 99, 100]).tolist(),
            "supported_skeleton_samples": int(supported.sum()),
            "retained_skeleton_samples": int(np.count_nonzero(clearance[supported] > 0)),
            "thin_skeleton_samples": int(thin.sum()),
            "thin_clearance_ratio_p0_p5_p50_p95": (
                np.percentile(clearance[thin] / original_clearance[thin], [0, 5, 50, 95]).tolist()
                if thin.any() else []),
            "locally_protected_skeleton_samples": len(protected),
            "coordinate_system": "DICOM LPS millimetres",
            "limits": "Move <=2 mm; each closed component volume change <=5%; supported skeleton clearance >=80%",
            "validation_note": "Skeleton samples and component checks do not prove anatomical accuracy or absence of all self-intersections",
        }
        temporary.replace(destination)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--mask-dir", type=Path, required=True, help="Matching postprocessing work directory")
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    source, output = args.source_dir.resolve(), args.output_dir.resolve()
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        parser.error("Keep the source and output directories separate")
    run = json.loads((args.mask_dir / "run_metadata.json").read_text(encoding="utf-8"))
    affine = np.asarray(run["affine_z_y_x_to_lps_mm"], dtype=float)
    hashes = {path.name: sha256_file(path) for path in source.glob("*.stl")}
    bins = {key: {"path": run[key], "sha256": sha256_file(Path(run[key]))}
            for key in ("input_bin", "prediction_bin")}
    for key, record in bins.items():
        if record["sha256"] != run[key.replace("_bin", "_sha256")]:
            raise ValueError(f"BIN differs from the postprocessing record: {key}")
    report = {"source_dir": str(source), "mask_dir": str(args.mask_dir.resolve()),
              "objects": {}, "source_stl_sha256": hashes, "unchanged_bin": bins}
    from .chest_ct_to_stl import save_scene
    from .export_results import export_results
    with tempfile.TemporaryDirectory() as folder:
        staging = Path(folder)
        for filename in hashes:
            shutil.copy2(source / filename, staging / filename)
        for name in VESSELS:
            filename = f"{name}.stl"
            if sha256_file(args.mask_dir / filename) != hashes[filename]:
                raise ValueError(f"Source STL differs from the supplied mask work directory: {name}")
            mask = np.load(args.mask_dir / f"{name}_mask.npy", mmap_mode="r")
            report["objects"][name] = refine_stl(source / filename, staging / filename, mask, affine)
            print(f"[vessel] {name}: volume {report['objects'][name]['volume_change_percent']:+.3f}%", flush=True)
        run["vessel_smoothing"] = report["objects"]
        (staging / "run_metadata.json").write_text(json.dumps(run, ensure_ascii=False, indent=2), encoding="utf-8")
        save_scene(staging)
        export_results(staging, output)
    for filename, expected in hashes.items():
        if sha256_file(source / filename) != expected:
            raise ValueError(f"Source STL changed: {filename}")
        if filename not in {f"{name}.stl" for name in VESSELS} and sha256_file(output / filename) != expected:
            raise ValueError(f"Non-vessel STL changed: {filename}")
    for record in bins.values():
        if sha256_file(Path(record["path"])) != record["sha256"]:
            raise ValueError("Input or prediction BIN changed")
    (output / "vessel_smoothing_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    with (output / "查看说明.md").open("a", encoding="utf-8") as stream:
        stream.write("\n本目录另加强肺动脉、肺静脉的厚度自适应平滑：主干使用较强平滑，细枝减弱；"
                     "对模型掩膜骨架附近变窄的位置局部回退。闭合分量数量保留，每分量体积变化≤5%，"
                     "顶点移动≤2 mm，已在原表面内部的骨架采样点保留至少80%的表面距离。"
                     "这不是医学准确性或完整细枝保真的证明。其他 STL 与源目录逐字节相同；"
                     "CT、输入 BIN、模型输出 BIN 均未修改。参数与实测值见 vessel_smoothing_report.json。\n")
    print(f"[done] {output}", flush=True)


if __name__ == "__main__":
    main()
