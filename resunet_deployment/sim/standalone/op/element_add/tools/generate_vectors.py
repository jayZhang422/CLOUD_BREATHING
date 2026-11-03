"""离线数学 Golden：Python 任意精度整数 + Fraction 最近偶数舍入。

冻结测试同时核对已有 Golden 的 SHA256 和逐元素结果，不复用 RTL 流水算法。
"""
import argparse
import csv
import hashlib
import itertools
import json
from fractions import Fraction
from pathlib import Path

import numpy as np

P = 16
MULT_BITS = 22


def pack(values, bits):
    return sum((int(v) & ((1 << bits) - 1)) << (bits * i) for i, v in enumerate(values))


def golden(a, b, ma, mb, bias, shift, lower, upper):
    return [max(lower, min(upper, round(Fraction(int(x) * int(m) + int(y) * int(n) + int(z), 1 << shift))))
            for x, y, m, n, z in zip(a, b, ma, mb, bias)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=Path(__file__).resolve().parent.parent / 'verification/deployment')
    parser.add_argument('--exports', type=Path, default=Path(__file__).resolve().parents[5] /
                        'src/params/int8')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    provenance = []
    count = 0
    with (args.out / 'cases.csv').open('w', newline='') as f:
        manifest = csv.writer(f)
        manifest.writerow(['case', 'groups', 'words', 'mode'])

        def write_case(name, groups, mode):
            nonlocal count
            directory = args.out / name
            directory.mkdir(exist_ok=True)
            total = 0
            with (directory / 'config.csv').open('w', newline='') as cf, \
                    (directory / 'stimulus.hex').open('w') as sf, (directory / 'golden.hex').open('w') as gf:
                configs = csv.writer(cf)
                configs.writerow(['words', 'group', 'last_group', 'shift', 'lower', 'upper', 'ma', 'mb', 'bias'])
                for words, tag, last, ma, mb, bias, shift, lower, upper, rows in groups:
                    assert all(-(1 << (MULT_BITS - 1)) <= int(v) < 1 << (MULT_BITS - 1) for v in [*ma, *mb])
                    assert all(-(1 << 63) <= int(v) < 1 << 63 for v in bias)
                    configs.writerow([words, tag, int(last), shift, lower, upper,
                                      f'{pack(ma, MULT_BITS):088x}', f'{pack(mb, MULT_BITS):088x}', f'{pack(bias, 64):0256x}'])
                    actual = 0
                    for a, b, expected in rows:
                        assert all(-(1 << 31) <= int(v) < 1 << 31 for v in [*a, *b])
                        answer = golden(a, b, ma, mb, bias, shift, lower, upper)
                        if expected is not None:
                            assert answer == list(expected), (name, tag, actual, answer, list(expected))
                        sf.write(f'{pack(a, 32) | (pack(b, 32) << 512):0256x}\n')
                        gf.write(f'{pack(answer, 8):032x}\n')
                        actual += 1
                    assert actual == words
                    total += words
            manifest.writerow([name, len(groups), total, mode])
            count += 1

        # 三套冻结包全部 42 个 mix/out 节点，按组读取真实 INT32 MAC 和既有 INT8 Golden。
        for task in ('lobe', 'vessel', 'airway'):
            export = args.exports / task
            contract_path = export / 'contract.json'
            contract = json.loads(contract_path.read_text())
            capture = export / 'golden_synthetic_32x32'
            tensors = json.loads((capture / 'manifest.json').read_text())['tensors']

            def tensor(name):
                info = tensors[name]
                path = capture / (name + '.bin')
                assert hashlib.sha256(path.read_bytes()).hexdigest() == info['sha256'], path
                dtype = {'int32': '<i4', 'int8': 'i1'}[info['dtype']]
                return np.fromfile(path, dtype=dtype).reshape(info['shape'])[0]

            for name, cfg in contract['merges'].items():
                if not name.endswith(('.mix', '.out')):
                    continue
                assert len(cfg['multipliers']) == 2 and cfg['bits'] == 8
                base, suffix = name.split('.')
                a = tensor(base + ('.dw3.mac' if suffix == 'mix' else '.project.mac'))
                b = tensor(base + ('.dw5.mac' if suffix == 'mix' else '.skip.mac'))
                expected = tensor(name)
                channels, height, width = expected.shape
                bias_path = export / cfg['bias_file']
                bias = np.fromfile(bias_path, dtype='<i8')
                assert channels % P == 0 and len(bias) == channels
                lower = 0 if cfg['relu6'] else -128
                upper = min(127, round(6 / cfg['output_scale'])) if cfg['relu6'] else 127
                groups = []
                for group in range(channels // P):
                    sl = slice(group * P, (group + 1) * P)
                    rows = zip(a[sl].reshape(P, -1).T, b[sl].reshape(P, -1).T, expected[sl].reshape(P, -1).T)
                    groups.append((height * width, group, group == channels // P - 1,
                                   cfg['multipliers'][0][sl], cfg['multipliers'][1][sl], bias[sl],
                                   cfg['shift'], lower, upper, rows))
                write_case(f'{task}_{name}', groups, 'random')
                provenance.append({'case': f'{task}_{name}', 'contract': str(contract_path),
                                   'contract_sha256': hashlib.sha256(contract_path.read_bytes()).hexdigest(),
                                   'bias_sha256': hashlib.sha256(bias_path.read_bytes()).hexdigest(),
                                   'a_sha256': tensors[base + ('.dw3.mac' if suffix == 'mix' else '.project.mac')]['sha256'],
                                   'b_sha256': tensors[base + ('.dw5.mac' if suffix == 'mix' else '.skip.mac')]['sha256'],
                                   'golden_sha256': tensors[name]['sha256']})

        ones, zeros = [1] * P, [0] * P
        # 所有 shift 0..63，正负半值、最近偶数、INT8 饱和及更低 ReLU6 上限。
        for shift in range(64):
            unit = 1 << shift
            deltas = (0, unit // 2 - 1, unit // 2, unit // 2 + 1, unit - 1) if shift else (-1, 0, 1)
            targets = [n * unit + d for n in (-130, -129, -128, -127, -3, -2, -1, 0, 1, 2, 3, 126, 127, 128, 129, 130)
                       for d in deltas if -(1 << 63) <= n * unit + d < 1 << 63]
            targets += [-(1 << 63), (1 << 63) - 1]
            targets += [0] * ((-len(targets)) % P)
            groups = []
            for group in range(len(targets) // P):
                bias = targets[group * P:(group + 1) * P]
                rows = (([offset] * P, zeros, None) for offset in (-1, 0, 1))
                groups.append((3, group, group == len(targets) // P - 1, ones, ones, bias, shift,
                               -128, 127, rows))
            write_case(f'rne_shift{shift}', groups, 'continuous')

        # 同尺度 INT8 加法全穷举只是兼容子集，不替代冻结契约测试。
        pairs = list(itertools.product(range(-128, 128), repeat=2))
        rows = (([p[0] for p in pairs[i:i + P]], [p[1] for p in pairs[i:i + P]], None)
                for i in range(0, len(pairs), P))
        write_case('int8_exhaustive', [(4096, 0, True, ones, ones, zeros, 0, -128, 127, rows)], 'continuous')

        rng = np.random.default_rng(20261011)
        ma = [int(v) for v in rng.integers(-(1 << 21), 1 << 21, P)]
        mb = [-v for v in ma]
        # 极端带符号乘数、INT32_MIN/MAX、INT64 偏置；验证超出 INT64 的中间值仍精确限幅。
        ma[:4] = [-(1 << 21), (1 << 21) - 1, 1, 1]
        mb[:4] = [(1 << 21) - 1, -(1 << 21), 1, 1]
        bias = [-(1 << 63) if i % 2 else (1 << 63) - 1 for i in range(P)]
        a = rng.integers(-(1 << 31), 1 << 31, (1024, P), dtype=np.int64)
        b = rng.integers(-(1 << 31), 1 << 31, (1024, P), dtype=np.int64)
        a[:4] = np.array([-(1 << 31), (1 << 31) - 1, -(1 << 31), (1 << 31) - 1])[:, None]
        b[:4] = np.array([(1 << 31) - 1, -(1 << 31), -(1 << 31), (1 << 31) - 1])[:, None]
        write_case('wide_extremes', [(1024, 11, False, ma, mb, bias, 24, -128, 127, zip(a, b, itertools.repeat(None)))], 'random')

        # 每路若先舍入会得到 0+0，统一舍入应得到 1；先饱和会破坏大数抵消。
        patterns = [([1] * P, [2] * P, None), ([20000] * P, [-19997] * P, None),
                    ([-1] * P, [-2] * P, None), ([3] * P, [3] * P, None)]
        write_case('relu6_limit', [(128, 0, True, ones, ones, zeros, 0, 0, 63,
                                  (([i - 64] * P, [32] * P, None) for i in range(128)))], 'random')
        for name, mode in (('single_round', 'random'), ('reset_mid', 'reset_mid'), ('reset_stalled', 'reset_stalled')):
            write_case(name, [(512, 0, True, ones, ones, zeros, 2, -128, 127,
                               itertools.islice(itertools.cycle(patterns), 512))], mode)

        # 最大配置字数与最后组号；数据周期变化，检查计数器边界与连续吞吐。
        write_case('full512', [(262144, 11, True, ones, ones, zeros, 2, -128, 127,
                               itertools.islice(itertools.cycle(patterns), 262144))], 'continuous')
        write_case('minimum_after_full', [(1, 0, True, ones, ones, zeros, 0, -128, 127,
                                          [(ones, zeros, None)])], 'continuous')
        write_case('max_groups_32', [(1, group, group == 31, ones, zeros, zeros, 0, -128, 127,
                                      [(ones, zeros, None)]) for group in range(32)], 'continuous')
    (args.out / 'provenance.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    print(f'Generated {count} cases; 42 frozen nodes verified against exported Golden; Fraction RNE oracle')


if __name__ == '__main__':
    main()
