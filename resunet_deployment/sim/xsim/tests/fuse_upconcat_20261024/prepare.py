"""Independent byte oracle for nearest-neighbor resize followed by channel concat."""
from pathlib import Path
import struct
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'src/host/python/bin_udp'))
from src.op_client import descriptor

A, B, Q, U = 0x02000000, 0x02800000, 0x03000000, 0x03800000
CASES = [('tiny', 1, 1, 1, 1, 0), ('odd', 3, 5, 2, 1, 16),
         ('rect', 7, 3, 1, 3, 0), ('width256', 256, 1, 1, 1, 16),
         ('height256', 1, 256, 1, 1, 0), ('groups32', 16, 2, 32, 32, 16),
         ('d1_small', 16, 16, 2, 1, 0), ('tumor_d1', 16, 16, 8, 4, 0),
         ('d1_row', 256, 4, 2, 1, 0)]

def hexfile(path, data):
    path.write_text(''.join(f'{b:02x}\n' for b in data), encoding='ascii')

manifest, rpc = [], []
for index, (name, w, h, ga, gb, offset) in enumerate(CASES):
    folder = HERE / 'vectors' / ('fuse_' + name)
    folder.mkdir(parents=True, exist_ok=True)
    source = bytes((g*53+y*31+x*17+l*7+index) & 255
                   for g in range(ga) for y in range(h) for x in range(w) for l in range(16))
    skip = bytes((g*47+y*13+x*29+l*11+123) & 255
                 for g in range(gb) for y in range(h*2) for x in range(w*2) for l in range(16))
    up = b''.join(source[((g*h+y//2)*w+x//2)*16:((g*h+y//2)*w+x//2+1)*16]
                  for g in range(ga) for y in range(h*2) for x in range(w*2))
    for filename, data in [('input.hex', source), ('skip.hex', skip), ('up.hex', up), ('golden.hex', up+skip)]:
        hexfile(folder / filename, data)
    desc = descriptor(13, index+1, width=w, height=h, groups=ga, groups_b=gb, cin=0, cout=0,
                      base_a=A+offset, base_b=B+offset, output=Q)
    hexfile(folder / 'descriptor.hex', desc)
    (folder / 'uploads.txt').write_text(
        f'{A+offset:08x} {len(source)} {(folder/"input.hex").as_posix()}\n'
        f'{B+offset:08x} {len(skip)} {(folder/"skip.hex").as_posix()}\n', encoding='ascii')
    manifest.append(f'fuse_{name} {w} {h} {ga} {gb} {offset} {len(source)} {len(skip)} {len(up+skip)}\n')
    if name in ('tiny', 'odd', 'groups32', 'd1_small', 'tumor_d1', 'd1_row'):
        rpc.append(f'fuse_{name} {len(up+skip)} 0\n')
(HERE/'cases.txt').write_text(''.join(manifest), encoding='ascii')
# Existing production RPC regression is retained, followed by six fused cases.
old = (HERE.parent/'p8p16_pending/rpc_cases.txt').read_text(encoding='ascii')
(HERE/'rpc_cases.txt').write_text(old + ''.join(rpc), encoding='ascii')
print(f'Generated {len(CASES)} independent resize/concat cases and 6 new RPC cases')
