"""生成本批改动的接口自校验；参考模块只用于仿真，不进入设计源集。"""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SOURCES = ROOT / "src/rtl/op"


def pair(module, source):
    header = source.read_text(encoding="utf-8-sig").split(");", 1)[0]
    ports = re.findall(r"\b(input|output)\s+(?:wire|logic)\s*(\[[^\]]+\])?\s*(\w+)\s*(?:,|//|\n)", header)
    declarations, actual, reference = [], [], []
    for direction, width, name in ports:
        suffix = f"{width} " if width else ""
        declarations.append(f"logic {suffix}{name};")
        actual.append(f".{name}({name})")
        if direction == "output":
            declarations.append(f"logic {suffix}{name}_before;")
            reference.append(f".{name}({name}_before)")
        else:
            reference.append(f".{name}({name})")
    instances = f"{module} dut (\n    " + ",\n    ".join(actual) + "\n);\n"
    instances += f"{module}_before baseline (\n    " + ",\n    ".join(reference) + "\n);\n"
    return "\n".join(declarations) + "\n" + instances


PW_BODY = r'''
localparam string VECTOR_ROOT = "sim/standalone/op/pw/verification/stage3_pe16/vectors/";
localparam string CHECK_ROOT = "sim/xsim/tests/rtl_slim_batch1/";
logic [127:0] inputs [0:65535], expected_mac [0:65535];
logic [511:0] weights [0:6143], params [0:127];
logic [63:0] expected_q [0:65535];
logic [31:0] expected_tags [0:65535], expected_requests [0:65535];
wire [127:0] mac = {io_output_o_payload_mac_3,io_output_o_payload_mac_2,io_output_o_payload_mac_1,io_output_o_payload_mac_0};
wire [63:0] q = {io_output_o_payload_q_3,io_output_o_payload_q_2,io_output_o_payload_q_1,io_output_o_payload_q_0};
wire [31:0] tag = {1'b0,io_output_o_payload_last,io_output_o_payload_mask,io_output_o_payload_group,io_output_o_payload_pixel};
wire [127:0] mac_before = {io_output_o_payload_mac_3_before,io_output_o_payload_mac_2_before,io_output_o_payload_mac_1_before,io_output_o_payload_mac_0_before};
wire [63:0] q_before = {io_output_o_payload_q_3_before,io_output_o_payload_q_2_before,io_output_o_payload_q_1_before,io_output_o_payload_q_0_before};
wire [31:0] tag_before = {1'b0,io_output_o_payload_last_before,io_output_o_payload_mask_before,io_output_o_payload_group_before,io_output_o_payload_pixel_before};
integer cycle = 0, got = 0, requests = 0, outputs_total = 0;
integer csv, report, manifest, scanned, ci, co, pixels, shift, raw_mode, int16_mode;
integer wi, pi, weight_words, param_words, input_words, started, cases_done = 0;
integer response_delay = 0, read_stalls = 0, output_stalls = 0;
logic pending = 1'b0, active = 1'b0, stalled = 1'b0;
logic [223:0] held;
logic [127:0] pending_data;
string name, folder;
always #4 clk = ~clk;

// 负沿驱动；正沿仅采样已稳定的握手和载荷。
always @(negedge clk) begin
    if (!resetn) begin
        io_rd_o_ready = 1'b0;
        io_rsp_i_valid = 1'b0;
        io_output_o_ready = 1'b0;
    end else begin
        io_rd_o_ready = !pending && cycle % 7 != 2;
        io_output_o_ready = cycle % 17 >= 5;
        io_rsp_i_valid = pending && response_delay == 0;
        io_rsp_i_payload = pending_data;
    end
end

always @(posedge clk) begin
    cycle = cycle + 1;
    if (resetn && active) begin
        if ({io_cfg_i_ready,io_weights_i_ready,io_params_i_ready,io_start_i_ready,io_busy_o,io_done_o,io_rd_o_valid,io_rsp_i_ready,io_output_o_valid} !==
            {io_cfg_i_ready_before,io_weights_i_ready_before,io_params_i_ready_before,io_start_i_ready_before,io_busy_o_before,io_done_o_before,io_rd_o_valid_before,io_rsp_i_ready_before,io_output_o_valid_before}) begin
            $error("PW cycle-equivalence control case=%s cycle=%0d",name,cycle); $stop;
        end
        if (io_rd_o_valid && io_rd_o_payload !== io_rd_o_payload_before) begin
            $error("PW cycle-equivalence address case=%s cycle=%0d",name,cycle); $stop;
        end
        if (io_output_o_valid && {tag,mac,q,io_output_o_payload_raw,io_output_o_payload_int16} !==
            {tag_before,mac_before,q_before,io_output_o_payload_raw_before,io_output_o_payload_int16_before}) begin
            $error("PW cycle-equivalence payload case=%s cycle=%0d",name,cycle); $stop;
        end
        if (stalled && (!io_output_o_valid || {tag,mac,q} !== held)) begin
            $error("PW backpressure data changed case=%s cycle=%0d",name,cycle); $stop;
        end
        stalled = io_output_o_valid && !io_output_o_ready;
        held = {tag,mac,q};
        if (io_output_o_valid && !io_output_o_ready) output_stalls = output_stalls + 1;
        if (io_rd_o_valid && !io_rd_o_ready) read_stalls = read_stalls + 1;
        if (pending && response_delay > 0) response_delay = response_delay - 1;
        if (io_rsp_i_valid && io_rsp_i_ready) pending = 1'b0;
        if (io_rd_o_valid && io_rd_o_ready) begin
            if (pending || requests >= input_words || io_rd_o_payload !== expected_requests[requests]) begin
                $error("PW read request case=%s index=%0d addr=%0d expected=%0d",name,requests,io_rd_o_payload,expected_requests[requests]); $stop;
            end
            pending_data = inputs[io_rd_o_payload];
            pending = 1'b1;
            response_delay = cycle % 4 + 1;
            requests = requests + 1;
        end
        if (io_output_o_valid && io_output_o_ready) begin
            if (got >= outputs_total || tag !== expected_tags[got] || mac !== expected_mac[got] || q !== expected_q[got] ||
                io_output_o_payload_raw !== io_cfg_i_payload_raw || io_output_o_payload_int16 !== io_cfg_i_payload_int16) begin
                $error("PW Golden case=%s index=%0d tag=%h expected_tag=%h mac=%h expected_mac=%h q=%h expected_q=%h",name,got,tag,expected_tags[got],mac,expected_mac[got],q,expected_q[got]); $stop;
            end
            got = got + 1;
        end
    end
    $fdisplay(csv,"%0d,%s,%b,%b,%h,%b,%b,%b,%b,%h,%h,%h,%0d,%0d",cycle,name,io_rd_o_valid,io_rd_o_ready,io_rd_o_payload,io_rsp_i_valid,io_rsp_i_ready,io_output_o_valid,io_output_o_ready,tag,mac,q,got,requests);
end

initial begin
    clk = 1'b0; resetn = 1'b0;
    io_cfg_i_valid = 1'b0; io_weights_i_valid = 1'b0; io_params_i_valid = 1'b0;
    io_start_i_valid = 1'b0; io_start_i_payload = 1'b1;
    io_cfg_i_payload_cin = 10'd1; io_cfg_i_payload_cout = 10'd1; io_cfg_i_payload_pixels = 19'd1;
    io_cfg_i_payload_shift = 6'd0; io_cfg_i_payload_raw = 1'b0; io_cfg_i_payload_int16 = 1'b0;
    io_weights_i_payload = 512'd0; io_params_i_payload = 512'd0; io_rsp_i_payload = 128'd0;
    csv = $fopen("sim_trace.csv","w");
    $fdisplay(csv,"cycle,case,rd_valid,rd_ready,rd_addr,rsp_valid,rsp_ready,out_valid,out_ready,tag,mac,q,outputs,requests");
    report = $fopen("checks.txt","w");
    $dumpfile("waveform.vcd");
    $dumpvars(0,clk,resetn,io_rd_o_valid,io_rd_o_ready,io_rd_o_payload,io_output_o_valid,io_output_o_ready,tag,io_done_o);
    manifest = $fopen({CHECK_ROOT,"pw_cases.txt"},"r");
    if (!manifest) $fatal(1,"Cannot open PW manifest");
    repeat (6) @(negedge clk);
    resetn = 1'b1;
    while (!$feof(manifest)) begin
        scanned = $fscanf(manifest,"%s %d %d %d %d %d %d\n",name,ci,co,pixels,shift,raw_mode,int16_mode);
        if (scanned == 7) begin
            folder = {VECTOR_ROOT,name,"/"};
            input_words = ((ci+15)/16)*pixels;
            outputs_total = ((co+3)/4)*pixels;
            weight_words = ((co+3)/4)*((ci+15)/16); param_words = (co+3)/4;
            $readmemh({folder,"stimulus.hex"},inputs,0,input_words-1);
            $readmemh({folder,"weights.hex"},weights,0,weight_words-1);
            $readmemh({folder,"params.hex"},params,0,param_words-1);
            $readmemh({folder,"mac.hex"},expected_mac,0,outputs_total-1);
            $readmemh({folder,"golden.hex"},expected_q,0,outputs_total-1);
            $readmemh({folder,"tags.hex"},expected_tags,0,outputs_total-1);
            $readmemh({folder,"requests.hex"},expected_requests,0,input_words-1);
            @(negedge clk);
            got = 0; requests = 0; active = 1'b1; pending = 1'b0; stalled = 1'b0;
            io_cfg_i_payload_cin = ci; io_cfg_i_payload_cout = co; io_cfg_i_payload_pixels = pixels;
            io_cfg_i_payload_shift = shift; io_cfg_i_payload_raw = raw_mode; io_cfg_i_payload_int16 = int16_mode;
            io_cfg_i_valid = 1'b1;
            do @(posedge clk); while (io_cfg_i_ready !== 1'b1);
            @(negedge clk); io_cfg_i_valid = 1'b0;
            wi = 0; pi = 0;
            while (wi < weight_words || pi < param_words) begin
                @(negedge clk);
                io_weights_i_valid = wi < weight_words && cycle % 5 != 0;
                io_weights_i_payload = weights[wi];
                io_params_i_valid = pi < param_words && cycle % 3 != 0;
                io_params_i_payload = params[pi];
                @(posedge clk);
                if (io_weights_i_valid && io_weights_i_ready) wi = wi + 1;
                if (io_params_i_valid && io_params_i_ready) pi = pi + 1;
            end
            @(negedge clk); io_weights_i_valid = 1'b0; io_params_i_valid = 1'b0; io_start_i_valid = 1'b1;
            do @(posedge clk); while (io_start_i_ready !== 1'b1);
            started = cycle;
            @(negedge clk); io_start_i_valid = 1'b0;
            do @(negedge clk); while (io_done_o !== 1'b1);
            if (got != outputs_total || requests != input_words || pending) begin
                $error("PW totals case=%s outputs=%0d/%0d reads=%0d/%0d",name,got,outputs_total,requests,input_words); $stop;
            end
            $display("[CASE PASSED] PW %s outputs=%0d run_cycles=%0d cycle_equivalent=1",name,got,cycle-started);
            $fdisplay(report,"PW %s outputs=%0d run_cycles=%0d cycle_equivalent=1",name,got,cycle-started);
            cases_done = cases_done + 1;
            repeat (3) @(negedge clk);
            active = 1'b0;
        end
    end
    if (cases_done != 11 || read_stalls == 0 || output_stalls == 0) $fatal(1,"PW incomplete coverage");
    $display("[TB PASSED] PW cases=%0d read_stalls=%0d output_stalls=%0d exact-cycle-equivalence",cases_done,read_stalls,output_stalls);
    $fdisplay(report,"[TB PASSED] PW cases=%0d read_stalls=%0d output_stalls=%0d",cases_done,read_stalls,output_stalls);
    $fclose(csv); $fclose(report); $fclose(manifest); $finish;
end
initial begin
    repeat (2000000) @(posedge clk);
    $error("PW watchdog case=%s cycle=%0d",name,cycle); $stop;
end
'''

OP_BODY = r'''
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
            $error("op12 cycle-equivalence control case=%s cycle=%0d",name,cycle); $stop;
        end
        if (mem_valid_o && {mem_write_o,mem_addr_o,mem_mask_o} !== {mem_write_o_before,mem_addr_o_before,mem_mask_o_before}) begin
            $error("op12 cycle-equivalence memory case=%s cycle=%0d",name,cycle); $stop;
        end
        if (stalled && (!mem_valid_o || {mem_write_o,mem_addr_o,mem_mask_o,mem_data_o} !== held)) begin
            $error("op12 memory changed under backpressure cycle=%0d",cycle); $stop;
        end
        stalled=mem_valid_o && !mem_ready_i;
        held={mem_write_o,mem_addr_o,mem_mask_o,mem_data_o};
        if (stalled) mem_stalls=mem_stalls+1;
        if (dut.u_bank.p12_read_en_w && dut.u_bank.p12_read_addr_w>p12_max_addr) p12_max_addr=dut.u_bank.p12_read_addr_w;
        if (dut.u_bank.p12_add_valid_r) begin
            if (dut.u_bank.p12_add_a_data_w !== baseline.u_bank.p12_add_a_data_r ||
                dut.u_bank.p12_add_b_data_w !== baseline.u_bank.p12_add_b_data_r) begin
                $error("op12 URAM assembly cycle=%0d pixel=%0d group=%0d",cycle,dut.u_bank.p12_add_pixel_r,dut.u_bank.add_group_i); $stop;
            end
            add_checks=add_checks+1;
        end
        if (pending && response_delay>0) response_delay=response_delay-1;
        if (mem_rsp_valid_i && mem_rsp_ready_o) pending=1'b0;
        if (mem_valid_o && mem_ready_i) begin
            if (pending) begin $error("op12 overlapping memory request"); $stop; end
            if (mem_write_o) begin
                for (integer b=0;b<32;b=b+1) if (mem_mask_o[b]) begin
                    if (mem_addr_o+b<OUT_BASE || mem_addr_o+b>=OUT_BASE+out_bytes ||
                        mem_data_o[b*8+:8] !== mem_data_o_before[b*8+:8]) begin
                        $error("op12 invalid/different write case=%s addr=%h lane=%0d",name,mem_addr_o,b); $stop;
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
                $error("op12 descriptor case=%s ok=%b bytes=%0d expected=%0d",name,descriptor_ok_o,candidate_bytes_o,out_bytes); $stop;
            end
            @(negedge clk_i); run_valid_i=1'b1;
            do @(posedge clk_i); while (run_ready_o !== 1'b1);
            started=cycle;
            @(negedge clk_i); run_valid_i=1'b0;
            do @(negedge clk_i); while (done_o !== 1'b1);
            if (error_o !== 1'b0 || aborted_o !== 1'b0 || result_bytes_o !== out_bytes || mac_bytes_o !== 32'd0 || pending) begin
                $error("op12 status case=%s error=%b aborted=%b bytes=%0d",name,error_o,aborted_o,result_bytes_o); $stop;
            end
            for (integer b=0;b<out_bytes;b=b+1) if (seen[b] !== 1'b1 || actual[b] !== golden[b]) begin
                $error("op12 Golden case=%s byte=%0d seen=%b expected=%h actual=%h",name,b,seen[b],golden[b],actual[b]); $stop;
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
    $error("op12 watchdog case=%s cycle=%0d state=%0d",name,cycle,dut.state_r); $stop;
end
'''


if __name__ == "__main__":
    for top, module, path, body in (
        ("tb_rtl_slim_pw", "PwMac", SOURCES / "PW/pwmac.v", PW_BODY),
        ("tb_rtl_slim_op12", "op_engine", SOURCES / "control/op_engine.sv", OP_BODY),
    ):
        (HERE / f"{top}.sv").write_text(
            "`timescale 1ns/1ps\nmodule " + top + ";\n" + pair(module, path)
            + body.replace("$stop;", "$fflush(csv); $fflush(report); $stop;") + "\nendmodule\n",
            encoding="utf-8",
        )
        print(f"Generated {top}.sv")
