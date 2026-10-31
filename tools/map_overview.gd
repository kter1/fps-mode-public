extends SceneTree

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,960)
	var id:=MapCatalog.default_id()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):id=arg.trim_prefix("--map=")
	var arena:MapArena=load(MapCatalog.scene_path(id)).instantiate();root.add_child(arena)
	# Top-down plans read better without the 300 m of haze between camera and ground.
	var environment:WorldEnvironment=arena.get_node_or_null("Environment")
	if environment!=null:environment.environment.fog_enabled=false;environment.environment.volumetric_fog_enabled=false
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=85 if id in MapCatalog.ids_for_mode("zombies") else 125;camera.far=700;camera.position=Vector3(0,300,0);camera.look_at(Vector3.ZERO,Vector3.FORWARD);camera.current=true
	var survival:=id in MapCatalog.ids_for_mode("zombies")
	if survival:
		for child in arena.nav_region.get_children():
			if str(child.name).begins_with("Roof"):child.hide()
	var title:=Label.new();title.text=arena.definition.display_name.to_upper()+(" / ZOMBIES SURVIVAL" if survival else " / %d v %d / ORIGINAL MAP"%[MatchWorld.TEAM_SIZE,MatchWorld.TEAM_SIZE]);title.position=Vector2(24,20);title.add_theme_font_size_override("font_size",28);root.add_child(title)
	var zones:Array[Dictionary]=[
		{"text":"BLUE DEPLOYMENT","point":arena.definition.spawns_blue[0]+Vector3.UP*8,"color":Color("70c6ff")},
		{"text":"RED DEPLOYMENT","point":arena.definition.spawns_red[0]+Vector3.UP*8,"color":Color("ff9584")}]
	if survival:
		zones.clear()
		for zone in arena.definition.zombies.zones:zones.append({"text":str(zone.name).to_upper(),"point":MapCatalog.vec3(zone.center),"color":Color("e8d8a7")})
	# Area labels from the map's registry entry.
	for item in MapCatalog.entry(id).get("overview",[]):zones.append({"text":str(item.text),"point":MapCatalog.vec3(item.point),"color":MapCatalog.color(item.get("color"))})
	for zone in zones:
		var label:=Label.new();label.text=zone.text;label.position=camera.unproject_position(zone.point)+Vector2(-85,0);label.add_theme_font_size_override("font_size",16);label.add_theme_color_override("font_color",zone.color);label.add_theme_color_override("font_outline_color",Color("18232d"));label.add_theme_constant_override("outline_size",6);root.add_child(label)
	for frame in 6:await process_frame
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/overviews")
	root.get_texture().get_image().save_png("res://.artifacts/screenshots/overviews/"+id+".png")
	arena.free();await process_frame;print("MAP OVERVIEW PASS ",id);quit()
