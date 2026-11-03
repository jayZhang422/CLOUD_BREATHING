`timescale 1ns/1ps
module tb_op_fused_residual;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #4 clk = ~clk;

    logic run_valid = 1'b0;
    logic check_valid = 1'b0;
    logic abort = 1'b0;
    logic mem_ready = 1'b0;
    logic mem_rsp_valid = 1'b0;
    logic mem_rsp_error = 1'b0;
    logic [511:0] descriptor = 512'd0;
    logic [255:0] mem_rsp_data = 256'd0;
    logic [7:0] output_bytes [0:527];
    logic [255:0] rsp_buffer;
    logic rsp_pending = 1'b0;
    logic [31:0] cycle = 32'd0;
    integer csv;
    logic check_done, run_ready, descriptor_ok, busy, done, error, aborted;
    logic mem_valid, mem_write, mem_rsp_ready;
    logic [31:0] result_bytes, mac_bytes, candidate_bytes, candidate_mac_bytes;
    logic [30:0] mem_addr;
    logic [255:0] mem_data;
    logic [31:0] mem_mask;

    op_engine dut (
        .clk_i(clk), .rst_n_i(rst_n), .run_valid_i(run_valid),
        .check_valid_i(check_valid), .check_done_o(check_done), .run_ready_o(run_ready),
        .descriptor_ok_o(descriptor_ok), .abort_i(abort), .busy_o(busy), .done_o(done),
        .error_o(error), .aborted_o(aborted), .mem_valid_o(mem_valid), .mem_ready_i(mem_ready),
        .mem_write_o(mem_write), .mem_rsp_valid_i(mem_rsp_valid), .mem_rsp_ready_o(mem_rsp_ready),
        .mem_rsp_error_i(mem_rsp_error), .descriptor_i(descriptor),
        .result_bytes_o(result_bytes), .mac_bytes_o(mac_bytes),
        .candidate_bytes_o(candidate_bytes), .candidate_mac_bytes_o(candidate_mac_bytes),
        .mem_addr_o(mem_addr), .mem_data_o(mem_data), .mem_mask_o(mem_mask),
        .mem_rsp_data_i(mem_rsp_data)
    );

    function automatic logic [7:0] model_byte(input logic [30:0] address);
        logic [31:0] offset;
        begin
            if ((address >= 31'h00200000 && address < 31'h00200210) ||
                (address >= 31'h00210000 && address < 31'h00210210))
                model_byte = 8'd1;
            else if ((address >= 31'h08000000 && address < 31'h08000200) ||
                     (address >= 31'h08000400 && address < 31'h08000600))
                model_byte = 8'd1;
            else if (address >= 31'h08000800 && address < 31'h08000A00) begin
                offset = address - 31'h08000800;
                case (offset[3:0])
                    4'd0, 4'd4: model_byte = 8'd1;
                    default: model_byte = 8'd0;
                endcase
            end else model_byte = 8'd0;
        end
    endfunction

    function automatic logic [255:0] model_line(input logic [30:0] address);
        logic [255:0] value;
        begin
            for (integer b = 0; b < 32; b++) value[b*8 +: 8] = model_byte(address + b);
            model_line = value;
        end
    endfunction

    always @(posedge clk) begin
        cycle <= cycle + 32'd1;
        if (!rst_n) begin
            rsp_pending <= 1'b0;
            mem_rsp_valid <= 1'b0;
            mem_rsp_data <= 256'd0;
        end else begin
            mem_ready <= (cycle[1:0] != 2'd1);
            if (mem_rsp_valid && mem_rsp_ready) begin
                mem_rsp_valid <= 1'b0;
                rsp_pending <= 1'b0;
            end
            if (rsp_pending && !mem_rsp_valid) mem_rsp_valid <= 1'b1;
            if (mem_valid && mem_ready) begin
                if (mem_write) begin
                    for (integer b = 0; b < 32; b++) begin
                        if (mem_mask[b] && mem_addr + b >= 31'h00220000 &&
                            mem_addr + b < 31'h00220220)
                            output_bytes[mem_addr + b - 31'h00220000] <= mem_data[b*8 +: 8];
                    end
                end else rsp_buffer <= model_line(mem_addr);
                rsp_pending <= 1'b1;
                mem_rsp_data <= mem_write ? 256'd0 : model_line(mem_addr);
            end
        end
    end

    initial begin
        csv = $fopen("sim_trace.csv", "w");
        $fdisplay(csv, "cycle,state,op,mem_valid,mem_write,mem_addr,reader_source,bank_rd_valid,bank_rd_addr,bank_rd_source,bank_out_valid,bank_out_ready,done,error,phase,add_valid,add_part,add_pixel,add_done,pw_state,skip_state,pw_valid,skip_valid,add_a_ready,add_b_ready,reader_state,reader_req,reader_addr,reader_mode,reader_rsp,reader_rsp_ready,bank_rsp_ready,pw_rsp_valid,pw_rsp_ready,skip_rsp_valid,skip_rsp_ready");
        $dumpfile("waveform.vcd");
        $dumpvars(0, clk, rst_n, run_valid, check_valid, check_done, run_ready,
            mem_valid, mem_write, mem_addr, mem_ready, mem_rsp_valid, done, error);
        for (integer b = 0; b < 528; b++) output_bytes[b] = 8'd0;
        repeat (6) @(negedge clk);
        rst_n = 1'b1;
        descriptor = 512'd0;
        descriptor[7:0] = 8'd12;
        descriptor[47:32] = 16'd33;
        descriptor[63:48] = 16'd1;
        descriptor[79:64] = 16'd1;
        descriptor[95:88] = 8'd0;
        descriptor[103:96] = 8'd127;
        descriptor[159:128] = 32'h00200000;
        descriptor[191:160] = 32'h00210000;
        descriptor[223:192] = 32'h00220000;
        descriptor[255:224] = 32'h08000400;
        descriptor[287:256] = 32'h08000000;
        descriptor[319:288] = 32'h08000800;
        descriptor[431:416] = 16'd16;
        descriptor[447:432] = 16'd16;
        descriptor[463:448] = 16'd3;

        @(negedge clk);
        check_valid = 1'b1;
        do @(negedge clk); while (check_done !== 1'b1);
        check_valid = 1'b0;
        if (descriptor_ok !== 1'b1 || candidate_bytes !== 32'd528 ||
            candidate_mac_bytes !== 32'd0 || dut.checked_weights_w !== 32'd8 ||
            dut.checked_params_w !== 32'd4) begin
            $error("opcode12 descriptor mismatch ok=%b bytes=%0d mac=%0d weights=%0d params=%0d",
                descriptor_ok, candidate_bytes, candidate_mac_bytes,
                dut.checked_weights_w, dut.checked_params_w);
            $stop;
        end

        @(negedge clk);
        run_valid = 1'b1;
        do @(posedge clk); while (run_ready !== 1'b1);
        @(negedge clk);
        run_valid = 1'b0;
        repeat (30000) begin
            @(negedge clk);
            if (done === 1'b1) begin
                if (error !== 1'b0 || aborted !== 1'b0 || result_bytes !== 32'd528 || mac_bytes !== 32'd0) begin
                    $error("opcode12 run status error=%b aborted=%b result=%0d mac=%0d",
                        error, aborted, result_bytes, mac_bytes);
                    $stop;
                end
                for (integer b = 0; b < 528; b++) begin
                    if (output_bytes[b] !== 8'd19) begin
                        $error("opcode12 result mismatch byte=%0d expected=32 actual=%0d", b, output_bytes[b]);
                        $stop;
                    end
                end
                $fclose(csv);
                $display("[TB PASSED] opcode12 project/skip raw PW + residual Add, 33 pixels x CinB3/Cout16, exact cycles=%0d", cycle);
                $finish;
            end
            $fdisplay(csv, "%0d,%0d,%0d,%b,%b,%08h,%b,%b,%08h,%b,%b,%b,%b,%0d,%b,%0d,%0d,%b,%0d,%0d,%b,%b,%b,%b,%0d,%b,%08h,%0d,%b,%b,%b,%b,%b,%b,%b,%b", cycle,
                dut.state_r, dut.op_w, mem_valid, mem_write, mem_addr, dut.reader_source_r,
                dut.bank_rd_valid_w, dut.bank_rd_addr_w, dut.bank_rd_source_w, dut.bank_out_valid_w,
                dut.bank_out_ready_w, done, error, dut.u_bank.p12_phase_r,
                dut.u_bank.p12_add_valid_r, dut.u_bank.p12_add_part_r,
                dut.u_bank.p12_add_pixel_r, dut.u_bank.done_w[6],
                dut.u_bank.u_pw_shared.project.state_r, dut.u_bank.u_pw_shared.skip.state_r,
                dut.u_bank.p12_pw_valid_w, dut.u_bank.p12_pw_skip_valid_w,
                dut.u_bank.in_ready_w[6], dut.u_bank.in_b_ready_o,
                dut.u_reader.state_r, dut.reader_req_w, dut.reader_addr_w,
                dut.reader_mode_w, dut.reader_rsp_w, dut.reader_rsp_ready_w,
                dut.bank_rsp_ready_w, dut.u_bank.u_pw_shared.project.io_rsp_i_valid,
                dut.u_bank.u_pw_shared.project.io_rsp_i_ready,
                dut.u_bank.u_pw_shared.skip.io_rsp_i_valid, dut.u_bank.u_pw_shared.skip.io_rsp_i_ready);
        end
        $fatal(1, "Simulation Timeout cycle=%0d state=%0d", cycle, dut.state_r);
    end
endmodule
