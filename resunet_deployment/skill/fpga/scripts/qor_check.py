#!/usr/bin/env python3
"""解析 Vivado 文本报告，做时序/资源门禁，并追加到可 diff 的历史 CSV。

只读报告文件，不调用 Vivado。支持 report_timing_summary 与 report_utilization 的默认文本格式
（UltraScale/UltraScale+/7 系列的资源行名不同，按关键字匹配）。

用法：
  python qor_check.py --timing top_timing_summary_routed.rpt [--util top_utilization_placed.rpt]
                      [--max-util 85] [--history qor_history.csv --tag round3]
                      [--baseline-util old_utilization.rpt]
退出码：0 通过；1 有门禁失败；2 报告无法解析。
"""
import argparse
import csv
import re
import sys
from datetime import datetime
from pathlib import Path

TIMING_KEYS = ["WNS", "TNS", "TNS_fail", "TNS_total", "WHS", "THS", "THS_fail", "THS_total",
               "WPWS", "TPWS", "TPWS_fail", "TPWS_total"]
# 资源行名 → 统一字段（同一字段按顺序取第一个出现的）
UTIL_ROWS = {
    "LUT": ["CLB LUTs", "Slice LUTs"],
    "FF": ["CLB Registers", "Slice Registers"],
    "CLB": ["CLB", "Slice"],
    "BRAM": ["Block RAM Tile"],
    "URAM": ["URAM"],
    "DSP": ["DSPs", "DSP48E2", "DSP48E1"],
}


def parse_timing(text):
    """Design Timing Summary 表头下的第一行数值。"""
    m = re.search(r"Design Timing Summary.*?\n\s*WNS\(ns\).*?\n\s*-+.*?\n(.*?)\n", text, re.S)
    if not m:
        return None
    nums = m.group(1).split()
    if len(nums) < 12:
        return None
    out = {}
    for k, v in zip(TIMING_KEYS, nums):
        out[k] = float(v) if "." in v else int(v)
    out["all_met"] = "All user specified timing constraints are met" in text
    # 每个时钟的 WNS/WHS（Intra Clock Table），便于定位哪个域出问题
    clocks = {}
    sec = text.split("Intra Clock Table", 1)
    if len(sec) == 2:
        started = False
        for line in sec[1].splitlines():
            parts = line.split()
            if not started:
                started = bool(parts) and set(parts[0]) == {"-"} and len(parts) > 5
                continue
            if not parts:
                if clocks:
                    break
                continue
            if len(parts) >= 13 and re.match(r"-?\d", parts[1]):
                clocks[parts[0]] = {"WNS": float(parts[1]), "WHS": float(parts[5])}
    out["clocks"] = clocks
    return out


def parse_util(text):
    out = {}
    for key, names in UTIL_ROWS.items():
        for name in names:
            m = re.search(r"^\|\s*" + re.escape(name) + r"\s*\|\s*([\d.]+)\s*\|.*?\|\s*([\d.<]+)\s*\|\s*$",
                          text, re.M)
            if m:
                out[key] = float(m.group(1))
                out[key + "_pct"] = float(m.group(2).lstrip("<"))
                break
    return out


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # Windows 控制台默认 GBK
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--timing", required=True)
    ap.add_argument("--util")
    ap.add_argument("--baseline-util", help="上一版 utilization 报告，用于检测资源突变")
    ap.add_argument("--max-util", type=float, default=85.0, help="单项资源占比红线（%%）")
    ap.add_argument("--jump", type=float, default=15.0, help="相对上一版变化超过该百分比即提示")
    ap.add_argument("--history")
    ap.add_argument("--tag", default="")
    a = ap.parse_args()

    t = parse_timing(Path(a.timing).read_text(encoding="utf-8", errors="replace"))
    if t is None:
        print("ERROR: 无法解析 Design Timing Summary"); return 2
    u = parse_util(Path(a.util).read_text(encoding="utf-8", errors="replace")) if a.util else {}

    fails, notes = [], []
    if t["WNS"] < 0: fails.append(f"setup WNS {t['WNS']} ns, {t['TNS_fail']} failing endpoints")
    if t["WHS"] < 0: fails.append(f"hold WHS {t['WHS']} ns, {t['THS_fail']} failing endpoints")
    if t["WPWS"] < 0: fails.append(f"pulse width WPWS {t['WPWS']} ns")
    if not t["all_met"]: notes.append("报告未包含 'All user specified timing constraints are met'")
    for k, v in u.items():
        if k.endswith("_pct") and v > a.max_util:
            notes.append(f"{k[:-4]} {v:.2f}% > {a.max_util}%（布线拥塞/后续扩展风险）")
    if a.baseline_util:
        b = parse_util(Path(a.baseline_util).read_text(encoding="utf-8", errors="replace"))
        for k in ("LUT", "FF", "BRAM", "URAM", "DSP"):
            if k in u and b.get(k):
                d = (u[k] - b[k]) / b[k] * 100
                if abs(d) > a.jump:
                    notes.append(f"{k} {b[k]:g} -> {u[k]:g} ({d:+.1f}%)：先查映射属性/推断退化，再看逻辑")

    print(f"WNS {t['WNS']:+.3f}  TNS {t['TNS']:.3f} ({t['TNS_fail']}/{t['TNS_total']})  "
          f"WHS {t['WHS']:+.3f}  THS {t['THS']:.3f} ({t['THS_fail']})  WPWS {t['WPWS']:+.3f}")
    worst = sorted(t["clocks"].items(), key=lambda kv: kv[1]["WNS"])[:3]
    for name, v in worst:
        print(f"  clock {name}: WNS {v['WNS']:+.3f}  WHS {v['WHS']:+.3f}")
    if u:
        print("  " + "  ".join(f"{k} {u[k]:g} ({u[k + '_pct']:.1f}%)" for k in UTIL_ROWS if k in u))
    for n in notes: print("NOTE", n)
    for f in fails: print("FAIL", f)

    if a.history:
        row = {"time": datetime.now().strftime("%Y-%m-%d %H:%M"), "tag": a.tag, "timing_rpt": a.timing,
               **{k: t[k] for k in TIMING_KEYS}, **{k: u.get(k, "") for k in UTIL_ROWS},
               "status": "PASS" if not fails else "FAIL"}
        new = not Path(a.history).exists()
        with open(a.history, "a", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(row))
            if new: w.writeheader()
            w.writerow(row)
    print("PASS" if not fails else "FAIL")
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
