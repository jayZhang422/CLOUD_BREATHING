// CT2BIN：DICOM → 原生网格 INT8 BIN，以及整卷作业描述 job.json。
#pragma once
#include "common/util.hpp"

namespace ctf {

const std::vector<std::string>& channel_names();  // 九结构，顺序固定

// 读 DICOM，写 <case>/input/ct_volume_int8.bin 与 metadata.json；已存在且校验通过则复用。
json prepare_ct(const std::string& data, const std::string& case_dir, const std::string& series_uid,
                const Progress& progress);

// 生成 VOL2 视图与 handoff/job.json。
json make_job(const std::string& case_dir, uint64_t image_base, int batch_slices, bool transpose,
              const Progress& progress);

}  // namespace ctf
