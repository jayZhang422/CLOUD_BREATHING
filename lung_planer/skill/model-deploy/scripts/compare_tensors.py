#!/usr/bin/env python3
"""逐元素比对两个二进制张量（RTL/板端输出 vs Golden），给出首个差异的多维坐标与误差统计。

用法：
  python compare_tensors.py actual.bin golden.bin --dtype int32 [--shape 16,4,4] [--atol 0]
                            [--layout CHW] [--max-report 10] [--json diff.json]
默认 atol=0（整数网络要求逐位一致）。只在契约明确规定容差时才设 atol。
退出码：0 一致；1 不一致；2 尺寸/形状不匹配。
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("actual")
    ap.add_argument("golden")
    ap.add_argument("--dtype", required=True)
    ap.add_argument("--shape")
    ap.add_argument("--layout", default="", help="仅用于打印坐标名，如 CHW、ZYX")
    ap.add_argument("--atol", type=float, default=0)
    ap.add_argument("--max-report", type=int, default=10)
    ap.add_argument("--json")
    a = ap.parse_args()

    act = np.fromfile(a.actual, dtype=a.dtype)
    gold = np.fromfile(a.golden, dtype=a.dtype)
    sha = {k: hashlib.sha256(Path(p).read_bytes()).hexdigest() for k, p in (("actual", a.actual), ("golden", a.golden))}
    res = {"actual": a.actual, "golden": a.golden, "dtype": a.dtype, "sha256": sha,
           "byte_identical": sha["actual"] == sha["golden"], "elements": int(gold.size)}
    if act.size != gold.size:
        print(f"SIZE MISMATCH actual={act.size} golden={gold.size} ({a.dtype})")
        return 2
    shape = tuple(int(s) for s in a.shape.split(",")) if a.shape else gold.shape
    if int(np.prod(shape)) != gold.size:
        print(f"SHAPE {shape} 与元素数 {gold.size} 不符")
        return 2
    act, gold = act.reshape(shape), gold.reshape(shape)

    diff = np.abs(act.astype(np.float64) - gold.astype(np.float64))
    bad = np.argwhere(diff > a.atol)
    res.update({"mismatches": int(len(bad)), "max_abs_err": float(diff.max()) if diff.size else 0.0,
                "atol": a.atol, "shape": list(shape)})
    names = list(a.layout) if len(a.layout) == len(shape) else [f"d{i}" for i in range(len(shape))]
    samples = []
    for idx in bad[:a.max_report]:
        t = tuple(int(i) for i in idx)
        samples.append({"index": dict(zip(names, t)), "actual": act[t].item(), "golden": gold[t].item()})
    res["first_mismatches"] = samples
    if len(bad):
        # 差异的分布：按第 0 维（通道/层/切片）统计，帮助区分「整体偏移」与「边界一圈错」
        axis0 = np.bincount(bad[:, 0], minlength=shape[0]).tolist() if len(shape) > 1 else []
        res["mismatch_per_axis0"] = axis0
        edge = 0
        if len(shape) >= 2:
            h, w = shape[-2], shape[-1]
            edge = int(np.sum((bad[:, -2] == 0) | (bad[:, -2] == h - 1) | (bad[:, -1] == 0) | (bad[:, -1] == w - 1)))
        res["mismatch_on_border"] = edge

    status = "MATCH" if not len(bad) else "MISMATCH"
    print(f"{status} elements={gold.size} mismatches={len(bad)} max_abs_err={res['max_abs_err']:g} "
          f"byte_identical={res['byte_identical']}")
    for s in samples:
        print("  ", s)
    if len(bad) and len(shape) >= 2:
        print(f"   边界像素上的差异 {res['mismatch_on_border']}/{len(bad)}（接近全部 → 查 padding/补边码/zero_point）")
    if a.json:
        Path(a.json).write_text(json.dumps(res, indent=2, ensure_ascii=False), encoding="utf-8")
    return 0 if not len(bad) else 1


if __name__ == "__main__":
    sys.exit(main())
