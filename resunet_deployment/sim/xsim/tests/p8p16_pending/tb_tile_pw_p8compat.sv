`timescale 1ns/1ps
interface tile_pw_if_p8compat;
logic io_cfg_i_valid;
logic io_cfg_i_ready;
logic [9:0] io_cfg_i_payload_cin;
logic [9:0] io_cfg_i_payload_cout;
logic [18:0] io_cfg_i_payload_pixels;
logic [5:0] io_cfg_i_payload_shift;
logic io_cfg_i_payload_raw;
logic io_cfg_i_payload_int16;
logic io_weights_i_valid;
logic io_weights_i_ready;
logic [511:0] io_weights_i_payload;
logic io_params_i_valid;
logic io_params_i_ready;
logic [511:0] io_params_i_payload;
logic io_start_i_valid;
logic io_start_i_ready;
logic io_start_i_payload;
logic io_busy_o;
logic io_done_o;
logic io_rd_o_valid;
logic io_rd_o_ready;
logic [31:0] io_rd_o_payload;
logic io_rsp_i_valid;
logic io_rsp_i_ready;
logic [127:0] io_rsp_i_payload;
logic io_output_o_valid;
logic io_output_o_ready;
logic [18:0] io_output_o_payload_pixel;
logic [6:0] io_output_o_payload_group;
logic [15:0] io_output_o_payload_mask;
logic io_output_o_payload_last;
logic io_output_o_payload_raw;
logic io_output_o_payload_int16;
logic [31:0] io_output_o_payload_mac_0;
logic [31:0] io_output_o_payload_mac_1;
logic [31:0] io_output_o_payload_mac_2;
logic [31:0] io_output_o_payload_mac_3;
logic [15:0] io_output_o_payload_q_0;
logic [15:0] io_output_o_payload_q_1;
logic [15:0] io_output_o_payload_q_2;
logic [15:0] io_output_o_payload_q_3;
logic clk;
logic resetn;
endinterface
module tile_pw_driver_p8compat #(parameter integer SIDE=0, parameter bit LONG_STALL=0, RESTART=0)(tile_pw_if_p8compat bus, output logic finished_o);
localparam string BATCH3_ROOT = "sim/xsim/tests/rtl_slim_batch3/";
localparam string VECTOR_ROOT = "sim/standalone/op/pw/verification/stage3_pe16/vectors/";
localparam string CHECK_ROOT = "sim/xsim/tests/rtl_slim_batch1/";
logic [127:0] inputs [0:65535], expected_mac [0:65535];
logic [511:0] weights [0:6143], params [0:127];
logic [63:0] expected_q [0:65535];
logic [31:0] expected_tags [0:65535], expected_requests [0:65535];
wire [127:0] mac = {bus.io_output_o_payload_mac_3,bus.io_output_o_payload_mac_2,bus.io_output_o_payload_mac_1,bus.io_output_o_payload_mac_0};
wire [63:0] q = {bus.io_output_o_payload_q_3,bus.io_output_o_payload_q_2,bus.io_output_o_payload_q_1,bus.io_output_o_payload_q_0};
wire [31:0] tag = {1'b0,bus.io_output_o_payload_last,bus.io_output_o_payload_mask[3:0],bus.io_output_o_payload_group,bus.io_output_o_payload_pixel};
integer cycle = 0, got = 0, requests = 0, outputs_total = 0;
integer csv, report, manifest,
        cancelled=0, scanned, ci, co, pixels, shift, raw_mode, int16_mode;
integer wi, pi, weight_words, param_words, input_words, started, cases_done = 0, completed_runs=0;
integer response_delay = 0, read_stalls = 0, output_stalls = 0;
logic pending = 1'b0, active = 1'b0, stalled = 1'b0;
logic [223:0] held;
logic rd_stalled=0;
logic [31:0] held_rd;
logic [127:0] pending_data;
string name, folder;
always #4 bus.clk = ~bus.clk;

// 负沿驱动；正沿仅采样已稳定的握手和载荷。
always @(negedge bus.clk) begin
    if (!bus.resetn) begin
        bus.io_rd_o_ready = 1'b0;
        bus.io_rsp_i_valid = 1'b0;
        bus.io_output_o_ready = 1'b0;
    end else begin
        bus.io_rd_o_ready = !pending && cycle % 7 != 2;
        bus.io_output_o_ready = LONG_STALL ? cycle % 211 >= 75 : cycle % 17 >= 5;
        bus.io_rsp_i_valid = pending && response_delay == 0;
        bus.io_rsp_i_payload = pending_data;
    end
end

always @(posedge bus.clk) begin
    cycle = cycle + 1;
    if (bus.resetn && active) begin
        if (rd_stalled && (!bus.io_rd_o_valid || bus.io_rd_o_payload !== held_rd)) begin
            $error("PW read payload changed under backpressure cycle=%0d",cycle); $fflush(csv); $stop;
        end
        rd_stalled = bus.io_rd_o_valid && !bus.io_rd_o_ready;
        held_rd = bus.io_rd_o_payload;
        if (stalled && (!bus.io_output_o_valid || {tag,mac,q} !== held)) begin
            $error("PW backpressure data changed case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
        end
        stalled = bus.io_output_o_valid && !bus.io_output_o_ready;
        held = {tag,mac,q};
        if (bus.io_output_o_valid && !bus.io_output_o_ready) output_stalls = output_stalls + 1;
        if (bus.io_rd_o_valid && !bus.io_rd_o_ready) read_stalls = read_stalls + 1;
        if (pending && response_delay > 0) response_delay = response_delay - 1;
        if (bus.io_rsp_i_valid && bus.io_rsp_i_ready) pending = 1'b0;
        if (bus.io_rd_o_valid && bus.io_rd_o_ready) begin
            if (pending || requests >= input_words || bus.io_rd_o_payload !== expected_requests[requests]) begin
                $error("PW read request case=%s index=%0d addr=%0d expected=%0d",name,requests,bus.io_rd_o_payload,expected_requests[requests]); $fflush(csv); $fflush(report); $stop;
            end
            pending_data = inputs[bus.io_rd_o_payload];
            pending = 1'b1;
            response_delay = cycle % 4 + 1;
            requests = requests + 1;
        end
        if (bus.io_output_o_valid && bus.io_output_o_ready) begin
            if (got >= outputs_total || tag !== expected_tags[got] || mac !== expected_mac[got] || q !== expected_q[got] ||
                bus.io_output_o_payload_raw !== bus.io_cfg_i_payload_raw || bus.io_output_o_payload_int16 !== bus.io_cfg_i_payload_int16) begin
                $error("PW Golden case=%s index=%0d tag=%h expected_tag=%h mac=%h expected_mac=%h q=%h expected_q=%h",name,got,tag,expected_tags[got],mac,expected_mac[got],q,expected_q[got]); $fflush(csv); $fflush(report); $stop;
            end
            got = got + 1;
        end
    end
    if (!finished_o) $fdisplay(csv,"%0d,%s,%b,%b,%h,%b,%b,%b,%b,%h,%h,%h,%0d,%0d",cycle,name,bus.io_rd_o_valid,bus.io_rd_o_ready,bus.io_rd_o_payload,bus.io_rsp_i_valid,bus.io_rsp_i_ready,bus.io_output_o_valid,bus.io_output_o_ready,tag,mac,q,got,requests);
end

initial begin
    finished_o=1'b0; bus.clk = 1'b0; bus.resetn = 1'b0;
    bus.io_cfg_i_valid = 1'b0; bus.io_weights_i_valid = 1'b0; bus.io_params_i_valid = 1'b0;
    bus.io_start_i_valid = 1'b0; bus.io_start_i_payload = 1'b1;
    bus.io_cfg_i_payload_cin = 10'd1; bus.io_cfg_i_payload_cout = 10'd1; bus.io_cfg_i_payload_pixels = 19'd1;
    bus.io_cfg_i_payload_shift = 6'd0; bus.io_cfg_i_payload_raw = 1'b0; bus.io_cfg_i_payload_int16 = 1'b0;
    bus.io_weights_i_payload = 512'd0; bus.io_params_i_payload = 512'd0; bus.io_rsp_i_payload = 128'd0;
    if (SIDE == 0) csv = $fopen("sim_trace_project.csv","w");
    else csv = $fopen("sim_trace_skip.csv","w");
    if (!finished_o) $fdisplay(csv,"cycle,case,rd_valid,rd_ready,rd_addr,rsp_valid,rsp_ready,out_valid,out_ready,tag,mac,q,outputs,requests");
    if (SIDE == 0) report = $fopen("checks_project.txt","w");
    else report = $fopen("checks_skip.txt","w");
    if (SIDE == 0) manifest = $fopen({BATCH3_ROOT,"pw_project.txt"},"r");
    else manifest = $fopen({BATCH3_ROOT,"pw_skip.txt"},"r");
    if (!manifest) $fatal(1,"Cannot open PW manifest");
    repeat (6) @(negedge bus.clk);
    bus.resetn = 1'b1;
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
            @(negedge bus.clk);
            got = 0; requests = 0; active = 1'b1; pending = 1'b0; stalled = 1'b0;
            bus.io_cfg_i_payload_cin = ci; bus.io_cfg_i_payload_cout = co; bus.io_cfg_i_payload_pixels = pixels;
            bus.io_cfg_i_payload_shift = shift; bus.io_cfg_i_payload_raw = raw_mode; bus.io_cfg_i_payload_int16 = int16_mode;
            bus.io_cfg_i_valid = 1'b1;
            do @(posedge bus.clk); while (bus.io_cfg_i_ready !== 1'b1);
            @(negedge bus.clk); bus.io_cfg_i_valid = 1'b0;
            wi = 0; pi = 0;
            while (wi < weight_words || pi < param_words) begin
                @(negedge bus.clk);
                bus.io_weights_i_valid = wi < weight_words && cycle % 5 != 0;
                bus.io_weights_i_payload = weights[wi];
                bus.io_params_i_valid = pi < param_words && cycle % 3 != 0;
                bus.io_params_i_payload = params[pi];
                @(posedge bus.clk);
                if (bus.io_weights_i_valid && bus.io_weights_i_ready) wi = wi + 1;
                if (bus.io_params_i_valid && bus.io_params_i_ready) pi = pi + 1;
            end
            @(negedge bus.clk); bus.io_weights_i_valid = 1'b0; bus.io_params_i_valid = 1'b0; bus.io_start_i_valid = 1'b0;
            if (RESTART && !cancelled) begin
                bus.io_start_i_valid=1;
                do @(posedge bus.clk); while (bus.io_start_i_ready !== 1'b1);
                @(negedge bus.clk); bus.io_start_i_valid=0;
                wait(requests>=5);
                @(negedge bus.clk); bus.resetn=0; active=0; pending=0; stalled=0; rd_stalled=0;
                repeat(6) @(negedge bus.clk);
                bus.resetn=1; cancelled=1;
                scanned=$rewind(manifest);
                continue;
            end
            for (int replay=0; replay < ((RESTART && cases_done==0) ? 2 : 1); replay++) begin
            @(negedge bus.clk); got=0; requests=0; pending=0; stalled=0; rd_stalled=0;
            bus.io_start_i_valid = 1'b1;
            do @(posedge bus.clk); while (bus.io_start_i_ready !== 1'b1);
            started = cycle;
            @(negedge bus.clk); bus.io_start_i_valid = 1'b0;
            do @(negedge bus.clk); while (bus.io_done_o !== 1'b1);
            if (got != outputs_total || requests != input_words || pending) begin
                $error("PW totals case=%s outputs=%0d/%0d reads=%0d/%0d",name,got,outputs_total,requests,input_words); $fflush(csv); $fflush(report); $stop;
            end
            completed_runs++;
            $display("[CASE PASSED] PW %s outputs=%0d run_cycles=%0d side=%0d",name,got,cycle-started,SIDE);
            $fdisplay(report,"PW %s outputs=%0d run_cycles=%0d side=%0d",name,got,cycle-started,SIDE);
            repeat (3) @(negedge bus.clk);
            end
            cases_done = cases_done + 1;
            active = 1'b0;
        end
    end
    if (completed_runs != (RESTART ? 12 : 11) || (RESTART && cancelled!=1)) begin
        $error("Reset/restart coverage missing runs=%0d cancelled=%0d",completed_runs,cancelled); $stop;
    end
    $display("[COVERAGE] side=%0d completed_runs=%0d reset_during_prefetch=%0d",SIDE,completed_runs,cancelled);
    if (cases_done != 11 || read_stalls == 0 || output_stalls == 0) $fatal(1,"PW incomplete coverage");
    $display("[DRIVER PASSED] PW cases=%0d read_stalls=%0d output_stalls=%0d shared-dot-Golden",cases_done,read_stalls,output_stalls);
    $fdisplay(report,"[DRIVER PASSED] PW cases=%0d read_stalls=%0d output_stalls=%0d",cases_done,read_stalls,output_stalls);
    $fclose(csv); $fclose(report); $fclose(manifest); finished_o=1'b1;
end
initial begin
    repeat (2000000) @(posedge bus.clk);
    $error("PW watchdog case=%s cycle=%0d",name,cycle); $fflush(csv); $fflush(report); $stop;
end

endmodule
module tb_tile_pw_p8compat #(parameter bit LONG_STALL=0, RESTART=0);
tile_pw_if_p8compat project();
tile_pw_if_p8compat skip();
wire project_finished, skip_finished;
wire [31:0] contention;
tile_pw_driver_p8compat #(.SIDE(0),.LONG_STALL(LONG_STALL),.RESTART(RESTART)) driver_project(project,project_finished);

generate if (!RESTART) begin : g_skip_driver
tile_pw_driver_p8compat #(.SIDE(1),.LONG_STALL(LONG_STALL),.RESTART(0)) driver_skip(skip,skip_finished);
end else begin : g_skip_idle
assign skip_finished=1'b1;
assign skip.clk=project.clk;
assign skip.resetn=1'b1;
assign skip.io_cfg_i_valid=1'b0;
assign skip.io_cfg_i_payload_cin=10'd1;
assign skip.io_cfg_i_payload_cout=10'd1;
assign skip.io_cfg_i_payload_pixels=19'd1;
assign skip.io_cfg_i_payload_shift=6'd0;
assign skip.io_cfg_i_payload_raw=1'b0;
assign skip.io_cfg_i_payload_int16=1'b0;
assign skip.io_weights_i_valid=1'b0;
assign skip.io_weights_i_payload=512'd0;
assign skip.io_params_i_valid=1'b0;
assign skip.io_params_i_payload=512'd0;
assign skip.io_start_i_valid=1'b0;
assign skip.io_start_i_payload=1'b1;
assign skip.io_rd_o_ready=1'b0;
assign skip.io_rsp_i_valid=1'b0;
assign skip.io_rsp_i_payload=128'd0;
assign skip.io_output_o_ready=1'b1;
end endgenerate

generate if (1) begin : g_shared
PwMacShared dut (
  .io_project_cfg_i_valid(project.io_cfg_i_valid),
  .io_project_cfg_i_ready(project.io_cfg_i_ready),
  .io_project_cfg_i_payload_cin(project.io_cfg_i_payload_cin),
  .io_project_cfg_i_payload_cout(project.io_cfg_i_payload_cout),
  .io_project_cfg_i_payload_pixels(project.io_cfg_i_payload_pixels),
  .io_project_cfg_i_payload_shift(project.io_cfg_i_payload_shift),
  .io_project_cfg_i_payload_raw(project.io_cfg_i_payload_raw),
  .io_project_cfg_i_payload_int16(project.io_cfg_i_payload_int16),
  .io_project_cfg_i_payload_legacyP4(1'b1),
  .io_project_weights_i_valid(project.io_weights_i_valid),
  .io_project_weights_i_ready(project.io_weights_i_ready),
  .io_project_weights_i_payload(project.io_weights_i_payload),
  .io_project_params_i_valid(project.io_params_i_valid),
  .io_project_params_i_ready(project.io_params_i_ready),
  .io_project_params_i_payload(project.io_params_i_payload),
  .io_project_start_i_valid(project.io_start_i_valid),
  .io_project_start_i_ready(project.io_start_i_ready),
  .io_project_start_i_payload(project.io_start_i_payload),
  .io_project_busy_o(project.io_busy_o),
  .io_project_done_o(project.io_done_o),
  .io_project_rd_o_valid(project.io_rd_o_valid),
  .io_project_rd_o_ready(project.io_rd_o_ready),
  .io_project_rd_o_payload(project.io_rd_o_payload),
  .io_project_rsp_i_valid(project.io_rsp_i_valid),
  .io_project_rsp_i_ready(project.io_rsp_i_ready),
  .io_project_rsp_i_payload(project.io_rsp_i_payload),
  .io_project_output_o_valid(project.io_output_o_valid),
  .io_project_output_o_ready(project.io_output_o_ready),
  .io_project_output_o_payload_pixel(project.io_output_o_payload_pixel),
  .io_project_output_o_payload_group(project.io_output_o_payload_group),
  .io_project_output_o_payload_mask(project.io_output_o_payload_mask),
  .io_project_output_o_payload_last(project.io_output_o_payload_last),
  .io_project_output_o_payload_raw(project.io_output_o_payload_raw),
  .io_project_output_o_payload_int16(project.io_output_o_payload_int16),
  .io_project_output_o_payload_mac_0(project.io_output_o_payload_mac_0),
  .io_project_output_o_payload_mac_1(project.io_output_o_payload_mac_1),
  .io_project_output_o_payload_mac_2(project.io_output_o_payload_mac_2),
  .io_project_output_o_payload_mac_3(project.io_output_o_payload_mac_3),
  .io_project_output_o_payload_q_0(project.io_output_o_payload_q_0),
  .io_project_output_o_payload_q_1(project.io_output_o_payload_q_1),
  .io_project_output_o_payload_q_2(project.io_output_o_payload_q_2),
  .io_project_output_o_payload_q_3(project.io_output_o_payload_q_3),
  .io_skip_cfg_i_valid(skip.io_cfg_i_valid),
  .io_skip_cfg_i_ready(skip.io_cfg_i_ready),
  .io_skip_cfg_i_payload_cin(skip.io_cfg_i_payload_cin),
  .io_skip_cfg_i_payload_cout(skip.io_cfg_i_payload_cout),
  .io_skip_cfg_i_payload_pixels(skip.io_cfg_i_payload_pixels),
  .io_skip_cfg_i_payload_shift(skip.io_cfg_i_payload_shift),
  .io_skip_cfg_i_payload_raw(skip.io_cfg_i_payload_raw),
  .io_skip_cfg_i_payload_int16(skip.io_cfg_i_payload_int16),
  .io_skip_cfg_i_payload_legacyP4(1'b1),
  .io_skip_weights_i_valid(skip.io_weights_i_valid),
  .io_skip_weights_i_ready(skip.io_weights_i_ready),
  .io_skip_weights_i_payload(skip.io_weights_i_payload),
  .io_skip_params_i_valid(skip.io_params_i_valid),
  .io_skip_params_i_ready(skip.io_params_i_ready),
  .io_skip_params_i_payload(skip.io_params_i_payload),
  .io_skip_start_i_valid(skip.io_start_i_valid),
  .io_skip_start_i_ready(skip.io_start_i_ready),
  .io_skip_start_i_payload(skip.io_start_i_payload),
  .io_skip_busy_o(skip.io_busy_o),
  .io_skip_done_o(skip.io_done_o),
  .io_skip_rd_o_valid(skip.io_rd_o_valid),
  .io_skip_rd_o_ready(skip.io_rd_o_ready),
  .io_skip_rd_o_payload(skip.io_rd_o_payload),
  .io_skip_rsp_i_valid(skip.io_rsp_i_valid),
  .io_skip_rsp_i_ready(skip.io_rsp_i_ready),
  .io_skip_rsp_i_payload(skip.io_rsp_i_payload),
  .io_skip_output_o_valid(skip.io_output_o_valid),
  .io_skip_output_o_ready(skip.io_output_o_ready),
  .io_skip_output_o_payload_pixel(skip.io_output_o_payload_pixel),
  .io_skip_output_o_payload_group(skip.io_output_o_payload_group),
  .io_skip_output_o_payload_mask(skip.io_output_o_payload_mask),
  .io_skip_output_o_payload_last(skip.io_output_o_payload_last),
  .io_skip_output_o_payload_raw(skip.io_output_o_payload_raw),
  .io_skip_output_o_payload_int16(skip.io_output_o_payload_int16),
  .io_skip_output_o_payload_mac_0(skip.io_output_o_payload_mac_0),
  .io_skip_output_o_payload_mac_1(skip.io_output_o_payload_mac_1),
  .io_skip_output_o_payload_mac_2(skip.io_output_o_payload_mac_2),
  .io_skip_output_o_payload_mac_3(skip.io_output_o_payload_mac_3),
  .io_skip_output_o_payload_q_0(skip.io_output_o_payload_q_0),
  .io_skip_output_o_payload_q_1(skip.io_output_o_payload_q_1),
  .io_skip_output_o_payload_q_2(skip.io_output_o_payload_q_2),
  .io_skip_output_o_payload_q_3(skip.io_output_o_payload_q_3),
  .clk(project.clk), .resetn(project.resetn && skip.resetn)
);
integer contention_count=0;
always @(posedge project.clk)
  if (project.resetn && skip.resetn && dut.project_io_dotRequest_o_valid && dut.skip_io_dotRequest_o_valid)
    contention_count=contention_count+1;
assign contention=contention_count;
end endgenerate

integer overlap_project=0, independent_project=0, serial_overlap_project=0;
always @(posedge project.clk) if (project.resetn) begin
    if (g_shared.dut.project.resultWrite_w && g_shared.dut.project.serializeActive_r &&
        g_shared.dut.project.resultWriteBank_r === g_shared.dut.project.resultSerialBank_r) begin
        $error("Result RAM bank overwritten during serialization: project"); $stop;
    end
    if (g_shared.dut.project.request_fire && g_shared.dut.project.serializeActive_r)
        serial_overlap_project++;
    if (g_shared.dut.project.io_rsp_i_fire && g_shared.dut.project.request_fire && g_shared.dut.project.fillBank_r === g_shared.dut.project.inputBank_r) begin
        $error("Input tile RAM collision: project"); $stop;
    end
    if (g_shared.dut.project.io_rd_o_fire && (g_shared.dut.project.state_r==4 || g_shared.dut.project.state_r==5 || g_shared.dut.project.state_r==8))
        overlap_project++;
    if (project.io_output_o_valid && !project.io_output_o_ready && g_shared.dut.project.request_fire)
        independent_project++;
end

integer overlap_skip=0, independent_skip=0, serial_overlap_skip=0;
always @(posedge skip.clk) if (skip.resetn) begin
    if (g_shared.dut.skip.resultWrite_w && g_shared.dut.skip.serializeActive_r &&
        g_shared.dut.skip.resultWriteBank_r === g_shared.dut.skip.resultSerialBank_r) begin
        $error("Result RAM bank overwritten during serialization: skip"); $stop;
    end
    if (g_shared.dut.skip.request_fire && g_shared.dut.skip.serializeActive_r)
        serial_overlap_skip++;
    if (g_shared.dut.skip.io_rsp_i_fire && g_shared.dut.skip.request_fire && g_shared.dut.skip.fillBank_r === g_shared.dut.skip.inputBank_r) begin
        $error("Input tile RAM collision: skip"); $stop;
    end
    if (g_shared.dut.skip.io_rd_o_fire && (g_shared.dut.skip.state_r==4 || g_shared.dut.skip.state_r==5 || g_shared.dut.skip.state_r==8))
        overlap_skip++;
    if (skip.io_output_o_valid && !skip.io_output_o_ready && g_shared.dut.skip.request_fire)
        independent_skip++;
end

initial begin
  $dumpfile("waveform.vcd");
  $dumpvars(0,project.clk,project.resetn,project.io_rd_o_valid,project.io_output_o_valid,
              skip.io_rd_o_valid,skip.io_output_o_valid,project_finished,skip_finished);
  wait(project_finished && skip_finished);
  if (!RESTART && contention==0) begin $error("Shared arbiter contention not exercised"); $stop; end
  if (overlap_project==0 || independent_project==0 || (!RESTART && (overlap_skip==0 || independent_skip==0))) begin
    $error("Double buffer/output overlap not covered"); $stop;
  end
  $display("[OVERLAP] input project=%0d skip=%0d output project=%0d skip=%0d",
           overlap_project,overlap_skip,independent_project,independent_skip);
  if (serial_overlap_project==0 || (!RESTART && serial_overlap_skip==0)) begin
    $error("Dot/serialization overlap not covered"); $stop;
  end
  $display("[SERIAL OVERLAP] project=%0d skip=%0d",serial_overlap_project,serial_overlap_skip);
  $display("[TB PASSED] PW tile Golden runs=%0d restart=%0d contention=%0d",RESTART ? 12 : 22,RESTART,contention);
  $finish;
end
endmodule
