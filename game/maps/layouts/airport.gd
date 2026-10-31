extends MapLayout

# A compact regional airport: a glazed terminal and security hall to the north,
# baggage handling to the west, a maintenance hangar to the east, and a parked
# passenger jet on the apron. Two boarding ramps and the cabin form an upper loop.
# Runways and the control tower belong to the airport beyond the playable fence.

const NAVY := Color("163e59")
const TEAL := Color("168e9b")
const WHITE := Color("e8ecec")
const YELLOW := Color("dfb337")
const DARK := Color("263238")
const FRAME_WIDTH := .08
const FRAME_LIP := .03
const CABIN := 2.6
const JET := Vector3(15,0,20)

var b: CompactMapBuilder
var materials := {}

class AirfieldNature extends MapNature:
	func _init(owner: MapBuilder) -> void:super(owner)
	func height(x: float,z: float) -> float:
		return super(x,z)*smoothstep(250.0,500.0,Vector2(x,z).length())
	func splat(_x: float,_z: float,_h: float,_n: Vector3) -> Color:return Color(0,0,0)
	func terrain() -> void:
		super()
		(arena.get_node("Terrain") as GeometryInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var key:=color.to_html()+str(metallic)
	if not materials.has(key):
		var mat:=StandardMaterial3D.new();mat.albedo_color=color
		mat.roughness=.42;mat.metallic=metallic
		materials[key]=mat
	return materials[key]

func block(label: String, at: Vector3, size: Vector3, color: Color, solid := true, parent: Node3D = null) -> Node3D:
	var node:=b.box(label,at,size,color,solid,parent)
	(node.get_child(0) as MeshInstance3D).material_override=material(color,.12)
	return node

func mesh_node(label: String, mesh: ArrayMesh, mat: Material, at: Vector3, solid := true, parent: Node3D = null) -> MeshInstance3D:
	mesh.lightmap_unwrap(Transform3D.IDENTITY,.35)
	var node:=MeshInstance3D.new();node.name=label;node.mesh=mesh;node.material_override=mat
	node.position=at;node.gi_mode=GeometryInstance3D.GI_MODE_STATIC
	(b.region if parent==null else parent).add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
		var collider:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new()
		shape.set_faces(mesh.get_faces());shape.backface_collision=true;collider.shape=shape
		body.add_child(collider);node.add_child(body)
	return node

func quad(st: SurfaceTool, points: Array, normal: Vector3, color := Color.WHITE) -> void:
	for tri in [[0,1,2],[0,2,3]]:
		var p:Vector3=points[tri[0]];var q:Vector3=points[tri[1]];var r:Vector3=points[tri[2]]
		if (q-p).cross(r-p).dot(normal)>0:var swap:=q;q=r;r=swap
		for v in [p,q,r]:
			st.set_normal(normal);st.set_color(color);st.set_uv(Vector2(v.x+v.z,v.y));st.add_vertex(v)

func finish(st: SurfaceTool) -> ArrayMesh:
	st.index();st.generate_tangents();return st.commit()

func cover_points(center: Vector3, size: Vector2) -> void:
	for side:float in [-1.0,1.0]:
		b.def.cover_points.append(center+Vector3(0,0,side*(size.y*.5+1.6)))
		b.def.cover_peeks.append(center+Vector3(size.x*.5+1.1,0,side*(size.y*.5+1.6)))

func boundaries(builder: CompactMapBuilder) -> void:
	b=builder;b.nature=AirfieldNature.new(b)
	b.arena.fixed_geometry_visibility=true
	b.region.navigation_mesh.agent_radius=.75;b.region.navigation_mesh.cell_size=.25
	b.region.navigation_mesh.agent_height=1.8;b.region.navigation_mesh.cell_height=.1
	var half:=b.def.extent*.5
	# Transparent security perimeter: actual posts and wire, backed by collision.
	for side:float in [-1.0,1.0]:
		b.collider(Vector3(side*half.x,3,0),Vector3(.2,6,b.def.extent.y))
		b.collider(Vector3(0,3,side*half.y),Vector3(b.def.extent.x,6,.2))
		for z in range(-int(half.y),int(half.y)+1,4):
			b.box("FencePost",Vector3(side*(half.x-.2),1.6,z),Vector3(.09,3.2,.09),DARK)
		for x in range(-int(half.x),int(half.x)+1,4):
			if side<0 and not north_fence_visible(x):continue
			b.box("FencePost",Vector3(x,1.6,side*(half.y-.2)),Vector3(.09,3.2,.09),DARK)
		for y:float in [.5,1.4,2.3,3.0]:
			b.detail(Vector3(side*(half.x-.2),y,0),Vector3(.025,.025,b.def.extent.y),Color("657278"))
			var spans:=[Vector2(-half.x,half.x)] if side>0 else [Vector2(-half.x,-45.2),Vector2(17.2,23.8),Vector2(48.2,half.x)]
			for span:Vector2 in spans:b.detail(Vector3((span.x+span.y)*.5,y,side*(half.y-.2)),Vector3(span.y-span.x,.025,.025),Color("657278"))
		for x in range(-int(half.x),int(half.x)+1):
			if side<0 and not north_fence_visible(x):continue
			b.detail(Vector3(x,1.5,side*(half.y-.2)),Vector3(.018,3,.018),Color("657278"))
		for z in range(-int(half.y),int(half.y)+1):b.detail(Vector3(side*(half.x-.2),1.5,z),Vector3(.018,3,.018),Color("657278"))
	backdrop()

func north_fence_visible(x: float) -> bool:
	return x< -45.2 or (x>17.2 and x<23.8) or x>48.2

func backdrop() -> void:
	# A real airfield horizon: runway, taxiway, low hangars, and control tower.
	for z:float in [100,180]:
		var runway:=block("Runway",Vector3(0,.035,z),Vector3(650,.07,32),Color("454c50"),false)
		(runway.get_child(0) as GeometryInstance3D).gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		for x in range(-300,301,24):b.detail(Vector3(x,.09,z),Vector3(12,.02,.7),WHITE)
		for x in range(-300,301,12):
			for side:float in [-1.0,1.0]:b.detail(Vector3(x,.12,z+side*15),Vector3(.18,.12,.18),Color("83b8e0"))
	for side:float in [-1.0,1.0]:
		var shed:=block("AirportHangars",Vector3(side*142,7,-72),Vector3(100,14,38),Color("b3bcc0"),false)
		(shed.get_child(0) as GeometryInstance3D).gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		for x in range(-40,41,20):block("HangarDoor",Vector3(side*142+x,5,-52.8),Vector3(15,10,.12),Color("75838a"),false)
	block("TowerShaft",Vector3(91,15,-42),Vector3(6,30,6),WHITE,false)
	block("TowerCab",Vector3(91,31,-42),Vector3(13,4,11),NAVY,false)
	block("TowerGlass",Vector3(91,31.5,-42),Vector3(13.1,2,11.1),Color("7cabb5"),false)
	block("TowerRoof",Vector3(91,34,-42),Vector3(15,.6,13),WHITE,false)
	b.detail(Vector3(91,37,-42),Vector3(.12,6,.12),DARK)

func wall(at: Vector3, length: float, height: float, openings: Array, along_z := false, glazed := false, kind := "plaster") -> void:
	var holes:Array=[]
	for rect:Rect2 in openings:holes.append(Rect2(rect.position.x-rect.size.x*.5+length*.5,rect.position.y,rect.size.x,rect.size.y))
	var node:=mesh_node("AirportWall",MapMeshes.wall(Vector3(length,height,.3),holes,.15),b.surfaces.get_material(kind),at+Vector3.UP*height*.5)
	if along_z:node.rotation.y=PI*.5
	var turn:=Basis(Vector3.UP,PI*.5 if along_z else 0.0)
	for rect:Rect2 in openings:
		# Cover the reveal with a 3 cm lip: flush inner faces fought the wall
		# at identical depth. Jambs stop at the header to avoid overlapping fronts.
		var centre:=at+turn*Vector3(rect.position.x,rect.position.y+rect.size.y*.5,0)
		for side:float in [-1.0,1.0]:
			var frame:=b.box("DoorFrame",centre+turn*Vector3(side*(rect.size.x*.5+FRAME_WIDTH*.5-FRAME_LIP),-FRAME_LIP*.5,0),Vector3(FRAME_WIDTH,rect.size.y-FRAME_LIP,.36),DARK)
			if along_z:frame.rotation.y=PI*.5
		var head:=b.box("DoorFrame",centre+Vector3.UP*(rect.size.y*.5+FRAME_WIDTH*.5-FRAME_LIP),Vector3(rect.size.x+2.0*(FRAME_WIDTH-FRAME_LIP),FRAME_WIDTH,.36),DARK)
		if along_z:head.rotation.y=PI*.5
		if glazed and rect.position.y>.1:
			var pane:=b.box("WindowGlass",centre,Vector3(rect.size.x,rect.size.y,.06),Color("b6d7dd"))
			if along_z:pane.rotation.y=PI*.5
			(pane.get_child(0) as MeshInstance3D).material_override=b.glass_material()
			for x in range(1,ceili(rect.size.x/1.8)):
				var bar:=b.box("Mullion",centre+turn*Vector3(-rect.size.x*.5+x*1.8,0,0),Vector3(.05,rect.size.y,.12),DARK)
				if along_z:bar.rotation.y=PI*.5

func shell(center: Vector3, size: Vector2, height: float, north: Array, south: Array, west: Array, east: Array, glazed := false, north_open := false) -> void:
	b.footprints.append(Rect2(center.x-size.x*.5,center.z-size.y*.5,size.x,size.y))
	if not north_open:wall(center+Vector3(0,0,-size.y*.5),size.x,height,north,false,glazed)
	wall(center+Vector3(0,0,size.y*.5),size.x,height,south,false,glazed)
	wall(center+Vector3(-size.x*.5,0,0),size.y,height,west,true,glazed)
	wall(center+Vector3(size.x*.5,0,0),size.y,height,east,true,glazed)
	var roof:=b.box("Roof",center+Vector3(0,height+.18,0),Vector3(size.x+1,.36,size.y+1),WHITE)
	if glazed:(roof.get_child(0) as MeshInstance3D).material_override=material(Color("aab6bd"))
	var floor_node:=block("Floor",center+Vector3(0,.015,0),Vector3(size.x-.3,.03,size.y-.3),Color("bbc6cb"),false)
	var tiles:=ShaderMaterial.new();tiles.shader=load("res://content/materials/airport_floor.gdshader")
	tiles.set_shader_parameter("grain_tex",MapSurfaces.texture("concrete_floor","diff"))
	(floor_node.get_child(0) as MeshInstance3D).material_override=tiles
	b.interior_lighting(center,size,height)
	for side:float in [-1.0,1.0]:
		block("Fascia",center+Vector3(0,height-.4,side*(size.y*.5+.17)),Vector3(size.x,.7,.12),NAVY,false)

func wayfinding(text: String, at: Vector3, width: float, yaw := 0.0) -> void:
	var node:=block("Wayfinding",at,Vector3(width,.8,.1),NAVY,false);node.rotation.y=yaw
	b.sign_text(text,at+Basis(Vector3.UP,yaw)*Vector3(0,0,.065),yaw,YELLOW,b.fit_font(text,width-.3,.62,70))

func build(builder: CompactMapBuilder) -> void:
	b=builder
	terminal()
	baggage()
	hangar()
	aircraft(JET,1.0,true)
	# Wide, straight boarding ramps with collision parapets and flush landings.
	b.ramp(Vector3(-1,0,10),Vector3(13.325,CABIN,10),3.4)
	b.ramp(Vector3(31,0,30),Vector3(16.675,CABIN,30),3.4)
	b.ramp(Vector3(-1,0,30),Vector3(13.325,CABIN,30),3.4)
	for ramp in b.region.get_children():
		if not String(ramp.name).begins_with("AccessRamp"):continue
		(ramp.get_child(0) as MeshInstance3D).material_override=material(Color("70828c"),.3)
		for part in ramp.get_children():
			if String(part.name).begins_with("RampParapet"):(part.get_child(0) as MeshInstance3D).material_override=material(WHITE,.2)
	for p in [Vector3(-1,0,10),Vector3(31,0,30),Vector3(-1,0,30)]:
		for reach:float in [2.0,4.0]:b.avoid.append(p+Vector3(signf(p.x-15)*reach,0,0))
	apron()
	connections()

func terminal() -> void:
	var c:=Vector3(-14,0,-27)
	var north:Array=[]
	var south:=[Rect2(-21,0,4.8,3.6),Rect2(-1,0,4.8,3.6),Rect2(21,0,4.8,3.6)]
	for x:float in [-26.0,-8.0,0.0,8.0,26.0]:
		var sill:=2.2 if x in [0.0,8.0] else 1.15
		north.append(Rect2(x,sill,5.5,4.95-sill))
	for x:float in [-27.0,-13.0,6.0,13.0,27.0]:
		var sill:=2.2 if x in [6.0,13.0,27.0] else 1.15
		south.append(Rect2(x,sill,5.0,4.95-sill))
	var ends:=[Rect2(0,0,5.0,3.6),Rect2(-10,2.2,5.0,2.75),Rect2(10,1.15,5.0,3.8)]
	shell(c,Vector2(62,34),6.8,north,south,ends,ends,true)
	# One screening line, with broad routes on either side of the central hall.
	wall(Vector3(-18,0,-27),33.7,4.8,[Rect2(-11,0,6.0,3.5),Rect2(7,0,6.0,3.5)],true)
	for z:float in [-30.0,-20.0]:
		block("Scanner",Vector3(-18,.55,z),Vector3(5.8,1.1,1.7),Color("a7b2b8"))
		block("ScannerHood",Vector3(-18,1.65,z),Vector3(2.0,1.1,1.7),NAVY)
		cover_points(Vector3(-18,0,z),Vector2(5.8,1.7))
	for x:float in [-36.0,-29.0]:
		block("CheckInDesk",Vector3(x,.6,-34.8),Vector3(4.6,1.2,1.3),WHITE)
		block("CheckInFace",Vector3(x,.6,-34.1),Vector3(4.4,.95,.07),TEAL,false)
		block("CheckInMonitor",Vector3(x,1.7,-35),Vector3(.8,.5,.08),DARK,false)
		cover_points(Vector3(x,0,-34.8),Vector2(4.6,1.3))
	block("CheckInIsland",Vector3(-32,.65,-24),Vector3(8.0,1.3,3),NAVY)
	block("CheckInIslandTop",Vector3(-32,1.35,-24),Vector3(8.2,.1,3.2),WHITE,false)
	for x:float in [-34.0,-30.0]:block("CheckInScreen",Vector3(x,1.8,-24),Vector3(.9,.55,.1),DARK,false)
	cover_points(Vector3(-32,0,-24),Vector2(8,3))
	wayfinding("CHECK-IN  01 - 04",Vector3(-32,3.4,-24),8,-PI*.5)
	for p in [Vector3(-6,0,-30),Vector3(7,0,-31),Vector3(-6,0,-16),Vector3(7,0,-16)]:seats(p,4)
	block("CafeCounter",Vector3(10,.65,-24),Vector3(5,1.3,2.4),TEAL)
	block("CafeTop",Vector3(10,1.34,-24),Vector3(5.2,.08,2.6),WHITE,false)
	cover_points(Vector3(10,0,-24),Vector2(5,2.4))
	for x in range(-42,16,6):
		b.box("SteelColumn",Vector3(x,3.2,-11.2),Vector3(.22,6.4,.22),WHITE)
		b.detail(Vector3(x,6.1,-25),Vector3(.14,.3,28),WHITE)
	# Flight board and gate signage are readable navigation landmarks.
	block("FlightBoard",Vector3(-13,4.4,-25),Vector3(.18,2.0,6.0),DARK,false)
	b.sign_text("DEPARTURES",Vector3(-13.105,5.05,-25),-PI*.5,YELLOW,42)
	b.sign_text("08:20   NS104   COAST CITY   A1\n08:45   NS216   LAKEVIEW     A2\n09:10   NS308   NORTH BAY    A1",Vector3(-13.105,4.2,-25),-PI*.5,WHITE,22)
	b.sign_text("DEPARTURES",Vector3(-12.895,5.05,-25),PI*.5,YELLOW,42)
	b.sign_text("08:20   NS104   COAST CITY   A1\n08:45   NS216   LAKEVIEW     A2\n09:10   NS308   NORTH BAY    A1",Vector3(-12.895,4.2,-25),PI*.5,WHITE,22)
	wayfinding("SECURITY   /   GATES A1 - A2",Vector3(-17.8,3.9,-25),8.0,-PI*.5)
	wayfinding("DEPARTURES",Vector3(-14,5.5,-9.78),12)
	wayfinding("ARRIVALS  /  CHECK-IN",Vector3(-14,5.5,-44.22),14,PI)
	wayfinding("A1",Vector3(7,3.9,-9.75),2.8)
	wayfinding("A2",Vector3(-15,3.9,-9.75),2.8)
	for x:float in [-11.0,11.0]:
		block("GateDesk",Vector3(x,.58,-12.5),Vector3(2.7,1.16,1.1),TEAL)
		block("GateMonitor",Vector3(x,1.55,-12.5),Vector3(.8,.5,.08),DARK,false)
		cover_points(Vector3(x,0,-12.5),Vector2(2.7,1.1))
	wayfinding("COFFEE",Vector3(10,3.2,-25.3),4,PI)
	for p in [Vector3(-42,0,-13.5),Vector3(-27,0,-37),Vector3(13,0,-36),Vector3(13,0,-13)]:b.prop("potted_plant_02",p,1.5,0,false)
	for p in [Vector3(-24,0,-13),Vector3(0,0,-36)]:b.prop("planter_box_02",p,.85)
	b.prop("WetFloorSign_01",Vector3(-9,0,-36),.6,0,false)
	b.prop("metal_office_desk",Vector3(-39,0,-28),.8,PI,false)
	b.prop("metal_office_desk",Vector3(12,0,-34),.8,PI,false)
	# Additional reflection volumes follow the actual room divisions.
	for p in [Vector3(-31,2.8,-25),Vector3(1,2.8,-25)]:b.arena.probe_volumes.append(AABB(p-Vector3(12,2.7,11),Vector3(24,5.4,22)))

func seats(at: Vector3, count: int, parent: Node3D = null) -> void:
	for i in count:
		var p:=at+Vector3((i-(count-1)*.5)*.85,0,0)
		block("Seat",p+Vector3(0,.48,0),Vector3(.72,.13,.65),NAVY,true,parent)
		block("SeatBack",p+Vector3(0,.9,.29),Vector3(.72,.78,.12),NAVY,true,parent)
		b.box("SeatLeg",p+Vector3(0,.22,0),Vector3(.1,.44,.4),DARK,true,parent)
		for side:float in [-1.0,1.0]:b.box("SeatArm",p+Vector3(side*.38,.67,0),Vector3(.04,.05,.58),WHITE,false,parent)
	if parent==null:cover_points(at,Vector2(count*.85,.8))

func baggage() -> void:
	var c:=Vector3(-33,0,8)
	shell(c,Vector2(24,24),5.2,[Rect2(0,0,6.0,3.5)],[Rect2(0,0,6.0,3.5)],[Rect2(0,0,5.0,3.5)],[Rect2(0,0,6.0,3.5)])
	# A roofed link joins the terminal's gate doors to the service-side entrance.
	block("BaggageCanopy",Vector3(-33,4.2,-7),Vector3(8,.25,6),WHITE,false)
	for x:float in [-36.5,-29.5]:b.box("CanopyColumn",Vector3(x,2,-5),Vector3(.16,4,.16),WHITE)
	block("BaggageExitCanopy",Vector3(-33,3.6,23),Vector3(8,.2,6),WHITE,false)
	carousel(Vector3(-33,0,8))
	wayfinding("BAGGAGE CLAIM",Vector3(-33,4.1,20.22),12)
	wayfinding("BAGGAGE / SERVICE",Vector3(-20.78,4.1,8),9,PI*.5)
	for x:float in [-42.0,-24.0]:
		b.prop("steel_frame_shelves_02",Vector3(x,0,15.5),2.0,0)
		b.prop("industrial_storage_cart",Vector3(x,0,.8),1.0,0)
		b.prop("hand_truck",Vector3(x,0,3.1),1.1,0,false)
	b.prop("security_camera_02",Vector3(-33,4.5,19.6),.3,PI,false)
	b.prop("korean_fire_extinguisher_01",Vector3(-44.6,.1,4),.65,PI*.5,false)

func carousel(at: Vector3) -> void:
	# Oval luggage belt: a continuous ring around a raised island, not a box pile.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		var a:=TAU*i/48;var c:=TAU*(i+1)/48
		var p:=Vector3(cos(a)*5.2,.76,sin(a)*2.8)
		var q:=Vector3(cos(c)*5.2,.76,sin(c)*2.8)
		var r:=Vector3(cos(c)*3.5,.76,sin(c)*1.1)
		var s:=Vector3(cos(a)*3.5,.76,sin(a)*1.1)
		quad(st,[p,q,r,s],Vector3.UP)
		quad(st,[p,q,q*Vector3(1,0,1)+Vector3.UP*.18,p*Vector3(1,0,1)+Vector3.UP*.18],Vector3(cos(a),0,sin(a)))
	mesh_node("LuggageCarousel",finish(st),material(DARK,.3),at)
	block("CarouselIsland",at+Vector3(0,1.05,0),Vector3(6.7,2.1,2.0),WHITE)
	wayfinding("ARRIVALS  /  BAGGAGE",at+Vector3(0,1.55,1.07),6)
	for i in 8:
		var a:=TAU*i/8;var p:=at+Vector3(cos(a)*4.4,1.05,sin(a)*1.9)
		var bag:=block("Suitcase",p,Vector3(.65,.58,.42),[NAVY,TEAL,Color("b46742")][i%3],false)
		bag.rotation.y=-a
	cover_points(at,Vector2(10.5,5.6))

func hangar() -> void:
	var c:=Vector3(36,0,-27)
	shell(c,Vector2(24,34),8.5,[],[Rect2(0,0,17,6.8)],[Rect2(0,0,6,3.6)],[Rect2(0,0,5,3.6)])
	block("ClosedServiceDoor",Vector3(36,3.1,-43.8),Vector3(9,6,.08),Color("75838a"),false)
	wayfinding("SERVICE",Vector3(36,7.1,-43.7),9)
	wayfinding("HANGAR 02",Vector3(36,7.5,-9.78),14)
	aircraft(Vector3(36,0,-25),.5,false)
	for p in [Vector3(27,0,-35),Vector3(45,0,-35),Vector3(27,0,-12),Vector3(45,0,-15)]:
		b.prop("tool_cart",p,.85,0)
		cover_points(p,Vector2(1.2,.8))
	b.prop("old_military_compressor",Vector3(42,0,-37),1.0,0,false)
	b.prop("steel_frame_shelves_02",Vector3(46,0,-30),2.0,-PI*.5)
	b.prop("portable_generator",Vector3(26,0,-29),1.0,0,false)
	for x:float in [28.0,44.0]:block("MaintenanceBench",Vector3(x,.5,-38),Vector3(4,1,1.2),NAVY)
	# Staggered tool banks interrupt the side aisles while the hangar door
	# still frames the aircraft and its central maintenance space.
	for p in [Vector3(29,0,-16),Vector3(43,0,-28)]:
		block("EngineServiceCabinet",p+Vector3.UP*1.1,Vector3(4,2.2,2),NAVY)
		block("ToolBankTop",p+Vector3.UP*2.24,Vector3(4.1,.08,2.1),WHITE,false)
		for x:float in [-1.5,-.5,.5,1.5]:
			block("ToolLockerDoor",p+Vector3(x,1.2,1.02),Vector3(.92,1.8,.04),TEAL,false)
			block("LockerHandle",p+Vector3(x+.3,1.2,1.06),Vector3(.04,.25,.05),WHITE,false)

func aircraft(at: Vector3, scale: float, boardable: bool) -> void:
	var plane:=Node3D.new();plane.name="PassengerJet" if boardable else "MaintenanceJet"
	plane.position=at;plane.scale=Vector3.ONE*scale;b.region.add_child(plane)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lining:=SurfaceTool.new();lining.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stations:=[Vector2(-18,.03),Vector2(-16,.6),Vector2(-13,1),Vector2(-11.4,1),Vector2(-8.6,1),Vector2(8.6,1),Vector2(11.4,1),Vector2(13,1),Vector2(16,.55),Vector2(18,.06)]
	var angles:Array[float]=[]
	for i in 40:angles.append(TAU*i/40)
	# Explicit door thresholds and heads keep the shell flush with the cabin floor.
	for a:float in [asin(-.8/2.2),PI-asin(-.8/2.2),asin(.84375),PI-asin(.84375)]:angles.append(fposmod(a,TAU))
	angles.sort();angles.append(TAU)
	for j in stations.size()-1:
		var a:Vector2=stations[j];var c:Vector2=stations[j+1]
		for i in angles.size()-1:
			var t:float=(angles[i]+angles[i+1])*.5
			var y:=3.4+sin(t)*(2.2 if sin(t)<0 else 1.6)
			var door:=boardable and y>CABIN+.001 and y<4.75-.001 and ((cos(t)<0 and a.x>=-11.41 and c.x<=-8.59) or (a.x>=8.59 and c.x<=11.41))
			if door:continue
			var points:Array=[]
			for pair in [[a,angles[i]],[c,angles[i]],[c,angles[i+1]],[a,angles[i+1]]]:
				var sec:Vector2=pair[0];var angle:float=pair[1]
				points.append(Vector3(cos(angle)*1.8*sec.y,3.4+sin(angle)*(2.2 if sin(angle)<0 else 1.6)*sec.y,sec.x))
			var normal:=Vector3(cos(t),sin(t),-(c.y-a.y)/(c.x-a.x)).normalized()
			quad(st,points,normal,TEAL if y>3.5 and y<4.05 else WHITE)
			if boardable:
				var inner:Array=[]
				for p:Vector3 in points:inner.append(Vector3(p.x*.98,3.4+(p.y-3.4)*.98,p.z))
				quad(lining,inner,-normal)
	var paint:=material(Color.WHITE,.2).duplicate();paint.vertex_color_use_as_albedo=true
	mesh_node("AircraftFuselage",finish(st),paint,Vector3.ZERO,true,plane)
	if boardable:mesh_node("CabinLining",finish(lining),material(Color("d7dfe2")),Vector3.ZERO,false,plane)
	# Swept wings and stabilisers have solid, matching polygon geometry.
	for side:float in [-1.0,1.0]:
		fin(plane,[Vector3(side*1.4,2.85,-1),Vector3(side*15.8,2.9,5),Vector3(side*15.5,3.05,7),Vector3(side*1.4,3.05,5)],WHITE)
		fin(plane,[Vector3(side*.6,4.7,12),Vector3(side*6.2,4.9,15),Vector3(side*5.8,5.05,16),Vector3(side*.5,5.05,15.5)],WHITE)
		var engine:=b.cylinder(Vector3(side*5.0,1.55,0),.95,3.8,WHITE,plane);engine.rotation.x=PI*.5
		(engine as MeshInstance3D).material_override=material(WHITE,.3)
		var intake:=b.cylinder(Vector3(side*5.0,1.55,-1.92),.78,.06,DARK,plane);intake.rotation.x=PI*.5
		(intake as MeshInstance3D).material_override=material(DARK,.2)
		for k in 10:
			var angle:=TAU*k/10
			# Radial half-blades: full bars duplicated their opposite blade,
			# putting two surfaces at exactly the same depth.
			var blade:=block("FanBlade",Vector3(side*5.0,1.55,-1.96)+Vector3(-sin(angle),cos(angle),0)*.38,Vector3(.06,.64,.03),Color("6d7e86"),false,plane)
			blade.rotation.z=angle
		block("MainGear",Vector3(side*2,.65,3),Vector3(.15,1.3,.15),DARK,true,plane)
		var wheel:=b.cylinder(Vector3(side*2,.48,3),.48,.4,DARK,plane);wheel.rotation.z=PI*.5
		for z in range(-7,8,2):
			aircraft_window(plane,z,3.95,.62,.4,side)
			if boardable:aircraft_window(plane,z,3.95,.62,.4,side,true)
		for z:float in [-15.5,-14.7,-13.9]:aircraft_window(plane,z,3.85,.68,.46,side)
	fin(plane,[Vector3(0,4.55,11),Vector3(0,8.5,15),Vector3(0,8.5,16.2),Vector3(0,4.55,17)],TEAL,.18)
	block("NoseGear",Vector3(0,.9,-12),Vector3(.15,1.8,.15),DARK,true,plane)
	var nosewheel:=b.cylinder(Vector3(0,.38,-12),.38,.36,DARK,plane);nosewheel.rotation.z=PI*.5
	if not boardable:return
	block("CabinFloor",Vector3(0,CABIN-.1,0),Vector3(3.35,.2,26),Color("465864"),true,plane)
	for z in range(-6,8,2):
		for side:float in [-1.0,1.0]:
			block("CabinSeat",Vector3(side*1.25,CABIN+.48,z),Vector3(.48,.14,.65),NAVY,true,plane)
			block("CabinSeatBack",Vector3(side*1.25,CABIN+.9,z+.28),Vector3(.48,.8,.12),NAVY,true,plane)
			b.box("SeatLeg",Vector3(side*1.25,CABIN+.22,z),Vector3(.08,.44,.4),DARK,true,plane)
	block("FlightDeckBulkhead",Vector3(0,3.5,-12.7),Vector3(3.0,1.8,.15),WHITE,true,plane)
	block("RearBulkhead",Vector3(0,3.5,12.7),Vector3(3.0,1.8,.15),WHITE,true,plane)
	for side:float in [-1.0,1.0]:
		b.def.cover_points.append(at+Vector3(side*4,0,0));b.def.cover_peeks.append(at+Vector3(side*4,0,-3))
	b.arena.probe_volumes.append(AABB(at+Vector3(-1.6,2.5,-13),Vector3(3.2,2.6,26)))
	for z:float in [-8.0,0.0,8.0]:
		var light:=OmniLight3D.new();light.position=Vector3(0,4.4,z);light.omni_range=9;light.light_energy=2.0;light.light_color=Color("d7eaff");light.light_bake_mode=Light3D.BAKE_STATIC;plane.add_child(light)
		b.box("CeilingLamp",Vector3(0,4.9,z),Vector3(.14,.035,3.0),WHITE,false,plane)

func aircraft_window(parent: Node3D,z: float,y: float,width: float,height: float,side: float,inside := false) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points:Array=[]
	for i in 17:
		var angle:=TAU*i/16
		var zz:=z+cos(angle)*width*.5;var yy:=y+sin(angle)*height*.5
		var radius:=lerpf(.6,1.0,clampf((zz+16)/3.0,0,1)) if zz<-13 else 1.0
		var x:=side*(1.8*radius*sqrt(maxf(.02,1.0-pow((yy-3.4)/(1.6*radius),2)))+(-.05 if inside else .012))
		points.append(Vector3(x,yy,zz))
	var centre:Vector3=points[0]
	var normal:=Vector3(side,.2,0).normalized()*(-1.0 if inside else 1.0)
	for i in range(1,points.size()-1):quad(st,[centre,points[i],points[i+1],centre],normal)
	mesh_node("AircraftWindow",finish(st),material(DARK,.25),Vector3.ZERO,false,parent)

func fin(parent: Node3D, outline: Array, color: Color, thickness := .16) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var normal:Vector3=(outline[1]-outline[0]).cross(outline[2]-outline[0]).normalized()
	var front:Array=[];var back:Array=[]
	for p:Vector3 in outline:front.append(p+normal*thickness*.5);back.append(p-normal*thickness*.5)
	quad(st,front,normal);quad(st,back,-normal)
	for i in outline.size():
		var j:=(i+1)%outline.size();var n:Vector3=(outline[j]-outline[i]).cross(normal).normalized()
		quad(st,[front[i],front[j],back[j],back[i]],n)
	mesh_node("Airfoil",finish(st),material(color,.2),Vector3.ZERO,true,parent)

func cart(at: Vector3, yaw: float, loaded := true) -> void:
	var root:=block("BaggageCart",at+Vector3(0,.5,0),Vector3(3.8,.55,1.8),Color("8b9ba1"));root.rotation.y=yaw
	for side:float in [-1.0,1.0]:
		for x:float in [-1.3,1.3]:
			var wheel:=b.cylinder(Vector3(x,-.28,side*.85),.26,.18,DARK,root);wheel.rotation.x=PI*.5
	if loaded:
		for x:float in [-1.15,0,1.15]:
			block("CargoCase",Vector3(x,.65,0),Vector3(.95,.85,1.55),[NAVY,TEAL,Color("ba7445")][int(x+2)%3],true,root)
	cover_points(at,Vector2(4.0,4.0))

func apron() -> void:
	for p in [Vector3(-11,0,1),Vector3(-3,0,-1),Vector3(-47,0,32),Vector3(-23,0,34),Vector3(44,0,15),Vector3(33,0,41),Vector3(3,0,40)]:cart(p,PI*.5 if p.x>20 else 0.0)
	# Ground-power and baggage tractors give cover with an airport purpose.
	for p in [Vector3(-13,0,20),Vector3(36,0,11)]:
		block("ApronTractor",p+Vector3(0,.7,0),Vector3(4.0,1.4,2.2),YELLOW)
		block("TractorCab",p+Vector3(-1.1,1.65,0),Vector3(1.5,1.2,2),NAVY)
		cover_points(p,Vector2(4,2.2))
		b.prop("portable_generator",p+Vector3(4,0,2),1.1,0)
	# Covered baggage sorting connects the terminal gates to the service hall.
	block("SortingCanopy",Vector3(-13,3.65,4),Vector3(12,.24,12),WHITE)
	for x:float in [-18.5,-7.5]:
		for z:float in [-1.5,9.5]:b.box("SteelColumn",Vector3(x,1.8,z),Vector3(.18,3.6,.18),WHITE)
	wayfinding("BAGGAGE TRANSFER",Vector3(-13,3.15,10.15),9)
	shuttle_bus(Vector3(-34,0,34))
	shuttle_bus(Vector3(37,0,37))
	shuttle_bus(Vector3(-50,0,-22),PI*.5)
	shuttle_bus(Vector3(52,0,-22),PI*.5)
	fuel_bowser(Vector3(29,0,6))
	for x in range(-54,56,8):
		b.detail(Vector3(x,.025,-3),Vector3(4,.012,.16),WHITE,"concrete")
		b.detail(Vector3(x,.025,41),Vector3(4,.012,.16),WHITE,"concrete")
	for x:float in [7.5,22.5]:b.detail(Vector3(x,.025,20),Vector3(.15,.012,40),YELLOW,"concrete")
	for z:float in [0,40]:b.detail(Vector3(15,.028,z),Vector3(15,.012,.18),YELLOW,"concrete")
	for p in [Vector3(-50,0,22),Vector3(50,0,-4),Vector3(-5,0,40)]:
		b.box("ApronMast",p+Vector3.UP*6,Vector3(.18,12,.18),WHITE)
		block("Floodlight",p+Vector3.UP*12,Vector3(2,.4,.5),WHITE,false)
	b.prop("security_camera_02",Vector3(-44.6,4,-10),.3,PI,false)
	b.prop("security_camera_02",Vector3(47.6,5,-10),.3,PI,false)

func shuttle_bus(at: Vector3, yaw := 0.0) -> void:
	var bus:=block("AirportShuttle",at+Vector3(0,1.5,0),Vector3(9,2.6,2.6),WHITE)
	bus.rotation.y=yaw
	for side:float in [-1.0,1.0]:
		block("ShuttleStripe",Vector3(0,-.45,side*1.315),Vector3(8.9,.5,.035),TEAL,false,bus)
		for x in range(-3,4):block("ShuttleWindow",Vector3(x,.5,side*1.315),Vector3(.88,.95,.04),NAVY,false,bus)
		for x:float in [-3.0,3.0]:
			var wheel:=b.cylinder(Vector3(x,-.98,side*1.29),.5,.22,DARK,bus);wheel.rotation.x=PI*.5
	block("ShuttleWindscreen",Vector3(-4.51,.45,0),Vector3(.035,1.0,2.3),NAVY,false,bus)
	cover_points(at,Vector2(9,2.6) if absf(sin(yaw))<.5 else Vector2(2.6,9))
	wayfinding("AIRPORT SHUTTLE",at+Vector3.UP*3.0+Basis(Vector3.UP,yaw)*Vector3(0,0,1.36),7,yaw)

func connections() -> void:
	# Two recognizable anchors leave a broad, visible loop around the aircraft.
	# The sorting shelter stays open on all sides; there are no road chicanes.
	service_pavilion(Vector3(8,0,-3),Vector2(12,14),"A1 GATE SERVICES",true)
	service_pavilion(Vector3(46,0,26),Vector2(12,14),"GROUND OPERATIONS")
	block("GateLinkCanopy",Vector3(7,3.6,-9),Vector3(5,.18,2.3),WHITE,false)
	block("SortingBeltGuard",Vector3(-13,1.1,5),Vector3(3.5,2.2,2),NAVY)
	# An open shuttle stop gives the southern crossing one readable cover
	# island. Both ends and both long sides remain open.
	block("ShuttleShelterRoof",Vector3(-8,3.3,38),Vector3(11,.2,4.5),WHITE,false)
	for x:float in [-13.0,-3.0]:
		for z:float in [36.1,39.9]:b.box("ShelterColumn",Vector3(x,1.6,z),Vector3(.12,3.2,.12),WHITE)
	block("ShuttleInformation",Vector3(-8,1.4,38),Vector3(1.0,2.8,4),NAVY)
	for x:float in [-10.5,-5.5]:seats(Vector3(x,0,38),3)
	wayfinding("SHUTTLE / BAGGAGE",Vector3(-8,2.85,40.3),9)
	cover_points(Vector3(-8,0,38),Vector2(1,4))
	boarding_pylon(Vector3(-3,0,7.8),"BOARDING")
	boarding_pylon(Vector3(-3,0,32.2),"REAR EXIT")

func boarding_pylon(at: Vector3, text: String) -> void:
	block("BoardingPylon",at+Vector3.UP*1.25,Vector3(.18,2.5,1.2),NAVY)
	b.sign_text("A1",at+Vector3(-.105,1.8,0),-PI*.5,YELLOW,72)
	b.sign_text(text,at+Vector3(-.105,1.15,0),-PI*.5,WHITE,18)

func service_pavilion(at: Vector3,size: Vector2,title: String, attached := false) -> void:
	var east:=[Rect2(-4.0,0,4.4,3.2)] if attached else [Rect2(0,0,5.0,3.2)]
	shell(at,size,4.4,[Rect2(-size.x*.2,0,5.0,3.2)],[Rect2(size.x*.2,0,5.0,3.2)],[Rect2(0,0,5.0,3.2)],east,false,attached)
	wayfinding(title,at+Vector3(0,3.8,size.y*.5+.22),minf(size.x-1,10))
	# A small dispatch desk gives the room a purpose without partitioning it.
	block("DispatchDesk",at+Vector3(-size.x*.25,.6,-size.y*.25),Vector3(2.7,1.2,1.1),TEAL)
	for side:float in [-1.0,1.0]:
		b.def.cover_points.append(at+Vector3(side*(size.x*.5+1.3),0,0))
		b.def.cover_peeks.append(at+Vector3(side*(size.x*.5+1.3),0,size.y*.5+1.3))

func fuel_bowser(at: Vector3) -> void:
	var vehicle:=Node3D.new();vehicle.name="FuelBowser";vehicle.position=at;b.region.add_child(vehicle)
	block("BowserChassis",Vector3(0,.6,0),Vector3(7,.4,2.6),DARK,true,vehicle)
	block("BowserCab",Vector3(-2.4,1.4,0),Vector3(2.2,2.1,2.5),YELLOW,true,vehicle)
	block("BowserWindscreen",Vector3(-3.51,1.9,0),Vector3(.04,.7,2.15),NAVY,false,vehicle)
	var tank:=b.cylinder(Vector3(1,1.65,0),1.1,4.8,WHITE,vehicle);tank.rotation.z=PI*.5
	(tank as MeshInstance3D).material_override=material(WHITE,.25)
	for side:float in [-1.0,1.0]:
		for x:float in [-2.5,2.2]:
			var wheel:=b.cylinder(Vector3(x,.5,side*1.3),.5,.25,DARK,vehicle);wheel.rotation.x=PI*.5
	wayfinding("AVIATION FUEL",at+Vector3(1,2.1,1.13),4.3)
	cover_points(at,Vector2(7,2.6))

func deployment(builder: CompactMapBuilder) -> void:
	b=builder
	for team in 2:
		var side:=-1.0 if team==0 else 1.0
		for row in 4:
			for col in 4:
				var p:=Vector3(side*(53-col),.05,[-32,-12,12,36][row])
				(b.def.spawns_blue if team==0 else b.def.spawns_red).append(p)
		b.def.routes.append_array([Vector3(side*51,0,-38),Vector3(side*52,0,-5),Vector3(side*51,0,39)])

func objectives(builder: CompactMapBuilder) -> void:
	b=builder
	var caches:=[Vector3(-38,0,-18),Vector3(11,0,-19),Vector3(29,0,-16),Vector3(-40,0,14),Vector3(-18,0,40),Vector3(46,0,29),Vector3(15,CABIN,9),Vector3(15,CABIN,31.9)]
	for p:Vector3 in caches:
		b.def.ammo_caches.append(p)
		block("AmmoCase",p+Vector3.UP*.32,Vector3(.9,.64,.6),Color("5b7565"))
	for p:Vector3 in [Vector3(-39,0,-25),Vector3(-25,0,-25),Vector3(-10,0,-25),Vector3(10,0,-25),Vector3(-31,0,-42),Vector3(3,0,-42),Vector3(35,0,-42),Vector3(35,0,-16),Vector3(24,0,-5),Vector3(10,0,-5),Vector3(-15,0,-5),Vector3(-33,0,0),Vector3(-33,0,16),Vector3(-20,0,25),Vector3(-4,0,29),Vector3(15,0,42),Vector3(28,0,41),Vector3(44,0,29),Vector3(45,0,0),Vector3(15,CABIN,12),Vector3(15,CABIN,28)]:b.def.routes.append(p)
	b.def.domination.assign([Vector3(-8,0,-24),Vector3(-33,0,15),Vector3(15,CABIN,20)])
	b.def.hardpoints.assign([Vector3(-8,0,-24),Vector3(-33,0,15),Vector3(15,CABIN,20),Vector3(36,0,-13),Vector3(-22,0,29)])
	b.def.qa_route.assign([Vector3(-54,0,-5),Vector3(-35,0,-25),Vector3(-1,0,10),Vector3(15,CABIN,11),Vector3(15,CABIN,20),Vector3(15,CABIN,29),Vector3(33,0,30),Vector3(36,0,-13),Vector3(-33,0,8),Vector3(-54,0,36)])

func dress(builder: CompactMapBuilder) -> void:
	b=builder
	for p in [Vector3(-27,0,-14),Vector3(-40,0,-33),Vector3(8,0,-28)]:
		b.small_prop("office_notepads",p+Vector3.UP*1.3,.03)
	for p in [Vector3(-42,0,18),Vector3(43,0,-38)]:
		b.small_prop("plastic_crate_02",p,.4,0)
	for p in [Vector3(-20,0,22),Vector3(35,0,12)]:
		b.props.scatter("water_manhole_cover",b.props.grounded("water_manhole_cover",p))

func ground_splat(_builder: CompactMapBuilder,x: float,z: float,_noise: FastNoiseLite) -> Color:
	var road:=smoothstep(0.0,2.0,absf(z+45))*(1.0-smoothstep(2.0,4.0,absf(z+45)))
	var verge:=smoothstep(49.5,51.5,absf(z))
	return Color(road,0.0,verge*.6)
