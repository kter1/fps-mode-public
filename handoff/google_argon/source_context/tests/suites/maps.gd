extends RefCounted

# Content checks for map assets, saved scenes, markers, navigation and lighting.
static func run(t) -> void:
	wall_openings(t)
	# Every delivered map asset is CC0 and matches its recorded hash.
	# Shared content/manifest/maps.json merged with per-map content/manifest/maps/<id>.json.
	var manifest:=MapCatalog.asset_manifest()
	t.check_that(manifest is Dictionary and manifest.assets.size()>=40,"map_manifest_present")
	if manifest is Dictionary:
		for id in manifest.assets:
			var asset:Dictionary=manifest.assets[id]
			var valid:bool=asset.license=="CC0-1.0" and not asset.files.is_empty()
			for file in asset.files:
				valid=valid and FileAccess.file_exists("res://"+file.path) and FileAccess.get_sha256("res://"+file.path)==file.sha256
			t.check_that(valid,"environment_asset_verified_"+id)
	for kind in MapSurfaces.SCANS:
		var complete:=true
		for channel in ["diff","nor_gl","arm"]:complete=complete and ResourceLoader.exists(MapSurfaces.texture_path(kind,channel))
		t.check_that(complete,"pbr_scan_"+kind)
	t.check_that(MapCatalog.ids().size()>=2,"map_registry_lists_maps")
	for id in MapCatalog.ids_for_mode("tdm"):
		var entry:=MapCatalog.entry(id)
		var complete:=true
		for key in ["display_name","menu_subtitle","layout","seed","extent","style","lighting","capture","overview"]:complete=complete and entry.has(key)
		for shot in ["blue_spawn","red_spawn","north_route","center_interior","south_route","elevated","first_person"]:complete=complete and entry.get("capture",{}).has(shot)
		complete=complete and ResourceLoader.exists(str(entry.get("layout",""))) and load(str(entry.layout)).new() is MapLayout
		complete=complete and ResourceLoader.exists(str(entry.get("lighting",{}).get("hdri","")))
		t.check_that(complete,"map_registry_entry_"+id)
		# Radar: a square registry window that covers the playable extent, with a baked 1024 px texture.
		var radar:Dictionary=entry.get("minimap",{})
		var box:Array=radar.get("bounds",[])
		var covers:=box.size()==4 and float(box[2])-float(box[0])==float(box[3])-float(box[1])
		covers=covers and float(box[0])<=-entry.extent[0]*.5 and float(box[2])>=entry.extent[0]*.5 and float(box[1])<=-entry.extent[1]*.5 and float(box[3])>=entry.extent[1]*.5
		t.check_that(covers,"minimap_bounds_cover_extent_"+id)
		var radar_texture:=str(radar.get("texture",""))
		t.check_that(ResourceLoader.exists(radar_texture) and load(radar_texture).get_width()==1024 and load(radar_texture).get_height()==1024,"minimap_texture_"+id)
		var path:String=MapCatalog.scene_path(id)
		t.check_that(ResourceLoader.exists(path),"map_scene_"+id)
		if ResourceLoader.exists(path):
			var arena:MapArena=load(path).instantiate()
			var expected:=MapCatalog.vec2(entry.extent)
			t.check_that(arena.definition.extent==expected,"compact_footprint_"+id)
			t.check_that(arena.definition.spawns_blue[0].distance_to(arena.definition.spawns_blue[12])>=48,"multiple_deployment_clusters_"+id)
			t.check_that(arena.definition.spawns_blue.size()==16 and arena.definition.spawns_red.size()==16,"spawns_"+id)
			t.check_that(arena.definition.cover_points.size()>=36,"cover_"+id)
			t.check_that(arena.definition.ammo_caches.size()==8,"caches_"+id)
			t.check_that(arena.definition.domination.size()==3 and arena.definition.hardpoints.size()==5,"objectives_"+id)
			t.check_that(arena.nav_region.navigation_mesh.get_polygon_count()>0,"navigation_"+id)
			var textures = arena.lightmap.light_data.get("lightmap_textures") if arena.lightmap.light_data!=null else []
			t.check_that(textures is Array and not textures.is_empty(),"baked_lighting_"+id)
			t.check_that(arena.lightmap.directional and arena.lightmap.quality>=LightmapGI.BAKE_QUALITY_MEDIUM and arena.lightmap.shadowmask_mode!=LightmapGIData.SHADOWMASK_MODE_NONE,"lightmap_directional_shadowmask_"+id)
			var environment:WorldEnvironment=arena.get_node_or_null("Environment")
			var sky_ok:=environment!=null and environment.environment.sky!=null and environment.environment.sky.sky_material is PanoramaSkyMaterial and environment.environment.sky.sky_material.panorama!=null
			t.check_that(sky_ok,"hdri_sky_"+id)
			# Exposure is fixed (MapArena.EXPOSURE): nothing re-meters as the player moves.
			arena.fix_exposure()
			t.check_that(environment!=null and environment.environment.tonemap_mode==Environment.TONE_MAPPER_AGX and environment.camera_attributes is CameraAttributesPractical and not environment.camera_attributes.auto_exposure_enabled and is_equal_approx(environment.camera_attributes.exposure_multiplier,MapArena.EXPOSURE),"agx_fixed_exposure_"+id)
			t.check_that(arena.probe_volumes.size()>=4,"interior_reflection_probes_"+id)
			# Architecture renders photoscanned surfaces on metric UVs, not untextured primitives.
			var scanned:=0;var primitives:=0
			for node in arena.find_children("*","MeshInstance3D",true,false):
				var mesh_instance:=node as MeshInstance3D
				if mesh_instance.mesh is BoxMesh or mesh_instance.mesh is CylinderMesh:primitives+=1
				var mat:=mesh_instance.material_override if mesh_instance.material_override!=null else mesh_instance.get_surface_override_material(0)
				if mat is ShaderMaterial and (mat.get_shader_parameter("albedo_tex")!=null or mat.get_shader_parameter("base_albedo")!=null):scanned+=1
			t.check_that(scanned>150,"photoscanned_architecture_"+id,"scanned="+str(scanned))
			t.check_that(primitives==0,"no_primitive_visuals_"+id,"primitives="+str(primitives))
			t.check_that(arena.get_node_or_null("Terrain")!=null,"terrain_backdrop_"+id)
			# Poly Haven prop dressing: placed props, batched clutter, cover props with colliders.
			var placed:=arena.find_children("Prop_*","Node3D",true,false)
			var solid_props:=placed.filter(func(node:Node):return not node.find_children("*","StaticBody3D",false,false).is_empty())
			t.check_that(placed.size()>=20,"props_placed_"+id,"props="+str(placed.size()))
			t.check_that(solid_props.size()>=2,"cover_props_collide_"+id,"solid="+str(solid_props.size()))
			# Instanced decoration is stored as transform data and built at load (see MapArena).
			var batched:=arena.instance_batches.filter(func(batch:Array):return String(batch[0]).begins_with("Clutter_"))
			t.check_that(not batched.is_empty(),"clutter_batched_"+id)
			var valid:=not arena.instance_batches.is_empty()
			var placed_somewhere:=false
			for batch in arena.instance_batches:
				var transforms:PackedFloat32Array=batch[3]
				valid=valid and batch[1] is Mesh and not transforms.is_empty() and transforms.size()%12==0
				if not transforms.is_empty():placed_somewhere=placed_somewhere or Vector3(transforms[3],transforms[7],transforms[11])!=Vector3.ZERO
			valid=valid and placed_somewhere
			t.check_that(valid,"instance_batches_have_transforms_"+id,"batches="+str(arena.instance_batches.size()))
			# Known spawn points land inside the radar texture under the registry bounds.
			var inside:=true
			for spawn in arena.definition.spawns_blue+arena.definition.spawns_red:
				var uv:=Minimap.uv_of(box,spawn)
				inside=inside and uv.x>=0 and uv.x<=1 and uv.y>=0 and uv.y<=1
			t.check_that(inside,"minimap_spawns_inside_texture_"+id)
			# Grass and shrubs stand clear of walls, fences, props and trunks (nothing grows through a solid).
			var solids:=MapNature.Clearance.new();solids.scan(arena)
			var grass_count:=0;var buried:=0
			for batch in arena.instance_batches:
				var kind:=String(batch[0]);var is_grass:=kind.begins_with("Grass");var is_bush:=kind.begins_with("Bush")
				if not is_grass and not is_bush:continue
				var transforms:PackedFloat32Array=batch[3]
				for i in transforms.size()/12:
					var x:=transforms[i*12+3];var y:=transforms[i*12+7];var z:=transforms[i*12+11]
					if absf(x)>arena.definition.extent.x*.5 or absf(z)>arena.definition.extent.y*.5:continue
					grass_count+=1
					var reach:=.3 if is_grass else .5
					if solids.gap(x,z,[y+.05,y+.4],reach+.5)<reach:buried+=1
			t.check_that(buried==0,"vegetation_clear_of_solids_"+id,"clumps="+str(grass_count)+" buried="+str(buried))
			arena.free()

# Check the rendered/collision triangles at thresholds, not only opening bounds.
static func wall_openings(t) -> void:
	var doorway:=MapMeshes.wall(Vector3(6,4,.3),[Rect2(2,0,2,3)])
	t.check_that(not triangle_hit(doorway,Vector3(0,-1.9,0),Vector3(0,-2.1,0)),"wall_floor_doorway_has_no_coplanar_threshold")
	t.check_that(triangle_hit(doorway,Vector3(-2,-1.9,0),Vector3(-2,-2.1,0)),"wall_bottom_cap_remains_outside_doorway")
	var window:=MapMeshes.wall(Vector3(6,4,.3),[Rect2(2,1,2,2)])
	t.check_that(triangle_hit(window,Vector3(0,-.9,0),Vector3(0,-1.1,0)),"wall_elevated_window_retains_sill")

static func triangle_hit(mesh: Mesh, from: Vector3, to: Vector3) -> bool:
	var faces:=mesh.get_faces()
	for i in range(0,faces.size(),3):
		if Geometry3D.segment_intersects_triangle(from,to,faces[i],faces[i+1],faces[i+2])!=null:return true
	return false
