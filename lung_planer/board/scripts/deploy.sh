#!/usr/bin/env bash
# Stage the board release (PS software + firmware + cube admission vectors) and copy it to the KV260.
# Usage (from lung_planer/, Git Bash / Linux):
#   bash board/scripts/deploy.sh [user@host] [remote_dir]
# Defaults: ubuntu@192.168.50.2  /home/ubuntu/memgmo/final/cloud-breathing-kv260
# FIRMWARE=build/output deploys a fresh local build instead of board/firmware;
# that bit/hwh carries a new header timestamp, so the admission record must be
# regenerated (bash run_on_board.sh admit, ~10 s, synthetic cube) and
# frozen_baseline.json updated before the app accepts it.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
target="${1:-ubuntu@192.168.50.2}"
remote="${2:-/home/ubuntu/memgmo/final/cloud-breathing-kv260}"
firmware="${FIRMWARE:-$root/board/firmware}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -r "$root/src/ps/." "$stage/"
cp -r "$root/data/board_vectors" "$stage/vectors"
cp "$root/board/scripts/run_on_board.sh" "$stage/"
mkdir -p "$stage/fpga"
cp "$firmware"/lung_planner.{bit,bit.bin,hwh} "$stage/fpga/"
cp "$root/board/firmware/frozen_baseline.json" "$root/board/firmware/mesh-full.json" "$stage/fpga/"

ssh "$target" "mkdir -p '$remote'"
tar -C "$stage" -cf - . | ssh "$target" "tar -C '$remote' -xf -"
echo "DEPLOYED $target:$remote"
