`timescale 1ns/1ps
// 【文件类型：.sv】协议 V1 的 0x20..0x25 扩展。请求/回复均采用稳定总线 toggle 握手 CDC。
// CRC 未通过的帧不提交；请求按到达顺序进入 NB 深环形队列，回复 UDP 发送完成后才释放对应槽位。
module op_transport (
    input logic rx_clk_i, // 时钟域输入
    input logic ui_clk_i, // 时钟域输入
    input logic rx_rst_n_i, // 异步低有效控制复位
    input logic ui_rst_n_i, // 异步低有效控制复位
    input logic legacy_idle_i, // 任务配置或协议控制字段
    input logic block_ui_i, // 阶段占用与流控状态
    input logic frame_valid_i, // 握手有效，阻塞期间保持载荷
    input logic body_en_i, // 数据载荷，低位承载首字节或首 lane
    output logic accept_o, // 任务配置或协议控制字段
    output logic block_rx_o, // 阶段占用与流控状态
    output logic tx_start_o, // 任务配置或协议控制字段
    input logic tx_req_i, // 任务配置或协议控制字段
    input logic tx_done_i, // 完成通知，须遵守排空条件
    output logic req_valid_o, // 握手有效，阻塞期间保持载荷
    input logic req_ready_i, // 握手接收许可
    input logic resp_valid_i, // 握手有效，阻塞期间保持载荷
    input logic [7:0] msg_i, // 任务配置或协议控制字段
    input logic [31:0] id_i, // 任务配置或协议控制字段
    input logic [31:0] sequence_i, // 任务配置或协议控制字段
    input logic [15:0] body_len_i, // 数据载荷，低位承载首字节或首 lane
    input logic [15:0] body_count_i, // 数据载荷，低位承载首字节或首 lane
    input logic [7:0] body_data_i, // 数据载荷，低位承载首字节或首 lane
    output logic [7:0] tx_data_o, // 数据载荷，低位承载首字节或首 lane
    output logic [15:0] tx_len_o, // 有效字节数或接口长度
    output logic [7:0] req_msg_o, // 任务配置或协议控制字段
    output logic [31:0] req_id_o, // 任务配置或协议控制字段
    output logic [31:0] req_sequence_o, // 任务配置或协议控制字段
    output logic [15:0] req_len_o, // 有效字节数或接口长度
    output logic [511:0] req_body_o, // 仅保留描述符/请求头；大包载荷留在 RAM
    input logic [4:0] req_data_addr_i, // 请求载荷的 32B 字地址，一拍同步读
    input logic req_data_en_i,
    output logic [255:0] req_data_o,
    input logic [15:0] resp_len_i, // 有效字节数或接口长度
    input logic [127:0] resp_body_i, // 16B 回复头，直到 UDP 完成保持稳定
    input logic resp_data_we_i,
    input logic [4:0] resp_data_addr_i,
    input logic [255:0] resp_data_i
);
    // 环形队列不变量：wr_ptr_r == active_bank_r + count_r（模 NB）。
    // 队满时 RX 被阻塞；队列内任一槽位的载荷 RAM 与描述符都不会被后续帧改写。
    localparam int NB = 4;
    localparam int PTR_W = $clog2(NB);
    logic [511:0] request_body_r[0:NB-1];
    logic [7:0] request_msg_r;
    logic [31:0] request_id_r, request_sequence_r;
    logic [7:0] request_msg_bank_r[0:NB-1];
    logic [31:0] request_id_bank_r[0:NB-1], request_sequence_bank_r[0:NB-1];
    logic [15:0] request_len_bank_r[0:NB-1];
    logic [15:0] request_len_r;
    logic request_r, ui_seen_r, reply_r, reply_seen_r;
    logic [PTR_W-1:0] wr_ptr_r, active_bank_r;
    logic [PTR_W:0] count_r;
    logic full_r;
    (* ASYNC_REG="TRUE" *) logic req_sync1_r, req_sync2_r;
    (* ASYNC_REG="TRUE" *) logic reply_sync1_r, reply_sync2_r;
    (* ASYNC_REG="TRUE" *) logic block_sync1_r, block_sync2_r;
    logic [7:0] unused_body_w[0:0];
    logic [15:0] build_body_addr_w;
    logic [9:0] request_byte_addr_w, reply_byte_addr_w;
    logic [255:0] request_data_w;
    logic request_write_w, reply_payload_r;
    logic [7:0] reply_ram_data_w, reply_header_r, reply_data_w;
    logic [127:0] reply_header_rx_r;
    logic [15:0] reply_len_rx_r;
    // 请求 toggle 已在 ui 域同步后，再锁存稳定的描述符总线。
    // 描述符与载荷 bank 同拍锁存；service 的 RAM 数据选择只使用 ui 域寄存器。
    logic [511:0] request_body_ui_r;
    logic [PTR_W-1:0] active_bank_ui_r;
    logic body_loaded_r;
    logic build_start_r, build_valid_w, build_done_w;
    logic [7:0] build_data_w;
    logic [15:0] build_bytes_w;
    (* ram_style="block" *) logic [7:0] tx_mem_r[0:2047];
    logic [10:0] wr_ptr_tx_r, rd_ptr_tx_r;
    logic frame_ready_r;
    logic pop_w, launch_new_w, launch_queued_w;
    logic [PTR_W-1:0] next_bank_w;
    assign pop_w = tx_done_i && frame_ready_r;
    assign next_bank_w = active_bank_r + 1'b1;
    // 空队列接收，或本拍恰好释放最后一个请求：新帧直接成为活动请求。
    assign launch_new_w = accept_o &&
        (count_r == {(PTR_W+1){1'b0}} || (pop_w && count_r == {{PTR_W{1'b0}},1'b1}));
    // 活动请求回复完成且后面已有排队请求：装载下一条描述符。
    assign launch_queued_w = pop_w && count_r > {{PTR_W{1'b0}},1'b1};
    assign accept_o = frame_valid_i && msg_i >= 8'h20 && msg_i <= 8'h29 &&
        body_len_i <= 16'd1032 && !full_r && legacy_idle_i;
    assign block_rx_o = full_r || block_sync2_r;
    assign req_valid_o = body_loaded_r;
    assign req_msg_o = request_msg_r; assign req_id_o = request_id_r;
    assign req_sequence_o = request_sequence_r; assign req_len_o = request_len_r;
    assign req_body_o = request_body_ui_r;
    assign request_byte_addr_w = body_count_i[9:0] - 10'd8;
    assign request_write_w = body_en_i && msg_i == 8'h20 && !full_r &&
        body_count_i >= 16'd8 && body_count_i < 16'd1032;
    rpc_request_bram u_request_ram (
        .clka(rx_clk_i), .ena(request_write_w), .wea(request_write_w),
        .addra({wr_ptr_r, request_byte_addr_w}), .dina(body_data_i),
        .clkb(ui_clk_i), .enb(req_data_en_i), .addrb({active_bank_ui_r, req_data_addr_i}), .doutb(request_data_w)
    );
    assign req_data_o = request_data_w;
    assign reply_byte_addr_w = build_body_addr_w[9:0] - 10'd16;
    rpc_response_bram u_reply_ram (
        .clka(ui_clk_i), .ena(resp_data_we_i), .wea(resp_data_we_i),
        .addra(resp_data_addr_i), .dina(resp_data_i),
        .clkb(rx_clk_i), .enb(build_body_addr_w >= 16'd16), .addrb(reply_byte_addr_w), .doutb(reply_ram_data_w)
    );
    // RAM 和回复头均按 builder 提前一拍的地址取数；跨域所有权仍由 toggle 保证。
    always_ff @(posedge rx_clk_i) begin
        reply_payload_r <= build_body_addr_w >= 16'd16;
        reply_header_r <= reply_header_rx_r[build_body_addr_w[3:0]*8 +: 8];
        if (reply_sync2_r != reply_seen_r) begin
            reply_header_rx_r <= resp_body_i;
            reply_len_rx_r <= resp_len_i;
        end
    end
    assign reply_data_w = reply_payload_r ? reply_ram_data_w : reply_header_r;
    assign unused_body_w[0] = 8'd0;
    protocol_builder #(.BODY_MAX(1), .BODY_FROM_RAM(1'b1)) u_builder (
        .clk_i(rx_clk_i), .rst_n_i(rx_rst_n_i), .build_start_i(build_start_r),
        .msg_type_i(request_msg_r | 8'h80), .transfer_id_i(request_id_r),
        .sequence_i(request_sequence_r), .body_len_i(reply_len_rx_r), .build_body_i(unused_body_w),
        .body_addr_o(build_body_addr_w), .body_data_i(reply_data_w),
        .tx_data_o(build_data_w), .tx_valid_o(build_valid_w),
        .tx_bytes_o(build_bytes_w), .tx_done_o(build_done_w)
    );
    always_ff @(posedge rx_clk_i) begin
        // 队满时 RX 被阻塞，这里仍显式门控，保证不会改写活动/排队槽位的描述符头。
        if (body_en_i && msg_i >= 8'h20 && msg_i <= 8'h29 && body_count_i < 16'd64 && !full_r)
            request_body_r[wr_ptr_r][body_count_i[5:0]*8 +: 8] <= body_data_i;
        if (build_valid_w) tx_mem_r[wr_ptr_tx_r] <= build_data_w;
        if (tx_req_i && frame_ready_r) tx_data_o <= tx_mem_r[rd_ptr_tx_r];
    end
    always_ff @(posedge rx_clk_i or negedge rx_rst_n_i) begin
        if (!rx_rst_n_i) begin
            request_r <= 1'b0; reply_seen_r <= 1'b0;
            request_msg_r <= 8'd0; request_id_r <= 32'd0; request_sequence_r <= 32'd0; request_len_r <= 16'd0;
            for (int bank=0; bank<NB; bank++) begin
                request_msg_bank_r[bank] <= 8'd0; request_id_bank_r[bank] <= 32'd0;
                request_sequence_bank_r[bank] <= 32'd0; request_len_bank_r[bank] <= 16'd0;
            end
            wr_ptr_r <= {PTR_W{1'b0}}; active_bank_r <= {PTR_W{1'b0}};
            count_r <= {(PTR_W+1){1'b0}}; full_r <= 1'b0;
            reply_sync1_r <= 1'b0; reply_sync2_r <= 1'b0;
            block_sync1_r <= 1'b0; block_sync2_r <= 1'b0;
            build_start_r <= 1'b0; frame_ready_r <= 1'b0;
            wr_ptr_tx_r <= 11'd0; rd_ptr_tx_r <= 11'd0; tx_len_o <= 16'd0;
        end else begin
            reply_sync1_r <= reply_r; reply_sync2_r <= reply_sync1_r;
            block_sync1_r <= block_ui_i; block_sync2_r <= block_sync1_r;
            build_start_r <= 1'b0;
            if (accept_o) begin
                request_msg_bank_r[wr_ptr_r] <= msg_i;
                request_id_bank_r[wr_ptr_r] <= id_i;
                request_sequence_bank_r[wr_ptr_r] <= sequence_i;
                request_len_bank_r[wr_ptr_r] <= body_len_i;
                wr_ptr_r <= wr_ptr_r + 1'b1;
            end
            if (launch_new_w) begin
                request_r <= !request_r;
                request_msg_r <= msg_i; request_id_r <= id_i;
                request_sequence_r <= sequence_i; request_len_r <= body_len_i;
            end else if (launch_queued_w) begin
                request_r <= !request_r;
                request_msg_r <= request_msg_bank_r[next_bank_w];
                request_id_r <= request_id_bank_r[next_bank_w];
                request_sequence_r <= request_sequence_bank_r[next_bank_w];
                request_len_r <= request_len_bank_r[next_bank_w];
            end
            if (pop_w) active_bank_r <= next_bank_w;
            // 接收与释放同拍发生时计数不变；full_r 单独寄存，避免比较器进入 RX 阻塞路径。
            case ({accept_o, pop_w})
                2'b10: begin count_r <= count_r + 1'b1; full_r <= count_r == (PTR_W+1)'(NB-1); end
                2'b01: begin count_r <= count_r - 1'b1; full_r <= 1'b0; end
                default: ;
            endcase
            if (reply_sync2_r != reply_seen_r) begin
                reply_seen_r <= reply_sync2_r; build_start_r <= 1'b1;
                wr_ptr_tx_r <= 11'd0; rd_ptr_tx_r <= 11'd0;
            end
            if (build_valid_w) wr_ptr_tx_r <= wr_ptr_tx_r+11'd1;
            if (build_done_w) begin frame_ready_r <= 1'b1; tx_len_o <= build_bytes_w; end
            if (tx_req_i && frame_ready_r) rd_ptr_tx_r <= rd_ptr_tx_r+11'd1;
            if (pop_w) frame_ready_r <= 1'b0;
        end
    end
    assign tx_start_o = frame_ready_r;
    always_ff @(posedge ui_clk_i or negedge ui_rst_n_i) begin
        if (!ui_rst_n_i) begin
            req_sync1_r <= 1'b0; req_sync2_r <= 1'b0; ui_seen_r <= 1'b0; reply_r <= 1'b0;
            request_body_ui_r <= 512'd0; body_loaded_r <= 1'b0;
            active_bank_ui_r <= {PTR_W{1'b0}};
        end
        else begin
            req_sync1_r <= request_r; req_sync2_r <= req_sync1_r;
            if (req_sync2_r != ui_seen_r && !body_loaded_r) begin
                request_body_ui_r <= request_body_r[active_bank_r];
                active_bank_ui_r <= active_bank_r;
                body_loaded_r <= 1'b1;
            end
            if (body_loaded_r && req_ready_i) begin
                ui_seen_r <= req_sync2_r;
                body_loaded_r <= 1'b0;
            end
            if (resp_valid_i) reply_r <= ui_seen_r;
        end
    end
endmodule
