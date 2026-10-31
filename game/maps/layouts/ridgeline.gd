extends MapLayout

# Ridgeline: four station blocks around a paved courtyard with planting beds,
# crossed by the pipe-rack gantry. Alpine grass with dirt tracks, gravel aprons
# and old snow.

func build(b: CompactMapBuilder) -> void:
	b.modern_building(Vector3(-24,0,0),Vector2(14,22),4.2,"NORTHLINE  /  OPERATIONS")
	b.modern_building(Vector3(24,0,0),Vector2(14,22),4.2,"ENGINEERING")
	b.modern_building(Vector3(0,0,29),Vector2(25,10),4.1,"LOGISTICS")
	b.modern_building(Vector3(0,0,-28),Vector2(25,10),4.3,"COMMUNICATIONS")
	b.bridge()
	# Modern courtyard paving, with usable planting beds instead of cone trees.
	b.box("Pavement",Vector3(0,.012,0),Vector3(30,.024,28),Color("d0d0c8"),false)
	b.footprints.append(Rect2(-15,-14,30,28))
	for x in [-9,9]:
		for z in [-8,8]:
			b.prop("planter_box_02",Vector3(x,0,z),1.15)
			b.prop("potted_plant_02",Vector3(x,.5,z),1.35,0,false)
			b.def.cover_points.append(Vector3(x,0,z+2));b.def.cover_peeks.append(Vector3(x+2,0,z+2))
			b.def.cover_points.append(Vector3(x,0,z-2));b.def.cover_peeks.append(Vector3(x-2,0,z-2))
	for x in [-30,-18,18,30]:
		for z in [-23,23]:b.cover(Vector3(x,0,z),2.4,b.accent)
	for x in [-8,8]:
		for z in [-38,38]:
			b.cover(Vector3(x,0,z),3.3,b.accent)
			b.prop("portable_generator",Vector3(x,0,z+2),.95)
			b.stains.append(Vector3(x,0,z+3))
	for x in [-42,42]:
		for z in [-29,29]:
			b.prop("industrial_pastic_container",Vector3(x,0,z),1.15)
			for i in 3:b.prop("barrel_03",Vector3(x+i*.7,0,z+2),.88)
	b.road_markings()

# Realism pass (runs after the shared dressing): furnished stations, a roof
# mast on the communications block, courtyard wear, site clutter and planting
# (grass clumps, shrubs and young firs in MultiMeshes) inside and around the walls.
func dress(b: CompactMapBuilder) -> void:
	b.building_trim()
	for data in b.buildings:
		station(b,data)
	mast(b,Vector3(8,4.63,-28))
	courtyard(b)
	site(b)
	planting(b)

func station(b: CompactMapBuilder, data: Dictionary) -> void:
	var c:Vector3=data.center;var size:Vector2=data.size;var h:float=data.height
	var area:=Rect2(c.x-size.x*.5+1,c.z-size.y*.5+1,size.x-2,size.y-2)
	for side in [-1,1]:
		var desk:=c+Vector3(side*(size.x*.5-1.7),0,side*(size.y*.5-2))
		var yaw:=0.0 if side<0 else PI
		var turn:=Basis(Vector3.UP,yaw)
		b.small_prop("metal_stool_02",desk+turn*Vector3(-.2,0,-.95),.46,yaw)
		b.small_prop("desk_lamp_arm_01",desk+turn*Vector3(.7,.79,.1),.5,yaw+.4)
		b.small_prop("office_notepads",desk+turn*Vector3(-.4,.79,0),.02,yaw+.2)
		b.small_prop("television_02",desk+turn*Vector3(0,.79,.25),.38,yaw+PI)
	var comms:=c.z<-20
	if comms:
		# Equipment racks in the back corners, a patch panel tray overhead.
		for sx in [-1.0,1.0]:
			for step in 3:b.cabinet(c+Vector3(sx*(size.x*.5-.6-step*.95),0,-size.y*.5+.55),0.0,Color("2e3a40") if step!=1 else Color("3b484e"),.9,2.1,.7)
		b.tray(c+Vector3(-size.x*.5+.5,h-.55,-2),c+Vector3(size.x*.5-.5,h-.55,-2),.5)
		b.wall_sign("RF SUITE  /  NO FOOD OR DRINK",c+Vector3(0,3.1,size.y*.5-.16),Vector3(0,0,-1),Color("d9d5c4"),24)
	else:
		var wide:=size.x>size.y
		if wide:
			b.tray(c+Vector3(-size.x*.5+.6,h-.5,size.y*.5-.5),c+Vector3(size.x*.5-.6,h-.5,size.y*.5-.5),.3)
			b.wall_sign("OPERATIONS LOG  /  SIGN IN",c+Vector3(0,3.1,-size.y*.5+.16),Vector3(0,0,1),Color("d9d5c4"),24)
		else:
			b.tray(c+Vector3(size.x*.5-.5,h-.5,-size.y*.5+.6),c+Vector3(size.x*.5-.5,h-.5,size.y*.5-.6),.3)
			b.wall_sign("OPERATIONS LOG  /  SIGN IN",c+Vector3(-size.x*.5+.16,3.1,0),Vector3(1,0,0),Color("d9d5c4"),24)
			b.wall_sign("EVACUATION ASSEMBLY  >  COURTYARD",c+Vector3(size.x*.5-.16,3.05,0),Vector3(-1,0,0),Color("6fd29a"),22)
	b.low_clutter(data,["bench","crates","trash","cart","pallet"],.55,2.4)
	b.small_prop("security_camera_02",c+Vector3(size.x*.5-.4,h-.4,size.y*.5-.4),.25,atan2(-1,-1))
	b.interior_streaks(data,2)
	b.floor_decals("Leaking009",2,area,Vector2(1.7,1.7),Color(.1,.09,.08,.65),true)
	b.floor_decals("AsphaltDamage001",1,area,Vector2(2.2,2.2),Color(.8,.8,.78,.6),true)

# A guyed lattice mast with antenna arms and a dish on the roof.
func mast(b: CompactMapBuilder, base: Vector3) -> void:
	var steel:=Color("c8cbc8");var red:=Color("c4382c")
	var height:=11.0
	for corner in [Vector2(-.45,-.3),Vector2(.45,-.3),Vector2(0,.5)]:
		b.detail(base+Vector3(corner.x,height*.5,corner.y),Vector3(.08,height,.08),steel,"steel")
	for level in 8:
		var y:=1.0+level*1.35
		var band:=red if level%2==0 else steel
		b.detail(base+Vector3(0,y,-.3),Vector3(.9,.045,.045),band,"steel")
		b.detail(base+Vector3(-.22,y,.1),Vector3(.045,.045,1.0),band,"steel",Vector3(0,.5,0))
		b.detail(base+Vector3(.22,y,.1),Vector3(.045,.045,1.0),band,"steel",Vector3(0,-.5,0))
	for arm in [[height-.4,1.0,0.0],[height-1.6,.8,PI*.5],[height-2.8,.8,PI*.25]]:
		b.detail(base+Vector3(0,float(arm[0]),0),Vector3(float(arm[1])*2.0,.06,.06),steel,"steel",Vector3(0,float(arm[2]),0))
		for end in [-1.0,1.0]:
			b.detail(base+Basis(Vector3.UP,float(arm[2]))*Vector3(end*float(arm[1]),float(arm[0])-.4,0),Vector3(.1,.8,.06),Color("e4e6e2"),"steel",Vector3(0,float(arm[2]),0))
	var dish:=b.cylinder(base+Vector3(-3.2,1.1,1.5),1.0,.07,Color("d8dad6"))
	dish.basis=Basis(Vector3.RIGHT,PI*.32)
	b.detail(base+Vector3(-3.2,.55,1.5),Vector3(.12,1.1,.12),Color("6a7377"),"steel")

func courtyard(b: CompactMapBuilder) -> void:
	# Expansion joints, stains, damp and hairline cracks on the big paved slab.
	for line in range(-12,13,3):
		b.detail(Vector3(line,.03,0),Vector3(.025,.012,28.0),Color("77776f"),"concrete")
	for line in range(-12,13,3):
		b.detail(Vector3(0,.03,line*1.0),Vector3(30.0,.012,.025),Color("77776f"),"concrete")
	var slab:=Rect2(-14.5,-13.5,29,27)
	b.floor_decals("Leaking006",3,slab,Vector2(2.8,2.8),Color(.06,.055,.05,.9))
	b.floor_decals("Leaking009",3,slab,Vector2(3.2,3.2),Color(.1,.09,.08,.85))
	b.floor_decals("Leaking007",3,slab,Vector2(2.6,2.6),Color(.2,.17,.13,.8))
	b.floor_decals("AsphaltDamage001",4,slab,Vector2(2.6,2.6),Color(.8,.8,.78,.55))
	# Planting beds: mulch stain and leaf litter around each planter.
	for x in [-9,9]:
		for z in [-8,8]:b.decal("Leaking007",Vector3(x,0,z),Vector2(3.2,3.2),Vector3.UP,b.rng.randf()*TAU,Color(.16,.13,.09,.7))

func site(b: CompactMapBuilder) -> void:
	# Cones, pallets, reels and fuel cans around the logistics and service areas.
	for spot in [Vector3(-12,0,34.4),Vector3(-8.6,0,34.4),Vector3(12,0,34.4),Vector3(8.6,0,34.4),Vector3(-34,0,-14),Vector3(34,0,14),Vector3(-34,0,14),Vector3(34,0,-14)]:
		if b.clear(spot,Vector2(.3,.3),.1,.8):b.cone(spot)
	for spot in [Vector3(-8,0,34.6),Vector3(9,0,34.6),Vector3(-14.5,0,31),Vector3(14.5,0,31),Vector3(-30,0,27),Vector3(30,0,-27),Vector3(-40,0,-33),Vector3(40,0,33)]:
		b.pallet(spot,b.rng.randf_range(-.2,.2),2)
	for spot in [Vector3(-14,0,-36),Vector3(14,0,-36),Vector3(-52,0,36),Vector3(52,0,-36)]:
		b.cable_reel(spot,b.rng.randf()*PI)
	for spot in [Vector3(-33,0,-39.5),Vector3(33,0,39.5),Vector3(-22,0,40.3),Vector3(22,0,-40.3)]:
		b.pipe_stack(spot,0.0 if spot.x<0 else PI,5.0)
	for spot in [Vector3(-16.5,0,-9.5),Vector3(16.5,0,9.5),Vector3(-4,0,17.5),Vector3(4,0,-17.5),Vector3(-37,0,10),Vector3(37,0,-10)]:
		for i in 2:b.small_prop("trashbag",spot+Vector3(i*.5,0,b.rng.randf_range(-.2,.2)),.5,b.rng.randf()*TAU,i==0)
	for spot in [Vector3(-27,0,12.4),Vector3(27,0,-12.4),Vector3(-27,0,-12.4),Vector3(27,0,12.4)]:
		b.small_prop("small_lpg_tank",spot,.62,b.rng.randf()*TAU,true)
	# Stains and tyre marks on the dirt and gravel tracks, cracks near the doors.
	var yard:=Rect2(-56,-43,112,86)
	b.floor_decals("Leaking006",5,yard,Vector2(2.6,2.6),Color(.06,.055,.045,.6))
	b.floor_decals("Leaking009",4,yard,Vector2(3.0,3.0),Color(.1,.09,.07,.55))
	b.floor_decals("Leaking010A",3,yard,Vector2(2.2,3.2),Color(.1,.085,.06,.5))
	for track in [Vector3(-40,0,0),Vector3(40,0,0),Vector3(-10,0,0),Vector3(10,0,0),Vector3(0,0,-48),Vector3(0,0,48)]:
		var along_x:=absf(track.z)>40
		for i in 2:
			b.decal("TireTracks001",track+(Vector3(b.rng.randf_range(-9,9),0,b.rng.randf_range(-1.5,1.5)) if along_x else Vector3(b.rng.randf_range(-3,3),0,b.rng.randf_range(-9,9))),Vector2(8.0,2.2),Vector3.UP,(0.0 if along_x else PI*.5)+b.rng.randf_range(-.1,.1),Color(.2,.17,.12,.8))
	# Damp and dirt at the foot of the boundary wall.
	for x in range(-56,57,12):
		for side in [-1.0,1.0]:
			b.decal("Leaking008",Vector3(x+b.rng.randf_range(-1,1),.8,side*47.74),Vector2(3.4,1.6),Vector3(0,0,-side),0,Color(1,1,1,.75))
	for z in range(-40,41,12):
		for side in [-1.0,1.0]:
			b.decal("Leaking008",Vector3(side*59.74,.8,z+b.rng.randf_range(-1,1)),Vector2(3.4,1.6),Vector3(-side,0,0),0,Color(1,1,1,.75))

func planting(b: CompactMapBuilder) -> void:
	var nature:=b.nature
	var noise:=FastNoiseLite.new();noise.seed=int(b.rng.seed);noise.frequency=.035;noise.fractal_octaves=3
	nature.scan_clearance(b.arena)
	# Grass clumps wherever the ground splat reads as lawn: patches of sward from
	# noise, none on tracks, gravel, old snow, paving, floors or within reach of a solid.
	var lawn:=func(x:float,z:float)->float:
		var mix:=ground_splat(b,x,z,noise)
		var open:=1.0-smoothstep(.08,.35,maxf(maxf(mix.r,mix.g),mix.b))
		if open<=0.0 or b.footprint_distance(x,z)<.5:return 0.0
		return open*smoothstep(.34,.6,nature.plant_gap(x,z,.45,1.0))
	nature.grass_field(Rect2(-59.5,-47.5,119,95),lawn,func(_x:float,_z:float)->float:return 0.0,.85,38.0,1.0)
	# Shrubs along the inside of the wall and around building corners.
	var shrubs:Array[Vector3]=[]
	for x in range(-54,55,6):
		for side in [-1.0,1.0]:
			var spot:=Vector3(x+b.rng.randf_range(-1.6,1.6),0,side*(47.4-b.rng.randf_range(0,.9)))
			if b.clear(spot,Vector2(.7,.7),.3,1.6):shrubs.append(spot)
	for z in range(-40,41,6):
		for side in [-1.0,1.0]:
			var spot:=Vector3(side*(59.4-b.rng.randf_range(0,.9)),0,z+b.rng.randf_range(-1.6,1.6))
			if b.clear(spot,Vector2(.7,.7),.3,1.6):shrubs.append(spot)
	for data in b.buildings:
		var c:Vector3=data.center;var size:Vector2=data.size
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
			var spot:=c+Vector3(corner.x*(size.x*.5+2.6),0,corner.y*(size.y*.5+2.6))
			if b.clear(spot,Vector2(.7,.7),.3,2.0):shrubs.append(spot)
	nature.bushes(shrubs,Vector2(.75,1.35),75.0)
	# A hedge line of young firs, shrubs and rough grass just outside the walls.
	var firs:Array[Vector3]=[];var outer_shrubs:Array[Vector3]=[]
	for i in 70:
		var along:=b.rng.randf()
		var point:=Vector2.ZERO
		match b.rng.randi()%4:
			0:point=Vector2(lerpf(-62,62,along),-(48.0+b.rng.randf_range(3.0,14.0)))
			1:point=Vector2(lerpf(-62,62,along),48.0+b.rng.randf_range(3.0,14.0))
			2:point=Vector2(-(60.0+b.rng.randf_range(3.0,14.0)),lerpf(-50,50,along))
			3:point=Vector2(60.0+b.rng.randf_range(3.0,14.0),lerpf(-50,50,along))
		firs.append(Vector3(point.x,nature.height(point.x,point.y)-.2,point.y))
	for i in 90:
		var point:=Vector2(b.rng.randf_range(-70,70),b.rng.randf_range(-58,58))
		if absf(point.x)<61.5 and absf(point.y)<49.5:continue
		outer_shrubs.append(Vector3(point.x,nature.height(point.x,point.y)-.05,point.y))
	nature.small_firs(firs)
	nature.bushes(outer_shrubs,Vector2(1.0,1.8),110.0)
	# Rough grass in the strip outside the walls, following the terrain.
	var verge:=func(x:float,z:float)->float:
		var d:=nature.outside(x,z)
		return smoothstep(.6,1.6,d)*(1.0-smoothstep(9.0,15.0,d))
	nature.grass_field(Rect2(-76,-64,152,128),verge,func(x:float,z:float)->float:return nature.height(x,z),1.15,56.0,.8,Vector2(.7,1.4))

func ground_splat(b: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n:=noise.get_noise_2d(x,z)
	var fine:=noise.get_noise_2d(x*3.3+170.0,z*3.3-40.0)
	var apron:=b.footprint_distance(x,z)
	var edge:=minf(b.def.extent.x*.5-absf(x),b.def.extent.y*.5-absf(z))
	var track:=maxf(1.0-smoothstep(2.0,5.0,absf(z)+n*2.5),1.0-smoothstep(1.5,4.0,absf(absf(z)-52.0)+n*2.0))
	track=maxf(track,smoothstep(.38,.75,fine)*.7)
	var gravel:=maxf(1.0-smoothstep(1.5,5.5,apron+n*1.8),1.0-smoothstep(2.0,5.0,edge+n*3.0))
	var snow:=smoothstep(.35,.8,noise.get_noise_2d(x*.6-40.0,z*.6+11.0)+smoothstep(-35.0,-50.0,z)*.35)*(1.0-gravel)
	return Color(track,gravel,snow)
