from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
OP = ROOT / 'src/rtl/op'
TBROOT = HERE.parent
snapshot = HERE / 'before'
for name in ('op_board.sv',):
    p = snapshot / name
    if not p.exists():
        p.write_bytes((OP / name).read_bytes())
for name in ('op_service.sv', 'op_core_bank.sv'):
    p = snapshot / name
    if not p.exists():
        p.write_bytes((OP / 'control' / name).read_bytes())
modules = []
for p in snapshot.glob('*'):
    if p.suffix in ('.v', '.sv'):
        modules += re.findall(r'^module\s+(\w+)', p.read_text(encoding='utf-8'), re.M)
pattern = re.compile(r'\b(' + '|'.join(modules) + r')\b')
dest = HERE / 'baseline_rtl'
dest.mkdir(exist_ok=True)
for p in snapshot.glob('*'):
    if p.suffix in ('.v', '.sv'):
        (dest / p.name).write_text(pattern.sub(lambda m: m[0] + '_wstream_before', p.read_text(encoding='utf-8')), encoding='utf-8')
source = (TBROOT / 'stream_250/baseline_fixture/tb_stream250_baseline_rpc.sv').read_text(encoding='utf-8')
source = source.replace("parameter bit FAST=1'b0", "parameter bit FAST=1'b1")
source = source.replace('repeat (20000000)', 'repeat (5000000)')
source = source.replace('case_folder = {VECTOR_DIR,name,"/"};', 'case_folder = {VECTOR_DIR,name,"/"};\n                if(name=="lobe_e1.expand" || name=="tumor_d3.expand" || name=="tumor_head") case_folder="sim/xsim/tests/pw_doublebuffer/vectors/";\n                if(name=="lobe_e1.expand" || name=="tumor_d3.expand" || name=="tumor_head") case_folder={case_folder,name,"/"};')
source = source.replace('else $readmemh({VECTOR_DIR,filename},file_mem,0,input_size-1);', 'else if(name=="lobe_e1.expand" || name=="tumor_d3.expand" || name=="tumor_head") $readmemh({"sim/xsim/tests/pw_doublebuffer/vectors/",filename},file_mem,0,input_size-1); else $readmemh({VECTOR_DIR,filename},file_mem,0,input_size-1);')
source = source.replace('stream_250/baseline_rpc_cases.txt', 'pw_stream_20261022/rpc_cases.txt')
source = source.replace('int ddr_reads = 0, ddr_writes = 0, rom_reads = 0;', 'int ddr_reads = 0, ddr_writes = 0, rom_reads = 0;\n    longint unsigned read_bytes=0, run_read_bytes=0;\n    int run_reads=0;')
source = source.replace('rd_phase <= 1; rd_delay <= 2; ddr_reads = ddr_reads + 1;', 'rd_phase <= 1; rd_delay <= 2; ddr_reads = ddr_reads + 1; read_bytes=read_bytes+rd_len;')
source = source.replace("rpc(8'h21,identity,64);check_status(8'd0);", "run_read_bytes=read_bytes; run_reads=ddr_reads;\n                rpc(8'h21,identity,64);check_status(8'd0);")
source = source.replace('$display("[TIMING] %s hardware_cycles=%0d",name,hardware_cycles);', '$display("[TIMING] %s hardware_cycles=%0d read_bursts=%0d read_bytes=%0d",name,hardware_cycles,ddr_reads-run_reads,read_bytes-run_read_bytes);')
for variant in ('before', 'after'):
    s = source.replace('tb_stream250_baseline_rpc', 'tb_pwstream_' + variant)
    s = s.replace('op_board_stream250_before', 'op_board_wstream_before' if variant == 'before' else 'op_board')
    (HERE / ('tb_pwstream_' + variant + '.sv')).write_text(s, encoding='utf-8')
print('Prepared before/after 250 MHz RPC fixtures and', len(modules), 'renamed baseline modules')
(HERE / 'rpc_cases.txt').write_text((TBROOT / 'stream_250/baseline_rpc_cases.txt').read_text() + (TBROOT / 'pw_doublebuffer/rpc_cases.txt').read_text())
op12 = (TBROOT / 'move_clock/tb_move_op12.sv').read_text(encoding='utf-8')
op12 = op12.replace('move_op12_runner', 'pwstream_op12_runner').replace('tb_move_op12', 'tb_pwstream_op12')
(HERE / 'tb_pwstream_op12.sv').write_text(op12, encoding='utf-8')
