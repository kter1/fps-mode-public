#!/usr/bin/env python3
"""Run release verification sequentially so rendered measurements do not compete."""
import argparse, json, subprocess, sys, time
from pathlib import Path
from dev import map_ids

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'.artifacts'

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--benchmarks-only',action='store_true')
    parser.add_argument('--skip-benchmarks',action='store_true')
    parser.add_argument('--keep-going',action='store_true',help='Collect remaining evidence even if an acceptance threshold fails')
    parser.add_argument('--stage',action='append',help='Run only the named stages')
    args=parser.parse_args()
    (ART/'logs').mkdir(parents=True,exist_ok=True)
    status_path=ART/'release-status.json'
    status=json.loads(status_path.read_text()) if status_path.exists() else {'stages':{}}
    stages=[]
    if not args.benchmarks_only:
        # Per-map stages run for every registered map; each map gets its own seed (1201, 1202, ...).
        maps=[(name,str(1201+index)) for index,name in enumerate(map_ids("tdm"))]
        stages += [('check',['check']),('core',['test','--suite','core']),('audio',['test','--suite','audio']),('zombies',['test','--suite','zombies']),('integration',['test','--suite','integration']),('graphics',['graphics-check']),('replay',['inspect-replay'])]
        stages += [('render-cleanup-'+name,['render-cleanup','--map',name]) for name,_ in maps]
        stages += [('swap-'+name,['match-test','--map',name,'--seed',seed,'--swap']) for name,seed in maps]
        stages += [('arsenal',['inspect-arsenal']),('optics',['inspect-optics']),('operators',['inspect-operators'])]
        stages += [('overview-'+name,['inspect-map','--map',name]) for name,_ in maps]
        stages += [('capture-'+name,['capture','--map',name]) for name,_ in maps]
        stages += [('capture-zombies-'+name,['capture','--mode','zombies','--map',name,'--seed',str(2601+i)]) for i,name in enumerate(map_ids("zombies"))]
        stages += [('cleanup-zombies-'+name,['render-cleanup','--mode','zombies','--map',name,'--seed',str(2601+i)]) for i,name in enumerate(map_ids("zombies"))]
        stages += [('rounds-zombies-'+name,['match-test','--mode','zombies','--map',name,'--seed',str(2601+i)]) for i,name in enumerate(map_ids("zombies"))]
        stages += [('export',['export']),('smoke-export',['smoke-export'])]
        stages += [('smoke-export-zombies-'+name,['smoke-export','--mode','zombies','--map',name,'--seed',str(2601+i)]) for i,name in enumerate(map_ids("zombies"))]
    if not args.skip_benchmarks:
        maps=[(name,str(1201+index)) for index,name in enumerate(map_ids("tdm"))]
        stages += [('benchmark-'+name,['benchmark','--map',name,'--seed',seed,'--seconds','600']) for name,seed in maps]
        stages += [('stress-'+name,['benchmark','--map',name,'--seed',seed,'--seconds','60','--stress']) for name,seed in maps]
    if not args.skip_benchmarks:
        stages += [('benchmark-zombies-'+name,['benchmark','--mode','zombies','--map',name,'--seed',str(2601+i),'--seconds','600']) for i,name in enumerate(map_ids("zombies"))]
    if args.stage:stages=[stage for stage in stages if stage[0] in args.stage]
    failures=[]
    for name,command in stages:
        print('START',name,flush=True)
        started=time.time()
        status['active']=name;status_path.write_text(json.dumps(status,indent=2))
        log=ART/'logs'/('release-'+name+'.console.log')
        with log.open('w') as output:
            result=subprocess.run([sys.executable,'tools/dev.py',*command],cwd=ROOT,stdout=output,stderr=subprocess.STDOUT)
        status['stages'][name]={'exit_code':result.returncode,'seconds':round(time.time()-started,2),'log':str(log.relative_to(ROOT))}
        status_path.write_text(json.dumps(status,indent=2))
        print('PASS' if result.returncode==0 else 'FAIL',name,flush=True)
        if result.returncode:
            failures.append(name)
            print(log.read_text(errors='replace')[-6000:],flush=True)
            if not args.keep_going:sys.exit(result.returncode)
    status['active']=None
    status_path.write_text(json.dumps(status,indent=2))
    print('VERIFICATION STAGES COMPLETE; FAILURES: '+(', '.join(failures) if failures else 'none'),flush=True)
    if failures:sys.exit(1)

if __name__=='__main__':main()
