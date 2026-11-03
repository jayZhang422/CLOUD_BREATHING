"""CT ZIP -> INT8 BIN -> FPGA INT16 heads -> UINT16 masks -> verified STL."""

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import sys
from time import perf_counter

import numpy as np

from .fullnet import (TASKS, NetworkPlan, coefficient_image, prepare_session, run_plane,
                      classify, ASSETS)
from .io.dicom_ct import load_ct_series
from .io.fpga_volume_io import load_volume, resample_int8, restore_labels
from .io.prediction_io import CHANNELS, file_sha256, write_packed_prediction
from .op_client import OpClient
from .volume_bin import quantize_hu

HERE = Path(__file__).resolve().parents[1]
DEFAULT_CASE = HERE / "output/ct_01"
DEFAULT_CT = Path("data/ct_input.zip")
REFERENCE = Path("data/ct_stl_work/01/reference_support.npz")
PIPELINE_VERSION = "fpga-ct-v1"


def write_json(path, payload):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix+".tmp")
    temp.write_text(json.dumps(payload, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    temp.replace(path)


def check_copied_sources():
    records = json.loads((ASSETS / "validated_model_sources.json").read_text(encoding="utf-8-sig"))
    for entry in records:
        if file_sha256(HERE / entry["file"]) != entry["sha256"]:
            raise ValueError(f"Verified CT/STL source changed: {entry['file']}")
    return len(records)


def prepare_ct(data_dir, input_dir, series_uid=None):
    started = perf_counter()
    input_dir = Path(input_dir)
    path = input_dir / "ct_volume_int8.bin"
    metadata_path = input_dir / "metadata.json"
    if metadata_path.exists():
        volume, metadata = load_volume(path, metadata_path)
        if Path(metadata["source_dicom"]).resolve() != Path(data_dir).resolve():
            raise ValueError("Input directory belongs to a different source CT")
        print(f"[CT BIN reused] {list(volume.shape)}, {path.stat().st_size:,} bytes", flush=True)
        return metadata
    # Original DICOM ZIP reader and physical geometry are copied without edits.
    hu, metadata = load_ct_series(Path(data_dir), series_uid)
    if hu.shape[1:] != (512, 512):
        raise ValueError("FPGA input must have source planes of 512x512")
    read_s = perf_counter()-started
    input_dir.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(".bin.tmp")
    with temp.open("wb") as stream:
        for plane in hu:
            stream.write(quantize_hu(plane).tobytes())
    temp.replace(path)
    metadata["model_input"] = dict(file=path.name, dtype="int8", layout="Z,Y,X", shape=list(hu.shape),
        hu_clip=[-1024.0, 1000.0], sha256=file_sha256(path), bytes=path.stat().st_size,
        channel_offsets_z=[-1, 0, 1], edge_policy="repeat_boundary_slice",
        mapping="round((clip(HU)-hu_min)*255/(hu_max-hu_min))-128")
    metadata["stage_timings_s"] = dict(read_dicom=read_s, total=perf_counter()-started)
    write_json(metadata_path, metadata)
    print(f"[CT BIN] {hu.shape}, {path.stat().st_size:,} bytes, {perf_counter()-started:.2f}s -> {path}", flush=True)
    return metadata


def volume_geometry(volume, metadata):
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"])
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    directions = affine[:3, :3] / spacing
    direction = metadata["anatomical_z_direction"]
    if (direction not in (-1, 1) or not np.allclose(directions[:2], [[0,0,1], [0,1,0]], atol=1e-3)
            or not np.allclose(abs(directions[2]), [1,0,0], atol=1e-3)):
        raise ValueError("Current verified RAS adapter requires axial L/P source planes and verified slice order")
    return affine, spacing, direction


def task_grid(volume, spacing, target_spacing):
    shape = tuple(np.maximum(2, np.rint((np.asarray(volume.shape)-1)*spacing/target_spacing).astype(int)+1)) if target_spacing else volume.shape
    if max(shape[1:]) > 512:
        raise ValueError("Model-space plane exceeds 512")
    return resample_int8(volume, shape) if target_spacing else volume


def prepare_sample(centers, index, orientation, direction):
    # Same Q16/neighbor order/padding/orientation as Model/src/fpga/fpga_int8.py.
    depth, height, width = centers.shape
    neighbors = np.clip(index+np.array([-1,0,1])*(direction if orientation=="nifti-ras" else 1), 0, depth-1)
    pad_y, pad_x = (512-height)//2, (512-width)//2
    sample = np.full((3,512,512), -128, np.int8)
    sample[:, pad_y:pad_y+height, pad_x:pad_x+width] = centers[neighbors]
    if orientation == "nifti-ras":
        sample = sample[..., ::-1, ::-1].swapaxes(-1,-2)
    elif orientation == "transpose":
        sample = sample.swapaxes(-1,-2)
    return np.ascontiguousarray(sample)


def native_plane(logits, orientation, shape):
    result = classify(logits)
    if orientation == "nifti-ras":
        result = result.T[::-1, ::-1]
    elif orientation == "transpose":
        result = result.T
    h,w = shape[-2:]
    y,x = (512-h)//2, (512-w)//2
    return result[y:y+h, x:x+w]


def plans(lobe_only=False):
    image = coefficient_image()
    return {task: NetworkPlan(task, image, fuse_dw_add=True)
            for task, *_ in TASKS if not lobe_only or task=="lobe"}


def connect(args):
    client = OpClient(args.host, args.port, args.timeout, bind=args.bind)
    try:
        prepare_session(client)
    except BaseException:
        client.close()
        raise
    return client


def benchmark(args, all_plans):
    volume, metadata = load_volume(args.case_dir/"input/ct_volume_int8.bin", args.case_dir/"input/metadata.json")
    _, spacing, direction = volume_geometry(volume, metadata)
    folder = args.case_dir / "benchmarks" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    report = dict(status="running", timing_scope="PC wall time; RUN+STATUS includes RPC, parameter loading, DDR and polling; not a hardware cycle counter", planes=[])
    report.update(host=args.host,port=args.port,bind=args.bind,input_sha256=metadata["model_input"]["sha256"])
    client = None
    started = perf_counter()
    try:
        client = connect(args)
        for task, channels, _, orientation, target_spacing in TASKS:
            if args.tasks and task not in args.tasks:
                continue
            plan = all_plans[task]
            centers = task_grid(volume, spacing, target_spacing)
            fused = sum(s["op"]==11 for s in plan.stages)
            print(f"[BENCHMARK] {task}: {len(centers)} model slices, {plan.channels} INT16 channels; "
                  f"{len(plan.stages)} RUN/slice, {fused} fused DW3+DW5+Mix (op=11)",flush=True)
            t = perf_counter()
            if plan.parameters:
                client.upload(0x08000000, plan.parameters)
            parameter_s = perf_counter()-t
            for repeat in range(args.repeat):
                index = len(centers)//2 if args.slice is None else args.slice
                if not 0 <= index < len(centers):
                    raise ValueError(f"{task}: model slice must be in 0..{len(centers)-1}")
                record = dict(model=task, model_slice=index, repeat=repeat, parameter_upload_seconds=parameter_s,
                              plan=plan.summary(),
                              model_shape_z_y_x=list(map(int,centers.shape)))
                report["planes"].append(record)
                logits = run_plane(client, plan, prepare_sample(centers,index,orientation,direction), args.run_timeout, record)
                folder.mkdir(parents=True,exist_ok=True)
                # Save true channels in C,Y,X order, distinct from the padded P4 wire layout.
                path = folder/f"{task}_{repeat}_logits_int16.bin"
                logits.astype("<i2",copy=False).tofile(path)
                record.update(head_bin=str(path.resolve()), head_shape=list(logits.shape), head_sha256=file_sha256(path),
                              slices_per_second=1/record["elapsed_seconds"])
                print(f"[FPGA TIME] {task} z={index}: upload={record['upload_seconds']:.3f}s, "
                      f"RUN+STATUS={record['run_wait_seconds']:.3f}s, read={record['download_seconds']:.3f}s, "
                      f"total={record['elapsed_seconds']:.3f}s ({record['slices_per_second']:.4f} slice/s)", flush=True)
                write_json(folder/"performance.json", report)
            del centers
        estimates = {}
        for task in {p["model"] for p in report["planes"]}:
            rows = [p for p in report["planes"] if p["model"]==task]
            estimates[task] = float(np.mean([p["elapsed_seconds"] for p in rows]))*rows[0]["model_shape_z_y_x"][0]+rows[0]["parameter_upload_seconds"]
        report["estimated_volume_seconds_from_sampled_slices"] = estimates
        report["status"] = "complete"
    except BaseException as exc:
        report.update(status="failed",error=str(exc) or type(exc).__name__)
        raise
    finally:
        if client is not None:
            client.close()
        report["elapsed_seconds"] = perf_counter()-started
        write_json(folder/"performance.json",report)
    print(f"[BENCHMARK COMPLETE] {folder/'performance.json'}",flush=True)


def infer(args, all_plans):
    input_bin, metadata_path = args.case_dir/"input/ct_volume_int8.bin", args.case_dir/"input/metadata.json"
    volume, metadata = load_volume(input_bin, metadata_path)
    affine, spacing, direction = volume_geometry(volume,metadata)
    lobe_only = getattr(args,"lobe_only",False)
    selected = TASKS[:1] if lobe_only else TASKS
    prediction_dir = args.case_dir/("prediction_lobe" if lobe_only else "prediction")
    # Reuse the same completed slices; publish scoped results separately.
    progress_dir = args.case_dir/"prediction/progress"
    progress_dir.mkdir(parents=True,exist_ok=True)
    # Publish a final metadata.json only after every model and every slice completes.
    if (prediction_dir/"metadata.json").exists():
        from .io.prediction_io import read_prediction
        _, existing = read_prediction(prediction_dir)
        provenance = existing["provenance"]
        if (provenance.get("pipeline_version") != PIPELINE_VERSION or provenance["input_sha256"] != file_sha256(input_bin)
                or provenance.get("input_metadata_sha256") != file_sha256(metadata_path)
                or set(provenance["tasks"]) != {t[0] for t in selected}
                or any(any(provenance["tasks"][t].get(key) != getattr(p,key)
                           for key in ("schedule_sha256","contract_sha256","export_sha256"))
                       for t,p in all_plans.items() if t in {s[0] for s in selected})):
            raise ValueError("Prediction directory contains a different run; choose a new --case-dir")
        print(f"[UINT16 BIN reused] {prediction_dir}",flush=True)
        return
    started = perf_counter()
    packed = np.zeros(volume.shape,np.uint16)
    task_reports = {}
    report = dict(status="running", pipeline_version=PIPELINE_VERSION, tasks=task_reports,
                  host=args.host,port=args.port,bind=args.bind)
    client = None
    try:
        for task,channels,offset,orientation,target_spacing in selected:
            plan = all_plans[task]
            task_start = perf_counter()
            centers = task_grid(volume,spacing,target_spacing)
            identity = dict(pipeline_version=PIPELINE_VERSION,input_sha256=metadata["model_input"]["sha256"],
                            input_metadata_sha256=file_sha256(metadata_path),schedule_sha256=plan.schedule_sha256,
                            contract_sha256=plan.contract_sha256,model_shape=list(centers.shape),orientation=orientation)
            identity["export_sha256"] = plan.export_sha256
            checkpoint = progress_dir/f"{task}.json"
            labels_path = progress_dir/f"{task}_labels_uint8.bin"
            state = json.loads(checkpoint.read_text(encoding="utf-8")) if checkpoint.exists() else dict(identity=identity,completed=0,timings=[])
            if state["identity"] != identity:
                raise ValueError(f"{task}: resume checkpoint belongs to another input/model")
            completed = state["completed"]
            if not 0 <= completed <= len(centers):
                raise ValueError("Invalid completed slice count")
            if labels_path.exists() and labels_path.stat().st_size != centers.size:
                raise ValueError("Resume label BIN size mismatch")
            if completed and not labels_path.exists():
                raise ValueError("Missing resume label BIN")
            labels = np.memmap(labels_path,mode="r+" if labels_path.exists() else "w+",dtype=np.uint8,shape=centers.shape)
            if len(state["timings"]) != completed:
                raise ValueError("Resume timing/checksum count mismatch")
            for index, saved in enumerate(state["timings"]):
                if hashlib.sha256(labels[index].tobytes()).hexdigest() != saved["label_sha256"]:
                    raise ValueError(f"{task}: resume slice {index} checksum mismatch")
            if completed < len(centers) and client is None:
                client = connect(args)
            parameter_s = 0.0
            if plan.parameters and completed < len(centers):
                t = perf_counter()
                client.upload(0x08000000,plan.parameters)
                parameter_s = perf_counter()-t
            for index in range(completed,len(centers)):
                active = dict(model=task,model_slice=index)
                report["active"] = active
                logits = run_plane(client,plan,prepare_sample(centers,index,orientation,direction),args.run_timeout,active)
                labels[index] = native_plane(logits,orientation,centers.shape)
                labels.flush()
                state["completed"] = index+1
                state["timings"].append({k:active[k] for k in ("model_slice","upload_seconds","run_wait_seconds","download_seconds","elapsed_seconds")})
                state["timings"][-1]["label_sha256"] = hashlib.sha256(labels[index].tobytes()).hexdigest()
                write_json(checkpoint,state)
                mean = float(np.mean([r["elapsed_seconds"] for r in state["timings"]]))
                print(f"[FPGA] {task} {index+1}/{len(centers)}: {active['elapsed_seconds']:.2f}s/slice, "
                      f"mean={mean:.2f}s, ETA={(len(centers)-index-1)*mean/60:.1f}min",flush=True)
            native = restore_labels(labels,volume.shape)
            counts = []
            for channel in range(channels):
                mask = native==channel+1
                packed[mask] |= np.uint16(1 << (offset+channel))
                counts.append(int(mask.sum()))
            task_reports[task] = dict(**plan.summary(),raw_channel_voxels=counts,orientation=orientation,
                model_spacing_mm=target_spacing,model_shape_z_y_x=list(map(int,centers.shape)),
                logit_threshold=0,logit_dtype="int16",parameter_upload_seconds=parameter_s,
                elapsed_this_session_seconds=perf_counter()-task_start,timings=state["timings"])
            del labels,native,centers
            report.pop("active",None)
            write_json(prediction_dir/"performance.json",report)
        provenance = dict(pipeline_version=PIPELINE_VERSION,input_bin=str(input_bin.resolve()),input_metadata=str(metadata_path.resolve()),
            input_sha256=file_sha256(input_bin),input_shape=list(volume.shape),input_metadata_content=metadata,tasks=task_reports,
            input_metadata_sha256=file_sha256(metadata_path),
            device="KU5P FPGA via UDP operator RPC",arithmetic="INT8 features/weights; INT32 MAC; INT64 RNE; INT16 logits",
            input_adaptation="Verified Q16 resampling, neighbor ordering/orientation/padding, integer nearest-neighbor restore",
            timing_scope="PC wall time; RUN+STATUS includes command, parameter loading, DDR and polling",
            elapsed_seconds=perf_counter()-started)
        provenance["inferred_tasks"] = [t[0] for t in selected]
        provenance["not_inferred_tasks"] = [t[0] for t in TASKS if t not in selected]
        result = write_packed_prediction(prediction_dir,packed,affine,provenance)
        if lobe_only:
            result["semantics"] += "; lobe-only: bits 5..8 are uncomputed placeholders, not negative predictions"
            write_json(prediction_dir/"metadata.json",result)
        report.update(status="complete",sha256=result["sha256"])
        print(f"[UINT16 BIN] {result['shape']}, {result['bytes']:,} bytes -> {prediction_dir}",flush=True)
    except BaseException as exc:
        report.update(status="failed",error=str(exc) or type(exc).__name__)
        raise
    finally:
        if client is not None:
            client.close()
        report["elapsed_this_session_seconds"] = perf_counter()-started
        write_json(prediction_dir/"performance.json",report)


def postprocess(args):
    from .stl.chest_ct_to_stl import argument_parser, postprocess_case
    options = argument_parser("postprocess").parse_args([])
    suffix = "_lobe" if args.lobe_only else ""
    options.prediction_dir = args.case_dir/("prediction"+suffix)
    options.output_dir = args.case_dir/("work"+suffix)
    options.view_dir = args.case_dir/("stl"+suffix)
    options.reference_support = args.reference_support
    options.smooth_only = args.smooth_only
    options.no_previews = args.no_previews
    started = perf_counter()
    postprocess_case(options)
    write_json(args.case_dir/("postprocess_time"+suffix+".json"),dict(elapsed_seconds=perf_counter()-started))
    if args.lobe_only:
        write_json(options.view_dir/"inference_scope.json",dict(inferred_tasks=["lobe"],
            not_inferred_tasks=[t[0] for t in TASKS[1:]],note="Only five lung lobes inferred; other structures were not evaluated."))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage",choices=("prepare","plan","infer","benchmark","postprocess","all","view","smooth-vessels"))
    parser.add_argument("--case-dir",type=Path,default=DEFAULT_CASE)
    parser.add_argument("--data-dir",type=Path,default=DEFAULT_CT)
    parser.add_argument("--series-uid")
    parser.add_argument("--host",default="192.168.1.10")
    parser.add_argument("--port",type=int,default=8080)
    parser.add_argument("--bind",default="192.168.1.102",help="PC NIC IPv4; ephemeral source port")
    parser.add_argument("--timeout",type=float,default=1.)
    parser.add_argument("--run-timeout",type=float,default=600.)
    parser.add_argument("--tasks",nargs="+",choices=[t[0] for t in TASKS],help="benchmark only")
    parser.add_argument("--slice",type=int,help="benchmark only: model-grid index; default central slice")
    parser.add_argument("--repeat",type=int,default=1,help="benchmark only")
    parser.add_argument("--reference-support",type=Path,help="optional CT-aligned reference_support.npz; use 01's verified file for 01")
    parser.add_argument("--smooth-only",action="store_true")
    parser.add_argument("--no-previews",action="store_true")
    parser.add_argument("--lobe-only",action="store_true",help="infer/export five lung lobes only; reuse completed lobe checkpoints")
    args = parser.parse_args(argv)
    if (args.tasks or args.slice is not None or args.repeat!=1) and args.stage!="benchmark":
        parser.error("--tasks/--slice/--repeat are only for benchmark; use --lobe-only for five-lobe output")
    if not 1<=args.port<=65535 or min(args.timeout,args.run_timeout)<=0 or args.repeat<1:
        parser.error("invalid port, timeout or repeat count")
    if args.lobe_only and args.stage not in ("all","infer","postprocess","view","plan"):
        parser.error("--lobe-only supports all/infer/postprocess/view/plan")
    check_copied_sources()
    if args.reference_support is None and args.data_dir.resolve()==DEFAULT_CT.resolve() and REFERENCE.exists():
        # Only default 01 may use 01's verified reference; other CTs require explicit input.
        args.reference_support = REFERENCE if args.stage=="all" else None
    if args.stage in ("prepare","all"):
        prepare_ct(args.data_dir,args.case_dir/"input",args.series_uid)
    if args.stage in ("plan","infer","benchmark","all"):
        all_plans = plans(args.lobe_only)
        if args.stage=="plan":
            summary = dict(copied_sources=check_copied_sources(),models=[p.summary() for p in all_plans.values()])
            print(json.dumps(summary,ensure_ascii=False,indent=2))
            write_json(args.case_dir/"deployment_plan.json",summary)
        elif args.stage=="benchmark":
            benchmark(args,all_plans)
        else:
            infer(args,all_plans)
    if args.stage in ("postprocess","all"):
        postprocess(args)
    if args.stage in ("view","smooth-vessels"):
        from importlib import import_module
        module = import_module("src.stl."+("view_chest" if args.stage=="view" else "vessel_surface"))
        view_dir = args.case_dir/"stl_lobe" if args.lobe_only else (args.case_dir/"stl_vessels_refined" if (args.case_dir/"stl_vessels_refined").exists() else args.case_dir/"stl")
        forwarded = ["--output-dir",str(view_dir)] if args.stage=="view" else [
            "--source-dir",str(args.case_dir/"stl"),"--output-dir",str(args.case_dir/"stl_vessels_refined"),
            "--mask-dir",str(args.case_dir/"work")]
        sys.argv = [sys.argv[0],*forwarded]
        module.main()
    return 0
