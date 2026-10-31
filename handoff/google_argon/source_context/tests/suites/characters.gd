extends RefCounted

# Content checks for the third-person soldier (tools/blender/ingest_soldier.py output):
# scale and facing, named in-place clips, triangle budgets per LOD, PBR maps per
# material, distinct team finishes, and the bones the pose modifier and ragdoll use.
const CLIPS := ["idle", "crouch_idle", "airborne", "sprint_f", "sprint_fl", "sprint_fr", "death_front", "death_back"]
const BONES := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "RightShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot", "LeftHandMiddle1", "RightHandMiddle1", "RightHandIndex3", "LeftHandThumb3"]

static func run(t) -> void:
	t.check_that(ResourceLoader.exists(SoldierFactory.MODEL),"soldier_model")
	var soldier:=ModelFactory.scene(SoldierFactory.MODEL)
	var bounds:=ModelFactory.bounds(soldier)
	t.check_that(bounds.size.y>1.75 and bounds.size.y<1.85 and absf(bounds.position.y)<.03,"soldier_height_1_8m","height=%.3f floor=%.3f"%[bounds.size.y,bounds.position.y])
	var skeleton:=SoldierFactory.skeleton_of(soldier)
	var missing:=BONES.filter(func(bone:String)->bool:return skeleton==null or skeleton.find_bone(bone)<0)
	t.check_that(missing.is_empty() and skeleton.get_bone_count()==52,"soldier_rig_bones",str(missing))
	t.check_that(skeleton!=null and not skeleton.get_concatenated_bone_names().contains("mixamorig"),"soldier_bone_names_unprefixed")
	t.check_that(skeleton!=null and skeleton.get_bone_global_rest(skeleton.find_bone("LeftHand")).origin.x<-.5,"soldier_faces_minus_z")
	var player:=ModelFactory.animation_player(soldier)
	var clips:=CLIPS.duplicate()
	for prefix in ["walk_","run_","crouch_"]:
		for direction in SoldierFactory.DIRECTIONS:clips.append(prefix+direction)
	var absent:=clips.filter(func(clip:String)->bool:return player==null or not player.has_animation(clip))
	t.check_that(absent.is_empty(),"soldier_clips_named","%d clips, missing %s"%[clips.size(),str(absent)])
	var travel:=0.0
	for clip in ["walk_f","run_f","run_l","crouch_f","sprint_f"]:
		if player==null or not player.has_animation(clip):continue
		var animation:=player.get_animation(clip)
		var track:=animation.find_track(NodePath("Armature/Skeleton3D:Hips"),Animation.TYPE_POSITION_3D)
		if track>=0:
			var offset:=animation.position_track_interpolate(track,animation.length)-animation.position_track_interpolate(track,0)
			travel=maxf(travel,Vector2(offset.x,offset.z).length())
	t.check_that(travel<.05,"soldier_clips_in_place","max hip travel per cycle %.3f m"%travel)
	var clip_table:Dictionary=SoldierFactory.info().get("clips",{})
	t.check_that(absf(SoldierFactory.velocity(clip_table,"run_f").y-4.76)<.5 and SoldierFactory.velocity(clip_table,"walk_r").x>1,"soldier_clip_speeds_recorded")
	var levels:=[0,0,0,0,0,0]
	for instance in soldier.find_children("*","MeshInstance3D",true,false):
		for surface in instance.mesh.get_surface_count():
			var data:=RenderingServer.mesh_get_surface(instance.mesh.get_rid(),surface)
			var index_bytes:=4 if int(data.get("vertex_count",0))>65535 else 2
			levels[0]+=instance.mesh.surface_get_array_index_len(surface)/3
			var lods:Array=data.get("lods",[])
			for level in mini(lods.size(),5):levels[level+1]+=lods[level].index_data.size()/(3*index_bytes)
	var mid:=levels.slice(1).any(func(count:int)->bool:return count>0 and count<=10000)
	var far:=levels.slice(1).any(func(count:int)->bool:return count>0 and count<=3000)
	t.check_that(levels[0]<=30000 and mid and far,"soldier_lod_budget","triangles per LOD "+str(levels))
	for part in ["body","gear"]:
		var maps:Dictionary=SoldierFactory.info().get("textures",{}).get(part,{})
		var ok:=maps.size()==4
		for key in ["albedo_blue","albedo_red","normal","orm"]:
			var texture:Texture2D=load(maps.get(key,"")) if ResourceLoader.exists(maps.get(key,"")) else null
			ok=ok and texture!=null and texture.get_width()<=2048 and texture.get_height()<=2048
		t.check_that(ok,"soldier_pbr_textures_"+part)
	var blue:=SoldierFactory.finish(0,"body");var red:=SoldierFactory.finish(1,"body")
	t.check_that(blue!=red and blue.albedo_texture!=red.albedo_texture and blue.normal_texture==red.normal_texture and blue.roughness_texture!=null,"soldier_team_finishes")
	var ragdoll_bones:=SoldierFactory.RAGDOLL.filter(func(spec:Array)->bool:return skeleton.find_bone(spec[0])<0 or (spec[1]!="" and skeleton.find_bone(spec[1])<0))
	t.check_that(ragdoll_bones.is_empty() and SoldierFactory.MAX_RAGDOLLS==6,"soldier_ragdoll_bones")
	ragdoll_joints(t,skeleton)
	var sources:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(SoldierFactory.MANIFEST)).get("assets",{})
	t.check_that(sources.has("mixamo_swat_guy") and sources.mixamo_swat_guy.source=="manual","soldier_source_recorded")
	soldier.free();ModelFactory.sources.clear()

# Every ragdoll body but the pelvis hangs on a limited joint (hinges for knees and
# elbows, tight cones for the spine and neck) and is damped, grippy and dead: no
# bounce, mass spread like a real body, no rubber limbs.
static func ragdoll_joints(t, skeleton: Skeleton3D) -> void:
	var frame:=SoldierFactory.character_frame(skeleton)
	var unlimited:=[];var loose:=[];var undamped:=[];var slippery:=[]
	var total:=0.0
	var hinges:=0
	var tight:=true
	for spec in SoldierFactory.RAGDOLL:
		var body:=SoldierFactory.ragdoll_bone(skeleton,spec,frame)
		total+=body.mass
		if spec[4]=="root":
			body.free()
			continue
		if body.joint_type==PhysicalBone3D.JOINT_TYPE_NONE:unlimited.append(spec[0])
		if body.joint_type==PhysicalBone3D.JOINT_TYPE_HINGE:
			hinges+=1
			if not body.get("joint_constraints/angular_limit_enabled"):unlimited.append(spec[0])
			if float(body.get("joint_constraints/angular_limit_upper"))-float(body.get("joint_constraints/angular_limit_lower"))>150.0:loose.append(spec[0])
		if body.joint_type==PhysicalBone3D.JOINT_TYPE_6DOF:
			for axis in ["x","y","z"]:
				if not body.get("joint_constraints/"+axis+"/angular_limit_enabled"):unlimited.append(spec[0]+axis)
				var span:float=float(body.get("joint_constraints/"+axis+"/angular_limit_upper"))-float(body.get("joint_constraints/"+axis+"/angular_limit_lower"))
				if spec[4] in ["spine","neck"] and span>64.0:tight=false
				if span>190.0:loose.append(spec[0]+axis)
		if body.angular_damp<2.0 or body.linear_damp<.2:undamped.append(spec[0])
		if body.friction<.8 or body.bounce>0.0:slippery.append(spec[0])
		body.free()
	t.check_that(unlimited.is_empty() and hinges==4,"ragdoll_joints_have_limits",str(unlimited)+" hinges=%d"%hinges)
	t.check_that(loose.is_empty() and tight,"ragdoll_no_rubber_limbs",str(loose)+" tight=%s"%tight)
	t.check_that(undamped.is_empty(),"ragdoll_bodies_damped",str(undamped))
	t.check_that(slippery.is_empty(),"ragdoll_bodies_grip_and_dont_bounce",str(slippery))
	t.check_that(total>75.0 and total<100.0,"ragdoll_mass_is_a_soldier_in_kit","%.1f kg"%total)

# Physics and presentation checks that need frames; run from the integration suite.
static func integration(t) -> void:
	Combatant.force_visuals=true
	await dead_weight(t)
	await weapon_stays_visible(t)
	await muzzle_stays_outside_body(t)
	Combatant.force_visuals=false

static func origin_of(simulator: Node, bone: String) -> Vector3:
	var body:PhysicalBone3D=simulator.get_node(bone)
	return (body.global_transform*body.body_offset.affine_inverse()).origin

# Degrees a limb is bent at its middle joint (0 = straight).
static func bend_of(simulator: Node, upper: String, middle: String, end: String) -> float:
	var a:=origin_of(simulator,upper);var b:=origin_of(simulator,middle);var c:=origin_of(simulator,end)
	return rad_to_deg((b-a).angle_to(c-b))

# A soldier killed standing, running and crouched falls as dead weight: the knees and
# elbows never bend backwards, nothing flies off, and the corpse lies below a speed
# threshold within three seconds, when it freezes.
static func dead_weight(t) -> void:
	var stage:=Node3D.new();t.root.add_child(stage)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var floor_shape:=CollisionShape3D.new();var slab:=BoxShape3D.new();slab.size=Vector3(40,.2,40);floor_shape.shape=slab;floor_body.add_child(floor_shape);floor_body.position.y=-.1;stage.add_child(floor_body)
	var worst:=[]
	for case in [["idle",Vector3.ZERO,Vector3(0,0,1)],["run_f",Vector3(0,0,-4.7),Vector3(0,0,1)],["sprint_f",Vector3(0,0,-7),Vector3(1,0,0)],["crouch_idle",Vector3.ZERO,Vector3(0,0,-1)]]:
		var model_root:=SoldierFactory.soldier(0);stage.add_child(model_root)
		var player:=ModelFactory.animation_player(model_root.get_node("Model"))
		player.play(case[0]);player.seek(.3,true);player.advance(0)
		var victim:=Combatant.new();stage.add_child(victim)
		victim.slot=ActorSlot.new();victim.slot.team=0
		victim.skeleton=SoldierFactory.skeleton_of(model_root.get_node("Model"));victim.visual=model_root;victim.velocity=case[1]
		var body:=SoldierFactory.corpse(stage,victim,case[2])
		var driver:RagdollDriver=body.get_node("Driver")
		var simulator:Node=body.find_child("Ragdoll",true,false)
		var start:=origin_of(simulator,"Hips")
		var lowest_bend:=INF;var highest_bend:=-INF;var farthest:=0.0;var frames:=0
		while driver.settled_at<0 and frames<240:
			await t.physics_frame
			frames+=1
			if driver.settled_at>=0:break
			for limb in [["LeftUpLeg","LeftLeg","LeftFoot"],["RightUpLeg","RightLeg","RightFoot"],["LeftArm","LeftForeArm","LeftForeArm"]]:
				if limb[1]==limb[2]:continue
				var bend:=bend_of(simulator,limb[0],limb[1],limb[2])
				lowest_bend=minf(lowest_bend,bend);highest_bend=maxf(highest_bend,bend)
			farthest=maxf(farthest,(origin_of(simulator,"Hips")-start).length())
		var detail:="%s settled=%.2fs peak=%.2fm/s final=%.3fm/s drift=%.2fm bend=[%.0f,%.0f]"%[case[0],driver.settled_at,driver.peak_speed,driver.final_speed,farthest,lowest_bend,highest_bend]
		worst.append(detail)
		t.check_that(driver.settled_at>=0.5 and driver.settled_at<=3.0,"corpse_settles_within_3s_"+case[0],detail)
		t.check_that(driver.final_speed<.2,"corpse_is_still_when_it_freezes_"+case[0],detail)
		t.check_that(driver.peak_speed<9.0 and farthest<3.5,"corpse_does_not_fly_"+case[0],detail)
		t.check_that(highest_bend<150.0 and lowest_bend>-12.0,"corpse_knees_do_not_hyperextend_"+case[0],detail)
		var settled:=body.find_child("Ragdoll",true,false)
		t.check_that(settled==null or settled.is_queued_for_deletion(),"corpse_simulation_stops_"+case[0])
		body.queue_free();victim.queue_free();model_root.queue_free()
		await t.physics_frame
	stage.queue_free()

# Builds the visible soldier with its real weapon in a headless run.
static func soldier_with(t, weapon: StringName) -> Combatant:
	var actor:=Combatant.new();t.root.add_child(actor)
	var slot:=ActorSlot.new();slot.id=1;slot.team=0;slot.loadout=LoadoutDefinition.new()
	slot.loadout.primary=weapon
	actor.setup(slot,t.catalog)
	return actor

static func tick(t, actor: Combatant, clock: Array, count: int) -> void:
	for i in count:
		clock[0]+=1.0/60
		actor.update_animation(clock[0]);actor.update_gun_pose()
		await t.physics_frame

# Why a gun is not visible, or "" when it is: missing, hidden, thrown off the body, or
# every mesh culled (the weapon draws either its detailed parts or its LOD mesh).
static func gun_problem(actor: Combatant) -> String:
	var gun:=actor.gun
	if gun==null or not is_instance_valid(gun) or not gun.is_inside_tree():return "no gun"
	if not gun.is_visible_in_tree():return "hidden"
	var origin:=gun.global_position
	if not (is_finite(origin.x) and is_finite(origin.y) and is_finite(origin.z)):return "not finite"
	if origin.distance_to(actor.global_position+Vector3.UP)>1.5:return "far from body %.2f"%origin.distance_to(actor.global_position)
	var drawn:=0
	for node in gun.get_node("Model").get_children():
		if node is GeometryInstance3D and node.visible and node.visibility_range_begin==0.0 and node.visibility_range_end==0.0:drawn+=1
	return "" if drawn>0 else "no visible mesh"

# The third-person gun stays drawn through a scripted run of weapon swaps, reloads, a
# grenade throw, sprinting, death and respawn, and weapon LOD never leaves a distance
# where neither the detailed parts nor the LOD mesh are drawn.
static func weapon_stays_visible(t) -> void:
	var clock:=[2.0]
	var actor:=soldier_with(t,&"ar_a4")
	var problems:=[]
	var check:=func(step: String) -> void:
		var problem:=gun_problem(actor)
		if problem!="":problems.append(step+": "+problem)
	await tick(t,actor,clock,10);check.call("spawn")
	actor.switch_to(1,clock[0]);await tick(t,actor,clock,10);check.call("swap to sidearm")
	actor.switch_to(0,clock[0]);await tick(t,actor,clock,10);check.call("swap to primary")
	actor.weapon().ammo=3;actor.weapon().start_reload(clock[0])
	for i in 6:
		await tick(t,actor,clock,8);check.call("reload %d"%i)
	actor.weapon().cancel_reload();actor.weapon().state="READY"
	actor.action_kind="throw";actor.throw_started=clock[0];actor.throw_holding=true;actor.action_until=clock[0]+60
	await tick(t,actor,clock,15);check.call("throw cook")
	actor.throw_holding=false;actor.throw_at=clock[0]+ThrowTimeline.RELEASE-ThrowTimeline.PULL;actor.action_until=actor.throw_at+ThrowTimeline.TOTAL-ThrowTimeline.RELEASE
	for i in 6:
		await tick(t,actor,clock,8);check.call("throw %d"%i)
	actor.action_kind="";actor.action_until=0;actor.throw_at=-1
	actor.velocity=Vector3(0,0,-7);actor.sprinting=true
	for i in 6:
		await tick(t,actor,clock,10);check.call("sprint %d"%i)
	# Death hides the soldier, respawn brings him back with a fresh weapon.
	actor.alive=false;actor.visual.visible=false
	await tick(t,actor,clock,3)
	actor.respawn(Vector3(0,.1,0),clock[0],t.catalog);actor.visual.visible=true
	await tick(t,actor,clock,3);check.call("respawn")
	t.check_that(problems.is_empty(),"third_person_gun_visible_across_swap_reload_throw_sprint_respawn",str(problems.slice(0,4)))
	var seams:=[]
	for id in t.catalog.weapons:
		var gun:=ModelFactory.weapon(t.catalog.weapons[id],[] as Array[String])
		var far:=false
		for step in 1600:
			var distance:=step*.05
			if step>=800:distance=(1600-step)*.05
			far=ModelFactory.far_weapon(distance,far)
			ModelFactory.set_weapon_detail(gun,not far)
			var detailed:=0;var lod:=0
			for node in gun.get_node("Model").get_children():
				if node is GeometryInstance3D:
					if node.visibility_range_begin!=0.0 or node.visibility_range_end!=0.0:seams.append(str(id)+" ranged "+node.name)
					if node.visible:
						if node.name=="LOD":lod+=1
						else:detailed+=1
			if (detailed==0)==(lod==0):seams.append("%s at %.2f m detailed=%d lod=%d"%[id,distance,detailed,lod]);break
		gun.free()
	t.check_that(seams.is_empty(),"weapon_lod_always_draws_exactly_one_representation",str(seams.slice(0,4)))
	actor.free()

# Poses that put the rifle across the body: the muzzle and the barrel in front of the
# receiver stay outside the drawn head, torso and legs (SoldierFactory.body_shapes).
static func muzzle_stays_outside_body(t) -> void:
	var clock:=[2.0]
	var failures:=[]
	var tightest:=INF
	for case in [["aim","ar_a4"],["run","ar_k47"],["sprint","ar_a4"],["sprint","sg_p12"],["sprint","sniper_s90"],["crouch","ar_a4"],["crouch_walk","smg_mp9"],["reload","ar_k47"],["throw","ar_a4"],["throw","sg_p12"],["melee","ar_a4"],["aim","lmg_l56"],["aim","pistol_p9"]]:
		var pose:String=case[0]
		var actor:=soldier_with(t,case[1])
		if str(case[1]).begins_with("pistol"):actor.switch_to(1,clock[0])
		actor.crouched=pose.begins_with("crouch");actor.ads=pose=="aim";actor.pitch=-.05
		actor.velocity={"run":Vector3(0,0,-4.7),"sprint":Vector3(0,0,-7),"crouch_walk":Vector3(0,0,-2.5)}.get(pose,Vector3.ZERO)
		actor.sprinting=pose=="sprint"
		match pose:
			"reload":actor.weapon().ammo=3;actor.weapon().start_reload(clock[0])
			"melee":actor.action_kind="melee";actor.action_until=clock[0]+.8
			"throw":actor.action_kind="throw";actor.throw_started=clock[0];actor.throw_holding=false;actor.throw_at=clock[0]+ThrowTimeline.RELEASE;actor.action_until=clock[0]+ThrowTimeline.TOTAL
		# Sample a full second so every phase of a stride, reload or throw is covered.
		for sample in 24:
			await tick(t,actor,clock,3 if pose!="throw" else 2)
			var found:=[]
			SoldierFactory.at_final_pose(actor.skeleton,actor.visual,func() -> void:found.append(SoldierFactory.gun_clearance(actor)))
			var clearance:Dictionary=found[0]
			tightest=minf(tightest,minf(clearance.muzzle,clearance.barrel))
			if clearance.muzzle<MUZZLE_CLEAR or clearance.barrel<BARREL_CLEAR:
				failures.append("%s %s muzzle=%.3f barrel=%.3f"%[pose,case[1],clearance.muzzle,clearance.barrel]);break
		actor.free()
	t.check_that(failures.is_empty(),"muzzle_stays_outside_body_in_every_pose",str(failures.slice(0,4))+" tightest=%.3f"%tightest)

const MUZZLE_CLEAR := .04
const BARREL_CLEAR := .0
