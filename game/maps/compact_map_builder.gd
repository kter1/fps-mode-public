class_name CompactMapBuilder
extends MapBuilder

# Authored in metres. Every wall below uses the same visual and collision size.
# A smaller footprint is built from full-size architecture, never scaled scenes.
# Surfaces, lighting, props, weathering and the backdrop come from MapBuilder
# and its helpers; this class owns the shared compact frame (boundary,
# deployment, objectives) and runs the map's layout script (MapLayout) from
# the registry (MapCatalog).

# Photoscanned surface, bevel (m) and grime height (m) for the compact parts.
const COMPACT_PARTS := {
	"BoundaryWall":["precast",.035,1.0],"ContextWarehouse":["corrugated",.03,1.2],
	"Pavement":["paving",.012,0.0],"InteriorSlab":["floor",0.0,0.0],
	"Sill":["concrete",.02,.4],"Cladding":["shutter",.015,0.0],"Panel":["shutter",.015,.4],
	"EntranceLintel":["precast",.025,0.0],"Gutter":["painted_metal",.008,0.0],
	"DoorFrame":["painted_metal",.008,0.0],"Mullion":["painted_metal",.006,0.0],"CornerPost":["precast",.02,.9],
	"GantryColumn":["painted_metal",.01,.3],"GantryRail":["painted_metal",.005,0.0],
}

func part_info(label: String) -> Array:
	return COMPACT_PARTS[label] if COMPACT_PARTS.has(label) else super.part_info(label)

var layout: MapLayout

func build(id:String) -> MapArena:
	var entry:=MapCatalog.entry(id)
	style=entry.get("style",{});lighting_settings=entry.lighting
	layout=load(entry.layout).new()
	rng.seed=int(entry.seed)
	arena=MapArena.new();arena.name=str(entry.display_name)
	def=MapDefinition.new();def.id=id;def.display_name=arena.name
	def.extent=MapCatalog.vec2(entry.extent)
	def.scene_path=MapCatalog.scene_path(id);arena.definition=def
	stone=Color("d2d0c8");dark=Color("343b40");metal=Color("899092");accent=MapCatalog.color(style.get("accent","c9a35a"))
	region=NavigationRegion3D.new();region.name="Navigation";arena.add_child(region);arena.nav_region=region
	props=MapProps.new(region);nature=MapNature.new(self)
	var nav:=NavigationMesh.new();nav.agent_radius=.5;nav.agent_height=2;nav.agent_max_climb=.25;nav.agent_max_slope=35
	nav.cell_size=.5;nav.cell_height=.25;nav.geometry_parsed_geometry_type=NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS;nav.geometry_collision_mask=1;region.navigation_mesh=nav
	box("Ground",Vector3(0,-.35,0),Vector3(def.extent.x,.7,def.extent.y),Color("b0b0ac"))
	layout.boundaries(self)
	layout.build(self)
	layout.deployment(self)
	layout.objectives(self)
	finish_ground()
	lighting()
	# Outside the boundary: terrain plus the registry's backdrop (an industrial
	# skyline or fir forests).
	nature.terrain()
	var backdrop:Dictionary=style.get("backdrop",{})
	match str(backdrop.get("kind","")):
		"skyline":nature.skyline(float(backdrop.get("nearest",30.0)))
		"forests":nature.forests(float(backdrop.get("nearest",6.0)))
	weathering()
	dressing()
	begin_dress();layout.dress(self);finish_dress()
	flush_details()
	flush_rail_guards()
	set_owners(arena,arena)
	# MapNature and the layout point back at the builder; break the cycle so all free.
	nature.builder=null;layout=null
	return arena

func ground_splat(x: float, z: float, noise: FastNoiseLite) -> Color:
	return layout.ground_splat(self,x,z,noise)

# Shared compact objectives (MapLayout.objectives calls this by default).
func objectives() -> void:
	for x in [-28,-12,12,28]:
		for z in [-18,18]:
			var p:=Vector3(x,0,z);def.ammo_caches.append(p)
			box("AmmoCase",p+Vector3(0,.35,0),Vector3(1.1,.7,.65),Color("59644d"))
			sign_text("SUPPLIES",p+Vector3(0,.42,.333),0,Color("c9d9c5"),15)
	for z in [-25,0,25]:
		for x in [-32,-19,0,19,32]:def.routes.append(Vector3(x,.05,z))
	for x in [-24,0,24]:def.domination.append(Vector3(x,0,0))
	def.hardpoints.assign([Vector3(-26,0,-23),Vector3(0,0,0),Vector3(26,0,23),Vector3(-20,0,26),Vector3(20,0,-25)])
	def.qa_route.assign([Vector3(-43,0,-17),Vector3(-29,0,-25),Vector3(-19,0,-34),Vector3(-19,3.2,-17),Vector3(0,3.2,-17),Vector3(19,3.2,-17),Vector3(29,0,23),Vector3(0,0,0),Vector3(0,0,29),Vector3(-43,0,17)])

func boundaries() -> void:
	var half:=def.extent*.5
	# The side walls run through the corners; the north and south walls butt against their inner
	# faces, so no two walls overlap (no coplanar tops) and every corner is closed.
	for side in [-1,1]:
		box("BoundaryWall",Vector3(side*half.x,2,0),Vector3(.5,4,def.extent.y+.5),stone)
		box("BoundaryWall",Vector3(0,2,side*half.y),Vector3(def.extent.x-.5,4,.5),stone)
		coping_run(Vector3(side*half.x,4.07,0),Vector3(.65,.14,def.extent.y+.65),true)
		coping_run(Vector3(0,4.07,side*half.y),Vector3(def.extent.x-.65,.14,.65),false)
		# A continuous facade gives the playable facility a surrounding context.
		for x in [-38,-12,14,40]:
			var center:=Vector3(x,0,side*(half.y+9))
			box("ContextWarehouse",center+Vector3(0,5,0),Vector3(22,10,12),Color("9b9d99"),false)
			for level in [3.5,7.5]:
				for offset in [-7,-2,3,8]:context_window(center+Vector3(offset,level,-side*6.0),-side)

# A perimeter wall's coping: slabs of at most 6 m tiling the whole run (`along_z` says which way it
# runs) so the cap neither stops short of the corners nor leaves gaps.
func coping_run(center:Vector3, size:Vector3, along_z:bool) -> void:
	var length:=size.z if along_z else size.x
	var count:=ceili(length/6.0)
	var piece:=length/count
	for i in count:
		var offset:=-length*.5+piece*(i+.5)
		var slab_size:=Vector3(size.x,size.y,piece) if along_z else Vector3(piece,size.y,size.z)
		detail(center+(Vector3(0,0,offset) if along_z else Vector3(offset,0,0)),slab_size,dark)

# A window in a context building: frame (sill, head, jambs) around the pane, face = the wall's
# outward direction along z.
func context_window(wall_point:Vector3, face:int) -> void:
	box("WindowGlass",wall_point+Vector3(0,0,face*.05),Vector3(2.6,1.45,.08),dark,false)
	var frame:=Color("55595a")
	for sy in [-1,1]:detail(wall_point+Vector3(0,sy*(1.45*.5+.04),face*.06),Vector3(2.76,.08,.14),frame)
	for sx in [-1,1]:detail(wall_point+Vector3(sx*(2.6*.5+.04),0,face*.06),Vector3(.08,1.45,.14),frame)

func deployment() -> void:
	for team in 2:
		var side:=-1.0 if team==0 else 1.0
		for row in 4:
			for col in 4:
				var p:=Vector3(side*(def.extent.x*.5-6-col*2),.05,[-26,-5,5,26][row])
				(def.spawns_blue if team==0 else def.spawns_red).append(p)
		modern_building(Vector3(side*(def.extent.x*.5-11),0,0),Vector2(12,20),3.6,"CREW / RECEIVING" if team==0 else "SECURITY / SERVICE")
		for z in [-22,22]:
			sign_text("DELIVERY  /  01" if team==0 else "SERVICE  /  02",Vector3(side*(def.extent.x*.5-17.18),2.85,signf(z)*6),PI*.5 if team==0 else -PI*.5,accent,25)
		for z in [-8,8]:
			cover(Vector3(side*32,0,z),2.8,Color("6d777c"))

func glass_material() -> StandardMaterial3D:
	if not materials.has("clear_glass"):
		# Clear float glass: mostly transparent, with real reflections at grazing angles.
		# Back faces are culled (each pane is a thin box, so one face per side still
		# shows) and the glass doesn't receive shadows: layered alpha panes running
		# soft-shadow lighting cost up to 16 ms of GPU when looking through buildings.
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.22,.28,.3,.3);mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness=.05;mat.metallic=.15;mat.metallic_specular=.9;mat.disable_receive_shadows=true
		materials["clear_glass"]=mat
	return materials["clear_glass"]

# Wall thickness and corner pilaster width of a modern_building (m).
const WALL := .3
const PILASTER := .4
# Width of the steel architrave around a doorway and of a window's frame members.
const SURROUND := .14
const FRAME := .07
# Trim covers the reveal instead of sharing its plane.
const REVEAL_LIP := .03
# Label3D pixel size used by sign_text.
const TEXT_PIXEL := .012

func modern_building(center:Vector3, size:Vector2, height:float, title:String, industrial:=false) -> void:
	footprints.append(Rect2(center.x-size.x*.5,center.z-size.y*.5,size.x,size.y))
	buildings.append({"center":center,"size":size,"height":height,"furnished":not industrial,"door":2.9,"wall":WALL})
	for side in [-1,1]:
		for reach in [1.5,4.0]:avoid.append_array([center+Vector3(side*(size.x*.5+reach),0,0),center+Vector3(0,0,side*(size.y*.5+reach))])
	for side in [-1,1]:
		box("Pavement",center+Vector3(0,.05,side*(size.y*.5+.75)),Vector3(size.x+3,.1,1.5),Color("c7c9c3"))
		box("Pavement",center+Vector3(side*(size.x*.5+.75),.05,0),Vector3(1.5,.1,size.y),Color("c7c9c3"))
	var door:=4.0
	var lintels:=[door+SURROUND*2.0,door+SURROUND*2.0]
	buildings.back()["lintel"]=lintels
	var fill:=Color("9ca4a6") if industrial else Color("c7cdcb")
	# Corner pilasters close each corner exactly: the four walls end on their inner faces, so no
	# wall overlaps another (no coplanar tops) and no corner is left open.
	for sx in [-1,1]:
		for sz in [-1,1]:
			box("CornerPost",center+Vector3(sx*size.x*.5,height*.5,sz*size.y*.5),Vector3(PILASTER,height,PILASTER),Color("b7bcb9"))
	# Walls, glazing and doorways; axis 0 runs along X, axis 1 along Z.
	for axis in 2:
		var length:float=(size.x if axis==0 else size.y)-PILASTER
		var depth:float=size.y if axis==0 else size.x
		var turn:=Basis(Vector3.UP,PI*.5*axis)
		var span:=(length-door)*.5
		for side in [-1.0,1.0]:
			for segment in [-1.0,1.0]:
				var local:=Vector3(segment*(length+door)*.25,0,side*depth*.5)
				var root:=Node3D.new();region.add_child(root);root.position=center;root.rotation.y=PI*.5*axis
				box("Sill",local+Vector3.UP*.5,Vector3(span,1,WALL),stone,true,root)
				box("Cladding",local+Vector3.UP*(height+2.5)*.5,Vector3(span,height-2.5,WALL),fill,true,root)
				# The opening runs from the doorway architrave to the corner pilaster.
				var opening:=span-SURROUND
				var middle:=Vector3(local.x+segment*SURROUND*.5,0,local.z)
				window_bay(center,turn,middle,opening,root)
			# Entrance lintel; on the long facades it is widened into a sign band that carries the name.
			var lintel_width:=door+SURROUND*2.0
			var font:=0
			if axis==0:
				font=56 if height>=5.0 else 34
				lintel_width=clampf(text_em(title)*TEXT_PIXEL*font+1.0,lintel_width,length-2.0)
				font=fit_font(title,lintel_width-1.0,height-3.3,font)
			lintels[axis]=lintel_width
			# Trim extends into the opening and stands proud of both wall faces;
			# a flush inner face also competes with the wall when viewed indoors.
			var lintel_local:=Vector3(0,(height+2.9-REVEAL_LIP)*.5,side*(depth*.5+.03))
			var lintel:=box("EntranceLintel",center+turn*lintel_local,Vector3(lintel_width,height-2.9+REVEAL_LIP,WALL+.10),Color("b7bcb9"))
			lintel.rotation.y=PI*.5*axis
			if axis==0:sign_text(title,center+turn*Vector3(0,(height+2.9)*.5,side*(depth*.5+WALL*.5+.08+.01)),0 if side==1 else PI,Color("111517"),font)
			# Steel architrave: two jambs, flush with the lintel above them.
			for end in [-1.0,1.0]:
				detail(center+turn*Vector3(end*(door*.5+SURROUND*.5-REVEAL_LIP),(2.9-REVEAL_LIP)*.5,side*(depth*.5+.03)),Vector3(SURROUND,2.9-REVEAL_LIP,WALL+.10),dark,"steel",Vector3(0,PI*.5*axis,0))
	box("Roof",center+Vector3.UP*(height+.16),Vector3(size.x+.5,.32,size.y+.5),Color("626c70"))
	box("InteriorSlab",center+Vector3.UP*.015,Vector3(size.x,.03,size.y),Color("d2d0c7"),false)
	# Eaves gutters sit tight against the end walls between the corner pilasters, downpipes hug the wall.
	for side in [-1,1]:
		var gutter_x:float=side*(size.x*.5+WALL*.5+.07)
		detail(center+Vector3(gutter_x,height-.1,0),Vector3(.14,.12,size.y-PILASTER),dark,"steel")
		for z in [-1,1]:
			var pipe_z:float=z*(size.y*.5-PILASTER*.5-.3)
			cylinder(center+Vector3(side*(size.x*.5+WALL*.5+.055),(height-.16)*.5,pipe_z),.055,height-.16,metal)
			for y in [.4,height*.5,height-.45]:detail(center+Vector3(side*(size.x*.5+WALL*.5+.03),y,pipe_z),Vector3(.06,.05,.12),dark,"steel")
	if not industrial:
		for side in [-1,1]:
			prop("metal_office_desk",center+Vector3(side*(size.x*.5-1.7),0,side*(size.y*.5-2)),.76,0 if side<0 else PI)
		prop("potted_plant_02",center+Vector3(size.x*.5-1.2,0,-size.y*.5+1.2),1.35)
	# Rooftop ventilators, each on a curb so no face is shared with the roof deck.
	for x in [-size.x*.35,size.x*.35]:
		box("Ventilation",center+Vector3(x,height+.72,0),Vector3(1.9,1.1,1.4),Color("afb1ac"),false)
		for i in 8:detail(center+Vector3(x-.72+i*.2,height+1.29,0),Vector3(.07,.03,1.15),dark)
	interior_lighting(center,size,height)

# One window between sill (y 1.0) and cladding (y 2.5) in a wall segment: a stone stool, a steel
# frame (head, foot, jambs, a glazing bar and mullions) and the glass pane set inside it, so the pane
# has no free edge. `middle` is the opening's centre on the wall's centre line (root's local frame).
func window_bay(center:Vector3, turn:Basis, middle:Vector3, width:float, root:Node3D) -> void:
	var rotate:=Vector3(0,turn.get_euler().y,0)
	var inner:=width-FRAME*2.0
	var origin:=center+turn*Vector3(middle.x,0,middle.z)
	# Projecting stool that sheds water off the sill, then the frame: foot, head, jambs, glazing bar.
	detail(origin+turn*Vector3(0,1.025,0),Vector3(width,.05,WALL+.12),stone,"concrete",rotate)
	detail(origin+turn*Vector3(0,1.085,0),Vector3(width,.07,.16),dark,"steel",rotate)
	detail(origin+turn*Vector3(0,2.465,0),Vector3(width,.07,.16),dark,"steel",rotate)
	for end in [-1.0,1.0]:detail(origin+turn*Vector3(end*(width-FRAME)*.5,1.775,0),Vector3(FRAME,1.31,.16),dark,"steel",rotate)
	detail(origin+turn*Vector3(0,1.775,0),Vector3(inner,.04,.1),dark,"steel",rotate)
	var panes:=maxi(1,roundi(inner/1.4))
	for k in range(1,panes):detail(origin+turn*Vector3(-inner*.5+inner*k/panes,1.775,0),Vector3(.045,1.31,.12),dark,"steel",rotate)
	var glass:=box("WindowGlass",Vector3(middle.x,1.775,middle.z),Vector3(inner,1.31,.08),dark,true,root)
	glass.get_child(0).material_override=glass_material()

# Rough width of a line of capitals in the default sans font, in ems (per-character advances).
static func text_em(text:String) -> float:
	var total:=0.0
	for character in text:
		if character==" ":total+=.28
		elif character in "/|-.,":total+=.36
		elif character in "IJ1":total+=.4
		elif character in "MW":total+=.95
		else:total+=.66
	return total

# The largest font size (up to `wanted`) whose line fits a plate of width x height metres.
func fit_font(text:String, width:float, height:float, wanted:int) -> int:
	var by_width:=width/(text_em(text)*TEXT_PIXEL)
	var by_height:=height/(TEXT_PIXEL*1.1)
	return maxi(8,int(minf(float(wanted),minf(by_width,by_height))))

# A Poly Haven prop normalised to a physical height; solid props get a box
# collider around their bounds (they act as cover like any wall).
func prop(id:String, position:Vector3, height:float, yaw:=0.0, solid:=true) -> void:
	var scale:=height/maxf(props.bounds(id).size.y,.01)
	props.place(id,props.grounded(id,position,yaw,scale),solid,120.0)

func freight(center:Vector3,color:Color) -> void:
	box("Freight",center+Vector3(0,1.295,0),Vector3(6.05,2.59,2.44),color)
	var frame:=color.darkened(.35)
	# Frame members stand proud of the skin by at least 1 cm on every face (castings by 2 cm), so no
	# face of a detail shares a plane with the body or with another member.
	for sx in [-1,1]:
		for sz in [-1,1]:
			detail(center+Vector3(sx*2.95,1.295,sz*1.145),Vector3(.15,2.612,.15),frame)
			for y in [.095,2.495]:detail(center+Vector3(sx*2.945,y,sz*1.14),Vector3(.19,.19,.19),Color("4a4d4f"))
		for y in [.09,2.50]:
			detail(center+Vector3(0,y,sx*1.245),Vector3(5.7,.1,.05),dark)
			detail(center+Vector3(sx*3.04,y,0),Vector3(.05,.1,2.1),dark)
	# Cargo doors: seam, locking bars with keepers and handles.
	detail(center+Vector3(3.04,1.3,0),Vector3(.03,2.35,.035),Color("1e2224"))
	for z in [-.92,-.32,.32,.92]:
		detail(center+Vector3(3.07,1.3,z),Vector3(.045,2.3,.045),Color("8b8e88"))
		for y in [.28,2.33]:detail(center+Vector3(3.08,y,z),Vector3(.07,.1,.1),Color("6c6f6b"))
		detail(center+Vector3(3.12,1.05,z+(.12 if z<0 else -.12)),Vector3(.045,.045,.26),Color("8b8e88"))

# A guard rail along a path of deck points (deck surface height): regularly spaced posts, a top
# rail at `height`, a mid rail and a toe board. Posts stand at both ends and at every bend;
# rails butt against those posts instead of overlapping. With `solid`, each run also gets a
# thin collider on the Characters layer: soldiers cannot walk through or off it, while bullets,
# sight lines and the navigation bake (all World-layer only) pass the open railing.
func railing_path(points:Array, height:=1.05, color:=Color("2a3033"), pitch:=1.5, solid:=true) -> void:
	for index in points.size():
		var here:Vector3=points[index]
		# End and corner posts rise to the rail height; the rails stop against their sides.
		detail(here+Vector3(0,height*.5,0),Vector3(.07,height,.07),color,"steel")
		if index==points.size()-1:break
		var there:Vector3=points[index+1]
		var run:=there-here;var length:=run.length();var along:=run/length
		var yaw:=Vector3(0,atan2(-along.z,along.x),0)
		var net:=length-.07
		var middle:=(here+there)*.5
		# Intermediate posts, evenly spaced; they stop under the top rail.
		var bays:=maxi(1,ceili(length/pitch-.001))
		for k in range(1,bays):detail(here+along*length*k/bays+Vector3(0,(height-.04)*.5,0),Vector3(.06,height-.04,.06),color,"steel")
		detail(middle+Vector3(0,height-.02,0),Vector3(net,.04,.04),color,"steel",yaw)
		detail(middle+Vector3(0,height*.5,0),Vector3(net,.035,.035),color,"steel",yaw)
		detail(middle+Vector3(0,.07,0),Vector3(net,.1,.09),color,"steel",yaw)
		if solid:rail_guards.append([Transform3D(Basis.from_euler(yaw),middle+Vector3(0,(height+.05)*.5,0)),Vector3(length+.07,height+.05,.12)])

# Railing colliders are added after everything else, so the rest of the map keeps its node
# names and order (and with them the dressing, physics and saved scene) exactly as before.
var rail_guards:Array=[]
func flush_rail_guards() -> void:
	for index in rail_guards.size():
		var guard:=StaticBody3D.new();guard.name="RailGuard"+str(index)
		guard.collision_layer=2;guard.collision_mask=0;guard.set_meta("surface","metal")
		var shape:=CollisionShape3D.new();var volume:=BoxShape3D.new();volume.size=rail_guards[index][1];shape.shape=volume
		guard.add_child(shape);guard.transform=rail_guards[index][0];region.add_child(guard)
	rail_guards.clear()

func bridge() -> void:
	box("Gantry",Vector3(0,3.05,-17),Vector3(42,.3,3.6),metal)
	# The deck (Gantry) spans z -18.8..-15.2, so each ramp must meet its near edge at deck height; ending
	# it at the centre line left a 32 cm lip at the top that players could not climb.
	for x in [-19,19]:ramp(Vector3(x,0,-35),Vector3(x,3.2,-18.8),3.6)
	# Guard rails inset from the deck edge: the near edge between the two ramp heads, and the far
	# edge returning round both deck ends.
	var near:=-17.0-1.74;var far:=-17.0+1.74
	railing_path([Vector3(-17.1,3.2,near),Vector3(17.1,3.2,near)])
	railing_path([Vector3(-20.95,3.2,near),Vector3(-20.95,3.2,far),Vector3(20.95,3.2,far),Vector3(20.95,3.2,near)])
	for x in [-14,14]:box("GantryColumn",Vector3(x,1.5,-17),Vector3(.18,3,.18),dark)
	# This is a pipe-service rack between the power rooms, with a real purpose: flanged at both ends
	# and clamped to the deck underside by hangers.
	for z in [-17.6,-17,-16.4]:
		var pipe:=cylinder(Vector3(0,2.55,z),.14,41.9,metal);pipe.rotation.z=PI*.5
		for end in [-1,1]:
			var flange:=cylinder(Vector3(end*20.96,2.55,z),.2,.05,dark);flange.rotation.z=PI*.5
	for x in [-14,-7,0,7,14]:
		detail(Vector3(x,2.76,-17),Vector3(.1,.28,1.9),dark)

func road_markings() -> void:
	for x in range(-28,29,7):
		for z in [-40,40]:detail(Vector3(x,.018,z),Vector3(3,.022,.1),Color("c9b577"),"concrete")
	for side in [-1,1]:
		for x in [-30,30]:
			for z in range(-13,14,3):detail(Vector3(x,.018,z),Vector3(.1,.022,1.6),Color("c9b577"),"concrete")

# --- Realism dressing ---------------------------------------------------------
# Helpers for MapLayout.dress(): furniture, clutter, decals, trim. Everything
# that blocks movement gets a collider, is tested against the colliders already
# in the map (clear) and stays off every gameplay marker and doorway lane.

var dress_solids: Array[AABB] = []
var dress_points: Array[Vector3] = []
var dress_cones: Array[Transform3D] = []

func begin_dress() -> void:
	dress_solids=collider_bounds()
	dress_points=markers();dress_points.append_array(avoid)
	decal_fade=34.0

func finish_dress() -> void:
	props.flush(arena,55.0)
	flush_cones()
	decal_fade=55.0

# Half extents on the ground of a width x depth footprint turned by yaw.
func footprint_half(width: float, depth: float, yaw: float) -> Vector2:
	var s:=absf(sin(yaw));var c:=absf(cos(yaw))
	return Vector2(width*.5*c+depth*.5*s,width*.5*s+depth*.5*c)

# True when a footprint is clear of every collider by `clearance` and of every
# gameplay marker by `gap` (works inside buildings too).
func clear(center: Vector3, half: Vector2, clearance := .3, gap := 1.0) -> bool:
	var area:=AABB(Vector3(center.x-half.x-clearance,center.y+.08,center.z-half.y-clearance),Vector3((half.x+clearance)*2,2.0,(half.y+clearance)*2))
	for solid in dress_solids:
		if solid.intersects(area):return false
	for point in dress_points:
		if absf(point.y-center.y)<3 and Vector2(point.x-center.x,point.z-center.z).length()<gap+maxf(half.x,half.y):return false
	return true

func claim(center: Vector3, half: Vector2, height: float) -> void:
	dress_solids.append(AABB(Vector3(center.x-half.x,center.y,center.z-half.y),Vector3(half.x*2,height,half.y*2)))

# Collision without a visual (the look comes from batched details).
func collider(center: Vector3, size: Vector3, surface := "metal") -> void:
	var body:=StaticBody3D.new();body.name="Solid"+str(serial);serial+=1
	body.collision_layer=1;body.collision_mask=0;body.set_meta("surface",surface)
	var shape:=CollisionShape3D.new();var volume:=BoxShape3D.new();volume.size=size;shape.shape=volume
	body.add_child(shape);body.position=center;region.add_child(body)

# A Poly Haven prop with a collider, placed only where it fits.
func solid_prop(id: String, position: Vector3, height: float, yaw := 0.0, clearance := .2, gap := 1.0) -> bool:
	var box:=props.bounds(id);var scale:=height/maxf(box.size.y,.01)
	var half:=footprint_half(box.size.x*scale,box.size.z*scale,yaw)
	if not clear(position,half,clearance,gap):return false
	props.place(id,props.grounded(id,position,yaw,scale),true,60.0)
	claim(position,half,height)
	return true

# Visual-only prop in a shared MultiMesh; placed on top of something or in a
# free spot (check = true tests the spot against colliders).
func small_prop(id: String, position: Vector3, height: float, yaw := 0.0, check := false) -> bool:
	var box:=props.bounds(id);var scale:=height/maxf(box.size.y,.01)
	if check and not clear(position,footprint_half(box.size.x*scale,box.size.z*scale,yaw),.05,.8):return false
	props.scatter(id,props.grounded(id,position,yaw,scale))
	return true

func bake_light(position: Vector3, color: Color, energy: float, reach: float) -> void:
	var lamp:=OmniLight3D.new();lamp.name="AccentLight"+str(serial);serial+=1
	lamp.position=position;lamp.light_color=color;lamp.light_energy=energy;lamp.light_indirect_energy=1.2
	lamp.omni_range=reach;lamp.omni_attenuation=1.4;lamp.shadow_enabled=true;lamp.light_size=.3
	lamp.light_bake_mode=Light3D.BAKE_STATIC
	region.add_child(lamp)

# A straight pipe, duct or conduit between two points (no collision).
func pipe(from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var run:=cylinder((from+to)*.5,radius,from.distance_to(to),color)
	run.basis=Basis(Quaternion(Vector3.UP,(to-from).normalized()))

# Slots along the inside of a building's walls, doorway lanes left out. Each
# has the wall face point, the inward direction and the yaw that faces inward.
func wall_slots(data: Dictionary, pitch: float, margin := .8, door := 3.2) -> Array[Dictionary]:
	var slots:Array[Dictionary]=[]
	var center:Vector3=data.center;var size:Vector2=data.size;var thick:=float(data.get("wall",.3))
	for inward in [Vector3(0,0,1),Vector3(0,0,-1),Vector3(1,0,0),Vector3(-1,0,0)]:
		var tangent:=Vector3(inward.z,0,-inward.x)
		var along:=size.x if absf(inward.z)>.5 else size.y
		var depth:=size.y if absf(inward.z)>.5 else size.x
		var face:Vector3=center-inward*(depth*.5-thick*.5)
		var s:=-along*.5+margin+pitch*.5
		while s<=along*.5-margin-pitch*.5+.001:
			if absf(s)>door*.5+pitch*.5:slots.append({"face":face+tangent*s,"inward":inward,"tangent":tangent,"yaw":atan2(inward.x,inward.z)})
			s+=pitch
	return slots

const CARDBOARD := [Vector3(.42,.3,.32),Vector3(.32,.26,.3),Vector3(.5,.34,.36)]
const CARTON_COLORS := [Color("a88a62"),Color("9b7f58"),Color("b59a73")]
const CRATE_COLORS := [Color("2f5d8a"),Color("6e7478"),Color("b0832c")]

# One shelf bay: steel uprights, four boards and goods (cartons, crates, cans)
# lying on them. Solid, against a wall or free standing.
func shelf_unit(base: Vector3, yaw: float, width := 2.0, height := 2.0, depth := .5, frame := Color("3a5a70"), stocked := true, levels := 4) -> bool:
	var half:=footprint_half(width,depth,yaw)
	if not clear(base,half,.0,.9):return false
	var turn:=Basis(Vector3.UP,yaw);var rotate:=Vector3(0,yaw,0)
	for sx in [-1,1]:
		for sz in [-1,1]:detail(base+turn*Vector3(sx*(width*.5-.03),height*.5,sz*(depth*.5-.03)),Vector3(.05,height,.05),frame,"steel",rotate,50.0)
	var gap:=(height-.35)/float(levels-1)
	for level in levels:
		var y:=.15+level*gap
		detail(base+turn*Vector3(0,y,0),Vector3(width-.04,.035,depth-.02),Color("8a9296"),"steel",rotate,50.0)
		if not stocked or level==levels-1 and rng.randf()<.5:continue
		var x:=-width*.5+.12
		while x<width*.5-.35:
			var kind:=rng.randi()%3
			if kind==2 and gap<.4:kind=0
			var size:Vector3=CARDBOARD[rng.randi()%CARDBOARD.size()]
			var color:Color=CARTON_COLORS[rng.randi()%CARTON_COLORS.size()]
			if kind==1:
				size=Vector3(.46,.24,.34);color=CRATE_COLORS[rng.randi()%CRATE_COLORS.size()]
			elif kind==2:
				size=Vector3(.34,.34,.34);color=Color("3d4a3a")
			if size.y>gap-.1:size.y=gap-.1
			var finish:="concrete" if kind==0 else "steel"
			detail(base+turn*Vector3(x+size.x*.5,y+.0175+size.y*.5,rng.randf_range(-.04,.04)),size,color,finish,rotate,50.0)
			if rng.randf()<.25 and size.y*2.0<gap-.05:detail(base+turn*Vector3(x+size.x*.5,y+.0175+size.y*1.5,0),size,color,finish,rotate,50.0)
			x+=size.x+rng.randf_range(.03,.16)
	collider(base+Vector3(0,height*.5,0),Vector3(half.x*2,height,half.y*2))
	claim(base,half,height)
	return true

# A wooden pallet with a stacked load of cartons (a low block of cover when
# stack > 1: kept against walls by the layouts).
func pallet(base: Vector3, yaw: float, stack := 2, solid := true) -> bool:
	var half:=footprint_half(1.2,.8,yaw)
	if not clear(base,half,.0,.9):return false
	var root:=box("PalletBoard",base+Vector3(0,.075,0),Vector3(1.2,.15,.8),Color("8b7a5b"),false);root.rotation.y=yaw
	var turn:=Basis(Vector3.UP,yaw);var rotate:=Vector3(0,yaw,0)
	var top:=.15
	for level in stack:
		var color:Color=CARTON_COLORS[(level+rng.randi())%CARTON_COLORS.size()]
		for cx in [-.29,.29]:
			for cz in [-.19,.19]:
				detail(base+turn*Vector3(cx,top+.17,cz),Vector3(.56,.34,.38),color,"concrete",rotate,55.0)
		top+=.34
	if stack>=2:detail(base+turn*Vector3(0,top+.01,0),Vector3(1.0,.02,.74),Color("d8dad6"),"steel",rotate,55.0)
	if solid and stack>0:
		collider(base+Vector3(0,top*.5,0),Vector3(half.x*2,top,half.y*2),"wood")
		claim(base,half,top)
	return true

func cone(position: Vector3) -> void:
	dress_cones.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU),position))

func cone_mesh() -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var orange:=Color(.9,.3,.04);var white:=Color(.85,.85,.82)
	var rings:=[[.025,.15,orange],[.24,.078,orange],[.26,.072,white],[.40,.058,white],[.42,.056,orange],[.70,.012,orange]]
	var sides:=8
	for i in rings.size()-1:
		var lower:Array=rings[i];var upper:Array=rings[i+1]
		for k in sides:
			var a0:=TAU*k/sides;var a1:=TAU*(k+1)/sides
			var corners:=[Vector3(cos(a0)*lower[1],lower[0],sin(a0)*lower[1]),Vector3(cos(a1)*lower[1],lower[0],sin(a1)*lower[1]),Vector3(cos(a1)*upper[1],upper[0],sin(a1)*upper[1]),Vector3(cos(a0)*upper[1],upper[0],sin(a0)*upper[1])]
			for tri in [[0,1,2],[0,2,3]]:
				for index in tri:
					var p:Vector3=corners[index]
					st.set_color(lower[2]);st.set_normal(Vector3(p.x,.35*.1,p.z).normalized());st.add_vertex(p)
	# Square foot plate.
	var plate:=.17;var dark_plate:=Color(.05,.05,.05)
	for corners in [[Vector3(-plate,.025,-plate),Vector3(plate,.025,-plate),Vector3(plate,.025,plate),Vector3(-plate,.025,plate)]]:
		for tri in [[0,1,2],[0,2,3]]:
			for index in tri:
				st.set_color(dark_plate);st.set_normal(Vector3.UP);st.add_vertex(corners[index])
	return st.commit()

func flush_cones() -> void:
	if dress_cones.is_empty():return
	var mat:=StandardMaterial3D.new();mat.vertex_color_use_as_albedo=true;mat.roughness=.55;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var transforms:=PackedFloat32Array()
	for transform in dress_cones:transforms.append_array(MapArena.pack(transform))
	arena.instance_batches.append(["Cones",cone_mesh(),mat,transforms,GeometryInstance3D.GI_MODE_DYNAMIC,45.0,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])
	dress_cones.clear()

# Decals scattered on open ground or inside buildings (inside = true), kept
# clear of colliders' tops by the decal's own projection box.
func floor_decals(id: String, count: int, area: Rect2, size: Vector2, tint := Color.WHITE, inside := false) -> void:
	var placed:=0;var attempts:=0
	while placed<count and attempts<count*14:
		attempts+=1
		var point:=Vector3(rng.randf_range(area.position.x,area.end.x),0,rng.randf_range(area.position.y,area.end.y))
		if (footprint_distance(point.x,point.z)<.01)!=inside:continue
		decal(id,point,size*rng.randf_range(.75,1.25),Vector3.UP,rng.randf()*TAU,tint)
		placed+=1

# Leak and damp streaks on the inside faces of a building's walls.
func interior_streaks(data: Dictionary, per_wall := 2) -> void:
	var center:Vector3=data.center;var height:float=data.height;var thick:=float(data.get("wall",.3))
	for inward in [Vector3(0,0,1),Vector3(0,0,-1),Vector3(1,0,0),Vector3(-1,0,0)]:
		var tangent:=Vector3(inward.z,0,-inward.x)
		var along:float=data.size.x if absf(inward.z)>.5 else data.size.y
		var depth:float=data.size.y if absf(inward.z)>.5 else data.size.x
		var face:Vector3=center-inward*(depth*.5-thick*.5-.01)
		for i in per_wall:
			var s:=rng.randf_range(-along*.4,along*.4)
			if absf(s)<2.6:continue
			var id:String=["Leaking001","Leaking002","Leaking003","Leaking005"][rng.randi()%4]
			decal(id,face+tangent*s+Vector3(0,rng.randf_range(.5,height-1.2),0),Vector2(rng.randf_range(1.4,2.4),rng.randf_range(2.0,3.0)),inward,0,Color(.8,.78,.72,rng.randf_range(.55,.85)))

# Panel seams, a coping band under the roof and bollards at the doors: breaks up the flat
# prefab walls of every ground-level building. Everything stays clear of the architrave, the
# sign lintel and the corner pilasters (no shared planes, no ends in mid-air).
func building_trim() -> void:
	for data in buildings:
		var center:Vector3=data.center;var size:Vector2=data.size;var height:float=data.height
		if center.y>.5 or not data.has("lintel"):continue
		var seam:=Color("40484c");var pier:=Color("b7bcb9");var bollard:=Color("c99a22")
		for axis in 2:
			var length:float=(size.x if axis==0 else size.y)-PILASTER
			var depth:float=size.y if axis==0 else size.x
			var tangent:=Vector3(1,0,0) if axis==0 else Vector3(0,0,1)
			var rotate:=Vector3(0,0.0 if axis==0 else PI*.5,0)
			var lintel_half:float=float(data.lintel[axis])*.5
			for side in [-1.0,1.0]:
				var normal:=(Vector3(0,0,side) if axis==0 else Vector3(side,0,0))
				var face:=center+normal*(depth*.5+.17)
				# Cladding runs from the architrave to the corner pilaster.
				var start:=2.0+SURROUND;var stop:=length*.5
				for segment in [-1.0,1.0]:
					var middle:Vector3=face+tangent*segment*(start+stop)*.5
					detail(middle+Vector3(0,2.58,0),Vector3(stop-start-.1,.07,.06),seam,"steel",rotate,75.0)
					var band_start:=maxf(start,lintel_half+.05)
					detail(face+tangent*segment*(band_start+stop)*.5+Vector3(0,height-.14,0),Vector3(stop-band_start,.28,.1),pier,"concrete",rotate,90.0)
				var t:=-length*.5+1.4
				while t<length*.5-1.0:
					if absf(t)>maxf(lintel_half,2.0+SURROUND)+.4:detail(face+tangent*t+Vector3(0,(2.6+height-.3)*.5,0),Vector3(.035,height-2.9,.035),seam,"steel",rotate,60.0)
					t+=1.5
				for edge in [-1.0,1.0]:
					detail(face+normal*1.1+tangent*edge*2.9+Vector3(0,.5,0),Vector3(.18,1.0,.18),bollard,"steel",Vector3.ZERO,60.0)

# A low workbench (below the window sills, so sight lines are unchanged) with
# a vice, tool box and parts on top.
func bench(base: Vector3, yaw: float, width := 1.8, depth := .65) -> bool:
	var half:=footprint_half(width,depth,yaw)
	if not clear(base,half,.0,.9):return false
	var turn:=Basis(Vector3.UP,yaw);var rotate:=Vector3(0,yaw,0)
	var top:=box("Worktop",base+Vector3(0,.9,0),Vector3(width,.06,depth),metal,false);top.rotation.y=yaw
	var frame:=Color("3c4a52")
	for sx in [-1,1]:detail(base+turn*Vector3(sx*(width*.5-.04),.45,0),Vector3(.06,.9,depth-.08),frame,"steel",rotate,50.0)
	detail(base+turn*Vector3(0,.25,0),Vector3(width-.1,.04,depth-.1),frame,"steel",rotate,50.0)
	detail(base+turn*Vector3(-width*.3,.99,0),Vector3(.4,.14,.2),Color("a3281f"),"steel",rotate,50.0)
	detail(base+turn*Vector3(width*.05,.97,.05),Vector3(.3,.1,.22),Color("2f5d8a"),"steel",rotate,50.0)
	detail(base+turn*Vector3(width*.33,1.0,-.05),Vector3(.14,.16,.1),Color("2d3236"),"steel",rotate,50.0)
	for crate in 2:detail(base+turn*Vector3(-width*.1+crate*.5,.34,0),Vector3(.42,.2,.5),CRATE_COLORS[crate],"steel",rotate,50.0)
	collider(base+Vector3(0,.5,0),Vector3(half.x*2,1.0,half.y*2))
	claim(base,half,1.0)
	return true

# Lettering on a wall face (normal = outward from the wall into the room).
func wall_sign(text: String, position: Vector3, normal: Vector3, color := Color("e8e2cf"), size := 30) -> void:
	sign_text(text,position+normal*.02,atan2(normal.x,normal.z),color,size)

# Low furniture and clutter along the inside of a building's walls. Everything
# stays under the window sills (about 1 m), so sight lines through the glass and
# the doorway lanes are untouched. kinds: bench, pallet, cart, drum, crates, trash.
func low_clutter(data: Dictionary, kinds: Array, chance := .75, pitch := 2.2) -> void:
	var index:=0
	for slot in wall_slots(data,pitch):
		index+=1
		if rng.randf()>chance:continue
		var kind:String=kinds[(index+rng.randi())%kinds.size()]
		var face:Vector3=slot.face;var inward:Vector3=slot.inward;var yaw:float=slot.yaw
		match kind:
			"bench":bench(face+inward*.37,yaw)
			"pallet":pallet(face+inward*.46,yaw,2)
			"cart":solid_prop("tool_cart",face+inward*.45,.96,yaw,.0,.9)
			"drum":
				var spot:=face+inward*.55
				if clear(spot,Vector2(.5,.5),.0,.9):
					drum(spot);claim(spot,Vector2(.5,.5),1.24)
			"crates":
				var spot:=face+inward*.3
				if clear(spot,Vector2(.3,.3),.0,.8):
					for level in 3:small_prop("plastic_crate_02",spot+Vector3(0,level*.25,0),.25,yaw+rng.randf_range(-.1,.1))
					collider(spot+Vector3(0,.37,0),Vector3(.55,.75,.55),"metal");claim(spot,Vector2(.3,.3),.75)
			"trash":
				var spot:=face+inward*.3
				if clear(spot,Vector2(.35,.35),.0,.8):
					small_prop("trashbag",spot,.55,rng.randf()*TAU);small_prop("trashbag",spot+inward*.4+Vector3(.2,0,.1),.5,rng.randf()*TAU)

# Wires and ducts overhead: a tray with conduit between two points.
func tray(from: Vector3, to: Vector3, width := .4) -> void:
	var middle:=(from+to)*.5;var length:=from.distance_to(to)
	var along_x:=absf(to.x-from.x)>absf(to.z-from.z)
	var size:=Vector3(length,.05,width) if along_x else Vector3(width,.05,length)
	detail(middle,size,Color("6a7377"),"steel")
	for offset in [-.12,0.0,.12]:
		var shift:=Vector3(0,.05,offset) if along_x else Vector3(offset,.05,0)
		var color:=Color("1d2022") if offset==0.0 else Color("2c2f31")
		detail(middle+shift,Vector3(length,.035,.035) if along_x else Vector3(.035,.035,length),color,"steel")

# A free-standing equipment cabinet: collider, louvres and a latch, placed only where it fits.
func cabinet(base: Vector3, yaw: float, color := Color("5f6d73"), width := .9, height := 2.1, depth := .7) -> bool:
	var half:=footprint_half(width,depth,yaw)
	if not clear(base,half,.0,1.0):return false
	var root:=box("ServerCabinet",base+Vector3(0,height*.5,0),Vector3(width,height,depth),color);root.rotation.y=yaw
	var turn:=Basis(Vector3.UP,yaw);var rotate:=Vector3(0,yaw,0)
	for slot in 6:detail(base+turn*Vector3(0,height*.55+slot*.07,depth*.5+.01),Vector3(width*.7,.025,.02),Color("1c1f21"),"steel",rotate,50.0)
	detail(base+turn*Vector3(width*.4,1.05,depth*.5+.02),Vector3(.04,.18,.03),Color("d0d3d0"),"steel",rotate,50.0)
	claim(base,half,height)
	return true

# A stack of steel pipes or conduit bundles lying on timber bearers.
func pipe_stack(base: Vector3, yaw: float, length := 5.0) -> bool:
	var half:=footprint_half(length,1.0,yaw)
	if not clear(base,half,.2,1.0):return false
	var turn:=Basis(Vector3.UP,yaw)
	var rows:=[[0.0,3],[.3,2],[.6,1]]
	for row in rows:
		for k in int(row[1]):
			var offset:=(k-(int(row[1])-1)*.5)*.36
			var item:=cylinder(base+turn*Vector3(0,.19+float(row[0]),offset+0.0),.17,length,Color("6f7679") if rng.randi()%2==0 else Color("8a6a4a"))
			item.basis=turn*Basis(Vector3.BACK,PI*.5)
	for bearer in [-length*.35,length*.35]:
		detail(base+turn*Vector3(bearer,.04,0),Vector3(.12,.08,1.1),Color("7c6a50"),"steel",Vector3(0,yaw,0))
	collider(base+Vector3(0,.4,0),Vector3(half.x*2,.8,half.y*2))
	claim(base,half,.8)
	return true

# A timber cable drum on its side with wound cable.
func cable_reel(base: Vector3, yaw := 0.0) -> bool:
	var half:=footprint_half(.9,.9,yaw)
	if not clear(base,half,.2,1.0):return false
	var turn:=Basis(Vector3.UP,yaw)
	for end in [-1.0,1.0]:
		var disc:=cylinder(base+turn*Vector3(0,.45,end*.3),.45,.06,Color("8a6a46"))
		disc.basis=turn*Basis(Vector3.RIGHT,PI*.5)
	var core:=cylinder(base+turn*Vector3(0,.45,0),.27,.5,Color("171a1b"))
	core.basis=turn*Basis(Vector3.RIGHT,PI*.5)
	collider(base+Vector3(0,.45,0),Vector3(half.x*2,.9,half.y*2),"wood")
	claim(base,half,.9)
	return true
