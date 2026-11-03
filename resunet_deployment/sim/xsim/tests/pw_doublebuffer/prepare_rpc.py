"""仅重排既有冻结结果到原 DDR 布局；不计算或更改算法 Golden。"""
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
VECTORS = ROOT / "sim/standalone/op/pw/verification/stage3_pe16/vectors"


def words(path, width):
    return [int(s, 16).to_bytes(width, "little") for s in path.read_text().split()]


def write_bytes(path, data):
    path.write_text("".join(f"{b:02x}\n" for b in data), encoding="utf-8")


rows = []
for name, ci, co, pixels, head in (
    ("lobe_e1.expand", 3, 16, 1024, False),
    ("tumor_d3.expand", 768, 256, 64, False),
    ("tumor_head", 64, 1, 1024, True),
):
    source = VECTORS / name
    target = HERE / "vectors" / name
    target.mkdir(parents=True, exist_ok=True)
    descriptor = bytearray(64)
    descriptor[0] = 1
    descriptor[1] = 8 if head else 0
    descriptor[2] = ci & 255
    descriptor[3] = co & 255
    width = min(pixels, 512)
    for offset, value in ((4, width), (6, pixels // width), (8, (co + 15) // 16), (52, ci), (54, co)):
        descriptor[offset:offset + 2] = value.to_bytes(2, "little")
    descriptor[10] = 24
    descriptor[12] = 127
    for offset, value in ((16, 0x02000000), (24, 0x02400000), (32, 0x08000000), (36, 0x08180000)):
        descriptor[offset:offset + 4] = value.to_bytes(4, "little")
    write_bytes(target / "descriptor.hex", descriptor)
    uploads = []
    for filename, width, address in (("stimulus", 16, 0x02000000), ("weights", 64, 0x08000000), ("params", 64, 0x08180000)):
        data = b"".join(words(source / (filename + ".hex"), width))
        path = target / (filename + ".hex")
        write_bytes(path, data)
        uploads.append(f"{address:08x} {len(data)} {path.as_posix()}\n")
    (target / "uploads.txt").write_text("".join(uploads), encoding="utf-8")
    result_size = ((co + 3) // 4) * pixels * 8 if head else ((co + 15) // 16) * pixels * 16
    result = bytearray(result_size)
    for q, tag in zip(words(source / "golden.hex", 8), words(source / "tags.hex", 4), strict=True):
        tag = int.from_bytes(tag, "little")
        pixel, group = tag & ((1 << 19) - 1), (tag >> 19) & 127
        if head:
            offset = (group * pixels + pixel) * 8
            result[offset:offset + 8] = q
        else:
            offset = ((group // 4) * pixels + pixel) * 16 + (group % 4) * 4
            result[offset:offset + 4] = q[::2]
    write_bytes(target / "golden.hex", result)
    rows.append(f"{name} {result_size} 0\n")
(HERE / "rpc_cases.txt").write_text("".join(rows), encoding="utf-8")
s = (HERE.parent / "ddr_continuous/tb_continuous_rpc.sv").read_text(encoding="utf-8-sig")
s = s.replace("module tb_continuous_rpc;", "module tb_tile_rpc;")
s = s.replace("sim/xsim/tests/mkdc/vectors/", (HERE / "vectors").as_posix() + "/")
s = s.replace("sim/xsim/tests/ddr_continuous/rpc_cases.txt", (HERE / "rpc_cases.txt").as_posix())
(HERE / "tb_tile_rpc.sv").write_text(s, encoding="utf-8")
(HERE / "tb_tile_rpc_before.sv").write_text(
    s.replace("module tb_tile_rpc;", "module tb_tile_rpc_before;").replace("op_board dut", "op_board_tile_before dut"),
    encoding="utf-8")
for relative in ("control/op_service.sv", "op_board.sv"):
    path = ROOT / "src/rtl/op" / relative
    text = path.read_text(encoding="utf-8-sig")
    for module in ("op_board", "op_service", "op_engine"):
        text = re.sub(r"\b" + module + r"\b", module + "_tile_before", text)
    (HERE / (path.stem + "_tile_before.sv")).write_text(text, encoding="utf-8")
