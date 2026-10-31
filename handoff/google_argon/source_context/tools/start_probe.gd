extends SceneTree

# Starts a match the way the menu does (backdrop camera first, then DEPLOY) and records
# the first seconds: the player's view, an overview from the menu camera's pose, and
# every effect that is visible (debris, blast flashes, burners, particle emitters).
#   godot --script res://tools/start_probe.gd -- --map=harbor [--seconds=24]
# Stills and a JSON log in .artifacts/probes/start-<map>/

var app: Control
var map_id := "harbor"
var seconds := 24.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_id=arg.trim_prefix("--map=")
		if arg.begins_with("--seconds="):seconds=float(arg.trim_prefix("--seconds="))
	call_deferred("probe")

func probe() -> void:
	root.size=Vector2i(1280,720)
	# Never take the keyboard or mouse from whoever is using this Mac.
	root.unfocusable=true;root.mouse_passthrough=true
	var out:="res://.artifacts/probes/start-"+map_id
	DirAccess.make_dir_recursive_absolute(out)
	app=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	for frame in 10:await process_frame
	var menu_pose:Transform3D=app.camera.global_transform
	# QA mode after the menu is up: no mouse capture, no pause on focus loss, bots fight.
	app.qa={"qa":"probe"}
	app.selected_map=map_id;app.start_match()
	while app.match_world==null or not app.match_world.ready_for_play or app.hud==null:await process_frame
	var world:MatchWorld=app.match_world
	world.qa_protect_player=true
	# A second view of the same world from where the menu camera stood.
	var overview:=SubViewport.new();overview.size=Vector2i(960,540);overview.world_3d=app.world_view.find_world_3d()
	overview.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(overview)
	var eye:=Camera3D.new();eye.far=900;overview.add_child(eye);eye.global_transform=menu_pose;eye.current=true
	var log:=[]
	var started:=Time.get_ticks_msec()
	var next:=0.0
	while true:
		var elapsed:=(Time.get_ticks_msec()-started)/1000.0
		if elapsed>=seconds:break
		if elapsed>=next:
			next+=1.0
			await RenderingServer.frame_post_draw
			app.world_view.get_texture().get_image().save_png("%s/player_%02d.png"%[out,int(elapsed)])
			overview.get_texture().get_image().save_png("%s/overview_%02d.png"%[out,int(elapsed)])
			log.append({"t":snappedf(elapsed,.01),"countdown":world.countdown,"clock":world.clock,"camera":str(app.camera.global_position),"effects":visible_effects(world.effects)})
		await process_frame
	var scene:=[]
	for node in root.find_children("*","GeometryInstance3D",true,false):
		var geometry:GeometryInstance3D=node
		if not geometry.is_visible_in_tree():continue
		var particles:=geometry is CPUParticles3D or geometry is GPUParticles3D
		var aabb:=geometry.get_aabb();var centre:=geometry.global_transform*aabb.get_center()
		if particles or centre.y>8.0 and aabb.size.length()>3.0 and geometry.material_override is ShaderMaterial:
			scene.append([str(geometry.get_path()).replace("/root/",""),geometry.get_class(),str(centre.snapped(Vector3.ONE*.1)),str(aabb.size.snapped(Vector3.ONE*.1))])
	var file:=FileAccess.open(out+"/log.json",FileAccess.WRITE);file.store_string(JSON.stringify({"menu_pose":str(menu_pose.origin),"samples":log,"scene":scene},"\t"));file.close()
	print("START PROBE PASS ",map_id)
	app.safe_quit()

func visible_effects(effects:MatchEffects) -> Array:
	var items:=[]
	for body in effects.debris:
		if body.node.visible:items.append(["debris",str(body.node.global_position.snapped(Vector3.ONE*.1)),snappedf(body.node.scale.x,.001)])
	for flash in effects.blast_flashes:
		if flash.node.visible:items.append(["blast_flash",str(flash.node.global_position.snapped(Vector3.ONE*.1)),snappedf(flash.node.scale.x,.001)])
	for light in effects.blast_lights:
		if light.node.visible:items.append(["blast_light",str(light.node.global_position.snapped(Vector3.ONE*.1)),snappedf(light.node.light_energy,.01)])
	for burner in effects.burners:
		if burner.root!=null and burner.root.visible:items.append(["burner",str(burner.root.global_position.snapped(Vector3.ONE*.1)),burner.until])
	for kind in effects.emitters:
		for particles:CPUParticles3D in effects.emitters[kind]:
			if particles.emitting:items.append([kind,str(particles.global_position.snapped(Vector3.ONE*.1)),snappedf(particles.scale_amount_max,.001)])
	for decal in effects.decals+effects.scorches:
		if decal.visible:items.append(["decal",str(decal.global_position.snapped(Vector3.ONE*.1))])
	return items
