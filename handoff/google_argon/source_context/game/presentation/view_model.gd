class_name ViewModel
extends Node3D

# First-person rig: the ingested weapon plus the third-person soldier's gloved,
# sleeved arms (Mixamo skeleton, no skin) whose hands are solved onto the weapon's
# grip and support sockets every frame.

const FOV := 70.0
# Aimed down sights the rig narrows its own field of view (the world keeps its own zoom), so
# iron sights and red-dot or holographic windows fill about 1.6x more of the screen. Scopes
# hide the rig once aimed.
const ADS_FOV := 46.0
# Recoil the rig shows per shot, relative to the weapon's recoil rating.
const KICK := .6
const DEPTH_SCALE := .3
const ARMS := "res://content/models/arms/fp_arms.glb"
const CHARACTERS := "res://content/manifest/characters.json"
# Arm surfaces and the soldier texture set they use (sleeves on the uniform, gloves on the gear).
const ARM_PARTS := {"FP_Sleeve":"body","FP_Glove":"gear"}
const TEAM_COLOURS := ["blue","red"]
const SIDE_NAMES := {"L":"Left","R":"Right"}
# Shoulder joints relative to the eye, in camera space (metres).
const SHOULDER := Vector3(.185,-.235,.075)
# Bladed shooting stance: the support shoulder sits forward of the firing shoulder.
const STANCE := {"L":Vector3(.035,.01,-.11),"R":Vector3.ZERO}
# Fingers close along this profile (degrees per joint) until they touch the grip.
const CLOSE := [95.0,105.0,75.0]
# Furthest a shoulder root may travel from its rest position (metres, stance included).
const MAX_SHIFT := .27
# The elbow-led pose may move the shoulder further, since the shoulder stays out of frame.
const MAX_ELBOW_SHIFT := .6
# Preferred forearm direction (elbow to wrist, camera space): both forearms rise from
# the bottom of the frame toward the weapon, elbows hanging below the hands.
const FOREARM := {"L":Vector3(.3,.4,-.87),"R":Vector3(-.14,.36,-.92)}
# Two-handed pistol: the forearms come in from the lower corners in a V (mirrored per side),
# swinging out of line with the hands by at most PISTOL_HOLD.wrist so the wrists stay near neutral.
const FOREARM_PISTOL := {"L":Vector3(.36,.2,-.91),"R":Vector3(-.36,.2,-.91)}
# Two-handed pistol grip, in weapon space (metres, radians). Both hands sit inside the grip's
# silhouette so the grip reads as held: the firing hand turns about its knuckles until its
# fingers point along the forearm (heel behind the backstrap), the support hand wraps from the
# left with its fingers crossing the firing fingers. `drop` is the resting pitch of the hands
# below the barrel line, `wrist` the most a forearm may swing out of line with its hand.
const PISTOL_HOLD := {"wrist":.33,"drop":.05,"fire_back":.35,"fire_turn":.5,"fire_radius":.011,"fire_side":-.02,"fire_fore":.015,
	"support_back":.1,"support_turn":-.45,"support_radius":.02,"support_side":.004,"support_fore":.03}
# The forearm swings toward FOREARM until the wrist reaches this share of its range
# (1.0 = the WRIST_FLEX/WRIST_DEVIATE ellipse); limit_wrist below is the backstop.
const WRIST_COMFORT := .75
# Wrist range of motion (radians): flexion/extension and radial/ulnar deviation, as an ellipse.
const WRIST_FLEX := .85
const WRIST_DEVIATE := .5
const TRIGGER_POSES := ["pistol","stock"]
# Hip carry: where the grip socket sits relative to the eye, per grip style.
const HIP_GRIP := {"pistol":Vector3(.155,-.215,-.3),"stock":Vector3(.155,-.205,-.29),"sidearm":Vector3(.085,-.16,-.36)}
# Cheek weld: the eye sits this far ahead of the butt on long guns; pistols are held out.
const CHEEK := .165
const MIN_RELIEF := {"":.07,"reflex":.12,"holographic":.11}
const PISTOL_RELIEF := .6
# Finger flexion in degrees: [proximal, middle, distal] per finger; thumb uses its own chain.
# Overarm throw, camera space (-Z forward) on ThrowTimeline times: the right wrist goes
# back beside and behind the head (cocked from PULL), whips through RELEASE up and ahead
# of the shoulder, follows down across the body and returns to the grip. Fingers lead
# the wrist; the palm faces where the grenade is going.
const THROW_WRIST := [[0.0,Vector3(.16,-.16,-.32)],[.1,Vector3(.2,-.12,-.12)],[.25,Vector3(.27,.0,.2)],[.3,Vector3(.27,.0,.2)],[.45,Vector3(.14,.04,-.5)],[.6,Vector3(.0,-.24,-.55)],[.72,Vector3(.1,-.36,-.38)],[.85,Vector3(.16,-.16,-.32)]]
const THROW_FINGERS := [[0.0,Vector3(0,.2,-1)],[.25,Vector3(0,.9,.2)],[.3,Vector3(0,.9,.2)],[.45,Vector3(0,.35,-1)],[.6,Vector3(0,-.5,-1)],[.85,Vector3(0,.2,-1)]]
const THROW_PALM := [[0.0,Vector3(-.75,.5,.3)],[.25,Vector3(-.5,.2,-.8)],[.3,Vector3(-.5,.2,-.8)],[.45,Vector3(-.3,-.5,-.8)],[.6,Vector3(-.4,-.4,-.4)],[.85,Vector3(-.75,.5,.3)]]
# Knife slash on Combatant.MELEE_TIME (strike at MELEE_HIT): the rifle drops away, the right
# hand draws the knife up beside the face and cuts across and down from right to left, edge
# leading, then returns to the grip. Camera space, -Z forward.
const KNIFE_WRIST := [[0.0,Vector3(.16,-.2,-.3)],[.07,Vector3(.24,-.06,-.28)],[.14,Vector3(.04,-.1,-.46)],[.22,Vector3(-.14,-.2,-.42)],[.4,Vector3(.06,-.3,-.34)],[.6,Vector3(.16,-.2,-.3)]]
const KNIFE_FINGERS := [[0.0,Vector3(-.1,.2,-1)],[.07,Vector3(.15,.55,-.8)],[.14,Vector3(-.55,.25,-.8)],[.22,Vector3(-.9,-.15,-.4)],[.4,Vector3(-.3,0,-1)],[.6,Vector3(-.1,.2,-1)]]
const KNIFE_PALM := [[0.0,Vector3(-.9,.2,0)],[.07,Vector3(-.95,.1,-.3)],[.14,Vector3(-.5,-.5,.6)],[.22,Vector3(-.15,-.85,.5)],[.4,Vector3(-.8,-.3,.2)],[.6,Vector3(-.9,.2,0)]]
const POSES := {
	"pistol":{"index":[22,38,18],"middle":[78,92,42],"ring":[80,92,40],"pinky":[82,88,38],"thumb":[6,8,4]},
	"stock":{"index":[30,45,22],"middle":[66,80,38],"ring":[68,80,36],"pinky":[70,78,34],"thumb":[34,30,18]},
	"handguard":{"index":[24,36,18],"middle":[32,46,24],"ring":[36,48,24],"pinky":[40,48,24],"thumb":[20,18,10]},
	"pump":{"index":[52,62,32],"middle":[60,72,36],"ring":[62,72,36],"pinky":[64,70,34],"thumb":[8,6,4]},
	"magwell":{"index":[62,74,36],"middle":[70,84,40],"ring":[72,84,38],"pinky":[74,80,36],"thumb":[24,26,14]},
	"vertical":{"index":[70,84,40],"middle":[74,88,42],"ring":[76,88,40],"pinky":[78,84,38],"thumb":[28,30,16]},
	"angled":{"index":[30,40,20],"middle":[40,50,26],"ring":[44,52,26],"pinky":[48,52,26],"thumb":[0,6,4]},
	"pistol_support":{"index":[54,64,30],"middle":[58,70,34],"ring":[60,70,32],"pinky":[62,66,30],"thumb":[2,4,2]},
	"knife":{"index":[58,70,34],"middle":[64,78,38],"ring":[66,78,36],"pinky":[68,74,34],"thumb":[30,34,20]},
	"grenade":{"index":[26,38,20],"middle":[30,42,22],"ring":[34,44,22],"pinky":[38,44,20],"thumb":[24,18,10]},
	"open":{"index":[10,14,8],"middle":[12,16,8],"ring":[14,18,8],"pinky":[16,18,8],"thumb":[6,8,4]}}

static var active: ViewModel

var player: Combatant
var rig: Node3D
var weapon: Node3D
var arms: Node3D
var skeleton: Skeleton3D
var held_grenade: Node3D
var knife: Node3D
var flash: Node3D
var flash_light: OmniLight3D
var blend := 0.0
var sprint := 0.0
var shown := true
# The rig's current field of view (FOV at the hip, narrower aimed down sights).
var fov := FOV
var rig_materials: Array = []
var fixed_materials: Array = []
var previous_ammo := 0
var last_definition := ""
var last_slot := -1
var last_aim := Vector2.ZERO
var stride_phase := 0.0
var flash_until := 0.0
var flash_frame := 0
# Springs: weapon position/rotation offsets and their velocities (camera space).
var kick_offset := Vector3.ZERO
var kick_velocity := Vector3.ZERO
var kick_angle := Vector3.ZERO
var kick_spin := Vector3.ZERO
var sway := Vector2.ZERO
var sway_velocity := Vector2.ZERO
var move_tilt := Vector2.ZERO
var random := RandomNumberGenerator.new()
var bones := {}
var finger_cache := {}
var hand_rest := {}
var arm_base := Vector3.ZERO
var arm_team := -1
var arm_materials := {}
var pistol_hold := false
const MAX_CACHED_RIGS := 24
var cached_rigs:Dictionary={}
var rig_order:Array[String]=[]
static var flash_texture: Texture2D

func _enter_tree() -> void:active=self

func _exit_tree() -> void:
	if active==self:active=null

func refresh(actor: Combatant) -> void:
	player=actor;random.seed=1201
	blend=0;sprint=0;kick_offset=Vector3.ZERO;kick_velocity=Vector3.ZERO;kick_angle=Vector3.ZERO;kick_spin=Vector3.ZERO
	sway=Vector2.ZERO;sway_velocity=Vector2.ZERO;move_tilt=Vector2.ZERO;last_aim=Vector2(player.yaw,player.pitch);stride_phase=0;flash_until=-1
	var runtime:=player.weapon()
	if rig!=null:rig.hide()
	var key:=str(runtime.definition.id)+str(runtime.attachments)
	if not cached_rigs.has(key):
		var pivot:=Node3D.new();pivot.name="WeaponPivot";add_child(pivot)
		var model:=ModelFactory.weapon(runtime.definition,runtime.attachments);pivot.add_child(model)
		var muzzle:=muzzle_flash();model.add_child(muzzle);muzzle.position=model.get_meta("muzzle")
		var light:=OmniLight3D.new();light.light_color=Color(1,.72,.42);light.omni_range=3.5;light.light_energy=0
		light.shadow_enabled=false;light.light_size=.05;muzzle.add_child(light);light.position=Vector3(0,0,-.05)
		prepare_rig(pivot)
		cached_rigs[key]={"rig":pivot,"weapon":model,"flash":muzzle,"light":light,"materials":fov_materials(pivot)}
	var cached:Dictionary=cached_rigs[key]
	rig=cached.rig;weapon=cached.weapon;flash=cached.flash;flash_light=cached.light;rig_materials=cached.materials
	rig.show();flash.hide();flash_light.light_energy=0
	rig_order.erase(key);rig_order.append(key)
	while rig_order.size()>MAX_CACHED_RIGS:
		var expired:String=rig_order.pop_front();cached_rigs[expired].rig.queue_free();cached_rigs.erase(expired)
	# The same skinned arms serve every weapon and recorded killer viewpoint.
	# Keeping their skin and FOV materials alive avoids driver stalls on death.
	if arms==null:
		build_arms();prepare_rig(arms)
	dress_arms(player.slot.team if player.slot!=null else 0)
	if held_grenade==null:
		held_grenade=ModelFactory.grenade(0);add_child(held_grenade);prepare_rig(held_grenade)
	if knife==null:
		knife=ModelFactory.knife();add_child(knife);prepare_rig(knife)
	held_grenade.visible=false;knife.visible=false
	fixed_materials=fov_materials(arms)+fov_materials(held_grenade)+fov_materials(knife)
	fov=-1.0;set_fov(FOV)
	previous_ammo=runtime.ammo;last_definition=str(runtime.definition.id);last_slot=player.selected_weapon

func build_arms() -> void:
	arms=ModelFactory.scene(ARMS);arms.name="Arms";add_child(arms)
	var found:=arms.find_children("*","Skeleton3D",true,false)
	skeleton=found[0] if not found.is_empty() else null
	bones.clear();hand_rest.clear()
	if skeleton==null:return
	for index in skeleton.get_bone_count():bones[skeleton.get_bone_name(index)]=index
	# Place the rig so the right shoulder joint sits at SHOULDER.
	var shoulder:Vector3=skeleton.get_bone_global_rest(bone("R","Arm")).origin
	var skeleton_offset:=Transform3D.IDENTITY
	var node:Node=skeleton
	while node!=arms and node is Node3D:skeleton_offset=node.transform*skeleton_offset;node=node.get_parent()
	arm_base=SHOULDER-skeleton_offset*shoulder
	arms.position=arm_base
	for side in ["L","R"]:hand_rest[side]=rest_frame(side)

# Mixamo bone index: bone("L","ForeArm") -> LeftForeArm, bone("R","HandIndex1") -> RightHandIndex1.
func bone(side:String,part:String) -> int:
	return bones.get(SIDE_NAMES[side]+part,-1)

# Rest-pose hand frame: x = wrist to middle knuckle, z = out of the palm.
func rest_frame(side:String) -> Dictionary:
	var wrist:=rest_point(side,"Hand");var middle:=rest_point(side,"HandMiddle1")
	var index:=rest_point(side,"HandIndex1");var pinky:=rest_point(side,"HandPinky1")
	var forward:=(middle-wrist).normalized()
	var across:=(index-pinky).slide(forward).normalized()
	var normal:=forward.cross(across)
	# Mixamo binds in a T-pose with the palms facing down.
	var palm_sign:=1.0 if normal.dot(Vector3.DOWN)>0 else -1.0
	var arm:=rest_point(side,"Arm").distance_to(rest_point(side,"ForeArm"))+rest_point(side,"ForeArm").distance_to(wrist)
	return {"basis":Basis(forward,across,normal),"palm_sign":palm_sign,"reach":wrist.distance_to(middle),"arm":arm,
		"hand_basis":skeleton.get_bone_global_rest(bone(side,"Hand")).basis}

func rest_point(side:String,part:String) -> Vector3:
	return skeleton.get_bone_global_rest(bone(side,part)).origin

# Sleeves and gloves take the third-person soldier's team-coloured maps.
func dress_arms(team:int) -> void:
	if arms==null or team==arm_team:return
	arm_team=team
	for instance in arms.find_children("*","MeshInstance3D",true,false):
		for surface in instance.mesh.get_surface_count():
			instance.set_surface_override_material(surface,arm_material(instance.mesh.surface_get_material(surface).resource_name,team))

func arm_material(label:String,team:int) -> Material:
	var key:=label+str(team)
	if arm_materials.has(key):return arm_materials[key]
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(CHARACTERS))
	var textures:Dictionary=parsed.get("soldier",{}).get("textures",{}) if parsed is Dictionary else {}
	var maps:Dictionary=textures.get(ARM_PARTS.get(label,"body"),{})
	var material:=StandardMaterial3D.new();material.resource_name=label
	var albedo:=str(maps.get("albedo_"+TEAM_COLOURS[clampi(team,0,1)],""))
	if albedo!="":material.albedo_texture=load(albedo)
	if maps.has("normal"):material.normal_enabled=true;material.normal_texture=load(str(maps.normal))
	if maps.has("orm"):
		var orm:Texture2D=load(str(maps.orm))
		material.roughness_texture=orm;material.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		material.metallic_texture=orm;material.metallic_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE;material.metallic=1.0
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if label=="FP_Sleeve":
		# The sleeve's trailing end carries vertex alpha: it dissolves (hashed, no sorting)
		# instead of ending in a flat polygon when a shifted shoulder swings into view.
		material.vertex_color_use_as_albedo=true;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	arm_materials[key]=first_person(material)
	return arm_materials[key]

# Rig materials keep a fixed first-person FOV and are pulled toward the camera so
# they never clip into walls, while still receiving the world's lighting.
func prepare_rig(node:Node) -> void:
	for instance in node.find_children("*","GeometryInstance3D",true,false):
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.ignore_occlusion_culling=true;instance.extra_cull_margin=4
		if instance.material_override!=null:instance.material_override=first_person(instance.material_override)
		elif instance is MeshInstance3D and instance.mesh!=null:
			for surface in instance.mesh.get_surface_count():
				var material:Material=instance.get_active_material(surface)
				if material!=null:instance.set_surface_override_material(surface,first_person(material))

# Every first-person material under `node` (they carry the rig's FOV override).
func fov_materials(node:Node) -> Array:
	var found:=[]
	for instance in node.find_children("*","GeometryInstance3D",true,false):
		var candidates:=[instance.material_override]
		if instance is MeshInstance3D and instance.mesh!=null:
			for surface in instance.mesh.get_surface_count():candidates.append(instance.get_surface_override_material(surface))
		for material in candidates:
			if material is BaseMaterial3D and material.use_fov_override and not found.has(material):found.append(material)
	return found

func set_fov(value:float) -> void:
	if absf(value-fov)<.01:return
	fov=value
	for material in rig_materials+fixed_materials:material.fov_override=value

func first_person(material:Material) -> Material:
	if not material is BaseMaterial3D:return material
	var copy:=material.duplicate() as BaseMaterial3D
	copy.use_fov_override=true;copy.fov_override=FOV
	copy.use_z_clip_scale=true;copy.z_clip_scale=DEPTH_SCALE
	return copy

func tick(delta: float, clock: float, shake: float) -> void:
	if player==null:visible=false;return
	if last_definition!=str(player.weapon().definition.id) or last_slot!=player.selected_weapon:refresh(player)
	var runtime:=player.weapon()
	var definition:=runtime.definition
	var step:=minf(delta,1.0/30)
	ModelFactory.animate_weapon(weapon,runtime,clock)
	weapon.visible=true;held_grenade.visible=false
	blend=move_toward(blend,1 if player.ads else 0,delta/maxf(.05,runtime.ads_time))
	var eased:=blend*blend*(3-2*blend)
	set_fov(lerpf(FOV,ADS_FOV,eased))
	# Peep sights (a separate rear aperture leaf): fully aimed, the eye is on the front post and
	# the leaf would be a solid disc over the target, so it is put away.
	var rear:=weapon.get_node_or_null("Model/RearSight") as Node3D
	if rear!=null and str(weapon.get_meta("optic"))=="":rear.visible=not ghost_ring()
	# Scopes hide the rig once the optic fills the view.
	visible=shown and player.alive and not (runtime.magnification>=3 and blend>.85)
	if runtime.ammo<previous_ammo:fire_impulse(runtime,shake)
	previous_ammo=runtime.ammo
	integrate_springs(step)
	flash.visible=clock<flash_until
	flash_light.light_energy=1.7*clampf((flash_until-clock)/.05,0,1) if flash.visible else 0.0
	# Aim inertia: the weapon lags the view and settles with a spring.
	var motion:=Vector2(wrapf(player.yaw-last_aim.x,-PI,PI),player.pitch-last_aim.y)
	last_aim=Vector2(player.yaw,player.pitch)
	var target_sway:=(motion/maxf(delta,.001)*.012).limit_length(.11)*(1-eased*.7)
	sway_velocity+=((target_sway-sway)*95-sway_velocity*13)*step;sway+=sway_velocity*step
	var local_velocity:Vector3=Basis(Vector3.UP,player.yaw).inverse()*player.velocity
	move_tilt=move_tilt.lerp(Vector2(local_velocity.x,local_velocity.z)*(1-eased*.75),minf(1,delta*6))
	var speed:=Vector2(player.velocity.x,player.velocity.z).length()
	var grounded:=player.is_on_floor()
	stride_phase+=speed*delta*1.9 if grounded else 0.0
	var sprinting:=speed>5.3 and not player.ads and runtime.state!="RELOADING"
	sprint=move_toward(sprint,1 if sprinting else 0,delta*4)
	var sprint_eased:=sprint*sprint*(3-2*sprint)
	# Placement: blend hip carry to the aimed sight picture.
	var placement:=hip_transform(definition).interpolate_with(aim_transform(definition),eased)
	var weight:=(1-eased*.85)
	var amplitude:=minf(speed,7)/7.0*weight*shake
	var bob:=Vector3(sin(stride_phase)*.011,-absf(cos(stride_phase))*.009,0)*amplitude*(1+sprint_eased*1.2)
	var breathing:=Vector3(sin(clock*1.3)*.0012,sin(clock*2.6)*.0009,0)*(1-eased*.6)
	var offset:=bob+breathing+kick_offset+Vector3(-sway.x*.05-move_tilt.x*.0025,-sway.y*.045,0)
	var angles:=Vector3(kick_angle.x+sway.y*.35+breathing.y*2,kick_angle.y+sway.x*.4,kick_angle.z-sway.x*.5-move_tilt.x*.012+bob.x*1.4)
	var pose:=Transform3D(Basis.from_euler(angles),offset)*placement
	if sprint_eased>.001:
		# Sprint carry: muzzle swung in and down around the grip hand, rig dropped a little.
		var grip:Vector3=weapon.get_meta("sockets").get("grip",Vector3.ZERO)
		var turn:=Basis.from_euler(Vector3(-.62,.16,.34) if definition.category!="sidearm" else Vector3(-.7,.15,.25))
		var lowered:=Transform3D(Basis.IDENTITY,Vector3(-.02,-.035,.03))*pose*Transform3D(turn,grip-turn*grip)
		pose=pose.interpolate_with(lowered,sprint_eased)
	if runtime.state=="EQUIPPING":
		var lift:=clampf((runtime.ready_at-clock)/.35,0,1)
		pose=Transform3D(Basis.from_euler(Vector3(-lift*.9,0,lift*.3)),Vector3(0,-lift*.3,lift*.05))*pose
	var reload:=0.0
	if runtime.state=="RELOADING":
		reload=clampf(1.0-(runtime.reload_at-clock)/maxf(.1,runtime.reload_time),0,1)
		var tilt:=smoothstep(0,.12,reload)*(1-smoothstep(.86,1,reload)) if not definition.shell_reload else .6
		pose=pose*Transform3D(Basis.from_euler(Vector3(.16,-.12,-.45)*tilt),Vector3(-.015,.03,.02)*tilt)
	var throw_time:=ThrowTimeline.seconds(player,clock)
	var throwing:=throw_time>=0
	var knife_time:=Combatant.MELEE_TIME-(player.action_until-clock) if player.action_kind=="melee" and clock<player.action_until else -1.0
	if knife_time>=0:
		# The rifle drops out of view while the knife works, then comes back up.
		var away:=smoothstep(0.0,.08,knife_time)*(1.0-smoothstep(.42,.58,knife_time))
		weapon.visible=away<.98
		pose=Transform3D(Basis.from_euler(Vector3(-.6*away,0,.25*away)),Vector3(.04*away,-.75*away,.2*away))*pose
	if throwing:
		# The weapon drops down and away out of view while both hands work, then comes back.
		var away:=ThrowTimeline.lowered(throw_time)
		weapon.visible=away<.98
		pose=Transform3D(Basis.from_euler(Vector3(-.6*away,0,.25*away)),Vector3(.04*away,-.75*away,.2*away))*pose
	rig.transform=pose
	arms.position=arm_base+bob*.5+breathing*.5+Vector3(-sway.x*.02,-sway.y*.02,kick_offset.z*.3)
	pose_hands(runtime,reload,throw_time,clock,knife_time)

# True while a bare peep sight is aimed and its rear leaf is put away.
func ghost_ring() -> bool:
	return weapon!=null and blend>.85 and str(weapon.get_meta("optic"))=="" and weapon.has_node("Model/RearSight")

func hip_transform(definition:WeaponDefinition) -> Transform3D:
	var sockets:Dictionary=weapon.get_meta("sockets")
	var grip:Vector3=sockets.get("grip",Vector3.ZERO)
	var style:="sidearm" if definition.category=="sidearm" else str(weapon.get_meta("grip_pose"))
	var basis:=Basis.from_euler(Vector3(.02,.085,-.05)) if style!="sidearm" else Basis.from_euler(Vector3(.05,.06,-.02))
	var placed:=Transform3D(basis,HIP_GRIP.get(style,HIP_GRIP.pistol)-basis*grip)
	if definition.category=="wonder":placed.origin+=Vector3(.125,-.155,-.42)
	# Pump guns: draw the weapon back toward the body so the support arm is not dragged
	# to full stretch with its shoulder far forward.
	if style!="sidearm" and sockets.has("support") and hand_rest.has("L"):
		var shoulder:=Vector3(-SHOULDER.x,SHOULDER.y,SHOULDER.z)+STANCE["L"]
		var excess:=(placed*Vector3(sockets.support)).distance_to(shoulder)-.09-float(hand_rest["L"].arm)*.985-.03
		if excess>0:placed.origin+=basis*Vector3.BACK*minf(excess,.1)
	return placed

# The aiming line (rear sight to front sight, or the optic axis) lands on the camera ray,
# with the eye where the cheek weld puts it.
func aim_transform(definition:WeaponDefinition) -> Transform3D:
	var sight:Vector3=weapon.get_meta("sight");var front:Vector3=weapon.get_meta("sight_front")
	var optic:String=weapon.get_meta("optic")
	var line:=(front-sight).normalized()
	if line.length()<.5:line=Vector3.FORWARD
	var eye_z:float
	if weapon.get_meta("sight_is_eye",false):eye_z=sight.z
	elif definition.category=="sidearm":eye_z=sight.z+PISTOL_RELIEF
	else:
		var butt:float=weapon.get_meta("sockets").get("butt",Vector3(0,0,sight.z+.3)).z
		eye_z=maxf(butt-CHEEK,sight.z+float(weapon.get_meta("sight_relief",MIN_RELIEF.get(optic,.07))))
	var eye:=sight-line*((eye_z-sight.z)/maxf(-line.z,.05))
	var basis:=Basis(Quaternion(line,Vector3.FORWARD))
	return Transform3D(basis,-(basis*eye))

func fire_impulse(runtime:WeaponRuntime,shake:float) -> void:
	var definition:=runtime.definition
	var strength:=clampf(definition.recoil*runtime.recoil_scale,.3,2.5)*(.45 if player.ads else 1.0)*KICK
	var heavy:=definition.category in ["sniper","shotgun"] or definition.damage>50
	var back:=(.05 if heavy else .022)*strength
	kick_velocity+=Vector3(random.randf_range(-.08,.08),random.randf_range(.05,.15)*(1 if player.ads else 2),back*14)*shake
	kick_spin+=Vector3((1.9 if heavy else .85)*strength,random.randf_range(-.35,.35)*strength,random.randf_range(-.6,.6)*strength)*shake
	flash_until=player.weapon().last_shot_at+.055;flash_frame=(flash_frame+1+random.randi_range(0,2))%4
	if flash!=null:
		flash.rotation.z=random.randf_range(-PI,PI)
		for child in flash.get_children():
			if child is MeshInstance3D and child.mesh is QuadMesh:
				var mat:=child.get_active_material(0) as StandardMaterial3D
				if mat!=null:mat.uv1_offset=Vector3((flash_frame%2)*.5,(flash_frame/2)*.5,0)
		flash.scale=Vector3.ONE*random.randf_range(.85,1.2)*(.6 if runtime.attachments.has("suppressor") else 1.0)

func integrate_springs(step:float) -> void:
	# Two critically-damped-ish springs: translation settles faster than rotation.
	var substeps:=2
	for i in substeps:
		var h:=step/substeps
		kick_velocity+=(-kick_offset*260-kick_velocity*24)*h;kick_offset+=kick_velocity*h
		kick_spin+=(-kick_angle*190-kick_spin*19)*h;kick_angle+=kick_spin*h

# Hands: grip and support targets from the weapon sockets, then IK and finger poses.
func pose_hands(runtime:WeaponRuntime,reload:float,throw_time:float,clock:float,knife_time:=-1.0) -> void:
	if skeleton==null:return
	skeleton.reset_bone_poses()
	var definition:=runtime.definition
	var sockets:Dictionary=weapon.get_meta("sockets")
	var to_rig:=weapon.global_transform
	pistol_hold=definition.category=="sidearm"
	var grip_style:String="pistol" if definition.category=="sidearm" else str(weapon.get_meta("grip_pose"))
	var angle:=deg_to_rad(float(weapon.get_meta("grip_angle")))
	var forward:=to_rig.basis*Vector3.FORWARD;var right:=to_rig.basis*Vector3.RIGHT;var up:=to_rig.basis*Vector3.UP
	var grip_point:Vector3=to_rig*sockets.get("grip",Vector3.ZERO)
	var grip_palm:=(-right*.88+forward*.35).normalized()
	if definition.category=="sidearm":grip_palm=(-right+forward*float(PISTOL_HOLD.fire_back)).normalized()
	if grip_style=="stock":
		# Straight wrists: the hand closes just behind and below the trigger guard,
		# fingers under the wrist, thumb over the top.
		angle=minf(angle,deg_to_rad(12))
		grip_point=to_rig*(weapon.get_meta("trigger",Vector3.ZERO)+Vector3(0,-.03,.07))
		grip_palm=(-right*.8+up*.42+forward*.22).normalized()
	var grip_axis:=to_rig.basis*Vector3(0,-cos(angle),sin(angle))
	var grip_radius:=float(PISTOL_HOLD.fire_radius) if definition.category=="sidearm" else .016
	# Sidearms: a low grip keeps both hands under the slide in the sight picture.
	if definition.category=="sidearm":grip_point-=up*.02
	# Pistols: the grip crosses the palm diagonally so the hand points along the forearm,
	# not down the rake of the grip.
	var hand_tilt:=maxf(angle-float(PISTOL_HOLD.drop),0.0) if definition.category=="sidearm" else 0.0
	var hand_point:=grip_point+(right*float(PISTOL_HOLD.fire_side)-forward*float(PISTOL_HOLD.fire_fore) if definition.category=="sidearm" else Vector3.ZERO)
	var right_hand:=wrap_frame("R",hand_point,grip_axis,grip_palm,grip_radius,hand_tilt,right,float(PISTOL_HOLD.fire_turn) if definition.category=="sidearm" else 0.0)
	var right_pose:=grip_style
	# Cylinders the fingers close around: [centre, axis, radius] (global).
	var right_grip:=[grip_point,grip_axis,grip_radius]
	var left_grip:=[]
	var throwing:=throw_time>=0
	if throwing:
		var path:=ThrowTimeline.path(THROW_WRIST,throw_time)
		var fingers:=ThrowTimeline.path(THROW_FINGERS,throw_time).normalized()
		var palm:=ThrowTimeline.path(THROW_PALM,throw_time).normalized()
		right_hand=hand_frame("R",global_transform*path,global_transform.basis*fingers,global_transform.basis*palm)
		right_pose="grenade" if throw_time<ThrowTimeline.RELEASE else "open";right_grip=[]
		held_grenade.visible=throw_time>.06 and throw_time<ThrowTimeline.RELEASE
	var slashing:=knife_time>=0 and not throwing
	knife.visible=slashing and knife_time>.03 and knife_time<.53
	if slashing:
		var cut:=hand_frame("R",global_transform*ThrowTimeline.path(KNIFE_WRIST,knife_time),global_transform.basis*ThrowTimeline.path(KNIFE_FINGERS,knife_time).normalized(),global_transform.basis*ThrowTimeline.path(KNIFE_PALM,knife_time).normalized())
		right_hand=right_hand.interpolate_with(cut,smoothstep(0.0,.05,knife_time)*(1.0-smoothstep(.5,.6,knife_time)))
		if knife.visible:right_pose="knife"
		right_grip=[]
	var support_point:Vector3=to_rig*sockets.get("support",sockets.get("grip",Vector3.ZERO))
	var support_pose:String=weapon.get_meta("support_pose")
	var radius:float=weapon.get_meta("support_radius")
	# The pump hand rides the fore-end as it cycles.
	var pump:=weapon.get_node_or_null("Model/Pump") as Node3D
	if pump!=null and support_pose=="pump":
		support_point+=to_rig.basis*(pump.transform.origin-Transform3D(pump.get_meta("rest")).origin)
	var left_hand:Transform3D
	match support_pose:
		"pistol":
			# Low two-handed grip: the support hand wraps the firing hand's fingers
			# under the slide, thumb forward along the frame.
			var wrap_centre:=grip_point+forward*float(PISTOL_HOLD.support_fore)+right*float(PISTOL_HOLD.support_side)-up*.02
			var support_palm:=(right-forward*float(PISTOL_HOLD.support_back)+up*.08).normalized()
			left_hand=wrap_frame("L",wrap_centre,grip_axis,support_palm,float(PISTOL_HOLD.support_radius),hand_tilt,right,float(PISTOL_HOLD.support_turn))
			left_grip=[wrap_centre,grip_axis,float(PISTOL_HOLD.support_radius)]
			support_pose="pistol_support"
		"magwell","vertical":
			left_hand=wrap_frame("L",support_point,-up,(right*.95+forward*.3).normalized(),radius)
			left_grip=[support_point,-up,radius]
		"angled":
			left_hand=grasp("L",support_point,forward*.7+right*.45+up*.3,up*.85+right*.5,.02)
		_:
			# Handguard or pump: palm pressed to the lower-left quarter, fingers closing
			# under and up the far side, thumb along the left. Out of reach, the hand
			# slides back along the handguard before the shoulder has to move.
			# The palm cups the underside, so the hand sits at the bottom of the handguard
			# (below any gas tube or top rail) and the fingers wrap only its lower half.
			var back:=-forward;var slid:=0.0;var limit:=.05
			for attempt in 5:
				left_hand=grasp("L",support_point,forward*.88+right*.4+up*.24,up*.9+right*.38+back*.22,radius)
				var excess:=reach_excess("L",left_hand.origin)
				if excess<=0 or slid>=limit:break
				var step:=minf(excess,limit-slid);support_point+=back*step;slid+=step
			left_grip=[support_point,forward,radius]
	var magazine:=weapon.get_node_or_null("Model/Magazine") as Node3D
	if reload>0:
		left_hand=reload_hand(runtime,reload,magazine,left_hand)
		if reload>.08 and reload<.9:support_pose="magwell";left_grip=[]
	elif magazine!=null:
		magazine.transform=magazine.get_meta("rest");magazine.visible=true
	if throwing:
		# The support arm leaves the weapon and points at the target while the throwing arm works.
		var pointing:=smoothstep(0.0,.2,throw_time)*(1.0-smoothstep(.6,.8,throw_time))
		var pointer:=hand_frame("L",global_transform*Vector3(-.15,-.12,-.5),global_transform.basis*Vector3(.12,.15,-1).normalized(),global_transform.basis*Vector3(.7,-.25,0).normalized())
		left_hand=left_hand.interpolate_with(pointer,pointing)
		if pointing>.35:support_pose="open";left_grip=[]
	# Bolt guns: the firing hand leaves the grip to work the bolt between shots.
	var bolt:=weapon.get_node_or_null("Model/Bolt") as Node3D
	if bolt!=null and str(weapon.get_meta("action"))=="bolt" and not throwing and not slashing and reload<=0:
		var since:=clock-runtime.last_shot_at;var interval:=60.0/runtime.definition.rpm
		var work:=smoothstep(.0,.12,since/interval)*(1-smoothstep(.82,.95,since/interval)) if since>=0 and since<interval else 0.0
		if work>0:
			var handle:=bolt.global_transform*Vector3(.035,0,.02)
			var pinch:=hand_frame("R",handle-forward*.03+right*.05-up*.03,(forward*.6-right*.5+up*.2).normalized(),(-right*.4-up*.9).normalized())
			right_hand=right_hand.interpolate_with(pinch,work)
			if work>.5:right_pose="pistol_support";right_grip=[]
	right_hand=solve_arm("R",right_hand)
	left_hand=solve_arm("L",left_hand)
	if knife.visible:
		# The knife pose is a closed fist round the handle (the contact solver would leave the
		# fingers straight, the handle sitting inside the palm).
		var fist:=fist_axes("R",right_hand)
		# Blade out of the index side of the fist, raked a little forward; edge toward the knuckles.
		var blade:Vector3=(Vector3(fist.across)*.95+Vector3(fist.along)*.3).normalized()
		var back:=-Vector3(fist.along).slide(blade).normalized()
		knife.global_transform=Transform3D(Basis(blade.cross(back),blade,back),Vector3(fist.centre)+blade*ModelFactory.KNIFE_GRIP_Y)
	apply_fingers("R",right_pose,right_hand,right_grip)
	apply_fingers("L",support_pose,left_hand,left_grip)
	if held_grenade.visible:held_grenade.global_position=palm_point("R")

# A handle held in the fist of `side` posed at `hand` (skeleton space): its centre and the
# hand's axes, global. `across` runs pinky to index along the handle.
func fist_axes(side:String,hand:Transform3D) -> Dictionary:
	var rest:Dictionary=hand_rest[side]
	var turn:=hand.basis.orthonormalized()*Basis(rest.hand_basis).inverse()
	var along:=turn*Basis(rest.basis).x;var across:=turn*Basis(rest.basis).y;var palm:=turn*Basis(rest.basis).z*float(rest.palm_sign)
	var to_global:=skeleton.global_transform
	var centre:=hand.origin+along*float(rest.reach)*.6+palm*(ModelFactory.KNIFE_GRIP_RADIUS+.017)
	return {"centre":to_global*centre,"along":(to_global.basis*along).normalized(),"across":(to_global.basis*across).normalized(),"palm":(to_global.basis*palm).normalized()}

# Centre of the palm after posing (global), for objects held in the hand.
func palm_point(side:String) -> Vector3:
	var rest:Dictionary=hand_rest[side]
	var pose:=skeleton.get_bone_global_pose(bone(side,"Hand"))
	var rotation:=pose.basis*Basis(rest.hand_basis).inverse()
	var along:=rotation*Basis(rest.basis).x;var palm:=rotation*Basis(rest.basis).z*float(rest.palm_sign)
	return skeleton.global_transform*(pose.origin+along*float(rest.reach)*.62+palm*.048)

# Magazine change: strip, drop out of view, return with a fresh magazine, seat it.
func reload_hand(runtime:WeaponRuntime,reload:float,magazine:Node3D,support:Transform3D) -> Transform3D:
	var definition:=runtime.definition
	var below:=global_transform*Vector3(-.08,-.62,-.28)
	if definition.shell_reload or magazine==null:
		# Single rounds: the support hand ferries a round to the loading port each cycle.
		var cycle:=fmod(reload*maxf(1,runtime.reload_time/.6),1.0)
		var port:Vector3=weapon.global_transform*(weapon.get_meta("sockets").get("magwell",Vector3.ZERO)+Vector3(0,-.03,.02))
		var reach:=smoothstep(0,.35,cycle)*(1-smoothstep(.7,1,cycle))
		var frame:=wrap_frame("L",port,weapon.global_basis*Vector3.BACK,(weapon.global_basis*Vector3(.4,.9,0)).normalized(),.012)
		frame.origin=(skeleton.global_transform.affine_inverse()*below).lerp(frame.origin,reach)
		return support.interpolate_with(frame,smoothstep(0,.1,reload)*(1-smoothstep(.9,1,reload)))
	var rest:Transform3D=magazine.get_meta("rest")
	var length:=maxf(.06,float(weapon.get_meta("magazine_length")))*magazine.scale.y
	var out:=smoothstep(.12,.24,reload)*(1-smoothstep(.74,.86,reload))
	var away:=smoothstep(.24,.42,reload)*(1-smoothstep(.55,.74,reload))
	var drop:=Vector3(0,-length*1.05*out,-.01*out)
	var magazine_global:=weapon.global_transform*rest.translated(drop)
	magazine_global.origin=magazine_global.origin.lerp(below,away)
	magazine.global_transform=magazine_global
	magazine.visible=away<.98
	var grab:=magazine_global*Vector3(0,-length*.55,0)
	var frame:=wrap_frame("L",grab,-magazine_global.basis.y.normalized(),(weapon.global_basis*Vector3(.95,0,-.3)).normalized(),.015)
	var hold:=smoothstep(.06,.16,reload)*(1-smoothstep(.86,.97,reload))
	return support.interpolate_with(frame,hold)

# Hand wrapped around a cylinder: `axis_down` runs index-to-pinky along it and the
# palm faces `palm` (toward the axis). Handedness then fixes where the fingers point.
# After it is placed, `tilt` turns the hand about the knuckles around `tilt_axis` and `turn`
# around the grip (the grip then crosses the palm diagonally, as it does in a real hand).
func wrap_frame(side:String,centre:Vector3,axis_down:Vector3,palm:Vector3,radius:float,tilt:=0.0,tilt_axis:=Vector3.RIGHT,turn:=0.0) -> Transform3D:
	var rest:Dictionary=hand_rest[side]
	var across:=-axis_down.normalized()
	var normal:=palm.slide(across).normalized()
	var forward:=across.cross(normal*float(rest.palm_sign))
	var knuckles:=centre-normal*(radius+.017)
	if tilt!=0.0:forward=forward.rotated(tilt_axis.normalized(),tilt);normal=normal.rotated(tilt_axis.normalized(),tilt)
	if turn!=0.0:forward=forward.rotated(across,turn);normal=normal.rotated(across,turn)
	return hand_frame(side,knuckles-forward*float(rest.reach),forward,normal)

# Hand closing on a cylinder at `centre`: wrist-to-knuckle direction and palm normal given.
func grasp(side:String,centre:Vector3,forward:Vector3,palm:Vector3,radius:float) -> Transform3D:
	var normal:=palm.normalized()
	var direction:=forward.slide(normal).normalized()
	var knuckles:=centre-normal*(radius+.017)
	return hand_frame(side,knuckles-direction*float(hand_rest[side].reach),direction,normal)

# Hand-bone transform (skeleton space) whose rest frame maps onto (forward, palm normal).
func hand_frame(side:String,wrist:Vector3,forward:Vector3,palm:Vector3) -> Transform3D:
	var rest:Dictionary=hand_rest[side]
	var x:=forward.normalized()
	var z:=(palm*float(rest.palm_sign)).slide(x).normalized()
	var y:=z.cross(x)
	var target_frame:=Basis(x,y,z)
	var to_skeleton:=skeleton.global_transform.affine_inverse()
	var local_frame:=to_skeleton.basis*target_frame
	var rotation:=local_frame*Basis(rest.basis).inverse()
	return Transform3D(rotation*Basis(rest.hand_basis),to_skeleton*wrist)

# Analytic two-bone IK in skeleton space (shoulder, arm, forearm, hand) as in
# StanceModifier.solve_chain, with a real elbow hinge: the upper arm turns so the
# elbow flexes in the plane of shoulder, elbow and wrist, and half of the hand's roll
# goes into the forearm so neither the elbow nor the wrist candy-wraps.
func solve_arm(side:String,hand:Transform3D) -> Transform3D:
	var clavicle:=bone(side,"Shoulder")
	var upper:=bone(side,"Arm");var lower:=bone(side,"ForeArm");var hand_bone:=bone(side,"Hand")
	var clavicle_global:=skeleton.get_bone_global_rest(clavicle)
	var parent_global:=skeleton.get_bone_global_rest(skeleton.get_bone_parent(clavicle))
	var upper_rest:=skeleton.get_bone_global_rest(upper);var lower_rest:=skeleton.get_bone_global_rest(lower)
	var hand_rest_global:=skeleton.get_bone_global_rest(hand_bone)
	var first:=upper_rest.origin.distance_to(lower_rest.origin)
	var wrist_local:=(lower_rest.affine_inverse()*hand_rest_global).origin
	var second:=wrist_local.length()
	var target:=hand.origin
	# Out of reach (long rifles at full extension): the shoulder rolls forward instead of the hand floating.
	# Stance places the shoulder; a target still out of reach moves the arm's root
	# (rigidly skinned) rather than stretching anything.
	var shift:=stance(side)
	# Arms stay slightly bent (elbow about 140 degrees at most) rather than locked straight.
	var reach:=(first+second)*.93
	var root:=upper_rest.origin+shift
	if root.distance_to(target)>reach:
		shift+=(target-root)*(1-reach/root.distance_to(target))
		# Past this the hand lags the target (arm straightened) rather than the shoulder
		# swinging into the picture.
		shift=shift.limit_length(MAX_SHIFT)
	clavicle_global.origin+=shift
	skeleton.set_bone_pose(clavicle,parent_global.affine_inverse()*clavicle_global)
	var upper_global:=clavicle_global*skeleton.get_bone_rest(upper)
	var a:=upper_global.origin
	var distance:=clampf(a.distance_to(target),absf(first-second)+.001,first+second-.001)
	var direction:=(target-a).normalized()
	var cosine:=clampf((first*first+distance*distance-second*second)/(2*first*distance),-1,1)
	var pole:Vector3=skeleton.global_transform.basis.inverse()*(global_basis*Vector3(.55 if side=="R" else -.55,-1,.35))
	# Elbow-led pose. The hand stays exactly where the grip puts it; the forearm
	# swings from the hand's own line toward the preferred direction as far as a
	# comfortable wrist allows, and the shoulder goes wherever that elbow needs it
	# (it is out of frame, and the arm is skinned rigidly to it).
	var frame:=hand_axes(side,hand)
	var hand_line:Vector3=frame.forward
	var preferred:Vector3=(skeleton.global_transform.basis.inverse()*(global_basis*Vector3((FOREARM_PISTOL if pistol_hold else FOREARM)[side]))).normalized()
	var forearm_line:=hand_line
	if pistol_hold:
		var swing_angle:=hand_line.angle_to(preferred)
		if swing_angle>.0001:forearm_line=hand_line.slerp(preferred,minf(1.0,float(PISTOL_HOLD.wrist)/swing_angle)).normalized()
	else:
		for step in range(1,13):
			var candidate:=hand_line.slerp(preferred,step/12.0).normalized()
			if wrist_load(frame,candidate)>WRIST_COMFORT:break
			forearm_line=candidate
	var wanted_elbow:=target-forearm_line*second
	var preferred_shoulder:=upper_rest.origin+stance(side)
	var shoulder:=wanted_elbow+(preferred_shoulder-wanted_elbow).normalized()*first
	var elbow_shift:=(shoulder-upper_rest.origin).limit_length(MAX_ELBOW_SHIFT)
	if elbow_shift.distance_to(shift)>.0005:
		shift=elbow_shift
		clavicle_global=skeleton.get_bone_global_rest(clavicle);clavicle_global.origin+=shift
		skeleton.set_bone_pose(clavicle,parent_global.affine_inverse()*clavicle_global)
		upper_global=clavicle_global*skeleton.get_bone_rest(upper);a=upper_global.origin
		distance=clampf(a.distance_to(target),absf(first-second)+.001,first+second-.001)
		direction=(target-a).normalized()
		cosine=clampf((first*first+distance*distance-second*second)/(2*first*distance),-1,1)
	var centre:=a+direction*first*cosine;var radius:=first*sqrt(1-cosine*cosine)
	var elbow:=centre+(wanted_elbow-centre).slide(direction).normalized()*radius
	# Hinge frames: the T-posed arm flexes forward (-Z) about rest_hinge.
	var rest_dir:=(lower_rest.origin-upper_rest.origin).normalized()
	var rest_hinge:=rest_dir.cross(Vector3.FORWARD).normalized()
	var new_dir:=(elbow-a).normalized();var forearm_dir:=(target-elbow).normalized()
	var new_hinge:=new_dir.cross(forearm_dir)
	if new_hinge.length()<.05:new_hinge=new_dir.cross(pole)
	new_hinge=new_hinge.normalized()
	var swing:=Basis(new_dir,new_hinge,new_dir.cross(new_hinge))*Basis(rest_dir,rest_hinge,rest_dir.cross(rest_hinge)).inverse()
	upper_global.basis=swing*upper_rest.basis
	var lower_basis:=swing*lower_rest.basis
	lower_basis=Basis(Quaternion((lower_basis*wrist_local).normalized(),forearm_dir))*lower_basis
	var implied:=lower_basis*(lower_rest.basis.inverse()*hand_rest_global.basis)
	var delta:=(hand.basis.orthonormalized()*implied.orthonormalized().inverse()).get_rotation_quaternion()
	var twist:=wrapf(2.0*atan2(Vector3(delta.x,delta.y,delta.z).dot(forearm_dir),delta.w),-PI,PI)
	lower_basis=Basis(forearm_dir,twist*.5)*lower_basis
	var lower_global:=Transform3D(lower_basis.orthonormalized(),elbow)
	skeleton.set_bone_pose(upper,clavicle_global.affine_inverse()*Transform3D(upper_global.basis.orthonormalized(),a))
	skeleton.set_bone_pose(lower,Transform3D(upper_global.basis.orthonormalized(),a).affine_inverse()*lower_global)
	var wrist:=lower_global*wrist_local
	# Backstop: never bend the wrist past its range of motion.
	var final_hand:=limit_wrist(side,Transform3D(hand.basis.orthonormalized(),wrist),forearm_dir)
	skeleton.set_bone_pose(hand_bone,lower_global.affine_inverse()*final_hand)
	return Transform3D(final_hand.basis,hand.origin)

# The hand's forward, palm-facing and across axes (skeleton space) for a hand frame.
func hand_axes(side:String,hand:Transform3D) -> Dictionary:
	var rest:Dictionary=hand_rest[side]
	var turn:=hand.basis.orthonormalized()*Basis(rest.hand_basis).inverse()
	var rest_basis:Basis=rest.basis
	return {"forward":turn*rest_basis.x,"palm":turn*rest_basis.z*float(rest.palm_sign),"across":turn*rest_basis.y}

# Wrist flexion and deviation (radians) between a forearm direction and a hand.
# The forearm's direction is read in the hand's own frame: along the hand, and
# sideways towards the palm (flexion) or the thumb (deviation).
func wrist_angles(frame:Dictionary,forearm:Vector3) -> Vector2:
	var along:float=forearm.dot(frame.forward)
	return Vector2(atan2(forearm.dot(frame.palm),along),atan2(forearm.dot(frame.across),along))

# 1.0 at the edge of the wrist's range of motion.
func wrist_load(frame:Dictionary,forearm:Vector3) -> float:
	var angles:=wrist_angles(frame,forearm)
	return pow(angles.x/WRIST_FLEX,2)+pow(angles.y/WRIST_DEVIATE,2)

func limit_wrist(side:String,hand:Transform3D,forearm:Vector3) -> Transform3D:
	var frame:=hand_axes(side,hand)
	var load_value:=wrist_load(frame,forearm)
	if load_value<=1.0:return hand
	# Swing the hand about the wrist, towards the forearm line, until it is inside the range.
	var forward:Vector3=frame.forward
	var angle:=acos(clampf(forward.dot(forearm),-1,1))
	var target_forward:=forearm.slerp(forward,1.0/sqrt(load_value)) if forward.dot(forearm)<.9999 else forward
	var swing:=Basis(Quaternion(forward,target_forward.normalized())) if angle>.0001 else Basis.IDENTITY
	return Transform3D(swing*hand.basis,hand.origin)

# Wrist bend in degrees after posing, from the skeleton itself: the angle between
# the forearm and the hand (wrist to middle knuckle).
func wrist_bend(side:String) -> float:
	var elbow:=skeleton.get_bone_global_pose(bone(side,"ForeArm")).origin
	var wrist:=skeleton.get_bone_global_pose(bone(side,"Hand")).origin
	var knuckle:=skeleton.get_bone_global_pose(bone(side,"HandMiddle1")).origin
	return rad_to_deg((wrist-elbow).normalized().angle_to((knuckle-wrist).normalized()))

# Finger poses. With a grip cylinder, each finger closes along CLOSE until it touches
# the grip (the trigger finger and thumb keep their authored pose); solved once per
# hand, pose and grip size, then cached.
func apply_fingers(side:String,pose:String,frame:=Transform3D(),grip:=[]) -> void:
	var key:=side+pose+("" if grip.is_empty() else "%.3f"%float(grip[2]))
	if not finger_cache.has(key):
		var curls:=contact_curls(side,pose,frame,grip) if not grip.is_empty() else {}
		finger_cache[key]=finger_pose(side,POSES.get(pose,POSES.open),curls)
	for joint in finger_cache[key]:skeleton.set_bone_pose_rotation(joint[0],joint[1])

func contact_curls(side:String,pose:String,frame:Transform3D,grip:Array) -> Dictionary:
	var rest:Dictionary=hand_rest[side]
	var palm:Vector3=Basis(rest.basis).z*float(rest.palm_sign)
	# The grip, carried from the posed hand frame into the rest pose of the hand.
	var to_skeleton:=skeleton.global_transform.affine_inverse()
	var into_rest:=skeleton.get_bone_global_rest(bone(side,"Hand"))*frame.affine_inverse()
	var centre:Vector3=into_rest*(to_skeleton*Vector3(grip[0]))
	var axis:Vector3=(into_rest.basis*(to_skeleton.basis*Vector3(grip[1]))).normalized()
	var surface:=float(grip[2])+.009
	var result:={}
	for finger in ["index","middle","ring","pinky"]:
		if side=="R" and finger=="index" and pose in TRIGGER_POSES:continue
		var prefix:String="Hand"+str(finger).capitalize()
		var p1:=rest_point(side,prefix+"1");var p2:=rest_point(side,prefix+"2");var p3:=rest_point(side,prefix+"3")
		var s1:=p2-p1;var s2:=p3-p2;var s3:=s2*.85
		var k:=s1.normalized().cross(palm).normalized()
		var angles:=[0.0,0.0,0.0]
		# Knuckle first, then middle joint, then fingertip: each phalanx closes until it
		# rests on the grip, so the finger wraps the surface instead of standing off it.
		for joint in 3:
			for step in range(1,25):
				var trial:=angles.duplicate();trial[joint]=float(CLOSE[joint])*step/24.0
				var a:=deg_to_rad(float(trial[0]));var b:=a+deg_to_rad(float(trial[1]));var c:=b+deg_to_rad(float(trial[2]))
				var j2:=p1+s1.rotated(k,a);var j3:=j2+s2.rotated(k,b);var tip:=j3+s3.rotated(k,c)
				var chain:=[p1,j2,j3,tip]
				var start:Vector3=chain[joint];var finish:Vector3=chain[joint+1]
				var touching:=false
				for q in [(start+finish)*.5,finish]:
					var offset:Vector3=q-centre
					if (offset-axis*offset.dot(axis)).length()<=surface:touching=true
				if touching:break
				angles[joint]=trial[joint]
		result[finger]=angles
	return result

func finger_pose(side:String,pose:Dictionary,curls:={}) -> Array:
	var rest:Dictionary=hand_rest[side]
	var palm:Vector3=Basis(rest.basis).z*float(rest.palm_sign)
	var result:=[]
	for finger in ["index","middle","ring","pinky","thumb"]:
		var prefix:String="Hand"+str(finger).capitalize()
		var start:=rest_point(side,prefix+"1");var next:=rest_point(side,prefix+"2")
		var axis:=(next-start).normalized().cross(palm).normalized()
		if finger=="thumb":axis=(next-start).normalized().cross(palm+Basis(rest.basis).x*.6).normalized()
		var angles:Array=curls.get(finger,pose[finger])
		for joint in 3:
			var index:=bone(side,prefix+str(joint+1))
			if index<0:continue
			var local_axis:=skeleton.get_bone_global_rest(index).basis.inverse()*axis
			var rotation:=skeleton.get_bone_rest(index).basis.get_rotation_quaternion()*Quaternion(local_axis.normalized(),deg_to_rad(float(angles[joint])))
			result.append([index,rotation])
	return result

# How far a wrist target (skeleton space) lies beyond the arm's comfortable reach
# from its stance shoulder; <= 0 when reachable.
func reach_excess(side:String,wrist:Vector3) -> float:
	var shoulder:=skeleton.get_bone_global_rest(bone(side,"Arm")).origin+stance(side)
	return shoulder.distance_to(wrist)-float(hand_rest[side].arm)*.93

func stance(side:String) -> Vector3:
	return skeleton.global_transform.basis.inverse()*(global_basis*Vector3(STANCE[side]))

# Point on the weapon where spent cases leave, for first-person casings.
func ejection_transform() -> Transform3D:
	if weapon==null or not is_inside_tree():return Transform3D.IDENTITY
	var port:Vector3=weapon.get_meta("sockets").get("ejection",Vector3.ZERO)
	return Transform3D(weapon.global_basis,weapon.global_transform*port)

func muzzle_flash() -> Node3D:
	var root:=Node3D.new();root.name="MuzzleFlash"
	if flash_texture==null:flash_texture=flash_atlas()
	for i in 3:
		var quad:=MeshInstance3D.new();var mesh:=QuadMesh.new()
		mesh.size=Vector2(.13,.13) if i==0 else Vector2(.1,.24)
		quad.mesh=mesh
		var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_texture=flash_texture;mat.albedo_color=Color(1,.82,.55);mat.uv1_scale=Vector3(.5,.5,1)
		mat.cull_mode=BaseMaterial3D.CULL_DISABLED;mat.disable_receive_shadows=true
		quad.material_override=mat;root.add_child(quad)
		if i==0:quad.position=Vector3(0,0,-.015)
		else:quad.basis=Basis(Vector3.FORWARD,i*PI*.5)*Basis(Vector3.RIGHT,PI*.5);quad.position=Vector3(0,0,-.1)
	root.visible=false
	return root

# Four flash frames (2x2 atlas): hot core, ragged petals and sparks, built once.
static func flash_atlas() -> Texture2D:
	var size:=128;var image:=Image.create(size*2,size*2,false,Image.FORMAT_RGBA8)
	var noise:=RandomNumberGenerator.new();noise.seed=77
	for frame in 4:
		var petals:=4+frame;var twist:=noise.randf()*TAU
		var lengths:=[];for p in petals:lengths.append(noise.randf_range(.55,1.0))
		for y in size:
			for x in size:
				var d:=Vector2(x+.5-size*.5,y+.5-size*.5)/(size*.5)
				var r:=d.length();var a:=atan2(d.y,d.x)+twist
				var petal:=0.0
				for p in petals:
					var centre:=TAU*p/petals;var delta:=absf(wrapf(a-centre,-PI,PI))
					petal=maxf(petal,clampf(1-delta*petals*.55,0,1)*float(lengths[p]))
				var core:=clampf(1-r*2.6,0,1)
				var flame:=clampf((petal-r)*2.2,0,1)*(1-r)
				var value:=clampf(core*1.3+flame,0,1)
				image.set_pixel(x+(frame%2)*size,y+(frame/2)*size,Color(1,.55+value*.45,.2+value*.6,value))
	return ImageTexture.create_from_image(image)
