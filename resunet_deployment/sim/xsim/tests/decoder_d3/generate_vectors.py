"""XSim专用：复用独立NumPy整数Golden，核对工程ROM；不导入或修改PC客户端。"""
from pathlib import Path
import csv
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / "vectors"
SOURCE = ROOT / "src/params"
EXPORT = ROOT / "src/params/int8/vessel"


def write_hex(path, data):
    path.write_text("".join(f"{v:02x}\n" for v in data), encoding="ascii")


def pack16(a):
    c, h, w = a.shape
    return a.reshape(c//16, 16, h, w).transpose(0, 2, 3, 1).tobytes()


def main():
    OUT.mkdir(exist_ok=True)
    rows = list(csv.DictReader((SOURCE / "quantized_params_rom_address_map.tsv").open(encoding="utf-8"), delimiter="\t"))
    coe = (SOURCE / "quantized_params_rom.coe").read_text().split("memory_initialization_vector=")[-1]
    rom = b"".join(int(w.strip(), 16).to_bytes(8, "little") for w in coe.strip().rstrip(";").split(","))
    contract = json.loads((EXPORT / "contract.json").read_text(encoding="utf-8"))
    cases, hashes = [], {}

    def addr(name):
        row = next(r for r in rows if r["model"] == "vessel" and r["file"] == name)
        return int(row["request_byte_addr"], 16)

    def check_rom(name, data):
        offset = addr(name) - 0x100000
        assert rom[offset:offset+len(data)] == data, name

    def save(name, op, w, h, groups, a, q, gold, uploads=(), b=0, gb=0, cin=0, cout=0, flags=0, weights=0, params=0, shift=24):
        folder = OUT / name
        folder.mkdir(exist_ok=True)
        d = bytearray(64)
        d[:4] = bytes((op, flags, cin & 255, cout & 255))
        struct.pack_into("<HHH", d, 4, w, h, groups)
        d[10:13] = bytes((shift, 0, 127))
        struct.pack_into("<H", d, 14, gb)
        for off, value in ((16,a),(20,b),(24,q),(32,weights),(36,params),(48,0x55000001+len(cases))):
            struct.pack_into("<I", d, off, value)
        struct.pack_into("<HH", d, 52, cin, cout)
        write_hex(folder / "descriptor.hex", d)
        write_hex(folder / "golden.hex", gold)
        entries=[]
        for i, (base, data) in enumerate(uploads):
            file=f"{name}/input_{i}.hex"
            write_hex(OUT / file, data)
            entries.append(f"{base:08x} {len(data)} {file}\n")
        (folder / "uploads.txt").write_text("".join(entries),encoding="ascii")
        cases.append(f"{name} {len(gold)} 0\n")
        hashes[name] = hashlib.sha256(gold).hexdigest()

    # 每次重新执行独立算法并验证冻结SHA256，临时目录仅保存离线小向量。
    with tempfile.TemporaryDirectory(prefix="decoder_golden_") as temp:
        reference = Path(temp) / "reference"
        subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "sim/standalone/op/decoder_d3/tools/generate_vectors.py"), "--out", str(reference)], check=True)

        def data(name, nbytes=16):
            return b"".join(int(v,16).to_bytes(nbytes,"little") for v in (reference / (name+".hex")).read_text().split())

        provenance = json.loads((reference / "provenance.json").read_text(encoding="utf-8"))
        (OUT / "provenance.json").write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding="utf-8")
        for name in ("expand","project","skip"):
            check_rom(f"d3.{name}.weight.i8.bin", data(name+"_weights",64))
            # raw模式不执行量化；工程的既有占位乘数为1，独立仿真占位为0。
            check_rom(f"d3.{name}.params", data(name+"_params",64) if name=="expand" else struct.pack("<iqhh",1,0,-128,127)*64)
        for k in (3,5):
            check_rom(f"d3.dw{k}.weight.i8.bin", data(f"dw{k}_weights",16*k*k))
        for name in ("mix","out"):
            cfg=contract["merges"]["d3."+name]
            bias=np.fromfile(EXPORT / cfg["bias_file"],dtype="<i8")
            check_rom(f"d3.{name}.params",b"".join(struct.pack("<iiq",int(a),int(b),int(c)) for a,b,c in zip(*cfg["multipliers"],bias)))

        low, enc, up, cat, ex, d3, d5, mix, proj, skip, final = [0x03000000+i*0x100000 for i in range(11)]
        write_hex(OUT / "encoder_skip.hex",data("encoder_skip"))
        save("vessel_d3_up",10,4,4,8,low,up,data("up_golden"),[(low,data("mid")),(enc,data("encoder_skip"))])
        save("vessel_d3_concat",5,8,8,8,up,cat,data("concat_golden"),b=enc,gb=4)
        for name, a, q, ci, co, gold in (
            ("expand",cat,ex,192,64,"expand_golden"),
            ("dw3",ex,d3,64,64,"dw3_mac"),
            ("dw5",ex,d5,64,64,"dw5_mac"),
            ("mix",d3,mix,64,64,"mix_golden"),
            ("project",mix,proj,64,64,"project_mac"),
            ("skip",cat,skip,192,64,"skip_mac"),
            ("out",proj,final,64,64,"final_golden"),
        ):
            raw=name in ("dw3","dw5","project","skip")
            op={"dw3":8,"dw5":9,"mix":6,"out":6}.get(name,1)
            save("vessel_d3_"+name,op,8,8,co//16,a,q,data(gold,64 if raw else 16),
                 b=d5 if name=="mix" else skip if name=="out" else 0,cin=ci,cout=co,
                 flags=20 if name in ("project","skip") else 0,
                 weights=addr(f"d3.{name}.weight.i8.bin") if op!=6 else 0,
                 params=addr(f"d3.{name}.params") if op in (1,6) else 0,
                 shift=contract["merges"]["d3."+name]["shift"] if op==6 else 24)
    (OUT / "cases_chain.txt").write_text("".join(cases),encoding="ascii")
    rng=np.random.default_rng(20261016)
    start=len(cases)
    for w,h,g in ((1,1,1),(5,3,32),(256,1,1),(1,256,1),(256,256,1)):
        x=rng.integers(-128,128,(16*g,h,w),dtype=np.int16).astype(np.int8)
        save(f"up_{w}x{h}_g{g}",10,w,h,g,0x03000010,0x06000000,pack16(x.repeat(2,1).repeat(2,2)),[(0x03000010,pack16(x))])
    (OUT / "cases_edge.txt").write_text("".join(cases[start:-1]),encoding="ascii")
    (OUT / "cases_max.txt").write_text(cases[-1],encoding="ascii")
    (OUT / "cases_all.txt").write_text("".join(cases),encoding="ascii")
    (OUT / "cases_quick.txt").write_text("".join(cases[:-1]),encoding="ascii")
    (HERE / "vector_manifest.json").write_text(json.dumps({"seed":20261016,"cases":len(cases),"golden_sha256":hashes,"rom_sha256":hashlib.sha256((SOURCE / "quantized_params_rom.coe").read_bytes()).hexdigest()},indent=2))
    print(f"[VECTORS PASSED] d3 stages=9 independent Upsample cases=5 total={len(cases)} ROM weights/quantization exact")


if __name__ == "__main__":
    main()
