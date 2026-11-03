/*------------------------------------------------------------------------------
Function: aq_axi_master V3.0 独立测试顶层 (Verilator, 由 sim_main.cpp 驱动时钟/复位)
  测试表 (见 f_* 函数): 地址 / 长度 / 随机停顿强度 / 是否读写并发
   T0  4KB 对齐单突发 128 拍              无停顿
   T1  64KB 多突发 (吞吐测试)              无停顿
   T2  起点距 4KB 边界 128B, 300 拍        无停顿   (4 + 128 + 128 + 40 拍, 验证 4KB 拆分)
   T3  单拍 32B                           无停顿
   T4  8KB 对齐 (2 个满突发)               无停顿
   T5  64KB                               随机停顿 96/256
   T6  同 T2                              随机停顿 96/256
   T7  单拍                               随机停顿 96/256
   T8  16KB                               随机停顿 200/256 (重度停顿)
   T9  读写并发: 写新区域同时读 T1 写过的区域   随机停顿 64/256
   T10 长度 0                             无停顿   (不应产生任何 AXI 事务)
  随机停顿同时作用于: 从机 AWREADY/WREADY/ARREADY/RVALID, 用户写 FIFO 的 EMPTY, 用户读 FIFO 的 FULL
Author: AI Assistant
Date: 2026-10-03
------------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module tb_aq_axi_master
#(
  parameter AXI_ADDR_WIDTH = 32,
  parameter AXI_DATA_WIDTH = 256
)
(
  input  wire        clk,
  input  wire        rst_n,
  output reg         test_done,
  output reg         test_pass,
  output reg  [31:0] err_count,
  output reg  [7:0]  cur_test,
  output wire [15:0] slave_flags,
  output wire [31:0] slave_err
);

  localparam AXI_BYTES = AXI_DATA_WIDTH / 8;   // 32
  localparam NTESTS    = 11;

  // AXI 互连信号
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
  wire [AXI_BYTES-1:0]       axi_wstrb;
  wire                       axi_wlast;
  wire [0:0]                 axi_wuser;
  wire                       axi_wvalid;
  wire                       axi_wready;

  wire [0:0]                 axi_bid;
  wire [1:0]                 axi_bresp;
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
  wire                       axi_rvalid;
  wire                       axi_rready;

  // Local Bus
  reg                        wr_start;
  reg [AXI_ADDR_WIDTH-1:0]   wr_adrs;
  reg [31:0]                 wr_len;
  wire                       wr_ready;
  wire                       wr_fifo_re;
  wire                       wr_done;
  wire                       dut_wr_err;
  wire [AXI_DATA_WIDTH-1:0]  wr_fifo_data;
  reg                        wr_empty;

  reg                        rd_start;
  reg [AXI_ADDR_WIDTH-1:0]   rd_adrs;
  reg [31:0]                 rd_len;
  wire                       rd_ready;
  wire                       rd_fifo_we;
  wire [AXI_DATA_WIDTH-1:0]  rd_fifo_data;
  wire                       rd_done;
  wire                       dut_rd_err;
  reg                        rd_full;

  reg [7:0]                  stall_thr;

  //--------------------------------------------------------------------
  // DUT
  //--------------------------------------------------------------------
  aq_axi_master #(
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .MAX_OUT_WR     (8),
    .MAX_OUT_RD     (8)
  ) u_dut (
    .ARESETN        (rst_n),
    .ACLK           (clk),

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

    .M_AXI_WDATA    (axi_wdata),
    .M_AXI_WSTRB    (axi_wstrb),
    .M_AXI_WLAST    (axi_wlast),
    .M_AXI_WUSER    (axi_wuser),
    .M_AXI_WVALID   (axi_wvalid),
    .M_AXI_WREADY   (axi_wready),

    .M_AXI_BID      (axi_bid),
    .M_AXI_BRESP    (axi_bresp),
    .M_AXI_BUSER    (1'b0),
    .M_AXI_BVALID   (axi_bvalid),
    .M_AXI_BREADY   (axi_bready),

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

    .M_AXI_RID      (axi_rid),
    .M_AXI_RDATA    (axi_rdata),
    .M_AXI_RRESP    (axi_rresp),
    .M_AXI_RLAST    (axi_rlast),
    .M_AXI_RUSER    (1'b0),
    .M_AXI_RVALID   (axi_rvalid),
    .M_AXI_RREADY   (axi_rready),

    .MASTER_RST     (1'b0),
    .WR_START       (wr_start),
    .WR_ADRS        (wr_adrs),
    .WR_LEN         (wr_len),
    .WR_READY       (wr_ready),
    .WR_FIFO_RE     (wr_fifo_re),
    .WR_FIFO_EMPTY  (wr_empty),
    .WR_FIFO_DATA   (wr_fifo_data),
    .WR_DONE        (wr_done),
    .WR_ERR         (dut_wr_err),

    .RD_START       (rd_start),
    .RD_ADRS        (rd_adrs),
    .RD_LEN         (rd_len),
    .RD_READY       (rd_ready),
    .RD_FIFO_WE     (rd_fifo_we),
    .RD_FIFO_FULL   (rd_full),
    .RD_FIFO_DATA   (rd_fifo_data),
    .RD_DONE        (rd_done),
    .RD_ERR         (dut_rd_err),

    .DEBUG          ()
  );

  //--------------------------------------------------------------------
  // 从机 RAM + 协议检查器
  //--------------------------------------------------------------------
  axi_slave_ram #(
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .MEM_SIZE       (1048576),
    .R_LATENCY      (40),
    .B_LATENCY      (30)
  ) u_ram (
    .ACLK           (clk),
    .ARESETN        (rst_n),
    .stall_thr      (stall_thr),
    .chk_err        (slave_err),
    .chk_flags      (slave_flags),

    .s_axi_awid     (axi_awid),
    .s_axi_awaddr   (axi_awaddr),
    .s_axi_awlen    (axi_awlen),
    .s_axi_awsize   (axi_awsize),
    .s_axi_awburst  (axi_awburst),
    .s_axi_awvalid  (axi_awvalid),
    .s_axi_awready  (axi_awready),

    .s_axi_wdata    (axi_wdata),
    .s_axi_wstrb    (axi_wstrb),
    .s_axi_wlast    (axi_wlast),
    .s_axi_wvalid   (axi_wvalid),
    .s_axi_wready   (axi_wready),

    .s_axi_bid      (axi_bid),
    .s_axi_bresp    (axi_bresp),
    .s_axi_bvalid   (axi_bvalid),
    .s_axi_bready   (axi_bready),

    .s_axi_arid     (axi_arid),
    .s_axi_araddr   (axi_araddr),
    .s_axi_arlen    (axi_arlen),
    .s_axi_arsize   (axi_arsize),
    .s_axi_arburst  (axi_arburst),
    .s_axi_arvalid  (axi_arvalid),
    .s_axi_arready  (axi_arready),

    .s_axi_rid      (axi_rid),
    .s_axi_rdata    (axi_rdata),
    .s_axi_rresp    (axi_rresp),
    .s_axi_rlast    (axi_rlast),
    .s_axi_rvalid   (axi_rvalid),
    .s_axi_rready   (axi_rready)
  );

  //--------------------------------------------------------------------
  // 数据模式: 每拍 8 个 32 位字, 由 (seed, 拍序号) 唯一确定
  //--------------------------------------------------------------------
  function [AXI_DATA_WIDTH-1:0] gen_pattern(input [31:0] seed, input [31:0] idx);
    begin
      gen_pattern = {
        seed + idx + 32'h7000, seed + idx + 32'h6000,
        seed + idx + 32'h5000, seed + idx + 32'h4000,
        seed + idx + 32'h3000, seed + idx + 32'h2000,
        seed + idx + 32'h1000, seed + idx
      };
    end
  endfunction

  //--------------------------------------------------------------------
  // 测试表
  //--------------------------------------------------------------------
  function [31:0] f_seed(input [7:0] t);
    case(t)
      8'd0:  f_seed = 32'h1000_0000;  8'd1:  f_seed = 32'h2000_0000;
      8'd2:  f_seed = 32'h3000_0000;  8'd3:  f_seed = 32'h4000_0000;
      8'd4:  f_seed = 32'h5000_0000;  8'd5:  f_seed = 32'h6000_0000;
      8'd6:  f_seed = 32'h7000_0000;  8'd7:  f_seed = 32'h8000_0000;
      8'd8:  f_seed = 32'h9000_0000;  8'd9:  f_seed = 32'hA000_0000;
      8'd10: f_seed = 32'hB000_0000;
      default: f_seed = 32'd0;
    endcase
  endfunction

  function [AXI_ADDR_WIDTH-1:0] f_adrs(input [7:0] t);
    case(t)
      8'd0:  f_adrs = 32'h0000_0000;  8'd1:  f_adrs = 32'h0000_1000;
      8'd2:  f_adrs = 32'h0002_0F80;  8'd3:  f_adrs = 32'h0003_0020;
      8'd4:  f_adrs = 32'h0004_0000;  8'd5:  f_adrs = 32'h0005_0000;
      8'd6:  f_adrs = 32'h0007_0F80;  8'd7:  f_adrs = 32'h0008_0020;
      8'd8:  f_adrs = 32'h0009_0000;  8'd9:  f_adrs = 32'h000A_0000;
      8'd10: f_adrs = 32'h000B_0000;
      default: f_adrs = 32'd0;
    endcase
  endfunction

  function [31:0] f_bytes(input [7:0] t);
    case(t)
      8'd0:  f_bytes = 32'd4096;   8'd1:  f_bytes = 32'd65536;
      8'd2:  f_bytes = 32'd9600;   8'd3:  f_bytes = 32'd32;
      8'd4:  f_bytes = 32'd8192;   8'd5:  f_bytes = 32'd65536;
      8'd6:  f_bytes = 32'd9600;   8'd7:  f_bytes = 32'd32;
      8'd8:  f_bytes = 32'd16384;  8'd9:  f_bytes = 32'd16384;
      8'd10: f_bytes = 32'd0;
      default: f_bytes = 32'd0;
    endcase
  endfunction

  function [7:0] f_thr(input [7:0] t);
    case(t)
      8'd5, 8'd6, 8'd7: f_thr = 8'd96;
      8'd8:             f_thr = 8'd200;
      8'd9:             f_thr = 8'd64;
      default:          f_thr = 8'd0;
    endcase
  endfunction

  //--------------------------------------------------------------------
  // 状态与计数
  //--------------------------------------------------------------------
  localparam S_INIT     = 4'd0;
  localparam S_LOAD     = 4'd1;
  localparam S_P1_START = 4'd2;
  localparam S_P1_WAIT  = 4'd3;
  localparam S_P2_START = 4'd4;
  localparam S_P2_WAIT  = 4'd5;
  localparam S_CHECK    = 4'd6;
  localparam S_FIN_CHK  = 4'd7;
  localparam S_FINISH   = 4'd8;

  reg [3:0]  state;
  reg [31:0] wr_seed, rd_seed;
  reg [31:0] wr_bytes, rd_bytes;
  reg        t_conc;
  reg        wr_done_seen, rd_done_seen;
  reg [31:0] err_snap;
  reg [31:0] slave_snap;      // 本测试开始时从机检查器的计数

  reg [31:0] wr_beat_cnt;   // 用户写 FIFO 已被取走的拍数 (同时是数据序号)
  reg [31:0] rd_beat_cnt;   // 用户读 FIFO 已收到的拍数
  reg [31:0] wr_cyc, rd_cyc;

  wire [31:0] wr_beats_exp = (wr_bytes + (AXI_BYTES - 1)) / AXI_BYTES;
  wire [31:0] rd_beats_exp = (rd_bytes + (AXI_BYTES - 1)) / AXI_BYTES;

  assign wr_fifo_data = gen_pattern(wr_seed, wr_beat_cnt);

  // 用户侧随机停顿 (FWFT 写 FIFO: 一旦非空, 在被取走前保持非空)
  reg [31:0] tb_lfsr;
  wire       stall_en = (stall_thr != 8'd0);

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      tb_lfsr  <= 32'h1357_9BDF;
      wr_empty <= 1'b1;
      rd_full  <= 1'b0;
    end else begin
      tb_lfsr <= {tb_lfsr[30:0], tb_lfsr[31] ^ tb_lfsr[21] ^ tb_lfsr[1] ^ tb_lfsr[0]};
      if(stall_en) begin
        if(wr_empty || wr_fifo_re)
          wr_empty <= (tb_lfsr[7:0] < stall_thr);
        rd_full <= (tb_lfsr[15:8] < stall_thr);
      end else begin
        wr_empty <= 1'b0;
        rd_full  <= 1'b0;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      wr_beat_cnt <= 32'd0;
      rd_beat_cnt <= 32'd0;
      wr_cyc      <= 32'd0;
      rd_cyc      <= 32'd0;
    end else begin
      if(wr_start)        wr_beat_cnt <= 32'd0;
      else if(wr_fifo_re) wr_beat_cnt <= wr_beat_cnt + 32'd1;

      if(rd_start)        rd_beat_cnt <= 32'd0;
      else if(rd_fifo_we) rd_beat_cnt <= rd_beat_cnt + 32'd1;

      if(wr_start)         wr_cyc <= 32'd1;
      else if(!wr_ready)   wr_cyc <= wr_cyc + 32'd1;

      if(rd_start)         rd_cyc <= 32'd1;
      else if(!rd_ready)   rd_cyc <= rd_cyc + 32'd1;
    end
  end

  //--------------------------------------------------------------------
  // 错误事件 (单一驱动 err_count)
  //--------------------------------------------------------------------
  wire        data_mismatch = rd_fifo_we && (rd_fifo_data !== gen_pattern(rd_seed, rd_beat_cnt));
  wire        in_check      = (state == S_CHECK);
  wire        e_wr_beats    = in_check && (wr_beat_cnt != wr_beats_exp);
  wire        e_rd_beats    = in_check && (rd_beat_cnt != rd_beats_exp);
  wire        e_resp        = in_check && (dut_wr_err || dut_rd_err);
  wire [31:0] e_slave       = (state == S_FIN_CHK) ? slave_err : 32'd0;
  wire        test_ok       = (err_count == err_snap) && (slave_err == slave_snap) &&
                                      !e_wr_beats && !e_rd_beats && !e_resp;

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
      err_count <= 32'd0;
    else
      err_count <= err_count + {31'd0, data_mismatch} + {31'd0, e_wr_beats}
                             + {31'd0, e_rd_beats} + {31'd0, e_resp} + e_slave;
  end

  always @(posedge clk) begin
    if(data_mismatch)
      $display("[TB ERROR] test %0d beat %0d mismatch! Expected: 0x%h, Got: 0x%h",
               cur_test, rd_beat_cnt, gen_pattern(rd_seed, rd_beat_cnt), rd_fifo_data);
  end

  //--------------------------------------------------------------------
  // 主状态机
  //--------------------------------------------------------------------
  wire wr_fin = wr_done_seen | wr_done;
  wire rd_fin = rd_done_seen | rd_done;

  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      state        <= S_INIT;
      cur_test     <= 8'd0;
      wr_start     <= 1'b0;
      rd_start     <= 1'b0;
      wr_adrs      <= {AXI_ADDR_WIDTH{1'b0}};
      rd_adrs      <= {AXI_ADDR_WIDTH{1'b0}};
      wr_len       <= 32'd0;
      rd_len       <= 32'd0;
      wr_seed      <= 32'd0;
      rd_seed      <= 32'd0;
      wr_bytes     <= 32'd0;
      rd_bytes     <= 32'd0;
      t_conc       <= 1'b0;
      stall_thr    <= 8'd0;
      wr_done_seen <= 1'b0;
      rd_done_seen <= 1'b0;
      err_snap     <= 32'd0;
      slave_snap   <= 32'd0;
      test_done    <= 1'b0;
      test_pass    <= 1'b0;
    end else begin
      if(wr_done) wr_done_seen <= 1'b1;
      if(rd_done) rd_done_seen <= 1'b1;

      case(state)
        S_INIT: begin
          if(wr_ready && rd_ready) begin
            cur_test <= 8'd0;
            state    <= S_LOAD;
          end
        end

        S_LOAD: begin
          wr_done_seen <= 1'b0;
          rd_done_seen <= 1'b0;
          err_snap     <= err_count;
          slave_snap   <= slave_err;
          stall_thr    <= f_thr(cur_test);

          wr_seed      <= f_seed(cur_test);
          wr_adrs      <= f_adrs(cur_test);
          wr_bytes     <= f_bytes(cur_test);
          wr_len       <= f_bytes(cur_test);

          if(cur_test == 8'd9) begin
            // 并发: 写新区域, 同时读 T1 写过的前 16KB
            t_conc   <= 1'b1;
            rd_seed  <= f_seed(8'd1);
            rd_adrs  <= f_adrs(8'd1);
            rd_bytes <= 32'd16384;
            rd_len   <= 32'd16384;
          end else begin
            t_conc   <= 1'b0;
            rd_seed  <= f_seed(cur_test);
            rd_adrs  <= f_adrs(cur_test);
            rd_bytes <= f_bytes(cur_test);
            rd_len   <= f_bytes(cur_test);
          end

          $display("\n>>> [TEST %0d] start: addr=0x%08h bytes=%0d stall_thr=%0d/256%s",
                   cur_test, f_adrs(cur_test), f_bytes(cur_test), f_thr(cur_test),
                   (cur_test == 8'd9) ? " (read/write concurrent)" : "");
          state <= S_P1_START;
        end

        S_P1_START: begin
          wr_start <= 1'b1;
          if(t_conc) rd_start <= 1'b1;
          state    <= S_P1_WAIT;
        end

        S_P1_WAIT: begin
          wr_start <= 1'b0;
          rd_start <= 1'b0;
          if(wr_fin && (!t_conc || rd_fin)) begin
            if(t_conc) state <= S_CHECK;
            else       state <= S_P2_START;
          end
        end

        S_P2_START: begin
          rd_start <= 1'b1;
          state    <= S_P2_WAIT;
        end

        S_P2_WAIT: begin
          rd_start <= 1'b0;
          if(rd_fin) state <= S_CHECK;
        end

        S_CHECK: begin
          $display("    [TEST %0d] WR %0d beats / %0d cyc = %0d.%0d%% | RD %0d beats / %0d cyc = %0d.%0d%% | %s",
                   cur_test,
                   wr_beat_cnt, wr_cyc,
                   (wr_cyc == 0) ? 32'd0 : (wr_beat_cnt * 1000 / wr_cyc) / 10,
                   (wr_cyc == 0) ? 32'd0 : (wr_beat_cnt * 1000 / wr_cyc) % 10,
                   rd_beat_cnt, rd_cyc,
                   (rd_cyc == 0) ? 32'd0 : (rd_beat_cnt * 1000 / rd_cyc) / 10,
                   (rd_cyc == 0) ? 32'd0 : (rd_beat_cnt * 1000 / rd_cyc) % 10,
                   test_ok ? "PASS" : "FAIL");
          if(slave_err != slave_snap)
            $display("    [TEST %0d] 从机协议检查器命中 %0d 次, 累计 chk_flags = 0x%04h", cur_test, slave_err - slave_snap, slave_flags);
          if(cur_test == NTESTS - 1) begin
            state <= S_FIN_CHK;
          end else begin
            cur_test <= cur_test + 8'd1;
            state    <= S_LOAD;
          end
        end

        S_FIN_CHK: begin
          state <= S_FINISH;
        end

        S_FINISH: begin
          if(!test_done)
            $display("\n>>> [SLAVE CHECKER] chk_flags = 0x%04h, chk_err = %0d (期望全 0)", slave_flags, slave_err);
          test_done <= 1'b1;
          test_pass <= (err_count == 32'd0);
          state     <= S_FINISH;
        end

        default: state <= S_INIT;
      endcase
    end
  end

endmodule
