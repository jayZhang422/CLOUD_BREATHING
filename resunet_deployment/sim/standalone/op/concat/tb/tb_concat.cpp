// 仅仿真：离线 Golden、随机缓存延迟/反压、运行中复位和无复位配置切换。
#include "Vtb_concat.h"
#include "verilated.h"
#include "verilated_fst_c.h"
#include <array>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>
#include <stdexcept>
#include <vector>

using Word = std::array<uint32_t, 4>;

static std::vector<Word> load_hex(const std::string& path) {
    std::ifstream file(path);
    if (!file) throw std::runtime_error("Cannot open " + path);
    std::vector<Word> words;
    std::string line;
    while (file >> line) {
        if (!(line.size() == 32)) throw std::runtime_error("Bad hex word: " + path);
        Word word{};
        for (int i = 0; i < 4; ++i)
            word[i] = std::stoul(line.substr(24 - 8 * i, 8), nullptr, 16);
        words.push_back(word);
    }
    return words;
}

template <class Bus> static void put(Bus& bus, const Word& word) {
    for (int i = 0; i < 4; ++i) bus[i] = word[i];
}

template <class Bus> static std::string hex(const Bus& bus) {
    std::ostringstream text;
    text << std::hex << std::setfill('0');
    for (int i = 3; i >= 0; --i) text << std::setw(8) << bus[i];
    return text.str();
}

struct Events {
    bool config, request, output, done;
    unsigned source;
    uint32_t addr;
};

int main(int argc, char** argv) {
    VerilatedContext context;
    context.commandArgs(argc, argv);
    context.traceEverOn(true);
    Vtb_concat dut(&context);
    VerilatedFstC wave;
    dut.trace(&wave, 8);
    std::ofstream csv;
    uint64_t cycle = 0, total_words = 0;
    auto fail = [&](const std::string& message) {
        csv.flush();
        wave.flush();
        throw std::runtime_error("cycle=" + std::to_string(cycle) + " " + message);
    };
    auto tick = [&]() {
        dut.clk_i = 0;
        dut.eval();
        wave.dump(context.time());
        context.timeInc(5);
        Events e{bool(dut.cfg_valid_i && dut.cfg_ready_o),
                 bool(dut.rd_valid_o && dut.rd_ready_i),
                 bool(dut.valid_o && dut.ready_i), bool(dut.done_o),
                 unsigned(dut.rd_source_o), dut.rd_addr_o};
        // 上升沿前的握手值对应 HDL 断言采样值；先落盘再评估上升沿。
        csv << cycle << ',' << unsigned(dut.rst_n_i) << ',' << unsigned(dut.cfg_valid_i)
            << ',' << unsigned(dut.cfg_ready_o) << ',' << unsigned(dut.busy_o)
            << ',' << unsigned(dut.rd_valid_o) << ',' << unsigned(dut.rd_ready_i)
            << ',' << e.source << ',' << e.addr << ',' << unsigned(dut.rsp_valid_i)
            << ',' << unsigned(dut.rsp_ready_o) << ',' << unsigned(dut.valid_o)
            << ',' << unsigned(dut.ready_i) << ',' << unsigned(dut.last_o)
            << ',' << unsigned(dut.done_o) << ',' << hex(dut.data_o)
            << ',' << hex(dut.golden_i) << '\n';
        csv.flush();
        dut.clk_i = 1;
        dut.eval();
        wave.dump(context.time());
        context.timeInc(5);
        ++cycle;
        return e;
    };
    try {
        if (!(argc == 3)) throw std::runtime_error("Usage: Vtb_concat vector_dir trace_dir");
        std::ifstream manifest(std::string(argv[1]) + "/cases.txt");
        if (!manifest) throw std::runtime_error("Missing case manifest");
        std::mt19937 random(20261011);
        std::string name, mode;
        uint32_t count1, count2, base1, base2;
        unsigned cases = 0;
        dut.rst_n_i = 0;
        while (manifest >> name >> count1 >> count2 >> base1 >> base2 >> mode) {
            const auto directory = std::string(argv[1]) + "/" + name;
            const auto a = load_hex(directory + "/stimulus1.hex");
            const auto b = load_hex(directory + "/stimulus2.hex");
            const auto golden = load_hex(directory + "/golden.hex");
            if (!(a.size() == count1 && b.size() == count2 && golden.size() == a.size() + b.size()))
                fail("Vector size mismatch " + name);
            const auto trace_dir = std::string(argv[2]) + "/" + name;
            std::filesystem::create_directories(trace_dir);
            wave.open((trace_dir + "/waveform.fst").c_str());
            csv.open(trace_dir + "/sim_trace.csv");
            csv << "cycle,rst_n,cfg_valid,cfg_ready,busy,rd_valid,rd_ready,source,addr,"
                   "rsp_valid,rsp_ready,valid,ready,last,done,data,golden\n";
            dut.check_i = 0;
            dut.cfg_valid_i = 0;
            dut.rsp_valid_i = 0;
            dut.rd_ready_i = 0;
            dut.ready_i = 0;
            tick();
            dut.rst_n_i = 1;
            dut.check_i = 1;
            auto configure = [&]() {
                dut.cfg_base1_i = base1;
                dut.cfg_base2_i = base2;
                dut.cfg_words1_i = count1;
                dut.cfg_words2_i = count2;
                dut.cfg_valid_i = 1;
                if (!tick().config) fail("Configuration not accepted " + name);
                dut.cfg_valid_i = 0;
            };
            configure();
            size_t issued = 0, received = 0;
            bool pending = false, aborted = false;
            const bool reset_case = mode.rfind("reset_", 0) == 0;
            unsigned request_hold = 3, output_hold = 3;
            int delay = 0;
            Word response{};
            uint64_t request_stalls = 0, output_stalls = 0, done_count = 0;
            const auto start_cycle = cycle;
            while (received < golden.size()) {
                if (cycle - start_cycle > golden.size() * 40 + 200) fail("Watchdog " + name);
                const bool continuous = mode == "continuous";
                dut.rd_ready_i = continuous || random() % 4 > 0;
                dut.ready_i = continuous || random() % 3 > 0;
                dut.rsp_valid_i = pending && delay == 0;
                put(dut.rsp_data_i, response);
                dut.expected_valid_i = received < golden.size();
                dut.expected_source_i = issued >= a.size();
                dut.expected_addr_i = issued < a.size() ? base1 + issued : base2 + issued - a.size();
                dut.expected_last_i = received + 1 == golden.size();
                put(dut.golden_i, golden[received]);
                // 配置输入在 busy 期间持续变化，确认任务使用已锁存的参数。
                dut.cfg_base1_i = random();
                dut.cfg_base2_i = random();
                dut.cfg_words1_i = random();
                dut.cfg_words2_i = random();
                dut.eval();
                if (!continuous && dut.rd_valid_o && issued == 0 && request_hold > 0) {
                    dut.rd_ready_i = 0;
                    --request_hold;
                }
                if (!continuous && dut.valid_o && received == 0 && output_hold > 0) {
                    dut.ready_i = 0;
                    --output_hold;
                }
                bool reset_now = false;
                if (reset_case && !aborted && received >= 5) {
                    if (mode == "reset_request" && dut.rd_valid_o) {
                        dut.rd_ready_i = 0;
                        reset_now = true;
                    } else if (mode == "reset_response" && pending) {
                        dut.rsp_valid_i = 0;
                        reset_now = true;
                    } else if (mode == "reset_output" && dut.valid_o) {
                        dut.ready_i = 0;
                        reset_now = true;
                    }
                }
                dut.eval();
                request_stalls += dut.rd_valid_o && !dut.rd_ready_i;
                output_stalls += dut.valid_o && !dut.ready_i;
                const auto e = tick();
                if (reset_now) {
                    dut.rst_n_i = 0;
                    // 缓存适配器也必须丢弃复位前的未完成返回。
                    dut.rsp_valid_i = 0;
                    pending = false;
                    tick();
                    if (dut.valid_o || dut.rd_valid_o || dut.busy_o || dut.done_o)
                        fail("Reset did not discard in-flight work");
                    tick();
                    dut.rst_n_i = 1;
                    issued = received = 0;
                    aborted = true;
                    configure();
                    continue;
                }
                if (pending && delay > 0) --delay;
                if (e.request) {
                    if (pending) fail("More than one outstanding request");
                    response = e.source ? b.at(e.addr - base2) : a.at(e.addr - base1);
                    pending = true;
                    delay = continuous ? 0 : random() % 5;
                    ++issued;
                }
                if (e.output) {
                    if (!pending) fail("Output without response");
                    pending = false;
                    ++received;
                }
                done_count += e.done;
                if (dut.busy_o && dut.cfg_ready_o) fail("Accepted configuration while busy");
            }
            dut.rsp_valid_i = 0;
            dut.expected_valid_i = 0;
            for (int i = 0; i < 4; ++i) {
                const auto e = tick();
                done_count += e.done;
                if (e.request || e.output) fail("Extra request/output after completion");
            }
            if (!(issued == golden.size() && done_count == 1 && !dut.busy_o))
                fail("Completion/count mismatch " + name);
            if (!(mode == "continuous") && !(request_stalls > 0 && output_stalls > 0))
                fail("Missing backpressure coverage " + name);
            if (reset_case && !aborted) fail("Missing reset coverage " + name);
            total_words += received;
            ++cases;
            std::cout << "[TB PASSED] " << name << " words=" << received
                      << " cycles=" << cycle - start_cycle << " requestStalls=" << request_stalls
                      << " outputStalls=" << output_stalls << " reset=" << aborted << std::endl;
            wave.close();
            csv.close();
        }
        if (!(cases == 18)) fail("Incomplete test manifest");
        // 成功仅在全部用例完成后输出；末拍由 HDL 调用 $finish。
        dut.finish_i = 1;
        dut.clk_i = 0;
        dut.eval();
        dut.clk_i = 1;
        dut.eval();
        dut.final();
        std::cout << "[TB PASSED] 全部数据验证一致 cases=" << cases
                  << " words=" << total_words << " bytes=" << total_words * 16
                  << " cycles=" << cycle << std::endl;
        return 0;
    } catch (const std::exception& error) {
        csv.flush();
        wave.flush();
        std::cerr << "[TB FAILED] " << error.what() << std::endl;
        return 1;
    }
}
