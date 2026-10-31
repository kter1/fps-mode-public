extends RefCounted

# Map-local art: collision-free, instanced emissive fixtures and authored graphics.
# The established colliders and navigation remain the source of gameplay geometry.
const GRAPHICS = preload("res://content/materials/neon/arena_graphics.gdshader")
const CYAN := Color("19dfff")
const PINK := Color("ff279d")
const VIOLET := Color("8250ff")
const GOLD := Color("ffba49")
var b: CompactMapBuilder
var groups := {}
var mats := {}

func _init(builder: CompactMapBuilder) -> void:
	b = builder

func material(color: Color) -> StandardMaterial3D:
	var key := str(color)
	if not mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Unshaded fixtures write HDR colour directly so bloom sees a light source.
		m.albedo_color = Color(color.r*3.0,color.g*3.0,color.b*3.0,1.0)
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 3.0
		mats[key] = m
	return mats[key]

func strip(center: Vector3, size: Vector3, color: Color, rotation := Vector3.ZERO) -> void:
	size = size.snapped(Vector3.ONE * 0.001)
	var key := str(size) + str(color)
	if not groups.has(key):groups[key] = {"size":size,"color":color,"poses":[]}
	groups[key].poses.append(Transform3D(Basis.from_euler(rotation),center))

func line(a: Vector3, z: Vector3, color: Color, width := 0.035) -> void:
	var delta := z-a
	var basis := Basis(Quaternion(Vector3.UP,delta.normalized()))
	strip((a+z)*0.5,Vector3(width,delta.length(),width),color,basis.get_euler())

func panel(center: Vector3, size: Vector2, normal: Vector3, color: Color, graphic := 0, aspect := Vector2.ONE) -> void:
	var q := QuadMesh.new();q.size = size
	var m := ShaderMaterial.new();m.shader = GRAPHICS
	m.set_shader_parameter("ink",color);m.set_shader_parameter("graphic",graphic)
	m.set_shader_parameter("aspect",aspect)
	m.set_shader_parameter("phase",float(b.serial%11));b.serial += 1
	var node := MeshInstance3D.new();node.name = "BlacklightGraphic"
	node.mesh = q;node.material_override = m
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.region.add_child(node)
	node.position = center
	node.basis = Basis.looking_at(-normal,Vector3.FORWARD if absf(normal.y)>0.9 else Vector3.UP)

func text(value: String, center: Vector3, normal: Vector3, color: Color, scale := 0.006, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var node := Label3D.new();node.name = "NeonTypography"
	node.text = value;node.font_size = 96;node.pixel_size = scale
	node.horizontal_alignment = align
	node.modulate = color;node.shaded = false;node.outline_size = 0
	node.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	node.double_sided = false
	node.no_depth_test = false
	b.region.add_child(node);node.position = center
	node.basis = Basis.looking_at(-normal,Vector3.UP)

func ring(center: Vector3, radius: float, color: Color, vertical := false) -> void:
	for i in 48:
		var a := TAU*i/48.0;var z := TAU*(i+1)/48.0
		var p := Vector3(cos(a),sin(a),0) if vertical else Vector3(cos(a),0,sin(a))
		var q := Vector3(cos(z),sin(z),0) if vertical else Vector3(cos(z),0,sin(z))
		line(center+p*radius,center+q*radius,color,0.025)

func maze(center: Vector3, size: Vector3, color: Color) -> void:
	var along_x := size.x>size.z
	var length := size.x if along_x else size.z
	var tangent := Vector3.RIGHT if along_x else Vector3.BACK
	var normal := Vector3.BACK if along_x else Vector3.RIGHT
	for side: float in [-1.0,1.0]:
		var face := center + normal*side*0.185
		panel(face,Vector2(length-0.18,size.y-0.25),normal*side,color,0,Vector2(length*0.5,1.2))
		for y: float in [-1.12,1.25]:
			line(face+tangent*(-length*0.5+0.06)+Vector3.UP*y,face+tangent*(length*0.5-0.06)+Vector3.UP*y,color)
		for end: float in [-1.0,1.0]:
			var p := face+tangent*end*(length*0.5-0.08)
			line(p+Vector3.DOWN*1.1,p+Vector3.UP*1.25,color,0.055)
		# Large luminous chevrons give walls a recognizable arena identity.
		for offset: float in [-1.2,1.2]:
			var p := face+tangent*offset
			line(p-tangent*0.35+Vector3.UP*0.35,p+Vector3.UP*0.65,color,0.06)
			line(p+Vector3.UP*0.65,p+tangent*0.35+Vector3.UP*0.35,color,0.06)

func arena() -> void:
	panel(Vector3(0,0.085,0),Vector2(31.5,31.5),Vector3.UP,VIOLET,2,Vector2(25,25))
	# Tall starship wall murals, high enough to leave every doorway clear.
	for side: float in [-1.0,1.0]:
		# Murals start at the 4.5 m door heads so nothing floats across an opening.
		panel(Vector3(side*15.77,5.35,0),Vector2(30,1.7),Vector3(-side,0,0),CYAN if side<0 else PINK,0,Vector2(13,1.2))
		panel(Vector3(0,4.9,side*15.77),Vector2(30,2.4),Vector3(0,0,-side),VIOLET,4,Vector2(12.5,1))
		text("01  /  ION DRIVE" if side<0 else "02  /  PHOTON ARRAY",Vector3(side*15.72,5.35,0),Vector3(-side,0,0),CYAN if side<0 else PINK,0.008)
		# Lit airlock frames surround the existing three side entrances.
		for z: float in [-8,0,8]:
			for edge: float in [-1.0,1.0]:
				strip(Vector3(side*15.73,1.8,z+edge*1.5),Vector3(0.07,3.6,0.07),CYAN if side<0 else PINK)
			strip(Vector3(side*15.73,3.6,z),Vector3(0.07,0.08,3.05),CYAN if side<0 else PINK)
		for z: float in [-13.6,13.6]:
			line(Vector3(side*13,0.15,z-1.45),Vector3(side*3,3.73,z-1.45),CYAN if side<0 else PINK,0.045)
		# Ceiling ribs and suspended UV tubes establish scale above the maze.
		for x: float in [-12,-6,0,6,12]:
			b.box("UVFixture",Vector3(x,6.22,side*7),Vector3(0.32,0.18,9),Color("111322"),false)
			strip(Vector3(x,6.1,side*7),Vector3(0.08,0.04,8.5),VIOLET)
	# Overhead laser fan: thin cores, distinct from solid gameplay cover.
	for i in 7:
		line(Vector3(-15,5.65,-10+i*3),Vector3(15,4.6,10-i*2.5),PINK if i%2 else CYAN,0.012)
	# Reactor: raised energy lattice over the existing pedestal; no new collision.
	for y: float in [1.2,1.38,2.65]:ring(Vector3(0,y,0),0.95,PINK)
	for i in 8:
		var a := TAU*i/8.0
		line(Vector3(cos(a)*0.7,1.4,sin(a)*0.7),Vector3(cos(a+0.8)*0.45,2.6,sin(a+0.8)*0.45),CYAN,0.045)
	ring(Vector3(0,0.1,0),3.6,VIOLET)
	panel(Vector3(0,1.85,0),Vector2(1.2,1.3),Vector3.BACK,CYAN,3)
	text("REACTOR // 07",Vector3(-1.21,0.65,0),Vector3.LEFT,PINK,0.0024)
	text("REACTOR // 07",Vector3(1.21,0.65,0),Vector3.RIGHT,CYAN,0.0024)
	# Team beacon banners occupy the high walls, never the sightlines at head height.
	text("NEON CIRCUIT",Vector3(0,5.5,15.74),Vector3.FORWARD,PINK,0.012)
	text("ENTER THE GRID",Vector3(0,4.4,15.74),Vector3.FORWARD,CYAN,0.006)
	text("05  /  OBSERVATION DECK",Vector3(0,5.7,-15.74),Vector3.BACK,CYAN,0.007)

func cabinet(pos: Vector3, yaw: float, color: Color, index: int) -> void:
	# Local +Z is the playing side. Body, bezel, recessed animated display,
	# control shelf, joystick, buttons, lit marquee, coin door and side art.
	var t := Transform3D(Basis(Vector3.UP,yaw),pos)
	var turn := Vector3(0,yaw,0)
	var normal := t.basis*Vector3.BACK
	for part in [["ArcadeCab",Vector3(0,.95,0),Vector3(.8,1.9,.9),Color("0d0e1c"),true],
			["ArcadeBezel",Vector3(0,1.34,.46),Vector3(.77,.8,.1),Color("111022"),false],
			["ArcadeControls",Vector3(0,.98,.54),Vector3(.8,.12,.32),Color("1e2140"),false],
			["CoinDoor",Vector3(0,.48,.465),Vector3(.28,.4,.04),Color("080915"),false]]:
		var node: Node3D = b.box(part[0],t*part[1],part[2],part[3],part[4])
		node.rotation = turn
	panel(t*Vector3(0,1.36,.522),Vector2(.62,.57),normal,color,1)
	strip(t*Vector3(-.2,1.09,.62),Vector3(.04,.1,.04),PINK,turn)
	for x: float in [.05,.17,.29]:strip(t*Vector3(x,1.05,.62),Vector3(.06,.018,.075),color,turn)
	strip(t*Vector3(0,1.91,.5),Vector3(.76,.2,.04),color,turn)
	text(["VOID RUN","STAR RAID","ION RUSH","GALAXY","COMET"][index%5],t*Vector3(0,1.91,.525),normal,Color("111022"),0.001)
	strip(t*Vector3(0,.56,.492),Vector3(.12,.035,.018),GOLD,turn)
	for side: float in [-1.0,1.0]:
		panel(t*Vector3(side*.406,1.12,0),Vector2(.8,1.45),t.basis*Vector3(side,0,0),color,0,Vector2(1,2))

func exterior() -> void:
	for side: float in [-1.0,1.0]:
		panel(Vector3(side*30,0.04,0),Vector2(13,21),Vector3.UP,VIOLET,2,Vector2(13,21))
		# Entrance branding sits on the wall above the 4.5 m door head.
		var normal := Vector3(side,0,0)
		text("NEON CIRCUIT",Vector3(side*16.34,5.75,0),normal,CYAN if side<0 else PINK,0.006)
		text("LASER TAG  /  ARCADE",Vector3(side*16.34,4.95,0),normal,Color.WHITE,0.003)
		for y: float in [4.68,6.2]:strip(Vector3(side*16.3,y,0),Vector3(0.04,0.05,5.2),CYAN if side<0 else PINK)

func finish() -> void:
	for data in groups.values():
		var mesh := MapMeshes.block(data.size,0.0,0.0)
		var poses := PackedFloat32Array()
		for pose in data.poses:poses.append_array(MapArena.pack(pose))
		b.arena.instance_batches.append(["NeonFixture"+str(b.arena.instance_batches.size()),mesh,material(data.color),poses,GeometryInstance3D.GI_MODE_DISABLED,0.0,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF])
	groups.clear();b=null
