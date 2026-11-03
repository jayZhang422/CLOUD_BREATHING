#!/usr/bin/env python3
"""Vessel-only e94 joint fine-tuning, with a separate OS supervisor.

The historical module is imported for its verified model, reader, loss and
metrics. Its command-line training entry point is never invoked.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import os
import random
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

BASE = Path('/root/autodl-tmp/lung_training')
HIPAS = BASE / 'other_compact_v1/hipas/hipas'
PARSE = BASE / 'atm22_extra_train_cache_v1'
AUDIT = BASE / 'vessel_joint_audit_20261008_v1'
INIT = BASE / 'vessel_mkdc_v1/runs/resunet_mkdc_relu6_100e_v1/best_records/best_epoch_0094.pt'
SEED = 20261008
OLD = None


def read(path):
    return json.loads(Path(path).read_text())


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def atomic_json(path, value):
    path = Path(path)
    temp = path.with_name(path.name + f'.tmp.{os.getpid()}')
    with temp.open('w') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)
    directory = os.open(path.parent, os.O_DIRECTORY)
    os.fsync(directory)
    os.close(directory)


def atomic_torch(path, value):
    path = Path(path)
    temp = path.with_name(path.name + f'.tmp.{os.getpid()}')
    with temp.open('wb') as stream:
        torch.save(value, stream)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)
    directory = os.open(path.parent, os.O_DIRECTORY)
    os.fsync(directory)
    os.close(directory)


def atomic_copy(source, path):
    path = Path(path)
    temp = path.with_name(path.name + f'.tmp.{os.getpid()}')
    with Path(source).open('rb') as inp, temp.open('wb') as out:
        shutil.copyfileobj(inp, out)
        out.flush()
        os.fsync(out.fileno())
    os.replace(temp, path)
    directory = os.open(path.parent, os.O_DIRECTORY)
    os.fsync(directory)
    os.close(directory)


def event(run, name, **values):
    with (run / 'events.jsonl').open('a') as stream:
        stream.write(json.dumps({'time': time.time(), 'event': name, **values}, allow_nan=False) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return Path(f'/proc/{pid}/stat').read_text().split(') ')[1][0] != 'Z'
    except (OSError, ValueError, IndexError):
        return False


def heartbeat(run, role, epoch=0, phase='starting', **values):
    atomic_json(run / f'{role}_heartbeat.json', {'pid': os.getpid(), 'time': time.time(),
                                               'epoch': epoch, 'phase': phase, **values})


def resources(run):
    disk = shutil.disk_usage(run)
    gpu = subprocess.check_output(['nvidia-smi', '--query-gpu=utilization.gpu,memory.used,memory.total',
                                   '--format=csv,noheader,nounits'], text=True).strip().splitlines()[0]
    util, used, total = [int(v.strip()) for v in gpu.split(',')]
    return {'disk_free_bytes': disk.free, 'disk_total_bytes': disk.total,
            'gpu_util_percent': util, 'gpu_used_mib': used, 'gpu_total_mib': total}


def load_old(run):
    global OLD
    sys.path.insert(0, str(run / 'source'))
    spec = importlib.util.spec_from_file_location('verified_vessel_legacy', run / 'source/historical_model.py')
    OLD = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(OLD)
    torch.set_num_threads(8)
    OLD.seed_all(SEED)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False


class ParseCase:
    def __init__(self, root, row):
        self.row = row
        self.zdim = row['shape'][2]
        self.region = (slice(0, 512), slice(0, 512))
        self.x = np.load(root / 'samples' / f"{row['case']}_x.npy", mmap_mode='r')
        self.y = np.load(root / 'samples' / f"{row['case']}_y.npy", mmap_mode='r')
        assert self.x.dtype == np.int8 and self.x.shape == (self.zdim, 3, 512, 512)
        assert self.y.dtype == np.uint8 and self.y.shape == (self.zdim, 1, 512, 512)

    def read_sample(self, z):
        assert 0 <= z < self.zdim
        return (self.x[z].astype(np.float32), np.array(self.y[z], copy=True),
                np.ones((1, 512, 512), dtype=np.uint8))


class ParseCache:
    def __init__(self):
        self.root = PARSE
        self.meta = read(PARSE / 'metadata.json')
        self.target_names = ['artery']
        self.rows = {}
        for row in self.meta['cases']:
            self.rows[row['case']] = {**row, 'shape_h_w_z': row['shape'],
                                     'positive_slices_per_target': [row['positive_slices']],
                                     'label_voxels': [int(bool(row['positive_slices']))]}
        self.current_id = None
        self.current = None

    def open_case(self, cid):
        if cid != self.current_id:
            self.current = ParseCase(self.root, self.rows[cid])
            self.current_id = cid
        return self.current

    def positive_slices(self, cid):
        return np.asarray(self.rows[cid]['positive_slices'], dtype=np.int64)

    def read_batch(self, cid, indices, augment, rng):
        assert not augment
        values = [self.open_case(cid).read_sample(int(z)) for z in indices]
        return tuple(np.stack([v[i] for v in values]).astype(np.float32) for i in range(3))


def caches():
    return {'hipas': OLD.Cache(HIPAS, 'hipas'), 'parse': ParseCache()}


def transform(x, y, mask, flip_h=False, flip_w=False, turns=0):
    arrays = [x, y, mask]
    if flip_h:
        arrays = [a[:, ::-1, :] for a in arrays]
    if flip_w:
        arrays = [a[:, :, ::-1] for a in arrays]
    if turns:
        arrays = [np.rot90(a, turns, axes=(-2, -1)) for a in arrays]
    return tuple(np.ascontiguousarray(a) for a in arrays)


def training_batch(cache, dataset, cid, zs, rng, augment):
    xs, ys, masks = [], [], []
    for z in zs:
        x, y, mask = cache.open_case(cid).read_sample(int(z))
        if dataset == 'hipas':
            mask = np.repeat(mask, 2, axis=0)
        else:
            y = np.concatenate((y, np.zeros_like(y)), axis=0)
            mask = np.concatenate((mask, np.zeros_like(mask)), axis=0)
        if augment:
            turns = rng.choice((-1, 1)) if rng.random() < 0.25 else 0
            x, y, mask = transform(x, y, mask, rng.random() < 0.5, rng.random() < 0.5, turns)
        xs.append(x)
        ys.append(y)
        masks.append(mask)
    return tuple(np.stack(a).astype(np.float32) for a in (xs, ys, masks))


def mixed_loss(logits, y, mask, half):
    # Equal dataset loss weights; the missing PARSE vein is never supervised.
    h = OLD.masked_loss(logits[:half], y[:half], mask[:half, :1])
    p = OLD.masked_loss(logits[half:, :1], y[half:, :1], mask[half:, :1])
    return 0.5 * (h + p), h, p


class ArteryHead(nn.Module):
    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        return self.net(x)[:, :1]


def mean_metrics(rows):
    return {key: float(np.mean([r[key] for r in rows if r[key] is not None]))
            if any(r[key] is not None for r in rows) else None
            for key in ('dice', 'recall', 'precision', 'positive_layer_recall')}


def summed_metrics(rows):
    return {**OLD.stats(*(sum(r[key] for r in rows) for key in ('tp', 'fp', 'fn'))),
            **OLD.layer_stats(*(sum(r[key] for r in rows) for key in ('positive_layers', 'hit_positive_layers')))}


def evaluate(net, cache, dataset, ids, run=None, epoch=0, phase='validation'):
    adapter = net if dataset == 'hipas' else ArteryHead(net)
    rows, loss_slices, slices = [], 0.0, 0
    for cid in ids:
        if run:
            heartbeat(run, 'trainer', epoch, phase, dataset=dataset, case=cid)
        result = OLD.validate(adapter, cache, [cid], torch.device('cuda'), 16, True)
        row = result['cases'][0]
        row['loss'] = result['loss']
        row['spacing_z_y_x_mm'] = cache.rows[cid].get('spacing_z_y_x_mm')
        row['primary'] = row['union'] if dataset == 'hipas' else row['classes'][0]
        if dataset == 'parse':
            row.pop('union')
            row['vein_metric'] = None
        rows.append(row)
        zdim = row['shape_h_w_z'][2]
        loss_slices += row['loss'] * zdim
        slices += zdim
    primary = summed_metrics([r['primary'] for r in rows])
    classes = [{'name': name, **summed_metrics([r['classes'][i] for r in rows])}
               for i, name in enumerate(cache.target_names)]
    return {'dataset': dataset, 'primary_name': 'vessel_union' if dataset == 'hipas' else 'artery',
            'primary': primary, 'classes': classes,
            'macro': {'primary': mean_metrics([r['primary'] for r in rows]),
                      'classes': [{'name': name, **mean_metrics([r['classes'][i] for r in rows])}
                                  for i, name in enumerate(cache.target_names)]},
            'case_count': len(rows), 'slices': slices, 'loss': loss_slices / slices,
            'eval_mode': not net.training, 'grad_enabled': False, 'cases': rows}


def parameter_hash(net):
    digest = hashlib.sha256()
    for name, tensor in net.named_parameters():
        digest.update(name.encode())
        digest.update(tensor.detach().cpu().contiguous().numpy().tobytes())
    return digest.hexdigest()


def select_z(cache, cid, rng, positive=12, negative=4):
    pos = cache.positive_slices(cid)
    zdim = cache.rows[cid]['shape_h_w_z'][2]
    neg = np.setdiff1d(np.arange(zdim), pos)
    assert len(pos), f'{cid}: empty positive training case'
    chosen_pos = rng.choice(pos, positive, replace=len(pos) < positive)
    if len(neg):
        chosen_neg = rng.choice(neg, negative, replace=len(neg) < negative)
    else:
        chosen_neg = rng.choice(pos, negative, replace=len(pos) < negative)
    zs = np.concatenate((chosen_pos, chosen_neg))
    rng.shuffle(zs)
    return zs.astype(int).tolist(), int(np.isin(zs, pos).sum())


def optimizer(net):
    # One explicit group: all learned parameters, including BN and biases.
    return torch.optim.AdamW(net.parameters(), lr=1e-4, weight_decay=1e-4)


def model(run):
    net = OLD.ResUNet(2, 16, 'mkdc').cuda()
    initial = torch.load(run / 'initial_weights.pt', map_location='cpu', weights_only=False)
    net.load_state_dict(initial['model'], strict=True)
    return net


def smoke(run, cfg, data):
    rng = np.random.default_rng(SEED)
    batches, descriptions = [], {}
    for name, cache in data.items():
        cid = cfg['splits'][name]['train'][0]
        pos = cache.positive_slices(cid)
        positive_z = int(pos[len(pos) // 2])
        zdim = cache.rows[cid]['shape_h_w_z'][2]
        neg = sorted(set(range(zdim)) - set(pos.tolist()))
        zs = [positive_z, neg[0] if neg else positive_z]
        batch = training_batch(cache, name, cid, zs, random.Random(SEED), False)
        x, y, mask = batch
        assert x.shape == (2, 3, 512, 512) and x.dtype == np.float32
        assert y.shape == mask.shape == (2, 2, 512, 512)
        assert np.all((y == 0) | (y == 1)) and np.all((mask == 0) | (mask == 1))
        assert np.all(x == np.rint(x)) and x.min() >= -128 and x.max() <= 127
        if name == 'parse':
            assert mask[:, 1].sum() == 0 and y[:, 1].sum() == 0 and mask[:, 0].min() == 1
        else:
            assert np.array_equal(mask[:, 0], mask[:, 1])
            assert np.all(mask[np.repeat(y.sum(1, keepdims=True) > 1, 2, axis=1)] == 0)
        for z in (0, zdim - 1):
            edge = cache.open_case(cid).read_sample(z)[0]
            assert np.array_equal(edge[0 if z == 0 else 2], edge[1])
        for turns in (-1, 0, 1):
            a = transform(x[0], y[0], mask[0], True, True, turns)
            assert all(np.array_equal(v, np.rot90(orig[:, ::-1, ::-1], turns, axes=(-2, -1)))
                       for v, orig in zip(a, (x[0], y[0], mask[0])))
        chosen, npos = select_z(cache, cid, rng)
        assert len(chosen) == 16 and npos >= 12
        batches.append(batch)
        descriptions[name] = {'case': cid, 'centers': zs, 'positive_samples': npos,
                              'supervised_voxels_per_class': mask.sum((0, 2, 3)).astype(int).tolist(),
                              'positive_supervised_voxels_per_class': (y * mask).sum((0, 2, 3)).astype(int).tolist()}
    xt, yt, vt = [torch.from_numpy(np.concatenate((batches[0][i], batches[1][i]))).cuda() for i in range(3)]
    net = model(run)
    opt = optimizer(net)
    assert not opt.state
    scaler = torch.cuda.amp.GradScaler(enabled=True, init_scale=1024)
    net.train()
    before = parameter_hash(net)
    with torch.autocast(device_type='cuda', dtype=torch.float16):
        logits = net(xt)
    assert logits.shape == (4, 2, 512, 512) and torch.isfinite(logits).all()
    logits.retain_grad()
    loss, hl, pl = mixed_loss(logits, yt, vt, 2)
    assert torch.isfinite(loss)
    scaler.scale(loss).backward()
    scaler.unscale_(opt)
    grads = [p.grad for p in net.parameters() if p.grad is not None]
    assert grads and all(torch.isfinite(g).all() for g in grads)
    grad_norm = math.sqrt(sum(float(g.float().square().sum()) for g in grads))
    assert grad_norm > 0 and logits.grad[2:, 1].abs().sum() == 0
    scaler.step(opt)
    scaler.update()
    assert before != parameter_hash(net) and all(int(v['step']) == 1 for v in opt.state.values())
    net.eval()
    with torch.inference_mode(), torch.autocast(device_type='cuda', dtype=torch.float16):
        expected = net(xt).clone()
        individual = [net(xt[:2]), net(xt[2:])]
    assert all(torch.isfinite(v).all() and (v[:, 0] >= 0).any() for v in individual)
    saved = {'model': net.state_dict(), 'optimizer': opt.state_dict(), 'scaler': scaler.state_dict(), 'epoch': 0}
    atomic_torch(run / 'smoke_checkpoint.pt', saved)
    restored = model(run)
    state = torch.load(run / 'smoke_checkpoint.pt', map_location='cuda', weights_only=False)
    restored.load_state_dict(state['model'], strict=True)
    restored_opt = optimizer(restored)
    restored_opt.load_state_dict(state['optimizer'])
    restored_scaler = torch.cuda.amp.GradScaler(enabled=True)
    restored_scaler.load_state_dict(state['scaler'])
    restored.eval()
    with torch.inference_mode(), torch.autocast(device_type='cuda', dtype=torch.float16):
        actual = restored(xt)
    assert torch.equal(actual, expected)
    assert restored_scaler.state_dict() == scaler.state_dict()
    assert all(int(v['step']) == 1 for v in restored_opt.state.values())
    result = {'status': 'PASS', 'datasets': descriptions, 'mixed_shape': list(xt.shape),
              'output_shape': list(logits.shape), 'amp': 'float16', 'grad_scaler': scaler.state_dict(),
              'loss': float(loss), 'hipas_loss': float(hl), 'parse_loss': float(pl),
              'gradient_norm': grad_norm, 'parse_vein_gradient_zero': True,
              'parameters_updated': True, 'new_optimizer_initially_empty': True,
              'restored_predictions_exact': True, 'restored_optimizer_and_scaler': True,
              'separate_dataset_forward': True, 'augmentation_alignment': True,
              'sampling_positive_aware': True, 'edge_channels_repeat': True,
              'checkpoint_sha256': sha(run / 'smoke_checkpoint.pt'), 'resources': resources(run)}
    atomic_json(run / 'smoke_check.json', result)
    print('SMOKE_PASS', json.dumps(result), flush=True)
    del net, restored, opt, restored_opt, xt, yt, vt
    torch.cuda.empty_cache()


def prepare(run):
    if run.exists():
        raise FileExistsError('Use a new version; preparation never overwrites a run')
    duplicate = read(AUDIT / 'cross_dataset_check.json')
    assert not duplicate['anomalies'] and not duplicate['within_dataset_duplicate_groups']
    repro = read(AUDIT / 'e94_reproduction.json')
    assert repro['status'] == 'PASS' and sha(INIT) == repro['checkpoint_sha256']
    assert read(AUDIT / 'parse_sample_checks.json')['status'] == 'PASS'
    original = read(HIPAS / 'patient_split.json')
    hs = {k: original['validation' if k == 'val' else k] for k in ('train', 'val', 'test')}
    ps = {'train': [], 'val': [], 'test': []}
    for match in duplicate['cross_matches']:
        partition = match['hipas_partition']
        assert partition != 'quarantined'
        ps['val' if partition == 'validation' else partition].append(match['parse'])
    unmatched = sorted(duplicate['parse_unmatched'], key=lambda cid: hashlib.sha256(f'{SEED}:{cid}'.encode()).hexdigest())
    n, v = int(len(unmatched) * 0.70), int(len(unmatched) * 0.15)
    for key, values in zip(('train', 'val', 'test'), (unmatched[:n], unmatched[n:n + v], unmatched[n + v:])):
        ps[key] = sorted(ps[key] + values)
    assert sum(map(len, ps.values())) == 100
    assert len(set(sum(ps.values(), []))) == 100
    for match in duplicate['cross_matches']:
        k = 'val' if match['hipas_partition'] == 'validation' else match['hipas_partition']
        assert match['parse'] in ps[k] and match['hipas'] in hs[k]
    run.mkdir(parents=True)
    for name in ('source', 'audit', 'checkpoints', 'epoch_records', 'decisions', 'best_records', 'reports'):
        (run / name).mkdir()
    shutil.copy2(BASE / 'train_compact_mkdc_v1.py', run / 'source/historical_model.py')
    shutil.copy2(BASE / 'compact_cache_reader.py', run / 'source/compact_cache_reader.py')
    shutil.copy2(__file__, run / 'source' / Path(__file__).name)
    for path in AUDIT.glob('*.json'):
        shutil.copy2(path, run / 'audit' / path.name)
    load_old(run)
    state = torch.load(INIT, map_location='cpu', weights_only=False)
    net = OLD.ResUNet(2, 16, 'mkdc')
    net.load_state_dict(state['model'], strict=True)
    atomic_torch(run / 'initial_weights.pt', {'model': state['model'], 'run_epoch': 0, 'historical_epoch': 94,
                                            'kind': 'baseline_e94', 'source': str(INIT), 'source_sha256': sha(INIT)})
    cfg = {
        'version': 'vessel_joint_20261008_v1', 'run_dir': str(run), 'task': 'vessel_only',
        'seed': SEED, 'max_epochs': 100, 'historical_initial_epoch': 94,
        'initial_checkpoint': str(INIT), 'initial_checkpoint_sha256': sha(INIT),
        'initial_weights_sha256': sha(run / 'initial_weights.pt'),
        'model': state['config']['architecture'], 'base': 16, 'op': 'mkdc',
        'parameter_count': sum(p.numel() for p in net.parameters()),
        'input_contract': state['config']['input_contract'],
        'datasets': {
            'hipas': {'root': str(HIPAS), 'version': duplicate['hipas_version'], 'cases': 250,
                      'eligible': 137, 'quarantined': original['quarantined'], 'labels': ['artery', 'vein'],
                      'metadata_sha256': sha(HIPAS / 'metadata.json'), 'original_split_sha256': sha(HIPAS / 'patient_split.json'),
                      'space': 'native source axes; spacing_z_y_x_mm retained; absent affine is not invented'},
            'parse': {'root': str(PARSE), 'version': duplicate['parse_cache_version'], 'cases': 100,
                      'official_source_partition': 'PARSE labeled training archive; PA case IDs and original pulmonary artery masks',
                      'metadata_sha256': sha(PARSE / 'metadata.json'), 'labels': ['artery'],
                      'label_reference': 'https://parse2022.grand-challenge.org/Dataset/',
                      'label_values': {'0': 'non-artery background', '1': 'pulmonary artery'},
                      'unknown': 'vein channel ignored at every voxel; not supervised as background',
                      'space': 'affine and spacing_xyz_mm from cache; native NIfTI in-plane axes retained',
                      'input_shape_header': '[N,3,512,512]; N=Z because all centers 0..Z-1 are cached',
                      'partition_reason': 'No saved split or labeled official val/test present. Fixed internal holdouts from available 100-case official training pool; duplicate groups inherit frozen HiPaS partition.'}},
        'splits': {'hipas': hs, 'parse': ps},
        'cross_dataset_matches': duplicate['cross_matches'],
        'leakage_check_limit': duplicate['limitations'],
        'train_evaluation_subset': {key: sorted(values['train'], key=lambda cid: hashlib.sha256(f'subset:{cid}'.encode()).hexdigest())[:2]
                                    for key, values in {'hipas': hs, 'parse': ps}.items()},
        'optimizer': {'name': 'AdamW', 'initial_lr': 1e-4, 'weight_decay': 1e-4,
                      'groups': [{'name': 'all_learned_parameters_including_BN_and_bias',
                                  'weight_decay': 1e-4, 'parameters': [n for n, _ in net.named_parameters()]}],
                      'old_optimizer_loaded': False},
        'lr_schedule': {'name': 'fixed cosine', 'epochs': 100, 'minimum_lr': 1e-6,
                        'formula': '1e-6 + 0.5*(1e-4-1e-6)*(1+cos(pi*(epoch-1)/99))',
                        'supervisor_adjustments': 'none; no test or noise-driven feedback'},
        'batch_size': 16, 'dataset_batch_size': 8,
        'sampling': {'rounds': max(len(hs['train']), len(ps['train'])), 'positive_per_case_visit': 12,
                     'negative_per_case_visit': 4, 'dataset_loss_weight': {'hipas': 0.5, 'parse': 0.5},
                     'policy': 'every training patient per epoch; independently shuffled balanced cycles; negative-unavailable slots use positive slices and are explicitly counted'},
        'augmentation': {'flip_h_probability': 0.5, 'flip_w_probability': 0.5, 'planar_90_degree_probability': 0.25,
                         'policy': 'same transform on image, labels and supervision mask; no Z-axis or channel permutation; no intensity changes'},
        'loss': 'equal dataset mean of historical 0.5 balanced BCE + 0.5 per-class soft Dice; HiPaS both classes, PARSE artery only; BCE pos_weight clamp1..20',
        'label_contract': {'output_order': ['artery', 'vein'], 'logits': 'independent sigmoid logits',
                           'hipas': 'preserve binary A/V; A&V overlap ignored for per-class loss/metrics',
                           'parse': 'native artery binary mask; entire vein supervision mask zero',
                           'padding': 'INT8 -128; loss and metrics ignore padding',
                           'annotated_scope': 'HiPaS A/V and PARSE artery according to supplied masks; no additional unknown-region masks supplied; absent anatomical vein labels are ignored'},
        'metrics': {'threshold': 'logit >= 0 (sigmoid >= 0.5)',
                    'hipas_union': 'OR of channel threshold results; full native mask, including A/V overlap; exact historical semantics',
                    'union_score': 'max(sigmoid artery, sigmoid vein), whose 0.5 threshold equals historical OR',
                    'parse': 'artery only; vein and total-vessel union are unobservable and not scored',
                    'empty': 'Dice=1 if prediction and truth both empty; precision/recall/layer recall None when undefined',
                    'aggregation': 'global confusion sums AND unweighted macro patient metrics; complete slices; batch16 FP16',
                    'positive_layer_recall': 'positive layer hit requires at least one true-positive voxel',
                    'small_vessel_metric': 'not available; positive-layer recall is not small-vessel recall'},
        'best_rule': {'primary': 'maximize HiPaS union macro patient Dice; tie-break with PARSE artery macro Dice',
                      'eligibility': 'HiPaS union global and macro Dice >= respective e94 baselines - 0.01; PARSE artery macro Dice >= baseline - 0.01; both HiPaS class global Dice >= baseline - 0.02',
                      'baseline_candidate_epoch': 0, 'test_feedback': False},
        'supervision': {'protocol': 1, 'decision_timeout_seconds': 120, 'heartbeat_timeout_seconds': 180,
                        'startup_timeout_seconds': 45, 'minimum_disk_free_bytes': 2 * 1024**3,
                        'maximum_amp_skip_fraction': 0.05,
                        'failure': 'safe pause, persist state, no automatic restart or hot code edit',
                        'metric_degradation': 'warnings and best guard; low Dice/single fluctuation never changes code or configuration',
                        'checkpoint_policy': 'every completed epoch immutable; last and selected best are rolling aliases; best refresh immediately has immutable copy'},
        'scripts_sha256': {p.name: sha(p) for p in (run / 'source').glob('*.py')},
        'software': {'python': sys.version, 'numpy': np.__version__, 'torch': torch.__version__,
                     'cuda': torch.version.cuda, 'cudnn': torch.backends.cudnn.version(),
                     'gpu': torch.cuda.get_device_name(0)},
        'resources_at_prepare': resources(run),
    }
    atomic_json(run / 'patient_splits.json', cfg['splits'])
    cfg['patient_splits_sha256'] = sha(run / 'patient_splits.json')
    data = caches()
    smoke(run, cfg, data)
    baseline = {'hipas': evaluate(model(run), data['hipas'], 'hipas', hs['val']),
                'parse': evaluate(model(run), data['parse'], 'parse', ps['val'])}
    historical = repro['validation']['union']
    assert baseline['hipas']['primary'] == historical
    cfg['baseline'] = {key: {'primary': value['primary'], 'macro': value['macro'], 'classes': value['classes'], 'loss': value['loss']}
                       for key, value in baseline.items()}
    atomic_json(run / 'baseline_validation.json', baseline)
    atomic_json(run / 'run_config.json', cfg)
    atomic_json(run / 'status.json', {'state': 'ready', 'completed_epochs': 0, 'smoke': 'PASS', 'time': time.time()})
    print('PREPARED', str(run), json.dumps({'splits': {k: {s: len(v) for s, v in ds.items()} for k, ds in cfg['splits'].items()},
                                         'baseline': cfg['baseline']}), flush=True)


def best_key(validation, cfg):
    h, p = validation['hipas'], validation['parse']
    bh, bp = cfg['baseline']['hipas'], cfg['baseline']['parse']
    eligible = (h['primary']['dice'] >= bh['primary']['dice'] - 0.01
                and h['macro']['primary']['dice'] >= bh['macro']['primary']['dice'] - 0.01
                and p['macro']['primary']['dice'] >= bp['macro']['primary']['dice'] - 0.01
                and all(a['dice'] >= b['dice'] - 0.02 for a, b in zip(h['classes'], bh['classes'])))
    return (h['macro']['primary']['dice'], p['macro']['primary']['dice']), eligible


def assert_frozen(run, cfg):
    assert sha(run / 'patient_splits.json') == cfg['patient_splits_sha256'], 'split changed'
    for name, expected in cfg['scripts_sha256'].items():
        assert sha(run / 'source' / name) == expected, f'source changed: {name}'
    for dataset in cfg['datasets'].values():
        assert sha(Path(dataset['root']) / 'metadata.json') == dataset['metadata_sha256'], 'metadata changed'
    assert sha(HIPAS / 'patient_split.json') == cfg['datasets']['hipas']['original_split_sha256']


def check_metric(value):
    counts = [value[key] for key in ('tp', 'fp', 'fn', 'positive_layers', 'hit_positive_layers')]
    assert all(isinstance(v, int) and v >= 0 for v in counts), 'invalid confusion/layer count'
    assert value['hit_positive_layers'] <= value['positive_layers']
    expected = {**OLD.stats(*counts[:3]), **OLD.layer_stats(*counts[3:])}
    for key in ('dice', 'recall', 'precision', 'positive_layer_recall'):
        actual, want = value[key], expected[key]
        assert actual is None if want is None else actual is not None and math.isfinite(actual) and abs(actual - want) < 1e-12, key


def check_evaluation(evaluation, ids, names):
    assert [r['case'] for r in evaluation['cases']] == ids, 'wrong evaluation patients/order'
    assert evaluation['case_count'] == len(ids)
    assert evaluation['eval_mode'] and not evaluation['grad_enabled']
    assert math.isfinite(evaluation['loss']) and evaluation['loss'] >= 0
    for row in evaluation['cases']:
        check_metric(row['primary'])
        assert [v['name'] for v in row['classes']] == names
        for value in row['classes']:
            check_metric(value)
    for column in ('primary',):
        check_metric(evaluation[column])
        assert evaluation[column] == summed_metrics([r[column] for r in evaluation['cases']])
        assert evaluation['macro'][column] == mean_metrics([r[column] for r in evaluation['cases']])
    for i, name in enumerate(names):
        check_metric(evaluation['classes'][i])
        assert evaluation['classes'][i] == {'name': name, **summed_metrics([r['classes'][i] for r in evaluation['cases']])}
        assert evaluation['macro']['classes'][i] == {'name': name, **mean_metrics([r['classes'][i] for r in evaluation['cases']])}


def check_epoch(run, cfg, record, expected_epoch, record_hash):
    assert record['epoch'] == expected_epoch and record['protocol'] == 1
    assert record['run_config_sha256'] == sha(run / 'run_config.json')
    assert sha(run / 'epoch_records' / f'epoch_{expected_epoch:04d}.json') == record_hash
    assert_frozen(run, cfg)
    for match in cfg['cross_dataset_matches']:
        k = 'val' if match['hipas_partition'] == 'validation' else match['hipas_partition']
        assert match['hipas'] in cfg['splits']['hipas'][k] and match['parse'] in cfg['splits']['parse'][k]
    if expected_epoch > 1:
        previous = run / 'decisions' / f'decision_{expected_epoch - 1:04d}.json'
        assert record['previous_decision_sha256'] == sha(previous)
        assert read(previous)['action'] == 'CONTINUE'
    t = record['training']
    assert t['train_mode_all_batches'] and t['grad_enabled_all_batches']
    assert t['loss_finite_all_batches'] and t['finite_gradients_all_applied_steps']
    assert t['optimizer_updates'] > 0 and t['parameter_sha256_before'] != t['parameter_sha256_after']
    assert t['scaler_enabled'] and t['amp_dtype'] == 'float16'
    assert t['amp_skipped_steps'] / t['attempted_steps'] <= cfg['supervision']['maximum_amp_skip_fraction']
    assert t['optimizer_updates'] + t['amp_skipped_steps'] == t['attempted_steps']
    assert math.isfinite(t['gradient_norm_max']) and t['gradient_norm_max'] > 0
    assert math.isfinite(t['train_loss']) and t['train_loss'] >= 0
    wanted_lr = 1e-6 + 0.5 * (1e-4 - 1e-6) * (1 + math.cos(math.pi * (expected_epoch - 1) / 99))
    assert abs(record['lr'] - wanted_lr) < 1e-15
    expected_samples = cfg['sampling']['rounds'] * 16
    for name in ('hipas', 'parse'):
        sample = t['sampling'][name]
        assert sample['samples'] == expected_samples
        assert set(sample['cases']) == set(cfg['splits'][name]['train']), 'training partition not fully used'
        assert sample['positive_slices'] >= cfg['sampling']['rounds'] * 12
        assert sample['positive_slices'] + sample['negative_slices'] == sample['samples']
        assert sum(v['samples'] for v in sample['cases'].values()) == sample['samples']
        for value in sample['cases'].values():
            assert value['positive_slices'] + value['negative_slices'] == value['samples']
            assert all(0 <= p <= v <= value['samples'] * 512 * 512
                       for p, v in zip(value['positive_supervised_voxels'], value['supervised_voxels']))
        assert sample['supervised_voxels'][0] > 0 and sample['positive_supervised_voxels'][0] > 0
        if name == 'parse':
            assert sample['supervised_voxels'][1] == sample['positive_supervised_voxels'][1] == 0
        else:
            assert sample['supervised_voxels'][1] > 0 and sample['positive_supervised_voxels'][1] > 0
        check_evaluation(record['validation'][name], cfg['splits'][name]['val'], ['artery', 'vein'] if name == 'hipas' else ['artery'])
        check_evaluation(record['train_evaluation'][name], cfg['train_evaluation_subset'][name], ['artery', 'vein'] if name == 'hipas' else ['artery'])
        metric = record['validation'][name]['primary']
        assert metric['tp'] + metric['fp'] > 0, f'{name}: all-background prediction'
    for kind, value in record['checkpoints'].items():
        path = run / value['path']
        assert path.is_file() and sha(path) == value['sha256'], f'{kind} checksum'
    last = torch.load(run / 'last.pt', map_location='cpu', weights_only=False)
    assert last['epoch'] == expected_epoch and last['run_config_sha256'] == record['run_config_sha256']
    assert last['optimizer']['param_groups'][0]['weight_decay'] == 1e-4
    assert last['optimizer']['param_groups'][0]['lr'] == record['lr']
    assert last['scaler'] and last['scaler']['scale'] > 0
    assert last['optimizer']['state'], 'optimizer not updated'
    assert all(torch.isfinite(v).all() for v in last['model'].values())
    cpu_model = OLD.ResUNet(2, 16, 'mkdc')
    cpu_model.load_state_dict(last['model'], strict=True)
    assert parameter_hash(cpu_model) == t['parameter_sha256_after']
    steps = [int(v['step']) for v in last['optimizer']['state'].values()]
    assert min(steps) == max(steps) == t['cumulative_optimizer_updates']
    _, eligible = best_key(record['validation'], cfg)
    if record['best_refreshed']:
        assert eligible and record['best_epoch'] == expected_epoch
        assert record['checkpoints']['best']['sha256'] == record['checkpoints']['epoch']['sha256']
        assert record['checkpoints']['best_immutable']['sha256'] == record['checkpoints']['best']['sha256']
    assert record['resources']['disk_free_bytes'] >= cfg['supervision']['minimum_disk_free_bytes']
    warnings = []
    for name in ('hipas', 'parse'):
        metric = record['validation'][name]['primary']
        baseline = cfg['baseline'][name]['primary']
        if metric['dice'] < baseline['dice'] - 0.03:
            warnings.append(f'{name}: Dice lower than e94 by >0.03; inspect patient metrics, not automatic code/config change')
        before = (baseline if expected_epoch == 1 else read(run / 'epoch_records' / f'epoch_{expected_epoch - 1:04d}.json')['validation'][name]['primary'])
        old_count, new_count = before['tp'] + before['fp'], metric['tp'] + metric['fp']
        if old_count and not 0.5 <= new_count / old_count <= 2:
            warnings.append(f'{name}: predicted voxel count changed by more than factor2')
    return {'status': 'PASS', 'checks': ['patient_partition_and_duplicate_groups', 'both_datasets_and_all_training_cases',
                                        'label_order_and_vein_unknown_mask', 'train_eval_and_gradient_modes',
                                        'AMP_updates_gradients_LR', 'per_case_global_macro_confusion_metrics',
                                        'nonempty_predictions', 'checkpoint_model_optimizer_scaler_and_SHA256',
                                        'immutable_best', 'frozen_source_metadata_split', 'disk'], 'warnings': warnings}


def ensure_supervisor(run, cfg):
    if (run / 'pause_requested.json').exists():
        raise RuntimeError('Supervisor requested pause: ' + str(read(run / 'pause_requested.json')))
    processes = read(run / 'processes.json')
    pid = processes['supervisor']['pid']
    assert alive(pid), 'supervisor process died'
    beat = read(run / 'supervisor_heartbeat.json')
    assert beat['pid'] == pid and time.time() - beat['time'] < cfg['supervision']['heartbeat_timeout_seconds'], 'supervisor heartbeat timeout'


def decision_identity(decision, epoch, record_hash, config_hash, supervisor_pid):
    assert decision['epoch'] == epoch and decision['record_sha256'] == record_hash, 'stale/wrong decision'
    assert decision['run_config_sha256'] == config_hash
    assert decision['supervisor_pid'] == supervisor_pid
    assert decision['action'] == 'CONTINUE', f'supervisor held epoch: {decision}'


def wait_decision(run, cfg, epoch, record_hash):
    path = run / 'decisions' / f'decision_{epoch:04d}.json'
    deadline = time.monotonic() + cfg['supervision']['decision_timeout_seconds']
    while not path.exists():
        heartbeat(run, 'trainer', epoch, 'waiting_supervisor', record_sha256=record_hash)
        ensure_supervisor(run, cfg)
        if time.monotonic() >= deadline:
            raise TimeoutError(f'epoch {epoch}: supervisor decision timeout')
        time.sleep(1)
    decision = read(path)
    decision_identity(decision, epoch, record_hash, sha(run / 'run_config.json'), read(run / 'processes.json')['supervisor']['pid'])
    return sha(path)


def twenty_epoch_report(run, epoch, cfg):
    records = [read(p) for p in sorted((run / 'epoch_records').glob('epoch_*.json'))]
    result = {'epoch': epoch, 'best_epoch': records[-1]['best_epoch'], 'configuration_adjustments': [],
              'recommendation': 'continue the bounded fixed experiment if supervisory checks pass', 'datasets': {}}
    for name in ('hipas', 'parse'):
        recent = records[-20:]
        cases = recent[-1]['validation'][name]['cases']
        result['datasets'][name] = {
            'validation_global_dice': [r['validation'][name]['primary']['dice'] for r in recent],
            'validation_macro_dice': [r['validation'][name]['macro']['primary']['dice'] for r in recent],
            'train_subset_macro_dice': [r['train_evaluation'][name]['macro']['primary']['dice'] for r in recent],
            'train_validation_macro_gap': recent[-1]['train_evaluation'][name]['macro']['primary']['dice'] - recent[-1]['validation'][name]['macro']['primary']['dice'],
            'worst_cases': [{'case': r['case'], **r['primary']} for r in sorted(cases, key=lambda r: r['primary']['dice'])[:3]],
            'false_positive_voxels': recent[-1]['validation'][name]['primary']['fp'],
            'false_negative_voxels': recent[-1]['validation'][name]['primary']['fn'],
        }
        last10 = recent[-10:]
        train = [r['train_evaluation'][name]['macro']['primary']['dice'] for r in last10]
        val = [r['validation'][name]['macro']['primary']['dice'] for r in last10]
        rising = sum(b > a for a, b in zip(train, train[1:]))
        falling = sum(b < a for a, b in zip(val, val[1:]))
        evidence = len(last10) == 10 and rising >= 7 and falling >= 7 and train[-1] - train[0] > 0.01 and val[0] - val[-1] > 0.01
        result['datasets'][name]['overfitting_evidence'] = {
            'sustained_opposite_trends_flag': evidence, 'training_improving_transitions': rising,
            'validation_declining_transitions': falling,
            'interpretation': 'candidate evidence; inspect loss, patient and sampling records' if evidence else 'insufficient sustained train-improving/validation-degrading evidence'}
    atomic_json(run / 'reports' / f'epoch_{epoch:04d}.json', result)
    print('ANALYSIS20', json.dumps(result), flush=True)


def state_bundle(net, opt, scaler, epoch, best_epoch, key, run):
    return {'epoch': epoch, 'historical_initial_epoch': 94, 'best_epoch': best_epoch, 'best_key': key,
            'model': net.state_dict(), 'optimizer': opt.state_dict(), 'scaler': scaler.state_dict(),
            'run_config_sha256': sha(run / 'run_config.json'),
            'rng': {'python': random.getstate(), 'numpy': np.random.get_state(), 'torch': torch.get_rng_state(),
                    'cuda': torch.cuda.get_rng_state_all()}}


def train(run, resume=False):
    cfg = read(run / 'run_config.json')
    load_old(run)
    assert_frozen(run, cfg)
    assert read(run / 'smoke_check.json')['status'] == 'PASS'
    heartbeat(run, 'trainer', 0, 'startup')
    deadline = time.monotonic() + cfg['supervision']['startup_timeout_seconds']
    while not (run / 'processes.json').exists() or not (run / 'supervisor_heartbeat.json').exists():
        if time.monotonic() > deadline:
            raise TimeoutError('supervisor startup timeout')
        time.sleep(1)
    ensure_supervisor(run, cfg)
    data = caches()
    net = model(run)
    opt = optimizer(net)
    scaler = torch.cuda.amp.GradScaler(enabled=True, init_scale=1024)
    baseline = read(run / 'baseline_validation.json')
    key, _ = best_key(baseline, cfg)
    best_epoch, completed, cumulative_updates, previous_decision = 0, 0, 0, None
    immutable_best = 'initial_weights.pt'
    if resume:
        assert (run / 'last.pt').exists()
        state = torch.load(run / 'last.pt', map_location='cuda', weights_only=False)
        completed = state['epoch']
        decision_path = run / 'decisions' / f'decision_{completed:04d}.json'
        assert read(decision_path)['action'] == 'CONTINUE', 'last checkpoint lacks a passing supervisor decision'
        rec = read(run / 'epoch_records' / f'epoch_{completed:04d}.json')
        assert sha(run / 'last.pt') == rec['checkpoints']['last']['sha256']
        assert state['run_config_sha256'] == sha(run / 'run_config.json')
        net.load_state_dict(state['model'], strict=True)
        opt.load_state_dict(state['optimizer'])
        scaler.load_state_dict(state['scaler'])
        best_epoch, key = state['best_epoch'], tuple(state['best_key'])
        cumulative_updates = rec['training']['cumulative_optimizer_updates']
        previous_decision = sha(decision_path)
        immutable_best = rec['checkpoints']['best_immutable']['path']
        event(run, 'resume', checkpoint=rec['checkpoints']['last'], epoch=completed)
    else:
        assert not (run / 'last.pt').exists() and not (run / 'best.pt').exists(), 'existing training requires explicit resume'
        assert not opt.state
        atomic_copy(run / 'initial_weights.pt', run / 'best.pt')
    print('TRAIN_START', json.dumps({'pid': os.getpid(), 'completed_epochs': completed,
                                    'new_optimizer': not resume, 'config_sha256': sha(run / 'run_config.json')}), flush=True)
    epoch = completed
    try:
        for epoch in range(completed + 1, cfg['max_epochs'] + 1):
            ensure_supervisor(run, cfg)
            assert_frozen(run, cfg)
            assert resources(run)['disk_free_bytes'] >= cfg['supervision']['minimum_disk_free_bytes']
            started = time.time()
            heartbeat(run, 'trainer', epoch, 'training')
            atomic_json(run / 'status.json', {'state': 'training', 'epoch': epoch, 'completed_epochs': completed, 'time': time.time()})
            lr = 1e-6 + 0.5 * (1e-4 - 1e-6) * (1 + math.cos(math.pi * (epoch - 1) / 99))
            for group in opt.param_groups:
                group['lr'] = lr
            net.train()
            torch.cuda.reset_peak_memory_stats()
            rng = np.random.default_rng(SEED + epoch * 1009)
            planar_rng = random.Random(SEED + epoch * 1013)
            rounds = cfg['sampling']['rounds']
            orders = {}
            for name in ('hipas', 'parse'):
                values = []
                while len(values) < rounds:
                    cycle = cfg['splits'][name]['train'][:]
                    rng.shuffle(cycle)
                    values.extend(cycle)
                orders[name] = values[:rounds]
            sampling = {name: {'samples': 0, 'positive_slices': 0, 'negative_slices': 0,
                               'supervised_voxels': [0, 0], 'positive_supervised_voxels': [0, 0], 'cases': {}}
                        for name in ('hipas', 'parse')}
            before = parameter_hash(net)
            attempted, updates, skipped, max_grad, losses, hloss, ploss = 0, 0, 0, 0.0, 0.0, 0.0, 0.0
            for visit in range(rounds):
                selected = {}
                for name in ('hipas', 'parse'):
                    cid = orders[name][visit]
                    zs, npos = select_z(data[name], cid, rng)
                    selected[name] = (cid, zs)
                    log = sampling[name]
                    log['samples'] += 16
                    log['positive_slices'] += npos
                    log['negative_slices'] += 16 - npos
                    patient = log['cases'].setdefault(cid, {'visits': 0, 'samples': 0, 'positive_slices': 0, 'negative_slices': 0,
                                                           'supervised_voxels': [0, 0], 'positive_supervised_voxels': [0, 0]})
                    patient['visits'] += 1
                    patient['samples'] += 16
                    patient['positive_slices'] += npos
                    patient['negative_slices'] += 16 - npos
                for offset in (0, 8):
                    ensure_supervisor(run, cfg)
                    heartbeat(run, 'trainer', epoch, 'training', visit=visit, batch=attempted)
                    parts = []
                    for name in ('hipas', 'parse'):
                        cid, zs = selected[name]
                        arrays = training_batch(data[name], name, cid, zs[offset:offset + 8], planar_rng, True)
                        parts.append(arrays)
                        _, y, mask = arrays
                        for field, counts in [('supervised_voxels', mask.sum((0, 2, 3))),
                                              ('positive_supervised_voxels', (y * mask).sum((0, 2, 3)))]:
                            for c in (0, 1):
                                sampling[name][field][c] += int(counts[c])
                                sampling[name]['cases'][cid][field][c] += int(counts[c])
                    xt, yt, vt = [torch.from_numpy(np.concatenate((parts[0][i], parts[1][i]))).cuda() for i in range(3)]
                    assert net.training and torch.is_grad_enabled()
                    opt.zero_grad(set_to_none=True)
                    with torch.autocast(device_type='cuda', dtype=torch.float16):
                        logits = net(xt)
                    loss, h, p = mixed_loss(logits, yt, vt, 8)
                    assert torch.isfinite(loss), 'nonfinite loss'
                    scaler.scale(loss).backward()
                    scaler.unscale_(opt)
                    grads = [v.grad for v in net.parameters() if v.grad is not None]
                    finite = all(torch.isfinite(v).all() for v in grads)
                    old_scale = scaler.get_scale()
                    scaler.step(opt)
                    scaler.update()
                    is_skip = scaler.get_scale() < old_scale
                    assert finite or is_skip, 'nonfinite gradients applied'
                    if finite:
                        norm = math.sqrt(sum(float(g.float().square().sum()) for g in grads))
                        assert math.isfinite(norm) and norm > 0
                        max_grad = max(max_grad, norm)
                    attempted += 1
                    skipped += int(is_skip)
                    updates += int(not is_skip)
                    losses += float(loss)
                    hloss += float(h)
                    ploss += float(p)
                    if attempted >= 20 and skipped / attempted > cfg['supervision']['maximum_amp_skip_fraction']:
                        raise RuntimeError('AMP skip fraction exceeds predeclared limit')
                    if attempted % 50 == 0:
                        print('PROGRESS', json.dumps({'epoch': epoch, 'batch': attempted,
                                                     'loss': losses / attempted, 'updates': updates,
                                                     'amp_skipped': skipped}), flush=True)
            after = parameter_hash(net)
            assert before != after and updates > 0
            cumulative_updates += updates
            validation = {name: evaluate(net, data[name], name, cfg['splits'][name]['val'], run, epoch)
                          for name in ('hipas', 'parse')}
            train_evaluation = {name: evaluate(net, data[name], name, cfg['train_evaluation_subset'][name], run, epoch, 'train_subset_evaluation')
                                for name in ('hipas', 'parse')}
            candidate, eligible = best_key(validation, cfg)
            refresh = eligible and candidate > key
            if refresh:
                best_epoch, key = epoch, candidate
            state = state_bundle(net, opt, scaler, epoch, best_epoch, key, run)
            epoch_path = run / 'checkpoints' / f'epoch_{epoch:04d}.pt'
            assert not epoch_path.exists(), 'immutable epoch checkpoint already exists'
            atomic_torch(epoch_path, state)
            atomic_copy(epoch_path, run / 'last.pt')
            epoch_sha = sha(epoch_path)
            if refresh:
                immutable_best = f'best_records/best_epoch_{epoch:04d}.pt'
                assert not (run / immutable_best).exists()
                atomic_copy(epoch_path, run / immutable_best)
                atomic_copy(epoch_path, run / 'best.pt')
            record = {
                'protocol': 1, 'epoch': epoch, 'historical_initial_epoch': 94,
                'run_config_sha256': sha(run / 'run_config.json'), 'previous_decision_sha256': previous_decision,
                'lr': lr, 'best_epoch': best_epoch, 'best_kind': 'baseline_e94' if best_epoch == 0 else 'joint_finetune',
                'best_refreshed': refresh, 'best_eligible': eligible,
                'training': {'train_loss': losses / attempted, 'dataset_losses': {'hipas': hloss / attempted, 'parse': ploss / attempted},
                             'attempted_steps': attempted, 'optimizer_updates': updates, 'amp_skipped_steps': skipped,
                             'cumulative_optimizer_updates': cumulative_updates, 'gradient_norm_max': max_grad,
                             'parameter_sha256_before': before, 'parameter_sha256_after': after,
                             'train_mode_all_batches': True, 'grad_enabled_all_batches': True,
                             'loss_finite_all_batches': True, 'finite_gradients_all_applied_steps': True,
                             'amp_dtype': 'float16', 'scaler_enabled': scaler.is_enabled(), 'scaler_scale': scaler.get_scale(),
                             'sampling': sampling},
                'validation': validation, 'train_evaluation': train_evaluation,
                'seconds': time.time() - started, 'gpu_peak_allocated_bytes': torch.cuda.max_memory_allocated(),
                'gpu_peak_reserved_bytes': torch.cuda.max_memory_reserved(), 'resources': resources(run),
                'checkpoints': {'epoch': {'path': str(epoch_path.relative_to(run)), 'sha256': epoch_sha},
                                'last': {'path': 'last.pt', 'sha256': sha(run / 'last.pt')},
                                'best': {'path': 'best.pt', 'sha256': sha(run / 'best.pt')},
                                'best_immutable': {'path': immutable_best, 'sha256': sha(run / immutable_best)}}}
            record_path = run / 'epoch_records' / f'epoch_{epoch:04d}.json'
            assert not record_path.exists()
            atomic_json(record_path, record)
            record_hash = sha(record_path)
            atomic_json(run / 'epoch_ready.json', {'epoch': epoch, 'record_sha256': record_hash, 'time': time.time()})
            previous_decision = wait_decision(run, cfg, epoch, record_hash)
            completed = epoch
            summary = {'epoch': epoch, 'best_epoch': best_epoch, 'best_refreshed': refresh, 'supervision': 'PASS',
                       **{name: validation[name]['primary'] for name in ('hipas', 'parse')}}
            print('EPOCH', json.dumps(summary), flush=True)
            event(run, 'epoch_complete', **summary)
            if epoch % 20 == 0:
                twenty_epoch_report(run, epoch, cfg)
            if (run / 'stop_requested.json').exists():
                event(run, 'user_stop_at_epoch_boundary', epoch=epoch)
                break
        heartbeat(run, 'trainer', completed, 'final_test')
        atomic_json(run / 'status.json', {'state': 'finalizing', 'completed_epochs': completed, 'best_epoch': best_epoch, 'time': time.time()})
        selected = torch.load(run / 'best.pt', map_location='cuda', weights_only=False)
        net.load_state_dict(selected['model'], strict=True)
        test = {name: evaluate(net, data[name], name, cfg['splits'][name]['test'], run, completed, 'final_test')
                for name in ('hipas', 'parse')}
        best_validation = baseline if best_epoch == 0 else read(run / 'epoch_records' / f'epoch_{best_epoch:04d}.json')['validation']
        final = {'state': 'complete', 'completed_epochs': completed, 'best_epoch': best_epoch,
                 'best_kind': 'baseline_e94' if best_epoch == 0 else 'joint_finetune',
                 'initial_checkpoint': str(INIT), 'initial_checkpoint_sha256': cfg['initial_checkpoint_sha256'],
                 'best_checkpoint': str(run / 'best.pt'), 'best_checkpoint_sha256': sha(run / 'best.pt'),
                 'best_immutable': str(run / immutable_best), 'best_immutable_sha256': sha(run / immutable_best),
                 'baseline_validation': baseline, 'best_validation': best_validation, 'test': test,
                 'relative_to_e94_validation': {name: {key: best_validation[name]['primary'][key] - cfg['baseline'][name]['primary'][key]
                                                      for key in ('dice', 'recall', 'precision', 'positive_layer_recall')}
                                               for name in ('hipas', 'parse')},
                 'data_usage': {'splits': cfg['splits'], 'cross_dataset_shared_CTs': 45,
                                'unique_training_CT_groups': 133, 'quarantined_hipas': 113},
                 'small_vessel_metric': cfg['metrics']['small_vessel_metric'],
                 'abnormal_case_policy': '113 HiPaS quarantined excluded; no missing/empty binary labels in eligible metadata/header checks; unknown PARSE veins masked',
                 'supervision': {'epoch_checks_passed': completed, 'adjustments': [], 'repairs': []},
                 'test_used_for_selection': False, 'resources': resources(run), 'time': time.time(),
                 'deployment': 'pending independent deployment/quantization and anatomical validation; no automatic other experiment'}
        atomic_json(run / 'final_results.json', final)
        deadline = time.monotonic() + cfg['supervision']['decision_timeout_seconds']
        while not (run / 'final_check.json').exists():
            heartbeat(run, 'trainer', completed, 'waiting_final_check')
            ensure_supervisor(run, cfg)
            if time.monotonic() > deadline:
                raise TimeoutError('final supervisor check timeout')
            time.sleep(1)
        assert read(run / 'final_check.json')['status'] == 'PASS'
        atomic_json(run / 'status.json', {'state': 'complete', 'completed_epochs': completed, 'best_epoch': best_epoch, 'time': time.time()})
        print('COMPLETE', json.dumps({k: v for k, v in final.items() if k not in ('baseline_validation', 'best_validation', 'test', 'data_usage')}), flush=True)
    except BaseException as exc:
        error = {'state': 'paused', 'epoch': epoch, 'completed_epochs': completed, 'best_epoch': best_epoch,
                 'error': repr(exc), 'traceback': traceback.format_exc(), 'time': time.time()}
        try:
            atomic_torch(run / 'paused_state.pt', state_bundle(net, opt, scaler, epoch, best_epoch, key, run))
            error['paused_state_sha256'] = sha(run / 'paused_state.pt')
        except Exception as save_error:
            error['save_error'] = repr(save_error)
        atomic_json(run / 'status.json', error)
        event(run, 'safe_pause', **error)
        print('SAFE_PAUSE', json.dumps(error), flush=True)
        raise


def supervisor_selfcheck(run):
    # Three actual failure modes, with no framework or synthetic training.
    good = {**OLD.stats(2, 1, 1), **OLD.layer_stats(2, 1)}
    check_metric(good)
    failures = 0
    try:
        check_metric({**good, 'dice': 0.9})
    except AssertionError:
        failures += 1
    correct = {'epoch': 1, 'record_sha256': 'a', 'run_config_sha256': 'b', 'supervisor_pid': 123, 'action': 'CONTINUE'}
    decision_identity(correct, 1, 'a', 'b', 123)
    for value in ({**correct, 'epoch': 0}, {**correct, 'record_sha256': 'wrong'}):
        try:
            decision_identity(value, 1, 'a', 'b', 123)
        except AssertionError:
            failures += 1
    exited = subprocess.Popen([sys.executable, '-c', 'pass'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    exited.wait(timeout=10)
    assert not alive(exited.pid)
    assert failures == 3
    result = {'status': 'PASS', 'incorrect_metric_rejected': True, 'stale_epoch_rejected': True,
              'wrong_record_hash_rejected': True, 'dead_OS_process_detected': True}
    atomic_json(run / 'supervisor_selfcheck.json', result)
    print('SUPERVISOR_SELFCHECK_PASS', json.dumps(result), flush=True)


def supervise(run):
    cfg = read(run / 'run_config.json')
    load_old(run)
    assert_frozen(run, cfg)
    last_checked = 0
    existing = sorted((run / 'decisions').glob('decision_*.json'))
    if existing:
        latest = read(existing[-1])
        assert latest['action'] == 'CONTINUE', 'failed decision requires repair and re-smoke before restart'
        last_checked = latest['epoch']
    startup = time.monotonic() + cfg['supervision']['startup_timeout_seconds']
    final_checked = False
    while True:
        heartbeat(run, 'supervisor', last_checked, 'watching')
        if not (run / 'processes.json').exists():
            if time.monotonic() > startup:
                raise TimeoutError('trainer registration missing')
            time.sleep(1)
            continue
        processes = read(run / 'processes.json')
        assert processes['supervisor']['pid'] == os.getpid()
        status = read(run / 'status.json')
        if status['state'] in ('complete', 'paused'):
            print('SUPERVISOR_EXIT', json.dumps(status), flush=True)
            return
        reason = None
        if not alive(processes['trainer']['pid']):
            reason = 'trainer process exited before completion'
        elif (run / 'trainer_heartbeat.json').exists():
            beat = read(run / 'trainer_heartbeat.json')
            if beat['pid'] != processes['trainer']['pid'] or time.time() - beat['time'] > cfg['supervision']['heartbeat_timeout_seconds']:
                reason = 'trainer heartbeat stalled or wrong PID'
        elif time.monotonic() > startup:
            reason = 'trainer heartbeat never started'
        if resources(run)['disk_free_bytes'] < cfg['supervision']['minimum_disk_free_bytes']:
            reason = 'disk free below 2 GiB'
        log_path = Path(processes['trainer']['log'])
        if log_path.exists():
            with log_path.open('rb') as stream:
                stream.seek(max(0, log_path.stat().st_size - 8192))
                tail = stream.read().decode(errors='replace')
            if 'Traceback (most recent call last)' in tail or 'CUDA out of memory' in tail:
                reason = 'fatal exception/OOM in trainer log'
            if time.time() - log_path.stat().st_mtime > 300:
                reason = 'trainer log has not progressed for 300 seconds'
        ready_path = run / 'epoch_ready.json'
        if ready_path.exists():
            ready = read(ready_path)
            if ready['epoch'] > last_checked:
                epoch, record_hash = ready['epoch'], ready['record_sha256']
                try:
                    assert epoch == last_checked + 1, 'nonsequential epoch record'
                    record = read(run / 'epoch_records' / f'epoch_{epoch:04d}.json')
                    check = check_epoch(run, cfg, record, epoch, record_hash)
                    action = 'CONTINUE'
                except Exception as exc:
                    check = {'status': 'FAIL', 'error': repr(exc), 'traceback': traceback.format_exc()}
                    action = 'PAUSE'
                    reason = f'epoch {epoch} verification failed: {exc!r}'
                check.update({'epoch': epoch, 'record_sha256': record_hash, 'supervisor_pid': os.getpid(), 'time': time.time()})
                check_path = run / 'reports' / f'check_{epoch:04d}.json'
                assert not check_path.exists()
                atomic_json(check_path, check)
                decision = {'protocol': 1, 'epoch': epoch, 'record_sha256': record_hash,
                            'run_config_sha256': sha(run / 'run_config.json'), 'supervisor_pid': os.getpid(),
                            'action': action, 'check_sha256': sha(check_path), 'time': time.time()}
                path = run / 'decisions' / f'decision_{epoch:04d}.json'
                assert not path.exists()
                atomic_json(path, decision)
                last_checked = epoch
                print('SUPERVISOR', json.dumps(check), flush=True)
        if (run / 'final_results.json').exists() and not final_checked:
            try:
                final = read(run / 'final_results.json')
                assert final['state'] == 'complete' and final['completed_epochs'] == last_checked
                assert not final['test_used_for_selection']
                assert sha(final['best_checkpoint']) == final['best_checkpoint_sha256']
                assert sha(final['best_immutable']) == final['best_immutable_sha256']
                for name in ('hipas', 'parse'):
                    check_evaluation(final['test'][name], cfg['splits'][name]['test'], ['artery', 'vein'] if name == 'hipas' else ['artery'])
                result = {'status': 'PASS', 'epochs': last_checked, 'final_results_sha256': sha(run / 'final_results.json'),
                          'supervisor_pid': os.getpid(), 'time': time.time()}
            except Exception as exc:
                result = {'status': 'FAIL', 'error': repr(exc), 'time': time.time()}
                reason = 'final result verification failed'
            atomic_json(run / 'final_check.json', result)
            final_checked = True
            print('FINAL_CHECK', json.dumps(result), flush=True)
        if reason:
            atomic_json(run / 'pause_requested.json', {'reason': reason, 'epoch': last_checked,
                                                      'supervisor_pid': os.getpid(), 'time': time.time()})
            event(run, 'supervisor_pause_request', reason=reason)
            # A dead trainer cannot save state; its last immutable checkpoint remains.
            if not alive(processes['trainer']['pid']):
                atomic_json(run / 'status.json', {'state': 'paused', 'completed_epochs': last_checked,
                                                 'error': reason, 'time': time.time()})
                return
        time.sleep(3)


def launch(run, resume=False):
    cfg = read(run / 'run_config.json')
    assert_frozen(run, cfg)
    assert read(run / 'smoke_check.json')['status'] == 'PASS'
    assert read(run / 'supervisor_selfcheck.json')['status'] == 'PASS'
    if (run / 'processes.json').exists():
        old = read(run / 'processes.json')
        assert not alive(old['trainer']['pid']) and not alive(old['supervisor']['pid']), 'run already active'
    if not resume:
        assert read(run / 'status.json')['state'] == 'ready'
    atomic_json(run / 'status.json', {'state': 'starting', 'time': time.time()})
    script = run / 'source' / Path(__file__).name
    commands = {role: [sys.executable, '-u', str(script), mode, '--run-dir', str(run)]
                for role, mode in [('supervisor', 'supervise'), ('trainer', 'train')]}
    if resume:
        commands['trainer'].append('--resume')
    suffix = f'.resume_{int(time.time())}' if resume else ''
    processes = {}
    for role in ('supervisor', 'trainer'):
        log_path = run / f'{role}{suffix}.log'
        with log_path.open('x') as stream:
            process = subprocess.Popen(commands[role], stdin=subprocess.DEVNULL, stdout=stream,
                                       stderr=subprocess.STDOUT, cwd=run, start_new_session=True)
        processes[role] = {'pid': process.pid, 'command': commands[role], 'log': str(log_path)}
    processes['started_at'] = time.time()
    processes['run_config_sha256'] = sha(run / 'run_config.json')
    atomic_json(run / 'processes.json', processes)
    print('LAUNCHED', json.dumps(processes), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('prepare', 'selfcheck', 'launch', 'train', 'supervise'))
    parser.add_argument('--run-dir', type=Path, required=True)
    parser.add_argument('--resume', action='store_true')
    args = parser.parse_args()
    if args.mode == 'prepare':
        prepare(args.run_dir)
    elif args.mode == 'selfcheck':
        load_old(args.run_dir)
        supervisor_selfcheck(args.run_dir)
    elif args.mode == 'launch':
        launch(args.run_dir, args.resume)
    elif args.mode == 'train':
        train(args.run_dir, args.resume)
    else:
        supervise(args.run_dir)


if __name__ == '__main__':
    main()

