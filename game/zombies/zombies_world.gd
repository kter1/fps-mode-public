class_name ZombiesWorld
extends MatchWorld

var open_zones: Dictionary = {0:true}
var barriers: Array[ZombieBarrier] = []
var stations: Array[ZombieStation] = []
var box: ZombieMysteryBox
var box_rng:=RandomNumberGenerator.new()
var loot_rng:=RandomNumberGenerator.new()
var spawn_rng:=RandomNumberGenerator.new()
var fx_rng:=RandomNumberGenerator.new()
var downed_until := 0.0
var was_downed := false
var revive_protection_until := 0.0
var spawn_at := 0.0
var interactions: ZombieInteractions
var projectiles: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var drop_at := 0.0
var rules: Dictionary
var ended_sent := false
var run_stats: Dictionary = {}
var energy_beams: Array[Dictionary] = []
var zombie_voices: Array[AudioStreamPlayer3D] = []
var zombie_voice_index := 0

func configure(_source: Catalog, map_id: String, _loadout: LoadoutDefinition, level: int, random_seed: int, auto := false) -> void:
	mode_id="zombies";catalog=ZombiesCatalog.new();difficulty=level;seed_value=random_seed;automation=auto
	rules=JSON.parse_string(FileAccess.get_file_as_string("res://content/data/zombies/rules.json"))
	rng.seed=random_seed;spawn_rng.seed=random_seed+101;box_rng.seed=random_seed+211;loot_rng.seed=random_seed+307;fx_rng.seed=random_seed+401
	process_mode=Node.PROCESS_MODE_PAUSABLE;NavigationServer3D.map_set_use_async_iterations(get_world_3d().navigation_map,false)
	arena=load(MapCatalog.scene_path(map_id)).instantiate();add_child(arena)
	destructibles=arena.destructibles
	for prop in destructibles:prop.world=self
	effects=MatchEffects.new();add_child(effects);effects.configure_audio("blackout" if map_id=="dead_current" else "airport")
	for i in int(rules.pool_cap)+1:
		var slot:=ActorSlot.new();slot.id=i;slot.team=0 if i==0 else 1;slot.is_human=i==0;slot.callsign="YOU" if i==0 else "INFECTED %02d"%i;slot.loadout=LoadoutDefinition.new();slots.append(slot)
		var actor: Combatant=ZombiePlayer.new() if i==0 else ZombieActor.new();add_child(actor);actor.setup(slot,catalog);actors.append(actor)
		if i==0:actor.respawn(MapCatalog.vec3(arena.definition.zombies.player_start),0,catalog)
	for data: Dictionary in arena.definition.zombies.barriers:
		var barrier:=ZombieBarrier.new();add_child(barrier);barrier.configure(data);barriers.append(barrier)
	for data: Dictionary in arena.definition.zombies.doors:
		var station:=ZombieStation.new();add_child(station);station.configure(data)
		var link:=NavigationLink3D.new();link.bidirectional=true;link.enabled=false
		var normal:=Basis(Vector3.UP,station.rotation.y)*Vector3(0,0,2.1)
		link.start_position=station.position+normal;link.end_position=station.position-normal
		add_child(link);station.link=link;stations.append(station)
	for data: Dictionary in arena.definition.zombies.stations:
		var station:=ZombieStation.new();add_child(station);station.configure(data);stations.append(station)
	box=ZombieMysteryBox.new();add_child(box);box.configure(self,arena.definition.zombies.box_sites)
	mode=ZombiesMode.new();mode.begin(self);mode.points=int(rules.starting_points)
	interactions=ZombieInteractions.new();interactions.world=self
	if DisplayServer.get_name()!="headless":
		for i in 12:
			var voice:=AudioStreamPlayer3D.new();voice.max_distance=40;voice.unit_size=4;add_child(voice);zombie_voices.append(voice)
	call_deferred("finish_loading")

func finish_loading() -> void:
	await get_tree().physics_frame;await get_tree().physics_frame
	var map:=get_world_3d().navigation_map
	NavigationServer3D.map_set_active(map,true);NavigationServer3D.map_force_update(map)
	var deadline:=Time.get_ticks_msec()+15000
	while NavigationServer3D.map_get_iteration_id(map)==0:
		if Time.get_ticks_msec()>deadline:push_error("Zombies navigation did not synchronize");return
		await get_tree().physics_frame
	ready_for_play=true

func _physics_process(delta: float) -> void:
	if not ready_for_play:return
	if mode.finished:
		if not ended_sent:ended_sent=true;ended.emit()
		return
	clock+=delta;ticks+=1;mode.tick(delta)
	var player:=actors[0] as ZombiePlayer
	if was_downed and clock>=downed_until:
		was_downed=false;player.health=100;mode.say("SECOND WIND — PERKS LOST");cue("revive",player.eye())
	player.command=player_command
	if clock<downed_until:player.command=ActorCommand.new();player.command.crouch=true
	interactions.capture(delta)
	spawn_tick()
	player.simulate_movement(delta,self)
	for i in range(1,actors.size()):actors[i].simulate_movement(delta,self)
	if clock>=downed_until and not interactions.blocks_fire:combat(player)
	for grenade: GameGrenade in grenades.duplicate():
		grenade.step(delta)
		if clock>=grenade.detonate_at:detonate(grenade);grenades.erase(grenade);grenade.queue_free()
	projectile_tick(delta);trap_tick(delta);step_destructibles();resolve_damage()
	interactions.commit()
	box.tick(delta);drop_tick()
	for corpse: Dictionary in corpses.duplicate():
		if corpse.has("velocity"):
			var velocity: Vector3=corpse.velocity;velocity.y-=delta*12
			var from: Vector3=corpse.node.position;var to:=from+velocity*delta
			if to.y<.2:to.y=.2;velocity.y=0;velocity.x=move_toward(velocity.x,0,delta*5);velocity.z=move_toward(velocity.z,0,delta*5)
			if visible_between(from+Vector3.UP*.2,to+Vector3.UP*.2,false):corpse.node.position=to
			else:velocity=Vector3.ZERO
			corpse.velocity=velocity
		if clock>=float(corpse.expires):corpse.node.queue_free();corpses.erase(corpse)
	for beam: Dictionary in energy_beams.duplicate():
		if clock>=float(beam.expires):beam.node.queue_free();energy_beams.erase(beam)
	effects.tick(clock);effects.audio.set_listener_health(player.health/maxf(player.max_health,1)*100,player.alive)
	mode.check_clear(living_count())
	player_command.fire_pressed=false;player_command.reload_pressed=false;player_command.jump_pressed=false;player_command.melee_pressed=false;player_command.interact_pressed=false;player_command.requested_throwable=-1;player_command.requested_weapon_slot=-1
	if mode.finished and not ended_sent:ended_sent=true;ended.emit()

func living_count() -> int:
	var count:=0
	for i in range(1,actors.size()):
		if actors[i].alive:count+=1
	return count

func spawn_tick() -> void:
	if mode.intermission>0 or mode.remaining_to_spawn<=0 or clock<spawn_at:return
	if living_count()>=mini(int(rules.pool_cap),6+2*(mode.round_number-1)):return
	var available: Array[ZombieBarrier]=[]
	for barrier in barriers:
		if not open_zones.has(barrier.zone) or barrier.occupants.size()>=3:continue
		var camera:=get_viewport().get_camera_3d()
		if camera!=null and camera.is_position_in_frustum(barrier.outside+Vector3.UP) and visible_between(actors[0].eye(),barrier.outside+Vector3.UP,false):continue
		available.append(barrier)
	if available.is_empty():return
	var enemy: ZombieActor
	for i in range(1,actors.size()):
		if not actors[i].alive:enemy=actors[i];break
	if enemy==null:return
	var barrier: ZombieBarrier=available[spawn_rng.randi_range(0,available.size()-1)]
	var queue_index:=barrier.occupants.size()
	if not barrier.reserve(enemy.slot.id):return
	var point:=barrier.outside+barrier.global_basis*Vector3((queue_index-1)*.9,0,queue_index*.5)
	var low:=1.3 if mode.round_number<4 else (2.0 if mode.round_number<7 else 2.8)
	var high:=2.0 if mode.round_number<4 else (2.8 if mode.round_number<7 else (3.8 if mode.round_number<11 else 4.4))
	enemy.activate(point,clock,ZombiesMode.enemy_health(mode.round_number),spawn_rng.randf_range(low,high),barrier)
	mode.remaining_to_spawn-=1;spawn_at=clock+maxf(.45,2-.08*(mode.round_number-1))

func recover_enemy(enemy: ZombieActor) -> void:
	if enemy.global_position.distance_to(actors[0].global_position)<5:return
	var camera:=get_viewport().get_camera_3d()
	if camera!=null and camera.is_position_in_frustum(enemy.aim_target()) and visible_between(actors[0].eye(),enemy.aim_target(),false):return
	for barrier in barriers:
		if not open_zones.has(barrier.zone) or barrier.inside.distance_to(actors[0].global_position)<8:continue
		if camera!=null and camera.is_position_in_frustum(barrier.inside) and visible_between(actors[0].eye(),barrier.inside+Vector3.UP,false):continue
		enemy.global_position=barrier.inside;enemy.state="PURSUE";enemy.last_progress_at=clock;enemy.next_path_at=0;enemy.route.clear();enemy.route_index=0;return

func owns(id: String) -> bool:
	for runtime: ZombieWeaponRuntime in actors[0].weapons:
		if runtime.base_id==id:return true
	return false

func give_weapon(id: String) -> bool:
	if owns(id):return false
	var player:=actors[0] as ZombiePlayer
	var runtime: ZombieWeaponRuntime=catalog.runtime(id);runtime.recompute(mode.perks)
	if player.weapons.size()<2:player.weapons.append(runtime);player.selected_weapon=player.weapons.size()-1
	else:player.weapons[player.selected_weapon]=runtime
	player.action_until=clock+.35;player.refresh_gun();weapon_changed.emit();return true

func queue_damage(source: int, victim: Combatant, amount: float, weapon: StringName, headshot: bool) -> void:
	sequence+=1
	super(source,victim,amount,weapon,headshot)

func resolve_damage() -> void:
	var pending:=damage_queue.duplicate();damage_queue.clear()
	for event: DamageEvent in pending:
		if event.victim_slot<0 or event.victim_slot>=actors.size():continue
		var victim:=actors[event.victim_slot]
		if not victim.alive or event.victim_life!=victim.slot.life_id or clock<victim.protected_until:continue
		if event.victim_slot==0 and (qa_protect_player or clock<revive_protection_until):continue
		if event.source_slot>=0 and event.source_slot!=event.victim_slot and slots[event.source_slot].team==victim.slot.team:continue
		var is_enemy:=victim is ZombieActor
		var lethal_effect: bool=event.weapon_id in [&"nuke",&"trap",&"z_thunder_kill"] or (event.source_slot==0 and clock<mode.insta_until)
		victim.health-=maxf(victim.health,event.amount) if lethal_effect and is_enemy else event.amount
		victim.last_damage_at=clock
		if is_enemy:
			var enemy:=victim as ZombieActor
			if victim.health<=0:die(victim,event)
			else:
				if event.weapon_id==&"frag" and event.leg_damage>=float(rules.crawler_threshold) and enemy.become_crawler():sever_legs(enemy);cue("leg_break",enemy.global_position)
				if event.source_slot==0 and not str(event.weapon_id).begins_with("z_") and event.weapon_id not in [&"frag",&"knife",&"trap",&"nuke"] and enemy.hit_awards<5:
					enemy.hit_awards+=1;mode.award(10)
			if event.source_slot==0:player_hit.emit(event.headshot,not victim.alive)
		else:
			effects.sound("hurt",victim.eye(),.6,true)
			if event.source_slot>0:player_damaged.emit(actors[event.source_slot].global_position)
			if victim.health<=0:die(victim,event)

func die(victim: Combatant, event: DamageEvent) -> void:
	if victim.slot.id==0:
		if "revive" in mode.perks:
			mode.perks.clear();(victim as ZombiePlayer).apply_perks(mode.perks);victim.health=1;downed_until=clock+3;revive_protection_until=clock+5;victim.protected_until=clock+5;was_downed=true
			player_command=ActorCommand.new();mode.say("SECOND WIND — GETTING BACK UP",3);cue("down",victim.eye());return
		victim.alive=false;victim.health=0;mode.finished=true;slots[0].deaths+=1;return
	var enemy:=victim as ZombieActor
	if enemy.barrier!=null:enemy.barrier.release(enemy.slot.id);enemy.barrier=null
	if DisplayServer.get_name()!="headless":make_corpse(enemy)
	enemy.deactivate();enemy.state="DEAD"
	mode.kills+=1;slots[0].kills+=1
	if event.headshot:mode.headshots+=1
	if event.weapon_id not in [&"trap",&"nuke"]:
		mode.award(130 if event.weapon_id==&"knife" else (50 if event.weapon_id==&"frag" or str(event.weapon_id).begins_with("z_") else (100 if event.headshot else 60)))
		maybe_drop(enemy.global_position)
	cue("z_death",enemy.global_position,.2)

func knife(actor: Combatant) -> void:
	var best: Combatant;var distance:=2.4
	for i in range(1,actors.size()):
		var enemy:=actors[i]
		if not enemy.alive:continue
		var offset:=enemy.aim_target()-actor.eye();var d:=offset.length()
		if d<distance and actor.aim_direction().angle_to(offset.normalized())<deg_to_rad(40) and visible_between(actor.eye(),enemy.aim_target(),false):best=enemy;distance=d
	if best!=null:queue_damage(0,best,150,&"knife",false);cue("knife_hit",best.global_position)

func detonate(grenade: GameGrenade) -> void:
	if grenade.kind==1:return
	effects.explosion(grenade.global_position,.7,.6);blast(grenade.global_position,float(rules.frag_radius),float(rules.frag_damage),grenade.source,&"frag")

func blast(at: Vector3, radius: float, damage: float, source: int, weapon: StringName, origin: Destructible = null) -> void:
	for actor in actors:
		if not actor.alive:continue
		var target:=actor.aim_target();var distance:=actor.global_position.distance_to(at)
		if distance>=radius or not visible_between(at+Vector3.UP*.05,target,false):continue
		var amount:=damage if distance<=radius/3 else damage*(radius-distance)/(radius-radius/3)
		if actor.slot.id==0 and weapon==&"frag":amount*=120.0/350.0
		queue_damage(source,actor,amount,weapon,false)
		if actor is ZombieActor and weapon==&"frag" and at.y<=actor.global_position.y+1.2 and visible_between(at+Vector3.UP*.05,actor.global_position+Vector3.UP*.3,false):damage_queue.back().leg_damage=amount
	for prop in destructibles:
		if prop==origin or prop.state in [Destructible.State.DONE,Destructible.State.EXPLODING]:continue
		var distance:=prop.center.distance_to(at)
		if distance<radius and visible_between(at,prop.center,false,[prop.body.get_rid()]):prop.blast_hit(distance,damage*(1-distance/radius),source)

func fire(actor: Combatant, runtime: WeaponRuntime) -> void:
	var id:=str(runtime.definition.id)
	if not id.begins_with("z_"):super(actor,runtime);return
	var upgraded: bool=runtime.upgraded
	var start:=actor.eye();var forward:=actor.aim_direction()
	cue(id,start,.7)
	match id:
		"z_ray":
			if projectiles.size()>=32:return
			var node:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.08;sphere.height=.16;node.mesh=sphere;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.material_override=ZombieVisual.finish(Color("5dff9a"));add_child(node);node.global_position=start
			projectiles.append({"node":node,"position":node.global_position,"velocity":forward*35,"expires":clock+3,"damage":1600.0 if upgraded else 800.0,"splash":600.0 if upgraded else 300.0})
		"z_thunder":
			var reach:=12.0 if upgraded else 9.0;var kill_range:=8.0 if upgraded else 6.0
			for i in range(1,actors.size()):
				var enemy:=actors[i] as ZombieActor
				if not enemy.alive:continue
				var offset:=enemy.aim_target()-start
				if offset.length()>reach or forward.angle_to(offset.normalized())>deg_to_rad(35) or not visible_between(start,enemy.aim_target(),false):continue
				queue_damage(0,enemy,400,&"z_thunder_kill" if offset.length()<kill_range else &"z_thunder",false)
				enemy.velocity=offset.normalized()*9+Vector3.UP*3 if enemy.barrier==null else Vector3.ZERO;enemy.stagger_until=clock+1.2
			for i in 12:effects.tracer(start,start+forward*reach+Vector3(sin(i)*2,cos(i)*2,0),false)
		"z_arc":
			var hit:=ray(start,start+forward*24,actor)
			var current: ZombieActor
			if hit.has("collider") and hit.collider.has_meta("actor") and hit.collider.get_meta("actor") is ZombieActor:current=hit.collider.get_meta("actor")
			var visited: Array[int]=[];var from:=start
			while current!=null and visited.size()<(8 if upgraded else 5):
				visited.append(current.slot.id);queue_damage(0,current,1800 if upgraded else 1200,&"z_arc",false);energy_beam(from,current.aim_target(),Color("7ccfff"));from=current.aim_target()
				var next: ZombieActor;var best:=4.0
				for i in range(1,actors.size()):
					var enemy:=actors[i] as ZombieActor
					if not enemy.alive or i in visited:continue
					var distance:=from.distance_to(enemy.aim_target())
					if distance<best and visible_between(from,enemy.aim_target(),false):next=enemy;best=distance
				current=next

func projectile_tick(delta: float) -> void:
	for shot: Dictionary in projectiles.duplicate():
		var next: Vector3=shot.position+shot.velocity*delta
		var hit:=ray(shot.position,next,actors[0])
		if not hit.is_empty():
			var point: Vector3=hit.position
			var direct: Combatant=hit.collider.get_meta("actor") if hit.collider.has_meta("actor") else null
			for actor in actors:
				if not actor.alive:continue
				var distance:=actor.aim_target().distance_to(point)
				var amount: float=shot.damage if actor==direct else 0.0
				if distance<1.5 and visible_between(point+Vector3.UP*.03,actor.aim_target(),false):amount+=float(shot.splash)*(1-distance/1.5)
				if actor.slot.id==0:amount=minf(30,amount)
				if amount>0:queue_damage(0,actor,amount,&"z_ray",false)
			effects.explosion(point,.25,.12);remove_projectile(shot)
		elif clock>=float(shot.expires):remove_projectile(shot)
		else:shot.position=next;shot.node.global_position=next

func remove_projectile(shot: Dictionary) -> void:
	shot.node.queue_free();projectiles.erase(shot)

func trap_tick(delta: float) -> void:
	for station in stations:
		if station.kind!="trap" or station.active_until<=clock or clock<station.active_until-8:continue
		for actor in actors:
			if not actor.alive or actor.global_position.distance_to(station.global_position)>4:continue
			queue_damage(-1,actor,50*delta if actor.slot.id==0 else actor.health,&"trap",false)
		if ticks%6==0:effects.tracer(station.global_position+Vector3.UP*2,station.global_position+Vector3(fx_rng.randf_range(-3,3),.2,fx_rng.randf_range(-3,3)),true)

func maybe_drop(at: Vector3) -> void:
	if mode.drops_this_round>=3 or drops.size()>=4 or clock<drop_at or loot_rng.randf()>=.08:return
	var weights: Array[String]=[]
	for pair in [["ammo",30],["double",25],["insta",20],["nuke",10],["carpenter",15]]:
		for i in int(pair[1]):weights.append(pair[0])
	spawn_drop(weights[loot_rng.randi_range(0,weights.size()-1)],at);mode.drops_this_round+=1;drop_at=clock+8

func spawn_drop(kind: String, at: Vector3) -> void:
	var node:=Node3D.new();add_child(node);node.position=at+Vector3.UP*.8
	match kind:
		"ammo":
			for i in 3:ZombieVisual.part(node,Vector3(.12,.4,.12),Vector3((i-1)*.17,0,0),Color("d3ba6a"),true)
		"double":
			for i in 2:ZombieVisual.part(node,Vector3(.25,.35,.09),Vector3((i-.5)*.3,0,0),Color("dfb34e"),true)
		"insta":
			ZombieVisual.part(node,Vector3(.35,.4,.3),Vector3.ZERO,Color("d7d3b5"),true)
			for x in [-.08,.08]:ZombieVisual.part(node,Vector3(.075,.09,.05),Vector3(x,.05,.15),Color("302f29"))
		"carpenter":
			ZombieVisual.part(node,Vector3(.09,.5,.09),Vector3(0,-.08,0),Color("926b40"))
			ZombieVisual.part(node,Vector3(.45,.15,.17),Vector3(0,.2,0),Color("b1c0b0"))
		_:
			for i in 3:ZombieVisual.part(node,Vector3(.22,.3,.09),Vector3(sin(i*TAU/3)*.15,cos(i*TAU/3)*.15,0),Color("c9bc47"))
	ZombieObjects.label(node,kind.to_upper(),Vector3(0,.4,0),Color("f1e8b5"),32)
	drops.append({"kind":kind,"node":node,"expires":clock+20})

func drop_tick() -> void:
	for drop: Dictionary in drops.duplicate():
		drop.node.rotation.y+=.025
		drop.node.visible=clock<float(drop.expires)-5 or ticks%20<12
		if clock>=float(drop.expires):drop.node.queue_free();drops.erase(drop)
		elif actors[0].alive and actors[0].global_position.distance_to(drop.node.global_position)<1.5:collect(str(drop.kind));drop.node.queue_free();drops.erase(drop)

func collect(kind: String) -> void:
	mode.say({"ammo":"MAX AMMO","double":"DOUBLE POINTS","insta":"INSTA-KILL","nuke":"NUKE","carpenter":"CARPENTER"}.get(kind,kind));cue("pickup",actors[0].eye())
	match kind:
		"ammo":
			for runtime: ZombieWeaponRuntime in actors[0].weapons:runtime.refill()
			actors[0].frags=mini(4,maxi(2,actors[0].frags))
		"double":mode.double_until=clock+30
		"insta":mode.insta_until=clock+30
		"carpenter":
			for barrier in barriers:barrier.carpenter()
			mode.award(200)
		"nuke":
			for i in range(1,actors.size()):
				if actors[i].alive:queue_damage(-1,actors[i],actors[i].health,&"nuke",false)
			mode.award(400);resolve_damage()

func make_corpse(enemy: ZombieActor) -> void:
	var body:=ZombieVisual.new();add_child(body);body.build(enemy.variant);body.global_transform=enemy.global_transform;body.pose(clock,enemy.crawling,0,false,false)
	body.rotation.z+=PI*.5;body.position.y=.2
	if corpses.size()>=8:corpses.pop_front().node.queue_free()
	corpses.append({"node":body,"expires":clock+12,"velocity":enemy.velocity})

func sever_legs(enemy: ZombieActor) -> void:
	if DisplayServer.get_name()=="headless":return
	for side in [-1,1]:
		var limb: Node3D=(enemy.visual as ZombieVisual).detached_leg(side);add_child(limb);limb.global_position=enemy.global_position+Vector3(side*.2,.15,0);limb.rotation=Vector3(PI*.5,side*.7,.3)
		if corpses.size()>=8:corpses.pop_front().node.queue_free()
		corpses.append({"node":limb,"expires":clock+8})

func cue(id: String, at: Vector3, volume := .5) -> void:
	if zombie_voices.is_empty():return
	var path:="res://content/audio/zombies/"+id+".wav"
	if not ResourceLoader.exists(path):return
	var voice:=zombie_voices[zombie_voice_index%zombie_voices.size()];zombie_voice_index+=1
	voice.stop();voice.stream=load(path);voice.position=at;voice.volume_db=linear_to_db(maxf(volume,.001));voice.play()

func energy_beam(from: Vector3, to: Vector3, color: Color) -> void:
	if DisplayServer.get_name()=="headless" or energy_beams.size()>=32:return
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var forward:=(to-from).normalized();var side:=forward.cross(Vector3.UP).normalized()*.025
	if side.length()<.01:side=Vector3.RIGHT*.025
	var points: Array[Vector3]=[from]
	for i in range(1,6):points.append(from.lerp(to,i/6.0)+Vector3(fx_rng.randf_range(-.12,.12),fx_rng.randf_range(-.12,.12),fx_rng.randf_range(-.12,.12)))
	points.append(to)
	for i in points.size()-1:
		for point in [points[i]-side,points[i]+side,points[i+1]+side,points[i]-side,points[i+1]+side,points[i+1]-side]:surface.add_vertex(point)
	var node:=MeshInstance3D.new();node.mesh=surface.commit();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=color;material.cull_mode=BaseMaterial3D.CULL_DISABLED;node.material_override=material
	add_child(node);energy_beams.append({"node":node,"expires":clock+.16})
