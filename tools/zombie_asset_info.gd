extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var atlas:=Image.load_from_file("res://content/models/zombies/pixelhouse/diffuse.jpg")
	atlas.get_region(Rect2i(1400,1500,648,548)).save_png("res://.artifacts/zombie-face-uv-inspection.png")
	var model: Node3D=load("res://content/models/zombies/pixelhouse/infected.fbx").instantiate();root.add_child(model)
	var skeleton: Skeleton3D=SoldierFactory.skeleton_of(model)
	var bones: Array=[]
	if skeleton!=null:
		for i in skeleton.get_bone_count():bones.append({"id":i,"name":skeleton.get_bone_name(i),"parent":skeleton.get_bone_parent(i),"rest":str(skeleton.get_bone_global_rest(i).origin)})
	var meshes: Array=[]
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):meshes.append({"path":str(model.get_path_to(mesh)),"bounds":str(mesh.get_aabb()),"transform":str(mesh.global_transform),"surfaces":mesh.mesh.get_surface_count()})
	var source_mesh: MeshInstance3D=model.find_children("*","MeshInstance3D",true,false)[0]
	for target in [Vector2(1417.0/2048,1752.0/2048),Vector2(1508.0/2048,1752.0/2048)]:
		eye_position(source_mesh,skeleton,target);eye_position(source_mesh,skeleton,Vector2(target.x,1-target.y))
	var clips: Array=[]
	for player: AnimationPlayer in model.find_children("*","AnimationPlayer",true,false):
		for clip in player.get_animation_list():clips.append({"name":clip,"seconds":player.get_animation(clip).length})
	var file:=FileAccess.open("res://.artifacts/zombie-asset-info.json",FileAccess.WRITE);file.store_string(JSON.stringify({"bones":bones,"meshes":meshes,"clips":clips},"\t"));file.close()
	print("ZOMBIE ASSET ",bones.size()," bones ",meshes.size()," meshes ",clips);model.free();quit()

func eye_position(mesh: MeshInstance3D, skeleton: Skeleton3D, uv: Vector2) -> void:
	var arrays:=mesh.mesh.surface_get_arrays(0);var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX];var uvs: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS];var stride: int=bones.size()/vertices.size()
	for at in range(0,indices.size(),3):
		var a:=uvs[indices[at]];var b:=uvs[indices[at+1]];var c:=uvs[indices[at+2]];var denominator:=(b-a).cross(c-a)
		if absf(denominator)<.00000001:continue
		var u:=(uv-a).cross(c-a)/denominator;var v:=(b-a).cross(uv-a)/denominator
		if u<0 or v<0 or u+v>1:continue
		var point:=Vector3.ZERO;var names: Dictionary={}
		for j in 3:
			var vertex:=indices[at+j];var position:=Vector3.ZERO
			for k in stride:
				var binding:=bones[vertex*stride+k];var weight:=weights[vertex*stride+k]
				var bone:=mesh.skin.get_bind_bone(binding)
				if bone<0:bone=skeleton.find_bone(mesh.skin.get_bind_name(binding))
				if weight>.1:names[skeleton.get_bone_name(bone)]=true
				position+=(skeleton.get_bone_global_rest(bone)*mesh.skin.get_bind_pose(binding)*vertices[vertex])*weight
			point+=position*([1-u-v,u,v][j])
		print("EYE UV ",uv," bones=",names," head_local=",skeleton.get_bone_global_rest(skeleton.find_bone("Bip01 Head")).affine_inverse()*point)
