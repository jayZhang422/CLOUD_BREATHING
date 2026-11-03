"""Benchmark frozen FPGA inference schedules for four segmentation models.

The ``freeze`` command is used once.  Normal comparisons use only ``run``;
they read the saved input BIN and 64-byte descriptors from the manifest.
The ``suite`` command freezes one plane per model once and reuses it thereafter.
Current RTL executes the selected d1 Upsample/Concat pair as op13; an old
fused_residual manifest is adapted in memory and the execution SHA is reported.
"""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import secrets
import struct
import sys
from time import monotonic, perf_counter

import numpy as np


HERE = Path(__file__).resolve().parent
MODEL_TASKS = ("lobe", "airway", "vessel", "tumor")
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from src.op_client import OpClient, RELEASE, STATUS
from src.protocol import (
    ImageBegin,
    MSG_ACK,
    MSG_IMAGE_BEGIN,
    MSG_TRANSFER_ABORT,
    build_frame,
    parse_ack_body,
    parse_frame,
    FrameError,
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def reset_session(client: OpClient) -> None:
    """Invalidate a previous legacy IMAGE_READY without touching model data."""
    if client.rpc(STATUS)["state"] != 0:
        raise RuntimeError("FPGA is busy; preserve the active run and reset/release it first")
    identity = secrets.randbits(32) or 1
    client.sequence = (client.sequence + 1) & 0xFFFFFFFF
    sequence = client.sequence
    begin = ImageBegin(total_slices=1, total_bytes=262144, expected_packets=256,
                       image_base_addr=0x10000000)
    packet = build_frame(MSG_IMAGE_BEGIN, identity, sequence, begin.body())
    for _ in range(client.retries):
        client.socket.sendto(packet, client.peer)
        deadline = monotonic() + client.socket.gettimeout()
        while monotonic() < deadline:
            try:
                data, peer = client.socket.recvfrom(2048)
            except TimeoutError:
                break
            if peer != client.peer:
                continue
            try:
                frame = parse_frame(data)
            except FrameError:
                continue
            if (frame.msg_type, frame.transfer_id, frame.sequence) != (
                    MSG_ACK, identity, (sequence + 1) & 0xFFFFFFFF):
                continue
            ack = parse_ack_body(frame.body)
            if ack.status or ack.acked_msg_type != MSG_IMAGE_BEGIN or ack.acked_sequence != sequence:
                raise RuntimeError(f"FPGA rejected session reset: {ack}")
            client.sequence = (client.sequence + 1) & 0xFFFFFFFF
            client.socket.sendto(build_frame(MSG_TRANSFER_ABORT, identity, client.sequence, b""),
                                 client.peer)
            return
    raise TimeoutError("FPGA did not acknowledge session reset")


def fuse_residual_plan(plan) -> None:
    """Use existing op12, then allocate its real input/output lifetimes."""
    original = {stage["name"]: stage for stage in plan.stages}
    stages = []
    for stage in plan.stages:
        if stage["name"].endswith((".project", ".skip")):
            continue
        if stage["name"].endswith(".out"):
            block = stage["name"].rsplit(".", 1)[0]
            project, skip = (original[block + suffix] for suffix in (".project", ".skip"))
            stage = {**stage, "op": 12, "reads": project["reads"] + skip["reads"],
                     "kwargs": {**stage["kwargs"], "cin": project["kwargs"]["cin"],
                                "weights": project["kwargs"]["weights"],
                                "mac": skip["kwargs"]["weights"]}}
        stages.append(stage)
    tensors = {"input": {**plan.tensors["input"], "produced": -1, "last": -1}}
    for index, stage in enumerate(stages):
        tensors[stage["name"]] = {**plan.tensors[stage["name"]], "produced": index, "last": index}
        for name in stage["reads"]:
            tensors[name]["last"] = index
    plan.stages, plan.tensors = stages, tensors
    plan.allocate()
    # Current RTL remaps three old lobe concat addresses. Explicit high skip
    # addresses work for all four models without relying on that compatibility patch.
    cursor = 0x1E000000
    if plan.arena_end > cursor:
        raise ValueError("Residual scratch arena overlaps encoder skip storage")
    for name in ("e1.out", "e2.out", "e3.out"):
        tensor = tensors[name]
        tensor["address"] = cursor
        cursor += (tensor["bytes"] + 31) & ~31
    if cursor > 0x20000000:
        raise ValueError("Residual encoder skips exceed DDR capacity")
    for stage in stages:
        desc = bytearray(stage["descriptor"])
        sources = [tensors[name]["address"] for name in stage["reads"]]
        struct.pack_into("<3I", desc, 16, sources[0], sources[1] if len(sources) > 1 else 0,
                         tensors[stage["name"]]["address"])
        if stage["op"] == 12:
            skip = original[stage["name"].rsplit(".", 1)[0] + ".skip"]
            struct.pack_into("<H", desc, 56, skip["kwargs"]["cin"])
        stage["descriptor"] = bytes(desc)
    plan.arena_end = max(plan.arena_end, cursor)
    plan.schedule_sha256 = sha256_bytes(b"".join(stage["descriptor"] for stage in stages))


def freeze(args: argparse.Namespace) -> int:
    """Create immutable slice inputs and a descriptor manifest once."""
    # This is deliberately isolated to freeze mode.  The normal run path below
    # imports no model planner and therefore cannot change with its source.
    from src.ct_pipeline import prepare_sample, task_grid, volume_geometry
    from src.fullnet import NetworkPlan, TASKS, coefficient_image, pack_input
    from src.io.fpga_volume_io import load_volume

    task_row = next(row for row in TASKS if row[0] == args.task)
    _, _, _, orientation, target_spacing = task_row
    volume, metadata = load_volume(args.case_dir / "input/ct_volume_int8.bin",
                                   args.case_dir / "input/metadata.json")
    _, spacing, direction = volume_geometry(volume, metadata)
    centers = task_grid(volume, spacing, target_spacing)
    slice_indices = args.slices if args.slices else [len(centers) // 2 if args.slice is None else args.slice]
    if len(set(slice_indices)) != len(slice_indices):
        raise ValueError("slice indices must be unique")
    for index in slice_indices:
        if not 0 <= index < len(centers):
            raise ValueError(f"slice must be in 0..{len(centers) - 1}: {index}")
    golden_slice = args.golden_slice
    if args.golden and golden_slice is None:
        if len(slice_indices) != 1:
            raise ValueError("--golden-slice is required with --golden and multiple slices")
        golden_slice = slice_indices[0]
    if golden_slice is not None and golden_slice not in slice_indices:
        raise ValueError("--golden-slice must be one of the selected slices")

    plan = NetworkPlan(args.task, coefficient_image(), fuse_dw_add=args.profile != "legacy")
    if args.profile == "fused_residual":
        fuse_residual_plan(plan)
    input_base = args.input.resolve()
    input_base.parent.mkdir(parents=True, exist_ok=True)
    inputs = []
    for index in slice_indices:
        sample = prepare_sample(centers, index, orientation, direction)
        payload = pack_input(sample)
        input_path = (input_base if len(slice_indices) == 1 else
                      input_base.with_name(f"{input_base.stem}_z{index}{input_base.suffix}"))
        input_path.write_bytes(payload)
        inputs.append({
            "slice": index,
            "path": input_path,
            "address": int(plan.tensors["input"]["address"]),
            "bytes": len(payload),
            "sha256": sha256_bytes(payload),
        })

    parameter_path = None
    if plan.parameters:
        parameter_path = input_base.with_name(input_base.stem + ".params.bin")
        parameter_path.write_bytes(plan.parameters)

    stages = []
    for stage in plan.stages:
        stages.append({
            "name": stage["name"],
            "op": int(stage["op"]),
            "format": int(stage["format"]),
            "bytes": int(stage["bytes"]),
            "descriptor_hex": stage["descriptor"].hex(),
        })

    golden_sha256 = None
    if args.golden:
        golden = args.golden.resolve()
        expected_bytes = plan.channels * plan.side * plan.side * 2
        if golden.stat().st_size != expected_bytes:
            raise ValueError(f"golden size {golden.stat().st_size} != {expected_bytes}")
        golden_sha256 = sha256_file(golden)
        for item in inputs:
            if item["slice"] == golden_slice:
                item["golden_sha256"] = golden_sha256

    manifest_path = args.manifest.resolve()
    import os
    rel = lambda path: os.path.relpath(path, manifest_path.parent).replace("\\", "/")
    manifest = {
        "format": 1,
        "profile": args.profile,
        "task": args.task,
        "source_slices": slice_indices,
        "inputs": [{**item, "path": rel(item["path"])} for item in inputs],
        "parameters": ({
            "path": rel(parameter_path),
            "address": 0x08000000,
            "bytes": len(plan.parameters),
            "sha256": sha256_bytes(plan.parameters),
        } if parameter_path else None),
        "output": {
            "address": int(plan.tensors["head"]["address"]),
            "bytes": int(plan.tensors["head"]["bytes"]),
            "channels": int(plan.channels),
            "side": int(plan.side),
            "golden_sha256": golden_sha256 if len(inputs) == 1 else None,
        },
        "plan": {
            "stages": len(stages),
            "schedule_sha256": plan.schedule_sha256,
            "input_bytes": int(plan.tensors["input"]["bytes"]),
            "fused_dw_add": args.profile != "legacy",
            "fused_residual": args.profile == "fused_residual",
            "model_grid": list(map(int, centers.shape)),
        },
        "stages": stages,
    }
    write_json(manifest_path, manifest)
    print(f"[FROZEN] {manifest_path}")
    for item in inputs:
        print(f"[INPUT] z={item['slice']} {item['path']} ({item['bytes']:,} bytes)")
    print(f"[SCHEDULE] {len(stages)} stages x {len(inputs)} slices, profile={args.profile}")
    return 0


def load_manifest(path: Path) -> tuple[dict, list[dict], bytes | None]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("format") != 1 or manifest.get("task") not in MODEL_TASKS:
        raise ValueError("unsupported frozen benchmark manifest")
    stages = manifest.get("stages") or []
    if not stages:
        raise ValueError("manifest contains no stages")
    # 仅在内存把已冻结的d1.up→d1.concat改为op13；原输入、数学及文件不变。
    if manifest.get("profile") == "fused_residual":
        for index in range(len(stages) - 1):
            up, concat = stages[index:index+2]
            if (up["name"], up["op"], concat["name"], concat["op"]) == ("d1.up", 10, "d1.concat", 5):
                a, b = bytes.fromhex(up["descriptor_hex"]), bytearray.fromhex(concat["descriptor_hex"])
                aw, ah = struct.unpack_from("<HH", a, 4)
                if (struct.unpack_from("<HH", b, 4) != (aw*2, ah*2) or a[8:10] != b[8:10] or
                        a[24:28] != b[16:20] or up["bytes"] != 64*aw*ah*struct.unpack_from("<H",a,8)[0]):
                    raise ValueError("d1 Upsample/Concat frozen descriptors disagree")
                b[0] = 13
                b[4:8] = a[4:8]
                b[16:20] = a[16:20]
                stages[index:index+2] = [{**concat, "op": 13, "descriptor_hex": b.hex()}]
                manifest["fused_up_concat"] = "d1"
                break
    for stage in stages:
        descriptor = bytes.fromhex(stage["descriptor_hex"])
        if len(descriptor) != 64:
            raise ValueError(f"{stage['name']}: descriptor must be 64 bytes")
        # 冻结输入、描述符和数学Golden保持不变，仅适配本版普通INT16的P8长度。
        if descriptor[0] == 1 and descriptor[1] & 14 == 8:
            width,height = struct.unpack_from("<HH",descriptor,4)
            cout = struct.unpack_from("<H",descriptor,54)[0] or descriptor[3]
            stage["bytes"] = ((cout+7)//8)*width*height*16
            if stage is stages[-1]:
                manifest["output"]["bytes"] = stage["bytes"]
    input_specs = manifest.get("inputs") or [
        {"slice": manifest.get("source_slice", 0), **manifest["input"]}
    ]
    if not input_specs or len({item["slice"] for item in input_specs}) != len(input_specs):
        raise ValueError("manifest input slices must be non-empty and unique")
    inputs = []
    for spec in input_specs:
        input_path = (path.parent / spec["path"]).resolve()
        payload = input_path.read_bytes()
        if len(payload) != spec["bytes"] or sha256_bytes(payload) != spec["sha256"]:
            raise ValueError(f"fixed input changed: {input_path}")
        inputs.append({**spec, "path": input_path, "payload": payload})
    parameters = None
    if manifest.get("parameters"):
        spec = manifest["parameters"]
        parameter_path = (path.parent / spec["path"]).resolve()
        parameters = parameter_path.read_bytes()
        if len(parameters) != spec["bytes"] or sha256_bytes(parameters) != spec["sha256"]:
            raise ValueError(f"fixed parameters changed: {parameter_path}")
    manifest["execution_schedule_sha256"] = sha256_bytes(b"".join(
        bytes.fromhex(stage["descriptor_hex"]) for stage in stages))
    return manifest, inputs, parameters


def decode_head(data: bytes, channels: int, side: int) -> bytes:
    groups = (channels + 7) // 8
    expected = groups * side * side * 16
    if len(data) != expected:
        raise ValueError(f"FPGA head size {len(data)} != {expected}")
    packed = np.frombuffer(data, dtype="<i2").reshape(groups, side, side, 8)
    return packed.transpose(0, 3, 1, 2).reshape(-1, side, side)[:channels].tobytes()


def run_manifest(args: argparse.Namespace, manifest_path: Path) -> dict:
    manifest, inputs, parameters = load_manifest(manifest_path)
    output_spec = manifest["output"]
    report = {
        "status": "running",
        "manifest": str(manifest_path.resolve()),
        "source_manifest_sha256": sha256_file(manifest_path),
        "execution_schedule_sha256": manifest["execution_schedule_sha256"],
        "execution_stages": len(manifest["stages"]),
        "profile": manifest["profile"],
        "task": manifest["task"],
        "head_layout": "group8,Y,X,lane8 INT16",
        "fused_up_concat": manifest.get("fused_up_concat", "d1" if any(s["op"] == 13 for s in manifest["stages"]) else None),
        "inputs": [{"slice": item["slice"], "path": str(item["path"]), "sha256": item["sha256"]}
                   for item in inputs],
        "runs": [],
        "timing_scope": "PC wall time; fpga_run_seconds sums RUN+STATUS RPC waits, including polling",
        "hardware_timing_scope": "Sum of board snapshot total/compute_hz per stage; includes coefficient load, compute, DDR waits and output drain; excludes PC RPC/polling and input/output transfer",
    }
    client = OpClient(args.host, args.port, args.timeout, bind=args.bind)
    first_output_sha256 = {}
    try:
        reset_session(client)
        if parameters:
            t = perf_counter()
            client.upload(manifest["parameters"]["address"], parameters)
            report["parameter_upload_seconds"] = perf_counter() - t
        for repeat in range(args.repeat):
            for input_item in inputs:
                active = {"repeat": repeat, "slice": input_item["slice"], "stage": None,
                          "phase": "upload"}
                report["active"] = active
                wall_started = perf_counter()
                t = perf_counter()
                client.upload(input_item["address"], input_item["payload"])
                upload_seconds = perf_counter() - t
                stage_rows = []
                completed_ids = []
                used_perf_slots = set()
                head_data = None
                for index, stage in enumerate(manifest["stages"], 1):
                    active["stage"] = stage["name"]
                    descriptor = bytearray.fromhex(stage["descriptor_hex"])
                    run_id = secrets.randbits(32) or 1
                    while run_id & 63 in used_perf_slots:
                        run_id = secrets.randbits(32) or 1
                    used_perf_slots.add(run_id & 63)
                    struct.pack_into("<I", descriptor, 48, run_id)
                    active.update(phase="run", run_id=run_id, op=stage["op"])
                    print(f"[STAGE {manifest['task']} {repeat + 1}/{args.repeat} "
                          f"{index}/{len(manifest['stages'])}] {stage['name']} "
                          f"op={stage['op']} run_id=0x{run_id:08x}", flush=True)
                    t = perf_counter()
                    client.run(descriptor)
                    active["phase"] = "wait"
                    status = client.wait(run_id, timeout=args.run_timeout)
                    run_seconds = perf_counter() - t
                    expected = (stage["op"], stage["format"], stage["bytes"], 0)
                    actual = (status["op"], status["format"], status["bytes"], status["mac_bytes"])
                    if actual != expected:
                        raise RuntimeError(f"{stage['name']}: status {actual} != expected {expected}")
                    read_seconds = 0.0
                    if index == len(manifest["stages"]):
                        active["phase"] = "read"
                        t = perf_counter()
                        head_data = client.read(run_id, output_spec["address"], output_spec["bytes"])
                        read_seconds = perf_counter() - t
                    active["phase"] = "release"
                    client.rpc(RELEASE, run_id)
                    completed_ids.append(run_id)
                    stage_rows.append({"name": stage["name"], "op": stage["op"],
                                       "run_wait_seconds": run_seconds, "read_seconds": read_seconds})
                    active["completed_stages"] = stage_rows
                wall_seconds = perf_counter() - wall_started
                # 64 snapshot slots: unique low bits preserve all 31 layers until
                # the timed run ends. Diagnostic reads do not enter wall timing.
                performance_error = None
                for stage_row, completed_id in zip(stage_rows, completed_ids):
                    stage_row["hardware"] = None
                    if performance_error is not None:
                        continue
                    try:
                        stage_row["hardware"] = client.performance(completed_id)
                    except (RuntimeError, OSError) as error:
                        performance_error = str(error)
                        print(f"[CYCLES UNAVAILABLE] {performance_error}", flush=True)
                        continue
                    counters = stage_row["hardware"]["cycles"]
                    print(f"[CYCLES {stage_row['name']}] total={counters['total']}, "
                          f"load={counters['load']}, run={counters['run']}, "
                          f"output_stall={counters['output_stall']}, "
                          f"DDR_wait={counters['memory_stall']}, "
                          f"hardware={stage_row['hardware']['seconds']:.6f}s", flush=True)
                total_run = sum(row["run_wait_seconds"] for row in stage_rows)
                decoded_head = decode_head(head_data or b"", output_spec["channels"], output_spec["side"])
                output_sha256 = sha256_bytes(decoded_head)
                expected_sha256 = input_item.get("golden_sha256", output_spec.get("golden_sha256"))
                if expected_sha256 and output_sha256 != expected_sha256:
                    raise RuntimeError(f"slice {input_item['slice']} output SHA256 mismatch: "
                                       f"{output_sha256} != {expected_sha256}")
                previous_sha256 = first_output_sha256.setdefault(input_item["slice"], output_sha256)
                if output_sha256 != previous_sha256:
                    raise RuntimeError(f"slice {input_item['slice']} output changed between repeats: "
                                       f"{output_sha256} != {previous_sha256}")
                row = {
                    "slice": input_item["slice"],
                    "input_sha256": input_item["sha256"],
                    "repeat": repeat,
                    "upload_seconds": upload_seconds,
                    "fpga_run_seconds": total_run,
                    "hardware_seconds": (sum(stage["hardware"]["seconds"] for stage in stage_rows)
                                         if performance_error is None else None),
                    "hardware_unavailable": performance_error,
                    "download_seconds": stage_rows[-1]["read_seconds"],
                    "wall_seconds": wall_seconds,
                    "output_sha256": output_sha256,
                    "golden_verified": bool(expected_sha256),
                    "stages": stage_rows,
                }
                report["runs"].append(row)
                hardware_text = (f"{row['hardware_seconds']:.6f}s"
                                 if row["hardware_seconds"] is not None else "unavailable")
                print(f"[RUN {repeat + 1}/{args.repeat} SLICE {input_item['slice']}] "
                      f"upload={upload_seconds:.3f}s, HW={hardware_text}, RUN+poll={total_run:.3f}s, "
                      f"read={row['download_seconds']:.3f}s, wall={row['wall_seconds']:.3f}s, "
                      f"sha256={output_sha256}", flush=True)
        report.pop("active", None)
        report["status"] = "complete"
        report["per_slice"] = []
        for input_item in inputs:
            rows = [row for row in report["runs"] if row["slice"] == input_item["slice"]]
            summary = {
                "slice": input_item["slice"],
                "input_sha256": input_item["sha256"],
                "repeats": len(rows),
                "mean_fpga_run_seconds": sum(row["fpga_run_seconds"] for row in rows) / len(rows),
                "mean_wall_seconds": sum(row["wall_seconds"] for row in rows) / len(rows),
            }
            summary["mean_hardware_seconds"] = mean_hardware_seconds(rows)
            report["per_slice"].append(summary)
            hardware_text = (f"{summary['mean_hardware_seconds']:.6f}s"
                             if summary["mean_hardware_seconds"] is not None else "unavailable")
            print(f"[AVERAGE SLICE {summary['slice']}] HW={hardware_text}, RUN+poll="
                  f"{summary['mean_fpga_run_seconds']:.3f}s, wall="
                  f"{summary['mean_wall_seconds']:.3f}s ({summary['repeats']} runs)", flush=True)
        return report
    except BaseException as exc:
        report["status"] = "failed"
        report["error"] = str(exc) or type(exc).__name__
        return report
    finally:
        client.close()


def run(args: argparse.Namespace) -> int:
    manifest_path = args.manifest.resolve()
    if args.dry_run:
        manifest, inputs, parameters = load_manifest(manifest_path)
        input_bytes = sum(len(item["payload"]) for item in inputs)
        print(f"[VALID] {manifest_path}: {len(manifest['stages'])} stages, "
              f"slices={len(inputs)}, input={input_bytes:,} bytes total, "
              f"parameters={len(parameters or b''):,} bytes")
        return 0
    report_path = args.report.resolve() if args.report else (
        manifest_path.parent / "runs" / (manifest_path.stem + "_" +
        datetime.now().strftime("%Y%m%d_%H%M%S_%f") + ".json"))
    try:
        report = run_manifest(args, manifest_path)
    except BaseException as exc:
        report = {"status": "failed", "manifest": str(manifest_path), "error": str(exc)}
    finally:
        write_json(report_path, report)
    print(f"[REPORT] {report_path}")
    if report["status"] != "complete":
        print(f"[FAILED] {report.get('error', 'benchmark failed')}", flush=True)
        return 1
    return 0


def mean_hardware_seconds(rows: list[dict]) -> float | None:
    """Only report a board mean when every repeat has a valid snapshot."""
    values = [row.get("hardware_seconds") for row in rows]
    return sum(values) / len(values) if values and all(v is not None for v in values) else None


def suite(args: argparse.Namespace) -> int:
    """Freeze once, then benchmark one fixed plane per model on the current RTL."""
    folder = args.case_dir.resolve() / "fixed_benchmark/all_models_fused_residual"
    manifests = []
    # Validate every model before opening a socket or changing board memory.
    for task in args.tasks:
        path = folder / f"{task}.json"
        if not path.exists():
            freeze(argparse.Namespace(**{**vars(args), "task": task, "profile": "fused_residual",
                "manifest": path, "input": folder / f"{task}_input_p16_int8.bin",
                "slices": None, "golden": None, "golden_slice": None}))
        manifest, inputs, parameters = load_manifest(path)
        if (manifest["task"] != task or manifest["profile"] != "fused_residual" or len(inputs) != 1 or
                (args.slice is not None and inputs[0]["slice"] != args.slice)):
            raise ValueError(f"Frozen model/slice differs from requested suite: {path}")
        print(f"[VALID MODEL {task}] slice={inputs[0]['slice']}, "
              f"stages={len(manifest['stages'])}, parameters={len(parameters or b''):,} bytes, "
              f"Golden={'provided' if inputs[0].get('golden_sha256', manifest['output'].get('golden_sha256')) else 'none (repeat consistency only)'}", flush=True)
        manifests.append(path)
    if args.dry_run:
        print("[DRY RUN] Frozen files validated; no UDP sent.")
        return 0
    report_path = args.report.resolve() if args.report else (
        folder / "runs" / ("suite_" + datetime.now().strftime("%Y%m%d_%H%M%S_%f") + ".json"))
    report = {"status": "running", "models": [], "per_model": [],
              "timing_scope": "Same fixed plane repeated per model; parameter upload/preprocessing excluded from per-run means. fpga_run_seconds includes RUN+STATUS RPC and polling.",
              "hardware_timing_scope": "mean_hardware_seconds averages the sum of per-stage board snapshot total/compute_hz, excluding PC RPC/polling and input/output transfer",
              "validation_scope": "Repeat SHA256 consistency; Golden checked only when supplied in manifest."}
    write_json(report_path, report)
    for path in manifests:
        print(f"[MODEL {path.stem}] {args.repeat} repeats", flush=True)
        result = run_manifest(args, path)
        report["models"].append(result)
        if result["status"] != "complete":
            report.update(status="failed", error=result.get("error", "model benchmark failed"))
            write_json(report_path, report)
            print(f"[FAILED] {path.stem}: {report['error']}\n[REPORT] {report_path}", flush=True)
            return 1
        rows = result["runs"]
        means = {key: sum(row[key] for row in rows) / len(rows) for key in
                 ("upload_seconds", "fpga_run_seconds", "download_seconds", "wall_seconds")}
        summary = {"task": result["task"], "slice": rows[0]["slice"], "repeats": len(rows),
                   "golden_verified": all(row["golden_verified"] for row in rows),
                   "parameter_upload_seconds": result.get("parameter_upload_seconds", 0.0),
                   "mean_hardware_seconds": mean_hardware_seconds(rows),
                   **{"mean_" + key: value for key, value in means.items()}}
        report["per_model"].append(summary)
        hardware_text = (f"{summary['mean_hardware_seconds']:.6f}s"
                         if summary["mean_hardware_seconds"] is not None else "unavailable")
        print(f"[AVERAGE MODEL {result['task']}] upload={means['upload_seconds']:.3f}s, "
              f"HW={hardware_text}, RUN+poll={means['fpga_run_seconds']:.3f}s, read={means['download_seconds']:.3f}s, "
              f"wall={means['wall_seconds']:.3f}s ({len(rows)} runs)", flush=True)
        write_json(report_path, report)
    report["status"] = "complete"
    write_json(report_path, report)
    print(f"[REPORT] {report_path}")
    return 0


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    freeze_parser = sub.add_parser("freeze", help="one-time input/schedule snapshot")
    freeze_parser.add_argument("--case-dir", type=Path, required=True)
    freeze_parser.add_argument("--task", choices=MODEL_TASKS, default="lobe")
    slice_group = freeze_parser.add_mutually_exclusive_group(required=True)
    slice_group.add_argument("--slice", type=int)
    slice_group.add_argument("--slices", type=int, nargs="+")
    freeze_parser.add_argument("--profile", choices=("legacy", "fused", "fused_residual"), default="fused")
    freeze_parser.add_argument("--manifest", type=Path, required=True)
    freeze_parser.add_argument("--input", type=Path, required=True)
    freeze_parser.add_argument("--golden", type=Path)
    freeze_parser.add_argument("--golden-slice", type=int)
    freeze_parser.set_defaults(func=freeze)

    run_parser = sub.add_parser("run", help="run only the frozen BIN and descriptors")
    run_parser.add_argument("--manifest", type=Path, required=True)
    run_parser.set_defaults(func=run)
    suite_parser = sub.add_parser("suite", help="four-model fixed-plane benchmark on existing RTL")
    suite_parser.add_argument("--case-dir", type=Path, default=HERE / "output/ct_01")
    suite_parser.add_argument("--tasks", nargs="+", choices=MODEL_TASKS,
                              default=["vessel", "tumor", "lobe", "airway"])
    suite_parser.add_argument("--slice", type=int, help="model-grid slice; default middle slice per model")
    suite_parser.set_defaults(func=suite)
    for target in (run_parser, suite_parser):
        target.add_argument("--host", default="192.168.1.10")
        target.add_argument("--port", type=int, default=8080)
        target.add_argument("--bind", default="192.168.1.102")
        target.add_argument("--timeout", type=float, default=1.0)
        target.add_argument("--run-timeout", type=float, default=120.0)
        target.add_argument("--repeat", type=int, default=3 if target is suite_parser else 1)
        target.add_argument("--report", type=Path)
        target.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)
    if (getattr(args, "repeat", 1) < 1 or getattr(args, "timeout", 1) <= 0 or
            getattr(args, "run_timeout", 1) <= 0):
        parser.error("repeat and timeouts must be positive")
    if args.command == "suite" and len(args.tasks) != len(set(args.tasks)):
        parser.error("tasks must be unique")
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
