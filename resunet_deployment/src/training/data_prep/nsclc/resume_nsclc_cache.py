#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path
import nibabel as nib

root=Path('/root/autodl-tmp/datasets/nsclc_hf_stage'); out=Path('/root/autodl-tmp/lung_training/nsclc_radiomics_cache_v1')
orig='/root/autodl-tmp/lung_training/prepare_task06_cache_stream_v4.py'; special='/tmp/prepare_nsclc_case_resample.py'
meta=out/'metadata.json'
while True:
    spec=json.loads(meta.read_text()); done={r['case'] for r in spec['cases']}
    q=out/'quarantine_missing_labels.json'; quarantined={x['case'] for x in (json.loads(q.read_text()) if q.exists() else [])}
    images=sorted((root/'imagesTr').glob('*.nii.gz'))
    pending=[p for p in images if p.name[:-7] not in done and p.name[:-7] not in quarantined]
    if not pending: print(f'COMPLETE {len(done)}/{len(images)}',flush=True); break
    p=pending[0]; case=p.name[:-7]
    label=root/'labelsTr'/p.name
    if not label.exists():
        q=out/'quarantine_missing_labels.json'
        rows=json.loads(q.read_text()) if q.exists() else []
        if case not in {x['case'] for x in rows}:
            rows.append({'case':case,'image':str(p),'label':str(label),'reason':'label symlink target missing'})
            q.write_text(json.dumps(rows,indent=2)+'\n')
        print(f'QUARANTINE {case} missing label',flush=True)
        done.add(case)
        continue
    im=nib.load(str(p)); la=nib.load(str(root/'labelsTr'/p.name))
    mismatch=im.shape != la.shape or not (im.affine == la.affine).all()
    print(f'START {case} done={len(done)}/{len(images)} mismatch={mismatch}',flush=True)
    cmd=[sys.executable, special if mismatch else orig, '--root' if mismatch else '--data-root', str(root), '--out', str(out), '--case', case]
    r=subprocess.run(cmd)
    if r.returncode: raise SystemExit(f'FAILED {case} rc={r.returncode}')
