# Transit Works replacement validation

Replaced the Foundry-derived seventh map on 2026-10-22 using
`transit_works_handoff_package.zip`. The registered ID remains `transit_works`,
menu order 60. There are exactly seven TDM maps; Airport remains the default.

The replacement uses a central locomotive turntable, two walk-through metro
cars, southern maintenance stalls, northern overhaul concourse and mezzanine,
and open platform spawns. It does not call Foundry's `modern_building()` or
`bridge()` helpers. No local layout corrections were needed for acceptance.
The supplied layout uses 0.75 m navigation radius and 0.25 m navigation cells.

## Engine verification

- Godot 4.7.2 script parsing and project script check passed (0 failures).
- Preparation and directional lightmap/shadowmask bake passed; navigation has
  1,221 polygons.
- Regenerated and imported the 1024 x 1024 minimap.
- Content suite: 570 passed, 0 failed.
- Full integration suite: 726 passed, 0 failed.
- Focused traversal: 16/16 ramp walks, 128/128 spawn-to-objective walks,
  128/128 spawn-to-ammo walks, and 60/60 sampled routes passed with no stuck points.
- Full 16-slot match, seed 1906: passed, final score 71–100.
- Engine captures and labelled overhead generated and visually inspected.
- Standalone `builds/FPSMode.app` rebuilt and code signature verified.
- Standalone export smoke test: all 21 steps passed.
- Direct exported-pack inspection confirmed seven TDM entries and the new
  Transit Works subtitle and seed 1906.

## Files and evidence

- Source: `game/maps/layouts/transit_works.gd` and
  `content/manifest/map_list/transit_works.json`.
- Generated scene, navigation, meshes, lightmaps: `game/maps/generated/transit_works*`.
- Minimap: `content/minimaps/transit_works.png`.
- Content and integration reports: `.artifacts/reports/`.
- Match report: `.artifacts/match-transit_works.json`.
- Gameplay captures: `.artifacts/screenshots/transit_works/`.
- Overhead: `.artifacts/screenshots/overviews/transit_works.png`.
- Original supplied README, Python verifier, static report and plan are preserved
  under `handoff/transit_works/`. Their prose and static results are reference
  material; local engine checks above establish acceptance for this integration.

## Limits

No hardware performance acceptance benchmark or human playtest was performed.
Objective markers do not add playable Domination or Hardpoint modes.
