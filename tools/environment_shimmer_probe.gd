extends SceneTree

# Pure camera rotation lets us reproject pixels without a depth approximation.
# Compare the existing spatial AA with temporal AA on every registered map.
var report: Array = []
var camera: Camera3D
var output := "res://.artifacts/probes/environment-shimmer"

func _initialize() -> void:call_deferred("run")

func capture() -> Image:
	await process_frame
	RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image()
	image.convert(Image.FORMAT_L8)
	return image

func measure(temporal: bool, label: String) -> Dictionary:
	root.use_taa=temporal
	root.msaa_3d=Viewport.MSAA_4X if temporal else Viewport.MSAA_DISABLED
	root.use_occlusion_culling=false
	root.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED if temporal else Viewport.SCREEN_SPACE_AA_SMAA
	var initial:=camera.rotation
	for frame in 20:await capture()
	var previous:=await capture()
	var previous_transform:=camera.global_transform
	var total:=0.0;var unstable:=0;var count:=0
	for frame in 12:
		camera.rotation.y+=deg_to_rad(.12)
		var current:=await capture()
		var current_transform:=camera.global_transform
		var data:=current.get_data();var old:=previous.get_data()
		var reprojection:=previous_transform.basis.inverse()*current_transform.basis
		var focal:=270.0/tan(deg_to_rad(camera.fov*.5))
		for y in range(60,480,2):
			for x in range(80,880,2):
				var direction:=reprojection*Vector3((x+.5-480.0)/focal,-(y+.5-270.0)/focal,-1.0)
				var pixel:=Vector2(480.0+focal*direction.x/-direction.z,270.0-focal*direction.y/-direction.z)-Vector2(.5,.5)
				var px:=floori(pixel.x);var py:=floori(pixel.y)
				if px<0 or py<0 or px>=959 or py>=539:continue
				var fx:=pixel.x-px;var fy:=pixel.y-py
				var a:=lerpf(old[py*960+px],old[py*960+px+1],fx)
				var b:=lerpf(old[(py+1)*960+px],old[(py+1)*960+px+1],fx)
				var difference:=absf(data[y*960+x]-lerpf(a,b,fy))
				total+=difference;count+=1
				if difference>18.0:unstable+=1
		previous=current;previous_transform=current_transform
	var screenshot:=root.get_texture().get_image()
	screenshot.save_png(output+"/"+label+".png")
	camera.rotation=initial
	return {"mean_luma_difference":total/count,"unstable_fraction":float(unstable)/count,"samples":count}

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Rendered display required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(960,540);root.unfocusable=true;root.mouse_passthrough=true
	camera=Camera3D.new();camera.near=.02;camera.far=900;camera.fov=75
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(camera);camera.current=true
	var selected:=MapCatalog.ids()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):selected.assign([arg.trim_prefix("--map=")])
	for id in selected:
		var arena:MapArena=load(MapCatalog.scene_path(id)).instantiate();root.add_child(arena)
		arena.apply_quality(1)
		var captures:Dictionary=MapCatalog.entry(id).capture
		for view in ["first_person","north_route"]:
			if not captures.has(view):continue
			camera.position=MapCatalog.vec3(captures[view].position);camera.look_at(MapCatalog.vec3(captures[view].target))
			var spatial:=await measure(false,id+"-"+view+"-spatial")
			var temporal:=await measure(true,id+"-"+view+"-temporal")
			var result:={"map":id,"view":view,"spatial":spatial,"temporal":temporal}
			report.append(result);print("SHIMMER ",JSON.stringify(result))
		arena.free();await process_frame
	var file:=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	quit()
