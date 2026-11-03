"""Shared CPU crossing, parity and interval rules in millimetres."""
import numpy as np

HIT_TOLERANCE_MM = 1.e-5


def collapse_crossings(hits):
    values = np.sort(np.asarray(hits, dtype=np.float64))
    if not np.isfinite(values).all():
        raise ValueError('nonfinite crossing')
    return values[np.r_[True, np.diff(values) > HIT_TOLERANCE_MM]] if len(values) else values


def inside_from_crossings(hits):
    return bool(len(collapse_crossings(hits)) % 2)


def inside_intervals(hits, length, origin_inside, *, presorted=False):
    """Clip a complete crossing list and pair every inside segment."""
    if not np.isfinite(length) or length <= 0:
        raise ValueError('ray length must be finite and positive')
    crossings = np.asarray(hits) if presorted else collapse_crossings(hits)
    crossings = crossings[(crossings > 1.e-6) & (crossings < length - 1.e-6)]
    edges = np.r_[0., crossings, length]
    start = 0 if origin_inside else 1
    return np.column_stack((edges[:-1][start::2], edges[1:][start::2]))


def volume_fraction(hits, length, origin_inside, *, presorted=False):
    intervals = inside_intervals(hits, length, origin_inside, presorted=presorted) / length
    return float(np.sum(intervals[:, 1] ** 3 - intervals[:, 0] ** 3))


def path_entry(hits, length, *, presorted=False):
    crossings = np.asarray(hits) if presorted else collapse_crossings(hits)
    crossings = crossings[(crossings > 1.e-6) & (crossings <= length + 1.e-6)]
    return float(crossings[-1]) if len(crossings) else float(length)
