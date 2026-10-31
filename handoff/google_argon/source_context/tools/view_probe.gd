extends SceneTree

# Renders a baked map from a list of camera views and saves each shot plus
# 2 x 2 contact sheets. Run through tools/dev.py's engine() (render lock):
#   --map=<id> --views=<json file: [{name,pos:[x,y,z],look:[x,y,z],fov?}]> --out=<dir> [--wait=<frames>]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var id:=MapCatalog.default_id();var views_path:="";var out:="res://.artifacts/screenshots/probe";var wait:=24
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):id=arg.trim_prefix("--map=")
		elif arg.begins_with("--views="):views_path=arg.trim_prefix("--views=")
		elif arg.begins_with("--out="):out=arg.trim_prefix("--out=")
		elif arg.begins_with("--wait="):wait=int(arg.trim_prefix("--wait="))
	root.size=Vector2i(960,540)
	var views:Array=JSON.parse_string(FileAccess.get_file_as_string(views_path))
	var arena:MapArena=load(MapCatalog.scene_path(id)).instantiate();root.add_child(arena)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true;camera.near=.05;camera.far=400
	DirAccess.make_dir_recursive_absolute(out)
	for frame in 8:await process_frame
	var images:Array[Image]=[]
	for view in views:
		var pos:=Vector3(view.pos[0],view.pos[1],view.pos[2]);var look:=Vector3(view.look[0],view.look[1],view.look[2])
		camera.position=pos;camera.look_at(look,Vector3.UP);camera.fov=float(view.get("fov",70))
		for frame in wait:await process_frame
		RenderingServer.force_draw(false)
		var image:=root.get_texture().get_image()
		image.save_png("%s/%s.png"%[out,view.name]);images.append(image)
	var sheet_index:=0
	for start in range(0,images.size(),4):
		var sheet:=Image.create(1920,1080,false,Image.FORMAT_RGB8)
		for k in range(start,mini(start+4,images.size())):
			var image:=images[k];image.convert(Image.FORMAT_RGB8)
			sheet.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i((k-start)%2*960,(k-start)/2*540))
		sheet.save_png("%s/sheet_%02d.png"%[out,sheet_index]);sheet_index+=1
	arena.free();await process_frame;print("VIEW PROBE PASS ",id," ",images.size());quit()
