#!/usr/bin/env python3
import argparse, hashlib, json, os
from pathlib import Path
import nibabel as nib
import numpy as np

HU_MIN, HU_MAX = -1024, 1000

def qint8(x):
    return (np.rint((np.clip(x, HU_MIN, HU_MAX).astype(np.float64) + 1024.0) * 255.0 / 2024.0).astype(np.int16) - 128).astype(np.int8)

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()

def main():
    p=argparse.ArgumentParser(); p.add_argument('--data-root',required=True); p.add_argument('--out',required=True); p.add_argument('--case-limit',type=int,default=0); p.add_argument('--all-slices',action='store_true'); a=p.parse_args()
    root,out=Path(a.data_root),Path(a.out); (out/'samples').mkdir(parents=True,exist_ok=True); imgs=sorted(x for x in (root/'imagesTr').glob('*.nii.gz') if not x.name.startswith('._')); imgs=imgs[:a.case_limit] if a.case_limit else imgs
    meta_path=out/'metadata.json'; rows=[]
    if meta_path.exists(): rows=json.loads(meta_path.read_text(encoding='utf-8')).get('cases',[])
    done={r['case'] for r in rows}
    for n,image in enumerate(imgs,1):
        case=image.name[:-7]; label=root/'labelsTr'/image.name
        if case in done: print(f'[{n}/{len(imgs)}] {case} already_done',flush=True); continue
        if not label.exists(): raise FileNotFoundError(label)
        im=nib.load(str(image)); la=nib.load(str(label)); x=im.get_fdata(dtype=np.float32); y=np.asarray(la.dataobj,dtype=np.uint8)
        if x.shape!=y.shape or x.shape[:2]!=(512,512) or not np.allclose(im.affine,la.affine): raise ValueError(f'{case}: image/label mismatch')
        positive=np.flatnonzero(np.any(y>0,axis=(0,1))); negative=np.flatnonzero(~np.any(y>0,axis=(0,1)))
        centers=np.arange(x.shape[2]) if a.all_slices else positive
        q=np.empty((len(centers),3,512,512),dtype=np.int8); masks=np.empty((len(centers),1,512,512),dtype=np.uint8)
        for j,z in enumerate(centers):
            iz=[max(0,int(z)-1),int(z),min(x.shape[2]-1,int(z)+1)]; q[j]=qint8(np.stack([x[:,:,i] for i in iz])); masks[j,0]=y[:,:,int(z)]
        np.save(out/'samples'/f'{case}_x.npy',q); np.save(out/'samples'/f'{case}_y.npy',masks)
        rows.append({'case':case,'shape':list(x.shape),'centers':centers.astype(int).tolist(),'positive_slices':positive.astype(int).tolist(),'negative_slices':negative.astype(int).tolist(),'spacing_xyz_mm':[float(v) for v in im.header.get_zooms()[:3]],'affine':im.affine.tolist(),'image_sha256':sha(image),'label_sha256':sha(label),'x_bytes':int(q.nbytes),'y_bytes':int(masks.nbytes)})
        print(f'[{n}/{len(imgs)}] {case} samples={len(centers)} bytes={q.nbytes+masks.nbytes}',flush=True)
        spec={'version':'task06_tumor_cache_v1','input_contract':{'dtype':'signed int8','shape':'[N,3,512,512]','channels':'[z-1,z,z+1]','boundary':'repeat edge','hu_clip':[HU_MIN,HU_MAX],'round':'NumPy rint nearest-even','training_cast':'direct float32','target':'center slice'},'source_root':str(root),'all_slices':a.all_slices,'case_count':len(rows),'cases':rows}
        meta_path.write_text(json.dumps(spec,indent=2)+'\n',encoding='utf-8')
    spec={'version':'task06_tumor_cache_v1','input_contract':{'dtype':'signed int8','shape':'[N,3,512,512]','channels':'[z-1,z,z+1]','boundary':'repeat edge','hu_clip':[HU_MIN,HU_MAX],'round':'NumPy rint nearest-even','training_cast':'direct float32','target':'center slice'},'source_root':str(root),'all_slices':a.all_slices,'case_count':len(rows),'cases':rows}
    (out/'metadata.json').write_text(json.dumps(spec,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'cases':len(rows),'bytes':sum(r['x_bytes']+r['y_bytes'] for r in rows),'out':str(out)}),flush=True)

if __name__=='__main__': main()
