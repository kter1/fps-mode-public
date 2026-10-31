extends SceneTree

# Rendered probe for destructibles. Clones a map's own car and drum into an open
# stage, saves screenshots of a barrel blast, a car burning down to a wreck, then
# detonates 3 cars + 6 barrels within two seconds while the match runs and records
# frame times (JSON + PNGs in .artifacts/probes).
#   godot --script res://tools/destruction_probe.gd -- --map=foundry [--stress-only]

var world: MatchWorld
var camera: Camera3D
var map_id := "foundry"
var out_dir := "res://.artifacts/probes"
var stage := Vector3.ZERO
var car_source: Node3D
var drum_source: Node3D
var visual_source: Node3D
var copies := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_id = arg.trim_prefix("--map=")
	call_deferred("probe")

func probe() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var catalog := Catalog.new()
	world = MatchWorld.new();root.add_child(world)
	world.configure(catalog, map_id, catalog.starter_loadouts()[0], 1, 1201, true)
	while not world.ready_for_play:await physics_frame
	world.arena.apply_quality(1)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	camera = Camera3D.new();camera.fov = 70;world.add_child(camera);camera.current = true
	world.countdown = 0
	var cars := world.destructibles.filter(func(p: Destructible):return p.kind == Destructible.Kind.CAR)
	var drums := world.destructibles.filter(func(p: Destructible):return p.kind == Destructible.Kind.BARREL)
	car_source = cars[0].node;drum_source = drums[0].node
	for candidate in world.arena.find_children("Prop_*arrel*", "Node3D", true, false):
		if visual_source == null or flat(candidate, drum_source) < flat(visual_source, drum_source):visual_source = candidate
	# An open concrete deck high above the map keeps the framing clean.
	stage = Vector3(-300, 60, -300)
	var deck := StaticBody3D.new();deck.collision_layer = 1;deck.position = stage + Vector3(0, -.5, 0)
	var deck_shape := CollisionShape3D.new();var deck_box := BoxShape3D.new();deck_box.size = Vector3(120, 1, 120);deck_shape.shape = deck_box;deck.add_child(deck_shape)
	var deck_mesh := MeshInstance3D.new();var slab := BoxMesh.new();slab.size = Vector3(120, 1, 120);deck_mesh.mesh = slab
	var deck_material := StandardMaterial3D.new();deck_material.albedo_color = Color(.42, .41, .39);deck_material.roughness = .9;deck_mesh.material_override = deck_material
	deck.add_child(deck_mesh);world.add_child(deck)
	print("STAGE ", stage, " cars=", cars.size(), " drums=", drums.size())
	await seconds(1.0)
	if not OS.get_cmdline_user_args().has("--stress-only"):
		var row := stage_group(0, 1, 6)
		var barrels_at: Vector3 = row.barrels[2].center
		look(barrels_at + Vector3(4.5, 1.4, 5.5), barrels_at + Vector3(0, -.1, 0))
		await seconds(.6);shot("barrels_intact")
		for i in 6:row.barrels[0].hit(30, 0)
		await seconds(.12);shot("barrel_blast_120ms")
		await seconds(.35);shot("barrel_blast_470ms")
		await seconds(1.2);shot("barrel_blast_1700ms")
		var car: Destructible = row.cars[0]
		look(car.center + Vector3(6, 2.2, 6.5), car.center)
		car.hit(210, 0);await seconds(.5);shot("car_smoking")
		car.hit(100, 0);await seconds(1.5);shot("car_burning")
		await seconds(3.6);shot("car_explosion_a")
		await seconds(.25);shot("car_explosion_b")
		await seconds(.8);shot("car_explosion_c")
		await seconds(4.0);shot("car_wreck_burning")
	# Stress: three cars and six barrels detonated across two seconds.
	for actor in world.actors:actor.visible = not OS.get_cmdline_user_args().has("--hide-actors")
	if OS.get_cmdline_user_args().has("--no-physics"):world.set_physics_process(false)
	var passes := 2 if OS.get_cmdline_user_args().has("--twice") else 1
	var result := {}
	for pass_index in passes:
		result = await stress_pass(-22 - pass_index * 25, pass_index == 0)
		print("DESTRUCTION_PASS ", pass_index, " ", JSON.stringify(result))
	var file := FileAccess.open(out_dir + "/destruction-" + map_id + ".json", FileAccess.WRITE);file.store_string(JSON.stringify(result, "\t"));file.close()
	print("DESTRUCTION_PROBE ", JSON.stringify(result))
	quit()

func stress_pass(shift: float, capture: bool) -> Dictionary:
	var group := stage_group(shift, 3, 6)
	look(group.barrels[1].center + Vector3(8, 4.5, 15), group.barrels[1].center + Vector3(-1, -1.5, -6))
	await seconds(1.0)
	var times: Array[float] = []
	var started := Time.get_ticks_usec();var last := started;var triggered := 0
	var items: Array = []
	for i in 6:
		if i < 3:items.append(group.cars[i])
		items.append(group.barrels[i])
	var shot_mid := false;var shot_after := false
	while (Time.get_ticks_usec() - started) / 1000000.0 < 8.0:
		await process_frame
		if OS.get_cmdline_user_args().has("--no-physics"):
			world.clock += (Time.get_ticks_usec() - last) / 1000000.0;world.step_destructibles();world.effects.tick(world.clock)
		var now := Time.get_ticks_usec();times.append((now - last) / 1000.0);last = now
		var elapsed := (now - started) / 1000000.0
		if times[times.size() - 1] > 30:print("SPIKE ", times[times.size() - 1], " ms at ", elapsed, " s, detonations so far ", triggered, " burners=", world.effects.live_burners()," gpu=",RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())," cpu=",RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," proc=",Performance.get_monitor(Performance.TIME_PROCESS)*1000," phys=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
		while not OS.get_cmdline_user_args().has("--control") and triggered < items.size() and elapsed >= triggered * 2.0 / items.size():
			var prop: Destructible = items[triggered]
			if prop.kind == Destructible.Kind.CAR:prop.hit(1000, 0)
			else:
				for k in 6:prop.hit(30, 0)
			triggered += 1
		if capture and elapsed > 1.2 and not shot_mid:shot_mid = true;shot("stress_mid");last = Time.get_ticks_usec()
		if capture and elapsed > 3.5 and not shot_after:shot_after = true;shot("stress_after");last = Time.get_ticks_usec()
	var sorted := times.duplicate();sorted.sort()
	var total := 0.0
	for ms in times:total += ms
	var result := {"map": map_id, "frames": times.size(), "avg_ms": total / times.size(), "p95_ms": sorted[int(sorted.size() * .95)], "max_ms": sorted[sorted.size() - 1], "frames_over_50ms": times.filter(func(v: float):return v > 50).size(), "triggered": triggered, "driver": RenderingServer.get_current_rendering_driver_name(), "worst_five": sorted.slice(sorted.size() - 5)}
	return result

func stage_group(shift: float, car_count: int, barrel_count: int) -> Dictionary:
	var made: Array[Node3D] = []
	for i in car_count:made.append(clone(car_source, stage + Vector3(-8 + i * 5.0, 0, -6 + shift), PI * .5 + (.0 if i % 2 == 0 else .1)))
	for i in barrel_count:
		var spot := stage + Vector3(-7 + (i % 3) * 1.4, 0, 1.5 + (i / 3) * 1.6 + shift)
		made.append(clone(drum_source, spot, 0));clone(visual_source, spot, 0)
	world.arena.destructibles = Destructible.scan(world.arena)
	world.destructibles = world.arena.destructibles
	for prop in world.destructibles:prop.world = world
	for node in made:print("MADE ", node.name, " ", node.get_class(), " in_tree=", node.is_inside_tree())
	for prop in world.destructibles:
		if prop.kind == Destructible.Kind.CAR:print("CARPROP ", prop.node.name, " ", prop.node.get_instance_id())
	var result := {"cars": [], "barrels": []}
	for prop in world.destructibles:
		if not made.has(prop.node):continue
		if prop.kind == Destructible.Kind.CAR:result.cars.append(prop)
		else:result.barrels.append(prop)
	print("STAGED cars=", result.cars.size(), " barrels=", result.barrels.size())
	return result

func flat(a: Node3D, b: Node3D) -> float:
	var offset := a.global_position - b.global_position
	return Vector2(offset.x, offset.z).length()

func clone(source: Node3D, at: Vector3, yaw: float) -> Node3D:
	var copy: Node3D = source.duplicate()
	copy.name = String(source.name).rstrip("0123456789") + str(9000 + copies);copies += 1
	source.get_parent().add_child(copy)
	var height := stage.y + source.global_position.y * 0 + (.62 if String(source.name).begins_with("Drum") else 0.0)
	copy.global_position = Vector3(at.x, height, at.z)
	if yaw != 0:copy.rotation.y = yaw
	return copy

func look(from: Vector3, target: Vector3) -> void:
	camera.global_position = from;camera.look_at(target)

func seconds(amount: float) -> void:
	var until := Time.get_ticks_usec() + int(amount * 1000000)
	while Time.get_ticks_usec() < until:await process_frame

func shot(name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(out_dir + "/" + name + ".png"))
	print("SHOT ", name)
