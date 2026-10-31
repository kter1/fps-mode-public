extends SceneTree

# Bakes each map's radar texture: an orthographic top-down render over the registry
# "minimap" bounds, desaturated and darkened for the HUD, with ground outside the
# playable extent flattened so the rim reads as the edge of the map. Output goes to
# content/minimaps/<id>.png; game/presentation/minimap.gd samples it.
# Run: python3 tools/dev.py minimap-bake [--map <id>]

const SIZE := 1024
const DIRECTORY := "res://content/minimaps/"
const VOID := Color(.03,.05,.07)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(SIZE,SIZE)
	var ids:Array[String]=[]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):ids.append(arg.trim_prefix("--map="))
	if ids.is_empty():ids=MapCatalog.ids()
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	for id in ids:await bake(id)
	print("MINIMAP BAKE PASS ",", ".join(ids));quit()

func bake(id: String) -> void:
	var entry:=MapCatalog.entry(id)
	var bounds:Array=entry.minimap.bounds
	var x0:=float(bounds[0]);var z0:=float(bounds[1]);var x1:=float(bounds[2]);var z1:=float(bounds[3])
	var extent:=MapCatalog.vec2(entry.extent)
	var arena:MapArena=load(MapCatalog.scene_path(id)).instantiate();root.add_child(arena)
	# Plans read better without the haze between the camera and the ground.
	var environment:WorldEnvironment=arena.get_node_or_null("Environment")
	if environment!=null:environment.environment.fog_enabled=false;environment.environment.volumetric_fog_enabled=false
	var centre:=Vector3((x0+x1)*.5,0,(z0+z1)*.5)
	var camera:=Camera3D.new();root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=x1-x0;camera.near=1;camera.far=700
	camera.position=centre+Vector3.UP*300;camera.look_at(centre,Vector3.FORWARD);camera.current=true
	for frame in 6:await process_frame
	RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image()
	if image.get_width()!=SIZE or image.get_height()!=SIZE:image.resize(SIZE,SIZE)
	image.convert(Image.FORMAT_RGBA8)
	for y in SIZE:
		var z:=z0+(y+.5)/SIZE*(z1-z0)
		for x in SIZE:
			var world_x:=x0+(x+.5)/SIZE*(x1-x0)
			var colour:Color=image.get_pixel(x,y)
			if absf(world_x)>extent.x*.5 or absf(z)>extent.y*.5:colour=VOID
			else:
				# Keep 30% of the colour, then darken; RGB only so alpha stays opaque.
				var luminance:=colour.get_luminance()
				colour=Color(lerpf(luminance,colour.r,.3)*.62,lerpf(luminance,colour.g,.3)*.62,lerpf(luminance,colour.b,.3)*.62)
			image.set_pixel(x,y,colour)
	image.save_png(DIRECTORY+id+".png")
	arena.free();camera.free()
	await process_frame
