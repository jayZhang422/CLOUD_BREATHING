`timescale 1ns/1ps
// 【文件类型：.sv】RPC 控制、通用上传/回读及运行身份管理。一次只保留一个结果。
// status:0成功 1忙 2参数错 3DDR错 4中止 5输入未就绪 6身份过期。
module op_service_wstream_before #(
    parameter logic [31:0] COMPUTE_HZ = 32'd125000000 // 性能记录中的实际计算频率
)(
    input logic clk_i, // 时钟域输入
    input logic rst_n_i, // 异步低有效控制复位
    input logic storage_idle_i, // 任务配置或协议控制字段
    input logic image_ready_i, // 握手接收许可
    input logic req_valid_i, // 握手有效，阻塞期间保持载荷
    output logic req_ready_o, // 握手接收许可
    output logic resp_valid_o, // 握手有效，阻塞期间保持载荷
    output logic claim_o, // 阶段占用与流控状态
    output logic mem_valid_o, // 握手有效，阻塞期间保持载荷
    input logic mem_ready_i, // 握手接收许可
    output logic mem_write_o, // DDR 事务接口字段
    input logic mem_rsp_valid_i, // 握手有效，阻塞期间保持载荷
    output logic mem_rsp_ready_o, // 握手接收许可
    input logic mem_rsp_error_i, // 本次操作错误状态
    input logic [30:0] image_base_i, // 地址字段，单位按模块接口约定
    input logic [31:0] image_slices_i, // 任务配置或协议控制字段
    input logic [7:0] req_msg_i, // 任务配置或协议控制字段
    input logic [31:0] req_id_i, // 任务配置或协议控制字段
    input logic [15:0] req_len_i, // 有效字节数或接口长度
    input logic [511:0] req_body_i, // 描述符/请求头，完整载荷在 transport RAM
    output logic [4:0] req_data_addr_o,
    output logic req_data_en_o,
    input logic [255:0] req_data_i,
    output logic [15:0] resp_len_o, // 有效字节数或接口长度
    output logic [127:0] resp_body_o, // 固定回复头；大包数据同步写 RAM
    output logic resp_data_we_o,
    output logic [4:0] resp_data_addr_o,
    output logic [255:0] resp_data_o,
    output logic [30:0] mem_addr_o, // 地址字段，单位按模块接口约定
    output logic [255:0] mem_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [31:0] mem_mask_o, // DDR 事务接口字段
    input logic [255:0] mem_rsp_data_i // 数据载荷，低位承载首字节或首 lane
);
    typedef enum logic [3:0] {IDLE, CHECK_DESCRIPTOR, DECODE, START_RUN, WRITE_REQUEST, READ_REQUEST,
        WRITE_RETURN, READ_RETURN, FLUSH_REQUEST, FLUSH_RETURN, REPLY, WAIT_SEND, WRITE_PREFETCH,
        PERF_PREFETCH, PERF_RETURN} state_t;
    state_t state_r, state_nxt;
    logic [7:0] msg_r, status_r, op_r, format_r;
    logic [31:0] id_r, run_id_r, offset_r, out_base_r, mac_base_r;
    logic [15:0] len_r, transfer_len_r;
    logic [511:0] body_r;
    logic [127:0] response_r;
    logic [511:0] last_descriptor_r;
    logic held_r, seen_r, finished_r, final_error_r, final_abort_r, abort_pending_r;
    logic engine_busy_w, engine_done_w, engine_error_w, engine_abort_w, engine_ready_w, descriptor_ok_w;
    logic check_done_w;
    logic abort_w;
    logic [31:0] result_bytes_w, mac_bytes_w;
    logic [31:0] candidate_bytes_w, candidate_mac_bytes_w;
    logic upload_volume_overlap_w, result_volume_overlap_w;
    logic [63:0] volume_end_w;
    logic engine_mem_w, engine_write_w, engine_rsp_ready_w;
    logic [30:0] engine_addr_w; logic [255:0] engine_data_w; logic [31:0] engine_mask_w;
    logic rpc_mem_w, rpc_write_w, pending_r;
    logic [1:0] mem_source_ready_w, mem_response_valid_w;
    logic [30:0] rpc_addr_w; logic [255:0] rpc_data_w;
    logic request_ok_w, result_range_w;
    logic [63:0] request_end_r;
    logic [63:0] result_end_r, mac_end_r;
    logic [7:0] report_state_w;
    localparam logic [30:0] PERF_BASE = 31'h1fff0000;
    localparam logic [30:0] PERF_LIMIT = 31'h1fff4000;
    logic [1279:0] engine_perf_w;
    logic perf_writing_r, perf_request_w, perf_read_valid_r;
    logic [2:0] perf_word_r;
    logic [63:0] perf_valid_r;
    logic [8:0] perf_read_addr_w;
    logic [255:0] perf_write_data_w, perf_read_data_w;
    assign req_ready_o = state_r == IDLE;
    assign req_data_addr_o = offset_r[9:5];
    assign req_data_en_o = state_r == WRITE_PREFETCH || state_r == WRITE_REQUEST;
    assign resp_data_we_o = (state_r == READ_RETURN && mem_response_valid_w[1]) || state_r == PERF_RETURN;
    assign resp_data_addr_o = offset_r[9:5];
    assign resp_data_o = state_r == PERF_RETURN ?
        (perf_read_valid_r ? perf_read_data_w : 256'd0) : mem_rsp_data_i;
    assign claim_o = engine_busy_w || held_r || state_r != IDLE;
    assign abort_w = state_r == DECODE && msg_r == 8'h25 && len_r == 16'd0 && held_r && id_r == run_id_r && engine_busy_w;
    op_engine_wstream_before u_engine (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .run_valid_i(state_r == START_RUN && !perf_writing_r),
        .check_valid_i(state_r == CHECK_DESCRIPTOR), .check_done_o(check_done_w),
        .run_ready_o(engine_ready_w), .descriptor_i(body_r[511:0]), .descriptor_ok_o(descriptor_ok_w),
        .abort_i(abort_w), .busy_o(engine_busy_w), .done_o(engine_done_w),
        .error_o(engine_error_w), .aborted_o(engine_abort_w),
        .result_bytes_o(result_bytes_w), .mac_bytes_o(mac_bytes_w),
        .candidate_bytes_o(candidate_bytes_w), .candidate_mac_bytes_o(candidate_mac_bytes_w),
        .mem_valid_o(engine_mem_w), .mem_ready_i(mem_source_ready_w[0]),
        .mem_write_o(engine_write_w), .mem_addr_o(engine_addr_w), .mem_data_o(engine_data_w), .mem_mask_o(engine_mask_w),
        .mem_rsp_valid_i(mem_response_valid_w[0]), .mem_rsp_ready_o(engine_rsp_ready_w),
        .mem_rsp_data_i(mem_rsp_data_i), .mem_rsp_error_i(mem_rsp_error_i), .perf_data_o(engine_perf_w)
    );
    assign rpc_mem_w = state_r == WRITE_REQUEST || state_r == READ_REQUEST || state_r == FLUSH_REQUEST;
    assign rpc_write_w = state_r == WRITE_REQUEST || state_r == FLUSH_REQUEST;
    op_mem_arbiter_wstream_before u_service_queue (
        .clk_i(clk_i), .rst_n_i(rst_n_i),
        .req_valid_i({rpc_mem_w && !pending_r,engine_mem_w}), .req_ready_o(mem_source_ready_w),
        .req_write_i({rpc_write_w,engine_write_w}), .req_addr_i({rpc_addr_w,engine_addr_w}),
        .req_data_i({rpc_data_w,engine_data_w}),
        .req_mask_i({state_r == FLUSH_REQUEST ? 32'd0 : 32'hffffffff,engine_mask_w}),
        .rsp_valid_o(mem_response_valid_w),
        .rsp_ready_i({state_r == WRITE_RETURN || state_r == READ_RETURN || state_r == FLUSH_RETURN,engine_rsp_ready_w}),
        .pending_o(), .mem_valid_o(mem_valid_o), .mem_ready_i(mem_ready_i),
        .mem_write_o(mem_write_o), .mem_addr_o(mem_addr_o), .mem_data_o(mem_data_o), .mem_mask_o(mem_mask_o),
        .mem_rsp_valid_i(mem_rsp_valid_i), .mem_rsp_ready_o(mem_rsp_ready_o)
    );
    always_comb begin
        rpc_addr_w = body_r[30:0] + offset_r[30:0];
        if (state_r == FLUSH_REQUEST) rpc_addr_w = 31'd0;
        rpc_data_w = req_data_i;
        perf_request_w = body_r[63:48] == 16'd1 && body_r[31:0] >= {1'b0,PERF_BASE} &&
                         request_end_r <= {33'd0,PERF_LIMIT};
        volume_end_w = {33'd0,image_base_i} + ({32'd0,image_slices_i}<<18);
        upload_volume_overlap_w = image_ready_i && {32'd0,body_r[31:0]} < volume_end_w && request_end_r > {33'd0,image_base_i};
        result_volume_overlap_w = image_ready_i &&
            (({32'd0,body_r[223:192]} < volume_end_w && {32'd0,body_r[223:192]}+{32'd0,candidate_bytes_w} > {33'd0,image_base_i}) ||
             (candidate_mac_bytes_w != 32'd0 && {32'd0,body_r[255:224]} < volume_end_w && {32'd0,body_r[255:224]}+{32'd0,candidate_mac_bytes_w} > {33'd0,image_base_i}));
        request_ok_w = len_r >= 16'd8 && body_r[47:32] >= 16'd32 &&
            body_r[47:32] <= 16'd1024 && body_r[36:32] == 5'd0 && body_r[4:0] == 5'd0 &&
            request_end_r <= 64'h20000000;
        // 尾包允许读到最后一个32B拍；结束地址已在任务完成时锁存。
        result_range_w = held_r && finished_r && !final_error_r && !final_abort_r && id_r == run_id_r &&
            ((body_r[31:0] >= out_base_r && request_end_r <= result_end_r) ||
             (mac_bytes_w != 32'd0 && body_r[31:0] >= mac_base_r && request_end_r <= mac_end_r));
        report_state_w = 8'd0;
        if (held_r) begin
            if (engine_busy_w) report_state_w = abort_pending_r ? 8'd4 : 8'd1;
            else if (finished_r) report_state_w = final_error_r || final_abort_r ? 8'd3 : 8'd2;
        end
        resp_valid_o = state_r == REPLY;
        resp_len_o = msg_r == 8'h23 && status_r == 8'd0 ? 16'd16+transfer_len_r : 16'd16;
        resp_body_o = response_r;
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i)
                state_nxt = req_msg_i == 8'h21 && req_len_i == 16'd64 ? CHECK_DESCRIPTOR : DECODE;
            CHECK_DESCRIPTOR: if (check_done_w) state_nxt = DECODE;
            DECODE: begin
                state_nxt = REPLY;
                case (msg_r)
                    8'h20: if (!held_r && storage_idle_i && request_ok_w && !upload_volume_overlap_w && len_r == 16'd8+body_r[47:32] && body_r[63:48] == 16'd0) state_nxt = WRITE_PREFETCH;
                    8'h21: if ((!seen_r || id_r != run_id_r) && !held_r && storage_idle_i && len_r == 16'd64 && descriptor_ok_w && !result_volume_overlap_w && body_r[415:384] == id_r &&
                        (!body_r[8] || (image_ready_i && body_r[159:128] == {1'b0,image_base_i} && body_r[351:320] == image_slices_i))) state_nxt = START_RUN;
                    8'h23: if (!engine_busy_w && storage_idle_i && request_ok_w && len_r == 16'd8 &&
                        !perf_writing_r &&
                        (result_range_w || (body_r[63:48] == 16'd1 && !held_r && id_r == 32'd0)))
                        state_nxt = perf_request_w ? PERF_PREFETCH : READ_REQUEST;
                    default: ;
                endcase
            end
            START_RUN: if (engine_ready_w && !perf_writing_r) state_nxt = REPLY;
            WRITE_PREFETCH: state_nxt = WRITE_REQUEST; // offset 更新后一拍读出下一个 32B
            WRITE_REQUEST: if (mem_source_ready_w[1] && !pending_r) state_nxt = WRITE_RETURN;
            READ_REQUEST: if (mem_source_ready_w[1] && !pending_r) state_nxt = READ_RETURN;
            WRITE_RETURN, READ_RETURN: if (mem_response_valid_w[1]) begin
                if (mem_rsp_error_i || offset_r+32'd32 >= {16'd0,transfer_len_r})
                    state_nxt = state_r == WRITE_RETURN ? FLUSH_REQUEST : REPLY;
                else state_nxt = state_r == WRITE_RETURN ? WRITE_PREFETCH : READ_REQUEST;
            end
            FLUSH_REQUEST: if (mem_source_ready_w[1] && !pending_r) state_nxt = FLUSH_RETURN;
            FLUSH_RETURN: if (mem_response_valid_w[1]) state_nxt = REPLY;
            PERF_PREFETCH: state_nxt = PERF_RETURN;
            PERF_RETURN: state_nxt = offset_r+32'd32 >= {16'd0,transfer_len_r} ? REPLY : PERF_PREFETCH;
            REPLY: state_nxt = WAIT_SEND;
            WAIT_SEND: if (!req_valid_i) state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end
    // finished_r同拍置位，后续结果查询只做比较，不串联取整、基址加法和比较。
    always_ff @(posedge clk_i) begin
        if (engine_done_w) begin
            result_end_r <= {32'd0,out_base_r} + (({32'd0,result_bytes_w}+64'd31)&64'hffffffffffffffe0);
            mac_end_r <= {32'd0,mac_base_r} + (({32'd0,mac_bytes_w}+64'd31)&64'hffffffffffffffe0);
        end
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            state_r <= IDLE; msg_r <= 8'd0; status_r <= 8'd0; op_r <= 8'd0; format_r <= 8'd0;
            id_r <= 32'd0; run_id_r <= 32'd0; offset_r <= 32'd0; out_base_r <= 32'd0; mac_base_r <= 32'd0;
            len_r <= 16'd0; transfer_len_r <= 16'd0;
            held_r <= 1'b0; seen_r <= 1'b0; finished_r <= 1'b0;
            final_error_r <= 1'b0; final_abort_r <= 1'b0; abort_pending_r <= 1'b0;
            pending_r <= 1'b0;
        end else begin
            state_r <= state_nxt;
            if (rpc_mem_w && !pending_r && mem_source_ready_w[1]) pending_r <= 1'b1;
            if (mem_response_valid_w[1]) pending_r <= 1'b0;
            if (engine_done_w) begin
                finished_r <= 1'b1; final_error_r <= engine_error_w; final_abort_r <= engine_abort_w;
            end
            if (state_r == IDLE && req_valid_i) begin
                msg_r <= req_msg_i; id_r <= req_id_i; len_r <= req_len_i;
                offset_r <= 32'd0; transfer_len_r <= req_body_i[47:32]; status_r <= 8'd0;
            end
            if (state_r == DECODE) case (msg_r)
                8'h20: begin
                    if (held_r || !storage_idle_i) status_r <= 8'd1;
                    else if (state_nxt != WRITE_PREFETCH) status_r <= 8'd2;
                end
                8'h21: begin
                    if (seen_r && id_r == run_id_r) begin
                        if (!held_r) status_r <= 8'd6;
                        else if (body_r[511:0] != last_descriptor_r) status_r <= 8'd2;
                    end else if (held_r || !storage_idle_i) status_r <= 8'd1;
                    else if (len_r != 16'd64 || !descriptor_ok_w || result_volume_overlap_w || body_r[415:384] != id_r) status_r <= 8'd2;
                    else if (body_r[8] && (!image_ready_i || body_r[159:128] != {1'b0,image_base_i} || body_r[351:320] != image_slices_i)) status_r <= 8'd5;
                end
                8'h22: if (len_r != 16'd0) status_r <= 8'd2;
                8'h23: begin
                    if (engine_busy_w || !storage_idle_i || perf_writing_r) status_r <= 8'd1;
                    else if (!request_ok_w || len_r != 16'd8 || body_r[63:48] > 16'd1) status_r <= 8'd2;
                    else if (state_nxt != READ_REQUEST && state_nxt != PERF_PREFETCH) status_r <= 8'd6;
                end
                8'h24: begin
                    if (len_r != 16'd0) status_r <= 8'd2;
                    else if (engine_busy_w) status_r <= 8'd1;
                    else if (!seen_r || id_r != run_id_r) status_r <= 8'd6;
                    else held_r <= 1'b0;
                end
                8'h25: begin
                    if (len_r != 16'd0) status_r <= 8'd2;
                    else if (!held_r || id_r != run_id_r) status_r <= 8'd6;
                    else begin
                        abort_pending_r <= 1'b1;
                        if (!engine_busy_w) final_abort_r <= 1'b1;
                    end
                end
                default: status_r <= 8'd2;
            endcase
            if (state_r == START_RUN && engine_ready_w && !perf_writing_r) begin
                run_id_r <= id_r; held_r <= 1'b1; seen_r <= 1'b1; finished_r <= 1'b0;
                final_error_r <= 1'b0; final_abort_r <= 1'b0; abort_pending_r <= 1'b0;
                out_base_r <= body_r[223:192]; mac_base_r <= body_r[255:224]; op_r <= body_r[7:0];
                format_r <= (body_r[7:0] == 8'd8 || body_r[7:0] == 8'd9 || body_r[12]) ? 8'd5 :
                    body_r[10] ? 8'd2 : body_r[11] ? 8'd1 : body_r[7:0] == 8'd3 ? 8'd3 : body_r[7:0] == 8'd4 ? 8'd4 : 8'd0;
            end
            if ((state_r == WRITE_RETURN || state_r == READ_RETURN) && mem_response_valid_w[1]) begin
                offset_r <= offset_r+32'd32;
                if (mem_rsp_error_i) status_r <= 8'd3;
            end
            if (state_r == PERF_RETURN) offset_r <= offset_r+32'd32;
            if (state_r == FLUSH_RETURN && mem_response_valid_w[1] && mem_rsp_error_i) status_r <= 8'd3;
        end
    end
    always_ff @(posedge clk_i) begin
        if (state_r == IDLE && req_valid_i) begin
            body_r <= req_body_i;
            // 请求握手拍预存结束地址，范围检查不再串联加法进状态选择。
            request_end_r <= {32'd0,req_body_i[31:0]} + {48'd0,req_body_i[47:32]};
        end
        // 与BRAM读同拍保存槽位有效性，避免地址选择直接驱动256位回复数据门控。
        if (state_r == PERF_PREFETCH) perf_read_valid_r <= perf_valid_r[perf_read_addr_w[8:3]];
        if (state_r == START_RUN && engine_ready_w && !perf_writing_r) last_descriptor_r <= body_r[511:0];
        if (state_r == REPLY) begin
            response_r[7:0] <= status_r; response_r[15:8] <= report_state_w;
            response_r[23:16] <= op_r; response_r[31:24] <= format_r;
            response_r[63:32] <= run_id_r; response_r[95:64] <= result_bytes_w; response_r[127:96] <= mac_bytes_w;
        end
    end
    // 每层记录256B，run_id低6位选槽；只占用诊断READ别名，不写特征DDR。
    // 原有READ格式和生产结果不变，普通READ仍访问DDR。
    assign perf_read_addr_w = body_r[13:5] + offset_r[13:5];
    always_comb begin
        perf_write_data_w = 256'd0;
        case (perf_word_r)
            3'd0: perf_write_data_w = {30'd0,final_abort_r,final_error_r,32'd333333333,
                COMPUTE_HZ,{16'd0,format_r,op_r},run_id_r,32'd1,32'd256,32'h4650504f};
            3'd1: perf_write_data_w = engine_perf_w[255:0];
            3'd2: perf_write_data_w = engine_perf_w[511:256];
            3'd3: perf_write_data_w = engine_perf_w[767:512];
            3'd4: perf_write_data_w = engine_perf_w[1023:768];
            3'd5: perf_write_data_w = engine_perf_w[1279:1024];
            default: ;
        endcase
    end
    op_perf_bram u_perf_memory (
        .clka(clk_i), .ena(perf_writing_r), .wea(1'b1),
        .addra({run_id_r[5:0],perf_word_r}), .dina(perf_write_data_w),
        .clkb(clk_i), .enb(state_r == PERF_PREFETCH), .addrb(perf_read_addr_w), .doutb(perf_read_data_w)
    );
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            perf_writing_r <= 1'b0; perf_word_r <= 3'd0; perf_valid_r <= 64'd0;
        end else begin
            if (engine_done_w) begin
                perf_writing_r <= 1'b1; perf_word_r <= 3'd0;
                perf_valid_r[run_id_r[5:0]] <= 1'b0;
            end else if (perf_writing_r) begin
                perf_word_r <= perf_word_r+3'd1;
                if (perf_word_r == 3'd7) begin
                    perf_writing_r <= 1'b0; perf_valid_r[run_id_r[5:0]] <= 1'b1;
                end
            end
        end
    end
endmodule
