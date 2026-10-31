extends SceneTree

# Stable art-review views without a match, HUD or randomly positioned actors.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1600, 900)
	var arena: MapArena = load(MapCatalog.scene_path("glacier_peak")).instantiate()
	root.add_child(arena)
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.far = 900.0
	var folder: String = "res://.artifacts/screenshots/glacier_redesign"
	DirAccess.make_dir_recursive_absolute(folder)
	var views: Dictionary = MapCatalog.entry("glacier_peak").capture
	for label: String in ["blue_spawn", "red_spawn", "center_interior", "south_route", "elevated"]:
		var view: Dictionary = views[label]
		camera.position = MapCatalog.vec3(view.position)
		camera.look_at(MapCatalog.vec3(view.target))
		camera.fov = float(view.fov)
		for frame: int in 20:
			await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(folder + "/" + label + ".png")
	arena.free()
	await process_frame
	print("GLACIER PREVIEW PASS: 5 views")
	quit()
