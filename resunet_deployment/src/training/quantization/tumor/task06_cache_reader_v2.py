#!/usr/bin/env python3
"""Read the verified Task06 expanded cache without changing INT8 values."""
import argparse
import json
import operator
from pathlib import Path

import numpy as np


class Task06Case:
    def __init__(self, cache_root, metadata_row):
        self.metadata = metadata_row
        self.case = metadata_row['case']
        shape = metadata_row['shape']
        if len(shape) != 3 or shape[:2] != [512, 512] or shape[2] < 1:
            raise ValueError(f'{self.case}: invalid native shape')
        self.zdim = shape[2]
        centers = list(range(self.zdim))
        if metadata_row['centers'] != centers:
            raise ValueError(f'{self.case}: cache must contain every center slice')
        self.positive_slices = list(metadata_row['positive_slices'])
        self.negative_slices = list(metadata_row['negative_slices'])
        if (self.positive_slices != sorted(set(self.positive_slices))
                or self.negative_slices != sorted(set(self.negative_slices))
                or set(self.positive_slices) & set(self.negative_slices)
                or sorted(self.positive_slices + self.negative_slices) != centers):
            raise ValueError(f'{self.case}: invalid positive/negative slice partition')
        samples = Path(cache_root) / 'samples'
        arrays = {}
        for suffix, dtype, channels in (('x', np.int8, 3), ('y', np.uint8, 1)):
            path = samples / f'{self.case}_{suffix}.npy'
            arr = np.load(path, mmap_mode='r', allow_pickle=False)
            if (arr.dtype != dtype or arr.shape != (self.zdim, channels, 512, 512)
                    or not arr.flags.c_contiguous):
                raise ValueError(f'{path}: invalid dtype, shape or layout')
            if (arr.nbytes != metadata_row[f'{suffix}_bytes']
                    or path.stat().st_size != arr.offset + arr.nbytes):
                raise ValueError(f'{path}: payload or file size differs from metadata')
            arrays[suffix] = arr
        self.x, self.y = arrays['x'], arrays['y']

    def read_sample(self, z):
        """Return direct-cast float32 x [3,512,512], uint8 y [1,512,512]."""
        z = operator.index(z)
        if not 0 <= z < self.zdim:
            raise IndexError(f'{self.case}: center {z} outside [0,{self.zdim})')
        return self.x[z].astype(np.float32), np.asarray(self.y[z])

    def read_batch(self, indices):
        """Return float32 x [B,3,512,512], y [B,1,512,512]."""
        indices = [operator.index(z) for z in indices]
        if not indices or min(indices) < 0 or max(indices) >= self.zdim:
            raise IndexError(f'{self.case}: batch centers must be nonempty and in range')
        return (self.x[indices].astype(np.float32),
                self.y[indices].astype(np.float32))

    def check_representative(self):
        """Check first/last and representative positive/negative samples only."""
        selected = {0, self.zdim - 1}
        for group in (self.positive_slices, self.negative_slices):
            if group:
                selected.add(group[len(group) // 2])
        positive = set(self.positive_slices)
        for z in sorted(selected):
            x, y = self.read_sample(z)
            if x.dtype != np.float32 or y.dtype != np.uint8:
                raise ValueError(f'{self.case}: incorrect reader output dtype')
            if not np.array_equal(x, self.x[z].astype(np.float32)):
                raise ValueError(f'{self.case}: reader changed cached INT8 input values')
            for channel, center in enumerate((max(0, z - 1), z,
                                               min(self.zdim - 1, z + 1))):
                if not np.array_equal(self.x[z, channel], self.x[center, 1]):
                    raise ValueError(f'{self.case}: channel/boundary mismatch at z={z}')
            if not np.all((y == 0) | (y == 1)) or bool(np.any(y)) != (z in positive):
                raise ValueError(f'{self.case}: label/metadata mismatch at z={z}')
        xb, yb = self.read_batch(sorted(selected))
        if (xb.dtype != np.float32 or yb.dtype != np.float32
                or not np.array_equal(xb, self.x[sorted(selected)].astype(np.float32))
                or not np.array_equal(yb, self.y[sorted(selected)].astype(np.float32))):
            raise ValueError(f'{self.case}: batch reader changed cached values')
        return {'case': self.case, 'status': 'PASS', 'checked_centers': sorted(selected),
                'input_dtype': 'float32', 'stored_dtype': 'int8',
                'sample_shape': list(xb.shape[1:])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('cache_root', type=Path)
    parser.add_argument('--case')
    args = parser.parse_args()
    metadata = json.loads((args.cache_root / 'metadata.json').read_text(encoding='utf-8'))
    row = next(row for row in metadata['cases']
               if args.case is None or row['case'] == args.case)
    print(json.dumps(Task06Case(args.cache_root, row).check_representative()))


if __name__ == '__main__':
    main()
