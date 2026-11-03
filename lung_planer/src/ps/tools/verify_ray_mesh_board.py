"""Bounded board regression for the DDR mesh/BVH ray core (capacity, repeat, golden)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cas_frontend.pl_metrics import PlMetrics
from cas_frontend.mesh_bvh import build_mesh_image


def capacity_mesh(count):
    # Keep all vertices representable. Place the unique hit at the end of the
    # buffer to exercise traversal beyond the old BRAM limit.
    miss=np.array([[-100,-100,0],[-99,-100,0],[-100,-99,0]],dtype=float)
    values=np.tile(miss,(count,1,1))
    values[-1]=[[-10,-10,0],[10,-10,0],[-10,10,0]]
    return values


def check_summary(result,count=2):
    if not result.get('ok'):
        raise RuntimeError(result)
    expected=[(1,1,20<<16,20<<16),(2,0,0x7fffffff,0)]
    actual=[tuple(item[k] for k in ('ray_id','hit_count','t_near_q16','t_far_q16')) for item in result['results']]
    if actual!=expected or result['processed']!=count or result['hits']!=1 or result['errors']:
        raise RuntimeError('summary mismatch: %r'%result)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--bit',type=Path,default=Path('fpga/lung_planner.bit'))
    parser.add_argument('--triangles',type=int,nargs='+',default=[1,8002,100000])
    parser.add_argument('--repeat',type=int,default=100)
    parser.add_argument('--golden',type=Path,default=Path('golden'))
    parser.add_argument('--skip-golden',action='store_true')
    parser.add_argument('--out',type=Path,default=Path('board_results.json'))
    args=parser.parse_args()
    if os.geteuid()!=0:
        raise RuntimeError('Run with sudo and the PYNQ Python interpreter')
    if args.repeat<1 or any(n<1 for n in args.triangles):
        raise ValueError('counts must be positive')
    os.environ['LUNG_PL_BIT']=str(args.bit.resolve());os.environ['LUNG_PL_ENABLE']='1'
    client=PlMetrics();records=[]
    origins=np.array([[0,0,20],[20,20,20]],float);directions=np.tile([0,0,-1],(2,1))
    try:
        for count in args.triangles:
            capacity=capacity_mesh(count)
            image=build_mesh_image(capacity)
            if int(image.order[-1])!=count-1:
                raise RuntimeError('capacity unique hit did not remain at the DDR tail')
            client.cache_mesh_image(image)
            result=client.evaluate_mesh_rays(capacity,origins,directions,
                        timeout_cycles=0xffffffff,timeout_seconds=120)
            check_summary(result);records.append(dict(test='capacity',triangles=count,**result))
            print('CAPACITY_PASS triangles=%d nodes=%d ms=%.3f'%(count,result['bvh_nodes'],result['job_ms']),flush=True)
            if not client._mesh_metadata or client._mesh_mmio.read(0x048)!=result['bvh_nodes']:
                raise RuntimeError('BVH metadata ABI missing or wrong')
        mesh=capacity_mesh(1)
        for i in range(args.repeat):
            result=client.evaluate_mesh_rays(mesh,origins,directions)
            check_summary(result)
            if i and not result['mesh_reused']:
                raise RuntimeError('unchanged mesh was rebuilt')
        records.append(dict(test='repeat',count=args.repeat,**result));print('REPEAT_PASS',args.repeat,flush=True)
        # Force hardware timeout while a real read/compute job is active.
        result=client.evaluate_mesh_rays(capacity_mesh(100000),origins,directions,
                                       timeout_cycles=32,timeout_seconds=2)
        if result.get('ok') or 'timeout' not in result.get('error','').lower():
            raise RuntimeError('forced timeout did not fail as expected: %r'%result)
        records.append(dict(test='forced_timeout',**result))
        recovered=client.evaluate_mesh_rays(mesh,origins,directions);check_summary(recovered)
        records.append(dict(test='timeout_recovery',**recovered));print('TIMEOUT_RECOVERY_PASS',flush=True)
        # Explicit Abort before supplying any ray beats, avoiding a race with
        # a completed small job. The next job reprograms the fabric.
        mmio=client._mesh_mmio;mmio.write(0x008,1);mmio.write(0x030,100000000);mmio.write(0x000,1)
        mmio.write(0x000,2)
        import time
        deadline=time.monotonic()+2
        while mmio.read(0x000)&2:
            if time.monotonic()>deadline: raise TimeoutError('Abort remained busy')
        if not mmio.read(0x018)&0x80: raise RuntimeError('Abort error flag missing')
        client._reset_hardware_state()
        recovered=client.evaluate_mesh_rays(mesh,origins,directions);check_summary(recovered)
        records.append(dict(test='abort_recovery',**recovered));print('ABORT_RECOVERY_PASS',flush=True)
        for name in (() if args.skip_golden else ('convex','nonconvex','lung_8002','all_structures')):
            path=args.golden/(name+'.npz')
            if not path.is_file(): raise FileNotFoundError(path)
            with np.load(path) as data:
                triangles=data['triangles'];orig=data['origins'];dirs=data['directions']
            # Compare the exact fixed-point arithmetic, not a quantization-
            # sensitive floating-point raw triangle count.
            expected=json.loads((args.golden/(name+'_pl_summary.json')).read_text())
            expected_errors=json.loads((args.golden/(name+'_pl_errors.json')).read_text())
            for i,(origin,direction) in enumerate(zip(orig,dirs)):
                result=client.evaluate_mesh_rays(triangles,[origin],[direction],
                             timeout_cycles=0xffffffff,timeout_seconds=120)
                observed=result if result.get('ok') else result.get('diagnostic')
                wanted=dict(expected[i],ray_id=1)
                if not observed or observed['processed']!=1 or observed['results']!=[wanted] or observed['errors']!=expected_errors[i]:
                    raise RuntimeError('fixed golden mismatch %s ray %d: %r'%(name,i+1,result))
                if expected_errors[i] and result.get('ok'):
                    raise RuntimeError('arithmetic error did not trigger CPU fallback')
                records.append(dict(test='golden_ray',dataset=name,ray=i+1,**result))
                if (i+1)%20==0:print('GOLDEN_PROGRESS',name,i+1,flush=True)
            image=build_mesh_image(triangles)
            if hashlib.sha256(image.node_bytes).hexdigest()!=json.loads((args.golden/'manifest.json').read_text())['datasets'][name]['bvh_sha256']:
                raise RuntimeError('BVH layout hash mismatch '+name)
            print('GOLDEN_PASS',name,flush=True)
        args.out.write_text(json.dumps(dict(board_validated=True,results=records),indent=2))
        print('RAY_MESH_BOARD_PASS')
    except Exception as exc:
        args.out.write_text(json.dumps(dict(board_validated=False,error=str(exc),results=records),indent=2))
        raise
    finally:
        client.close()


if __name__=='__main__':
    main()
