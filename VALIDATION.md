# FPS Mode validation

Generated 2026-10-17T20:38:20.285478+00:00

Release acceptance is incomplete; failed or unavailable gates are listed below.

Tested on Apple M2, 8 CPU cores, 16 GiB memory, macOS 26.6.2. Godot 4.7.2 standard (ed1daf0bf), Forward+ / Vulkan.

Automated assertions: 544 passed; 0 failed.

| Scenario | Measured seconds | Average FPS | p95 ms | p99 ms | >50 ms frames | Contact median |
|---|---:|---:|---:|---:|---:|---:|
| foundry | 599.98 | 66.59 | 21.09 | 23.84 | 16 | 2.00s |
| ridgeline | 600.00 | 71.67 | 18.57 | 20.36 | 27 | 2.10s |
| foundry-stress | 60.00 | 55.50 | 24.33 | 40.82 | 4 | 0.07s |
| ridgeline-stress | 60.00 | 63.93 | 20.11 | 24.39 | 3 | 0.05s |

Acceptance uses these rendered game measurements, including frame stalls. Diagnostic runs and trimmed frame distributions do not substitute for the required tests. Targets remain average FPS ≥60, p95 ≤20 ms and p99 ≤33.3 ms.

Rendered runs use 1920×1080 internal world resolution at Medium, 30 seconds warm-up, normal simulation speed, VSync disabled, no frame cap, and 16 stable roster slots. CSV files preserve every measured frame interval. Headless matches omit presentation meshes and audio, and are gameplay checks only. Swapped-side runs are accelerated physics checks, not rendering measurements.

The automated player follows authored routes and uses the shared movement and weapon systems. These are scripted tests, not human playtests.

The lightmap editor emits retained native teardown diagnostics after saving its baked textures. Content checks verify actual lightmap texture arrays. Runtime test/capture/export logs are checked separately for script and engine errors.

## Gates

| Check | Result |
|---|---|
| content | PASS |
| core | PASS |
| integration | PASS |
| graphics | PASS |
| killer_replay | PASS |
| test_harness_exit_code | PASS |
| swapped_match_foundry | PASS |
| swapped_match_ridgeline | PASS |
| rendered_cleanup_foundry | PASS |
| rendered_cleanup_ridgeline | PASS |
| exported_controls_and_flow | PASS |
| export_matches_source | PASS |
| signature | PASS |
| bundle_id | PASS |
| rendering_foundry | FAIL / UNAVAILABLE |
| raw_csv_foundry | PASS |
| contact_time_foundry | FAIL / UNAVAILABLE |
| full_round_foundry | PASS |
| rendering_ridgeline | PASS |
| raw_csv_ridgeline | PASS |
| contact_time_ridgeline | FAIL / UNAVAILABLE |
| full_round_ridgeline | PASS |
| rendering_foundry-stress | FAIL / UNAVAILABLE |
| raw_csv_foundry-stress | PASS |
| rendering_ridgeline-stress | FAIL / UNAVAILABLE |
| raw_csv_ridgeline-stress | PASS |
| one_verified_content_build | PASS |
| captures_foundry | PASS |
| captures_ridgeline | PASS |
| optic_ads_captures | PASS |
| visual_review | FAIL / UNAVAILABLE |

## Evidence

- `.artifacts/validation.json`: complete machine-readable results.
- `.artifacts/reports/`: named assertions and deliberate failure exit-code check.
- `.artifacts/benchmark-*.csv` and `.json`: raw intervals and measured results.
- `.artifacts/screenshots/`: map, HUD, smoke, reload, loadout, and weapon inspections.
- `.artifacts/visual-review.json`: inspected images, hashes and visual limits.
- `.artifacts/export-smoke.json` and `logs/export-smoke.log`: native packaged controls/flow.
- `.artifacts/match-*-swapped.json`: full matches with exchanged starting sides.

The local bundle uses ad-hoc signing. Public notarization and multiplayer are outside this release. Competitive balance still needs human playtesting. Architecture and first-person hands remain below AAA photorealistic quality; some firearm variants share meshes. The killer replay reconstructs sampled poses and weapons, without rewinding every particle or ragdoll.
