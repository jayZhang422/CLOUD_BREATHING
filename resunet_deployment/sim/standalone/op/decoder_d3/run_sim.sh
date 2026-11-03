#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
export DECODER_REPO=$(cd ../../../.. && pwd)
mkdir -p verification "$HOME/.cache"
decoder_work=$(mktemp -d "$HOME/.cache/decoder-d3.XXXXXX")
decoder_result="$(pwd)/verification/$(date +%Y%m%d_%H%M%S)_$(basename "$decoder_work")"
mkdir "$decoder_result"
printf '%s\n' "$decoder_work" > "$decoder_result/workspace.txt"
mkdir -p "$decoder_work/project/project" "$decoder_work/run"
cp build.sbt "$decoder_work/project/build.sbt"
cp project/build.properties "$decoder_work/project/project/build.properties"
python3 -B tools/generate_vectors.py --out "$decoder_work/run/vectors" 2>&1 | tee "$decoder_result/golden.log"
{ java -version; verilator --version; python3 --version; } > "$decoder_result/environment.txt" 2>&1
(cd "$decoder_work/project" && sbt "runMain DecoderD3Sim $decoder_work/run $DECODER_REPO/sim/standalone/op/concat/rtl/concat.sv") 2>&1 | tee "$decoder_result/run.log"
grep -q '\[TB PASSED\] ALL trials=3' "$decoder_result/run.log"
# 独立联合仿真通过后仅归档必要记录；不读取 PASS trace。
python3 - "$decoder_work" "$decoder_result" "$DECODER_REPO" <<'PY'
import hashlib, json, pathlib, shutil, sys
work, result, repo = (pathlib.Path(p).resolve() for p in sys.argv[1:])
assert work.parent == (pathlib.Path.home()/'.cache').resolve() and work.name.startswith('decoder-d3.')
for name in ('vectors',):
    shutil.copytree(work/'run'/name, result/name)
shutil.copy2(work/'run/results.csv', result/'results.csv')
for directory in (work/'run').glob('trial_*'):
    (result/directory.name).mkdir()
    for path in directory.glob('*.actual.hex'):
        shutil.copy2(path, result/directory.name/path.name)
    for path in directory.glob('protocol.csv'):
        shutil.copy2(path, result/directory.name/path.name)
shutil.copytree(work/'run/compiled/DecoderD3Harness/rtl', result/'rtl')
sources = list((repo/'src/scala/decoder_d3').glob('*.scala'))
sources += [repo/'src/scala'/p for p in ('upsample/upsample.scala','pw/pwmac.scala','line_buffer/linebuffer.scala',
    'dw3x3/dw3x3.scala','dw5x5/dw5x5.scala','element_add/elementadd.scala')]
sources += [repo/'sim/standalone/op/concat/rtl/concat.sv']
sources += [repo/'sim/standalone/op/decoder_d3'/p for p in ('tb/decoderd3sim.scala','tools/generate_vectors.py','run_sim.sh','build.sbt')]
(result/'source_sha256.json').write_text(json.dumps({str(p.relative_to(repo)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},indent=2)+'\n')
shutil.rmtree(work)
(result/'cleanup.txt').write_text('PASS: no trace CSV read; archived vectors, actual outputs, RTL and logs; removed this unique WSL directory including FST, cycle CSV and sbt/Verilator caches.\n')
print('PASS artifacts:', result)
PY
