# Neon Circuit — handoff to a local Claude Code session

## Paste this into the new local chat

> Continue the Neon Circuit (laser tag map, id `neon`) update in this repo. Check out
> and pull branch `claude/youthful-fermi-246mxn`, then read
> `handoff/neon_circuit/HANDOFF.md` and finish the steps under "What is left".
> Run every command yourself. I don't want to use the terminal. Commit and push
> the results to the same branch, and tell me plainly what passed and what didn't.

## Where things stand

Branch: `claude/youthful-fermi-246mxn` (pushed). Commits on top of `6722a8e`:

1. `cd35011` **Layout and signage.** These files changed:
   - `game/maps/layouts/neon.gd`
   - `game/maps/layouts/neon_art.gd`
   - `content/manifest/map_list/neon.json`
   - `MAP_DESIGN.md`
   - `NEON_CIRCUIT_VALIDATION.md`

   Changes:
   - **Arcades.** The arcades at x = ±30 are rebuilt into themed zones:
     - an angled five-cabinet pod
     - a prize corner with claw machines and a token changer
     - air hockey
     - three racing machines
     - a dance stage
     - two skee-ball lanes
     - fascia signs on all four canopy edges
   - **Outskirts.** Additions around the edges:
     - shopfronts on the north and south walls, plus a cinema
     - billboards on top of the walls
     - loading docks with trucks
     - marked parking bays with detailed cars, pay booths and EV islands
     - umbrellas, string lights and dumpsters in the food court, plus a plaza sculpture
     - pylons, photo booths and rocket rides
   - **Signage fixes:**
     - texts that overlapped are separated
     - labels that floated across door openings are moved onto boards above the doors
     - scene-lit signs now use self-lit text
     - menus use aligned columns
     - the duplicate "02" label is now "05"
     - the "•" glyph is replaced
   - **Gameplay data.** The south lane arrow moved to (20, 0, 31). The total cover count is unchanged.
2. `cc9f74f` **Regenerated map.** Updated `game/maps/generated/neon.tscn` and the
   `neon_lightmap.*` files, and added cached part `.res` files for
   `exterior_aircon_unit` and `utility_box_02`. This was built in a cloud
   container with the pinned Linux build
   `4.7.2.stable.official.ed1daf0bf`, running on CPU (Mesa lavapipe, no GPU).
   - Script check: **0 failures**.
   - `tools/prepare.gd --map=neon`: **PREPARE PASS**, with 1,597 navigation
     polygons (previously 1,247).
   - Editor lightmap bake: **LIGHTMAP BAKE PASS** in 1,300 s. The only error was
     the known teardown line "Can't use get_node() with absolute paths…", which
     `dev.py` already allows.

## What is left

Run these on the Mac with the project's own tooling (Metal GPU):

1. `python3 tools/dev.py prepare --map neon`. This rebuilds the scene and
   navigation, re-bakes the lightmap on Metal and runs the content suite. Do
   the full re-bake: the existing bake ran on a CPU software renderer, so it
   should be replaced by a native one.
2. `python3 tools/dev.py minimap-bake --map neon`. **Not done yet.**
   `content/minimaps/neon.png` still shows the old layout.
3. `python3 tools/dev.py test --suite content`, unless step 1's content run
   already covers it.
4. Integration and traversal checks for `neon`. Earlier validation used a
   focused runner, `.artifacts/neon_test_runner.gd`, described in
   `NEON_CIRCUIT_VALIDATION.md`. It is a copy of the integration runner limited
   to `neon`. If it isn't in `.artifacts/`, run
   `python3 tools/dev.py test --suite integration`. The full suite takes longer
   because it covers every map. The checks to watch:
   - both teams reach `tests.upper_point` and the annex navigation points
   - spawn and marker clearance
   - ramp, objective, cache and route walks
5. Look at the map with `python3 tools/dev.py capture --map neon` or
   `python3 tools/dev.py run --map neon`. Check that:
   - the arcade signs read correctly
   - no text is mirrored, overlapping or floating
   - the billboards and shopfronts look right
6. If anything fails, fix it in `neon.gd` or `neon_art.gd`, prepare again, then
   add the results to the October 27 section of `NEON_CIRCUIT_VALIDATION.md`.
   Its "Not yet run" line needs updating either way.
7. Commit the regenerated files with the logs' pass lines in the message, then
   push to `claude/youthful-fermi-246mxn`. Only open a pull request if the user
   asks for one.

## Things to watch for

- **Possible marker warnings.** `prepare.gd` moves gameplay markers onto the
  navmesh and fails if it can't. Two spots are worth a look if it complains:
  - Some parked cars sit about 0.77 m from cover peek points at (±16.1, 37.2)
    and (±27.9, 37.2). If one is flagged, empty bays 3 or 6 in `_parking`.
  - The QA point (−19, 0, −34) next to the TACO BYTE stall was already tight
    before this change.
- **Covered car.** `covered_car` is placed with a fit check that tries both
  orientations, so it may be missing if neither fits.
- **Performance.** About 14 static practical lights were added. The last
  benchmark already missed the p95 ≤ 20 ms gate by 0.4 ms, so rerun
  `python3 tools/dev.py benchmark --map neon` if performance matters.
- **Shared code.** Shared builder code (`compact_map_builder.gd`,
  `map_builder.gd`) was not changed. Every edit is local to the Neon Circuit
  map.
