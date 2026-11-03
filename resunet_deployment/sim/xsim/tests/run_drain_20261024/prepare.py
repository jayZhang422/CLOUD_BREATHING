"""Independent NumPy Golden for op11 at production row/frame boundaries."""
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parent


def words(path, data):
    raw = bytes(data)
    path.write_text("".join(raw[i:i+16][::-1].hex() + "\n"
                            for i in range(0, len(raw), 16)), encoding="ascii")


def main():
    for name, w, h, groups in [("row512", 512, 4, 1),
                                ("pressure64", 64, 64, 1),
                                ("pressure8", 8, 512, 1),
                                ("frame512", 512, 512, 1),
                                ("groups2", 31, 9, 2)]:
        folder = ROOT / name
        folder.mkdir(exist_ok=True)
        rng = np.random.default_rng(241024)
        x = rng.integers(-5, 6, (groups, h, w, 16), dtype=np.int8)
        total = np.zeros(x.shape, dtype=np.int32)
        weights = []
        for k in (3, 5):
            weight = rng.integers(-1, 2, (groups, k, k, 16), dtype=np.int8)
            weights.append(weight.transpose(0, 3, 1, 2).tobytes())
            padded = np.pad(x.astype(np.int32), ((0, 0), (k//2, k//2), (k//2, k//2), (0, 0)))
            for y in range(k):
                for col in range(k):
                    total += padded[:, y:y+h, col:col+w, :] * weight[:, y, col, :][:, None, None, :]
        params = bytearray(groups * 256)
        for lane in range(groups * 16):
            params[lane*16:lane*16+4] = (1).to_bytes(4, "little")
            params[lane*16+4:lane*16+8] = (1).to_bytes(4, "little")
        words(folder / "input.hex", x.tobytes())
        words(folder / "golden.hex", np.clip(total, -128, 127).astype(np.int8).tobytes())
        words(folder / "dw3.hex", weights[0])
        words(folder / "dw5.hex", weights[1])
        words(folder / "params.hex", params)
    print("Prepared independent op11 Golden: row512, pressure64, pressure8, frame512, groups2")


if __name__ == "__main__":
    main()
