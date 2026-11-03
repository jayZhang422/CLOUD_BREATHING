"""CT2BIN：DICOM ZIP/目录 → 原生 CT 网格 signed INT8 BIN。"""
from pathlib import Path

import numpy as np

from .dicom_ct import load_ct_series
from .prediction_io import CHANNELS, file_sha256
from ..files import check_file, crc32_file, read_json, write_json


def quantize_hu(hu):
    return (np.rint((np.clip(hu, -1024, 1000) + 1024) * 255 / 2024).astype(np.int16) - 128).astype(np.int8)


def prepare(data_dir, case_dir, series_uid=None, progress=lambda text: None):
    """保留物理坐标和真实层序；不在 PC 复制邻层或执行模型。"""
    source, case = Path(data_dir).resolve(), Path(case_dir)
    folder = case / "input"
    path, metadata_path = folder / "ct_volume_int8.bin", folder / "metadata.json"
    if metadata_path.exists():
        metadata = read_json(metadata_path)
        if (Path(metadata["source_dicom"]).resolve() != source
                or metadata.get("requested_series_uid") != series_uid):
            raise ValueError("该 case 已属于其他 CT/series；请使用新的 --case-dir")
        spec = metadata["model_input"]
        check_file(path, int(np.prod(spec["shape"])), spec["sha256"])
        progress("复用已校验 CT BIN")
        return metadata
    progress("读取 DICOM 与物理坐标")
    volume, metadata = load_ct_series(source, series_uid)
    if volume.shape[1:] != (512, 512) or not np.isfinite(volume).all():
        raise ValueError("现有上传协议要求有限 HU 值、512×512 的 CT 平面")
    folder.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".bin.tmp")
    with temporary.open("wb") as stream:
        for z, plane in enumerate(volume):
            stream.write(quantize_hu(plane).tobytes())
            progress(f"编码 {z + 1}/{len(volume)} slices")
    temporary.replace(path)
    metadata["requested_series_uid"] = series_uid
    metadata["model_input"] = dict(file=path.name, dtype="int8", layout="Z,Y,X", shape=list(volume.shape),
        bytes=path.stat().st_size, sha256=file_sha256(path), crc32=crc32_file(path),
        hu_clip=[-1024.0, 1000.0], channel_offsets_z=[-1, 0, 1], edge_policy="repeat_boundary_slice",
        mapping="round((clip(HU)-hu_min)*255/(hu_max-hu_min))-128")
    write_json(metadata_path, metadata)
    return metadata


def make_job(case_dir, image_base, batch_slices, transpose=True):
    """保留原生 INT8 BIN，并另生成 VOL2 紧凑视图供板端连续读取。"""
    case = Path(case_dir)
    metadata = read_json(case / "input/metadata.json")
    spec = metadata["model_input"]
    path = check_file(case / "input/ct_volume_int8.bin", int(np.prod(spec["shape"])), spec["sha256"])
    shape = spec["shape"]
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"])
    if (len(shape) != 3 or any(type(n) is not int or n < 1 for n in shape)
            or spec["bytes"] != path.stat().st_size or affine.shape != (4,4)
            or not np.isfinite(affine).all() or not np.allclose(affine[3],[0,0,0,1])
            or abs(np.linalg.det(affine[:3,:3])) < 1e-10):
        raise ValueError("输入尺寸、字节数或物理坐标元数据无效")
    depth = shape[0]
    if (spec["dtype"] != "int8" or spec["layout"] != "Z,Y,X" or spec["shape"][1:] != [512, 512]
            or not 1 <= depth <= 65535 or not 1 <= batch_slices <= 8
            or image_base != 0x00400000):
        raise ValueError("VOL2 整卷固件要求原生视图基址为 0x00400000，且输入布局、Slice_ID、批次有效")
    from .vol2 import prepare_vol2
    compact_bin = prepare_vol2(case, dict(input=dict(file="input/ct_volume_int8.bin",
        bytes=path.stat().st_size, sha256=spec["sha256"], shape=shape),
        result_contract=dict(bytes=path.stat().st_size*2)), metadata, transpose=transpose)
    job = dict(format="pc-fpga-volume-job-v2", status="prepared",
        input=dict(file="input/ct_volume_int8.bin", metadata="input/metadata.json", **{k:spec[k] for k in ("dtype","layout","shape","bytes","sha256")},
                   crc32=crc32_file(path), ddr_base=image_base, batch_slices=batch_slices),
        compact_bin=compact_bin,
        models=["lobe", "airway", "vessel", "tumor"],
        result_contract=dict(format="ct-segmentation-bitmask-v2", dtype="uint16", byte_order="little_endian",
            layout="Z,Y,X", shape=spec["shape"], bytes=path.stat().st_size * 2,
            channels=CHANNELS, channel_bits=list(range(9)), reserved_bits=list(range(9,16)),
            coordinate_system="DICOM LPS millimetres",
            affine_z_y_x_to_lps_mm=metadata["affine_z_y_x_to_lps_mm"]),
        execution="VOL2 compact BIN upload; START/QUERY/READ/RELEASE")
    write_json(case / "handoff/job.json", job)
    template = dict(format="pc-fpga-result-ready-v2", state="pending", transfer_id=None,
                    input_sha256=spec["sha256"], tasks=job["models"],
                    result={**job["result_contract"], "ddr_base":None, "sha256":None})
    template_path = case / "handoff/result_ready.template.json"
    if not template_path.exists():
        write_json(template_path, template)
    return job
