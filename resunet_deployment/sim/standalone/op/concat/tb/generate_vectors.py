"""离线生成 NCHW Concat Golden，再打包成 [组][像素][16 通道]。"""
import hashlib
import json
from pathlib import Path
import random

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "verification"
EXPORTS = ROOT.parents[3] / "src/params/int8"


def packed(chw, channels, pixels):
    assert channels % 16 == 0 and len(chw) == channels * pixels
    view = memoryview(chw)
    for group in range(channels // 16):
        lanes = [view[(group * 16 + lane) * pixels:(group * 16 + lane + 1) * pixels]
                 for lane in range(16)]
        for word in zip(*lanes):
            yield bytes(reversed(word)).hex()


def write_case(name, width, height, c1, c2, a, b, mode):
    directory = OUT / name
    directory.mkdir(parents=True, exist_ok=True)
    pixels = width * height
    for filename, data, channels in (("stimulus1.hex", a, c1), ("stimulus2.hex", b, c2),
                                     ("golden.hex", a + b, c1 + c2)):
        with (directory / filename).open("w") as handle:
            handle.writelines(word + "\n" for word in packed(data, channels, pixels))
    words1, words2 = pixels * (c1 // 16), pixels * (c2 // 16)
    # 非零且相互独立的地址，另有跨 16-bit 边界的长图测试。
    return f"{name} {words1} {words2} 65521 1048589 {mode}\n"


def main():
    OUT.mkdir(exist_ok=True)
    rng = random.Random(20261011)
    cases = []
    synthetic = [("minimum", 1, 1, 16, 16, "random"),
                 ("odd", 13, 7, 16, 32, "random"),
                 ("full64", 64, 64, 128, 64, "continuous"),
                 ("full128", 128, 128, 128, 64, "continuous"),
                 ("full256", 256, 256, 64, 32, "continuous"),
                 ("full512", 512, 512, 32, 16, "continuous"),
                 ("reset_request", 17, 9, 32, 16, "reset_request"),
                 ("reset_response", 17, 9, 32, 16, "reset_response"),
                 ("reset_output", 17, 9, 32, 16, "reset_output")]
    for name, w, h, c1, c2, mode in synthetic:
        a = rng.randbytes(w * h * c1)
        b = rng.randbytes(w * h * c2)
        cases.append(write_case(name, w, h, c1, c2, a, b, mode))
    for model in ("lobe", "airway", "vessel"):
        export = EXPORTS / model
        contract = json.loads((export / "contract.json").read_text())
        directory = export / "golden_synthetic_32x32"
        manifest = json.loads((directory / "manifest.json").read_text())["tensors"]
        for stage in ("d3", "d2", "d1"):
            inputs = []
            for suffix in ("concat_up", "concat_skip"):
                key = f"{stage}.{suffix}"
                merge = contract["merges"][key]
                assert all(m == 2 ** merge["shift"] for row in merge["multipliers"] for m in row)
                assert not any((export / merge["bias_file"]).read_bytes())
                info = manifest[key]
                assert info["dtype"] == "int8" and info["shape"][0] == 1
                data = (directory / f"{key}.bin").read_bytes()
                assert hashlib.sha256(data).hexdigest() == info["sha256"]
                inputs.append((info["shape"], data))
            (_, c1, h, w), a = inputs[0]
            (_, c2, h2, w2), b = inputs[1]
            assert (h, w) == (h2, w2)
            cases.append(write_case(f"{model}_{stage}", w, h, c1, c2, a, b, "random"))
    (OUT / "cases.txt").write_text("".join(cases))
    print(f"Generated {len(cases)} Concat stimulus/Golden cases")


if __name__ == "__main__":
    main()
