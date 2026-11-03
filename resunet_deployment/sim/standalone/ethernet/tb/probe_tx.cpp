/*
 * probe_tx.cpp - 打印 FPGA 回传的原始 GMII 帧字节, 定位发送链路问题
 */

#include <verilated.h>
#include "Veth_top.h"
#include <cstdio>
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

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    std::vector<uint8_t> body(76, 0);
    body[3]=1;
    body[4]=0x02; body[5]=0x00;
    body[6]=0x02; body[7]=0x00;
    body[8]=1; body[9]=1; body[10]=1; body[11]=1;
    body[14]=0x04; body[18]=0x01; body[21]=0x04;

    std::vector<uint8_t> f;
    pu16(f,0x55AA); pu8(f,0x01); pu8(f,0x03);
    pu32(f,0x11223344); pu16(f,16); pu16(f,76);
    pu32(f,0);
    f.insert(f.end(), body.begin(), body.end());
    pu32(f, crc32_iso(f.data()+2, f.size()-2));
    pu16(f,0xAA55);

    std::vector<uint8_t> w;
    for (int i=0;i<7;i++) w.push_back(0x55);
    w.push_back(0xD5);
    const uint8_t dm[6]={0x00,0x11,0x22,0x33,0x44,0x55};
    const uint8_t sm[6]={0xAA,0xBB,0xCC,0xDD,0xEE,0xFF};
    for (uint8_t x:dm) w.push_back(x);
    for (uint8_t x:sm) w.push_back(x);
    w.push_back(0x08); w.push_back(0x00);
    uint16_t ipt=20+8+f.size();
    w.push_back(0x45); w.push_back(0x00);
    w.push_back(ipt>>8); w.push_back(ipt&0xFF);
    w.push_back(0x00); w.push_back(0x01);
    w.push_back(0x40); w.push_back(0x00);
    w.push_back(0x40); w.push_back(0x11);
    w.push_back(0x00); w.push_back(0x00);
    const uint8_t si[4]={192,168,1,102}, di[4]={192,168,1,10};
    for (uint8_t x:si) w.push_back(x);
    for (uint8_t x:di) w.push_back(x);
    uint16_t ul=8+f.size();
    w.push_back(0x1F); w.push_back(0x90);
    w.push_back(0x1F); w.push_back(0x90);
    w.push_back(ul>>8); w.push_back(ul&0xFF);
    w.push_back(0x00); w.push_back(0x00);
    w.insert(w.end(), f.begin(), f.end());
    for (int i=0;i<4;i++) w.push_back(0);

    Veth_top* d = new Veth_top;
    d->clk_i=0; d->rst_n_i=0; d->gmii_rx_dv_i=0; d->gmii_rxd_i=0;
    for (int i=0;i<20;i++){ d->clk_i=1; d->eval(); d->clk_i=0; d->eval(); }
    d->rst_n_i=1;
    for (int i=0;i<10;i++){ d->clk_i=1; d->eval(); d->clk_i=0; d->eval(); }

    std::deque<uint8_t> q(w.begin(), w.end());
    int gap=8;
    std::vector<uint8_t> cap;      // 抓到的 GMII TX 字节
    bool active=false;

    for (int c=0; c<60000; c++) {
        if (!q.empty()) { d->gmii_rx_dv_i=1; d->gmii_rxd_i=q.front(); q.pop_front(); }
        else { if (gap>0) gap--; d->gmii_rx_dv_i=0; d->gmii_rxd_i=0; }

        d->clk_i=1; d->eval();

        if (d->gmii_tx_en_o) { active=true; cap.push_back((uint8_t)d->gmii_txd_o); }
        else if (active) { active=false; }

        d->clk_i=0; d->eval();
    }

    std::printf("抓到的 GMII TX 总字节数: %zu\n", cap.size());
    if (cap.empty()) { std::printf("没有发送!\n"); delete d; return 0; }

    std::printf("\n=== 原始 GMII TX (前 80 字节) ===\n");
    for (size_t i = 0; i < cap.size() && i < 80; i++) {
        std::printf("%02X ", cap[i]);
        if (i % 16 == 15) std::printf("  [%zu]\n", i);
    }
    std::printf("\n\n=== 按结构解析 ===\n");
    std::printf("前导码(8): ");
    for (size_t i=0;i<8 && i<cap.size();i++) std::printf("%02X ", cap[i]);
    std::printf("\n");
    if (cap.size() > 22) {
        std::printf("以太头(14): ");
        for (size_t i=8;i<22;i++) std::printf("%02X ", cap[i]);
        std::printf("\n");
        std::printf("IP头(20):   ");
        for (size_t i=22;i<42 && i<cap.size();i++) std::printf("%02X ", cap[i]);
        std::printf("\n");
        std::printf("UDP头(8):   ");
        for (size_t i=42;i<50 && i<cap.size();i++) std::printf("%02X ", cap[i]);
        std::printf("\n");
        std::printf("协议帧载荷 (从偏移 50 开始, 期望 55 AA 01 81 ...):\n  ");
        for (size_t i=50;i<cap.size() && i<50+70;i++) std::printf("%02X ", cap[i]);
        std::printf("\n");
    }

    delete d;
    return 0;
}
