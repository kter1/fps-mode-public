class_name ZombieActor
extends Combatant

var crawling := false
var state := "INACTIVE"
var barrier: Node3D
var attack_at := 0.0
var recover_at := 0.0
var move_speed := 1.5
var enter_progress := 0.0
var entry_start := Vector3.ZERO
var last_progress_at := 0.0
var progress_position := Vector3.ZERO
var hit_awards := 0
var rewarded_shots: Dictionary = {}
var stagger_until := 0.0
var next_path_at := 0.0
var next_visual_update := 0.0
var variant := 0
var portal_crossing := false
var route := PackedVector3Array()
var route_index := 0

func setup(source: ActorSlot, _catalog: Catalog) -> void:
	slot=source;name="Zombie_%02d"%slot.id;variant=slot.id%3
	collision_layer=0;collision_mask=3;floor_snap_length=.4
	collider=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.height=1.8;shape.radius=.35
	collider.shape=shape;collider.position.y=.9;add_child(collider)
	torso=hurtbox(false);head=hurtbox(true)
	visual=Node3D.new() if headless_visuals() else ZombieVisual.new();add_child(visual)
	if visual is ZombieVisual:visual.build(variant)
	deactivate()

func activate(point: Vector3, now: float, hp: float, speed: float, entrance: Node3D) -> void:
	slot.life_id+=1;alive=true;health=hp;max_health=hp;crawling=false;barrier=entrance;state="APPROACH_BARRIER"
	global_position=point;velocity=Vector3.ZERO;move_speed=speed;hit_awards=0;rewarded_shots.clear();attack_at=0;recover_at=0;enter_progress=0
	next_visual_update=0;route.clear();route_index=0;portal_crossing=false;stagger_until=0;next_path_at=0;last_progress_at=now;progress_position=point
	protected_until=0;slot.respawn_at=-1;collision_layer=2;collision_mask=3;head.collision_layer=4;torso.collision_layer=4
	visual.visible=true;anatomy();reset_physics_interpolation()

func deactivate() -> void:
	alive=false;state="INACTIVE";velocity=Vector3.ZERO
	collision_layer=0;collision_mask=0
	if head!=null:head.collision_layer=0;torso.collision_layer=0
	if visual!=null:visual.visible=false

func anatomy() -> void:
	if crawling:
		collider.shape.height=1.4;collider.shape.radius=.3;collider.rotation.x=PI*.5;collider.position=Vector3(0,.32,-.3)
		head.position=Vector3(0,.4,-.7);torso.position=Vector3(0,.3,-.25);torso.rotation.x=PI*.5;torso.get_child(0).shape.height=1.0;eye_height=.45
	else:
		collider.shape.height=1.8;collider.shape.radius=.35;collider.rotation=Vector3.ZERO;collider.position=Vector3(0,.9,0)
		head.position=Vector3(0,1.65,0);torso.position=Vector3(0,.78,0);torso.rotation=Vector3.ZERO;torso.get_child(0).shape.height=1.35;eye_height=1.62

func become_crawler() -> bool:
	if not alive or crawling:return false
	crawling=true;next_visual_update=0;anatomy();return true

func aim_target() -> Vector3:
	return global_transform*(Vector3(0,.35,-.35) if crawling else Vector3(0,1.2,0))

func simulate_movement(delta: float, world: Object) -> void:
	if not alive:return
	var now: float=world.clock
	if (world.ticks+slot.id*17)%300==0:world.cue("z_groan",global_position,.2)
	var player: Combatant=world.actors[0]
	if now<stagger_until:
		velocity.x=move_toward(velocity.x,0,delta*8);velocity.z=move_toward(velocity.z,0,delta*8)
		if not is_on_floor():velocity.y-=24*delta
		move_and_slide();animate(now);return
	if barrier!=null and state in ["APPROACH_BARRIER","TEAR_BARRIER","ENTERING"]:
		if state=="APPROACH_BARRIER":
			var queue_index: int=barrier.occupants.find(slot.id)
			var local_target:=Vector3(0,0,.85) if barrier.attacker==slot.id else Vector3((queue_index-1)*.85,0,2.0+queue_index*.4)
			var goal:=barrier.global_transform*local_target
			var toward:=goal-global_position;toward.y=0
			velocity=toward.normalized()*minf((.65 if crawling else move_speed),toward.length()/maxf(delta,.001))
			move_and_slide()
			if toward.length()<.2 and barrier.attacker==slot.id:state="TEAR_BARRIER"
		elif state=="TEAR_BARRIER":
			if barrier.boards>0:
				if now>=attack_at and barrier.attacker==slot.id:
					barrier.tear(world);attack_at=now+float(world.rules.tear_seconds)
			else:
				if barrier.traveller<0 or barrier.traveller==slot.id:
					barrier.traveller=slot.id;state="ENTERING";entry_start=global_position;enter_progress=0;collision_mask=0
		elif state=="ENTERING":
			enter_progress=minf(1,enter_progress+delta/(1.6 if crawling else 1.1))
			global_position=entry_start.lerp(barrier.inside,enter_progress)+Vector3.UP*(sin(enter_progress*PI)*(.1 if crawling else .35))
			if enter_progress>=1:barrier.release(slot.id);barrier=null;state="PURSUE";collision_mask=3;last_progress_at=now
		if barrier!=null:
			var face: Vector3=barrier.inside-global_position;yaw=atan2(-face.x,-face.z);rotation.y=yaw
		animate(now);return
	if world.downed_until>now or not player.alive:
		var away:=global_position-player.global_position;away.y=0
		velocity=away.normalized()*1.5 if away.length()<4 else Vector3.ZERO
		move_and_slide();animate(now);return
	var target:=player.global_position
	var offset:=target-global_position;offset.y=0
	var reach:=1.1 if crawling else 1.35
	var bite_origin:=global_transform*Vector3(0,.3,-.7) if crawling else global_position
	var melee_offset:=player.global_position-bite_origin;melee_offset.y=0
	var melee_distance:=melee_offset.length()
	if state=="ATTACK_WINDUP":
		if now>=attack_at:
			if melee_distance<reach and world.visible_between(aim_target(),player.global_position+Vector3.UP*.6,false):world.queue_damage(slot.id,player,40,&"zombie",false)
			state="ATTACK_RECOVERY";recover_at=now+(.9 if crawling else .6)
	elif state=="ATTACK_RECOVERY":
		if now>=recover_at:state="PURSUE"
	elif melee_distance<reach:
		state="ATTACK_WINDUP";attack_at=now+(.5 if crawling else .4);world.cue("z_attack",global_position,.35)
	var direction:=Vector3.ZERO
	if state=="PURSUE":
		var nav_map:=get_world_3d().navigation_map
		var nearest:=NavigationServer3D.map_get_closest_point(nav_map,global_position)
		portal_crossing=nearest.distance_to(global_position)>.25
		# Keep the selected portal route until the whole doorway is behind us.
		for station in world.stations:
			if station.kind=="door" and station.opened and global_position.distance_to(station.global_position)<4:portal_crossing=true
		var refresh:=route.is_empty() or route_index>=route.size()
		if now>=next_path_at and not portal_crossing and not route.is_empty() and route[route.size()-1].distance_to(target)>4:refresh=true
		if refresh:
			route=NavigationServer3D.map_get_path(nav_map,global_position,target,false);route_index=0;next_path_at=now+.75
		while route_index<route.size():
			var next_offset:=route[route_index]-global_position;next_offset.y=0
			if next_offset.length()>.3:break
			route_index+=1
		if route_index<route.size():direction=route[route_index]-global_position
		else:direction=offset
		direction.y=0;direction=direction.normalized()
		for other: Combatant in world.actors:
			if other==self or not other.alive:continue
			var separation:=global_position-other.global_position;separation.y=0
			var distance:=separation.length()
			if distance>.01 and distance<.85:direction+=separation.normalized()*(.85-distance)*1.4
		direction=direction.limit_length()
	var speed: float=float(world.rules.crawler_speed) if crawling else move_speed
	velocity.x=move_toward(velocity.x,direction.x*speed,delta*14);velocity.z=move_toward(velocity.z,direction.z*speed,delta*14)
	if not is_on_floor():velocity.y-=24*delta
	else:velocity.y=0
	if offset.length()>.1:yaw=atan2(-offset.x,-offset.z);rotation.y=yaw
	move_and_slide()
	if global_position.distance_to(progress_position)>.6:progress_position=global_position;last_progress_at=now
	elif state=="PURSUE" and offset.length()>3 and now-last_progress_at>12:world.recover_enemy(self)
	animate(now)

func animate(now: float) -> void:
	if visual is ZombieVisual:
		if now<next_visual_update:return
		var world:=get_parent() as ZombiesWorld
		var distance:=global_position.distance_squared_to(world.actors[0].global_position)
		var interval:=0.0 if distance<100 else (1.0/30 if distance<400 else 1.0/15)
		var camera:=get_viewport().get_camera_3d()
		if camera!=null and distance>64 and not camera.is_position_in_frustum(aim_target()):interval=.1
		next_visual_update=now+maxf(0,interval-.0001)
		var reaching:=state=="ATTACK_WINDUP"
		if state=="PURSUE" and get_parent() is ZombiesWorld:reaching=reaching or global_position.distance_to(get_parent().actors[0].global_position)<3.5
		visual.pose(now,crawling,Vector2(velocity.x,velocity.z).length(),reaching,state=="TEAR_BARRIER")
