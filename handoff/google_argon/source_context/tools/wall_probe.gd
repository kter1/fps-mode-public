extends SceneTree

# Finds walls you can walk through: every visible, wall-shaped static mesh (tall, thin, long)
# is checked for World or Character colliders along its length at chest height.
#   godot --headless --script res://tools/wall_probe.gd -- [--map=village]
# Prints each hollow wall with its position; exit code 1 when any is found.

func _initialize() -> void:call_deferred("probe")

func probe() -> void:
	var ids:=MapCatalog.ids()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):ids=[arg.trim_prefix("--map=")]
	var total:=0
	for id in ids:
		var arena:MapArena=load(MapCatalog.scene_path(id)).instantiate();root.add_child(arena)
		for frame in 3:await physics_frame
		var space:=arena.get_world_3d().direct_space_state
		var extent:Vector2=arena.definition.extent
		var hollow:=[]
		for node in arena.find_children("*","MeshInstance3D",true,false):
			var mesh:MeshInstance3D=node
			if mesh.mesh==null or not mesh.is_visible_in_tree():continue
			var box:=mesh.global_transform*mesh.mesh.get_aabb()
			var long:=maxf(box.size.x,box.size.z);var thin:=minf(box.size.x,box.size.z)
			if box.size.y<1.6 or long<1.5 or thin>.9 or box.position.y>.6 or box.end.y<1.6:continue
			if absf(box.get_center().x)>extent.x*.5+2 or absf(box.get_center().z)>extent.y*.5+2:continue
			# Sample chest height along the long axis: where the mesh itself has a surface (a ray
			# across the wall's thickness meets one of its triangles) there must be a collider.
			var faces:=mesh.mesh.get_faces();var to_world:=mesh.global_transform
			var across:=Vector3(0,0,1) if box.size.x>=box.size.z else Vector3(1,0,0)
			var open:=0;var solid:=0;var samples:=16
			for k in samples:
				var t:=(k+.5)/samples
				var p:=box.position+Vector3(box.size.x*(t if box.size.x>=box.size.z else .5),1.1-box.position.y,box.size.z*(t if box.size.z>box.size.x else .5))
				var start:=p-across*(thin+.5);var hit_mesh:=false
				for f in range(0,faces.size(),3):
					if Geometry3D.ray_intersects_triangle(start,across,to_world*faces[f],to_world*faces[f+1],to_world*faces[f+2])!=null:hit_mesh=true;break
				if not hit_mesh:continue
				solid+=1
				var query:=PhysicsShapeQueryParameters3D.new();var probe_box:=BoxShape3D.new();probe_box.size=Vector3(thin+.1,.3,thin+.1)
				query.shape=probe_box;query.transform=Transform3D(Basis.IDENTITY,p);query.collision_mask=3
				if space.intersect_shape(query,1).is_empty():open+=1
			if open>=2:hollow.append("%s (%s) centre=%s size=%s open=%d of %d surfaced samples"%[mesh.name,mesh.get_parent().name,str(box.get_center().snapped(Vector3.ONE*.1)),str(box.size.snapped(Vector3.ONE*.1)),open,solid])
		print("== ",id," hollow walls: ",hollow.size())
		for line in hollow:print("  ",line)
		total+=hollow.size()
		arena.queue_free();await process_frame;await process_frame
	print("WALL PROBE ",total)
	quit(1 if total>0 else 0)
