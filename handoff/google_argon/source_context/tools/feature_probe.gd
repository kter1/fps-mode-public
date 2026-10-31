extends SceneTree

# Screenshots of the player-facing features in a real match (full window, HUD included):
# iron-sight and optic ADS, the knife slash, the damage vignette, the pickup prompt and the
# end-of-match kill cam.
#   godot --script res://tools/feature_probe.gd -- --map=harbor
# Stills in .artifacts/probes/features-<map>/

var app: Control
var out := ""

func _initialize() -> void:call_deferred("probe")

func shot(name: String) -> void:
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png"%[out,name])
	print("SHOT ",name)

func wait(seconds: float) -> void:
	var until:=Time.get_ticks_msec()+seconds*1000
	while Time.get_ticks_msec()<until:await process_frame

func probe() -> void:
	var map_id:="harbor"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_id=arg.trim_prefix("--map=")
	root.size=Vector2i(1280,720);root.unfocusable=true;root.mouse_passthrough=true
	out="res://.artifacts/probes/features-"+map_id
	DirAccess.make_dir_recursive_absolute(out)
	app=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	for frame in 10:await process_frame
	app.qa={"qa":"probe","allow-input":true}
	app.selected_map=map_id;app.start_match()
	while app.match_world==null or not app.match_world.ready_for_play or app.hud==null:await process_frame
	var world:MatchWorld=app.match_world
	world.qa_protect_player=true
	var player:=world.actors[0];player.bot=null;player.command=world.player_command
	await shot("countdown")
	while world.countdown>0:await process_frame
	await wait(.5)
	# ADS: iron sights on the L56 and AR-A4, the pistol, then a red dot.
	for setup in [["lmg_l56",[]],["lmg_l56",["reflex","compensator","extended"]],["ar_k47",[]],["pistol_p9",[]],["smg_v45",["reflex"]]]:
		var slot:=1 if setup[0].begins_with("pistol") else 0
		var attachments:Array[String]=[];attachments.assign(setup[1])
		player.weapons[slot].configure(world.catalog.weapons[setup[0]],attachments);player.selected_weapon=slot;player.refresh_gun()
		app.hands.refresh(player);app.controls.aiming=false
		await wait(.6)
		if setup[0]=="lmg_l56":await shot("hip_lmg_l56")
		app.controls.aiming=true
		await wait(.8)
		await shot("ads_"+setup[0]+("_"+"_".join(setup[1]) if not setup[1].is_empty() else ""))
		app.controls.aiming=false
	player.selected_weapon=0;player.weapons[0].configure(world.catalog.weapons.ar_a4,[]);player.refresh_gun();app.hands.refresh(player)
	await wait(.6)
	# Knife: freeze the simulation and place the slash at fixed moments.
	world.set_physics_process(false)
	for at in [.07,.14,.22,.4]:
		player.action_kind="melee";player.action_until=world.clock-at+Combatant.MELEE_TIME
		await shot("knife_%03d"%int(at*1000))
	player.action_kind="";player.action_until=world.clock
	# Damage: a hit from the right at 60 health, then critical health.
	player.health=60;world.player_damaged.emit(player.global_position+Basis(Vector3.UP,player.yaw)*Vector3(8,0,0))
	await shot("damage_hit_60")
	await wait(.8)
	player.health=22
	await wait(1.2)
	await shot("damage_critical_22")
	player.health=100;app.hud.wound=0
	world.set_physics_process(true)
	# A dropped gun at the player's feet: the pickup prompt.
	var dropped:=WeaponRuntime.new();dropped.configure(world.catalog.weapons.ar_k47);world.drop_weapon(world.actors[MatchWorld.TEAM_SIZE],dropped)
	world.pickups.back().position=player.global_position
	if is_instance_valid(world.pickups.back().node):world.pickups.back().node.global_position=player.global_position+Basis(Vector3.UP,player.yaw)*Vector3(0,.4,-1.2)
	await wait(.8)
	await shot("pickup_prompt")
	app.controls.last_was_pad=true
	await shot("pickup_prompt_pad")
	app.controls.last_was_pad=false
	# End of match: wait for a kill to be recorded, then finish the match.
	player.bot=BotController.new(0)
	var deadline:=Time.get_ticks_msec()+60000
	while world.final_kill.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	await wait(.5)
	world.mode.remaining=.01
	while app.screen!="killcam" and app.screen!="results":await process_frame
	print("END SCREEN ",app.screen," final_kill=",not world.final_kill.is_empty())
	if app.screen=="killcam":
		await wait(.6);await shot("killcam_early")
		while not app.kill_replay.final_cam or app.kill_replay.held<=0:
			if app.screen!="killcam":break
			await process_frame
		await shot("killcam_hold")
		while app.screen=="killcam":await process_frame
	await wait(.3)
	await shot("results")
	print("FEATURE PROBE PASS ",map_id)
	app.safe_quit()
