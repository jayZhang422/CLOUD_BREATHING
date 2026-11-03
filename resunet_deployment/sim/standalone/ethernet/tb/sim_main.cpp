/*
 * sim_main.cpp - CT-FPGA 以太网收发链路 Verilator 仿真主程序
 *
 * 两种运行模式:
 *   1) 内建自测 (--selftest):
 *      本地生成完全符合协议 V1 的帧流(带真实 CRC32), 覆盖
 *        IMAGE_BEGIN -> 256×IMAGE_DATA -> BATCH_END(校验缺包位图)
 *        -> IMAGE_END -> INFER_TRIGGER
 *      并故意丢掉部分包, 验证 FPGA 回传的缺包位图是否正确。
 *      用于把 "RTL 的 bug" 与 "socket/Python 的 bug" 分开定位。
 *
 *   2) UDP 桥接 (默认):
 *      绑定 192.168.1.10:8080, 对端 192.168.1.102:8080。
 *      收到任何 UDP 数据报 -> 加以太/IP/UDP 头 -> 灌入 GMII RX;
 *      抓取 GMII TX -> 剥离各层头 -> 回送 UDP 数据报。
 *      这样 PC 上那套 Python 发送端 (prj/main.py send) 可原样运行,
 *      由真实 Python 端做 CRC/字段的最严格校验。
 *
 * CRC: 本文件内置 CRC-32/ISO-HDLC (反射, poly 0xEDB88320, init/xorout 0xFFFFFFFF),
 *      与 Python zlib.crc32 逐位一致; RTL 侧用 crc32_iso_hdlc.sv。
 */

#include <verilated.h>
#include "Veth_top.h"
#ifdef VM_TRACE
#include <verilated_vcd_c.h>
#endif

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <string>
#include <vector>
#include <deque>
#include <map>
#include <set>
#include <iostream>
#include <iomanip>

//========================================================================================
// 协议常量
//========================================================================================
static const uint16_t MAGIC      = 0x55AA;
static const uint16_t TAIL       = 0xAA55;
static const uint8_t  VERSION    = 0x01;
static const uint16_t HEADER_LEN = 16;

static const uint8_t MSG_IMAGE_DATA    = 0x01;
static const uint8_t MSG_INFER_TRIGGER = 0x02;
static const uint8_t MSG_IMAGE_BEGIN   = 0x03;
static const uint8_t MSG_IMAGE_END     = 0x04;
static const uint8_t MSG_BATCH_END     = 0x05;
static const uint8_t MSG_ACK           = 0x81;
static const uint8_t MSG_INFER_DONE    = 0x82;
static const uint8_t MSG_BATCH_STATUS  = 0x83;
static const uint8_t MSG_IMAGE_READY   = 0x84;

static const uint16_t PACKETS_PER_SLICE  = 256;
static const uint16_t PACKET_PIXEL_BYTES = 1024;
static const uint32_t SLICE_BYTES        = 512u * 512u;   // 262144

//========================================================================================
// CRC-32/ISO-HDLC (与 zlib.crc32 一致)
//========================================================================================
static uint32_t crc32_iso_hdlc(const uint8_t* p, size_t n, uint32_t crc = 0xFFFFFFFFu)
{
    for (size_t i = 0; i < n; i++) {
        crc ^= p[i];
        for (int k = 0; k < 8; k++)
            crc = (crc & 1u) ? ((crc >> 1) ^ 0xEDB88320u) : (crc >> 1);
    }
    return crc;
}
static uint32_t crc32_final(uint32_t crc) { return crc ^ 0xFFFFFFFFu; }

//========================================================================================
// 大端写入
//========================================================================================
static void put_u8 (std::vector<uint8_t>& v, uint8_t  x) { v.push_back(x); }
static void put_u16(std::vector<uint8_t>& v, uint16_t x) { v.push_back(x >> 8); v.push_back(x & 0xFF); }
static void put_u32(std::vector<uint8_t>& v, uint32_t x) {
    v.push_back((x >> 24) & 0xFF); v.push_back((x >> 16) & 0xFF);
    v.push_back((x >> 8) & 0xFF);  v.push_back(x & 0xFF);
}
static void put_u64(std::vector<uint8_t>& v, uint64_t x) {
    for (int i = 7; i >= 0; i--) v.push_back((x >> (8 * i)) & 0xFF);
}

static uint16_t get_u16(const std::vector<uint8_t>& v, size_t o) {
    return (uint16_t)((v[o] << 8) | v[o + 1]);
}
static uint32_t get_u32(const std::vector<uint8_t>& v, size_t o) {
    return ((uint32_t)v[o] << 24) | ((uint32_t)v[o + 1] << 16) |
           ((uint32_t)v[o + 2] << 8) | (uint32_t)v[o + 3];
}
static uint64_t get_u64(const std::vector<uint8_t>& v, size_t o) {
    uint64_t r = 0;
    for (int i = 0; i < 8; i++) r = (r << 8) | v[o + i];
    return r;
}

//========================================================================================
// 协议帧构建 (通用头 + Body + CRC32 + Tail)
//========================================================================================
static std::vector<uint8_t> build_frame(uint8_t msg_type, uint32_t transfer_id,
                                        uint32_t sequence,
                                        const std::vector<uint8_t>& body)
{
    std::vector<uint8_t> f;
    f.reserve(HEADER_LEN + body.size() + 6);

    put_u16(f, MAGIC);
    put_u8 (f, VERSION);
    put_u8 (f, msg_type);
    put_u32(f, transfer_id);
    put_u16(f, HEADER_LEN);
    put_u16(f, (uint16_t)body.size());
    put_u32(f, sequence);
    f.insert(f.end(), body.begin(), body.end());

    // CRC 覆盖 [Version .. Body 尾]
    uint32_t crc = crc32_final(crc32_iso_hdlc(f.data() + 2, f.size() - 2));
    put_u32(f, crc);
    put_u16(f, TAIL);
    return f;
}

//========================================================================================
// 各消息 Body
//========================================================================================
static std::vector<uint8_t> body_image_begin(uint32_t total_slices,
                                             uint32_t total_bytes,
                                             uint32_t expected_packets,
                                             uint32_t whole_crc32)
{
    std::vector<uint8_t> b;
    put_u32(b, total_slices);        // [0:3]
    put_u16(b, 512);                 // [4:5]  Width
    put_u16(b, 512);                 // [6:7]  Height
    put_u8 (b, 1);                   // [8]    Bytes_Per_Pixel
    put_u8 (b, 0x01);                // [9]    DType_Code = int8
    put_u8 (b, 0x01);                // [10]   Layout_Code
    put_u8 (b, 0x01);                // [11]   Z_Boundary
    put_u32(b, PACKET_PIXEL_BYTES);  // [12:15]
    put_u32(b, PACKETS_PER_SLICE);   // [16:19]
    put_u32(b, SLICE_BYTES);         // [20:23]
    put_u64(b, total_bytes);         // [24:31]
    put_u64(b, 0x10000000ull);       // [32:39] Image_Base_Addr
    put_u32(b, 1);                   // [40:43] Batch_Slices
    put_u32(b, expected_packets);    // [44:47]
    put_u32(b, whole_crc32);         // [48:51]
    put_u32(b, 0x00000001);          // [52:55] Quantization_ID
    put_u32(b, (uint32_t)(int32_t)-1024); // [56:59] HU_Min
    put_u32(b, 1000);                // [60:63] HU_Max
    put_u8 (b, 0x01);                // [64]   Rounding
    put_u8 (b, 0x01);                // [65]   XY_Padding
    put_u8 (b, 0x01);                // [66]   Target
    put_u8 (b, 0x00);                // [67]   Reserved
    put_u16(b, 33);                  // [68:69] Depth
    put_u16(b, 16);                  // [70:71] Center_Index
    put_u16(b, 96);                  // [72:73] Patch_Size
    put_u16(b, 0);                   // [74:75] Reserved
    return b;                        // 76 字节
}

static std::vector<uint8_t> body_image_data(uint16_t slice_id, uint16_t packet_idx,
                                            const uint8_t* pixels)
{
    std::vector<uint8_t> b;
    b.reserve(8 + PACKET_PIXEL_BYTES);
    put_u16(b, slice_id);
    put_u16(b, packet_idx);
    put_u16(b, PACKET_PIXEL_BYTES);
    put_u16(b, 0);
    b.insert(b.end(), pixels, pixels + PACKET_PIXEL_BYTES);
    return b;
}

static std::vector<uint8_t> body_batch_end(uint16_t batch_id, uint16_t first_slice,
                                           uint16_t slice_count,
                                           uint32_t expected_packets,
                                           uint32_t batch_crc32)
{
    std::vector<uint8_t> b;
    put_u16(b, batch_id);
    put_u16(b, first_slice);
    put_u16(b, slice_count);
    put_u16(b, 0);
    put_u32(b, expected_packets);
    put_u32(b, batch_crc32);
    return b;
}

static std::vector<uint8_t> body_image_end(uint32_t expected_packets,
                                           uint64_t expected_bytes,
                                           uint32_t whole_crc32)
{
    std::vector<uint8_t> b;
    put_u32(b, expected_packets);
    put_u64(b, expected_bytes);
    put_u32(b, whole_crc32);
    put_u32(b, 0);
    return b;
}

static std::vector<uint8_t> body_infer_trigger(uint32_t task_id, uint32_t center)
{
    std::vector<uint8_t> b;
    put_u32(b, task_id);
    put_u32(b, center);
    put_u16(b, 0);
    put_u16(b, 0);
    put_u16(b, 33);
    put_u16(b, 16);
    put_u16(b, 96);
    put_u16(b, 1);
    put_u32(b, 0);
    return b;
}

//========================================================================================
// 以太/IP/UDP 封装 (仅用于喂给 udp_rx; 其不校验 IP 校验和与以太 FCS)
//========================================================================================
static std::vector<uint8_t> wrap_ethernet(const std::vector<uint8_t>& payload,
                                          uint16_t src_port, uint16_t dst_port)
{
    std::vector<uint8_t> w;
    w.reserve(8 + 14 + 20 + 8 + payload.size());

    // 前导码 7×0x55 + SFD 0xD5
    for (int i = 0; i < 7; i++) w.push_back(0x55);
    w.push_back(0xD5);

    // 以太头: 目的 MAC = 板卡 MAC 00:11:22:33:44:55
    const uint8_t dst_mac[6] = {0x00, 0x11, 0x22, 0x33, 0x44, 0x55};
    const uint8_t src_mac[6] = {0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF};
    for (uint8_t x : dst_mac) w.push_back(x);
    for (uint8_t x : src_mac) w.push_back(x);
    w.push_back(0x08); w.push_back(0x00);

    // IP 头
    uint16_t ip_total = (uint16_t)(20 + 8 + payload.size());
    w.push_back(0x45); w.push_back(0x00);
    w.push_back(ip_total >> 8); w.push_back(ip_total & 0xFF);
    w.push_back(0x00); w.push_back(0x01);
    w.push_back(0x40); w.push_back(0x00);
    w.push_back(0x40); w.push_back(0x11);          // TTL 64, UDP
    w.push_back(0x00); w.push_back(0x00);          // 校验和(不校验)
    const uint8_t src_ip[4] = {192, 168, 1, 102};
    const uint8_t dst_ip[4] = {192, 168, 1, 10};
    for (uint8_t x : src_ip) w.push_back(x);
    for (uint8_t x : dst_ip) w.push_back(x);

    // UDP 头
    uint16_t udp_len = (uint16_t)(8 + payload.size());
    w.push_back(src_port >> 8); w.push_back(src_port & 0xFF);
    w.push_back(dst_port >> 8); w.push_back(dst_port & 0xFF);
    w.push_back(udp_len >> 8);  w.push_back(udp_len & 0xFF);
    w.push_back(0x00); w.push_back(0x00);          // 校验和(不校验)

    w.insert(w.end(), payload.begin(), payload.end());

    // 以太 FCS: udp_rx 不校验, 填 0 即可
    for (int i = 0; i < 4; i++) w.push_back(0x00);

    return w;
}

//========================================================================================
// DUT 封装
//========================================================================================
struct Dut {
    Veth_top*       top;
#ifdef VM_TRACE
    VerilatedVcdC*  tfp = nullptr;
#endif
    uint64_t        t   = 0;
    bool            trace_on = false;

    // ---- RX 注入队列 ----
    // 关键: 必须按"帧"排队并插入帧间间隔, 不能把多帧字节平铺进同一个队列。
    // 原因: udp_rx 的 st_rx_end 需要等待 gmii_rx_dv 拉低才回到 st_idle:
    //         st_rx_end: if (gmii_rx_dv == 1'b0) skip_en <= 1'b1;
    //       若多帧背靠背、rx_dv 一直为高, 它在收完第 1 帧后会一直卡在 st_rx_end,
    //       后续帧全部被忽略 (实测现象: 只回一次 ACK, 之后 BATCH_STATUS 永远不来)。
    std::deque<std::vector<uint8_t>> pending_frames;   // 待注入的整帧(含前导码)
    std::vector<uint8_t>             cur_frame;        // 正在注入的帧
    size_t                           cur_pos = 0;      // 当前注入到第几字节
    int                              gap = 0;          // 帧间间隔计数

    // 尚未注入的字节数 (用于估算需要推进多少周期)
    size_t pending_bytes() const {
        size_t n = cur_frame.size() - cur_pos;
        for (const auto& f : pending_frames) n += f.size() + 8;
        return n;
    }

    // GMII TX 抓取
    std::vector<uint8_t> tx_frame;
    bool                 tx_active = false;
    std::vector<std::vector<uint8_t>> tx_frames;   // 已完成的帧(去掉前导码)

    explicit Dut(bool trace) {
        top = new Veth_top;
        trace_on = trace;
#ifdef VM_TRACE
        if (trace_on) {
            Verilated::traceEverOn(true);
            tfp = new VerilatedVcdC;
            top->trace(tfp, 99);
        tfp->open("results/wave.vcd");
        }
#else
        if (trace_on)
            std::fprintf(stderr, "警告: 编译时未加 --trace, 忽略 --trace 参数\n");
#endif
    }
    ~Dut() {
#ifdef VM_TRACE
        if (tfp) { tfp->close(); delete tfp; }
#endif
        delete top;
    }

    // 排入一个完整以太网帧 (含前导码), 帧间自动插入间隔
    void prepend_frame(const std::vector<uint8_t>& wire) {
        if (wire.empty()) return;
        pending_frames.push_back(wire);
    }

    // 波形采样 (未开 --trace 时为空操作)
    void dump() {
#ifdef VM_TRACE
        if (tfp) tfp->dump(t);
#endif
    }

    // 推进一个 125MHz 周期
    //
    // 采样相位说明:
    //   udp_tx 在 clk 上升沿更新 gmii_txd/gmii_tx_en (它们是寄存器输出)。
    //   因此必须在"上升沿 eval 之后"读取, 才拿到与线上一致的字节;
    //   若在下降沿读, 会读到上一拍的旧值, 整帧错位一字节。
    void step() {
        // ---- RX 驱动: 逐帧注入, 帧间留够间隔让 udp_rx 回到 st_idle ----
        if (cur_pos < cur_frame.size()) {
            top->gmii_rx_dv_i = 1;
            top->gmii_rxd_i   = cur_frame[cur_pos++];
        } else {
            // 当前帧发完: 先给帧间间隔, 再取下一帧
            if (gap > 0) {
                gap--;
            } else if (!pending_frames.empty()) {
                cur_frame.swap(pending_frames.front());
                pending_frames.pop_front();
                cur_pos = 0;
                gap     = 8;               // 帧间间隔 (IFG)
                top->gmii_rx_dv_i = 1;
                top->gmii_rxd_i   = cur_frame[cur_pos++];
            } else {
                top->gmii_rx_dv_i = 0;
                top->gmii_rxd_i   = 0;
            }
        }

        // 上升沿: 寄存器更新, 采样 TX
        top->clk_i = 1;
        top->eval();
        dump();
        t++;

        if (top->gmii_tx_en_o) {
            tx_active = true;
            tx_frame.push_back((uint8_t)top->gmii_txd_o);
        } else if (tx_active) {
            tx_active = false;
            if (!tx_frame.empty()) {
                tx_frames.push_back(tx_frame);
                tx_frame.clear();
            }
        }

        // 下降沿
        top->clk_i = 0;
        top->eval();
        dump();
    }

    void run(int cycles) { for (int i = 0; i < cycles; i++) step(); }

    // 跑到 TX 帧队列出现新帧 (或超时)
    bool wait_frame(int timeout_cycles) {
        size_t before = tx_frames.size();
        for (int i = 0; i < timeout_cycles; i++) {
            step();
            if (tx_frames.size() > before) return true;
        }
        return false;
    }

    // 诊断: 打印已捕获的所有 GMII 帧
    void dump_tx_frames(const char* tag) const {
        std::printf("    [诊断 %s] 已捕获 %zu 个 GMII 帧:\n", tag, tx_frames.size());
        for (size_t i = 0; i < tx_frames.size() && i < 4; i++) {
            const auto& f = tx_frames[i];
            std::printf("      帧#%zu 长 %zu:", i, f.size());
            for (size_t k = 0; k < f.size() && k < 24; k++)
                std::printf(" %02X", f[k]);
            std::vector<uint8_t> pl;
            if (extract_payload(f, pl)) {
                std::printf("\n         -> 载荷 %zu 字节:", pl.size());
                for (size_t k = 0; k < pl.size() && k < 16; k++)
                    std::printf(" %02X", pl[k]);
            } else {
                std::printf("\n         -> extract_payload 失败");
            }
            std::printf("\n");
        }
    }

    void reset(int cycles = 20) {
        top->rst_n_i     = 0;
        top->clk_i       = 0;
        top->gmii_rx_dv_i= 0;
        top->gmii_rxd_i  = 0;
        for (int i = 0; i < cycles; i++) {
            top->clk_i = 1; top->eval(); dump(); t++;
            top->clk_i = 0; top->eval(); dump();
        }
        top->rst_n_i = 1;
        run(10);
    }

    // 从抓到的 GMII 帧剥离 前导(8) + 以太(14) + IP(20) + UDP(8) + FCS(4)
    // 注意下标含 8 字节前导码偏移:
    //   [0..7]   前导码
    //   [8..21]  以太头 (目的MAC 8..13, 源MAC 14..19, EtherType 20..21)
    //   [22..41] IP 头  (协议号在 31)
    //   [42..49] UDP 头
    //   [50..]   载荷
    static bool extract_payload(const std::vector<uint8_t>& f,
                                std::vector<uint8_t>& payload)
    {
        const size_t off = 8 + 14 + 20 + 8;      // = 50
        if (f.size() < off + 4) return false;
        if (f[20] != 0x08 || f[21] != 0x00) return false;   // EtherType IPv4
        if (f[31] != 0x11) return false;                     // IP Protocol UDP
        size_t total = f.size() - 4;                         // 去掉 FCS
        if (total <= off) return false;
        payload.assign(f.begin() + off, f.begin() + total);
        return true;
    }
};

//========================================================================================
// 校验辅助
//========================================================================================
static int g_fail = 0;

static void expect(bool cond, const std::string& what)
{
    std::printf("    [%s] %s\n", cond ? " OK " : "FAIL", what.c_str());
    if (!cond) g_fail++;
}

// 从 GMII 帧取出协议载荷
static bool gmii_to_payload(const std::vector<uint8_t>& f, std::vector<uint8_t>& payload)
{
    return Dut::extract_payload(f, payload);
}

// 解析一个响应帧
struct ParsedFrame {
    bool     ok = false;
    uint8_t  msg_type = 0;
    uint32_t transfer_id = 0;
    uint32_t sequence = 0;
    uint16_t body_len = 0;
    std::vector<uint8_t> body;
    uint32_t crc = 0;
    std::string err;
};

static ParsedFrame parse_frame(const std::vector<uint8_t>& f)
{
    ParsedFrame r;
    if (f.size() < HEADER_LEN + 6) { r.err = "too short"; return r; }
    if (get_u16(f, 0) != MAGIC)    { r.err = "bad magic"; return r; }
    if (f[2] != VERSION)           { r.err = "bad version"; return r; }
    r.msg_type    = f[3];
    r.transfer_id = get_u32(f, 4);
    if (get_u16(f, 8) != HEADER_LEN) { r.err = "bad header_len"; return r; }
    r.body_len    = get_u16(f, 10);
    r.sequence    = get_u32(f, 12);
    if (f.size() < (size_t)(HEADER_LEN + r.body_len + 6)) { r.err = "truncated"; return r; }

    r.body.assign(f.begin() + HEADER_LEN, f.begin() + HEADER_LEN + r.body_len);

    size_t crc_off = HEADER_LEN + r.body_len;
    r.crc = get_u32(f, crc_off);
    uint16_t tail = get_u16(f, crc_off + 4);
    if (tail != TAIL) { r.err = "bad tail"; return r; }

    uint32_t calc = crc32_final(crc32_iso_hdlc(f.data() + 2, crc_off - 2));
    if (calc != r.crc) {
        char buf[96];
        std::snprintf(buf, sizeof buf, "CRC mismatch stored=0x%08X calc=0x%08X",
                      r.crc, calc);
        r.err = buf;
        return r;
    }
    r.ok = true;
    return r;
}

// 解析 FPGA 回传的 GMII 帧: 先剥 以太/IP/UDP 头, 再按协议解析
static ParsedFrame parse_gmii_frame(const std::vector<uint8_t>& f)
{
    std::vector<uint8_t> payload;
    if (!Dut::extract_payload(f, payload)) {
        ParsedFrame r;
        r.err = "extract_payload failed (以太/IP/UDP 头异常)";
        return r;
    }
    return parse_frame(payload);
}

//========================================================================================
// 内建自测
//========================================================================================
static uint32_t g_whole_crc = 0;

// 生成一份确定的切片像素 (signed int8 全范围), 计算整卷 CRC
static void make_slice(std::vector<uint8_t>& slice, uint32_t slice_id)
{
    slice.resize(SLICE_BYTES);
    for (uint32_t i = 0; i < SLICE_BYTES; i++)
        slice[i] = (uint8_t)((i * 31u + slice_id * 97u) & 0xFF);
}

static int run_selftest(bool trace, int drop_mod)
{
    Dut dut(trace);
    dut.reset();

    const uint32_t TOTAL_SLICES = 1;
    const uint32_t TOTAL_BYTES  = TOTAL_SLICES * SLICE_BYTES;
    const uint32_t EXP_PACKETS  = TOTAL_SLICES * PACKETS_PER_SLICE;
    const uint32_t TRANSFER_ID  = 0x11223344;
    uint32_t seq = 0;

    std::vector<uint8_t> slice;
    make_slice(slice, 0);
    g_whole_crc = crc32_final(crc32_iso_hdlc(slice.data(), slice.size()));

    std::printf("================================================================\n");
    std::printf(" CT-FPGA 以太网收发链路 内建自测\n");
    std::printf(" 整卷: %u 层, %u 包, whole_crc32=0x%08X\n",
                TOTAL_SLICES, EXP_PACKETS, g_whole_crc);
    if (drop_mod > 0)
        std::printf(" 故意丢包: 每 %d 个包丢 1 个 (第二包号为 index %% %d == 7)\n",
                    drop_mod, drop_mod);
    std::printf("================================================================\n");

    // ---------------- 1. IMAGE_BEGIN ----------------
    std::printf("\n[1] IMAGE_BEGIN -> 期望 ACK(ACCEPTED=0x00)\n");
    auto b_begin = body_image_begin(TOTAL_SLICES, TOTAL_BYTES, EXP_PACKETS, g_whole_crc);
    expect(b_begin.size() == 76, "IMAGE_BEGIN Body = 76 字节");
    auto f_begin = build_frame(MSG_IMAGE_BEGIN, TRANSFER_ID, seq++, b_begin);
    dut.prepend_frame(wrap_ethernet(f_begin, 8080, 8080));
    if (!dut.wait_frame(20000)) {
        std::printf("    [FAIL] 未收到 ACK\n");
        g_fail++;
        return g_fail;
    }
    {
        auto p = parse_gmii_frame(dut.tx_frames.back());
        if (!p.ok) {
            std::printf("    [FAIL] ACK 帧非法: %s\n", p.err.c_str());
            dut.dump_tx_frames("ACK");
            g_fail++;
            return g_fail;
        }
        expect(p.msg_type == MSG_ACK, "Msg_Type = ACK(0x81)");
        expect(p.transfer_id == TRANSFER_ID, "Transfer_ID 回显");
        expect(p.body.size() == 8, "ACK Body = 8 字节");
        expect(p.body.size() >= 5 && p.body[0] == MSG_IMAGE_BEGIN, "Acked_Msg_Type = IMAGE_BEGIN");
        expect(p.body.size() >= 2 && p.body[1] == 0x00, "Status = ACCEPTED(0x00)");
        expect(p.body.size() >= 8 && get_u32(p.body, 4) == 0,
               "Acked_Sequence = 0 (IMAGE_BEGIN 的序号)");
    }

    // ---------------- 2. 256 × IMAGE_DATA ----------------
    std::printf("\n[2] 256 × IMAGE_DATA -> 期望不回帧, 计数=256\n");
    // 刻意丢掉一部分包, 检验位图
    std::set<uint16_t> dropped;
    for (uint16_t i = 0; i < PACKETS_PER_SLICE; i++) {
        if (drop_mod > 0 && (i % (uint16_t)drop_mod) == 7) {
            dropped.insert(i);
            continue;
        }
        auto body = body_image_data(0, i, slice.data() + (size_t)i * PACKET_PIXEL_BYTES);
        auto fr   = build_frame(MSG_IMAGE_DATA, TRANSFER_ID, seq++, body);
        dut.prepend_frame(wrap_ethernet(fr, 8080, 8080));
        dut.run((int)((8 + 14 + 20 + 8 + fr.size() + 4 + 12) * 1.2));
    }
    dut.run(4000);
    uint32_t rx_cnt = dut.top->rx_pkt_cnt_o;
    std::printf("    FPGA 计数 rx_pkt_cnt_o = %u (期望 %u)\n",
                rx_cnt, (uint32_t)(PACKETS_PER_SLICE - dropped.size()));
    expect(rx_cnt == (uint32_t)(PACKETS_PER_SLICE - dropped.size()),
           "收到的 IMAGE_DATA 数 = 实际发送数");
    expect(dut.top->rx_bad_crc_cnt_o == 0, "无 CRC 错帧");

    // ---------------- 3. BATCH_END ----------------
    std::printf("\n[3] BATCH_END -> 期望 BATCH_STATUS + 缺包位图\n");
    auto b_be = body_batch_end(0, 0, 1, PACKETS_PER_SLICE, 0);
    auto f_be = build_frame(MSG_BATCH_END, TRANSFER_ID, seq++, b_be);
    dut.prepend_frame(wrap_ethernet(f_be, 8080, 8080));
    if (!dut.wait_frame(40000)) {
        std::printf("    [FAIL] 未收到 BATCH_STATUS\n");
        g_fail++;
        return g_fail;
    }
    {
        auto p = parse_gmii_frame(dut.tx_frames.back());
        if (!p.ok) { std::printf("    [FAIL] BATCH_STATUS 帧非法: %s\n", p.err.c_str()); g_fail++; return g_fail; }
        expect(p.msg_type == MSG_BATCH_STATUS, "Msg_Type = BATCH_STATUS(0x83)");
        expect(p.body.size() == 16 + 32, "Body = 16 + 32(位图) = 48 字节");

        uint16_t batch_id   = get_u16(p.body, 0);
        uint8_t  status     = p.body[2];
        uint32_t expected   = get_u32(p.body, 4);
        uint32_t received   = get_u32(p.body, 8);
        uint16_t bm_bytes   = get_u16(p.body, 12);

        expect(batch_id == 0, "Batch_ID = 0");
        expect(expected == PACKETS_PER_SLICE, "Expected_Packets = 256");
        expect(received == (uint32_t)(PACKETS_PER_SLICE - dropped.size()),
               "Received_Packets = 实际收到数");
        expect(bm_bytes == 32, "Bitmap_Bytes = 32");
        expect(status == (dropped.empty() ? 0x00 : 0x01),
               dropped.empty() ? "Status = COMPLETE(0x00)" : "Status = MISSING(0x01)");

        // 校验位图逐位
        const uint8_t* bm = p.body.data() + 16;
        std::set<uint16_t> decoded;
        for (uint16_t i = 0; i < PACKETS_PER_SLICE; i++)
            if (bm[i / 8] >> (7 - (i % 8)) & 1) decoded.insert(i);

        std::printf("    FPGA 位图报缺失 %u 个包, 本地丢了 %u 个包\n",
                    (unsigned)decoded.size(), (unsigned)dropped.size());
        expect(decoded == dropped, "缺包位图与本地丢包集合完全一致");
        if (decoded != dropped) {
            std::printf("      位图: ");
            for (uint16_t i : decoded) std::printf("%u ", i);
            std::printf("\n      期望: ");
            for (uint16_t i : dropped) std::printf("%u ", i);
            std::printf("\n");
        }
    }

    // ---------------- 4. IMAGE_END ----------------
    std::printf("\n[4] IMAGE_END -> 期望 IMAGE_READY\n");
    auto b_ie = body_image_end(EXP_PACKETS, TOTAL_BYTES, g_whole_crc);
    auto f_ie = build_frame(MSG_IMAGE_END, TRANSFER_ID, seq++, b_ie);
    dut.prepend_frame(wrap_ethernet(f_ie, 8080, 8080));
    if (!dut.wait_frame(40000)) {
        std::printf("    [FAIL] 未收到 IMAGE_READY\n");
        g_fail++;
        return g_fail;
    }
    {
        auto p = parse_gmii_frame(dut.tx_frames.back());
        if (!p.ok) { std::printf("    [FAIL] IMAGE_READY 帧非法: %s\n", p.err.c_str()); g_fail++; return g_fail; }
        expect(p.msg_type == MSG_IMAGE_READY, "Msg_Type = IMAGE_READY(0x84)");
        expect(p.body.size() == 32, "Body = 32 字节");
        uint8_t  status = p.body[0];
        uint32_t slices = get_u32(p.body, 4);
        uint32_t pkts   = get_u32(p.body, 8);
        uint64_t bytes_ = get_u64(p.body, 12);
        std::printf("    Status=0x%02X Slices=%u Packets=%u Bytes=%llu\n",
                    status, slices, pkts, (unsigned long long)bytes_);
        expect(slices == TOTAL_SLICES, "Received_Slices = 1");
        expect(pkts == rx_cnt, "Received_Packets = 实收数");
        expect(bytes_ == TOTAL_BYTES, "Received_Bytes = 262144");
        expect(status == (dropped.empty() ? 0x00 : 0x01),
               dropped.empty() ? "Status = READY_OK(0x00)" : "Status = MISSING(0x01)");
    }

    // ---------------- 5. INFER_TRIGGER ----------------
    std::printf("\n[5] INFER_TRIGGER -> 期望 INFER_DONE(0xDEADBEEF)\n");
    auto b_it = body_infer_trigger(0xABCD, 0);
    auto f_it = build_frame(MSG_INFER_TRIGGER, TRANSFER_ID, seq++, b_it);
    dut.prepend_frame(wrap_ethernet(f_it, 8080, 8080));
    if (!dut.wait_frame(40000)) {
        std::printf("    [FAIL] 未收到 INFER_DONE\n");
        g_fail++;
        return g_fail;
    }
    {
        auto p = parse_gmii_frame(dut.tx_frames.back());
        if (!p.ok) { std::printf("    [FAIL] INFER_DONE 帧非法: %s\n", p.err.c_str()); g_fail++; return g_fail; }
        expect(p.msg_type == MSG_INFER_DONE, "Msg_Type = INFER_DONE(0x82)");
        expect(p.body.size() == 16, "Body = 16 字节");
        expect(p.body.size() >= 4 && get_u32(p.body, 0) == 0xABCD, "Task_ID 回显");
        expect(p.body.size() >= 9 && p.body[8] == 0x00, "Status = OK(0x00)");
        expect(p.body.size() >= 16 && get_u32(p.body, 12) == 0xDEADBEEF,
               "Result = 0xDEADBEEF");
    }

    std::printf("\n================================================================\n");
    std::printf(" 自测结束: %s (失败项 %d)\n", g_fail ? "存在失败" : "全部通过", g_fail);
    std::printf(" 仿真推进周期数: %llu\n", (unsigned long long)dut.t);
    std::printf("================================================================\n");
    return g_fail;
}

//========================================================================================
// UDP 桥接模式
//========================================================================================
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <cerrno>

static int run_bridge(bool trace, const std::string& bind_ip, int bind_port,
                      const std::string& peer_ip, int peer_port,
                      double idle_timeout_s, uint64_t max_cycles)
{
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) { std::perror("socket"); return 1; }

    int one = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    int rcvbuf = 8 * 1024 * 1024;
    setsockopt(sock, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof rcvbuf);

    sockaddr_in local{};
    local.sin_family = AF_INET;
    local.sin_port   = htons((uint16_t)bind_port);
    if (inet_pton(AF_INET, bind_ip.c_str(), &local.sin_addr) != 1) {
        std::fprintf(stderr, "非法绑定地址: %s\n", bind_ip.c_str());
        return 1;
    }
    if (bind(sock, (sockaddr*)&local, sizeof local) < 0) {
        std::perror("bind");
        std::fprintf(stderr,
            "提示: 需要先在本机(lo)上配置 FPGA 地址:\n"
            "  sudo ip addr add %s/32 dev lo\n", bind_ip.c_str());
        return 1;
    }

    sockaddr_in peer{};
    peer.sin_family = AF_INET;
    peer.sin_port   = htons((uint16_t)peer_port);
    inet_pton(AF_INET, peer_ip.c_str(), &peer.sin_addr);

    fcntl(sock, F_SETFL, O_NONBLOCK);

    Dut dut(trace);
    dut.reset();
    std::printf("================================================================\n");
    std::printf(" UDP 桥接模式 (Verilator)\n");
    std::printf("   绑定 FPGA 侧: %s:%d\n", bind_ip.c_str(), bind_port);
    std::printf("   对端 PC 侧  : %s:%d\n", peer_ip.c_str(), peer_port);
    std::printf("   现在可在 PC 端运行: python prj/main.py send --limit-slices 1\n");
    std::printf("  (Ctrl-C 结束)\n");
    std::printf("================================================================\n");

    uint64_t rx_datagrams = 0;
    uint64_t tx_datagrams = 0;
    size_t   tx_seen = 0;
    uint64_t cycles_since_rx = 0;
    uint8_t  buf[65536];

    while (dut.t < max_cycles) {
        // ---- 拉取 socket 数据（每次最多几个包，避免队列堆积）----
        bool got = false;
        for (int burst = 0; burst < 16; burst++) {  // 从 256 降到 16，分批处理
            ssize_t n = recv(sock, buf, sizeof buf, 0);
            if (n <= 0) break;
            got = true;
            rx_datagrams++;
            std::vector<uint8_t> payload(buf, buf + n);
            dut.prepend_frame(wrap_ethernet(payload, (uint16_t)peer_port, (uint16_t)bind_port));
        }
        if (got) cycles_since_rx = 0; else cycles_since_rx++;

        // 周期性状态输出, 便于观察 FPGA 侧处理进度
        {
            static uint64_t next_report = 0;
            if (dut.t >= next_report) {
                std::printf("  [状态] t=%llu 待注入=%zuB 已收IMAGE_DATA=%u 帧错误=%u 批次=%u 回送=%llu\n",
                            (unsigned long long)dut.t, dut.pending_bytes(),
                            dut.top->rx_pkt_cnt_o, dut.top->rx_bad_crc_cnt_o,
                            dut.top->rx_batch_cnt_o, (unsigned long long)tx_datagrams);
                std::fflush(stdout);
                next_report = dut.t + 2000000;
            }
        }

        // ---- 推进 DUT（确保处理完队列中所有帧）----
        size_t pend = dut.pending_bytes();
        if (pend > 0) {
            // 有待注入数据：推进足够多的周期处理完它们
            // 每字节平均需 10 周期（包括状态机开销）
            int n_step = (int)(pend * 10 + 10000);  // 10 倍余量 + 响应构建时间
            if (n_step > 500000) n_step = 500000;
            dut.run(n_step);
        } else {
            // 空闲：推进少量周期检查是否有新的 TX 输出
            dut.run(256);
        }

        // ---- 回送已完成的 TX 帧 ----
        while (tx_seen < dut.tx_frames.size()) {
            std::vector<uint8_t> payload;
            if (Dut::extract_payload(dut.tx_frames[tx_seen], payload) && !payload.empty()) {
                sendto(sock, payload.data(), payload.size(), 0,
                       (sockaddr*)&peer, sizeof peer);
                tx_datagrams++;
                std::printf("  [TX] 回送 %zu 字节 (帧 #%llu)\n",
                            payload.size(), (unsigned long long)tx_datagrams);
                std::fflush(stdout);
            }
            tx_seen++;
        }

        // ---- 空闲超时 ----
        if (cycles_since_rx > (uint64_t)(idle_timeout_s * 125000000.0)) {
            std::printf("\n空闲 %.1fs, 结束。累计: 收 %llu 个数据报, 回 %llu 个\n",
                        idle_timeout_s, (unsigned long long)rx_datagrams,
                        (unsigned long long)tx_datagrams);
            break;
        }
    }

    std::printf("桥接结束: rx_datagrams=%llu tx_datagrams=%llu cycles=%llu\n",
                (unsigned long long)rx_datagrams,
                (unsigned long long)tx_datagrams, (unsigned long long)dut.t);
    std::printf("FPGA 侧统计: IMAGE_DATA=%u, 帧错误=%u, 批次数=%u\n",
                dut.top->rx_pkt_cnt_o, dut.top->rx_bad_crc_cnt_o, dut.top->rx_batch_cnt_o);
    close(sock);
    return 0;
}

//========================================================================================
// main
//========================================================================================
int main(int argc, char** argv)
{
    Verilated::commandArgs(argc, argv);

    bool        trace     = false;
    bool        selftest  = false;
    int         drop_mod  = 0;
    std::string bind_ip   = "192.168.1.10";
    int         bind_port = 8080;
    std::string peer_ip   = "192.168.1.102";
    int         peer_port = 8080;
    double      idle_s    = 3.0;
    uint64_t    max_cycles= (uint64_t)125000000 * 300;   // 300 秒仿真上限

    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&](void) -> std::string { return (i + 1 < argc) ? argv[++i] : std::string(); };

        if      (a == "--selftest")             selftest = true;
        else if (a == "--trace")                trace = true;
        else if (a == "--drop-mod")             drop_mod = std::atoi(next().c_str());
        else if (a == "--bind-ip")              bind_ip = next();
        else if (a == "--bind-port")            bind_port = std::atoi(next().c_str());
        else if (a == "--peer-ip")              peer_ip = next();
        else if (a == "--peer-port")            peer_port = std::atoi(next().c_str());
        else if (a == "--idle-s")               idle_s = std::atof(next().c_str());
        else if (a == "--help" || a == "-h") {
            std::printf(
                "用法: Veth_top [选项]\n"
                "  --selftest            内建自测(不用 socket), 完整跑一遍协议流程\n"
                "  --drop-mod N          自测时每 N 个包丢 1 个(包号 %% N == 7), 校验缺包位图\n"
                "  --trace               输出 wave.vcd 波形(大, 建议仅调试时开)\n"
                "  --bind-ip/--bind-port 本机绑定(FPGA 侧), 默认 192.168.1.10:8080\n"
                "  --peer-ip/--peer-port 对端(PC 侧), 默认 192.168.1.102:8080\n"
                "  --idle-s SEC          空闲多久后退出, 默认 3.0\n");
            return 0;
        }
        else {
            std::fprintf(stderr, "未知参数: %s (--help 查看用法)\n", a.c_str());
            return 2;
        }
    }

    if (selftest) {
        int fails = run_selftest(trace, drop_mod);
        return fails ? 1 : 0;
    }
    return run_bridge(trace, bind_ip, bind_port, peer_ip, peer_port, idle_s, max_cycles);
}
