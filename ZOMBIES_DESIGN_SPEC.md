# Zombies mode: research and detailed design specification

Prepared October 20, 2026 for **GPT 6.1 SOL Light** in this FPS Mode project.
Status: planning only. [ZOMBIES_IMPLEMENTATION_PLAN.md](ZOMBIES_IMPLEMENTATION_PLAN.md) is the canonical execution plan. This reference owns the researched mechanics, initial tuning, map designs and detailed acceptance cases; the execution plan owns sequencing and module boundaries. Read only the sections needed for the current milestone. No game code has been implemented.

## 1. Product decision and completion target

Build an offline, solo, endless, round-based Zombies mode alongside the existing 8v8 Team Deathmatch. Use the recognizable early Zombies survival loop: pistol and knife, scarce ammunition, repairable window barriers, points, purchased doors, chalk wall weapons, a random weapon box, powerful wonder weapons, perk machines, power, and weapon upgrading.

The complete first release includes **two finished maps, three mechanically distinct wonder weapons, five perks, five power-up drops, and one usable trap per map**. Build a small playable portion of Dead Current early, finish the shared systems and that map, then add Dead Air through the same content schema. A one-room wave shooter, stationary shooting targets, or placeholders replacing the requested crawler/wall-buy/box behavior do not complete the task.

The game remains native Godot 4.7.2 and fully offline. Online co-op, AI squadmates, account progression, weapon rarity tiers, armor/salvage/crafting, GobbleGums, elaborate boss quests, and exfil are later work. These exclusions keep this release focused on the requested classic experience. “Legendary guns” means memorable rare wonder weapons here, not a mandatory modern orange-rarity system.

Keep the reference roles recognizable while making the shipped map geometry, machine art, weapon models, sounds, and fiction original. Reference names below explain the intended mechanics.

## 2. What the study established

The sources describe different games and eras. They establish the principles below; they do not establish one universal set of Zombies statistics. All exact rules and numbers from section 4 onward are **proposed tuning for FPS Mode**, not claims about Call of Duty.

| Studied system | Evidence and design lesson |
|---|---|
| Barriers and competing purchases | Official BO4 guidance says rebuilding barriers yields points and delays incoming zombies; kills fund doors, wall weapons, and box spins. Defense, progression, and firepower compete for one budget. [Voyage of Despair, 2018](https://www.callofduty.com/blog/2018-10/voyage-of-despair.html). |
| Pistol start, chalk outlines, matching ammunition | Activision's Mobile primer explicitly describes pistol/knife starts, boarded windows, chalk weapon outlines, and buying matching ammunition at the same outline. Use these readable physical interactions rather than a generic shop menu. Its automatic boarding is a Mobile-specific implementation, not a requirement here. [Official Zombies primer, 2019](https://blog.activision.com/call-of-duty/2019-11/Welcome-to-CODM-Zombies). |
| Random box, relocation, route pressure | The Treyarch-approved BO2 supplemental guide describes guaranteed wall weapons/ammunition, random box weapons, and relocation between several sites. It also explains the benefits and risks of open streets, cramped interiors, and ammunition availability. [BradyGames/Pearson BO2 supplement](https://ptgmedia.pearsoncmg.com/imprint_downloads/brady/colin/black_ops_2_zombies_supplement_11-12.pdf). |
| Wonder-weapon excitement | Treyarch describes the Ray Gun's rare box discovery as a memorable reward. A special gun needs unmistakable shape, sound, firing behavior, and ammunition pressure, not only a damage multiplier. [Ray Gun retrospective, 2023](https://www.callofduty.com/ca/en/blog/2023/03/call-of-duty-franchise-ray-gun-history-treyarch-intel-interview-collectible). |
| Perks and era differences | Treyarch's Cold War guide identifies health, recovery, reload, movement, and critical-shot perks. It calls weapon rarities and permanent perk skill upgrades new systems. Cold War's published numerical effects should not be copied as though they were BO1 rules. [Treyarch gameplay guide, 2020](https://www.treyarch.com/game-intel/2020/10/Black_Ops_Cold_War_Zombies_Gameplay_Guide). |
| Modern comparison | BO6 retains chalk wall buys, random box rewards, box relocation and its location beam, power-gated upgrading, perks, and timed drops. It also uses separate currencies and several progression layers. Borrow the readable survival interactions, while keeping this project's first release to one currency and one weapon-upgrade tier. [BO6 systems deep dive, 2024](https://www.callofduty.com/blog/2024/08/call-of-duty-black-ops-6-zombies-deep-dive-terminus-map-intel). |
| Fun circulation and geography | Official Shi No Numa guidance highlights alternate routes, cramped huts, open space for grouping a horde, multiple entry directions, hazardous terrain, and traps with cooldowns. The implementation inference is to combine maneuvering spaces with risky transitions and valuable destinations. [Shi No Numa survival guide, 2022](https://www.callofduty.com/blog/2022/06/call-of-duty-vanguard-zombies-shi-no-numa-survival-guide-map). |
| Strong map identity | Nacht's airfield, Kino's cinema, Ascension's cosmodrome, and Shi No Numa's swamp illustrate distinct settings and spatial threats. Build places players can remember and learn. [Official Zombies Chronicles map descriptions](https://www.callofduty.com/zombieschronicles). |

**Research limit:** Primary prose reviewed did not establish exact grenade-to-crawler thresholds or Thundergun damage statistics. Implement the explicitly requested leg-loss behavior and compressed-air weapon as deliberate project rules below. Official Kino references to “Crawler Zombies” are not evidence for grenade-dismembered ordinary zombies; those descriptions concern its special crawler enemies.

### Why the loop works

Early rounds teach aim, melee timing, repairing, and saving points. Opening a door grants space and useful purchases while exposing additional entry directions. A reliable wall gun supports ammunition planning; the box offers the chance of an extraordinary tool. Power and an upgrade station create medium-term goals. Perks buy more room for mistakes but consume points that could open an escape route.

Training means gathering the horde into a trailing group and choosing when to turn and fire. It needs predictable pursuit and collision, sufficient maneuvering width, and dangerous entry points. A last surviving crawler creates an intentional interval to buy, repair, and explore. Killing it is the player's decision to advance. This pacing must survive the implementation.

## 3. Project evidence and integration constraints

Read these current files again before implementation; this workspace already contains substantial unrelated edits.

| Existing area | Observed constraint | Planned treatment |
|---|---|---|
| game/core/match_world.gd | TeamDeathmatchMode is inferred concretely; the loop constructs 16 actors, respawns them after three seconds, activates free caches, drops guns, and records replays. | Separate ZombiesWorld lifecycle; retain reusable combat functions and leave TDM defaults intact. |
| game/combat/damage_event.gd and MatchWorld.fire/resolve_damage | Victim IDs index actors/slots, and life_id rejects damage from a previous life. Hurtboxes refer to Combatant. | Stable enemy pool with matching slot/index and life generation. Do not insert/remove actors mid-match. |
| game/actors/combatant.gd | 100-HP regeneration, rifle animation, two guns, speed values, BotController and respawn equipment are embedded. | Parameterize human stats with original defaults; dedicated ZombiePlayer and ZombieActor subclasses. |
| game/combat/weapon_runtime.gd | Useful fire/reload/ammo state exists, but shell reload is hardcoded at 0.6 seconds. | Add baseline-derived modifiers including shell and empty-reload timing; preserve existing behavior with multipliers of 1. |
| game/core/catalog.gd and profile_store.gd | Exactly 15 ordered TDM weapons; primary/sidearm slices validate saved presets. | Separate ZombiesCatalog. Never append wonder guns to the TDM selection list. |
| tools/generate_content.py | Preparation regenerates firearm resources. | Make generated changes in canonical inputs/generators, not only in generated resources. |
| game/presentation/model_factory.gd and view_model.gd | First-person weapons need grip/support/muzzle/sight/reload sockets and component metadata. | Build real wonder-weapon models and authored sockets; verify hand placement and reloads. |
| game/ui/hud.gd, minimap.gd, replay_history.gd | HUD is TDM-specific; minimap/replay paths assume armed actors. | ZombiesHUD; do not attach the TDM minimap or replay recorder in Zombies. |
| MapCatalog, map_definition.gd, tests/suites/maps.gd | Registry maps are assumed to have TDM spawns, eight free ammo caches, objectives and capture cameras. | Mode-aware registry/validation and separate ZombiesMapDefinition. |
| MapArena and tools/prepare.gd | One static nav region, TDM spawn normalization; moving collision alone does not update paths. | Baked per-zone navigation with explicit gated links. Validate exact barrier/portal sockets. |
| MapArena lighting | Baked fixtures are hidden at runtime; Medium disables bloom and volumetric fog. | Always-readable emergency lighting, clear albedo/text affordances, emissive power indicators and few shadowless runtime lights. |
| content/manifest/characters.json | Soldier clips exist; crawler, zombie attack/breach and removable-leg meshes do not. | Explicit new zombie art/animation pipeline and visual acceptance gates. |
| README.md and tools/dev.py | Rendered tools share .tools/render.lock; headless omits visual/audio cost. | Route every bake/render/benchmark through dev.py; add mode-aware QA instead of invoking rendered Godot directly. |

VALIDATION.md contains historical results dated October 17, including 544 passed assertions and incomplete release/performance gates. It is not proof that the current dirty tree or a future horde passes. Establish fresh relevant baselines.

## 4. Decision-complete gameplay contract

### 4.1 Rounds, spawning, and failure

- One human; 24 enemy pool slots maximum. Start with six zombies in round 1.
- Total normal enemies in round r: N(r) = 6 + 3(r - 1) + floor((r - 1)^2 / 8). This is a finite per-round spawn budget, not a requirement to simulate the whole round at once.
- Maximum living enemies: min(24, 6 + 2(r - 1)). A vacated pool slot can receive another budgeted spawn.
- Health: 150 + 50(r - 1) through round 9; from round 10 use round(550 * 1.12^(r - 9)). Compute safely and reject nonfinite tuning values.
- Base pursuit speeds: 1.3–2.0 m/s in rounds 1–3; 2.0–2.8 in 4–6; 2.8–3.8 in 7–10; later maximum 4.4. Seed each enemy's speed within that band. No enemy may exceed unperked human sprint speed.
- Normal melee: 40 damage, 1.35 m reach, 0.4-second visible windup, 1.0-second attack interval. Recheck reach, line of sight, and target state at the hit frame. Per-enemy hit cooldown; no unavoidable contact damage every physics tick.
- Spawn interval: max(0.45, 2.0 - 0.08(r - 1)) seconds. Choose eligible entries in opened zones with a route to the player. Avoid repeating an entry more than twice when alternatives exist.
- An entry with its attack/queue/staging capacity occupied is ineligible; try other eligible entries before retrying later. Never stack an additional spawn into an already reserved approach socket.
- A spawn consumes the budget only when a pooled enemy has actually activated at a valid socket. Failed placement retries; it neither loses an enemy nor fabricates a kill.
- First round begins after a 5-second ready period. Between cleared rounds allow 10 seconds, play distinct start/end cues, and restore frags to at least two, capped at four.
- Round ends only when remaining_to_spawn == 0 AND living_count == 0. Crawlers, barrier attackers and enemies entering through a window count as living. A low remaining count alone never advances the round.
- Do not auto-kill, time out, or silently replace a valid last crawler. There is no overall match timer or kill limit.
- Without self-revive, lethal player damage ends the run and shows rounds completed, highest round reached, kills, headshots, points earned and survival time. Rematch resets everything.

### 4.2 Points, purchases, and inventory

Start at 500 points with an unmodified P9 pistol (8 loaded, 32 reserve), knife, two frags, and no smoke. ZombiePlayer uses a per-instance pistol definition; never alter the shared TDM pistol resource. There is initially one owned firearm; acquire a second before two-slot swapping is available.

| Event | Award |
|---|---:|
| Valid nonlethal firearm hit | 10 |
| Body kill | 60 |
| Headshot kill | 100 |
| Knife kill | 130 |
| Frag or wonder-weapon kill | 50 |
| Successfully replace one missing plank | 10 |
| Trap kill | 0 |

Only conventional firearms earn nonlethal hit points, capped at five awards per enemy life and at one award per trigger shot per victim. Wonder-weapon nonlethal hits earn none. Shotgun pellets cannot multiply the award. No hit award on the killing event; select exactly one terminal kill award. No points for damage to corpses, protected/inactive enemies, friendly targets, or duplicate death processing. Repairs award at most 100 points per round; further repairs still work. Double Points multiplies valid rewards while the unmultiplied repair budget remains capped.

Use one authoritative purchase function: revalidate target, price, power, inventory eligibility and distance; debit once; grant once; publish result. Failed or cancelled validation spends nothing. Reset-on-load and input repetition must not duplicate grants.

On buying a new gun, fill the empty slot first, then replace only the selected weapon. Reject a duplicate owned base weapon; use its ammunition purchase instead. Box results never overwrite anything until explicitly claimed. Purchased replacements do not drop free ammunition or a free world gun. New conventional purchases arrive with a full magazine and reserve_max = 5 × their unupgraded configured magazine capacity; the starting pistol's 8/32 rule is the exception. Wonder ammunition follows its explicit table.

### 4.3 Repairable window barriers

Each barrier has six individually visible wooden planks, outside approach/queue sockets, one attack socket, a traversal path, and an inside navigation destination. A barrier is an enemy entrance, separate from a purchased door.

- Hold Interact within 2.2 m and look toward the barrier to replace one missing plank every 0.65 seconds. Cancel on releasing, leaving range, looking away, damage, pausing, or another blocking action. Revalidate before each plank commit.
- One assigned zombie tears a plank every 1.2 seconds; up to two queue behind it without stacking inside each other. Missing planks visibly expose the doorway/window.
- At zero planks reserve the traversal and enter with a visible breach/vault animation, then pursue the player. Reserve traversal before repair commits in that tick; a repairing plank cannot trap an enemy halfway through.
- No player escape through the window into spawn staging. Its perimeter collider remains separate from visual planks; enemy traversal uses the scripted path.
- Bullets and blast traces use the same authored opening rules. Enemies inside the map never become dependent on returning to a window.
- Repairs buy time; they are not an invulnerable forcefield. Play localized tear, repair and entry sounds, and display plank/hold progress.

### 4.4 Grenade leg loss and crawlers

Reuse the existing frag throw, fuse, bounce, blast falloff and occlusion. Zombies-specific frag damage is 350 at the inner 2 m, falling linearly to zero at 6 m. Keep TDM's existing grenade values.

Resolve a frag victim in this order:

1. Validate life generation and visibility; calculate ordinary blast damage and a separate lower-body exposure ray to a point 0.3 m above the feet.
2. Apply health damage. If lethal, process death once and stop. A fatal blast must never resurrect a crawler.
3. If still alive, a normal standing zombie becomes a crawler when lower-body exposure is clear, the blast origin is no more than 1.2 m above its feet, and lower-body falloff damage is at least 60. These are deterministic authored thresholds, not a random roll.
4. Preserve actor identity, life_id, remaining health and round membership. Change locomotion state once, disable/hide severed leg geometry, emit at most two bounded limb props, and switch hurtboxes and capsule at the physics-safe boundary.

Crawler: 0.65 m/s, approximately 0.7 m total collision height, appropriately lowered torso/head/aim target, real arms-driven crawling animation, 1.1 m melee reach, 0.5-second windup and 1.4-second attack interval. It still hurts the player. Rendered anatomy and collision must agree; it is not a scaled-down walking soldier.

A crawler cannot vault through a standing-only entry animation. If injured outside, preserve its barrier assignment: it still queues and tears remaining planks with compatible low behavior, then reserves low traversal only at zero planks. If injured during an already reserved entry, keep that reservation and progress while blending to the low traversal, ending at the same authored interior endpoint. Test conversion with six, partial and zero boards and during ENTERING. Use the same sufficiently tall floor routes as normal enemies; no crawler-only under-table shortcuts in this release.

The final crawler deliberately allows purchases and map exploration. For genuinely stuck enemies, first repath; after 12 seconds of movement failure, recover only when fully outside the player's view and at a valid unobserved entry in an open, connected zone. Preserve health, crawler state, identity and accounting; award no points. A nearby valid crawler must never trigger recovery merely because it is slow.

### 4.5 Chalk wall weapons

White, visibly hand-drawn weapon silhouettes sit on actual walls at readable height. Include the matching gun profile, price, interaction prompt and purchase sound; legibility must work at Medium with bloom disabled.

| Gun | Purchase | Reserve refill | Intended location/role |
|---|---:|---:|---|
| P9 | 500 | 250 | Start room; emergency ammo |
| P12 Pump | 750 | 375 | Start/early branch; close defense |
| MP9 | 1,000 | 500 | First expansion; dependable point gun |
| A4 Carbine | 1,500 | 750 | Mid-route; flexible survival |
| L56 Support | 2,000 | 1,000 | Riskier later destination; sustained fire |

Normal purchased guns use existing models and original firearm behavior. Zombies-only gun damage uses a 2.0 multiplier over existing base firearm damage; the starting P9 instead uses 20 base damage. Apply headshot multipliers after mode damage. Knife damage is 150, preserving a useful early-round melee decision rather than TDM's permanent one-strike kill.

Refills restore reserve to the gun's configured maximum and leave the current magazine unchanged. Reject a full-reserve purchase. An upgraded wall gun retains its base wall identity and costs 2,500 to refill upgraded reserve. Wonder weapons have no wall refill and rely on finite reserves and Max Ammo. Disable TDM supply caches and automatic dropped-gun scavenging.

### 4.6 Mystery box and wonder weapons

One active box among three authored sites per map. The first is fixed in the first expansion; later sites may be in still-locked areas, creating a reason to open them. Display a visible site beacon and map-direction signage. Power is not required.

Box lifecycle: IDLE → ROLLING (3 s) → OFFERED (10 s) → CLOSING (1 s) → IDLE. Spin costs 950; a reveal is seeded once at purchase commit, not rerolled every animation frame. Reject interaction while busy. The gun hovers above the box with its real model, name and claim prompt; timeout forfeits that result and fee.

Eligible result weights: existing 15 conventional guns weight 10 each, Raycaster weight 3, Thunder Cannon weight 2, Arc Rifle weight 2. Exclude owned base IDs and renormalize. Increment the site's accepted-spin counter on every successful debit, including offers that later expire. Spins 1–3 cannot relocate; on spin 4 and later perform a separate 15% relocation roll before choosing a gun. Relocation shows an original mascot/token, refunds that spin, closes for 3 seconds, then moves to another site and resets the site counter to zero. If only one site is configured, disable relocation. A round transition does not reset an offer or move the box.

“Rare” is honest uncertainty, not a promise of a wonder gun after a fixed number of spins. Tests can force a result through QA injection; normal play uses the seeded weighted pool. No real-money mechanics.

| Weapon / reference role | Required firing behavior | Initial tuning and upgrade |
|---|---|---|
| Raycaster / Ray Gun | Visible green energy projectile; swept collision; direct impact plus small splash; distinct coil weapon and energy-cell reload. | 20/160 ammo, semi-auto 180 RPM, 2.4 s reload, 35 m/s projectile, 800 direct plus 300 splash within 1.5 m, 30 self-splash maximum. Same victim gets one combined event, not duplicated direct hits. Upgrade: 40/240, 2× damage. |
| Thunder Cannon / Thundergun | Short, broad compressed-air cone that visibly throws a horde backward; distinctive pressure-chamber model, blast and reload. | 2/12 ammo, 45 RPM, 3.0 s reload, 9 m range, 70° total cone. LOS-tested normal zombies within 6 m die; 6–9 m take 400 damage and 1.2 s stagger/knockback. No effect through walls. Upgrade: 4/24, lethal inner range 8 m, total range 12 m. |
| Arc Rifle / Wunderwaffe role | Initial ray to one target, then visible electrical chains to nearby enemies. | 3/24 ammo, 60 RPM, 2.8 s reload, initial aimed ray range 24 m, 1,200 damage to at most five unique targets, 4 m chain hops and LOS per hop. Stable distance/ID tie-breaks; never chain repeatedly to one victim or through walls. Upgrade: 6/36, 1,800 damage, eight targets. |

These are initial project values. Wonder reloads allow partial-magazine reload, use the same additional 0.35-second empty-magazine penalty as existing guns, and are affected by Quick Hands. Upgrading does not change reload duration. No infinite projectile lifetime, unlimited chain search, screen-wide cone, or hidden conventional rifle beneath the special-gun label. Ray projectiles live at most 3 seconds; cap the global projectile pool at 32. Reuse world occlusion and the same authoritative damage/reward pipeline.

### 4.7 Power, perks, upgrading and traps

The one-time power switch is free after reaching its room. Power activates the weapon-upgrade station, powered traps and every perk machine except Second Wind, which is already available. Make the change visible/audible through machine faces, signs, motors and a few bounded lights. Do not pretend baked ambient illumination can switch off and on.

Use five original machines/icons/audio identities corresponding to these familiar perk roles. A player can own four at once, cannot buy duplicates, and loses every perk on a down. Show the cap before spending.

| Project perk / familiar role | Price | Exact effect |
|---|---:|---|
| Ironheart / Jugger-Nog | 2,500 | Max health 100 → 200; buying adds the gained 100 HP, clamped to 200. |
| Quick Hands / Speed Cola | 3,000 | All reload durations ×0.65, including per-shell intervals and empty reload penalty. |
| Long Stride / Stamin-Up | 2,000 | Walk and sprint ×1.15; crouch, jump and gravity unchanged. |
| Second Wind / solo Quick Revive | 500 | Consume on lethal damage; 3-second downed recovery, then restore to full unperked HP with 2 seconds protection. At most three purchases per run. Machine usable before power. |
| Overdrive / Double Tap role | 2,000 | Conventional firearm cadence ×1.25 and damage ×1.25; no bonus to knife, frags or wonder guns. |

During self-revive, suppress attacks/damage and player weapon use; enemies disperse toward deterministic nearby loiter points rather than camping inside the player capsule. On recovery keep the two guns, current ammo and points, clear every perk, recompute original stats and resume pursuit after the protection interval. Do not invoke ordinary respawn/loadout reset. Without an owned unused Second Wind, end the run.

Recompute every derived stat from immutable weapon/attachment/mode baselines plus current perks and upgrade flag. Never multiply the already-modified value on purchase, switch, revive or reload. Ordinary TDM uses neutral multipliers.

Upgrade station (Pack-a-Punch role): 5,000 points, power required, one upgrade per gun. Hold Interact for 2 seconds; switching gun, leaving range or taking damage cancels before debit. Keep the gun in inventory during the hold, block firing, and atomically debit/upgrade/refill on successful completion. Conventional guns gain 3× Zombies damage, 1.5× magazine and reserve, original upgraded names/material accents and firing cue. Wonder upgrades follow the table. Reject repeated upgrades and preserve upgrade state across weapon switching.

One powered trap per map: 1,000 points, 8 seconds active, 45 seconds cooldown, 1-second warning before activation. Contact instantly kills normal zombies and crawlers through the damage pipeline regardless of round HP; no kill/hit points or drops from trap deaths. Deal 50 damage per second to the player with a clear warning and a usable escape route. A trap must not require resetting the map or block the only route to the final enemy.

### 4.8 Drops and limited recovery

Five drops: Max Ammo (weight 30), Double Points (25), Insta-Kill (20), Nuke (10), Carpenter (15). Eligible player-caused kills inside the playable area roll 8%, with at most three drops per round, a global 8-second spawn cooldown, and at most four live pickup nodes. No drops from trap kills, staging enemies or corpse damage. Dedicated seeded loot RNG; pickup life 20 seconds, blinking in its last 5 seconds.

- Max Ammo: refill loaded magazine and reserve on both owned guns; restore frags to at least two, capped at four. This magazine refill is an intentional project convenience.
- Double Points: 30 seconds; valid hit/kill/repair rewards ×2. Repick resets remaining duration to 30 seconds; no multiplicative stacking.
- Insta-Kill: 30 seconds; valid firearm/projectile/knife hits kill normal zombies or crawlers. It never makes players invulnerable or bypasses world collision.
- Nuke: kills currently living enemies after a short visible pulse and gives 400 points total, doubled only if Double Points is active. No per-enemy rewards, drops or dismemberment. Does not remove the round's not-yet-spawned budget.
- Carpenter: fills every barrier, gives 200 points total (400 during Double Points), and does not create per-plank rewards. Traversing enemies finish their reservation before boards reappear.

Timed effects use the match clock and pause with gameplay. Drops have distinct shapes/text, sounds and HUD timers; color alone is insufficient. No decoy, dog round or boss is required for this release.

## 5. Two maps designed for this loop

Both are new layouts using existing material/prop kits. Do not modify current TDM Airport or Blackout geometry to create them. Dimensions are the playable footprint, not permission for long empty runs. Author enough room for a 24-enemy horde and two-way escape choices.

### Map A: Dead Current — quarantined coastal power station

ID dead_current; approximately 88 × 72 m. Industrial dusk, emergency lamps, a recognizable central turbine, salt-stained brick and a switchyard against the seawall. Start confined, discover two branches, turn power on above the turbine, then open a second training loop.

| Zone | Role and contents |
|---|---|
| Intake Office | 14 × 14 m start; four windows, desk island, P9 and P12 chalk buys, Second Wind, two visible exits. |
| Service Yard | ~18 × 16 m clear oval around generator island; MP9, Long Stride, first box site. |
| Workshop | Alternate early route with shelves, safe-width passages, A4 and Quick Hands. |
| Turbine Hall | ~28 × 24 m; figure-eight paths around two turbines, Ironheart, L56 and second box site. |
| Control Deck | 3.2 m raised destination with ramps at both ends; power and upgrade station, never a one-ramp camping platform. |
| Switchyard | ~22 × 18 m training loop around transformers; Overdrive, third box site, electric trap and seawall shortcut. |

Gate graph and prices (all bidirectional, open permanently once paid):

~~~text
Intake --750--> Service Yard --1000--> Turbine Hall --1250--> Control Deck
   |                                      |
  750                                   1250
   v                                      v
Workshop --------1000--------------> Switchyard
   |                                 |
   +------1000--> Turbine Hall        +------1000--> Service Yard
~~~

Interpret this as an undirected graph; repeated names denote the same zone. Workshop → Switchyard is the alternate late approach. Both initial branches can reach power; no box luck is required. Four start barriers plus two in each of the other five zones gives 14 total. Keep repair sockets out of main traffic.

### Map B: Dead Air — sealed regional airport service concourse

ID dead_air; approximately 80 × 64 m. Fluorescent quarantine signage, abandoned check-in desks, baggage machinery, a broad gate lounge and rain-dark service ramp. Reuse the airport art vocabulary without copying its entire 112 × 88 m TDM layout.

| Zone | Role and contents |
|---|---|
| Ticket Office | Start, four barriers, P9/P12 chalk buys, Second Wind. |
| Security Hall | Tight lane with screening islands, MP9, Quick Hands, first box site. |
| Baggage Service | Alternate early branch, low visual clutter, A4, Long Stride; carousel island training path. |
| Gate Lounge | Main open loop broken by seating islands; Ironheart, L56, second box site. |
| Maintenance Room | Power/upgrade destination with two doors; Overdrive. |
| Loading Apron | Longer exposed loop around a baggage tractor and containers; third box, powered shutter/electric trap and return shortcut. |

Gate graph:

~~~text
Ticket --750-- Security --1000-- Gate Lounge --1250-- Maintenance
   |                              |                     |
  750                            1000                  750
   |                              |                     |
Baggage --------1000--------- Loading Apron --------------+
   |
   +-------------1000--------- Gate Lounge
~~~

Baggage → Lounge and Lounge → Apron give early circulation choices; Maintenance can be reached from either later approach. Four starting barriers plus two per other zone gives 14. Both maps contain all five perk machines, five wall guns, three box sites, one power switch, one upgrade station and one trap.

### Spatial acceptance for both maps

- At least two distinct training loops and one pressured camping position with multiple enemy approaches.
- Usable main paths at least 3 m clear width; important door thresholds at least 2 m after nav clearance, with measured actual passage tests.
- Machines sit off the main running line, visibly identifiable, with room to turn and leave. No purchase requires guessing an invisible trigger.
- Power is a readable mid-run goal; health perk and first box are discoverable before full-map exploration.
- New entries activate as zones are unlocked. Exterior staging remains hidden; no enemies pop into an occupied player view inside a room.
- All-open navigation reaches every floor destination; closed gates cannot be bypassed by nav, jumping or barrier holes. Test every reachable gate-open subset in graph tests and representative actual geometry paths.
- Use consistent signs, zone names, sound landmarks, worn floor routes and original environmental storytelling. A small optional three-switch secret grants a one-time Max Ammo on each map; it never gates core progression.
- Human playtests must assess whether loops are readable and entertaining. Automated path completion cannot certify fun.

## 6. Implementation architecture and interfaces

### Keep the existing FPS playable throughout

Add a mode selector before battlefield selection. TDM keeps its six current maps, saved loadouts, 8v8 roster, 100-kill/600-second rules, three-second respawns and replay behavior. Zombies lists only its two maps, explains the pistol start and shows its local records.

Use this concrete integration approach:

- Add mode_id = "tdm" to MatchWorld. Change its inferred concrete mode field to an explicitly Variant mode object, defaulting to TeamDeathmatchMode. Document the shared begin/tick/on_actor_died/get_result/finished contract. This avoids requiring a broad inheritance refactor or adding fake TDM scores/timers to ZombiesMode.
- Add ZombiesWorld extending MatchWorld. Override configure, the physics lifecycle, player/enemy death and mode-specific damage hooks. Retain the base catalog, effects, actor references, world clock, bullet tracing, throws, explosion occlusion and destructibles.
- Instantiate 25 stable slots: human index 0, zombie pool indices 1–24. slot.id always equals its array index. Increment life_id on each activation; clear pending action, collision, anatomy, movement, attack, sound and navigation state on reuse. Inactive enemies are alive=false, hidden and noncolliding.
- ZombieActor extends Combatant only to satisfy existing combat-target assumptions. It creates body/head hurtboxes with actor metadata but does not create guns, gun mounts, SoldierFactory animation, or BotController. Override all setup/movement/respawn/animation paths that assume weapon(). Use a dedicated ZombieFactory; initially keep enemy decisions in ZombieActor and extract a controller only when its actual complexity warrants it.
- ZombiePlayer extends Combatant, starts with a single owned WeaponRuntime and adds a second on purchase. Update Combatant.switch_to to reject index >= weapons.size(); a request for an unavailable second slot does nothing. Preserve the normal two-gun TDM behavior.
- ZombiePlayer overrides inherited set_loadout and initialization/reset so it cannot construct the normal primary/sidearm pair. One Zombies inventory factory creates ZombieWeaponRuntime instances for pistol start, wall buys and box claims, with base ID, upgrade flag, immutable baseline stats and explicit reserve_max. Never call MatchWorld.swap_weapon for these purchases: its dropped-gun and fixed-slot semantics belong to TDM.
- Configure human max_health, regeneration delay/rate and walk/sprint multipliers with current TDM defaults (100, 6 seconds, 25 HP/s, 1×). Zombies perks may alter those values. Zombie movement never regenerates health.
- Add an aim_target() getter with the current chest position as default. ZombieActor overrides it for standing/crawling anatomy; use it in aim assist and mode AI.
- ZombiesHUD extends GameHUD for shared feedback and vignette helpers, while replacing connection, drawing and scoreboard behavior. Normalize health effects against actual max_health, not 100. Do not create its TDM minimap, elimination feed or replay UI.

Branch App.start_match, on_match_ended, show_results, qa_tick, finish_benchmark and exported smoke flow into the selected mode's handlers before any access to TDM mode.remaining/scores/kill_limit, TDM replay, or the human's automation BotController. Explicitly type result dictionaries returned through the Variant mode field to avoid GDScript inference errors. A Zombies QA driver issues normal ActorCommand input and explicit QA fixture actions; it does not attach the soldier combat bot or rely on TDM score/time completion. CLI flags alone do not make these existing handlers mode-safe.

Before reuse, audit every shared function's calls to weapon(), bot, gun_mount, mode.scores, arena.ammo_caches and replay objects. Shared functions operating over all actors must tolerate an unarmed zombie or be skipped in Zombies. Do not solve this by equipping invisible rifles.

### Simulation order and enemy state

ZombiesWorld physics order:

1. Return when paused, finished or not ready; advance the same match clock once.
2. Tick mode state and requested spawns, update the human command, and capture interaction intent/progress without committing it. A held upgrade blocks firing immediately.
3. Tick living enemy decisions and reserve barrier entry traversals; update player/enemy movement and collision.
4. Resolve player firearm/melee/throw actions; step grenades/projectiles/traps.
5. Resolve damage in stable order; apply deaths or crawler transitions, then update round accounting.
6. Revalidate and commit interaction intents after damage: damage cancels that tick's repair/upgrade, and reserved entry takes precedence over plank replacement. Then tick pickups, timers, despawning presentation props, effects and bounded audio.
7. Detect round clear after all actions resolve; emit a single run-ended signal when appropriate.

Enemies use these explicit states: INACTIVE, APPROACH_BARRIER, TEAR_BARRIER, ENTERING, PURSUE, ATTACK_WINDUP, ATTACK_RECOVERY, STAGGER, DEAD. Standing/crawling anatomy is an independent persistent flag that selects speed, collision, aim points and animation. Do not duplicate the pursuit/attack state graph for crawlers; stagger/recovery must preserve anatomy. Every state has a valid exit on target loss, barrier change, downing, death or pool reset.

Use NavigationAgent3D to follow authored open-zone routes and local short-range separation. Stagger expensive decisions across enemies: repath at 4 Hz maximum with jittered stable slot offsets, with immediate refresh on a portal change. Avoid per-enemy full-world searches every tick. Preserve physical body blocking and let the horde form a train rather than overlap into a single damage stack. With 24 capped enemies, prefer bounded simple searches until profiling justifies another data structure. Seed spawn, combat, box and drop RNG streams separately; cosmetic choices never advance a gameplay stream.

### Navigation and map schema

- Add supported_modes to registry entries; absent means ["tdm"]. Add MapCatalog.ids_for_mode/entries_for_mode; keep ids() meaning all registered maps for preparation.
- Add optional ZombiesMapDefinition reference to MapDefinition. Include stable zone/portal/barrier/station IDs, player start, entry staging points, traversal endpoints, nav region/link references, purchases, box sites, secret switches and QA routes.
- Store gameplay tuning in content/data/zombies/rules.json and per-map purchase/marker bindings in content/data/zombies/maps/<id>.json. Layout scripts author geometry and stable marker transforms; runtime data binds to those IDs. Do not maintain two competing coordinate lists.
- Add game/maps/zombies_map_builder.gd and a mode-based builder dispatch. The current CompactMapBuilder always creates one region, so merely adding layout markers or a Python wrapper cannot create the required zone topology. Add tools/prepare_zombies.gd for zone baking/validation and have dev.py prepare dispatch to it. MapArena exposes the Zombies region list for save/export/readiness; retain nav_region as the existing TDM singleton.
- Bake disconnected zone regions from explicitly bounded zone sources; do not let every region bake the whole map ground. Exclude runtime door/plank colliders from those bake sources. Gaps at purchased thresholds are navigation-only: physical floor collision stays continuous. Disable automatic edge connections on these regions and validate that each link endpoint attaches to its intended distinct region. Span each threshold with a disabled bidirectional NavigationLink3D. Buying a gate removes its collider and enables its link together, waits for a navigation-server update before declaring the route ready, then refreshes pursuit. Godot documents [automatic region edge connections](https://docs.godotengine.org/en/stable/classes/class_navigationregion3d.html) and [explicit navigation links](https://docs.godotengine.org/en/stable/classes/class_navigationlink3d.html); verify property behavior in the pinned engine. Test no path across a closed portal despite the intact floor, then actual standing/crawler passage after enabling only that link.
- All required crawl routes have normal standing clearance in this release, so one floor-nav profile suffices. Crawlers still require low body collision and low entry traversal.
- Add mode-aware readiness, closest-point and normalization logic. Existing prepare code cannot index spawns_blue[0] on a Zombies map or silently shift a window endpoint up to six metres.
- Topology tests use the authored zone graph; physical navigation tests exercise baked links and actual door colliders. A graph-only test is insufficient.

### Authoritative interaction and damage services

Add ZombieInteractions with a single nearest-visible candidate selection (2.2 m maximum, view cone and clear ray). Candidate includes stable id, type, label, price, enabled/denial reason and hold progress. The HUD draws this exact candidate; it must never advertise one object while the command buys another.

Keyboard E taps purchase/claim/switches, and holds repairs/upgrading. Add interact_held to ActorCommand; clear it on focus loss, pause, death and command reset. Controller Square keeps tap-to-reload when no interaction is active; holding 0.35 seconds captures the visible interaction, suppresses reload, and starts its hold behavior. Release cancels capture. Once a purchase commits, require release before another purchase. A barrier can continue repairing while held, once per plank interval.

Centralize applied-damage handling through small optional hooks on MatchWorld, with default TDM behavior unchanged:

- Per-weapon effective damage/cadence/reload modifiers and firing-behavior dispatch.
- Damage applied and victim killed callbacks for points/drops/anatomy.
- Death handling override so Zombies never schedules a TDM respawn, dropped gun or replay.
- Per-explosion victim metadata for lower-body exposure, damage kind and blast origin.

Concrete call sites: MatchWorld.fire obtains effective conventional damage from runtime/mode before queueing its hit; combat dispatches the selected firing behavior only after one successful try_fire, so a wonder shot consumes ammo and cadence once; knife obtains the mode's melee damage; resolve_damage calls applied-hit/death hooks after protection/team/life validation. Add a neutral cadence multiplier to the runtime rather than mutating shared WeaponDefinition.rpm. Blast LOS uses an anatomy-aware damage point (standing torso or crawler torso), replacing the fixed +0.8 m target in Zombies while retaining the existing TDM target. Low melee reach tests against the standing player's body volume, not only its eye point.

Extend DamageEvent additively with damage_kind, hit_region, impact/origin and reward policy fields. Add source life generation where delayed projectiles/attacks need it. Allocate a fresh monotonically increasing event/action ID for every gunshot, grenade detonation, trap tick and melee swing; do not rely on the current fire-only sequence to deduplicate unrelated events. Keep victim life validation. Record terminal processing once per victim life.

All bullets, wonders, grenades, traps and power-ups pass through that damage pipeline; no separate direct health subtraction that skips scoring, downing or counters. Explosion self-damage remains possible. TDM defaults must not acquire Zombies points or damage scaling.

### Ownership, data, and presentation files

Start with these ownership boundaries; filenames are targets, not a requirement to create empty wrappers. Add a module only when it owns a real lifecycle or shared behavior.

| Responsibility | Initial owner |
|---|---|
| World lifecycle, bounded pool and spawn placement | game/zombies/zombies_world.gd |
| Rounds, points, rewards and run records | game/zombies/zombies_mode.gd |
| Enemy AI, body/posture and pool reset; human inventory initialization | game/zombies/zombie_actor.gd; zombie_player.gd |
| Candidate selection and atomic transactions | game/zombies/zombie_interactions.gd |
| Complex persistent objects | game/zombies/zombie_barrier.gd; zombie_door.gd; mystery_box.gd |
| Simple wall/perk/power/upgrade station definitions | game/zombies/zombie_station.gd with explicit station kinds; extract a kind when its actual behavior warrants it |
| Inventory/runtime and special firing | game/zombies/zombies_catalog.gd; zombie_weapon_runtime.gd; wonder_weapons.gd; energy_projectile.gd |
| Timed pickups and damaging trap volumes | game/zombies/zombie_pickups.gd; zombie_trap.gd |
| Map contract, builder and preparation | game/maps/zombies_map_definition.gd; zombies_map_builder.gd; tools/prepare_zombies.gd |
| Two authored maps | game/maps/layouts/dead_current.gd; dead_air.gd; matching map_list registry files |
| Visuals and UI | game/presentation/zombie_factory.gd; game/ui/zombies_hud.gd; original zombie/weapon/audio content |
| Tuning and provenance | content/data/zombies/; content/manifest/zombies.json; content/licenses/ |
| Focused evidence | tests/suites/zombies.gd; tools/zombies_probe.gd; extend existing mode-aware benchmark tooling before adding another driver |

Reuse the retained Dead Current development area as it expands into the full release layout. Do not create a second disposable map pipeline. Keep the existing renderer lock, export packer and asset preparation entry point.

ZombiesCatalog extends Catalog so existing typed configure calls remain compatible, but keeps legacy weapon_ids unchanged. Load wonder definitions into its weapons dictionary through a separate zombie_weapon_ids collection. Conventional firearms are resolved from Catalog without changing shared resources. Build per-instance overrides/runtime stats for mode damage and starting-ammo values.

ModelFactory should merge a separate zombies weapon manifest for weapon-info/socket lookup without exposing those guns in TDM loadouts. Record actual model licenses and authored source provenance. Add neutral firing behavior and runtime multipliers only where needed; keep special weapon data outside the canonical list of 15 guns.

Persist a versioned optional zombies_records object in ProfileStore, keyed by map/difficulty with highest round reached, completed rounds, kills and best survival time. Missing or malformed optional records fall back safely. Do not reset existing settings/loadouts. There is no save-and-resume feature in this release.

## 7. Art, sound and readability are required work

The current soldier is not the final enemy. Produce one original infected humanoid rig with at least three clothing/material variants; author or obtain suitable licensed walk, faster pursuit, idle, attack windup/hit/recovery, plank tearing, entry, hit reaction, death and true crawler clips.

The mesh needs separable leg geometry with capped wounds or a clean alternate legless mesh. Keep the crawler's shoulders/head physically close to the ground and its arms pulling the torso. Detached pieces are cosmetic, pooled and short-lived. A first implementation may use debug meshes to validate simulation, but the asset gate must replace them before release.

Each wonder gun requires a distinct original model, first-person sockets, working reload component/animation, shot sound and readable effect. The Thunder Cannon's broad pressure blast, Raycaster projectile and Arc Rifle chain must be distinguishable from silhouettes and effects without reading the HUD.

Required world props: repairable windows with six removable boards, chalk silhouettes for five guns, powered/unpowered machine faces for five perks, animated weapon box with offer display and relocation token, power switch, upgrade machine and trap controls.

Required feedback: denied/successful purchase, points gained, perk acquired/lost, health difference, reload speed difference, box rolling/claim/timeout/relocation, power activation, round start/end, crawler leg loss, incoming melee, pickup/timer expiry, self-revive and run end.

Reserve bounded voice pools for zombie groans/attacks and station cues so they cannot interrupt weapon audio. Throttle distant groans; prioritize nearby attack windups. Generate or license original sounds. Respect master volume, pause and focus behavior. Do not use copied Call of Duty recordings or jingles.

Start budgets: 24 living enemy visuals; eight total corpses with a 12-second lifetime and oldest-first eviction, at most six actively simulated as ragdolls; 12 nonblocking cosmetic detached pieces with an 8-second lifetime; 32 live energy projectiles; four pickups; four shadowless station/power lights; and the existing bounded CPU-particle pattern. Share meshes/materials, throttle distant animation, and pool effects. Medium quality must keep every gameplay cue readable without glow, volumetric fog or expensive full-screen effects.

## 8. Verification reference

### Existing commands, valid before implementation

~~~sh
python3 tools/dev.py --help
python3 tools/dev.py check
python3 tools/dev.py test --suite core
python3 tools/dev.py test --suite content
python3 tools/dev.py test --suite audio
python3 tools/dev.py test --suite integration
~~~

Run the smallest appropriate subset per milestone. Shared combat/runtime/profile changes require the related TDM regression checks; final release requires all suites. Record assertion counts and names of failures, not simply “tested.”

### Tooling that must be added before using these commands

Add --suite zombies to dev.py and explicit dispatch in tests/test_runner.gd; unknown suites must fail rather than fall through to integration. Add --mode {tdm,zombies}, default tdm, to run/capture/benchmark/render-cleanup/smoke-export and pass it to app QA. Prepare/inspect select map metadata automatically. Use distinct artifact filenames containing mode, map and seed.

Update tools/release_verify.py and tools/report.py to schedule/read mode-specific evidence. They currently iterate all map IDs, run TDM defaults and expect 16-slot matches, TDM screenshot names and old filenames. Retain TDM-only swapped-team/replay/contact-time gates for TDM maps; add Zombies round/pool/visual/export gates for Zombies maps. Route graphics, capture, overview and minimap probes by supported mode: generic geometry/lightmap checks still apply, while Zombies has no player-facing radar or requirement for TDM capture cameras. Report both modes without overwriting one mode's evidence or weakening existing assertions.

After that support exists:

~~~sh
python3 tools/dev.py test --suite zombies
python3 tools/dev.py prepare --map dead_current
python3 tools/dev.py prepare --map dead_air
python3 tools/dev.py inspect-map --map dead_current
python3 tools/dev.py inspect-map --map dead_air
python3 tools/dev.py capture --mode zombies --map dead_current
python3 tools/dev.py capture --mode zombies --map dead_air
python3 tools/dev.py render-cleanup --mode zombies --map dead_current
python3 tools/dev.py render-cleanup --mode zombies --map dead_air
python3 tools/dev.py benchmark --mode zombies --map dead_current --seed 2601 --seconds 600
python3 tools/dev.py benchmark --mode zombies --map dead_air --seed 2602 --seconds 600
python3 tools/dev.py export
python3 tools/dev.py smoke-export --mode zombies --map dead_current
python3 tools/dev.py smoke-export --mode zombies --map dead_air
python3 tools/dev.py smoke-export --mode tdm
~~~

CLI --mode support and the new suite do not exist at planning time. Do not present the above as commands already run or passing.

### Required automated assertions

| Area | Decisive cases |
|---|---|
| Rounds/pool | Correct counts across 20 rounds; cap never exceeded; failed spawn retries; last living crawler/entry enemy prevents clear; exactly one next-round signal; inactive collision disabled; stale damage rejected after pool reuse. |
| Attacks | Hit-frame distance/LOS recheck; per-enemy cooldown; no damage after death; low crawler aim/hit volumes; self-revive immunity and collision clearance. |
| Crawlers | Eligible surviving frag transforms once; fatal frag stays dead; occluded legs stay standing; hitboxes match anatomy; health/identity remain; state resets on reuse; no automatic last-crawler expiry. |
| Barriers | Six-board bounds; hold cancellation; one repair reward per actual board; per-round cap; tear/repair race; reserved entry not trapped; exterior player containment. |
| Economy/inventory | Exact hit/kill awards, pellet cap, no corpse farming; atomic failures; two-slot replace rules; matched wall refill; upgraded ammo price; no free TDM ammo. |
| Box | Deterministic weighted selection; only one debit; no early replacement; accept/expire paths; duplicate exclusion; relocation refund and new site; reset/rematch. |
| Perks/upgrade | Four-perk cap; repeated recalculation has no drift; HP/regen/movement and all reload types; upgrade retained on switch; interrupted hold spends nothing; down clears perks; revive purchase cap. |
| Drops/trap | Spawn cooldown/round cap/node cap; expiry; timer pause; repeat timed pickup resets; nuke preserves pending budget; Carpenter traversal safety; trap no reward/drop recursion and safe cooldown. |
| Wonders | Swept projectile hits thin walls; finite pools; one combined impact; self-splash; cone range/angle/occlusion; chain unique targets/LOS; upgraded ammo/damage; no damage after run ended. |
| Maps | Marker IDs/references valid; all reachable portal-state subsets have eligible connected spawns; actual locked-door blocking; open-link passage; crawl route; no fallback marker normalization breaking windows. |
| Product/regression | Save migration; pause/focus cancellation; keyboard/controller hold arbitration; three complete rematches; no object/voice growth; TDM roster, timer, scoring, loadouts, maps, replays, grenades and audio remain intact. |

### Rendered and manual acceptance

Capture both maps' starting room, each main loop, a repair in progress, a zombie tearing/entering, actual grenade leg loss, standing/crawler aim hits, each chalk buy, box reveal/relocation, every perk identity, power before/after, upgraded gun, each wonder firing/reloading, down/revive and game-over results. Inspect 720p UI as well as the benchmark resolution; long prompts must fit.

Performance gate: on the target M2, Medium, fixed 1920 × 1080 internal world target, normal simulation, 30-second warmup and 600 measured seconds: average at least 60 FPS, p95 at most 20 ms, p99 at most 33.3 ms. Retain every raw measured frame and report stalls. Exercise 24 living zombies with some crawlers, barrier activity, a full corpse/effect budget and repeated wonder use on each map. A QA-only survival/loadout driver may maintain the scenario; record its settings separately from normal gameplay. First run a 60-second rendered diagnostic as soon as the real enemy rig and pool work; reserve the full 600-second acceptance runs for stable content. Performance fixes preserve the 24-enemy cap and required behavior unless the user approves a scope change.

Also run an unprotected deterministic gameplay scenario through round 20 on each map and a three-rematch cleanup scenario. Headless tests certify simulation, not rendered performance. Keep all rendering under dev.py's shared lock.

Manual play acceptance:

1. A new player can identify the two start exits, chalk weapon and repair prompt without external directions.
2. Both maps allow understandable horde training, dangerous recoverable mistakes and at least two viable progression routes.
3. Deliberately create a crawler, open/buy/repair while it survives, then kill it to advance.
4. Compare wall-gun reliability to box risk; check whether power/health/upgrade purchases produce useful decisions.
5. Feel the health, reload and speed perks, then verify their loss after self-revive.
6. Fire all three wonders into a horde and against walls; confirm distinct effects and finite-ammo pressure.
7. Record actual feedback and tuning changes; do not claim fun or balance from unit tests alone.

### Completion rule

Finished means both maps and all requested mechanics are accessible in the exported native app, visible assets pass inspection, focused tests and previously passing regressions pass, and performance evidence is recorded. Report inherited TDM failures separately without weakening their assertions or expanding this task into unrelated repairs. A remaining crawler placeholder, missing second map, nonworking box claim, untested export or failed Zombies performance gate is outstanding work, not a completed release.

## 9. Optimization notes

The execution plan replaces the original eleven packets with eight milestones. It proves real crawling, gated navigation and representative horde cost early; grows the release map directly; integrates input and tests with each feature; and reuses the first map's schema for the second. Required product scope and the source links above are retained.

Exact numerical tuning remains provisional. Change it in canonical runtime data after collecting evidence, and update this specification in the same change; avoid competing values across code, the plan and UI. Optional three-switch secrets do not block delivery of the requested systems.
