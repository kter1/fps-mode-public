class_name ZombieVisual
extends Node3D

# Pixelhouse textured zombie and authored clips (CC BY 3.0; see content/licenses).
# Normalize the source rig and remove real leg triangles for crawling.
# The shared primitive helpers below also serve machines and map purchases.
static var materials: Dictionary = {}
static var meshes: Dictionary = {}
var variant := 0

static func finish(color: Color, roughness := .85) -> StandardMaterial3D:
	var key:=str(color)+str(roughness)
	if not materials.has(key):
		var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=roughness
		materials[key]=mat
	return materials[key]

static func part(parent: Node3D, size: Vector3, at: Vector3, color: Color, round_shape := false) -> MeshInstance3D:
	var key:=str(size)+str(round_shape)
	if not meshes.has(key):
		if round_shape:
			var mesh:=CapsuleMesh.new();mesh.radius=minf(size.x,size.z)*.5;mesh.height=maxf(size.y,mesh.radius*2);mesh.radial_segments=8;mesh.rings=3;meshes[key]=mesh
		else:
			meshes[key]=MapMeshes.block(size,.025,.1,false)
	var node:=MeshInstance3D.new();node.mesh=meshes[key];node.material_override=finish(color);parent.add_child(node);node.position=at
	return node

static func joint(parent: Node3D, label: String, at: Vector3) -> Node3D:
	var node:=Node3D.new();node.name=label;parent.add_child(node);node.position=at;return node

const INFECTED_MODEL := "res://content/models/zombies/pixelhouse/infected.fbx"
static var severed_mesh: ArrayMesh
static var detached_meshes: Dictionary = {}
var model: Node3D
var rig: Skeleton3D
var animator: AnimationPlayer
var body_mesh: MeshInstance3D
var whole_mesh: Mesh
var normal_frame: Transform3D
var root_bone := 0
var head_bone := 7
var clip := "Take 001"
var was_crawling := false
static var attack_clip: Animation
var arm_bones: Array[Array] = []

func build(index: int) -> void:
	variant=index%3
	model=ModelFactory.scene(INFECTED_MODEL);add_child(model)
	rig=SoldierFactory.skeleton_of(model);body_mesh=model.find_children("*","MeshInstance3D",true,false)[0]
	whole_mesh=body_mesh.mesh
	animator=ModelFactory.animation_player(model)
	animator.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if attack_clip==null:
		var attack_model:=ModelFactory.scene("res://content/models/zombies/pixelhouse/fury.fbx")
		attack_clip=ModelFactory.animation_player(attack_model).get_animation("Take 001").duplicate();attack_model.free()
	var library:=animator.get_animation_library("")
	if not library.has_animation("attack"):library.add_animation("attack",attack_clip)
	animator.play(clip);animator.seek(0,true)
	for side in ["L","R"]:arm_bones.append([rig.find_bone("Bip01 "+side+" UpperArm"),rig.find_bone("Bip01 "+side+" Forearm"),rig.find_bone("Bip01 "+side+" Hand")])
	root_bone=rig.find_bone("Bip01");head_bone=rig.find_bone("Bip01 Head")
	# The source faces -X and uses a 0.58 m authoring scale. Normalize once;
	# animation and skin binds remain intact, with in-place root motion below.
	var origin:=rig.get_bone_global_rest(root_bone).origin
	var basis:=Basis(Vector3.UP,-PI*.5).scaled(Vector3.ONE*3.10)
	normal_frame=Transform3D(basis,-(basis*Vector3(origin.x,-.0223,origin.z)))
	model.transform=normal_frame
	var key:="infected_%d"%variant
	if not materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_texture=load("res://content/models/zombies/pixelhouse/diffuse.jpg")
		material.normal_enabled=true;material.normal_texture=load("res://content/models/zombies/pixelhouse/normal.jpg");material.normal_scale=.7
		material.albedo_color=[Color("c8c3ab"),Color("a5b6a4"),Color("b3a1a0")][variant];material.roughness=.86
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC;materials[key]=material
	body_mesh.material_override=materials[key]
	if severed_mesh==null:severed_mesh=without_legs(body_mesh,rig,normal_frame)
	var attachment:=BoneAttachment3D.new();attachment.bone_name=rig.get_bone_name(head_bone);rig.add_child(attachment)
	# Eye sockets are sampled from the atlas UV triangles and skin bind matrices
	# by tools/zombie_asset_info.gd, then stored in head-bone local space.
	var pupils: Array[Vector3]=[Vector3(.035018,.028392,-.012377),Vector3(.035030,.029939,.007398)]
	for side in [-1,1]:
		var eye:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.0024;sphere.height=.0048;sphere.radial_segments=8;sphere.rings=4;eye.mesh=sphere
		var glow:=finish(Color("f2c15e")).duplicate() as StandardMaterial3D;glow.emission_enabled=true;glow.emission=Color("f0b33d");glow.emission_energy_multiplier=2;eye.material_override=glow
		attachment.add_child(eye);eye.position=pupils[0 if side<0 else 1];eye.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pose(0,false,0,false,false)

static func without_legs(instance: MeshInstance3D, skeleton: Skeleton3D, frame: Transform3D) -> ArrayMesh:
	var result:=ArrayMesh.new()
	for surface in instance.mesh.get_surface_count():
		var arrays:=instance.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array=arrays[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var removed: Array[bool]=[];var sides: Array[int]=[];var stride: int=bones.size()/vertices.size()
		for vertex in vertices.size():
			var leg_weight:=0.0;var left:=0.0;var right:=0.0
			for influence in stride:
				var binding:=bones[vertex*stride+influence];var name:=str(instance.skin.get_bind_name(binding))
				if name.is_empty():name=skeleton.get_bone_name(instance.skin.get_bind_bone(binding))
				if "Thigh" in name or "Calf" in name or "Foot" in name or "Toe" in name:
					var weight:=weights[vertex*stride+influence];leg_weight+=weight
					if " L " in name:left+=weight
					else:right+=weight
			removed.append(leg_weight>.3);sides.append(-1 if left>.3 else (1 if right>.3 else 0))
		var source: PackedInt32Array=arrays[Mesh.ARRAY_INDEX];var kept:=PackedInt32Array()
		for triangle in range(0,source.size(),3):
			if not removed[source[triangle]] and not removed[source[triangle+1]] and not removed[source[triangle+2]]:
				kept.append(source[triangle]);kept.append(source[triangle+1]);kept.append(source[triangle+2])
		for side in [-1,1]:
			var leg_indices:=PackedInt32Array()
			for triangle in range(0,source.size(),3):
				if sides[source[triangle]]==side and sides[source[triangle+1]]==side and sides[source[triangle+2]]==side:
					leg_indices.append_array(PackedInt32Array([source[triangle],source[triangle+1],source[triangle+2]]))
			detached_meshes[side]=bake_limb(instance,skeleton,arrays,leg_indices,frame)
		arrays[Mesh.ARRAY_INDEX]=kept;result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result

func pose(now: float, crawling: bool, speed: float, attacking: bool, tearing: bool) -> void:
	if rig==null:return
	var phase:=now*(.35 if speed<.1 else clampf(speed/.9,.6,2.5))+variant*.29
	rig.set_bone_global_pose_override(head_bone,Transform3D.IDENTITY,0,false)
	var desired:="attack" if attacking or tearing else clip
	if animator.current_animation!=desired:animator.play(desired)
	for limb in arm_bones:
		for bone: int in limb:rig.set_bone_global_pose_override(bone,Transform3D.IDENTITY,0,false)
	animator.seek(fmod(phase,animator.get_animation(desired).length),true)
	# Cancel source translation so AI owns movement, retaining its authored limp.
	var position:=rig.get_bone_pose_position(root_bone);var rest:=rig.get_bone_rest(root_bone).origin
	position.x=rest.x;position.z=rest.z;rig.set_bone_pose_position(root_bone,position)
	if crawling!=was_crawling:body_mesh.mesh=severed_mesh if crawling else whole_mesh;was_crawling=crawling
	if crawling:
		model.transform=Transform3D(Basis(Vector3.RIGHT,-PI*.5),Vector3(0,.33,0))*Transform3D(Basis.IDENTITY,Vector3(0,-.96,0))*normal_frame
		var head_pose:=rig.get_bone_global_pose(head_bone)
		head_pose.basis=Basis(Vector3(0,0,-1),PI*.5)*head_pose.basis
		rig.set_bone_global_pose_override(head_bone,head_pose,1,true)
		for i in 2:crawl_arm(arm_bones[i],-1 if i==0 else 1,phase)
	else:
		model.transform=normal_frame;rig.set_bone_global_pose_override(head_bone,Transform3D.IDENTITY,0,false)
		if attacking or tearing:
			model.rotation.z+=sin(now*9+variant)*.025
			var face:=rig.get_bone_global_pose(head_bone)
			face.basis=face.basis.orthonormalized().slerp(rig.get_bone_global_rest(head_bone).basis.orthonormalized(),.65)
			rig.set_bone_global_pose_override(head_bone,face,1,true)
			for i in 2:crawl_arm(arm_bones[i],-1 if i==0 else 1,phase,false)

func crawl_arm(bones: Array, side: int, phase: float, low := true) -> void:
	var upper:=rig.get_bone_global_pose(bones[0]);var elbow:=rig.get_bone_global_pose(bones[1]);var hand:=rig.get_bone_global_pose(bones[2])
	var first:=(elbow.origin-upper.origin).length();var second:=(hand.origin-elbow.origin).length()
	var target:=model.transform.affine_inverse()*(Vector3(side*.28,.065,-.72+sin(phase*5+side*PI)*.12) if low else Vector3(side*.30,1.25+sin(phase*6+side)*.06,-.52-sin(phase*6+side)*.07))
	var travel:=target-upper.origin;var length:=clampf(travel.length(),.01,first+second-.001);var forward:=travel.normalized()
	var bend:=(model.transform.basis.inverse()*Vector3(side,0,0)).normalized();bend=(bend-forward*bend.dot(forward)).normalized()
	var cosine:=clampf((first*first+length*length-second*second)/(2*first*length),-1,1)
	var joint:=upper.origin+forward*first*cosine+bend*first*sqrt(maxf(0,1-cosine*cosine))
	var turn:=Basis(Quaternion((elbow.origin-upper.origin).normalized(),(joint-upper.origin).normalized()))
	upper.basis=turn*upper.basis
	var lower_turn:=Basis(Quaternion((hand.origin-elbow.origin).normalized(),(target-joint).normalized()))
	elbow.origin=joint;elbow.basis=lower_turn*elbow.basis;hand.origin=target;hand.basis=lower_turn*hand.basis
	rig.set_bone_global_pose_override(bones[0],upper,1,true);rig.set_bone_global_pose_override(bones[1],elbow,1,true);rig.set_bone_global_pose_override(bones[2],hand,1,true)

static func bake_limb(instance: MeshInstance3D, skeleton: Skeleton3D, source: Array, indices: PackedInt32Array, frame: Transform3D) -> ArrayMesh:
	var arrays:=source.duplicate();var vertices: PackedVector3Array=source[Mesh.ARRAY_VERTEX];var normals: PackedVector3Array=source[Mesh.ARRAY_NORMAL]
	var bones: PackedInt32Array=source[Mesh.ARRAY_BONES];var weights: PackedFloat32Array=source[Mesh.ARRAY_WEIGHTS];var stride: int=bones.size()/vertices.size()
	var transforms: Array[Transform3D]=[]
	for binding in instance.skin.get_bind_count():
		var bone:=instance.skin.get_bind_bone(binding)
		if bone<0:bone=skeleton.find_bone(instance.skin.get_bind_name(binding))
		transforms.append(frame*skeleton.get_bone_global_pose(bone)*instance.skin.get_bind_pose(binding))
	var posed:=PackedVector3Array();var smooth:=PackedVector3Array()
	for vertex in vertices.size():
		var position:=Vector3.ZERO;var normal:=Vector3.ZERO
		for influence in stride:
			var weight:=weights[vertex*stride+influence];var transform:=transforms[bones[vertex*stride+influence]]
			position+=(transform*vertices[vertex])*weight;normal+=(transform.basis*normals[vertex])*weight
		posed.append(position);smooth.append(normal.normalized())
	var center:=Vector3.ZERO
	for index in indices:center+=posed[index]
	center/=maxi(1,indices.size())
	for i in posed.size():posed[i]-=center
	arrays[Mesh.ARRAY_VERTEX]=posed;arrays[Mesh.ARRAY_NORMAL]=smooth;arrays[Mesh.ARRAY_INDEX]=indices
	arrays[Mesh.ARRAY_BONES]=null;arrays[Mesh.ARRAY_WEIGHTS]=null;arrays[Mesh.ARRAY_TANGENT]=null
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return result

func detached_leg(side: int) -> MeshInstance3D:
	var limb:=MeshInstance3D.new();limb.mesh=detached_meshes[side];limb.material_override=materials["infected_%d"%variant]
	return limb
