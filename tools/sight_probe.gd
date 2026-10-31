extends SceneTree

# Renders the first-person sight picture of a few weapons, fully aimed, at several rig
# fields of view (the rig's own FOV, not the world camera's), on a plain lit backdrop.
#   godot --script res://tools/sight_probe.gd -- [--weapons=lmg_l56,smg_v45:reflex] [--fovs=70,56,42]
# Stills in .artifacts/probes/sights/<weapon>_<fov>.png

func _initialize() -> void:call_deferred("probe")

func probe() -> void:
	var weapons:=["lmg_l56","ar_a4","smg_mp9","pistol_p9"];var fovs:=[70.0,56.0,42.0]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weapons="):weapons=Array(arg.trim_prefix("--weapons=").split(","))
		if arg.begins_with("--fovs="):fovs=Array(arg.trim_prefix("--fovs=").split(",")).map(func(v):return float(v))
	root.size=Vector2i(1280,720);root.unfocusable=true;root.mouse_passthrough=true
	var out:="res://.artifacts/probes/sights";DirAccess.make_dir_recursive_absolute(out)
	var catalog:=Catalog.new()
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("9fb3c4")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("c8d4de");env.ambient_light_energy=.8;environment.environment=env;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-40,30,0);root.add_child(sun)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.near=.02
	var target:=MeshInstance3D.new();var board:=BoxMesh.new();board.size=Vector3(1,1,.05);target.mesh=board;target.position=Vector3(0,0,-25);root.add_child(target)
	var actor:=Combatant.new();root.add_child(actor)
	var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=LoadoutDefinition.new();actor.setup(slot,catalog)
	var hands:=ViewModel.new();camera.add_child(hands)
	for entry in weapons:
		# "id" or "id:attachment+attachment".
		var id:String=entry.split(":")[0]
		var attachments:Array[String]=[]
		if ":" in entry:attachments.assign(entry.split(":")[1].split("+"))
		var definition:WeaponDefinition=catalog.weapons[id]
		var sidearm:=definition.category=="sidearm"
		if sidearm:slot.loadout.sidearm=StringName(id);slot.loadout.sidearm_attachments=attachments
		else:slot.loadout.primary=StringName(id);slot.loadout.primary_attachments=attachments
		actor.set_loadout(catalog)
		if sidearm:actor.switch_to(1,0.0)
		actor.ads=true;hands.refresh(actor);hands.shown=true;hands.blend=1.0
		camera.fov=rad_to_deg(2*atan(tan(deg_to_rad(75.0)*.5)/actor.weapon().magnification))
		for i in 30:
			hands.tick(1.0/60,1.0+float(i)/60,0.0)
			await process_frame
		for fov in fovs:
			hands.set_fov(fov)
			await process_frame;await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%d.png"%[out,entry.replace(":","_").replace("+","_"),int(fov)])
			print("SHOT ",entry," ",fov)
	print("SIGHT PROBE PASS")
	hands.free();actor.free()
	await process_frame
	quit()
