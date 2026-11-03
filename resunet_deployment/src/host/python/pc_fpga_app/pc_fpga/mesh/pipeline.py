"""仅 BIN→STL / Smooth：Model 算法、病例校验与阶段文件衔接。"""
from pathlib import Path
import tempfile

import numpy as np

from ..ct.prediction_io import CHANNELS, file_sha256, prediction_mask, read_prediction
from ..files import check_file, read_json, write_json
from . import reference as core
from .lobe_surface import write_joint_lobes


def load_ct(prediction_dir, contract, shape, metadata_path=None):
    """兼容 PC 单卷和 Model 旧三邻层；中心层视图不创建额外 BIN。"""
    provenance = contract.get("provenance", {})
    explicit_metadata = metadata_path is not None
    metadata_path = Path(metadata_path or provenance.get("input_metadata")
                         or Path(prediction_dir).parent / "input/metadata.json")
    if not metadata_path.is_file():
        raise ValueError("CT 修补需要匹配的 input/metadata.json；外部病例可用 --ct-metadata 指定")
    metadata = read_json(metadata_path)
    spec = metadata["model_input"]
    path = (Path(provenance["input_bin"]) if not explicit_metadata and provenance.get("input_bin")
            else metadata_path.parent / spec["file"])
    if spec["dtype"] != "int8" or spec["hu_clip"] != [-1024., 1000.]:
        raise ValueError("CT 必须使用 Model 的 INT8/HU 编码")
    check_file(path, int(np.prod(spec["shape"])), spec.get("sha256") or provenance.get("input_sha256"))
    digest = file_sha256(path)
    if provenance.get("input_sha256") and provenance["input_sha256"] != digest:
        raise ValueError("CT SHA256 与预测 BIN 来源不一致")
    q = np.memmap(path, mode="r", dtype=np.int8, shape=tuple(spec["shape"]))
    if spec["layout"] == "Z,Y,X" and q.ndim == 3:
        q = np.broadcast_to(q[:, None], (len(q), 3, *q.shape[1:]))
    elif spec["layout"] != "Z,C,H,W" or q.ndim != 4 or q.shape[1] != 3:
        raise ValueError("不支持的 CT 布局")
    if ((q.shape[0], *q.shape[2:]) != shape
            or (provenance.get("input_shape") is not None and list(spec["shape"]) != provenance["input_shape"])
            or not np.allclose(contract["affine_z_y_x_to_lps_mm"], metadata["affine_z_y_x_to_lps_mm"])):
        raise ValueError("CT 与预测 BIN 的网格/affine 不匹配")
    body = core.body_mask(q, spec["hu_clip"])
    hu = (q[:, 1].astype(np.float32) + 128.) * 2024. / 255. - 1024.
    return body, hu, dict(metadata=str(metadata_path.resolve()), file=str(path.resolve()), sha256=digest)


def bin_to_stl(prediction_dir, output_dir, progress=lambda text: None, *, ct_metadata=None, reference_support=None):
    from .stages import _new_output, category, read_stl
    from .repair import prepare_masks
    prediction, contract = read_prediction(prediction_dir)
    affine = np.asarray(contract["affine_z_y_x_to_lps_mm"], dtype=float)
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    masks = [prediction_mask(prediction, i) for i in range(9)]
    del prediction
    original_counts = [int(mask.sum()) for mask in masks]
    synthetic = contract.get("provenance", {}).get("synthetic") is True
    # 演示没有 CT，不能冒充经过 CT 支持的修补结果。
    ct = None
    if not synthetic:
        body, hu, ct = load_ct(prediction_dir, contract, masks[0].shape, ct_metadata)
    out = _new_output(output_dir)
    report = dict(stage="BIN2STL", status="complete", source_sha256=contract["sha256"],
                  coordinate_system="DICOM LPS millimetres", affine_z_y_x_to_lps_mm=affine.tolist(),
                  ct_reference=ct, synthetic_mask_only=synthetic, objects=[])
    references = np.load(reference_support, allow_pickle=False) if reference_support else None
    try:
        if synthetic:
            repairs = [dict(operation="Synthetic demonstration; CT repair skipped") for _ in masks]
        else:
            progress("Model CT-supported mask repair")
            masks, repairs, details = prepare_masks(masks, body, spacing, hu, affine, out, references, progress)
            report.update(details)
        if references is not None:
            report["reference_support"] = dict(file=str(Path(reference_support).resolve()), sha256=file_sha256(reference_support))
    finally:
        if references is not None:
            references.close()
    joint = write_joint_lobes(masks[:5], affine, out / "lobes", iterations=0)
    (out / "masks").mkdir(exist_ok=True)
    for i, name in enumerate(CHANNELS):
        progress(f"{i+1}/9 {name}")
        mask = masks[i]
        mask_path = out / "masks" / f"{name}.npy"
        np.save(mask_path, mask.astype(np.uint8), allow_pickle=False)
        entry = dict(name=name, category=category(i), raw_voxels=original_counts[i], voxels=int(mask.sum()),
                     repair=repairs[i], mask_file=mask_path.relative_to(out).as_posix(), mask_sha256=file_sha256(mask_path))
        report["objects"].append(entry)
        if not mask.any():
            entry.update(status="empty_prediction", empty_reason="empty after repair" if original_counts[i] else "empty input")
            continue
        relative = Path(category(i)) / f"{name}.stl"
        path = out / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if i >= 5:
            core.write_stl(mask, affine, path, step_size=1, iterations=0)
        quality = core.mesh_quality(read_stl(path))
        entry.update(status="exported", file=relative.as_posix(), sha256=file_sha256(path),
                     triangles=quality["triangles"], volume_mm3=quality["volume_mm3"])
        if i < 5:
            entry["surface"] = joint[name]
    write_json(out / "manifest.json", report)
    return report


def _checked_path(directory, relative, digest):
    path = (directory / relative).resolve()
    if not path.is_relative_to(directory):
        raise ValueError("阶段清单路径超出输入目录")
    return check_file(path, path.stat().st_size, digest)


def smooth_meshes(source_dir, output_dir, iterations=15, passband=.08, progress=lambda text: None):
    from .stages import _new_output, read_stl
    from .surface import smooth_surface
    from .vessel_surface import refine_stl
    source_dir = Path(source_dir).resolve()
    manifest = read_json(source_dir / "manifest.json")
    if manifest.get("status") != "complete" or "affine_z_y_x_to_lps_mm" not in manifest:
        raise ValueError("结构专用平滑需要新版 BIN2STL 目录（含修补掩膜）；请重新执行 bin2stl")
    affine = np.asarray(manifest["affine_z_y_x_to_lps_mm"], dtype=float)
    masks = []
    for entry in manifest["objects"]:
        path = _checked_path(source_dir, entry["mask_file"], entry["mask_sha256"])
        masks.append(np.load(path, allow_pickle=False).astype(bool))
        if entry["status"] != "empty_prediction":
            _checked_path(source_dir, entry["file"], entry["sha256"])
    if [e["name"] for e in manifest["objects"]] != CHANNELS:
        raise ValueError("平滑输入的九结构顺序不匹配")
    out = _new_output(output_dir)
    report = dict(stage="Smooth", status="complete", coordinate_system="DICOM LPS millimetres",
                  source_manifest_sha256=file_sha256(source_dir / "manifest.json"),
                  parameters=dict(lobe_iterations=60, lobe_passband=.001, lobe_maximum_move_mm=2.5,
                                  iterations=iterations, passband=passband, reduction_applied=False), objects=[])
    progress("Joint lobe surfaces; shared-vertex smoothing")
    joint = write_joint_lobes(masks[:5], affine, out / "lobes")
    with tempfile.TemporaryDirectory(dir=out) as temporary:
        for i, entry in enumerate(manifest["objects"]):
            progress(f"{i+1}/9 {entry['name']}")
            # 平滑产物不宣称拥有 raw 阶段中的相对掩膜路径。
            item = {k:v for k,v in entry.items() if k not in ("mask_file", "mask_sha256")}
            report["objects"].append(item)
            if entry["status"] == "empty_prediction":
                continue
            target = out / entry["file"]
            target.parent.mkdir(parents=True, exist_ok=True)
            before = core.mesh_quality(read_stl(source_dir / entry["file"]))
            if i < 5:
                item["smoothing"] = joint[entry["name"]]
            else:
                tumor = i == 8
                candidate = Path(temporary) / f"{entry['name']}.stl"
                item["surface"] = core.write_stl(masks[i], affine, candidate, 1, 10 if tumor else 5,
                    2. if tumor else .45, preserve_voxels=not tumor, preserve_volume=tumor)
                supported = entry["repair"].get("reference_supported_component_selection", False)
                item["smoothing"] = smooth_surface(candidate, target,
                    largest_surface=i != 7 and not supported,
                    minimum_surface_volume_mm3=5. if tumor else 20., iterations=iterations, passband=passband)
                if i in (6, 7):
                    item["vessel_smoothing"] = refine_stl(target, target, masks[i], affine)
            after = core.mesh_quality(read_stl(target))
            if after["boundary_nonmanifold_edges"] or after["volume_mm3"] <= 0:
                raise ValueError(f"平滑输出未通过闭合检查：{target}")
            item.update(status="processed", source_sha256=entry["sha256"], sha256=file_sha256(target),
                        before=before, after=after, triangles=after["triangles"], volume_mm3=after["volume_mm3"],
                        volume_change_percent=100*(after["volume_mm3"]/before["volume_mm3"]-1))
    write_json(out / "manifest.json", report)
    return report
