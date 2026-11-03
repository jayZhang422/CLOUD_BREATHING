// 七阶段状态表：终端逐行输出 + <case>/status.json（字段与 Python 版一致）。
#pragma once
#include "common/util.hpp"

namespace ctf {

class StageTable {
 public:
  explicit StageTable(const std::string& status_path);
  void set(const std::string& stage, const std::string& status, const std::string& detail = "");
  // 开始一个阶段；返回的 progress 回调更新 detail（节流写盘）。
  Progress begin(const std::string& stage);
  void done(const std::string& stage);
  void fail(const std::string& stage, const std::string& why);

 private:
  struct Row { std::string status = "Queue", start = "--", detail; double elapsed = 0, since = -1; };
  void save();
  std::string path_;
  std::vector<std::string> order_;
  std::vector<Row> rows_;
  double last_save_ = 0, last_print_ = 0;
  Row& row(const std::string& s);
};

}  // namespace ctf
