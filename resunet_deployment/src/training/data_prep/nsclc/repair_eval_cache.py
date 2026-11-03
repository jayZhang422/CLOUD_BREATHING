import json, hashlib
from pathlib import Path
import nibabel as nib
import numpy as np

src=Path('/root/autodl-tmp/datasets/nsclc_eval_raw/evaluation')
out=Path('/root/autodl-tmp/lung_training/nsclc_eval_image_cache_v1')
meta=out/'metadata.json'
data=json.loads(meta.read_text())

def qint8(x):
    return (np.rint((np.clip(np.asarray(x,dtype=np.float32),-1024,1000).astype(np.float64)+1024)*255/2024).astype(np.int16)-128).astype(np.int8)

def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()

for row in data['cases']:
    case=row['case']; dest=out/'cases'/case/'q.npy'
    if dest.exists(): continue
    im=nib.load(row['source'],mmap='r'); h,w,z=im.shape[:3]
    dest.parent.mkdir(parents=True,exist_ok=True)
    q=np.lib.format.open_memmap(dest,mode='w+',dtype=np.int8,shape=(z,h,w))
    for i in range(z): q[i]=qint8(im.dataobj[:,:,i])
    q.flush(); del q
    row['q_sha256']=sha(dest)
meta.write_text(json.dumps(data,indent=2)+'\n')
print('repaired',len(data['cases']))
