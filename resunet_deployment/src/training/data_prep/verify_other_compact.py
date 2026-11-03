#!/usr/bin/env python3
"""Verify ATM22 or TotalSegmentator compact caches without regenerating them."""
import argparse
import csv
import hashlib
import json
import os
import time
from pathlib import Path
import sys

# Keep shared readers importable when this standalone script is run from any working directory.
SHARED_DIR = Path(__file__).resolve().parents[2] / "shared"
if str(SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_DIR))

import nibabel as nib
import numpy as np

from compact_cache_reader import open_case


LOBES = ['lung_upper_lobe_left', 'lung_lower_lobe_left',
         'lung_upper_lobe_right', 'lung_middle_lobe_right',
         'lung_lower_lobe_right']
CONTRACT = {'dtype': 'signed int8', 'shape': '[Z,3,512,512]',
            'channels': '[z-1,z,z+1]', 'boundary': 'repeat edge',
            'hu_clip': [-1024, 1000], 'round': 'NumPy rint nearest-even',
            'training_cast': 'direct float32', 'target': 'center slice'}


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
        if hasattr(os, 'posix_fadvise'):
            os.posix_fadvise(f.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
    return h.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def discover(root, task):
    """Return the source pair inventory using the same pairing rule as preparation."""
    cases, unavailable = [], []
    if task == 'atm22':
        for batch in sorted((root / 'ATM22').glob('TrainBatch*')):
            images = {p.name: p for p in (batch / 'imagesTr').glob('*.nii.gz')}
            labels = {p.name: p for p in (batch / 'labelsTr').glob('*.nii.gz')}
            for name in sorted(set(labels) - set(images)):
                unavailable.append({'case': name[:-12], 'batch': batch.name,
                                    'reason': 'label exists but CT is missing',
                                    'label': str(labels[name])})
            for name, image in sorted(images.items()):
                if name not in labels:
                    unavailable.append({'case': name[:-12], 'reason': 'missing label'})
                    continue
                cases.append({'case': name[:-12], 'task': task,
                              'batch': batch.name, 'image': str(image),
                              'labels': [str(labels[name])],
                              'target_names': ['airway']})
    elif task == 'totalsegmentator':
        ts = root / 'TotalSegmentator' / 'Totalsegmentator_dataset'
        meta_path = ts / 'meta.csv'
        with meta_path.open(encoding='utf-8-sig', newline='') as f:
            official = {r['image_id']: r for r in csv.DictReader(f, delimiter=';')}
        for image in sorted(ts.glob('s*/ct.nii.gz')):
            labels = [image.parent / 'segmentations' / f'{name}.nii.gz'
                      for name in LOBES]
            if not all(p.exists() for p in labels):
                unavailable.append({'case': image.parent.name,
                                    'reason': 'missing lobe label',
                                    'missing': [str(p) for p in labels if not p.exists()]})
                continue
            cases.append({'case': image.parent.name, 'task': task,
                          'image': str(image), 'labels': [str(p) for p in labels],
                          'target_names': LOBES,
                          'official_metadata': official.get(image.parent.name, {})})
    else:
        raise ValueError(task)
    return sorted(cases, key=lambda row: row['case']), unavailable


def verify_case(directory, row, source):
    directory = Path(directory)
    info = json.loads((directory / 'case.json').read_text(encoding='utf-8'))
    require(info == row, 'metadata row differs from case.json')
    require(info['task'] == source['task'], 'task mismatch')
    require(info['target_names'] == source['target_names'], 'target order mismatch')
    require(info['case'] == source['case'], 'case identifier mismatch')
    require(info.get('cache_version') == 'other_compact_v1', 'cache version mismatch')
    require(info.get('supervised_targets_only') == source['target_names'],
            'supervised targets mismatch')
    if source['task'] == 'atm22':
        require(info.get('batch') == source['batch'], 'source batch mismatch')
    else:
        require(info.get('official_metadata') == source['official_metadata'],
                'official metadata/split differs from source meta.csv')
    for key, value in CONTRACT.items():
        require(info.get('input_contract', {}).get(key) == value,
                f'input contract mismatch: {key}')
    require(info.get('verification', {}).get('passed') is True,
            'generation verification is not passed')
    require(info['verification'].get('all_source_masks_exact_packed_roundtrip') is True,
            'generation did not record exact label roundtrip')
    h, w, z = info['shape_h_w_z']
    require(info['input_shape'] == [z, 3, 512, 512], 'input shape mismatch')
    require(1 <= h <= 512 and 1 <= w <= 512 and z > 0, 'invalid native dimensions')
    require(source['task'] != 'atm22' or (h, w) == (512, 512),
            'ATM22 plane is not 512 x 512')
    expected_padding = {'h': [(512 - h) // 2, (513 - h) // 2],
                        'w': [(512 - w) // 2, (513 - w) // 2]}
    require(info['padding'] == expected_padding, 'padding is not centered')

    image = Path(source['image'])
    labels = [Path(p) for p in source['labels']]
    require(str(image) == info['image'], 'source image path differs')
    require([str(p) for p in labels] == info['labels'], 'source label paths differ')
    require(image.exists(), f'missing source image: {image}')
    require(sha(image) == info['source_image_sha256'], 'source image SHA256 mismatch')
    require(len(labels) == len(info['source_label_sha256']), 'source label hash count mismatch')
    for label, expected in zip(labels, info['source_label_sha256']):
        require(label.exists(), f'missing source label: {label}')
        require(sha(label) == expected, f'source label SHA256 mismatch: {label}')

    # Header inspection does not load/decompress voxel data. Voxel q checks are
    # intentionally limited to the generation record to avoid repeating work.
    nii = nib.load(str(image), mmap=False)
    require(tuple(nii.shape[:3]) == (h, w, z), 'source image shape mismatch')
    require(np.allclose(nii.affine, np.asarray(info['affine']), rtol=0, atol=1e-3),
            'source image affine mismatch')
    spacing = np.asarray(nii.header.get_zooms()[:3], dtype=np.float64)
    require(np.allclose(spacing, np.asarray(info['spacing_xyz_mm']), rtol=0, atol=1e-6),
            'source image spacing mismatch')
    for label in labels:
        lm = nib.load(str(label), mmap=False)
        require(tuple(lm.shape[:3]) == (h, w, z), f'label shape mismatch: {label}')
        require(np.allclose(lm.affine, np.asarray(info['affine']), rtol=0, atol=1e-3),
                f'label affine mismatch: {label}')
        require(np.allclose(np.asarray(lm.header.get_zooms()[:3]), spacing,
                            rtol=0, atol=1e-6), f'label spacing mismatch: {label}')

    qpath, lpath = directory / 'q.npy', directory / 'labels.npz'
    require(qpath.exists() and lpath.exists(), 'cache files missing')
    require(sha(qpath) == info['cache_sha256']['q.npy'], 'q.npy SHA256 mismatch')
    require(sha(lpath) == info['cache_sha256']['labels.npz'], 'labels.npz SHA256 mismatch')
    case = open_case(directory)
    require(case.q.shape == (z, h, w) and case.q.dtype == np.int8,
            'q.npy shape/dtype mismatch')
    require(case.q.flags.c_contiguous, 'q.npy is not C-order')
    require(qpath.stat().st_size == case.q.offset + case.q.nbytes,
            'q.npy payload size mismatch')
    k = len(source['target_names'])
    counts = np.zeros((k, z), dtype=np.int64)
    boundary = [{key: 0 for key in ('h0', 'h1', 'w0', 'w1', 'z0', 'z1')}
                for _ in range(k)]
    overlap = 0
    bits = case.bits
    if w % 8:
        require(not np.any(bits[..., -1] & (255 ^ ((1 << (w % 8)) - 1))),
                'nonzero padding bits in packed labels')
    for start in range(0, z, 16):
        masks = np.unpackbits(bits[:, start:start + 16], axis=-1, count=w,
                              bitorder='little')
        counts[:, start:start + masks.shape[1]] = masks.sum(axis=(2, 3), dtype=np.int64)
        overlap += int(np.count_nonzero(masks.sum(axis=0) >= 2))
        for j in range(k):
            m = masks[j]
            boundary[j]['h0'] += int(m[:, 0, :].sum())
            boundary[j]['h1'] += int(m[:, -1, :].sum())
            boundary[j]['w0'] += int(m[:, :, 0].sum())
            boundary[j]['w1'] += int(m[:, :, -1].sum())
            if start == 0:
                boundary[j]['z0'] = int(m[0].sum())
            if start + m.shape[0] == z:
                boundary[j]['z1'] = int(m[-1].sum())
    require(counts.sum(axis=1).tolist() == info['label_voxels'], 'label voxel counts mismatch')
    require([np.flatnonzero(c).tolist() for c in counts] == info['positive_slices_per_target'],
            'positive slice lists mismatch')
    require(boundary == info['label_boundary_voxels'], 'label boundary counts mismatch')
    require(overlap == info['overlap_voxels'], 'overlap count mismatch')

    selected = sorted({0, z - 1, z // 2, z // 3, 2 * z // 3})
    require(info['verification'].get('ct_centers_checked') == selected,
            'generation CT representative centers differ')
    ph, pw = info['padding']['h'][0], info['padding']['w'][0]
    for center in selected:
        channels = [max(0, center - 1), center, min(z - 1, center + 1)]
        x, y, valid = case.read_sample(center)
        expected = case.q[channels].astype(np.float32)
        require(x.dtype == np.float32 and x.shape == (3, 512, 512),
                'reader input shape/dtype mismatch')
        require(y.dtype == valid.dtype == np.uint8 and y.shape == (k, 512, 512)
                and valid.shape == (1, 512, 512), 'reader labels/valid shape/dtype mismatch')
        require(np.array_equal(x[:, ph:ph + h, pw:pw + w], expected),
                'reader q differs from direct float32 cast')
        require(np.all(x[:, :ph] == -128) and np.all(x[:, ph + h:] == -128)
                and np.all(x[:, :, :pw] == -128)
                and np.all(x[:, :, pw + w:] == -128), 'q padding mismatch')
        expected_y = np.unpackbits(bits[:, center], axis=-1, count=w,
                                   bitorder='little')
        require(np.array_equal(y[:, ph:ph + h, pw:pw + w], expected_y),
                'reader center labels mismatch')
        require(np.all(y[:, :ph] == 0) and np.all(y[:, ph + h:] == 0)
                and np.all(y[:, :, :pw] == 0)
                and np.all(y[:, :, pw + w:] == 0), 'label padding mismatch')
        expected_valid = (expected_y.sum(axis=0) < 2).astype(np.uint8)
        require(np.array_equal(valid[0, ph:ph + h, pw:pw + w], expected_valid),
                'reader overlap-valid mismatch')
        require(np.all(valid[:, :ph] == 0) and np.all(valid[:, ph + h:] == 0)
                and np.all(valid[:, :, :pw] == 0)
                and np.all(valid[:, :, pw + w:] == 0), 'valid padding mismatch')
        int_x, int_y, int_valid = case.read_sample(center, float32=False)
        require(int_x.dtype == np.int8 and np.array_equal(int_x.astype(np.float32), x),
                'signed INT8 reader differs from direct float32 cast')
        require(np.array_equal(int_y, y) and np.array_equal(int_valid, valid),
                'labels/valid change with input cast')
    if source['task'] == 'totalsegmentator':
        all_nonempty = all(int(c) > 0 for c in counts.sum(axis=1))
        touches_z = any(int(b['z0']) or int(b['z1']) for b in boundary)
        candidate = all_nonempty and not touches_z
        coverage = info.get('lung_coverage', {})
        require(coverage.get('all_five_lobes_nonempty') is all_nonempty,
                'coverage nonempty flag mismatch')
        require(coverage.get('target_touches_z_edge') is touches_z,
                'coverage z-edge flag mismatch')
        require(coverage.get('complete_lung_candidate') is candidate,
                'coverage candidate mismatch')
        require(coverage.get('requires_visual_review_before_complete_lung_evaluation') is True,
                'coverage visual-review requirement missing')
    del case
    return {'case': source['case'], 'passed': True, 'slices': z,
            'targets': k, 'label_voxels': info['label_voxels'],
            'overlap_voxels': overlap, 'error': ''}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--task', choices=['atm22', 'totalsegmentator'], required=True)
    parser.add_argument('--out', type=Path, required=True,
                        help='task directory containing cases/metadata.json')
    parser.add_argument('--data-root', type=Path, default=Path('/root/autodl-tmp/datasets'))
    parser.add_argument('--case', help='verify a single completed case; does not claim full completion')
    args = parser.parse_args()
    start = time.monotonic()
    metadata = json.loads((args.out / 'metadata.json').read_text(encoding='utf-8'))
    source_cases, unavailable = discover(args.data_root, args.task)
    cached = {r['case']: r for r in metadata.get('cases', [])}
    source_map = {r['case']: r for r in source_cases}
    require(len(source_map) == len(source_cases) > 0, 'empty or duplicate source inventory')
    require(len(cached) == len(metadata.get('cases', [])), 'duplicate metadata case IDs')
    require(metadata.get('task') == args.task, 'aggregate task mismatch')
    require(metadata.get('case_count') == len(cached), 'aggregate case count mismatch')
    require(metadata.get('expected_cases') == len(source_cases), 'expected case count mismatch')
    require(metadata.get('unavailable') == unavailable, 'unavailable source inventory mismatch')
    present = {p.name for p in (args.out / 'cases').iterdir() if p.is_dir()}
    if args.case:
        require(args.case in present and args.case in cached and args.case in source_map,
                'selected case absent from completed cache or source inventory')
        names = [args.case]
    else:
        require(set(cached) == set(source_map), 'cached/source case IDs differ')
        require(present == set(source_map), 'case directories differ from source inventory')
        names = sorted(source_map)
    rows = []
    for number, name in enumerate(names, 1):
        try:
            result = verify_case(args.out / 'cases' / name, cached[name], source_map[name])
        except Exception as error:
            result = {'case': name, 'passed': False,
                      'slices': cached[name].get('shape_h_w_z', [0, 0, 0])[2],
                      'targets': len(source_map[name]['target_names']),
                      'label_voxels': cached[name].get('label_voxels', []),
                      'overlap_voxels': cached[name].get('overlap_voxels', 0),
                      'error': str(error)}
        rows.append(result)
        print(f'{number}/{len(names)} {name} '
              f'{"PASS" if result["passed"] else "FAIL"} {result["error"]}', flush=True)
    fields = ['case', 'passed', 'slices', 'targets', 'label_voxels', 'overlap_voxels', 'error']
    prefix = 'single_case' if args.case else 'final'
    with (args.out / f'{prefix}_per_case_verification.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    report = {'passed': all(r['passed'] for r in rows),
              'task': args.task, 'verified_cases': len(rows),
              'verification_scope': 'single case' if args.case else 'all available paired cases',
              'full_package_complete': not args.case and all(r['passed'] for r in rows),
              'passed_cases': sum(r['passed'] for r in rows),
              'expected_cases': len(source_cases),
              'unavailable_cases': len(unavailable),
              'slices': sum(r['slices'] for r in rows),
              'completed_at': time.strftime('%F %T'),
              'seconds': round(time.monotonic() - start, 3),
              'source_inventory': 'actual paired files discovered under data-root; no assumed total',
              'source_and_cache_hashes': 'all checked cases compressed original CT/labels and q.npy/labels.npz',
              'source_quantization': 'q generation record checked; source voxel decompression not repeated',
              'geometry': 'NIfTI shape, affine (atol 1e-3), spacing checked for image and labels',
              'labels': 'all packed bits counted in 16-slice chunks; positive slices, boundary and overlap checked',
              'reader': 'five edge/center positions; signed INT8, direct float32, center labels, repeated channels and padding checked',
              'failures': [r for r in rows if not r['passed']]}
    if args.task == 'totalsegmentator':
        report['coverage'] = {'complete_candidates': sum(
            1 for name in names if cached[name].get('lung_coverage', {}).get('complete_lung_candidate')),
            'rule': 'all five labels nonempty and no target voxels on z edges; visual review remains required'}
    (args.out / f'{prefix}_verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ('passed', 'passed_cases', 'expected_cases', 'unavailable_cases', 'seconds')}), flush=True)
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
