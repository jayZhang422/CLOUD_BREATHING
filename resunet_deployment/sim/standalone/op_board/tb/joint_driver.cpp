#include "Vtb_op_candidate.h"
#include "verilated.h"
#include "verilated_fst_c.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

static constexpr uint64_t kMaxCycles = 2000000;
static constexpr size_t kBodyBytes = 1040;

static uint32_t load32(const std::vector<uint8_t>& bytes, size_t offset) {
    uint32_t value = 0;
    for (size_t i = 0; i < 4 && offset + i < bytes.size(); ++i)
        value |= static_cast<uint32_t>(bytes[offset + i]) << (8U * i);
    return value;
}

static uint16_t load16(const std::vector<uint8_t>& bytes, size_t offset) {
    return static_cast<uint16_t>(load32(bytes, offset) & 0xffffU);
}

static void store16(std::vector<uint8_t>& bytes, size_t offset, uint16_t value) {
    if (bytes.size() < offset + 2) bytes.resize(offset + 2, 0);
    bytes[offset] = static_cast<uint8_t>(value);
    bytes[offset + 1] = static_cast<uint8_t>(value >> 8);
}

static void store32(std::vector<uint8_t>& bytes, size_t offset, uint32_t value) {
    if (bytes.size() < offset + 4) bytes.resize(offset + 4, 0);
    for (size_t i = 0; i < 4; ++i) bytes[offset + i] = static_cast<uint8_t>(value >> (8U * i));
}

static void wideZero(uint32_t* wide, size_t words) {
    std::fill(wide, wide + words, 0U);
}

static void widePut(uint32_t* wide, size_t words, const std::vector<uint8_t>& bytes,
                    size_t offset = 0) {
    wideZero(wide, words);
    for (size_t i = 0; i < bytes.size() && offset + i < words * 4; ++i)
        wide[(offset + i) / 4] |= static_cast<uint32_t>(bytes[i]) << (8U * ((offset + i) % 4));
}

static std::vector<uint8_t> wideGet(const uint32_t* wide, size_t bytes) {
    std::vector<uint8_t> result(bytes, 0);
    for (size_t i = 0; i < bytes; ++i) result[i] = static_cast<uint8_t>(wide[i / 4] >> (8U * (i % 4)));
    return result;
}

class SparseMemory {
public:
    uint8_t read(uint32_t address) const {
        const auto it = bytes_.find(address);
        return it == bytes_.end() ? 0 : it->second;
    }

    void write(uint32_t address, uint8_t value) { bytes_[address] = value; }

    void writeBeat(uint32_t address, const uint32_t* data) {
        for (size_t word = 0; word < 8; ++word)
            for (size_t byte = 0; byte < 4; ++byte)
                write(address + static_cast<uint32_t>(word * 4 + byte),
                      static_cast<uint8_t>(data[word] >> (8U * byte)));
    }

    void readBeat(uint32_t address, uint32_t* data) const {
        std::fill(data, data + 8, 0U);
        for (size_t byte = 0; byte < 32; ++byte)
            data[byte / 4] |= static_cast<uint32_t>(read(address + static_cast<uint32_t>(byte)))
                              << (8U * (byte % 4));
    }

private:
    std::unordered_map<uint32_t, uint8_t> bytes_;
};

struct Reply {
    std::vector<uint8_t> body;
    uint16_t length = 0;
};

struct CaseInfo {
    std::string name;
    fs::path path;
    std::vector<uint8_t> descriptor;
    std::vector<uint8_t> golden;
    uint32_t runId = 0;
};

class JointSim {
public:
    explicit JointSim(const fs::path& vectorRoot, const fs::path& artifactRoot)
        : vectorRoot_(vectorRoot), artifactRoot_(artifactRoot), context_(new VerilatedContext),
          dut_(new Vtb_op_candidate(context_.get(), "TOP")), trace_(new VerilatedFstC) {
        context_->traceEverOn(true);
        dut_->trace(trace_.get(), 99);
        const fs::path fst = artifactRoot_ / "joint_waveform.fst";
        trace_->open(fst.string().c_str());
        dut_->clk_i = 0;
        dut_->rst_n_i = 0;
        dut_->req_valid_i = 0;
        dut_->req_msg_i = 0;
        dut_->req_id_i = 0;
        dut_->req_len_i = 0;
        dut_->resp_ready_i = 1;
        dut_->wr_ready_i = 1;
        dut_->rd_ready_i = 1;
        dut_->coeff_req_ready_i = 0;
        dut_->coeff_rsp_valid_i = 0;
        dut_->coeff_rsp_error_i = 0;
        std::fill(dut_->coeff_rsp_data_i.data(), dut_->coeff_rsp_data_i.data() + 8, 0U);
        clearMemoryInputs();
        dut_->eval();
        openTraceLog();
        for (int i = 0; i < 8; ++i) step();
        dut_->rst_n_i = 1;
        for (int i = 0; i < 4; ++i) step();
    }

    ~JointSim() {
        dut_->final();
        trace_->close();
    }

    bool run(const std::vector<CaseInfo>& cases) {
        if (!verifyCoefficientWriteRejected()) return false;
        bool allPassed = true;
        for (const auto& info : cases) {
            const bool passed = runCase(info);
            allPassed = allPassed && passed;
            if (!passed) break;
        }
        return allPassed;
    }

private:
    bool verifyCoefficientWriteRejected() {
        std::vector<uint8_t> body(40, 0);
        store32(body, 0, 0x00100000U);
        store16(body, 4, 32);
        body[8] = 0x5a;
        const Reply reply = command(0x20, 0x00c0ffeeU, body);
        if (reply.body.empty() || reply.body[0] != 3) {
            fail("coefficient write expected read-only rejection status=3 actual=" +
                 (reply.body.empty() ? std::string("missing") : std::to_string(reply.body[0])));
            return false;
        }
        std::cout << "[CASE PASS] read_only_coefficients\n";
        return true;
    }

    void clearMemoryInputs() {
        dut_->wr_done_i = 0;
        dut_->wr_error_i = 0;
        dut_->wr_fifo_re_i = 0;
        dut_->rd_done_i = 0;
        dut_->rd_error_i = 0;
        dut_->rd_fifo_we_i = 0;
        for (int i = 0; i < 8; ++i) dut_->rd_fifo_data_i[i] = 0U;
    }

    bool step() {
        if (++cycles_ > kMaxCycles) {
            fail("watchdog timeout");
            return false;
        }

        // Apply deterministic stalls at the external DDR FIFO boundary.  The
        // memory data/response signals are prepared only after the DUT has
        // exposed the current request, then held through the rising edge.
        dut_->clk_i = 0;
        dut_->wr_ready_i = (cycles_ % 11U) != 0U;
        dut_->rd_ready_i = (cycles_ % 7U) != 0U;
        dut_->coeff_req_ready_i = (cycles_ % 5U) != 0U;
        dut_->coeff_rsp_valid_i = coeffResponseValid_;
        dut_->coeff_rsp_error_i = 0;
        if (coeffResponseValid_) {
            for (int i = 0; i < 8; ++i) dut_->coeff_rsp_data_i.data()[i] = coeffResponse_[i];
        }
        clearMemoryInputs();
        dut_->eval();

        if (!dut_->wr_fifo_empty_o && (cycles_ % 5U) != 0U) {
            dut_->wr_fifo_re_i = 1;
            dut_->wr_done_i = 1;
        }
        if (!dut_->rd_fifo_full_o && (cycles_ % 5U) != 0U) {
            dut_->rd_fifo_we_i = 1;
            dut_->rd_done_i = 1;
            memory_.readBeat(dut_->rd_addr_o, dut_->rd_fifo_data_i);
        }
        dut_->eval();

        const bool requestFire = dut_->req_valid_i && dut_->req_ready_o;
        const bool writeBeat = dut_->wr_fifo_re_i && !dut_->wr_fifo_empty_o;
        const bool readBeat = dut_->rd_fifo_we_i && !dut_->rd_fifo_full_o;
        const bool coeffRequestFire = dut_->coeff_req_valid_o && dut_->coeff_req_ready_i;
        const bool coeffResponseFire = dut_->coeff_rsp_valid_i && dut_->coeff_rsp_ready_o;
        logCycle(requestFire, writeBeat, readBeat);

        dut_->clk_i = 1;
        dut_->eval();
        if (writeBeat) memory_.writeBeat(dut_->wr_addr_o, dut_->wr_fifo_data_o);
        if (coeffResponseFire) coeffResponseValid_ = false;
        if (coeffRequestFire) {
            coeffPendingAddress_ = dut_->coeff_req_addr_o;
            coeffPendingDue_ = cycles_ + 2;
            coeffPending_ = true;
        }
        if (coeffPending_ && cycles_ >= coeffPendingDue_ && !coeffResponseValid_) {
            coefficientMemory_.readBeat(coeffPendingAddress_, coeffResponse_.data());
            coeffResponseValid_ = true;
            coeffPending_ = false;
        }
        trace_->dump(static_cast<vluint64_t>(cycles_ * 2U + 1U));
        dut_->clk_i = 0;
        dut_->eval();
        trace_->dump(static_cast<vluint64_t>(cycles_ * 2U + 2U));
        return requestFire;
    }

    void logCycle(bool requestFire, bool writeBeat, bool readBeat) {
        traceLog_ << cycles_ << ',' << static_cast<unsigned>(dut_->req_valid_i) << ','
                  << static_cast<unsigned>(dut_->req_ready_o) << ',' << requestFire << ','
                  << static_cast<unsigned>(dut_->resp_valid_o) << ','
                  << static_cast<unsigned>(dut_->wr_start_o || dut_->rd_start_o) << ','
                  << static_cast<unsigned>(dut_->wr_start_o) << ','
                  << (dut_->wr_start_o ? dut_->wr_addr_o : dut_->rd_addr_o) << ','
                  << static_cast<unsigned>(dut_->wr_ready_i) << ','
                  << static_cast<unsigned>(dut_->rd_ready_i) << ',' << writeBeat << ','
                  << readBeat << '\n';
    }

    void fail(const std::string& message) {
        if (!failed_) {
            failed_ = true;
            std::cerr << "[TB FAIL] cycle=" << cycles_ << ' ' << message << '\n';
        }
    }

    Reply command(uint8_t message, uint32_t id, const std::vector<uint8_t>& body) {
        if (body.size() > kBodyBytes) {
            fail("command body exceeds RPC mailbox");
            return {};
        }
        widePut(dut_->req_body_i, 260, body);
        dut_->req_msg_i = message;
        dut_->req_id_i = id;
        dut_->req_len_i = static_cast<uint16_t>(body.size());
        dut_->req_valid_i = 1;

        bool accepted = false;
        for (uint64_t wait = 0; wait < 100000 && !accepted; ++wait) accepted = step();
        dut_->req_valid_i = 0;
        wideZero(dut_->req_body_i, 260);
        if (!accepted) {
            fail("RPC request was not accepted");
            return {};
        }

        for (uint64_t wait = 0; wait < 100000; ++wait) {
            if (dut_->resp_valid_o) {
                Reply reply;
                reply.length = dut_->resp_len_o;
                reply.body = wideGet(dut_->resp_body_o, std::min<size_t>(reply.length, kBodyBytes));
                step(); // consume the response mailbox and reach WAIT_SEND/IDLE
                return reply;
            }
            step();
        }
        fail("RPC response timeout");
        return {};
    }

    bool upload(uint32_t runId, const fs::path& file, uint32_t address) {
        std::ifstream input(file, std::ios::binary);
        std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
        if (!input.good() && !input.eof()) {
            fail("unable to read upload " + file.string());
            return false;
        }
        if (bytes.empty() || (bytes.size() % 32U) != 0U) {
            fail("upload is not a non-empty 32-byte multiple: " + file.string());
            return false;
        }
        for (size_t offset = 0; offset < bytes.size(); ) {
            const size_t count = std::min<size_t>(1024, bytes.size() - offset);
            std::vector<uint8_t> body(8 + count, 0);
            store32(body, 0, address + static_cast<uint32_t>(offset));
            store16(body, 4, static_cast<uint16_t>(count));
            store16(body, 6, 0);
            std::copy(bytes.begin() + static_cast<std::ptrdiff_t>(offset),
                      bytes.begin() + static_cast<std::ptrdiff_t>(offset + count), body.begin() + 8);
            const Reply reply = command(0x20, runId, body);
            if (reply.body.empty() || reply.body[0] != 0) {
                fail("WRITE rejected for " + file.string());
                return false;
            }
            offset += count;
        }
        return true;
    }

    bool loadCoefficients(const fs::path& casePath) {
        std::ifstream manifest(casePath / "coeffs.tsv");
        std::string addressText, filename;
        while (manifest >> addressText >> filename) {
            const uint32_t address = static_cast<uint32_t>(std::stoul(addressText, nullptr, 0));
            std::ifstream input(casePath / filename, std::ios::binary);
            if (!input) {
                fail("missing read-only coefficient image " + (casePath / filename).string());
                return false;
            }
            std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)), {});
            for (size_t i = 0; i < bytes.size(); ++i)
                coefficientMemory_.write(address + static_cast<uint32_t>(i), bytes[i]);
        }
        return true;
    }

    Reply status(uint32_t runId) { return command(0x22, runId, {}); }

    bool runDescriptor(const CaseInfo& info) {
        const Reply reply = command(0x21, info.runId, info.descriptor);
        if (reply.body.empty() || reply.body[0] != 0) {
            fail(info.name + " RUN rejected, status=" + (reply.body.empty() ? "missing" : std::to_string(reply.body[0])));
            return false;
        }
        for (uint64_t poll = 0; poll < 100000; ++poll) {
            const Reply state = status(info.runId);
            if (state.body.size() < 16 || state.body[0] != 0) {
                fail(info.name + " STATUS failed");
                return false;
            }
            const uint8_t runState = state.body[1];
            if (runState == 2) return true;
            if (runState == 3 || runState == 4) {
                fail(info.name + " entered failed/aborting state=" + std::to_string(runState));
                return false;
            }
        }
        fail(info.name + " did not reach READY");
        return false;
    }

    bool readResult(const CaseInfo& info) {
        const Reply state = status(info.runId);
        if (state.body.size() < 16) {
            fail(info.name + " missing READY status");
            return false;
        }
        const uint32_t resultBase = load32(info.descriptor, 24);
        const uint32_t resultBytes = load32(state.body, 8);
        if (resultBytes != info.golden.size()) {
            fail(info.name + " result length expected=" + std::to_string(info.golden.size()) +
                 " actual=" + std::to_string(resultBytes));
            return false;
        }
        std::vector<uint8_t> actual;
        for (size_t offset = 0; offset < resultBytes; ) {
            const size_t remaining = resultBytes - offset;
            const size_t count = std::min<size_t>(1024, (remaining + 31U) & ~size_t(31U));
            std::vector<uint8_t> body(8, 0);
            store32(body, 0, resultBase + static_cast<uint32_t>(offset));
            store16(body, 4, static_cast<uint16_t>(count));
            store16(body, 6, 0);
            const Reply reply = command(0x23, info.runId, body);
            if (reply.body.size() < 16 + count || reply.body[0] != 0) {
                fail(info.name + " READ failed");
                return false;
            }
            actual.insert(actual.end(), reply.body.begin() + 16,
                          reply.body.begin() + 16 + std::min(count, remaining));
            offset += std::min(count, remaining);
        }
        if (actual != info.golden) {
            if (actual.size() != info.golden.size()) {
                fail(info.name + " returned byte count " + std::to_string(actual.size()));
                return false;
            }
            const size_t mismatch = std::mismatch(actual.begin(), actual.end(), info.golden.begin()).first - actual.begin();
            std::ostringstream message;
            message << info.name << " golden mismatch at byte " << mismatch << " expected=0x"
                    << std::hex << static_cast<unsigned>(info.golden[mismatch]) << " actual=0x"
                    << static_cast<unsigned>(actual[mismatch]);
            fail(message.str());
            return false;
        }
        return true;
    }

    bool release(const CaseInfo& info) {
        const Reply reply = command(0x24, info.runId, {});
        if (reply.body.empty() || reply.body[0] != 0) {
            fail(info.name + " RELEASE failed");
            return false;
        }
        return true;
    }

    bool runCase(const CaseInfo& info) {
        std::cout << "[CASE] " << info.name << '\n';
        if (!loadCoefficients(info.path)) return false;
        std::ifstream uploads(info.path / "uploads.tsv");
        std::string addressText, filename;
        while (uploads >> addressText >> filename) {
            const uint32_t address = static_cast<uint32_t>(std::stoul(addressText, nullptr, 0));
            if (!upload(info.runId, info.path / filename, address)) return false;
        }
        if (!runDescriptor(info)) return false;
        if (!readResult(info)) return false;
        if (!release(info)) return false;
        std::cout << "[CASE PASS] " << info.name << '\n';
        return true;
    }

    void openTraceLog() { traceLog_.open((artifactRoot_ / "sim_trace.csv").string());
        traceLog_ << "cycle,req_valid,req_ready,req_fire,resp_valid,port_start,write_start,port_addr,wr_ready,rd_ready,wr_beat,rd_beat\n"; }

    fs::path vectorRoot_;
    fs::path artifactRoot_;
    std::unique_ptr<VerilatedContext> context_;
    std::unique_ptr<Vtb_op_candidate> dut_;
    std::unique_ptr<VerilatedFstC> trace_;
    SparseMemory memory_;
    SparseMemory coefficientMemory_;
    std::array<uint32_t, 8> coeffResponse_{};
    std::ofstream traceLog_;
    uint32_t coeffPendingAddress_ = 0;
    uint64_t coeffPendingDue_ = 0;
    uint64_t cycles_ = 0;
    bool failed_ = false;
    bool coeffPending_ = false;
    bool coeffResponseValid_ = false;
};

static std::vector<CaseInfo> loadCases(const fs::path& root) {
    std::vector<CaseInfo> cases;
    std::ifstream manifest(root / "cases.txt");
    std::string name;
    while (std::getline(manifest, name)) {
        if (!name.empty() && name.back() == '\r') name.pop_back();
        if (name.empty()) continue;
        CaseInfo info;
        info.name = name;
        info.path = root / name;
        std::ifstream descriptor(info.path / "descriptor.bin", std::ios::binary);
        info.descriptor.assign(std::istreambuf_iterator<char>(descriptor), {});
        std::ifstream golden(info.path / "golden.bin", std::ios::binary);
        info.golden.assign(std::istreambuf_iterator<char>(golden), {});
        info.runId = load32(info.descriptor, 48);
        cases.push_back(std::move(info));
    }
    return cases;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    const fs::path root = argc > 1 ? fs::path(argv[1]) : fs::path("vectors");
    const fs::path artifacts = argc > 2 ? fs::path(argv[2]) : fs::path("artifacts");
    fs::create_directories(artifacts);
    const auto cases = loadCases(root);
    if (cases.empty()) {
        std::cerr << "[TB FAIL] no vector cases under " << root << '\n';
        return 2;
    }
    JointSim sim(root, artifacts);
    // Keep the trace in the same directory as the self-checking CSV.
    // The constructor opens the FST before the first edge; the CSV is opened
    // here by the same object lifetime through a small deterministic header.
    const bool passed = sim.run(cases);
    if (passed) {
        std::cout << "[TB PASSED] all joint cases matched golden data\n";
        return 0;
    }
    return 1;
}
