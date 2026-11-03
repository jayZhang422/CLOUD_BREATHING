#!/usr/bin/env bash
# 回环端到端：mockboard 充当 KU5P，真实历史预测作为"推理结果"。
# 校验：DDR 实收内容的 SHA256、执行清单/坐标表哈希（对照 Python 标准答案）、回读文件哈希、RELEASE 语义。
# 用法：scripts/e2e_loopback.sh [drop_every=0] [client_timeout=1.0] [build_dir] [case_dir]
# 环境变量：DATA（DICOM 目录或 .zip）、REF（Python 参考病例目录，取 program.json/job.json 作标准答案）、
#           BATCH（--batch-slices，需与参考一致，默认 8）。参考目录没有 prediction 时合成一份合法 UINT16 结果回放。
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYDIR="$(cd "$HERE/../../python/PC_FPGA" && pwd)"
DROP="${1:-0}"
TMO="${2:-1.0}"
BUILD="${3:-$HOME/ctfpga_build}"
CASE="${4:-$HOME/ctf_cases/verify_ct2bin}"
REF="${REF:-$PYDIR/output/case_a_v3}"
BATCH="${BATCH:-8}"
PORT=18080
REPORT="$CASE/mock_report.json"

DICOM_DIR="${DATA:-$(find "$PYDIR/source" -name '*.dcm' -printf '%h\n' | sort -u | head -1)}"
if [ ! -f "$CASE/handoff/job.json" ]; then
  "$BUILD/ctfpga" --stage ct2bin --data-dir "$DICOM_DIR" --case-dir "$CASE" --assets "$PYDIR/assets" --batch-slices "$BATCH" >/dev/null
fi
rm -rf "$CASE/prediction" "$CASE/stl" "$CASE/handoff/send_receipt.json" "$CASE/handoff/program.json" \
       "$CASE/handoff/result_ready.json" "$CASE/handoff/inference_status.json" "$REPORT"

# 结果回放文件：优先用参考预测；没有则按 job.json 的结果长度合成（bit9..15 为 0，保证标签位合法）。
RESULT="$REF/prediction/segmentation_uint16.bin"
if [ ! -f "$RESULT" ]; then
  RESULT="$CASE/synthetic_result.bin"
  python3 - "$CASE/handoff/job.json" "$RESULT" <<'PY'
import json, sys
import numpy as np
n = json.load(open(sys.argv[1], encoding="utf-8"))["result_contract"]["bytes"]
rng = np.random.default_rng(20261101)
a = (rng.integers(0, 1 << 9, size=n // 2, dtype=np.uint16))
a.astype("<u2").tofile(sys.argv[2])
PY
fi

# 各 DDR 区域起点取自 job.json 的视图表，再加三块固定区域。
EXTENTS="$(python3 - "$CASE/handoff/job.json" <<'EOF'
import json, sys
job = json.load(open(sys.argv[1], encoding="utf-8"))
args = [f"--hash-extent {v['base']}:{v['name']}" for v in job["compact_bin"]["views"]]
args += ["--hash-extent 134217728:params", "--hash-extent 136314880:script", "--hash-extent 142606336:maps"]
print(" ".join(args))
EOF
)"

# shellcheck disable=SC2086
"$BUILD/mockboard" --bind 127.0.0.1 --port $PORT --result-file "$RESULT" \
  --drop-every "$DROP" --busy-polls 3 --report "$REPORT" $EXTENTS > "$CASE/mock.log" 2>&1 &
MOCK=$!
trap 'kill $MOCK 2>/dev/null || true' EXIT
for _ in $(seq 1 300); do grep -q listening "$CASE/mock.log" && break; sleep 0.1; done
grep -q listening "$CASE/mock.log" || { echo "mockboard 未能启动"; cat "$CASE/mock.log"; exit 1; }

"$BUILD/ctfpga" --stage all --data-dir "$DICOM_DIR" --case-dir "$CASE" --assets "$PYDIR/assets" --batch-slices "$BATCH" --host 127.0.0.1 --bind 127.0.0.1 \
  --port $PORT --timeout "$TMO" --stall-timeout 30 --run-timeout 120 2>&1 | grep -v -E "^\[(Send|Receive) +\] (VOL2|[0-9])" | tail -25
wait $MOCK || true
trap - EXIT

python3 - "$REF" "$CASE" "$PYDIR/assets" "$RESULT" <<'EOF'
import json, sys, hashlib
ref, got, assets, result = sys.argv[1:5]
L = lambda p: json.load(open(p, encoding="utf-8"))
rp, gp = L(ref + "/handoff/program.json"), L(got + "/handoff/program.json")
rj, gj = L(ref + "/handoff/job.json"), L(got + "/handoff/job.json")
mock = L(got + "/mock_report.json")
pm = L(got + "/prediction/metadata.json")
rpm = {"sha256": hashlib.sha256(open(result, "rb").read()).hexdigest(), "bytes": __import__("os").path.getsize(result)}
bad = 0
def check(name, a, b):
    global bad
    ok = a == b
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f"\n   expect={a}\n   actual={b}"))
    bad += (not ok)
d = mock["ddr_sha256"]
views = {v["name"]: v for v in gj["compact_bin"]["views"]}
vol = open(got + "/input/ct_volume_vol2.bin", "rb")
def section(name):
    v = views[name]; vol.seek(v["file_offset"]); return hashlib.sha256(vol.read(v["bytes"])).hexdigest()
for n in ("native", "lobe", "lobe_t", "native_t"):
    check(f"DDR {n} == VOL2 section", section(n), d.get(n))
check("DDR native == int8 BIN sha", gj["input"]["sha256"], d["native"])
check("DDR script == Python schedule_sha256", rp["schedule_sha256"], d["script"])
check("DDR maps   == Python maps_sha256", rp["maps_sha256"], d["maps"])
check("DDR params == frozen asset", L(assets + "/volume_assets.json")["assets"]["tumor.params.bin"]["sha256"], d["params"])
check("program.json schedule/maps/compact/commands",
      [rp[k] for k in ("schedule_sha256", "maps_sha256", "compact_sha256", "commands", "header_hex")],
      [gp[k] for k in ("schedule_sha256", "maps_sha256", "compact_sha256", "commands", "header_hex")])
check("program.json models", rp["models"], gp["models"])
strip = lambda j: {k: ({a: b for a, b in v.items() if a != "source"} if k == "input" else v) for k, v in j.items()}
check("job.json (minus source path)", strip(rj), strip(gj))
check("prediction sha256 == replayed result", rpm["sha256"], pm["sha256"])
check("prediction bytes", rpm["bytes"], pm["bytes"])
check("DDR released", True, pm["ddr_released"])
check("mock start header ok", True, mock["start_header_ok"])
check("mock program structure ok", True, mock["program_structure_ok"])
check("mock released", True, mock["released"])
s = L(got + "/handoff/send_receipt.json")
print(f"INFO packets_rx={mock['packets_rx']} dropped={mock['packets_dropped']} writes={mock['writes']} reads={mock['reads']} "
      f"retransmits={s.get('retransmits')} upload={s.get('upload_mib_s',0):.1f} MiB/s receive={pm.get('receive_mib_s',0):.1f} MiB/s")
print("ALL_PASS" if not bad else f"{bad} CHECK(S) FAILED")
sys.exit(1 if bad else 0)
EOF
