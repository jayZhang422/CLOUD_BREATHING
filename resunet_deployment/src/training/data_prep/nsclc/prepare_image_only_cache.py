import hashlib, json, os, sys, tempfile, time
from pathlib import Path
import nibabel as nib
import numpy as np

src = Path(sys.argv[1]); out = Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
cases = sorted(src.rglob('*.nii.gz'))
manifest = out / 'metadata.json'
done = {}
if manifest.exists(): done = {x['case']: x for x in json.loads(manifest.read_text()).get('cases', [])}
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1<<20), b''): h.update(b)
    return h.hexdigest()
def qint8(x):
    return (np.rint((np.clip(np.asarray(x,dtype=np.float32),-1024,1000).astype(np.float64)+1024)*255/2024).astype(np.int16)-128).astype(np.int8)
for p in cases:
    case = p.name[:-7]
    if case in done: continue
    im=nib.load(str(p),mmap='r'); h,w,z=im.shape[:3]
    if h>512 or w>512: raise ValueError(f'{case}: shape {im.shape}')
    d=out/'cases'/case; d.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out) as td:
        stage=Path(td); q=np.lib.format.open_memmap(stage/'q.npy',mode='w+',dtype=np.int8,shape=(z,h,w))
        for i in range(z): q[i]=qint8(im.dataobj[:,:,i])
        q.flush(); del q
        os.replace(stage/'q.npy',d/'q.npy') if d.exists() else (d.mkdir() or os.replace(stage/'q.npy',d/'q.npy'))
    row={'case':case,'source':str(p),'shape_h_w_z':[h,w,z],'input_shape':[z,3,512,512],
         'spacing_xyz_mm':[float(v) for v in im.header.get_zooms()[:3]],'affine':im.affine.tolist(),
         'source_sha256':sha(p),'q_sha256':sha(d/'q.npy'),'labels_available':False,
         'input_contract':{'dtype':'signed int8','channels':'[z-1,z,z+1]','boundary':'repeat edge','hu_clip':[-1024,1000],'round':'NumPy rint nearest-even','training_cast':'direct float32'}}
    done[case]=row
    manifest.write_text(json.dumps({'version':'image_only_compact_v1','case_count':len(done),'cases':sorted(done.values(),key=lambda x:x['case'])},indent=2)+'\n')
    print('DONE',case,len(done),len(cases),flush=True)
print('COMPLETE',len(done),len(cases),flush=True)
