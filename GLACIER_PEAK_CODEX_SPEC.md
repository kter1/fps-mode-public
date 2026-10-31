# GLACIER PEAK (`glacier_peak`) — Lead Level Design Blueprint & Self-Contained Codex Implementation Specification

**Target Engine & Project:** Godot 4.7.2 (`FPS Mode` — `CompactMapBuilder` / `MapLayout` Pipeline)

**Map Identifier (`id`):** `glacier_peak`

**Display Name:** `Glacier Peak`

**Menu Subtitle:** `TDM  /  ALPINE TELEMETRY DOME, GONDOLA STATION & HELIPADS`

**Registry Order & Deterministic Seed:** `order: 70`, `seed: 2410`

**Supported Modes:** `["tdm"]` (with authored `domination` and `hardpoints` anchors for objective modes and bot routing)

**Design Precedents:** Call of Duty [*Summit*](https://www.callofduty.com/guides/blackops7/multiplayer-maps/s03/summit) (central command rotunda + upper catwalk + cliffside gondola cars), [*Sub Base*](https://www.callofduty.com/guides/multiplayer-maps/call-of-duty-modern-warfare-iii-play-maps-core-multiplayer-map-guide-sub-base) (high-contrast snow/industrial sightlines), [*Vista*](https://www.callofduty.com/guides/multiplayer-maps/call-of-duty-guides-modern-warfare-iii-multiplayer-map-guide-vista), [*Hideout*](https://www.callofduty.com/guides/blackops6/multiplayer-maps/call-of-duty-guides-black-ops-6-multiplayer-map-guide-hideout), and [*Protocol*](https://www.callofduty.com/guides/blackops6/multiplayer-maps/call-of-duty-guides-black-ops-6-multiplayer-map-guide-protocol).

## Stage 0: Greybox Blockout First-Pass Summary

Before adding any architectural trim, `SurfaceTool` fairings, or CC0 props, the greybox blockout establishes the complete collision, line-of-sight, and navigation mesh topology using only primitive `StaticBody3D` / `BoxShape3D` volumes and `pierced_wall()` apertures:

```
NORTH (-Z = -45.0 m) — GRANITE RIDGE CUTTING & BLAST WALL
+---------------------------------------------------------------------------------------------------+
| [BLUE CLUSTER 1]          [B2: SNOWCAT HANGAR & WEATHER LAB]                     [RED CLUSTER 1]  |
| (-51.5..-45.5, -34)       Center (0, 0, -33.0) | 40.0 x 14.0 x 6.8 m             (45.5..51.5,-34) |
|                           6 Portals (2N, 2S, 2E/W) + Weather Balloon Rig                          |
|                                                                                                   |
|      [B4: AVALANCHE BUNKER W]     [V1: SNOWCAT W]         [V2: SNOWCAT E]   [B5: AVALANCHE E]     |
|      (-39.0, 0, -22.0) 10x10m     (-25.0, 0, -19.5)       (25.0, 0, -19.5)  (39.0, 0, -22.0)      |
|                                                                                                   |
| [BLUE CLUSTERS 2 & 3]     [B1: CRYO-RADAR ROTUNDA & GEODESIC DOME]               [RED CLUSTERS]   |
| [H1: WEST HELIPAD]        Center (0, 0, -6.5) | 28.0 x 16.0 x 7.6 m              [H2: EAST PAD]   |
| (-46.0, 0, 0.0) R=7.2m    6 Ground Portals + Twin Cryo Cores (+-5.5, 0, -6.5)    (46.0, 0, 0.0)   |
|                           +-----------------------------------------------+                       |
|                           | [E1: ELEVATED CATWALK & CLIFFSIDE OVERLOOK]   |                       |
|                           | Gallery (0, 3.4, -0.3) + Balcony (0, 3.4, 4.5) |                       |
|                           | W Ramp (-15->-4, Z=3.3) | E Ramp (15->4, Z=3.3)|                      |
|                           +-----------------------------------------------+                       |
|      [C1: WINCH CANOPY W]                                                   [C2: WINCH CANOPY E]  |
|      (-39.0, 0, +20.0) Open                                                 (39.0, 0, +20.0) Open |
|                           [G1: GONDOLA 01 (DOM A)] [B3: BULLWHEEL] [G2: GONDOLA 02 (DOM C)]       |
| [BLUE CLUSTER 4]          (-21.0, 0, +30.0)        (0, 0, +33.0)   (+21.0, 0, +30.0) [RED CL 4]   |
| (-51.5..-45.5, +34)       12.0 x 4.2 x 3.4 m       16.0 x 11.0 m   12.0 x 4.2 x 3.4 m (45.5..51.5)|
+---------------------------------------------------------------------------------------------------+
SOUTH (+Z = +45.0 m) — SHEER ALPINE GORGE RAILING & SUSPENDED HAUL CABLES

```

### Greybox Invariants (Must Hold Before Art Pass)

1. **Zero Foundry Prefab Overlap:** `0` calls to `b.modern_building()` and `0` calls to `b.bridge()`. None of the 5 enclosed buildings (`B1` at `(0,-6.5)`, `B2` at `(0,-33)`, `B3` at `(0,33)`, `B4` at `(-39,-22)`, `B5` at `(39,-22)`) lie within `6.0 m` of any `foundry.gd` building center (`(0,0)`, `(±26,25)`, `(±26,-27)`, `(±44,0)`).

2. **Ground Plane Constraint (`Y = 0.0 m`):** `CompactMapBuilder` constructs a `110 × 90 × 0.7 m` ground slab with top surface at `Y = 0.0 m`. All primary ground floors sit at `Y = 0.0 m` (`InteriorSlab` visual overlays at `Y = 0.015–0.03 m` with `solid = false`), while the elevated gallery and cliffside overlook sit at `Y = +3.40 m`.

3. **Dual-Radius Navmesh Erosion Guarantee:** The layout sets `b.region.navigation_mesh.agent_radius = 0.75` and `cell_size = 0.25`. Every doorway is `>= 3.4 m` wide (`>= 1.9 m` clear after `2 × 0.75 m` erosion), every exterior passage between colliders is `>= 3.2 m` wide, and the West/East Overlook Ramps (`Z = +3.3 m`, width `3.2 m`, `Z ∈ [6.2, 9.4]`) sit flush against the Rotunda South Wall (`Z = +1.5 m`), eliminating narrow wall-to-ramp dead slots.

## 1. Theme and Visual Identity

* **Setting:** A high-altitude atmospheric research, cryo-radar, and aerial tramway complex perched on a snow-swept basalt mountain saddle at `2,800 m` elevation.

* **Time of Day & Skybox:** Crisp mid-morning alpine sunlight under the pre-approved CC0 HDRI [Poly Haven Kloofendal 43° Clear Pure Sky](https://polyhaven.com/a/kloofendal_43d_clear_puresky) (`res://content/sky/kloofendal_43d_clear_puresky_2k.hdr`), casting sharp directional shadows across snowdrifts and high-visibility orange/teal polar station architecture.

* **Color Palette & Readability Contrast:**

  * `GLACIER_SLATE` (`#1f2e3d`): Insulated corrugated steel exterior cladding on the Central Cryo-Radar Rotunda and North Snowcat Hangar.

  * `RESCUE_ORANGE` (`#d95326`): High-visibility polar trim on the Gondola Cabins, Tracked Snowcats, Bullwheel Drive Station, and doorway headers.

  * `CRYO_TEAL` (`#158594`): Interior acoustic panelling, cryo-cooling vessels, and wayfinding bands.

  * `HAZARD_AMBER` (`#eab308`): Safety railings, helipad landing rings, ramp curbings, and crane/bullwheel hazard stripes.

  * `ALABASTER_SNOW` (`#e8eef2`): Geodesic radome panels, roof snow caps, and exterior snow berms.

  * `BASALT_DARK` (`#23282d`): Structural steel H-columns, caterpillar tracks, cable bullwheels, and window mullions.

* **Silhouette Variety by Zone (Instant Callout Recognition):**

  * **Center (`B1`):** Faceted white-and-orange **Geodesic Radome Cupola (`R = 6.5 m`, apex `Y = 12.8 m`)** crowning the Cryo-Radar Rotunda.

  * **South Gorge (`B3`, `G1`, `G2`):** Open cliffside safety railing overlooking a sheer `400 m` mountain drop-off, with **twin horizontal steel cable bullwheels** (`R = 3.2 m`) and two **boardable rescue-orange Alpine Gondola Cabins** suspended from overhead steel hanger arms.

  * **North Ridge (`B2`, `V1`, `V2`):** Granite cliff cut (`rock_face_01`, `boulder_01`) framing the wide **Snowcat Maintenance Hangar** and two **sculpted Tracked Snowcat Groomers** with angled snowplow blades.

  * **West & East Ends (`H1`, `H2`):** Circular **Heated Concrete Helipads** (`R = 7.2 m`) with yellow `H` markings, perimeter deck lights, and flanking **Avalanche Radar Bunkers** (North) and **Open-Air Ski-Patrol Winch Canopies** (South).

## 2. Exact Playable Dimensions & Metrics

| Metric / Parameter | Exact Specification | Engine / Builder Binding | 
| ----- | ----- | ----- | 
| **Playable Footprint (`extent`)** | `110.0 m` (East-West `X`) × `90.0 m` (North-South `Z`) = `9,900 m²` | `"extent": [110, 90]` in `glacier_peak.json` | 
| **Playable Bounds** | `X ∈ [-55.0, +55.0]`, `Z ∈ [-45.0, +45.0]` | Bounded by `palisade` / cliff wall on W, E, N and `CliffSafetyRailS` on S | 
| **Minimap Orthographic Bounds** | `[-59, -59, 59, 59]` (`118.0 × 118.0 m` square) | Covers `100%` of playable extent with `4.0 m` E/W and `14.0 m` N/S margin | 
| **Ground Elevation (`Y`)** | `Y = 0.00 m` (top of `CompactMapBuilder` base slab) | `box("Ground", Vector3(0, -0.35, 0), Vector3(110, 0.7, 90))` | 
| **Upper Catwalk & Overlook (`Y`)** | `Y = +3.40 m` (top of walkable slab) | `DECK_Y = 3.4` (`tests.upper_point = [0, 3.4, -0.3]`) | 
| **Highest Architectural Apex** | `Y = +12.80 m` (Geodesic Radome apex at `(0, 12.8, -6.5)`) | Overview camera height safely clears all geometry | 
| **Player Physics Capsule** | Radius `0.35 m` (diameter `0.70 m`), standing height `1.80 m`, eye height `1.60 m` | Crouch height `1.05 m`; low waist cover height `1.20–1.35 m` | 
| **Navmesh Bake Parameters** | `agent_radius = 0.75 m`, `agent_height = 1.80 m`, `cell_size = 0.25 m`, `cell_height = 0.10 m` | `agent_max_climb = 0.25 m`, `agent_max_slope = 35.0°` | 

## 3. Coordinate System and Overhead Layout

* **Coordinate System:** Godot 4 right-handed meter coordinates:

  * **Origin `(0.0, 0.0, 0.0)`:** Center of the map on the ground plane, `2.0 m` south of the Cryo-Radar Rotunda center `(0.0, 0.0, -6.5)`.

  * **`-X` (West):** Blue Team deployment (`X = -51.5 .. -45.5 m`).

  * **`+X` (East):** Red Team deployment (`X = +45.5 .. +51.5 m`).

  * **`-Z` (North):** Granite Ridge & Snowcat Maintenance Hangar (`Z = -45.0 .. -18.0 m`).

  * **`+Z` (South):** Alpine Gorge Rim, Bullwheel Station & Gondola Cabins (`Z = +18.0 .. +45.0 m`).

  * **`+Y` (Up):** Vertical elevation in meters (`Y = 0.0 m` ground; `Y = +3.4 m` upper catwalk and cliffside overlook).

### Overhead Coordinate Grid (10 m Major Divisions)

| Zone ID | Structure / Landmark Name | Center `(X, Y, Z)` | Footprint `(W × D)` | Height `H` | Symmetry Relationship | 
| ----- | ----- | ----- | ----- | ----- | ----- | 
| **`B1`** | **Cryo-Radar Rotunda & Geodesic Dome** | `(0.0, 0.0, -6.5)` | `28.0 × 16.0 m` | `7.6 m` (`12.8 m` dome) | Mirror-symmetric across `X = 0` | 
| **`E1`** | **Elevated Catwalk & Cliffside Overlook** | `(0.0, 3.4, -0.3)` & `(0.0, 3.4, +4.5)` | `18.0 × 3.2 m` & `8.0 × 6.0 m` | `Y = +3.4 m` deck | Reached by W/E ramps at `Z = +3.3 m` | 
| **`B2`** | **Snowcat Hangar & Weather Lab** | `(0.0, 0.0, -33.0)` | `40.0 × 14.0 m` | `6.8 m` | Mirror-symmetric across `X = 0` | 
| **`V1` / `V2`** | **Tracked Snowcat Groomers W & E** | `(±25.0, 0.0, -19.5)` | `5.8 × 2.8 m` | `2.7 m` | Mirror-symmetric across `X = 0` | 
| **`B3`** | **Bullwheel Cable Drive Station** | `(0.0, 0.0, +33.0)` | `16.0 × 11.0 m` | `6.2 m` | Mirror-symmetric across `X = 0` | 
| **`G1` / `G2`** | **Boardable Alpine Gondola Cabins 01 & 02** | `(±21.0, 0.0, +30.0)` | `12.0 × 4.2 m` | `3.4 m` (`9.2 m` arm) | Mirror-symmetric across `X = 0` | 
| **`H1` / `H2`** | **Heated Helipad Decks W & E** | `(±46.0, 0.0, 0.0)` | `14.4 × 14.4 m` (`R = 7.2 m`) | `0.04 m` pad + `1.3 m` baffles | Mirror-symmetric across `X = 0` | 
| **`B4` / `B5`** | **Avalanche Radar Bunkers W & E** | `(±39.0, 0.0, -22.0)` | `10.0 × 10.0 m` | `4.4 m` | Mirror-symmetric across `X = 0` | 
| **`C1` / `C2`** | **Open-Air Ski-Patrol Winch Canopies W & E** | `(±39.0, 0.0, +20.0)` | `10.0 × 8.0 m` | `4.4 m` open canopy | Mirror-symmetric across `X = 0` | 

## 4. Major Buildings, Rooms, Roads, Elevations and Landmarks with Exact Coordinates

### 4.1 `B1` — Central Cryo-Radar Rotunda & Geodesic Dome (`(0.0, 0.0, -6.5)`)

* **Exterior Shell:** `28.0 m` (`X: -14.0 .. +14.0`) × `16.0 m` (`Z: -14.5 .. +1.5`), wall height `7.6 m`, wall thickness `t = 0.40 m`, surface `"corrugated"` tinted `GLACIER_SLATE` (`#1f2e3d`).

* **Geodesic Radome Cupola (Hero Roof Landmark):** Centered at `(0.0, 7.6, -6.5)` above the flat roof slab (`28.8 × 0.36 × 16.8 m`), construct a stepped/faceted dome (`SurfaceTool` 16-sided dome or 3 concentric cylinders/octagonal rings of radius `6.5 m`, `5.2 m`, and `3.4 m` rising to `Y = 12.8 m`) in `ALABASTER_SNOW` with `RESCUE_ORANGE` meridian ribs and a lightning arrestor mast up to `Y = 14.5 m`.

* **Wall Openings (`pierced_wall` `Rect2(local_center_x, bottom_y, width, height)`):**

  * **North Wall (`Z = -14.5`):**

    * Left Ground Portal: `Rect2(-8.0, 0.0, 4.2, 3.5)` (world `X ∈ [-10.1, -5.9]`)

    * Right Ground Portal: `Rect2(8.0, 0.0, 4.2, 3.5)` (world `X ∈ [+5.9, +10.1]`)

    * Clerestory Windows (3): `Rect2(-11.0, 4.8, 3.2, 1.8)`, `Rect2(0.0, 4.8, 4.4, 1.8)`, `Rect2(11.0, 4.8, 3.2, 1.8)`

  * **South Wall (`Z = +1.5`):**

    * Left Ground Portal: `Rect2(-9.5, 0.0, 4.2, 3.5)` (world `X ∈ [-11.6, -7.4]`)

    * Right Ground Portal: `Rect2(9.5, 0.0, 4.2, 3.5)` (world `X ∈ [+7.4, +11.6]`)

    * **Upper Catwalk Archway:** `Rect2(0.0, 3.4, 8.0, 3.6)` (world `X ∈ [-4.0, +4.0], Y ∈ [3.4, 7.0]`)

    * Clerestory Windows (2): `Rect2(-9.5, 4.8, 3.6, 1.8)`, `Rect2(9.5, 4.8, 3.6, 1.8)`

  * **West & East Gable Walls (`X = -14.0` and `X = +14.0`):**

    * Center Gable Portal: `Rect2(0.0, 0.0, 4.4, 3.6)` (world `Z ∈ [-4.2, +0.2]`)

    * Upper Gable Windows (2): `Rect2(-4.2, 4.6, 2.8, 1.8)`, `Rect2(4.2, 4.6, 2.8, 1.8)`

* **Interior Sightline Breakers & Cover (Required Colliders):**

  * **Twin Cryo-Cooling Core Vessels:** Centered at `(-5.5, 1.35, -6.5)` and `(+5.5, 1.35, -6.5)`, collider size `2.4 × 2.7 × 2.4 m` (`b.box("Cover", ...)` + visual cylinder `R = 1.15 m, H = 5.4 m` in `CRYO_TEAL` with glowing `COOL_LED` sight-glass rings). Blocks direct East-West sniper fire between the `X = ±14.0` gable portals while leaving `3.5 m` north/south aisles.

  * **Central Holo-Telemetry Console:** Centered at `(0.0, 0.65, -2.0)`, size `2.6 × 1.3 × 1.6 m` (`GLACIER_SLATE` base with `HAZARD_AMBER` cap and glowing holographic topographic projection frame at `Y = 1.45 m`).

### 4.2 `E1` — Elevated Catwalk & South Cliffside Overlook Bridge (`Y = +3.40 m`)

* **Interior South Gallery Slab:** `b.box("Worktop", Vector3(0.0, 3.25, 4.2), Vector3(18.0, 0.30, 3.2), STEEL)` (`X ∈ [-9.0, +9.0], Z ∈ [2.6, 5.8]`, walkable top at `Y = +3.40 m`). Supported underneath at the center by `b.box("RailServiceCabin", Vector3(0.0, 1.55, 4.2), Vector3(5.2, 3.1, 3.0), CONCRETE_WARM)` so the ground portals at `X = ±9.5` have `4.9 m` of unobstructed headroom!

* **Exterior Cantilevered Cliffside Overlook Deck:** `b.box("Worktop", Vector3(0.0, 3.25, 9.0), Vector3(8.0, 0.30, 6.0), STEEL)` (`X ∈ [-4.0, +4.0], Z ∈ [6.0, 12.0]`, walkable top at `Y = +3.40 m`), supported underneath by an enclosed radar equipment vault `b.box("RailServiceCabin", Vector3(0.0, 1.55, 9.0), Vector3(7.8, 3.1, 5.8), GLACIER_SLATE)`.

* **Glazed Overlook Canopy & Sniper Aperture:** Roof slab at `(0.0, 6.15, 9.0)` (`8.4 × 0.24 × 6.2 m`), side glass windscreens (`b.glass_material()`) at `(±3.85, 4.85, 9.0)` (`0.06 × 1.4 × 4.8 m`), and split south windscreens at `(±2.6, 4.95, 11.92)` (`2.2 × 1.1 × 0.06 m`) framing a central overlook aperture over the Gondola Gorge.

* **West & East Access Ramps (`17.2°` slope, flush against Rotunda South Wall `Z = +1.5`):**

  * **West Ramp:** `b.ramp(Vector3(-15.0, 0.0, 7.8), Vector3(-4.0, 3.4, 7.8), 3.2)` with stepped concrete sub-base sills filling `X ∈ [-13.5, -4.0], Z ∈ [6.3, 9.3]`.

  * **East Ramp:** `b.ramp(Vector3(15.0, 0.0, 7.8), Vector3(4.0, 3.4, 7.8), 3.2)` with stepped concrete sub-base sills filling `X ∈ [+4.0, +13.5], Z ∈ [6.3, 9.3]`.

  * **Safety Railings:** `b.railing_path([Vector3(-3.9, 3.4, 11.9), Vector3(3.9, 3.4, 11.9)], 1.05, HAZARD_AMBER, 1.5, true)` along the south cliffside edge and `b.railing_path([Vector3(-8.8, 3.4, 2.7), Vector3(8.8, 3.4, 2.7)], 1.05, HAZARD_AMBER, 1.5, true)` along the interior gallery edge.

### 4.3 `B2` & `V1/V2` — North Snowcat Hangar (`(0.0, 0.0, -33.0)`) & Tracked Snowcat Groomers (`(±25.0, 0.0, -19.5)`)

* **Hangar Shell (`B2`):** `40.0 × 14.0 m` (`X ∈ [-20.0, +20.0], Z ∈ [-40.0, -26.0]`), height `6.8 m`, wall thickness `0.40 m`, surface `"corrugated"` tinted `GLACIER_SLATE`.

  * **North Wall (`Z = -40.0`):** Portals `Rect2(-12.0, 0.0, 4.2, 3.4)` and `Rect2(12.0, 0.0, 4.2, 3.4)` + 3 upper windows at `Y = 4.2 m`.

  * **South Wall (`Z = -26.0`):** Portals `Rect2(-12.0, 0.0, 4.4, 3.6)` and `Rect2(12.0, 0.0, 4.4, 3.6)` + 3 upper windows at `Y = 4.2 m`.

  * **West & East Gable Walls (`X = ±20.0`):** Center bay doors `Rect2(0.0, 0.0, 4.4, 3.6)` (world `Z ∈ [-35.2, -30.8]`) + 2 upper windows.

  * **Interior Equipment:** Central **Weather-Balloon Inflation Rig** at `(0.0, 1.1, -35.5)` (`2.6 × 2.2 × 2.4 m` collider + overhead `R = 1.6 m` silver balloon envelope suspended at `Y = 4.8 m`), plus symmetric **Snowcat Hydraulic Workbenches** at `(±6.5, 0.65, -33.0)` (`2.8 × 1.3 × 1.5 m`).

* **Tracked Alpine Snowcat Groomers (`V1` at `(-25.0, 0.0, -18.0)` & `V2` at `(+25.0, 0.0, -18.0)`):**

  * **Physics Collider:** Single clean box per vehicle: `b.collider(Vector3(side * 25.0, 1.35, -18.0), Vector3(5.8, 2.7, 2.8), "metal")`.

  * **Sculpted Multi-Part Visuals (`b.detail`, `b.cylinder`, `b.glass_material`):**

    * Twin triangular caterpillar track assemblies at `dz = ±1.15 m` (`4.2 m` long × `0.85 m` tall × `0.55 m` wide in `BASALT_DARK` with 4 yellow drive/idler sprockets per side).

    * Raked forward cab (`2.2 × 1.65 × 2.3 m` in `RESCUE_ORANGE`) with wrap-around sloped windshield (`b.glass_material()`), twin amber roof beacons, and LED lightbar.

    * Rear flatbed diesel pack (`2.4 × 1.1 × 2.1 m` in `GLACIER_SLATE`) with twin vertical exhaust stacks and a front angled hydraulic snowplow blade (`0.35 × 0.95 × 3.1 m` in `HAZARD_AMBER`).

### 4.4 `B3` & `G1/G2` — South Bullwheel Cable Station (`(0.0, 0.0, +33.0)`) & Boardable Alpine Gondola Cabins (`(±21.0, 0.0, +30.0)`)

* **Bullwheel Cable Drive Station (`B3`):** `16.0 × 11.0 m` (`X ∈ [-8.0, +8.0], Z ∈ [27.5, 38.5]`), height `6.2 m`, wall thickness `0.35 m`, surface `"concrete"` / `"corrugated"` in `RESCUE_ORANGE` & `CONCRETE_WARM`.

  * **4 Portals:** North (`Z = 27.5`) and South (`Z = 38.5`) portals `Rect2(0.0, 0.0, 4.4, 3.6)` + 2 side windows each; West (`X = -8.0`) and East (`X = +8.0`) portals `Rect2(0.0, 0.0, 3.8, 3.4)` + 2 side windows each.

  * **Overhead Dual Bullwheel Truss:** At `Y = 6.6..9.2 m` above `B3`, mount two horizontal `R = 3.2 m` red-and-yellow steel drive bullwheels (`b.cylinder`) with `0.06 m` steel haul cables (`strut()`) stretching west and east to the Gondola hanger arms at `(±21.0, 8.8, +30.0)` and out over the southern gorge cliff (`Z = +72.0 m`).

* **Boardable Alpine Gondola Cabins (`G1` at `(-21.0, 0.0, +30.0)` & `G2` at `(+21.0, 0.0, +30.0)`):**

  * **Walk-Through Compound Colliders:** Overall cabin envelope `12.0 m` (`X`) × `4.2 m` (`Z`) × `3.4 m` (`Y`), wall thickness `0.32 m`:

    * North & South Side Walls (`Z = 30.0 ± 2.1 m`): Two wide `3.4 m` open sliding-door portals at `local_x = -3.0` and `local_x = +3.0` (`Rect2(-3.0, 0.0, 3.4, 2.85)` and `Rect2(3.0, 0.0, 3.4, 2.85)`), leaving a central `2.6 m` pillar (`X = gcx - 1.3 .. gcx + 1.3`) with panoramic window opening `Rect2(0.0, 1.0, 1.8, 1.4)`.

    * West & East End Walls (`X = gcx ± 6.0 m`): Open `2.8 m`-wide end vestibule portals `Rect2(0.0, 0.0, 2.8, 2.85)`.

  * **Sculpted `SurfaceTool` Panoramic Gondola Visuals (Must NOT look like boxy sheds):**

    * Curved tumblehome aluminum cabin shell in `RESCUE_ORANGE` and `ALABASTER_SNOW` with tapered octagonal panoramic glass nose/tail fairings (`b.glass_material()`), exterior perforated steel ski-rack baskets, yellow boarding step plates, interior bench seats along the center pillar, and an overhead **curved steel suspension hanger arm** rising from the cabin roof (`Y = 3.5 m`) to the haul-cable grip carriage at `Y = 8.8 m`!

### 4.5 `H1/H2`, `B4/B5`, & `C1/C2` — West & East Helipad Deployments & Flanking Structures

* **Heated Concrete Helipad Decks (`H1` at `(-46.0, 0.0, 0.0)` & `H2` at `(+46.0, 0.0, 0.0)`):**

  * Circular concrete pad (`b.cylinder(Vector3(side * 46.0, 0.02, 0.0), 7.2, 0.04, Color("485056"))`) ringed by 16 recessed green/amber perimeter deck lights and a painted `HAZARD_AMBER` landing circle and `"H"` emblem (`b.detail`).

  * Protected on the inward (midfield-facing) edge by two **Helipad Blast Baffles** at `(side * 41.5, 0.65, ±6.8)` (`1.4 × 1.3 × 2.6 m` in `HAZARD_AMBER` & `GLACIER_SLATE`).

* **North Flank Avalanche Radar Bunkers (`B4` at `(-39.0, 0.0, -22.0)` & `B5` at `(+39.0, 0.0, -22.0)`):**

  * `10.0 × 10.0 × 4.4 m` reinforced concrete bunkers (`t = 0.32 m`) with `3.8 × 3.0 m` center doorways and two `1.8 × 1.3 m` windows on all 4 walls (`Rect2(0.0, 0.0, 3.8, 3.0)`, `Rect2(±3.0, 1.2, 1.8, 1.3)`), topped by a rotating rooftop avalanche Doppler horn.

* **South Flank Open-Air Ski-Patrol & Winch Canopies (`C1` at `(-39.0, 0.0, +20.0)` & `C2` at `(+39.0, 0.0, +20.0)`):**

  * Open-sided `10.0 × 8.0 m` sloped steel canopy roof at `Y = 4.4 m` supported by 4 slender steel columns at `(±39.0 ± 4.5, 2.2, 20.0 ± 3.6)` (`0.3 × 4.4 × 0.3 m`) sheltering a central **Cable Winch Skid** (`2.6 × 1.3 × 1.4 m` at `(±39.0, 0.65, +20.0)`). Keeps the southern flank visually open and distinct from the northern bunkers.

## 5. Primary, Secondary, and Flanking Routes

### 5.1 Three Primary East–West Lanes

1. **North Ridge Lane (`Z ≈ -33.0 m` — Close/Medium Indoor-Outdoor Hybrid):**

   * Runs from West Cluster 1 (`(-48, 0, -34)`) past the North Avalanche Bunker (`B4`) into the **Snowcat Hangar (`B2`)** via the `4.4 m` west bay door (`(-20, 0, -33)`) or the exterior north snow-cut bypass (`Z = -42.5 m`, width `2.5 m`), exiting to Red Cluster 1 (`(+48, 0, -34)`).

2. **Center Rotunda & Snowcat Courtyard Lane (`Z ≈ -18.0 .. +2.0 m` — Multi-Tier Core Arena):**

   * Runs from the West Helipad (`(-46, 0, 0)`) past granite cover blocks (`(-33, 0, ±7.5)` and `(-24, 0, -3)`) and the **Tracked Snowcat Groomer (`V1` at `(-25, 0, -18)`)** into the **Cryo-Radar Rotunda (`B1`)** via 6 ground portals, or climbs the `17.2°` ramps at `Z = +3.3 m` (`X = ±15.0 → ±4.0`) to the **Elevated Catwalk & Cliffside Overlook (`E1`, `Y = +3.4 m`)**.

3. **South Cliffside Gondola Lane (`Z ≈ +25.0 .. +34.0 m` — Medium/Long Sightlines + Boardable Cabins):**

   * Runs from West Cluster 4 (`(-48, 0, +34)`) through the Open Winch Canopy (`C1`), boarding **Gondola 01 (`(-21, 0, +30)`)**, crossing the **Bullwheel Cable Drive Station (`B3` at `(0, 0, +33)`)** or the cliffside promenade (`Z = +41.5 m`), and continuing through **Gondola 02 (`(+21, 0, +30)`)** to Red Cluster 4 (`(+48, 0, +34)`).

### 5.2 Four North–South Lateral Connectors

* **West & East Outer Lateral Connectors (`X ≈ ±39.0 m`):** Link North Clusters (`Z = -34`) through the Avalanche Bunkers (`B4/B5` at `Z = -22`), across the Helipad apron (`Z = 0`), and through the Open Winch Canopies (`C1/C2` at `Z = +20`) to the South Gondola apron (`Z = +34`).

* **West & East Inner Midfield Cuts (`X ≈ ±16.0 m`):** Link the Snowcat Hangar south portals (`(±12, 0, -26)`) past the Tracked Snowcats (`(±25, 0, -18)`), between the Cryo-Radar Rotunda gables (`(±14, 0, -2)`) and the Overlook Ramp toes (`(±16.5, 0, +7.8)`), straight down to the Gondola Cabins (`(±21, 0, +30)`).

### 5.3 Exact Route & Navigation Arrays for `objectives(builder)`

* **`b.def.routes` (15 nodes — 5 per lane):**

  * North: `(-34.0, 0.05, -31.0)`, `(-16.0, 0.05, -22.0)`, `(0.0, 0.05, -18.0)`, `(16.0, 0.05, -22.0)`, `(34.0, 0.05, -31.0)`

  * Center: `(-36.0, 0.05, 0.0)`, `(-19.0, 0.05, -2.0)`, `(0.0, 0.05, 1.5)`, `(19.0, 0.05, -2.0)`, `(36.0, 0.05, 0.0)`

  * South: `(-34.0, 0.05, 25.0)`, `(-21.0, 0.05, 30.0)`, `(0.0, 0.05, 24.0)`, `(21.0, 0.05, 30.0)`, `(34.0, 0.05, 25.0)`

* **`b.def.qa_route` (11 nodes — traverses West Spawn -> West Ramp -> Upper Catwalk `indices 3, 4, 5` -> East Ramp -> South Gondolas -> West Spawn):**

  * `0`: `Vector3(-45.5, 0.0, -5.5)`

  * `1`: `Vector3(-26.0, 0.0, 2.0)`

  * `2`: `Vector3(-16.5, 0.0, 3.3)` *(West Ramp toe)*

  * `3`: `Vector3(-2.5, 3.4, 3.3)` *(Upper Deck West — `Y = 3.4 >= 3.0`)*

  * `4`: `Vector3(0.0, 3.4, -0.3)` *(Upper Gallery Center — matches `tests.upper_point`)*

  * `5`: `Vector3(2.5, 3.4, 3.3)` *(Upper Deck East — `Y = 3.4 >= 3.0`)*

  * `6`: `Vector3(16.5, 0.0, 3.3)` *(East Ramp toe)*

  * `7`: `Vector3(21.0, 0.0, 30.0)` *(East Gondola 02 interior)*

  * `8`: `Vector3(0.0, 0.0, 33.0)` *(Bullwheel Drive Station center)*

  * `9`: `Vector3(-21.0, 0.0, 30.0)` *(West Gondola 01 interior)*

  * `10`: `Vector3(-45.5, 0.0, 5.5)`

## 6. Spawn Locations, Sightlines, Cover and Chokepoints

### 6.1 Exact Team Spawn Coordinates (`16` Blue West, `16` Red East)

* **Formula:** For `team` in `0` (Blue, `side = -1.0`, `yaw = +PI * 0.5`) and `1` (Red, `side = +1.0`, `yaw = -PI * 0.5`):

  * **4 Clusters (`row = 0..3`)** at `Z = [-34.0, -5.5, +5.5, +34.0]` (`68.0 m` north–south spread across clusters).

  * **4 Columns (`col = 0..3`)** at `X = side * (51.5 - float(col) * 2.0)` (`X = ±51.5, ±49.5, ±47.5, ±45.5`), `Y = 0.05 m`.

* **Spawn Protection & Zero Spawn-to-Spawn Sightlines:**

  * Cluster 1 (`Z = -34.0`) is shielded by the Avalanche Bunker (`B4/B5`) and Snowcat Hangar (`B2`).

  * Clusters 2 & 3 (`Z = ±5.5`) deploy on the Heated Helipad apron behind the `2.6 m`-wide Helipad Blast Baffles (`X = ±41.5, Z = ±6.8`) and granite cover blocks (`X = ±33.0, Z = ±7.5`).

  * Cluster 4 (`Z = +34.0`) is shielded by the Winch Canopy (`C1/C2`) and Gondola Cabins (`G1/G2`).

### 6.2 Sightline Horizon Caps & Chokepoint Widths

| Sightline Corridor | Start `(X, Z)` | End `(X, Z)` | Max Unobstructed Length | Blocking Feature Preventing Map-Wide Sniping | 
| ----- | ----- | ----- | ----- | ----- | 
| **North Hangar Centerline** | `(-20.0, -35.5)` | `(0.0, -35.5)` | `18.7 m` | Central Weather-Balloon Rig (`2.6 × 2.2 × 2.4 m` at `(0, 0, -35.5)`) | 
| **North-Mid Snowcat Courtyard** | `(-39.0, -18.0)` | `(+25.0, -18.0)` | `36.2 m` | Tracked Snowcats `V1` & `V2` at `(±25.0, 0, -19.5)` | 
| **Cryo-Radar Rotunda Axis** | `(-14.0, -2.0)` | `(-5.5, -2.0)` | `7.3 m` | Twin Cryo-Cooling Core Vessels at `(±5.5, 0, -6.5)` & Holo-Console at `(0, 0, -6.5)` | 
| **Cliffside Overlook to South Gorge** | `(0.0, +9.0)` | `(±21.0, +30.0)` | `29.7 m` | Bullwheel Station `B3` at `(0, 0, +33.0)` and Gondola hulls | 
| **South Gondola Promenade** | `(-39.0, +30.0)` | `(0.0, +33.0)` | `31.0 m` | Gondola Cabins `G1/G2` (`(±21, 0, 30)`) and Bullwheel Station `B3` | 

* **Minimum Chokepoint Widths (Verified for `0.75 m` Navmesh Agent Radius):**

  * Narrowest interior doorway: `2.80 m` (Gondola end gangways) → `1.30 m` clear navmesh after `2 × 0.75 m` erosion (`>= 5` navmesh cells wide).

  * Standard building portals: `3.80 m – 4.40 m` wide (`2.30 m – 2.90 m` clear navmesh).

  * Ramp width: `3.20 m` (`1.70 m` clear navmesh).

### 6.3 Authored Cover & Peek Pairs (`56` Pairs = `112` Markers, Exceeding `>= 36` Requirement)

Every waist-high cover object (`H = 1.20–1.35 m`) and vehicle/pillar edge registers an explicit `(cover_point, cover_peek)` pair in `b.def.cover_points` and `b.def.cover_peeks` with `>= 0.50 m` capsule clearance from all solid AABBs:

* **Cryo-Radar Rotunda (`B1`):** `6` pairs (`4` on Twin Cryo-Core Vessels at `(±5.5, 0, -4.1 / +0.1)`, `2` on Central Holo-Console at `(±2.2, 0, -2.0)`).

* **Overlook Sub-Vault (`E1`):** `2` pairs at `(±2.5, 0.0, 13.0)` peeking `±X`.

* **Snowcat Hangar (`B2`):** `6` pairs (`4` on service benches at `(±6.5, 0, -30.8 / -35.2)`, `2` on Weather-Balloon Rig at `(±2.4, 0, -35.5)`).

* **Tracked Snowcats (`V1` & `V2`):** `4` pairs at `(±25.0, 0.0, -18.0 ± 2.4)`.

* **Bullwheel Cable Station (`B3`):** `2` pairs on interior winch anchors at `(±3.0, 0.0, 33.0)`.

* **Boardable Gondola Cabins (`G1` & `G2`):** `12` pairs (`6` per cabin along North/South flanks at `X = gcx - 4.8, gcx, gcx + 4.8, Z = 30.0 ± 3.2`).

* **Helipad Blast Baffles (`H1` & `H2`):** `4` pairs at `(±39.7, 0.0, ±6.8)`.

* **Open Winch Canopies (`C1` & `C2`):** `4` pairs on cable winch skids at `(±39.0, 0.0, 20.0 ± 1.7)`.

* **Midfield Granite/Snow Berm Cover Blocks (`8` blocks):** `16` pairs (`2` per block at `(±24.0, 0, -3.0)`, `(±33.0, 0, -7.5)`, `(±33.0, 0, +7.5)`, and `(±12.0, 0, +19.0)`).

## 7. Interior and Exterior Transitions

1. **Zero-Step Flush Thresholds:** Every building floor slab (`InteriorSlab`) and Gondola cabin floor (`CoachFloor`) has height `<= 0.06 m` with `solid = false` (riding directly on the `Y = 0.0 m` ground collider), so players and bots never snag on door sills.

2. **High-Contrast Portal Framing:** All ground doorways created via `pierced_wall()` automatically generate `0.12 m` steel door jambs (`BASALT_DARK`) and a `0.16 m` overhead lintel cap in `RESCUE_ORANGE` or `HAZARD_AMBER`, making entry points readable from `40+ m` against snow and dark slate walls.

3. **Acoustic & Lighting Transitions (Reflection Probes & Baked Fixtures):**

   * Each of the `5` enclosed buildings (`B1`, `B2`, `B3`, `B4`, `B5`) appends its dictionary to `b.buildings`, which automatically generates an interior `ReflectionProbe` volume and baked fluorescent ceiling strips via `b.interior_lighting(c, size, h)`.

   * Warm interior lighting (`WARM_HALIDE` `Color(1.0, 0.91, 0.78)` in `B2/B3/B4/B5` and `COOL_LED` `Color(0.76, 0.89, 1.0)` in `B1` and Gondolas `G1/G2`) contrasts with the crisp `43°` alpine daylight outside, eliminating dark interior corners.

## 8. Proposed Gameplay Flow for 8v8 Matches

### 8.1 Opening Break & First-Contact Timing (`5.0 – 7.5 seconds` Sprint)

* **North Snowcat Hangar Rush (`5.1 s` sprint / `7.1 s` run):** Players spawning in Cluster 1 (`X = ±45.5, Z = -34.0`) sprint `35.5 m` to reach the Snowcat Hangar bay doors (`X = ±20.0, Z = -33.0`) or angle south behind the **Tracked Snowcats (`V1/V2` at `X = ±25.0, Z = -18.0`)** to contest the north courtyard.

* **Center Rotunda & Catwalk Contest (`5.0 s` sprint / `7.0 s` run):** Players spawning at the Heated Helipads (`X = ±45.5, Z = ±5.5`) sprint `35.0 m` past the granite cover blocks to breach the **Cryo-Radar Rotunda (`B1`)** gable doors (`X = ±14.0, Z = -2.0`) OR take the protected `17.2°` ramps (`X = ±15.0, Z = +7.8`) up to the **Elevated Catwalk & Cliffside Overlook (`E1`, `Y = +3.4 m`)**.

* **South Cliffside Gondola Push (`4.9 s` sprint / `6.9 s` run):** Players spawning in Cluster 4 (`X = ±45.5, Z = +34.0`) pass through the Open Winch Canopy (`C1/C2`) and board **Gondola 01 / 02 (`X = ±21.0, Z = +30.0`)** within `5 seconds`, trading fire across the **Bullwheel Drive Station (`B3`)**.

### 8.2 Objective Mode Anchors (Domination & 5-Rotation Hardpoint)

* **Domination Flags (`b.def.domination`):**

  * **Flag A (West Gondola 01):** `Vector3(-21.0, 0.0, 30.0)`

  * **Flag B (Central Cryo-Radar Rotunda South Floor, under Catwalk):** `Vector3(0.0, 0.0, -3.0)`

  * **Flag C (East Gondola 02):** `Vector3(21.0, 0.0, 30.0)`

* **Hardpoint Rotation (`b.def.hardpoints`):**

  * **HP 1 (Center Rotunda):** `Vector3(0.0, 0.0, -3.0)`

  * **HP 2 (North Snowcat Hangar):** `Vector3(0.0, 0.0, -31.0)`

  * **HP 3 (South Bullwheel Cable Station):** `Vector3(0.0, 0.0, 33.0)`

  * **HP 4 (West Gondola 01):** `Vector3(-21.0, 0.0, 30.0)`

  * **HP 5 (East Gondola 02):** `Vector3(21.0, 0.0, 30.0)`

* **8 Ammunition Caches (`b.def.ammo_caches`):**

  * `(-14.0, 0.0, -33.0)`, `(14.0, 0.0, -33.0)`, `(-22.0, 0.0, -11.0)`, `(22.0, 0.0, -11.0)`, `(-11.0, 0.0, -2.0)`, `(11.0, 0.0, -2.0)`, `(-12.0, 0.0, 29.0)`, `(12.0, 0.0, 29.0)`.

## 9. Geometry and Asset Requirements (Required vs. Optional Decoration)

### 9.1 Strict Separation of Required Gameplay Geometry vs. Optional Set-Dressing

| Category | Classification | Elements & Implementation Rule | 
| ----- | ----- | ----- | 
| **1. Perimeter & Primary Architecture** | **REQUIRED (Colliders + Occluders)** | W/E/N `palisade` fences (`X = ±55, Z = -45`), South `CliffSafetyRailS` (`Z = +45`), `B1` Cryo-Radar Rotunda, `B2` Snowcat Hangar, `B3` Bullwheel Station, `B4/B5` Avalanche Bunkers, `E1` Catwalk & Overlook slabs + `17.2°` ramps + railings, `C1/C2` Winch Canopy columns. | 
| **2. Hero Vehicles & Gondolas** | **REQUIRED (Compound/Box Colliders + Sculpted Mesh)** | `G1/G2` Boardable Gondola Cabins (`(±21, 0, 30)`, `SurfaceTool` hull + compound doorway colliders), `V1/V2` Tracked Snowcat Groomers (`(±25, 0, -18)`, box collider + bevelled track/cab/plow detail), `H1/H2` Helipad Blast Baffles (`(±41.5, 0, ±6.8)`). | 
| **3. Sightline Breakers & Cover** | **REQUIRED (Solid Colliders + Cover Pairs)** | Twin Cryo-Core Vessels (`(±5.5, 0, -2)`), Holo-Telemetry Desk (`(0, 0, -2)`), Weather-Balloon Rig (`(0, 0, -35.5)`), Hangar Benches (`(±6.5, 0, -33)`), Bullwheel Winch Anchors (`(±4.8, 0, 33)`), 8 Midfield Granite/Snow Cover Blocks, 8 `AmmoCase` boxes. | 
| **4. Architectural Landmark Trim** | **REQUIRED VISUAL (`solid = false` / `b.detail`)** | `B1` Geodesic Radome Cupola (`R = 6.5 m` at `Y = 7.6..12.8 m`), `B3` Overhead Dual Bullwheels (`R = 3.2 m` at `Y = 6.8 m`) & Haul Cables, `G1/G2` Overhead Suspension Hanger Arms, `H1/H2` Helipad `H` rings & deck lights. | 
| **5. Approved CC0 Solid Props (`>= 20`)** | **REQUIRED BY TEST SUITE (`b.prop`)** | Place `24` solid CC0 props from `content/manifest/maps.json` along building walls and perimeter corners outside movement lanes (see exact coordinates in Section 11). | 
| **6. Small Clutter & Floor Decals** | **OPTIONAL DECORATION (`b.small_prop`, `b.floor_decals`)** | `b.pipe_stack`, `b.cable_reel`, `b.pallet`, `b.cone`, `WetFloorSign_01`, `security_camera_02`, `Leaking006`, `AsphaltDamage001`. Must never block capsules or sightline windows. Set `"authored_dressing": true` in `glacier_peak.json`. | 

### 9.2 Pre-Approved CC0 Assets Used (Zero External Downloads Required)

All textures, HDRIs, decals, and props are already committed and hash-verified in `content/manifest/maps.json` and `content/manifest/maps/*.json`:

* **HDRI Sky:** [Poly Haven Kloofendal 43° Clear Pure Sky](https://polyhaven.com/a/kloofendal_43d_clear_puresky) (`res://content/sky/kloofendal_43d_clear_puresky_2k.hdr`)

* **Ground Splat Materials:** `brushed_concrete` (base), `snow_02` (red channel — snowdrifts), `gravel_stones` (green channel — salted paths), `lichen_rock` (blue channel — exposed alpine basalt)

* **Surface Materials:** `corrugated_iron_02`, `concrete_wall_004`, `painted_metal_shutter`, `concrete_floor_worn_001`

* **3D Props (`b.prop` / `b.small_prop`):** `portable_generator`, `old_military_compressor`, `steel_frame_shelves_02`, `industrial_storage_cart`, `industrial_pastic_container`, `Barrel_01`, `barrel_03`, `boulder_01`, `rock_face_01`, `security_camera_02`, `WetFloorSign_01`, `old_tyre`, `trashbag`

* **Decals:** [ambientCG AsphaltDamage001](https://ambientcg.com/view?id=AsphaltDamage001), `Leaking006`, `Leaking008`

## 10. Acceptance Tests for the Implementation

Codex must verify that the implementation passes **all 10 automated & engine gates** before completion:

 1. **GDScript 4.7.2 Strict Static Typing Gate:**

    * `0` inferred `:=` variable declarations (`var x := ...` is forbidden on Variants/floats in strict mode; use `var x: float = ...`, `const` with `:=` is fine).

    * `0` untyped `for` loops (always write `for i: int in ...`, `for side: float in [-1.0, 1.0]:`, `for p: Vector3 in ...`).

 2. **Topological Originality Gate:**

    * `0` calls to `b.modern_building()` or `b.bridge()`.

    * `0` building centers within `6.0 m` of any `foundry.gd` building center.

    * Gondola Cabins (`G1`, `G2`) and Geodesic Radome (`B1`) use `SurfaceTool` 3D geometry (`quad` + `finish_mesh`), not plain box sheds.

 3. **Registry & Catalog Gate (`python3 tools/dev.py check`):**

    * `glacier_peak` loads cleanly in `MapCatalog`, `order: 70` and `seed: 2410` are unique, `airport` remains the first map (`order: 5`) and default `menu_backdrop`, and `minimap.bounds` is square `[-59, -59, 59, 59]` covering `extent: [110, 90]`.

 4. **Marker Counts & Capsule Clearance Gate:**

    * `16` Blue spawns + `16` Red spawns (`4` clusters each, `68.0 m` spread), `0` capsule overlaps (`R = 0.45 m`).

    * `56` authored `cover_points` / `cover_peeks` pairs (`>= 36` required), `8` `ammo_caches`, `15` `routes`, `3` `domination`, `5` `hardpoints`, `11` `qa_route` (`indices 3, 4, 5` at `Y = 3.4 >= 3.0`), `0` capsule overlaps (`R = 0.35 m`).

 5. **Dual-Radius Navmesh Connectivity Gate (`0.50 m` and `0.75 m` Erosion):**

    * `100%` of ground markers (`190 / 190`) belong to a single connected navmesh component under both `0.50 m` and `0.75 m` agent radius erosion on a `0.25 m` grid.

    * Both teams have valid navmesh paths to `tests.upper_point = [0, 3.4, -0.3]` via the `Z = +3.3 m` ramps.

 6. **Sightline & Smoke Ray Gate:**

    * `tests.smoke_origin = [0, 2, 16.0]`: Ray from `(-5, 2, -16)` to `(+5, 2, -16)` is `100%` unobstructed.

    * Gondola 01 gangway ray from `(-27, 2, 30)` to `(-15, 2, 30)` is `100%` unobstructed.

    * All `7` capture cameras (`blue_spawn`, `red_spawn`, `north_route`, `center_interior`, `south_route`, `elevated`, `first_person`) have clear origin capsules and `>= 4.0 m` unobstructed forward sightlines.

 7. **Scene Preparation & Lightmap Bake Gate:**

    * `python3 tools/dev.py prepare --map glacier_peak` generates `game/maps/generated/glacier_peak.tscn` and directional `LightmapGI` `.lmbake` with `5` interior `ReflectionProbe` volumes (`>= 4` required).

 8. **Minimap & Visual Capture Gate:**

    * `python3 tools/dev.py minimap-bake --map glacier_peak` generates `content/minimaps/glacier_peak.png` (`1024 × 1024`).

    * `python3 tools/dev.py inspect-map --map glacier_peak` and `python3 tools/dev.py capture --map glacier_peak` render the overview and 7 camera views.

 9. **Content & Integration Test Suites Gate:**

    * `python3 tools/dev.py test --suite content` and `python3 tools/dev.py test --suite integration` pass with `0` failures.

10. **8v8 Bot Match & Apple M2 Air Performance Gate:**

    * `python3 tools/dev.py match-test --map glacier_peak --seed 2410` completes a full 8v8 bot match with zero stuck bots.

    * `python3 tools/dev.py benchmark --map glacier_peak --seed 2410 --seconds 600` achieves `>= 60 FPS` average, `p95 <= 20.0 ms`, `<= 2.5M` visible triangles, and `<= 2,500` draw calls at Medium `1920 × 1080`.

## 11. Self-Contained Codex Implementation Handoff

Hand the two file specifications below directly to **Codex** to implement `glacier_peak`:

### File 1: `content/manifest/map_list/glacier_peak.json`

```
{
  "id": "glacier_peak",
  "display_name": "Glacier Peak",
  "order": 70,
  "modes": ["tdm"],
  "blurb": "High-altitude alpine cryo-radar rotunda, cliffside aerial tramway gondolas, snowcat hangar, and heated helipads.",
  "menu_subtitle": "TDM  /  ALPINE TELEMETRY DOME, GONDOLA STATION & HELIPADS",
  "layout": "res://game/maps/layouts/glacier_peak.gd",
  "seed": 2410,
  "extent": [110, 90],
  "minimap": {
    "bounds": [-59, -59, 59, 59]
  },
  "style": {
    "ground_base": "brushed_concrete",
    "ground_red": "snow_02",
    "ground_green": "gravel_stones",
    "ground_blue": "lichen_rock",
    "ground_tint": "d8e0e6",
    "authored_dressing": true,
    "wall": "corrugated_iron_02",
    "wall_Alt": "concrete_wall_004",
    "roof": "painted_metal_shutter",
    "trim": "painted_metal_shutter",
    "plinth": "brushed_concrete",
    "road": "brushed_concrete",
    "walk": "concrete_floor_worn_001",
    "gravel": "gravel_stones",
    "dirt": "snow_02",
    "interior_floor": "concrete_floor_worn_001",
    "crate": "wooden_crate_02",
    "crate_height": 0.96,
    "palette": ["1f2e3d", "d95326", "158594", "eab308", "e8eef2", "23282d"],
    "office_paint": "e8eef2",
    "hall_paint": "1f2e3d",
    "plant_paint": "d95326"
  },
  "lighting": {
    "hdri": "res://content/sky/kloofendal_43d_clear_puresky_2k.hdr",
    "rotation_y": -0.62,
    "sky_energy": 1.05,
    "ambient_energy": 0.38,
    "sun_rotation_degrees": [-43, -36, 0],
    "sun_color": [1.0, 0.96, 0.90],
    "sun_energy": 2.45,
    "tonemap_exposure": 0.86,
    "glow_intensity": 0.18,
    "glow_bloom": 0.03,
    "fog_enabled": true,
    "fog_light_color": [0.82, 0.88, 0.94],
    "fog_density": 0.00045,
    "fog_sky_affect": 0.12,
    "fog_height": -4.0,
    "fog_height_density": 0.04
  },
  "capture": {
    "blue_spawn": {
      "position": [-46, 2.5, 0],
      "target": [-18, 2.2, -2],
      "fov": 64
    },
    "red_spawn": {
      "position": [46, 2.5, 0],
      "target": [18, 2.2, -2],
      "fov": 64
    },
    "north_route": {
      "position": [-32, 3.0, -33],
      "target": [10, 2.2, -33],
      "fov": 64
    },
    "center_interior": {
      "position": [-11, 2.8, 1.5],
      "target": [8, 2.0, -2],
      "fov": 66
    },
    "south_route": {
      "position": [-32, 3.0, 24],
      "target": [10, 2.2, 29],
      "fov": 64
    },
    "elevated": {
      "position": [0, 5.1, 8.5],
      "target": [0, 1.8, 30],
      "fov": 66
    },
    "first_person": {
      "position": [-28, 1.7, -14],
      "target": [-10, 1.7, -14],
      "fov": 68
    }
  },
  "overview": {
    "size": 124,
    "labels": [
      {"text": "WEST HELIPAD", "position": [-46, 8, 0], "pixel_size": 0.055},
      {"text": "EAST HELIPAD", "position": [46, 8, 0], "pixel_size": 0.055},
      {"text": "SNOWCAT HANGAR", "position": [0, 10, -33], "pixel_size": 0.055},
      {"text": "CRYO-RADAR DOME & GONDOLAS", "position": [0, 13, 8], "pixel_size": 0.055}
    ]
  },
  "tests": {
    "smoke_origin": [0, 2, 16.0],
    "upper_point": [0, 3.4, -0.3],
    "navigation_points": [
      [-45.5, 0, -5.5],
      [45.5, 0, 5.5],
      [0, 0, -31.0],
      [0, 3.4, -0.3],
      [0, 0, -3.0],
      [-21, 0, 30.0],
      [21, 0, 30.0],
      [0, 0, 33.0]
    ]
  }
}

```

### File 2: `game/maps/layouts/glacier_peak.gd` Architecture & Function Contract for Codex

Codex must implement `game/maps/layouts/glacier_peak.gd` extending `MapLayout` with the following exact functions and coordinates:

1. **`boundaries(builder: CompactMapBuilder) -> void`:**

   * Set `b.nature = AlpinePeakNature.new(b)` (custom `MapNature` subclass that raises granite ridge berms on the north/east/west beyond `58 m` and drops the south cliff gorge `Z > 46 m` down by `-28.0 m` to create a dramatic alpine abyss).

   * Set `b.region.navigation_mesh.agent_radius = 0.75`, `cell_size = 0.25`, `agent_height = 1.8`, `cell_height = 0.1`.

   * Build `palisade` fences on West (`X = -55`), East (`X = +55`), and North (`Z = -45`), and build a waist-high steel cliff safety railing backed by an invisible `3.6 m` player collider along South (`Z = +45.0`) so players can look out over the southern gorge and distant bullwheel towers (`alpine_gorge_backdrop()`).

2. **`build(builder: CompactMapBuilder) -> void`:**

   * `central_cryo_radar_rotunda()`: Builds `B1` at `(0, 0, -6.5)` (`28 × 16 × 7.6 m`), its `SurfaceTool` **Geodesic Radome Cupola** (`R = 6.5 m`, apex `Y = 12.8 m`), Twin Cryo-Cooling Core Vessels (`(±5.5, 0, -6.5)`), and Central Holo-Telemetry Console (`(0, 0, -6.5)`).

   * `elevated_catwalk_and_cliff_overlook()`: Builds `E1` at `Y = +3.4 m` (`Gallery` at `(0, 3.4, 4.2)` + `Cantilevered Overlook` at `(0, 3.4, 9.0)` with `b.glass_material()` windscreens), and the two `17.2°` ramps along `Z = +3.3 m` (`X = ±15.0 → ±4.0`).

   * `north_snowcat_hangar_and_vehicles()`: Builds `B2` at `(0, 0, -33.0)` (`40 × 14 × 6.8 m`), the central Weather-Balloon Inflation Rig (`(0, 0, -35.5)`), Hangar service benches (`(±6.5, 0, -33.0)`), and the two multi-part **Tracked Snowcat Groomers (`V1/V2`)** at `(±25.0, 0.0, -19.5)`.

   * `south_bullwheel_and_gondolas()`: Builds `B3` at `(0, 0, +33.0)` (`16 × 11 × 6.2 m`) with overhead Dual Bullwheels (`R = 3.2 m` at `Y = 6.8 m`), haul cables, and the two boardable `SurfaceTool` **Alpine Gondola Cabins (`G1/G2`)** at `(±21.0, 0.0, +30.0)` (`12.0 × 4.2 × 3.4 m`) suspended from overhead steel hanger arms.

   * `midfield_cover_and_props()`: Places the `8` Granite/Snow Cover Blocks (`(±24, 0, -3)`, `(±33, 0, ±7.5)`, `(±12, 0, +19)`), floodlight masts (`(±30, 0, -14)` and `(±32, 0, +14)`), and `24` approved solid CC0 props:

     * `steel_frame_shelves_02` at `(±17.5, 0.0, -38.8)` (`H = 2.2`)

     * `industrial_storage_cart` at `(±11.5, 0.0, -38.8)` (`H = 1.0`)

     * `old_military_compressor` at `(±31.0, 0.0, -39.5)` and `(±12.0, 0.0, 39.5)` (`H = 1.45`)

     * `portable_generator` at `(±34.5, 0.0, -39.5)` (`H = 0.95`)

     * `industrial_pastic_container` at `(±28.0, 0.0, -39.5)` and `(±15.0, 0.0, 39.5)` (`H = 1.15`)

     * `Barrel_01` and `barrel_03` clusters (`10` barrels total) along `Z = -39.5` and `Z = +39.5` (`X = ±36.5 .. ±38.1` and `X = ±17.0 .. ±17.8`).

3. **`deployment(builder: CompactMapBuilder) -> void`:**

   * Populates the `16` Blue and `16` Red spawns at `X = side * (51.5 - col * 2.0), Z = [-34.0, -5.5, +5.5, +34.0]`, builds the **Heated Helipad Decks (`H1/H2`)** at `(±46.0, 0, 0)` with Blast Baffles at `(±41.5, 0.65, ±6.8)`, builds the **North Avalanche Radar Bunkers (`B4/B5`)** at `(±39.0, 0, -22.0)`, and builds the **South Open-Air Winch Canopies (`C1/C2`)** at `(±39.0, 0, +20.0)`.

4. **`objectives(builder: CompactMapBuilder) -> void` & `dress(builder: CompactMapBuilder) -> void`:**

   * Populates the exact `ammo_caches` (`8`), `routes` (`15`), `domination` (`3`), `hardpoints` (`5`), and `qa_route` (`11`) arrays verified in Section 5.3 and Section 8.2, adds `ground_splat()` blending `brushed_concrete` aprons, `gravel_stones` paths, and `snow_02` snowdrifts, and places non-blocking decals (`AsphaltDamage001`, `Leaking006`, `Leaking008`).