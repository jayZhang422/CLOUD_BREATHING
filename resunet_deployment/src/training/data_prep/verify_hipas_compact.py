#!/usr/bin/env python3
"""Verify completed HiPaS compact caches against the existing audit and split."""
import argparse
import csv
import hashlib
import json
import shutil
import time
from pathlib import Path
import sys

# Keep shared readers importable when this standalone script is run from any working directory.
SHARED_DIR = Path(__file__).resolve().parents[2] / "shared"
if str(SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_DIR))

import numpy as np

from compact_cache_reader import open_case


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_case(directory, old, aggregate):
    info = json.loads((directory / 'case.json').read_text(encoding='utf-8'))
    require(info == aggregate, 'aggregate metadata differs from case.json')
    h, w, z = old['shape_h_w_z']
    require((h, w) == (512, 512), 'source plane is not 512 x 512')
    for key, expected in {
        'case': old['case'], 'task': 'hipas', 'cache_version': 'other_compact_v1',
        'shape_h_w_z': [h, w, z], 'input_shape': [z, 3, 512, 512],
        'target_names': ['artery', 'vein'], 'eligibility': old['eligibility'],
        'quarantine_reason': old['quarantine_reason'],
        'spacing_z_y_x_mm': old['spacing_z_y_x_mm'],
        'source_ct_range': [old['ct_min'], old['ct_max']],
        'clip_voxels_below': old['ct_clip_below_hu_min_voxels'],
        'clip_voxels_above': old['ct_clip_above_hu_max_voxels'],
        'label_voxels': [old['artery_voxels'], old['vein_voxels']],
        'overlap_voxels': old['overlap_voxels'],
    }.items():
        require(info.get(key) == expected, f'{key} differs from previous audit')
    require(info['verification']['passed'], 'generation verification failed')
    require(info['verification']['all_source_masks_exact_packed_roundtrip'],
            'missing source-mask roundtrip verification')
    for key, expected in {
        'dtype': 'signed int8', 'shape': '[Z,3,512,512]',
        'channels': '[z-1,z,z+1]', 'boundary': 'repeat edge',
        'hu_clip': [-1024, 1000], 'round': 'NumPy rint nearest-even',
        'training_cast': 'direct float32', 'target': 'center slice',
    }.items():
        require(info['input_contract'].get(key) == expected,
                f'input contract {key} mismatch')
    selected = sorted({0, z - 1, z // 2, z // 3, 2 * z // 3})
    require(info['verification']['ct_centers_checked'] == selected,
            'generation did not check expected source CT planes')
    for filename in ['q.npy', 'labels.npz']:
        require(sha(directory / filename) == info['cache_sha256'][filename],
                f'{filename} SHA256 mismatch')
    sources = [Path(info['image'])] + [Path(p) for p in info['labels']]
    expected_hashes = [info['source_image_sha256']] + info['source_label_sha256']
    require(len(sources) == len(expected_hashes) == 3, 'invalid source list')
    for source, expected in zip(sources, expected_hashes):
        require(sha(source) == expected, f'source SHA256 mismatch: {source}')

    case = open_case(directory)
    require(case.q.shape == (z, 512, 512) and case.q.dtype == np.int8,
            'invalid q shape or dtype')
    require(case.q.flags.c_contiguous, 'q is not C-order')
    require((directory / 'q.npy').stat().st_size == case.q.offset + case.q.nbytes,
            'q.npy file payload size mismatch')
    counts = np.zeros((2, z), dtype=np.int64)
    overlap = overlap_slices = 0
    for start in range(0, z, 16):
        masks = np.unpackbits(case.bits[:, start:start + 16], axis=-1,
                              count=512, bitorder='little')
        counts[:, start:start + 16] = masks.sum(axis=(2, 3), dtype=np.int64)
        common = masks[0] & masks[1]
        overlap += int(common.sum(dtype=np.int64))
        overlap_slices += int(np.count_nonzero(common.any(axis=(1, 2))))
    require(counts.sum(axis=1).tolist() == info['label_voxels'], 'label count mismatch')
    require(overlap == old['overlap_voxels'], 'overlap count mismatch')
    require(overlap_slices == old['overlap_slices'], 'overlap slice count mismatch')
    positive = [np.flatnonzero(c).tolist() for c in counts]
    require(positive == info['positive_slices_per_target'], 'positive target slices mismatch')
    union_positive = counts.sum(axis=0) > 0
    require(np.flatnonzero(union_positive).tolist() == old['positive_slices'],
            'positive union slices differ from audit')
    require(np.flatnonzero(~union_positive).tolist() == old['negative_slices'],
            'negative union slices differ from audit')
    for center in selected:
        channels = [max(0, center - 1), center, min(z - 1, center + 1)]
        expected_x = np.asarray(case.q[channels])
        expected_y = np.unpackbits(case.bits[:, center], axis=-1,
                                    count=512, bitorder='little')
        expected_valid = (~((expected_y[0] != 0) & (expected_y[1] != 0))).astype(np.uint8)[None]
        x, y, valid = case.read_sample(center)
        require(x.dtype == np.float32 and x.shape == (3, 512, 512),
                'float32 reader shape/dtype mismatch')
        require(np.array_equal(x, expected_x.astype(np.float32)),
                'float32 input differs from direct INT8 cast')
        require(y.dtype == valid.dtype == np.uint8, 'label/valid dtype mismatch')
        require(np.array_equal(y, expected_y), 'center labels differ from packed labels')
        require(np.array_equal(valid, expected_valid), 'overlap exclusion differs from A&V')
        int_x, int_y, int_valid = case.read_sample(center, float32=False)
        require(int_x.dtype == np.int8 and np.array_equal(int_x, expected_x),
                'signed INT8 reader mismatch')
        require(np.array_equal(int_y, y) and np.array_equal(int_valid, valid),
                'labels/valid change with input cast')
    del case
    return {'case': old['case'], 'passed': True, 'slices': z,
            'eligibility': old['eligibility'], 'artery_voxels': old['artery_voxels'],
            'vein_voxels': old['vein_voxels'], 'overlap_voxels': overlap,
            'reader_centers_checked': len(selected), 'error': ''}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True,
                        help='HiPaS task directory containing cases/ and metadata.json')
    parser.add_argument('--index', type=Path, required=True,
                        help='Existing HiPaS data_index.json')
    args = parser.parse_args()
    started = time.monotonic()
    index = json.loads(args.index.read_text(encoding='utf-8'))
    metadata = json.loads((args.out / 'metadata.json').read_text(encoding='utf-8'))
    old_rows = {r['case']: r for r in index['cases']}
    new_rows = {r['case']: r for r in metadata['cases']}
    present = {p.name for p in (args.out / 'cases').iterdir() if p.is_dir()}
    require(len(index['cases']) == len(old_rows) == 250, 'audit must contain 250 unique cases')
    require(len(metadata['cases']) == len(new_rows) == 250,
            'completed metadata must contain 250 unique cases')
    require(metadata['task'] == 'hipas' and metadata['case_count'] == metadata['expected_cases'] == 250,
            'metadata completion count mismatch')
    require(present == set(old_rows) == set(new_rows), 'case IDs differ from audit')
    rows = []
    for number, name in enumerate(sorted(old_rows), 1):
        try:
            row = verify_case(args.out / 'cases' / name, old_rows[name], new_rows[name])
        except Exception as error:
            row = {'case': name, 'passed': False, 'slices': old_rows[name]['shape_h_w_z'][2],
                   'eligibility': old_rows[name]['eligibility'], 'error': str(error)}
        rows.append(row)
        print(f'{number}/250 {name} {"PASS" if row["passed"] else "FAIL"} {row["error"]}', flush=True)

    split_source = args.index.parent / 'patient_split.json'
    split_target = args.out / 'patient_split.json'
    split = json.loads(split_source.read_text(encoding='utf-8'))
    eligible = {name for name, r in old_rows.items() if r['eligibility'] == 'eligible'}
    assigned = split['train'] + split['validation'] + split['test']
    require(len(assigned) == len(set(assigned)) and set(assigned) == eligible,
            'patient split does not exactly cover eligible cases without duplicates')
    require(set(split['quarantined']) == set(old_rows) - eligible,
            'patient split quarantine IDs differ from audit')
    split_sha = sha(split_source)
    if split_target.exists():
        require(sha(split_target) == split_sha, 'existing copied split differs; will not overwrite')
    else:
        shutil.copyfile(split_source, split_target)
    require(sha(split_target) == split_sha, 'copied patient split SHA256 mismatch')
    fields = ['case', 'passed', 'slices', 'eligibility', 'artery_voxels', 'vein_voxels',
              'overlap_voxels', 'reader_centers_checked', 'error']
    with (args.out / 'final_per_case_verification.csv').open('w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    report = {'passed': all(r['passed'] for r in rows), 'verified_cases': len(rows),
              'passed_cases': sum(r['passed'] for r in rows), 'expected_cases': 250,
              'slices': sum(r['slices'] for r in rows),
              'completed_at': time.strftime('%F %T'), 'seconds': round(time.monotonic() - started, 3),
              'audit_index_sha256': sha(args.index),
              'source_and_cache_hashes': 'all compressed original CT/labels and q.npy/labels.npz checked',
              'labels': 'all packed voxels unpacked in 16-slice chunks; counts/slices/overlap match audit',
              'input': 'INT8 C-order [Z,512,512]; 5 reader centers/edges exact; direct float32 cast',
              'source_quantization': 'source CT plane comparison performed during generation; not repeated',
              'patient_split': {'file': str(split_target), 'file_sha256': split_sha,
                                'split_sha256': split['sha256'],
                                'counts': {key: len(split[key]) for key in ['train', 'validation', 'test', 'quarantined']}},
              'failures': [r for r in rows if not r['passed']]}
    (args.out / 'final_verification.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: report[k] for k in ['passed', 'passed_cases', 'slices', 'seconds']}), flush=True)
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
