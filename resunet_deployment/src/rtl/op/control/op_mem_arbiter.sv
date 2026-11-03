`timescale 1ns/1ps
// 【文件类型：.sv】两路保序仲裁；两槽请求缓冲、8笔响应标签。
// 下游按接收顺序返回；等待ready期间由本地缓冲保持完整载荷。
module op_mem_arbiter #(
    parameter int TAGS = 8 // 在途响应标签数（2的幂）；engine 存储路径用 16，其余保持 8
) (
    input  logic         clk_i, // 算子域时钟
    input  logic         rst_n_i, // 异步低有效控制复位
    input  logic [1:0]   req_valid_i, // 上游请求有效
    output logic [1:0]   req_ready_o, // 上游请求接收许可
    input  logic [1:0]   req_write_i, // 写标志
    input  logic [61:0]  req_addr_i, // 请求字节地址
    input  logic [511:0] req_data_i, // 写数据，首字节在低位
    input  logic [63:0]  req_mask_i, // 逐字节写使能
    output logic [1:0]   rsp_valid_o, // 按请求顺序交付响应
    input  logic [1:0]   rsp_ready_i, // 上游响应接收许可
    output logic         pending_o, // 存在尚未返回的请求
    output logic         mem_valid_o, // 下游请求有效
    input  logic         mem_ready_i, // 下游请求接收许可
    output logic         mem_write_o, // 下游写标志
    output logic [30:0]  mem_addr_o, // 下游字节地址
    output logic [255:0] mem_data_o, // 下游写数据
    output logic [31:0]  mem_mask_o, // 下游字节写使能
    input  logic         mem_rsp_valid_i, // 下游响应有效
    output logic         mem_rsp_ready_o // 下游响应接收许可
);
    localparam int TW = $clog2(TAGS);
    logic [TAGS-1:0] owner_r;
    logic [TW-1:0] head_r, tail_r;
    logic [TW:0] count_r;
    logic prefer_r, selected_w;
    logic push_w, pop_w;
    logic accept_w, request_head_r, request_tail_r;
    logic [1:0] request_count_r;
    logic [319:0] request_r[0:1];
    always_comb begin
        selected_w = prefer_r;
        case (req_valid_i)
            2'b01: selected_w = 1'b0;
            2'b10: selected_w = 1'b1;
            default: ;
        endcase
        req_ready_o = 2'b00; rsp_valid_o = 2'b00;
        // 本地空槽决定接收许可；下游ready不再穿过两级仲裁回到宽FIFO。
        mem_valid_o = request_count_r != 2'd0;
        req_ready_o[selected_w] = count_r < (TW+1)'(TAGS) && request_count_r < 2'd2;
        {mem_write_o,mem_addr_o,mem_mask_o,mem_data_o} = request_r[request_head_r];
        if (count_r != '0) rsp_valid_o[owner_r[head_r]] = mem_rsp_valid_i;
        mem_rsp_ready_o = count_r != '0 && rsp_ready_i[owner_r[head_r]];
        pending_o = count_r != '0;
    end
    assign push_w = req_valid_i[selected_w] && req_ready_o[selected_w];
    assign accept_w = mem_valid_o && mem_ready_i;
    assign pop_w = mem_rsp_valid_i && mem_rsp_ready_o;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            head_r <= '0; tail_r <= '0; count_r <= '0;
            prefer_r <= 1'b0;
            request_count_r <= 2'd0; request_head_r <= 1'b0; request_tail_r <= 1'b0;
        end else begin
            if (accept_w) request_head_r <= !request_head_r;
            if (push_w) begin
                tail_r <= tail_r + 1'b1; prefer_r <= !selected_w;
                request_tail_r <= !request_tail_r;
            end
            case ({push_w,accept_w})
                2'b10: request_count_r <= request_count_r + 2'd1;
                2'b01: request_count_r <= request_count_r - 2'd1;
                default: ;
            endcase
            if (pop_w) head_r <= head_r + 1'b1;
            case ({push_w,pop_w})
                2'b10: count_r <= count_r + 1'b1;
                2'b01: count_r <= count_r - 1'b1;
                default: ;
            endcase
        end
    end
    always_ff @(posedge clk_i) if (push_w) begin
        owner_r[tail_r] <= selected_w;
        request_r[request_tail_r] <= {req_write_i[selected_w],
            selected_w ? req_addr_i[61:31] : req_addr_i[30:0],
            selected_w ? req_mask_i[63:32] : req_mask_i[31:0],
            selected_w ? req_data_i[511:256] : req_data_i[255:0]};
    end
endmodule
