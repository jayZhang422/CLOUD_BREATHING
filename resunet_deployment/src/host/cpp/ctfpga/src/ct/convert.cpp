#include "ct/convert.hpp"

#include <cmath>

#include "ct/vol2.hpp"
#ifdef CTFPGA_HAVE_GDCM
#include "ct/dicom.hpp"
#endif

namespace ctf {

const std::vector<std::string>& channel_names() {
  static const std::vector<std::string> v = {"LeftUpperLobe", "LeftLowerLobe", "RightUpperLobe",
                                             "RightMiddleLobe", "RightLowerLobe", "Bronchus",
                                             "PulmonaryArtery", "PulmonaryVenous", "LungTumor"};
  return v;
}

namespace {
std::string real_path(const std::string& p) {
  char buf[4096];
  return realpath(p.c_str(), buf) ? std::string(buf) : p;
}
}  // namespace

json prepare_ct(const std::string& data, const std::string& case_dir, const std::string& series_uid,
                const Progress& progress) {
  const std::string folder = join(case_dir, "input");
  const std::string path = join(folder, "ct_volume_int8.bin");
  const std::string meta_path = join(folder, "metadata.json");

  if (file_exists(meta_path)) {
    json meta = read_json(meta_path);
    const json want = series_uid.empty() ? json(nullptr) : json(series_uid);
    if (real_path(meta["source_dicom"].get<std::string>()) != real_path(data) ||
        meta.value("requested_series_uid", json(nullptr)) != want)
      throw Error("该 case 已属于其他 CT/series；请使用新的 --case-dir");
    const json& spec = meta["model_input"];
    uint64_t n = 1;
    for (auto& d : spec["shape"]) n *= d.get<uint64_t>();
    check_file(path, n, spec["sha256"].get<std::string>());
    progress("复用已校验 CT BIN");
    return meta;
  }

#ifdef CTFPGA_HAVE_GDCM
  progress("读取 DICOM 与物理坐标");
  CtVolume vol = load_ct_quantized(data, series_uid, progress);
  if (vol.rows != 512 || vol.cols != 512) throw Error("现有上传协议要求 512×512 的 CT 平面");
  make_dirs(folder);
  const std::string tmp = path + ".tmp";
  HashedWriter w(tmp);
  w.write(vol.q.data(), vol.q.size());
  const uint32_t crc = w.crc();
  const uint64_t bytes = w.position();
  const std::string sha = w.finish_hex();
  rename_file(tmp, path);

  json meta = vol.metadata;
  meta["requested_series_uid"] = series_uid.empty() ? json(nullptr) : json(series_uid);
  json mi = json::object();
  mi["file"] = "ct_volume_int8.bin";
  mi["dtype"] = "int8";
  mi["layout"] = "Z,Y,X";
  mi["shape"] = json::array({vol.depth, vol.rows, vol.cols});
  mi["bytes"] = bytes;
  mi["sha256"] = sha;
  mi["crc32"] = crc;
  mi["hu_clip"] = json::array({-1024.0, 1000.0});
  mi["channel_offsets_z"] = json::array({-1, 0, 1});
  mi["edge_policy"] = "repeat_boundary_slice";
  mi["mapping"] = "round((clip(HU)-hu_min)*255/(hu_max-hu_min))-128";
  meta["model_input"] = mi;
  write_json(meta_path, meta);
  progress(fmt("%d slices; %llu bytes", vol.depth, (unsigned long long)bytes));
  return meta;
#else
  (void)data; (void)series_uid;
  throw Error("本构建未包含 GDCM，无法读取 DICOM");
#endif
}

json make_job(const std::string& case_dir, uint64_t image_base, int batch_slices, bool transpose,
              const Progress& progress) {
  json meta = read_json(join(case_dir, "input/metadata.json"));
  const json& spec = meta["model_input"];
  uint64_t n = 1;
  for (auto& d : spec["shape"]) n *= d.get<uint64_t>();
  const std::string path = join(case_dir, "input/ct_volume_int8.bin");
  check_file(path, n, spec["sha256"].get<std::string>());
  const json& shape = spec["shape"];
  if (shape.size() != 3 || shape[1].get<int>() != 512 || shape[2].get<int>() != 512)
    throw Error("输入尺寸必须为 [Z,512,512]");
  const int depth = shape[0].get<int>();
  // 仿射矩阵合法性
  const json& A = meta["affine_z_y_x_to_lps_mm"];
  double m[3][3];
  for (int r = 0; r < 3; ++r)
    for (int c = 0; c < 3; ++c) {
      m[r][c] = A[r][c].get<double>();
      if (!std::isfinite(m[r][c])) throw Error("输入尺寸、字节数或物理坐标元数据无效");
    }
  double det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
               m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
  if (std::fabs(det) < 1e-10) throw Error("输入尺寸、字节数或物理坐标元数据无效");
  if (spec["dtype"].get<std::string>() != "int8" || spec["layout"].get<std::string>() != "Z,Y,X" || depth < 1 ||
      depth > 65535 || batch_slices < 1 || batch_slices > 8 || image_base != IMAGE_BASE)
    throw Error("VOL2 整卷固件要求原生视图基址为 0x00400000，且输入布局、Slice_ID、批次有效");

  const std::string sha = spec["sha256"].get<std::string>();
  json in = json::object();
  in["file"] = "input/ct_volume_int8.bin";
  in["shape"] = shape;
  in["bytes"] = n;
  in["sha256"] = sha;
  json compact = prepare_vol2(case_dir, in, meta, transpose, progress);

  json input = json::object();
  input["file"] = "input/ct_volume_int8.bin";
  input["metadata"] = "input/metadata.json";
  for (const char* k : {"dtype", "layout", "shape", "bytes", "sha256"}) input[k] = spec[k];
  input["crc32"] = crc32_file(path);
  input["ddr_base"] = image_base;
  input["batch_slices"] = batch_slices;

  json rc = json::object();
  rc["format"] = "ct-segmentation-bitmask-v2";
  rc["dtype"] = "uint16";
  rc["byte_order"] = "little_endian";
  rc["layout"] = "Z,Y,X";
  rc["shape"] = shape;
  rc["bytes"] = n * 2;
  rc["channels"] = channel_names();
  json bits = json::array(), reserved = json::array();
  for (int i = 0; i < 9; ++i) bits.push_back(i);
  for (int i = 9; i < 16; ++i) reserved.push_back(i);
  rc["channel_bits"] = bits;
  rc["reserved_bits"] = reserved;
  rc["coordinate_system"] = "DICOM LPS millimetres";
  rc["affine_z_y_x_to_lps_mm"] = A;

  json job = json::object();
  job["format"] = "pc-fpga-volume-job-v2";
  job["status"] = "prepared";
  job["input"] = input;
  job["compact_bin"] = compact;
  job["models"] = json::array({"lobe", "airway", "vessel", "tumor"});
  job["result_contract"] = rc;
  job["execution"] = "VOL2 compact BIN upload; START/QUERY/READ/RELEASE";
  write_json(join(case_dir, "handoff/job.json"), job);

  const std::string tpl = join(case_dir, "handoff/result_ready.template.json");
  if (!file_exists(tpl)) {
    json t = json::object();
    t["format"] = "pc-fpga-result-ready-v2";
    t["state"] = "pending";
    t["transfer_id"] = nullptr;
    t["input_sha256"] = sha;
    t["tasks"] = job["models"];
    json r = rc;
    r["ddr_base"] = nullptr;
    r["sha256"] = nullptr;
    t["result"] = r;
    write_json(tpl, t);
  }
  return job;
}

}  // namespace ctf
