"""Map surfaces are photoscanned CC0 scans fetched by `python3 tools/dev.py fetch
--domain maps` (see content/asset_sources/maps.json), so generate() writes nothing.
The PNG and value-noise helpers remain because tools/generate_fabric.py uses them.
"""
from pathlib import Path
import struct, zlib
SIZE=384

def png(path, data):
    def chunk(kind, value):
        return struct.pack('>I',len(value))+kind+value+struct.pack('>I',zlib.crc32(kind+value)&0xffffffff)
    raw=b''.join(b'\0'+bytes(data[y*SIZE*3:(y+1)*SIZE*3]) for y in range(SIZE))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',SIZE,SIZE,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,8))+chunk(b'IEND',b''))

def field(rng, grid):
    lattice=[rng.random() for _ in range(grid*grid)]
    output=[]
    for y in range(SIZE):
        fy=y/SIZE*grid;iy=int(fy);v=fy-iy;v=v*v*(3-2*v)
        for x in range(SIZE):
            fx=x/SIZE*grid;ix=int(fx);u=fx-ix;u=u*u*(3-2*u)
            a=lattice[(iy%grid)*grid+ix%grid];b=lattice[(iy%grid)*grid+(ix+1)%grid]
            c=lattice[((iy+1)%grid)*grid+ix%grid];d=lattice[((iy+1)%grid)*grid+(ix+1)%grid]
            output.append((a+(b-a)*u)*(1-v)+(c+(d-c)*u)*v)
    return output

def generate(root: Path) -> None:
    return None
