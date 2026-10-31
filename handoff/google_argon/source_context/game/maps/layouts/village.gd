extends MapLayout

# Village: a partly overgrown Eastern-European farming village in summer. A
# cobbled main street (middle lane) crosses a small square between a church
# with a bell tower and the old village hall; two-storey plaster houses with
# stairs face the street. The north lane runs past an orchard, a graveyard and
# farm sheds, the south lane through fenced back gardens. Each team deploys
# from a timber barn and its farmyards at one end. The layout is point
# symmetric about the square (every authored piece at p has a twin at -p,
# turned half a circle), so both teams get the same cover.
#
# Everything village-specific (materials, walls with real openings, roofs,
# stairs, trees, fences, power lines) is built here from the shared mesh and
# surface helpers; the shared builder files stay untouched.

const TEX := "res://content/materials/"
const PROPS := "res://content/models/props/"
const PITCH := 0.70   # roof pitch, 40 degrees: too steep for navigation or walking
const STEP_RISE := 0.2
const STEP_GO := 0.475  # 23 degree flight: navigation climbs at most 0.25 m per 0.5 m cell
const FLOOR := 3.2    # upper floor level (walkable top of the slab)
const LEAVES := "res://content/materials/village_leaf/"  # generated leaf sprays (tools/generate_village_leaves.gd)
const LOD_SWITCH := 45.0  # trees swap to their light crowns beyond this (small on screen there)

var b: CompactMapBuilder
var mats := {}
var trims := {}       # material key -> {cell -> PackedFloat32Array} of scaled unit boxes
var foliage := {}     # mesh key -> {cell -> PackedFloat32Array}
var foliage_meshes := {}
var blocks: Array[Rect2] = []   # building footprints for the ground splat
var paths: Array = []           # [from, to, width] dirt paths for the ground splat
var trunks: Array[Vector3] = []
var bush_spots: Array[Transform3D] = []  # queued until every path is known, see place_bushes()
var grass := {}
var weeds: Array = []   # [id, position, yaw, scale], placed by place_weeds()
var tree_spots: Array = []   # [kind, position, scale, yaw], placed by place_trees()
var cables := SurfaceTool.new()

# --- Materials ----------------------------------------------------------------

func scan(id: String, size: float, grime := .6, res := "2k", tint := Color.WHITE, mix := 0.0, gain := 1.3) -> ShaderMaterial:
	var key:=id+str(size)+str(grime)+tint.to_html()+str(mix)
	if mats.has(key):return mats[key]
	var mat:=ShaderMaterial.new()
	mat.shader=preload("res://content/materials/surface.gdshader")
	var base:=TEX+id+"/"+id+"_%s_"+res+".jpg"
	mat.set_shader_parameter("albedo_tex",load(base%"diff"))
	mat.set_shader_parameter("normal_tex",load(base%"nor_gl"))
	mat.set_shader_parameter("arm_tex",load(base%"arm"))
	mat.set_shader_parameter("breakup_tex",load(MapSurfaces.BREAKUP))
	mat.set_shader_parameter("uv_scale",1.0/size)
	mat.set_shader_parameter("grime_amount",grime)
	if mix>0:
		mat.set_shader_parameter("tint",tint);mat.set_shader_parameter("tint_mix",mix);mat.set_shader_parameter("paint_gain",gain)
	mats[key]=mat
	return mat

# Smooth limewash for most houses; the worn plaster with brick showing
# through is kept for the poorest cottages.
func plaster(tint: Color, mix := .5) -> ShaderMaterial:
	return scan("painted_plaster_wall",2.0,.9,"2k",tint,mix,1.35)
func worn_plaster(tint: Color, mix := .5) -> ShaderMaterial:
	return scan("damaged_plaster",2.4,.85,"2k",tint,mix,1.25)
func stone() -> ShaderMaterial: return scan("old_stone_wall",2.0,.7)
func planks(tint := Color.WHITE, mix := 0.0, gain := 1.6) -> ShaderMaterial: return scan("weathered_brown_planks",1.8,.55,"2k",tint,mix,gain)
func floorboards() -> ShaderMaterial: return scan("old_wood_floor",3.0,.3)
func roof_red() -> ShaderMaterial: return scan("clay_roof_tiles_02",2.5,.2)
func roof_dark() -> ShaderMaterial: return scan("ceramic_roof_01",3.5,.2)
func straw() -> ShaderMaterial: return scan("reed_roof_03",1.6,.35,"1k",Color(1.0,.88,.6),.7,2.6)
func bark() -> ShaderMaterial: return scan("bark_brown_02",1.0,.3,"1k")
func clay() -> ShaderMaterial: return scan("patterned_clay_plaster",2.0,.8)

func trim_material(key: String) -> Material:
	match key:
		"white":return planks(Color(.86,.85,.8),.85,2.4)
		"green":return planks(Color(.34,.5,.38),.8,2.6)
		"blue":return planks(Color(.4,.53,.66),.8,2.6)
		"brown":return planks(Color(.36,.25,.17),.6)
		"wood":return planks()
		"stone":return stone()
		"tin":return b.surfaces.get_material("painted_metal",Color("5d6461"))
		"rust":return b.surfaces.get_material("rust")
		"black":return b.surfaces.get_material("painted_metal",Color("2b2e2d"))
		"porcelain":return b.surfaces.get_material("paint_concrete",Color("d9d6cc"))
		"cobble":return scan("cobblestone_floor_001",2.4,.3)
	return planks()

# --- Geometry helpers -----------------------------------------------------------

func block_mesh(size: Vector3, bevel := .02, grime := .8) -> ArrayMesh:
	var key:="vblock"+str(size)+str(bevel)+str(grime)
	if not b.meshes.has(key):
		var mesh:=MapMeshes.block(size,bevel,grime)
		mesh.lightmap_unwrap(Transform3D.IDENTITY,.35)
		b.meshes[key]=mesh
	return b.meshes[key]

func body(item: Node3D, shapes: Array, surface: String) -> void:
	var collider:=StaticBody3D.new();collider.collision_layer=1;collider.collision_mask=0
	collider.set_meta("surface",surface)
	for shape_data in shapes:
		var shape:=CollisionShape3D.new()
		if shape_data[1] is Shape3D:shape.shape=shape_data[1]
		else:
			var volume:=BoxShape3D.new();volume.size=shape_data[1];shape.shape=volume
		shape.transform=shape_data[0] if shape_data[0] is Transform3D else Transform3D(Basis.IDENTITY,shape_data[0])
		collider.add_child(shape)
	item.add_child(collider)

func occlude(item: Node3D, center: Vector3, size: Vector3) -> void:
	var occluder:=OccluderInstance3D.new();var volume:=BoxOccluder3D.new()
	volume.size=size*.98;occluder.occluder=volume;occluder.position=center;item.add_child(occluder)

func node(parent: Node3D, label: String, position: Vector3, rotation := Vector3.ZERO) -> Node3D:
	var item:=Node3D.new();item.name=label+str(b.serial);b.serial+=1
	parent.add_child(item);item.position=position;item.rotation=rotation
	return item

func visual(item: Node3D, mesh: Mesh, mat: Material, baked := true) -> MeshInstance3D:
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=mat
	instance.gi_mode=GeometryInstance3D.GI_MODE_STATIC if baked else GeometryInstance3D.GI_MODE_DYNAMIC
	item.add_child(instance)
	return instance

# A bevelled block with a scanned material; solid blocks collide and stop bullets.
func piece(parent: Node3D, label: String, center: Vector3, size: Vector3, mat: Material, solid := true, surface := "concrete", rotation := Vector3.ZERO, grime := .8, baked := true) -> Node3D:
	var item:=node(parent,label,center,rotation)
	visual(item,block_mesh(size,minf(.025,minf(size.x,minf(size.y,size.z))*.2),grime),mat,baked)
	if solid:
		body(item,[[Vector3.ZERO,size]],surface)
		if size.y>=3 and minf(size.x,size.z)>.4:occlude(item,Vector3.ZERO,size)
	return item

# Small repeated parts (frames, shutters, rails, pickets, insulators): scaled
# unit boxes batched into MultiMeshes per material and 24 m cell.
func trim(transform: Transform3D, size: Vector3, key: String) -> void:
	var placed:=Transform3D(transform.basis*Basis.from_scale(size),transform.origin)
	var cell:=str(Vector2i(floori(placed.origin.x/24),floori(placed.origin.z/24)))
	if not trims.has(key):trims[key]={}
	if not trims[key].has(cell):trims[key][cell]=PackedFloat32Array()
	trims[key][cell].append_array(MapArena.pack(placed))

func flush_trims() -> void:
	var unit:=MapMeshes.block(Vector3.ONE,0.0,0.0)
	for key in trims:
		for cell in trims[key]:
			b.arena.instance_batches.append(["VillageTrim_"+key+str(b.arena.instance_batches.size()),unit,trim_material(key),trims[key][cell],GeometryInstance3D.GI_MODE_DYNAMIC,110.0])
	trims.clear()

# A wall from a to c (on its base line, parent space) pierced by openings
# (Rect2: distance from a, height above the base, width, height). Outward is
# the wall's local +Z, i.e. to the right of a->c seen from above... the house
# builder walks its walls so that +Z always faces outside. Collision is split
# around every opening, so doors are walkable and windows can be shot through.
func wall(parent: Node3D, xf: Transform3D, a: Vector3, c: Vector3, height: float, thick: float, openings: Array, mat: Material, frames := "", surface := "concrete", baked := true, solid := true) -> void:
	var d:=c-a;var length:=Vector2(d.x,d.z).length()
	var item:=node(parent,"VillageWall",(a+c)*.5+Vector3.UP*height*.5,Vector3(0,atan2(-d.z,d.x),0))
	var key:="vwall"+str(Vector3(length,height,thick))+str(openings)
	if not b.meshes.has(key):
		var mesh:=MapMeshes.wall(Vector3(length,height,thick),openings,1.1)
		mesh.lightmap_unwrap(Transform3D.IDENTITY,.35)
		b.meshes[key]=mesh
	visual(item,b.meshes[key],mat,baked)
	if solid:
		var xs:Array[float]=[0.0,length]
		for rect:Rect2 in openings:xs.append_array([clampf(rect.position.x,0,length),clampf(rect.end.x,0,length)])
		xs.sort()
		var shapes:=[]
		for i in xs.size()-1:
			var x0:=xs[i];var x1:=xs[i+1]
			if x1-x0<.01:continue
			var gaps:Array[Rect2]=[]
			for rect:Rect2 in openings:
				if rect.position.x<=x0+.001 and rect.end.x>=x1-.001:gaps.append(rect)
			gaps.sort_custom(func(p:Rect2,q:Rect2):return p.position.y<q.position.y)
			var y:=0.0
			for gap in gaps:
				if gap.position.y-y>.01:shapes.append([Vector3((x0+x1)*.5-length*.5,(y+gap.position.y)*.5-height*.5,0),Vector3(x1-x0,gap.position.y-y,thick)])
				y=maxf(y,gap.end.y)
			if height-y>.01:shapes.append([Vector3((x0+x1)*.5-length*.5,(y+height)*.5-height*.5,0),Vector3(x1-x0,height-y,thick)])
			if gaps.is_empty() and height>=3 and x1-x0>=1.2:occlude(item,Vector3((x0+x1)*.5-length*.5,0,0),Vector3(x1-x0,height,thick))
		body(item,shapes,surface)
	if frames=="":return
	var wall_xf:=xf*item.transform
	for rect:Rect2 in openings:
		var mid:=Vector3(rect.position.x+rect.size.x*.5-length*.5,rect.position.y+rect.size.y*.5-height*.5,0)
		opening_frame(wall_xf,mid,rect.size,thick,frames,rect.position.y<.05)

# Painted timber frame, casement bars, sill and (some) open shutters around one
# opening; doors get a frame and a leaf standing open against the reveal.
func opening_frame(xf: Transform3D, mid: Vector3, size: Vector2, thick: float, paint: String, door: bool) -> void:
	var face:=thick*.5+.03
	var hx:=size.x*.5;var hy:=size.y*.5
	for side:float in [-1.0,1.0]:
		trim(xf*Transform3D(Basis.IDENTITY,mid+Vector3(side*(hx+.04),.0 if not door else .04,face)),Vector3(.1,size.y+(.16 if not door else .08),.07),paint)
	trim(xf*Transform3D(Basis.IDENTITY,mid+Vector3(0,hy+.05,face)),Vector3(size.x+.18,.1,.07),paint)
	var h:=b.rng.randf()
	if door:
		# Plank door leaf swung open inside, against the right-hand reveal.
		if h<.75:trim(xf*Transform3D(Basis(Vector3.UP,PI*.5),mid+Vector3(hx-.03,-.02,-thick*.5-size.x*.42)),Vector3(size.x*.82,size.y-.06,.05),"brown")
		return
	trim(xf*Transform3D(Basis.IDENTITY,mid+Vector3(0,-hy-.03,face+.03)),Vector3(size.x+.26,.06,.2),"stone" if h<.5 else paint)
	# Casement: frame inside the reveal, a mullion and a transom; no glass left.
	trim(xf*Transform3D(Basis.IDENTITY,mid+Vector3(0,0,thick*.15)),Vector3(.06,size.y,.06),paint)
	trim(xf*Transform3D(Basis.IDENTITY,mid+Vector3(0,hy*.35,thick*.15)),Vector3(size.x,.06,.06),paint)
	for side:float in [-1.0,1.0]:
		trim(xf*Transform3D(Basis.IDENTITY,mid+Vector3(side*(hx-.03),0,thick*.15)),Vector3(.06,size.y,.07),paint)
	for edge:float in [-1.0,1.0]:trim(xf*Transform3D(Basis.IDENTITY,mid+Vector3(0,edge*(hy-.03),thick*.15)),Vector3(size.x,.06,.07),paint)
	if h>.35:
		var swing:=b.rng.randf_range(.0,.5)
		for side:float in [-1.0,1.0]:
			if h>.85 and side>0:continue  # one shutter lost
			var hinge:=mid+Vector3(side*(hx+.1),0,face+.02)
			var leaf:=Basis(Vector3.UP,-side*swing)
			trim(xf*Transform3D(leaf,hinge+leaf*Vector3(side*hx*.5,0,.02)),Vector3(hx,size.y,.04),paint)

# Triangular gable (base on y=0, width along X, apex at y=rise), thickness along Z.
func gable_mesh(width: float, rise: float, thick: float) -> ArrayMesh:
	var key:="vgable"+str(Vector3(width,rise,thick))
	if b.meshes.has(key):return b.meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h:=width*.5;var t:=thick*.5
	var tri:=[Vector3(-h,0,0),Vector3(h,0,0),Vector3(0,rise,0)]
	for s:float in [-1.0,1.0]:
		var face:=[]
		for p:Vector3 in tri:face.append(p+Vector3(0,0,s*t))
		add_poly(st,face,Vector3(0,0,s),true)
	for i in 3:
		var p0:Vector3=tri[i];var p1:Vector3=tri[(i+1)%3]
		var out:=Vector3(p1.y-p0.y,-(p1.x-p0.x),0).normalized()
		if out.dot((p0+p1)*.5-Vector3(0,rise/3.0,0))<0:out=-out
		add_poly(st,[p0+Vector3(0,0,-t),p1+Vector3(0,0,-t),p1+Vector3(0,0,t),p0+Vector3(0,0,t)],out,false)
	st.index();st.generate_tangents()
	var mesh:=st.commit();mesh.lightmap_unwrap(Transform3D.IDENTITY,.35)
	b.meshes[key]=mesh
	return mesh

# Square pyramid (spire) of base half-width h and height rise, base at y=0.
func pyramid_mesh(h: float, rise: float) -> ArrayMesh:
	var key:="vpyramid"+str(Vector2(h,rise))
	if b.meshes.has(key):return b.meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var apex:=Vector3(0,rise,0)
	var corners:=[Vector3(-h,0,-h),Vector3(h,0,-h),Vector3(h,0,h),Vector3(-h,0,h)]
	for i in 4:
		var p0:Vector3=corners[i];var p1:Vector3=corners[(i+1)%4]
		var n:=(p1-p0).cross(apex-p0).normalized()
		if n.dot((p0+p1)*.5)<0:n=-n
		add_poly(st,[p0,p1,apex],n,false)
	st.index();st.generate_tangents()
	var mesh:=st.commit();mesh.lightmap_unwrap(Transform3D.IDENTITY,.3)
	b.meshes[key]=mesh
	return mesh

# Polygon with metric UVs (planar for walls, along-slope for sloped faces),
# white vertex colour (no grime), front face along n.
func add_poly(st: SurfaceTool, corners: Array, n: Vector3, flat: bool) -> void:
	var tris:=[[0,1,2]] if corners.size()==3 else [[0,1,2],[0,2,3]]
	var u_axis:=Vector3.UP.cross(n).normalized() if absf(n.y)<.95 else Vector3.RIGHT
	var v_axis:=n.cross(u_axis).normalized()
	for tri in tris:
		var p0:Vector3=corners[tri[0]];var p1:Vector3=corners[tri[1]];var p2:Vector3=corners[tri[2]]
		if (p1-p0).cross(p2-p0).dot(n)>0:var swap:=p1;p1=p2;p2=swap
		for p in [p0,p1,p2]:
			st.set_color(Color(1,1,1));st.set_normal(n)
			st.set_uv(Vector2(p.dot(u_axis),-p.dot(v_axis)) if not flat else Vector2(p.x if absf(n.z)>.5 else p.z,-p.y))
			st.add_vertex(p)

# Gable roof over a rectangle (local, ridge along X) whose walls end at eave.
func roof(parent: Node3D, size: Vector2, eave: float, thick: float, gable_mat: Material, roof_mat: Material, chimney := true, overhang := .55) -> void:
	var half:=size.y*.5
	var rise:=half*tan(PITCH)
	var length:=(half+overhang)/cos(PITCH)+.12
	for side:float in [-1.0,1.0]:
		var angle:=PITCH*side
		var n:=Vector3(0,cos(PITCH),side*sin(PITCH))
		# Bottom face runs from the wall top (z = side*half, y = eave) up to the ridge.
		var down:=Vector3(0,-sin(PITCH),side*cos(PITCH))
		var mid:=Vector3(0,eave+rise,0)+down*(length*.5-.12)+n*.12
		piece(parent,"VillageRoof",mid,Vector3(size.x+.7,.24,length),roof_mat,true,"concrete",Vector3(angle,0,0),0.0)
		# Timber boarding under the tiles where the attic is open.
		piece(parent,"VillageRafters",mid-n*.135,Vector3(size.x-.1,.03,length-.3),planks(),false,"wood",Vector3(angle,0,0),0.0)
	piece(parent,"VillageRidge",Vector3(0,eave+rise+.2,0),Vector3(size.x+.75,.18,.36),roof_mat,false,"concrete",Vector3.ZERO,0.0)
	for side:float in [-1.0,1.0]:
		var item:=node(parent,"VillageGable",Vector3(side*(size.x*.5-thick*.5),eave,0),Vector3(0,PI*.5,0))
		visual(item,gable_mesh(size.y,rise,thick),gable_mat)
		var hull:=ConvexPolygonShape3D.new()
		hull.points=PackedVector3Array([Vector3(-half,0,-thick*.5),Vector3(half,0,-thick*.5),Vector3(0,rise,-thick*.5),Vector3(-half,0,thick*.5),Vector3(half,0,thick*.5),Vector3(0,rise,thick*.5)])
		body(item,[[Vector3.ZERO,hull]],"concrete")
	if chimney:
		piece(parent,"VillageChimney",Vector3(size.x*.22,eave+rise*.75+.6,-.6),Vector3(.62,rise*.5+1.6,.62),plaster(Color(.8,.78,.74),.2),false,"concrete",Vector3.ZERO,.2)
		piece(parent,"VillageChimneyCap",Vector3(size.x*.22,eave+rise+1.05,-.6),Vector3(.78,.12,.78),stone(),false)

# --- Buildings --------------------------------------------------------------------

func house_xf(center: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP,yaw),center)

func footprint(center: Vector3, size: Vector2, yaw: float) -> void:
	var turned:=absf(sin(yaw))>.5
	var s:=Vector2(size.y,size.x) if turned else size
	blocks.append(Rect2(center.x-s.x*.5,center.z-s.y*.5,s.x,s.y))

# Openings on a house wall, measured from the wall's start (see walls below).
func openings_for(spec: Array, start: float, direction: float, floors: int) -> Array:
	var result:=[]
	for item in spec:
		var at:float=item[0];var kind:String=item[1]
		var off:=(at-start)*direction
		match kind:
			"door":result.append(Rect2(off-1.0,0,2.0,2.4))
			"wide":result.append(Rect2(off-1.2,0,2.4,2.6))
			"window":result.append(Rect2(off-.55,.95,1.1,1.3))
			"upper":result.append(Rect2(off-.55,FLOOR+.85,1.1,1.25))
			"both":
				result.append(Rect2(off-.55,.95,1.1,1.3))
				if floors>1:result.append(Rect2(off-.55,FLOOR+.85,1.1,1.25))
	return result

# A plaster house on a rubble-stone plinth: walls with real door and window
# openings, a timber floor, a gable roof. cfg: floors (1/2), stairs (bool),
# s/n/e/w opening lists ([along, kind]), wall, roof, paint, furniture.
func house(center: Vector3, size: Vector2, yaw: float, cfg: Dictionary) -> Node3D:
	var xf:=house_xf(center,yaw)
	var root:=node(b.region,"VillageHouse",center,Vector3(0,yaw,0))
	footprint(center,size,yaw)
	var floors:int=cfg.get("floors",2)
	var eave:=FLOOR*2-.2+.2 if floors>1 else 3.45
	var t:=.45
	var hx:=size.x*.5;var hz:=size.y*.5
	var mat:Material=cfg.get("wall",plaster(Color.WHITE,0.0))
	var paint:String=cfg.get("paint","white")
	var solid:bool=not cfg.get("context",false)
	# South (+z, front), east, north, west; +Z of every wall faces outside.
	wall(root,xf,Vector3(-hx,0,hz-t*.5),Vector3(hx,0,hz-t*.5),eave,t,openings_for(cfg.get("s",[]),-hx,1,floors),mat,paint,"concrete",true,solid)
	wall(root,xf,Vector3(hx,0,-hz+t*.5),Vector3(-hx,0,-hz+t*.5),eave,t,openings_for(cfg.get("n",[]),hx,-1,floors),mat,paint,"concrete",true,solid)
	wall(root,xf,Vector3(hx-t*.5,0,hz-t),Vector3(hx-t*.5,0,-hz+t),eave,t,openings_for(cfg.get("e",[]),hz-t,-1,floors),mat,paint,"concrete",true,solid)
	wall(root,xf,Vector3(-hx+t*.5,0,-hz+t),Vector3(-hx+t*.5,0,hz-t),eave,t,openings_for(cfg.get("w",[]),-hz+t,1,floors),mat,paint,"concrete",true,solid)
	plinth(root,xf,size,t,cfg)
	if floors>1:
		# String course between the storeys.
		for side:float in [-1.0,1.0]:
			trim(xf*Transform3D(Basis.IDENTITY,Vector3(0,FLOOR-.05,side*(hz+.02))),Vector3(size.x+.08,.12,.08),"stone")
			trim(xf*Transform3D(Basis.IDENTITY,Vector3(side*(hx+.02),FLOOR-.05,0)),Vector3(.08,.12,size.y),"stone")
	roof(root,size,eave,t,mat,cfg.get("roof",roof_red()),cfg.get("chimney",true))
	# Eaves gutters and a downpipe at each corner of the front.
	for side:float in [-1.0,1.0]:
		trim(xf*Transform3D(Basis.IDENTITY,Vector3(0,eave-.05,side*(hz+.62))),Vector3(size.x+.6,.12,.14),"tin")
		trim(xf*Transform3D(Basis.IDENTITY,Vector3(side*(hx-.15),eave*.5,hz+.08)),Vector3(.09,eave,.09),"tin")
	if not solid:return root
	var inner:=Vector2(size.x-t*2,size.y-t*2)
	piece(root,"VillageFloor",Vector3(0,.02,0),Vector3(inner.x,.04,inner.y),floorboards(),false,"wood",Vector3.ZERO,0.0)
	fill_light(xf*Vector3(0,(FLOOR if floors>1 else eave)-.7,0),maxf(inner.x,inner.y)*.8,1.1)
	if floors>1 and cfg.get("stairs",false):fill_light(xf*Vector3(0,eave+.6,0),maxf(inner.x,inner.y)*.8,1.0)
	if floors>1:
		if cfg.get("stairs",false):stairs(root,xf,inner,cfg)
		else:piece(root,"VillageCeiling",Vector3(0,FLOOR-.125,0),Vector3(inner.x,.25,inner.y),floorboards(),true,"wood",Vector3.ZERO,0.0)
	else:
		piece(root,"VillageCeiling",Vector3(0,eave-.125,0),Vector3(inner.x,.25,inner.y),floorboards(),true,"wood",Vector3.ZERO,0.0)
	var turned:=absf(sin(yaw))>.5
	var w:=inner.y if turned else inner.x;var d:=inner.x if turned else inner.y
	b.arena.probe_volumes.append(AABB(center-Vector3(w*.5,0,d*.5),Vector3(w,eave,d)))
	return root

# Rubble-stone plinth: a slightly proud band at the wall foot, broken at doors.
func plinth(root: Node3D, xf: Transform3D, size: Vector2, t: float, cfg: Dictionary) -> void:
	var hx:=size.x*.5;var hz:=size.y*.5
	var sides:=[["s",Vector3(0,0,hz+.03),Vector3(1,0,0),size.x,-hx,1.0],["n",Vector3(0,0,-hz-.03),Vector3(1,0,0),size.x,-hx,1.0],["e",Vector3(hx+.03,0,0),Vector3(0,0,1),size.y,-hz,1.0],["w",Vector3(-hx-.03,0,0),Vector3(0,0,1),size.y,-hz,1.0]]
	for side in sides:
		var cuts:Array[Vector2]=[]
		for item in cfg.get(side[0],[]):
			if item[1] in ["door","wide"]:
				var w:=1.0 if item[1]=="door" else 1.2
				cuts.append(Vector2(float(item[0])-w-.05,float(item[0])+w+.05))
		cuts.sort_custom(func(p:Vector2,q:Vector2):return p.x<q.x)
		var start:float=side[4];var finish:float=-start
		var spans:Array[Vector2]=[]
		var cursor:=start
		for cut in cuts:
			if cut.x>cursor+.1:spans.append(Vector2(cursor,cut.x))
			cursor=maxf(cursor,cut.y)
		if finish>cursor+.1:spans.append(Vector2(cursor,finish))
		var axis:Vector3=side[2]
		for span in spans:
			var mid:=(span.x+span.y)*.5;var length:=span.y-span.x
			var pos:Vector3=side[1]+axis*mid+Vector3.UP*.32
			var dims:=Vector3(length,.64,.12) if axis.x>.5 else Vector3(.12,.64,length)
			piece(root,"VillagePlinth",pos,dims,stone(),false,"concrete",Vector3.ZERO,.6)

# Masonry stairs along the north wall rising to the upper floor, the slab with
# its stairwell, and a balustrade round the well.
func stairs(root: Node3D, xf: Transform3D, inner: Vector2, cfg: Dictionary) -> void:
	var x0:=-inner.x*.5+1.2;var z0:=-inner.y*.5;var width:=2.4
	var run:=STEP_GO*16
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 16:
		var top:=(k+1)*STEP_RISE
		st.append_from(MapMeshes.block(Vector3(STEP_GO,top,width),.015,.6),0,Transform3D(Basis.IDENTITY,Vector3(x0+(k+.5)*STEP_GO,top*.5,z0+width*.5)))
	var mesh:=st.commit();mesh.lightmap_unwrap(Transform3D.IDENTITY,.3)
	var flight:=node(root,"VillageStairs",Vector3.ZERO)
	visual(flight,mesh,stone())
	# Walkable slope just above the nosings, from the floor to the landing.
	var a:=Vector3(x0-.19,0,z0+width*.5);var c:=Vector3(x0+run,FLOOR+.1,z0+width*.5)
	var along:=c-a;var slope:=atan2(along.y,along.x)
	var n:=Vector3(-sin(slope),cos(slope),0)
	body(flight,[[Transform3D(Basis(Vector3.BACK,slope),(a+c)*.5-n*.15),Vector3(along.length(),.3,width)]],"concrete")
	# Headroom: the slab opens where the flight is within 2 m of its underside.
	var hole0:=x0+1.0;var hole1:=x0+run
	var slab:=FLOOR-.125
	piece(root,"VillageSlab",Vector3((-inner.x*.5+hole0)*.5,slab,0),Vector3(hole0+inner.x*.5,.25,inner.y),floorboards(),true,"wood",Vector3.ZERO,0.0)
	piece(root,"VillageSlab",Vector3((hole0+hole1)*.5,slab,(z0+width+inner.y*.5)*.5),Vector3(hole1-hole0,.25,inner.y*.5-z0-width),floorboards(),true,"wood",Vector3.ZERO,0.0)
	piece(root,"VillageSlab",Vector3((hole1+inner.x*.5)*.5,slab,0),Vector3(inner.x*.5-hole1,.25,inner.y),floorboards(),true,"wood",Vector3.ZERO,0.0)
	# Balustrade round the well (solid: nobody steps off the upper floor into it).
	piece(root,"VillageBalustrade",Vector3((hole0+hole1)*.5,FLOOR+.5,z0+width+.04),Vector3(hole1-hole0,1.0,.08),planks(),true,"wood",Vector3.ZERO,0.0,false)
	piece(root,"VillageBalustrade",Vector3(hole0-.04,FLOOR+.5,z0+width*.5),Vector3(.08,1.0,width),planks(),true,"wood",Vector3.ZERO,0.0,false)
	for i in 6:trim(xf*Transform3D(Basis.IDENTITY,Vector3(hole0+i*(hole1-hole0)/5.0,FLOOR+.55,z0+width+.04)),Vector3(.09,1.1,.09),"brown")
	trim(xf*Transform3D(Basis.IDENTITY,Vector3((hole0+hole1)*.5,FLOOR+1.04,z0+width+.04)),Vector3(hole1-hole0+.1,.07,.12),"brown")
	# Handrail on the wall side of the flight.
	var rail:=Transform3D(Basis(Vector3.BACK,slope),(a+c)*.5+Vector3(0,.95,-width*.5+.08))
	trim(xf*rail,Vector3(along.length(),.06,.06),"brown")

# The village church: a whitewashed nave on a stone plinth with tall arched
# windows, a square bell tower over the porch facing the square and a metal
# spire. Pews and an altar inside; side doors give the north lane a route
# through the nave.
func church(center: Vector3) -> void:
	var xf:=house_xf(center,0.0)
	var root:=node(b.region,"VillageChurch",center)
	var size:=Vector2(9.0,15.0);var t:=.7;var eave:=7.0
	var hx:=size.x*.5;var hz:=size.y*.5
	blocks.append(Rect2(center.x-hx,center.z-hz,size.x,size.y))
	var white:=plaster(Color(.95,.94,.9),.25)
	var tall:=func(at:float,start:float,direction:float)->Rect2:return Rect2((at-start)*direction-.55,2.6,1.1,3.2)
	var east:=[tall.call(-5.0,hz-t,-1),Rect2((hz-t-(-1.8))-1.0,0,2.0,2.8),tall.call(3.5,hz-t,-1)]
	var west:=[tall.call(-5.0,-hz+t,1),Rect2((-1.8-(-hz+t))-1.0,0,2.0,2.8),tall.call(3.5,-hz+t,1)]
	# Front (+z) opens into the tower porch; the apse wall (-z) is closed.
	wall(root,xf,Vector3(-hx,0,hz-t*.5),Vector3(hx,0,hz-t*.5),eave,t,[Rect2(hx-1.0,0,2.0,3.0)],white,"brown")
	wall(root,xf,Vector3(hx,0,-hz+t*.5),Vector3(-hx,0,-hz+t*.5),eave,t,[Rect2(hx-.5,3.4,1.0,1.0)],white,"brown")
	wall(root,xf,Vector3(hx-t*.5,0,hz-t),Vector3(hx-t*.5,0,-hz+t),eave,t,east,white,"brown")
	wall(root,xf,Vector3(-hx+t*.5,0,-hz+t),Vector3(-hx+t*.5,0,hz-t),eave,t,west,white,"brown")
	plinth(root,xf,size,t,{"s":[[0.0,"door"]],"e":[[-1.8,"wide"]],"w":[[-1.8,"wide"]]})
	# Buttresses on the long walls.
	for side:float in [-1.0,1.0]:
		for z in [-5.0,0.5,5.5]:piece(root,"VillageButtress",Vector3(side*(hx+.3),1.6,z),Vector3(.6,3.2,.9),stone(),true,"concrete",Vector3.ZERO,.8)
	var nave_roof:=node(root,"VillageNaveRoof",Vector3.ZERO,Vector3(0,PI*.5,0))
	roof(nave_roof,Vector2(size.y,size.x),eave,t,white,roof_dark(),false,.6)
	piece(root,"VillageFloor",Vector3(0,.02,0),Vector3(size.x-t*2,.04,size.y-t*2),scan("cobblestone_floor_001",2.4,.2),false,"concrete",Vector3.ZERO,0.0)
	# Pews either side of a 2.4 m aisle, an altar on a step and a tie beam truss.
	for z in [.8,2.6,4.4]:
		for side:float in [-1.0,1.0]:
			piece(root,"VillagePew",Vector3(side*2.2,.45,z),Vector3(2.4,.9,.5),planks(Color(.42,.3,.2),.5),true,"wood",Vector3.ZERO,0.0)
	piece(root,"VillageAltarStep",Vector3(0,.1,-hz+t+1.6),Vector3(size.x-t*2,.2,3.2),stone(),true)
	piece(root,"VillageAltar",Vector3(0,.7,-hz+t+1.2),Vector3(2.0,1.0,.9),stone(),true)
	for z in [-4.0,0.0,4.0]:piece(root,"VillageTieBeam",Vector3(0,eave-.25,z),Vector3(size.x-t*2,.3,.3),planks(Color(.36,.25,.17),.6),false,"wood",Vector3.ZERO,0.0)
	b.arena.probe_volumes.append(AABB(center-Vector3(hx-t,0,hz-t),Vector3(size.x-t*2,eave,size.y-t*2)))
	for z in [-4.0,3.0]:fill_light(center+Vector3(0,eave-1.2,z),9.0,1.2)
	# Bell tower: porch at ground level, closed shaft, open belfry, metal spire.
	var tower:=node(root,"VillageTower",Vector3(0,0,hz+2.0))
	var txf:=xf*tower.transform
	var ts:=4.4;var th:=15.0;var tt:=.6
	blocks.append(Rect2(center.x-ts*.5,center.z+hz+2.0-ts*.5,ts,ts))
	var belfry:=Rect2(ts*.5-.75,th-4.2,1.5,2.6)
	wall(tower,txf,Vector3(-ts*.5,0,ts*.5-tt*.5),Vector3(ts*.5,0,ts*.5-tt*.5),th,tt,[Rect2(ts*.5-1.0,0,2.0,3.0),Rect2(ts*.5-.4,7.0,.8,1.4),belfry],white,"brown")
	wall(tower,txf,Vector3(ts*.5,0,-ts*.5+tt*.5),Vector3(-ts*.5,0,-ts*.5+tt*.5),th,tt,[Rect2(ts*.5-1.0,0,2.0,3.0)],white,"brown")
	wall(tower,txf,Vector3(ts*.5-tt*.5,0,ts*.5-tt),Vector3(ts*.5-tt*.5,0,-ts*.5+tt),th,tt,[Rect2((ts-tt*2)*.5-1.0,0,2.0,2.8),Rect2((ts-tt*2)*.5-.65,th-4.2,1.3,2.6)],white,"brown")
	wall(tower,txf,Vector3(-ts*.5+tt*.5,0,-ts*.5+tt),Vector3(-ts*.5+tt*.5,0,ts*.5-tt),th,tt,[Rect2((ts-tt*2)*.5-1.0,0,2.0,2.8),Rect2((ts-tt*2)*.5-.65,th-4.2,1.3,2.6)],white,"brown")
	piece(tower,"VillageTowerFloor",Vector3(0,3.6,0),Vector3(ts-tt*2,.3,ts-tt*2),floorboards(),true,"wood",Vector3.ZERO,0.0)
	for y in [7.0,th-.15]:
		piece(tower,"VillageCornice",Vector3(0,y,0),Vector3(ts+.3,.3,ts+.3),stone(),false,"concrete",Vector3.ZERO,0.0)
	var spire:=node(tower,"VillageSpire",Vector3(0,th,0))
	visual(spire,pyramid_mesh(ts*.5+.15,7.0),b.surfaces.get_material("painted_metal",Color("43594c")))
	piece(tower,"VillageCross",Vector3(0,th+7.6,0),Vector3(.08,1.2,.08),trim_material("black"),false)
	piece(tower,"VillageCross",Vector3(0,th+7.85,0),Vector3(.6,.08,.08),trim_material("black"),false)
	# A bell in the belfry.
	var bell:=b.cylinder(Vector3(0,th-2.6,0)+center+Vector3(0,0,hz+2.0),.42,.7,Color("6b5a3a"))
	bell.material_override=b.surfaces.get_material("rust")

# A timber barn on a stone footing, open to the yard: the team deploys inside
# it. Local +x faces the village.
func barn(center: Vector3, yaw: float) -> void:
	var xf:=house_xf(center,yaw)
	var root:=node(b.region,"VillageBarn",center,Vector3(0,yaw,0))
	var size:=Vector2(10.0,20.0);var t:=.3;var eave:=4.6
	footprint(center,size,yaw)
	var hx:=size.x*.5;var hz:=size.y*.5
	var wood:=planks()
	# Rotated so the ridge runs along the barn's length (local z).
	var east_open:=[Rect2(hz-t-7.0-2.0,0,4.0,3.6),Rect2(hz-t-(-7.0)-2.0,0,4.0,3.6),Rect2(hz-t-1.0,1.4,2.0,1.0)]
	wall(root,xf,Vector3(hx-t*.5,0,hz-t),Vector3(hx-t*.5,0,-hz+t),eave,t,east_open,wood,"wood","wood")
	wall(root,xf,Vector3(-hx+t*.5,0,-hz+t),Vector3(-hx+t*.5,0,hz-t),eave,t,[Rect2(hz-t-1.0,1.4,2.0,1.0)],wood,"wood","wood")
	wall(root,xf,Vector3(-hx,0,hz-t*.5),Vector3(hx,0,hz-t*.5),eave,t,[Rect2(hx-2.0,0,4.0,3.8)],wood,"wood","wood")
	wall(root,xf,Vector3(hx,0,-hz+t*.5),Vector3(-hx,0,-hz+t*.5),eave,t,[Rect2(hx-2.0,0,4.0,3.8)],wood,"wood","wood")
	plinth(root,xf,size,t,{"e":[[-7.0,"wide"],[7.0,"wide"]],"s":[[0.0,"wide"]],"n":[[0.0,"wide"]]})
	var roof_node:=node(root,"VillageBarnRoof",Vector3.ZERO,Vector3(0,PI*.5,0))
	roof(roof_node,Vector2(size.y,size.x),eave,t,wood,b.surfaces.get_material("corrugated",Color("7d5a45")),false,.6)
	# Posts and tie beams carry the roof; no posts on the deployment rows.
	for z in [-hz+t+.2,-2.5,2.5,hz-t-.2]:
		piece(root,"VillageBeam",Vector3(0,eave-.2,z),Vector3(size.x-t*2,.25,.25),wood,false,"wood",Vector3.ZERO,0.0)
	for z in [-2.5,2.5]:piece(root,"VillagePost",Vector3(0,eave*.5,z),Vector3(.25,eave,.25),wood,true,"wood",Vector3.ZERO,.3)
	piece(root,"VillageFloor",Vector3(0,.015,0),Vector3(size.x-t*2,.03,size.y-t*2),straw(),false,"earth",Vector3.ZERO,0.0)
	# Hay in the corners, clear of the deployment rows (local z = +-5).
	for corner in [Vector3(-3.4,0,-8.4),Vector3(-3.4,0,8.4)]:
		square_bales(xf*corner,yaw,3)
	b.arena.probe_volumes.append(AABB(center-Vector3(4.7,0,9.7),Vector3(9.4,eave,19.4)))
	for z in [-5.0,5.0]:fill_light(xf*Vector3(0,eave-.8,z),9.0,.8)

# The old village hall: single storey, clay plaster, a deep porch to the square.
func hall(center: Vector3, yaw: float) -> void:
	var root:=house(center,Vector2(14,8),yaw,{"floors":1,"wall":clay(),"roof":roof_dark(),"paint":"green","chimney":true,
		"s":[[-4.5,"window"],[0.0,"wide"],[4.5,"window"]],"n":[[-3.0,"window"],[3.0,"door"]],"e":[[0.0,"door"]],"w":[[0.0,"door"]]})
	var xf:=house_xf(center,yaw)
	# Porch: four posts, a lean-to roof, a stone step.
	for x in [-3.0,-1.0,1.0,3.0]:
		if absf(x)>2:piece(root,"VillagePorchPost",Vector3(x,1.35,5.6),Vector3(.2,2.7,.2),planks(Color(.27,.4,.31),.7),true,"wood",Vector3.ZERO,.3)
	piece(root,"VillagePorchRoof",Vector3(0,2.95,5.0),Vector3(7.4,.12,2.4),roof_dark(),false,"concrete",Vector3(.18,0,0),0.0)
	b.prop("painted_wooden_bench",xf*Vector3(-5.0,0,4.9),.85,yaw+PI)
	# Shop counter and shelving inside.
	piece(root,"VillageCounter",Vector3(2.5,.5,-1.8),Vector3(3.6,1.0,.7),planks(Color(.36,.25,.17),.6),true,"wood",Vector3.ZERO,.2)
	b.prop("painted_wooden_cabinet",xf*Vector3(-5.6,0,-3.0),1.9,yaw)
	b.prop("painted_wooden_table",xf*Vector3(-3.0,0,1.2),.78,yaw+.3)
	b.prop("painted_wooden_chair_01",xf*Vector3(-3.9,0,1.6),.95,yaw+1.2,false)
	sign_board(xf,Vector3(0,2.85,4.05),"MAGAZIN")

func sign_board(xf: Transform3D, local: Vector3, text: String) -> void:
	trim(xf*Transform3D(Basis.IDENTITY,local),Vector3(2.6,.3,.05),"blue")
	var label:=Label3D.new();label.text=text;label.font_size=40;label.pixel_size=.008
	label.modulate=Color(.86,.84,.78);label.shaded=true;label.outline_size=0;label.alpha_cut=Label3D.ALPHA_CUT_DISCARD;label.double_sided=false
	b.region.add_child(label);label.transform=xf*Transform3D(Basis.IDENTITY,local+Vector3(0,0,.035))

# --- Yards, walls, fences ----------------------------------------------------------

# Rubble-stone garden wall with a flat stone coping; cover on both faces.
func stone_wall(a: Vector3, c: Vector3, height := 1.05, cover := true) -> void:
	var d:=c-a;var length:=Vector2(d.x,d.z).length()
	var yaw:=atan2(-d.z,d.x)
	var mid:=(a+c)*.5
	piece(b.region,"VillageStoneWall",mid+Vector3.UP*height*.5,Vector3(length,height,.5),stone(),true,"concrete",Vector3(0,yaw,0),.9)
	piece(b.region,"VillageCoping",mid+Vector3.UP*(height+.04),Vector3(length+.06,.08,.6),stone(),false,"concrete",Vector3(0,yaw,0),0.0,false)
	if cover and length>2.2:
		var side:=Basis(Vector3.UP,yaw)*Vector3(0,0,1.1);var along:=d.normalized()
		for s:float in [-1.0,1.0]:
			b.def.cover_points.append(mid+side*s)
			b.def.cover_peeks.append(mid+side*s+along*s*(length*.5+.9))
	burn(7*int(length*1.4))

# Picket fence (posts, two rails, pickets) on a thin collider, with an
# optional open gate gap of 1.6 m at gate (distance from a).
func fence(a: Vector3, c: Vector3, paint := "wood", gate := -1.0, height := 1.15) -> void:
	var d:=c-a;var length:=Vector2(d.x,d.z).length();var along:=d/length
	var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var spans:Array[Vector2]=[]
	if gate<0:spans.append(Vector2(0,length))
	else:
		if gate-.8>.2:spans.append(Vector2(0,gate-.8))
		if length-(gate+.8)>.2:spans.append(Vector2(gate+.8,length))
	for span in spans:
		var span_length:=span.y-span.x
		var mid:=a+along*(span.x+span.y)*.5
		var item:=node(b.region,"VillageFence",mid,Vector3(0,yaw,0))
		body(item,[[Vector3(0,height*.5,0),Vector3(span_length,height,.12)]],"wood")
		var posts:=maxi(1,ceili(span_length/2.2))
		for i in posts+1:
			var p:=a+along*(span.x+span_length*i/posts)
			trim(Transform3D(turn.rotated(Vector3.UP,b.rng.randf_range(-.05,.05)),p+Vector3.UP*(height*.5+.05)),Vector3(.1,height+.1,.1),"wood")
		for y in [.35,height-.2]:trim(Transform3D(turn,mid+Vector3(0,y,0)+turn*Vector3(0,0,.07)),Vector3(span_length,.07,.03),paint)
		var pickets:=int(span_length/.16)
		for i in pickets:
			if b.rng.randf()<.06:continue  # a few boards missing
			var p:=a+along*(span.x+(i+.5)*span_length/pickets)+turn*Vector3(0,0,.1)
			var tall:=height-.05+b.rng.randf_range(-.06,.04)
			trim(Transform3D(turn.rotated(Vector3.UP,b.rng.randf_range(-.04,.04)).rotated(along,b.rng.randf_range(-.03,.03)),p+Vector3.UP*tall*.5),Vector3(.09,tall,.02),paint)
	if gate>=0 and b.rng.randf()<.8:
		# Gate leaf hanging open from its post.
		var hinge:=a+along*(gate-.8)+turn*Vector3(0,0,.1)
		var leaf:=turn.rotated(Vector3.UP,1.1)
		trim(Transform3D(leaf,hinge+leaf*Vector3(.75,height*.5,0)),Vector3(1.5,height-.1,.04),paint)
	burn(7*int(length*1.2))

# Round straw bale lying on its side (1.5 m across), solid cover.
func round_bale(p: Vector3, yaw: float) -> void:
	var item:=node(b.region,"VillageBale",p+Vector3.UP*.75,Vector3(PI*.5,yaw,0))
	var key:="vbale"
	if not b.meshes.has(key):
		var mesh:=MapMeshes.cylinder(.75,1.2,20,0.0);mesh.lightmap_unwrap(Transform3D.IDENTITY,.3);b.meshes[key]=mesh
	visual(item,b.meshes[key],straw())
	var shape:=CylinderShape3D.new();shape.radius=.75;shape.height=1.2
	body(item,[[Vector3.ZERO,shape]],"earth")

# Stack of small square bales; rows of three on a 1.1 x 0.5 x 0.4 m bale.
func square_bales(p: Vector3, yaw: float, rows := 2) -> void:
	var turn:=Basis(Vector3.UP,yaw)
	for row in rows:
		for i in 3-row%2:
			var off:=Vector3((i-1+(.5 if row%2 else 0.0))*1.12,row*.41+.205,b.rng.randf_range(-.05,.05))
			piece(b.region,"VillageSquareBale",p+turn*off,Vector3(1.1,.4,.5),straw(),row==0,"earth",Vector3(0,yaw+b.rng.randf_range(-.06,.06),0),0.0,false)

# Firewood stacked against a wall: rows of split logs (batched cylinders).
func woodpile(p: Vector3, yaw: float, length := 2.4, height := 1.2) -> void:
	var turn:=Basis(Vector3.UP,yaw)
	var key:="log"
	if not foliage_meshes.has(key):
		var mesh:=MapMeshes.cylinder(.075,.45,7,0.0)
		foliage_meshes[key]=[mesh,bark()]
	var rows:=int(height/.14)
	for row in rows:
		var count:=int(length/.155)
		for i in count:
			var off:=Vector3(-length*.5+(i+.5+(.5 if row%2 else 0.0))*.155,.075+row*.135,b.rng.randf_range(-.03,.03))
			var log_basis:=turn*Basis(Vector3.RIGHT,PI*.5)*Basis(Vector3.UP,b.rng.randf()*TAU)
			add_foliage(key,Transform3D(log_basis.scaled(Vector3.ONE*b.rng.randf_range(.85,1.15)),p+turn*off))
	# A plank lean-to keeps the rain off.
	piece(b.region,"VillageWoodpileRoof",p+turn*Vector3(0,height+.18,-.05),Vector3(length+.3,.04,.75),planks(),false,"wood",Vector3(-.25,yaw,0),0.0,false)
	var box:=node(b.region,"VillageWoodpile",p,Vector3(0,yaw,0))
	body(box,[[Vector3(0,height*.5,0),Vector3(length,height,.45)]],"wood")

# Stone well with a timber roof and a winch over the square.
func well(p: Vector3) -> void:
	var ring:=node(b.region,"VillageWell",p+Vector3.UP*.45)
	var key:="vwell"
	if not b.meshes.has(key):
		var mesh:=MapMeshes.cylinder(.85,.9,24,.6);mesh.lightmap_unwrap(Transform3D.IDENTITY,.3);b.meshes[key]=mesh
	visual(ring,b.meshes[key],stone())
	var shape:=CylinderShape3D.new();shape.radius=.85;shape.height=.9
	body(ring,[[Vector3.ZERO,shape]],"concrete")
	for side:float in [-1.0,1.0]:
		trim(Transform3D(Basis.IDENTITY,p+Vector3(side*.78,1.25,0)),Vector3(.12,2.5,.12),"wood")
	var winch:=Transform3D(Basis(Vector3.BACK,PI*.5),p+Vector3(0,1.65,0))
	trim(winch,Vector3(.16,1.6,.16),"wood")
	for side:float in [-1.0,1.0]:
		var roof_basis:=Basis(Vector3.RIGHT,side*.62)
		trim(Transform3D(roof_basis,p+Vector3(0,2.42,side*.42)),Vector3(1.9,.04,1.05),"wood")
	b.props.scatter("wooden_bucket_01",b.props.grounded("wooden_bucket_01",p+Vector3(.3,.9,.15),.4,.32/maxf(b.props.bounds("wooden_bucket_01").size.y,.01)))

# A wooden power pole with a crossarm and three porcelain insulators.
func pole(p: Vector3, yaw: float) -> Array[Vector3]:
	var key:="vpole"
	if not b.meshes.has(key):
		var mesh:=MapMeshes.cylinder(.13,8.4,10,.5);mesh.lightmap_unwrap(Transform3D.IDENTITY,.3);b.meshes[key]=mesh
	var item:=node(b.region,"VillagePole",p+Vector3.UP*4.2,Vector3(b.rng.randf_range(-.03,.03),0,b.rng.randf_range(-.03,.03)))
	visual(item,b.meshes[key],planks(Color(.3,.24,.19),.6),false)
	var shape:=CylinderShape3D.new();shape.radius=.14;shape.height=8.4
	body(item,[[Vector3.ZERO,shape]],"wood")
	var turn:=Basis(Vector3.UP,yaw)
	trim(Transform3D(turn,p+Vector3(0,7.75,0)),Vector3(.1,.12,1.9),"wood")
	var tops:Array[Vector3]=[]
	for z in [-.8,0.0,.8]:
		var at:=p+turn*Vector3(0,7.92,z)
		trim(Transform3D(turn,at),Vector3(.08,.16,.08),"porcelain")
		tops.append(at+Vector3.UP*.08)
	return tops

# A sagging cable between two points: a thin square tube along a parabola.
func cable(a: Vector3, c: Vector3, sag: float) -> void:
	var segments:=14
	var prev:=a
	for i in segments:
		var t1:=float(i+1)/segments
		var p:=a.lerp(c,t1)-Vector3.UP*sag*4.0*t1*(1.0-t1)
		var dir:=(p-prev).normalized();var side:=dir.cross(Vector3.UP).normalized()*.012;var up:=dir.cross(side).normalized()*.012
		for k in 4:
			var o0:Vector3=[side,up,-side,-up][k];var o1:Vector3=[side,up,-side,-up][(k+1)%4]
			var n:Vector3=(o0+o1).normalized()
			for v in [prev+o0,p+o0,p+o1,prev+o0,p+o1,prev+o1]:
				cables.set_normal(n);cables.set_uv(Vector2.ZERO);cables.add_vertex(v)
		prev=p

func flush_cables() -> void:
	var mesh:=cables.commit()
	var item:=node(b.region,"VillageCables",Vector3.ZERO)
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.07,.07,.07);mat.roughness=.6;mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	var instance:=visual(item,mesh,mat,false)
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# --- Vegetation ----------------------------------------------------------------------

func foliage_material(id: String, tint: Color) -> ShaderMaterial:
	var key:="leaf"+id+tint.to_html()
	if mats.has(key):return mats[key]
	var mat:=ShaderMaterial.new();mat.shader=preload("res://content/materials/village_leaf.gdshader")
	mat.set_shader_parameter("albedo_tex",load(LEAVES+id+"_color.png"))
	mat.set_shader_parameter("opacity_tex",load(LEAVES+id+"_opacity.png"))
	mat.set_shader_parameter("normal_tex",load(LEAVES+id+"_normal.png"))
	mat.set_shader_parameter("tint",tint)
	mat.set_shader_parameter("alpha_cut",.4)
	mat.set_shader_parameter("transmission",Color(.3,.38,.12))
	mats[key]=mat
	return mat

func add_foliage(key: String, transform: Transform3D) -> void:
	var cell:=str(Vector2i(floori(transform.origin.x/24),floori(transform.origin.z/24)))
	if not foliage.has(key):foliage[key]={}
	if not foliage[key].has(cell):foliage[key][cell]=PackedFloat32Array()
	foliage[key][cell].append_array(MapArena.pack(transform))

func flush_foliage() -> void:
	for key in foliage:
		var entry:Array=foliage_meshes[key]
		var range_end:float=entry[2] if entry.size()>2 else 0.0
		for cell in foliage[key]:
			b.arena.instance_batches.append(["VillageGreen_"+key+str(b.arena.instance_batches.size()),entry[0],entry[1],foliage[key][cell],GeometryInstance3D.GI_MODE_DYNAMIC,range_end])
	foliage.clear()

# Leaf card: a quad of the whole leaf-set atlas centred on p, facing out.
func leaf_card(st: SurfaceTool, p: Vector3, out: Vector3, size: float, spin: float, shade: float) -> void:
	var side:=out.cross(Vector3.UP)
	if side.length()<.05:side=Vector3.RIGHT
	side=side.normalized().rotated(out,spin)
	var up:=out.cross(side).normalized()
	var n:=(out*.7+Vector3.UP*.5).normalized()
	var corners:=[p-side*size*.5-up*size*.5,p+side*size*.5-up*size*.5,p+side*size*.5+up*size*.5,p-side*size*.5+up*size*.5]
	var uvs:=[Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)]
	# Tangent along the card's U axis (for the leaf normal map) and a per-card hue shift in G.
	var tangent:=(side-n*n.dot(side)).normalized()
	var hue:=fposmod(sin(p.x*12.9898+p.y*78.233+p.z*37.719)*43758.5453,1.0)  # stable per card; leaves the layout's random stream alone
	for tri in [[0,1,2],[0,2,3]]:
		for k in tri:
			st.set_color(Color(shade*(.8 if k<2 else 1.0),hue,1));st.set_normal(n);st.set_tangent(Plane(tangent,1.0));st.set_uv(uvs[k]);st.add_vertex(corners[k])

# Broadleaf tree (linden, walnut, apple): tapered trunk, a few limbs and a
# crown of leaf-cluster cards on an ellipsoid shell. Two surfaces: bark, leaves.
func broadleaf(seed: int, height: float, crown: float, cards: int, card: float) -> ArrayMesh:
	var r:=RandomNumberGenerator.new();r.seed=seed
	var wood:=SurfaceTool.new();wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk_height:=height*.42
	var base_radius:=height*.022
	var limb:=func(from:Vector3,to:Vector3,r0:float,r1:float)->void:
		var cyl:=MapMeshes.cylinder(1.0,1.0,7)
		var arrays:=cyl.surface_get_arrays(0)
		var verts:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var dir:=(to-from);var length:=dir.length()
		var frame:=Basis.looking_at(dir.normalized(),Vector3.FORWARD if absf(dir.normalized().y)>.99 else Vector3.UP)*Basis(Vector3.RIGHT,-PI*.5)
		for i in verts.size():
			var t:=verts[i].y+.5
			var radius:=lerpf(r0,r1,t)
			verts[i]=from+frame*Vector3(verts[i].x*radius,t*length,verts[i].z*radius)
			normals[i]=(frame*normals[i]).normalized()
		# Metric UVs so the bark scan keeps its real scale along the whole limb.
		var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
		for i in verts.size():uvs[i]=Vector2(uvs[i].x*(r0+r1)*.5,(verts[i]-from).dot(dir.normalized()))
		arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_TANGENT]=null
		var built:=ArrayMesh.new();built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		wood.append_from(built,0,Transform3D.IDENTITY)
	var lean:=Vector3(r.randf_range(-.3,.3),0,r.randf_range(-.3,.3))
	var top:=Vector3(0,trunk_height,0)+lean
	limb.call(Vector3(0,-.3,0),top,base_radius*1.2,base_radius*.7)
	var centre:=Vector3(0,trunk_height+crown*.85,0)+lean*1.4
	for i in 5:
		var angle:=TAU*i/5.0+r.randf_range(-.4,.4)
		var end:=centre+Vector3(cos(angle)*crown*.6,r.randf_range(-.2,.5)*crown,sin(angle)*crown*.6)
		limb.call(top,end,base_radius*.55,base_radius*.12)
		# Secondary branches fork off each limb so the wood shows through the crown.
		var fork:=top.lerp(end,.55)
		for k in 2:limb.call(fork,end.lerp(centre,.3)+Vector3(r.randfn()*crown*.2,r.randf_range(-.2,.15)*crown,r.randfn()*crown*.2),base_radius*.2,base_radius*.05)
	limb.call(top,centre+Vector3(0,crown*.6,0),base_radius*.5,base_radius*.1)
	var leaves:=SurfaceTool.new();leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var radii:=Vector3(crown,crown*.85,crown)
	for i in cards:
		var dir:=Vector3(r.randfn(),r.randfn()*.8,r.randfn()).normalized()
		# Lumpy crown: noise on the radius and a dense outer shell.
		var lump:=1.0+.18*sin(dir.x*5.0+seed)*cos(dir.z*4.0)
		var depth:=pow(r.randf(),.35)
		var p:=centre+dir*radii*lump*depth
		var shade:=clampf(.35+.65*depth*(.6+.4*(dir.y*.5+.5)),0,1)
		leaf_card(leaves,p,(dir+Vector3(r.randf_range(-.4,.4),r.randf_range(-.2,.4),r.randf_range(-.4,.4))).normalized(),card*r.randf_range(.8,1.2),r.randf()*TAU,shade)
	var mesh:=ArrayMesh.new()
	wood.generate_tangents();wood.commit(mesh)
	leaves.index();leaves.commit(mesh)
	return mesh

# [height, crown radius] of each tree kind (see broadleaf calls in grow()).
const TREE_SHAPE := {"linden":[11.0,3.6],"walnut":[9.0,3.4],"apple":[5.2,2.1]}

func tree(p: Vector3, kind: String, scale := 1.0) -> void:
	tree_spots.append([kind,p,scale,b.rng.randf()*TAU])

func grow(kind: String, p: Vector3, scale: float, yaw: float) -> void:
	if not foliage_meshes.has(kind):
		# Near and far versions: the far crown has a third of the cards, each
		# larger, and takes over beyond LOD_SWITCH (same seed, same silhouette).
		var leaves:=foliage_material("linden" if kind=="linden" else "beech",Color(.98,1.0,.84) if kind=="linden" else (Color(1.0,1.0,.82) if kind=="walnut" else Color(1.05,1.05,.84)))
		var near:ArrayMesh;var far:ArrayMesh
		match kind:
			"linden":near=broadleaf(311,11.0,3.6,330,1.2);far=broadleaf(311,11.0,3.6,115,1.9)
			"walnut":near=broadleaf(523,9.0,3.4,300,1.15);far=broadleaf(523,9.0,3.4,110,1.85)
			_:near=broadleaf(97,5.2,2.1,150,.95);far=broadleaf(97,5.2,2.1,60,1.5)
		foliage_meshes[kind]=[near,far,leaves]
	var entry:Array=foliage_meshes[kind]
	var placed:=Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale),p)
	for lod in 2:
		var mesh:ArrayMesh=entry[lod]
		var end:=LOD_SWITCH if lod==0 else 0.0;var begin:=LOD_SWITCH if lod==1 else 0.0
		merge(kind+"_bark"+str(lod),placed,end,mesh,0,bark(),begin,false)
		merge(kind+"_leaf"+str(lod),placed,end,mesh,1,entry[2],begin,false)
	# Shadows are SET: one shadow-only copy of the light crown, never range-culled, casts
	# the tree's shadow at every distance, so it does not change as the LODs swap.
	merge("shadow_"+kind+"_bark",placed,0.0,entry[1],0,bark(),0.0,true)
	merge("shadow_"+kind+"_leaf",placed,0.0,entry[1],1,entry[2],0.0,true)
	trunks.append(p)
	var item:=node(b.region,"VillageTrunk",p+Vector3.UP*1.5)
	var shape:=CylinderShape3D.new();shape.radius=.22*scale+.05;shape.height=3.0
	body(item,[[Vector3.ZERO,shape]],"wood")

# Hedge segment: leaf cards filling a 4 x 1.3 x 2.2 m box.
func hedge(p: Vector3, yaw: float) -> void:
	if not foliage_meshes.has("hedge"):
		var r:=RandomNumberGenerator.new();r.seed=77
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 80:
			var q:=Vector3(r.randf_range(-2.1,2.1),r.randf_range(.1,2.2),r.randf_range(-.6,.6))
			var out:=Vector3(r.randfn()*.4,r.randf_range(-.1,.8),signf(q.z)+r.randfn()*.3).normalized()
			leaf_card(st,q,out,r.randf_range(.9,1.1),r.randf()*TAU,clampf(.3+q.y/2.2*.5+absf(q.z),0,1))
		foliage_meshes["hedge"]=[st.commit(),foliage_material("beech",Color(.95,1.0,.8))]
	# Outside the boundary: merged without shadows (they fall beyond the
	# real-time shadow range anyway).
	merge("hedge",Transform3D(Basis(Vector3.UP,yaw+b.rng.randf_range(-.08,.08)).scaled(Vector3(1,b.rng.randf_range(.85,1.15),1)),p),0.0)

# Merges one surface of a vegetation mesh into a per-24 m-cell mesh (plain
# meshes rather than MultiMeshes, so each cell can have its own visibility
# range for LOD and choose whether it casts shadows).
func merge(kind: String, transform: Transform3D, range_end: float, mesh: Mesh = null, surface := 0, mat: Material = null, range_begin := 0.0, shadows := false) -> void:
	var p:=transform.origin
	var key:=kind+"@"+str(Vector2i(floori(p.x/24),floori(p.z/24)))
	if mesh==null:mesh=foliage_meshes[kind][0];mat=foliage_meshes[kind][1]
	if not grass.has(key):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);grass[key]=[st,mat,range_end,range_begin,shadows]
	(grass[key][0] as SurfaceTool).append_from(mesh,surface,transform)

func flush_grass() -> void:
	for key in grass:
		var entry:Array=grass[key]
		var item:=node(b.region,"VillageGrass",Vector3.ZERO)
		var instance:=visual(item,(entry[0] as SurfaceTool).commit(),entry[1],false)
		if not entry[4]:instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif String(key).begins_with("shadow_"):instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		if entry[2]>0:instance.visibility_range_end=entry[2];instance.visibility_range_end_margin=4.0
		if entry[3]>0:instance.visibility_range_begin=entry[3];instance.visibility_range_begin_margin=4.0
		if entry[2]>0 or entry[3]>0:instance.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	grass.clear()

# Baked fill light standing in for daylight bounced in through the openings
# (fully baked: MapArena hides static lights at run time, so it costs nothing).
func fill_light(position: Vector3, reach: float, energy := 1.0) -> void:
	var lamp:=OmniLight3D.new();lamp.name="VillageFill"+str(b.serial);b.serial+=1
	lamp.position=position;lamp.light_color=Color(1.0,.97,.92)
	lamp.light_energy=energy;lamp.light_indirect_energy=1.2;lamp.light_specular=0.0
	lamp.omni_range=reach;lamp.omni_attenuation=1.2
	lamp.shadow_enabled=true;lamp.light_size=1.5
	lamp.light_bake_mode=Light3D.BAKE_STATIC
	b.region.add_child(lamp)

# Grass used to be scattered tuft by tuft from this layout's random stream. The field
# now draws from its own generator, but the stream still advances by as many draws as
# those tufts took, so every other random choice (fence runs, bale turns, orchard trees)
# stays as the layout was tested and the routes do not move.
func burn(draws: int, source: RandomNumberGenerator = null) -> void:
	var stream:=source if source!=null else b.rng
	for i in draws:stream.randf()

# Weeds in a building's corners (the grass itself comes from the field, see dress()).
func overgrow(center: Vector3, size: Vector2, yaw: float) -> void:
	var turn:=Basis(Vector3.UP,yaw)
	var hx:=size.x*.5+.25;var hz:=size.y*.5+.25
	for length in [hx*2.0,hx*2.0,hz*2.0,hz*2.0]:burn(7*int(length*1.2))
	for i in 2:
		var corner:=center+turn*Vector3([-1,1][i]*(hx+.2),0,[1,-1][i]*(hz+.2))
		weed(corner)

func weed(p: Vector3) -> void:
	var id:String=["weed_plant_02","fern_02","fern_02"][b.rng.randi()%3]
	var height:float={"weed_plant_02":.7,"fern_02":.6}[id]
	var scale:=height*b.rng.randf_range(.8,1.2)/maxf(b.props.bounds(id).size.y,.01)
	weeds.append([id,p,b.rng.randf()*TAU,scale])

# Weeds are placed once every solid exists, and only where they clear walls, fences and props.
func place_weeds() -> void:
	var dropped:=0
	for item in weeds:
		var id:String=item[0];var box:=b.props.bounds(id);var scale:float=item[3]
		var reach:=maxf(.35,maxf(box.size.x,box.size.z)*scale*.5)
		var spot:Variant=b.nature.fit(item[1],reach,box.size.y*scale)
		if spot==null:dropped+=1;continue
		b.props.scatter(id,b.props.grounded(id,spot,item[2],scale))
	print("Village weeds=",weeds.size()-dropped," dropped=",dropped)
	weeds.clear()

# Elder/lilac-like bush: leaf-cluster cards on a squashed dome (a few hundred
# triangles where a scanned shrub costs ~50k).
func bush(p: Vector3, height := 1.6) -> void:
	if not foliage_meshes.has("bush"):
		var r:=RandomNumberGenerator.new();r.seed=313
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 60:
			var dir:=Vector3(r.randfn(),absf(r.randfn())*.9+.1,r.randfn()).normalized()
			var depth:=pow(r.randf(),.4)
			var q:=Vector3(0,.75,0)+dir*Vector3(1.1,.85,1.1)*depth
			leaf_card(st,q,(dir+Vector3(r.randf_range(-.4,.4),.2,r.randf_range(-.4,.4))).normalized(),r.randf_range(.9,1.0),r.randf()*TAU,clampf(.35+.65*depth*(.5+.5*dir.y),0,1))
		var mesh:=st.commit()
		mesh.surface_set_material(0,foliage_material("beech",Color(.92,1.0,.78)))
		foliage_meshes["bush"]=[mesh,null,120.0]
	var size:=height/1.6*b.rng.randf_range(.85,1.15)
	bush_spots.append(Transform3D(Basis(Vector3.UP,b.rng.randf()*TAU).scaled(Vector3(size,size*b.rng.randf_range(.85,1.1),size)),p))

# Places the queued bushes, sliding any whose crown (about 0.7 m of radius per
# metre of height) would lie on a dirt path out of the way, away from its centre line,
# and any that would grow into a wall, fence, prop or trunk away from it (or dropping it).
func place_bushes() -> void:
	var moved:=0;var dropped:=0;var kept:=0
	for spot in bush_spots:
		var p:=spot.origin;var reach:=spot.basis.x.length()*1.1+.4
		for step in 8:
			var d:=path_distance(p.x,p.z)
			if d>=reach:break
			var away:=Vector2(path_distance(p.x+.1,p.z)-path_distance(p.x-.1,p.z),path_distance(p.x,p.z+.1)-path_distance(p.x,p.z-.1))
			if away.length()<.001:away=Vector2(0,-1)
			p+=Vector3(away.x,0,away.y).normalized()*(reach-d+.05)
			if step==0:moved+=1
		var fitted:Variant=b.nature.fit(p,spot.basis.x.length()*1.15,spot.basis.y.length()*1.5)
		if fitted==null:dropped+=1;continue
		spot.origin=fitted
		kept+=1
		add_foliage("bush",spot)
	print("Village bushes=",kept," moved off paths=",moved," dropped (no room clear of walls)=",dropped)
	bush_spots.clear()

# Trees go in last, where their trunks and crowns (card radius about 1.05 of the
# crown size, from 4 m up) clear every wall, roof and fence; one that cannot be
# moved clear is dropped.
func place_trees() -> void:
	var kept:=0;var dropped:=0;var moved:=0
	for item in tree_spots:
		var kind:String=item[0];var scale:float=item[2]
		var shape:Array=TREE_SHAPE[kind]
		var crown:float=shape[1]*scale*1.05
		# The crown (leaf cards from about 40% of the height up) must clear walls and roofs,
		# not the poles and fences below it; the trunk only needs room itself.
		var heights:=[shape[0]*scale*.45,shape[0]*scale*.65,shape[0]*scale*.85]
		var fitted:Variant=b.nature.fit(item[1],crown,shape[0]*scale,heights,.2)
		if fitted!=null:fitted=b.nature.fit(fitted,.6,2.5,[.3,1.2,2.2])
		if fitted==null:
			dropped+=1;print("  tree dropped: ",kind," at ",(item[1] as Vector3).snapped(Vector3(.1,.1,.1)));continue
		if (fitted as Vector3).distance_to(item[1])>.05:moved+=1
		grow(kind,fitted,scale,item[3])
		kept+=1
	print("Village trees=",kept," moved=",moved," dropped=",dropped)
	tree_spots.clear()

# --- Layout ----------------------------------------------------------------------------

# Runs f(p, yaw) and its point-symmetric twin f(-p, yaw + PI).
func both(f: Callable, p: Vector3, yaw := 0.0) -> void:
	f.call(p,yaw)
	f.call(Vector3(-p.x,p.y,-p.z),yaw+PI)

func mirror(p: Vector3) -> Vector3:
	return Vector3(-p.x,p.y,-p.z)

func cover_at(point: Vector3, peek: Vector3) -> void:
	for flip in [false,true]:
		b.def.cover_points.append(mirror(point) if flip else point)
		b.def.cover_peeks.append(mirror(peek) if flip else peek)

func boundaries(builder: CompactMapBuilder) -> void:
	b=builder
	var half:=b.def.extent*.5
	# Solid but invisible limits a metre outside the dressing at the edges.
	var limits:=node(b.region,"Perimeter",Vector3.ZERO)
	body(limits,[[Vector3(-half.x-.25,4,0),Vector3(.5,8,b.def.extent.y)],[Vector3(half.x+.25,4,0),Vector3(.5,8,b.def.extent.y)],
		[Vector3(0,4,-half.y-.25),Vector3(b.def.extent.x,8,.5)],[Vector3(0,4,half.y+.25),Vector3(b.def.extent.x,8,.5)]],"concrete")
	# The village edge: picket fences and stone walls along the north and south
	# lanes, hedgerows and outlying farmhouses beyond them; fields past the barns.
	for side:float in [-1.0,1.0]:
		var z:=side*(half.y-.4)
		var x:=-half.x
		var k:=0
		while x<half.x-.5:
			var length:=minf(b.rng.randf_range(9.0,16.0),half.x-x)
			if k%3==1:stone_wall(Vector3(x,0,z),Vector3(x+length,0,z),1.25,false)
			else:fence(Vector3(x,0,z),Vector3(x+length,0,z),"wood",-1.0,1.3)
			x+=length;k+=1
		for i in 30:hedge(Vector3(-half.x+2+i*3.8,0,side*(half.y+1.8)),0.0)
		for xx in [-46.0,-27.0,-6.0,15.0,36.0]:
			if b.rng.randf()<.85:tree(Vector3(xx+b.rng.randf_range(-3,3),0,side*(half.y+b.rng.randf_range(4.5,8.0))),"walnut" if b.rng.randf()<.5 else "linden",b.rng.randf_range(.9,1.25))
		var outlying:=[[-30.0,0.0],[2.0,.2],[33.0,-.1]]
		for item in outlying:
			var cx:float=item[0]*side
			house(Vector3(cx,0,side*(half.y+13.0)),Vector2(10,7.5),(0.0 if side<0 else PI)+float(item[1]),{"context":true,"floors":1 if cx>0 else 2,"wall":plaster([Color(.86,.76,.56),Color(.95,.94,.9),Color(.72,.8,.7)][b.rng.randi()%3],.45),"roof":roof_red() if b.rng.randf()<.6 else roof_dark(),
				"s":[[-2.8,"both"],[0.0,"both"],[2.8,"both"]],"n":[[-2.0,"both"],[2.0,"both"]]})
	for side:float in [-1.0,1.0]:
		var x:=side*(half.x-.4)
		fence(Vector3(x,0,-half.y),Vector3(x,0,half.y),"wood",-1.0,1.3)
		for i in 24:hedge(Vector3(side*(half.x+2.0),0,-half.y+2+i*3.75),PI*.5)

func build(builder: CompactMapBuilder) -> void:
	b=builder
	cables.begin(Mesh.PRIMITIVE_TRIANGLES)
	cobbled_street()
	# Middle lane: two-storey houses with stairs face each other across the
	# street; single-storey cottages opposite them; church and hall on the square.
	var colours:=[Color(.88,.76,.52),Color(.68,.77,.84),Color(.78,.86,.72),Color(.9,.7,.6),Color(.95,.94,.9)]
	var h1:={"floors":2,"stairs":true,"wall":plaster(colours[0],.55),"roof":roof_red(),"paint":"green",
		"s":[[-3.6,"both"],[-.9,"both"],[2.5,"door"],[2.5,"upper"]],"n":[[-3.0,"upper"],[3.5,"both"]],"e":[[.5,"door"],[-2.0,"upper"]],"w":[[1.0,"door"],[-1.6,"upper"],[2.2,"upper"]]}
	house(Vector3(-22,0,-13),Vector2(12.5,8),0.0,h1)
	var h2:=h1.duplicate();h2.wall=plaster(colours[1],.5);h2.paint="white"
	house(Vector3(22,0,13),Vector2(12.5,8),PI,h2)
	furnish_two_storey(Vector3(-22,0,-13),0.0)
	furnish_two_storey(Vector3(22,0,13),PI)
	var h3:={"floors":1,"wall":worn_plaster(colours[4],0.0),"roof":roof_dark(),"paint":"blue",
		"s":[[-2.6,"window"],[1.0,"door"],[3.2,"window"]],"n":[[-2.0,"window"],[2.4,"door"]],"e":[[0.0,"window"]],"w":[[-.8,"door"]]}
	house(Vector3(-25,0,14),Vector2(9,7.5),PI,h3)
	var h4:=h3.duplicate();h4.wall=worn_plaster(colours[3],.45);h4.paint="green"
	house(Vector3(25,0,-14),Vector2(9,7.5),0.0,h4)
	both(func(p:Vector3,yaw:float):
		var xf:=house_xf(p,yaw)
		b.prop("painted_wooden_table",xf*Vector3(-1.8,0,-1.0),.78,yaw+.2)
		b.prop("painted_wooden_chair_01",xf*Vector3(-1.0,0,-1.6),.95,yaw+2.4,false)
		b.prop("painted_wooden_cabinet",xf*Vector3(-3.4,0,-2.9),1.9,yaw+PI)
		,Vector3(-25,0,14),PI)
	# Outer houses by the farmyards: ground floor open, upper floor shut.
	var h5:={"floors":2,"wall":plaster(colours[2],.5),"roof":roof_red(),"paint":"white",
		"s":[[-2.2,"both"],[1.6,"door"],[1.6,"upper"]],"n":[[2.0,"door"],[-2.0,"both"]],"e":[[0.0,"both"]],"w":[[0.0,"upper"]]}
	house(Vector3(-33,0,-31),Vector2(9,8),0.0,h5)
	var h6:=h5.duplicate();h6.wall=plaster(colours[0],.35)
	house(Vector3(33,0,31),Vector2(9,8),PI,h6)
	both(func(p:Vector3,yaw:float):
		var xf:=house_xf(p,yaw)
		b.prop("painted_wooden_table",xf*Vector3(-2.0,0,.5),.78,yaw)
		b.prop("painted_wooden_cabinet",xf*Vector3(3.6,0,-3.0),1.9,yaw+PI)
		woodpile(xf*Vector3(3.55,0,4.35),yaw,1.8,1.25)
		,Vector3(-33,0,-31))
	church(Vector3(0,0,-20))
	hall(Vector3(0,0,19),PI)
	for item in [[Vector3(-22,0,-13),Vector2(12.5,8),0.0],[Vector3(22,0,13),Vector2(12.5,8),PI],[Vector3(-25,0,14),Vector2(9,7.5),PI],[Vector3(25,0,-14),Vector2(9,7.5),0.0],
		[Vector3(-33,0,-31),Vector2(9,8),0.0],[Vector3(33,0,31),Vector2(9,8),PI],[Vector3(0,0,19),Vector2(14,8),PI],[Vector3(0,0,-20),Vector2(9,15),0.0]]:
		overgrow(item[0],item[1],item[2])
	square()
	gardens()
	north_lane()
	power_lines()
	weathering()

func furnish_two_storey(p: Vector3, yaw: float) -> void:
	var xf:=house_xf(p,yaw)
	b.prop("painted_wooden_table",xf*Vector3(-2.4,0,1.0),.78,yaw+.15)
	b.prop("painted_wooden_chair_01",xf*Vector3(-1.5,0,1.7),.95,yaw-1.9,false)
	b.prop("painted_wooden_cabinet",xf*Vector3(5.3,0,-2.6),1.9,yaw-PI*.5)
	b.prop("painted_wooden_cabinet",xf*Vector3(-5.3,FLOOR,-2.6),1.9,yaw+PI*.5)
	b.prop("painted_wooden_table",xf*Vector3(3.6,FLOOR,2.6),.78,yaw+1.4)
	b.prop("wicker_basket_01",xf*Vector3(-4.4,FLOOR,2.8),.4,yaw,false)
	b.prop("metal_jerrycan",xf*Vector3(5.3,0,3.0),.45,yaw+.6,false)
	# Cover inside: behind the front wall under the windows, upstairs by the gable.
	for local in [[Vector3(-3.6,0,2.4),Vector3(-2.2,0,2.4)],[Vector3(-.9,0,2.4),Vector3(.6,0,2.4)],[Vector3(-5.0,FLOOR,1.5),Vector3(-5.0,FLOOR,.2)]]:
		b.def.cover_points.append(xf*(local[0] as Vector3));b.def.cover_peeks.append(xf*(local[1] as Vector3))

func cobbled_street() -> void:
	# The ground's fourth splat layer becomes cobbles (the registry names
	# asphalt; this map swaps that layer's textures before the ground is built).
	var ground:Dictionary=b.style.get("ground",{});var layers:Array=ground.get("layers",[])
	var mat:=b.surfaces.ground_material(layers[0],layers[1],layers[2],layers[3],MapCatalog.color(ground.get("tint")))
	var base:=TEX+"cobblestone_floor_001/cobblestone_floor_001_%s_2k.jpg"
	mat.set_shader_parameter("b_albedo",load(base%"diff"))
	mat.set_shader_parameter("b_normal",load(base%"nor_gl"))
	mat.set_shader_parameter("b_scale",1.0/2.4)
	mat.set_shader_parameter("b_roughness",.82)
	# The shared dressing pass scatters industrial cars, barriers, tyres and
	# street lamps on a fixed grid of open spots; mark those spots as taken.
	for x in range(-int(b.def.extent.x*.5)+10,int(b.def.extent.x*.5)-9,6):
		for z in range(-int(b.def.extent.y*.5)+10,int(b.def.extent.y*.5)-9,6):b.footprints.append(Rect2(x-.05,z-.05,.1,.1))
	for x in range(-84,85,24):
		for z in [-7.0,7.0]:b.footprints.append(Rect2(x-.05,z-.05,.1,.1))
	paths.append([Vector3(-55,0,-39.5),Vector3(55,0,-39.5),2.2])
	paths.append([Vector3(-55,0,39.5),Vector3(55,0,39.5),2.2])
	for s:float in [-1.0,1.0]:
		paths.append([Vector3(-8.0*s,0,-8*s),Vector3(-8.0*s,0,-38*s),1.6])
		paths.append([Vector3(-31*s,0,-6*s),Vector3(-31*s,0,-26*s),1.6])
		paths.append([Vector3(-45*s,0,-11*s),Vector3(-45*s,0,-26*s),2.6])

func square() -> void:
	well(Vector3(-6,0,5))
	cover_at(Vector3(-6,0,6.6),Vector3(-4.3,0,6.6))
	# A war memorial (obelisk on a stepped plinth) opposite the well.
	piece(b.region,"VillageMemorial",Vector3(6,.25,-5),Vector3(2.0,.5,2.0),stone(),true)
	piece(b.region,"VillageMemorial",Vector3(6,.75,-5),Vector3(1.3,.5,1.3),stone(),true)
	piece(b.region,"VillageMemorial",Vector3(6,2.0,-5),Vector3(.6,2.0,.6),stone(),true)
	both(func(p:Vector3,yaw:float):
		tree(p,"linden",1.1)
		var turn:=Basis(Vector3.UP,yaw)
		b.prop("painted_wooden_bench",p+turn*Vector3(0,0,1.6),.85,yaw+PI)
		burn(40)
		,Vector3(-9.5,0,-7.5))
	# Abandoned cars on the street and a hay trailer by the west houses.
	both(func(p:Vector3,yaw:float):
		b.props.place("covered_car",b.props.grounded("covered_car",p,yaw),true,220.0)
		b.stains.append(p)
		,Vector3(-36,0,2.1),PI*.5+.06)
	both(func(p:Vector3,yaw:float):
		b.props.place("covered_car",b.props.grounded("covered_car",p,yaw),true,220.0)
		b.stains.append(p)
		,Vector3(-14.5,0,-2.0),PI*.5-.35)
	cover_at(Vector3(-36,0,4.2),Vector3(-32.6,0,4.2))
	cover_at(Vector3(-36,0,0),Vector3(-39.4,0,0))
	cover_at(Vector3(-14.0,0,.4),Vector3(-11,0,1.2))
	cover_at(Vector3(-15.2,0,-4.4),Vector3(-18.5,0,-4.6))
	# Front-garden walls along the street (north side; the south side mirrors them).
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		stone_wall(p+turn*Vector3(-6,0,0),p+turn*Vector3(1.6,0,0))
		stone_wall(p+turn*Vector3(3.4,0,0),p+turn*Vector3(5.4,0,0))
		,Vector3(-22,0,-7.0))
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		fence(p+turn*Vector3(-4.5,0,0),p+turn*Vector3(4.5,0,0),"green",3.5)
		,Vector3(-25,0,8.8))
	both(func(p:Vector3,yaw:float):
		round_bale(p,yaw);round_bale(p+Basis(Vector3.UP,yaw)*Vector3(1.6,0,.4),yaw+.2)
		,Vector3(-30.5,0,-5.6),.1)
	cover_at(Vector3(-29.7,0,-3.4),Vector3(-27.4,0,-3.0))

func gardens() -> void:
	# Fenced kitchen garden behind each two-storey house, with gates on both ends.
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		var c:=func(x:float,z:float)->Vector3:return p+turn*Vector3(x,0,z)
		fence(c.call(-5.5,-4.6),c.call(-5.5,-11.0),"wood",3.0)
		fence(c.call(-5.5,-11.0),c.call(5.5,-11.0),"wood",7.5)
		fence(c.call(5.5,-11.0),c.call(5.5,-4.6),"wood",2.5)
		woodpile(c.call(-2.5,-4.35),yaw+PI,3.2,1.3)
		square_bales(c.call(3.6,-6.6),yaw,2)
		b.prop("wooden_ladder",c.call(4.0,-4.4),2.6,yaw+PI,false)
		b.prop("wooden_axe",c.call(-.6,-4.9),.85,yaw+.4,false)
		b.props.scatter("tree_stump_01",b.props.grounded("tree_stump_01",c.call(-.8,-5.0),yaw,.45/maxf(b.props.bounds("tree_stump_01").size.y,.01)))
		tree(c.call(-3.0,-8.6),"apple",1.0)
		for i in 3:weed(c.call(b.rng.randf_range(-4.8,4.8),b.rng.randf_range(-10.3,-7.5)))
		burn(150)
		cover_at(c.call(3.6,-8.0),c.call(1.4,-8.0))
		,Vector3(-22,0,-13))
	# Cottage back yards: low wall to the lane, bushes, a shed wall of firewood.
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		var c:=func(x:float,z:float)->Vector3:return p+turn*Vector3(x,0,z)
		# West end pulled back 1.6 m: the navmesh (0.5 m cells) does not erode round this thin wall,
		# so the lane path ran 0.1 m off its end and caught walkers at the corner.
		stone_wall(c.call(-2.9,-9.5),c.call(.6,-9.5))
		stone_wall(c.call(2.4,-9.5),c.call(4.5,-9.5))
		for x in [-3.5,3.8]:bush(c.call(x,-6.0),1.7)
		round_bale(c.call(5.8,-6.8),yaw+.4)
		,Vector3(-25,0,14),PI)
	# Spawn farmyards: bales, a woodpile and fencing round each team's yards.
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		var c:=func(x:float,z:float)->Vector3:return p+turn*Vector3(x,0,z)
		for s:float in [-1.0,1.0]:
			round_bale(c.call(2.2,s*15.0),yaw+.3);round_bale(c.call(3.9,s*15.6),yaw-.2)
			square_bales(c.call(-3.0,s*16.8),yaw,3)
			b.def.cover_points.append(c.call(3.0,s*13.4));b.def.cover_peeks.append(c.call(5.6,s*13.2))
			burn(150)
		tree(c.call(-6.0,-20.0),"walnut",1.1)
		tree(c.call(8.0,18.5),"linden",1.0)
		,Vector3(-45,0,0))
	# Behind the barns: closed off with stone walls to the field fence.
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		stone_wall(p+turn*Vector3(0,0,-10.2),p+turn*Vector3(-5,0,-10.2),2.2,false)
		stone_wall(p+turn*Vector3(0,0,10.2),p+turn*Vector3(-5,0,10.2),2.2,false)
		,Vector3(-50.1,0,0))

func north_lane() -> void:
	# Graveyard behind the church (its twin on the south lane is a vegetable plot).
	stone_wall(Vector3(-7,0,-29.2),Vector3(-1.2,0,-29.2),.9)
	stone_wall(Vector3(1.2,0,-29.2),Vector3(7,0,-29.2),.9)
	stone_wall(Vector3(-7,0,-36.2),Vector3(-1.2,0,-36.2),.9)
	stone_wall(Vector3(1.2,0,-36.2),Vector3(7,0,-36.2),.9)
	stone_wall(Vector3(-7,0,-29.2),Vector3(-7,0,-31.6),.9,false)
	stone_wall(Vector3(-7,0,-33.8),Vector3(-7,0,-36.2),.9,false)
	stone_wall(Vector3(7,0,-29.2),Vector3(7,0,-31.6),.9,false)
	stone_wall(Vector3(7,0,-33.8),Vector3(7,0,-36.2),.9,false)
	for x in [-5.0,-3.2,3.2,5.0]:
		for z in [-31.0,-34.4]:
			var p:=Vector3(x+b.rng.randf_range(-.2,.2),0,z+b.rng.randf_range(-.2,.2))
			var lean:=Vector3(b.rng.randf_range(-.08,.08),b.rng.randf_range(-.2,.2),b.rng.randf_range(-.08,.08))
			trim(Transform3D(Basis.from_euler(lean),p+Vector3.UP*.5),Vector3(.12,1.0,.1),"stone")
			trim(Transform3D(Basis.from_euler(lean),p+Vector3.UP*.72),Vector3(.55,.1,.1),"stone")
			trim(Transform3D(Basis.IDENTITY,p+Vector3(0,.06,.55)),Vector3(.7,.12,1.4),"stone")
			burn(12)
	for x in [-6.0,6.0]:bush(Vector3(x,0,-32.7),1.4)
	# South-lane vegetable plot behind the hall.
	fence(Vector3(7,0,29.2),Vector3(1.2,0,29.2),"wood")
	fence(Vector3(-1.2,0,29.2),Vector3(-7,0,29.2),"wood")
	fence(Vector3(7,0,36.2),Vector3(1.2,0,36.2),"wood")
	fence(Vector3(-1.2,0,36.2),Vector3(-7,0,36.2),"wood")
	for x in [-7.0,7.0]:
		fence(Vector3(x,0,29.2),Vector3(x,0,31.6),"wood")
		fence(Vector3(x,0,33.8),Vector3(x,0,36.2),"wood")
	for i in 6:weed(Vector3(b.rng.randf_range(-6,6),0,b.rng.randf_range(30,35.5)))
	for side:float in [-1.0,1.0]:
		cover_at(Vector3(side*4.1,0,-28.0),Vector3(side*1.6,0,-27.4))
	# Open-fronted farm sheds with hay.
	both(func(p:Vector3,yaw:float):
		farm_shed(p,yaw)
		,Vector3(-13,0,-35))
	# Orchard of old apple and walnut trees.
	both(func(p:Vector3,yaw:float):
		var r:=RandomNumberGenerator.new();r.seed=4411
		for row in 2:
			for col in 5:
				var q:=p+Basis(Vector3.UP,yaw)*Vector3(col*5.2+r.randf_range(-.6,.6),0,row*5.0+r.randf_range(-.5,.5))
				tree(q,"apple" if (row+col)%4 else "walnut",r.randf_range(.85,1.15) if (row+col)%4 else .8)
				burn(16);burn(16,r)
		,Vector3(8,0,-36.6))
	for z in [-33.5,-28.8]:cover_at(Vector3(10.0,0,z+1.0),Vector3(12.5,0,z+1.0))
	# Outbuilding walls and bushes between the outer houses and the barns.
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		stone_wall(p+turn*Vector3(-3,0,0),p+turn*Vector3(3,0,0))
		bush(p+turn*Vector3(4.4,0,.2),1.8)
		bush(p+turn*Vector3(-4.4,0,-.4),1.5)
		,Vector3(-34,0,-17.5))
	both(func(p:Vector3,yaw:float):
		var turn:=Basis(Vector3.UP,yaw)
		stone_wall(p+turn*Vector3(0,0,-2.8),p+turn*Vector3(0,0,2.8))
		,Vector3(-14.5,0,-24.0))
	cover_at(Vector3(-13.4,0,-24.0),Vector3(-13.4,0,-27.6))
	both(func(p:Vector3,yaw:float):
		tree(p,"walnut",1.2)
		# Kept between the tree and the boundary fence, off the lane path.
		for i in 3:bush(p+Basis(Vector3.UP,yaw)*Vector3(b.rng.randf_range(-3,3),0,b.rng.randf_range(-2.4,-.8)),1.4)
		,Vector3(-22,0,-41.5))

func farm_shed(p: Vector3, yaw: float) -> void:
	var xf:=house_xf(p,yaw)
	var root:=node(b.region,"VillageShed",p,Vector3(0,yaw,0))
	var size:=Vector2(7.0,4.5);var t:=.2;var eave:=3.0
	footprint(p,size,yaw)
	var hx:=size.x*.5;var hz:=size.y*.5
	wall(root,xf,Vector3(hx,0,-hz+t*.5),Vector3(-hx,0,-hz+t*.5),eave+.8,t,[],planks(),"","wood")
	wall(root,xf,Vector3(hx-t*.5,0,hz),Vector3(hx-t*.5,0,-hz+t),eave+.4,t,[],planks(),"","wood")
	wall(root,xf,Vector3(-hx+t*.5,0,-hz+t),Vector3(-hx+t*.5,0,hz),eave+.4,t,[],planks(),"","wood")
	for x in [-hx+.15,0.0,hx-.15]:piece(root,"VillagePost",Vector3(x,eave*.5,hz-.1),Vector3(.2,eave,.2),planks(),true,"wood",Vector3.ZERO,.3)
	piece(root,"VillageShedRoof",Vector3(0,eave+.42,0),Vector3(size.x+.6,.1,size.y+.8),b.surfaces.get_material("corrugated",Color("6f6a5f")),true,"metal",Vector3(.17,0,0),0.0)
	piece(root,"VillageFloor",Vector3(0,.015,0),Vector3(size.x-t*2,.03,size.y-t),straw(),false,"earth",Vector3.ZERO,0.0)
	square_bales(xf*Vector3(-1.6,0,-1.5),yaw,3)
	round_bale(xf*Vector3(1.9,0,-.9),yaw+PI*.5)
	cover_at(xf*Vector3(-1.6,0,.1),xf*Vector3(.3,0,.6))
	burn(32)

func power_lines() -> void:
	# A line of poles along the north side of the street, with drops to the houses.
	var prev:Array[Vector3]=[]
	for spot in [Vector3(-38,0,-5.6),Vector3(-24,0,-5.6),Vector3(-8,0,-8.6),Vector3(8,0,-8.6),Vector3(24,0,-5.6),Vector3(38,0,-5.6)]:
		var tops:=pole(spot,PI*.5)
		if not prev.is_empty():
			for i in 3:cable(prev[i],tops[i],.55+i*.05)
		prev=tops
	for drop in [[Vector3(-24,0,-5.6),Vector3(-22,6.2,-8.9)],[Vector3(24,0,-5.6),Vector3(25,3.3,-10.2)],[Vector3(-24,0,-5.6),Vector3(-25,3.3,10.2)],[Vector3(24,0,-5.6),Vector3(22,6.2,8.9)]]:
		cable((drop[0] as Vector3)+Vector3(0,7.6,0),drop[1],.35)
	flush_cables()

# Damp and leak decals on the plaster, moss and stains on the ground.
func weathering() -> void:
	for rect in blocks:
		var c:=rect.get_center()
		for i in 3:
			var on_x:=i%2==0;var side:=1.0 if (i/2)%2==0 else -1.0
			var outward:=Vector3(0,0,side) if on_x else Vector3(side,0,0)
			var along:=b.rng.randf_range(-.35,.35)
			var face:=Vector3(c.x+along*rect.size.x,0,c.y+side*(rect.size.y*.5+.03)) if on_x else Vector3(c.x+side*(rect.size.x*.5+.03),0,c.y+along*rect.size.y)
			b.decal("Leaking008",face+Vector3(0,.75,0),Vector2(b.rng.randf_range(1.8,3.2),1.5),outward,0,Color(.85,.9,.75,.8))
			if i<2:b.decal("Leaking004",face+Vector3(0,b.rng.randf_range(2.0,2.8),0),Vector2(b.rng.randf_range(1.2,2.0),2.2),outward,0,Color(1,1,1,.7))

# --- Deployment and objectives ------------------------------------------------------

func deployment(builder: CompactMapBuilder) -> void:
	b=builder
	for team in 2:
		var side:=-1.0 if team==0 else 1.0
		for row in 4:
			for col in 4:
				var p:=Vector3(side*(b.def.extent.x*.5-6-col*2),.05,[-26,-5,5,26][row])
				(b.def.spawns_blue if team==0 else b.def.spawns_red).append(p)
	barn(Vector3(-45,0,0),0.0)
	barn(Vector3(45,0,0),PI)

func objectives(builder: CompactMapBuilder) -> void:
	b=builder
	for p in [Vector3(-34,0,-21),Vector3(-12,0,-14),Vector3(-24,0,-36),Vector3(-15,0,6)]:
		for q:Vector3 in [p,mirror(p)]:
			b.def.ammo_caches.append(q)
			b.box("AmmoCase",q+Vector3(0,.35,0),Vector3(1.1,.7,.65),Color("59644d"))
	for z in [-39.5,0.0,39.5]:
		for x in [-32,-19,0,19,32]:b.def.routes.append(Vector3(x,.05,z))
	for x in [-24,0,24]:b.def.domination.append(Vector3(x,0,0))
	b.def.hardpoints.assign([Vector3(0,0,-21),Vector3(0,0,0),Vector3(0,0,19),Vector3(-22,0,-12),Vector3(22,0,12)])
	# Points 3-5 are on the upper floor of the west two-storey house.
	b.def.qa_route.assign([Vector3(-46,0,-26),Vector3(-34,0,-21),Vector3(-19.5,0,-7.8),Vector3(-18.5,FLOOR,-12.5),Vector3(-22,FLOOR,-12),Vector3(-26.6,FLOOR,-12),Vector3(0,0,0),Vector3(22,0,12),Vector3(0,0,-21),Vector3(0,0,39.5),Vector3(-46,0,26)])
	flush_trims()
	# Everything solid exists now: vegetation is placed clear of it.
	b.nature.scan_clearance(b.arena)
	place_trees()
	b.nature.scan_clearance(b.arena)
	place_weeds()
	place_bushes()
	flush_foliage()
	flush_grass()
	# The shared lighting pass adds the sun after these hooks. Its soft-shadow
	# search (0.55 degree angular size) runs on every shaded pixel, and this map
	# is full of tree and eave shade: 4-5 ms of GPU at Medium on the M2. A crisp
	# PCF-filtered sun keeps the frame budget; the edge blur stays.
	b.arena.child_order_changed.connect(crisp_sun)
	print("Village cover points=",b.def.cover_points.size())

# Grass over the lawn, after the shared dressing: noise-driven patches of clumps,
# none on cobbles, dirt tracks, gravel aprons, building floors or within reach of a
# wall, fence, prop or trunk. A verge of rough grass continues outside the fences.
func dress(builder: CompactMapBuilder) -> void:
	b=builder
	var nature:=b.nature
	nature.scan_clearance(b.arena)
	var noise:=FastNoiseLite.new();noise.seed=int(b.rng.seed);noise.frequency=.035;noise.fractal_octaves=3
	var lawn:=func(x:float,z:float)->float:
		var splat:=ground_splat(b,x,z,noise)
		var open:=1.0-smoothstep(.08,.4,maxf(maxf(splat.r*1.1,splat.g*1.1),splat.b*3.0))
		if open<=0.0 or block_distance(x,z)<.35:return 0.0
		return open*smoothstep(.32,.58,nature.plant_gap(x,z,.45,1.0))
	var half:=b.def.extent*.5
	nature.grass_field(Rect2(-half.x-.5,-half.y-.5,b.def.extent.x+1.0,b.def.extent.y+1.0),lawn,func(_x:float,_z:float)->float:return 0.0,.85,36.0,1.0)
	var verge:=func(x:float,z:float)->float:
		var d:=nature.outside(x,z)
		if d<1.2 or d>12.0:return 0.0
		return smoothstep(1.2,2.4,d)*(1.0-smoothstep(7.0,12.0,d))*smoothstep(.32,.58,nature.plant_gap(x,z,.45,1.0))
	nature.grass_field(Rect2(-half.x-13.0,-half.y-13.0,b.def.extent.x+26.0,b.def.extent.y+26.0),verge,func(x:float,z:float)->float:return nature.height(x,z),1.1,48.0,.8,Vector2(.7,1.4))

func crisp_sun() -> void:
	var sun:=b.arena.get_node_or_null("Sun") as DirectionalLight3D
	if sun==null:return
	sun.light_angular_distance=0.0
	b.arena.child_order_changed.disconnect(crisp_sun)

# --- Ground ---------------------------------------------------------------------------

func block_distance(x: float, z: float) -> float:
	var best:=INF
	for rect in blocks:
		var dx:=maxf(maxf(rect.position.x-x,x-rect.end.x),0.0);var dz:=maxf(maxf(rect.position.y-z,z-rect.end.y),0.0)
		best=minf(best,Vector2(dx,dz).length())
	return best

func path_distance(x: float, z: float) -> float:
	var best:=INF
	var p:=Vector2(x,z)
	for item in paths:
		var a:=Vector2(item[0].x,item[0].z);var c:=Vector2(item[1].x,item[1].z)
		var t:=clampf((p-a).dot(c-a)/(c-a).length_squared(),0,1)
		best=minf(best,p.distance_to(a+(c-a)*t)-float(item[2])*.5)
	return best

# R dirt (paths, yards, garden soil), G gravel (shoulders and building aprons),
# B cobbles (the main street and the square).
func ground_splat(_builder: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n:=noise.get_noise_2d(x,z)
	var fine:=noise.get_noise_2d(x*3.1+90.0,z*3.1-17.0)
	var street:=1.0-smoothstep(3.2,4.4,absf(z)+n*1.2)
	street*=1.0-smoothstep(47.0,51.0,absf(x)+n*2.0)
	var plaza:=(1.0-smoothstep(11.0,13.0,absf(x)+n*1.5))*(1.0-smoothstep(9.0,10.5,absf(z)+n*1.5))
	var cobble:=clampf(maxf(street,plaza)-smoothstep(.55,.85,fine)*.35,0,1)
	var shoulder:=(1.0-smoothstep(4.0,6.5,absf(z)+n*1.5))*(1.0-cobble)
	var apron:=1.0-smoothstep(.4,2.2,block_distance(x,z)+n*1.2)
	var gravel:=clampf(maxf(shoulder*.8,apron*.75),0,1)*(1.0-cobble)
	var track:=1.0-smoothstep(-.2,1.1,path_distance(x,z)+n*1.4)
	var yard:=(1.0-smoothstep(4.0,11.0,Vector2(absf(x)-45.0,absf(z)-18.0).length()+n*3.0))*.8
	var dirt:=clampf(maxf(maxf(track,yard),smoothstep(.45,.8,fine)*.5),0,1)*(1.0-cobble)
	return Color(dirt,gravel*(1.0-dirt*.5),cobble)
