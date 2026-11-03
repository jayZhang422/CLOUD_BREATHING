`timescale 1ns/1ps
// 【文件类型：.sv】op=11 融合 DW3/DW5+ElementAdd 自校验。
// 单组7x7脉冲输入，两路DW权重全为1，mix两路乘数均为1；
// 3x3与5x5支持域不同，用输出票面检查窗口对齐和反压保持。
module tb_op_fused_dw_add;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #4 clk = ~clk;

    logic cfg_valid = 1'b0, raw = 1'b0, int16 = 1'b0, add_last = 1'b1;
    logic weights_valid = 1'b0, params_valid = 1'b0, start_valid = 1'b0;
    logic in_valid = 1'b0, in_b_valid = 1'b0, rd_ready = 1'b0, rsp_valid = 1'b0;
    logic out_ready = 1'b1;
    logic [7:0] op = 8'd11;
    logic [9:0] cin = 10'd16, cout = 10'd16, width = 10'd7, height = 10'd7;
    logic [18:0] pixels = 19'd49;
    logic [5:0] groups = 6'd1, shift = 6'd0, add_group = 6'd0;
    logic [7:0] clamp_min = 8'd0, clamp_max = 8'd127;
    logic [2047:0] add_params = 2048'd0;
    logic [511:0] load_data = 512'd0, in_data = 512'd0, in_b_data = 512'd0;
    logic [127:0] rsp_data = 128'd0;
    logic cfg_ready, weights_ready, params_ready, start_ready, in_ready, in_b_ready;
    logic rd_valid, rd_source, rsp_ready, out_valid, out_last, done;
    logic [31:0] rd_addr;
    logic [3199:0] out_data;
    logic [127:0] out_mac;
    logic [18:0] out_pixel;
    logic [6:0] out_group;
    logic [3:0] out_mask;
    integer cycle = 0;
    integer csv;
    integer output_count = 0;
    logic stalled_last = 1'b0;
    logic [3199:0] stalled_data;
    logic stalled_last_flag;

    op_core_bank dut (
        .clk_i(clk), .rst_n_i(rst_n), .cfg_valid_i(cfg_valid), .cfg_ready_o(cfg_ready),
        .raw_i(raw), .int16_i(int16), .add_last_i(add_last),
        .weights_valid_i(weights_valid), .weights_ready_o(weights_ready),
        .params_valid_i(params_valid), .params_ready_o(params_ready),
        .start_valid_i(start_valid), .start_ready_o(start_ready),
        .in_valid_i(in_valid), .in_ready_o(in_ready),
        .in_b_valid_i(in_b_valid), .in_b_ready_o(in_b_ready),
        .rd_valid_o(rd_valid), .rd_ready_i(rd_ready), .rd_source_o(rd_source),
        .rsp_valid_i(rsp_valid), .rsp_ready_o(rsp_ready),
        .out_valid_o(out_valid), .out_ready_i(out_ready), .out_last_o(out_last), .done_o(done),
        .op_i(op), .cin_i(cin), .cout_i(cout), .pixels_i(pixels),
        .width_i(width), .height_i(height), .groups_i(groups), .words_b_i(32'd0),
        .shift_i(shift), .clamp_min_i(clamp_min), .clamp_max_i(clamp_max),
        .add_group_i(add_group), .add_params_i(add_params), .load_data_i(load_data),
        .in_data_i(in_data), .in_b_data_i(in_b_data), .rd_addr_o(rd_addr),
        .rsp_data_i(rsp_data), .out_data_o(out_data), .out_mac_o(out_mac),
        .out_pixel_o(out_pixel), .out_group_o(out_group), .out_mask_o(out_mask)
    );

    initial begin
        csv = $fopen("sim_trace.csv", "w");
        $fdisplay(csv, "cycle,cfg_valid,cfg_ready,weights_valid,weights_ready,in_valid,in_ready,out_valid,out_ready,out_data_p16,out_last,done,dw3_valid,dw3_mac0,align_valid,align_mac0,dw5_valid,dw5_mac0,add_a_ready,add_b_ready");
        $dumpfile("waveform.vcd");
        $dumpvars(0, clk, rst_n, cfg_valid, cfg_ready, weights_valid, weights_ready,
            in_valid, in_ready, out_valid, out_ready, out_last, done);
    end

    always @(posedge clk) begin
        cycle = cycle + 1;
        $fdisplay(csv, "%0d,%b,%b,%b,%b,%b,%b,%b,%b,%032h,%b,%b,%b,%08h,%b,%08h,%b,%08h,%b,%b", cycle,
            cfg_valid,cfg_ready,weights_valid,weights_ready,in_valid,in_ready,
            out_valid,out_ready,out_data[127:0],out_last,done,dut.valid_w[8],
            dut.data_w[8][31:0],dut.fused_dw3_align_valid_r,
            dut.fused_dw3_align_data_r[31:0],dut.valid_w[9],dut.data_w[9][31:0],
            dut.in_ready_w[6],dut.in_b_ready_o);
        $fflush(csv);
        if (rst_n && stalled_last &&
            (out_valid !== 1'b1 || out_data !== stalled_data || out_last !== stalled_last_flag)) begin
            $error("output changed under backpressure cycle=%0d", cycle);
            $stop;
        end
        stalled_last = rst_n && out_valid && !out_ready;
        if (stalled_last) begin
            stalled_data = out_data;
            stalled_last_flag = out_last;
        end
        if (rst_n && out_valid && out_ready) begin
            if (output_count >= 49 || out_data[127:0] !== {16{expected_pixel(output_count)}}) begin
                $error("pixel mismatch cycle=%0d index=%0d expected=%h data=%h a=%h b=%h",
                    cycle, output_count, expected_pixel(output_count), out_data[127:0],
                    dut.fused_dw3_align_data_r[31:0], dut.data_w[9][31:0]);
                $stop;
            end
            if (out_last !== (output_count == 48)) begin
                $error("last marker mismatch output=%0d last=%b", output_count, out_last);
                $stop;
            end
            output_count = output_count + 1;
        end
    end

    task automatic send_weights;
        integer n;
        begin
            for (n = 0; n < 34; n = n + 1) begin
                @(negedge clk);
                weights_valid = 1'b1;
                // 填满16路权重，覆盖两种DW的全部tap。
                load_data[127:0] = {16{8'd1}};
                while (weights_ready !== 1'b1) @(negedge clk);
                @(negedge clk);
                weights_valid = 1'b0;
            end
        end
    endtask

    initial begin : stimulus
        repeat (8) @(negedge clk);
        rst_n = 1'b1;
        for (integer p = 0; p < 16; p = p + 1) begin
            add_params[p*128 +: 22] = 22'd1;
            add_params[p*128 + 32 +: 22] = 22'd1;
        end
        @(negedge clk);
        cfg_valid = 1'b1;
        while (cfg_ready !== 1'b1) @(negedge clk);
        @(negedge clk);
        cfg_valid = 1'b0;
        send_weights();
        // op=11 的 Add 参数在引擎中装载后单独锁存一次配置；
        // 这一步复现真实 LOAD_ADD -> CONFIGURE 握手。
        @(negedge clk);
        cfg_valid = 1'b1;
        while (cfg_ready !== 1'b1) @(negedge clk);
        @(negedge clk);
        cfg_valid = 1'b0;
        @(negedge clk);
        for (integer y = 0; y < 7; y = y + 1)
            for (integer x = 0; x < 7; x = x + 1)
                send_pixel((x == 3 && y == 3) ? 8'd1 : 8'd0);
        repeat (4000) begin
            @(negedge clk);
            if (done === 1'b1) begin
                if (output_count != 49) begin
                    $error("expected 49 outputs, observed %0d", output_count);
                    $stop;
                end
                if (out_valid !== 1'b0) begin
                    $error("done overlapped unconsumed output cycle=%0d", cycle);
                    $stop;
                end
                $fclose(csv);
                $display("[TB PASSED] fused DW3/DW5+Add output exact cycle=%0d", cycle);
                $finish;
            end
        end
        $fatal(1, "Simulation Timeout cycle=%0d", cycle);
    end

    task automatic send_pixel(input logic [7:0] value);
        begin
            @(negedge clk);
            in_data[127:0] = {16{value}};
            in_valid = 1'b1;
            do @(posedge clk); while (in_ready !== 1'b1);
            @(negedge clk);
            in_valid = 1'b0;
        end
    endtask

    function automatic logic [7:0] expected_pixel(input integer index);
        integer row;
        integer col;
        begin
            row = index / 7;
            col = index % 7;
            if (row >= 2 && row <= 4 && col >= 2 && col <= 4)
                expected_pixel = 8'd2;
            else if (row >= 1 && row <= 5 && col >= 1 && col <= 5)
                expected_pixel = 8'd1;
            else
                expected_pixel = 8'd0;
        end
    endfunction

    always @(negedge clk) begin
        if (rst_n) out_ready = (cycle % 4 != 1);
    end
endmodule
