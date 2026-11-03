#include <cstdio>

#include "common/util.hpp"

using namespace ctf;

static int failures = 0;
#define CHECK(c) do { if (!(c)) { std::printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); ++failures; } } while (0)

int main() {
  CHECK(sha256_hex("", 0) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  CHECK(sha256_hex("abc", 3) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  // 跨块边界（56 字节触发双块填充）
  CHECK(sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 56) ==
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  // 分段更新与一次性更新一致
  {
    std::vector<uint8_t> big(100003);
    for (size_t i = 0; i < big.size(); ++i) big[i] = (uint8_t)(i * 31 + 7);
    Sha256 s;
    for (size_t i = 0; i < big.size();) { size_t n = std::min<size_t>(1 + i % 97, big.size() - i); s.update(&big[i], n); i += n; }
    CHECK(s.hex() == sha256_hex(big.data(), big.size()));
  }
  CHECK(crc32("123456789", 9) == 0xCBF43926u);
  CHECK(crc32("", 0) == 0);
  {
    std::vector<uint8_t> d(5000);
    for (size_t i = 0; i < d.size(); ++i) d[i] = (uint8_t)(i * 13);
    uint32_t whole = crc32(d.data(), d.size());
    uint32_t part = crc32_update(crc32_update(0, d.data(), 1234), d.data() + 1234, d.size() - 1234);
    CHECK(whole == part);
  }
  uint8_t b[4];
  put_be32(b, 0x01020304); CHECK(b[0] == 1 && b[3] == 4 && get_be32(b) == 0x01020304u);
  put_le32(b, 0x01020304); CHECK(b[0] == 4 && b[3] == 1 && get_le32(b) == 0x01020304u);
  CHECK(from_hex("00ff10") == (std::vector<uint8_t>{0, 255, 16}));
  CHECK(align_up(33) == 64 && align_up(64) == 64 && align_up(0) == 0);
  CHECK(rint_even(0.5) == 0 && rint_even(1.5) == 2 && rint_even(2.5) == 2 && rint_even(-0.5) == 0 && rint_even(-1.5) == -2);
  if (failures == 0) std::puts("test_util OK");
  return failures != 0;
}
