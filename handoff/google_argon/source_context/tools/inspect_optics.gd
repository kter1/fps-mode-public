extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,720)
	var app:Variant=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	await app.start_match()
	app.set_process(false);paused=true;app.screen="inspection";app.menu.hide()
	var actor:Combatant=app.match_world.actors[0];app.match_world.countdown=0
	app.camera.global_position=Vector3(-12,1.62,17);app.camera.rotation=Vector3(0,-PI*.5,0)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/optics")
	for optic in ["bare","reflex","holographic","scope"]:
		actor.slot.loadout.primary_attachments.assign([] if optic=="bare" else [optic])
		actor.set_loadout(app.catalog);actor.ads=true;app.hands.shown=true;app.hands.refresh(actor);app.hands.tick(1,app.match_world.clock,0)
		app.camera.fov=rad_to_deg(2*atan(tan(deg_to_rad(75.0)*.5)/actor.weapon().magnification))
		app.hud.show();app.hud.queue_redraw()
		await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/optics/"+optic+".png")
	print("OPTICS INSPECTION PASS / BARE, RED DOT, HOLOGRAPHIC, 3X")
	paused=false;await app.safe_quit()
