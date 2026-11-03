"""BIN2STL / Smooth / Cut：三个独立、可重跑的文件阶段。"""
from pathlib import Path
import shutil

import numpy as np

from ..ct.prediction_io import CHANNELS, file_sha256, prediction_mask, read_prediction
from ..files import check_file, read_json, write_json


def category(index):
    return "lobes" if index < 5 else "airway" if index == 5 else "vessels" if index < 8 else "tumor"


def _new_output(directory):
    directory = Path(directory)
    if (directory / "manifest.json").exists():
        raise FileExistsError(f"该阶段已发布，请指定新输出目录：{directory}")
    directory.mkdir(parents=True, exist_ok=True)
    return directory


def bin_to_stl(prediction_dir, output_dir, progress=lambda text: None, **kwargs):
    from .pipeline import bin_to_stl as convert
    return convert(prediction_dir, output_dir, progress, **kwargs)


def read_stl(path):
    from vtkmodules.vtkCommonDataModel import vtkPolyData
    from vtkmodules.vtkIOGeometry import vtkSTLReader
    reader = vtkSTLReader()
    reader.SetFileName(str(path))
    reader.Update()
    mesh = vtkPolyData()
    mesh.DeepCopy(reader.GetOutput())
    if mesh.GetNumberOfPolys() == 0:
        raise ValueError(f"STL 没有三角面：{path}")
    return mesh


def _quality_ok(before, after, volume_limit):
    return (after["boundary_nonmanifold_edges"] == 0
            and after["surface_components"] == before["surface_components"]
            and before["volume_mm3"] > 0
            and abs(after["volume_mm3"] / before["volume_mm3"] - 1) <= volume_limit)


def process_meshes(source_dir, output_dir, stage, iterations=15, passband=.08, max_faces=150000,
                   volume_limit=.05, progress=lambda text: None):
    from vtkmodules.vtkFiltersCore import vtkQuadricDecimation, vtkWindowedSincPolyDataFilter
    from vtkmodules.vtkIOGeometry import vtkSTLWriter
    from .reference import mesh_quality
    if stage not in ("Smooth", "Cut") or iterations < 1 or not 0 < passband <= 2 or max_faces < 4 or not 0 < volume_limit < 1:
        raise ValueError("无效的网格阶段或参数")
    if stage == "Smooth":
        from .pipeline import smooth_meshes
        return smooth_meshes(source_dir, output_dir, iterations, passband, progress)
    source_dir = Path(source_dir).resolve()
    manifest = read_json(source_dir / "manifest.json")
    if manifest.get("status") != "complete":
        raise ValueError("输入网格阶段尚未完成")
    out = _new_output(output_dir)
    report = dict(stage=stage, status="complete", source_manifest_sha256=file_sha256(source_dir / "manifest.json"),
        coordinate_system="DICOM LPS millimetres", max_total_volume_change=volume_limit,
        parameters=dict(iterations=iterations, passband=passband) if stage == "Smooth" else dict(max_faces=max_faces), objects=[])
    for index,entry in enumerate(manifest["objects"]):
        progress(f"{index+1}/{len(manifest['objects'])} {entry['name']}")
        item = {**entry}
        report["objects"].append(item)
        if entry["status"] == "empty_prediction":
            continue
        source = (source_dir / entry["file"]).resolve()
        if not source.is_relative_to(source_dir):
            raise ValueError("STL 清单路径超出输入目录")
        check_file(source, source.stat().st_size, entry["sha256"])
        mesh = read_stl(source)
        before = mesh_quality(mesh)
        if before["boundary_nonmanifold_edges"]:
            raise ValueError(f"输入 STL 非闭合/非流形：{source}")
        if stage == "Smooth":
            operation = vtkWindowedSincPolyDataFilter()
            operation.SetInputData(mesh)
            operation.SetNumberOfIterations(iterations)
            operation.SetPassBand(passband)
            operation.NormalizeCoordinatesOn()
            operation.FeatureEdgeSmoothingOff()
            operation.BoundarySmoothingOff()
            operation.NonManifoldSmoothingOff()
        else:
            operation = vtkQuadricDecimation()
            operation.SetInputData(mesh)
            operation.SetTargetReduction(max(0., 1-max_faces/before["triangles"]))
            operation.SetVolumePreservation(True)
        operation.Update()
        target = out / entry["file"]
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_suffix(".stl.tmp")
        writer = vtkSTLWriter()
        writer.SetFileName(str(temporary))
        writer.SetFileTypeToBinary()
        writer.SetInputData(operation.GetOutput())
        if not writer.Write():
            raise OSError(f"写入失败：{temporary}")
        after = mesh_quality(read_stl(temporary))
        # 以序列化后的结果判定；减面失败时允许面数超过预算。
        accepted = _quality_ok(before, after, volume_limit)
        if not accepted:
            shutil.copyfile(source, temporary)
            after = mesh_quality(read_stl(temporary))
        temporary.replace(target)
        item.update(status="processed" if accepted else "kept_source_quality_guard",
            sha256=file_sha256(target), source_sha256=entry["sha256"], before=before, after=after,
            triangles=after["triangles"], volume_mm3=after["volume_mm3"],
            volume_change_percent=100*(after["volume_mm3"]/before["volume_mm3"]-1))
    write_json(out / "manifest.json", report)
    return report
