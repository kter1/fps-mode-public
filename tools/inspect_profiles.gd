extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,720)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(2,0,0);camera.look_at(Vector3.ZERO);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.5;camera.current=true
	var environment:=WorldEnvironment.new();var sky:=Environment.new();sky.background_mode=Environment.BG_COLOR;sky.background_color=Color("647585");sky.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;sky.ambient_light_energy=.8;sky.ambient_light_color=Color("cad8e1");environment.environment=sky;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-25,0);sun.light_energy=1.6;root.add_child(sun)
	var stage:=Node3D.new();root.add_child(stage);var catalog:=Catalog.new();var row:=0
	for id in ["smg_mp9","smg_v45","smg_p90"]:
		var height:=.48-row*.48;var gun:=ModelFactory.weapon(catalog.weapons[id]);stage.add_child(gun);gun.position.y=height
		for front in [true,false]:ModelFactory.primitive(stage,Vector3(.03,.03,.03),Vector3(0,height,-.52 if front else .52),Color("71bcff") if front else Color("ff8878"))
		var label:=Label.new();label.text=id+"  /  BLUE = FORWARD (-Z)";label.position=camera.unproject_position(Vector3(0,height+.15,-.6));root.add_child(label);row+=1
	for frame in 4:await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://.artifacts/screenshots/smg-profiles.png")
	stage.free();ModelFactory.sources.clear();await process_frame;quit()
