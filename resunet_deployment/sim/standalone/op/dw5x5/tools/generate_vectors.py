"""Generate the smallest frozen DW5x5 MAC vector set without using RTL logic."""
from pathlib import Path
import hashlib
import numpy as np

ROOT = Path(__file__).resolve().parents[5]
FROZEN = ROOT / "src" / "params" / "int8" / "vessel"
OUT = Path(__file__).resolve().parents[1] / "verification" / "vectors"
OUT.mkdir(parents=True, exist_ok=True)

H = W = 4
C = 128
GROUPS = C // 16
x = np.fromfile(FROZEN / "golden_synthetic_32x32" / "mid.expand.bin", dtype=np.int8).reshape(C, H, W)
w = np.fromfile(FROZEN / "mid.dw5.weight.i8.bin", dtype=np.int8).reshape(C, 5, 5)
gold = np.fromfile(FROZEN / "golden_synthetic_32x32" / "mid.dw5.mac.bin", dtype="<i4").reshape(C, H, W)

def pack(values, bits):
    result = 0
    mask = (1 << bits) - 1
    for index, value in enumerate(values):
        result |= (int(value) & mask) << (index * bits)
    return result

def word(values):
    return f"{pack(values, 8):032x}"

with (OUT / "stimulus.hex").open("w", encoding="ascii") as f:
    for g in range(GROUPS):
        for y in range(H):
            for xx in range(W):
                f.write(word([x[g * 16 + lane, y, xx] for lane in range(16)]) + "\n")

with (OUT / "golden_mac.hex").open("w", encoding="ascii") as f:
    for g in range(GROUPS):
        for y in range(H):
            for xx in range(W):
                f.write(f"{pack([gold[g * 16 + lane, y, xx] for lane in range(16)], 32):0128x}\n")

with (OUT / "weights.hex").open("w", encoding="ascii") as f:
    for g in range(GROUPS):
        lanes = [w[g * 16 + lane, r, c] for lane in range(16) for r in range(5) for c in range(5)]
        f.write(f"{pack(lanes, 8):0640x}\n")

with (OUT / "params.hex").open("w", encoding="ascii") as f:
    lanes = []
    for _ in range(16):
        lanes.extend([1, 0, -128, 127])
    value = 0
    for lane, (multiplier, bias, lower, upper) in enumerate(zip(lanes[0::4], lanes[1::4], lanes[2::4], lanes[3::4])):
        base = lane * 128
        value |= (multiplier & ((1 << 32) - 1)) << base
        value |= (bias & ((1 << 64) - 1)) << (base + 32)
        value |= (lower & 0xffff) << (base + 96)
        value |= (upper & 0xffff) << (base + 112)
    for _ in range(GROUPS):
        f.write(f"{value:0512x}\n")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

(OUT / "vector_manifest.txt").write_text(
    f"source={FROZEN}\nshape=C{C}xH{H}xW{W}\ngroups={GROUPS}\npadding=2\n"
    f"stimulus_sha256={sha(OUT / 'stimulus.hex')}\n"
    f"golden_mac_sha256={sha(OUT / 'golden_mac.hex')}\n"
    f"weights_sha256={sha(OUT / 'weights.hex')}\n"
    f"params_sha256={sha(OUT / 'params.hex')}\n",
    encoding="utf-8",
)
