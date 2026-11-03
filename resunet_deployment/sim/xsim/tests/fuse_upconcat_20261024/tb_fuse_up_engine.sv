`timescale 1ns/1ps
// 实际engine及官方FIFO；Python Golden负责数学，TB只驱动流控与核对字节。
module tb_fuse_up_engine;
    localparam string ROOT="sim/xsim/tests/fuse_upconcat_20261024/";
    localparam logic [30:0] A=31'h02000000, B=31'h02800000, Q=31'h03000000, U=31'h03800000;
    logic clk_i=1'b0, rst_n_i=1'b0, run_valid_i=1'b0, check_valid_i=1'b0, abort_i=1'b0;
    logic check_done_o,run_ready_o,descriptor_ok_o,busy_o,done_o,error_o,aborted_o;
    logic mem_valid_o,mem_ready_i=1'b0,mem_write_o,mem_rsp_valid_i=1'b0,mem_rsp_ready_o,mem_rsp_error_i=1'b0;
    logic [511:0] descriptor_i=512'd0;
    logic [31:0] result_bytes_o,mac_bytes_o,candidate_bytes_o,candidate_mac_bytes_o,mem_mask_o;
    logic [30:0] mem_addr_o;
    logic [255:0] mem_data_o,mem_rsp_data_i=256'd0;
    logic [1279:0] perf_data_o;
    op_engine dut(.debug_o(),.*);
    logic [7:0] inputs[0:65535],skip[0:65535],upgold[0:131071],golden[0:196607];
    logic [7:0] actual[0:196639],intermediate[0:131071];
    logic seen[0:196639];
    integer cycle=0,delay=0,csv,report,fd,got,w,h,ga,gb,offset,ab,bb,qb;
    integer mode,passed=0,reads,writes,fences,outputs,started,baseline_cycles,baseline_reads,baseline_writes;
    integer fused_cycles,reset_count=0;
    logic pending=1'b0,active=1'b0,held_valid=1'b0,held_req=1'b0;
    logic [255:0] response;
    logic [128:0] held_output;
    logic [319:0] held_request;
    string name,folder;
    always #2 clk_i=~clk_i;
    function automatic logic [7:0] model_byte(input logic [30:0] addr);
        if(addr>=A+offset && addr<A+offset+ab) return inputs[addr-A-offset];
        if(addr>=B+offset && addr<B+offset+bb) return skip[addr-B-offset];
        if(addr>=U && addr<U+ab*4) return intermediate[addr-U];
        return 8'hA5;
    endfunction
    always @(negedge clk_i) begin
        mem_ready_i=rst_n_i && !pending && (mode==0 || cycle%211>=100);
        mem_rsp_valid_i=rst_n_i && pending && delay==0;
        mem_rsp_data_i=response;
    end
    always @(posedge clk_i) begin
        cycle=cycle+1;
        if(active) begin
            $fdisplay(csv,"%0d,%s,%0d,%0d,%b,%b,%b,%h,%b,%b,%b,%b,%h,%b,%b",cycle,name,mode,dut.state_r,mem_valid_o,mem_ready_i,mem_write_o,mem_addr_o,mem_rsp_valid_i,mem_rsp_ready_o,dut.bank_out_valid_w,dut.bank_out_ready_w,dut.bank_data_w,dut.fuse_skip_r,done_o);
            if(held_valid && {dut.bank_out_valid_w,dut.bank_last_w,dut.bank_data_w} !== {1'b1,held_output}) begin
                $error("output changed under stall cycle=%0d",cycle);$fflush(csv);$stop;
            end
            held_valid=dut.bank_out_valid_w && !dut.bank_out_ready_w;
            held_output={dut.bank_last_w,dut.bank_data_w};
            if(held_req && {mem_valid_o,mem_write_o,mem_addr_o,mem_mask_o,mem_data_o} !== {1'b1,held_request}) begin
                $error("request changed under stall cycle=%0d",cycle);$fflush(csv);$stop;
            end
            held_req=mem_valid_o && !mem_ready_i;
            held_request={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
            if(dut.output_fire_w) outputs=outputs+1;
            if(pending && delay>0)delay=delay-1;
            if(mem_rsp_valid_i&&mem_rsp_ready_o)pending=1'b0;
            if(mem_valid_o&&mem_ready_i) begin
                if(pending)begin $error("overlapping model request");$stop;end
                response=256'd0;
                if(mem_write_o) begin
                    if(mem_mask_o==32'd0) fences=fences+1;
                    else writes=writes+1;
                    for(integer b=0;b<32;b=b+1)if(mem_mask_o[b])begin
                        if(mem_addr_o+b>=Q && mem_addr_o+b<Q+qb)begin
                            actual[mem_addr_o+b-Q]=mem_data_o[b*8+:8];seen[mem_addr_o+b-Q]=1'b1;
                        end else if(mem_addr_o+b>=U && mem_addr_o+b<U+ab*4)
                            intermediate[mem_addr_o+b-U]=mem_data_o[b*8+:8];
                        else begin $error("write outside tensor addr=%h byte=%0d",mem_addr_o,b);$fflush(csv);$stop;end
                    end
                end else begin
                    reads=reads+1;
                    for(integer b=0;b<32;b=b+1)response[b*8+:8]=model_byte(mem_addr_o+b);
                end
                pending=1'b1;delay=mode==0 ? 0 : cycle%9+1;
            end
        end
    end
    task automatic make_desc(input integer op);
        descriptor_i=512'd0;descriptor_i[7:0]=8'(op);
        descriptor_i[47:32]=16'(op==5 ? w*2 : w);descriptor_i[63:48]=16'(op==5 ? h*2 : h);
        descriptor_i[79:64]=16'(ga);descriptor_i[127:112]=16'(gb);
        descriptor_i[159:128]=op==5 ? {1'b0,U} : A+offset;
        descriptor_i[191:160]=B+offset;descriptor_i[223:192]=op==10 ? {1'b0,U} : {1'b0,Q};
    endtask
    task automatic check_desc(input integer expected_bytes,input logic expected_ok);
        @(negedge clk_i);check_valid_i=1'b1;
        do @(negedge clk_i);while(check_done_o!==1'b1);check_valid_i=1'b0;
        if(descriptor_ok_o!==expected_ok || (expected_ok && candidate_bytes_o!==32'(expected_bytes)))begin
            $error("descriptor op=%0d ok=%b bytes=%0d expected=%0d",descriptor_i[7:0],descriptor_ok_o,candidate_bytes_o,expected_bytes);$stop;
        end
        repeat(3)@(negedge clk_i);
    endtask
    task automatic launch;
        @(negedge clk_i);run_valid_i=1'b1;started=cycle;held_valid=1'b0;held_req=1'b0;active=1'b1;
        do @(posedge clk_i);while(run_ready_o!==1'b1);
        @(negedge clk_i);run_valid_i=1'b0;
    endtask
    task automatic finish_run;
        do @(negedge clk_i);while(done_o!==1'b1);
        if(error_o!==1'b0||aborted_o!==1'b0||pending||dut.u_move_writer.idle_o!==1'b1)begin
            $error("completion before drain or bad status");$fflush(csv);$stop;
        end
        active=1'b0;repeat(4)@(negedge clk_i);
    endtask
    task automatic check_golden;
        for(integer b=0;b<qb;b=b+1)if(seen[b]!==1'b1||actual[b]!==golden[b])begin
            $error("Golden %s mode=%0d byte=%0d expected=%h actual=%h seen=%b cycle=%0d",name,mode,b,golden[b],actual[b],seen[b],cycle);$fflush(csv);$stop;
        end
    endtask
    initial begin
        csv=$fopen("sim_trace.csv","w");report=$fopen("checks.txt","w");
        $fdisplay(csv,"cycle,case,mode,state,mem_valid,mem_ready,write,addr,rsp_valid,rsp_ready,out_valid,out_ready,out_data,skip,done");
        $dumpfile("waveform.vcd");$dumpvars(0,clk_i,rst_n_i,mem_valid_o,mem_ready_i,mem_addr_o,mem_rsp_valid_i,done_o);
        repeat(6)@(negedge clk_i);rst_n_i=1'b1;
        // 检查尺寸上限、skip组数、两输入范围和尾段重叠。
        w=2;h=2;ga=1;gb=1;offset=0;ab=64;bb=256;qb=512;
        for(integer bad=0;bad<7;bad=bad+1)begin
            make_desc(13);
            case(bad)
                0:descriptor_i[47:32]=16'd257;
                1:descriptor_i[127:112]=16'd0;
                2:descriptor_i[127:112]=16'd33;
                3:descriptor_i[191:160]=32'h1ffffff0;
                4:descriptor_i[223:192]=A-32'd256;
                5:descriptor_i[223:192]=B;
                6:descriptor_i[15:8]=8'd1;
            endcase
            check_desc(0,1'b0);
        end
        $display("[BOUNDS PASSED] 7 invalid op13 descriptors rejected");
        for(mode=0;mode<2;mode=mode+1)begin
            fd=$fopen({ROOT,"cases.txt"},"r");if(!fd)$fatal(1,"missing manifest");
            while(!$feof(fd))begin
                got=$fscanf(fd,"%s %d %d %d %d %d %d %d %d\n",name,w,h,ga,gb,offset,ab,bb,qb);
                if(got==9)begin
                    folder={ROOT,"vectors/",name,"/"};
                    $readmemh({folder,"input.hex"},inputs,0,ab-1);$readmemh({folder,"skip.hex"},skip,0,bb-1);
                    $readmemh({folder,"up.hex"},upgold,0,ab*4-1);$readmemh({folder,"golden.hex"},golden,0,qb-1);
                    for(integer b=0;b<qb;b=b+1)begin actual[b]=8'hCC;seen[b]=1'b0;end
                    reads=0;writes=0;fences=0;outputs=0;
                    make_desc(10);check_desc(ab*4,1'b1);launch;finish_run;baseline_cycles=cycle-started-4;
                    for(integer b=0;b<ab*4;b=b+1)if(intermediate[b]!==upgold[b])begin $error("baseline Upsample Golden");$stop;end
                    make_desc(5);check_desc(qb,1'b1);launch;finish_run;baseline_cycles=baseline_cycles+cycle-started-4;check_golden;
                    baseline_reads=reads;baseline_writes=writes;
                    reads=0;writes=0;fences=0;outputs=0;
                    for(integer b=0;b<qb;b=b+1)begin actual[b]=8'hCC;seen[b]=1'b0;end
                    make_desc(13);check_desc(qb,1'b1);
                    // A和skip两阶段分别在途复位，再完整重跑；复位代表外部内存总线同步取消。
                    if(mode==1 && (name=="fuse_odd" || name=="fuse_d1_small"))begin
                        launch;
                        if(name=="fuse_odd")begin do @(negedge clk_i);while(outputs<2);end
                        else begin do @(negedge clk_i);while(!dut.fuse_skip_started_r);repeat(8)@(negedge clk_i);end
                        rst_n_i=1'b0;active=1'b0;pending=1'b0;held_valid=1'b0;held_req=1'b0;
                        repeat(6)@(negedge clk_i);rst_n_i=1'b1;repeat(4)@(negedge clk_i);
                        make_desc(13);check_desc(qb,1'b1);reset_count=reset_count+1;
                        reads=0;writes=0;fences=0;outputs=0;
                        for(integer b=0;b<qb;b=b+1)begin actual[b]=8'hCC;seen[b]=1'b0;end
                    end
                    launch;finish_run;fused_cycles=cycle-started-4;check_golden;
                    if(fences!=1 || outputs!=qb/16 || reads>=baseline_reads || writes>=baseline_writes)begin
                        $error("coverage/traffic not improved fences=%0d outputs=%0d reads=%0d/%0d writes=%0d/%0d",fences,outputs,reads,baseline_reads,writes,baseline_writes);$stop;
                    end
                    $display("[CASE PASSED] %s mode=%0d cycles=%0d->%0d reads=%0d->%0d writes=%0d->%0d bytes=%0d",name,mode,baseline_cycles,fused_cycles,baseline_reads,reads,baseline_writes,writes,qb);
                    $fdisplay(report,"%s %0d %0d %0d %0d %0d %0d %0d",name,mode,baseline_cycles,fused_cycles,baseline_reads,reads,baseline_writes,writes);
                    passed=passed+1;
                    // 同描述符不复位重复启动，缓存及流水不得残留上一任务有效位。
                    if(name=="fuse_odd")begin
                        for(integer b=0;b<qb;b=b+1)begin actual[b]=8'hCC;seen[b]=1'b0;end
                        reads=0;writes=0;fences=0;outputs=0;
                        check_desc(qb,1'b1);launch;finish_run;check_golden;
                        if(fences!=1 || outputs!=qb/16)begin $error("restart coverage incomplete");$stop;end
                        $display("[RESTART PASSED] mode=%0d",mode);
                    end
                end
            end
            $fclose(fd);
        end
        if(passed!=18 || reset_count!=2)$fatal(1,"coverage incomplete");
        $display("[TB PASSED] 18 fused/baseline Golden pairs, 7 invalid descriptors, 2 restarts, 2 resets");
        $fclose(csv);$fclose(report);$finish;
    end
    initial begin repeat(4000000)@(posedge clk_i);$error("watchdog %s cycle=%0d state=%0d",name,cycle,dut.state_r);$fflush(csv);$stop;end
endmodule
