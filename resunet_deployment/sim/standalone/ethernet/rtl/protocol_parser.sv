//========================================================================================
// 文件类型: .sv
// 模块功能: CT-FPGA 以太网传输协议 V1 帧解析器 (接收侧)
//
// 微架构:
//   - 输入为 udp_rx 输出的 UDP 载荷字节流, 实测该流与 UDP 载荷逐字节对齐、零延迟
//   - 单拍一字节的顺序解析, 字段区段完全由 byte_cnt_r 组合译码 (不依赖"上一拍"判断)
//   - 内嵌 CRC-32/ISO-HDLC 引擎, 对 [Version .. Body尾] 做真校验
//   - frame_valid_o 仅在 Magic/Version/Header_Len/Tail/长度/CRC 全部通过时脉冲一拍
//
// 修正记录 (相对旧版 sim 版):
//   旧版在 st_idle 进入时把 byte_cnt_r 清零, 导致第 0 字节被判为前导、
//   第 1 字节被当作 magic[15:8], 整帧前移一字节, 永远解析不出正确 Magic。
//   本版在 st_recv 期间 byte_cnt_r 即为当前字节下标 (0 = 载荷首字节)。
//========================================================================================

module protocol_parser (
    input  logic        clk_i            ,  // 时钟
    input  logic        rst_n_i          ,  // 复位, 低有效

    // 来自 udp_rx
    input  logic        udp_rx_en_i      ,  // 载荷字节有效 (每字节一拍)
    input  logic [7:0]  udp_rx_data_i    ,  // 载荷字节
    input  logic        udp_rx_done_i    ,  // 单包接收完成
    input  logic [15:0] udp_rx_bytes_i   ,  // 载荷总字节数

    // 解析结果 (在 frame_valid_o 有效时一并有效)
    output logic        frame_valid_o    ,
    output logic        frame_error_o    ,
    output logic [7:0]  msg_type_o       ,
    output logic [31:0] transfer_id_o    ,
    output logic [31:0] sequence_o       ,
    output logic [15:0] body_len_o       ,

    // Body 字节流
    output logic        body_en_o        ,
    output logic [7:0]  body_data_o      ,
    output logic [15:0] body_cnt_o
);

//========================================================================================
// 协议常量
//========================================================================================
localparam logic [15:0] MAGIC       = 16'h55AA;
localparam logic [15:0] TAIL        = 16'hAA55;
localparam logic [7:0]  VERSION     = 8'h01;
localparam logic [15:0] HEADER_LEN  = 16'd16;
localparam logic [15:0] TRAILER_LEN = 16'd6;   // CRC32(4) + Tail(2)

//========================================================================================
// 状态机
//========================================================================================
typedef enum logic [1:0] {
    ST_IDLE ,   // 等待载荷起始
    ST_RECV ,   // 逐字节接收 + 解析
    ST_DONE     // 判定并输出
} state_t;

state_t state_r, state_nxt;

//========================================================================================
// 寄存器
//========================================================================================
logic [15:0] byte_cnt_r;
logic [15:0] total_len_r;      // 本帧应有总长 = 16 + body_len + 6
logic [15:0] body_len_r;
logic [7:0]  msg_type_r;
logic [31:0] transfer_id_r;
logic [31:0] sequence_r;
logic [15:0] header_len_r;
logic [15:0] magic_r;
logic [15:0] tail_r;
logic [31:0] crc_recv_r;
logic [31:0] crc_calc_w;       // 引擎输出
logic [15:0] body_cnt_r;

logic        crc_init_w;
logic        crc_en_w;

logic [7:0]  data_w;

// 接收侧错误标志 (寄存, 供末拍判定)
logic        magic_bad_r;
logic        ver_bad_r;
logic        hlen_bad_r;

//========================================================================================
// 字节区段译码 (当前字节在帧中的归属)
//========================================================================================
logic        in_magic_w;
logic        in_crc_w;
logic        in_tail_w;
logic        recv_act_w;      // "正在吃字节"——含 ST_IDLE->ST_RECV 的过渡拍

// recv_act_w 的含义:
//   udp_rx 在 st_rx_data 期间 rec_en 连续为高。第一个字节到达时本模块仍在 ST_IDLE,
//   下一拍才进 ST_RECV。若只认 (state_r == ST_RECV), 首字节会被丢弃、整帧错位一字节
//   (旧版 sim 正是这么错的)。因此把过渡拍也算作有效接收拍,
//   这样 byte_cnt_r 在解析首字节时恰好为 0。
assign recv_act_w   = (state_r == ST_RECV) || ((state_r == ST_IDLE) && udp_rx_en_i);

assign data_w       = data_sr;      // 对齐后的当前字节
assign in_magic_w   = (byte_cnt_r < 16'd2);
assign in_crc_w     = (byte_cnt_r >= (HEADER_LEN + body_len_r)) &&
                      (byte_cnt_r <  (HEADER_LEN + body_len_r + 16'd4));
assign in_tail_w    = (byte_cnt_r >= (HEADER_LEN + body_len_r + 16'd4)) &&
                      (byte_cnt_r <  (HEADER_LEN + body_len_r + 16'd6));
assign total_len_r  = HEADER_LEN + body_len_r + TRAILER_LEN;

// CRC 覆盖: 从 Version (下标2) 到 Body 尾 (下标 16+body_len-1)
assign crc_en_w     = recv_act_w && en_sr                            &&
                      (byte_cnt_r >= 16'd2)                          &&
                      (byte_cnt_r <  HEADER_LEN + body_len_r);
// 仅在 ST_IDLE 复位 CRC; 进了 ST_DONE 必须保持最终值供比较 (否则比较时被清空)
assign crc_init_w   = (state_r == ST_IDLE);

//========================================================================================
// CRC 引擎
//========================================================================================
crc32_iso_hdlc u_crc (
    .clk_i      (clk_i     ),
    .rst_n_i    (rst_n_i   ),
    .crc_init_i (crc_init_w),
    .crc_en_i   (crc_en_w  ),
    .data_i     (data_w    ),
    .crc_o      (crc_calc_w)
);

//========================================================================================
// 状态转移: 时序
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        state_r <= ST_IDLE;
    else
        state_r <= state_nxt;
end

//========================================================================================
// 状态转移: 组合
//========================================================================================
always_comb begin
    state_nxt = state_r;

    case (state_r)
        ST_IDLE : begin
            if (udp_rx_en_i)
                state_nxt = ST_RECV;
        end

        ST_RECV : begin
            // 对齐后: 处理到最后一字节时 byte_cnt_r == total_len-1
            if (recv_act_w && en_sr && (byte_cnt_r == total_len_r - 16'd1))
                state_nxt = ST_DONE;
            // 兜底: udp_rx 提前结束 (截断/异常短帧)
            else if (!udp_rx_en_i && udp_rx_done_i)
                state_nxt = ST_DONE;
        end

        ST_DONE : state_nxt = ST_IDLE;

        default : state_nxt = ST_IDLE;
    endcase
end

//========================================================================================
// 字节计数
//   byte_cnt_r 的含义是"当前正在解析的字节下标"。
//   udp_rx 连拍给字节; 首字节到达时本模块尚在 ST_IDLE, 下一拍才进 ST_RECV。
//   为了统一对齐, 内部把 使能/数据 各延迟一拍 (en_sr/data_sr), 与 ST_IDLE->ST_RECV
//   的过渡拍正好抵消, 于是: 收到第 1 个字节时 byte_cnt_r=0 且 data_sr 也是该字节,
//   之后每个被接收的字节简单 +1。实测若在接收拍直接 +1, 下标会超前一个, 整帧错位。
//========================================================================================
logic        en_sr;      // 延迟一拍的字节使能
logic [7:0]  data_sr;    // 延迟一拍的数据

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        en_sr   <= 1'b0;
        data_sr <= 8'd0;
    end
    else begin
        en_sr   <= udp_rx_en_i;
        data_sr <= udp_rx_data_i;
    end
end

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        byte_cnt_r <= 16'd0;
    else if (recv_act_w) begin
        if (en_sr)
            byte_cnt_r <= byte_cnt_r + 16'd1;
    end
    else
        byte_cnt_r <= 16'd0;
end

//========================================================================================
// 字段解析
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        magic_r       <= 16'd0;
        msg_type_r    <= 8'd0;
        transfer_id_r <= 32'd0;
        header_len_r  <= 16'd0;
        body_len_r    <= 16'd0;
        sequence_r    <= 32'd0;
        tail_r        <= 16'd0;
        crc_recv_r    <= 32'd0;

        magic_bad_r   <= 1'b0;
        ver_bad_r     <= 1'b0;
        hlen_bad_r    <= 1'b0;
    end
    else if (state_r == ST_IDLE) begin
        magic_r       <= 16'd0;
        body_len_r    <= 16'd0;
        tail_r        <= 16'd0;
        crc_recv_r    <= 32'd0;

        magic_bad_r   <= 1'b0;
        ver_bad_r     <= 1'b0;
        hlen_bad_r    <= 1'b0;
    end
    else if (recv_act_w && en_sr) begin
        case (byte_cnt_r)
            // Magic
            16'd0   : magic_r[15:8]        <= data_w;
            16'd1   : begin
                      magic_r[7:0]         <= data_w;
                      magic_bad_r          <= (magic_r[15:8] != MAGIC[15:8]) ||
                                              (data_w          != MAGIC[7:0]);
                      // 注意: 此处不能校验 udp_rx_bytes_i。
                      // udp_rx 的 rec_byte_num 是在"最后一个字节"那一拍才被写入的,
                      // 收帧过程中它一直是 0/上一次的值。长度校验必须放到 ST_DONE,
                      // 那时 rec_byte_num 才是本帧真实长度 (见 len_ok_w)。
                      end
            // Version
            16'd2   : ver_bad_r            <= (data_w != VERSION);
            // Msg_Type
            16'd3   : msg_type_r           <= data_w;
            // Transfer_ID
            16'd4   : transfer_id_r[31:24] <= data_w;
            16'd5   : transfer_id_r[23:16] <= data_w;
            16'd6   : transfer_id_r[15:8]  <= data_w;
            16'd7   : transfer_id_r[7:0]   <= data_w;
            // Header_Len
            16'd8   : header_len_r[15:8]   <= data_w;
            16'd9   : begin
                      header_len_r[7:0]    <= data_w;
                      hlen_bad_r           <= (header_len_r[15:8] != HEADER_LEN[15:8]) ||
                                              (data_w              != HEADER_LEN[7:0]);
                      end
            // Body_Len
            16'd10  : body_len_r[15:8]     <= data_w;
            16'd11  : body_len_r[7:0]      <= data_w;
            // Sequence
            16'd12  : sequence_r[31:24]    <= data_w;
            16'd13  : sequence_r[23:16]    <= data_w;
            16'd14  : sequence_r[15:8]     <= data_w;
            16'd15  : sequence_r[7:0]      <= data_w;
            // CRC32 (大端)
            16'd16  : if (body_len_r == 16'd0) crc_recv_r[31:24] <= data_w;
            16'd17  : if (body_len_r == 16'd0) crc_recv_r[23:16] <= data_w;
            16'd18  : if (body_len_r == 16'd0) crc_recv_r[15:8]  <= data_w;
            16'd19  : if (body_len_r == 16'd0) crc_recv_r[7:0]   <= data_w;
            // Tail (大端)
            16'd20  : if (body_len_r == 16'd0) tail_r[15:8]      <= data_w;
            16'd21  : if (body_len_r == 16'd0) tail_r[7:0]       <= data_w;
            default : begin
                // 通用: CRC 与 Tail 的区段由 body_len_r 决定
                if (byte_cnt_r == HEADER_LEN + body_len_r)
                    crc_recv_r[31:24] <= data_w;
                else if (byte_cnt_r == HEADER_LEN + body_len_r + 16'd1)
                    crc_recv_r[23:16] <= data_w;
                else if (byte_cnt_r == HEADER_LEN + body_len_r + 16'd2)
                    crc_recv_r[15:8]  <= data_w;
                else if (byte_cnt_r == HEADER_LEN + body_len_r + 16'd3)
                    crc_recv_r[7:0]   <= data_w;
                else if (byte_cnt_r == HEADER_LEN + body_len_r + 16'd4)
                    tail_r[15:8]      <= data_w;
                else if (byte_cnt_r == HEADER_LEN + body_len_r + 16'd5)
                    tail_r[7:0]       <= data_w;
                else ;
            end
        endcase
    end
end

//========================================================================================
// Body 计数
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        body_cnt_r <= 16'd0;
    else if (!recv_act_w)
        body_cnt_r <= 16'd0;
    else if (en_sr && (byte_cnt_r >= HEADER_LEN) &&
             (byte_cnt_r < HEADER_LEN + body_len_r))
        body_cnt_r <= body_cnt_r + 16'd1;
end

//========================================================================================
// 末拍判定与输出
//========================================================================================
logic crc_ok_w;
logic tail_ok_w;
logic len_ok_w;

// CRC 引擎在本拍输出的 crc_calc_w 已包含"最新吃过字节"的迭代结果,
// 故当最后一个被 CRC 覆盖的字节(下标 16+body_len-1)在拍上时, crc_calc_w 即为最终值。
assign crc_ok_w  = (crc_recv_r == crc_calc_w);
assign tail_ok_w = (tail_r == TAIL);
assign len_ok_w  = (udp_rx_bytes_i == total_len_r);

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        frame_valid_o <= 1'b0;
        frame_error_o <= 1'b0;
    end
    else if (state_r == ST_DONE) begin
        if (!magic_bad_r && !ver_bad_r && !hlen_bad_r &&
            tail_ok_w && len_ok_w && crc_ok_w) begin
            frame_valid_o <= 1'b1;
            frame_error_o <= 1'b0;
        end
        else begin
            frame_valid_o <= 1'b0;
            frame_error_o <= 1'b1;
        end
    end
    else begin
        frame_valid_o <= 1'b0;
        frame_error_o <= 1'b0;
    end
end

//========================================================================================
// 输出赋值
//========================================================================================
assign msg_type_o    = msg_type_r;
assign transfer_id_o = transfer_id_r;
assign sequence_o    = sequence_r;
assign body_len_o    = body_len_r;

assign body_en_o     = recv_act_w && en_sr &&
                       (byte_cnt_r >= HEADER_LEN) &&
                       (byte_cnt_r <  HEADER_LEN + body_len_r);
assign body_data_o   = data_w;
assign body_cnt_o    = body_cnt_r;

endmodule

//========================================================================================
// 说明:
// 1. 状态机: ST_IDLE -> ST_RECV -> ST_DONE -> ST_IDLE
// 2. 区段由 byte_cnt_r 组合译码, 不依赖上一拍状态, 消除旧版一字节错位
// 3. CRC 覆盖 [Version .. Body尾], 与 PC 端 zlib.crc32 完全一致
//========================================================================================
