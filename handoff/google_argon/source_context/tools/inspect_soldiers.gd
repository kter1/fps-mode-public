extends SceneTree

# Review sheets for the third-person soldier, rendered through the real Combatant,
# AnimationTree, pose modifier and ragdoll:
#   .artifacts/screenshots/soldiers/death_<n>.png   one death per sheet, side view, a frame every 0.25 s
#   .artifacts/screenshots/soldiers/pose_<name>.png one pose per sheet: side, front quarter and front views
# and prints the muzzle clearance (metres outside the drawn body, negative = inside)
# for every pose. Run with: python3 tools/inspect_soldiers.py
# Arguments after "--": any of poses, deaths, gun, legacy to run only those (default all); gun counts the gun's visible
# pixels (a magenta-painted weapon) at camera distances around the weapon LOD switch;
# legacy does the same with the old per-mesh visibility ranges, for comparison.

const POSES := ["aim", "run", "sprint", "crouch", "crouch_walk", "reload", "throw", "melee", "pistol", "shotgun", "lmg"]
const DEATHS := [
	{"pose": "aim", "weapon": "ar_a4", "velocity": Vector3.ZERO, "hit": Vector3(0, 0, 1), "crouch": false},
	{"pose": "run", "weapon": "ar_k47", "velocity": Vector3(0, 0, -4.7), "hit": Vector3(0, 0, -1), "crouch": false},
	{"pose": "crouch", "weapon": "smg_mp9", "velocity": Vector3.ZERO, "hit": Vector3(-.6, 0, .8), "crouch": true},
	{"pose": "sprint", "weapon": "sg_p12", "velocity": Vector3(0, 0, -7.0), "hit": Vector3(.6, 0, .8), "crouch": false},
]
const FRAME := Vector2i(640, 440)

var clock := 2.0
var camera: Camera3D
var title: Label
var stage: Node3D
var catalog: Catalog

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,880)
	camera=Camera3D.new();root.add_child(camera);camera.fov=30;camera.current=true;camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var environment:=WorldEnvironment.new();var sky_env:=Environment.new()
	var sky:=Sky.new();var material:=ProceduralSkyMaterial.new();material.sky_top_color=Color("6f8db0");material.sky_horizon_color=Color("b9c6cf");material.ground_horizon_color=Color("8a8d88");material.ground_bottom_color=Color("4a4d48");sky.sky_material=material
	sky_env.background_mode=Environment.BG_SKY;sky_env.sky=sky;sky_env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY;sky_env.ambient_light_energy=.9
	sky_env.tonemap_mode=Environment.TONE_MAPPER_AGX
	environment.environment=sky_env;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-32,0);sun.light_energy=1.6;sun.shadow_enabled=true;root.add_child(sun)
	stage=Node3D.new();root.add_child(stage)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1;var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(40,.2,40);floor_shape.shape=box;floor_body.add_child(floor_shape);floor_body.position.y=-.1;stage.add_child(floor_body)
	# Checker floor so motion and sliding read in stills.
	for x in range(-8,8):
		for z in range(-8,8):
			if (x+z)%2==0:ModelFactory.primitive(stage,Vector3(1,.02,1),Vector3(x+.5,-.01,z+.5),Color("565a5c"))
	ModelFactory.primitive(stage,Vector3(20,.1,20),Vector3(0,-.07,0),Color("686c6e"))
	title=Label.new();title.position=Vector2(14,10);title.add_theme_font_size_override("font_size",22);root.add_child(title)
	catalog=Catalog.new()
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/soldiers")
	var only:=OS.get_cmdline_user_args()
	var everything:=only.is_empty()
	if everything or "poses" in only:await poses()
	if everything or "deaths" in only:await deaths()
	if everything or "gun" in only:await gun_visibility(false)
	if everything or "legacy" in only:await gun_visibility(true)
	ModelFactory.sources.clear();await process_frame;print("SOLDIER INSPECTION PASS");quit()

func soldier(weapon: StringName, team := 0) -> Combatant:
	var actor:=Combatant.new();root.add_child(actor);var slot:=ActorSlot.new();slot.id=team+1;slot.team=team;slot.loadout=LoadoutDefinition.new()
	if weapon.begins_with("pistol"):
		slot.loadout.sidearm=weapon
	else:slot.loadout.primary=weapon
	actor.setup(slot,catalog);actor.position=Vector3.ZERO;actor.yaw=0;actor.rotation.y=0
	if weapon.begins_with("pistol"):actor.switch_to(1,clock)
	return actor

# Runs the animation for a while with the same settings the game uses each tick.
func step(actors: Array, seconds: float) -> void:
	var ticks:=maxi(1,roundi(seconds*60))
	for i in ticks:
		clock+=1.0/60
		for actor in actors:
			if actor.visual.visible:actor.update_animation(clock);actor.update_gun_pose()
		await physics_frame

func configure(actor: Combatant, pose: String, velocity: Vector3) -> void:
	actor.crouched=pose.begins_with("crouch")
	actor.ads=pose=="aim"
	actor.sprinting=pose=="sprint"
	actor.pitch=-.05
	actor.velocity=velocity
	actor.weapon().cancel_reload();actor.action_kind="";actor.action_until=0;actor.throw_at=-1;actor.throw_holding=false
	match pose:
		"reload":actor.weapon().ammo=3;actor.weapon().start_reload(clock)
		"melee":actor.action_kind="melee";actor.action_until=clock+.8
		"throw":actor.action_kind="throw";actor.throw_started=clock;actor.throw_holding=false;actor.throw_at=clock+ThrowTimeline.RELEASE;actor.action_until=clock+ThrowTimeline.TOTAL

func poses() -> void:
	var cases:={
		"aim":["ar_a4",Vector3.ZERO,1.2],"run":["ar_k47",Vector3(0,0,-4.7),1.2],"sprint":["ar_a4",Vector3(0,0,-7.0),1.4],
		"crouch":["ar_a4",Vector3.ZERO,1.4],"crouch_walk":["smg_mp9",Vector3(0,0,-2.5),1.4],"reload":["ar_k47",Vector3.ZERO,.9],
		"throw":["ar_a4",Vector3.ZERO,.34],"melee":["ar_a4",Vector3.ZERO,.2],"pistol":["pistol_p9",Vector3.ZERO,1.2],
		"shotgun":["sg_p12",Vector3.ZERO,1.2],"lmg":["lmg_l56",Vector3.ZERO,1.2]}
	for pose in POSES:
		var spec:Array=cases[pose]
		var actor:=soldier(spec[0],0 if pose!="run" else 1)
		configure(actor,pose,spec[1])
		await step([actor],spec[2])
		var sheet:=Image.create(FRAME.x*3,FRAME.y,false,Image.FORMAT_RGB8)
		var height:=1.0 if actor.crouched else 1.35
		var focus:=Vector3(0,.95 if not actor.crouched else .6,-.15)
		var views:=[["side",Vector3(3.5,height,0),focus],["quarter",Vector3(-2.5,height+.1,-2.6),focus],["front",Vector3(.7,height,-3.4),focus]]
		var report:=PackedStringArray()
		for view in views:
			camera.position=view[1];camera.look_at(view[2])
			title.text="%s / %s"%[pose.to_upper(),view[0]]
			await process_frame;RenderingServer.force_draw(false)
			var shot:=root.get_texture().get_image();shot.resize(FRAME.x,FRAME.y,Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(shot,Rect2i(0,0,FRAME.x,FRAME.y),Vector2i(FRAME.x*views.find(view),0))
		sheet.save_png("res://.artifacts/screenshots/soldiers/pose_%s.png"%pose)
		print("POSE %s clearance=%s"%[pose,clearance_report(actor)])
		actor.free()

# Muzzle and forward-barrel clearance from the drawn body, after the pose modifier.
func clearance_report(actor: Combatant) -> String:
	var found:=[]
	var skeleton:=actor.skeleton
	var probe:=func() -> void:found.append(SoldierFactory.gun_clearance(actor))
	skeleton.skeleton_updated.connect(probe)
	actor.update_animation(clock+.1);skeleton.advance(0.0)
	skeleton.skeleton_updated.disconnect(probe)
	return str(found[0]) if not found.is_empty() else "n/a"

func deaths() -> void:
	for index in DEATHS.size():
		var spec:Dictionary=DEATHS[index]
		var actor:=soldier(spec.weapon,index%2)
		configure(actor,spec.pose,spec.velocity)
		actor.yaw=0
		await step([actor],1.2)
		var hit:Vector3=spec.hit
		# Side view, perpendicular to the way the soldier faces (-Z), centred between where he
		# stood and where a runner ends up.
		camera.position=Vector3(5.2,1.1,-.7)
		camera.look_at(Vector3(0,.5,-.7))
		var corpse:=SoldierFactory.corpse(stage,actor,hit);actor.visual.visible=false
		var driver:RagdollDriver=corpse.get_node("Driver")
		var frames:Array[Image]=[]
		var next:=0.0
		var elapsed:=0.0
		while elapsed<3.0:
			if elapsed>=next-.001:
				title.text="DEATH %d (%s, %s)  t=%.2fs"%[index+1,spec.pose,spec.weapon,elapsed]
				await process_frame;RenderingServer.force_draw(false)
				var shot:=root.get_texture().get_image();shot.resize(FRAME.x,FRAME.y,Image.INTERPOLATE_LANCZOS);frames.append(shot)
				next+=.25
			await physics_frame
			elapsed+=1.0/60
		var sheet:=Image.create(FRAME.x*4,FRAME.y*3,false,Image.FORMAT_RGB8)
		for i in mini(frames.size(),12):sheet.blit_rect(frames[i],Rect2i(0,0,FRAME.x,FRAME.y),Vector2i(FRAME.x*(i%4),FRAME.y*(i/4)))
		sheet.save_png("res://.artifacts/screenshots/soldiers/death_%d.png"%(index+1))
		print("DEATH %d settled_at=%.2f peak_speed=%.2f final_speed=%.3f"%[index+1,driver.settled_at,driver.peak_speed,driver.final_speed])
		corpse.free();actor.free()

# Paints the weapon magenta and counts its visible pixels from distances around the LOD
# switch (6 m), for each weapon; zero or a sudden drop means the gun vanished.
func gun_visibility(legacy: bool) -> void:
	var paint:=StandardMaterial3D.new();paint.albedo_color=Color(1,0,1);paint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	root.size=Vector2i(480,300)
	for weapon in [&"ar_a4",&"ar_k47",&"sg_p12",&"lmg_l56",&"sniper_s90",&"smg_mp9"]:
		var actor:=soldier(weapon,0)
		actor.crouched=false;actor.ads=true;actor.pitch=-.05
		await step([actor],.8)
		var lowest:=INF
		var report:=""
		var distance:=4.6
		while distance<=8.4:
			camera.position=Vector3(distance*.8,1.3,-distance*.6)
			camera.look_at(Vector3(0,1.2,0))
			if legacy:
				for child in actor.gun.get_node("Model").get_children():
					if child is GeometryInstance3D:
						child.visible=true;child.visibility_range_begin=0.0;child.visibility_range_end=0.0
						if child.name=="LOD":child.visibility_range_begin=6.0
						else:child.visibility_range_end=6.0
			for child in actor.gun.find_children("*","GeometryInstance3D",true,false):child.material_override=paint
			await step([actor],.03)
			if legacy:
				for child in actor.gun.get_node("Model").get_children():
					if child is GeometryInstance3D:child.visible=true
			title.text="%s  %.2f m  %s"%[weapon,distance,"legacy" if legacy else "now"]
			await process_frame;RenderingServer.force_draw(false)
			var data:=root.get_texture().get_image().get_data()
			var count:=0
			for i in range(0,data.size()-2,3):
				if data[i]>130 and data[i+2]>130 and data[i+1]+60<mini(data[i],data[i+2]):count+=1
			report+=" %.1f:%d"%[distance,count]
			if distance>5.0 and distance<7.4:lowest=minf(lowest,count)
			distance+=.2
		print("GUN %s lowest_between_5_and_7.4m=%d |%s"%[weapon,lowest,report])
		actor.free()
