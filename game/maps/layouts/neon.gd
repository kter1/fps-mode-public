extends MapLayout

# Neon Circuit: a lights-out entertainment complex.
#
# A dark laser-tag arena anchors the middle: a two-storey neon maze with a
# ramp-fed overlooks and two enclosed bypass wings. Open-air arcades under
# canopies hold the team ends, split into themed zones (cabinet pod, prize and
# claw corner, racers, dance stage, skee-ball). A food court with shopfronts
# lines the north edge and a marked parking lot with a cinema the south.
# Mirror-symmetric across X = 0.
#
# Spawns, caches, routes and objectives come from the shared compact frame;
# only build/dress/ground differ per map. All geometry is original; the glow
# comes from baked practical lights, not new assets.

const ARENA := 16.0
const WALL_T := 0.4
const WALL_H := 6.5
const DECK_H := 3.6
const DARK := Color(0.07, 0.08, 0.10)
const CONCRETE := Color(0.16, 0.17, 0.19)
const CYAN := Color(0.16, 0.88, 1.0)
const PINK := Color(1.0, 0.18, 0.84)
const AMBER := Color(1.0, 0.69, 0.18)
const LIME := Color(0.55, 1.0, 0.25)
const NeonArt = preload("res://game/maps/layouts/neon_art.gd")
var art: RefCounted


func build(b: CompactMapBuilder) -> void:
	art = NeonArt.new(b)
	# Extra clearance keeps capsule movement clear of the maze's sharp corners.
	b.arena.nav_region.navigation_mesh.agent_radius = 0.75
	b.arena.nav_region.navigation_mesh.cell_size = 0.25
	b.arena.nav_region.navigation_mesh.cell_height = 0.1
	b.arena.nav_region.navigation_mesh.agent_max_climb = 0.35
	_arena_shell(b)
	_arena_maze(b)
	_arena_decks(b)
	_arena_wings(b)
	_arcade_rows(b)
	_snack_street(b)
	_parking(b)
	_outskirts(b)
	b.road_markings()


func objectives(b: CompactMapBuilder) -> void:
	b.objectives()
	# Bot route anchors make the new flanks part of ordinary combat movement.
	for side: float in [-1.0, 1.0]:
		for x: float in [-8.0, 8.0]:
			b.def.routes.append(Vector3(x, 0, side * 20.0))
	# Keep the inspection route on the authored north catwalk.
	b.def.qa_route[3] = Vector3(-2, DECK_H, -13.6)
	b.def.qa_route[4] = Vector3(0, DECK_H, -13.6)
	b.def.qa_route[5] = Vector3(2, DECK_H, -13.6)


func _arena_shell(b: CompactMapBuilder) -> void:
	# Floor plate, four walls with door gaps, corner posts and a roof.
	b.box("ArenaFloor", Vector3(0, 0.02, 0), Vector3(ARENA * 2 + 1.0, 0.12, ARENA * 2 + 1.0), CONCRETE, false)
	var dz := 8.0
	var dw := 3.0
	for sx in [-1.0, 1.0]:
		# West/east walls (plane x = sx*ARENA), doors at z = -8, 0, 8.
		for seg in [[-ARENA, -dz - dw * 0.5], [-dz + dw * 0.5, -dw * 0.5], [dw * 0.5, dz - dw * 0.5], [dz + dw * 0.5, ARENA]]:
			var zc: float = (seg[0] + seg[1]) * 0.5
			b.box("ArenaWall", Vector3(sx * ARENA, WALL_H * 0.5, zc), Vector3(WALL_T, WALL_H, seg[1] - seg[0]), DARK)
		for door in [-dz, 0.0, dz]:
			b.box("ArenaLintel", Vector3(sx * ARENA, WALL_H - 1.0, door), Vector3(WALL_T + 0.1, 2.0, dw + 0.4), DARK)
		# North/south walls (plane z = sx*ARENA), doors at x = +/-8.
		for seg in [[-ARENA, -dz - dw * 0.5], [-dz + dw * 0.5, dz - dw * 0.5], [dz + dw * 0.5, ARENA]]:
			var xc: float = (seg[0] + seg[1]) * 0.5
			b.box("ArenaWall", Vector3(xc, WALL_H * 0.5, sx * ARENA), Vector3(seg[1] - seg[0], WALL_H, WALL_T), DARK)
		for door in [-dz, dz]:
			b.box("ArenaLintel", Vector3(door, WALL_H - 1.0, sx * ARENA), Vector3(dw + 0.4, 2.0, WALL_T + 0.1), DARK)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			b.box("ArenaPost", Vector3(cx * ARENA, WALL_H * 0.5, cz * ARENA), Vector3(0.9, WALL_H, 0.9), CONCRETE)
	b.box("ArenaRoof", Vector3(0, WALL_H + 0.25, 0), Vector3(ARENA * 2 + 1.2, 0.5, ARENA * 2 + 1.2), DARK, false)
	b.arena.probe_volumes.append(AABB(Vector3(-15.5, 0, -15.5), Vector3(31, WALL_H, 31)))
	# Neon roofline and the big signs.
	for sx in [-1.0, 1.0]:
		b.detail(Vector3(0, WALL_H - 0.15, sx * (ARENA + 0.25)), Vector3(ARENA * 2 + 0.6, 0.12, 0.12), PINK)
		b.detail(Vector3(sx * (ARENA + 0.25), WALL_H - 0.15, 0), Vector3(0.12, 0.12, ARENA * 2 + 0.6), CYAN)
	# Self-lit lettering: the practicals are baked, so lit labels would read black.
	art.text("NEON CIRCUIT", Vector3(0, WALL_H - 1.2, ARENA + 0.24), Vector3.BACK, CYAN, 0.012)
	art.text("LASER TAG", Vector3(0, WALL_H - 1.2, -ARENA - 0.24), Vector3.FORWARD, PINK, 0.009)
	art.text("HOUSE RULES  /  TAGGERS UP, PHONES DOWN", Vector3(0, 3.0, -ARENA - 0.24), Vector3.FORWARD, PINK, 0.0035)
	art.text("NO CLIMBING THE MAZE WALLS", Vector3(0, 3.0, ARENA + 0.24), Vector3.BACK, CYAN, 0.0035)
	# Exit boards on the north/south door heads, clear of the openings below.
	for sz in [-1.0, 1.0]:
		for x in [-dz, dz]:
			_sign_board(b, Vector3(x, 4.95, sz * (ARENA - 0.28)), Vector3(0, 0, -sz), Vector2(1.0, 0.36), "EXIT", Color("4fd08a"), 0.0026)


func _maze_wall(b: CompactMapBuilder, center: Vector3, size: Vector3, neon: Color) -> void:
	b.box("MazeWall", center, size, DARK)
	b.detail(center + Vector3(0, size.y * 0.5 + 0.035, 0), Vector3(size.x + 0.08, 0.07, size.z + 0.08), neon)
	art.maze(center,size,neon)


func _arena_maze(b: CompactMapBuilder) -> void:
	# Staggered maze walls with neon caps. The z = 0 corridor stays open so the
	# shared east-west route passes through the arena and around the reactor.
	var h := 2.6
	var cols := [CYAN, PINK, LIME, AMBER]
	var i := 0
	for sx in [-1.0, 1.0]:
		for seg in [[-12.0, -4.0], [4.0, 12.0]]:
			_maze_wall(b, Vector3(sx * 5.5, h * 0.5, (seg[0] + seg[1]) * 0.5), Vector3(0.35, h, seg[1] - seg[0]), cols[i % 4])
			i += 1
		for seg in [[-12.0, -4.0], [4.0, 12.0]]:
			_maze_wall(b, Vector3(sx * 11.0, h * 0.5, (seg[0] + seg[1]) * 0.5), Vector3(0.35, h, seg[1] - seg[0]), cols[i % 4])
			i += 1
	for sz in [-1.0, 1.0]:
		for seg in [[-14.0, -7.0], [7.0, 14.0]]:
			_maze_wall(b, Vector3((seg[0] + seg[1]) * 0.5, h * 0.5, sz * 11.0), Vector3(seg[1] - seg[0], h, 0.35), cols[i % 4])
			i += 1
	# Reactor core on the centre plaza; the domination anchor stays walkable around it.
	b.box("Reactor", Vector3(0, 0.55, 0), Vector3(2.4, 1.1, 2.4), CONCRETE)
	b.detail(Vector3(0, 1.16, 0), Vector3(2.0, 0.12, 2.0), PINK)
	b.bake_light(Vector3(0, 3.6, 0), Color(1.0, 0.25, 0.85), 3.0, 14.0)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			b.box("ReactorPillar", Vector3(cx * 2.6, 0.8, cz * 2.6), Vector3(0.35, 1.6, 0.35), DARK)
			b.detail(Vector3(cx * 2.6, 1.64, cz * 2.6), Vector3(0.43, 0.08, 0.43), CYAN)
	# Neon wash over the maze.
	for lx in [-8.0, 0.0, 8.0]:
		for lz in [-8.0, 8.0]:
			var col: Color = CYAN if lx < 0 else PINK
			b.bake_light(Vector3(lx, 4.6, lz), col, 2.0, 10.0)
	# Staggered cover pairs through the lanes.
	for sx in [-1.0, 1.0]:
		b.cover(Vector3(sx * 8.2, 0, -7.0), 2.4, b.accent)
		b.cover(Vector3(sx * 2.8, 0, 7.0), 2.4, b.accent)


func _arena_decks(b: CompactMapBuilder) -> void:
	# One overlook deck per side, each fed by a ramp at both ends so either
	# team can climb from their half.
	for sz in [-1.0, 1.0]:
		var z: float = sz * 13.6
		b.box("Catwalk", Vector3(0, DECK_H - 0.125, z), Vector3(6, 0.25, 3.6), CONCRETE)
		for rx in [-1.0, 1.0]:
			b.ramp(Vector3(rx * 13.0, 0, z), Vector3(rx * 3.0, DECK_H, z), 3.2)
		b.railing_path([Vector3(-3, DECK_H, z - sz * 1.8), Vector3(3, DECK_H, z - sz * 1.8)], 1.05, Color("2a3033"))
		for cx in [-2.0, 0.0, 2.0]:
			b.box("DeckPost", Vector3(cx, (DECK_H - 0.25) * 0.5, z), Vector3(0.3, DECK_H - 0.25, 0.3), DARK)
		b.bake_light(Vector3(0, DECK_H + 1.6, z), CYAN if sz < 0 else PINK, 1.6, 12.0)


func _arena_wings(b: CompactMapBuilder) -> void:
	# Two annexes turn the old exterior doors into internal route junctions.
	# Three-metre exits and two lanes around each island preserve cross traffic.
	for side: float in [-1.0, 1.0]:
		var z := side * 20.0
		var color := CYAN if side < 0 else PINK
		b.box("AnnexFloor", Vector3(0, 0.02, z), Vector3(36.4, 0.12, 8.0), CONCRETE, false)
		b.box("AnnexRoof", Vector3(0, WALL_H + 0.25, z), Vector3(36.8, 0.5, 8.4), DARK, false)
		for xside: float in [-1.0, 1.0]:
			for offset: float in [-2.75, 2.75]:
				b.box("AnnexSideWall", Vector3(xside * 18.0, WALL_H * 0.5, z + offset), Vector3(WALL_T, WALL_H, 2.5), DARK)
			b.box("AnnexSideLintel", Vector3(xside * 18.0, 5.5, z), Vector3(WALL_T, 2.0, 3.0), DARK)
			for edge: float in [-1.0, 1.0]:
				art.strip(Vector3(xside * 18.23, 2.0, z + edge * 1.5), Vector3(0.08, 4.0, 0.08), color)
		for segment in [[-18.0, -9.5], [-6.5, 6.5], [9.5, 18.0]]:
			b.box("AnnexOuterWall", Vector3((segment[0] + segment[1]) * 0.5, WALL_H * 0.5, side * 24.0), Vector3(segment[1] - segment[0], WALL_H, WALL_T), DARK)
		for x: float in [-8.0, 8.0]:
			b.box("AnnexExitLintel", Vector3(x, 5.5, side * 24.0), Vector3(3.0, 2.0, WALL_T), DARK)
			# Boards hang on the lintel faces, above the 4.5 m opening.
			_sign_board(b, Vector3(x, 5.0, side * 23.77), Vector3(0, 0, -side), Vector2(3.2, 0.45), "EXIT  /  FOOD COURT" if side < 0 else "EXIT  /  PARKING", color, 0.0026)
			_sign_board(b, Vector3(x, 5.0, side * 24.23), Vector3(0, 0, side), Vector2(3.2, 0.45), "LASER TAG  /  ENTRANCE", color, 0.0026)
		for x: float in [-12.5, 0.0, 12.5]:
			_maze_wall(b, Vector3(x, 1.3, z), Vector3(4.0, 2.6, 0.35), color)
			b.bake_light(Vector3(x, 4.8, z), color, 1.6, 9.0)
		art.panel(Vector3(0, 0.085, z), Vector2(35.5, 7.5), Vector3.UP, color, 2, Vector2(25, 6))
		art.strip(Vector3(0, 6.2, side * 24.24), Vector3(36.4, 0.1, 0.1), color)
		art.text("03 / ION BYPASS" if side < 0 else "04 / PHOTON GALLERY", Vector3(0, 4.8, side * 23.76), Vector3(0, 0, -side), color, 0.007)
		b.arena.probe_volumes.append(AABB(Vector3(-17.5, 0, z - 3.5), Vector3(35, WALL_H, 7)))


func _sign_board(b: CompactMapBuilder, center: Vector3, normal: Vector3, size: Vector2, title: String, color: Color, scale := 0.004) -> void:
	# A dark backing board with neon edges and self-lit lettering.
	var across_z := absf(normal.x) > 0.5
	b.box("SignBoard", center, Vector3(0.06, size.y, size.x) if across_z else Vector3(size.x, size.y, 0.06), Color("0b0c14"), false)
	for edge: float in [-1.0, 1.0]:
		var bar := Vector3(0.02, 0.035, size.x - 0.04) if across_z else Vector3(size.x - 0.04, 0.035, 0.02)
		art.strip(center + normal * 0.04 + Vector3.UP * edge * (size.y * 0.5 - 0.03), bar, color)
	art.text(title, center + normal * 0.05, normal, color, scale)


func _arcade_rows(b: CompactMapBuilder) -> void:
	# Open-air arcades on the team ends. Arcade-local u runs from the spawn
	# side (-7) toward the arena (+7); z = 0 stays a clear lane past the cover.
	for sx in [-1.0, 1.0]:
		var cx: float = sx * 30.0
		var face: float = -sx
		var color: Color = CYAN if sx < 0 else PINK
		b.arena.probe_volumes.append(AABB(Vector3(cx - 6.5, 0, -10.5), Vector3(13, 4, 21)))
		_arcade_canopy(b, cx, face, sx, color)
		_arcade_north(b, cx, face, color)
		_arcade_south(b, cx, face, color)
		b.cover(Vector3(cx, 0, 0), 3.0, b.accent)


func _arcade_canopy(b: CompactMapBuilder, cx: float, face: float, sx: float, color: Color) -> void:
	for ox in [-6.0, 6.0]:
		for oz in [-9.0, 9.0]:
			b.box("CanopyPost", Vector3(cx + ox, 2.0, oz), Vector3(0.35, 4.0, 0.35), DARK)
			art.strip(Vector3(cx + ox, 2.0, oz - signf(oz) * 0.19), Vector3(0.06, 3.6, 0.02), color)
	b.box("Canopy", Vector3(cx, 4.1, 0), Vector3(14, 0.3, 22), DARK, false)
	# Fascia boards on all four edges carry the signage; inner faces greet players.
	for sz in [-1.0, 1.0]:
		b.box("ArcadeFascia", Vector3(cx, 3.5, sz * 11.0), Vector3(14.2, 0.9, 0.14), Color("0b0c14"), false)
		for y in [3.08, 3.92]:
			art.strip(Vector3(cx, y, sz * 11.08), Vector3(14.2, 0.04, 0.02), color)
		art.text("NEON ARCADE", Vector3(cx, 3.5, sz * 11.09), Vector3(0, 0, sz), color, 0.0055)
		art.text("INSERT COIN" if sz < 0 else "HIGH SCORE", Vector3(cx, 3.5, sz * 10.91), Vector3(0, 0, -sz), AMBER, 0.0045)
	for su in [-1.0, 1.0]:
		var x: float = cx + face * su * 7.0
		var out := Vector3(face * su, 0, 0)
		b.box("ArcadeFascia", Vector3(x, 3.5, 0), Vector3(0.14, 0.9, 21.86), Color("0b0c14"), false)
		for y in [3.08, 3.92]:
			art.strip(Vector3(x, y, 0) + out * 0.08, Vector3(0.02, 0.04, 21.86), color)
		var title := "ARCADE  /  PLAY BEYOND" if su > 0 else ("PLAYER 1 START" if sx < 0 else "PLAYER 2 START")
		art.text(title, Vector3(x, 3.5, 0) + out * 0.09, out, color, 0.0055)
	# Underside light bars.
	for i in 5:
		art.strip(Vector3(cx, 3.93, -8.0 + i * 4.0), Vector3(13.0, 0.03, 0.06), Color("8250ff"))


func _ap(cx: float, face: float, u: float, y: float, z: float) -> Vector3:
	return Vector3(cx + face * u, y, z)


func _arcade_north(b: CompactMapBuilder, cx: float, face: float, color: Color) -> void:
	# Cabinet pod: five cabinets on an arc, all facing a shared focus by the lane.
	var screens := [CYAN, PINK, AMBER, Color("8250ff"), LIME]
	var focus := _ap(cx, face, 3.0, 0, -1.0)
	for i in 5:
		var theta := deg_to_rad(-50.0 + i * 25.0)
		var spot := _ap(cx, face, 3.0 + 3.4 * sin(theta), 0, -1.0 - 3.4 * cos(theta))
		var toward := focus - spot
		art.cabinet(spot, atan2(toward.x, toward.z), screens[i], i)
	b.bake_light(_ap(cx, face, 3.0, 2.9, -4.0), color.lightened(0.3), 1.8, 8.0)
	# Prize corner: L counter, stocked shelf and a hanging board.
	b.box("PrizeCounter", _ap(cx, face, -5.35, 0.55, -8.0), Vector3(2.3, 1.1, 0.6), CONCRETE)
	b.box("PrizeCounter", _ap(cx, face, -4.5, 0.55, -9.4), Vector3(0.6, 1.1, 2.2), CONCRETE)
	art.strip(_ap(cx, face, -5.35, 1.08, -7.69), Vector3(2.3, 0.04, 0.02), AMBER)
	for i in 4:
		b.detail(_ap(cx, face, -6.2 + i * 0.5, 1.22, -8.0), Vector3(0.26, 0.24, 0.26), [PINK, CYAN, AMBER, LIME][i].darkened(0.2))
	b.shelf_unit(_ap(cx, face, -5.6, 0, -10.45), 0.0, 1.5, 2.2, 0.5, Color("3a2a4a"))
	_sign_board(b, _ap(cx, face, -5.35, 2.85, -8.0), Vector3.BACK, Vector2(2.4, 0.55), "PRIZE ZONE", AMBER, 0.0035)
	for du in [-1.0, 1.0]:
		art.line(_ap(cx, face, -5.35 + du * 1.0, 3.12, -8.0), _ap(cx, face, -5.35 + du * 1.0, 3.95, -8.0), Color("15151d"), 0.015)
	b.bake_light(_ap(cx, face, -5.0, 2.8, -9.0), Color(1.0, 0.75, 0.45), 2.0, 8.0)
	# Claw machines and a token changer along the back edge.
	for i in 3:
		_claw(b, _ap(cx, face, 1.0 + i * 1.3, 0, -9.7), [PINK, CYAN, LIME][i])
	b.box("TokenChanger", _ap(cx, face, 5.0, 0.9, -9.8), Vector3(0.8, 1.8, 0.6), DARK)
	art.strip(_ap(cx, face, 5.0, 1.72, -9.49), Vector3(0.7, 0.05, 0.02), AMBER)
	art.text("TOKENS\n4 FOR $5", _ap(cx, face, 5.0, 1.35, -9.48), Vector3.BACK, AMBER, 0.0016)
	b.bake_light(_ap(cx, face, 2.3, 2.9, -9.0), color, 1.4, 7.0)
	# Air hockey: low cover with a glowing rink.
	var rink := _ap(cx, face, -4.5, 0, -4.5)
	b.box("AirHockey", rink + Vector3(0, 0.4, 0), Vector3(2.2, 0.8, 1.2), Color("181a2e"))
	art.panel(rink + Vector3(0, 0.805, 0), Vector2(2.0, 1.0), Vector3.UP, CYAN, 2, Vector2(2, 1))
	for edge in [-1.0, 1.0]:
		art.strip(rink + Vector3(0, 0.83, edge * 0.56), Vector3(2.1, 0.04, 0.04), PINK)
		art.strip(rink + Vector3(edge * 1.06, 0.83, 0), Vector3(0.04, 0.04, 1.1), PINK)
		art.strip(rink + Vector3(edge * 0.7, 0.84, 0), Vector3(0.1, 0.03, 0.1), AMBER)
	art.strip(rink + Vector3(0, 0.81, 0), Vector3(0.02, 0.01, 1.0), CYAN)
	art.text("AIR HOCKEY", rink + Vector3(0, 0.45, 0.61), Vector3.BACK, CYAN, 0.0018)


func _claw(b: CompactMapBuilder, base: Vector3, color: Color) -> void:
	# Glass-cased crane game: solid cabinet, clear case with prizes, lit header.
	b.box("ClawBase", base + Vector3(0, 0.45, 0), Vector3(1.0, 0.9, 1.0), DARK)
	var glass := b.box("WindowGlass", base + Vector3(0, 1.42, 0), Vector3(0.96, 1.04, 0.96), DARK)
	glass.get_child(0).material_override = b.glass_material()
	b.box("ClawHeader", base + Vector3(0, 2.1, 0), Vector3(1.0, 0.36, 1.0), DARK, false)
	art.strip(base + Vector3(0, 2.1, 0.505), Vector3(0.9, 0.22, 0.02), color)
	art.text("CLAW", base + Vector3(0, 2.1, 0.52), Vector3.BACK, Color("111022"), 0.0018)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			art.strip(base + Vector3(cx * 0.48, 1.42, cz * 0.48), Vector3(0.03, 1.04, 0.03), color)
	for i in 6:
		var spot := Vector3(-0.3 + (i % 3) * 0.3, 0.98 + floorf(i / 3.0) * 0.12, -0.15 + floorf(i / 3.0) * 0.25)
		b.detail(base + spot, Vector3(0.2, 0.16, 0.2), [PINK, CYAN, AMBER, LIME][i % 4].darkened(0.25))
	art.line(base + Vector3(0, 1.9, 0), base + Vector3(0, 1.6, 0), Color("c8c8d0"), 0.012)
	for i in 3:
		var a := TAU * i / 3.0
		art.line(base + Vector3(0, 1.6, 0), base + Vector3(cos(a) * 0.08, 1.48, sin(a) * 0.08), Color("c8c8d0"), 0.012)


func _arcade_south(b: CompactMapBuilder, cx: float, face: float, color: Color) -> void:
	# Sit-down racers: seat, wheel and big display, facing away from the lane.
	var names := ["TURBO", "NITRO", "DRIFT"]
	for i in 3:
		var u := 1.5 + i * 1.6
		var tint: Color = [CYAN, PINK, AMBER][i]
		b.box("RacerPlate", _ap(cx, face, u, 0.04, 4.6), Vector3(1.2, 0.08, 2.8), Color("15122a"), false)
		b.box("RacerSeat", _ap(cx, face, u, 0.35, 3.6), Vector3(0.6, 0.7, 0.7), Color("1a1a2e"))
		b.box("RacerSeatBack", _ap(cx, face, u, 1.0, 3.25), Vector3(0.6, 0.8, 0.14), Color("1a1a2e"), false)
		b.box("RacerCab", _ap(cx, face, u, 1.0, 5.6), Vector3(1.1, 2.0, 0.9), Color("0d0e1c"))
		art.panel(_ap(cx, face, u, 1.35, 5.14), Vector2(0.9, 0.6), Vector3.FORWARD, tint, 1)
		art.panel(_ap(cx, face, u, 1.0, 6.06), Vector2(1.0, 1.8), Vector3.BACK, tint, 0, Vector2(1, 2))
		art.ring(_ap(cx, face, u, 1.0, 4.75), 0.17, tint, true)
		art.line(_ap(cx, face, u, 0.85, 5.15), _ap(cx, face, u, 1.0, 4.77), Color("2a2a3a"), 0.03)
		art.strip(_ap(cx, face, u, 2.05, 5.13), Vector3(1.0, 0.2, 0.03), tint)
		art.text(names[i], _ap(cx, face, u, 2.05, 5.11), Vector3.FORWARD, Color("111022"), 0.0016)
	b.bake_light(_ap(cx, face, 3.1, 2.9, 4.6), color, 1.6, 8.0)
	# Dance stage: lit floor pads in front of a speaker tower.
	b.box("DanceTower", _ap(cx, face, -4.5, 1.3, 6.3), Vector3(3.0, 2.6, 0.6), Color("0d0e1c"))
	art.panel(_ap(cx, face, -4.5, 1.6, 5.99), Vector2(1.5, 1.0), Vector3.FORWARD, PINK, 1)
	for du in [-1.0, 1.0]:
		art.ring(_ap(cx, face, -4.5 + du * 1.15, 1.0, 5.98), 0.28, CYAN, true)
		art.ring(_ap(cx, face, -4.5 + du * 1.15, 1.0, 5.98), 0.12, CYAN, true)
	art.strip(_ap(cx, face, -4.5, 2.45, 5.98), Vector3(2.8, 0.22, 0.03), Color("8250ff"))
	art.text("DANCE GRID", _ap(cx, face, -4.5, 2.45, 5.96), Vector3.FORWARD, Color("111022"), 0.0022)
	b.box("DanceStage", _ap(cx, face, -4.5, 0.05, 4.4), Vector3(2.6, 0.1, 2.4), Color("15122a"), false)
	for i in 3:
		for j in 3:
			var pad: Color = [PINK, CYAN, LIME][(i + j) % 3]
			art.strip(_ap(cx, face, -4.5 + (i - 1) * 0.8, 0.105, 4.4 + (j - 1) * 0.75), Vector3(0.66, 0.01, 0.62), pad.darkened(0.35))
	b.bake_light(_ap(cx, face, -4.5, 2.9, 4.4), Color(0.8, 0.35, 1.0), 1.6, 8.0)
	# Skee-ball lanes along the back edge, rolled toward the arena side.
	for z in [9.0, 10.1]:
		b.box("SkeeLane", _ap(cx, face, 2.4, 0.45, z), Vector3(3.2, 0.9, 0.8), Color("2a1838"))
		b.box("SkeeBack", _ap(cx, face, 4.15, 1.2, z), Vector3(0.3, 2.4, 0.8), DARK)
		for edge in [-1.0, 1.0]:
			art.strip(_ap(cx, face, 2.4, 0.92, z + edge * 0.37), Vector3(3.2, 0.03, 0.03), AMBER)
		art.panel(_ap(cx, face, 3.99, 1.3, z), Vector2(0.7, 0.7), Vector3(-face, 0, 0), color, 3)
		art.strip(_ap(cx, face, 3.99, 2.2, z), Vector3(0.02, 0.18, 0.7), AMBER)
		art.text("SKEE-BALL", _ap(cx, face, 3.98, 2.2, z), Vector3(-face, 0, 0), Color("111022"), 0.0012)
	b.bake_light(_ap(cx, face, 2.4, 2.9, 9.6), Color(1.0, 0.75, 0.45), 1.4, 7.0)


func _snack_street(b: CompactMapBuilder) -> void:
	# Open-front shops with recessed service bays and distinct equipment.
	var names := ["NOODLE LAB", "TACO BYTE", "FIZZY FUEL"]
	var spots := [10.0, 22.0, 34.0]
	for sx in [-1.0, 1.0]:
		for i in 3:
			var x: float = sx * spots[i]
			var z := -32.0
			var color: Color = [CYAN, PINK, AMBER][i]
			b.box("VendorPlinth", Vector3(x, 0.12, z), Vector3(5.2, 0.24, 3.8), DARK)
			b.box("VendorBack", Vector3(x, 1.65, z - 1.65), Vector3(5.0, 3.3, 0.2), CONCRETE)
			for edge: float in [-1.0, 1.0]:
				b.box("VendorSide", Vector3(x + edge * 2.4, 1.65, z), Vector3(0.2, 3.3, 3.4), DARK)
				b.box("VendorAwningPost", Vector3(x + edge * 2.4, 1.6, z + 2.4), Vector3(0.12, 3.2, 0.12), DARK)
			b.box("VendorCounter", Vector3(x, 0.6, z + 1.4), Vector3(4.7, 1.2, 0.6), CONCRETE)
			b.box("VendorWorktop", Vector3(x, 1.23, z + 1.4), Vector3(4.9, 0.12, 0.85), Color("697681"))
			b.box("VendorFascia", Vector3(x, 3.1, z + 1.6), Vector3(5.2, 0.65, 0.24), DARK)
			b.box("VendorAwning", Vector3(x, 3.5, z + 0.5), Vector3(5.4, 0.18, 4.4), color.darkened(0.65), false)
			art.strip(Vector3(x, 2.76, z + 1.75), Vector3(5.0, 0.06, 0.06), color)
			art.text(names[i], Vector3(x, 3.12, z + 1.74), Vector3.BACK, color, 0.0035)
			b.box("VendorMenu", Vector3(x - 1.3, 2.1, z - 1.52), Vector3(1.6, 1.0, 0.08), DARK, false)
			# Two aligned columns: proportional type cannot line prices up with spaces.
			art.text(["RAMEN\nMISO\nBOWL", "TACOS\nNACHOS\nSALSA", "SODA\nFLOAT\nICE"][i], Vector3(x - 1.62, 2.1, z - 1.46), Vector3.BACK, Color.WHITE, 0.0018, HORIZONTAL_ALIGNMENT_LEFT)
			art.text(["08\n06\n09", "06\n08\n02", "03\n05\n02"][i], Vector3(x - 0.82, 2.1, z - 1.46), Vector3.BACK, color, 0.0018, HORIZONTAL_ALIGNMENT_RIGHT)
			b.box("VendorRegister", Vector3(x + 1.65, 1.45, z + 1.3), Vector3(0.45, 0.32, 0.4), DARK, false)
			art.strip(Vector3(x + 1.65, 1.51, z + 1.51), Vector3(0.31, 0.16, 0.02), CYAN)
			b.box("VendorPrepCounter", Vector3(x + 0.65, 0.75, z - 0.9), Vector3(2.5, 1.35, 0.8), Color("46505b"))
			for item in 3:
				var px := x + 0.2 + item * 0.45
				b.box("VendorEquipment", Vector3(px, 1.75 if i == 2 else 1.55, z - 0.9), Vector3(0.3, 0.65 if i == 2 else 0.25, 0.4), color.darkened(0.3), false)
			b.bake_light(Vector3(x, 2.6, z + 0.4), Color(1.0, 0.78, 0.5), 2.0, 8.0)

		for tx in [16.0, 28.0]:
			var x: float = sx * tx
			b.box("PicnicTop", Vector3(x, 0.78, -29.0), Vector3(2.2, 0.1, 1.0), Color(0.35, 0.25, 0.16))
			b.bench(Vector3(x, 0, -29.9), 0.0, 2.2)
			b.bench(Vector3(x, 0, -28.1), PI, 2.2)
		b.cone(Vector3(sx * 40.0, 0, -30.0))
		b.pallet(Vector3(sx * 38.0, 0, -34.5), 0.3, 2)
		# Umbrellas over the picnic tables.
		for tx in [16.0, 28.0]:
			var top := Vector3(sx * tx, 2.45, -29.0)
			b.pipe(Vector3(sx * tx, 0.83, -29.0), top, 0.035, DARK)
			for k in 4:
				b.detail(top, Vector3(2.5, 0.05, 1.04), (PINK if tx < 20.0 else CYAN).darkened(0.45), "steel", Vector3(0, PI * 0.25 * k, 0))
		# Dumpsters behind the stalls, on the outboard side of each service bay.
		for i in 3:
			var spot := Vector3(sx * (spots[i] + 1.2), 0, -35.7)
			b.box("Dumpster", spot + Vector3(0, 0.6, 0), Vector3(1.8, 1.2, 1.1), Color("2f4a3a"))
			b.detail(spot + Vector3(0, 1.24, 0), Vector3(1.86, 0.08, 1.16), Color("26382d"))
			for edge in [-1.0, 1.0]:
				b.detail(spot + Vector3(edge * 0.94, 0.75, 0), Vector3(0.06, 0.12, 1.0), Color("1d1f22"))
	# String lights on posts along the stall fronts.
	var posts := [-40.0, -28.0, -16.0, -4.0, 4.0, 16.0, 28.0, 40.0]
	for x: float in posts:
		b.pipe(Vector3(x, 0, -27.0), Vector3(x, 3.9, -27.0), 0.06, DARK)
		b.collider(Vector3(x, 1.95, -27.0), Vector3(0.16, 3.9, 0.16))
	for i in posts.size() - 1:
		_string_lights(Vector3(posts[i], 3.75, -27.0), Vector3(posts[i + 1], 3.75, -27.0), 0.9)


func _string_lights(from: Vector3, to: Vector3, sag: float) -> void:
	# A drooping wire with warm, pink and cyan bulbs every metre or so.
	var steps := maxi(4, int(from.distance_to(to)))
	var previous := from
	for k in range(1, steps + 1):
		var f := float(k) / steps
		var point := from.lerp(to, f) + Vector3.DOWN * sag * 4.0 * f * (1.0 - f)
		art.line(previous, point, Color("101014"), 0.01)
		art.strip(point + Vector3.DOWN * 0.06, Vector3(0.07, 0.09, 0.07), [AMBER, PINK, CYAN][k % 3])
		previous = point


func _parking(b: CompactMapBuilder) -> void:
	# South lot: marked bays with nose-in cars, lit lamp islands, a pay booth
	# and EV chargers in the corners.
	var paints := [Color("3d4650"), Color("7a1b22"), Color("1f3352"), Color("c7c9cc"), Color("2c2f33"), Color("4a5d3a"), Color("8a6a1c")]
	for sx in [-1.0, 1.0]:
		for k in 12:
			b.detail(Vector3(sx * (8.0 + k * 2.8), 0.018, 38.5), Vector3(0.1, 0.022, 5.0), Color("d9d6c8"), "concrete")
		b.detail(Vector3(sx * 23.4, 0.018, 41.3), Vector3(30.8, 0.022, 0.12), Color("c9b577"), "concrete")
		# Bays beside the cover posts stay empty so their stand-and-peek spots stay open.
		var bays := [0, 3, 6, 9, 10]
		for n in bays.size():
			var k: int = bays[n]
			_car(b, Vector3(sx * (9.4 + k * 2.8), 0, 38.5), PI if n % 3 == 1 else 0.0, paints[(n + (2 if sx > 0 else 0)) % paints.size()])
		for i in 3:
			b.cover(Vector3(sx * (14.0 + i * 8.0), 0, 35.2), 2.6, b.accent)
		for lx in [10.0, 34.0]:
			var x: float = sx * lx
			b.box("LampBase", Vector3(x, 0.3, 33), Vector3(0.6, 0.6, 0.6), CONCRETE)
			b.pipe(Vector3(x, 0.6, 33), Vector3(x, 5.6, 33), 0.09, DARK)
			b.detail(Vector3(x, 5.55, 33), Vector3(0.5, 0.18, 0.5), CONCRETE)
			art.strip(Vector3(x, 5.44, 33), Vector3(0.36, 0.03, 0.36), Color(0.82, 0.9, 1.0) * 0.6)
			b.bake_light(Vector3(x, 5.2, 33), Color(0.82, 0.9, 1.0), 3.0, 17.0)
		for bx in [6.0, 44.0]:
			b.box("Barrier", Vector3(sx * bx, 0.4, 28.5), Vector3(2.0, 0.8, 0.45), CONCRETE)
		# Pay booth by the lot entrance.
		var booth := Vector3(sx * 41.5, 0, 31.0)
		b.box("TicketBooth", booth + Vector3(0, 1.3, 0), Vector3(1.8, 2.6, 1.8), Color("2a2f3a"))
		b.box("TicketBoothRoof", booth + Vector3(0, 2.7, 0), Vector3(2.3, 0.2, 2.3), DARK, false)
		var window := b.box("WindowGlass", booth + Vector3(-sx * 0.91, 1.55, 0), Vector3(0.04, 0.9, 1.3), DARK, false)
		window.get_child(0).material_override = b.glass_material()
		art.strip(booth + Vector3(0, 2.58, 0), Vector3(2.32, 0.04, 2.32), LIME)
		_sign_board(b, booth + Vector3(0, 2.25, -0.93), Vector3.FORWARD, Vector2(1.6, 0.4), "PAY HERE", LIME, 0.0028)
		b.bake_light(booth + Vector3(-sx * 1.6, 2.4, 0), Color(0.75, 1.0, 0.6), 1.2, 7.0)
		# EV charging island (counts as cover) with a car on charge.
		var ev := Vector3(sx * 46.0, 0, 36.0)
		b.cover(ev, 3.0, LIME)
		for dx in [-0.9, 0.9]:
			b.box("Charger", ev + Vector3(dx, 1.95, 0), Vector3(0.35, 1.3, 0.3), Color("dde3e6"), false)
			art.strip(ev + Vector3(dx, 2.3, -0.16), Vector3(0.2, 0.08, 0.02), LIME)
			art.strip(ev + Vector3(dx, 2.3, 0.16), Vector3(0.2, 0.08, 0.02), LIME)
		art.text("EV CHARGE", ev + Vector3(0, 0.85, -0.62), Vector3.FORWARD, LIME, 0.0022)
		_car(b, ev + Vector3(0, 0, 4.0), PI * 0.5, paints[3 if sx < 0 else 1])
		b.floor_decals("AsphaltDamage001", 4, Rect2(sx * 8.0, 28.0, 36.0, 14.0), Vector2(3.0, 3.0), Color(0.7, 0.7, 0.68, 0.8))


func _car(b: CompactMapBuilder, base: Vector3, yaw: float, paint: Color) -> void:
	# A hatchback built along local Z: body, glasshouse, roof, wheels and lamps.
	var t := Transform3D(Basis(Vector3.UP, yaw), base)
	var turn := Vector3(0, yaw, 0)
	var body := b.box("CarBody", t * Vector3(0, 0.58, 0), Vector3(1.86, 0.72, 4.3), paint)
	body.rotation = turn
	var cabin := b.box("CarCabin", t * Vector3(0, 1.2, -0.25), Vector3(1.64, 0.52, 2.3), Color("0e1418"), false)
	cabin.rotation = turn
	var roof := b.box("CarRoof", t * Vector3(0, 1.48, -0.3), Vector3(1.56, 0.06, 1.9), paint, false)
	roof.rotation = turn
	for side in [-1.0, 1.0]:
		for end in [-1.32, 1.32]:
			var wheel := b.cylinder(t * Vector3(side * 0.86, 0.33, end), 0.33, 0.24, Color("141618"))
			wheel.rotation = Vector3(0, yaw, PI * 0.5)
		art.strip(t * Vector3(side * 0.62, 0.72, 2.16), Vector3(0.36, 0.1, 0.02), Color(0.55, 0.55, 0.5), turn)
		art.strip(t * Vector3(side * 0.66, 0.76, -2.16), Vector3(0.3, 0.09, 0.02), Color(0.45, 0.02, 0.04), turn)
	b.detail(t * Vector3(0, 0.36, 2.17), Vector3(1.7, 0.16, 0.06), Color("1d1f22"), "steel", turn)
	b.detail(t * Vector3(0, 0.36, -2.17), Vector3(1.7, 0.16, 0.06), Color("1d1f22"), "steel", turn)


func _storefront(b: CompactMapBuilder, x: float, sz: float, width: float, title: String, color: Color, shutter: bool) -> void:
	# A shallow shopfront against the boundary wall: shutter or lit display
	# window, a door, a neon fascia and a practical light.
	var n := -sz
	var front := sz * 44.75 + n * 0.4
	b.box("StoreFront", Vector3(x, 2.2, sz * 44.75 + n * 0.2), Vector3(width, 4.4, 0.4), Color("1a1c26"))
	b.box("StoreFascia", Vector3(x, 3.55, front + n * 0.07), Vector3(width - 0.4, 0.9, 0.14), Color("0b0c14"), false)
	for y in [3.08, 4.02]:
		art.strip(Vector3(x, y, front + n * 0.15), Vector3(width - 0.4, 0.04, 0.02), color)
	art.text(title, Vector3(x, 3.55, front + n * 0.15), Vector3(0, 0, n), color, 0.0045)
	var opening := width * 0.55
	if shutter:
		b.box("Cladding", Vector3(x - width * 0.12, 1.4, front + n * 0.03), Vector3(opening, 2.8, 0.06), Color("8b9196"), false)
		art.strip(Vector3(x - width * 0.12, 2.86, front + n * 0.07), Vector3(opening + 0.2, 0.08, 0.04), AMBER)
	else:
		art.panel(Vector3(x - width * 0.12, 1.5, front + n * 0.01), Vector2(opening, 2.0), Vector3(0, 0, n), color, 0, Vector2(opening * 0.6, 1.4))
		var glass := b.box("WindowGlass", Vector3(x - width * 0.12, 1.5, front + n * 0.05), Vector3(opening, 2.0, 0.04), DARK, false)
		glass.get_child(0).material_override = b.glass_material()
		for edge in [-1.0, 1.0]:
			b.detail(Vector3(x - width * 0.12 + edge * opening * 0.5, 1.5, front + n * 0.06), Vector3(0.08, 2.1, 0.08), Color("2a2f36"))
		b.detail(Vector3(x - width * 0.12, 0.45, front + n * 0.06), Vector3(opening, 0.1, 0.1), Color("2a2f36"))
	var door := x + width * 0.5 - 1.2
	b.box("StoreDoor", Vector3(door, 1.1, front + n * 0.03), Vector3(1.1, 2.2, 0.06), Color("23262c"), false)
	art.strip(Vector3(door, 2.27, front + n * 0.07), Vector3(1.2, 0.04, 0.03), color)
	art.strip(Vector3(door + 0.4, 1.1, front + n * 0.08), Vector3(0.03, 0.3, 0.03), Color("c8c8d0"))


func _billboard(b: CompactMapBuilder, x: float, sz: float, title: String, color: Color) -> void:
	# A lit hoarding standing on the boundary wall, seen from both lanes and outside.
	var z := sz * 45.0
	for dx in [-2.2, 2.2]:
		b.pipe(Vector3(x + dx, 4.1, z), Vector3(x + dx, 5.2, z), 0.08, DARK)
	b.box("Billboard", Vector3(x, 6.6, z), Vector3(6.2, 2.9, 0.25), Color("0b0c14"), false)
	art.panel(Vector3(x, 6.6, z - sz * 0.14), Vector2(5.9, 2.6), Vector3(0, 0, -sz), color, 4, Vector2(2.27, 1))
	art.text(title, Vector3(x, 6.05, z - sz * 0.15), Vector3(0, 0, -sz), Color.WHITE, 0.004)
	for y in [5.17, 8.03]:
		art.strip(Vector3(x, y, z - sz * 0.14), Vector3(6.2, 0.05, 0.03), color)


func _outskirts(b: CompactMapBuilder) -> void:
	# North shopfronts behind the food court; the corners hold a loading dock.
	var north := [["CYBER CAFE", "KARAOKE"], ["BOWL-O-RAMA", "MOON BAKERY"], ["RETRO RECORDS", "COMIC VAULT"], ["LOADING DOCK", "LOADING DOCK"]]
	var south := [["MEGA MART", "GAME VAULT"], ["BURGER ORBIT", "BUBBLE TEA"], ["VALET", "VALET"]]
	for sx in [-1.0, 1.0]:
		var pick := 0 if sx < 0 else 1
		for i in 4:
			var x: float = sx * [8.0, 20.0, 32.0, 46.0][i]
			var color: Color = [CYAN, AMBER, PINK, LIME][i]
			_storefront(b, x, -1.0, 9.0, north[i][pick], color, i == 3)
		for i in 3:
			var x: float = sx * [17.0, 28.0, 44.0][i]
			_storefront(b, x, 1.0, [8.0, 8.0, 10.0][i], south[i][pick], [PINK, AMBER, CYAN][i], i == 2)
		b.bake_light(Vector3(sx * 14.0, 3.2, -42.8), CYAN, 1.4, 9.0)
		b.bake_light(Vector3(sx * 32.0, 3.2, -42.8), PINK, 1.4, 9.0)
		b.bake_light(Vector3(sx * 22.0, 3.2, 42.8), AMBER, 1.4, 9.0)
		_billboard(b, sx * 20.0, -1.0, "PLAY LATE  /  OPEN TILL 2AM" if sx < 0 else "NEW  /  PHOTON GALLERY", Color("8250ff") if sx < 0 else PINK)
		_billboard(b, sx * 28.0, 1.0, "NEON CIRCUIT  /  LASER TAG" if sx < 0 else "ARCADE  /  4 TOKENS FOR $5", CYAN if sx < 0 else AMBER)
		# Loading dock: a delivery truck backed up to the shutter.
		b.utility_truck(Vector3(sx * 47.0, 0, -38.0), -PI * 0.5, Color("c9ccd0"))
		b.detail(Vector3(sx * 47.0, 0.018, -43.0), Vector3(4.0, 0.022, 0.25), Color("c9a33a"), "concrete")
		# Wayfinding pylons beside the arena corners.
		for sz in [-1.0, 1.0]:
			_pylon(b, Vector3(sx * 20.5, 0, sz * 12.5), sx, sz)
			_photo_booth(b, Vector3(sx * 35.0, 0, sz * 15.5), -sx)
			_rocket_ride(b, Vector3(sx * 24.0, 0, sz * 15.0), sz)
	# Cinema frontage across the middle of the south lot.
	_storefront(b, 0.0, 1.0, 18.0, "CINEPLEX 9", Color("ff3a5c"), false)
	art.text("NOW SHOWING  /  ATTACK OF THE PIXELS", Vector3(0, 2.75, 44.3), Vector3.FORWARD, AMBER, 0.0024)
	b.bake_light(Vector3(0, 3.2, 42.8), Color(1.0, 0.4, 0.5), 1.6, 10.0)
	# Food court centrepiece: a planter with an orbiting neon sculpture.
	var plaza := Vector3(0, 0, -37.0)
	b.box("CourtyardPlanter", plaza + Vector3(0, 0.4, 0), Vector3(3.2, 0.8, 3.2), CONCRETE)
	b.pipe(plaza + Vector3(0, 0.8, 0), plaza + Vector3(0, 3.0, 0), 0.07, DARK)
	art.strip(plaza + Vector3(0, 3.35, 0), Vector3(0.5, 0.5, 0.5), Color("8250ff"))
	art.ring(plaza + Vector3(0, 3.35, 0), 1.25, PINK)
	art.ring(plaza + Vector3(0, 3.35, 0), 0.95, CYAN, true)
	for sz in [-1.0, 1.0]:
		art.text("FOOD COURT", plaza + Vector3(0, 0.5, sz * 1.62), Vector3(0, 0, sz), AMBER, 0.0028)
		b.def.cover_points.append(plaza + Vector3(0, 0, sz * 2.6))
		b.def.cover_peeks.append(plaza + Vector3(sz * 2.4, 0, sz * 2.6))
	b.bake_light(plaza + Vector3(0, 3.0, 0), Color(0.75, 0.4, 1.0), 1.8, 10.0)


func _pylon(b: CompactMapBuilder, base: Vector3, sx: float, sz: float) -> void:
	b.box("SignPylon", base + Vector3(0, 2.75, 0), Vector3(0.9, 5.5, 0.9), Color("101220"))
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			art.strip(base + Vector3(cx * 0.46, 2.75, cz * 0.46), Vector3(0.04, 5.4, 0.04), CYAN if sx < 0 else PINK)
	art.text("L\nA\nS\nE\nR", base + Vector3(0, 3.1, sz * 0.47), Vector3(0, 0, sz), CYAN if sx < 0 else PINK, 0.0042)
	art.text("A\nR\nC\nA\nD\nE", base + Vector3(sx * 0.47, 3.1, 0), Vector3(sx, 0, 0), AMBER, 0.0042)


func _photo_booth(b: CompactMapBuilder, base: Vector3, face: float) -> void:
	b.box("PhotoBooth", base + Vector3(0, 1.15, 0), Vector3(1.5, 2.3, 1.5), Color("1c1830"))
	var normal := Vector3(face, 0, 0)
	b.box("BoothCurtain", base + normal * 0.77 + Vector3(0, 1.0, 0.2), Vector3(0.04, 1.8, 0.8), Color("6a1e4a"), false)
	art.strip(base + normal * 0.79 + Vector3(0, 2.0, 0), Vector3(0.02, 0.32, 1.4), PINK)
	art.text("PHOTO", base + normal * 0.81 + Vector3(0, 2.0, 0), normal, Color("111022"), 0.0022)
	art.panel(base + normal * 0.77 + Vector3(0, 1.1, -0.45), Vector2(0.45, 1.4), normal, CYAN, 0, Vector2(0.6, 1.6))


func _rocket_ride(b: CompactMapBuilder, base: Vector3, sz: float) -> void:
	b.box("RideBase", base + Vector3(0, 0.22, 0), Vector3(1.6, 0.45, 1.6), Color("2a2f3a"))
	b.box("RocketBody", base + Vector3(0, 1.25, 0), Vector3(0.7, 1.6, 0.7), Color("d8dde2"))
	b.detail(base + Vector3(0, 2.2, 0), Vector3(0.45, 0.45, 0.45), PINK.darkened(0.2), "steel", Vector3(PI * 0.25, 0, PI * 0.25))
	for k in 4:
		var a := PI * 0.5 * k
		b.detail(base + Vector3(cos(a) * 0.45, 0.75, sin(a) * 0.45), Vector3(0.25, 0.5, 0.06), CYAN.darkened(0.3), "steel", Vector3(0, -a, 0))
	art.strip(base + Vector3(0, 1.5, 0), Vector3(0.74, 0.05, 0.74), AMBER)
	art.panel(base + Vector3(0, 1.35, -sz * 0.36), Vector2(0.38, 0.38), Vector3(0, 0, -sz), CYAN, 3)
	art.text("RIDE  /  1 TOKEN", base + Vector3(0, 0.25, -sz * 0.81), Vector3(0, 0, -sz), AMBER, 0.0016)


# Realism pass: house rules, exit markers, floor wear, tyre marks.
func dress(b: CompactMapBuilder) -> void:
	art.arena()
	art.exterior()
	art.finish()
	art = null
	var environment: Environment = b.arena.get_node("Environment").environment
	environment.glow_intensity = 0.65
	environment.glow_bloom = 0.045
	environment.volumetric_fog_albedo = Color("6566ac")
	# Safety equipment beside the arena's six east/west entrances.
	for side: float in [-1.0, 1.0]:
		for z: float in [-8.0, 0.0, 8.0]:
			var spot := Vector3(side * 16.6, 0, z + 2.0)
			b.props.place("korean_fire_extinguisher_01", b.props.grounded("korean_fire_extinguisher_01", spot, 0), false, 60)
	b.floor_decals("Leaking006", 5, Rect2(-14, -14, 28, 28), Vector2(2.0, 2.0), Color(0.05, 0.045, 0.04, 0.85), true)
	for x in range(-14, 15, 7):
		for sz in [-1.0, 1.0]:
			b.decal("Leaking008", Vector3(x, 0.9, sz * 16.24), Vector2(3.2, 1.5), Vector3(0, 0, -sz), 0, Color(1, 1, 1, 0.7))
	# Street furniture, placed only where it clears every collider and marker.
	for sx in [-1.0, 1.0]:
		for x in [4.5, 13.0, 38.5]:
			b.solid_prop("planter_box_02", Vector3(sx * x, 0, -42.6), 0.85)
		for x in [12.0, 24.0, 36.0]:
			b.solid_prop("planter_box_02", Vector3(sx * x, 0, 42.9), 0.85)
		b.small_prop("potted_plant_02", Vector3(sx * 2.6, 0, -39.2), 1.2, 0.0, true)
		b.pallet(Vector3(sx * 43.0, 0, -42.8), 0.0, 3)
		b.prop("hand_truck", Vector3(sx * 44.2, 0, -41.0), 1.1, 0.0, false)
		b.solid_prop("utility_box_02", Vector3(sx * 52.5, 0, -41.5), 1.2, -sx * PI * 0.5)
		b.solid_prop("exterior_aircon_unit", Vector3(sx * 52.5, 0, 41.5), 0.9)
		# The model's long axis is not known here; try both turns and keep the one that fits.
		if not b.solid_prop("covered_car", Vector3(sx * 51.5, 0, 33.0), 1.45, 0.0):
			b.solid_prop("covered_car", Vector3(sx * 51.5, 0, 33.0), 1.45, PI * 0.5)
	for lx in [-24.0, 0.0, 24.0]:
		b.decal("TireTracks001", Vector3(lx, 0.01, 33), Vector2(9.0, 2.2), Vector3.UP, PI * 0.5, Color(0.1, 0.1, 0.1, 0.7))


func ground_splat(b: CompactMapBuilder, x: float, z: float, noise: FastNoiseLite) -> Color:
	var n := noise.get_noise_2d(x, z)
	var ax := maxf(absf(x) - (ARENA + 0.6), 0.0)
	var az := maxf(absf(z) - (ARENA + 0.6), 0.0)
	var d_arena := Vector2(ax, az).length()
	var concrete := 1.0 - smoothstep(0.0, 3.0, d_arena + n * 1.5)
	# Paved sidewalks run along the shopfronts; the bare verge stays behind the spawns.
	var sidewalk := 1.0 - smoothstep(2.6, 3.4, b.def.extent.y * 0.5 - absf(z))
	concrete = maxf(concrete, sidewalk)
	var edge := b.def.extent.x * 0.5 - absf(x)
	var dirt := (1.0 - smoothstep(2.0, 8.0, edge + n * 3.0)) * (1.0 - concrete)
	var asphalt := 1.0 - concrete - dirt
	return Color(maxf(asphalt, 0.0), concrete, maxf(dirt, 0.0))
