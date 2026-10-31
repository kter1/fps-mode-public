class_name EffectMeshes
extends RefCounted

# Procedural meshes shared by the pooled effects (built once at load).

# A glowing spark: two perpendicular tapering ribbons along +Y with the hot head at
# +Y and a transparent tail at -Y. With particle_flag_align_y the ribbons follow the
# velocity, and the cross keeps one of them facing the camera from any side.
static func streak(length: float, width: float) -> ArrayMesh:
	var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var head := Color(1, 1, 1, 1);var tail := Color(1, 1, 1, 0)
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		var half: Vector3 = axis * width * .5
		var tip := Vector3(0, -length * .5, 0);var top := Vector3(0, length * .5, 0)
		var mid := Vector3(0, length * .25, 0)
		for vertex in [[tip, tail], [mid + half, Color(1, 1, 1, .6)], [mid - half, Color(1, 1, 1, .6)],
				[mid + half, Color(1, 1, 1, .6)], [top + half * .35, head], [mid - half, Color(1, 1, 1, .6)],
				[mid - half, Color(1, 1, 1, .6)], [top + half * .35, head], [top - half * .35, head]]:
			tool.set_color(vertex[1]);tool.add_vertex(vertex[0])
	return tool.commit()

# An irregular rock shard: an octahedron with jittered vertex radii, flat shaded.
static func chunk(seed_value: int, size: Vector3) -> ArrayMesh:
	var rng := RandomNumberGenerator.new();rng.seed = seed_value
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var points: Array[Vector3] = []
	for axis in axes:
		var jitter := Vector3(rng.randf_range(-.22, .22), rng.randf_range(-.22, .22), rng.randf_range(-.22, .22))
		points.append((axis * rng.randf_range(.62, 1.0) + jitter) * size * .5)
	# Faces: every pairing of one x-axis, one y-axis and one z-axis point.
	var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [0, 1]:
		for y in [2, 3]:
			for z in [4, 5]:
				var corners: Array[Vector3] = [points[x], points[y], points[z]]
				var normal := (corners[1] - corners[0]).cross(corners[2] - corners[0])
				if normal.dot(corners[0] + corners[1] + corners[2]) < 0:corners = [corners[0], corners[2], corners[1]]
				for corner in corners:tool.add_vertex(corner)
	tool.generate_normals()
	return tool.commit()

# A bent sheet-metal panel (door, bonnet): a slightly cambered slab.
static func panel(size: Vector3) -> ArrayMesh:
	var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var columns := 4
	for layer in [1.0, -1.0]:
		for i in columns:
			var a := float(i) / columns;var b := float(i + 1) / columns
			var xa := (a - .5) * size.x;var xb := (b - .5) * size.x
			var ya: float = sin(a * PI) * size.y * 2.0 + layer * size.y * .5
			var yb: float = sin(b * PI) * size.y * 2.0 + layer * size.y * .5
			var quad := [Vector3(xa, ya, -size.z * .5), Vector3(xb, yb, -size.z * .5), Vector3(xb, yb, size.z * .5), Vector3(xa, ya, size.z * .5)]
			var order := [0, 1, 2, 0, 2, 3] if layer > 0 else [0, 2, 1, 0, 3, 2]
			for index in order:tool.add_vertex(quad[index])
	tool.generate_normals()
	return tool.commit()

# Tracer: two perpendicular ribbons one metre long along +Y (centred), fading from a hot
# head at +Y to nothing at -Y. Oriented by the node's basis; no billboarding, because a
# fixed-Y billboard keeps the quad vertical in the world however the node is turned.
static func tracer(width: float) -> ArrayMesh:
	var tool := SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for axis in [Vector3.RIGHT, Vector3.BACK]:
		var half: Vector3 = axis * width * .5
		var corners := [[Vector3(0, -.5, 0) - half, Color(1, 1, 1, 0)], [Vector3(0, -.5, 0) + half, Color(1, 1, 1, 0)], [Vector3(0, .5, 0) + half, Color(1, 1, 1, 1)], [Vector3(0, .5, 0) - half, Color(1, 1, 1, 1)]]
		for index in [0, 1, 2, 0, 2, 3]:
			tool.set_color(corners[index][1]);tool.add_vertex(corners[index][0])
	return tool.commit()
