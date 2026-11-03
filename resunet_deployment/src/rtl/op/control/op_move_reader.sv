`timescale 1ns/1ps
// 【文件类型：.sv】连续P16读：最多8笔32B在途，官方FIFO保存响应。
// 两段输入按A→B拼接；丢弃首尾对齐块中的无效半拍，不额外预取下一32B块。
module op_move_reader #(
    parameter int CREDITS = 8 // 最多在途 32B 读请求数（2的幂，不得超过响应 FIFO 深度 32）
) (
    input  logic         clk_i,          // 计算时钟
    input  logic         rst_n_i,        // 异步低有效复位
    input  logic         start_i,        // 空闲时锁存两段配置
    input  logic [30:0]  base_a_i,       // A段16B对齐字节地址
    input  logic [30:0]  base_b_i,       // B段16B对齐字节地址
    input  logic [31:0]  words_a_i,      // A段P16字数，非零
    input  logic [31:0]  words_b_i,      // B段P16字数，零表示单段
    output logic         valid_o,        // 连续输入流有效
    input  logic         ready_i,        // 核心反压
    output logic [127:0] data_o,         // P16输入数据
    output logic         last_o,         // 最后一个合法P16字
    output logic         idle_o,         // 请求与响应完全排空
    output logic         error_o,        // 本次读错误锁存
    output logic         mem_valid_o,    // 32B读请求
    output logic         mem_prefetch_o, // 当前1KiB行之后仍有待读行
    input  logic         mem_ready_i,    // 请求接收许可
    output logic [30:0]  mem_addr_o,     // 32B对齐字节地址
    input  logic         mem_rsp_valid_i,// 保序读响应
    output logic         mem_rsp_ready_o,// 响应接收许可
    input  logic [255:0] mem_rsp_data_i, // 32B返回数据
    input  logic         mem_rsp_error_i // 返回错误
);
    logic active_r, issue_r, issue_b_r, output_b_r, half_r, b_half_r;
    logic [30:0] address_r, base_b_r;
    logic [31:0] beats_r, beats_b_r, left_r, words_b_r;
    logic [$clog2(CREDITS):0] credit_r;
    logic full_w, empty_w, issue_fire_w, output_fire_w, pop_w;
    logic [5:0] line_beats_left_w;
    logic [255:0] fifo_data_w;

    op_move_read_fifo u_responses (
        .clk(clk_i), .rst(!rst_n_i), .din(mem_rsp_data_i),
        .wr_en(mem_rsp_valid_i && mem_rsp_ready_o), .rd_en(pop_w),
        .dout(fifo_data_w), .full(full_w), .empty(empty_w)
    );
    assign mem_valid_o = issue_r && credit_r < ($clog2(CREDITS)+1)'(CREDITS);
    assign line_beats_left_w = 6'd32 - {1'b0,address_r[9:5]};
    assign mem_prefetch_o = mem_valid_o && ((|beats_r[31:6]) || beats_r[5:0] > line_beats_left_w);
    assign mem_addr_o = address_r;
    assign mem_rsp_ready_o = !full_w;
    assign valid_o = active_r && !empty_w;
    assign data_o = half_r ? fifo_data_w[255:128] : fifo_data_w[127:0];
    assign last_o = left_r == 32'd1 && (output_b_r || words_b_r == 32'd0);
    assign issue_fire_w = mem_valid_o && mem_ready_i;
    assign output_fire_w = valid_o && ready_i;
    assign pop_w = output_fire_w && (half_r || left_r == 32'd1);
    assign idle_o = !active_r && !issue_r && credit_r == '0;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            active_r <= 1'b0; issue_r <= 1'b0; issue_b_r <= 1'b0;
            output_b_r <= 1'b0; half_r <= 1'b0; b_half_r <= 1'b0;
            address_r <= 31'd0; base_b_r <= 31'd0;
            beats_r <= 32'd0; beats_b_r <= 32'd0;
            left_r <= 32'd0; words_b_r <= 32'd0; credit_r <= '0;
            error_o <= 1'b0;
        end else begin
            if (start_i) begin
                active_r <= 1'b1; issue_r <= 1'b1;
                issue_b_r <= 1'b0; output_b_r <= 1'b0;
                address_r <= {base_a_i[30:5],5'd0};
                base_b_r <= {base_b_i[30:5],5'd0};
                beats_r <= (words_a_i + {31'd0,base_a_i[4]} + 32'd1) >> 1;
                beats_b_r <= (words_b_i + {31'd0,base_b_i[4]} + 32'd1) >> 1;
                left_r <= words_a_i; words_b_r <= words_b_i;
                half_r <= base_a_i[4]; b_half_r <= base_b_i[4];
                error_o <= 1'b0;
            end
            if (issue_fire_w) begin
                address_r <= address_r + 31'd32;
                beats_r <= beats_r - 32'd1;
                if (beats_r == 32'd1) begin
                    if (!issue_b_r && words_b_r != 32'd0) begin
                        issue_b_r <= 1'b1;
                        address_r <= base_b_r; beats_r <= beats_b_r;
                    end else issue_r <= 1'b0;
                end
            end
            if (output_fire_w) begin
                half_r <= !half_r;
                left_r <= left_r - 32'd1;
                if (left_r == 32'd1) begin
                    if (!output_b_r && words_b_r != 32'd0) begin
                        output_b_r <= 1'b1; half_r <= b_half_r; left_r <= words_b_r;
                    end else active_r <= 1'b0;
                end
            end
            case ({issue_fire_w,pop_w})
                2'b10: credit_r <= credit_r + 1'b1;
                2'b01: credit_r <= credit_r - 1'b1;
                default: ;
            endcase
            if (mem_rsp_valid_i && mem_rsp_ready_o && mem_rsp_error_i) error_o <= 1'b1;
        end
    end
endmodule
