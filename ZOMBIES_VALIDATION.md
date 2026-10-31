# Zombies validation — reference-driven visual build

Date: 2026-10-21. Apple M2, macOS, Godot 4.7.2, Forward+ Vulkan.

Source/content SHA-256: `de82fe95849dd70a6b8b0b135c0b420633dec3d810ba469d4a4b4789da47ab11`. The signed native export and source-matched reports use this fingerprint. Export settings are recorded separately in `.artifacts/export-build.json`.

## Implemented experience

Offline solo survival on Dead Current and Dead Air: finite rounds and a stable 24-enemy pool; six-board barriers with queued entry and repair; surviving grenade victims becoming legless crawlers that retain their life/health and hold the round; five chalk wall guns with matched ammunition; a weighted mystery box with explicit claim, timeout, refund/relocation; three wonder weapons; power, five perks with a four-perk limit, upgrading, five drops, a powered trap per map, solo down/revive with perk loss, mode-specific HUD/results/records, keyboard/controller interactions, pause and clean rematches.

The reference-driven visual revision replaces primitive zombies with the attributed Pixelhouse 57-bone textured character, authored clips, forward-reaching hand IK, aligned luminous pupils, real leg-triangle removal and cached textured detached limbs. Maps add worn plaster beneath exposed brick, scanned projected leaks, aged timber, beams/columns, furniture, service hardware and batched debris/papers. Full art details, source/license, staged preview disclosure and topology limits are in `ZOMBIES_VISUAL_UPGRADE.md`.

## Assertion suites

| Suite | Passed | Failed |
|---|---:|---:|
| zombies | 128 | 0 |
| core | 48 | 0 |
| content | 545 | 0 |
| audio | 23 | 0 |
| integration | 625 | 0 |

The Zombies cases cover transactions, perks, shell reloads, upgrade/ammo rules, box reveal/claim/timeout, damage/life isolation, lower-body occlusion and fatal/nonfatal explosions, last-crawler retention, revive/perk loss, power-up rules, thin and point-blank cover, unique arc targets, window-queue knockback, save sanitation, textured skinning/materials, authored attacks, true leg removal, repeated crawler-pose stability, forward hand placement and cached detached-limb geometry. Existing TDM expectations remain in place.

Python tools compile and `git diff --check` passes. Export runs the project script check.

## Actual movement and lifecycle

`python3 tools/dev.py zombies-probe` passes eight actual-motion fixtures: both maps × walker/crawler × multi-room/machine-adjacent starts, with a moving player followed by a stationary finish. The probe follows purchased doorways and goes around real collision obstacles.

| Map | Completed rounds | Simulated seconds | Nodes across three rematches | Fingerprint matches |
|---|---:|---:|---|---|
| dead_current | 20 | 1219.48 | [2350, 2350, 2350] | True |
| dead_air | 20 | 1191.08 | [2361, 2361, 2361] | True |

**Soak fixture:** a protected QA player with a full perk/upgraded-wonder loadout and replenished magazine/reserve ammunition. These runs establish lifecycle/path/combat/round completion stability, not human difficulty or economy. Earlier normal-damage route-bot diagnostics died in later rounds. Normal damage, downing, perk loss, revival and fatal game-over are verified separately in the input smoke.

## Rendered and packaged evidence

Both exported maps pass 28 synthetic-input steps through the ordinary app pipeline: mode/map selection, pistol/roster/HUD start, keyboard fire/aim/reload, pause/resume, door/wall purchases, controller hold-repair/reload arbitration, frag throw/crawler/round retention, power and perks, down/revive/loss, fatal game-over, rematch reset and menu return. Both reports record `exported=true`, `export_matches_source=true`, and `source_unchanged=true`. The packaged TDM smoke also passes with the same export fingerprint.

Native app: `builds/FPSMode.app`. Reports: `.artifacts/smoke-export-zombies-<map>-<seed>.json`, `.artifacts/export-smoke.json`, and `.artifacts/export-build.json`. The export explicitly includes the Zombies rule/map JSON and asset credits.

Each map has six ordinary rendered capture fixtures under `.artifacts/screenshots/zombies/<map>/`. Rig close-ups and deliberately staged real-app horde views are under `.artifacts/screenshots/zombie-art/`. The staged horde views are art-review fixtures, not human-playtest evidence.

## Performance

Presentation-only animation cadence keeps nearby posing at full physics rate, nominal 30 Hz beyond 10 m, 15 Hz beyond 20 m and 10 Hz outside the camera beyond 8 m. Movement, collision, damage and round simulation still update every tick for all 24 enemies. Crawler conversion forces an immediate visual update.

Both final 600-second measurements pass the required frame-delivery gates. Configuration: Apple M2, Medium, 1920 × 1080 internal, software VSync disabled and engine frame cap zero, 30-second warmup. Targets: average ≥60 FPS, p95 ≤20 ms and p99 ≤33.3 ms. Fixture: protected moving QA human, continuously replenished round-15 horde capped at 24, crawlers, barriers, repeated upgraded wonders, traps and bounded presentation.

| Map | Seconds | Samples | Avg FPS | p95 ms | p99 ms | Focused frames | Result |
|---|---:|---:|---:|---:|---:|---:|---|
| dead_current | 600.006481 | 65385 | 108.974 | 15.922 | 18.078 | 16.2% | PASS |
| dead_air | 599.999036 | 49318 | 82.197 | 18.203 | 22.351 | 100.0% | PASS |

All raw frame intervals were independently re-read. Sample counts, elapsed sums, average FPS and percentile values match their JSON reports; both reports have `source_unchanged=true` and the final export fingerprint. No samples were filtered by focus. Dead Current’s 16.2% focused-frame fraction limits interpretation as a controlled foreground-throughput measurement. Dead Air remained fully focused.

Raw data: `.artifacts/benchmark-zombies-dead_current-2601.csv` and `.artifacts/benchmark-zombies-dead_air-2602.csv`. Full report aggregate: `.artifacts/zombies-final-evidence.json`. The native app’s deep/strict code signature verifies successfully.

Diagnostic history is retained separately. The initial new-art diagnostic measured 65.56 FPS / p95 19.998 ms; animation cadence improved the focused diagnostic to 85.06 FPS / p95 18.148 ms. An earlier full Dead Air run missed the gate at p95 20.644 ms; that failure is preserved under `.artifacts/visual-before-wall-batch/`. After static wall batching and removal of unused navigation agents, the focused Dead Air diagnostic passed at 83.62 FPS / p95 17.344 ms, followed by the passing final full run above. Neither the enemy cap nor resolution, visual settings, textures, geometry or effects were reduced.

The previous primitive-version full benchmark remains historical comparison only under `.artifacts/visual-baseline/`. It is not used as acceptance of the new art.

## Limits and inherited evidence

- The licensed character/clothing and retained six-zone map topology differ from the supplied reference. The starting staircase is sealed scenery, not a new upper-floor route.
- No human playtest establishes fun, economy pacing, difficulty, controller feel or visual approval. Controller smoke uses synthetic events, not a physical device.
- No co-op, networking, quests or bosses are included in this scope.
- Known Godot editor lightmap teardown diagnostics are retained. Checks reject runtime/parse errors; rematch node counts are stable.
- Historical TDM rendering/release gates in `VALIDATION.md` remain separate. Shared regressions and the packaged TDM flow were checked here; every TDM map benchmark was not repeated.
