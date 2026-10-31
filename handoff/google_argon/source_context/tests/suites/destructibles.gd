extends RefCounted

# Interactive props: barrels, cars and shoot-through glass. Fixtures sit on their
# own floor far outside the map; time is stepped by hand on the match clock.
const ORIGIN := Vector3(-200, 0, 0)
const TICK := 1.0 / 60

static func run(t) -> void:
	var world := MatchWorld.new();t.root.add_child(world)
	world.configure(t.catalog, "foundry", t.catalog.starter_loadouts()[0], 1, 1201, true)
	while not world.ready_for_play:await t.physics_frame
	world.set_physics_process(false);world.clock = 10
	var counter := {"blasts": 0, "feed": []}
	world.effects.shake_requested.connect(func(_at: Vector3, _strength: float):counter.blasts += 1)
	world.elimination.connect(func(text: String, _team: int):counter.feed.append(text))
	fixture(world, ORIGIN + Vector3(0, -.5, 0), Vector3(60, 1, 60))
	await t.physics_frame

	# Registration by node name; clutter barrels (MultiMesh) stay inert.
	var kinds := {Destructible.Kind.BARREL: 0, Destructible.Kind.CAR: 0, Destructible.Kind.GLASS: 0}
	var wired := true;var tinted := 0
	for prop in world.destructibles:
		kinds[prop.kind] += 1
		wired = wired and prop.body.get_meta("destructible") == prop and prop.world == world and prop.state == Destructible.State.INTACT
		if prop.kind == Destructible.Kind.BARREL and not prop.visuals.is_empty():tinted += 1
	var drums := world.arena.find_children("Drum*", "Node3D", true, false).size()
	t.check_that(kinds[Destructible.Kind.BARREL] == drums and drums > 0 and kinds[Destructible.Kind.CAR] > 0 and kinds[Destructible.Kind.GLASS] > 0, "destructibles_registered_by_name", str(kinds))
	t.check_that(wired and tinted == drums, "destructibles_wired_and_barrels_tinted")
	t.check_that(world.active_destructibles.is_empty(), "intact_props_are_not_ticked")

	# A puncture starts a timed fuse; the barrel then explodes on its own.
	var barrel := prop(world, Destructible.Kind.BARREL, ORIGIN)
	barrel.hit(30, 0)
	var fuse := barrel.fuse_at - world.clock
	t.check_that(barrel.state == Destructible.State.LEAKING and fuse >= 8 and fuse <= 12, "single_hit_punctures_barrel_with_8_to_12s_fuse", str(fuse))
	advance(world, fuse - .3)
	t.check_that(barrel.state == Destructible.State.LEAKING and barrel.body.collision_layer == 1 and counter.blasts == 0, "barrel_waits_for_its_fuse")
	advance(world, .6)
	t.check_that(barrel.state == Destructible.State.DONE and barrel.body.collision_layer == 0 and counter.blasts == 1, "punctured_barrel_explodes_after_fuse")

	# Six hits explode it at once.
	var quick := prop(world, Destructible.Kind.BARREL, ORIGIN + Vector3(10, 0, 0))
	for i in 5:quick.hit(30, 0)
	t.check_that(quick.state == Destructible.State.LEAKING, "five_hits_do_not_detonate")
	quick.hit(30, 0);advance(world, TICK * 2)
	t.check_that(quick.state == Destructible.State.DONE and counter.blasts == 2, "six_hits_detonate_immediately")

	# Chain reaction: B is 3 m from A, C is 3 m beyond B (outside A's blast), D is
	# 4.5 m from A (inside the blast but beyond the 4 m trigger distance).
	var base := ORIGIN + Vector3(-15, 0, 0)
	var a := prop(world, Destructible.Kind.BARREL, base)
	var b := prop(world, Destructible.Kind.BARREL, base + Vector3(3, 0, 0))
	var c := prop(world, Destructible.Kind.BARREL, base + Vector3(6, 0, 0))
	var d := prop(world, Destructible.Kind.BARREL, base + Vector3(0, 0, 4.5))
	var before: int = counter.blasts
	for i in 6:a.hit(30, 0)
	advance(world, TICK)
	t.check_that(a.state == Destructible.State.DONE and b.state == Destructible.State.EXPLODING and c.state == Destructible.State.INTACT, "blast_triggers_neighbours_on_later_ticks")
	t.check_that(d.state == Destructible.State.LEAKING, "barrel_beyond_four_metres_is_only_punctured")
	advance(world, .6)
	t.check_that(b.state == Destructible.State.DONE and c.state == Destructible.State.DONE and counter.blasts - before == 3, "chain_reaction_runs_through_the_row")

	# Walls occlude: a blast does not reach a barrel or soldier behind a solid wall.
	var wall_origin := ORIGIN + Vector3(0, 0, 15)
	var source := prop(world, Destructible.Kind.BARREL, wall_origin)
	var shielded := prop(world, Destructible.Kind.BARREL, wall_origin + Vector3(3, 0, 0))
	var wall := fixture(world, wall_origin + Vector3(1.5, 1.5, 0), Vector3(.3, 3, 8))
	var enemy: Combatant = world.actors[MatchWorld.TEAM_SIZE]
	ready_actor(enemy, wall_origin + Vector3(2.5, .05, 1.5))
	await t.physics_frame;await t.physics_frame
	for i in 6:source.hit(30, 0)
	advance(world, TICK * 2)
	t.check_that(source.state == Destructible.State.DONE and shielded.state == Destructible.State.INTACT and enemy.health == 100, "walls_occlude_blasts")
	wall.free()

	# Kill credit goes to the slot that started the chain.
	await t.physics_frame
	var kill_a := prop(world, Destructible.Kind.BARREL, ORIGIN + Vector3(15, 0, 15))
	var kill_b := prop(world, Destructible.Kind.BARREL, ORIGIN + Vector3(15, 0, 18))
	ready_actor(enemy, ORIGIN + Vector3(15, .05, 19.2))
	enemy.health = 40;var kills: int = world.slots[0].kills;var feed: int = counter.feed.size()
	await t.physics_frame;await t.physics_frame
	for i in 6:kill_a.hit(30, 0)
	advance(world, 1.0)
	t.check_that(not enemy.alive and world.slots[0].kills == kills + 1 and kill_b.state == Destructible.State.DONE, "barrel_chain_kill_credited_to_instigator")
	t.check_that(counter.feed.size() == feed + 1 and "BARREL" in counter.feed[feed] and world.slots[0].callsign in counter.feed[feed], "killfeed_names_the_barrel", str(counter.feed.slice(feed)))

	# Cars: smoke below 50%, fire below 25%, explosion five seconds after ignition.
	var car := prop(world, Destructible.Kind.CAR, ORIGIN + Vector3(-15, 0, -15))
	car.hit(100, 0)
	t.check_that(car.state == Destructible.State.INTACT, "car_takes_damage_before_smoking")
	car.hit(100, 0)
	t.check_that(car.state == Destructible.State.SMOKING and world.active_destructibles.has(car), "car_smokes_below_half_health")
	car.hit(100, 0)
	var ignited: float = world.clock
	t.check_that(car.state == Destructible.State.BURNING and is_equal_approx(car.fuse_at - ignited, 5.0), "car_burns_below_a_quarter")
	var survivor: Combatant = world.actors[MatchWorld.TEAM_SIZE + 1]
	ready_actor(survivor, ORIGIN + Vector3(-10, .05, -15))
	await t.physics_frame;await t.physics_frame
	advance(world, 4.9)
	t.check_that(car.state == Destructible.State.BURNING and survivor.health == 100, "car_holds_for_five_seconds")
	advance(world, .3)
	t.check_that(car.state == Destructible.State.WRECK and survivor.health < 100 and survivor.health > 0, "car_explodes_five_seconds_after_ignition", str(survivor.health))
	var wreck_hit := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(car.center + Vector3(-3, 0, 0), car.center, 1))
	t.check_that(car.body.collision_layer == 1 and wreck_hit.get("collider") == car.body, "wreck_keeps_collision")
	t.check_that(world.effects.live_burners() >= 1, "wreck_burns")
	advance(world, 20.5)
	t.check_that(not world.active_destructibles.has(car) and world.effects.live_burners() == 0 and car.body.collision_layer == 1, "wreck_stops_burning_after_twenty_seconds")

	# Cars from other map builders (Prop_car_<n>) register like the covered cars.
	var lot := Node3D.new();lot.name = "Lot";world.add_child(lot)
	var named := Node3D.new();named.name = "Prop_car_7";lot.add_child(named)
	var named_body := StaticBody3D.new();named_body.add_child(CollisionShape3D.new());named.add_child(named_body)
	var scanned := Destructible.scan(lot)
	t.check_that(scanned.size() == 1 and scanned[0].kind == Destructible.Kind.CAR, "prop_car_nodes_register_as_cars")
	lot.free()

	# The blast lifts the car's visuals and lets them settle exactly back; the collider never moves.
	var rocker := prop(world, Destructible.Kind.CAR, ORIGIN + Vector3(-5, 0, -30))
	var shell := MeshInstance3D.new();shell.transform = Transform3D(Basis.IDENTITY, Vector3(0, .6, 0));rocker.node.add_child(shell);rocker.visuals.append(shell)
	var collider_at: Vector3 = rocker.body.global_position
	rocker.hit(1000, 0);var peak := 0.0
	for i in 40:
		advance(world, TICK);peak = maxf(peak, shell.position.y - .6)
	t.check_that(rocker.state == Destructible.State.WRECK and peak > .1 and peak < .5, "car_blast_lifts_the_body_slightly", str(peak))
	advance(world, Destructible.CAR_JOLT + .3)
	t.check_that(shell.transform.is_equal_approx(Transform3D(Basis.IDENTITY, Vector3(0, .6, 0))) and rocker.body.global_position.is_equal_approx(collider_at), "car_body_settles_back_to_rest")
	advance(world, 21.0)

	# At most four flame emitters are alive at once.
	var leakers: Array[Destructible] = []
	for i in 7:
		var leaker := prop(world, Destructible.Kind.BARREL, ORIGIN + Vector3(-25 + i * 2.2, 0, 25));leaker.hit(30, 0);leakers.append(leaker)
	t.check_that(world.effects.live_burners() == 4, "at_most_four_burning_emitters", str(world.effects.live_burners()))

	# Grenade frags reach props, and a car blast kills a soldier in range.
	var near := prop(world, Destructible.Kind.BARREL, ORIGIN + Vector3(-25, 0, -25))
	world.blast(near.center + Vector3(2, 0, 0), 6, 120, 0, &"frag")
	t.check_that(near.state == Destructible.State.EXPLODING, "frag_blast_sets_off_barrels")
	var wreck := prop(world, Destructible.Kind.CAR, ORIGIN + Vector3(20, 0, -20))
	ready_actor(enemy, ORIGIN + Vector3(22, .05, -20));enemy.health = 100
	await t.physics_frame;await t.physics_frame
	wreck.hit(1000, 0);advance(world, .5)
	t.check_that(not enemy.alive and world.slots[0].kills == kills + 2 and "CAR" in counter.feed[counter.feed.size() - 1], "car_blast_kills_nearby_soldier")

	# Glass: bullets pass through, losing 15% per pane; a pane shatters on the first hit.
	var shooter: Combatant = world.actors[0]
	var glass_base := ORIGIN + Vector3(0, 0, -15)
	ready_actor(shooter, glass_base);shooter.yaw = 0;shooter.pitch = 0;shooter.ads = true
	ready_actor(enemy, glass_base + Vector3(0, 0, -7));enemy.health = 100
	var pane := prop(world, Destructible.Kind.GLASS, glass_base + Vector3(0, 1.5, -3), Vector3(3, 3, .08))
	var second := prop(world, Destructible.Kind.GLASS, glass_base + Vector3(0, 1.5, -4.5), Vector3(3, 3, .08))
	await t.physics_frame;await t.physics_frame
	var crossed: Array = []
	var through := world.ray(shooter.eye(), shooter.eye() + Vector3.FORWARD * 20, shooter, crossed)
	t.check_that(crossed.size() == 2 and through.get("collider") != null and through.collider.get_meta("actor", null) == enemy, "ray_continues_through_glass_to_the_soldier_behind")
	t.check_that(not world.visible_between(shooter.eye(), enemy.eye(), false), "intact_glass_still_blocks_bot_sight")
	var runtime := shooter.weapon();runtime.ammo = runtime.capacity
	world.damage_queue.clear();world.fire(shooter, runtime)
	var scale := pow(Destructible.GLASS_PASS, 2)
	var distance := shooter.eye().distance_to(enemy.global_position + Vector3(0, 1, 0))
	var expected: Array[float] = []
	for head in [false, true]:expected.append(runtime.definition.damage_at(shooter.eye().distance_to(enemy.global_position + Vector3(0, 1.0 if not head else 1.7, 0)) / runtime.range_scale, head) * scale)
	var landed := world.damage_queue.filter(func(event: DamageEvent):return event.victim_slot == enemy.slot.id)
	var amount: float = landed[0].amount if landed.size() > 0 else -1.0
	t.check_that(landed.size() > 0 and expected.any(func(value: float):return absf(value - amount) < 1.2), "bullet_through_two_panes_hits_actor_with_30_percent_loss", "amount=%s expected=%s distance=%s" % [amount, expected, distance])
	t.check_that(pane.state == Destructible.State.DONE and second.state == Destructible.State.DONE and pane.body.collision_layer == 0, "panes_shatter_on_first_hit")
	t.check_that(world.visible_between(shooter.eye(), enemy.eye(), false), "shattered_glass_no_longer_blocks_sight")
	crossed.clear()
	world.ray(shooter.eye(), shooter.eye() + Vector3.FORWARD * 20, shooter, crossed)
	t.check_that(crossed.is_empty(), "shattered_panes_leave_no_collider")

	# A pane that cannot shatter (merged mesh) still lets shots through.
	var fixed := fixture(world, glass_base + Vector3(5, 1.5, -3), Vector3(3, 3, .08));fixed.set_meta("shoot_through", true)
	await t.physics_frame
	crossed.clear()
	var beyond := world.ray(shooter.eye() + Vector3(5, 0, 0), shooter.eye() + Vector3(5, 0, -20), shooter, crossed)
	t.check_that(crossed.size() == 1 and crossed[0].collider == fixed and beyond.is_empty(), "unbreakable_pane_still_passes_shots")

	# Decorative panes (no collider in the map) become shootable without changing sight lines.
	var decor: Destructible = null
	for candidate in world.destructibles:
		if candidate.kind == Destructible.Kind.GLASS and candidate.body.collision_layer == Destructible.HITBOX_LAYER:decor = candidate;break
	t.check_that(decor != null, "decorative_panes_get_hitbox_only_colliders")
	if decor != null:
		var axis: Vector3 = decor.body.global_basis.z.normalized()
		var from := decor.center + axis * 3;var to := decor.center - axis * 3
		var sight := world.visible_between(from, to, false)
		var seen := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 5))
		t.check_that(sight and seen.get("collider") == decor.body, "decorative_pane_stops_bullets_but_not_sight")
		crossed.clear()
		decor.hit(0, 0, seen.position, seen.normal)
		t.check_that(decor.state == Destructible.State.DONE and decor.body.collision_layer == 0 and decor.visuals.all(func(m: MeshInstance3D):return not m.visible), "decorative_pane_shatters_and_disappears")

	world.free()
	await t.process_frame

# A prop with a box collider; `size` defaults to a barrel or car volume.
static func prop(world: MatchWorld, kind: Destructible.Kind, at: Vector3, size := Vector3.ZERO) -> Destructible:
	if size == Vector3.ZERO:size = Vector3(1, 1.24, 1) if kind == Destructible.Kind.BARREL else Vector3(2, 1.5, 4.5)
	var none: Array[MeshInstance3D] = []
	var root := Node3D.new();world.add_child(root);root.global_position = at
	var body := StaticBody3D.new();body.collision_layer = 1
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size = size;shape.shape = box;shape.position = Vector3(0, size.y * .5, 0)
	body.add_child(shape);root.add_child(body)
	var result := Destructible.make(kind, root, body, none, at + Vector3(0, size.y * .5, 0))
	result.world = world;world.destructibles.append(result)
	return result

static func fixture(world: MatchWorld, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new();body.collision_layer = 1
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size = size;shape.shape = box;body.add_child(shape)
	world.add_child(body);body.global_position = center
	return body

static func ready_actor(actor: Combatant, at: Vector3) -> void:
	actor.alive = true;actor.health = 100;actor.protected_until = 0;actor.last_damage_at = -100
	actor.global_position = at;actor.velocity = Vector3.ZERO
	actor.collision_layer = 2;actor.head.collision_layer = 4;actor.torso.collision_layer = 4

static func advance(world: MatchWorld, seconds: float) -> void:
	for i in int(ceil(seconds / TICK)):
		world.clock += TICK
		world.step_destructibles();world.effects.tick(world.clock)
