`timescale 1ns/1ps
// 【文件类型：.sv】联合验证连接层：RPC→调度/算子→特征 DDR 与只读参数接口。
// 外部 C++ 模拟存储响应；不包含 ROM IP、UDP/RGMII 或跨时钟域传输。
module tb_op_candidate (
    input  logic          clk_i,
    input  logic          rst_n_i,
    input  logic          req_valid_i,
    output logic          req_ready_o,
    input  logic [7:0]    req_msg_i,
    input  logic [31:0]   req_id_i,
    input  logic [15:0]   req_len_i,
    input  logic [8319:0] req_body_i,
    output logic          resp_valid_o,
    input  logic          resp_ready_i,
    output logic [15:0]   resp_len_o,
    output logic [8319:0] resp_body_o,
    input  logic          wr_ready_i,
    input  logic          wr_done_i,
    input  logic          wr_error_i,
    input  logic          wr_fifo_re_i,
    output logic          wr_fifo_empty_o,
    output logic          wr_start_o,
    output logic [30:0]   wr_addr_o,
    output logic [31:0]   wr_len_o,
    output logic [255:0]  wr_fifo_data_o,
    input  logic          rd_ready_i,
    input  logic          rd_done_i,
    input  logic          rd_error_i,
    input  logic          rd_fifo_we_i,
    output logic          rd_fifo_full_o,
    output logic          rd_start_o,
    output logic [30:0]   rd_addr_o,
    output logic [31:0]   rd_len_o,
    input  logic [255:0]  rd_fifo_data_i,
    output logic          coeff_req_valid_o,
    input  logic          coeff_req_ready_i,
    output logic [30:0]   coeff_req_addr_o,
    input  logic          coeff_rsp_valid_i,
    output logic          coeff_rsp_ready_o,
    input  logic [255:0]  coeff_rsp_data_i,
    input  logic          coeff_rsp_error_i
);
    logic service_resp_valid_w;
    logic [15:0] service_resp_len_w;
    logic [8319:0] service_resp_body_w;
    logic service_mem_valid_w, service_mem_ready_w, service_mem_write_w;
    logic service_mem_rsp_valid_w, service_mem_rsp_ready_w, service_mem_error_w;
    logic [30:0] service_mem_addr_w;
    logic [255:0] service_mem_data_w, service_mem_rsp_data_w;
    logic [31:0] service_mem_mask_w;
    logic service_claim_w;
    logic port_rsp_valid_w, port_rsp_ready_w, port_rsp_error_w, port_active_w;
    logic port_req_valid_w, port_req_ready_w;
    logic [255:0] port_rsp_data_w;

    // Match the RX-side response mailbox: allow the service one cycle to publish
    // its body before presenting a stable, back-pressured response to the driver.
    logic response_pending_r, response_valid_r;
    logic [15:0] response_len_r;
    logic [8319:0] response_body_r;
    always_ff @(posedge clk_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            response_pending_r <= 1'b0;
            response_valid_r <= 1'b0;
            response_len_r <= 16'd0;
        end else begin
            if (service_resp_valid_w && !response_pending_r) response_pending_r <= 1'b1;
            else if (response_pending_r) begin
                response_pending_r <= 1'b0;
                response_valid_r <= 1'b1;
                response_len_r <= service_resp_len_w;
                response_body_r <= service_resp_body_w;
            end
            if (response_valid_r && resp_ready_i) response_valid_r <= 1'b0;
        end
    end
    assign resp_valid_o = response_valid_r;
    assign resp_len_o = response_len_r;
    assign resp_body_o = response_body_r;

    op_service u_service (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .storage_idle_i(1'b1), .image_ready_i(1'b0),
        .req_valid_i(req_valid_i), .req_ready_o(req_ready_o), .resp_valid_o(service_resp_valid_w),
        .claim_o(service_claim_w), .mem_valid_o(service_mem_valid_w), .mem_ready_i(service_mem_ready_w),
        .mem_write_o(service_mem_write_w), .mem_rsp_valid_i(service_mem_rsp_valid_w),
        .mem_rsp_ready_o(service_mem_rsp_ready_w), .mem_rsp_error_i(service_mem_error_w),
        .image_base_i(31'd0), .image_slices_i(32'd0), .req_msg_i(req_msg_i), .req_id_i(req_id_i),
        .req_len_i(req_len_i), .req_body_i(req_body_i), .resp_len_o(service_resp_len_w),
        .resp_body_o(service_resp_body_w), .mem_addr_o(service_mem_addr_w),
        .mem_data_o(service_mem_data_w), .mem_mask_o(service_mem_mask_w),
        .mem_rsp_data_i(service_mem_rsp_data_w)
    );
    op_coeff_split u_split (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .req_valid_i(service_mem_valid_w),
        .req_ready_o(service_mem_ready_w), .req_write_i(service_mem_write_w),
        .req_addr_i(service_mem_addr_w), .rsp_valid_o(service_mem_rsp_valid_w),
        .rsp_ready_i(service_mem_rsp_ready_w), .rsp_data_o(service_mem_rsp_data_w),
        .rsp_error_o(service_mem_error_w), .ddr_req_valid_o(port_req_valid_w),
        .ddr_req_ready_i(port_req_ready_w), .ddr_rsp_valid_i(port_rsp_valid_w),
        .ddr_rsp_ready_o(port_rsp_ready_w), .ddr_rsp_data_i(port_rsp_data_w),
        .ddr_rsp_error_i(port_rsp_error_w), .coeff_req_valid_o(coeff_req_valid_o),
        .coeff_req_ready_i(coeff_req_ready_i), .coeff_req_addr_o(coeff_req_addr_o),
        .coeff_rsp_valid_i(coeff_rsp_valid_i), .coeff_rsp_ready_o(coeff_rsp_ready_o),
        .coeff_rsp_data_i(coeff_rsp_data_i), .coeff_rsp_error_i(coeff_rsp_error_i)
    );
    op_ddr_port u_port (
        .clk_i(clk_i), .rst_n_i(rst_n_i), .req_valid_i(port_req_valid_w),
        .req_ready_o(port_req_ready_w), .req_write_i(service_mem_write_w),
        .req_addr_i(service_mem_addr_w), .req_data_i(service_mem_data_w), .req_mask_i(service_mem_mask_w),
        .rsp_valid_o(port_rsp_valid_w), .rsp_ready_i(port_rsp_ready_w),
        .rsp_data_o(port_rsp_data_w), .rsp_error_o(port_rsp_error_w), .active_o(port_active_w),
        .wr_start_o(wr_start_o), .wr_addr_o(wr_addr_o), .wr_len_o(wr_len_o),
        .wr_ready_i(wr_ready_i), .wr_done_i(wr_done_i), .wr_error_i(wr_error_i),
        .wr_fifo_re_i(wr_fifo_re_i), .wr_fifo_empty_o(wr_fifo_empty_o), .wr_fifo_data_o(wr_fifo_data_o),
        .rd_start_o(rd_start_o), .rd_addr_o(rd_addr_o), .rd_len_o(rd_len_o),
        .rd_ready_i(rd_ready_i), .rd_done_i(rd_done_i), .rd_error_i(rd_error_i),
        .rd_fifo_we_i(rd_fifo_we_i), .rd_fifo_data_i(rd_fifo_data_i), .rd_fifo_full_o(rd_fifo_full_o)
    );
endmodule
