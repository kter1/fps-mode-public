class_name SoldierFactory
extends RefCounted

# Third-person soldier presentation: the Mixamo-derived soldier (team materials,
# AnimationTree and the final pose modifier) and the ragdoll left behind on death.
# Gameplay hurtboxes and collision live on Combatant and are never touched here.
# tools/blender/ingest_soldier.py builds the model; its clip table (ground speeds)
# and texture paths come from the "soldier" entry of the characters manifest.

const MODEL := "res://content/models/characters/soldier.glb"
const MANIFEST := "res://content/manifest/characters.json"
const TEAMS := ["blue", "red"]
const DIRECTIONS := ["f", "b", "l", "r", "fl", "fr", "bl", "br"]
const MAX_RAGDOLLS := 6
const RAGDOLL_SETTLE := 2.8
# Ragdolls sit on their own physics layer (7) and only collide with the world, so a
# corpse never blocks a bullet, a grenade or a living soldier.
const RAGDOLL_LAYER := 64
const STANCE := preload("res://game/presentation/stance_modifier.gd")

static var data: Dictionary = {}
static var finishes: Dictionary = {}
static var graph: AnimationNodeBlendTree
static var effects: AnimationLibrary
static var rings: Dictionary = {}
static var ragdolls: Array = []

static func info() -> Dictionary:
	if data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		data = parsed.get("soldier", {}) if parsed is Dictionary else {}
	return data

static func soldier(team: int) -> Node3D:
	var root := Node3D.new()
	var model := ModelFactory.scene(MODEL)
	model.name = "Model"
	root.add_child(model)
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		for surface in instance.mesh.get_surface_count():
			instance.set_surface_override_material(surface, finish(team, instance.mesh.surface_get_material(surface).resource_name))
	return root

# One shared material per team and part: albedo recoloured per team in the ingest,
# shared normal and ORM (roughness in G, metallic in B) maps.
static func finish(team: int, part: String) -> StandardMaterial3D:
	var key: String = part + "_" + TEAMS[team]
	if not finishes.has(key):
		var maps: Dictionary = info().textures[part]
		var material := StandardMaterial3D.new()
		material.resource_name = key
		material.albedo_texture = load(maps["albedo_" + TEAMS[team]])
		material.normal_enabled = true
		material.normal_texture = load(maps.normal)
		material.roughness_texture = load(maps.orm)
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.metallic_texture = load(maps.orm)
		material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		material.metallic = 1.0
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		finishes[key] = material
	return finishes[key]

static func skeleton_of(visual: Node) -> Skeleton3D:
	var found := visual.find_children("*", "Skeleton3D", true, false)
	return found[0] if not found.is_empty() else null

# Replaces the model's AnimationPlayer with an AnimationTree that shares its clips
# and the locomotion graph, and adds the pose modifier for the given actor.
static func animate(visual: Node3D, actor: Object) -> AnimationTree:
	var model := visual.get_node("Model")
	var player := ModelFactory.animation_player(model)
	var skeleton := skeleton_of(model)
	var library := player.get_animation_library("")
	prepare(library, skeleton, model.get_path_to(skeleton))
	model.remove_child(player)
	player.free()
	var tree := AnimationTree.new()
	tree.name = "Animator"
	tree.add_animation_library("", library)
	tree.add_animation_library("fx", effects)
	tree.tree_root = graph
	# Combatant.update_animation advances both by hand (animation LOD).
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	model.add_child(tree)
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var stance := STANCE.new()
	stance.name = "Stance"
	stance.actor = actor
	skeleton.add_child(stance)
	return tree

# Builds the shared graph once:
#   stand (BlendSpace2D: idle, 8 walk, 8 run, 3 sprint) and crouch (crouch idle,
#   8 crouch walk), each point placed at the clip's measured ground velocity
#   -> posture (Blend2 by crouch) -> pace (TimeScale past the outer ring)
#   -> air (Blend2 to the airborne loop) -> recoil (additive OneShot per shot).
static func prepare(library: AnimationLibrary, skeleton: Skeleton3D, skeleton_path: NodePath) -> void:
	if graph != null:
		return
	var clips: Dictionary = info().get("clips", {})
	for clip in clips:
		if library.has_animation(clip) and clips[clip].loop:
			library.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var stand := space([["idle", Vector2.ZERO]] + ring(clips, "walk_") + ring(clips, "run_") + [["sprint_f", velocity(clips, "sprint_f")], ["sprint_fl", velocity(clips, "sprint_fl")], ["sprint_fr", velocity(clips, "sprint_fr")]], 7.6)
	var crouch := space([["crouch_idle", Vector2.ZERO]] + ring(clips, "crouch_"), 2.6)
	rings = {"run": velocity(clips, "run_f").length(), "sprint": velocity(clips, "sprint_f").length(), "crouch": velocity(clips, "crouch_f").length()}
	graph = AnimationNodeBlendTree.new()
	graph.add_node("stand", stand)
	graph.add_node("crouch", crouch)
	graph.add_node("posture", AnimationNodeBlend2.new())
	graph.add_node("pace", AnimationNodeTimeScale.new())
	var airborne := AnimationNodeAnimation.new()
	airborne.animation = &"airborne"
	graph.add_node("airborne", airborne)
	graph.add_node("air", AnimationNodeBlend2.new())
	var kick := AnimationNodeAnimation.new()
	kick.animation = &"fx/recoil"
	graph.add_node("kick", kick)
	var recoil := AnimationNodeOneShot.new()
	recoil.mix_mode = AnimationNodeOneShot.MIX_MODE_ADD
	recoil.fadein_time = .02
	recoil.fadeout_time = .06
	graph.add_node("recoil", recoil)
	graph.connect_node("posture", 0, "stand")
	graph.connect_node("posture", 1, "crouch")
	graph.connect_node("pace", 0, "posture")
	graph.connect_node("air", 0, "pace")
	graph.connect_node("air", 1, "airborne")
	graph.connect_node("recoil", 0, "air")
	graph.connect_node("recoil", 1, "kick")
	graph.connect_node("output", 0, "recoil")
	effects = AnimationLibrary.new()
	effects.add_animation(&"recoil", recoil_clip(skeleton, skeleton_path))

static func ring(clips: Dictionary, prefix: String) -> Array:
	var points := []
	for direction in DIRECTIONS:
		if clips.has(prefix + direction):
			points.append([prefix + direction, velocity(clips, prefix + direction)])
	return points

static func velocity(clips: Dictionary, clip: String) -> Vector2:
	var value: Array = clips.get(clip, {}).get("velocity", [0, 0])
	return Vector2(value[0], value[1])

static func space(points: Array, extent: float) -> AnimationNodeBlendSpace2D:
	var result := AnimationNodeBlendSpace2D.new()
	result.min_space = Vector2(-extent, -extent)
	result.max_space = Vector2(extent, extent)
	result.snap = Vector2(.01, .01)
	# Phase-match cycles of different lengths (walk 1.0 s, run 0.5 s) so feet stay in step.
	result.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE
	for point in points:
		var clip := AnimationNodeAnimation.new()
		clip.animation = StringName(point[0])
		result.add_blend_point(clip, point[1], -1, StringName(point[0]))
	return result

# Additive recoil: keys are rest * kick, which the mixer adds on top of any pose.
# The chest rocks back and the right shoulder lifts, then settles within 0.18 s.
static func recoil_clip(skeleton: Skeleton3D, skeleton_path: NodePath) -> Animation:
	var clip := Animation.new()
	clip.length = .18
	for entry in [["Spine1", Vector3.RIGHT, 1.6], ["Spine2", Vector3.RIGHT, 2.4], ["RightShoulder", Vector3.BACK, 3.0], ["Neck", Vector3.RIGHT, -1.8]]:
		var bone := skeleton.find_bone(entry[0])
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		var axis: Vector3 = (skeleton.get_bone_global_rest(bone).basis.inverse() * entry[1]).normalized()
		var track := clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(track, NodePath(str(skeleton_path) + ":" + str(entry[0])))
		clip.rotation_track_insert_key(track, 0.0, rest)
		clip.rotation_track_insert_key(track, .035, rest * Quaternion(axis, deg_to_rad(entry[2])))
		clip.rotation_track_insert_key(track, .18, rest)
	return clip

# Leaves a ragdoll where the victim fell. hit_direction points from the killer
# toward the victim (zero for environmental deaths). The ragdoll starts from the
# pose the victim was last drawn in (modifier result included) with part of his
# momentum, takes the hit as a modest shove, and a RagdollDriver freezes it in place
# once it lies still (RAGDOLL_SETTLE at the latest); at most MAX_RAGDOLLS simulate at
# once (the oldest freezes first). MatchWorld still frees the corpse later.
static func corpse(parent: Node3D, victim: Combatant, hit_direction: Vector3) -> Node3D:
	var body := soldier(victim.slot.team)
	parent.add_child(body)
	body.global_transform = victim.global_transform
	var model := body.get_node("Model")
	var player := ModelFactory.animation_player(model)
	if player != null:
		model.remove_child(player)
		player.free()
	var skeleton := skeleton_of(model)
	if victim.skeleton != null:
		var last := final_pose(victim)
		for bone in last.size():
			skeleton.set_bone_pose(bone, last[bone])
	skeleton.force_update_all_bone_transforms()
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "Ragdoll"
	skeleton.add_child(simulator)
	var frame := character_frame(skeleton)
	for spec in RAGDOLL:
		var physical := ragdoll_bone(skeleton, spec, frame)
		if physical != null:
			simulator.add_child(physical)
	simulator.physical_bones_start_simulation()
	collapse(body, simulator, skeleton, victim, hit_direction, frame)
	var driver := RagdollDriver.new()
	driver.name = "Driver"
	body.add_child(driver)
	driver.start(simulator)
	var reference: WeakRef = weakref(body)
	ragdolls = ragdolls.filter(func(entry: WeakRef) -> bool: return entry.get_ref() != null)
	while ragdolls.size() >= MAX_RAGDOLLS:
		freeze(ragdolls[0])
	ragdolls.append(reference)
	return body

# The pose the victim was drawn in at the end of its last update: the pose modifier's
# result (aimed spine, hands on the weapon, crouch) is thrown away after every update,
# so the modifier is run once more and read in skeleton_updated.
static func final_pose(victim: Combatant) -> Array[Transform3D]:
	var skeleton := victim.skeleton
	var captured: Array[Transform3D] = []
	var grab := func() -> void:
		captured.clear()
		for bone in skeleton.get_bone_count():
			captured.append(skeleton.get_bone_pose(bone))
	at_final_pose(skeleton, victim.visual, grab)
	if captured.is_empty():
		grab.call()
	return captured

# Runs the pose modifier now, synchronously, and calls `action` while the pose it
# produced is current (skeleton_updated normally fires a frame later, and only for a
# skeleton whose pose changed, hence the nudge).
static func at_final_pose(skeleton: Skeleton3D, visual: Node3D, action: Callable) -> void:
	var was := visual.visible
	visual.visible = true
	skeleton.skeleton_updated.connect(action, CONNECT_ONE_SHOT)
	var original := skeleton.get_bone_pose_position(0)
	skeleton.set_bone_pose_position(0, original + Vector3(0, .0001, 0))
	skeleton.advance(.001)
	skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	skeleton.set_bone_pose_position(0, original)
	visual.visible = was

# Capsules [from, to, radius] approximating the drawn body (head, torso, thighs and
# shins), in skeleton space and read from the current pose. Used to check that a
# carried weapon stays outside the body.
static func body_shapes(skeleton: Skeleton3D) -> Array:
	var at := func(name: String) -> Vector3:
		return skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin
	var neck: Vector3 = at.call("Neck")
	var head: Vector3 = at.call("Head")
	var crown := head + (head - neck).normalized() * .12
	var shapes := [[at.call("Hips"), neck, .15], [head, crown, .12]]
	for side in ["Left", "Right"]:
		shapes.append([at.call(side + "UpLeg"), at.call(side + "Leg"), .09])
		shapes.append([at.call(side + "Leg"), at.call(side + "Foot"), .07])
	return shapes

# Distance from a skeleton-space point to the nearest body shape's surface (negative inside).
static func clearance(point: Vector3, shapes: Array) -> float:
	var best := INF
	for shape in shapes:
		var nearest := Geometry3D.get_closest_point_to_segment(point, shape[0], shape[1])
		best = minf(best, point.distance_to(nearest) - shape[2])
	return best

# How far the carried weapon's muzzle and forward barrel (a line back from the muzzle to
# the receiver) stay outside the body; read while the pose is final (skeleton_updated).
static func gun_clearance(actor: Combatant) -> Dictionary:
	var gun := actor.gun
	if gun == null or actor.skeleton == null or not gun.has_meta("muzzle"):
		return {"muzzle": INF, "barrel": INF}
	var shapes := body_shapes(actor.skeleton)
	var to_skeleton := actor.skeleton.global_transform.affine_inverse() * gun.global_transform
	var muzzle: Vector3 = gun.get_meta("muzzle")
	var worst := INF
	for step in 9:
		var along := muzzle.lerp(Vector3(muzzle.x, muzzle.y, muzzle.z * .15), step / 8.0)
		worst = minf(worst, clearance(to_skeleton * along, shapes))
	return {"muzzle": clearance(to_skeleton * muzzle, shapes), "barrel": worst}

# The soldier's own axes in skeleton space, from the pelvis: right (left hip to right
# hip), up (hips to chest) and forward.
static func character_frame(skeleton: Skeleton3D) -> Basis:
	var right := (skeleton.get_bone_global_pose(skeleton.find_bone("RightUpLeg")).origin - skeleton.get_bone_global_pose(skeleton.find_bone("LeftUpLeg")).origin).normalized()
	var up := (skeleton.get_bone_global_pose(skeleton.find_bone("Spine2")).origin - skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin).normalized()
	up = up.slide(right).normalized()
	return Basis(right, up, right.cross(up))

# Starting velocities. The upper body carries COLLAPSE_CARRY of the victim's momentum
# (capped), the feet stay nearer the ground; the knees get a flexing spin and the hips
# a hint of sit-back so the legs go first; the hit is a shove on the chest, shoulders
# and head, small enough that nobody flies.
static func collapse(body: Node3D, simulator: PhysicalBoneSimulator3D, skeleton: Skeleton3D, victim: Combatant, hit_direction: Vector3, frame: Basis) -> void:
	var momentum := Vector3(victim.velocity.x, 0, victim.velocity.z) * COLLAPSE_CARRY
	momentum = momentum.limit_length(CARRY_LIMIT)
	var carried := momentum + Vector3.UP * clampf(victim.velocity.y, -6.0, 1.0)
	var push := hit_direction.normalized() if hit_direction.length_squared() > .001 else Vector3.ZERO
	push.y = 0
	var world := skeleton.global_transform.basis
	var flex := world * frame.x
	for physical in simulator.get_children():
		if not physical is PhysicalBone3D:
			continue
		var name: String = physical.bone_name
		var grounded: float = {"LeftLeg": .45, "RightLeg": .45, "LeftFoot": .3, "RightFoot": .3}.get(name, 1.0)
		physical.linear_velocity = Vector3(carried.x * grounded, carried.y, carried.z * grounded)
		if push != Vector3.ZERO:
			physical.linear_velocity += push * HIT_SPEED * {"Spine2": 1.0, "Spine1": .8, "Spine": .5, "Head": .7, "LeftArm": .6, "RightArm": .6, "Hips": .3}.get(name, .0)
		if name.ends_with("Leg") and not name.ends_with("UpLeg"):
			physical.angular_velocity = -flex * KNEE_BUCKLE
		elif name.ends_with("UpLeg"):
			physical.angular_velocity = flex * HIP_SIT
	var hips := simulator.get_node_or_null("Hips") as PhysicalBone3D
	if hips != null:
		hips.linear_velocity += Vector3.DOWN * SAG_SPEED

# A dropped rifle: the weapon the soldier carried falls from where it was held and
# lies beside the body (its own rigid body, world-only collisions, frozen with the
# ragdoll). Without it the gun simply vanished at the moment of death.
# The weapon a soldier lets go of (on death, or swapped away): a physics body under
# `parent` that falls from where `held_by` carried its gun. MatchWorld keeps it as a pickup.
static func drop_gun(parent: Node3D, held_by: Combatant, runtime: WeaponRuntime = null) -> RigidBody3D:
	var held := held_by.gun
	if runtime == null:
		runtime = held_by.weapon()
	if held == null or not held.is_inside_tree() or DisplayServer.get_name() == "headless":
		return null
	var model := ModelFactory.weapon(runtime.definition, runtime.attachments)
	var box := ModelFactory.bounds(model)
	if box.size.length() < .1:
		model.free()
		return null
	var rigid := RigidBody3D.new()
	rigid.name = "DroppedGun"
	rigid.collision_layer = RAGDOLL_LAYER
	rigid.collision_mask = 1
	rigid.mass = 3.5
	rigid.gravity_scale = .5
	rigid.linear_damp = .4
	rigid.angular_damp = 3.0
	rigid.physics_material_override = PhysicsMaterial.new()
	rigid.physics_material_override.friction = 1.0
	rigid.physics_material_override.bounce = 0.0
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = box.size * .85
	shape.shape = hull
	shape.position = box.get_center()
	rigid.add_child(shape)
	rigid.add_child(model)
	parent.add_child(rigid)
	rigid.global_transform = held.global_transform
	rigid.linear_velocity = Vector3(held_by.velocity.x, 0, held_by.velocity.z).limit_length(CARRY_LIMIT) * COLLAPSE_CARRY
	return rigid

const COLLAPSE_CARRY := .6
const CARRY_LIMIT := 3.2
const HIT_SPEED := 1.3
const KNEE_BUCKLE := 1.3
const HIP_SIT := .8
const SAG_SPEED := .5
# Hinge joints end this many degrees past a straight limb.
const HYPEREXTEND := 3.0
# Godot's hinge angle runs against the flexion of a bone pair, a hip's X angle with it.
const HINGE_SIGN := -1.0
const HIP_SIGN := 1.0

# [bone, child bone (shape axis), radius, mass kg, joint, limits, resting angular damping].
# Masses follow body-segment fractions of an 85 kg soldier in kit (the chest carries
# the vest and magazines). Limits are degrees: spine, neck, shoulder and ankle are
# [bend, twist] cones about the starting pose; hips are [flexion, extension, spread,
# twist]; knees and elbows hinge one way, [maximum flexion].
const RAGDOLL := [
	["Hips", "Spine", .15, 11.0, "root", [], 3.0],
	["Spine", "Spine1", .13, 8.0, "spine", [6, 5], 7.0],
	["Spine1", "Spine2", .14, 9.0, "spine", [6, 5], 7.0],
	["Spine2", "Neck", .16, 18.0, "spine", [8, 6], 7.0],
	["Head", "", .11, 5.5, "neck", [28, 30], 6.0],
	["LeftArm", "LeftForeArm", .055, 2.8, "shoulder", [80, 35], 4.0],
	["LeftForeArm", "LeftHandMiddle1", .045, 2.2, "elbow", [145], 4.0],
	["RightArm", "RightForeArm", .055, 2.8, "shoulder", [80, 35], 4.0],
	["RightForeArm", "RightHandMiddle1", .045, 2.2, "elbow", [145], 4.0],
	["LeftUpLeg", "LeftLeg", .085, 8.5, "hip", [115, 20, 35, 25], 2.5],
	["LeftLeg", "LeftFoot", .06, 4.0, "knee", [128], 2.0],
	["LeftFoot", "LeftToeBase", .05, 1.5, "ankle", [28, 14], 3.5],
	["RightUpLeg", "RightLeg", .085, 8.5, "hip", [115, 20, 35, 25], 2.5],
	["RightLeg", "RightFoot", .06, 4.0, "knee", [128], 2.0],
	["RightFoot", "RightToeBase", .05, 1.5, "ankle", [28, 14], 3.5],
]

# A capsule along the bone (towards its child), centred on the segment, with the
# joint at the bone's own origin. Hinges turn about the limb's flexion axis.
static func ragdoll_bone(skeleton: Skeleton3D, spec: Array, frame: Basis) -> PhysicalBone3D:
	var bone := skeleton.find_bone(spec[0])
	if bone < 0:
		return null
	var pose := skeleton.get_bone_global_pose(bone)
	var child := skeleton.find_bone(spec[1]) if spec[1] != "" else -1
	var reach: Vector3 = (skeleton.get_bone_global_pose(child).origin - pose.origin) if child >= 0 else pose.basis.y.normalized() * .24
	var local := pose.basis.inverse() * reach
	var length := local.length()
	var along := Basis(Quaternion(Vector3.UP, local / length))
	var physical := PhysicalBone3D.new()
	physical.name = str(spec[0])
	physical.bone_name = spec[0]
	physical.mass = spec[3]
	physical.friction = 1.0
	physical.bounce = 0.0
	physical.gravity_scale = .5
	physical.linear_damp = .35
	physical.angular_damp = spec[6]
	physical.can_sleep = true
	physical.collision_layer = RAGDOLL_LAYER
	physical.collision_mask = 1
	physical.body_offset = Transform3D(along, local * .5)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = spec[2]
	capsule.height = maxf(length + spec[2] * (1.0 if spec[0] in ["Hips", "Spine2", "Head"] else .4), spec[2] * 2.01)
	if spec[0] == "Hips":
		capsule.height = .34
	shape.shape = capsule
	if spec[0] == "Hips":
		shape.rotation = Vector3(0, 0, PI * .5)
	physical.add_child(shape)
	var joint_origin := along.inverse() * (-local * .5)
	var limb := reach.normalized()
	var body_basis := pose.basis * along
	match spec[4]:
		"root":
			physical.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		"spine", "neck", "shoulder", "ankle":
			# A 6DOF joint with angular limits per axis: Y runs along the bone (twist),
			# X and Z bend it. Narrow cone-twist limits diverged in sideways falls.
			physical.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			physical.joint_offset = Transform3D(Basis(), joint_origin)
			for axis in ["x", "y", "z"]:
				var limit: float = spec[5][1] if axis == "y" else spec[5][0]
				limit_axis(physical, axis, -limit, limit)
		"hip":
			# Anatomical axes: X turns the thigh forward and back, Z out and in, Y twists.
			physical.joint_type = PhysicalBone3D.JOINT_TYPE_6DOF
			var x_axis := body_basis.inverse() * frame.x
			var y_axis := Vector3.UP
			var side := x_axis.slide(y_axis).normalized()
			physical.joint_offset = Transform3D(Basis(side, y_axis, side.cross(y_axis)), joint_origin)
			var forward := limb.dot(-frame.z)
			var spread := limb.dot(frame.x)
			var start_flex := rad_to_deg(atan2(forward, -limb.dot(frame.y)))
			var start_spread := rad_to_deg(atan2(spread, -limb.dot(frame.y))) * (1.0 if spec[0].begins_with("Right") else -1.0)
			var flex: Array = angle_range(start_flex, -spec[5][1], spec[5][0], HIP_SIGN)
			limit_axis(physical, "x", flex[0], flex[1])
			var out: Array = angle_range(start_spread, -spec[5][2] * .45, spec[5][2], 1.0 if spec[0].begins_with("Right") else -1.0)
			limit_axis(physical, "z", out[0], out[1])
			limit_axis(physical, "y", -spec[5][3], spec[5][3])
		"knee", "elbow":
			physical.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
			var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
			var upper := (pose.origin - parent.origin).normalized()
			var bend := upper.cross(limb)
			var flexion := rad_to_deg(upper.angle_to(limb))
			var axis := bend.normalized() if bend.length() > .02 and flexion > 6.0 else (-frame.x if spec[4] == "knee" else frame.x)
			# Hinge joints turn about their Z axis.
			var hinge := (body_basis.inverse() * axis).normalized()
			var across := hinge.cross(Vector3.UP).normalized() if absf(hinge.dot(Vector3.UP)) < .95 else hinge.cross(Vector3.RIGHT).normalized()
			physical.joint_offset = Transform3D(Basis(across, hinge.cross(across), hinge), joint_origin)
			var range: Array = angle_range(flexion, -HYPEREXTEND, spec[5][0], HINGE_SIGN)
			physical.set("joint_constraints/angular_limit_enabled", true)
			physical.set("joint_constraints/angular_limit_lower", range[0])
			physical.set("joint_constraints/angular_limit_upper", range[1])
	return physical

# Joint-angle limits (degrees) for a joint that starts at `start` and may travel
# between `lowest` and `highest` in anatomical terms; `sign` maps anatomical angle
# to the engine's joint angle.
static func angle_range(start: float, lowest: float, highest: float, sign: float) -> Array:
	var low := lowest - start
	var high := highest - start
	return [low, high] if sign > 0 else [-high, -low]

static func limit_axis(physical: PhysicalBone3D, axis: String, lower: float, upper: float) -> void:
	physical.set("joint_constraints/" + axis + "/angular_limit_enabled", true)
	physical.set("joint_constraints/" + axis + "/angular_limit_lower", lower)
	physical.set("joint_constraints/" + axis + "/angular_limit_upper", upper)

# Stops a ragdoll's simulation, keeping the pose it reached.
static func freeze(reference: WeakRef) -> void:
	ragdolls.erase(reference)
	var body: Node3D = reference.get_ref()
	if body == null or not body.is_inside_tree():
		return
	var rifle := body.get_node_or_null("DroppedGun") as RigidBody3D
	if rifle != null:
		rifle.freeze = true
	var simulator: PhysicalBoneSimulator3D = body.find_child("Ragdoll", true, false)
	if simulator == null:
		return
	var skeleton := simulator.get_skeleton()
	var reached := {}
	var to_skeleton := skeleton.global_transform.affine_inverse()
	for physical in simulator.get_children():
		if physical is PhysicalBone3D and physical.get_bone_id() >= 0:
			reached[physical.get_bone_id()] = to_skeleton * physical.global_transform * physical.body_offset.affine_inverse()
	var globals := {}
	for root in skeleton.get_parentless_bones():
		settle(skeleton, root, Transform3D.IDENTITY, reached, globals)
	simulator.physical_bones_stop_simulation()
	simulator.queue_free()

static func settle(skeleton: Skeleton3D, bone: int, parent: Transform3D, reached: Dictionary, globals: Dictionary) -> void:
	var global: Transform3D = reached.get(bone, parent * skeleton.get_bone_pose(bone))
	if reached.has(bone):
		var local := parent.affine_inverse() * global
		skeleton.set_bone_pose_position(bone, local.origin)
		skeleton.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
	globals[bone] = global
	for child in skeleton.get_bone_children(bone):
		settle(skeleton, child, global, reached, globals)
