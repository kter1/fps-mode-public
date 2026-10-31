# Transit Works (`transit_works`) — Map Handoff Package

## 1. Executive Summary
**Transit Works** (`transit_works`) is a brand-new `110 × 90 m` Team Deathmatch, Domination, and Hardpoint map set in an active municipal rail overhaul complex. Designed from scratch with a **Central Circular Locomotive Turntable Ring**, a **3-Bay Stepped Fan Roundhouse Arc**, a **North Grand Overhaul Concourse**, two point-symmetrically offset **Walk-Through Metro Cars**, and **Open-Air Cantilevered Platform Canopies**, it shares **0/8 building positions** and **0 prefab calls** (`0` `b.modern_building()`, `0` `b.bridge()`) with `foundry.gd`.

All **40 / 40** deterministic static source, asset-provenance, 3D collider AABB, player-capsule clearance, camera sightline, and dual-radius (`0.50 m` and `0.75 m` agent radius on a `0.25 m` cell grid) navmesh connectivity checks pass via `verify_transit_works.py`.

## 2. Package File Manifest & Checksums

| Package Path | Target Repository Path | Size (Bytes) | SHA-256 Checksum |
| :--- | :--- | ---: | :--- |
| `game/maps/layouts/transit_works.gd` | `game/maps/layouts/transit_works.gd` | 41,190 | `7ea5dd94866a5f92e73d53823763513a1e8332e9b54bdbd4a9b78154f5d018c8` |
| `content/manifest/map_list/transit_works.json` | `content/manifest/map_list/transit_works.json` | 3,095 | `3ff7f1c52e140f9608da872e71e63f30b32f9fa67196068ae2b7c9422e698984` |
| `tools/verify_transit_works.py` | `tools/verify_transit_works.py` | 32,999 | `6c222bacde7561ce37a025884f89c6725987d177300546e4f8e2783c8580aec1` |
| `artifacts/transit_works_static_verification.json` | *(Verification Report)* | 8,644 | `b54b5e39352a585707e0b65eab219e7a7c7c24119bfd1843fcb82b11822ef6fd` |
| `artifacts/transit_works_overview_plan.png` | *(Architectural Blueprint)* | 316,763 | `cbff57a05fad00c4182cdd73596d240e115d661fc897ff328396b34d541e0a73` |

## 3. Spatial Architecture & Combat Zones (`110 × 90 m`, `seed: 1906`, `order: 60`)

| Zone / Landmark | Center & Footprint | Doors / Windows / Elevation | Tactical Role & Sightlines |
| :--- | :--- | :--- | :--- |
| **North Grand Overhaul Concourse** | `(0, 0, -33.0)` (`48 × 16 m`, `H = 8.8 m`) | 6 ground doors (`4.4 m` wide: 2 N, 2 S, 2 E/W gables) + 12 clerestory windows | High-ceilinged heavy overhaul bay with bridge crane, bogie jacks (`(±9.5, 0, -35)`), wheel lathes (`(±19.5, 0, -30)`), and calibration rig (`(0, 0, -35)`). |
| **Mezzanine & Signal Rotunda Balcony** | `(0, 3.4, -26.8)` & `(0, 3.4, -22.0)` (`Y = +3.4 m`) | Reached via West/East `17.2°` ramps flush against the Concourse south facade (`X = ±15 → ±4, Z = -23.2`) | Connects the interior Concourse mezzanine through an `8.0 m` upper arch to a cantilevered balcony overlooking the central turntable. |
| **Rotary Turntable Pit & Loco 801** | `(0, 0, 5.0)` (`16 m` outer ring, `R = 7.8 m`) | Open circular ring with `1.2 m` concrete curbing, girder bridge, `Loco 801`, and control booth | Signature central arena (`Domination B` / `Hardpoint 1` at `(0, 0, -1)`), breaking cross-map sightlines while rewarding curved ring movement. |
| **Walk-Through Metro Cars (`401` & `402`)** | `(-20, 0, -5)` & `(20, 0, 5)` (`16.0 × 4.4 m` each) | 4 wide open side doors (`3.6 m` wide) + 2 end gangways (`3.0 m` wide) + 2 windows per car | Point-symmetrically offset mainline train cars (`Domination A & C`) offering fast interior-to-exterior lane switching. |
| **South 3-Bay Fan Roundhouse Arc** | `Stall 02` `(0, 0, 34)` (`18 × 12 m`); `Stalls 01/03` `(±22, 0, 30)` (`14 × 11 m`) | 4 ground portals + 8 windows per stall (12 portals, 24 windows across the arc) | Radial locomotive stalls fed by fan tracks from the turntable; `Stall 02` features a sunken inspection pit and `Hardpoint 2`. |
| **Platform Canopies & Corner Pavilions** | Canopies `(±46, 0, 0)` (`8.4 × 18 m`); Pavilions `(±41, 0, -20)` & `(±41, 0, 22)` (`10 × 10 m`) | Open-air canopies + four 4-door corner pavilions (`Traction Relay W/E`, `Crew Dispatch W/E`) | Protected 4-cluster team spawns (`16` Blue West, `16` Red East across `Z = -34, -5, +5, +34`, `68 m` spread) with immediate 3-lane exits. |

## 4. Local Godot 4.7.2 Build, Bake & Verification Pipeline
After unpacking `transit_works_handoff_package.zip` into the repository root, run the following commands on your development machine with Godot 4.7.2:

```bash
# 1. Run the standalone 40-check static, AABB & dual-radius navmesh verification script
python3 tools/verify_transit_works.py --repo . --out artifacts/

# 2. Validate GDScript compilation and project integrity
python3 tools/dev.py check

# 3. Build game/maps/generated/transit_works.tscn and bake directional LightmapGI (.lmbake)
python3 tools/dev.py prepare --map transit_works

# 4. Bake the 1024x1024 orthographic minimap to content/minimaps/transit_works.png
python3 tools/dev.py minimap-bake --map transit_works

# 5. Execute content and integration test suites
python3 tools/dev.py test --suite content
python3 tools/dev.py test --suite integration

# 6. Render top-down inspection overview and all 7 capture camera views
python3 tools/dev.py inspect-map --map transit_works
python3 tools/dev.py capture --map transit_works

# 7. Run deterministic 8v8 bot match test and 600s Apple M2 Air hardware benchmark
python3 tools/dev.py match-test --map transit_works --seed 1906
python3 tools/dev.py benchmark --map transit_works --seed 1906 --seconds 600
```
