//========================================================================================
// 文件类型: .sv
// 模块功能: CT-FPGA 以太网传输协议 V1 响应帧构建器 (发送侧)
//
// 微架构:
//   - 上游预装完整 Body 到 build_body_i[0 .. body_len_i-1], 拉高 build_start_i
//   - 本模块单拍一字节串行吐出整帧: 通用头16 + Body + CRC32(4) + Tail(2)
//   - tx_valid_o 指示 tx_data_o 当前有效, 由下游写入发送缓存 (异步于 udp_tx 取数节奏)
//   - CRC 直接取 crc32_iso_hdlc 的组合输出 crc_o, 不额外锁存:
//       byte_cnt == 16+body_len 时 crc_en 已拉低, crc_r 定格, crc_o 即为最终值;
//       该拍恰好是 CRC 首字节, 因此无需等待, 也不会漏掉 Body 最后一字节。
//
// 与 PC 端一致性:
//   CRC 覆盖 [Version .. Body尾], 结果 = zlib.crc32(帧[2 : 16+body_len]), 大端输出。
//========================================================================================

module protocol_builder #(
    parameter int BODY_MAX = 288    // 最大 Body 字节数 (16 头 + 8层×32字节位图 = 272)
) (
    input  logic        clk_i          ,  // 时钟
    input  logic        rst_n_i        ,  // 复位, 低有效

    // 构建请求
    input  logic        build_start_i  ,  // 单拍脉冲: 开始构建本帧
    input  logic [7:0]  msg_type_i     ,  // Msg_Type
    input  logic [31:0] transfer_id_i  ,  // Transfer_ID
    input  logic [31:0] sequence_i     ,  // Sequence
    input  logic [15:0] body_len_i     ,  // Body_Len
    input  logic [7:0]  build_body_i [0:BODY_MAX-1],   // Body 预装数组

    // 串行帧输出
    output logic [7:0]  tx_data_o      ,  // 帧字节
    output logic        tx_valid_o     ,  // 本拍 tx_data_o 有效
    output logic [15:0] tx_bytes_o     ,  // 帧总长 = 16 + body_len + 6
    output logic        tx_done_o         // 本帧最后一字节已吐出 (单拍脉冲)
);

//========================================================================================
// 协议常量
//========================================================================================
localparam logic [15:0] MAGIC      = 16'h55AA;
localparam logic [15:0] TAIL       = 16'hAA55;
localparam logic [7:0]  VERSION    = 8'h01;
localparam logic [15:0] HEADER_LEN = 16'd16;
localparam logic [15:0] TRAILER_LEN= 16'd6;

//========================================================================================
// 状态机
//========================================================================================
typedef enum logic [1:0] {
    ST_IDLE ,
    ST_SEND ,
    ST_DONE
} state_t;

state_t state_r, state_nxt;

//========================================================================================
// 寄存器 / 线网
//========================================================================================
logic [15:0] total_len_r;
logic [15:0] byte_cnt_r;
logic [15:0] body_len_r;
logic [7:0]  msg_type_r;
logic [31:0] transfer_id_r;
logic [31:0] sequence_r;

logic [31:0] crc_w;
logic        crc_init_w;
logic        crc_en_w;

logic [7:0]  tx_data_w;

//========================================================================================
// CRC 引擎: 覆盖下标 [2, 15+body_len]  (Version .. Body 尾)
//   body_len=0 时覆盖 [2,15] (整个头), 与 PC 端 zlib.crc32(header[2:]) 一致
//========================================================================================
assign crc_init_w = (state_r != ST_SEND);
assign crc_en_w   = (state_r == ST_SEND)          &&
                    (byte_cnt_r >= 16'd2)         &&
                    (byte_cnt_r <  HEADER_LEN + body_len_r);

crc32_iso_hdlc u_crc (
    .clk_i      (clk_i     ),
    .rst_n_i    (rst_n_i   ),
    .crc_init_i (crc_init_w),
    .crc_en_i   (crc_en_w  ),
    .data_i     (tx_data_w ),
    .crc_o      (crc_w     )
);

//========================================================================================
// 状态转移
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        state_r <= ST_IDLE;
    else
        state_r <= state_nxt;
end

always_comb begin
    state_nxt = state_r;

    case (state_r)
        ST_IDLE : if (build_start_i)                     state_nxt = ST_SEND;
        ST_SEND : if (byte_cnt_r == total_len_r - 16'd1)  state_nxt = ST_DONE;
        ST_DONE :                                         state_nxt = ST_IDLE;
        default :                                         state_nxt = ST_IDLE;
    endcase
end

//========================================================================================
// 参数锁存
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        msg_type_r    <= 8'd0;
        transfer_id_r <= 32'd0;
        sequence_r    <= 32'd0;
        body_len_r    <= 16'd0;
        total_len_r   <= 16'd0;
    end
    else if (state_r == ST_IDLE && build_start_i) begin
        msg_type_r    <= msg_type_i;
        transfer_id_r <= transfer_id_i;
        sequence_r    <= sequence_i;
        body_len_r    <= body_len_i;
        total_len_r   <= HEADER_LEN + body_len_i + TRAILER_LEN;
    end
end

//========================================================================================
// 字节计数
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        byte_cnt_r <= 16'd0;
    else if (state_r == ST_SEND)
        byte_cnt_r <= byte_cnt_r + 16'd1;
    else
        byte_cnt_r <= 16'd0;
end

//========================================================================================
// 串行输出 (大端)
//========================================================================================
always_comb begin
    tx_data_w = 8'd0;

    if (state_r == ST_SEND) begin
        if (byte_cnt_r < HEADER_LEN) begin
            // ---------------- 通用头 16 字节 ----------------
            case (byte_cnt_r)
                16'd0  : tx_data_w = MAGIC[15:8];
                16'd1  : tx_data_w = MAGIC[7:0];
                16'd2  : tx_data_w = VERSION;
                16'd3  : tx_data_w = msg_type_r;
                16'd4  : tx_data_w = transfer_id_r[31:24];
                16'd5  : tx_data_w = transfer_id_r[23:16];
                16'd6  : tx_data_w = transfer_id_r[15:8];
                16'd7  : tx_data_w = transfer_id_r[7:0];
                16'd8  : tx_data_w = HEADER_LEN[15:8];
                16'd9  : tx_data_w = HEADER_LEN[7:0];
                16'd10 : tx_data_w = body_len_r[15:8];
                16'd11 : tx_data_w = body_len_r[7:0];
                16'd12 : tx_data_w = sequence_r[31:24];
                16'd13 : tx_data_w = sequence_r[23:16];
                16'd14 : tx_data_w = sequence_r[15:8];
                16'd15 : tx_data_w = sequence_r[7:0];
                default: tx_data_w = 8'd0;
            endcase
        end
        else if (byte_cnt_r < HEADER_LEN + body_len_r) begin
            // ---------------- Body ----------------
            tx_data_w = build_body_i[byte_cnt_r - HEADER_LEN];
        end
        else if (byte_cnt_r < HEADER_LEN + body_len_r + 16'd4) begin
            // ---------------- CRC32 大端 (crc_r 已定格) ----------------
            case (byte_cnt_r - HEADER_LEN - body_len_r)
                16'd0 : tx_data_w = crc_w[31:24];
                16'd1 : tx_data_w = crc_w[23:16];
                16'd2 : tx_data_w = crc_w[15:8];
                16'd3 : tx_data_w = crc_w[7:0];
                default: tx_data_w = 8'd0;
            endcase
        end
        else begin
            // ---------------- Tail 大端 ----------------
            case (byte_cnt_r - HEADER_LEN - body_len_r - 16'd4)
                16'd0 : tx_data_w = TAIL[15:8];
                16'd1 : tx_data_w = TAIL[7:0];
                default: tx_data_w = 8'd0;
            endcase
        end
    end
end

assign tx_data_o  = tx_data_w;
assign tx_valid_o = (state_r == ST_SEND);
assign tx_bytes_o = total_len_r;

//========================================================================================
// 完成脉冲
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        tx_done_o <= 1'b0;
    else
        tx_done_o <= (state_r == ST_SEND) &&
                     (byte_cnt_r == total_len_r - 16'd1);
end

endmodule

//========================================================================================
// 说明:
// 1. 状态机: ST_IDLE -> ST_SEND -> ST_DONE -> ST_IDLE
// 2. 逐拍无空泡输出, tx_valid_o 持续为高; 下游按 tx_valid_o 写入发送缓存
// 3. CRC 取自 crc32_iso_hdlc 组合输出, 与 PC 端 zlib.crc32 逐位一致
//========================================================================================
