"""XSim专用离线Golden；不修改PC客户端、冻结参数或工程ROM。"""
from pathlib import Path
import csv
import hashlib
import json
import shutil
import struct
import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OUT = HERE / "vectors"
OUT.mkdir(exist_ok=True)
SOURCE = ROOT / "src/params"
OLD = HERE.parent / "op_rom/vectors"
rows = list(csv.DictReader((SOURCE / "quantized_params_rom_address_map.tsv").open(encoding="utf-8"), delimiter="\t"))
FULL_COE = ROOT / "src/host/python/bin_udp/assets/quantized_params_rom_full.coe"
coe = FULL_COE.read_text().split("memory_initialization_vector=")[-1]
if "memory_initialization_vector" in coe:
    raise ValueError("Unexpected COE format")
image = b"".join(int(w.strip(), 16).to_bytes(8, "little") for w in coe.strip().rstrip(";").split(","))
rom_coe = (SOURCE / "quantized_params_rom.coe").read_text().split("memory_initialization_vector=")[-1]
rom_image = b"".join(int(w.strip(),16).to_bytes(8,"little") for w in rom_coe.strip().rstrip(";").split(","))
assert image[:len(rom_image)] == rom_image
cases, evidence = [], []


def write_hex(path, data):
    path.write_text("".join(f"{v:02x}\n" for v in data), encoding="ascii")


def pack16(a):
    c, h, w = a.shape
    assert c % 16 == 0
    return a.reshape(c // 16, 16, h, w).transpose(0, 2, 3, 1).tobytes()


def address(model, name):
    row = next(r for r in rows if r["model"] == model and r["file"] == name)
    addr = int(row["request_byte_addr"], 16)
    return addr - 0x159600 + 0x08000000 if model == "tumor" else addr


def descriptor(op, cin, cout, w, h, a, q, *, b=0, weights=0, params=0, flags=0, groups=None, shift=24):
    d = bytearray(64)
    d[:4] = bytes((op, flags, cin & 255, cout & 255))
    struct.pack_into("<HHH", d, 4, w, h, groups or (cout // 16))
    d[10:13] = bytes((shift, 0, 127))
    for off, value in ((16,a),(20,b),(24,q),(32,weights),(36,params),(48,0x4d000000+len(cases)+1)):
        struct.pack_into("<I", d, off, value)
    struct.pack_into("<HH", d, 52, cin, cout)
    return d


def save_case(name, d, golden, uploads=()):
    folder = OUT / name
    folder.mkdir(exist_ok=True)
    write_hex(folder / "descriptor.hex", d)
    write_hex(folder / "golden.hex", golden)
    lines = []
    for i, (addr, data) in enumerate(uploads):
        file = f"{name}/input_{i}.hex"
        write_hex(OUT / file, data)
        lines.append(f"{addr:08x} {len(data)} {file}\n")
    (folder / "uploads.txt").write_text("".join(lines), encoding="ascii")
    cases.append(f"{name} {len(golden)} 0\n")
    evidence.append({"case": name, "golden_sha256": hashlib.sha256(golden).hexdigest(), "bytes": len(golden)})


def rne(a, shift):
    q, r = np.divmod(a, np.int64(1 << shift))
    return q + ((r * 2 > (1 << shift)) | ((r * 2 == (1 << shift)) & ((q & 1) != 0)))


for model in ("vessel", "airway", "lobe", "tumor"):
    version = "20261012_tumor_base64_epoch70_v1" if model == "tumor" else "20261011_ptq_qat_v2"
    export = ROOT / "src/params/int8" / model
    contract = json.loads((export / "contract.json").read_text(encoding="utf-8"))
    cap = export / "golden_synthetic_32x32"
    manifest = json.loads((cap / "manifest.json").read_text(encoding="utf-8"))

    def tensor(name):
        spec = manifest["tensors"][name]
        data = (cap / (name + ".bin")).read_bytes()
        assert hashlib.sha256(data).hexdigest() == spec["sha256"], (model, name)
        return np.frombuffer(data, dtype=np.dtype(spec["dtype"]).newbyteorder("<")).reshape(spec["shape"])[0]

    x = tensor("e3.out")
    c, h, w = x.shape
    x = x.reshape(c, h//2, 2, w//2, 2).max(axis=(2, 4))
    h, w = x.shape[1:]
    expanded, mix, final = (tensor("mid." + n) for n in ("expand", "mix", "out"))
    hidden, cout = expanded.shape[0], final.shape[0]
    # 独立离线整数运算同时核对冻结Golden与当前ROM/DDR参数镜像。
    def verify_weight(name):
        spec = contract["convolutions"]["mid." + name]
        data = (export / spec["file"]).read_bytes()
        row = next(r for r in rows if r["model"] == model and r["file"] == spec["file"])
        offset = int(row["start_word"]) * 8
        weight = np.frombuffer(data, dtype=np.int8).reshape(spec["shape"])
        if name.startswith("dw"):
            assert image[offset:offset+len(data)] == data
        else:
            co, ci = weight.shape[:2]
            packed = weight.reshape(co//4, 4, ci//16, 16).transpose(0, 2, 1, 3).tobytes()
            assert image[offset:offset+len(packed)] == packed, (model,name,offset,image[offset:offset+32].hex(),packed[:32].hex())
        return weight.astype(np.int64)

    for name, source in (("expand",x),("project",mix),("skip",x)):
        weight = verify_weight(name)
        mac = (weight[:,:,0,0] @ source.reshape(source.shape[0], -1).astype(np.int64)).reshape(weight.shape[0], h, w)
        assert np.array_equal(mac, tensor("mid." + name + ".mac")), (model, name, "MAC")
    for k in (3, 5):
        weight = verify_weight(f"dw{k}")
        padded = np.pad(expanded.astype(np.int64), ((0,0),(k//2,k//2),(k//2,k//2)))
        mac = np.zeros_like(expanded, dtype=np.int64)
        for y in range(k):
            for z in range(k):
                mac += padded[:,y:y+h,z:z+w] * weight[:,0,y,z,None,None]
        assert np.array_equal(mac, tensor(f"mid.dw{k}.mac")), (model, k, "MAC")
    for name, lhs, rhs in (("mix","dw3","dw5"),("out","project","skip")):
        spec = contract["merges"]["mid."+name]
        ma, mb = (np.array(v,dtype=np.int64) for v in spec["multipliers"])
        bias = np.fromfile(export / spec["bias_file"], dtype="<i8")
        total = tensor("mid."+lhs+".mac").astype(np.int64)*ma[:,None,None] + tensor("mid."+rhs+".mac").astype(np.int64)*mb[:,None,None] + bias[:,None,None]
        q = np.clip(rne(total,spec["shift"]), 0, 127).astype(np.int8)
        assert np.array_equal(q,tensor("mid."+name)), (model,name,"RNE")

    # 每段输出独占区域；后续uploads为空，绝不以Golden回填阶段输入。
    a, ex, d3, d5, mx, pr, sk, out = [0x03000000+i*0x100000 for i in range(8)]
    initial = [(a,pack16(x))]
    if model == "tumor":
        initial.append((0x08000000,image[0x59600:0x1bd240]))
    for name, inp, dst, channels_in, channels_out, flags, uploads in (
        ("expand",a,ex,c,hidden,0,initial),
        ("dw3",ex,d3,hidden,hidden,0,()),
        ("dw5",ex,d5,hidden,hidden,0,()),
        ("mix",d3,mx,hidden,hidden,0,()),
        ("project",mx,pr,hidden,cout,20,()),
        ("skip",a,sk,c,cout,20,()),
        ("out",pr,out,cout,cout,0,()),
    ):
        if name in ("mix","out"):
            d = descriptor(6,channels_in,channels_out,w,h,inp,dst,b=d5 if name=="mix" else sk,
                           params=address(model,f"mid.{name}.params"),shift=contract["merges"]["mid."+name]["shift"])
        else:
            op = {"dw3":8,"dw5":9}.get(name,1)
            d = descriptor(op,channels_in,channels_out,w,h,inp,dst,flags=flags,
                           weights=address(model,f"mid.{name}.weight.i8.bin"),
                           params=address(model,f"mid.{name}.params") if op==1 else 0)
        raw = name in ("dw3","dw5","project","skip")
        gold = tensor("mid."+name+(".mac" if raw else ""))
        save_case(model+"_mid_"+name,d,pack16(gold),uploads)

# 旧算子全套快速回归；仅把tumor参数地址适配为已上线的DDR窗口。
for line in (OLD / "cases_fast.txt").read_text().splitlines():
    name, size, mac = line.split()
    source, dest = OLD / name, OUT / ("legacy_"+name)
    shutil.copytree(source, dest, dirs_exist_ok=True)
    d = bytearray.fromhex((source / "descriptor.hex").read_text())
    for off in (32,36):
        addr = struct.unpack_from("<I",d,off)[0]
        if 0x159600 <= addr < 0x2bd240:
            struct.pack_into("<I",d,off,addr-0x159600+0x08000000)
    write_hex(dest / "descriptor.hex",d)
    lines=[]
    for i, line in enumerate((source / "uploads.txt").read_text().splitlines()):
        addr, length, file = line.split()
        target=f"{dest.name}/upload_{i}.hex"
        shutil.copyfile(OLD / file, OUT / target)
        lines.append(f"{addr} {length} {target}\n")
    (dest / "uploads.txt").write_text("".join(lines),encoding="ascii")
    cases.append(f"{dest.name} {size} {mac}\n")
(OUT / "cases.txt").write_text("".join(cases), encoding="ascii")
(OUT / "cases_chain.txt").write_text("".join(cases[:28]), encoding="ascii")
print(f"[VECTORS PASSED] frozen mkdc chains=4 stages=28 total_cases={len(cases)}")

# 定向边界单独列出：1x1补边、奇数宽高/三组、PW跨16像素块的P16写回。
edge_start = len(cases)
rng = np.random.default_rng(20261015)
for k, h, w, groups in ((3,1,1,1),(5,3,5,3)):
    x = rng.integers(-128,128,(groups*16,h,w),dtype=np.int16).astype(np.int8)
    weight = rng.integers(-127,128,(groups*16,k,k),dtype=np.int16).astype(np.int8)
    pad = np.pad(x.astype(np.int64),((0,0),(k//2,k//2),(k//2,k//2)))
    mac = np.zeros_like(x,dtype=np.int64)
    for y in range(k):
        for z in range(k):
            mac += pad[:,y:y+h,z:z+w] * weight[:,y,z,None,None].astype(np.int64)
    d = descriptor(8 if k==3 else 9,groups*16,groups*16,w,h,0x03000000,0x06000000,weights=0x081f0000)
    save_case(f"edge_dw{k}_{w}x{h}_g{groups}",d,pack16(mac.astype('<i4')),
              [(0x03000000,pack16(x)),(0x081f0000,weight.tobytes())])
x = rng.integers(-128,128,(16,3,11),dtype=np.int16).astype(np.int8)
weight = rng.integers(-127,128,(32,16),dtype=np.int16).astype(np.int8)
mac = (weight.astype(np.int64) @ x.reshape(16,-1).astype(np.int64)).reshape(32,3,11).astype('<i4')
d = descriptor(1,16,32,11,3,0x03000000,0x06000000,weights=0x081f0000,params=0x081f1000,flags=20)
params = struct.pack('<iqhh',0,0,-128,127)*32
save_case('edge_pw_raw_p16_multitile',d,pack16(mac),[(0x03000000,pack16(x)),(0x081f0000,weight.tobytes()),(0x081f1000,params)])
(OUT / 'cases_edge.txt').write_text(''.join(cases[edge_start:]),encoding='ascii')
(OUT / 'cases_all.txt').write_text(''.join(cases),encoding='ascii')
(HERE / "vector_manifest.json").write_text(json.dumps({"cases":len(cases),"chain_stages":28,"edge_cases":3,
    "coe_sha256":hashlib.sha256((SOURCE / "quantized_params_rom.coe").read_bytes()).hexdigest(),
    "full_coe_sha256":hashlib.sha256(FULL_COE.read_bytes()).hexdigest(),"golden":evidence},indent=2),encoding="utf-8")
print('[VECTORS PASSED] directed edge cases=3')
