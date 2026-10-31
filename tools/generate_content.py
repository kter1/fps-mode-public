"""Generate original game resources and deterministic layered audio."""
import json, math, random, struct, wave

ROWS = [
 ("ar_a4","A4 Carbine","assault",28,700,30,2.2,"AssaultRifle_4"),
 ("ar_k47","K47 Rifle","assault",31,600,30,2.5,"AssaultRifle2_1"),
 ("ar_b56","B56 Bullpup","assault",25,850,30,2.4,"Bullpup_1"),
 ("smg_mp9","MP9 Compact","smg",23,800,30,1.9,"SubmachineGun_1"),
 ("smg_v45","V45 Rapid","smg",19,1100,25,2.0,"SubmachineGun_2"),
 ("smg_p90","P90 PDW","smg",21,950,50,2.6,"SubmachineGun_3"),
 ("sg_p12","P12 Pump","shotgun",14,70,8,.6,"Shotgun_1"),
 ("sg_a12","A12 Tactical","shotgun",12,150,8,2.7,"Shotgun_2"),
 ("lmg_l56","L56 Support","lmg",23,750,75,4.2,"AssaultRifle_4"),
 ("lmg_l762","L762 Support","lmg",30,600,60,3.8,"AssaultRifle2_4"),
 ("dmr_d14","D14 Marksman","marksman",56,240,20,2.6,"SniperRifle_2"),
 ("sniper_s90","S90 Precision","sniper",90,50,5,3.0,"SniperRifle_1"),
 ("pistol_p9","P9 Duty","sidearm",30,360,17,1.5,"Pistol_1"),
 ("pistol_p45","P45 Combat","sidearm",38,300,12,1.7,"Pistol_2"),
 ("pistol_r357","R357 Revolver","sidearm",55,180,6,2.8,"Revolver_1")]
DEFAULTS = {
 "assault":(.22,25,80,.6,2.4,.12,1.0), "smg":(.16,15,45,.6,3,.2,.65),
 "shotgun":(.24,8,25,.2,6,3.5,2.6), "lmg":(.32,35,90,.6,3.2,.18,1.25),
 "marksman":(.28,60,140,.75,2.5,.04,2.1), "sniper":(.38,100,200,.85,5,.015,3.8),
 "sidearm":(.14,15,50,.6,2,.15,1.5)}
ATTACHMENTS = [
 ("reflex","optic","Red dot sight","1.3× sight · +10ms aim",{"magnification":1.3,"ads_add":.01}),
 ("holographic","optic","Holographic sight","1.5× ring / dot · +20ms aim",{"magnification":1.5,"ads_add":.02}),
 ("scope","optic","3× Scope","3× sight · +50ms aim",{"magnification":3.,"ads_add":.05}),
 ("compensator","muzzle","Compensator","−20% recoil · +15ms aim",{"recoil":.8,"ads_add":.015}),
 ("suppressor","muzzle","Suppressor","Quieter shots · −15% range",{"hearing":.45,"range":.85}),
 ("extended","magazine","Extended magazine","+40% capacity · slower reload / aim",{"capacity":1.4,"reload":1.15,"ads_add":.025}),
 ("fast","magazine","Fast magazine","−20% reload time · −15% capacity",{"capacity":.85,"reload":.8}),
 ("vertical","grip","Vertical grip","−15% vertical recoil · +20ms aim",{"recoil":.85,"ads_add":.02}),
 ("angled","grip","Angled grip","−15% aim time · +15% hip spread",{"ads":.85,"hip":1.15})]

def resource(path, script, values):
    lines = ['[gd_resource type="Resource" script_class="'+script[1]+'" load_steps=2 format=3]', '', '[ext_resource type="Script" path="res://'+script[0]+'" id="1"]', '', '[resource]', 'script = ExtResource("1")']
    for key, value in values.items():
        literal = ('true' if value else 'false') if isinstance(value,bool) else json.dumps(value,ensure_ascii=False)
        lines.append(f'{key} = {literal}')
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text('\n'.join(lines)+'\n')

def audio(path, seed, kind, variant=0, force=False):
    if path.exists() and not force: return
    rng=random.Random(seed+variant)
    rate=22050
    duration={'reload':.55,'step':.18,'step_gravel':.2,'step_metal':.25,'click':.08,'switch':.18,'casing':.3,'impact':.12}.get(kind,.27)
    samples=[]; filtered=0.
    pitch={'assault':105,'smg':150,'shotgun':65,'lmg':82,'marksman':90,'sniper':58,'sidearm':135}.get(kind,240)
    for i in range(int(rate*duration)):
        t=i/rate; noise=rng.uniform(-1,1); filtered=filtered*.68+noise*.32
        if kind=='reload':
            envelope=sum(math.exp(-max(0,t-p)*65) if t>=p else 0 for p in [.0,.12,.32,.48]); value=(filtered*.7+math.sin(t*2400)*.12)*envelope*.4
        elif kind in ['step','step_gravel','step_metal']:
            # Cushioned heel then a quieter sole scuff. No pitched metal ping or
            # instantaneous noise spike; each variant varies the heel/toe timing.
            attack=1-math.exp(-t*650)
            heel=attack*math.exp(-t*38)
            toe=max(0,t-(.032+variant*.003))
            scuff=(1-math.exp(-toe*180))*math.exp(-toe*40)
            value=filtered*(heel*.42+scuff*.22)
            value+=math.sin(2*math.pi*(66+variant*3)*t)*heel*.065
            if kind=='step_gravel':value+=noise*scuff*.055
            if kind=='step_metal':value+=filtered*scuff*.08
            value*=min(1,(duration-t)/.025)
        elif kind in ['switch','impact','casing']:
            value=(filtered*.6+math.sin(t*2*math.pi*1800)*.3)*math.exp(-t*({'switch':35,'impact':55,'casing':18}[kind]))
        elif kind=='click': value=filtered*math.exp(-t*100)*.5
        else:
            value=noise*.55*math.exp(-t*90)+math.sin(2*math.pi*pitch*t)*.55*math.exp(-t*24)+filtered*.45*math.exp(-t*14)
        samples.append(struct.pack('<h',int(max(-.95,min(.95,value)) * 32767)))
    path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),'wb') as out:
        out.setnchannels(1);out.setsampwidth(2);out.setframerate(rate);out.writeframes(b''.join(samples))

def generate(root):
    # Prepared weapon models and their display names come from the weapons pipeline.
    manifest=root/'content/manifest/weapons.json'
    prepared_weapons=json.loads(manifest.read_text()).get('weapons',{}) if manifest.exists() else {}
    for idx,row in enumerate(ROWS):
        wid,name,category,damage,rpm,capacity,reload,model=row
        ads,start,end,minimum,hip,spread,recoil=DEFAULTS[category]
        values=dict(id=wid,display_name=name,category=category,automatic=category in ['assault','smg','lmg'],damage=float(damage),rpm=float(rpm),capacity=capacity,reload_seconds=reload,pellets=9 if wid=='sg_p12' else (8 if wid=='sg_a12' else 1),shell_reload=wid=='sg_p12',ads_seconds=ads,range_start=float(start),range_end=float(end),min_damage=minimum,hip_spread=hip,ads_spread=spread,recoil=recoil,model_path='res://content/models/'+model+'.glb',audio_path='res://content/audio/'+category+'_0.wav')
        prepared=root/'content/models/realism'/(wid+'.glb')
        if wid in prepared_weapons:values['model_path']=prepared_weapons[wid]['model'];values['display_name']=prepared_weapons[wid]['display_name']
        elif prepared.exists():values['model_path']='res://content/models/realism/'+wid+'.glb'
        resource(root / ('content/data/weapons/'+wid+'.tres'),('game/combat/weapon_definition.gd','WeaponDefinition'),values)
    for aid,slot,name,description,modifiers in ATTACHMENTS:
        resource(root / ('content/data/attachments/'+aid+'.tres'),('game/combat/attachment_definition.gd','AttachmentDefinition'),dict(id=aid,slot=slot,display_name=name,description=description,modifiers=modifiers))
    for idx,kind in enumerate(list(DEFAULTS)+['reload','step','click','switch','casing','impact','step_gravel','step_metal']):
        for variant in range(4): audio(root / f'content/audio/{kind}_{variant}.wav',idx*73,kind,variant)
    print('Generated 15 weapons, 9 attachments, 60 original audio clips',flush=True)

if __name__=='__main__':
    from pathlib import Path
    generate(Path(__file__).resolve().parents[1])
