"""冻结 lobe e1 参数的独立 NumPy Golden；不更改模型或 ROM。"""
import json
import struct
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EXPORT = ROOT / 'src/params/int8/lobe'
CONTRACT = json.loads((EXPORT / 'contract.json').read_text(encoding='utf-8'))
PLAN = json.loads((ROOT / 'src/host/python/pc_fpga_app/assets/volume_plans.json').read_text(encoding='utf-8'))['lobe']


def save(path, raw):
    path.write_text(''.join(f'{b:02x}\n' for b in raw), encoding='ascii')


def quantize(values, name):
    spec = CONTRACT['merges'][name]
    multipliers = np.asarray(spec['multipliers'], dtype=np.int64)
    total = sum(value * scale[:, None, None] for value, scale in zip(values, multipliers))
    total += np.fromfile(EXPORT / spec['bias_file'], dtype='<i8')[:, None, None]
    unit = 1 << spec['shift']
    q, r = np.divmod(total, unit)
    return np.clip(q + ((r * 2 > unit) | ((r * 2 == unit) & ((q & 1) != 0))), 0, 127).astype(np.int8)


def weight(name):
    spec = CONTRACT['convolutions'][name]
    return np.fromfile(EXPORT / spec['file'], dtype=np.int8).reshape(spec['shape']).astype(np.int64)


for name, height in [('stall_lobe_row512', 8), ('stall_lobe_frame512', 512)]:
    folder = HERE / 'vectors' / name
    folder.mkdir(parents=True, exist_ok=True)
    x = np.random.default_rng(20261025).integers(-128, 128, (3, height, 512), dtype=np.int16).astype(np.int8)
    expanded = quantize([(weight('e1.expand')[:, :, 0, 0] @ x.reshape(3, -1).astype(np.int64)).reshape(16, height, 512)], 'e1.expand')
    branches = []
    for k in (3, 5):
        w = weight(f'e1.dw{k}')
        padded = np.pad(expanded.astype(np.int64), ((0, 0), (k // 2, k // 2), (k // 2, k // 2)))
        acc = np.zeros_like(expanded, dtype=np.int64)
        for y in range(k):
            for col in range(k):
                acc += padded[:, y:y+height, col:col+512] * w[:, 0, y, col, None, None]
        branches.append(acc)
    golden = quantize(branches, 'e1.mix')
    packed = np.zeros((height, 512, 16), dtype=np.int8)
    packed[:, :, :3] = x.transpose(1, 2, 0)
    save(folder / 'input.hex', packed.tobytes())
    save(folder / 'expanded.hex', expanded.transpose(1, 2, 0).tobytes())
    save(folder / 'golden.hex', golden.transpose(1, 2, 0).tobytes())
    for stage, filename in [('e1.expand', 'prefix_descriptor.hex'), ('e1.mix', 'descriptor.hex')]:
        desc = bytearray.fromhex(next(s['descriptor_hex'] for s in PLAN['stages'] if s['name'] == stage))
        struct.pack_into('<H', desc, 6, height)
        struct.pack_into('<I', desc, 48, 0)
        save(folder / filename, desc)
    (folder / 'uploads.txt').write_text(f'0a000000 {packed.size} {(folder / "input.hex").as_posix()}\n', encoding='ascii')
    (HERE / f'{name}.txt').write_text(f'{name} {golden.size} 0\n', encoding='ascii')
    print(name, golden.size)
