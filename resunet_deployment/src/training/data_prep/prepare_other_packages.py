#!/usr/bin/env python3
"""Compact, resumable preprocessing without rewriting any original data."""
import argparse
import csv
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
import zipfile
from pathlib import Path

# Keep shared readers importable when this standalone script is run from any working directory.
SHARED_DIR = Path(__file__).resolve().parents[2] / "shared"
if str(SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(SHARED_DIR))

import nibabel as nib
import numpy as np

from compact_cache_reader import open_case

LOBES = ['lung_upper_lobe_left', 'lung_lower_lobe_left',
         'lung_upper_lobe_right', 'lung_middle_lobe_right', 'lung_lower_lobe_right']
CONTRACT = {'dtype': 'signed int8', 'shape': '[Z,3,512,512]',
            'channels': '[z-1,z,z+1]', 'boundary': 'repeat edge',
            'hu_clip': [-1024, 1000], 'round': 'NumPy rint nearest-even',
            'training_cast': 'direct float32', 'target': 'center slice',
            'storage': 'q.npy native [Z,H,W]; lossless packed binary labels',
            'padding': 'center native plane to 512; q=-128, supervision valid=0 in padding',
            'orientation': 'preserve source array axes and affine; no resampling/reorientation'}


def log(s):
    print(time.strftime('%F %T ') + s, flush=True)


def sha(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
        os.posix_fadvise(f.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
    return h.hexdigest()


def write_json(path, data):
    tmp = path.with_name(path.name + '.tmp')
    with tmp.open('w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    tmp.replace(path)


def qint8(x):
    x = np.asarray(x, dtype=np.float32)
    if not np.all(np.isfinite(x)):
        raise ValueError('nonfinite CT values')
    return (np.rint((np.clip(x, -1024, 1000).astype(np.float64) + 1024.0)
                    * 255.0 / 2024.0).astype(np.int16) - 128).astype(np.int8)


def cases_for(root, task, index):
    cases, unavailable = [], []
    if task == 'hipas':
        for row in index['cases']:
            c = row['case']
            cases.append({'case': c, 'task': task,
                          'image': str(root / 'HiPaS' / 'ct_scan' / f'{c}.npz'),
                          'labels': [str(root / 'HiPaS' / 'annotation' / n / f'{c}.npz')
                                     for n in ['artery', 'vein']],
                          'target_names': ['artery', 'vein'], 'previous_audit': row})
    elif task == 'atm22':
        for batch in sorted((root / 'ATM22').glob('TrainBatch*')):
            images = {p.name: p for p in (batch / 'imagesTr').glob('*.nii.gz')}
            labels = {p.name: p for p in (batch / 'labelsTr').glob('*.nii.gz')}
            for name in sorted(set(labels) - set(images)):
                unavailable.append({'case': name[:-12], 'batch': batch.name,
                                    'reason': 'label exists but CT is missing',
                                    'label': str(labels[name])})
            for name, p in sorted(images.items()):
                if name not in labels:
                    unavailable.append({'case': name[:-12], 'reason': 'missing label'})
                    continue
                cases.append({'case': name[:-12], 'task': task, 'batch': batch.name,
                              'image': str(p), 'labels': [str(labels[name])],
                              'target_names': ['airway']})
    else:
        ts = root / 'TotalSegmentator' / 'Totalsegmentator_dataset'
        with (ts / 'meta.csv').open(encoding='utf-8-sig', newline='') as f:
            info = {r['image_id']: r for r in csv.DictReader(f, delimiter=';')}
        for p in sorted(ts.glob('s*/ct.nii.gz')):
            labels = [p.parent / 'segmentations' / f'{l}.nii.gz' for l in LOBES]
            if not all(q.exists() for q in labels):
                unavailable.append({'case': p.parent.name, 'reason': 'missing lobe label',
                                    'missing': [str(q) for q in labels if not q.exists()]})
                continue
            cases.append({'case': p.parent.name, 'task': task, 'image': str(p),
                          'labels': [str(q) for q in labels], 'target_names': LOBES,
                          'official_metadata': info.get(p.parent.name, {})})
    return sorted(cases, key=lambda c: c['case']), unavailable


def unpack(source, dest):
    if source.suffix == '.npz':
        with zipfile.ZipFile(source) as z:
            if z.namelist() != ['data.npy']:
                raise ValueError(f'{source}: unexpected NPZ members')
            with z.open('data.npy') as incoming, dest.open('wb') as outgoing:
                shutil.copyfileobj(incoming, outgoing, length=1 << 20)
        return np.load(dest, mmap_mode='r', allow_pickle=False), None
    with gzip.open(source, 'rb') as incoming, dest.open('wb') as outgoing:
        shutil.copyfileobj(incoming, outgoing, length=1 << 20)
    im = nib.load(str(dest), mmap='r')
    return im.dataobj, im


def prepare_case(entry, out):
    case, task = entry['case'], entry['task']
    started = time.monotonic()
    dst = out / 'cases' / case
    if dst.exists():
        raise FileExistsError(dst)
    # One directory rename commits q, labels and case.json together.
    with tempfile.TemporaryDirectory(prefix=f'.case_{case}_', dir=out) as work:
        work = Path(work)
        stage = work / 'ready'
        stage.mkdir()
        source = Path(entry['image'])
        native = work / ('image.npy' if source.suffix == '.npz' else 'image.nii')
        log(f'UNPACK {task}/{case}')
        data, im = unpack(source, native)
        h, w, z = data.shape
        if h > 512 or w > 512 or min(h, w, z) < 1:
            raise ValueError(f'{case}: unsupported native shape {data.shape}')
        if task in ('hipas', 'atm22') and (h, w) != (512, 512):
            raise ValueError(f'{case}: expected 512 in-plane')
        affine = im.affine.tolist() if im is not None else None
        spacing = list(im.header.get_zooms()[:3]) if im is not None else None
        q = np.lib.format.open_memmap(stage / 'q.npy', mode='w+', dtype=np.int8,
                                      shape=(z, h, w))
        below, above = 0, 0
        ct_min, ct_max = float('inf'), float('-inf')
        for i in range(z):
            plane = np.asarray(data[:, :, i], dtype=np.float32)
            below += int(np.count_nonzero(plane < -1024))
            above += int(np.count_nonzero(plane > 1000))
            ct_min, ct_max = min(ct_min, float(plane.min())), max(ct_max, float(plane.max()))
            q[i] = qint8(plane)
        q.flush()
        selected = sorted({0, z - 1, z // 2, z // 3, 2 * z // 3})
        # Reopen written output and compare source CT representative planes.
        reopened = np.load(stage / 'q.npy', mmap_mode='r')
        for i in selected:
            if not np.array_equal(reopened[i], qint8(data[:, :, i])):
                raise ValueError(f'{case}: persisted q mismatch z={i}')
        del reopened, q, data, im
        with native.open('rb') as f:
            os.posix_fadvise(f.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
        native.unlink()
        k = len(entry['labels'])
        bits = np.zeros((k, z, h, (w + 7) // 8), dtype=np.uint8)
        counts, positive, bounds, hashes = [], [], [], []
        for j, filename in enumerate(entry['labels']):
            source_label = Path(filename)
            raw = work / ('mask.npy' if source_label.suffix == '.npz' else 'mask.nii')
            data, la = unpack(source_label, raw)
            if data.shape != (h, w, z):
                raise ValueError(f'{case}: mask shape mismatch')
            if la is not None and not np.allclose(la.affine, affine, rtol=0, atol=1e-3):
                raise ValueError(f'{case}: mask affine mismatch beyond 1e-3 mm')
            count, pos = 0, []
            boundary = {'h0': 0, 'h1': 0, 'w0': 0, 'w1': 0, 'z0': 0, 'z1': 0}
            for i in range(z):
                mask = np.asarray(data[:, :, i])
                if not np.all((mask == 0) | (mask == 1)):
                    raise ValueError(f'{case}: nonbinary {entry["target_names"][j]} z={i}')
                mask = mask.astype(np.uint8)
                bits[j, i] = np.packbits(mask, axis=-1, bitorder='little')
                if not np.array_equal(np.unpackbits(bits[j, i], axis=-1, count=w,
                                                   bitorder='little'), mask):
                    raise ValueError('packed labels failed exact roundtrip')
                n = int(mask.sum())
                count += n
                if n:
                    pos.append(i)
                for key, arr in [('h0', mask[0]), ('h1', mask[-1]),
                                 ('w0', mask[:, 0]), ('w1', mask[:, -1])]:
                    boundary[key] += int(arr.sum())
                if i == 0:
                    boundary['z0'] = n
                if i == z - 1:
                    boundary['z1'] = n
            counts.append(count)
            positive.append(pos)
            bounds.append(boundary)
            hashes.append(sha(source_label))
            del data, la
            with raw.open('rb') as f:
                os.posix_fadvise(f.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)
            raw.unlink()
        overlaps = 0
        for start in range(0, z, 16):
            masks = np.unpackbits(bits[:, start:start + 16], axis=-1,
                                  count=w, bitorder='little')
            overlaps += int(np.count_nonzero(masks.sum(axis=0) >= 2))
        np.savez_compressed(stage / 'labels.npz', bits=bits,
                            label_shape=np.array([k, z, h, w], dtype=np.int64))
        with np.load(stage / 'labels.npz') as saved:
            if not np.array_equal(saved['bits'], bits):
                raise ValueError('persisted labels mismatch')
        del bits
        pad = {'h': [(512 - h) // 2, (513 - h) // 2],
               'w': [(512 - w) // 2, (513 - w) // 2]}
        info = {**entry, 'cache_version': 'other_compact_v1', 'shape_h_w_z': [h, w, z],
                'input_shape': [z, 3, 512, 512], 'padding': pad,
                'affine': affine, 'spacing_xyz_mm': [float(v) for v in spacing] if spacing else None,
                'input_contract': CONTRACT, 'source_image_sha256': sha(source),
                'source_label_sha256': hashes, 'label_voxels': counts,
                'positive_slices_per_target': positive, 'label_boundary_voxels': bounds,
                'overlap_voxels': overlaps, 'source_ct_range': [ct_min, ct_max],
                'clip_voxels_below': below, 'clip_voxels_above': above,
                'supervised_targets_only': entry['target_names'],
                'verification': {'passed': True, 'ct_centers_checked': selected,
                                 'all_source_masks_exact_packed_roundtrip': True}}
        if task == 'hipas':
            old = info.pop('previous_audit')
            info.update(eligibility=old['eligibility'], quarantine_reason=old['quarantine_reason'],
                        spacing_z_y_x_mm=old['spacing_z_y_x_mm'],
                        intensity_rule='source values as provided; no guessed rescale; original eligibility retained',
                        overlap_rule='preserve A/V masks; ignore A&V in loss and metrics')
            if old['shape_h_w_z'] != [h, w, z] or old['overlap_voxels'] != overlaps:
                raise ValueError(f'{case}: changed relative to existing HiPaS audit')
        elif task == 'totalsegmentator':
            # Coverage is not a diagnosis; preserve flags for later full-case evaluation selection.
            info['lung_coverage'] = {
                'all_five_lobes_nonempty': all(c > 0 for c in counts),
                'target_touches_z_edge': any(b['z0'] or b['z1'] for b in bounds),
                'complete_lung_candidate': all(c > 0 for c in counts)
                                           and not any(b['z0'] or b['z1'] for b in bounds),
                'requires_visual_review_before_complete_lung_evaluation': True}
            info['overlap_rule'] = 'preserve all five masks; ignore multi-lobe overlap for lobe metrics/loss'
        write_json(stage / 'case.json', info)
        reader = open_case(stage)
        for i in selected:
            x, y, valid = reader.read_sample(i)
            if x.dtype != np.float32 or x.shape != (3, 512, 512) or y.shape != (k, 512, 512):
                raise ValueError('cache reader shape/dtype failure')
            if i == 0 and not np.array_equal(x[0], x[1]):
                raise ValueError('first boundary failure')
            if i == z - 1 and not np.array_equal(x[1], x[2]):
                raise ValueError('last boundary failure')
        del reader
        info['cache_sha256'] = {'q.npy': sha(stage / 'q.npy'),
                                'labels.npz': sha(stage / 'labels.npz')}
        info['seconds'] = round(time.monotonic() - started, 3)
        info['bytes'] = sum(p.stat().st_size for p in stage.iterdir())
        write_json(stage / 'case.json', info)
        for p in stage.iterdir():
            with p.open('rb') as f:
                os.fsync(f.fileno())
        stage.rename(dst)
        log(f'DONE {task}/{case} slices={z} seconds={info["seconds"]} bytes={info["bytes"]}')


def run(args):
    out = args.out
    out.mkdir(parents=True, exist_ok=True)
    with (out / '.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        index = json.loads(args.hipas_index.read_text())
        tasks = [args.task] if args.task != 'all' else ['hipas', 'atm22', 'totalsegmentator']
        inventory = {t: cases_for(args.data_root, t, index) for t in tasks}
        write_json(out / 'plan.json', {'version': 'other_compact_v1', 'input_contract': CONTRACT,
                   'packages': {t: {'cases': len(cs), 'unavailable': unavailable}
                                for t, (cs, unavailable) in inventory.items()}})
        for task, (entries, unavailable) in inventory.items():
            taskout = out / task
            (taskout / 'cases').mkdir(parents=True, exist_ok=True)
            log(f'PACKAGE {task} cases={len(entries)} unavailable={len(unavailable)}')
            # Preserve incomplete work from interrupted prior runs, never count it complete.
            for p in taskout.glob('.case_*'):
                backup = taskout / ('interrupted_' + p.name[1:] + '_' + str(time.time_ns()))
                p.rename(backup)
            results = []
            for n, entry in enumerate(entries, 1):
                dest = taskout / 'cases' / entry['case']
                if not dest.exists():
                    if shutil.disk_usage(out).free < 6 * 2**30:
                        raise RuntimeError('less than 6 GiB free; stop before consuming remaining disk')
                    log(f'START {task} {n}/{len(entries)} {entry["case"]}')
                    entry_file = taskout / 'current_entry.json'
                    write_json(entry_file, entry)
                    r = subprocess.run([sys.executable, '-u', __file__, '--out', str(taskout),
                                        '--task', task, '--entry', str(entry_file)])
                    if r.returncode:
                        raise RuntimeError(f'{task}/{entry["case"]} child exited {r.returncode}')
                data = json.loads((dest / 'case.json').read_text())
                if not data['verification']['passed']:
                    raise ValueError(f'{dest}: failed verification')
                results.append(data)
                # Persist aggregate metadata after each committed case.
                write_json(taskout / 'metadata.json', {
                    'version': 'other_compact_v1', 'task': task, 'case_count': len(results),
                    'expected_cases': len(entries), 'input_contract': CONTRACT,
                    'unavailable': unavailable, 'cases': results})
            write_json(taskout / 'verification.json', {
                'passed': len(results) == len(entries), 'verified_cases': len(results),
                'samples': sum(r['shape_h_w_z'][2] for r in results),
                'ct_check': '5 representative source planes per case, all pixels',
                'label_check': 'all source label voxels exact packed roundtrip and persisted bits equality',
                'reader_check': 'source region, shapes, dtype, repeated first/last channels',
                'sha256': 'every source and saved q/labels',
                'unavailable': unavailable})
            with (taskout / 'per_case.csv').open('w', newline='') as f:
                writer = csv.writer(f)
                writer.writerow(['case', 'slices', 'verified', 'seconds', 'bytes', 'overlap_voxels'])
                for r in results:
                    writer.writerow([r['case'], r['shape_h_w_z'][2], True,
                                     r['seconds'], r['bytes'], r['overlap_voxels']])
            log(f'PACKAGE_COMPLETE {task} {len(results)}/{len(entries)}')
        write_json(out / 'complete.json', {'passed': True, 'completed_at': time.strftime('%F %T'),
                   'packages': {t: len(cs) for t, (cs, _) in inventory.items()}})
        log('ALL_PACKAGES_COMPLETE')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--data-root', type=Path, default=Path('/root/autodl-tmp/datasets'))
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--task', choices=['hipas', 'atm22', 'totalsegmentator', 'all'], required=True)
    p.add_argument('--hipas-index', type=Path,
                   default=Path('/root/autodl-tmp/lung_training/hipas_av_v1/manifest/data_index.json'))
    p.add_argument('--entry', type=Path)
    a = p.parse_args()
    if a.entry:
        prepare_case(json.loads(a.entry.read_text()), a.out)
    else:
        run(a)


if __name__ == '__main__':
    main()
