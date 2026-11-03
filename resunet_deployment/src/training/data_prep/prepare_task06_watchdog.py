#!/usr/bin/env python3
import json, subprocess, sys, time
from pathlib import Path

ROOT=Path('/root/autodl-tmp/datasets/Task06_Lung')
OUT=Path('/root/autodl-tmp/lung_training/task06_tumor_cache_v1')
LOG=Path('/root/autodl-tmp/lung_training/task06_tumor_watchdog.log')
SCRIPT=Path('/root/autodl-tmp/lung_training/prepare_task06_cache_v2.py')

def log(s):
    with LOG.open('a',encoding='utf-8') as f: f.write(time.strftime('%F %T ')+s+'\n')
    print(s,flush=True)

while True:
    meta=OUT/'metadata.json'
    done=set()
    if meta.exists():
        try: done={x['case'] for x in json.loads(meta.read_text())['cases']}
        except Exception as e: log('metadata_error '+repr(e))
    cases=sorted(p.name[:-7] for p in (ROOT/'imagesTr').glob('*.nii.gz') if not p.name.startswith('._'))
    if len(done)==len(cases): log(f'COMPLETE {len(done)}/{len(cases)}'); break
    log(f'RESTART done={len(done)}/{len(cases)}')
    r=subprocess.run(['/root/miniconda3/bin/python',str(SCRIPT),'--data-root',str(ROOT),'--out',str(OUT),'--case-limit',str(len(cases)),'--all-slices'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    for line in r.stdout.splitlines(): log(line)
    if r.returncode==0: continue
    log(f'CHILD_EXIT code={r.returncode}; retrying in 5s')
    time.sleep(5)
