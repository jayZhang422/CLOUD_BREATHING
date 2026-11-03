"""预转置视图与板端 compact gather 朝向 1/2 的逐像素等价性（纯数学，不依赖 CT 夹具）。"""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from pc_fpga.ct import vol2  # noqa: E402
from pc_fpga.ct.vol2 import (DDR_INPUT_LIMIT, VIEW_TOP, _align, derive_geometry, derive_plane,  # noqa: E402
                             plan_views)
from pc_fpga.ethernet.volume import IMAGE_BASE  # noqa: E402


def hardware_gather(flat, row_stride, grid_w, grid_h, orientation):
    """逐像素复现 op_volume_transform 的 compact 地址与填充判定（输出 512x512，字节级）。

    与 RTL 一致：a=pixel[17:9]、b=pixel[8:0]；朝向 0 取 (x,y)=(b,a)，朝向 1 取 (a,b)，
    朝向 2 取 (511-a,511-b)；减去居中填充量后做 10 位无符号比较，越界输出 0x80。
    """
    pixel = np.arange(512 * 512)
    a, b = pixel >> 9, pixel & 511
    if orientation == 0:
        x, y = b, a
    elif orientation == 1:
        x, y = a, b
    else:
        x, y = 511 - a, 511 - b
    x = (x - ((512 - grid_w) >> 1)) & 1023
    y = (y - ((512 - grid_h) >> 1)) & 1023
    padding = (x >= grid_w) | (y >= grid_h)
    out = np.full(pixel.shape, 0x80, np.uint8)
    out[~padding] = np.asarray(flat, np.uint8)[y[~padding] * row_stride + x[~padding]]
    return out


class TransposeEquivalence(unittest.TestCase):
    def check(self, grid_w, grid_h, orientation, seed):
        rng = np.random.default_rng(seed)
        stride = _align(grid_w)
        source = np.zeros((grid_h, stride), np.int8)
        source[:, :grid_w] = rng.integers(-100, 100, (grid_h, grid_w), dtype=np.int8)
        geometry = derive_geometry(orientation, grid_w, grid_h)
        new_stride = _align(geometry["width"])
        derived = derive_plane(source, geometry, new_stride)
        self.assertLessEqual(geometry["width"], 512)
        self.assertLessEqual(geometry["height"], 512)
        self.assertLessEqual(new_stride, 4096)
        expected = hardware_gather(source.reshape(-1), stride, grid_w, grid_h, orientation)
        actual = hardware_gather(derived.reshape(-1), new_stride, geometry["width"], geometry["height"], 0)
        np.testing.assert_array_equal(actual, expected)
        # 派生平面在读取范围内：最大地址不超过平面字节数。
        self.assertEqual(derived.size, geometry["height"] * new_stride)

    def test_native_and_even_lobe_grids(self):
        self.check(512, 512, 1, 1)
        self.check(278, 278, 2, 2)
        self.check(278, 278, 1, 3)

    def test_odd_and_rectangular_grids(self):
        for index, (grid_w, grid_h) in enumerate(((277, 277), (5, 7), (7, 5), (1, 1), (300, 211), (211, 300), (511, 2), (2, 511))):
            for orientation in (1, 2):
                self.check(grid_w, grid_h, orientation, 10 + index * 2 + orientation)


RESULT_BASE = 0x10000000
SKIP_LO, SKIP_HI = 0x1E000000, 0x20000000


def lobe_grid(depth):
    """与 prepare_vol2 相同的 1.5 mm 肺叶网格（本例用 0.80078125/0.80078125/1.0 mm 间距）。"""
    spacing = np.array([1.0, 0.80078125, 0.80078125])
    return tuple(int(v) for v in np.maximum(2, np.rint((np.array([depth, 512, 512]) - 1) * spacing / 1.5).astype(int) + 1))


class PlanViews(unittest.TestCase):
    def plan(self, depth, transpose=True, direction=0):
        z, h, w = lobe_grid(depth)
        return plan_views(depth, z, w, h, depth * 524288, direction, transpose)

    def check_invariants(self, views, depth):
        end = RESULT_BASE + depth * 524288
        for view in views:
            self.assertEqual(view["base"] % 32, 0, view["name"])
            self.assertEqual(view["bytes"], view["planes"] * view["plane_stride"], view["name"])
            self.assertLessEqual(view["base"] + view["bytes"], VIEW_TOP, view["name"])
            low = view["base"] >= IMAGE_BASE and view["base"] + view["bytes"] <= DDR_INPUT_LIMIT
            after = view["base"] >= end and (view["base"] + view["bytes"] <= SKIP_LO or view["base"] >= SKIP_HI)
            self.assertTrue(low or after, f"{view['name']} 位置不在 RTL 允许窗口内: {view['base']:#x}")
        for index, first in enumerate(views):
            for second in views[index + 1:]:
                self.assertFalse(first["base"] < second["base"] + second["bytes"] and
                                 second["base"] < first["base"] + first["bytes"], (first["name"], second["name"]))

    def test_334_slices_places_native_t_in_extension(self):
        # 本次实测病例：334 层。旧布局下 native_t 放不下被静默丢弃，airway/tumor 的 gather 全未命中。
        views, geometries, dropped = self.plan(334)
        by_name = {view["name"]: view for view in views}
        self.assertEqual(dropped, [])
        self.assertEqual([view["name"] for view in views], ["native", "lobe", "lobe_t", "native_t"])
        self.assertIn("native_t", geometries)
        self.assertGreaterEqual(by_name["native_t"]["base"], SKIP_HI)
        self.check_invariants(views, 334)

    def test_245_slices_keeps_working_without_extension_for_lobe_t(self):
        views, _, dropped = self.plan(245)
        self.assertEqual(dropped, [])
        self.assertEqual([view["name"] for view in views], ["native", "lobe", "lobe_t", "native_t"])
        self.check_invariants(views, 245)

    def test_small_volume_stays_in_low_window(self):
        views, _, dropped = self.plan(2)
        self.assertEqual(dropped, [])
        for view in views:
            self.assertLessEqual(view["base"] + view["bytes"], DDR_INPUT_LIMIT)
        self.check_invariants(views, 2)

    def test_maximum_depth_layout_is_legal_or_explicitly_dropped(self):
        for depth in (400, 448, 480):
            z, h, w = lobe_grid(depth)
            if z > 480:
                continue
            try:
                views, _, dropped = self.plan(depth)
            except ValueError:
                continue  # 原生卷本身放不下低区属于既有限制，不由本改动引入
            self.check_invariants(views, depth)
            self.assertEqual({v["name"] for v in views} | set(dropped), {"native", "lobe", "lobe_t", "native_t"})

    def test_no_transpose_has_only_native_and_lobe(self):
        views, geometries, dropped = self.plan(334, transpose=False)
        self.assertEqual([view["name"] for view in views], ["native", "lobe"])
        self.assertEqual((geometries, dropped), ({}, []))

    def test_view_that_cannot_fit_is_reported_not_silently_lost(self):
        # 把视图窗口压到不足以容纳 native_t：必须出现在 dropped 中，而不是悄悄消失。
        with patch.object(vol2, "VIEW_TOP", 0x20000000):
            _, geometries, dropped = self.plan(334)
        self.assertEqual(dropped, ["native_t"])
        self.assertNotIn("native_t", geometries)

    def test_nothing_is_ever_placed_inside_the_skip_zone(self):
        for depth in range(1, 481, 7):
            z, h, w = lobe_grid(depth)
            if z > 480:
                continue
            try:
                views, _, _ = self.plan(depth)
            except ValueError:
                continue
            for view in views:
                end = view["base"] + view["bytes"]
                self.assertFalse(view["base"] < SKIP_HI and end > SKIP_LO, (depth, view["name"], hex(view["base"])))


if __name__ == "__main__":
    unittest.main()
