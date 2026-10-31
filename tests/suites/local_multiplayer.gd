extends RefCounted

const SEAT_INPUT := preload("res://game/local/local_player_input.gd")
const SPLIT := preload("res://game/local/local_split_screen.gd")

class SplitApp extends Control:
	var match_world: MatchWorld
	var world_view: SubViewport
	var world_texture: TextureRect
	var hands: ViewModel
	var hud: Control
	var camera: Camera3D
	var profile := ProfileStore.new()
	var screen := "playing"

static func pad_button(device: int, button: JoyButton, pressed := true) -> InputEventJoypadButton:
	var event:=InputEventJoypadButton.new();event.device=device;event.button_index=button;event.pressed=pressed;return event

static func pad_axis(device: int, axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var event:=InputEventJoypadMotion.new();event.device=device;event.axis=axis;event.axis_value=value;return event

static func run(t: SceneTree) -> void:
	PlayerControls.install({})
	var app:=SplitApp.new();app.size=Vector2(1280,720);t.root.add_child(app)
	app.world_view=SubViewport.new();app.world_view.own_world_3d=true;app.add_child(app.world_view)
	app.world_texture=TextureRect.new();app.add_child(app.world_texture)
	app.camera=Camera3D.new();app.world_view.add_child(app.camera);app.camera.current=true
	app.hands=ViewModel.new();app.camera.add_child(app.hands);app.hud=Control.new();app.add_child(app.hud)
	var world:=MatchWorld.new();app.match_world=world;world.local_player_count=4;app.world_view.add_child(world)
	var preset:LoadoutDefinition=t.catalog.starter_loadouts()[0]
	world.configure(t.catalog,"airport",preset,1,1201,false);world.set_physics_process(false)
	for i in 240:
		if world.ready_for_play:break
		await t.physics_frame
	t.check_that(world.ready_for_play,"split_world_ready")
	t.check_that(world.actors.size()==16 and world.slots.filter(func(slot:ActorSlot):return slot.is_human).size()==4,"four_humans_replace_allied_bots")
	t.check_that(world.actors.slice(0,4).all(func(actor:Combatant):return actor.bot==null and actor.slot.team==0),"four_humans_share_blue_team")
	world.slots[1].loadout.primary=&"smg_mp9"
	t.check_that(world.slots[0].loadout.primary!=world.slots[1].loadout.primary and preset.primary!=world.slots[1].loadout.primary,"player_loadouts_are_independent")
	var inputs: Array = []
	for i in 4:
		var state:=SEAT_INPUT.new();state.settings=app.profile.settings;state.device=i;state.reset(world.actors[i]);inputs.append(state)
	for i in 4:
		for state in inputs:state.handle(pad_axis(i,JOY_AXIS_LEFT_X,1.0 if i%2==0 else -1.0))
		var own:ActorCommand=inputs[i].sample(1.0/60,world.actors[i])
		t.check_that(absf(own.movement.x)==1,"controller_%d_moves_own_seat"%i)
		for j in range(i+1,4):t.check_that(inputs[j].sample(1.0/60,world.actors[j]).movement==Vector2.ZERO,"controller_%d_does_not_move_seat_%d"%[i,j])
	for state in inputs:state.handle(pad_axis(2,JOY_AXIS_TRIGGER_RIGHT,1))
	for i in 4:
		var command:ActorCommand=inputs[i].sample(1.0/60,world.actors[i])
		t.check_that(command.fire_held==(i==2) and command.fire_pressed==(i==2),"trigger_isolated_seat_%d"%i)
	inputs[2].handle(pad_axis(2,JOY_AXIS_TRIGGER_RIGHT,.9))
	t.check_that(not inputs[2].sample(.016,world.actors[2]).fire_pressed,"held_trigger_does_not_repeat_semi_auto_edge")
	inputs[2].handle(pad_axis(2,JOY_AXIS_TRIGGER_RIGHT,0))
	t.check_that(not inputs[2].sample(.016,world.actors[2]).fire_held,"trigger_release_stops_firing")
	inputs[1].handle(pad_button(1,JOY_BUTTON_B));inputs[1].sample(.36,world.actors[1])
	inputs[1].handle(pad_button(1,JOY_BUTTON_B,false))
	t.check_that(inputs[1].sample(.016,world.actors[1]).prone and not inputs[0].sample(.016,world.actors[0]).prone,"hold_circle_prone_is_independent")
	inputs[1].reset(world.actors[1]);inputs[1].handle(pad_button(1,JOY_BUTTON_B));inputs[1].handle(pad_button(1,JOY_BUTTON_B,false))
	t.check_that(inputs[1].sample(.016,world.actors[1]).crouch,"tap_circle_still_crouches")
	inputs[1].reset(world.actors[1]);inputs[1].prone=true
	inputs[1].handle(pad_button(1,JOY_BUTTON_B,false))
	t.check_that(inputs[1].sample(.016,world.actors[1]).prone,"menu_circle_release_does_not_change_gameplay_stance")
	inputs[3].handle(pad_button(3,JOY_BUTTON_X),true);inputs[3].sample(.36,world.actors[3])
	t.check_that(inputs[3].sample(.016,world.actors[3]).interact_held,"square_hold_picks_up_for_own_seat")
	inputs[3].handle(pad_button(3,JOY_BUTTON_X,false));inputs[3].reset(world.actors[3])
	var keyboard:=SEAT_INPUT.new();keyboard.device=-1;keyboard.settings=app.profile.settings
	var key:=InputEventKey.new();key.physical_keycode=KEY_W;key.pressed=true
	keyboard.handle(key);keyboard.handle(pad_axis(0,JOY_AXIS_LEFT_X,1))
	t.check_that(keyboard.sample(.016,world.actors[0]).movement==Vector2(0,-1),"keyboard_seat_ignores_all_gamepads")
	for i in world.actors.size():
		if i>=4:world.actors[i].alive=false;world.slots[i].respawn_at=-1
	world.countdown=0
	for i in 4:
		var command:=ActorCommand.new();command.aim_yaw=float(i)*.3
		world.local_commands[i]=command
	world.player_command=world.local_commands[0];world._physics_process(1.0/60)
	t.check_that(world.actors.slice(0,4).all(func(actor:Combatant):return is_equal_approx(actor.yaw,float(actor.slot.id)*.3)),"simulation_routes_four_independent_commands")
	for i in 4:
		world.actors[i].weapon().state="READY";world.actors[i].action_until=0
		world.local_commands[i].fire_pressed=true;world.local_commands[i].fire_held=true
	var ammo: Array = world.actors.slice(0,4).map(func(actor:Combatant):return actor.weapon().ammo)
	world._physics_process(1.0/60)
	for i in 4:t.check_that(world.actors[i].weapon().ammo==ammo[i]-1,"player_%d_can_fire"%(i+1))
	t.check_that(world.local_commands.all(func(command:ActorCommand):return not command.fire_pressed),"all_player_edges_consumed_after_tick")
	var actor:=world.actors[2];var life:=actor.slot.life_id
	actor.alive=false;actor.slot.respawn_at=world.clock;actor.head.collision_layer=0;actor.torso.collision_layer=0
	world._physics_process(1.0/60)
	t.check_that(actor.alive and actor.slot.life_id==life+1 and actor.bot==null,"additional_player_respawns_without_becoming_bot")
	var scavenger:=world.actors[1]
	for other in world.actors:
		if other!=scavenger:other.global_position=Vector3(100,20,100)
	scavenger.weapon().reserve=0
	world.drop_weapon(scavenger,scavenger.weapon())
	world.pickups.back().dropper="another-life"
	world.tick_pickups()
	t.check_that(scavenger.weapon().reserve>0,"additional_player_scavenges_ammunition")
	var dropped:=WeaponRuntime.new();dropped.configure(t.catalog.weapons["sniper_s90"])
	world.drop_weapon(scavenger,dropped)
	var interact:=ActorCommand.new();interact.interact_pressed=true;scavenger.command=interact
	world.combat(scavenger)
	t.check_that(scavenger.weapon().definition.id==&"sniper_s90","additional_player_can_pick_up_a_dropped_weapon")
	var split:=SPLIT.new();app.add_child(split);split.configure(app,false);split.set_physics_process(false)
	await t.process_frame
	t.check_that(split.seats.size()==4 and split.seats.all(func(seat:Dictionary):return seat.view.world_3d==world.get_world_3d()),"four_views_share_one_simulation")
	t.check_that(split.seats[0].input.device==-1,"player_one_uses_keyboard_in_mixed_layout")
	var masks_ok:=true
	for i in 4:
		var seat:Dictionary=split.seats[i]
		masks_ok=masks_ok and (seat.camera.cull_mask&seat.body_layer)==0 and (seat.camera.cull_mask&seat.hands_layer)!=0
		for j in 4:
			if i!=j:masks_ok=masks_ok and (seat.camera.cull_mask&split.seats[j].body_layer)!=0 and (seat.camera.cull_mask&split.seats[j].hands_layer)==0
	t.check_that(masks_ok,"each_camera_hides_own_body_and_other_players_first_person_rigs")
	var window:=Vector2(split.get_window().size)
	var pane:SubViewport=split.seats[3].view
	t.check_that(pane.size==Vector2i(window*.5) and is_equal_approx(pane.scaling_3d_scale,clampf(RenderScale.HEIGHTS[1]/window.y,.25,2.0)),"panes_render_at_window_pixels_with_preset_budget","%s %s %.3f"%[window,pane.size,pane.scaling_3d_scale])
	# A seat bound to a controller that never sends input (a ghost listing) is reclaimed
	# by the first press from an unowned controller; a seat that has been heard is kept.
	for i in range(1,4):split.assign(i,20+i)
	split.handle(pad_axis(21,JOY_AXIS_LEFT_X,.4))
	split.handle(pad_button(30,JOY_BUTTON_A));split.handle(pad_button(30,JOY_BUTTON_A,false))
	t.check_that(split.seats[1].input.device==21 and split.seats[2].input.device==30 and split.seats[3].input.device==23,"ghost_controller_seat_is_reclaimed")
	split.handle(pad_axis(30,JOY_AXIS_LEFT_X,0));split.handle(pad_axis(23,JOY_AXIS_LEFT_X,0))
	split.handle(pad_button(31,JOY_BUTTON_B));split.handle(pad_button(31,JOY_BUTTON_B,false))
	split.handle(pad_axis(31,JOY_AXIS_LEFT_Y,-1))
	var spare_command:ActorCommand=split.seats[0].input.sample(.016,world.actors[0])
	t.check_that(split.seats[0].input.device==-1 and split.seats[0].input.spare_pad==31 and spare_command.movement.y<-.9,"spare_controller_drives_keyboard_seat")
	split.handle(pad_axis(31,JOY_AXIS_LEFT_Y,0));split.seats[0].input.reset(world.actors[0])
	# Kill cam: private to the victim's view, the shared world is untouched.
	for step in 4:world.clock+=.06;world.replay_history.record(world.clock,world.actors,true)
	var victim:Combatant=world.actors[1];victim.alive=false
	var seat_one:Dictionary=split.seats[1];var replay:KillReplay=seat_one.replay
	var live_bot:Combatant=world.actors[8]
	split.begin_replay(1,8,world.clock)
	var avatar_layers:=true
	for avatar in replay.avatars:
		for node in avatar.model.find_children("*","VisualInstance3D",true,false):avatar_layers=avatar_layers and node.layers==replay.view_layer
	t.check_that(replay.active and seat_one.camera.cull_mask&replay.view_layer!=0 and seat_one.camera.cull_mask&(SPLIT.LIVE_LAYER|4|8|16|32)==0 and avatar_layers,"split_kill_cam_renders_only_in_victims_view")
	var bot_meshes:=live_bot.visual.find_children("*","VisualInstance3D",true,false)
	t.check_that(world.effects.visible and bot_meshes.all(func(node:VisualInstance3D):return node.layers==SPLIT.LIVE_LAYER) and split.seats[0].camera.cull_mask&SPLIT.LIVE_LAYER!=0 and split.seats[0].camera.cull_mask&replay.view_layer==0,"split_kill_cam_leaves_other_views_live")
	split.tick(.016)
	split.handle(pad_button(21,JOY_BUTTON_A));split.handle(pad_button(21,JOY_BUTTON_A,false))
	t.check_that(not replay.active and seat_one.camera.cull_mask&SPLIT.LIVE_LAYER!=0 and seat_one.camera.cull_mask&replay.view_layer==0,"split_kill_cam_skip_restores_live_view")
	victim.alive=true
	for i in 4:split.seats[i].input.device=-2
	split.controller_changed(42,true);split.controller_changed(43,true)
	t.check_that(split.seats[0].input.device==42 and split.seats[1].input.device==43,"hotplug_assigns_distinct_waiting_seats")
	split.seats[0].input.handle(pad_axis(42,JOY_AXIS_TRIGGER_RIGHT,1));split.controller_changed(42,false)
	t.check_that(split.seats[0].input.device==-2 and split.seats[0].input.held.is_empty(),"disconnect_clears_held_input")
	split.controller_changed(44,true)
	t.check_that(split.seats[0].input.device==44 and split.seats[1].input.device==43,"replacement_controller_reclaims_vacant_seat")
	split.reset_inputs()
	t.check_that(world.local_commands.all(func(command:ActorCommand):return not command.fire_held and command.movement==Vector2.ZERO),"pause_reset_clears_every_player_command")
	for count in [2,3,4]:
		var area:=0.0;var overlaps:=false
		for i in count:
			var rect:Rect2=SPLIT.seat_rect(i,count);area+=rect.get_area()
			for j in range(i+1,count):overlaps=overlaps or rect.intersects(SPLIT.seat_rect(j,count))
		t.check_that(not overlaps and is_equal_approx(area,.75 if count==3 else 1.0),"split_layout_%d_has_no_overlap"%count)
	split.tick(.016);split.shutdown();split.free()
	t.check_that(app.world_texture.visible and app.world_view.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"cleanup_restores_single_player_view")
	var pads_only:=SPLIT.new();app.add_child(pads_only);pads_only.configure(app,true);pads_only.set_physics_process(false)
	for seat in pads_only.seats:seat.input.device=-2
	for i in 4:pads_only.controller_changed(i,true)
	t.check_that(pads_only.seats.all(func(seat:Dictionary):return seat.input.device>=0) and pads_only.seats.map(func(seat:Dictionary):return seat.input.device)==[0,1,2,3],"four_controller_layout_assigns_four_distinct_devices")
	pads_only.shutdown();pads_only.free()
	app.free()
	await t.process_frame
	for count in [2,3,4]:
		var versus:=MatchWorld.new();versus.local_player_count=count;versus.local_versus=true;t.root.add_child(versus)
		versus.configure(t.catalog,"airport",preset,1,1201,false);versus.set_physics_process(false)
		for i in 240:
			if versus.ready_for_play:break
			await t.physics_frame
		var blue:=versus.slots.filter(func(slot:ActorSlot):return slot.team==0).size()
		var red:=versus.slots.filter(func(slot:ActorSlot):return slot.team==1).size()
		t.check_that(blue==8 and red==8 and versus.slots.slice(0,count).all(func(slot:ActorSlot):return slot.team==slot.id%2),"versus_%d_alternates_humans_and_balances_bots"%count)
		versus.free();await t.process_frame
