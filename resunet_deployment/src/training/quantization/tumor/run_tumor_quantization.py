#!/usr/bin/env python3
"""复用三任务流程量化肿瘤 base64 epoch70；原权重与数据缓存只读。"""
import copy
import json
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True
import numpy as np
import torch

import run_quantization as common
from task06_cache_reader_v2 import Task06Case
from task06_tumor_loss_v3 import loss_value
from tumor_model import ResUNet


TRAIN_RUN = common.BASE / 'tumor_base64_supervised_100e_v1'
EPOCH70 = TRAIN_RUN / 'stop_snapshot_20261012_epoch0090/checkpoint/best_epoch_0070.pt'
EXPECTED = '556d048f668560c66789369bcc491351a76249de820353c6b52d1ce645849f45'
PREVIOUS_SPECS = dict(common.SPECS)
common.SPECS = {'tumor': (TRAIN_RUN.name, 'config.json', 70, 1, EXPECTED)}


def check_originals():
    paths = [EPOCH70, TRAIN_RUN / 'best.pt', TRAIN_RUN / 'last.pt']
    for directory, _, epoch, _, expected in PREVIOUS_SPECS.values():
        for suffix in ('best.pt', f'best_records/best_epoch_{epoch:04d}.pt'):
            path = common.BASE / directory / suffix
            assert common.sha(path) == expected, f'Previous original changed: {path}'
            paths.append(path)
    assert all(common.sha(p) == EXPECTED for p in paths[:2])
    return {str(path): common.sha(path) for path in paths}


def freeze(run):
    hashes = check_originals()
    previous = run / 'original_sha256_before.json'
    if previous.exists():
        assert json.loads(previous.read_text()) == hashes
    else:
        common.write_json(previous, hashes)
    target = run / 'fp32/tumor'
    target.mkdir(parents=True, exist_ok=True)
    for source, name in ((EPOCH70, 'best_epoch_0070.pt'),
                         (TRAIN_RUN / 'config.json', 'config.json'),
                         (TRAIN_RUN / 'patient_split.json', 'patient_split.json')):
        output = target / name
        if not output.exists():
            shutil.copyfile(source, output)
        assert common.sha(output) == common.sha(source)


class Case:
    """适配原量化流程的三元输入；所有肿瘤缓存均为完整 512×512。"""
    def __init__(self, root, metadata):
        self.reader = Task06Case(root, metadata)
        self.zdim = self.reader.zdim
        self.region = (slice(0, 512), slice(0, 512))

    def read_sample(self, z):
        x, y = self.reader.read_sample(z)
        return x, y.astype(np.float32), np.ones((1, 1, 1), dtype=np.float32)


class Cache:
    def __init__(self, root):
        self.root = root
        self.metadata = json.loads((root / 'metadata.json').read_text())
        self.rows = {row['case']: row for row in self.metadata['cases']}
        self.target_names = ['tumor']
        self.opened = {}

    def open_case(self, cid):
        if cid not in self.opened:
            if len(self.opened) >= 8:
                self.opened.pop(next(iter(self.opened)))
            self.opened[cid] = Case(self.root, self.rows[cid])
        return self.opened[cid]

    def positive_slices(self, cid):
        return self.rows[cid]['positive_slices']


def sources():
    original_source = common.BASE / PREVIOUS_SPECS['lobe'][0] / 'source'
    sys.path.insert(0, str(original_source))
    sys.path.insert(0, str(common.BASE))
    metrics = common.import_file('previous_quantization_metrics', original_source / 'train_compact_mkdc_v1.py')
    # 若 PTQ 不达标才进行 QAT，损失沿用肿瘤原训练配方。
    metrics.masked_loss = lambda logits, target, valid: loss_value(logits, target)
    return metrics, None


def load_task(run, task, metrics, unused):
    checkpoint = torch.load(run / 'fp32/tumor/best_epoch_0070.pt', map_location='cpu', weights_only=False)
    assert checkpoint['epoch'] == checkpoint['best_epoch'] == 70
    assert checkpoint['config']['base'] == 64
    original = ResUNet(out_channels=1, base=64).eval()
    original.load_state_dict(checkpoint['model'], strict=True)
    assert all(torch.isfinite(value).all() for value in original.state_dict().values())
    splits = json.loads((run / 'fp32/tumor/patient_split.json').read_text())
    assert [len(splits[key]) for key in ('train', 'val', 'test')] == [344, 73, 66]
    all_ids = sum(splits.values(), [])
    assert len(all_ids) == len(set(all_ids))
    cfg = json.loads((run / 'fp32/tumor/config.json').read_text())
    assert common.sha(run / 'fp32/tumor/patient_split.json') == cfg['split_sha256']
    datasets, hash_partition = {}, {}
    for source, root_name in (('Task06', 'task06_tumor_cache_v1'), ('NSCLC', 'nsclc_radiomics_cache_v1')):
        cache = Cache(common.BASE / root_name)
        assert common.sha(cache.root / 'metadata.json') == cfg['cache_metadata_sha256'][source]
        assert cache.metadata['all_slices']
        selected = {part: [cid.split('/', 1)[1] for cid in ids if cid.startswith(source + '/')]
                    for part, ids in splits.items()}
        assert set(sum(selected.values(), [])) <= set(cache.rows)
        for part, ids in selected.items():
            for cid in ids:
                image_hash = cache.rows[cid]['image_sha256']
                assert hash_partition.setdefault(image_hash, part) == part
        datasets[source] = cache, selected
    contracts = [cache.metadata['input_contract'] for cache, _ in datasets.values()]
    assert contracts[0] == contracts[1]
    return original, datasets


previous_export = common.export


def export(run, task, model, original, target):
    previous_export(run, task, model, original, target)
    contract_path = target / 'contract.json'
    contract = json.loads(contract_path.read_text())
    contract.update({'model_base': 64, 'channels': [64, 128, 256, 512], 'original_epoch': 70,
                     'max_input_channels': 768, 'max_output_channels': 512,
                     'grouping': 'hardware lane P=16; runtime channel groups up to Cin=768/Cout=512; input3 and head1 require valid-lane masks'})
    mac_bounds = {}
    for name, packed in model.packed.items():
        bound = packed['weight'].cpu().long().abs().flatten(1).sum(1) * 128
        assert int(bound.max()) < 2**24
        mac_bounds[name] = bound.tolist()
    merge_bounds = {}
    for name, config in model.merges.items():
        if '.concat_' in name:
            parts = [torch.full_like(config['bias_fixed'].cpu(), 128)]
        elif name.endswith('.mix'):
            block = name.rsplit('.', 1)[0]
            parts = [torch.tensor(mac_bounds[block + '.dw3']), torch.tensor(mac_bounds[block + '.dw5'])]
        elif name.endswith('.out'):
            block = name.rsplit('.', 1)[0]
            skip = mac_bounds.get(block + '.skip', [128] * len(config['bias_fixed']))
            parts = [torch.tensor(mac_bounds[block + '.project']), torch.tensor(skip)]
        else:
            parts = [torch.tensor(mac_bounds[name])]
        bound = config['bias_fixed'].cpu().abs().clone()
        for value, multiplier in zip(parts, config['multipliers']):
            bound += value * multiplier.cpu().abs()
        maximum = int(bound.max())
        assert maximum < 2**62, (name, maximum)
        merge_bounds[name] = maximum
        contract['merges'][name]['exact_integer_numerator_abs_bound'] = maximum
    common.write_json(contract_path, contract)
    common.write_json(target / 'integer_bounds.json', {'status': 'PASS',
        'mac_abs_bound_by_channel': mac_bounds, 'merge_abs_bound': merge_bounds,
        'max_mac_abs_bound': max(max(values) for values in mac_bounds.values()),
        'max_merge_abs_bound': max(merge_bounds.values()), 'fp32_integer_carrier_bound': 2**24,
        'rtl_mac': 'INT32', 'reference_merge': 'INT64; exact bound <2**62'})
    common.write_json(target / 'sha256.json', {str(p.relative_to(target)): common.sha(p)
        for p in target.rglob('*') if p.is_file() and p.name != 'sha256.json'})


common.check_originals = check_originals
common.freeze = freeze
common.sources = sources
common.load_task = load_task
common.export = export


if __name__ == '__main__':
    common.main()
