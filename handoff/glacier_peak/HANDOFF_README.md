# Glacier Peak (`glacier_peak`) — Full Map Handoff Package

## 1. Executive Summary
**Glacier Peak** (`glacier_peak`) is a brand-new `110 × 90 m` high-altitude alpine multiplayer map (`order: 70`, `seed: 2410`) for `FPS Mode`, inspired by Call of Duty's *Summit*, *Sub Base*, *Vista*, *Hideout*, and *Protocol*.

It features a **Central Cryo-Radar Rotunda & Geodesic Radome Cupola** (`(0, 0, -6.5)`, `28 × 16 × 7.6 m`, dome apex `Y = 12.8 m`), an **Elevated Catwalk & Glazed Cliffside Overlook Bridge** (`Y = +3.4 m`), a **North Snowcat Maintenance Hangar & Weather Lab** (`(0, 0, -33.0)`, `40 × 14 × 6.8 m`) flanked by two multi-part **Tracked Snowcat Groomers** (`(±25.0, 0, -19.5)`), a **South Bullwheel Cable Drive Station** (`(0, 0, +33.0)`) with two boardable `SurfaceTool` **Alpine Gondola Cabins** (`GONDOLA 01` & `GONDOLA 02` at `(±21.0, 0, +30.0)`), **West/East Heated Helipad Decks** (`(±46.0, 0, 0)`), **North Avalanche Radar Bunkers** (`(±39.0, 0, -22.0)`), and **South Open-Air Ski-Patrol Winch Canopies** (`(±39.0, 0, +20.0)`).

All **41 / 41** deterministic static, `SurfaceTool` landmark, 3D collider AABB, player-capsule clearance, camera sightline, and dual-radius (`0.50 m` and `0.75 m` agent radius on a `0.25 m` cell grid) navmesh checks pass via `verify_glacier_peak.py`.

## 2. Package File Manifest & Checksums

| Archive Path | Target Repository Path | Size (Bytes) | SHA-256 Checksum |
| :--- | :--- | ---: | :--- |
| `game/maps/layouts/glacier_peak.gd` | `game/maps/layouts/glacier_peak.gd` | 42,387 | `4a37c161c4a344429cc89234f7bb511b613817521203fd720690ad011a5e93b4` |
| `content/manifest/map_list/glacier_peak.json` | `content/manifest/map_list/glacier_peak.json` | 4,437 | `58a50ec09101e946bcdc4ae7573eb748400efbdfa7724e276b162aab4c9d65e5` |
| `tools/verify_glacier_peak.py` | `tools/verify_glacier_peak.py` | 32,090 | `41d92f42e97ef2417c824234758171d97977f63e8aa2aee43060c92416040492` |
| `artifacts/glacier_peak_static_verification.json` | *(Verification Report)* | 8,834 | `763641cfec82627667fa080d597d5adad42dd700d48d5ea3ca308151ddb70bba` |
| `artifacts/glacier_peak_blueprint.png` | *(2-Panel Greybox & Blueprint)* | 482,619 | `6eff15217f424f175df820ae412597dc835a9e90053683576ddb53cd5dc376d4` |
| `GLACIER_PEAK_CODEX_SPEC.md` | *(Complete 11-Section Design Spec)* | 45,721 | `142b47cb1e5023abca9f23f88af9062e050c64556848e247175de149e6550d47` |

## 3. Local Godot 4.7.2 Build, Bake & Verification Pipeline

```bash
unzip -o glacier_peak_handoff_package.zip -d /path/to/repo
cd /path/to/repo

# 1. Run the standalone 41-check static, SurfaceTool, AABB & dual-radius navmesh verification suite
python3 tools/verify_glacier_peak.py --repo . --out artifacts/

# 2. Validate GDScript compilation, build glacier_peak.tscn/.lmbake, and bake the 1024x1024 minimap
python3 tools/dev.py check
python3 tools/dev.py prepare --map glacier_peak
python3 tools/dev.py minimap-bake --map glacier_peak

# 3. Run Godot content/integration suites, capture cameras, 8v8 bot match, and M2 Air benchmark
python3 tools/dev.py test --suite content
python3 tools/dev.py test --suite integration
python3 tools/dev.py inspect-map --map glacier_peak
python3 tools/dev.py capture --map glacier_peak
python3 tools/dev.py match-test --map glacier_peak --seed 2410
python3 tools/dev.py benchmark --map glacier_peak --seed 2410 --seconds 600
```
