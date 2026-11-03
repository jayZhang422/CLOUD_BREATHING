/*------------------------------
Author: JasperZ (Parameterized by AI Assistant)
Data: 2026-10-03
Code: UTF-8
Version: Vivado 2026.1
Function: V3.0: aq_axi_master AXI4 主机控制器 (参数化位宽 64/128/256/512-bit)
  时序修复: W通道增加一拍弹性寄存级；FWFT取数与对外AXI握手解耦，连续吞吐仍为每拍一拍。
  V3.0 相对 V2.0 的修复:
   1. 突发自动按 4KB 边界拆分 (AXI4 禁止 INCR 突发跨 4KB), 单突发最大拍数 = min(256, 4096/字节数)
   2. 写: AW / W / B 三通道解耦, 支持 MAX_OUT_WR 个突发在途 (outstanding)
   3. 读: AR / R 解耦, 支持 MAX_OUT_RD 个突发在途
   4. 读数据写使能 = RVALID & RREADY, RREADY 仅由 RD_FIFO_FULL 决定 (修复满时丢数/重复写)
   5. 起始长度 / 地址在启动时锁存, 之后改动 WR_LEN / RD_LEN 无影响
   6. 新增 WR_ERR / RD_ERR: BRESP / RRESP 出错 (SLVERR/DECERR) 的粘滞标志, 下次启动清零
   7. MASTER_RST 同时作用于读写两侧; M_AXI_ARLOCK 改为 1 位 (AXI4)
  用户侧接口语义变化 (与 V2.0 不兼容):
   - 写数据口按 FWFT(show-ahead) FIFO 消费: WR_FIFO_EMPTY=0 时 WR_FIFO_DATA 必须有效,
     WR_FIFO_RE 为"本拍取走当前数据"脉冲. 已删除 WR_FIFO_AEMPTY / RD_FIFO_AFULL 端口.
  使用约束:
   - WR_ADRS / RD_ADRS 按总线字节数向下对齐; WR_LEN / RD_LEN 按总线字节数向上取整成拍数, 0 表示无传输
   - MASTER_RST 只清内部状态, 不能撤销已发出的 AXI 事务, 仅在总线空闲或随后整体复位 MIG 时使用
   - ARESETN 的释放需在 ACLK 域同步 (例: 由 ui_clk_sync_rst 取反并等 init_calib_complete)
-------------------------------*/
module aq_axi_master
#(
  parameter AXI_ADDR_WIDTH = 32,
  parameter AXI_DATA_WIDTH = 256,
  parameter MAX_OUT_WR     = 8,     // 写在途突发数上限 (1~16)
  parameter MAX_OUT_RD     = 8      // 读在途突发数上限 (1~31)
)
(
  // Reset, Clock
  input                        ARESETN,
  input                        ACLK,

  // Master Write Address
  output [0:0]                 M_AXI_AWID,
  output [AXI_ADDR_WIDTH-1:0]  M_AXI_AWADDR,
  output [7:0]                 M_AXI_AWLEN,    // Burst Length - 1
  output [2:0]                 M_AXI_AWSIZE,   // Burst Size: $clog2(bytes)
  output [1:0]                 M_AXI_AWBURST,  // 2'b01 (INCR)
  output                       M_AXI_AWLOCK,
  output [3:0]                 M_AXI_AWCACHE,
  output [2:0]                 M_AXI_AWPROT,
  output [3:0]                 M_AXI_AWQOS,
  output [0:0]                 M_AXI_AWUSER,
  output                       M_AXI_AWVALID,
  input                        M_AXI_AWREADY,

  // Master Write Data
  output [AXI_DATA_WIDTH-1:0]  M_AXI_WDATA,
  output [(AXI_DATA_WIDTH/8)-1:0] M_AXI_WSTRB,
  output                       M_AXI_WLAST,
  output [0:0]                 M_AXI_WUSER,
  output                       M_AXI_WVALID,
  input                        M_AXI_WREADY,

  // Master Write Response
  input [0:0]                  M_AXI_BID,
  input [1:0]                  M_AXI_BRESP,
  input [0:0]                  M_AXI_BUSER,
  input                        M_AXI_BVALID,
  output                       M_AXI_BREADY,

  // Master Read Address
  output [0:0]                 M_AXI_ARID,
  output [AXI_ADDR_WIDTH-1:0]  M_AXI_ARADDR,
  output [7:0]                 M_AXI_ARLEN,
  output [2:0]                 M_AXI_ARSIZE,
  output [1:0]                 M_AXI_ARBURST,
  output                       M_AXI_ARLOCK,
  output [3:0]                 M_AXI_ARCACHE,
  output [2:0]                 M_AXI_ARPROT,
  output [3:0]                 M_AXI_ARQOS,
  output [0:0]                 M_AXI_ARUSER,
  output                       M_AXI_ARVALID,
  input                        M_AXI_ARREADY,

  // Master Read Data
  input [0:0]                  M_AXI_RID,
  input [AXI_DATA_WIDTH-1:0]   M_AXI_RDATA,
  input [1:0]                  M_AXI_RRESP,
  input                        M_AXI_RLAST,
  input [0:0]                  M_AXI_RUSER,
  input                        M_AXI_RVALID,
  output                       M_AXI_RREADY,

  // Local Bus (用户端 FIFO 接口)
  input                        MASTER_RST,

  input                        WR_START,       // 写启动脉冲 (WR_READY=1 时有效)
  input [AXI_ADDR_WIDTH-1:0]   WR_ADRS,        // 目标字节起始地址
  input [31:0]                 WR_LEN,         // 传输总字节数
  output                       WR_READY,       // 写空闲
  output                       WR_FIFO_RE,     // 写 FIFO 读使能 (FWFT: 取走当前数据)
  input                        WR_FIFO_EMPTY,  // 写 FIFO 空标志
  input [AXI_DATA_WIDTH-1:0]   WR_FIFO_DATA,   // 写入数据流 (EMPTY=0 时有效)
  output                       WR_DONE,        // 写任务全部完成脉冲 (最后一个 B 响应已收)
  output                       WR_ERR,         // 写响应出错 (粘滞, 下次启动清零)

  input                        RD_START,       // 读启动脉冲 (RD_READY=1 时有效)
  input [AXI_ADDR_WIDTH-1:0]   RD_ADRS,        // 源字节起始地址
  input [31:0]                 RD_LEN,         // 传输总字节数
  output                       RD_READY,       // 读空闲
  output                       RD_FIFO_WE,     // 读 FIFO 写使能 (= RVALID & RREADY)
  input                        RD_FIFO_FULL,   // 读 FIFO 满标志
  output [AXI_DATA_WIDTH-1:0]  RD_FIFO_DATA,   // 读出数据流
  output                       RD_DONE,        // 读任务全部完成脉冲 (最后一个 RLAST 已收)
  output                       RD_ERR,         // 读响应出错 (粘滞, 下次启动清零)

  output [31:0]                DEBUG
);

  //--------------------------------------------------------------------
  // 常量
  //--------------------------------------------------------------------
  localparam AXI_BYTES     = AXI_DATA_WIDTH / 8;
  localparam AXI_OFFSET    = $clog2(AXI_BYTES);
  localparam BEATS_4K      = 4096 / AXI_BYTES;                           // 一个 4KB 页的拍数
  localparam MAX_BURST_I   = (BEATS_4K > 256) ? 256 : BEATS_4K;          // 单突发最大拍数
  /* verilator lint_off WIDTHTRUNC */
  localparam [2:0] AXI_SIZE    = AXI_OFFSET;
  localparam [8:0] MAX_BURST_N = MAX_BURST_I;
  /* verilator lint_on WIDTHTRUNC */

  //--------------------------------------------------------------------
  // 写通道: 地址 / 控制
  //--------------------------------------------------------------------
  reg                        wr_run;
  reg                        wr_done_r;
  reg                        wr_err_r;
  reg [AXI_ADDR_WIDTH-1:0]   aw_addr;        // 下一个突发的起始地址
  reg [31:0]                 aw_rem;         // 尚未发出 AW 的剩余拍数
  reg                        awvalid_r;
  reg [AXI_ADDR_WIDTH-1:0]   awaddr_r;
  reg [7:0]                  awlen_r;
  reg [4:0]                  wr_out_cnt;     // 在途突发数: AW 发出决定时 +1, B 收到时 -1

  // 已被从机接收 AW 的突发长度队列 (供 W 通道按序取用)
  reg [7:0]                  len_mem [0:15];
  reg [4:0]                  len_wptr;
  reg [4:0]                  len_rptr;

  wire [32:0]                wr_len_up    = {1'b0, WR_LEN} + (AXI_BYTES - 1);
  wire [31:0]                wr_beats_all = {{(AXI_OFFSET-1){1'b0}}, wr_len_up[32:AXI_OFFSET]};

  // 本突发拍数 = min(剩余, MAX_BURST_N, 距 4KB 边界拍数)
  wire [12:0]                aw_beats_4k  = (13'd4096 - {1'b0, aw_addr[11:0]}) >> AXI_OFFSET;
  wire [8:0]                 aw_cap       = (aw_beats_4k > {4'd0, MAX_BURST_N}) ? MAX_BURST_N : aw_beats_4k[8:0];
  wire [8:0]                 aw_n         = (aw_rem > {23'd0, aw_cap}) ? aw_cap : aw_rem[8:0];

  wire                       aw_hs        = awvalid_r & M_AXI_AWREADY;
  wire                       b_hs         = M_AXI_BVALID & (wr_out_cnt != 5'd0);
  wire                       aw_can_load  = wr_run & (aw_rem != 32'd0) &
                                            (~awvalid_r | M_AXI_AWREADY) &
                                            (wr_out_cnt < MAX_OUT_WR);

  always @(posedge ACLK) begin
    if(aw_hs)
      len_mem[len_wptr[3:0]] <= awlen_r;
  end

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN) begin
      wr_run      <= 1'b0;
      wr_done_r   <= 1'b0;
      wr_err_r    <= 1'b0;
      aw_addr     <= {AXI_ADDR_WIDTH{1'b0}};
      aw_rem      <= 32'd0;
      awvalid_r   <= 1'b0;
      awaddr_r    <= {AXI_ADDR_WIDTH{1'b0}};
      awlen_r     <= 8'd0;
      wr_out_cnt  <= 5'd0;
      len_wptr    <= 5'd0;
    end else if(MASTER_RST) begin
      wr_run      <= 1'b0;
      wr_done_r   <= 1'b0;
      wr_err_r    <= 1'b0;
      aw_rem      <= 32'd0;
      awvalid_r   <= 1'b0;
      wr_out_cnt  <= 5'd0;
      len_wptr    <= 5'd0;
    end else begin
      wr_done_r  <= 1'b0;
      wr_out_cnt <= wr_out_cnt + {4'd0, aw_can_load} - {4'd0, b_hs};

      if(!wr_run) begin
        if(WR_START) begin
          wr_run   <= 1'b1;
          wr_err_r <= 1'b0;
          aw_addr  <= {WR_ADRS[AXI_ADDR_WIDTH-1:AXI_OFFSET], {AXI_OFFSET{1'b0}}};
          aw_rem   <= wr_beats_all;
        end
      end else begin
        if(aw_can_load) begin
          awvalid_r <= 1'b1;
          awaddr_r  <= aw_addr;
          awlen_r   <= aw_n[7:0] - 8'd1;
          aw_addr   <= aw_addr + ({{(AXI_ADDR_WIDTH-9){1'b0}}, aw_n} << AXI_OFFSET);
          aw_rem    <= aw_rem - {23'd0, aw_n};
        end else if(M_AXI_AWREADY) begin
          awvalid_r <= 1'b0;
        end

        if(aw_hs)
          len_wptr <= len_wptr + 5'd1;

        if(b_hs && M_AXI_BRESP[1])
          wr_err_r <= 1'b1;

        // 全部突发已发出且全部 B 已回: 完成
        if(aw_rem == 32'd0 && wr_out_cnt == 5'd0 && !awvalid_r) begin
          wr_run    <= 1'b0;
          wr_done_r <= 1'b1;
        end
      end
    end
  end

  //--------------------------------------------------------------------
  // 写通道: 数据 (只在对应 AW 已被接收后才开始发该突发的 W)
  //--------------------------------------------------------------------
  reg                        w_active;
  reg [7:0]                  w_cnt;          // 本突发剩余拍数 - 1
  reg                        w_valid_r;
  reg                        w_last_r;
  reg [AXI_DATA_WIDTH-1:0]    w_data_r;

  wire                       w_have     = (len_wptr != len_rptr);
  wire [7:0]                 w_len_head = len_mem[len_rptr[3:0]];
  // 弹性寄存级切断BRAM输出到MIG写缓冲的组合路径，允许每拍装入/送出一拍。
  // w_hs表示从FWFT源取入寄存级；W计数与WLAST在取入时对齐。
  wire                       w_accept   = ~w_valid_r | M_AXI_WREADY;
  wire                       w_hs       = w_active & ~WR_FIFO_EMPTY & w_accept;
  wire                       w_end      = w_hs & (w_cnt == 8'd0);
  wire                       w_load     = w_have & (~w_active | w_end);

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN)
      w_valid_r <= 1'b0;
    else if(MASTER_RST)
      w_valid_r <= 1'b0;
    else if(w_accept)
      w_valid_r <= w_active & ~WR_FIFO_EMPTY;
  end

  // 数据无复位；valid=0时内容无效，反压时数据和LAST均保持。
  always @(posedge ACLK) begin
    if(w_hs) begin
      w_data_r <= WR_FIFO_DATA;
      w_last_r <= (w_cnt == 8'd0);
    end
  end

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN) begin
      w_active  <= 1'b0;
      w_cnt     <= 8'd0;
      len_rptr  <= 5'd0;
    end else if(MASTER_RST) begin
      w_active  <= 1'b0;
      w_cnt     <= 8'd0;
      len_rptr  <= 5'd0;
    end else begin
      if(w_load) begin
        w_active <= 1'b1;
        w_cnt    <= w_len_head;
        len_rptr <= len_rptr + 5'd1;
      end else if(w_end) begin
        w_active <= 1'b0;
      end else if(w_hs) begin
        w_cnt    <= w_cnt - 8'd1;
      end
    end
  end

  //--------------------------------------------------------------------
  // 读通道
  //--------------------------------------------------------------------
  reg                        rd_run;
  reg                        rd_done_r;
  reg                        rd_err_r;
  reg [AXI_ADDR_WIDTH-1:0]   ar_addr;
  reg [31:0]                 ar_rem;
  reg                        arvalid_r;
  reg [AXI_ADDR_WIDTH-1:0]   araddr_r;
  reg [7:0]                  arlen_r;
  reg [4:0]                  rd_out_cnt;

  wire [32:0]                rd_len_up    = {1'b0, RD_LEN} + (AXI_BYTES - 1);
  wire [31:0]                rd_beats_all = {{(AXI_OFFSET-1){1'b0}}, rd_len_up[32:AXI_OFFSET]};

  wire [12:0]                ar_beats_4k  = (13'd4096 - {1'b0, ar_addr[11:0]}) >> AXI_OFFSET;
  wire [8:0]                 ar_cap       = (ar_beats_4k > {4'd0, MAX_BURST_N}) ? MAX_BURST_N : ar_beats_4k[8:0];
  wire [8:0]                 ar_n         = (ar_rem > {23'd0, ar_cap}) ? ar_cap : ar_rem[8:0];

  wire                       r_hs         = M_AXI_RVALID & M_AXI_RREADY;
  wire                       r_end        = r_hs & M_AXI_RLAST;
  wire                       ar_can_load  = rd_run & (ar_rem != 32'd0) &
                                            (~arvalid_r | M_AXI_ARREADY) &
                                            (rd_out_cnt < MAX_OUT_RD);

  always @(posedge ACLK or negedge ARESETN) begin
    if(!ARESETN) begin
      rd_run      <= 1'b0;
      rd_done_r   <= 1'b0;
      rd_err_r    <= 1'b0;
      ar_addr     <= {AXI_ADDR_WIDTH{1'b0}};
      ar_rem      <= 32'd0;
      arvalid_r   <= 1'b0;
      araddr_r    <= {AXI_ADDR_WIDTH{1'b0}};
      arlen_r     <= 8'd0;
      rd_out_cnt  <= 5'd0;
    end else if(MASTER_RST) begin
      rd_run      <= 1'b0;
      rd_done_r   <= 1'b0;
      rd_err_r    <= 1'b0;
      ar_rem      <= 32'd0;
      arvalid_r   <= 1'b0;
      rd_out_cnt  <= 5'd0;
    end else begin
      rd_done_r  <= 1'b0;
      if(rd_run)
        rd_out_cnt <= rd_out_cnt + {4'd0, ar_can_load} - {4'd0, r_end};

      if(!rd_run) begin
        if(RD_START) begin
          rd_run   <= 1'b1;
          rd_err_r <= 1'b0;
          ar_addr  <= {RD_ADRS[AXI_ADDR_WIDTH-1:AXI_OFFSET], {AXI_OFFSET{1'b0}}};
          ar_rem   <= rd_beats_all;
        end
      end else begin
        if(ar_can_load) begin
          arvalid_r <= 1'b1;
          araddr_r  <= ar_addr;
          arlen_r   <= ar_n[7:0] - 8'd1;
          ar_addr   <= ar_addr + ({{(AXI_ADDR_WIDTH-9){1'b0}}, ar_n} << AXI_OFFSET);
          ar_rem    <= ar_rem - {23'd0, ar_n};
        end else if(M_AXI_ARREADY) begin
          arvalid_r <= 1'b0;
        end

        if(r_hs && M_AXI_RRESP[1])
          rd_err_r <= 1'b1;

        if(ar_rem == 32'd0 && rd_out_cnt == 5'd0 && !arvalid_r) begin
          rd_run    <= 1'b0;
          rd_done_r <= 1'b1;
        end
      end
    end
  end

  //--------------------------------------------------------------------
  // AXI 信号赋值
  //--------------------------------------------------------------------
  // Write Address
  assign M_AXI_AWID         = 1'b0;
  assign M_AXI_AWADDR       = awaddr_r;
  assign M_AXI_AWLEN        = awlen_r;
  assign M_AXI_AWSIZE       = AXI_SIZE;
  assign M_AXI_AWBURST      = 2'b01;            // INCR
  assign M_AXI_AWLOCK       = 1'b0;
  assign M_AXI_AWCACHE      = 4'b0011;
  assign M_AXI_AWPROT       = 3'b000;
  assign M_AXI_AWQOS        = 4'b0000;
  assign M_AXI_AWUSER       = 1'b1;
  assign M_AXI_AWVALID      = awvalid_r;

  // Write Data
  assign M_AXI_WDATA        = w_data_r;
  assign M_AXI_WSTRB        = {AXI_BYTES{1'b1}};
  assign M_AXI_WLAST        = w_last_r;
  assign M_AXI_WUSER        = 1'b1;
  assign M_AXI_WVALID       = w_valid_r;
  assign WR_FIFO_RE         = w_hs;

  // Write Response
  assign M_AXI_BREADY       = 1'b1;

  // Read Address
  assign M_AXI_ARID         = 1'b0;
  assign M_AXI_ARADDR       = araddr_r;
  assign M_AXI_ARLEN        = arlen_r;
  assign M_AXI_ARSIZE       = AXI_SIZE;
  assign M_AXI_ARBURST      = 2'b01;            // INCR
  assign M_AXI_ARLOCK       = 1'b0;
  assign M_AXI_ARCACHE      = 4'b0011;
  assign M_AXI_ARPROT       = 3'b000;
  assign M_AXI_ARQOS        = 4'b0000;
  assign M_AXI_ARUSER       = 1'b1;
  assign M_AXI_ARVALID      = arvalid_r;

  // Read Data
  assign M_AXI_RREADY       = ~RD_FIFO_FULL;
  assign RD_FIFO_WE         = r_hs;
  assign RD_FIFO_DATA       = M_AXI_RDATA;

  // 用户侧状态
  assign WR_READY           = ~wr_run;
  assign WR_DONE            = wr_done_r;
  assign WR_ERR             = wr_err_r;
  assign RD_READY           = ~rd_run;
  assign RD_DONE            = rd_done_r;
  assign RD_ERR             = rd_err_r;

  assign DEBUG              = {15'd0, rd_err_r, wr_err_r, arvalid_r, awvalid_r, w_active,
                               rd_run, wr_run, rd_out_cnt, wr_out_cnt};

endmodule
