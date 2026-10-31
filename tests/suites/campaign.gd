extends RefCounted

static func run(t:SceneTree) -> void:
	var world:=CampaignWorld.new()
	t.root.add_child(world)
	world.set_physics_process(false)
	world.configure(t.catalog,"blackout",t.catalog.starter_loadouts()[0],1,1201)
	var deadline:=Time.get_ticks_msec()+20000
	while not world.mode.activated and Time.get_ticks_msec()<deadline:await t.physics_frame
	t.check_that(world.mode.activated,"campaign_navigation_and_encounter_ready")
	if not world.mode.activated:world.free();return
	t.check_that(world.mode_id=="campaign" and world.mode.enemies_left()==4,"campaign_first_encounter_finite_roster")
	t.check_that(world.actors[1].alive and world.actors[2].alive and not world.actors[3].alive,"campaign_two_squadmates")
	var dialogue:=world.dialogue
	dialogue.set_process(false)
	t.check_that(dialogue.cues.size()==10 and dialogue.streams.size()==10,"campaign_all_approved_voice_assets_load")
	t.check_that(dialogue.cues[5].take==2 and FileAccess.get_sha256(dialogue.cues[5].audio)==dialogue.cues[5].sha256,"campaign_approved_atlas_relay_take_two")
	var heard:Array[String]=[]
	dialogue.cue_started.connect(func(id:String):heard.append(id))
	dialogue.start_intro();dialogue.advance(dialogue.lead_seconds+.01)
	t.check_that(heard==["01_rook"] and dialogue.subtitle.begins_with("ROOK") and dialogue.spatial.playing and not dialogue.radio.playing,"campaign_rook_spatial_voice_and_subtitle")
	var frozen:=dialogue.remaining
	dialogue.set_process(true);t.paused=true
	for frame in 3:await t.process_frame
	t.check_that(is_equal_approx(dialogue.remaining,frozen) and not dialogue.can_process(),"campaign_pause_freezes_dialogue")
	dialogue.set_process(false);t.paused=false
	dialogue.advance(dialogue.remaining+.01)
	t.check_that(dialogue.subtitle.begins_with("CONTROL") and dialogue.radio.playing and not dialogue.spatial.playing and dialogue.radio.bus==CampaignDialogue.RADIO_BUS,"campaign_control_uses_radio_bus")
	while dialogue.active:dialogue.advance(dialogue.remaining+.01)
	t.check_that(heard.size()==10 and heard[5]=="06_atlas" and dialogue.subtitle.is_empty() and not dialogue.radio.playing and not dialogue.spatial.playing,"campaign_complete_voice_sequence_cleans_up")
	dialogue.start_intro()
	t.check_that(not dialogue.active,"campaign_intro_does_not_repeat_in_same_attempt")
	dialogue.intro_started=false;dialogue.start_intro();dialogue.advance(dialogue.lead_seconds+.01)
	world.actors[1].alive=false;dialogue._process(.01)
	t.check_that(not dialogue.active and dialogue.subtitle.is_empty() and not dialogue.spatial.playing,"campaign_dead_squad_speaker_stops_dialogue")
	world.actors[1].alive=true
	world.actors[0].global_position=CampaignMode.TARGETS[0]
	world.mode.tick(4)
	t.check_that(world.mode.stage==0,"campaign_hostiles_block_objective")
	var stages:Array[int]=[]
	world.mode.checkpoint_reached.connect(func(stage:int):stages.append(stage))
	for stage in 4:
		for actor in world.actors:
			if actor.slot.team==1:world.deactivate_actor(actor)
		world.actors[0].global_position=CampaignMode.TARGETS[stage]
		world.mode.tick(1)
		t.check_that(world.mode.hold==1,"campaign_hold_progress_"+str(stage))
		world.actors[0].global_position=Vector3(50,0,40)
		world.mode.tick(.1)
		t.check_that(world.mode.hold==0,"campaign_hold_resets_outside_zone_"+str(stage))
		world.actors[0].global_position=CampaignMode.TARGETS[stage]
		world.mode.tick(3.1)
		if stage<3:t.check_that(world.mode.stage==stage+1 and world.mode.enemies_left()==CampaignMode.COUNTS[stage+1],"campaign_next_encounter_"+str(stage))
	t.check_that(stages==[1,2,3],"campaign_checkpoint_sequence")
	t.check_that(world.mode.finished and world.mode.get_result().success,"campaign_extraction_ending")
	world.mode.finished=false;world.mode.success=false
	world.mode.on_actor_died({"source":8,"victim":0})
	t.check_that(world.mode.finished and not world.mode.get_result().success and world.slots[0].respawn_at==-1,"campaign_death_fails_without_respawn")
	world.free()
	var resumed:=CampaignWorld.new();resumed.initial_stage=2;t.root.add_child(resumed);resumed.set_physics_process(false)
	resumed.configure(t.catalog,"blackout",t.catalog.starter_loadouts()[0],1,1201)
	deadline=Time.get_ticks_msec()+20000
	while not resumed.mode.activated and Time.get_ticks_msec()<deadline:await t.physics_frame
	t.check_that(resumed.mode.stage==2 and resumed.mode.enemies_left()==8 and resumed.actors[0].alive,"campaign_checkpoint_restores_encounter")
	resumed.dialogue.start_intro()
	t.check_that(not resumed.dialogue.active and resumed.dialogue.subtitle.is_empty(),"campaign_later_checkpoint_skips_arrival_dialogue")
	resumed.free()

	var app=load("res://game/core/app.gd").new()
	app.profile.directory="res://.artifacts/campaign-test-profile"
	app.save_campaign_checkpoint(2)
	var path:String=app.profile.directory.path_join("campaign.json")
	var saved:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	t.check_that(saved is Dictionary and saved.get("stage")==2 and saved.get("version")==1,"campaign_checkpoint_saved_to_disk")
	app.save_campaign_checkpoint(0)
	saved=JSON.parse_string(FileAccess.get_file_as_string(path))
	t.check_that(saved.stage==0 and not FileAccess.file_exists(path+".tmp"),"campaign_new_mission_resets_checkpoint_atomically")
	app.free()
