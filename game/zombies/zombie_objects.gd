class_name ZombieObjects
extends RefCounted

static func label(parent: Node3D, text: String, at: Vector3, color := Color.WHITE, pixels := 40) -> Label3D:
	var node:=Label3D.new();node.text=text;node.position=at;node.font_size=pixels;node.pixel_size=.0035;node.modulate=color
	node.outline_size=3;node.no_depth_test=false;parent.add_child(node);return node

static func solid(parent: Node3D, size: Vector3, at: Vector3) -> StaticBody3D:
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;body.set_meta("surface","metal")
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape);parent.add_child(body);body.position=at;return body

static func chalk(parent: Node3D, id: String) -> void:
	var points: Array[Vector2]
	if id.begins_with("pistol"):
		points=[Vector2(-.38,.08),Vector2(-.38,.23),Vector2(.35,.23),Vector2(.35,.07),Vector2(.02,.07),Vector2(-.04,-.3),Vector2(-.24,-.3),Vector2(-.22,.07),Vector2(-.38,.08)]
	elif id=="smg_mp9":
		points=[Vector2(-.45,.03),Vector2(-.45,.16),Vector2(-.2,.16),Vector2(-.2,.24),Vector2(.3,.24),Vector2(.3,.17),Vector2(.53,.17),Vector2(.53,.08),Vector2(.13,.08),Vector2(.11,-.22),Vector2(-.04,-.22),Vector2(-.06,.03),Vector2(-.45,.03)]
	elif id=="sg_p12":
		points=[Vector2(-.8,-.08),Vector2(-.8,.1),Vector2(-.4,.05),Vector2(-.28,.18),Vector2(.92,.18),Vector2(.92,.12),Vector2(.25,.12),Vector2(.25,.02),Vector2(-.22,.02),Vector2(-.38,-.08),Vector2(-.8,-.08)]
	elif id=="lmg_l56":
		points=[Vector2(-.8,-.08),Vector2(-.8,.15),Vector2(-.3,.1),Vector2(-.28,.28),Vector2(.3,.28),Vector2(.3,.2),Vector2(.9,.2),Vector2(.9,.12),Vector2(.15,.12),Vector2(.15,-.28),Vector2(-.15,-.28),Vector2(-.15,.02),Vector2(-.3,.02),Vector2(-.4,-.08),Vector2(-.8,-.08)]
	else:
		points=[Vector2(-.7,-.06),Vector2(-.7,.16),Vector2(-.35,.1),Vector2(-.3,.25),Vector2(.35,.25),Vector2(.35,.2),Vector2(.83,.2),Vector2(.83,.13),Vector2(.3,.13),Vector2(.2,.02),Vector2(.05,.02),Vector2(.06,-.25),Vector2(-.1,-.25),Vector2(-.12,.02),Vector2(-.3,.02),Vector2(-.38,-.06),Vector2(-.7,-.06)]
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in points.size()-1:
		var a:=points[i];var b:=points[i+1];var n:=(b-a).orthogonal().normalized()*.009
		for p in [a+n,b+n,b-n,a+n,b-n,a-n]:surface.add_vertex(Vector3(p.x,p.y,0))
	var node:=MeshInstance3D.new();node.mesh=surface.commit()
	var mat:=StandardMaterial3D.new();mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;mat.albedo_color=Color("e8e4d6");mat.cull_mode=BaseMaterial3D.CULL_DISABLED;node.material_override=mat;parent.add_child(node)

static func wonder(id: String) -> Node3D:
	var root:=Node3D.new();var color: Color=Color("89bfb0") if id=="z_ray" else (Color("b8a575") if id=="z_thunder" else Color("7b8db3"))
	ZombieVisual.part(root,Vector3(.18,.2,.5),Vector3(0,0,-.08),Color("303c42"))
	ZombieVisual.part(root,Vector3(.11,.22,.12),Vector3(0,-.17,.12),Color("4b514d"))
	var count:=5 if id=="z_arc" else 3
	for i in count:
		var ring:=ZombieVisual.part(root,Vector3(.28,.12,.28),Vector3(0,0,-.1-i*.09),color,true);ring.rotation.x=PI*.5
	if id=="z_thunder":
		ZombieVisual.part(root,Vector3(.42,.32,.36),Vector3(0,.02,-.48),color)
		ZombieVisual.part(root,Vector3(.34,.24,.05),Vector3(0,.02,-.69),Color("172929"))
	else:ZombieVisual.part(root,Vector3(.1,.1,.2),Vector3(0,0,-.59),color)
	var sockets:={"grip":Vector3(0,-.11,.12),"support":Vector3(0,-.08,-.24),"muzzle":Vector3(0,0,-.75),"sight":Vector3(0,.18,.12),"magwell":Vector3(0,-.06,.04)}
	root.set_meta("sockets",sockets);root.set_meta("muzzle",sockets.muzzle);root.set_meta("sight_height",.12)
	root.set_meta("sight",sockets.sight);root.set_meta("sight_front",Vector3(0,.18,-.45));root.set_meta("sight_relief",.30);root.set_meta("support_pose","handguard");root.set_meta("support_radius",.035)
	var magazine:=ZombieVisual.part(root,Vector3(.12,.17,.15),Vector3(0,-.14,-.03),color);magazine.name="Magazine";magazine.set_meta("rest",magazine.transform)
	root.set_meta("optic","");root.set_meta("sight_is_eye",false);root.set_meta("grip_pose","pistol");root.set_meta("grip_angle",18.0)
	root.set_meta("trigger",Vector3(0,-.06,.08));root.set_meta("action","closed");root.set_meta("magazine_length",.16)
	var container:=Node3D.new();container.name="Weapon";root.name="Model";container.add_child(root)
	for key in root.get_meta_list():container.set_meta(key,root.get_meta(key))
	return container

static func joint(parent: Node3D, label_text: String, at: Vector3) -> Node3D:
	return ZombieVisual.joint(parent,label_text,at)
