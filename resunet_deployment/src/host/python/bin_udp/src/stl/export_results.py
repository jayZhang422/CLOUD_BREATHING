"""Collect the current STLs and export a colored GLB for convenient viewing."""

import argparse
import base64
import json
from pathlib import Path
import shutil
import struct
import tempfile

from .chest_ct_to_stl import ROOT, LOBE_NAMES, NAMES, scene_actors


def save_colored_glb(source, destination):
    from vtkmodules.vtkIOExport import vtkGLTFExporter
    from vtkmodules.vtkRenderingCore import vtkRenderer, vtkRenderWindow
    from vtkmodules.util.numpy_support import vtk_to_numpy

    actors = scene_actors(source)
    renderer = vtkRenderer()
    window = vtkRenderWindow()
    window.SetOffScreenRendering(True)
    window.AddRenderer(renderer)
    for name, actor in actors.items():
        actor.GetMapper().Update()
        actor.SetScale(.001)  # STL millimetres -> glTF metres.
        actor.RotateX(-90)  # DICOM LPS -> glTF: X=L, Y=S, Z=-P.
        actor.GetProperty().SetOpacity(.15 if name in LOBE_NAMES else 1.)
        renderer.AddActor(actor)
    renderer.ResetCamera()
    try:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "scene.gltf"
            exporter = vtkGLTFExporter()
            exporter.SetRenderWindow(window)
            exporter.SetFileName(str(path))
            exporter.InlineDataOn()
            exporter.Write()
            scene = json.loads(path.read_text(encoding="utf-8"))
    finally:
        window.Finalize()

    buffers = [base64.b64decode(b["uri"].split(",", 1)[1]) for b in scene["buffers"]]
    for index, (name, actor) in enumerate(actors.items()):
        mesh = scene["meshes"][index]
        mesh["name"] = name
        for node in scene["nodes"]:
            if node.get("mesh") == index:
                node["name"] = name
        material = scene["materials"][index]
        material["name"] = name
        material["alphaMode"] = "BLEND" if name in LOBE_NAMES else "OPAQUE"
        material["pbrMetallicRoughness"]["metallicFactor"] = 0
        # VTK's scene exporter omits normals; preserve them for smooth GLB shading.
        normals = vtk_to_numpy(actor.GetMapper().GetInput().GetPointData().GetNormals())
        normal_bytes = normals.astype("<f4").tobytes()
        scene["bufferViews"].append({"buffer": len(buffers), "byteOffset": 0,
                                     "byteLength": len(normal_bytes), "target": 34962})
        buffers.append(normal_bytes)
        scene["accessors"].append({"bufferView": len(scene["bufferViews"]) - 1,
                                   "componentType": 5126, "count": len(normals), "type": "VEC3"})
        mesh["primitives"][0]["attributes"]["NORMAL"] = len(scene["accessors"]) - 1

    binary = bytearray()
    offsets = []
    for data in buffers:
        binary.extend(b"\0" * (-len(binary) % 4))
        offsets.append(len(binary))
        binary.extend(data)
    for view in scene["bufferViews"]:
        view["byteOffset"] = view.get("byteOffset", 0) + offsets[view["buffer"]]
        view["buffer"] = 0
    scene["buffers"] = [{"byteLength": len(binary)}]
    scene["asset"]["extras"] = {"source_coordinates": "DICOM LPS millimetres",
                                 "display_coordinates": "metres; X=L, Y=S, Z=-P"}
    encoded = json.dumps(scene, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    binary.extend(b"\0" * (-len(binary) % 4))
    with destination.open("wb") as file:
        file.write(struct.pack("<4sII", b"glTF", 2, 28 + len(encoded) + len(binary)))
        file.write(struct.pack("<I4s", len(encoded), b"JSON"))
        file.write(encoded)
        file.write(struct.pack("<I4s", len(binary), b"BIN\0"))
        file.write(binary)


def export_results(source, destination):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if source == destination:
        raise ValueError("The viewing folder must be separate from the source output")
    if not any((source / f"{name}.stl").exists() for name in NAMES):
        raise ValueError("No current STLs found; run main.py convert first")
    destination.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        current, copy = source / f"{name}.stl", destination / f"{name}.stl"
        if current.exists():
            shutil.copy2(current, copy)
        else:
            copy.unlink(missing_ok=True)  # Drop an obsolete export if this run has no positive prediction.
    save_colored_glb(source, destination / "Chest_Colored.glb")
    preview = source / "chest_surface_preview.png"
    if preview.exists():
        shutil.copy2(preview, destination / preview.name)
    run_path = source / "run_metadata.json"
    smooth_only = run_path.exists() and json.loads(run_path.read_text(encoding="utf-8")).get("postprocess_mode") == "smooth_only"
    processing_note = ("本版不修改预测 BIN，仅提取并平滑网格；未执行去孤岛、补连、填孔、筛选最大块或减面。肿瘤表面按原分量体素数量补偿平滑收缩，实际网格体积仍有离散误差；仅清理重合反向内壁。高斯表面提取可能使极小碎片消失或改变局部连接，不能纠正模型误检。\n\n"
                       if smooth_only else
                       "按 CT 灰度与配对参考筛选孤岛、连接短断口；没有合理连接路径的分支保留为独立闭合表面。原始预测 BIN 不改写。\n\n")
    if run_path.exists():
        run = json.loads(run_path.read_text(encoding="utf-8"))
        if "joint_lobe_repair" in run:
            processing_note += "肺叶采用五叶联合网格与 Windowed Sinc 平滑，顶点移动上限 2.5 mm；浅坑填补受 CT、距离与每叶 1% 新增预算限制，局部分叶平顺调整另设每叶 1% 上限。肺门和主要分叶仍保留。\n\n"
            if run.get("postprocess_mode") == "joint_lobe_refinement":
                processing_note += "本目录是肺叶优化对照版；气道、动脉、静脉及已有肿瘤 STL 沿用原结果，原版仍在 stl 目录。\n\n"
        if "vessel_smoothing" in run or any("vessel_smoothing" in info for info in run.get("objects", {}).values()):
            processing_note += "动静脉另作厚度自适应网格平滑，主干加强、细枝减弱，威胁骨架的位置局部回退；"
            processing_note += "保存后核对闭合与分量数，顶点移动≤2 mm、每个闭合分量体积变化≤5%，"
            processing_note += "原表面内部的骨架采样点保留至少80%的表面距离；这些检查不能证明医学准确性或全部细枝保真。\n\n"
    if not (destination / "LungTumor.stl").exists():
        processing_note += "本例没有保留的肿瘤候选，未输出 LungTumor.stl；这不代表不存在病灶，请查看 CT 与参考对照记录。\n\n"
    (destination / "查看说明.md").write_text(
        "# STL 与彩色模型\n\n"
        "这里集中保存当前结果的 STL 副本；与原文件完全相同，坐标仍为 DICOM LPS 毫米。\n\n"
        "STL 通常只保存形状，不保存通用颜色。`Chest_Colored.glb` 保存全部结构、颜色与肺叶透明度，"
        "可在支持 GLB 的 3D 查看器中打开；预览 PNG 可直接查看。\n\n"
        + processing_note +
        "| 文件 | 结构 | 组合模型颜色 |\n|---|---|---|\n"
        "| LeftUpperLobe.stl | 左上叶 | 浅蓝 |\n"
        "| LeftLowerLobe.stl | 左下叶 | 蓝紫 |\n"
        "| RightUpperLobe.stl | 右上叶 | 橙黄 |\n"
        "| RightMiddleLobe.stl | 右中叶 | 绿色 |\n"
        "| RightLowerLobe.stl | 右下叶 | 紫色 |\n"
        "| Bronchus.stl | 气管和支气管 | 浅黄色 |\n"
        "| PulmonaryArtery.stl | 肺动脉 | 红色 |\n"
        "| PulmonaryVenous.stl | 肺静脉 | 蓝色 |\n"
        "| LungTumor.stl | 肿瘤预测 | 粉色 |\n\n"
        "GLB 使用米和 Y 向上坐标以适配查看器；进行毫米测量、打印或与 CT 对齐请使用 STL。\n\n"
        "在项目根目录运行 `main.py view --output-dir \"该病例文件夹完整路径\"` 可旋转模型、切换对象和肺叶透明度。"
        "默认 `main.py` 查看新批次的 01 号；`main.py batch` 更新十例结果。\n",
        encoding="utf-8")
    print(f"[export] {destination}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True, help="Postprocessing work directory containing STLs")
    parser.add_argument("--output-dir", type=Path, required=True, help="Final STL and GLB directory")
    args = parser.parse_args()
    export_results(args.source_dir, args.output_dir)


if __name__ == "__main__":
    main()
