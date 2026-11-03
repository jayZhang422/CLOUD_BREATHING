#!/usr/bin/env python3
"""定点 Golden 原语：舍入、饱和、再量化、lane 打包与 hex 导出。只依赖 numpy。

全部用 Python 整数 / int64 计算，保证与 RTL 逐位一致；不要在 Golden 里用浮点再取整。
导入用法：
    import sys; sys.path.insert(0, "<skill>/model-deploy/scripts")
    from fixedpoint import rne_shift, requant, pack_lanes, write_hex
命令行自测：python fixedpoint.py --selftest
"""
import sys

import numpy as np


def rne_shift(value, shift):
    """有符号整数右移 shift 位，round-half-to-even（就近取偶）。等价于 numpy.rint(value / 2**shift)。"""
    if shift == 0:
        return int(value)
    q, r = divmod(int(value), 1 << shift)          # Python divmod：r 始终 >= 0，负数也正确
    half = 1 << (shift - 1)
    return q + (r > half or (r == half and (q & 1)))


def round_half_away(value, shift):
    """round-half-away-from-zero，常见的「四舍五入」，与 RNE 只在恰好 .5 时不同。"""
    if shift == 0:
        return int(value)
    mag = (abs(int(value)) + (1 << (shift - 1))) >> shift
    return mag if value >= 0 else -mag


def floor_shift(value, shift):
    """算术右移（向负无穷截断），即 RTL 里的 >>>。"""
    return int(value) >> shift


def saturate(value, bits, signed=True):
    lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if signed else (0, (1 << bits) - 1)
    return max(lo, min(hi, int(value)))


def requant(acc, multiplier, shift, bias=0, bits=8, relu6_max=None, bound=1 << 62):
    """y = clamp(RNE((acc * multiplier + bias) / 2**shift))。超过 bound 直接报错，对应 RTL 的溢出检查。"""
    num = int(acc) * int(multiplier) + int(bias)
    if abs(num) >= bound:
        raise OverflowError(f"numerator {num} exceeds bound {bound}")
    y = rne_shift(num, shift)
    if relu6_max is not None:
        y = max(0, min(relu6_max, y))
    return saturate(y, bits)


def pack_lanes(values, bits):
    """lane 0 放在最低位。返回 Python int。"""
    mask = (1 << bits) - 1
    return sum((int(v) & mask) << (i * bits) for i, v in enumerate(values))


def unpack_lanes(word, bits, lanes, signed=True):
    mask = (1 << bits) - 1
    out = []
    for i in range(lanes):
        v = (int(word) >> (i * bits)) & mask
        if signed and v >> (bits - 1):
            v -= 1 << bits
        out.append(v)
    return out


def write_hex(path, words, width_bits):
    """每行一个字，固定宽度十六进制，供 $readmemh 读取。"""
    digits = (width_bits + 3) // 4
    mask = (1 << width_bits) - 1
    with open(path, "w", encoding="ascii") as f:
        for w in words:
            f.write(f"{int(w) & mask:0{digits}x}\n")


def selftest():
    # RNE 与 numpy.rint 一致（覆盖负数与恰好 .5）
    for v in range(-4096, 4097):
        for s in (1, 3, 8):
            assert rne_shift(v, s) == int(np.rint(v / (1 << s))), (v, s)
    assert rne_shift(5, 1) == 2 and rne_shift(7, 1) == 4 and rne_shift(-5, 1) == -2
    assert round_half_away(5, 1) == 3 and round_half_away(-5, 1) == -3
    assert floor_shift(-5, 1) == -3
    assert saturate(200, 8) == 127 and saturate(-200, 8) == -128 and saturate(300, 8, signed=False) == 255
    vals = [-1, 2, -128, 127]
    assert unpack_lanes(pack_lanes(vals, 8), 8, 4) == vals
    assert pack_lanes([1, 2], 8) == 0x0201                # lane 0 在低位
    assert requant(1000, 3, 4) == 127                     # RNE(3000/16)=188 → 饱和到 127
    assert requant(-1000, 3, 4, relu6_max=96) == 0        # ReLU6 下限
    assert requant(40, 3, 4) == 8                         # 120/16=7.5 → 取偶 8
    try:
        requant(1 << 40, 1 << 30, 4)
        raise AssertionError("bound not enforced")
    except OverflowError:
        pass
    print("fixedpoint selftest PASS")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
    else:
        print(__doc__)
