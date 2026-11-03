#!/usr/bin/env bash
# 仅仿真 Concat；日志、波形和逐周期 CSV 归档到 verification。
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p verification
python3 tb/generate_vectors.py
verilator -Wall --cc --top-module tb_concat rtl/concat.sv rtl/tb_concat.sv \
    --exe tb/tb_concat.cpp --trace-fst --assert --build -j 4 -Mdir obj_dir \
    > verification/build.log 2>&1
# 在 WSL 本地盘逐拍刷新黑匣子，结束或失败后复制回工程目录。
concat_trace_dir=$(mktemp -d /tmp/concat-trace.XXXXXX)
trap 'cp -a "$concat_trace_dir/." verification/' EXIT
./obj_dir/Vtb_concat verification "$concat_trace_dir" 2>&1 | tee verification/run.log
