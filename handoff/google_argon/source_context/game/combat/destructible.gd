class_name Destructible
extends RefCounted

# Interactive props registered at run time by MapArena (barrels, cars, glass panes).
# A Destructible is plain data driven by MatchWorld: intact props cost nothing per
# frame, and only damaged ones sit in MatchWorld.active_destructibles. Explosions
# are queued (MatchWorld.queue_explosion) and resolved after resolve_damage, so
# chain reactions happen in a fixed order on the match clock.

enum Kind {BARREL, CAR, GLASS}
enum State {INTACT, LEAKING, SMOKING, BURNING, EXPLODING, WRECK, DONE}

const BARREL_HITS := 6.0
const BARREL_FUSE := Vector2(8, 12)
const BARREL_CHAIN := 4.0
const BARREL_RADIUS := 5.0
const BARREL_DAMAGE := 110.0
const CAR_HEALTH := 400.0
const CAR_FIRE_FUSE := 5.0
const CAR_WRECK_BURN := 20.0
const CAR_RADIUS := 7.0
const CAR_DAMAGE := 140.0
const CAR_BLAST_FACTOR := 1.5
const GLASS_PASS := .85
const HITBOX_LAYER := 4
const CAR_JOLT := .9
const FX := "res://content/effects/"
# Paint luminance of each scanned drum's albedo (the drum shader recolours it hazard red).
const DRUM_PAINT := {"Barrel_01": .2, "Barrel_02": .3, "barrel_03": .3}

static var wreck_material: StandardMaterial3D
static var tints: Dictionary = {}
static var drum_shader: Shader
static var drum_textures: Dictionary = {}

var kind: Kind
var state := State.INTACT
var node: Node3D
var body: StaticBody3D
var visuals: Array[MeshInstance3D] = []
var center := Vector3.ZERO
var world: MatchWorld
var health := 0.0
var hits := 0.0
var source := -1
var fuse_at := -1.0
var wreck_until := -1.0
var burner: Dictionary = {}
var rng := RandomNumberGenerator.new()
# Cars: bonnet end (+1 or -1 along the long axis), escalation flag, next spark pop and
# the visuals' rest transforms for the blast jolt.
var engine_end := 1.0
var escalated := false
var next_pop := 0.0
var jolt_at := -1.0
var rest_transforms: Array[Transform3D] = []

static func make(prop_kind: Kind, root: Node3D, collider: StaticBody3D, meshes: Array[MeshInstance3D], middle: Vector3) -> Destructible:
	var result := Destructible.new()
	result.kind = prop_kind;result.node = root;result.body = collider;result.visuals = meshes;result.center = middle
	result.health = CAR_HEALTH if prop_kind == Kind.CAR else 0.0
	result.rng.seed = hash(str(root.name)) ^ hash(middle)
	result.engine_end = 1.0 if result.rng.randf() < .5 else -1.0
	collider.set_meta("destructible", result)
	if prop_kind == Kind.GLASS:collider.set_meta("shoot_through", true)
	return result

# Finds the interactive props of a map by node name. MultiMesh clutter is never
# registered, so scattered barrels stay inert.
static func scan(arena: Node) -> Array[Destructible]:
	var found: Array[Destructible] = []
	tints.clear()
	var barrels := arena.find_children("Prop_*arrel*", "Node3D", true, false)
	for drum in arena.find_children("Drum*", "Node3D", true, false):
		var collider := first_body(drum)
		if collider == null:continue
		var meshes: Array[MeshInstance3D] = []
		var best: Node3D = null;var best_distance := .25
		for candidate in barrels:
			var offset: Vector3 = candidate.global_position - drum.global_position
			if Vector2(offset.x, offset.z).length() < best_distance:best = candidate;best_distance = Vector2(offset.x, offset.z).length()
		if best != null:
			for mesh in best.find_children("*", "MeshInstance3D", true, false):meshes.append(mesh);tint(mesh)
		found.append(make(Kind.BARREL, drum, collider, meshes, drum.global_position))
	var cars := arena.find_children("Prop_covered_car*", "Node3D", true, false)
	cars.append_array(arena.find_children("Prop_car_*", "Node3D", true, false))
	for car in cars:
		var collider := first_body(car)
		if collider == null:continue
		var meshes: Array[MeshInstance3D] = []
		for mesh in car.find_children("*", "MeshInstance3D", true, false):meshes.append(mesh)
		var shape: Node3D = collider.get_child(0) if collider.get_child_count() > 0 else collider
		found.append(make(Kind.CAR, car, collider, meshes, shape.global_position))
	for pane in arena.find_children("WindowGlass*", "Node3D", true, false):
		var meshes: Array[MeshInstance3D] = []
		for mesh in pane.find_children("*", "MeshInstance3D", true, false):meshes.append(mesh)
		if meshes.is_empty():continue
		var collider := first_body(pane)
		if collider == null:collider = shootable_body(pane, meshes[0])
		found.append(make(Kind.GLASS, pane, collider, meshes, pane.global_position))
	return found

# Decorative panes (distant context buildings) have no collider. Give them one on
# the hitbox layer only: bullets see it, bot sight and movement (layer 1) do not.
static func shootable_body(pane: Node3D, mesh: MeshInstance3D) -> StaticBody3D:
	var box := mesh.mesh.get_aabb()
	var body := StaticBody3D.new();body.collision_layer = HITBOX_LAYER;body.collision_mask = 0;body.set_meta("surface", "concrete")
	var shape := CollisionShape3D.new();var volume := BoxShape3D.new()
	volume.size = box.size * mesh.scale;shape.shape = volume;shape.position = mesh.position + mesh.basis * (box.get_center() * mesh.scale)
	body.add_child(shape);pane.add_child(body)
	return body

static func first_body(root: Node) -> StaticBody3D:
	for child in root.get_children():
		if child is StaticBody3D:return child
	return null

# Explosive barrels read as hazards: the scanned drum gets the weathered hazard-red
# steel shader (fx_drum: recoloured scan paint, rusty rims, scratches and a FLAMMABLE
# plate plus class-3 diamond).
static func tint(mesh: MeshInstance3D) -> void:
	if mesh.mesh == null or DisplayServer.get_name() == "headless":return
	for surface in mesh.mesh.get_surface_count():
		var source_material := mesh.get_active_material(surface) as BaseMaterial3D
		if source_material == null:continue
		var key := str(source_material.get_instance_id()) + str(mesh.mesh.get_instance_id())
		if not tints.has(key):tints[key] = drum_material(source_material, mesh.mesh)
		mesh.set_surface_override_material(surface, tints[key])
	var seed_value := hash(str(mesh.get_path()))
	mesh.set_instance_shader_parameter("wear", float(seed_value % 1000) / 1000.0 * .55 + .45)
	mesh.set_instance_shader_parameter("label_angle", float((seed_value / 1000) % 1000) / 1000.0 * TAU - PI)

static func drum_material(source: BaseMaterial3D, mesh: Mesh) -> ShaderMaterial:
	if drum_shader == null:
		drum_shader = load(FX + "fx_drum.gdshader") as Shader
		drum_textures = {"label": load(FX + "label_flammable.png"), "diamond": load(FX + "hazard_diamond.png"), "dents": dent_normals()}
	var material := ShaderMaterial.new();material.shader = drum_shader
	var path := source.albedo_texture.resource_path if source.albedo_texture != null else ""
	var paint := .25
	for name in DRUM_PAINT:
		if name.to_lower() in path.to_lower():paint = DRUM_PAINT[name]
	material.set_shader_parameter("albedo_map", source.albedo_texture)
	material.set_shader_parameter("arm_map", source.metallic_texture if source.metallic_texture != null else source.roughness_texture)
	material.set_shader_parameter("normal_map", source.normal_texture)
	material.set_shader_parameter("dent_map", drum_textures.dents)
	material.set_shader_parameter("label_map", drum_textures.label)
	material.set_shader_parameter("diamond_map", drum_textures.diamond)
	material.set_shader_parameter("paint_luminance", paint)
	var box := mesh.get_aabb()
	material.set_shader_parameter("body_box", Vector4(box.position.y, box.end.y, maxf(box.size.x, box.size.z) * .5, 0))
	return material

static func dent_normals() -> Texture2D:
	var noise := FastNoiseLite.new();noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;noise.seed = 31;noise.frequency = .035
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM;noise.fractal_octaves = 3
	var image := noise.get_seamless_image(128, 128, false)
	image.bump_map_to_normal_map(5.0)
	return ImageTexture.create_from_image(image)

# Burnt-out car: black, sooty steel and rubber with mottled rust.
static func charred() -> StandardMaterial3D:
	if wreck_material == null:
		wreck_material = StandardMaterial3D.new()
		var noise := FastNoiseLite.new();noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;noise.seed = 73;noise.frequency = .05
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM;noise.fractal_octaves = 4
		var image := noise.get_seamless_image(128, 128, false)
		var shade := Image.create(128, 128, false, Image.FORMAT_RGB8)
		for y in 128:
			for x in 128:
				var n := image.get_pixel(x, y).r
				var rust := smoothstep(.62, .8, n)
				shade.set_pixel(x, y, Color(.045, .042, .04).lerp(Color(.12, .075, .05), rust * .5) * (.7 + n * .6))
		wreck_material.albedo_texture = ImageTexture.create_from_image(shade);wreck_material.uv1_scale = Vector3(3, 3, 3)
		wreck_material.roughness = .92;wreck_material.metallic = .15
	return wreck_material

# --- damage ----------------------------------------------------------------------

# A bullet. `crossed` is where it hit; weight lets heavy rounds count for more.
func hit(amount: float, from_slot: int, point := Vector3.ZERO, normal := Vector3.UP) -> void:
	if world == null or state == State.DONE or state == State.EXPLODING:return
	if from_slot >= 0:source = from_slot
	match kind:
		Kind.GLASS:shatter(point, normal)
		Kind.BARREL:
			hits += clampf(amount / 30.0, .5, 3.0)
			if hits >= BARREL_HITS:explode(0.0)
			elif state == State.INTACT:puncture()
		Kind.CAR:damage_car(amount)

# An explosion reaching this prop `distance` metres from its centre.
func blast_hit(distance: float, amount: float, from_slot: int) -> void:
	if world == null or state == State.DONE or state == State.EXPLODING:return
	if from_slot >= 0:source = from_slot
	match kind:
		Kind.GLASS:shatter(center, Vector3.UP)
		Kind.BARREL:
			if distance <= BARREL_CHAIN:explode(.1 + .04 * distance)
			elif state == State.INTACT:puncture()
		Kind.CAR:damage_car(amount * CAR_BLAST_FACTOR)

func shatter(point: Vector3, normal: Vector3) -> void:
	state = State.DONE
	body.collision_layer = 0
	for mesh in visuals:mesh.visible = false
	if point == Vector3.ZERO:point = center
	if world.effects != null:world.effects.glass_burst(point, normal)

func puncture() -> void:
	state = State.LEAKING
	fuse_at = world.clock + rng.randf_range(BARREL_FUSE.x, BARREL_FUSE.y)
	burner = world.effects.burning(center + Vector3.UP * .15, fuse_at, .3)
	world.activate(self)

# Under the bonnet: the car's long axis (from its collider box), one end chosen at random.
func engine_point() -> Vector3:
	var shape := body.get_child(0) as CollisionShape3D if body.get_child_count() > 0 else null
	var box := shape.shape as BoxShape3D if shape != null else null
	if box == null:return center + Vector3.UP * .4
	var along := Vector3.RIGHT if box.size.x > box.size.z else Vector3.BACK
	return center + shape.global_basis * along * engine_end * maxf(box.size.x, box.size.z) * .3 + Vector3.UP * (box.size.y * .05)

func damage_car(amount: float) -> void:
	if state == State.WRECK:return
	health -= amount
	if health <= 0:explode(.2);return
	if health <= CAR_HEALTH * .25 and state != State.BURNING:
		# Fire under the bonnet: flames and black smoke from the engine bay.
		state = State.BURNING;fuse_at = world.clock + CAR_FIRE_FUSE;escalated = false;next_pop = world.clock + 1.0
		world.effects.burn_stop(burner);burner = world.effects.burning(engine_point(), fuse_at, .9, true, true)
		world.activate(self)
	elif health <= CAR_HEALTH * .5 and state == State.INTACT:
		# Damage smoke: a dark plume from the engine bay.
		state = State.SMOKING
		burner = world.effects.burning(engine_point(), 1e9, .7, false, true)
		world.activate(self)

func explode(delay: float) -> void:
	if state == State.EXPLODING or state == State.DONE or state == State.WRECK:return
	state = State.EXPLODING
	world.queue_explosion(self, world.clock + delay)
	world.activate(self)

# Called by MatchWorld.resolve_explosions when the queued time arrives.
func detonate() -> void:
	world.effects.burn_stop(burner);burner = {}
	if kind == Kind.BARREL:
		state = State.DONE;body.collision_layer = 0
		for mesh in visuals:mesh.visible = false
		world.effects.explosion(center, 1.0, .8)
		world.deactivate(self)
		world.blast(center, BARREL_RADIUS, BARREL_DAMAGE, source, &"barrel", self)
	else:
		state = State.WRECK;wreck_until = world.clock + CAR_WRECK_BURN
		for mesh in visuals:mesh.material_override = charred()
		# The body jolts up and settles; doors and bonnet fly off.
		rest_transforms.clear()
		for mesh in visuals:rest_transforms.append(mesh.transform)
		jolt_at = world.clock
		world.effects.explosion(center + Vector3.UP * .4, 1.5, 1.0, 3)
		burner = world.effects.burning(center + Vector3.UP * .55, wreck_until, 1.3, true, true)
		world.blast(center + Vector3.UP * .4, CAR_RADIUS, CAR_DAMAGE, source, &"car", self)

# Advances timers; called only for props in MatchWorld.active_destructibles.
func tick(now: float) -> void:
	match state:
		State.LEAKING:
			if now >= fuse_at:explode(0.0)
		State.BURNING:
			if now >= fuse_at:explode(0.0)
			else:burn_up(now)
		State.WRECK:
			if jolt_at >= 0:jolt(now - jolt_at)
			if now >= wreck_until:
				world.effects.burn_stop(burner);burner = {};world.deactivate(self)

# The last seconds before a car goes: a bigger fire and popping sparks.
func burn_up(now: float) -> void:
	if not escalated and fuse_at - now < 1.4:
		escalated = true
		world.effects.burn_resize(burner, 1.7)
	if now >= next_pop and fuse_at - now < 3.5:
		next_pop = now + rng.randf_range(.25, .6)
		var spot := engine_point() + Vector3(rng.randf_range(-.4, .4), .2, rng.randf_range(-.4, .4))
		world.effects.emit("sparks", spot, Basis.IDENTITY);world.effects.emit("spark_glow", spot, Basis.IDENTITY)

# The blast lifts the body about a quarter metre, rocks it and lets it settle; only the
# visuals move, so the collider stays where the map put it.
func jolt(age: float) -> void:
	var done := age >= CAR_JOLT
	var lift := 0.0 if done else .62 * exp(-4.0 * age) * absf(sin(age * 7.0))
	var roll := 0.0 if done else .1 * exp(-3.2 * age) * sin(age * 9.0)
	var pitch := 0.0 if done else .06 * exp(-3.2 * age) * sin(age * 7.5 + 1.0)
	var offset := Transform3D(Basis.from_euler(Vector3(pitch, 0, roll)), Vector3(0, lift, 0))
	for i in mini(visuals.size(), rest_transforms.size()):
		visuals[i].transform = rest_transforms[i] if done else offset * rest_transforms[i]
	if done:jolt_at = -1.0
