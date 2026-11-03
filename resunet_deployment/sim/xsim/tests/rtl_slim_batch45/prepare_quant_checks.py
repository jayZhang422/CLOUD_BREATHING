"""只生成本批仿真向量，不修改部署 Python 或冻结 Golden。"""
from pathlib import Path
import random
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RNG = random.Random(20261020)


def signed(value, width):
    value &= (1 << width) - 1
    return value - (1 << width) if value >> (width - 1) else value


def rne(value, shift):
    if not shift:
        return value
    whole, remainder = divmod(value, 1 << shift)
    half = 1 << (shift - 1)
    return whole + int(remainder > half or (remainder == half and whole & 1))


def ports(path, module):
    body = path.read_text(encoding='utf-8-sig').split('module ' + module + ' (', 1)[1].split(');', 1)[0]
    return [(d, int(hi) + 1 if hi else 1, n) for d, hi, n in
            re.findall(r'(input|output)\s+wire\s+(?:\[(\d+):0\]\s+)?(\w+)', body)]


def pack(values, fields):
    result = 0
    for _, width, name in fields:
        result = (result << width) | (values[name] & ((1 << width) - 1))
    return result


def hexfile(name, words, width):
    (HERE / name).write_text(''.join(f'{w:0{(width+3)//4}x}\n' for w in words))


def declarations(all_ports):
    return '\n'.join(f'logic {"["+str(w-1)+":0] " if w>1 else ""}{n};' for _, w, n in all_ports)


def instance(module, all_ports):
    return module + ' dut (\n' + ',\n'.join(f'.{n}({n})' for _, _, n in all_ports) + '\n);\n'


def concat(fields):
    return '{' + ','.join(n for _, _, n in fields) + '}'


pw_ports = ports(ROOT / 'src/rtl/op/pw/pwmacshared.v', 'PwSharedRequant')
pw_in = [x for x in pw_ports if x[2].startswith('io_input_i_payload_')]
pw_out = [x for x in pw_ports if x[2].startswith('io_output_o_payload_')]
stim, expected = [], []
for i in range(8192):
    shift = i % 64
    values = {n: RNG.getrandbits(w) for _, w, n in pw_in}
    values['io_input_i_payload_shift'] = shift
    values['io_input_i_payload_tag_mask'] = 15 if i < 1024 else i % 16
    values['io_input_i_payload_raw'] = 0 if i < 1024 else i % 13 == 0
    for lane in range(4):
        if i < 1024:
            half = 1 << (shift - 1) if shift else 0
            value = ((i // 64) % 4 - 2) * (1 << shift) + half + lane - 1
            values[f'io_input_i_payload_mac_{lane}'] = 0
            values[f'io_input_i_payload_multiplier_{lane}'] = 0
            values[f'io_input_i_payload_bias_{lane}'] = value
        values[f'io_input_i_payload_lower_{lane}'] = -32768 if i < 1024 else -128
        values[f'io_input_i_payload_upper_{lane}'] = 32767 if i < 1024 else 127
    out = {}
    for name in ('pixel', 'group', 'mask', 'last'):
        out['io_output_o_payload_' + name] = values['io_input_i_payload_tag_' + name]
    for name in ('raw', 'int16'):
        out['io_output_o_payload_' + name] = values['io_input_i_payload_' + name]
    for lane in range(4):
        mac = signed(values[f'io_input_i_payload_mac_{lane}'], 32)
        mult = signed(values[f'io_input_i_payload_multiplier_{lane}'], 32)
        bias = signed(values[f'io_input_i_payload_bias_{lane}'], 64)
        numerator = signed(mac * mult + bias, 64)  # 保留原 RTL 的 INT64 截断语义
        lo = signed(values[f'io_input_i_payload_lower_{lane}'], 16)
        hi = signed(values[f'io_input_i_payload_upper_{lane}'], 16)
        valid = values['io_input_i_payload_tag_mask'] >> lane & 1
        out[f'io_output_o_payload_mac_{lane}'] = mac if valid else 0
        out[f'io_output_o_payload_q_{lane}'] = min(hi, max(lo, rne(numerator, shift))) if valid and not out['io_output_o_payload_raw'] else 0
    stim.append(pack(values, pw_in))
    expected.append(pack(out, pw_out))
iw, ow = sum(x[1] for x in pw_in), sum(x[1] for x in pw_out)
hexfile('pw_quant_stimulus.hex', stim, iw)
hexfile('pw_quant_golden.hex', expected, ow)
pw = f'''module batch45_pw_quant(output logic finished_o);
{declarations(pw_ports)}
{instance('PwSharedRequant', pw_ports)}
logic [{iw-1}:0] stimulus[0:8191];
logic [{ow-1}:0] golden[0:8191];
wire [{ow-1}:0] actual={concat(pw_out)};
logic [{ow-1}:0] held;
logic stalled=1'b0;
integer sent=0, got=0, cycle=0, csv;
always #4 clk=~clk;
always @(negedge clk) begin
  io_output_o_ready=resetn && cycle%13>=4;
end
always @(posedge clk) begin
  cycle=cycle+1;
  if(resetn) begin
    if(stalled && (!io_output_o_valid || actual !== held)) begin $error("PW quant payload changed cycle=%0d",cycle);$fflush(csv);$stop;end
    stalled=io_output_o_valid && !io_output_o_ready;held=actual;
    if(io_input_i_valid && io_input_i_ready)sent=sent+1;
    if(io_output_o_valid && io_output_o_ready)begin
      if(got>=8192 || actual !== golden[got])begin $error("PW quant Golden index=%0d actual=%h expected=%h",got,actual,golden[got]);$fflush(csv);$stop;end
      got=got+1;
    end
  end
  if(!finished_o)$fdisplay(csv,"%0d,%b,%b,%b,%b,%h,%0d",cycle,io_input_i_valid,io_input_i_ready,io_output_o_valid,io_output_o_ready,actual,got);
end
initial begin
  clk=0;resetn=0;finished_o=0;io_input_i_valid=0;io_output_o_ready=0;
  csv=$fopen("sim_trace_pw_quant.csv","w");
  $fdisplay(csv,"cycle,in_valid,in_ready,out_valid,out_ready,payload,got");
  $readmemh("{HERE.as_posix()}/pw_quant_stimulus.hex",stimulus);
  $readmemh("{HERE.as_posix()}/pw_quant_golden.hex",golden);
  repeat(6)@(negedge clk);resetn=1;
  for(int n=0;n<8192;n++)begin
    @(negedge clk);io_input_i_valid=1;{concat(pw_in)}=stimulus[n];
    do @(posedge clk);while(io_input_i_ready !== 1'b1);
    @(negedge clk);io_input_i_valid=0;
  end
  wait(got==8192);@(negedge clk);finished_o=1;$fclose(csv);
  $display("[CASE PASS] PW quant 8192 vectors shift0..63 negative ties INT64 wrap saturation mask raw");
end
endmodule
'''

add_ports = ports(ROOT / 'src/rtl/op/elementadd/elementadd_p16.v', 'ElementAdd_p16')
cfg_fields = [x for x in add_ports if x[2].startswith('io_cfg_i_payload_')]
out_fields = [x for x in add_ports if x[2].startswith('io_output_o_payload_')]
cfg_words, a_words, b_words, add_expected = [], [], [], []
for group in range(192):
    shift = group % 64
    cfg = {n: 0 for _, _, n in cfg_fields}
    cfg.update(io_cfg_i_payload_words=17, io_cfg_i_payload_group=group%32,
               io_cfg_i_payload_last_group=group%3==0, io_cfg_i_payload_shift=shift,
               io_cfg_i_payload_clamp_min=-128 if group%2 else 0, io_cfg_i_payload_clamp_max=127)
    for lane in range(16):
        cfg[f'io_cfg_i_payload_multiplier_a_{lane}'] = 1 if group < 128 else signed(RNG.getrandbits(22),22)
        cfg[f'io_cfg_i_payload_multiplier_b_{lane}'] = 0 if group < 128 else signed(RNG.getrandbits(22),22)
        half = 1 << (shift-1) if shift else 0
        cfg[f'io_cfg_i_payload_bias_fixed_{lane}'] = signed((-half if group%2 else half) + lane%3-1,64) if group < 128 else signed(RNG.getrandbits(64),64)
    cfg_words.append(pack(cfg,cfg_fields))
    for word in range(17):
        aa=[(word-8) if group<128 else signed(RNG.getrandbits(32),32) for _ in range(16)]
        bb=[signed(RNG.getrandbits(32),32) for _ in range(16)]
        a_words.append(sum((v&0xffffffff)<<(lane*32) for lane,v in enumerate(aa)))
        b_words.append(sum((v&0xffffffff)<<(lane*32) for lane,v in enumerate(bb)))
        data=0
        for lane in range(16):
            value=aa[lane]*cfg[f'io_cfg_i_payload_multiplier_a_{lane}']+bb[lane]*cfg[f'io_cfg_i_payload_multiplier_b_{lane}']+cfg[f'io_cfg_i_payload_bias_fixed_{lane}']
            q=min(127,max(cfg['io_cfg_i_payload_clamp_min'],rne(value,shift)))
            data|=(q&255)<<(lane*8)
        out={'io_output_o_payload_fragment_data':data,'io_output_o_payload_fragment_group':group%32,
             'io_output_o_payload_fragment_group_last':word==16,'io_output_o_payload_last':word==16 and cfg['io_cfg_i_payload_last_group']}
        add_expected.append(pack(out,out_fields))
cw, aw=sum(x[1] for x in cfg_fields),sum(x[1] for x in out_fields)
hexfile('add_cfg.hex',cfg_words,cw);hexfile('add_a.hex',a_words,512);hexfile('add_b.hex',b_words,512);hexfile('add_golden.hex',add_expected,aw)
add=f'''module batch45_add_quant(output logic finished_o);
{declarations(add_ports)}
{instance('ElementAdd_p16',add_ports)}
logic [{cw-1}:0] configs[0:191];
logic [511:0] stimulus_a[0:3263],stimulus_b[0:3263];
logic [{aw-1}:0] golden[0:3263];
wire [{aw-1}:0] actual={concat(out_fields)};
logic [{aw-1}:0] held;
logic stalled=0;
integer got=0,cycle=0,csv;
always #4 clk=~clk;
always @(negedge clk)io_output_o_ready=resetn && cycle%11>=3;
always @(posedge clk)begin
  cycle=cycle+1;
  if(resetn)begin
    if(stalled && (!io_output_o_valid || actual !== held))begin $error("Add quant stalled payload changed cycle=%0d",cycle);$fflush(csv);$stop;end
    stalled=io_output_o_valid && !io_output_o_ready;held=actual;
    if(io_output_o_valid && io_output_o_ready)begin
      if(got>=3264 || actual !== golden[got])begin $error("Add quant Golden index=%0d actual=%h expected=%h",got,actual,golden[got]);$fflush(csv);$stop;end
      got=got+1;
    end
  end
  if(!finished_o)$fdisplay(csv,"%0d,%b,%b,%b,%b,%b,%b,%h,%0d",cycle,io_a_i_valid,io_a_i_ready,io_b_i_valid,io_b_i_ready,io_output_o_valid,io_output_o_ready,actual,got);
end
initial begin
  clk=0;resetn=0;finished_o=0;io_cfg_i_valid=0;io_a_i_valid=0;io_b_i_valid=0;io_output_o_ready=0;
  csv=$fopen("sim_trace_add_quant.csv","w");$fdisplay(csv,"cycle,a_valid,a_ready,b_valid,b_ready,out_valid,out_ready,payload,got");
  $readmemh("{HERE.as_posix()}/add_cfg.hex",configs);$readmemh("{HERE.as_posix()}/add_a.hex",stimulus_a);$readmemh("{HERE.as_posix()}/add_b.hex",stimulus_b);$readmemh("{HERE.as_posix()}/add_golden.hex",golden);
  repeat(6)@(negedge clk);resetn=1;
  for(int g=0;g<192;g++)begin
    @(negedge clk);{concat(cfg_fields)}=configs[g];io_cfg_i_valid=1;
    do @(posedge clk);while(io_cfg_i_ready !== 1'b1);
    @(negedge clk);io_cfg_i_valid=0;
    for(int w=0;w<17;w++)begin
      @(negedge clk);io_a_i_payload=stimulus_a[g*17+w];io_b_i_payload=stimulus_b[g*17+w];io_a_i_valid=1;
      repeat(w%3)@(negedge clk);io_b_i_valid=1;
      do @(posedge clk);while(!(io_a_i_ready === 1'b1 && io_b_i_ready === 1'b1));
      @(negedge clk);io_a_i_valid=0;io_b_i_valid=0;
    end
    wait(got==(g+1)*17);
  end
  @(negedge clk);finished_o=1;$fclose(csv);
  $display("[CASE PASS] Add quant 192 configs 3264 outputs shift0..63 ties signed extremes join backpressure");
end
endmodule
'''
top='''module tb_batch45_quant;
wire pw_done,add_done;
batch45_pw_quant pw(pw_done);
batch45_add_quant addq(add_done);
initial begin
  $dumpfile("waveform.vcd");$dumpvars(0,pw.clk,pw.resetn,pw_done,add_done);
  wait(pw_done && add_done);$display("[TB PASSED] quantization all offline Golden vectors matched");$finish;
end
initial begin #2000000;$fatal(1,"Quantization timeout");end
endmodule
'''
(HERE/'tb_batch45_quant.sv').write_text('`timescale 1ns/1ps\n'+pw+add+top,encoding='utf-8')
print('Generated PW8192 + Add3264 offline Golden cases; seed20261020')
