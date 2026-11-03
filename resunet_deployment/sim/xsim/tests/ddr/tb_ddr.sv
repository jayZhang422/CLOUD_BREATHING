`timescale 1ps / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/10/03
// Design Name: DDR4 256-bit 极限吞吐性能测试平台
// Module Name: tb_ddr
// Project Name: Model_Deployment
// Target Devices: xcku5p-ffvb676-2-i
// Tool Versions: Vivado 2023.1
// Description:
//   1. 例化 top.sv 压测顶层 (含 256-bit V3.0 AXI Master 与 DDR4 MIG)
//   2. 例化 2 颗 Micron MT40A512M16 仿真模型 (构成 32-bit DQ 物理总线)
//   3. 自动生成 200MHz 差分参考时钟与复位时序
//   4. 实时监控初始化校准、读写状态机跳变、吞吐率换算与数据完整性校验
//////////////////////////////////////////////////////////////////////////////////

`ifdef XILINX_SIMULATOR
module short(in1, in1);
inout in1;
endmodule
`endif

`include "arch_package.sv"
`include "proj_package.sv"
`include "interface.sv"
`include "ddr4_model.sv"

module tb_ddr;

    //==========================================================================
    // DDR4 颗粒与模型参数配置 (2 颗 16-bit DDR4 颗粒 = 32-bit DQ)
    //==========================================================================
    localparam ADDR_WIDTH          = 17;
    localparam DQ_WIDTH            = 32;
    localparam DQS_WIDTH           = 4;
    localparam DM_WIDTH            = 4;
    localparam DRAM_WIDTH          = 16;
    localparam NUM_PHYSICAL_PARTS  = (DQ_WIDTH / DRAM_WIDTH); // 2 颗
    localparam RANK_WIDTH          = 1;
    localparam CS_WIDTH            = 1;
    localparam ODT_WIDTH           = 1;
    localparam CA_MIRROR           = "OFF";

    import arch_package::*;
    parameter UTYPE_density CONFIGURED_DENSITY = _8G;

    // 仿真测试数据量 (默认为 16KB = 512 拍 256-bit 数据，跨越 4 个 4KB 边界与多轮 Burst 流水)
    // 快速在 1~2 分钟内跑完全流程；若需测更大规模可按需修改
    localparam bit [31:0] SIM_TEST_BYTES = 32'd16384; 
    localparam bit [30:0] SIM_START_ADDR = 31'h0000_0000;

    // DDR4 命令编码 (供波形窗口直观显示总线命令)
    localparam MRS = 3'b000;
    localparam REF = 3'b001;
    localparam PRE = 3'b010;
    localparam ACT = 3'b011;
    localparam WR  = 3'b100;
    localparam RD  = 3'b101;
    localparam ZQC = 3'b110;
    localparam NOP = 3'b111;

    //==========================================================================
    // 信号声明
    //==========================================================================
    reg                  sys_clk_i;
    reg                  sys_rst;

    wire                 c0_sys_clk_p;
    wire                 c0_sys_clk_n;
    wire                 c0_init_calib_complete;
    wire                 error;

    wire                 c0_ddr4_act_n;
    wire [16:0]          c0_ddr4_adr;
    wire [1:0]           c0_ddr4_ba;
    wire [0:0]           c0_ddr4_bg;
    wire [0:0]           c0_ddr4_cke;
    wire [0:0]           c0_ddr4_odt;
    wire [0:0]           c0_ddr4_cs_n;
    wire [0:0]           c0_ddr4_ck_t;
    wire [0:0]           c0_ddr4_ck_c;
    wire                 c0_ddr4_reset_n;
    wire [3:0]           c0_ddr4_dm_dbi_n;
    wire [31:0]          c0_ddr4_dq;
    wire [3:0]           c0_ddr4_dqs_t;
    wire [3:0]           c0_ddr4_dqs_c;

    reg  [16:0]          c0_ddr4_adr_sdram[1:0];
    reg  [1:0]           c0_ddr4_ba_sdram[1:0];
    reg  [0:0]           c0_ddr4_bg_sdram[1:0];

    bit                  en_model;
    tri                  model_enable = en_model;

    //==========================================================================
    // 时钟与复位驱动
    //==========================================================================
    // 200MHz 差分参考时钟 (周期 5000ps)
    initial sys_clk_i = 1'b0;
    always #(5000 / 2.0) sys_clk_i = ~sys_clk_i;

    assign c0_sys_clk_p = sys_clk_i;
    assign c0_sys_clk_n = ~sys_clk_i;

    // 外部低电平复位脉冲时序 (对应板载 K9 按键)
    initial begin
        sys_rst  = 1'b1;
        en_model = 1'b0;
        #20000;          // 20 ns
        sys_rst  = 1'b0; // 按下按键，产生复位
        #5000;
        en_model = 1'b1; // 使能 Micron SDRAM 模型
        #200000;         // 保持复位 200 ns (40 个参考时钟周期)
        sys_rst  = 1'b1; // 释放按键，复位解除
    end

    //==========================================================================
    // 地址与命令解码 (供波形直观监视)
    //==========================================================================
    always @(*) begin
        c0_ddr4_adr_sdram[0] = c0_ddr4_adr;
        c0_ddr4_adr_sdram[1] = (CA_MIRROR == "ON") ?
            {c0_ddr4_adr[ADDR_WIDTH-1:14],
             c0_ddr4_adr[11], c0_ddr4_adr[12],
             c0_ddr4_adr[13], c0_ddr4_adr[10:9],
             c0_ddr4_adr[7],  c0_ddr4_adr[8],
             c0_ddr4_adr[5],  c0_ddr4_adr[6],
             c0_ddr4_adr[3],  c0_ddr4_adr[4],
             c0_ddr4_adr[2:0]} : c0_ddr4_adr;
        c0_ddr4_ba_sdram[0]  = c0_ddr4_ba;
        c0_ddr4_ba_sdram[1]  = (CA_MIRROR == "ON") ? {c0_ddr4_ba[0], c0_ddr4_ba[1]} : c0_ddr4_ba;
        c0_ddr4_bg_sdram[0]  = c0_ddr4_bg;
        c0_ddr4_bg_sdram[1]  = c0_ddr4_bg;
    end

    reg [ADDR_WIDTH-1:0] DDR4_ADRMOD[RANK_WIDTH-1:0];
    genvar rnk;
    generate
        for (rnk = 0; rnk < CS_WIDTH; rnk++) begin: rankup
            always @(*) begin
                if (c0_ddr4_act_n) begin
                    casez (c0_ddr4_adr_sdram[0][16:14])
                        WR, RD:  DDR4_ADRMOD[rnk] = c0_ddr4_adr_sdram[rnk] & 18'h1C7FF;
                        default: DDR4_ADRMOD[rnk] = c0_ddr4_adr_sdram[rnk];
                    endcase
                end else begin
                    DDR4_ADRMOD[rnk] = c0_ddr4_adr_sdram[rnk];
                end
            end
        end
    endgenerate

    reg [63:0] ddr4_cmd_name;
    always @(*) begin
        if (c0_ddr4_cs_n[0])
            ddr4_cmd_name = "DESEL";
        else if (c0_ddr4_act_n) begin
            casez (DDR4_ADRMOD[0][16:14])
                MRS:     ddr4_cmd_name = "MRS";
                REF:     ddr4_cmd_name = "REF";
                PRE:     ddr4_cmd_name = "PRE";
                WR:      ddr4_cmd_name = "WR";
                RD:      ddr4_cmd_name = "RD";
                ZQC:     ddr4_cmd_name = "ZQC";
                NOP:     ddr4_cmd_name = "NOP";
                default: ddr4_cmd_name = "***";
            endcase
        end else begin
            ddr4_cmd_name = "ACT";
        end
    end

    //==========================================================================
    // 实例化 Micron DDR4 颗粒模型 (2 颗 16-bit 组成 32-bit 总线)
    //==========================================================================
    genvar r, i, s;
    generate
        DDR4_if #(.CONFIGURED_DQ_BITS(16)) iDDR4[0:(RANK_WIDTH * NUM_PHYSICAL_PARTS) - 1]();

        for (r = 0; r < RANK_WIDTH; r++) begin: memModels_Ri2
            for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin: memModel2
                ddr4_model #(
                    .CONFIGURED_DQ_BITS(16),
                    .CONFIGURED_DENSITY(CONFIGURED_DENSITY)
                ) u_ddr4_model (
                    .model_enable(model_enable),
                    .iDDR4       (iDDR4[(r * NUM_PHYSICAL_PARTS) + i])
                );
            end
        end

        // DQ 物理双向总线映射
        for (r = 0; r < RANK_WIDTH; r++) begin: tranDQ3
            for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin: tranDQ13
                for (s = 0; s < 16; s++) begin: tranDQ2
                    `ifdef XILINX_SIMULATOR
                    short bidiDQ(iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQ[s], c0_ddr4_dq[s + i * 16]);
                    `else
                    tran  bidiDQ(iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQ[s], c0_ddr4_dq[s + i * 16]);
                    `endif
                end
            end
        end

        // DQS / DM 物理双向总线映射
        for (r = 0; r < RANK_WIDTH; r++) begin: tranDQS3
            for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin: tranDQS13
                `ifdef XILINX_SIMULATOR
                short bidiDQS0 (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_t[0], c0_ddr4_dqs_t[(2 * i)]);
                short bidiDQS0_(iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_c[0], c0_ddr4_dqs_c[(2 * i)]);
                short bidiDM0  (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DM_n[0],  c0_ddr4_dm_dbi_n[(2 * i)]);
                short bidiDQS1 (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_t[1], c0_ddr4_dqs_t[((2 * i) + 1)]);
                short bidiDQS1_(iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_c[1], c0_ddr4_dqs_c[((2 * i) + 1)]);
                short bidiDM1  (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DM_n[1],  c0_ddr4_dm_dbi_n[((2 * i) + 1)]);
                `else
                tran  bidiDQS0 (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_t[0], c0_ddr4_dqs_t[(2 * i)]);
                tran  bidiDQS0_(iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_c[0], c0_ddr4_dqs_c[(2 * i)]);
                tran  bidiDM0  (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DM_n[0],  c0_ddr4_dm_dbi_n[(2 * i)]);
                tran  bidiDQS1 (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_t[1], c0_ddr4_dqs_t[((2 * i) + 1)]);
                tran  bidiDQS1_(iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DQS_c[1], c0_ddr4_dqs_c[((2 * i) + 1)]);
                tran  bidiDM1  (iDDR4[(r * NUM_PHYSICAL_PARTS) + i].DM_n[1],  c0_ddr4_dm_dbi_n[((2 * i) + 1)]);
                `endif
            end
        end

        // 控制与地址总线映射
        for (r = 0; r < RANK_WIDTH; r++) begin: tranADCTL_RANKS
            for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin: tranADCTL
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].BG      = c0_ddr4_bg_sdram[r];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].BA      = c0_ddr4_ba_sdram[r];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].ADDR_17 = (ADDR_WIDTH == 18) ? DDR4_ADRMOD[r][ADDR_WIDTH-1] : 1'b0;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].ADDR    = DDR4_ADRMOD[r][13:0];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].CS_n    = c0_ddr4_cs_n[r];
            end
        end

        for (r = 0; r < RANK_WIDTH; r++) begin: tranADCTL_RANKS1
            for (i = 0; i < NUM_PHYSICAL_PARTS; i++) begin: tranADCTL1
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].CK         = {c0_ddr4_ck_t[0], c0_ddr4_ck_c[0]};
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].ACT_n      = c0_ddr4_act_n;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].RAS_n_A16  = DDR4_ADRMOD[r][16];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].CAS_n_A15  = DDR4_ADRMOD[r][15];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].WE_n_A14   = DDR4_ADRMOD[r][14];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].CKE        = c0_ddr4_cke[r];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].ODT        = c0_ddr4_odt[r];
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].PARITY     = 1'b0;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].TEN        = 1'b0;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].ZQ         = 1'b1;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].PWR        = 1'b1;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].VREF_CA    = 1'b1;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].VREF_DQ    = 1'b1;
                assign iDDR4[(r * NUM_PHYSICAL_PARTS) + i].RESET_n    = c0_ddr4_reset_n;
            end
        end
    endgenerate

    //==========================================================================
    // 实例化待测顶层模块 top.sv
    //==========================================================================
    top #(
        .ETHERNET_ENABLE (1'b0),
        .TEST_TOTAL_BYTES (SIM_TEST_BYTES), // 仿真模式: 16 KB (512 拍 256-bit 数据)
        .TEST_START_ADDR  (SIM_START_ADDR)
    ) u_top (
        .c0_ddr4_act_n          (c0_ddr4_act_n),
        .c0_ddr4_adr            (c0_ddr4_adr),
        .c0_ddr4_ba             (c0_ddr4_ba),
        .c0_ddr4_bg             (c0_ddr4_bg),
        .c0_ddr4_cke            (c0_ddr4_cke),
        .c0_ddr4_odt            (c0_ddr4_odt),
        .c0_ddr4_cs_n           (c0_ddr4_cs_n),
        .c0_ddr4_ck_t           (c0_ddr4_ck_t),
        .c0_ddr4_ck_c           (c0_ddr4_ck_c),
        .c0_ddr4_reset_n        (c0_ddr4_reset_n),
        .c0_ddr4_dm_dbi_n       (c0_ddr4_dm_dbi_n),
        .c0_ddr4_dq             (c0_ddr4_dq),
        .c0_ddr4_dqs_t          (c0_ddr4_dqs_t),
        .c0_ddr4_dqs_c          (c0_ddr4_dqs_c),

        .c0_sys_clk_p           (c0_sys_clk_p),
        .c0_sys_clk_n           (c0_sys_clk_n),
        .c0_init_calib_complete (c0_init_calib_complete),
        .error                  (error),
        .sys_rst                (sys_rst)
    );

    //==========================================================================
    // 自动化监测、吞吐率换算与判决打印进程
    //==========================================================================
    real clk_period_ns;
    real total_beats;
    localparam int NUM_ROUNDS = 3;      // 观测轮数
    integer rnd;

    initial begin
        clk_period_ns = 3.0; // c0_ddr4_ui_clk @ 333.33MHz = 3.0ns
        total_beats   = real'(SIM_TEST_BYTES) / 32.0; // 256-bit = 32 字节/拍

        $display("\n================================================================================");
        $display("   [TB_DDR] Kintex UltraScale+ DDR4 256-bit Throughput Benchmark Started");
        $display("   [TB_DDR] Target Device : xcku5p-ffvb676-2-i");
        $display("   [TB_DDR] Physical DQ   : 32-bit (2x MT40A512M16HA @ 2666 MT/s)");
        $display("   [TB_DDR] UI Clock      : 333.33 MHz (AXI Bus Data Width = 256-bit)");
        $display("   [TB_DDR] Test Size     : %0d Bytes (%0d Beats @ 256-bit)", SIM_TEST_BYTES, int'(total_beats));
        $display("   [TB_DDR] Theoretical Peak Bandwidth: 10.667 GB/s");
        $display("================================================================================\n");

        // 1. 等待 MIG 初始化校准完成
        $display("[%0t ps] Waiting for DDR4 MIG Calibration (c0_init_calib_complete)...", $time);
        fork
            begin
                wait(c0_init_calib_complete === 1'b1);
                $display("\n[%0t ps] >>> SUCCESS: DDR4 MIG Calibration Completed! (c0_init_calib_complete = 1)", $time);
            end
            begin
                #1_000_000_000; // 1 ms 超时看门狗
                $display("\n[%0t ps] >>> ERROR: Timeout waiting for c0_init_calib_complete!", $time);
                $finish;
            end
        join_any
        disable fork;

        // 2. 连续观测 NUM_ROUNDS 轮 (多轮才能暴露"上一轮残留数据蒙混过关"和轮计数类问题)
        for (rnd = 0; rnd < NUM_ROUNDS; rnd++) begin
            wait(u_top.bench_state == 3'd1);   // ST_WR_RUN
            $display("[%0t ps] >>> Round %0d Phase 1: Full-Speed Write Initiated...", $time, rnd);

            wait(u_top.bench_state == 3'd3);   // ST_RD_RUN: 写阶段结束, wr_latched_cycles 已锁存
            #1;
            report_phase("WRITE", u_top.wr_latched_cycles, u_top.wr_min_cycles);

            wait(u_top.bench_state == 3'd5);   // ST_CHECK_END: 读阶段结束, rd_latched_cycles 已锁存
            #1;
            report_phase("READ ", u_top.rd_latched_cycles, u_top.rd_min_cycles);
        end

        // 3. 等待最后一轮停顿结束 (test_round 在此时 +1), 然后判决
        wait(u_top.bench_state == 3'd0);
        #1000;

        $display("================================================================================");
        $display("   test_round = %0d (期望 %0d), error_beat_cnt = %0d, error_flag = %b, error pin = %b",
                 u_top.test_round, NUM_ROUNDS, u_top.error_beat_cnt, u_top.error_flag, error);
        if (error === 1'b0 && u_top.error_flag === 1'b0 && u_top.error_beat_cnt === 0 &&
            u_top.test_round === NUM_ROUNDS[15:0]) begin
            $display("   >>> ALL %0d BEATS x %0d ROUNDS VERIFIED! 0 MISMATCHES! <<<", int'(total_beats), NUM_ROUNDS);
            $display("   >>> [TEST STATUS: PASSED] DDR4 256-bit Pipeline Architecture Verified! <<<");
        end else begin
            $display("   >>> [TEST STATUS: FAILED] Error Beats = %0d, rounds = %0d <<<",
                     u_top.error_beat_cnt, u_top.test_round);
        end
        $display("================================================================================");

        #50000;
        $finish;
    end

    // 总看门狗: 防止仿真卡死
    initial begin
        #2_000_000_000; // 2 ms
        $display("\n[%0t ps] >>> [TEST STATUS: FAILED] global watchdog timeout, bench_state = %0d", $time, u_top.bench_state);
        $finish;
    end

    // 单阶段结果打印: cycles 为最近一轮, min_cycles 为历史最小
    task automatic report_phase(input string name, input [31:0] cycles, input [31:0] min_cycles);
        real bw, eff, bw_min;
        begin
            bw     = (cycles == 0) ? 0.0 : (real'(SIM_TEST_BYTES) / (real'(cycles) * clk_period_ns * 1.0e-9)) / 1.0e9;
            bw_min = (min_cycles == 0 || min_cycles == 32'hFFFF_FFFF) ? 0.0 :
                     (real'(SIM_TEST_BYTES) / (real'(min_cycles) * clk_period_ns * 1.0e-9)) / 1.0e9;
            eff    = (cycles == 0) ? 0.0 : (total_beats / real'(cycles)) * 100.0;
            $display("[%0t ps] %s: %0d bytes, %0d cycles, %0.3f GB/s (bus eff %0.2f %%), best-so-far %0d cycles = %0.3f GB/s",
                     $time, name, SIM_TEST_BYTES, cycles, bw, eff, min_cycles, bw_min);
        end
    endtask

endmodule
