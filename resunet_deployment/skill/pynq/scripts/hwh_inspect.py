#!/usr/bin/env python3
"""离线解析 Vivado 导出的 .hwh，生成 PYNQ 上板前需要核对的接口清单。

不依赖 pynq，可在工作站运行。输出：
  - bit/hwh 的 SHA256 与 HWH 时间戳、Vivado 版本、器件
  - PS 可见的 AXI-Lite 地址映射（实例、基地址、范围）
  - 每个 axi_dma 的单次传输上限、数据位宽、DRE、SG 配置
  - PL 时钟（fclk/pl_clk）请求频率
  - HWH 中是否带寄存器描述（决定 register_map 能否使用）
可选 --emit-stub 生成主机侧 MMIO 调用骨架。

用法：
  python hwh_inspect.py design.hwh [--bit design.bit] [--json out.json]
                        [--regs regs.json] [--emit-stub driver_stub.py]
regs.json（可选，自定义 RTL 核的寄存器契约，HWH 里没有时使用）：
  {"<instance>": {"CTRL": 0, "STATUS": 4, "VERSION": 8}}
"""
import argparse
import hashlib
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def params_of(module):
    node = module.find("PARAMETERS")
    if node is None:
        return {}
    return {p.get("NAME"): p.get("VALUE") for p in node.findall("PARAMETER")}


def find_ps(root):
    for m in root.iter("MODULE"):
        if m.get("MODTYPE") in ("processing_system7", "zynq_ultra_ps_e", "versal_cips"):
            return m
    return None


def address_map(ps):
    """PS 主口上 MEMTYPE=REGISTER 的地址段，即 Python MMIO 能访问的 IP。"""
    rows, seen = [], set()
    for mr in ps.iter("MEMRANGE"):
        if mr.get("MEMTYPE") != "REGISTER":
            continue
        key = (mr.get("INSTANCE"), mr.get("BASEVALUE"))
        if key in seen:
            continue
        seen.add(key)
        base, high = int(mr.get("BASEVALUE"), 16), int(mr.get("HIGHVALUE"), 16)
        rows.append({"instance": mr.get("INSTANCE"), "base": hex(base),
                     "range": high - base + 1, "master": mr.get("MASTERBUSINTERFACE"),
                     "slave_if": mr.get("SLAVEBUSINTERFACE")})
    return sorted(rows, key=lambda r: int(r["base"], 16))


def pl_clocks(ps):
    """PL 时钟请求值。MPSoC: PSU__CRL_APB__PLn_REF_CTRL__*FREQMHZ；Zynq-7000: PCW_*FPGAn_PERIPHERAL_FREQMHZ。"""
    out = {}
    for k, v in params_of(ps).items():
        u = k.upper()
        if "FREQMHZ" in u and ("_PL" in u and "REF_CTRL" in u or "FPGA" in u and "PERIPHERAL" in u):
            out[k] = v
    return out


def dma_info(root):
    rows = []
    for m in root.iter("MODULE"):
        if m.get("MODTYPE") != "axi_dma":
            continue
        p = params_of(m)
        width = int(p.get("C_SG_LENGTH_WIDTH", "14"))
        rows.append({
            "instance": m.get("INSTANCE"),
            "vlnv": m.get("VLNV"),
            "max_bytes_per_transfer": (1 << width) - 1,   # 与 pynq DMA.buffer_max_size 一致
            "sg_length_width": width,
            "scatter_gather": p.get("C_INCLUDE_SG") == "1",
            "mm2s": p.get("C_INCLUDE_MM2S") == "1",
            "s2mm": p.get("C_INCLUDE_S2MM") == "1",
            "mm2s_data_width": p.get("C_M_AXI_MM2S_DATA_WIDTH"),
            "s2mm_data_width": p.get("C_M_AXI_S2MM_DATA_WIDTH"),
            "mm2s_dre": p.get("C_INCLUDE_MM2S_DRE") == "1",
            "s2mm_dre": p.get("C_INCLUDE_S2MM_DRE") == "1",
        })
    return rows


def register_coverage(root, instances):
    """HWH 里带 <REGISTER> 的实例才有 register_map；module_ref 自定义核通常没有。"""
    out = {}
    for m in root.iter("MODULE"):
        inst = m.get("INSTANCE")
        if inst in instances:
            regs = [r.get("NAME") for r in m.iter("REGISTER")]
            out[inst] = {"vlnv": m.get("VLNV"), "register_count": len(regs),
                         "register_map": bool(regs)}
    return out


def emit_stub(path, report, regs):
    lines = [
        '"""由 hwh_inspect.py 生成的主机侧骨架。偏移来自 HWH/regs.json，不要手改常量，改契约后重新生成。"""',
        "from pynq import Overlay, MMIO, allocate",
        "",
        f"BIT_SHA256 = {report.get('bit_sha256')!r}",
        f"HWH_SHA256 = {report['hwh_sha256']!r}",
        "",
    ]
    for row in report["address_map"]:
        name = row["instance"].upper().replace("/", "_")
        lines.append(f"{name}_BASE = {row['base']}  # range {row['range']}")
        for reg, off in regs.get(row["instance"], {}).items():
            lines.append(f"{name}_{reg.upper()} = {int(off):#06x}")
    lines.append("")
    for d in report["dma"]:
        lines.append(f"{d['instance'].upper()}_MAX_BYTES = {d['max_bytes_per_transfer']}")
    lines += ["", "", "def open_overlay(bit_path):",
              "    ol = Overlay(str(bit_path))  # 同名 .hwh 必须与 .bit 同一次构建",
              "    return ol", ""]
    Path(path).write_text("\n".join(lines), encoding="utf-8")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # Windows 控制台默认 GBK
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hwh")
    ap.add_argument("--bit")
    ap.add_argument("--json")
    ap.add_argument("--regs")
    ap.add_argument("--emit-stub")
    a = ap.parse_args()

    hwh = Path(a.hwh)
    bit = Path(a.bit) if a.bit else hwh.with_suffix(".bit")
    root = ET.parse(hwh).getroot()
    ps = find_ps(root)
    if ps is None:
        sys.exit("ERROR: HWH 中没有 PS 模块（processing_system7/zynq_ultra_ps_e/versal_cips）")
    sysinfo = root.find("SYSTEMINFO")
    report = {
        "hwh": str(hwh), "hwh_sha256": sha256(hwh),
        "bit": str(bit) if bit.is_file() else None,
        "bit_sha256": sha256(bit) if bit.is_file() else None,
        "timestamp": root.get("TIMESTAMP"), "vivado": root.get("VIVADOVERSION"),
        "device": dict(sysinfo.attrib) if sysinfo is not None else {},
        "pl_clocks": pl_clocks(ps),
        "address_map": address_map(ps),
        "dma": dma_info(root),
    }
    report["register_coverage"] = register_coverage(root, {r["instance"] for r in report["address_map"]})
    regs = json.loads(Path(a.regs).read_text(encoding="utf-8")) if a.regs else {}

    print(f"HWH  {report['hwh_sha256'][:16]}  {report['timestamp']}  Vivado {report['vivado']}")
    print(f"BIT  {(report['bit_sha256'] or 'MISSING')[:16]}  {report['bit']}")
    if not report["bit"]:
        print("WARN 未找到同名 .bit：PYNQ 要求 .bit 与 .hwh 同名同目录")
    print("PL clocks:", report["pl_clocks"] or "未找到")
    print(f"{'instance':28s} {'base':>12s} {'range':>8s}  register_map")
    for r in report["address_map"]:
        cov = report["register_coverage"].get(r["instance"], {})
        flag = "yes" if cov.get("register_map") else ("regs.json" if r["instance"] in regs else "NO")
        print(f"{r['instance']:28s} {r['base']:>12s} {r['range']:>8d}  {flag}")
    for d in report["dma"]:
        print(f"DMA {d['instance']}: max {d['max_bytes_per_transfer']} B/transfer, "
              f"SG={d['scatter_gather']}, width mm2s/s2mm={d['mm2s_data_width']}/{d['s2mm_data_width']}, "
              f"DRE={d['mm2s_dre']}/{d['s2mm_dre']}")
    if a.json:
        Path(a.json).write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    if a.emit_stub:
        emit_stub(a.emit_stub, report, regs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
