extends SceneTree

class IdleController extends BotController:
	func perceive(_actor:Combatant,_world:Object) -> void:pass
	func choose_goal(_actor:Combatant,_world:Object) -> void:pass
	func command(actor:Combatant,_world:Object,_delta:float) -> ActorCommand:
		var result:=ActorCommand.new();result.aim_yaw=actor.yaw;return result

class FiringController extends IdleController:
	var starts:=1000.0
	func command(_actor:Combatant,world:Object,_delta:float) -> ActorCommand:
		var result:=ActorCommand.new();result.aim_yaw=-PI*.5;result.aim_pitch=-.055;result.aim_down_sights=true
		result.fire_held=world.clock>=starts
		return result

var results:Array[Dictionary]=[]
func verify(condition:bool,name:String) -> void:
	results.append({"name":name,"passed":condition});print("PASS " if condition else "FAIL ",name)

func _initialize() -> void:call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,720)
	var app:Variant=load("res://game/core/app.tscn").instantiate();root.add_child(app)
	app.qa["qa"]="replay-inspection";app.profile.directory="res://.artifacts/replay-profile"
	await app.start_match()
	var world:MatchWorld=app.match_world
	world.countdown=0
	for actor in world.actors:
		if actor.slot.id!=0:actor.bot=IdleController.new(actor.slot.id)
	world.actors[0].bot=null
	var player:Combatant=world.actors[0];var killer:Combatant=world.actors[MatchWorld.TEAM_SIZE]
	player.global_position=Vector3(6,.1,0);player.reset_physics_interpolation();player.protected_until=0
	killer.global_position=Vector3(-6,.1,0);killer.reset_physics_interpolation()
	killer.slot.loadout=world.catalog.starter_loadouts()[0];killer.set_loadout(world.catalog)
	var firing:=FiringController.new(MatchWorld.TEAM_SIZE);firing.starts=world.clock+3.1;killer.bot=firing
	var life:=player.slot.life_id;var deadline:=Time.get_ticks_msec()+20000
	while player.alive and Time.get_ticks_msec()<deadline:await process_frame
	verify(not player.alive,"scripted_rifle_eliminates_player")
	var death_time:=player.slot.death_at
	while world.clock<death_time+.3 and Time.get_ticks_msec()<deadline:await process_frame
	verify(app.kill_replay.active,"replay_automatically_starts")
	verify(app.kill_replay.frames.size()>20 and app.kill_replay.frames[0].time<death_time-1,"replay_uses_predeath_history")
	verify(app.camera.global_position.distance_to(killer.eye())<1.5,"recorded_killer_first_person_camera")
	firing.starts=1000
	while world.clock<death_time+2.4 and Time.get_ticks_msec()<deadline:await process_frame
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute("res://.artifacts/screenshots/replay")
	root.get_texture().get_image().save_png("res://.artifacts/screenshots/replay/killer_pov.png")
	while player.slot.life_id==life and Time.get_ticks_msec()<deadline:await process_frame
	await process_frame
	verify(player.alive and player.slot.life_id==life+1 and absf(player.slot.spawned_at-death_time-3)<.04,"automatic_respawn_at_three_seconds")
	verify(not app.kill_replay.active and app.hands.player==player,"respawn_restores_player_view_and_weapon")
	# Second death verifies the actual F-key skip route and preserves the timer.
	while world.clock<player.slot.spawned_at+2 and Time.get_ticks_msec()<deadline:await process_frame
	player.protected_until=0;world.queue_damage(killer.slot.id,player,200,&"ar_a4",false);world.resolve_damage()
	while not app.kill_replay.active and Time.get_ticks_msec()<deadline:await process_frame
	var respawn_at:=player.slot.respawn_at;app.qa["allow-input"]=true
	var skip:=InputEventKey.new();skip.physical_keycode=KEY_F;skip.pressed=true;Input.parse_input_event(skip)
	skip=skip.duplicate();skip.pressed=false;Input.parse_input_event(skip)
	verify(not app.kill_replay.active and app.kill_replay.skipped and not player.alive,"F_skips_replay_without_extra_respawn")
	verify(is_equal_approx(player.slot.respawn_at,respawn_at),"skip_keeps_three_second_respawn_deadline")
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://.artifacts/screenshots/replay/skipped_countdown.png")
	var failed:=results.filter(func(row:Dictionary):return not row.passed).size()
	var file:=FileAccess.open("res://.artifacts/reports/replay.json",FileAccess.WRITE);file.store_string(JSON.stringify({"passed":results.size()-failed,"failed":failed,"tests":results},"\t"));file.close()
	if failed:push_error("Killer replay inspection failed")
	print("REPLAY CHECK ",results.size()-failed," passed / ",failed," failed")
	await app.safe_quit()
