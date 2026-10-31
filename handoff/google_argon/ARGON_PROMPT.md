Create an original, playable map for the supplied FPS Mode Godot project. Read START_HERE.md, MAP_SPEC.md, MAP_DESIGN.md, README.md, the current map registry, MapLayout, CompactMapBuilder, MapArena, MapDefinition, MapCatalog and content/integration tests before editing. Inspect current source over prose where they differ. Work in the full repository; the source-context attachment alone lacks binary assets and is not runnable.

Deliver a new TDM map named “Transit Works”, id `transit_works`: a compact contemporary urban rail maintenance depot, 110 × 90 metres, for the existing 8v8 local match. Follow the supplied concept, adapting exact prop placements to existing helpers, collision and route requirements. Build original geometry; do not copy a commercial game's map or change gameplay systems.

Required integration:
1. Add content/manifest/map_list/transit_works.json and game/maps/layouts/transit_works.gd extending MapLayout. Copy a suitable current registry structure, assign a unique menu order and deterministic seed, and author accurate overview labels and all seven capture cameras. Keep Airport as menu backdrop. Remove any copied minimap reference; generate a new one with the existing minimap pipeline, then register its actual bounds/path.
2. Use shared frame defaults where possible: 16 safe spawn markers per team in four clusters, at least 36 authored cover/peek pairs, eight ammo caches, three domination and five hardpoint anchors, bot routes and QA route. TDM is the playable mode; objective markers do not imply new modes.
3. Provide three readable routes with lateral links, a principal hall with four useful entrances, and one elevated maintenance route reachable from both teams and bypassable on the ground. Set tests.upper_point to an actual reachable point. Preserve clear spawn capsules and navigation around every blocking prop.
4. Reuse existing approved assets and materials. Use real metre scale, matching visual and physics geometry, correct surface tags, bevels, furnished interiors, restrained wear and coherent signage. Author geometry, navigation and baked lighting during preparation, not during a match. Respect spatial MultiMesh batching and the saved instance_batches pipeline.
5. If new assets are necessary, supply per-map source manifests, license/provenance and hashes using the existing fetch/ingest workflow. Do not add unverified downloads or commit credentials.
6. Follow current MapArena exposure behavior (fixed exposure), existing HDRI/sun alignment, directional LightmapGI, shadowmask and probes. Older MAP_DESIGN.md text mentioning auto exposure is stale relative to current runtime source.

Validation, from repository root, after registration:
python3 tools/dev.py check
python3 tools/dev.py prepare --map transit_works
python3 tools/dev.py test --suite content
python3 tools/dev.py test --suite integration
python3 tools/dev.py inspect-map --map transit_works
python3 tools/dev.py capture --map transit_works
python3 tools/dev.py minimap-bake --map transit_works
python3 tools/dev.py match-test --map transit_works --seed 1201
python3 tools/dev.py benchmark --map transit_works --seed 1201 --seconds 600

Inspect dev.py and its called tools first for current command behavior and output paths. Run all renders/bakes/benchmarks through dev.py so its shared render lock is honored. Re-run relevant checks after fixes. Do not bypass failures or weaken tests. Aim for Medium 1920×1080 on fanless M2 Air: >=60 average FPS, <=20 ms p95 frame time, <=2.5M visible triangles, <=2,500 draw calls in the worst view. Only claim hardware performance when actually measured on the target hardware.

Return changed source files, generated map/bake/minimap resources, asset records if any, labelled overhead and seven player-height views, test counts/failures, benchmark settings/results, and a short playtest report covering spawn safety, all route connections, elevated access, clipping, readability and exposure. Measure first-contact timing against the provisional 5–20 second range; distinguish automated traversal from human playtesting. If tools/hardware/assets are unavailable, deliver authored source and explicitly list unverified requirements. Do not claim the map validated from screenshots alone.
