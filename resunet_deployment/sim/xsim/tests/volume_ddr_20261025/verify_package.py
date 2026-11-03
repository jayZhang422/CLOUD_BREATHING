"""只读参考冻结模型；验证独立PC交付资产、张量生命周期及当前病例清单。"""
from pathlib import Path
import hashlib
import json
import struct
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / 'src/host/python/bin_udp'))
sys.path.insert(0, str(ROOT / 'src/host/python/pc_fpga_app'))
from src.fullnet import NetworkPlan, coefficient_image
from fixed_fpga_benchmark import fuse_residual_plan
from pc_fpga.ethernet.volume import build_program, ASSETS, IMAGE_BASE, SCRIPT_BASE, MAP_BASE, RESULT_BASE


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def main():
    image = coefficient_image()
    assets = json.loads((ASSETS / 'volume_plans.json').read_text(encoding='utf-8'))
    audit = {'scope': 'offline package equivalence and layout; no board inference', 'models': {}}
    for task, saved in assets.items():
        plan = NetworkPlan(task, image)
        fuse_residual_plan(plan)
        skip_cin = {s['name']: struct.unpack_from('<H', s['descriptor'], 56)[0]
                    for s in plan.stages if s['op'] == 12}
        plan.allocate()
        expected = []
        for stage in plan.stages:
            cmd = bytearray(stage['descriptor'])
            if stage['op'] == 12:
                struct.pack_into('<H', cmd, 56, skip_cin[stage['name']])
            for offset in (16, 20, 24):
                address = struct.unpack_from('<I', cmd, offset)[0]
                if address:
                    struct.pack_into('<I', cmd, offset, address + 0x01000000)
            expected.append(dict(name=stage['name'], descriptor_hex=cmd.hex()))
        assert expected == saved['stages'], (task, 'descriptor semantics differ')
        assert saved['input'] == plan.tensors['input']['address'] + 0x01000000
        assert saved['head'] == plan.tensors['head']['address'] + 0x01000000
        assert saved['arena_end'] == plan.arena_end + 0x01000000 <= RESULT_BASE
        assert saved['contract_sha256'] == plan.contract_sha256
        for index, stage in enumerate(plan.stages):
            live = [t for t in plan.tensors.values() if t['produced'] <= index <= t['last']]
            for i, a in enumerate(live):
                for b in live[i + 1:]:
                    assert not (a['address'] < b['address'] + b['bytes'] and
                                b['address'] < a['address'] + a['bytes']), (task, stage['name'])
        audit['models'][task] = dict(stages=len(expected), input=saved['input'], head=saved['head'],
            arena_end=saved['arena_end'], scratch_bytes=saved['arena_end'] - 0x0a000000,
            contract_sha256=plan.contract_sha256, export_sha256=plan.export_sha256,
            descriptors_sha256=sha(b''.join(bytes.fromhex(s['descriptor_hex']) for s in expected)))
        if task == 'tumor':
            assert (ASSETS / 'tumor.params.bin').read_bytes() == plan.parameters
    metadata_path = ROOT / 'src/host/python/bin_udp/output/ct_01/input/metadata.json'
    metadata = json.loads(metadata_path.read_text(encoding='utf-8'))
    spec = metadata['model_input']
    job = dict(input=dict(shape=spec['shape'], ddr_base=IMAGE_BASE, sha256=spec['sha256']))
    program, maps, header, models = build_program(job, metadata, assets)
    depth = spec['shape'][0]
    count = len(program) // 96
    assert struct.unpack('<8I', header[:32]) == (0x314c4f56, 1, SCRIPT_BASE, count,
        IMAGE_BASE, depth, RESULT_BASE, depth * 524288)
    assert program[-96:] == bytes([255]) + bytes(95)
    coverage = {0: [], 5: [], 6: [], 8: []}
    for offset in range(0, len(program) - 96, 96):
        kind, cmd = program[offset], program[offset + 32:offset + 96]
        if kind == 3:
            coverage[cmd[3]].append((struct.unpack_from('<I', cmd, 8)[0] - RESULT_BASE) // 524288)
    assert all(sorted(slices) == list(range(depth)) for slices in coverage.values())
    audit['case'] = dict(metadata=str(metadata_path), depth=depth, input_sha256=spec['sha256'],
        input_bytes=depth * 262144, input_end=IMAGE_BASE + depth * 262144,
        result_bytes=depth * 524288, result_end=RESULT_BASE + depth * 524288,
        command_count=count, program_bytes=len(program), maps_bytes=len(maps),
        program_end=SCRIPT_BASE + len(program), maps_end=MAP_BASE + len(maps),
        program_sha256=sha(program), maps_sha256=sha(maps), models=models)
    audit['assets'] = {name: dict(bytes=(ASSETS / name).stat().st_size,
        sha256=sha((ASSETS / name).read_bytes())) for name in ('volume_plans.json', 'tumor.params.bin')}
    destination = HERE / 'results/package_audit.json'
    destination.write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('[PACKAGE PASSED] four frozen plans, tensor lifetimes, tumor parameters and full-volume output coverage')
    print(json.dumps(audit['case'], ensure_ascii=False))


if __name__ == '__main__':
    main()
