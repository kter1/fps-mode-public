class_name ProfileStore
extends RefCounted

var directory := "user://"
var settings := {"sensitivity": 0.08, "pad_sensitivity": 1.0, "aim_assist": true, "fov": 75.0, "quality": 1, "volume": 0.8, "shake": 0.6, "toggle_aim": true, "toggle_sprint": false, "bindings": {}}
var loadouts: Array[LoadoutDefinition] = []
var zombies_records: Dictionary = {}
var catalog: Catalog

func configure(source: Catalog, path := "user://") -> void:
	catalog = source
	directory = path
	loadouts = catalog.starter_loadouts()
	var file_path := directory.path_join("profile.json")
	if not FileAccess.file_exists(file_path): return
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(file_path))!=OK:return
	var decoded = parser.data
	if not decoded is Dictionary or decoded.get("version") != 1: return
	if decoded.get("zombies_records",{}) is Dictionary:
		for id in decoded.zombies_records:
			var record: Variant=decoded.zombies_records[id]
			if not record is Dictionary:continue
			var valid:=true
			for key in ["round","completed","kills","headshots","points_earned","seconds"]:
				if not record.get(key) is float and not record.get(key) is int:valid=false
				elif not is_finite(float(record[key])) or float(record[key])<0:valid=false
			if valid:zombies_records[str(id)]=record.duplicate(true)
	var incoming = decoded.get("settings", {})
	if incoming is Dictionary:
		for key in settings:
			if not incoming.has(key):continue
			if typeof(incoming[key]) == typeof(settings[key]):settings[key] = incoming[key]
			elif (incoming[key] is float or incoming[key] is int) and (settings[key] is float or settings[key] is int):settings[key]=incoming[key]
	settings.fov = clampf(float(settings.fov), 60, 90)
	settings.sensitivity = clampf(float(settings.sensitivity), .01, .4)
	settings.quality = clampi(int(settings.quality), 0, 2)
	settings.volume = clampf(float(settings.volume), 0, 1)
	settings.shake = clampf(float(settings.shake), 0, 1)
	var bindings:Dictionary={}
	for action in settings.bindings:
		var key = settings.bindings[action]
		if (key is float or key is int) and key>0 and key<33554432:bindings[str(action)]=int(key)
	settings.bindings=bindings
	var saved = decoded.get("loadouts", [])
	if not saved is Array: return
	for i in mini(5, saved.size()):
		if not saved[i] is Dictionary: continue
		var entry: Dictionary = saved[i]
		var primary: String = str(entry.get("primary", "ar_a4"))
		var sidearm: String = str(entry.get("sidearm", "pistol_p9"))
		if primary not in catalog.weapon_ids.slice(0,12) or sidearm not in catalog.weapon_ids.slice(12): continue
		var pa = entry.get("primary_attachments", [])
		var sa = entry.get("sidearm_attachments", [])
		if not pa is Array or not sa is Array: continue
		if not catalog.valid_attachments(catalog.weapons[primary], pa) or not catalog.valid_attachments(catalog.weapons[sidearm], sa): continue
		loadouts[i].primary = StringName(primary)
		loadouts[i].sidearm = StringName(sidearm)
		loadouts[i].primary_attachments.assign(pa)
		loadouts[i].sidearm_attachments.assign(sa)

func save() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var entries: Array = []
	for item in loadouts: entries.append(item.to_dict())
	var file := FileAccess.open(directory.path_join("profile.json.tmp"), FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"version": 1, "settings": settings, "loadouts": entries, "zombies_records": zombies_records}, "\t"))
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(directory.path_join("profile.json.tmp")), ProjectSettings.globalize_path(directory.path_join("profile.json"))) == OK
