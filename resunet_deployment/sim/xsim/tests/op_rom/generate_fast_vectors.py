"""从已有冻结向量裁出快速回归；不重算或修改原 Golden，不更改 ROM。"""
from pathlib import Path
import hashlib
import json
import struct

ROOT = Path(__file__).resolve().parent
VECTORS = ROOT / "vectors"


def read_hex(path):
    return bytes.fromhex(path.read_text(encoding="ascii"))


def write_hex(path, data):
    path.write_text("".join(f"{b:02x}\n" for b in data), encoding="ascii")


def crop(data, width, height, new_width, new_height):
    # P16 与四路 INT32 MAC 均按 [group][y][x][16 bytes] 保存。
    plane = width * height * 16
    assert len(data) % plane == 0
    return b"".join(
        data[g * plane + y * width * 16:g * plane + (y * width + new_width) * 16]
        for g in range(len(data) // plane) for y in range(new_height)
    )


def main():
    lines, evidence = [], []
    for line in (VECTORS / "cases.txt").read_text().splitlines():
        name, result_size, mac_size = line.split()
        if name == "bin512_online_first":
            continue
        if name.endswith("_e1") or name in ("pool_from_tumor_pw", "concat_pool", "pw_from_concat_rom"):
            source = VECTORS / name
            target = VECTORS / (name + "_fast")
            target.mkdir(exist_ok=True)
            desc = bytearray(read_hex(source / "descriptor.hex"))
            width, height = struct.unpack_from("<HH", desc, 4)
            new_size = 4 if width == 32 else 2
            struct.pack_into("<HH", desc, 4, new_size, new_size)
            write_hex(target / "descriptor.hex", desc)
            uploads = []
            for upload in (source / "uploads.txt").read_text().splitlines():
                if not upload.strip():
                    continue
                address, size, filename = upload.split()
                data = crop(read_hex(VECTORS / filename), width, height, new_size, new_size)
                write_hex(target / Path(filename).name, data)
                uploads.append(f"{address} {len(data)} {target.name}/{Path(filename).name}\n")
            (target / "uploads.txt").write_text("".join(uploads), encoding="ascii")
            out_width, out_height = (width // 2, height // 2) if desc[0] == 2 else (width, height)
            out_size = new_size // 2 if desc[0] == 2 else new_size
            sizes = []
            for filename, old_size in (("golden.hex", result_size), ("mac.hex", mac_size)):
                if int(old_size):
                    original = read_hex(source / filename)
                    data = crop(original, out_width, out_height, out_size, out_size)
                    write_hex(target / filename, data)
                    sizes.append(len(data))
                    evidence.append({"source": f"{name}/{filename}", "source_sha256": hashlib.sha256(original).hexdigest(),
                                     "crop": f"{out_size}x{out_size}", "target_sha256": hashlib.sha256(data).hexdigest()})
                else:
                    sizes.append(0)
            lines.append(f"{target.name} {sizes[0]} {sizes[1]}\n")
        else:
            lines.append(line + "\n")
    (VECTORS / "cases_fast.txt").write_text("".join(lines), encoding="ascii")
    (ROOT / "results" / "fast_vector_manifest.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(f"Prepared {len(lines)} cases; original vectors unchanged; 512x512 excluded.")


if __name__ == "__main__":
    main()
