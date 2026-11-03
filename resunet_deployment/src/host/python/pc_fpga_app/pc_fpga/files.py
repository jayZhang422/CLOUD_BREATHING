"""阶段之间只通过 BIN/STL 和 JSON 交接；元数据最后原子发布。"""
import json
from pathlib import Path
import zlib

from .ct.prediction_io import file_sha256


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def crc32_file(path):
    crc = 0
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            crc = zlib.crc32(chunk, crc)
    return crc & 0xffffffff


def check_file(path, size, sha256):
    path = Path(path)
    if path.stat().st_size != size or file_sha256(path) != sha256:
        raise ValueError(f"文件长度或 SHA256 不符：{path}")
    return path
