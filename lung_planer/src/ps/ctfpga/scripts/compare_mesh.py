#!/usr/bin/env python3
"""对照 C++ 与 Python 的网格三阶段产物：掩膜体素差异、面数、体积、双向最近顶点距离。
用法：compare_mesh.py <python_case_dir> <cpp_case_dir>
"""
import json
import sys
from pathlib import Path

import numpy as np

NAMES = ["LeftUpperLobe", "LeftLowerLobe", "RightUpperLobe", "RightMiddleLobe", "RightLowerLobe",
         "Bronchus", "PulmonaryArtery", "PulmonaryVenous", "LungTumor"]


def read_stl(path):
    raw = np.fromfile(path, dtype=np.uint8)
    n = int(np.frombuffer(raw[80:84].tobytes(), "<u4")[0])
    rec = np.frombuffer(raw[84:84 + 50 * n].tobytes(), dtype=np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")]))
    return rec["v"].reshape(-1, 3).astype(np.float64), n


def load_manifest(root, stage):
    return {o["name"]: o for o in json.loads((Path(root) / "stl" / stage / "manifest.json").read_text(encoding="utf-8"))["objects"]}


def nearest(a, b):
    """a 中每点到 b 的最近距离（分块 + 网格哈希前先用 KD 树）。"""
    from scipy.spatial import cKDTree  # noqa: WPS433
    return cKDTree(b).query(a, workers=-1)[0]


def main(py_root, cpp_root):
    try:
        import scipy  # noqa: F401
        have_scipy = True
    except ImportError:
        have_scipy = False
    py_raw, cpp_raw = load_manifest(py_root, "raw"), load_manifest(cpp_root, "raw")
    py_s, cpp_s = load_manifest(py_root, "smooth"), load_manifest(cpp_root, "smooth")
    py_c, cpp_c = load_manifest(py_root, "cut"), load_manifest(cpp_root, "cut")

    print("== 修补后掩膜 ==")
    print(f"{'结构':<18}{'Python体素':>12}{'C++体素':>12}{'异或体素':>10}{'异或/Py':>9}{'Dice':>8}")
    for name in NAMES:
        a = np.load(Path(py_root) / "stl/raw" / py_raw[name]["mask_file"]).astype(bool)
        b = np.load(Path(cpp_root) / "stl/raw" / cpp_raw[name]["mask_file"]).astype(bool)
        inter = int((a & b).sum())
        xor = int((a ^ b).sum())
        dice = 2 * inter / max(int(a.sum()) + int(b.sum()), 1)
        print(f"{name:<18}{int(a.sum()):>12,}{int(b.sum()):>12,}{xor:>10,}{xor / max(int(a.sum()), 1):>9.2%}{dice:>8.4f}")

    for stage, py, cpp in (("raw", py_raw, cpp_raw), ("smooth", py_s, cpp_s), ("cut", py_c, cpp_c)):
        print(f"\n== {stage} STL ==")
        print(f"{'结构':<18}{'Py面数':>10}{'C++面数':>10}{'Py体积mm3':>14}{'C++体积mm3':>14}{'体积差':>8}{'P50 mm':>8}{'P99 mm':>8}{'max mm':>8}  状态")
        for name in NAMES:
            if py[name]["status"] == "empty_prediction" or cpp[name]["status"] == "empty_prediction":
                print(f"{name:<18}  (空)")
                continue
            pa, pn = read_stl(Path(py_root) / "stl" / stage / py[name]["file"])
            ca, cn = read_stl(Path(cpp_root) / "stl" / stage / cpp[name]["file"])
            pv, cv = py[name]["volume_mm3"], cpp[name]["volume_mm3"]
            if have_scipy:
                # 取不超过 20 万点以控制耗时
                rng = np.random.default_rng(0)
                sa = pa[rng.choice(len(pa), min(len(pa), 200000), replace=False)]
                sb = ca[rng.choice(len(ca), min(len(ca), 200000), replace=False)]
                d = np.concatenate([nearest(sa, ca), nearest(sb, pa)])
                p50, p99, mx = np.percentile(d, 50), np.percentile(d, 99), d.max()
            else:
                p50 = p99 = mx = float("nan")
            print(f"{name:<18}{pn:>10,}{cn:>10,}{pv:>14,.0f}{cv:>14,.0f}{(cv / pv - 1):>8.2%}{p50:>8.3f}{p99:>8.3f}{mx:>8.3f}  "
                  f"py={py[name]['status']} cpp={cpp[name]['status']}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
