extends RefCounted

static func run(t) -> void:
	var catalog:=ZombiesCatalog.new()
	t.check_that(catalog.weapon_ids.size()==15,"zombies_preserve_fifteen_tdm_weapons")
	t.check_that(catalog.weapons.size()==18,"three_wonder_definitions")
	for id: String in ZombiesCatalog.WONDERS:
		var runtime:=catalog.runtime(id)
		t.check_that(runtime.ammo>0 and runtime.reserve_max>0,"wonder_finite_ammo_"+id)
	var starter:=catalog.runtime("pistol_p9",true)
	t.check_that(starter.ammo==8 and starter.reserve==32,"zombies_pistol_start")
	t.check_that(catalog.weapons.pistol_p9.capacity==17,"starter_does_not_mutate_tdm_resource")
	var weapon:=catalog.runtime("sg_p12")
	var perks: Array[String]=["hands","overdrive"]
	weapon.recompute(perks);var scale:=weapon.damage_scale
	for i in 20:weapon.recompute(perks)
	t.check_that(is_equal_approx(weapon.damage_scale,scale) and is_equal_approx(weapon.reload_scale,.65),"perk_recomputation_does_not_stack")
	weapon.ammo=0;weapon.start_reload(0);weapon.tick(.4)
	t.check_that(weapon.ammo==1,"speed_perk_affects_shell_reload")
	weapon.upgraded=true;weapon.recompute([])
	t.check_that(weapon.capacity==12 and weapon.reserve_max==60,"upgrade_capacity_and_reserve")
	for r in range(1,21):t.check_that(ZombiesMode.budget(r)>=6 and ZombiesMode.enemy_health(r)>0,"round_budget_health_%d"%r)
	t.check_that(ZombiesMode.budget(1)==6 and ZombiesMode.budget(20)==108,"round_budget_endpoints")
	t.check_that(MapCatalog.ids_for_mode("tdm").size()==6 and MapCatalog.ids_for_mode("zombies").size()==2,"mode_map_filtering")
	for id: String in MapCatalog.ids_for_mode("zombies"):
		var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/data/zombies/maps/"+id+".json"))
		t.check_that(config.zones.size()==6 and config.barriers.size()==14 and config.box_sites.size()==3,"zombie_map_markers_"+id)
		var ids: Dictionary={};var unique:=true
		for collection in [config.doors,config.barriers,config.stations]:
			for marker: Dictionary in collection:
				if ids.has(marker.id):unique=false
				ids[marker.id]=true
		t.check_that(unique,"unique_marker_ids_"+id)
		var reached: Dictionary={0:true}
		for iteration in 6:
			for edge: Dictionary in config.doors:
				if reached.has(int(edge.zones[0])) or reached.has(int(edge.zones[1])):reached[int(edge.zones[0])]=true;reached[int(edge.zones[1])]=true
		t.check_that(reached.size()==6,"all_zones_connected_"+id)
		t.check_that(ResourceLoader.exists(MapCatalog.scene_path(id)),"prepared_zombies_scene_"+id)
		if not ResourceLoader.exists(MapCatalog.scene_path(id)):continue
		var world:=ZombiesWorld.new();t.root.add_child(world);world.configure(catalog,id,LoadoutDefinition.new(),1,2601,false)
		for frame in 8:await t.physics_frame
		t.check_that(world.ready_for_play and world.actors.size()==25,"world_ready_stable_pool_"+id)
		t.check_that(world.actors[0].weapons.size()==1 and world.actors[0].smokes==0,"one_starting_gun_no_smoke_"+id)
		var nav_map:=world.get_world_3d().navigation_map
		var door:=world.stations[0]
		var a:=Vector3(-14,0,13);var b:=Vector3(-8,0,13)
		var closed_path:=NavigationServer3D.map_get_path(nav_map,a,b,true)
		t.check_that(closed_path.is_empty() or closed_path[closed_path.size()-1].distance_to(b)>1,"closed_door_blocks_navigation_"+id)
		t.check_that(not world.visible_between(a+Vector3.UP,b+Vector3.UP,false),"closed_door_has_physical_collision_"+id)
		door.open(world)
		await t.physics_frame;await t.physics_frame
		var open_path:=NavigationServer3D.map_get_path(nav_map,a,b,true)
		t.check_that(not open_path.is_empty() and open_path[open_path.size()-1].distance_to(b)<.5,"purchase_connects_actual_nav_regions_"+id)
		t.check_that(world.visible_between(a+Vector3.UP,b+Vector3.UP,false),"purchased_door_removes_collision_"+id)
		var enemy:=world.actors[1] as ZombieActor
		enemy.activate(Vector3(-25,0,13),world.clock,500,1,null);enemy.state="PURSUE"
		var life:=enemy.slot.life_id
		t.check_that(enemy.become_crawler() and not enemy.become_crawler(),"crawler_transforms_once_"+id)
		t.check_that(enemy.alive and enemy.health==500 and enemy.slot.life_id==life and enemy.head.position.y<.6,"crawler_keeps_health_life_low_hurtbox_"+id)
		world.mode.round_number=1;world.mode.intermission=0;world.mode.remaining_to_spawn=0;world.mode.check_clear(world.living_count())
		t.check_that(world.mode.intermission==0,"last_crawler_holds_round_"+id)
		world.queue_damage(0,enemy,600,&"frag",false);world.resolve_damage()
		t.check_that(not enemy.alive,"fatal_frag_never_resurrects_crawler_"+id)
		world.mode.check_clear(world.living_count())
		t.check_that(world.mode.completed_rounds==1,"round_clears_after_last_crawler_"+id)
		var old:=DamageEvent.new();old.victim_slot=1;old.victim_life=life;old.amount=9999;old.source_slot=0;old.weapon_id=&"frag"
		enemy.activate(Vector3(-25,0,13),world.clock,500,1,null);enemy.state="PURSUE";world.damage_queue.append(old);world.resolve_damage()
		t.check_that(enemy.health==500 and not enemy.crawling,"pool_reuse_resets_anatomy_rejects_stale_damage_"+id)
		world.qa_protect_player=true
		enemy.activate(Vector3(-20,0,5),world.clock,500,1,null);enemy.state="PURSUE"
		world.blast(Vector3(-23,0,5),6,350,0,&"frag");world.resolve_damage()
		t.check_that(enemy.crawling and enemy.health>0 and enemy.health<500,"actual_nonlethal_frag_severs_legs_"+id)
		enemy.activate(Vector3(-20,0,5),world.clock,500,1,null);enemy.state="PURSUE"
		var low_cover:=ZombieObjects.solid(world,Vector3(.3,.4,1),Vector3(-21.5,.2,5))
		await t.physics_frame
		world.blast(Vector3(-23,0,5),6,350,0,&"frag");world.resolve_damage()
		t.check_that(not enemy.crawling and enemy.health<500,"occluded_lower_body_prevents_leg_loss_"+id)
		low_cover.free()
		world.mode.points=20000
		var perk_station: ZombieStation
		for station in world.stations:
			if station.kind=="perk" and station.item=="heart":perk_station=station
		t.check_that(not world.interactions.perform(perk_station),"unpowered_perk_rejected_"+id)
		world.mode.power=true
		t.check_that(world.interactions.perform(perk_station) and world.actors[0].max_health==200,"health_perk_applies_"+id)
		var points_after: int=world.mode.points
		t.check_that(not world.interactions.perform(perk_station) and world.mode.points==points_after,"duplicate_perk_never_debits_"+id)
		var barrier:=world.barriers[0];barrier.boards=0;world.mode.repair_earned=0
		for i in 20:barrier.boards=0;barrier.repair(world)
		t.check_that(world.mode.repair_earned==100,"barrier_rewards_capped_"+id)
		world.mode.points=10000
		t.check_that(world.give_weapon("smg_mp9") and world.actors[0].weapons.size()==2 and not world.give_weapon("smg_mp9"),"two_slots_duplicate_rejected_"+id)
		world.box.roll();var after: int=world.mode.points
		t.check_that(not world.box.roll() and world.mode.points==after,"box_busy_no_double_debit_"+id)
		world.mode.perks.assign(["heart","revive"]);world.actors[0].apply_perks(world.mode.perks)
		world.qa_protect_player=false;world.actors[0].protected_until=0;world.queue_damage(1,world.actors[0],1000,&"zombie",false);world.resolve_damage()
		t.check_that(world.actors[0].alive and world.mode.perks.is_empty() and world.downed_until>world.clock,"solo_revive_consumes_all_perks_"+id)
		world.qa_protect_player=true;world.downed_until=0;world.revive_protection_until=0
		world.mode.perks.clear();world.mode.power=true;world.mode.points=20000
		var upgraded_runtime:=world.actors[0].weapon() as ZombieWeaponRuntime
		var upgrade_station: ZombieStation
		for station in world.stations:
			if station.kind=="upgrade":upgrade_station=station
		t.check_that(world.interactions.perform(upgrade_station) and upgraded_runtime.upgraded,"upgrade_success_"+id)
		var upgrade_points: int=world.mode.points
		t.check_that(not world.interactions.perform(upgrade_station) and world.mode.points==upgrade_points,"upgrade_repeat_no_debit_"+id)
		upgraded_runtime.reserve=0
		var ammo_wall: ZombieStation
		for station in world.stations:
			if station.kind=="wall" and station.item==upgraded_runtime.base_id:ammo_wall=station
		if ammo_wall!=null:
			var before_ammo: int=world.mode.points;var loaded:=upgraded_runtime.ammo
			t.check_that(world.interactions.perform(ammo_wall) and world.mode.points==before_ammo-2500 and upgraded_runtime.ammo==loaded,"upgraded_wall_ammo_preserves_magazine_"+id)
		world.box.state="IDLE";world.box.spins=0;world.box.roll()
		var before_offer: String=str(world.actors[0].weapon().definition.id)
		world.box.until=world.clock;world.box.tick(.1)
		t.check_that(world.box.state=="OFFERED" and str(world.actors[0].weapon().definition.id)==before_offer,"box_reveal_requires_claim_"+id)
		var offered: String=world.box.offer
		t.check_that(world.box.claim() and world.owns(offered),"box_claim_grants_offered_gun_"+id)
		world.box.state="IDLE";world.box.roll();world.box.until=world.clock;world.box.tick(.1)
		var expiry_points: int=world.mode.points;var expiry_gun: String=str(world.actors[0].weapon().definition.id)
		world.box.until=world.clock;world.box.tick(.1)
		t.check_that(world.box.state=="CLOSING" and world.mode.points==expiry_points and str(world.actors[0].weapon().definition.id)==expiry_gun,"box_timeout_neither_grants_nor_refunds_"+id)
		world.mode.remaining_to_spawn=7
		world.collect("nuke")
		t.check_that(world.mode.remaining_to_spawn==7,"nuke_keeps_unspawned_budget_"+id)
		world.collect("double");var old_until: float=world.mode.double_until
		world.clock+=1;world.collect("double")
		t.check_that(world.mode.double_until==world.clock+30 and world.mode.double_until<old_until+30,"timed_powerup_resets_without_stacking_"+id)
		var carpenter_before: int=world.mode.points;world.collect("carpenter")
		t.check_that(world.mode.points==carpenter_before+400,"carpenter_double_points_bonus_"+id)
		barrier.boards=0;barrier.traveller=1;barrier.carpenter()
		t.check_that(barrier.boards==0 and barrier.pending_carpenter,"carpenter_respects_entry_reservation_"+id)
		barrier.release(1)
		t.check_that(barrier.boards==6 and not barrier.pending_carpenter,"carpenter_finishes_after_entry_"+id)
		# Test actual wonder hit queries, rather than only checking their definitions.
		world.mode.intermission=10000;world.mode.remaining_to_spawn=0;world.mode.insta_until=0
		for actor in world.actors.slice(1):actor.deactivate()
		var shooter:=world.actors[0];shooter.global_position=Vector3(-6,0,20);shooter.yaw=0;shooter.pitch=-.09;shooter.recoil=0
		enemy.activate(Vector3(-6,0,15),world.clock,2000,1,null);enemy.state="PURSUE"
		var second:=world.actors[2] as ZombieActor
		second.activate(Vector3(-4,0,14),world.clock,2000,1,null);second.state="PURSUE"
		await t.physics_frame
		world.damage_queue.clear();world.fire(shooter,catalog.runtime("z_arc"))
		var chain_ids: Dictionary={}
		for event in world.damage_queue:chain_ids[event.victim_slot]=true
		t.check_that(world.damage_queue.size()==2 and chain_ids.size()==2,"arc_chains_to_distinct_targets_"+id)
		world.damage_queue.clear()
		var wonder_cover:=ZombieObjects.solid(world,Vector3(5,3,.08),Vector3(-6,1.5,17))
		await t.physics_frame
		world.fire(shooter,catalog.runtime("z_thunder"))
		t.check_that(world.damage_queue.is_empty(),"thunder_cone_respects_solid_cover_"+id)
		world.fire(shooter,catalog.runtime("z_ray"));world.projectile_tick(.3)
		t.check_that(world.projectiles.is_empty() and world.damage_queue.is_empty(),"ray_sweep_cannot_tunnel_through_thin_cover_"+id)
		wonder_cover.free();await t.physics_frame
		var close_cover:=ZombieObjects.solid(world,Vector3(2,3,.08),Vector3(-6,1.5,19.8))
		await t.physics_frame
		world.fire(shooter,catalog.runtime("z_ray"));world.projectile_tick(.3)
		t.check_that(world.projectiles.is_empty() and world.damage_queue.all(func(hit_damage):return hit_damage.victim_slot==0 and hit_damage.amount<=30),"ray_origin_cannot_spawn_past_point_blank_cover_"+id)
		world.damage_queue.clear();close_cover.free();await t.physics_frame
		world.fire(shooter,catalog.runtime("z_thunder"))
		t.check_that(world.damage_queue.size()==2,"thunder_hits_visible_cone_targets_"+id)
		world.damage_queue.clear()
		enemy.barrier=world.barriers[0];world.fire(shooter,catalog.runtime("z_thunder"))
		t.check_that(enemy.velocity==Vector3.ZERO,"window_queue_survivor_cannot_be_blown_off_staging_floor_"+id)
		world.free();await t.process_frame
	var art:=ZombieVisual.new();t.root.add_child(art);art.build(0)
	t.check_that(art.rig.get_bone_count()==57 and art.whole_mesh.surface_get_array_len(0)>1000,"textured_zombie_uses_authored_skinned_anatomy")
	t.check_that(art.body_mesh.material_override.albedo_texture!=null and art.body_mesh.material_override.normal_enabled,"zombie_has_diffuse_and_normal_maps")
	t.check_that(art.animator.has_animation("attack"),"authored_zombie_attack_clip")
	art.pose(.45,false,1,false,false)
	var standing_head:=art.model.transform*art.rig.get_bone_global_pose(art.head_bone).origin
	t.check_that(standing_head.y>1.2 and standing_head.y<1.9,"textured_zombie_normalized_head_height")
	art.pose(.45,true,1,false,false)
	var crawling_head:=art.model.transform*art.rig.get_bone_global_pose(art.head_bone).origin
	t.check_that(art.body_mesh.mesh.surface_get_array_index_len(0)<art.whole_mesh.surface_get_array_index_len(0),"crawler_removes_actual_skinned_leg_triangles")
	t.check_that(crawling_head.y>.1 and crawling_head.y<.8 and crawling_head.z<-.3,"skeletal_crawler_low_forward_head")
	var crawl_pose:=art.rig.get_bone_global_pose(art.head_bone)
	for repeat in 20:art.pose(.45,true,1,false,false)
	t.check_that(art.rig.get_bone_global_pose(art.head_bone).is_equal_approx(crawl_pose),"crawler_head_override_never_accumulates_rotation")
	art.pose(.45,false,1,false,false)
	t.check_that(art.body_mesh.mesh==art.whole_mesh,"pool_reuse_restores_complete_skinned_body")
	art.pose(.65,false,1,true,false)
	var reaching_hand:=art.model.transform*art.rig.get_bone_global_pose(art.arm_bones[0][2]).origin
	t.check_that(reaching_hand.z<-.25 and reaching_hand.y>.8 and reaching_hand.y<1.6,"zombie_lunge_reaches_toward_player")
	var detached:=art.detached_leg(-1)
	t.check_that(detached.mesh.surface_get_array_index_len(0)>0 and detached.mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES]==null,"severed_leg_is_baked_textured_geometry_not_another_live_rig")
	t.check_that(detached.material_override==art.body_mesh.material_override,"severed_leg_keeps_source_clothing_material")
	detached.free();art.free()
	var profile_path:="res://.artifacts/zombie-corrupt-profile"
	DirAccess.make_dir_recursive_absolute(profile_path)
	var profile_file:=FileAccess.open(profile_path+"/profile.json",FileAccess.WRITE)
	profile_file.store_string(JSON.stringify({"version":1,"loadouts":[],"zombies_records":{"dead_current":42,"dead_air":{"round":"bad"}}}));profile_file.close()
	var profile:=ProfileStore.new();profile.configure(Catalog.new(),profile_path)
	t.check_that(profile.zombies_records.is_empty() and profile.loadouts.size()==5,"invalid_optional_zombies_records_preserve_profile")
