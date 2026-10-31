#!/usr/bin/env python3
"""Assemble actual release evidence; absent or failed gates remain incomplete."""
import csv, datetime, json, math, plistlib, struct, subprocess
from pathlib import Path
from dev import build_fingerprint, map_ids

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'.artifacts'

def read(path):
    path=Path(path)
    return json.loads(path.read_text()) if path.exists() else {}

def main():
    checks=[]
    def gate(name, passed, evidence):checks.append({'name':name,'passed':bool(passed),'evidence':evidence})
    tests={suite:read(ART/'reports'/f'{suite}.json') for suite in ['content','core','integration','graphics','replay','audio','zombies']}
    for suite,minimum in [('content',70),('core',30),('integration',78),('graphics',30)]:
        result=tests[suite]
        gate(suite,result.get('failed',1)==0 and result.get('passed',0)>=minimum,f"{result.get('passed',0)} passed / {result.get('failed','unavailable')} failed")
    replay=read(ART/'reports/replay.json')
    gate('killer_replay',replay.get('failed',1)==0 and replay.get('passed',0)>=8,replay)
    gate('test_harness_exit_code',read(ART/'reports/harness-exit.json').get('passed'),'.artifacts/reports/harness-exit.json')
    maps=map_ids("tdm")
    matches={name:read(ART/f'match-{name}-swapped.json') for name in maps}
    for name,result in matches.items():gate('swapped_match_'+name,result.get('passed') and result.get('slots')==16,result)
    for name in maps:
        cleanup=read(ART/f'render-cleanup-{name}.json')
        gate('rendered_cleanup_'+name,cleanup.get('passed') and cleanup.get('rounds')==3,cleanup)
    smoke=read(ART/'export-smoke.json')
    gate('exported_controls_and_flow',smoke.get('content_build_sha256')==build_fingerprint() and smoke.get('passed') and len(smoke.get('steps',[]))==20 and 'keyboard_fire_while_aimed' in smoke.get('steps',[]) and 'shift_sprint_binding' in smoke.get('steps',[]),smoke)
    gate('export_matches_source',read(ART/'export-build.json').get('content_build_sha256')==build_fingerprint(),'.artifacts/export-build.json')
    app=ROOT/'builds/FPSMode.app'
    signature=subprocess.run(['codesign','--verify','--deep','--strict',str(app)],capture_output=True,text=True) if app.exists() else None
    gate('signature',signature is not None and signature.returncode==0,'codesign --verify --deep --strict builds/FPSMode.app')
    if app.exists():
        with (app/'Contents/Info.plist').open('rb') as f:metadata=plistlib.load(f)
        gate('bundle_id',metadata.get('CFBundleIdentifier')=='local.fpsmode.game',metadata.get('CFBundleIdentifier'))
    benchmarks={}
    for name in [*maps,*[name+'-stress' for name in maps]]:
        result=read(ART/f'benchmark-{name}.json');benchmarks[name]=result
        seconds=60 if name.endswith('stress') else 600
        gate('rendering_'+name,result.get('passed') and result.get('source_unchanged') and result.get('measured_seconds',0)>=seconds-.05 and result.get('internal_resolution')==[1920,1080] and result.get('slots')==16 and result.get('vsync_mode')==0 and result.get('frame_cap')==0,result)
        path=ART/f'benchmark-{name}.csv'
        intervals=[]
        if path.exists():
            with path.open() as f:intervals=[float(row['interval_ms']) for row in csv.DictReader(f)]
        if intervals:
            ordered=sorted(intervals);fps=len(intervals)/(sum(intervals)/1000)
            p95=ordered[math.ceil(len(ordered)*.95)-1];p99=ordered[math.ceil(len(ordered)*.99)-1]
            gate('raw_csv_'+name,len(intervals)==result.get('sample_frames') and abs(fps-result.get('average_fps',0))<.001 and abs(p95-result.get('p95_ms',0))<.001 and abs(p99-result.get('p99_ms',0))<.001,{'frames':len(intervals),'fps':fps,'p95_ms':p95,'p99_ms':p99})
        else:gate('raw_csv_'+name,False,'No raw frame intervals')
        if not name.endswith('stress'):
            gate('contact_time_'+name,5<=result.get('contact_median',-1)<=20,result.get('contact_median','unavailable'))
            gate('full_round_'+name,len(result.get('completed_rounds',[]))>0,result.get('completed_rounds',[]))
    for index,name in enumerate(map_ids("zombies")):
        seed=2601+index
        for scenario in ['capture','render-cleanup','match-test','smoke-export','benchmark']:
            path=ART/f'{scenario}-zombies-{name}-{seed}.json'
            evidence=read(path)
            gate(f'zombies_{scenario}_{name}',evidence.get('passed') and evidence.get('content_build_sha256')==build_fingerprint(),evidence)
        gate('zombies_visuals_'+name,all((ART/'screenshots/zombies'/name/(shot+'.png')).exists() for shot in ['start','window','crawler','box','perk','wonder']),'.artifacts/screenshots/zombies/'+name)
    for suite in ['audio','zombies']:
        evidence=tests[suite]
        gate(suite,evidence.get('failed',1)==0 and evidence.get('passed',0)>0,evidence)
    fingerprint=build_fingerprint()
    gate('one_verified_content_build',all(b.get('content_build_sha256')==fingerprint for b in benchmarks.values()),fingerprint)
    expected=['blue_spawn','red_spawn','north_route','center_interior','south_route','elevated','ads','reload','firefight','smoke_outside','smoke_inside','loadout','hud_720p']
    screenshots=[]
    for name in maps:
        valid=True
        for shot in expected:
            path=ART/'screenshots'/name/(shot+'.png')
            valid=valid and path.exists()
            if path.exists():
                width,height=struct.unpack('>II',path.read_bytes()[16:24]);valid=valid and (width,height)==(1280,720)
                screenshots.append(str(path.relative_to(ROOT)))
        gate('captures_'+name,valid,13)
    visual=read(ART/'visual-review.json')
    gate('optic_ads_captures',all((ART/'screenshots/optics'/(name+'.png')).exists() for name in ['bare','reflex','holographic','scope']),'Bare / red dot / holographic / 3× ADS views')
    gate('visual_review',visual.get('passed') and visual.get('content_build_sha256')==fingerprint,visual)
    probes={driver:read(ART/'probes'/('presentation-'+driver+'.json')) for driver in ['vulkan','metal']}
    result={'generated_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'release_acceptance_passed':all(c['passed'] for c in checks),'hardware':{'cpu':'Apple M2','gpu':'Apple M2','memory_gib':16,'cpu_cores':8,'os':'macOS 26.6.2'},'engine':'Godot 4.7.2 standard / ed1daf0bf','checks':checks,'tests':tests,'benchmarks':benchmarks,'swapped_matches':matches,'screenshots':screenshots,'presentation_diagnostics':probes,'human_playtest':False,'regression_notes':read(ART/'diagnostics/findings.json')}
    ART.mkdir(exist_ok=True)
    (ART/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
    lines=['# FPS Mode validation','',f"Generated {result['generated_utc']}",'',('Release acceptance gates passed.' if result['release_acceptance_passed'] else 'Release acceptance is incomplete; failed or unavailable gates are listed below.'),'','Tested on Apple M2, 8 CPU cores, 16 GiB memory, macOS 26.6.2. Godot 4.7.2 standard (ed1daf0bf), Forward+ / Vulkan.','',f"Automated assertions: {sum(t.get('passed',0) for t in tests.values())} passed; {sum(t.get('failed',0) for t in tests.values())} failed.",'','| Scenario | Measured seconds | Average FPS | p95 ms | p99 ms | >50 ms frames | Contact median |','|---|---:|---:|---:|---:|---:|---:|']
    for name,b in benchmarks.items():
        if b:lines.append(f"| {name} | {b.get('measured_seconds',0):.2f} | {b.get('average_fps',0):.2f} | {b.get('p95_ms',0):.2f} | {b.get('p99_ms',0):.2f} | {b.get('frames_over_50ms','—')} | {b.get('contact_median',0):.2f}s |")
    lines += ['', 'Acceptance uses these rendered game measurements, including frame stalls. Diagnostic runs and trimmed frame distributions do not substitute for the required tests. Targets remain average FPS ≥60, p95 ≤20 ms and p99 ≤33.3 ms.']
    lines += ['','Rendered runs use 1920×1080 internal world resolution at Medium, 30 seconds warm-up, normal simulation speed, VSync disabled, no frame cap, and 16 stable roster slots. CSV files preserve every measured frame interval. Headless matches omit presentation meshes and audio, and are gameplay checks only. Swapped-side runs are accelerated physics checks, not rendering measurements.','', 'The automated player follows authored routes and uses the shared movement and weapon systems. These are scripted tests, not human playtests.','', 'The lightmap editor emits retained native teardown diagnostics after saving its baked textures. Content checks verify actual lightmap texture arrays. Runtime test/capture/export logs are checked separately for script and engine errors.','', '## Gates','', '| Check | Result |','|---|---|']
    for check in checks:lines.append(f"| {check['name']} | {'PASS' if check['passed'] else 'FAIL / UNAVAILABLE'} |")
    lines += ['','## Evidence','', '- `.artifacts/validation.json`: complete machine-readable results.', '- `.artifacts/reports/`: named assertions and deliberate failure exit-code check.', '- `.artifacts/benchmark-*.csv` and `.json`: raw intervals and measured results.', '- `.artifacts/screenshots/`: map, HUD, smoke, reload, loadout, and weapon inspections.', '- `.artifacts/visual-review.json`: inspected images, hashes and visual limits.', '- `.artifacts/export-smoke.json` and `logs/export-smoke.log`: native packaged controls/flow.', '- `.artifacts/match-*-swapped.json`: full matches with exchanged starting sides.','', 'The local bundle uses ad-hoc signing. Public notarization and multiplayer are outside this release. Competitive balance still needs human playtesting. Architecture and first-person hands remain below AAA photorealistic quality; some firearm variants share meshes. The killer replay reconstructs sampled poses and weapons, without rewinding every particle or ragdoll.']
    notes=result['regression_notes']
    if notes:
        lines += ['', '## 8v8 regression pass', '', 'Original snapshot: `'+notes.get('original_commit','')+'`. Verification base: `'+notes.get('verification_base','')+'`.', '', notes.get('scope','')]
        if notes.get('artifact_archive'):lines += ['', 'Archived evidence for this pass: `'+notes['artifact_archive']+'`. Paths in the evidence list refer to files inside that archive.']
        for group in ['resolved','remaining','measurement_notes']:
            lines += ['', group.replace('_',' ').title()+':', '']
            lines += ['- '+item for item in notes.get(group,[])]
    document='\n'.join(lines)+'\n'
    (ART/'VALIDATION.md').write_text(document)
    (ROOT/'VALIDATION.md').write_text(document)
    print('ACCEPTANCE', 'PASS' if result['release_acceptance_passed'] else 'INCOMPLETE')
    for check in checks:
        if not check['passed']:print('UNRESOLVED',check['name'])

if __name__=='__main__':main()
