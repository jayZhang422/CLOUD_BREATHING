#include "mesh/repair.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <queue>

namespace ctf {

void CtData::init_lut() {
  for (int q = -128; q <= 127; ++q) {
    float t = (float)q + 128.0f;
    t = t * 2024.0f;
    t = t / 255.0f;
    lut[q + 128] = t - 1024.0f;
  }
}

Mask build_body(const CtData& ct) {
  Mask body(ct.d, 0);
#pragma omp parallel for schedule(dynamic)
  for (int z = 0; z < ct.d.z; ++z) {
    Mask fg(Dims{1, ct.d.y, ct.d.x}, 0);
    const size_t base = (size_t)z * ct.d.y * ct.d.x;
    for (size_t i = 0; i < fg.v.size(); ++i) fg.v[i] = ct.hu(base + i) > -200.0f ? 1 : 0;
    Vol<int32_t> lab;
    const int n = label(fg, 2, lab);  // 单层上 18 邻域等价于 8 邻域
    if (!n) continue;
    std::vector<int64_t> cnt(n + 1, 0);
    for (int32_t l : lab.v) ++cnt[l];
    int best = 1;
    for (int l = 2; l <= n; ++l) if (cnt[l] > cnt[best]) best = l;
    Mask sel(fg.d, 0);
    for (size_t i = 0; i < sel.v.size(); ++i) sel.v[i] = lab.v[i] == best ? 1 : 0;
    fill_holes_2d_slices(sel);
    std::memcpy(&body.v[base], sel.v.data(), sel.v.size());
  }
  return body;
}

namespace {

template <class Pred>
Mask make_mask(const CtData& ct, Pred pred) {
  Mask m(ct.d, 0);
#pragma omp parallel for
  for (long i = 0; i < (long)m.v.size(); ++i) m.v[i] = pred(ct.hu(i)) ? 1 : 0;
  return m;
}

Mask remove_small(const Mask& m, int64_t minimum) {
  Mask out(m.d, 0);
  Box b = bbox(m);
  if (b.empty()) return out;
  Mask c = crop(m, b);
  Vol<int32_t> lab;
  const int n = label(c, 3, lab);
  std::vector<int64_t> cnt(n + 1, 0);
  for (int32_t l : lab.v) ++cnt[l];
  Mask r(c.d, 0);
  for (size_t i = 0; i < r.v.size(); ++i) r.v[i] = (lab.v[i] && cnt[lab.v[i]] >= minimum) ? 1 : 0;
  paste(out, r, b);
  return out;
}

Mask keep_largest(const Mask& m) {
  Box b = bbox(m);
  if (b.empty()) return m;
  Mask c = crop(m, b);
  Vol<int32_t> lab;
  const int n = label(c, 2, lab);
  if (n <= 1) return m;
  std::vector<int64_t> cnt(n + 1, 0);
  for (int32_t l : lab.v) ++cnt[l];
  int best = 1;
  for (int l = 2; l <= n; ++l) if (cnt[l] > cnt[best]) best = l;
  Mask r(c.d, 0);
  for (size_t i = 0; i < r.v.size(); ++i) r.v[i] = lab.v[i] == best ? 1 : 0;
  Mask out(m.d, 0);
  paste(out, r, b);
  return out;
}

Mask label_eq(const Vol<int32_t>& lab, int id, const Box& b) {
  Mask r(b.dims(), 0);
  for (int z = 0; z < r.d.z; ++z)
    for (int y = 0; y < r.d.y; ++y)
      for (int x = 0; x < r.d.x; ++x)
        r.at(z, y, x) = lab.at(b.lo[0] + z, b.lo[1] + y, b.lo[2] + x) == id ? 1 : 0;
  return r;
}

// numpy.linspace(point, endpoint, num) 逐元素复现，再 rint。
std::vector<std::array<int, 3>> line_samples(const std::array<int, 3>& a, const std::array<int, 3>& b) {
  int maxabs = 0;
  for (int k = 0; k < 3; ++k) maxabs = std::max(maxabs, std::abs(b[k] - a[k]));
  const int num = 1 + maxabs * 4;
  std::vector<std::array<int, 3>> out(num);
  const double div = num - 1;
  double delta[3], step[3];
  bool any_zero = false;
  for (int k = 0; k < 3; ++k) { delta[k] = (double)b[k] - a[k]; step[k] = delta[k] / div; if (step[k] == 0) any_zero = true; }
  for (int i = 0; i < num; ++i)
    for (int k = 0; k < 3; ++k) {
      double v = any_zero ? ((double)i / div) * delta[k] : (double)i * step[k];
      v += a[k];
      if (i == num - 1) v = b[k];
      out[i][k] = (int)std::nearbyint(v);
    }
  return out;
}

Mask path_mask(const Dims& d, const std::array<int, 3>& point, const std::vector<std::array<int, 3>>& samples,
               const Spacing& sp) {
  Mask path(d, 0);
  std::array<int, 3> cur = point;
  path.at(cur[0], cur[1], cur[2]) = 1;
  for (size_t s = 1; s < samples.size(); ++s) {
    const auto& nx = samples[s];
    std::array<int, 3> ax = {0, 1, 2};
    double key[3];
    for (int k = 0; k < 3; ++k) key[k] = -std::abs(nx[k] - cur[k]) * sp[k];
    std::stable_sort(ax.begin(), ax.end(), [&](int p, int q) { return key[p] < key[q]; });
    for (int a : ax)
      while (cur[a] != nx[a]) {
        cur[a] += nx[a] > cur[a] ? 1 : -1;
        path.at(cur[0], cur[1], cur[2]) = 1;
      }
  }
  return path;
}

// 小片段就近桥接：只经由 allowed 体素。返回新掩膜与桥接数。
Mask connect_nearby(const Mask& mask, const Mask& allowed, const Spacing& sp, double max_mm, int& connected) {
  connected = 0;
  Box bb = bbox(mask);
  if (bb.empty()) return mask;
  std::array<int, 3> pad;
  for (int k = 0; k < 3; ++k) pad[k] = (int)std::ceil(max_mm / sp[k]) + 1;
  Box cb = clip_box(expand_box(bb, pad), mask.d);
  Mask m = crop(mask, cb), al = crop(allowed, cb), result = m;
  Vol<int32_t> lab;
  const int n = label(m, 1, lab);
  std::vector<int64_t> counts;
  std::vector<Box> boxes;
  label_stats(lab, n, counts, boxes);
  // argsort(counts[1:])[::-1][1:]：按体素数降序（并列时后出现的标签在前），跳过最大者。
  std::vector<int> order(n);
  std::iota(order.begin(), order.end(), 1);
  std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return counts[a] < counts[b]; });
  std::reverse(order.begin(), order.end());
  const double lim2 = max_mm * max_mm * (1 + 1e-6);
  for (size_t oi = 1; oi < order.size(); ++oi) {
    const int idx = order[oi];
    Box region = clip_box(expand_box(boxes[idx], pad), m.d);
    Mask cand = label_eq(lab, idx, region);
    Mask res = crop(result, region);
    Mask target = logical_andnot(res, cand);
    if (!count(target)) continue;
    Mask inv(target.d, 0);
    for (size_t i = 0; i < inv.v.size(); ++i) inv.v[i] = target.v[i] ? 0 : 1;
    Edt e = edt(inv, sp, true);
    float best = EDT_INF;
    size_t bi = 0;
    for (size_t i = 0; i < cand.v.size(); ++i)
      if (cand.v[i] && e.d2.v[i] < best) { best = e.d2.v[i]; bi = i; }
    if (best >= EDT_INF || best > lim2) continue;
    auto unravel = [&](size_t i) { return std::array<int, 3>{(int)(i / ((size_t)cand.d.y * cand.d.x)), (int)((i / cand.d.x) % cand.d.y), (int)(i % cand.d.x)}; };
    const auto point = unravel(bi), endpoint = unravel((size_t)e.nearest.v[bi]);
    Mask path = path_mask(cand.d, point, line_samples(point, endpoint), sp);
    Mask al_r = crop(al, region);
    bool ok = true;
    for (size_t i = 0; i < path.v.size() && ok; ++i)
      if (path.v[i] && !res.v[i] && !al_r.v[i]) ok = false;
    if (!ok) continue;
    paste_or(result, path, region);
    ++connected;
  }
  Mask out = mask;
  paste(out, result, cb);
  return out;
}

// 6 邻域 Dijkstra：多源到最近终点，边权为轴向物理间距，仅经 support 体素。
bool geodesic_path(const Mask& support, const std::vector<std::array<int, 3>>& starts, const Mask& ends,
                   const Spacing& sp, std::vector<std::array<int, 3>>& path) {
  const Dims d = support.d;
  std::vector<float> dist(support.v.size(), 3e38f);
  std::vector<int64_t> parent(support.v.size(), -1);
  using Item = std::pair<float, size_t>;
  std::priority_queue<Item, std::vector<Item>, std::greater<Item>> pq;
  for (auto& s : starts) {
    const size_t i = support.idx(s[0], s[1], s[2]);
    if (!support.v[i]) continue;
    dist[i] = 0;
    pq.push({0.f, i});
  }
  const int dz[6] = {-1, 1, 0, 0, 0, 0}, dy[6] = {0, 0, -1, 1, 0, 0}, dx[6] = {0, 0, 0, 0, -1, 1};
  while (!pq.empty()) {
    const auto [dd, i] = pq.top();
    pq.pop();
    if (dd > dist[i]) continue;
    if (ends.v[i]) {
      std::vector<std::array<int, 3>> rev;
      for (int64_t c = (int64_t)i; c >= 0; c = parent[c])
        rev.push_back({(int)(c / ((size_t)d.y * d.x)), (int)((c / d.x) % d.y), (int)(c % d.x)});
      path.assign(rev.rbegin(), rev.rend());
      return true;
    }
    const int z = (int)(i / ((size_t)d.y * d.x)), y = (int)((i / d.x) % d.y), x = (int)(i % d.x);
    for (int k = 0; k < 6; ++k) {
      const int nz = z + dz[k], ny = y + dy[k], nx = x + dx[k];
      if (nz < 0 || ny < 0 || nx < 0 || nz >= d.z || ny >= d.y || nx >= d.x) continue;
      const size_t j = support.idx(nz, ny, nx);
      if (!support.v[j]) continue;
      const float w = (float)(k < 2 ? sp[0] : k < 4 ? sp[1] : sp[2]);
      if (dd + w < dist[j]) { dist[j] = dd + w; parent[j] = (int64_t)i; pq.push({dd + w, j}); }
    }
  }
  return false;
}

std::vector<std::array<int, 3>> boundary_points(const Mask& m) {
  Mask er = erode6(m);
  std::vector<std::array<int, 3>> pts;
  for (int z = 0; z < m.d.z; ++z)
    for (int y = 0; y < m.d.y; ++y)
      for (int x = 0; x < m.d.x; ++x)
        if (m.at(z, y, x) && !er.at(z, y, x)) pts.push_back({z, y, x});
  return pts;
}

struct BranchOut { Mask anchor, rejected; json info; };

BranchOut repair_branches(const Mask& mask, const Mask& allowed, const Spacing& sp, double maximum_mm,
                          double retain_min_mm3 /* <0: None */) {
  const bool retain = retain_min_mm3 >= 0;
  BranchOut out;
  json info = json::object();
  auto base_info = [&](int unresolved, int64_t withheld, int64_t retained_vox, int64_t added, int ret_comp, int64_t ret_vox,
                       int remaining) {
    json j = json::object();
    j["accepted_bridges"] = json::array();
    j["unresolved_components"] = unresolved;
    j["withheld_voxels"] = withheld;
    j["retained_prediction_voxels"] = retained_vox;
    j["added_bridge_voxels"] = added;
    j["retained_unconnected_components"] = ret_comp;
    j["retained_unconnected_voxels"] = ret_vox;
    j["remaining_face_connected_components"] = remaining;
    j["retain_unconnected_minimum_mm3"] = retain ? json(retain_min_mm3) : json(nullptr);
    j["maximum_bridge_distance_mm"] = maximum_mm;
    return j;
  };
  Box bb = bbox(mask);
  if (bb.empty()) {
    out.anchor = mask;
    out.rejected = Mask(mask.d, 0);
    out.info = base_info(0, 0, 0, 0, 0, 0, 0);
    return out;
  }
  std::array<int, 3> pad;
  for (int k = 0; k < 3; ++k) pad[k] = (int)std::ceil(maximum_mm / sp[k]) + 2;
  Box cb = clip_box(expand_box(bb, pad), mask.d);
  Mask m = crop(mask, cb), al = crop(allowed, cb);
  Vol<int32_t> lab;
  const int count_n = label(m, 1, lab);
  std::vector<int64_t> counts;
  std::vector<Box> boxes;
  label_stats(lab, count_n, counts, boxes);
  int main_id = 1;
  for (int l = 2; l <= count_n; ++l) if (counts[l] > counts[main_id]) main_id = l;
  Mask anchor = label_eq(lab, main_id, Box{{0, 0, 0}, {m.d.z, m.d.y, m.d.x}});
  std::vector<int> parents(count_n + 1);
  std::iota(parents.begin(), parents.end(), 0);
  const double vv = vox_volume(sp);
  std::vector<char> eligible(count_n + 1, 0);
  for (int l = 1; l <= count_n; ++l) eligible[l] = retain && counts[l] * vv >= retain_min_mm3;
  eligible[main_id] = 1;
  auto root = [&](int i) { while (parents[i] != i) { parents[i] = parents[parents[i]]; i = parents[i]; } return i; };
  std::vector<int> pending(count_n);
  std::iota(pending.begin(), pending.end(), 1);
  std::stable_sort(pending.begin(), pending.end(), [&](int a, int b) { return counts[a] < counts[b]; });
  std::reverse(pending.begin(), pending.end());
  pending.erase(std::remove(pending.begin(), pending.end(), main_id), pending.end());
  json bridges = json::array();
  const double radius = std::max(1.3, std::max({sp[0], sp[1], sp[2]}) + .05);
  const double r2 = radius * radius * (1 + 1e-6), gap_lim2 = maximum_mm * maximum_mm * (1 + 1e-6);
  for (int round = 0; round < 4; ++round) {
    bool progress = false;
    for (size_t pi = 0; pi < pending.size();) {
      const int index = pending[pi];
      Box region = clip_box(expand_box(boxes[index], pad), m.d);
      Mask cand = label_eq(lab, index, region);
      Mask target;
      if (retain) {
        std::vector<int> groups(count_n + 1);
        for (int i = 0; i <= count_n; ++i) groups[i] = root(i);
        target = Mask(region.dims(), 0);
        const int mine = root(index);
        for (int z = 0; z < target.d.z; ++z)
          for (int y = 0; y < target.d.y; ++y)
            for (int x = 0; x < target.d.x; ++x) {
              const int32_t l = lab.at(region.lo[0] + z, region.lo[1] + y, region.lo[2] + x);
              target.at(z, y, x) = (l && eligible[l] && groups[l] != mine) ? 1 : 0;
            }
      } else {
        target = crop(anchor, region);
      }
      if (!count(target)) { ++pi; continue; }
      Mask inv(target.d, 0);
      for (size_t i = 0; i < inv.v.size(); ++i) inv.v[i] = target.v[i] ? 0 : 1;
      Edt e = edt(inv, sp, false);
      float best = EDT_INF;
      for (size_t i = 0; i < cand.v.size(); ++i) if (cand.v[i] && e.d2.v[i] < best) best = e.d2.v[i];
      if (best >= EDT_INF || best > gap_lim2) { ++pi; continue; }
      const double gap = std::sqrt((double)best);
      Mask al_r = crop(al, region);
      Mask support(cand.d, 0);
      for (size_t i = 0; i < support.v.size(); ++i) support.v[i] = (al_r.v[i] || cand.v[i] || target.v[i]) ? 1 : 0;
      auto starts = boundary_points(cand);
      Mask ends_m(cand.d, 0);
      for (auto& p : boundary_points(target)) ends_m.at(p[0], p[1], p[2]) = 1;
      std::vector<std::array<int, 3>> path;
      if (!geodesic_path(support, starts, ends_m, sp, path)) { ++pi; continue; }
      double length = 0;
      for (size_t k = 1; k < path.size(); ++k) {
        double s = 0;
        for (int a = 0; a < 3; ++a) { const double dd = (path[k][a] - path[k - 1][a]) * sp[a]; s += dd * dd; }
        length += std::sqrt(s);
      }
      if (length > maximum_mm * 1.8) { ++pi; continue; }
      Mask center(cand.d, 0);
      for (auto& p : path) center.at(p[0], p[1], p[2]) = 1;
      Mask cinv(cand.d, 0);
      for (size_t i = 0; i < cinv.v.size(); ++i) cinv.v[i] = center.v[i] ? 0 : 1;
      Edt ce = edt(cinv, sp, false);
      Mask tube(cand.d, 0);
      for (size_t i = 0; i < tube.v.size(); ++i) tube.v[i] = (ce.d2.v[i] <= r2 && support.v[i]) ? 1 : 0;
      Mask combined(cand.d, 0);
      for (size_t i = 0; i < combined.v.size(); ++i) combined.v[i] = (target.v[i] || cand.v[i] || tube.v[i]) ? 1 : 0;
      Vol<int32_t> ll;
      label(combined, 1, ll);
      const auto& s0 = path.front();
      const auto& e0 = path.back();
      if (ll.at(s0[0], s0[1], s0[2]) != ll.at(e0[0], e0[1], e0[2])) { ++pi; continue; }
      paste_or(anchor, cand, region);
      paste_or(anchor, tube, region);
      if (retain) {
        const int32_t endl = lab.at(region.lo[0] + e0[0], region.lo[1] + e0[1], region.lo[2] + e0[2]);
        parents[root(index)] = root(endl);
      }
      pending.erase(pending.begin() + pi);
      json b = json::object();
      b["component_voxels"] = counts[index];
      b["gap_mm"] = gap;
      b["path_length_mm"] = length;
      b["tube_radius_mm"] = radius;
      bridges.push_back(b);
      progress = true;
    }
    if (!progress) break;
  }
  if (retain) {
    std::vector<char> keep(count_n + 1, 0);
    for (int i : pending) if (counts[i] * vv >= retain_min_mm3) keep[i] = 1;
    for (size_t i = 0; i < anchor.v.size(); ++i) if (lab.v[i] && keep[lab.v[i]]) anchor.v[i] = 1;
  }
  Mask rejected = logical_andnot(m, anchor);
  Vol<int32_t> rl, fl;
  const int unresolved = label(rejected, 1, rl);
  const int remaining = label(anchor, 1, fl);
  std::vector<int64_t> fc(remaining + 1, 0);
  for (int32_t l : fl.v) ++fc[l];
  int largest = 1;
  for (int l = 2; l <= remaining; ++l) if (fc[l] > fc[largest]) largest = l;
  int64_t kept = 0, added = 0, ret_vox = 0, withheld = (int64_t)count(rejected);
  for (size_t i = 0; i < m.v.size(); ++i) {
    const bool a = anchor.v[i], o = m.v[i];
    if (o && a) { ++kept; if (fl.v[i] != largest) ++ret_vox; }
    if (a && !o) ++added;
  }
  info = base_info(unresolved, withheld, kept, added, std::max(0, remaining - 1), ret_vox, remaining);
  info["accepted_bridges"] = bridges;
  out.anchor = Mask(mask.d, 0);
  paste(out.anchor, anchor, cb);
  out.rejected = Mask(mask.d, 0);
  paste(out.rejected, rejected, cb);
  out.info = info;
  return out;
}

// 3x3 对称矩阵特征值（Jacobi），升序。
void eig3(double a[3][3], double w[3]) {
  for (int sweep = 0; sweep < 60; ++sweep) {
    double off = std::fabs(a[0][1]) + std::fabs(a[0][2]) + std::fabs(a[1][2]);
    if (off < 1e-14) break;
    for (int p = 0; p < 2; ++p)
      for (int q = p + 1; q < 3; ++q) {
        if (std::fabs(a[p][q]) < 1e-300) continue;
        const double theta = (a[q][q] - a[p][p]) / (2 * a[p][q]);
        const double t = (theta >= 0 ? 1 : -1) / (std::fabs(theta) + std::sqrt(theta * theta + 1));
        const double c = 1 / std::sqrt(t * t + 1), s = t * c;
        for (int k = 0; k < 3; ++k) {
          const double akp = a[k][p], akq = a[k][q];
          a[k][p] = c * akp - s * akq;
          a[k][q] = s * akp + c * akq;
        }
        for (int k = 0; k < 3; ++k) {
          const double apk = a[p][k], aqk = a[q][k];
          a[p][k] = c * apk - s * aqk;
          a[q][k] = s * apk + c * aqk;
        }
      }
  }
  w[0] = a[0][0]; w[1] = a[1][1]; w[2] = a[2][2];
  std::sort(w, w + 3);
}

Mask filter_vein_islands(const Mask& mask, const Spacing& sp, json& info) {
  Box bb = bbox(mask);
  Mask result(mask.d, 0);
  if (bb.empty()) {
    info = json::object();
    return result;
  }
  Mask m = crop(mask, bb);
  Vol<int32_t> lab;
  const int n = label(m, 3, lab);
  std::vector<int64_t> counts;
  std::vector<Box> boxes;
  label_stats(lab, n, counts, boxes);
  std::vector<char> keep(n + 1, 0);
  int largest = 1;
  for (int l = 2; l <= n; ++l) if (counts[l] > counts[largest]) largest = l;
  if (n) keep[largest] = 1;
  const double vv = vox_volume(sp);
  for (int l = 1; l <= n; ++l) {
    if (keep[l] || counts[l] * vv >= 500) { keep[l] = 1; continue; }
    double ext = 0;
    for (int a = 0; a < 3; ++a) ext = std::max(ext, (boxes[l].hi[a] - boxes[l].lo[a] - 1) * sp[a]);
    if (ext < 25) continue;
    double mean[3] = {0, 0, 0}, c[3][3] = {{0}};
    const double N = (double)counts[l];
    std::vector<std::array<double, 3>> pts;
    for (int z = boxes[l].lo[0]; z < boxes[l].hi[0]; ++z)
      for (int y = boxes[l].lo[1]; y < boxes[l].hi[1]; ++y)
        for (int x = boxes[l].lo[2]; x < boxes[l].hi[2]; ++x)
          if (lab.at(z, y, x) == l) {
            pts.push_back({(z - boxes[l].lo[0]) * sp[0], (y - boxes[l].lo[1]) * sp[1], (x - boxes[l].lo[2]) * sp[2]});
          }
    for (auto& p : pts) for (int a = 0; a < 3; ++a) mean[a] += p[a] / N;
    for (auto& p : pts)
      for (int a = 0; a < 3; ++a)
        for (int b = 0; b < 3; ++b) c[a][b] += (p[a] - mean[a]) * (p[b] - mean[b]);
    for (int a = 0; a < 3; ++a) for (int b = 0; b < 3; ++b) c[a][b] /= std::max(N - 1, 1.0);
    double w[3];
    eig3(c, w);
    keep[l] = std::sqrt(w[2] / std::max(w[1], .001)) >= 3;
  }
  int kept = 0;
  Mask r(m.d, 0);
  for (size_t i = 0; i < r.v.size(); ++i) r.v[i] = (lab.v[i] && keep[lab.v[i]]) ? 1 : 0;
  for (int l = 1; l <= n; ++l) kept += keep[l];
  int64_t removed = 0;
  for (size_t i = 0; i < r.v.size(); ++i) if (m.v[i] && !r.v[i]) ++removed;
  paste(result, r, bb);
  info = json::object();
  info["operation"] = "remove small isolated candidates; protect long slender branches";
  info["minimum_volume_mm3"] = 500;
  info["protected_branch_minimum_extent_mm"] = 25;
  info["protected_branch_minimum_pca_elongation"] = 3;
  info["components_before"] = n;
  info["components_after"] = kept;
  info["removed_components"] = n - kept;
  info["removed_voxels"] = removed;
  return result;
}

// 远距离碎片桥接：对主干之外的碎片，沿最近点连线补一根圆柱管（不穿过 exclude，如动脉/气道）。
// 用于模型漏分割造成的断联；与 CT 无关，管半径固定，后续平滑会把接口融合。
Mask bridge_far_fragments(const Mask& mask, const Mask& exclude, const Spacing& sp, double max_gap_mm, double radius_mm, json& info) {
  info = json::object();
  info["maximum_gap_mm"] = max_gap_mm;
  info["tube_radius_mm"] = radius_mm;
  json list = json::array();
  Box bb = bbox(mask);
  if (bb.empty() || max_gap_mm <= 0) { info["bridges"] = list; return mask; }
  Box cb = clip_box(expand_box(bb, {4, 4, 4}), mask.d);
  Mask m = crop(mask, cb), ex = crop(exclude, cb);
  std::array<int, 3> rv;
  for (int k = 0; k < 3; ++k) rv[k] = (int)std::ceil(radius_mm / sp[k]);
  int skipped_blocked = 0, skipped_far = 0;
  for (int round = 0; round < 8; ++round) {
    Vol<int32_t> lab;
    const int n = label(m, 1, lab);
    info["remaining_components"] = n;
    if (n <= 1) break;
    std::vector<int64_t> counts;
    std::vector<Box> boxes;
    label_stats(lab, n, counts, boxes);
    int main_id = 1;
    for (int l = 2; l <= n; ++l) if (counts[l] > counts[main_id]) main_id = l;
    Mask inv(m.d, 0);
    for (size_t i = 0; i < inv.v.size(); ++i) inv.v[i] = lab.v[i] == main_id ? 0 : 1;
    Edt e = edt(inv, sp, true);
    auto unravel = [&](size_t i) { return std::array<int, 3>{(int)(i / ((size_t)m.d.y * m.d.x)), (int)((i / m.d.x) % m.d.y), (int)(i % m.d.x)}; };
    Mask add(m.d, 0);
    int done = 0;
    skipped_blocked = skipped_far = 0;
    for (int l = 1; l <= n; ++l) {
      if (l == main_id) continue;
      float best = EDT_INF;
      size_t bi = 0;
      for (int z = boxes[l].lo[0]; z < boxes[l].hi[0]; ++z)
        for (int y = boxes[l].lo[1]; y < boxes[l].hi[1]; ++y)
          for (int x = boxes[l].lo[2]; x < boxes[l].hi[2]; ++x) {
            const size_t i = m.idx(z, y, x);
            if (lab.v[i] == l && e.d2.v[i] < best) { best = e.d2.v[i]; bi = i; }
          }
      const double gap = std::sqrt((double)best);
      if (best >= EDT_INF || gap > max_gap_mm) { ++skipped_far; continue; }
      const auto a = unravel(bi), b = unravel((size_t)e.nearest.v[bi]);
      const auto samples = line_samples(a, b);
      bool blocked = false;
      for (auto& s : samples) if (ex.at(s[0], s[1], s[2])) { blocked = true; break; }
      if (blocked) { ++skipped_blocked; continue; }
      for (auto& s : samples)
        for (int dz = -rv[0]; dz <= rv[0]; ++dz)
          for (int dy = -rv[1]; dy <= rv[1]; ++dy)
            for (int dx = -rv[2]; dx <= rv[2]; ++dx) {
              const int z = s[0] + dz, y = s[1] + dy, x = s[2] + dx;
              if (z < 0 || y < 0 || x < 0 || z >= m.d.z || y >= m.d.y || x >= m.d.x) continue;
              const double d2 = dz * dz * sp[0] * sp[0] + dy * dy * sp[1] * sp[1] + dx * dx * sp[2] * sp[2];
              if (d2 <= radius_mm * radius_mm && !ex.at(z, y, x)) add.at(z, y, x) = 1;
            }
      json bj = json::object();
      bj["component_voxels"] = counts[l];
      bj["gap_mm"] = gap;
      bj["round"] = round;
      list.push_back(bj);
      ++done;
    }
    or_inplace(m, add);
    if (!done) break;
  }
  info["bridges"] = list;
  info["skipped_beyond_gap"] = skipped_far;
  info["skipped_blocked_by_other_structure"] = skipped_blocked;
  Mask out = mask;
  paste(out, m, cb);
  return out;
}

// -------------------- repair_mask --------------------
const char* const NAMES[9] = {"LeftUpperLobe", "LeftLowerLobe", "RightUpperLobe", "RightMiddleLobe", "RightLowerLobe",
                              "Bronchus", "PulmonaryArtery", "PulmonaryVenous", "LungTumor"};

Mask repair_lobe(const Mask& raw_in, const Mask& body, const Spacing& sp, json& rep) {
  Mask raw = logical_and(raw_in, body);
  Mask mask = keep_largest(raw);
  Mask closed = logical_and(close_ellipsoid(mask, 1.0, sp), body);
  or_inplace(mask, closed);
  Mask out = logical_and(fill_holes_3d(mask), body);
  rep = json::object();
  rep["operation"] = "largest lobe, 1.0 mm closing, hole fill";
  rep["minimum_component_voxels"] = 1;
  rep["closing_radius_mm"] = 1.0;
  rep["reference_supported_component_selection"] = false;
  return out;
}

Mask repair_tumor(const Mask& raw_in, const Mask& body, const Mask& hu_ok, const Spacing& sp, json& rep) {
  Mask raw = logical_and(raw_in, body);
  Box b = bbox(raw);
  Mask result(raw.d, 0);
  int bridges = 0;
  int64_t removed_vox = 0;
  int components = 0;
  if (!b.empty()) {
    Vol<int32_t> lab;
    const int n = label(raw, 3, lab);
    std::vector<int64_t> counts(n + 1, 0);
    for (int32_t l : lab.v) ++counts[l];
    std::vector<char> major(n + 1, 0);
    for (int l = 1; l <= n; ++l) major[l] = counts[l] >= 50;
    Mask mj(raw.d, 0);
    for (size_t i = 0; i < mj.v.size(); ++i) mj.v[i] = (lab.v[i] && major[lab.v[i]]) ? 1 : 0;
    Mask near = dilate_ellipsoid(mj, 3.0, sp);
    std::vector<char> nearby(n + 1, 0);
    for (size_t i = 0; i < near.v.size(); ++i) if (near.v[i] && lab.v[i]) nearby[lab.v[i]] = 1;
    for (int l = 1; l <= n; ++l) if (nearby[l] && counts[l] >= 5) major[l] = 1;
    Mask mask(raw.d, 0);
    for (size_t i = 0; i < mask.v.size(); ++i) mask.v[i] = (lab.v[i] && major[lab.v[i]]) ? 1 : 0;
    Mask closed = logical_and(close_ellipsoid(mask, 1.5, sp), body);
    or_inplace(mask, closed);
    Mask allowed = logical_and(body, hu_ok);
    mask = connect_nearby(mask, allowed, sp, 3.0, bridges);
    mask = remove_small(mask, 5);
    const int64_t candidate_voxels = (int64_t)count(mask);
    Vol<int32_t> l2;
    components = label(mask, 3, l2);
    if (components) {
      std::vector<int64_t> c2(components + 1, 0);
      for (int32_t l : l2.v) ++c2[l];
      int best = 1;
      for (int l = 2; l <= components; ++l) if (c2[l] > c2[best]) best = l;
      for (size_t i = 0; i < mask.v.size(); ++i) mask.v[i] = l2.v[i] == best ? 1 : 0;
    }
    removed_vox = candidate_voxels - (int64_t)count(mask);
    result = mask;
  }
  rep = json::object();
  rep["operation"] = "close and bridge small gaps, then display only the largest connected tumor candidate";
  rep["minimum_component_voxels"] = 5;
  rep["distant_component_minimum_voxels"] = 50;
  rep["closing_radius_mm"] = 1.5;
  rep["maximum_bridge_distance_mm"] = 3.0;
  rep["accepted_bridges"] = bridges;
  rep["display_largest_candidate_only"] = true;
  rep["removed_disconnected_components"] = std::max(0, components - 1);
  rep["removed_disconnected_voxels"] = removed_vox;
  rep["reference_supported_component_selection"] = false;
  return result;
}

Mask repair_branch_mask(int index, const Mask& raw_in, const Mask& body, const CtData& ct, const Spacing& sp, json& rep) {
  Mask raw = logical_and(raw_in, body);
  Mask allowed;
  if (index == 5) allowed = logical_and(body, make_mask(ct, [](float h) { return h < -400.0f; }));
  else allowed = logical_and(body, make_mask(ct, [](float h) { return h > -200.0f && h < 700.0f; }));
  Mask additions = logical_and(close_ellipsoid(raw, 1.5, sp), allowed);
  Mask merged = logical_or(raw, additions);
  int bridges = 0;
  Mask mask = connect_nearby(merged, allowed, sp, 2.5, bridges);
  Mask out = remove_small(mask, 50);
  rep = json::object();
  rep["operation"] = "CT-constrained 1.5 mm closing and local bridges; retain branches >=50 voxels";
  rep["minimum_component_voxels"] = 50;
  rep["closing_radius_mm"] = 1.5;
  rep["maximum_bridge_distance_mm"] = 2.5;
  rep["accepted_bridges"] = bridges;
  rep["reference_supported_component_selection"] = false;
  return out;
}

// -------------------- 肺叶联合包络修补 --------------------
json repair_lobe_envelope(std::vector<Mask>& masks, const Mask& body, const CtData& ct, const Spacing& sp) {
  const Dims D = masks[0].d;
  Vol<uint8_t> labels(D, 0);
#pragma omp parallel for
  for (long k = 0; k < (long)labels.v.size(); ++k)
    for (size_t i = 0; i < masks.size(); ++i) if (masks[i].v[k]) labels.v[k] = (uint8_t)(i + 1);
  const Vol<uint8_t> original = labels;
  std::vector<int64_t> orig_count(6, 0);
  for (uint8_t l : original.v) ++orig_count[l];

  json details = json::object();
  details["maximum_fill_distance_mm"] = 2.5;
  details["closing_radius_mm"] = 3.0;
  details["maximum_added_fraction_per_lobe"] = .01;
  details["boundary_sigma_mm"] = 1.5;
  details["maximum_boundary_change_fraction_per_lobe"] = .01;
  json lungs = json::array();
  const std::vector<std::vector<int>> groups = {{1, 2}, {3, 4, 5}};
  for (const auto& ids : groups) {
    Mask lung(D, 0);
    for (size_t k = 0; k < lung.v.size(); ++k)
      for (int i : ids) if (original.v[k] == i) lung.v[k] = 1;
    Box lb = bbox(lung);
    if (lb.empty()) continue;
    std::array<int, 3> pad;
    for (int a = 0; a < 3; ++a) pad[a] = (int)std::ceil(5.0 / sp[a]);
    Box box = clip_box(expand_box(lb, pad), D);
    Mask local = crop(lung, box);
    const Dims ld = local.d;
    Vol<uint8_t> local_labels(ld, 0);
    for (int z = 0; z < ld.z; ++z)
      for (int y = 0; y < ld.y; ++y)
        for (int x = 0; x < ld.x; ++x) local_labels.at(z, y, x) = original.at(box.lo[0] + z, box.lo[1] + y, box.lo[2] + x);

    Vol<float> best(ld, 0.f), own(ld, 0.f);
    Vol<uint8_t> winner = local_labels;
    const std::array<double, 3> sg = {1.5 / sp[0], 1.5 / sp[1], 1.5 / sp[2]};
    for (int i : ids) {
      Vol<float> field(ld, 0.f);
      for (size_t k = 0; k < field.v.size(); ++k) field.v[k] = local_labels.v[k] == i ? 1.f : 0.f;
      gaussian_filter(field, sg, Border::Reflect);
      for (size_t k = 0; k < field.v.size(); ++k) {
        if (local_labels.v[k] == i) own.v[k] = field.v[k];
        if (field.v[k] > best.v[k]) { best.v[k] = field.v[k]; winner.v[k] = (uint8_t)i; }
      }
    }
    Mask candidate_boundary(ld, 0);
    for (size_t k = 0; k < candidate_boundary.v.size(); ++k)
      candidate_boundary.v[k] = (local.v[k] && winner.v[k] != local_labels.v[k] && own.v[k] < .4f && best.v[k] > .45f) ? 1 : 0;
    std::vector<int64_t> used_b(6, 0), budget_b(6, 0);
    for (int i : ids) budget_b[i] = (int64_t)(orig_count[i] * .01);
    for (int target : ids) {
      // 没有候选边界体素归属该目标时，后面的选择必为空，无需计算距离变换。
      bool any_candidate = false;
      for (size_t k = 0; k < candidate_boundary.v.size() && !any_candidate; ++k)
        any_candidate = candidate_boundary.v[k] && winner.v[k] == target;
      if (!any_candidate) continue;
      Mask not_t(ld, 0);
      for (size_t k = 0; k < not_t.v.size(); ++k) not_t.v[k] = local_labels.v[k] != target ? 1 : 0;
      Edt dt = edt(not_t, sp, false);
      for (int donor : ids) {
        if (donor == target) continue;
        Mask sel(ld, 0);
        for (size_t k = 0; k < sel.v.size(); ++k)
          sel.v[k] = (candidate_boundary.v[k] && winner.v[k] == target && local_labels.v[k] == donor && dt.d2.v[k] <= 1.5 * 1.5 * (1 + 1e-6)) ? 1 : 0;
        if (!count(sel)) continue;  // 空选择不会改动任何标签
        Vol<int32_t> patches;
        const int cnt = label(sel, 1, patches);
        std::vector<int64_t> sizes(cnt + 1, 0);
        for (int32_t l : patches.v) ++sizes[l];
        std::vector<int> order(cnt);
        std::iota(order.begin(), order.end(), 1);
        std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return sizes[a] < sizes[b]; });
        std::vector<char> accepted(cnt + 1, 0);
        for (int c : order) {
          const int64_t size = sizes[c];
          if (size * vox_volume(sp) <= 1000 && used_b[target] + size <= budget_b[target] && used_b[donor] + size <= budget_b[donor]) {
            accepted[c] = 1;
            used_b[target] += size;
            used_b[donor] += size;
          }
        }
        for (int z = 0; z < ld.z; ++z)
          for (int y = 0; y < ld.y; ++y)
            for (int x = 0; x < ld.x; ++x)
              if (accepted[patches.at(z, y, x)]) labels.at(box.lo[0] + z, box.lo[1] + y, box.lo[2] + x) = (uint8_t)target;
      }
    }

    Mask not_lung(ld, 0);
    for (size_t k = 0; k < not_lung.v.size(); ++k) not_lung.v[k] = local.v[k] ? 0 : 1;
    Edt near = edt(not_lung, sp, true);
    Mask closed = close_ellipsoid(local, 3.0, sp);
    Mask enclosed = fill_holes_3d(local);
    Mask candidate(ld, 0);
    for (int z = 0; z < ld.z; ++z)
      for (int y = 0; y < ld.y; ++y)
        for (int x = 0; x < ld.x; ++x) {
          const size_t k = local.idx(z, y, x);
          const size_t g = ct.d.n() ? ((size_t)(box.lo[0] + z) * D.y + box.lo[1] + y) * D.x + box.lo[2] + x : 0;
          const bool tgt = (closed.v[k] && ct.hu(g) < -300.0f) || enclosed.v[k];
          candidate.v[k] = (tgt && !local.v[k] && original.at(box.lo[0] + z, box.lo[1] + y, box.lo[2] + x) == 0 &&
                            body.at(box.lo[0] + z, box.lo[1] + y, box.lo[2] + x) && near.d2.v[k] <= 2.5 * 2.5 * (1 + 1e-6))
                               ? 1 : 0;
        }
    Vol<int32_t> comps;
    const int ncomp = label(candidate, 1, comps);
    std::vector<double> sizes(ncomp + 1, 0);
    for (int32_t l : comps.v) sizes[l] += 1;
    for (double& s : sizes) s *= vox_volume(sp);
    Vol<uint8_t> nearest_labels(ld, 0);
    for (size_t k = 0; k < nearest_labels.v.size(); ++k) {
      const int32_t ni = near.nearest.v[k];
      nearest_labels.v[k] = ni >= 0 ? local_labels.v[(size_t)ni] : 0;
    }
    std::vector<int64_t> budgets(6, 0), used(6, 0);
    for (int i : ids) budgets[i] = (int64_t)(orig_count[i] * .01);
    std::vector<std::vector<int64_t>> cnts(6);
    for (int i : ids) cnts[i].assign(ncomp + 1, 0);
    for (size_t k = 0; k < comps.v.size(); ++k)
      if (comps.v[k]) for (int i : ids) if (nearest_labels.v[k] == i) ++cnts[i][comps.v[k]];
    std::vector<int> order(ncomp);
    std::iota(order.begin(), order.end(), 1);
    std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return sizes[a] < sizes[b]; });
    std::vector<char> accepted(ncomp + 1, 0);
    for (int c : order) {
      if (sizes[c] > 1000.) continue;
      bool ok = true;
      for (int i : ids) if (used[i] + cnts[i][c] > budgets[i]) ok = false;
      if (!ok) continue;
      accepted[c] = 1;
      for (int i : ids) used[i] += cnts[i][c];
    }
    for (int z = 0; z < ld.z; ++z)
      for (int y = 0; y < ld.y; ++y)
        for (int x = 0; x < ld.x; ++x) {
          const size_t k = comps.idx(z, y, x);
          if (comps.v[k] && accepted[comps.v[k]]) labels.at(box.lo[0] + z, box.lo[1] + y, box.lo[2] + x) = nearest_labels.v[k];
        }
    json lj = json::object();
    json lab_ids = json::array();
    json added = json::object(), changed = json::object();
    for (int i : ids) { lab_ids.push_back(i); added[std::to_string(i)] = used[i]; changed[std::to_string(i)] = used_b[i]; }
    lj["labels"] = lab_ids;
    lj["candidate_voxels"] = (int64_t)count(candidate);
    lj["added_voxels_per_lobe"] = added;
    lj["boundary_changed_voxels_per_lobe"] = changed;
    lungs.push_back(lj);
  }
  details["lungs"] = lungs;
  int64_t added_total = 0, changed_total = 0;
  for (size_t k = 0; k < labels.v.size(); ++k) {
    if (labels.v[k] > 0 && original.v[k] == 0) ++added_total;
    if (original.v[k] > 0 && labels.v[k] != original.v[k]) ++changed_total;
  }
  details["added_voxels"] = added_total;
  details["changed_existing_labels"] = changed_total;
#pragma omp parallel for
  for (long k = 0; k < (long)labels.v.size(); ++k)
    for (size_t i = 0; i < masks.size(); ++i) masks[i].v[k] = labels.v[k] == i + 1 ? 1 : 0;
  return details;
}

}  // namespace

Prepared prepare_masks(const std::vector<Mask>& raw, const Mask& body, const CtData& ct, const Spacing& sp,
                       const std::string& out_dir, const Progress& progress, double far_bridge_mm) {
  Prepared P;
  P.masks.resize(9);
  P.repairs.resize(9);
  make_dirs(join(out_dir, "review_withheld"));
  progress("修补五肺叶");
  std::vector<Mask> lobes(5);
  std::vector<json> lobe_rep(5);
  // 五个肺叶的单独修补互不依赖（连通域/填洞为单线程），按肺叶并行。
  std::vector<std::string> lobe_err(5);
#pragma omp parallel for schedule(dynamic, 1)
  for (int i = 0; i < 5; ++i) {
    try { lobes[i] = repair_lobe(raw[i], body, sp, lobe_rep[i]); }
    catch (const std::exception& ex) { lobe_err[i] = ex.what(); }
  }
  for (const auto& e : lobe_err) if (!e.empty()) throw Error(e);
  P.details["joint_lobe_repair"] = repair_lobe_envelope(lobes, body, ct, sp);
  for (int i = 0; i < 5; ++i) { P.masks[i] = std::move(lobes[i]); P.repairs[i] = lobe_rep[i]; }

  Mask tumor_ok = make_mask(ct, [](float h) { return h > -250.0f; });
  for (int index = 5; index < 9; ++index) {
    progress(fmt("修补 %s", NAMES[index]));
    json rep;
    Mask mask;
    if (index == 8) {
      P.masks[8] = repair_tumor(raw[8], body, tumor_ok, sp, rep);
      P.repairs[8] = rep;
      continue;
    }
    mask = repair_branch_mask(index, raw[index], body, ct, sp, rep);
    Mask allowed = index == 5 ? logical_and(body, make_mask(ct, [](float h) { return h < -300.0f; }))
                              : logical_and(body, make_mask(ct, [](float h) { return h > -400.0f && h < 700.0f; }));
    if (index != 5) allowed = logical_andnot(allowed, raw[index == 6 ? 7 : 6]);
    const int64_t before_voxels = (int64_t)count(mask);
    Mask before_connections = mask;
    const bool vein = index == 7;
    BranchOut bo = repair_branches(mask, allowed, sp, 6.0, vein ? 20.0 : -1.0);
    mask = bo.anchor;
    Mask rejected = bo.rejected;
    json conn = bo.info;
    if (vein) {
      json cleanup;
      mask = filter_vein_islands(mask, sp, cleanup);
      {
        Mask exclude = logical_or(logical_or(raw[6], P.masks[6]), P.masks[5]);
        json farj;
        mask = bridge_far_fragments(mask, exclude, sp, far_bridge_mm, 1.5, farj);
        conn["far_bridge"] = farj;
        progress(fmt("[repair] 静脉远距离桥接 %zu 处", farj["bridges"].size()));
      }
      rejected = logical_andnot(before_connections, mask);
      conn["withheld_voxels"] = (int64_t)count(rejected);
      Vol<int32_t> rl;
      conn["unresolved_components"] = label(rejected, 1, rl);
      conn["retained_prediction_voxels"] = (int64_t)count(logical_and(before_connections, mask));
      conn["added_bridge_voxels"] = (int64_t)count(logical_andnot(mask, before_connections));
      Vol<int32_t> ml;
      const int comps = label(mask, 1, ml);
      std::vector<int64_t> sizes(comps + 1, 0);
      for (int32_t l : ml.v) ++sizes[l];
      int largest = 1;
      for (int l = 2; l <= comps; ++l) if (sizes[l] > sizes[largest]) largest = l;
      int64_t disc = 0;
      for (size_t k = 0; k < ml.v.size(); ++k) if (before_connections.v[k] && ml.v[k] && ml.v[k] != largest) ++disc;
      conn["remaining_face_connected_components"] = comps;
      conn["retained_unconnected_components"] = std::max(0, comps - 1);
      conn["retained_unconnected_voxels"] = disc;
      rep["island_cleanup"] = cleanup;
    }
    const std::string wp = join(out_dir, std::string("review_withheld/") + NAMES[index] + "_withheld.npy");
    write_npy_u8(wp, rejected);
    conn["before_voxels"] = before_voxels;
    conn["withheld_mask"] = wp;
    rep["connected_display"] = conn;
    P.masks[index] = std::move(mask);
    P.repairs[index] = rep;
    progress(fmt("[repair] %s: %zu bridges; %lld voxels withheld", NAMES[index], conn["accepted_bridges"].size(),
                 (long long)count(rejected)));
  }
  return P;
}

}  // namespace ctf
