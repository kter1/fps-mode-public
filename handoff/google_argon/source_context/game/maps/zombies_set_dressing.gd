class_name ZombiesSetDressing
extends RefCounted

# Retained circulation and colliders stay separate from the ruin dressing.
# Tall silhouettes live in existing nav exclusion islands or add explicit clearance.
static var stain_image: ImageTexture
static var finishes: Dictionary = {}

static func stain_texture() -> ImageTexture:
	if stain_image==null:
		var image:=Image.create(128,128,false,Image.FORMAT_RGBA8)
		var noise:=FastNoiseLite.new();noise.seed=8041;noise.frequency=.09;noise.fractal_octaves=4
		for y in 128:
			for x in 128:
				var uv:=Vector2(x-64,y-64)/64.0
				var edge:=clampf((1-uv.length())*3,0,1)
				var grain:=clampf((noise.get_noise_2d(x,y)+.15)*2,0,1)
				image.set_pixel(x,y,Color(1,1,1,edge*grain*.8))
		stain_image=ImageTexture.create_from_image(image)
	return stain_image

static func patch(parent: Node3D, at: Vector3, size: Vector2, color: Color, rotation := Vector3(-PI*.5,0,0)) -> void:
	var node:=Decal.new();node.texture_albedo=stain_texture();node.modulate=color;node.size=Vector3(size.x,.7,size.y)
	node.basis=Basis.from_euler(rotation)*Basis(Vector3.RIGHT,PI*.5)
	node.normal_fade=.4;node.distance_fade_enabled=true;node.distance_fade_begin=28;node.distance_fade_length=12
	parent.add_child(node);node.position=at

static func worn_wood(builder: ZombiesMapBuilder) -> ShaderMaterial:
	if not finishes.has("worn_wood"):
		var material:=builder.surfaces.get_material("wood").duplicate() as ShaderMaterial
		material.set_shader_parameter("tint",Color("8b8c74"));material.set_shader_parameter("tint_mix",.86);material.set_shader_parameter("paint_gain",1.15)
		material.set_shader_parameter("grime_amount",1.0);material.set_shader_parameter("roughness_offset",.15);finishes["worn_wood"]=material
	return finishes["worn_wood"]

static func timber(builder: ZombiesMapBuilder, label: String, at: Vector3, size: Vector3, solid := false) -> Node3D:
	var node:=builder.box(label,at,size,Color("6c6c56"),solid)
	(node.get_child(0) as MeshInstance3D).material_override=worn_wood(builder)
	return node

static func prop(builder: ZombiesMapBuilder, id: String, at: Vector3, yaw: float, width: float, depth: float, height: float) -> Node3D:
	var bounds:=builder.props.bounds(id)
	var scale:=minf(width/maxf(.01,bounds.size.x),minf(depth/maxf(.01,bounds.size.z),height/maxf(.01,bounds.size.y)))
	return builder.props.place(id,builder.props.grounded(id,at,yaw,scale),false)

static func dress(builder: ZombiesMapBuilder, map_id: String, index: int, center: Vector3, obstacles: Array) -> void:
	var room:=Node3D.new();room.name="RuinDressing_%d"%index;builder.region.add_child(room)
	var random:=RandomNumberGenerator.new();random.seed=8064+index*37+(1000 if map_id=="dead_air" else 0)
	var warm:=map_id=="dead_current"
	# Broken furniture and fallen fixtures inhabit the already excluded side islands.
	for side in [-1,1]:
		var at:=center+Vector3(side*7.4,0,5.5)
		prop(builder,"painted_wooden_bench",at,PI*.5,1.15,3.6,.85)
		prop(builder,"painted_wooden_chair_01",at+Vector3(.2,0,1.4),side*.8,.8,.8,1.2)
		prop(builder,"wooden_crate_01",at+Vector3(-.12,0,-1.3),.3,.9,.9,.7)
		prop(builder,"trashbag",at+Vector3(.25,0,.3),0,.7,.7,.6)
		patch(room,at+Vector3(0,.012,0),Vector2(3,5),Color("222820"))
	# Uneven timber flooring and strong overhead silhouettes break the empty-box reading.
	if warm and index in [0,2,4]:
		var floor:=builder.box("RuinFloor",center+Vector3(0,.012,0),Vector3(18,.02,22),Color("504b3d"),false)
		(floor.get_child(0) as MeshInstance3D).material_override=worn_wood(builder)
	for z in [-9.5,-3.5,3.5,9.5]:
		var beam:=builder.box("RuinBeam",center+Vector3(0,4.3,z),Vector3(21.6,.28,.27),Color("454a40"),false)
		(beam.get_child(0) as MeshInstance3D).material_override=worn_wood(builder) if warm else builder.surfaces.get_material("rust")
	for side in [-1,1]:
		for z in [-8.5,8.5]:
			builder.box("RuinColumn",center+Vector3(side*9.7,2.2,z),Vector3(.38,4.4,.45),Color("5d6255"),false)
		# Damp rising plaster and grime accumulate at walls, not randomly in the air.
		for z in [-8.0,0.0,8.0]:
			builder.decal("Leaking004",center+Vector3(side*10.72,1.4,z),Vector2(4.5,3.1),Vector3(-side,0,0),0,Color("a1a48c"))
		for x in [-7.5,0.0,7.5]:
			builder.decal("Leaking007",center+Vector3(x,1.4,side*12.72),Vector2(3.5,3.2),Vector3(0,0,-side),0,Color("969f85"))
	# Small debris is nonblocking and below a normal step; larger props never occupy a route.
	var debris:=SurfaceTool.new();debris.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 80:
		var x:=random.randf_range(-8.5,8.5);var z:=random.randf_range(-10.5,10.5)
		var mesh:=MapMeshes.block(Vector3(random.randf_range(.08,.38),random.randf_range(.025,.07),random.randf_range(.08,.4)),.008,.1,false)
		debris.append_from(mesh,0,Transform3D(Basis(Vector3.UP,random.randf_range(-PI,PI)),center+Vector3(x,.05,z)))
		if i%10==0:patch(room,center+Vector3(x,.035,z),Vector2(2.8,2.1),Color("3e3026"))
	var debris_node:=MeshInstance3D.new();debris_node.name="BatchedPlasterDebris";debris_node.mesh=debris.commit();debris_node.material_override=builder.surfaces.get_material("plaster");debris_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;room.add_child(debris_node)
	var paper:=SurfaceTool.new();paper.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		var at:=center+Vector3(random.randf_range(-8,8),.055,random.randf_range(-10,10))
		var sheet:=MapMeshes.block(Vector3(.21,.002,.3),0,0,false)
		paper.append_from(sheet,0,Transform3D(Basis(Vector3.UP,random.randf_range(-PI,PI)),at))
	var paper_node:=MeshInstance3D.new();paper_node.name="BatchedScatteredPaper";paper_node.mesh=paper.commit();var paper_material:=StandardMaterial3D.new();paper_material.albedo_color=Color("aaa183");paper_material.roughness=.95;paper_node.material_override=paper_material;paper_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;room.add_child(paper_node)
	# Service pipes, bent ventilation and worn electrical hardware establish each room.
	prop(builder,"modular_industrial_pipes_01",center+Vector3(-9.6,0,-8.4),PI*.5,1.2,2.5,3.4)
	prop(builder,"power_box_01",center+Vector3(9.6,1.2,-7.5),-PI*.5,.7,.5,1.1)
	prop(builder,"korean_fire_extinguisher_01",center+Vector3(9.6,0,7.8),0,.35,.35,.9)
	if index==0:
		# A barricaded stair ruin is a landmark, with clearance in the navigation mesh.
		var stair:=center+Vector3(-7.7,0,-6.5)
		obstacles.append(Rect2(Vector2(stair.x-1.8,stair.z-5.9),Vector2(3.6,7.4)))
		for step in 9:timber(builder,"RuinStep",stair+Vector3(0,.12+step*.12,-step*.45),Vector3(2.2,.24+step*.24,.5),true)
		timber(builder,"RuinLanding",stair+Vector3(0,2.15,-4.6),Vector3(2.5,.25,1.3),true)
		for side in [-1,1]:
			var boundary:=builder.box("RuinStairSide",stair+Vector3(side*1.25,1.35,-2),Vector3(.12,2.7,5.8),Color("333c38"),true);boundary.get_child(0).hide()
			for y in [.5,1.2,1.9]:timber(builder,"StairRail",stair+Vector3(side*1.25,y,-2),Vector3(.12,.13,5.8))
			for z in [-4.8,.8]:timber(builder,"StairPost",stair+Vector3(side*1.25,1.35,z),Vector3(.14,2.7,.14))
		var barricade:=builder.box("StairDebris",stair+Vector3(0,.8,.45),Vector3(2.6,1.6,.5),Color("484c3d"),true);barricade.get_child(0).hide()
		for i in 5:
			var plank:=timber(builder,"StairPlank",stair+Vector3(0,.22+i*.31,.7),Vector3(2.6,.2,.12));plank.rotation.z=.07 if i%2==0 else -.06
		ZombieObjects.label(room,"UPPER FLOOR SEALED",stair+Vector3(0,1.7,.8),Color("c1b085"),30)
	if not warm:
		prop(builder,"television_02",center+Vector3(8.8,1,-9.6),-.5,.8,.5,.65)
		prop(builder,"hand_truck",center+Vector3(-8.8,0,9.8),.8,.6,.7,1.2)
	else:
		prop(builder,"metal_jerrycan",center+Vector3(8.9,0,9.7),.4,.4,.4,.55)
