"""本批验证资料：复用冻结 PW Golden，另生成稀疏权重的 op12 Golden。"""
from pathlib import Path
import hashlib
import json
import re
import struct

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PW = ROOT / "sim/standalone/op/pw/verification/stage3_pe16/vectors"
BEFORE = HERE / "results/before"


def write_hex(path, data):
    path.write_text("".join(f"{b:02x}\n" for b in data), encoding="ascii")


def prepare():
    # 改动前真实源码只改模块名，用于同周期对照；不改变任一算法或流水。
    refs = (
        ("src/rtl/op/pw/pwmac.v", "pwmac_before.v",
         {"PwMac": "PwMac_before", "PwRequant": "PwRequant_before"}),
        ("src/rtl/op/control/op_core_bank.sv", "op_core_bank_before.sv",
         {"op_core_bank": "op_core_bank_before", "PwMac": "PwMac_before"}),
    )
    for source, dest, names in refs:
        text = (BEFORE / source).read_text(encoding="utf-8-sig")
        for old, new in names.items():
            text = re.sub(rf"\b{old}\b", new, text)
        (HERE / dest).write_text(text, encoding="utf-8")
    engine = (ROOT / "src/rtl/op/control/op_engine.sv").read_text(encoding="utf-8-sig")
    engine = re.sub(r"\bop_engine\b", "op_engine_before", engine)
    engine = re.sub(r"\bop_core_bank\b", "op_core_bank_before", engine)
    (HERE / "op_engine_before.sv").write_text(engine, encoding="utf-8")

    selected = {
        "lobe_e1.expand", "lobe_mid.project", "tumor_mid.project", "tumor_d3.expand",
        "tumor_head", "directed_17_5_19", "directed_191_127_17", "directed_192_128_33",
        "directed_768_512_1", "directed_767_511_3", "shift0_signed_saturation",
    }
    cases = [c for c in json.loads((PW / "cases.json").read_text()) if c["name"] in selected]
    assert {c["name"] for c in cases} == selected
    manifest = []
    with (HERE / "pw_cases.txt").open("w", encoding="ascii") as f:
        for c in cases:
            f.write(f'{c["name"]} {c["cin"]} {c["cout"]} {c["pixels"]} {c["shift"]} '
                    f'{int(c["raw"])} {int(c["int16"])}\n')
            for name in ("stimulus.hex", "weights.hex", "params.hex", "mac.hex", "golden.hex", "tags.hex", "requests.hex"):
                path = PW / c["name"] / name
                manifest.append({"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    (HERE / "results/pw_vectors_sha256.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    # Golden 在主机离线计算；TB 仅提供握手、访存响应和逐字节核对。
    op12_cases = (("small_tail", 17, 3, 32, 33), ("max_banks", 768, 767, 512, 17))
    with (HERE / "op12_cases.txt").open("w", encoding="ascii") as f:
        for name, cin, cin_b, cout, pixels in op12_cases:
            folder = HERE / "vectors" / name
            folder.mkdir(parents=True, exist_ok=True)

            def sample(ch, pixel, branch):
                return ((ch * 3 + pixel * 5 + branch * 7) % 23) - 11

            def feature(channels, branch):
                return bytes(sample(ch, pixel, branch) & 255 if ch < channels else 0xA5
                             for group in range((channels + 15) // 16)
                             for pixel in range(pixels) for ch in range(group * 16, group * 16 + 16))

            def weights(channels, branch):
                data = bytearray()
                for group in range(cout // 4):
                    for ig in range((channels + 15) // 16):
                        for oc in range(group * 4, group * 4 + 4):
                            selected_ch = (oc * 37 + branch * 19) % channels
                            sign = -1 if (oc + branch) % 3 == 0 else 1
                            for ic in range(ig * 16, ig * 16 + 16):
                                data.append(sign & 255 if ic == selected_ch else 0)
                return data

            golden = bytearray()
            params = bytearray()
            for oc in range(cout):
                params += struct.pack("<iiq", 1 if oc % 2 else -1, 1, 48 + oc % 7)
            for group in range(cout // 16):
                for pixel in range(pixels):
                    for oc in range(group * 16, group * 16 + 16):
                        a = sample((oc * 37) % cin, pixel, 0) * (-1 if oc % 3 == 0 else 1)
                        b = sample((oc * 37 + 19) % cin_b, pixel, 1) * (-1 if (oc + 1) % 3 == 0 else 1)
                        golden.append(max(0, min(127, a * (1 if oc % 2 else -1) + b + 48 + oc % 7)))
            vectors = {"input_a": feature(cin, 0), "input_b": feature(cin_b, 1),
                       "weights_a": weights(cin, 0), "weights_b": weights(cin_b, 1),
                       "params": params, "golden": golden}
            for filename, data in vectors.items():
                write_hex(folder / f"{filename}.hex", data)
            f.write(f"{name} {cin} {cin_b} {cout} {pixels}\n")
    print(f"Prepared {len(cases)} frozen PW cases and {len(op12_cases)} op12 cases")


if __name__ == "__main__":
    prepare()
