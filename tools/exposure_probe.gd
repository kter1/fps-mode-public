extends SceneTree

# Calibrates a fixed exposure that matches what auto exposure settles on. For each capture
# view of a map it renders the settled auto-exposed frame, then the same view at a ladder
# of fixed exposure multipliers, and finds the multiplier with the same mean brightness.
#   godot --script res://tools/exposure_probe.gd -- --map=foundry
# JSON in .artifacts/probes/exposure-<map>.json

const LADDER := [.5,.65,.8,1.0,1.25,1.6,2.0,2.5,3.2]
var map_id := "foundry"

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_id=arg.trim_prefix("--map=")
	call_deferred("probe")

func probe() -> void:
	root.size=Vector2i(960,540);root.unfocusable=true;root.mouse_passthrough=true
	var catalog:=Catalog.new()
	var world:=MatchWorld.new();root.add_child(world)
	world.configure(catalog,map_id,catalog.starter_loadouts()[0],1,1201,true)
	while not world.ready_for_play:await physics_frame
	world.arena.apply_quality(1);world.countdown=0;world.set_physics_process(false)
	for actor in world.actors:actor.visible=false
	var attributes:CameraAttributesPractical
	for child in world.arena.get_children():
		if child is WorldEnvironment:attributes=child.camera_attributes as CameraAttributesPractical
	var camera:=Camera3D.new();camera.fov=75;world.add_child(camera);camera.current=true
	var capture:Dictionary=MapCatalog.entry(map_id).capture
	var results:={}
	var matches:Array[float]=[]
	for view in capture:
		camera.global_position=MapCatalog.vec3(capture[view].position);camera.look_at(MapCatalog.vec3(capture[view].target))
		attributes.auto_exposure_enabled=true;attributes.exposure_multiplier=1.0;attributes.auto_exposure_speed=40.0
		for frame in 45:await process_frame
		var auto:=await brightness()
		attributes.auto_exposure_enabled=false
		var ladder:=[]
		for multiplier in LADDER:
			attributes.exposure_multiplier=multiplier
			for frame in 3:await process_frame
			ladder.append(await brightness())
		# Interpolate (in log multiplier) where the fixed ladder crosses the auto brightness.
		var matched:float=LADDER[0] if auto<ladder[0] else LADDER[-1]
		for i in LADDER.size()-1:
			if auto>=ladder[i] and auto<=ladder[i+1]:
				var t:float=(auto-ladder[i])/maxf(ladder[i+1]-ladder[i],.0001)
				matched=exp(lerpf(log(LADDER[i]),log(LADDER[i+1]),t))
		results[view]={"auto":auto,"ladder":ladder,"matched":matched}
		matches.append(matched)
		print("VIEW ",view," auto=",snappedf(auto,.001)," matched=",snappedf(matched,.001))
	matches.sort()
	var median:=matches[matches.size()/2]
	results["median"]=median
	print("EXPOSURE ",map_id," median=",snappedf(median,.001)," all=",matches)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/probes")
	var file:=FileAccess.open("res://.artifacts/probes/exposure-"+map_id+".json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"\t"));file.close()
	world.queue_free();await process_frame;await process_frame
	quit()

# Mean display brightness (Rec. 709 luma of the output) over a sparse pixel grid.
func brightness() -> float:
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
	var total:=0.0;var count:=0
	for y in range(0,image.get_height(),6):
		for x in range(0,image.get_width(),6):
			var c:=image.get_pixel(x,y);total+=c.r*.2126+c.g*.7152+c.b*.0722;count+=1
	return total/count
