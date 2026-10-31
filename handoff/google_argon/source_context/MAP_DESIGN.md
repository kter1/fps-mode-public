# Maps

Six maps are registered in `content/manifest/map_list/`: Foundry and Ridgeline
are the compact modern sites described first; Harbor, Village, Airport and Blackout Station follow in their
own sections below. Every map shares the frame, rules, lighting pipeline and
verification described here.

## Foundry and Ridgeline

The October 16 revision replaces the previous oversized maps in response to the
user's request for smaller, more realistic modern environments. Foundry is now
110 × 90 m (9,900 m², 75% less area); Ridgeline is 120 × 96 m (11,520 m², 76% less
area). Architecture, doors, people and equipment retain their metre scale.

Both of these layouts have three routes, lateral connections, four entrances to
principal buildings, four spawn clusters per team and furnished deployment
annexes, an elevated maintenance walkway reached from either end, 16 spawn
markers per team, at least 36 authored
cover/peek pairs, eight ammunition caches, three domination anchors and five
hardpoint anchors. Only team deathmatch has rules. Matches run 8v8 (16 roster slots).

Foundry is a contemporary light-industrial assembly facility: an enclosed central
hall, dispatch/service offices, power rooms, freight loading and equipment lanes.
Ridgeline is a contemporary communications campus: glazed operations and
engineering buildings, a paved central courtyard, communications and logistics
wings. Paved sidewalks, common roof trim and drainage, grouped equipment bays,
planted courtyard cover and furnished service buildings give the site a consistent
function. Freestanding spawn baffles are replaced by receiving/security annexes.
The former enormous terraces, cone trees and triangulated mountain backdrop
are removed. Beyond the solid boundaries, Foundry has an industrial plain and
skyline, and Ridgeline has low wooded hills with fir forests (no mountains).

Surfaces use CC0 photoscanned 2K materials from Poly Haven and ambientCG
(concrete, paving, painted panels, corrugated and rusted steel, brick, wood,
gravel, grass and rock) with albedo, OpenGL normal and ARM maps at true world
scale. A shared surface shader adds grime at wall feet and edge wear; the ground
uses a splat shader. Edges are bevelled; windows have actual openings, mullions
and glass backed by matching bullet-blocking collision. Freight containers
measure 6.05 × 2.44 × 2.59 m. Props (barrels, generators, IBC containers, carts,
shelving, cars, barriers, lamps, ducts, pipes) are normalized to physical scale;
cover-sized props carry collision and are registered as cover points. Leak, damp,
patch and road-marking decals break up large surfaces. Every map collider is
tagged with its surface ("concrete", "metal", "wood" or "earth") so bullet
impacts use matching particles and decals.

Lighting: each map has a photographed HDRI sky (misty 28° sun for Foundry,
partly cloudy 48° sun for Ridgeline; overcast for Harbor and clear 43° for Village,
see below) with the directional sun matched to it, AgX
tone mapping, practical-camera auto exposure, SSAO and SSIL, light haze and
volumetric fog. LightmapGI bakes at MEDIUM quality with directional lightmaps,
shadowmask and light probes, so soldiers and the first-person rig receive bounced
light. Interiors use baked fluorescent fixtures and a reflection probe per
building. All delivered sources, license records and hashes are committed under
content/ (see content/manifest/maps.json).

Map generation, marker normalization, navigation and lighting baking run during
preparation, never during a match. CompactMapBuilder contains the active layout;
MapBuilder provides shared geometric building utilities. Game rules remain in
MatchWorld and the mode. Repeated decorative parts use spatial MultiMesh groups;
their transforms are saved in MapArena.instance_batches and the MultiMeshes are
built when the map loads, because headless preparation cannot store MultiMesh
instance data.
Buildings use prepared face UVs, tangents and shared materials, keeping the
scanned surface detail while avoiding triplanar sampling on their large surfaces.

The smaller maps deliberately prioritize quicker contact over the original
large-map 15–25 second target. Contact timing and balance need measurement and
human feedback; a temporary compact-map inspection range is 5–20 seconds.
Scanned textures improve realism, but original architecture and limited prop
variety do not constitute AAA photorealistic art. Visual inspection is recorded
separately from automated physics checks; scripted routes are not human playtests.

Respawns use a fixed three-second timer. Safe-point selection penalizes recently used clusters and the actor’s previous location, while always rejecting occupied or obstructed capsules. A recorded killer-view replay plays during the timer and Space/F skips back to the countdown. Its 20 Hz history is bounded to 72 snapshots; playback interpolates recorded actor poses and aim, never enemy live positions, and cannot cause damage.

## Harbor

Harbor is berth 3 of a working container terminal at overcast late afternoon
(110 × 90 m, `game/maps/layouts/harbor.gd`). The quay edge runs along the south
side with open water beyond it, and a harbour basin drops away past the kerb to
a far shore about 300 m out. Spawns sit in gate houses at the short ends, and the
layout is mirrored across the centre line so both teams get the same cover.

- **North lane:** Warehouse 7, a corrugated steel shed on a concrete plinth with
  racking and pallets on the ground floor. A steel mezzanine runs along the
  yard-side wall at 3.6 m and is reached by a ramp at each end; its louvred
  windows look over the yard. The warehouse sits between the dock office and
  customs, with a service road to its south.
- **Middle lane:** the container yard. Mirrored blocks of 40 ft boxes stacked one
  to three high, with 2.3–4.8 m alleys and a central east-west street broken by a
  single box turned across it. Painted slot outlines and row numbers mark the
  blocks.
- **South lane:** the quay apron under two ship-to-shore cranes, with hatch
  covers, a straddle carrier, bollards, rail stops and the quay edge itself.
- **Key areas** (overview labels): WAREHOUSE 7, CONTAINER YARD, BERTH 3 QUAY.
- **Upper floor:** the warehouse mezzanine at 3.6 m. Every team must reach its test
  point (`tests.upper_point` = 0, 3.6, −23).
- **Lighting:** the overcast Poly Haven HDRI with a 22° sun, a warm-white sun
  colour and light haze.
- **Assets:** Poly Haven rusty metal, a wooden crate and an ocean buoy; ambientCG
  leak and road-marking decals. Licences are in `content/licenses/` and hashes in
  `content/manifest/maps/harbor.json`.

## Village

Village is a partly overgrown Eastern-European farming village in summer
(110 × 90 m, `game/maps/layouts/village.gd`). Its layout is point symmetric about
the church square, so every authored piece has a twin turned half a circle.

- **Middle lane:** a cobbled main street crossing a small square between the
  church (whitewashed nave, bell tower and spire over the porch) and the old village
  hall with its deep porch. Two-storey plaster houses with masonry stairs face the
  street.
- **North lane:** an orchard, a graveyard and farm sheds. The church's side doors
  give a route through the nave.
- **South lane:** fenced back gardens behind rubble-stone walls, with cover on both
  faces.
- **Team starts:** each team deploys inside a timber barn and its farmyards at one
  end of the village.
- **Key areas** (overview labels): ORCHARD + BARN, CHURCH SQUARE, BACK GARDENS.
- **Upper floor:** the two-storey houses have an upper floor at 3.2 m (the walkable
  slab top), reached by stairs along one wall. The test point
  (`tests.upper_point` = −20, 3.2, −18) sits on one of these floors.
- **Terrain and sky:** grass and hills beyond the boundaries with a forest backdrop
  (no mountains), under a clear Poly Haven HDRI with a 43° sun.
- **Assets:** Poly Haven cobblestone, plaster, stone, clay and reed roofs, planks,
  painted furniture and garden props, plus ambientCG foliage and leaf sets.

Authoring notes from this map, for future work:

- Soft sun shadows cost 4–5 ms of GPU time at Medium where many surfaces are
  shaded (trees and eaves). Village sets the light's angular distance to 0 from
  its layout; a registry knob in the shared lighting setup would be cleaner.
- Navigation uses a 0.5 m agent radius, which erodes 1.6 m doors shut. Doors need
  at least 2.0 m, and stairs must stay under about 23° (no more than 0.25 m climb
  per 0.5 m cell) or the navmesh breaks into ledges.
- The shared foliage shader re-flips back-face normals, so flat grass cards with
  upward normals render black in shade. Ground grass has its own shader
  (`grass_clump.gdshader`, below).
- Plants are placed last, after every collider exists: `MapNature.scan_clearance` reads
  the map's StaticBody3D shapes, `fit` slides a bush or tree (crown radius, height) off
  walls, fences, props and trunks (dropping it when it cannot), and the grass field keeps
  0.3 m from any solid. The content suite (`vegetation_clear_of_solids_<id>`) checks the
  saved scene.

## Airport

Airport is a compact 112 × 88 m regional airport (`game/maps/layouts/airport.gd`,
registry id `airport`), selected by default. The footprint is 26% smaller than the
first 128 × 104 m draft. The terminal functions and airside relationship were
informed by Santa Barbara Airport's [terminal addition plan](https://flysba.santabarbaraca.gov/sites/default/files/2023-05/Terminal%20Improvement%20Design%20Concept.pdf);
the playable layout and aircraft are original.

- **Flow:** three recognizable combat areas anchor the map: terminal, baggage
  claim and passenger aircraft. Broad ground connections join them, with a
  maintenance hangar on the east flank and a shuttle court on the south flank.
  The terminal and hangar form the rear boundary, eliminating the thin road
  behind them. Extra check-in partitions, checkpoint chicanes, staff booths and three small
  apron annexes have been removed. Players can see the next destination and
  choose a route around isolated cover.
- **Terminal:** check-in desks and a central island lead to one security line
  with two 6 m passages. The gate lounge is open, with seating, a cafe and flight
  information displays. Gate Services attaches directly to the terminal through
  its A1 doorway; it has broad exits onto the apron.
- **Baggage:** the four-entrance hall retains its oval carousel and central
  arrivals display. Its entrance canopies and baggage-transfer shelter have open
  sides. The sorting belt guard provides local cover without making corridors.
- **Aircraft:** three 3.4 m boarding ramps reach the 2.6 m cabin floor. Front-left,
  rear-left and rear-right doors let players cross the cabin, flank through the
  rear vestibule, or return to the apron. The visible hull, wings and doorways
  have matching collision. Domination's third point is inside the cabin; rotating
  hardpoints also visit the hangar entrance and shuttle court.
- **Apron and flanks:** the aircraft is visible from the main boarding approach.
  Two hangar tool banks, shuttle buses, luggage carts, tractors and a fuel bowser
  provide cover. The southern shuttle shelter has a narrow information panel and
  open bypasses. Ground Operations remains a recognizable eastern anchor.
- **Boundary:** the security fence follows the smaller footprint. Runways, distant
  hangars and the control tower establish the wider airport beyond playable space.
- **Navigation and review:** 0.75 m obstacle clearance on a 0.25 m horizontal and
  0.1 m vertical grid retains headroom inside the cabin. The movement suite walks
  every ramp in both directions and checks spawn-to-objective, supply and random
  routes. `tools/airport_sightlines.gd` checks six direct ground connections and
  four views of destinations, including the aircraft. Full-map sightline statistics
  are diagnostic; driving every ray length down previously produced the maze.
- **Presentation:** baked daylight and interior lighting, navy/teal wayfinding,
  procedural terrazzo flooring, and the existing licensed CC0 surfaces and props.

Movement, wall collision, in-game captures and packaged-map verification are
recorded in `.artifacts/airport-*.json`, `.artifacts/logs/` and
`.artifacts/screenshots/airport_review/`.

## Blackout Station

Blackout Station is a coastal power station at dusk during a grid failure
(110 × 90 m, `game/maps/layouts/blackout.gd`, registry id `blackout`). This layout
replaces the earlier radar complex. Teams deploy from the west gatehouse and east
stores, with three connected lanes running east-west and cover mirrored across X = 0.

- **North switchyard:** three main transformers between concrete blast walls,
  lattice gantries, breaker rows and relay kiosks. Personnel doors connect the
  switchyard road to the turbine hall.
- **Turbine hall:** a 42 × 22 m brick building with two turbine-generator sets,
  an overhead crane, roller doors at both ends and side entrances. Two ramps reach
  the control deck at 3.4 m along the north wall. Switchgear and machinery divide
  the floor routes and interrupt the sightline between the gable doors.
- **South intake:** an accessible pump house between two fuel-oil tanks in low
  containment bunds, overhead pipe racks and unloading bays. The seawall promenade
  connects the south flank around the buildings, with mooring blocks and an intake
  screen gantry providing cover.
- **Setting:** palisade fences bound the site on three sides. Beyond them are a
  boiler house, chimney, cooling tower and transmission lines extending into wooded
  hills. The seawall overlooks an animated bay between two headlands, with rock
  armour and cooling-water outfalls below the promenade.
- **Markers:** 16 spawns per team in four clusters, eight caches, three domination
  anchors and five hardpoints. Registered navigation points verify the pump-house
  floor and control deck at (0, 3.4, −8.5), including access from both teams.
  Navigation uses a 0.75 m obstacle margin on a 0.25 m grid to keep the capsule
  clear of corners while retaining access between the ramp parapets. The smoke
  visibility fixture uses open ground south of the hall rather than the occupied
  centre aisle.
- **Lighting and assets:** warm low sunlight under an overcast HDRI, generator-fed
  floodlights, amber emergency fittings, green exit signs, baked lighting and fixed
  exposure. The map reuses the existing verified CC0 materials, props and Harbor's
  animated water shader.

Reports and screenshots from the earlier radar layout do not validate this
replacement. Current automated checks and packaged-game checks are recorded in
`.artifacts/reports/` and `.artifacts/blackout-v2-package-check.json`.

## Ground grass

Ridgeline, Village and Blackout Station grow their lawns with `MapNature.grass_field`
(Foundry and Harbor have none). Each clump is three crossed 0.5 m cards carrying one of
four clumps of `content/materials/grass_clump/` (colour, opacity, normal): the sheet's
individual blades (CC0, ambientCG Foliage001) cut out, narrowed, bent and stamped in
dense fans by `tools/generate_grass_clumps.gd` (run through `dev.py ingest --domain maps
--map village`). The field is a jittered 0.85 m grid of clusters (a main clump with a few smaller ones), thinned by two noise layers (patches
of sward about 25 m across with graded rims, and a fine lumpiness), so density varies
naturally and no lone tufts appear; the layout's suitability function returns 0 on
tracks, cobbles, gravel, snow, floors, building footprints and within 0.3 m of a solid.
Clumps are batched per 16 m cell and variant as MultiMeshes without shadows.
`grass_clump.gdshader` varies colour per clump and in large fresh/dry patches,
shrinks clumps into the ground over the last third of the fade distance (36 m Village,
38 m Ridgeline inside the walls, 48 to 56 m on the verge outside), lowers the alpha
threshold with distance so mipmaps do not thin the blades, and sways the tips by under
3 cm.

## Adding a map

Every map is data plus one script, so map work in parallel worktrees never edits
a shared file. A new map `<id>` (lowercase, used in file names and `--map`) is:

1. **Registry entry** `content/manifest/map_list/<id>.json`. Copy an existing one
   and change: `display_name`, `menu_subtitle`, `order` (menu position), `layout`,
   `seed`, `extent` ([x, z] metres), `style` (accent colour, `wall_kind`,
   `ground_impact`, `ground.layers`/`tint`, `asphalt_patches`, `lane_arrows`,
   `ground_clutter`, `terrain` kind `plain` or `hills` with its layers,
   `backdrop` `skyline` or `forests`), `lighting` (HDRI, measured `sun_u` and
   `sun_elevation`, `sky_turn`, sun/sky energy, haze, fog), the seven `capture`
   cameras, `overview` labels and optional `tests.upper_point` (a point on an
   upper floor every team must reach). `menu_backdrop` marks the map shown
   behind the main menu; only one map should have it. The game (`MapCatalog`),
   `dev.py`, the bake plugin, tests, report and review tools all read this folder.
2. **Layout script** `game/maps/layouts/<id>.gd`, extending `MapLayout`.
   Override `build(b)` to place buildings, cover and props through the
   `CompactMapBuilder` helpers (`modern_building`, `bridge`, `freight`, `cover`,
   `prop`, `box`, `road_markings`...) and `ground_splat(b, x, z, noise)` for the
   ground layers. `boundaries`, `deployment` and `objectives` default to the
   shared compact frame (perimeter, 2 × 16 spawns in four clusters, 8 ammo
   caches, routes, domination, hardpoints, QA route); override them only if the
   map needs a different frame, keeping the counts the tests check. Do not add
   map ids to the shared builder files.
3. **Asset sources** (only for assets not already in `content/asset_sources/maps.json`):
   `content/asset_sources/maps/<id>.json`, same format as the shared list. Fetch with
   `python3 tools/dev.py fetch --domain maps --map <id>` (or `ingest`); the lock goes to
   `content/asset_sources/maps/<id>.lock.json` and provenance to
   `content/manifest/maps/<id>.json`, merged with the shared manifest at load.
4. `python3 tools/dev.py prepare --map <id>` builds, navigates and bakes just that map
   into `game/maps/generated/<id>.*`. Then `capture --map <id>`, `inspect-map --map <id>`
   and `benchmark --map <id> --seed 1201 --seconds 600`.

The content suite (`registry entry`, saved scene, footprint matching `extent`,
16 + 16 spawns, cover, caches, objectives, navigation, baked directional
lightmap, HDRI sky, probes, scanned surfaces, props, batches) and the
integration suite (roster, spawn-to-route connectivity, clear spawn capsules,
upper floor when `tests.upper_point` is set) iterate every registered map
automatically; `release_verify.py` and `report.py` add per-map stages too.

Budgets on the fanless M2 Air: compact footprint about 110 × 90 m (Ridgeline is
120 × 96); Medium preset at 1920 × 1080 averages at least 60 FPS with p95 frame
time at or under 20 ms; at most 2.5 M visible triangles and 2,500 draw calls in
the worst view. Renders, bakes and benchmarks queue on the shared render lock
(see README), so run them only through `dev.py`.

## Layout references

The official guides informed general routing choices; all geometry is original.
Vista describes three routes linked through multiple paths and interiors, which
informed the connected building entrances here. Hideout demonstrates staggered
cover and a central bridge; Protocol illustrates alternate approaches around,
above and below contested positions. The service walkway has approaches at both
ends and can be bypassed at ground level.

- [Vista](https://www.callofduty.com/guides/multiplayer-maps/call-of-duty-guides-modern-warfare-iii-multiplayer-map-guide-vista)
- [Hideout](https://www.callofduty.com/guides/blackops6/multiplayer-maps/call-of-duty-guides-black-ops-6-multiplayer-map-guide-hideout)
- [Protocol](https://www.callofduty.com/guides/blackops6/multiplayer-maps/call-of-duty-guides-black-ops-6-multiplayer-map-guide-protocol)


## Zombies survival maps

Dead Current and Dead Air each occupy a 76 × 64 m floor footprint with six connected zones, seven purchasable adjacent-room doors and fourteen real window openings. Four starting-room entries become two entries in each additional room. Separate saved floor navigation regions connect only through purchased door links; player-only collision keeps windows one-way for enemy entry. Indexed floor navigation excludes expanded equipment footprints. Pursuit preserves unsmoothed portal waypoints, because funnel smoothing across consecutive links could cut through a separating wall.

The six zone centers form a 2 × 3 grid. Seven adjacent edges form two closed circulation loops when opened. This implements the planned two-loop function with physically adjacent passages rather than the research sketch's eight-edge graph. Both maps have five wall guns, five perk machines, a power switch, an Overcharger, an electric trap and three box sites.

**Dead Current:** Intake Office → Service Yard → Switchyard across the south; Workshop → Turbine Hall → Control Room across the north. Twin turbine vessels, pipe racks, workshop equipment, brick interiors, yellow directional signage and dusk light establish the power-station identity. Service Yard and Switchyard are open overhead.

**Dead Air:** Ticket Office → Baggage Service → Loading Apron across the south; Security Hall → Gate Lounge → Maintenance Room across the north. Airport plaster, baggage conveyors and screening equipment, service carts, blue departure signage and terminal lighting establish its identity. The apron is open overhead.

Both maps intentionally reuse the validated topology and art kit. They are original layouts, not recreations of Call of Duty maps. Runtime purchase markers and tuning live in `content/data/zombies/`; prepared scenes and baked lighting live beside the existing TDM scenes.

The reference-driven ruin pass adds scanned broken benches/chairs/crates, discarded bags, small nonblocking plaster and paper debris, damp wall/floor staining, worn timber flooring in Dead Current's office rooms, overhead beams/columns, service pipes and electrical hardware. Ticket Office and Intake Office have a sealed staircase landmark with an authored navigation exclusion; it does not introduce an upper-floor route. Tall dressing remains inside existing exclusion islands or receives its own clearance. No new random gameplay blockers are spawned during a match.
