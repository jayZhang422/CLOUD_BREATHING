#include <cstdio>

#include "net/protocol.hpp"
#include "net/volume_ctl.hpp"

using namespace ctf;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

int main() {
  auto f = build_frame(MSG_STATUS, 0x12345678, 7, nullptr, 0);
  CHECK(f.size() == 22);
  CHECK(to_hex(f.data(), 16) == "55aa0122123456780010000000000007");
  CHECK(get_be16(&f[20]) == 0xAA55);
  Frame p = parse_frame(f.data(), f.size());
  CHECK(p.msg_type == MSG_STATUS && p.transfer_id == 0x12345678u && p.sequence == 7 && p.body.empty());

  std::vector<uint8_t> body(1032);
  for (size_t i = 0; i < body.size(); ++i) body[i] = (uint8_t)(i * 7);
  auto g = build_frame(MSG_WRITE, 0, 0xFFFFFFFFu, body);
  Frame q = parse_frame(g.data(), g.size());
  CHECK(q.body == body && q.sequence == 0xFFFFFFFFu);

  // 篡改任意一位都应被拒绝
  for (size_t pos : {size_t(2), size_t(5), size_t(20), g.size() - 7, g.size() - 3}) {
    auto h = g;
    h[pos] ^= 0x01;
    bool rejected = false;
    try { parse_frame(h.data(), h.size()); } catch (const FrameError&) { rejected = true; }
    CHECK(rejected);
  }
  bool short_rejected = false;
  try { parse_frame(g.data(), 10); } catch (const FrameError&) { short_rejected = true; }
  CHECK(short_rejected);

  // 位掩码合法性
  uint16_t ok[] = {0, 1, 2, 4, 8, 16, 32, 64, 128, 256, 1 | 32 | 64, 16 | 128 | 256};
  CHECK(validate_bits(ok, 12) < 0);
  uint16_t two_lobes[] = {0, 3};  CHECK(validate_bits(two_lobes, 2) == 1);
  uint16_t av[] = {0, 0, 192};    CHECK(validate_bits(av, 3) == 2);
  uint16_t reserved[] = {512};    CHECK(validate_bits(reserved, 1) == 0);
  if (failures == 0) std::puts("test_protocol OK");
  return failures != 0;
}
