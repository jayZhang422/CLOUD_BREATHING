#!/usr/bin/env python3
"""Generate small, independent byte-exact vectors for the operator-service joint test."""
import argparse
import struct
from pathlib import Path


def pad32(data):
    return data + bytes((-len(data)) % 32)


def write_case(root, name, op, width, height, groups, golden, base_a, base_b=0,
               out_base=0, cin=0, cout=0, groups_b=0, shift=0, uploads=(),
               coefficients=(), weight_base=0, param_base=0, mac_base=0, run_id=0):
    case = root / name
    case.mkdir(parents=True, exist_ok=True)
    desc = bytearray(64)
    desc[0:4] = bytes((op, 0, cin & 0xff, cout & 0xff))
    struct.pack_into("<HHH", desc, 4, width, height, groups)
    desc[10] = shift
    if op == 6:
        desc[11:13] = bytes((0x80, 0x7f))
    struct.pack_into("<H", desc, 14, groups_b)
    struct.pack_into("<IIIIII", desc, 16, base_a, base_b, out_base,
                     mac_base, weight_base, param_base)
    struct.pack_into("<I", desc, 48, run_id)
    if cin > 255 or cout > 255:
        struct.pack_into("<HH", desc, 52, cin, cout)
    (case / "descriptor.bin").write_bytes(desc)
    (case / "golden.bin").write_bytes(golden)
    lines = []
    for address, filename, data in uploads:
        (case / filename).write_bytes(pad32(data))
        lines.append(f"0x{address:08x}\t{filename}\n")
    (case / "uploads.tsv").write_text("".join(lines), encoding="ascii")
    coeff_lines = []
    for address, filename, data in coefficients:
        (case / filename).write_bytes(pad32(data))
        coeff_lines.append(f"0x{address:08x}\t{filename}\n")
    (case / "coeffs.tsv").write_text("".join(coeff_lines), encoding="ascii")


def rne(value, shift):
    if shift == 0:
        return value
    den = 1 << shift
    q, rem = divmod(value, den)
    if 2 * rem > den or (2 * rem == den and q & 1):
        q += 1
    return q


def make_pw(cin, cout, features, salt):
    pixels = len(features)
    weights = [[((o * 3 + i * 2 + salt) % 3) - 1 for i in range(cin)] for o in range(cout)]
    # The engine addresses the input as [input-group][pixel][16 lanes].
    # Keeping this group-major here is important for Cin > 16; an interleaved
    # pixel-major upload would make the second input group read the wrong data.
    input_bytes = bytearray()
    for ig in range((cin + 15) // 16):
        for pixel in features:
            for lane in range(16):
                i = ig * 16 + lane
                input_bytes.append(int(pixel[i]) & 0xff if i < cin else 0x6d)
    weight_bytes = bytearray()
    for og in range((cout + 3) // 4):
        for ig in range((cin + 15) // 16):
            for pe in range(4):
                o = og * 4 + pe
                for lane in range(16):
                    i = ig * 16 + lane
                    v = weights[o][i] if o < cout and i < cin else 0x65
                    weight_bytes.append(v & 0xff)
    params = bytearray()
    for og in range((cout + 3) // 4):
        for pe in range(4):
            o = og * 4 + pe
            params.extend(struct.pack("<iqhh", 1 if o < cout else 0, 0, -128, 127))
    # The service writes four output channels per beat.  For Cout > 16 the
    # writer advances a 16-channel output block before advancing the pixel;
    # keep the Golden in that same ROM/DDR-visible order.
    out = bytearray()
    for block in range((cout + 15) // 16):
        for pixel in features:
            for lane in range(16):
                o = block * 16 + lane
                if o < cout:
                    acc = sum(int(pixel[i]) * weights[o][i] for i in range(cin))
                    out.append(max(-128, min(127, acc)) & 0xff)
                else:
                    out.append(0)
    assert len(input_bytes) == pixels * ((cin + 15) // 16) * 16
    return bytes(input_bytes), bytes(weight_bytes), bytes(params), bytes(out)


def line_windows(image, width, height, groups, k):
    out = bytearray()
    pad = k // 2
    for g in range(groups):
        for y in range(height):
            for x in range(width):
                for ky in range(k):
                    for kx in range(k):
                        sy, sx = y + ky - pad, x + kx - pad
                        if 0 <= sy < height and 0 <= sx < width:
                            at = ((g * height + sy) * width + sx) * 16
                            out.extend(image[at:at + 16])
                        else:
                            out.extend(bytes(16))
    return bytes(out)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    root = parser.parse_args().out
    root.mkdir(parents=True, exist_ok=True)
    names = []

    # A real data dependency: synthetic 1x1 PW output is consumed by MaxPool.
    features = [[((p * 5 + c * 3) % 17) - 8 for c in range(3)] for p in range(16)]
    in0, w0, p0, pw0 = make_pw(3, 16, features, 0)
    write_case(root, "pw_seed", 1, 4, 4, 1, pw0, 0x03000000,
               out_base=0x06000000, cin=3, cout=16,
               weight_base=0x00100000, param_base=0x00180000, run_id=0x1001,
               uploads=((0x03000000, "input.bin", in0),),
               coefficients=((0x00100000, "weights.bin", w0),
                             (0x00180000, "params.bin", p0)))
    names.append("pw_seed")

    pooled = bytearray()
    for y in range(2):
        for x in range(2):
            for c in range(16):
                pooled.append(max((pw0[(2*y+dy)*4*16 + (2*x+dx)*16 + c] if pw0[(2*y+dy)*4*16 + (2*x+dx)*16 + c] < 128 else pw0[(2*y+dy)*4*16 + (2*x+dx)*16 + c]-256)
                                  for dy in range(2) for dx in range(2)) & 0xff)
    write_case(root, "pool_from_pw", 2, 4, 4, 1, bytes(pooled), 0x06000000,
               out_base=0x06100000, run_id=0x1002)
    names.append("pool_from_pw")

    # A second P16 feature joins the pooled feature; the concatenated P32 tensor
    # then becomes a two-group PW input.
    concat_b = bytes((((p * 11 + lane * 13) % 255) - 127) & 0xff for p in range(4) for lane in range(16))
    concat_golden = bytes(pooled) + concat_b
    write_case(root, "concat_chain", 5, 2, 2, 1, concat_golden, 0x06100000,
               base_b=0x04000000, out_base=0x06200000, groups_b=1, run_id=0x1003,
               uploads=((0x04000000, "feature_b.bin", concat_b),))
    names.append("concat_chain")

    concat_features = []
    for p in range(4):
        concat_features.append([
            (concat_golden[p * 16 + lane] - 256
             if concat_golden[p * 16 + lane] >= 128 else concat_golden[p * 16 + lane])
            for lane in range(16)
        ] + [
            (concat_golden[64 + p * 16 + lane] - 256
             if concat_golden[64 + p * 16 + lane] >= 128
             else concat_golden[64 + p * 16 + lane])
            for lane in range(16)
        ])
    in1, w1, p1, pw1 = make_pw(32, 16, concat_features, 1)
    write_case(root, "pw_after_concat", 1, 2, 2, 1, pw1, 0x06200000,
               out_base=0x06300000, cin=32, cout=16,
               weight_base=0x00200000, param_base=0x00280000, run_id=0x1004,
               coefficients=((0x00200000, "weights.bin", w1),
                             (0x00280000, "params.bin", p1)))
    names.append("pw_after_concat")

    # One pixel from the real frozen tumor d3.expand layer verifies the actual
    # 768x256 weights/quantization constants and matches the exported Golden.
    export = (Path(__file__).resolve().parents[4] / "src" / "params" / "int8" / "tumor")
    frozen = export / "golden_synthetic_32x32"
    manifest = __import__("json").loads((frozen / "manifest.json").read_text(encoding="utf-8"))
    contract = __import__("json").loads((export / "contract.json").read_text(encoding="utf-8"))

    def frozen_tensor(name, fmt, expected_shape):
        spec = manifest["tensors"][name]
        raw = (frozen / f"{name}.bin").read_bytes()
        import hashlib
        assert hashlib.sha256(raw).hexdigest() == spec["sha256"], f"tumor {name} SHA256"
        assert tuple(spec["shape"]) == expected_shape
        return list(struct.unpack("<" + fmt * (len(raw) // struct.calcsize(fmt)), raw))

    up = frozen_tensor("d3.concat_up", "b", (1, 512, 8, 8))
    skip = frozen_tensor("d3.concat_skip", "b", (1, 256, 8, 8))
    frozen_mac = frozen_tensor("d3.expand.mac", "i", (1, 256, 8, 8))
    frozen_out = frozen_tensor("d3.expand", "b", (1, 256, 8, 8))
    features = [up[channel * 64] for channel in range(512)] + [
        skip[channel * 64] for channel in range(256)]
    spec = contract["convolutions"]["d3.expand"]
    assert spec["shape"] == [256, 768, 1, 1]
    weights_raw = (export / spec["file"]).read_bytes()
    assert len(weights_raw) == 256 * 768
    weights = [list(row) for row in struct.iter_unpack("<768b", weights_raw)]
    merge = contract["merges"]["d3.expand"]
    multipliers = merge["multipliers"][0]
    bias_raw = (export / merge["bias_file"]).read_bytes()
    biases = list(struct.unpack("<256q", bias_raw))
    lower, upper, shift = 0, min(127, round(6 / merge["output_scale"])), merge["shift"]
    expected, accs = [], []
    for channel in range(256):
        acc = sum(features[i] * weights[channel][i] for i in range(768))
        assert acc == frozen_mac[channel * 64], f"tumor d3.expand MAC[{channel}]"
        value = max(lower, min(upper, rne(acc * multipliers[channel] + biases[channel], shift)))
        assert value == frozen_out[channel * 64], f"tumor d3.expand Golden[{channel}]"
        accs.append(acc)
        expected.append(value & 0xff)
    tumor_input = b"".join(bytes((v & 0xff for v in features[i:i + 16]))
                            for i in range(0, 768, 16))
    tumor_weights = bytearray()
    for og in range(64):
        for ig in range(48):
            for pe in range(4):
                channel = og * 4 + pe
                tumor_weights.extend(v & 0xff for v in weights[channel][ig * 16:(ig + 1) * 16])
    tumor_params = bytearray()
    for channel in range(256):
        tumor_params.extend(struct.pack("<iqhh", multipliers[channel], biases[channel], lower, upper))
    tumor_input_base, tumor_out_base = 0x0f000000, 0x0f100000
    tumor_weight_base, tumor_param_base = 0x001c0000, 0x00200000
    write_case(root, "tumor_d3_expand_frozen_pixel0", 1, 1, 1, 1, bytes(expected),
               tumor_input_base, out_base=tumor_out_base, cin=768, cout=256,
               shift=shift, weight_base=tumor_weight_base, param_base=tumor_param_base,
               run_id=0x100d, uploads=((tumor_input_base, "input.bin", tumor_input),),
               coefficients=((tumor_weight_base, "weights.bin", bytes(tumor_weights)),
                             (tumor_param_base, "params.bin", bytes(tumor_params))))
    names.append("tumor_d3_expand_frozen_pixel0")

    # Base64 pointwise pass: four input and four output groups exercise group
    # addressing and coefficient-bank changes through the read-only port.
    pw64_features = [[((p * 7 + c * 5 + 2) % 19) - 9 for c in range(64)]
                     for p in range(16)]
    in64, w64, p64, pw64 = make_pw(64, 64, pw64_features, 2)
    write_case(root, "pw_base64", 1, 4, 4, 1, pw64, 0x0c000000,
               out_base=0x0c100000, cin=64, cout=64,
               weight_base=0x002c0000, param_base=0x002d0000, run_id=0x100a,
               uploads=((0x0c000000, "input.bin", in64),),
               coefficients=((0x002c0000, "weights.bin", w64),
                             (0x002d0000, "params.bin", p64)))
    names.append("pw_base64")

    for name, cin, cout, pixels, in_base, out_base, weight_base, param_base, run_id in (
            ("pw_max_768_512", 768, 512, 1, 0x0d000000, 0x0d100000,
             0x00110000, 0x00170000, 0x100b),
            ("pw_tail_767_511", 767, 511, 3, 0x0e000000, 0x0e100000,
             0x00190000, 0x002a0000, 0x100c)):
        features = [[((p * 7 + c * 5 + 4) % 19) - 9 for c in range(cin)]
                    for p in range(pixels)]
        source, weights, params, golden = make_pw(cin, cout, features, 1)
        write_case(root, name, 1, pixels, 1, 1, golden, in_base,
                   out_base=out_base, cin=cin, cout=cout,
                   weight_base=weight_base, param_base=param_base, run_id=run_id,
                   uploads=((in_base, "input.bin", source),),
                   coefficients=((weight_base, "weights.bin", weights),
                                 (param_base, "params.bin", params)))
        names.append(name)

    # Standalone odd-tail pooling, two channel groups.
    w, h, groups = 5, 3, 2
    pool_input = bytes((((g * 37 + y * 29 + x * 17 + c * 7) % 255) - 127) & 0xff
                       for g in range(groups) for y in range(h) for x in range(w) for c in range(16))
    pool_output = bytearray()
    for g in range(groups):
        for y in range(h // 2):
            for x in range(w // 2):
                for c in range(16):
                    vals = []
                    for dy in range(2):
                        for dx in range(2):
                            at = ((g * h + y * 2 + dy) * w + x * 2 + dx) * 16 + c
                            b = pool_input[at]
                            vals.append(b - 256 if b >= 128 else b)
                    pool_output.append(max(vals) & 0xff)
    write_case(root, "pool_odd_two_groups", 2, w, h, groups, bytes(pool_output),
               0x07000000, out_base=0x07100000, run_id=0x1005,
               uploads=((0x07000000, "input.bin", pool_input),))
    names.append("pool_odd_two_groups")

    # Both zero-padded window cores share the same input/output storage path.
    for name, k, w, h, groups, in_base, out_base in (
            ("linebuffer3", 3, 2, 3, 2, 0x08000000, 0x08100000),
            ("linebuffer5", 5, 2, 2, 1, 0x09000000, 0x09100000)):
        source = bytes((((g * 43 + y * 23 + x * 11 + lane * 5) % 255) - 127) & 0xff
                       for g in range(groups) for y in range(h) for x in range(w) for lane in range(16))
        golden = line_windows(source, w, h, groups, k)
        write_case(root, name, 3 if k == 3 else 4, w, h, groups, golden, in_base,
                   out_base=out_base, run_id=0x1006 if k == 3 else 0x1007,
                   uploads=((in_base, "input.bin", source),))
        names.append(name)

    # Multi-group Element Add: each lane is packed as signed <mult_a,mult_b,bias>.
    w, h, groups = 3, 2, 4
    add_a, add_b, add_params = bytearray(), bytearray(), bytearray()
    add_golden = bytearray()
    for g in range(groups):
        lane_params = []
        for lane in range(16):
            lane_params.append((1 + (lane + g) % 2, 1 + g % 2, lane - 8 + g * 3))
        for pixel in range(w * h):
            av = [((g * 131 + pixel * 47 + lane * 19) % 2001) - 1000 for lane in range(16)]
            bv = [((g * 71 + pixel * 89 + lane * 31) % 1801) - 900 for lane in range(16)]
            add_a.extend(struct.pack("<16i", *av))
            add_b.extend(struct.pack("<16i", *bv))
            for lane, (ma, mb, bias) in enumerate(lane_params):
                value = rne(av[lane] * ma + bv[lane] * mb + bias, 1)
                add_golden.append(max(-128, min(127, value)) & 0xff)
        for ma, mb, bias in lane_params:
            add_params.extend(struct.pack("<iiq", ma, mb, bias))
    write_case(root, "element_add_two_groups", 6, w, h, groups, bytes(add_golden),
               0x0a000000, base_b=0x0a100000, out_base=0x0a200000, run_id=0x1008,
               shift=1, param_base=0x002e0000,
               uploads=((0x0a000000, "a.bin", bytes(add_a)),
                        (0x0a100000, "b.bin", bytes(add_b)),),
               coefficients=((0x002e0000, "params.bin", bytes(add_params)),))
    names.append("element_add_two_groups")

    # One configured P16 group, several pixels, lane-distinct shuffle pattern.
    w, h, groups = 2, 2, 1
    shuffle_input = bytes((((p * 41 + lane * 9) % 255) - 127) & 0xff
                          for p in range(w * h) for lane in range(16))
    shuffle_output = bytearray()
    for p in range(w * h):
        word = shuffle_input[p * 16:(p + 1) * 16]
        for i in range(8):
            shuffle_output.extend((word[i], word[i + 8]))
    write_case(root, "shuffle16", 7, w, h, groups, bytes(shuffle_output),
               0x0b000000, out_base=0x0b100000, run_id=0x1009,
               uploads=((0x0b000000, "input.bin", shuffle_input),))
    names.append("shuffle16")

    # Highest repaired group count with small geometry, including Add's
    # per-group parameter tags.  Reuse independent Golden from the cases above.
    for src_name, name, op, in_a, in_b, out_base, param_base, run_id in (
            ("pool_odd_two_groups", "pool_groups32", 2, 0x10000000, 0,
             0x10100000, 0, 0x1010),
            ("linebuffer3", "linebuffer3_groups32", 3, 0x10200000, 0,
             0x10300000, 0, 0x1011),
            ("linebuffer5", "linebuffer5_groups32", 4, 0x10400000, 0,
             0x10500000, 0, 0x1012)):
        src = root / src_name
        desc = (src / "descriptor.bin").read_bytes()
        width, height, old_groups = struct.unpack_from("<HHH", desc, 4)
        source = (src / "input.bin").read_bytes()[:width * height * old_groups * 16]
        golden = (src / "golden.bin").read_bytes()
        source = source * (32 // old_groups)
        golden = golden * (32 // old_groups)
        write_case(root, name, op, width, height, 32, golden, in_a,
                   out_base=out_base, run_id=run_id,
                   uploads=((in_a, "input.bin", source),))
        names.append(name)

    # Each group uses its own signed coefficients; outputs remain unsaturated
    # so a stale group or truncated address cannot hide behind saturation.
    add_a, add_b, add_params, add_golden = bytearray(), bytearray(), bytearray(), bytearray()
    for g in range(32):
        av = [g - lane for lane in range(16)]
        bv = [lane - 2 * g for lane in range(16)]
        add_a.extend(struct.pack("<16i", *av))
        add_b.extend(struct.pack("<16i", *bv))
        for lane in range(16):
            ma, mb, bias = 1 + g % 2, -1, lane - g
            add_params.extend(struct.pack("<iiq", ma, mb, bias))
            add_golden.append(rne(av[lane] * ma + bv[lane] * mb + bias, 1) & 0xff)
    write_case(root, "element_add_groups32", 6, 1, 1, 32, bytes(add_golden),
               0x10600000, base_b=0x10700000, out_base=0x10800000,
               shift=1, param_base=0x002e8000, run_id=0x1013,
               uploads=((0x10600000, "a.bin", bytes(add_a)),
                        (0x10700000, "b.bin", bytes(add_b))),
               coefficients=((0x002e8000, "params.bin", bytes(add_params)),))
    names.append("element_add_groups32")

    # Switch back to the already stored coefficient bank after wider layers.
    desc = (root / "pw_seed" / "descriptor.bin").read_bytes()
    write_case(root, "pw_switch_back", 1, 4, 4, 1, pw0, 0x03000000,
               out_base=0x10900000, cin=3, cout=16,
               weight_base=0x00100000, param_base=0x00180000, run_id=0x1014)
    names.append("pw_switch_back")

    (root / "cases.txt").write_text("\n".join(names) + "\n", encoding="ascii", newline="\n")
    print(f"generated {len(names)} joint cases")


if __name__ == "__main__":
    main()
