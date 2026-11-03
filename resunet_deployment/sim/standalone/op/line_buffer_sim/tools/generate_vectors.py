"""离线生成 P=16 多组 INT8 图像和独立零补边窗口 Golden。"""
import argparse
import csv
from pathlib import Path
import numpy as np

SHAPES = [
    ("minimum", 1, 1, 3, "random"),
    ("odd", 13, 7, 2, "random"),
    ("narrow", 1, 9, 2, "random"),
    ("short", 9, 1, 2, "random"),
    ("tall", 7, 41, 3, "random"),
    ("full64", 64, 64, 12, "continuous"),
    ("full128", 128, 128, 1, "continuous"),
    ("full256", 256, 256, 1, "continuous"),
    ("full512", 512, 512, 1, "continuous"),
    ("stress64", 64, 64, 2, "random"),
    ("reset_mid", 23, 11, 2, "reset_mid"),
    ("reset_stalled", 23, 11, 2, "reset_stalled"),
    ("max_groups", 16, 16, 32, "random"),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "verification/deployment")
    root = parser.parse_args().out
    root.mkdir(parents=True, exist_ok=True)
    with (root / "cases.csv").open("w", newline="") as manifest:
        writer = csv.writer(manifest)
        writer.writerow(["case", "width", "height", "k", "groups", "seed", "mode"])
        for k in (3, 5):
            for index, (label, width, height, groups, mode) in enumerate(SHAPES):
                name = f"{label}_k{k}"
                seed = 20261011 + k * 100 + index
                rng = np.random.default_rng(seed)
                directory = root / name
                directory.mkdir(exist_ok=True)
                with (directory / "stimulus.hex").open("w") as stimulus, (directory / "golden.hex").open("w") as golden:
                    for group in range(groups):
                        image = rng.integers(-128, 128, size=(height, width, 16), dtype=np.int16).astype(np.int8)
                        if group % 3 == 1:
                            # 每 lane 不同图案，避免通道串线被相同输入掩盖。
                            image = ((np.arange(height * width * 16).reshape(height, width, 16)
                                      + group * 37) % 256 - 128).astype(np.int8)
                        elif group % 3 == 2:
                            image = np.where(np.indices(image.shape).sum(axis=0) % 2, 127, -128).astype(np.int8)
                        image[0, 0, 0] = -128
                        image[-1, -1, -1] = 127
                        for pixel in image.reshape(-1, 16):
                            stimulus.write(pixel.view(np.uint8)[::-1].tobytes().hex() + "\n")
                        padded = np.pad(image, ((k // 2, k // 2), (k // 2, k // 2), (0, 0)))
                        windows = np.lib.stride_tricks.sliding_window_view(padded, (k, k), axis=(0, 1))
                        windows = windows.transpose(0, 1, 3, 4, 2)  # H,W,K,K,P
                        assert windows.shape == (height, width, k, k, 16)
                        for row in windows:
                            for window in row:
                                golden.write(window.view(np.uint8).flatten()[::-1].tobytes().hex() + "\n")
                writer.writerow([name, width, height, k, groups, seed, mode])
                print(f"{name}: groups={groups} windows={width * height * groups}")


if __name__ == "__main__":
    main()
