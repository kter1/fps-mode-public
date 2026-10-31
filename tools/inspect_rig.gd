extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for path in ["res://content/models/soldier.glb","res://content/models/realism/operator_combat.glb"]:
		var model:=ModelFactory.scene(path);root.add_child(model)
		print(path," BOUNDS=",ModelFactory.bounds(model))
		for node in model.find_children("*","Node3D",true,false):
			if node is MeshInstance3D:print(node.name," global=",node.global_transform," AABB=",node.get_aabb())
			if node is Skeleton3D:
				print("SKELETON ",node.global_transform)
				for key in ["Body","Head","Wrist.R"]:print(key," global=",node.to_global(node.get_bone_global_pose(node.find_bone(key)).origin))
		model.free()
	ModelFactory.sources.clear();quit()
