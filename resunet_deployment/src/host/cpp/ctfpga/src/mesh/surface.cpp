#include "mesh/surface.hpp"

#include "mesh/morph.hpp"

#include <vtkCellArray.h>
#include <vtkCellData.h>
#include <vtkCleanPolyData.h>
#include <vtkDataArray.h>
#include <vtkDiscreteMarchingCubes.h>
#include <vtkFlyingEdges3D.h>
#include <vtkFloatArray.h>
#include <vtkImageData.h>
#include <vtkPointData.h>
#include <vtkPolyDataConnectivityFilter.h>
#include <vtkUnsignedCharArray.h>
#include <vtkWindowedSincPolyDataFilter.h>

#include <algorithm>
#include <cmath>
#include <queue>
#include <unordered_map>

namespace ctf {

Spacing Affine::spacing() const {
  Spacing s{};
  for (int c = 0; c < 3; ++c) {
    double q = 0;
    for (int r = 0; r < 3; ++r) q += m[r][c] * m[r][c];
    s[c] = std::sqrt(q);
  }
  return s;
}

double Affine::det_zyx_reversed() const {
  double a[3][3];
  for (int r = 0; r < 3; ++r)
    for (int c = 0; c < 3; ++c) a[r][c] = m[r][2 - c];
  return a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
         a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]);
}

Affine affine_from_json(const json& j) {
  Affine A{};
  for (int r = 0; r < 3; ++r)
    for (int c = 0; c < 4; ++c) A.m[r][c] = j[r][c].get<double>();
  return A;
}

namespace {

// 体素下标 (z,y,x) → LPS
inline void to_world(const Affine& A, double z, double y, double x, double out[3]) {
  for (int r = 0; r < 3; ++r) out[r] = A.m[r][0] * z + A.m[r][1] * y + A.m[r][2] * x + A.m[r][3];
}

void remove_degenerate(std::vector<int64_t>& tris) {
  size_t w = 0;
  for (size_t f = 0; f + 2 < tris.size(); f += 3) {
    if (tris[f] == tris[f + 1] || tris[f] == tris[f + 2] || tris[f + 1] == tris[f + 2]) continue;
    tris[w++] = tris[f]; tris[w++] = tris[f + 1]; tris[w++] = tris[f + 2];
  }
  tris.resize(w);
}

// 对 float 体积在 level 处提取等值面。返回顶点（体素下标 z,y,x，未加偏移）与三角形。
void iso_surface(const Vol<float>& f, double level, std::vector<double>& pts_zyx, std::vector<int64_t>& tris) {
  auto img = vtkSmartPointer<vtkImageData>::New();
  img->SetDimensions(f.d.x, f.d.y, f.d.z);
  img->SetSpacing(1, 1, 1);
  img->SetOrigin(0, 0, 0);
  auto arr = vtkSmartPointer<vtkFloatArray>::New();
  arr->SetName("f");
  arr->SetNumberOfComponents(1);
  arr->SetNumberOfTuples(f.v.size());
  std::memcpy(arr->GetPointer(0), f.v.data(), f.v.size() * sizeof(float));
  img->GetPointData()->SetScalars(arr);
  auto fe = vtkSmartPointer<vtkFlyingEdges3D>::New();
  fe->SetInputData(img);
  fe->SetValue(0, level);
  fe->ComputeNormalsOff();
  fe->ComputeGradientsOff();
  fe->ComputeScalarsOff();
  fe->Update();
  std::vector<double> p;
  poly_to_arrays(fe->GetOutput(), p, tris);
  pts_zyx.resize(p.size());
  for (size_t i = 0; i < p.size() / 3; ++i) {
    pts_zyx[3 * i] = p[3 * i + 2];
    pts_zyx[3 * i + 1] = p[3 * i + 1];
    pts_zyx[3 * i + 2] = p[3 * i];
  }
  remove_degenerate(tris);
}

Vol<float> padded_float(const Mask& m, const Box& b, const std::array<int, 3>& pad) {
  Dims d{b.hi[0] - b.lo[0] + 2 * pad[0], b.hi[1] - b.lo[1] + 2 * pad[1], b.hi[2] - b.lo[2] + 2 * pad[2]};
  Vol<float> f(d, 0.f);
  for (int z = b.lo[0]; z < b.hi[0]; ++z)
    for (int y = b.lo[1]; y < b.hi[1]; ++y)
      for (int x = b.lo[2]; x < b.hi[2]; ++x)
        f.at(z - b.lo[0] + pad[0], y - b.lo[1] + pad[1], x - b.lo[2] + pad[2]) = m.at(z, y, x) ? 1.f : 0.f;
  return f;
}

// 拓扑保持细化（序贯）：按到背景的距离由小到大删除简单点（26 连通前景 / 6 连通背景不变），保留端点。
// 结果是 1 体素宽的 3D 骨架，用来只保护血管中轴的连通性，其余边界交给平滑场自由移动。
Mask thin_skeleton(const Mask& m, const Spacing& sp) {
  Mask a = m;
  Mask in_q(m.d, 0);
  Edt e = edt(m, sp, false);
  const long sy = m.d.x, sz = (long)m.d.x * m.d.y;
  int off[27][3];
  int no = 0;
  for (int dz = -1; dz <= 1; ++dz)
    for (int dy = -1; dy <= 1; ++dy)
      for (int dx = -1; dx <= 1; ++dx) { off[no][0] = dz; off[no][1] = dy; off[no][2] = dx; ++no; }
  auto cell = [](int dz, int dy, int dx) { return (dz + 1) * 9 + (dy + 1) * 3 + (dx + 1); };
  auto is_simple = [&](size_t i, bool& endpoint) {
    bool c[27];
    int fg = 0;
    for (int k = 0; k < 27; ++k) {
      c[k] = a.v[(long)i + off[k][0] * sz + off[k][1] * sy + off[k][2]] != 0;
      if (k != 13 && c[k]) ++fg;
    }
    endpoint = fg <= 1;
    if (fg == 0) return false;
    bool seen[27] = {};
    int comps = 0;
    for (int k = 0; k < 27; ++k) {
      if (k == 13 || !c[k] || seen[k]) continue;
      if (++comps > 1) return false;
      int st[27], top = 0;
      st[top++] = k; seen[k] = true;
      while (top) {
        int q = st[--top];
        int qz = q / 9 - 1, qy = (q / 3) % 3 - 1, qx = q % 3 - 1;
        for (int dz = -1; dz <= 1; ++dz) for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
          int nz = qz + dz, ny = qy + dy, nx = qx + dx;
          if (nz < -1 || nz > 1 || ny < -1 || ny > 1 || nx < -1 || nx > 1) continue;
          int r = cell(nz, ny, nx);
          if (r == 13 || !c[r] || seen[r]) continue;
          seen[r] = true; st[top++] = r;
        }
      }
    }
    // 与 p 的 6 邻面相接、经 N18 内背景 6 连通可达的背景分量必须恰好 1 个
    bool bseen[27] = {};
    int bcomps = 0;
    const int faces6[6] = {cell(-1,0,0), cell(1,0,0), cell(0,-1,0), cell(0,1,0), cell(0,0,-1), cell(0,0,1)};
    static const int d6[6][3] = {{-1,0,0},{1,0,0},{0,-1,0},{0,1,0},{0,0,-1},{0,0,1}};
    for (int f : faces6) {
      if (c[f] || bseen[f]) continue;
      if (++bcomps > 1) return false;
      int st[27], top = 0;
      st[top++] = f; bseen[f] = true;
      while (top) {
        int q = st[--top];
        int qz = q / 9 - 1, qy = (q / 3) % 3 - 1, qx = q % 3 - 1;
        for (auto& d : d6) {
          int nz = qz + d[0], ny = qy + d[1], nx = qx + d[2];
          if (nz < -1 || nz > 1 || ny < -1 || ny > 1 || nx < -1 || nx > 1) continue;
          int r = cell(nz, ny, nx);
          if (r == 13 || c[r] || bseen[r]) continue;
          if (std::abs(nz) + std::abs(ny) + std::abs(nx) > 2) continue;  // 只取 N18
          bseen[r] = true; st[top++] = r;
        }
      }
    }
    return bcomps == 1;
  };
  using Item = std::pair<float, size_t>;
  std::priority_queue<Item, std::vector<Item>, std::greater<Item>> pq;
  auto border = [&](size_t i) {
    return !a.v[i - 1] || !a.v[i + 1] || !a.v[i - sy] || !a.v[i + sy] || !a.v[i - sz] || !a.v[i + sz];
  };
  for (int z = 1; z < m.d.z - 1; ++z)
    for (int y = 1; y < m.d.y - 1; ++y)
      for (int x = 1; x < m.d.x - 1; ++x) {
        size_t i = m.idx(z, y, x);
        if (a.v[i] && border(i)) { pq.push({e.d2.v[i], i}); in_q.v[i] = 1; }
      }
  while (!pq.empty()) {
    size_t i = pq.top().second;
    pq.pop();
    in_q.v[i] = 0;
    if (!a.v[i]) continue;
    bool endpoint = false;
    if (!is_simple(i, endpoint) || endpoint) continue;
    a.v[i] = 0;
    for (int k = 0; k < 27; ++k) {
      if (k == 13) continue;
      size_t j = (size_t)((long)i + off[k][0] * sz + off[k][1] * sy + off[k][2]);
      if (a.v[j] && !in_q.v[j]) { pq.push({e.d2.v[j], j}); in_q.v[j] = 1; }
    }
  }
  return a;
}

}  // namespace

json write_mask_stl(const Mask& mask, const Affine& A, const std::string& path, int taubin_iterations,
                    double sigma_mm, bool preserve_voxels, bool preserve_volume, bool signed_distance,
                    double sigma_z_mm, bool skeleton_clamp, bool match_volume, double min_level) {
  const size_t n = count(mask);
  if (n == 0 || n == mask.v.size()) throw Error("Cannot export an empty or all-foreground mask");
  double last_level = 0.0;
  std::vector<double> verts;  // 体素下标 (z,y,x)
  std::vector<int64_t> faces;
  const Spacing sp = A.spacing();
  if (sigma_mm > 0) {
    const double sz_mm = sigma_z_mm > 0 ? sigma_z_mm : sigma_mm;
    std::array<double, 3> sigma = {sz_mm / sp[0], sigma_mm / sp[1], sigma_mm / sp[2]};
    std::array<int, 3> pad;
    for (int a = 0; a < 3; ++a) pad[a] = (int)std::ceil(4 * sigma[a]) + 1;
    Vol<int32_t> lab;
    const int nc = label(mask, 3, lab);
    std::vector<int64_t> counts;
    std::vector<Box> boxes;
    label_stats(lab, nc, counts, boxes);
    for (int idx = 1; idx <= nc; ++idx) {
      const Box& b = boxes[idx];
      Mask comp(b.dims(), 0);
      for (int z = 0; z < comp.d.z; ++z)
        for (int y = 0; y < comp.d.y; ++y)
          for (int x = 0; x < comp.d.x; ++x)
            comp.at(z, y, x) = lab.at(b.lo[0] + z, b.lo[1] + y, b.lo[2] + x) == idx ? 1 : 0;
      Box local{{0, 0, 0}, {comp.d.z, comp.d.y, comp.d.x}};
      Vol<float> original = padded_float(comp, local, pad);
      Vol<float> field = original;
      const int64_t voxel_count = counts[idx];
      double level = 0.5;
      if (signed_distance) {
        // 有符号距离场：内部为正、外部为负，零等值面在体素边界。
        Mask in(original.d, 0), out_m(original.d, 0);
        for (size_t k = 0; k < original.v.size(); ++k) { in.v[k] = original.v[k] > .5f; out_m.v[k] = original.v[k] > .5f ? 0 : 1; }
        Edt ein = edt(in, sp, false), eout = edt(out_m, sp, false);
        const float h = (float)(0.5 * std::min({sp[0], sp[1], sp[2]}));
        for (size_t k = 0; k < field.v.size(); ++k)
          field.v[k] = in.v[k] ? std::sqrt(ein.d2.v[k]) - h : -(std::sqrt(eout.d2.v[k]) - h);
        gaussian_filter(field, sigma, Border::Reflect);
        if (skeleton_clamp) {  // 只保护 3D 骨架及其 1 体素邻域：中轴连通，边界台阶（环状纹）可被平滑掉
          Mask sk = thin_skeleton(in, sp);
          for (int z = 1; z < in.d.z - 1; ++z)
            for (int y = 1; y < in.d.y - 1; ++y)
              for (int x = 1; x < in.d.x - 1; ++x) {
                size_t k = in.idx(z, y, x);
                if (!in.v[k]) continue;
                bool near = false;
                for (int dz = -1; dz <= 1 && !near; ++dz)
                  for (int dy = -1; dy <= 1 && !near; ++dy)
                    for (int dx = -1; dx <= 1; ++dx)
                      if (sk.at(z + dz, y + dy, x + dx)) { near = true; break; }
                if (near) field.v[k] = std::max(field.v[k], 0.02f);
              }
        } else if (preserve_voxels) {  // 原体素中心不被挤出表面，细支不断开
          for (size_t k = 0; k < field.v.size(); ++k) if (in.v[k]) field.v[k] = std::max(field.v[k], 0.02f);
        }
        level = 0.0;
        if (match_volume) {  // 取等值面使体素数与原掩膜一致，避免血管整体变细/变粗
          std::vector<float> tmp = field.v;
          const size_t split = tmp.size() - (size_t)voxel_count;
          std::nth_element(tmp.begin(), tmp.begin() + split, tmp.end());
          const float hi = tmp[split];
          const float lo = *std::max_element(tmp.begin(), tmp.begin() + split);
          level = ((double)lo + (double)hi) / 2.0;
          if (level < min_level) level = min_level;  // 下限：防止过度膨胀把相邻分支之间的缝隙填成薄片
        }
      } else {
      gaussian_filter(field, sigma, Border::Constant);
      if (preserve_voxels)
        for (size_t k = 0; k < field.v.size(); ++k) field.v[k] = std::max(field.v[k], original.v[k] * .55f);
      if (preserve_volume) {
        std::vector<float> tmp = field.v;
        const size_t split = tmp.size() - (size_t)voxel_count;
        std::nth_element(tmp.begin(), tmp.begin() + split, tmp.end());
        const float hi = tmp[split];
        const float lo = *std::max_element(tmp.begin(), tmp.begin() + split);
        level = ((double)lo + (double)hi) / 2.0;
      }
      }
      last_level = level;
      if (*std::max_element(field.v.begin(), field.v.end()) <= level) { field = original; level = 0.5; }
      std::vector<double> p;
      std::vector<int64_t> t;
      iso_surface(field, level, p, t);
      const int64_t base = (int64_t)(verts.size() / 3);
      for (size_t i = 0; i < p.size() / 3; ++i) {
        verts.push_back(p[3 * i] - pad[0] + b.lo[0]);
        verts.push_back(p[3 * i + 1] - pad[1] + b.lo[1]);
        verts.push_back(p[3 * i + 2] - pad[2] + b.lo[2]);
      }
      for (int64_t v : t) faces.push_back(v + base);
    }
  } else {
    // 仅在掩膜包围盒（外加一圈 0）内提面：包围盒外全为 0，不产生面，结果与整幅体积一致。
    const Box b = bbox(mask);
    Vol<float> f = padded_float(mask, b, {1, 1, 1});
    iso_surface(f, 0.5, verts, faces);
    for (size_t i = 0; i < verts.size() / 3; ++i)
      for (int a = 0; a < 3; ++a) verts[3 * i + a] += b.lo[a] - 1;
  }
  if (faces.empty()) throw Error("行进立方体没有产生三角面");
  std::vector<double> world(verts.size());
  for (size_t i = 0; i < verts.size() / 3; ++i) to_world(A, verts[3 * i], verts[3 * i + 1], verts[3 * i + 2], &world[3 * i]);
  taubin_smooth(world, faces, taubin_iterations);
  json j = write_stl_arrays(path, world, faces);
  j["mesh_smoothing_iterations"] = taubin_iterations;
  j["surface_gaussian_sigma_mm"] = sigma_mm;
  j["preserve_voxel_connectivity"] = preserve_voxels;
  j["volume_compensated_surface_field"] = preserve_volume || match_volume;
  j["skeleton_clamp"] = skeleton_clamp;
  j["iso_level_mm"] = last_level;
  j["iso_level_floor_mm"] = min_level;
  j["surface_gaussian_sigma_z_mm"] = sigma_z_mm > 0 ? sigma_z_mm : sigma_mm;
  return j;
}

json write_joint_lobes(const std::vector<Mask>& lobes, const Affine& A, const std::string& dir, int iterations,
                       double maximum_move_mm) {
  make_dirs(dir);
  const Dims D = lobes[0].d;
  Mask any(D, 0);
  Vol<uint8_t> labels(D, 0);
#pragma omp parallel for
  for (long k = 0; k < (long)labels.v.size(); ++k)
    for (size_t i = 0; i < lobes.size(); ++i) if (lobes[i].v[k]) labels.v[k] = (uint8_t)(i + 1);
  // 只对非零标签的包围盒提面（四周留一圈 0）。空单元不产生面，三角形与顶点顺序不变。
  Mask nonzero(D, 0);
#pragma omp parallel for
  for (long k = 0; k < (long)labels.v.size(); ++k) nonzero.v[k] = labels.v[k] ? 1 : 0;
  const Box bb = bbox(nonzero);
  if (bb.empty()) return json::object();
  const int cz = bb.hi[0] - bb.lo[0], cy = bb.hi[1] - bb.lo[1], cx = bb.hi[2] - bb.lo[2];

  auto img = vtkSmartPointer<vtkImageData>::New();
  img->SetDimensions(cx + 2, cy + 2, cz + 2);
  img->SetOrigin(bb.lo[2] - 1, bb.lo[1] - 1, bb.lo[0] - 1);
  img->SetSpacing(1, 1, 1);
  auto sc = vtkSmartPointer<vtkUnsignedCharArray>::New();
  sc->SetName("labels");
  sc->SetNumberOfComponents(1);
  sc->SetNumberOfTuples((vtkIdType)(cz + 2) * (cy + 2) * (cx + 2));
  std::memset(sc->GetPointer(0), 0, sc->GetNumberOfTuples());
  for (int z = 0; z < cz; ++z)
    for (int y = 0; y < cy; ++y)
      std::memcpy(sc->GetPointer(0) + ((size_t)(z + 1) * (cy + 2) + (y + 1)) * (cx + 2) + 1,
                  &labels.v[labels.idx(bb.lo[0] + z, bb.lo[1] + y, bb.lo[2])], cx);
  img->GetPointData()->SetScalars(sc);

  auto mc = vtkSmartPointer<vtkDiscreteMarchingCubes>::New();
  mc->SetInputData(img);
  mc->GenerateValues((int)lobes.size(), 1, (double)lobes.size());
  mc->ComputeNormalsOff();
  mc->Update();
  vtkPolyData* mesh = mc->GetOutput();

  std::vector<double> pts;
  std::vector<int64_t> tris;
  poly_to_arrays(mesh, pts, tris);
  const size_t nv = pts.size() / 3;
  std::vector<double> original(pts.size());
  for (size_t i = 0; i < nv; ++i) to_world(A, pts[3 * i + 2], pts[3 * i + 1], pts[3 * i], &original[3 * i]);

  vtkDataArray* cls = mesh->GetCellData()->GetScalars();
  if (!cls) throw Error("离散行进立方体缺少单元标量");
  std::vector<uint8_t> classes(tris.size() / 3);
  for (size_t f = 0; f < classes.size(); ++f) classes[f] = (uint8_t)cls->GetComponent(f, 0);

  std::vector<double> smoothed_pts = original;
  if (iterations > 0) {
    Poly tmp = arrays_to_poly(original, tris);
    auto sm = vtkSmartPointer<vtkWindowedSincPolyDataFilter>::New();
    sm->SetInputData(tmp);
    sm->SetNumberOfIterations(iterations);
    sm->SetPassBand(.001);
    sm->NonManifoldSmoothingOn();
    sm->NormalizeCoordinatesOn();
    sm->BoundarySmoothingOff();
    sm->FeatureEdgeSmoothingOff();
    sm->Update();
    vtkPolyData* out = sm->GetOutput();
    if ((size_t)out->GetNumberOfPoints() != nv) throw Error("Sinc 平滑改变了顶点数");
    for (size_t i = 0; i < nv; ++i) out->GetPoint(i, &smoothed_pts[3 * i]);
  }
  std::vector<double> points(pts.size());
  double measured = 0;
  for (size_t i = 0; i < nv; ++i) {
    double d[3], len = 0;
    for (int a = 0; a < 3; ++a) { d[a] = smoothed_pts[3 * i + a] - original[3 * i + a]; len += d[a] * d[a]; }
    len = std::sqrt(len);
    measured = std::max(measured, len);
    const double scale = std::min(1.0, maximum_move_mm / std::max(len, 1e-8));
    for (int a = 0; a < 3; ++a) points[3 * i + a] = original[3 * i + a] + d[a] * scale;
  }

  static const char* names[5] = {"LeftUpperLobe", "LeftLowerLobe", "RightUpperLobe", "RightMiddleLobe", "RightLowerLobe"};
  // 五个肺叶的拆分、清理、写盘与质量检查彼此独立（各用自己的 VTK 对象），按标签并行。
  const int nl = (int)lobes.size();
  std::vector<json> per(nl);
  std::vector<std::string> errs(nl);
#pragma omp parallel for schedule(dynamic, 1)
  for (int label_id = 1; label_id <= nl; ++label_id) try {
    std::vector<int64_t> sel;
    for (size_t f = 0; f < classes.size(); ++f)
      if (classes[f] == label_id) {
        if (A.det_zyx_reversed() < 0) { sel.push_back(tris[3 * f]); sel.push_back(tris[3 * f + 2]); sel.push_back(tris[3 * f + 1]); }
        else { sel.push_back(tris[3 * f]); sel.push_back(tris[3 * f + 1]); sel.push_back(tris[3 * f + 2]); }
      }
    if (sel.empty()) continue;
    Poly single = arrays_to_poly(points, sel);
    sel.clear();
    sel.shrink_to_fit();
    auto clean = vtkSmartPointer<vtkCleanPolyData>::New();
    clean->SetInputData(single);
    clean->Update();
    json frag;
    Poly filtered = remove_small_surfaces(clean->GetOutput(), 5., &frag);
    const std::string path = join(dir, std::string(names[label_id - 1]) + ".stl");
    write_stl_binary(filtered, path);
    Quality q = mesh_quality(read_stl(path));
    if (q.boundary_nonmanifold() || q.volume_mm3 <= 0) throw Error(std::string(names[label_id - 1]) + ": invalid joint surface");
    json o = json::object();
    o["path"] = path;
    o["algorithm"] = "Joint discrete marching cubes + Windowed Sinc";
    o["surface_smoothing_iterations"] = iterations;
    o["surface_smoothing_passband"] = .001;
    o["maximum_move_mm"] = maximum_move_mm;
    o["measured_maximum_move_mm"] = measured;
    o["surface_fragment_filter"] = frag;
    o["output_faces"] = q.triangles;
    o["output_quality"] = q.to_json();
    per[label_id - 1] = o;
  } catch (const std::exception& ex) {
    errs[label_id - 1] = ex.what();
  }
  for (const auto& e : errs) if (!e.empty()) throw Error(e);
  json objects = json::object();
  for (int i = 0; i < nl; ++i) if (!per[i].is_null()) objects[names[i]] = per[i];
  return objects;
}

json smooth_surface(const std::string& input, const std::string& output, bool largest_surface,
                    double minimum_surface_volume_mm3, int iterations, double passband) {
  Poly raw = read_stl(input);
  auto cleaner = vtkSmartPointer<vtkCleanPolyData>::New();
  cleaner->SetInputData(raw);
  cleaner->Update();
  const int64_t original_faces = cleaner->GetOutput()->GetNumberOfPolys();
  Poly source = Poly::New();
  source->DeepCopy(cleaner->GetOutput());
  if (largest_surface) {
    auto outer = vtkSmartPointer<vtkPolyDataConnectivityFilter>::New();
    outer->SetInputData(raw);
    outer->SetExtractionModeToLargestRegion();
    outer->Update();
    auto c2 = vtkSmartPointer<vtkCleanPolyData>::New();
    c2->SetInputData(outer->GetOutput());
    c2->Update();
    source = Poly::New();
    source->DeepCopy(c2->GetOutput());
  }
  json surface_filter = json::object();
  if (minimum_surface_volume_mm3 > 0) source = remove_small_surfaces(source, minimum_surface_volume_mm3, &surface_filter);
  int64_t source_faces = source->GetNumberOfPolys();
  if (source_faces == 0) throw Error("STL has no triangles: " + input);

  Quality sq = mesh_quality(source);
  int64_t removed_internal = 0;
  if (sq.nonmanifold_edges) {
    std::vector<double> pts;
    std::vector<int64_t> tris;
    poly_to_arrays(source, pts, tris);
    const size_t nf = tris.size() / 3;
    struct Key { int64_t a, b, c; bool operator==(const Key& o) const { return a == o.a && b == o.b && c == o.c; } };
    struct H { size_t operator()(const Key& k) const { return std::hash<int64_t>()(k.a * 1000003 ^ k.b * 998244353 ^ k.c); } };
    std::unordered_map<Key, int, H> group;
    std::vector<int> gid(nf);
    std::vector<int> gcount;
    std::vector<int> gwind;
    for (size_t f = 0; f < nf; ++f) {
      int64_t t[3] = {tris[3 * f], tris[3 * f + 1], tris[3 * f + 2]};
      const bool odd = (t[0] > t[1]) ^ (t[0] > t[2]) ^ (t[1] > t[2]);
      std::sort(t, t + 3);
      Key k{t[0], t[1], t[2]};
      auto it = group.find(k);
      if (it == group.end()) { it = group.emplace(k, (int)gcount.size()).first; gcount.push_back(0); gwind.push_back(0); }
      gid[f] = it->second;
      ++gcount[it->second];
      gwind[it->second] += odd ? -1 : 1;
    }
    std::vector<int64_t> keep;
    for (size_t f = 0; f < nf; ++f) {
      const bool cancel = gcount[gid[f]] == 2 && gwind[gid[f]] == 0;
      if (cancel) { ++removed_internal; continue; }
      keep.push_back(tris[3 * f]); keep.push_back(tris[3 * f + 1]); keep.push_back(tris[3 * f + 2]);
    }
    if (removed_internal) {
      source = arrays_to_poly(pts, keep);
      source_faces = (int64_t)(keep.size() / 3);
      sq = mesh_quality(source);
    }
  }

  auto smoother = vtkSmartPointer<vtkWindowedSincPolyDataFilter>::New();
  smoother->SetInputData(source);
  smoother->SetNumberOfIterations(iterations);
  smoother->SetPassBand(passband);
  smoother->NormalizeCoordinatesOn();
  smoother->FeatureEdgeSmoothingOff();
  smoother->BoundarySmoothingOff();
  smoother->NonManifoldSmoothingOff();
  smoother->Update();
  make_dirs(parent_dir(output));
  write_stl_binary(smoother->GetOutput(), output);
  Poly result = read_stl(output);
  Quality before = mesh_quality(source), after = mesh_quality(result);
  bool fallback = false;
  std::string algorithm = "Model surface cleanup + Windowed Sinc (no reduction)";
  if (after.boundary_nonmanifold() || after.components != before.components) {
    write_stl_binary(source, output);
    result = read_stl(output);
    after = mesh_quality(result);
    algorithm = "Unreduced surface (saved reduced STL failed mesh quality check)";
    fallback = true;
    if (after.boundary_nonmanifold() || after.components != before.components)
      throw Error("Source STL failed surface topology checks; inspect source and output");
  }
  json j = json::object();
  j["path"] = output;
  j["algorithm"] = algorithm;
  j["volume_preservation"] = false;
  j["surface_smoothing"] = "VTK Windowed Sinc";
  j["surface_smoothing_iterations"] = fallback ? 0 : iterations;
  j["surface_smoothing_passband"] = passband;
  j["source_faces"] = source_faces;
  j["original_source_faces"] = original_faces;
  j["removed_coincident_internal_faces"] = removed_internal;
  j["largest_surface_only"] = largest_surface;
  j["surface_fragment_filter"] = surface_filter;
  j["reduction_applied"] = false;
  j["output_faces"] = result->GetNumberOfPolys();
  j["source_quality"] = before.to_json();
  j["output_quality"] = after.to_json();
  j["volume_change_percent"] = 100.0 * (after.volume_mm3 / before.volume_mm3 - 1.0);
  return j;
}

}  // namespace ctf
