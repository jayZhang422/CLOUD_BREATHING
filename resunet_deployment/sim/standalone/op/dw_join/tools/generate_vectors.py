"""Prepare only the frozen merge vectors; DW inputs and MAC Goldens are reused from DW3x3/DW5x5."""
from pathlib import Path
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[5]
EXPORT = ROOT / "src" / "params" / "int8" / "vessel"
CAPTURE = EXPORT / "golden_synthetic_32x32"
OUT = Path(__file__).resolve().parents[1] / "verification" / "vectors"
OUT.mkdir(parents=True, exist_ok=True)

contract = json.loads((EXPORT / "contract.json").read_text(encoding="utf-8"))
merge = contract["merges"]["mid.mix"]
channels, height, width = 128, 4, 4
groups = channels // 16

expected = np.fromfile(CAPTURE / "mid.mix.bin", dtype=np.int8).reshape(channels, height, width)
params_a = np.asarray(merge["multipliers"][0], dtype=np.int32)
params_b = np.asarray(merge["multipliers"][1], dtype=np.int32)
bias = np.fromfile(EXPORT / merge["bias_file"], dtype="<i8")
assert len(params_a) == len(params_b) == len(bias) == channels
assert merge["shift"] == 24 and merge["relu6"]

def pack(values, bits):
    mask = (1 << bits) - 1
    return sum((int(v) & mask) << (bits * i) for i, v in enumerate(values))

with (OUT / "merge_golden.hex").open("w", encoding="ascii") as f:
    for group in range(groups):
        for row in range(height):
            for col in range(width):
                f.write(f"{pack(expected[group * 16:(group + 1) * 16, row, col], 8):032x}\n")

for name, values, bits in (("merge_params_a.hex", params_a, 22),
                           ("merge_params_b.hex", params_b, 22),
                           ("merge_bias.hex", bias, 64)):
    with (OUT / name).open("w", encoding="ascii") as f:
        for group in range(groups):
            f.write(f"{pack(values[group * 16:(group + 1) * 16], bits):0{(16 * bits + 3) // 4}x}\n")

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

manifest = {
    "source": str(EXPORT),
    "shape": [1, channels, height, width],
    "groups": groups,
    "shift": merge["shift"],
    "clamp": [0, min(127, round(6 / merge["output_scale"]))],
    "shared_stimulus": "../DW3x3/verification/vectors/stimulus.hex == ../DW5x5/verification/vectors/stimulus.hex",
    "merge_golden_sha256": sha(OUT / "merge_golden.hex"),
    "merge_params_a_sha256": sha(OUT / "merge_params_a.hex"),
    "merge_params_b_sha256": sha(OUT / "merge_params_b.hex"),
    "merge_bias_sha256": sha(OUT / "merge_bias.hex"),
    "frozen_mid_mix_sha256": sha(CAPTURE / "mid.mix.bin"),
}
(OUT / "vector_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest, indent=2))
