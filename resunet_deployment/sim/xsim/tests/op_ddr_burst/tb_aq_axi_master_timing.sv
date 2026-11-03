`timescale 1ns/1ps
// 【文件类型：.sv】复用AXI主机现有11项自检，验证新增W寄存级的跨突发和反压行为。
module tb_aq_axi_master_timing;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic test_done, test_pass;
    logic [31:0] err_count, slave_err;
    logic [15:0] slave_flags;
    logic [7:0] cur_test;
    logic stalled_r = 1'b0;
    logic [256:0] held_r;
    integer cycle = 0;
    integer csv;

    always #1.5 clk = ~clk;
    tb_aq_axi_master u_test (
        .clk(clk), .rst_n(rst_n), .test_done(test_done), .test_pass(test_pass),
        .err_count(err_count), .cur_test(cur_test), .slave_flags(slave_flags), .slave_err(slave_err)
    );

    initial begin
        csv = $fopen("sim_trace.csv", "w");
        $fdisplay(csv, "cycle,test,awvalid,awready,wvalid,wready,wlast,arvalid,arready,rvalid,rready,errors");
        $dumpfile("waveform.vcd");
        $dumpvars(0, clk, rst_n, cur_test, u_test.axi_awvalid, u_test.axi_awready,
            u_test.axi_wvalid, u_test.axi_wready, u_test.axi_wlast, u_test.axi_wdata,
            u_test.axi_arvalid, u_test.axi_arready, u_test.axi_rvalid, u_test.axi_rready);
        repeat (8) @(negedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        $fdisplay(csv, "%0d,%0d,%b,%b,%b,%b,%b,%b,%b,%b,%b,%0d", cycle, cur_test,
            u_test.axi_awvalid, u_test.axi_awready, u_test.axi_wvalid, u_test.axi_wready,
            u_test.axi_wlast, u_test.axi_arvalid, u_test.axi_arready,
            u_test.axi_rvalid, u_test.axi_rready, err_count);
        if (rst_n) begin
            if (stalled_r && {u_test.axi_wvalid, u_test.axi_wlast, u_test.axi_wdata} !== {1'b1, held_r}) begin
                $error("AXI W changed under backpressure cycle=%0d test=%0d", cycle, cur_test);
                $stop;
            end
            stalled_r = u_test.axi_wvalid && !u_test.axi_wready;
            held_r = {u_test.axi_wlast, u_test.axi_wdata};
            if (err_count !== 32'd0 || slave_err !== 32'd0) begin
                $error("AXI regression mismatch cycle=%0d test=%0d errors=%0d slave_errors=%0d", cycle, cur_test, err_count, slave_err);
                $stop;
            end
            if (test_done) begin
                if (test_pass !== 1'b1 || cur_test !== 8'd10) begin
                    $error("AXI regression did not complete all 11 cases");
                    $stop;
                end
                $fclose(csv);
                $display("[TB PASSED] 全部数据验证一致 AXI cases=11 cycles=%0d", cycle);
                $finish;
            end
        end
    end

    initial begin
        repeat (1000000) @(posedge clk);
        $fatal(1, "Simulation Timeout");
    end
endmodule
