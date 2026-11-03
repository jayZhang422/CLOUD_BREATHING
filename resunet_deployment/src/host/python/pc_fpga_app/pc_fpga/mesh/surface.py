from pathlib import Path
import numpy as np
from .reference import mesh_quality, remove_small_surfaces

def smooth_surface(input_path: Path, output_path: Path,
                 largest_surface: bool = False, minimum_surface_volume_mm3: float = 0.0, iterations=15, passband=.08) -> dict:
    """沿用 Model 的表面清理和 Sinc；不执行减面。"""
    from vtkmodules.vtkFiltersCore import vtkCleanPolyData
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

    from vtkmodules.vtkCommonExecutionModel import vtkTrivialProducer
    reduction = vtkTrivialProducer()
    reduction.SetOutput(source)
    algorithm = "Model surface cleanup + Windowed Sinc (no reduction)"
    smoother = vtkWindowedSincPolyDataFilter()
    smoother.SetInputConnection(reduction.GetOutputPort())
    smoother.SetNumberOfIterations(iterations)
    smoother.SetPassBand(passband)
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
        "surface_smoothing_iterations": 0 if saved_source_fallback else iterations,
        "surface_smoothing_passband": passband,
        "source_faces": int(source_faces),
        "original_source_faces": int(original_faces),
        "removed_coincident_internal_faces": removed_internal_faces,
        "largest_surface_only": largest_surface,
        "surface_fragment_filter": surface_filter,
        "reduction_applied": False,
        "output_faces": int(result.GetNumberOfPolys()),
        "source_quality": before,
        "output_quality": after,
        "volume_change_percent": 100.0 * (after["volume_mm3"] / before["volume_mm3"] - 1.0),
    }
