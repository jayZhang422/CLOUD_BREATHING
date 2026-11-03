// mockboard：KU5P 整卷服务的软件替身，仅用于 WSL 回环联调（不是交付物）。
// 行为：稀疏 512MiB DDR；WRITE/STATUS/START/QUERY/READ/RELEASE；START 校验执行清单结构；
// 完成时把 --result-file 装入 RESULT_BASE；--drop-every 注入丢包；RELEASE 后输出所选 DDR 区间的 SHA256。
#include <arpa/inet.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>

#include "common/util.hpp"
#include "net/protocol.hpp"

using namespace ctf;

namespace {
constexpr uint64_t DDR_SIZE = 0x30000000ull;
constexpr uint64_t RESULT_BASE_ = 0x10000000ull;
constexpr uint64_t SCRIPT_BASE_ = 0x08200000ull;
enum State { IDLE = 0, RUNNING = 1, COMPLETE = 2, FAILED = 3 };

volatile sig_atomic_t g_stop = 0;
void on_sig(int) { g_stop = 1; }

struct Range { uint64_t addr, len; std::string name; };
// --hash-extent：从 addr 起，哈希到该区域内被写入的最高地址（区域边界为下一个已登记的起点）。
struct Extent { uint64_t base; std::string name; uint64_t end = 0; };
}  // namespace

int main(int argc, char** argv) {
  std::string bind_ip = "127.0.0.1", result_file, report_path;
  int port = 8080, drop_every = 0, busy_polls = 3;
  double max_seconds = 600;
  bool exit_after_release = true;
  std::vector<Range> ranges;
  std::vector<Extent> extents;
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto val = [&]() -> std::string { if (i + 1 >= argc) { std::fprintf(stderr, "缺少参数值: %s\n", a.c_str()); std::exit(2); } return argv[++i]; };
    if (a == "--bind") bind_ip = val();
    else if (a == "--port") port = std::atoi(val().c_str());
    else if (a == "--result-file") result_file = val();
    else if (a == "--drop-every") drop_every = std::atoi(val().c_str());
    else if (a == "--busy-polls") busy_polls = std::atoi(val().c_str());
    else if (a == "--max-seconds") max_seconds = std::atof(val().c_str());
    else if (a == "--report") report_path = val();
    else if (a == "--keep-running") exit_after_release = false;
    else if (a == "--hash") {  // addr:len:name（十六进制或十进制）
      std::string s = val();
      auto p1 = s.find(':'), p2 = s.find(':', p1 + 1);
      ranges.push_back({std::strtoull(s.substr(0, p1).c_str(), nullptr, 0),
                        std::strtoull(s.substr(p1 + 1, p2 - p1 - 1).c_str(), nullptr, 0), s.substr(p2 + 1)});
    } else if (a == "--hash-extent") {  // addr:name
      std::string s = val();
      auto p = s.find(':');
      extents.push_back({std::strtoull(s.substr(0, p).c_str(), nullptr, 0), s.substr(p + 1), 0});
    } else { std::fprintf(stderr, "未知参数: %s\n", a.c_str()); return 2; }
  }
  std::sort(extents.begin(), extents.end(), [](const Extent& x, const Extent& y) { return x.base < y.base; });

  std::vector<uint8_t> preloaded;
  if (!result_file.empty()) preloaded = read_file(result_file);

  uint8_t* ddr = static_cast<uint8_t*>(mmap(nullptr, DDR_SIZE, PROT_READ | PROT_WRITE,
                                            MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0));
  if (ddr == MAP_FAILED) { std::perror("mmap"); return 1; }

  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  int buf = 8 << 20;
  setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &buf, sizeof buf);
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_port = htons(port);
  inet_pton(AF_INET, bind_ip.c_str(), &a.sin_addr);
  if (bind(fd, reinterpret_cast<sockaddr*>(&a), sizeof a) != 0) { std::perror("bind"); return 1; }
  timeval tv{0, 200000};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
  signal(SIGINT, on_sig);
  signal(SIGTERM, on_sig);
  std::printf("mockboard listening on %s:%d\n", bind_ip.c_str(), port);
  std::fflush(stdout);

  int state = IDLE;
  uint32_t run_id = 0, total_cmds = 0, depth = 0;
  uint64_t result_bytes = 0;
  uint32_t polls = 0;
  uint64_t n_rx = 0, n_drop = 0, n_write = 0, n_write_bytes = 0, n_read = 0, n_query = 0;
  bool header_ok = false, program_ok = false;
  std::string program_note;
  json report = json::object();
  const double t_start = now_seconds();
  bool released = false;

  std::vector<uint8_t> in(4096);
  while (!g_stop && now_seconds() - t_start < max_seconds) {
    sockaddr_in from{};
    socklen_t fl = sizeof from;
    ssize_t n = recvfrom(fd, in.data(), in.size(), 0, reinterpret_cast<sockaddr*>(&from), &fl);
    if (n < 0) continue;
    ++n_rx;
    if (drop_every > 0 && n_rx % drop_every == 0) { ++n_drop; continue; }
    Frame f;
    try { f = parse_frame(in.data(), n); } catch (const FrameError&) { continue; }

    uint8_t status = 0;
    uint32_t identity = f.transfer_id, size_field = 0, mac_field = 0;
    std::vector<uint8_t> extra;
    switch (f.msg_type) {
      case MSG_WRITE: {
        if (f.body.size() < 8) { status = 2; break; }
        const uint32_t addr = get_le32(&f.body[0]);
        const uint32_t len = get_le16(&f.body[4]);
        if (state == RUNNING) { status = 1; break; }
        if (f.body.size() != 8 + len || addr % 32 || len % 32 || (uint64_t)addr + len > DDR_SIZE) { status = 2; break; }
        if (addr < 0x00159600u && (uint64_t)addr + len > 0x00100000u) { status = 2; break; }
        std::memcpy(ddr + addr, &f.body[8], len);
        ++n_write; n_write_bytes += len;
        for (size_t k = 0; k < extents.size(); ++k) {
          const uint64_t hi = k + 1 < extents.size() ? extents[k + 1].base : DDR_SIZE;
          if (addr >= extents[k].base && addr < hi) extents[k].end = std::max<uint64_t>(extents[k].end, (uint64_t)addr + len);
        }
        identity = 0;
        break;
      }
      case MSG_STATUS:
        identity = run_id;
        break;
      case MSG_START: {
        if (f.body.size() != 64 || get_le32(&f.body[0]) != 0x324C4F56u || get_le32(&f.body[4]) != 2) { status = 2; break; }
        if (state != IDLE && !(f.transfer_id == run_id)) { status = 1; break; }
        if (state == IDLE) {
          const uint32_t script = get_le32(&f.body[8]), count = get_le32(&f.body[12]);
          depth = get_le32(&f.body[20]);
          result_bytes = get_le32(&f.body[28]);
          header_ok = script == SCRIPT_BASE_ && get_le32(&f.body[16]) == 0x00400000u && get_le32(&f.body[24]) == RESULT_BASE_ &&
                      result_bytes == (uint64_t)depth * 524288 && count >= 1 && count <= 65536;
          // 结构检查：每条 96B，kind∈{1,3,4,255}，仅最后一条为 255。
          program_ok = header_ok;
          uint32_t k1 = 0, k3 = 0, k4 = 0;
          for (uint32_t i = 0; program_ok && i < count; ++i) {
            const uint8_t kind = ddr[script + (uint64_t)i * 96];
            if (kind == 1) ++k1; else if (kind == 3) ++k3; else if (kind == 4) ++k4;
            else if (kind == 255) { program_ok = (i == count - 1); }
            else program_ok = false;
          }
          program_note = fmt("kind1=%u kind3=%u kind4=%u", k1, k3, k4);
          if (!header_ok || !program_ok) { status = 2; break; }
          total_cmds = count;
          run_id = f.transfer_id;
          state = RUNNING;
          polls = 0;
        }
        size_field = (uint32_t)result_bytes;
        break;
      }
      case MSG_QUERY: {
        ++n_query;
        if (f.transfer_id != run_id || state == IDLE) { status = 6; break; }
        if (state == RUNNING && ++polls > (uint32_t)busy_polls) {
          // 装入"推理结果"
          if (!result_file.empty()) {
            // 结果已在启动时预读；完成只做内存拷贝，避免阻塞应答。
            if (preloaded.size() != result_bytes) { state = FAILED; }
            else { std::memcpy(ddr + RESULT_BASE_, preloaded.data(), result_bytes); state = COMPLETE; }
          } else {
            state = COMPLETE;
          }
        }
        size_field = (uint32_t)result_bytes;
        mac_field = state == COMPLETE ? total_cmds : (uint32_t)((uint64_t)total_cmds * std::min<uint32_t>(polls, busy_polls) / (busy_polls + 1));
        // 附带 VDG1 诊断，计数随轮询推进
        extra.assign(32, 0);
        put_le32(&extra[0], 0x31474456u);
        put_le32(&extra[4], polls * 1000);
        put_le32(&extra[8], polls * 2000);
        put_le32(&extra[12], 0);
        break;
      }
      case MSG_READ: {
        if (f.body.size() != 8) { status = 2; break; }
        const uint32_t addr = get_le32(&f.body[0]);
        const uint32_t cnt = get_le16(&f.body[4]);
        const bool diag = get_le16(&f.body[6]) != 0;
        if (f.transfer_id != 0) {
          if (state != COMPLETE || f.transfer_id != run_id) { status = 6; break; }
          if (addr < RESULT_BASE_ || (uint64_t)addr + cnt > RESULT_BASE_ + result_bytes) { status = 2; break; }
        } else if (!diag) { status = 2; break; }
        if (addr % 32 || cnt % 32 || (uint64_t)addr + cnt > DDR_SIZE) { status = 3; break; }
        extra.assign(ddr + addr, ddr + addr + cnt);
        ++n_read;
        identity = f.transfer_id;
        break;
      }
      case MSG_VRELEASE:
        if (state == IDLE) { identity = f.transfer_id; break; }
        if (f.transfer_id != run_id) { status = 6; break; }
        if (state == RUNNING) { status = 1; break; }
        state = IDLE;
        released = true;
        break;
      case MSG_VABORT:
        if (f.transfer_id != run_id) { status = 6; break; }
        state = FAILED;
        break;
      default:
        status = 2;
    }

    std::vector<uint8_t> body(16 + extra.size(), 0);
    body[0] = status; body[1] = (uint8_t)state; body[2] = 0xFE; body[3] = 0;
    put_le32(&body[4], f.msg_type == MSG_WRITE ? 0 : (f.msg_type == MSG_STATUS ? run_id : identity));
    put_le32(&body[8], size_field);
    put_le32(&body[12], mac_field);
    if (!extra.empty()) std::memcpy(&body[16], extra.data(), extra.size());
    auto reply = build_frame(f.msg_type | 0x80, f.transfer_id, f.sequence, body);
    sendto(fd, reply.data(), reply.size(), 0, reinterpret_cast<sockaddr*>(&from), fl);

    if (released && exit_after_release) break;
  }

  json hashes = json::object();
  for (auto& r : ranges) hashes[r.name] = sha256_hex(ddr + r.addr, r.len);
  json extent_info = json::object();
  for (auto& e : extents) {
    if (e.end <= e.base) continue;
    hashes[e.name] = sha256_hex(ddr + e.base, e.end - e.base);
    extent_info[e.name] = e.end - e.base;
  }
  report["ddr_extent_bytes"] = extent_info;
  report["ddr_sha256"] = hashes;
  report["packets_rx"] = n_rx;
  report["packets_dropped"] = n_drop;
  report["writes"] = n_write;
  report["write_bytes"] = n_write_bytes;
  report["reads"] = n_read;
  report["queries"] = n_query;
  report["start_header_ok"] = header_ok;
  report["program_structure_ok"] = program_ok;
  report["program_note"] = program_note;
  report["released"] = released;
  if (!report_path.empty()) write_json(report_path, report);
  std::printf("%s\n", report.dump(2).c_str());
  return released || !exit_after_release ? 0 : 3;
}
