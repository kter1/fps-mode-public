extends MapLayout

# GLACIER PEAK / FRACTURE BASIN
# Terrain-first alpine combat: a depressed blue-ice river, high northern shelf,
# narrow suspended crossing and scattered expedition shelters. No campus grid.
const GLACIER_SLATE := Color("233b4c")
const RESCUE_ORANGE := Color("ed6b2e")
const CRYO_TEAL := Color("267e99")
const HAZARD_AMBER := Color("edc878")
const ALABASTER_SNOW := Color("e8f1f4")
const BASALT_DARK := Color("243443")
const CONCRETE_WARM := Color("91a6b0")
const STEEL := Color("3a4e59")
const GALV := Color("8dabb5")
const WARM_HALIDE := Color(1.0, 0.72, 0.4)
const COOL_LED := Color(0.58, 0.82, 1.0)
const SIGNAL_GREEN := Color(0.2, 0.95, 0.48)
const DECK_Y := 3.8
const RIM_SIDES := 256
const RIM_LEVELS := 24

var b: CompactMapBuilder
var glows: Dictionary = {}
var geology: FastNoiseLite
var moraine_shape: Shape3D

class Snowfield extends MapNature:
	func _init(owner: MapBuilder) -> void:
		super(owner)
		ridged.frequency = 0.0038
		ridged.fractal_octaves = 3
		noise.frequency = 0.009

	static func channel(x_z: float) -> float:
		return x_z * 0.24 + sin(x_z * 0.09) * 4.0

	static func height_at(x: float, z: float) -> float:
		var shelf: float = 3.4 * (1.0 - smoothstep(-27.0, -8.0, z))
		var cut: float = 3.2 * (1.0 - smoothstep(3.5, 18.0, absf(x - channel(z))))
		var roll: float = sin(x * 0.1 + z * 0.055) * 0.35 * smoothstep(13.0, 25.0, absf(x))
		var y: float = shelf - cut + roll
		for pad: Vector4 in [Vector4(-35.0, -29.0, 3.4, 1.0), Vector4(28.0, -32.0, 3.4, 1.0), Vector4(-29.0, 28.0, 0.0, 1.0)]:
			var d: float = maxf(absf(x - pad.x) - 10.0, absf(z - pad.y) - 7.0)
			y = lerpf(pad.z, y, smoothstep(0.0, 5.0, d))
		return y

	func height(x: float, z: float) -> float:
		var cx: float = clampf(x, -56.0, 56.0)
		var cz: float = clampf(z, -50.0, 50.0)
		var outside_distance: float = Vector2(x - cx, z - cz).length()
		var ridge: float = pow(clampf(ridged.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0), 1.6)
		# Smaller eroded ridges break up the broad slopes geometrically.
		var erosion: float = noise.get_noise_2d(x * 2.2, z * 2.2) * 6.0
		var mountain: float = 18.0 + ridge * 110.0 + noise.get_noise_2d(x, z) * 8.0 + erosion
		return height_at(cx, cz) + smoothstep(25.0, 180.0, outside_distance) * mountain

	func terrain() -> void:
		super()
		var terrain_node: MeshInstance3D = arena.get_node("Terrain") as MeshInstance3D
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://content/materials/glacier/mountain.gdshader")
		mat.set_shader_parameter("albedo_tex", MapSurfaces.texture("rock", "diff"))
		mat.set_shader_parameter("normal_tex", MapSurfaces.texture("rock", "nor_gl"))
		mat.set_shader_parameter("arm_tex", MapSurfaces.texture("rock", "arm"))
		mat.set_shader_parameter("snow_tex", MapSurfaces.texture("snow", "diff"))
		terrain_node.material_override = mat

func ground_point(x: float, z: float) -> Vector3:
	return Vector3(x, Snowfield.height_at(x, z) + 0.03, z)

func quad(st: SurfaceTool, pts: Array, normal: Vector3, color: Color = Color.WHITE) -> void:
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var p: Vector3 = pts[tri[0]] as Vector3
		var q: Vector3 = pts[tri[1]] as Vector3
		var r: Vector3 = pts[tri[2]] as Vector3
		if (q - p).cross(r - p).length_squared() < 0.00000001:
			continue
		if (q - p).cross(r - p).dot(normal) > 0.0:
			var sw: Vector3 = q
			q = r
			r = sw
		for v: Vector3 in [p, q, r]:
			st.set_normal(normal)
			st.set_color(color)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)

func finish_mesh(st: SurfaceTool) -> ArrayMesh:
	st.index()
	st.generate_tangents()
	var m: ArrayMesh = st.commit()
	m.lightmap_unwrap(Transform3D.IDENTITY, 0.35)
	return m

# Area-weighted shared normals remove lighting facets even at UV seams.
# Architecture keeps hard edges; only geological surfaces use this path.
func finish_organic_mesh(st: SurfaceTool, lightmapped: bool = true) -> ArrayMesh:
	st.index()
	var raw: ArrayMesh = st.commit()
	var arrays: Array = raw.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var sums: Dictionary = {}
	for offset: int in range(0, indices.size(), 3):
		var a: Vector3 = vertices[indices[offset]]
		var c: Vector3 = vertices[indices[offset + 1]]
		var d: Vector3 = vertices[indices[offset + 2]]
		var normal: Vector3 = (d - a).cross(c - a)
		for at: Vector3 in [a, c, d]:
			var key: Vector3 = at.snapped(Vector3.ONE * 0.0001)
			sums[key] = (sums.get(key, Vector3.ZERO) as Vector3) + normal
	var normals: PackedVector3Array = PackedVector3Array()
	normals.resize(vertices.size())
	for index: int in vertices.size():
		normals[index] = (sums.get(vertices[index].snapped(Vector3.ONE * 0.0001), Vector3.UP) as Vector3).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var smooth: ArrayMesh = ArrayMesh.new()
	smooth.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result: SurfaceTool = SurfaceTool.new()
	result.create_from(smooth, 0)
	result.deindex()
	result.index()
	result.generate_tangents()
	var mesh: ArrayMesh = result.commit()
	if lightmapped:
		mesh.lightmap_unwrap(Transform3D.IDENTITY, 0.35)
	return mesh

func mesh_instance(label: String, mesh: ArrayMesh, mat: Material, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label + str(b.serial)
	b.serial += 1
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	(b.region if parent == null else parent).add_child(node)
	return node

func glow(color: Color, energy: float) -> StandardMaterial3D:
	var key: String = str(color) + ":" + str(energy)
	if not glows.has(key):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.22
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
		glows[key] = mat
	return glows[key] as StandardMaterial3D

func strut(a: Vector3, c: Vector3, width: float, color: Color) -> void:
	var span: Vector3 = c - a
	if span.length() < 0.04:
		return
	var basis: Basis = Basis(Quaternion(Vector3.UP, span.normalized()))
	b.detail((a + c) * 0.5, Vector3(width, span.length(), width), color, "steel", basis.get_euler())

func emergency_lamp(position: Vector3, energy: float, reach: float, color: Color = WARM_HALIDE) -> void:
	var cage: Node3D = b.box("Bulkhead", position, Vector3(0.42, 0.16, 0.24), BASALT_DARK, false)
	(cage.get_child(0) as MeshInstance3D).material_override = glow(color, 4.2)
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "PeakLamp" + str(b.serial)
	b.serial += 1
	light.position = position + Vector3(0.0, -0.18, 0.0)
	light.light_color = color
	light.light_energy = energy
	light.light_indirect_energy = 1.25
	light.omni_range = reach
	light.omni_attenuation = 1.35
	light.shadow_enabled = false
	light.light_size = 0.24
	light.light_bake_mode = Light3D.BAKE_STATIC
	b.region.add_child(light)

func pierced_wall(mid: Vector3, length: float, height: float, thick: float, openings: Array, along_z: bool, kind: String, color: Color = Color.WHITE) -> void:
	var rects: Array = []
	for rect: Rect2 in openings:
		rects.append(Rect2(rect.position.x - rect.size.x * 0.5 + length * 0.5, rect.position.y, rect.size.x, rect.size.y))
	var holder: Node3D = b.box("Facade", mid + Vector3(0.0, height * 0.5, 0.0), Vector3(length, height, thick), color, false)
	var visual: MeshInstance3D = holder.get_child(0) as MeshInstance3D
	var key: String = "gp_wall_" + str(Vector3(length, height, thick)) + str(rects)
	if not b.meshes.has(key):
		b.meshes[key] = MapMeshes.wall(Vector3(length, height, thick), rects, 1.1)
		(b.meshes[key] as ArrayMesh).lightmap_unwrap(Transform3D.IDENTITY, 0.35)
	visual.mesh = b.meshes[key] as ArrayMesh
	visual.material_override = b.surfaces.get_material(kind if MapSurfaces.SCANS.has(kind) else b.detail_surface(kind, color), color)
	if along_z:
		holder.rotation.y = PI * 0.5
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", MapBuilder.impact_surface(kind))
	holder.add_child(body)
	var xs: Array[float] = [0.0, length]
	for rect: Rect2 in rects:
		xs.append_array([rect.position.x, rect.end.x])
	xs.sort()
	for i: int in xs.size() - 1:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		if x1 - x0 < 0.01:
			continue
		var spans: Array[Vector2] = []
		for rect: Rect2 in rects:
			if rect.position.x <= x0 + 0.001 and rect.end.x >= x1 - 0.001:
				spans.append(Vector2(rect.position.y, rect.end.y))
		spans.sort_custom(func(a: Vector2, c: Vector2) -> bool: return a.x < c.x)
		if spans.is_empty() and x1 - x0 > 1.5:
			var strip: OccluderInstance3D = OccluderInstance3D.new()
			var volume: BoxOccluder3D = BoxOccluder3D.new()
			volume.size = Vector3(x1 - x0, height, thick * 0.9)
			strip.occluder = volume
			strip.position = Vector3((x0 + x1) * 0.5 - length * 0.5, 0.0, 0.0)
			holder.add_child(strip)
		var y: float = 0.0
		var all_spans: Array[Vector2] = spans.duplicate()
		all_spans.append(Vector2(height, height))
		for span: Vector2 in all_spans:
			if span.x - y > 0.01:
				var shape: CollisionShape3D = CollisionShape3D.new()
				var box: BoxShape3D = BoxShape3D.new()
				box.size = Vector3(x1 - x0, span.x - y, thick)
				shape.shape = box
				shape.position = Vector3((x0 + x1) * 0.5 - length * 0.5, (y + span.x) * 0.5 - height * 0.5, 0.0)
				body.add_child(shape)
			y = maxf(y, span.y)
	var turn: Basis = Basis(Vector3.UP, PI * 0.5 if along_z else 0.0)
	var rot: Vector3 = Vector3(0.0, PI * 0.5 if along_z else 0.0, 0.0)
	for rect: Rect2 in rects:
		var pane: Vector3 = mid + turn * Vector3(rect.position.x + rect.size.x * 0.5 - length * 0.5, rect.position.y + rect.size.y * 0.5, 0.0)
		var w: float = rect.size.x
		var h: float = rect.size.y
		if rect.position.y < 0.05:
			for sx: float in [-1.0, 1.0]:
				b.detail(pane + turn * Vector3(sx * (w * 0.5 + 0.06), 0.0, 0.0), Vector3(0.12, h, thick + 0.1), BASALT_DARK, "steel", rot)
			b.detail(pane + turn * Vector3(0.0, h * 0.5 + 0.08, 0.0), Vector3(w + 0.3, 0.16, thick + 0.14), RESCUE_ORANGE, "steel", rot)
		else:
			for sx: float in [-1.0, 1.0]:
				b.detail(pane + turn * Vector3(sx * (w * 0.5 - 0.04), 0.0, 0.0), Vector3(0.08, h - 0.02, thick - 0.04), BASALT_DARK, "steel", rot)
			for sy: float in [-1.0, 1.0]:
				b.detail(pane + turn * Vector3(0.0, sy * (h * 0.5 - 0.04), 0.0), Vector3(w - 0.02, 0.08, thick - 0.04), BASALT_DARK, "steel", rot)

# The default ground is replaced after finish_ground(), so visual and physical
# terrain share these exact vertices. All markers use the same height function.
func sculpt_ground() -> void:
	var original: MeshInstance3D = b.ground_node
	var holder: Node3D = original.get_parent()
	for child: Node in holder.get_children():
		if child is StaticBody3D or child is OccluderInstance3D:
			child.free()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in 101:
		for col: int in 113:
			var x: float = -56.0 + float(col)
			var z: float = -50.0 + float(row)
			var distance: float = absf(x - Snowfield.channel(z))
			st.set_color(Color(1.0 - smoothstep(3.0, 8.5, distance), 0.0, 0.0))
			st.set_uv(Vector2(x, z))
			st.set_uv2(Vector2(float(col) / 112.0, float(row) / 100.0))
			st.add_vertex(Vector3(x, Snowfield.height_at(x, z) + 0.35, z))
	for row: int in 100:
		for col: int in 112:
			var a: int = row * 113 + col
			for index: int in [a, a + 1, a + 113, a + 1, a + 114, a + 113]:
				st.add_index(index)
	st.generate_normals()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	mesh.lightmap_size_hint = Vector2i(448, 400)
	original.mesh = mesh
	original.material_override = ice_material(true)
	original.create_trimesh_collision()
	var body: StaticBody3D = original.get_child(0) as StaticBody3D
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "earth")

func ice_material(ground: bool = false) -> ShaderMaterial:
	var key: String = "ice_ground" if ground else "ice_formation"
	if not b.materials.has(key):
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://content/materials/glacier/ice.gdshader")
		mat.set_shader_parameter("albedo_tex", MapSurfaces.texture("snow", "diff"))
		mat.set_shader_parameter("rock_tex", MapSurfaces.texture("rock", "diff"))
		mat.set_shader_parameter("terrain", ground)
		b.materials[key] = mat
	return b.materials[key] as ShaderMaterial

# Multi-scale geometry follows a glacier margin: connected snow/ice fields,
# crevasse cuts and scanned moraine, rather than repeated free-standing pillars.
func geological_noise(x: float, y: float, z: float) -> float:
	if geology == null:
		geology = FastNoiseLite.new()
		geology.seed = 2410
		geology.frequency = 1.0
		geology.fractal_octaves = 3
		geology.fractal_type = FastNoiseLite.FRACTAL_FBM
	return geology.get_noise_3d(x, y, z)

func moraine_rock(at: Vector3, size: Vector3, variant: int) -> void:
	var mesh: ArrayMesh = load("res://content/models/glacier/moraine_rock.res")
	var box: AABB = mesh.get_aabb()
	var scale: Vector3 = Vector3(size.x * 2.0 / box.size.x, size.y / box.size.y, size.z * 2.0 / box.size.z)
	var basis: Basis = Basis(Vector3.UP, float(variant) * 2.399).scaled(scale)
	var base: Vector3 = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var node: MeshInstance3D = mesh_instance("SnowGraniteScan", mesh, moraine_material(), at - basis * base)
	node.basis = basis
	if moraine_shape == null:
		moraine_shape = mesh.create_convex_shape(true, true)
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "earth")
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = moraine_shape
	body.add_child(shape)
	node.add_child(body)

func moraine_material() -> ShaderMaterial:
	if not b.materials.has("moraine_snow"):
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = load("res://content/materials/glacier/moraine.gdshader")
		mat.set_shader_parameter("albedo_tex", load("res://content/models/props/boulder_01/textures/boulder_01_diff_1k.jpg"))
		mat.set_shader_parameter("normal_tex", load("res://content/models/props/boulder_01/textures/boulder_01_nor_gl_1k.jpg"))
		mat.set_shader_parameter("snow_tex", MapSurfaces.texture("snow", "diff"))
		b.materials["moraine_snow"] = mat
	return b.materials["moraine_snow"] as ShaderMaterial

func ice_field_lift(x: float, z: float, size: Vector3, variant: int) -> float:
	var nx: float = x / size.x
	var nz: float = z / size.z
	var warp: float = geological_noise(x * 0.28, float(variant), z * 0.28)
	var width: float = size.x * clampf(0.78 + warp * 0.32 - nz * 0.08, 0.55, 0.97)
	var edge: float = minf(width - absf(x), size.z * (0.76 + geological_noise(x * 0.38, 19.0, float(variant)) * 0.26) - absf(z))
	var bank: float = smoothstep(0.0, 1.1, edge)
	var broad: float = 0.82 - nz * 0.1 + geological_noise(x * 0.18, float(variant) + 5.0, z * 0.18) * 0.2
	var phase: float = z * 0.27 + x * 0.055 + warp * 0.4
	var cut: float = 1.0 - smoothstep(0.018, 0.105, absf(fposmod(phase, 1.0) - 0.5))
	var cross_cut: float = 1.0 - smoothstep(0.01, 0.06, absf(fposmod(x * 0.21 + z * 0.09 + warp * 0.25, 1.0) - 0.5))
	return maxf(0.0, size.y * (broad - cut * 0.61 - cross_cut * 0.42) * bank)

func ice_field_surface(at: Vector3, size: Vector3, variant: int, cell: float) -> SurfaceTool:
	var nx: int = ceili(size.x * 2.0 / cell)
	var nz: int = ceili(size.z * 2.0 / cell)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lifts: PackedFloat32Array = PackedFloat32Array()
	for row: int in nz + 1:
		for col: int in nx + 1:
			var x: float = -size.x + float(col) * size.x * 2.0 / float(nx)
			var z: float = -size.z + float(row) * size.z * 2.0 / float(nz)
			var lift: float = ice_field_lift(x, z, size, variant)
			lifts.append(lift)
			var point: Vector3 = Vector3(at.x + x, Snowfield.height_at(at.x + x, at.z + z) + lift - 0.08 * (1.0 - smoothstep(0.12, 0.5, lift)), at.z + z)
			st.set_normal(Vector3.UP)
			st.set_color(Color(0.0, 0.0, 0.0))
			st.set_uv(Vector2(point.x + point.z, point.y))
			st.add_vertex(point)
	for row: int in nz:
		for col: int in nx:
			var a: int = row * (nx + 1) + col
			var c: int = a + nx + 1
			if maxf(maxf(lifts[a], lifts[a + 1]), maxf(lifts[c], lifts[c + 1])) < 0.06:
				continue
			for index: int in [a, a + 1, c, a + 1, c + 1, c]:
				st.add_index(index)
	return st

func glacier_field(at: Vector3, size: Vector3, variant: int) -> void:
	var mesh: ArrayMesh = finish_organic_mesh(ice_field_surface(at, size, variant, 0.32))
	var node: MeshInstance3D = mesh_instance("BlueIceField", mesh, ice_material(), Vector3.ZERO)
	attach_geological_collision(node, mesh)

func attach_geological_collision(node: MeshInstance3D, mesh: ArrayMesh) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "earth")
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	node.add_child(body)


func boundaries(builder: CompactMapBuilder) -> void:
	b = builder
	b.nature = Snowfield.new(b)
	b.arena.fixed_geometry_visibility = true
	b.region.navigation_mesh.agent_radius = 0.65
	b.region.navigation_mesh.agent_max_slope = 30.0
	b.region.navigation_mesh.cell_size = 0.3
	b.region.navigation_mesh.cell_height = 0.1
	# One continuous, irregular escarpment replaces the rectangular rock border.
	for side: float in [-1.0, 1.0]:
		b.collider(Vector3(side * 56.0, 8.0, 0.0), Vector3(0.6, 30.0, 100.0), "earth")
		b.collider(Vector3(0.0, 8.0, side * 50.0), Vector3(112.0, 30.0, 0.6), "earth")
	basin_escarpment()

func build(builder: CompactMapBuilder) -> void:
	b = builder
	expedition_shelter(Vector3(-35.0, 3.4, -29.0), Vector2(16.0, 10.0), "NORTH / ASCENT CAMP", RESCUE_ORANGE)
	expedition_shelter(Vector3(28.0, 3.4, -32.0), Vector2(18.0, 11.0), "RIDGE / WEATHER RELAY", GLACIER_SLATE)
	expedition_shelter(Vector3(-29.0, 0.0, 28.0), Vector2(15.0, 10.0), "SOUTH / RESCUE REFUGE", RESCUE_ORANGE)
	suspension_crossing()
	icefall_passage()
	natural_cover()
	weather_array()

# Small alpine refuges have pitched, snow-loaded roofs and opposed entrances.
# They sit on three different edges of the basin, never around a central yard.
func expedition_shelter(at: Vector3, size: Vector2, title: String, paint: Color) -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	var h: float = 3.5
	b.footprints.append(Rect2(at.x - hx, at.z - hz, size.x, size.y))
	b.buildings.append({"center": at, "size": size, "height": h, "furnished": false, "door": 4.0, "wall": 0.3})
	var doors: Array = [Rect2(0.0, 0.0, 4.2, 3.15)]
	var windows: Array = [Rect2(-hx * 0.55, 1.2, 2.5, 1.25), Rect2(hx * 0.55, 1.2, 2.5, 1.25)]
	for side: float in [-1.0, 1.0]:
		pierced_wall(at + Vector3(side * hx, 0.0, 0.0), size.y, h, 0.3, doors, true, "corrugated", paint)
		pierced_wall(at + Vector3(0.0, 0.0, side * hz), size.x + 0.3, h, 0.3, windows, false, "wood", paint)
		# Pitched roof with continuous eaves: the roof starts above the side wall.
		var roof: Node3D = b.box("Roof", at + Vector3(0.0, h + 1.15, side * (hz * 0.5 + 0.25)), Vector3(size.x + 1.3, 0.28, hz + 1.5), ALABASTER_SNOW, false)
		roof.rotation.x = side * 0.34
		var lining: Node3D = b.box("TimberRoofLining", Vector3(0.0, -0.2, 0.0), Vector3(size.x + 0.9, 0.1, hz + 1.2), BASALT_DARK, false, roof)
		(lining.get_child(0) as MeshInstance3D).material_override = b.surfaces.get_material("wood")
		var snow: MeshInstance3D = roof.get_child(0) as MeshInstance3D
		snow.material_override = b.surfaces.get_material("snow")
		for x: float in [-hx + 0.4, 0.0, hx - 0.4]:
			strut(at + Vector3(x, h + 2.1, 0.0), at + Vector3(x, h + 0.1, side * (hz + 0.7)), 0.16, GALV)
		b.box("Bench", at + Vector3(side * (hx - 2.0), 0.5, -hz + 1.0), Vector3(2.3, 1.0, 0.9), paint)
		b.box("Worktop", at + Vector3(side * (hx - 2.0), 1.06, -hz + 1.0), Vector3(2.45, 0.12, 1.02), STEEL, false)
		var gable: SurfaceTool = SurfaceTool.new()
		gable.begin(Mesh.PRIMITIVE_TRIANGLES)
		quad(gable, [Vector3(side * hx, h, -hz), Vector3(side * hx, h, hz), Vector3(side * hx, h + 2.0, 0.0), Vector3(side * hx, h + 2.0, 0.0)], Vector3(side, 0.0, 0.0))
		quad(gable, [Vector3(side * hx, h, -hz), Vector3(side * hx, h, hz), Vector3(side * hx, h + 2.0, 0.0), Vector3(side * hx, h + 2.0, 0.0)], Vector3(-side, 0.0, 0.0))
		mesh_instance("TimberGable", finish_mesh(gable), b.surfaces.get_material("wood"), at)
		var light: Node3D = b.box("CeilingLamp", at + Vector3(side * (hx - 0.2), 3.05, 0.0), Vector3(0.15, 0.14, 2.4), WARM_HALIDE, false)
		light.set_meta("glacier_warm_entry", true)
		emergency_lamp(at + Vector3(side * (hx + 0.35), 2.85, 0.0), 2.2, 7.0)
	var floor_node: Node3D = b.box("InteriorSlab", at + Vector3(0.0, 0.025, 0.0), Vector3(size.x - 0.35, 0.05, size.y - 0.35), BASALT_DARK, false)
	(floor_node.get_child(0) as MeshInstance3D).material_override = b.surfaces.get_material("wood")
	b.sign_text(title, at + Vector3(0.0, 3.05, hz + 0.18), 0.0, ALABASTER_SNOW, 30)
	b.interior_lighting(at, size, h)
	# Supply dressing is tucked into the shelter walls, clear of the cross route.
	for i: int in 7:
		var x: float = -hx + 1.0 + float(i) * (size.x - 2.0) / 6.0
		var prop_id: String = ["Barrel_01", "industrial_pastic_container", "industrial_storage_cart"][i % 3]
		var position: Vector3 = at + Vector3(x, 0.0, hz - 0.8)
		if prop_id == "Barrel_01":
			b.drum(position)
		else:
			b.prop(prop_id, position, 0.65, float(i) * 0.2)

func suspension_crossing() -> void:
	# A narrow crossing OVER the traversable ice river, not a central building.
	b.box("Worktop", Vector3(0.0, DECK_Y - 0.18, 0.0), Vector3(22.0, 0.36, 5.0), GLACIER_SLATE)
	for side: float in [-1.0, 1.0]:
		b.ramp(Vector3(side * 25.0, Snowfield.height_at(side * 25.0, 0.0), 0.0), Vector3(side * 11.0, DECK_Y, 0.0), 5.0)
		for x: float in [-10.5, 10.5]:
			b.box("BridgePylon", Vector3(x, DECK_Y + 2.0, side * 2.65), Vector3(0.3, 4.0, 0.3), RESCUE_ORANGE)
		for i: int in 11:
			var x: float = -10.0 + float(i) * 2.0
			var cable_y: float = DECK_Y + 2.2 + pow(absf(x) / 10.0, 2.0) * 1.6
			strut(Vector3(x, DECK_Y + 0.4, side * 2.65), Vector3(x, cable_y, side * 2.65), 0.045, GALV)
			if i < 10:
				var next_y: float = DECK_Y + 2.2 + pow(absf(x + 2.0) / 10.0, 2.0) * 1.6
				strut(Vector3(x, cable_y, side * 2.65), Vector3(x + 2.0, next_y, side * 2.65), 0.09, STEEL)
		b.railing_path([Vector3(-11.0, DECK_Y, side * 2.45), Vector3(11.0, DECK_Y, side * 2.45)], 1.1, GALV, 2.0, true)
	for i: int in 34:
		b.detail(Vector3(-10.7 + float(i) * 0.65, DECK_Y + 0.025, 0.0), Vector3(0.6, 0.05, 4.8), Color("8e8171"), "wood")
	b.sign_text("FRACTURE CROSSING / 04", Vector3(-10.65, DECK_Y + 2.8, 2.85), 0.0, ALABASTER_SNOW, 24)

func icefall_passage() -> void:
	# An open crevasse between connected, fractured ice banks. No separate
	# columns or manufactured-looking overhead ice bridge.
	glacier_field(Vector3(17.0, 0.0, 24.0), Vector3(3.7, 5.8, 16.0), 18)
	glacier_field(Vector3(29.0, 0.0, 24.0), Vector3(3.9, 6.7, 17.5), 29)
	b.arena.probe_volumes.append(AABB(Vector3(19.5, -1.0, 15.0), Vector3(7.0, 7.0, 18.0)))

func natural_cover() -> void:
	var clusters: Array[Vector4] = [
		Vector4(-38,-10,3.3,2.2), Vector4(-27,-14,2.8,1.8),
		Vector4(-20,-23,3.0,2.4), Vector4(-5,-31,3.0,3.0),
		Vector4(9,-24,3.0,4.2), Vector4(20,-17,3.0,2.2),
		Vector4(38,-14,3.2,2.5), Vector4(42,0,3.6,2.0),
		Vector4(34,7,2.8,1.8), Vector4(-40,9,3.4,2.0),
		Vector4(-29,13,2.8,2.6), Vector4(-16,15,3.5,3.7),
		Vector4(-8,25,2.6,2.0), Vector4(3,34,3.8,2.7),
		Vector4(12,39,2.8,2.1), Vector4(-38,40,2.5,1.9),
		Vector4(37,39,2.6,2.2), Vector4(-12,-43,3.3,2.1),
		Vector4(13,-42,2.8,2.4), Vector4(-44,-45,2.1,2.5)
	]
	for i: int in clusters.size():
		var c: Vector4 = clusters[i]
		var at: Vector3 = ground_point(c.x, c.y) - Vector3(0.0, 0.4, 0.0)
		moraine_rock(at, Vector3(c.z, c.w + 0.4, c.z * 0.75), i)
		for side: float in [-1.0, 1.0]:
			b.def.cover_points.append(ground_point(c.x, c.y + side * (c.z * 0.75 + 1.5)))
			b.def.cover_peeks.append(ground_point(c.x + side * (c.z + 1.5), c.y + side * (c.z * 0.75 + 1.5)))
	# Dominant ice blade makes the northern shelf an elbow rather than a lane.
	glacier_field(Vector3(3.5, 0.0, -15.0), Vector3(6.0, 6.5, 10.5), 72)
	glacier_field(Vector3(-9.0, 0.0, 12.0), Vector3(4.0, 4.5, 7.0), 73)

func weather_array() -> void:
	var at: Vector3 = Vector3(28.0, 3.4, -32.0)
	strut(at + Vector3(6.0, 5.0, -3.0), at + Vector3(6.0, 14.0, -3.0), 0.18, GALV)
	for y: float in [7.0, 10.0, 13.0]:
		strut(at + Vector3(4.5, y, -3.0), at + Vector3(7.5, y, -3.0), 0.08, RESCUE_ORANGE)
	# Survey stakes are the route language; no helipads, industrial grid or fences.
	for p: Vector2 in [Vector2(-20,-35), Vector2(-17,-16), Vector2(-28,5), Vector2(-19,26), Vector2(6,26), Vector2(35,24), Vector2(37,-24), Vector2(18,-9)]:
		var foot: Vector3 = ground_point(p.x, p.y)
		b.box("SurveyStake", foot + Vector3(0.0, 1.2, 0.0), Vector3(0.1, 2.4, 0.1), RESCUE_ORANGE)
		b.detail(foot + Vector3(0.28, 2.1, 0.0), Vector3(0.6, 0.38, 0.03), RESCUE_ORANGE, "painted_metal")

func deployment(builder: CompactMapBuilder) -> void:
	b = builder
	for team: int in 2:
		var target: Array[Vector3] = b.def.spawns_blue if team == 0 else b.def.spawns_red
		var side: float = -1.0 if team == 0 else 1.0
		for row: int in 4:
			for col: int in 4:
				var z: float = [-39.0, -31.0, -20.0, 31.0][row] * -side
				target.append(ground_point(side * (48.0 - float(col) * 1.9), z) + Vector3.UP * 0.08)

func objectives(builder: CompactMapBuilder) -> void:
	b = builder
	for p: Vector2 in [Vector2(-39,-24), Vector2(32,-28), Vector2(-33,24), Vector2(23,17), Vector2(-34,-5), Vector2(35,-5), Vector2(-18,35), Vector2(35,32)]:
		var point: Vector3 = ground_point(p.x, p.y)
		b.def.ammo_caches.append(point)
		b.box("AmmoCase", point + Vector3(0.0, 0.32, 0.0), Vector3(0.9, 0.64, 0.55), RESCUE_ORANGE)
	for p: Vector2 in [Vector2(-44,-35), Vector2(-22,-35), Vector2(-3,-24), Vector2(17,-25), Vector2(42,-25), Vector2(-34,-9), Vector2(-18,-9), Vector2(0,-8), Vector2(20,-7), Vector2(43,9), Vector2(-40,22), Vector2(-17,32), Vector2(7,26), Vector2(23,24), Vector2(40,29), Vector2(8,9)]:
		b.def.routes.append(ground_point(p.x, p.y))
	b.def.routes.append(Vector3(0.0, DECK_Y, 0.0))
	b.def.domination.assign([ground_point(-18.0, -26.0), Vector3(0.0, DECK_Y, 0.0), ground_point(23.0, 24.0)])
	b.def.hardpoints.assign([ground_point(-35.0, -29.0), ground_point(28.0, -32.0), ground_point(-29.0, 28.0), Vector3(0.0, DECK_Y, 0.0), ground_point(23.0, 24.0)])
	b.def.qa_route.assign([ground_point(-46.0, -31.0), ground_point(-30.0, -10.0), ground_point(-25.0, 0.0), Vector3(-7.0, DECK_Y, 0.0), Vector3(0.0, DECK_Y, 0.0), Vector3(7.0, DECK_Y, 0.0), ground_point(25.0, 0.0), ground_point(23.0, 24.0), ground_point(7.0, 26.0), ground_point(-18.0, 32.0), ground_point(-29.0, 28.0)])

func dress(builder: CompactMapBuilder) -> void:
	b = builder
	sculpt_ground()
	for shelter: Dictionary in b.buildings:
		var at: Vector3 = shelter.center
		var size: Vector2 = shelter.size
		for side: float in [-1.0, 1.0]:
			var desk: Vector3 = at + Vector3(side * (size.x * 0.5 - 2.0), 1.13, -size.y * 0.5 + 1.0)
			b.small_prop("desk_lamp_arm_01", desk + Vector3(0.6, 0.0, 0.0), 0.42, 0.3)
			b.small_prop("office_notepads", desk - Vector3(0.3, 0.0, 0.0), 0.025, -0.2)

func ground_splat(_builder: CompactMapBuilder, _x: float, _z: float, _noise: FastNoiseLite) -> Color:
	return Color.BLACK

# Cubic interpolation blends the foot, glacial face and snow crest into one
# continuous surface, instead of three enormous planar bands.
func rim_control(angle: float, ring: int) -> Vector3:
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var x: float = signf(ca) * sqrt(absf(ca)) * 59.0
	var z: float = signf(sa) * sqrt(absf(sa)) * 54.0
	var jagged: float = sin(angle * 13.0) * 0.9 + sin(angle * 23.0 + 0.5) * 0.45
	var radii: Array[float] = [0.955, 1.0, 1.12, 1.3]
	var heights: Array[float] = [-2.0, 7.5, 11.5, 2.0]
	var scale: float = radii[ring] + jagged * (0.012 if ring == 0 else 0.035)
	var y: float = Snowfield.height_at(clampf(x, -56.0, 56.0), clampf(z, -50.0, 50.0)) + heights[ring]
	if ring > 0:
		y += sin(angle * 7.0 + float(ring)) * 2.0 + cos(angle * 17.0) * 1.1
	return Vector3(x * scale, y, z * scale)

func rim_vertex(u: float, t: float) -> Vector3:
	var angle: float = TAU * u
	var f: float = t * 3.0
	var ring: int = mini(int(f), 2)
	var point: Vector3 = rim_control(angle, ring).cubic_interpolate(rim_control(angle, ring + 1), rim_control(angle, maxi(0, ring - 1)), rim_control(angle, mini(3, ring + 2)), f - float(ring))
	point.y += geological_noise(point.x * 0.7, point.y * 0.7, point.z * 0.7) * 0.35
	return point

func rim_surface(sides: int, levels: int, granite: bool) -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring: int in levels:
		for segment: int in sides:
			var is_granite: bool = ring < levels / 3 and segment >= sides / 2
			if is_granite != granite:
				continue
			var a: Vector3 = rim_vertex(float(segment) / float(sides), float(ring) / float(levels))
			var c: Vector3 = rim_vertex(float((segment + 1) % sides) / float(sides), float(ring) / float(levels))
			var d: Vector3 = rim_vertex(float((segment + 1) % sides) / float(sides), float(ring + 1) / float(levels))
			var e: Vector3 = rim_vertex(float(segment) / float(sides), float(ring + 1) / float(levels))
			quad(st, [a, c, d, e], (c - a).cross(e - a).normalized(), Color.BLACK)
	return st

func basin_escarpment() -> void:
	for granite: bool in [true, false]:
		var mesh: ArrayMesh = finish_organic_mesh(rim_surface(RIM_SIDES, RIM_LEVELS, granite))
		var node: MeshInstance3D = mesh_instance("BasinGraniteEscarpment" if granite else "BasinSnowIceEscarpment", mesh, b.surfaces.get_material("rock") if granite else ice_material(), Vector3.ZERO)
		var physics_st: SurfaceTool = rim_surface(128, 12, granite)
		var physics_mesh: ArrayMesh = physics_st.commit()
		var body: StaticBody3D = StaticBody3D.new()
		body.set_meta("surface", "earth")
		body.collision_layer = 1
		body.collision_mask = 0
		var shape: CollisionShape3D = CollisionShape3D.new()
		shape.shape = physics_mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)

# A few scanned granite spurs give the distant slopes actual rock silhouettes.
# They are outside play, probe/sky lit, and have no navigation or physics cost.
