"""Independent numeric vectors; no RTL arithmetic in the testbench."""
from pathlib import Path
import struct
import sys
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'src/host/python/pc_fpga_app'))
sys.path.insert(0, str(ROOT / 'src/host/python/bin_udp'))
from pc_fpga.ethernet.volume import transform
from src.io.fpga_volume_io import resample_int8

HERE = Path(__file__).resolve().parent
HERE.joinpath('vectors').mkdir(exist_ok=True)


def save(name, array, width):
    payload = np.asarray(array).tobytes() if not isinstance(array, bytes) else array
    HERE.joinpath('vectors', name+'.hex').write_text(''.join(
        int.from_bytes(payload[i:i+width], 'little').to_bytes(width, 'big').hex()+'\n'
        for i in range(0, len(payload), width)), encoding='ascii')


def generate():
    z,y,x = np.indices((2,512,512))
    volume = ((x*7+y*11+z*83)%256-128).astype(np.int8)
    save('volume', volume, 32)
    xq = (np.arange(512,dtype=np.uint32)*65536+32768)
    xq[-1]=511*65536
    yq = np.zeros(512, dtype=np.uint32)+32768
    zq = [0,32768,65536]
    commands=[];goldens=[]
    for orient in (0,1,2):
        commands.append(transform(2,orient,3,0,0x00400000,0x0a000000,2,512,512,0x08800000,0x08800800,zq))
        values=np.zeros((32,16),np.int8)
        for i in range(32):
            xx,yy=(i,0) if orient==0 else (0,i) if orient==1 else (511,511-i)
            qx,qy=int(xq[xx]),int(yq[yy])
            for c,qz in enumerate(zq):
                total=0
                for iz in (0,1):
                    for iy in (0,1):
                        for ix in (0,1):
                            wx=(qx&65535) if ix else 65536-(qx&65535)
                            wy=(qy&65535) if iy else 65536-(qy&65535)
                            wz=(qz&65535) if iz else 65536-(qz&65535)
                            total+=int(volume[min((qz>>16)+iz,1),min((qy>>16)+iy,511),min((qx>>16)+ix,511)])*wx*wy*wz
                whole,rem=divmod(abs(total),1<<48)
                whole+=rem>(1<<47) or rem==(1<<47) and whole%2
                values[i,c]=whole*(-1 if total<0 else 1)
        goldens.append(values.tobytes())
    save('xmap',xq.astype('<u4'),32);save('ymap',yq.astype('<u4'),32)
    save('commands',b''.join(commands),64);save('golden',b''.join(goldens),16)
    logits=np.full((512,512,8),-19,dtype='<i2')
    yy,xx=np.indices((512,512))
    for y0,x0 in zip(yy.ravel(),xx.ravel()):
        if (x0+y0)%7:
            logits[y0,x0,(x0+y0)%5]=(x0+y0)%13
            if (x0+y0)%3==0:logits[y0,x0,0]=(x0+y0)%13
    save('head',logits,32)
    labels=[];labels32=[];pack_commands=[]
    save('identity',np.arange(512,dtype='<u4'),32)
    for orient in (0,1,2):
        pack_commands.append(transform(3,orient,5,0,0x0a000000,0x10000000,2,512,512,0x08801000,0x08801000))
        row=[]
        for i in range(32):
            xx,yy=(i,0) if orient==0 else (0,i) if orient==1 else (511,511-i)
            v=logits[yy,xx,:5]
            row.append(0 if v.max()<0 else 1<<int(v.argmax()))
        labels32.append(np.array(row,dtype='<u2').tobytes())
        labels.append(np.array(row[:16],dtype='<u2').tobytes())
    save('pack_commands',b''.join(pack_commands),64);save('pack_golden',b''.join(labels),32)
    save('pack_golden32',b''.join(labels32),32)
    zz,yy,xx=np.indices((3,3,16))
    lobe_source = ((zz*71+yy*29+xx*13)%256-128).astype(np.int8)
    lobe_compact = resample_int8(lobe_source,(2,1,16))
    compact_rows=np.zeros((2,32),dtype=np.int8);compact_rows[:,:16]=lobe_compact[:,0,:]
    save('compact_volume',compact_rows,32)
    compact_commands=[];compact_expected=[]
    neighbor_sets=((0,0,1),(0,1,1),(1,0,0))
    for case,neighbors in enumerate(neighbor_sets):
        command=bytearray(64)
        struct.pack_into('<4B4I2H5I',command,0,4,(case&1)<<2,1,0,0x00600000,0x0a000000,
                         2,64,16,1,32,32,*neighbors)
        compact_commands.append(bytes(command))
        pixels=np.zeros((32,16),dtype=np.int8)
        for x in range(32):
            if 8<=x<24:
                sx=x-8
                pixels[x,:3]=lobe_compact[np.asarray(neighbors),0,sx]
            else:
                pixels[x,:3]=np.int8(-128)
        compact_expected.append(pixels.tobytes())
    save('compact_commands',b''.join(compact_commands),64)
    save('compact_golden',b''.join(compact_expected),16)
    descriptor=bytearray(64)
    struct.pack_into('<BBBBHHH',descriptor,0,7,0,0,0,16,1,1)
    struct.pack_into('<I',descriptor,16,0x0a000000)
    struct.pack_into('<I',descriptor,24,0x0a400000)
    gather=bytearray(commands[0]);gather[2]=5
    pack=bytearray(pack_commands[0]);struct.pack_into('<I',pack,4,0x0a800000)
    records=b''.join(bytes([k])+bytes(31)+bytes(c) for k,c in ((2,gather),(1,descriptor),(3,pack),(255,bytes(64))))
    save('scheduler',records,32)
    a=np.frombuffer(goldens[0],np.int8).reshape(32,16)[:16]
    save('shuffle_golden',a.reshape(16,2,8).transpose(0,2,1).copy(),32)
    print('[VECTORS] VOL1 gather/classify plus VOL2 Q16-RNE compact planes, boundary repeats, stride and -128 padding')


if __name__=='__main__':generate()

