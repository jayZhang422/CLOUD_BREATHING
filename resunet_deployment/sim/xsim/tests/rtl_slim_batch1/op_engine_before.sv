`timescale 1ns/1ps
// 【文件类型：.sv】上板准备候选调度，基于现有调度器扩宽通道/组标签。
// 权重/参数事务由外部 op_coeff_split 接到只读源；本文件不例化 ROM IP。
// 描述符 byte52/54 为可选 LE16 Cin/Cout；为零时兼容 byte2/3。
// 原始 BIN 保留 ZYX；PW 的 INT8 输出按 group16/pixel/lane 落址。
module op_engine_before (
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic run_valid_i, // 握手有效，阻塞期间保持载荷
    input logic check_valid_i, // 描述检查请求，保持到 check_done_o
    output logic check_done_o, // 描述检查完成，结果保持到下一次检查
    output logic run_ready_o, // 握手接收许可
    output logic descriptor_ok_o, // 任务配置或协议控制字段
    input logic abort_i, // 任务配置或协议控制字段
    output logic busy_o, // 阶段占用与流控状态
    output logic done_o, // 完成通知，须遵守排空条件
    output logic error_o, // 本次操作错误状态
    output logic aborted_o, // 任务配置或协议控制字段
    output logic mem_valid_o, // 握手有效，阻塞期间保持载荷
    input logic mem_ready_i, // 握手接收许可
    output logic mem_write_o, // DDR 事务接口字段
    input logic mem_rsp_valid_i, // 握手有效，阻塞期间保持载荷
    output logic mem_rsp_ready_o, // 握手接收许可
    input logic mem_rsp_error_i, // 本次操作错误状态
    input logic [511:0] descriptor_i, // 任务配置或协议控制字段
    output logic [31:0] result_bytes_o, // 有效字节数或接口长度
    output logic [31:0] mac_bytes_o, // 有效字节数或接口长度
    output logic [31:0] candidate_bytes_o, // 有效字节数或接口长度
    output logic [31:0] candidate_mac_bytes_o, // 有效字节数或接口长度
    output logic [30:0] mem_addr_o, // 地址字段，单位按模块接口约定
    output logic [255:0] mem_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [31:0] mem_mask_o, // DDR 事务接口字段
    input logic [255:0] mem_rsp_data_i // 数据载荷，低位承载首字节或首 lane
);
    typedef enum logic [3:0] {IDLE, RESET_CORE, CLEAR, CONFIGURE,
        LOAD_WEIGHTS, LOAD_PARAMS, LOAD_ADD, START, RUN, FLUSH_REQUEST, FLUSH_RETURN, FINISH} state_t;
    state_t state_r, state_nxt;
    typedef enum logic [3:0] {O_IDLE, O_INDEX, O_PIXEL, O_ADDRESS,
        O_Q_REQUEST, O_Q_WAIT, O_MAC_REQUEST, O_MAC_WAIT} output_state_t;
    output_state_t output_r, output_nxt;
    logic [511:0] d_r;
    logic [7:0] op_w;
    logic [9:0] cin_w, cin_b_w, cout_w;
    logic [9:0] width_w, height_w;
    logic [5:0] groups_w, group_r;
    logic [31:0] pixels_w, input_count_r, output_count_r, load_count_r, clear_addr_r, tile_base_r;
    logic [4:0] tile_words_w;
    logic [31:0] saved_output_count_r;
    logic [31:0] weight_words_w, param_words_w, total_inputs_w, p12_weight_a_words_w;
    logic [31:0] pixels_r, total_inputs_r, weight_words_r, param_words_r, words_b_r;
    logic [31:0] checked_pixels_w, checked_inputs_w, checked_weights_w, checked_params_w, checked_words_b_w;
    logic [31:0] group_pixel_base_r, output_addr_r, saved_linear_addr_r;
    logic [30:0] saved_q_addr_r, saved_mac_addr_r;
    logic [31:0] q_index_r, mac_index_r, q_pixel_r, mac_pixel_r;
    logic [31:0] base_a_w, base_b_w, base_b_concat_w, out_base_w, mac_base_w, weight_base_w, param_base_w;
    logic online_w, debug_w, raw_w, int16_w, core_done_r, error_r, aborted_r;
    logic [2047:0] add_params_r;
    logic add_a_valid_r, add_loaded_r;
    logic [511:0] add_a_r;
    logic cfg_valid_w, cfg_ready_w, weights_ready_w, params_ready_w, start_ready_w;
    logic bank_params_valid_w, p12_pw_loaded_r, p12_pw_started_r, reader_source_r;
    logic [511:0] bank_load_data_w;
    logic bank_in_valid_w, bank_in_ready_w, bank_b_valid_w, bank_b_ready_w;
    logic [511:0] bank_in_data_w;
    logic bank_rd_valid_w, bank_rd_ready_w, bank_rsp_ready_w, bank_rd_source_w;
    logic [31:0] bank_rd_addr_w;
    logic bank_out_valid_w, bank_out_ready_w, bank_last_w, bank_done_w;
    logic [3199:0] bank_data_w, saved_data_r;
    logic [127:0] bank_mac_w, saved_mac_r;
    logic [18:0] bank_pixel_w, saved_pixel_r;
    logic [6:0] bank_group_w, saved_group_r;
    logic [3:0] bank_mask_w;
    logic reader_req_w, reader_ready_w, reader_rsp_w, reader_rsp_ready_w, reader_error_w;
    logic [1:0] reader_mode_w;
    logic [30:0] reader_addr_w;
    logic [31:0] reader_pixel_w;
    logic [511:0] reader_data_w;
    logic reader_mem_w, reader_mem_ready_w, reader_mem_rsp_ready_w;
    logic [30:0] reader_mem_addr_w;
    logic writer_req_w, writer_ready_w, writer_done_w, writer_error_w;
    logic [30:0] writer_addr_w;
    logic [3199:0] writer_data_w;
    logic [8:0] writer_bytes_w;
    logic writer_mem_w, writer_mem_ready_w, writer_mem_rsp_ready_w;
    logic [30:0] writer_mem_addr_w;
    logic [255:0] writer_mem_data_w;
    logic [31:0] writer_mem_mask_w;
    logic response_writer_r, pending_r, clear_wait_r;
    logic load_fire_w, in_fire_w, output_fire_w, drained_w;

    assign op_w = d_r[7:0];
    assign online_w = d_r[8]; assign debug_w = d_r[9];
    assign raw_w = d_r[10]; assign int16_w = d_r[11];
    assign cin_w = d_r[431:416] == 16'd0 ? {2'd0,d_r[23:16]} : d_r[425:416];
    assign cin_b_w = d_r[457:448];
    assign cout_w = d_r[447:432] == 16'd0 ? {2'd0,d_r[31:24]} : d_r[441:432];
    assign width_w = d_r[41:32]; assign height_w = d_r[57:48];
    assign groups_w = d_r[69:64];
    assign pixels_w = pixels_r;
    assign tile_words_w = pixels_r - tile_base_r > 32'd16 ? 5'd16 : (pixels_r - tile_base_r);
    assign p12_weight_a_words_w = (({22'd0,cout_w} + 32'd3) >> 2) *
                                  (({22'd0,cin_w} + 32'd15) >> 4);
    assign base_a_w = d_r[159:128]; assign base_b_w = d_r[191:160];
    // 固定第二阶段清单的三个 decoder concat 描述符仍携带旧的 skip 地址。
    // 只对 lobe 的 op5、对应分辨率和旧地址做 FPGA 侧兼容映射，保持
    // Python 输入/描述符不变；其它网络和其它算子继续使用原始 base_b。
    always_comb begin
        base_b_concat_w = base_b_w;
        if (op_w == 8'd5) begin
            case (base_b_w)
                32'h09600000: if (width_w == 10'd128 && height_w == 10'd128)
                    base_b_concat_w = 32'h1E600000;
                32'h09400000: if (width_w == 10'd256 && height_w == 10'd256)
                    base_b_concat_w = 32'h1E400000;
                32'h09000000: if (width_w == 10'd512 && height_w == 10'd512)
                    base_b_concat_w = 32'h1E000000;
                default: ;
            endcase
        end
    end
    assign out_base_w = d_r[223:192]; assign mac_base_w = d_r[255:224];
    assign weight_base_w = d_r[287:256]; assign param_base_w = d_r[319:288];
    assign weight_words_w = weight_words_r;
    assign param_words_w = param_words_r;
    assign total_inputs_w = total_inputs_r;
    assign bank_params_valid_w = state_r == LOAD_PARAMS &&
        (op_w == 8'd12 ? load_count_r < param_words_w : reader_rsp_w);
    assign bank_load_data_w = state_r == LOAD_PARAMS && op_w == 8'd12 ? 512'd0 : reader_data_w;

    // 检查流水独立于已运行任务；新请求检查不会覆盖运行参数。
    op_descriptor_check u_check (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .req_valid_i(check_valid_i),
        .descriptor_i(descriptor_i), .done_o(check_done_o), .ok_o(descriptor_ok_o),
        .result_bytes_o(candidate_bytes_o), .mac_bytes_o(candidate_mac_bytes_o),
        .pixels_o(checked_pixels_w), .inputs_o(checked_inputs_w),
        .weight_words_o(checked_weights_w), .param_words_o(checked_params_w),
        .words_b_o(checked_words_b_w)
    );

    op_core_bank_before u_bank (
        .clk_i(clk_i), .rst_n_i(rst_n_i && state_r != RESET_CORE),
        .op_i(op_w), .cfg_valid_i(cfg_valid_w), .cfg_ready_o(cfg_ready_w),
        .cin_i(cin_w), .cin_b_i(cin_b_w), .cout_i(cout_w), .pixels_i(pixels_w[18:0]),
        .tile_base_i(tile_base_r[18:0]), .tile_words_i(tile_words_w),
        .width_i(width_w), .height_i(height_w), .groups_i(groups_w),
        .words_b_i(words_b_r), .shift_i(d_r[85:80]),
        .raw_i(raw_w), .int16_i(int16_w), .clamp_min_i(d_r[95:88]), .clamp_max_i(d_r[103:96]),
        .add_group_i(group_r), .add_last_i(group_r == groups_w - 6'd1), .add_params_i(add_params_r),
        .weights_valid_i(state_r == LOAD_WEIGHTS && reader_rsp_w), .weights_ready_o(weights_ready_w),
        .params_valid_i(bank_params_valid_w), .params_ready_o(params_ready_w),
        .load_data_i(bank_load_data_w), .start_valid_i(state_r == START), .start_ready_o(start_ready_w),
        .in_valid_i(bank_in_valid_w), .in_ready_o(bank_in_ready_w), .in_data_i(bank_in_data_w),
        .in_b_valid_i(bank_b_valid_w), .in_b_ready_o(bank_b_ready_w), .in_b_data_i(reader_data_w),
        .rd_valid_o(bank_rd_valid_w), .rd_ready_i(bank_rd_ready_w), .rd_addr_o(bank_rd_addr_w),
        .rd_source_o(bank_rd_source_w),
        .rsp_valid_i(state_r == RUN && reader_rsp_w &&
                     (op_w == 8'd1 || op_w == 8'd5 || op_w == 8'd12)),
        .rsp_source_i(reader_source_r),
        .rsp_ready_o(bank_rsp_ready_w), .rsp_data_i(reader_data_w[127:0]),
        .out_valid_o(bank_out_valid_w), .out_ready_i(bank_out_ready_w), .out_data_o(bank_data_w),
        .out_mac_o(bank_mac_w), .out_pixel_o(bank_pixel_w), .out_group_o(bank_group_w),
        .out_mask_o(bank_mask_w), .out_last_o(bank_last_w), .done_o(bank_done_w)
    );
    op_feature_reader u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .clear_i(state_r == RESET_CORE),
        .req_valid_i(reader_req_w), .req_ready_o(reader_ready_w), .req_mode_i(reader_mode_w),
        .req_addr_i(reader_addr_w), .req_pixel_i(reader_pixel_w),
        .slices_i(d_r[351:320]), .center_i(d_r[383:352]),
        .rsp_valid_o(reader_rsp_w), .rsp_ready_i(reader_rsp_ready_w),
        .rsp_data_o(reader_data_w), .rsp_error_o(reader_error_w),
        .mem_valid_o(reader_mem_w), .mem_ready_i(reader_mem_ready_w), .mem_addr_o(reader_mem_addr_w),
        .mem_rsp_valid_i(mem_rsp_valid_i && !response_writer_r && state_r != FLUSH_RETURN), .mem_rsp_ready_o(reader_mem_rsp_ready_w),
        .mem_rsp_data_i(mem_rsp_data_i), .mem_rsp_error_i(mem_rsp_error_i)
    );
    op_feature_writer u_writer (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .req_valid_i(writer_req_w), .req_ready_o(writer_ready_w),
        .req_addr_i(writer_addr_w), .req_data_i(writer_data_w), .req_bytes_i(writer_bytes_w),
        .done_o(writer_done_w), .error_o(writer_error_w),
        .mem_valid_o(writer_mem_w), .mem_ready_i(writer_mem_ready_w), .mem_addr_o(writer_mem_addr_w),
        .mem_data_o(writer_mem_data_w), .mem_mask_o(writer_mem_mask_w),
        .mem_rsp_valid_i(mem_rsp_valid_i && response_writer_r), .mem_rsp_ready_o(writer_mem_rsp_ready_w),
        .mem_rsp_error_i(mem_rsp_error_i)
    );
    // 零掩码写是DDR排空屏障，不产生字节写入；完成状态必须晚于最终B响应。
    assign mem_valid_o = !pending_r && (state_r == FLUSH_REQUEST || writer_mem_w || reader_mem_w);
    assign mem_write_o = state_r == FLUSH_REQUEST || writer_mem_w;
    assign mem_addr_o = state_r == FLUSH_REQUEST ? 31'd0 : writer_mem_w ? writer_mem_addr_w : reader_mem_addr_w;
    assign mem_data_o = writer_mem_data_w;
    assign mem_mask_o = state_r == FLUSH_REQUEST ? 32'd0 : writer_mem_mask_w;
    assign writer_mem_ready_w = !pending_r && mem_ready_i;
    assign reader_mem_ready_w = !pending_r && !writer_mem_w && mem_ready_i;
    assign mem_rsp_ready_o = state_r == FLUSH_RETURN ? 1'b1 : response_writer_r ? writer_mem_rsp_ready_w : reader_mem_rsp_ready_w;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin pending_r <= 1'b0; response_writer_r <= 1'b0; end
        else begin
            if (mem_valid_o && mem_ready_i) begin pending_r <= 1'b1; response_writer_r <= writer_mem_w; end
            if (mem_rsp_valid_i && mem_rsp_ready_o) pending_r <= 1'b0;
        end
    end

    always_comb begin
        reader_req_w = 1'b0; reader_mode_w = 2'd0;
        reader_addr_w = base_a_w[30:0]; reader_pixel_w = bank_rd_addr_w;
        reader_rsp_ready_w = 1'b0;
        bank_rd_ready_w = 1'b0; bank_in_valid_w = 1'b0; bank_b_valid_w = 1'b0;
        bank_in_data_w = reader_data_w;
        case (state_r)
            LOAD_WEIGHTS: begin
                reader_req_w = 1'b1; reader_mode_w = 2'd1;
                reader_addr_w = weight_base_w[30:0] + (load_count_r[24:0]<<6);
                if (op_w == 8'd8 || op_w == 8'd9) begin
                    reader_mode_w = 2'd0;
                    reader_addr_w = weight_base_w[30:0] + (load_count_r[26:0]<<4);
                end else if (op_w == 8'd11) begin
                    // 融合算子先装每组DW3的9个16B拍，再装DW5的25个16B拍。
                    reader_mode_w = 2'd0;
                    if (load_count_r < ({26'd0,groups_w} * 32'd9))
                        reader_addr_w = weight_base_w[30:0] + (load_count_r[26:0]<<4);
                    else
                        reader_addr_w = d_r[255:224] +
                            ((load_count_r - ({26'd0,groups_w} * 32'd9)) << 4);
                end else if (op_w == 8'd12) begin
                    if (load_count_r < p12_weight_a_words_w)
                        reader_addr_w = weight_base_w[30:0] + (load_count_r[24:0]<<6);
                    else
                        reader_addr_w = mac_base_w[30:0] +
                            ((load_count_r - p12_weight_a_words_w) << 6);
                end
                reader_rsp_ready_w = weights_ready_w;
            end
            LOAD_PARAMS: begin
                if (op_w != 8'd12) begin
                    reader_req_w = 1'b1; reader_mode_w = 2'd1;
                    reader_addr_w = param_base_w[30:0] + (load_count_r[24:0]<<6);
                    reader_rsp_ready_w = params_ready_w;
                end
            end
            LOAD_ADD: begin
                reader_req_w = 1'b1; reader_mode_w = 2'd1;
                reader_addr_w = param_base_w[30:0] + ({25'd0,group_r}<<8) + (load_count_r[24:0]<<6);
                reader_rsp_ready_w = 1'b1;
            end
            RUN: case (op_w)
                8'd1, 8'd5: begin
                    reader_req_w = bank_rd_valid_w; bank_rd_ready_w = reader_ready_w;
                    reader_rsp_ready_w = bank_rsp_ready_w;
                    if (op_w == 8'd1 && online_w) reader_mode_w = 2'd2;
                    else reader_addr_w = (bank_rd_source_w ? base_b_concat_w[30:0] : base_a_w[30:0]) + (bank_rd_addr_w[26:0]<<4);
                end
                8'd6: begin
                    reader_mode_w = 2'd1;
                    reader_req_w = input_count_r < pixels_w;
                    reader_addr_w = (add_a_valid_r ? base_b_w[30:0] : base_a_w[30:0]) +
                        ((group_pixel_base_r[30:0]+input_count_r[30:0])<<6);
                    reader_rsp_ready_w = add_a_valid_r ? bank_b_ready_w : 1'b1;
                    bank_in_data_w = add_a_r;
                    bank_in_valid_w = add_a_valid_r;
                    bank_b_valid_w = add_a_valid_r && reader_rsp_w;
                end
                8'd12: begin
                    reader_req_w = bank_rd_valid_w; bank_rd_ready_w = reader_ready_w;
                    reader_rsp_ready_w = bank_rsp_ready_w;
                    reader_addr_w = (bank_rd_source_w ? base_b_w[30:0] : base_a_w[30:0]) +
                                    (bank_rd_addr_w[26:0] << 4);
                end
                default: begin
                    // 融合 DW3/DW5 每个组只消费一遍输入；input_count_r 是当前组
                    // 的局部像素计数，group_pixel_base_r 是输入中的绝对像素基址。
                    // 其它默认算子仍使用连续的全局输入计数。
                    if (op_w == 8'd11) begin
                        reader_req_w = input_count_r < pixels_w;
                        reader_addr_w = base_a_w[30:0] +
                            ((group_pixel_base_r + input_count_r) << 4);
                    end else begin
                        reader_req_w = input_count_r < total_inputs_w;
                        reader_addr_w = base_a_w[30:0] + (input_count_r[26:0]<<4);
                    end
                    reader_rsp_ready_w = bank_in_ready_w;
                    bank_in_valid_w = reader_rsp_w;
                end
            endcase
            default: ;
        endcase
        load_fire_w = (reader_rsp_w && reader_rsp_ready_w &&
            (state_r == LOAD_WEIGHTS || state_r == LOAD_ADD ||
             (state_r == LOAD_PARAMS && op_w != 8'd12))) ||
            (state_r == LOAD_PARAMS && op_w == 8'd12 && bank_params_valid_w && params_ready_w);
        in_fire_w = state_r == RUN && reader_rsp_w && reader_rsp_ready_w && op_w != 8'd12;
    end

    always_comb begin
        writer_req_w = 1'b0; writer_addr_w = 31'd0; writer_data_w = saved_data_r; writer_bytes_w = 9'd16;
        case (output_r)
            O_Q_REQUEST: begin
                writer_req_w = 1'b1;
                writer_addr_w = saved_linear_addr_r[30:0];
                case (op_w)
                    8'd1: begin
                        writer_data_w = 3200'd0;
                        if (int16_w) begin
                            writer_bytes_w = 9'd8; writer_data_w[63:0] = saved_data_r[63:0];
                            writer_addr_w = saved_q_addr_r;
                        end else begin
                            writer_bytes_w = 9'd4;
                            for (int p=0; p<4; p++) writer_data_w[p*8 +: 8] = saved_data_r[p*16 +: 8];
                            writer_addr_w = saved_q_addr_r;
                        end
                    end
                    8'd3: writer_bytes_w = 9'd144;
                    8'd4: writer_bytes_w = 9'd400;
                    8'd8, 8'd9: begin
                        // DW adapter 不提供可靠的 pixel/group 标签；引擎的
                        // output_addr_r 已按输出握手维护连续的 [group][pixel] 地址。
                        writer_bytes_w = 9'd64;
                        writer_addr_w = saved_linear_addr_r[30:0];
                    end
                    8'd11: begin
                        // 融合 DW3/DW5+Add 同样按每个 P16 结果连续写回。
                        writer_bytes_w = 9'd16;
                        writer_addr_w = saved_linear_addr_r[30:0];
                    end
                    8'd12: begin
                        writer_data_w = 3200'd0;
                        writer_data_w[127:0] = saved_data_r[127:0];
                        writer_bytes_w = 9'd16;
                        writer_addr_w = saved_q_addr_r;
                    end
                    default: ;
                endcase
            end
            O_MAC_REQUEST: begin
                writer_req_w = 1'b1; writer_data_w = {3072'd0,saved_mac_r}; writer_bytes_w = 9'd16;
                writer_addr_w = saved_mac_addr_r;
            end
            default: ;
        endcase
        if (state_r == CLEAR) begin
            writer_req_w = !clear_wait_r; writer_addr_w = clear_addr_r[30:0];
            writer_data_w = 3200'd0; writer_bytes_w = 9'd32;
            if (out_base_w+result_bytes_o-clear_addr_r < 32'd32)
                writer_bytes_w = 9'(out_base_w+result_bytes_o-clear_addr_r);
        end
        output_nxt = output_r;
        case (output_r)
            O_IDLE: if (output_fire_w) output_nxt = (op_w == 8'd1 || op_w == 8'd12) ? O_INDEX : O_Q_REQUEST;
            O_INDEX: output_nxt = O_PIXEL;
            O_PIXEL: output_nxt = O_ADDRESS;
            O_ADDRESS: output_nxt = raw_w ? O_MAC_REQUEST : O_Q_REQUEST;
            O_Q_REQUEST: if (writer_ready_w) output_nxt = O_Q_WAIT;
            O_Q_WAIT: if (writer_done_w) output_nxt = op_w == 8'd1 && debug_w ? O_MAC_REQUEST : O_IDLE;
            O_MAC_REQUEST: if (writer_ready_w) output_nxt = O_MAC_WAIT;
            O_MAC_WAIT: if (writer_done_w) output_nxt = O_IDLE;
            default: output_nxt = O_IDLE;
        endcase
    end
    assign bank_out_ready_w = state_r == RUN && output_r == O_IDLE && writer_ready_w;
    assign output_fire_w = bank_out_valid_w && bank_out_ready_w;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin output_r <= O_IDLE; output_count_r <= 32'd0; end
        else begin
            output_r <= output_nxt;
            if (state_r == RESET_CORE) output_count_r <= 32'd0;
            if (output_fire_w) output_count_r <= output_count_r + 32'd1;
        end
    end
    // 地址计数在握手拍已经递增，保存本拍地址标签，不能写到下一个像素。
    always_ff @(posedge clk_i) begin
        // PW 地址乘法、像素偏移、基址加法分拍；DDR 请求仅在地址锁存后发出。
        if (output_r == O_INDEX) begin
            q_index_r <= (op_w == 8'd12 ? {25'd0,saved_group_r} :
                (int16_w ? {25'd0,saved_group_r} : {27'd0,saved_group_r[6:2]})) * pixels_r;
            mac_index_r <= (d_r[12] ? {27'd0,saved_group_r[6:2]} : {25'd0,saved_group_r}) * pixels_r;
        end
        if (output_r == O_PIXEL) begin
            q_pixel_r <= q_index_r + {13'd0,saved_pixel_r};
            mac_pixel_r <= mac_index_r + {13'd0,saved_pixel_r};
        end
        if (output_r == O_ADDRESS) begin
            saved_q_addr_r <= out_base_w[30:0] +
                (op_w == 8'd12 ? (q_pixel_r[30:0]<<4) :
                 (int16_w ? (q_pixel_r[30:0]<<3) : ((q_pixel_r[30:0]<<4) + {27'd0,saved_group_r[1:0],2'd0})));
            // flags.bit4 将 raw PW 写为 [group16][pixel][lane16 x INT32]，可直接接 Add。
            saved_mac_addr_r <= (raw_w ? out_base_w[30:0] : mac_base_w[30:0]) +
                (d_r[12] ? ((mac_pixel_r[30:0]<<6) + {25'd0,saved_group_r[1:0],4'd0}) : (mac_pixel_r[30:0]<<4));
        end
        if (state_r == RESET_CORE) output_addr_r <= out_base_w;
        if (output_fire_w) begin
            // 仅捕获本算子的有效宽度，Concat/Add/PW不再驱动3200位公共使能。
            saved_data_r[127:0] <= bank_data_w[127:0];
            case (op_w)
                8'd3: saved_data_r[1151:128] <= bank_data_w[1151:128];
                8'd4: saved_data_r[3199:128] <= bank_data_w[3199:128];
                8'd8, 8'd9: saved_data_r[511:128] <= bank_data_w[511:128];
                default: ;
            endcase
            saved_pixel_r <= bank_pixel_w; saved_group_r <= bank_group_w;
            saved_output_count_r <= output_count_r;
            saved_linear_addr_r <= output_addr_r;
            case (op_w)
                8'd3: output_addr_r <= output_addr_r + 32'd144;
                8'd4: output_addr_r <= output_addr_r + 32'd400;
                8'd8, 8'd9: output_addr_r <= output_addr_r + 32'd64;
                default: output_addr_r <= output_addr_r + 32'd16;
            endcase
            for (int p=0; p<4; p++) begin
                saved_mac_r[p*32 +: 32] <= bank_mask_w[p] ? bank_mac_w[p*32 +: 32] : 32'd0;
                if (op_w == 8'd1 && !bank_mask_w[p]) saved_data_r[p*16 +: 16] <= 16'd0;
            end
        end
        if (state_r == LOAD_ADD && load_fire_w) add_params_r[load_count_r[1:0]*512 +: 512] <= reader_data_w;
        if (state_r == RUN && op_w == 8'd6 && in_fire_w && !add_a_valid_r) add_a_r <= reader_data_w;
        if (run_valid_i && run_ready_o) begin
            d_r <= descriptor_i;
            pixels_r <= checked_pixels_w; total_inputs_r <= checked_inputs_w;
            weight_words_r <= checked_weights_w; param_words_r <= checked_params_w;
            words_b_r <= checked_words_b_w;
        end
    end
    // 顺序流结果统一采用已保存的输出序号。
    always_comb begin
        // reader_ready_w 只表示 reader 当前处于 IDLE；在同一拍发出最后一笔
        // bank 读请求时它仍可能为 1。必须等请求/返回通道都空闲后再离开 RUN，
        // 否则最后一笔响应会被 LOAD_ADD 状态的门控丢弃，PW 永远停在 FILL。
        drained_w = output_r == O_IDLE && writer_ready_w && reader_ready_w &&
                    !reader_req_w && !reader_rsp_w && !reader_mem_w && !pending_r;
        run_ready_o = state_r == IDLE && descriptor_ok_o;
        busy_o = state_r != IDLE; done_o = state_r == FINISH;
        error_o = error_r; aborted_o = aborted_r;
        cfg_valid_w = state_r == CONFIGURE;
        state_nxt = state_r;
        case (state_r)
            IDLE: if (run_valid_i && run_ready_o) state_nxt = RESET_CORE;
            RESET_CORE: begin
                if (op_w == 8'd6) state_nxt = LOAD_ADD;
                else if (op_w == 8'd1 && !raw_w && !int16_w && cout_w[3:0] != 4'd0) state_nxt = CLEAR;
                else state_nxt = CONFIGURE;
            end
            CLEAR: if (writer_done_w && clear_addr_r+32'd32 >= out_base_w+result_bytes_o) state_nxt = CONFIGURE;
            CONFIGURE: if (cfg_ready_w) begin
                if (op_w == 8'd11 && add_loaded_r) state_nxt = RUN;
                else if (op_w == 8'd12 && !p12_pw_loaded_r) state_nxt = LOAD_WEIGHTS;
                else if (op_w == 8'd12 && !p12_pw_started_r) state_nxt = START;
                else if (op_w == 8'd1 || op_w == 8'd8 || op_w == 8'd9 || op_w == 8'd11)
                    state_nxt = LOAD_WEIGHTS;
                else state_nxt = RUN;
            end
            LOAD_WEIGHTS: if (load_fire_w && load_count_r+32'd1 == weight_words_w)
                state_nxt = (op_w == 8'd1 || op_w == 8'd12) ? LOAD_PARAMS :
                            (op_w == 8'd11 ? LOAD_ADD : RUN);
            LOAD_PARAMS: if (load_fire_w && load_count_r+32'd1 == param_words_w)
                state_nxt = op_w == 8'd12 ? LOAD_ADD : START;
            LOAD_ADD: if (load_fire_w && load_count_r == 32'd3) state_nxt = CONFIGURE;
            START: if (start_ready_w) state_nxt = RUN;
            RUN: if (core_done_r && drained_w) begin
                if ((op_w == 8'd6 || op_w == 8'd11) && group_r < groups_w - 6'd1)
                    state_nxt = LOAD_ADD;
                else if (op_w == 8'd12 &&
                         (group_r < groups_w - 6'd1 || tile_base_r+{27'd0,tile_words_w} < pixels_r))
                    state_nxt = LOAD_ADD;
                else state_nxt = FLUSH_REQUEST;
            end
            FLUSH_REQUEST: if (mem_valid_o && mem_ready_i) state_nxt = FLUSH_RETURN;
            FLUSH_RETURN: if (mem_rsp_valid_i) state_nxt = FINISH;
            FINISH: state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= IDLE; input_count_r <= 32'd0; load_count_r <= 32'd0;
            group_r <= 6'd0; core_done_r <= 1'b0; add_a_valid_r <= 1'b0; add_loaded_r <= 1'b0;
            p12_pw_loaded_r <= 1'b0; p12_pw_started_r <= 1'b0; tile_base_r <= 32'd0;
            reader_source_r <= 1'b0;
            error_r <= 1'b0; aborted_r <= 1'b0; clear_wait_r <= 1'b0;
            clear_addr_r <= 32'd0; result_bytes_o <= 32'd0; mac_bytes_o <= 32'd0;
        end else begin
            state_r <= state_nxt;
            if (run_valid_i && run_ready_o) begin
                result_bytes_o <= candidate_bytes_o; mac_bytes_o <= candidate_mac_bytes_o;
                error_r <= 1'b0; aborted_r <= 1'b0;
            end
            if (abort_i && busy_o) aborted_r <= 1'b1; // 安全中止：运行到排空边界，状态可查询。
            if (reader_rsp_w && reader_rsp_ready_w && reader_error_w) error_r <= 1'b1;
            if (state_r == LOAD_PARAMS && load_fire_w)
                if (op_w != 8'd12)
                    for (int p=0; p<4; p++)
                        if ($signed(reader_data_w[p*128+96 +: 16]) > $signed(reader_data_w[p*128+112 +: 16])) error_r <= 1'b1;
            if (state_r == LOAD_ADD && load_fire_w)
                for (int p=0; p<4; p++)
                    if (reader_data_w[p*128 +: 32] != {{10{reader_data_w[p*128+21]}},reader_data_w[p*128 +: 22]} ||
                        reader_data_w[p*128+32 +: 32] != {{10{reader_data_w[p*128+53]}},reader_data_w[p*128+32 +: 22]}) error_r <= 1'b1;
            if (writer_done_w && writer_error_w) error_r <= 1'b1;
            if (state_r == FLUSH_RETURN && mem_rsp_valid_i && mem_rsp_error_i) error_r <= 1'b1;
            if (state_r == RESET_CORE) begin
                group_r <= 6'd0; input_count_r <= 32'd0; load_count_r <= 32'd0;
                core_done_r <= 1'b0; add_a_valid_r <= 1'b0; add_loaded_r <= 1'b0; clear_addr_r <= out_base_w;
                p12_pw_loaded_r <= 1'b0; p12_pw_started_r <= 1'b0; tile_base_r <= 32'd0;
                reader_source_r <= 1'b0;
                clear_wait_r <= 1'b0;
            end
            if (state_r == RUN && op_w == 8'd12 && bank_rd_valid_w && reader_ready_w)
                reader_source_r <= bank_rd_source_w;
            if (state_r == CONFIGURE && cfg_ready_w && op_w == 8'd12 && !p12_pw_loaded_r)
                p12_pw_loaded_r <= 1'b1;
            if (state_r == START && start_ready_w && op_w == 8'd12)
                p12_pw_started_r <= 1'b1;
            if (state_r == CLEAR) begin
                if (writer_req_w && writer_ready_w) clear_wait_r <= 1'b1;
                if (writer_done_w) begin clear_wait_r <= 1'b0; clear_addr_r <= clear_addr_r+32'd32; end
            end
            if (load_fire_w) load_count_r <= load_count_r+32'd1;
            if (state_r != state_nxt) load_count_r <= 32'd0;
            if (state_r == LOAD_ADD && load_fire_w && load_count_r == 32'd3)
                add_loaded_r <= 1'b1;
            if (state_r == RUN) begin
                if (bank_done_w) core_done_r <= 1'b1;
                if (in_fire_w) begin
                    if (op_w == 8'd6) begin
                        add_a_valid_r <= !add_a_valid_r;
                        if (add_a_valid_r) input_count_r <= input_count_r+32'd1;
                    end else input_count_r <= input_count_r+32'd1;
                    if (op_w == 8'd7 && input_count_r+32'd1 == total_inputs_w) core_done_r <= 1'b1;
                end
                if (state_nxt == LOAD_ADD) begin
                    core_done_r <= 1'b0;
                    if (op_w == 8'd12) begin
                        if (group_r < groups_w - 6'd1) group_r <= group_r+6'd1;
                        else begin
                            group_r <= 6'd0;
                            tile_base_r <= tile_base_r+{27'd0,tile_words_w};
                        end
                    end else begin
                        group_r <= group_r+6'd1;
                        if (op_w == 8'd6 || op_w == 8'd11) input_count_r <= 32'd0;
                    end
                end
            end
        end
    end
    // Add 的组基址以递增代替运行拍 group×pixels 宽乘法。
    always_ff @(posedge clk_i) begin
        if (state_r == RESET_CORE) group_pixel_base_r <= 32'd0;
        else if (state_r == RUN && state_nxt == LOAD_ADD &&
                 (op_w == 8'd6 || op_w == 8'd11))
            group_pixel_base_r <= group_pixel_base_r + pixels_r;
    end
endmodule
