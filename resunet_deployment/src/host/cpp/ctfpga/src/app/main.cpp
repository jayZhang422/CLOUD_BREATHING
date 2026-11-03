// ctfpga：CT 打包 BIN → 发送 → 推理等待 → 接收 → BIN→STL → 平滑 → 减面。
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <set>

#include "common/case_flow.hpp"
#include "ct/convert.hpp"
#include "ct/vol2.hpp"
#include "net/volume_ctl.hpp"
#ifdef CTFPGA_HAVE_VTK
#include "mesh/stages.hpp"
#endif

using namespace ctf;

namespace {

struct Args {
  std::string stage = "all", data_dir, case_dir, series_uid, assets;
  std::string result_manifest, prediction_dir, mesh_dir;
  NetCfg net;
  double run_timeout = 7200, stall_timeout = 120;
  uint64_t image_base = IMAGE_BASE;
  int batch_slices = 1;
  bool transpose = true;
#ifdef CTFPGA_HAVE_VTK
  MeshOpts mesh;
#endif
};

void usage() {
  std::puts(
      "用法: ctfpga --stage <all|ct2bin|send|reasoning|receive|bin2stl|smooth|cut> --case-dir DIR [选项]\n"
      "  --data-dir PATH        DICOM 目录或 .zip（ct2bin/all）\n"
      "  --series-uid UID       多序列时指定\n"
      "  --host IP --port N --bind IP --timeout SEC   FPGA 网络（默认 192.168.1.10:8080，本机 192.168.1.102）\n"
      "  --run-timeout SEC --stall-timeout SEC        推理等待上限 / 进度停滞上限\n"
      "  --result-manifest FILE receive 必需（all/reasoning 自动生成）\n"
      "  --prediction-dir DIR   已有预测 BIN，仅离线后处理\n"
      "  --ct-metadata FILE     BIN→STL 用的 CT 元数据（默认 <case>/input/metadata.json）\n"
      "  --mesh-dir DIR         smooth/cut 的独立输入目录\n"
      "  --iterations N --passband X --max-faces N    平滑/减面参数\n"
      "  --vessel-sigma-z X     血管 z 向 sigma（默认2.0mm）\n"
      "  --vessel-skeleton 0|1  血管骨架钳制（默认1，0=逐体素钳制）\n"
      "  --vessel-match-volume 0|1  血管等值面按原体素数选取（默认1）\n"
      "  --vessel-min-level X   血管等值面水平下限（默认-0.12mm）\n"
      "  --airway-sigma X / --airway-sigma-z X  气管平滑（默认0.7/1.1mm）\n"
      "  --tumor-sigma X / --tumor-taubin N     肿瘤平滑（默认1.0mm/5轮）\n"
      "  --far-bridge-mm X      静脉碎片远距离桥接上限（默认16，0关闭，bin2stl）\n"
      "  --vessel-sigma X --vessel-taubin N --vessel-iterations N --vessel-passband X   动/静脉平滑（smooth）\n"
      "  --tumor-faces N        肿瘤目标面数（默认2000，0不减，smooth）\n"
      "  --cut-smooth N         减面后 Taubin 平滑轮数（cut，默认0）\n"
      "  --cut-lobe-faces N --cut-airway-faces N --cut-artery-faces N --cut-vein-faces N --cut-tumor-faces N  分器官减面目标（cut，0=用--max-faces）\n"
      "  --assets DIR           冻结资产目录（volume_plans.json 等）\n"
      "  --no-transpose         不生成预转置派生视图\n");
}

bool parse(int argc, char** argv, Args& a) {
  for (int i = 1; i < argc; ++i) {
    const std::string k = argv[i];
    auto v = [&]() -> std::string {
      if (i + 1 >= argc) { std::fprintf(stderr, "缺少参数值: %s\n", k.c_str()); std::exit(2); }
      return argv[++i];
    };
    if (k == "--stage") a.stage = v();
    else if (k == "--data-dir") a.data_dir = v();
    else if (k == "--case-dir") a.case_dir = v();
    else if (k == "--series-uid") a.series_uid = v();
    else if (k == "--host") a.net.host = v();
    else if (k == "--port") a.net.port = std::atoi(v().c_str());
    else if (k == "--bind") a.net.bind = v();
    else if (k == "--timeout") a.net.timeout = std::atof(v().c_str());
    else if (k == "--run-timeout") a.run_timeout = std::atof(v().c_str());
    else if (k == "--stall-timeout") a.stall_timeout = std::atof(v().c_str());
    else if (k == "--image-base") a.image_base = std::strtoull(v().c_str(), nullptr, 0);
    else if (k == "--batch-slices") a.batch_slices = std::atoi(v().c_str());
    else if (k == "--result-manifest") a.result_manifest = v();
    else if (k == "--prediction-dir") a.prediction_dir = v();
    else if (k == "--mesh-dir") a.mesh_dir = v();
    else if (k == "--assets") a.assets = v();
    else if (k == "--no-transpose") a.transpose = false;
#ifdef CTFPGA_HAVE_VTK
    else if (k == "--ct-metadata") a.mesh.ct_metadata = v();
    else if (k == "--iterations") a.mesh.iterations = std::atoi(v().c_str());
    else if (k == "--passband") a.mesh.passband = std::atof(v().c_str());
    else if (k == "--max-faces") a.mesh.max_faces = std::atoi(v().c_str());
    else if (k == "--threads") a.mesh.threads = std::atoi(v().c_str());
    else if (k == "--far-bridge-mm") a.mesh.far_bridge_mm = std::atof(v().c_str());
    else if (k == "--vessel-sigma") a.mesh.vessel_sigma_mm = std::atof(v().c_str());
    else if (k == "--vessel-sigma-z") a.mesh.vessel_sigma_z_mm = std::atof(v().c_str());
    else if (k == "--vessel-skeleton") a.mesh.vessel_skeleton = std::atoi(v().c_str()) != 0;
    else if (k == "--vessel-match-volume") a.mesh.vessel_match_volume = std::atoi(v().c_str()) != 0;
    else if (k == "--vessel-min-level") a.mesh.vessel_min_level_mm = std::atof(v().c_str());
    else if (k == "--airway-sigma") a.mesh.airway_sigma_mm = std::atof(v().c_str());
    else if (k == "--airway-sigma-z") a.mesh.airway_sigma_z_mm = std::atof(v().c_str());
    else if (k == "--tumor-sigma") a.mesh.tumor_sigma_mm = std::atof(v().c_str());
    else if (k == "--tumor-taubin") a.mesh.tumor_taubin = std::atoi(v().c_str());
    else if (k == "--vessel-taubin") a.mesh.vessel_taubin = std::atoi(v().c_str());
    else if (k == "--vessel-iterations") a.mesh.vessel_iterations = std::atoi(v().c_str());
    else if (k == "--vessel-passband") a.mesh.vessel_passband = std::atof(v().c_str());
    else if (k == "--tumor-faces") a.mesh.tumor_faces = std::atoi(v().c_str());
    else if (k == "--cut-smooth") a.mesh.cut_smooth = std::atoi(v().c_str());
    else if (k == "--cut-lobe-faces") a.mesh.cut_lobe_faces = std::atoi(v().c_str());
    else if (k == "--cut-airway-faces") a.mesh.cut_airway_faces = std::atoi(v().c_str());
    else if (k == "--cut-artery-faces") a.mesh.cut_artery_faces = std::atoi(v().c_str());
    else if (k == "--cut-vein-faces") a.mesh.cut_vein_faces = std::atoi(v().c_str());
    else if (k == "--cut-tumor-faces") a.mesh.cut_tumor_faces = std::atoi(v().c_str());
#endif
    else if (k == "-h" || k == "--help") { usage(); std::exit(0); }
    else { std::fprintf(stderr, "未知参数: %s\n", k.c_str()); return false; }
  }
  return !a.case_dir.empty();
}

}  // namespace

int main(int argc, char** argv) {
  Args a;
  if (!parse(argc, argv, a)) { usage(); return 2; }
  const std::set<std::string> stages = {"all", "ct2bin", "send", "reasoning", "receive", "bin2stl", "smooth", "cut"};
  if (!stages.count(a.stage)) { std::fprintf(stderr, "未知 --stage: %s\n", a.stage.c_str()); return 2; }
  if (a.net.port < 1 || a.net.port > 65535 || a.net.timeout <= 0) { std::fprintf(stderr, "端口或超时无效\n"); return 2; }

  char buf[4096];
  if (!realpath(a.case_dir.c_str(), buf)) {
    make_dirs(a.case_dir);
    if (!realpath(a.case_dir.c_str(), buf)) { std::fprintf(stderr, "无法创建病例目录: %s\n", a.case_dir.c_str()); return 2; }
  }
  const std::string cd = buf;
  make_dirs(cd);
  json report = json::object();
  report["status"] = "running";
  report["stage"] = a.stage;
  report["hardware_used"] = false;
  write_json(join(cd, "run_report.json"), report);

  const bool offline = !a.prediction_dir.empty();
  const std::string published = join(cd, "prediction/metadata.json");
  if ((a.stage == "all" || a.stage == "send") && !offline && file_exists(published)) {
    std::fprintf(stderr, "%s 已有发布的 prediction；请换用新的 --case-dir\n", published.c_str());
    return 2;
  }

  StageTable table(join(cd, "status.json"));
  const std::string raw = join(cd, "stl/raw"), smoothed = join(cd, "stl/smooth"), reduced = join(cd, "stl/cut");
  std::string current;
  int rc = 0;
  try {
    const bool want = true;
    (void)want;
    auto run = [&](const char* name, const std::function<void(const Progress&)>& fn) {
      current = name;
      Progress p = table.begin(name);
      fn(p);
      table.done(name);
    };

    if (offline) {
      for (const char* s : {"CT2BIN", "Send", "Reasoning", "Receive"}) table.set(s, "Skipped", "Existing prediction; offline only");
    }
    if ((a.stage == "ct2bin" || a.stage == "all") && !offline) {
      if (a.data_dir.empty()) throw Error("ct2bin 需要 --data-dir");
      run("CT2BIN", [&](const Progress& p) {
        prepare_ct(a.data_dir, cd, a.series_uid, p);
        json job = make_job(cd, a.image_base, a.batch_slices, a.transpose, p);
        p(fmt("%d slices; job.json ready", job["input"]["shape"][0].get<int>()));
      });
    }
    if ((a.stage == "send" || a.stage == "all") && !offline && a.result_manifest.empty()) {
      json job = make_job(cd, a.image_base, a.batch_slices, a.transpose, [](const std::string&) {});
      run("Send", [&](const Progress& p) {
        report["hardware_used"] = true;
        report["upload"] = send_volume(cd, job, a.net, p);
        report["program"] = upload_program(cd, job, a.net, find_assets_dir(a.assets), p);
        p("VOL2 compact views, parameters, and DDR command list uploaded");
      });
    }
    if ((a.stage == "reasoning" || a.stage == "all") && !offline) {
      if (a.result_manifest.empty()) {
        run("Reasoning", [&](const Progress& p) {
          report["hardware_used"] = true;
          a.result_manifest = reason_volume(cd, a.net, a.run_timeout, a.stall_timeout, find_assets_dir(a.assets), p);
        });
      } else {
        table.set("Reasoning", "Skipped", "Existing result-ready manifest");
      }
    }
    if ((a.stage == "receive" || a.stage == "all") && !offline) {
      if (a.result_manifest.empty()) throw Error("receive 需要 --result-manifest，禁止猜测结果地址和长度");
      run("Receive", [&](const Progress& p) {
        report["hardware_used"] = true;
        json m = receive_result(cd, a.result_manifest, a.net, p);
        report["result"] = m;
      });
    }
#ifdef CTFPGA_HAVE_VTK
    const std::string src_pred = offline ? a.prediction_dir : join(cd, "prediction");
    if (a.stage == "all" || a.stage == "bin2stl") {
      run("BIN2STL", [&](const Progress& p) {
        report["bin2stl"] = bin_to_stl(src_pred, raw, a.mesh, p);
        p("mask repair + joint lobes; LPS mm");
      });
    }
    if (a.stage == "all" || a.stage == "smooth") {
      run("Smooth", [&](const Progress& p) {
        report["smooth"] = smooth_meshes(a.mesh_dir.empty() ? raw : a.mesh_dir, smoothed, a.mesh, p);
      });
    }
    if (a.stage == "all" || a.stage == "cut") {
      run("Cut", [&](const Progress& p) {
        report["cut"] = cut_meshes(a.mesh_dir.empty() ? smoothed : a.mesh_dir, reduced, a.mesh, p);
        p(fmt("Target <= %d faces/object", a.mesh.max_faces));
      });
    }
#else
    if (a.stage == "bin2stl" || a.stage == "smooth" || a.stage == "cut")
      throw Error("本构建未包含 VTK（CTFPGA_WITH_VTK=OFF），网格阶段不可用");
#endif
    report["status"] = "complete";
  } catch (const std::exception& e) {
    report["status"] = "failed";
    report["error"] = e.what();
    if (!current.empty()) table.fail(current, e.what());
    std::fprintf(stderr, "\n[FAILED] %s\n", e.what());
    rc = 1;
  }
  write_json(join(cd, "run_report.json"), report);
  std::printf("\nReport: %s\n", join(cd, "run_report.json").c_str());
  return rc;
}
