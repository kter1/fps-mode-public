extends "res://game/maps/layouts/village.gd"

# Château Mirelle: a white French-château winery in the Georgia piedmont,
# laid out after a real estate (building footprint, drives and vineyards from
# OpenStreetMap, the 4-6 m fall of the ground flattened; name and signage are
# invented). The château faces east over a paved plaza with a fountain, a lawn
# with a giant chess set and the drive's turnaround. A grey production
# building is built onto its back.
#
# Inside, room by room after the real winery: the tasting room behind the arcade
# (double height, two oak flights up to its galleries); Marc, the restaurant, down
# the north wing with its bar at the far end and a glass porch beyond; the Bordeaux
# Tasting Room and the wine market in the south wing; the Velvet Room and a private
# dining room upstairs, and a balcony over the arcade. The grey building behind is
# the Cask Room (along the château) and production. The north lane follows the
# service drive past a stone carriage house; the south lane runs past a raised
# rotunda terrace, a garden house and the vineyards. Blue deploys from the
# visitor car park (west), red from the turnaround lawn (east).
#
# Built on the village layout's helpers (walls with real openings, stairs,
# trims, leaf cards, trees, grass); everything château-specific is here.

const UPPER := 4.4      # upper floor (walkable top of the slab)
const CEIL := 8.8       # underside of the attic slab
const EAVE := 9.4
const T := .6           # château wall thickness
const HALL_TOP := 7.0   # barrel hall roof
const S_CHESS := 16.0   # giant chess: the tabletop set scaled up
const TURN := Vector3(62,0,-40)   # centre of the drive's turnaround

# Openings: [width, sill, height].
const OPENINGS := {"door":[2.2,0.0,3.2],"arch":[2.0,0.0,3.7],"win":[1.4,.8,2.6],"up":[1.3,UPPER+.8,2.3],
	"french":[2.0,UPPER,2.8],"archwin":[1.6,.7,3.2],"updoor":[2.0,UPPER,2.7],"bay":[4.0,0.0,4.2],"wide":[4.0,0.0,3.6],"hallwin":[2.2,3.6,1.6]}

# Gravel courts and dirt vineyards for the ground splat (x, z, width, depth).
const GRAVEL := [Rect2(-42,-22,22,44),Rect2(-20,-30,20,14),Rect2(-20,16,20,14),Rect2(-8,-36,36,10),Rect2(0,-58,24,16)]
const VINES := [Rect2(-64,54,40,18),Rect2(26,54,40,18),Rect2(-64,-72,36,18),Rect2(28,-72,16,16)]

var roads: Array = []   # [from, to, width] asphalt
var rooms: Array[AABB] = []
var casks := PackedFloat32Array()     # lying casks, one MultiMesh (cask_mesh)
var bottles := PackedFloat32Array()   # wine bottles, one MultiMesh (bottle_mesh)
var decor := RandomNumberGenerator.new()   # interior dressing, kept off the layout's own stream

# --- Materials ---------------------------------------------------------------------

func stucco() -> ShaderMaterial: return scan("white_stucco",2.5,.3,"2k",Color(.98,.96,.91),.2,1.15)
func sandstone() -> ShaderMaterial: return scan("white_sandstone_blocks_02",1.6,.35)
func slate() -> ShaderMaterial: return scan("roof_slates_02",1.8,.1,"2k",Color(.4,.43,.48),.6,1.0)
func marble() -> ShaderMaterial: return scan("marble_tiles",2.4,.05)
func parquet() -> ShaderMaterial: return scan("herringbone_parquet",1.6,.05)
func terracotta() -> ShaderMaterial: return scan("terracotta_floor_tiles",2.0,.15)
func inner() -> ShaderMaterial: return plaster(Color(.94,.91,.85),.35)
func polished() -> ShaderMaterial: return scan("brushed_concrete",3.0,.12,"2k",Color(.6,.61,.6),.35,1.15)
func ink() -> ShaderMaterial: return b.surfaces.get_material("paint_concrete",Color("1f2021"))
func rough_oak() -> ShaderMaterial: return planks(Color(.66,.5,.33),.35,1.45)
func timber() -> ShaderMaterial: return planks(Color(.62,.46,.3),.4,1.5)
func soapstone() -> ShaderMaterial: return scan("roof_slates_02",1.2,0.0,"2k",Color(.25,.26,.27),.5,1.0)

# Plain (untextured) finish for leather, fabric, brass, paint and glass, cached.
func flat(color: Color, rough := .8, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key:="flat"+color.to_html()+str(Vector3(rough,metal,glow))
	if mats.has(key):return mats[key]
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=rough;mat.metallic=metal
	if glow>0:mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=glow
	mats[key]=mat
	return mat
func hall_wall() -> ShaderMaterial: return b.surfaces.get_material("paint_concrete",Color("a3a5a1"))

func trim_material(key: String) -> Material:
	match key:
		"sandstone":return sandstone()
		"stucco":return stucco()
		"slate":return slate()
		"iron":return b.surfaces.get_material("painted_metal",Color("27292a"))
		"steel":return b.surfaces.get_material("painted_metal",Color("bcc1c2"))
		"canvas_red":return b.surfaces.get_material("paint_concrete",Color("b4443b"))
		"canvas_cream":return b.surfaces.get_material("paint_concrete",Color("ece5d0"))
		"darkwood":return planks(Color(.3,.2,.13),.7)
		"marble":return marble()
		"darkslate":return soapstone()
		"oak":return rough_oak()
		"walnut":return planks(Color(.3,.2,.13),.7)
		"beadboard":return flat(Color(.62,.72,.6),.8,0.0,.3)
		"leather":return flat(Color(.5,.3,.15),.5)
		"leather_seam":return flat(Color(.3,.17,.08),.6)
		"leather_red":return flat(Color(.42,.08,.06),.5)
		"brass":return flat(Color(.8,.62,.34),.32,.9)
		"rattan":return flat(Color(.7,.55,.34),.85)
		"linen":return flat(Color(.92,.88,.8),.9)
		"lamp":return flat(Color(1.0,.86,.64),.5,0.0,2.5)
		"blue_rack":return b.surfaces.get_material("painted_metal",Color("2c5a99"))
		"sage":return b.surfaces.get_material("paint_concrete",Color("7b8a7b"))
		"pilaster":return b.surfaces.get_material("paint_concrete",Color("9a9c99"))
		"rug_red":return flat(Color(.3,.08,.07),.95)
		"rug_navy":return flat(Color(.09,.1,.15),.95)
		"rug_cream":return flat(Color(.55,.46,.34),.95)
		"paint_sky":return flat(Color(.62,.74,.86),.9)
		"paint_hill":return flat(Color(.36,.48,.42),.9)
		"paint_field":return flat(Color(.46,.58,.26),.9)
		"paint_row":return flat(Color(.2,.3,.12),.9)
		"canvas":return flat(Color(.82,.78,.7),.9)
	return super(key)

# --- Geometry ------------------------------------------------------------------------

# Hipped roof over a size.x by size.y rectangle (base at y = 0), the ridge along
# the longer side; equal sides make a pyramid. A soffit closes the underside.
func hip_mesh(size: Vector2, rise: float) -> ArrayMesh:
	var key:="chip"+str(size)+str(rise)
	if b.meshes.has(key):return b.meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx:=size.x*.5;var hz:=size.y*.5
	if hx>=hz:
		var r:=hx-hz
		add_poly(st,[Vector3(-hx,0,hz),Vector3(hx,0,hz),Vector3(r,rise,0),Vector3(-r,rise,0)],Vector3(0,hz,rise).normalized(),false)
		add_poly(st,[Vector3(hx,0,-hz),Vector3(-hx,0,-hz),Vector3(-r,rise,0),Vector3(r,rise,0)],Vector3(0,hz,-rise).normalized(),false)
		add_poly(st,[Vector3(hx,0,hz),Vector3(hx,0,-hz),Vector3(r,rise,0)],Vector3(rise,hz,0).normalized(),false)
		add_poly(st,[Vector3(-hx,0,-hz),Vector3(-hx,0,hz),Vector3(-r,rise,0)],Vector3(-rise,hz,0).normalized(),false)
	else:
		var r:=hz-hx
		add_poly(st,[Vector3(hx,0,hz),Vector3(hx,0,-hz),Vector3(0,rise,-r),Vector3(0,rise,r)],Vector3(rise,hx,0).normalized(),false)
		add_poly(st,[Vector3(-hx,0,-hz),Vector3(-hx,0,hz),Vector3(0,rise,r),Vector3(0,rise,-r)],Vector3(-rise,hx,0).normalized(),false)
		add_poly(st,[Vector3(-hx,0,hz),Vector3(hx,0,hz),Vector3(0,rise,r)],Vector3(0,hx,rise).normalized(),false)
		add_poly(st,[Vector3(hx,0,-hz),Vector3(-hx,0,-hz),Vector3(0,rise,-r)],Vector3(0,hx,-rise).normalized(),false)
	add_poly(st,[Vector3(-hx,0,-hz),Vector3(hx,0,-hz),Vector3(hx,0,hz),Vector3(-hx,0,hz)],Vector3.DOWN,false)
	st.index();st.generate_tangents()
	var mesh:=st.commit();mesh.lightmap_unwrap(Transform3D.IDENTITY,.4)
	b.meshes[key]=mesh
	return mesh

# Shallow dome (base radius r at y = 0, crown at rise).
func dome_mesh(r: float, rise: float) -> ArrayMesh:
	var key:="cdome"+str(Vector2(r,rise))
	if b.meshes.has(key):return b.meshes[key]
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings:=6;var segments:=20
	var point:=func(i:int,j:int)->Vector3:
		var t:=float(i)/rings*PI*.5;var a:=TAU*j/segments
		return Vector3(cos(t)*r*cos(a),sin(t)*rise,cos(t)*r*sin(a))
	for i in rings:
		for j in segments:
			var p0:Vector3=point.call(i,j);var p1:Vector3=point.call(i,j+1);var p2:Vector3=point.call(i+1,j+1);var p3:Vector3=point.call(i+1,j)
			var mid:=(p0+p1+p2+p3)*.25
			var n:=Vector3(mid.x/(r*r),mid.y/(rise*rise),mid.z/(r*r)).normalized()
			add_poly(st,[p0,p1,p2,p3] if i<rings-1 else [p0,p1,p2],n,false)
	st.index();st.generate_tangents()
	var mesh:=st.commit();mesh.lightmap_unwrap(Transform3D.IDENTITY,.4)
	b.meshes[key]=mesh
	return mesh

# Cylinder with a scanned material and (optionally) a matching collider.
func drum(center: Vector3, radius: float, height: float, mat: Material, solid := true, label := "ChateauDrum") -> Node3D:
	var key:="cdrum"+str(Vector2(radius,height))
	if not b.meshes.has(key):
		var mesh:=MapMeshes.cylinder(radius,height,clampi(roundi(radius*30),12,40),0.0)
		mesh.lightmap_unwrap(Transform3D.IDENTITY,.3);b.meshes[key]=mesh
	var item:=node(b.region,label,center)
	visual(item,b.meshes[key],mat)
	if solid:
		var shape:=CylinderShape3D.new();shape.radius=radius;shape.height=height
		body(item,[[Vector3.ZERO,shape]],"concrete")
	return item

# Masonry flight rising along xf's local +x from local x = 0, centred on z = 0.
# One wedge collider under the nosings (23 degrees: walkable, nothing to crawl
# under), ending 5 cm proud of the landing.
func flight(xf: Transform3D, steps: int, width: float, mat: Material) -> void:
	var run:=STEP_GO*steps;var top:=STEP_RISE*steps
	var key:="cflight"+str(Vector2(steps,width))
	if not b.meshes.has(key):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in steps:
			var h:=(k+1)*STEP_RISE
			st.append_from(MapMeshes.block(Vector3(STEP_GO,h,width),.015,.4),0,Transform3D(Basis.IDENTITY,Vector3((k+.5)*STEP_GO,h*.5,0)))
		var mesh:=st.commit();mesh.lightmap_unwrap(Transform3D.IDENTITY,.3);b.meshes[key]=mesh
	var item:=node(b.region,"ChateauStair",xf.origin,xf.basis.get_euler())
	visual(item,b.meshes[key],mat)
	var w:=width*.5
	var hull:=ConvexPolygonShape3D.new()
	hull.points=PackedVector3Array([Vector3(-.19,0,-w),Vector3(-.19,0,w),Vector3(run,0,-w),Vector3(run,0,w),Vector3(run,top+.05,-w),Vector3(run,top+.05,w)])
	body(item,[[Vector3.ZERO,hull]],"concrete")
	# Handrails on both sides.
	var slope:=atan2(top,run)
	for side:float in [-1.0,1.0]:
		trim(xf*Transform3D(Basis(Vector3.BACK,slope),Vector3(run*.5,top*.5+.95,side*(w-.06))),Vector3(sqrt(run*run+top*top),.06,.06),"iron")
		for k in range(0,steps,3):
			trim(xf*Transform3D(Basis.IDENTITY,Vector3((k+.5)*STEP_GO,(k+1)*STEP_RISE+.47,side*(w-.06))),Vector3(.04,.94,.04),"iron")

# A wall of the château from a to c (outward to the right of a->c seen from
# above) with openings from OPENINGS at [distance from a, kind]; stone
# surrounds, arches, sills, casements and a plinth band when dressed.
func facade(a: Vector3, c: Vector3, height: float, thick: float, spec: Array, mat: Material, dress := true) -> void:
	var dir:=(c-a).normalized();var out:=Vector3(-dir.z,0,dir.x)
	var turn:=Basis(Vector3.UP,atan2(-dir.z,dir.x))
	var rects:=[]
	for item in spec:
		var size:Array=OPENINGS[item[1]]
		rects.append(Rect2(float(item[0])-float(size[0])*.5,float(size[1]),float(size[0]),float(size[2])))
	wall(b.region,Transform3D.IDENTITY,a,c,height,thick,rects,mat,"","concrete")
	if not dress:return
	var length:=a.distance_to(c)
	var cuts:Array[Vector2]=[]
	for i in spec.size():
		var rect:Rect2=rects[i]
		var mid:=a+dir*(rect.position.x+rect.size.x*.5)+Vector3.UP*(rect.position.y+rect.size.y*.5)
		surround(turn,mid,out,rect.size,thick,String(spec[i][1]))
		daylight(mid-out*(thick*.5+.15)+Vector3.UP*rect.size.y*.25,-out,rect.size)
		if rect.position.y<.05:cuts.append(Vector2(rect.position.x-.25,rect.end.x+.25))
	# Sandstone plinth band, broken at the doors.
	cuts.sort_custom(func(p:Vector2,q:Vector2):return p.x<q.x)
	var cursor:=0.0
	cuts.append(Vector2(length,length))
	for cut in cuts:
		if cut.x-cursor>.1:
			var mid:=a+dir*(cursor+cut.x)*.5+out*(thick*.5+.05)+Vector3.UP*.35
			trim(Transform3D(turn,mid),Vector3(cut.x-cursor,.7,.1),"sandstone")
		cursor=maxf(cursor,cut.y)

# Sky light falling in through an opening: a soft, cool spot just inside it, aimed
# into the room and down (fully baked, so it costs nothing at run time).
func daylight(at: Vector3, inward: Vector3, size: Vector2) -> void:
	var lamp:=SpotLight3D.new();lamp.name="ChateauDaylight"+str(b.serial);b.serial+=1
	lamp.transform=Transform3D(Basis.looking_at((inward+Vector3.DOWN*.45).normalized(),Vector3.UP),at)
	lamp.light_color=Color(.86,.92,1.0);lamp.light_energy=.8+size.x*size.y*.11;lamp.light_indirect_energy=1.3;lamp.light_specular=0.0
	lamp.spot_range=7.5+size.y;lamp.spot_angle=62.0;lamp.spot_attenuation=1.1;lamp.spot_angle_attenuation=.6
	lamp.shadow_enabled=true;lamp.light_size=maxf(size.x,1.0)
	lamp.light_bake_mode=Light3D.BAKE_STATIC
	b.region.add_child(lamp)

func surround(turn: Basis, mid: Vector3, out: Vector3, size: Vector2, thick: float, kind: String) -> void:
	var face:=out*(thick*.5+.04)
	var along:=turn*Vector3.RIGHT
	var hx:=size.x*.5;var hy:=size.y*.5
	for side:float in [-1.0,1.0]:
		trim(Transform3D(turn,mid+face+along*side*(hx+.11)),Vector3(.22,size.y,.08),"sandstone")
	trim(Transform3D(turn,mid+face+Vector3.UP*(hy+.13)),Vector3(size.x+.44,.26,.1),"sandstone")
	if kind in ["arch","door","wide","bay","updoor","french","archwin"]:
		trim(Transform3D(turn,mid+face+out*.03+Vector3.UP*(hy+.08)),Vector3(.34,.46,.1),"sandstone")
	if kind in ["arch","archwin"]:
		# Round the top corners through the wall's depth, voussoirs on the face.
		var n:=10
		for k in n:
			var x:=-hx+(k+.5)*size.x/n
			var gap:=hx-sqrt(maxf(hx*hx-x*x,0.0))
			if gap>.02:trim(Transform3D(turn,mid+along*x+Vector3.UP*(hy-gap*.5)),Vector3(size.x/n+.01,gap,thick+.02),"stucco")
		for k in 9:
			var a:=PI*(k+.5)/9.0
			var p:=mid+Vector3.UP*(hy-hx)+along*cos(a)*(hx+.12)+Vector3.UP*sin(a)*(hx+.12)+face
			trim(Transform3D(turn*Basis(Vector3.BACK,a-PI*.5),p),Vector3(.3,.24,.09),"sandstone")
	if kind in ["win","up","hallwin","archwin"]:
		trim(Transform3D(turn,mid+face+out*.06+Vector3.DOWN*(hy+.04)),Vector3(size.x+.32,.08,.2),"sandstone")
		# Casement frame standing open: the panes are gone, the iron glazing bars remain.
		trim(Transform3D(turn,mid),Vector3(.05,size.y-.1,.05),"iron")
		if kind=="archwin":
			# Transom at the springing, a fanlight of radiating bars above it.
			var spring:=mid+Vector3.UP*(hy-hx)
			trim(Transform3D(turn,spring),Vector3(size.x-.1,.05,.05),"iron")
			for a in [PI*.25,PI*.75]:trim(Transform3D(turn*Basis(Vector3.BACK,a),spring+(along*cos(a)+Vector3.UP*sin(a))*hx*.5),Vector3(hx,.04,.04),"iron")
		else:
			for y in [-.3,.25]:trim(Transform3D(turn,mid+Vector3.UP*hy*y*2.0),Vector3(size.x-.1,.04,.04),"iron")
	if kind in ["up","french"]:
		# Wrought-iron guard across the lower part of the opening.
		var low:=mid+face+out*.1+Vector3.DOWN*(hy-.55 if kind=="up" else hy-1.0)
		trim(Transform3D(turn,low),Vector3(size.x,.04,.04),"iron")
		for k in int(size.x/.14):trim(Transform3D(turn,low+along*(-hx+(k+.5)*.14)+Vector3.DOWN*.25),Vector3(.025,.5,.025),"iron")
	if kind in ["door","updoor","french"]:
		# Two leaves swung open into the room.
		for side:float in [-1.0,1.0]:
			var hinge:=mid-out*(thick*.5)+along*side*(hx-.04)
			trim(Transform3D(turn*Basis(Vector3.UP,PI*.5),hinge-out*(hx*.5-.03)+Vector3.DOWN*.02),Vector3(hx-.06,size.y-.06,.06),"darkwood")

# Plain bevelled slab of a floor (walkable top at top).
func slab(label: String, x0: float, x1: float, z0: float, z1: float, top: float, mat: Material, ceiling := true) -> void:
	piece(b.region,label,Vector3((x0+x1)*.5,top-.15,(z0+z1)*.5),Vector3(x1-x0,.3,z1-z0),mat,true,"wood",Vector3.ZERO,0.0)
	if ceiling:piece(b.region,"ChateauCeiling",Vector3((x0+x1)*.5,top-.31,(z0+z1)*.5),Vector3(x1-x0,.02,z1-z0),ink(),false,"concrete",Vector3.ZERO,0.0)

# Solid balustrade on a gallery edge: sandstone plinth and rail, turned balusters.
func balustrade(a: Vector3, c: Vector3, height := 1.0) -> void:
	var d:=c-a;var length:=Vector2(d.x,d.z).length();var mid:=(a+c)*.5
	var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var item:=node(b.region,"ChateauBalustrade",mid,Vector3(0,yaw,0))
	body(item,[[Vector3(0,height*.5,0),Vector3(length,height,.2)]],"concrete")
	trim(Transform3D(turn,mid+Vector3.UP*.08),Vector3(length,.16,.26),"sandstone")
	trim(Transform3D(turn,mid+Vector3.UP*(height-.06)),Vector3(length+.06,.12,.28),"sandstone")
	for k in int(length/.32):
		trim(Transform3D(turn,mid+d.normalized()*(-length*.5+(k+.5)*length/int(length/.32))+Vector3.UP*(height*.5+.02)),Vector3(.11,height-.28,.11),"sandstone")

func cv(point: Vector3, peek: Vector3) -> void:
	b.def.cover_points.append(point);b.def.cover_peeks.append(peek)

func fill(p: Vector3, reach: float, energy := 1.0) -> void:
	fill_light(p,reach,energy)

# --- Planting ---------------------------------------------------------------------------

# Deeper summer green with a soft sheen: the shared leaf cards otherwise flash
# white along the sunlit rim of each crown.
func foliage_material(id: String, tint: Color) -> ShaderMaterial:
	var mat:=super(id,tint*Color(.84,.9,.78))
	mat.set_shader_parameter("leaf_specular",.12);mat.set_shader_parameter("leaf_roughness",.82)
	return mat

# A kept estate lawn rather than Village's meadow: short, dense, muted turf.
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
	nature.grass_field(Rect2(-half.x-.5,-half.y-.5,b.def.extent.x+1.0,b.def.extent.y+1.0),lawn,func(_x:float,_z:float)->float:return 0.0,.62,36.0,1.15,Vector2(.24,.5))
	var verge:=func(x:float,z:float)->float:
		var d:=nature.outside(x,z)
		if d<1.2 or d>12.0:return 0.0
		return smoothstep(1.2,2.4,d)*(1.0-smoothstep(7.0,12.0,d))*smoothstep(.32,.58,nature.plant_gap(x,z,.45,1.0))
	nature.grass_field(Rect2(-half.x-13.0,-half.y-13.0,b.def.extent.x+26.0,b.def.extent.y+26.0),verge,func(x:float,z:float)->float:return nature.height(x,z),1.1,48.0,.8,Vector2(.7,1.4))
	for fade in [32.0,44.0]:
		var mat:ShaderMaterial=nature.grass_material(fade)
		mat.set_shader_parameter("fresh",Color(.4,.62,.27));mat.set_shader_parameter("dry",Color(.6,.62,.34))

# --- Château ---------------------------------------------------------------------------

func chateau() -> void:
	blocks.append(Rect2(0,-26,22,52))
	var white:=stucco()
	# East front: the arcade into the tasting room and French doors to the balcony above it;
	# Marc's round-headed windows in the north wing, plain windows in the south.
	var east:=[]
	for z in [-5.6,-2.8,0.0,2.8,5.6]:east.append([25.4-z,"arch"])
	for z in [-4.0,0.0,4.0]:east.append([25.4-z,"french"])
	for s:float in [-1.0,1.0]:
		for z in [11.0,18.5]:east.append([25.4-s*z,"archwin" if s<0 else "win"]);east.append([25.4-s*z,"up"])
		east.append([25.4-s*22.5,"door"]);east.append([25.4-s*22.5,"up"])
	facade(Vector3(22-T*.5,0,25.4),Vector3(22-T*.5,0,-25.4),EAVE,T,east,white)
	# West back: openings into the Cask Room, doors to the side yards.
	var west:=[[25.4-8.5,"door"],[25.4,"wide"],[25.4+8.5,"door"]]
	for s:float in [-1.0,1.0]:
		west.append([25.4+s*23.5,"door"]);west.append([25.4+s*23.5,"up"]);west.append([25.4+s*18.0,"up"])
	facade(Vector3(T*.5,0,-25.4),Vector3(T*.5,0,25.4),EAVE,T,west,white)
	# North end: Marc's door onto the glass porch and a blank wall behind its bar (east).
	facade(Vector3(22,0,-26+T*.5),Vector3(0,0,-26+T*.5),EAVE,T,[[11.0,"door"],[11.0,"up"],[4.5,"up"],[17.5,"win"],[17.5,"up"]],white)
	facade(Vector3(0,0,26-T*.5),Vector3(22,0,26-T*.5),EAVE,T,[[11.0,"door"],[11.0,"up"],[4.5,"win"],[4.5,"up"],[17.5,"win"],[17.5,"up"]],white)
	# Tasting room partitions: doors on both floors into the wings.
	for s:float in [-1.0,1.0]:
		var a:=Vector3(T,0,s*7.0);var c:=Vector3(22-T,0,s*7.0)
		if s>0:var swap:=a;a=c;c=swap
		var at:=func(x:float)->float:return x-T if s<0 else 22-T-x
		wall(b.region,Transform3D.IDENTITY,a,c,CEIL,.4,[Rect2(at.call(5.2)-1.2,0,2.4,3.2),Rect2(at.call(19.0)-1.2,0,2.4,3.2),Rect2(at.call(3.3)-1.0,UPPER,2.0,2.7),Rect2(at.call(19.0)-1.0,UPPER,2.0,2.7)],inner(),"","concrete")
	# South wing: the Bordeaux Tasting Room (front) and the wine market (end). Marc keeps
	# the north wing in one long room.
	wall(b.region,Transform3D.IDENTITY,Vector3(22-T,0,15.0),Vector3(3.0,0,15.0),UPPER-.3,.3,[Rect2(22-T-7.5-1.2,0,2.4,3.0),Rect2(22-T-16.0-1.2,0,2.4,3.0)],inner(),"","concrete")
	floors()
	stairs_inside()
	balcony()
	body_trim()
	roofs()
	tasting_room()
	marc()
	porch()
	south_wing()
	upstairs()

func floors() -> void:
	# Polished concrete in the tasting room and the south wing, herringbone oak through Marc.
	piece(b.region,"ChateauFloor",Vector3(11,.02,0),Vector3(22-T*2,.04,13.6),polished(),false,"concrete",Vector3.ZERO,0.0)
	piece(b.region,"ChateauFloor",Vector3(11,.02,-16.3),Vector3(22-T*2,.04,18.2),parquet(),false,"wood",Vector3.ZERO,0.0)
	piece(b.region,"ChateauFloor",Vector3(11,.02,16.3),Vector3(22-T*2,.04,18.2),polished(),false,"concrete",Vector3.ZERO,0.0)
	for s:float in [-1.0,1.0]:
		# Upstairs: the Velvet Room's reclaimed boards (north), parquet in the private dining room
		# (south); each wing's floor runs round its service stair well (x 0.6-3.0, from 1 m
		# above the flight's foot to its head).
		var boards:=floorboards() if s<0 else parquet()
		var z_foot:=s*19.5;var z_head:=s*10.05
		slab("ChateauSlab",3.0,22-T,minf(s*25.4,s*7.2),maxf(s*25.4,s*7.2),UPPER,boards)
		slab("ChateauSlab",T,3.0,minf(s*25.4,z_foot),maxf(s*25.4,z_foot),UPPER,boards)
		slab("ChateauSlab",T,3.0,minf(z_head,s*7.2),maxf(z_head,s*7.2),UPPER,boards)
		railing(Vector3(3.06,UPPER,z_foot),Vector3(3.06,UPPER,z_head))
		railing(Vector3(T,UPPER,z_foot+s*.06),Vector3(3.0,UPPER,z_foot+s*.06))
		# Gallery strips beside the void.
		slab("ChateauGallery",6.0,16.6,minf(s*6.8,s*4.5),maxf(s*6.8,s*4.5),UPPER,parquet())
		railing(Vector3(6.0,UPPER,s*4.56),Vector3(16.6,UPPER,s*4.56))
	slab("ChateauGallery",T,6.0,-6.8,6.8,UPPER,parquet())
	slab("ChateauGallery",16.6,22-T,-6.8,6.8,UPPER,parquet())
	railing(Vector3(6.06,UPPER,-2.1),Vector3(6.06,UPPER,2.1))
	railing(Vector3(16.54,UPPER,-4.5),Vector3(16.54,UPPER,4.5))
	# Attic slab over everything: the black-painted deck of the tasting room and the upstairs rooms.
	piece(b.region,"ChateauAttic",Vector3(11,CEIL+.15,0),Vector3(22-T*2,.3,52-T*2),ink(),true,"concrete",Vector3.ZERO,0.0)
	# Open-web steel joists under every ceiling, clear of the service stair wells.
	joists(Vector3(11,CEIL,0),13.6,22-T*2,PI*.5,1.6)
	for s:float in [-1.0,1.0]:
		joists(Vector3(12.2,UPPER-.31,s*16.3),18.4,18.2,0.0)
		joists(Vector3(11,CEIL,s*16.3),22-T*2,18.2,0.0)
	rooms.append(AABB(Vector3(T,0,-6.8),Vector3(22-T*2,CEIL,13.6)))
	rooms.append(AABB(Vector3(T,0,-25.4),Vector3(22-T*2,UPPER-.3,18.2)))
	rooms.append(AABB(Vector3(T,0,7.2),Vector3(22-T*2,UPPER-.3,7.8)))
	rooms.append(AABB(Vector3(T,0,15.0),Vector3(22-T*2,UPPER-.3,10.4)))
	for s:float in [-1.0,1.0]:rooms.append(AABB(Vector3(T,UPPER,minf(s*25.4,s*7.2)),Vector3(22-T*2,CEIL-UPPER,18.2)))

func stairs_inside() -> void:
	# Two oak flights in the tasting room rising west to the gallery.
	for s:float in [-1.0,1.0]:
		flight(Transform3D(Basis(Vector3.UP,PI),Vector3(16.45,0,s*3.3)),22,2.4,planks(Color(.45,.32,.21),.5))
		# Service stairs along the west wall of each wing, rising toward the tasting room.
		flight(Transform3D(Basis(Vector3.UP,PI*.5*s),Vector3(1.8,0,s*20.5)),22,2.4,polished())

func balcony() -> void:
	piece(b.region,"ChateauBalcony",Vector3(23.3,UPPER-.15,0),Vector3(2.6,.3,16.4),sandstone(),true,"concrete",Vector3.ZERO,0.0)
	balustrade(Vector3(24.5,UPPER,-8.2),Vector3(24.5,UPPER,8.2))
	for s:float in [-1.0,1.0]:balustrade(Vector3(22,UPPER,s*8.1),Vector3(24.6,UPPER,s*8.1))
	for z in [-7.0,-4.2,-1.4,1.4,4.2,7.0]:
		drum(Vector3(24.2,(UPPER-.3)*.5,z),.22,UPPER-.3,sandstone(),true,"ChateauColumn")
		piece(b.region,"ChateauCapital",Vector3(24.2,UPPER-.42,z),Vector3(.55,.24,.55),sandstone(),false)
		piece(b.region,"ChateauBase",Vector3(24.2,.1,z),Vector3(.55,.2,.55),sandstone(),false)

# Cornice, string course and quoins.
func body_trim() -> void:
	for band in [[EAVE-.25,.5,.45],[UPPER-.12,.24,.14]]:
		var y:float=band[0];var h:float=band[1];var d:float=band[2]
		trim(Transform3D(Basis.IDENTITY,Vector3(11,y,-26-d*.5)),Vector3(22+d*2,h,d),"sandstone")
		trim(Transform3D(Basis.IDENTITY,Vector3(11,y,26+d*.5)),Vector3(22+d*2,h,d),"sandstone")
		trim(Transform3D(Basis.IDENTITY,Vector3(22+d*.5,y,0)),Vector3(d,h,52),"sandstone")
		if y>HALL_TOP:trim(Transform3D(Basis.IDENTITY,Vector3(-d*.5,y,0)),Vector3(d,h,52),"sandstone")
		else:
			for s:float in [-1.0,1.0]:trim(Transform3D(Basis.IDENTITY,Vector3(-d*.5,y,s*21.0)),Vector3(d,h,10),"sandstone")
	# Quoins: alternating long and short blocks at the corners and the pavilion edges.
	var edges:=[[Vector3(22,0,-26),Vector3(1,0,0),Vector3(0,0,-1)],[Vector3(22,0,26),Vector3(1,0,0),Vector3(0,0,1)],
		[Vector3(0,0,-26),Vector3(-1,0,0),Vector3(0,0,-1)],[Vector3(0,0,26),Vector3(-1,0,0),Vector3(0,0,1)]]
	for item in edges:
		var corner:Vector3=item[0];var nx:Vector3=item[1];var nz:Vector3=item[2]
		for k in int(EAVE/.5):
			var long:=k%2==0;var y:=k*.5+.25
			trim(Transform3D(Basis.IDENTITY,corner+nx*.05+nz*(-(.45 if long else .3))+Vector3.UP*y),Vector3(.1,.42,.9 if long else .6),"sandstone")
			trim(Transform3D(Basis.IDENTITY,corner+nz*.05+nx*(-(.3 if long else .45))+Vector3.UP*y),Vector3(.6 if long else .9,.42,.1),"sandstone")
	for z in [-14.0,-7.0,7.0,14.0]:
		for k in int(EAVE/.5):
			if z*z<60 and k*.5<UPPER:continue  # the arcade's corner piers
			trim(Transform3D(Basis.IDENTITY,Vector3(22.05,k*.5+.25,z)),Vector3(.1,.42,.9 if k%2==0 else .6),"sandstone")

func roofs() -> void:
	var main:=node(b.region,"ChateauRoof",Vector3(11,EAVE,0))
	visual(main,hip_mesh(Vector2(23.0,53.0),9.0),slate())
	for z in [-20.0,0.0,20.0]:
		var wide:=14.8 if z==0 else 12.8
		var rise:=13.0 if z==0 else 12.0
		var item:=node(b.region,"ChateauPavilionRoof",Vector3(11,EAVE,z))
		visual(item,hip_mesh(Vector2(23.4,wide),rise),slate())
		var ridge:=11.7-wide*.5
		trim(Transform3D(Basis.IDENTITY,Vector3(11,EAVE+rise+.1,z)),Vector3(ridge*2+.2,.18,.18),"iron")
		for s:float in [-1.0,1.0]:
			trim(Transform3D(Basis.IDENTITY,Vector3(11+s*ridge,EAVE+rise+.8,z)),Vector3(.08,1.5,.08),"iron")
			trim(Transform3D(Basis.IDENTITY,Vector3(11+s*ridge,EAVE+rise+.55,z)),Vector3(.22,.22,.22),"iron")
		# Dormers low on the pavilion's east face.
		for dz in ([-3.2,3.2] if z==0 else [0.0]):dormer(Vector3(22.2,EAVE+.1,z+dz),1.0,2.6)
	trim(Transform3D(Basis.IDENTITY,Vector3(11,EAVE+9.08,0)),Vector3(.18,.16,30.2),"iron")
	for s:float in [-1.0,1.0]:
		for x_side:float in [1.0,-1.0]:dormer(Vector3(11+x_side*11.2,EAVE+.1,s*10.5),x_side)
		# Chimney stacks.
		for x in [4.0,18.0]:
			piece(b.region,"ChateauChimney",Vector3(x,EAVE+5.5,s*10.5),Vector3(.9,5.4,1.5),stucco(),false,"concrete",Vector3.ZERO,.1)
			piece(b.region,"ChateauChimneyCap",Vector3(x,EAVE+8.3,s*10.5),Vector3(1.1,.2,1.7),sandstone(),false)
	# Production building: flat roof with a parapet and plant on it.
	piece(b.region,"HallRoof",Vector3(-10,HALL_TOP-.15,0),Vector3(20,.3,32),b.surfaces.get_material("rough_concrete"),true,"concrete",Vector3.ZERO,0.0)
	for side:float in [-1.0,1.0]:
		trim(Transform3D(Basis.IDENTITY,Vector3(-10,HALL_TOP+.2,side*15.9)),Vector3(20,.4,.25),"steel")
	trim(Transform3D(Basis.IDENTITY,Vector3(-19.9,HALL_TOP+.2,0)),Vector3(.25,.4,32),"steel")
	for z in [-9.0,4.0]:b.props.place("exterior_aircon_unit",b.props.grounded("exterior_aircon_unit",Vector3(-12,HALL_TOP,z),PI*.5),false,160.0)

# A dormer window standing on the roof slope (front face toward +x * facing).
func dormer(front: Vector3, facing: float, height := 2.2) -> void:
	var c:=front+Vector3(-facing*1.0,height*.5,0)
	piece(b.region,"ChateauDormer",c,Vector3(2.0,height,1.6),stucco(),false,"concrete",Vector3.ZERO,.1)
	var turn:=Basis(Vector3.UP,-PI*.5 if facing>0 else PI*.5)
	var glass:=front+Vector3(0,height*.6,0)
	trim(Transform3D(turn,glass+Vector3(.02*facing,0,0)),Vector3(.9,1.3,.06),"iron")
	for side:float in [-1.0,1.0]:trim(Transform3D(turn,glass+Vector3(.04*facing,0,side*.55)),Vector3(.18,1.5,.08),"sandstone")
	var cap:=node(b.region,"ChateauDormerRoof",c+Vector3(0,height*.5,0))
	visual(cap,hip_mesh(Vector2(2.3,1.9),1.1),slate())

# The grey production building on the château's back: the Cask Room along the château
# (oak casks racked down both walls, chandeliers over a long table) and the production
# room behind it (stainless tanks, blue steel barrel racks); bay doors west, service
# doors north and south.
func barrel_hall() -> void:
	blocks.append(Rect2(-20,-16,20,32))
	var grey:=hall_wall()
	var t:=.4;var h:=HALL_TOP+.4
	facade(Vector3(-20+t*.5,0,-16+t),Vector3(-20+t*.5,0,16-t),h,t,[[15.6-7.0,"bay"],[15.6+7.0,"bay"],[15.6-12.5,"hallwin"],[15.6,"hallwin"],[15.6+12.5,"hallwin"]],grey,false)
	facade(Vector3(0,0,-16+t*.5),Vector3(-20,0,-16+t*.5),h,t,[[10.0,"wide"],[4.0,"hallwin"],[16.0,"hallwin"]],grey,false)
	facade(Vector3(-20,0,16-t*.5),Vector3(0,0,16-t*.5),h,t,[[10.0,"wide"],[4.0,"hallwin"],[16.0,"hallwin"]],grey,false)
	piece(b.region,"HallFloor",Vector3(-10,.02,0),Vector3(19.6,.04,31.2),b.surfaces.get_material("concrete_floor"),false,"concrete",Vector3.ZERO,0.0)
	# Rolled-up steel doors over the bays.
	for z in [-7.0,7.0]:trim(Transform3D(Basis.IDENTITY,Vector3(-19.6,4.45,z)),Vector3(.6,.5,4.3),"steel")
	# Stone wall between the Cask Room and production: a wide opening in line with the
	# château's, a door either side.
	wall(b.region,Transform3D.IDENTITY,Vector3(-7.6,0,-15.6),Vector3(-7.6,0,15.6),HALL_TOP-.3,.3,[Rect2(4.1-1.2,0,2.4,3.0),Rect2(13.6,0,4.0,3.6),Rect2(27.1-1.2,0,2.4,3.0)],stone(),"","concrete")
	# Production: stainless fermentation tanks on plinths, with cone tops and ladders.
	for p in [Vector3(-14.5,0,0),Vector3(-14.5,0,-12.2),Vector3(-14.5,0,12.2),Vector3(-10.6,0,-6.0),Vector3(-10.6,0,6.0)]:
		piece(b.region,"HallTankPlinth",p+Vector3(0,.15,0),Vector3(3.1,.3,3.1),b.surfaces.get_material("concrete"),true)
		tank(p+Vector3(0,3.05,0),1.4,5.5,true)
		tank(p+Vector3(0,5.95,0),.9,.3)
		tank(p+Vector3(0,6.25,0),.35,.3)
		for k in 3:trim(Transform3D(Basis.IDENTITY,p+Vector3(1.45,.8+k*1.9,0)),Vector3(.08,.08,.5),"steel")
		cv(p+Vector3(0,0,signf(p.z+.1)*2.4),p+Vector3(1.6,0,signf(p.z+.1)*2.4))
	# Blue steel racks along the west wall, three casks high, clear of the bay doors.
	for span in [[-15.2,-9.4],[-4.6,4.6],[9.4,15.2]]:
		cask_rack(Vector3(-18.9,0,float(span[0])),Vector3(-18.9,0,float(span[1])),3,"blue_rack")
		cv(Vector3(-17.8,0,float(span[1])+.6),Vector3(-17.8,0,float(span[1])-1.4))
	for s:float in [-1.0,1.0]:fill(Vector3(-13.5,HALL_TOP-1.2,s*7.5),11.0,1.0)
	rooms.append(AABB(Vector3(-19.6,0,-15.6),Vector3(11.85,HALL_TOP-.3,31.2)))
	# Cask Room: two casks high down both long walls and across the ends, a long table
	# either side of the walk-through, chandeliers.
	for span in [[-14.5,-13.0],[-10.0,-2.3],[2.3,10.0],[13.0,14.5]]:cask_rack(Vector3(-6.95,0,float(span[0])),Vector3(-6.95,0,float(span[1])),2,"oak")
	for span in [[-14.5,-9.9],[-7.1,-2.3],[2.3,7.1],[9.9,14.5]]:cask_rack(Vector3(-.5,0,float(span[0])),Vector3(-.5,0,float(span[1])),2,"oak")
	for s:float in [-1.0,1.0]:
		cask_rack(Vector3(-6.3,0,s*15.1),Vector3(-1.1,0,s*15.1),2,"oak")
		var p:=Vector3(-3.7,0,s*6.05)
		table(p,Vector2(1.1,6.9),.76,"walnut")
		for k in 9:
			for side:float in [-1.0,1.0]:chair(p+Vector3(side*.82,0,-3.0+k*.75),atan2(-side,0.0),"wood")
		for z in [3.6,8.4]:chandelier(Vector3(-3.7,HALL_TOP-.3,s*z),1.1)
		cv(Vector3(-5.4,0,s*2.0),Vector3(-5.4,0,s*3.2));cv(Vector3(-2.0,0,s*9.8),Vector3(-2.0,0,s*8.6))
	fill(Vector3(-3.7,HALL_TOP-1.0,0),12.0,.9)
	rooms.append(AABB(Vector3(-7.45,0,-15.6),Vector3(7.45,HALL_TOP-.3,31.2)))

# A rank of upright oak barrels (solid), optionally a second tier on top.
func barrels(p: Vector3, yaw: float, count: int, stacked := false) -> void:
	var along:=Basis(Vector3.UP,yaw)*Vector3.RIGHT
	for i in count:
		var q:=p+along*(i-(count-1)*.5)*.82
		b.prop("wine_barrel_01",q,.87,yaw+decor.randf_range(-.3,.3))
		if stacked and i<count-1 and i%2==0:b.prop("wine_barrel_01",q+along*.41+Vector3.UP*.87,.87,yaw+decor.randf_range(-.3,.3),false)

func chandelier(top: Vector3, height: float) -> void:
	b.prop("lantern_chandelier_01",top-Vector3(0,height,0),height,0.0,false)
	b.bake_light(top-Vector3(0,height*.7,0),Color(1.0,.8,.56),1.6,height*7.0)

# --- Winery interior --------------------------------------------------------------------
# Room by room after the real winery's own photographs (chateauelan.com: the tasting room,
# Marc and its bar and glass porch, the Bordeaux Tasting Room, the Velvet Room and the Cask
# Room). Black steel joists, ducts and timber posts throughout.

# The tasting room behind the arcade: a rough-sawn oak island bar, a second bar against oak
# wine shelving, camel leather banquettes under the galleries, a wall of barrel heads, a
# vineyard painting, brass and rattan pendants and a crystal chandelier.
func tasting_room() -> void:
	piece(b.region,"ChateauBar",Vector3(7.8,.52,0),Vector3(1.4,1.04,5.0),rough_oak(),true,"wood",Vector3.ZERO,.1)
	piece(b.region,"ChateauBarTop",Vector3(7.8,1.09,0),Vector3(1.75,.1,5.4),rough_oak(),false,"wood",Vector3.ZERO,0.0)
	for side:float in [-1.0,1.0]:trim(Transform3D(Basis.IDENTITY,Vector3(7.8+side*.82,.22,0)),Vector3(.05,.05,4.8),"brass")
	for z in [-2.1,.9]:bottle_row(Vector3(7.65,1.14,z),Vector3(7.65,1.14,z+.3))
	for z in [-.9,2.0]:b.props.scatter("wine_bottles_01",b.props.grounded("wine_bottles_01",Vector3(7.8,1.14,z),decor.randf()*TAU,.5))
	for z in [-1.6,0.0,1.6]:pendant(Vector3(7.8,3.3,z),CEIL,"dome",z==0.0)
	cv(Vector3(9.0,0,-1.6),Vector3(9.0,0,-3.2));cv(Vector3(6.6,0,1.6),Vector3(6.6,0,3.2))
	# Timber posts under the gallery strips.
	for s:float in [-1.0,1.0]:
		for x in [6.2,11.3,16.3]:drum(Vector3(x,(UPPER-.31)*.5,s*4.75),.16,UPPER-.31,timber(),true,"ChateauPost")
		# Banquettes under the galleries, walnut tables, iron bistro chairs, rattan pendants.
		banquette(Vector3(6.7,0,s*6.5),Vector3(9.9,0,s*6.5),Vector3(0,0,-s))
		for x in [7.2,8.4,9.6]:
			table(Vector3(x,0,s*5.65),Vector2(.6,.6),.75,"walnut")
			chair(Vector3(x,0,s*5.0),0.0 if s>0 else PI,"iron")
			pendant(Vector3(x,3.0,s*5.65),UPPER-.31,"rattan",x==8.4)
		cv(Vector3(10.4,0,s*5.6),Vector3(10.4,0,s*3.6))
	# Second bar against the oak shelving on the west wall, a wine wall north of the opening.
	piece(b.region,"ChateauBar",Vector3(2.3,.52,4.7),Vector3(.7,1.04,2.6),rough_oak(),true,"wood",Vector3.ZERO,.1)
	piece(b.region,"ChateauBarTop",Vector3(2.3,1.09,4.7),Vector3(.85,.08,2.8),rough_oak(),false,"wood",Vector3.ZERO,0.0)
	shelving(Vector3(T,0,2.6),Vector3(T,0,6.6),Vector3.RIGHT,2.8)
	shelving(Vector3(T,0,-6.6),Vector3(T,0,-2.6),Vector3.RIGHT,2.8)
	cv(Vector3(3.0,0,3.2),Vector3(3.0,0,1.8))
	# Barrel heads covering the west wall above the gallery.
	for r in 5:
		for k in 12:
			var z:=-3.85+k*.7+(.35 if r%2==1 else 0.0)
			if z<=3.9:cask(Transform3D(Basis.from_scale(Vector3(.2,1,1)),Vector3(T+.09,5.0+r*.62,z)))
	vineyard_painting(Vector3(11,6.6,-6.8),6.0,2.2)
	chandelier(Vector3(11,CEIL,0),2.2)
	for z in [-2.8,2.8]:b.pipe(Vector3(1.2,CEIL-.95,z),Vector3(20.8,CEIL-.95,z),.3,Color("1f2122"))
	fill(Vector3(11,CEIL-1.2,0),16.0,1.4)
	for x in [3.2,19.0]:fill(Vector3(x,UPPER-.9,0),8.0,1.0)

# Marc, the winery restaurant, in the north wing: herringbone floor, tall tufted leather booths
# back to back down the room, red leather chairs, fabric drum pendants, a plank wall, and the
# bar at the far end (soapstone on X-braced oak, red leather stools, oak back bar with two
# televisions, a wrought-iron cage of bottles overhead, limestone behind).
func marc() -> void:
	for span in [[5.45,9.8],[12.2,17.6]]:booths(Vector3(float(span[0]),0,-15.0),Vector3(float(span[1]),0,-15.0))
	for x in [5.25,17.8]:drum(Vector3(x,(UPPER-.31)*.5,-15.0),.16,UPPER-.31,timber(),true,"ChateauPost")
	for x in [8.5,11.0,13.5,15.5]:
		table(Vector3(x,0,-10.0),Vector2(.75,.75),.76,"walnut")
		for side:float in [-1.0,1.0]:chair(Vector3(x,0,-10.0+side*.66),0.0 if side<0 else PI,"red")
		pendant(Vector3(x,2.9,-10.0),UPPER-.31,"drum",x==11.0)
	for x in [5.5,8.0,10.5]:
		table(Vector3(x,0,-19.8),Vector2(.75,.75),.76,"walnut")
		for side:float in [-1.0,1.0]:chair(Vector3(x,0,-19.8+side*.66),0.0 if side<0 else PI,"red")
		pendant(Vector3(x,2.9,-19.8),UPPER-.31,"drum",x==8.0)
	cv(Vector3(9.8,0,-11.2),Vector3(11.0,0,-11.2));cv(Vector3(7.0,0,-21.0),Vector3(8.6,0,-21.0))
	# Plank wall on the tasting room side.
	piece(b.region,"ChateauPlankWall",Vector3(12.1,(UPPER-.31)*.5,-7.22),Vector3(11.2,UPPER-.31,.04),planks(),false,"wood",Vector3.ZERO,0.0)
	# The bar.
	var bar:=Vector3(15.7,0,-22.4)
	piece(b.region,"ChateauBar",bar+Vector3(0,.53,0),Vector3(5.8,1.06,.75),rough_oak(),true,"wood",Vector3.ZERO,.1)
	piece(b.region,"ChateauBarTop",bar+Vector3(0,1.1,.05),Vector3(6.0,.06,.9),soapstone(),false,"concrete",Vector3.ZERO,0.0)
	var panels:=4;var bay:=5.8/panels
	for k in panels:
		var c:=bar+Vector3(-2.9+(k+.5)*bay,.55,.39)
		for side:float in [-1.0,1.0]:trim(Transform3D(Basis(Vector3.BACK,side*atan2(.86,bay-.1)),c),Vector3(sqrt(.86*.86+(bay-.1)*(bay-.1)),.07,.04),"oak")
		trim(Transform3D(Basis.IDENTITY,c+Vector3(-bay*.5,0,.005)),Vector3(.08,1.0,.05),"oak")
	trim(Transform3D(Basis.IDENTITY,bar+Vector3(0,.22,.6)),Vector3(5.6,.05,.05),"brass")
	for k in 6:b.prop("bar_chair_round_01",bar+Vector3(-2.3+k*.92,0,1.0),.75,decor.randf()*TAU,false)
	piece(b.region,"ChateauLimestone",Vector3(15.8,2.0,-25.37),Vector3(6.8,4.0,.06),sandstone(),false,"concrete",Vector3.ZERO,0.0)
	shelving(Vector3(12.6,0,-25.4),Vector3(19.0,0,-25.4),Vector3.BACK,2.25,.42)
	for x in [14.2,17.4]:b.prop("television_02",Vector3(x,2.55,-25.12),.62,0.0,false)
	# Wrought-iron cage of bottles hung over the bar.
	var cage:=bar+Vector3(0,3.0,0)
	for y in [0.0,.6]:
		for side:float in [-1.0,1.0]:trim(Transform3D(Basis.IDENTITY,cage+Vector3(0,y,side*.55)),Vector3(5.6,.04,.04),"iron")
		for side:float in [-1.0,1.0]:trim(Transform3D(Basis.IDENTITY,cage+Vector3(side*2.8,y,0)),Vector3(.04,.04,1.1),"iron")
	for k in 19:trim(Transform3D(Basis.IDENTITY,cage+Vector3(-2.7+k*.3,.3,.55)),Vector3(.02,.6,.02),"iron")
	for k in 19:trim(Transform3D(Basis.IDENTITY,cage+Vector3(-2.7+k*.3,.3,-.55)),Vector3(.02,.6,.02),"iron")
	for k in 3:trim(Transform3D(Basis.IDENTITY,cage+Vector3(-2.0+k*2.0,.82,0)),Vector3(.02,.45,.02),"iron")
	trim(Transform3D(Basis.IDENTITY,cage+Vector3(0,.02,0)),Vector3(5.6,.03,1.1),"iron")
	for row in 3:bottle_row(cage+Vector3(-2.7,.04,-.5+row*.35),cage+Vector3(2.7,.04,-.5+row*.35),Vector3.BACK)
	cv(bar+Vector3(-3.3,0,.9),bar+Vector3(-3.3,0,2.2))
	for p in [Vector3(15.7,2.6,-22.4),Vector3(7.0,2.6,-15.0)]:b.bake_light(p,Color(1.0,.78,.52),1.1,7.5)
	b.pipe(Vector3(3.5,UPPER-.95,-12.2),Vector3(20.8,UPPER-.95,-12.2),.25,Color("1f2122"))
	for z in [-11.0,-20.0]:fill(Vector3(11,UPPER-.8,z),11.0,1.1)

# Tall tufted leather booths back to back along a->c: a 1.85 m back down the middle, a seat
# each side, walnut tables in front with a fabric drum pendant over each.
func booths(a: Vector3, c: Vector3) -> void:
	var d:=c-a;var length:=d.length();var mid:=(a+c)*.5;var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var item:=node(b.region,"ChateauBooth",mid,Vector3(0,yaw,0))
	body(item,[[Vector3(0,.925,0),Vector3(length,1.85,.3)],[Vector3(0,.23,.45),Vector3(length,.46,.6)],[Vector3(0,.23,-.45),Vector3(length,.46,.6)]],"wood")
	trim(Transform3D(turn,mid+Vector3.UP*.9),Vector3(length,1.8,.26),"leather")
	trim(Transform3D(turn,mid+Vector3.UP*1.83),Vector3(length+.04,.06,.32),"walnut")
	var n:=maxi(1,int(length/1.5))
	for side:float in [-1.0,1.0]:
		trim(Transform3D(turn,mid+turn*Vector3(0,.23,side*.45)),Vector3(length,.44,.6),"leather")
		trim(Transform3D(turn,mid+turn*Vector3(0,.04,side*.45)),Vector3(length,.08,.62),"walnut")
		# Tufting: buttoned rows across the back.
		for y in [.85,1.2,1.55]:trim(Transform3D(turn,mid+turn*Vector3(0,y,side*.135)),Vector3(length-.06,.02,.012),"leather_seam")
		for k in int(length/.3):trim(Transform3D(turn,mid+turn*Vector3(-length*.5+(k+.5)*length/int(length/.3),1.2,side*.137)),Vector3(.012,.7,.012),"leather_seam")
		for k in n:
			var p:=a+d*(k+.5)/n+turn*Vector3(0,0,side*1.2)
			table(p,Vector2(.75,.75),.76,"walnut")
			chair(p+turn*Vector3(0,0,side*.66),yaw+(PI if side>0 else 0.0),"red")
			pendant(p+Vector3.UP*2.9,UPPER-.31,"drum",k==n/2 and side>0)
	cv(a+turn*Vector3(-.4,0,2.1),a+turn*Vector3(-.4,0,.9));cv(c+turn*Vector3(.4,0,-2.1),c+turn*Vector3(.4,0,-.9))

# Marc's glass porch on the north end: floor-to-ceiling glazing in black steel (the panes are
# breakable), a green beadboard ceiling with fans and lanterns, a stone floor, marble tables
# and rattan bistro chairs.
func porch() -> void:
	var x0:=4.0;var x1:=18.0;var z0:=-32.4;var z1:=-26.0;var top:=3.4
	var mid:=Vector3((x0+x1)*.5,0,(z0+z1)*.5)
	blocks.append(Rect2(x0,z0,x1-x0,z1-z0))
	piece(b.region,"ChateauPorchFloor",mid+Vector3(0,.06,0),Vector3(x1-x0,.12,z1-z0),sandstone(),true,"concrete",Vector3.ZERO,0.0)
	piece(b.region,"ChateauPorchRoof",mid+Vector3(0,top+.2,-.1),Vector3(x1-x0+.5,.4,z1-z0+.3),stucco(),true,"concrete",Vector3.ZERO,.2)
	trim(Transform3D(Basis.IDENTITY,mid+Vector3(0,top+.42,-.1)),Vector3(x1-x0+.62,.1,z1-z0+.42),"sandstone")
	piece(b.region,"ChateauPorchCeiling",mid+Vector3(0,top-.015,0),Vector3(x1-x0-.1,.02,z1-z0-.1),trim_material("beadboard"),false,"wood",Vector3.ZERO,0.0)
	for k in int((x1-x0)/.2):trim(Transform3D(Basis.IDENTITY,Vector3(x0+(k+.5)*.2,top-.03,mid.z)),Vector3(.012,.01,z1-z0-.1),"walnut")
	glazing(Vector3(x0,0,z0),Vector3(x1,0,z0),top,[7.0])
	glazing(Vector3(x0,0,z1),Vector3(x0,0,z0),top,[3.2])
	glazing(Vector3(x1,0,z0),Vector3(x1,0,z1),top,[3.2])
	for x in [6.0,8.4,13.6,16.0]:
		var p:=Vector3(x,.12,mid.z)
		table(p,Vector2(.7,.7),.75,"marble")
		for side:float in [-1.0,1.0]:chair(p+Vector3(side*.68,0,0),atan2(-side,0.0),"rattan")
	for x in [7.2,14.8]:fan(Vector3(x,top,mid.z))
	for z in [-27.6,-30.8]:
		b.prop("lantern_chandelier_01",Vector3(11,top-.75,z),.7,0.0,false)
		b.bake_light(Vector3(11,top-.6,z),Color(1.0,.8,.56),.9,6.0)
	for p in [Vector3(4.6,.12,-26.6),Vector3(17.4,.12,-26.6)]:b.prop("planter_pot_clay",p,.8,0.0)
	cv(Vector3(4.7,.12,-31.6),Vector3(4.7,.12,-30.6));cv(Vector3(17.3,.12,-26.8),Vector3(17.3,.12,-27.8))
	rooms.append(AABB(Vector3(x0,0,z0),Vector3(x1-x0,top,z1-z0)))

# Floor-to-ceiling glazing in black steel from a to c (along x or z) with 2.2 m doorways at the
# given distances: a kerb, mullions, a transom at 2.6 m, breakable panes.
func glazing(a: Vector3, c: Vector3, top: float, doors: Array) -> void:
	var d:=c-a;var length:=d.length();var dir:=d/length;var turn:=Basis(Vector3.UP,atan2(-d.z,d.x))
	var spans:=[];var cursor:=0.0
	for door in doors:
		spans.append([cursor,float(door)-1.1]);cursor=float(door)+1.1
		var head:=a+dir*float(door)
		trim(Transform3D(turn,head+Vector3.UP*2.62),Vector3(2.2,.08,.12),"black")
		pane(head+Vector3.UP*(2.66+top)*.5,turn*Vector3(2.12,top-2.7,.02))
	spans.append([cursor,length])
	for span in spans:
		var from:float=span[0];var to:float=span[1]
		var n:=maxi(1,roundi((to-from)/1.3));var w:=(to-from)/n
		for k in n+1:trim(Transform3D(turn,a+dir*(from+k*w)+Vector3.UP*top*.5),Vector3(.08,top,.1),"black")
		for k in n:
			var at:=a+dir*(from+(k+.5)*w)
			trim(Transform3D(turn,at+Vector3.UP*.19),Vector3(w,.14,.12),"black")
			trim(Transform3D(turn,at+Vector3.UP*2.62),Vector3(w,.06,.1),"black")
			pane(at+Vector3.UP*1.41,turn*Vector3(w-.08,2.36,.02))
			pane(at+Vector3.UP*(2.66+top)*.5,turn*Vector3(w-.08,top-2.7,.02))

# A breakable pane (WindowGlass*, see Destructible): clear glass left out of the bake, so the
# sun still reaches the room behind it, and solid until it is shot out.
func pane(center: Vector3, size: Vector3) -> void:
	size=size.abs()
	var key:="cpane"+str(size)
	if not b.meshes.has(key):
		b.meshes[key]=MapMeshes.block(size,0.0,0.0)
	if not mats.has("porch_glass"):
		var glass:=StandardMaterial3D.new();glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color=Color(.8,.88,.9,.14);glass.roughness=.04;glass.metallic=.25;glass.metallic_specular=.9
		mats["porch_glass"]=glass
	var item:=node(b.region,"WindowGlass",center)
	var inst:=MeshInstance3D.new();inst.mesh=b.meshes[key];inst.material_override=mats["porch_glass"]
	inst.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;inst.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	item.add_child(inst)
	body(item,[[Vector3.ZERO,size]],"concrete")

func fan(at: Vector3) -> void:
	trim(Transform3D(Basis.IDENTITY,at+Vector3.DOWN*.2),Vector3(.03,.4,.03),"black")
	trim(Transform3D(Basis.IDENTITY,at+Vector3.DOWN*.44),Vector3(.2,.1,.2),"black")
	for k in 4:
		var a:=k*PI*.5+.3
		trim(Transform3D(Basis(Vector3.UP,a),at+Vector3(cos(a),0,-sin(a))*.45+Vector3.DOWN*.47),Vector3(.7,.015,.15),"walnut")

# South wing: the Bordeaux Tasting Room (open oak wine shelving, high-top tables with black
# stools, big drum pendants, a gallery wall) and the wine market at the end (oak shelving,
# the grey-green panelled host counter by a grey pilaster).
func south_wing() -> void:
	shelving(Vector3(6.8,0,7.2),Vector3(17.4,0,7.2),Vector3.BACK,2.8)
	for x in [9.0,12.0,15.0]:
		var p:=Vector3(x,0,11.2)
		table(p,Vector2(.8,.8),1.05,"oak")
		for k in 3:stool(p+Vector3(cos(k*2.1+x),0,sin(k*2.1+x))*.72)
		cv(p+Vector3(0,0,1.3),p+Vector3(1.4,0,1.3))
	for x in [10.5,13.5]:pendant(Vector3(x,2.8,11.2),UPPER-.31,"bigdrum",true)
	gallery_wall(Vector3(11.8,2.1,14.83),5.2,1.8,-1.0)
	b.pipe(Vector3(3.5,UPPER-.95,13.4),Vector3(20.8,UPPER-.95,13.4),.25,Color("1f2122"))
	fill(Vector3(12,UPPER-.8,11.0),10.0,1.1)
	# Wine market.
	piece(b.region,"ChateauCounter",Vector3(16.2,.5,19.0),Vector3(3.4,1.0,.8),trim_material("sage"),true,"wood",Vector3.ZERO,.1)
	piece(b.region,"ChateauCounterTop",Vector3(16.2,1.03,19.0),Vector3(3.55,.06,.95),rough_oak(),false,"wood",Vector3.ZERO,0.0)
	for side:float in [-1.0,1.0]:
		for k in 5:trim(Transform3D(Basis.IDENTITY,Vector3(14.5+k*.85,.5,19.0+side*.41)),Vector3(.06,.9,.03),"sage")
		trim(Transform3D(Basis.IDENTITY,Vector3(16.2,.88,19.0+side*.41)),Vector3(3.4,.05,.03),"sage")
	piece(b.region,"ChateauPilaster",Vector3(18.3,(UPPER-.31)*.5,19.0),Vector3(.5,UPPER-.31,.5),trim_material("pilaster"),true,"concrete",Vector3.ZERO,.1)
	cv(Vector3(16.2,0,20.1),Vector3(14.0,0,20.1))
	for span in [[5.4,9.6],[12.4,16.6]]:shelving(Vector3(float(span[0]),0,25.4),Vector3(float(span[1]),0,25.4),Vector3.FORWARD,2.6)
	for x in [[6.5,9.0],[13.0,15.5]]:
		for side:float in [-1.0,1.0]:shelving(Vector3(float(x[0]),0,21.0),Vector3(float(x[1]),0,21.0),Vector3(0,0,side),1.6,.32)
		cv(Vector3(float(x[0])-.6,0,20.0),Vector3(float(x[0])-.6,0,22.0))
	for p in [Vector3(5.0,0,17.2),Vector3(19.6,0,16.6)]:
		b.prop("wine_barrel_01",p,1.0,0.0)
		bottle_row(p+Vector3(-.15,1.0,0),p+Vector3(.15,1.0,0))
	for p in [Vector3(19.4,0,24.6),Vector3(6.0,0,24.0)]:
		b.prop("wooden_crate_02",p,.6,decor.randf()*TAU)
	for x in [8.0,14.0]:pendant(Vector3(x,2.9,18.4),UPPER-.31,"rattan",true)
	fill(Vector3(11,UPPER-.8,20.0),11.0,1.1)

# Upstairs: the Velvet Room over Marc (a reclaimed plank wall with wine racks, leather sofas
# on an oriental rug, a sideboard) and a private dining room over the south wing.
func upstairs() -> void:
	var y:=UPPER
	piece(b.region,"ChateauPlankWall",Vector3(11.15,y+(CEIL-y)*.5,-7.22),Vector3(13.1,CEIL-y,.04),planks(),false,"wood",Vector3.ZERO,0.0)
	var rack:=Vector3(11,y+.6,-7.39)
	for k in 21:trim(Transform3D(Basis.IDENTITY,rack+Vector3(-5.0+k*.5,1.3,0)),Vector3(.03,2.6,.32),"walnut")
	for k in 8:trim(Transform3D(Basis.IDENTITY,rack+Vector3(0,k*.37,0)),Vector3(10.0,.03,.32),"walnut")
	for k in 20:
		for r in 7:
			if (k*7+r)%5!=0:bottle_row(rack+Vector3(-4.95+k*.5,.07+r*.37,.02),rack+Vector3(-4.55+k*.5,.07+r*.37,.02),Vector3.FORWARD,.14)
	rug(Vector3(12.5,y,-16.0),Vector2(6.0,4.2))
	for item in [[Vector3(12.5,y,-19.6),0.0],[Vector3(12.5,y,-12.4),PI],[Vector3(8.4,y,-16.0),PI*.5]]:b.prop("sofa_02",item[0],.71,item[1])
	table(Vector3(12.5,y,-16.0),Vector2(1.3,.7),.42,"walnut")
	piece(b.region,"ChateauSideboard",Vector3(14.3,y+.45,-25.05),Vector3(2.0,.9,.5),trim_material("walnut"),true,"wood",Vector3.ZERO,.1)
	b.props.scatter("wine_bottles_01",b.props.grounded("wine_bottles_01",Vector3(13.8,y+.9,-25.05),0.0,.5))
	chandelier(Vector3(12.5,CEIL,-16.0),1.1)
	# A second, smaller lounge by the east windows, barrel tops for tables, and the library wall.
	for z in [-21.0,-12.0]:
		b.prop("sofa_02",Vector3(20.3,y,z),.71,-PI*.5)
		b.prop("wine_barrel_01",Vector3(18.6,y,z),.87,0.0)
	for x in [3.2,5.6]:b.prop("wooden_bookshelf_worn",Vector3(x,y,-24.95),2.2,0.0)
	cv(Vector3(14.5,y,-19.9),Vector3(14.5,y,-21.4));cv(Vector3(7.4,y,-17.8),Vector3(7.4,y,-19.6))
	# Private dining.
	for x in [9.5,16.0]:
		table(Vector3(x,y,16.5),Vector2(1.1,9.0),.76,"walnut")
		for z in [12.75,15.25,17.75,20.25]:
			for side:float in [-1.0,1.0]:chair(Vector3(x+side*.82,y,z),atan2(-side,0.0),"wood")
		cv(Vector3(x-1.4,y,21.8),Vector3(x-1.4,y,23.5))
	for x in [7.75,14.25]:b.prop("painted_wooden_cabinet",Vector3(x,y,25.0),1.9,PI)
	for z in [13.0,19.0]:chandelier(Vector3(12.8,CEIL,z),1.1)
	# West gallery.
	b.prop("sofa_02",Vector3(2.0,y,0),.71,PI*.5)
	cv(Vector3(3.0,y,-2.0),Vector3(5.2,y,-1.0));cv(Vector3(19.5,y,-5.6),Vector3(19.5,y,-3.4))
	for s:float in [-1.0,1.0]:fill(Vector3(11,CEIL-1.0,s*16.0),13.0,1.2)

# --- Interior pieces ---------------------------------------------------------------------

# Brushed stainless tank shell; lit from the lightmap's probes rather than its own UV2.
func tank(c: Vector3, radius: float, height: float, solid := false) -> void:
	var key:="tank"+str(radius)+"x"+str(height)
	if not mats.has(key):mats[key]=MapMeshes.cylinder(radius,height,clampi(roundi(radius*28),12,40))
	var node:=MeshInstance3D.new();node.name="HallTank";node.mesh=mats[key];node.position=c
	node.material_override=flat(Color(.72,.74,.75),.32,.75);node.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC
	b.region.add_child(node)
	if solid:
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
		var shape:=CollisionShape3D.new();var volume:=CylinderShape3D.new();volume.radius=radius;volume.height=height;shape.shape=volume;body.add_child(shape);node.add_child(body)

# Open-web steel joists under a ceiling (centre on its underside): each spans local x for
# `span` metres, spread across `width`; turned by `turn` about the vertical.
func joists(center: Vector3, span: float, width: float, turn: float, pitch := 1.5) -> void:
	var basis:=Basis(Vector3.UP,turn)
	var n:=maxi(1,roundi(width/pitch))
	var depth:=.42;var panels:=maxi(2,roundi(span/.6));var step:=span/panels
	var lean:=atan2(depth-.08,step);var bar:=sqrt(step*step+(depth-.08)*(depth-.08))
	for i in n:
		var z:=-width*.5+(i+.5)*width/n
		for y in [-.04,-depth+.04]:trim(Transform3D(basis,center+basis*Vector3(0,y,z)),Vector3(span,.07,.1),"black")
		for k in panels:
			trim(Transform3D(basis*Basis(Vector3.BACK,lean if k%2==0 else -lean),center+basis*Vector3(-span*.5+(k+.5)*step,-depth*.5,z)),Vector3(bar,.035,.035),"black")

# Gallery rail: black steel posts and bars under an oak handrail.
func railing(a: Vector3, c: Vector3, height := 1.0) -> void:
	var d:=c-a;var length:=Vector2(d.x,d.z).length();var mid:=(a+c)*.5
	var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var item:=node(b.region,"ChateauRailing",mid,Vector3(0,yaw,0))
	body(item,[[Vector3(0,height*.5,0),Vector3(length,height,.12)]],"metal")
	trim(Transform3D(turn,mid+Vector3.UP*(height-.04)),Vector3(length+.04,.08,.14),"oak")
	for y in [.12,height*.55]:trim(Transform3D(turn,mid+Vector3.UP*y),Vector3(length,.04,.04),"black")
	var n:=maxi(1,int(length/1.2))
	for k in n+1:trim(Transform3D(turn,mid+d.normalized()*(-length*.5+k*length/n)+Vector3.UP*height*.5),Vector3(.06,height,.06),"black")

# Camel leather banquette from a to c (its seat's centre line), seated toward `inward`; solid.
func banquette(a: Vector3, c: Vector3, inward: Vector3) -> void:
	var d:=c-a;var length:=d.length();var mid:=(a+c)*.5;var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var side:=signf((turn.inverse()*inward).z)
	var item:=node(b.region,"ChateauBanquette",mid,Vector3(0,yaw,0))
	body(item,[[Vector3(0,.23,0),Vector3(length,.46,.55)],[Vector3(0,.6,-side*.33),Vector3(length,1.2,.14)]],"wood")
	trim(Transform3D(turn,mid+Vector3.UP*.25),Vector3(length,.42,.55),"leather")
	trim(Transform3D(turn,mid+Vector3.UP*.04),Vector3(length,.08,.57),"walnut")
	trim(Transform3D(turn,mid+turn*Vector3(0,.82,-side*.33)),Vector3(length,.76,.16),"leather")
	for k in int(length/.45):trim(Transform3D(turn,mid+turn*Vector3(-length*.5+(k+.5)*length/int(length/.45),.82,-side*.245)),Vector3(.014,.7,.012),"leather_seam")

# A table with a top of the given key on a black pedestal (on four legs when long); solid.
func table(p: Vector3, size: Vector2, height: float, key: String, yaw := 0.0) -> void:
	var turn:=Basis(Vector3.UP,yaw)
	trim(Transform3D(turn,p+Vector3.UP*(height-.025)),Vector3(size.x,.05,size.y),key)
	if maxf(size.x,size.y)>1.6:
		for sx:float in [-1.0,1.0]:
			for sz:float in [-1.0,1.0]:trim(Transform3D(turn,p+turn*Vector3(sx*(size.x*.5-.1),(height-.05)*.5,sz*(size.y*.5-.1))),Vector3(.07,height-.05,.07),key)
	else:
		trim(Transform3D(turn,p+Vector3.UP*(height*.5)),Vector3(.08,height-.05,.08),"black")
		trim(Transform3D(turn,p+Vector3.UP*.02),Vector3(size.x*.6,.04,size.y*.6),"black")
	var item:=node(b.region,"ChateauTable",p,Vector3(0,yaw,0))
	body(item,[[Vector3(0,height*.5,0),Vector3(size.x,height,size.y)]],"wood")

# A chair facing yaw (the sitter looks along its local +z): Marc's red leather ("red"), an iron
# bistro chair ("iron"), a rattan bistro chair ("rattan") or a plain wooden one ("wood").
func chair(p: Vector3, yaw: float, kind := "red") -> void:
	var turn:=Basis(Vector3.UP,yaw)
	var seat:String={"red":"leather_red","iron":"black","rattan":"rattan","wood":"walnut"}[kind]
	var legs:="black" if kind in ["iron","rattan"] else "walnut"
	var soft:=kind=="red"
	trim(Transform3D(turn,p+Vector3.UP*.46),Vector3(.44,.07 if soft else .035,.44),seat)
	trim(Transform3D(turn,p+turn*Vector3(0,.8 if soft else .76,-.2)),Vector3(.42,.6 if soft else .36,.06 if soft else .03),seat)
	for sx:float in [-1.0,1.0]:
		for sz:float in [-1.0,1.0]:trim(Transform3D(turn,p+turn*Vector3(sx*.18,.22,sz*.18)),Vector3(.03,.44,.03),legs)
		if not soft:trim(Transform3D(turn,p+turn*Vector3(sx*.18,.62,-.2)),Vector3(.03,.36,.03),legs)

# Black steel bar stool with a leather seat.
func stool(p: Vector3) -> void:
	trim(Transform3D(Basis.IDENTITY,p+Vector3.UP*.76),Vector3(.36,.06,.36),"leather")
	for sx:float in [-1.0,1.0]:
		for sz:float in [-1.0,1.0]:trim(Transform3D(Basis.IDENTITY,p+Vector3(sx*.14,.37,sz*.14)),Vector3(.03,.74,.03),"black")
	for k in 2:trim(Transform3D(Basis(Vector3.UP,k*PI*.5),p+Vector3.UP*.28),Vector3(.3,.025,.3),"black")

# A pendant on a cord from the ceiling at `top`: a fabric drum, a big drum, a brass dome or a
# rattan drum, with a glowing diffuser under it; `lit` bakes a lamp in it.
func pendant(at: Vector3, top: float, kind: String, lit := false) -> void:
	trim(Transform3D(Basis.IDENTITY,Vector3(at.x,(top+at.y)*.5,at.z)),Vector3(.014,top-at.y,.014),"black")
	var size:Vector2={"drum":Vector2(.36,.32),"bigdrum":Vector2(.75,.5),"dome":Vector2(.22,.18),"rattan":Vector2(.3,.36)}[kind]
	var mat:Material=trim_material({"drum":"linen","bigdrum":"linen","dome":"brass","rattan":"rattan"}[kind])
	drum(at,size.x,size.y,mat,false,"ChateauShade")
	drum(at+Vector3.DOWN*(size.y*.5-.02),size.x*.86,.012,trim_material("lamp"),false,"ChateauShade")
	if lit:b.bake_light(at+Vector3.DOWN*(size.y*.5+.15),Color(1.0,.78,.52),1.0 if kind!="bigdrum" else 1.4,7.0)

# Open oak wine shelving along a wall (a to c on its back line, the shelves toward `inward`),
# solid, with bottles standing on the shelves.
func shelving(a: Vector3, c: Vector3, inward: Vector3, height := 2.6, depth := .38) -> void:
	var d:=c-a;var length:=d.length();var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var mid:=(a+c)*.5+inward*depth*.5
	var item:=node(b.region,"ChateauShelving",mid,Vector3(0,yaw,0))
	body(item,[[Vector3(0,height*.5,0),Vector3(length,height,depth)]],"wood")
	var n:=maxi(1,roundi(length/.9))
	for k in n+1:trim(Transform3D(turn,a+d*float(k)/n+inward*depth*.5+Vector3.UP*height*.5),Vector3(.04,height,depth),"oak")
	var shelf:=.06
	while shelf<height:
		trim(Transform3D(turn,mid+Vector3.UP*shelf),Vector3(length,.035,depth),"oak")
		if shelf+.4<height:
			for k in n:
				if decor.randf()<.85:bottle_row(a+d*(k+.08)/n+inward*depth*.5+Vector3.UP*(shelf+.02),a+d*(k+.92)/n+inward*depth*.5+Vector3.UP*(shelf+.02))
		shelf+=.54
	trim(Transform3D(turn,mid+Vector3.UP*(height-.02)),Vector3(length+.04,.04,depth+.02),"oak")

# Bottles standing (or, with `lying` set, lying along that direction) in a row from a to c.
func bottle_row(a: Vector3, c: Vector3, lying := Vector3.ZERO, pitch := .085) -> void:
	var n:=maxi(1,int(a.distance_to(c)/pitch)+1)
	for k in n:
		var p:=a.lerp(c,float(k)/maxf(n-1,1))
		var basis:=Basis(Vector3.UP,decor.randf()*TAU) if lying==Vector3.ZERO else Basis(Quaternion(Vector3.UP,lying.normalized()))
		if lying!=Vector3.ZERO:p+=Vector3.UP*.037
		bottles.append_array(MapArena.pack(Transform3D(basis,p)))

func cask(xf: Transform3D) -> void:
	casks.append_array(MapArena.pack(xf))

# A rack of casks lying across the run from a to c, `levels` high, heads to both aisles; blue
# steel in production, oak cradles in the Cask Room. Solid.
func cask_rack(a: Vector3, c: Vector3, levels: int, frame: String) -> void:
	var d:=c-a;var length:=d.length();var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var n:=maxi(1,int(length/.72));var tall:=.12+levels*.72;var mid:=(a+c)*.5
	var item:=node(b.region,"ChateauRack",mid,Vector3(0,yaw,0))
	body(item,[[Vector3(0,tall*.5,0),Vector3(length,tall,1.0)]],"wood")
	for l in levels:
		var y:=.12+l*.72
		for side:float in [-.36,.36]:trim(Transform3D(turn,mid+turn*Vector3(0,y-.03,side)),Vector3(length,.06,.07),frame)
		for k in n:cask(Transform3D(turn*Basis(Vector3.UP,PI*.5),a+d*(k+.5)/n+Vector3.UP*(y+.35)))
	for k in range(0,n+1,2):
		for side:float in [-.42,.42]:trim(Transform3D(turn,a+d*float(k)/n+turn*Vector3(0,tall*.5,side)),Vector3(.06,tall,.06),frame)

# Oak cask lying along local x (0.95 m, 0.68 m across the bilge): flat staves, two heads and
# four black hoops. Drawn as one MultiMesh with the bottles (see flush_interior()).
func cask_mesh() -> ArrayMesh:
	if b.meshes.has("ccask"):return b.meshes["ccask"]
	var half:=.475;var segs:=18;var rings:=6
	var radius:=func(x:float)->float:return .29+.05*(1.0-pow(x/half,2.0))
	var ring:=func(x:float,r:float,a:float)->Vector3:return Vector3(x,cos(a)*r,sin(a)*r)
	var mesh:=ArrayMesh.new()
	var wood:=SurfaceTool.new();wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rings:
		var xa:=-half+2.0*half*i/rings;var xb:=-half+2.0*half*(i+1)/rings
		var ra:float=radius.call(xa);var rb:float=radius.call(xb)
		for j in segs:
			var a0:=TAU*j/segs;var a1:=TAU*(j+1)/segs;var am:=(a0+a1)*.5
			add_poly(wood,[ring.call(xa,ra,a0),ring.call(xb,rb,a0),ring.call(xb,rb,a1),ring.call(xa,ra,a1)],Vector3(-(rb-ra)/(xb-xa),cos(am),sin(am)).normalized(),false)
	for side:float in [-1.0,1.0]:
		for j in segs:
			add_poly(wood,[Vector3(side*half,0,0),ring.call(side*half,.29,TAU*j/segs),ring.call(side*half,.29,TAU*(j+1)/segs)],Vector3(side,0,0),false)
	wood.generate_tangents();wood.commit(mesh)
	mesh.surface_set_material(0,planks(Color(.56,.38,.24),.45,1.4))
	var iron:=SurfaceTool.new();iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x in [-.42,-.27,.27,.42]:
		var r:float=radius.call(x)+.006
		for j in segs:
			var a0:=TAU*j/segs;var a1:=TAU*(j+1)/segs;var am:=(a0+a1)*.5
			add_poly(iron,[ring.call(x-.025,r,a0),ring.call(x+.025,r,a0),ring.call(x+.025,r,a1),ring.call(x-.025,r,a1)],Vector3(0,cos(am),sin(am)),false)
	iron.generate_tangents();iron.commit(mesh)
	mesh.surface_set_material(1,trim_material("black"))
	b.meshes["ccask"]=mesh
	return mesh

# Dark green wine bottle standing on its base (31.5 cm).
func bottle_mesh() -> ArrayMesh:
	if b.meshes.has("cbottle"):return b.meshes["cbottle"]
	var profile:=[Vector2(.0,0),Vector2(.037,0),Vector2(.037,.2),Vector2(.03,.235),Vector2(.014,.26),Vector2(.013,.3),Vector2(.015,.315),Vector2(0,.315)]
	var segs:=10
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in profile.size()-1:
		var p0:Vector2=profile[i];var p1:Vector2=profile[i+1]
		for j in segs:
			var a0:=TAU*j/segs;var a1:=TAU*(j+1)/segs;var am:=(a0+a1)*.5
			var n:=Vector3(cos(am)*(p1.y-p0.y),-(p1.x-p0.x),sin(am)*(p1.y-p0.y)).normalized()
			var q:=[Vector3(cos(a0)*p0.x,p0.y,sin(a0)*p0.x),Vector3(cos(a0)*p1.x,p1.y,sin(a0)*p1.x),Vector3(cos(a1)*p1.x,p1.y,sin(a1)*p1.x),Vector3(cos(a1)*p0.x,p0.y,sin(a1)*p0.x)]
			if p0.x<.001:q=[q[0],q[1],q[2]]
			elif p1.x<.001:q=[q[0],q[1],q[3]]
			add_poly(st,q,n,false)
	st.generate_tangents()
	var mesh:=st.commit()
	var glass:=StandardMaterial3D.new();glass.albedo_color=Color(.07,.14,.07);glass.roughness=.12;glass.metallic=.35;glass.metallic_specular=.8
	mesh.surface_set_material(0,glass)
	b.meshes["cbottle"]=mesh
	return mesh

func flush_interior() -> void:
	if not casks.is_empty():b.arena.instance_batches.append(["ChateauCasks",cask_mesh(),null,casks,GeometryInstance3D.GI_MODE_DYNAMIC,90.0])
	if not bottles.is_empty():b.arena.instance_batches.append(["ChateauBottles",bottle_mesh(),null,bottles,GeometryInstance3D.GI_MODE_DYNAMIC,40.0])
	casks=PackedFloat32Array();bottles=PackedFloat32Array()

# A big vineyard landscape on the wall (facing +z): sky, hills, a far white house, vine rows
# running toward the horizon, in a gilt frame.
func vineyard_painting(c: Vector3, w: float, h: float) -> void:
	var top:=c.y+h*.5;var f:=c.z+.03
	trim(Transform3D(Basis.IDENTITY,Vector3(c.x,top-h*.22,f)),Vector3(w,h*.44,.02),"paint_sky")
	trim(Transform3D(Basis.IDENTITY,Vector3(c.x,top-h*.51,f)),Vector3(w,h*.14,.02),"paint_hill")
	trim(Transform3D(Basis.IDENTITY,Vector3(c.x,top-h*.79,f)),Vector3(w,h*.42,.02),"paint_field")
	for k in 8:
		var t:=pow(float(k+1)/9.0,1.5)
		trim(Transform3D(Basis.IDENTITY,Vector3(c.x,top-h*.6-t*h*.38,f+.006)),Vector3(w,.012+.04*t,.01),"paint_row")
	trim(Transform3D(Basis.IDENTITY,Vector3(c.x+w*.2,top-h*.47,f+.007)),Vector3(w*.07,h*.06,.01),"canvas")
	trim(Transform3D(Basis.IDENTITY,Vector3(c.x+w*.2,top-h*.42,f+.007)),Vector3(w*.08,h*.04,.01),"black")
	for side:float in [-1.0,1.0]:
		trim(Transform3D(Basis.IDENTITY,Vector3(c.x,c.y+side*(h*.5+.06),c.z+.04)),Vector3(w+.24,.12,.06),"brass")
		trim(Transform3D(Basis.IDENTITY,Vector3(c.x+side*(w*.5+.06),c.y,c.z+.04)),Vector3(.12,h+.24,.06),"brass")

# Framed pictures hung close together on a wall facing `facing` (+1/-1 along z).
func gallery_wall(c: Vector3, w: float, h: float, facing: float) -> void:
	var r:=RandomNumberGenerator.new();r.seed=77
	var x:=c.x-w*.5
	while x<c.x+w*.5-.4:
		var fw:=r.randf_range(.45,.9);var fh:=r.randf_range(.5,.9)
		var y:=c.y+r.randf_range(-h*.5+fh*.5,h*.5-fh*.5)
		var at:=Vector3(x+fw*.5,y,c.z+facing*.025)
		trim(Transform3D(Basis.IDENTITY,at),Vector3(fw,fh,.03),"black")
		trim(Transform3D(Basis.IDENTITY,at+Vector3(0,0,facing*.012)),Vector3(fw-.1,fh-.1,.012),"canvas")
		trim(Transform3D(Basis.IDENTITY,at+Vector3(0,0,facing*.02)),Vector3((fw-.1)*.6,(fh-.1)*.55,.006),["paint_hill","paint_field","leather_red","paint_sky"][r.randi()%4])
		x+=fw+r.randf_range(.12,.25)

# Oriental rug: a red field, a navy border with a cream band, a navy medallion.
func rug(c: Vector3, size: Vector2) -> void:
	trim(Transform3D(Basis.IDENTITY,c+Vector3.UP*.006),Vector3(size.x,.012,size.y),"rug_navy")
	trim(Transform3D(Basis.IDENTITY,c+Vector3.UP*.008),Vector3(size.x-.5,.012,size.y-.5),"rug_cream")
	trim(Transform3D(Basis.IDENTITY,c+Vector3.UP*.01),Vector3(size.x-.62,.012,size.y-.62),"rug_red")
	trim(Transform3D(Basis(Vector3.UP,PI*.25),c+Vector3.UP*.012),Vector3(1.1,.012,1.1),"rug_navy")
	trim(Transform3D(Basis(Vector3.UP,PI*.25),c+Vector3.UP*.014),Vector3(.6,.012,.6),"rug_cream")

# --- Grounds ---------------------------------------------------------------------------

func plaza() -> void:
	blocks.append(Rect2(22,-13,15,26))
	piece(b.region,"ChateauPlaza",Vector3(29.5,.02,0),Vector3(15,.04,26),b.surfaces.get_material("paving"),false,"concrete",Vector3.ZERO,0.0)
	for z in [-13.05,13.05]:trim(Transform3D(Basis.IDENTITY,Vector3(29.5,.05,z)),Vector3(15,.1,.2),"sandstone")
	# Fountain: a stone basin, a pedestal and a bowl.
	var at:=Vector3(31,0,0)
	drum(at+Vector3(0,.3,0),2.7,.6,sandstone())
	drum(at+Vector3(0,.62,0),2.85,.08,sandstone(),false)
	var water:=StandardMaterial3D.new();water.albedo_color=Color(.16,.24,.24);water.roughness=.05;water.metallic_specular=.8
	drum(at+Vector3(0,.5,0),2.45,.04,water,false,"ChateauWater")
	drum(at+Vector3(0,1.1,0),.35,1.2,sandstone())
	drum(at+Vector3(0,1.8,0),1.1,.22,sandstone(),false)
	drum(at+Vector3(0,2.15,0),.18,.5,sandstone(),false)
	for k in 4:
		var a:=k*PI*.5+PI*.25
		cv(at+Vector3(cos(a),0,sin(a))*3.6,at+Vector3(cos(a+.6),0,sin(a+.6))*3.9)
	# Café tables under umbrellas either side of the fountain.
	var i:=0
	for p in [Vector3(25.5,0,-7.5),Vector3(25.5,0,7.5),Vector3(34.5,0,-8.0),Vector3(34.5,0,8.0)]:
		b.prop("round_wooden_table_01",p,.76,0.0)
		for k in 3:b.prop("dining_chair_02",p+Vector3(cos(k*2.1+i),0,sin(k*2.1+i))*1.05,.97,-k*2.1-i+PI*.5,false)
		umbrella(p,"canvas_red" if i%2==0 else "canvas_cream")
		i+=1
	cv(Vector3(25.5,0,-5.8),Vector3(27.5,0,-5.8));cv(Vector3(34.5,0,6.3),Vector3(36.4,0,6.3))
	for s:float in [-1.0,1.0]:
		# Clipped hedges framing the plaza, topiary cones at the corners and by the arcade.
		low_hedge(Vector3(23.0,0,s*14.2),Vector3(28.0,0,s*14.2))
		low_hedge(Vector3(31.0,0,s*14.2),Vector3(36.5,0,s*14.2))
		for p in [Vector3(22.8,0,s*9.0),Vector3(37.3,0,s*13.6),Vector3(22.8,0,s*13.6)]:topiary(p,2.2)
		cv(Vector3(25.5,0,s*15.4),Vector3(29.5,0,s*15.4))

func umbrella(p: Vector3, canvas: String) -> void:
	trim(Transform3D(Basis.IDENTITY,p+Vector3(0,1.25,0)),Vector3(.05,2.5,.05),"iron")
	var item:=node(b.region,"ChateauUmbrella",p+Vector3(0,2.15,0),Vector3(0,PI*.25,0))
	var key:=canvas
	visual(item,pyramid_mesh(1.35,.55),trim_material(key),false)
	for k in 4:
		var a:=k*PI*.5
		trim(Transform3D(Basis(Vector3.UP,-a),p+Vector3(cos(a)*.95,2.12,sin(a)*.95)),Vector3(1.95,.04,.04),canvas)

func lawn() -> void:
	chess(Vector3(47,0,-12))
	# Flower beds and benches on the south lawn, a clump of lindens by the drive.
	for x in [42.0,51.0]:
		low_hedge(Vector3(x-3.0,0,12.0),Vector3(x+3.0,0,12.0))
		low_hedge(Vector3(x-3.0,0,18.0),Vector3(x+3.0,0,18.0))
		cv(Vector3(x,0,10.6),Vector3(x+4.4,0,10.6));cv(Vector3(x,0,19.4),Vector3(x-4.4,0,19.4))
	for x in [42.0,51.0]:b.prop("painted_wooden_bench",Vector3(x,0,15.0),.89,0.0)
	for p in [Vector3(40.0,0,30.0),Vector3(56.0,0,26.0),Vector3(58.0,0,-2.0),Vector3(70.0,0,12.0),Vector3(72.0,0,-12.0)]:tree(p,"linden",b.rng.randf_range(.95,1.2))
	for p in [Vector3(66.0,0,32.0),Vector3(52.0,0,40.0)]:tree(p,"walnut",1.1)
	# Low stone walls on the red lawn: first cover out of deployment.
	for z in [-16.0,0.0,16.0]:stone_wall(Vector3(68.0,0,z-3.0),Vector3(68.0,0,z+3.0),1.05)
	stone_wall(Vector3(56.0,0,4.0),Vector3(62.0,0,4.0),1.05)

# Giant chess on the lawn: board squares laid in the turf and the tabletop
# set's pieces scaled up (pawns knee high, the kings chest high), mid-game.
func chess(center: Vector3) -> void:
	var parts:=b.props.parts("chess_set")
	var boxes:Array[AABB]=[]
	var board:=0;var best:=0.0
	for i in parts.size():
		var box:AABB=(parts[i].get_meta("prop_transform",Transform3D.IDENTITY) as Transform3D)*parts[i].get_aabb()
		boxes.append(box)
		if box.size.x*box.size.z>best:best=box.size.x*box.size.z;board=i
	var origin:=boxes[board].get_center()
	var pitch:=.058*S_CHESS
	blocks.append(Rect2(center.x-pitch*4.4,center.z-pitch*4.4,pitch*8.8,pitch*8.8))
	trim(Transform3D(Basis.IDENTITY,center+Vector3(0,.015,0)),Vector3(pitch*8.5,.03,pitch*8.5),"sandstone")
	for i in 8:
		for j in 8:
			trim(Transform3D(Basis.IDENTITY,center+Vector3((i-3.5)*pitch,.035,(j-3.5)*pitch)),Vector3(pitch-.03,.03,pitch-.03),"marble" if (i+j)%2==0 else "darkslate")
	var r:=RandomNumberGenerator.new();r.seed=64
	for i in parts.size():
		if i==board:continue
		var box:=boxes[i]
		var local:=box.get_center()-origin
		var spot:=center+Vector3(local.x,0,local.z)*S_CHESS
		var tall:=box.size.y*S_CHESS
		var lying:=false
		if box.size.y<.07 and r.randf()<.45:spot.z-=signf(local.z)*pitch  # pawns advanced
		elif r.randf()<.12:
			# Taken: laid on the lawn beside the board.
			spot=center+Vector3(pitch*6.6+r.randf_range(0,1.2),0,signf(local.z)*r.randf_range(1.0,3.5));lying=true
		var holder:=Node3D.new();holder.name="Prop_chess_piece"+str(b.serial);b.serial+=1
		var basis:=Basis(Vector3.UP,r.randf()*TAU)
		if lying:basis=basis*Basis(Vector3.BACK,PI*.5)
		holder.transform=Transform3D(basis.scaled(Vector3.ONE*S_CHESS),Vector3.ZERO)
		b.region.add_child(holder)
		var inst:=MeshInstance3D.new();inst.mesh=parts[i];inst.transform=parts[i].get_meta("prop_transform",Transform3D.IDENTITY)
		inst.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;holder.add_child(inst)
		# Stand the scaled piece on the board at its square.
		var foot:=holder.transform*Vector3(box.get_center().x,box.position.y,box.get_center().z)
		if lying:foot=holder.transform*box.get_center()-Vector3(0,maxf(box.size.x,box.size.z)*S_CHESS*.5,0)
		holder.position=Vector3(spot.x-foot.x,.05-foot.y,spot.z-foot.z)
		var shape:=CylinderShape3D.new();shape.radius=maxf(box.size.x,box.size.z)*S_CHESS*.42;shape.height=tall if not lying else shape.radius*2.0
		var post:=node(b.region,"ChessCollider",spot+Vector3(0,shape.height*.5+.05,0))
		body(post,[[Vector3.ZERO,shape]],"wood")
	for s:float in [-1.0,1.0]:cv(center+Vector3(-pitch*5.2,0,s*pitch*2.0),center+Vector3(-pitch*5.2,0,s*pitch*5.2))
	cv(center+Vector3(pitch*5.0,0,-pitch*.5),center+Vector3(pitch*5.0,0,-pitch*4.8))

func terrace() -> void:
	# Raised terrace on a sandstone retaining wall with a rotunda; steps up from the north and west.
	blocks.append(Rect2(22,30,18,14))
	piece(b.region,"ChateauTerrace",Vector3(31,.5,37),Vector3(18,1.0,14),sandstone(),true,"concrete",Vector3.ZERO,.5)
	piece(b.region,"ChateauTerraceTop",Vector3(31,1.02,37),Vector3(17.9,.04,13.9),b.surfaces.get_material("paving"),false,"concrete",Vector3.ZERO,0.0)
	flight(Transform3D(Basis(Vector3.UP,-PI*.5),Vector3(31,0,30-2.375)),5,3.0,sandstone())
	flight(Transform3D(Basis.IDENTITY,Vector3(22-2.375,0,37)),5,3.0,sandstone())
	var top:=1.0
	balustrade(Vector3(22.1,top,30.1),Vector3(29.4,top,30.1),.95)
	balustrade(Vector3(32.6,top,30.1),Vector3(39.9,top,30.1),.95)
	balustrade(Vector3(39.9,top,30.1),Vector3(39.9,top,43.9),.95)
	balustrade(Vector3(39.9,top,43.9),Vector3(22.1,top,43.9),.95)
	balustrade(Vector3(22.1,top,43.9),Vector3(22.1,top,38.6),.95)
	balustrade(Vector3(22.1,top,35.4),Vector3(22.1,top,30.1),.95)
	var at:=Vector3(33,top,38)
	for k in 8:
		var a:=TAU*k/8.0+PI/8.0
		var p:=at+Vector3(cos(a),0,sin(a))*3.6
		drum(p+Vector3(0,1.7,0),.24,3.4,sandstone(),true,"ChateauColumn")
		piece(b.region,"ChateauBase",p+Vector3(0,.1,0),Vector3(.6,.2,.6),sandstone(),false)
		piece(b.region,"ChateauCapital",p+Vector3(0,3.3,0),Vector3(.6,.22,.6),sandstone(),false)
		var a2:=a+TAU/8.0;var q:=at+Vector3(cos(a2),0,sin(a2))*3.6
		var mid:=(p+q)*.5
		piece(b.region,"ChateauEntablature",mid+Vector3(0,3.62,0),Vector3(p.distance_to(q)+.5,.42,.5),sandstone(),false,"concrete",Vector3(0,atan2(-(q-p).z,(q-p).x),0),0.0)
	var cap:=node(b.region,"ChateauDome",at+Vector3(0,3.83,0))
	visual(cap,dome_mesh(4.1,1.7),slate())
	for k in 2:b.prop("painted_wooden_bench",at+Vector3(0,0,(k*2-1)*1.7),.89,k*PI)
	for p in [Vector3(25.0,top,32.5),Vector3(25.0,top,41.5),Vector3(38.0,top,32.0)]:b.prop("planter_pot_clay",p,.8,0.0)
	cv(at+Vector3(-2.2,0,-1.0),at+Vector3(-2.2,0,-3.0))
	cv(Vector3(24.0,top,42.2),Vector3(26.5,top,42.2))
	for x in [26.0,36.0]:cv(Vector3(x,0,28.8),Vector3(x-2.4,0,28.8))
	cv(Vector3(41.2,0,38.0),Vector3(41.2,0,35.0))

func south_garden() -> void:
	# Garden house to the south-west, clipped parterres, lindens and the vineyard walk.
	house(Vector3(-6,0,42),Vector2(12,7),0.0,{"floors":1,"wall":stucco(),"roof":slate(),"paint":"green","chimney":false,
		"s":[[-3.0,"wide"],[3.0,"window"]],"n":[[-3.0,"window"],[3.0,"door"]],"e":[[0.0,"door"]],"w":[[0.0,"door"]]})
	b.prop("painted_wooden_table",Vector3(-8.0,0,42.5),.78,.2)
	b.prop("planter_pot_clay",Vector3(-2.0,0,40.5),.5,0.0,false)
	cv(Vector3(-8.0,0,40.8),Vector3(-5.6,0,40.6))
	low_hedge(Vector3(-16,0,30.5),Vector3(-6,0,30.5));low_hedge(Vector3(14,0,30.5),Vector3(20,0,30.5))
	cv(Vector3(-11,0,29.3),Vector3(-5,0,29.3));cv(Vector3(17,0,29.3),Vector3(13,0,29.3))
	for p in [Vector3(-16,0,34.5),Vector3(13,0,34.5)]:
		low_hedge(p,p+Vector3(6.0,0,0));topiary(p+Vector3(3.0,0,2.0),2.4)
	cv(Vector3(-12,0,32.5),Vector3(-8,0,32.5))
	for p in [Vector3(-16.0,0,48.0),Vector3(8.0,0,40.0),Vector3(16.0,0,46.0),Vector3(-26.0,0,36.0),Vector3(-36.0,0,44.0)]:tree(p,"linden",b.rng.randf_range(.9,1.15))
	cv(Vector3(14.6,0,32.0),Vector3(12.0,0,32.0))
	paths.append([Vector3(-70,0,50.5),Vector3(70,0,50.5),3.0])
	paths.append([Vector3(11,0,27),Vector3(11,0,50),2.4])
	paths.append([Vector3(-6,0,38),Vector3(-6,0,50),2.0])
	# Vineyards (rows run north-south, 2.8 m apart).
	for block in [[-63.0,-24.0],[26.0,66.0]]:
		var x:float=block[0];var k:=0
		while x<=float(block[1]):
			vine_row(Vector3(x,0,54.0),Vector3(x,0,72.0))
			if k%5==2:cv(Vector3(x+1.4,0,56.0),Vector3(x+1.4,0,52.4))
			x+=2.8;k+=1

func north_side() -> void:
	# Carriage house across the service drive, walk-through to the north vineyards.
	house(Vector3(11,0,-50),Vector2(16,8),0.0,{"floors":1,"wall":stone(),"roof":slate(),"paint":"green","chimney":true,
		"s":[[-5.0,"wide"],[0.0,"window"],[5.0,"wide"]],"n":[[-5.0,"wide"],[5.0,"wide"]],"e":[[0.0,"door"]],"w":[[0.0,"door"]]})
	b.props.place("covered_car",b.props.grounded("covered_car",Vector3(11,0,-50),PI*.5),true,220.0)
	barrels(Vector3(12.0,0,-53.0),0.0,3,true)
	b.prop("wooden_crate_01",Vector3(4.5,0,-53.2),1.0,.3)
	cv(Vector3(11,0,-48.0),Vector3(8.0,0,-48.0));cv(Vector3(11,0,-52.0),Vector3(14.0,0,-52.0))
	# Delivery vans on the drive, stone walls and lindens along it.
	for item in [[Vector3(-45,0,-37.6),PI*.5],[Vector3(15,0,-42.4),PI*.5+.05],[Vector3(40,0,-37.6),PI*.5-.04]]:
		b.props.place("covered_car",b.props.grounded("covered_car",item[0],item[1]),true,220.0)
		b.stains.append(item[0])
	cv(Vector3(-45,0,-35.4),Vector3(-41.6,0,-35.6));cv(Vector3(15,0,-44.6),Vector3(18.6,0,-44.6));cv(Vector3(40,0,-35.4),Vector3(36.4,0,-35.4))
	for x in [-30.0,-12.0,26.0]:
		stone_wall(Vector3(x-3.0,0,-33.0),Vector3(x+3.0,0,-33.0),1.05)
	for x in [-58.0,-38.0,-20.0,30.0]:tree(Vector3(x,0,-46.5),"linden" if int(x)%4==0 else "walnut",b.rng.randf_range(.95,1.2))
	for x in [-6.0,32.0]:tree(Vector3(x,0,-31.0),"linden",1.0)
	# Planters and topiary cones either side of Marc's glass porch.
	for x in [2.4,19.6]:b.prop("planter_pot_clay",Vector3(x,0,-32.0),.9,0.0)
	topiary(Vector3(2.4,0,-27.0),2.2);topiary(Vector3(19.6,0,-27.0),2.2)
	# Yards between the hall and the wings: delivery vans, crates, pallets of barrels.
	for s:float in [-1.0,1.0]:
		b.props.place("covered_car",b.props.grounded("covered_car",Vector3(-12,0,s*21.0),PI*.5),true,220.0)
		b.stains.append(Vector3(-12,0,s*21.0))
		barrels(Vector3(-9.0,0,s*25.0),0.0,3,true)
		b.prop("wooden_crate_02",Vector3(-18.0,0,s*18.0),.9,.4)
		cv(Vector3(-12,0,s*19.0),Vector3(-15.6,0,s*19.0));cv(Vector3(-9.0,0,s*23.6),Vector3(-6.5,0,s*23.6))
	# North vineyards beyond the carriage house.
	for block in [[-63.0,-30.0],[30.0,42.0]]:
		var x:float=block[0];var k:=0
		while x<=float(block[1]):
			vine_row(Vector3(x,0,-71.0),Vector3(x,0,-57.0))
			if k%5==2:cv(Vector3(x+1.4,0,-59.0),Vector3(x+1.4,0,-55.0))
			x+=2.8;k+=1

func west_side() -> void:
	# Loading yard behind the barrel hall: two vans, barrel pallets, crates.
	for z in [-10.0,10.0]:
		b.props.place("covered_car",b.props.grounded("covered_car",Vector3(-30,0,z),PI*.5),true,220.0)
		b.stains.append(Vector3(-30,0,z))
		cv(Vector3(-30,0,z-signf(z)*2.1),Vector3(-26.4,0,z-signf(z)*2.2))
	for p in [Vector3(-25.0,0,-4.5),Vector3(-25.0,0,4.5),Vector3(-38.0,0,-7.0),Vector3(-38.0,0,7.0)]:
		pallet_of_barrels(p)
		cv(p+Vector3(-1.8,0,0),p+Vector3(-1.8,0,signf(p.z)*2.4))
	for p in [Vector3(-23.0,0,-19.0),Vector3(-23.0,0,19.0)]:
		b.prop("wooden_crate_01",p,1.0,.2);b.prop("wooden_crate_02",p+Vector3(1.1,0,.2),.8,.5)
	# Visitor car park: two rows of cars, tree islands, a stone wall to the yard.
	var r:=RandomNumberGenerator.new();r.seed=903
	for x in [-64.0,-52.0]:
		var z:=-44.0
		while z<44.0:
			if absf(z)<2.0 or r.randf()<.42:z+=2.9;continue
			var p:=Vector3(x+r.randf_range(-.3,.3),0,z)
			b.props.place("covered_car",b.props.grounded("covered_car",p,PI*.5+(0.0 if r.randf()<.5 else PI)+r.randf_range(-.08,.08)),true,220.0)
			z+=2.9
		cv(Vector3(x+3.0,0,-24.0),Vector3(x+3.0,0,-20.0));cv(Vector3(x-3.0,0,24.0),Vector3(x-3.0,0,20.0))
	for z in [-30.0,0.0,30.0]:tree(Vector3(-58,0,z+6.0),"linden",b.rng.randf_range(.95,1.15))
	for z in [-34.0,-17.0,17.0,34.0]:tree(Vector3(-44,0,z),"walnut" if int(z)%2==0 else "linden",b.rng.randf_range(.9,1.1))
	for z in [-25.0,25.0]:stone_wall(Vector3(-42.0,0,z-4.0),Vector3(-42.0,0,z+4.0),1.05)

func pallet_of_barrels(p: Vector3) -> void:
	piece(b.region,"ChateauPallet",p+Vector3(0,.07,0),Vector3(1.9,.14,1.2),planks(),true,"wood",Vector3.ZERO,0.0)
	for k in 4:b.prop("wine_barrel_01",p+Vector3((k%2-.5)*.85,.14,(k/2-.5)*.6),.87,b.rng.randf()*TAU)

func turnaround() -> void:
	# The drive's turnaround: a round island with a linden, clipped hedges and the estate sign.
	drum(TURN+Vector3(0,.1,0),7.6,.2,sandstone(),false,"ChateauCurb")
	piece(b.region,"ChateauIsland",TURN+Vector3(0,.21,0),Vector3(10.4,.02,10.4),b.surfaces.get_material("grass"),false,"earth",Vector3(0,PI*.25,0),0.0)
	blocks.append(Rect2(TURN.x-7.6,TURN.z-7.6,15.2,15.2))
	tree(TURN,"linden",1.3)
	for k in 4:
		var a:=k*PI*.5
		low_hedge(TURN+Vector3(cos(a)*4.6,0,sin(a)*4.6)+Vector3(-sin(a),0,cos(a))*2.0,TURN+Vector3(cos(a)*4.6,0,sin(a)*4.6)-Vector3(-sin(a),0,cos(a))*2.0)
		cv(TURN+Vector3(cos(a),0,sin(a))*8.8,TURN+Vector3(cos(a+.5),0,sin(a+.5))*9.0)
	# Estate sign wall by the drive.
	var at:=Vector3(70,0,-24)
	piece(b.region,"ChateauSign",at+Vector3(0,.75,0),Vector3(7.0,1.5,.6),sandstone(),true,"concrete",Vector3.ZERO,.3)
	piece(b.region,"ChateauSignCap",at+Vector3(0,1.56,0),Vector3(7.3,.12,.75),sandstone(),false)
	for side:float in [-1.0,1.0]:
		var label:=Label3D.new();label.text="CHÂTEAU MIRELLE";label.font_size=72;label.pixel_size=.0085
		label.modulate=Color(.2,.2,.19);label.shaded=true;label.outline_size=0;label.alpha_cut=Label3D.ALPHA_CUT_DISCARD;label.double_sided=false
		b.region.add_child(label);label.transform=Transform3D(Basis(Vector3.UP,0.0 if side<0 else PI),at+Vector3(0,.95,side*-.31))
		var sub:=Label3D.new();sub.text="VINEYARDS · WINERY";sub.font_size=36;sub.pixel_size=.0085
		sub.modulate=Color(.25,.25,.23);sub.shaded=true;sub.outline_size=0;sub.alpha_cut=Label3D.ALPHA_CUT_DISCARD;sub.double_sided=false
		b.region.add_child(sub);sub.transform=Transform3D(Basis(Vector3.UP,0.0 if side<0 else PI),at+Vector3(0,.5,side*-.31))
	cv(at+Vector3(0,0,1.4),at+Vector3(4.2,0,1.4))
	roads.append([Vector3(-74,0,-40),Vector3(TURN.x-12.5,0,-40),7.0])
	roads.append([Vector3(TURN.x+12.5,0,-40),Vector3(92,0,-40),7.0])
	roads.append([Vector3(38,0,-38),Vector3(38,0,-14),6.0])

# --- Vegetation shapes -------------------------------------------------------------------

# Clipped low hedge (0.9 m, 0.7 m deep) between a and c, solid.
func low_hedge(a: Vector3, c: Vector3) -> void:
	if not foliage_meshes.has("lowhedge"):
		var r:=RandomNumberGenerator.new();r.seed=81
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 70:
			var q:=Vector3(r.randf_range(-.95,.95),r.randf_range(.1,.85),r.randf_range(-.3,.3))
			var out:=Vector3(r.randfn()*.3,r.randf_range(0,.9),signf(q.z)+r.randfn()*.3).normalized()
			leaf_card(st,q,out,r.randf_range(.45,.6),r.randf()*TAU,clampf(.35+q.y*.5+absf(q.z),0,1))
		foliage_meshes["lowhedge"]=[st.commit(),foliage_material("beech",Color(.85,1.0,.74))]
	var d:=c-a;var length:=Vector2(d.x,d.z).length();var yaw:=atan2(-d.z,d.x)
	var count:=maxi(1,roundi(length/1.9))
	for i in count:
		var p:=a+d*(i+.5)/count
		add_foliage("lowhedge",Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3(length/count/1.9,1,1)),p))
	var item:=node(b.region,"ChateauHedge",(a+c)*.5,Vector3(0,yaw,0))
	body(item,[[Vector3(0,.45,0),Vector3(length,.9,.6)]],"earth")

# Topiary cone of clipped box, solid at its core.
func topiary(p: Vector3, height: float) -> void:
	if not foliage_meshes.has("cone"):
		var r:=RandomNumberGenerator.new();r.seed=55
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 150:
			var t:=pow(r.randf(),1.4)
			var y:=t*2.2;var radius:=.75*(1.0-t)
			var a:=r.randf()*TAU;var depth:=pow(r.randf(),.3)
			var q:=Vector3(cos(a)*radius*depth,y,sin(a)*radius*depth)
			leaf_card(st,q,Vector3(cos(a),.35,sin(a)).normalized(),r.randf_range(.38,.5)*(1.0-t*.5),r.randf()*TAU,clampf(.3+.7*depth*(.5+t*.5),0,1))
		foliage_meshes["cone"]=[st.commit(),foliage_material("beech",Color(.78,.95,.7))]
	add_foliage("cone",Transform3D(Basis(Vector3.UP,b.rng.randf()*TAU).scaled(Vector3.ONE*height/2.2),p))
	var item:=node(b.region,"ChateauTopiary",p+Vector3.UP*height*.35)
	var shape:=CylinderShape3D.new();shape.radius=.45*height/2.2;shape.height=height*.7
	body(item,[[Vector3.ZERO,shape]],"earth")

# Vine row on a trellis: posts, two wires and a band of leaves, solid like a hedge.
func vine_row(a: Vector3, c: Vector3) -> void:
	if not foliage_meshes.has("vine"):
		var r:=RandomNumberGenerator.new();r.seed=17
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 26:
			var q:=Vector3(r.randf_range(-1.25,1.25),r.randf_range(.85,1.6),r.randf_range(-.18,.18))
			var out:=Vector3(r.randfn()*.3,r.randf_range(-.2,.6),signf(q.z)+r.randfn()*.4).normalized()
			leaf_card(st,q,out,r.randf_range(.5,.7),r.randf()*TAU,clampf(.4+(q.y-.85)*.6+absf(q.z)*1.5,0,1))
		foliage_meshes["vine"]=[st.commit(),foliage_material("linden",Color(.92,1.02,.72))]
	var d:=c-a;var length:=Vector2(d.x,d.z).length();var yaw:=atan2(-d.z,d.x);var turn:=Basis(Vector3.UP,yaw)
	var count:=maxi(1,roundi(length/2.5))
	for i in count:
		add_foliage("vine",Transform3D(turn.rotated(Vector3.UP,(b.rng.randf()-.5)*.04),a+d*(i+.5)/count))
	for i in count+1:
		trim(Transform3D(turn,a+d*float(i)/count+Vector3.UP*.9),Vector3(.09,1.8,.09),"wood")
	for y in [1.0,1.55]:trim(Transform3D(turn,(a+c)*.5+Vector3.UP*y),Vector3(length,.015,.015),"iron")
	var item:=node(b.region,"ChateauVines",(a+c)*.5,Vector3(0,yaw,0))
	body(item,[[Vector3(0,.85,0),Vector3(length,1.7,.45)]],"earth")

# --- Hooks -------------------------------------------------------------------------------

func boundaries(builder: CompactMapBuilder) -> void:
	b=builder
	var half:=b.def.extent*.5
	var limits:=node(b.region,"Perimeter",Vector3.ZERO)
	body(limits,[[Vector3(-half.x-.25,4,0),Vector3(.5,8,b.def.extent.y)],[Vector3(half.x+.25,4,0),Vector3(.5,8,b.def.extent.y)],
		[Vector3(0,4,-half.y-.25),Vector3(b.def.extent.x,8,.5)],[Vector3(0,4,half.y+.25),Vector3(b.def.extent.x,8,.5)]],"concrete")
	# Tall hedgerows just outside the boundary, the woods beyond them.
	for side:float in [-1.0,1.0]:
		for i in int(b.def.extent.x/3.8)+1:hedge(Vector3(-half.x+1.0+i*3.8,0,side*(half.y+1.4)),0.0)
		for i in int(b.def.extent.y/3.8)+1:hedge(Vector3(side*(half.x+1.4),0,-half.y+1.0+i*3.8),PI*.5)
		for i in 9:tree(Vector3(-half.x+10+i*20+b.rng.randf_range(-4,4),0,side*(half.y+b.rng.randf_range(5.0,9.0))),"walnut" if b.rng.randf()<.4 else "linden",b.rng.randf_range(1.0,1.3))
		for i in 7:
			# Keep z≈0 beyond the west edge clear: the engine's trace tests stand actors there.
			var z:=-half.y+10+i*21+b.rng.randf_range(-4,4)
			if absf(z)<5.0:z=5.0 if z>=0.0 else -5.0
			tree(Vector3(side*(half.x+b.rng.randf_range(5.0,9.0)),0,z),"linden",b.rng.randf_range(1.0,1.3))

func build(builder: CompactMapBuilder) -> void:
	b=builder
	decor.seed=1907
	chateau()
	barrel_hall()
	plaza()
	lawn()
	terrace()
	south_garden()
	north_side()
	west_side()
	turnaround()

func deployment(builder: CompactMapBuilder) -> void:
	b=builder
	for team in 2:
		var side:=-1.0 if team==0 else 1.0
		for row in 4:
			for col in 4:
				(b.def.spawns_blue if team==0 else b.def.spawns_red).append(Vector3(side*(b.def.extent.x*.5-6-col*2),.05,[-30,-10,10,30][row]))

func objectives(builder: CompactMapBuilder) -> void:
	b=builder
	for q in [Vector3(-36,0,-17),Vector3(-36,0,16.8),Vector3(-24,0,-30),Vector3(-24,0,30),Vector3(42,0,-19),Vector3(42,0,22),Vector3(57,0,-24),Vector3(57,0,24)]:
		b.def.ammo_caches.append(q)
		b.box("AmmoCase",q+Vector3(0,.35,0),Vector3(1.1,.7,.65),Color("59644d"))
	for x in [-60,-30,0,30,46]:b.def.routes.append(Vector3(x,.05,-40))
	for x in [-58,-34,-10,11,44]:b.def.routes.append(Vector3(x,.05,0))
	for x in [-60,-30,0,30,60]:b.def.routes.append(Vector3(x,.05,50.5))
	b.def.domination.assign([Vector3(-34,0,0),Vector3(11,0,0),Vector3(47,0,4)])
	b.def.hardpoints.assign([Vector3(11,0,0),Vector3(-10,0,0),Vector3(33,1.0,38),Vector3(6,0,-50),Vector3(47,0,-12)])
	# Points 3-5 are upstairs: the west gallery, the Velvet Room and the balcony.
	b.def.qa_route.assign([Vector3(-80,0,-30),Vector3(-34,0,0),Vector3(-10,0,0),Vector3(3,UPPER,0),Vector3(13,UPPER,-18),Vector3(23.3,UPPER,0),Vector3(11,0,0),Vector3(47,0,4),Vector3(33,1.0,38),Vector3(11,0,-40),Vector3(80,0,30)])
	for room in rooms:b.arena.probe_volumes.append(room)
	flush_interior()
	flush_trims()
	b.nature.scan_clearance(b.arena)
	place_trees()
	flush_foliage()
	flush_grass()
	b.arena.child_order_changed.connect(crisp_sun)
	print("Chateau cover points=",b.def.cover_points.size())

# --- Ground ---------------------------------------------------------------------------------

func rect_distance(rect: Rect2, x: float, z: float) -> float:
	var dx:=maxf(rect.position.x-x,x-rect.end.x);var dz:=maxf(rect.position.y-z,z-rect.end.y)
	return Vector2(maxf(dx,0),maxf(dz,0)).length()+minf(maxf(dx,dz),0.0)

func road_distance(x: float, z: float) -> float:
	var best:=INF;var p:=Vector2(x,z)
	for item in roads:
		var a:=Vector2(item[0].x,item[0].z);var c:=Vector2(item[1].x,item[1].z)
		var t:=clampf((p-a).dot(c-a)/(c-a).length_squared(),0,1)
		best=minf(best,p.distance_to(a+(c-a)*t)-float(item[2])*.5)
	best=minf(best,absf(Vector2(x-TURN.x,z-TURN.z).length()-12.0)-4.2)
	best=minf(best,rect_distance(Rect2(-74,-46,34,92),x,z))
	return best

# R dirt (vineyard soil, worn spots), G gravel (courts, yards, walks, aprons),
# B asphalt (the drive, the turnaround and the car park).
func ground_splat(_builder: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n:=noise.get_noise_2d(x,z)
	var fine:=noise.get_noise_2d(x*3.1+90.0,z*3.1-17.0)
	var road:=1.0-smoothstep(-.4,.4,road_distance(x,z)+n*.4)
	var gravel:=0.0
	for rect:Rect2 in GRAVEL:gravel=maxf(gravel,1.0-smoothstep(-.5,1.4,rect_distance(rect,x,z)+n*1.2))
	gravel=maxf(gravel,1.0-smoothstep(-.3,.9,path_distance(x,z)+n*.8))
	gravel=maxf(gravel,(1.0-smoothstep(.3,1.8,block_distance(x,z)+n*.9))*.55)
	var dirt:=0.0
	for rect:Rect2 in VINES:dirt=maxf(dirt,1.0-smoothstep(-.8,1.6,rect_distance(rect,x,z)+n*1.4))
	dirt=maxf(dirt,smoothstep(.6,.88,fine)*.3)
	gravel*=1.0-road
	dirt*=(1.0-road)*(1.0-gravel*.7)
	return Color(dirt,gravel,road)
