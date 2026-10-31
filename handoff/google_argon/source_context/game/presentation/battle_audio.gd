class_name BattleAudio
extends Node3D

# Gun tails and movement never compete for the same voices. All pools are fixed;
# a busy firefight drops a quiet distant cue before interrupting a close one.
const SPATIAL_FIREARMS := 24
const SPATIAL_FOLEY := 20
const LOCAL_FIREARMS := 8
const LOCAL_FOLEY := 8
const REFLECTION_VOICES := 8
const FIREARMS := ["assault", "smg", "shotgun", "lmg", "marksman", "sniper", "sidearm"]
const LOCAL_CUES := ["hit_confirm", "kill_confirm", "spawn", "match_win", "match_loss", "ui_focus", "ui_accept"]
const VARIANTS := ["reload", "step", "click", "switch", "casing", "impact", "step_gravel", "step_metal", "knife", "knife_hit", "gear", "jump", "land", "near_miss", "ricochet", "hurt", "grenade_pin", "grenade_throw", "grenade_bounce", "impact_concrete", "impact_metal", "impact_earth", "impact_wood", "impact_flesh"]
const REFLECTION_BUS := "Battle reflections"
const AMBIENCE_LEVELS := {
	"village": {"wind": -18.0, "birds": -18.5},
	"ridgeline": {"wind": -17.0, "birds": -23.0},
	"airport": {"wind": -23.0, "industrial": -21.0},
	"foundry": {"wind": -28.0, "industrial": -17.5},
	"blackout": {"wind": -24.0, "industrial": -20.0},
	"harbor": {"wind": -15.5, "industrial": -28.0},
}

var initialized := false
var replay_muted := false
var map_id := ""
var sounds: Dictionary = {}
var spatial_firearms: Array[AudioStreamPlayer3D] = []
var spatial_foley: Array[AudioStreamPlayer3D] = []
var local_firearms: Array[AudioStreamPlayer] = []
var local_foley: Array[AudioStreamPlayer] = []
var reflections: Array[AudioStreamPlayer3D] = []
var voices: Array[AudioStreamPlayer3D] = []
var player_voices: Array[AudioStreamPlayer] = []
var ambience: Dictionary = {}
var heartbeat: AudioStreamPlayer
var time := 0.0
var mix_time := 0.0
var last_combat := -10.0
var last_near_miss := -10.0
var last_impact := -10.0
var last_ricochet := -10.0
var health := 100.0
var listener_alive := true
var random := RandomNumberGenerator.new()
var occlusion_frame := -1
var occlusion_queries := 0

func initialize(force_audio := false) -> void:
	if initialized or (DisplayServer.get_name() == "headless" and not force_audio):return
	initialized = true
	random.seed = 41037
	for kind in FIREARMS + VARIANTS:
		var variants: Array[AudioStream] = []
		for i in 4:
			var path := "res://content/audio/%s_%d.wav" % [kind, i]
			if ResourceLoader.exists(path):variants.append(load(path) as AudioStream)
		if not variants.is_empty():sounds[kind] = variants
	for kind in LOCAL_CUES + ["smoke_hiss"]:
		var path := "res://content/audio/%s.wav" % kind
		if ResourceLoader.exists(path):sounds[kind] = [load(path) as AudioStream]
	for pair in [["explosion", "explosion"], ["glass", "glass_break"]]:
		var path := "res://content/audio/%s.ogg" % pair[1]
		if ResourceLoader.exists(path):sounds[pair[0]] = [load(path) as AudioStream]
	build_reflection_bus()
	for i in SPATIAL_FIREARMS:spatial_firearms.append(make_spatial())
	for i in SPATIAL_FOLEY:spatial_foley.append(make_spatial())
	for i in REFLECTION_VOICES:
		var voice := make_spatial();voice.bus = REFLECTION_BUS;reflections.append(voice)
	voices.append_array(spatial_firearms);voices.append_array(spatial_foley);voices.append_array(reflections)
	for i in LOCAL_FIREARMS:local_firearms.append(make_local())
	for i in LOCAL_FOLEY:local_foley.append(make_local())
	player_voices.append_array(local_firearms);player_voices.append_array(local_foley)
	for kind in ["wind", "industrial", "birds"]:
		var voice := make_local();voice.volume_db = -80.0
		voice.stream = loop_stream("res://content/audio/ambience_%s.wav" % kind)
		ambience[kind] = voice
	heartbeat = make_local();heartbeat.stream = loop_stream("res://content/audio/heartbeat.wav");heartbeat.volume_db = -80.0

func make_spatial() -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.max_distance = 100.0;voice.unit_size = 12.0;voice.max_db = 0.0
	voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(voice)
	return voice

func make_local() -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new();add_child(voice);return voice

func loop_stream(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamWAV:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	return stream

func build_reflection_bus() -> void:
	if AudioServer.get_bus_index(REFLECTION_BUS) >= 0:return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, REFLECTION_BUS);AudioServer.set_bus_send(index, "Master")
	var room := AudioEffectReverb.new()
	room.dry = 0.0;room.wet = .24;room.room_size = .42;room.damping = .65
	room.predelay_msec = 34.0;room.hipass = .35
	AudioServer.add_bus_effect(index, room)

func configure(id: String) -> void:
	map_id = id.to_lower()
	if not initialized:return
	for kind in ambience:
		var voice: AudioStreamPlayer = ambience[kind]
		voice.volume_db = -80.0
		if voice.stream != null and not voice.playing:voice.play()
		voice.stream_paused = replay_muted

func tick(now: float) -> void:
	time = now

# Ambience fades continue through the countdown and results. Node processing and
# audio players inherit their world's pause state, so an open pause menu is quiet.
func _process(delta: float) -> void:
	if not initialized:return
	if replay_muted:return
	mix_time += delta
	var levels: Dictionary = AMBIENCE_LEVELS.get(map_id, {"wind": -23.0})
	var duck := 3.5 * clampf(1.0 - (mix_time - last_combat) / 1.6, 0.0, 1.0)
	for kind in ambience:
		var voice: AudioStreamPlayer = ambience[kind]
		var target: float = float(levels.get(kind, -80.0)) - duck if not map_id.is_empty() else -80.0
		voice.volume_db = move_toward(voice.volume_db, target, delta * (45.0 if target > voice.volume_db else 14.0))
	var tension := clampf((30.0 - health) / 22.0, 0.0, 1.0) if listener_alive else 0.0
	var heartbeat_target := linear_to_db(lerpf(.08, .19, tension)) if tension > 0.0 else -80.0
	heartbeat.volume_db = move_toward(heartbeat.volume_db, heartbeat_target, delta * 45.0)
	if heartbeat.stream != null and heartbeat.volume_db > -65.0 and not heartbeat.playing:heartbeat.play()
	if heartbeat.volume_db <= -65.0 and heartbeat.playing:heartbeat.stop()

func set_listener_health(value: float, alive: bool) -> void:
	health = value;listener_alive = alive

func set_replay_muted(value: bool) -> void:
	if replay_muted == value:return
	replay_muted = value
	if not initialized:return
	if value:
		stop_transients()
		heartbeat.stop();heartbeat.volume_db = -80.0
	for kind in ambience:
		var voice: AudioStreamPlayer = ambience[kind]
		voice.stream_paused = value
		if not value:voice.volume_db = -80.0

func stop_transients() -> void:
	for voice in voices:voice.stop()
	for voice in player_voices:voice.stop()

func play_sound(kind: String, position: Vector3, volume := 1.0, priority := false) -> void:
	if not initialized or replay_muted or not sounds.has(kind) or volume <= 0.0:return
	var firearm := kind in FIREARMS
	if firearm or kind == "explosion":last_combat = mix_time
	var variants: Array = sounds[kind]
	var stream: AudioStream = variants[random.randi_range(0, variants.size() - 1)]
	var pitch := random.randf_range(.97, 1.03) if firearm else random.randf_range(.94, 1.06)
	if kind in LOCAL_CUES:pitch = 1.0
	var local := priority or kind in LOCAL_CUES
	if local:
		var voice := choose_local(local_firearms if firearm else local_foley)
		voice.stop();voice.stream = stream;voice.volume_db = linear_to_db(maxf(.01, volume)) - 2.0
		voice.pitch_scale = pitch;voice.set_meta("started", time);voice.play()
	else:
		var profile := profile_for(kind)
		var listener := listener_position()
		var distance := position.distance_to(listener)
		if distance > float(profile.distance):return
		var voice := choose_spatial(spatial_firearms if firearm else spatial_foley, position, volume, float(profile.unit))
		if voice == null:return
		var blocked := occluded(listener, position) if distance > 3.0 and kind != "near_miss" else false
		voice.stop();voice.stream = stream;voice.global_position = position
		voice.max_distance = float(profile.distance);voice.unit_size = float(profile.unit)
		voice.volume_db = linear_to_db(maxf(.01, volume)) - .8 - (7.0 if blocked else 0.0)
		voice.attenuation_filter_cutoff_hz = 1600.0 if blocked else float(profile.filter)
		voice.attenuation_filter_db = -18.0 if blocked else -9.0
		voice.pitch_scale = pitch;voice.set_meta("started", time);voice.play()
	if firearm and volume > .1:reflect(stream, position, volume, pitch)

func sound(kind: String, position: Vector3, volume := 1.0, priority := false) -> void:
	play_sound(kind, position, volume, priority)

func profile_for(kind: String) -> Dictionary:
	if kind in FIREARMS:return {"distance": 180.0, "unit": 12.0, "filter": 6500.0}
	if kind == "explosion":return {"distance": 200.0, "unit": 20.0, "filter": 5500.0}
	if kind in ["step", "step_gravel", "step_metal", "gear", "jump", "land"]:return {"distance": 28.0, "unit": 3.0, "filter": 4200.0}
	if kind in ["casing", "grenade_pin", "grenade_throw", "grenade_bounce"]:return {"distance": 22.0, "unit": 2.0, "filter": 5200.0}
	if kind.begins_with("impact_") or kind in ["ricochet", "near_miss"]:return {"distance": 48.0, "unit": 5.0, "filter": 6200.0}
	return {"distance": 55.0, "unit": 6.0, "filter": 5000.0}

func choose_local(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for voice in pool:
		if not voice.playing:return voice
	var quietest := pool[0]
	for voice in pool:
		if voice.volume_db < quietest.volume_db or (is_equal_approx(voice.volume_db, quietest.volume_db) and float(voice.get_meta("started", -1.0)) < float(quietest.get_meta("started", -1.0))):quietest = voice
	return quietest

func choose_spatial(pool: Array[AudioStreamPlayer3D], position: Vector3, volume: float, unit: float) -> AudioStreamPlayer3D:
	for voice in pool:
		if not voice.playing:return voice
	var listener := listener_position()
	var quietest := pool[0]
	var quietest_gain := INF
	for voice in pool:
		var gain := db_to_linear(voice.volume_db) * minf(1.0, voice.unit_size / maxf(1.0, voice.global_position.distance_to(listener)))
		if gain < quietest_gain:quietest = voice;quietest_gain = gain
	var incoming_gain := volume * minf(1.0, unit / maxf(1.0, position.distance_to(listener)))
	return quietest if incoming_gain >= quietest_gain * .8 else null

func listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else global_position

func occluded(listener: Vector3, position: Vector3) -> bool:
	if not is_inside_tree():return false
	var frame := Engine.get_physics_frames()
	if frame != occlusion_frame:occlusion_frame = frame;occlusion_queries = 0
	if occlusion_queries >= 3:return false
	occlusion_queries += 1
	var direction := (position - listener).normalized()
	var query := PhysicsRayQueryParameters3D.create(listener, position - direction * .35, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty()

func reflect(stream: AudioStream, position: Vector3, volume: float, pitch: float) -> void:
	var voice := choose_spatial(reflections, position, volume * .18, 14.0)
	if voice == null:return
	voice.stop();voice.stream = stream;voice.global_position = position
	voice.unit_size = 14.0;voice.max_distance = 100.0;voice.volume_db = linear_to_db(maxf(.001, volume)) - 15.0
	voice.attenuation_filter_cutoff_hz = 3500.0;voice.attenuation_filter_db = -12.0
	voice.pitch_scale = pitch;voice.set_meta("started", time);voice.play()

# Incoming bullets must cross the listener rather than start beside the weapon or
# merely end on the listener. One crack per .12 s keeps shotgun pellets bounded.
func bullet_pass(start: Vector3, end: Vector3, listener: Vector3, now: float) -> bool:
	if not initialized or replay_muted or now - last_near_miss < .12:return false
	var segment := end - start
	var length_squared := segment.length_squared()
	if length_squared < 9.0 or start.distance_squared_to(listener) < 9.0:return false
	var along := (listener - start).dot(segment) / length_squared
	if along <= 0.0 or along >= 1.0:return false
	var closest := start + segment * along
	if closest.distance_squared_to(end)<.35*.35:return false
	var distance := closest.distance_to(listener)
	if distance > 2.4:return false
	last_near_miss = now
	play_sound("near_miss", closest, lerpf(.68, .22, distance / 2.4))
	return true

func impact(surface: String, position: Vector3, direction: Vector3, normal: Vector3, now: float) -> void:
	if not initialized or replay_muted or now - last_impact < .045:return
	if listener_position().distance_squared_to(position) > 48.0 * 48.0:return
	last_impact = now
	var kind := "impact_" + surface
	play_sound(kind if sounds.has(kind) else "impact", position, .48 if surface != "flesh" else .35)
	if surface in ["metal", "concrete"] and absf(direction.dot(normal)) < .55 and now - last_ricochet >= .16:
		last_ricochet = now;play_sound("ricochet", position, .34)
