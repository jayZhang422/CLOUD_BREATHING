#include "mesh/mesh_io.hpp"

#include <vtkCellArray.h>
#include <vtkCleanPolyData.h>
#include <vtkDataArray.h>
#include <vtkDoubleArray.h>
#include <vtkFeatureEdges.h>
#include <vtkMassProperties.h>
#include <vtkPointData.h>
#include <vtkPoints.h>
#include <vtkPolyDataConnectivityFilter.h>
#include <vtkSTLReader.h>
#include <vtkSTLWriter.h>

#include <algorithm>
#include <cmath>

namespace ctf {

json Quality::to_json() const {
  json j = json::object();
  j["triangles"] = triangles;
  j["vertices"] = vertices;
  j["surface_components"] = components;
  j["boundary_edges"] = boundary_edges;
  j["nonmanifold_edges"] = nonmanifold_edges;
  j["boundary_nonmanifold_edges"] = boundary_nonmanifold();
  j["volume_mm3"] = volume_mm3;
  j["bounds_lps_mm"] = json::array({json::array({bounds[0], bounds[2], bounds[4]}),
                                    json::array({bounds[1], bounds[3], bounds[5]})});
  return j;
}

Poly read_stl(const std::string& path) {
  auto r = vtkSmartPointer<vtkSTLReader>::New();
  r->SetFileName(path.c_str());
  r->Update();
  Poly m = Poly::New();
  m->DeepCopy(r->GetOutput());
  if (m->GetNumberOfPolys() == 0) throw Error("STL 没有三角面：" + path);
  return m;
}

void write_stl_binary(vtkPolyData* mesh, const std::string& path) {
  auto w = vtkSmartPointer<vtkSTLWriter>::New();
  w->SetFileName(path.c_str());
  w->SetFileTypeToBinary();
  w->SetInputData(mesh);
  if (!w->Write()) throw Error("VTK could not write STL: " + path);
}

Quality mesh_quality(vtkPolyData* mesh) {
  Quality q;
  for (int pass = 0; pass < 2; ++pass) {
    auto e = vtkSmartPointer<vtkFeatureEdges>::New();
    e->SetInputData(mesh);
    e->SetBoundaryEdges(pass == 0);
    e->SetNonManifoldEdges(pass == 1);
    e->FeatureEdgesOff();
    e->ManifoldEdgesOff();
    e->Update();
    (pass == 0 ? q.boundary_edges : q.nonmanifold_edges) = e->GetOutput()->GetNumberOfCells();
  }
  auto c = vtkSmartPointer<vtkPolyDataConnectivityFilter>::New();
  c->SetInputData(mesh);
  c->SetExtractionModeToAllRegions();
  c->Update();
  q.components = c->GetNumberOfExtractedRegions();
  auto mp = vtkSmartPointer<vtkMassProperties>::New();
  mp->SetInputData(mesh);
  mp->Update();
  q.volume_mm3 = mp->GetVolume();
  q.triangles = mesh->GetNumberOfPolys();
  q.vertices = mesh->GetNumberOfPoints();
  mesh->GetBounds(q.bounds);
  return q;
}

void poly_to_arrays(vtkPolyData* mesh, std::vector<double>& pts, std::vector<int64_t>& tris) {
  const vtkIdType np = mesh->GetNumberOfPoints();
  pts.resize(3 * (size_t)np);
  for (vtkIdType i = 0; i < np; ++i) mesh->GetPoint(i, &pts[3 * (size_t)i]);
  tris.clear();
  vtkCellArray* polys = mesh->GetPolys();
  tris.reserve(3 * (size_t)polys->GetNumberOfCells());
  polys->InitTraversal();
  vtkIdType n;
  const vtkIdType* ids;
  while (polys->GetNextCell(n, ids)) {
    if (n != 3) continue;
    tris.push_back(ids[0]); tris.push_back(ids[1]); tris.push_back(ids[2]);
  }
}

Poly arrays_to_poly(const std::vector<double>& pts, const std::vector<int64_t>& tris) {
  auto points = vtkSmartPointer<vtkPoints>::New();
  points->SetDataTypeToDouble();
  points->SetNumberOfPoints(pts.size() / 3);
  for (size_t i = 0; i < pts.size() / 3; ++i) points->SetPoint(i, &pts[3 * i]);
  auto cells = vtkSmartPointer<vtkCellArray>::New();
  for (size_t i = 0; i < tris.size() / 3; ++i) {
    vtkIdType t[3] = {tris[3 * i], tris[3 * i + 1], tris[3 * i + 2]};
    cells->InsertNextCell(3, t);
  }
  Poly m = Poly::New();
  m->SetPoints(points);
  m->SetPolys(cells);
  return m;
}

Poly remove_small_surfaces(vtkPolyData* mesh, double minimum_mm3, json* info) {
  auto regions = vtkSmartPointer<vtkPolyDataConnectivityFilter>::New();
  regions->SetInputData(mesh);
  regions->SetExtractionModeToAllRegions();
  regions->ColorRegionsOn();
  regions->Update();
  vtkPolyData* colored = regions->GetOutput();
  const int count = regions->GetNumberOfExtractedRegions();
  std::vector<double> pts;
  std::vector<int64_t> tris;
  poly_to_arrays(colored, pts, tris);
  vtkDataArray* ids = colored->GetPointData()->GetArray("RegionId");
  if (!ids) throw Error("连通域着色缺少 RegionId");
  const size_t nv = pts.size() / 3, nf = tris.size() / 3;
  std::vector<int> lab(nv);
  for (size_t i = 0; i < nv; ++i) lab[i] = (int)ids->GetComponent(i, 0);
  std::vector<double> sizes(count, 0), cen(3 * (size_t)count, 0);
  for (size_t i = 0; i < nv; ++i) {
    sizes[lab[i]] += 1;
    for (int a = 0; a < 3; ++a) cen[3 * lab[i] + a] += pts[3 * i + a];
  }
  for (int r = 0; r < count; ++r)
    for (int a = 0; a < 3; ++a) cen[3 * r + a] /= std::max(sizes[r], 1.0);
  std::vector<double> vol(count, 0);
  for (size_t f = 0; f < nf; ++f) {
    const int r = lab[tris[3 * f]];
    double p[3][3];
    for (int k = 0; k < 3; ++k)
      for (int a = 0; a < 3; ++a) p[k][a] = pts[3 * tris[3 * f + k] + a] - cen[3 * r + a];
    const double cx = p[1][1] * p[2][2] - p[1][2] * p[2][1];
    const double cy = p[1][2] * p[2][0] - p[1][0] * p[2][2];
    const double cz = p[1][0] * p[2][1] - p[1][1] * p[2][0];
    vol[r] += (p[0][0] * cx + p[0][1] * cy + p[0][2] * cz) / 6.0;
  }
  for (double& v : vol) v = std::fabs(v);
  std::vector<char> keep(count, 0);
  int biggest = 0;
  for (int r = 0; r < count; ++r) {
    keep[r] = vol[r] >= minimum_mm3;
    if (vol[r] > vol[biggest]) biggest = r;
  }
  if (count) keep[biggest] = 1;
  std::vector<int64_t> sel;
  for (size_t f = 0; f < nf; ++f)
    if (keep[lab[tris[3 * f]]]) { sel.push_back(tris[3 * f]); sel.push_back(tris[3 * f + 1]); sel.push_back(tris[3 * f + 2]); }
  Poly filtered = arrays_to_poly(pts, sel);
  auto cleaner = vtkSmartPointer<vtkCleanPolyData>::New();
  cleaner->SetInputData(filtered);
  cleaner->Update();
  Poly out = Poly::New();
  out->DeepCopy(cleaner->GetOutput());
  if (info) {
    double removed = 0;
    int nrem = 0;
    for (int r = 0; r < count; ++r) if (!keep[r]) { removed += vol[r]; ++nrem; }
    json j = json::object();
    j["minimum_surface_volume_mm3"] = minimum_mm3;
    j["surface_components_before_filter"] = count;
    j["removed_surface_components"] = nrem;
    j["removed_surface_volume_mm3"] = removed;
    *info = j;
  }
  return out;
}

void taubin_smooth(std::vector<double>& pts, const std::vector<int64_t>& tris, int iterations) {
  if (iterations <= 0) return;
  const size_t nv = pts.size() / 3, nf = tris.size() / 3;
  std::vector<uint64_t> keys;
  keys.reserve(nf * 3);
  auto add = [&](int64_t a, int64_t b) {
    if (a > b) std::swap(a, b);
    keys.push_back(((uint64_t)a << 32) | (uint64_t)b);
  };
  for (size_t f = 0; f < nf; ++f) { add(tris[3 * f], tris[3 * f + 1]); add(tris[3 * f + 1], tris[3 * f + 2]); add(tris[3 * f + 2], tris[3 * f]); }
  std::sort(keys.begin(), keys.end());
  keys.erase(std::unique(keys.begin(), keys.end()), keys.end());
  std::vector<uint32_t> start(nv + 1, 0);
  for (uint64_t k : keys) { ++start[(k >> 32) + 1]; ++start[(k & 0xFFFFFFFFu) + 1]; }
  for (size_t i = 0; i < nv; ++i) start[i + 1] += start[i];
  std::vector<uint32_t> adj(start[nv]), fill(start.begin(), start.end() - 1);
  for (uint64_t k : keys) {
    const uint32_t a = k >> 32, b = k & 0xFFFFFFFFu;
    adj[fill[a]++] = b;
    adj[fill[b]++] = a;
  }
  std::vector<double> tmp(pts.size());
  for (int it = 0; it < iterations; ++it) {
    for (double factor : {0.5, -0.53}) {
#pragma omp parallel for
      for (long i = 0; i < (long)nv; ++i) {
        const uint32_t deg = start[i + 1] - start[i];
        double avg[3] = {0, 0, 0};
        for (uint32_t k = start[i]; k < start[i + 1]; ++k)
          for (int a = 0; a < 3; ++a) avg[a] += pts[3 * (size_t)adj[k] + a];
        for (int a = 0; a < 3; ++a) {
          const double m = deg ? avg[a] / deg : 0.0;  // 无邻居的顶点：平均为 0，与稀疏矩阵版一致
          tmp[3 * i + a] = pts[3 * i + a] + factor * (m - pts[3 * i + a]);
        }
      }
      pts.swap(tmp);
    }
  }
}

json write_stl_arrays(const std::string& path, const std::vector<double>& pts, std::vector<int64_t>& tris) {
  const size_t nf = tris.size() / 3;
  auto tri32 = [&](size_t f, float out[3][3]) {
    for (int k = 0; k < 3; ++k)
      for (int a = 0; a < 3; ++a) out[k][a] = (float)pts[3 * tris[3 * f + k] + a];
  };
  float acc = 0;  // float32 累加与 numpy einsum+sum 的量级一致，仅用于判定符号
  double signed_vol = 0;
  for (size_t f = 0; f < nf; ++f) {
    float t[3][3];
    tri32(f, t);
    const double cx = (double)t[1][1] * t[2][2] - (double)t[1][2] * t[2][1];
    const double cy = (double)t[1][2] * t[2][0] - (double)t[1][0] * t[2][2];
    const double cz = (double)t[1][0] * t[2][1] - (double)t[1][1] * t[2][0];
    signed_vol += (t[0][0] * cx + t[0][1] * cy + t[0][2] * cz);
  }
  (void)acc;
  signed_vol /= 6.0;
  if (signed_vol < 0)
    for (size_t f = 0; f < nf; ++f) std::swap(tris[3 * f + 1], tris[3 * f + 2]);

  std::vector<uint8_t> out(84 + nf * 50, 0);
  std::memcpy(out.data(), "CT lung STL (DICOM LPS millimetres)", 35);
  std::memset(out.data() + 35, ' ', 45);
  put_le32(&out[80], (uint32_t)nf);
  double bmin[3] = {1e300, 1e300, 1e300}, bmax[3] = {-1e300, -1e300, -1e300};
  for (size_t i = 0; i < pts.size() / 3; ++i)
    for (int a = 0; a < 3; ++a) { bmin[a] = std::min(bmin[a], pts[3 * i + a]); bmax[a] = std::max(bmax[a], pts[3 * i + a]); }
  for (size_t f = 0; f < nf; ++f) {
    float t[3][3];
    tri32(f, t);
    float u[3] = {t[1][0] - t[0][0], t[1][1] - t[0][1], t[1][2] - t[0][2]};
    float v[3] = {t[2][0] - t[0][0], t[2][1] - t[0][1], t[2][2] - t[0][2]};
    float n[3] = {u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]};
    const float len = std::sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    if (len > 0) for (float& c : n) c /= len; else n[0] = n[1] = n[2] = 0;
    uint8_t* rec = &out[84 + f * 50];
    std::memcpy(rec, n, 12);
    std::memcpy(rec + 12, t, 36);
  }
  write_file_atomic(path, out.data(), out.size());
  double vol = 0;
  for (size_t f = 0; f < nf; ++f) {
    float t[3][3];
    tri32(f, t);
    const double cx = (double)t[1][1] * t[2][2] - (double)t[1][2] * t[2][1];
    const double cy = (double)t[1][2] * t[2][0] - (double)t[1][0] * t[2][2];
    const double cz = (double)t[1][0] * t[2][1] - (double)t[1][1] * t[2][0];
    vol += (t[0][0] * cx + t[0][1] * cy + t[0][2] * cz);
  }
  json j = json::object();
  j["path"] = path;
  j["triangles"] = nf;
  j["vertices"] = pts.size() / 3;
  j["bounds_lps_mm"] = json::array({json::array({bmin[0], bmin[1], bmin[2]}), json::array({bmax[0], bmax[1], bmax[2]})});
  j["volume_mm3"] = std::fabs(vol / 6.0);
  return j;
}

}  // namespace ctf
