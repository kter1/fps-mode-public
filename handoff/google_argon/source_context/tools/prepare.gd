extends SceneTree

func _initialize() -> void:
	call_deferred("prepare")

func prepare() -> void:
	DirAccess.make_dir_recursive_absolute("res://game/maps/generated")
	var license_file:=FileAccess.open("res://content/licenses/godot-engine.txt",FileAccess.WRITE)
	license_file.store_string(Engine.get_license_text()+"\n\n"+JSON.stringify(Engine.get_license_info(),"\t"));license_file.close()
	var map_id := MapCatalog.default_id()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map="):map_id=argument.trim_prefix("--map=")
	for id in [map_id]:
		var builder := CompactMapBuilder.new()
		var map := builder.build(id)
		var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.size=Vector2i(64,64);root.add_child(viewport)
		NavigationServer3D.map_set_use_async_iterations(viewport.find_world_3d().navigation_map,false)
		viewport.add_child(map)
		await process_frame
		NavigationServer3D.region_set_use_async_iterations(map.nav_region.get_rid(),false)
		print("Baking navigation: ",id)
		map.nav_region.bake_navigation_mesh(false)
		print("Baked polygons before sync: ",map.nav_region.navigation_mesh.get_polygon_count())
		# Publish a fresh geometry resource. The bake mutates its source mesh in
		# place; a new resource forces server-side region geometry invalidation.
		var baked:=map.nav_region.navigation_mesh
		var fresh:NavigationMesh=baked.duplicate(true)
		fresh.clear_polygons();fresh.set_vertices(baked.get_vertices())
		for polygon in baked.get_polygon_count():fresh.add_polygon(baked.get_polygon(polygon))
		map.nav_region.navigation_mesh=fresh
		var nav_map:=map.get_world_3d().navigation_map
		# Preparation is a synchronous build step. Repeated force updates while an
		# asynchronous map iteration is pending can leave queries on an empty map.
		NavigationServer3D.map_set_use_async_iterations(nav_map,false)
		NavigationServer3D.set_active(true)
		map.nav_region.set_navigation_map(nav_map)
		NavigationServer3D.map_set_active(nav_map,true)
		NavigationServer3D.region_set_map(map.nav_region.get_rid(),nav_map)
		NavigationServer3D.region_set_enabled(map.nav_region.get_rid(),true)
		NavigationServer3D.region_set_navigation_mesh(map.nav_region.get_rid(),map.nav_region.navigation_mesh)
		await physics_frame
		await physics_frame
		NavigationServer3D.map_force_update(nav_map)
		var deadline:=Time.get_ticks_msec()+60000
		var retry:=Time.get_ticks_msec()+3000
		while NavigationServer3D.map_get_iteration_id(nav_map)==0 or NavigationServer3D.map_get_closest_point_owner(nav_map,map.definition.spawns_blue[0])!=map.nav_region.get_rid():
			await physics_frame
			if Time.get_ticks_msec()>deadline:
				push_error("Navigation preparation timed out for "+id+" owner="+str(NavigationServer3D.map_get_closest_point_owner(nav_map,map.definition.spawns_blue[0]))+" expected="+str(map.nav_region.get_rid())+" active="+str(NavigationServer3D.map_is_active(nav_map))+" iteration="+str(NavigationServer3D.map_get_iteration_id(nav_map))+" regions="+str(NavigationServer3D.map_get_regions(nav_map)));quit(1);return
		print("Navigation polygons: ",map.nav_region.navigation_mesh.get_polygon_count())
		for field in ["routes","cover_points","cover_peeks","domination","hardpoints","qa_route"]:
			var markers:Array[Vector3]=map.definition.get(field)
			for i in markers.size():markers[i]=normalize_marker(map,markers[i])
		externalize_meshes(map,id)
		# Destructible objects hang off collider metadata and recurse when packed; MapArena._ready
		# rebuilds them from node names at load, so the baked scene does not need them.
		for body in map.find_children("*","StaticBody3D",true,false):
			if body.has_meta("destructible"):body.remove_meta("destructible")
		var packed := PackedScene.new()
		packed.pack(map)
		ResourceSaver.save(packed,MapCatalog.scene_path(id))
		map.free()
		viewport.free()
		builder=null
		await process_frame;await process_frame
	print("PREPARE PASS")
	quit(0)

# Large generated meshes (ground, terrain, skyline, firs) are saved as binary
# resources beside the scene so the text scene stays small and loads quickly.
func externalize_meshes(map:MapArena, id:String) -> void:
	var folder:="res://game/maps/generated/"
	for old in DirAccess.get_files_at(folder):
		if old.begins_with(id+"_mesh_") and old.ends_with(".res"):DirAccess.remove_absolute(folder+old)
	var index:=0
	for node in map.find_children("*","GeometryInstance3D",true,false):
		var mesh:Mesh=null
		if node is MeshInstance3D:mesh=node.mesh
		elif node is MultiMeshInstance3D and node.multimesh!=null:mesh=node.multimesh.mesh
		if not mesh is ArrayMesh or mesh.resource_path!="":continue
		var vertices:=0
		for surface in mesh.get_surface_count():vertices+=mesh.surface_get_array_len(surface)
		if vertices<4000:continue
		var path:=folder+"%s_mesh_%d.res"%[id,index];index+=1
		ResourceSaver.save(mesh,path);mesh.take_over_path(path)

func normalize_marker(map:MapArena, original:Vector3) -> Vector3:
	var offsets:=[Vector3.ZERO]
	for radius in [1.0,2.0,4.0,6.0]:
		for direction in [Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK]:offsets.append(direction*radius)
	var nav:=map.get_world_3d().navigation_map
	var start:=map.closest(map.definition.spawns_blue[0])
	for offset in offsets:
		var closest:=map.closest(original+offset)
		var path:=NavigationServer3D.map_get_path(nav,start,closest,true)
		if path.is_empty() or path[path.size()-1].distance_to(closest)>.5:continue
		var query:=PhysicsShapeQueryParameters3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8
		query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,closest+Vector3.UP*.9);query.collision_mask=1
		if not map.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
		return closest
	push_error("Unable to normalize marker: "+str(original))
	quit(1)
	return original
