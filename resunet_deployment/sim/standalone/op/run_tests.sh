#!/bin/bash
# 一键运行所有算子的 Verilator 仿真
# 环境: WSL 或 Linux + Verilator 安装

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo "   FPGA Operator Verilator Test Suite"
echo "========================================="

run_operator() {
    local name="$1"
    echo ""
    echo "[$name]"
    echo "-------------------------------------------"
    (cd "$SCRIPT_DIR/$2" && bash run_sim.sh)
}

run_operator "Test 1/3: Channel Shuffle" "Channel_Shuffle_Sim" || exit 1
run_operator "Test 2/3: Concat" "Concat" || exit 1
run_operator "Test 3/3: Element Add" "Element_Add" || exit 1

echo ""
echo "========================================="
echo "   All tests completed successfully!"
echo "========================================="
