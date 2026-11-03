#include "net/volume_ctl.hpp"

#include <unistd.h>

#include <cmath>
#include <random>

#include "ct/vol2.hpp"

namespace ctf {
namespace {

constexpr uint32_t PARAM_BASE = 0x08000000u;
constexpr uint64_t SLICE_RESULT_BYTES = 524288;
const char* const TASKS[4] = {"lobe", "airway", "vessel", "tumor"};

std::vector<uint32_t> nearest_coordinates(int old_n, int new_n) {
  const int64_t denom = std::max(new_n - 1, 1);
  std::vector<uint32_t> v(new_n);
  for (int i = 0; i < new_n; ++i) v[i] = (uint32_t)((2 * (int64_t)i * (old_n - 1) + denom) / (2 * denom));
  return v;
}

bool near(double a, double b, double atol) { return std::fabs(a - b) <= atol + 1e-5 * std::fabs(b); }

uint32_t random_identity() {
  std::random_device rd;
  uint32_t v = rd();
  return v ? v : 1;
}

std::string exe_dir() {
  char buf[4096];
  ssize_t n = readlink("/proc/self/exe", buf, sizeof buf - 1);
  if (n <= 0) return ".";
  buf[n] = 0;
  return parent_dir(buf);
}

}  // namespace

std::string find_assets_dir(const std::string& hint) {
  std::vector<std::string> cands;
  if (!hint.empty()) cands.push_back(hint);
  if (const char* e = std::getenv("CTFPGA_ASSETS")) cands.push_back(e);
  const std::string d = exe_dir();
  for (const char* rel : {"../assets", "../../assets", "../../../assets", "assets"}) cands.push_back(join(d, rel));
  for (auto& c : cands)
    if (file_exists(join(c, "volume_plans.json"))) return c;
  throw Error("找不到冻结资产目录（volume_plans.json）；请用 --assets 或 CTFPGA_ASSETS 指定");
}

json load_plans(const std::string& dir) {
  json assets = read_json(join(dir, "volume_assets.json"));
  for (auto& kv : assets["assets"].items()) {
    const std::string p = join(dir, kv.key());
    check_file(p, kv.value()["bytes"].get<uint64_t>(), kv.value()["sha256"].get<std::string>());
  }
  return read_json(join(dir, "volume_plans.json"));
}

int64_t validate_bits(const uint16_t* p, size_t n) {
  for (size_t i = 0; i < n; ++i) {
    const uint32_t v = p[i];
    const uint32_t lobes = v & 31;
    if (v > 511 || (lobes & (lobes - 1)) || (v & 192) == 192) return (int64_t)i;
  }
  return -1;
}

Program build_program(const json& job, const json& metadata, const json& plans) {
  const int depth = job["input"]["shape"][0].get<int>();
  if (!job.contains("compact_bin") || job["compact_bin"].is_null()) throw Error("VOL2 compact BIN metadata is required");
  const json& compact = job["compact_bin"];
  if (job["input"]["ddr_base"].get<uint64_t>() != IMAGE_BASE || depth < 1 || depth > 480)
    throw Error("整卷固件要求 --image-base 0x00400000、层数 1..480");
  if (RESULT_BASE + (uint64_t)depth * SLICE_RESULT_BYTES > DDR_LIMIT_RESULT) throw Error("整卷结果超过 DDR 容量");

  const json& A = metadata["affine_z_y_x_to_lps_mm"];
  double spacing[3], dirs[3][3];
  for (int c = 0; c < 3; ++c) {
    double s = 0;
    for (int r = 0; r < 3; ++r) { double v = A[r][c].get<double>(); s += v * v; }
    spacing[c] = std::sqrt(s);
  }
  for (int r = 0; r < 3; ++r)
    for (int c = 0; c < 3; ++c) dirs[r][c] = A[r][c].get<double>() / spacing[c];
  const int direction = metadata["anatomical_z_direction"].get<int>();
  bool ok = (direction == -1 || direction == 1);
  const double want[2][3] = {{0, 0, 1}, {0, 1, 0}};
  // 注意：与 numpy 版一致，directions 取的是仿射前两"行"除以各列间距。
  for (int r = 0; r < 2; ++r)
    for (int c = 0; c < 3; ++c) ok = ok && near(dirs[r][c], want[r][c], 1e-3);
  const double w2[3] = {1, 0, 0};
  for (int c = 0; c < 3; ++c) ok = ok && near(std::fabs(dirs[2][c]), w2[c], 1e-3);
  if (!ok) throw Error("整卷模型要求已校验的轴向 DICOM L/P 平面与层序");

  Program P;
  P.summaries = json::array();
  auto table = [&](const std::vector<uint32_t>& v) -> uint32_t {
    const uint32_t addr = (uint32_t)(MAP_BASE + P.maps.size());
    const size_t off = P.maps.size();
    P.maps.resize(off + v.size() * 4);
    for (size_t i = 0; i < v.size(); ++i) put_le32(&P.maps[off + 4 * i], v[i]);
    P.maps.resize(align_up(P.maps.size()), 0);
    return addr;
  };
  auto record = [&](uint8_t kind, const uint8_t* payload, ProgramCtx c) {
    const size_t off = P.records.size();
    P.records.resize(off + 96, 0);
    P.records[off] = kind;
    std::memcpy(&P.records[off + 32], payload, 64);
    P.ctx.push_back(c);
  };
  // <4B4I2H5I>
  auto pack44 = [](uint8_t* b, uint8_t k, uint8_t o, uint8_t ch, uint8_t bit, uint32_t a0, uint32_t a1, uint32_t a2,
                   uint32_t a3, uint32_t w, uint32_t h, uint32_t b0, uint32_t b1, uint32_t n0, uint32_t n1,
                   uint32_t n2) {
    std::memset(b, 0, 64);
    b[0] = k; b[1] = o; b[2] = ch; b[3] = bit;
    put_le32(b + 4, a0); put_le32(b + 8, a1); put_le32(b + 12, a2); put_le32(b + 16, a3);
    put_le16(b + 20, w); put_le16(b + 22, h);
    put_le32(b + 24, b0); put_le32(b + 28, b1); put_le32(b + 32, n0); put_le32(b + 36, n1); put_le32(b + 40, n2);
  };

  struct Task { int channels, bit, orientation; };
  const Task tasks[4] = {{5, 0, 2}, {1, 5, 1}, {2, 6, 0}, {1, 8, 1}};
  for (int t = 0; t < 4; ++t) {
    const std::string task = TASKS[t];
    int dz, height, width;
    if (t == 0) {
      int g[3];
      const int dims[3] = {depth, 512, 512};
      for (int k = 0; k < 3; ++k) g[k] = std::max(2, (int)std::nearbyint(((double)(dims[k] - 1) * spacing[k]) / 1.5) + 1);
      dz = g[0]; height = g[1]; width = g[2];
    } else {
      dz = depth; height = 512; width = 512;
    }
    if (std::max(height, width) > 512 || dz > 65535) throw Error(task + ": model grid exceeds FPGA limits");
    auto rx = nearest_coordinates(width, 512), ry = nearest_coordinates(height, 512);
    for (auto& v : rx) v += (512 - width) / 2;
    for (auto& v : ry) v += (512 - height) / 2;
    const uint32_t restore_x = table(rx), restore_y = table(ry);
    const auto native_z = nearest_coordinates(dz, depth);

    const std::string source_name = t == 0 ? "lobe" : "native";
    const json* view = nullptr;
    for (auto& v : compact["views"]) if (v["name"] == source_name) view = &v;
    if (!view) throw Error("compact view missing: " + source_name);
    int gather_orientation = tasks[t].orientation;
    for (auto& v : compact["views"])
      if (v.contains("source") && v["source"] == source_name && v.contains("orientation") &&
          v["orientation"].get<int>() == tasks[t].orientation) { view = &v; gather_orientation = 0; break; }
    const int view_depth = (*view)["planes"].get<int>();
    if ((view_depth != dz && t == 0) || (view_depth != depth && t != 0))
      throw Error(task + ": compact view depth does not match model grid");
    const json& plan = plans[task];
    if (plan["arena_end"].get<uint64_t>() > RESULT_BASE || plan["input"].get<uint64_t>() < 0x0A000000ull)
      throw Error(task + ": scratch/result overlap");
    const size_t before = P.commands();
    std::vector<std::vector<uint8_t>> stage_desc;
    for (auto& st : plan["stages"]) stage_desc.push_back(from_hex(st["descriptor_hex"].get<std::string>()));
    // 原生层 → 该模型层的反向索引
    std::vector<std::vector<int>> natives(dz);
    for (int n = 0; n < depth; ++n) natives[native_z[n]].push_back(n);

    uint8_t cmd[64];
    for (int z = 0; z < dz; ++z) {
      uint32_t nb[3];
      const int step = (t == 0) ? direction : 1;
      for (int k = 0; k < 3; ++k) nb[k] = (uint32_t)std::min(std::max(z + (k - 1) * step, 0), view_depth - 1);
      pack44(cmd, 4, (uint8_t)(gather_orientation | (direction < 0 ? 4 : 0)), t == 0 ? 1 : 0, 0,
             (*view)["base"].get<uint32_t>(), plan["input"].get<uint32_t>(), (uint32_t)view_depth,
             (*view)["bytes"].get<uint32_t>(), (*view)["width"].get<uint32_t>(), (*view)["height"].get<uint32_t>(),
             (*view)["row_stride"].get<uint32_t>(), (*view)["plane_stride"].get<uint32_t>(), nb[0], nb[1], nb[2]);
      record(4, cmd, {(uint8_t)t, z, -1});
      for (size_t s = 0; s < stage_desc.size(); ++s) {
        if (stage_desc[s].size() != 64) throw Error("DDR command payload must be 64 bytes");
        record(1, stage_desc[s].data(), {(uint8_t)t, z, (int16_t)s});
      }
      for (int n : natives[z]) {
        pack44(cmd, 3, (uint8_t)tasks[t].orientation, (uint8_t)tasks[t].channels, (uint8_t)tasks[t].bit,
               plan["head"].get<uint32_t>(), (uint32_t)(RESULT_BASE + (uint64_t)n * SLICE_RESULT_BYTES),
               (uint32_t)depth, 0, 512, 512, restore_x, restore_y, 0, 0, 0);
        record(3, cmd, {(uint8_t)t, z, -2});
      }
    }
    json s = json::object();
    s["model"] = task;
    s["grid"] = json::array({dz, height, width});
    s["commands"] = P.commands() - before;
    s["stages_per_slice"] = plan["stages"].size();
    s["contract_sha256"] = plan["contract_sha256"];
    P.summaries.push_back(s);
  }
  uint8_t end[64] = {0};
  record(255, end, {0, 0, -3});
  const size_t count = P.commands();
  if (count > 65536 || SCRIPT_BASE + P.records.size() > MAP_BASE || MAP_BASE + P.maps.size() > 0x09000000ull)
    throw Error("执行清单或坐标表超出 DDR 保留区");
  P.header.assign(64, 0);
  put_le32(&P.header[0], 0x324C4F56u);
  put_le32(&P.header[4], 2);
  put_le32(&P.header[8], (uint32_t)SCRIPT_BASE);
  put_le32(&P.header[12], (uint32_t)count);
  put_le32(&P.header[16], (uint32_t)IMAGE_BASE);
  put_le32(&P.header[20], (uint32_t)depth);
  put_le32(&P.header[24], (uint32_t)RESULT_BASE);
  put_le32(&P.header[28], (uint32_t)((uint64_t)depth * SLICE_RESULT_BYTES));
  return P;
}

// ---------------------------------------------------------------------------------------------
json send_volume(const std::string& case_dir, const json& job, const NetCfg& net, const Progress& progress) {
  const json& compact = job["compact_bin"];
  const std::string path = join(case_dir, compact["file"].get<std::string>());
  check_file(path, compact["bytes"].get<uint64_t>(), compact["sha256"].get<std::string>());
  OpClient client(net.host, net.port, net.timeout, net.bind);
  const uint32_t identity = random_identity();
  Reply st = client.rpc(MSG_STATUS);
  if (st.state != 0) {
    const std::string rp = join(case_dir, "handoff/send_receipt.json");
    uint32_t old_id = 0;
    if (file_exists(rp)) {
      json prev = read_json(rp);
      if (prev.contains("transfer_id") && prev["transfer_id"].is_number_unsigned()) old_id = prev["transfer_id"].get<uint32_t>();
    }
    if ((st.state == 2 || st.state == 3) && old_id) {
      progress(fmt("Release terminal FPGA run 0x%08x", old_id));
      client.rpc(MSG_VRELEASE, old_id);
      st = client.rpc(MSG_STATUS);
    }
    if (st.state != 0) throw Error("板端仍保留运行；请先完成回读或显式释放");
  }
  const double t0 = now_seconds();
  uint64_t total = 0;
  for (auto& v : compact["views"]) {
    const uint64_t bytes = v["bytes"].get<uint64_t>();
    total += bytes;
    const std::string name = v["name"].get<std::string>();
    progress(fmt("Upload VOL2 %s: %llu bytes", name.c_str(), (unsigned long long)bytes));
    client.upload_file(v["base"].get<uint64_t>(), path, v["file_offset"].get<uint64_t>(), bytes,
                       [&](uint64_t s, uint64_t t) { progress(fmt("VOL2 %s: %llu/%llu bytes", name.c_str(), (unsigned long long)s, (unsigned long long)t)); });
  }
  const double dt = now_seconds() - t0;
  json r = json::object();
  r["status"] = "compact_uploaded";
  r["transfer_id"] = identity;
  r["input_sha256"] = job["input"]["sha256"];
  r["compact_sha256"] = compact["sha256"];
  json secs = json::array();
  for (auto& v : compact["views"]) { json s = v; s.erase("file_offset"); secs.push_back(s); }
  r["sections"] = secs;
  r["note"] = "VOL2 sections uploaded; native INT8 source remains in the case as compatibility baseline.";
  r["upload_seconds"] = dt;
  r["upload_mib_s"] = total / 1048576.0 / std::max(dt, 1e-9);
  r["frames_sent"] = client.frames_sent;
  r["retransmits"] = client.retransmits;
  write_json(join(case_dir, "handoff/send_receipt.json"), r);
  return r;
}

json upload_program(const std::string& case_dir, const json& job, const NetCfg& net, const std::string& assets_dir,
                    const Progress& progress) {
  json plans = load_plans(assets_dir);
  Program P = build_program(job, read_json(join(case_dir, "input/metadata.json")), plans);
  OpClient client(net.host, net.port, net.timeout, net.bind);
  if (client.rpc(MSG_STATUS).state != 0) throw Error("板端仍保留运行；请先完成回读或显式释放");
  json receipt = read_json(join(case_dir, "handoff/send_receipt.json"));
  if (receipt.value("compact_sha256", "") != job["compact_bin"]["sha256"].get<std::string>())
    throw Error("已上传 VOL2 BIN 与程序清单的 compact SHA256 不匹配");
  auto params = read_file(join(assets_dir, "tumor.params.bin"));
  struct Item { uint64_t addr; const std::vector<uint8_t>* data; const char* name; };
  for (Item it : {Item{PARAM_BASE, &params, "tumor parameters"}, Item{SCRIPT_BASE, &P.records, "DDR execution list"},
                  Item{MAP_BASE, &P.maps, "coordinate tables"}}) {
    progress(fmt("Upload %s: %zu bytes", it.name, it.data->size()));
    client.upload(it.addr, it.data->data(), it.data->size());
  }
  json pk = json::object();
  pk["format"] = "pc-fpga-volume-program-v2";
  pk["header_hex"] = to_hex(P.header.data(), P.header.size());
  pk["commands"] = P.commands();
  pk["schedule_sha256"] = sha256_hex(P.records.data(), P.records.size());
  pk["maps_sha256"] = sha256_hex(P.maps.data(), P.maps.size());
  pk["input_sha256"] = job["input"]["sha256"];
  pk["compact_sha256"] = job["compact_bin"]["sha256"];
  pk["models"] = P.summaries;
  write_json(join(case_dir, "handoff/program.json"), pk);
  return pk;
}

// ---------------------------------------------------------------------------------------------
namespace {

std::string describe(const Program& P, uint32_t count, const json& plans) {
  if (count >= P.ctx.size()) return "finished";
  const ProgramCtx& c = P.ctx[count];
  if (c.stage == -3) return "END";
  std::string stage = c.stage == -1 ? "gather" : c.stage == -2 ? "classify" : plans[TASKS[c.model]]["stages"][c.stage]["name"].get<std::string>();
  return fmt("%s slice %d %s", TASKS[c.model], c.slice, stage.c_str());
}

// 解析 QUERY 附带的 VDG 诊断；返回进度指纹（任一计数变化即认为板端仍在推进）。
bool parse_vdg(const std::vector<uint8_t>& d, json& hw, std::vector<uint64_t>& fp, json& cycles) {
  if (d.size() < 16) return false;
  const uint32_t magic = get_le32(d.data());
  auto w = [&](size_t i) { return get_le32(&d[4 * i]); };
  if (magic == 0x31474456) {
    const uint32_t outputs = w(1), inputs = w(2), flags = w(3);
    hw = {{"engine_state", flags & 15}, {"scheduler_state", (flags >> 4) & 15}, {"input_words", inputs},
          {"output_words", outputs}, {"read_idle", (flags & 256) != 0}, {"memory_pending", (flags & 512) != 0},
          {"core_done", (flags & 1024) != 0}, {"core_reset_n", (flags & 2048) != 0}};
    fp = {flags & 15u, inputs, outputs};
    if (d.size() >= 32) cycles = {{"fetch", w(4)}, {"operator", w(5)}, {"gather", w(6)}, {"classify", w(7)}};
    return true;
  }
  if ((magic == 0x32474456 || magic == 0x33474456 || magic == 0x34474456) && d.size() >= 64) {
    uint64_t high[8] = {0};
    if (magic == 0x34474456 && d.size() >= 96) for (int i = 0; i < 8; ++i) high[i] = w(16 + i);
    const uint32_t flags = w(1);
    uint64_t reads = w(2) | high[5] << 32, writes = w(3) | high[6] << 32;
    uint64_t fetch = w(6) | high[0] << 32, op = w(7) | high[1] << 32;
    uint64_t gather = w(8) | high[2] << 32, cls = w(9) | high[3] << 32;
    uint64_t wait = w(5) | high[4] << 32;
    const int version = magic == 0x32474456 ? 2 : magic == 0x33474456 ? 3 : 4;
    hw = {{"engine_state", flags & 15}, {"scheduler_state", (flags >> 4) & 15}, {"input_words", reads},
          {"output_words", writes}, {"read_idle", (flags & 256) != 0}, {"memory_pending", (flags & 512) != 0},
          {"core_done", (flags & 1024) != 0}, {"core_reset_n", (flags & 2048) != 0}, {"diagnostic_version", version},
          {"gather_request_stall_cycles", w(4)}, {"gather_response_wait_cycles", wait}};
    cycles = {{"fetch", fetch}, {"operator", op}, {"gather", gather}, {"classify", cls}};
    if (version == 2) {
      fp = {flags & 15u, reads, writes, gather};
    } else {
      const uint64_t k4 = w(10) | (uint64_t)w(11) << 32;
      hw["compact_cache_hits"] = w(12);
      hw["compact_cache_misses"] = w(13);
      hw["kind4_cycles"] = k4;
      cycles["kind4"] = k4;
      fp = {flags & 15u, reads, writes, w(12), k4};
    }
    return true;
  }
  return false;
}

}  // namespace

std::string reason_volume(const std::string& case_dir, const NetCfg& net, double run_timeout, double stall_timeout,
                          const std::string& assets_dir, const Progress& progress) {
  json job = read_json(join(case_dir, "handoff/job.json"));
  json pkg = read_json(join(case_dir, "handoff/program.json"));
  json receipt = read_json(join(case_dir, "handoff/send_receipt.json"));
  const std::string in_sha = job["input"]["sha256"];
  if (pkg["input_sha256"] != in_sha || receipt["input_sha256"] != in_sha) throw Error("输入与DDR执行清单身份不匹配");
  if (pkg.value("compact_sha256", "") != receipt.value("compact_sha256", "x")) throw Error("VOL2 compact BIN 身份与已上传文件不匹配");
  json plans = load_plans(assets_dir);
  Program P = build_program(job, read_json(join(case_dir, "input/metadata.json")), plans);
  if (sha256_hex(P.records.data(), P.records.size()) != pkg["schedule_sha256"].get<std::string>())
    throw Error("本地算子清单已变化，不能用它诊断板端旧任务");

  const uint32_t identity = receipt["transfer_id"].get<uint32_t>();
  const uint64_t result_bytes = job["result_contract"]["bytes"].get<uint64_t>();
  const uint32_t total_cmds = pkg["commands"].get<uint32_t>();
  const double started = now_seconds();
  double changed = started, last_saved = started - 1;
  int64_t last_count = -1;
  std::vector<uint64_t> last_fp;
  const std::string diag_path = join(case_dir, "handoff/inference_status.json");
  json diag = json::object();
  diag["transfer_id"] = identity;
  diag["total_commands"] = total_cmds;
  diag["status"] = "waiting";
  json samples = json::array();
  json hardware, cycles;

  auto save = [&]() {
    diag["samples"] = samples;
    write_json(diag_path, diag);
  };
  OpClient client(net.host, net.port, net.timeout, net.bind);
  try {
    Reply r = client.rpc(MSG_START, identity, P.header);
    while (true) {
      const double now = now_seconds();
      const uint32_t count = r.mac_bytes;
      if ((int64_t)count != last_count) { changed = now; last_count = count; }
      diag["status"] = r.state == 2 ? "complete" : "running";
      diag["state"] = r.state;
      diag["completed_commands"] = count;
      diag["elapsed_seconds"] = std::round((now - started) * 1000) / 1000;
      diag["no_progress_seconds"] = std::round((now - changed) * 1000) / 1000;
      diag["current_command"] = describe(P, count, plans);
      std::vector<uint64_t> fp;
      if (parse_vdg(r.data, hardware, fp, cycles)) {
        diag["hardware"] = hardware;
        diag["volume_cycles"] = cycles;
        if (!fp.empty() && fp != last_fp) { changed = now; last_fp = fp; diag["no_progress_seconds"] = 0.0; }
      }
      if (now - last_saved >= 1.0 || r.state != 1) {
        json s = json::object();
        s["elapsed_seconds"] = diag["elapsed_seconds"];
        s["completed_commands"] = count;
        s["hardware"] = diag.contains("hardware") ? diag["hardware"] : json(nullptr);
        samples.push_back(s);
        while (samples.size() > 8) samples.erase(samples.begin());
        save();
        last_saved = now;
      }
      if (r.run_id != identity || r.bytes != result_bytes) throw Error("整卷状态身份或结果长度不匹配");
      if (r.state == 2) break;
      if (r.state != 1) throw Error(fmt("整卷失败或被中止：state=%d", r.state));
      if (now - changed >= stall_timeout)
        throw TimeoutError(fmt("FPGA命令进度连续 %gs 未变化：%u/%u，当前 %s；诊断：%s；板端现场保留", stall_timeout, count,
                               total_cmds, describe(P, count, plans).c_str(), diag_path.c_str()));
      if (now - started > run_timeout) throw TimeoutError("整卷仍在运行，保留板端现场；重新 reasoning 可继续等待");
      progress(fmt("FPGA %u/%u; %s; %.1fs", count, total_cmds, describe(P, count, plans).c_str(), now - started));
      usleep(250000);
      r = client.rpc(MSG_QUERY, identity);
    }
  } catch (const std::exception& e) {
    diag["status"] = "failed";
    diag["error"] = e.what();
    save();
    throw;
  }
  json ready = json::object();
  ready["format"] = "pc-fpga-result-ready-v2";
  ready["state"] = "complete";
  ready["transfer_id"] = identity;
  ready["input_sha256"] = in_sha;
  ready["tasks"] = job["models"];
  ready["elapsed_seconds"] = now_seconds() - started;
  ready["schedule_sha256"] = pkg["schedule_sha256"];
  json res = job["result_contract"];
  res["ddr_base"] = RESULT_BASE;
  ready["result"] = res;
  ready["integrity"] = "V1 CRC32 per READ frame; local SHA256 after complete readback";
  const std::string path = join(case_dir, "handoff/result_ready.json");
  write_json(path, ready);
  return path;
}

json receive_result(const std::string& case_dir, const std::string& manifest, const NetCfg& net,
                    const Progress& progress) {
  json ready = read_json(manifest);
  json job = read_json(join(case_dir, "handoff/job.json"));
  json receipt = read_json(join(case_dir, "handoff/send_receipt.json"));
  const uint32_t identity = ready["transfer_id"].get<uint32_t>();
  json expected = job["result_contract"];
  expected["ddr_base"] = RESULT_BASE;
  // json 比较对键序不敏感；ordered_json 按序比较，故逐字段核对。
  auto same = [](const json& a, const json& b) {
    if (a.size() != b.size()) return false;
    for (auto& kv : a.items()) if (!b.contains(kv.key()) || b[kv.key()] != kv.value()) return false;
    return true;
  };
  if (ready.value("format", "") != "pc-fpga-result-ready-v2" || ready.value("state", "") != "complete" ||
      ready["input_sha256"] != job["input"]["sha256"] || identity != receipt["transfer_id"].get<uint32_t>() ||
      ready["tasks"] != job["models"] || !same(ready["result"], expected))
    throw Error("整卷结果身份或契约不匹配");

  const std::string folder = join(case_dir, "prediction");
  make_dirs(folder);
  const std::string published = join(folder, "metadata.json");
  const uint64_t total = job["result_contract"]["bytes"].get<uint64_t>();

  if (file_exists(published)) {
    json meta = read_json(published);
    if (!meta.contains("provenance") || !same(meta["provenance"]["result_ready"], ready))
      throw Error("prediction 已发布且身份不匹配；请使用新 case");
    check_file(join(folder, meta["file"].get<std::string>()), total, meta["sha256"].get<std::string>());
    if (!meta.value("ddr_released", false)) {
      OpClient c(net.host, net.port, net.timeout, net.bind);
      c.rpc(MSG_VRELEASE, identity);
      meta["ddr_released"] = true;
      write_json(published, meta);
    }
    return meta;
  }

  const std::string tmp = join(folder, "segmentation_uint16.bin.tmp");
  OpClient client(net.host, net.port, net.timeout, net.bind);
  Reply st = client.rpc(MSG_QUERY, identity);
  if (st.state != 2 || st.run_id != identity || st.bytes != total) throw Error("板端未完成整卷或身份已改变");
  const double t0 = now_seconds();
  std::string sha;
  {
    HashedWriter w(tmp);
    const uint64_t seg = 1u << 20;
    for (uint64_t off = 0; off < total; off += seg) {
      const uint64_t n = std::min(seg, total - off);
      auto payload = client.read(identity, RESULT_BASE + off, n);
      if (payload.size() != n) throw Error("结果回读被截断");
      // 位掩码为小端 UINT16；本机（x86/aarch64）亦为小端，可直接按 uint16 解释。
      std::vector<uint16_t> u(n / 2);
      std::memcpy(u.data(), payload.data(), n);
      const int64_t bad = validate_bits(u.data(), u.size());
      if (bad >= 0) throw Error(fmt("Invalid reserved bits or overlapping labels at byte %llu", (unsigned long long)(off + bad * 2)));
      w.write(payload.data(), n);
      progress(fmt("%llu/%llu bytes", (unsigned long long)(off + n), (unsigned long long)total));
    }
    sha = w.finish_hex();
  }
  const std::string path = join(folder, "segmentation_uint16.bin");
  rename_file(tmp, path);

  json meta = job["result_contract"];
  meta["file"] = "segmentation_uint16.bin";
  meta["order"] = "C";
  meta["sha256"] = sha;
  meta["ddr_released"] = false;
  meta["semantics"] = "FPGA classification, native CT grid, no mesh processing applied";
  json prov = json::object();
  prov["result_ready"] = ready;
  prov["input_sha256"] = job["input"]["sha256"];
  meta["provenance"] = prov;
  meta["receive_seconds"] = now_seconds() - t0;
  meta["receive_mib_s"] = total / 1048576.0 / std::max(now_seconds() - t0, 1e-9);
  write_json(published, meta);
  client.rpc(MSG_VRELEASE, identity);
  meta["ddr_released"] = true;
  write_json(published, meta);
  return meta;
}

}  // namespace ctf
