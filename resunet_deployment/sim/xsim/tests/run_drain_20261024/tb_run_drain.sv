`timescale 1ns/1ps
// 【文件类型：.sv】生产op11边界回归；数学Golden由prepare.py离线生成。
module tb_run_drain #(parameter bit FULL_FRAME=1'b1);
`ifdef DRAIN_BASELINE
    localparam bit BASELINE=1'b1;
`else
    localparam bit BASELINE=1'b0;
`endif
    localparam string ROOT="sim/xsim/tests/run_drain_20261024/";
    localparam logic [30:0] A=31'h09400000, Q=31'h09800000;
    localparam logic [30:0] W3=31'h08000000, W5=31'h08001000, P=31'h08002000;
    logic clk_i=1'b0,rst_n_i=1'b0,run_valid_i=1'b0,check_valid_i=1'b0,abort_i=1'b0;
    logic check_done_o,run_ready_o,descriptor_ok_o,busy_o,done_o,error_o,aborted_o;
    logic mem_valid_o,mem_ready_i=1'b0,mem_write_o,mem_rsp_valid_i=1'b0,mem_rsp_ready_o,mem_rsp_error_i=1'b0;
    logic [511:0] descriptor_i=512'd0;
    logic [31:0] result_bytes_o,mac_bytes_o,candidate_bytes_o,candidate_mac_bytes_o,mem_mask_o;
    logic [30:0] mem_addr_o;
    logic [255:0] mem_data_o,mem_rsp_data_i=256'd0;
    logic [1279:0] perf_data_o;
`ifdef DRAIN_BASELINE
    op_engine_drain_before dut(.*);
`else
    op_engine dut(.debug_o(),.*);
`endif
    logic [127:0] inputs[0:262143],golden[0:262143],dw3[0:287],dw5[0:799],params[0:511];
    integer cycle=0,delay_r=0,csv,mode=0,w,h,groups,words,checks,outputs,fences,started,last_progress;
    integer branch3=0,branch5=0,windows=0;
    logic pending=1'b0,active=1'b0,held=1'b0;
    logic [128:0] held_output;
    logic [255:0] response;
    string name;
    always #2 clk_i=~clk_i;
    function automatic logic [127:0] model_word(input logic [30:0] addr);
        if(addr>=A && addr<A+words*16) return inputs[(addr-A)>>4];
        if(addr>=W3 && addr<W3+groups*144) return dw3[(addr-W3)>>4];
        if(addr>=W5 && addr<W5+groups*400) return dw5[(addr-W5)>>4];
        if(addr>=P && addr<P+groups*256) return params[(addr-P)>>4];
        return 128'd0;
    endfunction
    always @(negedge clk_i) begin
        mem_ready_i=rst_n_i && !pending && (mode==0 || cycle%211>=100);
        mem_rsp_valid_i=rst_n_i && pending && delay_r==0;
        mem_rsp_data_i=response;
    end
    always @(posedge clk_i) begin
        cycle=cycle+1;
        if(active) begin
            $fdisplay(csv,"%0d,%s,%0d,%0d,%0d,%b,%b,%b,%b,%b,%b,%b,%0d,%0d,%0d,%0d,%0d",cycle,name,mode,dut.state_r,dut.input_count_r,dut.bank_in_valid_w,dut.bank_in_ready_w,dut.u_bank.valid_w[4],dut.u_bank.lb3_ready_w,dut.u_bank.lb5_ready_w,dut.bank_out_valid_w,dut.bank_out_ready_w,outputs,branch3,branch5,windows,checks);
            if(held && {dut.bank_out_valid_w,dut.bank_last_w,dut.bank_data_w} !== {1'b1,held_output})begin
                $error("unstable output cycle=%0d",cycle);$fflush(csv);$stop;
            end
            held=dut.bank_out_valid_w && !dut.bank_out_ready_w;
            held_output={dut.bank_last_w,dut.bank_data_w};
            if(dut.u_bank.valid_w[4] && dut.u_bank.fused_window_ready_w)windows=windows+1;
            if(dut.u_bank.u_dw3.valid_i && dut.u_bank.u_dw3.ready_o)branch3=branch3+1;
            if(dut.u_bank.u_dw5.valid_i && dut.u_bank.u_dw5.ready_o)branch5=branch5+1;
            if(dut.output_fire_w)begin outputs=outputs+1;last_progress=cycle;end
            if(pending && delay_r>0)delay_r=delay_r-1;
            if(mem_rsp_valid_i&&mem_rsp_ready_o)pending=1'b0;
            if(mem_valid_o&&mem_ready_i)begin
                if(pending)begin $error("overlap");$stop;end
                response=256'd0;
                if(mem_write_o)begin
                    if(mem_mask_o==32'd0)fences=fences+1;
                    else for(integer part=0;part<2;part=part+1)begin
                        if(mem_mask_o[part*16+:16]!==16'd0)begin
                            if(mem_addr_o+part*16 !== Q+checks*16 || mem_mask_o[part*16+:16]!==16'hffff ||
                               checks>=words || (!BASELINE && mem_data_o[part*128+:128]!==golden[checks]))begin
                                $error("Golden/address mismatch cycle=%0d word=%0d addr=%h got=%h expected=%h",cycle,checks,mem_addr_o,mem_data_o[part*128+:128],golden[checks]);$fflush(csv);$stop;
                            end
                            checks=checks+1;
                        end
                    end
                end else response={model_word(mem_addr_o+31'd16),model_word(mem_addr_o)};
                pending=1'b1;
                delay_r=mode==0 ? 0 : mode==2 && mem_write_o ? 50 : cycle%9+1;
            end
            if(cycle-last_progress>50000)begin
                $error("no progress cycle=%0d state=%0d inputs=%0d outputs=%0d branches=%0d/%0d windows=%0d",cycle,dut.state_r,dut.input_count_r,outputs,branch3,branch5,windows);$fflush(csv);$stop;
            end
        end
    end
    task automatic run_case(input string case_name,input integer width,input integer height,input integer g,input integer stall);
        name=case_name;w=width;h=height;groups=g;words=w*h*g;mode=stall;
        $readmemh({ROOT,name,"/input.hex"},inputs,0,words-1);
        $readmemh({ROOT,name,"/golden.hex"},golden,0,words-1);
        $readmemh({ROOT,name,"/dw3.hex"},dw3,0,g*9-1);
        $readmemh({ROOT,name,"/dw5.hex"},dw5,0,g*25-1);
        $readmemh({ROOT,name,"/params.hex"},params,0,g*16-1);
        descriptor_i=512'd0;descriptor_i[7:0]=8'd11;
        descriptor_i[23:16]=8'(g*16);descriptor_i[31:24]=8'(g*16);
        descriptor_i[47:32]=16'(w);descriptor_i[63:48]=16'(h);descriptor_i[79:64]=16'(g);
        descriptor_i[95:88]=8'h80;descriptor_i[103:96]=8'h7f;
        descriptor_i[159:128]={1'b0,A};descriptor_i[223:192]={1'b0,Q};
        descriptor_i[255:224]={1'b0,W5};descriptor_i[287:256]={1'b0,W3};descriptor_i[319:288]={1'b0,P};
        @(negedge clk_i);check_valid_i=1'b1;
        do @(negedge clk_i);while(check_done_o!==1'b1);
        check_valid_i=1'b0;
        if(descriptor_ok_o!==1'b1 || candidate_bytes_o!==32'(words*16))begin $error("descriptor rejected");$stop;end
        repeat(3)@(negedge clk_i);
        checks=0;outputs=0;fences=0;branch3=0;branch5=0;windows=0;held=1'b0;
        active=1'b1;started=cycle;last_progress=cycle;run_valid_i=1'b1;
        @(negedge clk_i);run_valid_i=1'b0;
        do @(negedge clk_i);while(done_o!==1'b1);
        if(error_o!==1'b0 || pending || checks!==words || outputs!==words || fences!==1 ||
           branch3!==words || branch5!==words || windows!==words)begin
            $error("bad completion checks=%0d outputs=%0d branches=%0d/%0d windows=%0d",checks,outputs,branch3,branch5,windows);$fflush(csv);$stop;
        end
        $display("[CASE PASSED] %s mode=%0d words=%0d cycles=%0d",name,mode,words,cycle-started);
        active=1'b0;repeat(6)@(negedge clk_i);
    endtask
    initial begin
        csv=$fopen("sim_trace.csv","w");
        $fdisplay(csv,"cycle,case,mode,state,input_count,in_valid,in_ready,window_valid,dw3_ready,dw5_ready,out_valid,out_ready,outputs,branch3,branch5,windows,checks");
        $dumpfile("waveform.vcd");$dumpvars(0,clk_i,rst_n_i,mem_valid_o,mem_ready_i,done_o);
        repeat(8)@(negedge clk_i);rst_n_i=1'b1;
        if(BASELINE) begin
            run_case("pressure8",8,512,1,2);
            run_case("pressure64",64,64,1,2);
            $fatal(1,"baseline unexpectedly passed the regression");
        end
        else begin
            run_case("row512",512,4,1,0);
            run_case("row512",512,4,1,1);
            run_case("groups2",31,9,2,1);
            run_case("pressure64",64,64,1,2);
            run_case("pressure8",8,512,1,2);
            if(FULL_FRAME) run_case("frame512",512,512,1,0);
        end
        $display("[TB PASSED] op11 Golden, independent branch handshakes, full_frame=%0d",FULL_FRAME);$fclose(csv);$finish;
    end
    initial begin repeat(12000000)@(posedge clk_i);$error("watchdog");$fflush(csv);$stop;end
endmodule
