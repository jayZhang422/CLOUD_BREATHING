"""Freeze commit 508462a; adapt only the INT16 wire layout of existing Golden."""
from pathlib import Path
import re
import subprocess
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
TBROOT = HERE.parent
OP = "src/rtl/op/"
baseline = HERE / "before"
baseline.mkdir(exist_ok=True)
paths = [OP+"PW/pwmacshared.v"] + [OP+"control/"+name+".sv" for name in
    ("op_core_bank", "op_engine", "op_descriptor_check", "op_pw_pack")]
sources = {p: subprocess.check_output(["git", "show", "508462a:"+p], cwd=ROOT).decode() for p in paths}
modules = [m for text in sources.values() for m in re.findall(r"^module\s+(\w+)", text, re.M)]
modules.append("op_pw_pack_bram")
pattern = re.compile(r"\b("+"|".join(modules)+r")\b")
for path, text in sources.items():
    (baseline / Path(path).name).write_text(pattern.sub(lambda m: m[0]+"_p8base", text), encoding="utf-8")
tb = (HERE/"tb_p8p16_engine.sv").read_text(encoding="utf-8")
tb = tb.replace("tb_p8p16_engine", "tb_p8p16_before").replace("op_engine dut", "op_engine_p8base dut")
tb = tb.replace('"cases.txt"', '"cases_before.txt"').replace('"golden.hex"', '"golden_before.hex"')
(HERE/"tb_p8p16_before.sv").write_text(tb, encoding="utf-8")

# Existing 21-case production board/RPC fixture, including stopped RX clock.
head_old = TBROOT/"pw_doublebuffer/vectors/tumor_head"
head_new = HERE/"vectors/rpc_tumor_head"
head_new.mkdir(exist_ok=True)
for name in ("descriptor.hex", "uploads.txt"):
    shutil.copyfile(head_old/name, head_new/name)
old = bytes(int(x,16) for x in (head_old/"golden.hex").read_text().split())
new = b"".join(old[p:p+8]+bytes(8) for p in range(0,len(old),8))
(head_new/"golden.hex").write_text("".join(f"{b:02x}\n" for b in new), encoding="ascii")
cases = (TBROOT/"move_clock/rpc_cases.txt").read_text(encoding="utf-8-sig")
# Retain the existing 21 cases and append three representative PW layers.
names = {row.split()[0] for row in cases.splitlines() if row.strip()}
for manifest in (TBROOT/"pw_stream_20261022/rpc_cases.txt", TBROOT/"move_clock/move_cases.txt"):
    for row in manifest.read_text(encoding="utf-8-sig").splitlines():
        if row.split()[0] not in names:
            cases += row+"\n"
            names.add(row.split()[0])
cases = re.sub(r"tumor_head\s+8192\s+0", f"tumor_head {len(new)} 0", cases)
(HERE/"rpc_cases.txt").write_text(cases, encoding="ascii")
tb = (TBROOT/"pw_stream_20261022/tb_pwstream_move.sv").read_text(encoding="utf-8-sig")
tb = tb.replace("tb_pwstream_move", "tb_p8p16_rpc")
tb = tb.replace((TBROOT/"move_clock/move_cases.txt").as_posix(), (HERE/"rpc_cases.txt").as_posix())
tb = tb.replace('$readmemh({case_folder,"descriptor.hex"},descriptor_mem);',
    'if(name=="tumor_head") case_folder="'+head_new.as_posix()+'/";\n                $readmemh({case_folder,"descriptor.hex"},descriptor_mem);')
(HERE/"tb_p8p16_rpc.sv").write_text(tb, encoding="utf-8")
print(f"Prepared baseline from 508462a and {len(names)} production RPC cases")

# Frozen P4 reference vectors exercise repeat-start and reset on the compatible path.
tb = (TBROOT/"pw_doublebuffer/tb_tile_pw.sv").read_text(encoding="utf-8-sig")
for old in ("tile_pw_if", "tile_pw_driver", "tb_tile_pw"):
    tb = re.sub(r"\b"+old+r"\b", old+"_p8compat", tb)
tb = tb.replace("logic [3:0] io_output_o_payload_mask;", "logic [15:0] io_output_o_payload_mask;")
tb = tb.replace("bus.io_output_o_payload_mask,", "bus.io_output_o_payload_mask[3:0],")
for side in ("project", "skip"):
    tb = tb.replace(f".io_{side}_cfg_i_payload_int16({side}.io_cfg_i_payload_int16),",
        f".io_{side}_cfg_i_payload_int16({side}.io_cfg_i_payload_int16),\n  .io_{side}_cfg_i_payload_legacyP4(1'b1),")
(HERE/"tb_tile_pw_p8compat.sv").write_text(tb, encoding="utf-8")
