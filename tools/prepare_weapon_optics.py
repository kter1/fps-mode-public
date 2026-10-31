"""Remove the source D14's permanent optic so loadout sights remain swappable.

The pinned Dragunov source has disconnected scope/turret/mount components. Use
their inspected bounds, preserving receiver, front/rear iron sights and UVs.
This is an offline mesh preparation step, not runtime geometry work.
"""
import collections,json,struct
from pathlib import Path
from refine_operator import load,values,append

def prepare(path):
    doc,data=load(path);parents={};points={}
    def find(a):
        parents.setdefault(a,a)
        while parents[a]!=a:parents[a]=parents[parents[a]];a=parents[a]
        return a
    def union(a,b):parents[find(a)]=find(b)
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            vs=values(doc,data,p['attributes']['POSITION']);ix=[r[0] for r in values(doc,data,p['indices'])];keys=[tuple(round(x,6) for x in v) for v in vs]
            for k,v in zip(keys,vs):points[k]=v
            for i in range(0,len(ix),3):union(keys[ix[i]],keys[ix[i+1]]);union(keys[ix[i]],keys[ix[i+2]])
    groups=collections.defaultdict(list)
    for key,point in points.items():groups[find(key)].append(point)
    removed=set()
    for group,vertices in groups.items():
        lo=[min(v[a] for v in vertices) for a in range(3)];hi=[max(v[a] for v in vertices) for a in range(3)]
        optic=lo[1]>.048 and lo[2]>.06
        bracket=lo[0]<-.009 and hi[0]<-.008 and lo[2]>.13 and hi[2]<.215 and hi[1]>.06
        if optic or bracket:removed.add(group)
    if len(removed)!=8:raise RuntimeError('Pinned D14 optic components changed: '+str(len(removed)))
    for mesh in doc['meshes']:
        primitives=[]
        for p in mesh['primitives']:
            vs=values(doc,data,p['attributes']['POSITION']);ix=[r[0] for r in values(doc,data,p['indices'])];kept=[]
            for i in range(0,len(ix),3):
                if find(tuple(round(x,6) for x in vs[ix[i]])) not in removed:kept.extend(ix[i:i+3])
            if not kept:continue
            used=sorted(set(kept));remap={old:new for new,old in enumerate(used)}
            for name,index in list(p['attributes'].items()):
                a=doc['accessors'][index];rows=values(doc,data,index)
                p['attributes'][name]=append(doc,data,[rows[i] for i in used],a['type'],a['componentType'])
            p['indices']=append(doc,data,[[remap[i]] for i in kept],'SCALAR',5125);primitives.append(p)
        mesh['primitives']=primitives
    doc['buffers'][0]['byteLength']=len(data);encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);data+=b'\0'*((-len(data))%4)
    path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(data))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(data),b'BIN\0')+data)
    print('D14: removed 8 permanent optic/mount components; iron sights preserved')

if __name__=='__main__':prepare(Path(__file__).resolve().parents[1]/'content/models/realism/dmr_d14.glb')
