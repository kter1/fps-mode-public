extends MapLayout

# Transit Works: a 110 x 90 m urban rail turntable, fan roundhouse, and overhaul
# terminal at cool late afternoon. Built with a radial-and-corridor topology that
# shares zero building positions or prefabs with Foundry:
# - North Zone (0, 0, -33): 48 x 16 m North Grand Overhaul Concourse with a wide
#   ground-floor machinery hall along Z = -35 and an Elevated Mezzanine Gallery
#   (Y = 3.4 m at Z = -26.8) jutting south onto a cantilevered Signal Rotunda
#   Balcony at (0, 3.4, -21.5), reached by gentle 17.2-degree ramps along the
#   concourse facade (X = +-15.0 -> +-4.0 at Z = -23.2).
# - Center Arena (0, 0, 5): 16 m Circular Locomotive Turntable Ring with a girder
#   bridge carrying shunter locomotive "LOCO 801" and a pit control booth, flanked
#   by two offset, boardable Walk-Through Metro Cars ("CAR 401" at (-20, 0, -5)
#   and "CAR 402" at (20, 0, 5)).
# - South Zone: 3-Stall Stepped Fan Roundhouse Arc facing the turntable — Center
#   Stall 02 at (0, 0, 34) (18 x 12 m) and West/East Wings Stall 01 & Stall 03 at
#   (+-22, 0, 30) (14 x 11 m), linked by radial inspection tracks.
# - West & East Ends: Open-air Cantilevered Station Platform Canopies at (+-46, 0, 0)
#   flanked by NW/NE Traction Relay Pavilions (+-41, 0, -20) and SW/SE Crew Dispatch
#   Pavilions (+-41, 0, 22).

const CONCOURSE_C := Vector3(0.0, 0.0, -33.0)
const CONCOURSE_SIZE := Vector2(48.0, 16.0)
const CONCOURSE_H := 8.8
const DECK_Y := 3.4
const MEZZ_Z := -26.8
const RAMP_Z := -23.2
const TURNTABLE_C := Vector3(0.0, 0.0, 5.0)
const TURNTABLE_R := 7.8

const STEEL := Color("444f56")
const GALV := Color("8d969b")
const DEPOT_BLUE := Color("2e556e")
const COBALT_TRIM := Color("1f3d52")
const LIVERY_SILVER := Color("cdd3d6")
const LIVERY_STRIPE := Color("e09f28")
const SAFETY_YELLOW := Color("d9a534")
const SIGNAL_RED := Color("bd362a")
const SIGNAL_GREEN := Color("36b86c")
const TRANSFORMER_GREEN := Color("53695f")
const SHUNTER_ORANGE := Color("c45a28")
const RAIL_RUST := Color("59473a")
const TIMBER := Color("63503d")
const SODIUM := Color(1.0, 0.76, 0.46)
const WARM_HALIDE := Color(1.0, 0.91, 0.76)
const COOL_LED := Color(0.86, 0.93, 1.0)

var b: CompactMapBuilder
var glows: Dictionary = {}
var far_parts: Dictionary = {}

# --- Custom terrain & surrounding rail corridor outside the perimeter --------------

class RailDepotNature extends MapNature:
	func _init(owner: MapBuilder) -> void:
		super(owner)
	func terrain() -> void:
		super()
		var node: GeometryInstance3D = arena.get_node_or_null("Terrain") as GeometryInstance3D
		if node != null:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func boundaries(builder: CompactMapBuilder) -> void:
	b = builder
	b.region.navigation_mesh.agent_radius = 0.75
	b.region.navigation_mesh.cell_size = 0.25
	b.nature = RailDepotNature.new(b)
	b.ground_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var half: Vector2 = b.def.extent * 0.5
	for side: float in [-1.0, 1.0]:
		palisade(Vector3(side * half.x, 0.0, -half.y), Vector3(side * half.x, 0.0, half.y))
		invisible_wall("PerimeterFence", Vector3(side * (half.x + 0.25), 3.2, 0.0), Vector3(0.5, 6.4, b.def.extent.y + 0.5))
	palisade(Vector3(-half.x, 0.0, -half.y), Vector3(half.x, 0.0, -half.y))
	invisible_wall("PerimeterFenceN", Vector3(0.0, 3.2, -half.y - 0.25), Vector3(b.def.extent.x + 0.5, 6.4, 0.5))
	b.box("BoundaryWall", Vector3(0.0, 1.8, half.y), Vector3(b.def.extent.x - 0.5, 3.6, 0.5), b.stone)
	b.coping_run(Vector3(0.0, 3.67, half.y), Vector3(b.def.extent.x - 0.65, 0.14, 0.65), false)
	invisible_wall("PerimeterWallS", Vector3(0.0, 3.6, half.y + 0.25), Vector3(b.def.extent.x + 0.5, 7.2, 0.5))
	depot_backdrop()

func invisible_wall(label: String, center: Vector3, size: Vector3) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = label + str(b.serial)
	b.serial += 1
	b.region.add_child(holder)
	holder.position = center
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "metal")
	var shape: CollisionShape3D = CollisionShape3D.new()
	var volume: BoxShape3D = BoxShape3D.new()
	volume.size = size
	shape.shape = volume
	body.add_child(shape)
	holder.add_child(body)

func palisade(a: Vector3, c: Vector3) -> void:
	var run: Vector3 = c - a
	var length: float = run.length()
	var along: Vector3 = run / length
	var yaw: Vector3 = Vector3(0.0, atan2(-along.z, along.x), 0.0)
	var bays: int = ceili(length / 2.75)
	b.detail((a + c) * 0.5 + Vector3(0.0, 0.18, 0.0), Vector3(length, 0.36, 0.32), Color("9c9a92"), "concrete", yaw)
	for k: int in bays + 1:
		b.detail(a + run * (float(k) / float(bays)) + Vector3(0.0, 1.5, 0.0), Vector3(0.12, 3.0, 0.12), STEEL, "steel", yaw)
	for y: float in [0.8, 2.35]:
		b.detail((a + c) * 0.5 + Vector3(0.0, y, 0.0), Vector3(length, 0.06, 0.05), STEEL, "steel", yaw)
	var pales: int = int(length / 0.22)
	for k: int in pales:
		b.detail(a + along * ((float(k) + 0.5) * length / float(pales)) + Vector3(0.0, 1.6, 0.0), Vector3(0.06, 2.6, 0.022), STEEL, "steel", yaw)

# --- Merged distant rail yard, catenary & carriage roundhouse backdrop -------------

func far_box(center: Vector3, size: Vector3, kind: String, color: Color = Color.WHITE, rotation: Basis = Basis.IDENTITY) -> void:
	var key: String = kind + color.to_html(false)
	if not far_parts.has(key):
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		far_parts[key] = {"st": st, "kind": kind, "color": color}
	var entry_st: SurfaceTool = far_parts[key]["st"] as SurfaceTool
	entry_st.append_from(MapMeshes.block(size, 0.0, 0.0), 0, Transform3D(rotation, center))

func flush_far(label: String) -> void:
	for data: Dictionary in far_parts.values():
		var node: MeshInstance3D = MeshInstance3D.new()
		node.name = label + str(b.serial)
		b.serial += 1
		var st: SurfaceTool = data["st"] as SurfaceTool
		node.mesh = st.commit()
		var kind_str: String = str(data["kind"])
		var col: Color = data["color"] as Color
		node.material_override = b.surfaces.get_material(kind_str, col)
		node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.arena.add_child(node)
	far_parts.clear()

func depot_backdrop() -> void:
	# Explicit float declarations on outer trackwork loops for Godot 4.7.2 parser.
	for side: float in [-1.0, 1.0]:
		var track_z: float = side * 62.0
		far_box(Vector3(0.0, 0.04, track_z), Vector3(240.0, 0.08, 14.0), "gravel", Color("7a766e"))
		for offset: float in [-3.6, 0.0, 3.6]:
			var z: float = track_z + offset
			for rail_s: float in [-0.72, 0.72]:
				far_box(Vector3(0.0, 0.12, z + rail_s), Vector3(236.0, 0.09, 0.09), "painted_metal", RAIL_RUST)
			for sx: int in range(-112, 113, 3):
				far_box(Vector3(float(sx), 0.07, z), Vector3(0.32, 0.05, 2.3), "concrete", TIMBER)
		for mx: int in range(-96, 97, 24):
			var fx: float = float(mx)
			for pz: float in [track_z - 6.2, track_z + 6.2]:
				far_box(Vector3(fx, 4.2, pz), Vector3(0.28, 8.4, 0.28), "painted_metal", GALV)
			far_box(Vector3(fx, 8.1, track_z), Vector3(0.24, 0.32, 12.8), "painted_metal", GALV)
		for offset: float in [-3.6, 0.0, 3.6]:
			far_box(Vector3(0.0, 6.8, track_z + offset), Vector3(220.0, 0.04, 0.04), "painted_metal", Color("23282b"))
	var shed: Vector3 = Vector3(-10.0, 0.0, -88.0)
	far_box(shed + Vector3(0.0, 6.5, 0.0), Vector3(54.0, 13.0, 22.0), "brick", Color.WHITE)
	far_box(shed + Vector3(0.0, 13.3, 0.0), Vector3(55.2, 0.6, 23.2), "concrete", Color("6e706b"))
	for bay: int in 6:
		var bx: float = shed.x - 20.0 + float(bay) * 8.0
		far_box(Vector3(bx, 2.8, shed.z + 11.08), Vector3(5.2, 5.6, 0.14), "painted_metal", Color("2d363b"))
		far_box(Vector3(bx, 9.2, shed.z + 11.08), Vector3(5.2, 3.2, 0.12), "painted_metal", Color("1f262a"))
	var tower: Vector3 = Vector3(54.0, 0.0, -82.0)
	far_box(tower + Vector3(0.0, 10.5, 0.0), Vector3(7.0, 21.0, 7.0), "precast", Color("c2c4be"))
	far_box(tower + Vector3(0.0, 22.5, 0.0), Vector3(11.5, 3.2, 9.5), "painted_metal", DEPOT_BLUE)
	far_box(tower + Vector3(0.0, 22.6, 0.0), Vector3(11.7, 1.6, 9.7), "painted_metal", Color("1e2b33"))
	far_box(tower + Vector3(0.0, 24.4, 0.0), Vector3(12.4, 0.5, 10.4), "concrete", Color("8a8d88"))
	for consist_pos: Vector3 in [Vector3(-42.0, 0.15, -62.0), Vector3(34.0, 0.15, 62.0)]:
		for car_idx: int in 2:
			var cx: float = consist_pos.x + float(car_idx) * 18.5
			far_box(Vector3(cx, 2.1, consist_pos.z), Vector3(17.2, 3.2, 2.9), "painted_metal", LIVERY_SILVER)
			far_box(Vector3(cx, 1.35, consist_pos.z), Vector3(17.3, 0.45, 2.94), "painted_metal", DEPOT_BLUE)
			far_box(Vector3(cx, 2.35, consist_pos.z), Vector3(16.4, 0.85, 2.96), "painted_metal", Color("1f2930"))
	flush_far("DepotBackdrop")

# --- Shared architectural & lighting helpers ---------------------------------------

func glow(color: Color, energy: float) -> StandardMaterial3D:
	var key: String = color.to_html() + str(energy)
	if not glows.has(key):
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = color.darkened(0.2)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
		mat.roughness = 0.38
		glows[key] = mat
	return glows[key] as StandardMaterial3D

func strut(a: Vector3, c: Vector3, width: float, color: Color) -> void:
	var run: Vector3 = c - a
	if run.length() < 0.01:
		return
	b.detail((a + c) * 0.5, Vector3(width, run.length(), width), color, "steel", Basis(Quaternion(Vector3.UP, run.normalized())).get_euler())

func emergency_lamp(position: Vector3, energy: float, reach: float, color: Color = SODIUM) -> void:
	b.box("LampHousing", position + Vector3(0.0, 0.07, 0.0), Vector3(0.44, 0.14, 0.22), Color("2b2f31"), false)
	var lens: Node3D = b.box("EmergencyLens", position - Vector3(0.0, 0.03, 0.0), Vector3(0.36, 0.08, 0.15), color, false)
	(lens.get_child(0) as MeshInstance3D).material_override = glow(color, 5.5)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "DepotLight" + str(b.serial)
	b.serial += 1
	lamp.position = position - Vector3(0.0, 0.28, 0.0)
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.light_indirect_energy = 1.4
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.25
	lamp.shadow_enabled = true
	lamp.light_size = 0.28
	lamp.light_bake_mode = Light3D.BAKE_STATIC
	b.region.add_child(lamp)

func exit_sign(position: Vector3, yaw: float) -> void:
	var sign_node: Node3D = b.box("ExitSign", position, Vector3(0.62, 0.24, 0.08), Color("2fa35a"), false)
	sign_node.rotation.y = yaw
	(sign_node.get_child(0) as MeshInstance3D).material_override = glow(Color("3fd27a"), 3.0)

func flood_mast(base: Vector3, height: float, target: Vector3, energy: float = 4.6, reach: float = 30.0) -> void:
	b.cylinder(base + Vector3(0.0, height * 0.5, 0.0), 0.13, height, GALV)
	b.collider(base + Vector3(0.0, height * 0.5, 0.0), Vector3(0.32, height, 0.32), "metal")
	b.detail(base + Vector3(0.0, 0.2, 0.0), Vector3(0.62, 0.4, 0.62), Color("8c8a84"), "concrete")
	var head: Vector3 = base + Vector3(0.0, height + 0.1, 0.0)
	var flat: Vector3 = Vector3(target.x - head.x, 0.0, target.z - head.z).normalized()
	b.detail(head + Vector3(0.0, 0.1, 0.0) + flat * 0.15, Vector3(0.52, 0.08, 0.08), GALV, "steel", Vector3(0.0, atan2(-flat.z, flat.x), 0.0))
	flood_lamp(head + flat * 0.4, target, energy, reach)

func flood_lamp(head: Vector3, target: Vector3, energy: float, reach: float) -> void:
	var aim: Vector3 = (target - head).normalized()
	var facing: Basis = Basis.looking_at(aim, Vector3.UP)
	var lantern: Node3D = b.box("Floodlight", head, Vector3(0.7, 0.48, 0.24), Color("1e2224"), false)
	lantern.basis = facing
	var lens: Node3D = b.box("FloodLens", head + aim * 0.13, Vector3(0.58, 0.38, 0.03), SODIUM, false)
	lens.basis = facing
	(lens.get_child(0) as MeshInstance3D).material_override = glow(SODIUM, 8.0)
	var spot: SpotLight3D = SpotLight3D.new()
	spot.name = "YardFlood" + str(b.serial)
	b.serial += 1
	spot.position = head + aim * 0.3
	spot.basis = facing
	spot.light_color = SODIUM
	spot.light_energy = energy
	spot.light_indirect_energy = 1.3
	spot.spot_range = reach
	spot.spot_angle = 48.0
	spot.spot_angle_attenuation = 0.8
	spot.spot_attenuation = 1.1
	spot.shadow_enabled = true
	spot.light_size = 0.3
	spot.light_bake_mode = Light3D.BAKE_STATIC
	b.region.add_child(spot)

func pierced_wall(mid: Vector3, length: float, height: float, thick: float, openings: Array, along_z: bool, kind: String, color: Color = Color.WHITE) -> void:
	var rects: Array = []
	for rect: Rect2 in openings:
		rects.append(Rect2(rect.position.x - rect.size.x * 0.5 + length * 0.5, rect.position.y, rect.size.x, rect.size.y))
	var holder: Node3D = b.box("Facade", mid + Vector3(0.0, height * 0.5, 0.0), Vector3(length, height, thick), color, false)
	var visual: MeshInstance3D = holder.get_child(0) as MeshInstance3D
	var key: String = "tw_wall_" + str(Vector3(length, height, thick)) + str(rects)
	if not b.meshes.has(key):
		b.meshes[key] = MapMeshes.wall(Vector3(length, height, thick), rects, 1.1)
		(b.meshes[key] as ArrayMesh).lightmap_unwrap(Transform3D.IDENTITY, 0.35)
	visual.mesh = b.meshes[key] as ArrayMesh
	visual.material_override = b.surfaces.get_material(kind, color)
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
	for rect: Rect2 in openings:
		var w: float = rect.size.x
		var h: float = rect.size.y
		var pane: Vector3 = mid + turn * Vector3(rect.position.x, rect.position.y + h * 0.5, 0.0)
		if rect.position.y < 0.01:
			for sx: float in [-1.0, 1.0]:
				b.detail(pane + turn * Vector3(sx * (w * 0.5 + 0.06), 0.0, 0.0), Vector3(0.12, h, thick + 0.1), Color("3a3f42"), "steel", rot)
			b.detail(pane + turn * Vector3(0.0, h * 0.5 + 0.06, 0.0), Vector3(w + 0.24, 0.12, thick + 0.1), Color("3a3f42"), "steel", rot)
			continue
		for face: float in [-1.0, 1.0]:
			b.detail(pane + turn * Vector3(0.0, -h * 0.5 - 0.03, face * (thick * 0.5 + 0.05)), Vector3(w + 0.2, 0.06, 0.14), Color("a8a69e"), "concrete", rot)
		for sx: float in [-1.0, 1.0]:
			b.detail(pane + turn * Vector3(sx * (w * 0.5 - 0.04), 0.0, 0.0), Vector3(0.08, h - 0.02, 0.1), Color("2e3436"), "steel", rot)
		for sy: float in [-1.0, 1.0]:
			b.detail(pane + turn * Vector3(0.0, sy * (h * 0.5 - 0.04), 0.0), Vector3(w - 0.02, 0.08, 0.1), Color("2e3436"), "steel", rot)
		var bars: int = maxi(1, roundi(w / 1.1))
		for k: int in range(1, bars):
			b.detail(pane + turn * Vector3(-w * 0.5 + w * (float(k) / float(bars)), 0.0, 0.0), Vector3(0.05, h - 0.1, 0.06), Color("2e3436"), "steel", rot)
		b.detail(pane, Vector3(w - 0.1, 0.05, 0.06), Color("2e3436"), "steel", rot)

func add_cover_pair(pt: Vector3, peek: Vector3) -> void:
	b.def.cover_points.append(pt)
	b.def.cover_peeks.append(peek)

# --- Main Play Space Construction --------------------------------------------------

func build(builder: CompactMapBuilder) -> void:
	b = builder
	north_grand_concourse()
	concourse_mezzanine_and_rotunda()
	central_locomotive_turntable()
	offset_walkthrough_metro_cars()
	south_fan_roundhouse()
	yard_tracks_and_props()

# 1. North Zone: 48 x 16 m Grand Overhaul Concourse at (0, 0, -33) (Z in -41..-25)
func north_grand_concourse() -> void:
	var c: Vector3 = CONCOURSE_C
	var hx: float = CONCOURSE_SIZE.x * 0.5
	var hz: float = CONCOURSE_SIZE.y * 0.5
	var h: float = CONCOURSE_H
	var t: float = 0.4
	b.footprints.append(Rect2(c.x - hx, c.z - hz, CONCOURSE_SIZE.x, CONCOURSE_SIZE.y))
	b.buildings.append({"center": c, "size": CONCOURSE_SIZE, "height": h, "furnished": false, "door": 3.5, "wall": t})
	# North wall (Z = -41): Two wide ground portals at X = +-15.0 + clerestory daylight windows.
	var north_openings: Array = [
		Rect2(-15.0, 0.0, 4.2, 3.5),
		Rect2(15.0, 0.0, 4.2, 3.5),
		Rect2(-18.0, 5.6, 4.0, 2.0),
		Rect2(-6.0, 5.6, 4.0, 2.0),
		Rect2(6.0, 5.6, 4.0, 2.0),
		Rect2(18.0, 5.6, 4.0, 2.0),
	]
	# South wall (Z = -25): Two wide ground portals at X = +-19.5 (4.5m clear of the ramp feet at +-15.0!)
	# + wide upper Mezzanine Rotunda arch at X = 0, Y = 3.4.
	var south_openings: Array = [
		Rect2(-19.5, 0.0, 4.4, 3.6),
		Rect2(19.5, 0.0, 4.4, 3.6),
		Rect2(0.0, DECK_Y, 8.0, 3.8),
		Rect2(-18.0, 5.6, 4.0, 2.0),
		Rect2(-8.5, 3.8, 3.4, 2.2),
		Rect2(8.5, 3.8, 3.4, 2.2),
		Rect2(18.0, 5.6, 4.0, 2.0),
	]
	# West & East Gable walls (X = +-24): Wide ground portal at Z = -35.0 (local -2.0).
	var gable_openings: Array = [
		Rect2(-2.0, 0.0, 4.6, 3.8),
		Rect2(-2.5, 5.6, 3.6, 2.0),
		Rect2(3.5, 5.6, 3.6, 2.0),
	]
	pierced_wall(c + Vector3(0.0, 0.0, -hz), CONCOURSE_SIZE.x + t, h, t, north_openings, false, "brick")
	pierced_wall(c + Vector3(0.0, 0.0, hz), CONCOURSE_SIZE.x + t, h, t, south_openings, false, "brick")
	for side: float in [-1.0, 1.0]:
		pierced_wall(c + Vector3(side * hx, 0.0, 0.0), CONCOURSE_SIZE.y - t, h, t, gable_openings, true, "brick")
		for sz: float in [-1.0, 1.0]:
			b.box("CornerPost", c + Vector3(side * (hx + 0.15), h * 0.5, sz * (hz + 0.15)), Vector3(0.65, h, 0.65), Color("b5b2a9"))
	b.box("Roof", c + Vector3(0.0, h + 0.2, 0.0), Vector3(CONCOURSE_SIZE.x + 1.2, 0.4, CONCOURSE_SIZE.y + 1.2), Color("4a5256"), false)
	b.box("InteriorSlab", c + Vector3(0.0, 0.015, 0.0), Vector3(CONCOURSE_SIZE.x - 0.4, 0.03, CONCOURSE_SIZE.y - 0.4), Color("cac7be"), false)
	b.sign_text("NORTH OVERHAUL CONCOURSE  —  BAYS A & B", c + Vector3(0.0, h - 0.7, hz + t * 0.5 + 0.05), 0.0, SAFETY_YELLOW, 68)
	for tx: int in range(-18, 19, 6):
		b.detail(c + Vector3(float(tx), h - 0.5, 0.0), Vector3(0.28, 0.6, CONCOURSE_SIZE.y - 0.8), STEEL)
	b.box("Gantry", c + Vector3(-5.0, 6.8, 0.0), Vector3(1.8, 0.55, CONCOURSE_SIZE.y - 1.2), SAFETY_YELLOW, false)
	# Ground-floor overhaul machinery along Z = -35.0 (Bogie Jacks & Wheel Lathes).
	for side: float in [-1.0, 1.0]:
		bogie_jack_station(Vector3(side * 9.5, 0.0, -35.0))
		wheel_lathe(Vector3(side * 19.5, 0.0, -30.0), side)
		b.prop("steel_frame_shelves_02", Vector3(side * 20.5, 0.0, -39.8), 2.2, 0.0)
		b.prop("industrial_storage_cart", Vector3(side * 4.2, 0.0, -39.5), 1.0, 0.0)
	b.box("Cover", Vector3(0.0, 1.1, -35.0), Vector3(2.4, 2.2, 3.0), DEPOT_BLUE)
	add_cover_pair(Vector3(-2.2, 0.0, -35.0), Vector3(-2.2, 0.0, -37.5))
	add_cover_pair(Vector3(2.2, 0.0, -35.0), Vector3(2.2, 0.0, -37.5))
	for lx: float in [-16.0, -5.5, 5.5, 16.0]:
		b.box("CeilingLamp", c + Vector3(lx, h - 0.7, -2.0), Vector3(1.4, 0.08, 0.45), Color("fff3d6"), false)
		b.bake_light(c + Vector3(lx, h - 1.0, -2.0), WARM_HALIDE, 3.6, 12.5)
	var c_vol: Vector3 = Vector3(CONCOURSE_SIZE.x - 0.8, h, CONCOURSE_SIZE.y - 0.8)
	b.arena.probe_volumes.append(AABB(c + Vector3(0.0, h * 0.5, 0.0) - c_vol * 0.5, c_vol))

# 2. Concourse Mezzanine Gallery (Z = -26.8, Y = 3.4) & Signal Rotunda Balcony (0, 3.4, -21.5)
func concourse_mezzanine_and_rotunda() -> void:
	# Interior Mezzanine Deck spanning X = -10..10, Z = -28.6..-25.0 at Y = 3.4 m.
	b.box("Worktop", Vector3(0.0, DECK_Y - 0.15, MEZZ_Z), Vector3(20.0, 0.3, 3.6), STEEL)
	b.box("RailServiceCabin", Vector3(0.0, 1.55, MEZZ_Z), Vector3(19.8, 3.1, 3.5), COBALT_TRIM)
	# Cantilevered Signal Rotunda Balcony hugging the Concourse South Wall (X = -4.0..4.0, Z = -25.0..-19.0, Y = 3.4 m).
	b.box("Worktop", Vector3(0.0, DECK_Y - 0.15, -22.0), Vector3(8.0, 0.3, 6.0), STEEL)
	b.box("DeckEdge", Vector3(0.0, DECK_Y - 0.3, -19.0), Vector3(8.2, 0.36, 0.14), SAFETY_YELLOW, false)
	b.box("RailServiceCabin", Vector3(0.0, 1.55, -22.0), Vector3(7.8, 3.1, 5.8), DEPOT_BLUE)
	b.sign_text("SIGNAL ROTUNDA  /  YARD CONTROL", Vector3(0.0, 2.55, -19.02), 0.0, SAFETY_YELLOW, 28)
	for side: float in [-1.0, 1.0]:
		add_cover_pair(Vector3(side * 2.4, 0.0, -17.5), Vector3(side * 4.6, 0.0, -17.5))
		# Gentle 17.2-degree Ramps hugging the Concourse South Wall along Z = -23.2 (X = +-15.0 -> +-4.0),
		# leaving zero gap against Z = -25.0 and 4.5 m of clear plaza to the South Doors at X = +-19.5!
		b.ramp(Vector3(side * 15.0, 0.0, RAMP_Z), Vector3(side * 4.0, DECK_Y, RAMP_Z), 3.2)
		var run: float = 11.0
		var step: float = 4.2
		while step < 13.4:
			var top_h: float = ((15.0 - (step + 1.5)) / run) * DECK_Y - 0.35
			if top_h > 0.15:
				b.box("Sill", Vector3(side * (step + 0.75), top_h * 0.5, RAMP_Z), Vector3(1.5, top_h, 3.0), Color("a6a49b"))
			step += 1.5
	b.railing_path([Vector3(-3.9, DECK_Y, -19.1), Vector3(3.9, DECK_Y, -19.1)], 1.05, SAFETY_YELLOW, 1.5, true)
	b.railing_path([Vector3(-9.8, DECK_Y, -28.5), Vector3(9.8, DECK_Y, -28.5)], 1.05, SAFETY_YELLOW, 1.5, true)
	for lx: float in [-6.0, 0.0, 6.0]:
		emergency_lamp(Vector3(lx, DECK_Y + 2.4, MEZZ_Z), 2.2, 9.0, WARM_HALIDE)

# 3. Center Arena: 16 m Circular Locomotive Turntable Ring & Loco 801 at (0, 0, 5)
func central_locomotive_turntable() -> void:
	var tc: Vector3 = TURNTABLE_C
	b.footprints.append(Rect2(tc.x - 8.5, tc.z - 8.5, 17.0, 17.0))
	var ring_floor: MeshInstance3D = b.cylinder(tc + Vector3(0.0, 0.015, 0.0), TURNTABLE_R, 0.03, Color("485054"))
	ring_floor.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	for seg: int in 24:
		var ang: float = TAU * float(seg) / 24.0
		var rx: float = tc.x + cos(ang) * TURNTABLE_R
		var rz: float = tc.z + sin(ang) * TURNTABLE_R
		b.detail(Vector3(rx, 0.06, rz), Vector3(2.1, 0.1, 0.36), SAFETY_YELLOW if seg % 2 == 0 else Color("8a8880"), "concrete", Vector3(0.0, -ang + PI * 0.5, 0.0))
	b.box("Worktop", tc + Vector3(0.0, 0.04, 0.0), Vector3(14.8, 0.08, 3.8), STEEL, false)
	for sz: float in [-1.85, 1.85]:
		b.box("Cover", tc + Vector3(0.0, 0.62, sz), Vector3(11.6, 1.24, 0.42), SAFETY_YELLOW)
	var loco_c: Vector3 = tc + Vector3(3.2, 0.0, 0.0)
	b.box("RailServiceCabin", loco_c + Vector3(0.0, 1.55, 0.0), Vector3(5.6, 3.1, 2.5), SHUNTER_ORANGE)
	b.detail(loco_c + Vector3(-1.2, 2.6, 0.0), Vector3(2.2, 1.0, 2.4), COBALT_TRIM, "steel")
	for sz: float in [-1.0, 1.0]:
		b.sign_text("TURNTABLE LOCO 801", loco_c + Vector3(0.0, 1.9, sz * 1.28), 0.0 if sz > 0.0 else PI, SAFETY_YELLOW, 24)
	for ax_dx: float in [-1.6, 1.6]:
		wheelset(loco_c + Vector3(ax_dx, 0.0, 0.0))
	var booth_c: Vector3 = tc + Vector3(-3.8, 0.0, 0.0)
	b.box("Cover", booth_c + Vector3(0.0, 0.68, 0.0), Vector3(2.6, 1.36, 2.2), DEPOT_BLUE)
	b.box("CoverCap", booth_c + Vector3(0.0, 1.4, 0.0), Vector3(2.72, 0.08, 2.32), SAFETY_YELLOW, false)
	for px: float in [-5.4, 5.4]:
		for pz: float in [-1.85, 1.85]:
			b.detail(tc + Vector3(px, 2.4, pz), Vector3(0.18, 4.8, 0.18), SAFETY_YELLOW, "steel")
		b.detail(tc + Vector3(px, 4.7, 0.0), Vector3(0.2, 0.28, 3.9), SAFETY_YELLOW, "steel")
	b.detail(tc + Vector3(0.0, 4.85, 0.0), Vector3(11.2, 0.24, 0.4), DEPOT_BLUE, "steel")
	b.sign_text("ROTARY TURNTABLE  —  PIT 01", tc + Vector3(0.0, 4.85, -0.24), PI, SAFETY_YELLOW, 26)
	b.sign_text("ROTARY TURNTABLE  —  PIT 01", tc + Vector3(0.0, 4.85, 0.24), 0.0, SAFETY_YELLOW, 26)
	for sx: float in [-5.8, 0.0, 5.8]:
		add_cover_pair(tc + Vector3(sx, 0.0, -3.1), tc + Vector3(sx + 1.8, 0.0, -3.1))
		add_cover_pair(tc + Vector3(sx, 0.0, 3.1), tc + Vector3(sx - 1.8, 0.0, 3.1))

# 4. Offset Walk-Through Commuter Metro Cars ("CAR 401" at (-20, 0, -5) and "CAR 402" at (20, 0, 5))
func offset_walkthrough_metro_cars() -> void:
	for side: float in [-1.0, 1.0]:
		var mc: Vector3 = Vector3(side * 20.0, 0.0, side * 5.0)
		var length: float = 16.0
		var width: float = 4.4
		var h: float = 3.5
		var t: float = 0.32
		var hz: float = width * 0.5
		var hx: float = length * 0.5
		b.footprints.append(Rect2(mc.x - hx, mc.z - hz, length, width))
		var side_openings: Array = [
			Rect2(-4.6, 0.0, 3.6, 2.85),
			Rect2(0.0, 1.05, 2.2, 1.35),
			Rect2(4.6, 0.0, 3.6, 2.85),
		]
		var end_openings: Array = [
			Rect2(0.0, 0.0, 3.0, 2.85),
		]
		pierced_wall(mc + Vector3(0.0, 0.0, -hz), length + t, h, t, side_openings, false, "painted_metal", LIVERY_SILVER)
		pierced_wall(mc + Vector3(0.0, 0.0, hz), length + t, h, t, side_openings, false, "painted_metal", LIVERY_SILVER)
		for sx: float in [-1.0, 1.0]:
			pierced_wall(mc + Vector3(sx * hx, 0.0, 0.0), width - t, h, t, end_openings, true, "painted_metal", LIVERY_SILVER)
		b.box("Roof", mc + Vector3(0.0, h + 0.14, 0.0), Vector3(length + 0.2, 0.28, width + 0.2), DEPOT_BLUE, false)
		b.box("InteriorSlab", mc + Vector3(0.0, 0.02, 0.0), Vector3(length - 0.2, 0.04, width - 0.2), Color("5b656b"), false)
		b.box("Ventilation", mc + Vector3(0.0, h + 0.45, 0.0), Vector3(3.6, 0.36, 2.1), GALV, false)
		var car_title: String = "METRO CAR 401" if side < 0.0 else "METRO CAR 402"
		for sz: float in [-1.0, 1.0]:
			var face_z: float = mc.z + sz * (hz + t * 0.5 + 0.02)
			b.detail(Vector3(mc.x, 0.55, face_z), Vector3(2.4, 0.45, 0.03), DEPOT_BLUE, "steel")
			b.detail(Vector3(mc.x, 0.88, face_z + sz * 0.01), Vector3(2.4, 0.14, 0.03), LIVERY_STRIPE, "steel")
			b.sign_text(car_title, Vector3(mc.x, 3.18, face_z + sz * 0.02), 0.0 if sz > 0.0 else PI, SAFETY_YELLOW, 28)
			add_cover_pair(mc + Vector3(-6.8, 0.0, sz * 3.3), mc + Vector3(-8.8, 0.0, sz * 3.3))
			add_cover_pair(mc + Vector3(0.0, 0.0, sz * 3.3), mc + Vector3(2.2, 0.0, sz * 3.3))
			add_cover_pair(mc + Vector3(6.8, 0.0, sz * 3.3), mc + Vector3(8.8, 0.0, sz * 3.3))
		for bogie_dx: float in [-5.8, 5.8]:
			wheelset(mc + Vector3(bogie_dx, 0.0, 0.0))
		b.bake_light(mc + Vector3(0.0, 3.15, 0.0), COOL_LED, 2.4, 7.5)

# 5. South Zone: 3-Bay Stepped Fan Roundhouse Arc facing the Turntable
func south_fan_roundhouse() -> void:
	roundhouse_stall(Vector3(0.0, 0.0, 34.0), Vector2(18.0, 12.0), 6.2, "ROUNDHOUSE STALL 02  —  HEAVY OVERHAUL", 0.0)
	for side: float in [-1.0, 1.0]:
		var stall_num: String = "01" if side < 0.0 else "03"
		roundhouse_stall(Vector3(side * 22.0, 0.0, 30.0), Vector2(14.0, 11.0), 5.4, "ROUNDHOUSE STALL " + stall_num, side)

func roundhouse_stall(c: Vector3, size: Vector2, h: float, title: String, side_flag: float) -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.y * 0.5
	var t: float = 0.35
	b.footprints.append(Rect2(c.x - hx, c.z - hz, size.x, size.y))
	b.buildings.append({"center": c, "size": size, "height": h, "furnished": false, "door": 3.4, "wall": t})
	var north_open: Array = [
		Rect2(0.0, 0.0, 4.6, 3.6),
		Rect2(-hx + 2.6, 1.2, 2.4, 1.5),
		Rect2(hx - 2.6, 1.2, 2.4, 1.5),
	]
	var south_open: Array = [
		Rect2(0.0, 0.0, 4.0, 3.2),
		Rect2(-hx + 2.6, 1.2, 2.4, 1.5),
		Rect2(hx - 2.6, 1.2, 2.4, 1.5),
	]
	var side_open: Array = [
		Rect2(0.0, 0.0, 3.8, 3.2),
		Rect2(-3.2, 1.2, 1.8, 1.4),
		Rect2(3.2, 1.2, 1.8, 1.4),
	]
	pierced_wall(c + Vector3(0.0, 0.0, -hz), size.x + t, h, t, north_open, false, "brick")
	pierced_wall(c + Vector3(0.0, 0.0, hz), size.x + t, h, t, south_open, false, "brick")
	for sx: float in [-1.0, 1.0]:
		pierced_wall(c + Vector3(sx * hx, 0.0, 0.0), size.y - t, h, t, side_open, true, "brick")
	b.box("Roof", c + Vector3(0.0, h + 0.18, 0.0), Vector3(size.x + 0.8, 0.36, size.y + 0.8), COBALT_TRIM, false)
	b.box("InteriorSlab", c + Vector3(0.0, 0.015, 0.0), Vector3(size.x - 0.3, 0.03, size.y - 0.3), Color("cccac2"), false)
	b.sign_text(title, c + Vector3(0.0, h - 0.65, -hz - t * 0.5 - 0.05), PI, SAFETY_YELLOW, 38)
	var bench_x: float = hx - 2.2
	var bench_z: float = hz - 1.9
	b.box("Worktop", c + Vector3(bench_x, 0.52, bench_z), Vector3(2.0, 1.04, 0.9), DEPOT_BLUE)
	b.box("Worktop", c + Vector3(-bench_x, 0.52, -bench_z), Vector3(2.0, 1.04, 0.9), SAFETY_YELLOW)
	add_cover_pair(c + Vector3(bench_x - 1.8, 0.0, bench_z), c + Vector3(bench_x - 1.8, 0.0, 0.0))
	add_cover_pair(c + Vector3(-bench_x + 1.8, 0.0, -bench_z), c + Vector3(-bench_x + 1.8, 0.0, 0.0))
	if absf(side_flag) < 0.1:
		b.prop("old_military_compressor", c + Vector3(-bench_x, 0.0, bench_z), 1.45)
		b.prop("steel_frame_shelves_02", c + Vector3(bench_x, 0.0, -bench_z), 2.2, PI)
	b.interior_lighting(c, size, h)

# 6. Yard Tracks, Radial Turntable Tracks & Trackside Equipment
func yard_tracks_and_props() -> void:
	track_run(-39.0, -8.5, -5.0)
	track_run(8.5, 39.0, -5.0)
	track_run(-39.0, -8.5, 5.0)
	track_run(8.5, 39.0, 5.0)
	track_z_run(0.0, 13.0, 39.0)
	track_z_run(-22.0, 14.0, 35.0)
	track_z_run(22.0, 14.0, 35.0)
	for side: float in [-1.0, 1.0]:
		var tc: Vector3 = Vector3(side * 31.5, 0.0, -35.0)
		b.box("Freight", tc + Vector3(0.0, 1.35, 0.0), Vector3(5.2, 2.7, 2.4), TRANSFORMER_GREEN)
		b.sign_text("25 kV SUB " + ("W" if side < 0.0 else "E"), tc + Vector3(0.0, 2.15, 1.24), 0.0, SAFETY_YELLOW, 28)
		add_cover_pair(tc + Vector3(0.0, 0.0, 2.3), tc + Vector3(side * 3.2, 0.0, 2.3))
		b.cover(Vector3(side * 22.0, 0.0, -14.0), 2.6, SAFETY_YELLOW)
		b.cover(Vector3(side * 34.0, 0.0, -7.5), 2.6, SAFETY_YELLOW)
		b.cover(Vector3(side * 34.0, 0.0, 7.5), 2.6, SAFETY_YELLOW)
		b.cover(Vector3(side * 11.0, 0.0, 21.0), 2.6, SAFETY_YELLOW)
		b.cargo_cluster(Vector3(side * 11.5, 0.0, -12.5), 0.0)
		buffer_stop(Vector3(side * 39.5, 0.0, -5.0), -side)
		buffer_stop(Vector3(side * 39.5, 0.0, 5.0), -side)
		signal_mast(Vector3(side * 10.5, 0.0, -1.5), side < 0.0)
		signal_mast(Vector3(side * 10.5, 0.0, 11.5), side > 0.0)
		flood_mast(Vector3(side * 30.0, 0.0, -18.5), 10.0, Vector3(side * 14.0, 0.0, -14.0), 4.6, 28.0)
		flood_mast(Vector3(side * 33.0, 0.0, 16.5), 10.0, Vector3(side * 12.0, 0.0, 18.0), 4.6, 28.0)
		b.prop("portable_generator", Vector3(side * 35.5, 0.0, -35.0), 0.95, 0.0)
		b.prop("industrial_pastic_container", Vector3(side * 34.0, 0.0, 41.2), 1.15)
		b.prop("industrial_pastic_container", Vector3(side * 12.0, 0.0, 41.2), 1.15)
		b.prop("old_military_compressor", Vector3(side * 31.0, 0.0, 41.2), 1.45)
		for bi: int in 3:
			b.prop("barrel_03", Vector3(side * (37.0 + float(bi) * 0.8), 0.0, -39.5), 0.88)
			b.prop("Barrel_01", Vector3(side * (14.5 + float(bi) * 0.8), 0.0, 41.2), 0.88)

func wheelset(center: Vector3) -> void:
	var axle: MeshInstance3D = b.cylinder(center + Vector3(0.0, 0.46, 0.0), 0.08, 1.62, STEEL)
	axle.rotation.x = PI * 0.5
	for side: float in [-0.72, 0.72]:
		var wheel: MeshInstance3D = b.cylinder(center + Vector3(0.0, 0.46, side), 0.44, 0.13, RAIL_RUST)
		wheel.rotation.x = PI * 0.5
		var flange: MeshInstance3D = b.cylinder(center + Vector3(0.0, 0.46, side - signf(side) * 0.05), 0.49, 0.04, GALV)
		flange.rotation.x = PI * 0.5

func bogie_jack_station(center: Vector3) -> void:
	for sz: float in [-1.35, 1.35]:
		var post: Vector3 = center + Vector3(0.0, 0.0, sz)
		b.box("Cover", post + Vector3(0.0, 1.3, 0.0), Vector3(0.85, 2.6, 0.75), SAFETY_YELLOW)
	b.box("Gantry", center + Vector3(0.0, 2.72, 0.0), Vector3(1.1, 0.24, 3.4), SAFETY_YELLOW, false)
	b.box("Worktop", center + Vector3(0.0, 0.65, 0.0), Vector3(2.4, 0.9, 1.6), DEPOT_BLUE)
	add_cover_pair(center + Vector3(0.0, 0.0, 2.25), center + Vector3(2.0, 0.0, 2.25))
	add_cover_pair(center + Vector3(0.0, 0.0, -2.25), center + Vector3(-2.0, 0.0, -2.25))

func wheel_lathe(center: Vector3, side: float) -> void:
	b.box("Sill", center + Vector3(0.0, 0.65, 0.0), Vector3(3.0, 1.3, 1.4), DEPOT_BLUE)
	b.box("Worktop", center + Vector3(0.0, 1.42, 0.0), Vector3(2.6, 0.3, 1.15), GALV, false)
	wheelset(center + Vector3(0.0, 0.88, 0.0))
	add_cover_pair(center + Vector3(0.0, 0.0, -1.65), center + Vector3(side * 2.2, 0.0, -1.65))
	add_cover_pair(center + Vector3(0.0, 0.0, 1.65), center + Vector3(-side * 2.2, 0.0, 1.65))

func track_run(x0: float, x1: float, z: float) -> void:
	var length: float = x1 - x0
	var mid_x: float = (x0 + x1) * 0.5
	for rail_s: float in [-0.72, 0.72]:
		b.detail(Vector3(mid_x, 0.038, z + rail_s), Vector3(length, 0.028, 0.09), RAIL_RUST, "steel")
	var count: int = int(length / 2.0)
	for i: int in count:
		var sx: float = x0 + (float(i) + 0.5) * (length / float(count))
		b.detail(Vector3(sx, 0.012, z), Vector3(0.28, 0.02, 2.1), TIMBER, "concrete")

func track_z_run(x: float, z0: float, z1: float) -> void:
	var length: float = z1 - z0
	var mid_z: float = (z0 + z1) * 0.5
	for rail_s: float in [-0.72, 0.72]:
		b.detail(Vector3(x + rail_s, 0.038, mid_z), Vector3(0.09, 0.028, length), RAIL_RUST, "steel")
	var count: int = int(length / 2.0)
	for i: int in count:
		var sz: float = z0 + (float(i) + 0.5) * (length / float(count))
		b.detail(Vector3(x, 0.012, sz), Vector3(2.1, 0.02, 0.28), TIMBER, "concrete")

func buffer_stop(center: Vector3, facing_x: float) -> void:
	b.box("Cover", center + Vector3(0.0, 0.65, 0.0), Vector3(1.3, 1.3, 2.2), SAFETY_YELLOW)
	b.detail(center + Vector3(facing_x * 0.62, 1.18, 0.0), Vector3(0.08, 0.22, 1.8), SIGNAL_RED, "steel")
	add_cover_pair(center + Vector3(0.0, 0.0, 1.95), center + Vector3(facing_x * 1.6, 0.0, 1.95))
	add_cover_pair(center + Vector3(0.0, 0.0, -1.95), center + Vector3(facing_x * 1.6, 0.0, -1.95))

func signal_mast(base: Vector3, green_aspect: bool) -> void:
	b.cylinder(base + Vector3(0.0, 2.1, 0.0), 0.08, 4.2, GALV)
	b.box("LampHousing", base + Vector3(0.0, 3.85, 0.0), Vector3(0.24, 0.85, 0.36), Color("1c2022"), false)
	var aspect_col: Color = SIGNAL_GREEN if green_aspect else SIGNAL_RED
	var lens_y: float = 4.05 if green_aspect else 3.65
	var lens: Node3D = b.box("EmergencyLens", base + Vector3(0.0, lens_y, 0.0), Vector3(0.28, 0.2, 0.2), aspect_col, false)
	(lens.get_child(0) as MeshInstance3D).material_override = glow(aspect_col, 6.0)

# --- Custom Deployment: Corner Pavilions & Open-Air Platform Canopies (Zero (44,0) Box!) ---

func deployment(builder: CompactMapBuilder) -> void:
	b = builder
	for team: int in 2:
		var side: float = -1.0 if team == 0 else 1.0
		for row: int in 4:
			for col: int in 4:
				var z_row: float = [-34.0, -5.0, 5.0, 34.0][row]
				var p: Vector3 = Vector3(side * (51.5 - float(col) * 2.0), 0.05, z_row)
				if team == 0:
					b.def.spawns_blue.append(p)
				else:
					b.def.spawns_red.append(p)
		# Open-Air Cantilevered Platform Canopy at (side * 46, 0, 0) instead of a solid building!
		var pc: Vector3 = Vector3(side * 46.0, 0.0, 0.0)
		b.box("Roof", pc + Vector3(0.0, 4.8, 0.0), Vector3(9.0, 0.28, 16.0), COBALT_TRIM, false)
		b.detail(pc + Vector3(0.0, 4.6, 0.0), Vector3(8.6, 0.16, 0.5), SAFETY_YELLOW, "steel")
		for cz: float in [-6.5, 0.0, 6.5]:
			b.box("SteelColumn", pc + Vector3(-side * 3.8, 2.4, cz), Vector3(0.3, 4.8, 0.3), STEEL)
		var plat_title: String = "WEST PLATFORM 1" if team == 0 else "EAST PLATFORM 2"
		b.sign_text(plat_title, pc + Vector3(-side * 4.55, 4.35, 0.0), -side * PI * 0.5, SAFETY_YELLOW, 36)
		b.bake_light(pc + Vector3(0.0, 4.3, 0.0), COOL_LED, 2.6, 11.0)
		# Twin Corner Pavilions at (side * 41.0, 0, -20.0) and (side * 41.0, 0, +22.0) (10 x 10 m, H = 4.2 m)
		for sz: float in [-1.0, 1.0]:
			var kz: float = -20.0 if sz < 0.0 else 22.0
			var kc: Vector3 = Vector3(side * 41.0, 0.0, kz)
			var ksize: Vector2 = Vector2(10.0, 10.0)
			var kh: float = 4.2
			var kt: float = 0.32
			b.footprints.append(Rect2(kc.x - ksize.x * 0.5, kc.z - ksize.y * 0.5, ksize.x, ksize.y))
			b.buildings.append({"center": kc, "size": ksize, "height": kh, "furnished": false, "door": 3.0, "wall": kt})
			var k_open: Array = [
				Rect2(0.0, 0.0, 3.8, 3.0),
				Rect2(-3.0, 1.2, 1.8, 1.3),
				Rect2(3.0, 1.2, 1.8, 1.3),
			]
			pierced_wall(kc + Vector3(0.0, 0.0, -ksize.y * 0.5), ksize.x + kt, kh, kt, k_open, false, "precast", Color("ccd2d4"))
			pierced_wall(kc + Vector3(0.0, 0.0, ksize.y * 0.5), ksize.x + kt, kh, kt, k_open, false, "precast", Color("ccd2d4"))
			for sx: float in [-1.0, 1.0]:
				pierced_wall(kc + Vector3(sx * ksize.x * 0.5, 0.0, 0.0), ksize.y - kt, kh, kt, k_open, true, "precast", Color("ccd2d4"))
			b.box("Roof", kc + Vector3(0.0, kh + 0.18, 0.0), Vector3(ksize.x + 0.6, 0.36, ksize.y + 0.6), DEPOT_BLUE, false)
			b.box("InteriorSlab", kc + Vector3(0.0, 0.015, 0.0), Vector3(ksize.x - 0.3, 0.03, ksize.y - 0.3), Color("ceccc4"), false)
			var k_label: String = ("TRACTION RELAY " if sz < 0.0 else "CREW DISPATCH ") + ("W" if team == 0 else "E")
			b.sign_text(k_label, kc + Vector3(-side * (ksize.x * 0.5 + kt * 0.5 + 0.04), kh - 0.55, 0.0), -side * PI * 0.5, SAFETY_YELLOW, 32)
			b.interior_lighting(kc, ksize, kh)

# --- Custom Objectives & Bot Routes ------------------------------------------------

func objectives(builder: CompactMapBuilder) -> void:
	b = builder
	var caches: Array[Vector3] = [
		Vector3(-14.0, 0.0, -31.5),
		Vector3(14.0, 0.0, -31.5),
		Vector3(-26.0, 0.0, -14.0),
		Vector3(26.0, 0.0, -14.0),
		Vector3(-11.0, 0.0, 5.0),
		Vector3(11.0, 0.0, 5.0),
		Vector3(-12.0, 0.0, 28.0),
		Vector3(12.0, 0.0, 28.0),
	]
	for p: Vector3 in caches:
		b.def.ammo_caches.append(p)
		b.box("AmmoCase", p + Vector3(0.0, 0.35, 0.0), Vector3(1.1, 0.7, 0.65), Color("59644d"))
		b.sign_text("SUPPLIES", p + Vector3(0.0, 0.42, 0.333), 0.0, Color("c9d9c5"), 15)
	var route_pts: Array[Vector3] = [
		Vector3(-34.0, 0.05, -29.0),
		Vector3(-19.5, 0.05, -20.0),
		Vector3(0.0, 0.05, -14.0),
		Vector3(19.5, 0.05, -20.0),
		Vector3(34.0, 0.05, -29.0),
		Vector3(-36.0, 0.05, 0.0),
		Vector3(-20.0, 0.05, -5.0),
		Vector3(0.0, 0.05, -1.0),
		Vector3(20.0, 0.05, 5.0),
		Vector3(36.0, 0.05, 0.0),
		Vector3(-34.0, 0.05, 22.0),
		Vector3(-22.0, 0.05, 30.0),
		Vector3(0.0, 0.05, 34.0),
		Vector3(22.0, 0.05, 30.0),
		Vector3(34.0, 0.05, 22.0),
	]
	b.def.routes.assign(route_pts)
	b.def.domination.assign([
		Vector3(-20.0, 0.0, -5.0),
		Vector3(0.0, 0.0, -1.0),
		Vector3(20.0, 0.0, 5.0),
	])
	b.def.hardpoints.assign([
		Vector3(0.0, 0.0, -1.0),
		Vector3(0.0, 0.0, 34.0),
		Vector3(-15.0, 0.0, -35.0),
		Vector3(-22.0, 0.0, 30.0),
		Vector3(22.0, 0.0, 30.0),
	])
	b.def.qa_route.assign([
		Vector3(-45.5, 0.0, -5.0),
		Vector3(-28.0, 0.0, -14.0),
		Vector3(-16.5, 0.0, RAMP_Z),
		Vector3(-2.5, DECK_Y, RAMP_Z),
		Vector3(0.0, DECK_Y, MEZZ_Z),
		Vector3(2.5, DECK_Y, RAMP_Z),
		Vector3(16.5, 0.0, RAMP_Z),
		Vector3(20.0, 0.0, 5.0),
		Vector3(0.0, 0.0, 34.0),
		Vector3(-20.0, 0.0, -5.0),
		Vector3(-45.5, 0.0, 5.0),
	])

# --- Realism & Clutter Pass --------------------------------------------------------

func dress(builder: CompactMapBuilder) -> void:
	b = builder
	for side: float in [-1.0, 1.0]:
		b.pipe_stack(Vector3(side * 44.0, 0.0, -41.0), 0.0, 5.0)
		b.cable_reel(Vector3(side * 42.0, 0.0, 41.0), 0.25 * side)
		b.pallet(Vector3(side * 28.0, 0.0, -41.0), 0.15 * side, 2)
		b.pallet(Vector3(side * 34.0, 0.0, 38.5), -0.15 * side, 2)
		b.cone(Vector3(side * 16.0, 0.0, -20.5))
		b.cone(Vector3(side * 10.0, 0.0, 14.0))
		b.small_prop("old_tyre", Vector3(side * 48.0, 0.0, 40.5), 0.6, 0.4, true)
		b.small_prop("trashbag", Vector3(side * 35.0, 0.0, -25.0), 0.5, 0.2, true)
		b.small_prop("security_camera_02", Vector3(side * 23.5, 6.8, -25.2), 0.3, side)
	b.small_prop("WetFloorSign_01", Vector3(-3.8, 0.0, -14.2), 0.62, 0.4, true)
	for data: Dictionary in b.buildings:
		b.interior_streaks(data, 2)
	var yard_area: Rect2 = Rect2(-52.0, -42.0, 104.0, 84.0)
	b.floor_decals("Leaking006", 9, yard_area, Vector2(2.8, 2.8), Color(0.04, 0.035, 0.03, 0.95))
	b.floor_decals("Leaking009", 6, yard_area, Vector2(3.0, 3.0), Color(0.07, 0.06, 0.05, 0.75))
	b.floor_decals("Leaking010A", 5, yard_area, Vector2(2.4, 3.4), Color(0.09, 0.075, 0.06, 0.7))
	b.floor_decals("AsphaltDamage001", 8, yard_area, Vector2(3.4, 3.4), Color(0.7, 0.7, 0.68, 0.8))

func ground_splat(builder: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n: float = noise.get_noise_2d(x, z)
	var fine: float = noise.get_noise_2d(x * 3.3 + 170.0, z * 3.3 - 40.0)
	var apron: float = builder.footprint_distance(x, z)
	var edge: float = minf(builder.def.extent.x * 0.5 - absf(x), builder.def.extent.y * 0.5 - absf(z))
	var concrete: float = maxf(1.0 - smoothstep(2.0, 7.0, apron + n * 2.5), smoothstep(78.0, 83.0, absf(x) + n * 3.0))
	var track_d: float = minf(absf(z - 5.0), absf(z + 5.0))
	var ballast: float = 1.0 - smoothstep(1.2, 3.2, track_d + n * 0.8)
	var dirt: float = maxf(1.0 - smoothstep(1.0, 7.0, edge + n * 4.0), smoothstep(0.42, 0.8, fine) * 0.82)
	return Color(concrete, ballast * (1.0 - concrete * 0.35), dirt * (1.0 - concrete * 0.6))
