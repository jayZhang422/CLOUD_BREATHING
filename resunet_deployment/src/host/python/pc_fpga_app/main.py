"""PC_FPGA 统一入口：整卷上传DDR、自主推理、完成后统一回读及STL后处理。"""
import argparse
from pathlib import Path
import sys

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent


def parser():
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--stage", choices=("all", "ct2bin", "send", "reasoning", "receive", "bin2stl", "smooth", "cut", "demo"), default="all")
    result.add_argument("--config", type=Path, default=HERE / "config.json")
    result.add_argument("--data-dir", type=Path, help="DICOM ZIP 或目录")
    result.add_argument("--case-dir", type=Path)
    result.add_argument("--series-uid")
    result.add_argument("--host")
    result.add_argument("--port", type=int)
    result.add_argument("--bind")
    result.add_argument("--timeout", type=float)
    result.add_argument("--run-timeout", type=float, default=7200., help="整卷推理等待上限（秒）")
    result.add_argument("--stall-timeout", type=float, default=120., help="板端命令进度不变的等待上限（秒），到期保存诊断并退出，不中止板端")
    result.add_argument("--image-base", type=lambda v:int(v,0))
    result.add_argument("--batch-slices", type=int)
    result.add_argument("--result-manifest", type=Path, help="已有整卷结果就绪清单；all/reasoning 默认自动生成")
    result.add_argument("--prediction-dir", type=Path, help="已有预测 BIN+metadata.json，离线后处理")
    result.add_argument("--ct-metadata", type=Path, help="BIN→STL 修补所用的匹配 CT 元数据；默认病例 input/metadata.json")
    result.add_argument("--reference-support", type=Path, help="可选：已配准到本病例的 Model 部分参考掩膜 NPZ，仅用于组件筛选")
    result.add_argument("--mesh-dir", type=Path, help="Smooth/Cut 的独立输入目录")
    result.add_argument("--iterations", type=int)
    result.add_argument("--passband", type=float)
    result.add_argument("--max-faces", type=int)
    result.add_argument("--plain", action="store_true", help="不使用 ANSI 刷新，适合重定向日志")
    result.add_argument("--no-transpose", action="store_true", help="不生成/使用朝向等价的预转置视图（回到原始朝向 gather，用于对照）")
    return result


def demo_prediction(case):
    """仅生成合成分割数据，演示文件后处理；无网络和模型推理。"""
    import numpy as np
    from pc_fpga.ct.prediction_io import write_packed_prediction
    z,y,x = np.indices((32,64,64))
    packed = np.zeros(z.shape, np.uint16)
    for index in range(9):
        cy,cx = 12+(index//3)*20, 12+(index%3)*20
        mask = ((z-16)/9)**2 + ((y-cy)/7)**2 + ((x-cx)/7)**2 <= 1
        packed[mask] |= np.uint16(1 << index)
    affine = np.array([[0,0,.8,-25],[0,.8,0,-25],[1.2,0,0,-18],[0,0,0,1.]])
    return write_packed_prediction(case / "prediction", packed, affine,
                                   dict(synthetic=True, note="Offline mesh demonstration; no FPGA inference"))


def main(argv=None):
    args = parser().parse_args(argv)
    from pc_fpga.files import read_json, write_json
    from pc_fpga.status import StatusTable, STAGES
    try:
        config = read_json(args.config)
    except (OSError, ValueError) as exc:
        parser().error(f"配置读取失败：{exc}")
    required = {"data_dir","case_dir","host","port","bind","timeout","image_base","batch_slices","iterations","passband","max_faces"}
    if not required <= config.keys():
        parser().error(f"配置缺少字段：{', '.join(sorted(required-config.keys()))}")
    for name in ("data_dir","case_dir","host","port","bind","timeout","image_base","batch_slices","iterations","passband","max_faces"):
        if getattr(args,name) is None:
            setattr(args,name,config[name])
    args.case_dir = Path(args.case_dir)
    if not args.case_dir.is_absolute():
        args.case_dir = HERE / args.case_dir
    args.case_dir = args.case_dir.resolve()
    if not 1 <= args.port <= 65535 or args.timeout <= 0 or args.run_timeout <= 0 or args.stall_timeout <= 0 or args.iterations < 1 or not 0 < args.passband <= 2 or args.max_faces < 4:
        parser().error("端口、超时、平滑或减面参数无效")
    if args.mesh_dir and args.stage not in ("smooth","cut"):
        parser().error("--mesh-dir 仅用于 smooth/cut")
    if args.prediction_dir and args.stage not in ("all","bin2stl"):
        parser().error("--prediction-dir 仅用于 all/bin2stl")
    # 独立目录完整迁移即可运行；禁止把输出写回参考工程。
    for path in (args.case_dir,):
        if any(part.lower() == "bin_udp" for part in path.parts) or path.is_relative_to(Path("E:/Pycharm_Prj/Model")):
            parser().error("输出目录不能位于只读参考工程内")
    # 板上整卷推理约 10 分钟：发布保护会在 Receive 才拒绝旧 prediction，先在发送前拦截。
    published = args.case_dir / "prediction" / "metadata.json"
    if args.stage in ("all","send") and args.prediction_dir is None and published.exists():
        parser().error(f"{published.parent} 已有发布的 prediction；新推理会产生新的 transfer id，"
                       "Receive 将被拒绝。请换用新的 --case-dir，或先把 prediction/stl 移走。")
    args.case_dir.mkdir(parents=True, exist_ok=True)
    source_prediction = args.prediction_dir or args.case_dir / "prediction"
    raw, smoothed, reduced = (args.case_dir / "stl" / name for name in ("raw","smooth","cut"))
    run_report = dict(status="running", stage=args.stage, hardware_used=False)
    write_json(args.case_dir / "run_report.json",run_report)
    try:
        with StatusTable(args.case_dir / "status.json", live=False if args.plain else None) as table:
            offline = args.prediction_dir is not None or args.stage == "demo"
            if args.stage == "demo":
                for stage in STAGES[:4]:
                    table.set(stage,"Skipped","OFFLINE SYNTHETIC DEMO")
                demo_prediction(args.case_dir)
            elif args.stage in ("ct2bin","all") and not offline:
                from pc_fpga.ct.convert import prepare, make_job
                with table.stage("CT2BIN") as progress:
                    metadata = prepare(args.data_dir,args.case_dir,args.series_uid,progress)
                    make_job(args.case_dir,args.image_base,args.batch_slices,transpose=not args.no_transpose)
                    progress(f"{metadata['model_input']['shape'][0]} slices; job.json ready")
            if offline:
                for stage in STAGES[:4]:
                    table.set(stage,"Skipped","Existing prediction; offline only")
            if args.stage in ("send", "all") and not offline and args.result_manifest is None:
                from pc_fpga.ct.convert import make_job
                from pc_fpga.ethernet.transfer import send_volume
                from pc_fpga.ethernet.volume import upload_program
                job = make_job(args.case_dir,args.image_base,args.batch_slices,transpose=not args.no_transpose)
                with table.stage("Send") as progress:
                    run_report["hardware_used"] = True
                    run_report["upload"] = send_volume(args.case_dir,job,args.host,args.port,args.bind,args.timeout,progress)
                    run_report["program"] = upload_program(args.case_dir,job,args.host,args.port,args.bind,args.timeout,progress)
                    progress("VOL2 compact views, parameters, and DDR command list uploaded")
            if args.stage in ("all","reasoning") and not offline:
                if args.result_manifest is None:
                    from pc_fpga.ethernet.volume import reason_volume
                    with table.stage("Reasoning") as progress:
                        run_report["hardware_used"] = True
                        args.result_manifest = reason_volume(args.case_dir,args.host,args.port,args.bind,args.timeout,args.run_timeout,progress,stall_timeout=args.stall_timeout)
                else:
                    table.set("Reasoning","Skipped","Existing result-ready manifest")
            if args.stage in ("receive","all") and not offline:
                if args.result_manifest is None:
                    raise ValueError("receive 需要 --result-manifest，禁止猜测结果地址和长度")
                from pc_fpga.ethernet.transfer import receive_volume
                from pc_fpga.ethernet.volume import receive_result
                with table.stage("Receive") as progress:
                    run_report["hardware_used"] = True
                    receiver = receive_result if read_json(args.result_manifest).get("format") == "pc-fpga-result-ready-v2" else receive_volume
                    run_report["result"] = receiver(args.case_dir,args.result_manifest,args.host,args.port,args.bind,args.timeout,progress)
            if args.stage in ("all","demo","bin2stl"):
                from pc_fpga.mesh.stages import bin_to_stl
                with table.stage("BIN2STL") as progress:
                    run_report["bin2stl"] = bin_to_stl(source_prediction,raw,progress,ct_metadata=args.ct_metadata,reference_support=args.reference_support)
                    progress("Model mask repair + joint lobes; LPS mm")
            if args.stage in ("all","demo","smooth"):
                from pc_fpga.mesh.stages import process_meshes
                with table.stage("Smooth") as progress:
                    run_report["smooth"] = process_meshes(args.mesh_dir or raw,smoothed,"Smooth",iterations=args.iterations,passband=args.passband,progress=progress)
                    progress("Model structure smoothing + vessel thickness protection")
            if args.stage in ("all","demo","cut"):
                from pc_fpga.mesh.stages import process_meshes
                with table.stage("Cut") as progress:
                    run_report["cut"] = process_meshes(args.mesh_dir or smoothed,reduced,"Cut",max_faces=args.max_faces,progress=progress)
                    progress(f"Target <= {args.max_faces:,} faces/object; quality first")
            run_report["status"] = "complete"
    except (Exception, KeyboardInterrupt) as exc:
        run_report.update(status="failed",error=str(exc) or type(exc).__name__)
        print(f"\n[FAILED] {run_report['error']}",file=sys.stderr)
        return 1
    finally:
        write_json(args.case_dir / "run_report.json",run_report)
        print(f"\nReport: {args.case_dir / 'run_report.json'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
