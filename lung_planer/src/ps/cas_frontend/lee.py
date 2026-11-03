"""Exact CPU Lee implementation selection; neither path represents PL work."""
import importlib.util
import os
from pathlib import Path
import sysconfig
from time import perf_counter

import numpy as np

_native = None


def _load_native():
    global _native
    if _native is not None:
        return _native
    path = (Path(__file__).resolve().parents[1] / 'native/lee' /
            ('_lee_native' + sysconfig.get_config_var('EXT_SUFFIX')))
    if not path.is_file():
        return None
    spec = importlib.util.spec_from_file_location('_lee_native', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    _native = module
    return module


def skeletonize_lee(mask, *, timings=None, implementation=None):
    """Keep six-direction order and sequential deletion rechecks unchanged.

    Auto uses the validated board extension when installed. Explicit native
    selection fails if it is missing. Desktop platforms without that extension
    retain scikit-image. Hardware distance selection remains independent.
    """
    implementation = implementation or os.environ.get('CLOUD_BREATHING_LEE_IMPLEMENTATION', 'auto')
    if implementation not in ('auto', 'native', 'skimage'):
        raise ValueError('Unknown CPU Lee implementation: ' + implementation)
    native = _load_native() if implementation != 'skimage' else None
    if implementation == 'native' and native is None:
        raise RuntimeError('Exact native CPU Lee extension is not installed')
    if native is None:
        from skimage.morphology import skeletonize
        return skeletonize(mask, method='lee')
    # Match skeletonize's public nonzero-as-foreground convention, including
    # existing callers that pass a canonical uint8 VoxelMask directly.
    mask = np.asarray(mask, dtype=np.bool_)
    if mask.ndim != 3:
        raise ValueError('Native Lee requires a 3D mask')
    started = perf_counter()
    # The native extension accepts only C-contiguous buffers.  np.pad may
    # return a strided view for some input layouts, so normalize before the
    # exact CPU kernel call rather than relying on the caller's mask layout.
    padded = np.ascontiguousarray(np.pad(mask.astype(np.uint8), 1), dtype=np.uint8)
    pad_ms = (perf_counter()-started)*1000.
    started = perf_counter()
    stats = native.thin(padded, scan='foreground', bits=True)
    native_ms = (perf_counter()-started)*1000.
    started = perf_counter()
    result = np.ascontiguousarray(padded[1:-1, 1:-1, 1:-1], dtype=np.bool_)
    if timings is not None:
        timings.update(lee_native_pad_ms=pad_ms, lee_native_ms=native_ms,
                       lee_native_export_ms=(perf_counter()-started)*1000.,
                       lee_native_gather_ms=stats['gather_seconds']*1000.,
                       lee_native_filter_ms=stats['filter_seconds']*1000.,
                       lee_native_recheck_ms=stats['recheck_seconds']*1000.,
                       lee_native_direction_calls=stats['direction_calls'],
                       lee_native_cpu_calls=1)
    return result
