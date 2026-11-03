// 板端算子 RPC：序号匹配、BUSY 重试、最多 4 帧在途的 1KiB WRITE/READ 流水。
#pragma once
#include "net/protocol.hpp"

namespace ctf {

struct TimeoutError : Error {
  using Error::Error;
};

struct Reply {
  int state = 0, op = 0, format = 0;
  uint32_t run_id = 0, bytes = 0, mac_bytes = 0;
  std::vector<uint8_t> data;  // 16 字节状态体之后的附加数据
};

// 主机 WRITE/READ 的 DDR 上限，须与 RTL op_service.HOST_DDR_TOP 一致（VOL2 派生视图可放到 0x20000000 之后）。
constexpr uint64_t DDR_TOP = 0x30000000ull;
constexpr uint64_t COEFF_BASE = 0x00100000ull, COEFF_LIMIT = 0x00159600ull;  // 只读 ROM
constexpr size_t RPC_FRAME_BYTES = 1024;
constexpr int WINDOW = 4;  // 板端请求环形队列 4 槽

class OpClient {
 public:
  OpClient(const std::string& host, int port, double timeout, const std::string& bind_ip, int retries = 8);
  ~OpClient();
  OpClient(const OpClient&) = delete;
  OpClient& operator=(const OpClient&) = delete;

  Reply rpc(uint8_t msg, uint32_t run_id = 0, const std::vector<uint8_t>& body = {});
  // 地址 32 字节对齐；数据末尾补零到 32 的整数倍。
  void upload(uint64_t address, const void* data, size_t len);
  void upload_file(uint64_t address, const std::string& path, uint64_t offset, uint64_t size,
                   const std::function<void(uint64_t, uint64_t)>& progress);
  // 返回 [address, address+size) 的内容；每个 1KiB 请求独立重试。
  std::vector<uint8_t> read(uint32_t run_id, uint64_t address, uint64_t size, bool diagnostic = false);

  uint64_t frames_sent = 0, retransmits = 0;

 private:
  struct Job {
    std::vector<uint8_t> body;
    int64_t token = 0;
  };
  void window_rpc(uint8_t msg, uint32_t run_id, const std::function<bool(Job&)>& next,
                  const std::function<void(int64_t, const std::vector<uint8_t>&)>& on_reply);

  int fd_ = -1;
  uint32_t peer_ip_ = 0;  // 网络序
  uint16_t peer_port_ = 0;
  double timeout_;
  int retries_;
  uint32_t sequence_ = 0;
};

}  // namespace ctf
