class_name MapNature
extends RefCounted

# Everything outside the walled play space: heightmap terrain (the registry's
# style.terrain.kind: "hills", low wooded hills, or "plain", a flat industrial
# plain), fir forests, rock outcrops and an industrial skyline. None of it
# collides or affects navigation; it renders with sky ambient (it lies outside
# the lightmap and its probes).

# Sprig rectangles in LeafSet019 (stem on the right edge, tip on the left).
const SPRIGS := [Rect2(.28,.06,.43,.21),Rect2(.07,.3,.85,.31),Rect2(.03,.63,.94,.35)]
const BARK := "res://content/models/props/Bark014/Bark014_1K-JPG_"
const LEAVES := "res://content/models/props/LeafSet019/LeafSet019_1K-JPG_"
const RIM := 770.0

var builder: MapBuilder
var arena: Node3D
var def: MapDefinition
var noise := FastNoiseLite.new()
var ridged := FastNoiseLite.new()
var patches := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()
var terrain_style: Dictionary = {}

func _init(owner: MapBuilder) -> void:
	builder=owner;arena=owner.arena;def=owner.def
	terrain_style=owner.style.get("terrain",{})
	rng.seed=owner.rng.seed+31
	noise.seed=rng.seed+1;noise.frequency=.0042;noise.fractal_octaves=5
	ridged.seed=rng.seed+2;ridged.frequency=.0019;ridged.fractal_type=FastNoiseLite.FRACTAL_RIDGED;ridged.fractal_octaves=3;ridged.fractal_gain=.42
	patches.seed=rng.seed+3;patches.frequency=.03;patches.fractal_octaves=3

# Distance from the walled play rectangle (0 on and inside the walls).
func outside(x: float, z: float) -> float:
	var half:=def.extent*.5
	return Vector2(maxf(absf(x)-half.x,0.0),maxf(absf(z)-half.y,0.0)).length()

func is_plain() -> bool:
	return terrain_style.get("kind","hills")=="plain"

func height(x: float, z: float) -> float:
	var d:=outside(x,z)
	if d<=0.0:return 0.0
	var n:=noise.get_noise_2d(x,z)*.5+.5
	# A rim that rises toward the terrain's edge (770 m, inside the camera's
	# 900 m far plane) so the edge is always a silhouette against the sky.
	var rim:=smoothstep(520.0,RIM,Vector2(x,z).length())
	if is_plain():return smoothstep(10.0,60.0,d)*n*2.2+rim*(14.0+n*22.0)
	# Low wooded hills around the campus: rolling ground near the boundary, a
	# gentle ridge line farther out, nothing high enough to read as mountains.
	var wx:=noise.get_noise_2d(x*.45+311.0,z*.45)*70.0;var wz:=noise.get_noise_2d(x*.45,z*.45-311.0)*70.0
	var ridge:=smoothstep(.3,.95,ridged.get_noise_2d(x+wx,z+wz)*.5+.5)
	var hills:=smoothstep(4.0,120.0,d)*(3.0+n*18.0)
	var far:=smoothstep(150.0,600.0,d)*(ridge*20.0+n*12.0)
	return hills+far+rim*(18.0+ridge*14.0)

func normal_at(x: float, z: float) -> Vector3:
	var e:=clampf(outside(x,z)*.03,1.5,8.0)
	return Vector3(height(x-e,z)-height(x+e,z),2.0*e,height(x,z-e)-height(x,z+e)).normalized()

# Grid lines: exact on the walls, fine just outside them, coarse at the horizon.
func axis(half: float, outer: float) -> Array[float]:
	var values:Array[float]=[-half,half]
	var x:=-outer
	while x<outer:
		values.append(x)
		var gap:=absf(absf(x)-half)
		x+=clampf(3.0+gap*.035,3.0,12.0) if absf(x)>half-2.0 else 30.0
	values.append(outer)
	values.sort()
	var clean:Array[float]=[]
	for value in values:
		if clean.is_empty() or value-clean.back()>.75:clean.append(value)
	return clean

# Splat for ground.gdshader: hills put R rock on slopes and high ground and
# G dirt over the base layer; the plain puts R and G patches over the base and
# B an asphalt service road ringing the site (layers from style.terrain).
func splat(x: float, z: float, h: float, n: Vector3) -> Color:
	var p:=patches.get_noise_2d(x,z)
	if is_plain():
		var road:=1.0-smoothstep(5.0,7.0,absf(outside(x,z)-16.0))
		return Color(smoothstep(.05,.55,p)*.7*(1.0-road),smoothstep(.35,.7,-p)*.6*(1.0-road),road)
	var slope:=1.0-n.y
	# Rock only where the hillsides steepen; bare earth on slopes and in patches.
	var rock:=smoothstep(.22,.4,slope+p*.06)
	var dirt:=maxf(smoothstep(.2,.65,p)*.55,smoothstep(.1,.22,slope)*.8)*(1.0-rock)
	return Color(rock,dirt,0.0)

func terrain() -> void:
	var half:=def.extent*.5
	var xs:=axis(half.x,RIM+15.0);var zs:=axis(half.y,RIM+15.0)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in zs:
		for x in xs:
			var h:=height(x,z);var n:=normal_at(x,z)
			st.set_color(splat(x,z,h,n));st.set_normal(n);st.set_uv(Vector2(x,z));st.add_vertex(Vector3(x,h,z))
	var row:=xs.size()
	for j in zs.size()-1:
		for i in xs.size()-1:
			if absf((xs[i]+xs[i+1])*.5)<half.x and absf((zs[j]+zs[j+1])*.5)<half.y:continue
			if Vector2((xs[i]+xs[i+1])*.5,(zs[j]+zs[j+1])*.5).length()>RIM:continue
			var a:=j*row+i;var b:=a+1;var c:=a+row;var d:=c+1
			for index in [a,b,c,b,d,c]:st.add_index(index)
	st.generate_tangents()
	var mesh:=st.commit()
	var layers:Array=terrain_style.get("layers",["grass","rock","dirt","snow"])
	var mat:ShaderMaterial=builder.surfaces.ground_material(layers[0],layers[1],layers[2],layers[3],MapCatalog.color(terrain_style.get("tint"))).duplicate()
	if terrain_style.get("steep_projection",false):mat.set_shader_parameter("steep_projection",true)
	# Coarser tiling for kilometre-scale slopes; parallax is wasted at range.
	mat.set_shader_parameter("parallax_depth",0.0)
	mat.set_shader_parameter("base_scale",1.0/4.0);mat.set_shader_parameter("r_scale",1.0/7.0);mat.set_shader_parameter("g_scale",1.0/3.0);mat.set_shader_parameter("b_scale",1.0/6.0)
	mat.set_shader_parameter("macro_amount",.32)
	var node:=MeshInstance3D.new();node.name="Terrain";node.mesh=mesh;node.material_override=mat
	node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	arena.add_child(node)

# --- Fir trees -------------------------------------------------------------

func materials() -> Array[Material]:
	if builder.materials.has("fir_leaves"):return [builder.materials.fir_bark,builder.materials.fir_leaves]
	var bark:=StandardMaterial3D.new()
	bark.albedo_texture=load(BARK+"Color.jpg");bark.normal_enabled=true;bark.normal_texture=load(BARK+"NormalGL.jpg")
	bark.roughness_texture=load(BARK+"Roughness.jpg");bark.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	bark.uv1_scale=Vector3(1.2,1.2,1.0);bark.albedo_color=Color(.8,.78,.74)
	bark.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var leaves:=ShaderMaterial.new();leaves.shader=preload("res://content/materials/foliage.gdshader")
	leaves.set_shader_parameter("albedo_tex",load(LEAVES+"Color.jpg"));leaves.set_shader_parameter("opacity_tex",load(LEAVES+"Opacity.jpg"))
	builder.materials["fir_bark"]=bark;builder.materials["fir_leaves"]=leaves
	return [bark,leaves]

func _card(st: SurfaceTool, base: Vector3, direction: Vector3, length: float, width: float, tilt: float, sprig: Rect2, shade: float) -> void:
	var side:=direction.cross(Vector3.UP)
	if side.length()<.01:side=Vector3.RIGHT
	side=side.normalized().rotated(direction,tilt)
	var tip:=base+direction*length
	var corners:=[base-side*width*.15,base+side*width*.15,tip+side*width*.5,tip-side*width*.5]
	var uvs:=[Vector2(sprig.end.x,sprig.position.y+sprig.size.y*.35),Vector2(sprig.end.x,sprig.position.y+sprig.size.y*.65),Vector2(sprig.position.x,sprig.end.y),Vector2(sprig.position.x,sprig.position.y)]
	for tri in [[0,1,2],[0,2,3]]:
		for k in tri:
			var p:Vector3=corners[k]
			var out:=Vector3(p.x,0,p.z).normalized() if Vector2(p.x,p.z).length()>.01 else direction
			st.set_color(Color(shade*(.62 if k<2 else 1.0),1,1))
			st.set_normal((out*.75+Vector3.UP*.45).normalized())
			st.set_uv(uvs[k]);st.add_vertex(p)

# A fir of the given height: tapered bark trunk plus whorls of crossed sprig
# cards, longest and most drooping at the bottom. Two surfaces: bark, needles.
func fir(seed: int, tall: float) -> ArrayMesh:
	var r:=RandomNumberGenerator.new();r.seed=seed
	var trunk:=MapMeshes.cylinder(tall*.016,tall,7)
	var bark:=SurfaceTool.new();bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Taper the cylinder toward the tip.
	var arrays:=trunk.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		var t:=(vertices[i].y+tall*.5)/tall
		vertices[i]=Vector3(vertices[i].x*lerpf(1.0,.12,t),vertices[i].y+tall*.5,vertices[i].z*lerpf(1.0,.12,t))
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var tapered:=ArrayMesh.new();tapered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	bark.append_from(tapered,0,Transform3D.IDENTITY)
	var leaves:=SurfaceTool.new();leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var first:=tall*.16
	var y:=first
	while y<tall-.4:
		var t:=(y-first)/(tall-first)
		var length:=lerpf(tall*.23,.45,pow(t,.8))*r.randf_range(.85,1.12)
		var count:=r.randi_range(5,7);var spin:=r.randf()*TAU
		for i in count:
			var angle:=spin+TAU*i/count+r.randf_range(-.25,.25)
			var droop:=lerpf(.42,-.12,t)+r.randf_range(-.1,.1)
			var direction:=Vector3(cos(angle)*cos(droop),-sin(droop),sin(angle)*cos(droop))
			var sprig:Rect2=SPRIGS[1+r.randi()%2] if t<.75 else SPRIGS[0]
			for tilt in [-.55,.55]:_card(leaves,Vector3(0,y,0)+direction*tall*.01,direction,length,length*.5,tilt+r.randf_range(-.15,.15),sprig,lerpf(.55,1.0,t))
		y+=r.randf_range(.36,.52)
	for tilt in [0.0,PI*.5]:
		_card(leaves,Vector3(0,tall-1.4,0),Vector3(0,1,0).rotated(Vector3.RIGHT,.08).rotated(Vector3.UP,tilt),1.6,.7,tilt,SPRIGS[0],1.0)
	var mesh:=ArrayMesh.new()
	bark.generate_tangents();bark.commit(mesh)
	leaves.index();leaves.commit(mesh)
	return mesh

var fir_meshes: Array[ArrayMesh] = []
var fir_batches := {}

func plant(position: Vector3, scale := 1.0) -> void:
	if fir_meshes.is_empty():
		for i in 3:fir_meshes.append(fir(700+i*17,[13.0,16.5,20.0][i]))
	# One variant per 160 m cell keeps forests to a few dozen draw calls;
	# rotation and scale vary per tree.
	var cell:=Vector2i(floori(position.x/160),floori(position.z/160))
	var variant:=posmod(cell.x*7+cell.y*13,fir_meshes.size())
	var key:=str(variant)+"@"+str(cell)
	if not fir_batches.has(key):fir_batches[key]={"variant":variant,"transforms":[]}
	fir_batches[key].transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),position))

func flush_trees() -> void:
	var mats:=materials()
	for variant in fir_meshes:
		# Bark surface first, needles second (see fir()).
		variant.surface_set_material(0,mats[0]);variant.surface_set_material(1,mats[1])
	for batch in fir_batches.values():
		var transforms:=PackedFloat32Array()
		for transform in batch.transforms:transforms.append_array(MapArena.pack(transform))
		(arena as MapArena).instance_batches.append(["Firs"+str((arena as MapArena).instance_batches.size()),fir_meshes[batch.variant],null,transforms,GeometryInstance3D.GI_MODE_DISABLED,0.0])
	fir_batches.clear()

# Forests on the lower slopes around the site, thinning out toward the tree
# line; rock outcrops on steeper ground.
func forests(nearest := 6.0) -> void:
	var half:=def.extent*.5
	var trees:=0;var attempts:=0
	while trees<700 and attempts<9000:
		attempts+=1
		var x:=rng.randf_range(-520.0,520.0);var z:=rng.randf_range(-520.0,520.0)
		var d:=outside(x,z)
		if d<nearest or d>460.0:continue
		var h:=height(x,z);var n:=normal_at(x,z)
		if h>95.0+patches.get_noise_2d(x,z)*20.0 or n.y<.78:continue
		# Clumps: keep trees where the patch noise is high, always near the walls.
		if patches.get_noise_2d(x*.6,z*.6)<-.05 and d>40.0:continue
		plant(Vector3(x,h-.3,z),rng.randf_range(.75,1.25)*(1.0+d*.0012))
		trees+=1
	flush_trees()
	var rocks:=MapProps.new(arena)
	var placed:=0;attempts=0
	while placed<70 and attempts<4000:
		attempts+=1
		var x:=rng.randf_range(-360.0,360.0);var z:=rng.randf_range(-360.0,360.0)
		var d:=outside(x,z)
		if d<nearest:continue
		var n:=normal_at(x,z)
		if n.y>.93 and rng.randf()<.7:continue
		var id:String=["boulder_01","rock_face_01","rock_face_02","rock_moss_set_02"][rng.randi()%4]
		var scale:=rng.randf_range(1.2,3.2)*(1.0+d*.004)
		var node:=rocks.place(id,rocks.grounded(id,Vector3(x,height(x,z)-.35*scale,z),rng.randf()*TAU,scale),false,420.0)
		for child in node.get_children():
			if child is GeometryInstance3D:child.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		placed+=1

# --- Industrial skyline ----------------------------------------------------------

var tools := {}

func _tool(kind: String) -> SurfaceTool:
	if not tools.has(kind):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);tools[kind]=st
	return tools[kind]

func _add(kind: String, mesh: ArrayMesh, transform: Transform3D, surface := 0) -> void:
	_tool(kind).append_from(mesh,surface,transform)

# A factory block: four walls with rows of windows, a roof slab, a parapet and
# dark glazing, merged into per-material skyline meshes.
func factory(center: Vector3, size: Vector3, facade: String, yaw: float) -> void:
	var turn:=Basis(Vector3.UP,yaw)
	for side in [-1.0,1.0]:
		for along_x in [true,false]:
			var length:=size.x if along_x else size.z
			var openings:=[]
			var rows:=int((size.y-3.0)/4.2)
			for row in rows:
				var count:=int((length-3.0)/5.0)
				for i in count:
					openings.append(Rect2(length*(i+.5)/count-1.2,2.4+row*4.2,2.4,1.9))
			var wall:=MapMeshes.wall(Vector3(length,size.y,.4),openings,1.2)
			var local:=Vector3(0,size.y*.5,side*size.z*.5) if along_x else Vector3(side*size.x*.5,size.y*.5,0)
			var wall_turn:=turn*(Basis.IDENTITY if along_x else Basis(Vector3.UP,PI*.5))
			_add(facade,wall,Transform3D(wall_turn,center+turn*local))
			var outward:=turn*(Vector3(0,0,side) if along_x else Vector3(side,0,0))
			for rect in openings:
				var pane:=center+turn*local+wall_turn*Vector3(rect.position.x+rect.size.x*.5-length*.5,rect.position.y+rect.size.y*.5-size.y*.5,0)
				MapMeshes.add_quad(_tool("glass"),pane+outward*.02,Vector3.UP.cross(outward),Vector3.UP,rect.size)
	_add("roof",MapMeshes.block(Vector3(size.x,.4,size.z),.02,0.0),Transform3D(turn,center+Vector3(0,size.y+.2,0)))
	for side in [-1.0,1.0]:
		_add(facade,MapMeshes.block(Vector3(size.x+.4,1.0,.4),.02,0.0),Transform3D(turn,center+turn*Vector3(0,size.y+.7,side*size.z*.5)))
		_add(facade,MapMeshes.block(Vector3(.4,1.0,size.z),.02,0.0),Transform3D(turn,center+turn*Vector3(side*size.x*.5,size.y+.7,0)))

func skyline(nearest := 30.0) -> void:
	var half:=def.extent*.5
	var blocks:Array[Rect2]=[]
	var attempts:=0
	while blocks.size()<34 and attempts<900:
		attempts+=1
		var far:=blocks.size()>=16
		var side:=rng.randi()%4
		var distance:=rng.randf_range(nearest,nearest+55.0) if not far else rng.randf_range(130.0,320.0)
		var along:=rng.randf_range(-1.0,1.0)*(half.x+120.0 if side<2 else half.y+120.0)
		var center:=Vector3(along,0,(half.y+distance)*(1 if side==0 else -1)) if side<2 else Vector3((half.x+distance)*(1 if side==2 else -1),0,along)
		var size:=Vector3(rng.randf_range(22.0,58.0),rng.randf_range(9.0,26.0)*(1.4 if far else 1.0),rng.randf_range(16.0,40.0))
		var rect:=Rect2(center.x-size.x*.5-6,center.z-size.z*.5-6,size.x+12,size.z+12)
		if blocks.any(func(other:Rect2):return other.intersects(rect)):continue
		if outside(center.x,center.z)<size.length()*.5+nearest*.5:continue
		blocks.append(rect)
		center.y=height(center.x,center.z)-.3
		factory(center,size,["brick","precast","corrugated","brick"][rng.randi()%4],PI*.5*(rng.randi()%2))
	# Chimney stacks, storage tanks and a pipe bridge give the plant its outline.
	for i in 7:
		var angle:=rng.randf_range(-PI,PI)
		var center:=Vector3(cos(angle)*(half.x+rng.randf_range(60,220)),0,sin(angle)*(half.y+rng.randf_range(60,220)))
		if outside(center.x,center.z)<40.0:continue
		var radius:=rng.randf_range(1.8,3.2);var tall:=rng.randf_range(38.0,64.0)
		center.y=height(center.x,center.z)+tall*.5
		_add("stack",MapMeshes.cylinder(radius,tall,28),Transform3D(Basis.IDENTITY,center))
		for band in [tall*.5-1.4,tall*.5-6.0]:_add("roof",MapMeshes.cylinder(radius*1.06,.9,28),Transform3D(Basis.IDENTITY,center+Vector3(0,band,0)))
	for i in 5:
		var center:=Vector3(rng.randf_range(-1,1)*(half.x+90),0,-(half.y+rng.randf_range(40,95)))
		var radius:=rng.randf_range(6.0,10.0);var tall:=rng.randf_range(9.0,15.0)
		center.y=height(center.x,center.z)+tall*.5
		_add("tank",MapMeshes.cylinder(radius,tall,40),Transform3D(Basis.IDENTITY,center))
	var mats:={"brick":builder.surfaces.get_material("brick"),"precast":builder.surfaces.get_material("precast"),
		"corrugated":builder.surfaces.get_material("corrugated",Color("5f6b70")),"roof":builder.surfaces.get_material("corrugated",Color("3b4246")),
		"stack":builder.surfaces.get_material("brick"),"tank":builder.surfaces.get_material("painted_metal",Color("8c9294"))}
	var glass:=StandardMaterial3D.new();glass.albedo_color=Color(.06,.08,.09);glass.roughness=.1;glass.metallic=.2
	mats["glass"]=glass
	for kind in tools:
		var st:SurfaceTool=tools[kind]
		if kind=="glass":st.index()
		st.generate_tangents()
		var node:=MeshInstance3D.new();node.name="Skyline_"+kind;node.mesh=st.commit();node.material_override=mats[kind]
		node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		# No shadows: they would pop at the real-time shadow distance because the
		# skyline is not in the baked shadowmask.
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arena.add_child(node)
	tools.clear()

# --- Site vegetation -----------------------------------------------------------
# Bushes, small firs and grass clumps inside and around the walled site. Pure
# decoration: batched into MultiMeshes per 24 m cell with a visibility range,
# no collision, no navigation, lit by the baked probes.

func _flora(label: String, mesh: Mesh, material: Material, transforms: PackedFloat32Array, reach: float, shadows: bool) -> void:
	var arena_map:=arena as MapArena
	arena_map.instance_batches.append([label+str(arena_map.instance_batches.size()),mesh,material,transforms,GeometryInstance3D.GI_MODE_DYNAMIC,reach,GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])

# --- Ground grass ------------------------------------------------------------
# Soft clumps of photographed blades (content/materials/grass_clump, composed by
# tools/generate_grass_clumps.gd) on three crossed cards, grown wherever a
# layout's suitability function allows and thinned or thickened by noise, so a
# lawn is patches of sward with graded edges instead of scattered single tufts.
# Batched per 16 m cell and variant; the shader (grass_clump.gdshader) shrinks
# clumps into the ground at the fade distance and sways their tips.

const CLUMP := "res://content/materials/grass_clump/"
const CLUMP_CARD := .5

var sward := FastNoiseLite.new()
var lump := FastNoiseLite.new()
var grass_rng := RandomNumberGenerator.new()  # separate from rng: forests must not move when grass changes
var clump_meshes: Array[ArrayMesh] = []
var clearance: Clearance

# Solid boxes of the map (StaticBody3D shapes below a node), for keeping plants
# off walls, fences, props and trunks. Query points are horizontal positions
# tested at the heights the plant occupies.
class Clearance extends RefCounted:
	const CELL := 4.0
	var boxes: Array = []   # [Transform3D (world to box, metric), half extents, ground rect]
	var grid := {}

	func scan(node: Node, to_world := Transform3D.IDENTITY) -> void:
		var here:=to_world
		if node is Node3D:here=to_world*(node as Node3D).transform
		if node is StaticBody3D:
			for child in node.get_children():
				if child is CollisionShape3D and not (child as CollisionShape3D).disabled and (child as CollisionShape3D).shape!=null:
					add(here*(child as CollisionShape3D).transform,(child as CollisionShape3D).shape)
		for child in node.get_children():scan(child,here)

	func add(world: Transform3D, shape: Shape3D) -> void:
		var half:=Vector3.ZERO;var middle:=Vector3.ZERO
		if shape is BoxShape3D:half=(shape as BoxShape3D).size*.5
		elif shape is CylinderShape3D:half=Vector3((shape as CylinderShape3D).radius,(shape as CylinderShape3D).height*.5,(shape as CylinderShape3D).radius)
		elif shape is SphereShape3D:half=Vector3.ONE*(shape as SphereShape3D).radius
		elif shape is CapsuleShape3D:half=Vector3((shape as CapsuleShape3D).radius,(shape as CapsuleShape3D).height*.5,(shape as CapsuleShape3D).radius)
		else:
			var box:=shape.get_debug_mesh().get_aabb();half=box.size*.5;middle=box.get_center()
		var scale:=Vector3(world.basis.x.length(),world.basis.y.length(),world.basis.z.length())
		var turned:=Transform3D(world.basis.orthonormalized(),world*middle)
		half*=scale
		var top:=turned.origin.y+absf(turned.basis.x.y)*half.x+absf(turned.basis.y.y)*half.y+absf(turned.basis.z.y)*half.z
		var low:=turned.origin.y-(absf(turned.basis.x.y)*half.x+absf(turned.basis.y.y)*half.y+absf(turned.basis.z.y)*half.z)
		# The ground slab is not an obstacle; neither is anything above tree-crown height.
		if top<.02 or low>14.0:return
		var index:=boxes.size()
		var reach:=Vector3(absf(turned.basis.x.x)*half.x+absf(turned.basis.y.x)*half.y+absf(turned.basis.z.x)*half.z,0,absf(turned.basis.x.z)*half.x+absf(turned.basis.y.z)*half.y+absf(turned.basis.z.z)*half.z)
		boxes.append([turned.affine_inverse(),half,Rect2(turned.origin.x-reach.x,turned.origin.z-reach.z,reach.x*2.0,reach.z*2.0)])
		for gx in range(floori((turned.origin.x-reach.x)/CELL),floori((turned.origin.x+reach.x)/CELL)+1):
			for gz in range(floori((turned.origin.z-reach.z)/CELL),floori((turned.origin.z+reach.z)/CELL)+1):
				var key:=Vector2i(gx,gz)
				if not grid.has(key):grid[key]=PackedInt32Array()
				grid[key].append(index)

	# Distance from the vertical line through (x, z) at the given heights to the
	# nearest solid (negative inside one), looking no further than `look` metres.
	# `thickest` skips solids narrower than that (poles and posts) for large crowns.
	func gap(x: float, z: float, heights: Array, look := 3.0, thickest := 0.0) -> float:
		var best:=look
		for gx in range(floori((x-look)/CELL),floori((x+look)/CELL)+1):
			for gz in range(floori((z-look)/CELL),floori((z+look)/CELL)+1):
				var key:=Vector2i(gx,gz)
				if not grid.has(key):continue
				for index in grid[key]:
					var box:Array=boxes[index]
					var rect:Rect2=box[2]
					if x<rect.position.x-best or x>rect.end.x+best or z<rect.position.y-best or z>rect.end.y+best:continue
					var half:Vector3=box[1]
					if thickest>0.0 and minf(half.x,half.z)<thickest:continue
					for y:float in heights:
						var local:Vector3=(box[0] as Transform3D)*Vector3(x,y,z)
						var q:=local.abs()-half
						var d:=Vector3(maxf(q.x,0.0),maxf(q.y,0.0),maxf(q.z,0.0)).length() if maxf(q.x,maxf(q.y,q.z))>0.0 else maxf(q.x,maxf(q.y,q.z))
						best=minf(best,d)
		return best

# Collects the solids below `root` (call once everything solid is placed).
func scan_clearance(root: Node) -> Clearance:
	clearance=Clearance.new();clearance.scan(root)
	return clearance

# Metres from a plant of the given radius and height to the nearest solid
# (negative: it would grow through one). Without a scan every spot is clear.
func plant_gap(x: float, z: float, height: float, look := 2.0) -> float:
	if clearance==null:return 9.0
	return clearance.gap(x,z,[.02,height*.3,height*.65,height],look)

# Slides a plant whose crown reaches `reach` metres from its stem away from the
# solids around it until it clears them all; null when it cannot be made to fit.
func fit(point: Vector3, reach: float, height: float, heights := [], thin := 0.0) -> Variant:
	if clearance==null:return point
	var p:=point
	if heights.is_empty():heights=[.25,height*.5,height*.9]
	for step in 10:
		var here:=clearance.gap(p.x,p.z,heights,reach+1.5,thin)
		if here>=reach:return p
		var e:=.2
		var away:=Vector2(clearance.gap(p.x+e,p.z,heights,reach+1.5,thin)-clearance.gap(p.x-e,p.z,heights,reach+1.5,thin),clearance.gap(p.x,p.z+e,heights,reach+1.5,thin)-clearance.gap(p.x,p.z-e,heights,reach+1.5,thin))
		if away.length()<.001:away=Vector2.RIGHT.rotated(step*1.3)
		away=away.normalized()
		p+=Vector3(away.x,0,away.y)*(reach-here+.05)
	return null

func grass_material(fade_end: float) -> Material:
	var key:="grass_clump"+str(fade_end)
	if builder.materials.has(key):return builder.materials[key]
	var mat:=ShaderMaterial.new();mat.shader=preload("res://content/materials/grass_clump.gdshader")
	mat.set_shader_parameter("albedo_tex",load(CLUMP+"color.png"))
	mat.set_shader_parameter("opacity_tex",load(CLUMP+"opacity.png"))
	mat.set_shader_parameter("normal_tex",load(CLUMP+"normal.png"))
	mat.set_shader_parameter("fade_start",fade_end*.62);mat.set_shader_parameter("fade_end",fade_end)
	builder.materials[key]=mat
	return mat

# Three crossed 0.5 m cards (60 degrees apart) showing one clump of the atlas,
# three rows tall so the tips can sway. Vertex colour R is the height up the card.
func grass_clump(variant: int) -> ArrayMesh:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var column:=float(variant%2);var row:=float(variant/2)
	var inset:=.004
	var rows:=4
	for card in 3:
		var turn:=Basis(Vector3.UP,PI*card/3.0)
		var side:=turn*Vector3.RIGHT
		for step in rows-1:
			var t0:=float(step)/(rows-1);var t1:=float(step+1)/(rows-1)
			var corners:=[[-1.0,t0],[1.0,t0],[1.0,t1],[-1.0,t1]]
			for tri in [[0,1,2],[0,2,3]]:
				for k in tri:
					var corner:Array=corners[k]
					var u:float=(corner[0]+1.0)*.5;var t:float=corner[1]
					st.set_color(Color(t,1,1));st.set_normal(Vector3.UP);st.set_tangent(Plane(side,1.0))
					st.set_uv(Vector2((column+inset+u*(1.0-inset*2.0))*.5,(row+inset+(1.0-t)*(1.0-inset*2.0))*.5))
					st.add_vertex(side*float(corner[0])*CLUMP_CARD*.5+Vector3.UP*t*CLUMP_CARD)
	return st.commit()

# Grows grass over `area`. suit(x, z) -> 0..1 says how much grass the ground
# there allows (0 on paths, floors, roads and beside solids); ground(x, z) is the
# ground height. Tufts grow in clusters on a jittered grid `spacing` metres apart:
# patches of sward come from noise with graded rims, a fine lumpiness thins the
# middle of a patch, and each accepted cluster is a main clump with a few smaller
# ones around it, so growth is uneven and overlapping instead of evenly spaced.
# Returns the number of clumps.
func grass_field(area: Rect2, suit: Callable, ground: Callable, spacing := .85, reach := 36.0, density := 1.0, tall := Vector2(.5,1.05)) -> int:
	if clump_meshes.is_empty():
		for i in 4:clump_meshes.append(grass_clump(i))
		sward.seed=int(rng.seed)+5;sward.frequency=.038;sward.fractal_octaves=3
		lump.seed=int(rng.seed)+6;grass_rng.seed=int(rng.seed)+7;lump.frequency=.23;lump.fractal_octaves=2
	var arena_map:=arena as MapArena
	var groups:={}
	var count:=0
	var nx:=int(area.size.x/spacing);var nz:=int(area.size.y/spacing)
	for i in nx:
		for j in nz:
			var cx:=area.position.x+(i+grass_rng.randf())*spacing;var cz:=area.position.y+(j+grass_rng.randf())*spacing
			var big:=sward.get_noise_2d(cx,cz)*.5+.5
			var core:=smoothstep(.22,.5,big)
			var fine:=lump.get_noise_2d(cx,cz)*.5+.5
			if grass_rng.randf()>core*lerpf(.6,1.0,fine)*density:continue
			var members:=1+int(core*lerpf(1.5,3.2,fine)+grass_rng.randf()*1.6)
			for member in members:
				var x:=cx;var z:=cz
				if member>0:
					x+=grass_rng.randfn()*spacing*.34;z+=grass_rng.randfn()*spacing*.34
				if not area.has_point(Vector2(x,z)):continue
				# The ground and clearance test comes last: it is the expensive part.
				var weight:float=suit.call(x,z)
				if weight<=.02 or grass_rng.randf()>weight:continue
				var size:=1.0 if member==0 else grass_rng.randf_range(.5,.95)
				var height:=lerpf(tall.x,tall.y,clampf(core*.6+fine*.4+grass_rng.randf_range(-.15,.15),0.0,1.0))*lerpf(.75,1.0,weight)*size
				var wide:=grass_rng.randf_range(.8,1.5)*lerpf(.8,1.0,weight)*lerpf(.75,1.0,size)
				var basis:=Basis(Vector3.UP,grass_rng.randf()*TAU)*Basis(Vector3.RIGHT,grass_rng.randf_range(-.1,.1))*Basis(Vector3.FORWARD,grass_rng.randf_range(-.1,.1))
				var at:=Vector3(x,float(ground.call(x,z))-.02,z)
				var variant:=grass_rng.randi()%clump_meshes.size()
				var key:=str(variant)+"@"+str(Vector2i(floori(x/16.0),floori(z/16.0)))
				if not groups.has(key):groups[key]={"variant":variant,"transforms":PackedFloat32Array()}
				groups[key].transforms.append_array(MapArena.pack(Transform3D(basis.scaled(Vector3(wide,height,wide)),at)))
				count+=1
	for group in groups.values():
		arena_map.instance_batches.append(["Grass"+str(arena_map.instance_batches.size()),clump_meshes[group.variant],grass_material(reach-4.0),group.transforms,GeometryInstance3D.GI_MODE_DYNAMIC,reach,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])
	print("Grass clumps=",count)
	return count

# A shrub: a ball of leaf cards using the fir needle sheet, recoloured.
func bush(seed: int, radius: float) -> ArrayMesh:
	var r:=RandomNumberGenerator.new();r.seed=seed
	var leaves:=SurfaceTool.new();leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=30
	for i in count:
		var angle:=r.randf()*TAU;var rise:=r.randf_range(.2,1.2)
		var direction:=Vector3(cos(angle)*cos(rise),sin(rise),sin(angle)*cos(rise))
		var length:=radius*r.randf_range(.65,1.0)
		_card(leaves,Vector3(0,.1,0)+direction*.04,direction,length,length*.62,r.randf()*TAU,SPRIGS[1+r.randi()%2],lerpf(.45,1.0,float(i)/count))
	leaves.index()
	var mesh:=ArrayMesh.new()
	leaves.commit(mesh)
	return mesh

func bush_material() -> Material:
	if builder.materials.has("bush_leaves"):return builder.materials.bush_leaves
	var mat:ShaderMaterial=(materials()[1] as ShaderMaterial).duplicate()
	mat.set_shader_parameter("tint",Color(.72,.78,.42))
	builder.materials["bush_leaves"]=mat
	return mat

var bush_meshes: Array[ArrayMesh] = []

func bushes(points: Array, size := Vector2(.7,1.3), reach := 70.0) -> void:
	if bush_meshes.is_empty():
		for i in 3:bush_meshes.append(bush(300+i*11,[1.0,1.25,.85][i]))
	var groups:={}
	for point:Vector3 in points:
		var cell:=Vector2i(floori(point.x/64),floori(point.z/64))
		var variant:=posmod(cell.x*5+cell.y*11,bush_meshes.size())
		var key:=str(variant)+"@"+str(cell)
		if not groups.has(key):groups[key]={"variant":variant,"transforms":PackedFloat32Array()}
		var s:=rng.randf_range(size.x,size.y)
		var spot:Variant=fit(point,[1.0,1.25,.85][variant]*s*.95,1.2*s)
		if spot==null:continue
		groups[key].transforms.append_array(MapArena.pack(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(s,s*rng.randf_range(.85,1.2),s)),spot)))
	for group in groups.values():
		if group.transforms.size()>0:_flora("Bush",bush_meshes[group.variant],bush_material(),group.transforms,reach,false)

# Young firs (4 to 8 m) in the hedge line just outside the walls.
func small_firs(points: Array, reach := 140.0) -> void:
	var mats:=materials()
	var meshes_:Array[ArrayMesh]=[]
	for i in 3:
		var mesh:=fir(900+i*13,[4.6,6.2,7.8][i])
		mesh.surface_set_material(0,mats[0]);mesh.surface_set_material(1,mats[1])
		meshes_.append(mesh)
	var groups:={}
	for point:Vector3 in points:
		var cell:=Vector2i(floori(point.x/96),floori(point.z/96))
		var variant:=posmod(cell.x*3+cell.y*5,meshes_.size())
		var key:=str(variant)+"@"+str(cell)
		if not groups.has(key):groups[key]={"variant":variant,"transforms":PackedFloat32Array()}
		var s:=rng.randf_range(.85,1.25)
		groups[key].transforms.append_array(MapArena.pack(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*s),point)))
	for group in groups.values():_flora("SmallFir",meshes_[group.variant],null,group.transforms,reach,false)
