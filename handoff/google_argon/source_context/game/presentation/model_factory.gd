class_name ModelFactory
extends RefCounted

const WEAPON_MANIFEST := "res://content/manifest/weapons.json"
# Detailed weapon parts give way to the merged <=5k triangle LOD beyond this range
# (set_weapon_detail, chosen per weapon from the camera distance with a little
# hysteresis; per-mesh visibility ranges measure each mesh's own bounds centre and
# left a band around the range where the parts and the LOD were both culled).
const WEAPON_LOD_DISTANCE := 6.0
const WEAPON_LOD_MARGIN := .75
const OPTICS := ["reflex","holographic","scope"]

static var sources: Dictionary = {}
static var weapon_data: Dictionary = {}

static func scene(path: String) -> Node3D:
	if not ResourceLoader.exists(path): return Node3D.new()
	if not sources.has(path): sources[path]=load(path)
	return sources[path].instantiate()

static func bounds(node: Node3D, transform := Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var first := true
	var current := transform * node.transform
	if node is MeshInstance3D and node.mesh != null and node.visible:
		result=current * node.mesh.get_aabb();first=false
	for child in node.get_children():
		if child is Node3D and child.name!="LOD":
			var child_bounds := bounds(child,current)
			if child_bounds.size.length() > 0:
				result=child_bounds if first else result.merge(child_bounds);first=false
	return result

static func primitive(parent: Node3D, size: Vector3, position: Vector3, color: Color, rounded := false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	if rounded:
		var capsule := CapsuleMesh.new()
		capsule.radius=minf(size.x,size.z)*.5;capsule.height=size.y
		capsule.radial_segments=10;capsule.rings=3
		visual.mesh=capsule
	else:
		var box := BoxMesh.new();box.size=size;visual.mesh=box
	var mat := StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.68
	visual.material_override=mat
	parent.add_child(visual);visual.position=position
	return visual

# Ingested weapon and attachment data: sockets, poses and provenance per slot.
static func manifest() -> Dictionary:
	if weapon_data.is_empty():
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(WEAPON_MANIFEST))
		weapon_data=parsed if parsed is Dictionary else {}
	return weapon_data

static func weapon_info(id: String) -> Dictionary:
	return manifest().get("weapons",{}).get(id,{})

static func attachment_info(id: String) -> Dictionary:
	return manifest().get("attachments",{}).get(id,{})

static func vector(value: Variant) -> Vector3:
	return Vector3(value[0],value[1],value[2]) if value is Array and value.size()==3 else Vector3.ZERO

# Weapons keep their authored PBR materials; sockets come from the ingest manifest.
# Metadata on the returned root:
#   sockets: Dictionary name -> Vector3 (weapon space, metres; -Z is the muzzle direction)
#   muzzle, sight_height: legacy keys used by tools and the third-person mount
#   sight / sight_front: points on the aiming line (bare irons, integrated scope or optic)
#   grip_angle, support_pose, support_radius, action: hand placement and cycling data
static func weapon(definition: WeaponDefinition, attachments: Array[String] = []) -> Node3D:
	if str(definition.id).begins_with("z_"):return ZombieObjects.wonder(str(definition.id))
	var root := Node3D.new();root.name="Weapon"
	var info := weapon_info(str(definition.id))
	var model := scene(definition.model_path);model.name="Model";root.add_child(model)
	for child in model.get_children():
		if child is Node3D:child.set_meta("rest",child.transform)
		if child.name=="LOD":child.visible=false
	var sockets := {}
	var raw:Dictionary=info.get("sockets",{})
	for key in raw:sockets[key]=vector(raw[key].get("position"))
	var support_pose:String=info.get("support_pose","handguard")
	var support_radius:float=raw.get("support",{}).get("radius",.016)
	var sight:Vector3=sockets.get("sight",Vector3(0,.05,.1))
	var sight_front:Vector3=vector(raw.get("sight",{}).get("front",[sight.x,sight.y,sight.z-.3]))
	var sight_is_eye:=false
	if sockets.has("scope_eye"):
		# Integrated scopes: the eye sits at the scope's eye relief behind the ocular.
		sight=sockets.scope_eye+Vector3(0,0,.085);sight_front=sight+Vector3.FORWARD*.2;sight_is_eye=true
	var optic:=""
	for item in attachments:
		if item in OPTICS:optic=item
	if definition.category=="lmg" and sockets.has("bipod"):mount(root,"bipod",sockets.bipod)
	for item in attachments:
		var data := attachment_info(item)
		match item:
			"reflex","holographic","scope":
				var rail:Vector3=sockets.get("optic_rail",sight)
				var sight_node:=mount(root,item,rail)
				sight_node.name="Optic"
				for hidden in ["RearSight","Scope"]:
					var node:=model.get_node_or_null(hidden)
					if node!=null:node.visible=false
				sight=rail+vector(data.get("sockets",{}).get("eye"));sight_front=sight+Vector3.FORWARD*.25
				sight_is_eye=item=="scope"
			"suppressor","compensator":
				mount(root,item,sockets.get("muzzle",Vector3.ZERO))
				sockets.muzzle=sockets.get("muzzle",Vector3.ZERO)+vector(data.get("sockets",{}).get("muzzle"))
			"vertical","angled":
				var under:Vector3=sockets.get("support",Vector3.ZERO)-Vector3(0,support_radius,0)
				mount(root,item,under)
				sockets.support=under+vector(data.get("sockets",{}).get("hand"))
				support_pose=item;support_radius=.016
			"extended":
				var magazine:=model.get_node_or_null("Magazine") as Node3D
				if magazine!=null:
					magazine.scale=Vector3(1,1.32,1) if definition.category!="lmg" else Vector3.ONE*1.12
					magazine.set_meta("rest",magazine.transform)
			"fast":
				var magazine:=model.get_node_or_null("Magazine") as Node3D
				if magazine!=null:
					var tab:=scene(str(data.get("model","")));magazine.add_child(tab)
					tab.position=Vector3(0,-float(raw.get("magwell",{}).get("length",.15)),0)
	# Bare sights on rifles with an integrated scope removed fall back to the irons.
	if optic=="" and not sockets.has("scope_eye") and model.get_node_or_null("RearSight")!=null:
		model.get_node("RearSight").visible=true
	# Bare iron sights get a readable front post and, on pistols, three emissive dots.
	if optic=="" and not sockets.has("scope_eye"):
		iron_sights(root,definition,sight,sight_front,float(raw.get("sight",{}).get("rear_top",sight.y)))
	root.set_meta("sockets",sockets)
	for child in model.get_children():
		if child is GeometryInstance3D and child.name!="LOD":child.set_meta("detail_visible",child.visible)
	# Third-person hands (stance_modifier.gd) read the same grip points as the first-person rig.
	for key in ["grip","support","magwell"]:
		if sockets.get(key) is Vector3:root.set_meta(key,sockets[key])
	root.set_meta("muzzle",sockets.get("muzzle",Vector3(0,0,-.45)))
	root.set_meta("sight",sight);root.set_meta("sight_front",sight_front);root.set_meta("sight_is_eye",sight_is_eye)
	root.set_meta("sight_height",sight.y)
	root.set_meta("optic",optic)
	# Iron sights whose rear sight fills the view can carry a longer eye relief.
	if optic=="" and raw.get("sight",{}).has("relief"):root.set_meta("sight_relief",float(raw.sight.relief))
	root.set_meta("grip_angle",float(raw.get("grip",{}).get("angle_deg",18)))
	root.set_meta("trigger",vector(raw.get("grip",{}).get("trigger")))
	root.set_meta("grip_pose",str(info.get("grip_pose","pistol")))
	root.set_meta("support_pose",support_pose);root.set_meta("support_radius",support_radius)
	root.set_meta("action",str(info.get("action","closed")))
	root.set_meta("magazine_length",float(raw.get("magwell",{}).get("length",0)))
	return root

# Third-person weapons far from the camera draw the merged LOD mesh instead of the
# detailed parts (attachments and iron sights stay). Parts keep the visibility they were
# built with (a hidden rear sight stays hidden when detail returns).
static func set_weapon_detail(root: Node3D, detailed: bool) -> void:
	var model:=root.get_node_or_null("Model")
	if model==null:return
	for child in model.get_children():
		if not child is GeometryInstance3D:continue
		if child.name=="LOD":child.visible=not detailed
		else:child.visible=detailed and bool(child.get_meta("detail_visible",true))

# Whether a weapon already drawn at LOD should stay there at this camera distance.
static func far_weapon(distance: float, was_far: bool) -> bool:
	return distance>WEAPON_LOD_DISTANCE-WEAPON_LOD_MARGIN if was_far else distance>WEAPON_LOD_DISTANCE+WEAPON_LOD_MARGIN

# Matte post (no specular, no sheen) with a lighter top edge, so the post reads against
# dark backgrounds. Pistols add a green dot on the front post and one either side of the
# rear notch; the dots are emissive surfaces only, with no light sources.
const POST_SIZE := Vector3(.003,.0055,.0024)
const POST_EDGE := Color(.34,.36,.38)
const DOT_GREEN := Color(.2,1,.3)
const DOT_RADIUS := .0006
const DOT_SPREAD := .0034

static func iron_sights(root: Node3D, definition: WeaponDefinition, sight: Vector3, front: Vector3, rear_top: float) -> void:
	var irons := Node3D.new();irons.name="IronSights";root.add_child(irons)
	var post := MeshInstance3D.new();var block := BoxMesh.new();block.size=POST_SIZE;post.mesh=block
	post.material_override=matte(Color(.02,.02,.025))
	post.position=front-Vector3(0,POST_SIZE.y*.5,0);irons.add_child(post)
	var edge := MeshInstance3D.new();var cap := BoxMesh.new();cap.size=Vector3(POST_SIZE.x,POST_SIZE.y*.12,POST_SIZE.z);edge.mesh=cap
	edge.material_override=matte(POST_EDGE);edge.position=front-Vector3(0,POST_SIZE.y*.06,0);irons.add_child(edge)
	if definition.category!="sidearm":return
	var dots:=[front-Vector3(0,POST_SIZE.y*.4,0)]
	dots.append(Vector3(sight.x-DOT_SPREAD,rear_top,sight.z));dots.append(Vector3(sight.x+DOT_SPREAD,rear_top,sight.z))
	for point in dots:
		var dot := MeshInstance3D.new();var sphere := SphereMesh.new();sphere.radius=DOT_RADIUS;sphere.height=DOT_RADIUS*2;sphere.radial_segments=8;sphere.rings=4;dot.mesh=sphere
		dot.material_override=emissive(DOT_GREEN);dot.position=point;irons.add_child(dot)

static func matte(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new();mat.albedo_color=colour;mat.roughness=1.0;mat.metallic=0.0;mat.metallic_specular=0.0
	return mat

static func emissive(colour: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new();mat.albedo_color=colour*.25;mat.roughness=.6
	mat.emission_enabled=true;mat.emission=colour;mat.emission_energy_multiplier=.9
	return mat

static func mount(root: Node3D, item: String, at: Vector3) -> Node3D:
	var node:=scene(str(attachment_info(item).get("model","")))
	node.name=item.capitalize();root.add_child(node);node.position=at
	return node

# Visual-only cycling: pump stroke, bolt throw, slide and carrier recoil.
static func animate_weapon(root:Node3D,runtime:WeaponRuntime,now:float) -> void:
	var model:=root.get_node_or_null("Model")
	if model==null:return
	var interval:=60.0/runtime.definition.rpm
	var since:=now-runtime.last_shot_at
	var progress:=clampf(since/maxf(interval,.05),0,1) if since>=0 else 1.0
	var action:String=root.get_meta("action","closed")
	var pump:=model.get_node_or_null("Pump") as Node3D
	if pump!=null:
		var rest:Transform3D=pump.get_meta("rest")
		var stroke:=sin(clampf((progress-.15)/.7,0,1)*PI)*.085 if progress<1 else 0.0
		pump.transform=rest.translated(Vector3(0,0,stroke))
	var bolt:=model.get_node_or_null("Bolt") as Node3D
	if bolt==null:return
	var rest:Transform3D=bolt.get_meta("rest")
	match action:
		"bolt":
			# Lift, draw, return, lock: the throw takes most of the shot interval.
			var lift:=clampf((progress-.1)/.15,0,1)-clampf((progress-.8)/.15,0,1)
			var draw:=sin(clampf((progress-.25)/.5,0,1)*PI)*.09
			bolt.transform=Transform3D(Basis(Vector3.FORWARD,-lift*1.05),Vector3.ZERO)*rest
			bolt.position=rest.origin+Vector3(0,0,draw)
		"slide","reciprocating":
			var travel:=.026 if action=="slide" else .055
			var kick:=(1-clampf(since/.07,0,1)) if since>=0 else 0.0
			bolt.transform=rest.translated(Vector3(0,0,kick*travel))
		_:
			bolt.transform=rest

static func grenade(kind: int) -> Node3D:
	var path:=str(manifest().get("grenades",{}).get("grenade_frag" if kind==0 else "grenade_smoke",{}).get("model",""))
	return scene(path)

# Combat knife, built here (no asset): a flat-ground clip-point blade along +Y from the
# guard, edge toward -Z, and a ribbed polymer handle along -Y. The hand closes on the
# handle at (0, -KNIFE_GRIP_Y, 0).
const KNIFE_GRIP_RADIUS := .0125
const KNIFE_GRIP_Y := .058
# Profile stations along the blade: [y, spine z, edge z, half thickness at the spine].
const KNIFE_BLADE := [[0.0,.011,-.013,.0019],[.06,.011,-.0135,.0019],[.11,.0105,-.012,.0017],[.145,.0062,-.0082,.0012],[.172,-.0015,-.0015,0.0]]

static func knife() -> Node3D:
	var root:=Node3D.new();root.name="Knife"
	var steel:=StandardMaterial3D.new();steel.albedo_color=Color(.6,.61,.62);steel.metallic=1.0;steel.roughness=.3
	var dark:=StandardMaterial3D.new();dark.albedo_color=Color(.13,.13,.14);dark.metallic=.75;dark.roughness=.5
	var polymer:=StandardMaterial3D.new();polymer.albedo_color=Color(.055,.06,.055);polymer.roughness=.85
	var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in KNIFE_BLADE.size()-1:
		var a:Array=KNIFE_BLADE[i];var b:Array=KNIFE_BLADE[i+1]
		var a_left:=Vector3(-a[3],a[0],a[1]);var a_right:=Vector3(a[3],a[0],a[1]);var a_edge:=Vector3(0,a[0],a[2])
		var b_left:=Vector3(-b[3],b[0],b[1]);var b_right:=Vector3(b[3],b[0],b[1]);var b_edge:=Vector3(0,b[0],b[2])
		var middle:=Vector3(0,(a[0]+b[0])*.5,(a[1]+a[2]+b[1]+b[2])*.25)
		for face in [[a_right,b_right,b_edge,a_edge],[a_edge,b_edge,b_left,a_left],[a_left,b_left,b_right,a_right]]:
			knife_quad(tool,face,middle)
	tool.generate_tangents()
	var blade:=MeshInstance3D.new();blade.name="Blade";blade.mesh=tool.commit();blade.material_override=steel;root.add_child(blade)
	var guard:=MeshInstance3D.new();var guard_box:=BoxMesh.new();guard_box.size=Vector3(.016,.007,.04);guard.mesh=guard_box
	guard.material_override=dark;guard.position=Vector3(0,-.0035,-.001);root.add_child(guard)
	var handle:=MeshInstance3D.new();var grip:=CylinderMesh.new();grip.top_radius=KNIFE_GRIP_RADIUS*.95;grip.bottom_radius=KNIFE_GRIP_RADIUS
	grip.height=.1;grip.radial_segments=10;grip.rings=6;handle.mesh=grip;handle.material_override=polymer
	handle.position=Vector3(0,-KNIFE_GRIP_Y,0);handle.scale=Vector3(.8,1,1.1);root.add_child(handle)
	for y in [-.03,-.05,-.07,-.09]:
		var rib:=MeshInstance3D.new();var ring:=CylinderMesh.new();ring.top_radius=KNIFE_GRIP_RADIUS*1.06;ring.bottom_radius=KNIFE_GRIP_RADIUS*1.06
		ring.height=.004;ring.radial_segments=10;ring.rings=1;rib.mesh=ring;rib.material_override=polymer;rib.position=Vector3(0,y,0);rib.scale=handle.scale;root.add_child(rib)
	var pommel:=MeshInstance3D.new();var cap:=CylinderMesh.new();cap.top_radius=KNIFE_GRIP_RADIUS*1.05;cap.bottom_radius=KNIFE_GRIP_RADIUS*.8
	cap.height=.012;cap.radial_segments=10;pommel.mesh=cap;pommel.material_override=dark;pommel.position=Vector3(0,-.114,0);pommel.scale=handle.scale;root.add_child(pommel)
	return root

# One flat-shaded blade facet (a quad, or a triangle where two corners meet at the tip),
# wound clockwise as seen from outside the blade.
static func knife_quad(tool:SurfaceTool,corners:Array,middle:Vector3) -> void:
	var points:Array[Vector3]=[]
	for corner:Vector3 in corners:
		if points.is_empty() or not points.back().is_equal_approx(corner):points.append(corner)
	if points.size()>3 and points[0].is_equal_approx(points[-1]):points.pop_back()
	if points.size()<3:return
	var normal:=(points[1]-points[0]).cross(points[2]-points[0])
	if normal.length()<.0000001:normal=(points[2]-points[0]).cross(points[-1]-points[0])
	normal=normal.normalized()
	var centre:=Vector3.ZERO
	for point in points:centre+=point
	if normal.dot(centre/points.size()-middle)<0:normal=-normal
	for k in range(1,points.size()-1):
		var triangle:=[points[0],points[k],points[k+1]]
		# Clockwise from the outside: the winding's own normal points into the blade.
		if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).dot(normal)>0:triangle=[triangle[0],triangle[2],triangle[1]]
		for vertex in triangle:
			tool.set_normal(normal);tool.set_uv(Vector2(vertex.z*20+.5,vertex.y*5));tool.add_vertex(vertex)

static func animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:return node
	for child in node.get_children():
		var result := animation_player(child)
		if result!=null:return result
	return null
