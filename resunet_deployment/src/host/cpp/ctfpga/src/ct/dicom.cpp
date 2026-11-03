#include "ct/dicom.hpp"

#include <dirent.h>
#include <zlib.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <functional>
#include <map>
#include <memory>
#include <mutex>

#include <gdcmImageReader.h>
#include <gdcmReader.h>
#include <gdcmStringFilter.h>
#include <gdcmTag.h>

namespace ctf {
namespace {

// ---------- 数据源：目录或 ZIP ----------
struct Source {
  std::vector<std::string> names;  // 已按字节序排序，仅 .dcm
  std::function<std::vector<uint8_t>(size_t)> read;
};

bool ends_with_dcm(const std::string& n) {
  if (n.size() < 4) return false;
  std::string t = n.substr(n.size() - 4);
  for (auto& c : t) c = std::tolower((unsigned char)c);
  return t == ".dcm";
}

struct Zip {
  FILE* f = nullptr;
  struct Entry { std::string name; uint32_t method, csize, usize, lho; };
  std::vector<Entry> entries;
  ~Zip() { if (f) std::fclose(f); }
  void open(const std::string& path) {
    f = std::fopen(path.c_str(), "rb");
    if (!f) throw Error("无法打开 ZIP: " + path);
    std::fseek(f, 0, SEEK_END);
    long size = std::ftell(f);
    long scan = std::min<long>(size, 65557);
    std::vector<uint8_t> tail(scan);
    std::fseek(f, size - scan, SEEK_SET);
    if (std::fread(tail.data(), 1, scan, f) != (size_t)scan) throw Error("ZIP 读取失败");
    long eocd = -1;
    for (long i = scan - 22; i >= 0; --i)
      if (get_le32(&tail[i]) == 0x06054b50) { eocd = i; break; }
    if (eocd < 0) throw Error("不是有效 ZIP（缺少目录尾）");
    uint32_t count = get_le16(&tail[eocd + 10]);
    uint32_t cd_size = get_le32(&tail[eocd + 12]), cd_off = get_le32(&tail[eocd + 16]);
    if (cd_off == 0xFFFFFFFFu || count == 0xFFFF) throw Error("暂不支持 Zip64");
    std::vector<uint8_t> cd(cd_size);
    std::fseek(f, cd_off, SEEK_SET);
    if (std::fread(cd.data(), 1, cd_size, f) != cd_size) throw Error("ZIP 目录读取失败");
    size_t p = 0;
    for (uint32_t i = 0; i < count; ++i) {
      if (p + 46 > cd.size() || get_le32(&cd[p]) != 0x02014b50) throw Error("ZIP 目录损坏");
      Entry e;
      e.method = get_le16(&cd[p + 10]);
      e.csize = get_le32(&cd[p + 20]);
      e.usize = get_le32(&cd[p + 24]);
      uint32_t nl = get_le16(&cd[p + 28]), xl = get_le16(&cd[p + 30]), cl = get_le16(&cd[p + 32]);
      e.lho = get_le32(&cd[p + 42]);
      e.name.assign(reinterpret_cast<char*>(&cd[p + 46]), nl);
      entries.push_back(e);
      p += 46 + nl + xl + cl;
    }
  }
  std::vector<uint8_t> extract(const Entry& e) {
    uint8_t h[30];
    std::fseek(f, e.lho, SEEK_SET);
    if (std::fread(h, 1, 30, f) != 30 || get_le32(h) != 0x04034b50) throw Error("ZIP 本地头损坏");
    std::fseek(f, get_le16(h + 26) + get_le16(h + 28), SEEK_CUR);
    std::vector<uint8_t> comp(e.csize), out(e.usize);
    if (e.csize && std::fread(comp.data(), 1, e.csize, f) != e.csize) throw Error("ZIP 数据读取失败");
    if (e.method == 0) return comp;
    if (e.method != 8) throw Error("ZIP 压缩方法不支持");
    z_stream zs{};
    if (inflateInit2(&zs, -15) != Z_OK) throw Error("inflate 初始化失败");
    zs.next_in = comp.data(); zs.avail_in = e.csize;
    zs.next_out = out.data(); zs.avail_out = e.usize;
    int rc = inflate(&zs, Z_FINISH);
    inflateEnd(&zs);
    if (rc != Z_STREAM_END) throw Error("ZIP 解压失败: " + e.name);
    return out;
  }
};

Source open_source(const std::string& path) {
  Source s;
  size_t n = path.size();
  bool is_zip = n > 4 && (path.compare(n - 4, 4, ".zip") == 0 || path.compare(n - 4, 4, ".ZIP") == 0);
  if (is_zip) {
    auto zip = std::make_shared<Zip>();
    zip->open(path);
    std::vector<Zip::Entry> picked;
    for (auto& e : zip->entries) if (ends_with_dcm(e.name)) picked.push_back(e);
    std::sort(picked.begin(), picked.end(), [](auto& a, auto& b) { return a.name < b.name; });
    for (auto& e : picked) s.names.push_back(e.name);
    // ZIP 句柄含文件指针，读取串行化。
    auto lock = std::make_shared<std::mutex>();
    s.read = [zip, picked, lock](size_t i) {
      std::lock_guard<std::mutex> g(*lock);
      return zip->extract(picked[i]);
    };
  } else {
    DIR* d = opendir(path.c_str());
    if (!d) throw Error("无法打开 DICOM 目录: " + path);
    while (dirent* e = readdir(d)) if (ends_with_dcm(e->d_name)) s.names.push_back(e->d_name);
    closedir(d);
    std::sort(s.names.begin(), s.names.end());
    std::string base = path;
    s.read = [base, names = s.names](size_t i) { return read_file(join(base, names[i])); };
  }
  if (s.names.empty()) throw Error("No .dcm files found in " + path);
  return s;
}

// ---------- 内存流 ----------
struct MemBuf : std::streambuf {
  MemBuf(const uint8_t* d, size_t n) {
    char* p = const_cast<char*>(reinterpret_cast<const char*>(d));
    setg(p, p, p + n);
  }
  pos_type seekoff(off_type off, std::ios_base::seekdir dir, std::ios_base::openmode) override {
    char* b = eback();
    char* e = egptr();
    char* c = gptr();
    char* t = dir == std::ios_base::beg ? b + off : dir == std::ios_base::cur ? c + off : e + off;
    if (t < b || t > e) return pos_type(off_type(-1));
    setg(b, t, e);
    return pos_type(t - b);
  }
  pos_type seekpos(pos_type pos, std::ios_base::openmode m) override {
    return seekoff(off_type(pos), std::ios_base::beg, m);
  }
};

std::string trim(std::string s) {
  while (!s.empty() && (s.back() == ' ' || s.back() == '\0' || s.back() == '\n' || s.back() == '\r')) s.pop_back();
  size_t i = 0;
  while (i < s.size() && (s[i] == ' ' || s[i] == '\0')) ++i;
  return s.substr(i);
}

std::vector<double> parse_ds(const std::string& s) {
  std::vector<double> v;
  size_t i = 0;
  while (i <= s.size()) {
    size_t j = s.find('\\', i);
    if (j == std::string::npos) j = s.size();
    std::string t = trim(s.substr(i, j - i));
    if (!t.empty()) v.push_back(std::strtod(t.c_str(), nullptr));
    i = j + 1;
  }
  return v;
}

struct Slice {
  bool ok = false;  // CT 且含像素
  std::string uid;
  int rows = 0, cols = 0, frames = 1;
  std::vector<double> orient, spacing, pos;
  double slope = 1, intercept = 0;
  std::vector<int8_t> q;
};

Slice decode(const std::vector<uint8_t>& bytes) {
  Slice s;
  MemBuf mb(bytes.data(), bytes.size());
  std::istream is(&mb);
  gdcm::ImageReader ir;
  ir.SetStream(is);
  if (!ir.Read()) return s;
  gdcm::StringFilter sf;
  sf.SetFile(ir.GetFile());
  auto get = [&](uint16_t g, uint16_t e) { return trim(sf.ToString(gdcm::Tag(g, e))); };
  if (get(0x0008, 0x0060) != "CT") return s;
  const gdcm::Image& img = ir.GetImage();
  s.uid = get(0x0020, 0x000E);
  std::string nf = get(0x0028, 0x0008);
  s.frames = nf.empty() ? 1 : std::atoi(nf.c_str());
  s.rows = std::atoi(get(0x0028, 0x0010).c_str());
  s.cols = std::atoi(get(0x0028, 0x0011).c_str());
  s.orient = parse_ds(get(0x0020, 0x0037));
  s.spacing = parse_ds(get(0x0028, 0x0030));
  s.pos = parse_ds(get(0x0020, 0x0032));
  auto sl = parse_ds(get(0x0028, 0x1053));
  auto ic = parse_ds(get(0x0028, 0x1052));
  s.slope = sl.empty() ? 1.0 : sl[0];
  s.intercept = ic.empty() ? 0.0 : ic[0];
  if (s.frames != 1) { s.ok = true; return s; }  // 由上层报错
  const auto st = img.GetPixelFormat().GetScalarType();
  if (img.GetPixelFormat().GetBitsAllocated() != 16 ||
      (st != gdcm::PixelFormat::INT16 && st != gdcm::PixelFormat::UINT16))
    throw Error("仅支持 16 位 CT 像素");
  size_t n = (size_t)s.rows * s.cols;
  if (img.GetBufferLength() != n * 2) throw Error("像素缓冲长度与 Rows×Columns 不符");
  std::vector<int16_t> raw_s(n);
  img.GetBuffer(reinterpret_cast<char*>(raw_s.data()));
  const bool is_signed = st == gdcm::PixelFormat::INT16;
  const float fs = static_cast<float>(s.slope), fi = static_cast<float>(s.intercept);
  s.q.resize(n);
  const uint16_t* ru = reinterpret_cast<const uint16_t*>(raw_s.data());
  for (size_t i = 0; i < n; ++i) {
    float px = is_signed ? static_cast<float>(raw_s[i]) : static_cast<float>(ru[i]);
    float hu = px * fs + fi;
    s.q[i] = quantize_hu(hu);
  }
  s.ok = true;
  return s;
}

bool allclose(double a, double b, double atol, double rtol = 1e-5) {
  return std::fabs(a - b) <= atol + rtol * std::fabs(b);
}

}  // namespace

CtVolume load_ct_quantized(const std::string& data, const std::string& series_uid, const Progress& progress) {
  Source src = open_source(data);
  const size_t N = src.names.size();
  progress(fmt("读取 DICOM：%zu 个文件", N));
  std::vector<Slice> slices(N);
  std::string first_error;

  // GDCM 全局字典首次使用需串行初始化。
  slices[0] = decode(src.read(0));
  const int batch = 16;
  for (size_t b = 1; b < N; b += batch) {
    size_t e = std::min(N, b + batch);
    std::vector<std::vector<uint8_t>> bytes(e - b);
    for (size_t i = b; i < e; ++i) bytes[i - b] = src.read(i);
#pragma omp parallel for schedule(dynamic)
    for (long i = (long)b; i < (long)e; ++i) {
      try { slices[i] = decode(bytes[i - b]); }
      catch (const std::exception& ex) {
#pragma omp critical
        if (first_error.empty()) first_error = ex.what();
      }
    }
    if (!first_error.empty()) throw Error(first_error);
    progress(fmt("解码 %zu/%zu slices", e, N));
  }

  std::map<std::string, std::vector<size_t>> series;
  for (size_t i = 0; i < N; ++i) {
    if (!slices[i].ok) continue;
    if (slices[i].frames != 1) throw Error("Multi-frame DICOM is not supported: " + src.names[i]);
    series[slices[i].uid].push_back(i);
  }
  if (series.empty()) throw Error("No single-frame CT image series found");
  std::string uid = series_uid;
  if (uid.empty()) {
    if (series.size() != 1) throw Error("Found multiple CT series; specify --series-uid");
    uid = series.begin()->first;
  }
  if (!series.count(uid)) throw Error("Series UID " + uid + " was not found");
  std::vector<size_t> idx = series[uid];
  if (idx.size() < 2) throw Error("At least two CT slices are required to determine slice spacing");

  const Slice& first = slices[idx[0]];
  if (first.orient.size() != 6 || first.spacing.size() != 2) throw Error("Invalid DICOM orientation or pixel spacing");
  std::array<double, 3> col{first.orient[0], first.orient[1], first.orient[2]};
  std::array<double, 3> row{first.orient[3], first.orient[4], first.orient[5]};
  std::array<double, 3> normal{col[1] * row[2] - col[2] * row[1], col[2] * row[0] - col[0] * row[2],
                               col[0] * row[1] - col[1] * row[0]};
  auto norm3 = [](const std::array<double, 3>& v) { return std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]); };
  if (std::fabs(norm3(col) - 1) > 1e-3 + 1e-5 || std::fabs(norm3(row) - 1) > 1e-3 + 1e-5 ||
      std::fabs(norm3(normal) - 1) > 1e-3 + 1e-5 || first.spacing[0] <= 0 || first.spacing[1] <= 0)
    throw Error("Invalid DICOM direction vectors or pixel spacing");

  for (size_t i : idx) {
    const Slice& s = slices[i];
    bool bad = s.rows != first.rows || s.cols != first.cols || s.orient.size() != 6 || s.spacing.size() != 2;
    for (int k = 0; !bad && k < 6; ++k) bad = !allclose(s.orient[k], first.orient[k], 1e-4);
    for (int k = 0; !bad && k < 2; ++k) bad = !allclose(s.spacing[k], first.spacing[k], 1e-4);
    if (bad) throw Error("Inconsistent CT image shape, orientation or pixel spacing");
    if (s.pos.size() != 3) throw Error("Invalid DICOM image position");
  }

  std::vector<std::pair<double, size_t>> proj;
  for (size_t i : idx) {
    const auto& p = slices[i].pos;
    proj.push_back({p[0] * normal[0] + p[1] * normal[1] + p[2] * normal[2], i});
  }
  std::stable_sort(proj.begin(), proj.end(), [](auto& a, auto& b) { return a.first < b.first; });
  const size_t D = proj.size();
  std::vector<std::array<double, 3>> pos(D);
  for (size_t k = 0; k < D; ++k) {
    const auto& p = slices[proj[k].second].pos;
    pos[k] = {p[0], p[1], p[2]};
  }
  std::array<double, 3> step{0, 0, 0};
  for (size_t k = 1; k < D; ++k)
    for (int a = 0; a < 3; ++a) step[a] += pos[k][a] - pos[k - 1][a];
  for (int a = 0; a < 3; ++a) step[a] /= (double)(D - 1);
  double projected = step[0] * normal[0] + step[1] * normal[1] + step[2] * normal[2];
  bool even = projected > 0;
  double atol = std::max(0.1, projected * 0.02);
  for (size_t k = 1; even && k < D; ++k)
    for (int a = 0; a < 3; ++a)
      if (!allclose(pos[k][a] - pos[k - 1][a], step[a], atol)) even = false;
  if (!even) throw Error("Duplicate or unevenly spaced CT slices; inspect the DICOM series");

  CtVolume v;
  v.depth = (int)D; v.rows = first.rows; v.cols = first.cols;
  v.q.resize(D * (size_t)v.rows * v.cols);
  std::vector<double> slopes, intercepts;
  for (size_t k = 0; k < D; ++k) {
    const Slice& s = slices[proj[k].second];
    std::copy(s.q.begin(), s.q.end(), v.q.begin() + k * (size_t)v.rows * v.cols);
    slopes.push_back(s.slope);
    intercepts.push_back(s.intercept);
  }

  json affine = json::array();
  double A[3][4];
  for (int a = 0; a < 3; ++a) {
    A[a][0] = step[a];
    A[a][1] = row[a] * first.spacing[0];
    A[a][2] = col[a] * first.spacing[1];
    A[a][3] = pos[0][a];
  }
  for (int a = 0; a < 3; ++a) affine.push_back(json::array({A[a][0], A[a][1], A[a][2], A[a][3]}));
  affine.push_back(json::array({0.0, 0.0, 0.0, 1.0}));

  json positions = json::array();
  for (auto& p : pos) positions.push_back(json::array({p[0], p[1], p[2]}));
  char abs_path[4096];
  std::string source = realpath(data.c_str(), abs_path) ? abs_path : data;

  v.metadata = json::object();
  v.metadata["series_id"] = sha256_hex(uid.data(), uid.size()).substr(0, 16);
  v.metadata["shape_z_y_x"] = json::array({v.depth, v.rows, v.cols});
  v.metadata["dtype"] = "float32";
  v.metadata["value_unit"] = "HU";
  v.metadata["coordinate_system"] = "DICOM LPS";
  v.metadata["affine_z_y_x_to_lps_mm"] = affine;
  v.metadata["spacing_z_y_x_mm"] = json::array({projected, first.spacing[0], first.spacing[1]});
  v.metadata["slice_positions_lps_mm"] = positions;
  v.metadata["rescale_slope_by_slice"] = slopes;
  v.metadata["rescale_intercept_by_slice"] = intercepts;
  v.metadata["resampled"] = false;
  v.metadata["cropped"] = false;
  v.metadata["anatomical_z_direction"] = step[2] > 0 ? 1 : -1;
  v.metadata["slice_order_basis"] = "DICOM ImagePositionPatient projected onto ImageOrientationPatient normal";
  v.metadata["source_dicom"] = source;
  return v;
}

}  // namespace ctf
