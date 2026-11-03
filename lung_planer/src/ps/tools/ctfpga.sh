#!/usr/bin/env bash
# Run ctfpga on all cores: tools/ctfpga.sh --stage <all|ct2bin|...|cut> --case-dir DIR [options]
# The planner launchers pin OMP_NUM_THREADS=1; this resets it for the C++ pipeline.
# Options are those of ctfpga --help; build first with tools/build_ctfpga.sh.
set -euo pipefail

app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
binary="$app_dir/ctfpga/build-$(uname -m)/ctfpga"
if [[ ! -x "$binary" ]]; then
    echo "ctfpga is not built: run tools/build_ctfpga.sh" >&2
    exit 1
fi
# GNU nproc itself honors OMP_NUM_THREADS, so count cores without it.
export OMP_NUM_THREADS="${CTFPGA_THREADS:-$(env -u OMP_NUM_THREADS -u OMP_THREAD_LIMIT nproc)}"
# Smoothing/decimation recipe (ctfpga/scripts/run_smooth_cut.sh); later "$@" values win.
recipe=(--vessel-taubin 0 --cut-smooth 12
        --cut-lobe-faces 5000 --cut-airway-faces 38000 --cut-artery-faces 55000
        --cut-vein-faces 65000 --cut-tumor-faces 2000)
exec "$binary" "${recipe[@]}" "$@"
