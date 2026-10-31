# Reference-driven Zombies visual revision

The supplied Call of Duty image established the art direction: damaged human anatomy, torn clothing, luminous eyes, asymmetrical threatening poses, worn interior surfaces, broken furnishings, scattered debris and localized light. The initial procedural capsule/block characters and sparse room shells did not meet that direction.

## Character replacement

The shipped character now uses Pixelhouse's textured zombie and authored walking/fury clips, published under CC BY 3.0 at https://opengameart.org/content/zombie. Attribution, source and adaptation details are in `content/licenses/pixelhouse_zombie.txt`, `content/manifest/zombies.json`, README and the main menu's ART CREDITS screen. The unmodified diffuse atlas retains its source artist mark. It is a different character from the supplied reference.

The 57-bone skin supplies actual skull/face, shoulders, elbows, hands/fingers, knees, shoes and clothing geometry, with diffuse and normal textures. FPS Mode normalizes its authoring units and facing direction, cancels root translation so AI owns movement, shares material/mesh resources, adds restrained material variants and uses the authored limp. Close-range poses combine the authored animation with two-bone hand reaching and a forward-facing head. The glowing pupils are positioned from their actual atlas UV triangles and skin bind matrices, rather than guessed offsets.

Crawling removes the skinned leg triangles; it does not scale the whole standing body down. The remaining torso rotates into a horizontal pose, the head stays low and forward, and hand IK plants/pulls the arms near the floor. Overrides reset before each pose so the head cannot accumulate rotation. Pool reuse restores the intact mesh. Detached legs are cached, textured meshes baked from the original skin; they do not allocate another live skeleton. Existing life IDs, damage, round retention and presentation limits remain in effect. Nearby skeletons pose every physics frame; nominal cadence drops to 30 Hz beyond 10 m, 15 Hz beyond 20 m, and 10 Hz outside the camera beyond 8 m. Movement, collisions, damage and round state still simulate every tick for the full 24-enemy pool. Crawler transitions force an immediate visual update.

## Environment revision

Dead Current and Dead Air retain their six-zone, seven-door, two-loop topology and their tested purchase/window locations. This is an art revision of those layouts, not a replacement with a copied franchise map.

Room shells now have worn plaster below exposed brick, map-specific tint, scanned projected leak decals, timber/metal beam silhouettes, columns and room signage. Dead Current's office rooms have weathered timber flooring. Side islands contain scanned broken furniture, crates and discarded bags, with service pipes, electrical hardware and airport/industrial details nearby. Plaster fragments and scattered papers are batched into a few meshes per room rather than hundreds of separate draw calls. Wall brick/plaster geometry is also combined into one static mesh with two finish surfaces; original wall collision bodies and visual geometry remain in place. Zombie pursuit uses cached server paths, so the obsolete per-enemy navigation-agent nodes are removed.

The starting office contains a sealed staircase landmark with timber steps, boards, posts and rails. It does not provide a playable upper floor. Tall props occupy existing navigation exclusions or receive explicit clearance. Small floor debris remains nonblocking. Projected stains follow real surfaces and do not form floating planes across doors/windows. Zombies-only fixed exposure keeps this mode moodier while retaining readable exits, enemies and purchase prompts; TDM keeps its original exposure.

## Reviewable engine images

- `.artifacts/screenshots/zombie-art/portrait.png`: isolated anatomy/material inspection.
- `.artifacts/screenshots/zombie-art/front.png`, `side.png`, `crawl.png`, `attack.png`: deterministic rig inspection.
- `.artifacts/screenshots/zombie-art/in-game-dead_current.png` and `in-game-dead_air.png`: staged close-horde fixtures through the real app camera/HUD. These deliberately place actors for art review and are not human-playtest evidence.
- `.artifacts/screenshots/zombies/<map>/`: separate ordinary capture fixtures for windows, crawlers, box, perks and wonders.

Run `python3 tools/dev.py inspect-zombies` for rig views and `python3 tools/dev.py inspect-zombies-game --map dead_current` for the staged app view. Gameplay assertions, normal-input exported-app smoke, round soaks, rematch cleanup and measured rendering acceptance are recorded in `ZOMBIES_VALIDATION.md`.

## Limits

The reference guides anatomy, decay and atmosphere; the imported civilian clothing and retained map topology differ from it. This work does not establish human fun, economy pacing or difficulty. Visual review is distinct from automated assertions and rendering measurements. Prior primitive-version benchmark evidence is retained under `.artifacts/visual-baseline/` and must not be reported as acceptance of this revision.
