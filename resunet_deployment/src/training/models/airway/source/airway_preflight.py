#!/usr/bin/env python3
"""Read existing cache metadata/headers; never recreate or audit source volumes."""
import argparse
import collections
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np

from compact_cache_reader import CompactCase

BASE = Path('/root/autodl-tmp/lung_training')
CACHE = BASE / 'other_compact_v1/atm22'
CONTRACT = {'dtype': 'signed int8', 'shape': '[Z,3,512,512]',
            'channels': '[z-1,z,z+1]', 'boundary': 'repeat edge',
            'hu_clip': [-1024, 1000], 'round': 'NumPy rint nearest-even',
            'training_cast': 'direct float32', 'target': 'center slice'}


def read(p):
    return json.loads(Path(p).read_text())


def sha(p):
    with Path(p).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def inventory(out):
    out.mkdir(parents=True, exist_ok=False)
    meta = read(CACHE / 'metadata.json')
    verify = read(CACHE / 'final_verification.json')
    assert meta['task'] == 'atm22' and verify['passed']
    for k, v in CONTRACT.items():
        assert meta['input_contract'][k] == v, k
    rows = meta['cases']
    assert len(rows) == meta['case_count'] == verify['verified_cases']
    assert len({r['case'] for r in rows}) == len(rows)
    header_checks, case_hashes, empty = [], {}, []
    for r in rows:
        d = CACHE / 'cases' / r['case']
        cm = read(d / 'case.json')
        for k in ('task', 'target_names', 'shape_h_w_z', 'input_shape', 'padding',
                  'affine', 'spacing_xyz_mm', 'label_voxels', 'positive_slices_per_target', 'cache_sha256'):
            assert cm[k] == r[k], (r['case'], k)
        assert r['target_names'] == ['airway'] and r['supervised_targets_only'] == ['airway']
        assert cm['verification']['passed'] and cm['verification']['all_source_masks_exact_packed_roundtrip']
        h, w, z = r['shape_h_w_z']
        q = np.load(d / 'q.npy', mmap_mode='r', allow_pickle=False)
        assert q.dtype == np.int8 and q.shape == (z, h, w) and q.flags.c_contiguous
        assert r['input_shape'] == [z, 3, 512, 512]
        assert np.isfinite(r['affine']).all() and all(v > 0 for v in r['spacing_xyz_mm'])
        assert np.allclose(np.linalg.norm(np.asarray(r['affine'])[:3, :3], axis=0), r['spacing_xyz_mm'], atol=1e-3)
        assert (d / 'labels.npz').is_file() and r['overlap_voxels'] == 0
        assert r['padding'] == {'h': [(512-h)//2, (513-h)//2], 'w': [(512-w)//2, (513-w)//2]}
        if not r['label_voxels'][0]:
            empty.append(r['case'])
        header_checks.append({'case': r['case'], 'q_shape': list(q.shape), 'q_dtype': str(q.dtype)})
        case_hashes[r['case']] = sha(d / 'case.json')
        del q
    fingerprints = collections.defaultdict(list)
    for r in rows:
        for kind, value in [('source_image_sha256', r['source_image_sha256']),
                            ('quantized_q_sha256', r['cache_sha256']['q.npy'])]:
            fingerprints[(kind, value)].append(r['case'])
    duplicates = [{'kind': k[0], 'cases': v} for k, v in fingerprints.items() if len(v) > 1]
    assert not duplicates, duplicates
    known_meta = sorted(set(list(BASE.glob('*/metadata.json')) + list((BASE/'other_compact_v1').rglob('metadata.json'))))
    matches, other_caches = [], []
    for p in known_meta:
        if p == CACHE/'metadata.json':
            continue
        m = read(p)
        other_caches.append({'path': str(p), 'task': m.get('task'), 'version': m.get('version'), 'cases': m.get('case_count'), 'sha256': sha(p)})
        for r in m.get('cases', []):
            for field in ('source_image_sha256', 'image_sha256', 'ct_sha256', 'source_sha256'):
                key = ('source_image_sha256', r.get(field))
                if key in fingerprints:
                    matches.append({'airway_cases': fingerprints[key], 'other_case': r.get('case'), 'metadata': str(p), 'method': field})
            key = ('quantized_q_sha256', r.get('cache_sha256', {}).get('q.npy'))
            if key in fingerprints:
                matches.append({'airway_cases': fingerprints[key], 'other_case': r.get('case'), 'metadata': str(p), 'method': 'q.npy SHA256'})
    existing_splits = []
    for p in BASE.rglob('patient_split.json'):
        m = read(p)
        if 'ATM_' in json.dumps(m) or 'atm22' in json.dumps(m).lower():
            existing_splits.append(str(p))
    checkpoints = sorted({str(p.parent) for p in BASE.rglob('*.pt')})
    samples = []
    for r in (rows[0], rows[len(rows)//2], rows[-1]):
        case = CompactCase(CACHE/'cases'/r['case'])
        pos = r['positive_slices_per_target'][0]
        for z in sorted({0, case.zdim-1, case.zdim//2, pos[len(pos)//2] if pos else 0}):
            x, y, mask = case.read_sample(z)
            raw, yr, mr = case.read_sample(z, float32=False)
            assert x.shape == (3,512,512) and x.dtype == np.float32
            assert y.shape == mask.shape == (1,512,512) and set(np.unique(y)) <= {0,1}
            assert np.array_equal(x, raw.astype(np.float32)) and np.array_equal(y, yr) and np.array_equal(mask, mr)
            assert np.all(y[mask == 0] == 0) and int(mask.sum()) == case.h*case.w
            if z == 0:
                assert np.array_equal(x[0], x[1])
            if z == case.zdim-1:
                assert np.array_equal(x[2], x[1])
            samples.append({'case': r['case'], 'z': z, 'x_shape': list(x.shape), 'dtype': str(x.dtype),
                            'x_range': [float(x.min()),float(x.max())], 'label_values': np.unique(y).tolist(),
                            'positive_voxels': int(y.sum()), 'valid_voxels': int(mask.sum())})
    total = sum(r['shape_h_w_z'][2] for r in rows)
    positive = sum(len(r['positive_slices_per_target'][0]) for r in rows)
    result = {'status':'PASS', 'scope':'existing metadata, all small case.json and q headers, 3 representative cache readers; no source audit',
              'dataset':'ATM22 labelled TrainBatch1/TrainBatch2', 'cache':str(CACHE), 'cache_version':meta['version'],
              'input_contract':meta['input_contract'], 'label_mapping':{'background':0,'airway':1}, 'output_logits':1,
              'cases':len(rows), 'batches':dict(collections.Counter(r['batch'] for r in rows)),
              'slices':total, 'positive_slices':positive, 'empty_slices':total-positive, 'positive_slice_fraction':positive/total,
              'empty_labels':empty, 'unavailable':meta['unavailable'], 'header_checks':header_checks, 'samples':samples,
              'shape_z_range':[min(r['shape_h_w_z'][2] for r in rows),max(r['shape_h_w_z'][2] for r in rows)],
              'geometry':{'axes':'source [X,Y,Z] -> cache [Z,H=X,W=Y]; no reorientation/resampling',
                          'spacing_z_h_w_mm':'[spacing_xyz_mm[2], spacing_xyz_mm[0], spacing_xyz_mm[1]]',
                          'source_alignment_evidence':verify['geometry'], 'current_source_files_available':False,
                          'limit':'Original ATM22 volumes were removed after verified preprocessing; rely on existing source hashes and geometry checks.'},
              'metadata_sha256':sha(CACHE/'metadata.json'), 'verification_sha256':sha(CACHE/'final_verification.json'),
              'case_json_sha256':case_hashes, 'within_cache_duplicate_groups':duplicates, 'cross_dataset_exact_matches':matches,
              'duplicate_limit':'Exact compressed source and quantized q hashes; deidentified metadata cannot rule out re-encoded same-patient scans.',
              'other_caches':other_caches, 'existing_airway_splits':existing_splits,
              'split_policy':'Reuse saved airway split if present; otherwise create one fixed internal patient split from labelled official training pool.',
              'checkpoint_directories_searched':checkpoints, 'trusted_airway_checkpoint':None,
              'excluded':'PARSE/HiPaS/NSCLC/TotalSegmentator labels and unlabelled evaluation are not Airway training data',
              'gpu':subprocess.check_output(['nvidia-smi'],text=True), 'disk':shutil.disk_usage(CACHE)._asdict(),
              'python':sys.executable}
    for name in ('metadata.json','final_verification.json','verification.json'):
        shutil.copy2(CACHE/name, out/name)
    (out/'preflight.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps({k:result[k] for k in ('status','dataset','cases','batches','slices','positive_slices','empty_slices','empty_labels','shape_z_range','existing_airway_splits','trusted_airway_checkpoint','cross_dataset_exact_matches')},indent=2))


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--audit-dir',type=Path,required=True)
    inventory(parser.parse_args().audit_dir)
