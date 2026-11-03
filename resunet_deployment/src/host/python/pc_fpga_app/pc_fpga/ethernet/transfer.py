"""整组上传和显式 DDR 结果回读；不发送旧 patch 推理触发命令。"""
from pathlib import Path
import secrets
import socket

import numpy as np

from .protocol import ImageBegin, check_fpga_requirements
from .sender import VolumeSender, SenderConfig
from .udp_link import UdpPeer
from .op_client import OpClient, STATUS
from ..ct.prediction_io import file_sha256, validate_bits
from ..files import check_file, read_json, write_json


def send_volume(case_dir, job, host, port, bind, timeout=1., progress=lambda text: None):
    case, spec = Path(case_dir), job["input"]
    if job.get("compact_bin"):
        compact = job["compact_bin"]
        path = check_file(case / compact["file"], compact["bytes"], compact["sha256"])
        client = OpClient(host, port, timeout, bind=bind)
        identity = secrets.randbits(32) or 1
        try:
            status = client.rpc(STATUS)
            if status["state"] != 0:
                # A failed/completed previous run owns the volume service until
                # RELEASE. Recover only terminal states; never interrupt RUNNING.
                previous = read_json(case / "handoff/send_receipt.json") if (case / "handoff/send_receipt.json").exists() else {}
                old_id = previous.get("transfer_id")
                if status["state"] in (2, 3) and isinstance(old_id, int) and old_id:
                    progress(f"Release terminal FPGA run 0x{old_id:08x}")
                    client.rpc(0x28, old_id)
                    status = client.rpc(STATUS)
                if status["state"] != 0:
                    raise RuntimeError("板端仍保留运行；请先完成回读或显式释放")
            for view in compact["views"]:
                progress(f"Upload VOL2 {view['name']}: {view['bytes']:,} bytes")
                client.upload_file(view["base"], path, view["file_offset"], view["bytes"],
                    lambda sent, total: progress(f"VOL2 {view['name']}: {sent:,}/{total:,} bytes"),
                    block_size=8 * 1024)
        finally:
            client.close()
        receipt = dict(status="compact_uploaded", transfer_id=identity,
            input_sha256=spec["sha256"], compact_sha256=compact["sha256"],
            sections=[{k:v for k,v in view.items() if k != "file_offset"} for view in compact["views"]],
            note="VOL2 sections uploaded; native INT8 source remains in the case as compatibility baseline.")
        write_json(case / "handoff/send_receipt.json", receipt)
        return receipt
    path = check_file(case / spec["file"], spec["bytes"], spec["sha256"])
    params = ImageBegin(total_slices=spec["shape"][0], total_bytes=spec["bytes"],
        image_base_addr=spec["ddr_base"], batch_slices=spec["batch_slices"],
        expected_packets=spec["shape"][0] * 256, whole_crc32=spec["crc32"])
    problem = check_fpga_requirements(params)
    if problem:
        raise ValueError(problem)
    link = UdpPeer((bind, 0))
    identity = secrets.randbits(32) or 1
    config = SenderConfig(begin_timeout=timeout, status_timeout=timeout, ready_timeout=timeout * 2,
                          pace_us=500)
    try:
        sender = VolumeSender(link, (socket.gethostbyname(host), port), path, params, identity, config,
                              log=lambda text, **kwargs: progress(text))
        receipt = sender.run(trigger=None)
    finally:
        link.close()
    receipt.update(status="image_ready", input_sha256=spec["sha256"],
                   note="Only upload verified; autonomous inference has not been triggered.")
    write_json(case / "handoff/send_receipt.json", receipt)
    return receipt


def validate_result_manifest(case_dir, manifest_path):
    """未来板端/控制适配器交接的磁盘清单；它不是新增的线上报文。"""
    case = Path(case_dir)
    job = read_json(case / "handoff/job.json")
    ready = read_json(manifest_path)
    result = ready.get("result", {})
    contract = job["result_contract"]
    if (ready.get("format") != "pc-fpga-result-ready-v1" or ready.get("state") != "complete"
            or ready.get("input_sha256") != job["input"]["sha256"]
            or ready.get("tasks") != job["models"]):
        raise ValueError("结果未完成，或输入身份/四模型范围不匹配")
    for key in ("dtype", "byte_order", "layout", "shape", "bytes", "channels", "channel_bits"):
        if result.get(key) != contract[key]:
            raise ValueError(f"结果契约不匹配：{key}")
    address, size, digest = result.get("ddr_base"), result["bytes"], result.get("sha256", "")
    if (type(address) is not int or address < 0 or address % 32 or address + ((size+31)&~31) > 0x1fff0000
            or not isinstance(digest,str) or len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest)):
        raise ValueError("结果 DDR 地址或 SHA256 无效；需由已完成的推理流程提供")
    input_spec = job["input"]
    if address < input_spec["ddr_base"] + input_spec["bytes"] and input_spec["ddr_base"] < address + size:
        raise ValueError("结果区与整组输入 DDR 区重叠")
    receipt_path = case / "handoff/send_receipt.json"
    if receipt_path.exists():
        receipt = read_json(receipt_path)
        if (ready.get("transfer_id") != receipt["transfer_id"]
                or receipt["input_sha256"] != ready["input_sha256"]):
            raise ValueError("结果 transfer_id 与本次上传不匹配")
    return job, ready


def receive_volume(case_dir, manifest_path, host, port, bind, timeout=1., progress=lambda text: None,
                   client_factory=OpClient):
    """只在明确结果就绪、服务空闲时 READ；不启动或释放任何运行。"""
    case = Path(case_dir)
    job, ready = validate_result_manifest(case, manifest_path)
    result = ready["result"]
    folder = case / "prediction"
    folder.mkdir(parents=True, exist_ok=True)
    if (folder / "metadata.json").exists():
        raise FileExistsError("prediction 已发布；请使用新 case 或显式保留旧结果后再接收")
    temporary = folder / "segmentation_uint16.bin.tmp"
    client = client_factory(host, port, timeout, bind=bind)
    try:
        status = client.rpc(STATUS)
        if status["state"] != 0:
            raise RuntimeError("DDR READ 要求板端推理完成并回到 idle；保留当前运行现场")
        with temporary.open("wb") as stream:
            for offset in range(0, result["bytes"], 1 << 20):
                count = min(1 << 20, result["bytes"] - offset)
                data = client.read(0, result["ddr_base"] + offset, count, diagnostic=True)
                if len(data) != count:
                    raise ValueError("结果 BIN 回读被截断")
                stream.write(data)
                progress(f"{offset+count:,}/{result['bytes']:,} bytes")
    finally:
        client.close()
    check_file(temporary, result["bytes"], result["sha256"])
    packed = np.memmap(temporary, dtype="<u2", mode="r", shape=tuple(result["shape"]))
    try:
        for plane in packed:
            validate_bits(plane)
    finally:
        packed._mmap.close()  # Windows 下必须释放映射，再原子重命名。
        del packed
    path = folder / "segmentation_uint16.bin"
    temporary.replace(path)
    metadata = {**job["result_contract"], "file":path.name, "order":"C", "sha256":file_sha256(path),
        "semantics":"Unmodified FPGA segmentation; no mesh processing applied",
        "provenance":dict(input_sha256=job["input"]["sha256"], result_ready=ready,
                          transport="Existing V1 operator READ, idle diagnostic access")}
    write_json(folder / "metadata.json", metadata)
    return metadata
