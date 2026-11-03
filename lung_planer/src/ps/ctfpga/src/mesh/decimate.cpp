#include "mesh/decimate.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <queue>

namespace ctf {
namespace {

using V3 = std::array<double, 3>;
// 对称 4×4 二次型：q0 q1 q2 q3 / q4 q5 q6 / q7 q8 / q9
using Quad = std::array<double, 10>;

inline V3 sub(const V3& a, const V3& b) { return {a[0] - b[0], a[1] - b[1], a[2] - b[2]}; }
inline V3 cross(const V3& a, const V3& b) {
  return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]};
}
inline double dot(const V3& a, const V3& b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

double quad_error(const Quad& q, const V3& v) {
  const double x = v[0], y = v[1], z = v[2];
  return q[0] * x * x + 2 * q[1] * x * y + 2 * q[2] * x * z + 2 * q[3] * x + q[4] * y * y + 2 * q[5] * y * z + 2 * q[6] * y +
         q[7] * z * z + 2 * q[8] * z + q[9];
}

struct Entry {
  double cost;
  int a, b;
  uint32_t va, vb;
  bool operator>(const Entry& o) const { return cost > o.cost; }
};

struct Mesh {
  std::vector<V3> P;
  std::vector<Quad> Q;
  std::vector<std::array<int, 3>> F;
  std::vector<char> fdead, vdead;
  std::vector<std::vector<int>> vf;
  std::vector<uint32_t> ver;
  size_t alive_faces = 0;
  double min_cos = 0.2;

  void neighbors(int v, std::vector<int>& out) const {
    out.clear();
    for (int f : vf[v]) {
      if (fdead[f]) continue;
      for (int k = 0; k < 3; ++k)
        if (F[f][k] != v) out.push_back(F[f][k]);
    }
    std::sort(out.begin(), out.end());
    out.erase(std::unique(out.begin(), out.end()), out.end());
  }

  // 最优折叠点：解二次型；病态时在 {a, b, 中点} 里取误差最小者。
  double place(int a, int b, V3& pos) const {
    Quad q;
    for (int i = 0; i < 10; ++i) q[i] = Q[a][i] + Q[b][i];
    const double m00 = q[0], m01 = q[1], m02 = q[2], m11 = q[4], m12 = q[5], m22 = q[7];
    const double det = m00 * (m11 * m22 - m12 * m12) - m01 * (m01 * m22 - m12 * m02) + m02 * (m01 * m12 - m11 * m02);
    const V3 mid = {(P[a][0] + P[b][0]) / 2, (P[a][1] + P[b][1]) / 2, (P[a][2] + P[b][2]) / 2};
    const double tr = std::fabs(m00) + std::fabs(m11) + std::fabs(m22);
    bool solved = false;
    if (std::fabs(det) > 1e-9 * tr * tr * tr) {
      const double r0 = -q[3], r1 = -q[6], r2 = -q[8];
      const double x = (r0 * (m11 * m22 - m12 * m12) - m01 * (r1 * m22 - m12 * r2) + m02 * (r1 * m12 - m11 * r2)) / det;
      const double y = (m00 * (r1 * m22 - m12 * r2) - r0 * (m01 * m22 - m12 * m02) + m02 * (m01 * r2 - r1 * m02)) / det;
      const double z = (m00 * (m11 * r2 - r1 * m12) - m01 * (m01 * r2 - r1 * m02) + r0 * (m01 * m12 - m11 * m02)) / det;
      const V3 s = {x, y, z};
      const V3 d = sub(s, mid);
      const V3 e = sub(P[a], P[b]);
      if (std::sqrt(dot(d, d)) <= 1.0 * std::sqrt(dot(e, e))) { pos = s; solved = true; }
    }
    if (!solved) {
      const V3 cand[3] = {P[a], P[b], mid};
      double best = 1e300;
      for (const V3& c : cand) {
        const double e = quad_error(q, c);
        if (e < best) { best = e; pos = c; }
      }
    }
    return std::max(0.0, quad_error(q, pos));
  }

  bool flips(int v, int other, const V3& pos) const {
    for (int f : vf[v]) {
      if (fdead[f]) continue;
      const auto& t = F[f];
      if (t[0] == other || t[1] == other || t[2] == other) continue;
      V3 p[3], n[3];
      for (int k = 0; k < 3; ++k) { p[k] = P[t[k]]; n[k] = (t[k] == v) ? pos : P[t[k]]; }
      const V3 no = cross(sub(p[1], p[0]), sub(p[2], p[0]));
      const V3 nn = cross(sub(n[1], n[0]), sub(n[2], n[0]));
      const double lo = std::sqrt(dot(no, no)), ln = std::sqrt(dot(nn, nn));
      if (ln < 1e-12) return true;
      if (lo > 0 && dot(no, nn) < min_cos * lo * ln) return true;
    }
    return false;
  }

  bool can_collapse(int a, int b, const V3& pos) const {
    int opp[2], cnt = 0;
    for (int f : vf[a]) {
      if (fdead[f]) continue;
      const auto& t = F[f];
      if (t[0] != b && t[1] != b && t[2] != b) continue;
      if (cnt == 2) return false;
      for (int k = 0; k < 3; ++k)
        if (t[k] != a && t[k] != b) opp[cnt] = t[k];
      ++cnt;
    }
    if (cnt != 2 || opp[0] == opp[1]) return false;
    std::vector<int> na, nb, common;
    neighbors(a, na);
    neighbors(b, nb);
    if (na.size() == 3 && nb.size() == 3) return false;
    std::set_intersection(na.begin(), na.end(), nb.begin(), nb.end(), std::back_inserter(common));
    if (common.size() != 2) return false;
    if (!((common[0] == opp[0] && common[1] == opp[1]) || (common[0] == opp[1] && common[1] == opp[0]))) return false;
    return !flips(a, b, pos) && !flips(b, a, pos);
  }

  void collapse(int a, int b, const V3& pos) {
    for (int i = 0; i < 10; ++i) Q[a][i] += Q[b][i];
    P[a] = pos;
    for (int f : vf[a]) {
      if (fdead[f]) continue;
      const auto& t = F[f];
      if (t[0] == b || t[1] == b || t[2] == b) { fdead[f] = 1; --alive_faces; }
    }
    for (int f : vf[b]) {
      if (fdead[f]) continue;
      auto& t = F[f];
      if (t[0] == b || t[1] == b || t[2] == b) {
        for (int k = 0; k < 3; ++k)
          if (t[k] == b) t[k] = a;
        vf[a].push_back(f);
      }
    }
    vf[b].clear();
    vdead[b] = 1;
    auto& L = vf[a];
    L.erase(std::remove_if(L.begin(), L.end(), [&](int f) { return fdead[f] != 0; }), L.end());
    ++ver[a];
  }
};

}  // namespace

size_t qem_decimate(std::vector<double>& pts, std::vector<int64_t>& tris, size_t target_faces, double min_normal_cos) {
  Mesh m;
  const size_t nv = pts.size() / 3, nf = tris.size() / 3;
  m.min_cos = min_normal_cos;
  m.P.resize(nv);
  m.Q.assign(nv, Quad{});
  m.F.resize(nf);
  m.fdead.assign(nf, 0);
  m.vdead.assign(nv, 0);
  m.vf.assign(nv, {});
  m.ver.assign(nv, 0);
  m.alive_faces = nf;
  for (size_t i = 0; i < nv; ++i) m.P[i] = {pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]};
  for (size_t f = 0; f < nf; ++f) {
    m.F[f] = {(int)tris[3 * f], (int)tris[3 * f + 1], (int)tris[3 * f + 2]};
    for (int k = 0; k < 3; ++k) m.vf[m.F[f][k]].push_back((int)f);
    const V3 n = cross(sub(m.P[m.F[f][1]], m.P[m.F[f][0]]), sub(m.P[m.F[f][2]], m.P[m.F[f][0]]));
    const double len = std::sqrt(dot(n, n));
    if (len < 1e-18) continue;
    const double area = len / 2;
    const V3 u = {n[0] / len, n[1] / len, n[2] / len};
    const double d = -dot(u, m.P[m.F[f][0]]);
    const Quad k = {u[0] * u[0], u[0] * u[1], u[0] * u[2], u[0] * d, u[1] * u[1], u[1] * u[2], u[1] * d, u[2] * u[2], u[2] * d, d * d};
    for (int c = 0; c < 3; ++c)
      for (int i = 0; i < 10; ++i) m.Q[m.F[f][c]][i] += area * k[i];
  }

  std::vector<int> nb;
  for (int pass = 0; pass < 4 && m.alive_faces > target_faces; ++pass) {
    std::priority_queue<Entry, std::vector<Entry>, std::greater<Entry>> heap;
    for (size_t v = 0; v < nv; ++v) {
      if (m.vdead[v]) continue;
      m.neighbors((int)v, nb);
      for (int w : nb) {
        if (w < (int)v) continue;
        V3 pos;
        const double c = m.place((int)v, w, pos);
        heap.push({c, (int)v, w, m.ver[v], m.ver[w]});
      }
    }
    size_t progressed = 0;
    while (m.alive_faces > target_faces && !heap.empty()) {
      const Entry e = heap.top();
      heap.pop();
      if (m.vdead[e.a] || m.vdead[e.b] || m.ver[e.a] != e.va || m.ver[e.b] != e.vb) continue;
      V3 pos;
      m.place(e.a, e.b, pos);
      if (!m.can_collapse(e.a, e.b, pos)) continue;
      m.collapse(e.a, e.b, pos);
      ++progressed;
      m.neighbors(e.a, nb);
      for (int w : nb) {
        V3 p2;
        const double c = m.place(e.a, w, p2);
        const int lo = std::min(e.a, w), hi = std::max(e.a, w);
        heap.push({c, lo, hi, m.ver[lo], m.ver[hi]});
      }
    }
    if (!progressed) break;
  }

  std::vector<int64_t> remap(nv, -1);
  std::vector<double> npts;
  std::vector<int64_t> ntris;
  ntris.reserve(3 * m.alive_faces);
  for (size_t f = 0; f < nf; ++f) {
    if (m.fdead[f]) continue;
    for (int k = 0; k < 3; ++k) {
      const int v = m.F[f][k];
      if (remap[v] < 0) {
        remap[v] = (int64_t)(npts.size() / 3);
        npts.insert(npts.end(), m.P[v].begin(), m.P[v].end());
      }
      ntris.push_back(remap[v]);
    }
  }
  pts.swap(npts);
  tris.swap(ntris);
  return tris.size() / 3;
}

}  // namespace ctf
