"""Independent NumPy integer Golden and whole-layer vessel/base16 task schedule.

Reuses only wire-format packing from the existing 32x32 generator. Frozen bins
are read-only; all 65 captured nodes are first checked against frozen 32x32.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path

import numpy as np

from generate_vectors import ROOT, EXPORT, ROM_MAP, pack_layout, pack_p4, descriptor, write_hex

BASE = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rne(value, shift):
    if not shift:
        return value
    magnitude = np.abs(value)
    whole = magnitude >> shift
    remainder = magnitude & ((1 << shift) - 1)
    half = 1 << (shift - 1)
    whole += (remainder > half) | ((remainder == half) & ((whole & 1) != 0))
    return np.where(value < 0, -whole, whole)


def golden(x, contract):
    trace = {"input": x.astype(np.int8)}

    def mac(name, value):
        config = contract["convolutions"][name]
        weights = np.fromfile(EXPORT / config["file"], np.int8).reshape(config["shape"]).astype(np.int64)
        value = value.astype(np.int64)
        channels, height, width = value.shape
        outputs, _, kh, kw = weights.shape
        if config["groups"] == 1 and kh == kw == 1:
            result = (weights[:, :, 0, 0] @ value.reshape(channels, -1)).reshape(outputs, height, width)
        else:
            assert config["groups"] == channels == outputs
            padding = config["padding"]
            padded = np.pad(value, ((0, 0), (padding, padding), (padding, padding)))
            result = np.zeros((outputs, height, width), np.int64)
            for y in range(kh):
                for z in range(kw):
                    result += padded[:, y:y + height, z:z + width] * weights[:, 0, y, z, None, None]
        assert np.max(np.abs(result)) < 2**31, name
        trace[name + ".mac"] = result.astype(np.int32)
        return result

    def merge(name, *parts):
        config = contract["merges"][name]
        numerator = np.fromfile(EXPORT / config["bias_file"], "<i8")[:, None, None]
        assert len(parts) == len(config["multipliers"])
        for part, multiplier in zip(parts, config["multipliers"]):
            numerator = numerator + part.astype(np.int64) * np.array(multiplier, np.int64)[:, None, None]
        assert np.max(np.abs(numerator)) < 2**62, name
        bits, relu = config["bits"], config["relu6"]
        lower = 0 if relu else -(1 << (bits - 1))
        upper = min((1 << (bits - 1)) - 1, round(6 / config["output_scale"])) if relu else (1 << (bits - 1)) - 1
        result = np.clip(rne(numerator, config["shift"]), lower, upper).astype(np.int16 if bits == 16 else np.int8)
        trace[name] = result
        return result

    def block(name, value):
        expand = merge(name + ".expand", mac(name + ".expand", value))
        mix = merge(name + ".mix", mac(name + ".dw3", expand), mac(name + ".dw5", expand))
        return merge(name + ".out", mac(name + ".project", mix), mac(name + ".skip", value))

    def pool(value):
        return np.maximum.reduce([value[:, y::2, z::2] for y in (0, 1) for z in (0, 1)])

    e1 = block("e1", x)
    e2 = block("e2", pool(e1))
    e3 = block("e3", pool(e2))
    value = block("mid", pool(e3))
    for name, skip in (("d3", e3), ("d2", e2), ("d1", e1)):
        up = value.repeat(2, 1).repeat(2, 2)
        a, b = merge(name + ".concat_up", up), merge(name + ".concat_skip", skip)
        # Current hardware CONCAT has no rescale: prove frozen alignment is identity.
        assert np.array_equal(a, up) and np.array_equal(b, skip)
        for suffix in ("up", "skip"):
            cfg = contract["merges"][name + ".concat_" + suffix]
            assert np.all(np.array(cfg["multipliers"]) == 1 << cfg["shift"])
            assert not np.any(np.fromfile(EXPORT / cfg["bias_file"], "<i8"))
        value = block(name, np.concatenate((a, b)))
    merge("head", mac("head", value))
    return trace


def verify_reference(contract):
    hashes = json.loads((EXPORT / "sha256.json").read_text(encoding="utf-8"))
    for name, digest in hashes.items():
        assert sha(EXPORT / name) == digest, name
    capture = EXPORT / "golden_synthetic_32x32"
    manifest = json.loads((capture / "manifest.json").read_text(encoding="utf-8"))["tensors"]

    def read(name):
        info = manifest[name]
        assert sha(capture / (name + ".bin")) == info["sha256"], name
        return np.fromfile(capture / (name + ".bin"), info["dtype"]).reshape(info["shape"])[0]

    trace = golden(read("input"), contract)
    assert trace.keys() == manifest.keys()
    for name, value in trace.items():
        assert np.array_equal(value, read(name)), name
    # Positive/negative ties, independently evaluated with Python integers.
    checks = 0
    for shift in range(1, 25):
        half = 1 << (shift - 1)
        values = [n * (1 << shift) + d for n in range(-8, 9) for d in (-half-1, -half, -half+1, 0, half-1, half, half+1)]
        expected = []
        for value in values:
            q, r = divmod(abs(value), 1 << shift)
            q += r > half or (r == half and q % 2 == 1)
            expected.append(-q if value < 0 else q)
        assert rne(np.array(values, np.int64), shift).tolist() == expected
        checks += len(values)
    return {"frozen_files": len(hashes), "frozen_nodes": len(trace), "elements": sum(a.size for a in trace.values()), "rne_cases": checks}


def generate(side, out, seed):
    if out.exists():
        raise FileExistsError(f"Refusing to overwrite existing vectors: {out}")
    contract = json.loads((EXPORT / "contract.json").read_text(encoding="utf-8"))
    reference = verify_reference(contract)
    print("[REFERENCE PASS] " + json.dumps(reference), flush=True)
    x = np.random.default_rng(seed).integers(-128, 128, (3, side, side), dtype=np.int16).astype(np.int8)
    trace = golden(x, contract)
    addresses = {}
    for line in ROM_MAP.read_text(encoding="utf-8").splitlines()[1:]:
        model, _, name, _, _, _, address = line.split("\t")
        if model == "vessel":
            addresses[name] = int(address, 16)

    # Fixed capacities calculated for 512x512, shared scratch reused per block.
    # Above both coefficient windows, including tumor DDR [08000000,08200000).
    capacities = {"input": 4, "e1": 4, "e2": 2, "e3": 1, "mid": .5,
                  "pool": 1, "expand": 4, "dw3": 16, "dw5": 16, "mix": 4,
                  "project": 16, "skip_raw": 16, "up": 8, "concat": 12,
                  "d3": 1, "d2": 2, "d1": 4, "head": 2}
    slots, cursor = {}, 0x09000000
    for name, mib in capacities.items():
        size = int(mib * 2**20)
        slots[name] = {"address": cursor, "capacity_512": size}
        cursor += size
    assert cursor <= 0x20000000
    tasks, tensors = [], {}
    tensors["input"] = dict(slot="input", size=side*side*16, produced=-1, consumers=[])

    def add(name, op, value, reads, slot, **kwargs):
        index = len(tasks)
        data = pack_p4(value) if name == "head" else pack_layout(value, 32 if value.dtype == np.int32 else 8)
        assert len(data) <= slots[slot]["capacity_512"]
        tensors[name] = dict(slot=slot, size=len(data), produced=index, consumers=[])
        regions = []
        for source in reads:
            t = tensors[source]
            t["consumers"].append(index)
            regions.append({"tensor": source, "address": slots[t["slot"]]["address"], "bytes": t["size"]})
        desc = descriptor(op, 0x68000001 + index, base_a=regions[0]["address"],
                          base_b=regions[1]["address"] if len(regions) > 1 else 0,
                          output=slots[slot]["address"], **kwargs)
        tasks.append(dict(task=f"{index:03d}_{name}", descriptor=desc, data=data, reads=regions,
                          output_base=slots[slot]["address"], result_bytes=len(data),
                          output_end=slots[slot]["address"]+len(data), run_id=0x68000001+index))

    def block(name, source, cin, cout, n):
        common = dict(width=n, height=n, groups=cout//16, cout=cout)
        for suffix, src, dest, raw, channels in (("expand", source, "expand", False, cin),
                                                ("project", name+".mix", "project", True, cout),
                                                ("skip", source, "skip_raw", True, cin)):
            full = name+"."+suffix
            add(full, 1, trace[full+".mac" if raw else full], [src], dest, cin=channels,
                weights=addresses[full+".weight.i8.bin"], params=addresses[full+".params"],
                flags=20 if raw else 0, **common)
            if suffix == "expand":
                for dw, op in (("dw3", 8), ("dw5", 9)):
                    key = name+"."+dw
                    add(key, op, trace[key+".mac"], [full], dw, cin=cout,
                        weights=addresses[key+".weight.i8.bin"], **common)
                add(name+".mix", 6, trace[name+".mix"], [name+".dw3", name+".dw5"], "mix",
                    cin=cout, params=addresses[name+".mix.params"], lower=0, upper=127, **common)
        add(name+".out", 6, trace[name+".out"], [name+".project", name+".skip"], name,
            cin=cout, params=addresses[name+".out.params"], lower=0, upper=127, **common)

    source, cin = "input", 3
    for i, name in enumerate(("e1", "e2", "e3", "mid")):
        n, cout = side >> i, 16 << i
        block(name, source, cin, cout, n)
        if name != "mid":
            value = trace[name+".out"]
            pooled = np.maximum.reduce([value[:, y::2, z::2] for y in (0, 1) for z in (0, 1)])
            source = "pool"+str(i+1)
            add(source, 2, pooled, [name+".out"], "pool", width=n, height=n, groups=cout//16, cin=cout, cout=cout)
        cin = cout
    previous = "mid"
    for name, enc, cout, n in (("d3", "e3", 64, side//4), ("d2", "e2", 32, side//2), ("d1", "e1", 16, side)):
        up = trace[previous+".out"].repeat(2, 1).repeat(2, 2)
        add(name+".up", 10, up, [previous+".out"], "up", width=n//2, height=n//2, groups=2*cout//16)
        cat = np.concatenate((up, trace[enc+".out"]))
        add(name+".concat", 5, cat, [name+".up", enc+".out"], "concat", width=n, height=n, groups=2*cout//16, groups_b=cout//16)
        block(name, name+".concat", 3*cout, cout, n)
        previous = name
    add("head", 1, trace["head"], ["d1.out"], "head", width=side, height=side, groups=1, cin=16, cout=2,
        weights=addresses["head.weight.i8.bin"], params=addresses["head.params"], flags=8)
    assert len(tasks) == 59
    # Prove each slot remains intact through its last consumer, including the
    # block-internal raw skip and the encoder long skip after Pool consumption.
    peak = 0
    for index in range(-1, len(tasks)):
        live = [(name, t) for name, t in tensors.items() if t["produced"] <= index <= max(t["consumers"] or [len(tasks)])]
        peak = max(peak, sum(t["size"] for _, t in live))
        for i, (name, a) in enumerate(live):
            for other, b in live[i+1:]:
                assert a["slot"] != b["slot"], (index, name, other)
    out.mkdir(parents=True)
    lines = []
    for task in tasks:
        folder = out / task["task"]
        folder.mkdir()
        desc, data = task.pop("descriptor"), task.pop("data")
        write_hex(folder / "descriptor.hex", desc)
        write_hex(folder / "golden.hex", data)
        task["descriptor_sha256"] = hashlib.sha256(desc).hexdigest()
        task["golden_sha256"] = hashlib.sha256(data).hexdigest()
        lines.append(f'{task["task"]} {len(data)} {task["task"]}/descriptor.hex {task["task"]}/golden.hex\n')
    data = pack_layout(x, 8, fill=-128)
    write_hex(out / "input.hex", data)
    (out / "uploads.txt").write_text(f'{slots["input"]["address"]:08x} {len(data)} input.hex\n', encoding="ascii")
    (out / "tasks.txt").write_text("".join(lines), encoding="ascii")
    report = dict(model="vessel", base=16, shape=[1,3,side,side], seed=seed, task_count=59, tasks=tasks,
                  input_bytes=len(data), input_address=slots["input"]["address"], input_sha256=hashlib.sha256(data).hexdigest(),
                  reference_check=reference, contract_sha256=sha(EXPORT/"contract.json"), slots=slots,
                  tensors=tensors, arena_end=cursor, arena_capacity_512=cursor-0x09000000, peak_live_bytes=peak)
    (out / "task_manifest.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    print(f"[FULLNET VECTORS PASSED] side={side} tasks=59 peak_live_bytes={peak} arena_capacity_512={cursor-0x09000000}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--size", type=int, choices=(64,128,256,512), default=128)
    parser.add_argument("--seed", type=int, default=20261017)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    generate(args.size, args.out or BASE / "vessel" / f"{args.size}x{args.size}" / "vectors", args.seed)
