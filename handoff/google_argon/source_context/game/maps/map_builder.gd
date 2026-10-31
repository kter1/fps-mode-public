class_name MapBuilder
extends RefCounted

var arena: MapArena
var region: NavigationRegion3D
var def: MapDefinition
var materials: Dictionary = {}
var meshes: Dictionary = {}
var rng := RandomNumberGenerator.new()
var stone := Color("6f7b82")
var dark := Color("28343f")
var metal := Color("4d6571")
var accent := Color("e9ac46")
var serial := 0
var detail_groups: Dictionary = {}
var surfaces := MapSurfaces.new()
var footprints: Array[Rect2] = []
var stains: Array[Vector3] = []
var queued_panes := 0
# Fade-out distance for projected decals; dress passes lower it to keep far clutter cheap.
var decal_fade := 55.0
# Ground areas (x, z rectangles) that already carry paint or lettering. Stains, puddles and
# asphalt patches stay off them so nothing is printed over anything else.
var painted: Array[Rect2] = []
var props: MapProps
var buildings: Array[Dictionary] = []
var avoid: Array[Vector3] = []
var nature: MapNature
var ground_node: MeshInstance3D
var ground_size: Vector3
# The map's registry entry: style knobs and lighting (see MapCatalog).
var style: Dictionary = {}
var lighting_settings: Dictionary = {}

# Photoscanned surface, edge bevel (m) and how far grime climbs from the base
# (m) for each architectural part. Unlisted parts are painted steel in the
# colour the layout asks for. TOPS gives walkable tops their own surface.
const PARTS := {
	"HallWall":["wall",.035,1.1],"DoorLintel":["wall",.035,0.0],
	"SecurityWall":["precast",.04,1.0],"Perimeter":["precast",.04,1.2],"ApproachBaffle":["precast",.04,1.0],
	"SecurityCoping":["concrete",.02,0.0],"Cover":["concrete",.05,.5],"AccessRamp":["concrete",.03,0.0],
	"CourtyardPlanter":["concrete",.05,.45],"NorthTerrace":["rough_concrete",.06,1.2],
	"InteriorSlab":["concrete_floor",0.0,0.0],"RoomPartition":["plaster",.02,.25],
	"Roof":["corrugated",.02,0.0],"MaintenanceAwning":["corrugated",.02,0.0],"RailServiceCabin":["corrugated",.03,.5],
	"Ventilation":["corrugated",.03,0.0],"Freight":["container",.03,.4],
	"PalletLoad":["wood",.02,.2],"PalletBoard":["wood",.01,0.0],
	"Rail":["rust",.01,0.0],"RailCoupler":["rust",.02,0.0],"CoverCap":["painted_metal",.015,0.0],
	"Gantry":["painted_metal",.02,0.0],"Worktop":["steel_plate",.01,0.0],
	"Parapet":["wall",.02,0.0],"Coping":["concrete",.015,0.0],"Fascia":["painted_metal",.008,0.0],
	"RoadDash":["paint_concrete",.004,0.0],"Hazard":["paint_concrete",.004,0.0],"PaintBand":["paint_concrete",.004,0.0],
}
const TOPS := {"NorthTerrace":"gravel","CourtyardPlanter":"dirt"}

# Impact class for a surface kind, read by MatchEffects.surface_of() from the
# collider's "surface" metadata.
static func impact_surface(kind: String) -> String:
	if kind in ["painted_metal","corrugated","container","container_red","rust","steel_plate","shutter"]:return "metal"
	if kind=="wood":return "wood"
	if kind in ["grass","dirt","gravel","rock","snow"]:return "earth"
	return "concrete"

# Containers keep their scanned paint where it matches; other colours are
# repainted corrugated steel.
static func container_surface(color: Color) -> String:
	if color.r>color.b*1.5:return "container_red"
	if color.g>color.b and color.g>color.r:return "container"
	return "corrugated"

# Surface, bevel and grime height for a part label; layouts with their own
# parts extend this.
func part_info(label: String) -> Array:
	return PARTS.get(label,["painted_metal",.02,.3])

func part_mesh(label: String, size: Vector3) -> ArrayMesh:
	var part:Array=part_info(label)
	var key:=label+str(size)
	if label in ["Freight","Rib","ContainerRail"] or part==["painted_metal",.02,.3]:key="generic"+str(size)
	if meshes.has(key):return meshes[key]
	var mesh:=MapMeshes.block(size,part[1],part[2],TOPS.has(label))
	mesh.lightmap_unwrap(Transform3D.IDENTITY,.35)
	meshes[key]=mesh
	return mesh

func box(label: String, center: Vector3, size: Vector3, color: Color, solid := true, parent: Node3D = null) -> Node3D:
	var target: Node3D = region if parent == null else parent
	var item := Node3D.new()
	item.name = label + str(serial)
	serial += 1
	target.add_child(item)
	item.position = center
	var visual := MeshInstance3D.new()
	var part:Array=part_info(label)
	var kind:String=part[0]
	if kind=="wall":kind=wall_kind()
	if label=="Freight":kind=container_surface(color)
	if label!="Ground":
		visual.mesh = part_mesh(label,size)
		visual.material_override = surfaces.get_material(kind,color)
		if TOPS.has(label):
			visual.material_override=null
			visual.set_surface_override_material(0,surfaces.get_material(kind,color))
			visual.set_surface_override_material(1,surfaces.get_material(TOPS[label]))
	if label=="WindowGlass":
		var glass:=StandardMaterial3D.new();glass.albedo_color=Color("365261");glass.metallic=.65;glass.roughness=.18
		visual.material_override=glass
	elif label=="CeilingLamp":
		if not materials.has("lamp"):
			var tube:=StandardMaterial3D.new();tube.albedo_color=Color("f4f1e6");tube.roughness=.4
			tube.emission_enabled=true;tube.emission=Color(1.0,.96,.88);tube.emission_energy_multiplier=5.0
			materials["lamp"]=tube
		visual.material_override=materials["lamp"]
	visual.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	item.add_child(visual)
	if label=="Ground":ground_node=visual;ground_size=size
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var impact:=impact_surface(kind)
		if label=="Ground":impact=str(style.get("ground_impact","concrete"))
		elif label=="WindowGlass":impact="concrete"
		body.set_meta("surface",impact)
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		item.add_child(body)
		if size.y>=3 and minf(size.x,size.z)>.4:
			var occluder:=OccluderInstance3D.new();var volume:=BoxOccluder3D.new();volume.size=size*.98;occluder.occluder=volume;item.add_child(occluder)
	return item

# Distance from a ground point to the nearest building footprint (0 inside).
func footprint_distance(x: float, z: float) -> float:
	var best:=INF
	for rect in footprints:
		var dx:=maxf(maxf(rect.position.x-x,x-rect.end.x),0.0);var dz:=maxf(maxf(rect.position.y-z,z-rect.end.y),0.0)
		best=minf(best,Vector2(dx,dz).length())
	return best

# Exterior wall finish for "wall" parts (brick or rough concrete).
func wall_kind() -> String:
	return str(style.get("wall_kind","rough_concrete"))

# Splat weights for the ground shader overlays (R, G, B); the map's layout
# provides them (MapLayout.ground_splat).
func ground_splat(x: float, z: float, noise: FastNoiseLite) -> Color:
	return Color(0,0,0)

# The ground keeps its box collision; its visual is a 2 m grid carrying the
# splat in vertex colours, metric UVs and a planar lightmap UV2.
func finish_ground() -> void:
	var size:=ground_size;var cell:=2.0
	var nx:=int(round(size.x/cell));var nz:=int(round(size.z/cell))
	var noise:=FastNoiseLite.new();noise.seed=rng.seed;noise.frequency=.035;noise.fractal_octaves=3
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in nz+1:
		for col in nx+1:
			var x:=-size.x*.5+col*size.x/nx;var z:=-size.z*.5+row*size.z/nz
			st.set_color(ground_splat(x,z,noise));st.set_normal(Vector3.UP)
			st.set_uv(Vector2(x,z));st.set_uv2(Vector2(col/float(nx),row/float(nz)))
			st.add_vertex(Vector3(x,size.y*.5,z))
	for row in nz:
		for col in nx:
			var a:=row*(nx+1)+col;var b:=a+1;var c:=a+nx+1;var d:=c+1
			for index in [a,b,c,b,d,c]:st.add_index(index)
	st.generate_tangents()
	var mesh:=st.commit()
	mesh.lightmap_size_hint=Vector2i(int(size.x/.3),int(size.z/.3))
	ground_node.mesh=mesh
	var ground:Dictionary=style.get("ground",{});var layers:Array=ground.get("layers",["asphalt","concrete_floor","gravel","dirt"])
	ground_node.material_override=surfaces.ground_material(layers[0],layers[1],layers[2],layers[3],MapCatalog.color(ground.get("tint")))

# ambientCG decals ship colour and opacity as separate images; Godot decals
# take alpha from the albedo, so the pair is packed once into a compressed
# resource beside the source (normal maps are stored the same way).
func decal_texture(id: String, channel: String) -> Texture2D:
	var path:="res://content/decals/%s/%s_%s.res"%[id,id,channel]
	if not ResourceLoader.exists(path):
		var source:="res://content/decals/%s/%s_1K-JPG_"%[id,id]
		var image:=Image.load_from_file(source+("Color.jpg" if channel=="albedo" else "NormalGL.jpg"))
		image.convert(Image.FORMAT_RGBA8)
		if channel=="albedo":
			if FileAccess.file_exists(source+"Opacity.jpg"):
				var opacity:=Image.load_from_file(source+"Opacity.jpg")
				for y in image.get_height():
					for x in image.get_width():
						var color:=image.get_pixel(x,y);color.a=opacity.get_pixel(x,y).r;image.set_pixel(x,y,color)
			else:
				# No opacity map (tyre tracks): fade out toward every edge.
				for y in image.get_height():
					for x in image.get_width():
						var color:=image.get_pixel(x,y)
						var u:=float(x)/image.get_width();var v:=float(y)/image.get_height()
						color.a=smoothstep(0.0,.2,v)*smoothstep(1.0,.8,v)*smoothstep(0.0,.1,u)*smoothstep(1.0,.9,u)
						image.set_pixel(x,y,color)
		image.generate_mipmaps()
		var texture:=PortableCompressedTexture2D.new();texture.keep_compressed_buffer=true
		texture.create_from_image(image,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY,channel=="normal",.85)
		ResourceSaver.save(texture,path)
	return load(path)

# Projects a decal along -normal onto the surface at position. Wall decals
# keep the texture's top up; ground decals spin by angle.
func decal(id: String, position: Vector3, size: Vector2, normal := Vector3.UP, angle := 0.0, tint := Color.WHITE) -> void:
	var node:=Decal.new()
	node.name=id+str(serial);serial+=1
	node.texture_albedo=decal_texture(id,"albedo")
	node.texture_normal=decal_texture(id,"normal")
	node.size=Vector3(size.x,.8,size.y)
	node.modulate=tint
	node.normal_fade=.35
	node.distance_fade_enabled=true;node.distance_fade_begin=decal_fade;node.distance_fade_length=decal_fade*20.0/55.0
	if normal.is_equal_approx(Vector3.UP):
		node.basis=Basis(Vector3.UP,angle)
	else:
		var x:=normal.cross(Vector3.DOWN).normalized()
		node.basis=Basis(x,normal,x.cross(normal))
	node.position=position
	arena.add_child(node)

# True when a footprint (half extents on the ground at a point) touches recorded paint.
func on_paint(point: Vector3, half: Vector2) -> bool:
	var area:=Rect2(point.x-half.x,point.z-half.y,half.x*2.0,half.y*2.0)
	return painted.any(func(rect:Rect2):return rect.intersects(area))

# Weathering and markings: leak streaks under roof edges, rising damp at wall
# feet, patched asphalt, runoff stains by vehicles, painted lane arrows.
func weathering() -> void:
	for building_data in buildings:
		var center3:Vector3=building_data.center
		if center3.y>.5:continue
		var center:=Vector2(center3.x,center3.z);var half:Vector2=building_data.size*.5
		var face_offset:=float(building_data.get("wall",.65))*.5+.01;var height:float=building_data.height
		for i in 4:
			var along:=rng.randf_range(-.38,.38);var side:=1.0 if i%2==0 else -1.0
			var on_x:=i<2
			var outward:=Vector3(0,0,side) if on_x else Vector3(side,0,0)
			var face:=Vector3(center.x+along*half.x*2,0,center.y+side*(half.y+face_offset)) if on_x else Vector3(center.x+side*(half.x+face_offset),0,center.y+along*half.y*2)
			decal("Leaking004",face+Vector3(0,height-rng.randf_range(1.0,1.6),0),Vector2(rng.randf_range(1.6,2.6),2.6),outward,0,Color(1,1,1,.85))
			decal("Leaking008",face+Vector3(0,.7,0)+outward.cross(Vector3.UP)*rng.randf_range(-2,2),Vector2(rng.randf_range(2.2,3.4),1.4),outward,0,Color(1,1,1,.75))
	var placed:=0;var attempts:=0
	while placed<int(style.get("asphalt_patches",0)) and attempts<400:
		attempts+=1
		var point:=Vector3(rng.randf_range(-def.extent.x*.42,def.extent.x*.42),0,rng.randf_range(-def.extent.y*.42,def.extent.y*.42))
		if footprint_distance(point.x,point.z)<4.0:continue
		var patch:=rng.randf_range(2.2,4.0)
		if on_paint(point,Vector2.ONE*patch*.6):continue
		decal("AsphaltDamage001",point,Vector2.ONE*patch,Vector3.UP,rng.randf()*TAU,Color(.92,.92,.92,.9))
		placed+=1
	for stain in stains:
		decal("Leaking004",stain+Vector3(rng.randf_range(-.8,.8),0,rng.randf_range(-.8,.8)),Vector2(rng.randf_range(1.6,2.8),rng.randf_range(1.6,2.8)),Vector3.UP,rng.randf()*TAU,Color(.32,.28,.24,.7))
	for point in style.get("lane_arrows",[]):
		var lane:=MapCatalog.vec3(point)
		decal("RoadLines030C",lane,Vector2(1.2,4.5),Vector3.UP,-PI*.5*signf(lane.x),Color(.95,.9,.8,.9))

# A steel drum: the original cylinder collider with a scanned barrel inside it.
func drum(base: Vector3) -> void:
	var item:=Node3D.new();item.name="Drum"+str(serial);serial+=1
	region.add_child(item);item.position=base+Vector3(0,.62,0)
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
	var collider:=CollisionShape3D.new();var shape:=CylinderShape3D.new();shape.radius=.48;shape.height=1.24
	collider.shape=shape;body.add_child(collider);item.add_child(body)
	var id:String=["Barrel_01","Barrel_02","barrel_03"][serial%3]
	props.place(id,props.grounded(id,base,rng.randf()*TAU,1.24/props.bounds(id).size.y),false,140.0)

# World-space bounds of every collider except the ground slab and perimeter.
func collider_bounds() -> Array[AABB]:
	var result:Array[AABB]=[]
	for node in region.find_children("*","CollisionShape3D",true,false):
		var item:String=String(node.get_parent().get_parent().name)
		if item.begins_with("Ground") or item.begins_with("Perimeter"):continue
		var shape:=(node as CollisionShape3D).shape
		var local:AABB
		if shape is BoxShape3D:local=AABB(-shape.size*.5,shape.size)
		elif shape is CylinderShape3D:local=AABB(Vector3(-shape.radius,-shape.height*.5,-shape.radius),Vector3(shape.radius*2,shape.height,shape.radius*2))
		else:continue
		result.append(MapProps.local_transform(node,arena)*local)
	return result

func markers() -> Array[Vector3]:
	var points:Array[Vector3]=[]
	for field in ["spawns_blue","spawns_red","routes","cover_points","cover_peeks","ammo_caches","domination","hardpoints","qa_route"]:points.append_array(def.get(field))
	return points

# True when a footprint (half extents on the ground at center) clears every
# collider by clearance and every gameplay marker and doorway by gap.
func spot_free(center: Vector3, half: Vector2, clearance: float, gap: float, solids: Array[AABB], points: Array[Vector3]) -> bool:
	if absf(center.x)>def.extent.x*.5-4 or absf(center.z)>def.extent.y*.5-4:return false
	if footprint_distance(center.x,center.z)<.01:return false
	var area:=AABB(Vector3(center.x-half.x-clearance,center.y+.08,center.z-half.y-clearance),Vector3((half.x+clearance)*2,2.4,(half.y+clearance)*2))
	for solid in solids:
		if solid.intersects(area):return false
	for point in points:
		if absf(point.y-center.y)<3 and Vector2(point.x-center.x,point.z-center.z).length()<gap+maxf(half.x,half.y):return false
	return true

# Prop dressing from the Poly Haven set. Wall clutter has no collision and
# stays within half a metre of walls (inside the navigation agent radius);
# cars and barrier rows are cover: box colliders plus registered cover points.
func dressing() -> void:
	# Some layouts author their own vehicles and furnishings rather than using
	# the shared industrial-yard dressing.
	if style.get("authored_dressing",false):
		props.flush(arena,85.0)
		return
	var solids:=collider_bounds()
	var points:=markers()
	var doors:=points.duplicate();doors.append_array(avoid)
	for building_data in buildings:
		var center:Vector3=building_data.center;var size:Vector2=building_data.size;var height:float=building_data.height
		for side in [-1.0,1.0]:
			for along_x in [true,false]:
				var length:=size.x if along_x else size.y
				var outward:=Vector3(0,0,side) if along_x else Vector3(side,0,0)
				var tangent:=Vector3(1,0,0) if along_x else Vector3(0,0,1)
				var face:=center+outward*((size.y if along_x else size.x)*.5+float(building_data.get("wall",.65))*.5)
				var offsets:=[]
				if length*.5-2.4>=3.3:offsets.append_array([-(length*.5-2.4),length*.5-2.4])
				if length>21:offsets.append_array([-length*.25,length*.25])
				for offset in offsets:
					wall_clutter(face+tangent*offset,outward,height,solids,doors)
			# Security lights over the street-facing doors.
			# Beside the entrance sign band (when the building has one) instead of over its lettering.
			var light_x:=float(building_data.lintel[0])*.5+.45 if building_data.has("lintel") else 0.0
			props.scatter("security_light",Transform3D(Basis(Vector3.UP,0.0 if side>0 else PI),center+Vector3(light_x,minf(float(building_data.door)+1.05,height-.55),side*(size.y*.5+float(building_data.get("wall",.65))*.5+.15))))
		if building_data.furnished and size.x>=20:
			for sx in [-1.0,1.0]:
				for sz in [-1.0,1.0]:
					var spot:=center+Vector3(sx*(size.x*.5-1.3),0,sz*(size.y*.5-.6))
					props.place("steel_frame_shelves_01",props.grounded("steel_frame_shelves_01",spot,0.0 if sz<0 else PI),false,60.0)
		if size.x>=24 and center.y<.5:
			props.place("modular_airduct_rectangular_01",props.grounded("modular_airduct_rectangular_01",center+Vector3(0,height+.4,-size.y*.18),0.0),false,160.0)
	if buildings.any(func(data:Dictionary):return data.center==Vector3.ZERO and data.height>=7.5):
		# A travelling crane over the hall's central bay, hook clear of heads.
		props.place("overhead_crane",props.grounded("overhead_crane",Vector3(0,7.38-props.bounds("overhead_crane").size.y,0),PI*.5),false,0.0)
	var cars:=0;var rows:=0;var lamps:=0;var covers:=0
	# Cover props scale with the playable area (four of each on the large maps).
	var budget:=clampi(roundi(def.extent.x*def.extent.y/10000.0),2,4)
	var candidates:=[]
	for x in range(-int(def.extent.x*.5)+10,int(def.extent.x*.5)-9,6):
		for z in range(-int(def.extent.y*.5)+10,int(def.extent.y*.5)-9,6):candidates.append(Vector3(x,0,z))
	# Seeded shuffle so every prepare produces the same layout.
	for i in range(candidates.size()-1,0,-1):
		var j:=rng.randi_range(0,i);var swap:Variant=candidates[i];candidates[i]=candidates[j];candidates[j]=swap
	for spot:Vector3 in candidates:
		if cars<budget and spot_free(spot,Vector2(1.1,2.4),2.0,4.0,solids,points):
			var yaw:=PI*.5 if (cars%2==0) else 0.0
			props.place("covered_car",props.grounded("covered_car",spot,yaw+rng.randf_range(-.12,.12)),true,220.0)
			solids.append(AABB(spot-Vector3(2.4,0,2.4),Vector3(4.8,1.5,4.8)))
			var across:=Basis(Vector3.UP,yaw)*Vector3(1.9,0,0)
			def.cover_points.append_array([spot+across,spot-across]);def.cover_peeks.append_array([spot+across+Basis(Vector3.UP,yaw)*Vector3(0,0,3.2),spot-across-Basis(Vector3.UP,yaw)*Vector3(0,0,3.2)])
			points.append_array([spot+across,spot-across])
			cars+=1
		elif rows<budget and spot_free(spot,Vector2(2.6,.6),2.0,4.5,solids,points):
			var yaw:=0.0 if rows%2==0 else PI*.5
			var turn:=Basis(Vector3.UP,yaw)
			for i in 3:props.place("concrete_road_barrier_02",props.grounded("concrete_road_barrier_02",spot+turn*Vector3((i-1)*1.6,0,0),yaw+rng.randf_range(-.05,.05)),true,180.0)
			solids.append(AABB(spot-Vector3(2.6,0,2.6),Vector3(5.2,1.2,5.2)))
			def.cover_points.append_array([spot+turn*Vector3(0,0,1.4),spot-turn*Vector3(0,0,1.4)])
			def.cover_peeks.append_array([spot+turn*Vector3(3.4,0,1.4),spot-turn*Vector3(3.4,0,1.4)])
			points.append_array([spot+turn*Vector3(0,0,1.4),spot-turn*Vector3(0,0,1.4)])
			rows+=1
		elif covers<10 and spot_free(spot,Vector2(.4,.4),1.0,2.5,solids,points) and not on_paint(spot,Vector2(.9,.9)):
			# Small ground clutter in open yards: manhole covers or old tyres. The registry's
			# "ground_clutter_count" (default 10) caps how many appear; the random stream is
			# consumed either way so later layout decisions do not move.
			var yaw:=rng.randf()*TAU
			if covers<int(style.get("ground_clutter_count",10)):
				if style.get("ground_clutter","manhole")=="tyre":props.scatter("old_tyre",Transform3D(Basis(Vector3.RIGHT,PI*.5).rotated(Vector3.UP,yaw),spot+Vector3(0,.08,0)))
				else:props.scatter("water_manhole_cover",props.grounded("water_manhole_cover",spot,yaw))
			covers+=1
	# Street lamps line the main east-west street.
	for x in range(-84,85,24):
		for z in [-7.0,7.0]:
			var spot:=Vector3(x,0,z)
			if lamps<10 and spot_free(spot,Vector2(.4,.4),.6,1.5,solids,points):
				props.place("street_lamp_01",props.grounded("street_lamp_01",spot,0.0 if z<0 else PI),false,200.0);lamps+=1
	# Generators and tool carts tucked under the maintenance awnings.
	for awning in region.get_children():
		if not String(awning.name).begins_with("MaintenanceAwning"):continue
		for corner:Vector3 in [Vector3(-5.5,0,-3),Vector3(5.5,0,3)]:
			var spot:=Vector3(awning.position.x,0,awning.position.z)+corner
			if spot_free(spot,Vector2(.6,.5),.4,2.0,solids,points):props.place("portable_generator",props.grounded("portable_generator",spot,rng.randf()*TAU),false,90.0)
	props.flush(arena,85.0)
	print("Dressing ",def.id,": cars=",cars," barrier rows=",rows," lamps=",lamps," cover points=",def.cover_points.size())

# One piece of clutter against a wall: air-conditioning unit, utility box,
# drums, crates, gas bottles or an IBC tote, facing out from the wall.
func wall_clutter(face: Vector3, outward: Vector3, height: float, solids: Array[AABB], points: Array[Vector3]) -> void:
	var kind:=rng.randi_range(0,5)
	if kind==0 and height<4.5:kind=1
	var yaw:=atan2(outward.x,outward.z)
	var turn:=Basis(Vector3.UP,yaw)
	var spot:=face+outward*.32
	var half:=Vector2(1.0,.3) if absf(outward.z)>.5 else Vector2(.3,1.0)
	if not spot_free(spot,half,.05,.8,solids,points):return
	match kind:
		0:props.place("exterior_aircon_unit",props.grounded("exterior_aircon_unit",face+outward*.21,yaw),false,120.0)
		1:props.place("utility_box_02",props.grounded("utility_box_02",face+outward*.24,yaw),false,120.0)
		2:
			for i in rng.randi_range(2,3):
				var id:String=["Barrel_01","Barrel_02","barrel_03"][rng.randi()%3]
				props.scatter(id,props.grounded(id,face+outward*.33+turn*Vector3((i-1)*.66,0,0),rng.randf()*TAU))
		3:
			props.scatter("wooden_crate_02",props.grounded("wooden_crate_02",face+outward*.3,yaw+PI*.5))
			props.scatter("wooden_crate_02",props.grounded("wooden_crate_02",face+outward*.3,yaw+PI*.5+rng.randf_range(-.2,.2))*Transform3D(Basis.IDENTITY,Vector3(0,.46,0)))
		4:
			for i in 2:props.scatter("propane_tank",props.grounded("propane_tank",face+outward*.2+turn*Vector3((i-.5)*.42,0,0),rng.randf()*TAU))
		5:props.scatter("industrial_pastic_container",props.grounded("industrial_pastic_container",face+outward*.34,yaw))

# Decorative pieces share meshes and spatially grouped draw calls. They never
# add navigation surfaces or hidden collision to authored movement routes.
func detail(center:Vector3,size:Vector3,color:Color,kind:="steel",rotation:=Vector3.ZERO,reach:=0.0) -> void:
	var cell:=Vector2i(floori(center.x/24),floori(center.z/24))
	var key:=str(cell)+str(size)+str(color)+kind+str(reach)
	if not detail_groups.has(key):detail_groups[key]={"size":size,"color":color,"kind":kind,"reach":reach,"transforms":[]}
	detail_groups[key].transforms.append(Transform3D(Basis.from_euler(rotation),center))

# Old detail kinds map onto scans: light "concrete" details are painted
# markings, darker ones bare concrete, "earth" is planted ground.
func detail_surface(kind: String, color: Color) -> String:
	if kind=="steel":return "painted_metal"
	if kind=="earth":return "grass"
	return "paint_concrete" if color.get_luminance()>.45 else "concrete"

func flush_details() -> void:
	for data in detail_groups.values():
		var key:="detail"+str(data.size)
		if not meshes.has(key):meshes[key]=MapMeshes.block(data.size,minf(.008,minf(data.size.x,minf(data.size.y,data.size.z))*.2),0.0)
		var transforms:=PackedFloat32Array()
		for transform in data.transforms:transforms.append_array(MapArena.pack(transform))
		# Probe-lit: details are too small and numerous to earn lightmap texels.
		arena.instance_batches.append(["Detail"+str(arena.instance_batches.size()),meshes[key],surfaces.get_material(detail_surface(data.kind,data.color),data.color),transforms,GeometryInstance3D.GI_MODE_DYNAMIC,float(data.get("reach",0.0))])
	detail_groups.clear()

func cylinder(center: Vector3, radius: float, height: float, color: Color, parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var key:="cylinder"+str(radius)+"x"+str(height)
	if not meshes.has(key):
		meshes[key]=MapMeshes.cylinder(radius,height,clampi(roundi(radius*28),12,40),minf(.8,height*.4))
		meshes[key].lightmap_unwrap(Transform3D.IDENTITY,.3)
	node.mesh = meshes[key]
	node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	node.material_override = surfaces.get_material("painted_metal",color)
	(region if parent == null else parent).add_child(node)
	node.position = center
	if radius>.4 and height>1:
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
		var collision:=CollisionShape3D.new();var volume:=CylinderShape3D.new();volume.radius=radius;volume.height=height;collision.shape=volume;body.add_child(collision);node.add_child(body)
	return node

# Painted lettering: lit by the scene, no glowing outline, alpha-tested edges.
func sign_text(text: String, center: Vector3, angle: float, color := Color("e9eef2"), font_size := 96) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = .012
	label.modulate = color.lerp(Color(.84,.82,.76),.22)
	label.outline_size = 0
	label.shaded = true
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.double_sided=false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	region.add_child(label)
	label.position = center
	label.rotation.y = angle

func cover(center: Vector3, width := 3.0, color := Color("65737d")) -> void:
	box("Cover", center + Vector3(0,.65,0), Vector3(width,1.3,1.2), stone.darkened(.12))
	box("CoverCap", center + Vector3(0,1.34,0), Vector3(width+.08,.12,1.3), dark, false)
	for side in [-1,1]:detail(center+Vector3(0,.85,side*.608),Vector3(width*.8,.18,.018),color,"steel")
	def.cover_points.append(center + Vector3(0,0,2.0))
	def.cover_points.append(center + Vector3(0,0,-2.0))
	def.cover_peeks.append(center+Vector3(width*.5+.8,0,2.0))
	def.cover_peeks.append(center+Vector3(-width*.5-.8,0,-2.0))

func container_at(center: Vector3, color: Color, angle := 0.0) -> void:
	var root := box("Freight", center + Vector3(0,1.65,0), Vector3(11,3.3,3.2), color)
	root.rotation.y = angle
	var basis:=Basis(Vector3.UP,angle);var turn:=Vector3(0,angle,0)
	var frame:=color.darkened(.35)
	# Steel frame around the corrugated skin: corner posts, rails and castings.
	for sx in [-1,1]:
		for sz in [-1,1]:
			detail(center+basis*Vector3(sx*5.43,1.65,sz*1.53),Vector3(.16,3.3,.16),frame,"steel",turn)
			for y in [.09,3.21]:detail(center+basis*Vector3(sx*5.42,y,sz*1.52),Vector3(.2,.18,.2),Color("4a4d4f"),"steel",turn)
		for y in [.08,3.22]:
			detail(center+basis*Vector3(0,y,sx*1.57),Vector3(10.7,.16,.08),frame,"steel",turn)
			detail(center+basis*Vector3(sx*5.57,y,0),Vector3(.08,.16,2.9),frame,"steel",turn)
	# Cargo doors on the +X end: seam, locking bars with cam keepers and handles, hinges.
	detail(center+basis*Vector3(5.62,1.65,0),Vector3(.03,3.0,.035),Color("1e2224"),"steel",turn)
	for z in [-1.18,-.42,.42,1.18]:
		detail(center+basis*Vector3(5.66,1.65,z),Vector3(.05,2.95,.05),Color("8b8e88"),"steel",turn)
		for y in [.32,2.98]:detail(center+basis*Vector3(5.67,y,z),Vector3(.08,.12,.12),Color("6c6f6b"),"steel",turn)
		detail(center+basis*Vector3(5.72,1.3,z+(.14 if z<0 else -.14)),Vector3(.05,.05,.32),Color("8b8e88"),"steel",turn)
	for z in [-1.5,1.5]:
		for y in [.45,1.25,2.05,2.85]:detail(center+basis*Vector3(5.63,y,z),Vector3(.06,.14,.1),frame,"steel",turn)
	def.cover_points.append(center + basis*Vector3(0,0,4.0))
	def.cover_points.append(center + basis*Vector3(0,0,-4.0))
	def.cover_peeks.append(center+basis*Vector3(6.3,0,4.0))
	def.cover_peeks.append(center+basis*Vector3(-6.3,0,-4.0))

func building(center: Vector3, size: Vector2, height: float, title: String, furnished:=true) -> void:
	var sx := size.x
	var sz := size.y
	var door:=4.0
	var doorway_height:=minf(3.4,height-.7)
	if center.y<.5:footprints.append(Rect2(center.x-sx*.5,center.z-sz*.5,sx,sz))
	buildings.append({"center":center,"size":size,"height":height,"furnished":furnished,"door":doorway_height,"wall":.65})
	for side in [-1,1]:
		for reach in [1.5,4.0]:avoid.append_array([center+Vector3(side*(sx*.5+reach),0,0),center+Vector3(0,0,side*(sz*.5+reach))])
	var glass_out:=SurfaceTool.new();glass_out.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass_in:=SurfaceTool.new();glass_in.begin(Mesh.PRIMITIVE_TRIANGLES)
	var brick:=wall_kind()=="brick"
	# Four entrances split the building perimeter; every interior remains traversable.
	for side in [-1,1]:
		for segment in [-1,1]:
			var side_size:=Vector3(.65,height,(sz-door)*.5)
			glaze_wall(box("HallWall", center + Vector3(side*sx*.5,height*.5,segment*(sz+door)*.25), side_size, stone),side_size,side,center,glass_out,glass_in)
			var front_size:=Vector3((sx-door)*.5,height,.65)
			glaze_wall(box("HallWall", center + Vector3(segment*(sx+door)*.25,height*.5,side*sz*.5), front_size, stone),front_size,side,center,glass_out,glass_in)
			if brick:
				detail(center+Vector3(side*(sx*.5+.34),.22,segment*(sz+door)*.25),Vector3(.05,.44,(sz-door)*.5),stone.darkened(.3),"concrete")
				detail(center+Vector3(segment*(sx+door)*.25,.22,side*(sz*.5+.34)),Vector3((sx-door)*.5,.44,.05),stone.darkened(.3),"concrete")
		box("DoorLintel",center+Vector3(side*sx*.5,(height+doorway_height)*.5,0),Vector3(.85,height-doorway_height,door),stone)
		box("DoorLintel",center+Vector3(0,(height+doorway_height)*.5,side*sz*.5),Vector3(door,height-doorway_height,.85),stone)
		# Steel door frames, roller-shutter housings and guide rails at each entrance.
		box("ShutterHousing",center+Vector3(side*(sx*.5+.68),doorway_height+.32,0),Vector3(.5,.55,door+.5),Color("5c6367"),false)
		box("ShutterHousing",center+Vector3(0,doorway_height+.32,side*(sz*.5+.68)),Vector3(door+.5,.55,.5),Color("5c6367"),false)
		for edge in [-1,1]:
			detail(center+Vector3(side*(sx*.5+.4),doorway_height*.5,edge*door*.5),Vector3(.15,doorway_height,.16),accent)
			detail(center+Vector3(edge*door*.5,doorway_height*.5,side*(sz*.5+.4)),Vector3(.16,doorway_height,.15),accent)
	box("Roof", center+Vector3(0,height+.2,0),Vector3(sx+1,.4,sz+1),dark)
	box("InteriorSlab",center+Vector3(0,.012,0),Vector3(sx,.024,sz),stone.darkened(.15),false)
	if furnished:interior_rooms(center,size,height,title)
	for x in [-sx*.5,sx*.5]:
		for z in [-sz*.5,sz*.5]:
			box("SteelColumn",center+Vector3(x,height*.5,z),Vector3(.8,height,.8),metal)
	if brick:
		# Brick parapet with a concrete coping hides the roof line.
		for side in [-1,1]:
			box("Parapet",center+Vector3(0,height+.75,side*sz*.5),Vector3(sx+.65,.7,.65),stone,false)
			box("Parapet",center+Vector3(side*sx*.5,height+.75,0),Vector3(.65,.7,sz-.65),stone,false)
			box("Coping",center+Vector3(0,height+1.14,side*sz*.5),Vector3(sx+.8,.08,.8),dark,false)
			box("Coping",center+Vector3(side*sx*.5,height+1.14,0),Vector3(.8,.08,sz-.8),dark,false)
	else:
		# Painted fascia, eaves gutters and downpipes on the concrete stations.
		for side in [-1,1]:
			box("Fascia",center+Vector3(0,height+.2,side*(sz*.5+.52)),Vector3(sx+1.08,.44,.04),Color("3c4347"),false)
			box("Fascia",center+Vector3(side*(sx*.5+.52),height+.2,0),Vector3(.04,.44,sz+1),Color("3c4347"),false)
			var gutter:=cylinder(center+Vector3(0,height-.02,side*(sz*.5+.62)),.085,sx+1.0,Color("6e7478"));gutter.rotation.z=PI*.5
			for x in [-sx*.5+1.1,sx*.5-1.1]:
				cylinder(center+Vector3(x,height*.5,side*(sz*.5+.42)),.055,height,Color("6e7478"))
	for side in [-1,1]:
		sign_text(title,center+Vector3(0,height-1.1,side*(sz*.5+.4)),0 if side==1 else PI,accent,72)
		detail(center+Vector3(0,height-1.1,side*(sz*.5+.355)),Vector3(title.length()*.52+.9,1.05,.04),Color("2c3236"))
		for stripe in 8:box("Hazard",center+Vector3(-2.7+stripe*.75,.015,side*(sz*.5+1.2)),Vector3(.42,.03,1.1),accent if stripe%2==0 else dark,false)
		for y in [height*.45,height-.3]:detail(center+Vector3(side*(sx*.5+.35),y,0),Vector3(.11,.14,sz),metal)
		var pipe:=cylinder(center+Vector3(side*(sx*.5+.5),height*.6,0),.12,sz,Color("62696a"));pipe.rotation.x=PI*.5
		for z in [-sz*.35,sz*.35]:detail(center+Vector3(side*(sx*.5+.5),height*.6,z),Vector3(.32,.4,.12),dark)
	for z in [-sz*.35,0,sz*.35]:
		box("RoofBeam",center+Vector3(0,height-.35,z),Vector3(sx,.45,.32),metal,false)
	for x in [-sx*.34,sx*.34]:
		box("Ventilation",center+Vector3(x,height+.65,0),Vector3(3.2,.9,2),metal,false)
		for grille in 6:box("VentGrille",center+Vector3(x-1.2+grille*.48,height+1.12,0),Vector3(.12,.04,1.75),dark,false)
	glazing(center,glass_out,glass_in)
	interior_lighting(center,size,height)

# Cuts evenly spaced windows through a perimeter wall segment (its collision
# box is untouched) and queues their panes: reflective glass outside, frosted
# daylit glass inside. Tall halls get clerestory windows above head height.
func glaze_wall(item:Node3D, size:Vector3, side:int, center:Vector3, glass_out:SurfaceTool, glass_in:SurfaceTool) -> void:
	var along_x:=size.x>size.z
	var length:=size.x if along_x else size.z
	var thickness:=size.z if along_x else size.x
	var height:=size.y
	var count:=int((length-1.4)/4.4)
	var openings:=[]
	if count>0:
		var pitch:=length/count
		var width:=minf(2.8,pitch-1.4)
		var y0:=height-3.1 if height>=5.5 else 1.05
		var y1:=height-1.45 if height>=5.5 else minf(height-.95,2.45)
		for i in count:openings.append(Rect2(pitch*(i+.5)-width*.5,y0,width,y1-y0))
	var key:="wall"+str(Vector3(length,height,thickness))+"/"+str(openings.size())
	if not meshes.has(key):
		meshes[key]=MapMeshes.wall(Vector3(length,height,thickness),openings,1.1)
		meshes[key].lightmap_unwrap(Transform3D.IDENTITY,.35)
	var visual:MeshInstance3D=item.get_child(0)
	visual.mesh=meshes[key]
	visual.material_override=surfaces.get_material(wall_kind())
	var turn:=Basis.IDENTITY if along_x else Basis(Vector3.UP,PI*.5)
	if not along_x:visual.rotation.y=PI*.5
	var outward:=turn*Vector3(0,0,side)
	for rect:Rect2 in openings:
		var local:=Vector3(rect.position.x+rect.size.x*.5-length*.5,rect.position.y+rect.size.y*.5-height*.5,0)
		var pane:=item.position+turn*local
		queued_panes+=1
		MapMeshes.add_quad(glass_out,pane-center+outward*.035,Vector3.UP.cross(outward),Vector3.UP,rect.size)
		MapMeshes.add_quad(glass_in,pane-center-outward*.035,Vector3.UP.cross(-outward),Vector3.UP,rect.size)
		var bar_turn:=Vector3(0,0.0 if along_x else PI*.5,0)
		for y in [-rect.size.y*.5+.03,rect.size.y*.5-.03,rect.size.y*(.08 if rect.size.y>1.2 else .5)]:
			detail(pane+Vector3(0,y,0),Vector3(rect.size.x,.06,.09),Color("2b3033"),"steel",bar_turn)
		var mullions:=maxi(1,roundi(rect.size.x/1.1))
		for m in mullions+1:
			var offset:=-rect.size.x*.5+.03+(rect.size.x-.06)*m/mullions
			detail(pane+turn*Vector3(offset,0,0),Vector3(.06,rect.size.y,.09),Color("2b3033"),"steel",bar_turn)

func glazing(center:Vector3, glass_out:SurfaceTool, glass_in:SurfaceTool) -> void:
	if queued_panes==0:return
	queued_panes=0
	var mesh:=ArrayMesh.new()
	glass_out.index();glass_out.generate_tangents();glass_out.commit(mesh)
	glass_in.index();glass_in.generate_tangents();glass_in.commit(mesh)
	mesh.lightmap_unwrap(Transform3D.IDENTITY,.3)
	if not materials.has("glass_out"):
		var outside:=StandardMaterial3D.new();outside.albedo_color=Color(.07,.09,.1);outside.metallic=.15;outside.roughness=.06;outside.metallic_specular=.9
		materials["glass_out"]=outside
		# Frosted wired glass lit by the day outside: emissive so it also bakes
		# soft daylight into the room.
		var inside:=StandardMaterial3D.new();inside.albedo_color=Color(.78,.8,.8);inside.roughness=.55
		inside.emission_enabled=true;inside.emission=Color(.86,.9,.97);inside.emission_energy_multiplier=1.6
		materials["glass_in"]=inside
	var panes:=MeshInstance3D.new();panes.name="Glazing"+str(serial);serial+=1
	panes.mesh=mesh;panes.position=center;panes.gi_mode=GeometryInstance3D.GI_MODE_STATIC
	panes.set_surface_override_material(0,materials["glass_out"]);panes.set_surface_override_material(1,materials["glass_in"])
	region.add_child(panes)

# Fluorescent fixtures hang between the roof beams on a grid of roughly 7 m.
# Their lights are fully baked (direct, bounce and shadows), so interiors read
# at no run-time cost; a box-projected probe gives the room its own reflections.
func interior_lighting(center:Vector3,size:Vector2,height:float) -> void:
	var columns:=maxi(1,roundi(size.x/9.0));var rows:=maxi(2,roundi(size.y/7.0))
	var mount:=height-.62
	for column in columns:
		for row in rows:
			var x:=(column-(columns-1)*.5)*size.x/columns;var z:=(row-(rows-1)*.5)*size.y/rows
			var fixture:=center+Vector3(x,mount,z)
			box("LampHousing",fixture+Vector3(0,.06,0),Vector3(1.5,.1,.32),Color("8d9296"),false)
			box("CeilingLamp",fixture,Vector3(1.38,.04,.2),Color("f4f1e6"),false)
			var lamp:=OmniLight3D.new()
			lamp.name="FixtureLight"+str(serial);serial+=1
			lamp.position=fixture+Vector3(0,-.25,0)
			lamp.light_color=Color(1.0,.955,.86)
			lamp.light_energy=2.1;lamp.light_indirect_energy=1.4
			lamp.omni_range=clampf(maxf(size.x/columns,size.y/rows)*1.35,7.0,12.0);lamp.omni_attenuation=1.4
			lamp.shadow_enabled=true;lamp.light_size=.35
			lamp.light_bake_mode=Light3D.BAKE_STATIC
			region.add_child(lamp)
	var volume:=Vector3(size.x-.4,height,size.y-.4)
	arena.probe_volumes.append(AABB(center+Vector3(0,height*.5,0)-volume*.5,volume))

func ramp(start: Vector3, end: Vector3, width: float) -> void:
	var difference := end-start
	var length := Vector2(difference.x,difference.z).length()
	var node := box("AccessRamp", (start+end)*.5-Vector3(0,.15,0), Vector3(width,.3,sqrt(length*length+difference.y*difference.y)), stone)
	node.rotation.y = atan2(difference.x,difference.z)
	node.rotation.x = -atan2(difference.y,length)
	var run:=sqrt(length*length+difference.y*difference.y)
	for side in [-1,1]:
		# Solid parapets: the open edges of a bare slab let players and bots slide off
		# onto the ground beside it, under a wall too high to climb back over. They also
		# make navigation baking keep clear of the edge.
		box("RampParapet",Vector3(side*(width*.5-.07),.6,0),Vector3(.14,.9,run),stone,true,node)
		var rail := box("RampRail",Vector3(side*(width*.5-.07),1.1,0),Vector3(.2,.1,run),accent,false,node)
		rail.rotation = Vector3.ZERO
	# Plumb end posts with caps: the tilted parapets otherwise end in sheared faces,
	# one dug into the ground and one jutting at the top.
	var across := Vector3(difference.z,0,-difference.x).normalized()
	for side in [-1,1]:
		for anchor in [start,end]:
			var foot:Vector3=anchor+across*side*(width*.5-.07)
			box("RampPost",foot+Vector3(0,.6,0),Vector3(.26,1.2,.26),stone,false)  # visual only: the parapets already block
			box("RampPostCap",foot+Vector3(0,1.24,0),Vector3(.32,.08,.32),accent,false)

func interior_rooms(center:Vector3,size:Vector2,height:float,title:String) -> void:
	# Cross circulation stays four metres wide; side rooms provide alternate
	# angles instead of furnishing a single giant empty box.
	if size.x>=20 and size.y>=16:
		for side in [-1,1]:
			for end in [-1,1]:
				var length:=size.y*.5-3
				box("RoomPartition",center+Vector3(side*size.x*.27,1.7,end*(size.y*.5+3)*.5),Vector3(.2,3.4,length),stone.darkened(.08))
	for side in [-1,1]:
		for end in [-1,1]:
			var point:=center+Vector3(side*size.x*.36,0,end*size.y*.31)
			box("Workbench",point+Vector3(0,.48,0),Vector3(2.4,.96,.85),dark)
			box("Worktop",point+Vector3(0,1,0),Vector3(2.55,.08,.95),metal,false)
			detail(point+Vector3(.7,1.3,0),Vector3(.45,.55,.12),Color("283b45"))
			detail(point+Vector3(.7,1.3,-.07),Vector3(.36,.37,.01),Color("719593"))
			detail(point+Vector3(-.7,1.08,0),Vector3(.8,.06,.55),Color("a9a295"),"concrete")
	for side in [-1,1]:
		for x in range(-int(size.x*.35),int(size.x*.35),3):detail(center+Vector3(x,.032,side*2.9),Vector3(1.6,.02,.10),accent,"concrete")
	if title.replace(" ","").contains("FOUNDRY"):
		for x in [-6,6]:
			for z in [-7,7]:
				box("PressBase",center+Vector3(x,.6,z),Vector3(3.4,1.2,3),metal)
				for side in [-1,1]:box("PressFrame",center+Vector3(x+side*1.25,2.5,z),Vector3(.32,3.8,.55),dark)
				box("PressBeam",center+Vector3(x,4.15,z),Vector3(3,.55,1.5),accent)
	elif size.x>30:
		for x in [-7,7]:
			for z in [-6,6]:
				box("ServerCabinet",center+Vector3(x,1.2,z),Vector3(1.4,2.4,1.0),dark)
				for shelf in 7:
					detail(center+Vector3(x,.3+shelf*.29,z+.51),Vector3(1.2,.16,.035),metal)
					detail(center+Vector3(x+.43,.3+shelf*.29,z+.535),Vector3(.09,.045,.015),Color("77ac96"))
				box("ControlDesk",center+Vector3(x,.47,z+1.8),Vector3(2.4,.94,.8),metal)
				detail(center+Vector3(x,1.3,z+1.6),Vector3(.9,.6,.08),Color("293b43"))
				detail(center+Vector3(x,1.3,z+1.65),Vector3(.79,.47,.02),Color("73998d"))

func cargo_cluster(center:Vector3, angle:=0.0) -> void:
	var root:=box("PalletLoad",center+Vector3(0,.72,0),Vector3(2.6,1.44,1.6),Color("726553"));root.rotation.y=angle
	for i in 6:box("PalletBoard",Vector3(-1.15+i*.46,-.67,0),Vector3(.34,.12,1.75),Color("8b7a5b"),false,root)
	for side in [-1,1]:box("CargoBand",Vector3(side*.85,.02,0),Vector3(.05,1.5,1.64),dark,false,root)
	var orientation:=Basis(Vector3.UP,angle)
	def.cover_points.append(center+orientation*Vector3(0,0,2.3));def.cover_peeks.append(center+orientation*Vector3(2.1,0,2.3))

func utility_truck(center:Vector3, angle:float, paint:Color) -> void:
	stains.append(center);stains.append(center+Basis(Vector3.UP,angle)*Vector3(2.2,0,0))
	var root:=box("TruckChassis",center+Vector3(0,.9,0),Vector3(7,1.05,2.5),dark);root.rotation.y=angle
	box("TruckBed",Vector3(-1,.85,0),Vector3(4.8,.65,2.6),paint,true,root)
	box("TruckCab",Vector3(2.25,1.05,0),Vector3(2.25,1.95,2.5),paint,true,root)
	box("CabWindscreen",Vector3(3.39,1.37,0),Vector3(.035,.72,2.1),Color("365261"),false,root)
	for side in [-1,1]:
		box("CabGlass",Vector3(2.4,1.45,side*1.27),Vector3(1.1,.65,.035),Color("365261"),false,root)
		box("TruckMirror",Vector3(2.8,1.42,side*1.5),Vector3(.22,.35,.12),dark,false,root)
		for x in [-2.2,2.2]:
			var wheel:=cylinder(Vector3(x,-.33,side*1.25),.5,.32,Color("171b1d"),root);wheel.rotation.x=PI*.5
		for z in [-.86,.86]:box("Headlight",Vector3(3.51,.45,z),Vector3(.06,.25,.38),Color("d8d1b0"),false,root)
	var facing:=Basis(Vector3.UP,angle)
	for side in [-1,1]:
		def.cover_points.append(center+facing*Vector3(0,0,side*2.3));def.cover_peeks.append(center+facing*Vector3(-4.3,0,side*2.3))

# Photographed CC0 skies (Poly Haven), from the registry entry's "lighting".
# sun_u/sun_elevation locate the sun disc in the equirectangular image
# (measured from the HDR); sky_turn rotates the panorama about +Y so the sun
# crosses the lanes instead of blinding one team.
# Direction from the scene toward the sun disc after the panorama is turned.
static func sun_direction(sky: Dictionary) -> Vector3:
	var azimuth:float=TAU*float(sky.sun_u);var elevation:=deg_to_rad(float(sky.sun_elevation))
	var toward:=Vector3(sin(azimuth)*cos(elevation),sin(elevation),-cos(azimuth)*cos(elevation))
	return Basis(Vector3.UP,deg_to_rad(float(sky.sky_turn)))*toward

func lighting() -> void:
	var settings:Dictionary=lighting_settings
	var environment := WorldEnvironment.new()
	environment.name="Environment"
	var env := Environment.new()
	var sky := Sky.new()
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama=load(settings.hdri)
	sky_material.energy_multiplier=settings.sky_energy
	sky.sky_material=sky_material
	sky.process_mode=Sky.PROCESS_MODE_QUALITY
	sky.radiance_size=Sky.RADIANCE_SIZE_256
	env.background_mode=Environment.BG_SKY;env.sky=sky
	env.sky_rotation=Vector3(0,deg_to_rad(float(settings.sky_turn)),0)
	# Static geometry takes sky light from the lightmap; dynamic actors and the
	# first-person rig take it from the baked probes, with the sky as fallback.
	env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy=1.0
	env.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode=Environment.TONE_MAPPER_AGX
	env.tonemap_exposure=1.0
	env.ssao_enabled=true;env.ssao_radius=1.4;env.ssao_intensity=1.6;env.ssao_power=1.4;env.ssao_detail=.6;env.ssao_light_affect=.08;env.ssao_ao_channel_affect=.35
	env.ssil_enabled=true;env.ssil_radius=4.0;env.ssil_intensity=.85;env.ssil_sharpness=.96
	env.glow_enabled=true;env.glow_intensity=.32;env.glow_strength=.95;env.glow_bloom=.015;env.glow_hdr_threshold=1.15;env.glow_blend_mode=Environment.GLOW_BLEND_MODE_SCREEN
	# Aerial perspective tints distance haze with the sky itself; the panorama
	# already contains its own atmosphere, so the sky is left unfogged.
	env.fog_enabled=true;env.fog_mode=Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color=MapCatalog.color(settings.haze);env.fog_density=settings.fog;env.fog_aerial_perspective=.7;env.fog_sky_affect=0.0;env.fog_sun_scatter=.08
	# Thin volumetric haze catches the sun through doors and windows (light shafts
	# in the halls); apply_quality switches it off on Low.
	env.volumetric_fog_enabled=true;env.volumetric_fog_density=settings.volume;env.volumetric_fog_albedo=Color(.92,.93,.94)
	env.volumetric_fog_anisotropy=.55;env.volumetric_fog_length=72.0;env.volumetric_fog_detail_spread=2.0;env.volumetric_fog_ambient_inject=.12;env.volumetric_fog_sky_affect=0.0
	env.adjustment_enabled=true;env.adjustment_contrast=1.04;env.adjustment_saturation=1.08
	environment.environment=env
	# Fixed exposure (MapArena.EXPOSURE, also applied at load to maps prepared before it).
	var camera := CameraAttributesPractical.new()
	camera.auto_exposure_enabled=false;camera.exposure_multiplier=MapArena.EXPOSURE
	environment.camera_attributes=camera
	arena.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name="Sun"
	sun.basis=Basis.looking_at(-sun_direction(settings),Vector3.UP)
	sun.light_color=MapCatalog.color(settings.sun_color)
	sun.light_energy=settings.sun_energy;sun.light_angular_distance=.55;sun.shadow_enabled=true
	sun.shadow_bias=.03;sun.shadow_normal_bias=1.2;sun.shadow_blur=1.0
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;sun.directional_shadow_blend_splits=true
	sun.directional_shadow_max_distance=80
	sun.directional_shadow_fade_start=.85
	# Dynamic bake mode: indirect light and a shadowmask are baked; direct light
	# and near shadows stay real-time so soldiers and weapons cast them.
	sun.light_bake_mode=Light3D.BAKE_DYNAMIC
	sun.sky_mode=DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	arena.add_child(sun)
	var gi := LightmapGI.new()
	gi.name="BakedLight";gi.quality=LightmapGI.BAKE_QUALITY_MEDIUM
	gi.directional=true;gi.shadowmask_mode=LightmapGIData.SHADOWMASK_MODE_REPLACE
	gi.bounces=3;gi.use_denoiser=true;gi.interior=false
	gi.environment_mode=LightmapGI.ENVIRONMENT_MODE_SCENE
	gi.generate_probes_subdiv=LightmapGI.GENERATE_PROBES_SUBDIV_8
	gi.max_texture_size=4096
	# 0.75 texel scale keeps each map's atlas near 25 MB with little visible loss.
	gi.texel_scale=.75
	arena.add_child(gi);arena.lightmap=gi

func set_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner=owner
		set_owners(child,owner)
