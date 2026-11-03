#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <memory>
#include "verilated.h"
#include "verilated_vcd_c.h"
#include "Vtb_aq_axi_master.h"

// 用法: ./obj_dir/Vtb_aq_axi_master [--notrace] [--trace-cycles N]
//   默认只把前 TRACE_CYCLES 个周期写入 waveform.vcd (整个仿真的 VCD 会很大)
int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Verilated::traceEverOn(true);

    bool     trace_on     = true;
    uint64_t trace_cycles = 30000;
    for (int i = 1; i < argc; i++) {
        if (!std::strcmp(argv[i], "--notrace")) trace_on = false;
        if (!std::strcmp(argv[i], "--trace-cycles") && i + 1 < argc) trace_cycles = std::strtoull(argv[++i], nullptr, 10);
    }

    auto top = std::make_unique<Vtb_aq_axi_master>();
    auto tfp = std::make_unique<VerilatedVcdC>();

    if (trace_on) {
        top->trace(tfp.get(), 99);
        tfp->open("results/waveform.vcd");
    }

    std::cout << "========================================================\n";
    std::cout << "       Verilator Simulation: aq_axi_master V3.0 (256-bit)\n";
    std::cout << "========================================================\n";

    uint64_t main_time = 0;
    const uint64_t MAX_CYCLES = 3000000;

    auto dump = [&]() { if (trace_on && main_time < 2 * trace_cycles + 20) tfp->dump(main_time); main_time++; };

    // 复位 10 个周期
    top->clk = 0;
    top->rst_n = 0;
    for (int i = 0; i < 20; i++) {
        top->clk = !top->clk;
        top->eval();
        dump();
    }
    top->rst_n = 1;

    uint64_t cycles = 0;
    bool finished = false;

    while (!Verilated::gotFinish() && cycles < MAX_CYCLES) {
        top->clk = 1;
        top->eval();
        dump();

        top->clk = 0;
        top->eval();
        dump();

        cycles++;
        if (top->test_done) {
            finished = true;
            break;
        }
    }

    for (int i = 0; i < 20; i++) {
        top->clk = !top->clk;
        top->eval();
        dump();
    }

    if (trace_on) tfp->close();

    std::cout << "========================================================\n";
    std::cout << "• 总仿真周期: " << cycles << "\n";
    std::cout << "• 错误计数 err_count: " << top->err_count << "\n";
    std::cout << "• 从机检查器 chk_err: " << top->slave_err
              << ", chk_flags: 0x" << std::hex << std::setw(4) << std::setfill('0') << top->slave_flags
              << std::dec << std::setfill(' ') << "\n";
    if (finished && top->test_pass) {
        std::cout << "\033[1;32m[ALL TESTS PASSED]\033[0m\n";
        if (trace_on) std::cout << "• 波形: waveform.vcd (前 " << trace_cycles << " 周期)\n";
        std::cout << "========================================================\n";
        return 0;
    } else {
        std::cout << "\033[1;31m[TEST FAILED]\033[0m 完成: " << (finished ? "是" : "否 (超时)")
                  << ", 停在测试 T" << unsigned(top->cur_test) << "\n";
        if (trace_on) std::cout << "• 波形: waveform.vcd (前 " << trace_cycles << " 周期)\n";
        std::cout << "========================================================\n";
        return 1;
    }
}
