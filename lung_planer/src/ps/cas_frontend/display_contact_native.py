"""ctypes releases the GIL during PS queries; all inputs remain caller-owned."""
import ctypes
from functools import lru_cache
from pathlib import Path

import numpy as np


@lru_cache(maxsize=1)
def library():
    path = Path(__file__).resolve().parents[1] / 'native/display_contact/libdisplay_contact.so'
    lib = ctypes.CDLL(str(path))
    ptr = ctypes.c_void_p
    lib.display_contact_v1.argtypes = [ptr, ctypes.c_int64, ptr, ctypes.c_int64,
        ptr, ptr, ptr, ptr, ptr, ctypes.c_int64, ctypes.c_int64, ptr,
        ctypes.c_double, ctypes.c_double, ptr, ptr, ptr]
    lib.display_contact_v1.restype = ctypes.c_int
    return lib


def query(index, points, tolerance, direction, hit_tolerance):
    children, leaf, members, width = index.display_contact_arrays()
    # No cached geometry copy: each invocation uses the same index's current
    # triangles and immutable BVH arrays. The references outlive the native call.
    triangles = np.ascontiguousarray(index.triangles, dtype=np.float64)
    mask, guard = np.zeros(len(points), dtype=np.uint8), np.zeros(len(points), dtype=np.uint8)
    counters = np.zeros(3, dtype=np.uint64)
    pointer = lambda a: ctypes.c_void_p(a.ctypes.data)
    code = library().display_contact_v1(pointer(points), len(points), pointer(triangles), len(triangles),
        pointer(index.low), pointer(index.high), pointer(children), pointer(leaf), pointer(members),
        len(index.low), width, pointer(direction), tolerance, hit_tolerance,
        pointer(mask), pointer(guard), pointer(counters))
    if code:
        raise RuntimeError(f'PS display query failed ({code})')
    return mask.astype(bool), guard.astype(bool), counters
