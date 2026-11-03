import concurrent.futures
import json
from pathlib import Path

import numpy as np

ROOT = Path('/root/autodl-tmp/datasets/HiPaS')
OUT = Path('/root/autodl-tmp/lung_training')


def audit(cid):
    arrays = []
    for folder in ('ct_scan', 'annotation/artery', 'annotation/vein'):
        with np.load(ROOT / folder / (cid + '.npz'), allow_pickle=False) as data:
            arrays.append(data['data'])
    ct, artery, vein = arrays
    assert ct.shape == artery.shape == vein.shape, cid
    assert set(np.unique(artery)) <= {0, 1}, cid
    assert set(np.unique(vein)) <= {0, 1}, cid
    sample = ct[::8, ::8, :].astype(np.float32)
    result = dict(case=cid, shape=list(ct.shape), dtype=str(ct.dtype),
                  minimum=float(ct.min()), maximum=float(ct.max()),
                  quantiles=np.percentile(sample, [1, 10, 25, 50, 75, 90, 99]).tolist(),
                  artery_voxels=int(artery.sum()), vein_voxels=int(vein.sum()),
                  overlap=int(np.count_nonzero((artery != 0) & (vein != 0))))
    print(json.dumps(result), flush=True)
    return result


if __name__ == '__main__':
    OUT.mkdir(exist_ok=True)
    cases = [p.stem for p in sorted((ROOT / 'ct_scan').glob('*.npz'))]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        records = list(pool.map(audit, cases))
    (OUT / 'hipas_audit.json').write_text(json.dumps(records, indent=2))
    print('AUDIT_DONE', len(records), flush=True)
