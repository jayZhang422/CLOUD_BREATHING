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

// 减面单个结构（可在并行区内调用：只读 entry，只写自己的输出文件）。
json cut_one(const json& entry, const std::string& src, const std::string& out, const MeshOpts& o) {
  json item = entry;
  if (entry["status"] == "empty_prediction") return item;
  StepTimer obj_tm;
  const std::string rel = entry["file"].get<std::string>();
  const std::string source = join(src, rel);
  check_file(source, file_size(source), entry["sha256"].get<std::string>());
  Poly mesh = read_stl(source);
  obj_tm.lap("hash_read_stl");
  // 上一阶段清单里的 after 就是对这个文件（SHA256 刚校验过）算的质量，直接复用；缺字段时重新计算。
  Quality before;
  if (!(entry.contains("after") && Quality::from_json(entry["after"], before))) before = mesh_quality(mesh);
  if (before.boundary_nonmanifold()) throw Error("输入 STL 非闭合/非流形：" + source);
  obj_tm.lap("source_quality");
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
  mesh = nullptr;  // 并行时尽早释放 VTK 网格
  obj_tm.lap("to_arrays");
  Quality after;
  bool accepted = false;
  int used_goal = goal;
  int attempts = 0;
  for (int attempt = 0; attempt < 4 && !accepted; ++attempt) {
    ++attempts;
    std::vector<double> pts = pts0;
    std::vector<int64_t> tris = tris0;
    qem_decimate(pts, tris, (size_t)used_goal);
    obj_tm.lap("qem_decimate");
    if (o.cut_smooth > 0) taubin_smooth(pts, tris, o.cut_smooth);
    obj_tm.lap("taubin");
    write_stl_arrays(tmp, pts, tris);
    obj_tm.lap("write_stl");
    after = mesh_quality(read_stl(tmp));
    obj_tm.lap("quality_guard");
    accepted = after.boundary_nonmanifold() == 0 && after.components == before.components && before.volume_mm3 > 0 &&
               std::fabs(after.volume_mm3 / before.volume_mm3 - 1) <= o.volume_limit;
    if (!accepted) used_goal = (int)(used_goal * 1.25);
    if (used_goal >= before.triangles) break;
  }
  item["attempts"] = attempts;
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
  obj_tm.lap("publish_hash");
  item["timing_seconds"] = obj_tm.out;
  item["source_sha256"] = entry["sha256"];
  item["before"] = before.to_json();
  item["after"] = after.to_json();
  item["triangles"] = after.triangles;
  item["volume_mm3"] = after.volume_mm3;
  item["volume_change_percent"] = 100 * (after.volume_mm3 / before.volume_mm3 - 1);
  return item;
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
  const json& objects = manifest["objects"];
  if (objects.size() != 9) throw Error("平滑输入的九结构顺序不匹配");
  for (int i = 0; i < 9; ++i) if (objects[i]["name"] != names[i]) throw Error("平滑输入的九结构顺序不匹配");
  StepTimer stage_tm;
  // 九个结构的掩膜读取、SHA256 校验与源网格质量互相独立，并行执行。
  std::vector<Mask> masks(9);
  std::vector<Quality> before(9);
  std::vector<std::string> read_errors(9);
#pragma omp parallel for schedule(dynamic, 1)
  for (int i = 0; i < 9; ++i) try {
    const json& e = objects[i];
    checked_file(src, e["mask_file"].get<std::string>(), e["mask_sha256"].get<std::string>());
    masks[i] = read_npy_u8(join(src, e["mask_file"].get<std::string>()));
    if (e["status"] == "empty_prediction") continue;
    checked_file(src, e["file"].get<std::string>(), e["sha256"].get<std::string>());
    // 肺叶的 BIN2STL 清单已带这个文件（SHA256 刚校验过）的质量，直接复用；其余结构重新计算。
    const bool reuse = e.contains("surface") && e["surface"].is_object() && e["surface"].contains("output_quality") &&
                       Quality::from_json(e["surface"]["output_quality"], before[i]);
    if (!reuse) before[i] = mesh_quality(read_stl(join(src, e["file"].get<std::string>())));
  } catch (const std::exception& ex) {
    read_errors[i] = ex.what();
  }
  for (const auto& e : read_errors) if (!e.empty()) throw Error(e);

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

  stage_tm.lap("read_inputs");
  progress("Joint lobe surfaces; shared-vertex smoothing");
  std::vector<Mask> lobes(masks.begin(), masks.begin() + 5);
  json joint_timing;
  json joint = write_joint_lobes(lobes, A, join(out, "lobes"), 60, 2.5, &joint_timing);
  stage_tm.lap("joint_lobes");
  report["joint_lobes_timing_seconds"] = joint_timing;
  const std::string tmp_dir = join(out, ".tmp_smooth");
  make_dirs(tmp_dir);
  for (int i = 0; i < 9; ++i) {
    const json& entry = objects[i];
    progress(fmt("%d/9 %s", i + 1, names[i].c_str()));
    StepTimer obj_tm;
    json item = json::object();
    for (auto it = entry.begin(); it != entry.end(); ++it)
      if (it.key() != "mask_file" && it.key() != "mask_sha256") item[it.key()] = it.value();
    if (entry["status"] == "empty_prediction") { report["objects"].push_back(item); continue; }
    const std::string rel = entry["file"].get<std::string>();
    const std::string target = join(out, rel);
    make_dirs(parent_dir(target));
    // 输出质量：肺叶取联合提面写盘后的检查结果，其余取 smooth_surface 对最终输出的检查结果；
    // 只有肿瘤减面被接受、文件被改写时才重新计算。
    Quality after;
    bool have_after = false;
    if (i < 5) {
      item["smoothing"] = joint[names[i]];
      have_after = joint[names[i]].is_object() && Quality::from_json(joint[names[i]]["output_quality"], after);
    } else {
      const bool tumor = i == 8, vessel = i == 6 || i == 7;
      const std::string cand = join(tmp_dir, names[i] + ".stl");
      if (vessel) {
        item["surface"] = write_mask_stl(masks[i], A, cand, o.vessel_taubin, o.vessel_sigma_mm, true, false, true,
                                          o.vessel_sigma_z_mm, o.vessel_skeleton, o.vessel_match_volume, o.vessel_min_level_mm);
        obj_tm.lap("mask_to_surface");
        item["smoothing"] = smooth_surface(cand, target, i != 7, 20., o.vessel_iterations, o.vessel_passband);
      } else if (i == 5) {
        item["surface"] = write_mask_stl(masks[i], A, cand, 0, o.airway_sigma_mm, true, false, true, o.airway_sigma_z_mm, false, false);
        obj_tm.lap("mask_to_surface");
        // 气管不只留最大表面：保留 bin2stl 修补后的分支（小于 20 mm³ 的碎块仍由 remove_small_surfaces 去掉）。
        item["smoothing"] = smooth_surface(cand, target, false, 20., o.iterations, o.passband);
      } else {
        item["surface"] = write_mask_stl(masks[i], A, cand, tumor ? o.tumor_taubin : 5, tumor ? o.tumor_sigma_mm : .45, !tumor, tumor);
        obj_tm.lap("mask_to_surface");
        item["smoothing"] = smooth_surface(cand, target, i != 7, tumor ? 5. : 20., o.iterations, o.passband);
      }
      obj_tm.lap("surface_smoothing");
      have_after = Quality::from_json(item["smoothing"]["output_quality"], after);
      if (tumor && o.tumor_faces > 0) {
        item["tumor_reduction"] = reduce_in_place(target, o.tumor_faces, 0.02);
        if (item["tumor_reduction"].value("accepted", false)) have_after = false;
        obj_tm.lap("tumor_reduction");
      }
    }
    if (!have_after) after = mesh_quality(read_stl(target));
    if (after.boundary_nonmanifold() || after.volume_mm3 <= 0) throw Error("平滑输出未通过闭合检查：" + target);
    obj_tm.lap("output_quality");
    item["status"] = "processed";
    item["source_sha256"] = entry["sha256"];
    item["sha256"] = sha256_file(target);
    obj_tm.lap("publish_hash");
    item["timing_seconds"] = obj_tm.out;
    stage_tm.lap(names[i].c_str());
    item["before"] = before[i].to_json();
    item["after"] = after.to_json();
    item["triangles"] = after.triangles;
    item["volume_mm3"] = after.volume_mm3;
    item["volume_change_percent"] = 100 * (after.volume_mm3 / before[i].volume_mm3 - 1);
    report["objects"].push_back(item);
  }
  for (int i = 5; i < 9; ++i) remove_file(join(tmp_dir, names[i] + ".stl"));
  ::rmdir(tmp_dir.c_str());
  stage_tm.lap("finish");
  report["timing_seconds"] = stage_tm.out;
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
  const json& objects = manifest["objects"];
  const int total = (int)objects.size();
  StepTimer stage_tm;
  // 各结构互相独立：按输入 STL 从大到小并行处理（大网格先开工，缩短拖尾），结果按清单原顺序写回。
  // QEM 本身单线程且确定，并行只改变执行顺序，不改变任何输出字节。
  std::vector<int> order;
  std::vector<uint64_t> bytes(total, 0);
  for (int k = 0; k < total; ++k) {
    order.push_back(k);
    const json& e = objects[k];
    if (e["status"] != "empty_prediction") {
      const std::string rel = e["file"].get<std::string>();
      if (rel.find("..") != std::string::npos) throw Error("STL 清单路径超出输入目录");
      bytes[k] = file_size(join(src, rel));
    }
  }
  std::stable_sort(order.begin(), order.end(), [&](int a, int b) { return bytes[a] > bytes[b]; });
  std::vector<json> items(total);
  std::vector<std::string> errors(total);
  int finished = 0;
#pragma omp parallel for schedule(dynamic, 1)
  for (int n = 0; n < total; ++n) {
    const int k = order[n];
    try {
      const json& entry = objects[k];
      items[k] = cut_one(entry, src, out, o);
    } catch (const std::exception& ex) {
      errors[k] = ex.what();
    }
#pragma omp critical(ctf_progress)
    try {  // 异常不能跨出 critical 区；进度写失败只记录，不中断其他结构
      progress(fmt("%d/%d %s", ++finished, total, objects[k]["name"].get<std::string>().c_str()));
    } catch (const std::exception& ex) {
      if (errors[k].empty()) errors[k] = ex.what();
    }
  }
  for (const auto& e : errors) if (!e.empty()) throw Error(e);
  stage_tm.lap("objects_parallel");
  for (auto& item : items) report["objects"].push_back(std::move(item));
  report["timing_seconds"] = stage_tm.out;
  write_json(join(out, "manifest.json"), report);
  return report;
}

}  // namespace ctf
