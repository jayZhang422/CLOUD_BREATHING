#!/usr/bin/env python3
import argparse
import csv
import gzip
import hashlib
import json
import shutil
import tempfile
import time
from pathlib import Path

import nibabel as nib
import numpy as np


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1 << 20), b''):
            digest.update(block)
    return digest.hexdigest()


def qint8(values):
    values = np.asarray(values, dtype=np.float32)
    return (np.rint((np.clip(values, -1024, 1000).astype(np.float64)
                     + 1024.0) * 255.0 / 2024.0).astype(np.int16)
            - 128).astype(np.int8)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def array_path(out, row, kind):
    path = Path(row.get(f'{kind}_file', f'samples/{row["case"]}_{kind}.npy'))
    return path if path.is_absolute() else out / path


def load_cache(out, row, kind, shape, dtype):
    path = array_path(out, row, kind)
    array = np.load(path, mmap_mode='r', allow_pickle=False)
    require(array.shape == shape, f'{kind}: shape {array.shape} != {shape}')
    require(array.dtype == np.dtype(dtype), f'{kind}: dtype {array.dtype}')
    require(array.flags.c_contiguous, f'{kind}: array is not C-contiguous')
    require(int(row[f'{kind}_bytes']) == array.nbytes,
            f'{kind}: metadata payload bytes mismatch')
    require(path.stat().st_size == array.offset + array.nbytes,
            f'{kind}: truncated file or extra bytes')
    return array


def unpack(source, destination):
    with gzip.open(source, 'rb') as incoming, destination.open('wb') as outgoing:
        shutil.copyfileobj(incoming, outgoing, length=1 << 20)
    return nib.load(str(destination), mmap='r')


def check_case(root, out, row, source_check, seed):
    case = row['case']
    shape = tuple(row['shape'])
    require(len(shape) == 3 and shape[:2] == (512, 512) and shape[2] > 0,
            'invalid source shape in metadata')
    depth = shape[2]
    require(row['centers'] == list(range(depth)), 'centers are not all Z slices')
    x = load_cache(out, row, 'x', (depth, 3, 512, 512), np.int8)
    y = load_cache(out, row, 'y', (depth, 1, 512, 512), np.uint8)
    positive = []
    require(np.array_equal(x[0, 0], x[0, 1]), 'first boundary is not repeated')
    require(np.array_equal(x[-1, 1], x[-1, 2]), 'last boundary is not repeated')
    for start in range(0, depth, 32):
        end = min(start + 32, depth)
        masks = y[start:end, 0]
        require(np.all((masks == 0) | (masks == 1)), 'labels contain values other than 0/1')
        positive.extend((np.flatnonzero(np.any(masks != 0, axis=(1, 2))) + start).tolist())
        previous = max(1, start)
        if previous < end:
            require(np.array_equal(x[previous:end, 0], x[previous - 1:end - 1, 1]),
                    f'previous channels disagree at slices {previous}:{end}')
        following = min(end, depth - 1)
        if start < following:
            require(np.array_equal(x[start:following, 2], x[start + 1:following + 1, 1]),
                    f'following channels disagree at slices {start}:{following}')
    negative = sorted(set(range(depth)) - set(positive))
    require(row['positive_slices'] == positive, 'positive slice metadata mismatch')
    require(row['negative_slices'] == negative, 'negative slice metadata mismatch')
    image_path = root / 'imagesTr' / f'{case}.nii.gz'
    label_path = root / 'labelsTr' / f'{case}.nii.gz'
    require(sha256(image_path) == row['image_sha256'], 'image source SHA256 mismatch')
    require(sha256(label_path) == row['label_sha256'], 'label source SHA256 mismatch')
    selected = []
    if source_check:
        stable_seed = seed + int(hashlib.sha256(case.encode('ascii')).hexdigest()[:8], 16)
        rng = np.random.default_rng(stable_seed)
        centers = {0, depth - 1, depth // 2, max(positive) if positive else 0,
                   int(rng.integers(depth))}
        while len(centers) < min(depth, 5):
            centers.add(int(rng.integers(depth)))
        selected = sorted(centers)
        with tempfile.TemporaryDirectory(prefix='.task06_verify_', dir=out) as temporary:
            temporary = Path(temporary)
            image = unpack(image_path, temporary / 'image.nii')
            label = unpack(label_path, temporary / 'label.nii')
            require(image.shape == label.shape == shape, 'source shape mismatch')
            require(np.allclose(image.affine, label.affine), 'source image/label affine mismatch')
            require(np.allclose(image.affine, row['affine']), 'source/metadata affine mismatch')
            require(np.allclose(image.header.get_zooms()[:3], row['spacing_xyz_mm']),
                    'source/metadata spacing mismatch')
            for start in range(0, depth, 32):
                end = min(start + 32, depth)
                original = np.asanyarray(label.dataobj[:, :, start:end])
                require(np.array_equal(y[start:end, 0], np.moveaxis(original, 2, 0)),
                        f'source center masks disagree at slices {start}:{end}')
            for center in selected:
                for channel, index in enumerate((max(0, center - 1), center,
                                                  min(depth - 1, center + 1))):
                    source_slice = np.asarray(image.dataobj[:, :, index], dtype=np.float32)
                    require(np.all(np.isfinite(source_slice)), f'nonfinite source CT at slice={index}')
                    expected = qint8(source_slice)
                    require(np.array_equal(x[center, channel], expected),
                            f'source qint8 mismatch at center={center}, channel={channel}')
    return depth, selected


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-root', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--source-check', action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument('--seed', type=int, default=20261001)
    args = parser.parse_args()
    root, out = Path(args.data_root), Path(args.out)
    started = time.time()
    metadata = json.loads((out / 'metadata.json').read_text(encoding='utf-8'))
    rows = metadata['cases']
    images = sorted(path.name[:-7] for path in (root / 'imagesTr').glob('*.nii.gz')
                    if not path.name.startswith('._'))
    labels = sorted(path.name[:-7] for path in (root / 'labelsTr').glob('*.nii.gz')
                    if not path.name.startswith('._'))
    global_errors = []
    if not metadata.get('all_slices'):
        global_errors.append('all_slices is not true')
    if len(rows) != len({row['case'] for row in rows}):
        global_errors.append('duplicate metadata case IDs')
    if len(images) != 63:
        global_errors.append(f'expected 63 original cases, found {len(images)}')
    if metadata.get('case_count') != len(rows):
        global_errors.append('case_count disagrees with metadata rows')
    if set(images) != {row['case'] for row in rows}:
        global_errors.append('source and metadata case sets differ')
    if labels != images:
        global_errors.append('source image and label case sets differ')
    by_case = {row['case']: row for row in rows}
    results = []
    for number, case in enumerate(images, 1):
        began = time.time()
        result = {'case': case, 'status': 'FAIL', 'samples': 0,
                  'source_checked': False, 'sampled_centers': [], 'error': ''}
        try:
            require(case in by_case, 'missing metadata row')
            result['samples'], result['sampled_centers'] = check_case(
                root, out, by_case[case], args.source_check, args.seed)
            result['source_checked'] = args.source_check
            result['status'] = 'PASS'
        except Exception as error:
            result['error'] = f'{type(error).__name__}: {error}'
        result['seconds'] = round(time.time() - began, 3)
        results.append(result)
        print(f'[{number}/{len(images)}] {case} {result["status"]} '
              f'seconds={result["seconds"]} {result["error"]}', flush=True)
    report = {'passed': not global_errors and all(row['status'] == 'PASS' for row in results),
              'source_check': args.source_check, 'seed': args.seed,
              'checked_cases': len(results), 'seconds': round(time.time() - started, 3),
              'global_errors': global_errors, 'cases': results,
              'input_contract': {'dtype': 'signed int8', 'shape': '[Z,3,512,512]',
                                 'channels': '[z-1,z,z+1]', 'boundary': 'repeat edge',
                                 'hu_clip': [-1024, 1000], 'round': 'NumPy rint nearest-even',
                                 'training_cast': 'direct float32', 'target': 'center slice'}}
    temporary = out / 'verification.json.tmp'
    temporary.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    temporary.replace(out / 'verification.json')
    with (out / 'per_case_verification.csv').open('w', newline='', encoding='utf-8') as stream:
        writer = csv.DictWriter(stream, fieldnames=results[0].keys() if results else
                                ['case', 'status', 'samples', 'source_checked',
                                 'sampled_centers', 'error', 'seconds'])
        writer.writeheader()
        writer.writerows(results)
    print(json.dumps({key: value for key, value in report.items() if key != 'cases'}), flush=True)
    raise SystemExit(0 if report['passed'] else 1)


if __name__ == '__main__':
    main()
