"""Freeze source-derived CPU golden inputs, complete crossings and DDR layouts."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from time import perf_counter
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend import planner_reference as ref
from cas_frontend.mesh_bvh import build_mesh_image
from cas_frontend.ray_golden import collapse_crossings, inside_from_crossings, inside_intervals, volume_fraction, path_entry
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'sim'))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'source'))
from ray_reference import ray_triangle_fixed


def box(low, high):
    points = np.array([[x,y,z] for x in (low[0],high[0])
                       for y in (low[1],high[1]) for z in (low[2],high[2])], dtype=float)
    faces = [(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
    return np.array([[points[a],points[b],points[c]] for a,b,c,d in faces] +
                    [[points[a],points[c],points[d]] for a,b,c,d in faces])


def crossings(triangles, origin, direction):
    a = triangles[:,0]; e1=triangles[:,1]-a; e2=triangles[:,2]-a
    h=np.cross(direction,e2); det=np.einsum('ij,ij->i',e1,h)
    inv=np.divide(1.,det,out=np.zeros_like(det),where=np.abs(det)>=1e-9)
    s=origin-a; u=inv*np.einsum('ij,ij->i',s,h); q=np.cross(s,e1)
    v=inv*(q@direction); t=inv*np.einsum('ij,ij->i',e2,q)
    mask=(np.abs(det)>=1e-9)&(u>=-1e-7)&(u<=1.0000001)&(v>=-1e-7)&(u+v<=1.0000001)&(t>=0)
    return t[mask],collapse_crossings(t[mask])


def fixed_summary(triangles, origin, direction, ray_id):
    hits = []
    errors = 0
    for triangle in triangles:
        item = ray_triangle_fixed(origin, direction, triangle)
        errors |= (item['error'] & 2) << 3
        if item['hit']:
            hits.append(item['t_q16'])
    return dict(ray_id=ray_id, hit_count=len(hits),
                t_near_q16=min(hits, default=0x7fffffff),
                t_far_q16=max(hits, default=0)), errors, hits


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--case',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();args.out.mkdir(parents=True,exist_ok=True)
    paths=sorted(args.case.glob('*.stl'))
    started=perf_counter();surfaces={p.name:np.array([t.points for t in ref.read_stl(p)]) for p in paths}
    parse_ms=(perf_counter()-started)*1000
    lung=np.concatenate([values for name,values in surfaces.items() if name.startswith('Right')])
    # A closed, disconnected nonconvex union has no overlapping interior
    # faces. Its axial ray has exactly four crossings and two intervals.
    nonconvex=np.concatenate([box((-4,-1,-1),(-1,1,1)),box((1,-1,-1),(4,1,1))])
    datasets={'lung_8002':lung,'all_structures':np.concatenate(list(surfaces.values())),
              'convex':box((-1,-1,-1),(1,1,1)),'nonconvex':nonconvex}
    manifest={'schema':2,'tolerance_mm':1e-5,'stl_parse_ms':parse_ms,
              'sources':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},'datasets':{}}
    if len(lung)!=8002:
        raise RuntimeError('Expected fixed 8002-face lung, got %d'%len(lung))
    for name,triangles in datasets.items():
        image=build_mesh_image(triangles);low=triangles.min(axis=(0,1));high=triangles.max(axis=(0,1))
        center=(low+high)/2;radius=max(1.,float(np.max(high-low)))
        directions=[]
        for i in range(19):
            for j in range(19-i):
                vector=np.array([1.,(i/18-.5)*.8,(j/18-.5)*.8]);directions.append(vector/np.linalg.norm(vector))
        directions=np.asarray(directions);origins=np.tile(center-np.array([2*radius,0,0]),(190,1))
        lengths=np.full(190,4*radius)
        if name in ('lung_8002','all_structures'):
            tumor=ref.largest_component(ref.read_stl(args.case/'LungTumor1.stl'))
            apex=np.asarray(ref.all_points(tumor),dtype=float).mean(axis=0)
            base=np.array([[low[0]-.1*radius,low[1],low[2]],
                           [low[0]-.1*radius,high[1],low[2]],
                           [low[0]-.1*radius,center[1],high[2]]])
            rays=[]
            for i in range(19):
                for j in range(19-i):
                    rays.append(base[0]*(1-i/18-j/18)+base[1]*(i/18)+base[2]*(j/18)-apex)
            rays=np.asarray(rays);lengths=np.linalg.norm(rays,axis=1)
            directions=rays/lengths[:,None];origins=np.tile(apex,(190,1))
        # Retain 190 rays while adding inside, shared-edge, shared-vertex,
        # boundary/tangent and axis-parallel cases to the synthetic meshes.
        if name in ('convex','nonconvex'):
            origins[:6]=[[-6,0,0],[-6,.25,.125],[0,0,0],[-3,0,0],[-6,1,1],[-6,1,0]]
            directions[:6]=[1,0,0]
        results=[];started=perf_counter()
        for origin,direction,length in zip(origins,directions,lengths):
            raw,hits=crossings(triangles,origin,direction)
            inside=inside_from_crossings(hits)
            results.append({'raw_hits':raw.tolist(),'crossings':hits.tolist(),'inside':inside,
                            'intervals':inside_intervals(hits,length,inside).tolist(),
                            'fraction':volume_fraction(hits,length,inside),'entry':path_entry(hits,length)})
        cpu_ms=(perf_counter()-started)*1000
        qtriangles=np.rint(triangles*65536).astype(np.int64).tolist()
        qorigins=np.rint(origins*65536).astype(np.int64).tolist()
        qdirections=np.rint(directions*65536).astype(np.int64).tolist()
        summaries=[];error_flags=[];max_error=0.;matched=0;count_mismatch=0
        started=perf_counter()
        for i,(origin,direction) in enumerate(zip(qorigins,qdirections)):
            summary,error,fixed_hits=fixed_summary(qtriangles,origin,direction,i+1)
            summaries.append(summary);error_flags.append(error)
            floating=np.sort(results[i]['raw_hits']);fixed=np.sort(np.asarray(fixed_hits)/65536.)
            if len(floating)==len(fixed):
                matched+=len(fixed)
                if len(fixed):max_error=max(max_error,float(np.max(np.abs(floating-fixed))))
            else:count_mismatch+=1
            if i%20==0: print(name,'fixed ray',i+1,flush=True)
        fixed_ms=(perf_counter()-started)*1000
        np.savez(args.out/(name+'.npz'),triangles=triangles,origins=origins,directions=directions,lengths=lengths,order=image.order)
        (args.out/(name+'_triangles.bin')).write_bytes(image.triangle_bytes)
        (args.out/(name+'_bvh.bin')).write_bytes(image.node_bytes)
        (args.out/(name+'_crossings.json')).write_text(json.dumps(results),encoding='utf-8')
        (args.out/(name+'_pl_summary.json')).write_text(json.dumps(summaries),encoding='utf-8')
        (args.out/(name+'_pl_errors.json')).write_text(json.dumps(error_flags),encoding='utf-8')
        manifest['datasets'][name]={'triangles':len(triangles),'nodes':len(image.nodes),'rays':190,
           'bvh_build_ms':image.build_ms,'pack_ms':image.pack_ms,'cpu_crossings_ms':cpu_ms,
           'mesh_key':image.key,'triangle_sha256':hashlib.sha256(image.triangle_bytes).hexdigest(),
           'bvh_sha256':hashlib.sha256(image.node_bytes).hexdigest(),
           'fixed_oracle_ms':fixed_ms,'fixed_error_rays':sum(bool(x) for x in error_flags),
           'matched_raw_hits':matched,'raw_count_mismatch_rays':count_mismatch,
           'max_t_error_mm_for_equal_raw_counts':max_error,
           'closed_organ':name!='all_structures'}
        print(name,manifest['datasets'][name],flush=True)
    (args.out/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('RAY_MESH_GOLDEN_PASS')


if __name__=='__main__':
    main()
