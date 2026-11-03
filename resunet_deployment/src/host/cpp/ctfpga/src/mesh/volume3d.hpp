// 三维体数据基础：掩膜容器、包围盒/ROI、连通域标记、NPY(uint8) 读写。
#pragma once
#include <array>
#include "common/util.hpp"

namespace ctf {

struct Dims {
  int z = 0, y = 0, x = 0;
  size_t n() const { return (size_t)z * y * x; }
  bool operator==(const Dims& o) const { return z == o.z && y == o.y && x == o.x; }
  bool operator!=(const Dims& o) const { return !(*this == o); }
};

// 半开区间 [lo, hi)，轴序 z,y,x。允许超出体数据范围（用于带零边距的 ROI）。
struct Box {
  int lo[3] = {0, 0, 0}, hi[3] = {0, 0, 0};
  bool empty() const { return hi[0] <= lo[0] || hi[1] <= lo[1] || hi[2] <= lo[2]; }
  Dims dims() const { return {hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]}; }
};

template <class T>
struct Vol {
  Dims d;
  std::vector<T> v;
  Vol() = default;
  explicit Vol(Dims dd, T fill = T()) : d(dd), v(dd.n(), fill) {}
  size_t idx(int z, int y, int x) const { return ((size_t)z * d.y + y) * d.x + x; }
  T& at(int z, int y, int x) { return v[idx(z, y, x)]; }
  const T& at(int z, int y, int x) const { return v[idx(z, y, x)]; }
};

using Mask = Vol<uint8_t>;
using Spacing = std::array<double, 3>;

inline double vox_volume(const Spacing& s) { return s[0] * s[1] * s[2]; }

Box bbox(const Mask& m);                                     // 空掩膜返回 empty()
Box clip_box(const Box& b, const Dims& d);                   // 与 [0,d) 求交
Box expand_box(const Box& b, const std::array<int, 3>& pad); // 不裁剪
Mask crop(const Mask& m, const Box& b);                      // 越界部分补 0
void paste(Mask& dst, const Mask& src, const Box& at);       // 覆盖写入（越界部分忽略）
void paste_or(Mask& dst, const Mask& src, const Box& at);
size_t count(const Mask& m);

Mask logical_and(const Mask& a, const Mask& b);
Mask logical_or(const Mask& a, const Mask& b);
Mask logical_andnot(const Mask& a, const Mask& b);           // a & ~b
void or_inplace(Mask& a, const Mask& b);
void and_inplace(Mask& a, const Mask& b);

// 连通域标记。connectivity: 1=6 邻域，2=18 邻域，3=26 邻域（对应 generate_binary_structure(3,k)）。
// 标签按栅格扫描首次出现顺序编号（与 scipy.ndimage.label 一致）。返回分量数。
int label(const Mask& m, int connectivity, Vol<int32_t>& out);
// 各标签的体素计数与包围盒（下标 0 为背景）。
void label_stats(const Vol<int32_t>& lab, int n, std::vector<int64_t>& counts, std::vector<Box>& boxes);

// 椭球结构元素半径（体素）：ceil(r/spacing)。
std::array<int, 3> ellipsoid_radii(double radius_mm, const Spacing& sp);

// NPY(uint8, C 序)
void write_npy_u8(const std::string& path, const Mask& m);
Mask read_npy_u8(const std::string& path);

}  // namespace ctf
