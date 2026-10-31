# Transit Works — original map concept

## Space and identity

Coordinates use Godot metres: Y up; X west/east, Z north/south (north is negative Z). Playable ground spans X −55…55 and Z −45…45. Keep the standard deployment footprint clear at each end; inspect shared deployment/objective placement before committing architecture. All following dimensions and coordinates are design targets to reconcile with the actual shared frame.

A working regional rail depot at cool late afternoon, with a warm-lit repair hall, inspection equipment, dispatch offices and fenced service yards. Realistic maintained construction with local grime, oil marks and faded safety lines. Use existing industrial props; a train model is optional, never a dependency. Static workshop equipment and service wagons can communicate the setting. Distant trackwork, sheds and catenary structures establish context beyond the playable boundary.

## Blockout targets

| Area | Approximate centre (X,Y,Z) | Size / role |
|---|---|---|
| Repair hall | (0,0,0) | 28 × 24 m, about 5.4 m tall; four entrances, machinery breaks cross-map views |
| North service lane | (0,0,-29) | Electrical rooms and tool storage; staggered cover |
| South loading lane | (0,0,29) | Pallets, freight and maintenance equipment; local covered pockets |
| West dispatch | (-26,0,25) | 12 × 10 m furnished office; two useful approaches |
| East dispatch | (26,0,-25) | Rotated counterpart; equal traversal utility |
| Elevated service crossing | near (0,3.2,-17) | Adapt shared bridge; approach from both ends, ground bypass |
| West/east deployment | shared defaults | Four clusters each, multiple protected exits |

The coordinates do not prescribe exact walls or obstacle positions. Preserve shared route and objective access, ramp clearance, capture views and spawn annexes. Reposition secondary structures instead of changing gameplay code.

## Routing and encounters

West spawn connects to north lane, hall and south lane; each leads to the opposing deployment area. Link both flanks to the hall near each end and at midfield. The crossing adds a short elevated contest without overlooking every exit. Break long unobstructed views with functional geometry, keeping clean silhouettes and legible enemy contrast. Do not place collisionless cover or deep decorative pits on routes.

Use approximately point-symmetric traversal and comparable cover value, with visually distinct west/east landmarks. Avoid blind spawn exits and dominant elevated positions. Low cover, standing cover and short open crossings should alternate; use the game's actual capsule and stance dimensions from source rather than invented character sizing. Door openings, ramps and furniture must support bots as well as players.

## Art and lighting

Palette: weathered off-white wall panels, desaturated blue-grey equipment, concrete and asphalt, yellow safety markings, warm repair-bay fixtures. North lane uses electrical cabinets; south lane uses loading equipment. Mark REPAIR HALL, DISPATCH, SERVICE and LOADING with existing signage helpers. Place clutter after colliders, using existing clearance helpers. Keep high-detail dressing outside movement envelopes and sight-critical windows.

Reuse a verified existing HDRI configuration first. Match sun direction to its sky, use current fixed exposure, bake practical fixtures, and retain reflection/light probes. Test first-person weapon and character visibility inside and outside.

## Production gates

1. Greybox: registry, routes, collision, markers, elevated access. Prepare and pass relevant content/integration checks.
2. Art: scanned surfaces, existing props, interior trim, signs, sky/backdrop, lighting and restrained decals. Prepare again.
3. Review: overhead, seven capture views and minimap. Walk all exits, ramps and interiors; inspect hidden blockers and spawn sightlines.
4. Evidence: deterministic match test and benchmark, exact results and limitations. Fix problems and repeat affected checks only.

The package requests one new map. No weapon, HUD, AI, movement, scoring, Zombies or existing-map redesign is required.
