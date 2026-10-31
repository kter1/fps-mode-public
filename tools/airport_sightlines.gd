extends SceneTree

# Airport flow review: readable connections plus standing-eye view diagnostics.
# Ignores transparent glazing. Sampling does not bound every possible view.
# Run with --headless --script res://tools/airport_sightlines.gd.

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var label:="flow"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	var arena:MapArena=load(MapCatalog.scene_path("airport")).instantiate();root.add_child(arena)
	for i in 5:await physics_frame
	var excluded:Array[RID]=[]
	# Transparent terminal glazing must not falsely count as visual cover.
	for body in arena.find_children("*","StaticBody3D",true,false):
		if String(body.get_parent().name).begins_with("WindowGlass"):excluded.append(body.get_rid())
	var space:=arena.get_world_3d().direct_space_state
	var samples:Array[float]=[];var worst:Array=[]
	var half:=arena.definition.extent*.5
	for x in range(-int(half.x)+5,int(half.x)-4,6):
		for z in range(-int(half.y)+5,int(half.y)-4,6):
			var p:=arena.closest(Vector3(x,0,z))
			if p.y>1 or Vector2(p.x-x,p.z-z).length()>.5:continue
			var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP,p+Vector3.DOWN*2,1))
			if floor_hit.is_empty():continue
			var floor_at:Vector3=floor_hit.position
			var shape:=CapsuleShape3D.new();shape.radius=.35;shape.height=1.8
			var shape_query:=PhysicsShapeQueryParameters3D.new();shape_query.shape=shape;shape_query.transform.origin=floor_at+Vector3.UP*.91;shape_query.collision_mask=1
			if not space.intersect_shape(shape_query,1).is_empty():continue
			var eye:=floor_at+Vector3.UP*1.62
			for i in 64:
				var direction:=Vector3(cos(TAU*i/64),0,sin(TAU*i/64))
				var q:=PhysicsRayQueryParameters3D.create(eye,eye+direction*180,1,excluded)
				var hit:=space.intersect_ray(q)
				var distance:float=eye.distance_to(hit.position) if not hit.is_empty() else 180.0
				samples.append(distance)
				if distance>40:worst.append({"distance":distance,"start":str(eye),"end":str(hit.get("position",eye+direction*180))})
	samples.sort();worst.sort_custom(func(a:Dictionary,c:Dictionary):return a.distance>c.distance)
	# Keep the main ground connections direct. A short sightline alone does
	# not indicate good flow: an obstacle maze can score well on that metric.
	var routes:=[]
	for pair in [
		["lounge_to_boarding",Vector3(-8,0,-17),Vector3(-1,0,10)],
		["baggage_to_sorting",Vector3(-33,0,15),Vector3(-13,0,4)],
		["sorting_to_boarding",Vector3(-13,0,4),Vector3(-1,0,10)],
		["hangar_to_apron",Vector3(36,0,-13),Vector3(34,0,4)],
		["south_court",Vector3(-22,0,27),Vector3(3,0,27)],
		["rear_crossing",Vector3(-4,0,34),Vector3(33,0,34)]
	]:
		var a:=arena.closest(pair[1]);var c:=arena.closest(pair[2])
		var path:=NavigationServer3D.map_get_path(arena.get_world_3d().navigation_map,a,c,true)
		var length:=0.0
		for i in range(1,path.size()):length+=path[i-1].distance_to(path[i])
		var ratio:=length/maxf(a.distance_to(c),1.0)
		var reaches:=not path.is_empty() and path[-1].distance_to(c)<.5
		routes.append({"name":pair[0],"length_m":length,"detour_ratio":ratio,"passed":reaches and ratio<=1.65})
	var views:=[]
	for pair in [
		["check_in_to_security",Vector3(-25,1.62,-34),Vector3(-10,1.62,-34)],
		["open_gate_lounge",Vector3(-8,1.62,-25),Vector3(8,1.62,-25)],
		["sorting_to_boarding",Vector3(-13,1.62,-.5),Vector3(-1,1.62,8)]
	]:
		var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(pair[1],pair[2],1,excluded))
		views.append({"name":pair[0],"passed":hit.is_empty()})
	var aircraft_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-8,1.62,17),Vector3(15,4.1,20),1,excluded))
	var aircraft_visible:=false
	if not aircraft_hit.is_empty():
		var node:Node=aircraft_hit.collider
		while node!=null:
			if String(node.name).begins_with("PassengerJet"):aircraft_visible=true;break
			node=node.get_parent()
	views.append({"name":"aircraft_landmark_visible","passed":aircraft_visible})
	var passed:=routes.all(func(route:Dictionary):return route.passed) and views.all(func(view:Dictionary):return view.passed)
	var report:={"passed":passed,"samples":samples.size(),"median_m":samples[samples.size()/2],"p90_m":samples[int(samples.size()*.9)],"p95_m":samples[int(samples.size()*.95)],"max_m":samples[-1],"routes":routes,"views":views,"worst":worst.slice(0,12)}
	var file:=FileAccess.open("res://.artifacts/airport-sightlines-"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("AIRPORT FLOW ",JSON.stringify(report))
	print("AIRPORT FLOW ","PASS" if passed else "FAIL")
	arena.free();quit(0 if passed else 1)
