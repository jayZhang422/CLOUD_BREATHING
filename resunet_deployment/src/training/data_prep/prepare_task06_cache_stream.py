#!/usr/bin/env python3
import argparse
import fcntl
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import nibabel as nib
import numpy as np


def log(message):
    print(time.strftime('%F %T ') + message, flush=True)


def qint8(x):
    return (np.rint((np.clip(x, -1024, 1000).astype(np.float64) + 1024.0)
                    * 255.0 / 2024.0).astype(np.int16) - 128).astype(np.int8)


def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def atomic_json(path, data):
    tmp = path.with_name(path.name + '.tmp')
    with tmp.open('w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    tmp.replace(path)


def check_cached(out, row):
    z = row['shape'][2]
    if row['centers'] != list(range(z)):
        raise ValueError(f"{row['case']}: cache does not contain all slices")
    for suffix, dtype, shape in (
            ('x', np.int8, (z, 3, 512, 512)),
            ('y', np.uint8, (z, 1, 512, 512))):
        path = out / 'samples' / f"{row['case']}_{suffix}.npy"
        arr = np.load(path, mmap_mode='r', allow_pickle=False)
        if arr.dtype != dtype or arr.shape != shape or not arr.flags.c_contiguous:
            raise ValueError(f'{path}: invalid dtype/shape/layout')
        if arr.nbytes != row[f'{suffix}_bytes'] or path.stat().st_size != arr.offset + arr.nbytes:
            raise ValueError(f'{path}: invalid payload/file size')
        del arr


def convert(root, out, case):
    started = time.monotonic()
    image = root / 'imagesTr' / f'{case}.nii.gz'
    label = root / 'labelsTr' / image.name
    samples = out / 'samples'
    samples.mkdir(exist_ok=True)
    xp, yp = (samples / f'{case}_{s}.npy' for s in ('x', 'y'))
    if xp.exists() or yp.exists():
        raise FileExistsError(f'{case}: existing unregistered files must be preserved first')
    log(f'UNPACK {case}')
    # A gzip proxy rereads earlier slices on backwards seeks. Unpack each source once.
    with tempfile.TemporaryDirectory(prefix=f'.unpack_{case}_', dir=out) as td:
        paths = []
        for source, name in ((image, 'image.nii'), (label, 'label.nii')):
            dest = Path(td) / name
            with gzip.open(source, 'rb') as inp, dest.open('wb') as dest_file:
                shutil.copyfileobj(inp, dest_file, length=1 << 20)
            paths.append(dest)
        im, la = (nib.load(str(path), mmap='r') for path in paths)
        if im.shape != la.shape or im.shape[:2] != (512, 512) or not np.allclose(im.affine, la.affine):
            raise ValueError(f'{case}: image/label mismatch')
        zdim = im.shape[2]
        xt = xp.with_name(xp.name + f'.part.{os.getpid()}')
        yt = yp.with_name(yp.name + f'.part.{os.getpid()}')
        x = np.lib.format.open_memmap(xt, mode='w+', dtype=np.int8,
                                      shape=(zdim, 3, 512, 512))
        y = np.lib.format.open_memmap(yt, mode='w+', dtype=np.uint8,
                                      shape=(zdim, 1, 512, 512))
        positive = []
        previous = current = qint8(np.asarray(im.dataobj[:, :, 0], dtype=np.float32))
        log(f'CONVERT {case} slices={zdim}')
        for z in range(zdim):
            following = (qint8(np.asarray(im.dataobj[:, :, z + 1], dtype=np.float32))
                         if z + 1 < zdim else current)
            x[z, 0], x[z, 1], x[z, 2] = previous, current, following
            mask = np.asarray(la.dataobj[:, :, z])
            if not np.all((mask == 0) | (mask == 1)):
                raise ValueError(f'{case}: nonbinary mask at z={z}')
            y[z, 0] = mask
            if np.any(mask):
                positive.append(z)
            previous, current = current, following
            if (z + 1) % 64 == 0 or z + 1 == zdim:
                x.flush()
                y.flush()
                log(f'PROGRESS {case} {z + 1}/{zdim}')
        x_bytes, y_bytes = x.nbytes, y.nbytes
        del x, y
        for path in (xt, yt):
            with path.open('rb') as f:
                os.fsync(f.fileno())
        row = {
            'case': case, 'shape': list(im.shape), 'centers': list(range(zdim)),
            'positive_slices': positive,
            'negative_slices': sorted(set(range(zdim)) - set(positive)),
            'spacing_xyz_mm': [float(v) for v in im.header.get_zooms()[:3]],
            'affine': im.affine.tolist(), 'image_sha256': sha(image),
            'label_sha256': sha(label), 'x_bytes': int(x_bytes), 'y_bytes': int(y_bytes),
            'preprocessor': 'prepare_task06_cache_stream_v4',
            'elapsed_seconds': round(time.monotonic() - started, 3),
        }
        xt.rename(xp)
        yt.rename(yp)
        check_cached(out, row)
        meta_path = out / 'metadata.json'
        spec = json.loads(meta_path.read_text(encoding='utf-8'))
        if case in {r['case'] for r in spec['cases']}:
            raise ValueError(f'{case}: already registered')
        spec['cases'] = sorted(spec['cases'] + [row], key=lambda r: r['case'])
        spec['case_count'] = len(spec['cases'])
        spec['preprocessor_revision'] = 'stream_v4_single_unpack'
        atomic_json(meta_path, spec)
        log(f"DONE {case} cases={spec['case_count']} seconds={row['elapsed_seconds']}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--data-root', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--case')
    a = p.parse_args()
    if a.case:
        convert(a.data_root, a.out, a.case)
        return
    # Keep one writer even if a second screen/session is started accidentally.
    with (a.out / '.preprocess.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        spec = json.loads((a.out / 'metadata.json').read_text(encoding='utf-8'))
        if not spec['all_slices']:
            raise ValueError('existing cache must use all_slices=True')
        for row in spec['cases']:
            check_cached(a.out, row)
        done = {r['case'] for r in spec['cases']}
        images = sorted(f for f in (a.data_root / 'imagesTr').glob('*.nii.gz')
                        if not f.name.startswith('._'))
        for image in images:
            case = image.name[:-7]
            if case in done:
                continue
            log(f'START {case} done={len(done)}/{len(images)}')
            r = subprocess.run([sys.executable, '-u', __file__, '--data-root',
                                str(a.data_root), '--out', str(a.out), '--case', case])
            if r.returncode != 0:
                raise RuntimeError(f'{case}: child exit {r.returncode}; retained incomplete files')
            done.add(case)
        log(f'COMPLETE {len(done)}/{len(images)}')


if __name__ == '__main__':
    main()
