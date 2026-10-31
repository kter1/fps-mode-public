extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.fov=38
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("222a2d");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("aebdca");env.ambient_light_energy=.6;env.tonemap_mode=Environment.TONE_MAPPER_AGX;environment.environment=env;root.add_child(environment)
	var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-35,-145,0);sun.light_energy=2
	var floor:=Node3D.new();root.add_child(floor);ZombieVisual.part(floor,Vector3(15,.05,15),Vector3(0,-.03,0),Color("545651"))
	var zombies: Array[ZombieVisual]=[]
	for i in 3:
		var zombie:=ZombieVisual.new();root.add_child(zombie);zombie.build(i);zombie.position=Vector3((i-1)*1.3,0,0);zombies.append(zombie)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/zombie-art")
	for pose in ["front","side","crawl","portrait","attack"]:
		for zombie in zombies:zombie.pose(.45,pose=="crawl",1.0,pose=="attack",false)
		var target:=Vector3(0,.65 if pose=="crawl" else 1,0)
		camera.position=target+Vector3(4,1,0) if pose=="side" else target+Vector3(.5,.4,-5.5)
		if pose=="portrait":
			for i in 3:zombies[i].visible=i==1
			target=Vector3(0,1.45,0);camera.position=Vector3(.25,1.55,-1.3)
		else:
			for zombie in zombies:zombie.visible=true
		camera.look_at(target)
		for frame in 8:await process_frame
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/zombie-art/"+pose+".png")
		print("ZOMBIE ART CAPTURE ",pose)
	quit()
