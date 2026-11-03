#!/usr/bin/env python3
r"""按统一规则判定仿真日志，写 result.json（含源文件 SHA256）。

判定 PASS 需同时满足：
  1. 日志含 PASS 标记（默认正则 r"\[TB PASSED\]|TEST_PASS"）
  2. 日志不含失败标记（FAILED / Fatal / ERROR: / watchdog / timeout / MISMATCH）
  3. 若给出 --expect-count，PASS 行里的计数（checked=/outputs=/cases=/windows=/*_values= 等）至少有一个等于它
适用于 xsim、Verilator、Icarus、SpinalSim(sbt) 的文本日志。

用法：
  python sim_check.py run.log [--expect-count 2048] [--sources rtl/*.sv tb/*.sv]
                      [--pass-re REGEX] [--out result.json]
退出码：0 PASS，1 FAIL。
"""
import argparse
import glob
import hashlib
import json
import re
import sys
from pathlib import Path

FAIL_RE = re.compile(r"\[TB FAILED\]|\bFATAL\b|Fatal:|^ERROR:|\[error\]|MISMATCH|watchdog|timed? ?out|"
                     r"Simulation failed|Assertion failed", re.I | re.M)
COUNT_RE = re.compile(r"\b(?:checked|outputs|cases|compared|lanes|windows|\w+_values)=(\d+)")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log")
    ap.add_argument("--pass-re", default=r"\[TB PASSED\]|TEST_PASS")
    ap.add_argument("--expect-count", type=int)
    ap.add_argument("--sources", nargs="*", default=[])
    ap.add_argument("--out", default="result.json")
    a = ap.parse_args()

    text = Path(a.log).read_text(encoding="utf-8", errors="replace")
    pass_lines = [l for l in text.splitlines() if re.search(a.pass_re, l)]
    fail_hits = [m.group(0) for m in FAIL_RE.finditer(text)]
    counts = sorted({int(c) for l in pass_lines for c in COUNT_RE.findall(l)})
    reasons = []
    if not pass_lines:
        reasons.append("no PASS marker")
    if fail_hits:
        reasons.append(f"failure markers: {sorted(set(fail_hits))[:5]}")
    if a.expect_count is not None and a.expect_count not in counts:
        reasons.append(f"expected count {a.expect_count} not found in PASS lines (found {counts})")

    files = sorted({p for pat in a.sources for p in glob.glob(pat, recursive=True)})
    result = {"status": "PASS" if not reasons else "FAIL", "log": a.log,
              "pass_lines": pass_lines[-5:], "counts": counts, "reasons": reasons,
              "source_sha256": {f: hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in files},
              "boundary": "仿真 PASS 只证明功能与 Golden 一致；时序、资源、上板行为需另行验证。"}
    Path(a.out).write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    print(result["status"], *(reasons or pass_lines[-1:]))
    return 0 if not reasons else 1


if __name__ == "__main__":
    sys.exit(main())
