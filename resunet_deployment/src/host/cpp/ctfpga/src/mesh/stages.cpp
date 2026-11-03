#include "mesh/stages.hpp"

#include <vtkQuadricDecimation.h>

#include <algorithm>
#include <cmath>
#include <unistd.h>
#ifdef _OPENMP
#include <omp.h>
#endif

#include "ct/convert.hpp"
#include "mesh/mesh_io.hpp"
#include "mesh/repair.hpp"
#include "mesh/surface.hpp"
#include "mesh/decimate.hpp"
#include "net/volume_ctl.hpp"

namespace ctf {
namespace {

std::string category(int i) { return i < 5 ? "lobes" : i == 5 ? "airway" : i < 8 ? "vessels" : "tumor"; }

std::string new_output(const std::string& dir) {
  if (file_exists(join(dir, "manifest.json"))) throw Error("该阶段已发布，请指定新输出目录：" + dir);
  make_dirs(dir);
  return dir;
}

std::string real_dir(const std::string& p) {
  char buf[4096];
  return realpath(p.c_str(), buf) ? std::string(buf) : p;
}

bool close_enough(const json& a, const json& b) {
  for (int r = 0; r < 4; ++r)
    for (int c = 0; c < 4; ++c)
      if (std::fabs(a[r][c].get<double>() - b[r][c].get<double>()) > 1e-8 + 1e-5 * std::fabs(b[r][c].get<double>())) return false;
  return true;
}

void set_threads(const MeshOpts& o) {
#ifdef _OPENMP
  if (o.threads > 0) omp_set_num_threads(o.threads);
#else
  (void)o;
#endif
}

void checked_file(const std::string& root, const std::string& rel, const std::string& sha) {
  const std::string p = join(root, rel);
  if (rel.find("..") != std::string::npos) throw Error("阶段清单路径超出输入目录");
  check_file(p, file_size(p), sha);
}

// 二次误差减面（就地）。拓扑/体积未通过检查则保留原文件。
json reduce_in_place(const std::string& path, int target_faces, double volume_limit) {
  Poly mesh = read_stl(path);
  Quality before = mesh_quality(mesh);
  json j = json::object();
  j["target_faces"] = target_faces;
  j["faces_before"] = before.triangles;
  if (before.triangles <= target_faces) { j["accepted"] = false; j["reason"] = "already below target"; return j; }
  auto dec = vtkSmartPointer<vtkQuadricDecimation>::New();
  dec->SetInputData(mesh);
  dec->SetTargetReduction(1 - (double)target_faces / (double)before.triangles);
  dec->SetVolumePreservation(true);
  dec->Update();
  const std::string tmp = path + ".tmp";
  write_stl_binary(dec->GetOutput(), tmp);
  Quality after = mesh_quality(read_stl(tmp));
  const bool ok = after.boundary_nonmanifold() == 0 && after.components == before.components && before.volume_mm3 > 0 &&
                  std::fabs(after.volume_mm3 / before.volume_mm3 - 1) <= volume_limit;
  j["accepted"] = ok;
  j["faces_after"] = after.triangles;
  j["volume_change_percent"] = 100 * (after.volume_mm3 / before.volume_mm3 - 1);
  if (ok) rename_file(tmp, path); else remove_file(tmp);
  return j;
}

}  // namespace

json bin_to_stl(const std::string& prediction_dir, const std::string& out_dir, const MeshOpts& o, const Progress& progress) {
  set_threads(o);
  const json meta = read_json(join(prediction_dir, "metadata.json"));
  if (meta.value("format", "") != "ct-segmentation-bitmask-v2")
    throw Error("仅支持 ct-segmentation-bitmask-v2 预测；旧 v1 请用 Python 版转换");
  if (meta["dtype"] != "uint16" || meta["byte_order"] != "little_endian" || meta["layout"] != "Z,Y,X" ||
      meta["coordinate_system"] != "DICOM LPS millimetres")
    throw Error("Unsupported packed segmentation contract or CT affine");
  const Dims D{meta["shape"][0].get<int>(), meta["shape"][1].get<int>(), meta["shape"][2].get<int>()};
  const std::string pred_path = join(prediction_dir, meta["file"].get<std::string>());
  if (file_size(pred_path) != D.n() * 2 || meta["bytes"].get<uint64_t>() != D.n() * 2)
    throw Error("Packed segmentation byte count does not match dimensions");
  progress("校验预测 BIN");
  if (sha256_file(pred_path) != meta["sha256"].get<std::string>()) throw Error("Packed segmentation SHA256 mismatch");
  const Affine A = affine_from_json(meta["affine_z_y_x_to_lps_mm"]);
  const Spacing sp = A.spacing();

  // 展开九个掩膜；逐层校验位合法性。
  progress("展开九结构掩膜");
  std::vector<Mask> raw(9, Mask(D, 0));
  {
    FILE* f = std::fopen(pred_path.c_str(), "rb");
    if (!f) throw Error("无法打开预测 BIN");
    std::vector<uint16_t> plane((size_t)D.y * D.x);
    for (int z = 0; z < D.z; ++z) {
      if (std::fread(plane.data(), 2, plane.size(), f) != plane.size()) { std::fclose(f); throw Error("预测 BIN 读取失败"); }
      if (validate_bits(plane.data(), plane.size()) >= 0) { std::fclose(f); throw Error("Invalid reserved bits or overlapping lobe/artery-vein labels"); }
      for (size_t i = 0; i < plane.size(); ++i) {
        const uint16_t v = plane[i];
        if (!v) continue;
        for (int c = 0; c < 9; ++c) if (v & (1u << c)) raw[c].v[(size_t)z * plane.size() + i] = 1;
      }
    }
    std::fclose(f);
  }
  std::vector<int64_t> original_counts(9);
  for (int i = 0; i < 9; ++i) original_counts[i] = (int64_t)count(raw[i]);

  // CT
  std::string meta_path = o.ct_metadata;
  const json prov = meta.contains("provenance") ? meta["provenance"] : json::object();
  if (meta_path.empty() && prov.contains("input_metadata")) meta_path = prov["input_metadata"].get<std::string>();
  if (meta_path.empty()) meta_path = join(parent_dir(real_dir(prediction_dir)), "input/metadata.json");
  if (!file_exists(meta_path)) throw Error("CT 修补需要匹配的 input/metadata.json；外部病例可用 --ct-metadata 指定");
  const json cm = read_json(meta_path);
  const json& spec = cm["model_input"];
  if (spec["dtype"] != "int8" || spec["hu_clip"][0].get<double>() != -1024. || spec["hu_clip"][1].get<double>() != 1000.)
    throw Error("CT 必须使用 Model 的 INT8/HU 编码");
  const std::string ct_path = join(parent_dir(meta_path), spec["file"].get<std::string>());
  progress("校验 CT BIN");
  const std::string ct_sha = sha256_file(ct_path);
  if (ct_sha != spec["sha256"].get<std::string>() || file_size(ct_path) != D.n()) throw Error("文件长度或 SHA256 不符：" + ct_path);
  if (prov.contains("input_sha256") && prov["input_sha256"].get<std::string>() != ct_sha) throw Error("CT SHA256 与预测 BIN 来源不一致");
  const Dims cd{spec["shape"][0].get<int>(), spec["shape"][1].get<int>(), spec["shape"][2].get<int>()};
  if (cd != D || !close_enough(meta["affine_z_y_x_to_lps_mm"], cm["affine_z_y_x_to_lps_mm"]))
    throw Error("CT 与预测 BIN 的网格/affine 不匹配");
  CtData ct;
  ct.d = D;
  ct.init_lut();
  {
    auto bytes = read_file(ct_path);
    ct.q.assign(reinterpret_cast<int8_t*>(bytes.data()), reinterpret_cast<int8_t*>(bytes.data()) + bytes.size());
  }
  progress("计算体部掩膜");
  Mask body = build_body(ct);

  const std::string out = new_output(out_dir);
  json report = json::object();
  report["stage"] = "BIN2STL";
  report["status"] = "complete";
  report["source_sha256"] = meta["sha256"];
  report["coordinate_system"] = "DICOM LPS millimetres";
  report["affine_z_y_x_to_lps_mm"] = meta["affine_z_y_x_to_lps_mm"];
  json ctref = json::object();
  ctref["metadata"] = real_dir(meta_path);
  ctref["file"] = real_dir(ct_path);
  ctref["sha256"] = ct_sha;
  report["ct_reference"] = ctref;
  report["synthetic_mask_only"] = false;
  report["objects"] = json::array();

  progress("CT-supported mask repair");
  Prepared P = prepare_masks(raw, body, ct, sp, out, progress, o.far_bridge_mm);
  raw.clear();
  for (auto it = P.details.begin(); it != P.details.end(); ++it) report[it.key()] = it.value();

  std::vector<Mask> lobes(P.masks.begin(), P.masks.begin() + 5);
  progress("联合肺叶提面");
  json joint = write_joint_lobes(lobes, A, join(out, "lobes"), 0);
  make_dirs(join(out, "masks"));
  const auto& names = channel_names();
  // 九个结构的掩膜写盘、血管/气道/肿瘤提面、质量检查与 SHA256 互相独立，并行执行；清单仍按固定顺序组装。
  struct Out { std::string mask_sha, stl_sha, error; int64_t voxels = 0, triangles = 0; double volume = 0; };
  std::vector<Out> res(9);
  for (int i = 0; i < 9; ++i) make_dirs(join(out, category(i)));
  progress("写出掩膜与 STL");
#pragma omp parallel for schedule(dynamic, 1)
  for (int i = 0; i < 9; ++i) {
    Out& r = res[i];
    try {
      const Mask& mask = P.masks[i];
      const std::string p = join(out, "masks/" + names[i] + ".npy");
      write_npy_u8(p, mask);
      r.mask_sha = sha256_file(p);
      r.voxels = (int64_t)count(mask);
      if (!r.voxels) continue;
      const std::string path = join(out, category(i) + "/" + names[i] + ".stl");
      const json& jc = joint;  // 并行区内只读访问
      const json* jq = i < 5 && jc.contains(names[i]) ? &jc.at(names[i]).at("output_quality") : nullptr;
      if (jq) {  // 肺叶 STL 已由联合提面写出并做过质量检查，直接复用其结果
        r.triangles = (*jq)["triangles"].get<int64_t>();
        r.volume = (*jq)["volume_mm3"].get<double>();
      } else {
        if (i >= 5) write_mask_stl(mask, A, path, 0, 0.0, false, false);
        Quality q = mesh_quality(read_stl(path));
        r.triangles = q.triangles;
        r.volume = q.volume_mm3;
      }
      r.stl_sha = sha256_file(path);
    } catch (const std::exception& ex) {
      r.error = ex.what();
    }
  }
  for (const Out& r : res) if (!r.error.empty()) throw Error(r.error);
  for (int i = 0; i < 9; ++i) {
    const Out& r = res[i];
    const std::string mask_rel = "masks/" + names[i] + ".npy";
    json e = json::object();
    e["name"] = names[i];
    e["category"] = category(i);
    e["raw_voxels"] = original_counts[i];
    e["voxels"] = r.voxels;
    e["repair"] = P.repairs[i];
    e["mask_file"] = mask_rel;
    e["mask_sha256"] = r.mask_sha;
    if (!r.voxels) {
      e["status"] = "empty_prediction";
      e["empty_reason"] = original_counts[i] ? "empty after repair" : "empty input";
      report["objects"].push_back(e);
      continue;
    }
    e["status"] = "exported";
    e["file"] = category(i) + "/" + names[i] + ".stl";
    e["sha256"] = r.stl_sha;
    e["triangles"] = r.triangles;
    e["volume_mm3"] = r.volume;
    if (i < 5) e["surface"] = joint[names[i]];
    report["objects"].push_back(e);
  }
  write_json(join(out, "manifest.json"), report);
  return report;
}

json smooth_meshes(const std::string& src_in, const std::string& out_dir, const MeshOpts& o, const Progress& progress) {
  set_threads(o);
  const std::string src = real_dir(src_in);
  const json manifest = read_json(join(src, "manifest.json"));
  if (manifest.value("status", "") != "complete" || !manifest.contains("affine_z_y_x_to_lps_mm"))
    throw Error("结构专用平滑需要新版 BIN2STL 目录（含修补掩膜）；请重新执行 bin2stl");
  const Affine A = affine_from_json(manifest["affine_z_y_x_to_lps_mm"]);
  const auto& names = channel_names();
  std::vector<Mask> masks;
  for (auto& e : manifest["objects"]) {
    checked_file(src, e["mask_file"].get<std::string>(), e["mask_sha256"].get<std::string>());
    masks.push_back(read_npy_u8(join(src, e["mask_file"].get<std::string>())));
    if (e["status"] != "empty_prediction") checked_file(src, e["file"].get<std::string>(), e["sha256"].get<std::string>());
  }
  if (masks.size() != 9) throw Error("平滑输入的九结构顺序不匹配");
  for (int i = 0; i < 9; ++i) if (manifest["objects"][i]["name"] != names[i]) throw Error("平滑输入的九结构顺序不匹配");

  const std::string out = new_output(out_dir);
  json report = json::object();
  report["stage"] = "Smooth";
  report["status"] = "complete";
  report["coordinate_system"] = "DICOM LPS millimetres";
  report["source_manifest_sha256"] = sha256_file(join(src, "manifest.json"));
  json params = json::object();
  params["lobe_iterations"] = 60;
  params["lobe_passband"] = .001;
  params["lobe_maximum_move_mm"] = 2.5;
  params["iterations"] = o.iterations;
  params["passband"] = o.passband;
  params["reduction_applied"] = false;
  params["vessel_thickness_refinement"] = "not ported (Python-only: skeleton-based adaptive smoothing)";
  report["parameters"] = params;
  report["objects"] = json::array();

  progress("Joint lobe surfaces; shared-vertex smoothing");
  std::vector<Mask> lobes(masks.begin(), masks.begin() + 5);
  json joint = write_joint_lobes(lobes, A, join(out, "lobes"), 60);
  const std::string tmp_dir = join(out, ".tmp_smooth");
  make_dirs(tmp_dir);
  for (int i = 0; i < 9; ++i) {
    const json& entry = manifest["objects"][i];
    progress(fmt("%d/9 %s", i + 1, names[i].c_str()));
    json item = json::object();
    for (auto it = entry.begin(); it != entry.end(); ++it)
      if (it.key() != "mask_file" && it.key() != "mask_sha256") item[it.key()] = it.value();
    if (entry["status"] == "empty_prediction") { report["objects"].push_back(item); continue; }
    const std::string rel = entry["file"].get<std::string>();
    const std::string target = join(out, rel);
    make_dirs(parent_dir(target));
    Quality before = mesh_quality(read_stl(join(src, rel)));
    if (i < 5) {
      item["smoothing"] = joint[names[i]];
    } else {
      const bool tumor = i == 8, vessel = i == 6 || i == 7;
      const std::string cand = join(tmp_dir, names[i] + ".stl");
      if (vessel) {
        item["surface"] = write_mask_stl(masks[i], A, cand, o.vessel_taubin, o.vessel_sigma_mm, true, false, true,
                                          o.vessel_sigma_z_mm, o.vessel_skeleton, o.vessel_match_volume, o.vessel_min_level_mm);
        item["smoothing"] = smooth_surface(cand, target, i != 7, 20., o.vessel_iterations, o.vessel_passband);
      } else if (i == 5) {
        item["surface"] = write_mask_stl(masks[i], A, cand, 0, o.airway_sigma_mm, true, false, true, o.airway_sigma_z_mm, false, false);
        item["smoothing"] = smooth_surface(cand, target, true, 20., o.iterations, o.passband);
      } else {
        item["surface"] = write_mask_stl(masks[i], A, cand, tumor ? o.tumor_taubin : 5, tumor ? o.tumor_sigma_mm : .45, !tumor, tumor);
        item["smoothing"] = smooth_surface(cand, target, i != 7, tumor ? 5. : 20., o.iterations, o.passband);
      }
      if (tumor && o.tumor_faces > 0) item["tumor_reduction"] = reduce_in_place(target, o.tumor_faces, 0.02);
    }
    Quality after = mesh_quality(read_stl(target));
    if (after.boundary_nonmanifold() || after.volume_mm3 <= 0) throw Error("平滑输出未通过闭合检查：" + target);
    item["status"] = "processed";
    item["source_sha256"] = entry["sha256"];
    item["sha256"] = sha256_file(target);
    item["before"] = before.to_json();
    item["after"] = after.to_json();
    item["triangles"] = after.triangles;
    item["volume_mm3"] = after.volume_mm3;
    item["volume_change_percent"] = 100 * (after.volume_mm3 / before.volume_mm3 - 1);
    report["objects"].push_back(item);
  }
  for (int i = 5; i < 9; ++i) remove_file(join(tmp_dir, names[i] + ".stl"));
  ::rmdir(tmp_dir.c_str());
  write_json(join(out, "manifest.json"), report);
  return report;
}

json cut_meshes(const std::string& src_in, const std::string& out_dir, const MeshOpts& o, const Progress& progress) {
  set_threads(o);
  const std::string src = real_dir(src_in);
  const json manifest = read_json(join(src, "manifest.json"));
  if (manifest.value("status", "") != "complete") throw Error("输入网格阶段尚未完成");
  const std::string out = new_output(out_dir);
  json report = json::object();
  report["stage"] = "Cut";
  report["status"] = "complete";
  report["source_manifest_sha256"] = sha256_file(join(src, "manifest.json"));
  report["coordinate_system"] = "DICOM LPS millimetres";
  report["max_total_volume_change"] = o.volume_limit;
  json params = json::object();
  params["max_faces"] = o.max_faces;
  report["parameters"] = params;
  report["objects"] = json::array();
  const size_t total = manifest["objects"].size();
  size_t idx = 0;
  for (auto& entry : manifest["objects"]) {
    progress(fmt("%zu/%zu %s", ++idx, total, entry["name"].get<std::string>().c_str()));
    json item = entry;
    if (entry["status"] == "empty_prediction") { report["objects"].push_back(item); continue; }
    const std::string rel = entry["file"].get<std::string>();
    if (rel.find("..") != std::string::npos) throw Error("STL 清单路径超出输入目录");
    const std::string source = join(src, rel);
    check_file(source, file_size(source), entry["sha256"].get<std::string>());
    Poly mesh = read_stl(source);
    Quality before = mesh_quality(mesh);
    if (before.boundary_nonmanifold()) throw Error("输入 STL 非闭合/非流形：" + source);
    const std::string name = entry["name"].get<std::string>();
    int goal = o.max_faces;
    int per = 0;
    if (name.size() >= 4 && name.compare(name.size() - 4, 4, "Lobe") == 0) per = o.cut_lobe_faces;
    else if (name == "Bronchus") per = o.cut_airway_faces;
    else if (name == "PulmonaryArtery") per = o.cut_artery_faces;
    else if (name == "PulmonaryVenous") per = o.cut_vein_faces;
    else if (name.rfind("LungTumor", 0) == 0) per = o.cut_tumor_faces;
    if (per > 0) goal = per;
    const std::string target = join(out, rel);
    make_dirs(parent_dir(target));
    const std::string tmp = target + ".tmp";
    // 自实现 QEM 折叠（保流形）；质量守卫拒绝时放宽目标面数（x1.25）重试，最多 4 次
    std::vector<double> pts0;
    std::vector<int64_t> tris0;
    poly_to_arrays(mesh, pts0, tris0);
    Quality after;
    bool accepted = false;
    int used_goal = goal;
    for (int attempt = 0; attempt < 4 && !accepted; ++attempt) {
      std::vector<double> pts = pts0;
      std::vector<int64_t> tris = tris0;
      qem_decimate(pts, tris, (size_t)used_goal);
      if (o.cut_smooth > 0) taubin_smooth(pts, tris, o.cut_smooth);
      write_stl_arrays(tmp, pts, tris);
      after = mesh_quality(read_stl(tmp));
      accepted = after.boundary_nonmanifold() == 0 && after.components == before.components && before.volume_mm3 > 0 &&
                 std::fabs(after.volume_mm3 / before.volume_mm3 - 1) <= o.volume_limit;
      if (!accepted) used_goal = (int)(used_goal * 1.25);
      if (used_goal >= before.triangles) break;
    }
    item["target_faces"] = goal;
    item["used_target_faces"] = used_goal;
    json rejected_candidate;
    if (!accepted) {
      rejected_candidate = after.to_json();  // 记录被拒绝的减面结果，便于判断是哪项指标未过
      auto bytes = read_file(source);
      write_file_atomic(tmp, bytes.data(), bytes.size());
      after = mesh_quality(read_stl(tmp));
    }
    rename_file(tmp, target);
    item["status"] = accepted ? "processed" : "kept_source_quality_guard";
    if (!accepted) item["rejected_candidate"] = rejected_candidate;
    item["sha256"] = sha256_file(target);
    item["source_sha256"] = entry["sha256"];
    item["before"] = before.to_json();
    item["after"] = after.to_json();
    item["triangles"] = after.triangles;
    item["volume_mm3"] = after.volume_mm3;
    item["volume_change_percent"] = 100 * (after.volume_mm3 / before.volume_mm3 - 1);
    report["objects"].push_back(item);
  }
  write_json(join(out, "manifest.json"), report);
  return report;
}

}  // namespace ctf
