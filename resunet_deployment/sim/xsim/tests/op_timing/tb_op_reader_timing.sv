`timescale 1ns/1ps
`include "reader_counts.svh"
// 【文件类型：.sv】读取器自校验：三切片钳位、cache命中、反压、错误及复位。
module tb_op_reader_timing;
    localparam string VECTOR_DIR = "sim/xsim/tests/op_timing/vectors/";
    logic clk = 1'b0, rst_n = 1'b0, clear = 1'b0;
    always #1.5 clk = !clk;
    logic req_valid = 1'b0, req_ready, rsp_valid, rsp_ready = 1'b0, rsp_error;
    logic [1:0] mode = 2'd0;
    logic [30:0] base = 31'h10000000, mem_addr;
    logic [31:0] pixel = 32'd0, slices = 32'd3, center = 32'd1;
    logic [511:0] data;
    logic mem_valid, mem_ready, mem_rsp_valid, mem_rsp_ready;
    logic [255:0] mem_data_r;
    logic enabled = 1'b0, pending_r = 1'b0, inject_error = 1'b0;
    logic [130:0] stimulus [0:`READER_CASES-1];
    logic [520:0] golden [0:`READER_CASES-1];
    logic [520:0] actual;
    logic stalled_r = 1'b0, out_stalled_r = 1'b0;
    logic [30:0] held_addr_r;
    logic [512:0] held_output_r;
    int cycle = 0, delay_r = 0, case_id = -1, beats = 0, total_beats = 0;
    integer csv;
    assign mem_ready = enabled && !pending_r && cycle % 7 < 3;
    assign mem_rsp_valid = pending_r && delay_r == 0;
    assign actual = {8'(beats),rsp_error,data};
    op_feature_reader dut (
        .clk_i(clk), .rst_n_i(rst_n), .clear_i(clear),
        .req_valid_i(req_valid), .req_ready_o(req_ready), .req_mode_i(mode),
        .req_addr_i(base), .req_pixel_i(pixel), .slices_i(slices), .center_i(center),
        .rsp_valid_o(rsp_valid), .rsp_ready_i(rsp_ready), .rsp_error_o(rsp_error), .rsp_data_o(data),
        .mem_valid_o(mem_valid), .mem_ready_i(mem_ready), .mem_addr_o(mem_addr),
        .mem_rsp_valid_i(mem_rsp_valid), .mem_rsp_ready_o(mem_rsp_ready),
        .mem_rsp_error_i(inject_error), .mem_rsp_data_i(mem_data_r)
    );
    function automatic logic [7:0] memory_byte(input logic [31:0] address);
        memory_byte = address[7:0] ^ address[15:8] ^ address[23:16] ^ address[31:24];
    endfunction
    always @(posedge clk) begin
        cycle = cycle + 1;
        $fdisplay(csv,"%0d,%0d,%0d,%b,%b,%b,%b,%h,%b,%b,%b,%b,%h",cycle,case_id,dut.state_r,req_valid,req_ready,mem_valid,mem_ready,mem_addr,mem_rsp_valid,mem_rsp_ready,rsp_valid,rsp_ready,data);
        if (!rst_n) begin
            pending_r <= 1'b0; stalled_r <= 1'b0; out_stalled_r <= 1'b0;
        end else begin
            if (stalled_r && (mem_valid !== 1'b1 || mem_addr !== held_addr_r)) begin
                $error("reader request changed cycle=%0d case=%0d expected=%h actual=%h",cycle,case_id,held_addr_r,mem_addr); $stop;
            end
            if (out_stalled_r && (rsp_valid !== 1'b1 || {rsp_error,data} !== held_output_r)) begin
                $error("reader response changed cycle=%0d case=%0d",cycle,case_id); $stop;
            end
            stalled_r <= mem_valid && !mem_ready; held_addr_r <= mem_addr;
            out_stalled_r <= rsp_valid && !rsp_ready; held_output_r <= {rsp_error,data};
            if (mem_valid && mem_ready) begin
                for (int b=0; b<32; b++) mem_data_r[b*8 +: 8] <= memory_byte({1'b0,mem_addr} + 32'(b));
                pending_r <= 1'b1; delay_r <= 1 + cycle % 5;
                beats = beats + 1; total_beats = total_beats + 1;
            end else if (mem_rsp_valid && mem_rsp_ready) pending_r <= 1'b0;
            else if (pending_r && delay_r > 0) delay_r <= delay_r - 1;
        end
    end
    initial begin
        csv = $fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,case,state,req_valid,req_ready,mem_valid,mem_ready,mem_addr,mem_rsp_valid,mem_rsp_ready,rsp_valid,rsp_ready,data");
        $dumpfile("waveform.vcd");
        $dumpvars(0,rst_n,clear,req_valid,req_ready,mem_valid,mem_ready,mem_addr,mem_rsp_valid,mem_rsp_ready,rsp_valid,rsp_ready,data);
        repeat(100000) @(posedge clk);
        $fatal(1,"Simulation Timeout cycle=%0d case=%0d",cycle,case_id);
    end
    initial begin
        $readmemh({VECTOR_DIR,"reader_stimulus.hex"},stimulus);
        $readmemh({VECTOR_DIR,"reader_golden.hex"},golden);
        repeat(5) @(negedge clk); rst_n=1'b1;
        // 在DDR请求反压期间复位，旧请求必须撤销。
        req_valid=1'b1;
        @(negedge clk); req_valid=1'b0;
        wait(mem_valid === 1'b1);
        repeat(3) @(negedge clk); rst_n=1'b0;
        repeat(2) @(negedge clk);
        if (mem_valid !== 1'b0 || rsp_valid !== 1'b0 || req_ready !== 1'b1) begin
            $error("reader reset did not cancel cycle=%0d",cycle); $stop;
        end
        rst_n=1'b1; enabled=1'b1;
        for (int c=0; c<`READER_CASES; c++) begin
            @(negedge clk); case_id=c; beats=0; rsp_ready=1'b0;
            {inject_error,clear,center,slices,pixel,base,mode}=stimulus[c];
            @(negedge clk); clear=1'b0; req_valid=1'b1;
            do @(posedge clk); while (req_ready !== 1'b1);
            @(negedge clk); req_valid=1'b0;
            do begin @(posedge clk); #0.1; end while (rsp_valid !== 1'b1);
            if (actual !== golden[c]) begin
                $error("reader mismatch cycle=%0d case=%0d expected=%h actual=%h",cycle,c,golden[c],actual); $stop;
            end
            repeat(4) @(negedge clk);
            rsp_ready=1'b1;
            @(negedge clk); rsp_ready=1'b0;
        end
        $fclose(csv);
        $display("[TB PASSED] 全部数据验证一致 reader_cases=%0d beats=%0d cycles=%0d",`READER_CASES,total_beats,cycle);
        $finish;
    end
endmodule
