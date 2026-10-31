extends RefCounted

# Exercise the real viewport setup without starting a match or loading a map.
class ViewportApp extends "res://game/core/app.gd":
	func _ready() -> void:pass
	func _process(_delta:float) -> void:pass
	func _input(_event:InputEvent) -> void:pass
	func _notification(_what:int) -> void:pass

static func run(t) -> void:
	viewport_listener(t)
	var audio:=BattleAudio.new();t.root.add_child(audio);audio.initialize(true)
	var expected:={"spatial_firearms":BattleAudio.SPATIAL_FIREARMS,"spatial_foley":BattleAudio.SPATIAL_FOLEY,"local_firearms":BattleAudio.LOCAL_FIREARMS,"local_foley":BattleAudio.LOCAL_FOLEY,"reflections":BattleAudio.REFLECTION_VOICES}
	var bounded:=true
	for property in expected:bounded=bounded and audio.get(property).size()==expected[property]
	t.check_that(bounded,"audio_separate_bounded_voice_pools")
	var before:=audio.get_child_count();audio.initialize(true)
	t.check_that(audio.get_child_count()==before,"audio_initialization_is_idempotent")
	sound_assets(t,audio)
	voice_isolation(t,audio)
	near_misses(t,audio)
	replay_and_pause(t,audio)
	map_ambience(t,audio)
	await footstep_surfaces(t)
	audio.stop_transients()
	for voice in audio.ambience.values():voice.stop()
	# Let the audio thread retire playback handles from the burst test.
	await t.create_timer(.3).timeout
	audio.free()
	await t.create_timer(.1).timeout

static func viewport_listener(t) -> void:
	var app:=ViewportApp.new();t.root.add_child(app);app.setup_viewports()
	var listener:=app.camera.get_node_or_null("WorldListener") as AudioListener3D
	t.check_that(app.world_view.audio_listener_enable_3d and listener!=null and listener.is_current(),"world_subviewport_has_active_3d_audio_listener")
	# The existing volume control must govern world and first-person sound alike.
	var previous:=AudioServer.get_bus_volume_db(0)
	var was_muted:=AudioServer.is_bus_mute(0)
	app.profile.settings.volume=.25;app.apply_settings()
	t.check_that(is_equal_approx(AudioServer.get_bus_volume_db(0),linear_to_db(.25)),"audio_uses_existing_master_volume_control")
	app.profile.settings.volume=0.0;app.apply_settings()
	t.check_that(AudioServer.is_bus_mute(0),"zero_master_volume_mutes_all_sound")
	app.profile.settings.volume=.25;app.apply_settings()
	t.check_that(not AudioServer.is_bus_mute(0),"raising_master_volume_restores_sound")
	AudioServer.set_bus_volume_db(0,previous);AudioServer.set_bus_mute(0,was_muted);app.free()

static func sound_assets(t,audio:BattleAudio) -> void:
	var valid:=true;var missing:Array[String]=[]
	for kind in BattleAudio.FIREARMS+BattleAudio.VARIANTS+BattleAudio.LOCAL_CUES+["explosion","glass","smoke_hiss"]:
		if not audio.sounds.has(kind) or audio.sounds[kind].is_empty():missing.append(kind);valid=false;continue
		for stream in audio.sounds[kind]:valid=valid and stream is AudioStream and stream.get_length()>0.0
	t.check_that(valid,"audio_existing_weapon_and_foley_assets_load",str(missing))
	var invalid:Array[String]=[]
	for kind in audio.sounds:
		for stream in audio.sounds[kind]:
			if not stream is AudioStream or stream.get_length()<=0.0:invalid.append(kind)
	t.check_that(invalid.is_empty(),"audio_every_registered_sound_has_decodable_samples",str(invalid))

static func voice_isolation(t,audio:BattleAudio) -> void:
	audio.play_sound("assault",Vector3.ZERO,1.0,true)
	audio.play_sound("assault",Vector3(3,0,-5))
	var local:=streams(audio.local_firearms);var spatial:=streams(audio.spatial_firearms)
	var before:=audio.get_child_count()
	for index in 240:
		audio.play_sound("step",Vector3(2,0,-3),.5,true)
		audio.play_sound("impact",Vector3(-2,0,-3),.5)
	t.check_that(local==streams(audio.local_firearms) and spatial==streams(audio.spatial_firearms),"foley_bursts_do_not_steal_gunshot_voices")
	t.check_that(audio.get_child_count()==before,"audio_bursts_do_not_allocate_unbounded_players")
	var routed:=true
	for voice in audio.voices+audio.player_voices:
		routed=routed and (voice.bus==&"Master" or (voice.bus==BattleAudio.REFLECTION_BUS and AudioServer.get_bus_send(AudioServer.get_bus_index(voice.bus))==&"Master"))
	for voice in audio.ambience.values():routed=routed and voice.bus==&"Master"
	t.check_that(routed,"all_audio_routes_through_master_volume")

static func streams(pool:Array) -> Array:
	var result:Array=[]
	for voice in pool:result.append(voice.stream)
	return result

static func near_misses(t,audio:BattleAudio) -> void:
	var listener:=Vector3.ZERO
	t.check_that(audio.bullet_pass(Vector3(-10,1,0),Vector3(10,1,0),listener,10.0),"incoming_round_passing_listener_makes_near_miss")
	t.check_that(not audio.bullet_pass(Vector3(-10,1,0),Vector3(10,1,0),listener,10.03),"near_miss_is_throttled_during_automatic_burst")
	t.check_that(audio.bullet_pass(Vector3(-10,1,0),Vector3(10,1,0),listener,10.2),"near_miss_recovers_after_cooldown")
	var rejected:=true
	for segment in [[Vector3(0,1,0),Vector3(10,1,0)],[Vector3(-1,1,0),Vector3(1,1,0)],[Vector3(-10,5,0),Vector3(10,5,0)],[Vector3(5,1,0),Vector3(15,1,0)],[Vector3(-15,1,0),Vector3(-5,1,0)]]:
		rejected=rejected and not audio.bullet_pass(segment[0],segment[1],listener,20.0)
	t.check_that(rejected,"near_miss_rejects_own_short_distant_and_nonpassing_traces")

static func replay_and_pause(t,audio:BattleAudio) -> void:
	audio.configure("foundry");audio.play_sound("assault",Vector3.ZERO,1.0,true);audio.play_sound("step",Vector3(1,0,-2))
	audio.set_replay_muted(true)
	var silent:=true
	for voice in audio.voices+audio.player_voices+audio.reflections:silent=silent and not voice.playing
	t.check_that(silent,"replay_stops_live_world_and_local_one_shots")
	var prior_local:=streams(audio.local_firearms);var prior_spatial:=streams(audio.spatial_foley)
	audio.play_sound("shotgun",Vector3.ZERO,1.0,true);audio.play_sound("glass",Vector3(2,0,-3))
	t.check_that(streams(audio.local_firearms)==prior_local and streams(audio.spatial_foley)==prior_spatial and not audio.bullet_pass(Vector3(-10,1,0),Vector3(10,1,0),Vector3.ZERO,30.0),"replay_blocks_new_live_audio_events")
	audio.set_replay_muted(false);audio.play_sound("shotgun",Vector3.ZERO,1.0,true)
	t.check_that(streams(audio.local_firearms)!=prior_local,"live_audio_resumes_after_replay")
	t.paused=true
	var pausable:=not audio.can_process()
	for voice in audio.voices+audio.player_voices+audio.reflections+audio.ambience.values():pausable=pausable and not voice.can_process()
	t.paused=false
	t.check_that(pausable,"audio_and_ambience_obey_match_pause")

static func map_ambience(t,audio:BattleAudio) -> void:
	var levels:={}
	for id in ["foundry","village"]:
		audio.configure(id);audio._process(3.0);var mix:={}
		for kind in audio.ambience:mix[kind]=audio.ambience[kind].volume_db
		levels[id]=mix
	t.check_that(levels.foundry!=levels.village,"industrial_and_outdoor_maps_use_distinct_ambience_mixes")
	var valid:=not audio.ambience.is_empty()
	for voice in audio.ambience.values():valid=valid and voice.stream is AudioStream and voice.stream.get_length()>0 and voice.playing
	t.check_that(valid,"map_ambience_layers_start_with_valid_loop_streams")

static func footstep_surfaces(t) -> void:
	var world:=MatchWorld.new();t.root.add_child(world)
	world.effects=MatchEffects.new();world.add_child(world.effects)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1;world.add_child(floor_body)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(4,.4,4);shape.shape=box
	floor_body.add_child(shape);floor_body.position.y=-.2;floor_body.set_meta("surface","metal")
	var actor:=Combatant.new();world.add_child(actor);actor.position=Vector3(0,.05,0)
	await t.physics_frame
	await t.physics_frame
	t.check_that(actor.footstep_sound(world)=="step_metal","metal_footsteps_follow_ground_material_at_ground_level")
	floor_body.position.y=4.8;floor_body.set_meta("surface","earth");actor.position.y=5.05
	await t.physics_frame
	await t.physics_frame
	t.check_that(actor.footstep_sound(world)=="step_gravel","raised_earth_floor_does_not_sound_like_metal")
	world.free()
