"""Deterministic independent integer PW oracle; TB handles only bus timing/checks."""
from pathlib import Path
import random
import struct

ROOT = Path(__file__).resolve().parent / "pw"
CASES = [
    ("compute192", 192, 64, 64, 0, 8),
    ("compute384", 384, 128, 64, 0, 8),
    ("compute768", 768, 256, 64, 0, 8),
    ("p16_low", 3, 32, 33, 0, 7),
    ("p16_tail", 17, 21, 19, 0, 5),
    ("p8_head1", 16, 1, 17, 8, 0),
    ("p8_head5", 3, 5, 33, 8, 3),
    ("p8_tail", 17, 21, 19, 8, 4),
    ("p8_max", 768, 512, 1, 8, 8),
    ("p16_max", 768, 512, 1, 0, 8),
    ("raw4_tail", 17, 21, 19, 4, 0),
    ("raw16", 32, 32, 17, 20, 0),
    ("debug8", 17, 21, 19, 2, 5),
    ("debug16", 17, 21, 19, 10, 5),
    ("reload1", 1, 1, 1, 0, 0),
]

def hexfile(path, data):
    path.write_text("".join(f"{b:02x}\n" for b in data), encoding="ascii")

def rounded(value, shift):
    if not shift:
        return value
    whole, rest = divmod(value, 1 << shift)
    half = 1 << (shift - 1)
    return whole + int(rest > half or (rest == half and whole & 1))

manifest = []
baseline_manifest = []
for index, (name, ci, co, px, flags, shift) in enumerate(CASES):
    rng = random.Random(20261023 + index)
    x = [[rng.randrange(-128, 128) for _ in range(ci)] for _ in range(px)]
    w = [[rng.randrange(-8, 9) for _ in range(ci)] for _ in range(co)]
    mult = [rng.choice((-13, -3, 1, 2, 7, 17)) for _ in range(co)]
    bias = [rng.randrange(-10000, 10001) for _ in range(co)]
    int16 = bool(flags & 8)
    lo, hi = (-32768, 32767) if int16 else (-128, 127)
    mac = [[sum(a*b for a,b in zip(row, weight)) for weight in w] for row in x]
    q = [[min(hi, max(lo, rounded(v*mult[c]+bias[c], shift))) for c,v in enumerate(row)] for row in mac]
    folder = ROOT / "vectors" / name
    folder.mkdir(parents=True, exist_ok=True)
    inputs = bytes(x[p][g*16+l] & 255 if g*16+l < ci else 0xA5
                   for g in range((ci+15)//16) for p in range(px) for l in range(16))
    weights = bytes(w[g*4+p][ig*16+l] & 255 if g*4+p < co and ig*16+l < ci else 0xA5
                    for g in range((co+3)//4) for ig in range((ci+15)//16) for p in range(4) for l in range(16))
    params = b"".join(struct.pack("<iqhh", mult[c], bias[c], lo, hi) if c < co else bytes([0xA5])*16
                      for c in range((co+3)//4*4))
    raw = bool(flags & 4)
    raw_lanes = 16 if flags & 16 else 4
    lanes = raw_lanes if raw else 4 if int16 and flags & 2 else 8 if int16 else 16
    fmt = "<i" if raw else "<h" if int16 else "<b"
    values = mac if raw else q
    golden = b"".join(struct.pack(fmt, values[p][g*lanes+l] if g*lanes+l < co else 0)
                      for g in range((co+lanes-1)//lanes) for p in range(px) for l in range(lanes))
    old_lanes = 4 if int16 and not raw else lanes
    golden_before = b"".join(struct.pack(fmt, values[p][g*old_lanes+l] if g*old_lanes+l < co else 0)
                             for g in range((co+old_lanes-1)//old_lanes) for p in range(px) for l in range(old_lanes))
    macgold = b"" if raw or not flags & 2 else b"".join(
        struct.pack("<i", mac[p][g*4+l] if g*4+l < co else 0)
        for g in range((co+3)//4) for p in range(px) for l in range(4))
    for fn, data in (("input.hex",inputs),("weights.hex",weights),("params.hex",params),("golden.hex",golden),("mac.hex",macgold)):
        hexfile(folder/fn, data)
    manifest.append(f"{name} {ci} {co} {px} {flags} {shift} {len(inputs)} {len(weights)} {len(params)} {len(golden)} {len(macgold)}\n")
    hexfile(folder/"golden_before.hex", golden_before)
    baseline_manifest.append(f"{name} {ci} {co} {px} {flags} {shift} {len(inputs)} {len(weights)} {len(params)} {len(golden_before)} {len(macgold)}\n")
(ROOT/"cases.txt").write_text("".join(manifest), encoding="ascii")
(ROOT/"cases_before.txt").write_text("".join(baseline_manifest), encoding="ascii")
print(f"Generated {len(CASES)} independent PW cases")
