#!/usr/bin/env python3
"""Produce the free, local Dead Circuit audition. Never calls a paid API."""
from __future__ import annotations
import argparse
import gc
import hashlib
import json
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
os.environ.setdefault('HF_HOME', str(ROOT / '.tools/voice-audition/huggingface'))
os.environ.setdefault('HF_HUB_DISABLE_TELEMETRY', '1')
SCRIPT = ROOT / 'auditions/dead_circuit/script.json'
OUT = ROOT / '.artifacts/voice-audition/dead-circuit'


def read_script():
    return json.loads(SCRIPT.read_text())


def measure(audio, sr):
    import numpy as np
    a = np.asarray(audio, dtype=np.float32)
    return {'seconds': round(len(a)/sr, 4), 'sample_rate': sr,
            'peak_dbfs': round(float(20*np.log10(max(float(np.max(np.abs(a))), 1e-12))), 2),
            'rms_dbfs': round(float(20*np.log10(max(float(np.sqrt(np.mean(a*a))), 1e-12))), 2),
            'finite': bool(np.isfinite(a).all()), 'clipped_samples': int((np.abs(a)>=1).sum())}


def trim_edges(a, sr):
    import numpy as np
    # Trim only quiet boundaries; preserve breaths and internal pauses.
    hop = max(1, int(sr*.01))
    rms = np.array([np.sqrt(np.mean(a[i:i+hop]**2)) for i in range(0,len(a),hop)])
    speech = np.flatnonzero(rms > max(.001, float(rms.max())*.012))
    if len(speech):
        a = a[max(0,int(speech[0]*hop-sr*.12)):min(len(a),int((speech[-1]+1)*hop+sr*.2))].copy()
    fade = min(int(sr*.008),len(a)//2)
    if fade:
        a[:fade]*=np.linspace(0,1,fade);a[-fade:]*=np.linspace(1,0,fade)
    return a


def generate(args):
    import numpy as np
    import soundfile as sf
    import mlx.core as mx
    from mlx_audio.tts.utils import load_model
    from dev import RenderLock
    data=read_script();(OUT/'takes').mkdir(parents=True,exist_ok=True)
    manifest_path=OUT/'generation.json'
    manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {
        'model':data['model'],'model_license':data['model_license'], 'cost_usd':0,
        'paid_api_calls':0, 'script_sha256':hashlib.sha256(SCRIPT.read_bytes()).hexdigest(), 'clips':{}}
    with RenderLock('local-voice-audition'):
        print('Loading local voice-design model',flush=True)
        model=load_model(data['model'])
        for take in (1,2):
            for line in data['lines']:
                if args.only and line['id'] not in args.only:continue
                path=OUT/'takes'/f"{line['id']}_take{take}.wav"
                if path.exists() and path.name in manifest['clips'] and not args.force:
                    print('REUSE',path.name,flush=True);continue
                role=data['roles'][line['speaker']]
                seed=role['seed']+(take-1)*100
                mx.random.seed(seed)
                instruction=role['description']+' '+line['direction']
                instruction+=' Measured conversational pacing, natural pauses and breathing. Speak only the supplied dialogue.'
                if take==2:instruction+=' A second, slightly more intimate and tense performance. Avoid melodrama.'
                started=time.monotonic()
                print('GENERATE',path.name,flush=True)
                results=list(model.generate_voice_design(text=line['text'],instruct=instruction,language='English',
                    temperature=.65 if take==1 else .8,max_tokens=350,verbose=False))
                sr=results[0].sample_rate
                audio=np.concatenate([np.array(r.audio,dtype=np.float32).reshape(-1) for r in results])
                raw=measure(audio,sr)
                if not raw['finite'] or raw['seconds']<.5 or raw['seconds']>26:
                    raise RuntimeError(f'Invalid generation: {path.name}: {raw}')
                audio=trim_edges(audio,sr)
                # Keep the unprocessed neural output as well as edit-ready clean clips.
                (OUT/'raw').mkdir(exist_ok=True)
                sf.write(OUT/'raw'/path.name,np.concatenate([np.array(r.audio).reshape(-1) for r in results]),sr,subtype='FLOAT')
                peak=float(np.max(np.abs(audio)))
                if peak>.95:audio*=.95/peak
                sf.write(path,audio,sr,subtype='PCM_24')
                manifest['clips'][path.name]={**measure(audio,sr),'seed':seed,'temperature':.65 if take==1 else .8,
                    'text':line['text'],'speaker':line['speaker'],'instruction':instruction,
                    'generation_seconds':round(time.monotonic()-started,2)}
                manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
                print('SAVED',path.name,manifest['clips'][path.name]['seconds'],'seconds',flush=True)
                del results,audio;gc.collect();mx.clear_cache()
        del model;gc.collect();mx.clear_cache()


def mix(args):
    import numpy as np
    import soundfile as sf
    from scipy import signal
    data=read_script();selection_path=OUT/'selection.json'
    selection=json.loads(selection_path.read_text()) if selection_path.exists() else {x['id']:1 for x in data['lines']}
    OUT.mkdir(parents=True,exist_ok=True);(OUT/'clean').mkdir(exist_ok=True)
    clips=[];sr=24000
    for line in data['lines']:
        take=int(selection[line['id']]);path=OUT/'takes'/f"{line['id']}_take{take}.wav"
        a,rate=sf.read(path,dtype='float32')
        if rate!=sr:a=signal.resample_poly(a,sr,rate)
        if a.ndim!=1:raise RuntimeError('Expected mono voice clips')
        sf.write(OUT/'clean'/f"{line['id']}.wav",a,sr,subtype='PCM_24')
        # Mild high-pass only in the edited mix, never the clean masters.
        a=signal.sosfilt(signal.butter(2,75,fs=sr,btype='highpass',output='sos'),a)
        rms=float(np.sqrt(np.mean(a*a)));gain=min(3.0,.075/max(rms,1e-8));a*=gain
        if line['speaker']=='control':
            a=signal.sosfilt(signal.butter(2,[280,4300],fs=sr,btype='bandpass',output='sos'),a)
            a=np.tanh(a*1.25)/1.25
            rms=float(np.sqrt(np.mean(a*a)));a*=min(2,.075/max(rms,1e-8))
        clips.append((line,a,take))
    # Pauses are authored scene beats, not slowed-down/pitch-shifted speech.
    lead=1.8;tail=2.2
    gaps=[float(line['gap_after_seconds']) for line,_,_ in clips]
    gaps[2]=.08;gaps[3]=.75;gaps[8]=.65
    total=lead+tail+sum(len(a)/sr for _,a,_ in clips)+sum(gaps)
    if total<45:
        extra=45-total
        for index,weight in [(0,.2),(1,.15),(2,.1),(3,.25),(8,.3)]:gaps[index]+=extra*weight
        total=45
    if total>60:raise RuntimeError(f'Audition runs {total:.1f}s; edit takes instead of truncating speech')
    mix=np.zeros((int((total+.1)*sr),2),dtype=np.float64)
    # Reuse original, locally synthesized station ambience at a restrained level.
    wind,wr=sf.read(ROOT/'content/audio/ambience_wind.wav',dtype='float32')
    machine,mr=sf.read(ROOT/'content/audio/ambience_industrial.wav',dtype='float32')
    for a,rate,level in [(wind,wr,.003),(machine,mr,.0025)]:
        if a.ndim>1:a=a.mean(axis=1)
        if rate!=sr:a=signal.resample_poly(a,sr,rate)
        a=np.tile(a,int(np.ceil(len(mix)/len(a))))[:len(mix)]
        a*=level/max(float(np.sqrt(np.mean(a*a))),1e-8)
        mix+=a[:,None]
    cursor=int(lead*sr);timeline=[]
    for line,a,take in clips:
        start=cursor/sr;end=start+len(a)/sr
        pan={'rook':-.14,'atlas':.14,'control':0}[line['speaker']]
        left=np.sqrt((1-pan)/2);right=np.sqrt((1+pan)/2)
        mix[cursor:cursor+len(a),0]+=a*left;mix[cursor:cursor+len(a),1]+=a*right
        timeline.append({'id':line['id'],'speaker':line['speaker'],'start':round(start,3),'end':round(end,3),
                         'take':take,'text':line['text']})
        cursor+=len(a)+int(gaps[len(timeline)-1]*sr)
    # Stereo preview and mono fold-down receive the same transparent peak ceiling.
    peak=float(np.max(np.abs(mix)))
    if peak>.89:mix*=.89/peak
    fade=int(sr*.7);mix[:fade]*=np.linspace(0,1,fade)[:,None];mix[-fade:]*=np.linspace(1,0,fade)[:,None]
    sf.write(OUT/'dead-circuit-audition.wav',mix,sr,subtype='PCM_24')
    sf.write(OUT/'dead-circuit-audition-mono.wav',mix.mean(axis=1),sr,subtype='PCM_24')
    selection_path.write_text(json.dumps(selection,indent=2)+'\n')
    (OUT/'timeline.json').write_text(json.dumps(timeline,indent=2)+'\n')
    report={'cost_usd':0,'paid_api_calls':0,'preview':measure(mix,sr),'mono':measure(mix.mean(axis=1),sr),
            'spoken_words':sum(len(x['text'].split()) for x in data['lines']), 'lines':len(timeline),
            'human_headphone_review':False,'human_laptop_speaker_review':False}
    (OUT/'checks.json').write_text(json.dumps(report,indent=2)+'\n')
    md=['# Dead Circuit — West Gate','', 'AI-generated voice audition. Free local Qwen3-TTS VoiceDesign; no paid services.', '',
        'Timing below is measured from the edited preview. Clean masters have no radio processing.', '',
        '| Start | End | Character | Dialogue |','|---:|---:|---|---|']
    for line in timeline:md.append(f"| {line['start']:.2f}s | {line['end']:.2f}s | {line['speaker'].title()} | {line['text']} |")
    md+=['','## Review status','','Automated duration, clipping, finite-sample and mono checks are recorded in checks.json. Physical headphone and laptop-speaker listening has not been performed. See review.json for transcript checks and take selection.','',
         '## Provenance','','Voice model: https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit (Apache-2.0). MLX-Audio: https://github.com/Blaizzy/mlx-audio (MIT). Voices are fictional descriptions; no real person was cloned. Ambience is the game’s existing original synthesized wind and industrial audio.']
    (OUT/'timed-script.md').write_text('\n'.join(md)+'\n')
    print(json.dumps(report,indent=2))
    master(args)


def master(args):
    import re
    import subprocess
    import numpy as np
    import soundfile as sf
    import imageio_ffmpeg
    exe=imageio_ffmpeg.get_ffmpeg_exe()
    wav=OUT/'dead-circuit-audition.wav'
    probe=subprocess.run([exe,'-hide_banner','-i',str(wav),'-af','loudnorm=I=-18:TP=-1.5:LRA=9:print_format=json','-f','null','-'],capture_output=True,text=True,check=True)
    measurement=json.loads(re.search(r'\{\s*"input_i".*?\}',probe.stderr,re.S).group())
    effect='loudnorm=I=-18:TP=-1.5:LRA=9:linear=false:print_format=json'
    effect+=':measured_I='+measurement['input_i']+':measured_TP='+measurement['input_tp']
    effect+=':measured_LRA='+measurement['input_lra']+':measured_thresh='+measurement['input_thresh']+':offset='+measurement['target_offset']
    temp=OUT/'mastering.tmp.wav'
    render=subprocess.run([exe,'-y','-hide_banner','-i',str(wav),'-af',effect,'-ar','24000','-c:a','pcm_s24le',str(temp)],capture_output=True,text=True,check=True)
    mastering=json.loads(re.search(r'\{\s*"input_i".*?\}',render.stderr,re.S).group())
    temp.replace(wav)
    a,sr=sf.read(wav,dtype='float32')
    sf.write(OUT/'dead-circuit-audition-mono.wav',a.mean(axis=1),sr,subtype='PCM_24')
    subprocess.run([exe,'-y','-hide_banner','-loglevel','error','-i',str(wav),'-ar','44100','-c:a','libmp3lame','-b:a','160k',str(OUT/'dead-circuit-audition.mp3')],check=True)
    check_path=OUT/'checks.json';checks=json.loads(check_path.read_text())
    checks['preview']=measure(a,sr);checks['mono']=measure(a.mean(axis=1),sr)
    checks['mastering']={'target_lufs':-18,'true_peak_ceiling_dbtp':-1.5,**mastering}
    checks['mastering']['ffmpeg_version']=imageio_ffmpeg.get_ffmpeg_version()
    check_path.write_text(json.dumps(checks,indent=2)+'\n')
    print('MASTERED',checks['preview']['seconds'],'seconds;',mastering['output_i'],'LUFS;',mastering['output_tp'],'dBTP')


def review(args):
    import difflib
    import re
    import numpy as np
    import soundfile as sf
    import mlx.core as mx
    from scipy import signal
    from mlx_audio.stt import load
    from transformers import WhisperProcessor
    from dev import RenderLock
    def words(text):
        text=text.lower().replace("’", "'")
        for a,b in {"we're":"we are", "they're":"they are", "i'll":"i will", "i've":"i have", "you've":"you have", "wasn't":"was not", "that's":"that is"}.items():text=text.replace(a,b)
        return [{"10":"ten","5":"five"}.get(w,w) for w in re.findall(r"[a-z0-9]+",text)]
    data=read_script();path=OUT/'review.json'
    report=json.loads(path.read_text()) if path.exists() else {'method':'Local Whisper base.en transcript comparison; not human listening or acting approval.','clips':{}}
    with RenderLock('local-voice-transcript-review'):
        model=load('mlx-community/whisper-base.en-mlx')
        if model._processor is None:model._processor=WhisperProcessor.from_pretrained('openai/whisper-base.en')
        for line in data['lines']:
            for take in (1,2):
                name=f"{line['id']}_take{take}.wav";clip=OUT/'takes'/name
                if not clip.exists():continue
                if name in report['clips'] and not args.force:continue
                audio,sr=sf.read(clip,dtype='float32')
                audio=signal.resample_poly(audio,16000,sr).astype('float32')
                result=model.generate(audio,language='en',temperature=0.0,verbose=None,condition_on_previous_text=False)
                transcript=result.text
                expected=words(line['text']);actual=words(transcript)
                edits=sum(max(i2-i1,j2-j1) for tag,i1,i2,j1,j2 in difflib.SequenceMatcher(None,expected,actual).get_opcodes() if tag!='equal')
                error=edits/max(1,len(expected))
                report['clips'][name]={'text':transcript,'expected':line['text'],'word_error_fraction':round(error,4)}
                path.write_text(json.dumps(report,indent=2)+'\n')
                print(name,round(error,3),transcript,flush=True)
        selection={}
        for line in data['lines']:
            candidates=[]
            for take in (1,2):
                name=f"{line['id']}_take{take}.wav"
                expected=words(line['text']);actual=words(report['clips'][name]['text'])
                edits=sum(max(i2-i1,j2-j1) for tag,i1,i2,j1,j2 in difflib.SequenceMatcher(None,expected,actual).get_opcodes() if tag!='equal')
                report['clips'][name]['word_error_fraction']=round(edits/max(1,len(expected)),4)
                info=sf.info(OUT/'takes'/name)
                pace=len(line['text'].split())/info.duration
                candidates.append((report['clips'][f"{line['id']}_take{take}.wav"]['word_error_fraction'],abs(pace-2.5),take))
            selection[line['id']]=min(candidates)[2]
        report['selection_basis']='Lowest transcript error; conversational pacing closest to 150 words/minute breaks ties. Emotional delivery and voice identity require listening.'
        report['selected_max_word_error_fraction']=max(report['clips'][f"{line['id']}_take{selection[line['id']]}.wav"]['word_error_fraction'] for line in data['lines'])
        path.write_text(json.dumps(report,indent=2)+'\n')
        (OUT/'selection.json').write_text(json.dumps(selection,indent=2)+'\n')
        del model;gc.collect();mx.clear_cache()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['generate','mix','review','master'])
    parser.add_argument('--only',nargs='*');parser.add_argument('--force',action='store_true')
    args=parser.parse_args()
    {'generate':generate,'mix':mix,'review':review,'master':master}[args.action](args)

if __name__=='__main__':main()
