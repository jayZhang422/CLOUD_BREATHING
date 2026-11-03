// 表面生成与平滑。对应 Python lobe_surface.write_joint_lobes / reference.write_stl / surface.smooth_surface。
// 未移植：vessel_surface.refine_stl（骨架化 + 厚度自适应），血管只做通用平滑。
#pragma once
#include <chrono>

#include "mesh/mesh_io.hpp"
#include "mesh/volume3d.hpp"

namespace ctf {

// 分步计时：lap(name) 把自上次 lap 以来的墙钟秒数累加到 out[name]（同名步骤多次出现时累加）。
struct StepTimer {
  using clock = std::chrono::steady_clock;
  json out = json::object();
  clock::time_point t = clock::now();
  void lap(const char* name) {
    const clock::time_point now = clock::now();
    out[name] = out.value(name, 0.0) + std::chrono::duration<double>(now - t).count();
    t = now;
  }
};

struct Affine {
  double m[3][4];  // [z,y,x] 体素下标 → LPS 毫米
  Spacing spacing() const;
  double det_zyx_reversed() const;  // det(A[:3,:3][:, ::-1])
};
Affine affine_from_json(const json& j);

// 五肺叶联合表面：共享顶点的离散行进立方体，Sinc 平滑（iterations=0 则只提面），位移钳制，逐叶写 STL。
json write_joint_lobes(const std::vector<Mask>& lobes, const Affine& A, const std::string& dir, int iterations,
                       double maximum_move_mm = 2.5, json* timing = nullptr);

// 单结构：signed_distance=true 时先做有符号距离场再高斯（亚体素平滑，原体素中心保持在内部）；可选高斯场（sigma_mm>0）+ 行进立方体 + Taubin，写 STL，返回统计。
json write_mask_stl(const Mask& mask, const Affine& A, const std::string& path, int taubin_iterations,
                    double sigma_mm, bool preserve_voxels, bool preserve_volume, bool signed_distance = false,
                    double sigma_z_mm = 0.0, bool skeleton_clamp = false, bool match_volume = false,
                    double min_level = -1e9);
// sigma_z_mm>0：z 向独立 sigma；skeleton_clamp：只保护 3D 骨架邻域；match_volume：按原掩膜体素数选等值面。

// 表面清理 + Windowed Sinc（不减面）。保存后拓扑变化则回退到未平滑的源表面。
json smooth_surface(const std::string& input, const std::string& output, bool largest_surface,
                    double minimum_surface_volume_mm3, int iterations, double passband);

}  // namespace ctf
