#!/usr/bin/env bash
set -euo pipefail
board_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$board_dir/../../.." && pwd)
op_dir="$repo_dir/src/rtl/op"
work_dir=$(mktemp -d /tmp/op-board-joint.XXXXXX)
mkdir -p "$work_dir/vectors" "$work_dir/artifacts" "$board_dir/results"
printf 'Temporary simulation directory: %s\n' "$work_dir"
python3 "$board_dir/tb/generate_vectors.py" --out "$work_dir/vectors"
sources=(
    "$board_dir/rtl/tb_op_candidate.sv" "$board_dir/rtl/op_coeff_split.sv"
    "$op_dir/control/op_service.sv" "$op_dir/control/op_engine.sv"
    "$op_dir/control/op_descriptor_check.sv"
    "$board_dir/rtl/op_core_bank.sv" "$op_dir/control/op_feature_reader.sv"
    "$op_dir/control/op_feature_writer.sv" "$op_dir/control/op_ddr_port.sv"
    "$repo_dir/sim/standalone/op/pw/rtl/pwmac.v"
    "$repo_dir/sim/standalone/op/maxpool/maxpool2d_512x512_c16.v"
    "$repo_dir/sim/standalone/op/line_buffer_sim/linebuffer_3x3.v"
    "$repo_dir/sim/standalone/op/line_buffer_sim/linebuffer_5x5.v"
    "$op_dir/concat/concat.sv" "$repo_dir/sim/standalone/op/element_add/elementadd_p16.v"
    "$op_dir/Shuffle/channel_shuffle.sv"
)
python3 - "${sources[@]}" "$board_dir/tb/joint_driver.cpp" "$board_dir/tb/generate_vectors.py" >"$board_dir/results/sources.sha256" <<'PY'
import hashlib, sys
for name in sys.argv[1:]:
    with open(name, "rb") as src:
        print(hashlib.sha256(src.read()).hexdigest(), name)
PY
if ! verilator -Wall -Wno-fatal --assert --cc --exe --build -j 4 --trace-fst \
    --top-module tb_op_candidate --Mdir "$work_dir/build" -o joint_sim \
    -CFLAGS '-std=c++17' "${sources[@]}" "$board_dir/tb/joint_driver.cpp" \
    >"$work_dir/build.log" 2>&1; then
    tail -n 60 "$work_dir/build.log"
    printf 'Build failed; evidence retained: %s\n' "$work_dir"
    exit 1
fi
verilator --version >"$board_dir/results/backend.txt"
set +e
"$work_dir/build/joint_sim" "$work_dir/vectors" "$work_dir/artifacts" \
    2>&1 | tee "$board_dir/results/run.log"
run_status=${PIPESTATUS[0]}
set -e
if ((run_status != 0)); then
    mkdir -p "$board_dir/results/failure"
    cp "$work_dir/artifacts/sim_trace.csv" "$work_dir/artifacts/joint_waveform.fst" \
       "$work_dir/build.log" "$board_dir/results/failure/"
    printf 'Simulation failed; evidence retained in results/failure and %s\n' "$work_dir"
    exit "$run_status"
fi
cp "$work_dir/build.log" "$board_dir/results/build.log"
if [[ ${KEEP_ARTIFACTS:-0} == 1 ]]; then
    printf 'Simulation artifacts retained: %s\n' "$work_dir"
else
    # Only delete this script's resolved mktemp directory after a successful run.
    [[ "$work_dir" == /tmp/op-board-joint.* && -d "$work_dir" ]]
    rm -rf -- "$work_dir"
    printf 'PASS: temporary vectors, build files, FST and CSV removed.\n'
fi
