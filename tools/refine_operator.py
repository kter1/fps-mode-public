"""Preserve the original tested animation rig while refining its mesh data.

Smooth surface normals directly in the original GLB. The original skin binds,
geometry, UVs and 24 animation clips remain intact. No Blender runtime needed.
"""
import json, math, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
WIDTH={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
FORMAT={5121:'B',5123:'H',5125:'I',5126:'f'}

def load(path):
    data=path.read_bytes();length=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+length]),bytearray(data[28+length:])

def values(doc,data,index):
    a=doc['accessors'][index];view=doc['bufferViews'][a['bufferView']]
    fmt='<'+FORMAT[a['componentType']]*WIDTH[a['type']];size=struct.calcsize(fmt)
    offset=view.get('byteOffset',0)+a.get('byteOffset',0)
    return [list(struct.unpack_from(fmt,data,offset+i*view.get('byteStride',size))) for i in range(a['count'])]

def append(doc,data,rows,kind,component=5126):
    while len(data)%4:data.append(0)
    offset=len(data);fmt='<'+FORMAT[component]*WIDTH[kind]
    for row in rows:data.extend(struct.pack(fmt,*row))
    doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(data)-offset})
    entry={'bufferView':len(doc['bufferViews'])-1,'componentType':component,'count':len(rows),'type':kind}
    if component==5126:entry.update(min=[min(r[i] for r in rows) for i in range(WIDTH[kind])],max=[max(r[i] for r in rows) for i in range(WIDTH[kind])])
    doc['accessors'].append(entry);return len(doc['accessors'])-1

def main():
    doc,data=load(ROOT/'content/models/soldier.glb')
    # Smooth coincident vertices without changing positions, UVs, bones or clips.
    for mesh in doc['meshes']:
        sums={}
        for p in mesh['primitives']:
            pos=values(doc,data,p['attributes']['POSITION']);norm=values(doc,data,p['attributes']['NORMAL'])
            for v,n in zip(pos,norm):
                key=tuple(round(x,7) for x in v);s=sums.setdefault(key,[0.,0.,0.])
                for i in range(3):s[i]+=n[i]
        for p in mesh['primitives']:
            normals=[]
            for v in values(doc,data,p['attributes']['POSITION']):
                n=sums[tuple(round(x,7) for x in v)];length=math.sqrt(sum(x*x for x in n));normals.append([x/max(length,1e-9) for x in n])
            p['attributes']['NORMAL']=append(doc,data,normals,'VEC3')
    for material in doc['materials']:material.setdefault('pbrMetallicRoughness',{})['roughnessFactor']=.88
    doc['buffers'][0]['byteLength']=len(data)
    encoded=json.dumps(doc,separators=(',',':')).encode()
    encoded+=b' '*((-len(encoded))%4);data+=b'\0'*((-len(data))%4)
    output=struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(data))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(data),b'BIN\0')+data
    (ROOT/'content/models/realism/operator_combat.glb').write_bytes(output)
    print('Operator geometry refined; original rig and',len(doc['animations']),'clips preserved')
if __name__=='__main__':main()
