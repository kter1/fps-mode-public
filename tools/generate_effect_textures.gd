extends SceneTree

# Generates the explosion/smoke/fire flipbooks, the scorch decal and the barrel
# signage decals into content/effects (original art, CC0). Run once; the PNGs are
# committed:  godot --headless --script res://tools/generate_effect_textures.gd
#
# smoke_flipbook.png  4x4 frames of 128 px. RG = sprite-space normal, B = detail, A = density.
# fire_flipbook.png   4x4 frames of 128 px. R = heat, G = soot, A = density.

const FRAMES := 4
const CELL := 128
const OUT := "res://content/effects/"

var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;noise.seed = 1337;noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM;noise.fractal_octaves = 4;noise.fractal_gain = .52
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH;detail.seed = 4242;detail.frequency = 1.0
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM;detail.fractal_octaves = 3
	smoke_flipbook();fire_flipbook();scorch();label_flammable();hazard_diamond()
	print("EFFECT_TEXTURES done")
	quit()

func save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + name))
	print("WROTE ", name, " ", image.get_width(), "x", image.get_height())

func edge_mask(r: float, inner := .62, outer := .98) -> float:
	return 1.0 - smoothstep(inner, outer, r)

# Billowy puff: domain-warped fBm under a soft radial envelope. The envelope reaches
# zero well inside the cell so no sprite edge can ever show.
func smoke_flipbook() -> void:
	var size := FRAMES * CELL
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for frame in FRAMES * FRAMES:
		var t := float(frame) / (FRAMES * FRAMES - 1)
		var density := PackedFloat32Array();density.resize(CELL * CELL)
		var fine := PackedFloat32Array();fine.resize(CELL * CELL)
		for y in CELL:
			for x in CELL:
				var p := Vector2((x + .5) / CELL * 2 - 1, (y + .5) / CELL * 2 - 1)
				var r := p.length()
				var warp := Vector2(noise.get_noise_3d(p.x * 1.7 + 11, p.y * 1.7, t * 1.3), noise.get_noise_3d(p.x * 1.7, p.y * 1.7 + 29, t * 1.3)) * .38
				var q := p + warp
				var n := noise.get_noise_3d(q.x * 1.9, q.y * 1.9, 5 + t * 1.6)
				var billow := 1.0 - absf(noise.get_noise_3d(q.x * 3.1, q.y * 3.1, 9 + t) * 1.5)
				var envelope := edge_mask(q.length() * (1.0 + t * .1), .28, .86)
				var value := clampf(envelope * (1.1 + n * .5 + billow * .12) - .12 + (1.0 - r) * .2, 0, 1)
				value *= edge_mask(r, .74, .97)
				density[y * CELL + x] = smoothstep(0.0, 1.0, value)
				fine[y * CELL + x] = detail.get_noise_3d(p.x * 6.5, p.y * 6.5, t * 2.0) * .5 + .5
		density = soften(density)
		for y in CELL:
			for x in CELL:
				var left := density[y * CELL + maxi(x - 1, 0)];var right := density[y * CELL + mini(x + 1, CELL - 1)]
				var up := density[maxi(y - 1, 0) * CELL + x];var down := density[mini(y + 1, CELL - 1) * CELL + x]
				var normal := Vector3((left - right) * 5.0, (up - down) * 5.0, 1.0).normalized()
				# Bulge: thick centres face the viewer, rims turn away.
				var d := density[y * CELL + x]
				normal = Vector3(normal.x, normal.y, 1.0 + d * 1.2).normalized()
				var ox := (frame % FRAMES) * CELL + x;var oy := (frame / FRAMES) * CELL + y
				image.set_pixel(ox, oy, Color(normal.x * .5 + .5, normal.y * .5 + .5, fine[y * CELL + x], d))
	save(image, "smoke_flipbook.png")

# Two 3x3 box-blur passes: puffs get soft, feathered edges instead of cut-out ones.
func soften(source: PackedFloat32Array) -> PackedFloat32Array:
	var current := source
	for pass_index in 2:
		var next := PackedFloat32Array();next.resize(CELL * CELL)
		for y in CELL:
			for x in CELL:
				var sum := 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						sum += current[clampi(y + dy, 0, CELL - 1) * CELL + clampi(x + dx, 0, CELL - 1)]
				next[y * CELL + x] = sum / 9.0
		current = next
	return current

# Fireball evolution: a hot turbulent core that swells, lifts and cools to dark red.
func fire_flipbook() -> void:
	var size := FRAMES * CELL
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for frame in FRAMES * FRAMES:
		var t := float(frame) / (FRAMES * FRAMES - 1)
		var grow := 1.0 - pow(1.0 - t, 2.2)
		var radius := lerpf(.34, .8, grow)
		for y in CELL:
			for x in CELL:
				var p := Vector2((x + .5) / CELL * 2 - 1, (y + .5) / CELL * 2 - 1)
				# Hot gas rises: the field slides upward (towards smaller y) over time.
				var lifted := p + Vector2(0, t * .22)
				var warp := Vector2(noise.get_noise_3d(lifted.x * 2.0 + 3, lifted.y * 2.0, t * 2.2), noise.get_noise_3d(lifted.x * 2.0, lifted.y * 2.0 + 41, t * 2.2)) * .34
				var q := lifted + warp
				var n := noise.get_noise_3d(q.x * 2.6, q.y * 2.6 - t * 1.4, 17 + t * 2.0)
				var core := 1.0 - q.length() / radius
				var shape := clampf(core * 1.5 + n * .62, 0, 1)
				var heat := clampf(shape * 1.25 - t * .78 + n * .12, 0, 1)
				var alpha := smoothstep(.0, .42, shape) * edge_mask(p.length(), .7, .98)
				alpha *= 1.0 - smoothstep(.72, 1.0, t) * .75
				var soot := clampf(.35 + n * .5 + t * .5, 0, 1)
				image.set_pixel((frame % FRAMES) * CELL + x, (frame / FRAMES) * CELL + y, Color(heat, soot, 0, alpha))
	soften_alpha(image)
	save(image, "fire_flipbook.png")

# One 3x3 blur of every cell's alpha channel (keeps spiky fire edges soft).
func soften_alpha(image: Image) -> void:
	var copy := image.duplicate() as Image
	for frame in FRAMES * FRAMES:
		var ox := (frame % FRAMES) * CELL;var oy := (frame / FRAMES) * CELL
		for y in CELL:
			for x in CELL:
				var sum := 0.0
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						sum += copy.get_pixel(ox + clampi(x + dx, 0, CELL - 1), oy + clampi(y + dy, 0, CELL - 1)).a
				var color := copy.get_pixel(ox + x, oy + y)
				image.set_pixel(ox + x, oy + y, Color(color.r, color.g, color.b, sum / 9.0))

# Blast scorch: charred core, ragged ejecta rays and a soft sooty rim.
func scorch() -> void:
	var size := 256
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2((x + .5) / size * 2 - 1, (y + .5) / size * 2 - 1)
			var r := p.length();var angle := atan2(p.y, p.x)
			var rough := noise.get_noise_2d(p.x * 2.4 + 5, p.y * 2.4) * .22
			var rays := detail.get_noise_2d(cos(angle) * 3.5, sin(angle) * 3.5) * .3 * (1.0 - r)
			var reach := r * (1.0 + rough) - rays * .5
			var core := 1.0 - smoothstep(.12, .62, reach)
			var rim := 1.0 - smoothstep(.45, .98, reach)
			var speck := detail.get_noise_2d(x * .35, y * .35) * .5 + .5
			var alpha := clampf(core * .74 + rim * .4 * (.65 + speck * .55), 0, 1) * (1.0 - smoothstep(.9, 1.0, r))
			var shade := .025 + .05 * speck + (1.0 - core) * .06
			image.set_pixel(x, y, Color(shade, shade * .95, shade * .9, alpha))
	save(image, "scorch.png")

# --- barrel signage -----------------------------------------------------------------

# Tiny 5x7 glyphs for the letters the label needs.
const GLYPHS := {
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"N": ["10001", "11001", "10101", "10101", "10011", "10001", "10001"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
}

func glyph_hit(letter: String, u: float, v: float) -> bool:
	# u, v in 0..1 inside a glyph cell (5x7 grid with a half-cell gap).
	var rows: Array = GLYPHS[letter]
	var gx := int(floor(u * 5.0));var gy := int(floor(v * 7.0))
	if gx < 0 or gx > 4 or gy < 0 or gy > 6:return false
	return String(rows[gy])[gx] == "1"

func flame_shape(p: Vector2) -> float:
	# Teardrop flame icon in -1..1 space, tip up. Returns 1 inside.
	var v := (p.y + 1.0) * .5
	var width := sin(clampf(v, 0, 1) * PI) * (1.0 - v) * 1.35 + .02
	var bend := (v - .5) * (v - .5) * .35
	var inside := absf(p.x - bend * .0) < width * .62 and p.y > -.95 and p.y < .92
	# Inner notch carves the classic two-tongue silhouette.
	var notch := Vector2(p.x - .18, p.y + .38).length() < .24
	return 1.0 if inside and not notch else 0.0

func label_flammable() -> void:
	# 256 x 128: white plate with a red border, FLAMMABLE in black and a red flame.
	var w := 256;var h := 128
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var word := "FLAMMABLE"
	for y in h:
		for x in w:
			var u := (x + .5) / w;var v := (y + .5) / h
			var cx := absf(u - .5) * 2;var cy := absf(v - .5) * 2
			# Rounded rectangle plate.
			var corner := maxf(cx - .86, 0) * 1.0 + maxf(cy - .8, 0) * 2.0
			var plate := 1.0 - smoothstep(.1, .16, corner + maxf(cx - .96, cy - .94) * 0.0)
			if cx > .97 or cy > .95:plate = 0.0
			var color := Color(.86, .84, .78)
			var border := cx > .9 or cy > .86
			if border:color = Color(.72, .06, .05)
			# Wear: blotchy dirt and scratches lower the plate's contrast.
			var grime := detail.get_noise_2d(x * .09, y * .09) * .5 + .5
			color = color.lerp(Color(.35, .3, .24), grime * .22)
			# Text row.
			var tx := (u - .07) / .86;var ty := (v - .55) / .3
			if tx >= 0 and tx < 1 and ty >= 0 and ty < 1:
				var slot := tx * word.length()
				var index := clampi(int(slot), 0, word.length() - 1)
				var local_u := (slot - index) * 1.25 - .1
				if glyph_hit(word[index], local_u, ty):color = Color(.05, .04, .04)
			# Flame pictogram above the word.
			var fx := (u - .5) / .12;var fy := ((v - .26) / .21) * 2.0 - 1.0 + 0.0
			if absf(fx) < 1.2 and absf(fy) < 1.0 and flame_shape(Vector2(fx, -fy)) > .5:color = Color(.8, .08, .05)
			var scuff := smoothstep(.62, .78, detail.get_noise_2d(x * .5 + 40, y * 1.4)) * .35
			color = color.lerp(Color(.3, .27, .22), scuff)
			image.set_pixel(x, y, Color(color, plate * (.94 - grime * .18)))
	save(image, "label_flammable.png")

func hazard_diamond() -> void:
	# 128 x 128 class-3 diamond: red field, white inner line, white flame.
	var size := 128
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := Vector2((x + .5) / size * 2 - 1, (y + .5) / size * 2 - 1)
			var d := absf(p.x) + absf(p.y)
			var color := Color(.78, .07, .05)
			var alpha := 1.0 - smoothstep(.94, .985, d)
			if d > .8 and d < .86:color = Color(.9, .88, .84)
			if d > .86 and d < .93:color = Color(.05, .04, .04)
			if d <= .8 and flame_shape(Vector2(p.x / .45, -p.y / .5 + .1)) > .5:color = Color(.93, .91, .86)
			var grime := detail.get_noise_2d(x * .11, y * .11) * .5 + .5
			color = color.lerp(Color(.25, .2, .16), grime * .25)
			image.set_pixel(x, y, Color(color, alpha * (.95 - grime * .15)))
	save(image, "hazard_diamond.png")
