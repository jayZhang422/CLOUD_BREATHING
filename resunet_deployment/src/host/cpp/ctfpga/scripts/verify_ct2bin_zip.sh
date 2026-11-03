#!/usr/bin/env bash
# 用 ZIP 病例跑 ct2bin，并与 Python 版留下的输出（metadata / job / VOL2 sidecar / BIN 哈希）逐项比对。
# 用法：scripts/verify_ct2bin_zip.sh <CT.zip> <Python 参考病例目录> [build_dir] [case_dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYDIR="$(cd "$HERE/../../python/PC_FPGA" && pwd)"
ZIP="$1"
REF="$2"
BUILD="${3:-$HOME/ctfpga_build_vtk}"
CASE="${4:-$HOME/ctf_cases/zip_ct2bin}"
BATCH="${BATCH:-8}"   # Python 参考用 --batch-slices 8 生成

rm -rf "$CASE"
"$BUILD/ctfpga" --stage ct2bin --data-dir "$ZIP" --case-dir "$CASE" --assets "$PYDIR/assets" --batch-slices "$BATCH" | tail -2

python3 - "$REF" "$CASE" <<'EOF'
import hashlib, json, sys
ref, got = sys.argv[1:3]
L = lambda p: json.load(open(p, encoding="utf-8"))
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 24), b""):
            h.update(b)
    return h.hexdigest()
bad = 0
def check(name, a, b):
    global bad
    ok = a == b
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n   ref={str(a)[:200]}\n   got={str(b)[:200]}"))
    bad += (not ok)
check("int8 BIN sha256 (file)", sha(ref + "/input/ct_volume_int8.bin"), sha(got + "/input/ct_volume_int8.bin"))
check("VOL2 BIN sha256 (file)", sha(ref + "/input/ct_volume_vol2.bin"), sha(got + "/input/ct_volume_vol2.bin"))
check("VOL2 sidecar", L(ref + "/input/ct_volume_vol2.json"), L(got + "/input/ct_volume_vol2.json"))
rm, gm = L(ref + "/input/metadata.json"), L(got + "/input/metadata.json")
for k in rm:
    if k != "source_dicom":      # 源路径随机器而异
        check("metadata." + k, rm[k], gm.get(k))
check("metadata key order", list(rm), list(gm))
rj, gj = L(ref + "/handoff/job.json"), L(got + "/handoff/job.json")
for k in rj:
    if k != "input":
        check("job." + k, rj[k], gj.get(k))
ri, gi = rj["input"], gj["input"]
for k in ri:
    if k != "source":
        check("job.input." + k, ri[k], gi.get(k))
print("ALL_PASS" if not bad else f"{bad} CHECK(S) FAILED")
sys.exit(1 if bad else 0)
EOF
