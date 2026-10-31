extends SceneTree

# Regression for camera-dependent fading and movement of static airport geometry.
# Headless checks all geometry/material state while walking three camera routes.
# Add --rendered for walk screenshots and a same-view near-plane depth diagnostic.
#   godot --headless --script res://tools/airport_stability_probe.gd
#   godot --script res://tools/airport_stability_probe.gd -- --rendered --label=after

const ROUTES := [
	["terminal",Vector3(-37,1.62,-31),Vector3(-13,1.62,-31),Vector3(5,1.62,-26)],
	["apron",Vector3(-9,1.62,5),Vector3(-9,1.62,27),Vector3(15,3.2,20)],
	["cabin",Vector3(15,4.22,10),Vector3(15,4.22,28),Vector3(15,4.22,31)]
]

var checks: Array[Dictionary] = []
var rendered := false
var output := "res://.artifacts/probes/airport-stability"

func _initialize() -> void:call_deferred("run")

func verify(condition: bool, name: String, details: Array = []) -> void:
	checks.append({"name":name,"passed":condition,"detail_count":details.size(),"details":details.slice(0,20)})
	print("PASS " if condition else "FAIL ",name," ",details.slice(0,20) if not condition else "")

func materials_of(geometry: GeometryInstance3D) -> Array[Material]:
	var materials: Array[Material] = []
	if geometry.material_override!=null:materials.append(geometry.material_override)
	if geometry.material_overlay!=null:materials.append(geometry.material_overlay)
	if geometry is MeshInstance3D and geometry.mesh!=null:
		for surface in geometry.mesh.get_surface_count():
			var material:Material=geometry.get_active_material(surface)
			if material!=null and material not in materials:materials.append(material)
	elif geometry is MultiMeshInstance3D and geometry.material_override==null and geometry.multimesh!=null and geometry.multimesh.mesh!=null:
		for surface in geometry.multimesh.mesh.get_surface_count():
			var material:Material=geometry.multimesh.mesh.surface_get_material(surface)
			if material!=null and material not in materials:materials.append(material)
	return materials

func material_state(material: Material) -> Dictionary:
	var state:={"id":material.get_instance_id(),"priority":material.render_priority}
	if material is BaseMaterial3D:
		state.merge({"alpha":material.albedo_color.a,"transparency":material.transparency,
			"distance_fade":material.distance_fade_mode,"cull":material.cull_mode,
			"depth_draw":material.depth_draw_mode,"no_depth_test":material.no_depth_test})
	elif material is ShaderMaterial:
		state["shader"]=material.shader.get_instance_id() if material.shader!=null else 0
		for property in material.get_property_list():
			if str(property.name).begins_with("shader_parameter/"):state[property.name]=material.get(property.name)
	return state

func snapshot(arena: MapArena) -> Dictionary:
	var states:={}
	for node in arena.find_children("*","GeometryInstance3D",true,false):
		var geometry:GeometryInstance3D=node
		var material_states:Array=[]
		for material in materials_of(geometry):material_states.append(material_state(material))
		var state:={"transform":geometry.global_transform,"visible":geometry.visible,
			"visible_in_tree":geometry.is_visible_in_tree(),"transparency":geometry.transparency,
			"range_begin":geometry.visibility_range_begin,"range_end":geometry.visibility_range_end,
			"fade_mode":geometry.visibility_range_fade_mode,"materials":material_states}
		if geometry is MeshInstance3D:state["mesh"]=geometry.mesh.get_instance_id() if geometry.mesh!=null else 0
		if geometry is MultiMeshInstance3D and geometry.multimesh!=null:
			state["instance_count"]=geometry.multimesh.instance_count
			state["instance_buffer_hash"]=hash(geometry.multimesh.buffer)
		states[str(arena.get_path_to(geometry))]=state
	return states

func repeated_fan_triangles(arena: MapArena) -> Array:
	var triangles:={};var repeated:Array=[]
	for node in arena.find_children("*","MeshInstance3D",true,false):
		var geometry:MeshInstance3D=node
		if geometry.mesh==null or not str(geometry.get_parent().name).begins_with("FanBlade"):continue
		var vertices:=geometry.mesh.get_faces()
		for index in range(0,vertices.size(),3):
			var points:Array[String]=[]
			for offset in 3:points.append(str((geometry.global_transform*vertices[index+offset]).snapped(Vector3.ONE*.0001)))
			points.sort()
			var key:="|".join(points)
			if triangles.has(key):repeated.append(str(arena.get_path_to(geometry))+" overlaps "+triangles[key])
			else:triangles[key]=str(arena.get_path_to(geometry))
	return repeated

func capture(camera: Camera3D, path: String) -> Image:
	# Publish updated camera data before the forced QA draw. It also works when
	# the game is not the foreground application.
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
	return image

func depth_diagnostic(camera: Camera3D, label: String) -> Dictionary:
	# Camera pose stays fixed. Moving only its near clip plane changes depth
	# precision, exposing overlapping surfaces without introducing walk parallax.
	camera.near=.025
	var close:=await capture(camera,output+"/"+label+"-near-025.png")
	camera.near=.12
	var farther:=await capture(camera,output+"/"+label+"-near-120.png")
	camera.near=.025
	var changed:=0;var total:=close.get_width()*close.get_height();var sum:=0.0
	var mask:=Image.create(close.get_width(),close.get_height(),false,Image.FORMAT_RGB8)
	for y in close.get_height():
		for x in close.get_width():
			var a:=close.get_pixel(x,y);var b:=farther.get_pixel(x,y)
			var difference:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			sum+=difference
			if difference>.12:changed+=1
			mask.set_pixel(x,y,Color(difference,difference,difference)*3.0)
	mask.save_png(output+"/"+label+"-depth-difference.png")
	return {"route":label,"changed_pixels":changed,"pixels":total,
		"changed_fraction":float(changed)/total,"mean_max_channel_difference":sum/total}

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--rendered":rendered=true
		elif arg.begins_with("--label="):output+="-"+arg.trim_prefix("--label=")
	if rendered and DisplayServer.get_name()=="headless":
		push_error("--rendered needs a rendering display driver");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(960,540);root.unfocusable=true;root.mouse_passthrough=true
	var arena:MapArena=load(MapCatalog.scene_path("airport")).instantiate();root.add_child(arena)
	arena.apply_quality(1)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	camera.fov=75;camera.near=.025;camera.far=650
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	for frame in 5:await physics_frame
	var initial:=snapshot(arena)
	var fading:Array=[];var material_fades:Array=[];var translucent:Array=[];var opaque_states:Array=[];var architecture_states:Array=[]
	for path in initial:
		var state:Dictionary=initial[path]
		if state.range_begin!=0.0 or state.range_end!=0.0 or state.fade_mode!=GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:fading.append(path)
		if state.transparency!=0.0:translucent.append(path)
		for material in state.materials:
			if material.get("distance_fade",BaseMaterial3D.DISTANCE_FADE_DISABLED)!=BaseMaterial3D.DISTANCE_FADE_DISABLED:material_fades.append(path)
			# Imported cutout foliage and translucent prop parts retain their
			# authored material modes; solid materials must always write depth.
			if "WindowGlass" not in path and material.has("alpha") and material.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED:
				if material.alpha!=1.0 or material.depth_draw!=BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY or material.no_depth_test:opaque_states.append(path)
			if "WindowGlass" not in path and "Prop_" not in path and not str(path).begins_with("Clutter_") and material.has("alpha"):
				if material.alpha!=1.0 or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED or material.depth_draw!=BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY or material.no_depth_test or material.cull!=BaseMaterial3D.CULL_BACK:architecture_states.append(path)
	verify(initial.size()>100,"airport_geometry_loaded",[initial.size()])
	verify(fading.is_empty(),"no_camera_distance_geometry_fades",fading)
	verify(material_fades.is_empty(),"no_camera_distance_material_fades",material_fades)
	verify(translucent.is_empty(),"no_instance_transparency",translucent)
	verify(opaque_states.is_empty(),"opaque_materials_write_solid_depth",opaque_states)
	verify(architecture_states.is_empty(),"architecture_is_opaque_with_backface_culling",architecture_states)
	var repeated:=repeated_fan_triangles(arena)
	verify(repeated.is_empty(),"no_duplicate_fan_blade_triangles",repeated)
	var depth:Array=[];var samples:=0
	for route in ROUTES:
		var changed:Array=[]
		for step in 9:
			camera.global_position=(route[1] as Vector3).lerp(route[2],step/8.0)
			camera.look_at(route[3])
			await physics_frame
			await process_frame
			var current:=snapshot(arena);samples+=1
			if current.size()!=initial.size():changed.append("geometry_count step "+str(step))
			for path in initial:
				if not current.has(path) or current[path]!=initial[path]:changed.append(path+" step "+str(step))
			if rendered and step in [0,4,8]:await capture(camera,output+"/"+route[0]+"-walk-"+str(step)+".png")
			if rendered and step==4:depth.append(await depth_diagnostic(camera,route[0]))
		verify(changed.is_empty(),route[0]+"_geometry_and_materials_stay_rigid",changed)
	var failed:=checks.filter(func(check:Dictionary):return not check.passed).size()
	var report:={"passed":checks.size()-failed,"failed":failed,"geometry_instances":initial.size(),
		"camera_samples":samples,"rendered":rendered,"checks":checks,"depth_diagnostics":depth}
	var file:=FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("AIRPORT STABILITY ",checks.size()-failed," passed / ",failed," failed; ",initial.size()," geometry instances, ",samples," camera samples")
	if rendered:print("AIRPORT DEPTH DIAGNOSTICS ",JSON.stringify(depth))
	arena.free();camera.free()
	# Let render-server frees retire before shutting down the display device.
	await process_frame;await process_frame
	quit(0 if failed==0 else 1)
