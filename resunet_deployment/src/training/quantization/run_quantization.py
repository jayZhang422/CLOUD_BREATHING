#!/usr/bin/env python3
"""服务器独立 PTQ→评估→必要时 QAT；原实验目录仅供读取。"""
import argparse
import copy
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import random
import shutil
import sys
import time
import traceback

sys.dont_write_bytecode = True
import numpy as np
import torch

from mkdc_int8 import BLOCKS, DeploymentNet, selfcheck


BASE = Path('/root/autodl-tmp/lung_training')
SPECS = {
    'lobe': ('lung_lobe_mkdc_v1/resunet_mkdc_20e_v2', 'config.json', 12, 5,
             '8cd857837ce113469fdfb0753a9f706cb969f6b4b7d43ad48aa0c055f47af342'),
    'airway': ('airway_mkdc_v1/runs/resunet_mkdc_relu6_100e_v2', 'run_config.json', 27, 1,
               'f0141e0a3579d33b3d781abe10d3f403a22d8673c263e9aca78ff85854df75ce'),
    'vessel': ('vessel_mkdc_joint_v1/runs/resunet_mkdc_relu6_e94_joint_100e_v1', 'run_config.json', 18, 2,
               '35b490975de4b22f895498d90f573f273d7590f5c1d1aaa77a2b8a0f5c998c29'),
}


def sha(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as source:
        for data in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(data)
    return digest.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')
    temporary.replace(path)


def event(run, stage, **values):
    value = {'time_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
             'pid': os.getpid(), 'stage': stage, **values}
    write_json(run / 'status.json', value)
    print(json.dumps(value, ensure_ascii=False), flush=True)


def check_originals():
    values = {}
    for task, (directory, _, epoch, _, expected) in SPECS.items():
        for suffix in ('best.pt', f'best_records/best_epoch_{epoch:04d}.pt'):
            path = BASE / directory / suffix
            actual = sha(path)
            if actual != expected:
                raise RuntimeError(f'Original checkpoint changed: {path}')
            values[str(path)] = actual
    return values


def import_file(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def freeze(run):
    hashes = check_originals()
    for task, (directory, config_name, epoch, _, expected) in SPECS.items():
        source = BASE / directory
        target = run / 'fp32' / task
        target.mkdir(parents=True, exist_ok=True)
        checkpoint = target / f'best_epoch_{epoch:04d}.pt'
        if checkpoint.exists():
            assert sha(checkpoint) == expected
        else:
            shutil.copyfile(source / f'best_records/best_epoch_{epoch:04d}.pt', checkpoint)
            assert sha(checkpoint) == expected
        if not (target / config_name).exists():
            shutil.copyfile(source / config_name, target / config_name)
    write_json(run / 'original_sha256_before.json', hashes)


def environment(run):
    torch.manual_seed(20261011)
    random.seed(20261011)
    np.random.seed(20261011)
    torch.set_num_threads(8)
    torch.backends.cuda.matmul.allow_tf32 = False
    torch.backends.cudnn.allow_tf32 = False
    torch.backends.cudnn.benchmark = False
    torch.backends.cudnn.deterministic = True
    write_json(run / 'environment.json', {'torch': torch.__version__, 'numpy': np.__version__,
        'python': sys.version, 'gpu': torch.cuda.get_device_name(0), 'tf32': False, 'amp': False,
        'code_sha256': {p.name: sha(p) for p in Path(__file__).parent.glob('*.py')}})


def sources():
    lobe_source = BASE / SPECS['lobe'][0] / 'source'
    sys.path.insert(0, str(lobe_source))
    if not (lobe_source / 'compact_cache_reader.py').exists():
        sys.path.insert(0, str(BASE))
    old = import_file('frozen_lobe_source', lobe_source / 'train_compact_mkdc_v1.py')
    vessel = import_file('frozen_vessel_source', BASE / SPECS['vessel'][0] / 'source/vessel_joint_20261008.py')
    return old, vessel


def load_task(run, task, old, vessel):
    directory, config_name, epoch, outputs, _ = SPECS[task]
    cfg = json.loads((run / 'fp32' / task / config_name).read_text())
    checkpoint = torch.load(run / 'fp32' / task / f'best_epoch_{epoch:04d}.pt', map_location='cpu', weights_only=False)
    original = old.ResUNet(outputs, base=16, op='mkdc').eval()
    original.load_state_dict(checkpoint['model'], strict=True)
    if task == 'lobe':
        datasets = {'lobe': (old.Cache(Path(cfg['cache_root']), 'totalsegmentator'), cfg['split'])}
    elif task == 'airway':
        datasets = {'airway': (old.Cache(Path(cfg['cache']), 'atm22'), cfg['splits'])}
    else:
        vessel.PARSE = Path(cfg['datasets']['parse']['root'])
        datasets = {'hipas': (old.Cache(Path(cfg['datasets']['hipas']['root']), 'hipas'), cfg['splits']['hipas']),
                    'parse': (vessel.ParseCache(), cfg['splits']['parse'])}
    for cache, splits in datasets.values():
        assert not (set(splits['train']) & set(splits['val']))
        assert not (set(splits['train']) & set(splits['test']))
        assert not (set(splits['val']) & set(splits['test']))
        assert set(sum(splits.values(), [])) <= set(cache.rows)
    return original, datasets


def select_cases(ids, count, seed):
    return sorted(ids, key=lambda cid: hashlib.sha256(f'{seed}:{cid}'.encode()).hexdigest())[:count]


def select_slices(cache, cid, count):
    case = cache.open_case(cid)
    positives = list(map(int, cache.positive_slices(cid)))
    positive_set = set(positives)
    negatives = [z for z in range(case.zdim) if z not in positive_set]
    def spaced(values, n):
        return [values[index] for index in np.linspace(0, len(values) - 1, min(n, len(values)), dtype=int)] if values else []
    chosen = set(spaced(positives, (count + 1) // 2) + spaced(negatives, count // 2))
    for z in spaced(list(range(case.zdim)), count):
        if len(chosen) >= count:
            break
        chosen.add(z)
    return sorted(chosen)


def tensors(cache, cid, zs, device):
    values = [cache.open_case(cid).read_sample(int(z)) for z in zs]
    return tuple(torch.from_numpy(np.stack([v[index] for v in values])).to(device).float() for index in range(3))


def calibrate(run, task, model, datasets, case_count, slice_count):
    selected = []
    model.mode = 'calibrate'
    model.eval()
    with torch.inference_mode():
        for dataset, (cache, splits) in datasets.items():
            for cid in select_cases(splits['train'], case_count, 20261011):
                zs = select_slices(cache, cid, slice_count)
                for z in zs:
                    x, _, _ = tensors(cache, cid, [z], 'cuda')
                    model(x)
                selected.append({'dataset': dataset, 'case': cid, 'slices': zs})
                event(run, 'calibration', task=task, dataset=dataset, case=cid, completed_cases=len(selected))
    model.finish_calibration()
    return {'partition': 'train only', 'selection': selected, 'activation_max_abs': model.observed,
            'activation_scales': model.scales, 'zero_point': 0,
            'policy': 'per-node symmetric activation max calibration; no normalization change'}


def check_graph(original, model):
    model.mode = 'float'
    results = []
    with torch.inference_mode():
        for shape in ((1, 3, 32, 32), (1, 3, 40, 56)):
            x = torch.randint(-128, 128, shape, device='cuda').float()
            expected = original(x)
            actual = model(x)
            error = float((actual - expected).abs().max())
            assert torch.allclose(actual, expected, atol=2e-3, rtol=2e-4), error
            results.append({'shape': shape, 'max_abs_error': error})
    return {'status': 'PASS', 'checks': results, 'absolute_tolerance': 0.002, 'relative_tolerance': 0.0002}


def stats(old, counts, layers, union, union_layers, names, slices, cases):
    return {'slice_count': slices, 'case_count': cases,
        'classes': [{'name': name, **old.stats(*counts[index]), **old.layer_stats(*layers[index])}
                    for index, name in enumerate(names)],
        'union': {**old.stats(*union), **old.layer_stats(*union_layers)}}


def evaluate_pair(run, task, original, candidate, datasets, old, batch, pilot_cases=None, pilot_slices=8):
    original.eval()
    candidate.eval()
    candidate.mode = 'integer'
    candidate.prepare_integer()
    reports = {}
    with torch.inference_mode():
        for dataset, (cache, splits) in datasets.items():
            ids = splits['val'] if pilot_cases is None else select_cases(splits['val'], pilot_cases, 20261012)
            names = cache.target_names
            totals = {key: [np.zeros((len(names), 3), dtype=np.int64), np.zeros((len(names), 2), dtype=np.int64),
                            np.zeros(3, dtype=np.int64), np.zeros(2, dtype=np.int64)] for key in ('fp32', 'integer')}
            slices = 0
            per_case = []
            started = time.monotonic()
            for case_index, cid in enumerate(ids):
                case = cache.open_case(cid)
                zs = list(range(case.zdim)) if pilot_cases is None else select_slices(cache, cid, pilot_slices)
                native = torch.zeros((1, 512, 512), dtype=torch.bool, device='cuda')
                native[(0,) + case.region] = True
                local = {key: np.zeros((len(names), 3), dtype=np.int64) for key in totals}
                for start in range(0, len(zs), batch):
                    x, target, valid = tensors(cache, cid, zs[start:start + batch], 'cuda')
                    for key, network in (('fp32', original), ('integer', candidate)):
                        logits = network.dequantized(x) if key == 'integer' else network(x)
                        if dataset == 'parse':
                            logits = logits[:, :1]
                        counts = old.batch_counts(logits, target, valid, native)
                        for index in range(4):
                            totals[key][index] += counts[index]
                        local[key] += counts[0]
                    slices += x.shape[0]
                per_case.append({'case': cid, 'slices': len(zs),
                    **{key: [old.stats(*row) for row in value] for key, value in local.items()}})
                event(run, 'validation', task=task, dataset=dataset, case=cid, completed_cases=case_index + 1,
                      total_cases=len(ids), slices=slices, seconds=round(time.monotonic() - started, 1),
                      scope='full validation' if pilot_cases is None else 'pilot subset')
            reports[dataset] = {'scope': 'full validation' if pilot_cases is None else 'pilot subset; not final acceptance',
                'fp32': stats(old, *totals['fp32'], names, slices, len(ids)),
                'integer': stats(old, *totals['integer'], names, slices, len(ids)), 'per_case': per_case}
            pairs = [('union', reports[dataset]['fp32']['union'], reports[dataset]['integer']['union'])]
            pairs += [(a['name'], a, b) for a, b in zip(reports[dataset]['fp32']['classes'], reports[dataset]['integer']['classes'])]
            reports[dataset]['comparison'] = {name: {'dice_drop': a['dice'] - b['dice'],
                'recall_drop': None if a['recall'] is None or b['recall'] is None else a['recall'] - b['recall']}
                for name, a, b in pairs}
            reports[dataset]['dice_gate_pass'] = all(value['dice_drop'] <= 0.02 for value in reports[dataset]['comparison'].values())
    return reports


def export(run, task, model, original, target):
    target.mkdir(parents=True, exist_ok=False)
    model.eval()
    model.mode = 'integer'
    model.prepare_integer()
    x = torch.randint(-128, 128, (1, 3, 32, 32), device='cuda', generator=torch.Generator(device='cuda').manual_seed(20261011)).float()
    x[:, :, 0] = -128
    x[:, :, -1] = 127
    model.capture = {}
    with torch.inference_mode():
        expected = model(x).cpu()
    trace = model.capture
    model.capture = None
    # 同一小图分别使用 CPU/CUDA 整数载体计算，必须逐元素完全一致。
    cpu = copy.deepcopy(model).cpu()
    cpu.prepare_integer()
    with torch.inference_mode():
        actual = cpu(x.cpu())
    assert torch.equal(expected, actual), 'CPU/CUDA integer mismatch'
    vector_dir = target / 'golden_synthetic_32x32'
    vector_dir.mkdir()
    trace = {'input': x.cpu().to(torch.int8), **trace}
    for name, value in trace.items():
        array = value.numpy()
        array.tofile(vector_dir / (name + '.bin'))
    write_json(vector_dir / 'manifest.json', {'source': 'synthetic; no patient image/label',
        'seed': 20261011, 'layout': 'NCHW, little endian, signed two-complement',
        'tensors': {name: {'shape': list(value.shape), 'dtype': str(value.numpy().dtype),
                            'sha256': sha(vector_dir / (name + '.bin'))} for name, value in trace.items()}})
    convs = {}
    for name, value in model.packed.items():
        weight_file = name + '.weight.i8.bin'
        value['weight'].cpu().numpy().tofile(target / weight_file)
        convs[name] = {'file': weight_file, 'shape': list(value['weight'].shape), 'layout': 'OIHW',
                      'weight_scale': value['scale'].cpu().tolist(), 'groups': value['groups'], 'padding': value['padding']}
    merges = {}
    for name, config in model.merges.items():
        bias_file = name + '.bias_fixed.i64.bin'
        config['bias_fixed'].cpu().numpy().astype('<i8').tofile(target / bias_file)
        merges[name] = {**{key: value for key, value in config.items() if key not in ('bias_fixed', 'multipliers')},
            'multipliers': [value.cpu().tolist() for value in config['multipliers']], 'bias_file': bias_file,
            'formula': 'RNE((sum(INT32_acc_i * multiplier_i) + bias_fixed) / 2**shift), then clamp'}
    contract = {'task': task, 'original_sha256': SPECS[task][4], 'weights': 'signed INT8 [-127,127], per output channel',
        'features': 'signed INT8, zero_point=0, per activation node', 'input_scale': 1.0,
        'input_contract': 'cached signed INT8 cast float32 directly; no extra normalization; external padding=-128',
        'mac': 'INT32; convolution padding integer 0', 'rescale': 'INT64; checked bound <2**62; signed RNE',
        'logits': 'signed INT16; scale=head; threshold q>=0, equivalent to decoded logits>=0',
        'activation_scales': model.scales, 'convolutions': convs, 'merges': merges,
        'graph': 'expand Conv+BN→ReLU6; DW3+DW5 with shared BN absorbed once→ReLU6; PW+BN and skip→Add→ReLU6',
        'shuffle': 'removed by permuting common BN and PW input columns together before quantization',
        'concat': 'two source scales align to max(source scales) before concatenation',
        'grouping': 'hardware lane P=16; first input 3 and output heads 1/2/5 require valid-lane masks'}
    write_json(target / 'contract.json', contract)
    torch.save({'fused_model': model.state_dict(), 'scales': model.scales, 'original_sha256': SPECS[task][4]}, target / 'deployment.pt')
    # 从实际保存的包重载，确认重建后的整数结果一致。
    saved = torch.load(target / 'deployment.pt', map_location='cpu', weights_only=False)
    rebuilt = DeploymentNet(original.cpu()).cpu()
    rebuilt.load_state_dict(saved['fused_model'])
    rebuilt.scales = saved['scales']
    rebuilt.mode = 'integer'
    rebuilt.prepare_integer()
    with torch.inference_mode():
        assert torch.equal(rebuilt(x.cpu()), expected), 'Export reload mismatch'
    original.cuda()
    write_json(target / 'verification.json', {'status': 'PASS', 'cpu_cuda_integer_equal': True,
        'export_reload_integer_equal': True, 'golden_scope': 'synthetic 32x32 full network and intermediate nodes'})
    write_json(target / 'sha256.json', {str(p.relative_to(target)): sha(p) for p in target.rglob('*') if p.is_file()})


def qat(run, task, model, original, datasets, old, args):
    target = run / task / 'qat'
    target.mkdir(parents=True, exist_ok=False)
    model.mode = 'fake'
    model.train()
    optimizer = torch.optim.Adam(model.parameters(), lr=args.qat_lr)
    rng = random.Random(20261011)
    dataset_names = list(datasets)
    history = []
    best_score = -1.0
    for epoch in range(1, args.qat_epochs + 1):
        loss_sum = 0.0
        visits = {name: 0 for name in dataset_names}
        for step in range(args.qat_steps):
            dataset = dataset_names[step % len(dataset_names)]
            cache, splits = datasets[dataset]
            cid = rng.choice(splits['train'])
            zs = select_slices(cache, cid, max(args.batch, 8))
            chosen = rng.sample(zs, min(args.batch, len(zs)))
            x, y, valid = tensors(cache, cid, chosen, 'cuda')
            optimizer.zero_grad(set_to_none=True)
            logits = model(x)
            if dataset == 'parse':
                logits = logits[:, :1]  # PARSE 未标注 vein，绝不按背景监督它。
            loss = old.masked_loss(logits, y, valid)
            if not torch.isfinite(loss):
                raise RuntimeError('Nonfinite QAT loss')
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 5.0)
            optimizer.step()
            loss_sum += float(loss.detach())
            visits[dataset] += len(chosen)
            if step % 16 == 0:
                event(run, 'qat_training', task=task, epoch=epoch, step=step + 1,
                      total_steps=args.qat_steps, loss=float(loss.detach()), samples=visits)
        checkpoint = {'epoch': epoch, 'model': model.state_dict(), 'scales': model.scales,
                      'optimizer': optimizer.state_dict(), 'original_sha256': SPECS[task][4]}
        torch.save(checkpoint, target / f'epoch_{epoch:04d}.pt')
        pilot = evaluate_pair(run, task, original, model, datasets, old, args.batch,
                              pilot_cases=args.pilot_cases, pilot_slices=args.pilot_slices)
        score = np.mean([report['integer']['union']['dice'] for report in pilot.values()])
        row = {'epoch': epoch, 'loss': loss_sum / args.qat_steps, 'training_samples': visits,
               'selection_scope': 'fixed validation subset; final acceptance uses full validation', 'validation': pilot}
        history.append(row)
        write_json(target / f'epoch_{epoch:04d}.json', row)
        if score > best_score:
            best_score = score
            best_state = copy.deepcopy(model.state_dict())
            best_epoch = epoch
        model.mode = 'fake'
        model.train()
    model.load_state_dict(best_state)
    write_json(target / 'history.json', {'best_epoch': best_epoch, 'epochs': history,
        'optimizer': 'Adam', 'learning_rate': args.qat_lr, 'batch_size': args.batch,
        'bn': 'folded inference graph; no BN statistic updates', 'activation_scales': 'PTQ frozen',
        'sampling': 'training patients only; balanced dataset alternation for vessel; no geometric augmentation'})
    export(run, task, model, original, target / 'export')
    final = evaluate_pair(run, task, original, model, datasets, old, args.batch)
    write_json(target / 'full_validation.json', final)
    return final


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', type=Path, required=True)
    parser.add_argument('--phase', choices=('preflight', 'run'), default='run')
    parser.add_argument('--batch', type=int, default=4)
    parser.add_argument('--calibration-cases', type=int, default=16)
    parser.add_argument('--calibration-slices', type=int, default=4)
    parser.add_argument('--pilot-cases', type=int, default=4)
    parser.add_argument('--pilot-slices', type=int, default=8)
    parser.add_argument('--qat-epochs', type=int, default=5)
    parser.add_argument('--qat-steps', type=int, default=128)
    parser.add_argument('--qat-lr', type=float, default=1e-5)
    args = parser.parse_args()
    run = args.run.resolve()
    assert run.parent == BASE / 'deployment_quantization', 'Output must stay in the independent quantization directory'
    run.mkdir(parents=True, exist_ok=True)
    try:
        environment(run)
        freeze(run)
        old, vessel = sources()
        write_json(run / 'integer_selfcheck.json', selfcheck('cuda'))
        write_json(run / ('preflight_config.json' if args.phase == 'preflight' else 'run_config.json'),
                   {**vars(args), 'run': str(run), 'qat_policy': 'only if full-validation Dice gate fails',
                    'acceptance': 'each dataset union and each supervised class Dice drop <=0.02 absolute'})
        reports = {}
        for task in SPECS:
            event(run, 'starting_task', task=task, phase=args.phase)
            original, datasets = load_task(run, task, old, vessel)
            model = DeploymentNet(original).cuda()
            original.cuda()
            target = run / 'preflight' / task if args.phase == 'preflight' else run / task / 'ptq'
            target.mkdir(parents=True, exist_ok=False)
            write_json(target / 'graph_equivalence.json', check_graph(original, model))
            calibration = calibrate(run, task, model, datasets,
                2 if args.phase == 'preflight' else args.calibration_cases,
                2 if args.phase == 'preflight' else args.calibration_slices)
            write_json(target / 'calibration.json', calibration)
            export(run, task, model, original, target / 'export')
            started = time.monotonic()
            pilot = evaluate_pair(run, task, original, model, datasets, old, args.batch,
                                  pilot_cases=1 if args.phase == 'preflight' else args.pilot_cases,
                                  pilot_slices=2 if args.phase == 'preflight' else args.pilot_slices)
            write_json(target / 'pilot_validation.json', pilot)
            if args.phase == 'preflight':
                reports[task] = {'status': 'PREFLIGHT_PASS', 'seconds': time.monotonic() - started, 'pilot': pilot}
            else:
                full = evaluate_pair(run, task, original, model, datasets, old, args.batch)
                write_json(target / 'full_validation.json', full)
                reports[task] = {'ptq_pass': all(report['dice_gate_pass'] for report in full.values()), 'ptq': full}
            del original, model, datasets
            torch.cuda.empty_cache()
        if args.phase == 'run':
            # 三任务 PTQ 均完成后，再对未通过任务开展独立 QAT。
            for task, report in reports.items():
                if report['ptq_pass']:
                    report['qat'] = {'status': 'NOT_NEEDED', 'reason': 'PTQ passed full validation Dice gate'}
                    continue
                original, datasets = load_task(run, task, old, vessel)
                original.cuda()
                saved = torch.load(run / task / 'ptq/export/deployment.pt', map_location='cpu', weights_only=False)
                model = DeploymentNet(original.cpu()).cuda()
                original.cuda()
                model.load_state_dict(saved['fused_model'])
                model.scales = saved['scales']
                report['qat'] = qat(run, task, model, original, datasets, old, args)
                del original, model, datasets
                torch.cuda.empty_cache()
        write_json(run / ('preflight_results.json' if args.phase == 'preflight' else 'results.json'), reports)
        write_json(run / 'original_sha256_after.json', check_originals())
        accepted = args.phase == 'run' and all(report['ptq_pass'] or
            all(value['dice_gate_pass'] for value in report['qat'].values()) for report in reports.values())
        event(run, 'PREFLIGHT_COMPLETE' if args.phase == 'preflight' else 'COMPLETE', tasks=list(reports),
              originals_unchanged=True, final_acceptance=accepted)
    except Exception as error:
        event(run, 'FAILED', error=str(error), traceback=traceback.format_exc())
        write_json(run / 'original_sha256_after_failure.json', check_originals())
        raise


if __name__ == '__main__':
    main()
