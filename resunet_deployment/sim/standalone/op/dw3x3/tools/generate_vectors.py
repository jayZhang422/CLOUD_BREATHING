from pathlib import Path
import hashlib
import numpy as np

ROOT = Path(__file__).resolve().parents[5]
FROZEN = ROOT / "src" / "params" / "int8" / "vessel"
OUT = Path(__file__).resolve().parents[1] / "verification" / "vectors"
OUT.mkdir(parents=True, exist_ok=True)

H = W = 4
C = 128
groups = C // 16
x = np.fromfile(FROZEN / "golden_synthetic_32x32" / "mid.expand.bin", dtype=np.int8).reshape(C, H, W)
w = np.fromfile(FROZEN / "mid.dw3.weight.i8.bin", dtype=np.int8).reshape(C, 3, 3)
gold = np.fromfile(FROZEN / "golden_synthetic_32x32" / "mid.dw3.mac.bin", dtype="<i4").reshape(C, H, W)

def word(values):
    result = 0
    for lane, value in enumerate(values):
        result |= int(np.uint8(value)) << (lane * 8)
    return f"{result:032x}"

with (OUT / "stimulus.hex").open("w", encoding="ascii") as f:
    for g in range(groups):
        for y in range(H):
            for xx in range(W):
                f.write(word([x[g * 16 + lane, y, xx] for lane in range(16)]) + "\n")

with (OUT / "golden_mac.hex").open("w", encoding="ascii") as f:
    for g in range(groups):
        for y in range(H):
            for xx in range(W):
                value = 0
                for lane in range(16):
                    value |= int(np.uint32(gold[g * 16 + lane, y, xx])) << (lane * 32)
                f.write(f"{value:0128x}\n")

with (OUT / "weights.hex").open("w", encoding="ascii") as f:
    for g in range(groups):
        value = 0
        for lane in range(16):
            for tap in range(9):
                value |= int(np.uint8(w[g * 16 + lane, tap // 3, tap % 3])) << ((lane * 9 + tap) * 8)
        f.write(f"{value:0288x}\n")

with (OUT / "params.hex").open("w", encoding="ascii") as f:
    value = 0
    for lane in range(16):
        base = lane * 128
        value |= 1 << base
        value |= int(np.uint16(np.int16(-128))) << (base + 96)
        value |= int(np.uint16(np.int16(127))) << (base + 112)
    for _ in range(groups):
        f.write(f"{value:0512x}\n")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

(OUT / "vector_manifest.txt").write_text(
    f"source={FROZEN}\nshape=C{C}xH{H}xW{W}\ngroups={groups}\n"
    f"stimulus_sha256={sha(OUT / 'stimulus.hex')}\n"
    f"golden_mac_sha256={sha(OUT / 'golden_mac.hex')}\n"
    f"weights_sha256={sha(OUT / 'weights.hex')}\n"
    f"params_sha256={sha(OUT / 'params.hex')}\n",
    encoding="utf-8",
)
