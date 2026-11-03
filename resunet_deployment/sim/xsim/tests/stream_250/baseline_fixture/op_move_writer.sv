`timescale 1ns/1ps
// 【文件类型：.sv】P16连续结果两两合并为32B，复用官方写队列IP后台写回。
// 最后不足32B仅写低16B；idle包含全部在途写响应，任务仍由engine执行最终FENCE。
module op_move_writer_stream250_before (
    input  logic         clk_i,          // 计算时钟
    input  logic         rst_n_i,        // 异步低有效复位
    input  logic         start_i,        // 排空后开始新任务
    input  logic [30:0]  base_i,         // 32B对齐输出地址
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
    logic [5:0] queued_r;
    logic [3:0] pending_r;
    assign ready_o = !full_w;
    assign push_w = valid_i && ready_o && (half_r || last_i);
    assign fifo_in_w = {1'b1,address_r,half_r ? 32'hffffffff : 32'h0000ffff,
                        half_r ? {data_i,low_r} : {128'd0,data_i}};
    op_write_queue_fifo u_results (
        .clk(clk_i), .rst(!rst_n_i), .din(fifo_in_w), .wr_en(push_w),
        .rd_en(pop_w), .dout(fifo_out_w), .full(full_w), .empty(empty_w)
    );
    assign mem_valid_o = !empty_w && pending_r < 4'd8;
    assign mem_data_o = fifo_out_w[255:0];
    assign mem_mask_o = fifo_out_w[287:256];
    assign mem_addr_o = fifo_out_w[318:288];
    assign pop_w = mem_valid_o && mem_ready_i;
    assign idle_o = !half_r && queued_r == 6'd0 && pending_r == 4'd0;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            half_r <= 1'b0; address_r <= 31'd0;
            queued_r <= 6'd0; pending_r <= 4'd0; error_o <= 1'b0;
        end else begin
            if (start_i) begin address_r <= base_i; half_r <= 1'b0; error_o <= 1'b0; end
            if (valid_i && ready_o) half_r <= !(half_r || last_i);
            if (push_w) address_r <= address_r + 31'd32;
            case ({push_w,pop_w})
                2'b10: queued_r <= queued_r + 6'd1;
                2'b01: queued_r <= queued_r - 6'd1;
                default: ;
            endcase
            case ({pop_w,mem_rsp_valid_i})
                2'b10: pending_r <= pending_r + 4'd1;
                2'b01: pending_r <= pending_r - 4'd1;
                default: ;
            endcase
            if (mem_rsp_valid_i && mem_rsp_error_i) error_o <= 1'b1;
        end
    end
    always_ff @(posedge clk_i)
        if (valid_i && ready_o && !half_r) low_r <= data_i;
endmodule
