extends SceneTree

func _initialize() -> void:
	var parser:=JSON.new();parser.parse(FileAccess.get_file_as_string("res://content/asset_manifest.json"))
	var manifest:Dictionary=parser.data
	var catalog:=Catalog.new()
	for id in catalog.weapon_ids:
		var definition:WeaponDefinition=catalog.weapons[id]
		manifest.assets[id]["render_model"]=definition.model_path.trim_prefix("res://")
		manifest.assets[id]["render_model_sha256"]=FileAccess.get_sha256(definition.model_path)
		var model:=ModelFactory.scene(definition.model_path)
		var bounds:=ModelFactory.bounds(model)
		var target:=.95
		match definition.category:
			"sidearm":target=.34
			"smg":target=.66
			"sniper":target=1.22
			"lmg":target=1.1
		manifest.assets[id]["import_scale"]=target/maxf(bounds.size.x,bounds.size.z)
		manifest.assets[id]["yaw_rotation_radians"]=PI*.5 if bounds.size.x>bounds.size.z else 0.0
		var prepared:=ModelFactory.weapon(definition)
		var muzzle:Vector3=prepared.get_meta("muzzle")
		manifest.assets[id]["sockets"]={"muzzle":[muzzle.x,muzzle.y,muzzle.z],"optic":[0,prepared.get_meta("sight_height"),-.07],"grip":[0,-.12,-.23]}
		prepared.free()
		model.free()
	var soldier:=ModelFactory.scene("res://content/models/realism/operator_combat.glb")
	manifest.soldier["render_model"]="content/models/realism/operator_combat.glb"
	manifest.soldier["render_model_sha256"]=FileAccess.get_sha256("res://"+manifest.soldier.render_model)
	manifest.soldier["import_scale"]=1.8/ModelFactory.bounds(soldier).size.y
	var skeletons:=soldier.find_children("*","Skeleton3D",true,false)
	if not skeletons.is_empty():
		var bones:Array[String]=[]
		for i in skeletons[0].get_bone_count():bones.append(skeletons[0].get_bone_name(i))
		manifest.soldier["imported_bones"]=bones
		manifest.soldier["weapon_hand_bone"]="Wrist.R"
	soldier.free();ModelFactory.sources.clear()
	var file:=FileAccess.open("res://content/asset_manifest.json",FileAccess.WRITE);file.store_string(JSON.stringify(manifest,"\t"));file.close()
	print("ASSET MANIFEST PASS");quit()
