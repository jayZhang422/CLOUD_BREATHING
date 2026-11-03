`timescale 1ns/1ps
// 【文件类型：.sv】上板准备候选调度，基于现有调度器扩宽通道/组标签。
// 权重/参数事务由外部 op_coeff_split 接到只读源；本文件不例化 ROM IP。
// 描述符 byte52/54 为可选 LE16 Cin/Cout；为零时兼容 byte2/3。
// 原始 BIN 保留 ZYX；PW 的 INT8 输出按 group16/pixel/lane 落址。
// 默认生产构建关闭op3/4窗口与op8/9独立DW导出；调试构建可显式开启。
module op_engine #(
`ifdef OP_ENABLE_WIDE_DEBUG
    parameter bit ENABLE_WIDE_DEBUG = 1'b1
`else
    parameter bit ENABLE_WIDE_DEBUG = 1'b0
`endif
) (
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
    input logic [255:0] mem_rsp_data_i, // 数据载荷，低位承载首字节或首 lane
    output logic [1279:0] perf_data_o // 16个64位核心计数和8个32位DDR计数
);
    localparam int RESULT_BITS = ENABLE_WIDE_DEBUG ? 3200 : 128;
    localparam int WRITER_BITS = ENABLE_WIDE_DEBUG ? 3200 : 256;
    typedef enum logic [3:0] {IDLE, RESET_CORE, CLEAR, CONFIGURE,
        LOAD_WEIGHTS, LOAD_PARAMS, LOAD_ADD, START, RUN, FLUSH_REQUEST, FLUSH_RETURN, FINISH, ADD_COMMIT} state_t;
    state_t state_r, state_nxt;
    typedef enum logic [3:0] {O_IDLE, O_INDEX, O_PIXEL, O_ADDRESS,
        O_Q_REQUEST, O_Q_WAIT, O_MAC_REQUEST, O_MAC_WAIT} output_state_t;
    output_state_t output_r, output_nxt;
    logic [511:0] d_r;
    logic [7:0] op_w;
    logic [3:0] core_op_r;
    logic [9:0] cin_w, cin_b_w, cout_w;
    logic [9:0] width_w, height_w;
    logic [5:0] groups_w, group_r;
    logic [31:0] pixels_w, input_count_r, output_count_r, load_count_r, clear_addr_r;
    logic [18:0] tile_base_r, tile_remaining_r;
    logic [4:0] tile_words_r, tile_words_w;
    logic tile_last_r;
    logic [18:0] next_tile_base_r, next_tile_remaining_r;
    logic [4:0] next_tile_words_r;
    logic next_tile_last_r;
    logic [31:0] saved_output_count_r;
    logic [31:0] weight_words_w, param_words_w, total_inputs_w, p12_weight_a_words_w;
    logic [8:0] p12_output_groups_r;
    logic [6:0] p12_input_groups_r;
    logic [15:0] p12_weight_a_words_r;
    logic [9:0] dw3_weight_words_r;
    logic [30:0] weight_b_base_r;
    logic [31:0] pixels_r, total_inputs_r, weight_words_r, param_words_r, words_b_r;
    logic [31:0] checked_pixels_w, checked_inputs_w, checked_weights_w, checked_params_w, checked_words_b_w;
    logic [31:0] group_pixel_base_r, output_addr_r, saved_linear_addr_r;
    logic [30:0] run_a_base_r, run_b_base_r, add_param_base_r;
    logic group_last_r;
    logic [30:0] saved_q_addr_r, saved_mac_addr_r;
    logic [31:0] q_index_r, mac_index_r, q_pixel_r, mac_pixel_r;
    logic [31:0] base_a_w, base_b_w, base_b_concat_w, out_base_w, mac_base_w, weight_base_w, param_base_w;
    logic online_w, debug_w, raw_w, int16_w, core_done_r, error_r, aborted_r;
    logic [2047:0] add_params_r;
    logic add_cache_hit_w, add_cache_read_en_w, add_cache_write_en_w;
    logic [1:0] add_cache_data_valid_r;
    logic [2:0] add_cache_issue_count_r;
    logic [6:0] add_cache_addr_w;
    logic [511:0] add_cache_data_w;
    logic [511:0] add_load_data_w;
    (* max_fanout = 32 *) logic add_load_valid_r;
    logic [1:0] add_load_index_r;
    logic [511:0] add_load_data_r;
    logic add_cache_write_valid_r;
    logic [6:0] add_cache_write_addr_r;
    logic [511:0] add_cache_write_data_r;
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
    logic [RESULT_BITS-1:0] bank_data_w, saved_data_r;
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
    logic [WRITER_BITS-1:0] writer_data_w;
    logic [8:0] writer_bytes_w;
    logic writer_mem_w, writer_mem_ready_w, writer_mem_rsp_ready_w;
    logic [30:0] writer_mem_addr_w;
    logic [255:0] writer_mem_data_w;
    logic [31:0] writer_mem_mask_w;
    logic pending_r, clear_wait_r, writer_idle_w;
    logic [1:0] mem_source_ready_w, mem_response_valid_w;
    logic load_fire_w, load_last_w, in_fire_w, output_fire_w, drained_w, run_drained_r;
    logic advance_group_w;
    logic move_w, stream_writer_w, move_start_w, stream_writer_start_w, stream_writer_started_r;
    logic dw_stream_w, dw_stream_start_r, cfg_accepted_r;
    logic packed_writer_start_r;
    logic move_mode_r, pw_pack_mode_r, stream_writer_mode_r, pw_reader_mode_r;
    logic fuse_skip_r, fuse_skip_started_r, fuse_restart_w, move_bypass_w;
    logic move_valid_w, move_ready_w, move_last_w;
    logic move_read_idle_w, move_read_error_w, move_read_mem_w, move_read_rsp_ready_w;
    logic [127:0] move_data_w;
    logic [30:0] move_read_addr_w;
    logic move_write_ready_w, move_write_idle_w, move_write_error_w, move_write_mem_w;
    logic [30:0] move_write_addr_w;
    logic [255:0] move_write_data_w;
    logic [31:0] move_write_mask_w;
    logic core_out_valid_w, core_last_w, core_done_w;
    logic [RESULT_BITS-1:0] core_data_w;
    logic pw_pack_w, pw_pack_ready_w, pw_pack_valid_w, pw_pack_last_w, pw_pack_idle_w;
    logic [127:0] pw_pack_input_w;
    logic [127:0] pw_pack_data_w;
    logic [30:0] pw_pack_address_w, stream_address_r;
    logic stream_valid_w, stream_last_w;
    logic [127:0] stream_data_w;
    logic [30:0] stream_address_w;
    logic [18:0] stream_group_pixel_r, stream_group_last_pixel_r;
    logic pw_reader_w, pw_reader_idle_w, pw_reader_error_w, pw_reader_source_w;
    logic pw_reader_ready_w, pw_reader_rsp_w, pw_reader_mem_w, pw_reader_mem_rsp_ready_w;
    logic [127:0] pw_reader_data_w;
    logic [30:0] pw_reader_addr_w;
    logic legacy_ready_w, legacy_rsp_w, legacy_error_w, legacy_mem_w, legacy_mem_rsp_ready_w;
    logic [511:0] legacy_data_w;
    logic [30:0] legacy_mem_addr_w;
    logic core_direct_valid_w, core_direct_ready_w, core_direct_last_w;
    logic [RESULT_BITS-1:0] core_direct_data_w;
    logic [127:0] core_direct_mac_w;
    logic [18:0] core_direct_pixel_w;
    logic [6:0] core_direct_group_w;
    logic [3:0] core_direct_mask_w;
    logic [RESULT_BITS+158:0] output_queue_r[0:1];
    logic output_head_r, output_tail_r, output_push_w, output_pop_w;
    logic [1:0] output_queued_r;
    assign pw_reader_w = state_r == RUN && pw_reader_mode_r;
    assign reader_ready_w = pw_reader_w ? pw_reader_ready_w : legacy_ready_w;
    assign reader_rsp_w = pw_reader_w ? pw_reader_rsp_w : legacy_rsp_w;
    assign reader_data_w = pw_reader_w ? {384'd0,pw_reader_data_w} : legacy_data_w;
    assign reader_error_w = pw_reader_w ? pw_reader_error_w : legacy_error_w;
    assign reader_mem_w = pw_reader_w ? pw_reader_mem_w : legacy_mem_w;
    assign reader_mem_addr_w = pw_reader_w ? pw_reader_addr_w : legacy_mem_addr_w;
    assign reader_mem_rsp_ready_w = pw_reader_w ? pw_reader_mem_rsp_ready_w : legacy_mem_rsp_ready_w;
    // 两槽寄存缓冲：核心ready只看本地占用，切断writer至DW/PW量化的反压链。
    assign core_direct_ready_w = output_queued_r < 2'd2;
    assign core_out_valid_w = output_queued_r != 2'd0;
    assign {core_last_w,bank_mask_w,bank_group_w,bank_pixel_w,bank_mac_w,core_data_w} = output_queue_r[output_head_r];
    assign output_push_w = core_direct_valid_w && core_direct_ready_w;
    assign output_pop_w = core_out_valid_w && bank_out_ready_w && !move_bypass_w;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin output_queued_r <= 2'd0; output_head_r <= 1'b0; output_tail_r <= 1'b0; end
        else if (state_r == RESET_CORE) begin output_queued_r <= 2'd0; output_head_r <= 1'b0; output_tail_r <= 1'b0; end
        else begin
            if (output_push_w) output_tail_r <= !output_tail_r;
            if (output_pop_w) output_head_r <= !output_head_r;
            case ({output_push_w,output_pop_w})
                2'b10: output_queued_r <= output_queued_r + 2'd1;
                2'b01: output_queued_r <= output_queued_r - 2'd1;
                default: ;
            endcase
        end
    end
    always_ff @(posedge clk_i) if (output_push_w)
        output_queue_r[output_tail_r] <= {core_direct_last_w,core_direct_mask_w,core_direct_group_w,
            core_direct_pixel_w,core_direct_mac_w,core_direct_data_w};

    assign move_w = move_mode_r;
    // op11每组顺序读P16，复用已有8笔在途FIFO；装载阶段仍走参数reader。
    assign dw_stream_w = op_w == 8'd11 && state_r == RUN;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin dw_stream_start_r <= 1'b0; cfg_accepted_r <= 1'b0; end
        else begin
            dw_stream_start_r <= op_w == 8'd11 && add_loaded_r && cfg_valid_w && cfg_ready_w;
            cfg_accepted_r <= cfg_valid_w && cfg_ready_w;
        end
    end
    // op13复用Upsample行缓存；A直接写最终Concat，末输出后重启读流接skip。
    assign move_bypass_w = op_w == 8'd5 || (op_w == 8'd13 && fuse_skip_r);
    assign fuse_restart_w = state_r == RUN && op_w == 8'd13 &&
        fuse_skip_r && !fuse_skip_started_r && move_read_idle_w;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin fuse_skip_r <= 1'b0; fuse_skip_started_r <= 1'b0; end
        else if (state_r == RESET_CORE) begin fuse_skip_r <= 1'b0; fuse_skip_started_r <= 1'b0; end
        else begin
            if (op_w == 8'd13 && output_fire_w && bank_last_w && !fuse_skip_r)
                fuse_skip_r <= 1'b1;
            if (fuse_restart_w) fuse_skip_started_r <= 1'b1;
        end
    end
    // 组切换只依赖RUN本地条件，避免完整FSM次态把装载末拍判断串入计数器CE。
    assign advance_group_w = state_r == RUN && run_drained_r &&
        (((op_w == 8'd6 || op_w == 8'd11) && !group_last_r) ||
         (op_w == 8'd12 && (!group_last_r || !tile_last_r)));
    // 搬运配置ready含尺寸检查，先寄存单拍启动，载荷在随后的RUN保持稳定。
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            move_start_w <= 1'b0;
            packed_writer_start_r <= 1'b0;
        end else begin
            move_start_w <= move_w && cfg_valid_w && cfg_ready_w;
            // 写回器启动晚一拍，不让PW尺寸合法性组合链驱动其宽数据寄存器。
            packed_writer_start_r <= !move_w &&
                (op_w == 8'd11 || op_w == 8'd12 || pw_pack_w) &&
                cfg_valid_w && cfg_ready_w && !stream_writer_started_r;
        end
    end
    assign pw_pack_w = pw_pack_mode_r;
    assign stream_writer_w = stream_writer_mode_r;
    assign stream_writer_start_w = move_w ? move_start_w : packed_writer_start_r;
    assign stream_valid_w = pw_pack_w ? pw_pack_valid_w : state_r == RUN && bank_out_valid_w;
    assign stream_data_w = pw_pack_w ? pw_pack_data_w : bank_data_w[127:0];
    assign stream_address_w = pw_pack_w ? pw_pack_address_w : stream_address_r;
    // op12按tile/group分段，段末冲刷半字；最终任务完成仍须等待FENCE。
    assign stream_last_w = pw_pack_w ? pw_pack_last_w : op_w == 8'd13 ?
        (fuse_skip_r && move_last_w) : op_w == 8'd12 ?
        {1'b0,bank_pixel_w[3:0]} == tile_words_r-5'd1 :
        op_w == 8'd11 ? stream_group_pixel_r == stream_group_last_pixel_r : bank_last_w;
    assign bank_out_valid_w = move_bypass_w ? move_valid_w : core_out_valid_w;
    assign bank_data_w = move_bypass_w ? RESULT_BITS'(move_data_w) : core_data_w;
    assign bank_last_w = move_bypass_w ? move_last_w : core_last_w;
    assign bank_done_w = op_w == 8'd13 ? fuse_skip_r && output_fire_w && move_last_w :
        op_w == 8'd5 ? output_fire_w && move_last_w : core_done_w;
    assign move_ready_w = state_r == RUN && (move_bypass_w ? bank_out_ready_w : bank_in_ready_w);

    assign op_w = d_r[7:0];
    assign online_w = d_r[8]; assign debug_w = d_r[9];
    assign raw_w = d_r[10]; assign int16_w = d_r[11];
    assign cin_w = d_r[431:416] == 16'd0 ? {2'd0,d_r[23:16]} : d_r[425:416];
    assign cin_b_w = d_r[457:448];
    assign cout_w = d_r[447:432] == 16'd0 ? {2'd0,d_r[31:24]} : d_r[441:432];
    assign width_w = d_r[41:32]; assign height_w = d_r[57:48];
    assign groups_w = d_r[69:64];
    assign pixels_w = pixels_r;
    assign tile_words_w = tile_words_r;
    assign p12_weight_a_words_w = {16'd0,p12_weight_a_words_r};
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
    op_descriptor_check #(.ENABLE_WIDE_DEBUG(ENABLE_WIDE_DEBUG)) u_check (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .req_valid_i(check_valid_i),
        .descriptor_i(descriptor_i), .done_o(check_done_o), .ok_o(descriptor_ok_o),
        .result_bytes_o(candidate_bytes_o), .mac_bytes_o(candidate_mac_bytes_o),
        .pixels_o(checked_pixels_w), .inputs_o(checked_inputs_w),
        .weight_words_o(checked_weights_w), .param_words_o(checked_params_w),
        .words_b_o(checked_words_b_w)
    );

    op_core_bank #(.ENABLE_WIDE_DEBUG(ENABLE_WIDE_DEBUG)) u_bank (
        .clk_i(clk_i), .rst_n_i(rst_n_i && state_r != RESET_CORE),
        .op_i(core_op_r), .cfg_valid_i(cfg_valid_w), .cfg_ready_o(cfg_ready_w),
        .cin_i(cin_w), .cin_b_i(cin_b_w), .cout_i(cout_w), .pixels_i(pixels_w[18:0]),
        .tile_base_i(tile_base_r[18:0]), .tile_words_i(tile_words_w),
        .width_i(width_w), .height_i(height_w), .groups_i(groups_w),
        .words_b_i(words_b_r), .shift_i(d_r[85:80]),
        .raw_i(raw_w), .debug_i(debug_w), .int16_i(int16_w),
        .clamp_min_i(d_r[95:88]), .clamp_max_i(d_r[103:96]),
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
        .rsp_source_i(pw_reader_w ? pw_reader_source_w : reader_source_r),
        .rsp_ready_o(bank_rsp_ready_w), .rsp_data_i(reader_data_w[127:0]),
        .out_valid_o(core_direct_valid_w), .out_ready_i(core_direct_ready_w && !move_bypass_w), .out_data_o(core_direct_data_w),
        .out_mac_o(core_direct_mac_w), .out_pixel_o(core_direct_pixel_w), .out_group_o(core_direct_group_w),
        .out_mask_o(core_direct_mask_w), .out_last_o(core_direct_last_w), .done_o(core_done_w)
    );
    assign add_cache_hit_w = op_w == 8'd12 && tile_base_r != 19'd0;
    // 参数装载与合法性检查共用同一数据源，缓存命中时不能检查reader的旧载荷。
    assign add_load_data_w = add_cache_hit_w ? add_cache_data_w : reader_data_w;
    assign add_cache_read_en_w = state_r == LOAD_ADD && add_cache_hit_w && add_cache_issue_count_r < 3'd4;
    assign add_cache_write_en_w = add_cache_write_valid_r;
    assign add_cache_addr_w = add_cache_write_en_w ? add_cache_write_addr_r :
                              {group_r[4:0],add_cache_issue_count_r[1:0]};
    op12_add_cache_bram u_op12_add_cache (
        // 原语输出寄存器需要继续使能一拍，将最后一笔读结果排出。
        .clka(clk_i), .ena(add_cache_read_en_w || add_cache_data_valid_r[0] || add_cache_write_en_w),
        .wea(add_cache_write_en_w), .addra(add_cache_addr_w),
        .dina(add_cache_write_data_r), .douta(add_cache_data_w)
    );
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            add_cache_issue_count_r <= 3'd0;
            add_cache_data_valid_r <= 2'b00;
            add_cache_write_valid_r <= 1'b0;
        end else begin
            add_cache_write_valid_r <= state_r == LOAD_ADD && op_w == 8'd12 && !add_cache_hit_w && reader_rsp_w;
            add_cache_data_valid_r <= {add_cache_data_valid_r[0],add_cache_read_en_w};
            if (state_r != LOAD_ADD) add_cache_issue_count_r <= 3'd0;
            else if (add_cache_read_en_w) add_cache_issue_count_r <= add_cache_issue_count_r + 3'd1;
        end
    end
    always_ff @(posedge clk_i) begin
        add_cache_write_addr_r <= {group_r[4:0],load_count_r[1:0]};
        add_cache_write_data_r <= reader_data_w;
    end
    op_move_reader u_move_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .start_i(move_start_w || fuse_restart_w || dw_stream_start_r),
        .base_a_i(op_w == 8'd11 ? run_a_base_r : fuse_restart_w ? base_b_w[30:0] : base_a_w[30:0]), .base_b_i(base_b_concat_w[30:0]),
        .words_a_i(op_w == 8'd11 ? pixels_r : fuse_restart_w ? words_b_r : total_inputs_r), .words_b_i(op_w == 8'd5 ? words_b_r : 32'd0),
        .valid_o(move_valid_w), .ready_i(move_ready_w), .data_o(move_data_w), .last_o(move_last_w),
        .idle_o(move_read_idle_w), .error_o(move_read_error_w),
        .mem_valid_o(move_read_mem_w), .mem_ready_i(reader_mem_ready_w), .mem_addr_o(move_read_addr_w),
        .mem_rsp_valid_i(mem_response_valid_w[0] && (move_w || dw_stream_w)), .mem_rsp_ready_o(move_read_rsp_ready_w),
        .mem_rsp_data_i(mem_rsp_data_i), .mem_rsp_error_i(mem_rsp_error_i)
    );
    assign pw_pack_input_w = bank_data_w[127:0];
    op_pw_pack u_pw_pack (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .start_i(pw_pack_w && state_r == START && start_ready_w),
        .base_i(out_base_w[30:0]), .pixels_i(pixels_r[18:0]), .cout_i(cout_w),
        .int16_i(int16_w),
        .valid_i(pw_pack_w && state_r == RUN && bank_out_valid_w), .ready_o(pw_pack_ready_w),
        .data_i(pw_pack_input_w), .pixel_i(bank_pixel_w), .group_i(bank_group_w),
        .valid_o(pw_pack_valid_w), .ready_i(move_write_ready_w && pw_pack_w),
        .data_o(pw_pack_data_w), .address_o(pw_pack_address_w), .last_o(pw_pack_last_w), .idle_o(pw_pack_idle_w)
    );
    op_move_writer #(.ADDRESS_PER_WORD(1'b1)) u_move_writer (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .start_i(stream_writer_start_w), .base_i(out_base_w[30:0]),
        .address_i(stream_address_w),
        .valid_i(stream_writer_w && stream_valid_w), .ready_o(move_write_ready_w),
        .data_i(stream_data_w), .last_i(stream_last_w),
        .idle_o(move_write_idle_w), .error_o(move_write_error_w),
        .mem_valid_o(move_write_mem_w), .mem_ready_i(writer_mem_ready_w),
        .mem_addr_o(move_write_addr_w), .mem_data_o(move_write_data_w), .mem_mask_o(move_write_mask_w),
        .mem_rsp_valid_i(mem_response_valid_w[1] && stream_writer_w && state_r != FLUSH_RETURN),
        .mem_rsp_error_i(mem_rsp_error_i)
    );
    op_feature_reader u_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .clear_i(state_r == RESET_CORE || (writer_mem_w && writer_mem_ready_w)),
        .req_valid_i(reader_req_w && !pw_reader_w), .req_ready_o(legacy_ready_w), .req_mode_i(reader_mode_w),
        .req_addr_i(reader_addr_w), .req_pixel_i(reader_pixel_w),
        .slices_i(d_r[351:320]), .center_i(d_r[383:352]),
        .rsp_valid_o(legacy_rsp_w), .rsp_ready_i(reader_rsp_ready_w && !pw_reader_w),
        .rsp_data_o(legacy_data_w), .rsp_error_o(legacy_error_w),
        .mem_valid_o(legacy_mem_w), .mem_ready_i(reader_mem_ready_w && !pw_reader_w), .mem_addr_o(legacy_mem_addr_w),
        .mem_rsp_valid_i(mem_response_valid_w[0] && !move_w && !dw_stream_w && !pw_reader_w), .mem_rsp_ready_o(legacy_mem_rsp_ready_w),
        .mem_rsp_data_i(mem_rsp_data_i), .mem_rsp_error_i(mem_rsp_error_i)
    );
    op_pw_reader u_pw_reader (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .clear_i(state_r == RESET_CORE),
        .req_valid_i(reader_req_w && pw_reader_w), .req_ready_o(pw_reader_ready_w),
        .req_addr_i(reader_addr_w + reader_pixel_w[30:0]), .req_source_i(bank_rd_source_w),
        .rsp_valid_o(pw_reader_rsp_w), .rsp_ready_i(reader_rsp_ready_w && pw_reader_w),
        .rsp_data_o(pw_reader_data_w), .rsp_source_o(pw_reader_source_w),
        .error_o(pw_reader_error_w), .idle_o(pw_reader_idle_w),
        .mem_valid_o(pw_reader_mem_w), .mem_ready_i(reader_mem_ready_w && pw_reader_w),
        .mem_addr_o(pw_reader_addr_w),
        .mem_rsp_valid_i(mem_response_valid_w[0] && pw_reader_w),
        .mem_rsp_ready_o(pw_reader_mem_rsp_ready_w), .mem_rsp_data_i(mem_rsp_data_i),
        .mem_rsp_error_i(mem_rsp_error_i)
    );
    op_feature_writer #(.ENABLE_WIDE_DEBUG(ENABLE_WIDE_DEBUG)) u_writer (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .req_valid_i(writer_req_w), .req_ready_o(writer_ready_w),
        .clear_i(state_r == RESET_CORE), .idle_o(writer_idle_w),
        .req_addr_i(writer_addr_w), .req_data_i(writer_data_w), .req_bytes_i(writer_bytes_w),
        .done_o(writer_done_w), .error_o(writer_error_w),
        .mem_valid_o(writer_mem_w), .mem_ready_i(writer_mem_ready_w), .mem_addr_o(writer_mem_addr_w),
        .mem_data_o(writer_mem_data_w), .mem_mask_o(writer_mem_mask_w),
        .mem_rsp_valid_i(mem_response_valid_w[1] && !stream_writer_w && state_r != FLUSH_RETURN), .mem_rsp_ready_o(writer_mem_rsp_ready_w),
        .mem_rsp_error_i(mem_rsp_error_i)
    );
    // 零掩码写是DDR排空屏障，不产生字节写入；完成状态必须晚于最终B响应。
    op_mem_arbiter u_mem_queue (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i({state_r == FLUSH_REQUEST || (stream_writer_w ? move_write_mem_w : writer_mem_w),(move_w || dw_stream_w) ? move_read_mem_w : reader_mem_w}),
        .req_ready_o(mem_source_ready_w), .req_write_i(2'b10),
        .req_addr_i({state_r == FLUSH_REQUEST ? 31'd0 : (stream_writer_w ? move_write_addr_w : writer_mem_addr_w),(move_w || dw_stream_w) ? move_read_addr_w : reader_mem_addr_w}),
        .req_data_i({stream_writer_w ? move_write_data_w : writer_mem_data_w,256'd0}),
        .req_mask_i({state_r == FLUSH_REQUEST ? 32'd0 : (stream_writer_w ? move_write_mask_w : writer_mem_mask_w),
                     pw_reader_w ? 32'd1 : 32'd0}),
        .rsp_valid_o(mem_response_valid_w),
        .rsp_ready_i({state_r == FLUSH_RETURN || (stream_writer_w ? 1'b1 : writer_mem_rsp_ready_w),(move_w || dw_stream_w) ? move_read_rsp_ready_w : reader_mem_rsp_ready_w}),
        .pending_o(pending_r), .mem_valid_o(mem_valid_o), .mem_ready_i(mem_ready_i),
        .mem_write_o(mem_write_o), .mem_addr_o(mem_addr_o), .mem_data_o(mem_data_o), .mem_mask_o(mem_mask_o),
        .mem_rsp_valid_i(mem_rsp_valid_i), .mem_rsp_ready_o(mem_rsp_ready_o)
    );
    assign writer_mem_ready_w = mem_source_ready_w[1] && state_r != FLUSH_REQUEST;
    assign reader_mem_ready_w = mem_source_ready_w[0];

    always_comb begin
        reader_req_w = 1'b0; reader_mode_w = 2'd0;
        reader_addr_w = base_a_w[30:0]; reader_pixel_w = 32'd0;
        reader_rsp_ready_w = 1'b0;
        bank_rd_ready_w = 1'b0; bank_in_valid_w = 1'b0; bank_b_valid_w = 1'b0;
        bank_in_data_w = reader_data_w;
        case (state_r)
            LOAD_WEIGHTS: begin
                reader_req_w = 1'b1; reader_mode_w = 2'd1;
                reader_addr_w = weight_base_w[30:0]; reader_pixel_w = {1'b0,load_count_r[24:0],6'd0};
                if (op_w == 8'd8 || op_w == 8'd9) begin
                    reader_mode_w = 2'd0;
                    reader_pixel_w = {1'b0,load_count_r[26:0],4'd0};
                end else if (op_w == 8'd11) begin
                    // 融合算子先装每组DW3的9个16B拍，再装DW5的25个16B拍。
                    reader_mode_w = 2'd0;
                    reader_pixel_w = {1'b0,load_count_r[26:0],4'd0};
                    if (load_count_r >= {22'd0,dw3_weight_words_r})
                        reader_addr_w = weight_b_base_r;
                end else if (op_w == 8'd12) begin
                    if (load_count_r < p12_weight_a_words_w)
                        reader_addr_w = weight_base_w[30:0];
                    else
                        reader_addr_w = weight_b_base_r;
                end
                reader_rsp_ready_w = weights_ready_w;
            end
            LOAD_PARAMS: begin
                if (op_w != 8'd12) begin
                    reader_req_w = 1'b1; reader_mode_w = 2'd1;
                    reader_addr_w = param_base_w[30:0]; reader_pixel_w = {1'b0,load_count_r[24:0],6'd0};
                    reader_rsp_ready_w = params_ready_w;
                end
            end
            LOAD_ADD: begin
                if (!add_cache_hit_w) begin
                    reader_req_w = 1'b1; reader_mode_w = 2'd1;
                    reader_addr_w = add_param_base_r; reader_pixel_w = {1'b0,load_count_r[24:0],6'd0};
                    reader_rsp_ready_w = 1'b1;
                end
            end
            RUN: case (op_w)
                8'd2, 8'd10, 8'd11, 8'd13: begin
                    bank_in_data_w = {384'd0,move_data_w};
                    bank_in_valid_w = move_valid_w && !(op_w == 8'd13 && fuse_skip_r);
                end
                8'd5: ; // Concat直接消费两段连续读流，保持原A→B布局。
                8'd1: begin
                    reader_req_w = bank_rd_valid_w && !run_drained_r;
                    bank_rd_ready_w = reader_ready_w && !run_drained_r;
                    reader_rsp_ready_w = bank_rsp_ready_w;
                    if (online_w) begin reader_mode_w = 2'd2; reader_pixel_w = bank_rd_addr_w; end
                    else begin
                        reader_addr_w = bank_rd_source_w ? base_b_w[30:0] : base_a_w[30:0];
                        reader_pixel_w = {1'b0,bank_rd_addr_w[26:0],4'd0};
                    end
                end
                8'd6: begin
                    reader_mode_w = 2'd1;
                    reader_req_w = input_count_r < pixels_w;
                    reader_addr_w = add_a_valid_r ? run_b_base_r : run_a_base_r;
                    reader_pixel_w = {1'b0,input_count_r[24:0],6'd0};
                    reader_rsp_ready_w = add_a_valid_r ? bank_b_ready_w : 1'b1;
                    bank_in_data_w = add_a_r;
                    bank_in_valid_w = add_a_valid_r;
                    bank_b_valid_w = add_a_valid_r && reader_rsp_w;
                end
                8'd12: begin
                    // 排空登记后的交接拍冻结新预取；valid/ready须同时门控，
                    // 保证reader与PW对请求握手的判断一致，待下一组RUN再继续。
                    reader_req_w = bank_rd_valid_w && !run_drained_r;
                    bank_rd_ready_w = reader_ready_w && !run_drained_r;
                    reader_rsp_ready_w = bank_rsp_ready_w;
                    reader_addr_w = bank_rd_source_w ? base_b_w[30:0] : base_a_w[30:0];
                    reader_pixel_w = {1'b0,bank_rd_addr_w[26:0],4'd0};
                end
                default: begin
                    // 融合 DW3/DW5 每个组只消费一遍输入；input_count_r 是当前组
                    // 的局部像素计数，group_pixel_base_r 是输入中的绝对像素基址。
                    // 其它默认算子仍使用连续的全局输入计数。
                    if (op_w == 8'd11) begin
                        reader_req_w = input_count_r < pixels_w;
                        reader_addr_w = run_a_base_r;
                    end else begin
                        reader_req_w = input_count_r < total_inputs_w;
                        reader_addr_w = base_a_w[30:0];
                    end
                    reader_pixel_w = {1'b0,input_count_r[26:0],4'd0};
                    reader_rsp_ready_w = bank_in_ready_w;
                    bank_in_valid_w = reader_rsp_w;
                end
            endcase
            default: ;
        endcase
        in_fire_w = state_r == RUN && reader_rsp_w && reader_rsp_ready_w && op_w != 8'd12;
        if (state_r == RUN && (move_w || dw_stream_w)) in_fire_w = move_valid_w && move_ready_w;
    end

    // 装载只看本阶段的接收端，避免RUN的多级ready选择串入装载计数和参数CE。
    always_comb begin
        load_fire_w = 1'b0;
        load_last_w = 1'b0;
        case (state_r)
            LOAD_WEIGHTS: begin
                load_fire_w = reader_rsp_w && weights_ready_w;
                load_last_w = load_count_r + 32'd1 == weight_words_w;
            end
            LOAD_PARAMS: begin
                load_fire_w = bank_params_valid_w && params_ready_w;
                load_last_w = load_count_r + 32'd1 == param_words_w;
            end
            LOAD_ADD: begin
                load_fire_w = add_cache_hit_w ? add_cache_data_valid_r[1] : reader_rsp_w;
                load_last_w = load_count_r == 32'd3;
            end
            default: ;
        endcase
    end

    always_comb begin
        writer_req_w = 1'b0; writer_addr_w = 31'd0; writer_data_w = WRITER_BITS'(saved_data_r); writer_bytes_w = 9'd16;
        case (output_r)
            O_Q_REQUEST: begin
                writer_req_w = 1'b1;
                writer_addr_w = saved_linear_addr_r[30:0];
                case (op_w)
                    8'd1: begin
                        writer_data_w = '0;
                        if (int16_w) begin
                            writer_bytes_w = 9'd8; writer_data_w[63:0] = saved_data_r[63:0];
                            writer_addr_w = saved_q_addr_r;
                        end else begin
                            writer_bytes_w = 9'd4;
                            for (int p=0; p<4; p++) writer_data_w[p*8 +: 8] = saved_data_r[p*16 +: 8];
                            writer_addr_w = saved_q_addr_r;
                        end
                    end
                    8'd3: if (ENABLE_WIDE_DEBUG) writer_bytes_w = 9'd144;
                    8'd4: if (ENABLE_WIDE_DEBUG) writer_bytes_w = 9'd400;
                    8'd8, 8'd9: begin
                        // DW adapter 不提供可靠的 pixel/group 标签；引擎的
                        // output_addr_r 已按输出握手维护连续的 [group][pixel] 地址。
                        if (ENABLE_WIDE_DEBUG) writer_bytes_w = 9'd64;
                        writer_addr_w = saved_linear_addr_r[30:0];
                    end
                    8'd11: begin
                        // 融合 DW3/DW5+Add 同样按每个 P16 结果连续写回。
                        writer_bytes_w = 9'd16;
                        writer_addr_w = saved_linear_addr_r[30:0];
                    end
                    8'd12: begin
                        writer_data_w = '0;
                        writer_data_w[127:0] = saved_data_r[127:0];
                        writer_bytes_w = 9'd16;
                        writer_addr_w = saved_q_addr_r;
                    end
                    default: ;
                endcase
            end
            O_MAC_REQUEST: begin
                writer_req_w = 1'b1; writer_data_w = WRITER_BITS'(saved_mac_r); writer_bytes_w = 9'd16;
                writer_addr_w = saved_mac_addr_r;
            end
            default: ;
        endcase
        if (state_r == CLEAR) begin
            writer_req_w = !clear_wait_r; writer_addr_w = clear_addr_r[30:0];
            writer_data_w = '0; writer_bytes_w = 9'd32;
            if (out_base_w+result_bytes_o-clear_addr_r < 32'd32)
                writer_bytes_w = 9'(out_base_w+result_bytes_o-clear_addr_r);
        end
        output_nxt = output_r;
        case (output_r)
            O_IDLE: if (output_fire_w && !stream_writer_w) output_nxt = (op_w == 8'd1 || op_w == 8'd12) ? O_INDEX : O_Q_REQUEST;
            O_INDEX: output_nxt = O_PIXEL;
            O_PIXEL: output_nxt = O_ADDRESS;
            O_ADDRESS: output_nxt = raw_w ? O_MAC_REQUEST : O_Q_REQUEST;
            O_Q_REQUEST: if (writer_ready_w) output_nxt = O_Q_WAIT;
            O_Q_WAIT: if (writer_done_w) output_nxt = op_w == 8'd1 && debug_w ? O_MAC_REQUEST : O_IDLE;
            O_MAC_REQUEST: if (writer_ready_w) output_nxt = O_MAC_WAIT;
            O_MAC_WAIT: if (writer_done_w) output_nxt = O_IDLE;
            default: output_nxt = O_IDLE;
        endcase
        if (stream_writer_w) output_nxt = O_IDLE;
    end
    assign bank_out_ready_w = state_r == RUN &&
        (pw_pack_w ? pw_pack_ready_w : stream_writer_w ? move_write_ready_w : output_r == O_IDLE && writer_ready_w);
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
            // 生产公共结果固定128位；宽导出寄存器仅在调试构建中生成。
            saved_data_r[127:0] <= bank_data_w[127:0];
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
        // Add装载无反压，宽参数寄存器不能复用含PW参数ready的通用装载事件。
        if (add_load_valid_r)
            add_params_r[add_load_index_r*512 +: 512] <= add_load_data_r;
        // Add的A拍无反压，不能让B端ready经通用in_fire回到512位A寄存器的CE。
        if (state_r == RUN && op_w == 8'd6 && reader_rsp_w && !add_a_valid_r) add_a_r <= reader_data_w;
        if (run_valid_i && run_ready_o) begin
            d_r <= descriptor_i;
            // 同描述符拍完成op13映射，去掉RUN中全局opcode比较到RAM/DSP的长链。
            core_op_r <= descriptor_i[7:0] == 8'd13 ? 4'd10 : descriptor_i[3:0];
            pixels_r <= checked_pixels_w; total_inputs_r <= checked_inputs_w;
            weight_words_r <= checked_weights_w; param_words_r <= checked_params_w;
            words_b_r <= checked_words_b_w;
        end
    end
    // 数据无使能连续打拍；只有本地有效位驱动宽参数寄存器的 CE。
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) add_load_valid_r <= 1'b0;
        else add_load_valid_r <= state_r == LOAD_ADD &&
            (add_cache_hit_w ? add_cache_data_valid_r[1] : reader_rsp_w);
    end
    always_ff @(posedge clk_i) begin
        add_load_index_r <= load_count_r[1:0];
        add_load_data_r <= add_load_data_w;
    end
    generate
        if (ENABLE_WIDE_DEBUG) begin : g_wide_debug
            always_ff @(posedge clk_i) begin
                if (output_fire_w) begin
                    case (op_w)
                        8'd3: saved_data_r[1151:128] <= bank_data_w[1151:128];
                        8'd4: saved_data_r[3199:128] <= bank_data_w[3199:128];
                        8'd8, 8'd9: saved_data_r[511:128] <= bank_data_w[511:128];
                        default: ;
                    endcase
                end
            end
        end
    endgenerate
    // 顺序流结果统一采用已保存的输出序号。
    always_comb begin
        // reader_ready_w 只表示 reader 当前处于 IDLE；在同一拍发出最后一笔
        // bank 读请求时它仍可能为 1。必须等请求/返回通道都空闲后再离开 RUN，
        // 否则最后一笔响应会被 LOAD_ADD 状态的门控丢弃，PW 永远停在 FILL。
        // writer_idle_w还包括已入FIFO但尚未返回的写，不能用接收就绪代替排空。
        drained_w = output_r == O_IDLE && output_queued_r == 2'd0 && writer_idle_w &&
                    (pw_reader_w ? pw_reader_idle_w : reader_ready_w) &&
                    !reader_req_w && !reader_rsp_w && !reader_mem_w && !pending_r;
        if (dw_stream_w) drained_w = core_done_r && output_r == O_IDLE && writer_idle_w &&
            move_read_idle_w && move_write_idle_w && !pending_r;
        else if (move_w) drained_w = drained_w && move_read_idle_w && move_write_idle_w;
        else if (stream_writer_w) drained_w = drained_w && move_write_idle_w && (!pw_pack_w || pw_pack_idle_w);
        run_ready_o = state_r == IDLE && descriptor_ok_o;
        busy_o = state_r != IDLE; done_o = state_r == FINISH;
        error_o = error_r; aborted_o = aborted_r;
        cfg_valid_w = state_r == CONFIGURE && !cfg_accepted_r;
        state_nxt = state_r;
        case (state_r)
            IDLE: if (run_valid_i && run_ready_o) state_nxt = RESET_CORE;
            RESET_CORE: begin
                if (op_w == 8'd6) state_nxt = LOAD_ADD;
                else if (op_w == 8'd1 && !pw_pack_w && !raw_w && !int16_w && cout_w[3:0] != 4'd0) state_nxt = CLEAR;
                else state_nxt = CONFIGURE;
            end
            CLEAR: if (writer_done_w && clear_addr_r+32'd32 >= out_base_w+result_bytes_o) state_nxt = CONFIGURE;
            CONFIGURE: if (cfg_accepted_r) begin
                if (op_w == 8'd11 && add_loaded_r) state_nxt = RUN;
                else if (op_w == 8'd12 && !p12_pw_loaded_r) state_nxt = LOAD_WEIGHTS;
                else if (op_w == 8'd12 && !p12_pw_started_r) state_nxt = START;
                else if (op_w == 8'd1 || op_w == 8'd8 || op_w == 8'd9 || op_w == 8'd11)
                    state_nxt = LOAD_WEIGHTS;
                else state_nxt = RUN;
            end
            LOAD_WEIGHTS: if (load_fire_w && load_last_w)
                state_nxt = (op_w == 8'd1 || op_w == 8'd12) ? LOAD_PARAMS :
                            (op_w == 8'd11 ? LOAD_ADD : RUN);
            LOAD_PARAMS: if (load_fire_w && load_last_w)
                state_nxt = op_w == 8'd12 ? LOAD_ADD : START;
            LOAD_ADD: if (load_fire_w && load_last_w) state_nxt = ADD_COMMIT;
            ADD_COMMIT: state_nxt = CONFIGURE;
            START: if (start_ready_w) state_nxt = RUN;
            RUN: if (run_drained_r) begin
                if (advance_group_w) state_nxt = LOAD_ADD;
                else state_nxt = FLUSH_REQUEST;
            end
            // 仲裁器已独立保存屏障；按本地握手推进，禁止等待下游期间重复入队。
            FLUSH_REQUEST: if (mem_source_ready_w[1]) state_nxt = FLUSH_RETURN;
            FLUSH_RETURN: if (mem_response_valid_w[1]) state_nxt = FINISH;
            FINISH: state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= IDLE; input_count_r <= 32'd0; load_count_r <= 32'd0;
            run_drained_r <= 1'b0;
            move_mode_r <= 1'b0; pw_pack_mode_r <= 1'b0; stream_writer_mode_r <= 1'b0;
            pw_reader_mode_r <= 1'b0;
            group_r <= 6'd0; core_done_r <= 1'b0; add_a_valid_r <= 1'b0; add_loaded_r <= 1'b0;
            p12_pw_loaded_r <= 1'b0; p12_pw_started_r <= 1'b0; tile_base_r <= 19'd0;
            tile_remaining_r <= 19'd0; tile_words_r <= 5'd0; tile_last_r <= 1'b0;
            stream_writer_started_r <= 1'b0;
            reader_source_r <= 1'b0;
            error_r <= 1'b0; aborted_r <= 1'b0; clear_wait_r <= 1'b0;
            clear_addr_r <= 32'd0; result_bytes_o <= 32'd0; mac_bytes_o <= 32'd0;
        end else begin
            state_r <= state_nxt;
            // 所有请求、响应和写回均排空后再寄存完成，下一拍才驱动组/tile更新。
            run_drained_r <= state_r == RUN && core_done_r && drained_w;
            if (run_valid_i && run_ready_o) begin
                // 与描述符同拍预解码，避免opcode多级选择贯穿ready及FIFO接口。
                move_mode_r <= descriptor_i[7:0] == 8'd2 || descriptor_i[7:0] == 8'd5 || descriptor_i[7:0] == 8'd10 || descriptor_i[7:0] == 8'd13;
                pw_pack_mode_r <= descriptor_i[7:0] == 8'd1 && !descriptor_i[10] && !descriptor_i[9];
                // 读响应选择也预解码，隔离opcode高位到reader错误/ready的路径。
                pw_reader_mode_r <= (descriptor_i[7:0] == 8'd1 && !descriptor_i[8]) ||
                                    descriptor_i[7:0] == 8'd12;
                case (descriptor_i[7:0])
                    8'd2, 8'd5, 8'd10, 8'd11, 8'd12, 8'd13: stream_writer_mode_r <= 1'b1;
                    8'd1: stream_writer_mode_r <= !descriptor_i[10] && !descriptor_i[9];
                    default: stream_writer_mode_r <= 1'b0;
                endcase
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
                    if (add_load_data_w[p*128 +: 32] != {{10{add_load_data_w[p*128+21]}},add_load_data_w[p*128 +: 22]} ||
                        add_load_data_w[p*128+32 +: 32] != {{10{add_load_data_w[p*128+53]}},add_load_data_w[p*128+32 +: 22]}) error_r <= 1'b1;
            if (writer_error_w && busy_o && state_r != RESET_CORE) error_r <= 1'b1;
            if (stream_writer_w && busy_o && (move_write_error_w || ((move_w || dw_stream_w) && move_read_error_w))) error_r <= 1'b1;
            if (state_r == FLUSH_RETURN && mem_rsp_valid_i && mem_rsp_error_i) error_r <= 1'b1;
            if (state_r == RESET_CORE) begin
                group_r <= 6'd0; input_count_r <= 32'd0;
                core_done_r <= 1'b0; add_a_valid_r <= 1'b0; add_loaded_r <= 1'b0; clear_addr_r <= out_base_w;
                p12_pw_loaded_r <= 1'b0; p12_pw_started_r <= 1'b0; tile_base_r <= 19'd0;
                tile_remaining_r <= pixels_r[18:0];
                tile_words_r <= pixels_r > 32'd16 ? 5'd16 : 5'(pixels_r);
                tile_last_r <= pixels_r <= 32'd16;
                stream_writer_started_r <= 1'b0;
                reader_source_r <= 1'b0;
                clear_wait_r <= 1'b0;
            end
            else if (stream_writer_start_w) stream_writer_started_r <= 1'b1;
            if (state_r == RUN && op_w == 8'd12 && bank_rd_valid_w && bank_rd_ready_w)
                reader_source_r <= bank_rd_source_w;
            if (state_r == CONFIGURE && cfg_accepted_r && op_w == 8'd12 && !p12_pw_loaded_r)
                p12_pw_loaded_r <= 1'b1;
            if (state_r == START && start_ready_w && op_w == 8'd12)
                p12_pw_started_r <= 1'b1;
            if (state_r == CLEAR) begin
                if (writer_req_w && writer_ready_w) clear_wait_r <= 1'b1;
                if (writer_done_w) begin clear_wait_r <= 1'b0; clear_addr_r <= clear_addr_r+32'd32; end
            end
            // 非装载阶段直接清零；不再把所有状态的迁移条件接入32位计数器CE。
            case (state_r)
                LOAD_WEIGHTS, LOAD_PARAMS, LOAD_ADD:
                    if (load_fire_w) load_count_r <= load_last_w ? 32'd0 : load_count_r + 32'd1;
                default: load_count_r <= 32'd0;
            endcase
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
                if (advance_group_w) begin
                    core_done_r <= 1'b0;
                    if (op_w == 8'd12) begin
                        if (!group_last_r) group_r <= group_r+6'd1;
                        else begin
                            group_r <= 6'd0;
                            tile_base_r <= next_tile_base_r;
                            tile_remaining_r <= next_tile_remaining_r;
                            tile_words_r <= next_tile_words_r;
                            tile_last_r <= next_tile_last_r;
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
        // 组号在装载/配置期间稳定，提前比较边界，避免groups解码直达tile控制CE。
        group_last_r <= group_r == groups_w - 6'd1;
        // 复用CONFIGURE拍预加组偏移，RUN请求只保留一次基址加法。
        if (state_r == CONFIGURE) begin
            run_a_base_r <= base_a_w[30:0] + (op_w == 8'd6 ? (group_pixel_base_r[24:0]<<6) : (group_pixel_base_r[26:0]<<4));
            run_b_base_r <= base_b_w[30:0] + (group_pixel_base_r[24:0]<<6);
        end
        if (state_r == RESET_CORE) add_param_base_r <= param_base_w[30:0];
        else if (advance_group_w)
            add_param_base_r <= op_w == 8'd12 && group_last_r ? param_base_w[30:0] : add_param_base_r + 31'd256;
        // 复用既有RESET_CORE/CONFIGURE两拍预计算project权重边界。
        // 避免描述符通道选择→取整→乘法→地址/reader握手→load计数同拍贯穿。
        if (state_r == RESET_CORE) begin
            p12_output_groups_r <= 9'(({1'b0,cout_w} + 11'd3) >> 2);
            p12_input_groups_r <= 7'(({1'b0,cin_w} + 11'd15) >> 4);
            dw3_weight_words_r <= {4'd0,groups_w} * 10'd9;
        end
        if (state_r == CONFIGURE)
            p12_weight_a_words_r <= p12_output_groups_r * p12_input_groups_r;
        // 第二段地址预减第一段长度，请求拍只做一次加法。
        // 合法op11/op12的第一段非空；其首笔响应前偏置已锁存，故不增加等待拍。
        if (state_r == LOAD_WEIGHTS)
            weight_b_base_r <= mac_base_w[30:0] - (op_w == 8'd11 ?
                {17'd0,dw3_weight_words_r,4'd0} : {9'd0,p12_weight_a_words_r,6'd0});
        if (state_r == RESET_CORE) group_pixel_base_r <= 32'd0;
        else if (advance_group_w &&
                 (op_w == 8'd6 || op_w == 8'd11 || op_w == 8'd12)) begin
            if (op_w == 8'd12 && group_last_r) group_pixel_base_r <= 32'd0;
            else group_pixel_base_r <= group_pixel_base_r + pixels_r;
        end
        if (state_r == RESET_CORE) stream_address_r <= out_base_w[30:0];
        else if (state_r == CONFIGURE && op_w == 8'd12)
            stream_address_r <= out_base_w[30:0] + ((group_pixel_base_r[30:0]+{12'd0,tile_base_r})<<4);
        else if (stream_writer_w && stream_valid_w && move_write_ready_w)
            stream_address_r <= stream_address_r+31'd16;
    end
    logic [63:0] perf_r [0:15];
    // op11每组均需排空；奇数像素组的末半字必须冲刷，不能等待下一组补齐。
    always_ff @(posedge clk_i) begin
        if (state_r == RESET_CORE) begin
            stream_group_pixel_r <= 19'd0;
            stream_group_last_pixel_r <= pixels_r[18:0]-19'd1;
        end else if (op_w == 8'd11 && output_fire_w)
            stream_group_pixel_r <= stream_last_w ? 19'd0 : stream_group_pixel_r+19'd1;
    end
    // 当前tile运行期间预计算下一tile；减法、边界比较分拍，不串入状态CE。
    always_ff @(posedge clk_i) begin
        next_tile_base_r <= tile_base_r + {14'd0,tile_words_r};
        next_tile_remaining_r <= tile_remaining_r - {14'd0,tile_words_r};
        next_tile_words_r <= next_tile_remaining_r > 19'd16 ? 5'd16 : next_tile_remaining_r[4:0];
        next_tile_last_r <= next_tile_remaining_r <= 19'd16;
    end
    logic [255:0] perf_ddr_r;
    logic [15:0] perf_event_w, perf_event_r;
    always_comb begin
        perf_event_w = 16'd0;
        perf_event_w[0] = busy_o && state_r != FINISH;
        perf_event_w[1] = state_r == LOAD_WEIGHTS || state_r == LOAD_PARAMS || state_r == LOAD_ADD;
        perf_event_w[2] = state_r == RUN;
        perf_event_w[3] = state_r == RUN && ((move_w || dw_stream_w) ? move_valid_w && move_ready_w : reader_rsp_w && reader_rsp_ready_w);
        perf_event_w[4] = output_fire_w;
        perf_event_w[5] = reader_req_w && !reader_ready_w;
        perf_event_w[6] = ((move_w || dw_stream_w) ? move_read_mem_w : reader_mem_w) && !reader_mem_ready_w;
        perf_event_w[7] = bank_out_valid_w && !bank_out_ready_w;
        perf_event_w[8] = mem_valid_o && mem_ready_i && !mem_write_o;
        perf_event_w[9] = mem_valid_o && mem_ready_i && mem_write_o && mem_mask_o != 32'd0;
        perf_event_w[10] = mem_valid_o && !mem_ready_i;
        perf_event_w[11] = pending_r;
        perf_event_w[12] = (move_w || dw_stream_w) ? mem_response_valid_w[0] && move_read_rsp_ready_w && mem_rsp_error_i :
                                   reader_rsp_w && reader_rsp_ready_w && reader_error_w;
        // PW先经过P4/P16打包；writer阻塞应采样其真实输入，不能采样上游P4有效位。
        perf_event_w[13] = stream_writer_w ? state_r == RUN && stream_valid_w && !move_write_ready_w :
                                   writer_req_w && !writer_ready_w;
        perf_event_w[14] = state_r == FLUSH_REQUEST || state_r == FLUSH_RETURN;
        perf_event_w[15] = state_r == RUN && ((move_w || dw_stream_w) ? !move_read_idle_w && !move_valid_w :
                                                                    !reader_ready_w && !reader_rsp_w);
        for (int p=0; p<16; p++) perf_data_o[p*64 +: 64] = perf_r[p];
        perf_data_o[1279:1024] = perf_ddr_r;
    end
    always_ff @(posedge clk_i) begin
        if (!rst_n_i || (run_valid_i && run_ready_o)) begin
            for (int p=0; p<16; p++) perf_r[p] <= 64'd0;
            perf_event_r <= 16'd0;
            perf_ddr_r <= 256'd0;
        end else begin
            // 先寄存单比特事件，切断reader地址/错误组合链到64位计数器CE的旁路。
            // FINISH拍收齐最后一个事件；service先写记录头，随后才读取这些计数。
            perf_event_r <= (busy_o && state_r != FINISH) ? perf_event_w : 16'd0;
            for (int p=0; p<16; p++)
                if (perf_event_r[p]) perf_r[p] <= perf_r[p]+64'd1;
            if (state_r == FLUSH_RETURN && mem_response_valid_w[1]) perf_ddr_r <= mem_rsp_data_i;
        end
    end
endmodule
