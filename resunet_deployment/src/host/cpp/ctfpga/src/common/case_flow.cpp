#include "common/case_flow.hpp"

#include <cstdio>

namespace ctf {

StageTable::StageTable(const std::string& status_path) : path_(status_path) {
  order_ = {"CT2BIN", "Send", "Reasoning", "Receive", "BIN2STL", "Smooth", "Cut"};
  rows_.resize(order_.size());
  save();
}

StageTable::Row& StageTable::row(const std::string& s) {
  for (size_t i = 0; i < order_.size(); ++i) if (order_[i] == s) return rows_[i];
  throw Error("未知阶段: " + s);
}

void StageTable::save() {
  json j = json::object();
  const double now = now_seconds();
  for (size_t i = 0; i < order_.size(); ++i) {
    const Row& r = rows_[i];
    json o = json::object();
    o["status"] = r.status;
    o["start"] = r.start;
    o["elapsed_seconds"] = r.elapsed + (r.since >= 0 ? now - r.since : 0.0);
    o["detail"] = r.detail;
    j[order_[i]] = o;
  }
  write_json(path_, j);
  last_save_ = now;
}

void StageTable::set(const std::string& stage, const std::string& status, const std::string& detail) {
  Row& r = row(stage);
  r.status = status;
  r.detail = detail;
  std::printf("[%-9s] %-8s %s\n", stage.c_str(), status.c_str(), detail.c_str());
  std::fflush(stdout);
  save();
}

Progress StageTable::begin(const std::string& stage) {
  Row& r = row(stage);
  r.status = "Running";
  r.start = iso_now();
  r.since = now_seconds();
  std::printf("[%-9s] Running\n", stage.c_str());
  std::fflush(stdout);
  save();
  return [this, stage](const std::string& text) {
    Row& rr = row(stage);
    rr.detail = text;
    const double now = now_seconds();
    if (now - last_print_ >= 1.0) {
      std::printf("[%-9s] %s\n", stage.c_str(), text.c_str());
      std::fflush(stdout);
      last_print_ = now;
    }
    if (now - last_save_ >= 1.0) save();
  };
}

void StageTable::done(const std::string& stage) {
  Row& r = row(stage);
  r.elapsed += r.since >= 0 ? now_seconds() - r.since : 0;
  r.since = -1;
  r.status = "Done";
  std::printf("[%-9s] Done     %.2fs  %s\n", stage.c_str(), r.elapsed, r.detail.c_str());
  std::fflush(stdout);
  save();
}

void StageTable::fail(const std::string& stage, const std::string& why) {
  Row& r = row(stage);
  r.elapsed += r.since >= 0 ? now_seconds() - r.since : 0;
  r.since = -1;
  r.status = "Failed";
  r.detail = why;
  std::printf("[%-9s] Failed   %s\n", stage.c_str(), why.c_str());
  std::fflush(stdout);
  save();
}

}  // namespace ctf
