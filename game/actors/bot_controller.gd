class_name BotController
extends RefCounted

var id := 0
var rng := RandomNumberGenerator.new()
var state := "PATROL"
var target := -1
var last_seen := Vector3.ZERO
var last_velocity := Vector3.ZERO
var seen_at := -100.0
var acquired_at := 0.0
var destination := Vector3.ZERO
var last_progress := Vector3.ZERO
var stuck_time := 0.0
var blocked_time := 0.0
var recovery_until := 0.0
var aim_error := Vector2.ZERO
var next_error_at := 0.0
var has_goal := false
var qa_route: Array[Vector3] = []
var qa_route_index := 0
var qa_route_visits: Array[int] = []

func _init(slot_id: int) -> void:
	id=slot_id;rng.seed=1201+id*997

func reset() -> void:
	state="PATROL";target=-1;seen_at=-100;has_goal=false;stuck_time=0;blocked_time=0;recovery_until=0

func perceive(actor: Combatant, world: Object) -> void:
	var best := -1
	var best_distance := 100.0
	for enemy in world.actors:
		if not enemy.alive or enemy.slot.team==actor.slot.team:continue
		var offset:Vector3=enemy.eye()-actor.eye()
		var distance:=offset.length()
		if distance>=best_distance:continue
		var facing := actor.aim_direction().dot(offset.normalized())
		if facing<.25 and distance>12:continue
		if world.visible_between(actor.eye(),enemy.eye(),true):best=enemy.slot.id;best_distance=distance
	if best>=0:
		if target!=best:acquired_at=world.clock
		target=best;last_seen=world.actors[target].global_position+Vector3.UP*1.15;last_velocity=world.actors[target].velocity;seen_at=world.clock
		state="ENGAGE"
	elif world.clock-seen_at>2.0:
		target=-1;state="INVESTIGATE" if world.clock-actor.heard_at<4 else "PATROL"

func choose_goal(actor: Combatant, world: Object) -> void:
	if world.clock<recovery_until:return
	if world.stress_mode:
		destination=world.arena.closest(Vector3(-3.5 if actor.slot.team==0 else 3.5,0,rng.randf_range(-10,10)))
		actor.nav.target_position=destination;has_goal=true;return
	if not qa_route.is_empty():
		if has_goal and actor.global_position.distance_to(destination)<2:
			qa_route_visits.append(qa_route_index);qa_route_index=(qa_route_index+1)%qa_route.size()
		destination=world.arena.closest(qa_route[qa_route_index])
		actor.nav.target_position=destination;has_goal=true;return
	var goal := destination
	if actor.weapon().reserve==0 and actor.weapon().ammo<2:
		goal=world.nearest_cache(actor.global_position)
	elif state=="ENGAGE" and actor.health<45:
		state="SEEK_COVER"
		goal=world.claim_cover(actor,last_seen)
	elif state=="ENGAGE":
		var distance := actor.eye().distance_to(last_seen)
		var preferred := 14.0 if actor.weapon().definition.category in ["smg","shotgun"] else 30.0
		if id%4==0 and distance>10:
			var toward:Vector3=last_seen-actor.eye();toward.y=0
			goal=last_seen-Vector3.UP*1.15+toward.normalized().cross(Vector3.UP)*12
		elif distance>preferred:goal=last_seen-Vector3(0,1.15,0)
		else:goal=actor.global_position+Vector3(rng.randf_range(-4,4),0,rng.randf_range(-4,4))
	elif state=="INVESTIGATE":goal=actor.heard_position
	elif not has_goal or actor.global_position.distance_to(goal)<3:
		var lane := id%3
		var options:Array[Vector3]=[]
		for point in world.arena.definition.routes:
			if (lane==0 and point.z< -16) or (lane==1 and absf(point.z)<10) or (lane==2 and point.z>16):options.append(point)
		goal=options[rng.randi_range(0,options.size()-1)]
	goal=world.arena.closest(goal)
	if not has_goal or destination.distance_to(goal)>2.0:
		destination=goal;actor.nav.target_position=goal;has_goal=true

func command(actor: Combatant, world: Object, delta: float) -> ActorCommand:
	var result := ActorCommand.new()
	result.aim_yaw=actor.yaw;result.aim_pitch=actor.pitch
	if not actor.alive:return result
	if has_goal and not actor.nav.is_navigation_finished():
		var next := actor.nav.get_next_path_position()
		var offset := next-actor.global_position;offset.y=0
		var local := Basis(Vector3.UP,-actor.yaw)*offset.normalized()
		result.movement=Vector2(local.x,local.z)
		if state not in ["ENGAGE","SEEK_COVER"] and offset.length()>.2:
			result.aim_yaw=lerp_angle(actor.yaw,atan2(-offset.x,-offset.z),minf(1,delta*4))
	if world.clock-seen_at<.4 and target>=0:
		var aim := last_seen+last_velocity*minf(world.clock-seen_at,.1)-actor.eye()
		if world.clock>next_error_at:
			var error:float=deg_to_rad([1.5,.8,.4][world.difficulty])
			aim_error=Vector2(rng.randf_range(-error,error),rng.randf_range(-error,error));next_error_at=world.clock+.3
		result.aim_yaw=lerp_angle(actor.yaw,atan2(-aim.x,-aim.z)+aim_error.x,minf(1,delta*9))
		result.aim_pitch=lerpf(actor.pitch,atan2(aim.y,Vector2(aim.x,aim.z).length())-actor.recoil+aim_error.y,minf(1,delta*9))
		# Godot's negative-Z forward vector pitches upward for positive X rotation.
		result.aim_down_sights=true
		var delay:float=[.35,.22,.15][world.difficulty]
		var aligned := actor.aim_direction().dot(aim.normalized())>.985
		if world.clock-acquired_at>=delay and aligned and world.visible_between(actor.eye(),last_seen,true):
			result.fire_pressed=true;result.fire_held=true
	if actor.weapon().ammo==0:result.reload_pressed=true
	elif actor.weapon().ammo<actor.weapon().capacity*.3 and world.clock-seen_at>1 and not world.visible_between(actor.eye(),last_seen,false):result.reload_pressed=true
	if actor.weapon().ammo==0 and actor.weapon().reserve==0 and actor.selected_weapon==0:result.requested_weapon_slot=1
	result.sprint=id%4==0 and state=="INVESTIGATE" and actor.global_position.distance_to(actor.heard_position)>25 and result.movement.y<-.5
	result.crouch=state=="SEEK_COVER" and actor.global_position.distance_to(destination)<1.5
	if target>=0 and world.clock-seen_at<.3:
		var range_to_target:=actor.eye().distance_to(last_seen)
		# Face to face, a bot goes for the knife.
		if range_to_target<Combatant.MELEE_REACH-.5 and rng.randf()<[.01,.025,.05][world.difficulty]:result.melee_pressed=true
		if actor.frags>0 and range_to_target>12 and range_to_target<28 and rng.randf()<.001:
			# Overarm with loft: the elevation that lands just short of the target, which then rolls on.
			var offset:=last_seen-actor.eye()
			result.requested_throwable=0;result.throw_range=maxf(Vector2(offset.x,offset.z).length()-2.0,6.0)
			result.throw_rise=last_seen.y-1.15-(actor.eye().y+ThrowTimeline.HAND.y)
		elif actor.smokes>0 and actor.health<35 and rng.randf()<.002:result.requested_throwable=1
	if actor.global_position.distance_to(last_progress)<.25 and result.movement.length()>.1:stuck_time+=delta;blocked_time+=delta
	else:stuck_time=0;blocked_time=0;last_progress=actor.global_position
	if stuck_time>3:
		actor.nav.target_position=world.arena.closest(actor.global_position+Vector3(rng.randf_range(-3,3),0,rng.randf_range(-3,3)))
		has_goal=true;stuck_time=0;recovery_until=world.clock+1
	if blocked_time>10:
		destination=world.arena.closest(world.arena.definition.routes[rng.randi_range(0,world.arena.definition.routes.size()-1)])
		actor.nav.target_position=destination;has_goal=true;blocked_time=0;recovery_until=world.clock+3;state="PATROL"
	return result
