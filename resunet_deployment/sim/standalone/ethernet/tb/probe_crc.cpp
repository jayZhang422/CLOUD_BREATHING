/*
 * probe_crc.cpp - crc32_d8 与 zlib.crc32 一致性验证
 *
 * 动机:
 *   PC 端(protocol.py)用 zlib.crc32 计算协议 CRC32 字段, 即标准
 *   CRC-32/ISO-HDLC: 反射输入/输出, poly 0xEDB88320, init 0xFFFFFFFF,
 *   xorout 0xFFFFFFFF。
 *   用户例程 crc32_d8.v 内部做了 bit-reverse(data_t), init=0xFFFFFFFF,
 *   而 udp_tx.v 在发送时对 crc_data 取反(~)。
 *   因此"协议CRC == ~crc_data"这一猜想必须实测确认, 否则握手第一步就失败。
 *
 * 同时验证: 若直接取 crc_data 而不取反, 是否等于某个已知变体。
 *
 * 测试向量由本文件内置, 并由 Python 用 zlib.crc32 独立计算后传入比对。
 */

#include <verilated.h>
#include "Vcrc32_d8.h"
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <vector>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // 测试向量: 若命令行给出, 用十六进制字符串; 否则用内置向量。
    // 内置向量刻意覆盖协议中最典型的几段:
    //   1) 空串        -> zlib.crc32(b"")        = 0x00000000
    //   2) "123456789" -> 标准校验值             = 0xCBF43926
    //   3) 递增0..255  -> 覆盖所有字节值
    const char* hex = (argc > 1) ? argv[1] : nullptr;

    std::vector<std::vector<uint8_t>> vectors;
    if (hex) {
        std::vector<uint8_t> v;
        for (size_t i = 0; hex[i] && hex[i + 1]; i += 2) {
            char b[3] = { hex[i], hex[i + 1], 0 };
            v.push_back((uint8_t)strtoul(b, nullptr, 16));
        }
        vectors.push_back(v);
    } else {
        vectors.push_back({});
        const char* s = "123456789";
        vectors.push_back(std::vector<uint8_t>(s, s + 9));
        std::vector<uint8_t> inc;
        for (int i = 0; i < 256; i++) inc.push_back((uint8_t)i);
        vectors.push_back(inc);
    }

    Vcrc32_d8* dut = new Vcrc32_d8;
    dut->clk = 0; dut->rst_n = 0; dut->data = 0; dut->crc_en = 0; dut->crc_clr = 1;
    for (int i = 0; i < 4; i++) { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }
    dut->rst_n = 1;

    for (size_t vi = 0; vi < vectors.size(); vi++) {
        const std::vector<uint8_t>& v = vectors[vi];

        // 复位 CRC 引擎
        dut->crc_clr = 1; dut->crc_en = 0;
        for (int i = 0; i < 3; i++) { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }
        dut->crc_clr = 0;

        // 逐字节喂入
        for (uint8_t b : v) {
            dut->data = b; dut->crc_en = 1;
            dut->clk = 1; dut->eval();
            dut->clk = 0; dut->eval();
        }
        dut->crc_en = 0;
        dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval();

        uint32_t raw = dut->crc_data;
        uint32_t inv = ~raw;

        std::printf("vec[%u] len=%u  crc_data=0x%08X  ~crc_data=0x%08X\n",
                    (unsigned)vi, (unsigned)v.size(), raw, inv);
    }

    delete dut;
    return 0;
}
