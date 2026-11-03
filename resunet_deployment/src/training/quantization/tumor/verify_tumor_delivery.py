#!/usr/bin/env python3
"""从实际冻结 .bin 验证 Golden、四档尺寸 MAC 抽查及完整 512 输出。"""
import argparse
import json
from pathlib import Path
import time

import torch
from torch.nn import functional as F

from mkdc_int8 import BLOCKS
from run_quantization import sha, write_json
from verify_export import FrozenIntegerNet, verify


def spatial_check(export_dir):
    contract = json.loads((export_dir / 'contract.json').read_text())
    results = []
    torch.manual_seed(20261012)
    model = FrozenIntegerNet(export_dir, 'cuda')
    with torch.inference_mode():
        for size in (64, 128, 256, 512):
            x = torch.randint(-128, 128, (1, 3, size, size), dtype=torch.int8)
            model.capture = {}
            model(x.cuda())
            trace = {'input': x, **model.capture}
            model.capture = None
            block_input = {'e1': x}
            for name, previous in (('e2', 'e1'), ('e3', 'e2'), ('mid', 'e3')):
                block_input[name] = F.max_pool2d(trace[previous + '.out'].float(), 2).to(torch.int8)
            for name in ('d3', 'd2', 'd1'):
                block_input[name] = torch.cat([trace[name + '.concat_up'], trace[name + '.concat_skip']], 1)
            checked = 0
            for name, cfg in contract['convolutions'].items():
                if name == 'head':
                    inputs = trace['d1.out']
                else:
                    block, operation = name.split('.')
                    inputs = (block_input[block] if operation in ('expand', 'skip') else
                              trace[block + ('.expand' if operation.startswith('dw') else '.mix')])
                weights = model.packed[name]['weight'].cpu().long()
                actual = trace[name + '.mac']
                _, channels, height, width = inputs.shape
                points = sorted({(0, 0), (height // 2, width // 2), (height - 1, width - 1)})
                kernel = weights.shape[-1]
                for y, x_pos in points:
                    expected = torch.zeros(weights.shape[0], dtype=torch.int64)
                    for ky in range(kernel):
                        for kx in range(kernel):
                            iy, ix = y + ky - cfg['padding'], x_pos + kx - cfg['padding']
                            if 0 <= iy < height and 0 <= ix < width:
                                values = inputs[0, :, iy, ix].long()
                                if cfg['groups'] == 1:
                                    expected += weights[:, :, ky, kx] @ values
                                else:
                                    assert cfg['groups'] == channels == weights.shape[0]
                                    expected += weights[:, 0, ky, kx] * values
                    assert torch.equal(expected, actual[0, :, y, x_pos].long()), (size, name, y, x_pos)
                    checked += expected.numel()
            results.append({'input_size': size, 'checked_elements': checked, 'status': 'PASS'})
            print('MAC_SPATIAL_PASS', size, checked, flush=True)
            del trace, block_input
    return {'status': 'PASS', 'scope': 'all convolution nodes; two corners and center; independent CPU INT64 sums',
            'checks': results, 'checked_elements': sum(row['checked_elements'] for row in results)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    run = args.run
    reports = json.loads((run / 'results.json').read_text())['tumor']
    selected = 'ptq' if reports['ptq_pass'] else 'qat'
    full = reports['ptq'] if selected == 'ptq' else reports['qat']
    precision_pass = all(row['dice_gate_pass'] for row in full.values())
    export_dir = run / 'tumor' / selected / 'export'
    write_json(export_dir.parent / 'frozen_binary_verification.json', verify(export_dir, 'cpu'))
    write_json(run / 'mac_spatial_check.json', spatial_check(export_dir))
    started = time.monotonic()
    x = torch.randint(-128, 128, (1, 3, 512, 512), dtype=torch.int8,
                      generator=torch.Generator().manual_seed(20261012))
    with torch.inference_mode():
        expected = FrozenIntegerNet(export_dir, 'cuda')(x.cuda()).cpu()
        actual = FrozenIntegerNet(export_dir, 'cpu')(x)
    assert torch.equal(expected, actual), '512x512 CPU/CUDA integer output differs'
    write_json(export_dir.parent / 'full_512_synthetic_verification.json', {
        'status': 'PASS', 'shape': list(x.shape), 'seed': 20261012,
        'checked_output_elements': expected.numel(), 'seconds': time.monotonic() - started,
        'source': 'synthetic; no patient CT or labels', 'scope': 'actual frozen bins; complete CPU/CUDA integer output'})
    before = json.loads((run / 'original_sha256_before.json').read_text())
    after = {path: sha(path) for path in before}
    assert before == after, 'Original checkpoint changed'
    write_json(run / 'original_sha256_after_delivery.json', after)
    write_json(run / 'acceptance.json', {'version': run.name, 'task': 'tumor', 'base': 64,
        'original_epoch': 70, 'selected': selected.upper(), 'precision_pass': precision_pass,
        'qat_executed': not reports['ptq_pass'], 'originals_unchanged': True,
        'integer_binary_golden': 'PASS', 'integer_mac_spatial': 'PASS', 'integer_full_512': 'PASS',
        'accepted': precision_pass, 'gate': 'each source union and each supervised class Dice drop <=0.02 absolute',
        'case_count': sum(row['fp32']['case_count'] for row in full.values()),
        'slice_count': sum(row['fp32']['slice_count'] for row in full.values()),
        'datasets': full, 'scope': 'complete validation; no test-set tuning; software, not RTL/board acceptance'})
    print('TUMOR_DELIVERY_VERIFIED', 'ACCEPTED' if precision_pass else 'PRECISION_FAILED', flush=True)


if __name__ == '__main__':
    main()
