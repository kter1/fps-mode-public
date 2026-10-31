extends SceneTree

# Renders the third-person soldiers (Blue left, Red right) through the real
# AnimationTree and pose modifier: idle, walk, aim, crouch (front, side, walking,
# against the crouched hurtboxes), reload, throw, melee, a weapon lineup (front and
# side, plus grip close-ups per weapon), then a ragdoll death sequence. Writes .artifacts/screenshots/operators/<pose>.png
# and prints the posed head height against the head hurtbox.

var actors: Array[Combatant] = []
var clock := 2.0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,720)
	var camera:=Camera3D.new();root.add_child(camera);camera.fov=40;camera.current=true;camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var environment:=WorldEnvironment.new();var sky_env:=Environment.new()
	var sky:=Sky.new();var material:=ProceduralSkyMaterial.new();material.sky_top_color=Color("6f8db0");material.sky_horizon_color=Color("b9c6cf");material.ground_horizon_color=Color("8a8d88");material.ground_bottom_color=Color("4a4d48");sky.sky_material=material
	sky_env.background_mode=Environment.BG_SKY;sky_env.sky=sky;sky_env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;sky_env.ambient_light_energy=.9
	sky_env.tonemap_mode=Environment.TONE_MAPPER_AGX;sky_env.ssao_enabled=true
	environment.environment=sky_env;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-32,0);sun.light_energy=1.6;sun.shadow_enabled=true;root.add_child(sun)
	var stage:=Node3D.new();root.add_child(stage)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1;var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,.2,20);floor_shape.shape=box;floor_body.add_child(floor_shape);floor_body.position.y=-.1;stage.add_child(floor_body)
	ModelFactory.primitive(stage,Vector3(20,.1,20),Vector3(0,-.05,0),Color("5d6062"))
	var catalog:=Catalog.new()
	for team in 2:
		var actor:=Combatant.new();root.add_child(actor);var slot:=ActorSlot.new();slot.id=team+1;slot.team=team;slot.loadout=LoadoutDefinition.new()
		if team==1:slot.loadout.primary=&"ar_k47"
		actor.setup(slot,catalog);actor.position=Vector3(-.75+team*1.5,0,0);actor.yaw=PI*.8;actor.rotation.y=actor.yaw;actors.append(actor)
	var title:=Label.new();title.position=Vector2(28,28);title.add_theme_font_size_override("font_size",25);root.add_child(title)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/operators")
	var facing:=Basis(Vector3.UP,PI*.8)
	var hurtboxes:=hurtbox_meshes(actors[0])
	for pose in ["idle","profile","hands","walk","aim","crouch","crouch_side","crouch_walk_side","crouch_hurtbox","stand_hurtbox","reload","throw","melee"]:
		var side:bool=pose.ends_with("_side") or pose.ends_with("_hurtbox")
		var low:bool=pose.begins_with("crouch")
		camera.position=Vector3(2.6,1.35 if not low else 1.0,3.6);camera.look_at(Vector3(0,.95 if not low else .6,0))
		if pose=="profile":camera.position=Vector3(-.75,1.3,0)+facing*Vector3(3.2,0,0);camera.look_at(Vector3(-.75,1.0,0))
		if pose=="hands":camera.position=Vector3(-.75,1.45,0)+facing*Vector3(.75,.05,-.95);camera.look_at(Vector3(-.75,1.33,0)+facing*Vector3(.1,0,-.3))
		if side:
			var target:=Vector3(-.75,.62 if low else .95,0)+facing*Vector3(0,0,-.2)
			camera.position=target+facing*Vector3(2.7 if low else 3.4,.05,0);camera.look_at(target)
		actors[1].visual.visible=not side
		for mesh in hurtboxes:mesh.visible=pose.ends_with("_hurtbox")
		for actor in actors:
			actor.crouched=low;actor.ads=pose=="aim";actor.pitch=-.12 if pose=="aim" else 0.0
			actor.velocity=facing*Vector3(0,0,-1.9 if pose=="walk" else -2.5) if pose in ["walk","crouch_walk_side"] else Vector3.ZERO
			place_hurtboxes(hurtboxes,low)
			actor.weapon().cancel_reload();actor.action_kind="";actor.action_until=0
			actor.update_animation(clock)
		var hold:float={"reload":.9,"throw":.4,"melee":.18}.get(pose,1.2)
		var started:=clock
		for actor in actors:
			if pose=="reload":actor.weapon().ammo=3;actor.weapon().start_reload(clock)
			if pose=="melee":actor.action_kind=pose;actor.action_until=clock+.8
			if pose=="throw":actor.action_kind=pose;actor.throw_started=clock;actor.throw_holding=false;actor.throw_at=clock+ThrowTimeline.RELEASE;actor.action_until=clock+ThrowTimeline.TOTAL
		await step(hold)
		if pose=="aim":
			for actor in actors:actor.weapon().last_shot_at=clock-.03
			await step(.02)
		title.text="SOLDIERS / "+pose.to_upper()+("  t=%.2fs"%(clock-started) if pose in ["reload","throw","melee"] else "")
		await capture(pose)
		if pose in ["crouch_side","crouch_walk_side","stand_hurtbox"]:await measure(actors[0],pose)
	actors[1].visual.visible=true
	for mesh in hurtboxes:mesh.queue_free()
	# Weapon lineup: grips on an SMG, shotgun, LMG, bolt-action, bullpup and pistol.
	var main:=actors;actors=[]
	for actor in main:actor.visual.visible=false
	for i in 6:
		var actor:=Combatant.new();root.add_child(actor);var slot:=ActorSlot.new();slot.id=10+i;slot.team=i%2;slot.loadout=LoadoutDefinition.new()
		slot.loadout.primary=[&"smg_mp9",&"sg_p12",&"lmg_l56",&"sniper_s90",&"ar_b56",&"ar_a4"][i]
		actor.setup(slot,catalog);actor.position=Vector3(-2.9+i*1.16,0,-1.5);actor.yaw=PI*.8;actor.rotation.y=actor.yaw;actors.append(actor)
		if i==5:actor.switch_to(1,clock)
	camera.position=Vector3(.6,1.5,4.6);camera.look_at(Vector3(-.1,1.0,-1.5))
	await step(1.2)
	title.text="SOLDIERS / WEAPON LINEUP";await capture("lineup")
	for actor in actors:actor.yaw=PI*.5;actor.rotation.y=actor.yaw
	await step(.6)
	title.text="SOLDIERS / WEAPON LINEUP, SIDE";await capture("lineup_side")
	# Close-ups of both hands on each lineup weapon, from the support-hand side.
	for actor in actors:actor.yaw=PI*.8;actor.rotation.y=actor.yaw
	await step(.4)
	for actor in actors:
		var turn:=Basis(Vector3.UP,actor.yaw)
		camera.position=actor.position+turn*Vector3(-.62,1.5,-.78);camera.look_at(actor.position+turn*Vector3(.06,1.3,-.22))
		var id:=str(actor.weapon().definition.id)
		title.text="SOLDIERS / GRIP "+id.to_upper();await capture("grip_"+id)
	for actor in actors:actor.free()
	actors=main
	for actor in actors:actor.visual.visible=true
	# Ragdoll: both fall from a run, shot from the front (Blue) and from the side (Red).
	camera.position=Vector3(3.4,2.2,4.2);camera.look_at(Vector3(0,.4,-.4))
	for actor in actors:actor.velocity=Basis(Vector3.UP,actor.yaw)*Vector3(0,0,-4.5);actor.update_animation(clock)
	await step(.5)
	var corpses:Array[Node3D]=[]
	for i in actors.size():
		var actor:=actors[i]
		var direction:=Basis(Vector3.UP,actor.yaw)*(Vector3(0,0,1) if i==0 else Vector3(1,0,0))
		corpses.append(SoldierFactory.corpse(stage,actor,direction));actor.visual.visible=false
	var died:=clock
	for frame in [["death_hit",.12],["death_fall",.45],["death",1.6]]:
		await step(frame[1])
		title.text="SOLDIERS / RAGDOLL t=%.2fs"%(clock-died)
		await capture(frame[0])
	for corpse in corpses:corpse.free()
	for actor in actors:actor.free()
	ModelFactory.sources.clear();await process_frame;print("OPERATOR INSPECTION PASS / 24 SHEETS");quit()

func step(seconds: float) -> void:
	var ticks:=maxi(1,roundi(seconds*60))
	for i in ticks:
		clock+=1.0/60
		for actor in actors:
			if actor.visual.visible:actor.update_animation(clock);actor.update_gun_pose()
		await physics_frame

# Translucent stand-ins for the head and torso hurtboxes (same sizes and heights as
# Combatant.simulate_movement uses), to judge how well the posed body covers them.
func hurtbox_meshes(actor: Combatant) -> Array[MeshInstance3D]:
	var finish:=StandardMaterial3D.new();finish.albedo_color=Color(1,.15,.1,.28);finish.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;finish.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	var head:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.19;sphere.height=.38;head.mesh=sphere
	var torso:=MeshInstance3D.new();var capsule:=CapsuleMesh.new();capsule.radius=.32;torso.mesh=capsule
	for mesh in [head,torso]:mesh.material_override=finish;mesh.visible=false;actor.add_child(mesh)
	return [head,torso]

func place_hurtboxes(meshes: Array[MeshInstance3D], crouched: bool) -> void:
	var height:=1.1 if crouched else 1.8
	meshes[0].position.y=height-(.10 if crouched else .15)
	meshes[1].position.y=(height-.34)*.5;(meshes[1].mesh as CapsuleMesh).height=height-.34

# Head height in the final pose (after the pose modifier) versus the head hurtbox.
func measure(actor: Combatant, pose: String) -> void:
	var skeleton:=actor.skeleton
	var heads:Array[float]=[]
	var probe:=func() -> void:heads.append((skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Head"))).origin.y-actor.global_position.y)
	skeleton.skeleton_updated.connect(probe)
	await step(.1)
	skeleton.skeleton_updated.disconnect(probe)
	var hurtbox:=1.0 if actor.crouched else 1.65
	print("HEAD %s head_bone=%.3f head_centre~%.3f hurtbox_centre=%.3f"%[pose,heads.max(),heads.max()+.1,hurtbox])

func capture(name: String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://.artifacts/screenshots/operators/"+name+".png")
