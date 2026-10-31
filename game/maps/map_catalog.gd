class_name MapCatalog
extends RefCounted

# The map registry: one JSON entry per map in content/manifest/map_list/<id>.json
# (id, menu text, layout script, seed, extent, style knobs, lighting, capture
# cameras, overview labels), sorted by "order" then id. tools/dev.py reads the
# same files, so adding a map never edits a shared list. See MAP_DESIGN.md.

const DIRECTORY := "res://content/manifest/map_list/"
const ASSET_MANIFEST := "res://content/manifest/maps.json"
const ASSET_MANIFESTS := "res://content/manifest/maps/"

static var _entries: Array[Dictionary] = []

static func entries() -> Array[Dictionary]:
	if _entries.is_empty():
		for file in DirAccess.get_files_at(DIRECTORY):
			if not file.ends_with(".json"):continue
			var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY+file))
			if data is Dictionary and str(data.get("id",""))==file.get_basename():_entries.append(data)
			else:push_error("Invalid map registry entry: "+DIRECTORY+file)
		_entries.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
			if float(a.get("order",0))!=float(b.get("order",0)):return float(a.get("order",0))<float(b.get("order",0))
			return str(a.id)<str(b.id))
	return _entries

static func ids() -> Array[String]:
	var result:Array[String]=[]
	for item in entries():result.append(str(item.id))
	return result

static func has(id: String) -> bool:
	return id in ids()

static func entry(id: String) -> Dictionary:
	for item in entries():
		if str(item.id)==id:return item
	push_error("Unknown map: "+id)
	return {}

static func default_id() -> String:
	return ids()[0] if not ids().is_empty() else ""

# The map shown behind the main menu: the first entry with a menu_backdrop camera.
static func backdrop_id() -> String:
	for item in entries():
		if item.has("menu_backdrop"):return str(item.id)
	return default_id()

static func scene_path(id: String) -> String:
	return "res://game/maps/generated/"+id+".tscn"

static func style(id: String) -> Dictionary:
	return entry(id).get("style",{})

# Asset provenance for maps: the shared content/manifest/maps.json plus one
# content/manifest/maps/<id>.json per map that fetched its own sources.
static func asset_manifest() -> Dictionary:
	var assets:={}
	var paths:Array[String]=[ASSET_MANIFEST]
	if DirAccess.dir_exists_absolute(ASSET_MANIFESTS):
		for file in DirAccess.get_files_at(ASSET_MANIFESTS):
			if file.ends_with(".json"):paths.append(ASSET_MANIFESTS+file)
	for path in paths:
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if data is Dictionary:assets.merge(data.get("assets",{}),true)
	return {"assets":assets}

# JSON helpers: colours are hex strings or [r, g, b(, a)]; vectors are arrays.
static func color(value: Variant, fallback := Color.WHITE) -> Color:
	if value is String:return Color(value)
	if value is Array:return Color(float(value[0]),float(value[1]),float(value[2]),float(value[3]) if value.size()>3 else 1.0)
	return fallback

static func vec2(value: Variant) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

static func vec3(value: Variant) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

static func entries_for_mode(mode_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in entries():
		if (mode_id=="campaign" and str(item.id)=="blackout") or mode_id in item.get("supported_modes", ["tdm"]):result.append(item)
	return result

static func ids_for_mode(mode_id: String) -> Array[String]:
	var result: Array[String] = []
	for item in entries_for_mode(mode_id):result.append(str(item.id))
	return result
