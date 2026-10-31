class_name Combatant
extends CharacterBody3D

# Knife: the strike lands MELEE_HIT seconds after the press and the action lasts MELEE_TIME.
# It takes the nearest enemy within MELEE_REACH metres of the eye and MELEE_CONE of the aim.
const MELEE_TIME := .6
const MELEE_HIT := .14
const MELEE_REACH := 2.4
const MELEE_CONE := 40.0
const MELEE_DAMAGE := 100.0

var slot: ActorSlot
var health := 100.0
var max_health := 100.0
var movement_scale := 1.0
var alive := true
var yaw := 0.0
var pitch := 0.0
var recoil := 0.0
var crouched := false
var ads := false
var sprinting := false
var protected_until := 0.0
var last_damage_at := -100.0
var eye_height := 1.62
var weapons: Array[WeaponRuntime] = []
var selected_weapon := 0
var frags := 1
var smokes := 1
var action_until := 0.0
var action_kind := ""
var melee_at := -1.0
var throw_at := -1.0
var throw_kind := -1
var throw_started := -1.0
var throw_holding := false
var throw_released := false
var throw_range := -1.0
var throw_rise := 0.0
var collider: CollisionShape3D
var head: Area3D
var torso: Area3D
var nav: NavigationAgent3D
var visual: Node3D
var gun_mount: Node3D
var gun: Node3D
var animation: AnimationTree
var animation_key := ""
var gun_far := false
var footsteps_distance := 0.0
var footstep_index := 0
var audio_airborne := false
var audio_fall_speed := 0.0
var dry_fire_at := 0.0
var last_position := Vector3.ZERO
var bot: BotController
var command := ActorCommand.new()
var skeleton: Skeleton3D
var hand_index := -1
var heard_position := Vector3.ZERO
var heard_at := -100.0
var collision_height := -1.0
var step_collision := KinematicCollision3D.new()
var measure_pose:=false
var pose_cpu_usec:=0
var pose_calls:=0
# Presentation-only animation state (SoldierFactory / stance_modifier.gd read these).
var anim_clock:=0.0
var anim_crouch:=0.0
var anim_blend:=Vector2.ZERO
var anim_air:=0.0
var anim_sprint:=0.0
var aim_weight:=1.0
var anim_shot_at:=-100.0
var anim_step:=1
var anim_pending:=0.0
var reload_started:=-1.0
var reload_length:=1.0
# Tests build the real soldier and weapon models even in a headless run.
static var force_visuals:=false

func setup(source: ActorSlot, catalog: Catalog) -> void:
	slot=source;name="Actor_%02d"%slot.id
	collision_layer=2;collision_mask=3
	floor_snap_length=.3;floor_max_angle=deg_to_rad(35)
	collider=CollisionShape3D.new()
	var shape := CapsuleShape3D.new();shape.height=1.8;shape.radius=.35
	collider.shape=shape;collider.position.y=.9;add_child(collider)
	torso=hurtbox(false);head=hurtbox(true)
	nav=NavigationAgent3D.new();nav.path_desired_distance=.7;nav.target_desired_distance=.9;nav.path_max_distance=4.0
	nav.avoidance_enabled=false;add_child(nav)
	visual=Node3D.new() if headless_visuals() else SoldierFactory.soldier(slot.team);add_child(visual)
	if visual.has_node("Model"):
		animation=SoldierFactory.animate(visual,self);skeleton=SoldierFactory.skeleton_of(visual)
		hand_index=skeleton.find_bone("RightHand")
	gun_mount=Node3D.new();visual.add_child(gun_mount);gun_mount.position=Vector3(.22,1.15,-.23)
	set_loadout(catalog)
	if slot.is_human:visual.visible=false
	else:bot=BotController.new(slot.id)

static func headless_visuals() -> bool:
	return DisplayServer.get_name()=="headless" and not force_visuals

func hurtbox(is_head: bool) -> Area3D:
	var area := Area3D.new();area.collision_layer=4;area.collision_mask=0;area.monitoring=false
	area.set_meta("actor",self);area.set_meta("head",is_head)
	var collision := CollisionShape3D.new()
	if is_head:
		var sphere := SphereShape3D.new();sphere.radius=.19;collision.shape=sphere;area.position.y=1.65
	else:
		var capsule := CapsuleShape3D.new();capsule.radius=.32;capsule.height=1.35;collision.shape=capsule;area.position.y=.78
	area.add_child(collision);add_child(area)
	return area

func set_loadout(catalog: Catalog) -> void:
	weapons.clear()
	for i in 2:
		var runtime := WeaponRuntime.new()
		var id := str(slot.loadout.primary if i==0 else slot.loadout.sidearm)
		runtime.configure(catalog.weapons[id],slot.loadout.primary_attachments if i==0 else slot.loadout.sidearm_attachments)
		weapons.append(runtime)
	selected_weapon=0;refresh_gun()

func refresh_gun() -> void:
	if gun!=null:gun.free()
	gun=Node3D.new() if headless_visuals() else ModelFactory.weapon(weapon().definition,weapon().attachments)
	gun_mount.add_child(gun);gun_far=false

func weapon() -> WeaponRuntime:
	return weapons[selected_weapon]

func eye() -> Vector3:
	return global_position+Vector3(0,eye_height,0)

func aim_direction() -> Vector3:
	return Basis.from_euler(Vector3(pitch+recoil,yaw,0))*Vector3.FORWARD

func excluded() -> Array[RID]:
	return [get_rid(),head.get_rid(),torso.get_rid()]

func switch_to(index: int, now: float) -> bool:
	if index<0 or index>=weapons.size() or index==selected_weapon:return false
	weapon().cancel_reload();selected_weapon=index;weapon().equip(now);refresh_gun();return true

func simulate_movement(delta: float, world: Object) -> void:
	if not alive:return
	yaw=command.aim_yaw;pitch=clampf(command.aim_pitch,-1.48,1.48)
	rotation.y=yaw
	recoil=move_toward(recoil,0,delta*.13)
	var wants_crouch := command.crouch
	if crouched and not wants_crouch:
		var query := PhysicsShapeQueryParameters3D.new()
		var standing := CapsuleShape3D.new();standing.radius=.35;standing.height=1.8
		query.shape=standing;query.transform=Transform3D(Basis.IDENTITY,global_position+Vector3(0,.9,0));query.collision_mask=3;query.exclude=excluded()
		wants_crouch=not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
	var was_crouched:=crouched
	var was_sprinting:=sprinting
	crouched=wants_crouch
	var height := 1.1 if crouched else 1.8
	if not is_equal_approx(collision_height,height):
		collision_height=height
		collider.shape.height=height;collider.position.y=height*.5
		# Crouched, the head hurtbox sits where the kneeling and crouch-walking soldier's
		# head is drawn (centre about 1.0 m).
		head.position.y=height-(.10 if crouched else .15);torso.position.y=(height-.34)*.5;torso.get_child(0).shape.height=height-.34
	eye_height=.98 if crouched else 1.62
	ads=command.aim_down_sights and weapon().state=="READY" and world.clock>=action_until
	var speed := 2.5 if crouched else 5.0
	sprinting=command.sprint and command.movement.y<-.1 and not crouched and not ads and not command.fire_held and not command.fire_pressed and weapon().state=="READY" and world.clock>=action_until
	if sprinting:speed=7
	if slot.is_human and (was_crouched!=crouched or (sprinting and not was_sprinting)):
		world.effects.sound("gear",eye(),.22,true)
	if ads:speed*=.7
	speed*=movement_scale
	var direction := Basis(Vector3.UP,yaw)*Vector3(command.movement.x,0,command.movement.y).limit_length(1)
	if bot!=null:
		var separation := Vector3.ZERO
		for other in world.actors:
			if other==self or not other.alive:continue
			var offset:Vector3=global_position-other.global_position;offset.y=0
			var distance := offset.length()
			if distance>.01 and distance<1.15:separation+=offset.normalized()*(1.15-distance)*1.5
		direction=(direction+separation).limit_length(1)
	var acceleration := 28.0 if direction.length_squared()>.01 else 32.0
	velocity.x=move_toward(velocity.x,direction.x*speed,acceleration*delta)
	velocity.z=move_toward(velocity.z,direction.z*speed,acceleration*delta)
	if not is_on_floor():velocity.y-=24*delta
	elif command.jump_pressed and not crouched:
		velocity.y=6
		world.effects.sound("jump",global_position,.45,slot.is_human)
	audio_fall_speed=maxf(audio_fall_speed,-velocity.y)
	var horizontal := Vector3(velocity.x,0,velocity.z)*delta
	if is_on_floor() and is_on_wall() and horizontal.length()>.001:
		if test_move(global_transform,horizontal,step_collision) and step_collision.get_normal().y<cos(deg_to_rad(35)):
			var raised := global_transform;raised.origin.y+=.35
			if not test_move(global_transform,Vector3.UP*.35) and not test_move(raised,horizontal):global_position.y+=.35
	last_position=global_position
	move_and_slide()
	if is_on_floor():
		if audio_airborne and audio_fall_speed>3.0:
			world.effects.sound("land",global_position,clampf(audio_fall_speed*.065,.3,.85),slot.is_human)
			world.effects.sound(footstep_sound(world),global_position,.45,slot.is_human)
			footsteps_distance=0
		audio_fall_speed=0
		footsteps_distance+=Vector2(global_position.x-last_position.x,global_position.z-last_position.z).length()
		var stride:=1.25 if crouched else (1.95 if sprinting else 1.65)
		if footsteps_distance>=stride:
			footsteps_distance=fmod(footsteps_distance,stride);footstep_index+=1
			var loudness:=.18 if crouched else (.85 if sprinting else .58)
			world.effects.sound(footstep_sound(world),global_position,loudness,slot.is_human)
			if footstep_index%2==0:world.effects.sound("gear",global_position,loudness*.28,slot.is_human)
	audio_airborne=not is_on_floor()
	if health<max_health and world.clock-last_damage_at>=6:health=minf(max_health,health+25*delta)
	update_animation(world.clock)
	update_gun_pose()

func footstep_sound(world: Object) -> String:
	var query:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*.2,global_position+Vector3.DOWN*.65,1)
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	var surface:String=world.effects.surface_of(hit.get("collider"))
	match surface:
		"metal":return "step_metal"
		"earth":return "step_gravel"
		_:return "step"

# A visible soldier's weapon is placed by its pose modifier, from the animated hold
# (stance_modifier.gd); this aimed placement serves headless runs and hidden actors.
func update_gun_pose() -> void:
	if skeleton!=null and visual.visible:return
	var basis:=Basis.from_euler(Vector3(pitch+recoil,yaw,0))
	gun_mount.global_transform=Transform3D(basis,global_position+Vector3.UP*(eye_height-(.15 if ads else .25))+basis*Vector3(.12,0,-.38))

# Drives the AnimationTree from movement and weapon state, then advances the mixer
# and pose modifier by hand (animation LOD): every tick within 15 m of the camera,
# every 2nd tick to 35 m, every 4th tick (15 Hz) beyond that or off screen, and
# at 2 Hz while hidden (the local player keeps a plausible pose for its corpse).
func update_animation(now := -100.0) -> void:
	var delta:=get_physics_process_delta_time()
	if now<0:anim_crouch=1.0 if crouched else 0.0;anim_blend=Vector2.ZERO;anim_air=0;anim_sprint=0;reload_started=-1;anim_shot_at=weapon().last_shot_at
	anim_clock=maxf(now,0)
	var runtime:=weapon()
	if runtime.state=="RELOADING":
		if reload_started<0:reload_started=anim_clock;reload_length=maxf(runtime.reload_at-anim_clock,.1)
	else:reload_started=-1
	if animation==null:return
	var local:=Basis(Vector3.UP,yaw).inverse()*Vector3(velocity.x,0,velocity.z)
	var blend:=Vector2(local.x,-local.z)
	var speed:=blend.length()
	anim_crouch=move_toward(anim_crouch,1.0 if crouched else 0.0,delta*5)
	anim_air=move_toward(anim_air,1.0 if alive and not is_on_floor() and absf(velocity.y)>1.5 else 0.0,delta*6)
	anim_sprint=move_toward(anim_sprint,1.0 if speed>5.6 and not crouched else 0.0,delta*5)
	aim_weight=1.0-anim_sprint
	var rings:=SoldierFactory.rings
	var outer:float=rings.get("crouch",2.0) if crouched else (rings.get("sprint",7.1) if blend.y>absf(blend.x)*2 else rings.get("run",4.8))
	# The blend spaces follow the velocity with a short lag: starting or stopping then
	# crosses idle, kneel and stride clips over ~0.3 s instead of 4 ticks (no pops).
	anim_blend=anim_blend.move_toward(blend,delta*(7.0 if crouched else 16.0))
	animation.set("parameters/stand/blend_position",anim_blend)
	animation.set("parameters/crouch/blend_position",anim_blend)
	animation.set("parameters/posture/blend_amount",anim_crouch)
	animation.set("parameters/pace/scale",clampf(speed/outer,1.0,1.45))
	animation.set("parameters/air/blend_amount",anim_air)
	if runtime.last_shot_at>anim_shot_at:
		anim_shot_at=runtime.last_shot_at
		if now-runtime.last_shot_at<.1:animation.set("parameters/recoil/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	var camera:=get_viewport().get_camera_3d() if is_inside_tree() else null
	anim_step=1 if visual.visible else 30
	if camera!=null and visual.visible:
		var distance:=camera.global_position.distance_to(global_position)
		var far:=ModelFactory.far_weapon(distance,gun_far)
		if far!=gun_far and gun!=null:gun_far=far;ModelFactory.set_weapon_detail(gun,not far)
		anim_step=4 if distance>35 or not camera.is_position_in_frustum(global_position+Vector3.UP) else (2 if distance>15 else 1)
	anim_pending+=delta
	if (Engine.get_physics_frames()+slot.id)%anim_step!=0:return
	var started:=Time.get_ticks_usec() if measure_pose else 0
	animation.advance(anim_pending)
	if measure_pose:pose_cpu_usec+=Time.get_ticks_usec()-started
	skeleton.advance(anim_pending);anim_pending=0

func respawn(position: Vector3, now: float, catalog: Catalog) -> void:
	slot.life_id+=1;slot.respawn_at=-1;slot.next_spawn_attempt=-1
	alive=true;health=100;last_damage_at=now-100;protected_until=now+1.5
	slot.spawned_at=now;command=ActorCommand.new()
	global_position=position+Vector3(0,.1,0);velocity=Vector3.ZERO
	yaw=signf(position.x)*PI*.5;pitch=0;recoil=0;crouched=false;sprinting=false;ads=false;collision_height=-1
	frags=1;smokes=1;action_until=now;action_kind="";melee_at=-1;throw_at=-1;throw_holding=false;throw_released=false;dry_fire_at=now
	footsteps_distance=0;footstep_index=0;audio_airborne=false;audio_fall_speed=0
	head.collision_layer=4;torso.collision_layer=4;collision_layer=2;collision_mask=3
	set_loadout(catalog)
	visual.visible=not slot.is_human
	animation_key="";reset_physics_interpolation()
	update_animation()
	if animation!=null:animation.advance(0)
	update_gun_pose()
	if bot!=null:bot.reset()

func aim_target() -> Vector3:
	return global_position+Vector3.UP*1.3
