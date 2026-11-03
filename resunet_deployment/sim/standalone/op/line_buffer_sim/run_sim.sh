#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p verification/deployment "$HOME/.cache"
# WSL 本地盘运行，避免每拍 CSV/FST 写入跨系统挂载盘。
linebuffer_run_dir=$(mktemp -d "$HOME/.cache/linebuffer-sim.XXXXXX")
mkdir -p "$linebuffer_run_dir/verification"
# 失败也归档黑匣子；保留波形，略去 Verilator 编译缓存和重复 RTL。
trap 'tar -C "$linebuffer_run_dir/verification" --exclude="*/verilator" --exclude="*/rtl" -cf - . | tar -C verification/deployment -xf -' EXIT
python3 -B tools/generate_vectors.py --out "$linebuffer_run_dir/verification"
sbt "runMain LineBufferSim $linebuffer_run_dir/verification" 2>&1 | tee verification/deployment/run.log
sbt "runMain LineBufferGen" 2>&1 | tee verification/deployment/generation.log
