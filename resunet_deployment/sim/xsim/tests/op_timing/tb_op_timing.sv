`timescale 1ns/1ps
`include "vector_counts.svh"
// 【文件类型：.sv】配置检查与写回器自校验；Golden由Python生成。
module tb_op_timing;
    localparam string VECTOR_DIR = "sim/xsim/tests/op_timing/vectors/";
    logic clk = 1'b0, check_rst_n = 1'b0, writer_rst_n = 1'b0;
    always #1.5 clk = !clk;
    logic check_req = 1'b0, check_done, check_ok;
    logic [511:0] descriptor = 512'd0;
    logic [31:0] q_bytes, m_bytes, pixels, inputs, weight_words, param_words, words_b;
    logic [224:0] checked_w;
    assign checked_w = {check_ok,q_bytes,m_bytes,pixels,inputs,weight_words,param_words,words_b};
    op_descriptor_check u_check (
        .clk_i(clk), .rst_n_i(check_rst_n), .req_valid_i(check_req), .descriptor_i(descriptor),
        .done_o(check_done), .ok_o(check_ok), .result_bytes_o(q_bytes), .mac_bytes_o(m_bytes),
        .pixels_o(pixels), .inputs_o(inputs), .weight_words_o(weight_words),
        .param_words_o(param_words), .words_b_o(words_b)
    );
    logic req_valid = 1'b0, req_ready, done, error;
    logic [30:0] req_addr = 31'd0, mem_addr;
    logic [8:0] req_bytes = 9'd0;
    logic [3199:0] req_data = 3200'd0;
    logic mem_valid, mem_ready, rsp_valid, rsp_ready, rsp_error = 1'b0;
    logic [255:0] mem_data;
    logic [31:0] mem_mask;
    logic enable_memory = 1'b0, pending_r = 1'b0;
    int delay_r = 0, cycle = 0, beat_count = 0, job_beats = 0;
    int descriptor_case = -1, writer_case = -1;
    logic expected_error = 1'b0;
    assign mem_ready = enable_memory && !pending_r && cycle % 7 != 1;
    assign rsp_valid = pending_r && delay_r == 0;
    op_feature_writer u_writer (
        .clk_i(clk), .rst_n_i(writer_rst_n), .req_valid_i(req_valid), .req_ready_o(req_ready),
        .req_addr_i(req_addr), .req_data_i(req_data), .req_bytes_i(req_bytes),
        .done_o(done), .error_o(error), .mem_valid_o(mem_valid), .mem_ready_i(mem_ready),
        .mem_addr_o(mem_addr), .mem_data_o(mem_data), .mem_mask_o(mem_mask),
        .mem_rsp_valid_i(rsp_valid), .mem_rsp_ready_o(rsp_ready), .mem_rsp_error_i(rsp_error)
    );
    logic [511:0] descriptor_mem [0:`DESCRIPTOR_CASES-1];
    logic [224:0] descriptor_golden [0:`DESCRIPTOR_CASES-1];
    logic [3240:0] writer_stimulus [0:`WRITER_CASES-1];
    logic [318:0] writer_golden [0:`WRITER_BEATS-1];
    logic [318:0] transaction_w, stalled_transaction_r;
    logic stalled_r = 1'b0, descriptors_passed = 1'b0, writers_passed = 1'b0;
    assign transaction_w = {mem_addr,mem_mask,mem_data};
    integer csv;

    initial begin
        $readmemh({VECTOR_DIR,"descriptors.hex"},descriptor_mem);
        $readmemh({VECTOR_DIR,"descriptor_golden.hex"},descriptor_golden);
        $readmemh({VECTOR_DIR,"writer_stimulus.hex"},writer_stimulus);
        $readmemh({VECTOR_DIR,"writer_golden.hex"},writer_golden);
        csv = $fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,descriptor_case,check_req,check_done,check_ok,writer_case,req_valid,req_ready,mem_valid,mem_ready,rsp_valid,rsp_ready,done,error,beat_count,addr,mask");
        $dumpfile("waveform.vcd");
        $dumpvars(0,check_rst_n,writer_rst_n,check_req,check_done,check_ok,descriptor_case,writer_case,req_valid,req_ready,mem_valid,mem_ready,rsp_valid,rsp_ready,done,error,mem_addr,mem_mask);
        repeat(1000000) @(posedge clk);
        $fatal(1,"Simulation Timeout cycle=%0d descriptor=%0d writer=%0d",cycle,descriptor_case,writer_case);
    end
    always @(posedge clk) begin
        cycle = cycle + 1;
        $fdisplay(csv,"%0d,%0d,%b,%b,%b,%0d,%b,%b,%b,%b,%b,%b,%b,%b,%0d,%h,%h",cycle,descriptor_case,check_req,check_done,check_ok,writer_case,req_valid,req_ready,mem_valid,mem_ready,rsp_valid,rsp_ready,done,error,beat_count,mem_addr,mem_mask);
        if (!writer_rst_n) begin
            pending_r <= 1'b0; delay_r <= 0; stalled_r <= 1'b0;
        end else begin
            if (stalled_r && (mem_valid !== 1'b1 || transaction_w !== stalled_transaction_r)) begin
                $error("writer backpressure changed cycle=%0d case=%0d",cycle,writer_case); $stop;
            end
            stalled_r <= mem_valid && !mem_ready;
            stalled_transaction_r <= transaction_w;
            if (mem_valid && mem_ready) begin
                if (beat_count >= `WRITER_BEATS) begin $error("extra write beat cycle=%0d",cycle); $stop; end
                if (transaction_w !== writer_golden[beat_count]) begin
                    $error("write mismatch cycle=%0d case=%0d beat=%0d expected=%h actual=%h",cycle,writer_case,beat_count,writer_golden[beat_count],transaction_w); $stop;
                end
                beat_count = beat_count + 1;
                rsp_error <= expected_error && job_beats == 0;
                job_beats = job_beats + 1;
                pending_r <= 1'b1; delay_r <= 1 + cycle % 5;
            end else if (rsp_valid && rsp_ready) pending_r <= 1'b0;
            else if (pending_r && delay_r > 0) delay_r <= delay_r - 1;
        end
    end
    initial begin : check_descriptors
        repeat(5) @(negedge clk); check_rst_n = 1'b1;
        // 先复位一次未完成检查，确保旧结果不会被当成新任务结果。
        descriptor = descriptor_mem[0]; check_req = 1'b1;
        repeat(3) @(negedge clk); check_rst_n = 1'b0; check_req = 1'b0;
        repeat(2) @(negedge clk);
        if (check_done !== 1'b0 || check_ok !== 1'b0) begin $error("checker reset did not cancel"); $stop; end
        check_rst_n = 1'b1;
        for (int c=0; c<`DESCRIPTOR_CASES; c++) begin
            @(negedge clk); descriptor_case = c; descriptor = descriptor_mem[c]; check_req = 1'b1;
            @(posedge clk); #0.1;
            // 输入可以变化；检查必须使用已捕获的描述。
            @(negedge clk); descriptor = ~descriptor_mem[c];
            do begin @(posedge clk); #0.1; end while (check_done !== 1'b1);
            if (checked_w !== descriptor_golden[c]) begin
                $error("descriptor mismatch cycle=%0d case=%0d expected=%h actual=%h",cycle,c,descriptor_golden[c],checked_w); $stop;
            end
            repeat(3) begin
                @(posedge clk); #0.1;
                if (check_done !== 1'b1 || checked_w !== descriptor_golden[c]) begin
                    $error("descriptor result not held case=%0d cycle=%0d",c,cycle); $stop;
                end
            end
            @(negedge clk); check_req = 1'b0;
            @(posedge clk); #0.1;
        end
        descriptors_passed = 1'b1;
        $display("[CASE PASS] descriptor_cases=%0d hold_and_reset=PASS",`DESCRIPTOR_CASES);
    end
    initial begin : check_writers
        repeat(5) @(negedge clk); writer_rst_n = 1'b1;
        // 在写请求被反压时复位，不能泄漏旧事务。
        req_valid = 1'b1; req_addr = 31'h10000; req_bytes = 9'd400; req_data = 3200'h55;
        @(negedge clk); req_valid = 1'b0;
        repeat(6) @(negedge clk); writer_rst_n = 1'b0;
        repeat(2) @(negedge clk);
        if (mem_valid !== 1'b0 || req_ready !== 1'b1) begin $error("writer reset did not cancel"); $stop; end
        writer_rst_n = 1'b1; enable_memory = 1'b1;
        for (int c=0; c<`WRITER_CASES; c++) begin
            @(negedge clk); while (req_ready !== 1'b1) @(negedge clk);
            writer_case = c; job_beats = 0;
            expected_error = writer_stimulus[c][3240];
            req_addr = writer_stimulus[c][3230:3200]; req_bytes = writer_stimulus[c][3239:3231];
            req_data = writer_stimulus[c][3199:0]; req_valid = 1'b1;
            @(posedge clk); #0.1;
            @(negedge clk); req_valid = 1'b0; req_data = ~writer_stimulus[c][3199:0];
            do begin @(posedge clk); #0.1; end while (done !== 1'b1);
            if (error !== expected_error || pending_r !== 1'b0) begin
                $error("writer completion/error mismatch case=%0d cycle=%0d expected=%b actual=%b pending=%b",c,cycle,expected_error,error,pending_r); $stop;
            end
        end
        if (beat_count !== `WRITER_BEATS) begin $error("missing beats expected=%0d actual=%0d",`WRITER_BEATS,beat_count); $stop; end
        writers_passed = 1'b1;
        $display("[CASE PASS] writer_cases=%0d beats=%0d offsets=32 error_and_reset=PASS",`WRITER_CASES,beat_count);
    end
    initial begin
        wait(descriptors_passed && writers_passed);
        $fclose(csv);
        $display("[TB PASSED] 全部数据验证一致 descriptor_cases=%0d writer_cases=%0d beats=%0d cycles=%0d",`DESCRIPTOR_CASES,`WRITER_CASES,beat_count,cycle);
        $finish;
    end
endmodule
