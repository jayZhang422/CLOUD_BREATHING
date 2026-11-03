#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p verification/deployment "$HOME/.cache"
maxpool_run_dir=$(mktemp -d "$HOME/.cache/maxpool-sim.XXXXXX")
mkdir -p "$maxpool_run_dir/verification"
# 失败也保存黑匣子；仿真在 WSL 本地盘运行，结束后归档回工程。
trap 'tar -C "$maxpool_run_dir/verification" --exclude="*/verilator" --exclude="*/rtl" -cf - . | tar -C verification/deployment -xf -' EXIT
python3 -B tools/generate_maxpool_vectors.py --out "$maxpool_run_dir/verification"
sbt "runMain MaxPoolSim $maxpool_run_dir/verification" 2>&1 | tee verification/deployment/run.log
sbt "runMain MaxPoolGen" 2>&1 | tee verification/deployment/generation.log
verilator --lint-only -Wall --top-module MaxPool2d_512x512_c16 rtl/maxpool2d_512x512_c16.v 2>&1 | tee verification/deployment/lint.log
