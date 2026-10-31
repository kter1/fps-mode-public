extends SceneTree

# Measures real-time sun-shadow stability. The camera pitches by a fixed whole-pixel
# step between frames (pure rotation: the image moves rigidly), so after undoing that
# shift what remains is shadow swimming/flicker. A variant with sun shadows off gives the
# floor; the muzzle-flash and recoil variants test whether firing disturbs shadows.
#   godot --script res://tools/shadow_probe.gd -- --map=foundry [--variants=base,bias]
# JSON in .artifacts/probes/shadow-<map>.json

var world: MatchWorld
var camera: Camera3D
var map_id := "foundry"
var names: PackedStringArray = []
const STEP_PX := 2.0
const FRAMES := 6

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_id = arg.trim_prefix("--map=")
		if arg.begins_with("--variants="):names = arg.trim_prefix("--variants=").split(",")
	call_deferred("probe")

func variants() -> Dictionary:
	return {
		"base": {},
		"angular_zero": {"angular": 0.0},
		"angular_low": {"angular": .15},
		"flash_lights": {"flash": true},
		"bias_low": {"bias": .01, "normal_bias": .6},
		"bias_high": {"bias": .06, "normal_bias": 2.0},
		"blur_half": {"blur": .5},
		"blur_two": {"blur": 2.0},
		"atlas_4096": {"atlas": 4096},
		"filter_medium": {"filter": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM},
		"filter_low": {"filter": RenderingServer.SHADOW_QUALITY_SOFT_LOW},
		"filter_hard": {"filter": RenderingServer.SHADOW_QUALITY_HARD},
		"splits_4": {"splits": DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS},
		"no_blend": {"blend": false},
		"far_80": {"distance": 80.0},
	}

func probe() -> void:
	root.size = Vector2i(1280, 720)
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	var catalog := Catalog.new()
	world = MatchWorld.new();root.add_child(world)
	world.configure(catalog, map_id, catalog.starter_loadouts()[0], 1, 1201, true)
	while not world.ready_for_play:await physics_frame
	world.arena.apply_quality(1)
	RenderingServer.directional_shadow_atlas_set_size(2048, false)
	world.countdown = 0;world.set_physics_process(false)
	for actor in world.actors:actor.visible = false
	for child in world.arena.get_children():
		if child is WorldEnvironment:
			var attributes := child.camera_attributes as CameraAttributesPractical
			if attributes != null:attributes.auto_exposure_enabled = false
	camera = Camera3D.new();camera.fov = 70;world.add_child(camera);camera.current = true
	var sun: DirectionalLight3D = world.arena.get_node("Sun")
	var capture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/manifest/map_list/%s.json" % map_id)).capture
	var views: Array = []
	for key in ["first_person", "north_route", "south_route"]:
		if capture.has(key):views.append(capture[key])
	var table := variants()
	var results := {}
	for name in table:
		if not names.is_empty() and not names.has(name):continue
		reset(sun)
		var option: Dictionary = table[name]
		if option.has("angular"):sun.light_angular_distance = option.angular
		if option.has("bias"):sun.shadow_bias = option.bias
		if option.has("normal_bias"):sun.shadow_normal_bias = option.normal_bias
		if option.has("blur"):sun.shadow_blur = option.blur
		if option.has("splits"):sun.directional_shadow_mode = option.splits
		if option.has("blend"):sun.directional_shadow_blend_splits = option.blend
		if option.has("pancake"):sun.directional_shadow_pancake_size = option.pancake
		if option.has("distance"):sun.directional_shadow_max_distance = option.distance
		if option.has("atlas"):RenderingServer.directional_shadow_atlas_set_size(option.atlas, false)
		if option.has("filter"):RenderingServer.directional_soft_shadow_filter_set_quality(option.filter)
		var scores := []
		for view in views:
			var from := MapCatalog.vec3(view.position);var to := MapCatalog.vec3(view.target)
			scores.append(await measure(sun, from, to, option.get("flash", false)))
		var mad := 0.0;var bad := 0.0
		for score in scores:mad += score.mad;bad += score.bad
		results[name] = {"mad": mad / scores.size(), "bad": bad / scores.size(), "views": scores}
		print("VARIANT ", name, " mad=", snappedf(mad / scores.size(), .001), " bad=", snappedf(bad / scores.size() * 100, .0001), "%")
	var file := FileAccess.open("res://.artifacts/probes/shadow-" + map_id + ".json", FileAccess.WRITE);file.store_string(JSON.stringify(results, "\t"));file.close()
	quit()

func reset(sun: DirectionalLight3D) -> void:
	sun.light_angular_distance = .55;sun.shadow_enabled = true;sun.shadow_bias = .03;sun.shadow_normal_bias = 1.2;sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS;sun.directional_shadow_blend_splits = true
	sun.directional_shadow_pancake_size = 20.0;sun.directional_shadow_max_distance = 45
	RenderingServer.directional_shadow_atlas_set_size(2048, false)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)

func measure(sun: DirectionalLight3D, from: Vector3, to: Vector3, flash: bool) -> Dictionary:
	camera.global_position = from;camera.look_at(to)
	var base_pitch := camera.rotation.x
	var step := atan(STEP_PX / (360.0 / tan(deg_to_rad(35))))
	for i in 6:await process_frame
	var frames: Array[PackedByteArray] = []
	var masks: Array[PackedByteArray] = []
	var size := Vector2i.ZERO
	for i in FRAMES:
		camera.rotation.x = base_pitch - step * i
		if flash:
			for k in 4:world.effects.world_flash(from + Vector3(1.2 + k * .1, -.3, -1.5), Vector3.FORWARD)
		sun.shadow_enabled = false
		await process_frame;await process_frame
		var off := root.get_viewport().get_texture().get_image();off.convert(Image.FORMAT_L8)
		sun.shadow_enabled = true
		await process_frame;await process_frame
		var on := root.get_viewport().get_texture().get_image();on.convert(Image.FORMAT_L8)
		size = on.get_size();frames.append(on.get_data())
		var a := on.get_data();var b := off.get_data();var mask := PackedByteArray();mask.resize(a.size())
		for k in a.size():mask[k] = 1 if absi(int(a[k]) - int(b[k])) > 14 else 0
		masks.append(mask)
	var total := 0.0;var bad := 0.0;var pairs := 0
	for i in range(1, FRAMES):
		var best := INF;var best_bad := 0.0
		for shift in range(0, 5):
			var result := compare(frames[i - 1], frames[i], masks[i], size, shift)
			if result.x < best:best = result.x;best_bad = result.y
		total += best;bad += best_bad;pairs += 1
	return {"mad": total / pairs, "bad": bad / pairs}

# Over the central crop, restricted to shadowed pixels (where the sun shadow changes the
# image): mean absolute difference and share differing by > 18 levels, with frame b
# shifted `shift` pixels down against frame a.
func compare(a: PackedByteArray, b: PackedByteArray, mask: PackedByteArray, size: Vector2i, shift: int) -> Vector2:
	var x0 := 160;var x1 := size.x - 160;var y0 := 120;var y1 := size.y - 120
	var sum := 0;var count := 0;var over := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			if mask[y * size.x + x] == 0:continue
			var difference := absi(int(a[(y + shift) * size.x + x]) - int(b[y * size.x + x]))
			sum += difference;count += 1
			if difference > 18:over += 1
	if count == 0:return Vector2.ZERO
	return Vector2(float(sum) / count, float(over) / count)
