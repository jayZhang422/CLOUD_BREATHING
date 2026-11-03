"""Complete crossing frames, with optional hardware volume integration."""
import struct

ABI_VERSION=0x00040000
MAX_HITS=128
RESULT_BYTES=64+MAX_HITS*4

def decode_results(data,ray_count,max_hits=MAX_HITS,*,volume=False,union=False,
                   expected_solid_count=None):
    stride=64+max_hits*4
    if len(data)!=ray_count*stride:raise ValueError('complete result size mismatch')
    output=[]
    for ri in range(ray_count):
        words=struct.unpack_from('<%dI'%(16+max_hits),data,ri*stride)
        ray_id,status,raw,count,entry,exit_,inside,intervals=words[:8]
        if ray_id!=ri+1 or count>max_hits or count>raw or inside>1:
            raise ValueError('complete result header invalid')
        hits=list(struct.unpack_from('<%di'%count,data,ri*stride+64)) if count else []
        if any(x<0 for x in hits) or any(b-a<=1 for a,b in zip(hits,hits[1:])):
            raise ValueError('crossings are not sorted and deduplicated')
        if (not union and inside!=count%2) or intervals!=(count+inside)//2:
            raise ValueError('parity/interval header invalid')
        if entry!=((0 if inside else hits[0]) if hits else 0x7fffffff):
            raise ValueError('entry header invalid')
        if exit_!=(hits[-1] if hits else 0):raise ValueError('exit header invalid')
        pairs=[]
        edges=([0]+hits) if inside else hits
        pairs=[edges[i:i+2] for i in range(0,len(edges),2)]
        output.append(dict(ray_id=ray_id,errors=status&255,advisory_flags=(status>>8)&255,
            hit_count=raw,unique_count=count,t_near_q16=hits[0] if hits else 0x7fffffff,
            t_far_q16=hits[-1] if hits else 0,entry_q16=entry,exit_q16=exit_,inside=bool(inside),
            interval_count=intervals,crossings_q16=hits,intervals_q16=pairs,parallel_count=words[10],complete_crossings=True))
        if words[15]:
            if words[15] > 32 or words[13] > raw or words[14] != count:
                raise ValueError('multi-solid diagnostic counters invalid')
            if expected_solid_count is not None and words[15] != expected_solid_count:
                raise ValueError('PL solid count disagrees with requested mesh')
            output[-1].update(raw_hit_count=raw, event_count=words[13],
                              union_boundary_count=words[14], solid_count=words[15])
        elif expected_solid_count is not None:
            raise ValueError('PL result is missing multi-solid diagnostics')
        if volume:
            fraction,length,valid=words[8],words[11],words[12]
            if fraction>1<<30 or valid>1 or bool(valid)==bool(status&255):
                raise ValueError('invalid PL volume status/fraction')
            if valid and not 0<length<0x80000000:
                raise ValueError('invalid PL integration length')
            if not valid and fraction:
                raise ValueError('failed ray contains a volume fraction')
            output[-1].update(volume_fraction_q30=fraction,volume_fraction=fraction/(1<<30),
                              length_q16=length,volume_valid=bool(valid))
    return output
