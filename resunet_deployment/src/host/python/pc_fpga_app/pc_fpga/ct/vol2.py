"""VOL2 compact, row-major INT8 views for whole-volume FPGA uploads."""
import struct
import warnings
from pathlib import Path

import numpy as np

from ..ethernet.volume import IMAGE_BASE, RESULT_BASE
from ..files import check_file, read_json, write_json
from .prediction_io import file_sha256

VOL2_HEADER = struct.Struct("<4sHHII")
VOL2_ENTRY = struct.Struct("<8sBBHIIIIHHII")
DDR_INPUT_LIMIT = 0x08000000
# 0x1E000000..0x20000000 是固定 decoder 阶段的 skip 兼容区（op_engine 对 concat 的地址映射），任何视图都不得落入。
DERIVED_DDR_LIMIT = 0x1E000000
# 扩展区：RTL 的 kind-4 视图上限（op_volume_service.VIEW_TOP）。334 层整卷下结果区之后只剩约 57 MiB，
# 放不下 native_t（约 84 MiB），所以必须允许把视图放到 0x20000000 之后。
EXT_BASE = 0x20000000
DDR_LIMIT = VIEW_TOP = 0x30000000
# v4：增加扩展区放置并禁止落入 skip 区；v3 缓存中可能缺少 native_t，必须重新生成。
LAYOUT_VERSION = 4
# (派生视图名, 源视图, 被等价替代的 compact gather 朝向)：
# lobe 用朝向 2、airway/tumor 用朝向 1。朝向 1/2 会让相邻输出像素读相邻行，
# 8 行缓存全部未命中；预先把平面转置/翻转后，板端用朝向 0 即可顺序读取，输出逐字节相同。
DERIVED_VIEWS = (("lobe_t", "lobe", 2), ("native_t", "native", 1))
PAD_BYTE = 0x80  # RTL 对 padding 像素写入 24'h808080


def _align(value, alignment=32):
    return (value + alignment - 1) // alignment * alignment


def _coordinates(old, new):
    denominator = max(new - 1, 1)
    numerator = np.arange(new, dtype=np.int64) * (old - 1) * 65536
    coordinate, remainder = np.divmod(numerator, denominator)
    coordinate += (remainder * 2 > denominator) | (
        (remainder * 2 == denominator) & ((coordinate & 1) != 0))
    low = coordinate >> 16
    return low, coordinate & 65535


def hardware_axes(orientation, grid_w, grid_h):
    """复现 op_volume_transform 的 compact 坐标变换（输出 512x512）。

    a=pixel[17:9]、b=pixel[8:0]；朝向 1 取 native_x=a、native_y=b，朝向 2 取 511-a、511-b，
    再减去居中填充量。返回 a→native_x 与 b→native_y 的映射及有效性（无符号 10 位比较，
    负值回绕后必然 >= 网格尺寸，即视为填充）。
    """
    if orientation not in (1, 2):
        raise ValueError("only orientation 1 and 2 can be derived")
    along = np.arange(512, dtype=np.int64)
    if orientation == 2:
        along = 511 - along
    nx = along - ((512 - grid_w) >> 1)
    ny = along - ((512 - grid_h) >> 1)
    return nx, (nx >= 0) & (nx < grid_w), ny, (ny >= 0) & (ny < grid_h)


def _fit_grid(valid):
    """在板端居中规则 pad=(512-g)>>1 下，找最小的 g 使 [pad, pad+g) 覆盖全部有效位置。"""
    indices = np.flatnonzero(valid)
    low, high = int(indices[0]), int(indices[-1])
    for size in range(high - low + 1, 513):
        pad = (512 - size) >> 1
        if pad <= low and pad + size - 1 >= high:
            return size, pad
    raise ValueError("derived view does not fit a 512x512 output")


def derive_geometry(orientation, grid_w, grid_h):
    """返回朝向 0 读取派生平面所需的尺寸与行/列源索引。行对应 a，列对应 b。"""
    nx, valid_x, ny, valid_y = hardware_axes(orientation, grid_w, grid_h)
    new_height, pad_y = _fit_grid(valid_x)
    new_width, pad_x = _fit_grid(valid_y)
    rows = pad_y + np.arange(new_height)
    cols = pad_x + np.arange(new_width)
    return dict(width=new_width, height=new_height, row_source=nx[rows], row_valid=valid_x[rows],
                col_source=ny[cols], col_valid=valid_y[cols])


def derive_plane(plane, geometry, row_stride):
    """plane 为 [native_y, native_x] 的 INT8 平面；返回 height x row_stride 的 uint8 派生平面。"""
    out = np.full((geometry["height"], row_stride), PAD_BYTE, dtype=np.uint8)
    rows = np.flatnonzero(geometry["row_valid"])
    cols = np.flatnonzero(geometry["col_valid"])
    sample = np.asarray(plane)[np.ix_(geometry["col_source"][cols], geometry["row_source"][rows])]
    out[np.ix_(rows, cols)] = np.ascontiguousarray(sample).view(np.uint8).T
    return out


def _resample_plane(volume, z, zf, yi, yf, xi, xf):
    height, width = len(yi), len(xi)
    total = np.zeros((height, width), dtype=np.int64)
    for iz in range(2):
        source_z = min(z + iz, volume.shape[0] - 1)
        wz = (65536 - zf) if iz == 0 else zf
        for iy in range(2):
            source_y = np.minimum(yi + iy, volume.shape[1] - 1)
            wy = (65536 - yf) if iy == 0 else yf
            for ix in range(2):
                source_x = np.minimum(xi + ix, volume.shape[2] - 1)
                wx = (65536 - xf) if ix == 0 else xf
                samples = volume[source_z, source_y[:, None], source_x[None, :]].astype(np.int64)
                total += samples * wz * wy[:, None] * wx[None, :]
    magnitude = np.abs(total)
    whole, remainder = np.divmod(magnitude, 1 << 48)
    whole += (remainder > (1 << 47)) | ((remainder == (1 << 47)) & ((whole & 1) != 0))
    return (whole * np.sign(total)).clip(-128, 127).astype(np.int8)


def _place_after_result(cursor, size):
    """结果区之后的放置：先用 skip 区之前的窗口，再用扩展区（0x20000000..VIEW_TOP）。

    返回 (base, 新游标) 或 None。任何视图都不能跨入或落入 0x1E000000..0x20000000。
    """
    cursor = _align(cursor)
    if cursor + size <= DERIVED_DDR_LIMIT:
        return cursor, _align(cursor + size)
    start = max(cursor, EXT_BASE)
    if start + size <= VIEW_TOP:
        return start, _align(start + size)
    return None


def plan_views(depth, z_depth, width, height, result_bytes, direction, transpose=True):
    """规划 VOL2 各视图的 DDR 位置（纯函数，不读写文件）。

    放置顺序：低区 [IMAGE_BASE, 0x08000000) → 结果区之后、skip 区之前 → 扩展区 [0x20000000, VIEW_TOP)。
    返回 (views, geometries, dropped)；dropped 为放不下而被放弃的派生视图名。
    """
    native_stride, native_plane = 512, 512 * 512
    lobe_stride, lobe_plane = _align(width), _align(_align(width) * height)
    native_bytes, lobe_bytes = depth * native_plane, z_depth * lobe_plane
    native_base = IMAGE_BASE
    result_end = RESULT_BASE + result_bytes
    if native_base + native_bytes > DDR_INPUT_LIMIT:
        raise ValueError("VOL2 compact views and result allocation exceed protected DDR regions")
    lobe_base = _align(native_base + native_bytes)
    high_cursor = _align(result_end)
    if lobe_base + lobe_bytes > DDR_INPUT_LIMIT:
        placed = _place_after_result(result_end, lobe_bytes)
        if placed is None:
            raise ValueError("VOL2 compact views and result allocation exceed protected DDR regions")
        lobe_base, high_cursor = placed
        low_cursor = _align(native_base + native_bytes)
    else:
        low_cursor = _align(lobe_base + lobe_bytes)

    views = [
        dict(name="native", direction=direction, base=native_base, planes=depth, width=512, height=512,
             row_stride=native_stride, plane_stride=native_plane, bytes=native_bytes),
        dict(name="lobe", direction=direction, base=lobe_base, planes=z_depth, width=width, height=height,
             row_stride=lobe_stride, plane_stride=lobe_plane, bytes=lobe_bytes),
    ]
    geometries, dropped = {}, []
    if transpose:
        by_name = {view["name"]: view for view in views}
        for name, source_name, orientation in DERIVED_VIEWS:
            source_view = by_name[source_name]
            geometry = derive_geometry(orientation, source_view["width"], source_view["height"])
            stride = _align(geometry["width"])
            plane_stride = _align(stride * geometry["height"])
            size = source_view["planes"] * plane_stride
            if low_cursor + size <= DDR_INPUT_LIMIT:
                base, low_cursor = low_cursor, _align(low_cursor + size)
            else:
                placed = _place_after_result(high_cursor, size)
                if placed is None:
                    dropped.append(name)
                    continue
                base, high_cursor = placed
            geometries[name] = (geometry, stride, plane_stride)
            views.append(dict(name=name, direction=source_view["direction"], base=base, planes=source_view["planes"],
                              width=geometry["width"], height=geometry["height"], row_stride=stride,
                              plane_stride=plane_stride, bytes=size, source=source_name,
                              orientation=orientation))
    for index, first in enumerate(views):
        for second in views[index + 1:]:
            if first["base"] < second["base"] + second["bytes"] and second["base"] < first["base"] + first["bytes"]:
                raise ValueError("VOL2 view DDR ranges overlap")
    return views, geometries, dropped


def prepare_vol2(case_dir, job, metadata, transpose=True):
    """Write native and lobe-resampled planes with aligned strides and a VOL2 table.

    transpose=True 时再追加朝向等价的派生视图（lobe_t/native_t），见 DERIVED_VIEWS。
    """
    case = Path(case_dir)
    source = check_file(case / job["input"]["file"], job["input"]["bytes"], job["input"]["sha256"])
    out = case / "input/ct_volume_vol2.bin"
    sidecar = case / "input/ct_volume_vol2.json"
    if sidecar.exists():
        cached = read_json(sidecar)
        if (cached.get("source_sha256") == job["input"]["sha256"]
                and cached["compact_bin"].get("layout_version") == LAYOUT_VERSION
                and cached["compact_bin"].get("transposed") == bool(transpose)):
            check_file(out, cached["compact_bin"]["bytes"], cached["compact_bin"]["sha256"])
            return cached["compact_bin"]
    depth = int(job["input"]["shape"][0])
    affine = np.asarray(metadata["affine_z_y_x_to_lps_mm"], dtype=np.float64)
    spacing = np.linalg.norm(affine[:3, :3], axis=0)
    z_depth, height, width = np.maximum(
        2, np.rint((np.array([depth, 512, 512]) - 1) * spacing / 1.5).astype(int) + 1)
    z_depth, height, width = map(int, (z_depth, height, width))
    if max(height, width) > 512 or z_depth > 480:
        raise ValueError(f"VOL2 lobe grid exceeds FPGA bounds: {(z_depth, height, width)}")

    views, geometries, dropped = plan_views(
        depth, z_depth, width, height, job["result_contract"]["bytes"],
        4 if metadata["anatomical_z_direction"] < 0 else 0, transpose)
    lobe_stride, lobe_plane = views[1]["row_stride"], views[1]["plane_stride"]
    if dropped:
        warnings.warn(
            f"VOL2 派生视图 {','.join(dropped)} 在 DDR 视图窗口中放不下，已退回原朝向 gather；"
            "朝向 1/2 会使 8 行缓存全部未命中，推理将明显变慢。", RuntimeWarning, stacklevel=2)

    native_view = np.memmap(source, mode="r", dtype=np.int8, shape=(depth, 512, 512))
    zq, zf = _coordinates(depth, z_depth)
    yq, yf = _coordinates(512, height)
    xq, xf = _coordinates(512, width)
    zlow = np.minimum(zq, depth - 1)
    ylow = np.minimum(yq, 511)
    xlow = np.minimum(xq, 511)
    with out.open("wb") as stream:
        stream.write(bytes(VOL2_HEADER.size + len(views) * VOL2_ENTRY.size))
        offsets = []
        for view in views:
            stream.seek(_align(stream.tell()))
            offsets.append(stream.tell())
            stream.seek(stream.tell() + view["bytes"])
        stream.truncate()
        for view, offset in zip(views, offsets):
            view["file_offset"] = offset
        stream.seek(offsets[0])
        native_view.tofile(stream)
        offset_by_name = {view["name"]: offset for view, offset in zip(views, offsets)}
        if "native_t" in geometries:
            geometry, stride, plane_stride = geometries["native_t"]
            stream.seek(offset_by_name["native_t"])
            for z in range(depth):
                stream.write(derive_plane(native_view[z], geometry, stride).tobytes())
                stream.write(bytes(plane_stride - stride * geometry["height"]))
        stream.seek(offsets[1])
        for z in range(z_depth):
            plane = _resample_plane(native_view, int(zlow[z]), int(zf[z]), ylow, yf, xlow, xf)
            for row in plane:
                stream.write(row.tobytes())
                stream.write(bytes(lobe_stride - width))
            stream.write(bytes(lobe_plane - lobe_stride * height))
            if "lobe_t" in geometries:
                geometry, stride, plane_stride = geometries["lobe_t"]
                resume = stream.tell()
                stream.seek(offset_by_name["lobe_t"] + z * plane_stride)
                stream.write(derive_plane(plane, geometry, stride).tobytes())
                stream.write(bytes(plane_stride - stride * geometry["height"]))
                stream.seek(resume)
        table = bytearray()
        for view in views:
            table.extend(VOL2_ENTRY.pack(view["name"].encode("ascii"), view["direction"], 1, 0,
                view["file_offset"], view["base"], view["planes"], view["bytes"],
                view["width"], view["height"], view["row_stride"], view["plane_stride"]))
        stream.seek(0)
        stream.write(VOL2_HEADER.pack(b"VOL2", 2, len(views), depth,
                                      VOL2_HEADER.size + len(table)))
        stream.write(table)
    compact = dict(file="input/ct_volume_vol2.bin", bytes=out.stat().st_size,
        sha256=file_sha256(out), header_bytes=VOL2_HEADER.size + len(views)*VOL2_ENTRY.size,
        views=views, layout_version=LAYOUT_VERSION, transposed=bool(transpose),
        lobe_resampling="align-corners Q16/RNE, one final signed RNE, INT8 saturation")
    write_json(sidecar, dict(source_sha256=job["input"]["sha256"], compact_bin=compact))
    return compact
