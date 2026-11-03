/*
 * probe_rx.cpp - udp_rx 字节流对齐探针
 *
 * 目的:
 *   用户例程中的 udp_rx.v 在 st_rx_data 状态用 (gmii_rx_dv) 作为字节使能,
 *   而 data_byte_num 在 st_udp_head 的最后一拍才计算出来。
 *   需要实测:
 *     1. rec_en 拉高的次数(= 捕获的字节数) 是否等于 UDP 载荷长度;
 *     2. rec_en 与 rec_data 的相对延迟;
 *     3. 捕获到的第一个字节是载荷的哪一字节;
 *     4. rec_pkt_done 相对最后一个字节的位置。
 *
 * 结论用于确定 protocol_parser 的字节对齐方式(不靠猜)。
 */

#include <verilated.h>
#include "Vudp_rx.h"
#include <cstdio>
#include <cstdint>
#include <vector>

static const uint16_t UDP_PAYLOAD_LEN = 1054;   // IMAGE_DATA 协议帧长度

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // ---- 构造与真实网络一致的以太网帧字节流 ----
    std::vector<uint8_t> wire;
    for (int i = 0; i < 7; i++) wire.push_back(0x55);   // 前导码
    wire.push_back(0xD5);                               // SFD
    const uint8_t mac_dst[6] = {0x00,0x11,0x22,0x33,0x44,0x55};  // 本板 MAC
    const uint8_t mac_src[6] = {0xAA,0xBB,0xCC,0xDD,0xEE,0xFF};  // PC MAC
    for (uint8_t b : mac_dst) wire.push_back(b);
    for (uint8_t b : mac_src) wire.push_back(b);
    wire.push_back(0x08); wire.push_back(0x00);         // EtherType = IPv4

    uint16_t ip_total = 20 + 8 + UDP_PAYLOAD_LEN;
    wire.push_back(0x45); wire.push_back(0x00);
    wire.push_back(ip_total >> 8); wire.push_back(ip_total & 0xFF);
    wire.push_back(0x00); wire.push_back(0x01);
    wire.push_back(0x40); wire.push_back(0x00);
    wire.push_back(0x40); wire.push_back(0x11);         // TTL=64, Proto=UDP
    wire.push_back(0x00); wire.push_back(0x00);         // IP 校验和(udp_rx 不校验)
    wire.push_back(192); wire.push_back(168); wire.push_back(1); wire.push_back(102); // 源 IP
    wire.push_back(192); wire.push_back(168); wire.push_back(1); wire.push_back(10);  // 目的 IP = 本板

    uint16_t udp_len = 8 + UDP_PAYLOAD_LEN;
    wire.push_back(0x1F); wire.push_back(0x90);         // 源端口 8080
    wire.push_back(0x1F); wire.push_back(0x90);         // 目的端口 8080
    wire.push_back(udp_len >> 8); wire.push_back(udp_len & 0xFF);
    wire.push_back(0x00); wire.push_back(0x00);         // UDP 校验和

    // 载荷: 递增图案, 便于校验字节对齐
    for (uint16_t i = 0; i < UDP_PAYLOAD_LEN; i++)
        wire.push_back((uint8_t)(i & 0xFF));

    // ---- 仿真 ----
    Vudp_rx* dut = new Vudp_rx;
    dut->clk = 0; dut->rst_n = 0; dut->gmii_rx_dv = 0; dut->gmii_rxd = 0;
    for (int i = 0; i < 8; i++) { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }
    dut->rst_n = 1;
    for (int i = 0; i < 4; i++) { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }

    std::vector<uint8_t> captured;
    bool     done_seen   = false;
    uint16_t done_bytes  = 0;
    int      done_cycle  = -1;
    int      last_en_cycle = -1;

    for (size_t i = 0; i < wire.size(); i++) {
        dut->gmii_rx_dv = 1;
        dut->gmii_rxd   = wire[i];
        // 上升沿: 采样
        dut->clk = 1; dut->eval();
        // 下降沿: 观测本拍输出
        dut->clk = 0; dut->eval();
        if (dut->rec_en) {
            captured.push_back((uint8_t)dut->rec_data);
            last_en_cycle = (int)i;
        }
        if (dut->rec_pkt_done && !done_seen) {
            done_seen  = true;
            done_bytes = dut->rec_byte_num;
            done_cycle = (int)i;
        }
    }
    // 帧结束: 拉低 rx_dv, 让状态机走完 st_rx_end
    dut->gmii_rx_dv = 0; dut->gmii_rxd = 0;
    for (int i = 0; i < 16; i++) {
        dut->clk = 1; dut->eval();
        dut->clk = 0; dut->eval();
        if (dut->rec_en) {
            captured.push_back((uint8_t)dut->rec_data);
            last_en_cycle = (int)wire.size() + i;
        }
        if (dut->rec_pkt_done && !done_seen) {
            done_seen  = true;
            done_bytes = dut->rec_byte_num;
            done_cycle = (int)wire.size() + i;
        }
    }

    // ---- 报告 ----
    std::printf("================ udp_rx 对齐探针 ================\n");
    std::printf("wire 总字节数        : %u (前导8 + 以太14 + IP20 + UDP8 + 载荷%u)\n",
                (unsigned)wire.size(), UDP_PAYLOAD_LEN);
    std::printf("rec_byte_num 报告值  : %u\n", done_bytes);
    std::printf("rec_pkt_done 位置    : wire[%d]\n", done_cycle);
    std::printf("rec_en 捕获字节数    : %u\n", (unsigned)captured.size());
    std::printf("最后一个 rec_en 位置 : wire[%d]\n", last_en_cycle);
    std::printf("\n捕获流 vs 载荷流(x=不匹配):\n");
    std::printf("  idx  captured  expected(payload[i])  match\n");
    for (int i = 0; i < 8 && i < (int)captured.size(); i++)
        std::printf("  %3d  0x%02X      0x%02X                %s\n",
                    i, captured[i], (uint8_t)(i & 0xFF),
                    captured[i] == (uint8_t)(i & 0xFF) ? "yes" : "NO");

    std::printf("\n逐字节比对结果: ");
    int first_bad = -1, n_bad = 0;
    for (size_t i = 0; i < captured.size(); i++) {
        if (captured[i] != (uint8_t)(i & 0xFF)) {
            if (first_bad < 0) first_bad = (int)i;
            n_bad++;
        }
    }
    if (first_bad < 0)
        std::printf("全部匹配（捕获流 == 载荷, 从载荷第0字节开始）\n");
    else
        std::printf("首个不匹配 idx=%d, 共 %d 个不匹配\n", first_bad, n_bad);
    std::printf("================================================\n");

    delete dut;
    return 0;
}
