// DICOM CT 序列读取 + HU→INT8 量化。语义对齐 Python 的 dicom_ct.py / convert.py。
#pragma once
#include <cmath>
#include "common/util.hpp"

namespace ctf {

// HU → signed INT8：rint((clip(HU,-1024,1000)+1024)*255/2024)-128，全程 float32，最近偶数舍入。
inline int8_t quantize_hu(float hu) {
  float c = std::fmin(std::fmax(hu, -1024.f), 1000.f);
  float v = (c + 1024.f) * 255.f / 2024.f;
  return static_cast<int8_t>(static_cast<int>(std::nearbyintf(v)) - 128);
}

struct CtVolume {
  int depth = 0, rows = 0, cols = 0;
  std::vector<int8_t> q;  // [depth][rows][cols]，已按物理层序排好
  json metadata;          // 与 Python load_ct_series 返回的 metadata 同构
};

// data: DICOM 目录或 .zip。series_uid 为空时要求只有一个 CT 序列。
CtVolume load_ct_quantized(const std::string& data, const std::string& series_uid, const Progress& progress);

}  // namespace ctf
