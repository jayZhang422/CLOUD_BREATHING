#!/usr/bin/env bash
# Run on the KV260 (Ubuntu 22.04 + PYNQ) inside the deployed app directory.
#   bash run_on_board.sh check   # verify bit/hwh hashes, admission record and gated source hashes
#   bash run_on_board.sh tests   # full unit/integration suite (297 tests, PL mocked, ~1 min)
#   bash run_on_board.sh admit [VECTORS_DIR]
#                                # regenerate fpga/mesh-full.json on hardware from the synthetic
#                                # cube vectors (default: $APP_DIR/vectors, shipped by deploy.sh)
#   bash run_on_board.sh points  # dual-plane point filter, 4096..16385 points, cancel/timeout recovery
#   bash run_on_board.sh union   # multi-solid ray union and union volume on synthetic boxes
#   bash run_on_board.sh raymesh # BVH ray core capacity (1, 8002 triangles), repeat and recovery
#   bash run_on_board.sh bench   # PL vs PS timing of the dual-plane mesh kernel on a synthetic mesh
#   bash run_on_board.sh gui     # full-screen Qt planner on the HDMI display (max 1 h)
# points/union/raymesh/bench write JSON to $OUT_DIR (default ./board-results). bench takes about 5 minutes.
set -euo pipefail
app="${APP_DIR:-/home/ubuntu/memgmo/final/cloud-breathing-kv260}"
py="${CLOUD_BREATHING_PYTHON:-/home/ubuntu/cloud-breathing-venv/bin/python}"
pynq_py="${PYNQ_PYTHON:-/usr/local/share/pynq-venv/bin/python}"
rel="$app/fpga"
out="${OUT_DIR:-$app/board-results}"
cd "$app"
# start_pl_service.sh restores XRT/PYNQ paths; without it xclbinutil cannot run under sudo.
# PYNQ remembers the bitstream path of the last load in a global state file; if that file was in a
# directory that has since been removed or moved, every Overlay load fails with "Unable to parse
# metadata". Drop such a stale record first.
pl() {
    sudo "$pynq_py" - <<'PY'
import json, os
from pynq.pl_server.global_state import clear_global_state
from pynq.pl_server import global_state
path = os.path.join(global_state.STATE_DIR, 'global_pl_state.json')
if os.path.isfile(path) and not os.path.isfile(json.load(open(path)).get('bitfile_name', '')):
    clear_global_state()
PY
    sudo LUNG_PL_BIT="$rel/lung_planner.bit" bash tools/start_pl_service.sh "$pynq_py" "$1" /usr "${@:2}"
}
case "${1:-check}" in
    check)   bash tools/start_desktop.sh --check ;;
    tests)   cd tests && env -u LUNG_PL_ENABLE -u DUAL_PLANE_MESH_ENABLE PYTHONPATH="$app" \
                 "$py" -m unittest discover -s . -p 'test_*.py' ;;
    admit)   pl tools/verify_dual_plane_board.py --vectors "${2:-$app/vectors}" \
                 --bit "$rel/lung_planner.bit" --output "$rel/mesh-full.json"
             sudo chown "$(id -un):$(id -gn)" "$rel/mesh-full.json" ;;
    points)  mkdir -p "$out"; pl tools/verify_point_batches_board.py --output "$out/hardware-points.json" ;;
    union)   mkdir -p "$out"; pl tools/verify_ray_union_board.py --bit "$rel/lung_planner.bit" \
                 --output "$out/ray-union.json" ;;
    raymesh) mkdir -p "$out"; pl tools/verify_ray_mesh_board.py --bit "$rel/lung_planner.bit" \
                 --triangles 1 8002 --repeat 3 --skip-golden --out "$out/ray-mesh-board.json" ;;
    bench)   mkdir -p "$out"; b=tools/benchmark_mesh_pl_vs_ps.py
             "$py" $b gen --inputs "$out/bench_inputs.npz"
             PYTHONPATH="$app" "$py" $b ps --inputs "$out/bench_inputs.npz" --out "$out/ps.json" --repeats 3
             sudo rm -f "$out/pl.json"
             pl $b pl --inputs "$out/bench_inputs.npz" --out "$out/pl.json" --bit "$rel/lung_planner.bit" --repeats 5
             sudo chown "$(id -un):$(id -gn)" "$out/pl.json"
             "$py" $b compare --ps "$out/ps.json" --pl "$out/pl.json" --out "$out/compare.json" ;;
    gui)     bash tools/start_desktop.sh ;;
    *)       echo "usage: $0 check|tests|admit [VECTORS_DIR]|points|union|raymesh|bench|gui" >&2; exit 2 ;;
esac
