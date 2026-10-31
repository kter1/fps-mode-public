extends SceneTree

# The first-person arms are built offline by tools/blender/build_fp_arms.py (the
# third-person Mixamo soldier's gloves and sleeves) and posed at runtime by ViewModel's
# IK. `prepare` runs this to verify that the shipped rig is complete and shows no skin.

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var path:="res://content/models/arms/fp_arms.glb"
	var model:=ModelFactory.scene(path);root.add_child(model)
	var skeletons:=model.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():push_error("First-person arms have no skeleton: "+path);quit(1);return
	var skeleton:Skeleton3D=skeletons[0]
	var surfaces:=0;var triangles:=0
	for instance in model.find_children("*","MeshInstance3D",true,false):
		for surface in instance.mesh.get_surface_count():
			surfaces+=1;triangles+=instance.mesh.surface_get_array_index_len(surface)/3
			var material:Material=instance.mesh.surface_get_material(surface)
			var label:String=material.resource_name if material!=null else ""
			if not (label.begins_with("FP_Glove") or label.begins_with("FP_Sleeve")):
				push_error("First-person arm surface is not glove or sleeve: "+label);quit(1);return
	for side in ["Left","Right"]:
		for part in ["Shoulder","Arm","ForeArm","Hand","HandIndex1","HandMiddle1","HandPinky1","HandThumb1"]:
			if skeleton.find_bone(side+part)<0:push_error("Missing arm bone "+side+part);quit(1);return
	print("FIRST-PERSON ARMS ",skeleton.get_bone_count()," bones / ",surfaces," glove and sleeve surfaces / ",triangles," triangles")
	model.free();ModelFactory.sources.clear();quit()
