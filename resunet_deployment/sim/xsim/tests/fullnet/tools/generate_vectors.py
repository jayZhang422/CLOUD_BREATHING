"""Generate the 32x32 vessel/base16 fullnet task table and P16 Golden files.

The descriptors are the only scheduler input.  Every task after the first one
reads the DDR address written by the preceding task; the Golden files are
used only by the XSim scoreboard.
"""
from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[5]
EXPORT = ROOT / "src/params/int8/vessel"
CAPTURE = EXPORT / "golden_synthetic_32x32"
ROM_MAP = ROOT / "src/params/quantized_params_rom_address_map.tsv"
OUT = Path(__file__).resolve().parents[1] / "vectors"


def write_hex(path: Path, data: bytes) -> None:
    path.write_text("".join(f"{b:02x}\n" for b in data), encoding="ascii")


def pack_layout(a: np.ndarray, bits: int, fill: int = 0) -> bytes:
    """[group16][row][col][lane16], little endian lane values."""
    c, h, w = a.shape
    groups = (c + 15) // 16
    padded = np.full((groups * 16, h, w), fill, dtype=a.dtype)
    padded[:c] = a
    packed = padded.reshape(groups, 16, h, w).transpose(0, 2, 3, 1)
    if bits == 8:
        return packed.astype(np.int8, copy=False).tobytes()
    if bits == 16:
        return packed.astype("<i2", copy=False).tobytes()
    if bits == 32:
        return packed.astype("<i4", copy=False).tobytes()
    raise ValueError(bits)


def pack_p4(a: np.ndarray, fill: int = 0) -> bytes:
    """P4 output layout used by the INT16 head (four lanes per word)."""
    c, h, w = a.shape
    groups = (c + 3) // 4
    padded = np.full((groups * 4, h, w), fill, dtype=a.dtype)
    padded[:c] = a
    return padded.reshape(groups, 4, h, w).transpose(0, 2, 3, 1).astype("<i2", copy=False).tobytes()


def descriptor(op: int, run_id: int, *, width: int, height: int, groups: int,
               cin: int = 0, cout: int = 0, base_a: int = 0,
               base_b: int = 0, output: int = 0, mac: int = 0,
               weights: int = 0, params: int = 0, groups_b: int = 0,
               shift: int = 24, lower: int = -128, upper: int = 127,
               flags: int = 0) -> bytes:
    b = bytearray(64)
    b[0:4] = bytes((op, flags, cin & 0xff, cout & 0xff))
    struct.pack_into("<HHH", b, 4, width, height, groups)
    b[10:13] = bytes((shift & 0x3f, lower & 0xff, upper & 0xff))
    struct.pack_into("<H", b, 14, groups_b)
    struct.pack_into("<9I", b, 16, base_a, base_b, output, mac,
                     weights, params, 1, 0, run_id)
    if cin > 255 or cout > 255:
        struct.pack_into("<HH", b, 52, cin, cout)
    return bytes(b)


def main() -> None:
    manifest = json.loads((CAPTURE / "manifest.json").read_text(encoding="utf-8"))
    tensors = manifest["tensors"]
    cache: dict[str, np.ndarray] = {}

    def tensor(name: str) -> np.ndarray:
        if name not in cache:
            info = tensors[name]
            data = (CAPTURE / f"{name}.bin").read_bytes()
            if hashlib.sha256(data).hexdigest() != info["sha256"]:
                raise ValueError(f"Golden SHA256 mismatch: {name}")
            cache[name] = np.frombuffer(data, dtype=np.dtype(info["dtype"]).newbyteorder("<")).reshape(info["shape"])[0]
        return cache[name]

    addresses: dict[str, int] = {}
    for line in ROM_MAP.read_text(encoding="utf-8").splitlines()[1:]:
        model, _kind, name, _start, _words, _bytes, addr = line.split("\t")
        if model == "vessel":
            addresses[name] = int(addr, 16)

    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*"):
        if old.is_dir():
            for p in old.glob("*"):
                p.unlink()
            old.rmdir()
        else:
            old.unlink()

    tasks: list[tuple[str, bytes, bytes]] = []
    task_regions: list[dict[str, object]] = []
    run_id = 0x66000001

    def add(name: str, desc: bytes, expected: bytes, source: str) -> None:
        nonlocal run_id
        folder = OUT / f"{len(tasks):03d}_{name}"
        folder.mkdir()
        write_hex(folder / "descriptor.hex", desc)
        write_hex(folder / "golden.hex", expected)
        task_name = f"{len(tasks):03d}_{name}"
        tasks.append((task_name, desc, expected))
        task_regions.append({"task": task_name, "source": source,
                             "run_id": run_id, "result_bytes": len(expected),
                             "output_base": struct.unpack_from("<I", desc, 24)[0],
                             "output_end": struct.unpack_from("<I", desc, 24)[0] + len(expected)})
        run_id += 1

    def stage_bytes(name: str, raw: bool = False) -> bytes:
        return pack_layout(tensor(name), 32 if raw else 8)

    def pw(name: str, cin: int, cout: int, width: int, height: int,
           src: int, dst: int, raw: bool = False, int16: bool = False) -> None:
        flags = (4 if raw else 0) | (8 if int16 else 0) | (16 if raw else 0)
        expected_name = f"{name}.mac" if raw else name
        expected = stage_bytes(expected_name, raw=raw) if not int16 else pack_layout(tensor(expected_name), 16)
        add(name, descriptor(1, run_id, width=width, height=height,
                             groups=(cout + 15) // 16, cin=cin, cout=cout,
                             base_a=src, output=dst,
                             weights=addresses[f"{name}.weight.i8.bin"],
                             params=addresses[f"{name}.params"], flags=flags),
            expected, expected_name)

    def dw(name: str, channels: int, width: int, height: int, src: int, dst: int) -> None:
        expected = stage_bytes(f"{name}.mac", raw=True)
        add(name, descriptor(8 if name.endswith("dw3") else 9, run_id,
                             width=width, height=height, groups=channels // 16,
                             cin=channels, cout=channels, base_a=src, output=dst,
                             weights=addresses[f"{name}.weight.i8.bin"]), expected, f"{name}.mac")

    def add_op(name: str, channels: int, width: int, height: int,
               src_a: int, src_b: int, dst: int) -> None:
        expected = pack_layout(tensor(name), 8)
        add(name, descriptor(6, run_id, width=width, height=height,
                             groups=channels // 16, cin=channels, cout=channels,
                             base_a=src_a, base_b=src_b, output=dst,
                             params=addresses[f"{name}.params"], lower=0, upper=127),
            expected, name)

    def block(prefix: str, cin: int, cout: int, width: int, height: int,
              src: int, out: int, raw_base: int) -> None:
        expand = raw_base
        dw3_out, dw5_out = raw_base + 0x10000, raw_base + 0x20000
        mix, project, skip = raw_base + 0x30000, raw_base + 0x40000, raw_base + 0x50000
        pw(f"{prefix}.expand", cin, cout, width, height, src, expand)
        dw(f"{prefix}.dw3", cout, width, height, expand, dw3_out)
        dw(f"{prefix}.dw5", cout, width, height, expand, dw5_out)
        add_op(f"{prefix}.mix", cout, width, height, dw3_out, dw5_out, mix)
        pw(f"{prefix}.project", cout, cout, width, height, mix, project, raw=True)
        pw(f"{prefix}.skip", cin, cout, width, height, src, skip, raw=True)
        add_op(f"{prefix}.out", cout, width, height, project, skip, out)

    # Address map: each output and raw workspace is disjoint; encoder outputs
    # are retained at 0x02000000/0x02100000/0x02200000 for decoder skips.
    input_addr = 0x01000000
    e1, e2, e3, mid = 0x02000000, 0x02100000, 0x02200000, 0x02300000
    pool1, pool2, pool3 = 0x02400000, 0x02500000, 0x02600000
    block("e1", 3, 16, 32, 32, input_addr, e1, 0x03000000)
    add("pool1", descriptor(2, run_id, width=32, height=32, groups=1,
                             cin=16, cout=16, base_a=e1, output=pool1),
        pack_layout(np.maximum.reduce([tensor("e1.out")[:, 0::2, 0::2],
                                       tensor("e1.out")[:, 1::2, 0::2],
                                       tensor("e1.out")[:, 0::2, 1::2],
                                       tensor("e1.out")[:, 1::2, 1::2]]), 8), "pool1")
    block("e2", 16, 32, 16, 16, pool1, e2, 0x05000000)
    add("pool2", descriptor(2, run_id, width=16, height=16, groups=2,
                             cin=32, cout=32, base_a=e2, output=pool2),
        pack_layout(np.maximum.reduce([tensor("e2.out")[:, 0::2, 0::2],
                                       tensor("e2.out")[:, 1::2, 0::2],
                                       tensor("e2.out")[:, 0::2, 1::2],
                                       tensor("e2.out")[:, 1::2, 1::2]]), 8), "pool2")
    block("e3", 32, 64, 8, 8, pool2, e3, 0x06000000)
    add("pool3", descriptor(2, run_id, width=8, height=8, groups=4,
                             cin=64, cout=64, base_a=e3, output=pool3),
        pack_layout(np.maximum.reduce([tensor("e3.out")[:, 0::2, 0::2],
                                       tensor("e3.out")[:, 1::2, 0::2],
                                       tensor("e3.out")[:, 0::2, 1::2],
                                       tensor("e3.out")[:, 1::2, 1::2]]), 8), "pool3")
    block("mid", 64, 128, 4, 4, pool3, mid, 0x07000000)

    def up_concat(prefix: str, src_name: str, skip_name: str, src: int,
                  skip: int, up_dst: int, cat_dst: int, width: int, height: int,
                  src_channels: int, skip_channels: int) -> None:
        up = tensor(src_name).repeat(2, axis=1).repeat(2, axis=2)
        add(f"{prefix}.up", descriptor(10, run_id, width=width // 2, height=height // 2,
                                        groups=src_channels // 16, base_a=src, output=up_dst),
            pack_layout(up, 8), f"{src_name}.nearest2")
        cat = np.concatenate((up, tensor(skip_name)), axis=0)
        add(f"{prefix}.concat", descriptor(5, run_id, width=width, height=height,
                                             groups=src_channels // 16, groups_b=skip_channels // 16,
                                             base_a=up_dst, base_b=skip, output=cat_dst),
            pack_layout(cat, 8), f"{prefix}.concat")

    d3_cat = 0x08100000
    up_concat("d3", "mid.out", "e3.out", mid, e3, 0x08000000, d3_cat, 8, 8, 128, 64)
    d3_out = 0x08200000
    block("d3", 192, 64, 8, 8, d3_cat, d3_out, 0x08300000)
    d2_cat = 0x08600000
    up_concat("d2", "d3.out", "e2.out", d3_out, e2, 0x08500000, d2_cat, 16, 16, 64, 32)
    d2_out = 0x08700000
    block("d2", 96, 32, 16, 16, d2_cat, d2_out, 0x08800000)
    d1_cat = 0x08c00000
    up_concat("d1", "d2.out", "e1.out", d2_out, e1, 0x08b00000, d1_cat, 32, 32, 32, 16)
    d1_out = 0x08e00000
    block("d1", 48, 16, 32, 32, d1_cat, d1_out, 0x09000000)
    head_expected = pack_p4(tensor("head"), fill=0)
    add("head", descriptor(1, run_id, width=32, height=32, groups=1,
                            cin=16, cout=2, base_a=d1_out, output=0x07000000,
                            weights=addresses["head.weight.i8.bin"],
                            params=addresses["head.params"], flags=8),
        head_expected, "head")

    input_data = pack_layout(tensor("input"), 8, fill=-128)
    write_hex(OUT / "input.hex", input_data)
    (OUT / "uploads.txt").write_text(f"{input_addr:08x} {len(input_data)} input.hex\n", encoding="ascii")
    lines = []
    for name, desc, expected in tasks:
        folder = f"{name}/"
        lines.append(f"{name} {len(expected)} {folder}descriptor.hex {folder}golden.hex\n")
    (OUT / "tasks.txt").write_text("".join(lines), encoding="ascii")
    (OUT / "task_manifest.json").write_text(json.dumps({
        "model": "vessel", "base": 16, "shape": [1, 3, 32, 32],
        "tasks": task_regions, "task_count": len(tasks),
        "input_bytes": len(input_data), "input_address": input_addr,
        "golden_manifest": str(CAPTURE.relative_to(ROOT)),
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"[FULLNET VECTORS PASSED] tasks={len(tasks)} input_bytes={len(input_data)}")


if __name__ == "__main__":
    main()
