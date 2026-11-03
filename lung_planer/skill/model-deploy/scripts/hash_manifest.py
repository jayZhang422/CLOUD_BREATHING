#!/usr/bin/env python3
"""为冻结的契约/权重/Golden 生成或校验 SHA256 清单（JSON：{相对路径: sha256}）。

冻结之后任何文件变化都意味着所有下游向量与验证结论作废，所以：
  生成：python hash_manifest.py make  <dir> [--glob "*.bin" --glob "*.json"] [--out sha256.json]
  校验：python hash_manifest.py check <dir> [--manifest sha256.json]
校验输出 changed / missing / extra 三类，任一非空退出码为 1。
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path


def digest(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def collect(root, globs, exclude):
    files = set()
    for g in globs:
        files.update(p for p in root.rglob(g) if p.is_file())
    return {p.relative_to(root).as_posix(): p for p in sorted(files) if p.name not in exclude}


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["make", "check"])
    ap.add_argument("dir")
    ap.add_argument("--glob", action="append", help="默认 *.bin、*.json、*.hex")
    ap.add_argument("--out", "--manifest", dest="manifest", default="sha256.json")
    a = ap.parse_args()

    root = Path(a.dir)
    mpath = Path(a.manifest) if Path(a.manifest).is_absolute() else root / a.manifest
    files = collect(root, a.glob or ["*.bin", "*.json", "*.hex"], {mpath.name})

    if a.mode == "make":
        mpath.write_text(json.dumps({k: digest(p) for k, p in files.items()}, indent=2), encoding="utf-8")
        print(f"wrote {mpath} ({len(files)} files)")
        return 0

    ref = json.loads(mpath.read_text(encoding="utf-8"))
    changed = [k for k in ref if k in files and digest(files[k]) != ref[k]]
    missing = [k for k in ref if k not in files]
    extra = [k for k in files if k not in ref]
    for name, items in (("changed", changed), ("missing", missing), ("extra", extra)):
        for k in items:
            print(f"{name:8s} {k}")
    ok = not (changed or missing)
    print(f"{'OK' if ok else 'FAIL'}: {len(ref)} in manifest, {len(changed)} changed, "
          f"{len(missing)} missing, {len(extra)} extra (extra 仅提示)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
