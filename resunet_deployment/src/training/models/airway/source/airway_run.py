#!/usr/bin/env python3
"""Independent Airway experiment and an epoch-gated OS supervisor."""
import argparse
import hashlib
import json
import math
import os
import random
import shutil
import subprocess
import sys
import time
import traceback
from pathlib import Path

import numpy as np
import torch
from torch.nn import functional as F

from airway_model import ResUNet
from airway_preflight import CACHE, CONTRACT, BASE
from compact_cache_reader import CompactCase

SEED = 20261008
AUDIT = BASE / 'airway_mkdc_v1/audit_20261008_v1'


def read(path):
    return json.loads(Path(path).read_text())


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def sync_parent(path):
    directory = os.open(Path(path).parent, os.O_DIRECTORY)
    os.fsync(directory)
    os.close(directory)


def atomic_json(path, value):
    path = Path(path)
    temp = path.with_name(path.name + f'.tmp.{os.getpid()}')
    with temp.open('w') as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)
    sync_parent(path)


def atomic_torch(path, value):
    path = Path(path)
    temp = path.with_name(path.name + f'.tmp.{os.getpid()}')
    with temp.open('wb') as f:
        torch.save(value, f)
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp, path)
    sync_parent(path)


def atomic_copy(source, path):
    path = Path(path)
    temp = path.with_name(path.name + f'.tmp.{os.getpid()}')
    with Path(source).open('rb') as inp, temp.open('wb') as out:
        shutil.copyfileobj(inp, out)
        out.flush()
        os.fsync(out.fileno())
    os.replace(temp, path)
    sync_parent(path)


def event(run, name, **values):
    with (run/'events.jsonl').open('a') as f:
        f.write(json.dumps({'time':time.time(),'event':name,**values},allow_nan=False)+'\n')
        f.flush()
        os.fsync(f.fileno())


def alive(pid):
    try:
        os.kill(int(pid),0)
        return Path(f'/proc/{pid}/stat').read_text().split(') ')[1][0] != 'Z'
    except (OSError,ValueError,IndexError):
        return False


def heartbeat(run, role, epoch=0, phase='starting', **values):
    atomic_json(run/f'{role}_heartbeat.json',{'pid':os.getpid(),'time':time.time(),
                                             'epoch':epoch,'phase':phase,**values})


def resources(run):
    disk = shutil.disk_usage(run)
    gpu = subprocess.check_output(['nvidia-smi','--query-gpu=utilization.gpu,memory.used,memory.total',
                                   '--format=csv,noheader,nounits'],text=True).strip().splitlines()[0]
    util, used, total = [int(v.strip()) for v in gpu.split(',')]
    pids = subprocess.check_output(['nvidia-smi','--query-compute-apps=pid','--format=csv,noheader,nounits'],text=True)
    return {'disk_free_bytes':disk.free,'gpu_used_mib':used,'gpu_total_mib':total,
            'gpu_util_percent':util,'gpu_compute_pids':[int(x) for x in pids.split() if x.isdigit()]}


def gpu_idle(run):
    state = resources(run)
    assert not state['gpu_compute_pids'] and state['gpu_used_mib'] < 256, f'GPU occupied; wait without stopping other tasks: {state}'


def seed_all():
    random.seed(SEED)
    np.random.seed(SEED)
    torch.manual_seed(SEED)
    torch.set_num_threads(8)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False


class AirwayData:
    def __init__(self):
        meta = read(CACHE/'metadata.json')
        assert meta['task'] == 'atm22' and read(CACHE/'final_verification.json')['passed']
        assert all(meta['input_contract'][k] == v for k,v in CONTRACT.items())
        self.rows = {r['case']:r for r in meta['cases']}
        assert all(r['target_names'] == ['airway'] and r['supervised_targets_only'] == ['airway'] for r in self.rows.values())
        self.current_id, self.current = None, None

    def open(self, cid):
        if self.current_id != cid:
            self.current = CompactCase(CACHE/'cases'/cid)
            assert self.current.task == 'atm22' and self.current.target_names == ['airway']
            self.current_id = cid
        return self.current

    def batch(self, cid, zs, rng=None):
        xs, ys, masks = [], [], []
        for z in zs:
            x,y,mask = self.open(cid).read_sample(int(z))
            if rng is not None:
                x,y,mask = transform(x,y,mask,rng.random()<0.5,rng.random()<0.5,
                                     rng.choice((-1,1)) if rng.random()<0.25 else 0)
            xs.append(x)
            ys.append(y)
            masks.append(mask)
        return tuple(np.stack(a).astype(np.float32) for a in (xs,ys,masks))


def transform(x,y,mask,flip_h=False,flip_w=False,turns=0):
    arrays = [x,y,mask]
    if flip_h:
        arrays = [a[:,::-1,:] for a in arrays]
    if flip_w:
        arrays = [a[:,:,::-1] for a in arrays]
    if turns:
        arrays = [np.rot90(a,turns,axes=(-2,-1)) for a in arrays]
    return tuple(np.ascontiguousarray(a) for a in arrays)


def sampling_pools(data, ids):
    lut = np.array([int(x).bit_count() for x in range(256)],dtype=np.uint8)
    result = {}
    for cid in ids:
        case = data.open(cid)
        counts = lut[case.bits[0]].sum((1,2),dtype=np.int64)
        pos = np.flatnonzero(counts)
        assert pos.tolist() == data.rows[cid]['positive_slices_per_target'][0]
        assert int(counts.sum()) == data.rows[cid]['label_voxels'][0] and len(pos)
        cutoff = float(np.quantile(counts[pos],0.25))
        sparse = pos[counts[pos] <= cutoff]
        result[cid] = {'voxel_counts':counts.tolist(),'positive':pos.tolist(),
                       'negative':np.flatnonzero(counts == 0).tolist(),'sparse_positive':sparse.tolist(),
                       'sparse_cutoff_voxels':cutoff,'sparse_rule':'within-case lower quartile of nonzero centre-slice voxel counts'}
    return result


def select_z(pool,rng):
    sparse = np.asarray(pool['sparse_positive'])
    other = np.setdiff1d(np.asarray(pool['positive']),sparse)
    if not len(other):
        other = np.asarray(pool['positive'])
    neg = np.asarray(pool['negative'])
    if not len(neg):
        neg = np.asarray(pool['positive'])
    zs = np.concatenate([rng.choice(p, n, replace=len(p)<n) for p,n in ((sparse,16),(other,16),(neg,8))])
    rng.shuffle(zs)
    return zs.astype(int).tolist()


def masked_loss(logits,target,valid):
    target, mask = target.float(), valid.float()
    positive = (target*mask).sum()
    negative = ((1-target)*mask).sum()
    weight = (negative/(positive+1)).clamp(1,20)
    bce = F.binary_cross_entropy_with_logits(logits.float(),target,pos_weight=weight,reduction='none')
    bce = (bce*mask).sum()/mask.sum().clamp_min(1)
    prob = torch.sigmoid(logits.float())*mask
    dice = 1-(2*(prob*target).sum()+1)/(prob.sum()+(target*mask).sum()+1)
    return 0.5*bce+0.5*dice


def stats(tp,fp,fn,positive_layers=0,hit_positive_layers=0):
    tp,fp,fn,positive_layers,hit_positive_layers = map(int,(tp,fp,fn,positive_layers,hit_positive_layers))
    return {'tp':tp,'fp':fp,'fn':fn,'dice':2*tp/(2*tp+fp+fn) if 2*tp+fp+fn else 1.0,
            'recall':tp/(tp+fn) if tp+fn else None,'precision':tp/(tp+fp) if tp+fp else None,
            'positive_layers':positive_layers,'hit_positive_layers':hit_positive_layers,
            'positive_layer_recall':hit_positive_layers/positive_layers if positive_layers else None}


def aggregate(rows):
    return stats(*(sum(r[k] for r in rows) for k in ('tp','fp','fn','positive_layers','hit_positive_layers')))


def macro(rows):
    return {k:float(np.mean([r[k] for r in rows if r[k] is not None])) if any(r[k] is not None for r in rows) else None
            for k in ('dice','recall','precision','positive_layer_recall')}


def parameter_hash(net):
    digest = hashlib.sha256()
    for name,tensor in net.named_parameters():
        digest.update(name.encode())
        digest.update(tensor.detach().cpu().contiguous().numpy().tobytes())
    return digest.hexdigest()


def optimizer(net,lr):
    return torch.optim.AdamW(net.parameters(),lr=lr,weight_decay=1e-4)


def make_anatomy_reference(run,data,cid):
    from scipy.ndimage import distance_transform_edt,label
    from skimage.morphology import skeletonize
    case = data.open(cid)
    truth = np.unpackbits(case.bits[0],axis=-1,count=case.w,bitorder='little').astype(bool)
    coords = np.nonzero(truth)
    low = [max(0,int(a.min())-1) for a in coords]
    high = [min(truth.shape[i],int(a.max())+2) for i,a in enumerate(coords)]
    box = tuple(slice(a,b) for a,b in zip(low,high))
    crop = truth[box]
    spacing_xyz = data.rows[cid]['spacing_xyz_mm']
    spacing = [spacing_xyz[2],spacing_xyz[0],spacing_xyz[1]]
    skel = skeletonize(crop,method='lee')
    points = np.argwhere(skel).astype(np.int32)
    radii = distance_transform_edt(crop,sampling=spacing)[tuple(points.T)]
    points += np.asarray(low,dtype=np.int32)
    _,components = label(crop,structure=np.ones((3,3,3),dtype=np.uint8))
    p = run/'anatomy_reference'/f'{cid}.npz'
    np.savez_compressed(p,points=points,thin=(radii<=2.0),radii_mm=radii.astype(np.float32))
    info = {'case':cid,'points':len(points),'thin_points_radius_le_2mm':int((radii<=2).sum()),
            'spacing_z_h_w_mm':spacing,'gt_components26':int(components),'annotation_boundary_voxels':data.rows[cid]['label_boundary_voxels'][0],
            'file':str(p.relative_to(run)),'sha256':sha(p)}
    print('ANATOMY_REFERENCE',json.dumps(info),flush=True)
    return info


def anatomy_metrics(pred,reference,run,cid,epoch):
    from scipy.ndimage import label
    with np.load(run/reference['file'],allow_pickle=False) as f:
        points,thin = f['points'],f['thin']
    covered = pred[tuple(points.T)]
    components,number = label(pred,structure=np.ones((3,3,3),dtype=np.uint8))
    counts = np.bincount(components.ravel())
    counts[0] = 0
    largest = int(counts.argmax())
    largest_coverage = components[tuple(points.T)] == largest if largest else np.zeros(len(points),dtype=bool)
    del components
    covered_skel = np.zeros(pred.shape,dtype=bool)
    covered_skel[tuple(points[covered].T)] = True
    _,fragments = label(covered_skel,structure=np.ones((3,3,3),dtype=np.uint8))
    result = {'scope':'fixed validation case; diagnostic, not official airway tree-length/branch detection',
              'gt_centerline_points':len(points),'covered_centerline_points':int(covered.sum()),
              'centerline_voxel_recall_zero_tolerance':float(covered.mean()) if len(points) else None,
              'thin_centerline_points':int(thin.sum()),'covered_thin_centerline_points':int(covered[thin].sum()),
              'thin_centerline_voxel_recall_radius_le_2mm':float(covered[thin].mean()) if thin.any() else None,
              'pred_components26':int(number),'largest_pred_component_fraction':float(counts[largest]/max(1,pred.sum())),
              'centerline_recall_in_largest_pred_component':float(largest_coverage.mean()) if len(points) else None,
              'covered_gt_centerline_components26':int(fragments),'tree_length_detection_rate':None,'branch_detection_rate':None}
    if epoch and epoch % 20 == 0:
        p = run/'reports'/f'fixed_{cid}_epoch_{epoch:04d}_prediction.npz'
        assert not p.exists()
        np.savez_compressed(p,bits=np.packbits(pred,axis=-1,bitorder='little'),shape=np.asarray(pred.shape),points=points,covered=covered,thin=thin)
        result['prediction_evidence'] = {'path':str(p.relative_to(run)),'sha256':sha(p)}
    return result


def evaluate(net,data,ids,run,cfg,epoch,phase):
    net.eval()
    rows, weighted_loss, total_slices = [],0.0,0
    with torch.inference_mode():
        for cid in ids:
            case = data.open(cid)
            sums = np.zeros(5,dtype=np.int64)
            case_loss = 0.0
            reference = cfg['anatomy_references'].get(cid)
            volume = np.zeros((case.zdim,case.h,case.w),dtype=bool) if reference else None
            for start in range(0,case.zdim,cfg['batch_size']):
                if phase != 'smoke':
                    ensure_supervisor(run,cfg)
                heartbeat(run,'trainer',epoch,phase,case=cid,z=start)
                zs = list(range(start,min(start+cfg['batch_size'],case.zdim)))
                x,y,mask = [torch.from_numpy(a).cuda() for a in data.batch(cid,zs)]
                assert not net.training and not torch.is_grad_enabled()
                with torch.autocast(device_type='cuda',dtype=torch.float16):
                    logits = net(x)
                assert logits.shape == y.shape and torch.isfinite(logits).all(), 'nonfinite/eval shape'
                loss = masked_loss(logits,y,mask)
                assert torch.isfinite(loss)
                p,t = (logits.float()>=0)&mask.bool(), y.bool()&mask.bool()
                positive = t.flatten(1).any(1)
                hits = (p&t).flatten(1).any(1)
                values = torch.stack(((p&t).sum(),(p&~t).sum(),(~p&t).sum(),positive.sum(),hits.sum()))
                sums += values.cpu().numpy()
                case_loss += float(loss)*len(zs)
                if volume is not None:
                    volume[start:start+len(zs)] = p[:,0,case.region[0],case.region[1]].cpu().numpy()
            metric = stats(*sums)
            assert metric['tp']+metric['fn'] == data.rows[cid]['label_voxels'][0]
            assert metric['positive_layers'] == len(data.rows[cid]['positive_slices_per_target'][0])
            row = {'case':cid,'slices':case.zdim,'loss':case_loss/case.zdim,'metric':metric,
                   'spacing_xyz_mm':data.rows[cid]['spacing_xyz_mm'],'full_case':True}
            if reference:
                heartbeat(run,'trainer',epoch,'anatomy',case=cid)
                row['anatomy'] = anatomy_metrics(volume,reference,run,cid,epoch)
                del volume
            rows.append(row)
            weighted_loss += case_loss
            total_slices += case.zdim
            print('EVAL_CASE',json.dumps({'epoch':epoch,'phase':phase,'case':cid,**metric}),flush=True)
    return {'loss':weighted_loss/total_slices,'global':aggregate([r['metric'] for r in rows]),
            'macro':macro([r['metric'] for r in rows]),'cases':rows,'case_count':len(ids),'slices':total_slices,
            'eval_mode':not net.training,'grad_enabled':False,'full_cases':True,'threshold_logit':0.0}


def prepare(run):
    assert not run.exists(), 'Use a new run version; never overwrite an experiment'
    preflight = read(AUDIT/'preflight.json')
    assert preflight['status'] == 'PASS' and not preflight['existing_airway_splits']
    assert not preflight['empty_labels'] and not preflight['cross_dataset_exact_matches']
    assert preflight['metadata_sha256'] == sha(CACHE/'metadata.json')
    run.mkdir(parents=True)
    for name in ('source','audit','anatomy_reference','epoch_records','decisions','checkpoints','best_records','reports'):
        (run/name).mkdir()
    for p in Path(__file__).parent.glob('*.py'):
        shutil.copy2(p,run/'source'/p.name)
    for p in AUDIT.glob('*.json'):
        shutil.copy2(p,run/'audit'/p.name)
    seed_all()
    data = AirwayData()
    ordered = sorted(data.rows,key=lambda cid:hashlib.sha256(f'{SEED}:{cid}'.encode()).hexdigest())
    nt,nv = int(len(ordered)*0.70),int(len(ordered)*0.15)
    split = {k:sorted(v) for k,v in zip(('train','val','test'),(ordered[:nt],ordered[nt:nt+nv],ordered[nt+nv:]))}
    assert len(set(sum(split.values(),[]))) == len(data.rows)
    atomic_json(run/'patient_split.json',{'seed':SEED,'dataset':'ATM22','policy':'first fixed internal split of official labelled training pool; case ID is patient unit',**split,
                                         'quarantined':preflight['unavailable'],'source_patient_identity_limit':preflight['duplicate_limit']})
    pools = sampling_pools(data,split['train'])
    atomic_json(run/'sampling_pools.json',pools)
    val_by_size = sorted(split['val'],key=lambda cid:data.rows[cid]['label_voxels'][0])
    fixed = [val_by_size[i] for i in (len(val_by_size)//4,len(val_by_size)//2,3*len(val_by_size)//4)]
    references = {cid:make_anatomy_reference(run,data,cid) for cid in fixed}
    net = ResUNet()
    atomic_torch(run/'initial_weights.pt',{'model':net.state_dict(),'epoch':0,'historical_epoch':None,'seed':SEED,'initialization':'random; no Airway checkpoint found'})
    cfg = {'version':'airway_mkdc_v1','task':'Airway','max_epochs':100,'seed':SEED,'historical_epochs':0,
           'model':{'architecture':'2.5D ResUNet + mkdc + ReLU6','base':16,'downsampling_stages':3,'input_channels':3,'output_logits':1,
                    'mkdc':'parallel depthwise 3x3/5x5 -> sum -> channel shuffle(2) -> pointwise + residual','upsampling':'nearest',
                    'parameters':sum(p.numel() for p in net.parameters())},
           'cache':str(CACHE),'input_contract':CONTRACT,'label_mapping':{'background':0,'airway':1},'threshold_logit':0.0,'threshold_sigmoid':0.5,
           'geometry':preflight['geometry'],'initialization':{'source':'random','checkpoint':str(run/'initial_weights.pt'),'sha256':sha(run/'initial_weights.pt')},
           'splits':split,'split_sha256':sha(run/'patient_split.json'),'sampling_pools_sha256':sha(run/'sampling_pools.json'),
           'train_evaluation_subset':sorted(split['train'][:3]),'batch_size':16,
           'sampling':{'case_visits_per_epoch':1,'samples_per_case':40,'sparse_positive':16,'other_positive':16,'negative':8,
                       'replacement':'only if pool smaller than requested count; all-positive cases replace missing negatives with true positive samples',
                       'all_cases_participate':True,'all_slices_traversed':False,'dataset_balance':'one dataset only',
                       'sparse_positive_rule':'within-case lower quartile by nonzero airway voxel count; proxy, not branch recall'},
           'augmentation':{'flip_h_probability':0.5,'flip_w_probability':0.5,'quarter_turn_probability':0.25,'synchronized':['image','label','valid'],
                           'axes':'only native H/W; Z/channel order unchanged; no intensity transform'},
           'loss':{'name':'masked BCEWithLogits + soft Dice','weights':[0.5,0.5],'pos_weight':'clamp(batch valid negative/(valid positive+1),1,20)',
                   'dice_smooth':1.0,'validation_reduction':'fixed batch=16; slice-weighted batch losses across complete cases'},
           'optimizer':{'name':'AdamW','weight_decay':1e-4,'decay_parameters':'all learned parameters, including BN weights and biases; explicit single group'},
           'lr_schedule':{'name':'cosine','start_lr':None,'end_lr':1e-6,'formula':'end + 0.5*(start-end)*(1+cos(pi*(epoch-1)/99))'},
           'best_selection':{'primary':'maximum global validation Dice','tie_break':'maximum macro validation Dice','test_used':False,
                             'limit':'Dice candidate is not anatomical/deployment acceptance; record Recall/Precision/thin skeleton/continuity changes'},
           'metrics':{'global':'sum TP/FP/FN across all valid voxels','macro':'unweighted case means, undefined Recall/Precision excluded',
                      'empty_label':'Dice=1 only if prediction also empty; recall undefined; precision undefined if no predictions',
                      'positive_layer_recall':'fraction of labelled positive centre slices with at least one true-positive voxel',
                      'tree_length_detection_rate':None,'branch_detection_rate':None,'tree_metric_limit':'No verified official airway tree/branch evaluator available.',
                      'anatomy':'fixed validation cases; skimage Lee 3D GT skeleton; exact coverage, tolerance=0 mm, thin EDT radius<=2 mm; not physical tree length or branch detection',
                      'connectivity':'26-neighbour voxel connectivity in preserved anisotropic native grid; component counts are diagnostic'},
           'anatomy_references':references,'supervision':{'protocol':1,'heartbeat_timeout_seconds':180,'decision_timeout_seconds':180,'startup_timeout_seconds':60,
                         'minimum_disk_free_bytes':2*1024**3,'maximum_amp_skip_fraction':0.1,'log_timeout_seconds':300,
                         'adjustment_policy':'fixed sampling/LR schedule; no reactive changes or test feedback',
                         'all_background_policy':'pause for inspection if full validation predicts zero positive voxels; not automatically diagnosed as a code bug'},
           'metadata_sha256':preflight['metadata_sha256'],'verification_sha256':preflight['verification_sha256'],
           'case_json_sha256':preflight['case_json_sha256'],'code_sha256':{p.name:sha(p) for p in (run/'source').glob('*.py')},
           'software':{'python':sys.version,'torch':torch.__version__,'cuda':torch.version.cuda,'numpy':np.__version__},
           'gpu':preflight['gpu'],'preflight_sha256':sha(run/'audit/preflight.json')}
    atomic_json(run/'draft_config.json',cfg)
    atomic_json(run/'status.json',{'state':'prepared','time':time.time()})
    print('PREPARED',json.dumps({'run':str(run),'splits':{k:len(v) for k,v in split.items()},'fixed_anatomy_cases':fixed,'parameters':cfg['model']['parameters']}),flush=True)


def assert_frozen(run,cfg):
    assert sha(CACHE/'metadata.json') == cfg['metadata_sha256']
    assert sha(CACHE/'final_verification.json') == cfg['verification_sha256']
    assert sha(run/'patient_split.json') == cfg['split_sha256']
    assert sha(run/'sampling_pools.json') == cfg['sampling_pools_sha256']
    for name,digest in cfg['code_sha256'].items():
        assert sha(run/'source'/name) == digest, f'Frozen source changed: {name}'
    for cid,digest in cfg['case_json_sha256'].items():
        assert sha(CACHE/'cases'/cid/'case.json') == digest, f'Case metadata changed: {cid}'
    for ref in cfg['anatomy_references'].values():
        assert sha(run/ref['file']) == ref['sha256']


def initial_model(run,device='cuda'):
    net = ResUNet().to(device)
    saved = torch.load(run/'initial_weights.pt',map_location=device,weights_only=False)
    net.load_state_dict(saved['model'],strict=True)
    return net


def gpu_step(net,opt,scaler,x,y,mask):
    opt.zero_grad(set_to_none=True)
    with torch.autocast(device_type='cuda',dtype=torch.float16):
        logits = net(x)
    assert logits.shape == y.shape and torch.isfinite(logits).all(), 'nonfinite/training output shape'
    loss = masked_loss(logits,y,mask)
    assert torch.isfinite(loss), 'nonfinite loss'
    scaler.scale(loss).backward()
    scaler.unscale_(opt)
    grads = [p.grad for p in net.parameters() if p.grad is not None]
    finite = bool(torch.stack([torch.isfinite(g).all() for g in grads]).all())
    norm = float(torch.sqrt(torch.stack([g.float().square().sum() for g in grads]).sum())) if finite else None
    old_scale = scaler.get_scale()
    scaler.step(opt)
    scaler.update()
    skipped = scaler.get_scale() < old_scale
    assert finite or skipped, 'nonfinite gradients applied'
    if not skipped:
        assert finite and norm is not None and math.isfinite(norm) and norm > 0
    return float(loss),int(skipped),norm


def smoke(run):
    cfg = read(run/'draft_config.json')
    assert not (run/'run_config.json').exists(), 'Do not overwrite finished smoke/config'
    assert_frozen(run,cfg)
    gpu_idle(run)
    seed_all()
    data, pools = AirwayData(),read(run/'sampling_pools.json')
    rng = np.random.default_rng(SEED)
    batches, descriptions = [],[]
    for cid in cfg['splits']['train'][:2]:
        pool = pools[cid]
        pos = np.asarray(pool['positive'])
        negative = np.asarray(pool['negative'] or pool['positive'])
        zs = np.concatenate((rng.choice(pool['sparse_positive'],3,replace=True),rng.choice(pos,3,replace=True),rng.choice(negative,2,replace=True))).astype(int).tolist()
        x,y,mask = data.batch(cid,zs)
        assert x.shape == (8,3,512,512) and x.dtype == np.float32
        assert y.shape == mask.shape == (8,1,512,512) and np.all((y == 0)|(y == 1))
        assert np.all(x == np.rint(x)) and x.min() >= -128 and x.max() <= 127
        assert np.all(y[mask == 0] == 0) and int(y.sum()) == sum(pool['voxel_counts'][z] for z in zs)
        case = data.open(cid)
        for z in (0,case.zdim-1):
            edge = case.read_sample(z)[0]
            assert np.array_equal(edge[0 if z == 0 else 2],edge[1])
        raw,_,_ = case.read_sample(zs[0],float32=False)
        assert np.array_equal(x[0],raw.astype(np.float32))
        for turns in (-1,0,1):
            augmented = transform(x[0],y[0],mask[0],True,True,turns)
            restored = transform(*augmented,False,False,-turns)
            restored = transform(*restored,True,True,0)
            assert all(np.array_equal(a,b) for a,b in zip(restored,(x[0],y[0],mask[0])))
            assert augmented[1].sum() == y[0].sum() and augmented[2].sum() == mask[0].sum()
        selected = select_z(pool,rng)
        actual_pos = sum(pool['voxel_counts'][z] > 0 for z in selected)
        actual_sparse = sum(z in pool['sparse_positive'] for z in selected)
        assert len(selected) == 40 and actual_pos >= 32 and actual_sparse >= 16
        descriptions.append({'case':cid,'centers':zs,'positive_voxels':int(y.sum()),'valid_voxels':int(mask.sum()),
                             'sampled_positive':actual_pos,'sampled_sparse_positive':actual_sparse})
        batches.append((x,y,mask))
    x,y,mask = [torch.from_numpy(np.concatenate([b[i] for b in batches])).cuda() for i in range(3)]
    trials, accepted = [],None
    for lr in (1e-3,3e-4):
        net = initial_model(run)
        opt = optimizer(net,lr)
        scaler = torch.cuda.amp.GradScaler(enabled=True,init_scale=1024)
        assert not opt.state
        before = parameter_hash(net)
        net.train()
        losses,skips,norms = [],0,[]
        started = time.time()
        for step in range(24):
            loss,skip,norm = gpu_step(net,opt,scaler,x,y,mask)
            losses.append(loss)
            skips += skip
            if norm is not None:
                norms.append(norm)
            print('SMOKE_STEP',json.dumps({'lr':lr,'step':step+1,'loss':loss,'amp_skip':skip}),flush=True)
        net.eval()
        with torch.inference_mode(),torch.autocast(device_type='cuda',dtype=torch.float16):
            expected = net(x).clone()
        positive = int(((expected >= 0)&mask.bool()).sum())
        stable = skips <= 2 and all(math.isfinite(v) for v in losses+norms) and np.mean(losses[-4:]) <= np.mean(losses[:4])*1.05
        trial = {'lr':lr,'updates':24-skips,'amp_skipped':skips,'losses':losses,'first4_mean':float(np.mean(losses[:4])),
                 'last4_mean':float(np.mean(losses[-4:])),'positive_eval_voxels':positive,'finite_gradient_norm_max':max(norms),
                 'seconds':time.time()-started,'stable':bool(stable)}
        trials.append(trial)
        if stable and positive > 0:
            accepted = lr
            break
        del net,opt,scaler,expected
        torch.cuda.empty_cache()
    assert accepted is not None, f'Smoke stability/nonzero prediction failed: {trials}'
    assert parameter_hash(net) != before
    steps = [int(v['step']) for v in opt.state.values()]
    assert min(steps) == max(steps) == 24-skips
    checkpoint = {'model':net.state_dict(),'optimizer':opt.state_dict(),'scaler':scaler.state_dict(),'epoch':0,'probe_only':True}
    atomic_torch(run/'smoke_checkpoint.pt',checkpoint)
    restored = initial_model(run)
    state = torch.load(run/'smoke_checkpoint.pt',map_location='cuda',weights_only=False)
    restored.load_state_dict(state['model'],strict=True)
    restored_opt,restored_scaler = optimizer(restored,accepted),torch.cuda.amp.GradScaler(enabled=True)
    restored_opt.load_state_dict(state['optimizer'])
    restored_scaler.load_state_dict(state['scaler'])
    restored.eval()
    with torch.inference_mode(),torch.autocast(device_type='cuda',dtype=torch.float16):
        actual = restored(x)
    assert torch.equal(actual,expected) and restored_scaler.state_dict() == scaler.state_dict()
    for old,new in zip(opt.state.values(),restored_opt.state.values()):
        assert old.keys() == new.keys() and all(torch.equal(old[k].cpu(),new[k].cpu()) for k in old)
    cfg['lr_schedule']['start_lr'] = accepted
    cfg['lr_selection'] = {'source':'random initialization, 24 AMP updates on fixed training-only batch',
                           'candidate_order':[1e-3,3e-4],'chosen':accepted,'rule':'first numerically stable candidate with final-four loss <= 1.05*first-four and nonzero evaluation prediction',
                           'probe_weights_used_for_training':False,'probe_updates_counted_as_run_epochs':False}
    cfg['optimizer']['parameter_names'] = [name for name,_ in net.named_parameters()]
    atomic_json(run/'run_config.json',cfg)
    result = {'status':'PASS','input_shape':list(x.shape),'output_shape':list(expected.shape),'datasets':descriptions,
              'direct_float32_verified':True,'edge_repeat_verified':True,'augmentation_alignment':True,'positive_sampling_verified':True,
              'finite_gradients':True,'optimizer_parameters_updated':True,'AMP':'float16','GradScaler':scaler.state_dict(),
              'checkpoint_prediction_exact_restore':True,'optimizer_moments_and_step_exact_restore':True,'scaler_exact_restore':True,
              'checkpoint_sha256':sha(run/'smoke_checkpoint.pt'),'trials':trials,'selected_lr':accepted,
              'formal_training_restarts_from_saved_random_initialization':True,'resources':resources(run)}
    atomic_json(run/'smoke_check.json',result)
    selfcheck(run)
    atomic_json(run/'status.json',{'state':'ready','time':time.time()})
    print('SMOKE_PASS',json.dumps(result),flush=True)


def ensure_supervisor(run,cfg):
    if (run/'pause_requested.json').exists():
        raise RuntimeError('Supervisor pause: '+str(read(run/'pause_requested.json')))
    pid = read(run/'processes.json')['supervisor']['pid']
    assert alive(pid), 'supervisor process died'
    beat = read(run/'supervisor_heartbeat.json')
    assert beat['pid'] == pid and time.time()-beat['time'] < cfg['supervision']['heartbeat_timeout_seconds'], 'supervisor heartbeat timeout'


def decision_identity(decision,epoch,record_hash,config_hash,pid):
    assert decision['epoch'] == epoch and decision['record_sha256'] == record_hash, 'stale/wrong epoch decision'
    assert decision['run_config_sha256'] == config_hash and decision['supervisor_pid'] == pid, 'wrong run/process decision'
    assert decision['action'] == 'CONTINUE', f'Supervisor held epoch: {decision}'


def wait_decision(run,cfg,epoch,record_hash):
    path = run/'decisions'/f'decision_{epoch:04d}.json'
    deadline = time.monotonic()+cfg['supervision']['decision_timeout_seconds']
    while not path.exists():
        heartbeat(run,'trainer',epoch,'waiting_supervisor',record_sha256=record_hash)
        ensure_supervisor(run,cfg)
        if time.monotonic() > deadline:
            raise TimeoutError(f'epoch {epoch} decision timeout')
        time.sleep(1)
    decision_identity(read(path),epoch,record_hash,sha(run/'run_config.json'),read(run/'processes.json')['supervisor']['pid'])
    assert sha(run/'reports'/f'check_{epoch:04d}.json') == read(path)['check_sha256']
    return sha(path)


def lr_at(cfg,epoch):
    a,b = cfg['lr_schedule']['start_lr'],cfg['lr_schedule']['end_lr']
    return b+0.5*(a-b)*(1+math.cos(math.pi*(epoch-1)/99))


def bundle(net,opt,scaler,epoch,best_epoch,key,coverage,cumulative_updates,run):
    return {'epoch':epoch,'historical_epoch':None,'best_epoch':best_epoch,'best_key':key,'model':net.state_dict(),
            'optimizer':opt.state_dict(),'scaler':scaler.state_dict(),'coverage':coverage,'cumulative_updates':cumulative_updates,
            'run_config_sha256':sha(run/'run_config.json'),'rng':{'python':random.getstate(),'numpy':np.random.get_state(),
            'torch':torch.get_rng_state(),'cuda':torch.cuda.get_rng_state_all()}}


def twenty_report(run,epoch):
    records = [read(p) for p in sorted((run/'epoch_records').glob('epoch_*.json'))][-20:]
    latest = records[-1]
    train,val = latest['train_evaluation']['macro'],latest['validation']['macro']
    histories = {k:[r['validation']['global'][k] for r in records] for k in ('dice','recall','precision','positive_layer_recall')}
    result = {'epoch':epoch,'best_epoch':latest['best_epoch'],'validation_history':histories,
              'train_validation_macro_dice_gap':train['dice']-val['dice'],
              'worst_cases':sorted(latest['validation']['cases'],key=lambda r:r['metric']['dice'])[:5],
              'fixed_case_anatomy':[{k:r[k] for k in ('case','anatomy')} for r in latest['validation']['cases'] if 'anatomy' in r],
              'false_positive_voxels':latest['validation']['global']['fp'],'false_negative_voxels':latest['validation']['global']['fn'],
              'tree_metric_limit':'Official airway length/branch detection unavailable; diagnostic exact skeleton/physical radius/component measures only.',
              'overfitting':'Low recall, plateau or one-epoch variation alone is insufficient; compare full train subset and validation trajectories.',
              'recommendation':'Continue to configured maximum only if supervisory checks pass; investigate persistent thin-skeleton misses or fragmented largest-component coverage.',
              'adjustments':[]}
    atomic_json(run/'reports'/f'analysis_{epoch:04d}.json',result)
    print('ANALYSIS20',json.dumps(result),flush=True)


def train(run,resume=False):
    cfg = read(run/'run_config.json')
    seed_all()
    assert_frozen(run,cfg)
    assert read(run/'smoke_check.json')['status'] == 'PASS'
    heartbeat(run,'trainer',0,'startup')
    deadline = time.monotonic()+cfg['supervision']['startup_timeout_seconds']
    while not (run/'processes.json').exists() or not (run/'supervisor_heartbeat.json').exists():
        if time.monotonic() > deadline:
            raise TimeoutError('supervisor startup timeout')
        time.sleep(1)
    ensure_supervisor(run,cfg)
    data,pools = AirwayData(),read(run/'sampling_pools.json')
    net = initial_model(run)
    opt = optimizer(net,cfg['lr_schedule']['start_lr'])
    scaler = torch.cuda.amp.GradScaler(enabled=True,init_scale=1024)
    completed,best_epoch,cumulative_updates,previous_decision = 0,0,0,None
    key,coverage,immutable_best = (-1.0,-1.0),{cid:[] for cid in cfg['splits']['train']},None
    if resume:
        state = torch.load(run/'last.pt',map_location='cuda',weights_only=False)
        completed = state['epoch']
        decision = run/'decisions'/f'decision_{completed:04d}.json'
        assert read(decision)['action'] == 'CONTINUE', 'Use last trusted checkpoint only'
        rec = read(run/'epoch_records'/f'epoch_{completed:04d}.json')
        assert sha(run/'last.pt') == rec['checkpoints']['last']['sha256'] and state['run_config_sha256'] == sha(run/'run_config.json')
        net.load_state_dict(state['model'],strict=True)
        opt.load_state_dict(state['optimizer'])
        scaler.load_state_dict(state['scaler'])
        coverage,cumulative_updates = state['coverage'],state['cumulative_updates']
        best_epoch,key = state['best_epoch'],tuple(state['best_key'])
        previous_decision = sha(decision)
        immutable_best = rec['checkpoints']['best_immutable']['path']
    else:
        assert not (run/'last.pt').exists() and not (run/'best.pt').exists()
    epoch = completed
    try:
        for epoch in range(completed+1,cfg['max_epochs']+1):
            ensure_supervisor(run,cfg)
            assert_frozen(run,cfg)
            assert resources(run)['disk_free_bytes'] >= cfg['supervision']['minimum_disk_free_bytes']
            assert not (run/'epoch_records'/f'epoch_{epoch:04d}.json').exists(), 'Completed/pending record is immutable'
            started = time.time()
            heartbeat(run,'trainer',epoch,'training')
            atomic_json(run/'status.json',{'state':'training','epoch':epoch,'completed_epochs':completed,'time':time.time()})
            lr = lr_at(cfg,epoch)
            for group in opt.param_groups:
                group['lr'] = lr
            net.train()
            torch.cuda.reset_peak_memory_stats()
            rng,planar_rng = np.random.default_rng(SEED+epoch*1009),random.Random(SEED+epoch*1013)
            order = cfg['splits']['train'][:]
            rng.shuffle(order)
            sampled,loss_sum,attempted,updates,skipped,max_grad = {},0.0,0,0,0,0.0
            before = parameter_hash(net)
            for cid in order:
                zs = select_z(pools[cid],rng)
                counts = pools[cid]['voxel_counts']
                coverage[cid] = sorted(set(coverage[cid])|set(zs))
                entry = {'visits':1,'samples':len(zs),'centers':zs,'positive_slices':sum(counts[z]>0 for z in zs),
                         'negative_slices':sum(counts[z]==0 for z in zs),'sparse_positive_slices':sum(z in pools[cid]['sparse_positive'] for z in zs),
                         'unique_slices_epoch':len(set(zs)),'unique_slices_run':len(coverage[cid]),'available_slices':len(counts),
                         'supervised_voxels':0,'positive_supervised_voxels':0,'source_batch':data.rows[cid]['batch']}
                for offset in range(0,len(zs),cfg['batch_size']):
                    ensure_supervisor(run,cfg)
                    heartbeat(run,'trainer',epoch,'training',case=cid,batch=attempted)
                    arrays = data.batch(cid,zs[offset:offset+cfg['batch_size']],planar_rng)
                    _,yn,vn = arrays
                    assert np.all(yn[vn == 0] == 0) and np.all((yn == 0)|(yn == 1))
                    entry['supervised_voxels'] += int(vn.sum())
                    entry['positive_supervised_voxels'] += int((yn*vn).sum())
                    x,y,mask = [torch.from_numpy(a).cuda() for a in arrays]
                    assert net.training and torch.is_grad_enabled()
                    loss,skip,norm = gpu_step(net,opt,scaler,x,y,mask)
                    attempted += 1
                    skipped += skip
                    updates += 1-skip
                    if norm is not None:
                        max_grad = max(max_grad,norm)
                    loss_sum += loss*len(x)
                    if attempted >= 20 and skipped/attempted > cfg['supervision']['maximum_amp_skip_fraction']:
                        raise RuntimeError('AMP skip fraction above declared maximum')
                    if attempted % 50 == 0:
                        print('PROGRESS',json.dumps({'epoch':epoch,'step':attempted,'case':cid,'loss':loss,'amp_skipped':skipped}),flush=True)
                assert entry['positive_supervised_voxels'] == sum(counts[z] for z in zs)
                sampled[cid] = entry
            after = parameter_hash(net)
            assert before != after and updates > 0
            cumulative_updates += updates
            validation = evaluate(net,data,cfg['splits']['val'],run,cfg,epoch,'validation')
            train_eval = evaluate(net,data,cfg['train_evaluation_subset'],run,cfg,epoch,'train_subset_evaluation')
            candidate = (validation['global']['dice'],validation['macro']['dice'])
            refresh = candidate > key
            if refresh:
                best_epoch,key = epoch,candidate
            checkpoint = run/'checkpoints'/f'epoch_{epoch:04d}.pt'
            assert not checkpoint.exists()
            atomic_torch(checkpoint,bundle(net,opt,scaler,epoch,best_epoch,key,coverage,cumulative_updates,run))
            atomic_copy(checkpoint,run/'last.pt')
            if refresh:
                immutable_best = f'best_records/best_epoch_{epoch:04d}.pt'
                assert not (run/immutable_best).exists()
                atomic_copy(checkpoint,run/immutable_best)
                atomic_copy(checkpoint,run/'best.pt')
            checkpoints = {k:{'path':p,'sha256':sha(run/p)} for k,p in (
                ('epoch',str(checkpoint.relative_to(run))),('last','last.pt'),('best','best.pt'),('best_immutable',immutable_best))}
            sampling = {k:sum(v[k] for v in sampled.values()) for k in ('samples','positive_slices','negative_slices','sparse_positive_slices','supervised_voxels','positive_supervised_voxels','unique_slices_epoch','unique_slices_run')}
            sampling.update({'dataset':'ATM22','cases':sampled,'all_cases_participated':True,'all_slices_traversed':False,
                             'available_training_slices':sum(len(p['voxel_counts']) for p in pools.values()),
                             'source_batches':{b:sum(v['samples'] for v in sampled.values() if v['source_batch'] == b) for b in ('TrainBatch1','TrainBatch2')}})
            record = {'protocol':1,'epoch':epoch,'historical_epoch':None,'run_config_sha256':sha(run/'run_config.json'),
                      'previous_decision_sha256':previous_decision,'lr':lr,'best_epoch':best_epoch,'best_refreshed':refresh,
                      'training':{'train_loss':loss_sum/sampling['samples'],'attempted_steps':attempted,'optimizer_updates':updates,'amp_skipped_steps':skipped,
                                  'cumulative_optimizer_updates':cumulative_updates,'gradient_norm_max':max_grad,'parameter_sha256_before':before,'parameter_sha256_after':after,
                                  'train_mode_all_batches':True,'grad_enabled_all_batches':True,'finite_loss_all_batches':True,'finite_gradients_all_applied_steps':True,
                                  'scaler_enabled':scaler.is_enabled(),'scaler_scale':scaler.get_scale(),'amp_dtype':'float16','sampling':sampling},
                      'validation':validation,'train_evaluation':train_eval,'seconds':time.time()-started,
                      'gpu_peak_allocated_bytes':torch.cuda.max_memory_allocated(),'gpu_peak_reserved_bytes':torch.cuda.max_memory_reserved(),
                      'resources':resources(run),'checkpoints':checkpoints}
            record_path = run/'epoch_records'/f'epoch_{epoch:04d}.json'
            atomic_json(record_path,record)
            record_hash = sha(record_path)
            atomic_json(run/'epoch_ready.json',{'epoch':epoch,'record_sha256':record_hash,'time':time.time()})
            previous_decision = wait_decision(run,cfg,epoch,record_hash)
            completed = epoch
            summary = {'epoch':epoch,**validation['global'],'macro_dice':validation['macro']['dice'],'best_epoch':best_epoch,
                       'best_refreshed':refresh,'supervision':'PASS','fixed_anatomy':{r['case']:r['anatomy'] for r in validation['cases'] if 'anatomy' in r}}
            print('EPOCH',json.dumps(summary),flush=True)
            event(run,'epoch_complete',**summary)
            if epoch % 20 == 0:
                twenty_report(run,epoch)
            if (run/'stop_requested.json').exists():
                event(run,'user_stop_at_epoch_boundary',epoch=epoch)
                break
        heartbeat(run,'trainer',completed,'final_test')
        atomic_json(run/'status.json',{'state':'finalizing','completed_epochs':completed,'best_epoch':best_epoch,'time':time.time()})
        selected = torch.load(run/'best.pt',map_location='cuda',weights_only=False)
        net.load_state_dict(selected['model'],strict=True)
        test = evaluate(net,data,cfg['splits']['test'],run,cfg,completed,'final_test')
        best_validation = read(run/'epoch_records'/f'epoch_{best_epoch:04d}.json')['validation']
        final = {'state':'complete','task':'Airway','completed_epochs':completed,'best_epoch':best_epoch,'historical_epochs':0,
                 'best_checkpoint':str(run/'best.pt'),'best_checkpoint_sha256':sha(run/'best.pt'),
                 'best_immutable':str(run/immutable_best),'best_immutable_sha256':sha(run/immutable_best),
                 'best_validation':best_validation,'test':test,'test_used_for_selection':False,'threshold_logit':0.0,
                 'tree_metrics':cfg['metrics'],'supervision':{'epoch_checks_passed':completed,'adjustments':[],'repairs':cfg.get('repairs',[])},
                 'abnormal_cases':read(run/'audit/preflight.json')['unavailable'],
                 'deployment':'Requires independent INT8/deployment and anatomy validation; voxel Dice alone is insufficient.',
                 'recommendation_3d':'If persistent thin-centerline misses/fragmentation are evidenced, suggest a separate lightweight 3D experiment; do not launch it here.',
                 'resources':resources(run),'time':time.time()}
        atomic_json(run/'final_results.json',final)
        deadline = time.monotonic()+cfg['supervision']['decision_timeout_seconds']
        while not (run/'final_check.json').exists():
            ensure_supervisor(run,cfg)
            heartbeat(run,'trainer',completed,'waiting_final_check')
            if time.monotonic() > deadline:
                raise TimeoutError('final supervisor check timeout')
            time.sleep(1)
        assert read(run/'final_check.json')['status'] == 'PASS'
        atomic_json(run/'status.json',{'state':'complete','completed_epochs':completed,'best_epoch':best_epoch,'time':time.time()})
        print('COMPLETE',json.dumps({'epochs':completed,'best_epoch':best_epoch,'validation':best_validation['global'],'test':test['global']}),flush=True)
    except Exception as exc:
        path = run/f'paused_epoch_{epoch:04d}_{int(time.time())}.pt'
        atomic_torch(path,bundle(net,opt,scaler,epoch,best_epoch,key,coverage,cumulative_updates,run))
        failure = {'state':'paused','epoch':epoch,'completed_epochs':completed,'best_epoch':best_epoch,'error':repr(exc),
                   'traceback':traceback.format_exc(),'partial_checkpoint':str(path),'partial_checkpoint_sha256':sha(path),'time':time.time()}
        atomic_json(run/'status.json',failure)
        event(run,'trainer_paused',**failure)
        print('PAUSED',json.dumps(failure),flush=True)
        raise


def check_metric(value):
    keys = ('tp','fp','fn','positive_layers','hit_positive_layers')
    assert all(isinstance(value[k],int) and value[k]>=0 for k in keys)
    assert value['hit_positive_layers'] <= value['positive_layers']
    wanted = stats(*(value[k] for k in keys))
    for key in ('dice','recall','precision','positive_layer_recall'):
        a,b = value[key],wanted[key]
        assert (a is None if b is None else a is not None and math.isfinite(a) and abs(a-b)<1e-12), f'inconsistent {key}'


def check_evaluation(evaluation,ids,rows):
    assert [r['case'] for r in evaluation['cases']] == ids, 'full evaluation patient coverage/order'
    assert evaluation['case_count'] == len(ids) and evaluation['slices'] == sum(rows[c]['shape_h_w_z'][2] for c in ids)
    assert evaluation['eval_mode'] and not evaluation['grad_enabled'] and evaluation['full_cases']
    assert evaluation['threshold_logit'] == 0.0 and math.isfinite(evaluation['loss']) and evaluation['loss'] >= 0
    for r in evaluation['cases']:
        assert r['full_case'] and r['slices'] == rows[r['case']]['shape_h_w_z'][2]
        check_metric(r['metric'])
        assert r['metric']['tp']+r['metric']['fn'] == rows[r['case']]['label_voxels'][0]
        assert r['metric']['positive_layers'] == len(rows[r['case']]['positive_slices_per_target'][0])
        if 'anatomy' in r:
            anatomy = r['anatomy']
            for n,d,key in (('covered_centerline_points','gt_centerline_points','centerline_voxel_recall_zero_tolerance'),
                            ('covered_thin_centerline_points','thin_centerline_points','thin_centerline_voxel_recall_radius_le_2mm')):
                assert 0 <= anatomy[n] <= anatomy[d]
                assert anatomy[key] is None if not anatomy[d] else abs(anatomy[key]-anatomy[n]/anatomy[d]) < 1e-12
            assert anatomy['tree_length_detection_rate'] is None and anatomy['branch_detection_rate'] is None
    check_metric(evaluation['global'])
    assert evaluation['global'] == aggregate([r['metric'] for r in evaluation['cases']])
    assert evaluation['macro'] == macro([r['metric'] for r in evaluation['cases']])


def check_epoch(run,cfg,rec,epoch,record_hash):
    assert rec['protocol'] == 1 and rec['epoch'] == epoch and rec['historical_epoch'] is None
    assert sha(run/'epoch_records'/f'epoch_{epoch:04d}.json') == record_hash
    assert rec['run_config_sha256'] == sha(run/'run_config.json')
    assert_frozen(run,cfg)
    split = cfg['splits']
    assert len(set(sum(split.values(),[]))) == sum(map(len,split.values())) == 280
    assert not read(run/'audit/preflight.json')['within_cache_duplicate_groups']
    if epoch > 1:
        p = run/'decisions'/f'decision_{epoch-1:04d}.json'
        assert rec['previous_decision_sha256'] == sha(p) and read(p)['action'] == 'CONTINUE'
    t = rec['training']
    assert t['train_mode_all_batches'] and t['grad_enabled_all_batches'] and t['finite_loss_all_batches']
    assert t['finite_gradients_all_applied_steps'] and t['scaler_enabled'] and t['amp_dtype'] == 'float16'
    assert t['optimizer_updates'] > 0 and t['parameter_sha256_before'] != t['parameter_sha256_after']
    assert t['optimizer_updates']+t['amp_skipped_steps'] == t['attempted_steps']
    assert t['amp_skipped_steps']/t['attempted_steps'] <= cfg['supervision']['maximum_amp_skip_fraction']
    assert math.isfinite(t['gradient_norm_max']) and t['gradient_norm_max'] > 0 and math.isfinite(t['train_loss'])
    assert abs(rec['lr']-lr_at(cfg,epoch)) < 1e-15
    pools = read(run/'sampling_pools.json')
    rows = AirwayData().rows
    sampling = t['sampling']
    assert sampling['dataset'] == 'ATM22' and set(sampling['cases']) == set(split['train'])
    assert sampling['samples'] == 40*len(split['train'])
    assert sampling['all_cases_participated'] and not sampling['all_slices_traversed']
    for cid,s in sampling['cases'].items():
        counts,pool = pools[cid]['voxel_counts'],pools[cid]
        zs = s['centers']
        assert s['visits'] == 1 and s['samples'] == len(zs) == 40
        assert all(0 <= z < len(counts) for z in zs)
        assert s['positive_slices'] == sum(counts[z]>0 for z in zs) >= 32
        assert s['negative_slices'] == sum(counts[z]==0 for z in zs)
        assert s['sparse_positive_slices'] == sum(z in pool['sparse_positive'] for z in zs) >= 16
        assert s['positive_supervised_voxels'] == sum(counts[z] for z in zs)
        h,w,_ = rows[cid]['shape_h_w_z']
        assert s['supervised_voxels'] == 40*h*w
        assert s['unique_slices_epoch'] == len(set(zs)) <= s['unique_slices_run'] <= len(counts)
        assert s['source_batch'] == rows[cid]['batch'] and rows[cid]['target_names'] == ['airway']
    for k in ('samples','positive_slices','negative_slices','sparse_positive_slices','supervised_voxels','positive_supervised_voxels','unique_slices_epoch','unique_slices_run'):
        assert sampling[k] == sum(s[k] for s in sampling['cases'].values()), k
    assert sampling['negative_slices'] > 0 and sampling['positive_supervised_voxels'] > 0
    for b in ('TrainBatch1','TrainBatch2'):
        assert sampling['source_batches'][b] == sum(s['samples'] for s in sampling['cases'].values() if s['source_batch'] == b) > 0
    check_evaluation(rec['validation'],split['val'],rows)
    check_evaluation(rec['train_evaluation'],cfg['train_evaluation_subset'],rows)
    val = rec['validation']['global']
    assert val['tp']+val['fp'] > 0, 'Full validation all-background: pause for model/data inspection, not an automatic code-error diagnosis'
    history = [read(run/'epoch_records'/f'epoch_{i:04d}.json') for i in range(1,epoch)] + [rec]
    winner = max(history,key=lambda r:(r['validation']['global']['dice'],r['validation']['macro']['dice']))
    assert rec['best_epoch'] == winner['epoch'], 'Best ranking differs from frozen validation-only selection'
    assert rec['best_refreshed'] == (winner['epoch'] == epoch)
    for previous in history:
        if previous['best_refreshed']:
            evidence = previous['checkpoints']['best_immutable']
            assert sha(run/evidence['path']) == evidence['sha256'], 'Historical immutable best changed'
    for kind,value in rec['checkpoints'].items():
        assert sha(run/value['path']) == value['sha256'], f'{kind} checkpoint SHA256 mismatch'
    last = torch.load(run/'last.pt',map_location='cpu',weights_only=False)
    assert last['epoch'] == epoch and last['run_config_sha256'] == rec['run_config_sha256']
    assert last['optimizer']['state'] and last['scaler']['scale'] > 0
    assert all(torch.isfinite(v).all() for v in last['model'].values())
    assert last['optimizer']['param_groups'][0]['weight_decay'] == 1e-4
    assert last['optimizer']['param_groups'][0]['lr'] == rec['lr']
    assert all(int(v['step']) == t['cumulative_optimizer_updates'] for v in last['optimizer']['state'].values())
    cpu = ResUNet()
    cpu.load_state_dict(last['model'],strict=True)
    assert parameter_hash(cpu) == t['parameter_sha256_after']
    assert len(last['optimizer']['param_groups'][0]['params']) == len(cfg['optimizer']['parameter_names'])
    assert last['coverage'].keys() == sampling['cases'].keys()
    for cid,s in sampling['cases'].items():
        assert len(last['coverage'][cid]) == s['unique_slices_run']
    if rec['best_refreshed']:
        assert rec['best_epoch'] == epoch
        assert rec['checkpoints']['best']['sha256'] == rec['checkpoints']['epoch']['sha256'] == rec['checkpoints']['best_immutable']['sha256']
    else:
        assert rec['best_epoch'] < epoch and rec['checkpoints']['best']['sha256'] == rec['checkpoints']['best_immutable']['sha256']
    assert rec['resources']['disk_free_bytes'] >= cfg['supervision']['minimum_disk_free_bytes']
    warnings = []
    if epoch > 1:
        previous = read(run/'epoch_records'/f'epoch_{epoch-1:04d}.json')
        old = previous['validation']['global']
        ratio = (val['tp']+val['fp'])/max(1,old['tp']+old['fp'])
        if not 0.5 <= ratio <= 2:
            warnings.append(f'Predicted voxel ratio vs previous epoch={ratio:.3f}; inspect per-case evidence without reactive changes')
        if rec['best_refreshed']:
            old_best = read(run/'epoch_records'/f"epoch_{previous['best_epoch']:04d}.json")['validation']
            if val['recall'] < old_best['global']['recall']-0.10:
                warnings.append('Dice-best candidate loses >0.10 absolute Recall versus previous best; not overall anatomical success')
            old_anatomy = {r['case']:r['anatomy'] for r in old_best['cases'] if 'anatomy' in r}
            for r in rec['validation']['cases']:
                if r['case'] in old_anatomy:
                    field = 'thin_centerline_voxel_recall_radius_le_2mm'
                    a,b = r['anatomy'][field],old_anatomy[r['case']][field]
                    if a is not None and b is not None and a < b-0.10:
                        warnings.append(f"{r['case']}: thin-skeleton recall dropped >0.10 versus previous Dice best")
    return {'status':'PASS','warnings':warnings,'adjustments':[],
            'checks':['frozen Airway label/input/source contracts','patient split and exact-hash duplicate checks','all train cases and both source batches',
                      'positive/negative/sparse-layer sampling and actual supervision counts','full validation/complete train-subset inference',
                      'valid masks and ground-truth voxel/layer totals','confusion counts/global/macro metrics','AMP/scaler/LR/gradients/updates',
                      'checkpoint optimizer/scaler/model hashes and immutable best','fixed-case skeleton/continuity diagnostics','disk space']}


def selfcheck(run):
    good = stats(2,1,1,2,1)
    check_metric(good)
    caught = 0
    try:
        check_metric({**good,'dice':0.99})
    except AssertionError:
        caught += 1
    d = {'epoch':1,'record_sha256':'a','run_config_sha256':'b','supervisor_pid':123,'action':'CONTINUE'}
    decision_identity(d,1,'a','b',123)
    for bad in ({**d,'epoch':0},{**d,'record_sha256':'wrong'},{**d,'supervisor_pid':124}):
        try:
            decision_identity(bad,1,'a','b',123)
        except AssertionError:
            caught += 1
    p = subprocess.Popen([sys.executable,'-c','pass'],stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL)
    p.wait(timeout=10)
    assert not alive(p.pid) and caught == 4
    atomic_json(run/'supervisor_selfcheck.json',{'status':'PASS','incorrect_metric_rejected':True,'stale_epoch_rejected':True,
                                               'wrong_record_hash_rejected':True,'wrong_supervisor_rejected':True,'dead_OS_process_detected':True})


def supervise(run):
    cfg = read(run/'run_config.json')
    torch.set_num_threads(4)
    assert_frozen(run,cfg)
    checked = 0
    for p in sorted((run/'decisions').glob('decision_*.json')):
        d = read(p)
        assert d['action'] == 'CONTINUE', 'Failed epoch requires repair/new version, not silent restart'
        checked = d['epoch']
    startup,final_checked = time.monotonic()+cfg['supervision']['startup_timeout_seconds'],False
    while True:
        heartbeat(run,'supervisor',checked,'watching')
        if not (run/'processes.json').exists():
            assert time.monotonic() < startup, 'Trainer registration timeout'
            time.sleep(1)
            continue
        processes = read(run/'processes.json')
        assert processes['supervisor']['pid'] == os.getpid()
        status = read(run/'status.json')
        if status['state'] in ('complete','paused'):
            print('SUPERVISOR_EXIT',json.dumps(status),flush=True)
            return
        reason = None
        if not alive(processes['trainer']['pid']):
            reason = 'Trainer exited before completion; preserve latest immutable checkpoint'
        elif (run/'trainer_heartbeat.json').exists():
            beat = read(run/'trainer_heartbeat.json')
            if beat['pid'] != processes['trainer']['pid'] or time.time()-beat['time'] > cfg['supervision']['heartbeat_timeout_seconds']:
                reason = 'Trainer heartbeat stopped/wrong PID'
        elif time.monotonic() > startup:
            reason = 'Trainer heartbeat never appeared'
        state = resources(run)
        if state['disk_free_bytes'] < cfg['supervision']['minimum_disk_free_bytes']:
            reason = 'Disk below 2 GiB reserve'
        foreign = set(state['gpu_compute_pids'])-{processes['trainer']['pid']}
        if foreign:
            reason = f'Foreign GPU processes {sorted(foreign)}; pause own training without stopping them'
        log = Path(processes['trainer']['log'])
        if log.exists():
            with log.open('rb') as f:
                f.seek(max(0,log.stat().st_size-8192))
                tail = f.read().decode(errors='replace')
            if 'Traceback (most recent call last)' in tail or 'CUDA out of memory' in tail:
                reason = 'Trainer exception/OOM in log'
            if time.time()-log.stat().st_mtime > cfg['supervision']['log_timeout_seconds']:
                reason = 'Trainer log stalled >300 seconds'
        ready = run/'epoch_ready.json'
        if ready.exists() and read(ready)['epoch'] > checked:
            r = read(ready)
            epoch,record_hash = r['epoch'],r['record_sha256']
            heartbeat(run,'supervisor',epoch,'checking_epoch')
            try:
                assert epoch == checked+1, 'Nonsequential epoch'
                rec = read(run/'epoch_records'/f'epoch_{epoch:04d}.json')
                result = check_epoch(run,cfg,rec,epoch,record_hash)
                action = 'CONTINUE'
            except Exception as exc:
                result = {'status':'FAIL','error':repr(exc),'traceback':traceback.format_exc()}
                action,reason = 'PAUSE',f'epoch {epoch} verification failed: {exc!r}'
            result.update({'epoch':epoch,'record_sha256':record_hash,'supervisor_pid':os.getpid(),'time':time.time()})
            report = run/'reports'/f'check_{epoch:04d}.json'
            decision = run/'decisions'/f'decision_{epoch:04d}.json'
            assert not report.exists() and not decision.exists()
            atomic_json(report,result)
            atomic_json(decision,{'protocol':1,'epoch':epoch,'record_sha256':record_hash,'run_config_sha256':sha(run/'run_config.json'),
                                 'supervisor_pid':os.getpid(),'action':action,'check_sha256':sha(report),'time':time.time()})
            checked = epoch
            print('SUPERVISOR',json.dumps(result),flush=True)
        if (run/'final_results.json').exists() and not final_checked:
            try:
                final = read(run/'final_results.json')
                assert final['state'] == 'complete' and final['task'] == 'Airway' and final['completed_epochs'] == checked <= 100
                assert not final['test_used_for_selection']
                assert sha(final['best_checkpoint']) == final['best_checkpoint_sha256']
                assert sha(final['best_immutable']) == final['best_immutable_sha256']
                check_evaluation(final['test'],cfg['splits']['test'],AirwayData().rows)
                result = {'status':'PASS','epochs':checked,'final_results_sha256':sha(run/'final_results.json'),'time':time.time()}
            except Exception as exc:
                result = {'status':'FAIL','error':repr(exc),'traceback':traceback.format_exc(),'time':time.time()}
                reason = 'Final result failed verification'
            atomic_json(run/'final_check.json',result)
            print('FINAL_CHECK',json.dumps(result),flush=True)
            final_checked = True
        if reason:
            atomic_json(run/'pause_requested.json',{'reason':reason,'epoch':checked,'supervisor_pid':os.getpid(),'time':time.time()})
            event(run,'supervisor_pause_request',reason=reason)
            if not alive(processes['trainer']['pid']):
                atomic_json(run/'status.json',{'state':'paused','completed_epochs':checked,'error':reason,'time':time.time()})
                return
        time.sleep(3)


def launch(run,resume=False):
    cfg = read(run/'run_config.json')
    assert_frozen(run,cfg)
    assert read(run/'smoke_check.json')['status'] == read(run/'supervisor_selfcheck.json')['status'] == 'PASS'
    if (run/'processes.json').exists():
        old = read(run/'processes.json')
        assert not alive(old['trainer']['pid']) and not alive(old['supervisor']['pid']), 'Already running'
    if not resume:
        assert read(run/'status.json')['state'] == 'ready'
    else:
        assert not (run/'pause_requested.json').exists(), 'Repair/resmoke and explicitly clear fault before same-code resume'
    gpu_idle(run)
    atomic_json(run/'status.json',{'state':'starting','time':time.time()})
    script = run/'source'/Path(__file__).name
    commands = {role:[sys.executable,'-u',str(script),mode,'--run-dir',str(run)]
                for role,mode in (('supervisor','supervise'),('trainer','train'))}
    if resume:
        commands['trainer'].append('--resume')
    suffix = f'.resume_{int(time.time())}' if resume else ''
    processes = {}
    for role in ('supervisor','trainer'):
        log = run/f'{role}{suffix}.log'
        with log.open('x') as f:
            p = subprocess.Popen(commands[role],stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT,cwd=run,start_new_session=True)
        processes[role] = {'pid':p.pid,'command':commands[role],'log':str(log)}
    processes['started_at'],processes['run_config_sha256'] = time.time(),sha(run/'run_config.json')
    atomic_json(run/'processes.json',processes)
    print('LAUNCHED',json.dumps(processes),flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode',choices=('prepare','smoke','launch','train','supervise','selfcheck'))
    parser.add_argument('--run-dir',type=Path,required=True)
    parser.add_argument('--resume',action='store_true')
    args = parser.parse_args()
    if args.mode == 'prepare':
        prepare(args.run_dir)
    elif args.mode == 'smoke':
        smoke(args.run_dir)
    elif args.mode == 'launch':
        launch(args.run_dir,args.resume)
    elif args.mode == 'train':
        train(args.run_dir,args.resume)
    elif args.mode == 'supervise':
        supervise(args.run_dir)
    else:
        selfcheck(args.run_dir)


if __name__ == '__main__':
    main()
