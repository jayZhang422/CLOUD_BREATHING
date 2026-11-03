`timescale 1ns/1ps
// 本轮定向自校验：确认 tumor DDR 参数窗口不再被片上 ROM 截获。
module tb_coeff_split_ddr;
    logic clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    logic req_valid, req_ready, req_write;
    logic [30:0] req_addr;
    logic rsp_valid, rsp_ready = 1'b1;
    logic [255:0] rsp_data;
    logic rsp_error;
    logic ddr_req_valid, ddr_req_ready = 1'b1;
    logic ddr_rsp_valid = 1'b0, ddr_rsp_ready;
    logic [255:0] ddr_rsp_data = 256'd0;
    logic ddr_rsp_error = 1'b0;
    logic coeff_req_valid, coeff_req_ready = 1'b1;
    logic [30:0] coeff_req_addr;
    logic coeff_rsp_valid = 1'b0, coeff_rsp_ready;
    logic [255:0] coeff_rsp_data = 256'd0;
    logic coeff_rsp_error = 1'b0;
    int checks = 0;

    op_coeff_split dut (
        .clk_i(clk), .rst_n_i(rst_n), .req_valid_i(req_valid), .req_ready_o(req_ready),
        .req_write_i(req_write), .req_addr_i(req_addr), .rsp_valid_o(rsp_valid),
        .rsp_ready_i(rsp_ready), .rsp_data_o(rsp_data), .rsp_error_o(rsp_error),
        .ddr_req_valid_o(ddr_req_valid), .ddr_req_ready_i(ddr_req_ready),
        .ddr_rsp_valid_i(ddr_rsp_valid), .ddr_rsp_ready_o(ddr_rsp_ready),
        .ddr_rsp_data_i(ddr_rsp_data), .ddr_rsp_error_i(ddr_rsp_error),
        .coeff_req_valid_o(coeff_req_valid), .coeff_req_ready_i(coeff_req_ready),
        .coeff_req_addr_o(coeff_req_addr), .coeff_rsp_valid_i(coeff_rsp_valid),
        .coeff_rsp_ready_o(coeff_rsp_ready), .coeff_rsp_data_i(coeff_rsp_data),
        .coeff_rsp_error_i(coeff_rsp_error)
    );

    task automatic read_ddr(input logic [30:0] address, input logic [255:0] expected);
        @(negedge clk); req_addr = address; req_write = 1'b0; req_valid = 1'b1; #1;
        if (req_ready !== 1'b1 || ddr_req_valid !== 1'b1 || coeff_req_valid !== 1'b0)
            $fatal(1, "DDR route failed addr=%h", address);
        @(posedge clk);
        req_valid = 1'b0;
        repeat (2) @(posedge clk);
        ddr_rsp_data = expected; ddr_rsp_valid = 1'b1;
        #1;
        if (ddr_rsp_ready !== 1'b1 || rsp_valid !== 1'b1 || rsp_error !== 1'b0 || rsp_data !== expected)
            $fatal(1, "DDR response not accepted");
        @(posedge clk);
        ddr_rsp_valid = 1'b0;
        @(posedge clk);
        @(posedge clk); checks++;
    endtask

    task automatic read_rom;
        @(negedge clk); req_addr = 31'h00100000; req_write = 1'b0; req_valid = 1'b1; #1;
        if (req_ready !== 1'b1 || coeff_req_valid !== 1'b1 || ddr_req_valid !== 1'b0 ||
            coeff_req_addr !== 31'h00100000) $fatal(1, "ROM route failed");
        @(posedge clk);
        req_valid = 1'b0;
        repeat (1) @(posedge clk);
        coeff_rsp_data = 256'h55; coeff_rsp_valid = 1'b1;
        #1;
        if (coeff_rsp_ready !== 1'b1 || rsp_valid !== 1'b1 || rsp_error !== 1'b0 || rsp_data !== 256'h55)
            $fatal(1, "ROM response not accepted");
        @(posedge clk);
        coeff_rsp_valid = 1'b0;
        @(posedge clk); checks++;
    endtask

    initial begin
        req_valid = 1'b0; req_write = 1'b0; req_addr = 31'd0;
        repeat (3) @(posedge clk); rst_n = 1'b1;
        read_ddr(31'h08000000, 256'h0123456789abcdef);
        read_ddr(31'h081ffff0, 256'hdeadbeef);
        read_rom();
        @(negedge clk); req_addr = 31'h00100000; req_write = 1'b1; req_valid = 1'b1; #1;
        if (req_ready !== 1'b1 || rsp_valid !== 1'b0) $fatal(1, "ROM write was not accepted for rejection");
        @(posedge clk);
        req_valid = 1'b0;
        #1;
        if (rsp_valid !== 1'b1 || rsp_error !== 1'b1 || ddr_req_valid !== 1'b0)
            $fatal(1, "ROM write was not rejected");
        @(posedge clk);
        $display("[TB PASSED] coeff_split DDR/ROM routing checks=%0d", checks);
        $finish;
    end
endmodule
