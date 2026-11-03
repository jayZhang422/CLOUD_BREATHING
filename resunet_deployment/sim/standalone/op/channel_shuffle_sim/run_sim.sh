#!/bin/bash
# Channel Shuffle 单独仿真脚本
# 位置: sim/standalone/op/channel_shuffle_sim

echo "========================================="
echo "   Channel Shuffle Verilator Simulation"
echo "========================================="

# 清理旧文件
rm -rf obj_dir
rm -f results/waveform_channel_shuffle.fst
rm -f results/sim_trace_channel_shuffle.csv

# 编译
echo "[Step 1] Verilator compilation..."
mkdir -p results
verilator -Wall --cc rtl/channel_shuffle.sv --exe tb/tb_channel_shuffle.cpp --trace-fst -Mdir obj_dir

if [ $? -ne 0 ]; then
    echo "ERROR: Verilator compilation failed!"
    exit 1
fi

# 编译 C++
echo "[Step 2] C++ compilation..."
make -C obj_dir -f Vchannel_shuffle.mk

if [ $? -ne 0 ]; then
    echo "ERROR: Make failed!"
    exit 1
fi

# 运行仿真
echo "[Step 3] Running simulation..."
./obj_dir/Vchannel_shuffle

if [ $? -ne 0 ]; then
    echo "ERROR: Simulation failed!"
    exit 1
fi

# 显示结果
echo ""
echo "========================================="
echo "   Simulation Results"
echo "========================================="
echo "Wave file: results/waveform_channel_shuffle.fst"
echo "CSV log:   results/sim_trace_channel_shuffle.csv"
echo ""
ls -lh results/waveform_channel_shuffle.fst results/sim_trace_channel_shuffle.csv

echo ""
echo "To view waveform: gtkwave results/waveform_channel_shuffle.fst"
