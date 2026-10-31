class_name MapArena
extends Node3D

@export var definition: MapDefinition
@export var nav_region: NavigationRegion3D
@export var zombie_regions: Array[NavigationRegion3D] = []
@export var lightmap: LightmapGI
# Interior reflection volumes. Probes are created at run time so the editor
# lightmap bake never renders them in its throwaway preview scenarios.
@export var probe_volumes: Array[AABB] = []
# Instanced decoration (details, clutter, trees): [name, mesh, material,
# transforms (12 floats each), gi_mode, visibility_end]. MultiMeshes are built
# here at load because maps are prepared headless, where the renderer cannot
# hold MultiMesh instance data for saving.
@export var instance_batches: Array = []
# Compact, open maps can keep their entire environment visible. Alpha range
# fades otherwise make solid props see-through as the player crosses the map.
@export var fixed_geometry_visibility := false

# Barrels, cars and glass panes found by node name at load (see Destructible).
var destructibles: Array[Destructible] = []

# Exposure is SET, like the shadows: auto exposure re-metered every view, so the whole scene
# brightened and darkened as the player walked and looked between sky, yards and interiors.
# tools/exposure_probe.gd found it settled at its brightening cap (about 1.42x) in almost every
# view on all four maps, dipping toward 0.8x only when sky filled the frame; this is that level.
const EXPOSURE := 1.42

# Row-major 3x4 layout of MultiMesh.TRANSFORM_3D buffers.
static func pack(transform: Transform3D) -> PackedFloat32Array:
	var b:=transform.basis;var o:=transform.origin
	return PackedFloat32Array([b.x.x,b.y.x,b.z.x,o.x,b.x.y,b.y.y,b.z.y,o.y,b.x.z,b.y.z,b.z.z,o.z])

func _ready() -> void:
	for batch in instance_batches:
		var transforms:PackedFloat32Array=batch[3]
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D;multi.mesh=batch[1]
		multi.instance_count=transforms.size()/12;multi.buffer=transforms
		var node:=MultiMeshInstance3D.new();node.name=batch[0];node.multimesh=multi
		node.material_override=batch[2];node.gi_mode=batch[4]
		# An optional 7th entry switches shadow casting off (grass, small clutter).
		if batch.size()>6:node.cast_shadow=batch[6]
		if batch[5]>0 and not fixed_geometry_visibility:
			node.visibility_range_end=batch[5];node.visibility_range_end_margin=batch[5]*.15
			node.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			# Shadows are SET: a range-culled batch would drop its shadows as the camera
			# moves away. A shadow-only twin, never culled, casts them at every distance.
			if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var caster:=MultiMeshInstance3D.new();caster.name=node.name+"_Shadow";caster.multimesh=multi
				caster.material_override=node.material_override;caster.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
				caster.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				add_child(caster)
		add_child(node)
	if fixed_geometry_visibility:
		for geometry:GeometryInstance3D in find_children("*","GeometryInstance3D",true,false):
			geometry.visibility_range_begin=0.0;geometry.visibility_range_end=0.0
			geometry.visibility_range_begin_margin=0.0;geometry.visibility_range_end_margin=0.0
			geometry.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for decal:Decal in find_children("*","Decal",true,false):decal.distance_fade_enabled=false
	for volume in probe_volumes:
		var probe:=ReflectionProbe.new()
		probe.position=volume.get_center();probe.size=volume.size
		probe.box_projection=true;probe.interior=true;probe.blend_distance=1.5
		probe.update_mode=ReflectionProbe.UPDATE_ONCE
		probe.ambient_mode=ReflectionProbe.AMBIENT_DISABLED
		add_child(probe)
	# Fixture lights are fully baked (direct, bounce and shadows) and reach
	# dynamic objects through the lightmap probes. Rendering them again at run
	# time only re-draws their shadow maps, which cost 5-7 ms of GPU per frame.
	for light in find_children("*","Light3D",true,false):
		if light.light_bake_mode==Light3D.BAKE_STATIC and not light is DirectionalLight3D:light.visible=false
	# Static shadows are SET: buildings, terrain and props take their sun shadows from
	# the bake (shadowmask overlaid everywhere, not only past the real-time distance), so
	# they never crawl, shimmer or hand over as the camera moves. Real-time sun shadows
	# are cast only by things that move: soldiers, weapons, debris and foliage.
	for gi in find_children("*","LightmapGI",true,false):
		(gi as LightmapGI).shadowmask_mode=LightmapGIData.SHADOWMASK_MODE_OVERLAY
	for node in find_children("*","GeometryInstance3D",true,false):
		var geometry:GeometryInstance3D=node
		if geometry.gi_mode==GeometryInstance3D.GI_MODE_STATIC:geometry.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fix_exposure()
	destructibles=Destructible.scan(self)

# Maps prepared before exposure was fixed still carry auto exposure in their saved scene.
func fix_exposure() -> void:
	for child in get_children():
		if child is WorldEnvironment and child.camera_attributes is CameraAttributesPractical:
			child.camera_attributes.auto_exposure_enabled=false;child.camera_attributes.exposure_multiplier=1.12 if definition!=null and not definition.zombies.is_empty() else EXPOSURE

func _enter_tree() -> void:
	# These maps are static. Publish their geometry synchronously before their
	# first server iteration, so loading cannot race an empty async region.
	# This also applies to the menu backdrop: changing the map's mode later in
	# MatchWorld cannot cancel an already pending backdrop iteration.
	NavigationServer3D.map_set_use_async_iterations(get_world_3d().navigation_map,false)
	for zombie_region in zombie_regions:
		NavigationServer3D.region_set_use_async_iterations(zombie_region.get_rid(),false)
	if nav_region!=null:
		if nav_region.navigation_mesh!=null:
			NavigationServer3D.map_set_cell_height(get_world_3d().navigation_map,nav_region.navigation_mesh.cell_height)
		NavigationServer3D.region_set_use_async_iterations(nav_region.get_rid(),false)

# Applies the player's graphics preset (0 low, 1 medium, 2 high) to this map's
# lighting and environment. Everything except the sun's near shadows is baked,
# so presets only scale the screen-space and volumetric passes.
func apply_quality(quality: int) -> void:
	var sun:DirectionalLight3D=get_node("Sun")
	# Real-time sun shadows cover the near field; the baked shadowmask takes over
	# beyond it, so Low and Medium keep a short two-cascade range.
	sun.directional_shadow_max_distance=[35,45,120][quality]
	sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality==2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# The sun's angular size drives a blocker-search (PCSS) penumbra. With the cheap
	# Low/Medium filter that search is a handful of noisy taps whose pattern is fixed to the
	# screen, so every shadow edge crawls whenever the camera turns (each recoil kick).
	# tools/shadow_probe.gd measured a 15 % drop in edge shimmer with a narrower sun disc;
	# High has the taps to afford the full soft penumbra. Slightly firmer biases keep
	# grazing faces (container roofs, wall tops) from flickering between lit and shadowed.
	sun.light_angular_distance=[.1,.18,.55][quality]
	sun.shadow_bias=.04;sun.shadow_normal_bias=1.4
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality==2 else RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
	RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM if quality==2 else RenderingServer.ENV_SSIL_QUALITY_LOW,quality!=2,.5,4,50,300)
	RenderingServer.environment_set_volumetric_fog_volume_size(96 if quality==2 else 64,96 if quality==2 else 64)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	for child in get_children():
		if child is WorldEnvironment:
			var env:Environment=child.environment
			# Baked lightmaps already carry occlusion and bounce light and the haze
			# stays on, so the screen-space passes, glow and volumetric fog are
			# High-only refinements. Medium holds 60 FPS on a fanless M2 under
			# sustained load.
			env.ssao_enabled=quality==2
			env.ssil_enabled=quality==2
			# Neon Circuit's emissive signage is part of its arena art at Medium.
			env.glow_enabled=quality==2 or (quality==1 and definition.id=="neon")
			env.volumetric_fog_enabled=quality==2

func closest(point: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0: return point
	return NavigationServer3D.map_get_closest_point(map, point)
