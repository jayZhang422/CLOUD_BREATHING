#!/usr/bin/env bash
# 从已有 bin2stl 结果（stl/raw）复现“平滑 v4 + 减面”整条配方，不覆盖原病例目录。
# 用法：scripts/run_smooth_cut.sh <源病例目录(含 stl/raw)> <新病例目录> [build_dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYDIR="$(cd "$HERE/../../python/PC_FPGA" && pwd)"
SRC="$(cd "$1" && pwd)"; DST="$2"; BUILD="${3:-$HOME/ctfpga_build_vtk}"
[ -d "$SRC/stl/raw" ] || { echo "缺少 $SRC/stl/raw"; exit 2; }
[ ! -e "$DST/stl/smooth" ] || { echo "$DST/stl/smooth 已存在（阶段不允许覆盖）"; exit 2; }
mkdir -p "$DST/stl"
cp -r "$SRC/stl/raw" "$DST/stl/"; cp "$SRC/status.json" "$DST/"
DST_ABS="$(cd "$DST" && pwd)"
sed -i "s#$SRC#$DST_ABS#g" "$DST/stl/raw/manifest.json"   # manifest 内含绝对路径
"$BUILD/ctfpga" --stage smooth --case-dir "$DST" --assets "$PYDIR/assets" --vessel-taubin 0
"$BUILD/ctfpga" --stage cut    --case-dir "$DST" --assets "$PYDIR/assets" \
  --cut-lobe-faces 5000 --cut-airway-faces 38000 --cut-artery-faces 55000 \
  --cut-vein-faces 65000 --cut-tumor-faces 2000 --cut-smooth 12
