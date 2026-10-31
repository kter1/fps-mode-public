# Dead Circuit voice integration

Validated 2026-10-21 on Apple M2 / macOS. Source/export fingerprint: `c6adcf49caa7a0d5c7c2cc908627a24992056676735eab138d829f4317edb1e1`.

## Included experience

The user-approved revision-2 audition is integrated as the opening campaign
conversation. Ten individual clean clips retain the approved performances,
including Atlas relay take 2. Rook and Atlas use a dedicated positional voice
player following their squad actors; Control uses a separate radio player with
280 Hz high-pass and 4.3 kHz low-pass filters. Speaker-labelled subtitles follow
imported audio durations and approved inter-line pauses. Existing map ambience
continues; the audition's mixed ambience is not duplicated.

Dialogue starts after deployment countdown. Game pause freezes its timeline and
audio through the pausable world subtree. Mission end/death, leaving the world,
advancing encounters, or a dead squad speaker cancels playback and captions.
A fresh opening attempt starts fresh; later checkpoints skip arrival dialogue.
The packaged game needs no model weights, network, API key, or paid service.

## Checks

- Campaign: 30 passed, 0 failed, including clip loading, approved relay asset
  hash/take, spatial/radio routing, subtitles, pause, cleanup, dead speaker, and
  later-checkpoint isolation.
- Core: 48 passed, 0 failed. Content: 570 passed, 0 failed.
- Script check: 0 failures. `git diff --check` passes.
- Rebuilt native app: ten real-time dialogue events, approved relay take 2,
  nonempty captions for every cue, exclusive radio/spatial routing, and clean
  completion all pass. Report records exported=true, export_matches_source=true,
  and source_unchanged=true.
- Rendered relay subtitle visually inspected at 1280 x 720.

Packaged playback fixture holds combat static so squad deaths cannot interrupt
the complete presentation check. It uses the ordinary dialogue controller,
audio players, resource imports and HUD; this does not establish human gameplay
or firefight mix quality. Normal gameplay retains combat and interruption rules.

## Evidence and limits

- `.artifacts/campaign-voices-smoke.json`: packaged playback result.
- `.artifacts/screenshots/campaign/approved-relay-voice.png`: caption render.
- `.artifacts/reports/campaign.json`: named campaign assertions.
- `content/data/campaign/dead_circuit_dialogue.json`: approved takes, hashes,
  generation provenance and model revisions.

The user approved the audition, including the alternate relay performance.
Physical listening in a live firefight remains unverified. Only the opening
conversation is voiced; later objective briefings remain text. Lip sync and
choreography are not included. The runtime exits with the existing seven-texture
RID teardown warning; no script/runtime errors were reported by this smoke.
