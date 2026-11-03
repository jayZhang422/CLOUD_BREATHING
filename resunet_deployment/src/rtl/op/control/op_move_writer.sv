`timescale 1ns/1ps
// 【文件类型：.sv】P16连续结果两两合并为32B，复用官方写队列IP后台写回。
// 最后不足32B仅写低16B；idle包含全部在途写响应，任务仍由engine执行最终FENCE。
module op_move_writer #(
    parameter bit ADDRESS_PER_WORD = 1'b0,
    parameter int PENDING_MAX = 8 // 最多在途写请求数
) (
    input  logic         clk_i,          // 计算时钟
    input  logic         rst_n_i,        // 异步低有效复位
    input  logic         start_i,        // 排空后开始新任务
    input  logic [30:0]  base_i,         // 32B对齐输出地址
    input  logic [30:0]  address_i,      // 可选逐P16地址，支持16B起始的分段写回
    input  logic         valid_i,        // P16结果有效
    output logic         ready_o,        // 结果接收许可
    input  logic [127:0] data_i,         // P16结果
    input  logic         last_i,         // 最后一个P16结果
    output logic         idle_o,         // 半拍、队列和写响应完全排空
    output logic         error_o,        // 写错误锁存
    output logic         mem_valid_o,    // 后台写请求
    input  logic         mem_ready_i,    // 请求接收许可
    output logic [30:0]  mem_addr_o,     // 32B对齐地址
    output logic [255:0] mem_data_o,     // 合并结果
    output logic [31:0]  mem_mask_o,     // 有效字节掩码
    input  logic         mem_rsp_valid_i,// 写响应
    input  logic         mem_rsp_error_i // 写错误
);
    logic half_r, full_w, empty_w, push_w, pop_w;
    logic [127:0] low_r;
    logic [30:0] address_r;
    logic [319:0] fifo_in_w, fifo_out_w;
    logic [319:0] fifo_in_r;
    logic fifo_push_r;
    logic [5:0] queued_r;
    logic [$clog2(PENDING_MAX):0] pending_r;
    logic [30:0] word_address_w;
    logic [159:0] input_queue_r[0:1];
    logic input_head_r, input_tail_r, input_push_w, input_pop_w, input_ready_w;
    logic [1:0] input_count_r;
    logic [127:0] input_data_w;
    logic [30:0] input_address_w;
    logic input_last_w, input_valid_w;
    // 先保存上游选择后的完整载荷，隔离算子/搬运选择到半字合并的长路径。
    assign ready_o = input_count_r < 2'd2;
    assign input_push_w = valid_i && ready_o;
    assign input_valid_w = input_count_r != 2'd0;
    assign input_pop_w = input_valid_w && input_ready_w;
    assign {input_last_w,input_address_w,input_data_w} = input_queue_r[input_head_r];
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin input_count_r <= 2'd0; input_head_r <= 1'b0; input_tail_r <= 1'b0; end
        else begin
            if (input_push_w) input_tail_r <= !input_tail_r;
            if (input_pop_w) input_head_r <= !input_head_r;
            case ({input_push_w,input_pop_w})
                2'b10: input_count_r <= input_count_r + 2'd1;
                2'b01: input_count_r <= input_count_r - 2'd1;
                default: ;
            endcase
        end
    end
    always_ff @(posedge clk_i)
        if (input_push_w) input_queue_r[input_tail_r] <= {last_i,address_i,data_i};
    assign word_address_w = ADDRESS_PER_WORD ? input_address_w : address_r;
    // queued_r在上游握手时计数，包含尚未写入FIFO的一级流水，防止超额接收。
    assign input_ready_w = !full_w && queued_r < 6'd32;
    assign push_w = input_pop_w && (word_address_w[4] || input_last_w);
    assign fifo_in_w = {1'b1,word_address_w[30:5],5'd0,
                        word_address_w[4] ? (half_r ? 32'hffffffff : 32'hffff0000) : 32'h0000ffff,
                        word_address_w[4] ? {input_data_w,half_r ? low_r : 128'd0} : {128'd0,input_data_w}};
    op_write_queue_fifo u_results (
        .clk(clk_i), .rst(!rst_n_i), .din(fifo_in_r), .wr_en(fifo_push_r),
        .rd_en(pop_w), .dout(fifo_out_w), .full(full_w), .empty(empty_w)
    );
    assign mem_valid_o = !empty_w && pending_r < ($clog2(PENDING_MAX)+1)'(PENDING_MAX);
    assign mem_data_o = fifo_out_w[255:0];
    assign mem_mask_o = fifo_out_w[287:256];
    assign mem_addr_o = fifo_out_w[318:288];
    assign pop_w = mem_valid_o && mem_ready_i;
    assign idle_o = input_count_r == 2'd0 && !half_r && queued_r == 6'd0 && pending_r == '0;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            half_r <= 1'b0; address_r <= 31'd0;
            fifo_push_r <= 1'b0;
            queued_r <= 6'd0; pending_r <= '0; error_o <= 1'b0;
        end else begin
            fifo_push_r <= push_w;
            if (start_i) begin address_r <= base_i; half_r <= 1'b0; error_o <= 1'b0; end
            if (input_pop_w) begin
                half_r <= !word_address_w[4] && !input_last_w;
                if (!ADDRESS_PER_WORD) address_r <= address_r+31'd16;
            end
            case ({push_w,pop_w})
                2'b10: queued_r <= queued_r + 6'd1;
                2'b01: queued_r <= queued_r - 6'd1;
                default: ;
            endcase
            case ({pop_w,mem_rsp_valid_i})
                2'b10: pending_r <= pending_r + 1'b1;
                2'b01: pending_r <= pending_r - 1'b1;
                default: ;
            endcase
            if (mem_rsp_valid_i && mem_rsp_error_i) error_o <= 1'b1;
        end
    end
    always_ff @(posedge clk_i) begin
        if (input_pop_w && !half_r) low_r <= input_data_w;
        // 组合拼接先打拍，切断算子/打包选择到分布式FIFO的宽数据路径。
        if (push_w) fifo_in_r <= fifo_in_w;
    end
endmodule
