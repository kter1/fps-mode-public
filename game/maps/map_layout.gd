class_name MapLayout
extends RefCounted

# One map's authored content. CompactMapBuilder.build() loads the layout script
# named in the map's registry entry (game/maps/layouts/<id>.gd), which extends
# this class, and calls these hooks in order:
#   boundaries -> build -> deployment -> objectives -> ground_splat (per vertex),
# then, once the shared prop dressing has placed cars and barriers, dress.
# The defaults are the shared compact frame (perimeter wall, deployment
# buildings, ammo, routes and objectives), so a layout usually only overrides
# build() and ground_splat(). Style knobs (walls, ground, terrain, backdrop,
# lighting) live in the registry entry, not here.

func boundaries(b: CompactMapBuilder) -> void:
	b.boundaries()

# Buildings, cover and props inside the boundary.
func build(_b: CompactMapBuilder) -> void:
	pass

func deployment(b: CompactMapBuilder) -> void:
	b.deployment()

# Ammo caches, bot routes, domination points, hardpoints and the QA route.
func objectives(b: CompactMapBuilder) -> void:
	b.objectives()

# Final dressing pass: furniture, clutter, decals and foliage placed around the
# colliders that exist by now (b.begin_dress() collects them; b.clear() tests a spot).
func dress(_b: CompactMapBuilder) -> void:
	pass

# Splat weights (R, G, B overlays on the ground material's base layer) at a
# point of the playable ground grid.
func ground_splat(b: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var fine:=noise.get_noise_2d(x*3.3+170.0,z*3.3-40.0)
	var n:=noise.get_noise_2d(x,z)
	var edge:=minf(b.def.extent.x*.5-absf(x),b.def.extent.y*.5-absf(z))
	var apron:=1.0-smoothstep(1.5,5.5,b.footprint_distance(x,z)+n*1.8)
	return Color(smoothstep(.38,.75,fine)*.7,maxf(apron,1.0-smoothstep(2.0,5.0,edge+n*3.0)),0.0)
