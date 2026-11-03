// VTK 网格辅助：STL 读写、质量检查、小碎片过滤、Taubin 平滑。语义对应 Python reference.py。
#pragma once
#include <vtkSmartPointer.h>
#include <vtkPolyData.h>

#include "common/util.hpp"

namespace ctf {

using Poly = vtkSmartPointer<vtkPolyData>;

struct Quality {
  int64_t triangles = 0, vertices = 0, components = 0, boundary_edges = 0, nonmanifold_edges = 0;
  double volume_mm3 = 0;
  double bounds[6] = {0, 0, 0, 0, 0, 0};
  int64_t boundary_nonmanifold() const { return boundary_edges + nonmanifold_edges; }
  json to_json() const;
};

Poly read_stl(const std::string& path);                        // 无三角面则抛错
void write_stl_binary(vtkPolyData* mesh, const std::string& path);
Quality mesh_quality(vtkPolyData* mesh);

// 以点连通性分区；体积小于 minimum_mm3 的壳被移除（最大壳始终保留）。返回过滤后的网格。
Poly remove_small_surfaces(vtkPolyData* mesh, double minimum_mm3, json* info);

// 顶点数组（N×3，double）与三角面（M×3，int64）互转。
void poly_to_arrays(vtkPolyData* mesh, std::vector<double>& pts, std::vector<int64_t>& tris);
Poly arrays_to_poly(const std::vector<double>& pts, const std::vector<int64_t>& tris);

// Taubin λ|μ 平滑（0.5/-0.53），按边邻接平均；迭代 0 次直接返回。
void taubin_smooth(std::vector<double>& pts, const std::vector<int64_t>& tris, int iterations);

// 直接以 float32 写二进制 STL（三角面朝向由有符号体积决定为外向）。tris 可能被翻转。
// 返回 {triangles, vertices, volume_mm3, bounds}。
json write_stl_arrays(const std::string& path, const std::vector<double>& pts, std::vector<int64_t>& tris);

}  // namespace ctf
