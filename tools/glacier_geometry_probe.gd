extends SceneTree

var checks: Array[Dictionary] = []
var arena: MapArena

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String, detail: String = "") -> void:
	checks.append({"name": label, "passed": condition, "detail": detail})
	print("PASS " if condition else "FAIL ", label, " ", detail)

func floor_at(x: float, z: float, top: float = 30.0) -> float:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -15.0, z), 1)
	var result: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(query)
	return float(result.position.y) if not result.is_empty() else -INF

func run() -> void:
	arena = load(MapCatalog.scene_path("glacier_peak")).instantiate()
	root.add_child(arena)
	NavigationServer3D.map_set_use_async_iterations(arena.get_world_3d().navigation_map, false)
	for frame: int in 8:
		await physics_frame
	NavigationServer3D.map_force_update(arena.get_world_3d().navigation_map)
	var bridge: float = floor_at(0.0, 0.0)
	var river: float = floor_at(0.0, 0.0, 2.0)
	var shelf: float = floor_at(-24.0, -35.0)
	check(absf(bridge - 3.8) < 0.12, "bridge_collision_at_authored_height", str(bridge))
	check(absf(river + 3.2) < 0.12, "river_is_a_physical_depression", str(river))
	check(bridge - river > 6.5, "stacked_routes_have_body_and_head_clearance", str(bridge - river))
	check(shelf - river > 6.0, "north_shelf_has_real_elevation", str(shelf))
	var failed_spawns: Array[String] = []
	for spawn: Vector3 in arena.definition.spawns_blue + arena.definition.spawns_red:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.height = 1.8
		capsule.radius = 0.35
		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = spawn + Vector3.UP * 0.95
		query.collision_mask = 1
		if not arena.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			failed_spawns.append(str(spawn))
	check(failed_spawns.is_empty(), "all_32_spawn_capsules_clear", str(failed_spawns))
	var upper: Vector3 = arena.closest(Vector3(0.0, 3.8, 0.0))
	var lower: Vector3 = arena.closest(Vector3(0.0, -3.2, 0.0))
	check(upper.y - lower.y > 6.5, "navigation_preserves_both_stacked_routes", str([upper, lower]))
	for team: int in 2:
		var start: Vector3 = arena.definition.spawns_blue[0] if team == 0 else arena.definition.spawns_red[0]
		for goal: Vector3 in [upper, lower, Vector3(23.0, 0.1, 24.0), Vector3(-35.0, 3.4, -29.0), Vector3(28.0, 3.4, -32.0), Vector3(-29.0, 0.0, 28.0)]:
			var closest: Vector3 = arena.closest(goal)
			var path: PackedVector3Array = NavigationServer3D.map_get_path(arena.get_world_3d().navigation_map, arena.closest(start), closest, true)
			check(not path.is_empty() and path[-1].distance_to(closest) < 0.5 and absf(closest.y - goal.y) < 0.75, "team_%d_reaches_%s" % [team, str(goal)], str(closest))
	for prefix: String in ["BlueIce", "BasinSnowIceEscarpment", "Terrain"]:
		var hard_seams: int = 0
		var curved: int = 0
		var triangles: int = 0
		for node: Node in arena.find_children(prefix + "*", "MeshInstance3D", true, false):
			var mesh: ArrayMesh = (node as MeshInstance3D).mesh as ArrayMesh
			var arrays: Array = mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var shared: Dictionary = {}
			for index: int in vertices.size():
				var key: Vector3 = vertices[index].snapped(Vector3.ONE * 0.0001)
				if shared.has(key) and (shared[key] as Vector3).dot(normals[index]) < 0.995:
					hard_seams += 1
				shared[key] = normals[index]
			for offset: int in range(0, indices.size(), 3):
				triangles += 1
				var a: Vector3 = normals[indices[offset]]
				var c: Vector3 = normals[indices[offset + 1]]
				var d: Vector3 = normals[indices[offset + 2]]
				if minf(a.dot(c), minf(c.dot(d), d.dot(a))) < 0.99999:
					curved += 1
		check(hard_seams == 0 and triangles > 0 and float(curved) / float(triangles) > 0.35, "continuous_organic_normals_" + prefix, "%d seams; %d/%d curved triangles" % [hard_seams, curved, triangles])
	var failures: int = checks.filter(func(item: Dictionary) -> bool: return not item.passed).size()
	DirAccess.make_dir_recursive_absolute("res://.artifacts/glacier_overhaul")
	var report: FileAccess = FileAccess.open("res://.artifacts/glacier_overhaul/geometry.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"map": "glacier_peak", "passed": checks.size() - failures, "failed": failures, "checks": checks}, "\t"))
	report.close()
	arena.free()
	await process_frame
	quit(1 if failures > 0 else 0)
