"""只读：整卷推理结束后，回读板上仍保留的逐阶段硬件性能快照（不发送 RUN/START，不改板上状态）。

背景：引擎每完成一条算子命令就把 16 项核心计数写入 64 槽快照 RAM（槽号 = run_id & 63），
整卷流程里后面的命令会覆盖前面的槽，因此只能读到最后 64 条算子命令，即所选模型的最后约 2 个切片。
run_id = transfer_id + 命令序号 + 1（op_volume_service.sv V_RUN），命令序号取自与板端一致的 build_program 上下文。
快照自带 identity，读回时由 OpClient.performance 校验；被覆盖或板子已复位会报 stale，不会给出错误数据。

用法（PC_FPGA 目录）：
  .\\.venv\\Scripts\\python.exe -X utf8 -B tools\\read_stage_perf.py --case-dir output\\case_a_ext_view --model tumor
"""
import argparse
import json
import sys
from collections import OrderedDict
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))

from pc_fpga.ethernet.op_client import OpClient  # noqa: E402
from pc_fpga.ethernet.volume import build_program  # noqa: E402
from pc_fpga.files import read_json  # noqa: E402

NON_OPERATOR = ("gather", "classify", "END")
SHOWN = ("total", "load", "run", "inputs", "outputs", "input_wait", "reader_memory_stall",
         "memory_stall", "output_stall", "writer_stall", "flush", "memory_reads", "memory_writes")
DDR_LINE_BYTES = 32  # 引擎访存按 32B 事务计数


def operator_commands(contexts, identity, model):
    """返回 [(run_id, context)]：指定模型的全部算子命令，按执行顺序。"""
    rows = []
    for index, context in enumerate(contexts):
        if context.get("model") == model and context.get("stage") not in NON_OPERATOR:
            rows.append(((identity + index + 1) & 0xFFFFFFFF, context))
    return rows


def select_readable(rows, slices):
    """只保留尚未被后续命令覆盖的快照：取末尾 slices 个切片，且槽号互不相同（至多 64 条）。"""
    wanted = sorted({context["slice"] for _, context in rows})[-slices:]
    chosen = [(rid, ctx) for rid, ctx in rows if ctx["slice"] in wanted]
    slots = [rid & 63 for rid, _ in chosen]
    if len(set(slots)) != len(slots):
        raise ValueError(f"所选 {len(chosen)} 条命令的快照槽有重复，最多只能读最后 64 条；请减小 --slices")
    return chosen


def summarize(snapshots):
    """按阶段名聚合多个切片的快照；返回 OrderedDict[stage] -> {counter: mean, 'seconds': mean, 'n': n}。"""
    grouped = OrderedDict()
    for context, snap in snapshots:
        grouped.setdefault(context["stage"], []).append(snap)
    result = OrderedDict()
    for stage, items in grouped.items():
        row = {"n": len(items), "op": items[0]["op"], "seconds": sum(s["seconds"] for s in items) / len(items)}
        for name in SHOWN:
            row[name] = sum(s["cycles"][name] for s in items) / len(items)
        result[stage] = row
    return result


def print_table(model, summary, hz):
    print(f"\n[{model}] 逐阶段硬件计数（同阶段多切片取平均；周期单位={hz/1e6:.0f} MHz 计算域）")
    head = (f"{'stage':<14}{'n':>2} {'ms':>8} {'load%':>6} {'run%':>6} {'in_wait%':>9} {'rd_mem_stall%':>14} "
            f"{'mem_stall%':>11} {'out_stall%':>11} | {'in(M)':>8} {'out(M)':>8} {'cyc/in':>7} {'cyc/out':>8} {'rdB/cyc':>8}")
    print(head)
    total_seconds = 0.0
    for stage, row in summary.items():
        t = row["total"] or 1.0
        total_seconds += row["seconds"]
        inputs, outputs = row["inputs"], row["outputs"]
        cyc_in = f"{row['run'] / inputs:7.2f}" if inputs else f"{'-':>7}"
        cyc_out = f"{row['run'] / outputs:8.2f}" if outputs else f"{'-':>8}"
        print(f"{stage:<14}{row['n']:>2} {row['seconds'] * 1e3:>8.2f} {row['load'] / t * 100:>6.1f} {row['run'] / t * 100:>6.1f} "
              f"{row['input_wait'] / t * 100:>9.1f} {row['reader_memory_stall'] / t * 100:>14.1f} "
              f"{row['memory_stall'] / t * 100:>11.1f} {row['output_stall'] / t * 100:>11.1f} | "
              f"{inputs / 1e6:>8.3f} {outputs / 1e6:>8.3f} {cyc_in} {cyc_out} "
              f"{row['memory_reads'] * DDR_LINE_BYTES / t:>8.2f}")
    print(f"{'一个切片的算子合计':<16} {total_seconds * 1e3:>8.2f} ms")
    print("注：等待条件会重叠，各百分比不能相加；memory_stall 高=DDR 受限，input_wait 高=上游喂数不足。")
    print("    in/out = 被接受的输入字数 / 被握手的输出字数（事件计数）；cyc/in = run 周期 ÷ 输入字数，接近 1 说明每拍都有有效输入。")
    print("    rdB/cyc = 引擎 32B 读事务数 × 32 ÷ total 周期，即该阶段的平均 DDR 读吞吐；搬运类阶段预计约 5 B/周期（8 笔在途上限）。")


def snapshot_to_json(run_id, context, snap):
    return {"run_id": run_id, "slot": run_id & 63, "slice": context["slice"], "stage": context["stage"],
            "op": snap["op"], "format": snap["format"], "compute_hz": snap["compute_hz"], "ddr_hz": snap["ddr_hz"],
            "seconds": snap["seconds"], "cycles": snap["cycles"], "ddr_counters": snap["ddr_counters"]}


def load_raw(path):
    """读回 --raw-out 保存的原始快照；返回 [(context, snap)] 与 model/transfer_id。"""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    snapshots = [({"slice": item["slice"], "stage": item["stage"]},
                  {"op": item["op"], "format": item["format"], "compute_hz": item["compute_hz"], "ddr_hz": item["ddr_hz"],
                   "seconds": item["seconds"], "cycles": item["cycles"], "ddr_counters": item["ddr_counters"]})
                 for item in data["snapshots"]]
    return data["model"], data["transfer_id"], snapshots


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case-dir", type=Path, help="读板时必需；--from-raw 离线汇总时不需要")
    parser.add_argument("--model", choices=("lobe", "airway", "vessel", "tumor"), default="tumor")
    parser.add_argument("--slices", type=int, default=2, help="读最后几个切片（每片 30 条，最多约 2 片）")
    parser.add_argument("--host", default="192.168.1.10")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--bind", default="192.168.1.102")
    parser.add_argument("--timeout", type=float, default=1.0)
    parser.add_argument("--dry-run", action="store_true", help="只列出将读取的 run_id，不连接板卡")
    parser.add_argument("--raw-out", type=Path, help="原始快照 JSON 保存位置；默认 <case-dir>/handoff/stage_perf_<model>.json")
    parser.add_argument("--from-raw", type=Path, help="不连接板卡，直接用已保存的原始 JSON 重新汇总（板子断电后仍可分析）")
    args = parser.parse_args(argv)

    if args.from_raw:
        model, transfer_id, snapshots = load_raw(args.from_raw)
        print(f"离线汇总 {args.from_raw}: transfer_id={transfer_id} model={model} 快照数={len(snapshots)}")
        print_table(model, summarize(snapshots), snapshots[0][1]["compute_hz"])
        return 0
    if args.case_dir is None:
        parser.error("读板需要 --case-dir")

    case = args.case_dir
    job = read_json(case / "handoff/job.json")
    receipt = read_json(case / "handoff/send_receipt.json")
    contexts = []
    build_program(job, read_json(case / "input/metadata.json"), contexts=contexts)
    chosen = select_readable(operator_commands(contexts, receipt["transfer_id"], args.model), args.slices)
    print(f"transfer_id={receipt['transfer_id']} model={args.model} 命令数={len(chosen)} "
          f"run_id {chosen[0][0]}..{chosen[-1][0]}")
    if args.dry_run:
        for rid, ctx in chosen:
            print(f"  run_id={rid} slot={rid & 63:2d} slice={ctx['slice']} stage={ctx['stage']}")
        return 0

    client = OpClient(args.host, args.port, args.timeout, bind=args.bind)
    snapshots = []
    try:
        for rid, ctx in chosen:
            snapshots.append((rid, ctx, client.performance(rid)))
    finally:
        client.close()
        # 先落盘再汇总：读到一半失败也保留已读到的快照。
        raw_path = args.raw_out or case / f"handoff/stage_perf_{args.model}.json"
        raw_path.write_text(json.dumps(
            {"model": args.model, "transfer_id": receipt["transfer_id"],
             "snapshots": [snapshot_to_json(rid, ctx, snap) for rid, ctx, snap in snapshots]},
            ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"原始快照已保存：{raw_path}（{len(snapshots)}/{len(chosen)} 条）")
    pairs = [(ctx, snap) for _, ctx, snap in snapshots]
    print_table(args.model, summarize(pairs), pairs[0][1]["compute_hz"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
