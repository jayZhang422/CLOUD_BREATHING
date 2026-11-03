#include "common/util.hpp"

#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <cstdarg>
#include <cstdio>

namespace ctf {

// ======================= SHA256 =======================
static const uint32_t K256[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

static inline uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }

void Sha256::reset() {
  static const uint32_t init[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  std::memcpy(h_, init, sizeof h_);
  fill_ = 0;
  total_ = 0;
}

void Sha256::block(const uint8_t* p) {
  uint32_t w[64];
  for (int i = 0; i < 16; ++i) w[i] = get_be32(p + 4 * i);
  for (int i = 16; i < 64; ++i) {
    uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
    uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  uint32_t a = h_[0], b = h_[1], c = h_[2], d = h_[3], e = h_[4], f = h_[5], g = h_[6], h = h_[7];
  for (int i = 0; i < 64; ++i) {
    uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    uint32_t ch = (e & f) ^ (~e & g);
    uint32_t t1 = h + S1 + ch + K256[i] + w[i];
    uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
    uint32_t t2 = S0 + mj;
    h = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
  }
  h_[0] += a; h_[1] += b; h_[2] += c; h_[3] += d; h_[4] += e; h_[5] += f; h_[6] += g; h_[7] += h;
}

void Sha256::update(const void* data, size_t len) {
  const uint8_t* p = static_cast<const uint8_t*>(data);
  total_ += len;
  if (fill_) {
    size_t n = std::min(len, 64 - fill_);
    std::memcpy(buf_ + fill_, p, n);
    fill_ += n; p += n; len -= n;
    if (fill_ == 64) { block(buf_); fill_ = 0; }
  }
  while (len >= 64) { block(p); p += 64; len -= 64; }
  if (len) { std::memcpy(buf_, p, len); fill_ = len; }
}

std::string Sha256::hex() {
  uint64_t bits = total_ * 8;
  uint8_t pad[72] = {0x80};
  size_t padlen = (fill_ < 56) ? (56 - fill_) : (120 - fill_);
  uint8_t len[8];
  for (int i = 0; i < 8; ++i) len[i] = bits >> (56 - 8 * i);
  update(pad, padlen);
  update(len, 8);
  uint8_t out[32];
  for (int i = 0; i < 8; ++i) put_be32(out + 4 * i, h_[i]);
  return to_hex(out, 32);
}

std::string sha256_hex(const void* data, size_t len) {
  Sha256 s; s.update(data, len); return s.hex();
}

std::string sha256_file(const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) throw Error("无法打开文件: " + path);
  Sha256 s;
  std::vector<uint8_t> buf(1 << 20);
  size_t n;
  while ((n = std::fread(buf.data(), 1, buf.size(), f)) > 0) s.update(buf.data(), n);
  std::fclose(f);
  return s.hex();
}

// ======================= CRC32 (slice-by-8) =======================
namespace {
struct CrcTable {
  uint32_t t[8][256];
  CrcTable() {
    for (uint32_t i = 0; i < 256; ++i) {
      uint32_t c = i;
      for (int k = 0; k < 8; ++k) c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
      t[0][i] = c;
    }
    for (uint32_t i = 0; i < 256; ++i)
      for (int s = 1; s < 8; ++s) t[s][i] = (t[s - 1][i] >> 8) ^ t[0][t[s - 1][i] & 0xFF];
  }
};
const CrcTable& crc_table() { static CrcTable t; return t; }
}  // namespace

uint32_t crc32_update(uint32_t crc, const void* data, size_t len) {
  const auto& T = crc_table();
  const uint8_t* p = static_cast<const uint8_t*>(data);
  uint32_t c = ~crc;
  while (len >= 8) {
    uint32_t a = c ^ get_le32(p);
    uint32_t b = get_le32(p + 4);
    c = T.t[7][a & 0xFF] ^ T.t[6][(a >> 8) & 0xFF] ^ T.t[5][(a >> 16) & 0xFF] ^ T.t[4][a >> 24] ^
        T.t[3][b & 0xFF] ^ T.t[2][(b >> 8) & 0xFF] ^ T.t[1][(b >> 16) & 0xFF] ^ T.t[0][b >> 24];
    p += 8; len -= 8;
  }
  while (len--) c = T.t[0][(c ^ *p++) & 0xFF] ^ (c >> 8);
  return ~c;
}

uint32_t crc32_file(const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) throw Error("无法打开文件: " + path);
  std::vector<uint8_t> buf(1 << 20);
  uint32_t c = 0;
  size_t n;
  while ((n = std::fread(buf.data(), 1, buf.size(), f)) > 0) c = crc32_update(c, buf.data(), n);
  std::fclose(f);
  return c;
}

// ======================= 杂项 =======================
std::string to_hex(const uint8_t* p, size_t n) {
  static const char* d = "0123456789abcdef";
  std::string s(n * 2, '0');
  for (size_t i = 0; i < n; ++i) { s[2 * i] = d[p[i] >> 4]; s[2 * i + 1] = d[p[i] & 15]; }
  return s;
}

std::vector<uint8_t> from_hex(const std::string& s) {
  if (s.size() % 2) throw Error("十六进制长度为奇数");
  auto nib = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    throw Error("非法十六进制字符");
  };
  std::vector<uint8_t> out(s.size() / 2);
  for (size_t i = 0; i < out.size(); ++i) out[i] = (nib(s[2 * i]) << 4) | nib(s[2 * i + 1]);
  return out;
}

double now_seconds() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

std::string iso_now() {
  time_t t = time(nullptr);
  tm lt;
  localtime_r(&t, &lt);
  char b[64];
  std::strftime(b, sizeof b, "%Y-%m-%dT%H:%M:%S%z", &lt);
  return b;
}

std::string fmt(const char* f, ...) {
  va_list ap, ap2;
  va_start(ap, f);
  va_copy(ap2, ap);
  int n = std::vsnprintf(nullptr, 0, f, ap);
  va_end(ap);
  std::string s(n > 0 ? n : 0, '\0');
  if (n > 0) std::vsnprintf(&s[0], n + 1, f, ap2);
  va_end(ap2);
  return s;
}

bool file_exists(const std::string& path) {
  struct stat st;
  return ::stat(path.c_str(), &st) == 0;
}

uint64_t file_size(const std::string& path) {
  struct stat st;
  if (::stat(path.c_str(), &st) != 0) throw Error("文件不存在: " + path);
  return st.st_size;
}

void make_dirs(const std::string& path) {
  if (path.empty() || file_exists(path)) return;
  auto pos = path.find_last_of('/');
  if (pos != std::string::npos && pos > 0) make_dirs(path.substr(0, pos));
  ::mkdir(path.c_str(), 0755);
}

std::string parent_dir(const std::string& path) {
  auto pos = path.find_last_of('/');
  return pos == std::string::npos ? "." : (pos == 0 ? "/" : path.substr(0, pos));
}

std::string join(const std::string& a, const std::string& b) {
  if (a.empty()) return b;
  if (!b.empty() && b[0] == '/') return b;
  return a.back() == '/' ? a + b : a + "/" + b;
}

std::vector<uint8_t> read_file(const std::string& path) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) throw Error("无法打开文件: " + path);
  std::fseek(f, 0, SEEK_END);
  long n = std::ftell(f);
  std::fseek(f, 0, SEEK_SET);
  std::vector<uint8_t> v(n);
  if (n && std::fread(v.data(), 1, n, f) != (size_t)n) { std::fclose(f); throw Error("读取失败: " + path); }
  std::fclose(f);
  return v;
}

void write_file_atomic(const std::string& path, const void* data, size_t len) {
  make_dirs(parent_dir(path));
  std::string tmp = path + ".tmp";
  FILE* f = std::fopen(tmp.c_str(), "wb");
  if (!f) throw Error("无法写入: " + tmp);
  if (len && std::fwrite(data, 1, len, f) != len) { std::fclose(f); throw Error("写入失败: " + tmp); }
  std::fclose(f);
  rename_file(tmp, path);
}

void rename_file(const std::string& from, const std::string& to) {
  if (std::rename(from.c_str(), to.c_str()) != 0) throw Error("重命名失败: " + from + " -> " + to);
}

void remove_file(const std::string& path) { std::remove(path.c_str()); }

json read_json(const std::string& path) {
  auto raw = read_file(path);
  size_t off = (raw.size() >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF) ? 3 : 0;
  return json::parse(raw.begin() + off, raw.end());
}

void write_json(const std::string& path, const json& v) {
  std::string s = v.dump(2, ' ', false, json::error_handler_t::replace) + "\n";
  write_file_atomic(path, s.data(), s.size());
}

void check_file(const std::string& path, uint64_t size, const std::string& sha) {
  if (file_size(path) != size || sha256_file(path) != sha) throw Error("文件长度或 SHA256 不符：" + path);
}

// ======================= HashedWriter =======================
HashedWriter::HashedWriter(const std::string& path) {
  make_dirs(parent_dir(path));
  f_ = std::fopen(path.c_str(), "wb");
  if (!f_) throw Error("无法写入: " + path);
  std::setvbuf(f_, nullptr, _IOFBF, 1 << 20);  // 大缓冲减少存储卡小写
}

HashedWriter::~HashedWriter() {
  if (f_) std::fclose(f_);
}

void HashedWriter::write(const void* data, size_t len) {
  if (!len) return;
  if (std::fwrite(data, 1, len, f_) != len) throw Error("写入失败");
  sha_.update(data, len);
  crc_ = crc32_update(crc_, data, len);
  pos_ += len;
}

void HashedWriter::zeros(size_t len) {
  static const uint8_t z[4096] = {0};
  while (len) {
    size_t n = std::min(len, sizeof z);
    write(z, n);
    len -= n;
  }
}

std::string HashedWriter::finish_hex() {
  if (std::fclose(f_) != 0) { f_ = nullptr; throw Error("关闭文件失败"); }
  f_ = nullptr;
  done_ = true;
  return sha_.hex();
}

}  // namespace ctf
