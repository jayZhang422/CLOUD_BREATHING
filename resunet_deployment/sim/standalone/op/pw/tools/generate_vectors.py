#!/usr/bin/env python3
"""只读冻结包，独立 NumPy INT64 MAC + Python divmod RNE；不训练、不重新量化。"""
from pathlib import Path
import hashlib, json, os, numpy as np

ROOT = Path(__file__).resolve().parents[1]
VERIFY_ROOT = Path(os.environ.get("PW_VERIFICATION_DIR", ROOT / "verification"))
OUT = VERIFY_ROOT / "vectors"
OUT.mkdir(parents=True, exist_ok=True)
cases = []
provenance = {}

def hexfile(path, values, bits):
    path.write_text("".join(f"{int(v) & ((1 << bits)-1):0{bits//4}x}\n" for v in values))

def pack(values, bits):
    return sum((int(v) & ((1 << bits)-1)) << (i*bits) for i,v in enumerate(values))

def rne(value, shift):
    quotient, remainder = divmod(int(value), 1 << shift)
    half = 1 << shift
    return quotient + (2*remainder > half or (2*remainder == half and quotient & 1))

def write_case(name, x, w, mac, q=None, mult=None, bias=None, shift=24, lower=-128, upper=127, int16=False):
    cout, cin = w.shape
    pixels = x.shape[1]
    raw = q is None
    ig, og = (cin+15)//16, (cout+3)//4
    directory = OUT / name
    directory.mkdir(exist_ok=True)
    # 无效通道故意填垃圾，验证核心掩码，而非依赖离线填零。
    stim = []
    for group in range(ig):
        for pixel in range(pixels):
            stim.append(pack([x[c,pixel] if c < cin else -77 for c in range(group*16,group*16+16)], 8))
    weights = []
    params = []
    if mult is None: mult = [0]*cout
    if bias is None: bias = [0]*cout
    lows = [lower]*cout if np.isscalar(lower) else list(lower)
    highs = [upper]*cout if np.isscalar(upper) else list(upper)
    for group in range(og):
        for ingroup in range(ig):
            weights.append(pack([w[c,k] if c < cout and k < cin else 113
                                 for c in range(group*4,group*4+4)
                                 for k in range(ingroup*16,ingroup*16+16)], 8))
        words = []
        for c in range(group*4,group*4+4):
            words.append((int(mult[c]) & 0xffffffff) |
                         ((int(bias[c]) & ((1<<64)-1)) << 32) |
                         ((int(lows[c]) & 0xffff) << 96) |
                         ((int(highs[c]) & 0xffff) << 112) if c < cout else 0)
        params.append(pack(words,128))
    exp_mac, exp_q, tags, requests = [], [], [], []
    for tile in range(0,pixels,16):
        count = min(16,pixels-tile)
        for ingroup in range(ig):
            requests.extend(ingroup*pixels+p for p in range(tile,tile+count))
        for group in range(og):
            mask = (1 << min(4,cout-group*4))-1
            for pixel in range(tile,tile+count):
                channels = range(group*4,group*4+4)
                exp_mac.append(pack([mac[c,pixel] if c < cout else 0 for c in channels],32))
                exp_q.append(pack([q[c,pixel] if c < cout and not raw else 0 for c in channels],16))
                last = pixel == pixels-1 and group == og-1
                tags.append(pixel | (group<<19) | (mask<<26) | (int(last)<<30))
    for file, values, bits in (("stimulus.hex",stim,128),("weights.hex",weights,512),
                              ("params.hex",params,512),("mac.hex",exp_mac,128),
                              ("golden.hex",exp_q,64),("tags.hex",tags,32),("requests.hex",requests,32)):
        hexfile(directory/file,values,bits)
    cases.append(dict(name=name,cin=cin,cout=cout,pixels=pixels,shift=shift,raw=raw,int16=int16,
                      inputs=len(stim),outputs=len(tags)))

for task in ("lobe","airway","vessel"):
    export = ROOT.parents[3]/"src/params/int8"/task
    contract = json.loads((export/"contract.json").read_text())
    source = export/"golden_synthetic_32x32"
    manifest = json.loads((source/"manifest.json").read_text())
    provenance[task] = {"contract_sha256":hashlib.sha256((export/"contract.json").read_bytes()).hexdigest(),
                        "checked_golden_files":0,"weight_sha256":{},"bias_sha256":{}}
    tensors = {}
    for name, spec in manifest["tensors"].items():
        data = (source/(name+".bin")).read_bytes()
        assert hashlib.sha256(data).hexdigest() == spec["sha256"], (task,name,"SHA256")
        tensors[name] = np.frombuffer(data,dtype=np.dtype(spec["dtype"]).newbyteorder("<")).reshape(spec["shape"])[0]
        provenance[task]["checked_golden_files"] += 1
    def block_input(block):
        if block == "e1": return tensors["input"]
        previous = {"e2":"e1","e3":"e2","mid":"e3"}
        if block in previous:
            a=tensors[previous[block]+".out"]
            c,h,w=a.shape
            return a.reshape(c,h//2,2,w//2,2).max(axis=(2,4))
        return np.concatenate([tensors[block+".concat_up"],tensors[block+".concat_skip"]],axis=0)
    for name, spec in contract["convolutions"].items():
        if spec["shape"][2:] != [1,1] or spec["groups"] != 1: continue
        weight_data = (export/spec["file"]).read_bytes()
        provenance[task]["weight_sha256"][name]=hashlib.sha256(weight_data).hexdigest()
        w=np.frombuffer(weight_data,dtype=np.int8).reshape(spec["shape"][:2])
        if name=="head": x=tensors["d1.out"]
        else:
            block,suffix=name.split(".")
            x=tensors[block+".mix"] if suffix=="project" else block_input(block)
        x=x.reshape(w.shape[1],-1)
        mac=w.astype(np.int64) @ x.astype(np.int64)
        frozen_mac=tensors[name+".mac"].reshape(w.shape[0],-1)
        assert np.array_equal(mac,frozen_mac), (task,name,"independent MAC != frozen")
        assert np.abs(mac).max() < (1<<31)
        if name in contract["merges"] and len(contract["merges"][name]["multipliers"]) == 1:
            cfg=contract["merges"][name]
            bias_data=(export/cfg["bias_file"]).read_bytes()
            provenance[task]["bias_sha256"][name]=hashlib.sha256(bias_data).hexdigest()
            bias=np.frombuffer(bias_data,dtype="<i8")
            mult=cfg["multipliers"][0]
            low=0 if cfg["relu6"] else -(1<<(cfg["bits"]-1))
            high=min((1<<(cfg["bits"]-1))-1,round(6/cfg["output_scale"])) if cfg["relu6"] else (1<<(cfg["bits"]-1))-1
            q=np.array([[min(high,max(low,rne(int(v)*int(mult[c])+int(bias[c]),cfg["shift"])))
                         for v in row] for c,row in enumerate(mac)],dtype=np.int64)
            assert np.array_equal(q,tensors[name].reshape(w.shape[0],-1)), (task,name,"RNE != frozen")
            write_case(task+"_"+name,x,w,mac,q,mult,bias,cfg["shift"],low,high,cfg["bits"]==16)
        else:
            write_case(task+"_"+name,x,w,mac)

# Tumor base64 frozen Golden: exercise first, largest and INT16-head PW layers.
tumor_export = ROOT.parents[3] / "src/params/int8/tumor"
tumor_golden = tumor_export / "golden_synthetic_32x32"
tumor_contract = json.loads((tumor_export/"contract.json").read_text())
tumor_manifest = json.loads((tumor_golden/"manifest.json").read_text())
tumor_tensors = {}
for name,spec in tumor_manifest["tensors"].items():
    data=(tumor_golden/(name+".bin")).read_bytes()
    assert hashlib.sha256(data).hexdigest()==spec["sha256"], ("tumor",name,"SHA256")
    tumor_tensors[name]=np.frombuffer(data,dtype=np.dtype(spec["dtype"]).newbyteorder("<")).reshape(spec["shape"])[0]
tumor_inputs = {
    "e1.expand": tumor_tensors["input"],
    "mid.project": tumor_tensors["mid.mix"],
    "d3.expand": np.concatenate([tumor_tensors["d3.concat_up"],tumor_tensors["d3.concat_skip"]],axis=0),
    "head": tumor_tensors["d1.out"],
}
for name in ("e1.expand","mid.project","d3.expand","head"):
    spec=tumor_contract["convolutions"][name]
    assert spec["shape"][2:]==[1,1] and spec["groups"]==1, ("tumor",name,"not PW")
    w=np.frombuffer((tumor_export/spec["file"]).read_bytes(),dtype=np.int8).reshape(spec["shape"][:2])
    x=tumor_inputs[name].reshape(w.shape[1],-1)
    mac=w.astype(np.int64) @ x.astype(np.int64)
    frozen_mac=tumor_tensors[name+".mac"].reshape(w.shape[0],-1)
    assert np.array_equal(mac,frozen_mac) and np.abs(mac).max() < (1<<31), ("tumor",name,"MAC != frozen")
    if name in tumor_contract["merges"]:
        cfg=tumor_contract["merges"][name]
        bias=np.frombuffer((tumor_export/cfg["bias_file"]).read_bytes(),dtype="<i8")
        mult=cfg["multipliers"][0]
        low=0 if cfg["relu6"] else -(1<<(cfg["bits"]-1))
        high=min((1<<(cfg["bits"]-1))-1,round(6/cfg["output_scale"])) if cfg["relu6"] else (1<<(cfg["bits"]-1))-1
        q=np.array([[min(high,max(low,rne(int(v)*int(mult[c])+int(bias[c]),cfg["shift"])))
                     for v in row] for c,row in enumerate(mac)],dtype=np.int64)
        assert np.array_equal(q,tumor_tensors[name].reshape(w.shape[0],-1)), ("tumor",name,"RNE != frozen")
        write_case("tumor_"+name,x,w,mac,q,mult,bias,cfg["shift"],low,high,cfg["bits"]==16)
    else:
        write_case("tumor_"+name,x,w,mac)

rng=np.random.default_rng(20261011)
for cin,cout,pixels in ((1,1,1),(17,5,19),(191,127,17),(192,128,33),(3,2,1),
                        (768,512,1),(767,511,3)):
    x=rng.integers(-128,128,(cin,pixels),dtype=np.int16).astype(np.int8)
    w=rng.integers(-128,128,(cout,cin),dtype=np.int16).astype(np.int8)
    mac=w.astype(np.int64) @ x.astype(np.int64)
    mult=[(-1 if c%2 else 1)*(1<<20) for c in range(cout)]
    bias=[(-1 if c%3 else 1)*(1<<42) for c in range(cout)]
    q=np.array([[min(32767,max(-32768,rne(int(v)*mult[c]+bias[c],24))) for v in row]
                 for c,row in enumerate(mac)],dtype=np.int64)
    write_case(f"directed_{cin}_{cout}_{pixels}",x,w,mac,q,mult,bias,24,-32768,32767,True)
# 满量程正负乘积、长通道累加；零 shift / signed INT8 两端饱和。
x=np.array([[-128,127,-128,127,-1,1,0]],dtype=np.int8)
w=np.array([[-128],[127],[1],[-1],[0]],dtype=np.int8)
mac=w.astype(np.int64)@x.astype(np.int64)
q=np.clip(mac,-128,127)
write_case("shift0_signed_saturation",x,w,mac,q,[1]*5,[0]*5,0,-128,127)
# 最大部署像素数：512×512，连续跨越所有块，验证计数器/末标记不提前回卷。
x=np.resize(np.array([-128,-127,-1,0,1,126,127],dtype=np.int8),262144).reshape(1,-1)
w=np.array([[1]],dtype=np.int8)
mac=x.astype(np.int64)
write_case("full_frame_512",x,w,mac,mac,[1],[0],0,-128,127)
(OUT/"cases.json").write_text(json.dumps(cases,indent=2))
(VERIFY_ROOT/"provenance.json").write_text(json.dumps(provenance,indent=2))
# 独立再量化边界：Python大整数参考；输入覆写复位另由SpinalSim完成。
quant=[]
for shift in (0,1,2,24,31,62):
    denominator=1<<shift
    numerators=set([0,1,-1,(1<<61)-1,-((1<<61)-1)])
    if shift:
        for integer in (-5,-4,-1,0,1,4,5):
            for delta in (-1,0,1):
                n=integer*denominator+denominator//2+delta
                if abs(n)<(1<<62): numerators.add(n)
    for n in sorted(numerators):
        # acc*mult + bias，以非零有符号乘法检查64位缩放。
        acc=-2147483648 if n<0 else 2147483647
        mult=-2147483648 if n<0 else 2147483647
        product=acc*mult
        bias=n-product
        assert -(1<<63)<=bias<(1<<63)
        for low,high in ((-128,127),(0,93),(-32768,32767)):
            quant.append(dict(acc=acc,mult=mult,bias=bias,shift=shift,lower=low,upper=high,
                              expected=min(high,max(low,rne(n,shift)))))
# 无饱和掩盖的正负乘数、正负输入与 shift；参考保持在上位机。
for acc in (-128,-1,1,127):
    for mult in (-126,-1,1,127):
        for bias in (-7,0,7):
            for shift in (0,4,24):
                quant.append(dict(acc=acc,mult=mult,bias=bias,shift=shift,lower=-32768,upper=32767,
                                  expected=min(32767,max(-32768,rne(acc*mult+bias,shift)))))
(VERIFY_ROOT/"quant_cases.json").write_text(json.dumps(quant))
print(f"[VECTORS PASSED] cases={len(cases)} frozen_pw=66 quant_boundaries={len(quant)}")

import csv
with (OUT/"cases.csv").open("w") as f:
    writer=csv.writer(f)
    for c in cases: writer.writerow([c[k] if not isinstance(c[k],bool) else int(c[k]) for k in ("name","cin","cout","pixels","shift","raw","int16")])
with (VERIFY_ROOT/"quant_cases.csv").open("w") as f:
    writer=csv.writer(f)
    for c in quant: writer.writerow([c[k] for k in ("acc","mult","bias","shift","lower","upper","expected")])
