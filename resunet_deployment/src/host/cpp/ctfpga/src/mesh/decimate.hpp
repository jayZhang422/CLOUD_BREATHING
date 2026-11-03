// 保持闭合二维流形的 QEM 边折叠减面（link condition + 法向翻转检查）。
// VTK 的 vtkQuadricDecimation 在大比例减面时会产生非流形边并拆出碎片，故自行实现。
#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>

namespace ctf {

// pts: N×3，tris: M×3（朝向一致的闭合流形）。原地减面到不超过 target_faces（折叠受拓扑/翻转检查限制，可能停在更高处）。
// 返回最终面数。min_normal_cos：折叠后相邻面法向与原法向的最小余弦。
size_t qem_decimate(std::vector<double>& pts, std::vector<int64_t>& tris, size_t target_faces, double min_normal_cos = 0.2);

}  // namespace ctf
