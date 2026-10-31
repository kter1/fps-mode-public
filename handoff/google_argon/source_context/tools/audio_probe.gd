extends SceneTree

# Rendered check of the actual game's SubViewport and audio server output.
# Run through tools/dev.py so editor/render work shares its exclusive lock.
var results:Array[Dictionary]=[]
var capture:AudioEffectCapture
var audio:BattleAudio
var app

func _initialize() -> void:
	call_deferred("run")

func record(name:String, passed:bool, detail:Dictionary={}) -> void:
	results.append({"name":name,"passed":passed,"detail":detail})
	print("PASS " if passed else "FAIL ",name," ",JSON.stringify(detail))

func sample() -> Dictionary:
	var frames:=capture.get_buffer(capture.get_frames_available())
	var peak:=0.0;var energy:=0.0
	for frame in frames:
		peak=maxf(peak,maxf(absf(frame.x),absf(frame.y)))
		energy+=frame.length_squared()
	return {"frames":frames.size(),"peak":peak,"rms":sqrt(energy/maxi(1,frames.size()*2))}

func measure(kind:String, local:=false) -> Dictionary:
	audio.stop_transients();capture.clear_buffer()
	audio.play_sound(kind,Vector3(2,0,-4),.65,local)
	await create_timer(.3).timeout
	return sample()

func run() -> void:
	app=load("res://tests/suites/audio.gd").ViewportApp.new()
	root.add_child(app);app.setup_viewports()
	var world:=Node3D.new();world.process_mode=Node.PROCESS_MODE_PAUSABLE
	app.world_view.add_child(world)
	audio=BattleAudio.new();world.add_child(audio);audio.initialize()
	AudioServer.set_bus_mute(AudioServer.get_bus_index(BattleAudio.REFLECTION_BUS),true)
	AudioServer.add_bus_effect(0,AudioEffectLimiter.new())
	capture=AudioEffectCapture.new();capture.buffer_length=1.0;AudioServer.add_bus_effect(0,capture)
	await create_timer(.2).timeout
	app.world_view.audio_listener_enable_3d=false
	var absent:Dictionary=await measure("step_metal")
	app.world_view.audio_listener_enable_3d=true
	var spatial:Dictionary=await measure("step_metal")
	record("spatial_audio_reaches_actual_game_viewport",spatial.rms>.0001 and absent.rms<spatial.rms*.01,{"disabled":absent,"enabled":spatial})
	var local:Dictionary=await measure("assault",true)
	record("original_first_person_gunfire_remains_audible",local.rms>.001,local)
	audio.stop_transients();await create_timer(1.3).timeout
	audio.configure("village");audio._process(3.0)
	await create_timer(.3).timeout;capture.clear_buffer();await create_timer(.3).timeout
	var ambient:=sample()
	record("map_ambience_produces_audible_output",ambient.rms>.00001,ambient)
	paused=true
	await create_timer(.2).timeout;capture.clear_buffer();await create_timer(.3).timeout
	var pause_mix:=sample()
	record("pausing_silences_world_audio",pause_mix.rms<.000001,pause_mix)
	paused=false
	await create_timer(.2).timeout;capture.clear_buffer();await create_timer(.3).timeout
	var resumed:=sample()
	record("resuming_restores_world_audio",resumed.rms>.00001,resumed)
	audio.set_replay_muted(true)
	await create_timer(.2).timeout;capture.clear_buffer();await create_timer(.3).timeout
	var replay:=sample()
	record("replay_mutes_live_ambience",replay.rms<.000001,replay)
	audio.set_replay_muted(false);audio.configure("")
	for voice in audio.ambience.values():voice.stop()
	capture.clear_buffer()
	for index in 16:audio.play_sound("assault",Vector3((index%4-2)*4,0,-4-index*2),.65)
	await create_timer(.4).timeout
	var battle:=sample()
	record("full_roster_gunfire_mix_is_bounded",battle.rms>.001 and battle.peak<=1.001,battle)
	var failed:=results.filter(func(result:Dictionary):return not result.passed).size()
	var report:={"passed":results.size()-failed,"failed":failed,"tests":results,"engine":Engine.get_version_info().string}
	var file:=FileAccess.open("res://.artifacts/reports/audio-output.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("AUDIO_OUTPUT_RESULT ",JSON.stringify(report))
	audio.stop_transients()
	app.world_texture.texture=null
	app.free()
	await process_frame
	await process_frame
	quit(0 if failed==0 else 1)
