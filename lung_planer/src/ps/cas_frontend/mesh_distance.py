"""96-bit unsigned Q32 squared-distance result ABI."""
import struct
RESULT_BYTES=32
SCALE=1<<32
MAX_SQUARED=3*((1<<32)-1)**2

def decode_results(data,count):
    if count<0 or len(data)!=count*RESULT_BYTES:raise ValueError('distance result size mismatch')
    rows=[]
    for index in range(count):
        ident,errors,lo,mid,hi,valid,reserved,fraction=struct.unpack_from('<8I',data,index*32)
        square=lo+(mid<<32)+(hi<<64)
        if ident!=index+1 or errors>255 or valid not in (0,1) or reserved or fraction!=32:
            raise ValueError('invalid distance result header/id/format')
        if not errors and (not valid or square>MAX_SQUARED):
            raise ValueError('invalid successful distance result')
        if errors and valid:raise ValueError('errored distance result marked valid')
        rows.append(dict(point_id=ident,errors=errors,distance_valid=bool(valid),
                         distance_squared_q32=square))
    return rows
