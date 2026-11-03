#!/usr/bin/env python3
"""Read compact_v1 caches without changing their signed INT8 input values."""
import json
import operator
import tempfile
from pathlib import Path

import numpy as np


class CompactCase:
    def __init__(self, directory):
        directory = Path(directory)
        self.metadata = json.loads((directory / 'case.json').read_text(encoding='utf-8'))
        self.task = self.metadata['task']
        if self.task not in ('hipas', 'atm22', 'totalsegmentator'):
            raise ValueError(f'Unsupported task: {self.task}')
        self.target_names = self.metadata['target_names']
        h, w, self.zdim = self.metadata['shape_h_w_z']
        k = len(self.target_names)
        if min(h, w, self.zdim, k) < 1 or max(h, w) > 512:
            raise ValueError('Invalid native dimensions or target count')
        if self.task == 'hipas' and self.target_names != ['artery', 'vein']:
            raise ValueError('HiPaS target order must be artery, vein')
        if self.metadata['input_shape'] != [self.zdim, 3, 512, 512]:
            raise ValueError('Invalid frozen input shape')
        padding = self.metadata['padding']
        expected = {'h': [(512 - h) // 2, (513 - h) // 2],
                    'w': [(512 - w) // 2, (513 - w) // 2]}
        if padding != expected:
            raise ValueError('Padding must center the native plane at 512 x 512')
        self.h, self.w = h, w
        self.region = (slice(padding['h'][0], padding['h'][0] + h),
                       slice(padding['w'][0], padding['w'][0] + w))
        self.q = np.load(directory / 'q.npy', mmap_mode='r', allow_pickle=False)
        if (self.q.dtype != np.int8 or self.q.shape != (self.zdim, h, w)
                or not self.q.flags.c_contiguous):
            raise ValueError('q.npy must be signed INT8, C-order [Z,H,W]')
        with np.load(directory / 'labels.npz', allow_pickle=False) as labels:
            shape = labels['label_shape']
            self.bits = labels['bits']
        if shape.dtype != np.int64 or shape.tolist() != [k, self.zdim, h, w]:
            raise ValueError('Invalid label_shape')
        if self.bits.dtype != np.uint8 or self.bits.shape != (k, self.zdim, h, (w + 7) // 8):
            raise ValueError('Invalid packed label shape or dtype')

    def read_sample(self, z, float32=True):
        """Return x [3,512,512], y [K,512,512], valid [1,512,512]."""
        z = operator.index(z)
        if not 0 <= z < self.zdim:
            raise IndexError(f'Center slice {z} outside [0,{self.zdim})')
        x = np.full((3, 512, 512), -128, dtype=np.int8)
        x[(slice(None),) + self.region] = self.q[[max(0, z - 1), z, min(self.zdim - 1, z + 1)]]
        center = np.unpackbits(self.bits[:, z], axis=-1, count=self.w, bitorder='little')
        y = np.zeros((len(self.target_names), 512, 512), dtype=np.uint8)
        y[(slice(None),) + self.region] = center
        valid = np.zeros((1, 512, 512), dtype=np.uint8)
        source_valid = np.ones((self.h, self.w), dtype=np.uint8)
        if self.task in ('hipas', 'totalsegmentator'):
            source_valid = (center.sum(axis=0) < 2).astype(np.uint8)
        valid[(0,) + self.region] = source_valid
        return x.astype(np.float32) if float32 else x, y, valid

def open_case(directory):
    return CompactCase(directory)


def selfcheck():
    with tempfile.TemporaryDirectory(prefix='compact_reader_') as td:
        directory = Path(td)
        q = np.array([[[-128, 0, 127], [11, 12, 13]],
                      [[-127, 1, 126], [21, 22, 23]],
                      [[-126, 2, 125], [31, 32, 33]]], dtype=np.int8)
        label = np.zeros((2, 3, 2, 3), dtype=np.uint8)
        label[0, 0, 0, 0] = 1
        label[:, 1, 1, 2] = 1
        label[1, 2, 0, 2] = 1
        np.save(directory / 'q.npy', q)
        np.savez_compressed(directory / 'labels.npz',
                            bits=np.packbits(label, axis=-1, bitorder='little'),
                            label_shape=np.array(label.shape, dtype=np.int64))
        metadata = {'task': 'hipas', 'target_names': ['artery', 'vein'],
                    'shape_h_w_z': [2, 3, 3], 'input_shape': [3, 3, 512, 512],
                    'padding': {'h': [255, 255], 'w': [254, 255]}}
        (directory / 'case.json').write_text(json.dumps(metadata), encoding='utf-8')
        case = open_case(directory)
        for z, channels in ((0, [0, 0, 1]), (1, [0, 1, 2]), (2, [1, 2, 2])):
            x, y, valid = case.read_sample(z)
            assert x.dtype == np.float32 and y.dtype == valid.dtype == np.uint8
            assert x.shape == (3, 512, 512) and y.shape == (2, 512, 512)
            assert valid.shape == (1, 512, 512)
            assert np.array_equal(x[:, 255:257, 254:257], q[channels].astype(np.float32))
            assert np.array_equal(y[:, 255:257, 254:257], label[:, z])
            assert np.all(x[:, :255] == -128) and np.all(x[:, :, :254] == -128)
            assert np.all(x[:, 257:] == -128) and np.all(x[:, :, 257:] == -128)
            assert valid.sum() == 6 - (z == 1)
            assert y.sum() == label[:, z].sum()
        assert case.read_sample(1)[2][0, 256, 256] == 0
        assert case.read_sample(1)[1][:, 256, 256].tolist() == [1, 1]
        assert case.read_sample(0, float32=False)[0].dtype == np.int8
        del case
        metadata.update(task='atm22', target_names=['bronchus'])
        np.savez_compressed(directory / 'labels.npz',
                            bits=np.packbits(label[:1], axis=-1, bitorder='little'),
                            label_shape=np.array(label[:1].shape, dtype=np.int64))
        (directory / 'case.json').write_text(json.dumps(metadata), encoding='utf-8')
        assert open_case(directory).read_sample(1)[2].sum() == 6
        total_label = np.concatenate([label, np.zeros((3, 3, 2, 3), dtype=np.uint8)])
        total_label[2, 1, 1, 2] = 1
        metadata.update(task='totalsegmentator', target_names=['a', 'b', 'c', 'd', 'e'])
        np.savez_compressed(directory / 'labels.npz',
                            bits=np.packbits(total_label, axis=-1, bitorder='little'),
                            label_shape=np.array(total_label.shape, dtype=np.int64))
        (directory / 'case.json').write_text(json.dumps(metadata), encoding='utf-8')
        _, y, valid = open_case(directory).read_sample(1)
        assert y[:, 256, 256].sum() == 3 and valid[0, 256, 256] == 0
        assert valid.sum() == 5
    print('COMPACT_READER_SELFCHECK_PASS')


if __name__ == '__main__':
    selfcheck()
