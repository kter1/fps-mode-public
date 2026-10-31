extends RefCounted

const SOCKETS := ["muzzle","grip","support","optic_rail","magwell","ejection","sight","butt"]
# Real-world overall length (metres) per category; models are no longer normalized.
const LENGTHS := {"assault":[.7,1.05],"smg":[.5,.95],"shotgun":[.8,1.3],"lmg":[.85,1.2],"marksman":[.95,1.3],"sniper":[1.0,1.35],"sidearm":[.15,.35]}
const ARMS := "res://content/models/arms/fp_arms.glb"

# Content checks for weapons, attachments and first-person arms.
static func run(t) -> void:
	t.check_that(t.catalog.weapons.size()==15,"fifteen_weapons")
	t.check_that(t.catalog.attachments.size()==9,"nine_attachments")
	var manifest:=ModelFactory.manifest()
	for id in t.catalog.weapon_ids:
		var def:WeaponDefinition=t.catalog.weapons[id]
		t.check_that(def!=null and def.capacity>0 and def.rpm>0 and def.range_end>def.range_start,"definition_"+id)
		t.check_that(ResourceLoader.exists(def.model_path),"model_"+id,def.model_path)
		var info:=ModelFactory.weapon_info(id)
		t.check_that(info.get("model","")==def.model_path and info.get("license","")=="CC0-1.0","manifest_"+id,str(info.get("model","")))
		var sockets:Dictionary=info.get("sockets",{})
		t.check_that(SOCKETS.all(func(name):return sockets.has(name)),"weapon_sockets_"+id,str(sockets.keys()))
		var imported:=ModelFactory.scene(def.model_path)
		var bounds:=ModelFactory.bounds(imported)
		var limits:Array=LENGTHS[def.category]
		t.check_that(bounds.size.z>limits[0] and bounds.size.z<limits[1] and bounds.size.x<.2,"real_scale_"+id,str(bounds.size))
		var grown:=bounds.grow(.03)
		var inside:=true
		for name in sockets:
			if name!="butt" and not grown.has_point(ModelFactory.vector(sockets[name].position)):inside=false
		t.check_that(inside,"sockets_on_model_"+id)
		var muzzle:=ModelFactory.vector(sockets.get("muzzle",{}).get("position"))
		t.check_that(muzzle.z<bounds.position.z+.02,"muzzle_at_front_"+id,str(muzzle))
		var view:=0;var lod:=0;var pbr:=true
		for mesh_instance in imported.find_children("*","MeshInstance3D",true,false):
			var triangles:=triangle_count(mesh_instance.mesh)
			if mesh_instance.name=="LOD":lod+=triangles
			else:view+=triangles
			for surface in mesh_instance.mesh.get_surface_count():
				var material:=mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
				pbr=pbr and material!=null and material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null
		t.check_that(view>0 and view<=25000,"viewmodel_budget_"+id,str(view))
		t.check_that(lod>0 and lod<=5000,"world_lod_budget_"+id,str(lod))
		t.check_that(pbr,"pbr_textures_"+id)
		# Tube-fed shotguns and the internal-magazine sniper load rounds by hand instead.
		t.check_that(imported.get_node_or_null("Magazine")!=null or def.category in ["shotgun","sniper"],"magazine_node_"+id)
		imported.free()
		var built:=ModelFactory.weapon(def,[])
		t.check_that(built.has_meta("sockets") and built.has_meta("sight") and built.has_meta("muzzle"),"factory_sockets_"+id)
		built.free()
	for id in t.catalog.attachment_ids:
		if id=="extended":continue
		var data:=ModelFactory.attachment_info(id)
		t.check_that(ResourceLoader.exists(str(data.get("model",""))),"attachment_model_"+id)
	# The extended magazine lengthens the weapon's own magazine instead of adding a model.
	var extended:=ModelFactory.weapon(t.catalog.weapons["ar_a4"],["extended"])
	var magazine:=extended.get_node_or_null("Model/Magazine") as Node3D
	t.check_that(magazine!=null and magazine.scale.y>1.2,"extended_magazine_lengthens")
	extended.free()
	for optic in ["reflex","holographic"]:
		var model:=ModelFactory.scene(str(ModelFactory.attachment_info(optic).get("model","")))
		var lit:=false
		for mesh_instance in model.find_children("*","MeshInstance3D",true,false):
			for surface in mesh_instance.mesh.get_surface_count():
				var material:=mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
				if material!=null and material.emission_enabled and material.emission_texture!=null:lit=true
		t.check_that(lit,"emissive_reticle_"+optic)
		model.free()
	for kind in 2:
		var grenade:=ModelFactory.grenade(kind)
		t.check_that(grenade.find_children("*","MeshInstance3D",true,false).size()>0,"grenade_model_"+str(kind))
		grenade.free()
	arms_tests(t)
	iron_sight_tests(t)
	ModelFactory.sources.clear()

# First-person arms: the soldier's gloves and sleeves on its Mixamo rig, never skin.
static func arms_tests(t) -> void:
	t.check_that(ResourceLoader.exists(ARMS),"first_person_arms_model")
	var arms:=ModelFactory.scene(ARMS)
	var skeletons:=arms.find_children("*","Skeleton3D",true,false)
	t.check_that(skeletons.size()==1,"first_person_arms_skeleton")
	if skeletons.size()==1:
		var skeleton:Skeleton3D=skeletons[0]
		var required:=true
		for side in ["Left","Right"]:
			for part in ["Shoulder","Arm","ForeArm","Hand","HandIndex1","HandIndex3","HandMiddle1","HandRing1","HandPinky1","HandThumb1","HandThumb3"]:
				if skeleton.find_bone(side+part)<0:required=false
		t.check_that(required,"first_person_arms_ik_bones")
	var names:Array[String]=[];var labelled:=true;var triangles:=0
	for mesh_instance in arms.find_children("*","MeshInstance3D",true,false):
		triangles+=triangle_count(mesh_instance.mesh)
		t.check_that(mesh_instance.skin!=null,"first_person_arm_skinned_"+mesh_instance.name)
		for surface in mesh_instance.mesh.get_surface_count():
			var material:=mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			var label:=material.resource_name if material!=null else "<none>"
			names.append(label)
			if not label in ViewModel.ARM_PARTS:labelled=false
	t.check_that(not names.is_empty() and labelled and "FP_Glove" in names and "FP_Sleeve" in names,"gloves_and_sleeves",", ".join(names))
	# The builder samples the source textures under every kept face; any skin tone fails it.
	var build:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/models/arms/arms.json"))
	var skin:Dictionary=build.get("skin_texels",{}) if build is Dictionary else {"missing":1}
	var sampled:int=int(build.get("sampled_texels",0)) if build is Dictionary else 0
	t.check_that(sampled>1000 and skin.values().all(func(count):return int(count)==0),"no_skin_on_first_person_arms",str(skin))
	# Runtime materials are the soldier's sleeve and glove maps, never a skin texture.
	var view:=ViewModel.new()
	var textures:=true
	for label in names:
		for team in 2:
			var material:=view.arm_material(label,team) as BaseMaterial3D
			var path:=material.albedo_texture.resource_path if material!=null and material.albedo_texture!=null else ""
			if path=="" or "skin" in path.to_lower() or not "/characters/textures/" in path:textures=false
	t.check_that(textures,"first_person_arm_textures_are_soldier_maps")
	# The sleeve's trailing end dissolves (vertex alpha + hashed material), so a shoulder
	# pushed forward for a long reach never shows a cut end.
	var fades:=false
	for mesh_instance in arms.find_children("*","MeshInstance3D",true,false):
		for surface in mesh_instance.mesh.get_surface_count():
			var material:=mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if material==null or material.resource_name!="FP_Sleeve":continue
			var colours:Variant=mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
			if colours is PackedColorArray:
				for colour in colours:
					if colour.a<.05:fades=true
	var sleeve:=view.arm_material("FP_Sleeve",0) as BaseMaterial3D
	t.check_that(fades and sleeve!=null and sleeve.vertex_color_use_as_albedo and sleeve.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_HASH,"first_person_sleeve_end_fades")
	view.free()
	wrist_tests(t)
	t.check_that(triangles>6000 and triangles<=25000,"first_person_arms_budget",str(triangles))
	arms.free()

static func triangle_count(mesh:Mesh) -> int:
	var total:=0
	if mesh==null:return 0
	for surface in mesh.get_surface_count():
		var arrays:=mesh.surface_get_arrays(surface)
		var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		total+=(indices.size() if indices!=null else arrays[Mesh.ARRAY_VERTEX].size())/3
	return total

# Every weapon, hip and aimed, keeps both wrists inside their range of motion: the
# glove continues the forearm instead of snapping off it.
static func wrist_tests(t) -> void:
	var camera:=Camera3D.new();t.root.add_child(camera)
	var actor:=Combatant.new();t.root.add_child(actor)
	var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=LoadoutDefinition.new();actor.setup(slot,t.catalog)
	var hands:=ViewModel.new();camera.add_child(hands)
	var worst:=0.0;var worst_name:=""
	for index in t.catalog.weapon_ids.size():
		var id:String=t.catalog.weapon_ids[index]
		if index<12:slot.loadout.primary=StringName(id)
		else:slot.loadout.sidearm=StringName(id)
		actor.set_loadout(t.catalog)
		if index>=12:actor.switch_to(1,0.0)
		for state in ["hip","ads"]:
			actor.ads=state=="ads"
			hands.refresh(actor);hands.shown=true;hands.blend=1.0 if actor.ads else 0.0
			for i in 20:hands.tick(1.0/60,float(i)/60,0.0)
			for side in ["L","R"]:
				var bend:=hands.wrist_bend(side)
				if bend>worst:worst=bend;worst_name=id+" "+state+" "+side
		# The overarm throw, held cocked and released, sampled across its whole timeline.
		if index%4==0:
			actor.ads=false;hands.blend=0.0
			actor.action_kind="throw";actor.throw_started=0.0;actor.throw_holding=true;actor.action_until=60.0;actor.throw_at=-1
			for step in 12:
				hands.tick(1.0/60,.05*step,0.0)
				for side in ["L","R"]:
					var bend:=hands.wrist_bend(side)
					if bend>worst:worst=bend;worst_name=id+" throw cocked "+side
			actor.throw_holding=false;actor.throw_at=1.0+ThrowTimeline.RELEASE-ThrowTimeline.PULL;actor.action_until=1.0+ThrowTimeline.TOTAL-ThrowTimeline.PULL
			for step in 36:
				var moment:=1.0+.02*step
				hands.tick(1.0/60,moment,0.0)
				for side in ["L","R"]:
					var bend:=hands.wrist_bend(side)
					if bend>worst:worst=bend;worst_name=id+" throw t=%.2f "%(ThrowTimeline.seconds(actor,moment))+side
			actor.action_kind="";actor.action_until=0.0;actor.throw_at=-1
	t.check_that(worst<=48.0,"first_person_wrists_within_range",worst_name+" "+str(snappedf(worst,.1))+" degrees")
	hands.free();actor.free();camera.free()
	pistol_hold_tests(t)

# Two-handed pistol grip, hip and aimed, for every sidearm: the elbows point outward (the
# left elbow left of the left wrist, the right elbow right of the right wrist, in camera
# space) so the forearms form a V, and both wrists stay near neutral.
static func pistol_hold_tests(t) -> void:
	var camera:=Camera3D.new();t.root.add_child(camera)
	var actor:=Combatant.new();t.root.add_child(actor)
	var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=LoadoutDefinition.new();actor.setup(slot,t.catalog)
	var hands:=ViewModel.new();camera.add_child(hands)
	var worst:=0.0;var worst_name:=""
	var out_wrist:=1.0;var out_name:=""
	for id in t.catalog.weapon_ids:
		if t.catalog.weapons[id].category!="sidearm":continue
		slot.loadout.sidearm=StringName(id);actor.set_loadout(t.catalog);actor.switch_to(1,0.0)
		for state in ["hip","ads"]:
			actor.ads=state=="ads"
			hands.refresh(actor);hands.shown=true;hands.blend=1.0 if actor.ads else 0.0
			for i in 20:hands.tick(1.0/60,1.0+float(i)/60,0.0)
			var to_camera:=camera.global_transform.affine_inverse()*hands.skeleton.global_transform
			for side in ["L","R"]:
				var elbow:float=(to_camera*hands.skeleton.get_bone_global_pose(hands.bone(side,"ForeArm")).origin).x
				var wrist:float=(to_camera*hands.skeleton.get_bone_global_pose(hands.bone(side,"Hand")).origin).x
				# Positive when the elbow lies outside the wrist.
				var outward:=(wrist-elbow) if side=="L" else (elbow-wrist)
				if outward<out_wrist:out_wrist=outward;out_name=id+" "+state+" "+side
				var bend:=hands.wrist_bend(side)
				if bend>worst:worst=bend;worst_name=id+" "+state+" "+side
	t.check_that(out_wrist>.02,"pistol_elbows_point_outward",out_name+" "+str(snappedf(out_wrist,.001))+" m")
	t.check_that(worst<=30.0,"pistol_wrists_near_neutral",worst_name+" "+str(snappedf(worst,.1))+" degrees")
	hands.free();actor.free();camera.free()

# Iron sights (no optic) at full ADS: the front post lands on screen centre at 1280x720, so
# the rear notch and post line up through the eye. Integrated scopes are optics, not irons.
static func iron_sight_tests(t) -> void:
	var camera:=Camera3D.new();t.root.add_child(camera)
	var actor:=Combatant.new();t.root.add_child(actor)
	var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=LoadoutDefinition.new();actor.setup(slot,t.catalog)
	var hands:=ViewModel.new();camera.add_child(hands)
	var viewport:=Vector2(1280,720)
	var worst:=0.0;var worst_name:=""
	var magnified:=true;var dots:=true;var zoomed:=true;var rear_hidden:=true
	for index in t.catalog.weapon_ids.size():
		var id:String=t.catalog.weapon_ids[index]
		var definition:WeaponDefinition=t.catalog.weapons[id]
		if definition.category=="sniper":continue
		if index<12:slot.loadout.primary=StringName(id);slot.loadout.primary_attachments=[]
		else:slot.loadout.sidearm=StringName(id);slot.loadout.sidearm_attachments=[]
		actor.set_loadout(t.catalog)
		if index>=12:actor.switch_to(1,0.0)
		actor.ads=true;hands.refresh(actor);hands.shown=true;hands.blend=1.0
		# Start after the equip lift has ended (switch_to puts the weapon ready 0.35 s later).
		for i in 20:hands.tick(1.0/60,1.0+float(i)/60,0.0)
		var runtime:=actor.weapon()
		magnified=magnified and is_equal_approx(runtime.magnification,WeaponRuntime.IRON_MAGNIFICATION)
		camera.fov=rad_to_deg(2*atan(tan(deg_to_rad(75.0)*.5)/runtime.magnification))
		var weapon:Node3D=hands.weapon
		t.check_that(weapon.get_meta("optic")=="" and not weapon.get_meta("sight_is_eye"),"iron_sight_no_optic_"+id)
		var front:Vector3=weapon.get_meta("sight_front")
		var local:Vector3=camera.global_transform.affine_inverse()*(weapon.global_transform*front)
		var scale:=(viewport.y*.5)/tan(deg_to_rad(camera.fov)*.5)
		var offset:=Vector2(local.x/-local.z,-local.y/-local.z)*scale
		if offset.length()>worst:worst=offset.length();worst_name=id
		# Post and edge, plus three emissive dots on pistols.
		var irons:=weapon.get_node_or_null("IronSights")
		var parts:=irons.find_children("*","MeshInstance3D",true,false).size() if irons!=null else 0
		dots=dots and parts==(5 if definition.category=="sidearm" else 2)
		var rig_material:BaseMaterial3D=hands.rig_materials[0] if not hands.rig_materials.is_empty() else null
		zoomed=zoomed and is_equal_approx(hands.fov,ViewModel.ADS_FOV) and rig_material!=null and is_equal_approx(rig_material.fov_override,hands.fov)
		var rear:=weapon.get_node_or_null("Model/RearSight") as Node3D
		if rear!=null:rear_hidden=rear_hidden and not rear.visible and hands.ghost_ring()
	t.check_that(worst<6.0,"iron_front_post_centred_at_ads",worst_name+" "+str(snappedf(worst,.1))+" px")
	t.check_that(magnified,"iron_sight_magnification")
	t.check_that(dots,"iron_sight_post_and_pistol_dots")
	t.check_that(zoomed,"iron_sights_narrow_the_rig_field_of_view")
	t.check_that(rear_hidden,"aimed_peep_sight_puts_the_rear_leaf_away")
	knife_tests(t,actor,hands,camera)
	hands.free();actor.free();camera.free()

# The knife slash: the rifle drops away, the knife shows in the right hand at the strike, in
# front of the eye, its handle in the palm; it is put away before the action ends.
static func knife_tests(t,actor:Combatant,hands:ViewModel,camera:Camera3D) -> void:
	actor.switch_to(0,0.0);actor.ads=false;hands.refresh(actor);hands.blend=0
	for i in 30:hands.tick(1.0/60,1.0+float(i)/60,0.0)
	var problems:=[]
	for at in [Combatant.MELEE_HIT,.22]:
		actor.action_kind="melee";actor.action_until=5.0-at+Combatant.MELEE_TIME
		hands.tick(1.0/60,5.0,0.0)
		var local:=camera.global_transform.affine_inverse()*hands.knife.global_position
		var handle:=hands.knife.global_transform*Vector3(0,-ModelFactory.KNIFE_GRIP_Y,0)
		if not hands.knife.visible:problems.append("hidden at %.2f"%at)
		if local.z>-.15 or local.length()>.8:problems.append("knife at %s"%str(local))
		if hands.palm_point("R").distance_to(handle)>.07:problems.append("palm %.3f from handle"%hands.palm_point("R").distance_to(handle))
		if hands.weapon.visible:problems.append("rifle still in view")
	actor.action_until=5.0-.58+Combatant.MELEE_TIME;hands.tick(1.0/60,5.0,0.0)
	if hands.knife.visible:problems.append("knife still out at the end")
	t.check_that(problems.is_empty(),"knife_slash_in_hand_and_in_view",str(problems))
	var blade:=hands.knife.get_node("Blade") as MeshInstance3D
	t.check_that(blade!=null and blade.mesh.get_aabb().size.y>.15,"knife_model_has_a_blade")
	actor.action_kind="";actor.action_until=0
