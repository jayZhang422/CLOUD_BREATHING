`timescale 1ns/1ps
// 【文件类型：.sv】两路保序仲裁；8笔响应标签，不复制宽数据。
// 下游按接收顺序返回；等待ready期间锁定选择，禁止切换载荷。
module op_mem_arbiter_wstream_before (
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
    logic [7:0] owner_r;
    logic [2:0] head_r, tail_r;
    logic [3:0] count_r;
    logic locked_r, locked_source_r, prefer_r, selected_w;
    logic push_w, pop_w;
    always_comb begin
        selected_w = prefer_r;
        if (locked_r) selected_w = locked_source_r;
        else case (req_valid_i)
            2'b01: selected_w = 1'b0;
            2'b10: selected_w = 1'b1;
            default: ;
        endcase
        req_ready_o = 2'b00; rsp_valid_o = 2'b00;
        mem_valid_o = count_r < 4'd8 && req_valid_i[selected_w];
        req_ready_o[selected_w] = count_r < 4'd8 && mem_ready_i;
        mem_write_o = req_write_i[selected_w];
        mem_addr_o = selected_w ? req_addr_i[61:31] : req_addr_i[30:0];
        mem_data_o = selected_w ? req_data_i[511:256] : req_data_i[255:0];
        mem_mask_o = selected_w ? req_mask_i[63:32] : req_mask_i[31:0];
        if (count_r != 4'd0) rsp_valid_o[owner_r[head_r]] = mem_rsp_valid_i;
        mem_rsp_ready_o = count_r != 4'd0 && rsp_ready_i[owner_r[head_r]];
        pending_o = count_r != 4'd0;
    end
    assign push_w = mem_valid_o && mem_ready_i;
    assign pop_w = mem_rsp_valid_i && mem_rsp_ready_o;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            head_r <= 3'd0; tail_r <= 3'd0; count_r <= 4'd0;
            locked_r <= 1'b0; locked_source_r <= 1'b0; prefer_r <= 1'b0;
        end else begin
            if (mem_valid_o && !mem_ready_i) begin
                locked_r <= 1'b1; locked_source_r <= selected_w;
            end
            if (push_w) begin
                tail_r <= tail_r + 3'd1; locked_r <= 1'b0; prefer_r <= !selected_w;
            end
            if (pop_w) head_r <= head_r + 3'd1;
            case ({push_w,pop_w})
                2'b10: count_r <= count_r + 4'd1;
                2'b01: count_r <= count_r - 4'd1;
                default: ;
            endcase
        end
    end
    always_ff @(posedge clk_i) if (push_w) owner_r[tail_r] <= selected_w;
endmodule
