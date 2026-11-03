#!/usr/bin/env python3
"""PYNQ 板端通用调用模板：身份校验 → 配置 → DMA 往返 → 逐元素比对 → 分段计时 → 运行记录。

只依赖 pynq + numpy。所有偏移、实例名、长度来自契约 JSON，脚本本身不含题目相关常量。

用法（板端）：
  python3 pynq_runner.py contract.json [--input in.bin --expected golden.bin] [--repeat 10] [--out run_record.json]

contract.json 示例：
{
  "bit": "design.bit",
  "pl_clock_mhz": 100.0,                                  # 可选：加载后强制并回读
  "version": {"ip": "my_core", "offset": 8, "expect": 65536},  # 可选但强烈建议
  "params":  [{"ip": "my_core", "offset": 12, "value": 1024}], # 启动前写入
  "start":   {"ip": "my_core", "offset": 0, "value": 1},       # 可选：无 START 的纯流核省略
  "dma": "axi_dma_0",
  "input":  {"file": "kv_in.bin",  "dtype": "uint32"},
  "output": {"count": 1024,        "dtype": "uint32"},
  "expected": "kv_golden.bin",
  "timeout_s": 5.0
}
退出码：0 一致；1 不一致；2 身份/超时/DMA 错误（已执行恢复）。
"""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

import numpy as np


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def wait_idle(ch, timeout_s):
    t_end = time.monotonic() + timeout_s
    while not ch.idle:
        if ch.error:
            raise RuntimeError("DMA error bit set")
        if time.monotonic() > t_end:
            raise TimeoutError("DMA channel not idle before deadline")


def reset_hw(ol, dma):
    """背压下 channel.stop() 可能卡住：直接写 DMACR=0，再 download() 作为 PL 复位屏障。"""
    for ch in (getattr(dma, "sendchannel", None), getattr(dma, "recvchannel", None)):
        try:
            if ch is not None:
                ch._mmio.write(ch._offset, 0)
        except Exception:
            pass
    ol.download()


def ip(ol, name):
    return getattr(ol, name)


def run_once(ol, c, src, dst, timing):
    dma = ip(ol, c["dma"])
    t0 = time.perf_counter_ns()
    for p in c.get("params", []):
        ip(ol, p["ip"]).write(p["offset"], p["value"])
    dma.recvchannel.transfer(dst)                 # 先挂接收
    if "start" in c:
        s = c["start"]
        ip(ol, s["ip"]).write(s["offset"], s["value"])
    dma.sendchannel.transfer(src)                 # transfer 内部 flush
    t1 = time.perf_counter_ns()
    wait_idle(dma.sendchannel, c.get("timeout_s", 5.0))
    wait_idle(dma.recvchannel, c.get("timeout_s", 5.0))
    t2 = time.perf_counter_ns()
    dst.invalidate()                              # 轮询 idle 不会自动 invalidate
    out = np.array(dst, copy=True)
    t3 = time.perf_counter_ns()
    timing.append({"submit_ns": t1 - t0, "wait_ns": t2 - t1, "readback_ns": t3 - t2, "total_ns": t3 - t0})
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("contract")
    ap.add_argument("--input")
    ap.add_argument("--expected")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--out", default="run_record.json")
    a = ap.parse_args()

    base = Path(a.contract).resolve().parent
    c = json.loads(Path(a.contract).read_text(encoding="utf-8"))
    bit = base / c["bit"]
    hwh = bit.with_suffix(".hwh")
    in_path = Path(a.input) if a.input else base / c["input"]["file"]
    exp_path = Path(a.expected) if a.expected else base / c["expected"]

    import pynq
    from pynq import Overlay, allocate

    rec = {"pynq_version": pynq.__version__, "python": sys.executable,
           "bit": str(bit), "bit_sha256": sha256(bit),
           "hwh_sha256": sha256(hwh) if hwh.is_file() else None,
           "input_sha256": sha256(in_path), "expected_sha256": sha256(exp_path),
           "repeat": a.repeat, "status": "invalid", "checks": []}
    if rec["hwh_sha256"] is None:
        rec["checks"].append("missing .hwh next to .bit")
        Path(a.out).write_text(json.dumps(rec, indent=2))
        print("FAIL: missing .hwh"); return 2

    t = time.perf_counter_ns()
    ol = Overlay(str(bit))
    rec["overlay_load_ns"] = time.perf_counter_ns() - t

    if "pl_clock_mhz" in c:
        from pynq import Clocks
        Clocks.fclk0_mhz = float(c["pl_clock_mhz"])
        rec["pl_clock_mhz"] = Clocks.fclk0_mhz
        if abs(rec["pl_clock_mhz"] - c["pl_clock_mhz"]) > 1.0:
            rec["checks"].append(f"fclk0 readback {rec['pl_clock_mhz']} != {c['pl_clock_mhz']}")
    if "version" in c:
        v = c["version"]
        got = ip(ol, v["ip"]).read(v["offset"])
        rec["version_read"] = hex(got)
        if got != v["expect"]:
            rec["checks"].append(f"version {got:#x} != {v['expect']:#x} (stale bitstream or bit/hwh mismatch)")
    if rec["checks"]:
        Path(a.out).write_text(json.dumps(rec, indent=2)); print("FAIL:", rec["checks"]); return 2

    x = np.fromfile(in_path, dtype=c["input"]["dtype"])
    expected = np.fromfile(exp_path, dtype=c["output"]["dtype"])
    n_out = int(c["output"]["count"])
    if expected.size != n_out:
        print(f"FAIL: expected file has {expected.size} elements, contract says {n_out}"); return 2

    t = time.perf_counter_ns()
    src = allocate(shape=x.shape, dtype=x.dtype)
    dst = allocate(shape=(n_out,), dtype=c["output"]["dtype"])
    rec["allocate_ns"] = time.perf_counter_ns() - t
    src[:] = x

    timing, rc = [], 0
    try:
        for _ in range(a.repeat):
            out = run_once(ol, c, src, dst, timing)
            diff = np.flatnonzero(out != expected)
            if diff.size:
                i = int(diff[0])
                rec["checks"].append(f"mismatch {diff.size}/{n_out}, first idx {i}: got {out[i]} exp {expected[i]}")
                rc = 1
                break
        rec["status"] = "passed" if rc == 0 else "failed"
    except (TimeoutError, RuntimeError) as e:
        rec["checks"].append(f"{type(e).__name__}: {e}")
        rec["status"] = "failed"
        rc = 2
        reset_hw(ol, ip(ol, c["dma"]))           # PL 复位之后才释放缓冲
    finally:
        rec["timing"] = timing
        if timing:
            rec["median_total_ns"] = int(np.median([t["total_ns"] for t in timing]))
        del src, dst
        Path(a.out).write_text(json.dumps(rec, indent=2, ensure_ascii=False))

    print(("PASS" if rc == 0 else "FAIL"), f"compared={n_out}", f"runs={len(timing)}",
          f"median_total_us={rec.get('median_total_ns', 0) / 1e3:.1f}", *rec["checks"])
    return rc


if __name__ == "__main__":
    sys.exit(main())
