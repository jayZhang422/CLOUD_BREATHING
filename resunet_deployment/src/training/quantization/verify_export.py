#!/usr/bin/env python3
"""直接读取冻结 .bin/contract，逐节点核对合成 Golden；不需要 FP32 权重或数据集。"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import torch
from torch import nn

from mkdc_int8 import BLOCKS, DeploymentNet


class FrozenIntegerNet(DeploymentNet):
    """沿用整数图，只加载实际导出的权重、乘数、移位和固定偏置。"""
    def __init__(self, export_dir, device='cpu'):
        nn.Module.__init__(self)
        export_dir = Path(export_dir)
        contract = json.loads((export_dir / 'contract.json').read_text(encoding='utf-8'))
        self.mode = 'integer'
        self.capture = None
        self.scales = contract['activation_scales']
        self.identity_skip = {name: name + '.skip' not in contract['convolutions'] for name in BLOCKS}
        self.packed = {}
        self.merges = {}
        for name, config in contract['convolutions'].items():
            weight = torch.from_numpy(np.fromfile(export_dir / config['file'], dtype=np.int8)
                                      .reshape(config['shape'])).to(device)
            scale = torch.tensor(config['weight_scale'], dtype=torch.float64)
            # 偏置已冻结在各 merge 的 bias_fixed 中，推理不再从浮点偏置重算。
            self.packed[name] = {'weight': weight, 'scale': scale,
                'bias': torch.zeros_like(scale), 'bound': weight.cpu().long().abs().flatten(1).sum(1) * 128,
                'groups': config['groups'], 'padding': config['padding']}
        for name, config in contract['merges'].items():
            bias = np.fromfile(export_dir / config['bias_file'], dtype='<i8')
            self.merges[name] = {**config, 'bias_fixed': torch.from_numpy(bias).to(device),
                'multipliers': [torch.tensor(value, dtype=torch.int64, device=device)
                                for value in config['multipliers']]}


def verify(export_dir, device='cpu'):
    export_dir = Path(export_dir)
    # 先检查落盘文件，再运行冻结整数图，避免仅验证从浮点包重建的另一份参数。
    hashes = json.loads((export_dir / 'sha256.json').read_text(encoding='utf-8'))
    for name, expected in hashes.items():
        actual = hashlib.sha256((export_dir / name).read_bytes()).hexdigest()
        if actual != expected:
            raise RuntimeError(f'SHA256 mismatch: {name}')
    vectors = export_dir / 'golden_synthetic_32x32'
    manifest = json.loads((vectors / 'manifest.json').read_text(encoding='utf-8'))['tensors']
    def read(name):
        config = manifest[name]
        return torch.from_numpy(np.fromfile(vectors / (name + '.bin'), dtype=config['dtype'])
                                .reshape(config['shape']))
    torch.set_num_threads(4)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True
    model = FrozenIntegerNet(export_dir, device)
    model.capture = {}
    x = read('input')
    with torch.inference_mode():
        model(x.to(device))
    trace = {'input': x, **model.capture}
    if set(trace) != set(manifest):
        raise RuntimeError('Golden node list differs from integer graph')
    for name, value in trace.items():
        if not torch.equal(value.cpu(), read(name)):
            raise RuntimeError(f'Frozen binary Golden mismatch: {name}')
    return {'status': 'PASS', 'device': device, 'checked_files': len(hashes),
        'checked_nodes': len(trace), 'checked_elements': sum(value.numel() for value in trace.values()),
        'parameters': 'actual INT8 weight bins and contract INT64 bias/multiplier/shift; no FP32 reconstruction',
        'scope': 'synthetic 32x32; software verification, not RTL or board acceptance'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', type=Path, required=True)
    parser.add_argument('--device', choices=('cpu', 'cuda'), default='cpu')
    args = parser.parse_args()
    print(json.dumps(verify(args.export, args.device), indent=2, ensure_ascii=False))
