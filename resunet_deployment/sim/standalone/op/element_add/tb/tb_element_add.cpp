// Verilator C++ Testbench for element_add
// 功能: 测试 Element-wise Add 的饱和加法逻辑
// 导出: sim_trace_element_add.csv (逐周期状态)

#include "Velement_add.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <iostream>
#include <fstream>

static void set_channel(vluint32_t* bus, int channel, unsigned char value) {
    const int word = channel / 4;
    const int shift = (channel % 4) * 8;
    bus[word] = (bus[word] & ~(0xffu << shift)) | (static_cast<vluint32_t>(value) << shift);
}

static unsigned char get_channel(const vluint32_t* bus, int channel) {
    return static_cast<unsigned char>((bus[channel / 4] >> ((channel % 4) * 8)) & 0xffu);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Velement_add* dut = new Velement_add;

    // FST 波形配置
    VerilatedFstC* tfp = new VerilatedFstC;
    Verilated::traceEverOn(true);
    dut->trace(tfp, 99);
    tfp->open("waveform_element_add.fst");

    // CSV 日志文件
    std::ofstream csv("sim_trace_element_add.csv");
    csv << "test_id,a0,b0,out0,a1,b1,out1,saturated\n";

    std::cout << "=== Element-wise Add Testbench ===" << std::endl;
    int test_id = 0;
    bool all_pass = true;

    // 测试用例 1: 正常加法（无溢出）
    std::cout << "\n[Test 1] Normal addition (no overflow)" << std::endl;
    for (int i = 0; i < 16; i++) {
        set_channel(dut->data1_i, i, 10);
        set_channel(dut->data2_i, i, 20);
    }
    dut->eval();
    tfp->dump(test_id * 10);

    bool test1_pass = true;
    for (int i = 0; i < 16; i++) {
        signed char result = (signed char)get_channel(dut->data_o, i);
        if (result != 30) {
            std::cout << "  FAIL: ch[" << i << "] = " << (int)result << ", expected 30" << std::endl;
            test1_pass = false;
        }
    }
    if (test1_pass) {
        std::cout << "  PASS: 10 + 20 = 30 (all channels)" << std::endl;
    } else {
        all_pass = false;
    }

    csv << test_id << ",10,20," << (int)(signed char)get_channel(dut->data_o, 0)
        << ",10,20," << (int)(signed char)get_channel(dut->data_o, 1) << ",0\n";
    test_id++;

    // 测试用例 2: 正溢出饱和
    std::cout << "\n[Test 2] Positive overflow saturation" << std::endl;
    for (int i = 0; i < 16; i++) {
        set_channel(dut->data1_i, i, 100);
        set_channel(dut->data2_i, i, 50);
    }
    dut->eval();
    tfp->dump(test_id * 10);

    bool test2_pass = true;
    for (int i = 0; i < 16; i++) {
        signed char result = (signed char)get_channel(dut->data_o, i);
        if (result != 127) {  // 100+50=150 → 饱和到 127
            std::cout << "  FAIL: ch[" << i << "] = " << (int)result << ", expected 127" << std::endl;
            test2_pass = false;
        }
    }
    if (test2_pass) {
        std::cout << "  PASS: 100 + 50 = 127 (saturated)" << std::endl;
    } else {
        all_pass = false;
    }

    csv << test_id << ",100,50," << (int)(signed char)get_channel(dut->data_o, 0)
        << ",100,50," << (int)(signed char)get_channel(dut->data_o, 1) << ",1\n";
    test_id++;

    // 测试用例 3: 负溢出饱和
    std::cout << "\n[Test 3] Negative overflow saturation" << std::endl;
    for (int i = 0; i < 16; i++) {
        set_channel(dut->data1_i, i, 0x8C);  // -116 in INT8
        set_channel(dut->data2_i, i, 0xF0);  // -16 in INT8
    }
    dut->eval();
    tfp->dump(test_id * 10);

    bool test3_pass = true;
    for (int i = 0; i < 16; i++) {
        signed char result = (signed char)get_channel(dut->data_o, i);
        if (result != -128) {  // -116-16=-132 → 饱和到 -128
            std::cout << "  FAIL: ch[" << i << "] = " << (int)result << ", expected -128" << std::endl;
            test3_pass = false;
        }
    }
    if (test3_pass) {
        std::cout << "  PASS: -116 + (-16) = -128 (saturated)" << std::endl;
    } else {
        all_pass = false;
    }

    csv << test_id << ",-116,-16," << (int)(signed char)get_channel(dut->data_o, 0)
        << ",-116,-16," << (int)(signed char)get_channel(dut->data_o, 1) << ",1\n";
    test_id++;

    // 测试用例 4: 零加法
    std::cout << "\n[Test 4] Zero addition" << std::endl;
    for (int i = 0; i < 16; i++) {
        set_channel(dut->data1_i, i, 0);
        set_channel(dut->data2_i, i, 0);
    }
    dut->eval();
    tfp->dump(test_id * 10);

    bool test4_pass = true;
    for (int i = 0; i < 16; i++) {
        if (get_channel(dut->data_o, i) != 0) {
            test4_pass = false;
        }
    }
    if (test4_pass) {
        std::cout << "  PASS: 0 + 0 = 0" << std::endl;
    } else {
        std::cout << "  FAIL: Zero addition error" << std::endl;
        all_pass = false;
    }

    csv << test_id << ",0,0,0,0,0,0,0\n";
    test_id++;

    // 测试用例 5: 临界值
    std::cout << "\n[Test 5] Boundary values" << std::endl;
    set_channel(dut->data1_i, 0, 127);
    set_channel(dut->data2_i, 0, 0);
    set_channel(dut->data1_i, 1, static_cast<unsigned char>(-128));
    set_channel(dut->data2_i, 1, 0);
    set_channel(dut->data1_i, 2, 127);
    set_channel(dut->data2_i, 2, 1);  // 应饱和到 127
    set_channel(dut->data1_i, 3, static_cast<unsigned char>(-128));
    set_channel(dut->data2_i, 3, static_cast<unsigned char>(-1)); // 应饱和到 -128
    dut->eval();
    tfp->dump(test_id * 10);

    bool test5_pass = true;
    if ((signed char)get_channel(dut->data_o, 0) != 127) test5_pass = false;
    if ((signed char)get_channel(dut->data_o, 1) != -128) test5_pass = false;
    if ((signed char)get_channel(dut->data_o, 2) != 127) test5_pass = false;
    if ((signed char)get_channel(dut->data_o, 3) != -128) test5_pass = false;

    if (test5_pass) {
        std::cout << "  PASS: Boundary values handled correctly" << std::endl;
    } else {
        std::cout << "  FAIL: Boundary value error" << std::endl;
        all_pass = false;
    }

    csv << test_id << ",127,0," << (int)(signed char)get_channel(dut->data_o, 0)
        << ",-128,0," << (int)(signed char)get_channel(dut->data_o, 1) << ",0\n";

    // 清理
    tfp->close();
    csv.close();
    delete dut;
    delete tfp;

    std::cout << "\n==================================" << std::endl;
    if (all_pass) {
        std::cout << "All tests PASSED!" << std::endl;
        return 0;
    } else {
        std::cout << "Some tests FAILED!" << std::endl;
        return 1;
    }
}
