// 网格三阶段：BIN→STL（修补+提面）、Smooth、Cut（减面）。每阶段只通过文件与 manifest.json 交接。
#pragma once
#include "common/util.hpp"

namespace ctf {

struct MeshOpts {
  std::string ct_metadata;   // 默认 <case>/input/metadata.json
  int iterations = 15;       // 非肺叶最终 Sinc 轮数
  double passband = 0.08;
  int max_faces = 150000;
  double volume_limit = 0.05;
  int threads = 0;           // 0 = 自动
  double far_bridge_mm = 16.0;     // 静脉碎片远距离桥接上限（mm），0 = 关闭
  double vessel_sigma_mm = 1.0;    // 动/静脉：距离场高斯 sigma（mm）
  double vessel_sigma_z_mm = 1.5;  // 动/静脉：z 向 sigma（层间半径跳变更大）
  bool vessel_skeleton = true;     // 骨架钳制代替逐体素钳制（去环状纹）
  bool vessel_match_volume = true; // 按原体素数选等值面
  double vessel_min_level_mm = -0.12;  // 等值面水平下限（mm，负值=外扩）
  double airway_sigma_mm = 0.7;    // 气管：距离场 xy sigma
  double airway_sigma_z_mm = 1.1;  // 气管：z 向 sigma
  double tumor_sigma_mm = 1.0;     // 肿瘤：高斯 sigma（原 2.0）
  int tumor_taubin = 5;            // 肿瘤：Taubin 轮数（原 10）
  int vessel_taubin = 10;
  int vessel_iterations = 30;      // 动/静脉最终 Sinc 轮数
  double vessel_passband = 0.05;
  int tumor_faces = 2000;          // 肿瘤目标面数，0 = 不减
  // Cut 阶段分器官目标面数（>0 时覆盖 max_faces；0 = 回退到 max_faces）
  int cut_lobe_faces = 0;
  int cut_airway_faces = 0;
  int cut_artery_faces = 0;
  int cut_vein_faces = 0;
  int cut_tumor_faces = 0;
  int cut_smooth = 0;  // 减面后 Taubin 轮数（磨去棱角），0 = 不平滑
};

json bin_to_stl(const std::string& prediction_dir, const std::string& out_dir, const MeshOpts& o, const Progress& p);
json smooth_meshes(const std::string& src_dir, const std::string& out_dir, const MeshOpts& o, const Progress& p);
json cut_meshes(const std::string& src_dir, const std::string& out_dir, const MeshOpts& o, const Progress& p);

}  // namespace ctf
