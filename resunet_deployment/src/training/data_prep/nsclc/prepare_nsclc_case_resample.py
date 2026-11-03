#!/usr/bin/env python3
import argparse, gzip, hashlib, json, os, shutil, tempfile, time
from pathlib import Path
import nibabel as nib
import numpy as np
from nibabel.processing import resample_from_to

def qint8(x):
    return (np.rint((np.clip(x, -1024, 1000).astype(np.float64) + 1024.0) * 255.0 / 2024.0).astype(np.int16) - 128).astype(np.int8)
def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1<<20),b''): h.update(b)
    return h.hexdigest()
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--root',type=Path,required=True); ap.add_argument('--out',type=Path,required=True); ap.add_argument('--case',required=True); a=ap.parse_args()
    case=a.case; image=a.root/'imagesTr'/f'{case}.nii.gz'; label=a.root/'labelsTr'/f'{case}.nii.gz'; samples=a.out/'samples'; samples.mkdir(exist_ok=True)
    xp=samples/f'{case}_x.npy'; yp=samples/f'{case}_y.npy'
    with tempfile.TemporaryDirectory(prefix=f'.unpack_{case}_',dir=a.out) as td:
        ip=Path(td)/'image.nii'; lp=Path(td)/'label.nii'
        for src,dst in [(image,ip),(label,lp)]:
            with gzip.open(src,'rb') as fi, open(dst,'wb') as fo: shutil.copyfileobj(fi,fo,1<<20)
        im=nib.load(str(ip),mmap='r'); la=nib.load(str(lp),mmap='r')
        if im.shape != la.shape or not np.allclose(im.affine,la.affine):
            la_rs=resample_from_to(la,(im.shape,im.affine),order=0)
        else: la_rs=la
        z=im.shape[2]; xt=xp.with_name(xp.name+'.part'); yt=yp.with_name(yp.name+'.part')
        x=np.lib.format.open_memmap(xt,mode='w+',dtype=np.int8,shape=(z,3,512,512)); y=np.lib.format.open_memmap(yt,mode='w+',dtype=np.uint8,shape=(z,1,512,512)); pos=[]
        prev=cur=qint8(np.asarray(im.dataobj[:,:,0],dtype=np.float32))
        for k in range(z):
            nxt=qint8(np.asarray(im.dataobj[:,:,k+1],dtype=np.float32)) if k+1<z else cur
            x[k,0],x[k,1],x[k,2]=prev,cur,nxt
            mask=np.rint(np.asarray(la_rs.dataobj[:,:,k])).astype(np.uint8)
            if not np.all((mask==0)|(mask==1)): raise ValueError(f'{case}: nonbinary mask after resample')
            y[k,0]=mask
            if np.any(mask): pos.append(k)
            prev,cur=cur,nxt
        xb,yb=x.nbytes,y.nbytes; del x,y
        os.replace(xt,xp); os.replace(yt,yp)
    meta=a.out/'metadata.json'; spec=json.loads(meta.read_text()); row={'case':case,'shape':list(im.shape),'centers':list(range(z)),'positive_slices':pos,'negative_slices':sorted(set(range(z))-set(pos)),'spacing_xyz_mm':[float(v) for v in im.header.get_zooms()[:3]],'affine':im.affine.tolist(),'image_sha256':sha(image),'label_sha256':sha(label),'x_bytes':int(xb),'y_bytes':int(yb),'preprocessor':'prepare_nsclc_case_resample_v1','resampled_label_to_image_grid':True,'source_label_shape':list(la.shape),'source_label_spacing_xyz_mm':[float(v) for v in la.header.get_zooms()[:3]],'elapsed_seconds':0.0}
    spec['cases']=sorted(spec['cases']+[row],key=lambda r:r['case']); spec['case_count']=len(spec['cases']); spec['preprocessor_revision']='stream_v4_single_unpack_with_quarantine_resample'; tmp=meta.with_suffix('.tmp'); tmp.write_text(json.dumps(spec,indent=2)+'\n'); os.replace(tmp,meta)
    print(f'DONE {case} resampled_label_to_image_grid cases={spec["case_count"]}',flush=True)
if __name__=='__main__': main()
