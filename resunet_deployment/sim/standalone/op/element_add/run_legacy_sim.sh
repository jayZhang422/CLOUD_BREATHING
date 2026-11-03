#!/bin/bash
# Element Add 单独仿真脚本
# 位置: sim/standalone/op/element_add

echo "========================================="
echo "   Element Add Verilator Simulation"
echo "========================================="

# 清理旧文件
rm -rf obj_dir
rm -f waveform_element_add.fst
rm -f sim_trace_element_add.csv

# 编译
echo "[Step 1] Verilator compilation..."
verilator -Wall --cc rtl/element_add.sv --exe tb/tb_element_add.cpp --trace-fst -Mdir obj_dir

if [ $? -ne 0 ]; then
    echo "ERROR: Verilator compilation failed!"
    exit 1
fi

# 编译 C++
echo "[Step 2] C++ compilation..."
make -C obj_dir -f Velement_add.mk

if [ $? -ne 0 ]; then
    echo "ERROR: Make failed!"
    exit 1
fi

# 运行仿真
echo "[Step 3] Running simulation..."
./obj_dir/Velement_add

if [ $? -ne 0 ]; then
    echo "ERROR: Simulation failed!"
    exit 1
fi

# 显示结果
echo ""
echo "========================================="
echo "   Simulation Results"
echo "========================================="
echo "Wave file: waveform_element_add.fst"
echo "CSV log:   sim_trace_element_add.csv"
echo ""
ls -lh waveform_element_add.fst sim_trace_element_add.csv

echo ""
echo "To view waveform: gtkwave waveform_element_add.fst"
