extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,720)
	var app:Variant=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	app.profile.directory="res://.artifacts/controls-profile"
	app.settings_menu(false)
	for i in 5:await process_frame
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/controls")
	root.get_texture().get_image().save_png("res://.artifacts/screenshots/controls/settings_720p.png")
	print("CONTROLS SCREEN CAPTURE PASS")
	await app.safe_quit()
