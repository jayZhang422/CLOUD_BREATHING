#!/bin/bash
# usage: run_in_wsl.sh <sub-dir under sim/standalone> <command...>
# Copies the sim directory to WSL local disk (faster than /mnt/e), runs the command,
# and writes the full console output to <sub-dir>/results/run.log in the repo.
set -u
SUB="$1"; shift
# Repo paths are derived from this script's location (sim/standalone/), so the
# repo can live anywhere.
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SRC/../.." && pwd)"
W=$(mktemp -d /tmp/sim.XXXXXX)
mkdir -p "$W/sim/standalone/$(dirname "$SUB")" "$W/src"
cp -r "$SRC/$SUB" "$W/sim/standalone/$SUB"
cp -r "$REPO/src/rtl" "$W/src/rtl"
mkdir -p "$SRC/$SUB/results"
cd "$W/sim/standalone/$SUB"
mkdir -p results
{
  echo "# $SUB   $(date -Is)"
  echo "# $(verilator --version)"
  echo "# cmd: $*"
  "$@"
  rc=$?
  echo "# exit=$rc"
} 2>&1 | tee "$SRC/$SUB/results/run.log"
rc=${PIPESTATUS[0]}
rm -rf "$W"
exit $rc
