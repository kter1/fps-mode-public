"""Original deterministic Zombies sound design; no external recordings."""
from pathlib import Path
import math, random, struct, wave
ROOT=Path(__file__).resolve().parents[1]
NAMES=['round_start','round_end','z_attack','z_death','z_groan','board_tear','board_repair','leg_break','box_roll','box_claim','box_move','power','perk','down','revive','upgrade','trap','pickup','purchase','denied','z_ray','z_thunder','z_arc','knife_hit']
def generate():
    directory=ROOT/'content/audio/zombies';directory.mkdir(exist_ok=True)
    for index,name in enumerate(NAMES):
        rng=random.Random(7100+index);rate=22050
        duration=1.4 if name in ['round_start','round_end','box_roll','power','z_groan'] else .45
        samples=[];filtered=0
        for n in range(int(rate*duration)):
            t=n/rate;noise=rng.uniform(-1,1);filtered=filtered*.82+noise*.18
            if name.startswith('z_') and name not in ['z_ray','z_arc','z_thunder']:
                f=57+index*2+math.sin(t*9)*8
                value=(math.sin(math.tau*f*t)*.3+filtered*.8)*math.sin(math.pi*t/duration)**.5
            elif name in ['board_tear','board_repair','leg_break','z_thunder','knife_hit']:
                value=(filtered*.8+noise*.2+math.sin(t*math.tau*72)*.25)*math.exp(-t*10)
            else:
                f=140+index*19
                if name in ['round_start','pickup','perk','upgrade']:f*=2**(int(t*6)%4/4)
                if name=='box_roll':f=180+int(t*12)%9*55
                value=(math.sin(math.tau*f*t)*.23+math.sin(math.tau*f*1.5*t)*.1+filtered*.2)*min(1,t*45)*math.exp(-t*2.5)
            samples.append(struct.pack('<h',int(max(-.9,min(.9,value))*26000)))
        with wave.open(str(directory/(name+'.wav')),'wb') as out:
            out.setnchannels(1);out.setsampwidth(2);out.setframerate(rate);out.writeframes(b''.join(samples))
    print(f'Generated {len(NAMES)} original Zombies cues')
if __name__=='__main__':generate()
