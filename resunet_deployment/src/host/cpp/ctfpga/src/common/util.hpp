// 公共工具：SHA256 / CRC32 / 字节序 / 文件与 JSON 原子读写。
// 无 OpenSSL、zlib 依赖，便于在 KV260 (aarch64) 上直接编译。
#pragma once
#include <cstdint>
#include <cstring>
#include <functional>
#include <stdexcept>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>

namespace ctf {

using json = nlohmann::ordered_json;  // 保持插入顺序，与 Python 版 JSON 键序一致

struct Error : std::runtime_error {
  using std::runtime_error::runtime_error;
};

// ---------- 哈希 ----------
class Sha256 {
 public:
  Sha256() { reset(); }
  void reset();
  void update(const void* data, size_t len);
  std::string hex();  // 结束并返回 64 位十六进制；之后需 reset()
 private:
  void block(const uint8_t* p);
  uint32_t h_[8];
  uint8_t buf_[64];
  size_t fill_ = 0;
  uint64_t total_ = 0;
};

uint32_t crc32_update(uint32_t crc, const void* data, size_t len);  // 与 zlib.crc32 等价
inline uint32_t crc32(const void* d, size_t n) { return crc32_update(0, d, n); }

std::string sha256_hex(const void* data, size_t len);
std::string sha256_file(const std::string& path);
uint32_t crc32_file(const std::string& path);

// ---------- 字节序 ----------
inline void put_le16(uint8_t* p, uint32_t v) { p[0] = v; p[1] = v >> 8; }
inline void put_le32(uint8_t* p, uint32_t v) { for (int i = 0; i < 4; ++i) p[i] = v >> (8 * i); }
inline void put_be16(uint8_t* p, uint32_t v) { p[0] = v >> 8; p[1] = v; }
inline void put_be32(uint8_t* p, uint32_t v) { for (int i = 0; i < 4; ++i) p[i] = v >> (24 - 8 * i); }
inline uint32_t get_le16(const uint8_t* p) { return p[0] | (p[1] << 8); }
inline uint32_t get_le32(const uint8_t* p) { return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24); }
inline uint32_t get_be16(const uint8_t* p) { return (p[0] << 8) | p[1]; }
inline uint32_t get_be32(const uint8_t* p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }

// ---------- 小工具 ----------
inline uint64_t align_up(uint64_t v, uint64_t a = 32) { return (v + a - 1) / a * a; }
std::string to_hex(const uint8_t* p, size_t n);
std::vector<uint8_t> from_hex(const std::string& s);
double now_seconds();                      // 单调时钟
std::string iso_now();                     // 本地时间 ISO8601
std::string fmt(const char* f, ...) __attribute__((format(printf, 1, 2)));

// 向量化的最近偶数舍入（等价 numpy.rint，需默认舍入模式）。
inline double rint_even(double x);

// ---------- 文件 ----------
bool file_exists(const std::string& path);
uint64_t file_size(const std::string& path);
void make_dirs(const std::string& path);
std::string parent_dir(const std::string& path);
std::string join(const std::string& a, const std::string& b);
std::vector<uint8_t> read_file(const std::string& path);
void write_file_atomic(const std::string& path, const void* data, size_t len);
json read_json(const std::string& path);
void write_json(const std::string& path, const json& v);  // 临时文件 + rename
void rename_file(const std::string& from, const std::string& to);
void remove_file(const std::string& path);

// 校验文件长度和 SHA256（等价 files.check_file）。
void check_file(const std::string& path, uint64_t size, const std::string& sha);

// 带哈希的顺序写文件：边写边算 SHA256，避免二次读盘。
class HashedWriter {
 public:
  explicit HashedWriter(const std::string& path);
  ~HashedWriter();
  void write(const void* data, size_t len);
  void zeros(size_t len);
  uint64_t position() const { return pos_; }
  uint32_t crc() const { return crc_; }
  std::string finish_hex();  // 关闭文件并返回 SHA256
 private:
  FILE* f_ = nullptr;
  Sha256 sha_;
  uint64_t pos_ = 0;
  uint32_t crc_ = 0;
  bool done_ = false;
};

using Progress = std::function<void(const std::string&)>;

}  // namespace ctf

#include <cmath>
namespace ctf {
inline double rint_even(double x) { return std::nearbyint(x); }
}  // namespace ctf
