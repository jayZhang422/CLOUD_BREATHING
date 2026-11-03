"""第一轮配置检查/写回回归：Python整数规范生成输入与Golden，固定种子。"""
from pathlib import Path
import hashlib
import json
import random
import struct

ROOT = Path(__file__).resolve().parent
VECTORS = ROOT / "vectors"
RNG = random.Random(20261014)


def descriptor(op=1, flags=0, width=4, height=4, groups=1, cin=16, cout=16, gb=1):
    d = bytearray(64)
    d[0:4] = bytes((op, flags, min(cin, 255), min(cout, 255)))
    struct.pack_into("<HHH", d, 4, width, height, groups)
    d[10:13] = bytes((24, 0, 127))
    struct.pack_into("<H", d, 14, gb)
    for offset, value in ((16, 0x10000000), (20, 0x12000000), (24, 0x18000000),
                          (28, 0x19000000), (32, 0x100000), (36, 0x200000), (40, 1)):
        struct.pack_into("<I", d, offset, value)
    struct.pack_into("<HH", d, 52, cin, cout)
    return d


def reference(d):
    u16 = lambda o: struct.unpack_from("<H", d, o)[0]
    u32 = lambda o: struct.unpack_from("<I", d, o)[0]
    op, flags = d[0], d[1]
    width, height, groups, gb = u16(4), u16(6), u16(8), u16(14)
    cin, cout = u16(52) or d[2], u16(54) or d[3]
    a, b, q, m, w, par = (u32(o) for o in (16, 20, 24, 28, 32, 36))
    p = width * height
    ig, og4, og16 = (cin + 15) // 16, (cout + 3) // 4, (cout + 15) // 16
    an, bn, qn, mn, wn, pn = p * groups * 16, 0, p * groups * 16, 0, 0, 0
    ok = 1 <= op <= 7 and 1 <= width <= 512 and 1 <= height <= 512 and 1 <= groups <= 32
    ok &= a % 16 == 0 and q % 32 == 0 and flags & 0xf0 == 0
    if op == 1:
        ok &= 1 <= cin <= 768 and 1 <= cout <= 512 and d[10] <= 62
        ok &= flags & 12 != 12 and w % 64 == 0 and par % 64 == 0
        an, qn = p * ig * 16, p * og16 * 16
        if flags & 8:
            qn = p * og4 * 8
        if flags & 4:
            qn = p * og4 * 16
        if flags & 2 and not flags & 4:
            mn = p * og4 * 16
        wn, pn = og4 * ig * 64, og4 * 64
        if flags & 1:
            an = u32(40) * 262144
            ok &= cin == 3 and cout in (16, 64) and p == 262144 and a % 262144 == 0
            ok &= 1 <= u32(40) <= 1024 and u32(44) < u32(40)
    elif op == 2:
        ok &= width >= 2 and height >= 2
        qn = (width // 2) * (height // 2) * groups * 16
    elif op == 3:
        qn = an * 9
    elif op == 4:
        qn = an * 25
    elif op == 5:
        bn = p * gb * 16
        qn = an + bn
        ok &= 1 <= gb <= 32 and b % 16 == 0
    elif op == 6:
        an *= 4
        bn, pn = an, groups * 256
        lo, hi = struct.unpack_from("bb", d, 11)
        ok &= a % 64 == 0 and b % 64 == 0 and par % 64 == 0 and d[10] <= 63 and lo <= hi
    if op != 1:
        ok &= flags == 0
    if op == 7:
        ok &= groups == 1
    fits = lambda address, size: size != 0 and address + size <= 0x20000000
    overlap = lambda x, n, y, k: n != 0 and k != 0 and x < y + k and y < x + n
    ok &= fits(a, an) and fits(q, qn)
    ok &= not any(overlap(q, qn, address, size) for address, size in ((a, an), (b, bn), (w, wn), (par, pn)))
    if bn:
        ok &= fits(b, bn)
    if wn:
        ok &= w >= 0x100000 and w + wn <= 0x300000
    if pn:
        ok &= par >= 0x100000 and par + pn <= 0x300000
    if mn:
        ok &= m % 32 == 0 and fits(m, mn)
        ok &= not any(overlap(m, mn, address, size) for address, size in ((a, an), (b, bn), (q, qn), (w, wn), (par, pn)))
    values = [qn, mn, p, p * groups, og4 * ig if op == 1 else 0, og4, p * gb]
    packed = int(bool(ok))
    for value in values:
        packed = (packed << 32) | (value & 0xffffffff)
    return packed


def write_hex(name, values, digits):
    (VECTORS / name).write_text("".join(f"{v:0{digits}x}\n" for v in values), encoding="ascii")


def main():
    VECTORS.mkdir(exist_ok=True)
    cases = []
    for op in range(1, 8):
        for width, height, groups in ((4, 4, 1), (3, 5, 2), (512, 512, 32), (512, 512, 1)):
            cases.append(descriptor(op, width=width, height=height, groups=groups))
    for cin, cout in ((3, 1), (16, 5), (256, 512), (768, 256), (768, 512)):
        for flags in (0, 2, 4, 8, 10):
            cases.append(descriptor(flags=flags, cin=cin, cout=cout))
    cases += [descriptor(flags=3, width=512, height=512, cin=3, cout=c, groups=1) for c in (16, 64)]
    legacy = descriptor(cin=3, cout=64)
    legacy[52:56] = bytes(4)
    cases.append(legacy)
    # 检查零值、16bit最大值、地址溢出、ROM上下界及所有重叠方向。
    for original in list(cases[:12]) + [descriptor(flags=2), descriptor(6)]:
        for offset, values, fmt in ((4, (0, 513, 65535), "<H"), (6, (0, 513, 65535), "<H"),
                                    (8, (0, 33, 65535), "<H"), (52, (0, 769, 65535), "<H"),
                                    (54, (0, 513, 65535), "<H"), (16, (0x1ffffff0, 0xfffffff0), "<I"),
                                    (24, (0x10000000, 0x100000, 0x200000, 0x1fffffe0, 0xffffffe0), "<I"),
                                    (28, (0x10000000, 0x18000000, 0x100000, 0xffffffe0), "<I"),
                                    (32, (0xfffc0, 0x2fffc0, 0xffffffc0), "<I"),
                                    (36, (0xfffc0, 0x2fffc0, 0xffffffc0), "<I")):
            for value in values:
                d = original.copy()
                struct.pack_into(fmt, d, offset, value)
                cases.append(d)
    for _ in range(500):
        op = RNG.randrange(1, 8)
        d = descriptor(op, width=RNG.choice((1, 2, 3, 31, 32, 511, 512)),
                       height=RNG.choice((1, 2, 5, 31, 512)), groups=RNG.choice((1, 2, 31, 32)),
                       cin=RNG.choice((1, 3, 16, 64, 256, 768)), cout=RNG.choice((1, 5, 16, 64, 256, 512)),
                       gb=RNG.choice((1, 2, 31, 32)))
        if op == 1:
            d[1] = RNG.choice((0, 2, 4, 8, 10))
        if RNG.randrange(2):
            d[RNG.randrange(64)] = RNG.randrange(256)
        cases.append(d)
    write_hex("descriptors.hex", (int.from_bytes(d, "little") for d in cases), 128)
    expected = [reference(d) for d in cases]
    write_hex("descriptor_golden.hex", expected, 57)

    lengths = (1, 4, 8, 16, 31, 32, 33, 63, 64, 65, 143, 144, 145, 399, 400)
    writes = [(offset, length) for offset in range(32) for length in lengths]
    writes += [(RNG.randrange(32), RNG.randrange(1, 401)) for _ in range(128)]
    stimuli, golden = [], []
    for case, (offset, length) in enumerate(writes):
        address = 0x10000 + case * 1024 + offset
        data = bytes(RNG.randrange(256) for _ in range(400))
        # error位只影响最终状态，全部写拍仍须排空。
        error = int(case % 17 == 0)
        stimuli.append((error << 3240) | (length << 3231) | (address << 3200) | int.from_bytes(data, "little"))
        consumed = 0
        while consumed < length:
            at = address + consumed
            count = min(32 - at % 32, length - consumed)
            payload = bytes(at % 32) + data[consumed:consumed + count] + bytes(32 - at % 32 - count)
            mask = ((1 << count) - 1) << (at % 32)
            golden.append(((at & ~31) << 288) | (mask << 256) | int.from_bytes(payload, "little"))
            consumed += count
    write_hex("writer_stimulus.hex", stimuli, 811)
    write_hex("writer_golden.hex", golden, 80)
    header = f"`define DESCRIPTOR_CASES {len(cases)}\n`define WRITER_CASES {len(writes)}\n`define WRITER_BEATS {len(golden)}\n"
    (ROOT / "vector_counts.svh").write_text(header, encoding="ascii")
    manifest = {"seed": 20261014, "descriptor_cases": len(cases), "valid_descriptors": sum(v >> 224 for v in expected),
                "writer_cases": len(writes), "writer_beats": len(golden), "offsets": 32,
                "sha256": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in VECTORS.glob("*.hex")}}
    (ROOT / "vector_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({k: v for k, v in manifest.items() if k != "sha256"}))


if __name__ == "__main__":
    main()
