`timescale 1ns/1ps
module tb_dual_plane_batch_filter_core;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, start=0, abort_job=0;
    reg [31:0] cfg_point_count=2, cfg_candidate_count=2;
    reg cfg_reuse_points=0;
    reg [31:0] cfg_timeout_cycles=10000, cfg_job_id=1;
    reg signed [31:0] cfg_margin=0;
    reg [127:0] s_data=0; reg [15:0] s_keep=16'hffff;
    reg s_last=0, s_valid=0, m_ready=1;
    wire s_ready; wire [127:0] m_data; wire [15:0] m_keep;
    wire m_last,m_valid,busy,done_pulse,result_valid;
    wire [31:0] processed_count,accepted_count,cycle_count;
    wire signed [31:0] min_margin_q16; wire [7:0] error_flags;
    dual_plane_batch_filter_core #(.MAX_POINTS(8)) dut(.*);
    function automatic [31:0] q16(input integer value); q16=value*65536; endfunction
    task send_word(input [127:0] value, input bit last);
        begin
            @(negedge clk); s_data=value; s_last=last; s_valid=1;
            while(!s_ready) @(negedge clk);
            @(posedge clk); @(negedge clk); s_valid=0; s_last=0;
        end
    endtask
    integer seen=0;
    reg [127:0] rows [0:1];
    reg [1:0] lasts;
    always @(posedge clk) if(m_valid && m_ready) begin
        rows[seen]=m_data; lasts[seen]=m_last; seen=seen+1;
    end
    initial begin
        lasts=0;
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); start=1; @(posedge clk); @(negedge clk); start=0;
        send_word({32'd0,q16(0),q16(3),q16(2)},1'b1);
        send_word({32'd0,q16(0),q16(3),q16(0)},1'b0);
        // Candidate 0: x >= 1 and y >= 2.
        send_word({q16(-1),32'd0,32'd0,q16(1)},1'b0);
        send_word({q16(-2),32'd0,q16(1),32'd0},1'b0);
        // Candidate 1: x >= 0 and y >= 2.
        send_word({32'd0,32'd0,32'd0,q16(1)},1'b0);
        send_word({q16(-2),32'd0,q16(1),32'd0},1'b1);
        wait(seen==2); @(negedge clk);
        if(rows[0][127:96]!==1 || rows[0][95:64]!==2 ||
           $signed(rows[0][63:32])!==-65536 || rows[0][31:0]!==0)
            $fatal(1,"candidate 0 mismatch: %h",rows[0]);
        if(rows[1][127:96]!==2 || rows[1][95:64]!==2 ||
           $signed(rows[1][63:32])!==0 || rows[1][31:0]!==0)
            $fatal(1,"candidate 1 mismatch: %h",rows[1]);
        if(lasts!==2'b10) $fatal(1,"candidate TLAST ordering mismatch: %b",lasts);
        if(processed_count!==4 || accepted_count!==3 || error_flags!==0)
            $fatal(1,"batch totals mismatch");
        cfg_reuse_points=1; cfg_candidate_count=1; m_ready=0;
        @(negedge clk); start=1; @(posedge clk); @(negedge clk); start=0;
        // Reuse the resident cloud; submit only the second candidate's planes.
        send_word({32'd0,32'd0,32'd0,q16(1)},1'b0);
        send_word({q16(-2),32'd0,q16(1),32'd0},1'b1);
        wait(m_valid); #1;
        if(m_data[127:96]!==2 || m_data[95:64]!==2 ||
           $signed(m_data[63:32])!==0 || m_data[31:0]!==0 || !m_last)
            $fatal(1,"resident-point reuse mismatch: %h",m_data);
        @(negedge clk); m_ready=1; wait(done_pulse); @(negedge clk); m_ready=0;
        $display("DUAL_PLANE_BATCH_RTL_PASS candidates=2 points=2 reuse=1 dma_tlast_inside_batch=ignored");
        $finish;
    end
    initial begin #200000; $fatal(1,"watchdog"); end
endmodule
