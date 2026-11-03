"""仿真专用：独立 NumPy nearest Golden，P16 小端字节流（gzip 无损压缩）。"""
import argparse
import csv
import gzip
import hashlib
import json
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[5]
CASES = [
    ("minimum", 1, 1, 1, "random"),
    ("one_pixel_32", 1, 1, 32, "random"),
    ("narrow", 1, 17, 3, "random"),
    ("short", 19, 1, 2, "random"),
    ("odd", 13, 7, 5, "random"),
    ("all_int8", 16, 4, 1, "continuous"),
    ("base16_mid", 64, 64, 8, "continuous"),
    ("base16_d3", 128, 128, 4, "continuous"),
    ("base16_d2", 256, 256, 2, "continuous"),
    ("base64_mid", 64, 64, 32, "random"),
    ("base64_d3", 128, 128, 16, "random"),
    ("base64_d2", 256, 256, 8, "random"),
    ("maximum_32", 256, 256, 32, "random"),
    ("reset_fill", 7, 5, 2, "reset_fill"),
    ("reset_emit", 9, 3, 1, "reset_emit"),
    ("reset_stalled", 5, 7, 32, "reset_stalled"),
    ("reset_last", 3, 5, 2, "reset_last"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    root = parser.parse_args().out
    root.mkdir(parents=True, exist_ok=False)
    provenance = []
    with (root / "cases.csv").open("w", newline="") as manifest:
        writer = csv.writer(manifest)
        writer.writerow(["case", "width", "height", "groups", "seed", "mode"])

        def emit(name, image, seed, mode):
            # 算法 Golden 在 NCHW 域 repeat，与 DUT 行缓存/计数控制独立。
            channels, height, width = image.shape
            assert image.dtype == np.int8 and channels % 16 == 0
            groups = channels // 16
            upsampled = image.repeat(2, axis=1).repeat(2, axis=2)
            directory = root / name
            directory.mkdir()
            for label, tensor in (("stimulus", image), ("golden", upsampled)):
                _, h, w = tensor.shape
                packed = tensor.reshape(groups, 16, h, w).transpose(0, 2, 3, 1).copy()
                with gzip.open(directory / f"{label}.bin.gz", "wb", compresslevel=1) as stream:
                    stream.write(packed.tobytes())
            writer.writerow([name, width, height, groups, seed, mode])
            print(f"{name}: {width}x{height} groups={groups} outputs={width*height*groups*4}")

        for index, (name, width, height, groups, mode) in enumerate(CASES):
            seed = 20261016 + index
            rng = np.random.default_rng(seed)
            image = rng.integers(-128, 128, (groups * 16, height, width), dtype=np.int16).astype(np.int8)
            if name == "all_int8":
                image = ((np.arange(image.size).reshape(image.shape) % 256) - 128).astype(np.int8)
            # 部分 lane 用可辨认的行列/组模式，同时保持随机 lane。
            for channel in range(0, groups * 16, 4):
                yy, xx = np.indices((height, width))
                image[channel] = ((yy * 43 + xx * 17 + channel * 11) % 256 - 128).astype(np.int8)
            emit(name, image, seed, mode)

        for task in ("lobe", "airway", "vessel", "tumor"):
            package = "20261012_tumor_base64_epoch70_v1" if task == "tumor" else "20261011_ptq_qat_v2"
            export = REPO / "src/params/int8" / task
            contract_path = export / "contract.json"
            contract = json.loads(contract_path.read_text())
            assert contract["features"] == "signed INT8, zero_point=0, per activation node"
            source = export / "golden_synthetic_32x32"
            tensors = json.loads((source / "manifest.json").read_text())["tensors"]
            for node in ("mid.out", "d3.out", "d2.out"):
                info = tensors[node]
                raw = (source / f"{node}.bin").read_bytes()
                digest = hashlib.sha256(raw).hexdigest()
                assert info["dtype"] == "int8" and digest == info["sha256"]
                image = np.frombuffer(raw, dtype=np.int8).reshape(info["shape"])[0]
                emit(f"{task}_{node}", image, 20261016, "random")
                provenance.append({"task": task, "node": node, "shape": info["shape"],
                    "source": str((source / f"{node}.bin").relative_to(REPO)), "sha256": digest,
                    "contract_sha256": hashlib.sha256(contract_path.read_bytes()).hexdigest(),
                    "scale_preserved": contract["activation_scales"][node]})
    (root / "provenance.json").write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
