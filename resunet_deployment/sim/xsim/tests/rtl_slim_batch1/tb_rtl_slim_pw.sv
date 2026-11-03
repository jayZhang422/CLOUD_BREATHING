`timescale 1ns/1ps
module tb_rtl_slim_pw;
logic io_cfg_i_valid;
logic io_cfg_i_ready;
logic io_cfg_i_ready_before;
logic [9:0] io_cfg_i_payload_cin;
logic [9:0] io_cfg_i_payload_cout;
logic [18:0] io_cfg_i_payload_pixels;
logic [5:0] io_cfg_i_payload_shift;
logic io_cfg_i_payload_raw;
logic io_cfg_i_payload_int16;
logic io_weights_i_valid;
logic io_weights_i_ready;
logic io_weights_i_ready_before;
logic [511:0] io_weights_i_payload;
logic io_params_i_valid;
logic io_params_i_ready;
logic io_params_i_ready_before;
logic [511:0] io_params_i_payload;
logic io_start_i_valid;
logic io_start_i_ready;
logic io_start_i_ready_before;
logic io_start_i_payload;
logic io_busy_o;
logic io_busy_o_before;
logic io_done_o;
logic io_done_o_before;
logic io_rd_o_valid;
logic io_rd_o_valid_before;
logic io_rd_o_ready;
logic [31:0] io_rd_o_payload;
logic [31:0] io_rd_o_payload_before;
logic io_rsp_i_valid;
logic io_rsp_i_ready;
logic io_rsp_i_ready_before;
logic [127:0] io_rsp_i_payload;
logic io_output_o_valid;
logic io_output_o_valid_before;
logic io_output_o_ready;
logic [18:0] io_output_o_payload_pixel;
logic [18:0] io_output_o_payload_pixel_before;
logic [6:0] io_output_o_payload_group;
logic [6:0] io_output_o_payload_group_before;
logic [3:0] io_output_o_payload_mask;
logic [3:0] io_output_o_payload_mask_before;
logic io_output_o_payload_last;
logic io_output_o_payload_last_before;
logic io_output_o_payload_raw;
logic io_output_o_payload_raw_before;
logic io_output_o_payload_int16;
logic io_output_o_payload_int16_before;
logic [31:0] io_output_o_payload_mac_0;
logic [31:0] io_output_o_payload_mac_0_before;
logic [31:0] io_output_o_payload_mac_1;
logic [31:0] io_output_o_payload_mac_1_before;
logic [31:0] io_output_o_payload_mac_2;
logic [31:0] io_output_o_payload_mac_2_before;
logic [31:0] io_output_o_payload_mac_3;
logic [31:0] io_output_o_payload_mac_3_before;
logic [15:0] io_output_o_payload_q_0;
logic [15:0] io_output_o_payload_q_0_before;
logic [15:0] io_output_o_payload_q_1;
logic [15:0] io_output_o_payload_q_1_before;
logic [15:0] io_output_o_payload_q_2;
logic [15:0] io_output_o_payload_q_2_before;
logic [15:0] io_output_o_payload_q_3;
logic [15:0] io_output_o_payload_q_3_before;
logic clk;
logic resetn;
PwMac dut (
    .io_cfg_i_valid(io_cfg_i_valid),
    .io_cfg_i_ready(io_cfg_i_ready),
    .io_cfg_i_payload_cin(io_cfg_i_payload_cin),
    .io_cfg_i_payload_cout(io_cfg_i_payload_cout),
    .io_cfg_i_payload_pixels(io_cfg_i_payload_pixels),
    .io_cfg_i_payload_shift(io_cfg_i_payload_shift),
    .io_cfg_i_payload_raw(io_cfg_i_payload_raw),
    .io_cfg_i_payload_int16(io_cfg_i_payload_int16),
    .io_weights_i_valid(io_weights_i_valid),
    .io_weights_i_ready(io_weights_i_ready),
    .io_weights_i_payload(io_weights_i_payload),
    .io_params_i_valid(io_params_i_valid),
    .io_params_i_ready(io_params_i_ready),
    .io_params_i_payload(io_params_i_payload),
    .io_start_i_valid(io_start_i_valid),
    .io_start_i_ready(io_start_i_ready),
    .io_start_i_payload(io_start_i_payload),
    .io_busy_o(io_busy_o),
    .io_done_o(io_done_o),
    .io_rd_o_valid(io_rd_o_valid),
    .io_rd_o_ready(io_rd_o_ready),
    .io_rd_o_payload(io_rd_o_payload),
    .io_rsp_i_valid(io_rsp_i_valid),
    .io_rsp_i_ready(io_rsp_i_ready),
    .io_rsp_i_payload(io_rsp_i_payload),
    .io_output_o_valid(io_output_o_valid),
    .io_output_o_ready(io_output_o_ready),
    .io_output_o_payload_pixel(io_output_o_payload_pixel),
    .io_output_o_payload_group(io_output_o_payload_group),
    .io_output_o_payload_mask(io_output_o_payload_mask),
    .io_output_o_payload_last(io_output_o_payload_last),
    .io_output_o_payload_raw(io_output_o_payload_raw),
    .io_output_o_payload_int16(io_output_o_payload_int16),
    .io_output_o_payload_mac_0(io_output_o_payload_mac_0),
    .io_output_o_payload_mac_1(io_output_o_payload_mac_1),
    .io_output_o_payload_mac_2(io_output_o_payload_mac_2),
    .io_output_o_payload_mac_3(io_output_o_payload_mac_3),
    .io_output_o_payload_q_0(io_output_o_payload_q_0),
    .io_output_o_payload_q_1(io_output_o_payload_q_1),
    .io_output_o_payload_q_2(io_output_o_payload_q_2),
    .io_output_o_payload_q_3(io_output_o_payload_q_3),
    .clk(clk),
    .resetn(resetn)
);
PwMac_before baseline (
    .io_cfg_i_valid(io_cfg_i_valid),
    .io_cfg_i_ready(io_cfg_i_ready_before),
    .io_cfg_i_payload_cin(io_cfg_i_payload_cin),
    .io_cfg_i_payload_cout(io_cfg_i_payload_cout),
    .io_cfg_i_payload_pixels(io_cfg_i_payload_pixels),
    .io_cfg_i_payload_shift(io_cfg_i_payload_shift),
    .io_cfg_i_payload_raw(io_cfg_i_payload_raw),
    .io_cfg_i_payload_int16(io_cfg_i_payload_int16),
    .io_weights_i_valid(io_weights_i_valid),
    .io_weights_i_ready(io_weights_i_ready_before),
    .io_weights_i_payload(io_weights_i_payload),
    .io_params_i_valid(io_params_i_valid),
    .io_params_i_ready(io_params_i_ready_before),
    .io_params_i_payload(io_params_i_payload),
    .io_start_i_valid(io_start_i_valid),
    .io_start_i_ready(io_start_i_ready_before),
    .io_start_i_payload(io_start_i_payload),
    .io_busy_o(io_busy_o_before),
    .io_done_o(io_done_o_before),
    .io_rd_o_valid(io_rd_o_valid_before),
    .io_rd_o_ready(io_rd_o_ready),
    .io_rd_o_payload(io_rd_o_payload_before),
    .io_rsp_i_valid(io_rsp_i_valid),
    .io_rsp_i_ready(io_rsp_i_ready_before),
    .io_rsp_i_payload(io_rsp_i_payload),
    .io_output_o_valid(io_output_o_valid_before),
    .io_output_o_ready(io_output_o_ready),
    .io_output_o_payload_pixel(io_output_o_payload_pixel_before),
    .io_output_o_payload_group(io_output_o_payload_group_before),
    .io_output_o_payload_mask(io_output_o_payload_mask_before),
    .io_output_o_payload_last(io_output_o_payload_last_before),
    .io_output_o_payload_raw(io_output_o_payload_raw_before),
    .io_output_o_payload_int16(io_output_o_payload_int16_before),
    .io_output_o_payload_mac_0(io_output_o_payload_mac_0_before),
    .io_output_o_payload_mac_1(io_output_o_payload_mac_1_before),
    .io_output_o_payload_mac_2(io_output_o_payload_mac_2_before),
    .io_output_o_payload_mac_3(io_output_o_payload_mac_3_before),
    .io_output_o_payload_q_0(io_output_o_payload_q_0_before),
    .io_output_o_payload_q_1(io_output_o_payload_q_1_before),
    .io_output_o_payload_q_2(io_output_o_payload_q_2_before),
    .io_output_o_payload_q_3(io_output_o_payload_q_3_before),
    .clk(clk),
    .resetn(resetn)
);

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
            $error("PW cycle-equivalence control case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
        end
        if (io_rd_o_valid && io_rd_o_payload !== io_rd_o_payload_before) begin
            $error("PW cycle-equivalence address case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
        end
        if (io_output_o_valid && {tag,mac,q,io_output_o_payload_raw,io_output_o_payload_int16} !==
            {tag_before,mac_before,q_before,io_output_o_payload_raw_before,io_output_o_payload_int16_before}) begin
            $error("PW cycle-equivalence payload case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
        end
        if (stalled && (!io_output_o_valid || {tag,mac,q} !== held)) begin
            $error("PW backpressure data changed case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
        end
        stalled = io_output_o_valid && !io_output_o_ready;
        held = {tag,mac,q};
        if (io_output_o_valid && !io_output_o_ready) output_stalls = output_stalls + 1;
        if (io_rd_o_valid && !io_rd_o_ready) read_stalls = read_stalls + 1;
        if (pending && response_delay > 0) response_delay = response_delay - 1;
        if (io_rsp_i_valid && io_rsp_i_ready) pending = 1'b0;
        if (io_rd_o_valid && io_rd_o_ready) begin
            if (pending || requests >= input_words || io_rd_o_payload !== expected_requests[requests]) begin
                $error("PW read request case=%s index=%0d addr=%0d expected=%0d",name,requests,io_rd_o_payload,expected_requests[requests]); $fflush(csv); $fflush(report); $stop;
            end
            pending_data = inputs[io_rd_o_payload];
            pending = 1'b1;
            response_delay = cycle % 4 + 1;
            requests = requests + 1;
        end
        if (io_output_o_valid && io_output_o_ready) begin
            if (got >= outputs_total || tag !== expected_tags[got] || mac !== expected_mac[got] || q !== expected_q[got] ||
                io_output_o_payload_raw !== io_cfg_i_payload_raw || io_output_o_payload_int16 !== io_cfg_i_payload_int16) begin
                $error("PW Golden case=%s index=%0d tag=%h expected_tag=%h mac=%h expected_mac=%h q=%h expected_q=%h",name,got,tag,expected_tags[got],mac,expected_mac[got],q,expected_q[got]); $fflush(csv); $fflush(report); $stop;
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
                $error("PW totals case=%s outputs=%0d/%0d reads=%0d/%0d",name,got,outputs_total,requests,input_words); $fflush(csv); $fflush(report); $stop;
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
    $error("PW watchdog case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
end

endmodule
