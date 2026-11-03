#!/usr/bin/env python3
"""Read-only audit for a paired NIfTI task; writes no source-derived cache."""
import argparse, hashlib, json
from pathlib import Path
import nibabel as nib
import numpy as np

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()

def audit(image_dir, label_dir, task):
    images = sorted(p for p in Path(image_dir).glob('*.nii.gz') if not p.name.startswith('._'))
    labels = {p.name: p for p in Path(label_dir).glob('*.nii.gz') if not p.name.startswith('._')}
    rows = []
    for image in images:
        label = labels.get(image.name) or labels.get(image.name.replace('_0000', ''))
        if label is None:
            raise ValueError(f'missing label for {image.name}')
        im, la = nib.load(str(image)), nib.load(str(label))
        x, y = im.dataobj, la.dataobj
        if x.ndim != 3 or x.shape[:2] != (512, 512):
            raise ValueError(f'{image.name}: expected [512,512,Z], got {x.shape}')
        if x.shape != y.shape or not np.allclose(im.affine, la.affine):
            raise ValueError(f'{image.name}: image/label shape or affine mismatch')
        step = max(1, x.shape[2] // 32)
        x_sample = np.asarray(x[:, ::16, ::step])
        y_sample = np.asarray(y[:, ::16, ::step])
        finite = np.isfinite(x_sample)
        values, counts = np.unique(y_sample, return_counts=True)
        rows.append({'case': image.stem.replace('.nii',''), 'image': image.name, 'label': label.name,
                     'shape_h_w_z': list(x.shape), 'image_dtype': str(x.dtype),
                     'image_sample_min': float(np.min(x_sample[finite])), 'image_sample_max': float(np.max(x_sample[finite])),
                     'image_sample_q01_q10_q50_q90_q99': np.percentile(x_sample[finite], [1,10,50,90,99]).tolist(),
                     'label_values': values.astype(float).tolist(), 'label_counts': counts.astype(int).tolist(),
                     'spacing_xyz_mm': [float(v) for v in im.header.get_zooms()[:3]],
                     'affine_sha256': hashlib.sha256(np.asarray(im.affine, dtype=np.float64).tobytes()).hexdigest(),
                     'image_sha256': sha(image), 'label_sha256': sha(label)})
    return {'task': task, 'image_dir': str(image_dir), 'label_dir': str(label_dir),
            'case_count': len(rows), 'cases': rows}

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--image-dir', required=True); p.add_argument('--label-dir', required=True)
    p.add_argument('--task', required=True); p.add_argument('--output', required=True)
    a = p.parse_args(); result = audit(a.image_dir, a.label_dir, a.task)
    Path(a.output).write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'task': a.task, 'case_count': result['case_count'],
                      'first_case': result['cases'][0] if result['cases'] else None}, indent=2))

if __name__ == '__main__': main()
