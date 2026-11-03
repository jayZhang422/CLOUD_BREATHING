`timescale 1ns/1ps
// 实际engine及官方IP；数学期望仅由prepare.py生成。
module tb_hotspot_pw #(parameter bit STRESS=1'b0);
    localparam string ROOT="sim/xsim/tests/hotspot_pe32_20261024/pw/";
    localparam logic [30:0] A=31'h02000000, Q=31'h02400000, M=31'h02600000,
        W=31'h08000000, P=31'h08180000;
    logic clk_i=1'b0, rst_n_i=1'b0, run_valid_i=1'b0, check_valid_i=1'b0, abort_i=1'b0;
    logic check_done_o,run_ready_o,descriptor_ok_o,busy_o,done_o,error_o,aborted_o;
    logic mem_valid_o,mem_ready_i=1'b0,mem_write_o,mem_rsp_valid_i=1'b0,mem_rsp_ready_o,mem_rsp_error_i=1'b0;
    logic [511:0] descriptor_i=512'd0;
    logic [31:0] result_bytes_o,mac_bytes_o,candidate_bytes_o,candidate_mac_bytes_o,mem_mask_o;
    logic [30:0] mem_addr_o;
    logic [255:0] mem_data_o,mem_rsp_data_i=256'd0;
    logic [1279:0] perf_data_o;
    op_engine dut(.debug_o(),.*);
    logic [7:0] inputs[0:65535],weights[0:393215],params[0:8191];
    logic [7:0] golden[0:65535],mac_golden[0:65535],actual[0:65535],actual_mac[0:65535];
    logic seen[0:65535],seen_mac[0:65535];
    integer cycle=0,delay=0,csv,report,fd,scanned,ci,co,px,flags,shift,ab,wb,pb,qb,mb;
    integer mode,started,run_started,passed=0,outputs=0,stalls=0,out_stalls=0,cancelled=0;
    logic pending=1'b0,active=1'b0,held_valid=1'b0;
    logic [255:0] response;
    logic [146:0] held_output;
    string name,folder;
    always #2 clk_i=~clk_i;
    function automatic logic [7:0] model_byte(input logic [30:0] addr);
        if(addr>=A && addr<A+ab) return inputs[addr-A];
        if(addr>=W && addr<W+wb) return weights[addr-W];
        if(addr>=P && addr<P+pb) return params[addr-P];
        return 8'hA5;
    endfunction
    always @(negedge clk_i) begin
        mem_ready_i=rst_n_i && !pending && (STRESS ? cycle%211>=100 : mode==0 || cycle%13>=5);
        mem_rsp_valid_i=rst_n_i && pending && delay==0;
        mem_rsp_data_i=response;
    end
    always @(posedge clk_i) begin
        cycle=cycle+1;
        if(active) begin
            $fdisplay(csv,"%0d,%s,%0d,%0d,%b,%b,%b,%h,%b,%b,%b,%h,%0d,%0d",cycle,name,mode,dut.state_r,mem_valid_o,mem_ready_i,mem_write_o,mem_addr_o,mem_rsp_valid_i,mem_rsp_ready_o,dut.bank_out_valid_w,dut.bank_data_w,dut.bank_pixel_w,dut.bank_group_w);
            if(held_valid && {dut.bank_out_valid_w,dut.bank_pixel_w,dut.bank_data_w} !== {1'b1,held_output}) begin
                $error("output not stable cycle=%0d case=%s",cycle,name);$fflush(csv);$stop;
            end
            held_valid=dut.bank_out_valid_w && !dut.bank_out_ready_w;
            held_output={dut.bank_pixel_w,dut.bank_data_w};
            if(held_valid) out_stalls=out_stalls+1;
            if(dut.output_fire_w) outputs=outputs+1;
            if(dut.state_r==dut.START && dut.start_ready_w)run_started=cycle;
            if(mem_valid_o&&!mem_ready_i)stalls=stalls+1;
            if(pending && delay>0)delay=delay-1;
            if(mem_rsp_valid_i&&mem_rsp_ready_o)pending=1'b0;
            if(mem_valid_o&&mem_ready_i) begin
                if(pending)begin $error("model overlapping request");$stop;end
                response=256'd0;
                if(mem_write_o) begin
                    for(integer b=0;b<32;b=b+1)if(mem_mask_o[b])begin
                        if(mem_addr_o+b>=Q && mem_addr_o+b<Q+qb)begin
                            actual[mem_addr_o+b-Q]=mem_data_o[b*8+:8];seen[mem_addr_o+b-Q]=1'b1;
                        end else if(mb>0 && mem_addr_o+b>=M && mem_addr_o+b<M+mb)begin
                            actual_mac[mem_addr_o+b-M]=mem_data_o[b*8+:8];seen_mac[mem_addr_o+b-M]=1'b1;
                        end else begin $error("write out of range case=%s addr=%h byte=%0d",name,mem_addr_o,b);$fflush(csv);$stop;end
                    end
                end else for(integer b=0;b<32;b=b+1)response[b*8+:8]=model_byte(mem_addr_o+b);
                pending=1'b1;delay=mode==0 ? 0 : cycle%7+1;
            end
        end
    end
    initial begin
        csv=$fopen("sim_trace.csv","w");report=$fopen("checks.txt","w");
        $fdisplay(csv,"cycle,case,mode,state,mem_valid,mem_ready,write,addr,rsp_valid,rsp_ready,out_valid,out_data,pixel,group");
        $dumpfile("waveform.vcd");$dumpvars(0,clk_i,rst_n_i,mem_valid_o,mem_ready_i,mem_addr_o,mem_rsp_valid_i,done_o);
        repeat(6)@(negedge clk_i);rst_n_i=1'b1;
        for(mode=STRESS ? 1 : 0;mode<2;mode=mode+1)begin
            fd=$fopen({ROOT,"cases.txt"},"r");if(!fd)$fatal(1,"missing manifest");
            while(!$feof(fd))begin
                scanned=$fscanf(fd,"%s %d %d %d %d %d %d %d %d %d %d\n",name,ci,co,px,flags,shift,ab,wb,pb,qb,mb);
                if(scanned==11)begin
                    folder={ROOT,"vectors/",name,"/"};
                    $readmemh({folder,"input.hex"},inputs,0,ab-1);$readmemh({folder,"weights.hex"},weights,0,wb-1);
                    $readmemh({folder,"params.hex"},params,0,pb-1);$readmemh({folder,"golden.hex"},golden,0,qb-1);
                    if(mb>0)$readmemh({folder,"mac.hex"},mac_golden,0,mb-1);
                    for(integer b=0;b<qb;b=b+1)begin actual[b]=8'hCC;seen[b]=1'b0;end
                    for(integer b=0;b<mb;b=b+1)begin actual_mac[b]=8'hCC;seen_mac[b]=1'b0;end
                    @(negedge clk_i);descriptor_i=512'd0;descriptor_i[7:0]=8'd1;descriptor_i[15:8]=8'(flags);
                    descriptor_i[47:32]=16'(px);descriptor_i[63:48]=16'd1;descriptor_i[79:64]=16'((co+15)/16);
                    descriptor_i[85:80]=6'(shift);descriptor_i[159:128]={1'b0,A};descriptor_i[223:192]={1'b0,Q};
                    descriptor_i[255:224]={1'b0,M};descriptor_i[287:256]={1'b0,W};descriptor_i[319:288]={1'b0,P};
                    descriptor_i[431:416]=16'(ci);descriptor_i[447:432]=16'(co);check_valid_i=1'b1;
                    do @(negedge clk_i);while(check_done_o!==1'b1);check_valid_i=1'b0;
                    if(descriptor_ok_o!==1'b1||candidate_bytes_o!==32'(qb)||candidate_mac_bytes_o!==32'(mb))begin
                        $error("descriptor case=%s ok=%b bytes=%0d/%0d mac=%0d/%0d",name,descriptor_ok_o,candidate_bytes_o,qb,candidate_mac_bytes_o,mb);$stop;
                    end
                    // 在途预取和已输出部分P8结果时取消，再重新加载同一层。
                    if(STRESS && (name=="p16_low" || name=="p8_tail"))begin
                        @(negedge clk_i);active=1'b1;outputs=0;run_valid_i=1'b1;
                        do @(posedge clk_i);while(run_ready_o!==1'b1);
                        @(negedge clk_i);run_valid_i=1'b0;
                        if(name=="p16_low")begin
                            do @(negedge clk_i);while(dut.u_bank.u_pw_shared.project.fillPending_r==0);
                        end else begin
                            do @(negedge clk_i);while(outputs<3);
                        end
                        rst_n_i=1'b0;active=1'b0;pending=1'b0;held_valid=1'b0;
                        repeat(6)@(negedge clk_i);rst_n_i=1'b1;
                        repeat(4)@(negedge clk_i);check_valid_i=1'b1;
                        do @(negedge clk_i);while(check_done_o!==1'b1);check_valid_i=1'b0;
                        for(integer b=0;b<qb;b=b+1)begin actual[b]=8'hCC;seen[b]=1'b0;end
                        cancelled=cancelled+1;
                        $display("[RESET PASSED] cancelled %s and reconfigured",name);
                    end
                    @(negedge clk_i);active=1'b1;outputs=0;held_valid=1'b0;run_valid_i=1'b1;
                    do @(posedge clk_i);while(run_ready_o!==1'b1);started=cycle;
                    @(negedge clk_i);run_valid_i=1'b0;
                    do @(negedge clk_i);while(done_o!==1'b1);
                    if(error_o!==1'b0||aborted_o!==1'b0||pending)begin $error("bad final status %s",name);$fflush(csv);$stop;end
                    for(integer b=0;b<qb;b=b+1)if(seen[b]!==1'b1||actual[b]!==golden[b])begin
                        $error("Golden case=%s mode=%0d byte=%0d expected=%h actual=%h seen=%b cycle=%0d",name,mode,b,golden[b],actual[b],seen[b],cycle);$fflush(csv);$stop;
                    end
                    for(integer b=0;b<mb;b=b+1)if(seen_mac[b]!==1'b1||actual_mac[b]!==mac_golden[b])begin
                        $error("MAC Golden case=%s byte=%0d expected=%h actual=%h",name,b,mac_golden[b],actual_mac[b]);$fflush(csv);$stop;
                    end
                    $display("[CASE PASSED] %s mode=%0d bytes=%0d mac=%0d tokens=%0d total_cycles=%0d run_cycles=%0d",name,mode,qb,mb,outputs,cycle-started,cycle-run_started);
                    $fdisplay(report,"%s %0d %0d %0d %0d %0d %0d",name,mode,qb,mb,outputs,cycle-started,cycle-run_started);
                    passed=passed+1;active=1'b0;repeat(4)@(negedge clk_i);
                end
            end
            $fclose(fd);
        end
        if(passed!=(STRESS ? 15 : 30)||stalls==0||out_stalls==0||(STRESS && cancelled!=2))$fatal(1,"coverage incomplete");
        $display("[TB PASSED] %0d engine Golden cases P8/P16/RAW/debug stress=%0d resets=%0d stalls=%0d out_stalls=%0d",passed,STRESS,cancelled,stalls,out_stalls);
        $fclose(csv);$fclose(report);$finish;
    end
    initial begin repeat(4000000)@(posedge clk_i);$error("watchdog case=%s cycle=%0d state=%0d",name,cycle,dut.state_r);$fflush(csv);$stop;end
endmodule
