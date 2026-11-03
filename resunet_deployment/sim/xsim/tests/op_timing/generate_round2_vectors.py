"""第二轮小向量：读取器缓存/切片边界，以及冻结PW多块与尾块回归。"""
from pathlib import Path
import importlib.util
import json
import struct

ROOT = Path(__file__).resolve().parent
VECTORS = ROOT / "vectors"
ROM = ROOT.parent / "op_rom"


def memory_byte(address):
    return (address ^ (address >> 8) ^ (address >> 16) ^ (address >> 24)) & 255


def main():
    cases = []
    for slices, center in ((1, 0), (2, 0), (2, 1), (5, 2), (5, 4), (1024, 1023)):
        for i, pixel in enumerate((0, 1, 15, 16, 30, 31, 32, 33, 262142, 262143)):
            cases.append((2, 0x10000000, pixel, slices, center, i == 0, False))
    for mode in (0, 1):
        for i in range(16):
            cases.append((mode, 0x10004000 + i * (16 if mode == 0 else 64), 0, 1, 0, True, i % 5 == 0))
    # 错误响应不得建立cache；随后重试应重新读取。
    cases += [(2, 0x10000000, 17, 3, 1, True, True),
              (2, 0x10000000, 17, 3, 1, False, False),
              (2, 0x10000000, 18, 3, 1, False, False)]
    cache = [None] * 3
    stimulus, golden = [], []
    total_beats = 0
    for mode, base, pixel, slices, center, clear, error in cases:
        if clear:
            cache = [None] * 3
        data = bytearray(64)
        beats = 0
        for part in range((1, 2, 3)[mode]):
            z = max(0, min(slices - 1, center + part - 1))
            address = base + (part * 32 if mode == 1 else z * 262144 + pixel if mode == 2 else 0)
            aligned = address & ~31
            hit = mode == 2 and cache[part] == aligned
            if not hit:
                beats += 1
                if mode == 2 and not error:
                    cache[part] = aligned
            if mode == 2:
                data[part] = memory_byte(address)
            else:
                start = part * 32 if mode == 1 else 0
                size = 32 if mode == 1 else 16
                for b in range(size):
                    data[start + b] = memory_byte(address + b)
        packed = mode | (base << 2) | (pixel << 33) | (slices << 65) | (center << 97)
        packed |= int(clear) << 129 | int(error) << 130
        stimulus.append(f"{packed:033x}\n")
        result = int.from_bytes(data, "little") | (int(error and beats > 0) << 512) | (beats << 513)
        golden.append(f"{result:131x}\n")
        total_beats += beats
    (VECTORS / "reader_stimulus.hex").write_text("".join(stimulus), encoding="ascii")
    (VECTORS / "reader_golden.hex").write_text("".join(golden), encoding="ascii")
    (ROOT / "reader_counts.svh").write_text(f"`define READER_CASES {len(cases)}\n", encoding="ascii")

    spec = importlib.util.spec_from_file_location("fast_vectors", ROM / "generate_fast_vectors.py")
    fast = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fast)
    lines = (ROM / "vectors/cases_fast.txt").read_text().splitlines()
    sizes = {line.split()[0]: list(map(int, line.split()[1:]))
             for line in (ROM / "vectors/cases.txt").read_text().splitlines()}
    for name, size in (("tumor_e1", 10), ("pool_from_tumor_pw", 10),
                       ("concat_pool", 5), ("pw_from_concat_rom", 5)):
        source = ROM / "vectors" / name
        target = ROM / "vectors" / (name + "_round2")
        target.mkdir(exist_ok=True)
        desc = bytearray(fast.read_hex(source / "descriptor.hex"))
        width, height = struct.unpack_from("<HH", desc, 4)
        struct.pack_into("<HH", desc, 4, size, size)
        fast.write_hex(target / "descriptor.hex", desc)
        uploads = []
        for line in (source / "uploads.txt").read_text().splitlines():
            if not line.strip():
                continue
            address, _, filename = line.split()
            data = fast.crop(fast.read_hex(ROM / "vectors" / filename), width, height, size, size)
            fast.write_hex(target / Path(filename).name, data)
            uploads.append(f"{address} {len(data)} {target.name}/{Path(filename).name}\n")
        (target / "uploads.txt").write_text("".join(uploads), encoding="ascii")
        out_w, out_h, out_size = (width // 2, height // 2, size // 2) if desc[0] == 2 else (width, height, size)
        new_sizes = []
        for filename, old_size in zip(("golden.hex", "mac.hex"), sizes[name]):
            data = fast.crop(fast.read_hex(source / filename), out_w, out_h, out_size, out_size) if old_size else b""
            if data:
                fast.write_hex(target / filename, data)
            new_sizes.append(len(data))
        lines.append(f"{target.name} {new_sizes[0]} {new_sizes[1]}")
    (ROM / "vectors/cases_round2.txt").write_text("\n".join(lines) + "\n", encoding="ascii")
    (ROOT / "results/round2_20261014/vector_manifest.json").write_text(
        json.dumps({"reader_cases": len(cases), "reader_memory_beats": total_beats,
                    "joint_cases": len(lines), "new_pw_pixels": [100, 25],
                    "golden": "crop existing frozen vectors; original files unchanged"}, indent=2), encoding="utf-8")
    print(f"reader_cases={len(cases)} memory_beats={total_beats} joint_cases={len(lines)}")


if __name__ == "__main__":
    main()
