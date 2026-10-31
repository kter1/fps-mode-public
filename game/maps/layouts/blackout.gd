extends MapLayout

# Blackout Station: a coastal power station at dusk, the evening the grid went
# down. Only the generator-fed floodlights and the amber emergency fittings are
# lit. The sea is to the south (+Z); spawns are at the short ends in the gatehouse
# (west) and the stores (east). Three lanes run east-west:
#   north  - the switchyard: three main transformers between blast walls under
#            lattice gantries, breaker rows and relay kiosks on the flanks
#   middle - the turbine hall: two turbine-generator sets, a control deck along
#            the north wall reached by two ramps, roller doors at both ends
#   south  - the cooling-water intake: the pump house between two fuel-oil tanks
#            in their bunds, a pipe rack, and the seawall promenade
# The playable space is mirrored across X = 0 so both teams get the same cover.
# Beyond the fences are the boiler house, its chimney, a cooling tower and the
# dead transmission lines walking into the hills, and to the south a bay
# between two headlands.

const DECK := 3.4
const RAMP_FOOT := 17.6
const HALL := Vector2(42,22)
const HALL_H := 11.0
const PUMP := Vector3(0,0,29)
const PUMP_SIZE := Vector2(18,10)
const TANK_X := 30.0
const TANK_Z := 29.0
const SEAWALL := 45.0
const SEA_Y := -3.2

const STEEL := Color("48535a")
const GALV := Color("8d9394")
const TRANSFORMER := Color("6b7a6e")
const YELLOW := Color("c9a33a")
const RED := Color("a33a2c")
const TANK_PAINT := Color("b9b8ad")
const SODIUM := Color(1.0,.6,.27)
const EMERGENCY := Color(1.0,.5,.24)

var b: CompactMapBuilder
var glows := {}

# --- Outside the fence: hills, the bay, the station beyond -------------------------

class CoastNature extends MapNature:
	func _init(owner: MapBuilder) -> void:super(owner)
	# The shore follows the seawall across the site, then sweeps south into two
	# headlands that close the bay.
	func shore(x: float) -> float:
		var reach:=maxf(0.0,absf(x)-58.0)/42.0
		return 45.5+reach*reach*30.0+noise.get_noise_2d(x*2.0,7.0)*4.0*smoothstep(58.0,90.0,absf(x))
	# The station's own grounds north of the fence stay flat.
	func plant_ground(x: float, z: float) -> float:
		return smoothstep(-160.0,-140.0,x)*(1.0-smoothstep(85.0,105.0,x))*smoothstep(-205.0,-185.0,z)*(1.0-smoothstep(-52.0,-46.0,z))
	func height(x: float, z: float) -> float:
		var land:=super(x,z)
		# Wooded banks rise close behind the west and east fences.
		var d:=outside(x,z)
		land+=smoothstep(4.0,40.0,d)*(4.0+noise.get_noise_2d(x*3.0,z*3.0)*5.0)*(1.0-plant_ground(x,z))
		var edge:=shore(x)
		if z<=edge:return land
		return lerpf(land,-16.0+noise.get_noise_2d(x,z)*4.0,smoothstep(edge,edge+14.0,z))
	# No trees in the sea, in the station's coal yard north of the fence or on the beach.
	func plant(position: Vector3, scale := 1.0) -> void:
		if position.y<1.2 or position.z>shore(position.x)-6.0:return
		if plant_ground(position.x,position.z)>.05:return
		super(position,scale)
	func terrain() -> void:
		super()
		(arena.get_node("Terrain") as GeometryInstance3D).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func boundaries(builder: CompactMapBuilder) -> void:
	b=builder
	# Leave room for the capsule and the follower's corner tolerance; the finer
	# grid preserves a walkable strip between the control-ramp parapets.
	b.region.navigation_mesh.agent_radius=.75
	b.region.navigation_mesh.cell_size=.25
	b.nature=CoastNature.new(b)
	b.ground_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var half:=b.def.extent*.5
	# Palisade on three sides (the backdrop shows through it), the seawall on the fourth.
	for side:float in [-1.0,1.0]:
		palisade(Vector3(side*half.x,0,-half.y),Vector3(side*half.x,0,SEAWALL-.6))
		invisible_wall("PerimeterFence",Vector3(side*(half.x+.2),3.2,0),Vector3(.4,6.4,b.def.extent.y))
	palisade(Vector3(-half.x,0,-half.y),Vector3(half.x,0,-half.y))
	invisible_wall("PerimeterFence",Vector3(0,3.2,-half.y-.2),Vector3(b.def.extent.x,6.4,.4))
	seawall()
	sea()
	# A belt of firs on the banks either side of the site (flushed with the forests).
	var placed:=0
	while placed<260:
		var x:=b.rng.randf_range(60.0,170.0)*(1.0 if placed%2==0 else -1.0);var z:=b.rng.randf_range(-130.0,60.0)
		var y:=b.nature.height(x,z)
		if y<1.5 or z>(b.nature as CoastNature).shore(x)-8.0:continue
		b.nature.plant(Vector3(x,y-.3,z),b.rng.randf_range(.8,1.25))
		placed+=1
	station_backdrop()

func invisible_wall(label: String, center: Vector3, size: Vector3) -> void:
	var holder:=Node3D.new();holder.name=label+str(b.serial);b.serial+=1
	b.region.add_child(holder);holder.position=center
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
	var shape:=CollisionShape3D.new();var volume:=BoxShape3D.new();volume.size=size;shape.shape=volume
	body.add_child(shape);holder.add_child(body)

# Steel palisade: a concrete kerb, posts every 2.75 m, two rails and close pales.
func palisade(a: Vector3, c: Vector3) -> void:
	var run:=c-a;var length:=run.length();var along:=run/length
	var yaw:=Vector3(0,atan2(-along.z,along.x),0)
	var bays:=ceili(length/2.75)
	b.detail((a+c)*.5+Vector3(0,.15,0),Vector3(length,.3,.3),Color("9c9a92"),"concrete",yaw)
	for k in bays+1:b.detail(a+run*k/bays+Vector3(0,1.4,0),Vector3(.12,2.8,.12),STEEL,"steel",yaw)
	for y:float in [.75,2.2]:b.detail((a+c)*.5+Vector3(0,y,0),Vector3(length,.06,.05),STEEL,"steel",yaw)
	var pales:=int(length/.2)
	for k in pales:b.detail(a+along*(k+.5)*length/pales+Vector3(0,1.55,0),Vector3(.065,2.5,.022),STEEL,"steel",yaw)

# The site ends at a concrete seawall: a parapet with a rail on top, the wall face
# dropping into the water and rock armour at its toe.
func seawall() -> void:
	var half:=b.def.extent*.5
	b.box("Perimeter",Vector3(0,.55,SEAWALL-.35),Vector3(b.def.extent.x,1.1,.5),b.stone)
	b.box("Coping",Vector3(0,1.14,SEAWALL-.35),Vector3(b.def.extent.x+.1,.08,.66),Color("8f8d86"),false)
	b.railing_path([Vector3(-half.x+.3,1.18,SEAWALL-.35),Vector3(half.x-.3,1.18,SEAWALL-.35)],.95,Color("6a7072"),2.4,false)
	invisible_wall("PerimeterSea",Vector3(0,3.2,SEAWALL+.1),Vector3(b.def.extent.x,6.4,.4))
	var face:=b.box("BoundaryWall",Vector3(0,-6.0,SEAWALL+.2),Vector3(130,12,.8),b.stone,false)
	(face.get_child(0) as GeometryInstance3D).gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	var rocks:=MapProps.new(b.arena)
	for i in 44:
		var x:=-64.0+i*3.0+b.rng.randf_range(-1,1)
		var id:String=["boulder_01","rock_moss_set_02"][i%2]
		# Armour stones 1.6-2.6 m tall, their tops below the promenade.
		var scale:=b.rng.randf_range(1.6,2.6)/maxf(rocks.bounds(id).size.y,.01)
		var node:=rocks.place(id,rocks.grounded(id,Vector3(x,SEA_Y-1.0,SEAWALL+2.0+b.rng.randf_range(0,2.0)),b.rng.randf()*TAU,scale),false,320.0)
		for child in node.get_children():
			if child is GeometryInstance3D:child.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	# Lifebuoys and ladders on the parapet; the cooling-water outfall below it.
	for x:float in [-36.0,-12.0,12.0,36.0]:
		b.detail(Vector3(x,.75,SEAWALL-.66),Vector3(.7,.7,.1),Color("c4532f"),"steel")
		b.detail(Vector3(x,.75,SEAWALL-.72),Vector3(.38,.38,.02),Color("dcd6c4"),"concrete")
		for y in 9:b.detail(Vector3(x+.9,-.3-y*.3,SEAWALL+.62),Vector3(.5,.04,.04),Color("6f6a5e"))
	for x:float in [-4.0,4.0]:
		var outfall:=b.cylinder(Vector3(x,-2.2,SEAWALL+1.6),1.1,2.4,Color("6b6a63"));outfall.rotation.x=PI*.5
		outfall.gi_mode=GeometryInstance3D.GI_MODE_DISABLED

func sea() -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners:=[Vector3(-900,0,SEAWALL+.5),Vector3(900,0,SEAWALL+.5),Vector3(900,0,900),Vector3(-900,0,900)]
	for index in [0,1,2,0,2,3]:
		var p:Vector3=corners[index];st.set_normal(Vector3.UP);st.set_uv(Vector2(p.x,p.z));st.add_vertex(p)
	st.generate_tangents()
	var mat:=ShaderMaterial.new();mat.shader=load("res://content/materials/harbor_water.gdshader")
	mat.set_shader_parameter("near_color",Color("1d3338"));mat.set_shader_parameter("far_color",Color("3f525a"))
	for slot in [["wave_a",23,.02],["wave_b",61,.05]]:
		var noise:=FastNoiseLite.new();noise.seed=int(slot[1]);noise.frequency=float(slot[2]);noise.fractal_octaves=4
		var waves:=NoiseTexture2D.new();waves.width=512;waves.height=512;waves.seamless=true;waves.as_normal_map=true;waves.bump_strength=7.0;waves.noise=noise
		mat.set_shader_parameter(slot[0],waves)
	var node:=MeshInstance3D.new();node.name="BaySea";node.mesh=st.commit();node.material_override=mat
	node.position.y=SEA_Y;node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.arena.add_child(node)

# --- Backdrop structures (no collision, outside the lightmap) ------------------------

# Merged struts and blocks for one far structure: one draw per material.
var far_parts := {}

func far_box(center: Vector3, size: Vector3, kind: String, color := Color.WHITE, rotation := Basis.IDENTITY) -> void:
	var key:=kind+color.to_html(false)
	if not far_parts.has(key):
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		far_parts[key]={"st":st,"kind":kind,"color":color}
	(far_parts[key].st as SurfaceTool).append_from(MapMeshes.block(size,0.0,0.0),0,Transform3D(rotation,center))

func far_strut(a: Vector3, c: Vector3, width: float, color: Color) -> void:
	var run:=c-a
	if run.length()<.01:return
	far_box((a+c)*.5,Vector3(width,run.length(),width),"painted_metal",color,Basis(Quaternion(Vector3.UP,run.normalized())))

func flush_far(label: String) -> void:
	for data in far_parts.values():
		var node:=MeshInstance3D.new();node.name=label+str(b.serial);b.serial+=1
		node.mesh=(data.st as SurfaceTool).commit();node.material_override=b.surfaces.get_material(data.kind,data.color)
		node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
		b.arena.add_child(node)
	far_parts.clear()

func station_backdrop() -> void:
	var ground:=func(x:float,z:float)->float:return b.nature.height(x,z)
	# Boiler house: a tall brick block with long window strips and its bunker bay,
	# on a plinth deep enough to meet the rolling ground.
	var house:=Vector3(-4,ground.call(-4.0,-95.0),-95)
	far_box(house+Vector3(0,13,0),Vector3(46,42,22),"brick")
	far_box(house+Vector3(0,34.4,0),Vector3(46.6,.8,22.6),"concrete",Color("77756f"))
	# Tall window bays between concrete pilasters, sill bands and a parapet.
	for x in range(-20,21,5):
		for y:float in [10.0,22.0]:
			far_box(house+Vector3(x,y,11.02),Vector3(2.6,8.0,.1),"painted_metal",Color("20272b"))
			for k in 3:far_box(house+Vector3(x,y-2.0+k*2.0,11.1),Vector3(2.6,.1,.12),"painted_metal",Color("3b4346"))
			far_box(house+Vector3(x,y,11.1),Vector3(.1,8.0,.12),"painted_metal",Color("3b4346"))
	for x in range(-22,24,5):far_box(house+Vector3(x-.5,15.5,11.3),Vector3(1.1,39.0,.6),"concrete",Color("a19b8f"))
	for y:float in [5.6,17.6,27.6]:far_box(house+Vector3(0,y,11.25),Vector3(46.4,.5,.5),"concrete",Color("a19b8f"))
	far_box(house+Vector3(0,35.6,0),Vector3(46.2,1.6,22.2),"brick")
	far_box(house+Vector3(-31,6,2),Vector3(16,28,16),"corrugated",Color("6f7a7c"))
	# The plant's near buildings: workshop, stores and the coal conveyor gallery.
	for spot in [[Vector3(-38,0,-60),Vector3(26,9,12),"corrugated",Color("7d8784")],[Vector3(48,0,-63),Vector3(18,7,10),"brick",Color.WHITE],[Vector3(-92,0,-84),Vector3(14,6,20),"corrugated",Color("6c7a6e")]]:
		var at:Vector3=spot[0];var size:Vector3=spot[1]
		at.y=ground.call(at.x,at.z)
		far_box(at+Vector3(0,size.y*.5-1.0,0),size+Vector3(0,2.0,0),spot[2],spot[3])
		far_box(at+Vector3(0,size.y+1.05,0),Vector3(size.x+.6,.3,size.z+.6),"painted_metal",Color("4e5558"))
		for k in int(size.x/4.0):far_box(at+Vector3(-size.x*.5+2.0+k*4.0,size.y*.55,size.z*.5+.06),Vector3(1.8,1.4,.1),"painted_metal",Color("1f2629"))
	far_box(Vector3(0,ground.call(0.0,-52.0)+.05,-52),Vector3(260,.12,7),"asphalt")
	far_strut(Vector3(-100,ground.call(-100.0,-60.0),-60),house+Vector3(-31,20,0),2.8,Color("6f7a7c"))
	for k in 4:
		var t:=.15+k*.22
		var leg:=Vector3(-100,0,-60).lerp(house+Vector3(-31,0,0),t);leg.y=ground.call(leg.x,leg.z)
		far_box(leg+Vector3(0,10.0*t,0),Vector3(.8,20.0*t+2.0,.8),"painted_metal",Color("59605f"))
	# Chimney with its painted bands and dark aviation lights.
	var stack:=Vector3(30,ground.call(30.0,-104.0),-104)
	var chimney:=MeshInstance3D.new();chimney.name="Chimney";chimney.mesh=MapMeshes.cylinder(4.0,104.0,28,6.0)
	chimney.material_override=b.surfaces.get_material("concrete");chimney.position=stack+Vector3(0,48,0)
	chimney.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;b.arena.add_child(chimney)
	for y:float in [82.0,92.0]:
		var band:=MeshInstance3D.new();band.mesh=MapMeshes.cylinder(4.08,3.0,28);band.position=stack+Vector3(0,y,0)
		band.material_override=b.surfaces.get_material("painted_metal",RED);band.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;b.arena.add_child(band)
	# Cooling tower: a hyperboloid shell, far enough to sit in the haze.
	cooling_tower(Vector3(-112,ground.call(-112.0,-150.0)-2.0,-150),19.0,96.0)
	# Transmission lines leave the switchyard gantries and fan out over the hills.
	for side:float in [-1.0,1.0]:
		var previous:Array[Vector3]=[]
		for k in 3:previous.append(Vector3(side*12+(k-1)*1.2,11.6,-37.8))
		for i in 4:
			var spot:=Vector3(side*(40.0+i*30.0+i*i*6.0),0,-75.0-i*72.0)
			spot.y=ground.call(spot.x,spot.z)
			var arms:=pylon(spot,32.0)
			for k in 3:far_strut(previous[k],arms[k]-Vector3(0,1.6,0),.07,Color("22282b"))
			previous=arms
	flush_far("StationBackdrop")

func cooling_tower(base: Vector3, waist: float, height: float) -> void:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings:=16;var segments:=48
	var radius:=func(y:float)->float:
		var t:=(y-height*.78)/(height*.62)
		return waist*sqrt(1.0+t*t*1.7)
	for j in rings+1:
		var y:=height*j/rings;var r:float=radius.call(y)
		var slope:=(float(radius.call(y+.5))-float(radius.call(y-.5)))
		for i in segments+1:
			var a:=TAU*i/segments
			var n:=Vector3(cos(a),-slope,sin(a)).normalized()
			st.set_normal(n);st.set_uv(Vector2(a*r,height-y)*.25);st.add_vertex(base+Vector3(cos(a)*r,y,sin(a)*r))
	for j in rings:
		for i in segments:
			var a:=j*(segments+1)+i;var c:=a+segments+1
			for index in [a,a+1,c,a+1,c+1,c]:st.add_index(index)
	st.generate_tangents()
	var node:=MeshInstance3D.new();node.name="CoolingTower";node.mesh=st.commit()
	node.material_override=b.surfaces.get_material("concrete");node.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
	b.arena.add_child(node)

# A lattice transmission tower; returns the three conductor attachment points.
func pylon(base: Vector3, height: float) -> Array[Vector3]:
	var color:=Color("5e6566")
	var levels:=[0.0,8.0,15.0,20.0,26.0,height]
	var widths:=[3.6,2.5,1.7,1.4,1.1,.4]
	for k in levels.size()-1:
		var y0:float=levels[k];var y1:float=levels[k+1];var w0:float=widths[k];var w1:float=widths[k+1]
		for sx:float in [-1.0,1.0]:
			for sz:float in [-1.0,1.0]:far_strut(base+Vector3(sx*w0,y0,sz*w0),base+Vector3(sx*w1,y1,sz*w1),.2,color)
			far_strut(base+Vector3(sx*w0,y0,-w0),base+Vector3(-sx*w1,y1,-w1),.09,color)
			far_strut(base+Vector3(sx*w0,y0,w0),base+Vector3(-sx*w1,y1,w1),.09,color)
			far_strut(base+Vector3(-w0,y0,sx*w0),base+Vector3(-w1,y1,-sx*w1),.09,color)
			far_strut(base+Vector3(w0,y0,sx*w0),base+Vector3(w1,y1,-sx*w1),.09,color)
	var arms:Array[Vector3]=[]
	for arm in [[20.0,7.0],[26.0,5.5]]:
		var y:float=arm[0];var span:float=arm[1]
		far_box(base+Vector3(0,y,0),Vector3(span*2,.5,.9),"painted_metal",color)
		if y<21:arms.append_array([base+Vector3(-span+.3,y,0),base+Vector3(span-.3,y,0)])
		else:arms.insert(1,base+Vector3(span-.3,y,0))
	return arms

# --- Shared parts -------------------------------------------------------------------

func glow(color: Color, energy: float) -> StandardMaterial3D:
	var key:=color.to_html()+str(energy)
	if not glows.has(key):
		var mat:=StandardMaterial3D.new();mat.albedo_color=color.darkened(.2);mat.emission_enabled=true
		mat.emission=color;mat.emission_energy_multiplier=energy;mat.roughness=.4
		glows[key]=mat
	return glows[key]

# A bulkhead emergency fitting (glowing lens on a dark body) with its baked light.
func emergency_lamp(position: Vector3, energy: float, reach: float, color := EMERGENCY) -> void:
	b.box("LampHousing",position+Vector3(0,.07,0),Vector3(.42,.14,.2),Color("2b2f31"),false)
	var lens:=b.box("EmergencyLens",position-Vector3(0,.03,0),Vector3(.34,.08,.14),color,false)
	(lens.get_child(0) as MeshInstance3D).material_override=glow(color,6.0)
	var lamp:=OmniLight3D.new();lamp.name="EmergencyLight"+str(b.serial);b.serial+=1
	lamp.position=position-Vector3(0,.3,0);lamp.light_color=color;lamp.light_energy=energy;lamp.light_indirect_energy=1.6
	lamp.omni_range=reach;lamp.omni_attenuation=1.2;lamp.shadow_enabled=true;lamp.light_size=.25
	lamp.light_bake_mode=Light3D.BAKE_STATIC
	b.region.add_child(lamp)

# A portable lighting tower: wheeled base, telescopic mast, two sodium heads.
func work_light(base: Vector3, target: Vector3) -> void:
	b.box("LightTowerBase",base+Vector3(0,.55,0),Vector3(1.4,.9,.9),YELLOW)
	b.detail(base+Vector3(0,1.0,0),Vector3(1.5,.04,1.0),Color("2a2e30"))
	for sx:float in [-.55,.55]:b.detail(base+Vector3(sx,.2,.48),Vector3(.38,.38,.12),Color("15181a"))
	b.cylinder(base+Vector3(0,2.6,0),.06,3.2,GALV)
	var head:=base+Vector3(0,4.3,0)
	b.detail(head,Vector3(1.2,.06,.06),GALV,"steel",Vector3(0,atan2(-(target.z-base.z),target.x-base.x)+PI*.5,0))
	flood_lamp(head+Vector3(0,.25,0),target,4.0,16.0)

# A green running-man exit sign over a doorway (glow only, no light of its own).
func exit_sign(position: Vector3, yaw: float) -> void:
	var sign:=b.box("ExitSign",position,Vector3(.62,.24,.08),Color("2fa35a"),false);sign.rotation.y=yaw
	(sign.get_child(0) as MeshInstance3D).material_override=glow(Color("3fd27a"),3.0)

# Generator-fed floodlight mast: a galvanised pole and a sodium lantern aimed at target.
func flood_mast(base: Vector3, height: float, target: Vector3, energy := 5.0, reach := 34.0) -> void:
	b.cylinder(base+Vector3(0,height*.5,0),.13,height,GALV)
	b.collider(base+Vector3(0,height*.5,0),Vector3(.3,height,.3),"metal")
	b.detail(base+Vector3(0,.2,0),Vector3(.6,.4,.6),Color("8c8a84"),"concrete")
	var head:=base+Vector3(0,height+.1,0)
	var flat:=Vector3(target.x-head.x,0,target.z-head.z).normalized()
	b.detail(head+Vector3(0,.1,0)+flat*.15,Vector3(.5,.08,.08),GALV,"steel",Vector3(0,atan2(-flat.z,flat.x),0))
	flood_lamp(head+flat*.4,target,energy,reach)

# A sodium floodlight head (lantern, glowing lens, baked spot light) aimed at target.
func flood_lamp(head: Vector3, target: Vector3, energy: float, reach: float) -> void:
	var aim:=(target-head).normalized()
	var facing:=Basis.looking_at(aim,Vector3.UP)
	var lantern:=b.box("Floodlight",head,Vector3(.7,.5,.24),Color("1e2224"),false);lantern.basis=facing
	var lens:=b.box("FloodLens",head+aim*.13,Vector3(.6,.4,.03),SODIUM,false);lens.basis=facing
	(lens.get_child(0) as MeshInstance3D).material_override=glow(SODIUM,9.0)
	var spot:=SpotLight3D.new();spot.name="Floodlight"+str(b.serial);b.serial+=1
	spot.position=head+aim*.3;spot.basis=facing
	spot.light_color=SODIUM;spot.light_energy=energy;spot.light_indirect_energy=1.3
	spot.spot_range=reach;spot.spot_angle=48;spot.spot_angle_attenuation=.8;spot.spot_attenuation=1.1
	spot.shadow_enabled=true;spot.light_size=.3;spot.light_bake_mode=Light3D.BAKE_STATIC
	b.region.add_child(spot)

func strut(a: Vector3, c: Vector3, width: float, color: Color) -> void:
	var run:=c-a
	if run.length()<.01:return
	b.detail((a+c)*.5,Vector3(width,run.length(),width),color,"steel",Basis(Quaternion(Vector3.UP,run.normalized())).get_euler())

# A wall pierced by openings (Rect2: x from the wall's centre, y from the base,
# width, height). The visual is one mesh with real reveals; collision fills the
# solid strips around the openings. Openings must be symmetric about the centre.
func pierced_wall(mid: Vector3, length: float, height: float, thick: float, openings: Array, along_z: bool, kind: String, color := Color.WHITE) -> void:
	var rects:Array=[]
	for rect:Rect2 in openings:rects.append(Rect2(rect.position.x-rect.size.x*.5+length*.5,rect.position.y,rect.size.x,rect.size.y))
	var holder:=b.box("Facade",mid+Vector3(0,height*.5,0),Vector3(length,height,thick),color,false)
	var visual:MeshInstance3D=holder.get_child(0)
	var key:="blackout_wall"+str(Vector3(length,height,thick))+str(rects)
	if not b.meshes.has(key):
		b.meshes[key]=MapMeshes.wall(Vector3(length,height,thick),rects,1.1)
		b.meshes[key].lightmap_unwrap(Transform3D.IDENTITY,.35)
	visual.mesh=b.meshes[key];visual.material_override=b.surfaces.get_material(kind,color)
	if along_z:holder.rotation.y=PI*.5
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	body.set_meta("surface",MapBuilder.impact_surface(kind));holder.add_child(body)
	var xs:Array[float]=[0.0,length]
	for rect:Rect2 in rects:xs.append_array([rect.position.x,rect.end.x])
	xs.sort()
	for i in xs.size()-1:
		var x0:=xs[i];var x1:=xs[i+1]
		if x1-x0<.01:continue
		var spans:Array[Vector2]=[]
		for rect:Rect2 in rects:
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
	# Finished edges: steel door frames, concrete sills and window frames.
	var turn:=Basis(Vector3.UP,PI*.5 if along_z else 0.0)
	var rot:=Vector3(0,PI*.5 if along_z else 0.0,0)
	for rect:Rect2 in openings:
		var w:=rect.size.x;var h:=rect.size.y
		var pane:=mid+turn*Vector3(rect.position.x,rect.position.y+h*.5,0)
		if rect.position.y<.01:
			for sx in [-1,1]:b.detail(pane+turn*Vector3(sx*(w*.5+.03),-.015,0),Vector3(.12,h-.03,thick+.1),Color("3a3f42"),"steel",rot)
			b.detail(pane+turn*Vector3(0,h*.5+.03,0),Vector3(w+.18,.12,thick+.1),Color("3a3f42"),"steel",rot)
			continue
		for face in [-1,1]:b.detail(pane+turn*Vector3(0,-h*.5-.03,face*(thick*.5+.05)),Vector3(w+.2,.06,.14),Color("a8a69e"),"concrete",rot)
		for sx in [-1,1]:b.detail(pane+turn*Vector3(sx*(w*.5-.05),0,0),Vector3(.08,h-.18,.1),Color("2e3436"),"steel",rot)
		for sy in [-1,1]:b.detail(pane+turn*Vector3(0,sy*(h*.5-.05),0),Vector3(w-.02,.08,.1),Color("2e3436"),"steel",rot)
		var bars:=maxi(1,roundi(w/.9))
		for k in range(1,bars):b.detail(pane+turn*Vector3(-w*.5+w*k/bars,0,0),Vector3(.05,h-.1,.06),Color("2e3436"),"steel",rot)
		b.detail(pane,Vector3(w-.18,.05,.07),Color("2e3436"),"steel",rot)

# --- Play space -------------------------------------------------------------------

func build(builder: CompactMapBuilder) -> void:
	b=builder
	turbine_hall()
	switchyard()
	intake()
	roads()

# The turbine hall: brick walls on a concrete plinth, roller doors in both gable
# ends, personnel doors north and south, clerestory windows and a flat roof.
func turbine_hall() -> void:
	var hx:=HALL.x*.5;var hz:=HALL.y*.5;var t:=.4
	b.footprints.append(Rect2(-hx,-hz,HALL.x,HALL.y))
	b.buildings.append({"center":Vector3.ZERO,"size":HALL,"height":HALL_H,"furnished":false,"door":3.0,"wall":t})
	var north:=[Rect2(-4,0,2.4,2.9),Rect2(4,0,2.4,2.9),Rect2(-4.6,DECK+1.1,2.6,1.3),Rect2(4.6,DECK+1.1,2.6,1.3)]
	var south:=[Rect2(-9,0,3.4,3.4),Rect2(9,0,3.4,3.4)]
	for x:float in [-16.0,-10.0,10.0,16.0]:north.append(Rect2(x,7.3,2.8,2.6))
	for x:float in [-15.0,-4.0,4.0,15.0]:south.append(Rect2(x,7.3,2.8,2.6))
	var ends:=[Rect2(0,0,7,5.2),Rect2(-7,7.3,2.8,2.6),Rect2(7,7.3,2.8,2.6)]
	pierced_wall(Vector3(0,0,-hz),HALL.x+t,HALL_H,t,north,false,"brick")
	pierced_wall(Vector3(0,0,hz),HALL.x+t,HALL_H,t,south,false,"brick")
	for side:float in [-1.0,1.0]:pierced_wall(Vector3(side*hx,0,0),HALL.y-t,HALL_H,t,ends,true,"brick")
	# Concrete corner pilasters and a string course under the roof.
	for side:float in [-1.0,1.0]:
		for x:float in [-1.0,1.0]:b.box("CornerPost",Vector3(x*(hx+.15),HALL_H*.5,side*(hz+.15)),Vector3(.7,HALL_H,.7),Color("b5b2a9"))
		b.detail(Vector3(0,HALL_H-.3,side*(hz+.24)),Vector3(HALL.x,.5,.1),Color("9b988f"),"concrete")
		b.detail(Vector3(side*(hx+.24),HALL_H-.3,0),Vector3(.1,.5,HALL.y),Color("9b988f"),"concrete")
	b.box("Roof",Vector3(0,HALL_H+.2,0),Vector3(HALL.x+1.2,.4,HALL.y+1.2),Color("4e5558"))
	b.box("InteriorSlab",Vector3(0,.015,0),Vector3(HALL.x-.4,.03,HALL.y-.4),Color("cfccc2"),false)
	# Roof trusses and purlins under the deck.
	for x in range(-18,19,6):
		b.detail(Vector3(x,HALL_H-.55,0),Vector3(.3,.7,HALL.y-.8),STEEL)
		b.detail(Vector3(x,HALL_H-1.2,0),Vector3(.18,.18,HALL.y-.8),STEEL)
		for z in range(-9,10,3):strut(Vector3(x,HALL_H-1.2,z),Vector3(x,HALL_H-.3,z+1.5),.09,STEEL)
	for z:float in [-7.0,0.0,7.0]:b.detail(Vector3(0,HALL_H-.12,z),Vector3(HALL.x-.8,.2,.16),STEEL)
	# Crane rails on corbels along both long walls.
	for side:float in [-1.0,1.0]:
		b.detail(Vector3(0,7.0,side*(hz-.55)),Vector3(HALL.x-.8,.45,.5),STEEL)
		for x in range(-18,19,6):b.detail(Vector3(x,6.55,side*(hz-.45)),Vector3(.5,.5,.5),Color("8e8c84"),"concrete")
	# Roller shutters stopped half way at both gable doors, with their drums and guides.
	for side:float in [-1.0,1.0]:
		var door:=Vector3(side*hx,0,0)
		b.box("ShutterHousing",door+Vector3(side*.45,5.55,0),Vector3(.6,.7,7.6),Color("596164"),false)
		for z:float in [-3.62,3.62]:b.detail(door+Vector3(side*.3,2.6,z),Vector3(.16,5.2,.14),YELLOW)
		for i in 7:b.detail(door+Vector3(side*.05,5.1-i*.12,0),Vector3(.05,.1,7.0),Color("7f8a8d"))
		b.sign_text("TURBINE HALL",door+Vector3(side*(t*.5+.05),9.9,0),side*PI*.5,Color("e2ddcf"),110)
		for i in 8:b.box("Hazard",door+Vector3(side*2.2,.015,-3.15+i*.9),Vector3(1.6,.03,.45),YELLOW if i%2==0 else Color("23272a"),false)
		b.avoid.append_array([door+Vector3(side*1.5,0,0),door+Vector3(side*4,0,0),door-Vector3(side*2.5,0,0)])
	for x:float in [-9.0,9.0]:b.avoid.append_array([Vector3(x,0,hz+1.5),Vector3(x,0,hz+4),Vector3(x,0,hz-1.8)])
	for x:float in [-4.0,4.0]:b.avoid.append_array([Vector3(x,0,-hz-1.5),Vector3(x,0,-hz-4),Vector3(x,0,-hz+1.8)])
	b.sign_text("UNIT 1",Vector3(-9.5,9.9,hz+t*.5+.03),0,Color("e2ddcf"),90)
	b.sign_text("UNIT 2",Vector3(9.5,9.9,hz+t*.5+.03),0,Color("e2ddcf"),90)
	# Sodium floods on both long walls light the roads outside.
	flood_lamp(Vector3(0,9.0,-hz-.5),Vector3(0,0,-22),5.5,26.0)
	flood_lamp(Vector3(0,9.0,hz+.5),Vector3(0,0,21),5.0,24.0)
	# Downpipes and gutters.
	for side:float in [-1.0,1.0]:
		for x:float in [-hx+1.2,-6.5,6.5,hx-1.2]:
			b.cylinder(Vector3(x,HALL_H*.5,side*(hz+.32)),.07,HALL_H,Color("5f6568"))
	for side:float in [-1.0,1.0]:turbine_set(Vector3(side*10,0,2.5),side)
	control_deck()
	hall_floor()
	hall_lighting()

# One turbine-generator unit on its concrete block: the turbine casing outboard,
# the generator inboard, bearing pedestals, steam pipes into the roof.
func turbine_set(center: Vector3, side: float) -> void:
	b.box("Sill",center+Vector3(0,.6,0),Vector3(13,1.2,4.6),Color("b8b5ab"))
	for x:float in [-6.4,6.4]:b.detail(center+Vector3(x,1.21,0),Vector3(.2,.02,4.6),YELLOW,"concrete")
	var top:=1.2
	var casing:=b.cylinder(center+Vector3(side*1.5,top+1.55,0),1.55,8.0,Color("8a9ca2"));casing.rotation.z=PI*.5
	for x:float in [-3.4,-1.2,1.2,3.4]:
		var ring:=b.cylinder(center+Vector3(side*1.5+x,top+1.55,0),1.66,.18,Color("4d5a60"));ring.rotation.z=PI*.5
	b.detail(center+Vector3(side*1.5,top+.25,0),Vector3(8.2,.5,3.4),Color("3f4a4f"))
	var generator:=b.cylinder(center+Vector3(-side*4.6,top+1.3,0),1.3,3.4,Color("4d8496"));generator.rotation.z=PI*.5
	b.detail(center+Vector3(-side*4.6,top+.2,0),Vector3(3.6,.4,2.8),Color("2b3336"))
	for x:float in [-2.7,6.0]:
		b.box("BearingPedestal",center+Vector3(side*x,top+.9,0),Vector3(.9,1.8,1.6),Color("4a565b"))
	b.sign_text("GEN "+("1" if side<0 else "2"),center+Vector3(-side*4.6,top+1.3,1.33),0,Color("e2ddcf"),40)
	for x:float in [-1.5,3.5]:
		b.pipe(center+Vector3(side*(1.5+x),top+3.0,-.4),center+Vector3(side*(1.5+x),HALL_H-.4,-.4),.36,Color("8a8478"))
		b.detail(center+Vector3(side*(1.5+x),top+3.15,-.4),Vector3(1.0,.3,1.0),Color("6a655c"))
	# A ladder and handrail up to the casing top.
	for k in 6:b.detail(center+Vector3(side*6.2,.3+k*.3,2.42),Vector3(.5,.04,.04),YELLOW)
	b.def.cover_points.append_array([center+Vector3(side*1.5,0,3.4),center+Vector3(side*1.5,0,-3.4)])
	b.def.cover_peeks.append_array([center+Vector3(side*7.6,0,3.4),center+Vector3(-side*7.6,0,-3.4)])

# The control deck along the north wall: a steel floor on columns, two ramps
# along the wall, consoles under the north windows and a railing at the front.
func control_deck() -> void:
	var front:=-6.6;var back:=-HALL.y*.5+.2;var mid:=(front+back)*.5;var depth:=front-back
	b.box("Worktop",Vector3(0,DECK-.15,mid),Vector3(14.8,.3,depth),Color("6e7272"))
	b.box("DeckEdge",Vector3(0,DECK-.3,front+.05),Vector3(14.8,.36,.12),YELLOW,false)
	for x:float in [-7.1,-2.4,2.4,7.1]:b.box("SteelColumn",Vector3(x,(DECK-.3)*.5,front+.15),Vector3(.26,DECK-.3,.26),Color("3f4649"))
	for x in range(-6,7,2):b.detail(Vector3(x,DECK-.45,mid),Vector3(.18,.3,depth),Color("3f4649"))
	for side:float in [-1.0,1.0]:
		# Each ramp leaves 3.2 m clear between its foot and the gable wall.
		var run:=RAMP_FOOT-7.4
		b.ramp(Vector3(side*RAMP_FOOT,0,-9.4),Vector3(side*7.4,DECK,-9.4),2.4)
		# Treads and a stepped concrete base under the ramp, so nothing hides beneath it.
		for i in int(run/.52):
			var x:=side*(RAMP_FOOT-.4-i*.52)
			b.detail(Vector3(x,.07+(RAMP_FOOT-absf(x))/run*DECK,-9.4),Vector3(.06,.035,2.1),Color("2f3436"),"steel",Vector3(0,0,side*atan2(DECK,run)))
		var step:=7.6
		while step<RAMP_FOOT-1.0:
			var top:=(RAMP_FOOT-(step+1.45))/run*DECK-.38
			if top>.15:b.box("Sill",Vector3(side*(step+.725),top*.5,-9.45),Vector3(1.45,top,2.3),Color("a9a69c"))
			step+=1.45
	# Railings: the front edge, and the short open ends beside the ramp heads.
	var rail_y:=DECK
	for span in [[Vector3(-7.3,rail_y,front+.05),Vector3(7.3,rail_y,front+.05)]]:
		b.railing_path(span,1.05,YELLOW,1.5,true)
	for side:float in [-1.0,1.0]:b.railing_path([Vector3(side*7.32,rail_y,-8.15),Vector3(side*7.32,rail_y,front+.05)],1.05,YELLOW,1.5,true)
	# Kick plate along the front edge: a little cover for crouched players.
	b.detail(Vector3(0,DECK+.15,front+.1),Vector3(14.6,.3,.04),YELLOW)
	# Control consoles under the windows and a supervisor's desk.
	var deck:=Vector3(0,DECK,mid)
	for x:float in [-4.6,4.6]:
		b.box("ControlDesk",Vector3(x,DECK+.45,back+.55),Vector3(2.6,.9,.8),Color("39434a"))
		b.detail(Vector3(x,DECK+.92,back+.6),Vector3(2.5,.06,.7),Color("23292c"))
		for k in 3:b.detail(Vector3(x-.8+k*.8,DECK+1.15,back+.35),Vector3(.62,.42,.05),Color("101416"))
	b.box("ControlDesk",Vector3(0,DECK+.5,back+.45),Vector3(1.6,1.0,.6),Color("39434a"))
	for k in 5:b.detail(Vector3(-.6+k*.3,DECK+.9,back+.76),Vector3(.12,.12,.02),[Color("6b2a22"),Color("2a4f2e")][k%2])
	b.small_prop("metal_stool_02",deck+Vector3(-4.6,0,-.2),.46)
	b.small_prop("metal_stool_02",deck+Vector3(4.2,0,-.3),.46,.6)
	b.small_prop("office_notepads",Vector3(-.3,DECK+1.0,-10.35),.04,.4)
	b.sign_text("UNIT CONTROL",Vector3(0,DECK+2.6,back+.02),0,Color("d9d4c7"),36)
	# Broken window panes the deck looks out of; railing guards keep players in.
	for x:float in [-4.6,4.6]:
		b.rail_guards.append([Transform3D(Basis.IDENTITY,Vector3(x,DECK+1.75,-HALL.y*.5)),Vector3(2.6,1.3,.42)])

# The hall floor: switchgear under the deck, cover in the aisles.
func hall_floor() -> void:
	var under:=-HALL.y*.5+.65
	for x:float in [-6.6,-1.4,1.4,6.6]:
		var cab:=b.box("ServerCabinet",Vector3(x,1.1,under),Vector3(1.6,2.2,.8),Color("5d6b70"))
		for k in 5:b.detail(Vector3(x,1.25+k*.14,under+.41),Vector3(1.2,.03,.02),Color("1c1f21"))
		b.detail(Vector3(x+.55,1.55,under+.42),Vector3(.16,.16,.02),Color("d1cbb5"))
	b.sign_text("11 kV SWITCHBOARD",Vector3(0,2.65,-HALL.y*.5+.22),0,Color("d9d4c7"),30)
	# Cover in the north aisle and the middle gap between the two units.
	for side:float in [-1.0,1.0]:
		b.cover(Vector3(side*12.5,0,-3.4),2.8,YELLOW)
		b.cargo_cluster(Vector3(side*18.6,0,8.6),-side*PI*.5)
		b.drum(Vector3(side*15.6,0,9.7))
		b.drum(Vector3(side*16.6,0,9.9))
		b.prop("steel_frame_shelves_02",Vector3(side*12.5,0,HALL.y*.5-.7),2.2,PI)
		b.prop("industrial_storage_cart",Vector3(side*5.2,0,8.4),1.0,side*.3)
	b.cargo_cluster(Vector3(0,0,3.0),PI*.5)
	# A switchgear cubicle in the middle of the north aisle: it closes the line of
	# sight between the two gable doors (and on through to both spawns).
	b.box("ServerCabinet",Vector3(0,1.1,-1.5),Vector3(1.6,2.2,3.0),Color("5d6b70"))
	for k in 6:b.detail(Vector3(.81,.8+k*.18,-1.5),Vector3(.02,.03,2.4),Color("1c1f21"))
	b.detail(Vector3(-.81,1.5,-1.5),Vector3(.02,.5,.8),YELLOW)
	b.def.cover_points.append_array([Vector3(-1.9,0,-1.5),Vector3(1.9,0,-1.5)])
	b.def.cover_peeks.append_array([Vector3(-1.9,0,-3.9),Vector3(1.9,0,-3.9)])
	# Painted walkway lines and oil stains.
	for z:float in [-5.9,5.6]:b.detail(Vector3(0,.035,z),Vector3(HALL.x-2,.006,.12),YELLOW,"concrete")
	for x:float in [-3.2,3.2]:b.detail(Vector3(x,.035,2.5),Vector3(.12,.006,4.4),YELLOW,"concrete")
	for p in [Vector3(-7,0,-2),Vector3(8,0,7),Vector3(-15,0,6)]:b.stains.append(p)

# Emergency lighting only: amber bulkheads along the walls and under the deck,
# exit signs over the doors. Daylight comes in through the doors and clerestory.
func hall_lighting() -> void:
	var hz:=HALL.y*.5-.25
	for x:float in [-17.0,-6.0,6.0,17.0]:
		emergency_lamp(Vector3(x,6.2,hz),3.2,14.0)
		emergency_lamp(Vector3(x*.9,6.2,-hz),2.8,13.0)
	for x:float in [-5.0,5.0]:emergency_lamp(Vector3(x,DECK-.5,-8.6),2.0,8.0)
	for x:float in [-5.0,5.0]:emergency_lamp(Vector3(x,DECK+2.6,-HALL.y*.5+.25),1.8,7.0,Color(1.0,.36,.2))
	for side:float in [-1.0,1.0]:
		emergency_lamp(Vector3(side*(HALL.x*.5-.25),5.9,-5.5),2.6,12.0)
		# Generator work-light towers left by the night shift, aimed at the turbines.
		work_light(Vector3(side*5.5,0,-4.8),Vector3(side*13.0,1.5,2.5))
		work_light(Vector3(-side*8.5,0,9.5),Vector3(-side*14.0,1.5,3.0))
		exit_sign(Vector3(side*(HALL.x*.5-.25),5.6,0),PI*.5)
	for x:float in [-9.0,9.0]:exit_sign(Vector3(x,3.75,HALL.y*.5-.25),0)
	for x:float in [-4.0,4.0]:exit_sign(Vector3(x,2.98,-HALL.y*.5+.25),0)
	var volume:=Vector3(HALL.x-.8,HALL_H,HALL.y-.8)
	b.arena.probe_volumes.append(AABB(Vector3(0,HALL_H*.5,0)-volume*.5,volume))

# --- Switchyard ---------------------------------------------------------------------

func switchyard() -> void:
	b.footprints.append(Rect2(-36,-43,72,20))
	# Blast walls between the three main transformer bays.
	for x:float in [-18.0,-6.0,6.0,18.0]:
		b.box("Perimeter",Vector3(x,3.0,-31),Vector3(.45,6.0,10.5),Color("a7a59d"))
		b.box("Coping",Vector3(x,6.04,-31),Vector3(.6,.08,10.6),Color("8f8d86"),false)
		b.def.cover_points.append_array([Vector3(x-.9,0,-25.4),Vector3(x+.9,0,-25.4)])
		b.def.cover_peeks.append_array([Vector3(x-.9,0,-24.0),Vector3(x+.9,0,-24.0)])
	transformer(Vector3(0,0,-31),"SGT 2")
	for side:float in [-1.0,1.0]:
		transformer(Vector3(side*12,0,-31),"SGT 1" if side<0 else "SGT 3")
		for z:float in [-38.6,-23.6]:
			for x:float in [25.0,30.0]:breaker(Vector3(side*x,0,z))
		relay_kiosk(Vector3(side*29,0,-31))
	# Lattice portals carry the busbars over every bay.
	for z:float in [-37.8,-24.2]:
		for x:float in [-34.0,-21.0,-12.0,12.0,21.0,34.0]:lattice_column(Vector3(x,0,z),12.0)
		for span in [[-34.0,-21.0],[-21.0,-12.0],[-12.0,12.0],[12.0,21.0],[21.0,34.0]]:
			lattice_beam(Vector3(span[0],12.0,z),Vector3(span[1],12.0,z))
	for x:float in [-34.0,-21.0,-12.0,12.0,21.0,34.0]:lattice_beam(Vector3(x,12.0,-37.8),Vector3(x,12.0,-24.2))
	# Droppers from the front portal's busbars down to the transformer bushings.
	for x:float in [-12.0,0.0,12.0]:
		for k in 3:strut(Vector3(x-1.2+k*1.2,11.3,-24.2+(k-1)*.6),Vector3(x-1.2+k*1.2,7.2,-30.6),.05,Color("25292b"))
	for z:float in [-37.8,-24.2]:
		for k in 3:b.detail(Vector3(0,11.3-k*.01,z+(k-1)*.6),Vector3(68,.05,.05),Color("25292b"))
	# Cable trench covers in front of the bays, and warning plates on the blast walls.
	for x in range(-17,18,2):
		if absf(absf(x)-12.0)>1.5:b.detail(Vector3(x,.03,-25.0),Vector3(1.94,.06,.9),Color("a29f96"),"concrete")
	for x:float in [-18.0,-6.0,6.0,18.0]:
		for s:float in [-1.0,1.0]:
			b.detail(Vector3(x+s*.24,2.4,-27.0),Vector3(.02,.6,.45),YELLOW)
			b.sign_text("DANGER",Vector3(x+s*.26,2.45,-27.0),s*PI*.5,Color("1d1f20"),14)

# A main transformer: tank on a plinth, radiator banks either side, conservator,
# three HV bushings and the marshalling box.
func transformer(center: Vector3, title: String) -> void:
	b.box("Sill",center+Vector3(0,.1,0),Vector3(8.4,.2,6.0),Color("a29f96"))
	b.box("TransformerTank",center+Vector3(0,2.0,0),Vector3(4.8,3.6,2.9),TRANSFORMER)
	for sz:float in [-1.0,1.0]:
		var face:=center+Vector3(0,0,sz*1.95)
		b.box("Radiator",face+Vector3(0,1.75,0),Vector3(4.4,2.7,.95),TRANSFORMER.darkened(.15))
		for k in 15:b.detail(face+Vector3(-2.1+k*.3,1.75,sz*.5),Vector3(.05,2.6,.12),TRANSFORMER)
		b.detail(face+Vector3(0,3.15,0),Vector3(4.4,.14,.2),Color("3c4542"))
	for k in 4:b.detail(center+Vector3(-1.8+k*1.2,3.85,0),Vector3(.18,.12,2.92),TRANSFORMER.darkened(.25))
	var conservator:=b.cylinder(center+Vector3(1.4,5.0,-.9),.55,3.2,TRANSFORMER);conservator.rotation.z=PI*.5
	for x:float in [.3,2.5]:b.detail(center+Vector3(x,4.3,-.9),Vector3(.12,1.0,.12),Color("3c4542"))
	for k in 3:
		var foot:=center+Vector3(-1.2+k*1.2,3.8,.4)
		b.cylinder(foot+Vector3(0,1.6,0),.14,3.2,Color("8b6b4f"))
		for s in 6:b.cylinder(foot+Vector3(0,.6+s*.45,0),.27,.07,Color("7b5d44"))
		b.detail(foot+Vector3(0,3.3,0),Vector3(.3,.2,.3),GALV)
	b.box("MarshallingBox",center+Vector3(-3.4,1.1,1.6),Vector3(.9,1.8,.6),Color("8d8f86"))
	b.sign_text(title,center+Vector3(0,2.9,1.46),0,Color("e9e3d0"),46)
	b.sign_text(title,center+Vector3(0,2.9,-1.46),PI,Color("e9e3d0"),46)
	for x:float in [-2.8,2.8]:b.detail(center+Vector3(x,.24,0),Vector3(.3,.06,5.0),YELLOW,"concrete")
	b.def.cover_points.append_array([center+Vector3(-3.4,0,3.4),center+Vector3(3.4,0,-3.4),center+Vector3(3.4,0,3.4),center+Vector3(-3.4,0,-3.4)])
	b.def.cover_peeks.append_array([center+Vector3(-4.6,0,3.4),center+Vector3(4.6,0,-3.4),center+Vector3(4.6,0,3.4),center+Vector3(-4.6,0,-3.4)])
	b.stains.append(center+Vector3(2.5,0,3.2))

# An outdoor circuit breaker: a concrete base (waist-high cover), steel frame,
# mechanism box and three porcelain poles.
func breaker(center: Vector3) -> void:
	b.box("Cover",center+Vector3(0,.65,0),Vector3(3.2,1.3,1.3),Color("9d9a91"))
	b.box("BreakerFrame",center+Vector3(0,1.95,0),Vector3(2.8,1.3,.7),GALV)
	for k in 3:
		var foot:=center+Vector3(-1.0+k*1.0,2.6,0)
		b.cylinder(foot+Vector3(0,.8,0),.12,1.6,Color("8b6b4f"))
		for s in 4:b.cylinder(foot+Vector3(0,.3+s*.38,0),.22,.06,Color("7b5d44"))
		strut(foot+Vector3(0,1.6,0),Vector3(foot.x,11.3,center.z+(.6 if center.z<-30 else -.6)),.04,Color("25292b"))
	b.def.cover_points.append_array([center+Vector3(0,0,1.8),center+Vector3(0,0,-1.8)])
	b.def.cover_peeks.append_array([center+Vector3(2.4,0,1.8),center+Vector3(-2.4,0,-1.8)])

# A relay kiosk: a solid corrugated hut with its door, vents and a cable entry.
func relay_kiosk(center: Vector3) -> void:
	b.box("RailServiceCabin",center+Vector3(0,1.6,0),Vector3(4.6,3.2,6.0),Color("7d8a83"))
	b.box("Roof",center+Vector3(0,3.32,0),Vector3(5.0,.24,6.4),Color("4f585b"),false)
	var inward:=-signf(center.x)
	b.detail(center+Vector3(inward*2.32,1.05,0),Vector3(.04,2.1,1.0),Color("4f5a55"))
	b.detail(center+Vector3(inward*2.34,1.0,.35),Vector3(.04,.14,.05),Color("cdc8b8"))
	for z:float in [-2.0,2.0]:
		for k in 5:b.detail(center+Vector3(inward*2.32,2.2+k*.1,z),Vector3(.04,.04,.7),Color("2a2f2d"))
	b.sign_text("RELAY ROOM "+("A" if center.x<0 else "B"),center+Vector3(inward*2.34,2.7,0),inward*PI*.5,Color("e9e3d0"),26)
	b.small_prop("security_light",center+Vector3(inward*2.35,2.6,-1.4),.35,inward*PI*.5)
	for sz:float in [-1.0,1.0]:
		b.def.cover_points.append(center+Vector3(0,0,sz*4.0))
		b.def.cover_peeks.append(center+Vector3(inward*3.3,0,sz*4.0))

# A square lattice column (four chords, ties and diagonals), with its own collider.
func lattice_column(base: Vector3, height: float) -> void:
	var w:=.42
	for sx:float in [-1.0,1.0]:
		for sz:float in [-1.0,1.0]:b.detail(base+Vector3(sx*w,height*.5,sz*w),Vector3(.1,height,.1),GALV)
	var panels:=int(height/1.5)
	for k in panels:
		var y0:=k*1.5;var y1:=y0+1.5
		for sx:float in [-1.0,1.0]:
			strut(base+Vector3(sx*w,y0,-w),base+Vector3(sx*w,y1,w),.05,GALV)
			strut(base+Vector3(-w,y0,sx*w),base+Vector3(w,y1,sx*w),.05,GALV)
		b.detail(base+Vector3(0,y1,0),Vector3(w*2,.05,w*2),GALV)
	b.detail(base+Vector3(0,.25,0),Vector3(1.4,.5,1.4),Color("a29f96"),"concrete")
	b.collider(base+Vector3(0,height*.5,0),Vector3(w*2+.1,height,w*2+.1),"metal")
	if absf(base.x)==12.0 and base.z>-30:
		b.def.cover_points.append(base+Vector3(0,0,1.4))
		b.def.cover_peeks.append(base+Vector3(signf(base.x)*1.6,0,1.4))

# A lattice girder between two column heads (no collision; it is overhead).
func lattice_beam(a: Vector3, c: Vector3) -> void:
	var run:=c-a;var length:=run.length();var along:=run/length
	var across:=Vector3(-along.z,0,along.x)*.35
	for s:float in [-1.0,1.0]:
		for y:float in [-.35,.35]:strut(a+across*s+Vector3(0,y,0),c+across*s+Vector3(0,y,0),.08,GALV)
	var bays:=int(length/1.3)
	for k in bays:
		var p:=a+run*k/bays;var q:=a+run*(k+1)/bays
		for s:float in [-1.0,1.0]:strut(p+across*s+Vector3(0,-.35,0),q+across*s+Vector3(0,.35,0),.045,GALV)

# --- Cooling-water intake -------------------------------------------------------------

func intake() -> void:
	pump_house()
	for side:float in [-1.0,1.0]:
		fuel_tank(Vector3(side*TANK_X,0,TANK_Z),side)
		# Pipe rack from each tank to the pump house, high enough to walk under.
		for x:float in [12.0,16.0,20.0]:
			var leg:=Vector3(side*x,0,22.5)
			for dz:float in [-.8,.8]:b.detail(leg+Vector3(0,2.5,dz),Vector3(.3,5.0,.3),STEEL)
			b.collider(leg+Vector3(0,2.5,0),Vector3(.4,5.0,1.9))
			b.detail(leg+Vector3(0,5.0,0),Vector3(.3,.3,2.2),STEEL)
		for k in 3:
			var pipe:=b.cylinder(Vector3(side*15.5,5.38+k*.02,21.8+k*.7),.2+k*.04,9.6,[Color("7c6a50"),Color("6d777b"),Color("6d777b")][k])
			pipe.rotation.z=PI*.5
		# Fuel oil unloading bay: a tanker parked by the bund with a hose stand.
		b.utility_truck(Vector3(side*15.5,0,35.0),0.0 if side<0 else PI,Color("8f2f24"))
		b.box("ValveManifold",Vector3(side*15.5,.6,28.8),Vector3(2.4,1.2,1.6),Color("586468"))
		for k in 3:b.detail(Vector3(side*(14.7+k*.8),1.45,28.8),Vector3(.24,.5,.24),[RED,YELLOW,RED][k])
		b.def.cover_points.append_array([Vector3(side*15.5,0,27.3),Vector3(side*15.5,0,30.3)])
		b.def.cover_peeks.append_array([Vector3(side*17.3,0,27.3),Vector3(side*13.7,0,30.3)])
	# Seawall promenade: mooring blocks, a screen-cleaning gantry at the intake.
	for side:float in [-1.0,1.0]:
		for x:float in [7.0,22.0,40.0]:b.cover(Vector3(side*x,0,41.0),2.6,YELLOW)
		b.box("Cover",Vector3(side*3.0,.6,41.6),Vector3(1.0,1.2,1.0),Color("a29f96"))
		b.box("ScreenGantryLeg",Vector3(side*3.0,3.0,41.6),Vector3(.5,3.6,.5),YELLOW)
		b.def.cover_points.append(Vector3(side*3.0,0,40.2));b.def.cover_peeks.append(Vector3(side*4.2,0,40.2))
	b.box("ScreenGantry",Vector3(0,5.1,41.6),Vector3(7.0,.6,1.2),YELLOW,false)
	b.box("ScreenGantryWinch",Vector3(1.2,5.8,41.6),Vector3(1.4,.8,1.0),Color("4a5154"),false)
	for x in range(-2,3):b.detail(Vector3(x,.03,42.6),Vector3(.9,.06,2.4),Color("3b3f41"))
	b.sign_text("CW INTAKE 1",Vector3(0,5.1,41.0),PI,Color("23272a"),40)

# The pump house: concrete walls, two vertical pumps, a header along the back.
func pump_house() -> void:
	var c:=PUMP;var size:=PUMP_SIZE;var h:=6.2;var t:=.35
	b.footprints.append(Rect2(c.x-size.x*.5,c.z-size.y*.5,size.x,size.y))
	b.buildings.append({"center":c,"size":size,"height":h,"furnished":false,"door":2.9,"wall":t})
	var north:=[Rect2(-3.2,0,2.4,2.9),Rect2(3.2,0,2.4,2.9),Rect2(-7,3.9,2.0,1.1),Rect2(7,3.9,2.0,1.1)]
	var south:=[Rect2(0,0,3.0,2.9),Rect2(-6,3.9,2.0,1.1),Rect2(6,3.9,2.0,1.1)]
	var ends:=[Rect2(0,0,2.8,2.9)]
	pierced_wall(c+Vector3(0,0,-size.y*.5),size.x+t,h,t,north,false,"precast")
	pierced_wall(c+Vector3(0,0,size.y*.5),size.x+t,h,t,south,false,"precast")
	for side:float in [-1.0,1.0]:pierced_wall(c+Vector3(side*size.x*.5,0,0),size.y-t,h,t,ends,true,"precast")
	b.box("Roof",c+Vector3(0,h+.18,0),Vector3(size.x+.8,.36,size.y+.8),Color("5a6164"))
	b.box("InteriorSlab",c+Vector3(0,.015,0),Vector3(size.x-.3,.03,size.y-.3),Color("cbc8be"),false)
	for side:float in [-1.0,1.0]:
		b.detail(c+Vector3(0,h-.25,side*(size.y*.5+.2)),Vector3(size.x+.4,.5,.06),Color("8f8d86"),"concrete")
	b.sign_text("PUMP HOUSE",c+Vector3(0,5.1,-size.y*.5-t*.5-.03),PI,Color("e2ddcf"),64)
	b.sign_text("CW PUMPS",c+Vector3(0,5.1,size.y*.5+t*.5+.03),0,Color("e2ddcf"),54)
	for side:float in [-1.0,1.0]:
		var pump:=c+Vector3(side*5.2,0,1.6)
		b.box("Sill",pump+Vector3(0,.3,0),Vector3(2.6,.6,2.6),Color("b8b5ab"))
		b.cylinder(pump+Vector3(0,1.35,0),1.0,1.5,Color("2f5e6e"))
		b.cylinder(pump+Vector3(0,2.7,0),.8,1.2,Color("3f4a4f"))
		for k in 8:b.detail(pump+Vector3(0,2.2+k*.14,0),Vector3(1.75,.04,1.75),Color("2f3639"))
		b.pipe(pump+Vector3(0,1.4,1.0),pump+Vector3(0,1.4,3.0),.32,Color("6d777b"))
		b.pipe(pump+Vector3(0,1.4,3.0),pump+Vector3(0,4.4,3.0),.32,Color("6d777b"))
		b.def.cover_points.append_array([pump+Vector3(0,0,-1.9),pump+Vector3(side*-1.9,0,0)])
		b.def.cover_peeks.append_array([pump+Vector3(1.9,0,-1.9),pump+Vector3(side*-1.9,0,-1.6)])
		emergency_lamp(c+Vector3(side*4.5,4.6,-size.y*.5+.3),1.5,9.0)
		exit_sign(c+Vector3(side*3.2,3.15,-size.y*.5+.24),0)
		for reach:float in [1.5,4.0]:
			b.avoid.append_array([c+Vector3(side*(size.x*.5+reach),0,0),c+Vector3(side*3.2,0,-size.y*.5-reach)])
	b.pipe(c+Vector3(-7.6,4.4,4.6),c+Vector3(7.6,4.4,4.6),.42,Color("6d777b"))
	for reach:float in [1.5,4.0]:b.avoid.append(c+Vector3(0,0,size.y*.5+reach))
	emergency_lamp(c+Vector3(0,4.6,size.y*.5-.3),1.4,8.0)
	exit_sign(c+Vector3(0,3.15,size.y*.5-.24),PI)
	b.prop("old_military_compressor",c+Vector3(-1.6,0,-2.7),1.1,.1)
	b.prop("steel_frame_shelves_02",c+Vector3(7.8,0,-3.9),2.0,-PI*.5)
	b.cabinet(c+Vector3(-7.9,0,-3.2),PI*.5,Color("5d6b70"))
	var volume:=Vector3(size.x-.6,h,size.y-.6)
	b.arena.probe_volumes.append(AABB(c+Vector3(0,h*.5,0)-volume*.5,volume))

# A fuel oil tank in a low bund (gaps toward the pump house and the road).
func fuel_tank(center: Vector3, side: float) -> void:
	var r:=5.5;var h:=8.5
	b.footprints.append(Rect2(center.x-8.6,center.z-8.6,17.2,17.2))
	b.cylinder(center+Vector3(0,h*.5,0),r,h,TANK_PAINT)
	b.cylinder(center+Vector3(0,.12,0),r+.4,.24,Color("8f8c83"))
	for y:float in [2.0,4.2,6.4]:b.cylinder(center+Vector3(0,y,0),r+.03,.1,TANK_PAINT.darkened(.2))
	var roof:=MeshInstance3D.new();roof.mesh=MapMeshes.cylinder(r-.2,.5,40);roof.position=center+Vector3(0,h+.25,0)
	roof.material_override=b.surfaces.get_material("painted_metal",TANK_PAINT.darkened(.1));roof.gi_mode=GeometryInstance3D.GI_MODE_STATIC
	b.region.add_child(roof)
	# Caged access ladder up the seaward side and the roof rail (decorative, out of reach).
	var foot:=center+Vector3(0,0,r+.32)
	for sx:float in [-.25,.25]:b.detail(foot+Vector3(sx,h*.5+.5,0),Vector3(.06,h+1.0,.06),STEEL)
	for k in int(h/.3):b.detail(foot+Vector3(0,.3+k*.3,0),Vector3(.5,.04,.04),STEEL)
	for k in int((h-2.2)/.9):b.detail(foot+Vector3(0,2.6+k*.9,.36),Vector3(.8,.05,.05),STEEL)
	for sx:float in [-.4,0.0,.4]:b.detail(foot+Vector3(sx,(h+2.6)*.5,.36+(.0 if sx==0.0 else -.12)),Vector3(.04,h-2.0,.04),STEEL)
	for k in 24:
		var a:=TAU*k/24
		b.detail(center+Vector3(cos(a)*(r-.25),h+1.0,sin(a)*(r-.25)),Vector3(.05,1.0,.05),YELLOW)
	b.sign_text("T"+("1" if side<0 else "2"),center+Vector3(0,5.6,-r-.06),PI,Color("2a2e30"),150)
	b.sign_text("T"+("1" if side<0 else "2"),center+Vector3(-side*(r+.06),5.6,0),-side*PI*.5,Color("2a2e30"),150)
	b.sign_text("FUEL OIL",center+Vector3(-side*(r+.06),4.2,0),-side*PI*.5,Color("2a2e30"),40)
	# Bund wall: 0.9 m, open on the north and inner sides.
	var e:=8.4
	for edge in [[Vector3(-e,0,-e),Vector3(-2,0,-e)],[Vector3(2,0,-e),Vector3(e,0,-e)],[Vector3(-e,0,e),Vector3(e,0,e)]]:
		bund(center+edge[0],center+edge[1])
	var outer:=Vector3(side*e,0,0);var inner:=Vector3(-side*e,0,0)
	bund(center+outer+Vector3(0,0,-e),center+outer+Vector3(0,0,e))
	bund(center+inner+Vector3(0,0,-e),center+inner+Vector3(0,0,-2))
	bund(center+inner+Vector3(0,0,2),center+inner+Vector3(0,0,e))
	b.def.cover_points.append_array([center+Vector3(0,0,-e-1.0),center+Vector3(-side*(e+1.0),0,5.0),center+Vector3(0,0,e+1.0)])
	b.def.cover_peeks.append_array([center+Vector3(3,0,-e-1.0),center+Vector3(-side*(e+1.0),0,1.5),center+Vector3(4,0,e+1.0)])
	# Inside the bund, the ring between tank and wall.
	for a:float in [PI,PI*1.5,0.0]:
		b.def.cover_points.append(center+Vector3(cos(a),0,sin(a))*(r+1.4))
		b.def.cover_peeks.append(center+Vector3(cos(a+.45),0,sin(a+.45))*(r+1.4))

func bund(a: Vector3, c: Vector3) -> void:
	var run:=c-a
	b.box("Cover",(a+c)*.5+Vector3(0,.45,0),Vector3(absf(run.x)+.3,.9,absf(run.z)+.3),Color("a29f96"))

# --- Roads and markings ----------------------------------------------------------------

# A generator or switchgear container on the ground, as cover with its markers.
func container_block(center: Vector3, along_z: bool, title: String, color: Color) -> void:
	var size:=Vector3(2.44,2.6,6.0) if along_z else Vector3(6.0,2.6,2.44)
	b.box("Freight",center+Vector3(0,1.3,0),size,color)
	var across:=Vector3(1,0,0) if along_z else Vector3(0,0,1)
	var along:=Vector3(0,0,1) if along_z else Vector3(1,0,0)
	for s:float in [-1.0,1.0]:
		b.sign_text(title,center+Vector3(0,1.9,0)+across*s*1.24,(PI*.5 if s>0 else -PI*.5) if along_z else (0.0 if s>0 else PI),Color("e9e3d0"),36)
		for k in 5:b.detail(center+Vector3(0,.9,0)+across*s*1.23+along*(-1.6+k*.8),Vector3(.3,.6,.04) if not along_z else Vector3(.04,.6,.3),Color("1d2124"))
		b.def.cover_points.append(center+across*s*2.2);b.def.cover_peeks.append(center+across*s*2.2+along*3.8)

func roads() -> void:
	# Blockers on the long lines: the gable doors and both roads would otherwise
	# give each spawn a 70-100 m view of the other.
	for side:float in [-1.0,1.0]:
		container_block(Vector3(side*30,0,0),true,"MOBILE GEN "+("A" if side<0 else "B"),Color("3c6a4c"))
		b.cover(Vector3(side*12,0,-13.9),2.8,YELLOW)
		b.cover(Vector3(side*6,0,-22.0),2.6,YELLOW)
		b.cover(Vector3(side*13,0,14.2),2.8,YELLOW)
		b.cover(Vector3(side*18,0,19.5),2.6,YELLOW)
	b.utility_truck(Vector3(0,0,-16.5),0.0,Color("d2c9a8"))
	container_block(Vector3(0,0,17.5),false,"11 kV SWITCHGEAR",Color("8d8f86"))
	# Road edge lines around the hall and dashed centre lines.
	for z:float in [-15.0,15.5]:
		for x in range(-44,45,4):b.detail(Vector3(x,.018,z),Vector3(2.0,.012,.12),Color("d8d2bd"),"concrete")
	for side:float in [-1.0,1.0]:
		for z in range(-12,13,4):b.detail(Vector3(side*30,.018,z),Vector3(.12,.012,2.0),Color("d8d2bd"),"concrete")
		b.sign_text("SLOW",Vector3(side*30.6,.03,-15.0),0,Color("d8d2bd"),120)
	for p in [Vector3(-30,.03,-15.0),Vector3(30,.03,-15.0)]:b.painted.append(Rect2(p.x-2,p.z-1,4,2))
	# Floodlight masts on the generator circuit: pools of sodium light at the junctions.
	for side:float in [-1.0,1.0]:
		flood_mast(Vector3(side*27.0,0,-19.5),11.0,Vector3(side*14.0,0,-26.0),6.0,30.0)
		flood_mast(Vector3(side*23.5,0,13.6),10.0,Vector3(side*12.0,0,22.0),5.0,26.0)
		flood_mast(Vector3(side*44.0,0,38.0),10.0,Vector3(side*34.0,0,40.0),4.5,24.0)
		flood_mast(Vector3(side*36.5,0,-12.6),9.0,Vector3(side*30.0,0,-4.0),4.5,22.0)
	flood_lamp(Vector3(0,5.6,PUMP.z+PUMP_SIZE.y*.5+.5),Vector3(0,0,41),3.5,18.0)

# --- Spawns: gatehouse (west) and stores (east) -------------------------------------------

func deployment(builder: CompactMapBuilder) -> void:
	b=builder
	for team in 2:
		var side:=-1.0 if team==0 else 1.0
		for row in 4:
			for col in 4:
				var p:=Vector3(side*(b.def.extent.x*.5-6-col*2),.05,[-26,-5,5,26][row])
				(b.def.spawns_blue if team==0 else b.def.spawns_red).append(p)
		b.modern_building(Vector3(side*(b.def.extent.x*.5-11),0,0),Vector2(12,20),3.6,"GATEHOUSE  /  SECURITY" if team==0 else "STORES  /  WORKSHOP")
		for z:float in [-8.0,8.0]:b.cover(Vector3(side*34.5,0,z),2.8,YELLOW)
		# Standby generator: the reason the floodlights still burn.
		var gen:=Vector3(side*44.0,0,-37.0)
		b.box("Freight",gen+Vector3(0,1.3,0),Vector3(6.0,2.6,2.44),Color("3c6a4c"))
		b.sign_text("STANDBY GEN",gen+Vector3(0,1.9,1.24),0,Color("e9e3d0"),40)
		for k in 6:b.detail(gen+Vector3(-2.4+k*.5,2.0,-1.24),Vector3(.3,.6,.04),Color("1d2124"))
		b.pipe(gen+Vector3(2.2,2.6,0),gen+Vector3(2.2,4.2,0),.12,Color("4a4f50"))
		b.def.cover_points.append_array([gen+Vector3(0,0,2.2),gen+Vector3(-side*3.8,0,0)])
		b.def.cover_peeks.append_array([gen+Vector3(3.6,0,2.2),gen+Vector3(-side*3.8,0,1.8)])

# --- Objectives ---------------------------------------------------------------------------

func objectives(builder: CompactMapBuilder) -> void:
	b=builder
	for side:float in [-1.0,1.0]:
		for p in [Vector3(side*23.0,0,-28.0),Vector3(side*10.0,0,-5.6),Vector3(side*11.5,0,39.0),Vector3(side*2.8,DECK,-7.3)]:
			b.def.ammo_caches.append(p)
			b.box("AmmoCase",p+Vector3(0,.35,0),Vector3(1.1,.7,.65),Color("59644d"))
			b.sign_text("SUPPLIES",p+Vector3(0,.42,.333),0,Color("c9d9c5"),15)
	for x:float in [-36.0,-24.0,-9.0,0.0,9.0,24.0,36.0]:
		for z:float in [-20.0,-13.0,16.5,38.5]:b.def.routes.append(Vector3(x,.05,14.0 if x==0.0 and z==16.5 else z))
	for x:float in [-36.0,36.0]:b.def.routes.append(Vector3(x,.05,-30.0))
	for x:float in [-41.0,41.0]:b.def.routes.append(Vector3(x,.05,30.0))
	b.def.routes.append_array([Vector3(-8,.05,-3),Vector3(8,.05,-3),Vector3(0,.05,8),Vector3(-12,.05,8),Vector3(12,.05,8),Vector3(0,DECK,-8.5),Vector3(0,.05,-34.5),Vector3(-12,.05,-35),Vector3(12,.05,-35),Vector3(0,.05,28.0),Vector3(-4.5,.05,27.5),Vector3(4.5,.05,27.5),Vector3(-30,.05,18.5),Vector3(30,.05,18.5)])
	b.def.domination.assign([Vector3(0,0,-21.0),Vector3(0,0,-4.8),Vector3(0,0,39.0)])
	b.def.hardpoints.assign([Vector3(0,0,-21.0),Vector3(0,0,-4.8),Vector3(0,0,39.0),Vector3(-24,0,-31.0),Vector3(24,0,18.0)])
	b.def.qa_route.assign([Vector3(-43,0,-5),Vector3(-30,0,-14),Vector3(-20.2,0,-6.0),Vector3(-6,DECK,-8.4),Vector3(0,DECK,-8.0),Vector3(6,DECK,-8.4),Vector3(20.2,0,-6.0),Vector3(24,0,16.5),Vector3(0,0,39.0),Vector3(-24,0,38.5),Vector3(-43,0,5)])

# --- Dressing -----------------------------------------------------------------------------

func dress(builder: CompactMapBuilder) -> void:
	b=builder
	b.interior_streaks(b.buildings[0],3)
	for side:float in [-1.0,1.0]:
		b.pipe_stack(Vector3(side*40.0,0,-21.5),0.0,5.0)
		b.cable_reel(Vector3(side*38.5,0,-28.0),.3*side)
		b.cable_reel(Vector3(side*37.2,0,-29.2),-.5*side)
		b.pallet(Vector3(side*26.5,0,14.6),.1*side,2)
		b.small_prop("security_camera_02",Vector3(side*21.4,8.6,-11.4),.3,side)
		for k in 3:b.small_prop("Barrel_02" if k%2==0 else "barrel_03",Vector3(side*(48.0+k*.75),0,42.6+(k%2)*.4),.9,b.rng.randf()*TAU,true)
	b.floor_decals("Leaking006",5,Rect2(-19,-9,38,18),Vector2(2.4,2),Color(.1,.085,.06,.7),true)
	# Rough grass along the fence lines and the verge behind the seawall.
	b.nature.scan_clearance(b.arena)
	for guard in b.rail_guards:
		var shape:=BoxShape3D.new();shape.size=guard[1]
		b.nature.clearance.add(guard[0],shape)
	var suit:=func(x:float,z:float)->float:
		if b.footprint_distance(x,z)<1.5:return 0.0
		var edge:=minf(b.def.extent.x*.5-absf(x),z+b.def.extent.y*.5)
		var verge:=1.0-smoothstep(2.5,4.5,edge)
		var shore:=smoothstep(42.6,43.4,z)*(1.0-smoothstep(44.1,44.4,z))
		var weight:=maxf(verge,shore*.8)
		if weight<=0.0:return 0.0
		return weight*smoothstep(1.2,1.8,b.nature.clearance.gap(x,z,[.02,.2,.45],2))
	b.nature.grass_field(Rect2(-54.5,-44.5,109,89),suit,func(_x:float,_z:float)->float:return 0.0,1.2,36,.7,Vector2(.45,.85))

func rect_distance(x: float, z: float, rect: Rect2) -> float:
	var dx:=maxf(maxf(rect.position.x-x,x-rect.end.x),0.0);var dz:=maxf(maxf(rect.position.y-z,z-rect.end.y),0.0)
	return Vector2(dx,dz).length()

# R gravel (switchyard and bunds), G grass (fence verges), B concrete (aprons, promenade).
func ground_splat(_builder: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n:=noise.get_noise_2d(x,z)
	var fine:=noise.get_noise_2d(x*3.1+90.0,z*3.1-17.0)
	var gravel:=1.0-smoothstep(0.0,1.6,rect_distance(x,z,Rect2(-36,-44,72,19.5))+n*1.5)
	for side:float in [-1.0,1.0]:gravel=maxf(gravel,1.0-smoothstep(0.0,.6,rect_distance(x,z,Rect2(side*TANK_X-8.4,TANK_Z-8.4,16.8,16.8))))
	var edge:=minf(55.0-absf(x),z+45.0)
	var grass:=(1.0-smoothstep(2.0,4.0,edge+n*2.5))*(1.0-gravel)
	var apron:=maxf(1.0-smoothstep(.5,3.5,rect_distance(x,z,Rect2(-21,-11,42,22))+n*1.2),1.0-smoothstep(.5,3.0,rect_distance(x,z,Rect2(-9,24,18,10))+n))
	apron=maxf(apron,smoothstep(37.0,38.5,z+n*.8))
	apron=maxf(apron*(1.0-gravel),smoothstep(.55,.8,fine)*.35)
	return Color(gravel,grass,apron)
