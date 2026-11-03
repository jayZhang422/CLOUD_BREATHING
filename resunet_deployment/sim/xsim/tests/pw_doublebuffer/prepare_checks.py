"""复用既有冻结 Golden；仅生成本批的流控/覆盖夹具，不修改主机程序。"""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
OLD = HERE.parent / "rtl_slim_batch3"

s = (OLD / "tb_batch3_pw.sv").read_text(encoding="utf-8-sig")
s = s.replace("batch3_pw_if", "tile_pw_if").replace("batch3_pw_driver", "tile_pw_driver")
s = s.replace("module tb_batch3_pw #(parameter bit SHARED=1'b1);",
              "module tb_tile_pw #(parameter bit LONG_STALL=0, RESTART=0);")
s = s.replace("#(parameter integer SIDE=0)", "#(parameter integer SIDE=0, parameter bit LONG_STALL=0, RESTART=0)")
s = s.replace("#(.SIDE(0))", "#(.SIDE(0),.LONG_STALL(LONG_STALL),.RESTART(RESTART))")
s = s.replace("#(.SIDE(1))", "#(.SIDE(1),.LONG_STALL(LONG_STALL),.RESTART(RESTART))")
s = s.replace("tile_pw_driver #(.SIDE(1),.LONG_STALL(LONG_STALL),.RESTART(RESTART)) driver_skip(skip,skip_finished);", """
generate if (!RESTART) begin : g_skip_driver
tile_pw_driver #(.SIDE(1),.LONG_STALL(LONG_STALL),.RESTART(0)) driver_skip(skip,skip_finished);
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
""")
start = s.index("end else begin : g_before")
end = s.index("end endgenerate", start)
s = s[:start] + "end endgenerate" + s[end + len("end endgenerate"):]
s = s.replace("generate if (SHARED)", "generate if (1)")
s = s.replace("if (SHARED && contention==0)", "if (!RESTART && contention==0)")
s = s.replace("SHARED=%0d, 22 Golden cases, contention=%0d\",SHARED,contention",
              "22 Golden cases, contention=%0d\",contention")
s = s.replace("bus.io_output_o_ready = cycle % 17 >= 5;",
              "bus.io_output_o_ready = LONG_STALL ? cycle % 211 >= 75 : cycle % 17 >= 5;")
s = s.replace("logic [223:0] held;", "logic [223:0] held;\nlogic rd_stalled=0;\nlogic [31:0] held_rd;")
s = s.replace("integer csv, report, manifest,", "integer csv, report, manifest,\n        cancelled=0,")
s = s.replace("cases_done = 0;", "cases_done = 0, completed_runs=0;")
s = s.replace("        if (stalled &&", """        if (rd_stalled && (!bus.io_rd_o_valid || bus.io_rd_o_payload !== held_rd)) begin
            $error("PW read payload changed under backpressure cycle=%0d",cycle); $fflush(csv); $stop;
        end
        rd_stalled = bus.io_rd_o_valid && !bus.io_rd_o_ready;
        held_rd = bus.io_rd_o_payload;
        if (stalled &&""")
start = s.index("            @(negedge bus.clk); bus.io_weights_i_valid = 1'b0;")
end = s.index("            active = 1'b0;", start)
block = s[start:end]
block = block.replace("            cases_done = cases_done + 1;\n", "")
block = block.replace("bus.io_start_i_valid = 1'b1;", """bus.io_start_i_valid = 1'b0;
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
            bus.io_start_i_valid = 1'b1;""")
s = s[:start] + block + "            end\n            cases_done = cases_done + 1;\n" + s[end:]
s = s.replace('            $display("[CASE PASSED]', '            completed_runs++;\n            $display("[CASE PASSED]')
s = s.replace('    if (cases_done != 11', '''    if (completed_runs != (RESTART ? 12 : 11) || (RESTART && cancelled!=1)) begin
        $error("Reset/restart coverage missing runs=%0d cancelled=%0d",completed_runs,cancelled); $stop;
    end
    $display("[COVERAGE] side=%0d completed_runs=%0d reset_during_prefetch=%0d",SIDE,completed_runs,cancelled);
    if (cases_done != 11''')
s = s.replace('PW two independent branches, 22 Golden cases, contention=%0d",contention',
              'PW tile Golden runs=%0d restart=%0d contention=%0d",RESTART ? 12 : 22,RESTART,contention')

monitor = ""
for branch in ("project", "skip"):
    p = "g_shared.dut." + branch
    monitor += f"""
integer overlap_{branch}=0, independent_{branch}=0;
always @(posedge {branch}.clk) if ({branch}.resetn) begin
    if ({p}.io_rsp_i_fire && {p}.request_fire && {p}.fillBank_r === {p}.inputBank_r) begin
        $error("Input tile RAM collision: {branch}"); $stop;
    end
    if ({p}.io_rd_o_fire && ({p}.state_r==4 || {p}.state_r==5 || {p}.state_r==8))
        overlap_{branch}++;
    if ({branch}.io_output_o_valid && !{branch}.io_output_o_ready && {p}.request_fire)
        independent_{branch}++;
end
"""
s = s.replace("initial begin\n  $dumpfile", monitor + "\ninitial begin\n  $dumpfile")
s = s.replace("  $display(\"[TB PASSED]", """  if (overlap_project==0 || independent_project==0 || (!RESTART && (overlap_skip==0 || independent_skip==0))) begin
    $error("Double buffer/output overlap not covered"); $stop;
  end
  $display("[OVERLAP] input project=%0d skip=%0d output project=%0d skip=%0d",
           overlap_project,overlap_skip,independent_project,independent_skip);
  $display("[TB PASSED]""")
(HERE / "tb_tile_pw.sv").write_text(s, encoding="utf-8")

# engine + 实际 IP：两种独立访存时序均逐字节比较既有 op12 Golden。
s = (HERE.parent / "rtl_slim_batch45/tb_batch45_op12.sv").read_text(encoding="utf-8-sig")
s = s[:s.index("`timescale 1ns/1ps", 30)]
s = s.replace("batch3_op12_shared", "tile_op12_runner")
s = s.replace('csv=$fopen("sim_trace_shared.csv","w"); report=$fopen("checks_shared.txt","w");',
              '''if (FAST) begin csv=$fopen("sim_trace_fast.csv","w"); report=$fopen("checks_fast.txt","w"); end
    else begin csv=$fopen("sim_trace_slow.csv","w"); report=$fopen("checks_slow.txt","w"); end''')
before = s.replace("tile_op12_runner", "tile_op12_before").replace("op_engine dut", "op_engine_tile_before dut")
before = before.replace("sim_trace_fast.csv", "sim_trace_fast_before.csv").replace("sim_trace_slow.csv", "sim_trace_slow_before.csv")
before = before.replace("checks_fast.txt", "checks_fast_before.txt").replace("checks_slow.txt", "checks_slow_before.txt")
before = before.replace("shared op12", "baseline op12")
s += before
s += """
module tb_tile_op12;
wire fast_finished,slow_finished,fast_before_finished,slow_before_finished;
tile_op12_runner #(.FAST(1'b1)) fast(fast_finished);
tile_op12_runner #(.FAST(1'b0)) slow(slow_finished);
tile_op12_before #(.FAST(1'b1)) fast_before(fast_before_finished);
tile_op12_before #(.FAST(1'b0)) slow_before(slow_before_finished);
initial begin
  $dumpfile("waveform.vcd");
  $dumpvars(0,fast.clk_i,fast.rst_n_i,fast.mem_valid_o,fast.mem_addr_o,fast.done_o,
               slow.mem_valid_o,slow.mem_addr_o,slow.done_o);
  wait(fast_finished && slow_finished && fast_before_finished && slow_before_finished);
  for (int i=0;i<2;i++) begin
    $display("[PERFORMANCE] op12 case=%0d fast=%0d before=%0d slow=%0d before=%0d",
             i,fast.run_cycles[i],fast_before.run_cycles[i],slow.run_cycles[i],slow_before.run_cycles[i]);
    if (fast.run_cycles[i] > fast_before.run_cycles[i]*101/100 || slow.run_cycles[i] > slow_before.run_cycles[i]*101/100) begin
      $error("op12 performance regression exceeds 1 percent"); $stop;
    end
  end
  $display("[TB PASSED] op12 two frozen Golden cases, fast+slow DDR, input double buffer");
  $finish;
end
endmodule
"""
(HERE / "tb_tile_op12.sv").write_text(s, encoding="utf-8")

# 固定本轮已上板版本，避免用更早的 Git 提交冒充本轮性能基线。
pw = (HERE / "before/pwmacshared.v").read_text(encoding="utf-8-sig")
names = re.findall(r"^module\s+(\w+)", pw, re.M) + ["op_core_bank", "op_engine"]
for filename in ("pwmacshared.v", "op_core_bank.sv", "op_engine.sv"):
    text = (HERE / "before" / filename).read_text(encoding="utf-8-sig")
    for name in names:
        text = re.sub(r"\b" + name + r"\b", name + "_tile_before", text)
    (HERE / (Path(filename).stem + "_tile_before" + Path(filename).suffix)).write_text(text, encoding="utf-8")
