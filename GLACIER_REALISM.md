# Glacier Peak — current environment revision

This supersedes the isolated pillar, rounded-volume and slab-prop experiments
recorded in `GLACIER_REDESIGN.md`. Those forms were rejected by the user.

## Current construction

- Removed the repeating standalone ice props and the overhead ice arch.
- Built four connected terrain-based ice banks with physical crevasse cuts,
  uneven toes, fractured crests and transitions into the snowfield. The southeast
  route is an open crevasse run. These banks share visual and collision meshes.
- Replaced scattered synthetic ice cover with snow-covered moraine using the
  project's existing Poly Haven `boulder_01` photogrammetry asset. A welded,
  UV-preserving Blender reduction produces a 3,966-triangle gameplay mesh from
  the original 66,122-triangle scan. Original asset files remain intact.
- Replaced the ring of separate mathematical peaks with continuous ridged
  terrain. Lowered the exaggerated near relief after checking rendered views.
- Reworked the ice material toward rough, weathered, desaturated ice and snow;
  removed the saturated cyan finish and regular drawn-looking vein pattern.
- Retained the established camps, survey bridge, 112 × 100 m footprint and TDM
  rules. One moraine boulder was moved two metres to clear a spawn capsule.

## References and provenance

Visual references were inspected directly, rather than using another primitive
shape as the reference:

- [NPS — Seracs and Icebergs, Emmons Glacier photograph](https://www.nps.gov/articles/seracsandicebergs.htm)
- [NPS — Glacier Ice Caves](https://www.nps.gov/articles/000/glacier-ice-caves.htm)

The reference photographs are not used as game textures. The rock source and
its textures were already included in the project's CC0 asset manifest.
`tools/build_glacier_rock.py` and `tools/build_glacier_rock.gd` reproduce the
Glacier-specific rock resource using the bundled Blender and Godot tools.

## Checks

- Godot script check: 0 failures.
- Saved-map physics, navigation and normal-continuity probe: 21 passed, 0 failed.
- All 32 spawn capsules clear after moving the intersecting boulder.
- Traversal: 16/16 ramp paths, 128/128 objective paths, 128/128 supply paths and
  59/59 sampled routes passed, with no stuck points (331 walks total).
- Rebuilt navigation: 1,662 polygons.
- `git diff --check` passed.

- Final directional lightmap/shadowmask, minimap and five review views rebuilt.
- Content suite: 622 passed, 0 failed.
- Final 30-second rendering sample: 60.03 FPS average, p95
  18.301 ms, p99 19.581 ms, zero frames above 50 ms, at
  1920 × 1080 Medium / Metal on Apple M2. All short-run thresholds passed.
- App export/signature verification passed; all 21 packaged Glacier
  gameplay smoke-test steps passed. Reopened with Glacier Peak preselected.
- Packaged and measured content fingerprint:
  `6b75ecd5761761893a85afa8c039bafe162f535784540fa8032ef821d402376f`.

Automated checks establish rendering/runtime correctness and traversability;
they do not establish artistic realism or competitive balance. Ice remains
procedurally modeled; the moraine rock comes from photogrammetry. The rendering
sample is 30 seconds after warm-up, rather than an endurance benchmark.

The game still opens on its Airport menu backdrop. Choose Deploy / Team
Deathmatch, then Start Team Deathmatch to enter the preselected Glacier map.


## Barrel and mountain cleanup

- Replaced all nine 0.65 m decorative barrels with the existing full-size
  `MapBuilder.drum` factory (1.24 m visual/collider height). They now register
  with `Destructible`, receive the flammable hazard finish and participate in
  the standard fuse, explosion and damage behavior.
- `glacier_barrel_probe.gd` checks the saved map: nine registered drums, correct
  visual and collider size, bullet-ray contact, puncture from an actual A4 shot,
  detonation under repeated A4 fire and removal of visible/collision geometry.
  All seven assertions passed for all nine barrels. The A4 uses 28 damage;
  seven rounds reach the existing normalized barrel-damage threshold. Global
  weapon damage and barrel rules were not changed.
- Added a Glacier-only mountain material: broad granite weathering, slope/wind
  snow masks, two decorrelated texture projections and fine-detail fading at
  distance. Added small erosion ridges to the out-of-bounds geometry. The
  backdrop no longer relies on the shared repeating terrain surface material.
  Route geometry remains unchanged. Trial background rock props were removed
  after visual review exposed poor contact with the steep terrain.
- Sunk the near-zero-height ice-bank skirts into the ground to remove thin
  floating triangles and contact seams.
- Geometry/shading checks: 21 passed. Traversal: 331/331 walks passed. Navigation
  rebuilt: 1,665 polygons. Script check: 0 failures; `git diff --check` passed.

Final cleanup build verification:

- Content suite: **660 passed, 0 failed**. Barrel probe: **7 passed, 0 failed**
  across all nine drums. Geometry probe: **21 passed, 0 failed**.
- 30-second rendering sample after warm-up, 1080p, Metal, Apple M2, 16 players:
  **70.89 FPS average**, **18.811 ms p95**, **26.645 ms p99**; acceptance passed.
  Window focus was 100%, and source stayed unchanged during measurement.
  The first sample failed (56.64 FPS, 24.975 ms p95) with only 85% foreground
  focus; its report is retained as `benchmark-first-cleanup-run.json`.
- Final lightmaps baked successfully. Five stable review views rendered.
  Native editor teardown diagnostics remain in the bake log; runtime checks
  reported no script errors.
- Signed macOS app rebuilt and verified. Benchmark/export content fingerprint:
  `dc376ef7f027ab764538d777e1f02bcf03248a14b36c53e20db2daa3a8c47cbf`.

Packaged Glacier smoke: **21/21 steps passed**, including match setup, firing,
ADS, replay, respawn, results and rematch. Export matches the benchmarked source.
The rebuilt app was reopened with Glacier preselected; Deploy → Start Team
Deathmatch enters the updated map.
