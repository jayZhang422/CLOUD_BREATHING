// 整卷 DDR 作业：执行清单构造、VOL2 上传、START/QUERY 轮询、结果回读。对应 Python transfer.py + volume.py。
#pragma once
#include "common/util.hpp"
#include "net/op_client.hpp"

namespace ctf {

struct NetCfg {
  std::string host = "192.168.1.10";
  int port = 8080;
  std::string bind = "192.168.1.102";
  double timeout = 1.0;
};

struct ProgramCtx {
  uint8_t model = 0;   // 0 lobe 1 airway 2 vessel 3 tumor
  int32_t slice = 0;
  int16_t stage = 0;   // >=0 为计划阶段序号；-1 gather；-2 classify；-3 END
};

struct Program {
  std::vector<uint8_t> records;  // 96 B / 条
  std::vector<uint8_t> maps;     // 坐标表
  std::vector<uint8_t> header;   // 64 B START 体
  json summaries;
  std::vector<ProgramCtx> ctx;
  size_t commands() const { return records.size() / 96; }
};

// 冻结资产目录（volume_plans.json、tumor.params.bin、volume_assets.json）。
std::string find_assets_dir(const std::string& hint);
json load_plans(const std::string& assets_dir);  // 同时校验 volume_assets.json 中的 SHA256

Program build_program(const json& job, const json& metadata, const json& plans);

json send_volume(const std::string& case_dir, const json& job, const NetCfg& net, const Progress& progress);
json upload_program(const std::string& case_dir, const json& job, const NetCfg& net,
                    const std::string& assets_dir, const Progress& progress);
// 发 START 并轮询；成功后写 handoff/result_ready.json 并返回其路径。
std::string reason_volume(const std::string& case_dir, const NetCfg& net, double run_timeout, double stall_timeout,
                          const std::string& assets_dir, const Progress& progress);
json receive_result(const std::string& case_dir, const std::string& manifest, const NetCfg& net,
                    const Progress& progress);

// 位掩码合法性：保留位、肺叶互斥、动静脉互斥。bad 返回首个非法体素的下标，否则 -1。
int64_t validate_bits(const uint16_t* plane, size_t n);

}  // namespace ctf
