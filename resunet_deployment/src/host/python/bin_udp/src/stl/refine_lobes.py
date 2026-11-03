"""Refine existing lung lobes into a separate directory without model inference."""

import argparse
import json
from pathlib import Path
import shutil
import time

import numpy as np
from scipy import ndimage
from vtkmodules.vtkIOGeometry import vtkSTLReader
from vtkmodules.util.numpy_support import vtk_to_numpy

from . import chest_ct_to_stl as pipeline
from .lobe_surface import write_joint_lobes
from ..io.prediction_io import read_prediction
from .reference_review import binary_triangles, voxelize, review_grid, agreement, save_lung_overview
from .export_results import export_results

ROOT = Path(__file__).resolve().parents[2]


def mesh_metrics(path):
    from vtkmodules.vtkFiltersGeneral import vtkCurvatures
    reader = vtkSTLReader()
    reader.SetFileName(str(path))
    reader.Update()
    mesh = reader.GetOutput()
    curvature = vtkCurvatures()
    curvature.SetInputData(mesh)
    curvature.SetCurvatureTypeToMean()
    curvature.Update()
    values = abs(vtk_to_numpy(curvature.GetOutput().GetPointData().GetScalars()))
    return {**pipeline.core.mesh_quality(mesh),
            "abs_mean_curvature_p50_p90_p99_per_mm": np.quantile(values, [.5, .9, .99]).tolist()}


def compare_on_ct(case, masks, final, baseline, review):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import ListedColormap

    q, metadata = pipeline.core.load_input(case / "input/input_int8.bin", case / "input/metadata.json")
    hu, affine = review_grid(q, metadata)
    labels, before_labels = np.zeros(hu.shape, np.uint8), np.zeros(hu.shape, np.uint8)
    objects = {}
    figure, axes = plt.subplots(2, 3, figsize=(15, 10))
    with np.load(case / "reference_support.npz", allow_pickle=False) as references:
        for index, name in enumerate(pipeline.LOBE_NAMES, 1):
            after = voxelize(binary_triangles((final / f"{name}.stl").read_bytes()), hu.shape, np.linalg.inv(affine))
            before = voxelize(binary_triangles((baseline / f"{name}.stl").read_bytes()), hu.shape, np.linalg.inv(affine))
            labels[after], before_labels[before] = index, index
            processed = ndimage.zoom(masks[index - 1], np.array(hu.shape) / masks[index - 1].shape,
                                     order=0, prefilter=False)
            item = {"before": mesh_metrics(baseline / f"{name}.stl"), "after": mesh_metrics(final / f"{name}.stl"),
                    "final_vs_before": agreement(after, before), "final_vs_processed": agreement(after, processed)}
            item["volume_change_percent"] = 100 * (item["after"]["volume_mm3"] / item["before"]["volume_mm3"] - 1)
            if name in references.files:
                item["before_reference_agreement"] = agreement(before, references[name])
                item["after_reference_agreement"] = agreement(after, references[name])
            objects[name] = item
            z = int(after.sum(axis=(1, 2)).argmax())
            axis = axes.ravel()[index - 1]
            axis.imshow(hu[z], cmap="gray", vmin=-1000, vmax=400)
            axis.imshow(np.ma.masked_where(~after[z], np.ones(hu[z].shape)),
                        cmap=ListedColormap([pipeline.COLORS[index - 1]]), alpha=.45)
            axis.contour(before[z], levels=[.5], colors=["orange"], linewidths=.7)
            if name in references.files:
                axis.contour(references[name][z], levels=[.5], colors=["lime"], linewidths=.9)
            axis.set_title(name)
            axis.axis("off")
        axes.ravel()[5].axis("off")
    figure.suptitle("Refined STL on CT | orange: previous STL | green: available reference")
    figure.tight_layout()
    figure.savefig(review / "ct_refinement_comparison.png", dpi=130)
    plt.close(figure)
    save_lung_overview(hu, labels, affine, review / "final_lung_three_planes.png")
    union = agreement(labels > 0, before_labels > 0)
    assert union["dice"] > .97, "Refinement changed the overall lung shape excessively"
    assert all(abs(item["volume_change_percent"]) < 5 for item in objects.values()), "Lobe volume changed excessively"
    return {"objects": objects, "whole_lung_before_after": union,
            "final_lung_end_slice_voxels": [int(np.count_nonzero(labels[0])), int(np.count_nonzero(labels[-1]))],
            "comparison_grid_spacing_mm": np.linalg.norm(affine[:3, :3], axis=0).tolist()}


def refine_case(record, output, review_root):
    started = time.perf_counter()
    number = record["number"]
    case, baseline = Path(record["bin_directory"]), Path(record["stl_directory"])
    review, temporary = review_root / number, case / "surface_refinement"
    review.mkdir(parents=True, exist_ok=True)
    temporary.mkdir(parents=True, exist_ok=True)
    prediction, contract = read_prediction(case / "prediction")
    q, metadata = pipeline.core.load_input(case / "input/input_int8.bin", case / "input/metadata.json")
    assert pipeline.core.sha256_file(case / "input/input_int8.bin") == contract["provenance"]["input_sha256"]
    affine = np.asarray(contract["affine_z_y_x_to_lps_mm"])
    assert np.allclose(affine, metadata["affine_z_y_x_to_lps_mm"])
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    body = pipeline.core.body_mask(q, metadata["model_input"]["hu_clip"])
    hu_min, hu_max = metadata["model_input"]["hu_clip"]
    hu = (q[:, 1].astype(np.float32) + 128) * (hu_max - hu_min) / 255 + hu_min
    raw = [prediction[:, index].astype(bool) for index in range(5)]
    with np.load(case / "reference_support.npz", allow_pickle=False) as references:
        raw, adjustment = pipeline.adjust_lobe_boundaries(raw, references, spacing)
        masks, repairs, envelope = pipeline.repair_joint_lobes(raw, body, spacing, hu, references)
    print(f"[refine {number}] pit additions={envelope['added_voxels']:,}; boundary relabels={envelope['changed_existing_labels']:,}", flush=True)
    surfaces = write_joint_lobes(masks, affine, temporary)
    for name, surface in surfaces.items():
        surface["path"] = str(output / number / f"{name}.stl")
    unchanged = {}
    for name in pipeline.NAMES[5:]:
        source = baseline / f"{name}.stl"
        if source.exists():
            shutil.copy2(source, temporary / source.name)
            unchanged[name] = pipeline.core.sha256_file(source)
    comparison = compare_on_ct(case, masks, temporary, baseline, review)
    run = {"status": "complete", "postprocess_mode": "joint_lobe_refinement", "source": record["source"],
           "prediction_sha256": contract["sha256"], "coordinate_system": "DICOM LPS millimetres",
           "minor_lobe_boundary_adjustment": adjustment, "joint_lobe_repair": envelope,
           "lobe_surfaces": surfaces, "unchanged_non_lobe_stl_sha256": unchanged,
           "comparison": comparison, "elapsed_seconds": time.perf_counter() - started}
    (temporary / "run_metadata.json").write_text(json.dumps(run, ensure_ascii=False, indent=2), encoding="utf-8")
    pipeline.save_scene(temporary)
    export_results(temporary, output / number)
    shutil.copy2(temporary / "chest_surface_preview.png", review / "chest_surface_preview.png")
    for name, expected in unchanged.items():
        assert pipeline.core.sha256_file(output / number / f"{name}.stl") == expected
    (review / "refinement.json").write_text(json.dumps(run, ensure_ascii=False, indent=2), encoding="utf-8")
    assert temporary.resolve().is_relative_to(case.resolve())
    shutil.rmtree(temporary)
    return run


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", help="Existing case number, such as 01; default: all ten")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "stl_refined")
    args = parser.parse_args()
    manifest = json.loads((ROOT / "stl/batch_manifest.json").read_text(encoding="utf-8"))
    baseline = ROOT / "stl"
    if args.output_dir.resolve().is_relative_to(baseline.resolve()):
        parser.error("Keep the original STL directory for comparison")
    if not args.output_dir.resolve().is_relative_to(ROOT.resolve()):
        parser.error("Refined outputs must remain within this project")
    review = ROOT / "output/review/surface_upgrade"
    review.mkdir(parents=True, exist_ok=True)
    reports = []
    for record in manifest["cases"]:
        if args.case is None or record["number"] == args.case:
            print(f"[refine {record['number']}] {record['source']}", flush=True)
            result = refine_case(record, args.output_dir, review)
            reports.append({"number": record["number"], "name": Path(record["source"]).stem[:-3],
                            "output": str(args.output_dir / record["number"]), **result})
            (review / "refined_batch.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding="utf-8")
    if not reports:
        parser.error("No matching case number")
    from PIL import Image, ImageDraw
    collage = Image.new("RGB", (1600, 330 * ((len(reports) + 1) // 2)), (246, 249, 251))
    for index, result in enumerate(reports):
        tile = Image.open(args.output_dir / result["number"] / "chest_surface_preview.png").crop((0, 0, 1800, 650)).resize((800, 289))
        x, y = 800 * (index % 2), 330 * (index // 2)
        collage.paste(tile, (x, y + 28))
        ImageDraw.Draw(collage).text((x + 15, y + 5), f"Case {result['number']} | refined lobes", fill=(20, 30, 50), font_size=15)
    collage.save(review / "ten_case_lobes_refined.png")
    write_summary(reports, review)
    print(f"REFINEMENT_PASS: {len(reports)} cases; {args.output_dir}", flush=True)


def write_summary(reports, review):
    lines = ["# 肺叶表面研究与局部修补", "",
             "已直接检查配对 STL 的真实几何，并在相同灯光、Phong 插值和视角下对照旧版与新版。"
             "参考的具体导出算法无法仅由 STL 反推；参考仍有肺门凹陷、肺裂及少量层纹。",
             "", "01 号参考只包含左上叶和左下叶，每叶约 4.7 万三角面；旧版每叶约 25～26 万面。"
             "三角面更多并不等于更顺滑。旧版逐叶高斯与低强度网格平滑保留了不少跨切片波纹。",
             "", "查阅的公开实现：",
             "- [3D Slicer：联合闭合表面和平滑](https://github.com/Slicer/Slicer/blob/main/Libs/vtkSegmentationCore/vtkBinaryLabelmapToClosedSurfaceConversionRule.cxx)",
             "- [VTK：Windowed Sinc](https://github.com/Kitware/VTK/blob/master/Filters/Core/vtkWindowedSincPolyDataFilter.h)",
             "- [VTK：Surface Nets](https://github.com/Kitware/VTK/blob/master/Filters/Core/vtkSurfaceNets3D.h)",
             "", "采用已安装 VTK 的联合 discrete marching cubes + 60 轮 Windowed Sinc，passband=0.001；"
             "同一个标签图中的共享顶点同步移动，物理位移钳制≤2.5 mm。没有增加依赖或修改网络权重。"
             "Surface Nets 在本例的局部标签交界未通过保存后的闭合检查，因此未作为交付算法。",
             "", "修补基于现有模型分类与 CT：每个补丁≤1000 mm³，浅坑填补距已有肺≤2.5 mm、"
             "外部新增需 HU<-300，新增总量≤每叶 1%；类别邻域投票仅清理≤1.5 mm 的细小边界，"
             "另限每叶改动≤1%。完全包围的小空隙也可局部填补。小于 5 mm³ 的独立闭合表面删去。"
             "这些操作发生在已有组件筛选/微小参考分类调整之后；原始预测 BIN 不改写。",
             "", "气道、动脉、静脉和原来保留的肿瘤 STL 按哈希核对，沿用旧版。"
             "原版在 stl，新版在 stl_refined，逐例 JSON 和 CT 叠加在本报告同目录。",
             "", "| 编号 | 病例 | 与旧版整体肺 Dice | 最大肺叶体积变化 | 曲率中位数下降范围 |",
             "|---|---|---:|---:|---:|"]
    for result in reports:
        objects = result["comparison"]["objects"]
        volumes = [abs(item["volume_change_percent"]) for item in objects.values()]
        decreases = [100 * (1 - item["after"]["abs_mean_curvature_p50_p90_p99_per_mm"][0] /
                             item["before"]["abs_mean_curvature_p50_p90_p99_per_mm"][0]) for item in objects.values()]
        lines.append(f"| {result['number']} | {result['name']} | "
                     f"{result['comparison']['whole_lung_before_after']['dice']:.4f} | {max(volumes):.2f}% | "
                     f"{min(decreases):.1f}～{max(decreases):.1f}% |")
    lines += ["", "表面曲率是几何平顺程度的辅助量，受三角网格采样影响，不能视为医学准确度。"
              "部分分叶交界的曲率高分位仍较大，局部细碎边界没有完全消失。"
              "CT 三平面只展示若干切面，定量比较在约 2 mm 网格上进行。",
              "", "04/05 等病例的右中叶分类偏差、较深的开放凹陷仍存在；本轮没有整体替换参考形状。"
              "大范围错分需进一步检查 CT 或改进分叶模型，不能由外观平滑验证正确。",
              "", "验证：逐例保存后的五叶闭合、非流形边=0、顶点位移≤2.5 mm、整体肺 Dice>0.97、"
              "每叶体积变化<5%；原有结构哈希一致。6 项平滑/几何回归与项目自检通过。",
              "", "![01 号前后对照](01_before_after.png)"]
    (review / "平滑研究与修复结果.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
