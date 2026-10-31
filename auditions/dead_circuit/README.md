# Dead Circuit: West Gate voice audition

A 106-word cinematic action exchange between Rook, Atlas, and Control. Two local
AI takes per character/line; no paid APIs, accounts, or subscriptions. The original
ElevenLabs proposal was replaced after the user specified **free only**.

The audition uses Qwen3-TTS VoiceDesign (Apache-2.0) via MLX-Audio (MIT) on Apple
Silicon. Initial setup downloads model weights; generation then runs locally.
The isolated environment and model cache are excluded from Git. The game and
its packaged app are not modified by this audition workflow.

## Generate and review

From the project root, using Python 3.13 on an Apple Silicon Mac:

```sh
python3 -m venv .voice-audition-venv
.voice-audition-venv/bin/python -m pip install mlx-audio==0.6.1 soundfile==0.13.1 imageio-ffmpeg==0.6.0
.voice-audition-venv/bin/python tools/voice_audition.py generate
.voice-audition-venv/bin/python tools/voice_audition.py review
.voice-audition-venv/bin/python tools/voice_audition.py mix
```

Generation and speech recognition share the existing render lock with Godot and
Blender. Generation resumes from recorded clips. Use `--only 01_rook` for a focused
retake, or `--force` to overwrite selected takes. After regeneration, rerun review
with `--force` before mixing. The review compares transcripts, not subjective
acting quality. Selection can be edited in the generated `selection.json`.

## Outputs

All outputs are under `.artifacts/voice-audition/dead-circuit/`:

- `dead-circuit-audition.mp3`: compact playback preview.
- `dead-circuit-audition.wav`: edited stereo audition with station ambience and
  light radio processing on Control, mastered toward -18 LUFS / -1.5 dBTP.
- `dead-circuit-audition-mono.wav`: mono fold-down for checking intelligibility.
- `raw/`: untouched floating-point synthesis outputs.
- `takes/`: both takes with boundary silence trimmed and a safe peak ceiling.
- `clean/`: chosen unprocessed dialogue clips for later game integration.
- `character-takes/`: six character reels (two takes each for Rook, Atlas, Control).
- `timed-script.md` and `timeline.json`: actual edited cue timings.
- `generation.json`, `review.json`, `checks.json`: provenance, transcript-based
  selection, measured audio checks, and explicitly unperformed listening checks.

Physical headphone and laptop-speaker listening must be done by a human before
voice casting is accepted. Realism is an audition criterion, not a guarantee.
The voices describe fictional characters; no real person's voice was cloned.

## Sources

- https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit
- https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign
- https://github.com/Blaizzy/mlx-audio
- https://huggingface.co/mlx-community/whisper-base.en-mlx (local transcript QA)

Existing original synthesized wind and industrial ambience comes from
`content/audio/`; no external music or sound effects are introduced.
