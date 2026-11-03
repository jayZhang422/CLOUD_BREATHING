`timescale 1ns/1ps
// 【文件类型：.sv】可综合单在途路由：只读参数空间与特征 DDR 分开。
// 参数接口是 256-bit 请求/响应；ROM IP 及固定读延迟适配本次不实现。
module op_coeff_split (
    input  logic         clk_i,                  // 计算域时钟
    input  logic         rst_n_i,                // 异步低有效控制复位
    input  logic         req_valid_i,            // 上游请求有效
    output logic         req_ready_o,            // 上游接收许可
    input  logic         req_write_i,            // 写请求
    input  logic [30:0]  req_addr_i,             // 字节地址，32B 对齐
    output logic         rsp_valid_o,            // 上游响应有效
    input  logic         rsp_ready_i,            // 上游响应接收许可
    output logic [255:0] rsp_data_o,             // 首字节在低位
    output logic         rsp_error_o,            // 参数空间写入被拒绝
    output logic         ddr_req_valid_o,        // 特征 DDR 请求
    input  logic         ddr_req_ready_i,        // DDR 接收许可
    input  logic         ddr_rsp_valid_i,        // DDR 响应有效
    output logic         ddr_rsp_ready_o,        // DDR 响应接收许可
    input  logic [255:0] ddr_rsp_data_i,          // DDR 返回数据
    input  logic         ddr_rsp_error_i,        // DDR 返回错误
    output logic         coeff_req_valid_o,      // 独立只读参数请求
    input  logic         coeff_req_ready_i,      // 参数源接收许可
    output logic [30:0]  coeff_req_addr_o,       // 参数空间字节地址
    input  logic         coeff_rsp_valid_i,      // 参数源返回有效，可等待
    output logic         coeff_rsp_ready_o,      // 参数源返回接收许可
    input  logic [255:0] coeff_rsp_data_i,        // 参数源数据，反压期间保持
    input  logic         coeff_rsp_error_i       // 参数源返回错误
);
    localparam logic [30:0] COEFF_BASE  = 31'h00100000;
    localparam logic [30:0] COEFF_LIMIT = 31'h00400000;
    typedef enum logic [1:0] {IDLE, DDR_WAIT, COEFF_WAIT, REJECT_WRITE} state_t;
    state_t state_r, state_nxt;
    logic select_coeff_w;

    assign select_coeff_w = req_addr_i >= COEFF_BASE && req_addr_i < COEFF_LIMIT;
    assign coeff_req_addr_o = req_addr_i;

    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) state_r <= IDLE;
        else          state_r <= state_nxt;
    end

    always_comb begin
        state_nxt = state_r;
        case (state_r)
            IDLE: if (req_valid_i && req_ready_o) begin
                if (select_coeff_w)
                    state_nxt = req_write_i ? REJECT_WRITE : COEFF_WAIT;
                else state_nxt = DDR_WAIT;
            end
            DDR_WAIT, COEFF_WAIT, REJECT_WRITE:
                if (rsp_valid_o && rsp_ready_i) state_nxt = IDLE;
            default: state_nxt = IDLE;
        endcase
    end

    always_comb begin
        req_ready_o = 1'b0;
        rsp_valid_o = 1'b0;
        rsp_data_o = 256'd0;
        rsp_error_o = 1'b0;
        ddr_req_valid_o = 1'b0;
        ddr_rsp_ready_o = 1'b0;
        coeff_req_valid_o = 1'b0;
        coeff_rsp_ready_o = 1'b0;
        case (state_r)
            IDLE: begin
                if (select_coeff_w) begin
                    req_ready_o = req_write_i ? 1'b1 : coeff_req_ready_i;
                    coeff_req_valid_o = req_valid_i && !req_write_i;
                end else begin
                    req_ready_o = ddr_req_ready_i;
                    ddr_req_valid_o = req_valid_i;
                end
            end
            DDR_WAIT: begin
                rsp_valid_o = ddr_rsp_valid_i;
                rsp_data_o = ddr_rsp_data_i;
                rsp_error_o = ddr_rsp_error_i;
                ddr_rsp_ready_o = rsp_ready_i;
            end
            COEFF_WAIT: begin
                rsp_valid_o = coeff_rsp_valid_i;
                rsp_data_o = coeff_rsp_data_i;
                rsp_error_o = coeff_rsp_error_i;
                coeff_rsp_ready_o = rsp_ready_i;
            end
            REJECT_WRITE: begin
                rsp_valid_o = 1'b1;
                rsp_error_o = 1'b1;
            end
            default: ;
        endcase
    end
endmodule
