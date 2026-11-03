`timescale 1ns/1ps
module tb_rtl_slim_op12;
logic clk_i;
logic rst_n_i;
logic run_valid_i;
logic check_valid_i;
logic check_done_o;
logic check_done_o_before;
logic run_ready_o;
logic run_ready_o_before;
logic descriptor_ok_o;
logic descriptor_ok_o_before;
logic abort_i;
logic busy_o;
logic busy_o_before;
logic done_o;
logic done_o_before;
logic error_o;
logic error_o_before;
logic aborted_o;
logic aborted_o_before;
logic mem_valid_o;
logic mem_valid_o_before;
logic mem_ready_i;
logic mem_write_o;
logic mem_write_o_before;
logic mem_rsp_valid_i;
logic mem_rsp_ready_o;
logic mem_rsp_ready_o_before;
logic mem_rsp_error_i;
logic [511:0] descriptor_i;
logic [31:0] result_bytes_o;
logic [31:0] result_bytes_o_before;
logic [31:0] mac_bytes_o;
logic [31:0] mac_bytes_o_before;
logic [31:0] candidate_bytes_o;
logic [31:0] candidate_bytes_o_before;
logic [31:0] candidate_mac_bytes_o;
logic [31:0] candidate_mac_bytes_o_before;
logic [30:0] mem_addr_o;
logic [30:0] mem_addr_o_before;
logic [255:0] mem_data_o;
logic [255:0] mem_data_o_before;
logic [31:0] mem_mask_o;
logic [31:0] mem_mask_o_before;
logic [255:0] mem_rsp_data_i;
op_engine dut (
    .clk_i(clk_i),
    .rst_n_i(rst_n_i),
    .run_valid_i(run_valid_i),
    .check_valid_i(check_valid_i),
    .check_done_o(check_done_o),
    .run_ready_o(run_ready_o),
    .descriptor_ok_o(descriptor_ok_o),
    .abort_i(abort_i),
    .busy_o(busy_o),
    .done_o(done_o),
    .error_o(error_o),
    .aborted_o(aborted_o),
    .mem_valid_o(mem_valid_o),
    .mem_ready_i(mem_ready_i),
    .mem_write_o(mem_write_o),
    .mem_rsp_valid_i(mem_rsp_valid_i),
    .mem_rsp_ready_o(mem_rsp_ready_o),
    .mem_rsp_error_i(mem_rsp_error_i),
    .descriptor_i(descriptor_i),
    .result_bytes_o(result_bytes_o),
    .mac_bytes_o(mac_bytes_o),
    .candidate_bytes_o(candidate_bytes_o),
    .candidate_mac_bytes_o(candidate_mac_bytes_o),
    .mem_addr_o(mem_addr_o),
    .mem_data_o(mem_data_o),
    .mem_mask_o(mem_mask_o),
    .mem_rsp_data_i(mem_rsp_data_i)
);
op_engine_before baseline (
    .clk_i(clk_i),
    .rst_n_i(rst_n_i),
    .run_valid_i(run_valid_i),
    .check_valid_i(check_valid_i),
    .check_done_o(check_done_o_before),
    .run_ready_o(run_ready_o_before),
    .descriptor_ok_o(descriptor_ok_o_before),
    .abort_i(abort_i),
    .busy_o(busy_o_before),
    .done_o(done_o_before),
    .error_o(error_o_before),
    .aborted_o(aborted_o_before),
    .mem_valid_o(mem_valid_o_before),
    .mem_ready_i(mem_ready_i),
    .mem_write_o(mem_write_o_before),
    .mem_rsp_valid_i(mem_rsp_valid_i),
    .mem_rsp_ready_o(mem_rsp_ready_o_before),
    .mem_rsp_error_i(mem_rsp_error_i),
    .descriptor_i(descriptor_i),
    .result_bytes_o(result_bytes_o_before),
    .mac_bytes_o(mac_bytes_o_before),
    .candidate_bytes_o(candidate_bytes_o_before),
    .candidate_mac_bytes_o(candidate_mac_bytes_o_before),
    .mem_addr_o(mem_addr_o_before),
    .mem_data_o(mem_data_o_before),
    .mem_mask_o(mem_mask_o_before),
    .mem_rsp_data_i(mem_rsp_data_i)
);

localparam string CHECK_ROOT = "sim/xsim/tests/rtl_slim_batch1/";
localparam logic [30:0] A_BASE = 31'h02000000, B_BASE = 31'h02200000, OUT_BASE = 31'h02400000;
localparam logic [30:0] WA_BASE = 31'h08000000, WB_BASE = 31'h08100000, P_BASE = 31'h08180000;
logic [7:0] input_a [0:16383], input_b [0:16383], weights_a [0:393215], weights_b [0:393215];
logic [7:0] params [0:8191], golden [0:17407], actual [0:17407];
logic seen [0:17407];
integer a_bytes,b_bytes,wa_bytes,wb_bytes,p_bytes,out_bytes;
integer cycle=0,csv,report,manifest,scanned,ci,cb,co,pixels,started,cases_done=0;
integer response_delay=0,write_bytes=0,mem_stalls=0,p12_max_addr=0,add_checks=0;
logic pending=1'b0,active=1'b0,stalled=1'b0;
logic [319:0] held;
logic [255:0] pending_data;
string name,folder;
always #4 clk_i = ~clk_i;

function automatic logic [7:0] model_byte(input logic [30:0] address);
    if (address >= A_BASE && address < A_BASE+a_bytes) model_byte=input_a[address-A_BASE];
    else if (address >= B_BASE && address < B_BASE+b_bytes) model_byte=input_b[address-B_BASE];
    else if (address >= WA_BASE && address < WA_BASE+wa_bytes) model_byte=weights_a[address-WA_BASE];
    else if (address >= WB_BASE && address < WB_BASE+wb_bytes) model_byte=weights_b[address-WB_BASE];
    else if (address >= P_BASE && address < P_BASE+p_bytes) model_byte=params[address-P_BASE];
    else if (address >= OUT_BASE && address < OUT_BASE+out_bytes) model_byte=actual[address-OUT_BASE];
    else model_byte=8'd0;
endfunction
function automatic logic [255:0] model_line(input logic [30:0] address);
    for (integer b=0;b<32;b=b+1) model_line[b*8+:8]=model_byte(address+b);
endfunction

always @(negedge clk_i) begin
    if (!rst_n_i) begin mem_ready_i=1'b0; mem_rsp_valid_i=1'b0; end
    else begin
        mem_ready_i=!pending && cycle%13>=4;
        mem_rsp_valid_i=pending && response_delay==0;
        mem_rsp_data_i=pending_data;
    end
end

always @(posedge clk_i) begin
    cycle=cycle+1;
    if (rst_n_i && active) begin
        if ({check_done_o,run_ready_o,descriptor_ok_o,busy_o,done_o,error_o,aborted_o,mem_valid_o,mem_rsp_ready_o} !==
            {check_done_o_before,run_ready_o_before,descriptor_ok_o_before,busy_o_before,done_o_before,error_o_before,aborted_o_before,mem_valid_o_before,mem_rsp_ready_o_before}) begin
            $error("op12 cycle-equivalence control case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
        end
        if (mem_valid_o && {mem_write_o,mem_addr_o,mem_mask_o} !== {mem_write_o_before,mem_addr_o_before,mem_mask_o_before}) begin
            $error("op12 cycle-equivalence memory case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
        end
        if (stalled && (!mem_valid_o || {mem_write_o,mem_addr_o,mem_mask_o,mem_data_o} !== held)) begin
            $error("op12 memory changed under backpressure cycle=%0d",cycle); $fflush(csv); $fflush(report); $stop;
        end
        stalled=mem_valid_o && !mem_ready_i;
        held={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
        if (stalled) mem_stalls=mem_stalls+1;
        if (dut.u_bank.p12_read_en_w && dut.u_bank.p12_read_addr_w>p12_max_addr) p12_max_addr=dut.u_bank.p12_read_addr_w;
        if (dut.u_bank.p12_add_valid_r) begin
            if (dut.u_bank.p12_add_a_data_w !== baseline.u_bank.p12_add_a_data_r ||
                dut.u_bank.p12_add_b_data_w !== baseline.u_bank.p12_add_b_data_r) begin
                $error("op12 URAM assembly cycle=%0d pixel=%0d group=%0d",cycle,dut.u_bank.p12_add_pixel_r,dut.u_bank.add_group_i); $fflush(csv); $fflush(report); $stop;
            end
            add_checks=add_checks+1;
        end
        if (pending && response_delay>0) response_delay=response_delay-1;
        if (mem_rsp_valid_i && mem_rsp_ready_o) pending=1'b0;
        if (mem_valid_o && mem_ready_i) begin
            if (pending) begin $error("op12 overlapping memory request"); $fflush(csv); $fflush(report); $stop; end
            if (mem_write_o) begin
                for (integer b=0;b<32;b=b+1) if (mem_mask_o[b]) begin
                    if (mem_addr_o+b<OUT_BASE || mem_addr_o+b>=OUT_BASE+out_bytes ||
                        mem_data_o[b*8+:8] !== mem_data_o_before[b*8+:8]) begin
                        $error("op12 invalid/different write case=%s addr=%h lane=%0d",name,mem_addr_o,b); $fflush(csv); $fflush(report); $stop;
                    end
                    actual[mem_addr_o+b-OUT_BASE]=mem_data_o[b*8+:8];
                    seen[mem_addr_o+b-OUT_BASE]=1'b1;
                    write_bytes=write_bytes+1;
                end
                pending_data=256'd0;
            end else pending_data=model_line(mem_addr_o);
            pending=1'b1;
            response_delay=cycle%5+1;
        end
    end
    $fdisplay(csv,"%0d,%s,%0d,%0d,%b,%b,%b,%h,%b,%b,%b,%b,%b,%0d,%0d,%0d,%b",cycle,name,dut.state_r,dut.u_bank.p12_phase_r,mem_valid_o,mem_ready_i,mem_write_o,mem_addr_o,mem_rsp_valid_i,mem_rsp_ready_o,done_o,error_o,dut.u_bank.p12_add_valid_r,dut.u_bank.p12_add_part_r,dut.u_bank.p12_add_pixel_r,p12_max_addr,pending);
end

initial begin
    clk_i=1'b0; rst_n_i=1'b0; run_valid_i=1'b0; check_valid_i=1'b0; abort_i=1'b0;
    mem_rsp_error_i=1'b0; mem_rsp_data_i=256'd0; descriptor_i=512'd0;
    csv=$fopen("sim_trace.csv","w"); report=$fopen("checks.txt","w");
    $fdisplay(csv,"cycle,case,state,phase,mem_valid,mem_ready,mem_write,mem_addr,rsp_valid,rsp_ready,done,error,add_valid,part,pixel,max_addr,pending");
    $dumpfile("waveform.vcd");
    $dumpvars(0,clk_i,rst_n_i,run_valid_i,mem_valid_o,mem_ready_i,mem_write_o,mem_addr_o,mem_rsp_valid_i,done_o,error_o);
    manifest=$fopen({CHECK_ROOT,"op12_cases.txt"},"r");
    if (!manifest) $fatal(1,"Cannot open op12 manifest");
    repeat (6) @(negedge clk_i);
    rst_n_i=1'b1;
    while (!$feof(manifest)) begin
        scanned=$fscanf(manifest,"%s %d %d %d %d\n",name,ci,cb,co,pixels);
        if (scanned==5) begin
            a_bytes=((ci+15)/16)*pixels*16; b_bytes=((cb+15)/16)*pixels*16;
            wa_bytes=((ci+15)/16)*(co/4)*64; wb_bytes=((cb+15)/16)*(co/4)*64;
            p_bytes=co*16; out_bytes=co*pixels;
            folder={CHECK_ROOT,"vectors/",name,"/"};
            $readmemh({folder,"input_a.hex"},input_a,0,a_bytes-1);
            $readmemh({folder,"input_b.hex"},input_b,0,b_bytes-1);
            $readmemh({folder,"weights_a.hex"},weights_a,0,wa_bytes-1);
            $readmemh({folder,"weights_b.hex"},weights_b,0,wb_bytes-1);
            $readmemh({folder,"params.hex"},params,0,p_bytes-1);
            $readmemh({folder,"golden.hex"},golden,0,out_bytes-1);
            for (integer b=0;b<out_bytes;b=b+1) begin actual[b]=8'hCC; seen[b]=1'b0; end
            @(negedge clk_i);
            active=1'b1; pending=1'b0; stalled=1'b0; write_bytes=0;
            descriptor_i=512'd0;
            descriptor_i[7:0]=8'd12; descriptor_i[47:32]=pixels; descriptor_i[63:48]=16'd1;
            descriptor_i[79:64]=co/16; descriptor_i[103:96]=8'd127;
            descriptor_i[159:128]={1'b0,A_BASE}; descriptor_i[191:160]={1'b0,B_BASE};
            descriptor_i[223:192]={1'b0,OUT_BASE}; descriptor_i[255:224]={1'b0,WB_BASE};
            descriptor_i[287:256]={1'b0,WA_BASE}; descriptor_i[319:288]={1'b0,P_BASE};
            descriptor_i[431:416]=ci; descriptor_i[447:432]=co; descriptor_i[463:448]=cb;
            check_valid_i=1'b1;
            do @(negedge clk_i); while (check_done_o !== 1'b1);
            check_valid_i=1'b0;
            if (descriptor_ok_o !== 1'b1 || candidate_bytes_o !== out_bytes) begin
                $error("op12 descriptor case=%s ok=%b bytes=%0d expected=%0d",name,descriptor_ok_o,candidate_bytes_o,out_bytes); $fflush(csv); $fflush(report); $stop;
            end
            @(negedge clk_i); run_valid_i=1'b1;
            do @(posedge clk_i); while (run_ready_o !== 1'b1);
            started=cycle;
            @(negedge clk_i); run_valid_i=1'b0;
            do @(negedge clk_i); while (done_o !== 1'b1);
            if (error_o !== 1'b0 || aborted_o !== 1'b0 || result_bytes_o !== out_bytes || mac_bytes_o !== 32'd0 || pending) begin
                $error("op12 status case=%s error=%b aborted=%b bytes=%0d",name,error_o,aborted_o,result_bytes_o); $fflush(csv); $fflush(report); $stop;
            end
            for (integer b=0;b<out_bytes;b=b+1) if (seen[b] !== 1'b1 || actual[b] !== golden[b]) begin
                $error("op12 Golden case=%s byte=%0d seen=%b expected=%h actual=%h",name,b,seen[b],golden[b],actual[b]); $fflush(csv); $fflush(report); $stop;
            end
            $display("[CASE PASSED] op12 %s bytes=%0d writes=%0d run_cycles=%0d cycle_equivalent=1",name,out_bytes,write_bytes,cycle-started);
            $fdisplay(report,"op12 %s bytes=%0d writes=%0d run_cycles=%0d cycle_equivalent=1",name,out_bytes,write_bytes,cycle-started);
            cases_done=cases_done+1;
            repeat (3) @(negedge clk_i);
            active=1'b0;
        end
    end
    if (cases_done!=2 || mem_stalls==0 || p12_max_addr!=2047 || add_checks==0) $fatal(1,"op12 incomplete coverage");
    $display("[TB PASSED] op12 cases=%0d mem_stalls=%0d p12_max_addr=%0d add_checks=%0d exact-cycle-equivalence",cases_done,mem_stalls,p12_max_addr,add_checks);
    $fdisplay(report,"[TB PASSED] op12 cases=%0d mem_stalls=%0d p12_max_addr=%0d add_checks=%0d",cases_done,mem_stalls,p12_max_addr,add_checks);
    $fclose(csv); $fclose(report); $fclose(manifest); $finish;
end
initial begin
    repeat (2000000) @(posedge clk_i);
    $error("op12 watchdog case=%s cycle=%0d state=%0d",name,cycle,dut.state_r); $fflush(csv); $fflush(report); $stop;
end

endmodule
