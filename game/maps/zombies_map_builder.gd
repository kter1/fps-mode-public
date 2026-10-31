class_name ZombiesMapBuilder
extends MapBuilder

# Shared authored floor plan. Each retained room has its own saved nav region;
# portal gaps are navigation gaps only, not holes in physical floor collision.
var data: Dictionary
var ruin_plaster: ShaderMaterial
var brick_batch: SurfaceTool
var plaster_batch: SurfaceTool

func build(id: String) -> MapArena:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://content/data/zombies/maps/"+id+".json"))
	var entry:=MapCatalog.entry(id);style=entry.style;lighting_settings=entry.lighting
	ruin_plaster=surfaces.get_material("plaster").duplicate()
	ruin_plaster.set_shader_parameter("tint",Color("8f9977") if id=="dead_current" else Color("8c9c9c"));ruin_plaster.set_shader_parameter("tint_mix",.48)
	ruin_plaster.set_shader_parameter("paint_gain",1.4);ruin_plaster.set_shader_parameter("grime_amount",1.0)
	arena=MapArena.new();arena.name=str(entry.display_name);arena.fixed_geometry_visibility=true
	def=MapDefinition.new();def.id=id;def.display_name=arena.name;def.extent=Vector2(76,64);def.scene_path=MapCatalog.scene_path(id);def.zombies=data
	arena.definition=def
	region=NavigationRegion3D.new();region.name="Architecture";region.enabled=false;arena.add_child(region);arena.nav_region=region;props=MapProps.new(region)
	box("InteriorSlab",Vector3(0,-.25,0),Vector3(76,.5,64),Color("848b86"))
	brick_batch=SurfaceTool.new();brick_batch.begin(Mesh.PRIMITIVE_TRIANGLES)
	plaster_batch=SurfaceTool.new();plaster_batch.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Main shell has fourteen authored window openings, not painted boards on solid walls.
	outer_run(-26,0,[-28.0,-16.0,-6.0,6.0,16.0,28.0],true)
	outer_run(26,PI,[-28.0,-16.0,-6.0,6.0,16.0,28.0],true)
	outer_run(-33,-PI*.5,[7.0,19.0],false)
	outer_run(33,PI*.5,[],false)
	for x in [-11.0,11.0]:
		for z in [-13.0,13.0]:wall(Vector3(x,0,z),PI*.5,26.0,[0.0],[4.0],false)
	for x in [-22.0,0.0,22.0]:wall(Vector3(x,0,0),0,22.0,[0.0],[4.0],false)
	for zone_index in data.zones.size():
		var zone: Dictionary=data.zones[zone_index];var c:=MapCatalog.vec3(zone.center)
		var obstacles: Array=[]
		if id=="dead_current" and zone_index==3:
			for offset in [-4.5,4.5]:
				var turbine:=cylinder(c+Vector3(offset,1.5,0),1.45,7.5,Color("536e68"));turbine.rotation.x=PI*.5
				obstacles.append(Rect2(Vector2(c.x+offset-2,c.z-4.6),Vector2(4,9.2)))
			for x in [-4.5,4.5]:
				for z in [-3.0,0.0,3.0]:box("Ventilation",c+Vector3(x,2.5,z),Vector3(2.6,.35,.7),Color("777f77"),false)
		else:
			var size:=Vector3(5,1.1,7) if zone_index in [1,5] else Vector3(4,1.25,3)
			var prop_id: String=""
			if id=="dead_current":prop_id=["metal_office_desk","portable_generator","steel_frame_shelves_02","","metal_office_desk","old_military_compressor"][zone_index]
			elif zone_index in [0,4,5]:prop_id="industrial_storage_cart" if zone_index==5 else "metal_office_desk"
			if not prop_id.is_empty():
				var bounds:=props.bounds(prop_id)
				var scale:=minf(minf((size.x-.3)/maxf(bounds.size.x,.1),(size.z-.3)/maxf(bounds.size.z,.1)),2.2/maxf(bounds.size.y,.1))
				props.place(prop_id,props.grounded(prop_id,c,0,scale),true)
			else:
				box("Worktop",c+Vector3(0,.35,0),Vector3(size.x,.7,size.z),Color("52636a"))
				if zone_index==2:
					box("Worktop",c+Vector3(0,2,0),Vector3(4,1,2.5),Color("b4bec0"))
					for side in [-1,1]:box("Worktop",c+Vector3(side*1.8,1,0),Vector3(.4,2,2.5),Color("a9b0ad"))
			obstacles.append(Rect2(Vector2(c.x-size.x*.5-.6,c.z-size.z*.5-.6),Vector2(size.x+1.2,size.z+1.2)))
			if id=="dead_air" and zone_index==1:
				for offset in [-2.0,0.0,2.0]:box("Freight",c+Vector3(offset,1.45,0),Vector3(.9,.5,1.5),Color("614d41"),false)
		# Seating / pipe racks hug the edges; central islands preserve two circulation sides.
		for side in [-1,1]:
			ZombieObjects.solid(region,Vector3(1.2,.9,4),c+Vector3(side*7.4,.45,5.5))
			obstacles.append(Rect2(Vector2(c.x+side*7.4-1.2,c.z+2.9),Vector2(2.4,5.2)))
		for z in [-8.0,8.0]:
			box("CeilingLamp",c+Vector3(0,4.7,z),Vector3(3,.12,.25),Color.WHITE,false)
			var lamp:=OmniLight3D.new();lamp.position=c+Vector3(0,4.1,z);lamp.omni_range=14;lamp.light_energy=1.1;lamp.light_color=Color("efd0a2") if id=="dead_current" else Color("bed7dc");lamp.light_bake_mode=Light3D.BAKE_STATIC;arena.add_child(lamp)
		var text:=ZombieObjects.label(region,str(zone.name).to_upper(),c+Vector3(0,3.3,-11.6),Color("e5d7ae"),75);text.gi_mode=GeometryInstance3D.GI_MODE_STATIC
		if zone_index!=5 and not (id=="dead_current" and zone_index==1):box("Roof",c+Vector3(0,5.2,0),Vector3(21.8,.25,25.8),Color("77817a"),true)
		if id=="dead_air":
			ZombieObjects.label(region,"DEPARTURES  →" if zone_index in [0,2] else ("BAGGAGE / SERVICE" if zone_index==1 else "GATE 04 / QUARANTINE"),c+Vector3(0,2.7,10.8),Color("95c6d7"),45).rotation.y=PI
		else:
			ZombieObjects.label(region,"POWER / CONTROL  →" if zone_index<4 else "DANGER / HIGH VOLTAGE",c+Vector3(0,2.7,10.8),Color("e0bd6b"),45).rotation.y=PI
		# Machines are physical obstacles too; leave clearance for either enemy anatomy.
		for station: Dictionary in data.stations:
			if int(station.get("zone",0))==zone_index and str(station.kind)!="wall":
				var point:=MapCatalog.vec3(station.position)
				obstacles.append(Rect2(Vector2(point.x-1,point.z-1),Vector2(2,2)))
		ZombiesSetDressing.dress(self,id,zone_index,c,obstacles)
		make_navigation(zone_index,c,obstacles)
	# Context makes the station/airport a place, without a second playable arena.
	for i in 7:
		var x:=-42+i*14
		box("ContextWarehouse",Vector3(x,5,-39),Vector3(11,10,10),Color("5f6869"),false)
	if id=="dead_current":
		box("ContextWarehouse",Vector3(40,12,-10),Vector3(7,24,7),Color("68746f"),false)
	else:
		box("ContextWarehouse",Vector3(0,9,-42),Vector3(7,18,7),Color("70868e"),false)
	# Batch the two wall finishes without changing geometry, UVs or colliders.
	# This avoids issuing a separate draw call for every wall/plaster segment.
	var walls:=ArrayMesh.new()
	for source in [brick_batch.commit(),plaster_batch.commit()]:walls.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(0))
	walls.surface_set_material(0,surfaces.get_material(wall_kind()));walls.surface_set_material(1,ruin_plaster)
	walls.lightmap_unwrap(Transform3D.IDENTITY,.35)
	var wall_node:=MeshInstance3D.new();wall_node.name="BatchedWallFinishes";wall_node.mesh=walls;wall_node.gi_mode=GeometryInstance3D.GI_MODE_STATIC;region.add_child(wall_node)
	lighting();set_owners(arena,arena)
	return arena

func outer_run(axis: float, angle: float, holes: Array, along_x: bool) -> void:
	wall(Vector3(0,0,axis) if along_x else Vector3(axis,0,0),angle,66.0 if along_x else 52.0,holes,[],true)

func wall(origin: Vector3, angle: float, length: float, holes: Array, widths: Array, window := false) -> void:
	var ranges: Array=[]
	for i in holes.size():ranges.append([float(holes[i])-(2.4 if widths.is_empty() else float(widths[i]))*.5,float(holes[i])+(2.4 if widths.is_empty() else float(widths[i]))*.5])
	ranges.sort_custom(func(a:Array,b:Array)->bool:return a[0]<b[0])
	var last:=-length*.5
	for span in ranges:
		segment(origin,angle,last,float(span[0]),0,5)
		if window:segment(origin,angle,float(span[0]),float(span[1]),0,.25)
		segment(origin,angle,float(span[0]),float(span[1]),2.6 if window else 3.4,5)
		last=float(span[1])
	segment(origin,angle,last,length*.5,0,5)

func segment(origin: Vector3, angle: float, a: float, b: float, bottom: float, top: float) -> void:
	if b-a<.01:return
	var position:=origin+Basis(Vector3.UP,angle)*Vector3((a+b)*.5,(bottom+top)*.5,0)
	var node:=box("HallWall",position,Vector3(b-a,top-bottom,.5),Color("8b8c7f"));node.rotation.y=angle
	var visual:=node.get_child(0) as MeshInstance3D
	brick_batch.append_from(visual.mesh,0,Transform3D(Basis(Vector3.UP,angle),position));visual.free()
	# A worn plaster dado below exposed brick breaks the monolithic room shells.
	var plaster_top:=minf(top,3.25)
	if plaster_top>bottom+.05:
		var surface_position:=origin+Basis(Vector3.UP,angle)*Vector3((a+b)*.5,(bottom+plaster_top)*.5,0)
		var mesh:=part_mesh("RuinPlaster",Vector3(b-a,plaster_top-bottom,.54))
		plaster_batch.append_from(mesh,0,Transform3D(Basis(Vector3.UP,angle),surface_position))

func make_navigation(index: int, center: Vector3, obstacles: Array) -> void:
	var nav_region:=NavigationRegion3D.new();nav_region.name="ZoneNav_%d"%index;nav_region.use_edge_connections=false
	var mesh:=NavigationMesh.new();mesh.cell_size=.25;mesh.cell_height=.25;mesh.agent_radius=.5;mesh.agent_height=2
	var vertices:=PackedVector3Array();var polygons: Array[PackedInt32Array]=[]
	# Indexed 1m cells share exact vertices. Omit cells under expanded physical obstacles.
	for z in 24:
		for x in 20:
			var at:=Vector2(center.x-10+x,center.z-12+z);var blocked:=false
			for rect: Rect2 in obstacles:
				if rect.intersects(Rect2(at,Vector2.ONE)):blocked=true;break
			if blocked:continue
			var base:=vertices.size()
			for p in [Vector3(at.x,0,at.y),Vector3(at.x,0,at.y+1),Vector3(at.x+1,0,at.y+1),Vector3(at.x+1,0,at.y)]:vertices.append(p)
			polygons.append(PackedInt32Array([base,base+1,base+2,base+3]))
	mesh.vertices=vertices
	for polygon in polygons:mesh.add_polygon(polygon)
	nav_region.navigation_mesh=mesh;arena.add_child(nav_region);arena.zombie_regions.append(nav_region)
