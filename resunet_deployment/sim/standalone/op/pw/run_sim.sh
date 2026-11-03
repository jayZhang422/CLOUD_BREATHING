#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p verification/tmp
export TMPDIR="$PWD/verification/tmp"
python3 tools/generate_vectors.py | tee verification/vector_run.log
timeout 300s sbt 'runMain PwGen' 'runMain PwRequantSim' 'runMain PwMacSim' 2>&1 | tee verification/run.log
python3 tools/check_results.py
