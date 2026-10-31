extends SceneTree

var results: Array[Dictionary] = []
var suite := "core"
var only_map := ""
var catalog: Catalog
var intentional_failure := false

class RejectingSpawns extends SpawnDirector:
	var attempts:=0
	var exposed:=false
	func select(_actor:Combatant,_world:Object,allow_exposed:=false) -> Variant:
		attempts+=1;exposed=allow_exposed;return null

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):suite=arg.trim_prefix("--suite=")
		if arg=="--self-test-failure":intentional_failure=true
		if arg.begins_with("--map="):only_map=arg.trim_prefix("--map=")
	call_deferred("run")

func check_that(condition: bool, name: String, detail := "") -> void:
	results.append({"name":name,"passed":condition,"detail":detail})
	print("PASS " if condition else "FAIL ",name," ",detail)

func runtime(id := "ar_a4", attachments: Array[String] = []) -> WeaponRuntime:
	var result:=WeaponRuntime.new();result.configure(catalog.weapons[id],attachments);return result

func run() -> void:
	catalog=Catalog.new()
	if suite=="content":content_tests()
	elif suite=="core":core_tests()
	elif suite=="local-multiplayer":await load("res://tests/suites/local_multiplayer.gd").run(self)
	elif suite=="audio":await load("res://tests/suites/audio.gd").run(self)
	elif suite=="zombies":await load("res://tests/suites/zombies.gd").run(self)
	elif suite=="campaign":await load("res://tests/suites/campaign.gd").run(self)
	elif suite=="prone":
		var world:=MatchWorld.new();root.add_child(world)
		world.configure(catalog,"airport",catalog.starter_loadouts()[0],1,1201,true)
		for i in 240:
			if world.ready_for_play:break
			await physics_frame
		await movement_and_trace_tests(world,"airport")
		world.free()
	elif suite=="traversal":
		if only_map in MapCatalog.ids_for_mode("tdm"):await traversal_tests(only_map)
		else:check_that(false,"traversal_requires_registered_map",only_map)
	elif suite=="integration":await integration_tests()
	else:check_that(false,"unknown_suite",suite)
	if intentional_failure:check_that(false,"intentional_harness_failure","Expected nonzero exit-code verification")
	var failed:=results.filter(func(result:Dictionary):return not result.passed).size()
	var report:={"suite":suite,"passed":results.size()-failed,"failed":failed,"tests":results,"engine":Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute("res://.artifacts/reports")
	var file:=FileAccess.open("res://.artifacts/reports/"+suite+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("TEST_RESULT ",JSON.stringify(report))
	quit(0 if failed==0 else 1)

# Content checks live in one suite file per domain so they can evolve separately.
func content_tests() -> void:
	for domain in ["weapons","characters","maps"]:load("res://tests/suites/"+domain+".gd").run(self)

func core_tests() -> void:
	var defaults:=TeamDeathmatchMode.new()
	check_that(MatchWorld.TEAM_SIZE==8 and defaults.kill_limit==100 and defaults.remaining==600,"eight_v_eight_match_defaults")
	PlayerControls.install({})
	var pad_ok:=true
	for action in ["pad_fire","pad_aim","pad_sprint","pad_crouch","pad_switch","jump","reload","melee","frag","smoke","pause","scoreboard","forward","back","left","right"]:
		var has_pad:=false
		for event in InputMap.action_get_events(action):has_pad=has_pad or event is InputEventJoypadButton or event is InputEventJoypadMotion
		pad_ok=pad_ok and has_pad
	check_that(pad_ok,"ps5_controller_bindings_installed")
	var cross:=InputEventJoypadButton.new();cross.button_index=JOY_BUTTON_A;cross.pressed=true
	var circle:=InputEventJoypadButton.new();circle.button_index=JOY_BUTTON_B;circle.pressed=true
	check_that(cross.is_action_pressed("ui_accept") and circle.is_action_pressed("ui_cancel"),"ps5_cross_accepts_and_circle_backs_out_of_menus")
	var interact_key:=InputEventKey.new();interact_key.physical_keycode=KEY_E;interact_key.pressed=true
	check_that(interact_key.is_action_pressed("interact"),"keyboard_e_picks_up_weapons")
	var controls:=PlayerControls.new()
	var aim_key:=InputEventKey.new();aim_key.physical_keycode=KEY_C;aim_key.pressed=true
	controls.handle(aim_key,true,false)
	check_that(controls.wants_aim(true),"keyboard_c_toggles_aim")
	aim_key.pressed=false;controls.handle(aim_key,true,false)
	check_that(controls.wants_aim(true),"aim_persists_after_key_release")
	var fire_key:=InputEventKey.new();fire_key.physical_keycode=KEY_F;fire_key.pressed=true
	check_that(fire_key.is_action_pressed("fire_key"),"keyboard_f_is_alternate_fire")
	var fire_click:=InputEventMouseButton.new();fire_click.button_index=MOUSE_BUTTON_LEFT;fire_click.pressed=true;controls.handle(fire_click,true,false)
	check_that(controls.wants_aim(true) and fire_click.is_action_pressed("fire"),"trackpad_click_fires_while_aim_is_latched")
	fire_click.pressed=false;controls.handle(fire_click,true,false)
	check_that(not controls.firing(),"quick_click_release_does_not_leave_automatic_trigger_held")
	var secondary_click:=InputEventMouseButton.new();secondary_click.button_index=MOUSE_BUTTON_RIGHT;secondary_click.pressed=true;controls.handle(secondary_click,true,false)
	check_that(not controls.wants_aim(true),"secondary_click_toggles_aim_off")
	var shift:=InputEventKey.new();shift.keycode=KEY_SHIFT;shift.pressed=true
	check_that(shift.is_action_pressed("sprint"),"macos_modifier_without_physical_code_matches_sprint")
	controls.handle(aim_key,true,false);controls.handle(secondary_click,true,false);controls.handle(shift,true,true)
	check_that(controls.wants_sprint(true) and not controls.wants_aim(true),"sprint_toggle_cancels_aim")
	controls.reset();check_that(not controls.wants_aim(true) and not controls.wants_sprint(true),"menus_reset_aim_and_sprint_latches")
	controls.reset();controls.handle(circle,true,false)
	check_that(not controls.wants_crouch() and not controls.wants_prone(),"circle_waits_for_tap_or_hold")
	circle.pressed=false;controls.handle(circle,true,false)
	check_that(controls.wants_crouch() and not controls.wants_prone(),"circle_tap_crouches")
	circle.pressed=true;controls.handle(circle,true,false);controls.update_circle_hold(controls.circle_started+PlayerControls.PRONE_HOLD_MS)
	check_that(controls.wants_prone() and not controls.wants_crouch(),"circle_hold_goes_prone")
	circle.pressed=false;controls.handle(circle,true,false)
	check_that(controls.wants_prone(),"circle_hold_release_stays_prone")
	circle.pressed=true;controls.handle(circle,true,false);controls.update_circle_hold(controls.circle_started+PlayerControls.PRONE_HOLD_MS)
	check_that(not controls.wants_prone(),"second_circle_hold_stands")
	controls.reset()
	var prone_key:=InputEventKey.new();prone_key.physical_keycode=KEY_Z;prone_key.pressed=true
	controls.handle(prone_key,true,false)
	check_that(controls.wants_prone(),"z_toggles_prone")
	controls.reset();check_that(not controls.wants_prone(),"reset_clears_prone")
	var a:=runtime();a.ammo=1000
	var count:=0
	for i in 600:
		if a.try_fire(i/60.0,i==0,true):count+=1
	check_that(absi(count-117)<=1,"automatic_cadence_700rpm","shots="+str(count))
	check_that(a.try_fire(100,true,true) and not a.try_fire(100,false,true),"idle_has_no_overdue_burst")
	var pistol:=runtime("pistol_p9");count=0
	var holo:=WeaponRuntime.new();holo.configure(catalog.weapons.ar_a4,["holographic"])
	check_that(is_equal_approx(holo.magnification,1.5) and is_equal_approx(holo.ads_time,.24),"holographic_magnification_and_aim_time")
	check_that(not catalog.valid_attachments(catalog.weapons.ar_a4,["reflex","holographic"]),"one_optic_per_weapon")
	check_that(catalog.valid_attachments(catalog.weapons.ar_a4,[]),"bare_iron_sights_supported")
	for i in 120:
		if pistol.try_fire(i/60.0,i==0,true):count+=1
	check_that(count==1,"semi_auto_requires_new_press")
	check_that(pistol.try_fire(3,true,false),"latched_quick_click_fires")
	var magazine:=runtime();magazine.ammo=4
	check_that(magazine.start_reload(0),"reload_starts")
	magazine.tick(1);magazine.cancel_reload();magazine.tick(4)
	check_that(magazine.ammo==4 and magazine.reserve==90,"cancelled_reload_preserves_ammo")
	magazine.start_reload(5);magazine.tick(7.3)
	check_that(magazine.ammo==30 and magazine.reserve==64,"reload_transfers_exact_ammunition")
	magazine.ammo=0;magazine.start_reload(10);magazine.tick(12.2)
	check_that(magazine.ammo==0,"empty_reload_has_extra_duration")
	magazine.tick(12.6);check_that(magazine.ammo==30,"empty_reload_completes")
	var pump:=runtime("sg_p12");pump.ammo=0;pump.start_reload(0);pump.tick(.61);pump.cancel_reload()
	check_that(pump.ammo==1 and pump.reserve==23,"shell_reload_commits_completed_shells")
	var bolt:=runtime("sniper_s90");bolt.try_fire(0,true,false)
	check_that(not bolt.try_fire(.5,true,false) and bolt.try_fire(1.21,true,false),"bolt_cycle_blocks_early_shot")
	var equipped:=runtime();equipped.equip(0)
	check_that(not equipped.try_fire(.2,true,true),"equip_blocks_early_shot")
	equipped.tick(.36);check_that(equipped.try_fire(.36,true,true),"equip_unlocks_after_duration")
	var def:WeaponDefinition=catalog.weapons.ar_a4
	check_that(ceili(100/def.damage_at(10))==4,"a4_four_body_hits")
	check_that(ceili(100/def.damage_at(10,true))==2,"a4_two_headshots")
	check_that(catalog.weapons.sniper_s90.damage_at(10,true)>=100,"sniper_headshot_lethal")
	check_that(ceili(100/def.damage_at(100))==6,"range_falloff_six_body_hits")
	var extended:=runtime("ar_a4",["extended","compensator","reflex"])
	check_that(extended.capacity==42 and is_equal_approx(extended.reload_time,2.53),"attachment_capacity_reload")
	check_that(is_equal_approx(extended.ads_time,.27) and is_equal_approx(extended.recoil_scale,.8),"attachment_timing_recoil")
	check_that(not catalog.valid_attachments(def,["reflex","scope"]),"duplicate_slot_rejected")
	check_that(not catalog.valid_attachments(def,["reflex","compensator","fast","angled"]),"fourth_attachment_rejected")
	check_that(not catalog.valid_attachments(catalog.weapons.sg_p12,["extended"]),"incompatible_attachment_rejected")
	var independent:=runtime();extended.ammo=1
	check_that(independent.ammo==30 and def.capacity==30,"resources_and_actor_ammo_are_independent")
	var profile:=ProfileStore.new();profile.configure(catalog,"res://.artifacts/test-profile")
	profile.settings.fov=82.0;profile.settings.quality=2;profile.loadouts[2].primary=&"ar_k47"
	profile.settings.toggle_aim=false;profile.settings.toggle_sprint=true
	check_that(profile.save(),"profile_atomic_save")
	var restored:=ProfileStore.new();restored.configure(catalog,"res://.artifacts/test-profile")
	check_that(restored.loadouts.size()==5 and restored.loadouts[2].primary==&"ar_k47" and restored.settings.fov==82,"profile_loadouts_round_trip")
	check_that(restored.settings.quality==2,"profile_numeric_settings_round_trip")
	check_that(not restored.settings.toggle_aim and restored.settings.toggle_sprint,"profile_laptop_controls_round_trip")
	var corrupt:=FileAccess.open("res://.artifacts/test-profile/profile.json",FileAccess.WRITE);corrupt.store_string("broken");corrupt.close()
	var recovered:=ProfileStore.new();recovered.configure(catalog,"res://.artifacts/test-profile")
	check_that(recovered.loadouts.size()==5 and recovered.loadouts[0].primary==&"ar_a4","invalid_profile_recovers")
	var replay_actor:=Combatant.new();root.add_child(replay_actor)
	var replay_slot:=ActorSlot.new();replay_slot.loadout=catalog.starter_loadouts()[0];replay_slot.is_human=true
	replay_actor.setup(replay_slot,catalog);replay_actor.global_position=Vector3(1,0,0)
	var history:=ReplayHistory.new();var recorded:Array[Combatant]=[replay_actor]
	history.record(0,recorded);replay_actor.global_position=Vector3(9,0,0);history.record(.02,recorded)
	check_that(history.frames.size()==1 and history.frames[0].actors[0].position==Vector3(1,0,0),"replay_samples_are_immutable_and_rate_limited")
	history.record(.021,recorded,true)
	check_that(history.frames.size()==2 and history.frames.back().actors[0].position==Vector3(9,0,0),"replay_forces_fatal_tick_capture")
	for i in 100:history.record(1+i*.05,recorded,true)
	check_that(history.frames.size()==ReplayHistory.MAX_FRAMES and history.preceding(5.95,2.6).size()<=54,"replay_history_is_bounded")
	history.clear();check_that(history.frames.is_empty(),"replay_history_clears_between_matches")
	replay_actor.free()

func integration_tests() -> void:
	await load("res://tests/suites/characters.gd").integration(self)
	await load("res://tests/suites/destructibles.gd").run(self)
	for id in MapCatalog.ids_for_mode("tdm"):
		if only_map!="" and id!=only_map:continue
		var world:=MatchWorld.new();root.add_child(world)
		world.configure(catalog,id,catalog.starter_loadouts()[0],1,1201,true)
		for i in 240:
			if world.ready_for_play:break
			await physics_frame
		check_that(world.ready_for_play,"ready_"+id)
		check_that(world.slots.size()==MatchWorld.TEAM_SIZE*2 and world.actors.size()==MatchWorld.TEAM_SIZE*2,"roster_full_"+id)
		check_that(world.slots.size()==16 and world.slots.filter(func(slot:ActorSlot):return slot.team==0).size()==8 and world.slots.filter(func(slot:ActorSlot):return slot.team==1).size()==8,"eight_combatants_per_team_"+id)
		var stable_ids:=true
		for slot_id in world.slots.size():
			var roster_slot:ActorSlot=world.slots[slot_id]
			stable_ids=stable_ids and roster_slot.id==slot_id and roster_slot.team==(0 if slot_id<8 else 1) and roster_slot.is_human==(slot_id==0)
		check_that(stable_ids,"stable_roster_ids_and_one_human_"+id)
		var map:=world.get_world_3d().navigation_map
		# Maps with an upper floor name a point on it in their registry entry (tests.upper_point).
		var registered:Dictionary=MapCatalog.entry(id).get("tests",{})
		if registered.has("upper_point"):
			var minimum_upper_height:=float(registered.get("upper_min_height",3.0))
			var raised_route:=world.arena.definition.qa_route
			check_that(raised_route.size()>5 and raised_route[3].y>=minimum_upper_height and raised_route[4].y>=minimum_upper_height and raised_route[5].y>=minimum_upper_height,"inspection_route_retains_upper_floor_"+id)
			var upper:=world.arena.closest(MapCatalog.vec3(registered.upper_point))
			var reaches_upper:=upper.y>=minimum_upper_height
			for starts in [world.arena.definition.spawns_blue,world.arena.definition.spawns_red]:
				var upper_path:=NavigationServer3D.map_get_path(map,world.arena.closest(starts[0]),upper,true)
				reaches_upper=reaches_upper and not upper_path.is_empty() and upper_path[upper_path.size()-1].distance_to(upper)<.5
			check_that(reaches_upper,"both_teams_reach_upper_gantry_"+id)
		# Stacked routes must retain their authored floor, rather than silently
		# normalizing an unreachable tunnel marker onto the roof above it.
		var level_points:Array=registered.get("navigation_points",[])
		for index in level_points.size():
			var authored:=MapCatalog.vec3(level_points[index])
			var level:=world.arena.closest(authored)
			var reachable:=absf(level.y-authored.y)<.75 and Vector2(level.x-authored.x,level.z-authored.z).length()<1.5
			for starts in [world.arena.definition.spawns_blue,world.arena.definition.spawns_red]:
				var path:=NavigationServer3D.map_get_path(map,world.arena.closest(starts[0]),level,true)
				reachable=reachable and not path.is_empty() and path[-1].distance_to(level)<.5
			check_that(reachable,"both_teams_reach_authored_level_%s_%d"%[id,index],str(level))
		for team in 2:
			var points:Array[Vector3]=world.arena.definition.spawns_blue if team==0 else world.arena.definition.spawns_red
			var connected:=true
			for spawn in points:
				for goal in world.arena.definition.routes:
					var path:=NavigationServer3D.map_get_path(map,world.arena.closest(spawn),world.arena.closest(goal),true)
					if path.is_empty() or path[path.size()-1].distance_to(world.arena.closest(goal))>1:
						if connected:print("UNREACHABLE ",spawn," → ",goal," closest=",world.arena.closest(goal)," path_end=",path[path.size()-1] if not path.is_empty() else Vector3.INF)
						connected=false
			check_that(connected,"spawn_route_connectivity_"+id+"_"+str(team))
			var clear:=true
			for spawn in points:
				var query:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8
				query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,spawn+Vector3.UP*.95);query.collision_mask=1
				clear=clear and world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
			check_that(clear,"all_spawn_capsules_clear_"+id+"_"+str(team))
		for field in ["cover_points","cover_peeks","domination","hardpoints","qa_route"]:
			var valid:=true
			for point in world.arena.definition.get(field):
				var path:=NavigationServer3D.map_get_path(map,world.arena.closest(world.arena.definition.spawns_blue[0]),point,true)
				valid=valid and not path.is_empty() and path[path.size()-1].distance_to(point)<.6
				var query:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8
				query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.95);query.collision_mask=1
				valid=valid and world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
			check_that(valid,"marker_reachability_"+field+"_"+id)
		var actor:=world.actors[0];var enemy:=world.actors[MatchWorld.TEAM_SIZE];var ally:=world.actors[1]
		actor.weapons[0].ammo=7;actor.switch_to(1,0);actor.switch_to(0,.5)
		check_that(actor.weapon().ammo==7,"switch_retains_ammunition_"+id)
		actor.weapon().tick(1)
		world.set_physics_process(false)
		world.clock=10;actor.protected_until=0;enemy.protected_until=0;ally.protected_until=0
		world.queue_damage(0,ally,200,&"ar_a4",false);world.resolve_damage()
		check_that(ally.health==100,"friendly_damage_disabled_"+id)
		var old_life:=enemy.slot.life_id
		world.queue_damage(0,enemy,200,&"ar_a4",true);world.queue_damage(0,enemy,200,&"ar_a4",true);world.resolve_damage()
		check_that(is_equal_approx(enemy.slot.respawn_at-world.clock,3.0),"three_second_respawn_timer_"+id)
		check_that(world.slots[0].kills==1 and world.mode.scores[0]==1 and enemy.slot.deaths==1,"single_kill_attribution_"+id)
		enemy.respawn(world.arena.definition.spawns_red[0],10,catalog);enemy.protected_until=0
		var stale:=DamageEvent.new();stale.source_slot=0;stale.victim_slot=MatchWorld.TEAM_SIZE;stale.victim_life=old_life;stale.amount=200;world.damage_queue.append(stale);world.resolve_damage()
		check_that(enemy.health==100,"old_life_damage_ignored_"+id)
		world.queue_damage(0,enemy,200,&"ar_a4",false);world.resolve_damage()
		var before_life:=enemy.slot.life_id
		world.clock=enemy.slot.respawn_at;world.countdown=0
		world._physics_process(1.0/60);world._physics_process(1.0/60)
		check_that(enemy.slot.life_id==before_life+1 and enemy.slot.respawn_at<0 and world.actors.size()==MatchWorld.TEAM_SIZE*2,"exactly_one_respawn_"+id)
		var normal_spawner:=world.spawner;var rejecting:=RejectingSpawns.new();world.spawner=rejecting
		enemy.alive=false;enemy.slot.respawn_at=world.clock;enemy.slot.next_spawn_attempt=world.clock
		var respawn_deadline:=world.clock
		world._physics_process(1.0/60);world._physics_process(1.0/60)
		check_that(rejecting.attempts==2 and enemy.slot.next_spawn_attempt>world.clock,"unsafe_respawn_retry_is_throttled_"+id)
		world.clock=respawn_deadline+2;world._physics_process(1.0/60)
		check_that(rejecting.exposed and not enemy.alive,"exposed_fallback_still_rejects_invalid_spawn_"+id)
		world.spawner=normal_spawner;enemy.respawn(world.arena.definition.spawns_red[0],world.clock,catalog)
		var smoke:=Node3D.new();world.add_child(smoke)
		var smoke_origin:=MapCatalog.vec3(registered.get("smoke_origin",[0,2,0]))
		world.smoke_clouds.append({"position":smoke_origin,"node":smoke,"expires":100})
		check_that(not world.visible_between(smoke_origin+Vector3.LEFT*5,smoke_origin+Vector3.RIGHT*5,true),"smoke_blocks_visibility_"+id)
		check_that(world.visible_between(smoke_origin+Vector3.LEFT*5,smoke_origin+Vector3.RIGHT*5,false),"smoke_test_ray_unobstructed_"+id)
		world.smoke_clouds.clear();smoke.free()
		var shooter:=world.actors[0];var gun:=shooter.weapon();var saved_command:=shooter.command
		shooter.action_until=-1;shooter.command=ActorCommand.new();gun.cancel_reload();gun.ammo=1;gun.reserve=60;gun.next_shot_at=0
		shooter.command.fire_pressed=true;world.combat(shooter)
		check_that(gun.ammo==0 and gun.state=="RELOADING","last_round_starts_automatic_reload_"+id,"ammo=%d state=%s"%[gun.ammo,gun.state])
		world.clock=gun.reload_at+.01;shooter.command=ActorCommand.new();world.combat(shooter)
		check_that(gun.ammo==gun.capacity and gun.state=="READY","automatic_reload_completes_"+id)
		gun.ammo=0;gun.reserve=0;world.combat(shooter)
		check_that(gun.state=="READY","no_reload_without_reserve_"+id)
		gun.ammo=gun.capacity;gun.reserve=gun.capacity*3;shooter.command=saved_command
		await movement_and_trace_tests(world,id)
		await grenade_throw_tests(world,id)
		await close_quarters_tests(world,id)
		var saved_actors:=world.actors;world.actors=[]
		var dynamic:=SpawnDirector.new()
		var saved_life:=actor.slot.life_id;actor.slot.life_id=0
		check_that(dynamic.candidates(actor,world)==world.arena.definition.spawns_blue,"opening_spawn_retains_team_base_"+id)
		actor.slot.life_id=saved_life
		var pool:=dynamic.candidates(actor,world)
		var shared_ends:=true
		for point in world.arena.definition.spawns_blue+world.arena.definition.spawns_red:
			shared_ends=shared_ends and pool.has(point)
		check_that(shared_ends,"dynamic_respawns_can_flip_team_ends_"+id)
		check_that(pool.size()>world.arena.definition.spawns_blue.size()+world.arena.definition.spawns_red.size(),"dynamic_respawns_include_map_routes_"+id)
		var rotating:=SpawnDirector.new();var first_spawn=rotating.select(actor,world,true);var second_spawn=rotating.select(actor,world,true)
		world.actors=saved_actors
		check_that(first_spawn is Vector3 and second_spawn is Vector3 and first_spawn.distance_to(second_spawn)>8,"respawns_rotate_between_physically_valid_clusters_"+id)
		world.mode.scores=[world.mode.kill_limit-1,world.mode.kill_limit-1];world.mode.on_actor_died({"source":0,"victim":MatchWorld.TEAM_SIZE});world.mode.on_actor_died({"source":MatchWorld.TEAM_SIZE,"victim":0});world.mode.tick(.016)
		check_that(world.mode.finished and world.mode.get_result().winner==-1,"simultaneous_limit_draw_"+id)
		world.mode.begin(world);world.mode.remaining=.01;world.mode.tick(.02)
		check_that(world.mode.finished,"time_limit_"+id)
		var before:=root.get_child_count();world.free();await process_frame
		check_that(root.get_child_count()==before-1,"match_cleanup_"+id)
		var baseline:=root.get_child_count()
		var clean:=true
		for round_index in 3:
			var rematch:=MatchWorld.new();root.add_child(rematch);rematch.configure(catalog,id,catalog.starter_loadouts()[0],1,1201+round_index,true)
			while not rematch.ready_for_play:await physics_frame
			clean=clean and rematch.slots.size()==MatchWorld.TEAM_SIZE*2 and rematch.actors.size()==MatchWorld.TEAM_SIZE*2
			rematch.countdown=0;rematch.mode.remaining=.01
			await physics_frame
			await physics_frame
			clean=clean and rematch.mode.finished
			rematch.free();await process_frame;await process_frame
			clean=clean and root.get_child_count()==baseline
		check_that(clean,"three_consecutive_rematches_"+id)
		await traversal_tests(id)
		var stress:=MatchWorld.new();stress.stress_mode=true;root.add_child(stress);stress.configure(catalog,id,catalog.starter_loadouts()[0],1,1201,true)
		while not stress.ready_for_play:await physics_frame
		stress.set_physics_process(false);await physics_frame;await physics_frame
		check_that(stress.actors.size()==MatchWorld.TEAM_SIZE*2 and stress.actors.all(func(item:Combatant):return item.alive),"stress_roster_full_"+id)
		var stress_clear:=true
		for item in stress.actors:
			var query:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8
			query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,item.global_position+Vector3.UP*.9);query.collision_mask=3;query.exclude=item.excluded()
			stress_clear=stress_clear and stress.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()
		check_that(stress_clear,"stress_spawn_capsules_clear_"+id)
		stress.free();await process_frame;await process_frame

# Knife reach and lethality, reduced recoil, and dropped weapons: a death leaves the weapon,
# walking over guns gives ammunition, interact swaps, and drops expire.
func close_quarters_tests(world:MatchWorld, id:String) -> void:
	var actor:=world.actors[0];var enemy:=world.actors[MatchWorld.TEAM_SIZE]
	var ground:=block(world,Vector3(-101,-.5,0),Vector3(24,1,24))
	actor.respawn(Vector3(-101,.05,0),world.clock,catalog);enemy.respawn(Vector3(-99.4,.05,0),world.clock,catalog)
	for other in world.actors:
		if other!=actor and other!=enemy:other.alive=false;other.collision_layer=0
	actor.global_position=Vector3(-101,.05,0);enemy.global_position=Vector3(-99.4,.05,0)
	actor.yaw=-PI*.5;actor.pitch=0;actor.recoil=0;actor.protected_until=0;enemy.protected_until=0
	await physics_frame;await physics_frame
	world.pickups.clear();world.damage_queue.clear()
	actor.command=ActorCommand.new();actor.command.melee_pressed=true;actor.action_until=world.clock;world.combat(actor)
	check_that(actor.action_kind=="melee" and actor.melee_at>world.clock,"knife_starts_on_melee_"+id)
	world.clock=actor.melee_at+.001;actor.command=ActorCommand.new();world.combat(actor);world.resolve_damage()
	check_that(not enemy.alive,"knife_kills_in_one_strike_"+id,"health="+str(enemy.health))
	check_that(world.pickups.size()==1 and world.pickups[0].weapon==enemy.weapon().definition.id,"death_drops_weapon_"+id)
	enemy.respawn(Vector3(-97.5,.05,0),world.clock,catalog);enemy.global_position=Vector3(-97.5,.05,0);enemy.protected_until=0
	await physics_frame
	world.clock=actor.action_until+.01;actor.command=ActorCommand.new();actor.command.melee_pressed=true;world.combat(actor)
	world.clock=actor.melee_at+.001;actor.command=ActorCommand.new();world.combat(actor);world.resolve_damage()
	check_that(enemy.alive and enemy.health==100,"knife_misses_out_of_reach_"+id)
	world.clock=actor.action_until+.01
	var gun:=actor.weapon();gun.cancel_reload();gun.ammo=gun.capacity;gun.next_shot_at=0;actor.recoil=0
	actor.command=ActorCommand.new();actor.command.fire_pressed=true;world.combat(actor)
	check_that(is_equal_approx(actor.recoil,deg_to_rad(gun.definition.recoil*gun.recoil_scale*MatchWorld.RECOIL_SCALE)) and MatchWorld.RECOIL_SCALE<1,"recoil_per_shot_reduced_"+id)
	# Ammunition: one magazine per carried gun from someone else's weapon, once.
	world.pickups.clear()
	var other:=WeaponRuntime.new();other.configure(catalog.weapons.smg_mp9);other.ammo=20;other.reserve=40
	world.drop_weapon(enemy,other);world.pickups[0].position=actor.global_position
	for runtime in actor.weapons:runtime.reserve=0
	world.tick_pickups()
	check_that(actor.weapons[0].reserve==actor.weapons[0].capacity and actor.weapons[1].reserve==actor.weapons[1].capacity and world.pickups.size()==1,"walking_over_a_gun_scavenges_a_magazine_each_"+id)
	world.tick_pickups()
	check_that(actor.weapons[0].reserve==actor.weapons[0].capacity,"scavenging_is_once_per_gun_"+id)
	# The same gun as one carried: all of its rounds, then it is gone.
	var same:=WeaponRuntime.new();same.configure(actor.weapons[0].definition);same.ammo=10;same.reserve=15
	world.drop_weapon(enemy,same);world.pickups[1].position=actor.global_position;world.tick_pickups()
	check_that(actor.weapons[0].reserve==actor.weapons[0].capacity+25 and world.pickups.size()==1,"same_gun_gives_all_its_rounds_"+id)
	# Interact swaps for the gun on the ground and leaves the old one there.
	var old_id:=actor.weapons[0].definition.id
	check_that(world.swap_candidate(actor).get("weapon",&"")==&"smg_mp9","dropped_gun_in_reach_is_offered_"+id)
	world.clock+=1;actor.action_until=world.clock;actor.command=ActorCommand.new();actor.command.interact_pressed=true;world.combat(actor)
	check_that(actor.weapons[0].definition.id==&"smg_mp9" and actor.weapons[0].ammo==20 and actor.selected_weapon==0,"interact_swaps_for_dropped_gun_"+id)
	check_that(world.pickups.size()==1 and world.pickups[0].weapon==old_id,"swapped_gun_is_left_behind_"+id)
	var reserve_after_swap:=actor.weapons[0].reserve;world.tick_pickups()
	check_that(actor.weapons[0].reserve==reserve_after_swap,"own_swapped_gun_gives_no_ammunition_"+id)
	world.clock=world.pickups[0].expires+.01;world.tick_pickups()
	check_that(world.pickups.is_empty(),"dropped_guns_expire_"+id)
	for i in MatchWorld.MAX_PICKUPS+3:world.drop_weapon(actor,other)
	check_that(world.pickups.size()==MatchWorld.MAX_PICKUPS,"dropped_guns_are_bounded_"+id)
	world.pickups.clear();actor.command=ActorCommand.new();actor.set_loadout(catalog)
	for item in world.actors:
		if item!=actor and item!=enemy:item.alive=true;item.collision_layer=2
	ground.free();await physics_frame

func block(world:MatchWorld, center:Vector3, size:Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=1
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);world.add_child(body);body.global_position=center;return body

func movement_and_trace_tests(world:MatchWorld, id:String) -> void:
	var actor:=world.actors[0];var enemy:=world.actors[MatchWorld.TEAM_SIZE];var ally:=world.actors[1]
	var fixture_floor:=block(world,Vector3(-101,-.5,0),Vector3(24,1,24))
	actor.respawn(Vector3(-101,.05,0),world.clock,catalog)
	for other in world.actors:
		other.head.collision_layer=0;other.torso.collision_layer=0;other.collision_layer=0
	actor.global_position=Vector3(-101,.1,0);actor.velocity=Vector3.ZERO;actor.command=ActorCommand.new();actor.command.aim_yaw=0
	for i in 15:
		await physics_frame;actor.simulate_movement(1.0/60,world)
	actor.command.movement=Vector2(1,1)
	for i in 30:
		await physics_frame;actor.simulate_movement(1.0/60,world)
	check_that(absf(Vector2(actor.velocity.x,actor.velocity.z).length()-5)<.05,"diagonal_speed_normalized_"+id)
	actor.command.movement=Vector2(0,-1);actor.command.sprint=true
	for i in 30:
		await physics_frame;actor.simulate_movement(1.0/60,world)
	check_that(actor.sprinting and absf(Vector2(actor.velocity.x,actor.velocity.z).length()-7)<.05,"shift_sprint_reaches_seven_metres_per_second_"+id,"speed="+str(actor.velocity)+" state="+actor.weapon().state)
	actor.command.crouch=true;actor.simulate_movement(1.0/60,world)
	check_that(not actor.sprinting,"crouch_blocks_sprint_"+id)
	actor.command.crouch=false;actor.command.aim_down_sights=true;actor.simulate_movement(1.0/60,world)
	check_that(actor.ads and not actor.sprinting,"ads_blocks_sprint_"+id,"state="+actor.weapon().state+" action_until="+str(actor.action_until)+" now="+str(world.clock))
	actor.global_position=Vector3(-101,.05,0);actor.velocity=Vector3.ZERO
	actor.command=ActorCommand.new();actor.command.jump_pressed=true
	var before:=actor.global_position.y
	await physics_frame;actor.simulate_movement(1.0/60,world)
	check_that(actor.velocity.y>0 and actor.global_position.y>before,"jump_leaves_ground_"+id)
	actor.global_position=Vector3(-101,.05,0);actor.velocity=Vector3.ZERO;actor.command=ActorCommand.new();actor.command.crouch=true
	await physics_frame;actor.simulate_movement(1.0/60,world)
	var ceiling:=block(world,Vector3(-101,1.45,0),Vector3(3,.2,3))
	await physics_frame;await physics_frame
	actor.command.crouch=false;actor.simulate_movement(1.0/60,world)
	check_that(actor.crouched,"crouch_clearance_"+id)
	ceiling.free();await physics_frame;await physics_frame
	actor.simulate_movement(1.0/60,world)
	check_that(not actor.crouched,"stand_when_clear_"+id)
	actor.command=ActorCommand.new();actor.command.prone=true;actor.command.sprint=true;actor.command.jump_pressed=true;actor.command.movement=Vector2(0,-1)
	for i in 30:
		await physics_frame;actor.simulate_movement(1.0/60,world)
	check_that(actor.prone and not actor.sprinting and actor.velocity.y<=0 and is_equal_approx(actor.eye_height,.6) and is_equal_approx(actor.collider.shape.height,.75),"prone_lowers_camera_and_collider_blocks_sprint_and_jump_"+id)
	check_that(absf(Vector2(actor.velocity.x,actor.velocity.z).length()-1.2)<.05,"prone_crawls_at_1_2_"+id)
	actor.command.movement=Vector2.ZERO;actor.command.jump_pressed=false
	var low_ceiling:=block(world,actor.global_position+Vector3(0,.98,0),Vector3(3,.2,3))
	await physics_frame;await physics_frame
	actor.command.prone=false;actor.command.crouch=true;actor.simulate_movement(1.0/60,world)
	check_that(actor.prone,"prone_cannot_crouch_through_ceiling_"+id)
	actor.command.crouch=false;actor.simulate_movement(1.0/60,world)
	check_that(actor.prone,"prone_cannot_stand_through_ceiling_"+id)
	low_ceiling.free();await physics_frame;await physics_frame
	actor.simulate_movement(1.0/60,world)
	check_that(not actor.prone and not actor.crouched,"prone_stands_when_clear_"+id)
	actor.command=ActorCommand.new();actor.global_position=Vector3(-101,.05,0);actor.velocity=Vector3.ZERO
	var stair:=block(world,Vector3(-101,.125,-3),Vector3(3,.25,1.5))
	actor.global_position=Vector3(-101,.05,0);actor.velocity=Vector3.ZERO;actor.command.movement=Vector2(0,-1)
	var traversed:=false
	for i in 65:
		await physics_frame;actor.simulate_movement(1.0/60,world)
		if actor.global_position.y>.2:traversed=true
	check_that(traversed and actor.global_position.z< -3,"step_traversal_"+id,"end="+str(actor.global_position)+" stepped="+str(traversed))
	stair.free()
	actor.command=ActorCommand.new();actor.global_position=Vector3(-101,.05,0);actor.velocity=Vector3.ZERO
	actor.health=50;actor.last_damage_at=world.clock-7
	actor.simulate_movement(.2,world)
	check_that(is_equal_approx(actor.health,55),"health_regeneration_"+id)
	actor.last_damage_at=world.clock;actor.simulate_movement(.2,world)
	check_that(is_equal_approx(actor.health,55),"damage_delays_regeneration_"+id)
	actor.global_position=Vector3(-101,.05,0)
	ally.global_position=Vector3(-98,.05,0);ally.head.collision_layer=4;ally.torso.collision_layer=4
	await physics_frame;await physics_frame
	var hit:=world.ray(actor.eye(),actor.eye()+Vector3.RIGHT*10,actor)
	check_that(hit.has("collider") and hit.collider.get_meta("actor",null)==ally,"teammate_stops_trace_"+id)
	var wall:=block(world,Vector3(-99.5,1,0),Vector3(.2,2,3));await physics_frame;await physics_frame
	hit=world.ray(actor.eye(),actor.eye()+Vector3.RIGHT*10,actor)
	check_that(hit.get("collider")==wall,"wall_stops_trace_"+id)
	wall.free();ally.head.collision_layer=0;ally.torso.collision_layer=0
	enemy.global_position=Vector3(-98,.05,0);enemy.head.collision_layer=4;enemy.torso.collision_layer=4;enemy.alive=true;enemy.protected_until=0
	await physics_frame;await physics_frame
	actor.yaw=-PI*.5;actor.pitch=0;actor.recoil=0;actor.ads=true
	var thin_cover:=block(world,Vector3(-99.5,1.3,0),Vector3(.015,3,3));await physics_frame;await physics_frame
	world.damage_queue.clear()
	for i in 30:world.fire(actor,runtime("ar_a4"))
	check_that(world.damage_queue.filter(func(event:DamageEvent):return event.victim_slot==MatchWorld.TEAM_SIZE).is_empty(),"thin_cover_blocks_repeated_bullets_"+id)
	thin_cover.free()
	var muzzle_wall:=block(world,Vector3(-100.55,1.3,0),Vector3(.025,3,3));await physics_frame;await physics_frame
	world.damage_queue.clear()
	for i in 12:world.fire(actor,runtime("ar_a4"))
	check_that(world.damage_queue.filter(func(event:DamageEvent):return event.victim_slot==MatchWorld.TEAM_SIZE).is_empty(),"muzzle_against_wall_cannot_shoot_through_"+id)
	muzzle_wall.free();await physics_frame;await physics_frame
	world.damage_queue.clear();world.fire(actor,runtime("sg_p12"))
	var pellet_events:=world.damage_queue.filter(func(event:DamageEvent):return event.victim_slot==MatchWorld.TEAM_SIZE)
	check_that(pellet_events.size()==1,"shotgun_aggregates_pellets_"+id)
	world.damage_queue.clear()
	var grenade:=GameGrenade.new();world.add_child(grenade);grenade.source=0;grenade.kind=0;grenade.global_position=Vector3(-100,.25,0)
	wall=block(world,Vector3(-99,1,0),Vector3(.2,2,3));await physics_frame;await physics_frame
	world.detonate(grenade)
	check_that(world.damage_queue.filter(func(event:DamageEvent):return event.victim_slot==MatchWorld.TEAM_SIZE).is_empty(),"frag_wall_occlusion_"+id)
	world.damage_queue.clear();wall.free();await physics_frame;await physics_frame
	actor.alive=false;world.detonate(grenade)
	check_that(not world.damage_queue.filter(func(event:DamageEvent):return event.victim_slot==MatchWorld.TEAM_SIZE and event.source_slot==0).is_empty(),"grenade_retains_dead_owner_"+id)
	world.damage_queue.clear();grenade.free();actor.alive=true
	world.countdown=0;world.set_physics_process(true)
	var frozen:=world.clock
	paused=true
	for i in 4:await physics_frame
	check_that(world.clock==frozen,"pause_freezes_simulation_"+id)
	paused=false;world.set_physics_process(false)
	fixture_floor.free()

# Overarm grenade: range on flat ground, no tunnelling through a thin wall at throw speed,
# cooking shortens a frag fuse (not a smoke's), and the bots' loft solver lands where asked.
func grenade_throw_tests(world:MatchWorld, id:String) -> void:
	var actor:=world.actors[0]
	var floor_body:=block(world,Vector3(-100,-.5,400),Vector3(300,1,300))
	await physics_frame;await physics_frame
	actor.respawn(Vector3(-100,.05,400),world.clock,catalog)
	actor.global_position=Vector3(-100,.05,400);actor.velocity=Vector3.ZERO;actor.yaw=-PI*.5;actor.pitch=deg_to_rad(15);actor.recoil=0;actor.throw_range=-1
	actor.throw_kind=0;actor.throw_started=world.clock
	world.throw_grenade(actor)
	var grenade:GameGrenade=world.grenades.back()
	var start:=actor.global_position
	var frames:=0
	while frames<900 and not grenade.at_rest():grenade.step(1.0/60);frames+=1
	var first:=Vector2(grenade.first_impact.x-start.x,grenade.first_impact.z-start.z).length()
	var rest:=Vector2(grenade.global_position.x-start.x,grenade.global_position.z-start.z).length()
	check_that(first>=28 and first<=36,"frag_max_throw_lands_28_to_36_metres_"+id,"first impact %.1f m"%first)
	check_that(rest>first and rest<=46 and grenade.bounces>=1 and grenade.at_rest(),"frag_bounces_and_rolls_to_rest_"+id,"rest %.1f m after %d bounces"%[rest,grenade.bounces])
	world.grenades.erase(grenade);grenade.free()
	actor.frags=1
	# A 0.3 m wall across the path, thrown level at full speed.
	var wall:=block(world,Vector3(-90,1.5,400),Vector3(.3,6,60));await physics_frame;await physics_frame
	actor.pitch=-ThrowTimeline.LOFT;world.throw_grenade(actor)
	grenade=world.grenades.back()
	var furthest:=-1000.0;var hit_wall:=false
	for i in 240:
		grenade.step(1.0/60);furthest=maxf(furthest,grenade.global_position.x)
		if grenade.bounces>0:hit_wall=true
	check_that(hit_wall and furthest<=-89.85,"grenade_never_passes_thin_wall_"+id,"furthest x %.2f"%furthest)
	world.grenades.erase(grenade);grenade.free();wall.free();actor.frags=1
	await physics_frame;await physics_frame
	# Cooking: the frag fuse starts at the pin, the smoke's at the throw.
	var fuses:Dictionary={}
	for cook in [0.0,1.2]:
		for kind in [0,1]:
			actor.frags=1;actor.smokes=1;actor.alive=true;actor.action_until=world.clock;actor.action_kind="";actor.throw_holding=false;actor.throw_at=-1
			actor.command=ActorCommand.new();actor.command.requested_throwable=kind;actor.command.throw_held=cook>0
			var began:=world.clock;world.combat(actor)
			actor.command.requested_throwable=-1
			check_that(actor.throw_holding,"throw_key_starts_hold_"+id)
			while world.clock<began+cook:
				world.clock+=.05;world.combat(actor)
			actor.command.throw_held=false
			var count:=world.grenades.size()
			for i in 40:
				world.clock+=.02;world.combat(actor)
				if world.grenades.size()>count:break
			check_that(world.grenades.size()==count+1,"released_throw_spawns_grenade_"+id)
			var thrown:GameGrenade=world.grenades.back()
			fuses[[cook,kind]]={"left":thrown.detonate_at-world.clock,"at":world.clock-began}
			world.grenades.erase(thrown);thrown.free()
	check_that(fuses[[1.2,0]].left<fuses[[0.0,0]].left-.8,"cooked_frag_explodes_earlier_"+id,str(fuses))
	check_that(absf(fuses[[1.2,1]].left-fuses[[0.0,1]].left)<.05,"smoke_fuse_not_cooked_"+id,str(fuses))
	check_that(fuses[[0.0,0]].at>=ThrowTimeline.RELEASE-.03 and fuses[[0.0,0]].at<=ThrowTimeline.RELEASE+.05,"tap_throw_releases_at_0_45_s_"+id,str(fuses[[0.0,0]].at))
	actor.action_until=world.clock;actor.action_kind="";actor.throw_holding=false;actor.throw_at=-1
	for distance in [14.0,22.0,28.0]:
		var landed:=ThrowTimeline.landing_distance(ThrowTimeline.elevation_for(distance,-1.2),-1.2)
		check_that(absf(landed-distance)<1.5,"bot_loft_lands_on_target_%d_%s"%[int(distance),id],"%.1f"%landed)
	floor_body.free()

# Drives the player's own movement code along navigation paths. Every walk must reach
# its goal, in four movement styles (walk, sprint, crouch, jump): every spawn of both
# teams to an objective and to an ammo cache, every ramp both ways, and a seeded sample
# of routes between spawns, route nodes, cover and caches. A walk fails if the player
# stops making progress or falls off; each stuck point is printed with its coordinates.
const WALK_STYLES:=["walk","sprint","crouch","jump"]
const STEP_HEIGHT:=.35

func traversal_tests(id:String) -> void:
	var world:=MatchWorld.new();root.add_child(world)
	world.configure(catalog,id,catalog.starter_loadouts()[0],1,1201,true)
	for i in 600:
		if world.ready_for_play:break
		await physics_frame
	world.set_physics_process(false)
	var actor:=world.actors[0];actor.bot=null
	for other in world.actors:
		if other!=actor:other.global_position=Vector3(0,-50,0);other.alive=false;other.collision_layer=0;other.head.collision_layer=0;other.torso.collision_layer=0
	var definition:=world.arena.definition
	var objectives:Array[Vector3]=[];objectives.append_array(definition.domination);objectives.append_array(definition.hardpoints)
	# Ramps: every AccessRamp in the arena is walked from below and from above in every style.
	var ramp_walks:Array=[]
	var ramps:=find_nodes(world.arena,"AccessRamp")
	print("RAMPS %s: %d AccessRamp nodes" % [id,ramps.size()])
	for ramp in ramps:
		var ends:=ramp_ends(ramp)
		if ends.is_empty():
			check_that(false,"ramp_geometry_readable_%s_%s" % [ramp.name,id]);continue
		var bottom:Vector3=ends.bottom;var top:Vector3=ends.top;var along:Vector3=ends.along
		var below:=bottom-along*1.2;var above:=top+along*1.2
		for style in WALK_STYLES:
			ramp_walks.append({"from":below,"to":above,"style":style,"label":"ramp_up %s" % ramp.name})
			ramp_walks.append({"from":above,"to":below,"style":style,"label":"ramp_down %s" % ramp.name})
		# Lip: the surface just outside each end must sit within one step of the surface just inside it.
		var lips:=[]
		for pair in [[bottom-along*.4,bottom+along*.4],[top+along*.4,top-along*.4]]:
			var outside:=ground_height(world,actor,pair[0]);var inside:=ground_height(world,actor,pair[1])
			lips.append(absf(outside-inside) if not is_nan(outside+inside) else INF)
		check_that(lips.all(func(lip:float):return lip<=STEP_HEIGHT),"ramp_lip_within_step_%s_%s" % [ramp.name,id],"lips %s m at bottom %s, top %s" % [str(lips),str(bottom),str(top)])
		# Solid parapets on both open sides, so nobody can slide off the slab.
		var parapets:=find_nodes(ramp,"RampParapet")
		check_that(parapets.size()==2,"ramp_parapets_both_sides_%s_%s" % [ramp.name,id],"%d parapets" % parapets.size())
	var ramp_result:=walk_paths(world,actor,ramp_walks,id)
	check_that(ramp_result.completed==ramp_result.walked,"ramps_traversable_both_ways_"+id,"%d of %d completed; stuck at %s" % [ramp_result.completed,ramp_result.walked,str(ramp_result.stuck)])
	# Team walks: spawn to objective and spawn to ammo cache, in every style.
	var objective_walks:Array=[];var cache_walks:Array=[]
	for team_index in 2:
		var spawns:Array[Vector3]=definition.spawns_blue if team_index==0 else definition.spawns_red
		for i in spawns.size():
			for style in WALK_STYLES:
				objective_walks.append({"from":spawns[i],"to":objectives[(i+team_index*3)%objectives.size()],"style":style,"label":"spawn%d_team%d_objective" % [i,team_index]})
				cache_walks.append({"from":spawns[i],"to":definition.ammo_caches[(i*3+team_index)%definition.ammo_caches.size()],"style":style,"label":"spawn%d_team%d_cache" % [i,team_index]})
	var objective_result:=walk_paths(world,actor,objective_walks,id)
	check_that(objective_result.completed==objective_result.walked,"spawn_to_objective_walkable_"+id,"%d of %d completed; stuck at %s" % [objective_result.completed,objective_result.walked,str(objective_result.stuck)])
	var cache_result:=walk_paths(world,actor,cache_walks,id)
	check_that(cache_result.completed==cache_result.walked,"spawn_to_ammo_cache_walkable_"+id,"%d of %d completed; stuck at %s" % [cache_result.completed,cache_result.walked,str(cache_result.stuck)])
	# Seeded sample of route nodes, cover and caches.
	var points:Array[Vector3]=[]
	points.append_array(definition.spawns_blue);points.append_array(definition.spawns_red);points.append_array(definition.routes);points.append_array(definition.cover_points);points.append_array(definition.ammo_caches)
	var rng:=RandomNumberGenerator.new();rng.seed=7
	var route_walks:Array=[]
	for i in 60:route_walks.append({"from":points[rng.randi()%points.size()],"to":points[rng.randi()%points.size()],"style":WALK_STYLES[rng.randi()%WALK_STYLES.size()],"label":"route"})
	var route_result:=walk_paths(world,actor,route_walks,id)
	# Nobody may stop beside a ramp either: a stuck point within 3 m of a ramp end is a ramp failure.
	var near_ramp:Array=[]
	for point in route_result.points+ramp_result.points+objective_result.points+cache_result.points:
		for ramp in ramps:
			var ends:=ramp_ends(ramp)
			if ends.is_empty():continue
			for end in [ends.bottom,ends.top]:
				if Vector2(point.x-end.x,point.z-end.z).length()<3.0:near_ramp.append(point)
	check_that(near_ramp.is_empty(),"ramp_stuck_points_clear_"+id,str(near_ramp))
	check_that(route_result.walked>=40 and route_result.completed==route_result.walked,"routes_walkable_"+id,"%d of %d completed; stuck at %s" % [route_result.completed,route_result.walked,str(route_result.stuck)])
	world.free();await process_frame

# Every node named `prefix*` under `node`, depth first.
func find_nodes(node:Node,prefix:String,found:Array=[]) -> Array:
	for child in node.get_children():
		if child.name.begins_with(prefix) and child is Node3D:found.append(child)
		find_nodes(child,prefix,found)
	return found

# A ramp's walkable top surface: the lower end, the upper end, the unit run direction and width.
func ramp_ends(ramp:Node3D) -> Dictionary:
	var visual:MeshInstance3D=null
	for child in ramp.get_children():
		if child is MeshInstance3D:visual=child;break
	if visual==null or visual.mesh==null:return {}
	var box:=visual.mesh.get_aabb()
	var frame:=ramp.global_transform*visual.transform
	var a:=frame*Vector3(box.get_center().x,box.end.y,box.position.z)
	var b:=frame*Vector3(box.get_center().x,box.end.y,box.end.z)
	var low:=a if a.y<=b.y else b;var high:=b if a.y<=b.y else a
	var horizontal:=Vector3(high.x-low.x,0,high.z-low.z)
	if horizontal.length()<.01:return {}
	return {"bottom":low,"top":high,"along":horizontal.normalized(),"width":box.size.x}

# Height of the solid surface under a point (NAN when there is none).
func ground_height(world:MatchWorld, actor:Combatant, point:Vector3) -> float:
	var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point+Vector3.DOWN*6,3,[actor.get_rid()])
	var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.position.y if not hit.is_empty() else NAN

func walk_paths(world:MatchWorld, actor:Combatant, walks:Array, id:String) -> Dictionary:
	var map:=world.get_world_3d().navigation_map
	var result:={"walked":0,"completed":0,"stuck":[],"points":[]}
	var fall_limit: float = float(MapCatalog.entry(id).get("tests",{}).get("fall_limit",-1.0))
	for walk in walks:
		var start:Vector3=world.arena.closest(walk.from);var goal:Vector3=world.arena.closest(walk.to)
		if start.distance_to(goal)<4:continue
		var path:=NavigationServer3D.map_get_path(map,start,goal,true)
		result.walked+=1
		if path.size()<2:
			stuck_point(result,id,walk,start,"no navmesh path")
			continue
		actor.respawn(start,world.clock,catalog);actor.protected_until=0
		actor.global_position=start+Vector3.UP*.1;actor.velocity=Vector3.ZERO;actor.reset_physics_interpolation()
		var command:=ActorCommand.new();command.sprint=walk.style=="sprint";command.crouch=walk.style=="crouch"
		var corner:=1;var last_progress:=actor.global_position;var still:=0.0
		var reached:=false;var stuck_before:int=result.stuck.size()
		# Budget: twice the time the slowest style (crouch, 2.5 m/s) needs to cover the path.
		var length:=0.0
		for i in range(1,path.size()):length+=path[i-1].distance_to(path[i])
		var budget:=int(length/2.5*60*2)+600
		for step in budget:
			while corner<path.size()-1 and Vector2(actor.global_position.x-path[corner].x,actor.global_position.z-path[corner].z).length()<.3:corner+=1
			var to:Vector3=path[corner]-actor.global_position;to.y=0
			if corner==path.size()-1 and to.length()<.6:reached=true;break
			command.aim_yaw=atan2(-to.x,-to.z);command.movement=Vector2(0,-1)
			command.jump_pressed=walk.style=="jump" and actor.is_on_floor() and step%45==0
			actor.command=command
			actor.simulate_movement(1.0/60,world)
			world.clock+=1.0/60
			# Glacier's playable river is below the old maps' zero-height yards.
			if actor.global_position.y<fall_limit:stuck_point(result,id,walk,actor.global_position,"fell",world);break
			if actor.global_position.distance_to(last_progress)>.35:last_progress=actor.global_position;still=0.0
			else:
				still+=1.0/60
				if still>2.0:stuck_point(result,id,walk,actor.global_position,"no progress",world);break
		if reached:result.completed+=1
		elif result.stuck.size()==stuck_before:stuck_point(result,id,walk,actor.global_position,"out of time",world)
	return result

func stuck_point(result:Dictionary, id:String, walk:Dictionary, at:Vector3, why:String, world:MatchWorld=null) -> void:
	result.stuck.append("(%.1f, %.1f, %.1f)" % [at.x,at.y,at.z])
	result.points.append(at)
	print("STUCK %s %s %s: %s at (%.2f, %.2f, %.2f) from (%.2f, %.2f, %.2f) to (%.2f, %.2f, %.2f)" % [id,walk.label,walk.style,why,at.x,at.y,at.z,walk.from.x,walk.from.y,walk.from.z,walk.to.x,walk.to.y,walk.to.z])
	# Colliders within 1.5 m of the stuck point, to show what the walker is pressed against.
	if world!=null:
		var query:=PhysicsShapeQueryParameters3D.new();var sphere:=SphereShape3D.new();sphere.radius=1.5
		query.shape=sphere;query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.9);query.collision_mask=3
		for hit in world.get_world_3d().direct_space_state.intersect_shape(query,16):
			var body:Node=hit.collider;var owner_name:=body.get_parent().get_parent().name if body.get_parent()!=null and body.get_parent().get_parent()!=null else body.name
			print("  near %s (%s)" % [owner_name,str(body.global_position)])
