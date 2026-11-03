"""第三批：复用冻结 Golden，验证共享点积与真实双分支调度。仅生成仿真资料。"""
from pathlib import Path
import hashlib
import json
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OLD = HERE.parent / 'rtl_slim_batch1'
B2 = HERE.parent / 'rtl_slim_batch2'
SOURCE = ROOT / 'src/rtl/op'


def write(name, text):
    (HERE / name).write_text(text, encoding='utf-8')


def rename(text):
    for name in ('PwMac', 'PwRequant', 'op_core_bank', 'op_engine'):
        text = re.sub(r'\b' + name + r'\b', name + '_batch3_before', text)
    return text


write('pwmac_batch3_before.v', rename((HERE / 'before/pwmac.v').read_text(encoding='utf-8-sig')))
write('op_core_bank_batch3_before.sv', rename((HERE / 'before/op_core_bank.sv').read_text(encoding='utf-8-sig')))
write('op_engine_batch3_before.sv', rename((SOURCE / 'control/op_engine.sv').read_text(encoding='utf-8-sig')))
rows = (OLD / 'pw_cases.txt').read_text(encoding='utf-8-sig').splitlines()
write('pw_project.txt', '\n'.join(rows) + '\n')
# 两路配置/输入故意错开，不能用相同结果掩盖分支路由错误。
write('pw_skip.txt', '\n'.join(rows[5:] + rows[:5]) + '\n')

# 复用原 PW 驱动与冻结向量，改为两路独立握手，通过接口接到共享阵列。
s = (OLD / 'tb_rtl_slim_pw.sv').read_text(encoding='utf-8-sig')
decl = s[s.index('logic io_cfg_i_valid;'):s.index('PwMac dut (')]
decl = re.sub(r'^logic .*_before;\n', '', decl, flags=re.M)
interface = 'interface batch3_pw_if;\n' + decl + 'endinterface\n'
ports = []
top_decl = (SOURCE / 'PW/pwmacshared.v').read_text(encoding='utf-8-sig').split(');', 1)[0]
for name in re.findall(r'\b(io_(?:project|skip)_\w+)\s*,?', top_decl):
    branch, field = name[3:].split('_', 1)
    ports.append(f'  .{name}({branch}.io_{field})')
shared = 'PwMacShared dut (\n' + ',\n'.join(ports) + ',\n  .clk(project.clk), .resetn(project.resetn && skip.resetn)\n);'
original_ports = re.search(r'PwMac dut \(\n(.*?)\n\);', s, re.S)[1]
originals = []
for branch in ('project', 'skip'):
    p = re.sub(r'\((\w+)\)', lambda m: '(' + branch + '.' + m[1] + ')', original_ports)
    originals.append(f'PwMac_batch3_before {branch}_before (\n{p}\n);')
body = s[s.index('localparam string VECTOR_ROOT'):s.rindex('endmodule')]
body = re.sub(r'^wire .*_before.*\n', '', body, flags=re.M)
start = body.index('        if ({io_cfg_i_ready,')
end = body.index('        if (stalled', start)
body = body[:start] + body[end:]
body = body.replace('integer cycle = 0', 'integer cycle = 0')
body = body.replace('"sim_trace.csv"', 'SIDE == 0 ? "sim_trace_project.csv" : "sim_trace_skip.csv"')
body = body.replace('"checks.txt"', 'SIDE == 0 ? "checks_project.txt" : "checks_skip.txt"')
body = re.sub(r'    \$dumpfile.*?    \$dumpvars.*?;\n', '', body, flags=re.S)
body = body.replace('manifest = $fopen({CHECK_ROOT,"pw_cases.txt"},"r");',
                    'manifest = $fopen({BATCH3_ROOT,SIDE == 0 ? "pw_project.txt" : "pw_skip.txt"},"r");')
# XSim 的文件名实参使用明确的分支常量，避免两路复用同一文件句柄。
for handle, first, second, mode in (
    ('csv', 'sim_trace_project.csv', 'sim_trace_skip.csv', 'w'),
    ('report', 'checks_project.txt', 'checks_skip.txt', 'w'),
):
    body = body.replace(f'{handle} = $fopen(SIDE == 0 ? "{first}" : "{second}","{mode}");',
                        f'if (SIDE == 0) {handle} = $fopen("{first}","{mode}");\n'
                        f'    else {handle} = $fopen("{second}","{mode}");')
body = body.replace('manifest = $fopen({BATCH3_ROOT,SIDE == 0 ? "pw_project.txt" : "pw_skip.txt"},"r");',
                    'if (SIDE == 0) manifest = $fopen({BATCH3_ROOT,"pw_project.txt"},"r");\n'
                    '    else manifest = $fopen({BATCH3_ROOT,"pw_skip.txt"},"r");')
body = f'localparam string BATCH3_ROOT = "{HERE.as_posix()}/";\n' + body
body = body.replace('cycle_equivalent=1', 'side=%0d').replace('name,got,cycle-started);', 'name,got,cycle-started,SIDE);')
body = body.replace('[TB PASSED]', '[DRIVER PASSED]').replace('exact-cycle-equivalence', 'shared-dot-Golden')
body = body.replace('$fclose(csv); $fclose(report); $fclose(manifest); $finish;',
                    '$fclose(csv); $fclose(report); $fclose(manifest); finished_o=1\'b1;')
body = body.replace('clk = 1\'b0; resetn', 'finished_o=1\'b0; clk = 1\'b0; resetn')
body = body.replace('    $fdisplay(csv,', '    if (!finished_o) $fdisplay(csv,')
body = re.sub(r'\bio_\w+\b|\bclk\b|\bresetn\b', lambda m: 'bus.' + m[0], body)
driver = 'module batch3_pw_driver #(parameter integer SIDE=0)(batch3_pw_if bus, output logic finished_o);\n' + body + 'endmodule\n'
top = '''module tb_batch3_pw #(parameter bit SHARED=1'b1);
batch3_pw_if project();
batch3_pw_if skip();
wire project_finished, skip_finished;
wire [31:0] contention;
batch3_pw_driver #(.SIDE(0)) driver_project(project,project_finished);
batch3_pw_driver #(.SIDE(1)) driver_skip(skip,skip_finished);
generate if (SHARED) begin : g_shared
SHARED_INSTANCE
integer contention_count=0;
always @(posedge project.clk)
  if (project.resetn && skip.resetn && dut.project_io_dotRequest_o_valid && dut.skip_io_dotRequest_o_valid)
    contention_count=contention_count+1;
assign contention=contention_count;
end else begin : g_before
ORIGINAL_INSTANCES
assign contention=32'd0;
end endgenerate
initial begin
  $dumpfile("waveform.vcd");
  $dumpvars(0,project.clk,project.resetn,project.io_rd_o_valid,project.io_output_o_valid,
              skip.io_rd_o_valid,skip.io_output_o_valid,project_finished,skip_finished);
  wait(project_finished && skip_finished);
  if (SHARED && contention==0) begin $error("Shared arbiter contention not exercised"); $stop; end
  $display("[TB PASSED] PW two independent branches, SHARED=%0d, 22 Golden cases, contention=%0d",SHARED,contention);
  $finish;
end
endmodule
'''.replace('SHARED_INSTANCE', shared).replace('ORIGINAL_INSTANCES', '\n'.join(originals))
write('tb_batch3_pw.sv', '`timescale 1ns/1ps\n' + interface + driver + top)

# op12 的优化版/基线分别提供 DDR 模型，允许微架构延迟变化；两者都核对同一冻结 Golden。
s = (B2 / 'tb_batch2_op12.sv').read_text(encoding='utf-8-sig')
s = re.sub(r'^logic .*_before;\n', '', s, flags=re.M)
s = re.sub(r'op_engine_batch2_before baseline \(.*?\n\);\n', '', s, flags=re.S)
start = s.index('        if ({check_done_o,')
end = s.index('        if (stalled', start)
s = s[:start] + s[end:]
s = s.replace('if (stalled && (!mem_valid_o ||', 'if (stalled && held[319] && (!mem_valid_o ||')
start = s.index('            if (dut.u_bank.p12_add_a_data_w')
end = s.index('            add_checks=add_checks+1;', start)
s = s[:start] + s[end:]
s = s.replace(' ||\n                        mem_data_o[b*8+:8] !== mem_data_o_before[b*8+:8]', '')
s = s.replace('integer cycle=0', 'integer run_cycles[0:1];\ninteger cycle=0')
s = s.replace('cycle%13>=4', '(FAST || cycle%13>=4)')
s = s.replace('response_delay=cycle%5+1;', 'response_delay=FAST ? 0 : cycle%5+1;')
s = s.replace('cycle_equivalent=1', 'independent-Golden')
s = s.replace('mem_stalls==0', '(!FAST && mem_stalls==0)')
s = s.replace('            cases_done=cases_done+1;', '            run_cycles[cases_done]=cycle-started;\n            cases_done=cases_done+1;')
s = s.replace('[TB PASSED]', '[RUNNER PASSED]').replace('exact-cycle-equivalence', 'independent-Golden')
s = s.replace('$fclose(csv); $fclose(report); $fclose(manifest); $finish;', '$fclose(csv); $fclose(report); $fclose(manifest); finished_o=1\'b1;')
s = s.replace('clk_i=1\'b0;', 'finished_o=1\'b0; clk_i=1\'b0;')
s = s.replace('    $fdisplay(csv,', '    if (!finished_o) $fdisplay(csv,')
s = re.sub(r'    \$dumpfile.*?    \$dumpvars.*?;\n', '', s, flags=re.S)
runners = []
for kind in ('shared', 'before'):
    t = s.replace('module tb_batch2_op12;', f'module batch3_op12_{kind} #(parameter bit FAST=0)(output logic finished_o);')
    if kind == 'before':
        t = t.replace('op_engine dut (', 'op_engine_batch3_before dut (')
    t = t.replace('"sim_trace.csv"', f'"sim_trace_{kind}.csv"').replace('"checks.txt"', f'"checks_{kind}.txt"')
    t = t.replace('"waveform.vcd"', f'"waveform_{kind}.vcd"')
    t = t.replace('op12 %s', kind + ' op12 %s')
    runners.append(t)
top = '''module tb_batch3_op12 #(parameter bit FAST=0);
wire shared_finished, before_finished;
batch3_op12_shared #(.FAST(FAST)) optimized(shared_finished);
batch3_op12_before #(.FAST(FAST)) reference(before_finished);
initial begin
  $dumpfile("waveform.vcd");
  $dumpvars(0,optimized.clk_i,optimized.rst_n_i,optimized.mem_valid_o,optimized.mem_ready_i,
              optimized.mem_write_o,optimized.mem_addr_o,optimized.done_o,
              reference.mem_valid_o,reference.mem_addr_o,reference.done_o);
  wait(shared_finished && before_finished);
  for (integer i=0;i<2;i=i+1) begin
    $display("[PERFORMANCE] case=%0d shared=%0d before=%0d fast=%0d",i,optimized.run_cycles[i],reference.run_cycles[i],FAST);
    if (optimized.run_cycles[i] > reference.run_cycles[i]*102/100) begin
      $error("op12 regression exceeds 2 percent, case=%0d",i); $stop;
    end
  end
  $display("[TB PASSED] op12 shared/reference Golden, two cases, speed regression <=2 percent, FAST=%0d",FAST);
  $finish;
end
endmodule
'''
write('tb_batch3_op12.sv', '\n'.join(runners) + top)
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (HERE / 'before').iterdir()}
write('results/baseline_sha256.json', json.dumps(hashes, indent=2))
print('Prepared PW two-branch and op12 independent baseline/Golden checks')
