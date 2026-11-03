//========================================================================================
// 文件类型: .sv
// 模块功能: 以太网接收发送顶层 (Verilator 仿真验证版, 不含 DDR / 不含任何 IP 核)
//
// 微架构:
//   GMII RX -> udp_rx -> protocol_parser(真 CRC32 校验) -> 响应控制器
//                                                              |
//                       GMII TX <- udp_tx <- tx_buf <- protocol_builder(真 CRC32 生成)
//
//   发送侧为何需要 tx_buf:
//     protocol_builder 是"每拍一字节"的突发输出; 而 udp_tx 要先发前导码/以太头/IP头
//     共约 50 拍才进入 st_tx_data, 之后按 tx_req 逐字节取数。两者节奏不同,
//     因此 builder 的输出必须先入缓存, 由 udp_tx 通过 tx_req 按需读取。
//
//   响应控制器维护真实接收状态:
//     - IMAGE_BEGIN  : 校验数据契约(协议 §7.3), 回 ACK(ACCEPTED / INVALID_PARAMETER)
//     - IMAGE_DATA   : 按 (Slice_ID, Packet_Idx) 置位接收位图, 不回帧
//     - BATCH_END    : 统计缺包, 回 BATCH_STATUS(COMPLETE / MISSING + 缺包位图)
//     - IMAGE_END    : 核对整卷包数, 回 IMAGE_READY
//     - INFER_TRIGGER: 回 INFER_DONE(占位结果 0xDEADBEEF)
//
//   与旧 sim 版的关键差别: 位图/包数/状态码全部由真实接收过程决定,
//   不再硬编码 256 / Status=0, 因此缺包重传路径可以被真正仿真到。
//========================================================================================

module eth_top (
    input  logic        clk_i            ,  // 125MHz GMII 时钟
    input  logic        rst_n_i          ,  // 复位, 低有效

    // GMII 接收
    input  logic        gmii_rx_dv_i     ,  // 接收数据有效
    input  logic [7:0]  gmii_rxd_i       ,  // 接收数据

    // GMII 发送
    output logic        gmii_tx_en_o     ,  // 发送数据有效
    output logic [7:0]  gmii_txd_o       ,  // 发送数据

    // 观测端口 (仅供仿真断言)
    output logic [7:0]  rx_msg_type_o    ,
    output logic        rx_frame_valid_o ,
    output logic        rx_frame_error_o ,
    output logic [7:0]  tx_msg_type_o    ,
    output logic        tx_frame_done_o  ,
    output logic [31:0] rx_pkt_cnt_o     ,  // 累计收到的 IMAGE_DATA 数
    output logic [31:0] rx_bad_crc_cnt_o ,  // 累计帧错误数
    output logic [15:0] rx_batch_cnt_o      // 累计完成的批次
);

//========================================================================================
// 参数与常量
//========================================================================================
localparam logic [47:0] BOARD_MAC = 48'h00_11_22_33_44_55;
localparam logic [31:0] BOARD_IP  = {8'd192, 8'd168, 8'd1, 8'd10};

// 消息类型
localparam logic [7:0] MSG_IMAGE_DATA    = 8'h01;
localparam logic [7:0] MSG_INFER_TRIGGER = 8'h02;
localparam logic [7:0] MSG_IMAGE_BEGIN   = 8'h03;
localparam logic [7:0] MSG_IMAGE_END     = 8'h04;
localparam logic [7:0] MSG_BATCH_END     = 8'h05;
localparam logic [7:0] MSG_ACK           = 8'h81;
localparam logic [7:0] MSG_INFER_DONE    = 8'h82;
localparam logic [7:0] MSG_BATCH_STATUS  = 8'h83;
localparam logic [7:0] MSG_IMAGE_READY   = 8'h84;

// ACK 状态
localparam logic [7:0] ACK_ACCEPTED      = 8'h00;
localparam logic [7:0] ACK_INVALID_PARAM = 8'h02;

// BATCH_STATUS 状态
localparam logic [7:0] BATCH_COMPLETE    = 8'h00;
localparam logic [7:0] BATCH_MISSING     = 8'h01;

// IMAGE_READY 状态
localparam logic [7:0] READY_OK          = 8'h00;
localparam logic [7:0] READY_MISSING     = 8'h01;
localparam logic [7:0] READY_PARAM_MISMATCH = 8'h04;

// INFER_DONE 状态
localparam logic [7:0] INFER_OK          = 8'h00;

// 数据契约 (协议 §7.3)
localparam logic [15:0] REQ_WIDTH         = 16'd512;
localparam logic [15:0] REQ_HEIGHT        = 16'd512;
localparam logic [15:0] REQ_PKT_PIX_BYTES = 16'd1024;
localparam logic [15:0] REQ_PKT_PER_SLICE = 16'd256;
localparam logic [31:0] REQ_SLICE_STRIDE  = 32'd262144;
localparam logic [15:0] REQ_DEPTH         = 16'd33;
localparam logic [15:0] REQ_CENTER_INDEX  = 16'd16;
localparam logic [15:0] REQ_PATCH_SIZE    = 16'd96;

// 容量参数
localparam int BATCH_SLICES_MAX  = 8;                             // 单批最大层数
localparam int BITMAP_WORDS      = BATCH_SLICES_MAX * 256;        // 位图 bit 数
localparam int BITMAP_BYTES_MAX  = BITMAP_WORDS / 8;              // 256 字节
localparam int BSTATUS_HEAD_LEN  = 16;                            // BATCH_STATUS 头
localparam int BODY_MAX          = BSTATUS_HEAD_LEN + BITMAP_BYTES_MAX;  // 272
localparam int TX_BUF_LEN        = 320;                           // 发送缓存

//========================================================================================
// udp_rx (例程原版)
//========================================================================================
logic        udp_rx_done_w;
logic        udp_rx_en_w;
logic [7:0]  udp_rx_data_w;
logic [15:0] udp_rx_bytes_w;

udp_rx #(
    .BOARD_MAC (BOARD_MAC),
    .BOARD_IP  (BOARD_IP )
) u_udp_rx (
    .clk          (clk_i         ),
    .rst_n        (rst_n_i       ),
    .gmii_rx_dv   (gmii_rx_dv_i  ),
    .gmii_rxd     (gmii_rxd_i    ),
    .rec_pkt_done (udp_rx_done_w ),
    .rec_en       (udp_rx_en_w   ),
    .rec_data     (udp_rx_data_w ),
    .rec_byte_num (udp_rx_bytes_w)
);

//========================================================================================
// protocol_parser (真 CRC32 校验)
//========================================================================================
logic        frame_valid_w;
logic        frame_error_w;
logic [7:0]  rx_msg_type_w;
logic [31:0] rx_transfer_id_w;
logic [31:0] rx_sequence_w;
logic [15:0] rx_body_len_w;
logic        body_en_w;
logic [7:0]  body_data_w;
logic [15:0] body_cnt_w;

protocol_parser u_parser (
    .clk_i          (clk_i           ),
    .rst_n_i        (rst_n_i         ),
    .udp_rx_en_i    (udp_rx_en_w     ),
    .udp_rx_data_i  (udp_rx_data_w   ),
    .udp_rx_done_i  (udp_rx_done_w   ),
    .udp_rx_bytes_i (udp_rx_bytes_w  ),
    .frame_valid_o  (frame_valid_w   ),
    .frame_error_o  (frame_error_w   ),
    .msg_type_o     (rx_msg_type_w   ),
    .transfer_id_o  (rx_transfer_id_w),
    .sequence_o     (rx_sequence_w   ),
    .body_len_o     (rx_body_len_w   ),
    .body_en_o      (body_en_w       ),
    .body_data_o    (body_data_w     ),
    .body_cnt_o     (body_cnt_w      )
);

//========================================================================================
// Body 字段捕获
//========================================================================================
logic [31:0] begin_total_slices_r;
logic [15:0] begin_width_r;
logic [15:0] begin_height_r;
logic [7:0]  begin_bytes_per_pixel_r;
logic [7:0]  begin_dtype_r;
logic [31:0] begin_pkt_pix_bytes_r;
logic [31:0] begin_pkt_per_slice_r;
logic [31:0] begin_slice_stride_r;
logic [63:0] begin_total_bytes_r;
logic [63:0] begin_base_addr_r;
logic [31:0] begin_batch_slices_r;
logic [31:0] begin_expected_packets_r;
logic [15:0] begin_depth_r;
logic [15:0] begin_center_index_r;
logic [15:0] begin_patch_size_r;

logic [15:0] be_batch_id_r;
logic [15:0] be_first_slice_r;
logic [15:0] be_slice_count_r;
logic [31:0] be_expected_packets_r;

logic [31:0] ie_expected_packets_r;

logic [31:0] it_task_id_r;
logic [31:0] it_center_slice_r;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        begin_total_slices_r     <= 32'd0;
        begin_width_r            <= 16'd0;
        begin_height_r           <= 16'd0;
        begin_bytes_per_pixel_r  <= 8'd0;
        begin_dtype_r            <= 8'd0;
        begin_pkt_pix_bytes_r    <= 32'd0;
        begin_pkt_per_slice_r    <= 32'd0;
        begin_slice_stride_r     <= 32'd0;
        begin_total_bytes_r      <= 64'd0;
        begin_base_addr_r        <= 64'd0;
        begin_batch_slices_r     <= 32'd0;
        begin_expected_packets_r <= 32'd0;
        begin_depth_r            <= 16'd0;
        begin_center_index_r     <= 16'd0;
        begin_patch_size_r       <= 16'd0;

        be_batch_id_r            <= 16'd0;
        be_first_slice_r         <= 16'd0;
        be_slice_count_r         <= 16'd0;
        be_expected_packets_r    <= 32'd0;

        ie_expected_packets_r    <= 32'd0;

        it_task_id_r             <= 32'd0;
        it_center_slice_r        <= 32'd0;
    end
    else if (body_en_w) begin
        case (rx_msg_type_w)
            // ================= IMAGE_BEGIN (Body_Len = 76) =================
            MSG_IMAGE_BEGIN: begin
                case (body_cnt_w)
                    16'd0  : begin_total_slices_r[31:24]     <= body_data_w;
                    16'd1  : begin_total_slices_r[23:16]     <= body_data_w;
                    16'd2  : begin_total_slices_r[15:8]      <= body_data_w;
                    16'd3  : begin_total_slices_r[7:0]       <= body_data_w;

                    16'd4  : begin_width_r[15:8]             <= body_data_w;
                    16'd5  : begin_width_r[7:0]              <= body_data_w;
                    16'd6  : begin_height_r[15:8]            <= body_data_w;
                    16'd7  : begin_height_r[7:0]             <= body_data_w;

                    16'd8  : begin_bytes_per_pixel_r         <= body_data_w;
                    16'd9  : begin_dtype_r                   <= body_data_w;

                    16'd12 : begin_pkt_pix_bytes_r[31:24]    <= body_data_w;
                    16'd13 : begin_pkt_pix_bytes_r[23:16]    <= body_data_w;
                    16'd14 : begin_pkt_pix_bytes_r[15:8]     <= body_data_w;
                    16'd15 : begin_pkt_pix_bytes_r[7:0]      <= body_data_w;

                    16'd16 : begin_pkt_per_slice_r[31:24]    <= body_data_w;
                    16'd17 : begin_pkt_per_slice_r[23:16]    <= body_data_w;
                    16'd18 : begin_pkt_per_slice_r[15:8]     <= body_data_w;
                    16'd19 : begin_pkt_per_slice_r[7:0]      <= body_data_w;

                    16'd20 : begin_slice_stride_r[31:24]     <= body_data_w;
                    16'd21 : begin_slice_stride_r[23:16]     <= body_data_w;
                    16'd22 : begin_slice_stride_r[15:8]      <= body_data_w;
                    16'd23 : begin_slice_stride_r[7:0]       <= body_data_w;

                    16'd24 : begin_total_bytes_r[63:56]      <= body_data_w;
                    16'd25 : begin_total_bytes_r[55:48]      <= body_data_w;
                    16'd26 : begin_total_bytes_r[47:40]      <= body_data_w;
                    16'd27 : begin_total_bytes_r[39:32]      <= body_data_w;
                    16'd28 : begin_total_bytes_r[31:24]      <= body_data_w;
                    16'd29 : begin_total_bytes_r[23:16]      <= body_data_w;
                    16'd30 : begin_total_bytes_r[15:8]       <= body_data_w;
                    16'd31 : begin_total_bytes_r[7:0]        <= body_data_w;

                    16'd32 : begin_base_addr_r[63:56]        <= body_data_w;
                    16'd33 : begin_base_addr_r[55:48]        <= body_data_w;
                    16'd34 : begin_base_addr_r[47:40]        <= body_data_w;
                    16'd35 : begin_base_addr_r[39:32]        <= body_data_w;
                    16'd36 : begin_base_addr_r[31:24]        <= body_data_w;
                    16'd37 : begin_base_addr_r[23:16]        <= body_data_w;
                    16'd38 : begin_base_addr_r[15:8]         <= body_data_w;
                    16'd39 : begin_base_addr_r[7:0]          <= body_data_w;

                    16'd40 : begin_batch_slices_r[31:24]     <= body_data_w;
                    16'd41 : begin_batch_slices_r[23:16]     <= body_data_w;
                    16'd42 : begin_batch_slices_r[15:8]      <= body_data_w;
                    16'd43 : begin_batch_slices_r[7:0]       <= body_data_w;

                    16'd44 : begin_expected_packets_r[31:24] <= body_data_w;
                    16'd45 : begin_expected_packets_r[23:16] <= body_data_w;
                    16'd46 : begin_expected_packets_r[15:8]  <= body_data_w;
                    16'd47 : begin_expected_packets_r[7:0]   <= body_data_w;

                    16'd68 : begin_depth_r[15:8]             <= body_data_w;
                    16'd69 : begin_depth_r[7:0]              <= body_data_w;
                    16'd70 : begin_center_index_r[15:8]      <= body_data_w;
                    16'd71 : begin_center_index_r[7:0]       <= body_data_w;
                    16'd72 : begin_patch_size_r[15:8]        <= body_data_w;
                    16'd73 : begin_patch_size_r[7:0]         <= body_data_w;
                    default: ;
                endcase
            end

            // ================= BATCH_END (Body_Len = 16) =================
            MSG_BATCH_END: begin
                case (body_cnt_w)
                    16'd0  : be_batch_id_r[15:8]          <= body_data_w;
                    16'd1  : be_batch_id_r[7:0]           <= body_data_w;
                    16'd2  : be_first_slice_r[15:8]       <= body_data_w;
                    16'd3  : be_first_slice_r[7:0]        <= body_data_w;
                    16'd4  : be_slice_count_r[15:8]       <= body_data_w;
                    16'd5  : be_slice_count_r[7:0]        <= body_data_w;
                    16'd8  : be_expected_packets_r[31:24] <= body_data_w;
                    16'd9  : be_expected_packets_r[23:16] <= body_data_w;
                    16'd10 : be_expected_packets_r[15:8]  <= body_data_w;
                    16'd11 : be_expected_packets_r[7:0]   <= body_data_w;
                    default: ;
                endcase
            end

            // ================= IMAGE_END (Body_Len = 20) =================
            MSG_IMAGE_END: begin
                case (body_cnt_w)
                    16'd0  : ie_expected_packets_r[31:24] <= body_data_w;
                    16'd1  : ie_expected_packets_r[23:16] <= body_data_w;
                    16'd2  : ie_expected_packets_r[15:8]  <= body_data_w;
                    16'd3  : ie_expected_packets_r[7:0]   <= body_data_w;
                    default: ;
                endcase
            end

            // ================= INFER_TRIGGER (Body_Len = 24) =================
            MSG_INFER_TRIGGER: begin
                case (body_cnt_w)
                    16'd0  : it_task_id_r[31:24]      <= body_data_w;
                    16'd1  : it_task_id_r[23:16]      <= body_data_w;
                    16'd2  : it_task_id_r[15:8]       <= body_data_w;
                    16'd3  : it_task_id_r[7:0]        <= body_data_w;
                    16'd4  : it_center_slice_r[31:24] <= body_data_w;
                    16'd5  : it_center_slice_r[23:16] <= body_data_w;
                    16'd6  : it_center_slice_r[15:8]  <= body_data_w;
                    16'd7  : it_center_slice_r[7:0]   <= body_data_w;
                    default: ;
                endcase
            end

            default: ;
        endcase
    end
end

//========================================================================================
// IMAGE_DATA 定位字段捕获
//========================================================================================
logic [15:0] idata_slice_id_r;
logic [15:0] idata_packet_idx_r;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        idata_slice_id_r   <= 16'd0;
        idata_packet_idx_r <= 16'd0;
    end
    else if (body_en_w && (rx_msg_type_w == MSG_IMAGE_DATA)) begin
        case (body_cnt_w)
            16'd0 : idata_slice_id_r[15:8]   <= body_data_w;
            16'd1 : idata_slice_id_r[7:0]    <= body_data_w;
            16'd2 : idata_packet_idx_r[15:8] <= body_data_w;
            16'd3 : idata_packet_idx_r[7:0]  <= body_data_w;
            default: ;
        endcase
    end
end

//========================================================================================
// 批次游标: 当前批次的起始 Slice_ID
//   BATCH_END 里的 First_Slice_ID 直到批末才可知, 因此用游标维护:
//   IMAGE_BEGIN 归零; 每批结束后推进 slice_count 层。
//========================================================================================
logic [15:0] cur_first_slice_r;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        cur_first_slice_r <= 16'd0;
    else if (frame_valid_w && (rx_msg_type_w == MSG_IMAGE_BEGIN))
        cur_first_slice_r <= 16'd0;
    else if (frame_valid_w && (rx_msg_type_w == MSG_BATCH_END))
        cur_first_slice_r <= be_first_slice_r + be_slice_count_r;
end

//========================================================================================
// 接收位图 (bit = 1 表示已收到)
//========================================================================================
logic [BITMAP_WORDS-1:0] rx_bitmap_r;
logic [31:0] rx_pkt_cnt_r;
logic [31:0] rx_bad_crc_r;
logic [15:0] rx_batch_cnt_r;

logic [15:0] rel_slice_w;
logic [15:0] rel_bit_idx_w;

assign rel_slice_w   = idata_slice_id_r - cur_first_slice_r;
assign rel_bit_idx_w = (rel_slice_w * REQ_PKT_PER_SLICE) + idata_packet_idx_r;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        rx_bitmap_r <= '0;
    else if (frame_valid_w && (rx_msg_type_w == MSG_IMAGE_BEGIN))
        rx_bitmap_r <= '0;
    // 批次结束时清空, 使位图始终反映"当前批次"
    else if (frame_valid_w && (rx_msg_type_w == MSG_BATCH_END))
        rx_bitmap_r <= '0;
    else if (frame_valid_w && (rx_msg_type_w == MSG_IMAGE_DATA) &&
             (rel_bit_idx_w < BITMAP_WORDS))
        rx_bitmap_r[rel_bit_idx_w] <= 1'b1;
end

//========================================================================================
// 统计
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        rx_pkt_cnt_r   <= 32'd0;
        rx_bad_crc_r   <= 32'd0;
        rx_batch_cnt_r <= 16'd0;
    end
    else begin
        if (frame_valid_w && (rx_msg_type_w == MSG_IMAGE_BEGIN))
            rx_pkt_cnt_r <= 32'd0;
        else if (frame_valid_w && (rx_msg_type_w == MSG_IMAGE_DATA))
            rx_pkt_cnt_r <= rx_pkt_cnt_r + 32'd1;

        if (frame_error_w)
            rx_bad_crc_r <= rx_bad_crc_r + 32'd1;

        if (frame_valid_w && (rx_msg_type_w == MSG_BATCH_END))
            rx_batch_cnt_r <= rx_batch_cnt_r + 16'd1;
    end
end

assign rx_msg_type_o    = rx_msg_type_w;
assign rx_frame_valid_o = frame_valid_w;
assign rx_frame_error_o = frame_error_w;
assign rx_pkt_cnt_o     = rx_pkt_cnt_r;
assign rx_bad_crc_cnt_o = rx_bad_crc_r;
assign rx_batch_cnt_o   = rx_batch_cnt_r;

//========================================================================================
// 缺包统计 (仅统计本批次范围内的包)
//========================================================================================
logic [31:0] recv_in_batch_w;
logic [31:0] missing_cnt_w;

always_comb begin
    recv_in_batch_w = 32'd0;
    missing_cnt_w   = 32'd0;

    for (int i = 0; i < BITMAP_WORDS; i++) begin
        if (i < (be_slice_count_r * REQ_PKT_PER_SLICE)) begin
            if (rx_bitmap_r[i])
                recv_in_batch_w = recv_in_batch_w + 32'd1;
            else
                missing_cnt_w   = missing_cnt_w + 32'd1;
        end
    end
end

//========================================================================================
// IMAGE_BEGIN 参数校验 (协议 §7.3)
//========================================================================================
logic begin_param_ok_w;

always_comb begin
    begin_param_ok_w = (begin_bytes_per_pixel_r == 8'd1)                 &&
                       (begin_width_r           == REQ_WIDTH)            &&
                       (begin_height_r          == REQ_HEIGHT)           &&
                       (begin_dtype_r           == 8'h01)                &&
                       (begin_pkt_per_slice_r   == REQ_PKT_PER_SLICE)    &&
                       (begin_pkt_pix_bytes_r   == REQ_PKT_PIX_BYTES)    &&
                       (begin_slice_stride_r    == REQ_SLICE_STRIDE)     &&
                       (begin_depth_r           == REQ_DEPTH)            &&
                       (begin_center_index_r    == REQ_CENTER_INDEX)     &&
                       (begin_patch_size_r      == REQ_PATCH_SIZE)       &&
                       (begin_total_slices_r    >= 32'd1)                &&
                       (begin_batch_slices_r    >= 32'd1)                &&
                       (begin_batch_slices_r    <= BATCH_SLICES_MAX);
end

//========================================================================================
// 响应控制器
//========================================================================================
logic [7:0]  resp_msg_type_r;
logic [31:0] resp_transfer_id_r;
logic [31:0] resp_sequence_r;
logic [15:0] resp_body_len_r;
logic        resp_start_r;

logic [7:0]  resp_body_r [0:BODY_MAX-1];

// 本批位图字节数 = Slice_Count × 32
logic [15:0] bstatus_bitmap_bytes_w;

assign bstatus_bitmap_bytes_w = be_slice_count_r * 32'd32;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        resp_msg_type_r    <= 8'd0;
        resp_transfer_id_r <= 32'd0;
        resp_sequence_r    <= 32'd0;
        resp_body_len_r    <= 16'd0;
        resp_start_r       <= 1'b0;

        for (int i = 0; i < BODY_MAX; i++)
            resp_body_r[i] <= 8'd0;
    end
    else begin
        resp_start_r <= 1'b0;

        if (frame_valid_w) begin
            resp_transfer_id_r <= rx_transfer_id_w;
            resp_sequence_r    <= rx_sequence_w + 32'd1;

            case (rx_msg_type_w)
                // ==================== IMAGE_BEGIN -> ACK ====================
                MSG_IMAGE_BEGIN: begin
                    resp_msg_type_r <= MSG_ACK;
                    resp_body_len_r <= 16'd8;
                    resp_start_r    <= 1'b1;

                    // Acked_Msg_Type(1) Status(1) Reason(2) Acked_Sequence(4)
                    resp_body_r[0] <= MSG_IMAGE_BEGIN;
                    resp_body_r[1] <= begin_param_ok_w ? ACK_ACCEPTED
                                                       : ACK_INVALID_PARAM;
                    resp_body_r[2] <= 8'd0;
                    resp_body_r[3] <= 8'd0;
                    resp_body_r[4] <= rx_sequence_w[31:24];
                    resp_body_r[5] <= rx_sequence_w[23:16];
                    resp_body_r[6] <= rx_sequence_w[15:8];
                    resp_body_r[7] <= rx_sequence_w[7:0];
                end

                // ============== BATCH_END -> BATCH_STATUS (+位图) ==============
                MSG_BATCH_END: begin
                    resp_msg_type_r <= MSG_BATCH_STATUS;
                    resp_body_len_r <= BSTATUS_HEAD_LEN + bstatus_bitmap_bytes_w;
                    resp_start_r    <= 1'b1;

                    // Batch_ID(2) Status(1) Rsv(1) Expected(4) Received(4)
                    // Bitmap_Bytes(2) Rsv(2)
                    resp_body_r[0]  <= be_batch_id_r[15:8];
                    resp_body_r[1]  <= be_batch_id_r[7:0];
                    resp_body_r[2]  <= (missing_cnt_w == 32'd0) ? BATCH_COMPLETE
                                                                : BATCH_MISSING;
                    resp_body_r[3]  <= 8'd0;
                    resp_body_r[4]  <= be_expected_packets_r[31:24];
                    resp_body_r[5]  <= be_expected_packets_r[23:16];
                    resp_body_r[6]  <= be_expected_packets_r[15:8];
                    resp_body_r[7]  <= be_expected_packets_r[7:0];
                    resp_body_r[8]  <= recv_in_batch_w[31:24];
                    resp_body_r[9]  <= recv_in_batch_w[23:16];
                    resp_body_r[10] <= recv_in_batch_w[15:8];
                    resp_body_r[11] <= recv_in_batch_w[7:0];
                    resp_body_r[12] <= bstatus_bitmap_bytes_w[15:8];
                    resp_body_r[13] <= bstatus_bitmap_bytes_w[7:0];
                    resp_body_r[14] <= 8'd0;
                    resp_body_r[15] <= 8'd0;

                    // 缺包位图: 取反 (bit=1 表示缺失), 字节内 MSB-first, 与 PC 端约定一致
                    // 位序约定 (两端口径必须一致, 见 PC 端 protocol.py 的 missing_to_bitmap):
                    //   包号 i -> 第 (i/8) 字节的第 (7 - i%8) 位
                    //   即: 字节的最高位(bit7)对应 i%8==0, 最低位(bit0)对应 i%8==7
                    // Verilog 拼接中左侧为高位, 因此拼写顺序是 b*8+0 ... b*8+7。
                    // 反例 (初版实现): 写成 b*8+7 ... b*8+0, 会把 i%8==7 的包错报在 bit7 上,
                    // 表现为回传位图整体"每 8 个包错位一次" (实测: 丢 7,15,23 却报 0,8,16)。
                    for (int b = 0; b < BITMAP_BYTES_MAX; b++) begin
                        resp_body_r[BSTATUS_HEAD_LEN + b] <= {
                            ~rx_bitmap_r[b*8 + 0], ~rx_bitmap_r[b*8 + 1],
                            ~rx_bitmap_r[b*8 + 2], ~rx_bitmap_r[b*8 + 3],
                            ~rx_bitmap_r[b*8 + 4], ~rx_bitmap_r[b*8 + 5],
                            ~rx_bitmap_r[b*8 + 6], ~rx_bitmap_r[b*8 + 7]
                        };
                    end
                end

                // ==================== IMAGE_END -> IMAGE_READY ====================
                MSG_IMAGE_END: begin
                    resp_msg_type_r <= MSG_IMAGE_READY;
                    resp_body_len_r <= 16'd32;
                    resp_start_r    <= 1'b1;

                    // Status(1) Rsv(3) Received_Slices(4) Received_Packets(4)
                    // Received_Bytes(8) Calculated_CRC32(4) Image_Base_Addr(8)
                    resp_body_r[0]  <= (rx_pkt_cnt_r == ie_expected_packets_r)
                                       ? READY_OK
                                       : ((rx_pkt_cnt_r < ie_expected_packets_r)
                                          ? READY_MISSING : READY_PARAM_MISMATCH);
                    resp_body_r[1]  <= 8'd0;
                    resp_body_r[2]  <= 8'd0;
                    resp_body_r[3]  <= 8'd0;
                    resp_body_r[4]  <= begin_total_slices_r[31:24];
                    resp_body_r[5]  <= begin_total_slices_r[23:16];
                    resp_body_r[6]  <= begin_total_slices_r[15:8];
                    resp_body_r[7]  <= begin_total_slices_r[7:0];
                    resp_body_r[8]  <= rx_pkt_cnt_r[31:24];
                    resp_body_r[9]  <= rx_pkt_cnt_r[23:16];
                    resp_body_r[10] <= rx_pkt_cnt_r[15:8];
                    resp_body_r[11] <= rx_pkt_cnt_r[7:0];
                    resp_body_r[12] <= begin_total_bytes_r[63:56];
                    resp_body_r[13] <= begin_total_bytes_r[55:48];
                    resp_body_r[14] <= begin_total_bytes_r[47:40];
                    resp_body_r[15] <= begin_total_bytes_r[39:32];
                    resp_body_r[16] <= begin_total_bytes_r[31:24];
                    resp_body_r[17] <= begin_total_bytes_r[23:16];
                    resp_body_r[18] <= begin_total_bytes_r[15:8];
                    resp_body_r[19] <= begin_total_bytes_r[7:0];
                    // Calculated_CRC32 占位 (本仿真不落 DDR, 无整卷 CRC)
                    resp_body_r[20] <= 8'h00;
                    resp_body_r[21] <= 8'h00;
                    resp_body_r[22] <= 8'h00;
                    resp_body_r[23] <= 8'h00;
                    resp_body_r[24] <= begin_base_addr_r[63:56];
                    resp_body_r[25] <= begin_base_addr_r[55:48];
                    resp_body_r[26] <= begin_base_addr_r[47:40];
                    resp_body_r[27] <= begin_base_addr_r[39:32];
                    resp_body_r[28] <= begin_base_addr_r[31:24];
                    resp_body_r[29] <= begin_base_addr_r[23:16];
                    resp_body_r[30] <= begin_base_addr_r[15:8];
                    resp_body_r[31] <= begin_base_addr_r[7:0];
                end

                // ============== INFER_TRIGGER -> INFER_DONE ==============
                MSG_INFER_TRIGGER: begin
                    resp_msg_type_r <= MSG_INFER_DONE;
                    resp_body_len_r <= 16'd16;
                    resp_start_r    <= 1'b1;

                    // Task_ID(4) Center_Slice_ID(4) Status(1) Result_Type(1)
                    // Result_Len(2) Result(4) = 0xDEADBEEF
                    resp_body_r[0]  <= it_task_id_r[31:24];
                    resp_body_r[1]  <= it_task_id_r[23:16];
                    resp_body_r[2]  <= it_task_id_r[15:8];
                    resp_body_r[3]  <= it_task_id_r[7:0];
                    resp_body_r[4]  <= it_center_slice_r[31:24];
                    resp_body_r[5]  <= it_center_slice_r[23:16];
                    resp_body_r[6]  <= it_center_slice_r[15:8];
                    resp_body_r[7]  <= it_center_slice_r[7:0];
                    resp_body_r[8]  <= INFER_OK;
                    resp_body_r[9]  <= 8'd0;
                    resp_body_r[10] <= 8'd0;
                    resp_body_r[11] <= 8'd4;
                    resp_body_r[12] <= 8'hDE;
                    resp_body_r[13] <= 8'hAD;
                    resp_body_r[14] <= 8'hBE;
                    resp_body_r[15] <= 8'hEF;
                end

                // IMAGE_DATA 及其余类型不回帧
                default: ;
            endcase
        end
    end
end

assign tx_msg_type_o = resp_msg_type_r;

//========================================================================================
// protocol_builder (真 CRC32 生成)
//========================================================================================
logic [7:0]  builder_data_w;
logic        builder_valid_w;
logic [15:0] builder_bytes_w;
logic        builder_done_w;

protocol_builder #(
    .BODY_MAX (BODY_MAX)
) u_builder (
    .clk_i         (clk_i           ),
    .rst_n_i       (rst_n_i         ),
    .build_start_i (resp_start_r    ),
    .msg_type_i    (resp_msg_type_r ),
    .transfer_id_i (resp_transfer_id_r),
    .sequence_i    (resp_sequence_r ),
    .body_len_i    (resp_body_len_r ),
    .build_body_i  (resp_body_r     ),
    .tx_data_o     (builder_data_w  ),
    .tx_valid_o    (builder_valid_w ),
    .tx_bytes_o    (builder_bytes_w ),
    .tx_done_o     (builder_done_w  )
);

//========================================================================================
// 发送缓存: builder 突发写入, udp_tx 按 tx_req 逐字节读取
//========================================================================================
logic [7:0]  tx_buf  [0:TX_BUF_LEN-1];
logic [15:0] tx_wr_ptr_r;
logic [15:0] tx_rd_ptr_r;
logic [15:0] tx_len_r;
logic        tx_frame_rdy_r;
logic [7:0]  tx_data_to_udp_w;
logic        udp_tx_req_w;
logic        udp_tx_done_w;          // 由下方 udp_tx 实例驱动

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        tx_wr_ptr_r <= 16'd0;
    else if (builder_valid_w)
        tx_wr_ptr_r <= tx_wr_ptr_r + 16'd1;
    else
        tx_wr_ptr_r <= 16'd0;
end

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        tx_buf[0] <= 8'd0;
    else if (builder_valid_w)
        tx_buf[tx_wr_ptr_r] <= builder_data_w;
end

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        tx_len_r       <= 16'd0;
        tx_frame_rdy_r <= 1'b0;
    end
    else if (builder_done_w) begin
        tx_len_r       <= builder_bytes_w;
        tx_frame_rdy_r <= 1'b1;
    end
    else if (udp_tx_done_w)
        tx_frame_rdy_r <= 1'b0;
end

//========================================================================================
// 发送缓存读出时序 (关键)
//
// udp_tx 的时序 (按周期计数):
//   N+0: st_ip_head 末字节, 调度 tx_req <= 1
//   N+1: tx_req 已为高, 但仍在本状态发 UDP 尾字节
//   N+2: 进入 st_tx_data, 本拍执行 gmii_txd <= tx_data  <-- 第 1 个载荷字节
// 由于 gmii_txd 是寄存器, 其值来自"上一拍沿"写入的 tx_data,
// 所以 tx_data 必须在 N+1 (第一个 tx_req 拍) 就呈现 tx_buf[0]。
//
// 结论: 读出规则统一为 —— 每当 tx_req 为高, 就 tx_data <= tx_buf[rd] 且 rd 递增,
//       初值 rd = 0 即可, 不需要任何额外的"预取"分支。
// 反例 (初版实现): 在 tx_frame_rdy_r 拉高时(远早于 tx_req)就把 rd 置 1 并预装 buf[0],
//       导致真正第一个 tx_req 拍呈现的是 buf[1], 整帧丢失首字节
//       (实测回包 Magic 变成 0xAA01 而非 0x55AA)。
//========================================================================================
always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        tx_rd_ptr_r      <= 16'd0;
        tx_data_to_udp_w <= 8'd0;
    end
    else if (!tx_frame_rdy_r) begin
        tx_rd_ptr_r      <= 16'd0;
        tx_data_to_udp_w <= 8'd0;
    end
    else if (udp_tx_req_w) begin
        tx_data_to_udp_w <= tx_buf[tx_rd_ptr_r];
        tx_rd_ptr_r      <= tx_rd_ptr_r + 16'd1;
    end
end

//========================================================================================
// udp_tx (例程原版)
//========================================================================================
logic [31:0] eth_crc_data_w;
logic [31:0] eth_crc_next_w;
logic        eth_crc_en_w;
logic        eth_crc_clr_w;

udp_tx #(
    .BOARD_MAC (BOARD_MAC              ),
    .BOARD_IP  ({8'd192,8'd168,8'd1,8'd10})
) u_udp_tx (
    .clk         (clk_i            ),
    .rst_n       (rst_n_i          ),
    .tx_start_en (tx_frame_rdy_r   ),
    .tx_data     (tx_data_to_udp_w ),
    .tx_byte_num (tx_len_r         ),
    .des_mac     (48'hFF_FF_FF_FF_FF_FF),
    .des_ip      (32'd0            ),
    .crc_data    (eth_crc_data_w   ),
    .crc_next    (eth_crc_next_w   ),
    .tx_done     (udp_tx_done_w    ),
    .tx_req      (udp_tx_req_w     ),
    .gmii_tx_en  (gmii_tx_en_o     ),
    .gmii_txd    (gmii_txd_o       ),
    .crc_en      (eth_crc_en_w     ),
    .crc_clr     (eth_crc_clr_w    )
);

// 以太网 FCS 引擎 (例程原版), 与协议 CRC 无关
crc32_d8 u_eth_fcs (
    .clk      (clk_i            ),
    .rst_n    (rst_n_i          ),
    .data     (tx_data_to_udp_w ),
    .crc_en   (eth_crc_en_w     ),
    .crc_clr  (eth_crc_clr_w    ),
    .crc_data (eth_crc_data_w   ),
    .crc_next (eth_crc_next_w   )
);

assign tx_frame_done_o = udp_tx_done_w;

endmodule

//========================================================================================
// 说明:
// 1. 接收链: GMII -> udp_rx -> protocol_parser(真 CRC32) -> 响应控制器
//    发送链: 响应控制器 -> protocol_builder(真 CRC32) -> tx_buf -> udp_tx -> GMII
// 2. 缺包位图由真实接收置位生成, BATCH_STATUS 输出 (Slice_Count × 32) 字节位图
// 3. 不含 DDR / AXI / 任何 Xilinx 原语, 可直接 Verilator 仿真
// 资源预期: 无 DSP; 位图 2048 bit + tx_buf 320×8 由寄存器/LUTRAM 承载, 不占 BRAM
//========================================================================================
