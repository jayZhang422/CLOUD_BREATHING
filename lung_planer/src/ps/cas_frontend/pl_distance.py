"""Strict driver for the independent exact centreline DDR distance block."""
import os
import sys
from time import perf_counter

import numpy as np

from .voxel_mask import VoxelMask, integer_axis_weights


def evaluate_mask_distances(client, volume, coordinates, *, max_radius=64, timeout_seconds=30.):
    started = perf_counter()
    if not isinstance(volume, VoxelMask):
        raise TypeError('需要经过校验的 VoxelMask')
    coords = np.asarray(coordinates)
    if (coords.ndim != 2 or coords.shape[1] != 3 or coords.dtype.kind not in 'iu'
            or len(coords) < 1 or len(coords) > 262144
            or np.any(coords < 0) or np.any(coords >= np.asarray(volume.data.shape))):
        raise ValueError('PL 距离查询坐标无效')
    if max(volume.data.shape) > 1024 or volume.data.size > 48_000_000:
        raise ValueError('PL 掩膜超过 1024/轴或 4800 万体素能力限制')
    weights = integer_axis_weights(volume.spacing)
    max_radius = int(max_radius)
    if not 1 <= max_radius <= 1023 or not np.isfinite(timeout_seconds) or not 0 < timeout_seconds <= 40:
        raise ValueError('PL 半径或超时参数无效')
    if not client.configured:
        raise RuntimeError('PL disabled by LUNG_PL_ENABLE; 没有 CPU 回退')
    if sys.platform == 'linux' and os.geteuid() != 0:
        if client._privileged is None:
            from .pl_privileged import PrivilegedPlClient
            client._privileged = PrivilegedPlClient(client.bit_path, require_strict_pl=client.require_strict_pl)
        result = client._privileged.evaluate_mask_distances(
            volume, coords, max_radius=max_radius, timeout_seconds=timeout_seconds)
        if not result.get('ok'):
            raise RuntimeError(result.get('error', 'PL 中心线距离查询失败；没有 CPU 回退'))
        return result
    overlay_started = perf_counter()
    client._load()
    overlay_load_ms = (perf_counter() - overlay_started) * 1000.
    dma, mmio = client._centerline_dma, client._centerline_mmio
    if dma is None or mmio is None:
        raise RuntimeError('当前固件没有中心线距离加速能力；没有 CPU 回退')
    if mmio.read(0) & 1:
        raise RuntimeError('中心线 PL 模块正在执行另一个任务')
    # Previous successful job has drained DMA and AXI; its buffers can now go.
    for buffer in client._centerline_buffers:
        buffer.freebuffer()
    client._centerline_buffers = []
    from .pl_metrics import _import_pynq
    _, allocate, _ = _import_pynq()
    touched_hardware = False
    try:
        allocation_started = perf_counter()
        mask_size = (volume.data.size + 15) // 16 * 16
        mask_buf = allocate(shape=(mask_size,), dtype='u1')
        client._centerline_buffers.append(mask_buf)
        input_buf = allocate(shape=(len(coords), 4), dtype='<u4')
        client._centerline_buffers.append(input_buf)
        output_buf = allocate(shape=(len(coords), 4), dtype='<u4')
        client._centerline_buffers.append(output_buf)
        cma_allocation_ms = (perf_counter() - allocation_started) * 1000.
        buffer_write_started = perf_counter()
        mask_buf[:] = 0
        mask_buf[:volume.data.size] = volume.data.ravel(order='C')
        input_buf[:] = 0
        input_buf[:, 0] = coords[:, 0].astype(np.uint32) | coords[:, 1].astype(np.uint32) << 16
        input_buf[:, 1] = coords[:, 2].astype(np.uint32)
        input_buf[:, 2] = np.arange(len(coords), dtype=np.uint32)
        output_buf[:] = 0xffffffff
        buffer_write_ms = (perf_counter() - buffer_write_started) * 1000.
        flush_started = perf_counter()
        mask_buf.flush(); input_buf.flush(); output_buf.flush()
        cache_flush_ms = (perf_counter() - flush_started) * 1000.
        preparation_ms = (perf_counter()-started)*1000
        base = int(mask_buf.physical_address)
        settings = {0x24:len(coords), 0x28:volume.data.shape[0], 0x2c:volume.data.shape[1],
                    0x30:volume.data.shape[2], 0x34:int(weights[0]), 0x38:int(weights[1]),
                    0x3c:int(weights[2]), 0x40:base & 0xffffffff, 0x44:base >> 32,
                    0x48:max_radius, 0x4c:int(timeout_seconds*(client.clock_mhz or 100.)*1e6)}
        register_started = perf_counter()
        for register, value in settings.items():
            mmio.write(register, int(value))
            if mmio.read(register) != int(value):
                raise RuntimeError('中心线 PL 配置回读不匹配')
        register_setup_ms = (perf_counter() - register_started) * 1000.
        hardware_started = perf_counter()
        touched_hardware = True
        dma_started = perf_counter()
        dma.recvchannel.transfer(output_buf)
        mmio.write(0, 1)
        dma.sendchannel.transfer(input_buf)
        deadline = hardware_started + timeout_seconds + 2
        while True:
            errors = mmio.read(0x10)
            if errors:
                raise RuntimeError('中心线 PL 错误位 0x%08x；没有 CPU 回退' % errors)
            # AXI DMA error flags: internal, slave, decode, SG internal/slave/decode.
            if dma.mmio.read(4) & 0x770 or dma.mmio.read(0x34) & 0x770:
                raise RuntimeError('中心线 DMA 错误；没有 CPU 回退')
            if dma.recvchannel.idle and dma.sendchannel.idle and mmio.read(0) & 2:
                break
            if perf_counter() >= deadline:
                raise TimeoutError('中心线 PL 超时；没有 CPU 回退')
        dma.recvchannel.wait(); dma.sendchannel.wait()
        dma_transfer_wait_ms = (perf_counter() - dma_started) * 1000.
        invalidate_started = perf_counter()
        output_buf.invalidate()
        cache_invalidate_ms = (perf_counter() - invalidate_started) * 1000.
        hardware_ms = (perf_counter()-hardware_started)*1000
        result_started = perf_counter()
        raw = np.asarray(output_buf).copy()
        if (mmio.read(0x14) != len(coords) or np.any(raw[:, 2] != np.arange(len(coords)))
                or np.any(raw[:, 1] >> 16) or np.any(raw[:, 3])):
            raise RuntimeError('中心线 PL 结果数量、标识或状态不匹配')
        halves = raw.view('<i2').reshape(-1, 8)
        deltas = halves[:, :3].astype(np.int64)
        nearest = coords.astype(np.int64) + deltas
        if (np.any(nearest < 0) or np.any(nearest >= volume.data.shape)
                or np.any(volume.data[tuple(nearest.T)] != 0)):
            raise RuntimeError('中心线 PL 返回的最近背景点无效')
        radii = np.sqrt(np.sum((deltas*volume.spacing)**2, axis=1))
        result_validation_ms = (perf_counter() - result_started) * 1000.
        cycles = mmio.read(0x18)
        kernel_ms = cycles/((client.clock_mhz or 100.)*1000)
        return dict(ok=True, radii_mm=radii.tolist(), deltas_xyz=deltas.tolist(),
                    processed=len(coords), pl_calls=1, cpu_fallback_count=0,
                    abi='0x00010000', capabilities=mmio.read(12), cycles=cycles,
                    ddr_reads=mmio.read(0x1c), candidates=mmio.read(0x20),
                    clock_mhz=client.clock_mhz, mask_bytes=volume.data.nbytes,
                    timings_ms=dict(preparation=preparation_ms, hardware_and_dma=hardware_ms,
                                    overlay_load=overlay_load_ms,
                                    cma_allocation=cma_allocation_ms,
                                    buffer_write=buffer_write_ms,
                                    cache_flush=cache_flush_ms,
                                    register_setup=register_setup_ms,
                                    dma_transfer_wait=dma_transfer_wait_ms,
                                    cache_invalidate=cache_invalidate_ms,
                                    dma_non_kernel_remainder=max(0., dma_transfer_wait_ms-kernel_ms),
                                    kernel=kernel_ms,
                                    result_validation=result_validation_ms,
                                    total=(perf_counter()-started)*1000))
    except Exception:
        if touched_hardware:
            # This resets the whole shared overlay BEFORE releasing any CMA
            # buffers. A failed reset keeps the buffers owned for safe recovery.
            client._reset_hardware_state()
        raise
