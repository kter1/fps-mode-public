extends SceneTree

# Rendered probe for explosion, smoke, spark and casing effects. Builds an open stage
# high above a map, clones the map's own drum and car onto it, and saves stills.
#   godot --script res://tools/effects_probe.gd -- --map=foundry [--only=barrel,car,smoke,sparks,casings]
# PNGs land in .artifacts/probes/effects.

var world: MatchWorld
var camera: Camera3D
var map_id := "foundry"
var out_dir := "res://.artifacts/probes/effects"
var stage := Vector3(-300, 60, -300)
var car_source: Node3D
var drum_source: Node3D
var visual_source: Node3D
var copies := 0
var only: PackedStringArray = []
var prefix := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_id = arg.trim_prefix("--map=")
		if arg.begins_with("--only="):only = arg.trim_prefix("--only=").split(",")
		if arg.begins_with("--prefix="):prefix = arg.trim_prefix("--prefix=")
		if arg.begins_with("--out="):out_dir = arg.trim_prefix("--out=")
	call_deferred("probe")

func wants(name: String) -> bool:
	return only.is_empty() or only.has(name)

func probe() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var catalog := Catalog.new()
	world = MatchWorld.new();root.add_child(world)
	world.configure(catalog, map_id, catalog.starter_loadouts()[0], 1, 1201, true)
	while not world.ready_for_play:await physics_frame
	world.arena.apply_quality(1)
	camera = Camera3D.new();camera.fov = 70;world.add_child(camera);camera.current = true
	world.countdown = 0
	for actor in world.actors:actor.visible = false
	var cars := world.destructibles.filter(func(p: Destructible):return p.kind == Destructible.Kind.CAR)
	var drums := world.destructibles.filter(func(p: Destructible):return p.kind == Destructible.Kind.BARREL)
	car_source = cars[0].node;drum_source = drums[0].node
	for candidate in world.arena.find_children("Prop_*arrel*", "Node3D", true, false):
		if visual_source == null or flat(candidate, drum_source) < flat(visual_source, drum_source):visual_source = candidate
	var deck := StaticBody3D.new();deck.collision_layer = 1;deck.position = stage + Vector3(0, -.5, 0)
	var deck_shape := CollisionShape3D.new();var deck_box := BoxShape3D.new();deck_box.size = Vector3(120, 1, 120);deck_shape.shape = deck_box;deck.add_child(deck_shape)
	var deck_mesh := MeshInstance3D.new();var slab := BoxMesh.new();slab.size = Vector3(120, 1, 120);deck_mesh.mesh = slab
	var deck_material := StandardMaterial3D.new();deck_material.albedo_color = Color(.42, .41, .39);deck_material.roughness = .9;deck_mesh.material_override = deck_material
	deck.add_child(deck_mesh);world.add_child(deck)
	Engine.time_scale = .2
	await seconds(1.0)
	if wants("barrel"):await barrel_sequence()
	if wants("car"):await car_sequence()
	if wants("smoke"):await smoke_sequence()
	if wants("sparks"):await spark_sequence()
	if wants("casings"):await casing_sequence()
	if only.has("spark_test"):await spark_test()
	print("EFFECTS_PROBE done")
	quit()

func barrel_sequence() -> void:
	var row := stage_group(0, 0, 3)
	var barrel: Destructible = row.barrels[1]
	look(barrel.center + Vector3(2.2, .6, 3.0), barrel.center + Vector3(0, .2, 0))
	await seconds(.6);shot("barrel_close_intact")
	look(barrel.center + Vector3(5.5, 1.6, 7.0), barrel.center + Vector3(0, .6, 0))
	await seconds(.3);shot("barrel_intact")
	for i in 6:barrel.hit(30, 0)
	for delay in [.1, .22, .45, .9, 1.8, 3.5]:
		await seconds(delay - elapsed_since_trigger());shot("barrel_blast_%dms" % int(delay * 1000))
	trigger_mark = Time.get_ticks_usec()
	await seconds(4.0);shot("barrel_aftermath")

var trigger_mark := 0
func elapsed_since_trigger() -> float:
	if trigger_mark == 0:trigger_mark = Time.get_ticks_usec();return 0.0
	return (Time.get_ticks_usec() - trigger_mark) / 1000000.0 * Engine.time_scale

func car_sequence() -> void:
	trigger_mark = 0
	var group := stage_group(-30, 1, 0)
	var car: Destructible = group.cars[0]
	look(car.center + Vector3(7.5, 2.4, 8.5), car.center + Vector3(0, .4, 0))
	await seconds(.5);shot("car_intact")
	car.hit(210, 0);await seconds(1.5);shot("car_smoking")
	car.hit(100, 0);await seconds(1.4);shot("car_burning")
	await seconds(2.0);shot("car_pre_explosion")
	trigger_mark = 0
	while car.state != Destructible.State.WRECK:await process_frame
	trigger_mark = Time.get_ticks_usec()
	for delay in [.05, .15, .3, .6, 1.2, 2.5]:
		await seconds(maxf(delay - elapsed_since_trigger(), 0));shot("car_blast_%dms" % int(delay * 1000))
	await seconds(5.0);shot("car_wreck_burning")

func smoke_sequence() -> void:
	var spot := stage + Vector3(0, 0, 30)
	look(spot + Vector3(12, 2.2, 14), spot + Vector3(0, 1.8, 0))
	var cloud := world.effects.smoke_cloud(spot + Vector3.UP * 1.7)
	await seconds(.3);shot("smoke_cloud_fresh")
	await seconds(3.0);shot("smoke_cloud_3s")
	look(spot + Vector3(6, 1.7, 7), spot + Vector3(0, 1.8, 0))
	await seconds(.5);shot("smoke_cloud_close")
	look(spot + Vector3(2, 1.7, 0.5), spot + Vector3(-3, 1.8, 0))
	await seconds(.3);shot("smoke_cloud_inside")
	await seconds(8.0);cloud.queue_free()

func spark_sequence() -> void:
	var plate := StaticBody3D.new();plate.collision_layer = 1;plate.set_meta("surface", "metal")
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size = Vector3(4, 3, .2);shape.shape = box;plate.add_child(shape)
	var mesh := MeshInstance3D.new();var slab := BoxMesh.new();slab.size = Vector3(4, 3, .2);mesh.mesh = slab
	var steel := StandardMaterial3D.new();steel.albedo_color = Color(.34, .36, .38);steel.metallic = .6;steel.roughness = .45;mesh.material_override = steel;plate.add_child(mesh)
	world.add_child(plate);plate.global_position = stage + Vector3(25, 1.6, 0)
	look(plate.global_position + Vector3(2.5, .6, 6.5), plate.global_position + Vector3(0, .1, 0))
	await seconds(.4)
	var from := camera.global_position + Vector3(.3, -.3, 0)
	for i in 5:
		var hit := plate.global_position + Vector3(-1.0 + i * .5, .3 - (i % 2) * .3, .11)
		world.effects.tracer(from, hit)
	await seconds(.03)
	for k in world.effects.emitters.sparks:print("SPARKS ", k.emitting, " ", k.global_position, " ", k.amount, " ", k.visible, " ", camera.global_position)
	shot("sparks_metal_30ms")
	await seconds(.06);shot("sparks_metal_90ms")
	await seconds(.15);shot("sparks_metal_250ms")
	look(plate.global_position + Vector3(.6, .3, 1.9), plate.global_position + Vector3(0, .1, 0))
	for i in 4:
		world.effects.tracer(camera.global_position + Vector3(.3, -.3, 1), plate.global_position + Vector3(-.4 + i * .25, .35 - (i % 2) * .25, .11))
	await seconds(.05);shot("sparks_metal_close")
	await seconds(1.0)

# Four emitter variants side by side: rotated basis with world-space particles (current),
# the same in local space, identity basis, and rotated basis without velocity alignment.
func spark_test() -> void:
	look(stage + Vector3(0, 1.6, 7), stage + Vector3(0, 1.4, 0))
	var effects := world.effects
	var spec: Dictionary = effects.specs.sparks
	var made: Array[CPUParticles3D] = []
	for i in 4:
		var particles: CPUParticles3D = effects.make_particles(spec, 5 + i)
		particles.one_shot = true;particles.emitting = false;particles.amount = 24
		if i == 1:particles.local_coords = true
		if i == 3:particles.particle_flag_align_y = false
		world.add_child(particles);made.append(particles)
	var basis := Basis(Quaternion(Vector3.UP, Vector3(0, 0, 1)))
	for i in 4:
		made[i].global_transform = Transform3D(basis if i != 2 else Basis.IDENTITY, stage + Vector3(-3 + i * 2.0, 1.4, 0))
		made[i].restart()
	await seconds(.04);shot("spark_test_a")
	await seconds(.08);shot("spark_test_b")
	await seconds(.15);shot("spark_test_c")

func casing_sequence() -> void:
	look(stage + Vector3(1.6, 1.25, 7.2), stage + Vector3(-.2, .6, 4.5))
	var side := Vector3.RIGHT
	for burst in 5:
		world.effects.eject_casing(stage + Vector3(-.9 + burst * .12, 1.25, 4.9), side)
		await seconds(.07)
	await seconds(.04);shot("casings_arc_a")
	await seconds(.12);shot("casings_arc_b")
	await seconds(.25);shot("casings_bounce")
	await seconds(1.2);shot("casings_resting")
	look(stage + Vector3(-.2, .9, 6.0), stage + Vector3(-.4, .0, 4.8))
	await seconds(.2);shot("casings_resting_close")
	await seconds(3.2);shot("casings_faded")

func stage_group(shift: float, car_count: int, barrel_count: int) -> Dictionary:
	var made: Array[Node3D] = []
	for i in car_count:made.append(clone(car_source, stage + Vector3(-2 + i * 5.0, 0, shift), PI * .5))
	for i in barrel_count:
		var spot := stage + Vector3(-1.4 + i * 1.4, 0, shift + 1.5)
		made.append(clone(drum_source, spot, 0));clone(visual_source, spot, 0)
	world.arena.destructibles = Destructible.scan(world.arena)
	world.destructibles = world.arena.destructibles
	for prop in world.destructibles:prop.world = world
	var result := {"cars": [], "barrels": []}
	for prop in world.destructibles:
		if not made.has(prop.node):continue
		if prop.kind == Destructible.Kind.CAR:result.cars.append(prop)
		else:result.barrels.append(prop)
	return result

func flat(a: Node3D, b: Node3D) -> float:
	var offset := a.global_position - b.global_position
	return Vector2(offset.x, offset.z).length()

func clone(source: Node3D, at: Vector3, yaw: float) -> Node3D:
	var copy: Node3D = source.duplicate()
	copy.name = String(source.name).rstrip("0123456789") + str(9000 + copies);copies += 1
	source.get_parent().add_child(copy)
	var height := stage.y + (.62 if String(source.name).begins_with("Drum") else 0.0)
	copy.global_position = Vector3(at.x, height, at.z)
	if yaw != 0:copy.rotation.y = yaw
	return copy

func look(from: Vector3, target: Vector3) -> void:
	camera.global_position = from;camera.look_at(target)

# Game seconds: the probe runs in slow motion so stills land on exact moments.
func seconds(amount: float) -> void:
	var until := Time.get_ticks_usec() + int(amount / Engine.time_scale * 1000000)
	await process_frame
	while Time.get_ticks_usec() < until:await process_frame

func shot(name: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(out_dir + "/" + prefix + name + ".png"))
	print("SHOT ", name)
