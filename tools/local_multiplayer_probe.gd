extends SceneTree

const SUITE := preload("res://tests/suites/local_multiplayer.gd")
var results: Array[Dictionary] = []

func _initialize() -> void:call_deferred("run")

func verify(condition: bool, name: String) -> void:
	results.append({"name":name,"passed":condition});print("PASS " if condition else "FAIL ",name)

func frames(count: int) -> void:
	for i in count:await process_frame

func run() -> void:
	root.unfocusable=true;root.mouse_passthrough=true
	var app:Variant=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	app.selected_mode="tdm";app.selected_map="airport"
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/local-multiplayer")
	for count in [4,2,3]:
		app.local_players=count
		app.local_versus=count!=2
		app.local_all_controllers=count==2
		await app.start_match()
		app.match_world.countdown=0
		var split:Control=app.local_split
		verify(split!=null and split.seats.size()==count,"app_builds_%d_views"%count)
		verify(app.kill_replay==null and not app.hud.visible,"split_uses_independent_huds_%d"%count)
		for i in count:
			if i>0 or app.local_all_controllers:split.seats[i].input.device=i
		await frames(20)
		var actor:Combatant=app.match_world.actors[count-1]
		app._unhandled_input(SUITE.pad_button(count-1,JOY_BUTTON_B))
		await frames(40)
		app._unhandled_input(SUITE.pad_button(count-1,JOY_BUTTON_B,false))
		await frames(3)
		verify(actor.prone,"last_player_hold_circle_goes_prone_%d"%count)
		var head_bone:=actor.skeleton.find_bone("Head")
		var foot_bone:=actor.skeleton.find_bone("LeftFoot")
		var pose:={}
		SoldierFactory.at_final_pose(actor.skeleton,actor.visual,func():
			pose.head=actor.skeleton.get_bone_global_pose(head_bone).origin
			pose.foot=actor.skeleton.get_bone_global_pose(foot_bone).origin)
		var head_position:Vector3=pose.head
		var foot_position:Vector3=pose.foot
		verify(head_position.is_finite() and foot_position.is_finite() and head_position.distance_to(foot_position)>1.0,"prone_pose_keeps_body_bone_offsets_%d"%count)
		verify(not app.match_world.actors[0].prone,"last_player_circle_does_not_affect_p1_%d"%count)
		var last_ammo:int=app.match_world.actors[count-1].weapon().ammo
		var first_ammo:int=app.match_world.actors[0].weapon().ammo
		app._unhandled_input(SUITE.pad_axis(count-1,JOY_AXIS_TRIGGER_RIGHT,1))
		# Shared speakers: the last player's own gunfire plays up close, not as distant fire.
		var loudest:=-200.0
		for i in 12:
			await process_frame
			loudest=maxf(loudest,maxf(AudioServer.get_bus_peak_volume_left_db(0,0),AudioServer.get_bus_peak_volume_right_db(0,0)))
		app._unhandled_input(SUITE.pad_axis(count-1,JOY_AXIS_TRIGGER_RIGHT,0))
		verify(loudest>-16.0,"last_player_hears_own_gunfire_%d"%count)
		verify(app.match_world.actors[count-1].weapon().ammo<last_ammo and app.match_world.actors[0].weapon().ammo==first_ammo,"last_player_fires_independently_%d"%count)
		app._unhandled_input(SUITE.pad_button(count-1,JOY_BUTTON_START))
		var clock:float=app.match_world.clock
		await frames(5)
		verify(paused and app.screen=="pause" and app.match_world.clock==clock,"any_controller_can_pause_all_players_%d"%count)
		app._unhandled_input(SUITE.pad_button(count-1,JOY_BUTTON_B))
		app._unhandled_input(SUITE.pad_button(count-1,JOY_BUTTON_B,false))
		await frames(5)
		verify(not paused and app.screen=="playing" and not app.hud.visible,"controller_resumes_split_screen_%d"%count)
		verify(actor.prone,"pause_preserves_player_stance_%d"%count)
		var sizes_ok:=true
		var pixels:Vector2=app.get_viewport().get_final_transform().get_scale()
		for seat in split.seats:sizes_ok=sizes_ok and Vector2(seat.view.size).distance_to(seat.pane.size*pixels)<2
		verify(sizes_ok,"viewports_match_pane_sizes_%d"%count)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.artifacts/screenshots/local-multiplayer/%d-players.png"%count)
		if count==2:
			var world:MatchWorld=app.match_world;var victim:Combatant=world.actors[1]
			var killer:Combatant=world.actors.filter(func(other:Combatant):return other.slot.team!=victim.slot.team)[0]
			victim.protected_until=0
			world.queue_damage(killer.slot.id,victim,500,&"ar_a4",false)
			await frames(30)
			var seat:Dictionary=split.seats[1]
			verify(not victim.alive and seat.replay.active and seat.replay.killer==killer.slot.id and seat.camera.cull_mask&seat.replay.view_layer!=0,"rendered_kill_cam_plays_in_victims_view")
			verify(not split.seats[0].replay.active and world.effects.visible and split.seats[0].camera.cull_mask&split.LIVE_LAYER!=0,"rendered_kill_cam_leaves_partner_view_live")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.artifacts/screenshots/local-multiplayer/2-players-killcam.png")
			var waited:=0
			while not victim.alive and waited<600:await frames(1);waited+=1
			await frames(3)
			verify(victim.alive and not seat.replay.active and seat.camera.cull_mask&split.LIVE_LAYER!=0,"kill_cam_ends_on_respawn")
		if count==3:
			app.match_world.mode.remaining=0;await frames(5)
			verify(app.screen=="results" and split.seats.all(func(seat:Dictionary):return not seat.hud.visible),"versus_match_finishes_with_results")
	await app.return_to_menu();await frames(3)
	verify(app.local_split==null and app.match_world==null and app.world_texture.visible,"return_to_menu_removes_split_screen")
	app.local_players=1;await app.start_match();await frames(3)
	verify(app.local_split==null and app.match_world.local_player_count==1 and app.hud.visible,"single_player_still_starts_after_split_screen")
	await app.dispose_match()
	var failed:=results.filter(func(row:Dictionary):return not row.passed).size()
	var report:={"passed":results.size()-failed,"failed":failed,"tests":results}
	var file:=FileAccess.open("res://.artifacts/reports/local-multiplayer-rendered.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("LOCAL_SPLIT_RENDER_RESULT ",JSON.stringify(report))
	app.queue_free();await frames(3);quit(0 if failed==0 else 1)
