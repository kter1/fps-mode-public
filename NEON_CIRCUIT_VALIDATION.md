# Neon Circuit integration

Source: [FPS Mode pull request #1](https://github.com/kter1/fps-mode/pull/1),
branch `map/neon-circuit`, commit `1814055bdf078f694989b6811a0f0e5679804ba5`.
This is the new map identified in the project's GitHub repository; the user
identified its creator as Muse AI. Source files were incorporated without
merging or changing the remote branch, preserving existing local work.

The map registers automatically in the team deathmatch selector as **Neon
Circuit** (`neon`). Run `python3 tools/dev.py run --map neon`, or select it in
the rebuilt `builds/FPSMode.app`.

Integration repairs:

- Explicit numeric types resolve upstream GDScript inference errors.
- Four ground material layers satisfy the shared splat shader contract.
- The central catwalk decks no longer overlap the ascending ramps. Wider ramps,
  entrances clear of the exterior walls, and finer navigation voxels preserve
  physical access to the upper floor with additional corner clearance.
- The inspection route follows the north catwalk at 3.6 m; authored navigation
  test points avoid the solid arcade cover.
- Interior probe volumes and fire extinguishers complete the shared environment
  checks. The map has generated navigation, lightmaps, meshes and a 1024px minimap.

Validation on October 22, 2026, Godot 4.7.2 / Apple M2:

- Script check: **0 failures**.
- Content suite: **595 passed, 0 failed**.
- Existing integration suite scoped to `neon`: **100 passed, 0 failed**,
  including both teams reaching the upper floor, spawn/marker clearance,
  combat, replay, rematches and stress roster checks.
- Physical traversal: **32/32** ramp walks, **128/128** spawn-to-objective
  walks, **128/128** spawn-to-cache walks and **59/59** sampled route walks;
  no stuck points. These use the existing four movement styles and player code.
- Game capture: **CAPTURE PASS neon**; arena screenshot visually inspected.
- Final lighting and minimap baking completed; the Mac app was exported and
  passed strict signature verification. Export logs include the Neon Circuit
  registry, compiled layout and saved scene.
- Packaged Neon Circuit smoke test: **21 steps passed**, including full roster,
  input, firing, reload, jumping, pause/resume, recorded replay, respawn, final
  kill cam, results, rematch and return to menu. Evidence:
  `.artifacts/neon-export-smoke.json` and
  `.artifacts/logs/neon-export-smoke-console.log`.

Evidence: `.artifacts/reports/neon-integration.json`,
`.artifacts/reports/content.json`, `.artifacts/logs/neon-final-console.log`,
`.artifacts/logs/neon-export-console.log`, and `.artifacts/screenshots/neon/`.
The focused runner in `.artifacts/neon_test_runner.gd` copies the existing
integration runner with its map loop restricted to `neon`; shared test sources
were not changed. Earlier failing runs informed the repairs above.

## Blacklight art overhaul

The subsequent visual pass replaces the plain painted-trim look with actual
HDR emissive fixtures and a map-local procedural art system:

- Cyan, magenta, amber and violet circuit murals, outlined maze panels and
  directional chevrons; ringed-planet graphics above the play area.
- Cosmic carpet, UV ceiling fixtures, overhead laser lines, lit door frames,
  illuminated ramp edges and a glowing reactor lattice with telemetry graphics.
- Arcade cabinets with animated pixel aliens and scanlines, graphic side art,
  named marquees, controls, joysticks, buttons and coin doors.
- Entrance and sector branding, canopy lighting and snack-stall signs.

`game/maps/layouts/neon_art.gd` batches fixtures into 50 groups and authors
80 shader panels using `content/materials/neon/arena_graphics.gdshader`.
These are original procedural assets. The added decoration has no collision;
the prepared map retains 1,118 navigation polygons. Medium quality keeps bloom
enabled specifically for Neon Circuit; Low retains the emissive art without it.

Art-pass checks: **0 script failures**, **595/595 content checks**, and
**100/100 focused integration checks**, including the existing physical
traversals. Final close-up screenshots of the arena, arcade and entrance were
reviewed at Medium quality in `.artifacts/screenshots/neon-art/`. Review caught
and corrected reversed/overlapping labels, washed-out marquee lettering and
entrance text intersecting its lintel. Cosmetic label corrections were also
applied to the saved scene without invalidating its baked lighting.

Art-pass evidence: `.artifacts/logs/neon-art-delivery.log`,
`.artifacts/reports/neon-art-integration.json`, and
`.artifacts/logs/neon-art-review.log`.

Short performance check: native Metal, Medium, 1920 × 1080, 16 players,
seed 1201, 30 seconds of warm-up followed by 60 measured seconds. Average
**60.02 FPS**, p95 **20.425 ms**, p99 **22.584 ms**, zero frames over 50 ms;
the window was focused for every measured frame. This **misses** the project's
p95 ≤ 20 ms acceptance gate by 0.425 ms; the benchmark's `passed` field is false.
It is not a sustained thermal soak. The initial Vulkan benchmark was stopped
during startup and provides no performance evidence. Results:
`.artifacts/benchmark-neon.json` and
`.artifacts/logs/neon-art-metal-benchmark.log`.

The final Mac app was rebuilt, passed strict code-signature verification, and
completed **all 21 packaged-game smoke steps on Neon Circuit** using Metal.
The final script check has **0 failures** and the final content suite remains
**595 passed / 0 failed**. Evidence: `.artifacts/neon-art-export-smoke.json`,
`.artifacts/logs/neon-art-package-console.log` and `.artifacts/export-build.json`.

Human balance/fun testing has not been measured.
The bake logs retain the project's recognized Godot editor teardown diagnostics;
the engine wrapper accepted the bake and the content checks verified its output.

## Arena expansion and vendor rebuild — October 24, 2026

Added two 36 × 8 m enclosed annex wings to the original 32 × 32 m arena,
adding approximately 56% more floor area. Existing north/south doors connect
to the wings; each wing has two outer exits and east/west side entrances.
Three staggered wall islands split each wing into parallel lanes, with new
bot route anchors, sector signs, cosmic floors and baked practical lights.
The original reactor and ramp-accessible overlooks remain in place.

Rebuilt all six food stalls as open-front service bays with recessed menus,
side walls, worktops, registers, equipment, awning supports and individual
neon branding. Removed the old duplicate snack signage and loose trash bags.

Expansion verification:

- Script validation: **0 failures**.
- Navigation regenerated: **1,247 polygons**.
- Focused integration: **104 passed / 0 failed**, including both teams
  reaching all four new annex navigation anchors.
- Existing physical checks: **32/32** ramp walks, **128/128** objective walks,
  **128/128** cache walks, **60/60** sampled route walks.
- Additional annex traversal: **48/48** walks through side entrances and
  internal/outer doors across four movement styles; zero stuck points.

Evidence: `.artifacts/logs/neon-expansion-*.log`,
`.artifacts/neon_expansion_paths.gd` and `.artifacts/neon_expansion_review.gd`.

- Final native Metal lighting bake: **LIGHTMAP BAKE PASS**; minimap regenerated.
- Vendor, annex and exterior screenshots rendered and visually reviewed in
  `.artifacts/screenshots/neon-expansion/`.
- Full content suite: **658 passed / 2 failed**. Remaining failures are
  `baked_lighting_ridgeline` and `baked_lighting_village`, unrelated maps with
  missing lighting bakes during concurrent workspace preparation. Neon lighting
  and content checks pass. The bake emitted the existing editor teardown
  diagnostics; review/minimap runs emitted texture-leak shutdown warnings.
- This update changes the source game and generated map. The packaged Mac app
  was not exported again, and no new performance benchmark was run.

## Arcade, outskirts and signage pass — October 27, 2026

Arcades rebuilt from two straight rows of four cabinets into themed zones
(cabinet pod, prize corner with claw machines, air hockey, racers, dance stage,
skee-ball) under a canopy with fascia signage on every edge. Cabinets take a
full transform so they can be grouped and angled. The outskirts gain north and
south shopfronts, a cinema, wall-top billboards, loading docks, EV and pay
islands, marked parking bays with detailed cars, food-court umbrellas, string
lights, dumpsters and a central planter sculpture, plus pylons, photo booths and
rides between the arcades and the lots.

Signage fixes: the overlapping canopy texts (INSERT COIN / HIGH SCORE over
ARCADE / PLAY BEYOND) and the inner-wall NEON CIRCUIT / ENTER THE GRID pair are
separated; EXIT, house-rules and annex exit labels that floated across door
openings now sit on boards above the door heads or on solid walls; murals no
longer hang over the side doorways; the scene-lit outer signs (which read dark
under baked lighting) use self-lit lettering; vendor menus use aligned columns;
the duplicate "02" sector number is now "05"; the bullet glyph is replaced.

The south lane arrow moved to the parking aisle (20, 0, 31). Cover count is
unchanged (the arcade cover that overlapped a deployment cover is replaced by
EV islands). The sources parse cleanly with gdtoolkit; the new solids were
checked against spawns, objectives, routes, cover spots and test points.
**Validated on macOS (Metal, Apple M2, Godot 4.7.2.stable):**
`python3 tools/dev.py prepare --map neon` — PREPARE PASS (1,597 navigation
polygons), LIGHTMAP BAKE PASS (native Metal bake, 41 s, replacing the earlier
CPU bake), content suite 660 passed / 0 failed. `minimap-bake --map neon` —
MINIMAP BAKE PASS (new layout). Full `test --suite integration` — 1,001 passed /
0 failed, including both teams reaching the upper gantry and every authored
level, spawn capsule clearance, spawn routes and marker reachability for cover
points, peeks, domination, hardpoints and the QA route. `capture --map neon` —
CAPTURE PASS; the arcade fascia (NEON ARCADE, PRIZE) and shopfront signs read
correctly with no mirrored or floating text in the captured views. The
`north_route` capture frames a wall at close range, so it shows little.
Not rerun: `benchmark --map neon` (last p95 missed the 20 ms gate by 0.4 ms).
