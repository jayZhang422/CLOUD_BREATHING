"""参考 Model 的纯网格函数快照；去除 Torch/模型推理依赖。"""
import struct
from pathlib import Path
import numpy as np
from scipy import ndimage, sparse
from skimage.measure import marching_cubes


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

from ..ct.prediction_io import file_sha256 as sha256_file
