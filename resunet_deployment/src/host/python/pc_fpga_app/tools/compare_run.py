"""只读：汇总一次整卷运行并与基线对照（不连接板卡）。

读取 <case-dir>/run_report.json、handoff/inference_status.json，打印：
  结果 SHA256 是否等于 --expect-sha；推理耗时与基线 --baseline-seconds 的差；
  各阶段周期折算秒数（operator / gather / classify）与基线；DDR 缓存命中率。
基线默认取 2026-11-01 case_a在 8 深度、逐像素 classify 比特流上的实测值。

用法（PC_FPGA 目录）：
  .\\.venv\\Scripts\\python.exe -X utf8 -B tools\\compare_run.py --case-dir output\\case_a_new ^
      --expect-sha 3304aa80c4360e87973e116a167f50bb89a455a25e1b0b8de5f432aed8bb0ebb
"""
import argparse
import json
import sys
from pathlib import Path

BASELINE = dict(seconds=596.9, operator=428.4, gather=30.2, classify=137.5)
HZ = 250e6


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def summarize(case, expect_sha=None, baseline=BASELINE):
    report = load(case / "run_report.json")
    status = load(case / "handoff/inference_status.json")
    sha = report["result"]["sha256"]
    seconds = report["result"]["provenance"]["result_ready"]["elapsed_seconds"]
    cycles = status["volume_cycles"]
    hardware = status["hardware"]
    hits, misses = hardware["compact_cache_hits"], hardware["compact_cache_misses"]
    rows = dict(operator=cycles["operator"] / HZ, gather=cycles["gather"] / HZ, classify=cycles["classify"] / HZ)
    lines = [f"case: {case}", f"SHA256: {sha}"]
    ok = True
    if expect_sha:
        match = sha == expect_sha
        ok = match
        lines.append("SHA 对照: " + ("一致" if match else f"不一致！期望 {expect_sha}"))
    lines.append(f"推理耗时: {seconds:.1f} s（基线 {baseline['seconds']:.1f} s，差 {seconds - baseline['seconds']:+.1f} s）")
    for name, value in rows.items():
        lines.append(f"  {name:<9}{value:7.1f} s（基线 {baseline[name]:6.1f} s，差 {value - baseline[name]:+7.1f} s）")
    lines.append(f"compact 缓存命中率: {hits / (hits + misses) * 100:.2f}%（命中 {hits}，未命中 {misses}）")
    lines.append(f"完成命令: {status['completed_commands']}/{status['total_commands']}")
    return ok, "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case-dir", type=Path, required=True)
    parser.add_argument("--expect-sha")
    parser.add_argument("--baseline-seconds", type=float, default=BASELINE["seconds"])
    args = parser.parse_args(argv)
    baseline = dict(BASELINE, seconds=args.baseline_seconds)
    ok, text = summarize(args.case_dir, args.expect_sha, baseline)
    print(text)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
