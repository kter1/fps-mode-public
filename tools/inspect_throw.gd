extends SceneTree

# Renders the overarm grenade throw as contact sheets (6 moments each): first person
# through the real ViewModel, and third person through the AnimationTree and pose
# modifier from three-quarter and side views. Writes .artifacts/screenshots/throw/*.png.

const MOMENTS := [.08, .25, .36, .45, .6, .78]
var clock := 2.0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,720)
	RenderingServer.render_loop_enabled=true
	var catalog:=Catalog.new()
	var camera:=Camera3D.new();camera.fov=70;camera.near=.025;root.add_child(camera);camera.current=true;camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var environment:=WorldEnvironment.new();var sky:=Environment.new();sky.background_mode=Environment.BG_COLOR;sky.background_color=Color("647585");sky.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;sky.ambient_light_energy=.8;sky.ambient_light_color=Color("b8c4d0")
	environment.environment=sky;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-38,-32,0);sun.light_energy=1.6;root.add_child(sun)
	var stage:=Node3D.new();root.add_child(stage)
	ModelFactory.primitive(stage,Vector3(30,.1,30),Vector3(0,-.05,0),Color("5d6062"))
	var title:=Label.new();title.position=Vector2(20,14);title.add_theme_font_size_override("font_size",22);root.add_child(title)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/throw")
	# First person.
	var player:=Combatant.new();root.add_child(player);var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=LoadoutDefinition.new();player.setup(slot,catalog)
	var hands:=ViewModel.new();camera.add_child(hands);hands.shown=true
	var frames:Array[Image]=[]
	for weapon in ["ar_a4","pistol_p9"]:
		frames.clear()
		if weapon=="pistol_p9":slot.loadout.sidearm=&"pistol_p9";player.set_loadout(catalog);player.switch_to(1,0.0)
		else:slot.loadout.primary=&"ar_a4";player.set_loadout(catalog)
		hands.refresh(player);player.ads=false;hands.blend=0
		for moment in MOMENTS:
			start_throw(player,10.0)
			hands.tick(1.0,10.0+moment,0.0)
			title.text="FIRST PERSON "+weapon+"  t=%.2f s"%moment
			frames.append(await shot())
		sheet(frames,"first_person_"+weapon)
	hands.queue_free();player.queue_free()
	camera.fov=40
	# Third person.
	var soldiers:Array[Combatant]=[]
	for team in 2:
		var actor:=Combatant.new();root.add_child(actor);var s:=ActorSlot.new();s.id=team+1;s.team=team;s.loadout=LoadoutDefinition.new()
		if team==1:s.loadout.primary=&"ar_k47"
		actor.setup(s,catalog);actor.position=Vector3(-.75+team*1.5,0,0);actor.yaw=PI*.8;actor.rotation.y=actor.yaw;soldiers.append(actor)
	var facing:=Basis(Vector3.UP,PI*.8)
	for view in ["three_quarter","side","front"]:
		frames.clear()
		var focus:=Vector3(-.75,1.0,0)
		if view=="three_quarter":camera.position=Vector3(2.4,1.5,3.2)
		if view=="side":camera.position=focus+facing*Vector3(3.4,.4,0)
		if view=="front":camera.position=focus+facing*Vector3(0,.5,-3.6)
		camera.look_at(focus)
		soldiers[1].visual.visible=false
		for moment in MOMENTS:
			clock+=1.5
			var began:=clock
			for step in 12:
				clock+=.05;soldiers[0].update_animation(clock);soldiers[0].update_gun_pose();await physics_frame
			start_throw(soldiers[0],clock)
			var target:float=clock+moment
			while clock<target-.001:
				clock=minf(clock+1.0/60,target);soldiers[0].update_animation(clock);soldiers[0].update_gun_pose();await physics_frame
			title.text="THIRD PERSON "+view+"  t=%.2f s"%moment
			frames.append(await shot())
			soldiers[0].action_kind="";soldiers[0].action_until=0
		sheet(frames,"third_person_"+view)
	print("THROW INSPECTION PASS");quit()

func start_throw(actor: Combatant, at: float) -> void:
	actor.action_kind="throw";actor.throw_started=at;actor.throw_holding=false
	actor.throw_at=at+ThrowTimeline.RELEASE;actor.action_until=at+ThrowTimeline.TOTAL

func shot() -> Image:
	await process_frame;RenderingServer.force_draw(false)
	return root.get_texture().get_image()

func sheet(frames: Array[Image], name: String) -> void:
	var out:=Image.create(1920,720,false,Image.FORMAT_RGBA8)
	for i in frames.size():
		var copy:=frames[i].duplicate() as Image;copy.convert(Image.FORMAT_RGBA8);copy.resize(640,360,Image.INTERPOLATE_BILINEAR)
		out.blit_rect(copy,Rect2i(0,0,640,360),Vector2i((i%3)*640,(i/3)*360))
	out.save_png("res://.artifacts/screenshots/throw/"+name+".png")
