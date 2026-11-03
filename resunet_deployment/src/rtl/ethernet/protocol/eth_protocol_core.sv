//========================================================================================
// 文件类型: .sv
// 模块功能: CT-FPGA协议核心；DDR_ENABLE=1时写响应确认后更新位图并读回校验
//
// 微架构:
//   protocol_parser → 响应控制器 → protocol_builder → 发送缓存 → udp_tx
//
// 功能:
//   - IMAGE_BEGIN参数校验 → ACK(ACCEPTED/INVALID_PARAM)
//   - IMAGE_DATA校验 → 提交缓存 → DDR写响应 → 更新位图
//   - BATCH_END → 统计缺包 → BATCH_STATUS(含位图)
//   - IMAGE_END → DDR按地址读回CRC → IMAGE_READY；DDR_ENABLE=0保留DDR_ERROR
//   - INFER_TRIGGER → INFER_DONE(NOT_READY：未接模型)
//
// 与仿真版本的差异:
//   - 移除GMII接口（由顶层连接）
//   - 移除udp_rx/udp_tx例化（由顶层连接）
//   - 保留完整的响应逻辑和位图管理
//========================================================================================

module eth_protocol_core #(
    parameter bit DDR_ENABLE = 1'b0 // 0保留原通信版本，1按DDR提交更新位图
) (
    input  logic        clk_i,
    input  logic        rst_n_i,

    //===================================================================================
    // 来自 protocol_parser 的解析结果
    //===================================================================================
    input  logic        frame_valid_i,
    input  logic        frame_error_i,
    input  logic [7:0]  msg_type_i,
    input  logic [31:0] transfer_id_i,
    input  logic [31:0] sequence_i,
    input  logic [15:0] body_len_i,
    input  logic        body_en_i,
    input  logic [7:0]  body_data_i,
    input  logic [15:0] body_cnt_i,

    //===================================================================================
    // 发送接口（连接udp_tx）
    //===================================================================================
    input  logic        udp_tx_req_i,       // udp_tx请求下一字节
    input  logic        udp_tx_done_i,      // udp_tx发送完成
    output logic        udp_tx_start_o,     // 启动发送
    output logic [7:0]  udp_tx_data_o,      // 发送数据
    output logic [15:0] udp_tx_len_o,
    output logic        response_accept_o,  // 本拍接受控制帧并锁存回复地址
    output logic        response_busy_o,    // 回复构建/发送期间占用 TX
    output logic        image_ready_o,      // DDR CRC 成功的稳定图像描述
    output logic [30:0] image_base_o,
    output logic [31:0] image_slices_o,

    //===================================================================================
    // DDR连接接口：均在clk_i域；数据缓存由ethernet_ddr_bridge提供
    input  logic        ddr_ready_i,
    input  logic        ddr_capture_ok_i,
    input  logic        ddr_packet_done_i,
    input  logic        ddr_packet_error_i,
    input  logic        ddr_verify_done_i,
    input  logic        ddr_verify_error_i,
    input  logic [31:0] ddr_verify_crc_i,
    output logic        ddr_packet_submit_o,
    output logic [30:0] ddr_packet_addr_o,
    output logic        ddr_verify_start_o,
    output logic [30:0] ddr_image_addr_o,
    output logic [31:0] ddr_image_bytes_o,
    output logic        ddr_error_o,

    // 调试/观测端口
    //===================================================================================
    output logic [7:0]  rx_msg_type_o,
    output logic        rx_frame_valid_o,
    output logic        rx_frame_error_o,
    output logic [7:0]  tx_msg_type_o,
    output logic        tx_frame_done_o,
    output logic [31:0] rx_pkt_cnt_o,
    output logic [31:0] rx_bad_crc_cnt_o,
    output logic [15:0] rx_batch_cnt_o
);

//========================================================================================
// 参数与常量
//========================================================================================
localparam logic [7:0] MSG_IMAGE_DATA    = 8'h01;
localparam logic [7:0] MSG_INFER_TRIGGER = 8'h02;
localparam logic [7:0] MSG_IMAGE_BEGIN   = 8'h03;
localparam logic [7:0] MSG_IMAGE_END     = 8'h04;
localparam logic [7:0] MSG_BATCH_END     = 8'h05;
localparam logic [7:0] MSG_ACK           = 8'h81;
localparam logic [7:0] MSG_INFER_DONE    = 8'h82;
localparam logic [7:0] MSG_BATCH_STATUS  = 8'h83;
localparam logic [7:0] MSG_IMAGE_READY   = 8'h84;

localparam logic [7:0] ACK_ACCEPTED      = 8'h00;
localparam logic [7:0] ACK_INVALID_PARAM = 8'h02;
localparam logic [7:0] BATCH_COMPLETE    = 8'h00;
localparam logic [7:0] BATCH_MISSING     = 8'h01;
localparam logic [7:0] READY_DDR_ERROR   = 8'h03;
localparam logic [7:0] READY_MISSING     = 8'h01;
localparam logic [7:0] READY_PARAM_MISMATCH = 8'h04;
localparam logic [7:0] INFER_NOT_READY   = 8'h02;
localparam logic [7:0] BATCH_PARAM_ERROR = 8'h03;

localparam logic [15:0] REQ_WIDTH         = 16'd512;
localparam logic [15:0] REQ_HEIGHT        = 16'd512;
localparam logic [15:0] REQ_PKT_PIX_BYTES = 16'd1024;
localparam logic [15:0] REQ_PKT_PER_SLICE = 16'd256;
localparam logic [31:0] REQ_SLICE_STRIDE  = 32'd262144;
localparam logic [15:0] REQ_DEPTH         = 16'd33;
localparam logic [15:0] REQ_CENTER_INDEX  = 16'd16;
localparam logic [15:0] REQ_PATCH_SIZE    = 16'd96;

localparam int BATCH_SLICES_MAX  = 8;
localparam int BITMAP_WORDS      = BATCH_SLICES_MAX * 256;
localparam int BITMAP_BYTES_MAX  = BITMAP_WORDS / 8;
localparam int BSTATUS_HEAD_LEN  = 16;
localparam int BODY_MAX          = BSTATUS_HEAD_LEN + BITMAP_BYTES_MAX;
localparam int TX_BUF_LEN        = 320;

//========================================================================================
// Body字段捕获寄存器
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
logic [31:0] begin_crc_r, expected_crc_r, ie_crc_r;
logic [15:0] begin_depth_r;
logic [15:0] begin_center_index_r;
logic [15:0] begin_patch_size_r;

logic [15:0] be_batch_id_r;
logic [15:0] be_first_slice_r;
logic [15:0] be_slice_count_r;
logic [31:0] be_expected_packets_r;

logic [31:0] ie_expected_packets_r;
logic [63:0] ie_expected_bytes_r;

logic [31:0] it_task_id_r;
logic [31:0] it_center_slice_r;

//========================================================================================
// Body字段捕获逻辑（大端序解析）
//========================================================================================
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
        begin_crc_r <= 32'd0;
        ie_crc_r <= 32'd0;
        begin_depth_r            <= 16'd0;
        begin_center_index_r     <= 16'd0;
        begin_patch_size_r       <= 16'd0;

        be_batch_id_r            <= 16'd0;
        be_first_slice_r         <= 16'd0;
        be_slice_count_r         <= 16'd0;
        be_expected_packets_r    <= 32'd0;

        ie_expected_packets_r    <= 32'd0;
        ie_expected_bytes_r      <= 64'd0;

        it_task_id_r             <= 32'd0;
        it_center_slice_r        <= 32'd0;
    end
    else if (body_en_i) begin
        case (msg_type_i)
            MSG_IMAGE_BEGIN: begin
                case (body_cnt_i)
                    16'd0  : begin_total_slices_r[31:24]     <= body_data_i;
                    16'd1  : begin_total_slices_r[23:16]     <= body_data_i;
                    16'd2  : begin_total_slices_r[15:8]      <= body_data_i;
                    16'd3  : begin_total_slices_r[7:0]       <= body_data_i;
                    16'd4  : begin_width_r[15:8]             <= body_data_i;
                    16'd5  : begin_width_r[7:0]              <= body_data_i;
                    16'd6  : begin_height_r[15:8]            <= body_data_i;
                    16'd7  : begin_height_r[7:0]             <= body_data_i;
                    16'd8  : begin_bytes_per_pixel_r         <= body_data_i;
                    16'd9  : begin_dtype_r                   <= body_data_i;
                    16'd12 : begin_pkt_pix_bytes_r[31:24]    <= body_data_i;
                    16'd13 : begin_pkt_pix_bytes_r[23:16]    <= body_data_i;
                    16'd14 : begin_pkt_pix_bytes_r[15:8]     <= body_data_i;
                    16'd15 : begin_pkt_pix_bytes_r[7:0]      <= body_data_i;
                    16'd16 : begin_pkt_per_slice_r[31:24]    <= body_data_i;
                    16'd17 : begin_pkt_per_slice_r[23:16]    <= body_data_i;
                    16'd18 : begin_pkt_per_slice_r[15:8]     <= body_data_i;
                    16'd19 : begin_pkt_per_slice_r[7:0]      <= body_data_i;
                    16'd20 : begin_slice_stride_r[31:24]     <= body_data_i;
                    16'd21 : begin_slice_stride_r[23:16]     <= body_data_i;
                    16'd22 : begin_slice_stride_r[15:8]      <= body_data_i;
                    16'd23 : begin_slice_stride_r[7:0]       <= body_data_i;
                    16'd24 : begin_total_bytes_r[63:56]      <= body_data_i;
                    16'd25 : begin_total_bytes_r[55:48]      <= body_data_i;
                    16'd26 : begin_total_bytes_r[47:40]      <= body_data_i;
                    16'd27 : begin_total_bytes_r[39:32]      <= body_data_i;
                    16'd28 : begin_total_bytes_r[31:24]      <= body_data_i;
                    16'd29 : begin_total_bytes_r[23:16]      <= body_data_i;
                    16'd30 : begin_total_bytes_r[15:8]       <= body_data_i;
                    16'd31 : begin_total_bytes_r[7:0]        <= body_data_i;
                    16'd32 : begin_base_addr_r[63:56]        <= body_data_i;
                    16'd33 : begin_base_addr_r[55:48]        <= body_data_i;
                    16'd34 : begin_base_addr_r[47:40]        <= body_data_i;
                    16'd35 : begin_base_addr_r[39:32]        <= body_data_i;
                    16'd36 : begin_base_addr_r[31:24]        <= body_data_i;
                    16'd37 : begin_base_addr_r[23:16]        <= body_data_i;
                    16'd38 : begin_base_addr_r[15:8]         <= body_data_i;
                    16'd39 : begin_base_addr_r[7:0]          <= body_data_i;
                    16'd40 : begin_batch_slices_r[31:24]     <= body_data_i;
                    16'd41 : begin_batch_slices_r[23:16]     <= body_data_i;
                    16'd42 : begin_batch_slices_r[15:8]      <= body_data_i;
                    16'd43 : begin_batch_slices_r[7:0]       <= body_data_i;
                    16'd44 : begin_expected_packets_r[31:24] <= body_data_i;
                    16'd45 : begin_expected_packets_r[23:16] <= body_data_i;
                    16'd46 : begin_expected_packets_r[15:8]  <= body_data_i;
                    16'd47 : begin_expected_packets_r[7:0]   <= body_data_i;
                    16'd48 : begin_crc_r[31:24] <= body_data_i;
                    16'd49 : begin_crc_r[23:16] <= body_data_i;
                    16'd50 : begin_crc_r[15:8]  <= body_data_i;
                    16'd51 : begin_crc_r[7:0]   <= body_data_i;
                    16'd68 : begin_depth_r[15:8]             <= body_data_i;
                    16'd69 : begin_depth_r[7:0]              <= body_data_i;
                    16'd70 : begin_center_index_r[15:8]      <= body_data_i;
                    16'd71 : begin_center_index_r[7:0]       <= body_data_i;
                    16'd72 : begin_patch_size_r[15:8]        <= body_data_i;
                    16'd73 : begin_patch_size_r[7:0]         <= body_data_i;
                    default: ;
                endcase
            end

            MSG_BATCH_END: begin
                case (body_cnt_i)
                    16'd0  : be_batch_id_r[15:8]          <= body_data_i;
                    16'd1  : be_batch_id_r[7:0]           <= body_data_i;
                    16'd2  : be_first_slice_r[15:8]       <= body_data_i;
                    16'd3  : be_first_slice_r[7:0]        <= body_data_i;
                    16'd4  : be_slice_count_r[15:8]       <= body_data_i;
                    16'd5  : be_slice_count_r[7:0]        <= body_data_i;
                    16'd8  : be_expected_packets_r[31:24] <= body_data_i;
                    16'd9  : be_expected_packets_r[23:16] <= body_data_i;
                    16'd10 : be_expected_packets_r[15:8]  <= body_data_i;
                    16'd11 : be_expected_packets_r[7:0]   <= body_data_i;
                    default: ;
                endcase
            end

            MSG_IMAGE_END: begin
                case (body_cnt_i)
                    16'd0  : ie_expected_packets_r[31:24] <= body_data_i;
                    16'd1  : ie_expected_packets_r[23:16] <= body_data_i;
                    16'd2  : ie_expected_packets_r[15:8]  <= body_data_i;
                    16'd3  : ie_expected_packets_r[7:0]   <= body_data_i;
                    16'd4  : ie_expected_bytes_r[63:56]   <= body_data_i;
                    16'd5  : ie_expected_bytes_r[55:48]   <= body_data_i;
                    16'd6  : ie_expected_bytes_r[47:40]   <= body_data_i;
                    16'd7  : ie_expected_bytes_r[39:32]   <= body_data_i;
                    16'd8  : ie_expected_bytes_r[31:24]   <= body_data_i;
                    16'd9  : ie_expected_bytes_r[23:16]   <= body_data_i;
                    16'd10 : ie_expected_bytes_r[15:8]    <= body_data_i;
                    16'd11 : ie_expected_bytes_r[7:0]     <= body_data_i;
                    16'd12 : ie_crc_r[31:24] <= body_data_i;
                    16'd13 : ie_crc_r[23:16] <= body_data_i;
                    16'd14 : ie_crc_r[15:8]  <= body_data_i;
                    16'd15 : ie_crc_r[7:0]   <= body_data_i;
                    default: ;
                endcase
            end

            MSG_INFER_TRIGGER: begin
                case (body_cnt_i)
                    16'd0  : it_task_id_r[31:24]      <= body_data_i;
                    16'd1  : it_task_id_r[23:16]      <= body_data_i;
                    16'd2  : it_task_id_r[15:8]       <= body_data_i;
                    16'd3  : it_task_id_r[7:0]        <= body_data_i;
                    16'd4  : it_center_slice_r[31:24] <= body_data_i;
                    16'd5  : it_center_slice_r[23:16] <= body_data_i;
                    16'd6  : it_center_slice_r[15:8]  <= body_data_i;
                    16'd7  : it_center_slice_r[7:0]   <= body_data_i;
                    default: ;
                endcase
            end

            default: ;
        endcase
    end
end

//========================================================================================
// IMAGE_DATA定位字段捕获
//========================================================================================
logic [15:0] idata_slice_id_r;
logic [15:0] idata_packet_idx_r;
logic [15:0] idata_pixel_len_r;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        idata_slice_id_r   <= 16'd0;
        idata_packet_idx_r <= 16'd0;
        idata_pixel_len_r <= 16'd0;
    end
    else if (body_en_i && (msg_type_i == MSG_IMAGE_DATA)) begin
        case (body_cnt_i)
            16'd0 : idata_slice_id_r[15:8]   <= body_data_i;
            16'd1 : idata_slice_id_r[7:0]    <= body_data_i;
            16'd2 : idata_packet_idx_r[15:8] <= body_data_i;
            16'd3 : idata_packet_idx_r[7:0]  <= body_data_i;
            16'd4 : idata_pixel_len_r[15:8] <= body_data_i;
            16'd5 : idata_pixel_len_r[7:0] <= body_data_i;
            default: ;
        endcase
    end
end

// 已通过校验的传输参数独立锁存，损坏/无效的后续BEGIN不会改写当前状态。
logic active_r, resp_busy_r;
logic packet_pending_r, verify_pending_r, verify_cached_r;
logic ddr_error_r, verify_error_r;
logic [10:0] pending_idx_r, commit_idx_w;
logic [31:0] verified_crc_r, response_crc_w;
logic data_commit_w, verify_event_w, response_event_w, image_param_ok_w;
logic [7:0] response_msg_w, image_status_w;
logic [31:0] active_id_r, total_slices_r;
logic [63:0] total_bytes_r, base_addr_r;
logic [3:0] batch_slices_r;
logic [15:0] cur_first_slice_r, cur_batch_id_r;
logic [15:0] last_first_r, last_count_r, last_batch_id_r;
logic last_complete_r, batch_empty_r;
logic [BITMAP_WORDS-1:0] rx_bitmap_r;
logic [11:0] batch_recv_r;
logic [31:0] rx_pkt_cnt_r, rx_bad_crc_r;
logic [15:0] rx_batch_cnt_r;
assign response_busy_o = resp_busy_r;
assign image_ready_o = active_r && verify_cached_r && !verify_error_r &&
                       !ddr_error_r && verified_crc_r == expected_crc_r;
assign image_base_o = base_addr_r[30:0];
assign image_slices_o = total_slices_r;
logic [16:0] rel_slice_w;
logic [10:0] rel_bit_idx_w;
logic begin_new_w, data_valid_w, data_new_w, batch_param_ok_w, batch_repeat_w;
logic batch_complete_w, begin_param_ok_w;
logic [31:0] recv_in_batch_w, missing_cnt_w;
logic [31:0] remaining_slices_w;
logic [15:0] current_batch_slices_w;

assign remaining_slices_w = total_slices_r - {16'd0,cur_first_slice_r};
assign current_batch_slices_w = (remaining_slices_w < {28'd0,batch_slices_r}) ?
                                remaining_slices_w[15:0] : {12'd0,batch_slices_r};

assign begin_new_w = response_accept_o && msg_type_i == MSG_IMAGE_BEGIN &&
                     begin_param_ok_w && (!active_r || transfer_id_i != active_id_r);
assign rel_slice_w = {1'b0,idata_slice_id_r} - {1'b0,cur_first_slice_r};
assign rel_bit_idx_w = {rel_slice_w[2:0],idata_packet_idx_r[7:0]};
assign data_valid_w = frame_valid_i && msg_type_i == MSG_IMAGE_DATA && active_r &&
                      transfer_id_i == active_id_r && body_len_i == 16'd1032 &&
                      idata_pixel_len_r == REQ_PKT_PIX_BYTES &&
                      idata_packet_idx_r < REQ_PKT_PER_SLICE &&
                      rel_slice_w < {13'd0,batch_slices_r} &&
                      {16'd0,idata_slice_id_r} < total_slices_r;
assign data_new_w = data_valid_w && !packet_pending_r && !verify_pending_r &&
                    !verify_cached_r && (batch_empty_r || !rx_bitmap_r[rel_bit_idx_w]);
assign ddr_packet_submit_o = DDR_ENABLE && data_new_w && ddr_capture_ok_i && ddr_ready_i;
assign ddr_packet_addr_o = base_addr_r[30:0] +
                          {idata_slice_id_r[12:0],idata_packet_idx_r[7:0],10'd0};
assign ddr_image_addr_o = base_addr_r[30:0];
assign ddr_image_bytes_o = total_bytes_r[31:0];
assign data_commit_w = DDR_ENABLE ?
                       (ddr_packet_done_i && packet_pending_r && !ddr_packet_error_i && active_r) :
                       data_new_w;
assign commit_idx_w = DDR_ENABLE ? pending_idx_r : rel_bit_idx_w;
assign ddr_error_o = ddr_error_r || verify_error_r ||
                     (DDR_ENABLE && verify_cached_r && verified_crc_r != expected_crc_r);
assign image_param_ok_w = (ie_expected_packets_r == {total_slices_r[23:0],8'd0}) &&
                          (ie_expected_bytes_r == total_bytes_r) &&
                          (!DDR_ENABLE || ie_crc_r == expected_crc_r);
assign ddr_verify_start_o = DDR_ENABLE && response_accept_o && msg_type_i == MSG_IMAGE_END &&
                            image_param_ok_w && rx_pkt_cnt_r == ie_expected_packets_r &&
                            !verify_cached_r && !ddr_error_r;
assign verify_event_w = DDR_ENABLE && verify_pending_r && ddr_verify_done_i && active_r;
assign response_event_w = (response_accept_o && !ddr_verify_start_o) || verify_event_w;
assign response_msg_w = verify_event_w ? MSG_IMAGE_END : msg_type_i;
assign response_crc_w = verify_event_w ? ddr_verify_crc_i : verified_crc_r;

always_comb begin
    image_status_w = READY_DDR_ERROR;
    if (verify_event_w) begin
        image_status_w = ddr_verify_error_i ? READY_DDR_ERROR :
                         ((ddr_verify_crc_i == expected_crc_r) ? 8'h00 : 8'h02);
    end else if (!image_param_ok_w) image_status_w = READY_PARAM_MISMATCH;
    else if (rx_pkt_cnt_r != ie_expected_packets_r) image_status_w = READY_MISSING;
    else if (DDR_ENABLE && verify_cached_r && !ddr_error_r && !verify_error_r)
        image_status_w = (verified_crc_r == expected_crc_r) ? 8'h00 : 8'h02;
end

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        packet_pending_r <= 1'b0;
        pending_idx_r <= 11'd0;
        verify_pending_r <= 1'b0;
        verify_cached_r <= 1'b0;
        verified_crc_r <= 32'd0;
        verify_error_r <= 1'b0;
        ddr_error_r <= 1'b0;
    end else begin
        if (ddr_packet_submit_o) begin
            packet_pending_r <= 1'b1;
            pending_idx_r <= rel_bit_idx_w;
        end
        if (ddr_packet_done_i && packet_pending_r) begin
            packet_pending_r <= 1'b0;
            if (ddr_packet_error_i) ddr_error_r <= 1'b1;
        end
        if (ddr_verify_start_o) verify_pending_r <= 1'b1;
        if (ddr_verify_done_i && verify_pending_r) begin
            verify_pending_r <= 1'b0;
            verify_cached_r <= 1'b1;
            verified_crc_r <= ddr_verify_crc_i;
            verify_error_r <= ddr_verify_error_i;
        end
        if (begin_new_w) begin
            verify_cached_r <= 1'b0;
            verified_crc_r <= 32'd0;
            verify_error_r <= 1'b0;
            ddr_error_r <= 1'b0;
        end
    end
end
assign batch_repeat_w = last_complete_r && be_batch_id_r == last_batch_id_r &&
                        be_first_slice_r == last_first_r && be_slice_count_r == last_count_r;
assign batch_param_ok_w = active_r && transfer_id_i == active_id_r &&
                         body_len_i == 16'd16 && be_slice_count_r != 16'd0 &&
                         be_slice_count_r <= {12'd0,batch_slices_r} &&
                         be_expected_packets_r == {8'd0,be_slice_count_r,8'd0} &&
                         ({16'd0,be_first_slice_r}+{16'd0,be_slice_count_r} <= total_slices_r) &&
                         (batch_repeat_w || (be_first_slice_r == cur_first_slice_r &&
                                             be_batch_id_r == cur_batch_id_r &&
                                             be_slice_count_r == current_batch_slices_w));
assign recv_in_batch_w = batch_repeat_w ? be_expected_packets_r :
                        (batch_empty_r ? 32'd0 : {20'd0,batch_recv_r});
assign missing_cnt_w = be_expected_packets_r - recv_in_batch_w;
assign batch_complete_w = response_accept_o && msg_type_i == MSG_BATCH_END &&
                          batch_param_ok_w && !batch_repeat_w && missing_cnt_w == 32'd0;

// 位图数据不接异步复位；接受新传输时同步清零，active_r屏蔽未初始化数据。
always_ff @(posedge clk_i) begin
    if (begin_new_w) rx_bitmap_r <= '0;
    else if (data_commit_w) begin
        if (batch_empty_r) rx_bitmap_r <= (2048'd1 << commit_idx_w);
        else rx_bitmap_r[commit_idx_w] <= 1'b1;
    end
end

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        active_r <= 1'b0;
        active_id_r <= 32'd0;
        cur_first_slice_r <= 16'd0;
        cur_batch_id_r <= 16'd0;
        last_complete_r <= 1'b0;
        batch_empty_r <= 1'b1;
        batch_recv_r <= 12'd0;
        rx_pkt_cnt_r <= 32'd0;
        rx_bad_crc_r <= 32'd0;
        rx_batch_cnt_r <= 16'd0;
        resp_busy_r <= 1'b0;
    end else begin
        if (response_accept_o) resp_busy_r <= 1'b1;
        else if (udp_tx_done_i || (ddr_verify_done_i && verify_pending_r && !active_r))
            resp_busy_r <= 1'b0;
        if (frame_error_i) rx_bad_crc_r <= rx_bad_crc_r + 32'd1;
        if (frame_valid_i && msg_type_i == 8'h06 && transfer_id_i == active_id_r)
            active_r <= 1'b0;
        if (begin_new_w) begin
            active_r <= 1'b1;
            active_id_r <= transfer_id_i;
            cur_first_slice_r <= 16'd0;
            cur_batch_id_r <= 16'd0;
            last_complete_r <= 1'b0;
            batch_empty_r <= 1'b1;
            batch_recv_r <= 12'd0;
            rx_pkt_cnt_r <= 32'd0;
            rx_batch_cnt_r <= 16'd0;
        end else begin
            if (data_commit_w) begin
                batch_empty_r <= 1'b0;
                batch_recv_r <= batch_empty_r ? 12'd1 : batch_recv_r + 12'd1;
                rx_pkt_cnt_r <= rx_pkt_cnt_r + 32'd1;
            end
            if (batch_complete_w) begin
                cur_first_slice_r <= be_first_slice_r + be_slice_count_r;
                cur_batch_id_r <= cur_batch_id_r + 16'd1;
                last_complete_r <= 1'b1;
                batch_empty_r <= 1'b1;
                rx_batch_cnt_r <= rx_batch_cnt_r + 16'd1;
            end
        end
    end
end

always_ff @(posedge clk_i) begin
    if (begin_new_w) begin
        expected_crc_r <= begin_crc_r;
        total_slices_r <= begin_total_slices_r;
        total_bytes_r <= begin_total_bytes_r;
        base_addr_r <= begin_base_addr_r;
        batch_slices_r <= begin_batch_slices_r[3:0];
    end
    if (batch_complete_w) begin
        last_first_r <= be_first_slice_r;
        last_count_r <= be_slice_count_r;
        last_batch_id_r <= be_batch_id_r;
    end
end

// 一次只构建/发送一个回复；忙时依靠上位机已有超时重试，防止覆盖发送缓存。
always_comb begin
    response_accept_o = 1'b0;
    if (frame_valid_i && !resp_busy_r && !packet_pending_r && !verify_pending_r) begin
        case (msg_type_i)
            MSG_IMAGE_BEGIN: response_accept_o = 1'b1;
            MSG_BATCH_END: response_accept_o = active_r && transfer_id_i == active_id_r;
            MSG_IMAGE_END: response_accept_o = active_r && transfer_id_i == active_id_r && body_len_i == 16'd20;
            MSG_INFER_TRIGGER: response_accept_o = active_r && transfer_id_i == active_id_r && body_len_i == 16'd24;
            default: ;
        endcase
    end
end

assign rx_msg_type_o    = msg_type_i;
assign rx_frame_valid_o = frame_valid_i;
assign rx_frame_error_o = frame_error_i;
assign rx_pkt_cnt_o     = rx_pkt_cnt_r;
assign rx_bad_crc_cnt_o = rx_bad_crc_r;
assign rx_batch_cnt_o   = rx_batch_cnt_r;

//========================================================================================
// IMAGE_BEGIN参数校验
//========================================================================================
always_comb begin
    begin_param_ok_w = (body_len_i == 16'd76) &&
                       (begin_total_slices_r <= 32'd65535) &&
                       (begin_expected_packets_r == {begin_total_slices_r[23:0],8'd0}) &&
                       (begin_total_bytes_r == {14'd0,begin_total_slices_r,18'd0}) &&
                       (begin_bytes_per_pixel_r == 8'd1)                 &&
                       (begin_width_r           == REQ_WIDTH)            &&
                       (begin_height_r          == REQ_HEIGHT)           &&
                       (begin_dtype_r           == 8'h01)                &&
                       (begin_pkt_per_slice_r   == {16'd0,REQ_PKT_PER_SLICE})    &&
                       (begin_pkt_pix_bytes_r   == {16'd0,REQ_PKT_PIX_BYTES})    &&
                       (begin_slice_stride_r    == REQ_SLICE_STRIDE)     &&
                       (begin_depth_r           == REQ_DEPTH)            &&
                       (begin_center_index_r    == REQ_CENTER_INDEX)     &&
                       (begin_patch_size_r      == REQ_PATCH_SIZE)       &&
                       (begin_total_slices_r    >= 32'd1)                &&
                       (begin_base_addr_r[11:0] == 12'd0)               &&
                       (!DDR_ENABLE || (ddr_ready_i &&
                        begin_base_addr_r < 64'h0000_0000_2000_0000 &&
                        begin_total_bytes_r <= 64'h0000_0000_2000_0000 &&
                        begin_base_addr_r + begin_total_bytes_r <= 64'h0000_0000_2000_0000)) &&
                       (!active_r || transfer_id_i != active_id_r ||
                        (begin_total_slices_r == total_slices_r &&
                         begin_total_bytes_r == total_bytes_r &&
                         begin_base_addr_r == base_addr_r &&
                         (!DDR_ENABLE || begin_crc_r == expected_crc_r) &&
                         begin_batch_slices_r == {28'd0,batch_slices_r})) &&
                       (begin_batch_slices_r    >= 32'd1)                &&
                       (begin_batch_slices_r    <= BATCH_SLICES_MAX);
end

//========================================================================================
// 响应控制器
//========================================================================================
logic [31:0] received_slices_w;
assign received_slices_w = {8'd0,rx_pkt_cnt_r[31:8]};
logic [63:0] received_bytes_w;
assign received_bytes_w = {22'd0,rx_pkt_cnt_r,10'd0};
logic [7:0]  resp_msg_type_r;
logic [31:0] resp_transfer_id_r;
logic [31:0] resp_sequence_r;
logic [15:0] resp_body_len_r;
logic        resp_start_r;
logic [7:0]  resp_body_r [0:BODY_MAX-1];

logic [15:0] bstatus_bitmap_bytes_w;
assign bstatus_bitmap_bytes_w = batch_param_ok_w ? {be_slice_count_r[10:0],5'd0} : 16'd0;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) resp_start_r <= 1'b0;
    else resp_start_r <= response_event_w;
end

always_ff @(posedge clk_i) begin
    if (response_accept_o) begin
            resp_transfer_id_r <= transfer_id_i;
            resp_sequence_r    <= sequence_i + 32'd1;
    end
    if (response_event_w) begin
            case (response_msg_w)
                MSG_IMAGE_BEGIN: begin
                    resp_msg_type_r <= MSG_ACK;
                    resp_body_len_r <= 16'd8;

                    resp_body_r[0] <= MSG_IMAGE_BEGIN;
                    resp_body_r[1] <= begin_param_ok_w ? ACK_ACCEPTED : ACK_INVALID_PARAM;
                    resp_body_r[2] <= 8'd0;
                    resp_body_r[3] <= 8'd0;
                    resp_body_r[4] <= sequence_i[31:24];
                    resp_body_r[5] <= sequence_i[23:16];
                    resp_body_r[6] <= sequence_i[15:8];
                    resp_body_r[7] <= sequence_i[7:0];
                end

                MSG_BATCH_END: begin
                    resp_msg_type_r <= MSG_BATCH_STATUS;
                    resp_body_len_r <= 16'd16 + bstatus_bitmap_bytes_w;

                    resp_body_r[0]  <= be_batch_id_r[15:8];
                    resp_body_r[1]  <= be_batch_id_r[7:0];
                    resp_body_r[2]  <= !batch_param_ok_w ? BATCH_PARAM_ERROR :
                                       ((missing_cnt_w == 32'd0) ? BATCH_COMPLETE : BATCH_MISSING);
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

                    for (int b = 0; b < BITMAP_BYTES_MAX; b++) begin
                        resp_body_r[BSTATUS_HEAD_LEN + b] <= batch_repeat_w ? 8'd0 :
                            (batch_empty_r ? 8'hff : {
                            ~rx_bitmap_r[b*8 + 0], ~rx_bitmap_r[b*8 + 1],
                            ~rx_bitmap_r[b*8 + 2], ~rx_bitmap_r[b*8 + 3],
                            ~rx_bitmap_r[b*8 + 4], ~rx_bitmap_r[b*8 + 5],
                            ~rx_bitmap_r[b*8 + 6], ~rx_bitmap_r[b*8 + 7]
                        });
                    end
                end

                MSG_IMAGE_END: begin
                    resp_msg_type_r <= MSG_IMAGE_READY;
                    resp_body_len_r <= 16'd32;

                    resp_body_r[0]  <= image_status_w;
                    resp_body_r[1]  <= 8'd0;
                    resp_body_r[2]  <= 8'd0;
                    resp_body_r[3]  <= 8'd0;
                    resp_body_r[4]  <= received_slices_w[31:24];
                    resp_body_r[5]  <= received_slices_w[23:16];
                    resp_body_r[6]  <= received_slices_w[15:8];
                    resp_body_r[7]  <= received_slices_w[7:0];
                    resp_body_r[8]  <= rx_pkt_cnt_r[31:24];
                    resp_body_r[9]  <= rx_pkt_cnt_r[23:16];
                    resp_body_r[10] <= rx_pkt_cnt_r[15:8];
                    resp_body_r[11] <= rx_pkt_cnt_r[7:0];
                    resp_body_r[12] <= received_bytes_w[63:56];
                    resp_body_r[13] <= received_bytes_w[55:48];
                    resp_body_r[14] <= received_bytes_w[47:40];
                    resp_body_r[15] <= received_bytes_w[39:32];
                    resp_body_r[16] <= received_bytes_w[31:24];
                    resp_body_r[17] <= received_bytes_w[23:16];
                    resp_body_r[18] <= received_bytes_w[15:8];
                    resp_body_r[19] <= received_bytes_w[7:0];
                    resp_body_r[20] <= response_crc_w[31:24];
                    resp_body_r[21] <= response_crc_w[23:16];
                    resp_body_r[22] <= response_crc_w[15:8];
                    resp_body_r[23] <= response_crc_w[7:0];
                    resp_body_r[24] <= base_addr_r[63:56];
                    resp_body_r[25] <= base_addr_r[55:48];
                    resp_body_r[26] <= base_addr_r[47:40];
                    resp_body_r[27] <= base_addr_r[39:32];
                    resp_body_r[28] <= base_addr_r[31:24];
                    resp_body_r[29] <= base_addr_r[23:16];
                    resp_body_r[30] <= base_addr_r[15:8];
                    resp_body_r[31] <= base_addr_r[7:0];
                end

                MSG_INFER_TRIGGER: begin
                    resp_msg_type_r <= MSG_INFER_DONE;
                    resp_body_len_r <= 16'd16;

                    resp_body_r[0]  <= it_task_id_r[31:24];
                    resp_body_r[1]  <= it_task_id_r[23:16];
                    resp_body_r[2]  <= it_task_id_r[15:8];
                    resp_body_r[3]  <= it_task_id_r[7:0];
                    resp_body_r[4]  <= it_center_slice_r[31:24];
                    resp_body_r[5]  <= it_center_slice_r[23:16];
                    resp_body_r[6]  <= it_center_slice_r[15:8];
                    resp_body_r[7]  <= it_center_slice_r[7:0];
                    resp_body_r[8]  <= INFER_NOT_READY;
                    resp_body_r[9]  <= 8'd0;
                    resp_body_r[10] <= 8'd0;
                    resp_body_r[11] <= 8'd0;
                    resp_body_r[12] <= 8'd0;
                    resp_body_r[13] <= 8'd0;
                    resp_body_r[14] <= 8'd0;
                    resp_body_r[15] <= 8'd0;
                end

                default: ;
            endcase
    end
end

assign tx_msg_type_o = resp_msg_type_r;

//========================================================================================
// protocol_builder例化
//========================================================================================
logic [7:0]  builder_data_w;
logic        builder_valid_w;
logic [15:0] builder_bytes_w;
logic        builder_done_w;

protocol_builder #(
    .BODY_MAX (BODY_MAX)
) u_builder (
    .clk_i         (clk_i            ),
    .rst_n_i       (rst_n_i          ),
    .build_start_i (resp_start_r     ),
    .msg_type_i    (resp_msg_type_r  ),
    .transfer_id_i (resp_transfer_id_r),
    .sequence_i    (resp_sequence_r  ),
    .body_len_i    (resp_body_len_r  ),
    .build_body_i  (resp_body_r      ),
    .body_addr_o   (                 ),
    .body_data_i   (8'd0             ),
    .tx_data_o     (builder_data_w   ),
    .tx_valid_o    (builder_valid_w  ),
    .tx_bytes_o    (builder_bytes_w  ),
    .tx_done_o     (builder_done_w   )
);

//========================================================================================
// 发送缓存
//========================================================================================
(* ram_style = "block" *) logic [7:0] tx_buf [0:511];
logic [8:0] tx_wr_ptr_r;
logic [8:0] tx_rd_ptr_r;
logic [15:0] tx_len_r;
logic        tx_frame_rdy_r;

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        tx_wr_ptr_r <= 9'd0;
    else if (builder_valid_w)
        tx_wr_ptr_r <= tx_wr_ptr_r + 9'd1;
    else
        tx_wr_ptr_r <= 9'd0;
end

always_ff @(posedge clk_i) begin
    if (builder_valid_w)
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
    else if (udp_tx_done_i)
        tx_frame_rdy_r <= 1'b0;
end

always_ff @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) tx_rd_ptr_r <= 9'd0;
    else if (!tx_frame_rdy_r) tx_rd_ptr_r <= 9'd0;
    else if (udp_tx_req_i) tx_rd_ptr_r <= tx_rd_ptr_r + 9'd1;
end

always_ff @(posedge clk_i) begin
    if (udp_tx_req_i) udp_tx_data_o <= tx_buf[tx_rd_ptr_r];
end

assign udp_tx_start_o    = tx_frame_rdy_r;
assign udp_tx_len_o      = tx_len_r;
assign tx_frame_done_o   = udp_tx_done_i;

endmodule

