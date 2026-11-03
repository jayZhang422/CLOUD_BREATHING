#!/usr/bin/env bash
set -euo pipefail
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1
runtime=/root/miniconda3/bin/python
scripts=/root/autodl-tmp/lung_training
cache=$scripts/other_compact_v1
# ATM22 was already started; observe that exact process instead of starting twice.
while kill -0 12992 2>/dev/null; do sleep 10; done
"$runtime" -u "$scripts/verify_other_compact.py" --task atm22 --out "$cache/atm22" > "$cache/atm22_final_verify.log" 2>&1
"$runtime" -u "$scripts/prepare_other_packages_v2.py" --task totalsegmentator --out "$cache" > "$cache/totalsegmentator_prepare.log" 2>&1
"$runtime" -u "$scripts/verify_other_compact.py" --task totalsegmentator --out "$cache/totalsegmentator" > "$cache/totalsegmentator_final_verify.log" 2>&1
"$runtime" - <<'PY'
import datetime,json
from pathlib import Path
p=Path('/root/autodl-tmp/lung_training/other_compact_v1')
reports={t:json.loads((p/t/'final_verification.json').read_text()) for t in ('atm22','totalsegmentator')}
assert all(r['full_package_complete'] and r['passed'] for r in reports.values())
(p/'remaining_complete.json').write_text(json.dumps({'completed_at':str(datetime.datetime.now()),'passed':True,'reports':reports},indent=2)+'\n')
print('ALL_REMAINING_PREPROCESS_VERIFIED')
PY
