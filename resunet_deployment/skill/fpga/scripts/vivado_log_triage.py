#!/usr/bin/env python3
"""把 Vivado 日志（runme.log / vivado.log / xsim 日志）按消息 ID 归并，过滤 INFO。

同一根因常在几十个模块刷屏，按 ID 归并后逐 ID 处置，而不是按出现顺序改。

用法：
  python vivado_log_triage.py synth_1/runme.log [impl_1/runme.log ...] [--csv messages.csv]
                              [--level WARNING] [--top 30]
输出：每个 ID 的级别、次数、首次出现行号、示例文本；CSV 一行一条原始消息。
退出码：有 ERROR 时为 1，否则 0。
"""
import argparse
import csv
import re
import sys
from collections import OrderedDict
from pathlib import Path

PAT = re.compile(r"^(ERROR|CRITICAL WARNING|WARNING|INFO):\s*\[([A-Za-z_ ]+ \d+-\d+)\]\s*(.*)$")
RANK = {"ERROR": 0, "CRITICAL WARNING": 1, "WARNING": 2, "INFO": 3}
SRC = re.compile(r"\[([^\[\]]+\.(?:v|sv|vh|svh|vhd|vhdl|xdc|tcl)):(\d+)\]")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--csv")
    ap.add_argument("--level", default="WARNING", choices=list(RANK), help="报告到哪个级别为止")
    ap.add_argument("--top", type=int, default=30)
    a = ap.parse_args()

    rows, groups = [], OrderedDict()
    for log in a.logs:
        for no, line in enumerate(Path(log).read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            m = PAT.match(line.strip())
            if not m or RANK[m.group(1)] > RANK[a.level]:
                continue
            lvl, mid, msg = m.groups()
            src = SRC.search(msg)
            rows.append({"log": log, "line": no, "level": lvl, "id": mid, "file": src.group(1) if src else "",
                         "src_line": src.group(2) if src else "", "message": msg})
            g = groups.setdefault((lvl, mid), {"count": 0, "first": f"{log}:{no}", "example": msg, "files": set()})
            g["count"] += 1
            if src:
                g["files"].add(Path(src.group(1)).name)

    order = sorted(groups.items(), key=lambda kv: (RANK[kv[0][0]], -kv[1]["count"]))
    totals = {}
    for (lvl, _), g in order:
        totals[lvl] = totals.get(lvl, 0) + g["count"]
    print("  ".join(f"{k}: {v}" for k, v in sorted(totals.items(), key=lambda kv: RANK[kv[0]])) or "无匹配消息")
    for (lvl, mid), g in order[:a.top]:
        files = ", ".join(sorted(g["files"])[:3]) + (" ..." if len(g["files"]) > 3 else "")
        print(f"[{lvl:16s}] {mid:16s} x{g['count']:<5d} first {g['first']}  {files}")
        print(f"    {g['example'][:160]}")
    if len(order) > a.top:
        print(f"... 另有 {len(order) - a.top} 个 ID，见 CSV")

    if a.csv:
        with open(a.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=["log", "line", "level", "id", "file", "src_line", "message"])
            w.writeheader()
            w.writerows(rows)
    return 1 if totals.get("ERROR") else 0


if __name__ == "__main__":
    sys.exit(main())
