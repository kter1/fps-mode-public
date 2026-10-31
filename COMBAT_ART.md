# Combat art preparation

All combat art is rebuilt reproducibly from pinned sources with
`python3 tools/dev.py ingest --domain weapons` and `--domain characters`. Each
domain lists its sources in `content/asset_sources/<domain>.json`; downloads are
verified against `<domain>.lock.json` and provenance is written to
`content/manifest/<domain>.json`. Conversion runs in the pinned local Blender
3.6.23 with automatic script execution disabled. Raw downloads stay in
git-ignored folders; only processed output is committed.

## First-person arms

`tools/blender/build_fp_arms.py` dresses para's CC0 MakeHuman arm rig as a
coyote stretch glove with a leather palm and fingertips, knuckle and finger pads
and a wrist strap, plus a ranger-green combat-shirt sleeve with cuff and elbow
pad, using Poly Haven fabric and leather scans. No skin surfaces remain; a
content test fails if any arm material is skin. At runtime `ViewModel` solves
both arms onto the weapon's grip and support sockets every frame, with finger
poses for pistol grip, stock, handguard, pump, magwell, vertical and angled
grips and two-handed pistol.

## Weapons and attachments

`tools/blender/ingest_weapon.py` maps CC0 models onto the fifteen weapon slots
(3DModelsCC0 Guns & Explosives Pack; Poly Haven bolt-action rifle and service
pistol). Five slots are variants of a shared base model with different
furniture, barrels or finish. Each weapon keeps its authored PBR maps, is
normalized to real-world metres (muzzle toward -Z), splits its magazine, bolt
and pump into animated parts, gets a world LOD of at most 5k triangles, and
publishes sockets (grip, support, muzzle, magwell, ejection, optic rail, sight,
butt) in `content/manifest/weapons.json`. `ModelFactory.weapon()` keeps those
materials and reads the sockets; third-person hands use the same points.

`tools/blender/build_attachments.py` models the red dot, holographic sight, 3×
scope, suppressor, compensator, vertical and angled grips and bipod with bevels
and PBR finishes. Reflex reticles are emissive lens surfaces; 3× and 6× optics
draw a scope eyepiece with a duplex reticle.

## Soldiers

`tools/blender/ingest_soldier.py` converts Mixamo's "Swat Guy" and the rifle
locomotion packs into one GLB: sci-fi exoskeleton parts removed, about 29.5k
triangles with automatic LODs, 1.80 m tall, 52 bones, 41 in-place clips with
measured ground speeds, and 2K PBR maps recoloured per team (woodland camouflage
with ranger-green gear for Blue, desert camouflage with coyote gear for Red).
`SoldierFactory` drives an AnimationTree (standing and crouching blend spaces,
airborne blend, additive recoil); `stance_modifier.gd` turns the spine to the
aim, places the rifle from the motion-captured hold and closes both hands on the
weapon. Reload, grenade and melee motions are procedural because the packs have
no such clips. Deaths become ragdolls carrying the hit impulse (at most six
simulate at once). Distant or off-screen soldiers update their animation at a
reduced rate.

## Effects

Tracers are moving streaks; impacts use per-surface particles and pooled
bullet-hole decals; muzzle flashes animate with a short shadowless light; brass
is a modelled casing; smoke grenades are particle clouds.

### Destructibles and glass

`MapArena` registers interactive props at load by node name (no re-bake), see
`game/combat/destructible.gd`: each `Drum*` collider (and its nearest scanned
barrel, repainted hazard red), each `Prop_covered_car*` and each solid
`WindowGlass*` pane. MultiMesh clutter barrels stay inert. A punctured barrel
explodes after 8-12 s, six hits or any blast within 4 m detonate it at once (5 m
blast, 110 damage). Cars have 400 HP: smoke below half, fire below a quarter,
explosion five seconds after ignition (7 m blast, 140 damage), then a charred
wreck with unchanged collision burning for 20 s. Bullets always continue through
glass (15% damage lost per pane); a pane that is its own node shatters on the
first hit, while intact glass still blocks bot sight (`visible_between`).
`MatchWorld.blast()` is the one radial-damage rule (grenade frags included);
explosions are queued and resolved after `resolve_damage` each tick so chains are
deterministic and kills credit the slot that started them (weapon ids `barrel`
and `car`). Effects: `MatchEffects.explosion` (synthesised `explosion.ogg`),
a pool of four flame/smoke emitters (`burning`), shard bursts with `glass_break.ogg`,
and a `shake_requested` signal the app scales by distance and the camera-kick
setting. Both sounds come from `tools/synthesize_destruction_audio.py` (numpy;
no recorded samples). `tools/destruction_probe.gd` renders screenshots of a barrel
blast, a car burning down to a wreck, and a 3-car + 6-barrel stress run.

## Inspection

`inspect-arsenal` captures hip and ADS views for all fifteen weapons,
`inspect-optics` the gameplay sight pictures, and `inspect-operators` the
soldier poses. This is realistic art within Godot on this hardware, not AAA
photorealism.
