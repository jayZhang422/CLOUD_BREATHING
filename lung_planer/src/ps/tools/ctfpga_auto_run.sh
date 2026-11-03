#!/usr/bin/env bash
# Wait until the inference board answers, then run the full ctfpga pipeline unattended.
# Usage: tools/ctfpga_auto_run.sh --data-dir DICOM [--host IP] [--bind IP] [--port N]
#        [--wait-minutes N] [--attempts N] [--retry-delay SEC]
# Each attempt gets data/ctfpga-cases/auto-<time>/ (log: ctfpga.log); progress goes to
# data/ctfpga-cases/auto-latest.txt. Only a failed Send (board not ready yet) is retried.
set -uo pipefail

app_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
data_dir="" host=192.168.1.10 bind=192.168.1.102 port=8080
wait_minutes=720 attempts=3 retry_delay=60 device="${CTFPGA_DEV:-eth0}"
while (($#)); do
    case "$1" in
        --data-dir) data_dir="$2" ;;
        --host) host="$2" ;;
        --bind) bind="$2" ;;
        --port) port="$2" ;;
        --wait-minutes) wait_minutes="$2" ;;
        --attempts) attempts="$2" ;;
        --retry-delay) retry_delay="$2" ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift 2
done
[[ -d "$data_dir" ]] || { echo "--data-dir must be a DICOM folder" >&2; exit 2; }

cases="$app_dir/data/ctfpga-cases"
mkdir -p "$cases"
summary="$cases/auto-latest.txt"
: > "$summary"
note() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$summary"; }

# The bind address must exist before ctfpga opens its socket; NetworkManager
# re-applies it on link up, this only covers a profile that lost it.
ensure_bind() {
    [[ "$bind" == 127.* ]] && return 0
    ip -4 addr show dev "$device" | grep -q "inet $bind/" && return 0
    sudo -n ip addr add "$bind/24" dev "$device" 2>/dev/null
}
# The FPGA stack may ignore ICMP, but it has to answer ARP to receive UDP.
reachable() {
    ping -c1 -W1 "$host" >/dev/null 2>&1 && return 0
    ip neigh show "$host" | grep -qE 'lladdr .* (REACHABLE|STALE|DELAY|PROBE)'
}
failed_stage() {
    python3 - "$1/status.json" <<'EOF'
import json, sys
try:
    table = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError):
    table = {}
print(next((k for k, v in table.items() if v.get("status") == "Failed"), ""))
EOF
}

note "data: $data_dir"
note "waiting for inference board $host:$port (bind $bind, up to $wait_minutes min)"
deadline=$((SECONDS + wait_minutes * 60))
until ensure_bind && reachable; do
    ((SECONDS >= deadline)) && { note "TIMEOUT: $host never answered"; exit 3; }
    sleep 5
done
note "board answered; waiting 15 s for it to settle"
sleep 15

for ((attempt = 1; attempt <= attempts; attempt++)); do
    case_dir="$cases/auto-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$case_dir"
    note "attempt $attempt/$attempts: $case_dir"
    bash "$app_dir/tools/ctfpga.sh" --stage all --data-dir "$data_dir" --case-dir "$case_dir" \
        --host "$host" --bind "$bind" --port "$port" > "$case_dir/ctfpga.log" 2>&1
    rc=$?
    if ((rc == 0)); then
        count="$(find "$case_dir/stl/cut" -name '*.stl' 2>/dev/null | wc -l)"
        if ((count == 0)); then
            note "FAILED: pipeline finished but $case_dir/stl/cut has no STL"
            exit 1
        fi
        note "DONE: $count STL in $case_dir/stl/cut"
        exit 0
    fi
    stage="$(failed_stage "$case_dir")"
    reason="$(grep '^\[FAILED\]' "$case_dir/ctfpga.log" | tail -1)"
    note "FAILED at ${stage:-unknown} (rc $rc): ${reason:-see ctfpga.log}"
    if [[ "$stage" != "Send" ]] || ((attempt == attempts)); then
        exit 1
    fi
    note "retrying in $retry_delay s"
    sleep "$retry_delay"
done
