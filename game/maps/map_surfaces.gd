class_name MapSurfaces
extends RefCounted

# Photoscanned CC0 surfaces (Poly Haven, content/materials/<scan>/). "size" is
# the scan's real-world width in metres, so generated meshes with metric UVs
# render every surface at its true scale. "paint" surfaces are recoloured with
# the requested colour; the others keep their photographed colour.
const SCANS := {
	"asphalt": {"scan":"asphalt_02","res":"2k","size":3.0},
	"concrete": {"scan":"brushed_concrete","res":"2k","size":2.5,"grime":.75},
	"concrete_floor": {"scan":"concrete_floor_worn_001","res":"2k","size":3.0,"grime":.4},
	"precast": {"scan":"concrete_wall_004","res":"2k","size":2.0,"grime":.85},
	"brick": {"scan":"factory_brick","res":"2k","size":1.5,"grime":.7},
	"rough_concrete": {"scan":"rough_concrete","res":"2k","size":1.23,"grime":.8},
	"plaster": {"scan":"painted_plaster_wall","res":"2k","size":2.0,"grime":.55},
	"corrugated": {"scan":"corrugated_iron_02","res":"1k","size":2.7,"paint":.72,"gain":1.9,"grime":.6},
	"container": {"scan":"container_side","res":"2k","size":1.94,"grime":.55},
	"container_red": {"scan":"rusty_painted_metal","res":"1k","size":2.2,"grime":.55},
	"painted_metal": {"scan":"green_metal_rust","res":"1k","size":1.0,"paint":.85,"gain":2.6,"grime":.55},
	"steel_plate": {"scan":"metal_plate","res":"1k","size":.5,"grime":.4},
	"paint_concrete": {"scan":"brushed_concrete","res":"2k","size":2.5,"paint":.82,"gain":2.0,"grime":.3},
	"rust": {"scan":"rust_coarse_01","res":"1k","size":2.2,"grime":.3},
	"wood": {"scan":"wood_planks","res":"1k","size":1.5,"grime":.5},
	"gravel": {"scan":"gravel_stones","res":"1k","size":2.0,"grime":.2},
	"grass": {"scan":"leafy_grass","res":"2k","size":2.0,"grime":.1},
	"dirt": {"scan":"rocky_trail","res":"2k","size":2.0,"grime":.1},
	"rock": {"scan":"lichen_rock","res":"2k","size":2.0,"grime":.2},
	"snow": {"scan":"snow_02","res":"2k","size":2.0,"grime":0.0},
	"paving": {"scan":"concrete_pavement","res":"2k","size":1.8,"dir":ENVIRONMENT,"grime":.45},
	"floor": {"scan":"concrete_floor_02","res":"2k","size":2.0,"dir":ENVIRONMENT,"grime":.35},
	"shutter": {"scan":"painted_metal_shutter","res":"2k","size":2.0,"dir":ENVIRONMENT,"paint":.72,"gain":1.9,"grime":.45},
}
const ENVIRONMENT := "res://content/environment/materials/"
const BREAKUP := "res://content/materials/rocky_trail/rocky_trail_disp_2k.jpg"

var cache: Dictionary = {}

static func texture_path(kind: String, channel: String) -> String:
	var scan:Dictionary=SCANS[kind]
	return String(scan.get("dir","res://content/materials/"))+"%s/%s_%s_%s.jpg"%[scan.scan,scan.scan,channel,scan.res]

static func texture(kind: String, channel: String) -> Texture2D:
	return load(texture_path(kind,channel))

# The shared shader material for a surface kind. Paint colours apply only to
# kinds marked "paint"; photographed scans keep their own colour.
func get_material(kind: String, paint := Color.WHITE) -> ShaderMaterial:
	var scan:Dictionary=SCANS[kind]
	var painted:=scan.has("paint")
	var key:=kind+(paint.to_html(false) if painted else "")
	if cache.has(key):return cache[key]
	var mat:=ShaderMaterial.new()
	mat.shader=preload("res://content/materials/surface.gdshader")
	mat.set_shader_parameter("albedo_tex",texture(kind,"diff"))
	mat.set_shader_parameter("normal_tex",texture(kind,"nor_gl"))
	mat.set_shader_parameter("arm_tex",texture(kind,"arm"))
	mat.set_shader_parameter("breakup_tex",load(BREAKUP))
	mat.set_shader_parameter("uv_scale",1.0/float(scan.size))
	mat.set_shader_parameter("grime_amount",float(scan.get("grime",.6)))
	if painted:
		mat.set_shader_parameter("tint",paint)
		mat.set_shader_parameter("tint_mix",float(scan.paint))
		mat.set_shader_parameter("paint_gain",float(scan.get("gain",2.0)))
	cache[key]=mat
	return mat

const GROUND_ROUGHNESS := {"concrete_floor":.82,"gravel":.9,"dirt":.92,"grass":.95,"snow":.55,"rock":.8,"asphalt":.88}

# Splat material for ground and terrain: a base scan with parallax plus three
# overlays selected by vertex colour R, G and B.
func ground_material(base: String, red: String, green: String, blue: String, tint := Color.WHITE) -> ShaderMaterial:
	var key:="ground/"+base+red+green+blue+tint.to_html()
	if cache.has(key):return cache[key]
	var mat:=ShaderMaterial.new()
	mat.shader=preload("res://content/materials/ground.gdshader")
	var scan:Dictionary=SCANS[base]
	mat.set_shader_parameter("base_albedo",texture(base,"diff"))
	mat.set_shader_parameter("base_normal",texture(base,"nor_gl"))
	mat.set_shader_parameter("base_arm",texture(base,"arm"))
	var height:=texture_path(base,"disp")
	if ResourceLoader.exists(height):mat.set_shader_parameter("base_height",load(height))
	else:mat.set_shader_parameter("parallax_depth",0.0)
	mat.set_shader_parameter("base_scale",1.0/float(scan.size))
	mat.set_shader_parameter("base_tint",tint)
	for layer in [["r",red],["g",green],["b",blue]]:
		var kind:String=layer[1]
		mat.set_shader_parameter(layer[0]+"_albedo",texture(kind,"diff"))
		mat.set_shader_parameter(layer[0]+"_normal",texture(kind,"nor_gl"))
		mat.set_shader_parameter(layer[0]+"_scale",1.0/float(SCANS[kind].size))
		mat.set_shader_parameter(layer[0]+"_roughness",float(GROUND_ROUGHNESS.get(kind,.85)))
	mat.set_shader_parameter("breakup_tex",load(BREAKUP))
	cache[key]=mat
	return mat
