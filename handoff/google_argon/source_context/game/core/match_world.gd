class_name MatchWorld
extends Node3D

signal ended
signal elimination(text: String, team: int)
signal player_hit(headshot: bool, killed: bool)
signal player_damaged(source_position: Vector3)
signal player_eliminated(source_slot: int, death_time: float)
signal weapon_changed
# Rounds the player took from dropped weapons.
signal ammo_scavenged(rounds: int)

const TEAM_SIZE := 8
const RESPAWN_DELAY := 3.0
const MAX_PASS := 4
# Share of each weapon's recoil rating that kicks the aim per shot.
const RECOIL_SCALE := .6
# Dropped weapons: how close the player must be, how long they lie, how many at once.
const PICKUP_REACH := 1.8
const PICKUP_LIFETIME := 30.0
const MAX_PICKUPS := 10

var catalog: Catalog
var arena: MapArena
var actors: Array[Combatant] = []
var slots: Array[ActorSlot] = []
var mode: Variant = TeamDeathmatchMode.new()
var mode_id := "tdm"
var spawner := SpawnDirector.new()
var effects: MatchEffects
var clock := 0.0
var ticks := 0
var countdown := 3.0
var ready_for_play := false
var difficulty := 1
var seed_value := 1201
var rng := RandomNumberGenerator.new()
var player_command := ActorCommand.new()
var automation := false
var stress_mode := false
var profile_phases:=false
var profile_ticks:=0
var phase_usec:Dictionary={"ai":0,"movement":0,"combat":0,"damage":0,"respawns_supplies":0,"effects_mode":0}
var damage_queue: Array[DamageEvent] = []
var recent_deaths: Array[Dictionary] = []
var smoke_clouds: Array[Dictionary] = []
var grenades: Array[GameGrenade] = []
var supply_times: Dictionary = {}
var cover_claims: Dictionary = {}
var contact_times: Array[float] = []
var contacts: Dictionary = {}
var sequence := 0
var lane_ticks := [0,0,0]
var corpses: Array[Dictionary] = []
var replay_history:=ReplayHistory.new()
var pending_player_death:Dictionary={}
var qa_protect_player:=false
var destructibles: Array[Destructible] = []
var active_destructibles: Array[Destructible] = []
var explosion_queue: Array[Dictionary] = []
var explosion_sequence := 0
# Weapons on the ground: {weapon, attachments, ammo, reserve, position, expires, node,
# scavenged (weapon ids already given a magazine from it), dropper (slot:life that let go)}.
var pickups: Array[Dictionary] = []
# The latest kill with the recorded frames leading up to it (the end-of-match kill cam).
var final_kill: Dictionary = {}

func configure(source: Catalog, map_id: String, loadout: LoadoutDefinition, level: int, random_seed: int, auto := false) -> void:
	catalog=source;difficulty=level;seed_value=random_seed;automation=auto;rng.seed=random_seed
	process_mode=Node.PROCESS_MODE_PAUSABLE
	NavigationServer3D.map_set_use_async_iterations(get_world_3d().navigation_map,false)
	var path := "res://game/maps/generated/"+map_id+".tscn"
	arena=load(path).instantiate()
	add_child(arena)
	destructibles=arena.destructibles
	for prop in destructibles:prop.world=self
	NavigationServer3D.region_set_use_async_iterations(arena.nav_region.get_rid(),false)
	effects=MatchEffects.new();add_child(effects)
	effects.configure_audio(map_id)
	var callsigns := [["YOU","ROOK","ATLAS","NOVA","GHOST","HARBOR","ECHO","VIPER","SABLE","FLINT","NOMAD","LYNX"],["WRAITH","RAVEN","KILO","EMBER","WOLF","RANGER","HAWK","ONYX","CINDER","FALCON","MICA","DUSK"]]
	for i in TEAM_SIZE*2:
		var slot := ActorSlot.new();slot.id=i;slot.team=0 if i<TEAM_SIZE else 1;slot.is_human=i==0;slot.callsign=callsigns[slot.team][i%TEAM_SIZE]
		slot.loadout=loadout if i==0 else LoadoutDefinition.new()
		if i!=0:
			slot.loadout.primary=StringName(catalog.weapon_ids[(i*7)%12])
			slot.loadout.primary_attachments.assign(["reflex"] if i%3==0 else [])
		slots.append(slot)
		var actor := Combatant.new();add_child(actor);actor.setup(slot,catalog);actor.measure_pose=profile_phases;actors.append(actor)
		actor.alive=false;actor.collision_layer=0;actor.head.collision_layer=0;actor.torso.collision_layer=0
		if automation and i==0:actor.bot=BotController.new(0)
		if automation and i==0 and not stress_mode:actor.bot.qa_route=arena.definition.qa_route.duplicate()
	mode.begin(self)
	call_deferred("finish_loading")

func finish_loading() -> void:
	if arena.nav_region.navigation_mesh.get_polygon_count()==0:
		push_error("Saved navigation is missing; run preparation before launching.");return
	await get_tree().physics_frame
	await get_tree().physics_frame
	NavigationServer3D.map_set_active(get_world_3d().navigation_map,true)
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)
	var nav_map:=get_world_3d().navigation_map
	var deadline:=Time.get_ticks_msec()+15000
	# A forced update can still precede the first published iteration. Never
	# issue a spatial query against iteration zero, including on a rematch.
	while NavigationServer3D.map_get_iteration_id(nav_map)==0 or NavigationServer3D.map_get_closest_point_owner(nav_map,arena.definition.spawns_blue[0])!=arena.nav_region.get_rid():
		if Time.get_ticks_msec()>=deadline:
			push_error("Map navigation did not synchronize within 15 seconds: "+arena.definition.id);return
		await get_tree().physics_frame
	for actor in actors:
		var point = spawner.select(actor,self,true)
		if point==null:
			push_error("No valid spawn for slot "+str(actor.slot.id));continue
		actor.respawn(point,0,catalog)
		if actor.bot!=null:actor.bot.rng.seed=seed_value+actor.slot.id*997
	ready_for_play=true

func _physics_process(delta: float) -> void:
	if not ready_for_play or mode.finished:return
	if countdown>0:
		var previous:=ceili(countdown)
		countdown=maxf(0,countdown-delta)
		if ceili(countdown)<previous:effects.sound("spawn" if countdown==0 else "ui_accept",Vector3.ZERO,.45 if countdown==0 else .22,true)
		return
	clock+=delta;ticks+=1
	var stamp:int=Time.get_ticks_usec() if profile_phases else 0
	for actor in actors:
		if not actor.alive:continue
		if actor.bot!=null:
			if (ticks+actor.slot.id)%6==0:
				actor.bot.perceive(actor,self)
				if absf(actor.global_position.x)<35:lane_ticks[0 if actor.global_position.z< -16 else (2 if actor.global_position.z>16 else 1)]+=1
				var key := "%d:%d"%[actor.slot.id,actor.slot.life_id]
				if actor.bot.target>=0 and not contacts.has(key):contacts[key]=true;contact_times.append(clock-actor.slot.spawned_at)
			if (ticks+actor.slot.id)%30==0:actor.bot.choose_goal(actor,self)
			actor.command=actor.bot.command(actor,self,delta)
		else:actor.command=player_command
	if profile_phases:stamp=profile_mark("ai",stamp)
	for actor in actors:actor.simulate_movement(delta,self)
	if profile_phases:stamp=profile_mark("movement",stamp)
	for actor in actors:
		if actor.alive:combat(actor)
	if profile_phases:stamp=profile_mark("combat",stamp)
	for grenade in grenades.duplicate():
		grenade.step(delta)
		if clock>=grenade.detonate_at:
			detonate(grenade);grenades.erase(grenade);grenade.queue_free()
	resolve_damage()
	step_destructibles()
	if profile_phases:stamp=profile_mark("damage",stamp)
	for actor in actors:
		if not actor.alive and actor.slot.respawn_at>=0 and clock>=actor.slot.respawn_at and clock>=actor.slot.next_spawn_attempt:
			var point = spawner.select(actor,self,false)
			# The requested three-second timer is fixed. If every hidden point is
			# exposed, use the best clear capsule with spawn protection at that time.
			if point==null:point=spawner.select(actor,self,true)
			if point!=null:
				actor.respawn(point,clock,catalog)
				if actor.slot.id==0:
					player_command=ActorCommand.new();weapon_changed.emit();effects.sound("spawn",actor.eye(),.5,true)
			else:
				actor.slot.next_spawn_attempt=clock+.2
		if actor.alive:supply(actor)
	tick_pickups()
	if profile_phases:stamp=profile_mark("respawns_supplies",stamp)
	for cloud in smoke_clouds.duplicate():
		if clock>=cloud.expires:cloud.node.queue_free();smoke_clouds.erase(cloud)
	for corpse in corpses.duplicate():
		if clock>=corpse.expires:corpse.node.queue_free();corpses.erase(corpse)
	while recent_deaths.size()>48:recent_deaths.pop_front()
	effects.tick(clock)
	effects.audio.set_listener_health(actors[0].health,actors[0].alive)
	if DisplayServer.get_name()!="headless":replay_history.record(clock,actors,not pending_player_death.is_empty())
	if not pending_player_death.is_empty():
		player_eliminated.emit(pending_player_death.source,pending_player_death.time);pending_player_death.clear()
	mode.tick(delta)
	if profile_phases:profile_mark("effects_mode",stamp);profile_ticks+=1
	player_command.fire_pressed=false;player_command.reload_pressed=false;player_command.jump_pressed=false;player_command.melee_pressed=false;player_command.interact_pressed=false;player_command.requested_throwable=-1;player_command.requested_weapon_slot=-1
	if mode.finished:ended.emit()

func profile_mark(section:String,started:int) -> int:
	var now:=Time.get_ticks_usec();phase_usec[section]+=now-started;return now

func visible_between(start: Vector3, end: Vector3, smoke := true, exclude: Array[RID] = []) -> bool:
	if smoke:
		for cloud in smoke_clouds:
			if Geometry3D.get_closest_point_to_segment(cloud.position,start,end).distance_to(cloud.position)<5:return false
	var query := PhysicsRayQueryParameters3D.create(start,end,1,exclude)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func combat(actor: Combatant) -> void:
	var command := actor.command
	if command.requested_weapon_slot>=0 and actor.switch_to(command.requested_weapon_slot,clock):
		effects.sound("switch",actor.eye(),.6,actor.slot.is_human)
		if actor.slot.id==0:weapon_changed.emit()
	var runtime := actor.weapon();runtime.tick(clock)
	if actor.melee_at>=0 and clock>=actor.melee_at:
		actor.melee_at=-1
		knife(actor)
	if actor.throw_holding and ((not command.throw_held and clock>=actor.throw_started+ThrowTimeline.PULL) or clock-actor.throw_started>=ThrowTimeline.MAX_COOK):
		actor.throw_holding=false;actor.throw_at=clock+ThrowTimeline.RELEASE-ThrowTimeline.PULL;actor.action_until=actor.throw_at+ThrowTimeline.TOTAL-ThrowTimeline.RELEASE
	if actor.throw_at>=0 and not actor.throw_released and clock>=actor.throw_at:
		actor.throw_released=true;throw_grenade(actor)
	if actor.throw_holding:return
	if clock<actor.action_until:return
	if command.requested_throwable>=0 and ((command.requested_throwable==0 and actor.frags>0) or (command.requested_throwable==1 and actor.smokes>0)):
		actor.throw_kind=command.requested_throwable;actor.throw_started=clock;actor.throw_holding=true;actor.throw_released=false;actor.throw_at=-1
		actor.throw_range=command.throw_range;actor.throw_rise=command.throw_rise
		actor.action_until=clock+60;actor.action_kind="throw";actor.protected_until=clock
		effects.sound("grenade_pin",actor.eye(),.6,actor.slot.is_human);return
	if command.interact_pressed and actor.slot.id==0:
		var entry:=swap_candidate(actor)
		if not entry.is_empty():swap_weapon(actor,entry);return
	if command.melee_pressed:
		actor.melee_at=clock+Combatant.MELEE_HIT;actor.action_until=clock+Combatant.MELEE_TIME;actor.action_kind="melee";actor.protected_until=clock
		effects.sound("knife",actor.eye(),.8,actor.slot.id==0);return
	if command.reload_pressed and runtime.start_reload(clock):effects.sound("reload",actor.eye(),.65,actor.slot.is_human)
	if runtime.ammo==0 and command.fire_pressed and runtime.state=="READY" and clock>=actor.dry_fire_at:
		effects.sound("click",actor.eye(),.8,actor.slot.id==0);actor.dry_fire_at=clock+.2
	if runtime.try_fire(clock,command.fire_pressed,command.fire_held):
		actor.protected_until=clock
		fire(actor,runtime)
		actor.recoil+=deg_to_rad(runtime.definition.recoil*runtime.recoil_scale*RECOIL_SCALE)
	# An empty magazine reloads itself as soon as the weapon is ready (players and bots).
	if runtime.ammo==0 and runtime.start_reload(clock):effects.sound("reload",actor.eye(),.65,actor.slot.is_human)

# The knife takes the nearest enemy in a short cone in front of the eye (a lunge rather than
# a precise ray) with nothing solid in between; one strike kills.
func knife(actor: Combatant) -> void:
	var forward:=actor.aim_direction();var best:Combatant=null;var best_score:=INF
	for other in actors:
		if not other.alive or other==actor or other.slot.team==actor.slot.team:continue
		var target:=other.global_position+Vector3.UP*other.eye_height*.7
		var offset:=target-actor.eye();var distance:=offset.length()
		if distance>Combatant.MELEE_REACH:continue
		var angle:=forward.angle_to(offset/maxf(distance,.01))
		if angle>deg_to_rad(Combatant.MELEE_CONE) or not visible_between(actor.eye(),target,false):continue
		var score:=distance+angle*1.5
		if score<best_score:best=other;best_score=score
	if best==null:return
	queue_damage(actor.slot.id,best,Combatant.MELEE_DAMAGE,&"knife",false)
	var point:=best.global_position+Vector3.UP*best.eye_height*.7
	effects.emit("mist",point,Basis.looking_at(forward,Vector3.UP));effects.sound("knife_hit",point,.9,actor.slot.id==0)

# Bullets continue through "shoot_through" bodies (glass); the hits on them are
# appended to `crossed` so the caller can shatter them and scale the damage.
func ray(start: Vector3, end: Vector3, actor: Combatant, crossed: Array = []) -> Dictionary:
	var exclude:=actor.excluded()
	var passes:=0
	while true:
		var query := PhysicsRayQueryParameters3D.create(start,end,5,exclude)
		query.collide_with_areas=true
		var result:=get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty() or not result.collider.has_meta("shoot_through") or passes>=MAX_PASS:return result
		crossed.append(result);exclude.append(result.rid);passes+=1
	return {}

func fire(actor: Combatant, runtime: WeaponRuntime) -> void:
	sequence+=1
	var origin := actor.eye()
	var forward := actor.aim_direction()
	var basis := Basis.looking_at(forward,Vector3.UP)
	var muzzle := origin+basis*Vector3(.16,-.14,-.6)
	var blocked_glass:Array=[]
	var blocked := ray(origin,muzzle,actor,blocked_glass)
	var pellets:Dictionary={}
	var def := runtime.definition
	effects.sound(def.category,origin,1 if actor.slot.id==0 else .65,actor.slot.id==0)
	# Visual effects start at the third-person weapon's own muzzle; the gameplay
	# muzzle above stays fixed relative to the eye.
	var visible_muzzle := muzzle
	if actor.slot.id!=0 and actor.gun!=null and actor.gun.has_meta("muzzle"):visible_muzzle=actor.gun.global_transform*Vector3(actor.gun.get_meta("muzzle"))
	effects.eject_casing(visible_muzzle,basis.x)
	for other in actors:
		if other.alive and other.slot.team!=actor.slot.team and other.global_position.distance_to(origin)<85*runtime.hearing_scale:
			other.heard_position=actor.global_position;other.heard_at=clock
	for i in def.pellets:
		var angle := deg_to_rad(def.ads_spread if actor.ads else def.hip_spread*runtime.hip_scale)
		var radius := sqrt(rng.randf())*tan(angle)
		var theta := rng.randf()*TAU
		var direction := (forward+basis.x*cos(theta)*radius+basis.y*sin(theta)*radius).normalized()
		var aim_hit := ray(origin,origin+direction*200,actor)
		var target:Vector3=aim_hit.get("position",origin+direction*200)
		var crossed:Array=blocked_glass.duplicate()
		var hit := blocked if not blocked.is_empty() else ray(muzzle,target+direction*.025,actor,crossed)
		var point:Vector3=hit.get("position",target)
		if i==0 and actor.slot.id!=0 and actors[0].alive:
			effects.audio.bullet_pass(muzzle,point,actors[0].eye(),clock)
		if i==0 and (actor.slot.id==0 or sequence%3==0):effects.tracer(visible_muzzle,point,not hit.is_empty())
		var carry:=pow(Destructible.GLASS_PASS,crossed.size())
		for pane in crossed:
			var glass:Destructible=pane.collider.get_meta("destructible",null)
			if glass!=null:glass.hit(0,actor.slot.id,pane.position,pane.normal)
			else:effects.decal_at(pane.position,pane.normal,"concrete")
		if hit.has("collider") and hit.collider.has_meta("destructible"):
			var prop:Destructible=hit.collider.get_meta("destructible")
			prop.hit(def.damage_at(origin.distance_to(point)/runtime.range_scale,false)*carry*runtime.damage_scale,actor.slot.id,point,hit.normal)
		if hit.has("collider") and hit.collider.has_meta("actor"):
			var victim:Combatant=hit.collider.get_meta("actor")
			var headshot:bool=hit.collider.get_meta("head")
			var amount := def.damage_at(origin.distance_to(point)/runtime.range_scale,headshot)*carry*runtime.damage_scale
			if not pellets.has(victim.slot.id):pellets[victim.slot.id]={"amount":0.0,"head":false}
			pellets[victim.slot.id].amount+=amount;pellets[victim.slot.id].head=pellets[victim.slot.id].head or headshot
	for victim_id in pellets:
		queue_damage(actor.slot.id,actors[victim_id],pellets[victim_id].amount,def.id,pellets[victim_id].head)

func queue_damage(source: int, victim: Combatant, amount: float, weapon: StringName, headshot: bool) -> void:
	var event := DamageEvent.new();event.event_id=sequence;event.source_slot=source;event.victim_slot=victim.slot.id;event.victim_life=victim.slot.life_id;event.amount=amount;event.weapon_id=weapon;event.headshot=headshot
	damage_queue.append(event)

func resolve_damage() -> void:
	for event in damage_queue:
		var victim := actors[event.victim_slot]
		if qa_protect_player and event.victim_slot==0:continue
		if not victim.alive or victim.slot.life_id!=event.victim_life or clock<victim.protected_until:continue
		if event.source_slot>=0 and event.source_slot!=event.victim_slot and slots[event.source_slot].team==victim.slot.team:continue
		victim.health-=event.amount;victim.last_damage_at=clock
		if event.victim_slot==0:effects.sound("hurt",victim.eye(),.65,true)
		elif event.source_slot==0:effects.sound("kill_confirm" if victim.health<=0 else "hit_confirm",victim.eye(),.4 if victim.health<=0 else .23,true)
		if event.victim_slot==0 and event.source_slot>=0:player_damaged.emit(actors[event.source_slot].global_position)
		if event.source_slot==0:player_hit.emit(event.headshot,victim.health<=0)
		if victim.health<=0:die(victim,event)
	damage_queue.clear()

func die(victim: Combatant, event: DamageEvent) -> void:
	victim.alive=false;victim.health=0;victim.slot.deaths+=1;victim.slot.death_at=clock;victim.slot.respawn_at=clock+RESPAWN_DELAY
	if victim.slot.id==0:pending_player_death={"source":event.source_slot,"time":clock}
	# The frames recorded so far end just before this death, with the victim still standing.
	if event.source_slot>=0 and event.source_slot!=victim.slot.id and DisplayServer.get_name()!="headless":
		var frames:=replay_history.preceding(clock,3.2)
		if frames.size()>=2:final_kill={"source":event.source_slot,"victim":victim.slot.id,"time":clock,"weapon":event.weapon_id,"frames":frames}
	drop_weapon(victim,victim.weapon())
	victim.slot.next_spawn_attempt=victim.slot.respawn_at
	victim.head.collision_layer=0;victim.torso.collision_layer=0;victim.collision_layer=0;victim.collision_mask=0
	victim.melee_at=-1;victim.throw_at=-1;victim.throw_holding=false;victim.visual.visible=false
	if event.source_slot>=0 and event.source_slot!=victim.slot.id:slots[event.source_slot].kills+=1
	mode.on_actor_died({"source":event.source_slot,"victim":victim.slot.id})
	recent_deaths.append({"time":clock,"position":victim.global_position})
	var source_name:String=slots[event.source_slot].callsign if event.source_slot>=0 else "ENVIRONMENT"
	var cause:=""
	if event.weapon_id==&"barrel":cause="BARREL  ›  "
	elif event.weapon_id==&"car":cause="CAR  ›  "
	elif event.weapon_id==&"knife":cause="KNIFE  ›  "
	elimination.emit(source_name+"  ›  "+cause+victim.slot.callsign,slots[event.source_slot].team if event.source_slot>=0 else 1)
	if DisplayServer.get_name()=="headless":return
	if corpses.size()>=8:corpses.pop_front().node.queue_free()
	var direction:=Vector3.ZERO
	if event.source_slot>=0 and event.source_slot!=victim.slot.id:direction=(victim.global_position-actors[event.source_slot].global_position).normalized()
	corpses.append({"node":SoldierFactory.corpse(self,victim,direction),"expires":clock+12})

# The grenade leaves the hand: aim pitch plus loft (bots solve the elevation for their
# target), released at the hand's position and carrying part of the thrower's motion.
func throw_grenade(actor: Combatant) -> void:
	var elevation:=ThrowTimeline.launch_pitch(actor.pitch+actor.recoil)
	if actor.throw_range>0:elevation=ThrowTimeline.elevation_for(actor.throw_range,actor.throw_rise)
	var basis:=Basis.from_euler(Vector3(elevation,actor.yaw,0))
	var hand:=actor.eye()+Basis.from_euler(Vector3(actor.pitch,actor.yaw,0))*ThrowTimeline.HAND
	var grenade:=GameGrenade.new();add_child(grenade)
	var fuse_end:=actor.throw_started+ThrowTimeline.FRAG_FUSE if actor.throw_kind==0 else clock+ThrowTimeline.SMOKE_FUSE
	var inherited:=Vector3(actor.velocity.x,0,actor.velocity.z)*ThrowTimeline.INHERIT
	grenade.configure(actor.slot.id,actor.throw_kind,fuse_end,GameGrenade.clear_point(get_world_3d().direct_space_state,actor.eye(),hand),basis*Vector3.FORWARD*ThrowTimeline.SPEED+inherited)
	grenades.append(grenade)
	grenade.bounced.connect(func(point:Vector3, speed:float):effects.sound("grenade_bounce",point,clampf(speed*.055,.12,.65)))
	effects.sound("grenade_throw",actor.eye(),.5,actor.slot.is_human)
	if actor.throw_kind==0:actor.frags-=1
	else:actor.smokes-=1

func detonate(grenade: GameGrenade) -> void:
	var position := grenade.global_position
	if grenade.kind==1:
		effects.sound("smoke_hiss",position,.7)
		var cloud:=effects.smoke_cloud(position+Vector3.UP*1.7)
		smoke_clouds.append({"node":cloud,"position":cloud.global_position,"expires":clock+10})
	else:
		effects.explosion(position,.7,.6)
		blast(position,6,120,grenade.source,&"frag")

# Radial damage: full inside a third of the radius, linear to zero at the edge.
# Soldiers need a clear line from the blast; barrels, cars and glass in range are
# told to react (props occlude by the same rule, ignoring their own collider).
func blast(position: Vector3, radius: float, max_damage: float, source: int, weapon: StringName, origin: Destructible = null) -> void:
	var inner:=radius/3.0
	for actor in actors:
		var distance := actor.global_position.distance_to(position)
		if actor.alive and distance<radius and visible_between(position+Vector3.UP*.2,actor.global_position+Vector3.UP*.8,false):
			queue_damage(source,actor,max_damage if distance<=inner else max_damage*(radius-distance)/(radius-inner),weapon,false)
	for prop in destructibles:
		if prop==origin or prop.state==Destructible.State.DONE or prop.state==Destructible.State.EXPLODING:continue
		var distance:=prop.center.distance_to(position)
		if distance>=radius or not visible_between(position,prop.center,false,[prop.body.get_rid()]):continue
		prop.blast_hit(distance,max_damage if distance<=inner else max_damage*(radius-distance)/(radius-inner),source)

func queue_explosion(prop: Destructible, at: float) -> void:
	explosion_sequence+=1
	explosion_queue.append({"at":at,"seq":explosion_sequence,"prop":prop})

func activate(prop: Destructible) -> void:
	if not active_destructibles.has(prop):active_destructibles.append(prop)

func deactivate(prop: Destructible) -> void:
	active_destructibles.erase(prop)

# Props' timers, then every explosion that has come due. Blasts queue damage that
# is resolved immediately; chained props detonate on a later tick.
func step_destructibles() -> void:
	if active_destructibles.is_empty() and explosion_queue.is_empty():return
	for prop in active_destructibles.duplicate():prop.tick(clock)
	var fired:=false
	for entry in explosion_queue.duplicate():
		if float(entry.at)>clock:continue
		explosion_queue.erase(entry);entry.prop.detonate();fired=true
	if fired:resolve_damage()

func nearest_cache(position: Vector3) -> Vector3:
	var best := arena.definition.ammo_caches[0]
	for p in arena.definition.ammo_caches:
		if position.distance_squared_to(p)<position.distance_squared_to(best):best=p
	return best+Vector3(0,0,2)

func supply(actor: Combatant) -> void:
	for i in arena.definition.ammo_caches.size():
		if actor.global_position.distance_to(arena.definition.ammo_caches[i])>2.5:continue
		var key := "%d:%d"%[actor.slot.id,i]
		if supply_times.get(key,-100.0)+20>clock:continue
		var restored:=false
		for runtime in actor.weapons:
			restored=restored or runtime.reserve<runtime.capacity*3
			runtime.reserve=runtime.capacity*3
		if restored and actor.slot.is_human:effects.sound("reload",actor.eye(),.35,true)
		supply_times[key]=clock

# --- dropped weapons -----------------------------------------------------------

# A weapon left on the ground with the rounds it still had: the player can swap for it, or
# walk over it for ammunition (all of its rounds into the same gun; one magazine for each
# other gun carried, once per dropped weapon).
func drop_weapon(actor: Combatant, runtime: WeaponRuntime) -> void:
	while pickups.size()>=MAX_PICKUPS:remove_pickup(pickups[0])
	var entry:={"weapon":runtime.definition.id,"attachments":runtime.attachments.duplicate(),"ammo":runtime.ammo,"reserve":runtime.reserve,
		"position":actor.global_position+Vector3.UP*.3,"expires":clock+PICKUP_LIFETIME,"node":null,"scavenged":[],"dropper":life_key(actor)}
	if DisplayServer.get_name()!="headless":entry.node=SoldierFactory.drop_gun(self,actor,runtime)
	pickups.append(entry)

func life_key(actor: Combatant) -> String:
	return "%d:%d"%[actor.slot.id,actor.slot.life_id]

func pickup_position(entry: Dictionary) -> Vector3:
	return entry.node.global_position if is_instance_valid(entry.node) else Vector3(entry.position)

func remove_pickup(entry: Dictionary) -> void:
	if is_instance_valid(entry.node):entry.node.queue_free()
	pickups.erase(entry)

func in_reach(actor: Combatant, entry: Dictionary) -> bool:
	return pickup_position(entry).distance_to(actor.global_position+Vector3.UP*.3)<=PICKUP_REACH

func tick_pickups() -> void:
	for entry in pickups.duplicate():
		if clock>=float(entry.expires):remove_pickup(entry)
	var player:=actors[0]
	if not player.alive:return
	# A gun the player swapped away in this life gives nothing back (no swap-and-scavenge loop).
	for entry in pickups.duplicate():
		if in_reach(player,entry) and entry.dropper!=life_key(player):scavenge(player,entry)

func scavenge(actor: Combatant, entry: Dictionary) -> void:
	var taken:=0
	for runtime in actor.weapons:
		var room:=runtime.capacity*3-runtime.reserve
		var left:=int(entry.ammo)+int(entry.reserve)
		if room<=0 or left<=0:continue
		if runtime.definition.id==entry.weapon:
			var rounds:=mini(room,left);runtime.reserve+=rounds;taken+=rounds
			var from_reserve:=mini(rounds,int(entry.reserve));entry.reserve=int(entry.reserve)-from_reserve;entry.ammo=int(entry.ammo)-(rounds-from_reserve)
		elif not entry.scavenged.has(runtime.definition.id):
			var rounds:=mini(room,runtime.capacity);runtime.reserve+=rounds;taken+=rounds;entry.scavenged.append(runtime.definition.id)
	if taken>0:
		effects.sound("reload",actor.eye(),.4,actor.slot.id==0)
		if actor.slot.id==0:ammo_scavenged.emit(taken)
	# A gun the player already carries is only its ammunition: once that is taken it is gone.
	var carried:=false
	for runtime in actor.weapons:carried=carried or runtime.definition.id==entry.weapon
	if carried and int(entry.ammo)+int(entry.reserve)<=0:remove_pickup(entry)

# The nearest dropped weapon in reach that the actor does not already carry.
func swap_candidate(actor: Combatant) -> Dictionary:
	var best:={};var nearest:=PICKUP_REACH
	for entry in pickups:
		var carried:=false
		for runtime in actor.weapons:carried=carried or runtime.definition.id==entry.weapon
		var distance:=pickup_position(entry).distance_to(actor.global_position+Vector3.UP*.3)
		if not carried and distance<=nearest:best=entry;nearest=distance
	return best

# Takes the dropped weapon into its own slot (sidearms for the sidearm) and leaves the one it
# replaces on the ground, with its rounds.
func swap_weapon(actor: Combatant, entry: Dictionary) -> void:
	var definition:WeaponDefinition=catalog.weapons[str(entry.weapon)]
	var slot:=1 if definition.category=="sidearm" else 0
	var fresh:=WeaponRuntime.new();var attachments:Array[String]=[];attachments.assign(entry.attachments)
	fresh.configure(definition,attachments);fresh.ammo=mini(int(entry.ammo),fresh.capacity);fresh.reserve=int(entry.reserve)
	remove_pickup(entry)
	actor.weapon().cancel_reload()
	drop_weapon(actor,actor.weapons[slot])
	actor.weapons[slot]=fresh;actor.selected_weapon=slot
	fresh.equip(clock);actor.refresh_gun()
	effects.sound("switch",actor.eye(),.8,actor.slot.id==0)
	if actor.slot.id==0:weapon_changed.emit()

func claim_cover(actor: Combatant, threat: Vector3) -> Vector3:
	var best := actor.global_position
	var distance := INF
	for point in arena.definition.cover_points:
		var key := str(point)
		if cover_claims.has(key) and cover_claims[key].until>clock and cover_claims[key].owner!=actor.slot.id:continue
		var candidate := actor.global_position.distance_squared_to(point)
		if candidate<distance and not visible_between(point+Vector3.UP*.9,threat,false):best=point;distance=candidate
	cover_claims[str(best)]={"owner":actor.slot.id,"until":clock+2.5}
	return best
