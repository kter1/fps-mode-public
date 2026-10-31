extends SkeletonModifier3D

# Final pose pass after the AnimationTree (SoldierFactory.animate): settles the
# clip's crouch toward the crouched hurtbox, turns the spine so the clip's rifle hold
# points along the real aim, places the world weapon where the animated grip hand
# holds it (so stock, cheek and shoulder come from the motion capture), then
# solves both arms so the palms close around the weapon's grip and support points.
# The Mixamo packs have no reload, grenade or melee clips, so those are procedural
# hand paths here, with weapon_offset() moving the weapon itself.

const SIDES := ["Left", "Right"]
const SPINE := [["Spine", .25], ["Spine1", .35], ["Spine2", .4]]
# Crouch posture on top of the Mixamo kneel and crouch-walk clips. Kneeling, the hips
# sit back toward the heel by swinging about the grounded knee (KNEEL_SIT degrees at
# most, never folding the thigh closer than KNEEL_FOLD degrees to the shin); in the
# crouch-walk the hips drop CROUCH_DROP metres with both feet planted. The pelvis
# tips forward PELVIS_TILT degrees, then (after the spine is aimed) the back hunches
# forward CROUCH_LEAN degrees over Spine, Spine1 and Spine2 while the neck and head
# take back HEAD_LEVEL of it, so the face stays on the sights.
const KNEEL_SIT := 22.0
const KNEEL_FOLD := 28.0
const CROUCH_DROP := .07
# Lowest the toes and ankles may go (metres above the floor) after the leg solve:
# blends between the kneel and the stride would otherwise sink a foot.
const TOE_FLOOR := .02
const ANKLE_FLOOR := .07
const PELVIS_TILT := 8.0
const CROUCH_LEAN := 22.0
const HEAD_LEVEL := .9
const HUNCH := [["Spine", .3], ["Spine1", .35], ["Spine2", .35]]
# Hands follow the held weapon's sockets with the same rules as the first-person rig
# (view_model.gd pose_hands): the firing hand wraps the grip axis (GRIP_RADIUS) with
# its palm on the rear right; the support hand cups a handguard or pump from below,
# wraps a vertical magwell or foregrip, takes an angled grip, or wraps over the
# firing hand on a pistol. The knuckle line rests KNUCKLE_LIFT off the surface.
# Weapons without sockets use DEFAULT_SOCKETS (a carbine), in weapon space.
const GRIP_RADIUS := .016
const KNUCKLE_LIFT := .017
# Undersides measured from weapon meshes, by weapon and support point (see underside()).
static var undersides: Dictionary = {}
const DEFAULT_SOCKETS := {"grip": Vector3(0, -.047, .178), "support": Vector3(0, .065, -.038), "magwell": Vector3(0, .051, .062)}
# The rifle span (grip palm to support palm) the clips are aligned with, for every weapon.
const SPAN := Vector3(0, .03, -.29)
# Finger curl in degrees for joints 1-3 (the clips leave the hands open).
const CURL := {
	"Right": {"Index": [20, 28, 16], "Middle": [62, 72, 40], "Ring": [64, 74, 40], "Pinky": [66, 74, 40], "Thumb": [18, 24, 18]},
	"Left": {"Index": [52, 62, 34], "Middle": [58, 66, 38], "Ring": [62, 68, 40], "Pinky": [66, 70, 40], "Thumb": [16, 22, 16]},
}
# Where a shouldered butt rests relative to the right shoulder joint: shoulder line, up, forward.
const POCKET := Vector3(.01, .06, .11)
const STOCK_REACH := .13
# Low ready while sprinting: muzzle-down angle, and how far the butt (or, for guns without
# a stock, the grip) rides below the shoulder pocket, in the chest frame.
const LOW_READY := 26.0
const LOW_POCKET := Vector3(0, -.05, .0)
const LOW_GRIP := Vector3(-.08, -.17, .17)
# Drawing a weapon or throwing lowers it, pivoting on the butt (weapon-mount space).
const LOWERED_SHIFT := Vector3(-.03, -.08, -.02)
const LOWERED_YAW := 10.0
const LOWERED_PITCH := -30.0
const POUCH := Vector3(-.12, .13, -.16)
# Overarm throw, right hand relative to the neck (skeleton space, -Z forward): pulled back
# above and behind the shoulder, whipped through the release point, followed down and across.
# Times follow ThrowTimeline (cocked at PULL, release at RELEASE).
const THROW := [[.1, Vector3(.2, -.12, -.12)], [.25, Vector3(.3, .2, .24)], [.3, Vector3(.3, .2, .24)], [.45, Vector3(.2, .3, -.62)], [.6, Vector3(.02, -.2, -.6)], [.72, Vector3(.06, -.3, -.3)]]
# Left hand while throwing: out in front, pointing at the target.
const POINT := Vector3(-.14, -.08, -.55)

var actor: Object
var bones: Dictionary = {}
var palms: Dictionary = {}
var knuckles: Dictionary = {}
var frames: Dictionary = {}
var toes: Dictionary = {}
var grips: Dictionary = {}

func _process_modification() -> void:
	if actor == null or not actor.visual.visible:
		return
	var started: int = Time.get_ticks_usec() if actor.measure_pose else 0
	apply_pose()
	if actor.measure_pose:
		actor.pose_cpu_usec += Time.get_ticks_usec() - started
		actor.pose_calls += 1

func cache(skeleton: Skeleton3D) -> void:
	for name in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head"]:
		bones[name] = skeleton.find_bone(name)
	for side in SIDES:
		for part in ["Arm", "ForeArm", "Hand", "HandMiddle1", "UpLeg", "Leg", "Foot"]:
			bones[side + part] = skeleton.find_bone(side + part)
		var ankle := skeleton.get_bone_global_rest(bones[side + "Foot"])
		toes[side] = ankle.affine_inverse() * skeleton.get_bone_global_rest(skeleton.find_bone(side + "ToeBase")).origin
		# Mixamo binds in a T-pose with the palms down: the palm centre is a little
		# past mid-hand towards the middle knuckle and 2.5 cm below the bones.
		var rest := skeleton.get_bone_global_rest(bones[side + "Hand"])
		var knuckle := skeleton.get_bone_global_rest(bones[side + "HandMiddle1"]).origin
		palms[side] = rest.affine_inverse() * (rest.origin.lerp(knuckle, .55) + Vector3.DOWN * .025)
		knuckles[side] = rest.affine_inverse() * knuckle
		var finger := (rest.basis.inverse() * (knuckle - rest.origin)).normalized()
		var normal := (rest.basis.inverse() * Vector3.DOWN).slide(finger).normalized()
		frames[side] = Basis(finger, normal, finger.cross(normal))
		grips[side] = []
		for digit in CURL[side]:
			for joint in 3:
				var bone := skeleton.find_bone(side + "Hand" + digit + str(joint + 1))
				var tip := skeleton.find_bone(side + "Hand" + digit + str(joint + 2))
				if bone < 0:
					continue
				var start := skeleton.get_bone_global_rest(bone)
				var along := (skeleton.get_bone_global_rest(tip).origin - start.origin) if tip >= 0 else (start.origin - skeleton.get_bone_global_rest(skeleton.get_bone_parent(bone)).origin)
				var axis := (start.basis.inverse() * along.cross(Vector3.DOWN)).normalized()
				grips[side].append([bone, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(axis, deg_to_rad(CURL[side][digit][joint]))])

func apply_pose() -> void:
	var skeleton := get_skeleton()
	if bones.is_empty():
		cache(skeleton)
	if bones.values().has(-1):
		return
	if actor.prone:
		# Lay the body along the ground; the existing aim and arm solve keeps the rifle usable.
		for bone in skeleton.get_bone_count():
			skeleton.set_bone_pose(bone, skeleton.get_bone_rest(bone))
		var hips := skeleton.get_bone_global_pose(bones.Hips)
		hips.basis=Basis(Vector3.RIGHT,-PI*.5)*hips.basis
		hips.origin=Vector3(0,.3,.35)
		skeleton.set_bone_global_pose(bones.Hips,hips)
	else:
		settle_crouch(skeleton, actor.anim_crouch)
	var holds := hand_holds(actor)
	var aim := Basis(Vector3.RIGHT, actor.pitch + actor.recoil)
	align_spine(skeleton, aim * SPAN.normalized(), actor.aim_weight)
	hunch(skeleton, 0.0 if actor.prone else actor.anim_crouch)
	# Aimed: the weapon points along the aim and its grip hand holds it where the clip does
	# (a long stock slid into the shoulder pocket). Sprinting: low ready, the butt in the
	# pocket (lowered a little) and the muzzle down LOW_READY degrees, so the gun rides
	# with the torso instead of dangling from a swinging hand.
	var low_ready: float = 1.0 - actor.aim_weight
	var basis := aim.slerp(Basis(Vector3.RIGHT, actor.pitch * .5 - deg_to_rad(LOW_READY)), low_ready)
	var origin: Vector3 = skeleton.get_bone_global_pose(bones.RightHand) * knuckles.Right - basis * holds.Right[0]
	origin += stock_shift(skeleton, basis, origin, holds.butt) * actor.aim_weight
	if low_ready > 0.0:
		var anchor: Vector3 = (holds.butt as Vector3) if (holds.butt as Vector3).is_finite() else holds.Right[0]
		var rest := pocket_of(skeleton, POCKET + LOW_POCKET) if (holds.butt as Vector3).is_finite() else pocket_of(skeleton, POCKET + LOW_GRIP)
		origin = origin.lerp(rest - basis * anchor, low_ready)
	if actor.weapon().definition.category == "sidearm":
		origin += basis * Vector3(0, .07, -.26) * actor.aim_weight
	var mount := Transform3D(basis, origin) * weapon_offset(actor, holds)
	actor.gun_mount.transform = actor.visual.global_transform.affine_inverse() * skeleton.global_transform * mount
	var grip: Vector3 = mount * holds.Right[0]
	var support: Vector3 = mount * holds.Left[0]
	var right := grip
	var left := support
	var now: float = actor.anim_clock
	var runtime: WeaponRuntime = actor.weapon()
	if runtime.state == "RELOADING" and actor.reload_started >= 0:
		left = reload_hand(skeleton, support, mount * holds.magazine, clampf((now - actor.reload_started) / maxf(actor.reload_length, .1), 0, 1), runtime.definition.shell_reload, now)
	var spent := ThrowTimeline.seconds(actor, now)
	if spent >= 0:
		right = throw_hand(skeleton, grip, spent)
		var point := skeleton.get_bone_global_pose(bones.Neck).origin + POINT
		left = left.lerp(point, smoothstep(0.0, .2, spent) * (1.0 - smoothstep(.6, .8, spent)))
	place_hand(skeleton, "Right", right, mount.basis * holds.Right[1], mount.basis * holds.Right[2], clampf(right.distance_to(grip) / .15, 0, 1))
	place_hand(skeleton, "Left", left, mount.basis * holds.Left[1], mount.basis * holds.Left[2], clampf(minf(left.distance_to(support), left.distance_to(mount * holds.magazine)) / .15, 0, 1))
	for side in SIDES:
		for joint in grips[side]:
			skeleton.set_bone_pose_rotation(joint[0], joint[1])

# Where each hand holds the current weapon, in weapon-mount space: per side
# [knuckle point, knuckle direction, palm normal], plus the magazine's bottom.
static func hand_holds(holder: Object) -> Dictionary:
	var gun: Node3D = holder.gun
	var grip: Vector3 = weapon_meta(gun, "grip", DEFAULT_SOCKETS.grip)
	var support: Vector3 = weapon_meta(gun, "support", DEFAULT_SOCKETS.support)
	var magwell: Vector3 = weapon_meta(gun, "magwell", DEFAULT_SOCKETS.magwell)
	var style: String = "pistol" if holder.weapon().definition.category == "sidearm" else str(weapon_meta(gun, "grip_pose", "pistol"))
	var angle := deg_to_rad(float(weapon_meta(gun, "grip_angle", 18.0)))
	var radius := float(weapon_meta(gun, "support_radius", .03))
	if str(weapon_meta(gun, "support_pose", "handguard")) in ["handguard", "pump"]:
		radius = maxf(radius, underside(holder, support))
	var palm := Vector3(-.88, 0, -.35)
	if style == "stock":
		# Straight wrist: hand low on the right of the wrist of the stock, thumb over.
		angle = minf(angle, deg_to_rad(12))
		grip += Vector3(0, -.026, -.01)
		palm = Vector3(-.8, .42, -.22)
	var axis := Vector3(0, -cos(angle), sin(angle))
	var holds := {"Right": wrap_grip(grip, axis, palm, GRIP_RADIUS)}
	match str(weapon_meta(gun, "support_pose", "handguard")):
		"pistol":
			holds.Left = wrap_grip(grip + Vector3(-.012, -.012, -.012), axis, Vector3(.92, 0, -.2), .026)
		"magwell", "vertical":
			holds.Left = wrap_grip(support, Vector3.DOWN, Vector3(.95, 0, -.3), radius)
		"angled":
			holds.Left = grasp(support, Vector3(.45, .3, -.7), Vector3(.5, .85, 0), .02)
		_:
			# Under-and-around C grip: palm cups the underside, fingers climb the far side.
			holds.Left = grasp(support, Vector3(.72, .42, -.5), Vector3(.4, .9, .06), radius)
	holds.magazine = magwell + Vector3.DOWN * float(weapon_meta(gun, "magazine_length", .15))
	var to_mount: Transform3D = gun.transform if gun != null else Transform3D.IDENTITY
	for side in SIDES:
		holds[side] = [to_mount * holds[side][0], (to_mount.basis * holds[side][1]).normalized(), (to_mount.basis * holds[side][2]).normalized()]
	holds.magazine = to_mount * holds.magazine
	var sockets: Dictionary = weapon_meta(gun, "sockets", {})
	holds.butt = to_mount * sockets.butt if sockets.get("butt") is Vector3 else Vector3.INF
	return holds

# Slides a long gun forward along its bore until its butt sits in the shoulder pocket
# instead of behind the shoulder: the clips hold a carbine, and a shotgun or sniper rifle
# anchored by the same grip hand would put its stock through the back of the shoulder.
# The pocket is where the carbine's butt lies in the chest frame (shoulder line, spine
# up, forward). Guns whose butt is already in front of it (SMGs, pistols) stay put.
func stock_shift(skeleton: Skeleton3D, basis: Basis, origin: Vector3, butt: Vector3) -> Vector3:
	if not butt.is_finite():
		return Vector3.ZERO
	var behind: float = (origin + basis * butt - pocket_of(skeleton, POCKET)).dot(basis * Vector3.BACK)
	return basis * Vector3.FORWARD * clampf(behind, 0.0, STOCK_REACH)

# A point in the chest frame (shoulder line, spine up, forward) about the right shoulder.
func pocket_of(skeleton: Skeleton3D, offset: Vector3) -> Vector3:
	var shoulder := skeleton.get_bone_global_pose(bones.RightArm).origin
	var right := (shoulder - skeleton.get_bone_global_pose(bones.LeftArm).origin).normalized()
	var up := (skeleton.get_bone_global_pose(bones.Neck).origin - skeleton.get_bone_global_pose(bones.Hips).origin).slide(right).normalized()
	return shoulder + right * offset.x + up * offset.y + up.cross(right) * offset.z

# How far the weapon's body reaches below the support point: a wooden forestock
# hangs well under the bore, beyond the published (barrel) radius. Measured once
# per weapon from the mesh in a 4 cm slab around the support point.
static func underside(holder: Object, support: Vector3) -> float:
	var gun: Node3D = holder.gun
	var key := str(holder.weapon().definition.id) + str(holder.weapon().attachments) + str(support)
	if gun == null or undersides.has(key):
		return undersides.get(key, 0.0)
	var lowest := [support.y]
	scan_underside(gun, Transform3D.IDENTITY, support, lowest)
	undersides[key] = clampf(support.y - lowest[0], 0, .08)
	return undersides[key]

static func scan_underside(node: Node, to_gun: Transform3D, support: Vector3, lowest: Array) -> void:
	for child in node.get_children():
		if not child is Node3D or not child.visible:
			continue
		var transform: Transform3D = to_gun * child.transform
		if child is MeshInstance3D and child.mesh != null:
			for surface in child.mesh.get_surface_count():
				for vertex in child.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var point: Vector3 = transform * vertex
					if absf(point.z - support.z) < .02 and absf(point.x - support.x) < .04 and point.y < lowest[0]:
						lowest[0] = point.y
		scan_underside(child, transform, support, lowest)

static func weapon_meta(gun: Node3D, key: String, fallback: Variant) -> Variant:
	return gun.get_meta(key) if gun != null and gun.has_meta(key) else fallback

# A hand wrapped around a cylinder (axis pointing down it) with the palm against the
# side facing `palm`: knuckles across the front, knuckle line just off the surface.
static func wrap_grip(centre: Vector3, axis: Vector3, palm: Vector3, radius: float) -> Array:
	var across := -axis.normalized()
	var normal := palm.slide(across).normalized()
	var direction := across.cross(normal)
	if direction.z > 0:
		direction = -direction
	return [centre - normal * (radius + KNUCKLE_LIFT), direction, normal]

# A hand closing on a cylinder from a given wrist-to-knuckle direction and palm normal.
static func grasp(centre: Vector3, forward: Vector3, palm: Vector3, radius: float) -> Array:
	var normal := palm.normalized()
	return [centre - normal * (radius + KNUCKLE_LIFT), forward.slide(normal).normalized(), normal]

func palm(skeleton: Skeleton3D, side: String) -> Vector3:
	return skeleton.get_bone_global_pose(bones[side + "Hand"]) * palms[side]

# The direction the clip holds its (invisible) rifle: grip palm to support palm.
func hold_axis(skeleton: Skeleton3D) -> Vector3:
	return (palm(skeleton, "Left") - palm(skeleton, "Right")).normalized()

func align_spine(skeleton: Skeleton3D, axis: Vector3, weight: float) -> void:
	if weight < .01:
		return
	var turn := Quaternion(hold_axis(skeleton), axis)
	var angle := turn.get_angle()
	if angle < .002:
		return
	turn = Quaternion(turn.get_axis(), minf(angle, deg_to_rad(65)) * weight)
	for entry in SPINE:
		var bone: int = bones[entry[0]]
		var pose := skeleton.get_bone_global_pose(bone)
		pose.basis = Basis(Quaternion.IDENTITY.slerp(turn, entry[1])) * pose.basis
		skeleton.set_bone_global_pose(bone, pose)

# Lowers a crouching soldier toward the crouched hurtbox without breaking the
# clip's legs. Kneeling (the crouch idle: one knee on the ground), the hips sit back
# toward that heel by swinging about the grounded knee, so the knee and toes stay
# planted; in the crouch-walk the hips drop a little. The pelvis tips forward and
# both feet are re-planted with the clip's knee directions. The kneel weight is the
# crouch idle's share of the blend (it falls to zero by walking speed), the lower
# knee is chosen softly, and everything scales with the crouch blend, so
# transitions never pop.
func settle_crouch(skeleton: Skeleton3D, amount: float) -> void:
	if amount < .01:
		return
	var feet := {}
	var knees := {}
	var seats := {}
	for side in SIDES:
		feet[side] = skeleton.get_bone_global_pose(bones[side + "Foot"])
		knees[side] = skeleton.get_bone_global_pose(bones[side + "Leg"]).origin
		var thigh: Vector3 = skeleton.get_bone_global_pose(bones[side + "UpLeg"]).origin - knees[side]
		var fold := minf(deg_to_rad(KNEEL_SIT), maxf(0, thigh.angle_to(feet[side].origin - knees[side]) - deg_to_rad(KNEEL_FOLD)))
		seats[side] = Basis(Vector3.RIGHT, fold) * thigh - thigh
	var kneel := clampf(1.0 - actor.anim_blend.length() / (SoldierFactory.rings.get("crouch", 1.5) * .9), 0, 1)
	var left := smoothstep(-.12, .12, knees.Right.y - knees.Left.y)
	var sit: Vector3 = seats.Right.lerp(seats.Left, left) * kneel
	var offset := (sit + Vector3.DOWN * CROUCH_DROP * (1.0 - kneel)) * amount
	skeleton.set_bone_pose_position(bones.Hips, skeleton.get_bone_pose_position(bones.Hips) + offset)
	# Tip the pelvis about the hip joints, which keeps both hips where they are.
	var pelvis := skeleton.get_bone_global_pose(bones.Hips)
	var pivot := (skeleton.get_bone_global_pose(bones.LeftUpLeg).origin + skeleton.get_bone_global_pose(bones.RightUpLeg).origin) * .5
	var tilt := Basis(Vector3.RIGHT, -deg_to_rad(PELVIS_TILT) * amount)
	skeleton.set_bone_global_pose(bones.Hips, Transform3D(tilt * pelvis.basis, pivot + tilt * (pelvis.origin - pivot)))
	for side in SIDES:
		var root := skeleton.get_bone_global_pose(bones[side + "UpLeg"]).origin
		# Knees keep the clip's direction, easing toward forward when the leg is straight.
		var bend: Vector3 = (knees[side] - root).slide((feet[side].origin - root).normalized()) + Vector3.FORWARD * .01
		var toe: Vector3 = feet[side] * toes[side]
		var target: Vector3 = feet[side].origin + Vector3.UP * maxf(0, maxf(TOE_FLOOR - toe.y, ANKLE_FLOOR - feet[side].origin.y))
		solve_chain(skeleton, bones[side + "UpLeg"], bones[side + "Leg"], bones[side + "Foot"], target, bend)
		var foot := skeleton.get_bone_global_pose(bones[side + "Foot"])
		skeleton.set_bone_global_pose(bones[side + "Foot"], Transform3D(feet[side].basis, foot.origin))

# Crouched back and neck: after the spine is aimed, bends it forward over its three
# joints (the shoulders and hands go with it) and takes most of that back out of the
# neck and head so the soldier still looks along the sights.
func hunch(skeleton: Skeleton3D, amount: float) -> void:
	if amount < .01:
		return
	var lean := deg_to_rad(CROUCH_LEAN) * amount
	for entry in HUNCH:
		turn_bone(skeleton, bones[entry[0]], -lean * entry[1])
	turn_bone(skeleton, bones.Neck, lean * HEAD_LEVEL * .5)
	turn_bone(skeleton, bones.Head, lean * HEAD_LEVEL * .5)

# Rotates a bone about its own origin around the soldier's right axis; its children
# follow.
static func turn_bone(skeleton: Skeleton3D, bone: int, angle: float) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(Vector3.RIGHT, angle) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)

# Moves a hand's knuckle line onto a point. On the weapon the hand takes the hold's
# orientation (knuckle direction, palm normal); away from it (pouch, throw) it eases
# back to the clip's orientation. The wrist goes where that puts the knuckles on
# target; the elbow keeps the clip's bend.
func place_hand(skeleton: Skeleton3D, side: String, target: Vector3, direction: Vector3, normal: Vector3, away: float) -> void:
	var hand: int = bones[side + "Hand"]
	var pose := skeleton.get_bone_global_pose(hand)
	var facing := normal.slide(direction).normalized()
	var held: Basis = Basis(direction, facing, direction.cross(facing)) * frames[side].transposed()
	var basis := Basis(held.get_rotation_quaternion().slerp(pose.basis.get_rotation_quaternion(), away))
	var shoulder := skeleton.get_bone_global_pose(bones[side + "Arm"]).origin
	var elbow := skeleton.get_bone_global_pose(bones[side + "ForeArm"]).origin
	var wrist: Vector3 = target - basis * knuckles[side]
	var bend := (elbow - shoulder).slide((wrist - shoulder).normalized())
	if bend.length_squared() < 1e-6:
		bend = Vector3(.6 if side == "Right" else -.6, -1, .1)
	solve_chain(skeleton, bones[side + "Arm"], bones[side + "ForeArm"], hand, wrist, bend)
	skeleton.set_bone_global_pose(hand, Transform3D(basis.orthonormalized(), skeleton.get_bone_global_pose(hand).origin))

# Left hand during a reload: off the handguard to the magazine, down to the belt
# pouch, back up to seat the new magazine, then home. Shotguns feed shells from
# the pouch to the loading port once per shell.
func reload_hand(skeleton: Skeleton3D, support: Vector3, magwell: Vector3, progress: float, shells: bool, now: float) -> Vector3:
	var pouch := skeleton.get_bone_global_pose(bones.Hips).origin + POUCH
	if shells:
		var cycle := fposmod(now, .6) / .6
		var away := smoothstep(.0, .35, cycle) * (1.0 - smoothstep(.55, .95, cycle))
		return support.lerp(magwell, smoothstep(0, .08, progress)).lerp(pouch, away)
	var path := [[0.0, support], [.14, magwell], [.24, magwell], [.42, pouch], [.56, pouch], [.74, magwell], [.84, magwell], [1.0, support]]
	return keyframes(path, progress)

# Right hand during a grenade throw (see THROW), from and back to the grip.
func throw_hand(skeleton: Skeleton3D, grip: Vector3, time: float) -> Vector3:
	var neck := skeleton.get_bone_global_pose(bones.Neck).origin
	var keys := [[0.0, grip]]
	for key in THROW:
		keys.append([key[0], neck + key[1]])
	keys.append([ThrowTimeline.TOTAL, grip])
	return ThrowTimeline.path(keys, time)

static func keyframes(path: Array, progress: float) -> Vector3:
	for i in range(1, path.size()):
		if progress <= path[i][0]:
			var t := smoothstep(path[i - 1][0], path[i][0], progress)
			return path[i - 1][1].lerp(path[i][1], t)
	return path[path.size() - 1][1]

static func envelope(progress: float, rise: float, fall: float) -> float:
	return smoothstep(0, rise, progress) * (1.0 - smoothstep(fall, 1.0, progress))

# Weapon motion layered on the aim pose (weapon-mount space): firing kick, reload
# cant, the low carry while sprinting or drawing, the lowered rifle during a
# throw, and the forward butt-stroke of a melee.
static func weapon_offset(holder: Object, holds: Dictionary) -> Transform3D:
	var now: float = holder.anim_clock
	var runtime: WeaponRuntime = holder.weapon()
	var offset := Transform3D.IDENTITY
	# Turns pivot on the butt in the shoulder (the grip for guns without a stock), so the
	# stock never swings up into the neck or back into the torso.
	var pivot: Vector3 = holds.butt if (holds.butt as Vector3).is_finite() else holds.Right[0]
	var since: float = now - runtime.last_shot_at
	if since >= 0 and since < .3:
		var kick := exp(-since * 18.0) * clampf(runtime.definition.recoil * .6, .4, 1.6)
		offset = turned(offset.translated_local(Vector3(0, .006, .04) * kick), Vector3.RIGHT, .07 * kick, pivot)
	if runtime.state == "RELOADING" and holder.reload_started >= 0:
		var cant := envelope(clampf((now - holder.reload_started) / maxf(holder.reload_length, .1), 0, 1), .12, .86)
		offset = turned(turned(offset.translated_local(Vector3(-.04, -.06, .07) * cant), Vector3.BACK, deg_to_rad(28) * cant, pivot), Vector3.RIGHT, deg_to_rad(-10) * cant, pivot)
	var low := 0.0
	if runtime.state == "EQUIPPING":
		low = clampf((runtime.ready_at - now) / .35, 0, 1)
	low = maxf(low, ThrowTimeline.lowered(ThrowTimeline.seconds(holder, now)) * 1.2)
	if low > .001:
		offset = turned(turned(offset.translated_local(LOWERED_SHIFT * low), Vector3.UP, deg_to_rad(LOWERED_YAW) * low, pivot), Vector3.RIGHT, deg_to_rad(LOWERED_PITCH) * low, pivot)
	if holder.action_kind == "melee" and now < holder.action_until:
		var strike := envelope(1.0 - (holder.action_until - now) / Combatant.MELEE_TIME, .25, .3)
		offset = turned(offset.translated_local(Vector3(-.02, .07, -.3) * strike), Vector3.RIGHT, deg_to_rad(18) * strike, pivot)
	return offset

# `offset` turned by `angle` about `axis` through `pivot` (weapon-mount space).
static func turned(offset: Transform3D, axis: Vector3, angle: float, pivot: Vector3) -> Transform3D:
	var rotation := Basis(axis, angle)
	return offset * Transform3D(rotation, pivot - rotation * pivot)

# Two-bone solve: rotates upper and lower so the end bone's origin reaches target,
# bending towards `bend`. Bone-index form so other rigs (first-person arms) can
# reuse it.
static func solve_chain(skeleton: Skeleton3D, upper: int, lower: int, end: int, target: Vector3, bend: Vector3) -> void:
	var a := skeleton.get_bone_global_pose(upper).origin
	var b := skeleton.get_bone_global_pose(lower).origin
	var c := skeleton.get_bone_global_pose(end).origin
	var first := a.distance_to(b)
	var second := b.distance_to(c)
	var distance := clampf(a.distance_to(target), absf(first - second) + .00001, first + second - .00001)
	var direction := (target - a).normalized()
	var cosine := clampf((first * first + distance * distance - second * second) / (2 * first * distance), -1, 1)
	var elbow := a + direction * first * cosine + bend.slide(direction).normalized() * first * sqrt(1 - cosine * cosine)
	swing_bone(skeleton, upper, b - a, elbow - a)
	b = skeleton.get_bone_global_pose(lower).origin
	c = skeleton.get_bone_global_pose(end).origin
	swing_bone(skeleton, lower, c - b, target - b)

static func swing_bone(skeleton: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	var pose := skeleton.get_bone_global_pose(bone)
	pose.basis = Basis(Quaternion(from.normalized(), to.normalized())) * pose.basis
	skeleton.set_bone_global_pose(bone, pose)
