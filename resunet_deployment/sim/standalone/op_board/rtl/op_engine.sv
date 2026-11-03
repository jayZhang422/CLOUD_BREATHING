`timescale 1ns/1ps
// 【文件类型：.sv】上板准备候选调度，基于现有调度器扩宽通道/组标签。
// 权重/参数事务由外部 op_coeff_split 接到只读源；本文件不例化 ROM IP。
// 描述符 byte52/54 为可选 LE16 Cin/Cout；为零时兼容 byte2/3。
// 原始 BIN 保留 ZYX；PW 的 INT8 输出按 group16/pixel/lane 落址。
module op_engine (
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic run_valid_i, // 握手有效，阻塞期间保持载荷
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
        LOAD_WEIGHTS, LOAD_PARAMS, LOAD_ADD, START, RUN, FINISH} state_t;
    state_t state_r, state_nxt;
    typedef enum logic [2:0] {O_IDLE, O_Q_REQUEST, O_Q_WAIT, O_MAC_REQUEST, O_MAC_WAIT} output_state_t;
    output_state_t output_r, output_nxt;
    logic [511:0] d_r;
    logic [7:0] op_w;
    logic [9:0] cin_w, cout_w;
    logic [15:0] candidate_cin_w, candidate_cout_w;
    logic [9:0] width_w, height_w;
    logic [5:0] groups_w, group_r;
    logic [31:0] pixels_w, input_count_r, output_count_r, load_count_r, clear_addr_r;
    logic [31:0] saved_output_count_r;
    logic [31:0] weight_words_w, param_words_w, total_inputs_w;
    logic [31:0] base_a_w, base_b_w, out_base_w, mac_base_w, weight_base_w, param_base_w;
    logic online_w, debug_w, raw_w, int16_w, core_done_r, error_r, aborted_r;
    logic [2047:0] add_params_r;
    logic add_a_valid_r;
    logic [511:0] add_a_r;
    logic cfg_valid_w, cfg_ready_w, weights_ready_w, params_ready_w, start_ready_w;
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
    assign cout_w = d_r[447:432] == 16'd0 ? {2'd0,d_r[31:24]} : d_r[441:432];
    assign candidate_cin_w = descriptor_i[431:416] == 16'd0 ? {8'd0,descriptor_i[23:16]} : descriptor_i[431:416];
    assign candidate_cout_w = descriptor_i[447:432] == 16'd0 ? {8'd0,descriptor_i[31:24]} : descriptor_i[447:432];
    assign width_w = d_r[41:32]; assign height_w = d_r[57:48];
    assign groups_w = d_r[69:64];
    assign pixels_w = {22'd0,width_w} * {22'd0,height_w};
    assign base_a_w = d_r[159:128]; assign base_b_w = d_r[191:160];
    assign out_base_w = d_r[223:192]; assign mac_base_w = d_r[255:224];
    assign weight_base_w = d_r[287:256]; assign param_base_w = d_r[319:288];
    assign weight_words_w = (({22'd0,cout_w}+32'd3)>>2) * (({22'd0,cin_w}+32'd15)>>4);
    assign param_words_w = ({22'd0,cout_w}+32'd3)>>2;
    assign total_inputs_w = pixels_w * {26'd0,groups_w};

    // 边界使用 64bit，禁止 32bit 地址溢出后误判合法。
    logic [63:0] p_w, a_bytes_w, b_bytes_w, q_bytes_w, m_bytes_w, weights_bytes_w, params_bytes_w;
    logic [63:0] a_w, b_w, q_w, m_w, w_w, par_w;
    function automatic logic fits(input logic [63:0] a, input logic [63:0] n);
        fits = n != 64'd0 && a + n <= 64'h20000000;
    endfunction
    function automatic logic overlap(input logic [63:0] a, input logic [63:0] n,
        input logic [63:0] b, input logic [63:0] m);
        overlap = n != 64'd0 && m != 64'd0 && a < b+m && b < a+n;
    endfunction
    always_comb begin
        p_w = {48'd0,descriptor_i[47:32]} * {48'd0,descriptor_i[63:48]};
        a_w = {32'd0,descriptor_i[159:128]}; b_w = {32'd0,descriptor_i[191:160]};
        q_w = {32'd0,descriptor_i[223:192]}; m_w = {32'd0,descriptor_i[255:224]};
        w_w = {32'd0,descriptor_i[287:256]}; par_w = {32'd0,descriptor_i[319:288]};
        a_bytes_w = p_w * {48'd0,descriptor_i[79:64]} * 64'd16;
        b_bytes_w = 64'd0; q_bytes_w = a_bytes_w; m_bytes_w = 64'd0;
        weights_bytes_w = 64'd0; params_bytes_w = 64'd0;
        descriptor_ok_o = descriptor_i[7:0] >= 8'd1 && descriptor_i[7:0] <= 8'd7 &&
            descriptor_i[47:32] >= 16'd1 && descriptor_i[47:32] <= 16'd512 &&
            descriptor_i[63:48] >= 16'd1 && descriptor_i[63:48] <= 16'd512 &&
            descriptor_i[79:64] >= 16'd1 && descriptor_i[79:64] <= 16'd32 &&
            a_w[3:0] == 4'd0 && q_w[4:0] == 5'd0 && descriptor_i[15:12] == 4'd0;
        case (descriptor_i[7:0])
            8'd1: begin
                descriptor_ok_o = descriptor_ok_o && candidate_cin_w >= 16'd1 &&
                    candidate_cin_w <= 16'd768 && candidate_cout_w >= 16'd1 &&
                    candidate_cout_w <= 16'd512 && descriptor_i[87:80] <= 8'd62 &&
                    !(descriptor_i[10] && descriptor_i[11]) && w_w[5:0] == 6'd0 && par_w[5:0] == 6'd0;
                a_bytes_w = p_w * (({48'd0,candidate_cin_w}+64'd15)>>4) * 64'd16;
                q_bytes_w = p_w * (({48'd0,candidate_cout_w}+64'd15)>>4) * 64'd16;
                if (descriptor_i[11]) q_bytes_w = p_w * (({48'd0,candidate_cout_w}+64'd3)>>2) * 64'd8;
                if (descriptor_i[10]) q_bytes_w = p_w * (({48'd0,candidate_cout_w}+64'd3)>>2) * 64'd16;
                if (descriptor_i[9] && !descriptor_i[10]) m_bytes_w = p_w * (({48'd0,candidate_cout_w}+64'd3)>>2) * 64'd16;
                weights_bytes_w = (({48'd0,candidate_cout_w}+64'd3)>>2) *
                    (({48'd0,candidate_cin_w}+64'd15)>>4) * 64'd64;
                params_bytes_w = (({48'd0,candidate_cout_w}+64'd3)>>2) * 64'd64;
                if (descriptor_i[8]) begin
                    a_bytes_w = {32'd0,descriptor_i[351:320]} * 64'd262144;
                    descriptor_ok_o = descriptor_ok_o && candidate_cin_w == 16'd3 &&
                        candidate_cout_w == 16'd16 && p_w == 64'd262144 && a_w[17:0] == 18'd0 &&
                        descriptor_i[351:320] >= 32'd1 && descriptor_i[351:320] <= 32'd1024 &&
                        descriptor_i[383:352] < descriptor_i[351:320];
                end
            end
            8'd2: begin
                descriptor_ok_o = descriptor_ok_o && descriptor_i[47:32] >= 16'd2 && descriptor_i[63:48] >= 16'd2;
                q_bytes_w = ({48'd0,descriptor_i[47:32]}>>1) * ({48'd0,descriptor_i[63:48]}>>1) *
                    {48'd0,descriptor_i[79:64]} * 64'd16;
            end
            8'd3: q_bytes_w = a_bytes_w * 64'd9;
            8'd4: q_bytes_w = a_bytes_w * 64'd25;
            8'd5: begin
                b_bytes_w = p_w * {48'd0,descriptor_i[127:112]} * 64'd16;
                q_bytes_w = a_bytes_w + b_bytes_w;
                descriptor_ok_o = descriptor_ok_o && descriptor_i[127:112] >= 16'd1 && descriptor_i[127:112] <= 16'd32 && b_w[3:0] == 4'd0;
            end
            8'd6: begin
                a_bytes_w = a_bytes_w * 64'd4; b_bytes_w = a_bytes_w;
                params_bytes_w = {48'd0,descriptor_i[79:64]} * 64'd256;
                descriptor_ok_o = descriptor_ok_o && a_w[5:0] == 6'd0 && b_w[5:0] == 6'd0 &&
                    par_w[5:0] == 6'd0 && descriptor_i[87:80] <= 8'd63 &&
                    $signed(descriptor_i[95:88]) <= $signed(descriptor_i[103:96]);
            end
            default: ;
        endcase
        if (descriptor_i[7:0] != 8'd1) descriptor_ok_o = descriptor_ok_o && descriptor_i[15:8] == 8'd0;
        descriptor_ok_o = descriptor_ok_o && fits(a_w,a_bytes_w) && fits(q_w,q_bytes_w) &&
            !overlap(q_w,q_bytes_w,a_w,a_bytes_w) && !overlap(q_w,q_bytes_w,b_w,b_bytes_w) &&
            !overlap(q_w,q_bytes_w,w_w,weights_bytes_w) && !overlap(q_w,q_bytes_w,par_w,params_bytes_w);
        if (b_bytes_w != 64'd0) descriptor_ok_o = descriptor_ok_o && fits(b_w,b_bytes_w);
        if (weights_bytes_w != 64'd0) descriptor_ok_o = descriptor_ok_o && fits(w_w,weights_bytes_w);
        if (params_bytes_w != 64'd0) descriptor_ok_o = descriptor_ok_o && fits(par_w,params_bytes_w);
        if (m_bytes_w != 64'd0) descriptor_ok_o = descriptor_ok_o && m_w[4:0] == 5'd0 && fits(m_w,m_bytes_w) &&
            !overlap(m_w,m_bytes_w,a_w,a_bytes_w) && !overlap(m_w,m_bytes_w,b_w,b_bytes_w) &&
            !overlap(m_w,m_bytes_w,q_w,q_bytes_w) && !overlap(m_w,m_bytes_w,w_w,weights_bytes_w) &&
            !overlap(m_w,m_bytes_w,par_w,params_bytes_w);
        if (descriptor_i[7:0] == 8'd7) descriptor_ok_o = descriptor_ok_o && descriptor_i[79:64] == 16'd1;
        candidate_bytes_o = q_bytes_w[31:0]; candidate_mac_bytes_o = m_bytes_w[31:0];
    end

    op_core_bank u_bank (
        .clk_i(clk_i), .rst_n_i(rst_n_i && state_r != RESET_CORE),
        .op_i(op_w), .cfg_valid_i(cfg_valid_w), .cfg_ready_o(cfg_ready_w),
        .cin_i(cin_w), .cout_i(cout_w), .pixels_i(pixels_w[18:0]),
        .width_i(width_w), .height_i(height_w), .groups_i(groups_w),
        .words_b_i(pixels_w * {16'd0,d_r[127:112]}), .shift_i(d_r[85:80]),
        .raw_i(raw_w), .int16_i(int16_w), .clamp_min_i(d_r[95:88]), .clamp_max_i(d_r[103:96]),
        .add_group_i(group_r), .add_last_i(group_r+6'd1 == groups_w), .add_params_i(add_params_r),
        .weights_valid_i(state_r == LOAD_WEIGHTS && reader_rsp_w), .weights_ready_o(weights_ready_w),
        .params_valid_i(state_r == LOAD_PARAMS && reader_rsp_w), .params_ready_o(params_ready_w),
        .load_data_i(reader_data_w), .start_valid_i(state_r == START), .start_ready_o(start_ready_w),
        .in_valid_i(bank_in_valid_w), .in_ready_o(bank_in_ready_w), .in_data_i(bank_in_data_w),
        .in_b_valid_i(bank_b_valid_w), .in_b_ready_o(bank_b_ready_w), .in_b_data_i(reader_data_w),
        .rd_valid_o(bank_rd_valid_w), .rd_ready_i(bank_rd_ready_w), .rd_addr_o(bank_rd_addr_w),
        .rd_source_o(bank_rd_source_w), .rsp_valid_i(state_r == RUN && reader_rsp_w && (op_w == 8'd1 || op_w == 8'd5)),
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
        .mem_rsp_valid_i(mem_rsp_valid_i && !response_writer_r), .mem_rsp_ready_o(reader_mem_rsp_ready_w),
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
    always_comb begin
        mem_valid_o = !pending_r && (writer_mem_w || reader_mem_w);
        mem_write_o = writer_mem_w;
        mem_addr_o = writer_mem_w ? writer_mem_addr_w : reader_mem_addr_w;
        mem_data_o = writer_mem_data_w; mem_mask_o = writer_mem_mask_w;
        writer_mem_ready_w = !pending_r && mem_ready_i;
        reader_mem_ready_w = !pending_r && !writer_mem_w && mem_ready_i;
        mem_rsp_ready_o = response_writer_r ? writer_mem_rsp_ready_w : reader_mem_rsp_ready_w;
    end
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
                reader_rsp_ready_w = weights_ready_w;
            end
            LOAD_PARAMS: begin
                reader_req_w = 1'b1; reader_mode_w = 2'd1;
                reader_addr_w = param_base_w[30:0] + (load_count_r[24:0]<<6);
                reader_rsp_ready_w = params_ready_w;
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
                    else reader_addr_w = (bank_rd_source_w ? base_b_w[30:0] : base_a_w[30:0]) + (bank_rd_addr_w[26:0]<<4);
                end
                8'd6: begin
                    reader_mode_w = 2'd1;
                    reader_req_w = input_count_r < pixels_w;
                    reader_addr_w = (add_a_valid_r ? base_b_w[30:0] : base_a_w[30:0]) +
                        (({25'd0,group_r}*pixels_w[30:0]+input_count_r[30:0])<<6);
                    reader_rsp_ready_w = add_a_valid_r ? bank_b_ready_w : 1'b1;
                    bank_in_data_w = add_a_r;
                    bank_in_valid_w = add_a_valid_r;
                    bank_b_valid_w = add_a_valid_r && reader_rsp_w;
                end
                default: begin
                    reader_req_w = input_count_r < total_inputs_w;
                    reader_addr_w = base_a_w[30:0] + (input_count_r[26:0]<<4);
                    reader_rsp_ready_w = bank_in_ready_w;
                    bank_in_valid_w = reader_rsp_w;
                end
            endcase
            default: ;
        endcase
        load_fire_w = reader_rsp_w && reader_rsp_ready_w &&
            (state_r == LOAD_WEIGHTS || state_r == LOAD_PARAMS || state_r == LOAD_ADD);
        in_fire_w = state_r == RUN && reader_rsp_w && reader_rsp_ready_w;
    end

    always_comb begin
        writer_req_w = 1'b0; writer_addr_w = 31'd0; writer_data_w = saved_data_r; writer_bytes_w = 9'd16;
        case (output_r)
            O_Q_REQUEST: begin
                writer_req_w = 1'b1;
                writer_addr_w = out_base_w[30:0] + (saved_output_count_r[26:0]<<4);
                case (op_w)
                    8'd1: begin
                        writer_data_w = 3200'd0;
                        if (int16_w) begin
                            writer_bytes_w = 9'd8; writer_data_w[63:0] = saved_data_r[63:0];
                            writer_addr_w = out_base_w[30:0] + (({24'd0,saved_group_r}*pixels_w[30:0]+{12'd0,saved_pixel_r})<<3);
                        end else begin
                            writer_bytes_w = 9'd4;
                            for (int p=0; p<4; p++) writer_data_w[p*8 +: 8] = saved_data_r[p*16 +: 8];
                            writer_addr_w = out_base_w[30:0] +
                                (({26'd0,saved_group_r[6:2]}*pixels_w[30:0]+{12'd0,saved_pixel_r})<<4) + {27'd0,saved_group_r[1:0],2'd0};
                        end
                    end
                    8'd3: begin writer_bytes_w = 9'd144; writer_addr_w = out_base_w[30:0]+saved_output_count_r[30:0]*31'd144; end
                    8'd4: begin writer_bytes_w = 9'd400; writer_addr_w = out_base_w[30:0]+saved_output_count_r[30:0]*31'd400; end
                    default: ;
                endcase
            end
            O_MAC_REQUEST: begin
                writer_req_w = 1'b1; writer_data_w = {3072'd0,saved_mac_r}; writer_bytes_w = 9'd16;
                writer_addr_w = (raw_w ? out_base_w[30:0] : mac_base_w[30:0]) +
                    (({24'd0,saved_group_r}*pixels_w[30:0]+{12'd0,saved_pixel_r})<<4);
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
            O_IDLE: if (output_fire_w) output_nxt = op_w == 8'd1 && raw_w ? O_MAC_REQUEST : O_Q_REQUEST;
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
        if (output_fire_w) begin
            saved_data_r <= bank_data_w; saved_pixel_r <= bank_pixel_w; saved_group_r <= bank_group_w;
            saved_output_count_r <= output_count_r;
            for (int p=0; p<4; p++) begin
                saved_mac_r[p*32 +: 32] <= bank_mask_w[p] ? bank_mac_w[p*32 +: 32] : 32'd0;
                if (op_w == 8'd1 && !bank_mask_w[p]) saved_data_r[p*16 +: 16] <= 16'd0;
            end
        end
        if (state_r == LOAD_ADD && load_fire_w) add_params_r[load_count_r[1:0]*512 +: 512] <= reader_data_w;
        if (state_r == RUN && op_w == 8'd6 && in_fire_w && !add_a_valid_r) add_a_r <= reader_data_w;
        if (run_valid_i && run_ready_o) d_r <= descriptor_i;
    end
    // 顺序流结果统一采用已保存的输出序号。
    always_comb begin
        drained_w = output_r == O_IDLE && writer_ready_w && reader_ready_w && !pending_r;
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
            CONFIGURE: if (cfg_ready_w) state_nxt = op_w == 8'd1 ? LOAD_WEIGHTS : RUN;
            LOAD_WEIGHTS: if (load_fire_w && load_count_r+32'd1 == weight_words_w) state_nxt = LOAD_PARAMS;
            LOAD_PARAMS: if (load_fire_w && load_count_r+32'd1 == param_words_w) state_nxt = START;
            LOAD_ADD: if (load_fire_w && load_count_r == 32'd3) state_nxt = CONFIGURE;
            START: if (start_ready_w) state_nxt = RUN;
            RUN: if (core_done_r && drained_w) state_nxt = op_w == 8'd6 && group_r+6'd1 < groups_w ? LOAD_ADD : FINISH;
            FINISH: state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= IDLE; input_count_r <= 32'd0; load_count_r <= 32'd0;
            group_r <= 6'd0; core_done_r <= 1'b0; add_a_valid_r <= 1'b0;
            error_r <= 1'b0; aborted_r <= 1'b0; clear_wait_r <= 1'b0;
            clear_addr_r <= 32'd0; result_bytes_o <= 32'd0; mac_bytes_o <= 32'd0;
        end else begin
            state_r <= state_nxt;
            if (run_valid_i && run_ready_o) begin
                result_bytes_o <= q_bytes_w[31:0]; mac_bytes_o <= m_bytes_w[31:0];
                error_r <= 1'b0; aborted_r <= 1'b0;
            end
            if (abort_i && busy_o) aborted_r <= 1'b1; // 安全中止：运行到排空边界，状态可查询。
            if (reader_rsp_w && reader_rsp_ready_w && reader_error_w) error_r <= 1'b1;
            if (state_r == LOAD_PARAMS && load_fire_w)
                for (int p=0; p<4; p++)
                    if ($signed(reader_data_w[p*128+96 +: 16]) > $signed(reader_data_w[p*128+112 +: 16])) error_r <= 1'b1;
            if (state_r == LOAD_ADD && load_fire_w)
                for (int p=0; p<4; p++)
                    if (reader_data_w[p*128 +: 32] != {{10{reader_data_w[p*128+21]}},reader_data_w[p*128 +: 22]} ||
                        reader_data_w[p*128+32 +: 32] != {{10{reader_data_w[p*128+53]}},reader_data_w[p*128+32 +: 22]}) error_r <= 1'b1;
            if (writer_done_w && writer_error_w) error_r <= 1'b1;
            if (state_r == RESET_CORE) begin
                group_r <= 6'd0; input_count_r <= 32'd0; load_count_r <= 32'd0;
                core_done_r <= 1'b0; add_a_valid_r <= 1'b0; clear_addr_r <= out_base_w;
                clear_wait_r <= 1'b0;
            end
            if (state_r == CLEAR) begin
                if (writer_req_w && writer_ready_w) clear_wait_r <= 1'b1;
                if (writer_done_w) begin clear_wait_r <= 1'b0; clear_addr_r <= clear_addr_r+32'd32; end
            end
            if (load_fire_w) load_count_r <= load_count_r+32'd1;
            if (state_r != state_nxt) load_count_r <= 32'd0;
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
                    group_r <= group_r+6'd1; input_count_r <= 32'd0; core_done_r <= 1'b0;
                end
            end
        end
    end
endmodule
