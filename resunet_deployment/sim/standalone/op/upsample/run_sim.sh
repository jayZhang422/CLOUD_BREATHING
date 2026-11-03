#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
mkdir -p verification "$HOME/.cache"
upsample_run_dir=$(mktemp -d "$HOME/.cache/upsample-sim.XXXXXX")
upsample_result_dir="$(pwd)/verification/$(date +%Y%m%d_%H%M%S)_$(basename "$upsample_run_dir")"
mkdir "$upsample_result_dir"
printf '%s\n' "$upsample_run_dir" > "$upsample_result_dir/workspace.txt"
# 每次独立目录；失败保留原始黑匣子供定向检查，不覆盖任何旧运行。
python3 -B tools/generate_vectors.py --out "$upsample_run_dir/vectors" 2>&1 | tee "$upsample_result_dir/vectors.log"
{ java -version; verilator --version; python3 --version; } > "$upsample_result_dir/environment.txt" 2>&1
sbt "runMain UpsampleSim $upsample_run_dir/vectors" 2>&1 | tee "$upsample_result_dir/run.log"
grep -q '\[TB PASSED\] ALL cases=29' "$upsample_result_dir/run.log"
sbt 'runMain UpsampleGen' 2>&1 | tee "$upsample_result_dir/generation.log"
# SYNTHESIS 选择可综合分支，排除 Spinal 自动生成的仿真状态字符串；不关闭告警。
verilator --lint-only -Wall -DSYNTHESIS --top-module Upsample rtl/upsample.v 2>&1 | tee "$upsample_result_dir/lint.log"
# 仅在仿真、生成、lint 全部成功后归档必要产物并清理本次黑匣子。
python3 - "$upsample_run_dir" "$upsample_result_dir" <<'PY'
import pathlib
import shutil
import sys
work = pathlib.Path(sys.argv[1]).resolve()
result = pathlib.Path(sys.argv[2]).resolve()
assert work.parent == (pathlib.Path.home() / '.cache').resolve() and work.name.startswith('upsample-sim.')
vectors = work / 'vectors'
for path in vectors.rglob('*'):
    if path.is_file() and (path.name in ('cases.csv', 'results.csv', 'provenance.json') or path.name.endswith('.bin.gz')):
        dest = result / path.relative_to(vectors)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
# 不打开 PASS trace CSV；只按本次工作目录删除波形、trace 和编译缓存。
shutil.rmtree(work)
(result / 'cleanup.txt').write_text('PASS: archived vectors/logs/results; removed this run FST, cycle CSV and temporary compilation cache.\n')
PY
printf 'PASS artifacts: %s\n' "$upsample_result_dir"
