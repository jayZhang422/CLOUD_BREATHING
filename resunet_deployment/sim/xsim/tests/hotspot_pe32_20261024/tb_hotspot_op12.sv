`timescale 1ns/1ps
module pwstream_op12_runner #(parameter bit FAST=0, parameter bit CACHE_ENABLED=1)(output logic finished_o);
logic clk_i;
logic rst_n_i;
logic run_valid_i;
logic check_valid_i;
logic check_done_o;
logic run_ready_o;
logic descriptor_ok_o;
logic abort_i;
logic busy_o;
logic done_o;
logic error_o;
logic aborted_o;
logic mem_valid_o;
logic mem_ready_i;
logic mem_write_o;
logic mem_rsp_valid_i;
logic mem_rsp_ready_o;
logic mem_rsp_error_i;
logic [511:0] descriptor_i;
logic [31:0] result_bytes_o;
logic [31:0] mac_bytes_o;
logic [31:0] candidate_bytes_o;
logic [31:0] candidate_mac_bytes_o;
logic [30:0] mem_addr_o;
logic [255:0] mem_data_o;
logic [31:0] mem_mask_o;
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

localparam string CHECK_ROOT = "sim/xsim/tests/rtl_slim_batch1/";
localparam logic [30:0] A_BASE = 31'h02000000, B_BASE = 31'h02200000, OUT_BASE = 31'h02400000;
localparam logic [30:0] WA_BASE = 31'h08000000, WB_BASE = 31'h08100000, P_BASE = 31'h08180000;
logic [7:0] input_a [0:16383], input_b [0:16383], weights_a [0:393215], weights_b [0:393215];
logic [7:0] params [0:8191], golden [0:17407], actual [0:17407];
logic seen [0:17407];
integer a_bytes,b_bytes,wa_bytes,wb_bytes,p_bytes,out_bytes;
integer run_cycles[0:1];
integer cycle=0,csv,report,manifest,scanned,ci,cb,co,pixels,started,cases_done=0;
integer response_delay=0,write_bytes=0,mem_stalls=0,p12_max_addr=0,add_checks=0;
integer add_param_reads=0;
integer expected_param_reads;
logic pending=1'b0,active=1'b0,stalled=1'b0;
logic [319:0] held;
logic [255:0] pending_data;
string name,folder;
always #2 clk_i = ~clk_i;

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
        mem_ready_i=!pending && (FAST || cycle%13>=4);
        mem_rsp_valid_i=pending && response_delay==0;
        mem_rsp_data_i=pending_data;
    end
end

always @(posedge clk_i) begin
    cycle=cycle+1;
    if (rst_n_i && active) begin
        if (mem_valid_o && mem_ready_i && !mem_write_o && mem_addr_o >= P_BASE && mem_addr_o < P_BASE+p_bytes)
            add_param_reads=add_param_reads+1;
        if (stalled && held[319] && (!mem_valid_o || {mem_write_o,mem_addr_o,mem_mask_o,mem_data_o} !== held)) begin
            $error("op12 memory changed under backpressure cycle=%0d",cycle); $fflush(csv); $fflush(report); $stop;
        end
        stalled=mem_valid_o && !mem_ready_i;
        held={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
        if (stalled) mem_stalls=mem_stalls+1;
        if (dut.u_bank.p12_read_en_w && dut.u_bank.p12_read_addr_w>p12_max_addr) p12_max_addr=dut.u_bank.p12_read_addr_w;
        if (dut.u_bank.p12_add_valid_r) begin
            add_checks=add_checks+1;
        end
        if (pending && response_delay>0) response_delay=response_delay-1;
        if (mem_rsp_valid_i && mem_rsp_ready_o) pending=1'b0;
        if (mem_valid_o && mem_ready_i) begin
            if (pending) begin $error("op12 overlapping memory request"); $fflush(csv); $fflush(report); $stop; end
            if (mem_write_o) begin
                for (integer b=0;b<32;b=b+1) if (mem_mask_o[b]) begin
                    if (mem_addr_o+b<OUT_BASE || mem_addr_o+b>=OUT_BASE+out_bytes) begin
                        $error("op12 invalid/different write case=%s addr=%h lane=%0d",name,mem_addr_o,b); $fflush(csv); $fflush(report); $stop;
                    end
                    actual[mem_addr_o+b-OUT_BASE]=mem_data_o[b*8+:8];
                    seen[mem_addr_o+b-OUT_BASE]=1'b1;
                    write_bytes=write_bytes+1;
                end
                pending_data=256'd0;
            end else pending_data=model_line(mem_addr_o);
            pending=1'b1;
            response_delay=FAST ? 0 : cycle%5+1;
        end
    end
    if (!finished_o) $fdisplay(csv,"%0d,%s,%0d,%0d,%b,%b,%b,%h,%b,%b,%b,%b,%b,%0d,%0d,%0d,%b",cycle,name,dut.state_r,dut.u_bank.p12_phase_r,mem_valid_o,mem_ready_i,mem_write_o,mem_addr_o,mem_rsp_valid_i,mem_rsp_ready_o,done_o,error_o,dut.u_bank.p12_add_valid_r,2'd0,dut.u_bank.p12_add_pixel_r,p12_max_addr,pending);
end

initial begin
    // 仅用于同一生产RTL的缓存开/关性能对照，不向生产模块增加调试参数。
    if (!CACHE_ENABLED) force dut.add_cache_hit_w = 1'b0;
    finished_o=1'b0; clk_i=1'b0; rst_n_i=1'b0; run_valid_i=1'b0; check_valid_i=1'b0; abort_i=1'b0;
    mem_rsp_error_i=1'b0; mem_rsp_data_i=256'd0; descriptor_i=512'd0;
    if (FAST) begin csv=$fopen("sim_trace_fast.csv","w"); report=$fopen("checks_fast.txt","w"); end
    else begin csv=$fopen("sim_trace_slow.csv","w"); report=$fopen("checks_slow.txt","w"); end
    if (!finished_o) $fdisplay(csv,"cycle,case,state,phase,mem_valid,mem_ready,mem_write,mem_addr,rsp_valid,rsp_ready,done,error,add_valid,part,pixel,max_addr,pending");
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
            active=1'b1; pending=1'b0; stalled=1'b0; write_bytes=0; add_param_reads=0;
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
            // 每层每个32B参数响应只取一次，跨tile复用；Golden仍逐字节独立比较。
            expected_param_reads = (p_bytes/32) * (CACHE_ENABLED ? 1 : ((pixels+15)/16));
            if (add_param_reads !== expected_param_reads) begin
                $error("op12 Add cache reads case=%s expected=%0d actual=%0d",name,expected_param_reads,add_param_reads);
                $fflush(csv); $fflush(report); $stop;
            end
            $display("[CACHE PASSED] %s enabled=%0d fast=%0d Add_reads_32B=%0d bytes=%0d",name,CACHE_ENABLED,FAST,add_param_reads,add_param_reads*32);
            $display("[CASE PASSED] shared op12 %s bytes=%0d writes=%0d run_cycles=%0d independent-Golden",name,out_bytes,write_bytes,cycle-started);
            $fdisplay(report,"shared op12 %s bytes=%0d writes=%0d run_cycles=%0d independent-Golden",name,out_bytes,write_bytes,cycle-started);
            run_cycles[cases_done]=cycle-started;
            cases_done=cases_done+1;
            repeat (3) @(negedge clk_i);
            active=1'b0;
        end
    end
    if (cases_done!=2 || (!FAST && mem_stalls==0) || p12_max_addr!=511 || add_checks==0) $fatal(1,"op12 incomplete coverage");
    $display("[RUNNER PASSED] op12 cases=%0d mem_stalls=%0d p12_max_addr=%0d add_checks=%0d independent-Golden",cases_done,mem_stalls,p12_max_addr,add_checks);
    $fdisplay(report,"[RUNNER PASSED] op12 cases=%0d mem_stalls=%0d p12_max_addr=%0d add_checks=%0d",cases_done,mem_stalls,p12_max_addr,add_checks);
    $fclose(csv); $fclose(report); $fclose(manifest); finished_o=1'b1;
end
initial begin
    repeat (2000000) @(posedge clk_i);
    $error("op12 watchdog case=%s cycle=%0d state=%0d",name,cycle,dut.state_r); $fflush(csv); $fflush(report); $stop;
end

endmodule


module tb_hotspot_op12 #(parameter bit CACHE_ENABLED=1);
wire fast_done,slow_done;
pwstream_op12_runner #(.FAST(1'b1),.CACHE_ENABLED(CACHE_ENABLED)) fast(fast_done);
pwstream_op12_runner #(.FAST(1'b0),.CACHE_ENABLED(CACHE_ENABLED)) slow(slow_done);
initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0,fast.clk_i,fast.rst_n_i,fast.mem_valid_o,fast.mem_addr_o,fast.done_o,
                 slow.mem_valid_o,slow.mem_addr_o,slow.done_o);
    wait(fast_done && slow_done);
    $display("[TB PASSED] 全部数据验证一致 op12 two frozen Golden cases fast+slow DDR 250MHz");
    $finish;
end
endmodule
