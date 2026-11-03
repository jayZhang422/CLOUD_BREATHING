`timescale 1ns/1ps
// 【文件类型：.sv】PW保序供数；官方FIFO隔离请求/返回，相邻16B复用32B。
module op_pw_reader #(
    parameter int CREDITS = 8 // 最多在途 32B 读请求数（2的幂，不得超过响应 FIFO 深度 32）
) (
    input logic clk_i,
    input logic rst_n_i,
    input logic clear_i,
    input logic req_valid_i,
    output logic req_ready_o,
    input logic [30:0] req_addr_i,
    input logic req_source_i,
    output logic rsp_valid_o,
    input logic rsp_ready_i,
    output logic [127:0] rsp_data_o,
    output logic rsp_source_o,
    output logic error_o,
    output logic idle_o,
    output logic mem_valid_o,
    input logic mem_ready_i,
    output logic [30:0] mem_addr_o,
    input logic mem_rsp_valid_i,
    output logic mem_rsp_ready_o,
    input logic [255:0] mem_rsp_data_i,
    input logic mem_rsp_error_i
);
    logic reset_w, request_full_w, request_empty_w, response_full_w, response_empty_w;
    logic [319:0] request_w;
    logic [255:0] response_w, previous_data_r[0:1];
    logic [30:0] previous_address_r[0:1];
    logic [1:0] previous_valid_r;
    logic reuse_w, issue_w, consume_w, request_push_w, response_pop_w;
    logic prepare_w, prepare_reuse_w, request_valid_r, request_reuse_r, request_source_r;
    logic [30:0] request_address_r;
    localparam int CW = $clog2(CREDITS);
    logic [CW-1:0] head_r, tail_r;
    logic [CW:0] count_r;
    logic [5:0] queued_r;
    logic [CREDITS-1:0] reuse_r, half_r, source_r;
    // 队首元数据寄存，避免队首索引参与响应控制组合链。
    logic head_reuse_r, head_half_r, head_source_r;
    logic next_reuse_w, next_half_w, next_source_w;
    logic [1:0] response_count_r, response_source_r;
    logic response_head_r, response_tail_r;
    // 仅两项响应，使用寄存器阵列避免 response_head_r 经过分布式 RAM 再串到引擎输出队列。
    (* ram_style = "registers" *) logic [127:0] response_data_r[0:1];
    logic [127:0] selected_response_w;
    assign reset_w = !rst_n_i || clear_i;
    assign req_ready_o = !reset_w && !request_full_w;
    assign request_push_w = req_valid_i && req_ready_o;
    op_write_queue_fifo u_requests (
        .clk(clk_i), .rst(reset_w), .din({288'd0,req_source_i,req_addr_i}),
        .wr_en(request_push_w), .rd_en(prepare_w), .dout(request_w),
        .full(request_full_w), .empty(request_empty_w)
    );
    // 描述标签最多8笔；每笔新32B读取在输出消费前一直占用一个信用。
    // 复用比较先寄存，不能经过共享仲裁 ready 再返回其它 reader/writer。
    assign prepare_reuse_w = previous_valid_r[request_w[31]] &&
        previous_address_r[request_w[31]] == {request_w[30:5],5'd0};
    assign prepare_w = !reset_w && !request_empty_w && (!request_valid_r || issue_w);
    assign reuse_w = request_reuse_r;
    assign mem_valid_o = !reset_w && request_valid_r && count_r < (CW+1)'(CREDITS) && !reuse_w;
    assign mem_addr_o = {request_address_r[30:5],5'd0};
    assign issue_w = !reset_w && request_valid_r && count_r < (CW+1)'(CREDITS) && (reuse_w || mem_ready_i);
    assign mem_rsp_ready_o = !reset_w && !response_full_w;
    op_move_read_fifo u_responses (
        .clk(clk_i), .rst(reset_w), .din(mem_rsp_data_i),
        .wr_en(mem_rsp_valid_i && mem_rsp_ready_o),
        .rd_en(consume_w && !head_reuse_r), .dout(response_w),
        .full(response_full_w), .empty(response_empty_w)
    );
    // 两槽弹性缓存只按寄存占用量取FIFO，下游ready不再组合驱动BRAM使能。
    assign consume_w = !reset_w && response_count_r < 2'd2 && count_r != '0 &&
        (head_reuse_r || !response_empty_w);
    assign rsp_valid_o = !reset_w && response_count_r != 2'd0;
    assign response_pop_w = rsp_valid_o && rsp_ready_i;
    assign rsp_data_o = response_data_r[response_head_r];
    assign rsp_source_o = response_source_r[response_head_r];
    assign idle_o = queued_r == 6'd0 && !request_valid_r && count_r == '0 && response_count_r == 2'd0;
    /*
     * 输出暂存槽将下游反压与响应 BRAM 读使能隔离。
     * FIFO 数据在当前边沿装入暂存槽，外部接口保持标准 valid/ready。
     */
    assign selected_response_w = head_reuse_r ?
        (head_half_r ? previous_data_r[head_source_r][255:128] : previous_data_r[head_source_r][127:0]) :
        (head_half_r ? response_w[255:128] : response_w[127:0]);
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            head_r <= '0; tail_r <= '0; count_r <= '0; queued_r <= 6'd0;
            previous_valid_r <= 2'd0; error_o <= 1'b0;
            head_reuse_r <= 1'b0; head_half_r <= 1'b0; head_source_r <= 1'b0;
            response_count_r <= 2'd0; response_head_r <= 1'b0; response_tail_r <= 1'b0;
            request_valid_r <= 1'b0;
        end else if (clear_i) begin
            head_r <= '0; tail_r <= '0; count_r <= '0; queued_r <= 6'd0;
            previous_valid_r <= 2'd0; error_o <= 1'b0;
            head_reuse_r <= 1'b0; head_half_r <= 1'b0; head_source_r <= 1'b0;
            response_count_r <= 2'd0; response_head_r <= 1'b0; response_tail_r <= 1'b0;
            request_valid_r <= 1'b0;
        end else begin
            if (response_pop_w) response_head_r <= !response_head_r;
            if (consume_w) response_tail_r <= !response_tail_r;
            case ({consume_w,response_pop_w})
                2'b10: response_count_r <= response_count_r + 2'd1;
                2'b01: response_count_r <= response_count_r - 2'd1;
                default: ;
            endcase
            if (prepare_w) begin
                request_valid_r <= 1'b1;
                request_reuse_r <= prepare_reuse_w;
                request_source_r <= request_w[31];
                request_address_r <= request_w[30:0];
                previous_valid_r[request_w[31]] <= 1'b1;
            end else if (issue_w) request_valid_r <= 1'b0;
            if (issue_w) tail_r <= tail_r + 1'b1;
            if (consume_w) head_r <= head_r + 1'b1;
            // 空队列首笔 issue 成为队首；消费时预装下一笔元数据。
            if (issue_w && count_r == '0) begin
                head_reuse_r <= reuse_w;
                head_half_r <= request_address_r[4];
                head_source_r <= request_source_r;
            end else if (consume_w) begin
                head_reuse_r <= next_reuse_w;
                head_half_r <= next_half_w;
                head_source_r <= next_source_w;
            end
            case ({issue_w,consume_w})
                2'b10: count_r <= count_r + 1'b1;
                2'b01: count_r <= count_r - 1'b1;
                default: ;
            endcase
            case ({request_push_w,prepare_w})
                2'b10: queued_r <= queued_r + 6'd1;
                2'b01: queued_r <= queued_r - 6'd1;
                default: ;
            endcase
            if (mem_rsp_valid_i && mem_rsp_ready_o && mem_rsp_error_i) error_o <= 1'b1;
        end
    end
    always_ff @(posedge clk_i) begin
        if (consume_w) begin
            response_data_r[response_tail_r] <= selected_response_w;
            response_source_r[response_tail_r] <= head_source_r;
        end
        if (prepare_w) begin
            previous_address_r[request_w[31]] <= {request_w[30:5],5'd0};
        end
        if (issue_w) begin
            reuse_r[tail_r] <= reuse_w; half_r[tail_r] <= request_address_r[4];
            source_r[tail_r] <= request_source_r;
        end
        if (consume_w && !head_reuse_r) previous_data_r[head_source_r] <= response_w;
    end
    // count==1 且同时 issue 时，下一笔元数据来自本拍写入值；否则来自环形队列。
    always_comb begin
        next_reuse_w = reuse_r[head_r + 1'b1];
        next_half_w = half_r[head_r + 1'b1];
        next_source_w = source_r[head_r + 1'b1];
        if (count_r == (CW+1)'(1) && issue_w) begin
            next_reuse_w = reuse_w;
            next_half_w = request_address_r[4];
            next_source_w = request_source_r;
        end
    end
endmodule
