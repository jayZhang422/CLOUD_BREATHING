#!/usr/bin/env python3
"""Train a fresh base64 mkdc model with balanced sources and mixed-patient batches."""
import argparse
from collections import Counter, OrderedDict, deque
import csv
import fcntl
import hashlib
import json
import math
from pathlib import Path
import random
import time
import traceback

import numpy as np
import torch

import train_task06_mkdc_finetune_100 as recipe
from task06_cache_reader_v2 import Task06Case

BASE = Path('/root/autodl-tmp/lung_training')
ROOTS = {'Task06': BASE / 'task06_tumor_cache_v1',
         'NSCLC': BASE / 'nsclc_radiomics_cache_v1'}
SEED = 20261011


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


class JointCache:
    def __init__(self):
        self.case_metadata = {}
        self.open_cases = OrderedDict()
        for source, root in ROOTS.items():
            metadata = json.loads((root / 'metadata.json').read_text())
            if source == 'Task06':
                contract = metadata['input_contract']
                verification = json.loads((root / 'verification.json').read_text())
                assert verification['passed'] and verification['checked_cases'] == 63
            assert metadata['input_contract'] == contract and metadata['all_slices']
            self.case_metadata.update({f'{source}/{row["case"]}': row for row in metadata['cases']})

    def open_case(self, key):
        if key not in self.open_cases:
            source, _ = key.split('/')
            self.open_cases[key] = Task06Case(ROOTS[source], self.case_metadata[key])
        self.open_cases.move_to_end(key)
        if len(self.open_cases) > 24:
            self.open_cases.popitem(last=False)
        return self.open_cases[key]

    def read_sample(self, key, z):
        x, y = self.open_case(key).read_sample(z)
        return x, y.astype(np.float32)


def load_split(path, cache):
    split = json.loads(path.read_text())
    assert set(split) == {'train', 'val', 'test'}
    all_keys = [key for keys in split.values() for key in keys]
    assert len(all_keys) == len(set(all_keys))
    assert set(all_keys) == set(cache.case_metadata) - {'NSCLC/LUNG1-246'}
    for part, expected in [('train', recipe.TRAIN_CASES), ('val', recipe.VAL_CASES), ('test', recipe.TEST_CASES)]:
        assert sorted(key.split('/')[1] for key in split[part] if key.startswith('Task06/')) == sorted(expected)
    assert [len(split[x]) for x in ('train', 'val', 'test')] == [344, 73, 66]
    partition_by_hash = {}
    for part, keys in split.items():
        for key in keys:
            image_hash = cache.case_metadata[key]['image_sha256']
            assert partition_by_hash.setdefault(image_hash, part) == part, f'Exact image duplicate across splits: {key}'
    return split


def epoch_batches(cache, train_keys, epoch):
    """Cycle every patient before revisiting; mix four patients per source."""
    rng = np.random.default_rng(SEED + epoch * 1009)
    pools = {source: sorted(k for k in train_keys if k.startswith(source + '/')) for source in ROOTS}
    queues = {source: deque() for source in ROOTS}
    slices, visits = {}, Counter()
    phases = {key: int(rng.integers(2)) for key in train_keys}
    steps = math.ceil(16 * len(pools['NSCLC']) / 4)
    for _ in range(steps):
        refs = []
        for source, pool in pools.items():
            chosen, deferred = [], []
            while len(chosen) < 4:
                if not queues[source]:
                    queues[source].extend(rng.permutation(pool).tolist())
                key = queues[source].popleft()
                if key in chosen:
                    deferred.append(key)
                else:
                    chosen.append(key)
            queues[source].extendleft(reversed(deferred))
            for key in chosen:
                positive = (visits[key] + phases[key]) % 2 == 0
                visits[key] += 1
                group = 'positive_slices' if positive else 'negative_slices'
                slot = (key, group)
                if not slices.get(slot):
                    slices[slot] = deque(rng.permutation(cache.case_metadata[key][group]).tolist())
                refs.append((key, slices[slot].popleft()))
        yield refs


def mixed_arrays(cache, refs, rng):
    xs, ys = [], []
    for key, z in refs:
        x, y = cache.read_sample(key, z)
        if rng.random() < 0.5:
            x, y = x[:, :, ::-1], y[:, :, ::-1]
        if rng.random() < 0.5:
            x, y = x[:, ::-1, :], y[:, ::-1, :]
        xs.append(np.ascontiguousarray(x)); ys.append(np.ascontiguousarray(y))
    return np.stack(xs), np.stack(ys)


def preflight(cache, split, run, config):
    # Check stored labels once; this does not establish the original annotation quality.
    signature = []
    for part, keys in split.items():
        for key in keys:
            source, case = key.split('/')
            for suffix in ('x', 'y'):
                path = ROOTS[source] / 'samples' / f'{case}_{suffix}.npy'
                stat = path.stat()
                signature.append((key, suffix, stat.st_size, stat.st_mtime_ns))
    fingerprint = hashlib.sha256(json.dumps(signature).encode()).hexdigest()
    path = run / 'preflight.json'
    if path.exists():
        result = json.loads(path.read_text())
        assert result['cache_file_fingerprint'] == fingerprint and result['config'] == config
        return result
    for i, key in enumerate(split['train'] + split['val'] + split['test']):
        case = cache.open_case(key)
        case.check_representative()
        counts = []
        for start in range(0, case.zdim, 16):
            block = case.y[start:start + 16]
            assert not (block > 1).any(), f'Nonbinary label: {key}'
            counts.extend(block.sum(axis=(1, 2, 3)).tolist())
        assert np.flatnonzero(counts).tolist() == case.positive_slices, f'Label/sampling mismatch: {key}'
        assert case.positive_slices and case.negative_slices, f'Empty sampling stratum: {key}'
        if (i + 1) % 50 == 0:
            print(f'Preflight labels {i + 1}/483 PASS', flush=True)
    checks = []
    for epoch in (1, 2, 100):
        seen, sampled = set(), Counter()
        positive = Counter()
        for refs in epoch_batches(cache, split['train'], epoch):
            assert len(refs) == len({key for key, _ in refs}) == 8
            assert sum(key.startswith('Task06/') for key, _ in refs) == 4
            for key, z in refs:
                seen.add(key); source = key.split('/')[0]; sampled[source] += 1
                positive[source] += int(z in cache.case_metadata[key]['positive_slices'])
                assert key in split['train']
        assert seen == set(split['train']) and sampled['Task06'] == sampled['NSCLC']
        assert all(abs(positive[s] / sampled[s] - 0.5) < 0.02 for s in ROOTS)
        checks.append({'epoch': epoch, 'patients': len(seen), 'samples': dict(sampled), 'positive_samples': dict(positive)})
    result = {'status': 'PASS', 'checked_cases': 483, 'split_overlap': False,
              'stored_labels_and_neighbor_slices': 'PASS', 'cache_file_fingerprint': fingerprint,
              'excluded': ['NSCLC/LUNG1-246', 'NSCLC/LUNG1-128 (missing label; absent from cache)'],
              'sampler_checks': checks, 'config': config}
    recipe.atomic_json(path, result)
    return result


def evaluate(net, cache, keys):
    by_source, cases = {}, []
    for source in ROOTS:
        subset = [key for key in keys if key.startswith(source + '/')]
        result = recipe.validate(net, cache, subset, torch.device('cuda'), 8, True)
        rows = result.pop('cases'); cases.extend(rows)
        result['macro_dice'] = float(np.mean([row['dice'] for row in rows]))
        by_source[source] = result
    totals = [sum(row[name] for row in cases) for name in ('tp', 'fp', 'fn')]
    dice, precision, recall = recipe.metrics(*totals)
    return {'by_dataset': by_source, 'global_dice': dice, 'macro_dice': float(np.mean([r['dice'] for r in cases])),
            'precision': precision, 'recall': recall, 'cases': cases,
            'selection_score': float(np.mean([r['dice'] for r in by_source.values()]))}


def checkpoint(epoch, score, best_epoch, net, optimizer, scaler, config):
    state = recipe.checkpoint_state(epoch, score, net, optimizer, scaler, config, best_epoch)
    state['best_score'] = state.pop('best_dice')
    return state


def smoke(cache, split, run, config):
    recipe.seed_all(SEED)
    net = recipe.Net(64).cuda()
    assert sum(p.numel() for p in net.parameters()) == 1353921
    optimizer = torch.optim.Adam(net.parameters(), lr=config['lr'])
    scaler = torch.cuda.amp.GradScaler(init_scale=1024)
    refs = next(epoch_batches(cache, split['train'], 1))
    x, y = mixed_arrays(cache, refs, random.Random(SEED))
    assert x.shape == (8, 3, 512, 512) and y.shape == (8, 1, 512, 512)
    assert x.dtype == y.dtype == np.float32 and set(np.unique(y)) <= {0, 1}
    before = {k: v.detach().clone() for k, v in net.named_parameters()}
    net.train()
    with torch.autocast('cuda', dtype=torch.float16):
        logits = net(torch.from_numpy(x).cuda())
        assert logits.shape == y.shape
        loss = recipe.loss_value(logits, torch.from_numpy(y).cuda())
    assert torch.isfinite(loss)
    scaler.scale(loss).backward(); scaler.unscale_(optimizer)
    assert all(p.grad is None or torch.isfinite(p.grad).all() for p in net.parameters())
    torch.nn.utils.clip_grad_norm_(net.parameters(), 1.0)
    scaler.step(optimizer); scaler.update()
    assert any(not torch.equal(before[k], v) for k, v in net.named_parameters())
    # Check the actual save/restore path before leaving a detached training process.
    saved = checkpoint(0, 0.0, 0, net, optimizer, scaler, config)
    path = run / 'smoke_checkpoint.pt'
    recipe.atomic_checkpoint(path, saved)
    restored = torch.load(path, map_location='cpu', weights_only=False)
    assert restored['config'] == config
    assert all(torch.equal(value.cpu(), restored['model'][key]) for key, value in net.state_dict().items())
    net.load_state_dict(restored['model'], strict=True)
    optimizer.load_state_dict(restored['optimizer']); scaler.load_state_dict(restored['scaler'])
    recipe.restore_random_state(restored)
    path.unlink()
    result = {'status': 'PASS', 'real_mixed_batch': refs, 'loss': float(loss),
              'finite_gradient_and_parameter_update': 'PASS', 'checkpoint_roundtrip': 'PASS',
              'parameters': 1353921, 'base': 64, 'logits_shape': list(logits.shape),
              'peak_allocated_mib': torch.cuda.max_memory_allocated() / 1024 ** 2,
              'peak_reserved_mib': torch.cuda.max_memory_reserved() / 1024 ** 2,
              'device': torch.cuda.get_device_name(0)}
    recipe.atomic_json(run / 'smoke.json', result)
    print(f'Smoke PASS: eight patients, two sources, finite gradient, weights updated; loss={loss.item():.6f}', flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--run', type=Path, required=True)
    ap.add_argument('--split-source', type=Path, required=True)
    ap.add_argument('--epochs', type=int, default=100)
    ap.add_argument('--lr', type=float, default=3e-4)
    ap.add_argument('--check-only', action='store_true')
    args = ap.parse_args()
    assert args.epochs > 1 and args.lr > 0
    run = args.run; run.mkdir(parents=True, exist_ok=True)
    lock = (run / 'training.lock').open('a'); fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    torch.set_num_threads(8)
    cache = JointCache(); split = load_split(args.split_source, cache)
    config = {'version': 'base64_supervised_mixed_patient_v1', 'model': 'base64 mkdc + MaxPool + ReLU6',
              'base': 64, 'channels': [64, 128, 256, 512], 'blocks_per_stage': 1,
              'parameters': 1353921, 'initialization': 'seeded PyTorch default initialization; no base16 weights loaded',
              'input_contract': 'unchanged signed INT8 [z-1,z,z+1] direct float32, native spacing',
              'split_source': str(args.split_source), 'split_sha256': digest(args.split_source),
              'epochs': args.epochs, 'lr': args.lr, 'lr_floor': args.lr * 0.01, 'schedule': f'{args.epochs}-epoch cosine',
              'seed': SEED, 'batch_size': 8, 'sampling': '4 distinct Task06 + 4 distinct NSCLC patients per batch; shuffled patient cycles; alternating positive/negative slices per patient; 1176 batches/epoch',
              'optimizer': 'fresh Adam; model and BN initialized from scratch',
              'bn': 'trainable affine and running statistics; original default momentum=0.1',
              'loss': 'existing 0.5 voxel-balanced BCE + 0.5 soft Dice; no teacher; clip=1; AMP init_scale=1024',
              'best_rule': 'mean of Task06 and NSCLC validation Global Dice', 'early_stopping': False,
              'test_policy': 'test excluded from optimization, checkpoint selection, and inference in this run',
              'cache_metadata_sha256': {s: digest(p / 'metadata.json') for s, p in ROOTS.items()},
              'source_sha256': {p.name: digest(p) for p in Path(__file__).parent.glob('*.py')}}
    config_path = run / 'config.json'
    if config_path.exists():
        assert json.loads(config_path.read_text()) == config, 'Changed config; use a new run directory'
    else:
        recipe.atomic_json(config_path, config); recipe.atomic_json(run / 'patient_split.json', split)
    preflight(cache, split, run, config)
    if args.check_only:
        smoke(cache, split, run, config)
        return
    assert json.loads((run / 'smoke.json').read_text())['status'] == 'PASS'
    recipe.seed_all(SEED)
    torch.backends.cudnn.benchmark = False; torch.backends.cudnn.deterministic = True
    net = recipe.Net(64).cuda(); optimizer = torch.optim.Adam(net.parameters(), lr=args.lr)
    scaler = torch.cuda.amp.GradScaler(init_scale=1024)
    last = run / 'last.pt'; best = run / 'best.pt'
    (run / 'epoch_records').mkdir(exist_ok=True)
    history = list(csv.DictReader((run / 'epochs.csv').open())) if (run / 'epochs.csv').exists() else []
    if last.exists():
        state = torch.load(last, map_location='cpu', weights_only=False)
        assert state['config'] == config
        net.load_state_dict(state['model']); optimizer.load_state_dict(state['optimizer']); scaler.load_state_dict(state['scaler'])
        recipe.restore_random_state(state)
        start, best_score, best_epoch = state['epoch'] + 1, state['best_score'], state['best_epoch']
    else:
        recipe.atomic_json(run / 'status.json', {'state': 'initial_validation', 'epoch': 0})
        validation = evaluate(net, cache, split['val'])
        recipe.atomic_json(run / 'initial_validation.json', validation)
        best_score, best_epoch, start = validation['selection_score'], 0, 1
        recipe.atomic_checkpoint(best, checkpoint(0, best_score, 0, net, optimizer, scaler, config))
        print(f'Initial: Task06={validation["by_dataset"]["Task06"]["dice"]:.6f} NSCLC={validation["by_dataset"]["NSCLC"]["dice"]:.6f} Score={best_score:.6f}', flush=True)
    for epoch in range(start, args.epochs + 1):
        begun = time.monotonic(); net.train(); skipped = 0; loss_sum = 0.0; samples = 0
        lr = recipe.epoch_lr(args.lr, epoch, args.epochs)
        for group in optimizer.param_groups:
            group['lr'] = lr
        recipe.atomic_json(run / 'status.json', {'state': 'training', 'epoch': epoch, 'best_score': best_score})
        rng = random.Random(SEED + epoch * 7919)
        for step, refs in enumerate(epoch_batches(cache, split['train'], epoch), 1):
            x, y = mixed_arrays(cache, refs, rng)
            optimizer.zero_grad(set_to_none=True)
            with torch.autocast('cuda', dtype=torch.float16):
                logits = net(torch.from_numpy(x).cuda())
                loss = recipe.loss_value(logits, torch.from_numpy(y).cuda())
            if not torch.isfinite(loss):
                raise FloatingPointError(f'Nonfinite loss: epoch={epoch} step={step}')
            scaler.scale(loss).backward(); scaler.unscale_(optimizer)
            torch.nn.utils.clip_grad_norm_(net.parameters(), 1.0)
            scale_before = scaler.get_scale(); scaler.step(optimizer); scaler.update()
            skipped += int(scaler.get_scale() < scale_before)
            if skipped > 5:
                raise FloatingPointError(f'Excessive AMP skips: epoch={epoch}, count={skipped}')
            loss_sum += float(loss.detach()) * 8; samples += 8
            if step % 200 == 0:
                print(f'Epoch {epoch}/{args.epochs} step {step}/1176 loss={loss_sum/samples:.6f} AMPskips={skipped}', flush=True)
                recipe.atomic_json(run / 'status.json', {'state': 'training', 'epoch': epoch, 'step': step, 'best_score': best_score})
        recipe.atomic_json(run / 'status.json', {'state': 'validation', 'epoch': epoch, 'best_score': best_score})
        validation = evaluate(net, cache, split['val'])
        score = validation['selection_score']; improved = score > best_score
        if improved:
            best_score, best_epoch = score, epoch
        task, ns = validation['by_dataset']['Task06'], validation['by_dataset']['NSCLC']
        row = {'epoch': epoch, 'train_loss': loss_sum / samples, 'task06_dice': task['dice'], 'task06_macro': task['macro_dice'],
               'task06_precision': task['precision'], 'task06_recall': task['recall'], 'nsclc_dice': ns['dice'],
               'nsclc_macro': ns['macro_dice'], 'nsclc_precision': ns['precision'], 'nsclc_recall': ns['recall'],
               'global_dice': validation['global_dice'], 'macro_dice': validation['macro_dice'], 'selection_score': score,
               'best_score': best_score, 'lr': lr, 'samples': samples, 'amp_skipped_steps': skipped,
               'seconds': time.monotonic() - begun}
        recipe.atomic_json(run / 'epoch_records' / f'epoch_{epoch:04d}.json', {'row': row, 'validation': validation})
        recipe.atomic_checkpoint(last, checkpoint(epoch, best_score, best_epoch, net, optimizer, scaler, config))
        if improved:
            recipe.checkpoint_alias(last, best)
        history.append(row); recipe.write_csv(run / 'epochs.csv', history)
        print(f'Epoch {epoch}/{args.epochs}: Task06={task["dice"]:.6f} NSCLC={ns["dice"]:.6f} Score={score:.6f} Best={best_score:.6f} Macro={validation["macro_dice"]:.6f} LR={lr:.8f} AMPskips={skipped} Seconds={row["seconds"]:.1f}', flush=True)
    result = {'state': 'complete', 'completed_epochs': args.epochs, 'best_epoch': best_epoch, 'best_score': best_score,
              'best_rule': config['best_rule'], 'test_evaluated': False}
    recipe.atomic_json(run / 'final_results.json', result); recipe.atomic_json(run / 'status.json', result)


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Keep the traceback alongside the independently saved last/best checkpoints.
        import sys
        if '--run' in sys.argv:
            directory = Path(sys.argv[sys.argv.index('--run') + 1])
            if directory.exists():
                recipe.atomic_json(directory / 'status.json', {'state': 'failed', 'error': traceback.format_exc()})
        raise
