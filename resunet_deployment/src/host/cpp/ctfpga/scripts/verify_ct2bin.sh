#!/usr/bin/env bash
# 用真实 DICOM 跑 ct2bin，并与 Python 版留下的标准答案逐项对照（SHA256 / 字节数 / 元数据）。
# 用法：scripts/verify_ct2bin.sh [build_dir] [case_dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYDIR="$(cd "$HERE/../../python/PC_FPGA" && pwd)"
BUILD="${1:-$HOME/ctfpga_build}"
CASE="${2:-$HOME/ctf_cases/verify_ct2bin}"
REF="$PYDIR/output/ct_03_q4"          # Python 版同一病例的输出，作为标准答案
DICOM_DIR="$(find "$PYDIR/source" -name '*.dcm' -printf '%h\n' | sort -u | head -1)"

rm -rf "$CASE"
echo "DICOM: $DICOM_DIR"
"$BUILD/ctfpga" --stage ct2bin --data-dir "$DICOM_DIR" --case-dir "$CASE" --assets "$PYDIR/assets"

python3 - "$REF" "$CASE" <<'EOF'
import json, sys
ref, got = sys.argv[1], sys.argv[2]
rm = json.load(open(ref + "/input/metadata.json", encoding="utf-8"))
gm = json.load(open(got + "/input/metadata.json", encoding="utf-8"))
rs = json.load(open(ref + "/input/ct_volume_vol2.json", encoding="utf-8"))
gs = json.load(open(got + "/input/ct_volume_vol2.json", encoding="utf-8"))
bad = 0
def check(name, a, b):
    global bad
    ok = a == b
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n   ref={a}\n   got={b}"))
    bad += (not ok)
check("int8 sha256", rm["model_input"]["sha256"], gm["model_input"]["sha256"])
check("int8 crc32", rm["model_input"]["crc32"], gm["model_input"]["crc32"])
check("int8 bytes", rm["model_input"]["bytes"], gm["model_input"]["bytes"])
check("shape", rm["shape_z_y_x"], gm["shape_z_y_x"])
check("series_id", rm["series_id"], gm["series_id"])
check("affine", rm["affine_z_y_x_to_lps_mm"], gm["affine_z_y_x_to_lps_mm"])
check("spacing", rm["spacing_z_y_x_mm"], gm["spacing_z_y_x_mm"])
check("slice positions", rm["slice_positions_lps_mm"], gm["slice_positions_lps_mm"])
check("z direction", rm["anatomical_z_direction"], gm["anatomical_z_direction"])
check("vol2 bytes", rs["compact_bin"]["bytes"], gs["compact_bin"]["bytes"])
check("vol2 sha256", rs["compact_bin"]["sha256"], gs["compact_bin"]["sha256"])
check("vol2 views", [{k: v for k, v in x.items()} for x in rs["compact_bin"]["views"]],
      [{k: v for k, v in x.items()} for x in gs["compact_bin"]["views"]])
check("metadata key order", list(rm.keys()), list(gm.keys()))
print("ALL_PASS" if not bad else f"{bad} CHECK(S) FAILED")
sys.exit(1 if bad else 0)
EOF
