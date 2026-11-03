"""本批离线向量及实际RPC夹具；不改产品Python，不在TB实现算法参考。"""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SIM = HERE.parent
SRC = ROOT / "src/rtl/op"

def save_hex(path, values):
    path.write_text("".join(f"{x:02x}\n" for x in values), encoding="utf-8")

rows = (SIM / "ddr_continuous/rpc_cases.txt").read_text().splitlines()
for name, op, w, h, ga, gb, offset in (
    ("move_pool_512", 2, 512, 4, 2, 0, 0),
    ("move_pool_odd", 2, 5, 5, 3, 0, 16),
    ("move_up_256", 10, 256, 4, 2, 0, 0),
    ("move_up_tail", 10, 3, 3, 1, 0, 16),
    ("move_concat", 5, 128, 4, 2, 3, 0),
    ("move_concat_tail", 5, 3, 3, 1, 3, 16),
    ("move_concat_odd", 5, 3, 3, 1, 2, 16),
    ("move_pool_single", 2, 3, 3, 1, 0, 16),
):
    out = HERE / "vectors" / name
    out.mkdir(parents=True, exist_ok=True)
    a = bytes((i * 73 + i // 7 + 193) & 255 for i in range(w*h*ga*16))
    b = bytes((i * 29 + i // 3 + 127) & 255 for i in range(w*h*gb*16))
    if op == 2:
        expected = bytearray()
        for g in range(ga):
            for y in range(h//2):
                for x in range(w//2):
                    for lane in range(16):
                        vals = [a[((g*h + 2*y+dy)*w + 2*x+dx)*16+lane] for dy in range(2) for dx in range(2)]
                        expected.append(max(v if v < 128 else v-256 for v in vals) & 255)
    elif op == 10:
        expected = b"".join(a[((g*h+y//2)*w+x//2)*16:((g*h+y//2)*w+x//2)*16+16]
                            for g in range(ga) for y in range(h*2) for x in range(w*2))
    else:
        expected = a+b
    d = bytearray(64)
    d[0] = op
    for off, val in ((4,w),(6,h),(8,ga),(14,gb)):
        d[off:off+2] = val.to_bytes(2,"little")
    for off, val in ((16,0x02000000+offset),(20,0x02200010),(24,0x02400000)):
        d[off:off+4] = val.to_bytes(4,"little")
    save_hex(out/"descriptor.hex", d)
    save_hex(out/"input.hex", a)
    save_hex(out/"golden.hex", expected)
    uploads = f"{0x02000000+offset:08x} {len(a)} {(out/'input.hex').as_posix()}\n"
    if b:
        save_hex(out/"input_b.hex", b)
        uploads += f"02200010 {len(b)} {(out/'input_b.hex').as_posix()}\n"
    (out/"uploads.txt").write_text(uploads, encoding="utf-8")
    rows.append(f"{name} {len(expected)} 0")
(HERE/"rpc_cases.txt").write_text("\n".join(rows)+"\n",encoding="utf-8")
unit_input = bytes((i*73+i//7+193)&255 for i in range(65536))
save_hex(HERE/"vectors/unit_input.hex",unit_input)
save_hex(HERE/"vectors/unit_golden.hex",unit_input[16:16016]+unit_input[32768:32768+772*16])

# 固定本次续作前的已上板engine/board，其他已验证核心和IP共用。
for filename in ("op_engine.sv", "op_board.sv"):
    s = (HERE/"before"/filename).read_text(encoding="utf-8-sig")
    for module in ("op_engine", "op_board", "op_service"):
        s = re.sub(r"\b"+module+r"\b",module+"_move_before",s)
    (HERE/(Path(filename).stem+"_move_before.sv")).write_text(s,encoding="utf-8")
s = (SRC/"control/op_service.sv").read_text(encoding="utf-8-sig")
for module in ("op_service", "op_engine"):
    s = re.sub(r"\b"+module+r"\b",module+"_move_before",s)
(HERE/"op_service_move_before.sv").write_text(s,encoding="utf-8")

# RPC/单元夹具独立维护，重生成向量不会覆盖定向CDC检查。
(HERE/"move_cases.txt").write_text("\n".join(r for r in rows if r.startswith("move_"))+"\n",encoding="utf-8")
print(f"prepared {len(rows)} RPC Golden cases and frozen production baseline")
