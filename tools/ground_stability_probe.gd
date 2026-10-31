extends SceneTree

# Track the same ground points from translated cameras. A UV diagnostic uses
# the actual ground shader's coordinate path, isolating camera-driven swimming
# from lighting, mip filtering and ordinary perspective motion.
const OUT := "res://.artifacts/probes/ground-stability"
var camera:Camera3D
var report:Array=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Rendered display required");quit(2);return
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(960,540);root.unfocusable=true;root.mouse_passthrough=true
	var material:=MapSurfaces.new().ground_material("concrete_floor","asphalt","gravel","grass")
	var current:=FileAccess.get_file_as_string("res://content/materials/ground.gdshader")
	var sources:={"current":current}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--baseline="):sources["baseline"]=FileAccess.get_file_as_string(arg.trim_prefix("--baseline="))
	var mesh:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(80,80);mesh.mesh=plane
	mesh.material_override=material;root.add_child(mesh)
	camera=Camera3D.new();camera.near=.02;camera.fov=75;root.add_child(camera);camera.current=true
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var points:Array[Vector3]=[]
	for z in range(-12,1,2):
		for x in range(-4,5,2):points.append(Vector3(x,0,z))
	for label in sources:
		var code:String=sources[label]
		code=code.replace("render_mode diffuse_burley, specular_schlick_ggx;","render_mode unshaded;")
		code=code.insert(code.rfind("}"),"\n ALBEDO=vec3(uv.x * 0.8 + 0.1, uv.y * 0.8 + 0.1, 0.0);\n")
		var shader:=Shader.new();shader.code=code;material.shader=shader
		material.set_shader_parameter("parallax_depth",.035)
		var height:=Image.create(4,4,false,Image.FORMAT_RGB8);height.fill(Color.BLACK)
		material.set_shader_parameter("base_height",ImageTexture.create_from_image(height))
		var samples:Array=[]
		for step in 9:
			camera.position=Vector3(-8.0+step*2.0,1.62,7.0);camera.look_at(Vector3(0,0,-5))
			for frame in 4:await process_frame
			RenderingServer.force_draw(false)
			var image:=root.get_texture().get_image()
			var colors:Array[Color]=[]
			for point in points:
				var pixel:=camera.unproject_position(point)*Vector2(image.get_size())/root.get_visible_rect().size-Vector2(.5,.5)
				var x:=clampi(floori(pixel.x),0,958);var y:=clampi(floori(pixel.y),0,538)
				var top:=image.get_pixel(x,y).lerp(image.get_pixel(x+1,y),pixel.x-x)
				var bottom:=image.get_pixel(x,y+1).lerp(image.get_pixel(x+1,y+1),pixel.x-x)
				colors.append(top.lerp(bottom,pixel.y-y))
			samples.append(colors)
			if step in [0,4,8]:image.save_png(OUT+"/"+str(label)+"-"+str(step)+".png")
		var sum:=0.0;var maximum:=0.0
		for index in points.size():
			var low:=Vector2.ONE;var high:=Vector2.ZERO
			for sample in samples:
				var color:Color=sample[index];low=low.min(Vector2(color.r,color.g));high=high.max(Vector2(color.r,color.g))
			var spread:=(high-low).length();sum+=spread;maximum=maxf(maximum,spread)
		var result:={"variant":label,"mean_ground_coordinate_drift":sum/points.size(),"max_ground_coordinate_drift":maximum,"tracked_points":points.size(),"camera_samples":samples.size()}
		report.append(result);print("GROUND STABILITY ",JSON.stringify(result))
	var current_result:Dictionary=report.filter(func(row:Dictionary):return row.variant=="current")[0]
	var stable:bool=current_result.mean_ground_coordinate_drift<.005 and current_result.max_ground_coordinate_drift<.01
	var file:=FileAccess.open(OUT+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":stable,"variants":report},"\t"));file.close()
	print("GROUND COORDINATES ","PASS" if stable else "FAIL")
	quit(0 if stable else 1)
