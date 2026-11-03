// VOL2 紧凑视图：原生平面 + 1.5mm 肺叶重采样平面 + 朝向等价的预转置派生视图。
// 整数算术与 Python 版 vol2.py 逐项对应（Q16 坐标、最近偶数舍入、INT8 饱和）。
#pragma once
#include "common/util.hpp"

namespace ctf {

constexpr uint64_t IMAGE_BASE = 0x00400000ull;
constexpr uint64_t SCRIPT_BASE = 0x08200000ull;
constexpr uint64_t MAP_BASE = 0x08800000ull;
constexpr uint64_t RESULT_BASE = 0x10000000ull;
constexpr uint64_t DDR_LIMIT_RESULT = 0x1FFF0000ull;
constexpr uint64_t DDR_INPUT_LIMIT = 0x08000000ull;
// 0x1E000000..0x20000000 是固定 decoder 阶段的 skip 兼容区，任何视图都不得落入。
constexpr uint64_t DERIVED_DDR_LIMIT = 0x1E000000ull;
// 扩展区：RTL kind-4 视图上限（op_volume_service.VIEW_TOP）。334 层整卷结果区之后只剩约 57 MiB，
// 放不下 native_t（约 84 MiB），所以允许把视图放到 0x20000000 之后。
constexpr uint64_t EXT_BASE = 0x20000000ull;
constexpr uint64_t DDR_LIMIT = 0x30000000ull;
constexpr uint64_t VIEW_TOP = DDR_LIMIT;
// v4：增加扩展区放置并禁止落入 skip 区；v3 缓存可能缺少 native_t，必须重新生成。
constexpr int LAYOUT_VERSION = 4;
constexpr uint8_t PAD_BYTE = 0x80;

struct View {
  std::string name;
  int direction = 0;
  uint64_t base = 0;
  int planes = 0, width = 0, height = 0;
  uint64_t row_stride = 0, plane_stride = 0, bytes = 0;
  std::string source;      // 派生视图的源视图名
  int orientation = -1;    // 派生视图等价的 gather 朝向；-1 表示非派生
  uint64_t file_offset = 0;
  json to_json(bool with_offset) const;
};

struct Geometry {
  int width = 0, height = 0;
  std::vector<int> row_source, col_source;
  std::vector<uint8_t> row_valid, col_valid;
};

// 复现 op_volume_transform 的坐标变换。
Geometry derive_geometry(int orientation, int grid_w, int grid_h);
// plane 为 [native_y][native_x] 的 INT8（行步长 plane_stride_x），输出 height × row_stride。
std::vector<uint8_t> derive_plane(const int8_t* plane, int plane_stride_x, const Geometry& g, size_t row_stride);

// 计算 (z, y, x) 重采样的 Q16 坐标：返回 {low, frac}
void q16_coordinates(int old_n, int new_n, std::vector<int>& low, std::vector<int>& frac);

// 规划各视图的 DDR 位置（纯函数）：低区 → 结果区之后、skip 区之前 → 扩展区。
// 返回 views（派生视图的 file_offset 未填）、geos（派生视图名 → 几何）与被放弃的派生视图名。
struct Derived {
  Geometry geo;
  uint64_t stride = 0, plane_stride = 0;
};
struct ViewPlan {
  std::vector<View> views;
  std::vector<std::pair<std::string, Derived>> geos;
  std::vector<std::string> dropped;
};
ViewPlan plan_views(int depth, int z_depth, int width, int height, uint64_t result_bytes, int direction,
                    bool transpose);

// 生成/复用 VOL2 文件。input: {file, bytes, sha256, shape}；返回 compact_bin JSON（含 views）。
json prepare_vol2(const std::string& case_dir, const json& input, const json& metadata, bool transpose,
                  const Progress& progress);

}  // namespace ctf
