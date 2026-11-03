`timescale 1ns/1ps
// 生产/调试writer同源驱动；Golden由prepare_checks.py离线生成。
module tb_batch2_writer;
    localparam string HERE="sim/xsim/tests/rtl_slim_batch2/";
    logic clk=1'b0, rst_n=1'b0, req=1'b0;
    logic [3239:0] stimuli [0:1119];
    logic [318:0] expected [0:4095];
    logic [3199:0] data;
    logic [30:0] address;
    logic [8:0] length;
    wire narrow=length<=9'd32;
    logic ready_n,ready_d,ready_b,done_n,done_d,done_b,error_n,error_d,error_b;
    logic mv_n,mv_d,mv_b,mready=1'b0,rsp=1'b0,rr_n,rr_d,rr_b,re=1'b0;
    logic [30:0] ma_n,ma_d,ma_b;
    logic [255:0] md_n,md_d,md_b;
    logic [31:0] mm_n,mm_d,mm_b;
    op_feature_writer dut (
        .clk_i(clk),.rst_n_i(rst_n),.req_valid_i(req&&narrow),.req_ready_o(ready_n),
        .done_o(done_n),.error_o(error_n),.req_addr_i(address),.req_data_i(data[255:0]),.req_bytes_i(length),
        .mem_valid_o(mv_n),.mem_ready_i(mready),.mem_rsp_valid_i(rsp&&narrow),.mem_rsp_ready_o(rr_n),
        .mem_rsp_error_i(re),.mem_addr_o(ma_n),.mem_data_o(md_n),.mem_mask_o(mm_n));
    op_feature_writer #(.ENABLE_WIDE_DEBUG(1'b1)) debug_dut (
        .clk_i(clk),.rst_n_i(rst_n),.req_valid_i(req),.req_ready_o(ready_d),
        .done_o(done_d),.error_o(error_d),.req_addr_i(address),.req_data_i(data),.req_bytes_i(length),
        .mem_valid_o(mv_d),.mem_ready_i(mready),.mem_rsp_valid_i(rsp),.mem_rsp_ready_o(rr_d),
        .mem_rsp_error_i(re),.mem_addr_o(ma_d),.mem_data_o(md_d),.mem_mask_o(mm_d));
    op_feature_writer_batch2_before baseline (
        .clk_i(clk),.rst_n_i(rst_n),.req_valid_i(req),.req_ready_o(ready_b),
        .done_o(done_b),.error_o(error_b),.req_addr_i(address),.req_data_i(data),.req_bytes_i(length),
        .mem_valid_o(mv_b),.mem_ready_i(mready),.mem_rsp_valid_i(rsp),.mem_rsp_ready_o(rr_b),
        .mem_rsp_error_i(re),.mem_addr_o(ma_b),.mem_data_o(md_b),.mem_mask_o(mm_b));
    integer cycle=0,idx=0,transaction=0,delay_r=0,csv,report,stalls=0,errors=0;
    logic pending=1'b0,active=1'b0,stalled=1'b0;
    logic [318:0] held;
    always #4 clk=~clk;
    always @(negedge clk) begin
        mready=rst_n&&!pending&&cycle%11>=3;
        rsp=rst_n&&pending&&delay_r==0;
        re=idx%11==0;
    end
    always @(posedge clk) begin
        cycle=cycle+1;
        if (rst_n&&active) begin
            if ({ready_d,done_d,error_d,mv_d,rr_d} !== {ready_b,done_b,error_b,mv_b,rr_b} ||
                (narrow && {ready_n,done_n,error_n,mv_n,rr_n} !== {ready_b,done_b,error_b,mv_b,rr_b})) begin
                $error("writer control idx=%0d cycle=%0d",idx,cycle); $fflush(csv); $stop;
            end
            if (mv_d && ({ma_d,mm_d,md_d} !== {ma_b,mm_b,md_b} ||
                (narrow && {ma_n,mm_n,md_n} !== {ma_b,mm_b,md_b}))) begin
                $error("writer data differs idx=%0d cycle=%0d",idx,cycle); $fflush(csv); $stop;
            end
            if (stalled && (!mv_d || {ma_d,mm_d,md_d} !== held)) begin
                $error("writer backpressure idx=%0d cycle=%0d",idx,cycle); $fflush(csv); $stop;
            end
            stalled=mv_d&&!mready; held={ma_d,mm_d,md_d};
            if (stalled) stalls=stalls+1;
            if (pending&&delay_r>0) delay_r=delay_r-1;
            if (rsp&&rr_d) pending=1'b0;
            if (mv_d&&mready) begin
                if (pending || {ma_d,mm_d,md_d} !== expected[transaction]) begin
                    $error("writer Golden idx=%0d txn=%0d got=%h expected=%h",idx,transaction,{ma_d,mm_d,md_d},expected[transaction]); $fflush(csv); $stop;
                end
                transaction=transaction+1; pending=1'b1; delay_r=cycle%7+1;
            end
        end
        $fdisplay(csv,"%0d,%0d,%0d,%0d,%b,%b,%h,%h,%b,%b,%b",cycle,idx,length,transaction,mv_d,mready,ma_d,mm_d,rsp,done_d,error_d);
    end
    initial begin
        csv=$fopen("sim_trace.csv","w"); report=$fopen("checks.txt","w");
        $fdisplay(csv,"cycle,case,length,transaction,valid,ready,address,mask,response,done,error");
        $dumpfile("waveform.vcd");
        $dumpvars(0,clk,rst_n,req,mv_d,mready,ma_d,mm_d,rsp,done_d,error_d);
        $readmemh({HERE,"vectors/writer_stimulus.hex"},stimuli);
        $readmemh({HERE,"vectors/writer_golden.hex"},expected);
        length=9'd4; address=31'd0; data=3200'd0;
        repeat (6) @(negedge clk); rst_n=1'b1;
        for (idx=0;idx<1120;idx=idx+1) begin
            @(negedge clk);
            {address,length,data}=stimuli[idx]; req=1'b1; active=1'b1;
            do @(posedge clk); while (ready_d !== 1'b1);
            @(negedge clk); req=1'b0;
            // 改变上游非有效载荷，检验writer确实锁存了请求。
            data=~data;
            do @(negedge clk); while (done_d !== 1'b1);
            if (pending || error_d !== (idx%11==0)) begin $error("writer completion idx=%0d",idx); $stop; end
            if (error_d) errors=errors+1;
            repeat (2) @(negedge clk); active=1'b0;
        end
        if (transaction==0 || stalls==0 || errors==0 || expected[transaction] !== 319'bx) $fatal(1,"writer coverage incomplete");
        $display("[TB PASSED] writer requests=1120 narrow=1024 wide=96 transactions=%0d stalls=%0d error_cases=%0d exact_cycle_equivalence",transaction,stalls,errors);
        $fdisplay(report,"[TB PASSED] writer requests=1120 narrow=1024 wide=96 transactions=%0d stalls=%0d error_cases=%0d exact_cycle_equivalence",transaction,stalls,errors);
        $fclose(csv); $fclose(report); $finish;
    end
    initial begin
        repeat (200000) @(posedge clk);
        $error("writer watchdog idx=%0d",idx); $fflush(csv); $stop;
    end
endmodule
