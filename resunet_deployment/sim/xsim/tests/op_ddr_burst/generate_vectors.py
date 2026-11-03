"""DDR transport vectors: frozen byte semantics, no operator reference model."""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SIZE = 0x40000
rng = random.Random(20261017)
initial = bytes(rng.randrange(256) for _ in range(SIZE))
memory = bytearray(initial)
stimulus, golden, phases = [], [], {}


def transaction(phase, kind, address=0, mask=0, data=bytes(32)):
    address &= ~31
    expected = bytes(32)
    if kind == 0:
        expected = memory[address:address + 32]
    elif kind in (1, 3):
        for b in range(32):
            if mask & (1 << b):
                memory[address + b] = data[b]
    word = (phase << 322) | (kind << 319) | (address << 288) | (mask << 256) | int.from_bytes(data, "little")
    stimulus.append(f"{word:083x}")
    golden.append(f"{int.from_bytes(expected, 'little'):064x}")
    phases[phase] = phases.get(phase, 0) + 1


def write(phase, address, size):
    offset = address % 32
    data = bytearray(32)
    data[offset:offset + size] = rng.randbytes(size)
    transaction(phase, 1, address, ((1 << size) - 1) << offset, data)


# Actual PW PE4 output order: group4 within a 16-pixel tile, then next tile.
for tile in range(4):
    for group4 in range(8):
        for p in range(16):
            pixel = tile * 16 + p
            transaction(1, 0, 0x20000 + pixel * 16)
            write(1, 0x4000 + (group4 // 4) * 1024 + pixel * 16 + (group4 % 4) * 4, 4)
transaction(1, 0, 0x2C000)  # Unrelated cache miss while a full line drains.
transaction(1, 2)

for tile in range(4):
    for group4 in range(8):
        for p in range(16):
            pixel = tile * 16 + p
            transaction(2, 0, 0x21000 + pixel * 16)
            write(2, 0x8000 + (group4 // 4) * 4096 + pixel * 64 + (group4 % 4) * 16, 16)
transaction(2, 2)

# INT16 head, DW full beats, interleaved Add sources, and both sides of 4KiB.
for group4 in range(2):
    for p in range(64):
        write(3, 0xC000 + group4 * 512 + p * 8, 8)
for p in range(96):
    transaction(3, 0, 0x22000 + p * 32)
    transaction(3, 0, 0x28000 + p * 32)
    write(3, 0xD000 + p * 32, 32)
transaction(3, 2)
for address in (0xFE0, 0x1000, 0x1FE0, 0x2000, 0x3FFE0):
    write(4, address + 7, 13)
    transaction(4, 0, address)  # Read must observe the buffered masked write.
transaction(4, 2)
for _ in range(80):
    address = rng.randrange(0x10000, 0x18000) & ~31
    mask = rng.getrandbits(32)
    transaction(4, 1, address, mask, rng.randbytes(32))
    transaction(4, 0, address)
transaction(4, 2)

# Legacy DDR ownership can change memory without going through this cache.
transaction(5, 0, 0x20000)
transaction(5, 3, 0x20000, 0xFFFFFFFF, rng.randbytes(32))
transaction(5, 0, 0x20000)
for address in range(0x3F00, 0x4900, 32):
    transaction(5, 0, address)
transaction(5, 2)

for filename, content in (("stimulus.hex", stimulus), ("golden.hex", golden),
                          ("memory_init.hex", [f"{b:02x}" for b in initial]),
                          ("memory_golden.hex", [f"{b:02x}" for b in memory])):
    (ROOT / filename).write_text("\n".join(content) + "\n", encoding="ascii")
(ROOT / "counts.svh").write_text(f"`define DDR_TRANSACTIONS {len(stimulus)}\n", encoding="ascii")
print(json.dumps({"transactions": len(stimulus), "phases": phases, "seed": 20261017}))

# Frozen tumor coefficients live in DDR on the board; preserve the original bytes.
coe = (ROOT.parents[3] / "src/host/python/bin_udp/assets/quantized_params_rom_full.coe").read_text(encoding="ascii")
words = coe.split("memory_initialization_vector=", 1)[1].replace(";", "").replace(",", " ").split()
coefficients = b"".join(int(word, 16).to_bytes(8, "little") for word in words)
tumor = coefficients[0x59600:0x1BD240]
assert len(tumor) == 1457216
(ROOT / "tumor_coefficients.hex").write_text("\n".join(f"{b:02x}" for b in tumor) + "\n", encoding="ascii")
print(json.dumps({"tumor_ddr_base": "0x08000000", "coefficient_bytes": len(tumor)}))
