// V1 线上帧：55AA/01 头、大端字段、CRC32(ISO-HDLC) 覆盖 Version..Body、尾 AA55。
#pragma once
#include "common/util.hpp"

namespace ctf {

constexpr uint16_t FRAME_MAGIC = 0x55AA;
constexpr uint16_t FRAME_TAIL = 0xAA55;
constexpr uint8_t FRAME_VERSION = 0x01;
constexpr size_t FRAME_HEADER = 16;
constexpr size_t FRAME_TRAILER = 6;

// 算子 RPC 与整卷控制消息
enum : uint8_t {
  MSG_WRITE = 0x20, MSG_RUN = 0x21, MSG_STATUS = 0x22, MSG_READ = 0x23, MSG_RELEASE = 0x24, MSG_ABORT = 0x25,
  MSG_START = 0x26, MSG_QUERY = 0x27, MSG_VRELEASE = 0x28, MSG_VABORT = 0x29,
};

struct Frame {
  uint8_t msg_type = 0;
  uint32_t transfer_id = 0;
  uint32_t sequence = 0;
  std::vector<uint8_t> body;
};

struct FrameError : Error {
  using Error::Error;
};

std::vector<uint8_t> build_frame(uint8_t msg_type, uint32_t transfer_id, uint32_t sequence,
                                 const uint8_t* body, size_t body_len);
inline std::vector<uint8_t> build_frame(uint8_t m, uint32_t t, uint32_t s, const std::vector<uint8_t>& b) {
  return build_frame(m, t, s, b.data(), b.size());
}
Frame parse_frame(const uint8_t* data, size_t len);  // 违规时抛 FrameError

}  // namespace ctf
