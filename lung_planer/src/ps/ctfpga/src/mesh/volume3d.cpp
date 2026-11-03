#include "mesh/volume3d.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>

namespace ctf {

Box bbox(const Mask& m) {
  Box b;
  int lo[3] = {m.d.z, m.d.y, m.d.x}, hi[3] = {-1, -1, -1};
  for (int z = 0; z < m.d.z; ++z) {
    bool any_z = false;
    for (int y = 0; y < m.d.y; ++y) {
      const uint8_t* row = &m.v[m.idx(z, y, 0)];
      int first = -1, last = -1;
      for (int x = 0; x < m.d.x; ++x)
        if (row[x]) { if (first < 0) first = x; last = x; }
      if (first < 0) continue;
      any_z = true;
      lo[1] = std::min(lo[1], y); hi[1] = std::max(hi[1], y);
      lo[2] = std::min(lo[2], first); hi[2] = std::max(hi[2], last);
    }
    if (any_z) { lo[0] = std::min(lo[0], z); hi[0] = std::max(hi[0], z); }
  }
  if (hi[0] < 0) return b;
  for (int a = 0; a < 3; ++a) { b.lo[a] = lo[a]; b.hi[a] = hi[a] + 1; }
  return b;
}

Box clip_box(const Box& b, const Dims& d) {
  Box r;
  const int lim[3] = {d.z, d.y, d.x};
  for (int a = 0; a < 3; ++a) { r.lo[a] = std::max(0, b.lo[a]); r.hi[a] = std::min(lim[a], b.hi[a]); }
  return r;
}

Box expand_box(const Box& b, const std::array<int, 3>& pad) {
  Box r = b;
  for (int a = 0; a < 3; ++a) { r.lo[a] -= pad[a]; r.hi[a] += pad[a]; }
  return r;
}

Mask crop(const Mask& m, const Box& b) {
  Mask out(b.dims(), 0);
  for (int z = 0; z < out.d.z; ++z) {
    const int sz = b.lo[0] + z;
    if (sz < 0 || sz >= m.d.z) continue;
    for (int y = 0; y < out.d.y; ++y) {
      const int sy = b.lo[1] + y;
      if (sy < 0 || sy >= m.d.y) continue;
      const int x0 = std::max(0, -b.lo[2]), x1 = std::min(out.d.x, m.d.x - b.lo[2]);
      if (x1 <= x0) continue;
      std::memcpy(&out.v[out.idx(z, y, x0)], &m.v[m.idx(sz, sy, b.lo[2] + x0)], x1 - x0);
    }
  }
  return out;
}

static void paste_impl(Mask& dst, const Mask& src, const Box& at, bool use_or) {
  for (int z = 0; z < src.d.z; ++z) {
    const int dz = at.lo[0] + z;
    if (dz < 0 || dz >= dst.d.z) continue;
    for (int y = 0; y < src.d.y; ++y) {
      const int dy = at.lo[1] + y;
      if (dy < 0 || dy >= dst.d.y) continue;
      const int x0 = std::max(0, -at.lo[2]), x1 = std::min(src.d.x, dst.d.x - at.lo[2]);
      if (x1 <= x0) continue;
      uint8_t* d = &dst.v[dst.idx(dz, dy, at.lo[2] + x0)];
      const uint8_t* s = &src.v[src.idx(z, y, x0)];
      if (use_or) for (int x = 0; x < x1 - x0; ++x) d[x] |= s[x];
      else std::memcpy(d, s, x1 - x0);
    }
  }
}
void paste(Mask& dst, const Mask& src, const Box& at) { paste_impl(dst, src, at, false); }
void paste_or(Mask& dst, const Mask& src, const Box& at) { paste_impl(dst, src, at, true); }

size_t count(const Mask& m) {
  size_t c = 0;
#pragma omp parallel for reduction(+ : c)
  for (long i = 0; i < (long)m.v.size(); ++i) c += m.v[i] != 0;
  return c;
}

Mask logical_and(const Mask& a, const Mask& b) {
  Mask r(a.d, 0);
#pragma omp parallel for
  for (long i = 0; i < (long)a.v.size(); ++i) r.v[i] = a.v[i] & b.v[i] ? 1 : 0;
  return r;
}
Mask logical_or(const Mask& a, const Mask& b) {
  Mask r(a.d, 0);
#pragma omp parallel for
  for (long i = 0; i < (long)a.v.size(); ++i) r.v[i] = (a.v[i] | b.v[i]) ? 1 : 0;
  return r;
}
Mask logical_andnot(const Mask& a, const Mask& b) {
  Mask r(a.d, 0);
#pragma omp parallel for
  for (long i = 0; i < (long)a.v.size(); ++i) r.v[i] = (a.v[i] && !b.v[i]) ? 1 : 0;
  return r;
}
void or_inplace(Mask& a, const Mask& b) {
#pragma omp parallel for
  for (long i = 0; i < (long)a.v.size(); ++i) a.v[i] = (a.v[i] | b.v[i]) ? 1 : 0;
}
void and_inplace(Mask& a, const Mask& b) {
#pragma omp parallel for
  for (long i = 0; i < (long)a.v.size(); ++i) a.v[i] = (a.v[i] & b.v[i]) ? 1 : 0;
}

// ---------------- 连通域（两遍扫描 + 并查集） ----------------
int label(const Mask& m, int connectivity, Vol<int32_t>& out) {
  out = Vol<int32_t>(m.d, 0);
  struct Off { int dz, dy, dx; };
  std::vector<Off> back;
  for (int dz = -1; dz <= 1; ++dz)
    for (int dy = -1; dy <= 1; ++dy)
      for (int dx = -1; dx <= 1; ++dx) {
        const bool earlier = dz < 0 || (dz == 0 && dy < 0) || (dz == 0 && dy == 0 && dx < 0);
        const int nz = (dz != 0) + (dy != 0) + (dx != 0);
        if (earlier && nz <= connectivity) back.push_back({dz, dy, dx});
      }
  std::vector<int32_t> parent(1, 0);
  auto find = [&](int32_t a) {
    while (parent[a] != a) { parent[a] = parent[parent[a]]; a = parent[a]; }
    return a;
  };
  for (int z = 0; z < m.d.z; ++z)
    for (int y = 0; y < m.d.y; ++y)
      for (int x = 0; x < m.d.x; ++x) {
        const size_t i = m.idx(z, y, x);
        if (!m.v[i]) continue;
        int32_t root = 0;
        for (const Off& o : back) {
          const int zz = z + o.dz, yy = y + o.dy, xx = x + o.dx;
          if (zz < 0 || yy < 0 || yy >= m.d.y || xx < 0 || xx >= m.d.x) continue;
          const int32_t l = out.v[m.idx(zz, yy, xx)];
          if (!l) continue;
          const int32_t r = find(l);
          if (!root) root = r;
          else if (r != root) { if (r < root) { parent[root] = r; root = r; } else parent[r] = root; }
        }
        if (!root) { root = (int32_t)parent.size(); parent.push_back(root); }
        out.v[i] = root;
      }
  // 压缩为按首次出现顺序的连续编号
  std::vector<int32_t> remap(parent.size(), 0);
  int n = 0;
  for (size_t l = 1; l < parent.size(); ++l)
    if (find((int32_t)l) == (int32_t)l) remap[l] = ++n;
  for (size_t l = 1; l < parent.size(); ++l) remap[l] = remap[find((int32_t)l)];
#pragma omp parallel for
  for (long i = 0; i < (long)out.v.size(); ++i) if (out.v[i]) out.v[i] = remap[out.v[i]];
  return n;
}

void label_stats(const Vol<int32_t>& lab, int n, std::vector<int64_t>& counts, std::vector<Box>& boxes) {
  counts.assign(n + 1, 0);
  boxes.assign(n + 1, Box());
  std::vector<char> seen(n + 1, 0);
  for (int z = 0; z < lab.d.z; ++z)
    for (int y = 0; y < lab.d.y; ++y)
      for (int x = 0; x < lab.d.x; ++x) {
        const int32_t l = lab.v[lab.idx(z, y, x)];
        if (!l) continue;
        ++counts[l];
        Box& b = boxes[l];
        if (!seen[l]) { seen[l] = 1; b.lo[0] = z; b.lo[1] = y; b.lo[2] = x; b.hi[0] = z + 1; b.hi[1] = y + 1; b.hi[2] = x + 1; }
        else {
          b.lo[0] = std::min(b.lo[0], z); b.hi[0] = std::max(b.hi[0], z + 1);
          b.lo[1] = std::min(b.lo[1], y); b.hi[1] = std::max(b.hi[1], y + 1);
          b.lo[2] = std::min(b.lo[2], x); b.hi[2] = std::max(b.hi[2], x + 1);
        }
      }
}

std::array<int, 3> ellipsoid_radii(double r, const Spacing& sp) {
  return {(int)std::ceil(r / sp[0]), (int)std::ceil(r / sp[1]), (int)std::ceil(r / sp[2])};
}

// ---------------- NPY ----------------
void write_npy_u8(const std::string& path, const Mask& m) {
  std::string hdr = fmt("{'descr': '|u1', 'fortran_order': False, 'shape': (%d, %d, %d), }", m.d.z, m.d.y, m.d.x);
  size_t total = 10 + hdr.size() + 1;
  hdr.append((64 - total % 64) % 64, ' ');
  hdr.push_back('\n');
  std::vector<uint8_t> out;
  out.reserve(10 + hdr.size() + m.v.size());
  const uint8_t magic[8] = {0x93, 'N', 'U', 'M', 'P', 'Y', 1, 0};
  out.insert(out.end(), magic, magic + 8);
  out.push_back(hdr.size() & 255);
  out.push_back(hdr.size() >> 8);
  out.insert(out.end(), hdr.begin(), hdr.end());
  out.insert(out.end(), m.v.begin(), m.v.end());
  write_file_atomic(path, out.data(), out.size());
}

Mask read_npy_u8(const std::string& path) {
  auto raw = read_file(path);
  if (raw.size() < 10 || std::memcmp(raw.data(), "\x93NUMPY", 6) != 0) throw Error("不是 NPY 文件: " + path);
  size_t hl, off;
  if (raw[6] == 1) { hl = get_le16(&raw[8]); off = 10; }
  else { hl = get_le32(&raw[8]); off = 12; }
  std::string h(reinterpret_cast<char*>(&raw[off]), hl);
  if (h.find("'|u1'") == std::string::npos || h.find("False") == std::string::npos) throw Error("仅支持 C 序 uint8 NPY");
  auto p = h.find("'shape': (");
  if (p == std::string::npos) throw Error("NPY 缺少 shape");
  int a = 0, b = 0, c = 0;
  if (std::sscanf(h.c_str() + p + 10, "%d, %d, %d", &a, &b, &c) != 3) throw Error("NPY 需要三维 shape");
  Mask m(Dims{a, b, c}, 0);
  if (raw.size() - off - hl != m.v.size()) throw Error("NPY 数据长度与 shape 不符");
  std::memcpy(m.v.data(), &raw[off + hl], m.v.size());
  return m;
}

}  // namespace ctf
