"""Original woven camouflage texture for operator uniforms, no external images."""
from pathlib import Path
import random,math
from generate_surfaces import SIZE,field,png

def generate(root):
 r=random.Random(339);large=field(r,12);small=field(r,38);albedo=bytearray();normal=bytearray()
 for y in range(SIZE):
  for x in range(SIZE):
   i=y*SIZE+x;pattern=large[i]*.8+small[i]*.2
   value=.45 if pattern<.42 else (.68 if pattern<.56 else .9)
   weave=(.025 if x%4<2 else -.025)+(.02 if y%4<2 else -.02)
   albedo.extend([max(0,min(255,int((value+weave)*255)))]*3)
   normal.extend([118 if x%4<2 else 138,118 if y%4<2 else 138,253])
 folder=root/'content/materials';png(folder/'fabric_albedo.png',albedo);png(folder/'fabric_normal.png',normal)
 print('Generated woven operator camouflage',flush=True)
if __name__=='__main__':generate(Path(__file__).resolve().parents[1])
