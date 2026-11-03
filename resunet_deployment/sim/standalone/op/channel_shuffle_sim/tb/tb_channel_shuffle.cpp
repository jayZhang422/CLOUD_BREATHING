// Verilator C++ Testbench for channel_shuffle
// 功能: 测试 Channel Shuffle 的通道重排逻辑
// 导出: sim_trace_channel_shuffle.csv (逐周期状态)

#include "Vchannel_shuffle.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <iostream>
#include <fstream>
#include <cstdlib>
#include <ctime>

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
    Vchannel_shuffle* dut = new Vchannel_shuffle;

    // FST 波形配置
    VerilatedFstC* tfp = new VerilatedFstC;
    Verilated::traceEverOn(true);
    dut->trace(tfp, 99);
    tfp->open("results/waveform_channel_shuffle.fst");

    // CSV 日志文件
    std::ofstream csv("results/sim_trace_channel_shuffle.csv");
    csv << "test_id,";
    for (int i = 0; i < 16; i++) {
        csv << "in_ch" << i << ",";
    }
    for (int i = 0; i < 16; i++) {
        csv << "out_ch" << i;
        if (i < 15) csv << ",";
    }
    csv << "\n";

    std::cout << "=== Channel Shuffle Testbench ===" << std::endl;
    int test_id = 0;
    bool all_pass = true;

    // 测试用例 1: 顺序输入 [0, 1, 2, ..., 15]
    std::cout << "\n[Test 1] Sequential input [0..15]" << std::endl;
    for (int i = 0; i < 16; i++) {
        set_channel(dut->data_i, i, static_cast<unsigned char>(i));
    }
    dut->eval();
    tfp->dump(test_id * 10);

    // 记录到 CSV
    csv << test_id << ",";
    for (int i = 0; i < 16; i++) {
        csv << (int)(signed char)get_channel(dut->data_i, i) << ",";
    }
    for (int i = 0; i < 16; i++) {
        csv << (int)(signed char)get_channel(dut->data_o, i);
        if (i < 15) csv << ",";
    }
    csv << "\n";

    // 验证输出: 应为 [0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15]
    int expected[16] = {0, 8, 1, 9, 2, 10, 3, 11, 4, 12, 5, 13, 6, 14, 7, 15};
    bool test1_pass = true;
    for (int i = 0; i < 16; i++) {
        if ((signed char)get_channel(dut->data_o, i) != expected[i]) {
            std::cout << "  FAIL: out_ch[" << i << "] = " << (int)(signed char)get_channel(dut->data_o, i)
                      << ", expected " << expected[i] << std::endl;
            test1_pass = false;
        }
    }
    if (test1_pass) {
        std::cout << "  PASS: Output = [0,8,1,9,2,10,3,11,4,12,5,13,6,14,7,15]" << std::endl;
    } else {
        all_pass = false;
    }
    test_id++;

    // 测试用例 2: 随机输入
    std::cout << "\n[Test 2] Random input" << std::endl;
    srand(20261008);
    for (int i = 0; i < 16; i++) {
        set_channel(dut->data_i, i, static_cast<unsigned char>((rand() % 256) - 128));  // INT8 范围
    }
    dut->eval();
    tfp->dump(test_id * 10);

    csv << test_id << ",";
    for (int i = 0; i < 16; i++) {
        csv << (int)(signed char)get_channel(dut->data_i, i) << ",";
    }
    for (int i = 0; i < 16; i++) {
        csv << (int)(signed char)get_channel(dut->data_o, i);
        if (i < 15) csv << ",";
    }
    csv << "\n";

    // 验证: 手工检查前 8 个放偶数位，后 8 个放奇数位
    bool test2_pass = true;
    for (int i = 0; i < 8; i++) {
        if (get_channel(dut->data_o, 2*i) != get_channel(dut->data_i, i)) {
            std::cout << "  FAIL: out[" << 2*i << "] != in[" << i << "]" << std::endl;
            test2_pass = false;
        }
        if (get_channel(dut->data_o, 2*i+1) != get_channel(dut->data_i, i+8)) {
            std::cout << "  FAIL: out[" << 2*i+1 << "] != in[" << i+8 << "]" << std::endl;
            test2_pass = false;
        }
    }
    if (test2_pass) {
        std::cout << "  PASS: Shuffle mapping correct" << std::endl;
    } else {
        all_pass = false;
    }
    test_id++;

    // 测试用例 3: 边界值
    std::cout << "\n[Test 3] Boundary values [-128, 127]" << std::endl;
    for (int i = 0; i < 8; i++) {
        set_channel(dut->data_i, i, static_cast<unsigned char>(-128));  // 最小值
        set_channel(dut->data_i, i+8, static_cast<unsigned char>(127)); // 最大值
    }
    dut->eval();
    tfp->dump(test_id * 10);

    csv << test_id << ",";
    for (int i = 0; i < 16; i++) {
        csv << (int)(signed char)get_channel(dut->data_i, i) << ",";
    }
    for (int i = 0; i < 16; i++) {
        csv << (int)(signed char)get_channel(dut->data_o, i);
        if (i < 15) csv << ",";
    }
    csv << "\n";

    // 验证: 输出应为 [-128, 127, -128, 127, ...]
    bool test3_pass = true;
    for (int i = 0; i < 16; i += 2) {
        if ((signed char)get_channel(dut->data_o, i) != -128) {
            test3_pass = false;
        }
        if ((signed char)get_channel(dut->data_o, i+1) != 127) {
            test3_pass = false;
        }
    }
    if (test3_pass) {
        std::cout << "  PASS: Boundary values preserved" << std::endl;
    } else {
        std::cout << "  FAIL: Boundary value error" << std::endl;
        all_pass = false;
    }

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
