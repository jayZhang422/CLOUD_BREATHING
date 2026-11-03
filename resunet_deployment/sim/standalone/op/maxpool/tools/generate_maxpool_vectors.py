"""独立 NumPy signed INT8 池化 Golden；不实现硬件 RAM/流水控制。"""
import argparse
import csv
from pathlib import Path
import numpy as np

CASES = [
    ("minimum", 2, 2, 3, "random"),
    ("odd", 5, 3, 3, "random"),
    ("odd_width", 13, 8, 2, "random"),
    ("odd_height", 8, 13, 2, "random"),
    ("narrow", 2, 17, 2, "random"),
    ("short", 17, 2, 2, "random"),
    ("full64", 64, 64, 12, "continuous"),
    ("full128", 128, 128, 1, "continuous"),
    ("full256", 256, 256, 1, "continuous"),
    ("full512", 512, 512, 1, "continuous"),
    ("stress512", 512, 512, 2, "random"),
    ("reset_mid", 23, 11, 2, "reset_mid"),
    ("reset_stalled", 23, 11, 2, "reset_stalled"),
    ("max_groups", 16, 16, 32, "random"),
    ("signed_edges", 4, 4, 3, "random"),
    ("odd_tail", 5, 5, 1, "tail_stall"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "verification/deployment")
    root = parser.parse_args().out
    root.mkdir(parents=True, exist_ok=True)
    with (root / "cases.csv").open("w", newline="") as manifest:
        writer = csv.writer(manifest)
        writer.writerow(["case", "width", "height", "groups", "seed", "mode"])
        for index, (name, width, height, groups, mode) in enumerate(CASES):
            seed = 20261011 + index
            rng = np.random.default_rng(seed)
            directory = root / name
            directory.mkdir(exist_ok=True)
            with (directory / "stimulus.hex").open("w") as stimulus, (directory / "golden.hex").open("w") as golden:
                for group in range(groups):
                    image = rng.integers(-128, 128, size=(height, width, 16), dtype=np.int16).astype(np.int8)
                    if group % 3 == 1:
                        image = ((np.arange(image.size).reshape(image.shape) + group * 37) % 256 - 128).astype(np.int8)
                    elif group % 3 == 2:
                        image = np.where(np.indices(image.shape).sum(axis=0) % 2, 127, -128).astype(np.int8)
                    if name == "signed_edges":
                        # 每个 lane 不同正负模式，包含全负数、相等值和 -128/127 边界。
                        values = np.array([-128, -127, -64, -1, 0, 1, 126, 127], dtype=np.int8)
                        image = values[(np.indices(image.shape).sum(axis=0) + group) % len(values)]
                        image[:, :, 0] = -128
                        image[:, :, 1] = -1
                        image[:, :, 2] = 127
                    for pixel in image.reshape(-1, 16):
                        stimulus.write(pixel.view(np.uint8)[::-1].tobytes().hex() + "\n")
                    cropped = image[:height // 2 * 2, :width // 2 * 2]
                    pooled = cropped.reshape(height // 2, 2, width // 2, 2, 16).max(axis=(1, 3))
                    for word in pooled.reshape(-1, 16):
                        golden.write(word.view(np.uint8)[::-1].tobytes().hex() + "\n")
            writer.writerow([name, width, height, groups, seed, mode])
            print(f"{name}: inputs={width * height * groups} outputs={width // 2 * (height // 2) * groups}")


if __name__ == "__main__":
    main()
