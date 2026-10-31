extends SceneTree

# Repeatable real-app art fixture. Gameplay evidence remains in the separate
# input smoke / lifecycle reports; this image deliberately stages a close horde.
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var app: Variant=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	app.qa["qa"]="art-preview";app.qa["zombies_initialized"]=true
	app.get_window().unfocusable=true;app.get_window().mouse_passthrough=true
	await app.start_match()
	var world:=app.match_world as ZombiesWorld
	world.set_physics_process(false);world.clock=15;world.mode.round_number=5;world.mode.intermission=0;world.mode.points=6120;world.mode.remaining_to_spawn=0
	app.qa["qa"]="art-preview";app.qa["zombies_initialized"]=true
	var player: Combatant=world.actors[0];player.global_position=Vector3(-28,0,16);player.reset_physics_interpolation()
	app.look=Vector2(-.15,-.07);player.yaw=app.look.x;player.pitch=app.look.y
	var points: Array[Vector3]=[Vector3(-27.5,0,13.5),Vector3(-29.3,0,10),Vector3(-25.5,0,10.5),Vector3(-28.7,0,14.5)]
	for i in points.size():
		var enemy:=world.actors[i+1] as ZombieActor
		enemy.activate(points[i],world.clock,500,1,null);enemy.state="PURSUE";enemy.yaw=PI;enemy.rotation.y=PI
		if i==3:enemy.become_crawler()
		(enemy.visual as ZombieVisual).pose(.65+i*.23,i==3,1,i==0,false);enemy.reset_physics_interpolation()
	for frame in 30:await process_frame
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/zombie-art")
	root.get_texture().get_image().save_png("res://.artifacts/screenshots/zombie-art/in-game-"+app.selected_map+".png")
	print("ZOMBIES IN-GAME ART CAPTURE ",app.selected_map)
	await app.safe_quit()
