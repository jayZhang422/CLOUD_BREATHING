#!/usr/bin/env bash
# 在 4 核 / 1 核限制下分别跑网格三阶段，用来近似 KV260 的核数。
# 注意：这只限制核数，不代表 Cortex-A53 的单核速度（通常明显慢于 x86 大核）。
# 用法：scripts/bench_cores.sh [build_dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="${1:-$HOME/ctfpga_build_vtk}"
for set in 0-3 0; do
  echo "##### CPUSET=$set"
  CPUSET="$set" OMP_NUM_THREADS="$(taskset -c "$set" nproc)" \
    bash "$HERE/run_mesh.sh" "$BUILD" "$HOME/ctf_cases/mesh_cpu_${set}" 2>&1 | grep -E "wall="
done
