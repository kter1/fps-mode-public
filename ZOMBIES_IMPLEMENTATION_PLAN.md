# Optimized Zombies implementation plan

Prepared October 20, 2026. Status: plan only; gameplay implementation has not started.

This is the canonical execution plan. [ZOMBIES_DESIGN_SPEC.md](ZOMBIES_DESIGN_SPEC.md) retains the official-source research, exact initial tuning, map graphs and detailed acceptance cases. Read this plan first, then only the specification sections needed for the current milestone.

## 1. Deliverable and priorities

Deliver a native, offline, solo, endless Zombies mode alongside the existing 8v8 TDM. Preserve the complete agreed scope:

| Required feature | Release behavior | Specification |
|---|---|---|
| Rounds and enemies | Pistol/knife start, finite round budget, 24-enemy pool, escalating pressure, death/results/rematch | §4.1–4.2 |
| Barriers | Six visible planks, enemy tearing/entry, held repair, bounded repair rewards | §4.3 |
| Grenade crawlers | Surviving blast removes legs; real low animation/collision/attacks; final crawler keeps the round alive | §4.4 |
| Wall weapons | Five chalk silhouettes, purchase/swap and matching paid ammunition; no free TDM resupply | §4.5 |
| Mystery box | Random offers, explicit claim, timeout, relocation/refund and location beacon | §4.6 |
| Wonder weapons | Ray Gun-style projectile, Thundergun-style air blast, chain-lightning rifle; real models/reloads | §4.6 |
| Progression | Five perks, power, one upgrade tier, five drops and one trap per map | §4.7–4.8 |
| Maps | Dead Current power station and Dead Air airport; six zones, branching doors and two training loops each | §5 |
| Product flow | Keyboard/controller, readable HUD, pause, records, clean rematches and exported app | §6–8 |

Implementation priority is a complete playable loop in the first map, followed by shared-system completion and the second map. Optional secrets follow required acceptance. Multiplayer, extra currencies, armor/crafting, rarity tiers, bosses and account progression remain outside this release.

## 2. Architecture decisions to keep fixed

1. **Reuse combat, isolate match flow.** ZombiesWorld extends MatchWorld and owns its loading, physics, spawning and death lifecycle. Keep TDM's 16 slots, 100 kills, 600 seconds and respawns unchanged. Give the mode field an explicit Variant contract rather than refactoring the whole FPS into a new framework. Route app setup/results/QA before dereferencing TDM-only fields.
2. **Stable identities.** Human is slot 0; 24 reusable ZombieActor slots retain matching array indices. Increment life_id on reuse; inactive actors are hidden and noncolliding. Shared traces, damage validation and aim targeting must tolerate unarmed enemies.
3. **One owner per state.** ZombiesMode owns rounds/points; ZombiesWorld owns pool/spawn placement; ZombieActor initially owns AI/body state; ZombieInteractions owns candidate selection and atomic purchase commits. Keep complex barrier/box/door lifecycles separate. Use data-driven simple station kinds; extract helpers only when actual behavior requires them.
4. **One enemy graph, two anatomies.** Standing/crawling is a persistent posture flag selecting collision, speed, aim point and clips. Reuse pursuit/attack/stagger states. A crawler retains health, identity, barrier assignment and live-round membership. Fatal blasts stay dead.
5. **One damage path.** Conventional shots, melee, frags, wonders, traps and drops use validated queued damage. Reuse world occlusion. Add the smallest effective-damage, special-fire, post-hit and death hooks; special fire consumes ammunition exactly once. Deduplicate terminal rewards by victim life and shot/action ID.
6. **One inventory factory.** ZombiePlayer overrides normal loadout construction and starts with one gun. Zombies runtimes retain base ID, upgrade flag, reserve maximum and immutable baselines. Recompute perk/upgrade effects from those baselines. Preserve the TDM catalog's ordered 15 guns and existing saves.
7. **Explicit gated navigation.** Bake one bounded region per zone with navigation-only threshold gaps, continuous physical floors and automatic edge stitching disabled. Runtime doors/planks are excluded from bake sources. Disabled links block closed routes; purchases coordinate link/collider changes and refresh paths after server synchronization. Keep the existing TDM singleton region and bake path.
8. **Predictable tick commits.** Capture input/interaction intent, reserve enemy traversal, simulate movement/attacks, resolve damage, then revalidate and commit repair/purchase/upgrade intents. Damage cancels held work; entry reservations win over repair. Check round clear last. Clear input latches on pause, focus loss, downing and reset.
9. **Bound cost before adding complexity.** Pool enemies/effects; stagger AI/path work, cache station candidates and throttle distant animation/audio. With only 24 enemies, keep simple bounded searches until profiling proves a more complex structure is needed. Separate gameplay RNG streams for spawn, combat, box and drops from cosmetic randomness.
10. **Use existing pipelines.** Add mode filters to map/UI/tests and dispatch to the Zombies builder/baker. Extend dev.py, app QA, release_verify.py and report.py together. Every rendered run uses dev.py's shared render lock. Keep baked emergency lighting; use bounded runtime machine indicators instead of trying to toggle baked lightmaps.

The specification's detailed interfaces remain useful reference. Its file list describes ownership, not permission to create empty services or duplicate working combat code.

## 3. Eight milestones with explicit exit gates

### M0 — Preserve the baseline and add the narrow mode seam

Read current diffs and relevant repository instructions. Record unrelated changes and baseline check results. Add mode selection/map filtering, safe app dispatch, an explicit Zombies suite route and the QA entry point required by M1. Existing registry entries default to TDM; tools can still discover every map for preparation.

**Gate:** Parser/content/core/audio results recorded; previously passing TDM assertions remain passing; TDM selects only its original six maps. Unknown test suites fail explicitly. Capture pre-existing failures separately; do not weaken checks or expand into unrelated repairs.

### M1 — Prove the expensive and uncertain parts first

Create the retained starting portion of Dead Current: Intake plus two adjacent zones, one purchased portal and one barrier. Establish the actual zone builder/baker, rather than a throwaway map pipeline. In a dev.py-driven probe, validate one real infected rig's standing movement, attack, leg separation, crawl pose, lowered hurtboxes and low entry. Add the minimal physics/damage fixture necessary to observe these states; M2 supplies full match rules.

Use the same rig in a 24-body rendered stress fixture. Run one 60-second diagnostic at Medium/1080p and record frame intervals. Debug station props are acceptable here; the enemy/crawler proof must use intended final rig geometry and animation.

**Gate:** Closed/open portal works in actual navigation and collision; each link attaches to its intended region; no bake polygons bridge a closed threshold. Fatal/nonfatal frag cases and crawler aim/collision pass. Rendered footage proves low crawling. Identify and fix material rig/nav/performance problems before building around them. This diagnostic is not final performance acceptance.

### M2 — Make the first survival loop playable end to end

Implement round budget, stable pool, pursuit/melee, human start equipment, points, death/results/rematch and a minimal ZombiesHUD. Connect one repairable window, the purchased door, one chalk gun/ammo station, a conventional-gun box and one health perk. Integrate keyboard E and controller Square arbitration now. This is a temporary content subset inside the retained release map; final configuration restores all specified content.

**Gate:** Play three rounds through normal input. Leave a grenade-created crawler alive, repair/buy/open a route, then kill it to advance exactly once. Verify debit/grant/kill rewards occur once, failed spawns retry without losing budget, no free cache ammo appears and death never causes a TDM respawn. Rematch clears all introduced state.

### M3 — Complete the shared progression systems

Expand the first map's blockout to its six-zone graph. Complete all five wall guns, full box claim/expiry/relocation, five perks/four-perk cap, power, weapon upgrade, self-revive/loss, five drops and the reusable trap. Integrate each mechanic's actual prompt, machine state, feedback and focused checks with its implementation.

**Gate:** Each specified purchase/drop works through the shared transaction/damage path. Exercise interrupted holds, pellet reward limits, modifier recalculation, shell reload, perk loss, three self-revive purchases, pending spawns after a Nuke and barrier traversal during Carpenter. Distinct station IDs/data drive behavior; no first-map coordinate branches.

### M4 — Deliver the wonder arsenal and visible identities

Implement Raycaster swept projectiles/splash, Thunder Cannon cone/knockback and Arc Rifle unique-target chains. Finish their distinct models, sockets, reloads, sound and upgraded forms. Complete original machine/box/chalk presentation and the enemy rig's required clips/three material variants. Keep tuning in canonical data and preserve all pool limits.

**Gate:** Inspect first-person hands/reloads and firing against a horde and walls. Test finite ammo, thin-wall sweeps, self-splash, cone occlusion, unique chain targets, one combined impact and upgrades. Run the 60-second horde diagnostic after the final effects are present; investigate new regressions before map dressing.

### M5 — Finish and accept Dead Current

Finish its geometry, dressing, signage, entry placement, emergency lighting and two training loops. Validate every reachable door-state subset in graph tests and representative actual physical routes, including crawlers. Exercise a 20-round scenario, pause, down/revive and three rematches. Record actual human feedback separately from automated evidence.

**Gate:** Every required system is usable in this map with finished assets; no stuck final enemy, inaccessible machine or entry leak. Perform its full 600-second horde benchmark once content is stable. Failed current-map gates remain open work.

### M6 — Add Dead Air through the proven content contract

Build its airport layout, six-zone graph, carousel/apron routes, stations, entries, box sites, lighting and trap using the same systems. Reuse art kits and mechanics; give the map distinct geometry and landmarks. Fix a shared defect in shared code with a regression case; do not fork the mode for this map.

**Gate:** Apply the same functional, physical-navigation, visual, round-20, rematch and full performance checks as Dead Current. A missing second map cannot be reclassified as post-release work.

### M7 — Verify the product and packaged build

Finish mode-specific help/settings/results/records and save migration. Complete any remaining input/accessibility work. Run all relevant suites, mode-aware release/report tooling, export the native app and exercise Zombies on both maps plus the TDM packaged flow. Reuse benchmark evidence only if its recorded source/content fingerprint still matches; changes affecting simulation/rendering invalidate it.

**Gate:** All required Zombies assertions and visual/export/performance gates pass. Existing TDM checks retain their expectations; inherited failures remain disclosed separately. Report counts, named failures, captures, source fingerprint and raw frame evidence. A document check or headless run never substitutes for gameplay or rendering acceptance.

## 4. Verification without redundant full runs

During development, run the changed feature's focused cases plus relevant existing regressions. Repeat a wider suite when shared code changes or a failure creates uncertainty. At M7 run the full required set. Attach evidence to the milestone while context is fresh.

| Change | Smallest meaningful evidence |
|---|---|
| Damage, pool, rounds or AI | Zombies lifecycle cases; existing core/combat checks |
| Inventory, perks or reloading | Transactions/modifier cases; existing weapon/core checks |
| Navigation, builder or layout | Marker/portal graph checks plus actual baked-path/collision probe |
| Rig, HUD, audio or effects | Rendered inspection; relevant character/audio/graphics checks |
| App, save or input flow | Input-driven pause/death/rematch smoke plus TDM counterpart |
| Simulation/rendering cost | 60-second diagnostic while iterating; full final benchmark after stability |

Mode-aware commands and the Zombies suite are implemented in tools/dev.py; see README.md for executable examples.

Performance acceptance on each map: M2, Medium, 1920 × 1080 internal resolution, VSync off, no frame cap, normal simulation, 30-second warmup and 600 measured seconds; average ≥60 FPS, p95 ≤20 ms, p99 ≤33.3 ms. Store all raw frame intervals and configuration. Test 24 live enemies including crawlers, active barriers, repeated wonders and full presentation budgets.

Bounded presentation: eight total corpses/12-second life, at most six simulated ragdolls; 12 nonblocking limbs/8-second life; 32 energy projectiles; four pickups; four shadowless station lights. Share resources and use the existing CPU-effect pools. Preserve required behavior and the 24-enemy cap when optimizing.

Final manual scenarios: identify exits and purchases without external directions; train in both loops; create and preserve a crawler; compare wall ammo with box risk; feel perk changes/loss; fire each wonder; recover or die; rematch. Record human feedback honestly. Automated route completion does not prove fun.

## 5. Working protocol and progress

Before each milestone, read its specification sections and the current code; record intended files and checks. Implement the smallest complete slice, verify it, then update this table with actual evidence. Keep tuning values only in canonical data and the specification; this plan does not duplicate their numbers. Capture remaining work on interruption so another run can resume at the next unmet gate.

| Milestone | Status | Evidence / next unmet gate |
|---|---|---|
| M0 | Verified | Core 48 / content 545 / audio 23 shared checks pass; filtered mode seam verified. |
| M1 | Verified | 128 Zombies assertions and eight actual walking/crawling route cases pass; full 24-enemy performance measured. |
| M2 | Verified | Finite round/barrier/wall loop and last-crawler retention verified; both 20-round soaks pass. |
| M3 | Verified | Purchases, box states, perks, power, upgrading, drops, revive and records covered by runtime assertions and native input smoke. |
| M4 | Verified | Three wonders verified; textured 57-bone zombie, real crawler mesh and detached limbs inspected and tested. |
| M5 | Verified | Dead Current: 20 rounds, 28 exported input steps, stable three-rematch nodes; 600 s: 108.974 FPS, p95 15.922 ms. |
| M6 | Verified | Dead Air: 20 rounds, 28 exported input steps, stable three-rematch nodes; 600 s: 82.197 FPS, p95 18.203 ms. |
| M7 | Verified | All 1,369 assertions pass; both native Zombies maps and TDM smoke pass; export signature and raw frame files verified. Human playtest remains separate. |

Implementation began after the user explicitly requested it. The full design specification remains the research reference. Current acceptance evidence and limits are recorded separately in ZOMBIES_VALIDATION.md; milestone implementation is not a claim of human playtesting.

The user’s supplied visual reference led to the documented character/environment revision in ZOMBIES_VISUAL_UPGRADE.md. Final measurements, focus fractions, fixture disclosures, source fingerprint and the retained failed/intermediate runs are recorded in ZOMBIES_VALIDATION.md. No human fun/balance or final visual approval is claimed.
