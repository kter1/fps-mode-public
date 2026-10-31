extends Control

const SEAT_INPUT := preload("res://game/local/local_player_input.gd")
const SEAT_HUD := preload("res://game/local/local_player_hud.gd")
const MAX_PLAYERS := 4
# Bit 2 holds live actors, corpses, pickups and effects so a seat watching its kill cam
# can drop them; bits 13-16 hold each seat's private replay models.
const LIVE_LAYER := 2
var app: Control
var world: MatchWorld
var seats: Array[Dictionary] = []
var running := false
var all_controllers := false
var bot_weapons: Array = []

static func seat_rect(index: int, count: int) -> Rect2:
	if count==2:return Rect2(0,index*.5,1,.5)
	return Rect2((index%2)*.5,(index/2)*.5,.5,.5)

static func set_layers(node: Node, mask: int) -> void:
	if node is VisualInstance3D:node.layers=mask
	if node is Light3D:node.light_cull_mask=mask
	for child in node.get_children():set_layers(child,mask)

# Visibility only: live lights keep lighting everything.
static func set_visual_layers(node: Node, mask: int) -> void:
	if node is VisualInstance3D:node.layers=mask
	for child in node.get_children():set_visual_layers(child,mask)

static func tag_live(node: Node) -> void:
	if node==null or node.has_meta("live_layer"):return
	set_visual_layers(node,LIVE_LAYER);node.set_meta("live_layer",true)

func configure(owner_app: Control, use_controllers: bool) -> void:
	app=owner_app;world=app.match_world;all_controllers=use_controllers
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_physics_priority=-100
	var devices:=Input.get_connected_joypads()
	for i in world.local_player_count:
		var pane:=Control.new();pane.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(pane)
		var rect:=seat_rect(i,world.local_player_count)
		pane.anchor_left=rect.position.x;pane.anchor_top=rect.position.y;pane.anchor_right=rect.end.x;pane.anchor_bottom=rect.end.y
		var view:=SubViewport.new();view.world_3d=world.get_world_3d();view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		view.physics_object_picking=false;view.msaa_3d=Viewport.MSAA_2X;view.use_taa=true;view.use_occlusion_culling=false;add_child(view)
		var texture:=TextureRect.new();texture.texture=view.get_texture();texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		texture.mouse_filter=Control.MOUSE_FILTER_IGNORE;pane.add_child(texture);texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var camera:=Camera3D.new();camera.far=900;camera.near=.02;camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		view.add_child(camera);camera.current=true
		# Layers 3-6 are the local bodies; 9-12 are private first-person rigs.
		var body_layer:=1<<(i+2);var hands_layer:=1<<(i+8)
		camera.cull_mask=(1|LIVE_LAYER|4|8|16|32)&~body_layer|hands_layer
		var hands:=ViewModel.new();camera.add_child(hands);hands.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
		var actor:=world.actors[i]
		hands.refresh(actor);hands.shown=true;set_layers(hands,hands_layer);set_layers(actor.visual,body_layer)
		var replay:=KillReplay.new();app.world_view.add_child(replay);replay.configure(world,1<<(i+12))
		var input:=SEAT_INPUT.new();input.settings=app.profile.settings
		var device_index:=i if all_controllers else i-1
		input.device=-1 if i==0 and not all_controllers else (devices[device_index] if device_index<devices.size() else -2)
		input.reset(actor)
		var hud:=SEAT_HUD.new();hud.world=world;hud.actor=actor;hud.seat=i;hud.input_state=input;hud.replay=replay
		pane.add_child(hud);hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		seats.append({"pane":pane,"view":view,"camera":camera,"hands":hands,"hud":hud,"input":input,"replay":replay,"replay_rig":"","life":actor.slot.life_id,"weapon":actor.weapon(),"body_layer":body_layer,"hands_layer":hands_layer})
	for i in range(world.local_player_count,world.actors.size()):set_visual_layers(world.actors[i].visual,LIVE_LAYER)
	bot_weapons.assign(world.actors.map(func(actor:Combatant):return actor.weapon()))
	set_visual_layers(world.effects,LIVE_LAYER)
	fit_views()
	Input.joy_connection_changed.connect(controller_changed)
	world.local_player_eliminated.connect(begin_replay)
	app.world_texture.hide();app.world_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	app.hands.shown=false;app.hands.hide();app.hud.hide()
	running=true

# Each pane renders at its real pixel size. Split-screen caps the 3D preset at Medium:
# every view is a full scene pass, so the panes together cost about one 1080p frame.
func fit_views() -> void:
	var window:=Vector2(get_window().size)
	var quality:=mini(int(app.profile.settings.quality),1)
	for i in seats.size():
		var rect:=seat_rect(i,seats.size())
		RenderScale.fit(seats[i].view,Vector2i(window*rect.size),window.y,quality,false)

func controller_changed(device: int, connected: bool) -> void:
	if not connected:
		for i in seats.size():
			if seats[i].input.device==device:seats[i].input.device=-2;seats[i].input.reset(world.actors[i])
			if seats[i].input.spare_pad==device:seats[i].input.spare_pad=-3
		return
	for seat in seats:
		if seat.input.device==device:return
	for i in seats.size():
		if seats[i].input.device==-2:assign(i,device);return

func assign(index: int, device: int) -> void:
	var input=seats[index].input
	input.device=device;input.heard=false;input.reset(world.actors[index])

# A button on a controller no seat owns claims, in order: a seat waiting for a
# controller, a seat whose controller has never sent input (a ghost listing), or the
# keyboard seat as its spare controller.
func claim(device: int) -> void:
	for seat in seats:
		if seat.input.device==device or seat.input.spare_pad==device:return
	for i in seats.size():
		if seats[i].input.device==-2:assign(i,device);return
	for i in seats.size():
		if seats[i].input.device>=0 and not seats[i].input.heard:assign(i,device);return
	if seats[0].input.device==-1:seats[0].input.spare_pad=device

func handle(event: InputEvent) -> void:
	if app.screen!="playing" or get_tree().paused:return
	if event is InputEventJoypadButton and event.pressed:claim(event.device)
	for i in seats.size():
		var input=seats[i].input
		if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and input.accepts(event):input.heard=true
		if world.actors[i].alive:input.handle(event,not world.swap_candidate(world.actors[i]).is_empty())
		elif seats[i].replay.active and input.skip_pressed(event):end_replay(i)

func begin_replay(index: int, source: int, death_time: float) -> void:
	if index>=seats.size() or source<0 or source==index or world.mode.finished:return
	var seat:=seats[index]
	if not seat.replay.begin(source,death_time):return
	seat.camera.cull_mask=1|seat.replay.view_layer|seat.hands_layer
	seat.replay_rig=""

func end_replay(index: int) -> void:
	var seat:=seats[index];var actor:=world.actors[index]
	if seat.replay.active:seat.replay.skip()
	seat.camera.cull_mask=(1|LIVE_LAYER|4|8|16|32)&~seat.body_layer|seat.hands_layer
	# Clearing the weapon makes the next tick re-tag both rigs for the new life.
	seat.hands.refresh(actor);seat.weapon=null

func reset_inputs() -> void:
	for i in seats.size():
		seats[i].input.reset(world.actors[i]);world.local_commands[i]=ActorCommand.new()
		seats[i].input.prone=world.actors[i].prone;seats[i].input.crouch=world.actors[i].crouched and not world.actors[i].prone
	world.player_command=world.local_commands[0]

func _physics_process(delta: float) -> void:
	if not running or app.screen!="playing" or get_tree().paused:return
	for i in seats.size():
		var actor:=world.actors[i];var seat:=seats[i]
		if actor.slot.life_id!=seat.life:
			seat.life=actor.slot.life_id;seat.input.reset(actor)
			if seat.replay.active:end_replay(i)
		if not actor.alive:seat.input.reset(actor)
		var command:ActorCommand=seat.input.sample(delta,actor) if actor.alive else ActorCommand.new()
		world.local_commands[i]=command
		if i==0:world.player_command=command

func tick(delta: float) -> void:
	tag_live_world()
	for i in seats.size():
		var seat:=seats[i];var actor:=world.actors[i]
		var camera:Camera3D=seat.camera;var hands:ViewModel=seat.hands
		var base:=float(app.profile.settings.fov)
		if seat.replay.active and (world.mode.finished or actor.alive):end_replay(i)
		if seat.replay.active:
			if not get_tree().paused:seat.replay.advance(delta,camera,hands,base)
			# The replay swaps the killer's weapon into this seat's rig.
			if seat.replay_rig!=seat.replay.source_weapon:
				seat.replay_rig=seat.replay.source_weapon;set_layers(hands,seat.hands_layer)
			seat.hud.visible=app.screen=="playing";seat.hud.queue_redraw()
			continue
		camera.global_position=actor.get_global_transform_interpolated().origin+Vector3.UP*actor.eye_height
		camera.rotation=Vector3(actor.pitch+actor.recoil,actor.yaw,0)
		hands.shown=actor.alive
		if not get_tree().paused:
			hands.tick(delta,world.clock,float(app.profile.settings.shake))
			# Weapon swaps and respawns create new meshes in both rigs.
			if seat.weapon!=actor.weapon():
				seat.weapon=actor.weapon();set_layers(hands,seat.hands_layer);set_layers(actor.visual,seat.body_layer)
		camera.fov=lerpf(base,rad_to_deg(2*atan(tan(deg_to_rad(base)*.5)/actor.weapon().magnification)),hands.blend)
		seat.hud.visible=app.screen=="playing";seat.hud.queue_redraw()
	app.camera.global_transform=seats[0].camera.global_transform
	# The effects fallback uses a single active rig for the audio listener's seat.
	ViewModel.active=seats[0].hands

# Bots' visuals are rebuilt with their weapons; corpses, pickups and grenades are
# spawned during play. All of them belong to the live layer.
func tag_live_world() -> void:
	for i in range(seats.size(),world.actors.size()):
		var actor:=world.actors[i]
		if i<bot_weapons.size() and bot_weapons[i]!=actor.weapon():
			bot_weapons[i]=actor.weapon();set_visual_layers(actor.visual,LIVE_LAYER)
	for corpse in world.corpses:
		if is_instance_valid(corpse.node):tag_live(corpse.node)
	for entry in world.pickups:
		if is_instance_valid(entry.node):tag_live(entry.node)
	for grenade in world.grenades:
		if is_instance_valid(grenade.body_mesh):tag_live(grenade.body_mesh)
	for cloud in world.smoke_clouds:
		if is_instance_valid(cloud.node):tag_live(cloud.node)

func shutdown() -> void:
	running=false
	for seat in seats:
		if is_instance_valid(seat.replay):seat.replay.stop();seat.replay.queue_free()
	if world.local_player_eliminated.is_connected(begin_replay):world.local_player_eliminated.disconnect(begin_replay)
	if Input.joy_connection_changed.is_connected(controller_changed):Input.joy_connection_changed.disconnect(controller_changed)
	app.world_texture.show();app.world_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	ViewModel.active=app.hands
