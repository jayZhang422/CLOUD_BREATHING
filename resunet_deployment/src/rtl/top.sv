`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 2026/10/03
// Design Name: Ethernet图像写DDR与读回CRC顶层（保留独立DDR压测模式）
// Module Name: top
// Project Name: Model_Deployment
// Target Devices: xcku5p-ffvb676-2-i
// Tool Versions: Vivado 2026.1
// Description:
//   1. 例化 DDR4 MIG 控制器 (256-bit UI @ 333.33MHz)
//   2. 例化 V3.0 高性能 AXI4 Master (Outstanding=8, 4KB 边界自动切片)
//   3. ETHERNET_ENABLE=1: 1024B整包缓存、跨时钟握手、B响应确认后计数、DDR读回CRC
//      ETHERNET_ENABLE=0: 原DDR吞吐压测；AXI master和MIG接口保持不变
//   4. 硬件跑分计时器: 每轮锁存写/读周期数, 并统计历史最小周期数 (= 最佳带宽)
//   5. 独立 DDR 压测连续运行；计时器保留，VIO 已移除
//
// V2 相对 V1 的修改:
//   - 修复 test_round 在 ST_CHECK_END 每周期自增的问题 (现在每轮只 +1)
//   - 数据模式混入轮号: 每轮写入的数据都不同, 上一轮残留数据无法通过本轮读校验
//   - 8 个 32 位通道各异 (counter ^ 通道常数), 可发现通道串线; 数据生成扇出 256 -> 32
//   - 读比对打一拍 (逐通道比较后寄存), 缩短 333MHz 下的关键路径
//   - 新增 wr/rd 最小周期统计
//   - buser/ruser 显式置 0
//
// 带宽(GB/s) = TEST_TOTAL_BYTES * 333.333e6 / cycles / 1e9, 理论峰值 10.667 GB/s
//////////////////////////////////////////////////////////////////////////////////

module top #(
    parameter bit ETHERNET_ENABLE = 1'b1, // 默认图像接收；0保留DDR独立压测
    parameter bit COMPUTE_250MHZ = 1'b1, // 默认选择250MHz候选；0选择独立125MHz
    // 单轮压测总字节数 (硬件默认 64MB: 67,108,864 字节 = 2,097,152 拍 256-bit 数据; 仿真可重设为 16KB 快速出波形)
    parameter bit [31:0] TEST_TOTAL_BYTES = 32'd67108864,
    parameter bit [30:0] TEST_START_ADDR  = 31'h0000_0000
)(
    // DDR4 物理硬件引脚 (直接由 PCB 连接 DDR4 颗粒)
    output logic                  c0_ddr4_act_n,
    output logic [16:0]           c0_ddr4_adr,
    output logic [1:0]            c0_ddr4_ba,
    output logic [0:0]            c0_ddr4_bg,
    output logic [0:0]            c0_ddr4_cke,
    output logic [0:0]            c0_ddr4_odt,
    output logic [0:0]            c0_ddr4_cs_n,
    output logic [0:0]            c0_ddr4_ck_t,
    output logic [0:0]            c0_ddr4_ck_c,
    output logic                  c0_ddr4_reset_n,
    inout  wire  [3:0]            c0_ddr4_dm_dbi_n,
    inout  wire  [31:0]           c0_ddr4_dq,
    inout  wire  [3:0]            c0_ddr4_dqs_t,
    inout  wire  [3:0]            c0_ddr4_dqs_c,

    // 系统参考时钟与指示灯
    input  wire                   c0_sys_clk_p,           // 200MHz 差分输入 P
    input  wire                   c0_sys_clk_n,           // 200MHz 差分输入 N
    output logic                  c0_init_calib_complete, // LED H11: 初始化校准完成
    output logic                  error,                  // LED G11: 数据比对错误指示
    input  wire                   sys_rst,                // 按键 K9: 外部低电平复位
    input  logic                  eth_rxc_i,              // PHY 125MHz
    input  logic                  eth_rx_ctl_i,
    input  logic [3:0]            eth_rxd_i,
    output logic                  eth_txc_o,
    output logic                  eth_tx_ctl_o,
    output logic [3:0]            eth_txd_o
);

    //==========================================================================
    // 常量定义与测试规模配置
    //==========================================================================
    localparam int AXI_ADDR_WIDTH = 31;
    localparam int AXI_DATA_WIDTH = 256;
    localparam int AXI_BYTES      = AXI_DATA_WIDTH / 8; // 32 字节

    // 8 个 32 位通道的区分常数 (黄金分割乘法, lane0 = 0), 数据 = 计数器 ^ 通道常数
    function automatic logic [255:0] build_lane_c();
        for (int i = 0; i < 8; i++) begin
            build_lane_c[32*i +: 32] = 32'h9E37_79B9 * 32'(i);
        end
    endfunction
    localparam logic [255:0] LANE_C = build_lane_c();

    //==========================================================================
    // 时钟与复位网络
    //==========================================================================
    logic axi_reset_n_w;
    wire c0_ddr4_ui_clk;
    wire c0_ddr4_ui_clk_sync_rst;
    reg  c0_ddr4_aresetn;

    wire calib_complete_w;
    assign c0_init_calib_complete = calib_complete_w;

    // 复位同步化: 必须在校准完成且控制器释放复位后才拉高 AXI 总线复位
    always_ff @(posedge c0_ddr4_ui_clk) begin
        if (c0_ddr4_ui_clk_sync_rst || !calib_complete_w) begin
            c0_ddr4_aresetn <= 1'b0;
        end else begin
            c0_ddr4_aresetn <= 1'b1;
        end
    end

    //==========================================================================
    // AXI4 总线互连连线
    //==========================================================================
    wire [0:0]                 axi_awid;
    wire [AXI_ADDR_WIDTH-1:0]  axi_awaddr;
    wire [7:0]                 axi_awlen;
    wire [2:0]                 axi_awsize;
    wire [1:0]                 axi_awburst;
    wire                       axi_awlock;
    wire [3:0]                 axi_awcache;
    wire [2:0]                 axi_awprot;
    wire [3:0]                 axi_awqos;
    wire [0:0]                 axi_awuser;
    wire                       axi_awvalid;
    wire                       axi_awready;

    wire [AXI_DATA_WIDTH-1:0]  axi_wdata;
    wire [31:0]                axi_wstrb;
    wire                       axi_wlast;
    wire [0:0]                 axi_wuser;
    wire                       axi_wvalid;
    wire                       axi_wready;

    wire [0:0]                 axi_bid;
    wire [1:0]                 axi_bresp;
    wire [0:0]                 axi_buser;
    wire                       axi_bvalid;
    wire                       axi_bready;

    wire [0:0]                 axi_arid;
    wire [AXI_ADDR_WIDTH-1:0]  axi_araddr;
    wire [7:0]                 axi_arlen;
    wire [2:0]                 axi_arsize;
    wire [1:0]                 axi_arburst;
    wire                       axi_arlock;
    wire [3:0]                 axi_arcache;
    wire [2:0]                 axi_arprot;
    wire [3:0]                 axi_arqos;
    wire [0:0]                 axi_aruser;
    wire                       axi_arvalid;
    wire                       axi_arready;

    wire [0:0]                 axi_rid;
    wire [AXI_DATA_WIDTH-1:0]  axi_rdata;
    wire [1:0]                 axi_rresp;
    wire                       axi_rlast;
    wire [0:0]                 axi_ruser;
    wire                       axi_rvalid;
    wire                       axi_rready;

    // MIG 无 USER 信号, 对应 master 输入显式置 0
    assign axi_buser = 1'b0;
    assign axi_ruser = 1'b0;

    // MIG IP 的 4 位 ID 扩展与未连接信号
    wire [3:0]                 mig_awid = {3'b000, axi_awid};
    wire [3:0]                 mig_arid = {3'b000, axi_arid};
    wire [3:0]                 mig_bid;
    wire [3:0]                 mig_rid;
    assign axi_bid = mig_bid[0];
    assign axi_rid = mig_rid[0];

    //==========================================================================
    // 用户侧控制与虚拟 FIFO 信号
    //==========================================================================
    logic        user_wr_start;
    logic [30:0] user_wr_addr;
    logic [31:0] user_wr_len;
    logic        user_wr_ready;
    logic        user_wr_done;
    logic        user_wr_err;

    logic        user_rd_start;
    logic [30:0] user_rd_addr;
    logic [31:0] user_rd_len;
    logic        user_rd_ready;
    logic        user_rd_done;
    logic        user_rd_err;

    // 虚拟 FIFO 读写端口 (零气泡全速数据流)
    logic        wr_fifo_re;
    logic        wr_fifo_empty;
    logic [AXI_DATA_WIDTH-1:0] wr_fifo_data;

    logic        rd_fifo_we;
    logic        rd_fifo_full;
    logic [AXI_DATA_WIDTH-1:0] rd_fifo_data;

    //==========================================================================
    // 性能跑分计时器与状态机
    //==========================================================================
    typedef enum logic [2:0] {
        ST_IDLE      = 3'd0,
        ST_WR_RUN    = 3'd1,
        ST_WR_WAIT   = 3'd2,
        ST_RD_RUN    = 3'd3,
        ST_RD_WAIT   = 3'd4,
        ST_CHECK_END = 3'd5
    } state_t;

    state_t       bench_state;
    logic [31:0]  wr_cycle_cnt;       // 写实时耗时周期
    logic [31:0]  wr_latched_cycles;  // 最近一轮写周期数
    logic [31:0]  wr_min_cycles;      // 历史最小写周期数
    logic [31:0]  rd_cycle_cnt;       // 读实时耗时周期
    logic [31:0]  rd_latched_cycles;  // 最近一轮读周期数
    logic [31:0]  rd_min_cycles;      // 历史最小读周期数
    logic [15:0]  test_round;         // 已完成压测轮数
    logic error_flag; // 数据不一致或 AXI 响应出错
    logic [31:0]  error_beat_cnt;     // 数据比对失败拍数

    generate if (!ETHERNET_ENABLE) begin : g_benchmark
    assign axi_reset_n_w = c0_ddr4_aresetn;
    assign error = error_flag;
    assign eth_txc_o = 1'b0;
    assign eth_tx_ctl_o = 1'b0;
    assign eth_txd_o = 4'd0;

    //==========================================================================
    // 零气泡数据生成器与流水线校验器 (Virtual FWFT Infinite FIFO)
    //==========================================================================
    // 数据模式: 第 n 拍第 i 通道 = (seed + n) ^ LANE_C[i], seed = {test_round, 16'h0}
    // 每轮 seed 不同 -> 上一轮残留数据不可能通过本轮校验
    wire [31:0] pat_seed = {test_round, 16'h0000};

    // 写 FIFO: 永不空, 被取走一拍后计数器 +1 (FWFT: 空闲时数据 = 当前拍)
    assign wr_fifo_empty = 1'b0;

    logic [31:0] wr_cnt;

    always_ff @(posedge c0_ddr4_ui_clk or negedge c0_ddr4_aresetn) begin
        if (!c0_ddr4_aresetn) begin
            wr_cnt <= 32'd0;
        end else if (user_wr_start) begin
            wr_cnt <= pat_seed;
        end else if (wr_fifo_re) begin
            wr_cnt <= wr_cnt + 32'd1;
        end
    end

    assign wr_fifo_data = {8{wr_cnt}} ^ LANE_C;

    // 读 FIFO: 永不满; 第 1 级逐通道比较并寄存, 第 2 级汇总计数
    assign rd_fifo_full = 1'b0;

    logic [31:0] rd_cnt;
    logic [7:0]  lane_mis_q;

    always_ff @(posedge c0_ddr4_ui_clk or negedge c0_ddr4_aresetn) begin
        if (!c0_ddr4_aresetn) begin
            rd_cnt         <= 32'd0;
            lane_mis_q     <= 8'd0;
            error_flag     <= 1'b0;
            error_beat_cnt <= 32'd0;
        end else begin
            if (user_rd_start) begin
                rd_cnt <= pat_seed;
            end else if (rd_fifo_we) begin
                rd_cnt <= rd_cnt + 32'd1;
            end

            for (int i = 0; i < 8; i++) begin
                lane_mis_q[i] <= rd_fifo_we &
                                 (rd_fifo_data[32*i +: 32] != (rd_cnt ^ LANE_C[32*i +: 32]));
            end

            if (|lane_mis_q) begin
                error_flag     <= 1'b1;
                error_beat_cnt <= error_beat_cnt + 32'd1;
            end

            // 监听 AXI 总线报错 (BRESP/RRESP 为 SLVERR/DECERR)
            if (user_wr_err || user_rd_err) begin
                error_flag <= 1'b1;
            end
        end
    end

    //==========================================================================
    // 硬件压测跑分主状态机 (自动连续循环压测)
    //==========================================================================
    logic [15:0] delay_cnt;

    always_ff @(posedge c0_ddr4_ui_clk or negedge c0_ddr4_aresetn) begin
        if (!c0_ddr4_aresetn) begin
            bench_state       <= ST_IDLE;
            user_wr_start     <= 1'b0;
            user_wr_addr      <= 31'd0;
            user_wr_len       <= 32'd0;
            user_rd_start     <= 1'b0;
            user_rd_addr      <= 31'd0;
            user_rd_len       <= 32'd0;
            wr_cycle_cnt      <= 32'd0;
            wr_latched_cycles <= 32'd0;
            wr_min_cycles     <= 32'hFFFF_FFFF;
            rd_cycle_cnt      <= 32'd0;
            rd_latched_cycles <= 32'd0;
            rd_min_cycles     <= 32'hFFFF_FFFF;
            test_round        <= 16'd0;
            delay_cnt         <= 16'd0;
        end else begin
            case (bench_state)
                ST_IDLE: begin
                    user_wr_start <= 1'b0;
                    user_rd_start <= 1'b0;
                    // 校准成功释放复位后，等待 256 周期进入连续测试。
                    if (delay_cnt < 16'd256) begin
                        delay_cnt <= delay_cnt + 16'd1;
                    end else if (user_wr_ready && user_rd_ready) begin
                        delay_cnt     <= 16'd0;
                        user_wr_start <= 1'b1;
                        user_wr_addr  <= TEST_START_ADDR;
                        user_wr_len   <= TEST_TOTAL_BYTES;
                        wr_cycle_cnt  <= 32'd0;
                        bench_state   <= ST_WR_RUN;
                    end
                end

                ST_WR_RUN: begin
                    user_wr_start <= 1'b0;
                    wr_cycle_cnt  <= wr_cycle_cnt + 32'd1;
                    bench_state   <= ST_WR_WAIT;
                end

                ST_WR_WAIT: begin
                    wr_cycle_cnt <= wr_cycle_cnt + 32'd1;
                    // 写任务全部落盘完成 (收到最后一个 BVALID)
                    if (user_wr_done) begin
                        wr_latched_cycles <= wr_cycle_cnt;
                        if (wr_cycle_cnt < wr_min_cycles) begin
                            wr_min_cycles <= wr_cycle_cnt;
                        end
                        bench_state <= ST_RD_RUN;
                    end
                end

                ST_RD_RUN: begin
                    user_rd_start <= 1'b1;
                    user_rd_addr  <= TEST_START_ADDR;
                    user_rd_len   <= TEST_TOTAL_BYTES;
                    rd_cycle_cnt  <= 32'd0;
                    bench_state   <= ST_RD_WAIT;
                end

                ST_RD_WAIT: begin
                    user_rd_start <= 1'b0;
                    rd_cycle_cnt  <= rd_cycle_cnt + 32'd1;
                    // 读任务全部接收完成 (收到最后一个 RLAST)
                    if (user_rd_done) begin
                        rd_latched_cycles <= rd_cycle_cnt;
                        if (rd_cycle_cnt < rd_min_cycles) begin
                            rd_min_cycles <= rd_cycle_cnt;
                        end
                        bench_state <= ST_CHECK_END;
                    end
                end

                ST_CHECK_END: begin
                    // 单轮结束后停顿 500 个周期 (让最后几拍比对流水完成), 然后轮数 +1 并进入下一轮
                    if (delay_cnt < 16'd500) begin
                        delay_cnt <= delay_cnt + 16'd1;
                    end else begin
                        delay_cnt   <= 16'd0;
                        test_round  <= test_round + 16'd1;
                        bench_state <= ST_IDLE;
                    end
                end

                default: bench_state <= ST_IDLE;
            endcase
        end
    end

    end else begin : g_ethernet
        logic rx_clk_w, rx_rst_n_w, bridge_rst_n_w;
        logic body_en_w, ready_w, capture_ok_w, packet_submit_w;
        logic packet_done_w, packet_error_w, verify_start_w, verify_done_w, verify_error_w;
        logic [15:0] body_cnt_w;
        logic [7:0] body_data_w;
        logic [30:0] packet_addr_w, image_addr_w;
        logic [31:0] image_bytes_w, verify_crc_w;
        logic storage_error_w;
        (* ASYNC_REG = "TRUE" *) logic bridge_reset_sync1_r, bridge_reset_sync2_r;
        // 时钟失锁/DDR复位共同撤销两端握手；各自时钟域同步释放。
        assign bridge_rst_n_w = c0_ddr4_aresetn && rx_rst_n_w;
        always_ff @(posedge c0_ddr4_ui_clk or negedge bridge_rst_n_w) begin
            if (!bridge_rst_n_w) begin
                bridge_reset_sync1_r <= 1'b0;
                bridge_reset_sync2_r <= 1'b0;
            end else begin
                bridge_reset_sync1_r <= 1'b1;
                bridge_reset_sync2_r <= bridge_reset_sync1_r;
            end
        end
        assign axi_reset_n_w = bridge_reset_sync2_r;
        assign error = storage_error_w;
        // 算子与ROM复用125MHz RX时钟；DDR事务在op_board内跨到UI域。
        logic op_frame_w, op_body_w, op_idle_rx_w, op_image_ready_w, op_accept_w, op_block_w;
        logic op_claim_w, bridge_idle_w, op_select_w, op_tx_start_w, op_tx_req_w, op_tx_done_w;
        logic [7:0] op_msg_w, op_body_data_w, op_tx_data_w;
        logic [15:0] op_body_len_w, op_body_count_w, op_tx_len_w;
        logic [31:0] op_id_w, op_sequence_w, op_image_slices_w;
        logic [30:0] op_image_base_w;
        logic b_wr_start, b_rd_start, b_wr_empty, b_rd_full;
        logic o_wr_start, o_rd_start, o_wr_empty, o_rd_full;
        logic [30:0] b_wr_addr, b_rd_addr, o_wr_addr, o_rd_addr;
        logic [31:0] b_wr_len, b_rd_len, o_wr_len, o_rd_len;
        logic [255:0] b_wr_data, o_wr_data;
        // 所有权先寄存再送DDR握手，隔离CDC pending归约至BRAM写使能。
        always_ff @(posedge c0_ddr4_ui_clk or negedge axi_reset_n_w)
            if (!axi_reset_n_w) op_select_w <= 1'b0;
            else if (!op_claim_w) op_select_w <= 1'b0;
            else if (bridge_idle_w) op_select_w <= 1'b1;
        assign user_wr_start = op_select_w ? o_wr_start : b_wr_start;
        assign user_wr_addr = op_select_w ? o_wr_addr : b_wr_addr;
        assign user_wr_len = op_select_w ? o_wr_len : b_wr_len;
        assign wr_fifo_empty = op_select_w ? o_wr_empty : b_wr_empty;
        assign wr_fifo_data = op_select_w ? o_wr_data : b_wr_data;
        assign user_rd_start = op_select_w ? o_rd_start : b_rd_start;
        assign user_rd_addr = op_select_w ? o_rd_addr : b_rd_addr;
        assign user_rd_len = op_select_w ? o_rd_len : b_rd_len;
        assign rd_fifo_full = op_select_w ? o_rd_full : b_rd_full;
        eth_rgmii_endpoint #(.DDR_ENABLE(1'b1), .OP_ENABLE(1'b1)) u_ethernet (
            .sys_rst_n(sys_rst && c0_ddr4_aresetn),
            .eth_rxc(eth_rxc_i), .eth_rx_ctl(eth_rx_ctl_i), .eth_rxd(eth_rxd_i),
            .eth_txc(eth_txc_o), .eth_tx_ctl(eth_tx_ctl_o), .eth_txd(eth_txd_o),
            .ddr_rx_clk_o(rx_clk_w), .ddr_rx_rst_n_o(rx_rst_n_w),
            .ddr_body_en_o(body_en_w), .ddr_body_cnt_o(body_cnt_w), .ddr_body_data_o(body_data_w),
            .ddr_ready_i(ready_w), .ddr_capture_ok_i(capture_ok_w),
            .ddr_packet_done_i(packet_done_w), .ddr_packet_error_i(packet_error_w),
            .ddr_verify_done_i(verify_done_w), .ddr_verify_error_i(verify_error_w),
            .ddr_verify_crc_i(verify_crc_w), .ddr_packet_submit_o(packet_submit_w),
            .ddr_packet_addr_o(packet_addr_w), .ddr_verify_start_o(verify_start_w),
            .ddr_image_addr_o(image_addr_w), .ddr_image_bytes_o(image_bytes_w),
            .ddr_error_o(storage_error_w),
            .op_frame_valid_o(op_frame_w), .op_msg_o(op_msg_w), .op_id_o(op_id_w), .op_sequence_o(op_sequence_w),
            .op_body_len_o(op_body_len_w), .op_body_en_o(op_body_w), .op_body_count_o(op_body_count_w), .op_body_data_o(op_body_data_w),
            .op_legacy_idle_o(op_idle_rx_w), .op_image_ready_o(op_image_ready_w), .op_image_base_o(op_image_base_w), .op_image_slices_o(op_image_slices_w),
            .op_block_i(op_block_w), .op_accept_i(op_accept_w), .op_tx_start_i(op_tx_start_w), .op_tx_data_i(op_tx_data_w),
            .op_tx_len_i(op_tx_len_w), .op_tx_req_o(op_tx_req_w), .op_tx_done_o(op_tx_done_w)
        );
        ethernet_ddr_bridge u_bridge (
            .block_rx_i(op_block_w), .grant_ui_i(!op_select_w), .idle_ui_o(bridge_idle_w),
            .rx_clk_i(rx_clk_w), .ui_clk_i(c0_ddr4_ui_clk),
            .rx_rst_n_i(rx_rst_n_w), .ui_rst_n_i(bridge_reset_sync2_r),
            .body_en_i(body_en_w), .body_cnt_i(body_cnt_w), .body_data_i(body_data_w),
            .packet_submit_i(packet_submit_w), .packet_addr_i(packet_addr_w),
            .verify_start_i(verify_start_w), .image_addr_i(image_addr_w),
            .image_bytes_i(image_bytes_w), .ready_o(ready_w), .capture_ok_o(capture_ok_w),
            .packet_done_o(packet_done_w), .packet_error_o(packet_error_w),
            .verify_done_o(verify_done_w), .verify_error_o(verify_error_w),
            .verify_crc_o(verify_crc_w),
            .wr_start_o(b_wr_start), .wr_addr_o(b_wr_addr), .wr_len_o(b_wr_len),
            .wr_ready_i(user_wr_ready && !op_select_w), .wr_done_i(user_wr_done && !op_select_w), .wr_error_i(user_wr_err && !op_select_w),
            .wr_fifo_re_i(wr_fifo_re && !op_select_w), .wr_fifo_empty_o(b_wr_empty), .wr_fifo_data_o(b_wr_data),
            .rd_start_o(b_rd_start), .rd_addr_o(b_rd_addr), .rd_len_o(b_rd_len),
            .rd_ready_i(user_rd_ready && !op_select_w), .rd_done_i(user_rd_done && !op_select_w), .rd_error_i(user_rd_err && !op_select_w),
            .rd_fifo_we_i(rd_fifo_we && !op_select_w), .rd_fifo_data_i(rd_fifo_data), .rd_fifo_full_o(b_rd_full)
        );
        // airway/lobe/vessel 参数来自缩短后的 ROM；tumor 参数由 Ethernet WRITE 上传到 DDR，
        // 特征和结果继续沿用已验证 DDR 链路。
        logic coeff_req_valid_w, coeff_req_ready_w, coeff_rsp_valid_w, coeff_rsp_ready_w, coeff_rsp_error_w;
        logic [30:0] coeff_req_addr_w;
        logic [255:0] coeff_rsp_data_w;
        logic op_compute_rst_n_w;
        wire op_compute_250_w, op_compute_125_w, op_compute_locked_w;
        wire op_compute_clk_w = COMPUTE_250MHZ ? op_compute_250_w : op_compute_125_w;
        // 使用MIG稳定UI时钟作为参考，计算时钟不再依赖PHY接收时钟。
        op_compute_clk_wiz u_compute_clock (
            .clk_in1(c0_ddr4_ui_clk), .resetn(c0_ddr4_aresetn),
            .clk_out1(op_compute_250_w), .clk_out2(op_compute_125_w), .locked(op_compute_locked_w)
        );
        op_coeff_rom u_coeff_rom (
            .clk_i(op_compute_clk_w), .rst_n_i(op_compute_rst_n_w),
            .req_valid_i(coeff_req_valid_w), .req_ready_o(coeff_req_ready_w), .req_addr_i(coeff_req_addr_w),
            .rsp_valid_o(coeff_rsp_valid_w), .rsp_ready_i(coeff_rsp_ready_w),
            .rsp_data_o(coeff_rsp_data_w), .rsp_error_o(coeff_rsp_error_w)
        );
        op_board #(.COMPUTE_HZ(COMPUTE_250MHZ ? 32'd250000000 : 32'd125000000)) u_op_board (
            .rx_clk_i(rx_clk_w), .rx_rst_n_i(rx_rst_n_w), .ui_clk_i(c0_ddr4_ui_clk), .ui_rst_n_i(bridge_reset_sync2_r),
            .compute_clk_i(op_compute_clk_w), .compute_locked_i(op_compute_locked_w),
            .compute_rst_n_o(op_compute_rst_n_w),
            .legacy_idle_rx_i(op_idle_rx_w), .storage_idle_ui_i(bridge_idle_w),
            .image_ready_rx_i(op_image_ready_w), .image_base_rx_i(op_image_base_w), .image_slices_rx_i(op_image_slices_w),
            .frame_valid_i(op_frame_w), .msg_i(op_msg_w), .id_i(op_id_w), .sequence_i(op_sequence_w),
            .body_len_i(op_body_len_w), .body_en_i(op_body_w), .body_count_i(op_body_count_w), .body_data_i(op_body_data_w),
            .accept_o(op_accept_w), .block_rx_o(op_block_w), .claim_ui_o(op_claim_w),
            .tx_start_o(op_tx_start_w), .tx_data_o(op_tx_data_w), .tx_len_o(op_tx_len_w), .tx_req_i(op_tx_req_w), .tx_done_i(op_tx_done_w),
            .wr_start_o(o_wr_start), .wr_addr_o(o_wr_addr), .wr_len_o(o_wr_len),
            .wr_ready_i(user_wr_ready && op_select_w), .wr_done_i(user_wr_done && op_select_w), .wr_error_i(user_wr_err),
            .wr_fifo_re_i(wr_fifo_re && op_select_w), .wr_fifo_empty_o(o_wr_empty), .wr_fifo_data_o(o_wr_data),
            .rd_start_o(o_rd_start), .rd_addr_o(o_rd_addr), .rd_len_o(o_rd_len),
            .rd_ready_i(user_rd_ready && op_select_w), .rd_done_i(user_rd_done && op_select_w), .rd_error_i(user_rd_err),
            .rd_fifo_we_i(rd_fifo_we && op_select_w), .rd_fifo_data_i(rd_fifo_data), .rd_fifo_full_o(o_rd_full),
            .coeff_req_valid_o(coeff_req_valid_w), .coeff_req_ready_i(coeff_req_ready_w),
            .coeff_req_addr_o(coeff_req_addr_w), .coeff_rsp_valid_i(coeff_rsp_valid_w),
            .coeff_rsp_ready_o(coeff_rsp_ready_w), .coeff_rsp_data_i(coeff_rsp_data_w),
            .coeff_rsp_error_i(coeff_rsp_error_w)
        );

    end endgenerate

    //==========================================================================
    // 实例化 AXI4 Master 高性能控制器 (V3.0: 256-bit, 4KB切片, 8在途流水)
    //==========================================================================
    aq_axi_master #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .MAX_OUT_WR     (8),
        .MAX_OUT_RD     (8)
    ) u_axi_master (
        .ARESETN        (axi_reset_n_w),
        .ACLK           (c0_ddr4_ui_clk),

        // AXI4 Write Address
        .M_AXI_AWID     (axi_awid),
        .M_AXI_AWADDR   (axi_awaddr),
        .M_AXI_AWLEN    (axi_awlen),
        .M_AXI_AWSIZE   (axi_awsize),
        .M_AXI_AWBURST  (axi_awburst),
        .M_AXI_AWLOCK   (axi_awlock),
        .M_AXI_AWCACHE  (axi_awcache),
        .M_AXI_AWPROT   (axi_awprot),
        .M_AXI_AWQOS    (axi_awqos),
        .M_AXI_AWUSER   (axi_awuser),
        .M_AXI_AWVALID  (axi_awvalid),
        .M_AXI_AWREADY  (axi_awready),

        // AXI4 Write Data
        .M_AXI_WDATA    (axi_wdata),
        .M_AXI_WSTRB    (axi_wstrb),
        .M_AXI_WLAST    (axi_wlast),
        .M_AXI_WUSER    (axi_wuser),
        .M_AXI_WVALID   (axi_wvalid),
        .M_AXI_WREADY   (axi_wready),

        // AXI4 Write Response
        .M_AXI_BID      (axi_bid),
        .M_AXI_BRESP    (axi_bresp),
        .M_AXI_BUSER    (axi_buser),
        .M_AXI_BVALID   (axi_bvalid),
        .M_AXI_BREADY   (axi_bready),

        // AXI4 Read Address
        .M_AXI_ARID     (axi_arid),
        .M_AXI_ARADDR   (axi_araddr),
        .M_AXI_ARLEN    (axi_arlen),
        .M_AXI_ARSIZE   (axi_arsize),
        .M_AXI_ARBURST  (axi_arburst),
        .M_AXI_ARLOCK   (axi_arlock),
        .M_AXI_ARCACHE  (axi_arcache),
        .M_AXI_ARPROT   (axi_arprot),
        .M_AXI_ARQOS    (axi_arqos),
        .M_AXI_ARUSER   (axi_aruser),
        .M_AXI_ARVALID  (axi_arvalid),
        .M_AXI_ARREADY  (axi_arready),

        // AXI4 Read Data
        .M_AXI_RID      (axi_rid),
        .M_AXI_RDATA    (axi_rdata),
        .M_AXI_RRESP    (axi_rresp),
        .M_AXI_RLAST    (axi_rlast),
        .M_AXI_RUSER    (axi_ruser),
        .M_AXI_RVALID   (axi_rvalid),
        .M_AXI_RREADY   (axi_rready),

        // Local Bus (用户控制与 FIFO 接口)
        .MASTER_RST     (1'b0),
        .WR_START       (user_wr_start),
        .WR_ADRS        (user_wr_addr),
        .WR_LEN         (user_wr_len),
        .WR_READY       (user_wr_ready),
        .WR_FIFO_RE     (wr_fifo_re),
        .WR_FIFO_EMPTY  (wr_fifo_empty),
        .WR_FIFO_DATA   (wr_fifo_data),
        .WR_DONE        (user_wr_done),
        .WR_ERR         (user_wr_err),

        .RD_START       (user_rd_start),
        .RD_ADRS        (user_rd_addr),
        .RD_LEN         (user_rd_len),
        .RD_READY       (user_rd_ready),
        .RD_FIFO_WE     (rd_fifo_we),
        .RD_FIFO_FULL   (rd_fifo_full),
        .RD_FIFO_DATA   (rd_fifo_data),
        .RD_DONE        (user_rd_done),
        .RD_ERR         (user_rd_err),

        .DEBUG          ()
    );

    //==========================================================================
    // 实例化 Xilinx DDR4 MIG 控制器 IP
    //==========================================================================
    ddr4_0 u_ddr4 (
        .sys_rst                    (~sys_rst),               // 按键低有效转 MIG 高有效
        .c0_sys_clk_p               (c0_sys_clk_p),
        .c0_sys_clk_n               (c0_sys_clk_n),
        .c0_init_calib_complete     (calib_complete_w),

        // DDR4 物理引脚
        .c0_ddr4_act_n              (c0_ddr4_act_n),
        .c0_ddr4_adr                (c0_ddr4_adr),
        .c0_ddr4_ba                 (c0_ddr4_ba),
        .c0_ddr4_bg                 (c0_ddr4_bg),
        .c0_ddr4_cke                (c0_ddr4_cke),
        .c0_ddr4_odt                (c0_ddr4_odt),
        .c0_ddr4_cs_n               (c0_ddr4_cs_n),
        .c0_ddr4_ck_t               (c0_ddr4_ck_t),
        .c0_ddr4_ck_c               (c0_ddr4_ck_c),
        .c0_ddr4_reset_n            (c0_ddr4_reset_n),
        .c0_ddr4_dm_dbi_n           (c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq                 (c0_ddr4_dq),
        .c0_ddr4_dqs_t              (c0_ddr4_dqs_t),
        .c0_ddr4_dqs_c              (c0_ddr4_dqs_c),

        // 用户接口时钟与复位
        .c0_ddr4_ui_clk             (c0_ddr4_ui_clk),
        .c0_ddr4_ui_clk_sync_rst    (c0_ddr4_ui_clk_sync_rst),
        .c0_ddr4_aresetn            (axi_reset_n_w),

        // AXI4 从机端口对接
        .c0_ddr4_s_axi_awid         (mig_awid),
        .c0_ddr4_s_axi_awaddr       (axi_awaddr),
        .c0_ddr4_s_axi_awlen        (axi_awlen),
        .c0_ddr4_s_axi_awsize       (axi_awsize),
        .c0_ddr4_s_axi_awburst      (axi_awburst),
        .c0_ddr4_s_axi_awlock       (axi_awlock),
        .c0_ddr4_s_axi_awcache      (axi_awcache),
        .c0_ddr4_s_axi_awprot       (axi_awprot),
        .c0_ddr4_s_axi_awqos        (axi_awqos),
        .c0_ddr4_s_axi_awvalid      (axi_awvalid),
        .c0_ddr4_s_axi_awready      (axi_awready),

        .c0_ddr4_s_axi_wdata        (axi_wdata),
        .c0_ddr4_s_axi_wstrb        (axi_wstrb),
        .c0_ddr4_s_axi_wlast        (axi_wlast),
        .c0_ddr4_s_axi_wvalid       (axi_wvalid),
        .c0_ddr4_s_axi_wready       (axi_wready),

        .c0_ddr4_s_axi_bready       (axi_bready),
        .c0_ddr4_s_axi_bid          (mig_bid),
        .c0_ddr4_s_axi_bresp        (axi_bresp),
        .c0_ddr4_s_axi_bvalid       (axi_bvalid),

        .c0_ddr4_s_axi_arid         (mig_arid),
        .c0_ddr4_s_axi_araddr       (axi_araddr),
        .c0_ddr4_s_axi_arlen        (axi_arlen),
        .c0_ddr4_s_axi_arsize       (axi_arsize),
        .c0_ddr4_s_axi_arburst      (axi_arburst),
        .c0_ddr4_s_axi_arlock       (axi_arlock),
        .c0_ddr4_s_axi_arcache      (axi_arcache),
        .c0_ddr4_s_axi_arprot       (axi_arprot),
        .c0_ddr4_s_axi_arqos        (axi_arqos),
        .c0_ddr4_s_axi_arvalid      (axi_arvalid),
        .c0_ddr4_s_axi_arready      (axi_arready),

        .c0_ddr4_s_axi_rready       (axi_rready),
        .c0_ddr4_s_axi_rlast        (axi_rlast),
        .c0_ddr4_s_axi_rvalid       (axi_rvalid),
        .c0_ddr4_s_axi_rresp        (axi_rresp),
        .c0_ddr4_s_axi_rid          (mig_rid),
        .c0_ddr4_s_axi_rdata        (axi_rdata)
    );

endmodule
