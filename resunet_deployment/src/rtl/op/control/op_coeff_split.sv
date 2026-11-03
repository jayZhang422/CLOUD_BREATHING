`timescale 1ns/1ps
// 【文件类型：.sv】8笔保序路由：DDR和片上参数分开提交，按接收标签交付。
// 参数源可以单笔工作；DDR请求不再等待每次跨域响应。
module op_coeff_split (
    input  logic clk_i, // 算子域时钟
    input  logic rst_n_i, // 异步低有效控制复位
    input  logic req_valid_i, // 上游请求有效
    output logic req_ready_o, // 上游请求接收许可
    input  logic req_write_i, // 写标志
    input  logic [30:0] req_addr_i, // 请求字节地址
    output logic rsp_valid_o, // 按请求顺序交付响应
    input  logic rsp_ready_i, // 上游响应接收许可
    output logic [255:0] rsp_data_o, // 返回数据
    output logic rsp_error_o, // 返回错误标志
    output logic ddr_req_valid_o, // DDR请求有效
    input  logic ddr_req_ready_i, // DDR请求接收许可
    input  logic ddr_rsp_valid_i, // DDR响应有效
    output logic ddr_rsp_ready_o, // DDR响应接收许可
    input  logic [255:0] ddr_rsp_data_i, // DDR返回数据
    input  logic ddr_rsp_error_i, // DDR返回错误
    output logic coeff_req_valid_o, // 片上系数请求有效
    input  logic coeff_req_ready_i, // 片上系数请求接收许可
    output logic [30:0] coeff_req_addr_o, // 片上系数字节地址
    input  logic coeff_rsp_valid_i, // 片上系数响应有效
    output logic coeff_rsp_ready_o, // 片上系数响应接收许可
    input  logic [255:0] coeff_rsp_data_i, // 片上系数返回数据
    input  logic coeff_rsp_error_i // 片上系数返回错误
);
    localparam logic [30:0] COEFF_BASE = 31'h00100000;
    localparam logic [30:0] COEFF_LIMIT = 31'h00159600;
    logic [1:0] owner_r [0:7];
    logic [2:0] head_r, tail_r;
    logic [3:0] count_r;
    logic select_coeff_w, push_w, pop_w;
    assign select_coeff_w = req_addr_i >= COEFF_BASE && req_addr_i < COEFF_LIMIT;
    assign coeff_req_addr_o = req_addr_i;
    assign push_w = req_valid_i && req_ready_o;
    assign pop_w = rsp_valid_o && rsp_ready_i;
    always_comb begin
        req_ready_o = 1'b0; ddr_req_valid_o = 1'b0; coeff_req_valid_o = 1'b0;
        if (count_r < 4'd8) begin
            if (select_coeff_w) begin
                req_ready_o = req_write_i || coeff_req_ready_i;
                coeff_req_valid_o = req_valid_i && !req_write_i;
            end else begin
                req_ready_o = ddr_req_ready_i;
                ddr_req_valid_o = req_valid_i;
            end
        end
        rsp_valid_o = 1'b0; rsp_data_o = 256'd0; rsp_error_o = 1'b0;
        ddr_rsp_ready_o = 1'b0; coeff_rsp_ready_o = 1'b0;
        if (count_r != 4'd0) case (owner_r[head_r])
            2'd0: begin
                rsp_valid_o = ddr_rsp_valid_i; rsp_data_o = ddr_rsp_data_i;
                rsp_error_o = ddr_rsp_error_i; ddr_rsp_ready_o = rsp_ready_i;
            end
            2'd1: begin
                rsp_valid_o = coeff_rsp_valid_i; rsp_data_o = coeff_rsp_data_i;
                rsp_error_o = coeff_rsp_error_i; coeff_rsp_ready_o = rsp_ready_i;
            end
            2'd2: begin rsp_valid_o = 1'b1; rsp_error_o = 1'b1; end
            default: ;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin head_r <= 3'd0; tail_r <= 3'd0; count_r <= 4'd0; end
        else begin
            if (push_w) tail_r <= tail_r + 3'd1;
            if (pop_w) head_r <= head_r + 3'd1;
            case ({push_w,pop_w})
                2'b10: count_r <= count_r + 4'd1;
                2'b01: count_r <= count_r - 4'd1;
                default: ;
            endcase
        end
    end
    always_ff @(posedge clk_i)
        if (push_w) owner_r[tail_r] <= select_coeff_w ? (req_write_i ? 2'd2 : 2'd1) : 2'd0;
endmodule
