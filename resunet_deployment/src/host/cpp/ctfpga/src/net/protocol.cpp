#include "net/protocol.hpp"

namespace ctf {

std::vector<uint8_t> build_frame(uint8_t msg_type, uint32_t transfer_id, uint32_t sequence,
                                 const uint8_t* body, size_t body_len) {
  std::vector<uint8_t> f(FRAME_HEADER + body_len + FRAME_TRAILER);
  put_be16(&f[0], FRAME_MAGIC);
  f[2] = FRAME_VERSION;
  f[3] = msg_type;
  put_be32(&f[4], transfer_id);
  put_be16(&f[8], FRAME_HEADER);
  put_be16(&f[10], (uint32_t)body_len);
  put_be32(&f[12], sequence);
  if (body_len) std::memcpy(&f[FRAME_HEADER], body, body_len);
  // CRC 覆盖 Version..Body（不含 Magic、CRC、Tail）
  uint32_t crc = crc32(&f[2], FRAME_HEADER - 2 + body_len);
  put_be32(&f[FRAME_HEADER + body_len], crc);
  put_be16(&f[FRAME_HEADER + body_len + 4], FRAME_TAIL);
  return f;
}

Frame parse_frame(const uint8_t* d, size_t len) {
  if (len < FRAME_HEADER + FRAME_TRAILER) throw FrameError("frame too short");
  if (get_be16(d) != FRAME_MAGIC) throw FrameError("bad magic");
  if (d[2] != FRAME_VERSION) throw FrameError("unsupported version");
  if (get_be16(d + 8) != FRAME_HEADER) throw FrameError("bad header length");
  const size_t body_len = get_be16(d + 10);
  if (len < FRAME_HEADER + body_len + FRAME_TRAILER) throw FrameError("truncated frame");
  if (get_be16(d + FRAME_HEADER + body_len + 4) != FRAME_TAIL) throw FrameError("bad tail");
  if (get_be32(d + FRAME_HEADER + body_len) != crc32(d + 2, FRAME_HEADER - 2 + body_len))
    throw FrameError("CRC mismatch");
  Frame f;
  f.msg_type = d[3];
  f.transfer_id = get_be32(d + 4);
  f.sequence = get_be32(d + 12);
  f.body.assign(d + FRAME_HEADER, d + FRAME_HEADER + body_len);
  return f;
}

}  // namespace ctf
