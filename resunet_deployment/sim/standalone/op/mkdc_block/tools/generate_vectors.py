#!/usr/bin/env python3
"""Generate only the small mkdc final-add vectors from the frozen vessel contract."""
from pathlib import Path
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[5]
FROZEN = ROOT / "src" / "params" / "int8" / "vessel"
CAPTURE = FROZEN / "golden_synthetic_32x32"
OUT = Path(__file__).resolve().parents[1] / "verification" / "vectors"
OUT.mkdir(parents=True, exist_ok=True)

contract = json.loads((FROZEN / "contract.json").read_text(encoding="utf-8"))
merge = contract["merges"]["mid.out"]
channels, height, width = 128, 4, 4
assert merge["shift"] == 24 and merge["relu6"]

def pack(values, bits):
    mask = (1 << bits) - 1
    return sum((int(v) & mask) << (bits * i) for i, v in enumerate(values))

mult = np.asarray(merge["multipliers"][0], dtype=np.int64)
mult_b = np.asarray(merge["multipliers"][1], dtype=np.int64)
bias = np.fromfile(FROZEN / merge["bias_file"], dtype="<i8")
expected = np.fromfile(CAPTURE / "mid.out.bin", dtype=np.int8).reshape(channels, height, width)
assert len(mult) == len(bias) == channels

with (OUT / "final_params.hex").open("w", encoding="ascii") as f:
    for group in range(channels // 16):
        f.write(f"{pack(mult[group * 16:(group + 1) * 16], 22):056x}\n")
        f.write(f"{pack(bias[group * 16:(group + 1) * 16], 64):0256x}\n")

with (OUT / "final_params_b.hex").open("w", encoding="ascii") as f:
    for group in range(channels // 16):
        f.write(f"{pack(mult_b[group * 16:(group + 1) * 16], 22):056x}\n")

with (OUT / "final_golden.hex").open("w", encoding="ascii") as f:
    for group in range(channels // 16):
        for row in range(height):
            for col in range(width):
                f.write(f"{pack(expected[group * 16:(group + 1) * 16, row, col], 8):032x}\n")

manifest = {
    "source": str(FROZEN / "contract.json"),
    "shape": [1, channels, height, width],
    "groups": channels // 16,
    "shift": merge["shift"],
    "clamp": [0, 127],
    "final_golden_sha256": hashlib.sha256((OUT / "final_golden.hex").read_bytes()).hexdigest(),
    "bias_sha256": hashlib.sha256((FROZEN / merge["bias_file"]).read_bytes()).hexdigest(),
}
(OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest, indent=2))
