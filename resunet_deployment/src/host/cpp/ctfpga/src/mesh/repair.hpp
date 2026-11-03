// 掩膜修补：对应 Python repair.py / branch_repair.py / lobe_surface.repair_lobe_envelope。
// 未移植：reference_support 相关分支（默认流程不使用）；MCP_Geometric 以 6 邻域 Dijkstra 替代（路径等长但并列时可能不同）。
#pragma once
#include "mesh/morph.hpp"

namespace ctf {

// CT 的 INT8 量化体及反量化表。HU = ((q+128)*2024/255) - 1024，逐步 float32，与 numpy 一致。
struct CtData {
  Dims d;
  std::vector<int8_t> q;
  float lut[256];
  void init_lut();
  float hu(size_t i) const { return lut[(int)q[i] + 128]; }
};

Mask build_body(const CtData& ct);  // 逐层 HU>-200 的最大 8 连通块并填洞

struct Prepared {
  std::vector<Mask> masks;    // 九结构修补后掩膜
  std::vector<json> repairs;  // 各结构修补说明
  json details;               // joint_lobe_repair 等
};

// raw 为模型预测的九结构原始掩膜；会被修改（供静脉/动脉互相排除用的是原始副本）。
Prepared prepare_masks(const std::vector<Mask>& raw, const Mask& body, const CtData& ct, const Spacing& sp,
                       const std::string& out_dir, const Progress& progress, double far_bridge_mm = 0.0);

}  // namespace ctf
