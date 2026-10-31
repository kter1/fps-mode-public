extends SceneTree

# Finds z-fighting: renders a map top-down (orthographic) and from a few oblique views at
# slightly different camera distances. Coplanar surfaces flip between frames where solid
# geometry does not. Writes a flicker mask and the world positions of the worst spots.
#   godot --script res://tools/zfight_probe.gd -- --map=village
# Output: .artifacts/probes/zfight-<map>.png and .json

func _initialize() -> void:call_deferred("probe")

func probe() -> void:
	var id:="village"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):id=arg.trim_prefix("--map=")
	root.size=Vector2i(1024,1024);root.unfocusable=true;root.mouse_passthrough=true
	var arena:MapArena=load(MapCatalog.scene_path(id)).instantiate();root.add_child(arena)
	arena.fix_exposure()
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var extent:Vector2=arena.definition.extent
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=maxf(extent.x,extent.y)+16;camera.near=.05;camera.far=400
	for frame in 10:await process_frame
	var frames:Array[Image]=[]
	for k in 6:
		camera.global_transform=Transform3D(Basis.looking_at(Vector3.DOWN,Vector3.FORWARD),Vector3(0,80+k*7.3,0))
		camera.near=.05+k*.37
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8);frames.append(image)
	var w:=frames[0].get_width();var h:=frames[0].get_height()
	var mask:=Image.create(w,h,false,Image.FORMAT_RGB8)
	var hot:={}
	# Orthographic size is the vertical extent.
	var scale:=camera.size/float(h)
	for y in h:
		for x in w:
			var low:=1.0;var high:=0.0
			for image in frames:
				var v:=image.get_pixel(x,y).get_luminance();low=minf(low,v);high=maxf(high,v)
			var spread:=high-low
			mask.set_pixel(x,y,Color(spread*3,spread*3,spread*3) if spread>.12 else frames[0].get_pixel(x,y)*.35)
			if spread>.12:
				var cell:=Vector2i(floori((x-w*.5)*scale/4.0),floori((y-h*.5)*scale/4.0))
				hot[cell]=int(hot.get(cell,0))+1
	DirAccess.make_dir_recursive_absolute("res://.artifacts/probes")
	mask.save_png("res://.artifacts/probes/zfight-"+id+".png")
	var cells:=hot.keys();cells.sort_custom(func(a,b):return hot[a]>hot[b])
	var spots:=[]
	for cell in cells.slice(0,25):
		# Image +x is world +x, image +y is world +z (camera looks down with -Z up the image).
		spots.append({"x":cell.x*4+2,"z":cell.y*4+2,"pixels":hot[cell]})
	var file:=FileAccess.open("res://.artifacts/probes/zfight-"+id+".json",FileAccess.WRITE);file.store_string(JSON.stringify(spots,"\t"));file.close()
	print("ZFIGHT ",id," flicker cells=",cells.size()," top=",spots.slice(0,10))
	arena.free();await process_frame
	quit()
