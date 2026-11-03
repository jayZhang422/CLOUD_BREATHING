// 形态学与距离：精确 EDT（可带最近特征点索引）、椭球膨胀/腐蚀/闭运算、填洞、高斯滤波。
// 语义对齐 scipy.ndimage：椭球结构元素 ⇔ 物理距离 ≤ r 的格点；border_value=0。
#pragma once
#include "mesh/volume3d.hpp"

namespace ctf {

constexpr float EDT_INF = 1e30f;

struct Edt {
  Vol<float> d2;         // 到最近零体素的平方物理距离；非零体素之外为 0；无零体素时为 EDT_INF
  Vol<int32_t> nearest;  // 最近零体素的线性下标（want_index 时有效）
};
// 约定与 scipy.ndimage.distance_transform_edt 相同：对 m 中非零体素计算到最近"零"体素的距离。
Edt edt(const Mask& m, const Spacing& sp, bool want_index);

// 椭球结构元素（物理半径 r_mm）。输入输出同尺寸；内部按包围盒+边距裁剪，边界外视为 0。
Mask dilate_ellipsoid(const Mask& m, double r_mm, const Spacing& sp);
Mask erode_ellipsoid(const Mask& m, double r_mm, const Spacing& sp);
Mask close_ellipsoid(const Mask& m, double r_mm, const Spacing& sp);

Mask erode6(const Mask& m);                 // 6 邻域十字结构，border_value=0
Mask fill_holes_3d(const Mask& m);          // 与 binary_fill_holes 相同（6 邻域背景泛洪）
void fill_holes_2d_slices(Mask& m);         // 逐 z 切片的 2D 填洞（4 邻域）

// 高斯滤波：每轴 sigma（体素单位，<=1e-15 的轴跳过），truncate=4。
enum class Border { Reflect, Constant };
void gaussian_filter(Vol<float>& f, const std::array<double, 3>& sigma, Border mode);

}  // namespace ctf
