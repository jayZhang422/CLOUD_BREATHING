#!/usr/bin/env bash
# 对已有预测 BIN 运行 C++ 网格三阶段，记录每阶段耗时与峰值内存（GNU time）。
# 用法：scripts/run_mesh.sh [build_dir] [case_dir] [prediction_dir] [ct_metadata]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYDIR="$(cd "$HERE/../../python/PC_FPGA" && pwd)"
BUILD="${1:-$HOME/ctfpga_build_vtk}"
CASE="${2:-$HOME/ctf_cases/mesh_cpp}"
PRED="${3:-$PYDIR/output/ct_03_q4/prediction}"
CTM="${4:-$PYDIR/output/ct_03_q4/input/metadata.json}"

rm -rf "$CASE"
mkdir -p "$CASE"
for stage in bin2stl smooth cut; do
  echo "=== $stage ==="
  extra=()
  [ "$stage" = bin2stl ] && extra=(--prediction-dir "$PRED" --ct-metadata "$CTM")
  # CPUSET 例如 "0-3" 限制到 4 核，用来近似 KV260 的核数（不代表 A53 的单核速度）。
  /usr/bin/time -f "$stage wall=%es user=%Us maxrss=%MKB" \
    ${CPUSET:+taskset -c "$CPUSET"} "$BUILD/ctfpga" --stage "$stage" --case-dir "$CASE" "${extra[@]}" --assets "$PYDIR/assets" 2>&1 | grep -v -E "^\[(BIN2STL|Smooth|Cut) +\] [0-9]/" | tail -12
done
