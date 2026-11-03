"""独立离线 d3 整数参考；只读同一 vessel 冻结包，不导入生产 Python。"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

REPO = Path(__file__).resolve().parents[5]
EXPORT = REPO / "src/params/int8/vessel"


def pack(values, bits):
    return sum((int(v) & ((1 << bits) - 1)) << (bits * i) for i, v in enumerate(values))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    out = parser.parse_args().out
    out.mkdir(parents=True, exist_ok=False)
    hashes = {}

    def read(path):
        data = path.read_bytes()
        hashes[str(path.relative_to(REPO))] = hashlib.sha256(data).hexdigest()
        return data

    contract = json.loads(read(EXPORT / "contract.json"))
    capture = EXPORT / "golden_synthetic_32x32"
    manifest = json.loads(read(capture / "manifest.json"))["tensors"]
    assert contract["task"] == "vessel"
    assert "removed by permuting" in contract["shuffle"]

    def tensor(name):
        info = manifest[name]
        data = read(capture / f"{name}.bin")
        assert hashlib.sha256(data).hexdigest() == info["sha256"], name
        return np.frombuffer(data, dtype=np.dtype(info["dtype"]).newbyteorder("<")).reshape(info["shape"])[0]

    def hexfile(name, values, bits):
        (out / f"{name}.hex").write_text("".join(f"{int(v):0{(bits+3)//4}x}\n" for v in values))

    def p16(name, data, bits=8):
        c, h, w = data.shape
        assert c % 16 == 0
        hexfile(name, (pack(data[g:g+16, y, x], bits)
            for g in range(0, c, 16) for y in range(h) for x in range(w)), bits * 16)

    def weights(name):
        spec = contract["convolutions"][f"d3.{name}"]
        return np.frombuffer(read(EXPORT / spec["file"]), dtype=np.int8).reshape(spec["shape"]).astype(np.int64)

    def bias(name):
        return np.frombuffer(read(EXPORT / contract["merges"][f"d3.{name}"]["bias_file"]), dtype="<i8")

    def clamp(cfg):
        assert cfg["bits"] == 8
        return (0, min(127, round(6 / cfg["output_scale"]))) if cfg["relu6"] else (-128, 127)

    def merge(name, inputs):
        cfg = contract["merges"][f"d3.{name}"]
        b = bias(name)
        numerator = np.broadcast_to(b[:, None, None], inputs[0].shape).copy()
        for value, multiplier in zip(inputs, cfg["multipliers"], strict=True):
            numerator += value.astype(np.int64) * np.array(multiplier, dtype=np.int64)[:, None, None]
        assert np.abs(numerator).max() < 2**62
        low, high = clamp(cfg)
        denominator = 1 << cfg["shift"]
        def rne(v):
            q, r = divmod(int(v), denominator)
            return min(high, max(low, q + (2*r > denominator or (2*r == denominator and q & 1))))
        result = np.array([rne(v) for v in numerator.flat], dtype=np.int8).reshape(numerator.shape)
        assert np.array_equal(result, tensor(f"d3.{name}")), (name, "independent RNE != frozen")
        return result

    mid, skip = tensor("mid.out"), tensor("e3.out")
    assert mid.shape == (128, 4, 4) and skip.shape == (64, 8, 8)
    up = mid.repeat(2, axis=1).repeat(2, axis=2)
    for name, source, source_node in (("concat_up", up, "mid.out"), ("concat_skip", skip, "e3.out")):
        cfg = contract["merges"][f"d3.{name}"]
        assert all(m == 1 << cfg["shift"] for row in cfg["multipliers"] for m in row)
        assert not np.any(bias(name)) and not cfg["relu6"]
        assert cfg["output_scale"] == contract["activation_scales"][source_node]
        assert np.array_equal(merge(name, [source]), source), "Concat scale is not identity"
    cat = np.concatenate((up, skip), axis=0)
    p16("mid", mid); p16("encoder_skip", skip)
    p16("up_golden", up); p16("concat_golden", cat)

    def pw(name, data):
        w = weights(name)[:, :, 0, 0]
        mac = (w @ data.reshape(data.shape[0], -1).astype(np.int64)).reshape(w.shape[0], 8, 8)
        assert np.abs(mac).max() < 2**31
        assert np.array_equal(mac, tensor(f"d3.{name}.mac")), name
        p16(f"{name}_mac", mac, 32)
        cout, cin = w.shape
        hexfile(f"{name}_weights", (pack(w[g:g+4, k:k+16].flat, 8)
            for g in range(0, cout, 4) for k in range(0, cin, 16)), 512)
        if name == "expand":
            cfg = contract["merges"]["d3.expand"]
            mult, b = cfg["multipliers"][0], bias(name)
            low, high = clamp(cfg)
            assert cfg["shift"] == 24
        else:
            mult, b, low, high = [0]*cout, [0]*cout, -128, 127
        params = [pack((int(mult[c]),), 32) | ((int(b[c]) & ((1 << 64)-1)) << 32)
                  | ((low & 65535) << 96) | ((high & 65535) << 112) for c in range(cout)]
        hexfile(f"{name}_params", (pack(params[g:g+4], 128) for g in range(0, cout, 4)), 512)
        return mac

    expand = merge("expand", [pw("expand", cat)])
    p16("expand_golden", expand)
    dw_mac = []
    for k in (3, 5):
        w = weights(f"dw{k}")[:, 0]
        padded = np.pad(expand.astype(np.int64), ((0, 0), (k//2, k//2), (k//2, k//2)))
        mac = sum(padded[:, y:y+8, x:x+8] * w[:, y, x, None, None] for y in range(k) for x in range(k))
        assert np.array_equal(mac, tensor(f"d3.dw{k}.mac"))
        p16(f"dw{k}_mac", mac, 32)
        dw_mac.append(mac)
        hexfile(f"dw{k}_weights", (pack(w[g:g+16].flat, 8) for g in range(0, 64, 16)), 16*k*k*8)
        raw_param = 1 | ((-128 & 65535) << 96) | (127 << 112)
        hexfile(f"dw{k}_params", [pack([raw_param]*16, 128)]*4, 2048)
        hexfile(f"window{k}_golden", (pack((pack(padded[g:g+16, y+dy, x+dx], 8)
            for dy in range(k) for dx in range(k)), 128)
            for g in range(0, 64, 16) for y in range(8) for x in range(8)), 128*k*k)
    mix = merge("mix", dw_mac)
    p16("mix_golden", mix)
    final = merge("out", [pw("project", mix), pw("skip", cat)])
    p16("final_golden", final)
    configs = []
    for name in ("mix", "out"):
        cfg = contract["merges"][f"d3.{name}"]
        for label, values, bits in (("a", cfg["multipliers"][0], 22),
                                     ("b", cfg["multipliers"][1], 22), ("bias", bias(name), 64)):
            assert all(-(1 << (bits-1)) <= int(v) < 1 << (bits-1) for v in values)
            hexfile(f"{name}_{label}", (pack(values[g:g+16], bits) for g in range(0, 64, 16)), bits*16)
        configs.append(f"{name},{cfg['shift']},{clamp(cfg)[0]},{clamp(cfg)[1]}")
    (out / "merge_config.csv").write_text("\n".join(configs)+"\n")
    (out / "provenance.json").write_text(json.dumps({"task":"vessel", "block":"d3", "input_shapes":[list(mid.shape),list(skip.shape)],
        "output_shape":list(final.shape), "scales":{n:contract["activation_scales"][n] for n in ("mid.out","e3.out","d3.expand","d3.mix","d3.out")},
        "concat_identity_verified":True,"shuffle":contract["shuffle"],"sources_sha256":hashes}, ensure_ascii=False,indent=2)+"\n")
    print("[GOLDEN PASSED] vessel d3 independent nearest/concat/PW/DW/RNE all match frozen tensors; source SHA256 checked")


if __name__ == "__main__":
    main()
