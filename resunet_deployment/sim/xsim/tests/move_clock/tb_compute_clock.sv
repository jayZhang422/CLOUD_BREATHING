`timescale 1ns/1ps
// 官方Clock Wizard真实模型：两档频率、复位与重新锁定。
module tb_compute_clock;
    logic ref_clk=1'b0, rst_n=1'b0;
    wire fast_clk, safe_clk, locked;
    always #1.5 ref_clk=!ref_clk;
    op_compute_clk_wiz dut(.clk_in1(ref_clk),.resetn(rst_n),.clk_out1(fast_clk),.clk_out2(safe_clk),.locked(locked));
    realtime fast_last=0.0, safe_last=0.0;
    integer fast_edges=0, safe_edges=0, csv;
    always @(posedge fast_clk) if(locked) begin
        if(fast_last!=0.0 && (($realtime-fast_last<3.995)||($realtime-fast_last>4.005)))begin
            $error("250MHz period actual=%0.3f ns",$realtime-fast_last);$stop;
        end
        fast_last=$realtime;fast_edges++;
    end else fast_last=0.0;
    always @(posedge safe_clk) if(locked) begin
        if(safe_last!=0.0 && (($realtime-safe_last<7.995)||($realtime-safe_last>8.005)))begin
            $error("125MHz period actual=%0.3f ns",$realtime-safe_last);$stop;
        end
        safe_last=$realtime;safe_edges++;
    end else safe_last=0.0;
    always @(posedge ref_clk)$fdisplay(csv,"%0t,%b,%b,%b,%b",$time,rst_n,locked,fast_clk,safe_clk);
    initial begin
        csv=$fopen("sim_trace.csv","w");$fdisplay(csv,"time,reset_n,locked,fast,safe");
        $dumpfile("waveform.vcd");$dumpvars(0,ref_clk,rst_n,locked,fast_clk,safe_clk);
        repeat(10)@(negedge ref_clk);rst_n=1'b1;wait(locked);repeat(100)@(negedge safe_clk);
        rst_n=1'b0;repeat(10)@(negedge ref_clk);
        if(locked!==1'b0)begin $error("Clock Wizard lock did not clear");$stop;end
        fast_last=0.0;safe_last=0.0;
        rst_n=1'b1;wait(locked);repeat(100)@(negedge safe_clk);
        if(fast_edges<390 || safe_edges<190)begin $error("clock edge coverage");$stop;end
        $fclose(csv);$display("[TB PASSED] 全部数据验证一致 fast_edges=%0d safe_edges=%0d relock=1",fast_edges,safe_edges);$finish;
    end
    initial begin #20000;$fatal(1,"Clock lock timeout");end
endmodule
