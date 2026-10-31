> Historical report for the retired rotunda/gondola layout. The terrain-first rebuild
> and current evidence are documented in `GLACIER_REDESIGN.md`.

# Glacier Peak validation

Integrated `glacier_peak_handoff_package.zip` into FPS Mode on 2026-10-23.
Glacier Peak is the ninth TDM map (order 70, seed 2410). Airport remains the default.
Select Deploy → Battlefield → Glacier Peak, or run
`python3 tools/dev.py run --map glacier_peak`.
The rebuilt, signature-verified `builds/FPSMode.app` includes the new map.

## Corrections

- Replaced the nonexistent MapMeshes.bevel_box call with MapMeshes.block.
- Passed a Color to the builder's cover helper instead of a boolean.
- Removed unused tree/prop overrides referencing a nonexistent MapNature.place API.
- Removed unsupported MapArena.spawn_yaws access; retained sign orientation.
- Adapted supported_modes, lighting, ground/terrain layers, minimap texture and
  overview labels to the project's actual registry schema.
- Resolved legacy detail material aliases without replacing valid corrugated and
  concrete surface kinds. Refreshed the scene, lighting and minimap afterward.
- Strengthened the static verifier with real builder/mesh method discovery and
  engine registry schema checks. Original supplied reports are reference evidence;
  they did not catch the initial engine compilation and runtime errors.

## Results

- Godot 4.7.2 script check: 0 failures.
- Static source/geometry verifier: 46 passed, 0 failed.
- Content suite: 620 passed, 0 failed (also passed after the final material bake).
- Integration suite: 927 passed, 0 failed; 101 checks specific to Glacier Peak.
- Engine navigation bake: 1,123 polygons at 0.75 m agent radius.
- Traversal: 16/16 ramp walks, 128/128 spawn-to-objective walks,
  128/128 spawn-to-ammo walks and 59/59 sampled routes; no stuck points.
- Spawn capsule clearance, cover/objective marker reachability and access to the
  upper deck from both teams passed.
- Directional lightmap/shadowmask and 1024 × 1024 minimap generated successfully.
- Labelled overview and gameplay captures generated; spawn, interior and gondola
  views visually inspected after correcting wall materials.
- Source and exported-app full 8v8 matches: passed, score 84–100,
  simulation clock 168.03 s, 194 contact samples.
- Export signature verification passed; exported-app smoke test passed all 21 steps.
- Final M2 / Metal / Forward+ benchmark: 600 seconds at 1920 × 1080,
  75.91 FPS average, p95 16.294 ms, p99 22.669 ms.
  All project performance thresholds passed; focused fraction 1.0.
  No additional performance changes were needed to meet those thresholds.
- Benchmark source remained unchanged. Benchmark, export and smoke test share
  content fingerprint `01396da8860e7d9adcf20d2d20823060807c60f669bf8ff662426956bb3f1a25`.
- `git diff --check`: passed.

## Evidence

- Source: `game/maps/layouts/glacier_peak.gd`.
- Registry: `content/manifest/map_list/glacier_peak.json`.
- Generated scene, meshes, navigation and lighting: `game/maps/generated/glacier_peak*`.
- Minimap: `content/minimaps/glacier_peak.png`.
- Static report: `.artifacts/glacier_peak/glacier_peak_static_verification.json`.
- Engine suites: `.artifacts/reports/content.json`, `.artifacts/reports/integration.json`.
- Benchmark: `.artifacts/benchmark-glacier_peak.json` and `.csv`.
- Export: `.artifacts/export-build.json`, `.artifacts/export-smoke.json`.
- Exported Glacier Peak match log: `.artifacts/logs/glacier-export-match.log`.
- Views: `.artifacts/screenshots/glacier_peak/` and
  `.artifacts/screenshots/overviews/glacier_peak.png`.
- Original handoff README, blueprint and static report: `handoff/glacier_peak/`.
- Complete supplied design: `GLACIER_PEAK_CODEX_SPEC.md`.

## Limits

No human playtest was performed. Domination and hardpoint markers are navigation
anchors; the map is registered for TDM only. The supplied dual-radius grid checks
are geometric estimates; the actual Godot integration used the baked 0.75 m mesh.
The standard benchmark reports frame times, not visible-triangle or draw-call
maxima, so the separate spec limits for those counters are unverified.
Godot emitted its known lightmap-editor teardown diagnostics and seven texture
RID warnings on rendered shutdown; all automated runs completed successfully.
Existing unrelated working-tree changes were retained. No commit or push was made.
