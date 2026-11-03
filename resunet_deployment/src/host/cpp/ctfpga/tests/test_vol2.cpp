// 预转置派生视图与板端 compact gather 朝向 1/2 的逐像素等价（对应 Python test_vol2_transpose.py）。
#include <cstdio>
#include <random>

#include "ct/dicom.hpp"
#include "ct/vol2.hpp"

using namespace ctf;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

// 逐像素复现 op_volume_transform：输出 512x512，越界 0x80。
static std::vector<uint8_t> hardware_gather(const std::vector<int8_t>& flat, int row_stride, int gw, int gh, int orient) {
  std::vector<uint8_t> out(512 * 512, 0x80);
  for (int pixel = 0; pixel < 512 * 512; ++pixel) {
    int a = pixel >> 9, b = pixel & 511, x, y;
    if (orient == 0) { x = b; y = a; }
    else if (orient == 1) { x = a; y = b; }
    else { x = 511 - a; y = 511 - b; }
    x = (x - ((512 - gw) >> 1)) & 1023;
    y = (y - ((512 - gh) >> 1)) & 1023;
    if (x >= gw || y >= gh) continue;
    out[pixel] = (uint8_t)flat[(size_t)y * row_stride + x];
  }
  return out;
}

static void check_equiv(int gw, int gh, int orient, unsigned seed) {
  std::mt19937 rng(seed);
  const int stride = (int)align_up(gw);
  std::vector<int8_t> src((size_t)gh * stride, 0);
  for (int y = 0; y < gh; ++y)
    for (int x = 0; x < gw; ++x) src[(size_t)y * stride + x] = (int8_t)((int)(rng() % 200) - 100);
  Geometry g = derive_geometry(orient, gw, gh);
  const size_t dstride = align_up(g.width);
  // derive_plane 的源平面按 [native_y][native_x] 索引，行步长即 stride。
  auto plane = derive_plane(src.data(), stride, g, dstride);
  // 板端用朝向 0 读取派生平面，应与原朝向读取源平面逐字节相同。
  std::vector<int8_t> derived(plane.size());
  for (size_t i = 0; i < plane.size(); ++i) derived[i] = (int8_t)plane[i];
  auto expect = hardware_gather(src, stride, gw, gh, orient);
  auto got = hardware_gather(derived, (int)dstride, g.width, g.height, 0);
  CHECK(expect == got);
}

// 视图布局（对应 Python plan_views）：不重叠、不落入 skip 区、不越过 VIEW_TOP。
static void check_layout(int depth, int z_depth, int w, int h, bool expect_native_t_ext) {
  ViewPlan p = plan_views(depth, z_depth, w, h, (uint64_t)depth * 524288, 0, true);
  CHECK(p.dropped.empty());
  CHECK(p.views.size() == 4);
  bool has_ext = false;
  for (size_t i = 0; i < p.views.size(); ++i) {
    const View& v = p.views[i];
    CHECK(v.base % 32 == 0 && v.base + v.bytes <= VIEW_TOP);
    CHECK(!(v.base < 0x20000000ull && v.base + v.bytes > DERIVED_DDR_LIMIT));  // 不跨入/落入 skip 区
    CHECK(!(v.base >= DERIVED_DDR_LIMIT && v.base < EXT_BASE));
    if (v.name == "native_t" && v.base >= EXT_BASE) has_ext = true;
    for (size_t j = i + 1; j < p.views.size(); ++j)
      CHECK(!(v.base < p.views[j].base + p.views[j].bytes && p.views[j].base < v.base + v.bytes));
  }
  CHECK(has_ext == expect_native_t_ext);
}

int main() {
  unsigned seed = 1;
  check_layout(334, 223, 274, 274, true);   // 326~334 层整卷：native_t 只能放扩展区
  check_layout(120, 80, 274, 274, false);   // 小体积：全部落在低区/结果区之后
  CHECK(LAYOUT_VERSION == 4);
  for (int orient : {1, 2})
    for (auto sz : {std::pair<int, int>{278, 278}, {512, 512}, {300, 301}, {511, 480}, {97, 331}})
      check_equiv(sz.first, sz.second, orient, seed++);

  // Q16 坐标：端点精确，且单调不减
  std::vector<int> lo, fr;
  q16_coordinates(245, 204, lo, fr);
  CHECK(lo.front() == 0 && fr.front() == 0);
  CHECK(lo.back() == 244 && fr.back() == 0);
  for (size_t i = 1; i < lo.size(); ++i) CHECK(lo[i] * 65536 + fr[i] >= lo[i - 1] * 65536 + fr[i - 1]);

  // HU 量化边界：-1024→-128，1000→127，最近偶数舍入
  CHECK(quantize_hu(-2000.f) == -128 && quantize_hu(-1024.f) == -128);
  CHECK(quantize_hu(1000.f) == 127 && quantize_hu(5000.f) == 127);
  CHECK(quantize_hu(0.f) == (int8_t)((int)std::nearbyintf(1024.f * 255.f / 2024.f) - 128));
  if (failures == 0) std::puts("test_vol2 OK");
  return failures != 0;
}
