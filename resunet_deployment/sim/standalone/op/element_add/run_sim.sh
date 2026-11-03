#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p verification/deployment "$HOME/.cache"
add_run_dir=$(mktemp -d "$HOME/.cache/elementadd-sim.XXXXXX")
mkdir -p "$add_run_dir/verification"
# 失败也归档黑匣子；通过前不生成正式交付 RTL。
trap 'tar -C "$add_run_dir/verification" --exclude="*/verilator" --exclude="*/rtl" -cf - . | tar -C verification/deployment -xf -' EXIT
python3 -B tools/generate_vectors.py --out "$add_run_dir/verification"
sbt "runMain ElementAddSim $add_run_dir/verification" 2>&1 | tee verification/deployment/run.log
sbt "runMain ElementAddGen" 2>&1 | tee verification/deployment/generation.log
verilator --lint-only -Wall --top-module ElementAdd_p16 rtl/elementadd_p16.v 2>&1 | tee verification/deployment/lint.log
