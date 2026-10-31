extends MapLayout

# Foundry: an assembly hall under a pipe-rack gantry, power rooms to the north,
# freight and loading to the south. Asphalt with concrete aprons, rail ballast
# and weedy dirt edges.

func build(b: CompactMapBuilder) -> void:
	b.modern_building(Vector3.ZERO,Vector2(28,24),5.4,"NORTHLINE  /  ASSEMBLY 04",true)
	b.bridge()
	for x in [-26,26]:
		b.modern_building(Vector3(x,0,25),Vector2(12,10),3.7,"DISPATCH" if x<0 else "SERVICE",false)
		b.modern_building(Vector3(x,0,-27),Vector2(10,10),4,"POWER SYSTEMS",true)
	for x in [-8,8]:
		for z in [-6,6]:
			b.prop("old_military_compressor",Vector3(x,0,z),1.65,PI*.5)
			b.prop("barrel_03",Vector3(x-2,0,z),.88)
	for side in [-1,1]:
		for z in [-7,7]:b.prop("steel_frame_shelves_02",Vector3(side*12,0,z),2.2,side*PI*.5)
		b.prop("industrial_storage_cart",Vector3(side*7,0,10),1.05)
	for x in [-11,1,14]:b.freight(Vector3(x,0,31 if x!=1 else 26),Color("7c7f72") if x<1 else Color("687b84"))
	for x in [-9,9]:
		b.freight(Vector3(x,0,-32),Color("888b87"))
		b.prop("portable_generator",Vector3(x,0,-25),.95,.3)
		b.stains.append(Vector3(x,0,-24))
	for x in [-28,-16,16,28]:
		for z in [-9,9]:b.cover(Vector3(x,0,z),2.4,b.accent)
	for x in [-10,0,10]:
		b.cover(Vector3(x,0,20),2.4,b.accent)
		b.cover(Vector3(x,0,-23),2.4,b.accent)
	for side in [-1,1]:
		for z in [-39,39]:
			b.prop("industrial_pastic_container",Vector3(side*27,0,z),1.15)
			for i in 3:b.prop("barrel_03",Vector3(side*29+i*.7,0,z),.88)
	b.road_markings()

# Realism pass (runs after the shared dressing): roof steel and services in the
# hall, low workshop clutter under the window sills, offices, power rooms, yard
# clutter, signage, stains, tyre marks and wall-base grime.
func dress(b: CompactMapBuilder) -> void:
	b.building_trim()
	for data in b.buildings:
		var center:Vector3=data.center
		if center==Vector3.ZERO:hall(b,data)
		elif data.furnished:office(b,data)
		else:power_room(b,data)
	yard(b)
	grime(b)

func hall(b: CompactMapBuilder, data: Dictionary) -> void:
	var c:Vector3=data.center;var h:float=data.height
	var steel:=Color("566066")
	# Roof trusses, purlins and a ventilation trunk between the baked fixtures.
	for x in [-11.7,-7.0,-2.3,2.3,7.0,11.7]:b.box("RoofBeam",c+Vector3(x,h-.5,0),Vector3(.3,.6,23.7),steel,false)
	for z in [-9.0,-3.0,3.0,9.0]:b.box("RoofBeam",c+Vector3(0,h-.22,z),Vector3(27.7,.2,.18),steel,false)
	for z in [-5.5,5.5]:
		b.box("Ventilation",c+Vector3(0,h-1.3,z),Vector3(24,.7,.75),Color("a9b0b2"),false)
		for end in [-1.0,1.0]:b.detail(c+Vector3(end*12.03,h-1.3,z),Vector3(.06,.8,.85),steel,"steel")
		for x in range(-10,11,5):b.detail(c+Vector3(x,h-.9,z),Vector3(.08,.4,.08),steel,"steel")
	# Pipe racks along the end walls (above the door heads) and cable trays on the long walls.
	for side in [-1.0,1.0]:
		for run in [[3.55,.1,Color("9a2f26")],[3.95,.07,Color("8b9296")],[4.3,.12,Color("2e4f73")]]:
			b.pipe(c+Vector3(side*13.55,run[0],-11.9),c+Vector3(side*13.55,run[0],11.9),run[1],run[2])
		for z in range(-10,11,4):b.detail(c+Vector3(side*13.73,3.95,z),Vector3(.24,1.0,.16),Color("2e3438"),"steel")
		b.tray(c+Vector3(-12.5,4.15,side*11.55),c+Vector3(12.5,4.15,side*11.55))
	# Warm work lights over the machine bays, baked into the floor.
	for x in [-8.0,8.0]:
		for z in [-6.0,6.0]:
			b.box("CeilingLamp",c+Vector3(x,h-.9,z),Vector3(.9,.1,.9),Color("fff0cf"),false)
			b.bake_light(c+Vector3(x,h-1.2,z),Color(1.0,.84,.62),4.2,11.0)
	for z in [-8.0,8.0]:b.bake_light(c+Vector3(0,h-1.2,z),Color(1.0,.92,.8),3.0,11.0)
	# Walkway lines, signs and wall-mounted safety gear.
	for x in [-4.4,4.4]:b.box("RoadDash",c+Vector3(x,.04,0),Vector3(.14,.02,21.0),Color("d2b24a"),false)
	for z in [-5.2,5.2]:b.box("RoadDash",c+Vector3(0,.04,z),Vector3(7.6,.02,.14),Color("d2b24a"),false)
	b.wall_sign("HARD HATS + EYE PROTECTION REQUIRED",c+Vector3(-7,3.35,-11.84),Vector3(0,0,1),Color("e3b93c"),34)
	b.wall_sign("FORKLIFT TRAFFIC  /  KEEP CLEAR",c+Vector3(7,3.35,11.84),Vector3(0,0,-1),Color("e3b93c"),34)
	b.wall_sign("EXIT",c+Vector3(0,3.25,-11.84),Vector3(0,0,1),Color("4fd08a"),40)
	b.wall_sign("EXIT",c+Vector3(0,3.25,11.84),Vector3(0,0,-1),Color("4fd08a"),40)
	b.wall_sign("PRESS LINE 2  /  LOCK OUT TAG OUT",c+Vector3(13.84,3.3,-7),Vector3(-1,0,0),Color("d9d5c4"),30)
	b.wall_sign("COMPRESSED AIR  /  FIRE MAIN",c+Vector3(-13.84,3.3,7),Vector3(1,0,0),Color("d9d5c4"),30)
	for slot in b.wall_slots(data,5.2,1.0,3.2):
		var face:Vector3=slot.face;var inward:Vector3=slot.inward;var yaw:float=slot.yaw
		b.small_prop("korean_fire_extinguisher_01",face+inward*.12+Vector3(0,.3,0),.6,yaw)
		b.small_prop("power_box_01",face+inward*.1+Vector3(0,.35,0)+slot.tangent*1.6,.55,yaw)
	for corner in [Vector3(-1,0,-1),Vector3(1,0,1)]:
		var spot:=c+Vector3(corner.x*13.5,4.6,corner.z*11.4)
		b.small_prop("security_camera_01",spot,.32,atan2(-corner.x,-corner.z))
	b.small_prop("WetFloorSign_01",c+Vector3(3.0,0,-9.4),.62,.6,true)
	b.low_clutter(data,["bench","pallet","cart","crates","drum","pallet","trash"],.8,2.4)
	b.interior_streaks(data,2)
	b.floor_decals("Leaking006",3,Rect2(c.x-12,c.z-10,24,20),Vector2(2.2,2.2),Color(.05,.045,.04,.9),true)
	b.floor_decals("Leaking009",3,Rect2(c.x-12,c.z-10,24,20),Vector2(2.4,2.4),Color(.07,.06,.05,.85),true)
	b.floor_decals("Leaking010A",2,Rect2(c.x-12,c.z-10,24,20),Vector2(1.8,2.6),Color(.1,.08,.06,.8),true)
	b.floor_decals("AsphaltDamage001",3,Rect2(c.x-12,c.z-10,24,20),Vector2(2.6,2.6),Color(.78,.78,.76,.75),true)
	for track in 4:
		b.decal("TireTracks001",c+Vector3([-4.4,4.4,-4.4,4.4][track],0,[-6.0,-6.0,6.0,6.0][track]),Vector2(8.0,2.2),Vector3.UP,PI*.5,Color(.12,.1,.09,.8))

func office(b: CompactMapBuilder, data: Dictionary) -> void:
	var c:Vector3=data.center;var size:Vector2=data.size;var h:float=data.height
	for side in [-1,1]:
		# The two desks the builder placed: stools, lamps, paperwork and a screen.
		var desk:=c+Vector3(side*(size.x*.5-1.7),0,side*(size.y*.5-2))
		var yaw:=0.0 if side<0 else PI
		var turn:=Basis(Vector3.UP,yaw)
		b.small_prop("metal_stool_01",desk+turn*Vector3(-.2,0,-.95),.55,yaw)
		b.small_prop("desk_lamp_arm_01",desk+turn*Vector3(.7,.79,.1),.5,yaw+.4)
		b.small_prop("office_notepads",desk+turn*Vector3(-.4,.79,0),.02,yaw+.2)
		b.small_prop("television_02",desk+turn*Vector3(0,.79,.25),.38,yaw+PI)
	b.low_clutter(data,["bench","crates","trash","cart","pallet"],.6,2.4)
	b.wall_sign("DISPATCH BOARD  /  SHIFT 06:00 - 14:00",c+Vector3(0,3.05,-size.y*.5+.16),Vector3(0,0,1),Color("d9d5c4"),24)
	b.wall_sign("FIRST AID  /  MUSTER POINT B",c+Vector3(0,3.05,size.y*.5-.16),Vector3(0,0,-1),Color("6fd29a"),24)
	b.tray(c+Vector3(-size.x*.5+.8,h-.5,-size.y*.5+.5),c+Vector3(size.x*.5-.8,h-.5,-size.y*.5+.5),.3)
	b.interior_streaks(data,2)
	b.floor_decals("Leaking009",3,Rect2(c.x-size.x*.5+1,c.z-size.y*.5+1,size.x-2,size.y-2),Vector2(1.6,1.6),Color(.1,.09,.08,.7),true)
	b.small_prop("security_camera_01",c+Vector3(size.x*.5-.4,h-.45,size.y*.5-.4),.3,atan2(-1,-1))

func power_room(b: CompactMapBuilder, data: Dictionary) -> void:
	var c:Vector3=data.center;var size:Vector2=data.size;var h:float=data.height
	# Switchgear in the two back corners, conduit and trays overhead, warning signs.
	for sx in [-1.0,1.0]:
		b.cabinet(c+Vector3(sx*(size.x*.5-.6),0,-size.y*.5+.55),0.0,Color("5f6d73"))
		b.cabinet(c+Vector3(sx*(size.x*.5-.6),0,-size.y*.5+1.55),0.0,Color("6c777c"))
	for z in [-3.0,3.0]:b.tray(c+Vector3(-size.x*.5+.5,h-.55,z),c+Vector3(size.x*.5-.5,h-.55,z),.45)
	for run in [[3.25,.07],[3.45,.05]]:
		b.pipe(c+Vector3(-size.x*.5+.5,run[0],size.y*.5-.4),c+Vector3(size.x*.5-.5,run[0],size.y*.5-.4),run[1],Color("a9852a"))
	b.wall_sign("DANGER  /  HIGH VOLTAGE",c+Vector3(0,3.0,-size.y*.5+.16),Vector3(0,0,1),Color("e3b93c"),30)
	b.wall_sign("AUTHORISED PERSONNEL ONLY",c+Vector3(0,3.0,size.y*.5-.16),Vector3(0,0,-1),Color("d9d5c4"),24)
	b.bake_light(c+Vector3(0,h-1.0,-2.0),Color(1.0,.78,.55),2.2,8.0)
	b.low_clutter(data,["crates","drum","trash","cart"],.55,2.2)
	b.interior_streaks(data,2)
	b.floor_decals("Leaking006",3,Rect2(c.x-size.x*.5+1,c.z-size.y*.5+1,size.x-2,size.y-2),Vector2(1.6,1.6),Color(.05,.045,.04,.85),true)
	b.floor_decals("Leaking010A",2,Rect2(c.x-size.x*.5+1,c.z-size.y*.5+1,size.x-2,size.y-2),Vector2(1.4,2.0),Color(.1,.08,.06,.7),true)

func yard(b: CompactMapBuilder) -> void:
	# Cones, pallets and spill kits around the freight containers.
	for freight in [Vector3(-11,0,31),Vector3(1,0,26),Vector3(14,0,31),Vector3(-9,0,-32),Vector3(9,0,-32)]:
		for corner in [Vector2(-3.7,-1.9),Vector2(3.7,1.9)]:
			var spot:Vector3=freight+Vector3(corner.x,0,corner.y)
			if b.clear(spot,Vector2(.3,.3),.1,.8):b.cone(spot)
		b.pallet(freight+Vector3(5.2,0,-1.0),.15,2)
		b.pallet(freight+Vector3(-5.0,0,1.2),-.2,1,false)
	# Goods-in area: loose pallets, drums and tyres along the yard walls.
	for spot in [Vector3(-36,0,-38),Vector3(-31,0,-38.5),Vector3(34,0,38),Vector3(38.5,0,37.5),Vector3(-43,0,29),Vector3(43,0,-29),Vector3(-22,0,38.6),Vector3(22,0,-38.6)]:
		b.pallet(spot,b.rng.randf()*PI,2)
	for spot in [Vector3(-47,0,35),Vector3(47,0,-35),Vector3(-16,0,-39.5),Vector3(17,0,39.6)]:
		for i in 3:b.small_prop("old_tyre",spot+Vector3(b.rng.randf_range(-.2,.2),i*.16,b.rng.randf_range(-.2,.2)),.6,b.rng.randf()*TAU,i==0)
	for spot in [Vector3(-14,0,-39),Vector3(12,0,39),Vector3(-48,0,-36),Vector3(48,0,36)]:
		b.cable_reel(spot,b.rng.randf()*PI)
	for spot in [Vector3(-33,0,-36),Vector3(33,0,36),Vector3(-26,0,40.3),Vector3(26,0,-40.3)]:
		b.pipe_stack(spot,0.0 if spot.x<0 else PI,5.0)
	for spot in [Vector3(-20.5,0,-12.5),Vector3(20.5,0,12.5),Vector3(-5,0,13.2),Vector3(5,0,-13.2),Vector3(-38,0,12),Vector3(38,0,-12)]:
		for i in 2:b.small_prop("trashbag",spot+Vector3(i*.5,0,b.rng.randf_range(-.2,.2)),.5,b.rng.randf()*TAU,i==0)
	b.small_prop("WetFloorSign_01",Vector3(-2.8,0,12.8),.62,.5,true)
	# Stains and tyre marks on the lanes; cracked patches near the doors.
	var yard_area:=Rect2(-52,-42,104,84)
	b.floor_decals("Leaking006",9,yard_area,Vector2(2.8,2.8),Color(.04,.035,.03,.95))
	b.floor_decals("Leaking009",6,yard_area,Vector2(3.0,3.0),Color(.07,.06,.05,.75))
	b.floor_decals("Leaking010A",5,yard_area,Vector2(2.4,3.4),Color(.09,.075,.06,.7))
	b.floor_decals("Leaking007",4,yard_area,Vector2(2.6,2.6),Color(.16,.13,.1,.65))
	b.floor_decals("AsphaltDamage001",8,yard_area,Vector2(3.4,3.4),Color(.7,.7,.68,.8))
	for lane in [Vector3(-20,0,-41),Vector3(20,0,41),Vector3(-31,0,0),Vector3(31,0,0),Vector3(0,0,-44),Vector3(0,0,44)]:
		for i in 2:
			var along_x:=absf(lane.z)>40
			b.decal("TireTracks001",lane+Vector3(b.rng.randf_range(-8,8) if along_x else b.rng.randf_range(-2,2),0,b.rng.randf_range(-1,1) if along_x else b.rng.randf_range(-8,8)),Vector2(8.0,2.2),Vector3.UP,(0.0 if along_x else PI*.5)+b.rng.randf_range(-.08,.08),Color(.05,.045,.04,.95))

func grime(b: CompactMapBuilder) -> void:
	# Damp and dirt at the foot of the boundary wall, leaks under its coping.
	for x in range(-50,51,10):
		for side in [-1.0,1.0]:
			b.decal("Leaking008",Vector3(x+b.rng.randf_range(-1,1),.8,side*44.74),Vector2(3.4,1.6),Vector3(0,0,-side),0,Color(1,1,1,.8))
			if b.rng.randf()<.5:b.decal("Leaking%03d"%[1,2,3,5][b.rng.randi()%4],Vector3(x+3.5,2.4,side*44.74),Vector2(1.7,3.2),Vector3(0,0,-side),0,Color(.85,.82,.76,.7))
	for z in range(-38,39,12):
		for side in [-1.0,1.0]:
			b.decal("Leaking008",Vector3(side*54.74,.8,z+b.rng.randf_range(-1,1)),Vector2(3.4,1.6),Vector3(-side,0,0),0,Color(1,1,1,.8))

func ground_splat(b: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n:=noise.get_noise_2d(x,z)
	var fine:=noise.get_noise_2d(x*3.3+170.0,z*3.3-40.0)
	var apron:=b.footprint_distance(x,z)
	var edge:=minf(b.def.extent.x*.5-absf(x),b.def.extent.y*.5-absf(z))
	var concrete:=maxf(1.0-smoothstep(2.0,7.0,apron+n*2.5),smoothstep(78.0,83.0,absf(x)+n*3.0))
	var ballast:=1.0-smoothstep(4.0,7.5,absf(z+57.0)+n*1.6)
	var dirt:=maxf(1.0-smoothstep(1.0,7.0,edge+n*4.0),smoothstep(.42,.8,fine)*.85)
	return Color(concrete,ballast,dirt*(1.0-concrete*.6))
