/*------------------------------------------------------------------------------
Function: AXI4-Full 从机 RAM 行为模型 + 协议检查器 (脱机仿真用, 不是 DDR 时序模型)
  - 多事务在途: AW / AR 各 16 深队列
  - 固定延迟: AR 握手后 R_LATENCY 周期出首拍; 最后一拍 W 后 B_LATENCY 周期出 B
  - 随机反压: stall_thr/256 的概率拉低 AWREADY / ARREADY / WREADY / RVALID (0 = 不停顿)
  - 协议检查 (命中记入 chk_flags 粘滞位, chk_err 累计命中次数):
      [0] AW 突发跨 4KB            [1] AR 突发跨 4KB
      [2] AWSIZE/AWBURST 异常      [3] ARSIZE/ARBURST 异常
      [4] AW 在 VALID 期间信号变化  [5] W 在 VALID 期间信号变化   [6] AR 在 VALID 期间信号变化
      [7] WLAST 位置与 AWLEN 不符  [8] 地址越界 (不做取模别名)
      [9] WSTRB 非全 1             [10] 队列溢出
Author: AI Assistant
Date: 2026-10-03
------------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module axi_slave_ram
#(
  parameter AXI_ADDR_WIDTH = 32,
  parameter AXI_DATA_WIDTH = 256,
  parameter MEM_SIZE       = 1048576,   // 字节, 1 MB
  parameter R_LATENCY      = 40,        // AR 握手 -> 首拍 R (周期)
  parameter B_LATENCY      = 30         // 最后一拍 W -> B (周期)
)
(
  input  wire                           ACLK,
  input  wire                           ARESETN,

  input  wire [7:0]                     stall_thr,     // 随机停顿概率 = stall_thr/256

  output reg  [31:0]                    chk_err,
  output reg  [15:0]                    chk_flags,

  // Write Address Channel
  input  wire [0:0]                     s_axi_awid,
  input  wire [AXI_ADDR_WIDTH-1:0]      s_axi_awaddr,
  input  wire [7:0]                     s_axi_awlen,
  input  wire [2:0]                     s_axi_awsize,
  input  wire [1:0]                     s_axi_awburst,
  input  wire                           s_axi_awvalid,
  output wire                           s_axi_awready,

  // Write Data Channel
  input  wire [AXI_DATA_WIDTH-1:0]      s_axi_wdata,
  input  wire [(AXI_DATA_WIDTH/8)-1:0]  s_axi_wstrb,
  input  wire                           s_axi_wlast,
  input  wire                           s_axi_wvalid,
  output wire                           s_axi_wready,

  // Write Response Channel
  output wire [0:0]                     s_axi_bid,
  output wire [1:0]                     s_axi_bresp,
  output wire                           s_axi_bvalid,
  input  wire                           s_axi_bready,

  // Read Address Channel
  input  wire [0:0]                     s_axi_arid,
  input  wire [AXI_ADDR_WIDTH-1:0]      s_axi_araddr,
  input  wire [7:0]                     s_axi_arlen,
  input  wire [2:0]                     s_axi_arsize,
  input  wire [1:0]                     s_axi_arburst,
  input  wire                           s_axi_arvalid,
  output wire                           s_axi_arready,

  // Read Data Channel
  output wire [0:0]                     s_axi_rid,
  output wire [AXI_DATA_WIDTH-1:0]      s_axi_rdata,
  output wire [1:0]                     s_axi_rresp,
  output wire                           s_axi_rlast,
  output wire                           s_axi_rvalid,
  input  wire                           s_axi_rready
);

  localparam AXI_BYTES      = AXI_DATA_WIDTH / 8;
  localparam AXI_OFFSET     = $clog2(AXI_BYTES);
  /* verilator lint_off WIDTHTRUNC */
  localparam [2:0] AXI_SIZE = AXI_OFFSET;
  /* verilator lint_on WIDTHTRUNC */
  localparam RAM_DEPTH      = MEM_SIZE / AXI_BYTES;

  reg [AXI_DATA_WIDTH-1:0] mem [0:RAM_DEPTH-1];

  //--------------------------------------------------------------------
  // 周期计数与随机数
  //--------------------------------------------------------------------
  reg [31:0] cyc;
  reg [31:0] lfsr;

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN) begin
      cyc  <= 32'd0;
      lfsr <= 32'hACE1_2468;
    end else begin
      cyc  <= cyc + 32'd1;
      lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
    end
  end

  wire stall_aw = (lfsr[7:0]   < stall_thr);
  wire stall_w  = (lfsr[15:8]  < stall_thr);
  wire stall_ar = (lfsr[23:16] < stall_thr);
  wire stall_r  = (lfsr[31:24] < stall_thr);

  // 突发是否跨 4KB
  function cross_4k(input [AXI_ADDR_WIDTH-1:0] addr, input [7:0] len);
    reg [15:0] endb;
    begin
      endb     = {4'd0, addr[11:0]} + ({8'd0, len} + 16'd1) * AXI_BYTES;
      cross_4k = (endb > 16'd4096);
    end
  endfunction

  //--------------------------------------------------------------------
  // 写通道
  //--------------------------------------------------------------------
  reg [AXI_ADDR_WIDTH-1:0] awq_addr [0:15];
  reg [7:0]                awq_len  [0:15];
  reg [4:0]                awq_wp, awq_rp;
  reg [7:0]                w_beat;

  reg [31:0]               bq_time [0:15];
  reg [4:0]                bq_wp, bq_rp;

  reg                      aw_rdy_r;
  reg                      w_ok_r;

  wire awq_full  = ((awq_wp - awq_rp) >= 5'd15);
  wire w_have    = (awq_wp != awq_rp);

  assign s_axi_awready = aw_rdy_r;
  assign s_axi_wready  = w_have & w_ok_r;
  assign s_axi_bvalid  = (bq_wp != bq_rp) && (cyc >= bq_time[bq_rp[3:0]]);
  assign s_axi_bresp   = 2'b00;
  assign s_axi_bid     = 1'b0;

  wire [AXI_ADDR_WIDTH-1:0] w_head_addr = awq_addr[awq_rp[3:0]];
  wire [7:0]                w_head_len  = awq_len[awq_rp[3:0]];
  wire [AXI_ADDR_WIDTH-1:0] w_cur_addr  = w_head_addr + ({{(AXI_ADDR_WIDTH-8){1'b0}}, w_beat} << AXI_OFFSET);
  wire                      w_hs        = s_axi_wvalid & s_axi_wready;
  wire                      aw_hs       = s_axi_awvalid & s_axi_awready;
  wire                      w_oor       = ({1'b0, w_cur_addr} + AXI_BYTES) > MEM_SIZE;

  // VALID 期间稳定性检查寄存
  reg                       aw_pend;
  reg [AXI_ADDR_WIDTH-1:0]  aw_pend_addr;
  reg [7:0]                 aw_pend_len;
  reg                       w_pend;
  reg [AXI_DATA_WIDTH-1:0]  w_pend_data;
  reg                       w_pend_last;

  integer i;

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN) begin
      awq_wp       <= 5'd0;
      awq_rp       <= 5'd0;
      bq_wp        <= 5'd0;
      bq_rp        <= 5'd0;
      w_beat       <= 8'd0;
      aw_rdy_r     <= 1'b0;
      w_ok_r       <= 1'b0;
      aw_pend      <= 1'b0;
      w_pend       <= 1'b0;
      aw_pend_addr <= {AXI_ADDR_WIDTH{1'b0}};
      aw_pend_len  <= 8'd0;
      w_pend_data  <= {AXI_DATA_WIDTH{1'b0}};
      w_pend_last  <= 1'b0;
    end else begin
      aw_rdy_r <= ~stall_aw & ~awq_full;
      w_ok_r   <= ~stall_w;

      aw_pend <= s_axi_awvalid & ~s_axi_awready;
      if(s_axi_awvalid & ~s_axi_awready) begin
        aw_pend_addr <= s_axi_awaddr;
        aw_pend_len  <= s_axi_awlen;
      end

      if(aw_hs) begin
        awq_addr[awq_wp[3:0]] <= s_axi_awaddr;
        awq_len [awq_wp[3:0]] <= s_axi_awlen;
        awq_wp                <= awq_wp + 5'd1;
      end

      w_pend <= s_axi_wvalid & ~s_axi_wready;
      if(s_axi_wvalid & ~s_axi_wready) begin
        w_pend_data <= s_axi_wdata;
        w_pend_last <= s_axi_wlast;
      end

      if(w_hs) begin
        if(!w_oor) begin
          for(i = 0; i < AXI_BYTES; i = i + 1)
            if(s_axi_wstrb[i])
              mem[w_cur_addr >> AXI_OFFSET][8*i +: 8] <= s_axi_wdata[8*i +: 8];
        end

        if(w_beat == w_head_len) begin
          w_beat               <= 8'd0;
          awq_rp               <= awq_rp + 5'd1;
          bq_time[bq_wp[3:0]]  <= cyc + B_LATENCY;
          bq_wp                <= bq_wp + 5'd1;
        end else begin
          w_beat <= w_beat + 8'd1;
        end
      end

      if(s_axi_bvalid && s_axi_bready)
        bq_rp <= bq_rp + 5'd1;
    end
  end

  //--------------------------------------------------------------------
  // 读通道
  //--------------------------------------------------------------------
  reg [AXI_ADDR_WIDTH-1:0] arq_addr [0:15];
  reg [7:0]                arq_len  [0:15];
  reg [31:0]               arq_time [0:15];
  reg [4:0]                arq_wp, arq_rp;
  reg [7:0]                r_beat;

  reg                      ar_rdy_r;
  reg                      rvalid_r;
  reg [AXI_DATA_WIDTH-1:0] rdata_r;
  reg                      rlast_r;

  wire arq_full = ((arq_wp - arq_rp) >= 5'd15);
  wire arq_have = (arq_wp != arq_rp);
  wire ar_hs    = s_axi_arvalid & s_axi_arready;

  wire [AXI_ADDR_WIDTH-1:0] r_head_addr = arq_addr[arq_rp[3:0]];
  wire [7:0]                r_head_len  = arq_len[arq_rp[3:0]];
  wire [AXI_ADDR_WIDTH-1:0] r_cur_addr  = r_head_addr + ({{(AXI_ADDR_WIDTH-8){1'b0}}, r_beat} << AXI_OFFSET);
  wire                      r_slot_free = ~rvalid_r | s_axi_rready;
  wire                      r_issue     = r_slot_free & arq_have & (cyc >= arq_time[arq_rp[3:0]]) & ~stall_r;
  wire                      r_oor       = ({1'b0, r_cur_addr} + AXI_BYTES) > MEM_SIZE;

  assign s_axi_arready = ar_rdy_r;
  assign s_axi_rvalid  = rvalid_r;
  assign s_axi_rdata   = rdata_r;
  assign s_axi_rlast   = rlast_r;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_rid     = 1'b0;

  reg                       ar_pend;
  reg [AXI_ADDR_WIDTH-1:0]  ar_pend_addr;
  reg [7:0]                 ar_pend_len;

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN) begin
      arq_wp       <= 5'd0;
      arq_rp       <= 5'd0;
      r_beat       <= 8'd0;
      ar_rdy_r     <= 1'b0;
      rvalid_r     <= 1'b0;
      rdata_r      <= {AXI_DATA_WIDTH{1'b0}};
      rlast_r      <= 1'b0;
      ar_pend      <= 1'b0;
      ar_pend_addr <= {AXI_ADDR_WIDTH{1'b0}};
      ar_pend_len  <= 8'd0;
    end else begin
      ar_rdy_r <= ~stall_ar & ~arq_full;

      ar_pend <= s_axi_arvalid & ~s_axi_arready;
      if(s_axi_arvalid & ~s_axi_arready) begin
        ar_pend_addr <= s_axi_araddr;
        ar_pend_len  <= s_axi_arlen;
      end

      if(ar_hs) begin
        arq_addr[arq_wp[3:0]] <= s_axi_araddr;
        arq_len [arq_wp[3:0]] <= s_axi_arlen;
        arq_time[arq_wp[3:0]] <= cyc + R_LATENCY;
        arq_wp                <= arq_wp + 5'd1;
      end

      // R 输出: 槽空 (无 VALID 或已被取走) 时才可换新值, VALID 期间保持稳定
      if(r_slot_free) begin
        if(r_issue) begin
          rvalid_r <= 1'b1;
          rdata_r  <= r_oor ? {AXI_DATA_WIDTH{1'b0}} : mem[r_cur_addr >> AXI_OFFSET];
          rlast_r  <= (r_beat == r_head_len);
          if(r_beat == r_head_len) begin
            r_beat <= 8'd0;
            arq_rp <= arq_rp + 5'd1;
          end else begin
            r_beat <= r_beat + 8'd1;
          end
        end else begin
          rvalid_r <= 1'b0;
          rlast_r  <= 1'b0;
        end
      end
    end
  end

  //--------------------------------------------------------------------
  // 协议检查: 组合事件 -> 单一 always 汇总
  //--------------------------------------------------------------------
  wire [10:0] ev;
  assign ev[0]  = aw_hs & cross_4k(s_axi_awaddr, s_axi_awlen);
  assign ev[1]  = ar_hs & cross_4k(s_axi_araddr, s_axi_arlen);
  assign ev[2]  = aw_hs & ((s_axi_awsize != AXI_SIZE) | (s_axi_awburst != 2'b01));
  assign ev[3]  = ar_hs & ((s_axi_arsize != AXI_SIZE) | (s_axi_arburst != 2'b01));
  assign ev[4]  = aw_pend & ~(s_axi_awvalid & (s_axi_awaddr == aw_pend_addr) & (s_axi_awlen == aw_pend_len));
  assign ev[5]  = w_pend  & ~(s_axi_wvalid  & (s_axi_wdata == w_pend_data)   & (s_axi_wlast == w_pend_last));
  assign ev[6]  = ar_pend & ~(s_axi_arvalid & (s_axi_araddr == ar_pend_addr) & (s_axi_arlen == ar_pend_len));
  assign ev[7]  = w_hs & (s_axi_wlast != (w_beat == w_head_len));
  assign ev[8]  = (w_hs & w_oor) | (r_issue & r_oor);
  assign ev[9]  = w_hs & (s_axi_wstrb != {AXI_BYTES{1'b1}});
  assign ev[10] = (aw_hs & awq_full) | (ar_hs & arq_full);

  function [3:0] popcnt11(input [10:0] v);
    integer k;
    begin
      popcnt11 = 4'd0;
      for(k = 0; k < 11; k = k + 1)
        popcnt11 = popcnt11 + {3'd0, v[k]};
    end
  endfunction

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN) begin
      chk_err   <= 32'd0;
      chk_flags <= 16'd0;
    end else begin
      chk_flags <= chk_flags | {5'd0, ev};
      chk_err   <= chk_err + {28'd0, popcnt11(ev)};
    end
  end

endmodule
