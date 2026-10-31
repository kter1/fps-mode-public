"""Repackage Godot MJPEG/PCM AVI into QuickTime for macOS avconvert.

No re-encoding or external Python packages. The original AVI is preserved.
Movie recording is scripted fixed-step capture, never FPS acceptance evidence.
"""
import struct, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def box(kind,payload):return struct.pack('>I4s',len(payload)+8,kind.encode())+payload
def full(kind,payload,flags=0):return box(kind,struct.pack('>I',flags)+payload)
def ints(*v):return struct.pack('>'+'I'*len(v),*v)
MATRIX=ints(65536,0,0,0,65536,0,0,0,1073741824)

def chunks(data,start,end):
    while start+8<=end:
        kind=data[start:start+4];size=struct.unpack_from('<I',data,start+4)[0];payload=start+8
        if size<=0 or payload+size>end:break
        if kind in [b'LIST',b'RIFF']:yield from chunks(data,payload+4,payload+size)
        else:yield kind,data[payload:payload+size]
        start=payload+size+(size%2)

def track(track_id,entry,handler,scale,duration,sizes,offset,delta,width=0,height=0,constant=0):
    movie_duration=round(duration*600/scale)
    tkhd=full('tkhd',ints(0,0,track_id,0,movie_duration)+b'\0'*8+struct.pack('>hhhh',0,0,256 if handler=='soun' else 0,0)+MATRIX+ints(width<<16,height<<16),7)
    mdhd=full('mdhd',ints(0,0,scale,duration)+b'\0'*4)
    hdlr=full('hdlr',ints(0)+handler.encode()+b'\0'*12+b'FPS Mode\0')
    stsd=full('stsd',ints(1)+entry)
    count=len(sizes)
    stts=full('stts',ints(1,count,delta));stsc=full('stsc',ints(1,1,count,1))
    stsz=full('stsz',ints(constant,count)+(b'' if constant else ints(*sizes)))
    stco=full('stco',ints(1,offset));stbl=box('stbl',stsd+stts+stsc+stsz+stco)
    dinf=box('dinf',full('dref',ints(1)+full('url ',b'',1)))
    media=full('vmhd',b'\0'*8,1) if handler=='vide' else full('smhd',b'\0'*4)
    return box('trak',tkhd+box('mdia',mdhd+hdlr+box('minf',media+dinf+stbl)))

def main():
    from dev import map_ids
    name=sys.argv[1] if len(sys.argv)>1 else map_ids()[0]
    source=ROOT/f'.artifacts/gameplay-{name}.avi';data=source.read_bytes()
    frames=[];audio=[];width=1280;height=720;rate=48000;channels=2;bits=16
    for kind,payload in chunks(data,0,len(data)):
        if kind==b'avih':width,height=struct.unpack_from('<II',payload,32)
        elif kind==b'strf' and len(payload)>=16 and struct.unpack_from('<H',payload)[0]==1:
            _,channels,rate,_,_,bits=struct.unpack_from('<HHIIHH',payload)
        elif kind[-2:] in [b'dc',b'db'] and payload.startswith(b'\xff\xd8'):frames.append(payload)
        elif kind.endswith(b'wb'):audio.append(payload)
    if not frames:raise RuntimeError('No MJPEG frames in AVI')
    ftyp=box('ftyp',b'qt  '+ints(0)+b'qt  ');video=b''.join(frames);sound=b''.join(audio);start=len(ftyp)+8
    # QuickTime visual sample entry (JPEG), 78-byte payload.
    compressor=b'Motion JPEG';name=bytes([len(compressor)])+compressor+b'\0'*(31-len(compressor))
    visual=b'\0'*6+struct.pack('>HHH',1,0,0)+b'appl'+ints(0,512)+struct.pack('>HH',width,height)+ints(72<<16,72<<16,0)+struct.pack('>H',1)+name+struct.pack('>Hh',24,-1)
    duration=len(frames)*10
    tracks=track(1,box('jpeg',visual),'vide',600,duration,[len(f) for f in frames],start,10,width,height)
    if sound:
        stride=channels*bits//8;samples=len(sound)//stride
        entry=b'\0'*6+struct.pack('>HHH',1,0,0)+ints(0)+struct.pack('>HHHHI',channels,bits,0,0,rate<<16)
        tracks+=track(2,box('sowt',entry),'soun',rate,samples,range(samples),start+len(video),1,constant=stride)
    mvhd=full('mvhd',ints(0,0,600,duration,65536)+struct.pack('>H',256)+b'\0'*10+MATRIX+b'\0'*24+ints(3))
    target=source.with_suffix('.mov');target.write_bytes(ftyp+box('mdat',video+sound)+box('moov',mvhd+tracks))
    print(target, len(frames),'frames /',len(sound),'PCM bytes')
if __name__=='__main__':main()
