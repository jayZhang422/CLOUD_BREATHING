#include "ct/vol2.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>

namespace ctf {

json View::to_json(bool with_offset) const {
  json j = json::object();
  j["name"] = name;
  j["direction"] = direction;
  j["base"] = base;
  j["planes"] = planes;
  j["width"] = width;
  j["height"] = height;
  j["row_stride"] = row_stride;
  j["plane_stride"] = plane_stride;
  j["bytes"] = bytes;
  if (!source.empty()) {
    j["source"] = source;
    j["orientation"] = orientation;
  }
  if (with_offset) j["file_offset"] = file_offset;
  return j;
}

void q16_coordinates(int old_n, int new_n, std::vector<int>& low, std::vector<int>& frac) {
  const int64_t denom = std::max(new_n - 1, 1);
  low.resize(new_n);
  frac.resize(new_n);
  for (int i = 0; i < new_n; ++i) {
    int64_t num = (int64_t)i * (old_n - 1) * 65536;
    int64_t q = num / denom, r = num % denom;
    if (r * 2 > denom || (r * 2 == denom && (q & 1))) q += 1;
    low[i] = (int)(q >> 16);
    frac[i] = (int)(q & 65535);
  }
}

namespace {

struct Axes { std::vector<int> nx, ny; std::vector<uint8_t> vx, vy; };

Axes hardware_axes(int orientation, int grid_w, int grid_h) {
  if (orientation != 1 && orientation != 2) throw Error("only orientation 1 and 2 can be derived");
  Axes a;
  a.nx.resize(512); a.ny.resize(512); a.vx.resize(512); a.vy.resize(512);
  for (int i = 0; i < 512; ++i) {
    int along = orientation == 2 ? 511 - i : i;
    a.nx[i] = along - ((512 - grid_w) >> 1);
    a.ny[i] = along - ((512 - grid_h) >> 1);
    a.vx[i] = a.nx[i] >= 0 && a.nx[i] < grid_w;
    a.vy[i] = a.ny[i] >= 0 && a.ny[i] < grid_h;
  }
  return a;
}

void fit_grid(const std::vector<uint8_t>& valid, int& size, int& pad) {
  int low = -1, high = -1;
  for (int i = 0; i < (int)valid.size(); ++i)
    if (valid[i]) { if (low < 0) low = i; high = i; }
  if (low < 0) throw Error("derived view has no valid positions");
  for (int s = high - low + 1; s <= 512; ++s) {
    int p = (512 - s) >> 1;
    if (p <= low && p + s - 1 >= high) { size = s; pad = p; return; }
  }
  throw Error("derived view does not fit a 512x512 output");
}

}  // namespace

Geometry derive_geometry(int orientation, int grid_w, int grid_h) {
  Axes a = hardware_axes(orientation, grid_w, grid_h);
  int new_height, pad_y, new_width, pad_x;
  fit_grid(a.vx, new_height, pad_y);
  fit_grid(a.vy, new_width, pad_x);
  Geometry g;
  g.width = new_width;
  g.height = new_height;
  for (int i = 0; i < new_height; ++i) { g.row_source.push_back(a.nx[pad_y + i]); g.row_valid.push_back(a.vx[pad_y + i]); }
  for (int i = 0; i < new_width; ++i) { g.col_source.push_back(a.ny[pad_x + i]); g.col_valid.push_back(a.vy[pad_x + i]); }
  return g;
}

std::vector<uint8_t> derive_plane(const int8_t* plane, int sx, const Geometry& g, size_t row_stride) {
  std::vector<uint8_t> out((size_t)g.height * row_stride, PAD_BYTE);
  for (int r = 0; r < g.height; ++r) {
    if (!g.row_valid[r]) continue;
    uint8_t* dst = &out[(size_t)r * row_stride];
    for (int c = 0; c < g.width; ++c) {
      if (!g.col_valid[c]) continue;
      dst[c] = (uint8_t)plane[(size_t)g.col_source[c] * sx + g.row_source[r]];
    }
  }
  return out;
}

namespace {

// 单个重采样平面；等价于 _resample_plane（整数可分离展开，结果与逐项求和相同）。
void resample_plane(const int8_t* vol, int depth, int zlow, int zf, const std::vector<int>& yi,
                    const std::vector<int>& yf, const std::vector<int>& xi, const std::vector<int>& xf,
                    int8_t* out) {
  const int H = (int)yi.size(), W = (int)xi.size();
  for (int y = 0; y < H; ++y) {
    for (int x = 0; x < W; ++x) {
      int64_t total = 0;
      for (int iz = 0; iz < 2; ++iz) {
        const int sz = std::min(zlow + iz, depth - 1);
        const int64_t wz = iz == 0 ? 65536 - zf : zf;
        for (int iy = 0; iy < 2; ++iy) {
          const int sy = std::min(yi[y] + iy, 511);
          const int64_t wy = iy == 0 ? 65536 - yf[y] : yf[y];
          const int8_t* row = vol + ((size_t)sz * 512 + sy) * 512;
          int64_t inner = 0;
          for (int ix = 0; ix < 2; ++ix) {
            const int sx = std::min(xi[x] + ix, 511);
            const int64_t wx = ix == 0 ? 65536 - xf[x] : xf[x];
            inner += (int64_t)row[sx] * wx;
          }
          total += inner * wz * wy;
        }
      }
      const int64_t mag = total < 0 ? -total : total;
      int64_t whole = mag >> 48, rem = mag & ((1ll << 48) - 1);
      const int64_t half = 1ll << 47;
      if (rem > half || (rem == half && (whole & 1))) whole += 1;
      int64_t v = total < 0 ? -whole : whole;
      v = std::max<int64_t>(-128, std::min<int64_t>(127, v));
      out[(size_t)y * W + x] = (int8_t)v;
    }
  }
}

bool overlap(const View& a, const View& b) { return a.base < b.base + b.bytes && b.base < a.base + a.bytes; }

// 结果区之后的放置：先用 skip 区之前的窗口，再用扩展区；任何视图都不能落入 0x1E000000..0x20000000。
bool place_after_result(uint64_t cursor, uint64_t size, uint64_t& base, uint64_t& next) {
  cursor = align_up(cursor);
  if (cursor + size <= DERIVED_DDR_LIMIT) { base = cursor; next = align_up(cursor + size); return true; }
  const uint64_t start = std::max(cursor, EXT_BASE);
  if (start + size <= VIEW_TOP) { base = start; next = align_up(start + size); return true; }
  return false;
}

}  // namespace

ViewPlan plan_views(int depth, int z_depth, int width, int height, uint64_t result_bytes, int direction,
                    bool transpose) {
  const uint64_t native_stride = 512, native_plane = 512ull * 512;
  const uint64_t lobe_stride = align_up(width), lobe_plane = align_up(lobe_stride * height);
  const uint64_t native_bytes = (uint64_t)depth * native_plane, lobe_bytes = (uint64_t)z_depth * lobe_plane;
  const uint64_t native_base = IMAGE_BASE;
  const uint64_t result_end = RESULT_BASE + result_bytes;
  if (native_base + native_bytes > DDR_INPUT_LIMIT)
    throw Error("VOL2 compact views and result allocation exceed protected DDR regions");
  uint64_t lobe_base = align_up(native_base + native_bytes);
  uint64_t high_cursor = align_up(result_end), low_cursor;
  if (lobe_base + lobe_bytes > DDR_INPUT_LIMIT) {
    uint64_t next;
    if (!place_after_result(result_end, lobe_bytes, lobe_base, next))
      throw Error("VOL2 compact views and result allocation exceed protected DDR regions");
    high_cursor = next;
    low_cursor = align_up(native_base + native_bytes);
  } else {
    low_cursor = align_up(lobe_base + lobe_bytes);
  }

  ViewPlan plan;
  auto fill = [](View& v, const char* name, int dir, uint64_t base, int planes, int w, int h, uint64_t rs, uint64_t ps,
                 uint64_t bytes) {
    v.name = name; v.direction = dir; v.base = base; v.planes = planes; v.width = w; v.height = h;
    v.row_stride = rs; v.plane_stride = ps; v.bytes = bytes;
  };
  plan.views.resize(2);
  fill(plan.views[0], "native", direction, native_base, depth, 512, 512, native_stride, native_plane, native_bytes);
  fill(plan.views[1], "lobe", direction, lobe_base, z_depth, width, height, lobe_stride, lobe_plane, lobe_bytes);

  if (transpose) {
    struct Spec { const char* name; int src; int orientation; };
    for (Spec sp : {Spec{"lobe_t", 1, 2}, Spec{"native_t", 0, 1}}) {
      const View sv = plan.views[sp.src];
      Geometry geo = derive_geometry(sp.orientation, sv.width, sv.height);
      const uint64_t stride = align_up(geo.width), plane_stride = align_up(stride * geo.height);
      const uint64_t size = (uint64_t)sv.planes * plane_stride;
      uint64_t base;
      if (low_cursor + size <= DDR_INPUT_LIMIT) {
        base = low_cursor;
        low_cursor = align_up(low_cursor + size);
      } else {
        uint64_t next;
        if (!place_after_result(high_cursor, size, base, next)) { plan.dropped.push_back(sp.name); continue; }
        high_cursor = next;
      }
      View v;
      v.name = sp.name; v.direction = sv.direction; v.base = base; v.planes = sv.planes;
      v.width = geo.width; v.height = geo.height; v.row_stride = stride; v.plane_stride = plane_stride;
      v.bytes = size; v.source = sv.name; v.orientation = sp.orientation;
      plan.views.push_back(v);
      plan.geos.push_back({sp.name, {geo, stride, plane_stride}});
    }
  }
  for (size_t i = 0; i < plan.views.size(); ++i)
    for (size_t j = i + 1; j < plan.views.size(); ++j)
      if (overlap(plan.views[i], plan.views[j])) throw Error("VOL2 view DDR ranges overlap");
  return plan;
}

json prepare_vol2(const std::string& case_dir, const json& input, const json& metadata, bool transpose,
                  const Progress& progress) {
  const std::string source = join(case_dir, input["file"].get<std::string>());
  const uint64_t src_bytes = input["bytes"].get<uint64_t>();
  const std::string src_sha = input["sha256"].get<std::string>();
  const std::string out = join(case_dir, "input/ct_volume_vol2.bin");
  const std::string sidecar = join(case_dir, "input/ct_volume_vol2.json");

  if (file_exists(sidecar)) {
    json cached = read_json(sidecar);
    if (cached.value("source_sha256", "") == src_sha) {
      const json& cb = cached["compact_bin"];
      if (cb.value("layout_version", -1) == LAYOUT_VERSION && cb.value("transposed", !transpose) == transpose) {
        check_file(out, cb["bytes"].get<uint64_t>(), cb["sha256"].get<std::string>());
        progress("复用已校验 VOL2");
        return cb;
      }
    }
  }
  check_file(source, src_bytes, src_sha);

  const int depth = input["shape"][0].get<int>();
  // 间距 = 仿射前三列各自的 2-范数。
  double sp[3];
  for (int c = 0; c < 3; ++c) {
    double s = 0;
    for (int r = 0; r < 3; ++r) { double v = metadata["affine_z_y_x_to_lps_mm"][r][c].get<double>(); s += v * v; }
    sp[c] = std::sqrt(s);
  }
  const int dims[3] = {depth, 512, 512};
  int g[3];
  for (int k = 0; k < 3; ++k) g[k] = std::max(2, (int)std::nearbyint(((double)(dims[k] - 1) * sp[k]) / 1.5) + 1);
  const int z_depth = g[0], height = g[1], width = g[2];
  if (std::max(height, width) > 512 || z_depth > 480) throw Error("VOL2 lobe grid exceeds FPGA bounds");

  const int zdir = metadata["anatomical_z_direction"].get<int>() < 0 ? 4 : 0;
  ViewPlan plan = plan_views(depth, z_depth, width, height, src_bytes * 2, zdir, transpose);
  std::vector<View>& views = plan.views;
  const auto& geos = plan.geos;
  const uint64_t native_plane = views[0].plane_stride;
  if (!plan.dropped.empty()) {
    std::string names;
    for (auto& n : plan.dropped) names += (names.empty() ? std::string() : std::string(",")) + n;
    std::fprintf(stderr, "警告: VOL2 派生视图 %s 在 DDR 视图窗口中放不下，已退回原朝向 gather；推理将明显变慢。\n",
                 names.c_str());
  }

  // 文件布局：16B 头 + 40B/视图表；各视图 32B 对齐。
  const uint64_t header_bytes = 16 + views.size() * 40;
  uint64_t pos = header_bytes;
  for (auto& v : views) { pos = align_up(pos); v.file_offset = pos; pos += v.bytes; }

  progress("读取原生 INT8 BIN");
  std::vector<uint8_t> src = read_file(source);
  const int8_t* vol = reinterpret_cast<const int8_t*>(src.data());

  progress(fmt("重采样肺叶网格 %dx%dx%d", z_depth, height, width));
  std::vector<int> zq, zf, yq, yf, xq, xf;
  q16_coordinates(depth, z_depth, zq, zf);
  q16_coordinates(512, height, yq, yf);
  q16_coordinates(512, width, xq, xf);
  for (auto& v : zq) v = std::min(v, depth - 1);
  for (auto& v : yq) v = std::min(v, 511);
  for (auto& v : xq) v = std::min(v, 511);
  std::vector<int8_t> lobe((size_t)z_depth * height * width);
#pragma omp parallel for schedule(static)
  for (int z = 0; z < z_depth; ++z)
    resample_plane(vol, depth, zq[z], zf[z], yq, yf, xq, xf, lobe.data() + (size_t)z * height * width);

  HashedWriter w(out);
  std::vector<uint8_t> head(header_bytes, 0);
  std::memcpy(head.data(), "VOL2", 4);
  put_le16(&head[4], 2);
  put_le16(&head[6], (uint32_t)views.size());
  put_le32(&head[8], (uint32_t)depth);
  put_le32(&head[12], (uint32_t)header_bytes);
  for (size_t i = 0; i < views.size(); ++i) {
    uint8_t* e = &head[16 + i * 40];
    const View& v = views[i];
    std::memcpy(e, v.name.data(), std::min<size_t>(8, v.name.size()));
    e[8] = (uint8_t)v.direction;
    e[9] = 1;
    put_le16(e + 10, 0);
    put_le32(e + 12, (uint32_t)v.file_offset);
    put_le32(e + 16, (uint32_t)v.base);
    put_le32(e + 20, (uint32_t)v.planes);
    put_le32(e + 24, (uint32_t)v.bytes);
    put_le16(e + 28, (uint32_t)v.width);
    put_le16(e + 30, (uint32_t)v.height);
    put_le32(e + 32, (uint32_t)v.row_stride);
    put_le32(e + 36, (uint32_t)v.plane_stride);
  }
  w.write(head.data(), head.size());

  auto pad_to = [&](uint64_t off) { w.zeros(off - w.position()); };
  auto find_geo = [&](const std::string& n) -> const Derived* {
    for (auto& p : geos) if (p.first == n) return &p.second;
    return nullptr;
  };

  for (const View& v : views) {
    pad_to(v.file_offset);
    progress("写入 VOL2 视图 " + v.name);
    if (v.name == "native") {
      w.write(src.data(), v.bytes);
    } else if (v.name == "lobe") {
      std::vector<uint8_t> plane(v.plane_stride);
      for (int z = 0; z < v.planes; ++z) {
        std::fill(plane.begin(), plane.end(), 0);
        for (int r = 0; r < height; ++r)
          std::memcpy(&plane[(size_t)r * v.row_stride], &lobe[((size_t)z * height + r) * width], width);
        w.write(plane.data(), plane.size());
      }
    } else {
      const Derived* d = find_geo(v.name);
      const bool from_lobe = v.source == "lobe";
      for (int z = 0; z < v.planes; ++z) {
        const int8_t* pl = from_lobe ? reinterpret_cast<const int8_t*>(&lobe[(size_t)z * height * width])
                                     : vol + (size_t)z * native_plane;
        auto buf = derive_plane(pl, from_lobe ? width : 512, d->geo, d->stride);
        w.write(buf.data(), buf.size());
        w.zeros(d->plane_stride - d->stride * d->geo.height);
      }
    }
  }
  const uint64_t total = w.position();
  const std::string sha = w.finish_hex();

  json compact = json::object();
  compact["file"] = "input/ct_volume_vol2.bin";
  compact["bytes"] = total;
  compact["sha256"] = sha;
  compact["header_bytes"] = header_bytes;
  json jv = json::array();
  for (auto& v : views) jv.push_back(v.to_json(true));
  compact["views"] = jv;
  compact["layout_version"] = LAYOUT_VERSION;
  compact["transposed"] = transpose;
  compact["lobe_resampling"] = "align-corners Q16/RNE, one final signed RNE, INT8 saturation";
  json side = json::object();
  side["source_sha256"] = src_sha;
  side["compact_bin"] = compact;
  write_json(sidecar, side);
  return compact;
}

}  // namespace ctf
