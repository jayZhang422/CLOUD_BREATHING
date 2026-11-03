#include "net/op_client.hpp"

#include <arpa/inet.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <map>

namespace ctf {

OpClient::OpClient(const std::string& host, int port, double timeout, const std::string& bind_ip, int retries)
    : timeout_(timeout), retries_(retries) {
  addrinfo hints{}, *res = nullptr;
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_DGRAM;
  if (getaddrinfo(host.c_str(), nullptr, &hints, &res) != 0 || !res) throw Error("无法解析主机: " + host);
  peer_ip_ = reinterpret_cast<sockaddr_in*>(res->ai_addr)->sin_addr.s_addr;
  freeaddrinfo(res);
  peer_port_ = htons((uint16_t)port);
  fd_ = ::socket(AF_INET, SOCK_DGRAM, 0);
  if (fd_ < 0) throw Error("socket 创建失败");
  int buf = 4 << 20;
  setsockopt(fd_, SOL_SOCKET, SO_RCVBUF, &buf, sizeof buf);
  setsockopt(fd_, SOL_SOCKET, SO_SNDBUF, &buf, sizeof buf);
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_port = 0;  // 板端向请求源端口应答
  if (inet_pton(AF_INET, bind_ip.c_str(), &a.sin_addr) != 1) throw Error("非法绑定地址: " + bind_ip);
  if (::bind(fd_, reinterpret_cast<sockaddr*>(&a), sizeof a) != 0) {
    ::close(fd_);
    fd_ = -1;
    throw Error("无法绑定 UDP " + bind_ip + ": " + std::strerror(errno));
  }
}

OpClient::~OpClient() {
  if (fd_ >= 0) ::close(fd_);
}

namespace {
inline void send_packet(int fd, uint32_t ip, uint16_t port, const std::vector<uint8_t>& p) {
  sockaddr_in a{};
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = ip;
  a.sin_port = port;
  for (int tries = 0;; ++tries) {
    ssize_t n = ::sendto(fd, p.data(), p.size(), 0, reinterpret_cast<sockaddr*>(&a), sizeof a);
    if (n == (ssize_t)p.size()) return;
    if ((errno == ENOBUFS || errno == EAGAIN) && tries < 6) { usleep(1000 << tries); continue; }
    if (errno == ECONNREFUSED) return;
    throw Error(std::string("sendto 失败: ") + std::strerror(errno));
  }
}

// 等待可读；返回 false 表示超时。
inline bool wait_readable(int fd, double seconds) {
  pollfd pf{fd, POLLIN, 0};
  int ms = (int)std::ceil(std::max(0.0, seconds) * 1000.0);
  int r = ::poll(&pf, 1, ms);
  return r > 0 && (pf.revents & POLLIN);
}

enum class Rx { None, Peer, Foreign };

inline Rx recv_packet(int fd, uint32_t peer_ip, uint16_t peer_port, std::vector<uint8_t>& buf) {
  sockaddr_in from{};
  socklen_t fl = sizeof from;
  buf.resize(2048);
  ssize_t n = ::recvfrom(fd, buf.data(), buf.size(), MSG_DONTWAIT, reinterpret_cast<sockaddr*>(&from), &fl);
  if (n < 0) { buf.clear(); return Rx::None; }
  buf.resize(n);
  return (from.sin_addr.s_addr == peer_ip && from.sin_port == peer_port) ? Rx::Peer : Rx::Foreign;
}
}  // namespace

Reply OpClient::rpc(uint8_t msg, uint32_t run_id, const std::vector<uint8_t>& body) {
  sequence_ += 1;
  const auto packet = build_frame(msg, run_id, sequence_, body);
  std::vector<uint8_t> buf;
  for (int attempt = 0; attempt < retries_; ++attempt) {
    send_packet(fd_, peer_ip_, peer_port_, packet);
    ++frames_sent;
    const double deadline = now_seconds() + timeout_;
    while (true) {
      const double left = deadline - now_seconds();
      if (left <= 0) break;
      if (!wait_readable(fd_, left)) break;
      if (recv_packet(fd_, peer_ip_, peer_port_, buf) != Rx::Peer) continue;
      Frame f;
      try { f = parse_frame(buf.data(), buf.size()); } catch (const FrameError&) { continue; }
      if (f.msg_type != (uint8_t)(msg | 0x80) || f.transfer_id != run_id || f.sequence != sequence_) continue;
      if (f.body.size() < 16) throw Error("truncated operator reply");
      const uint8_t status = f.body[0];
      Reply r;
      r.state = f.body[1]; r.op = f.body[2]; r.format = f.body[3];
      r.run_id = get_le32(&f.body[4]);
      r.bytes = get_le32(&f.body[8]);
      r.mac_bytes = get_le32(&f.body[12]);
      if (status == 1) { usleep(10000); break; }  // BUSY：稍候重发
      if (status) {
        static const char* names[] = {"OK", "BUSY", "INVALID", "DDR_ERROR", "?", "INPUT_NOT_READY", "STALE"};
        throw Error(fmt("RPC 0x%02x: %s, state=%d, run_id=0x%08x", msg, status < 7 ? names[status] : "?", r.state, r.run_id));
      }
      const bool id_checked = msg == MSG_RUN || msg == MSG_READ || msg == MSG_RELEASE || msg == MSG_ABORT ||
                              (msg >= MSG_START && msg <= MSG_VABORT);
      if (id_checked && run_id != r.run_id && !(msg == MSG_READ && run_id == 0))
        throw Error("reply body run identity mismatch");
      r.data.assign(f.body.begin() + 16, f.body.end());
      return r;
    }
    if (attempt) ++retransmits;
  }
  throw TimeoutError(fmt("operator RPC 0x%02x timed out", msg));
}

void OpClient::window_rpc(uint8_t msg, uint32_t run_id, const std::function<bool(Job&)>& next,
                          const std::function<void(int64_t, const std::vector<uint8_t>&)>& on_reply) {
  struct Entry { std::vector<uint8_t> packet; int attempts = 0; double deadline = 0; int64_t token = 0; };
  std::map<uint32_t, Entry> pending;
  bool exhausted = false;
  std::vector<uint8_t> buf;
  auto send = [&](Entry& e) {
    send_packet(fd_, peer_ip_, peer_port_, e.packet);
    ++frames_sent;
    if (e.attempts) ++retransmits;
    ++e.attempts;
    e.deadline = now_seconds() + timeout_;
  };
  while (!pending.empty() || !exhausted) {
    while ((int)pending.size() < WINDOW && !exhausted) {
      Job job;
      if (!next(job)) { exhausted = true; break; }
      const uint32_t seq = ++sequence_;
      Entry e;
      e.packet = build_frame(msg, run_id, seq, job.body);
      e.token = job.token;
      auto& slot = pending.emplace(seq, std::move(e)).first->second;
      send(slot);
    }
    if (pending.empty()) break;
    double next_deadline = 1e300;
    for (auto& kv : pending) next_deadline = std::min(next_deadline, kv.second.deadline);
    wait_readable(fd_, std::max(0.001, next_deadline - now_seconds()));
    // 把已到达的应答全部取走
    while (true) {
      const Rx rx = recv_packet(fd_, peer_ip_, peer_port_, buf);
      if (rx == Rx::None) break;
      if (rx == Rx::Foreign) continue;
      Frame f;
      try { f = parse_frame(buf.data(), buf.size()); } catch (const FrameError&) { continue; }
      auto it = pending.find(f.sequence);
      if (it == pending.end() || f.msg_type != (uint8_t)(msg | 0x80) || f.transfer_id != run_id || f.body.size() < 16)
        continue;
      const uint8_t status = f.body[0];
      if (status == 0) {
        const uint32_t identity = get_le32(&f.body[4]);
        if (msg == MSG_READ && run_id != 0 && identity != run_id) throw Error("reply body run identity mismatch");
        const int64_t token = it->second.token;
        pending.erase(it);
        on_reply(token, f.body);
      } else if (status != 1) {
        throw Error(fmt("RPC 0x%02x: status %d", msg, status));
      } else {
        it->second.deadline = now_seconds() + 0.01;
      }
    }
    const double now = now_seconds();
    for (auto& kv : pending) {
      if (kv.second.deadline <= now) {
        if (kv.second.attempts >= retries_) throw TimeoutError(fmt("operator RPC 0x%02x timed out, sequence=%u", msg, kv.first));
        send(kv.second);
      }
    }
  }
}

void OpClient::upload(uint64_t address, const void* data, size_t len) {
  if (address % 32) throw Error("upload address must be 32-byte aligned");
  const size_t padded = align_up(len);
  if (address + padded > DDR_TOP) throw Error("upload is outside DDR address range");
  if (address < COEFF_LIMIT && address + padded > COEFF_BASE) throw Error("coefficient space is read-only ROM");
  const uint8_t* p = static_cast<const uint8_t*>(data);
  size_t off = 0;
  window_rpc(MSG_WRITE, 0, [&](Job& j) {
    if (off >= padded) return false;
    const size_t n = std::min(RPC_FRAME_BYTES, padded - off);
    j.body.assign(8 + n, 0);
    put_le32(&j.body[0], (uint32_t)(address + off));
    put_le16(&j.body[4], (uint32_t)n);
    const size_t have = off < len ? std::min(n, len - off) : 0;
    if (have) std::memcpy(&j.body[8], p + off, have);
    off += n;
    return true;
  }, [](int64_t, const std::vector<uint8_t>&) {});
}

void OpClient::upload_file(uint64_t address, const std::string& path, uint64_t offset, uint64_t size,
                           const std::function<void(uint64_t, uint64_t)>& progress) {
  if (address % 32 || size % 32) throw Error("file upload range must be 32-byte aligned");
  if (address + size > DDR_TOP) throw Error("upload is outside DDR address range");
  if (address < COEFF_LIMIT && address + size > COEFF_BASE) throw Error("coefficient space is read-only ROM");
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) throw Error("无法打开: " + path);
  std::setvbuf(f, nullptr, _IOFBF, 1 << 20);
  std::fseek(f, (long)offset, SEEK_SET);
  uint64_t sent = 0, acked = 0, last = 0;
  try {
    window_rpc(MSG_WRITE, 0, [&](Job& j) {
      if (sent >= size) return false;
      const size_t n = (size_t)std::min<uint64_t>(RPC_FRAME_BYTES, size - sent);
      j.body.assign(8 + n, 0);
      put_le32(&j.body[0], (uint32_t)(address + sent));
      put_le16(&j.body[4], (uint32_t)n);
      if (std::fread(&j.body[8], 1, n, f) != n) throw Error("compact BIN ended before its declared section size");
      j.token = (int64_t)n;
      sent += n;
      return true;
    }, [&](int64_t n, const std::vector<uint8_t>&) {
      acked += (uint64_t)n;
      if (acked - last >= (1u << 22) || acked == size) { progress(acked, size); last = acked; }
    });
  } catch (...) {
    std::fclose(f);
    throw;
  }
  std::fclose(f);
}

std::vector<uint8_t> OpClient::read(uint32_t run_id, uint64_t address, uint64_t size, bool diagnostic) {
  if (address % 32 || address + align_up(size) > DDR_TOP) throw Error("read must be 32-byte aligned and inside DDR");
  const uint64_t total = align_up(size);
  std::vector<uint8_t> out(total);
  uint64_t off = 0;
  window_rpc(MSG_READ, run_id, [&](Job& j) {
    if (off >= total) return false;
    const uint32_t n = (uint32_t)std::min<uint64_t>(RPC_FRAME_BYTES, total - off);
    j.body.assign(8, 0);
    put_le32(&j.body[0], (uint32_t)(address + off));
    put_le16(&j.body[4], n);
    put_le16(&j.body[6], diagnostic ? 1 : 0);
    j.token = (int64_t)off;
    off += n;
    return true;
  }, [&](int64_t at, const std::vector<uint8_t>& body) {
    const uint64_t want = std::min<uint64_t>(RPC_FRAME_BYTES, total - (uint64_t)at);
    if (body.size() - 16 != want) throw Error("result packet length mismatch");
    std::memcpy(&out[(size_t)at], &body[16], want);
  });
  out.resize(size);
  return out;
}

}  // namespace ctf
