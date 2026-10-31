extends MapLayout

# Harbor: berth 3 of a working container terminal at overcast late afternoon.
# The quay edge runs along the south (+Z) long side with open water beyond it;
# spawns sit in the gate houses at the short ends. Three lanes run east-west:
#   north  - warehouse 7 (ground floor plus a mezzanine reached by two ramps)
#            between the dock office and customs, with a service road south of it
#   middle - the container yard: mirrored blocks of 40 ft boxes, 1-3 high
#   south  - the quay apron under two ship-to-shore cranes, hatch covers,
#            a straddle carrier, bollards and the quay edge
# The layout is mirrored across X = 0 so both teams get the same cover.
# Everything not covered by the shared builders (cranes, vehicles, pallets,
# bollards, water, puddles) is built here from metric blocks and scans.

const QUAY := 45.0
const WATER_Y := -1.7
const RAIL_LAND := 30.5
const RAIL_SEA := 43.0
const CRANE_PAINT := Color("c7c2b2")
const CRANE_DARK := Color("4b5053")
const YELLOW := Color("c9a63c")
const WHITE_LINE := Color("d6d4ca")
# Weathered box colours; red-browns keep the rusty red scan, the rest repaint it.
const BOX_COLORS := [Color("8f3226"),Color("3f7aa3"),Color("8e9294"),Color("c2662c"),Color("23405f"),Color("cfccc0"),Color("3c6a4c"),Color("c4a04a"),Color("4f8fb3"),Color("6e7a5c"),Color("2d5a7c"),Color("a8acaa")]

var b: CompactMapBuilder
var paint_index := 0
# Decorative parts merged per 32 m cell and material (one draw each), see piece().
var batches := {}
# True only while building parts whose real-time shadows are worth their cost
# (vehicles, the tug); trims, markings and crane steel are probe-lit without.
var casting := false
# Vehicle under construction: origin and heading of the local frame vb()/vcyl() use.
var vo := Vector3.ZERO
var vt := Basis.IDENTITY

# --- Outside the play space: terrain becomes a harbour basin ---------------------

# Terrain that drops into a harbour basin beyond the quay, with the far shore
# 300 m out; skyline blocks that would land in the water move to the far shore.
class HarborNature extends MapNature:
	const BASIN := 260.0
	func _init(owner: MapBuilder) -> void:
		super(owner)
	func in_basin(z: float) -> bool:
		return z>def.extent.y*.5+.5 and z<def.extent.y*.5+BASIN
	func height(x: float, z: float) -> float:
		var land:=super(x,z)
		var half:=def.extent.y*.5
		if z<=half+.5:return land
		# Seabed 9 m down, rising to the far shore beyond the basin.
		var shore:=smoothstep(half+BASIN-40.0,half+BASIN+20.0,z)
		return lerpf(-9.0,maxf(land,1.2),shore)
	func factory(center: Vector3, size: Vector3, facade: String, yaw: float) -> void:
		if in_basin(center.z):
			center.z=def.extent.y*.5+BASIN+30.0+(center.z-def.extent.y*.5)*.6
			center.y=height(center.x,center.z)-.3
		super(center,size,facade,yaw)
	# Flat terrain beyond the walls shadows nothing; keep it out of the shadow pass.
	func terrain() -> void:
		super()
		var node:=arena.get_node_or_null("Terrain") as GeometryInstance3D
		if node!=null:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	func _add(kind: String, mesh: ArrayMesh, transform: Transform3D, surface := 0) -> void:
		if in_basin(transform.origin.z) and kind in ["stack","roof"]:
			var old:=height(transform.origin.x,transform.origin.z)
			transform.origin.z+=BASIN+30.0
			transform.origin.y+=height(transform.origin.x,transform.origin.z)-old
		super(kind,mesh,transform,surface)

# --- Frame --------------------------------------------------------------------------

func boundaries(builder: CompactMapBuilder) -> void:
	b=builder
	b.nature=HarborNature.new(b)
	b.ground_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var half:=b.def.extent*.5
	# Side walls run through the corners; the land-side wall butts against their inner faces.
	for side in [-1,1]:
		b.box("BoundaryWall",Vector3(side*half.x,2,-.125),Vector3(.5,4,b.def.extent.y+.25),b.stone)
		b.coping_run(Vector3(side*half.x,4.07,-.1625),Vector3(.65,.14,b.def.extent.y+.325),true)
	b.box("BoundaryWall",Vector3(0,2,-half.y),Vector3(b.def.extent.x-.5,4,.5),b.stone)
	b.coping_run(Vector3(0,4.07,-half.y),Vector3(b.def.extent.x-.65,.14,.65),false)
	# Terminal sheds beyond the land-side wall.
	for x in [-38,-12,14,40]:
		var center:=Vector3(x,0,-(half.y+9))
		b.box("ContextWarehouse",center+Vector3(0,5,0),Vector3(22,10,12),Color("8f9796"),false)
		for level in [3.5,7.5]:
			for offset in [-7,-2,3,8]:b.context_window(center+Vector3(offset,level,6.0),1)
	quay()
	water()

func quay() -> void:
	var half:=b.def.extent*.5
	# Concrete quay face down to the seabed, continuing past the walls.
	b.box("BoundaryWall",Vector3(0,-3.5,QUAY+.25),Vector3(b.def.extent.x+.5,7,.5),b.stone,false)
	for side in [-1,1]:
		var face:=b.box("BoundaryWall",Vector3(side*(half.x+400.25),-3.5,QUAY+.25),Vector3(800,7,.5),b.stone,false)
		(face.get_child(0) as GeometryInstance3D).gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	# Raised edge kerb with a worn yellow line; the player boundary stands on it.
	b.box("Sill",Vector3(0,.15,QUAY-.22),Vector3(b.def.extent.x-.5,.3,.44),b.stone)
	for x in range(-54,55,2):d(Vector3(x+.5,.304,QUAY-.22),Vector3(1.0,.006,.42),YELLOW,"concrete")
	invisible_wall("PerimeterQuay",Vector3(0,3.2,QUAY+.2),Vector3(b.def.extent.x,6.4,.4))
	# Rubber fenders and recessed ladders on the quay face.
	for x in range(-50,51,10):
		d(Vector3(x,-.95,QUAY+.62),Vector3(1.1,1.7,.26),Color("1d1f20"))
		d(Vector3(x,-.2,QUAY+.52),Vector3(1.3,.14,.1),Color("2a2c2d"))
	for x in [-35,15,47]:
		for side in [-1,1]:d(Vector3(x+side*.22,-1.2,QUAY+.52),Vector3(.05,2.6,.05),Color("6f6a5e"))
		for y in range(0,6):d(Vector3(x,-2.3+y*.32,QUAY+.52),Vector3(.44,.04,.04),Color("6f6a5e"))
	# Bollards along the edge, one coiled line on a few of them.
	for i in 12:
		var x:=-49.5+i*9.0
		bollard(Vector3(x,0,QUAY-1.0))
	for x in [-49.5,-13.5,22.5]:rope_coil(Vector3(x+.9,0,QUAY-1.4))
	for x in [-7.0,7.0]:lifebuoy_post(Vector3(x,0,QUAY-1.0))
	# Crane rails: steel rail set flush in a concrete strip, with end stops.
	for z in [RAIL_LAND,RAIL_SEA]:
		for x in range(-54,55,12):
			d(Vector3(x+6,.018,z),Vector3(12.0,.036,.16),Color("3f3d3a"))
			d(Vector3(x+6,.037,z),Vector3(12.0,.004,.07),Color("9a9894"))
		for x in range(-54,55,6):d(Vector3(x+3,.006,z),Vector3(5.8,.008,.9),Color("8e8c86"),"concrete")
		for side in [-1,1]:b.box("RailStop",Vector3(side*53.6,.6,z),Vector3(.8,1.2,1.2),YELLOW)
	# Navigation buoys and a lateral marker out in the basin.
	b.props.place("ocean_buoy",b.props.grounded("ocean_buoy",Vector3(-30,WATER_Y-.9,96),.4,1.0),false,400.0)

func invisible_wall(label: String, center: Vector3, size: Vector3) -> void:
	var holder:=Node3D.new();holder.name=label+str(b.serial);b.serial+=1
	b.region.add_child(holder);holder.position=center
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","concrete")
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box
	body.add_child(shape);holder.add_child(body)

func water() -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners:=[Vector3(-900,0,QUAY+.5),Vector3(900,0,QUAY+.5),Vector3(900,0,900),Vector3(-900,0,900)]
	for index in [0,1,2,0,2,3]:
		var p:Vector3=corners[index]
		st.set_normal(Vector3.UP);st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
	st.generate_tangents()
	var mat:=ShaderMaterial.new();mat.shader=load("res://content/materials/harbor_water.gdshader")
	for slot in [["wave_a",7,.018],["wave_b",19,.045]]:
		var noise:=FastNoiseLite.new();noise.seed=int(slot[1]);noise.frequency=float(slot[2]);noise.fractal_octaves=4
		var waves:=NoiseTexture2D.new();waves.width=512;waves.height=512;waves.seamless=true;waves.as_normal_map=true;waves.bump_strength=6.0;waves.noise=noise
		mat.set_shader_parameter(slot[0],waves)
	var node:=MeshInstance3D.new();node.name="HarbourWater";node.mesh=st.commit();node.material_override=mat
	node.position.y=WATER_Y;node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.arena.add_child(node)

# --- Gate houses (spawn annexes) -------------------------------------------------

func deployment(builder: CompactMapBuilder) -> void:
	b=builder
	for team in 2:
		var side:=-1.0 if team==0 else 1.0
		for row in 4:
			for col in 4:
				var p:=Vector3(side*(b.def.extent.x*.5-6-col*2),.05,[-26,-5,5,26][row])
				(b.def.spawns_blue if team==0 else b.def.spawns_red).append(p)
		b.modern_building(Vector3(side*(b.def.extent.x*.5-11),0,0),Vector2(12,20),3.6,"GATE 2  /  STEVEDORES" if team==0 else "GATE 4  /  PORT SECURITY")
		for z in [-22,22]:
			b.sign_text("BERTH 3  /  WEST" if team==0 else "BERTH 3  /  EAST",Vector3(side*(b.def.extent.x*.5-17.18),2.85,signf(z)*6),PI*.5 if team==0 else -PI*.5,b.accent,25)
		for z in [-6.5,6.5]:b.cover(Vector3(side*34.5,0,z),2.8,Color("6d777c"))

# --- Play space -------------------------------------------------------------------

func build(builder: CompactMapBuilder) -> void:
	b=builder
	warehouse(Vector3(0,0,-30),Vector2(32,18),8.0)
	for side in [-1,1]:
		# Furnished by hand: the shared furnished option adds a 23k-triangle pot plant.
		var office:=Vector3(side*28,0,-33)
		b.modern_building(office,Vector2(11,9),3.8,"DOCK OFFICE" if side<0 else "CUSTOMS  /  INSPECTION",true)
		for corner in [-1,1]:b.prop("metal_office_desk",office+Vector3(corner*3.6,0,corner*2.4),.76,0.0 if corner<0 else PI)
		for i in 3:b.box("FilingCabinet",office+Vector3(2.45+i*.52,.66,-4.0),Vector3(.48,1.32,.62),Color("6a7472"))
	yard()
	apron()
	service_road()
	for side in [-1,1]:
		flood_mast(Vector3(side*15.75,0,-11.2))
		flood_mast(Vector3(side*33,0,22))
	for x in [-82.0,84.0]:crane(x,x>0,false)
	tug(Vector3(-34,WATER_Y,51.3))
	for side in [-1,1]:gas_cage(Vector3(side*36.6,0,-38.2))
	markings()
	puddles()
	flush_batches()

# The container yard: mirrored blocks (rows of 40 ft boxes stacked 1-3 high)
# with 2.3-4.8 m alleys between them and a central east-west street.
func yard() -> void:
	for side in [-1,1]:
		var s:=float(side)
		yard_block(Vector3(s*23,0,-5),3,[2,3,1],side)
		yard_block(Vector3(s*8.5,0,-5),2,[1,2],side)
		yard_block(Vector3(s*23,0,12),3,[1,3,2],side)
		yard_block(Vector3(s*8.5,0,12),2,[2,1],side)
		# Low cover where the alleys meet the street.
		pallet_stack(Vector3(s*15.75,0,3.5),PI*.5,8)
		pallet_stack(Vector3(s*15.75,0,4.9),PI*.5,5)
		b.drum(Vector3(s*30.5,0,3.0));b.drum(Vector3(s*30.6,0,4.1))
	# Boxes set down along the apron road break its long sight line.
	for side in [-1,1]:
		var s:=float(side)
		container(Vector3(s*14.5,0,22.0),PI*.5,BOX_COLORS[7 if side<0 else 10],6.058,side>0)
		add_cover_pair(Vector3(s*14.5,0,22.0),PI*.5,6.058,2.44)
		container(Vector3(s*27.0,0,22.4),0.0,BOX_COLORS[0 if side<0 else 11],6.058,side<0)
		container(Vector3(s*27.0,2.591,22.4),0.0,BOX_COLORS[9 if side<0 else 2],6.058,side>0)
		add_cover_pair(Vector3(s*27.0,0,22.4),0.0,6.058,2.44)
	# The street's centre: a single 20 ft box turned across it.
	container(Vector3(0,0,3.5),PI*.5,BOX_COLORS[5],6.058,true)
	add_cover_pair(Vector3(0,0,3.5),PI*.5,6.058,2.44)

func yard_block(center: Vector3, rows: int, heights: Array, side: int) -> void:
	var length:=12.192;var pitch:=2.74
	var width:=rows*2.438+(rows-1)*.3
	for row in rows:
		var z:=center.z-width*.5+1.219+row*pitch
		occluder(Vector3(center.x,int(heights[row])*1.2955,z),Vector3(length-.2,int(heights[row])*2.591-.1,2.3))
		for tier in int(heights[row]):
			var color:Color=BOX_COLORS[(paint_index*7+tier*3+row)%BOX_COLORS.size()];paint_index+=1
			container(Vector3(center.x,tier*2.591,z),0.0,color,length,(row+tier+side)%2==0)
	# Painted slot outline: the long lines run the full outline width and the short ends fit
	# between them, so no two painted strips overlap. Each box has one row number, at its outer
	# end (the inner box's number sits in the 1.6 m alley, which is why its reach differs).
	var half_w:=width*.5+.35;var half_l:=length*.5+.35
	for sz in [-1,1]:line(Vector3(center.x,.012,center.z+sz*half_w),Vector3(length+.82,.006,.12),WHITE_LINE)
	for sx in [-1,1]:line(Vector3(center.x+sx*half_l,.012,center.z),Vector3(.12,.006,half_w*2.0-.12),WHITE_LINE)
	var tag:="%s%02d"%["C" if center.z>0 else "B",int(absf(center.x))]
	var toward:=signf(center.x)
	var tag_x:=center.x+toward*(length*.5+(1.15 if absf(center.x)<15.0 else 1.4))
	ground_text(tag,Vector3(tag_x,.02,center.z),PI*.5*toward,WHITE_LINE)
	b.painted.append(Rect2(tag_x-.7,center.z-1.6,1.4,3.2))
	for sz in [-1,1]:
		for sx in [-1,1]:
			var p:=Vector3(center.x+sx*length*.25,0,center.z+sz*(width*.5+1.6))
			b.def.cover_points.append(p)
			b.def.cover_peeks.append(Vector3(center.x+sx*(length*.5+1.0),0,p.z))

# A strip of paint on the ground, recorded so nothing else is printed over it.
func line(center: Vector3, size: Vector3, color: Color) -> void:
	d(center,size,color,"concrete")
	b.painted.append(Rect2(center.x-size.x*.5,center.z-size.z*.5,size.x,size.z))

# Box occluder (no collision, no visual): lets the renderer cull what is hidden
# behind container rows and solid walls.
func occluder(center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var node:=OccluderInstance3D.new();node.name="Occluder"+str(b.serial);b.serial+=1
	var box:=BoxOccluder3D.new();box.size=size;node.occluder=box
	b.region.add_child(node);node.position=center;node.rotation.y=yaw

# Cover markers on both long faces of a single box (yaw 0 = along X).
func add_cover_pair(center: Vector3, yaw: float, length: float, width: float) -> void:
	var turn:=Basis(Vector3.UP,yaw)
	for sz in [-1,1]:
		b.def.cover_points.append(center+turn*Vector3(0,0,sz*(width*.5+1.5)))
		b.def.cover_peeks.append(center+turn*Vector3(sz*(length*.5+1.0),0,sz*(width*.5+1.5)))

# An ISO box: 40 ft (12.19 m) or 20 ft (6.06 m) x 2.44 x 2.59, one mesh per
# length (corrugated walls, corner posts and castings, rails, cargo doors) in
# the box's paint; the collider is the plain box.
func container(base: Vector3, yaw: float, color: Color, length := 12.192, doors_forward := true) -> void:
	var root:=b.box("Freight",base+Vector3(0,1.2955,0),Vector3(length,2.591,2.438),color)
	root.rotation.y=yaw+(0.0 if doors_forward else PI)
	var visual:MeshInstance3D=root.get_child(0)
	visual.mesh=container_mesh(length);visual.material_override=container_material(color)

func container_mesh(length: float) -> ArrayMesh:
	var key:="harbor_box_mesh%.2f"%length
	if b.meshes.has(key):return b.meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cache:={}
	var add:=func(size:Vector3,at:Vector3,bevel:float,grime:float) -> void:
		var id:=str(size)+str(bevel)+str(grime)
		if not cache.has(id):cache[id]=MapMeshes.block(size,bevel,grime) if grime>0.0 else simple_box(size)
		st.append_from(cache[id],0,Transform3D(Basis.IDENTITY,at))
	var hx:=length*.5;var hy:=1.2955;var hz:=1.219;var depth:=.036
	# No two faces of the box share a plane: the core sits 2.5 cm inside the frame's top and 1.2 cm
	# behind the corrugation valleys, rails stand 1 cm proud of the crests, and castings are wider
	# at the top (2 cm) than at the foot (1 cm), so a stacked box never meets a casting face to face.
	add.call(Vector3(length-.04,2.591-.05,2.438-depth*2.0-.024),Vector3.ZERO,.02,.45)
	# Trapezoidal corrugated sheets on both side walls and the blind end.
	var side:=corrugated_sheet(length-.34,2.27,depth)
	st.append_from(side,0,Transform3D(Basis.IDENTITY,Vector3(0,0,hz-depth)))
	st.append_from(side,0,Transform3D(Basis(Vector3.UP,PI),Vector3(0,0,-(hz-depth))))
	st.append_from(corrugated_sheet(2.1,2.27,depth),0,Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(-(hx-depth),0,0)))
	# Frame: corner posts, castings, side and end rails.
	for sx in [-1.0,1.0]:
		for sz in [-1.0,1.0]:
			add.call(Vector3(.17,2.591,.17),Vector3(sx*(hx-.085),0,sz*(hz-.085)),.01,0.0)
			add.call(Vector3(.21,.2,.21),Vector3(sx*(hx-.09),hy-.09,sz*(hz-.09)),.01,0.0)
			add.call(Vector3(.19,.19,.19),Vector3(sx*(hx-.09),-hy+.095,sz*(hz-.09)),.01,0.0)
		for y in [-hy+.08,hy-.09]:
			add.call(Vector3(length-.34,.16,.06),Vector3(0,y,sx*(hz-.02)),.008,0.0)
			add.call(Vector3(.06,.16,2.1),Vector3(sx*(hx-.02),y,0),.008,0.0)
	# Cargo doors at +X: two leaves with a seam, four locking bars, keepers, handles, hinges.
	for sz in [-1.0,1.0]:add.call(Vector3(.03,2.3,1.05),Vector3(hx+.005,0,sz*.555),.006,0.0)
	add.call(Vector3(.035,2.3,.03),Vector3(hx+.01,0,0),0.0,0.0)
	for z in [-.9,-.31,.31,.9]:
		add.call(Vector3(.045,2.28,.045),Vector3(hx+.04,0,z),0.0,0.0)
		for y in [-1.0,1.0]:add.call(Vector3(.07,.1,.1),Vector3(hx+.045,y,z),0.0,0.0)
		add.call(Vector3(.045,.045,.26),Vector3(hx+.08,-.25,z+(.12 if z<0 else -.12)),0.0,0.0)
	for z in [-1.15,1.15]:
		for y in [-.85,0.0,.85]:add.call(Vector3(.06,.14,.1),Vector3(hx+.02,y,z),0.0,0.0)
	st.index()
	var mesh:=st.commit()
	mesh.lightmap_unwrap(Transform3D.IDENTITY,.5)
	mesh=with_lods(mesh)
	b.meshes[key]=mesh
	return mesh

# Adds automatic LODs (corrugation and small parts collapse at distance instead
# of rasterising sub-pixel slivers); keeps the lightmap UV2 already unwrapped.
func with_lods(mesh: ArrayMesh) -> ArrayMesh:
	var importer:=ImporterMesh.new()
	for i in mesh.get_surface_count():importer.add_surface(mesh.surface_get_primitive_type(i),mesh.surface_get_arrays(i))
	importer.generate_lods(25.0,60.0,[])
	var result:=importer.get_mesh()
	result.lightmap_size_hint=mesh.lightmap_size_hint
	return result

# A corrugated steel sheet (0.28 m trapezoid pitch) centred on the origin in the
# XY plane, ribs standing out to +Z by depth; dirt gathers toward its foot.
func corrugated_sheet(length: float, height: float, depth: float) -> ArrayMesh:
	var key:="harbor_sheet%.3f/%.3f"%[length,height]
	if b.meshes.has(key):return b.meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pitch:=length/maxf(1.0,roundf(length/.28));var w:=pitch*.36;var slope:=pitch*.14
	var profile:Array[Vector2]=[]
	var x:=-length*.5
	while x<length*.5-.001:
		profile.append_array([Vector2(x,depth),Vector2(x+w,depth),Vector2(x+w+slope,0.0),Vector2(x+w*2+slope,0.0)])
		x+=pitch
	profile.append(Vector2(length*.5,depth))
	var h:=height*.5
	for i in profile.size()-1:
		var a:=profile[i];var c:=profile[i+1]
		var n:=Vector3(-(c.y-a.y),0,c.x-a.x).normalized()
		var quad:=[Vector3(a.x,-h,a.y),Vector3(c.x,-h,c.y),Vector3(c.x,h,c.y),Vector3(a.x,h,a.y)]
		for tri in [[0,2,1],[0,3,2]]:
			for k in tri:
				var p:Vector3=quad[k]
				st.set_color(Color(lerpf(.35,1.0,smoothstep(0.0,.9,p.y+h)),1.0 if a.y==c.y else .6,1.0))
				st.set_normal(n);st.set_uv(Vector2(p.x,h-p.y));st.add_vertex(p)
	st.index();st.generate_tangents()
	var mesh:=st.commit()
	b.meshes[key]=mesh
	return mesh

# Boxes reuse the rusty red scan; other colours repaint it, keeping its runs.
func container_material(color: Color) -> Material:
	if MapBuilder.container_surface(color)=="container_red":return b.surfaces.get_material("container_red")
	var key:="harbor_box"+color.to_html(false)
	if b.materials.has(key):return b.materials[key]
	var mat:ShaderMaterial=b.surfaces.get_material("container_red").duplicate()
	mat.set_shader_parameter("tint",color)
	mat.set_shader_parameter("tint_mix",.9)
	mat.set_shader_parameter("paint_gain",2.6)
	b.materials[key]=mat
	return mat

# Scanned rusty steel for bollards, rail stops and crane bogies.
func rust_material(tint := Color.WHITE, mix := 0.0) -> Material:
	var key:="harbor_rust"+tint.to_html(false)
	if b.materials.has(key):return b.materials[key]
	var mat:ShaderMaterial=b.surfaces.get_material("rust").duplicate()
	var folder:="res://content/materials/rusty_metal_02/rusty_metal_02_"
	mat.set_shader_parameter("albedo_tex",load(folder+"diff_1k.jpg"))
	mat.set_shader_parameter("normal_tex",load(folder+"nor_gl_1k.jpg"))
	mat.set_shader_parameter("arm_tex",load(folder+"arm_1k.jpg"))
	mat.set_shader_parameter("uv_scale",1.0/1.2)
	mat.set_shader_parameter("tint",tint);mat.set_shader_parameter("tint_mix",mix);mat.set_shader_parameter("paint_gain",2.2)
	b.materials[key]=mat
	return mat

# --- Warehouse 7 -------------------------------------------------------------------

# Corrugated steel shed on a concrete plinth. Ground floor with racking and
# pallets; a steel mezzanine along the yard-side wall (deck at 3.6 m) reached by
# a ramp at each end, with open louvred windows over the yard.
func warehouse(center: Vector3, size: Vector2, height: float) -> void:
	var hx:=size.x*.5;var hz:=size.y*.5;var t:=.3
	b.footprints.append(Rect2(center.x-hx,center.z-hz,size.x,size.y))
	b.buildings.append({"center":center,"size":size,"height":height,"furnished":false,"door":3.2,"wall":t})
	var cladding:=Color("7d8a8e")
	# Openings are Rect2(x from the wall's left end, y, width, height); every wall
	# is symmetric so its orientation does not matter.
	var south:=[Rect2(hx-7-2.2,0,4.4,3.2),Rect2(hx+7-2.2,0,4.4,3.2)]
	for x in [-12,-6,0,6,12]:south.append(Rect2(hx+x-1.3,4.4,2.6,1.2))
	var north:=[Rect2(hx-1.5,0,3,3)]
	for x in [-12,-6,6,12]:north.append(Rect2(hx+x-1.5,6.0,3,1.0))
	var ends:=[Rect2(hz-1.5,0,3,3.1)]
	for z in [-5,5]:ends.append(Rect2(hz+z-1.5,6.0,3,1.0))
	clad_wall(center+Vector3(0,0,hz),size.x,height,t,south,false,cladding)
	clad_wall(center+Vector3(0,0,-hz),size.x,height,t,north,false,cladding)
	for side in [-1,1]:clad_wall(center+Vector3(side*hx,0,0),size.y,height,t,ends,true,cladding)
	for side in [-1,1]:
		for reach in [1.5,4.0]:
			b.avoid.append_array([center+Vector3(side*7,0,hz+reach),center+Vector3(side*(hx+reach),0,0),center+Vector3(0,0,-hz-reach)])
	# Roof, eaves gutters, downpipes, corner trims and a ridge vent.
	b.box("Roof",center+Vector3(0,height+.16,0),Vector3(size.x+.6,.32,size.y+.6),Color("5d6569"))
	occluder(center+Vector3(0,height+.16,0),Vector3(size.x,.3,size.y))
	b.box("InteriorSlab",center+Vector3(0,.015,0),Vector3(size.x-.3,.03,size.y-.3),Color("cfcdc5"),false)
	for side in [-1,1]:
		# Gutter tight under the roof edge against the wall, downpipes touching the wall with clips.
		cyl(center+Vector3(0,height-.05,side*(hz+.25)),.09,size.x+.58,Color("5f6568"),Basis(Vector3.BACK,PI*.5))
		for x in [-hx+.6,hx-.6]:
			cyl(center+Vector3(x,(height-.1)*.5,side*(hz+.15+.06)),.06,height-.1,Color("5f6568"))
			for y in [.5,height*.35,height*.7]:d(center+Vector3(x,y,side*(hz+.15+.03)),Vector3(.16,.05,.06),Color("4a5154"))
		for x in [-hx,hx]:d(center+Vector3(x,height*.5,side*hz),Vector3(.42,height,.42),Color("4a5154"))
	for x in range(-12,13,6):
		b.box("Ventilation",center+Vector3(x,height+.6,0),Vector3(2.2,.9,1.3),Color("9ea19c"),false)
	for x in range(-int(hx)+2,int(hx)-1,4):d(center+Vector3(x,height-.45,0),Vector3(.3,.5,size.y-.6),Color("586064"))
	# Signage above the loading doors and on the gable ends.
	# The north wall's louvred windows start 4.5 m from the centre line: the lettering is sized to
	# fit between them (and is used on both faces so they match).
	var sign_size:=b.fit_font("WAREHOUSE  7",8.4,1.1,120)
	b.sign_text("WAREHOUSE  7",center+Vector3(0,6.9,hz+.2),0,Color("e6e4dc"),sign_size)
	b.sign_text("WAREHOUSE  7",center+Vector3(0,6.9,-hz-.2),PI,Color("e6e4dc"),sign_size)
	for side in [-1,1]:
		b.sign_text("7",center+Vector3(side*(hx+.2),5.0,0),side*PI*.5,Color("e6e4dc"),260)
		# Shutter housings and guide rails over the loading doors.
		var door:=center+Vector3(side*7,0,hz)
		b.box("ShutterHousing",door+Vector3(0,3.5,.4),Vector3(5.0,.6,.5),Color("596164"),false)
		for x in [-2.3,2.3]:d(door+Vector3(x,1.6,.23),Vector3(.14,3.2,.16),YELLOW)
		# Half-raised shutter: slats hang in the top of the opening.
		for i in 4:d(door+Vector3(0,3.1-i*.11,.05),Vector3(4.4,.1,.04),Color("8a9396"))
		b.stains.append(door+Vector3(0,0,3.5))
		# Painted crossing outside each loading door.
		for i in 6:line(door+Vector3(-2.5+i*1.0,.012,3.2),Vector3(.5,.006,2.4),WHITE_LINE)
	mezzanine(center,size)
	ground_floor(center,size)
	b.interior_lighting(center,size,height)
	# Extra fittings under the mezzanine, baked like the hall fixtures.
	for x in [-10.0,0.0,10.0]:
		var fixture:=center+Vector3(x,3.1,hz-2.0)
		b.box("LampHousing",fixture+Vector3(0,.06,0),Vector3(1.5,.1,.32),Color("8d9296"),false)
		b.box("CeilingLamp",fixture,Vector3(1.38,.04,.2),Color("f4f1e6"),false)
		var lamp:=OmniLight3D.new();lamp.name="FixtureLight"+str(b.serial);b.serial+=1
		lamp.position=fixture+Vector3(0,-.25,0);lamp.light_color=Color(1.0,.955,.86)
		lamp.light_energy=1.4;lamp.light_indirect_energy=1.2;lamp.omni_range=7.0;lamp.omni_attenuation=1.4
		lamp.shadow_enabled=true;lamp.light_size=.3;lamp.light_bake_mode=Light3D.BAKE_STATIC
		b.region.add_child(lamp)

# One wall: a corrugated slab (visual mesh with real openings), collision boxes
# around the openings and a concrete plinth outside except at doorways.
func clad_wall(mid: Vector3, length: float, height: float, thick: float, openings: Array, along_z: bool, color: Color) -> void:
	var holder:=b.box("ContextWarehouse",mid+Vector3(0,height*.5,0),Vector3(length,height,thick),color,false)
	var visual:MeshInstance3D=holder.get_child(0)
	var key:="harbor_wall"+str(Vector3(length,height,thick))+str(openings)
	if not b.meshes.has(key):
		b.meshes[key]=MapMeshes.wall(Vector3(length,height,thick),openings,1.0)
		b.meshes[key].lightmap_unwrap(Transform3D.IDENTITY,.35)
	visual.mesh=b.meshes[key]
	if along_z:holder.rotation.y=PI*.5
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
	holder.add_child(body)
	# Vertical strips between opening edges; each strip is solid except where openings cut it.
	var xs:Array[float]=[0.0,length]
	for rect:Rect2 in openings:xs.append_array([rect.position.x,rect.end.x])
	xs.sort()
	for i in xs.size()-1:
		var x0:=xs[i];var x1:=xs[i+1]
		if x1-x0<.01:continue
		var spans:Array[Vector2]=[]
		for rect:Rect2 in openings:
			if rect.position.x<=x0+.001 and rect.end.x>=x1-.001:spans.append(Vector2(rect.position.y,rect.end.y))
		spans.sort_custom(func(a:Vector2,c:Vector2):return a.x<c.x)
		if spans.is_empty() and x1-x0>1.5:
			var strip:=OccluderInstance3D.new();var volume:=BoxOccluder3D.new();volume.size=Vector3(x1-x0,height,thick*.9)
			strip.occluder=volume;strip.position=Vector3((x0+x1)*.5-length*.5,0,0);holder.add_child(strip)
		var y:=0.0
		for span in spans+[Vector2(height,height)]:
			if span.x-y>.01:
				var shape:=CollisionShape3D.new();var box:=BoxShape3D.new()
				box.size=Vector3(x1-x0,span.x-y,thick);shape.shape=box
				shape.position=Vector3((x0+x1)*.5-length*.5,(y+span.x)*.5-height*.5,0)
				body.add_child(shape)
			y=maxf(y,span.y)
	# Plinth: one continuous concrete run per stretch of solid wall (broken only at doorways),
	# with a projecting cap, so it never stops mid-wall.
	var turn:=Basis(Vector3.UP,PI*.5 if along_z else 0.0)
	var rot:=Vector3(0,PI*.5 if along_z else 0.0,0)
	var outward:=turn*Vector3(0,0,1)
	var runs:Array[Vector2]=[]
	for i in xs.size()-1:
		var x0:=xs[i];var x1:=xs[i+1]
		if x1-x0<.05:continue
		var door:=openings.any(func(rect:Rect2):return rect.position.y<.01 and rect.position.x<=x0+.001 and rect.end.x>=x1-.001)
		if door:continue
		if not runs.is_empty() and absf(runs.back().y-x0)<.01:runs[runs.size()-1]=Vector2(runs.back().x,x1)
		else:runs.append(Vector2(x0,x1))
	for run in runs:
		var run_length:=run.y-run.x;var run_mid:=(run.x+run.y)*.5-length*.5
		for face in [-1,1]:
			d(mid+turn*Vector3(run_mid,.5,face*(thick*.5+.04)),Vector3(run_length,1.0,.08),Color("9a9890"),"concrete",rot)
			d(mid+turn*Vector3(run_mid,1.03,face*(thick*.5+.07)),Vector3(run_length,.06,.14),Color("aeaca4"),"concrete",rot)
	for rect:Rect2 in openings:
		var pane:=mid+turn*Vector3(rect.position.x+rect.size.x*.5-length*.5,rect.position.y+rect.size.y*.5,0)
		if rect.position.y<.01:
			if w_open(rect):continue
			# Doorway: steel jambs and head just proud of the wall faces, so the opening has a finished edge.
			for sx in [-1,1]:d(pane+turn*Vector3(sx*(rect.size.x*.5+.03),-.015,0),Vector3(.12,rect.size.y-.03,thick+.1),Color("3e4447"),"steel",rot)
			d(pane+turn*Vector3(0,rect.size.y*.5+.03,0),Vector3(rect.size.x+.18,.12,thick+.1),Color("3e4447"),"steel",rot)
			continue
		# Louvred window: a steel frame set inside the reveals (every face 1 cm clear of them), a
		# projecting stool and tilted blades, so the opening reads as a finished window.
		var w:=rect.size.x;var h:=rect.size.y
		var frame_color:=Color("3e4447")
		for sx in [-1,1]:d(pane+turn*Vector3(sx*(w*.5-.05),0,0),Vector3(.08,h-.18,thick-.04),frame_color,"steel",rot)
		for sy in [-1,1]:d(pane+turn*Vector3(0,sy*(h*.5-.05),0),Vector3(w-.02,.08,thick-.04),frame_color,"steel",rot)
		for face in [-1,1]:d(pane+turn*Vector3(0,-h*.5-.03,face*(thick*.5+.05)),Vector3(w+.2,.06,.14),Color("aeaca4"),"concrete",rot)
		var blades:=int((h-.2)/.14)
		for k in blades:
			var y:=-h*.5+.1+(k+.5)*(h-.2)/blades
			d(pane+turn*Vector3(0,y,0),Vector3(w-.2,.014,.11),frame_color.lightened(.1),"steel",Vector3(-.65,PI*.5 if along_z else 0.0,0))

# True for the wide loading doors, which carry their own shutter rails instead of a steel surround.
func w_open(rect: Rect2) -> bool:
	return rect.size.x>4.0

func mezzanine(center: Vector3, size: Vector2) -> void:
	var hx:=size.x*.5-.15;var front:=center.z+size.y*.5-.15-3.85
	var deck_mid:=(front+center.z+size.y*.5-.15)*.5
	b.box("Worktop",Vector3(center.x,3.45,deck_mid),Vector3(hx*2,.3,3.85),Color("777b7b"))
	b.box("DeckEdge",Vector3(center.x,3.3,front+.048),Vector3(hx*2,.36,.12),YELLOW,false)
	for x in [-10.0,-3.5,3.5,10.0]:b.box("SteelColumn",Vector3(center.x+x,1.65,front+.15),Vector3(.26,3.3,.26),Color("3f4649"))
	for x in range(-14,15,4):d(Vector3(center.x+x,3.15,deck_mid),Vector3(.2,.3,3.85),Color("3f4649"))
	# Ramps from the north end of each bay up to the deck edge (17 degrees).
	for side in [-1,1]:
		b.ramp(Vector3(center.x+side*12.6,0,center.z-6.6),Vector3(center.x+side*12.6,3.6,front),2.2)
		for i in 22:
			var z:=center.z-6.3+i*.52
			d(Vector3(center.x+side*12.6,.06+(z-(center.z-6.6))/(front-(center.z-6.6))*3.6,z),Vector3(1.9,.035,.06),Color("2f3436"))
	# Railing along the open edge, leaving the ramp heads clear.
	for span:Vector2 in [Vector2(-hx,-13.75),Vector2(-11.45,11.45),Vector2(13.75,hx)]:
		var length:=span.y-span.x;var mid:=(span.x+span.y)*.5
		var holder:=Node3D.new();b.region.add_child(holder);holder.position=Vector3(center.x+mid,4.12,front+.04)
		holder.name="Railing"+str(b.serial);b.serial+=1
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(length,1.05,.08);shape.shape=box
		body.add_child(shape);holder.add_child(body)
		b.railing_path([Vector3(center.x+span.x,3.6,front+.04),Vector3(center.x+span.y,3.6,front+.04)],1.05,YELLOW,1.5,false)
	# Deck furniture: lockers, a desk and crates.
	var deck:=Vector3(center.x,3.6,deck_mid)
	for x in [-14.6,14.6]:b.box("Locker",deck+Vector3(x,.95,1.2),Vector3(.5,1.9,1.2),Color("5d6e6a"))
	b.prop("metal_office_desk",deck+Vector3(-4.5,0,1.1),.76,PI)
	b.prop("wooden_crate_01",deck+Vector3(4.6,0,1.0),.95,.2)
	b.prop("wooden_crate_01",deck+Vector3(-9.6,0,1.0),.95,-.15)
	b.prop("industrial_pastic_container",deck+Vector3(8.6,0,1.05),1.15,0.0)

func ground_floor(center: Vector3, size: Vector2) -> void:
	for x in [-8.0,-4.0,4.0,8.0]:b.prop("steel_frame_shelves_02",center+Vector3(x,0,-size.y*.5+.75),2.2,0.0)
	b.cargo_cluster(center+Vector3(-6,0,-2.5),0.0)
	b.cargo_cluster(center+Vector3(6,0,1.0),PI)
	forklift(center+Vector3(-1.4,0,-4.6),.45)
	pallet_stack(center+Vector3(9.4,0,-2.2),0.0,9)
	pallet_stack(center+Vector3(-9.6,0,1.6),.1,6)
	for i in 2:b.drum(center+Vector3(-10.4,0,-8.3+i*1.0))
	b.drum(center+Vector3(10.4,0,-8.3))
	b.prop("wooden_crate_01",center+Vector3(2.5,0,-8.0),.95,.1)
	b.prop("wooden_crate_01",center+Vector3(3.6,0,-8.05),.95,-.2)
	for i in 3:d(center+Vector3(-8+i*8,.035,0),Vector3(.12,.006,size.y-4.5),YELLOW,"concrete")

# --- Quay apron ---------------------------------------------------------------------

func apron() -> void:
	crane(-19.0,false,true)
	crane(19.0,true,true)
	for side in [-1,1]:
		var s:=float(side)
		# A 20 ft box landed between the crane legs, and a straddle carrier over a 40 ft box.
		container(Vector3(s*19,0,36.75),0.0,BOX_COLORS[1 if side<0 else 3],6.058,side>0)
		add_cover_pair(Vector3(s*19,0,36.75),0.0,6.058,2.44)
		container(Vector3(s*38.5,0,37.0),0.0,BOX_COLORS[4 if side<0 else 8],12.192,side<0)
		add_cover_pair(Vector3(s*38.5,0,37.0),0.0,12.192,2.44)
		straddle_carrier(Vector3(s*38.5,0,37.0))
		# Lashing bars and twist-lock bins by the rails.
		b.box("LashingBin",Vector3(s*6.5,.45,29.6),Vector3(1.6,.9,1.1),Color("5b6460"))
		for i in 6:d(Vector3(s*6.5-.6+i*.24,1.3,29.6),Vector3(.04,.9,.04),Color("6d6a62"),"steel",Vector3(0,0,.12))
	hatch_cover(Vector3(0,0,37.5))

# A ship-to-shore gantry crane straddling both rails. Legs and bogies collide;
# the portal, boom, apex and stays are batched details overhead.
func crane(x: float, boom_raised: bool, playable: bool) -> void:
	var paint:=CRANE_PAINT;var dark:=CRANE_DARK
	for lx in [x-7.5,x+7.5]:
		for z in [RAIL_LAND,RAIL_SEA]:
			if playable:
				var bogie:=b.box("CraneBogie",Vector3(lx,.9,z),Vector3(3.4,1.8,1.5),dark)
				(bogie.get_child(0) as MeshInstance3D).material_override=rust_material(Color("4f5254"),.55)
				b.box("CraneLeg",Vector3(lx,8.0,z),Vector3(1.3,12.4,1.3),paint)
				b.stains.append(Vector3(lx,0,z))
			else:
				d(Vector3(lx,.9,z),Vector3(3.4,1.8,1.5),dark)
				d(Vector3(lx,8.0,z),Vector3(1.3,12.4,1.3),paint)
			for wx in [-1.0,0.0,1.0]:d(Vector3(lx+wx*1.05,.42,z),Vector3(.8,.8,1.56),Color("2a2d2e"))
			d(Vector3(lx,24.6,z),Vector3(1.1,20.8,1.1),paint)
			d(Vector3(lx,14.9,z),Vector3(1.6,1.0,1.6),dark)
		# Sill beam across the rails at portal height and the girder-level cross head.
		d(Vector3(lx,14.6,(RAIL_LAND+RAIL_SEA)*.5),Vector3(1.3,1.4,RAIL_SEA-RAIL_LAND+1.3),paint)
		d(Vector3(lx,35.4,(RAIL_LAND+RAIL_SEA)*.5),Vector3(1.1,1.2,RAIL_SEA-RAIL_LAND+1.1),paint)
		# Diagonal bracing in the leg frames.
		beam(Vector3(lx,15.6,RAIL_LAND),Vector3(lx,34.6,RAIL_SEA),.5,paint)
		beam(Vector3(lx,15.6,RAIL_SEA),Vector3(lx,34.6,RAIL_LAND),.5,paint)
	for z in [RAIL_LAND,RAIL_SEA]:
		d(Vector3(x,14.6,z),Vector3(16.3,1.4,1.4),paint)
		d(Vector3(x,35.4,z),Vector3(16.3,1.2,1.2),paint)
		beam(Vector3(x-7.5,15.4,z),Vector3(x,34.8,z),.45,paint)
		beam(Vector3(x+7.5,15.4,z),Vector3(x,34.8,z),.45,paint)
	# Girders from the backreach over the rails to the boom hinge at the waterside legs.
	var back:=12.0;var hinge:=Vector3(x,36.9,RAIL_SEA+.8)
	for gx in [-2.5,2.5]:
		d(Vector3(x+gx,36.9,(back+hinge.z)*.5),Vector3(1.2,2.2,hinge.z-back),paint)
		for i in int((hinge.z-back)/3.0):d(Vector3(x+gx,36.9,back+1.5+i*3.0),Vector3(1.26,2.0,.1),paint.darkened(.12))
	for i in 5:d(Vector3(x,36.0,back+2+i*7.0),Vector3(5.0,.5,.5),paint)
	# Boom: horizontal over the water, or raised against the apex when idle.
	var boom_length:=58.0
	var direction:=Vector3(0,sin(deg_to_rad(80.0)),cos(deg_to_rad(80.0))) if boom_raised else Vector3(0,0,1)
	var pitch:=-deg_to_rad(80.0) if boom_raised else 0.0
	for gx in [-2.5,2.5]:
		var start:=hinge+Vector3(gx,0,0)
		d(start+direction*boom_length*.5,Vector3(1.1,2.0,boom_length),paint,"steel",Vector3(pitch,0,0))
		for i in int(boom_length/4.0):
			d(start+direction*(2.0+i*4.0),Vector3(1.16,1.9,.1),paint.darkened(.12),"steel",Vector3(pitch,0,0))
	for i in int(boom_length/6.0):d(hinge+direction*(3.0+i*6.0)+Vector3(0,-.6 if not boom_raised else 0.0,0),Vector3(5.0,.4,.4),paint,"steel",Vector3(pitch,0,0))
	var tip:=hinge+direction*boom_length
	# A-frame apex over the waterside legs, with back and fore stays.
	var apex:=Vector3(x,58.0,RAIL_SEA-2.0)
	for side in [-1,1]:
		beam(Vector3(x+side*7.5,35.6,RAIL_SEA),apex+Vector3(side*1.4,0,0),.9,paint)
		beam(Vector3(x+side*7.5,35.6,RAIL_LAND),apex+Vector3(side*1.4,0,0),.8,paint)
		beam(apex+Vector3(side*1.4,0,0),Vector3(x+side*2.5,37.8,back),.22,dark)
		beam(apex+Vector3(side*1.4,0,0),tip+Vector3(side*2.5,.8,0),.2,dark)
		beam(apex+Vector3(side*1.4,0,0),hinge+direction*boom_length*.55+Vector3(side*2.5,.8,0),.2,dark)
	d(apex,Vector3(4.4,1.4,1.4),paint)
	# Machinery house on the backreach, electrical house, trolley, cab and spreader.
	d(Vector3(x,40.4,back+5.5),Vector3(8.2,5.0,10.5),Color("d5d1c4"))
	d(Vector3(x,43.0,back+5.5),Vector3(8.4,.25,10.7),dark)
	for i in 6:d(Vector3(x+4.13,40.6,back+1.5+i*1.6),Vector3(.04,3.6,.9),Color("8f928e"))
	var trolley_z:=RAIL_SEA-6.0 if boom_raised else RAIL_SEA+14.0
	d(Vector3(x,38.6,trolley_z),Vector3(6.6,1.4,5.6),Color("bfbaa8"))
	d(Vector3(x+1.9,34.2,trolley_z+1.6),Vector3(2.6,2.9,2.8),Color("bfbaa8"))
	d(Vector3(x+1.9,34.5,trolley_z+3.02),Vector3(2.3,1.9,.05),Color("1f2a2f"))
	var hook_y:=28.0 if boom_raised else 12.0
	for rx in [-1.6,1.6]:
		for rz in [-.7,.7]:d(Vector3(x+rx,(37.9+hook_y+.5)*.5,trolley_z+rz),Vector3(.05,37.9-hook_y-.5,.05),Color("2a2b2b"))
	d(Vector3(x,hook_y,trolley_z),Vector3(12.0,.7,2.5),YELLOW)
	d(Vector3(x,hook_y+.6,trolley_z),Vector3(3.2,.7,2.3),YELLOW.darkened(.2))
	# Stair tower up one landside leg, warning band and the crane's number.
	for i in 18:d(Vector3(x-7.5+(1.1 if i%2==0 else -1.1),1.9+i*.7,RAIL_LAND-1.0),Vector3(1.0,.06,.8),dark)
	for z in [RAIL_LAND,RAIL_SEA]:
		for lx in [x-7.5,x+7.5]:
			for i in 4:d(Vector3(lx,2.4+i*.6,z),Vector3(1.34,.3,1.34),YELLOW if i%2==0 else Color("232526"))
	var number:=(3 if x<0 else 4) if absf(x)<40 else (1 if x<0 else 6)
	for side in [-1,1]:label("STS  0%d"%number,Vector3(x,36.9,back+12),side*PI*.5,Color("3c4143"),680)

# A thin straight member between two points, as a rotated detail block.
func beam(from: Vector3, to: Vector3, width: float, color: Color) -> void:
	var span:=to-from
	var basis:=Basis(Quaternion(Vector3.UP,span.normalized()))
	d((from+to)*.5,Vector3(width,span.length(),width),color,"steel",basis.get_euler())

# Painted lettering standing on a surface (side text on cranes and vehicles).
func label(text: String, center: Vector3, yaw: float, color: Color, size: int) -> void:
	var node:=Label3D.new();node.text=text;node.font_size=size;node.pixel_size=.004
	node.modulate=color;node.outline_size=0;node.shaded=true;node.double_sided=false
	node.alpha_cut=Label3D.ALPHA_CUT_DISCARD;node.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	node.position=center+Basis(Vector3.UP,yaw)*Vector3(0,0,3.16);node.rotation.y=yaw
	b.region.add_child(node)

# Lettering painted flat on the ground (bay numbers, berth markings).
func ground_text(text: String, center: Vector3, yaw: float, color: Color, size := 220) -> void:
	var node:=Label3D.new();node.text=text;node.font_size=size;node.pixel_size=.006
	node.modulate=color.darkened(.08);node.outline_size=0;node.shaded=true;node.double_sided=false
	node.alpha_cut=Label3D.ALPHA_CUT_DISCARD;node.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	node.position=center;node.rotation=Vector3(-PI*.5,yaw,0)
	b.region.add_child(node)

# Stacked steel hatch covers landed on the quay: low, wide cover mid-apron.
func hatch_cover(center: Vector3) -> void:
	b.box("Worktop",center+Vector3(0,.42,0),Vector3(10,.84,7),Color("5f6a6f"))
	b.box("Worktop",center+Vector3(.15,1.24,-.1),Vector3(9.6,.8,6.6),Color("6c4a3a"))
	for i in 7:
		d(center+Vector3(-4.5+i*1.5,.42,3.52),Vector3(.12,.7,.06),Color("3e4447"))
		d(center+Vector3(-4.5+i*1.5,.42,-3.52),Vector3(.12,.7,.06),Color("3e4447"))
	for z in [-2.4,0.0,2.4]:d(center+Vector3(0,1.66,z-.1),Vector3(9.4,.06,.12),Color("4f3a2e"))
	for corner in [Vector3(-4.6,0,-3.2),Vector3(4.6,0,3.2)]:d(center+corner+Vector3(0,1.9,0),Vector3(.3,.3,.3),YELLOW)
	b.def.cover_points.append_array([center+Vector3(-2.5,0,5.0),center+Vector3(2.5,0,-5.0),center+Vector3(6.6,0,0)+Vector3(0,0,1.5),center+Vector3(-6.6,0,-1.5)])
	b.def.cover_peeks.append_array([center+Vector3(-6.2,0,5.0),center+Vector3(6.2,0,-5.0),center+Vector3(6.6,0,4.8),center+Vector3(-6.6,0,-4.8)])

# Straddle carrier over a 40 ft box: four legs on wheel bogies, top frame,
# engine and a cab at the top front corner.
func straddle_carrier(center: Vector3) -> void:
	casting=true
	var paint:=Color("d6a72a")  # port safety yellow, painted steel throughout
	for sx in [-1,1]:
		for sz in [-1,1]:
			var leg:=center+Vector3(sx*4.2,0,sz*2.0)
			collider(leg+Vector3(0,6.6,0),Vector3(.6,11.6,.42),0.0,"metal")
			d(leg+Vector3(0,6.6,0),Vector3(.6,11.6,.42),paint)
			d(leg+Vector3(0,.55,sz*.14),Vector3(1.1,1.1,.5),Color("1e2021"))
		d(center+Vector3(sx*4.2,12.6,0),Vector3(.7,.8,4.6),paint)
	for sz in [-1,1]:
		d(center+Vector3(0,12.8,sz*2.0),Vector3(9.2,.9,.5),paint)
		d(center+Vector3(0,1.25,sz*2.05),Vector3(7.8,.5,.4),paint.darkened(.25))
		beam(center+Vector3(-4.2,8.0,sz*2.0),center+Vector3(4.2,12.2,sz*2.0),.25,paint)
	d(center+Vector3(-1.0,13.9,0),Vector3(3.6,1.4,3.2),Color("a2a39b"))
	d(center+Vector3(2.9,11.6,2.6),Vector3(1.6,2.0,1.4),paint)
	d(center+Vector3(3.71,11.8,2.6),Vector3(.04,1.2,1.2),Color("1f2a2f"))
	d(center+Vector3(0,11.4,0),Vector3(6.4,.4,2.6),Color("3d4244"))
	casting=false

# --- Service road (north lane) -------------------------------------------------

func service_road() -> void:
	# Two 20 ft boxes stacked in the road's centre break the long sight line.
	container(Vector3(0,0,-15),0.0,BOX_COLORS[2],6.058,true)
	container(Vector3(0,2.591,-15),0.0,BOX_COLORS[6],6.058,false)
	add_cover_pair(Vector3(0,0,-15),0.0,6.058,2.44)
	for side in [-1,1]:
		var s:=float(side)
		reach_stacker(Vector3(s*27,0,-15.4),PI if side>0 else 0.0)
		pallet_stack(Vector3(s*9.5,0,-18.4),0.0,7)
		b.prop("wooden_crate_01",Vector3(s*8.3,0,-18.3),.95,.3*s)
		b.prop("industrial_pastic_container",Vector3(s*19.5,0,-38.8),1.15,0.0)
		forklift(Vector3(s*19.2,0,-25.0),PI*.5 if side<0 else -PI*.5)

# Reach stacker parked by the road: ladder frame on four big treaded tyres, rear
# engine hood and counterweight, a glazed cab on the right, a two-stage boom on a
# lift ram with hoses, and a 20 ft spreader under the tip. Faces +X when yaw is 0.
# Built from bevelled blocks, lathed tyres and rams; materials carry paint wear,
# rust and the old_tyre scan. Collision stays one box (collider below).
func reach_stacker(center: Vector3, yaw: float) -> void:
	casting=true
	vo=center;vt=Basis(Vector3.UP,yaw)
	var turn:=vt
	var paint:=wear_paint(Color("b83e2f"));var skirt:=wear_paint(Color("6b2219"))
	var steel:=wear_paint(Color("30363a"));var yellow:=wear_paint(Color("b8962f"))
	var black:=wear_paint(Color("1c1e20"));var chrome:=b.surfaces.get_material("painted_metal",Color("9a9fa2"))
	var rust:=rust_material(Color("4a3026"),.5);var glass:=b.glass_material()
	var lens:=b.surfaces.get_material("painted_metal",Color("d9d4b8"));var red_lens:=b.surfaces.get_material("painted_metal",Color("c4261b"))
	var amber:=b.surfaces.get_material("painted_metal",Color("d98a1c"))
	# 0.5 m shorter at the counterweight end than the bodywork, so the lane beside it keeps its navigation clearance.
	collider(center+turn*Vector3(.25,1.5,0),Vector3(8.9,2.2,3.4),yaw,"metal")
	# Ladder frame: rails, cross members, fuel tank, battery box, bumper.
	for z in [-.8,.8]:
		vb(0,1.25,z,9.0,.34,.22,rust,.03)
		vb(0,1.04,z,8.6,.06,.34,steel,.02)
	for x in [-4.2,-1.8,1.2,4.0]:vb(x,1.25,0,.24,.28,1.5,rust,.03)
	vcyl(-.4,.98,-1.1,.36,1.5,0,steel)
	for x in [-.9,.1]:vb(x,.98,-1.1,.06,.8,.46,rust,.0)
	vb(-1.9,1.0,1.18,.8,.5,.5,steel,.04)
	vb(4.6,1.0,0,.3,.5,3.0,steel,.05);vb(4.62,1.32,0,.12,.12,2.8,black,.02)
	for z in [-1.3,1.3]:
		vb(4.5,1.5,z,.24,.22,.34,steel,.04);vb(4.64,1.5,z,.04,.14,.24,lens,.0)
	vb(4.75,.75,0,.18,.16,.4,steel,.03);vcyl(4.8,.75,0,.05,.18,1,chrome,10)
	# Axles, diff housings and wheels (tyre with tread and sidewall, rim, nuts).
	for wx in [-3.0,3.4]:
		vcyl(wx,.8,0,.14,2.9,2,steel);vcyl(wx,.8,0,.3,.7,2,steel,14)
		for wz in [-1.45,1.45]:
			var out:=signf(wz)
			vtyre(Vector3(wx,.8,wz))
			vcyl(wx,.8,wz+out*.02,.46,.5,2,steel,20)
			vcyl(wx,.8,wz+out*.27,.34,.06,2,chrome,18)
			vcyl(wx,.8,wz+out*.31,.12,.1,2,steel,12)
			for i in 10:
				var a:=TAU*i/10.0
				vcyl(wx+cos(a)*.22,.8+sin(a)*.22,wz+out*.31,.026,.07,2,chrome,6)
			# Mudguard with a front lip and a splash flap.
			vb(wx,1.74,wz,1.9,.07,.86,paint,.03)
			vb(wx+(.98 if wx>0 else -.98),1.66,wz,.07,.22,.86,paint,.02)
			vb(wx-(.98 if wx>0 else -.98)*.0,1.62,wz+out*.45,1.9,.2,.05,skirt,.02)
	# Engine hood, louvres, grille, counterweight with hazard bars, lights.
	vb(-3.0,2.15,0,3.2,1.35,2.6,paint,.09)
	vb(-3.0,1.5,0,3.3,.28,2.7,skirt,.05)
	for i in 6:vb(-3.95+i*.34,2.84,0,.14,.03,1.9,black,.0)
	for z in [-1.32,1.32]:
		for i in 5:vb(-3.0-.9+i*.45,2.2,z,.3,.9,.03,black,.0)
	vb(-4.6,1.62,0,.74,1.7,3.1,black,.09)
	for i in 14:vb(-4.99,.95+.0,-1.43+i*.22,.04,.34,.2,yellow if i%2==0 else black,.0)
	vb(-4.99,1.62,0,.04,.34,1.1,wear_paint(Color("c9c4b4")),.0)
	for z in [-1.3,1.3]:vb(-4.99,2.1,z,.05,.24,.36,red_lens,.01)
	vb(-5.02,.64,0,.12,.18,.28,steel,.02)
	vpipe(Vector3(-2.2,2.8,-.95),Vector3(-2.2,4.55,-.95),.08,steel);vcyl(-2.2,4.6,-.95,.12,.05,1,black,10)
	vcyl(-1.7,3.0,-.6,.2,.9,1,steel,12);vpipe(Vector3(-1.7,3.45,-.6),Vector3(-2.3,2.82,-.4),.07,black)
	# Cab on the right side, raised over the frame: floor, waist, posts, roof, glass, door, seat.
	vb(.7,2.0,1.0,2.3,.34,1.6,steel,.05)
	vb(.7,2.4,1.0,2.2,.46,1.58,paint,.05)
	for px in [-.38,1.78]:
		for pz in [.3,1.7]:vb(px,3.1,pz,.1,1.45,.1,steel,.02)
	vb(.7,3.86,1.0,2.4,.12,1.78,paint,.05);vb(.7,3.95,1.0,2.0,.05,1.4,steel,.03)
	vb(1.76,3.0,1.0,.03,1.25,1.5,glass,.0);vb(-.36,3.0,1.0,.03,1.25,1.5,glass,.0)
	vb(.7,3.0,.3,2.1,1.25,.03,glass,.0);vb(.7,3.0,1.7,2.1,1.25,.03,glass,.0)
	vb(.7,2.72,1.7,.09,.7,.09,steel,.02)
	vb(1.3,2.62,1.75,.34,.05,.05,black,.01)
	vb(.5,2.5,1.0,.62,.22,.62,black,.04);vb(.28,2.9,1.0,.14,.9,.6,black,.04);vb(1.25,2.7,1.0,.1,.55,.1,black,.01)
	for z in [.55,1.45]:vb(1.77,3.0,z,.02,.3,.02,black,.0)
	vrod(Vector3(1.8,2.55,.7),Vector3(1.8,3.25,1.2),.03,.03,black)
	for x in [-.05,.7,1.45]:
		for z in [.85,1.55]:vb(x,3.86,1.0+(z-1.2)*.9,.34,.1,.2,lens,.01)
	vcyl(.7,4.05,1.0,.1,.12,1,amber,10)
	for z in [.3,1.7]:
		vb(1.82,3.05,z+(.15 if z<1 else -.15),.05,.05,.28,steel,.0)
		vb(1.7,3.2,z+(-.32 if z<1 else .32),.05,.05,.5,steel,.0)
		vb(1.7,3.2,z+(-.58 if z<1 else .58),.04,.45,.22,black,.01)
	# Cab steps and rails on the right side.
	for y in [1.15,1.65]:vb(.9,y,1.95,.8,.05,.36,rust,.01)
	vpipe(Vector3(1.3,1.1,1.88),Vector3(1.3,3.0,1.88),.025,chrome);vpipe(Vector3(.5,1.1,1.88),Vector3(.5,3.0,1.88),.025,chrome)
	# Boom pivot towers and pin, two-stage boom, wear pads, head, rams, hoses.
	var pivot:=Vector3(-3.6,3.0,-.3);var tip:=Vector3(5.4,8.9,-.3)
	for dz in [-.62,.62]:vb(pivot.x,2.35,pivot.z+dz,.7,1.6,.16,steel,.04)
	vcyl(pivot.x,pivot.y,pivot.z,.14,1.6,2,chrome,14);vcyl(pivot.x,pivot.y,pivot.z,.3,1.1,2,steel,14)
	vrod(pivot,pivot.lerp(tip,.64),.98,1.0,paint,.06)
	vrod(pivot.lerp(tip,.18),pivot.lerp(tip,.62),.14,1.04,black,.02)
	vrod(pivot.lerp(tip,.5),tip,.74,.76,wear_paint(Color("b0402f")),.05)
	vrod(pivot.lerp(tip,.62),pivot.lerp(tip,.7),1.06,1.1,black,.02)
	for i in 3:vrod(pivot.lerp(tip,.7+i*.08),pivot.lerp(tip,.72+i*.08),.8,.84,yellow,.01)
	var head:=tip+Vector3(0,-.15,0)
	vb(head.x+.15,head.y,head.z,.9,.9,1.1,steel,.07);vcyl(head.x+.15,head.y,head.z,.2,1.4,2,chrome,12)
	# Lift ram under the boom and tilt ram at the head.
	var dir:=(tip-pivot).normalized();var under:=Vector3(dir.y,-dir.x,0)
	var anchor:=Vector3(.4,1.62,-.3);var top:=pivot.lerp(tip,.42)+under*.6
	vb(anchor.x,1.55,anchor.z,.5,.5,1.0,steel,.04);vb(top.x,top.y,top.z,.34,.34,.9,steel,.04)
	vram(anchor+Vector3(0,.12,0),top,.16,.085,paint,chrome,steel)
	var t0:=pivot.lerp(tip,.82)+under*.55;var t1:=head+Vector3(-.5,.3,0)
	vram(t0,t1,.1,.055,paint,chrome,steel)
	var h0:=pivot.lerp(tip,.12)+Vector3(0,.0,-.62)+under*.15
	var prev:=h0
	for k in [.4,.6,.8,.98]:
		var s:=pivot.lerp(tip,k)+Vector3(0,.2,-.7)+under*.2
		vpipe(prev,s,.03,black);prev=s
	vb(prev.x,prev.y,prev.z,.1,.1,.08,steel,.0)
	# Spreader: rotator, main beam, end beams, twist-lock castings, guide flippers, hoses.
	var hang:=tip+Vector3(0,-1.0,0)
	vcyl(hang.x,hang.y+.2,hang.z,.46,.34,1,steel,16);vb(hang.x,hang.y-.1,hang.z,.9,.34,.9,steel,.05)
	vb(hang.x,hang.y-.5,hang.z,.55,.44,6.0,yellow,.05)
	for i in 6:vb(hang.x,hang.y-.26,hang.z-2.5+i,.58,.05,.5,black,.0)
	for sz in [-1,1]:
		vb(hang.x,hang.y-.5,hang.z+sz*2.95,2.3,.4,.34,yellow,.05)
		for sx in [-1,1]:
			vb(hang.x+sx*1.08,hang.y-.78,hang.z+sz*2.95,.34,.22,.34,steel,.03)
			vcyl(hang.x+sx*1.08,hang.y-.93,hang.z+sz*2.95,.07,.12,1,black,8)
		vb(hang.x,hang.y-.55,hang.z+sz*3.14,2.3,.5,.04,yellow,.01,Basis(Vector3.RIGHT,-sz*.5))
	for sz in [-1,1]:
		var o:=Vector3(hang.x-.2,hang.y+.1,hang.z+sz*.1)
		var q:=Vector3(hang.x-.2,hang.y-.45,hang.z+sz*2.6)
		vpipe(o,o.lerp(q,.5)+Vector3(0,-.3,0),.03,black);vpipe(o.lerp(q,.5)+Vector3(0,-.3,0),q,.03,black)
	b.stains.append(center)
	casting=false
	b.decal("Leaking006",vp(-2,0,0),Vector2(3.2,2.4),Vector3.UP,yaw,Color(.16,.14,.12,.8))
	for sz in [-1,1]:
		b.def.cover_points.append(center+turn*Vector3(-1.0,0,sz*3.1))
		b.def.cover_peeks.append(center+turn*Vector3(-6.0,0,sz*3.1))

# --- Vehicle part helpers (local coordinates of the vehicle in vo/vt) ----------

# A painted-steel material with heavy paint wear and grime.
func wear_paint(color: Color) -> Material:
	var key:="harbor_wear"+color.to_html(false)
	if b.materials.has(key):return b.materials[key]
	var mat:ShaderMaterial=b.surfaces.get_material("painted_metal",color).duplicate()
	mat.set_shader_parameter("wear_amount",1.0);mat.set_shader_parameter("grime_amount",.7)
	mat.set_shader_parameter("grime_color",Color(.13,.1,.08))
	b.materials[key]=mat
	return mat

# Rubber and tread from the old_tyre scan; the lathed tyre's UVs address its
# tread and sidewall regions directly, so the texture is not tiled.
func tyre_material() -> Material:
	if b.materials.has("harbor_tyre"):return b.materials["harbor_tyre"]
	var mat:ShaderMaterial=b.surfaces.get_material("rust").duplicate()
	var folder:="res://content/models/props/old_tyre/textures/old_tyre_"
	mat.set_shader_parameter("albedo_tex",load(folder+"diff_1k.jpg"))
	mat.set_shader_parameter("normal_tex",load(folder+"nor_gl_1k.jpg"))
	mat.set_shader_parameter("arm_tex",load(folder+"arm_1k.jpg"))
	mat.set_shader_parameter("uv_scale",1.0);mat.set_shader_parameter("tint_mix",0.0)
	mat.set_shader_parameter("grime_amount",.25);mat.set_shader_parameter("wear_amount",0.0)
	mat.set_shader_parameter("roughness_offset",.2)
	b.materials["harbor_tyre"]=mat
	return mat

func vp(x: float, y: float, z: float) -> Vector3:
	return vo+vt*Vector3(x,y,z)

# Bevelled block (plain box when tiny) at local x, y, z; extra rotates it first.
func vb(x: float, y: float, z: float, sx: float, sy: float, sz: float, mat: Material, bevel := .03, extra := Basis.IDENTITY) -> void:
	var size:=Vector3(sx,sy,sz)
	var mesh:Mesh
	if bevel<.012 or minf(sx,minf(sy,sz))<.07:mesh=simple_box(size)
	else:
		var key:="harbor_vb%.3f/%.3f/%.3f/%.3f"%[sx,sy,sz,bevel]
		if not b.meshes.has(key):b.meshes[key]=MapMeshes.block(size,bevel,0.0)
		mesh=b.meshes[key]
	piece(mesh,Transform3D(vt*extra,vp(x,y,z)),mat,casting and sy>.1 and vo.y+y<18.0)

# Cylinder at local x, y, z along local axis (0 x, 1 y, 2 z).
func vcyl(x: float, y: float, z: float, radius: float, length: float, axis: int, mat: Material, segments := 10) -> void:
	var key:="harbor_vc%.3f/%.3f/%d"%[radius,length,segments]
	if not b.meshes.has(key):b.meshes[key]=MapMeshes.cylinder(radius,length,segments)
	var extra:=Basis.IDENTITY
	if axis==0:extra=Basis(Vector3.BACK,PI*.5)
	elif axis==2:extra=Basis(Vector3.RIGHT,PI*.5)
	piece(b.meshes[key],Transform3D(vt*extra,vp(x,y,z)),mat,casting and length>.1)

# Round member between two local points.
func vpipe(a: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var span:=to-a
	var key:="harbor_vp%.3f/%.3f"%[radius,span.length()]
	if not b.meshes.has(key):b.meshes[key]=MapMeshes.cylinder(radius,span.length(),6)
	piece(b.meshes[key],Transform3D(vt*Basis(Quaternion(Vector3.UP,span.normalized())),vp(a.x+span.x*.5,a.y+span.y*.5,a.z+span.z*.5)),mat,false)

# Rectangular member between two local points (section thick x wide, wide along Z).
func vrod(a: Vector3, to: Vector3, thick: float, wide: float, mat: Material, bevel := .03) -> void:
	var span:=to-a
	var dir:=span.normalized()
	var side:=Vector3.BACK
	var x:=dir.cross(side).normalized()
	var frame:=Basis(x,dir,side)
	var size:=Vector3(thick,span.length(),wide)
	var key:="harbor_vr%.3f/%.3f/%.3f/%.3f"%[thick,span.length(),wide,bevel]
	if not b.meshes.has(key):b.meshes[key]=MapMeshes.block(size,bevel,0.0) if bevel>=.012 else simple_box(size)
	piece(b.meshes[key],Transform3D(vt*frame,vp(a.x+span.x*.5,a.y+span.y*.5,a.z+span.z*.5)),mat,casting)

# Hydraulic ram: barrel over the first 55 %, chrome rod beyond, collars and eyes.
func vram(a: Vector3, to: Vector3, barrel: float, rod: float, paint: Material, chrome: Material, steel: Material) -> void:
	var cut:=a.lerp(to,.55)
	vpipe_axis(a,cut,barrel,paint,12);vpipe_axis(cut,to,rod,chrome,8)
	vpipe_axis(cut.lerp(a,.04),cut.lerp(to,.06),barrel*1.18,steel,12)
	vpipe_axis(a,a.lerp(to,.05),barrel*1.15,steel,12)

func vpipe_axis(a: Vector3, to: Vector3, radius: float, mat: Material, segments: int) -> void:
	var span:=to-a
	var key:="harbor_va%.3f/%.3f/%d"%[radius,span.length(),segments]
	if not b.meshes.has(key):b.meshes[key]=MapMeshes.cylinder(radius,span.length(),segments)
	piece(b.meshes[key],Transform3D(vt*Basis(Quaternion(Vector3.UP,span.normalized())),vp(a.x+span.x*.5,a.y+span.y*.5,a.z+span.z*.5)),mat,casting)

# Lathed tyre (axle along local Z): sidewalls, shoulder and a three-rib tread
# with staggered lugs on the outer ribs.
func vtyre(c: Vector3) -> void:
	piece(tyre_mesh(.8,.62),Transform3D(vt*Basis(Vector3.RIGHT,PI*.5),vp(c.x,c.y,c.z)),tyre_material(),casting)

func tyre_mesh(radius: float, width: float) -> ArrayMesh:
	var key:="harbor_tyre%.2f/%.2f"%[radius,width]
	if b.meshes.has(key):return b.meshes[key]
	var rim:=radius*.58;var w:=width*.5;var span:=radius-rim
	# [radius, axial offset, v, lug]: left sidewall, tread ribs and grooves, right sidewall.
	var half:Array=[[rim,-w*.80,.30,0],[rim+span*.30,-w*1.0,.40,0],[rim+span*.78,-w*.98,.54,0],[radius-.03,-w*.86,.64,0],
		[radius,-w*.76,.72,1],[radius,-w*.52,.78,1],[radius-.04,-w*.46,.82,0],[radius-.04,-w*.30,.85,0],[radius,-w*.26,.88,0]]
	var profile:Array=half.duplicate()
	for i in range(half.size()-1,-1,-1):
		var p:Array=half[i]
		profile.append([p[0],-p[1],p[2] if p[2]>.7 else p[2],p[3]*2])
	# The middle rib joins the mirrored half; drop the duplicated centre point.
	var segments:=48
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre:=Vector2(rim+span*.5,0)
	for k in profile.size()-1:
		var p0:Array=profile[k];var p1:Array=profile[k+1]
		var n2:=Vector2(p1[1]-p0[1],-(p1[0]-p0[0]))
		if n2.length()<.0001:continue
		n2=n2.normalized()
		if n2.dot(Vector2((p0[0]+p1[0])*.5,(p0[1]+p1[1])*.5)-centre)<0:n2=-n2
		for i in segments:
			var corners:Array=[]
			for pair in [[p0,i],[p1,i],[p1,i+1],[p0,i+1]]:
				var p:Array=pair[0];var j:int=pair[1]
				var r:float=p[0]
				if p[3]==1 and j%2==1:r-=.035
				if p[3]==2 and j%2==0:r-=.035
				var a:=TAU*j/segments
				corners.append([Vector3(cos(a)*r,p[1],sin(a)*r),Vector2(.95*float(j)/segments,p[2]),Vector3(cos(a)*n2.x,n2.y,sin(a)*n2.x)])
			for tri in [[0,1,2],[0,2,3]]:
				var a:Vector3=corners[tri[0]][0];var bb:Vector3=corners[tri[1]][0];var cc:Vector3=corners[tri[2]][0]
				var order:Array=tri
				if (bb-a).cross(cc-a).dot(corners[tri[0]][2])>0:order=[tri[0],tri[2],tri[1]]
				for idx in order:
					st.set_color(Color(1,1,1));st.set_normal(corners[idx][2]);st.set_uv(corners[idx][1]);st.add_vertex(corners[idx][0])
	st.index();st.generate_tangents()
	var mesh:=st.commit()
	b.meshes[key]=mesh
	return mesh

# Counterbalance forklift with LPG bottle, seat, overhead guard, mast, carriage
# and forks; faces +X at yaw 0.
func forklift(center: Vector3, yaw: float) -> void:
	# Staged freight instead of a box-built forklift (no convincing CC0 forklift model):
	# two pallet stacks on the same footprint keep the cover where it was.
	var turn:=Basis(Vector3.UP,yaw)
	pallet_stack(center+turn*Vector3(-.48,0,0),yaw,9)
	pallet_stack(center+turn*Vector3(.48,0,0),yaw+.06,7)

func collider(center: Vector3, size: Vector3, yaw: float, surface: String) -> void:
	var holder:=Node3D.new();holder.name="Vehicle"+str(b.serial);b.serial+=1
	b.region.add_child(holder);holder.position=center;holder.rotation.y=yaw
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface",surface)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box
	body.add_child(shape);holder.add_child(body)

# --- Merged decorative parts -----------------------------------------------------

# Adds a mesh to the merged batch for its 32 m cell, material and shadow setting.
func piece(mesh: Mesh, transform: Transform3D, material: Material, shadow := true) -> void:
	var o:=transform.origin
	var key:="%d_%d_%d_%d"%[floori(o.x/32.0),floori(o.z/32.0),material.get_instance_id(),int(shadow)]
	if not batches.has(key):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		batches[key]={"st":st,"material":material,"shadow":shadow}
	(batches[key].st as SurfaceTool).append_from(mesh,0,transform)

# A plain box (12 triangles) with metric UVs, for parts too small for bevels
# and grime gradients.
func simple_box(size: Vector3) -> ArrayMesh:
	var key:="harbor_box"+str(size)
	if b.meshes.has(key):return b.meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h:=size*.5
	for axis in 3:
		for dir in [-1.0,1.0]:
			var n:=Vector3.ZERO;n[axis]=dir
			var u:=Vector3.ZERO;u[(axis+1)%3]=1.0
			var v:=Vector3.ZERO;v[(axis+2)%3]=1.0
			var corners:=[]
			for c in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:corners.append(n*h[axis]+u*c.x*h[(axis+1)%3]+v*c.y*h[(axis+2)%3])
			var flip:=(u.cross(v).dot(n)>0)
			for index in ([0,2,1,0,3,2] if flip else [0,1,2,0,2,3]):
				var p:Vector3=corners[index]
				var uv:=Vector2(p.x,p.z) if axis==1 else (Vector2(p.z,h.y-p.y) if axis==0 else Vector2(p.x,h.y-p.y))
				st.set_color(Color(.82 if axis==1 and dir>0 else 1.0,1,1));st.set_normal(n);st.set_uv(uv);st.add_vertex(p)
	st.index();st.generate_tangents()
	var mesh:=st.commit()
	b.meshes[key]=mesh
	return mesh

# A small block in a detail colour (painted steel, or paint/concrete for "concrete").
# Parts high on the cranes cast no shadow: they are outside the near cascades.
func d(center: Vector3, size: Vector3, color: Color, kind := "steel", rotation := Vector3.ZERO) -> void:
	piece(simple_box(size),Transform3D(Basis.from_euler(rotation),center),b.surfaces.get_material(b.detail_surface(kind,color),color),casting and center.y<18.0 and size.y>.05)

func cyl(center: Vector3, radius: float, height: float, color: Color, basis := Basis.IDENTITY) -> void:
	var key:="harbor_cyl%.3f/%.3f"%[radius,height]
	if not b.meshes.has(key):b.meshes[key]=MapMeshes.cylinder(radius,height,clampi(roundi(radius*40),10,28))
	piece(b.meshes[key],Transform3D(basis,center),b.surfaces.get_material("painted_metal",color),casting and center.y<18.0)

func flush_batches() -> void:
	for data in batches.values():
		var node:=MeshInstance3D.new();node.name="HarborParts"+str(b.serial);b.serial+=1
		var mesh:=(data.st as SurfaceTool).commit()
		# Probe-lit instances sample the light probes at their bounds' centre; flat
		# ground markings would sample at (dark) ground level, so lift the bounds.
		var bounds:=mesh.get_aabb()
		node.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
		if bounds.size.y<.1:
			# Painted markings lie on the ground: bake them with it so they match its light.
			mesh.lightmap_unwrap(Transform3D.IDENTITY,.25);node.gi_mode=GeometryInstance3D.GI_MODE_STATIC
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mesh=with_lods(mesh)
			if bounds.size.y<2.5:mesh.custom_aabb=AABB(bounds.position,Vector3(bounds.size.x,2.5,bounds.size.z))
		node.mesh=mesh;node.material_override=data.material
		if not data.shadow:node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.region.add_child(node)
	batches.clear()

# Stacked euro pallets (1.2 x 0.8 x 0.144 m each): one shared mesh per height.
func pallet_stack(center: Vector3, yaw: float, count: int) -> void:
	var key:="harbor_pallets%d"%count
	if not b.meshes.has(key):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for level in count:
			var y0:=level*.144
			var parts:=[]
			for i in 5:parts.append([Vector3(.145 if i in [0,2,4] else .1,.022,1.2),Vector3(-.3275+i*.16375,y0+.133,0)])
			for i in 3:parts.append([Vector3(.145,.022,1.2),Vector3(-.3275+i*.3275,y0+.011,0)])
			for i in 3:
				for j in 3:parts.append([Vector3(.145,.078,.145),Vector3(-.3275+i*.3275,y0+.061,-.5275+j*.5275)])
			for i in 3:parts.append([Vector3(.8,.022,.1),Vector3(0,y0+.111,-.55+i*.55)])
			for part in parts:
				var size:Vector3=part[0];var offset:Vector3=part[1]
				var jitter:=Vector3(sin(level*3.7)*.012,0,cos(level*2.1)*.015)
				st.append_from(simple_box(size),0,Transform3D(Basis.IDENTITY,offset+jitter))
		st.index();st.generate_tangents()
		b.meshes[key]=st.commit()
	var node:=MeshInstance3D.new();node.name="Pallets"+str(b.serial);b.serial+=1
	node.mesh=b.meshes[key];node.material_override=b.surfaces.get_material("wood")
	node.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	node.visibility_range_end=90.0;node.visibility_range_end_margin=12.0;node.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	b.region.add_child(node);node.position=center;node.rotation.y=yaw
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","wood")
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.82,count*.144,1.22);shape.shape=box
	shape.position.y=count*.072;body.add_child(shape);node.add_child(body)

# Cast mooring bollard on a base plate, with a collider so it stops players.
func bollard(base: Vector3) -> void:
	if not b.meshes.has("harbor_bollard"):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(MapMeshes.block(Vector3(.8,.06,.8),.01,0.0),0,Transform3D(Basis.IDENTITY,Vector3(0,.03,0)))
		st.append_from(MapMeshes.cylinder(.2,.62,18),0,Transform3D(Basis.IDENTITY,Vector3(0,.37,0)))
		st.append_from(MapMeshes.cylinder(.31,.12,20),0,Transform3D(Basis(Vector3.RIGHT,.0).scaled(Vector3(1.15,1,.85)),Vector3(.06,.72,0)))
		st.append_from(MapMeshes.cylinder(.24,.08,18),0,Transform3D(Basis.IDENTITY,Vector3(0,.1,0)))
		st.index();st.generate_tangents()
		var mesh:=st.commit();mesh.lightmap_unwrap(Transform3D.IDENTITY,.1)
		b.meshes["harbor_bollard"]=mesh
	var node:=MeshInstance3D.new();node.name="Bollard"+str(b.serial);b.serial+=1
	node.mesh=b.meshes["harbor_bollard"];node.material_override=rust_material(Color("2b2d2d"),.6)
	node.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	b.region.add_child(node);node.position=base
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.62,.8,.62);shape.shape=box
	shape.position.y=.4;body.add_child(shape);node.add_child(body)

# A coiled mooring line lying on the quay beside a bollard.
func rope_coil(center: Vector3) -> void:
	if not b.meshes.has("harbor_rope"):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for loop in 4:
			var radius:=.42-loop*.06
			var turns:=24
			for i in turns:
				var a0:=TAU*i/turns;var a1:=TAU*(i+1)/turns
				var p0:=Vector3(cos(a0)*radius,.04+loop*.05,sin(a0)*radius);var p1:=Vector3(cos(a1)*radius,.04+loop*.05,sin(a1)*radius)
				var piece:=MapMeshes.cylinder(.035,p0.distance_to(p1)+.01,6)
				var dir:=(p1-p0).normalized()
				st.append_from(piece,0,Transform3D(Basis(Quaternion(Vector3.UP,dir)),(p0+p1)*.5))
		st.index();st.generate_tangents()
		b.meshes["harbor_rope"]=st.commit()
	var node:=MeshInstance3D.new();node.name="Rope"+str(b.serial);b.serial+=1
	node.mesh=b.meshes["harbor_rope"]
	if not b.materials.has("harbor_rope"):
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("8a7a52");mat.roughness=.95
		mat.albedo_texture=load("res://content/materials/fabric_albedo.png");mat.uv1_scale=Vector3(6,6,1)
		b.materials["harbor_rope"]=mat
	node.material_override=b.materials["harbor_rope"];node.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	b.region.add_child(node);node.position=center

func lifebuoy_post(base: Vector3) -> void:
	d(base+Vector3(0,.7,.0),Vector3(.08,1.4,.08),Color("b9b3a3"))
	d(base+Vector3(0,1.15,-.06),Vector3(.7,.75,.03),Color("bfb9a8"))
	# Ring buoy: a torus of 16 short tubes in alternating orange and white bands.
	for i in 16:
		var a0:=TAU*i/16.0;var a1:=TAU*(i+1)/16.0
		var p0:=base+Vector3(cos(a0)*.3,1.15+sin(a0)*.3,.06);var p1:=base+Vector3(cos(a1)*.3,1.15+sin(a1)*.3,.06)
		var dir:=p1-p0
		cyl((p0+p1)*.5,.065,dir.length()+.03,Color("d2522a") if int(i/2.0)%2==0 else Color("dedad0"),Basis(Quaternion(Vector3.UP,dir.normalized())))

# Floodlight mast: concrete plinth, two-stage steel pole and a lamp frame.
func flood_mast(base: Vector3) -> void:
	b.box("Sill",base+Vector3(0,.3,0),Vector3(1.3,.6,1.3),b.stone)
	b.cylinder(base+Vector3(0,6.6,0),.42,12.0,Color("8c918f"))
	cyl(base+Vector3(0,18.6,0),.28,12.0,Color("8c918f"))
	d(base+Vector3(0,24.8,0),Vector3(3.6,.12,.9),Color("4a4f51"))
	d(base+Vector3(0,25.9,0),Vector3(3.6,.12,.9),Color("4a4f51"))
	for i in 4:
		var x:=-1.35+i*.9
		d(base+Vector3(x,25.35,.35),Vector3(.75,.75,.3),Color("3b4042"),"steel",Vector3(-.5,0,0))
		d(base+Vector3(x,25.25,.52),Vector3(.62,.6,.03),Color("d9d7cc"),"steel",Vector3(-.5,0,0))
	for i in 10:d(base+Vector3(.3,1.2+i*2.3,0),Vector3(.04,.04,.36),Color("4a4f51"))

# --- Moored harbour tug ------------------------------------------------------------

# A 26 m harbour tug berthed alongside the quay west of the cranes (bow to +X):
# lofted steel hull with bulwarks, deckhouse and wheelhouse, funnels, mast,
# towing winch, tyre fenders and four mooring lines to the quay bollards.
func tug(center: Vector3) -> void:
	casting=true
	var length:=26.0;var beam:=9.2;var stations:=16
	var hull:=SurfaceTool.new();hull.begin(Mesh.PRIMITIVE_TRIANGLES)
	var deck:=SurfaceTool.new();deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings:=[]
	for i in stations+1:
		var t:=float(i)/stations
		var x:=-length*.5+t*length
		var half:=beam*.5*(.86+.14*smoothstep(0.0,.18,t))
		if t>.55:half*=sqrt(maxf(0.0,1.0-pow((t-.55)/.45,2.0)))*.97+.03
		var top:=1.45+1.0*pow(t,2.6)
		var keel:=-3.0+2.4*smoothstep(.72,1.0,t)
		rings.append([Vector3(x,top,half),Vector3(x,.35,half*.995),Vector3(x,-1.5,half*.86),Vector3(x,keel*.9,half*.45),Vector3(x,keel,0.0)])
	for i in stations:
		var ring_a:Array=rings[i];var ring_b:Array=rings[i+1]
		for side in [-1.0,1.0]:
			for k in 4:
				var quad:=[ring_a[k],ring_b[k],ring_b[k+1],ring_a[k+1]]
				for tri in ([[0,1,2],[0,2,3]] if side>0 else [[0,2,1],[0,3,2]]):
					for index in tri:
						var p:Vector3=quad[index];p.z*=side
						hull.set_color(Color(1,1,1));hull.set_uv(Vector2(p.x,-p.y));hull.add_vertex(p)
		# Deck strip and bulwarks (0.9 m) around the edge.
		var a:Vector3=ring_a[0];var c:Vector3=ring_b[0]
		var deck_quad:=[Vector3(a.x,a.y-.05,-a.z),Vector3(c.x,c.y-.05,-c.z),Vector3(c.x,c.y-.05,c.z),Vector3(a.x,a.y-.05,a.z)]
		for index in [0,1,2,0,2,3]:
			var p:Vector3=deck_quad[index]
			deck.set_color(Color(.85,1,1));deck.set_uv(Vector2(p.x,p.z));deck.add_vertex(p)
		for side in [-1.0,1.0]:
			var lo_a:=Vector3(a.x,a.y,a.z*side);var lo_c:=Vector3(c.x,c.y,c.z*side)
			var wall:=[lo_a,lo_c,lo_c+Vector3(0,.9,0),lo_a+Vector3(0,.9,0)]
			for tri in [[0,1,2],[0,2,3],[0,2,1],[0,3,2]]:
				for index in tri:
					var p:Vector3=wall[index]
					hull.set_color(Color(1,1,1));hull.set_uv(Vector2(p.x,-p.y));hull.add_vertex(p)
	# Transom.
	var stern:Array=rings[0]
	for side in [-1.0,1.0]:
		for k in 4:
			var tri:=[Vector3(stern[0].x,stern[0].y,0),stern[k],stern[k+1]]
			for index in ([0,1,2] if side<0 else [0,2,1]):
				var p:Vector3=tri[index];p.z*=side
				hull.set_color(Color(1,1,1));hull.set_uv(Vector2(p.z,-p.y));hull.add_vertex(p)
	var basis:=Basis.IDENTITY
	for pair in [[hull,Color("2a2c2d")],[deck,Color("6a4b3b")]]:
		var tool:SurfaceTool=pair[0]
		tool.index();tool.generate_normals();tool.generate_tangents()
		var node:=MeshInstance3D.new();node.name="Tug"+str(b.serial);b.serial+=1
		node.mesh=tool.commit();node.material_override=b.surfaces.get_material("painted_metal",pair[1])
		node.position=center;node.basis=basis;node.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
		b.region.add_child(node)
	# Red boot topping band at the waterline and a rubbing strake.
	var at:=func(x:float,y:float,z:float) -> Vector3:return center+Vector3(x,y,z)
	var white:=Color("d6d3c8");var dark:=Color("1f2224")
	for i in stations:
		var ring_a:Array=rings[i];var ring_b:Array=rings[i+1]
		for side in [-1.0,1.0]:
			var p0:Vector3=ring_a[0];var p1:Vector3=ring_b[0]
			var mid:=(p0+p1)*.5;var span:=Vector2(p1.x-p0.x,p1.z-p0.z).length()
			var yaw:float=-atan2(p1.z-p0.z,p1.x-p0.x)*side
			d(at.call(mid.x,mid.y-.35,mid.z*side+side*.08),Vector3(span+.05,.28,.18),dark,"steel",Vector3(0,yaw,0))
	# Deckhouse, wheelhouse with its window band, funnels, mast and radar.
	var deck_y:=1.55
	d(at.call(3.0,deck_y+1.3,0),Vector3(8.0,2.6,6.0),white)
	d(at.call(4.3,deck_y+3.75,0),Vector3(4.6,2.3,5.4),white)
	d(at.call(4.3,deck_y+4.15,0),Vector3(4.7,.95,5.5),Color("1b2328"))
	d(at.call(4.3,deck_y+4.95,0),Vector3(5.4,.12,6.2),dark)
	for z in [-1.7,1.7]:
		d(at.call(.2,deck_y+3.9,z),Vector3(1.1,2.6,.9),Color("b23a2c"))
		d(at.call(.2,deck_y+5.25,z),Vector3(1.15,.18,.95),dark)
	beam(at.call(4.6,deck_y+5.0,0),at.call(4.6,deck_y+9.2,0),.18,white)
	d(at.call(4.6,deck_y+8.0,0),Vector3(.12,.12,2.4),white)
	d(at.call(4.6,deck_y+8.5,0),Vector3(1.6,.1,.3),dark)
	for z in [-2.0,2.0]:d(at.call(4.6,deck_y+8.1,z*.55),Vector3(.18,.25,.18),Color("e0dccb"))
	# Towing winch, H-bitt, deck bitts and tyre fenders down the quay side.
	d(at.call(-5.2,deck_y+.65,0),Vector3(2.0,1.3,2.6),Color("56605f"))
	d(at.call(-8.5,deck_y+.6,0),Vector3(.35,1.2,2.2),dark)
	var bitts:={"stern":Vector3(-11.0,deck_y+.35,-3.2),"quarter":Vector3(-7.0,deck_y+.35,-3.9),"bow":Vector3(9.4,deck_y+1.1,-2.4),"breast":Vector3(6.2,deck_y+.55,-3.5)}
	for key in bitts:
		var p:Vector3=bitts[key]
		for dx in [-.25,.25]:cyl(at.call(p.x+dx,p.y,p.z),.13,.55,dark)
	for i in 9:
		var x:=-10.0+i*2.4
		cyl(at.call(x,.9,-4.62),.42,.34,Color("1b1d1e"),Basis(Vector3.RIGHT,PI*.5))
	casting=false
	label("KESTREL",center+Vector3(9.6,2.0,0),PI*.5,Color("d6d3c8"),300)
	# Mooring lines: stern and aft spring from the quarter, head and forward spring from the bow.
	var lines:=[["stern",-49.5],["quarter",-31.5],["bow",-13.5],["breast",-40.5]]
	for line in lines:
		var bitt:Vector3=center+(bitts[line[0]] as Vector3)
		mooring_line(Vector3(float(line[1]),.66,QUAY-1.0),bitt)

# A slack rope from a quay bollard over the edge kerb down to a deck bitt.
func mooring_line(bollard_top: Vector3, bitt: Vector3) -> void:
	var edge:=Vector3(lerpf(bollard_top.x,bitt.x,.12),.36,QUAY-.05)
	var points:=[bollard_top,edge]
	for i in range(1,13):
		var s:=i/12.0
		points.append(edge.lerp(bitt,s)-Vector3(0,.55*4.0*s*(1.0-s),0))
	if not b.materials.has("harbor_rope"):
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("8a7a52");mat.roughness=.95
		mat.albedo_texture=load("res://content/materials/fabric_albedo.png");mat.uv1_scale=Vector3(6,6,1)
		b.materials["harbor_rope"]=mat
	if not b.meshes.has("harbor_rope_unit"):b.meshes["harbor_rope_unit"]=MapMeshes.cylinder(.04,1.0,8)
	for i in points.size()-1:
		var a:Vector3=points[i];var c:Vector3=points[i+1]
		var dir:=(c-a)
		var basis:=Basis(Quaternion(Vector3.UP,dir.normalized()))*Basis.from_scale(Vector3(1,dir.length()+.02,1))
		piece(b.meshes["harbor_rope_unit"],Transform3D(basis,(a+c)*.5),b.materials["harbor_rope"],true)

# Palisade-fenced gas bottle cage beside an office.
func gas_cage(center: Vector3) -> void:
	var size:=Vector2(3.0,2.0)
	collider(center+Vector3(0,1.0,0),Vector3(size.x,2.0,size.y),0.0,"metal")
	var steel:=Color("5d6b63")
	for side in [-1,1]:
		for along in [true,false]:
			var length:=size.x if along else size.y
			var mid:=center+(Vector3(0,0,side*size.y*.5) if along else Vector3(side*size.x*.5,0,0))
			var tangent:=Vector3(1,0,0) if along else Vector3(0,0,1)
			for y in [.35,1.6]:d(mid+Vector3(0,y,0),Vector3(length,.05,.04) if along else Vector3(.04,.05,length),steel)
			var pales:=int(length/.13)
			for i in pales+1:
				var p:=mid+tangent*(-length*.5+i*length/pales)
				d(p+Vector3(0,.95,0),Vector3(.04,1.9,.012) if along else Vector3(.012,1.9,.04),steel)
	for sx in [-1,1]:
		for sz in [-1,1]:d(center+Vector3(sx*size.x*.5,1.0,sz*size.y*.5),Vector3(.07,2.0,.07),steel)
	# Gas bottles: body, shoulder and valve guard.
	for i in 8:
		var spot:=center+Vector3(-1.1+(i%4)*.72,0,-.45+floori(i/4.0)*.9)
		var paint:Color=[Color("8d9294"),Color("9c2f29"),Color("c4a04a"),Color("3c6a4c")][i%4]
		cyl(spot+Vector3(0,.62,0),.15,1.24,paint)
		cyl(spot+Vector3(0,1.28,0),.1,.08,paint.darkened(.2))
		cyl(spot+Vector3(0,1.38,0),.06,.14,Color("5b5e5c"))

# --- Markings, puddles, decals --------------------------------------------------------

func markings() -> void:
	# Lane centre dashes on the service road and the apron road; the dashes beside the warehouse
	# doors are left out where the painted crossings are.
	for x in range(-36,37,6):
		if absf(x)>4 and absf(x)!=6:line(Vector3(x,.012,-18.6),Vector3(3.0,.006,.14),YELLOW)
		line(Vector3(x,.012,24.0),Vector3(3.0,.006,.14),YELLOW)
	# Solid edge lines along the apron road and the crane working zone.
	for z in [18.6,28.8]:line(Vector3(0,.012,z),Vector3(80,.006,.14),WHITE_LINE)
	for z in [-21.8,-11.4]:line(Vector3(0,.012,z),Vector3(60,.006,.12),WHITE_LINE)
	# Hatched no-go boxes around the crane bogies.
	for x in [-26.5,-11.5,11.5,26.5]:
		for z in [RAIL_LAND,RAIL_SEA]:
			b.decal("RoadLines020C",Vector3(x,0,z),Vector2(4.4,2.6),Vector3.UP,0.0,Color(.95,.9,.75,.85))
			b.painted.append(Rect2(x-2.2,z-1.3,4.4,2.6))
	# Berth markings painted along the quay: the name between the crane rails and the cover, the
	# bollard numbers on the strip between the sea rail and the kerb. Both stay clear of the
	# hatched boxes, the rails and the bollards.
	for x in [-19,0,19]:
		ground_text("BERTH 3",Vector3(x,.02,41.8),PI,YELLOW,200)
		b.painted.append(Rect2(x-2.8,41.3,5.6,1.0))
	for i in 7:
		var x:float=[-45,-35,-19,0,19,35,45][i]
		ground_text(str(301+i),Vector3(x,.02,43.95),PI,WHITE_LINE,160)
		b.painted.append(Rect2(x-1.0,43.55,2.0,.8))
	# Oil stains and rust under the apron's machinery, kept off the paint.
	for spot in [Vector3(-19,0,34),Vector3(19,0,39.5),Vector3(-38,0,33),Vector3(38,0,40.5),Vector3(-6,0,26),Vector3(8,0,-21.5),Vector3(-25,0,-11.8),Vector3(30,0,1.2)]:
		if b.on_paint(spot,Vector2(1.3,1.1)):continue
		b.decal("Leaking006",spot,Vector2(2.6,2.2),Vector3.UP,spot.x*.37,Color(.14,.12,.1,.72))

# Standing water on the low spots: thin glossy films with feathered edges.
func puddles() -> void:
	var spots:=[Vector3(-31,0,24.6),Vector3(31,0,23.2),Vector3(-12,0,22.4),Vector3(13,0,25.8),Vector3(-4,0,33.2),Vector3(5,0,42.0),
		Vector3(-24,0,41.5),Vector3(25,0,33.0),Vector3(-20,0,-17.6),Vector3(21,0,-12.8),Vector3(-6,0,-19.5),Vector3(3,0,6.9),
		Vector3(-16,0,-.4),Vector3(16,0,7.6),Vector3(-37,0,-14),Vector3(37,0,-17),
		]
	if not b.materials.has("harbor_puddle"):
		var mat:=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo=true;mat.albedo_color=Color(.05,.055,.06,.9);mat.roughness=.04;mat.metallic_specular=.6
		mat.disable_receive_shadows=false
		b.materials["harbor_puddle"]=mat
	var noise:=FastNoiseLite.new();noise.seed=77;noise.frequency=.9
	for index in spots.size():
		var center:Vector3=spots[index]
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var radius:=1.1+(index%5)*.45;var stretch:=1.0+(index%3)*.45;var segments:=28
		# A puddle never lies over paint or lettering: test the bounds of its turned, stretched outline.
		var reach_x:=radius*stretch*1.3;var reach_z:=radius*1.3;var turn:=index*1.3
		var half:=Vector2(sqrt(pow(reach_x*cos(turn),2.0)+pow(reach_z*sin(turn),2.0)),sqrt(pow(reach_x*sin(turn),2.0)+pow(reach_z*cos(turn),2.0)))
		if b.on_paint(center,half):continue
		var ring:=[]
		for i in segments:
			var a:=TAU*i/segments
			var r:=radius*(1.0+noise.get_noise_2d(cos(a)*2.0+index*7.0,sin(a)*2.0)*.45)
			ring.append(Vector3(cos(a)*r*stretch,0,sin(a)*r))
		for i in segments:
			var p0:Vector3=ring[i];var p1:Vector3=ring[(i+1)%segments]
			for p in [Vector3.ZERO,p1*.62,p0*.62]:
				st.set_color(Color(1,1,1,1));st.set_normal(Vector3.UP);st.add_vertex(p)
			for quad in [[p0*.62,p1*.62,p1],[p0*.62,p1,p0]]:
				for p:Vector3 in quad:
					st.set_color(Color(1,1,1,0.0 if p==p0 or p==p1 else 1.0));st.set_normal(Vector3.UP);st.add_vertex(p)
		var node:=MeshInstance3D.new();node.name="Puddle"+str(index);node.mesh=st.commit()
		node.material_override=b.materials["harbor_puddle"];node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.position=center+Vector3(0,.014,0);node.rotation.y=index*1.3
		b.region.add_child(node)

# --- Objectives ----------------------------------------------------------------

func objectives(builder: CompactMapBuilder) -> void:
	b=builder
	for p in [Vector3(-12,0,-17.5),Vector3(12,0,-17.5),Vector3(-36,0,-21),Vector3(36,0,-21),Vector3(-12.5,0,3.5),Vector3(12.5,0,3.5),Vector3(-10,0,24.5),Vector3(10,0,24.5)]:
		b.def.ammo_caches.append(p)
		b.box("AmmoCase",p+Vector3(0,.35,0),Vector3(1.1,.7,.65),Color("59644d"))
		b.sign_text("SUPPLIES",p+Vector3(0,.42,.333),0,Color("c9d9c5"),15)
	for z in [-18.5,3.5,24.0]:
		for x in [-36,-19,0,19,36]:
			b.def.routes.append(Vector3(x,.05,-1.0 if (x==0 and z==3.5) else z))
	b.def.routes.append_array([Vector3(-30,.05,38.5),Vector3(0,.05,42.4),Vector3(30,.05,38.5),Vector3(0,.05,-30)])
	b.def.domination.assign([Vector3(-23,0,3.5),Vector3(0,0,-1.0),Vector3(23,0,3.5)])
	b.def.hardpoints.assign([Vector3(0,0,-30),Vector3(-23,0,3.5),Vector3(23,0,3.5),Vector3(0,0,25),Vector3(0,0,-18.5)])
	b.def.qa_route.assign([Vector3(-43,0,-17),Vector3(-24,0,-18.5),Vector3(-12.6,0,-37.6),Vector3(-8,3.6,-23),Vector3(0,3.6,-23),Vector3(8,3.6,-23),Vector3(24,0,-18.5),Vector3(23,0,3.5),Vector3(0,0,-1.0),Vector3(0,0,25),Vector3(-30,0,38.5),Vector3(-43,0,17)])

# --- Ground ---------------------------------------------------------------------------

# Splat over the asphalt base: R concrete (quay apron, rail strips, building
# aprons), G gravel along the walls, B dirt in a few worn patches.
func ground_splat(builder: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n:=noise.get_noise_2d(x,z)
	var fine:=noise.get_noise_2d(x*3.3+170.0,z*3.3-40.0)
	var apron:=builder.footprint_distance(x,z)
	var edge:=minf(builder.def.extent.x*.5-absf(x),builder.def.extent.y*.5+z)
	var quay:=smoothstep(28.0,30.5,z+n*1.2)
	var concrete:=maxf(maxf(1.0-smoothstep(1.5,5.0,apron+n*2.0),quay),smoothstep(.5,.85,fine)*.35)
	var gravel:=1.0-smoothstep(.8,3.2,edge+n*2.5)
	var dirt:=smoothstep(.55,.9,noise.get_noise_2d(x*.7-90.0,z*.7+33.0))*.5*(1.0-quay)
	return Color(concrete,gravel*(1.0-concrete*.5),dirt*(1.0-gravel))
