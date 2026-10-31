> Current ice/environment implementation: see `GLACIER_REALISM.md`. This file
> also records superseded shape experiments and earlier build results.

# Glacier Peak / Fracture Basin — 2026-10-24

## Ground-up environment and layout replacement

The original industrial campus and the first facade-only revision are retired.
The playable map is rebuilt around a real curved glacier depression, a high
northern shelf and a narrow survey bridge. The old central radar building,
snowcat hangar, helipads, gondola cabins, fences and mirrored building grid have
all been removed. The footprint is now 112 × 100 m.

### What shapes combat

- A blue-ice river at -3.2 m forms a winding low route. Broad banks permit
  climbing and lateral movement; the navigation slope limit leaves a margin
  below the character's actual climb limit.
- A suspended wooden survey crossing at +3.8 m creates seven metres of vertical
  separation from the river. Both routes remain independently traversable.
- An icefall passage beneath a fallen serac anchors the southeast flank.
- Three small timber/corrugated expedition shelters with steep snow-loaded
  roofs sit on the northwest shelf, northeast relay ridge and southwest refuge.
- Irregular ice blades, snow-capped moraine and a continuous faceted escarpment
  provide cover and shape sightlines. There is no perimeter warehouse grid.
- The two teams' primary deployments are biased northwest/southeast, with
  alternate deployment pockets. Supply caches, routes, cover/peek pairs and
  objective anchors were all moved for the new layout.
- Scanned snow, blue ice, exposed rock, cold haze, survey markers and stronger
  alpine wind establish the setting. Ground impact audio now uses earth.

The visible snowfield and its triangle collider use exactly the same deformed
mesh. Raised routes, ground-level markers and stacked navigation are checked
against the saved map, not a hand-calculated approximation of another layout.

## Verification changes

`tools/verify_glacier_peak.py` now runs `glacier_geometry_probe.gd` against Godot's
actual physics and navigation. The old verifier encoded the retired building
positions and was unsuitable for this terrain. The new probe checks bridge and
river floor collision separately, their clearance, northern elevation, all 32
spawn capsules and both teams' access to the three shelters and both levels.

The traversal harness supports focused `--suite=traversal --map=glacier_peak`
runs, while full integration still defaults to every map. Glacier registers a
-5 m fall limit so the legitimate -3.2 m river is not mistaken for falling out
of the map. Other maps retain -1 m. The content suite checks physical ground
relief and triangle collision; its scanned-node threshold accounts for the
escarpment being batched into two meshes instead of many facade pieces.

## Results

- Script parse: 0 failures.
- Saved-map physics/navigation probe: 18 passed, 0 failed. The measured bridge
  floor is +3.8 m, river floor -3.2 m and clearance 7.0 m.
- Navigation: 1,406 polygons, rebuilt from the final collider geometry.
- Content suite: 622 passed, 0 failed, including 6.95 m of real ground relief.
- Glacier-focused integration: 165 passed, 0 failed.
- Traversal: 16/16 ramp walks, 128/128 spawn-to-objective walks, 128/128
  spawn-to-ammo walks and 60/60 sampled routes. No stuck points.
- Full 8v8 match: passed; score 69–100, simulation duration 138.22 seconds,
  175 contact samples.
- Directional lightmap/shadowmask, 1024 px minimap and labelled overview rebuilt.
- Five final clean views generated and reviewed in
  `.artifacts/screenshots/glacier_redesign/`.
- `git diff --check` passed.

The first movement run exposed overly steep riverbank sections. Broadening the
banks and baking navigation at 30 degrees eliminated all sampled movement
failures without changing the character controller. An initial 30-second
benchmark ran alongside the CPU-heavy headless match and missed the frame-time
threshold (59.97 FPS, p95 23.15 ms); the final isolated run passed: 60.06 FPS average, p95
18.560 ms, p99 20.204 ms, zero frames above 50 ms, at
1920 × 1080 Medium / Metal on Apple M2. The measured sample is 30 seconds after
30 seconds of warm-up; it is a short check rather than the 600-second endurance
run used for the original map. The source remained unchanged during this run.

## Limits

Competitive balance requires human playtesting. Performance measurements are
reported with their actual duration; a short run is not a full endurance test.
Godot's existing lightmap editor teardown diagnostics and seven texture RID
shutdown warnings are retained in logs.


## Final interior review

The final shelter views were corrected to include both interior and exterior
gable faces, timber roof linings and raised visual timber floors. The snowfield
no longer shows through inside the enclosed refuges. These are visual meshes;
the tested terrain and route collision remain unchanged.


## Delivered app

`builds/FPSMode.app` was rebuilt, ad-hoc signed and signature-verified. The final
packaged Glacier run passed all 21 smoke-test steps. Its content fingerprint
matches the final measured source: `8080b31f5393f9e5e1d6c215bbeac8495ea049b12b8c861add10df127ff30fec`.

The rebuilt app was reopened with Glacier Peak preselected. From the main menu,
choose Deploy / Team Deathmatch, then Start Team Deathmatch. The main menu's
background remains Airport; the selected match loads the rebuilt glacier basin.


## Ice form and shading refinement

The user requested less blocky ice while retaining fractured glacial forms.
An intermediate rounded-volume experiment was rejected and is not the delivered
shape. Foreground seracs now use irregular slab outlines, sloping fracture
faces, uneven crests and narrow eroded corner transitions. Their volume is not
an oval or ellipsoid. Shared area-weighted vertex normals remove mesh faceting
and UV-seam lighting breaks without rounding away the overall fracture shape.

The continuous basin escarpment now interpolates between its foot, wall and
snow crest rather than displaying three large planar bands. Distant mountains
have denser geometry and continuous shading. Snow accumulation uses normalized
interpolated normals so its transition no longer follows large triangle faces.

Visual meshes use higher sampling density. Collision uses the same shape
functions at lower density to limit physics cost. Ground, shelter placement,
bridge height and route layout remain unchanged.

- Script parse: 0 failures.
- Physics/navigation and geological shading: 21 passed, 0 failed.
- No hard shared-vertex normal seams in ice, glacier walls or mountains.
- Navigation rebuilt: 1,758 polygons.
- Walked 16/16 ramp paths, 128/128 spawn-to-objective paths, 128/128 supply
  paths and 59/59 sampled routes without stuck points.
- Content: 622 passed, 0 failed.
- Directional lighting and minimap regenerated; five rendered views reviewed.
- `git diff --check` and verifier Python compilation passed.
