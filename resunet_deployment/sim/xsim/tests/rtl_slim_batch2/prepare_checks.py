"""第二批专用：冻结参考模块、复用已验收Golden，生成接口边界向量。"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import struct

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCE = ROOT / 'src/rtl/op/control'
OLD = HERE.parent / 'rtl_slim_batch1'
mkdc = HERE.parent / 'mkdc/vectors'
VECTORS = HERE / 'vectors'
VECTORS.mkdir(exist_ok=True)

for module in ('op_engine', 'op_core_bank', 'op_descriptor_check', 'op_feature_writer'):
    text = (HERE / 'before' / (module + '.sv')).read_text(encoding='utf-8-sig')
    for name in ('op_engine', 'op_core_bank', 'op_descriptor_check', 'op_feature_writer'):
        text = re.sub(r'\b' + name + r'\b', name + '_batch2_before', text)
    (HERE / (module + '_batch2_before.sv')).write_text(text, encoding='utf-8')

# 第一批已通过的op12边界向量不重新计算；参考换为本轮前真实工作树。
text = (OLD / 'tb_rtl_slim_op12.sv').read_text(encoding='utf-8')
text = text.replace('tb_rtl_slim_op12', 'tb_batch2_op12')
text = text.replace('op_engine_before baseline', 'op_engine_batch2_before baseline')
text = text.replace('baseline.u_bank.p12_add_a_data_r', 'baseline.u_bank.p12_add_a_data_w')
text = text.replace('baseline.u_bank.p12_add_b_data_r', 'baseline.u_bank.p12_add_b_data_w')
(HERE / 'tb_batch2_op12.sv').write_text(text, encoding='utf-8')

# 所有writer长度1..32、地址低5位，以及64/144/400B调试导出。
stimuli, expected = [], []
for length in list(range(1, 33)) + [64, 144, 400]:
    for offset in range(32):
        address = 0x02400000 + offset
        payload = bytes((b * 29 + length * 7 + offset * 13) & 255 for b in range(400))
        stimuli.append(f'{(address << 3209) | (length << 3200) | int.from_bytes(payload, "little"):0810x}\n')
        cursor = 0
        while cursor < length:
            at = address + cursor
            count = min(32 - (at & 31), length - cursor)
            data = int.from_bytes(payload[cursor:cursor+count], 'little') << ((at & 31) * 8)
            mask = ((1 << count) - 1) << (at & 31)
            expected.append(f'{((at & ~31) << 288) | (mask << 256) | data:080x}\n')
            cursor += count
(VECTORS / 'writer_stimulus.hex').write_text(''.join(stimuli), encoding='ascii')
(VECTORS / 'writer_golden.hex').write_text(''.join(expected), encoding='ascii')

def write_hex(path, data):
    path.write_text(''.join(f'{b:02x}\n' for b in data), encoding='ascii')

production = ['lobe_mid_expand', 'edge_pw_raw_p16_multitile', 'lobe_mid_mix', 'lobe_mid_out',
              'legacy_lobe_head', 'legacy_pool_odd_two_groups',
              'legacy_shuffle16', 'legacy_pool_groups32']
debug = ['legacy_linebuffer3', 'legacy_linebuffer5', 'lobe_mid_dw3', 'lobe_mid_dw5']
old_cases = {row.split()[0]: row.split()[1:] for row in (mkdc / 'cases_all.txt').read_text().splitlines()}
# mkdc原中间层是连续链用例；这里仅验证改动过的接口，显式使用冻结上游张量作为单层输入。
unit_inputs = {'lobe_mid_mix': [(16, 'lobe_mid_dw3'), (20, 'lobe_mid_dw5')],
               'lobe_mid_out': [(16, 'lobe_mid_project'), (20, 'lobe_mid_skip')],
               'lobe_mid_dw3': [(16, 'lobe_mid_expand')],
               'lobe_mid_dw5': [(16, 'lobe_mid_expand')]}
def case_row(name):
    folder = mkdc / name
    if name in unit_inputs:
        folder = VECTORS / name
        folder.mkdir(exist_ok=True)
        for filename in ('descriptor.hex', 'golden.hex'):
            shutil.copyfile(mkdc / name / filename, folder / filename)
        desc = bytes.fromhex((folder / 'descriptor.hex').read_text())
        uploads = []
        for offset, source in unit_inputs[name]:
            address = struct.unpack_from('<I', desc, offset)[0]
            path = mkdc / source / 'golden.hex'
            length = len(bytes.fromhex(path.read_text()))
            uploads.append(f'{address:08x} {length} {path.as_posix()}\n')
        (folder / 'uploads.txt').write_text(''.join(uploads), encoding='ascii')
    return f'{folder.as_posix()} ' + ' '.join(old_cases[name]) + '\n'
prod_rows = [case_row(name) for name in production]
debug_rows = [case_row(name) for name in debug]

def custom_case(name, op, width, height, payload, golden, **kwargs):
    folder = VECTORS / name
    folder.mkdir(exist_ok=True)
    descriptor = bytearray(64)
    descriptor[0] = op
    descriptor[2:4] = bytes((16, 16))
    struct.pack_into('<HHH', descriptor, 4, width, height, 1)
    descriptor[12] = 127
    for offset, value in ((16, 0x02000000), (24, 0x02400000), (28, kwargs.get('wb', 0)),
                          (32, kwargs.get('wa', 0)), (36, kwargs.get('params', 0))):
        struct.pack_into('<I', descriptor, offset, value)
    write_hex(folder / 'descriptor.hex', descriptor)
    write_hex(folder / 'golden.hex', golden)
    write_hex(folder / 'input.hex', payload)
    uploads = [f'02000000 {len(payload)} {folder.as_posix()}/input.hex\n']
    for field, address in (('weights_a', kwargs.get('wa')), ('weights_b', kwargs.get('wb')),
                           ('params_data', kwargs.get('params'))):
        if field in kwargs:
            write_hex(folder / (field + '.hex'), kwargs[field])
            uploads.append(f'{address:08x} {len(kwargs[field])} {folder.as_posix()}/{field}.hex\n')
    (folder / 'uploads.txt').write_text(''.join(uploads), encoding='ascii')
    return f'{folder.as_posix()} {len(golden)} 0\n'

# op10行/组次序；op11脉冲的3x3和5x5支持域，离线Golden。
image = [bytes((p * 17 + lane) & 255 for lane in range(16)) for p in range(6)]
up = b''.join(image[(y//2)*3+x//2] for y in range(4) for x in range(6))
prod_rows.append(custom_case('upsample', 10, 3, 2, b''.join(image), up))
concat_a = bytes((b * 3 + 5) & 255 for b in range(48))
concat_b = bytes((b * 7 + 19) & 255 for b in range(48))
prod_rows.append(custom_case('concat', 5, 3, 1, concat_a, concat_a + concat_b))
concat_dir = VECTORS / 'concat'
concat_desc = bytearray.fromhex((concat_dir / 'descriptor.hex').read_text())
struct.pack_into('<I', concat_desc, 20, 0x02200000)
struct.pack_into('<H', concat_desc, 14, 1)
write_hex(concat_dir / 'descriptor.hex', concat_desc)
write_hex(concat_dir / 'input_b.hex', concat_b)
with (concat_dir / 'uploads.txt').open('a', encoding='ascii') as stream:
    stream.write(f'02200000 48 {concat_dir.as_posix()}/input_b.hex\n')
input11 = b''.join(bytes([int(x == 3 and y == 3)] * 16) for y in range(7) for x in range(7))
gold11 = b''.join(bytes([int(2 <= x <= 4 and 2 <= y <= 4) + int(1 <= x <= 5 and 1 <= y <= 5)] * 16)
                   for y in range(7) for x in range(7))
params = b''.join(struct.pack('<iiq', 1, 1, 0) for _ in range(16))
prod_rows.append(custom_case('fused_dw11', 11, 7, 7, input11, gold11,
                            wa=0x08000000, wb=0x08001000, params=0x08002000,
                            weights_a=bytes([1] * 144), weights_b=bytes([1] * 400), params_data=params))
prod_rows.append(custom_case('pw_tail_clear', 1, 3, 1, bytes(48), bytes(48),
                            wa=0x08000000, params=0x08002000,
                            weights_a=bytes(128), params_data=bytes(128)))
tail = bytearray.fromhex(''.join((VECTORS / 'pw_tail_clear/descriptor.hex').read_text().split()))
tail[2:4] = bytes((1, 5))
write_hex(VECTORS / 'pw_tail_clear/descriptor.hex', tail)
(HERE / 'production_cases.txt').write_text(''.join(prod_rows), encoding='ascii')
(HERE / 'debug_cases.txt').write_text(''.join(debug_rows), encoding='ascii')

coe = (ROOT / 'src/params/quantized_params_rom.coe').read_text()
rom = b''.join(int(word.strip(), 16).to_bytes(8, 'little')
               for word in coe.split('memory_initialization_vector=')[1].strip().rstrip(';').split(','))
write_hex(VECTORS / 'coeff.hex', rom)

# engine外部接口完全不变，可直接复用第一批接口声明/接线。
pair = text.split('localparam string CHECK_ROOT', 1)[0]
pair = pair.replace('module tb_batch2_op12;', "module tb_batch2_engine #(parameter bit WIDE_DEBUG = 1'b0);")
pair = pair.replace('op_engine dut (', 'op_engine #(.ENABLE_WIDE_DEBUG(WIDE_DEBUG)) dut (')
(HERE / 'tb_batch2_engine.sv').write_text(pair + (HERE / 'engine_body.svh').read_text(encoding='utf-8'), encoding='utf-8')

hashes = {str(path.relative_to(ROOT)).replace('\\', '/'): hashlib.sha256(path.read_bytes()).hexdigest()
          for path in sorted(VECTORS.rglob('*.hex'))}
(HERE / 'results/vectors_sha256.json').write_text(json.dumps(hashes, indent=2), encoding='utf-8')
print(f'Prepared writer_requests={len(stimuli)} writer_transactions={len(expected)} production_cases={len(prod_rows)} debug_cases={len(debug_rows)} coeff_bytes={len(rom)}')
