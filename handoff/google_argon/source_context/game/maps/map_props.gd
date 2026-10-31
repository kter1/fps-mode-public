class_name MapProps
extends RefCounted

# Poly Haven glTF props (content/models/props/<id>/). On first use each mesh of
# the imported scene is saved beside the source as a standalone resource, LODs
# included, so generated maps reference it instead of embedding geometry and
# repeated props can share it in a MultiMesh.

# Cover props are baked into the lightmap (they shadow the ground they guard);
# decorative props are lit by the baked probes, keeping the bake BVH small.
const STATIC := ["covered_car","concrete_road_barrier_02"]

# Source files authored at the wrong scale (vertex data, not node transforms).
const FIX_SCALE := {"steel_frame_shelves_01":.1}

var region: Node3D
var parts_cache := {}
var batches := {}
var serial := 0

func _init(target: Node3D) -> void:
	region=target

static func local_transform(node: Node, root: Node) -> Transform3D:
	var transform:=Transform3D.IDENTITY
	var walk:=node
	while walk!=null:
		if walk is Node3D:transform=(walk as Node3D).transform*transform
		if walk==root:break
		walk=walk.get_parent()
	return transform

# Map props live in content/models/props; the compact layouts' furniture set
# was delivered to content/environment/props.
static func folder_of(id: String) -> String:
	var folder:="res://content/models/props/%s/"%id
	return folder if FileAccess.file_exists(folder+id+"_1k.gltf") else "res://content/environment/props/%s/"%id

func parts(id: String) -> Array[Mesh]:
	if parts_cache.has(id):return parts_cache[id]
	var folder:=folder_of(id)
	if not ResourceLoader.exists(folder+id+"_part0.res"):
		var root:=(load(folder+id+"_1k.gltf") as PackedScene).instantiate()
		var index:=0
		for node in root.find_children("*","MeshInstance3D",true,false):
			var mesh:Mesh=(node as MeshInstance3D).mesh.duplicate()
			mesh.set_meta("prop_transform",Transform3D(Basis.from_scale(Vector3.ONE*float(FIX_SCALE.get(id,1.0))))*local_transform(node,root))
			ResourceSaver.save(mesh,folder+id+"_part%d.res"%index)
			index+=1
		root.free()
	var result:Array[Mesh]=[]
	while ResourceLoader.exists(folder+id+"_part%d.res"%result.size()):
		result.append(load(folder+id+"_part%d.res"%result.size()))
	parts_cache[id]=result
	return result

# Bounds of the whole prop in its own space (Y up, origin as authored).
func bounds(id: String) -> AABB:
	var box:=AABB()
	var first:=true
	for mesh in parts(id):
		var part:AABB=(mesh.get_meta("prop_transform",Transform3D.IDENTITY) as Transform3D)*mesh.get_aabb()
		box=part if first else box.merge(part)
		first=false
	return box

# Transform that stands the prop on the ground at position, turned by yaw.
func grounded(id: String, position: Vector3, yaw := 0.0, scale := 1.0) -> Transform3D:
	var box:=bounds(id)
	var basis:=Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale)
	return Transform3D(basis,position-basis*Vector3(box.get_center().x,box.position.y,box.get_center().z))

# A single placed prop. solid adds a box collider around its bounds on the
# world layer (navigation and bullets treat it like any other wall).
func place(id: String, transform: Transform3D, solid := false, visible_to := 0.0) -> Node3D:
	var holder:=Node3D.new()
	holder.name="Prop_"+id+str(serial);serial+=1
	holder.transform=transform
	region.add_child(holder)
	for mesh in parts(id):
		var instance:=MeshInstance3D.new()
		instance.mesh=mesh
		instance.transform=mesh.get_meta("prop_transform",Transform3D.IDENTITY)
		instance.gi_mode=GeometryInstance3D.GI_MODE_STATIC if id in STATIC else GeometryInstance3D.GI_MODE_DYNAMIC
		if visible_to>0:
			instance.visibility_range_end=visible_to;instance.visibility_range_end_margin=visible_to*.15
			instance.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(instance)
	if solid:
		var box:=bounds(id)
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
		body.set_meta("surface","concrete" if "barrier" in id else ("wood" if "crate" in id or "planter" in id else "metal"))
		var shape:=CollisionShape3D.new();var volume:=BoxShape3D.new()
		volume.size=box.size;shape.shape=volume;shape.position=box.get_center()
		body.add_child(shape);holder.add_child(body)
	return holder

# Repeated clutter without collision: batched into one MultiMesh per part and
# 32 m cell, so culling and visibility ranges still work per neighbourhood.
func scatter(id: String, transform: Transform3D) -> void:
	var key:=id+"@"+str(Vector2i(floori(transform.origin.x/32),floori(transform.origin.z/32)))
	if not batches.has(key):batches[key]={"id":id,"transforms":[]}
	batches[key].transforms.append(transform)

func flush(arena: MapArena, visible_to := 90.0) -> void:
	for batch in batches.values():
		var id:String=batch.id
		for mesh in parts(id):
			var offset:Transform3D=mesh.get_meta("prop_transform",Transform3D.IDENTITY)
			var transforms:=PackedFloat32Array()
			for transform in batch.transforms:transforms.append_array(MapArena.pack(transform*offset))
			arena.instance_batches.append(["Clutter_"+id+str(serial),mesh,null,transforms,GeometryInstance3D.GI_MODE_DYNAMIC,visible_to])
			serial+=1
	batches.clear()
