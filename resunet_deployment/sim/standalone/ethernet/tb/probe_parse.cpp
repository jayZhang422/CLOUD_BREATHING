/*
 * probe_parse.cpp - 单帧解析链路诊断
 *
 * 喂一个真实 IMAGE_BEGIN 帧, 打印 udp_rx 与 protocol_parser 的每个关键内部信号,
 * 定位"帧有效"为何未拉高: 是 udp_rx 没收全, 还是 CRC 算错, 还是头字段错位。
 */

#include <verilated.h>
#include "Veth_top.h"
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <vector>
#include <deque>

static uint32_t crc32_iso(const uint8_t* p, size_t n) {
    uint32_t c = 0xFFFFFFFFu;
    for (size_t i = 0; i < n; i++) {
        c ^= p[i];
        for (int k = 0; k < 8; k++) c = (c & 1) ? ((c >> 1) ^ 0xEDB88320u) : (c >> 1);
    }
    return c ^ 0xFFFFFFFFu;
}
static void pu8 (std::vector<uint8_t>& v, uint8_t  x){ v.push_back(x); }
static void pu16(std::vector<uint8_t>& v, uint16_t x){ v.push_back(x>>8); v.push_back(x&0xFF); }
static void pu32(std::vector<uint8_t>& v, uint32_t x){
    v.push_back((x>>24)&0xFF); v.push_back((x>>16)&0xFF);
    v.push_back((x>>8)&0xFF);  v.push_back(x&0xFF);
}
static void pu64(std::vector<uint8_t>& v, uint64_t x){ for (int i=7;i>=0;i--) v.push_back((x>>(8*i))&0xFF); }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    // ---- 构造 IMAGE_BEGIN 帧 (与 sim_main.cpp 同逻辑) ----
    std::vector<uint8_t> body;
    pu32(body, 1);            // Total_Slices
    pu16(body, 512); pu16(body, 512);
    pu8(body, 1); pu8(body, 0x01); pu8(body, 0x01); pu8(body, 0x01);
    pu32(body, 1024); pu32(body, 256); pu32(body, 262144);
    pu64(body, 262144);
    pu64(body, 0x10000000ull);
    pu32(body, 1); pu32(body, 256); pu32(body, 0);
    pu32(body, 1);
    pu32(body, (uint32_t)(int32_t)-1024); pu32(body, 1000);
    pu8(body, 1); pu8(body, 1); pu8(body, 1); pu8(body, 0);
    pu16(body, 33); pu16(body, 16); pu16(body, 96); pu16(body, 0);

    std::vector<uint8_t> f;
    pu16(f, 0x55AA); pu8(f, 0x01); pu8(f, 0x03);
    pu32(f, 0x11223344); pu16(f, 16); pu16(f, (uint16_t)body.size());
    pu32(f, 0);
    f.insert(f.end(), body.begin(), body.end());
    uint32_t crc = crc32_iso(f.data()+2, f.size()-2);
    pu32(f, crc); pu16(f, 0xAA55);

    std::printf("帧: body=%zu 总长=%zu CRC=0x%08X (PC 端同算法)\n",
                body.size(), f.size(), crc);

    // ---- 以太封装 ----
    std::vector<uint8_t> w;
    for (int i=0;i<7;i++) w.push_back(0x55);
    w.push_back(0xD5);
    const uint8_t dm[6]={0x00,0x11,0x22,0x33,0x44,0x55};
    const uint8_t sm[6]={0xAA,0xBB,0xCC,0xDD,0xEE,0xFF};
    for (uint8_t x:dm) w.push_back(x);
    for (uint8_t x:sm) w.push_back(x);
    w.push_back(0x08); w.push_back(0x00);
    uint16_t ipt = 20+8+f.size();
    w.push_back(0x45); w.push_back(0x00);
    w.push_back(ipt>>8); w.push_back(ipt&0xFF);
    w.push_back(0x00); w.push_back(0x01);
    w.push_back(0x40); w.push_back(0x00);
    w.push_back(0x40); w.push_back(0x11);
    w.push_back(0x00); w.push_back(0x00);
    const uint8_t si[4]={192,168,1,102}, di[4]={192,168,1,10};
    for (uint8_t x:si) w.push_back(x);
    for (uint8_t x:di) w.push_back(x);
    uint16_t ul = 8+f.size();
    w.push_back(0x1F); w.push_back(0x90);
    w.push_back(0x1F); w.push_back(0x90);
    w.push_back(ul>>8); w.push_back(ul&0xFF);
    w.push_back(0x00); w.push_back(0x00);
    w.insert(w.end(), f.begin(), f.end());
    for (int i=0;i<4;i++) w.push_back(0);

    // ---- 仿真 ----
    Veth_top* d = new Veth_top;
    d->clk_i=0; d->rst_n_i=0; d->gmii_rx_dv_i=0; d->gmii_rxd_i=0;
    for (int i=0;i<20;i++){ d->clk_i=1; d->eval(); d->clk_i=0; d->eval(); }
    d->rst_n_i=1;
    for (int i=0;i<10;i++){ d->clk_i=1; d->eval(); d->clk_i=0; d->eval(); }

    std::deque<uint8_t> q(w.begin(), w.end());
    int gap = 8;
    int valid_seen = -1, err_seen = -1;
    uint8_t seen_type = 0;
    int udp_done_cycle = -1;
    uint16_t udp_bytes = 0;

    for (int c = 0; c < 60000; c++) {
        if (!q.empty()) { d->gmii_rx_dv_i=1; d->gmii_rxd_i=q.front(); q.pop_front(); }
        else { if (gap>0) gap--; d->gmii_rx_dv_i=0; d->gmii_rxd_i=0; }

        d->clk_i=1; d->eval();
        d->clk_i=0; d->eval();

        if (d->rx_frame_valid_o && valid_seen < 0) { valid_seen = c; seen_type = d->rx_msg_type_o; }
        if (d->rx_frame_error_o && err_seen < 0)   { err_seen = c; }
    }

    std::printf("\n--- 结果 ---\n");
    std::printf("rx_frame_valid_o  首次拉高周期: %d\n", valid_seen);
    std::printf("rx_frame_error_o  首次拉高周期: %d\n", err_seen);
    std::printf("rx_msg_type_o                 : 0x%02X\n", seen_type);
    std::printf("rx_pkt_cnt_o                  : %u\n", d->rx_pkt_cnt_o);
    std::printf("rx_bad_crc_cnt_o              : %u\n", d->rx_bad_crc_cnt_o);

    // 直接读 udp_rx 的字节输出计数: 用一个独立探针不行(未导出),
    // 改为复算: 载荷长度应为 f.size()
    std::printf("期望载荷长度                  : %zu\n", f.size());

    delete d;
    return 0;
}
