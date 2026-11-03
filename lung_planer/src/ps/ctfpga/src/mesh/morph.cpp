#include "mesh/morph.hpp"

#include <algorithm>
#include <cmath>
#include <deque>
#include <limits>

namespace ctf {
namespace {

constexpr double BIG = 1e29;

// Felzenszwalb 下包络：f 为各点抛物线基值（>=BIG 视为无穷），s 为格点间距（mm）。
// out[i] = min_q f[q] + ((i-q)*s)^2；src[i] 为取得最小值的 q（无穷时为 -1）。
struct LineBuf {
  std::vector<double> f, out, zz;
  std::vector<int> v, src;
  void init(int n) { f.resize(n); out.resize(n); zz.resize(n + 1); v.resize(n); src.resize(n); }
};

void line_edt(LineBuf& b, int n, double s) {
  int k = -1;
  const double INFD = std::numeric_limits<double>::infinity();
  for (int q = 0; q < n; ++q) {
    if (b.f[q] >= BIG) continue;
    const double pq = q * s;
    if (k < 0) { k = 0; b.v[0] = q; b.zz[0] = -INFD; b.zz[1] = INFD; continue; }
    while (true) {
      const double pv = b.v[k] * s;
      const double sx = ((b.f[q] + pq * pq) - (b.f[b.v[k]] + pv * pv)) / (2.0 * (pq - pv));
      if (sx <= b.zz[k]) { --k; if (k < 0) { k = 0; b.v[0] = q; b.zz[0] = -INFD; b.zz[1] = INFD; break; } }
      else { ++k; b.v[k] = q; b.zz[k] = sx; b.zz[k + 1] = INFD; break; }
    }
  }
  if (k < 0) {
    for (int i = 0; i < n; ++i) { b.out[i] = (double)EDT_INF; b.src[i] = -1; }
    return;
  }
  int j = 0;
  for (int i = 0; i < n; ++i) {
    const double pos = i * s;
    while (b.zz[j + 1] < pos) ++j;
    const double dq = pos - b.v[j] * s;
    b.out[i] = dq * dq + b.f[b.v[j]];
    b.src[i] = b.v[j];
  }
}

}  // namespace

Edt edt(const Mask& m, const Spacing& sp, bool want_index) {
  Edt r;
  r.d2 = Vol<float>(m.d, 0.f);
  if (want_index) r.nearest = Vol<int32_t>(m.d, -1);
  const Dims d = m.d;
  // 第 1 趟：沿 x。
#pragma omp parallel
  {
    LineBuf b;
    b.init(d.x);
#pragma omp for collapse(2)
    for (int z = 0; z < d.z; ++z)
      for (int y = 0; y < d.y; ++y) {
        const size_t base = m.idx(z, y, 0);
        for (int x = 0; x < d.x; ++x) b.f[x] = m.v[base + x] ? (double)EDT_INF : 0.0;
        line_edt(b, d.x, sp[2]);
        for (int x = 0; x < d.x; ++x) {
          r.d2.v[base + x] = (float)b.out[x];
          if (want_index) r.nearest.v[base + x] = b.src[x] < 0 ? -1 : (int32_t)(base + b.src[x]);
        }
      }
  }
  // 第 2 趟：沿 y。
#pragma omp parallel
  {
    LineBuf b;
    b.init(d.y);
    std::vector<int32_t> pay(d.y);
#pragma omp for collapse(2)
    for (int z = 0; z < d.z; ++z)
      for (int x = 0; x < d.x; ++x) {
        for (int y = 0; y < d.y; ++y) {
          const size_t i = r.d2.idx(z, y, x);
          b.f[y] = r.d2.v[i];
          if (want_index) pay[y] = r.nearest.v[i];
        }
        line_edt(b, d.y, sp[1]);
        for (int y = 0; y < d.y; ++y) {
          const size_t i = r.d2.idx(z, y, x);
          r.d2.v[i] = (float)b.out[y];
          if (want_index) r.nearest.v[i] = b.src[y] < 0 ? -1 : pay[b.src[y]];
        }
      }
  }
  // 第 3 趟：沿 z。
#pragma omp parallel
  {
    LineBuf b;
    b.init(d.z);
    std::vector<int32_t> pay(d.z);
#pragma omp for collapse(2)
    for (int y = 0; y < d.y; ++y)
      for (int x = 0; x < d.x; ++x) {
        for (int z = 0; z < d.z; ++z) {
          const size_t i = r.d2.idx(z, y, x);
          b.f[z] = r.d2.v[i];
          if (want_index) pay[z] = r.nearest.v[i];
        }
        line_edt(b, d.z, sp[0]);
        for (int z = 0; z < d.z; ++z) {
          const size_t i = r.d2.idx(z, y, x);
          r.d2.v[i] = (float)b.out[z];
          if (want_index) r.nearest.v[i] = b.src[z] < 0 ? -1 : pay[b.src[z]];
        }
      }
  }
  // 零体素自身距离为 0，最近点为自身。
  if (want_index)
#pragma omp parallel for
    for (long i = 0; i < (long)m.v.size(); ++i) if (!m.v[i]) { r.d2.v[i] = 0.f; r.nearest.v[i] = (int32_t)i; }
  return r;
}

namespace {
// 浮点余量：吸收 float 存储误差，同时保持恰好相等的格点（如 2×1.25 mm = 2.5 mm）被包含。
inline double thr(double r_mm) { return r_mm * r_mm * (1.0 + 1e-6); }

Mask dilate_in_box(const Mask& m, const Box& box, double r_mm, const Spacing& sp) {
  Mask crop_m = crop(m, box);
  Mask inv(crop_m.d, 0);
  for (size_t i = 0; i < inv.v.size(); ++i) inv.v[i] = crop_m.v[i] ? 0 : 1;
  Edt e = edt(inv, sp, false);
  const double t = thr(r_mm);
  Mask out(crop_m.d, 0);
#pragma omp parallel for
  for (long i = 0; i < (long)out.v.size(); ++i) out.v[i] = (crop_m.v[i] || e.d2.v[i] <= t) ? 1 : 0;
  return out;
}
}  // namespace

Mask dilate_ellipsoid(const Mask& m, double r_mm, const Spacing& sp) {
  Mask out(m.d, 0);
  Box b = bbox(m);
  if (b.empty()) return out;
  const auto rad = ellipsoid_radii(r_mm, sp);
  Box box = clip_box(expand_box(b, rad), m.d);  // 体数据之外本来就是边界，不需要额外边距
  Mask part = dilate_in_box(m, box, r_mm, sp);
  paste(out, part, box);
  return out;
}

Mask erode_ellipsoid(const Mask& m, double r_mm, const Spacing& sp) {
  Mask out(m.d, 0);
  Box b = bbox(m);
  if (b.empty()) return out;
  // 边界外视为 0：裁剪时在包围盒外侧补 1 圈 0，使包围盒贴边的体素也能被边界侵蚀。
  Box box = expand_box(b, {1, 1, 1});
  Mask crop_m = crop(m, box);
  Edt e = edt(crop_m, sp, false);
  const double t = thr(r_mm);
  Mask part(crop_m.d, 0);
#pragma omp parallel for
  for (long i = 0; i < (long)part.v.size(); ++i) part.v[i] = (crop_m.v[i] && e.d2.v[i] > t) ? 1 : 0;
  paste(out, part, box);
  return out;
}

Mask close_ellipsoid(const Mask& m, double r_mm, const Spacing& sp) {
  Mask out(m.d, 0);
  Box b = bbox(m);
  if (b.empty()) return out;
  const auto rad = ellipsoid_radii(r_mm, sp);
  std::array<int, 3> pad = {rad[0] + 1, rad[1] + 1, rad[2] + 1};
  Box box = expand_box(b, pad);  // 允许超出体数据（补 0）
  Mask dil = dilate_in_box(m, box, r_mm, sp);
  // 体数据之外的膨胀结果不存在（border_value=0），腐蚀时它们应为背景。
  for (int z = 0; z < dil.d.z; ++z)
    for (int y = 0; y < dil.d.y; ++y) {
      const int gz = box.lo[0] + z, gy = box.lo[1] + y;
      const bool zy_in = gz >= 0 && gz < m.d.z && gy >= 0 && gy < m.d.y;
      for (int x = 0; x < dil.d.x; ++x) {
        const int gx = box.lo[2] + x;
        if (!(zy_in && gx >= 0 && gx < m.d.x)) dil.v[dil.idx(z, y, x)] = 0;
      }
    }
  Edt e = edt(dil, sp, false);
  const double t = thr(r_mm);
  Mask ero(dil.d, 0);
#pragma omp parallel for
  for (long i = 0; i < (long)ero.v.size(); ++i) ero.v[i] = (dil.v[i] && e.d2.v[i] > t) ? 1 : 0;
  paste(out, ero, box);
  return out;
}

Mask erode6(const Mask& m) {
  Mask out(m.d, 0);
#pragma omp parallel for
  for (int z = 0; z < m.d.z; ++z)
    for (int y = 0; y < m.d.y; ++y)
      for (int x = 0; x < m.d.x; ++x) {
        if (!m.at(z, y, x)) continue;
        if (z == 0 || y == 0 || x == 0 || z == m.d.z - 1 || y == m.d.y - 1 || x == m.d.x - 1) continue;
        if (m.at(z - 1, y, x) && m.at(z + 1, y, x) && m.at(z, y - 1, x) && m.at(z, y + 1, x) && m.at(z, y, x - 1) &&
            m.at(z, y, x + 1))
          out.at(z, y, x) = 1;
      }
  return out;
}

Mask fill_holes_3d(const Mask& m) {
  Mask out = m;
  Box b = bbox(m);
  if (b.empty()) return out;
  Box box = expand_box(b, {1, 1, 1});
  Mask c = crop(m, box);
  std::vector<uint8_t> outside(c.v.size(), 0);
  std::deque<size_t> q;
  auto push = [&](int z, int y, int x) {
    const size_t i = c.idx(z, y, x);
    if (!c.v[i] && !outside[i]) { outside[i] = 1; q.push_back(i); }
  };
  push(0, 0, 0);  // 包围盒外圈全为背景且互相连通
  while (!q.empty()) {
    const size_t i = q.front(); q.pop_front();
    const int x = (int)(i % c.d.x), y = (int)((i / c.d.x) % c.d.y), z = (int)(i / ((size_t)c.d.x * c.d.y));
    if (z > 0) push(z - 1, y, x);
    if (z + 1 < c.d.z) push(z + 1, y, x);
    if (y > 0) push(z, y - 1, x);
    if (y + 1 < c.d.y) push(z, y + 1, x);
    if (x > 0) push(z, y, x - 1);
    if (x + 1 < c.d.x) push(z, y, x + 1);
  }
  Mask filled(c.d, 0);
  for (size_t i = 0; i < filled.v.size(); ++i) filled.v[i] = outside[i] ? 0 : 1;
  paste(out, filled, box);
  return out;
}

void fill_holes_2d_slices(Mask& m) {
#pragma omp parallel for
  for (int z = 0; z < m.d.z; ++z) {
    const int H = m.d.y, W = m.d.x;
    uint8_t* s = &m.v[m.idx(z, 0, 0)];
    std::vector<uint8_t> out(H * W, 0);
    std::deque<int> q;
    auto push = [&](int y, int x) {
      const int i = y * W + x;
      if (!s[i] && !out[i]) { out[i] = 1; q.push_back(i); }
    };
    for (int x = 0; x < W; ++x) { push(0, x); push(H - 1, x); }
    for (int y = 0; y < H; ++y) { push(y, 0); push(y, W - 1); }
    while (!q.empty()) {
      const int i = q.front(); q.pop_front();
      const int y = i / W, x = i % W;
      if (y > 0) push(y - 1, x);
      if (y + 1 < H) push(y + 1, x);
      if (x > 0) push(y, x - 1);
      if (x + 1 < W) push(y, x + 1);
    }
    for (int i = 0; i < H * W; ++i) s[i] = out[i] ? 0 : 1;
  }
}

// ---------------- 高斯滤波（与 scipy gaussian_filter 同核、同逐轴顺序） ----------------
void gaussian_filter(Vol<float>& f, const std::array<double, 3>& sigma, Border mode) {
  const int dim[3] = {f.d.z, f.d.y, f.d.x};
  for (int axis = 0; axis < 3; ++axis) {
    const double sg = sigma[axis];
    if (sg <= 1e-15) continue;
    const int radius = (int)(4.0 * sg + 0.5);
    std::vector<double> w(2 * radius + 1);
    double sum = 0;
    for (int i = -radius; i <= radius; ++i) { w[i + radius] = std::exp(-0.5 / (sg * sg) * i * i); sum += w[i + radius]; }
    for (double& x : w) x /= sum;
    const int n = dim[axis];
    const size_t stride = axis == 0 ? (size_t)f.d.y * f.d.x : axis == 1 ? (size_t)f.d.x : 1;
    // 其余两个轴的循环范围
    const int a1 = axis == 0 ? f.d.y : axis == 1 ? f.d.z : f.d.z;
    const int a2 = axis == 0 ? f.d.x : axis == 1 ? f.d.x : f.d.y;
#pragma omp parallel
    {
      std::vector<float> line(n);
      std::vector<double> ext(n + 2 * radius);
#pragma omp for collapse(2)
      for (int p = 0; p < a1; ++p)
        for (int q = 0; q < a2; ++q) {
          size_t base;
          if (axis == 0) base = (size_t)p * f.d.x + q;           // p=y, q=x
          else if (axis == 1) base = (size_t)p * f.d.y * f.d.x + q;  // p=z, q=x
          else base = ((size_t)p * f.d.y + q) * f.d.x;           // p=z, q=y
          for (int i = 0; i < n; ++i) line[i] = f.v[base + i * stride];
          for (int i = -radius; i < n + radius; ++i) {
            double v;
            if (i >= 0 && i < n) v = line[i];
            else if (mode == Border::Constant) v = 0.0;
            else {  // reflect：d c b a | a b c d | d c b a
              int j = i;
              const int period = 2 * n;
              j = ((j % period) + period) % period;
              if (j >= n) j = period - 1 - j;
              v = line[j];
            }
            ext[i + radius] = v;
          }
          for (int i = 0; i < n; ++i) {
            double acc = 0;
            for (int k = 0; k <= 2 * radius; ++k) acc += w[k] * ext[i + k];
            f.v[base + i * stride] = (float)acc;
          }
        }
    }
  }
}

}  // namespace ctf
