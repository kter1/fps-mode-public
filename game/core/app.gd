extends Control

const SPLIT_SCREEN := preload("res://game/local/local_split_screen.gd")
var local_players := 1
var local_all_controllers := false
var local_versus := false
var local_split: Control
var catalog: Catalog
var profile := ProfileStore.new()
var world_view: SubViewport
var world_texture: TextureRect
var camera: Camera3D
var shake_trauma := 0.0
var hands: ViewModel
var menu: Control
var hud: GameHUD
var match_world: MatchWorld
var backdrop: MapArena
var campaign_checkpoint := 0
var campaign_resume := false
var selected_mode := "tdm"
var selected_map := MapCatalog.default_id()
var pad_interacting := false
var selected_loadout := 0
var difficulty := 1
var screen := "main"
var look := Vector2.ZERO
var blocked_fire := true
var controls := PlayerControls.new()
var kill_replay:KillReplay
var player_life := -1
var rebind_action := ""
var rebind_button: Button
var qa: Dictionary = {}
var qa_elapsed := 0.0
var qa_start := -1.0
var qa_step := 0
var qa_next := 0.0
var frame_times: Array[float] = []
var render_cpu_total := 0.0
var render_gpu_total := 0.0
var physics_cpu_total := 0.0
var focused_frames := 0
var previous_frame_usec := 0
var qa_warmup := 30.0
var qa_duration := 600.0
var qa_seed := 1201
var qa_rounds: Array[Dictionary] = []
var qa_saved_contacts: Array[float] = []
var qa_restarting := false
var qa_capture_index := 0
var qa_smoke_phase := 0
var benchmark_started_usec := 0
var shutting_down := false
var preview_model: Node3D
var menu_audio: BattleAudio
var loadout_notice := ""
var cleanup_counts: Array[int] = []
var cleanup_round := -1
# Menu focus survives a rebuild of the same screen (option changes redraw it).
var last_menu_screen := ""
var focus_index := -1
# Real time Square went down by a dropped weapon (-1 when not held).
var pad_pickup_at := -1.0
var blue := Color("72c8e8")
var orange := Color("e6ab65")
var ink := Color("101b25")
var text_color := Color("e9eff3")
const BINDINGS := PlayerControls.KEYS

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	Input.use_accumulated_input=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var pair:=arg.trim_prefix("--").split("=",true,1)
			qa[pair[0]]=pair[1] if pair.size()>1 else true
	if qa.get("qa","") in ["smoke","smoke-export"]:
		# Synthetic InputEvents still use the normal input pipeline. The test
		# window must not consume hardware input while the user works nearby.
		get_window().unfocusable=true;get_window().mouse_passthrough=true
	selected_mode=str(qa.get("mode","tdm"))
	local_players=clampi(int(qa.get("local-players",1)),1,4)
	local_all_controllers=qa.has("all-controllers")
	selected_map=str(qa.get("map",MapCatalog.ids_for_mode(selected_mode)[0]))
	catalog=Catalog.new()
	profile.configure(catalog,str(qa.get("profile-dir","user://")))
	setup_input()
	setup_theme()
	setup_viewports()
	apply_settings()
	apply_window_mode()
	get_window().size_changed.connect(fit_render_resolution)
	if qa.get("qa","")=="benchmark":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
		get_window().always_on_top=true;DisplayServer.window_move_to_foreground()
	if qa.get("qa","")=="benchmark" and RenderingServer.has_method("viewport_set_measure_render_time"):
		RenderingServer.call("viewport_set_measure_render_time",world_view.get_viewport_rid(),true)
	menu=Control.new();menu.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var limiter:=AudioEffectLimiter.new();AudioServer.add_bus_effect(0,limiter)
	menu_audio=BattleAudio.new();add_child(menu_audio);menu_audio.initialize()
	if qa.has("qa"):
		selected_map=str(qa.get("map",MapCatalog.ids_for_mode(selected_mode)[0]));qa_seed=int(qa.get("seed",1201));qa_duration=float(qa.get("seconds",600))
		if qa.qa=="smoke":qa_warmup=0;qa_duration=30
		if qa.qa=="capture":qa_warmup=0
		if qa.qa in ["smoke","smoke-export"]:show_backdrop();main_menu()
		else:start_match()
	else:
		show_backdrop();main_menu()

func setup_input() -> void:
	PlayerControls.install(profile.settings.bindings)

func setup_theme() -> void:
	var skin:=Theme.new()
	skin.default_font_size=18
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("20303d") if state=="normal" else Color("345468")
		if state=="disabled":style.bg_color=Color("18232d")
		style.set_corner_radius_all(4);style.set_border_width_all(1);style.border_color=Color("405767")
		style.content_margin_left=18;style.content_margin_right=18;style.content_margin_top=11;style.content_margin_bottom=11
		skin.set_stylebox(state,"Button",style)
		skin.set_stylebox(state,"OptionButton",style)
	skin.set_color("font_color","Label",text_color)
	skin.set_color("font_color","Button",text_color)
	skin.set_color("font_disabled_color","Button",Color("657783"))
	theme=skin

func setup_viewports() -> void:
	world_view=SubViewport.new();world_view.name="WorldRender";world_view.own_world_3d=true;world_view.size=Vector2i(1920,1080)
	world_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;world_view.physics_object_picking=false
	# Conservative visibility: authored occluder volumes can hide visible
	# interiors as the camera crosses openings. Keep frustum culling only.
	world_view.use_occlusion_culling=false
	# SubViewports do not listen to 3D audio by default. The camera listener needs
	# this enabled for every spatial gunshot, footstep and explosion in its world.
	world_view.audio_listener_enable_3d=true
	add_child(world_view)
	world_texture=TextureRect.new();world_texture.texture=world_view.get_texture();world_texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	world_texture.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(world_texture);world_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	camera=Camera3D.new();camera.far=900;camera.near=.02;world_view.add_child(camera);camera.current=true
	camera.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	var listener:=AudioListener3D.new();listener.name="WorldListener";camera.add_child(listener);listener.make_current()
	# The first-person rig renders in the world pass so it shares the scene's
	# sun, sky, probes and shadows; its materials carry their own FOV and depth.
	hands=ViewModel.new();camera.add_child(hands);hands.shown=false
	hands.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF

func apply_settings() -> void:
	var quality:int=profile.settings.quality
	if qa.has("qa"):quality=1
	fit_render_resolution()
	# Spatial AA only smooths edges within one frame. Accumulate reprojected
	# samples to stabilize textures; multisampling also integrates thin geometry
	# before the temporal resolve, rather than leaving it to history alone.
	world_view.use_taa=true
	world_view.msaa_3d=Viewport.MSAA_4X
	world_view.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if quality==2 else RenderingServer.ENV_SSAO_QUALITY_MEDIUM,quality!=2,.5,2,50,300)
	RenderingServer.directional_shadow_atlas_set_size([1024,2048,4096][quality],false)
	AudioServer.set_bus_volume_db(0,linear_to_db(maxf(.001,float(profile.settings.volume))))
	AudioServer.set_bus_mute(0,float(profile.settings.volume)<=0)
	camera.fov=float(profile.settings.fov)
	var map:MapArena=match_world.arena if match_world!=null else backdrop
	if map!=null:map.apply_quality(quality)
	if match_world!=null and match_world.effects!=null:match_world.effects.set_quality(quality)

# The world renders at the window's pixel size; quality sets the internal 3D resolution.
func fit_render_resolution() -> void:
	var quality:int=1 if qa.has("qa") else profile.settings.quality
	var output:=get_window().size
	RenderScale.fit(world_view,output,output.y,quality,int(profile.settings.render_resolution)==1 and not qa.has("qa"))
	if local_split!=null:local_split.fit_views()

# Fullscreen by default: a 1280x720 window is a postage stamp on a 4K TV.
func apply_window_mode() -> void:
	# Probe scripts (--script) drive the app in a background window; leave it alone.
	if qa.has("qa") or DisplayServer.get_name()=="headless" or OS.get_cmdline_args().has("--script"):return
	var mode:=Window.MODE_FULLSCREEN if bool(profile.settings.fullscreen) else Window.MODE_WINDOWED
	if get_window().mode!=mode:get_window().mode=mode

func show_backdrop() -> void:
	if backdrop!=null:backdrop.queue_free()
	var id:=MapCatalog.backdrop_id()
	var path:=MapCatalog.scene_path(id)
	if not ResourceLoader.exists(path):return
	backdrop=load(path).instantiate()
	world_view.add_child(backdrop)
	var view:Dictionary=MapCatalog.entry(id).get("menu_backdrop",{"position":[38,26,39],"target":[0,3,0]})
	camera.position=MapCatalog.vec3(view.position);camera.look_at(MapCatalog.vec3(view.target))

func clear_menu() -> void:
	var owner:=get_viewport().gui_get_focus_owner()
	focus_index=menu_controls().find(owner) if owner!=null and screen==last_menu_screen else -1
	last_menu_screen=screen
	for child in menu.get_children():child.queue_free()
	if hud!=null:hud.visible=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	blocked_fire=true
	var shade:=ColorRect.new();shade.color=Color(.018,.03,.047,.83 if screen in ["loadout","settings"] else .62)
	menu.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	call_deferred("focus_first_button")

# With a controller connected, menus start focused on their first control (or, when a
# screen is rebuilt, the one that had focus) so the D-pad or left stick moves between them,
# Cross selects and Circle goes back.
func focus_first_button() -> void:
	if menu==null or (Input.get_connected_joypads().is_empty() and not controls.last_was_pad):return
	var candidates:=menu_controls()
	if candidates.is_empty():return
	candidates[clampi(focus_index,0,candidates.size()-1)].grab_focus()

# Buttons, option lists and sliders of the current menu, in tree order.
func menu_controls() -> Array[Control]:
	var found:Array[Control]=[]
	if menu==null:return found
	for node in menu.find_children("*","Control",true,false):
		var control:Control=node
		if control.focus_mode==Control.FOCUS_NONE or not control.is_visible_in_tree() or not (control is BaseButton or control is Range):continue
		if control is BaseButton and control.disabled:continue
		var leaving:=false;var up:Node=control
		while up!=null and up!=menu:leaving=leaving or up.is_queued_for_deletion();up=up.get_parent()
		if not leaving:found.append(control)
	return found

func column(position: Vector2, width := 500.0, parent: Control = null) -> VBoxContainer:
	var box:=VBoxContainer.new();box.position=position;box.custom_minimum_size.x=width;box.add_theme_constant_override("separation",12)
	(menu if parent==null else parent).add_child(box)
	return box

func label(parent: Node, text: String, font_size := 18, color := Color("e9eff3")) -> Label:
	var node:=Label.new();node.text=text;node.add_theme_font_size_override("font_size",font_size);node.add_theme_color_override("font_color",color);parent.add_child(node);return node

func button(parent: Node, text: String, callback: Callable) -> Button:
	var node:=Button.new();node.text=text;node.alignment=HORIZONTAL_ALIGNMENT_LEFT;node.custom_minimum_size.y=44;parent.add_child(node)
	node.mouse_entered.connect(func():if not node.disabled:menu_audio.play_sound("ui_focus",Vector3.ZERO,.18,true))
	node.focus_entered.connect(func():menu_audio.play_sound("ui_focus",Vector3.ZERO,.18,true))
	node.pressed.connect(func():menu_audio.play_sound("ui_accept",Vector3.ZERO,.24,true))
	node.pressed.connect(callback);return node

func main_menu() -> void:
	screen="main";clear_menu();hands.shown=false
	var box:=column(Vector2(62,54),510)
	box.add_theme_constant_override("separation",8)
	label(box,"F P S   M O D E   /   OFFLINE COMBAT",15,orange)
	label(box,"OWN THE",65)
	label(box,"FRONTLINE.",65,blue)
	var count:=MapCatalog.ids_for_mode("tdm").size()
	label(box,"%d COMBATANTS  /  %s BATTLEFIELD%s"%[MatchWorld.TEAM_SIZE*2,["NO","ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT","NINE"][count] if count<10 else str(count),"" if count==1 else "S"],13,Color("b2c0ca"))
	label(box,"PLAY",13,orange)
	button(box,"DEPLOY / TEAM DEATHMATCH    →",func():choose_mode("tdm"))
	button(box,"ZOMBIES / ROUND-BASED SURVIVAL    →",func():choose_mode("zombies"))
	button(box,"CAMPAIGN / DEAD CIRCUIT    →",campaign_menu)
	var utilities:=column(Vector2(62,508),510)
	utilities.add_theme_constant_override("separation",8)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);utilities.add_child(row)
	var armory:=button(row,"ARMORY & LOADOUTS",func():loadout_menu(false));armory.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var settings:=button(row,"SETTINGS",func():settings_menu(false));settings.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var secondary:=HBoxContainer.new();secondary.add_theme_constant_override("separation",12);utilities.add_child(secondary)
	var credits:=button(secondary,"ART CREDITS",art_credits);credits.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var exit:=button(secondary,"QUIT",func():profile.save();get_tree().quit());exit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var footer:=label(menu,"OFFLINE COMBAT   /   TEAM DEATHMATCH  •  %d V %d"%[MatchWorld.TEAM_SIZE,MatchWorld.TEAM_SIZE],12,Color("9dafbe"))
	footer.position=Vector2(64,660)

func art_credits() -> void:
	screen="credits";clear_menu()
	var box:=column(Vector2(64,80),800)
	label(box,"ART CREDITS",42,blue)
	label(box,"TEXTURED ZOMBIE / PIXELHOUSE",24)
	label(box,"Model and authored animations by Pixelhouse (2009).
CC BY 3.0. Adapted materials, scale, crawler mesh and animation.",19)
	var source:=LinkButton.new();source.text="opengameart.org/content/zombie";source.pressed.connect(func():OS.shell_open("https://opengameart.org/content/zombie"));box.add_child(source)
	label(box,"Creator: pixelhouse.com.ar  /  License: creativecommons.org/licenses/by/3.0/",15)
	label(box,"Environment props and scans: Poly Haven contributors, CC0.
Detailed asset credits are included in content/licenses and content/manifest.
Original gameplay code, ruin dressing, machines and synthesized cues: FPS Mode.",19)
	button(box,"BACK",main_menu)

func choose_mode(value: String) -> void:
	selected_mode=value
	if selected_map not in MapCatalog.ids_for_mode(value):selected_map=MapCatalog.ids_for_mode(value)[0]
	setup_menu()

func setup_menu() -> void:
	screen="setup";clear_menu()
	var scroll:=ScrollContainer.new();scroll.position=Vector2(64,48);scroll.size=Vector2(660,624);menu.add_child(scroll)
	var box:=column(Vector2.ZERO,620,scroll)
	box.custom_minimum_size.x=620
	label(box,"OPERATIONS / LOCAL MATCH",14,orange);label(box,"Choose your battlefield",36)
	var mode_select:=OptionButton.new();mode_select.add_item("TEAM DEATHMATCH");mode_select.add_item("ZOMBIES SURVIVAL");mode_select.select(1 if selected_mode=="zombies" else 0);box.add_child(mode_select)
	mode_select.item_selected.connect(func(index:int):choose_mode("zombies" if index==1 else "tdm"))
	label(box,"BATTLEFIELD",13,blue)
	var maps:=OptionButton.new()
	for item in MapCatalog.entries_for_mode(selected_mode):maps.add_item(str(item.display_name).to_upper()+"  /  "+str(item.get("menu_subtitle","")))
	maps.select(maxi(0,MapCatalog.ids_for_mode(selected_mode).find(selected_map)));box.add_child(maps)
	maps.item_selected.connect(func(index:int):selected_map=MapCatalog.ids_for_mode(selected_mode)[index])
	if selected_mode=="zombies":
		label(box,"PISTOL + KNIFE / SURVIVE THE ROUNDS",21,orange)
		label(box,"Repair windows. Earn points. Open routes.\nBuy chalk weapons, perks and the mystery box.\nKeep a crawler alive to rearm between fights.",17)
		var record: Dictionary=profile.zombies_records.get(selected_map,{})
		label(box,"BEST ROUND  %d"%int(record.get("round",0)),20,blue)
		button(box,"START ZOMBIES    →",start_match);button(box,"BACK",main_menu);return
	label(box,"OPPOSITION",13,blue)
	var players:=OptionButton.new()
	for count in range(1,5):players.add_item("%d LOCAL PLAYER%s"%[count,"" if count==1 else "S / SPLIT-SCREEN"])
	players.select(local_players-1);box.add_child(players)
	players.item_selected.connect(func(index:int):local_players=index+1;setup_menu())
	if local_players>1:
		var input_choice:=OptionButton.new();input_choice.add_item("P1 KEYBOARD + MOUSE / OTHERS CONTROLLERS");input_choice.add_item("ALL PLAYERS USE CONTROLLERS")
		input_choice.select(1 if local_all_controllers else 0);box.add_child(input_choice)
		input_choice.item_selected.connect(func(index:int):local_all_controllers=index==1;setup_menu())
		var teams:=OptionButton.new();teams.add_item("CO-OP / BLUE TEAM vs BOTS");teams.add_item("VERSUS / ALTERNATING TEAMS")
		teams.select(1 if local_versus else 0);box.add_child(teams);teams.item_selected.connect(func(index:int):local_versus=index==1)
		label(box,"Connect %d controllers. Press any button on a controller to take a free seat.\nHold Circle to go prone. Start/Options pauses everyone."%(local_players if local_all_controllers else local_players-1),14,blue)
	var level:=OptionButton.new()
	for name in ["EASY — relaxed reactions","NORMAL — balanced firefights","HARD — faster, more accurate"]:level.add_item(name)
	level.select(difficulty);box.add_child(level);level.item_selected.connect(func(index:int):difficulty=index)
	label(box,"LOADOUT",13,blue)
	var loadouts:=OptionButton.new()
	for item in profile.loadouts:loadouts.add_item(item.display_name+" / "+catalog.weapons[str(item.primary)].display_name)
	loadouts.select(selected_loadout);box.add_child(loadouts);loadouts.item_selected.connect(func(index:int):selected_loadout=index)
	label(box,"YOU + %d ALLIES  vs  %d ENEMIES\n%d kills / 10 minutes / fast respawns"%[MatchWorld.TEAM_SIZE-1,MatchWorld.TEAM_SIZE,TeamDeathmatchMode.new().kill_limit],17,Color("acbdc9"))
	button(box,"START TEAM DEATHMATCH    →",start_match)
	button(box,"BACK",main_menu)

func start_match() -> void:
	if selected_mode=="zombies":print("ZOMBIES LOAD begin")
	get_tree().paused=false;screen="loading";clear_menu()
	var loading:=column(Vector2(64,260),600);label(loading,"DEPLOYING",45);label(loading,selected_map.to_upper()+" / PREPARING NAVIGATION",16,blue)
	await get_tree().process_frame
	if backdrop!=null:backdrop.free();backdrop=null
	await dispose_match()
	if not ResourceLoader.exists("res://game/maps/generated/"+selected_map+".tscn"):
		show_error("The selected map is missing. Run preparation from the project tools.");return
	match_world=CampaignWorld.new() if selected_mode=="campaign" else (ZombiesWorld.new() if selected_mode=="zombies" else MatchWorld.new())
	if match_world is CampaignWorld:match_world.initial_stage=campaign_checkpoint if campaign_resume else 0
	world_view.add_child(match_world)
	match_world.local_player_count=local_players if selected_mode=="tdm" else 1
	match_world.local_versus=local_versus
	match_world.stress_mode=qa.has("stress")
	match_world.profile_phases=qa.has("profile-simulation")
	match_world.configure(catalog,selected_map,profile.loadouts[selected_loadout],difficulty,qa_seed,qa.has("qa"))
	if selected_mode=="campaign":match_world.mode.checkpoint_reached.connect(save_campaign_checkpoint)
	if selected_mode=="zombies":print("ZOMBIES LOAD configured")
	match_world.qa_protect_player=qa.get("qa","")=="capture"
	if qa.has("swap") and selected_mode=="tdm":
		match_world.arena.definition=match_world.arena.definition.duplicate(true)
		var blue_spawns:=match_world.arena.definition.spawns_blue.duplicate()
		match_world.arena.definition.spawns_blue=match_world.arena.definition.spawns_red
		match_world.arena.definition.spawns_red=blue_spawns
		if match_world.actors[0].bot!=null:match_world.actors[0].bot.qa_route.clear()
	match_world.ended.connect(on_match_ended)
	match_world.effects.shake_requested.connect(add_shake)
	shake_trauma=0.0
	match_world.player_eliminated.connect(begin_kill_replay)
	pad_pickup_at=-1.0
	match_world.weapon_changed.connect(func():
		if local_split==null:hands.refresh(match_world.actors[0]))
	var load_started:=Time.get_ticks_msec()
	while not match_world.ready_for_play:
		await get_tree().process_frame
		# Packaged first launches can compile shaders while navigation waits for frames.
		if Time.get_ticks_msec()-load_started>120000:
			push_error("Match navigation/spawning did not become ready within 120 seconds")
			if qa.has("qa"):get_tree().quit(1)
			else:show_error("The battlefield could not finish loading. Please return to the menu and try again.")
			return
	if selected_mode=="zombies":print("ZOMBIES LOAD navigation ready")
	hands.refresh(match_world.actors[0]);hands.shown=true
	hud=ZombiesHUD.new() if selected_mode=="zombies" else GameHUD.new();add_child(hud);hud.connect_world(match_world,camera)
	if DisplayServer.get_name()!="headless" and selected_mode=="tdm" and match_world.local_player_count==1:
		kill_replay=KillReplay.new();world_view.add_child(kill_replay);kill_replay.configure(match_world)
	for child in menu.get_children():child.queue_free()
	menu.move_to_front();screen="playing";blocked_fire=true
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if not qa.has("qa") else Input.MOUSE_MODE_VISIBLE
	look=Vector2(match_world.actors[0].yaw,0)
	qa_restarting=false
	apply_settings()
	if match_world.local_player_count>1:
		local_split=SPLIT_SCREEN.new();add_child(local_split);local_split.configure(self,local_all_controllers)
		menu.move_to_front()
	if qa.get("qa","")=="capture":qa_next=qa_elapsed+4.0

func pause_menu() -> void:
	if match_world==null:return
	if match_world is ZombiesWorld:match_world.interactions.cancel()
	get_tree().paused=true;screen="pause";clear_menu()
	match_world.player_command=ActorCommand.new()
	controls.reset();pad_interacting=false
	if local_split!=null:local_split.reset_inputs()
	var box:=column(Vector2(64,85),440)
	label(box,"OPERATIONS PAUSED",14,orange);label(box,"Take a breath.",42)
	button(box,"RESUME",resume_match)
	if selected_mode=="tdm":button(box,"LOADOUTS / NEXT DEPLOYMENT",func():loadout_menu(true))
	button(box,"SETTINGS",func():settings_menu(true))
	button(box,"RETURN TO MAIN MENU",return_to_menu)

func resume_match() -> void:
	get_tree().paused=false;screen="playing"
	hud.visible=true
	for child in menu.get_children():child.queue_free()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if qa.has("qa") else Input.MOUSE_MODE_CAPTURED;blocked_fire=true
	match_world.player_command=ActorCommand.new()
	controls.reset()
	if local_split!=null:local_split.reset_inputs();hud.hide()

func return_to_menu() -> void:
	get_tree().paused=false
	screen="loading"
	await dispose_match()
	hands.player=null;hands.shown=false
	show_backdrop();main_menu()

func show_error(message:String) -> void:
	screen="error";clear_menu()
	var box:=column(Vector2(64,180),950)
	label(box,"UNABLE TO DEPLOY",36,orange);label(box,message,19)
	button(box,"MAIN MENU",return_to_menu)

func dispose_match() -> void:
	if local_split!=null:
		local_split.shutdown();local_split.free();local_split=null
	if kill_replay!=null:
		kill_replay.stop();kill_replay.queue_free();kill_replay=null
	if hud!=null:hud.hide();hud.queue_free();hud=null
	hands.player=null
	if match_world==null:return
	var old:=match_world;match_world=null
	old.set_physics_process(false);old.hide()
	# Keep GPU resources alive until the renderer has removed every old instance.
	var retired:Array[Resource]=[]
	for instance in old.find_children("*","MeshInstance3D",true,false):
		if instance.mesh!=null:
			retired.append(instance.mesh)
			for surface in instance.mesh.get_surface_count():
				var material:Material=instance.get_active_material(surface)
				if material!=null:retired.append(material)
		if instance.material_override!=null:retired.append(instance.material_override)
	old.get_parent().remove_child(old);old.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless":RenderingServer.force_draw(false)
	retired.clear()

func loadout_menu(in_match: bool) -> void:
	screen="loadout";clear_menu()
	var box:=column(Vector2(48,38),510)
	label(box,"ARMORY / ALL EQUIPMENT AVAILABLE",13,orange);label(box,"Build your loadout",34)
	var preset:=OptionButton.new()
	for item in profile.loadouts:preset.add_item(item.display_name)
	preset.select(selected_loadout);box.add_child(preset)
	preset.item_selected.connect(func(index:int):
		selected_loadout=index
		if in_match:match_world.slots[0].loadout=profile.loadouts[index]
		loadout_menu(in_match))
	var loadout:=profile.loadouts[selected_loadout]
	for weapon_slot in 2:
		label(box,"PRIMARY" if weapon_slot==0 else "SIDEARM",12,blue)
		var choose:=OptionButton.new()
		var ids:Array[String]=catalog.weapon_ids.slice(0,12) if weapon_slot==0 else catalog.weapon_ids.slice(12)
		var current:=str(loadout.primary if weapon_slot==0 else loadout.sidearm)
		for id in ids:choose.add_item(catalog.weapons[id].display_name)
		choose.select(ids.find(current));box.add_child(choose)
		choose.item_selected.connect(func(index:int):
			if weapon_slot==0:loadout.primary=StringName(ids[index]);loadout.primary_attachments=[]
			else:loadout.sidearm=StringName(ids[index]);loadout.sidearm_attachments=[]
			profile.save();loadout_menu(in_match))
	var summary:=WeaponRuntime.new();summary.configure(catalog.weapons[str(loadout.primary)],loadout.primary_attachments)
	var damage_label:="%d × %d"%[summary.definition.pellets,summary.definition.damage] if summary.definition.pellets>1 else str(roundi(summary.definition.damage))
	label(box,"%s DAMAGE  /  %d RPM  /  %d → %d ROUNDS"%[damage_label,summary.definition.rpm,summary.definition.capacity,summary.capacity],15)
	label(box,"BASE → EQUIPPED   AIM %.2f → %.2fs   RELOAD %.2f → %.2fs"%[summary.definition.ads_seconds,summary.ads_time,summary.definition.reload_seconds,summary.reload_time],12,Color("b1c0ca"))
	var sidearm:=WeaponRuntime.new();sidearm.configure(catalog.weapons[str(loadout.sidearm)],loadout.sidearm_attachments)
	label(box,"SIDEARM  %d DMG · %d → %d RDS · RELOAD %.2f → %.2fs\n"%[sidearm.definition.damage,sidearm.definition.capacity,sidearm.capacity,sidearm.definition.reload_seconds,sidearm.reload_time]+("Changes apply next deployment." if in_match else "Five presets save automatically. All equipment is unlocked."),13,Color("a3b7c6"))
	var back:=button(menu,"BACK",pause_menu if in_match else main_menu);back.position=Vector2(48,658);back.size=Vector2(510,44)
	weapon_preview(loadout)
	var right:=column(Vector2(610,80),610)
	if loadout_notice!="":label(right,loadout_notice,13,orange)
	label(right,"PRIMARY ATTACHMENTS",14,blue)
	attachment_controls(right,loadout,0,in_match)
	label(right,"SIDEARM ATTACHMENTS",14,blue)
	attachment_controls(right,loadout,1,in_match)

func weapon_preview(loadout:LoadoutDefinition) -> void:
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.size=Vector2i(900,300);viewport.transparent_bg=false;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;menu.add_child(viewport)
	var camera_preview:=Camera3D.new();viewport.add_child(camera_preview);camera_preview.position=Vector3(1.5,.45,.3);camera_preview.look_at(Vector3.ZERO);camera_preview.projection=Camera3D.PROJECTION_ORTHOGONAL;camera_preview.size=.5;camera_preview.current=true
	var environment:=WorldEnvironment.new();var env:=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("14212d");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("b7cbd8");env.ambient_light_energy=.6;environment.environment=env;viewport.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-30,0);light.light_color=Color("b7d9ee");light.light_energy=1.7;viewport.add_child(light)
	preview_model=ModelFactory.weapon(catalog.weapons[str(loadout.primary)],loadout.primary_attachments);viewport.add_child(preview_model)
	var texture:=TextureRect.new();texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;texture.texture=viewport.get_texture();texture.position=Vector2(48,490);texture.size=Vector2(510,155);texture.mouse_filter=Control.MOUSE_FILTER_IGNORE;menu.add_child(texture)

func attachment_controls(parent: VBoxContainer, loadout: LoadoutDefinition, weapon_slot: int, in_match: bool) -> void:
	var id:=str(loadout.primary if weapon_slot==0 else loadout.sidearm)
	var selected:Array[String]=loadout.primary_attachments if weapon_slot==0 else loadout.sidearm_attachments
	for slot_name in ["optic","muzzle","magazine","grip"]:
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);parent.add_child(row)
		var title:=label(row,slot_name.to_upper(),12);title.custom_minimum_size.x=95
		var options:=OptionButton.new();options.custom_minimum_size.x=470;options.clip_text=true
		options.add_item(("Standard 6× scope" if catalog.weapons[id].category=="sniper" else "Bare / iron sights") if slot_name=="optic" else "Standard / none")
		var choices:Array[String]=[""]
		for aid in catalog.attachment_ids:
			var entry:AttachmentDefinition=catalog.attachments[aid]
			if entry.slot!=slot_name:continue
			choices.append(aid);options.add_item(entry.display_name+" · "+entry.description)
			if not entry.compatible(catalog.weapons[id]):options.set_item_disabled(choices.size()-1,true);options.set_item_text(choices.size()-1,entry.display_name+" — "+entry.incompatibility_reason(catalog.weapons[id]))
			if selected.has(aid):options.select(choices.size()-1)
		row.add_child(options)
		options.item_selected.connect(func(index:int):
			var new_values:Array[String]=[]
			for existing in selected:
				if catalog.attachments[existing].slot!=slot_name:new_values.append(existing)
			if index>0:new_values.append(choices[index])
			if new_values.size()>3:
				loadout_notice="Remove an attachment before adding a fourth.";loadout_menu(in_match);return
			loadout_notice=""
			if weapon_slot==0:loadout.primary_attachments=new_values
			else:loadout.sidearm_attachments=new_values
			profile.save();loadout_menu(in_match))

func settings_menu(in_match: bool) -> void:
	screen="settings";clear_menu()
	var box:=column(Vector2(48,40),505)
	box.add_theme_constant_override("separation",7)
	label(box,"PREFERENCES",13,orange);label(box,"Make it yours",36)
	for setting in [["sensitivity","MOUSE SENSITIVITY",.01,.4,.01],["fov","VERTICAL FIELD OF VIEW",60,90,1],["volume","MASTER VOLUME",0,1,.05],["shake","WEAPON / CAMERA KICK",0,1,.05],["pad_sensitivity","CONTROLLER LOOK SENSITIVITY",.3,2.5,.05]]:
		label(box,setting[1]+"  /  "+str(profile.settings[setting[0]]),13,blue)
		var slider:=HSlider.new();slider.min_value=setting[2];slider.max_value=setting[3];slider.step=setting[4];slider.value=profile.settings[setting[0]];slider.custom_minimum_size.y=28;box.add_child(slider)
		slider.value_changed.connect(func(value:float):profile.settings[setting[0]]=value;apply_settings();profile.save())
	label(box,"GRAPHICS",13,blue)
	var quality:=OptionButton.new()
	for name in ["LOW / 810p UPSCALED","MEDIUM / 1080p UPSCALED","HIGH / 1440p UPSCALED","HIGH / NATIVE SCREEN RESOLUTION"]:quality.add_item(name)
	quality.select(3 if profile.settings.quality==2 and profile.settings.render_resolution==1 else profile.settings.quality);box.add_child(quality)
	quality.item_selected.connect(func(value:int):profile.settings.quality=mini(value,2);profile.settings.render_resolution=int(value==3);apply_settings();profile.save())
	var assist:=OptionButton.new();assist.add_item("CONTROLLER AIM ASSIST · OFF");assist.add_item("CONTROLLER AIM ASSIST · ON")
	assist.select(1 if profile.settings.get("aim_assist",true) else 0);box.add_child(assist)
	assist.item_selected.connect(func(value:int):profile.settings.aim_assist=value==1;profile.save())
	for setting in [["toggle_aim","SECONDARY CLICK AIM"],["toggle_sprint","SPRINT: SHIFT"]]:
		var option:=OptionButton.new();option.add_item(setting[1]+" · HOLD");option.add_item(setting[1]+" · TOGGLE")
		option.select(1 if profile.settings[setting[0]] else 0);box.add_child(option)
		option.item_selected.connect(func(value:int):profile.settings[setting[0]]=value==1;controls.reset();profile.save())
	label(box,"LAPTOP: C aims · hold F to fire · Shift + W sprints.\nOne finger looks · two-finger secondary click also aims.",13,blue)
	button(box,"BACK",pause_menu if in_match else main_menu)
	var bindings:=column(Vector2(625,44),565)
	label(bindings,"KEYBOARD BINDINGS",14,blue)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(565,530);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;bindings.add_child(scroll)
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",3);scroll.add_child(grid)
	for action in BINDINGS:
		label(grid,{"aim_toggle":"AIM / TOGGLE","fire_key":"FIRE / ALTERNATE"}.get(action,action.to_upper()),12).custom_minimum_size.x=190
		var current:int=int(profile.settings.bindings.get(action,BINDINGS[action]))
		var bind:=button(grid,OS.get_keycode_string(current),func():pass);bind.custom_minimum_size=Vector2(280,28);bind.add_theme_font_size_override("font_size",12)
		bind.pressed.connect(func():rebind_action=action;rebind_button=bind;bind.text="PRESS A KEY…")
	var display:=OptionButton.new();display.add_item("DISPLAY · FULLSCREEN");display.add_item("DISPLAY · WINDOWED")
	display.select(0 if profile.settings.fullscreen else 1);bindings.add_child(display)
	display.item_selected.connect(func(value:int):profile.settings.fullscreen=value==0;apply_window_mode();profile.save())

func on_match_ended() -> void:
	if selected_mode=="campaign":
		show_campaign_results();return
	if selected_mode=="zombies":
		show_zombies_results();return
	if kill_replay!=null:kill_replay.stop()
	if qa.has("qa"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps=0
		qa_rounds.append({"result":match_world.mode.get_result(),"clock":match_world.clock,"slots":match_world.slots.size()})
		qa_rounds.back()["route_visits"]=match_world.actors[0].bot.qa_route_visits.duplicate() if match_world.actors[0].bot!=null else []
		qa_rounds.back()["shots"]=match_world.sequence;qa_rounds.back()["lane_ticks"]=match_world.lane_ticks.duplicate()
		if qa.qa=="cleanup":
			if qa_rounds.size()<3:qa_restarting=true;start_match();return
			var stable:bool=cleanup_counts.size()==3 and cleanup_counts.min()==cleanup_counts.max()
			save_json(artifact_dir()+"/render-cleanup-"+selected_map+".json",{"passed":stable,"rounds":3,"node_counts":cleanup_counts})
			if not stable:push_error("Rendered rematches accumulated nodes: "+str(cleanup_counts))
			print("RENDER CLEANUP ","PASS" if stable else "FAIL"," ",cleanup_counts);safe_quit();return
		qa_saved_contacts.append_array(match_world.contact_times)
		if qa.qa=="matchtest":
			save_json(artifact_dir()+"/match-"+selected_map+("-swapped" if qa.has("swap") else "")+".json",{"passed":match_world.slots.size()==MatchWorld.TEAM_SIZE*2 and match_world.mode.finished,"clock":match_world.clock,"result":match_world.mode.get_result(),"slots":match_world.slots.size(),"swapped":qa.has("swap"),"contact_samples":match_world.contact_times.size()})
			print("FULL MATCH PASS ",selected_map," swapped=",qa.has("swap"));safe_quit();return
		if qa.qa=="benchmark":
			qa_restarting=true;start_match();return
	if kill_replay!=null and final_killcam():return
	show_results()

# The end-of-match kill cam: the last kill of the match from the killer's eyes, slowing
# into the shot and holding on it, then the results. Any fire, jump or accept skips it.
func final_killcam() -> bool:
	var kill:Dictionary=match_world.final_kill
	if kill.is_empty() or not kill_replay.begin_final(int(kill.source),kill.frames):return false
	screen="killcam"
	for child in menu.get_children():child.queue_free()
	controls.reset();blocked_fire=true;pad_pickup_at=-1.0
	hud.visible=true;hud.show_scoreboard=false;hud.replaying=true;hud.final_kill=true
	hud.replay_killer=match_world.slots[int(kill.source)].callsign;hud.replay_victim=match_world.slots[int(kill.victim)].callsign
	hud.replay_actor=kill_replay.replay_actor;hud.replay_team=match_world.slots[int(kill.source)].team
	return true

func show_results() -> void:
	if kill_replay!=null:kill_replay.stop()
	hud.final_kill=false;hud.replaying=false;hands.shown=false
	screen="results";clear_menu();hud.show_scoreboard=false
	var result: Dictionary=match_world.mode.get_result()
	match_world.effects.sound("match_win" if result.winner<=0 else "match_loss",Vector3.ZERO,.65,true)
	var box:=column(Vector2(64,75),510)
	label(box,"OPERATION COMPLETE",14,orange)
	label(box,"DRAW" if result.winner<0 else ("VICTORY" if result.winner==0 else "DEFEAT"),61,blue if result.winner==0 else orange)
	label(box,"BLUE %d  /  RED %d"%[result.scores[0],result.scores[1]],27)
	label(box,"YOUR RECORD   %d KILLS / %d DEATHS"%[match_world.slots[0].kills,match_world.slots[0].deaths],17)
	button(box,"REMATCH",start_match)
	button(box,"MAIN MENU",return_to_menu)
	var table:=column(Vector2(650,105),570)
	label(table,"FINAL ROSTER",14,blue)
	var teams:=HBoxContainer.new();teams.add_theme_constant_override("separation",20);table.add_child(teams)
	for team in 2:
		var entries:=VBoxContainer.new();entries.custom_minimum_size.x=260;entries.add_theme_constant_override("separation",10);teams.add_child(entries)
		label(entries,"BLUE              K / D" if team==0 else "RED               K / D",14,blue if team==0 else orange)
		for slot in match_world.slots:
			if slot.team!=team:continue
			var row:=HBoxContainer.new();entries.add_child(row)
			label(row,slot.callsign,14).custom_minimum_size.x=170
			label(row,"%02d / %02d"%[slot.kills,slot.deaths],14)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value)>.5):controls.last_was_pad=true
	elif event is InputEventKey or event is InputEventMouseButton:controls.last_was_pad=false

func _unhandled_input(event: InputEvent) -> void:
	if local_split!=null and screen!="playing" and event is InputEventJoypadButton:
		event=event.duplicate();event.device=0
	if rebind_action!="" and event is InputEventKey and event.pressed and not event.echo:
		var key:int=event.keycode if event.keycode>=KEY_SPECIAL else event.physical_keycode
		if key==0:key=event.keycode
		profile.settings.bindings[rebind_action]=key;rebind_button.text=OS.get_keycode_string(key);rebind_action="";setup_input();profile.save();return
	if screen=="killcam":
		if event.is_action_pressed("jump") or event.is_action_pressed("fire") or event.is_action_pressed("fire_key") or event.is_action_pressed("pad_fire") or event.is_action_pressed("ui_accept") or event.is_action_pressed("pause"):show_results()
		return
	if not (screen in ["playing","loading"]):
		# A controller in a menu with nothing focused (the mouse was used last): focus it.
		if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and get_viewport().gui_get_focus_owner()==null:focus_first_button()
		if event is InputEventJoypadButton and event.is_action_pressed("ui_cancel"):
			match screen:
				"pause":resume_match()
				"settings","loadout":
					if match_world!=null:pause_menu()
					else:main_menu()
				"setup":main_menu()
			return
	if (event.is_action_pressed("pause") or (local_split!=null and event is InputEventJoypadButton and event.pressed and event.button_index==JOY_BUTTON_START)) and match_world!=null and not qa.has("qa"):
		if screen=="playing":pause_menu()
		elif screen=="pause":resume_match()
		return
	if screen!="playing" or (qa.has("qa") and not qa.has("allow-input")) or match_world==null:return
	if local_split!=null:
		local_split.handle(event);return
	if not match_world.actors[0].alive:
		if kill_replay!=null and kill_replay.active and (event.is_action_pressed("jump") or event.is_action_pressed("fire_key") or event.is_action_pressed("fire") or event.is_action_pressed("ui_accept")):
			kill_replay.skip();hud.replaying=false;hands.player=match_world.actors[0];hands.shown=false;blocked_fire=true;controls.reset()
		return
	if event is InputEventMouseMotion:
		look.x-=deg_to_rad(event.screen_relative.x*float(profile.settings.sensitivity))
		look.y=clampf(look.y-deg_to_rad(event.screen_relative.y*float(profile.settings.sensitivity)),-1.48,1.48)
		match_world.player_command.aim_yaw=look.x;match_world.player_command.aim_pitch=look.y
	var command:=match_world.player_command
	controls.handle(event,profile.settings.toggle_aim,profile.settings.toggle_sprint)
	if (event.is_action_pressed("fire") or event.is_action_pressed("fire_key") or event.is_action_pressed("pad_fire")) and not blocked_fire:command.fire_pressed=true
	if event.is_action_pressed("pad_switch"):command.requested_weapon_slot=1-match_world.actors[0].selected_weapon
	if event.is_action_pressed("reload"):
		# Square by a dropped weapon: a tap reloads, holding it picks the weapon up.
		if event is InputEventJoypadButton and ((match_world is ZombiesWorld and match_world.interactions.candidate!=null) or not match_world.swap_candidate(match_world.actors[0]).is_empty()):pad_pickup_at=Time.get_ticks_msec()/1000.0
		else:command.reload_pressed=true
	if event.is_action_released("reload") and event is InputEventJoypadButton:
		if pad_pickup_at>=0:pad_pickup_at=-1.0;command.reload_pressed=true
		pad_interacting=false
	if event.is_action_pressed("interact"):command.interact_pressed=true
	if event.is_action_pressed("jump"):command.jump_pressed=true
	if event.is_action_pressed("melee"):command.melee_pressed=true
	if event.is_action_pressed("frag"):command.requested_throwable=0;command.throw_held=true
	if event.is_action_pressed("smoke"):command.requested_throwable=1;command.throw_held=true
	if event.is_action_released("frag") or event.is_action_released("smoke"):command.throw_held=false
	if event.is_action_pressed("primary"):command.requested_weapon_slot=0
	if event.is_action_pressed("secondary"):command.requested_weapon_slot=1
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:command.requested_weapon_slot=1-match_world.actors[0].selected_weapon

# Right stick: radial deadzone, a response curve for fine aim near centre, and a turn
# rate scaled by the controller sensitivity, slower while aiming down sights.
func pad_look(delta: float, player: Combatant) -> void:
	var pads:=Input.get_connected_joypads()
	if pads.is_empty():return
	var device:int=pads[0]
	var stick:=Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y))
	var size:=stick.length()
	var assist:=aim_assist_target(player) if bool(profile.settings.get("aim_assist",true)) and controls.last_was_pad else {}
	if size>=.14:
		var strength:=pow(clampf((size-.14)/.86,0,1),1.7)
		var rate:=deg_to_rad(240.0)*float(profile.settings.get("pad_sensitivity",1.0))*(.5 if hands.blend>.5 else 1.0)/maxf(1.0,player.weapon().magnification*.75)
		# Slowdown: the stick turns slower while the crosshair is on a visible enemy.
		if not assist.is_empty() and float(assist.angle)<deg_to_rad(3.5):rate*=.6
		var turn:=stick/size*strength*rate*delta
		look.x-=turn.x;look.y=clampf(look.y-turn.y*.8,-1.48,1.48)
		controls.last_was_pad=true
	# Gentle pull while aiming or firing AND giving input (stick or movement), never at rest.
	var moving:=size>=.14 or Input.get_vector("left","right","forward","back").length()>.2
	if not assist.is_empty() and moving and (hands.blend>.5 or controls.firing()):
		var step:=deg_to_rad(7.0)*delta
		look.x+=clampf(wrapf(float(assist.yaw)-look.x,-PI,PI),-step,step)
		look.y+=clampf(float(assist.pitch)-look.y,-step,step)

# Nearest visible enemy within 5 degrees of the crosshair (chest height): its angle
# from the aim line and the yaw/pitch that would centre it. Walls and smoke block it.
func aim_assist_target(player: Combatant) -> Dictionary:
	var eye:=player.eye();var best:={};var limit:=deg_to_rad(5.0)
	var forward:=Vector3(-sin(look.x)*cos(look.y),sin(look.y),-cos(look.x)*cos(look.y))
	for other in match_world.actors:
		if not other.alive or other.slot.team==player.slot.team:continue
		var target:Vector3=other.aim_target()
		var to:=target-eye;var distance:=to.length()
		if distance<1.0 or distance>60.0:continue
		var angle:=forward.angle_to(to/distance)
		if angle>limit or (not best.is_empty() and angle>=float(best.angle)):continue
		if not match_world.visible_between(eye,target):continue
		best={"angle":angle,"yaw":atan2(-to.x,-to.z),"pitch":asin(clampf(to.y/distance,-1,1))}
	return best

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and screen=="playing" and not qa.has("qa"):pause_menu()
	if what==NOTIFICATION_WM_CLOSE_REQUEST:profile.save()

func _process(delta: float) -> void:
	if shutting_down:return
	if is_instance_valid(preview_model):preview_model.rotation.y=sin(Time.get_ticks_msec()*.0004)*.3
	if match_world==null:
		if qa.get("qa","")=="smoke" or (selected_mode=="zombies" and qa.get("qa","")=="smoke-export"):qa_tick(delta)
		return
	if not match_world.ready_for_play:return
	if local_split!=null:
		local_split.tick(delta);return
	var player:=match_world.actors[0]
	if qa.get("qa","")=="smoke":qa["jump-peak"]=maxf(float(qa.get("jump-peak",0)),player.global_position.y)
	if player.slot.life_id!=player_life:
		player_life=player.slot.life_id;look=Vector2(player.yaw,player.pitch);blocked_fire=true;controls.reset()
		if kill_replay!=null and kill_replay.active:kill_replay.stop()
		hands.refresh(player);hands.shown=true;hud.replaying=false;pad_pickup_at=-1.0
	if screen=="killcam":
		if kill_replay!=null and kill_replay.active:kill_replay.advance(delta,camera,hands,float(profile.settings.fov))
		if kill_replay==null or not kill_replay.active or kill_replay.finished():show_results()
		if qa.has("qa"):qa_tick(delta)
		return
	if kill_replay!=null and kill_replay.active and screen=="playing" and not get_tree().paused:
		kill_replay.advance(delta,camera,hands,float(profile.settings.fov));hud.replaying=true
		hud.replay_actor=kill_replay.replay_actor
		if qa.has("qa"):qa_tick(delta)
		return
	if screen=="playing" and (not qa.has("qa") or qa.has("allow-input")):
		var command:=match_world.player_command
		command.interact_held=Input.is_action_pressed("interact") or pad_interacting
		command.movement=Input.get_vector("left","right","forward","back")
		pad_look(delta,player)
		command.aim_yaw=look.x;command.aim_pitch=look.y
		command.fire_held=controls.firing() and not blocked_fire
		command.aim_down_sights=controls.wants_aim(profile.settings.toggle_aim);command.sprint=controls.wants_sprint(profile.settings.toggle_sprint);command.crouch=controls.wants_crouch();command.prone=controls.wants_prone()
		if not Input.is_action_pressed("fire") and not Input.is_action_pressed("fire_key") and not Input.is_action_pressed("pad_fire"):blocked_fire=false
		if player.slot.life_id>0 and absf(player.yaw-look.x)>PI:look.x=player.yaw
		if pad_pickup_at>=0 and Time.get_ticks_msec()/1000.0-pad_pickup_at>=PlayerControls.PAD_PICKUP_HOLD:
			pad_pickup_at=-1.0;pad_interacting=true;command.interact_pressed=true
		hud.show_scoreboard=Input.is_action_pressed("scoreboard")
		hud.pad=controls.last_was_pad
	var position:Vector3=player.get_global_transform_interpolated().origin+Vector3.UP*player.eye_height
	camera.global_position=position
	var camera_look:=Vector2(player.yaw,player.pitch)
	if player.alive and player.bot==null and screen=="playing":camera_look=look
	camera.rotation=Vector3(camera_look.y+player.recoil,camera_look.x,player.recoil*.1*float(profile.settings.shake))
	if not player.alive:
		var focus:Vector3=player.global_position+Vector3.UP*.8
		var desired:=focus+Vector3.UP*3+Basis(Vector3.UP,player.yaw)*Vector3(0,0,4.5)
		var query:=PhysicsRayQueryParameters3D.create(focus,desired,1)
		var obstruction:=match_world.get_world_3d().direct_space_state.intersect_ray(query)
		camera.global_position=Vector3(obstruction.position).move_toward(focus,.3) if not obstruction.is_empty() else desired
		camera.look_at(focus)
	apply_shake(delta)
	# Paused, the rig holds its pose: ticking it would keep the sprint stride and bob
	# running on the frozen velocity behind the menu.
	if not get_tree().paused:hands.tick(delta,match_world.clock,float(profile.settings.shake))
	var base:float=profile.settings.fov
	var zoom:=hands.blend
	var aimed:=rad_to_deg(2*atan(tan(deg_to_rad(base)*.5)/player.weapon().magnification))
	camera.fov=lerpf(base,aimed,zoom)
	if not player.alive:camera.fov=base
	if qa.has("qa"):qa_tick(delta)

# Explosion shake: trauma falls off with distance from the blast, scales with the
# "weapon / camera kick" setting and decays quickly.
func add_shake(at: Vector3, strength: float) -> void:
	if camera==null:return
	var reach:=clampf(1.0-camera.global_position.distance_to(at)/45.0,0,1)
	shake_trauma=minf(1.0,shake_trauma+strength*reach*reach*float(profile.settings.shake))

func apply_shake(delta: float) -> void:
	if shake_trauma<=0:return
	shake_trauma=maxf(0,shake_trauma-delta*1.5)
	var amount:=shake_trauma*shake_trauma*.06;var t:=Time.get_ticks_msec()*.001
	camera.rotation+=Vector3(sin(t*61.0),sin(t*53.0+1.7),sin(t*47.0+3.1)*.5)*amount

func begin_kill_replay(source:int, death_time:float) -> void:
	if local_split!=null:return
	if kill_replay==null or source<0 or source==0 or match_world.mode.finished:return
	controls.reset();blocked_fire=true;match_world.player_command=ActorCommand.new()
	hud.replaying=kill_replay.begin(source,death_time)
	hud.replay_killer=match_world.slots[source].callsign

func artifact_dir() -> String:
	var directory:="res://.artifacts"
	if not OS.has_feature("editor"):directory=str(qa.get("profile-dir",OS.get_user_data_dir())).get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	return directory

func save_json(path: String, value: Variant) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(value,"\t"))

func qa_tick(delta: float) -> void:
	if selected_mode=="zombies":zombies_qa_tick(delta);return
	qa_elapsed+=delta
	if qa.qa=="campaign-voices":campaign_voice_smoke();return
	if qa.qa=="capture":qa_capture(delta);return
	if qa.qa=="smoke":qa_smoke(delta);return
	if qa.qa=="matchtest":return
	if qa.qa=="cleanup":
		if qa_restarting or match_world.mode.finished:return
		if match_world.clock>.5 and cleanup_round!=qa_rounds.size():
			cleanup_round=qa_rounds.size();cleanup_counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			for i in 24:match_world.effects.tracer(match_world.actors[0].eye(),match_world.actors[0].eye()+camera.global_basis*Vector3((i-12)*.05,.5,-4))
			for enemy in match_world.actors:
				if enemy.slot.team==1 and enemy.alive:
					enemy.protected_until=0;match_world.queue_damage(0,enemy,200,&"ar_a4",false);break
			match_world.resolve_damage();match_world.mode.remaining=.01
		return
	if qa.qa=="clip":
		if qa_elapsed>=qa_duration:safe_quit()
		return
	var now:=Time.get_ticks_usec()
	if benchmark_started_usec==0:benchmark_started_usec=now
	var elapsed:float=(now-benchmark_started_usec)/1000000.0
	if elapsed<qa_warmup:return
	if previous_frame_usec>0:
		frame_times.append((now-previous_frame_usec)/1000.0)
		physics_cpu_total+=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000
		if DisplayServer.window_is_focused():focused_frames+=1
		if RenderingServer.has_method("viewport_get_measured_render_time_cpu"):
			render_cpu_total+=float(RenderingServer.call("viewport_get_measured_render_time_cpu",world_view.get_viewport_rid()))
			render_gpu_total+=float(RenderingServer.call("viewport_get_measured_render_time_gpu",world_view.get_viewport_rid()))
	previous_frame_usec=now
	if elapsed>=qa_warmup+qa_duration:finish_benchmark();return
	if int(elapsed)%30==0 and qa_step!=int(elapsed):
		qa_step=int(elapsed);print("BENCHMARK ",selected_map," ",qa_step,"s / ",qa_duration+qa_warmup,"s; score=",match_world.mode.scores," rounds=",qa_rounds.size())

func finish_benchmark() -> void:
	var sorted:=frame_times.duplicate();sorted.sort()
	var total:=0.0;var over:=0
	for frame in sorted:
		total+=frame
		if frame>50:over+=1
	var average:=sorted.size()/maxf(.001,total/1000)
	var p95:float=sorted[clampi(ceili(sorted.size()*.95)-1,0,sorted.size()-1)]
	var p99:float=sorted[clampi(ceili(sorted.size()*.99)-1,0,sorted.size()-1)]
	var contacts_all:=qa_saved_contacts.duplicate();contacts_all.append_array(match_world.contact_times);contacts_all.sort()
	var result:={"map":selected_map,"seed":qa_seed,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"internal_resolution":[RenderScale.internal_size(world_view).x,RenderScale.internal_size(world_view).y],"slots":match_world.slots.size(),"sample_frames":sorted.size(),"measured_seconds":total/1000,"average_fps":average,"p95_ms":p95,"p99_ms":p99,"frames_over_50ms":over,"stress":qa.has("stress"),"completed_rounds":qa_rounds,"contact_samples":contacts_all.size(),"contact_median":contacts_all[contacts_all.size()/2] if not contacts_all.is_empty() else -1,"player_route_visits":match_world.actors[0].bot.qa_route_visits,"passed":average>=60 and p95<=20 and p99<=33.3}
	var suffix:="-stress" if qa.has("stress") else ""
	result["world_render_cpu_ms"]=render_cpu_total/maxi(1,frame_times.size())
	result["world_render_gpu_ms"]=render_gpu_total/maxi(1,frame_times.size())
	result["physics_cpu_ms"]=physics_cpu_total/maxi(1,frame_times.size())
	# macOS paces windows that are not frontmost to the display refresh, which caps
	# the run at 60 FPS; a benchmark is only representative when this is near 1.
	result["focused_fraction"]=float(focused_frames)/maxi(1,frame_times.size())
	if match_world.profile_phases:
		var sections:Dictionary={};var poses:=0
		for section in match_world.phase_usec:sections[section]=float(match_world.phase_usec[section])/maxi(1,match_world.profile_ticks)
		for actor in match_world.actors:poses+=actor.pose_cpu_usec
		result["simulation_profile_us_per_tick"]=sections;result["character_pose_us_per_tick"]=float(poses)/maxi(1,match_world.profile_ticks)
	result["vsync_mode"]=DisplayServer.window_get_vsync_mode();result["frame_cap"]=Engine.max_fps
	result["driver"]=RenderingServer.call("get_current_rendering_driver_name") if RenderingServer.has_method("get_current_rendering_driver_name") else "unavailable"
	result["current_round"]={"clock":match_world.clock,"scores":match_world.mode.scores,"shots":match_world.sequence,"lane_ticks":match_world.lane_ticks.duplicate()}
	if result.world_render_gpu_ms<=0:result.world_render_gpu_ms=null
	var prefix:=artifact_dir()+"/benchmark-"+selected_map+suffix
	save_json(prefix+".json",result)
	var file:=FileAccess.open(prefix+".csv",FileAccess.WRITE);file.store_line("frame,interval_ms")
	for i in frame_times.size():file.store_line("%d,%.4f"%[i,frame_times[i]])
	print("BENCHMARK_RESULT ",JSON.stringify(result));safe_quit()

func qa_capture(_delta: float) -> void:
	if selected_mode=="campaign":
		if qa_elapsed<qa_next:return
		qa_next=INF
		var directory:=artifact_dir()+"/screenshots/campaign"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		get_viewport().get_texture().get_image().save_png(directory+"/dead-circuit.png")
		print("CAMPAIGN CAPTURE PASS");safe_quit();return
	if qa_elapsed<qa_next:return
	qa_next=qa_elapsed+1.0
	var shots:=["blue_spawn","red_spawn","north_route","center_interior","south_route","elevated","ads","reload","firefight","smoke_outside","smoke_inside","loadout","hud_720p"]
	if qa_capture_index>=shots.size():
		save_json(artifact_dir()+"/capture-"+selected_map+".json",{"screenshots":shots,"map":selected_map,"renderer":RenderingServer.get_current_rendering_method()});print("CAPTURE PASS ",selected_map);safe_quit();return
	var shot:String=shots[qa_capture_index]
	if shot=="firefight" and match_world.clock<25:return
	var was_processing:=match_world.is_physics_processing();match_world.set_physics_process(false)
	# Map cameras for the first six shots and the first-person ones come from the registry.
	var views:Dictionary=MapCatalog.entry(selected_map).capture
	if qa_capture_index<6:camera.global_position=MapCatalog.vec3(views[shot].position);camera.look_at(MapCatalog.vec3(views[shot].target));hands.shown=false;hands.hide()
	else:
		hands.shown=true;hands.show()
		if shot in ["ads","reload"]:
			camera.global_position=MapCatalog.vec3(views.first_person.position)
			camera.look_at(MapCatalog.vec3(views.first_person.target))
		if shot=="ads":
			match_world.actors[0].weapon().state="READY";match_world.actors[0].weapon().ammo=30;hands.refresh(match_world.actors[0])
			match_world.actors[0].ads=true;hands.tick(1,match_world.clock,1)
			camera.fov=rad_to_deg(2*atan(tan(deg_to_rad(float(profile.settings.fov))*.5)/match_world.actors[0].weapon().magnification))
		if shot=="reload":match_world.actors[0].ads=false;match_world.actors[0].weapon().ammo=3;match_world.actors[0].weapon().start_reload(match_world.clock);hands.tick(1,match_world.clock+.7,1)
		if shot=="smoke_outside" or shot=="smoke_inside":
			var grenade:=GameGrenade.new();match_world.add_child(grenade);grenade.kind=1;grenade.global_position=camera.global_position+camera.global_basis*Vector3(0,-1,-(6 if shot=="smoke_outside" else 0));match_world.detonate(grenade);grenade.queue_free()
		if shot=="loadout":loadout_menu(false)
		if shot=="hud_720p":
			for child in menu.get_children():child.queue_free()
			screen="playing";hud.visible=true
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	if shot in ["smoke_outside","smoke_inside"]:
		for frame in 3:
			await get_tree().process_frame;RenderingServer.force_draw(false)
	var directory:=artifact_dir()+"/screenshots/"+selected_map
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	get_viewport().get_texture().get_image().save_png(directory+"/"+shot+".png")
	match_world.set_physics_process(was_processing)
	qa_capture_index+=1

func qa_smoke(_delta: float) -> void:
	if qa_elapsed<qa_next:return
	qa_next=qa_elapsed+2
	match qa_smoke_phase:
		0:
			if not qa_require(screen=="main","main menu"):return
			press_menu("DEPLOY")
		1:
			if not qa_require(screen=="setup","match setup"):return
			press_menu("START TEAM")
		2:
			if match_world==null or not match_world.ready_for_play or match_world.countdown>0:return
			if not qa_require(match_world.slots.size()==MatchWorld.TEAM_SIZE*2,"full roster"):return
			qa["allow-input"]=true;match_world.actors[0].bot=null;blocked_fire=false
			match_world.qa_protect_player=true
			controls.reset();match_world.player_command=ActorCommand.new();match_world.actors[0].command=match_world.player_command
			match_world.actors[0].weapon().configure(catalog.weapons.ar_a4,["reflex"]);match_world.actors[0].action_until=match_world.clock
			qa["ammo-before"]=match_world.actors[0].weapon().ammo
			var motion:=InputEventMouseMotion.new();motion.relative=Vector2(20,0);motion.screen_relative=Vector2(20,0)
			qa["expected-yaw"]=look.x-deg_to_rad(20*float(profile.settings.sensitivity))
			Input.parse_input_event(motion)
			# Assert the injected event's response now. Checking two seconds later
			# also includes unrelated physical mouse motion on this shared Mac.
			if not qa_require(is_equal_approx(look.x,float(qa["expected-yaw"])),"mouse look event response"):return
			qa["mouse-look-verified"]=true
			var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=size*.5;click.pressed=true;Input.parse_input_event(click)
			click=click.duplicate();click.pressed=false;Input.parse_input_event(click)
			var aim_click:=InputEventMouseButton.new();aim_click.button_index=MOUSE_BUTTON_RIGHT;aim_click.position=size*.5;aim_click.pressed=true;Input.parse_input_event(aim_click)
			aim_click=aim_click.duplicate();aim_click.pressed=false;Input.parse_input_event(aim_click)
		3:
			if not qa_require(bool(qa.get("mouse-look-verified",false)),"mouse look"):return
			if not qa_require(match_world.actors[0].weapon().ammo==int(qa["ammo-before"])-1,"quick click fire"):return
			if not qa_require(match_world.actors[0].ads and hands.blend>.95 and camera.fov<float(profile.settings.fov)-5,"toggle ADS persists after secondary click release"):return
			send_key("aim_toggle")
			if not qa_require(not controls.aiming,"C releases toggle aim"):return
			var shift:=InputEventKey.new();shift.keycode=KEY_SHIFT;shift.pressed=true;Input.parse_input_event(shift)
			if not qa_require(Input.is_action_pressed("sprint"),"native Shift sprint binding"):return
			shift.pressed=false;Input.parse_input_event(shift)
			qa["keyboard-ammo-before"]=match_world.actors[0].weapon().ammo
			send_key("aim_toggle");send_key("fire_key")
			qa["jump-peak"]=0.0
			send_key("jump")
		4:
			if not qa_require(float(qa["jump-peak"])>.3,"jump"):return
			if not qa_require(match_world.actors[0].ads and match_world.actors[0].weapon().ammo==int(qa["keyboard-ammo-before"])-1,"keyboard F fires while C aim is active"):return
			send_key("aim_toggle")
			send_key("reload")
			qa["reload-request-clock"]=match_world.clock;qa_next=qa_elapsed+.05
		5:
			if match_world.actors[0].weapon().state!="RELOADING" and match_world.clock<float(qa["reload-request-clock"])+.25:
				qa_next=qa_elapsed+.05;return
			if not qa_require(match_world.actors[0].weapon().state=="RELOADING","reload start"):return
			qa["reload-deadline"]=match_world.actors[0].weapon().reload_at;qa_next=qa_elapsed+.05
		6:
			if match_world.clock<float(qa["reload-deadline"])+.05:
				qa_next=qa_elapsed+.05;return
			if not qa_require(match_world.actors[0].weapon().ammo==match_world.actors[0].weapon().capacity,"reload completion"):return
			pause_menu();qa["paused-clock"]=match_world.clock
		7:
			if not qa_require(get_tree().paused and match_world.clock==float(qa["paused-clock"]),"pause freezes time"):return
			resume_match()
		8:
			if not qa_require(match_world.clock>float(qa["paused-clock"]),"resume"):return
			match_world.qa_protect_player=false
			var player:=match_world.actors[0];player.protected_until=0
			qa["replay-life"]=player.slot.life_id
			match_world.queue_damage(MatchWorld.TEAM_SIZE,player,200,&"ar_a4",false);match_world.resolve_damage()
			qa["respawn-deadline"]=player.slot.respawn_at;qa_next=qa_elapsed+.2
		9:
			if not qa_require(kill_replay.active and not match_world.actors[0].alive,"recorded killer POV starts on death"):return
			var frame:Dictionary=kill_replay.frames[kill_replay.cursor].actors[kill_replay.killer]
			if not qa_require(camera.global_position.distance_to(Vector3(frame.position)+Vector3.UP*float(frame.eye))<1.2,"replay camera follows recorded killer position"):return
			send_key("jump")
			if not qa_require(not kill_replay.active and kill_replay.skipped,"Space skips replay"):return
			qa_next=qa_elapsed+.05
		10:
			if match_world.clock<float(qa["respawn-deadline"]):qa_next=qa_elapsed+.05;return
			if not qa_require(match_world.actors[0].alive and match_world.actors[0].slot.life_id==int(qa["replay-life"])+1,"three-second redeployment after skip"):return
			match_world.qa_protect_player=true
			match_world.mode.remaining=.02
		11:
			if not qa_require(match_world.mode.finished and screen=="killcam" and kill_replay.active,"final kill cam"):return
			send_key("jump")
			if not qa_require(screen=="results","results after skipping the kill cam"):return
			start_match()
		12:
			if match_world==null or not match_world.ready_for_play:return
			if not qa_require(match_world.slots.size()==MatchWorld.TEAM_SIZE*2 and not match_world.mode.finished,"rematch"):return
			return_to_menu()
		13:
			if not qa_require(screen=="main" and match_world==null,"return to menu"):return
			save_json(artifact_dir()+"/export-smoke.json",{"passed":true,"steps":["main_menu","setup","full_roster","mouse_look","quick_click_fire","right_mouse_toggle_ads","keyboard_aim_toggle","shift_sprint_binding","keyboard_fire_while_aimed","jump","reload","pause","resume","killer_replay","recorded_killer_camera","skip_replay","three_second_respawn","final_killcam","results","rematch","menu"]})
			print("EXPORT SMOKE PASS");safe_quit()
	print("SMOKE STEP ",qa_smoke_phase," PASS")
	qa_smoke_phase+=1

func qa_require(condition:bool, description:String) -> bool:
	if not condition:
		if match_world!=null:
			var actor:=match_world.actors[0];var runtime:=actor.weapon()
			print("SMOKE DIAGNOSTIC ",JSON.stringify({"phase":qa_smoke_phase,"screen":screen,"finished":match_world.mode.finished,"final_kill_frames":match_world.final_kill.get("frames",[]).size(),"kill_cam":kill_replay!=null and kill_replay.active,"qa_time":qa_elapsed,"match_clock":match_world.clock,"alive":actor.alive,"health":actor.health,"life":actor.slot.life_id,"weapon":runtime.definition.id,"state":runtime.state,"ammo":runtime.ammo,"capacity":runtime.capacity,"reload_at":runtime.reload_at,"last_shot_at":runtime.last_shot_at}))
		push_error("EXPORT SMOKE FAILED: "+description);get_tree().quit(1)
	return condition

func press_menu(prefix:String) -> void:
	for node in menu.find_children("*","Button",true,false):
		if node.text.begins_with(prefix):node.pressed.emit();return
	push_error("Missing menu action: "+prefix)
	safe_quit()

func send_key(action:String) -> void:
	var event:=InputEventKey.new();event.physical_keycode=int(profile.settings.bindings.get(action,BINDINGS[action]));event.pressed=true;Input.parse_input_event(event)
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event)

func safe_quit() -> void:
	if shutting_down:return
	shutting_down=true
	await get_tree().process_frame
	get_tree().paused=false
	await dispose_match()
	if backdrop!=null:backdrop.free();backdrop=null
	for child in menu.get_children():child.free()
	# Release the presentation rig and shared materials while the render server
	# is still alive, then let its queued shader frees finish before shutdown.
	world_texture.texture=null
	world_view.free();world_view=null;camera=null;hands=null
	ModelFactory.sources.clear()
	SoldierFactory.finishes.clear();SoldierFactory.graph=null;SoldierFactory.effects=null;SoldierFactory.ragdolls.clear()
	ViewModel.flash_texture=null
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name()!="headless":RenderingServer.force_draw(false)
	await get_tree().process_frame
	get_tree().quit()

func show_zombies_results() -> void:
	var result: Dictionary=match_world.mode.get_result()
	var previous: Dictionary=profile.zombies_records.get(selected_map,{})
	if int(result.round)>=int(previous.get("round",0)):profile.zombies_records[selected_map]=result.duplicate(true)
	profile.save();screen="results";clear_menu();hud.visible=false;hands.shown=false
	var box_ui:=column(Vector2(64,85),650)
	label(box_ui,"ZOMBIES / SURVIVAL ENDED",15,orange);label(box_ui,"ROUND %d"%int(result.round),65,blue)
	label(box_ui,"%d ROUNDS CLEARED"%int(result.completed),25)
	label(box_ui,"%d KILLS / %d HEADSHOTS\n%d POINTS EARNED / %.0f SECONDS"%[result.kills,result.headshots,result.points_earned,result.seconds],20)
	button(box_ui,"SURVIVE AGAIN",start_match);button(box_ui,"MAIN MENU",return_to_menu)

func zombies_qa_report(value: Dictionary) -> void:
	value["exported"]=not OS.has_feature("editor");value["mode"]="zombies";value["map"]=selected_map;value["seed"]=qa_seed
	var path:=artifact_dir()+"/%s-zombies-%s-%d.json"%[str(qa.qa),selected_map,qa_seed]
	save_json(path,value)

func zombies_qa_tick(delta: float) -> void:
	qa_elapsed+=delta
	if qa.qa=="smoke-export":zombies_smoke_tick();return
	if match_world==null or not match_world.ready_for_play:return
	var z:=match_world as ZombiesWorld
	if not qa.has("zombies_initialized"):
		print("ZOMBIES QA initialize ",qa.qa)
		qa["zombies_initialized"]=true
		z.qa_protect_player=true
		for station in z.stations:
			if station.kind=="door":station.open(z)
		z.mode.power=true
		for station in z.stations:station.enable_power(true)
		if qa.qa!="capture":z.give_weapon("z_thunder")
		if qa.qa in ["match-test","benchmark"]:
			z.mode.perks.assign(["heart","stride","hands","revive"]);(z.actors[0] as ZombiePlayer).apply_perks(z.mode.perks)
			z.actors[0].health=z.actors[0].max_health
			z.actors[0].global_position=Vector3(-6,0,6)
			qa["route_index"]=0
			var qa_runtime:=z.actors[0].weapon() as ZombieWeaponRuntime;qa_runtime.upgraded=true;qa_runtime.recompute(z.mode.perks);qa_runtime.refill()
		z.mode.intermission=0;z.mode.round_number=1;z.mode.remaining_to_spawn=ZombiesMode.budget(1)
		if qa.qa=="benchmark":z.mode.round_number=15;z.mode.remaining_to_spawn=100000
		qa_next=qa_elapsed+3
	var player:=z.actors[0]
	if qa.qa in ["benchmark","match-test"]:
		z.spawn_at=minf(z.spawn_at,z.clock)
		if qa.qa=="benchmark":
			var wonder_ids: Array[String]=["z_thunder","z_ray","z_arc"]
			var desired: String=wonder_ids[int(z.clock/12)%3]
			if str(player.weapon().definition.id)!=desired:
				z.give_weapon(desired)
				var changed:=player.weapon() as ZombieWeaponRuntime;changed.upgraded=true;changed.recompute(z.mode.perks);changed.refill()
			for enemy in z.actors:
				if enemy is ZombieActor and enemy.alive and enemy.slot.id%8==0 and enemy.become_crawler():z.sever_legs(enemy)
			for station in z.stations:
				if station.kind=="trap" and z.clock>=station.cooldown_until:station.active_until=z.clock+9;station.cooldown_until=z.clock+54
		var runtime:=player.weapon() as ZombieWeaponRuntime
		runtime.refill()
		var target: Combatant
		var best:=INF
		for i in range(1,z.actors.size()):
			var enemy:=z.actors[i]
			if not enemy.alive:continue
			var distance:=player.eye().distance_to(enemy.aim_target())
			if distance<best and z.visible_between(player.eye(),enemy.aim_target(),false):target=enemy;best=distance
		if target!=null:
			var offset: Vector3=target.aim_target()-player.eye()
			look=Vector2(atan2(-offset.x,-offset.z),asin(clampf(offset.normalized().y,-1,1)))
			z.player_command.aim_yaw=look.x;z.player_command.aim_pitch=look.y
			z.player_command.fire_pressed=true;z.player_command.fire_held=true
		# Moving within the opened yard exercises real player movement, not a frozen camera.
		var route: Array[Vector3]=[Vector3(-6,0,6),Vector3(6,0,6),Vector3(6,0,21),Vector3(-6,0,21)]
		var route_index: int=int(qa.get("route_index",0))
		if player.global_position.distance_to(route[route_index])<1.0:route_index=(route_index+1)%route.size();qa["route_index"]=route_index
		var travel:=route[route_index]-player.global_position;travel.y=0
		var local:=Basis(Vector3.UP,-look.x)*travel.normalized()
		z.player_command.movement=Vector2(local.x,local.z)
		if qa.qa=="match-test":
			if z.clock>=qa_next:
				qa_next=z.clock+10
				var detail: Array=[]
				for enemy in z.actors:
					if enemy is ZombieActor and enemy.alive:detail.append([enemy.slot.id,enemy.state,enemy.health,str(enemy.global_position)])
				print("ZOMBIES QA PROGRESS ",roundi(z.clock)," round=",z.mode.round_number," pending=",z.mode.remaining_to_spawn," hp=",player.health," living=",z.living_count())
				if z.living_count()<3:
					for enemy in z.actors:
						if enemy is ZombieActor and enemy.alive:
							var blocks: Array=[]
							for i in enemy.get_slide_collision_count():blocks.append(str(enemy.get_slide_collision(i).get_collider().get_path()))
							print("ZOMBIES LAST ",enemy.global_position," state=",enemy.state," portal=",enemy.portal_crossing," player=",player.global_position," blocks=",blocks)
			if z.mode.completed_rounds!=qa_step:qa_step=z.mode.completed_rounds;print("ZOMBIES QA ROUND ",qa_step," hp=",player.health," living=",z.living_count())
			if z.mode.completed_rounds>=20 or z.mode.finished:
				zombies_qa_report({"passed":z.mode.completed_rounds>=20,"completed_rounds":z.mode.completed_rounds,"clock":z.clock,"fixture":"protected QA human; full perk/upgraded wonder loadout and magazine/reserve replenished; lifecycle soak, not balance evidence"});safe_quit()
			return
		var now:=Time.get_ticks_usec()
		if benchmark_started_usec==0:benchmark_started_usec=now
		var elapsed:=(now-benchmark_started_usec)/1000000.0
		if elapsed<qa_warmup:return
		if previous_frame_usec>0:
			frame_times.append((now-previous_frame_usec)/1000.0)
			if DisplayServer.window_is_focused():focused_frames+=1
		previous_frame_usec=now
		if int(elapsed/30)>qa_step:qa_step=int(elapsed/30);print("ZOMBIES BENCHMARK ",int(elapsed),"s living=",z.living_count())
		if elapsed>=qa_warmup+qa_duration:
			var ordered:=frame_times.duplicate();ordered.sort()
			var total:=0.0
			for frame in ordered:total+=frame
			var average:=ordered.size()/maxf(total/1000,.001)
			var p95: float=ordered[mini(ordered.size()-1,ceili(ordered.size()*.95)-1)] if not ordered.is_empty() else INF
			var p99: float=ordered[mini(ordered.size()-1,ceili(ordered.size()*.99)-1)] if not ordered.is_empty() else INF
			var file:=FileAccess.open(artifact_dir()+"/benchmark-zombies-%s-%d.csv"%[selected_map,qa_seed],FileAccess.WRITE);file.store_line("interval_ms")
			for frame in frame_times:file.store_line(str(frame))
			file.close()
			zombies_qa_report({"passed":average>=60 and p95<=20 and p99<=33.3,"average_fps":average,"p95_ms":p95,"p99_ms":p99,"measured_seconds":total/1000,"warmup_seconds":qa_warmup,"sample_frames":frame_times.size(),"internal_resolution":[RenderScale.internal_size(world_view).x,RenderScale.internal_size(world_view).y],"pool_cap":24,"living":z.living_count(),"focused_fraction":focused_frames/maxf(1,frame_times.size()),"fixture":"protected QA human; replenished wonder ammunition; round 15 continuous spawning"});safe_quit()
		return
	if qa.qa=="capture" and qa_elapsed>=qa_next:
		var names:=["start","window","crawler","box","perk","wonder"]
		var folder:=artifact_dir()+"/screenshots/zombies/"+selected_map
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		if qa_capture_index>0:get_viewport().get_texture().get_image().save_png(folder+"/"+names[qa_capture_index-1]+".png")
		if qa_capture_index>=names.size():zombies_qa_report({"passed":true,"captures":names});safe_quit();return
		match qa_capture_index:
			0:player.global_position=Vector3(-28,0,16);look=Vector2(0,0)
			1:player.global_position=Vector3(-28,0,22);look=Vector2(PI,0)
			2:
				var enemy:=z.actors[1] as ZombieActor
				if enemy.barrier!=null:enemy.barrier.release(enemy.slot.id);enemy.barrier=null
				enemy.activate(Vector3(-26,0,14),z.clock,500,1,null);enemy.state="PURSUE";enemy.become_crawler()
				player.global_position=Vector3(-26,0,19);look=Vector2(0,-.25)
			3:player.global_position=z.box.position+Vector3(0,0,2);look=Vector2(0,0);z.mode.points=20000;z.box.roll()
			4:player.global_position=Vector3(-15,0,6);look=Vector2(0,0)
			5:z.give_weapon("z_arc");look=Vector2(0,0)
		z.player_command.aim_yaw=look.x;z.player_command.aim_pitch=look.y
		qa_capture_index+=1;qa_next=qa_elapsed+2
		return
	if qa.qa=="render-cleanup" and qa_elapsed>=qa_next:
		cleanup_counts.append(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		if cleanup_counts.size()<3:qa_next=qa_elapsed+3;qa_restarting=true;qa.erase("zombies_initialized");start_match();return
		var stable: bool=cleanup_counts.max()-cleanup_counts.min()<25
		zombies_qa_report({"passed":stable,"rounds":3,"node_counts":cleanup_counts});safe_quit();return

func zombie_smoke_pose(at: Vector3, yaw_value: float) -> void:
	match_world.actors[0].global_position=at;match_world.actors[0].velocity=Vector3.ZERO
	look=Vector2(yaw_value,0);match_world.player_command.aim_yaw=yaw_value;match_world.player_command.aim_pitch=0

func zombie_smoke_pad(pressed: bool) -> void:
	var event:=InputEventJoypadButton.new();event.button_index=JOY_BUTTON_X;event.pressed=pressed;Input.parse_input_event(event)

func zombies_smoke_tick() -> void:
	if qa_elapsed<qa_next:return
	qa_next=qa_elapsed+.2
	var z:=match_world as ZombiesWorld
	match qa_smoke_phase:
		0:
			if not qa_require(screen=="main","Zombies main menu"):return
			press_menu("ZOMBIES")
		1:
			if not qa_require(screen=="setup" and selected_mode=="zombies","Zombies mode selection"):return
			press_menu("START ZOMBIES")
		2:
			if z==null or not z.ready_for_play:return
			if not qa_require(z.actors.size()==25 and hud is ZombiesHUD and z.actors[0].weapons.size()==1,"Zombies roster HUD pistol start"):return
			qa["allow-input"]=true;z.qa_protect_player=true;z.mode.intermission=10000;blocked_fire=false
			qa["smoke_ammo"]=z.actors[0].weapon().ammo;send_key("fire_key")
		3:
			if not qa_require(z.actors[0].weapon().ammo==int(qa.smoke_ammo)-1,"Zombies keyboard firing"):return
			send_key("aim_toggle");qa_next=qa_elapsed+.4
		4:
			if not qa_require(z.actors[0].ads and hands.blend>.9,"Zombies toggle aim"):return
			send_key("aim_toggle");send_key("reload")
		5:
			if not qa_require(z.actors[0].weapon().state=="RELOADING","Zombies reload input"):return
			pause_menu();qa["smoke_pause_clock"]=z.clock
		6:
			if not qa_require(get_tree().paused and z.clock==float(qa.smoke_pause_clock) and z.interactions.progress==0,"Zombies pause freezes/cancels"):return
			resume_match();qa_next=qa_elapsed+1.8
		7:
			if not qa_require(z.clock>float(qa.smoke_pause_clock) and z.actors[0].weapon().ammo==8,"Zombies resume and reload complete"):return
			z.mode.points=20000;zombie_smoke_pose(Vector3(-12.7,0,13),-PI*.5)
		8:send_key("interact")
		9:
			if not qa_require(z.stations[0].opened,"Zombies E opens purchased door"):return
			var station: ZombieStation
			for object in z.stations:
				if object.kind=="wall" and object.item=="smg_mp9":station=object
			zombie_smoke_pose(station.position+Vector3(0,0,1.6),0)
		10:send_key("interact")
		11:
			if not qa_require(z.owns("smg_mp9") and z.actors[0].weapons.size()==2,"Zombies E buys wall weapon"):return
			z.barriers[0].boards=0;z.barriers[0].refresh();zombie_smoke_pose(z.barriers[0].inside,PI)
		12:zombie_smoke_pad(true);qa_next=qa_elapsed+1.15
		13:
			zombie_smoke_pad(false)
			if not qa_require(z.barriers[0].boards>=1 and z.actors[0].weapon().state!="RELOADING","Zombies controller hold repairs without reload"):return
			send_key("frag");qa_next=qa_elapsed+.9
		14:
			if not qa_require(z.actors[0].frags==1,"Zombies grenade input"):return
			var enemy:=z.actors[1] as ZombieActor;enemy.activate(Vector3(-25,0,21),z.clock,500,1,null);enemy.state="PURSUE"
			z.blast(Vector3(-28,0,21),6,350,0,&"frag");z.resolve_damage()
			z.mode.round_number=1;z.mode.intermission=0;z.mode.remaining_to_spawn=0
		15:
			if not qa_require(z.actors[1].alive and z.actors[1].crawling and z.mode.intermission==0,"Zombies grenade crawler holds round"):return
			z.queue_damage(0,z.actors[1],1000,&"frag",false);z.resolve_damage()
		16:
			if not qa_require(z.mode.completed_rounds==1,"Zombies crawler death advances round"):return
			z.mode.intermission=10000
			var station: ZombieStation
			for object in z.stations:
				if object.kind=="power":station=object
			zombie_smoke_pose(station.position+Vector3(0,0,1.6),0)
		17:send_key("interact")
		18:
			if not qa_require(z.mode.power,"Zombies power switch"):return
			var station: ZombieStation
			for object in z.stations:
				if object.kind=="perk" and object.item=="heart":station=object
			zombie_smoke_pose(station.position+Vector3(0,0,1.6),0)
		19:send_key("interact")
		20:
			if not qa_require(z.actors[0].max_health==200,"Zombies health perk purchase"):return
			var station: ZombieStation
			for object in z.stations:
				if object.kind=="perk" and object.item=="revive":station=object
			zombie_smoke_pose(station.position+Vector3(0,0,1.6),0)
		21:send_key("interact")
		22:
			if not qa_require("revive" in z.mode.perks,"Zombies self-revive purchase"):return
			z.qa_protect_player=false;z.actors[0].protected_until=0;z.queue_damage(1,z.actors[0],1000,&"zombie",false);z.resolve_damage()
		23:
			if not qa_require(z.actors[0].alive and z.downed_until>z.clock and z.mode.perks.is_empty(),"Zombies down consumes perks"):return
			qa_next=qa_elapsed+3.1
		24:
			if not qa_require(z.actors[0].health==100 and z.actors[0].max_health==100,"Zombies revive restores unperked health"):return
			z.revive_protection_until=0;z.actors[0].protected_until=0;z.queue_damage(1,z.actors[0],1000,&"zombie",false);z.resolve_damage()
		25:
			if not qa_require(screen=="results" and z.mode.finished and not z.actors[0].alive,"Zombies game over without TDM respawn"):return
			press_menu("SURVIVE AGAIN")
		26:
			if z==null or not z.ready_for_play:return
			if not qa_require(z.actors.size()==25 and z.mode.points==500 and not z.mode.power and z.mode.perks.is_empty() and not z.stations[0].opened and z.barriers[0].boards==6,"Zombies rematch resets progression"):return
			return_to_menu()
		27:
			if not qa_require(screen=="main" and match_world==null,"Zombies return to menu"):return
			zombies_qa_report({"passed":true,"steps":["main_menu","mode_selection","map_selection","pistol_start","25_slots","zombies_hud","keyboard_fire","toggle_aim","reload","pause_freezes","resume","door_purchase","wall_weapon_purchase","two_gun_inventory","controller_hold_repair","controller_reload_arbitration","grenade_throw","grenade_crawler","crawler_holds_round","round_clear","power_switch","health_perk","self_revive_purchase","down_perk_loss","revive","game_over","rematch_resets","return_to_menu"]})
			print("ZOMBIES EXPORT SMOKE PASS");safe_quit();return
	print("ZOMBIES SMOKE STEP ",qa_smoke_phase," PASS")
	qa_smoke_phase+=1

func campaign_menu() -> void:
	selected_mode="campaign";selected_map="blackout"
	screen="setup";clear_menu()
	var path:=profile.directory.path_join("campaign.json")
	campaign_checkpoint=0
	if FileAccess.file_exists(path):
		var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and data.get("version")==1 and data.get("stage") is float:
			campaign_checkpoint=clampi(int(data.stage),0,3)
	var box:=column(Vector2(64,65),840)
	label(box,"CAMPAIGN / MISSION 01",15,orange)
	label(box,"DEAD CIRCUIT",48,blue)
	label(box,"Blackout Station has gone dark. Recover the control records\nand reach the seawall with Rook and Atlas.",21)
	label(box,"Clear each encounter, then remain at the blue objective marker\nfor three seconds. Checkpoints save after each objective.\nDeath ends the attempt. Continue restores the current encounter\nwith fresh loadout ammunition. Your armory loadout is used.",18)
	label(box,"OPPOSITION",14,blue)
	var level:=OptionButton.new()
	for title in ["EASY","NORMAL","HARD"]:level.add_item(title)
	level.select(difficulty);box.add_child(level);level.item_selected.connect(func(index:int):difficulty=index)
	button(box,"BEGIN MISSION",func():campaign_resume=false;save_campaign_checkpoint(0);start_match())
	if campaign_checkpoint>0:button(box,"CONTINUE / CHECKPOINT %d"%(campaign_checkpoint+1),func():campaign_resume=true;start_match())
	button(box,"BACK",main_menu)

func save_campaign_checkpoint(stage:int) -> void:
	campaign_checkpoint=stage
	var path:=profile.directory.path_join("campaign.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(profile.directory))
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:push_error("Unable to save campaign checkpoint");return
	file.store_string(JSON.stringify({"version":1,"stage":stage}));file.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK:push_error("Unable to commit campaign checkpoint")

func show_campaign_results() -> void:
	if match_world is CampaignWorld and match_world.dialogue!=null:match_world.dialogue.stop()
	get_tree().paused=true;screen="results";clear_menu();hands.shown=false
	var won:bool=match_world.mode.success
	var box:=column(Vector2(64,100),850)
	label(box,"DEAD CIRCUIT",18,orange)
	label(box,"MISSION COMPLETE" if won else "MISSION FAILED",44,blue)
	label(box,"CONTROL: Records received. Your squad is clear. End of mission." if won else "Your squad lost contact. Restart from the latest checkpoint.",20)
	if won:
		save_campaign_checkpoint(0)
		button(box,"REPLAY MISSION",func():campaign_resume=false;start_match())
	else:button(box,"RETRY CHECKPOINT",func():campaign_resume=true;start_match())
	button(box,"MAIN MENU",return_to_menu)

# Rendered/exported playback probe: ordinary campaign audio and subtitles, with
# static combat so this checks presentation rather than player difficulty.
func campaign_voice_smoke() -> void:
	var mission:=match_world as CampaignWorld
	if mission==null:return
	var dialogue:=mission.dialogue
	if dialogue==null:return
	if not qa.has("voice-events"):
		qa["voice-events"]=[]
		mission.actors[0].bot=null
		dialogue.cue_started.connect(func(id:String):
			qa["voice-events"].append({"id":id,"subtitle":dialogue.subtitle,"spatial":dialogue.spatial.playing,"radio":dialogue.radio.playing})
			save_json(artifact_dir()+"/campaign-voices-progress.json",{"events":qa["voice-events"]}))
	if mission.countdown<=0:
		mission.set_physics_process(false)
		dialogue.start_intro()
	if dialogue.current_index==5 and not qa.has("voice-relay-capture"):
		qa["voice-relay-capture"]=true
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var folder:=artifact_dir()+"/screenshots/campaign"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		get_viewport().get_texture().get_image().save_png(folder+"/approved-relay-voice.png")
	if dialogue.intro_started and not dialogue.active and qa["voice-events"].size()==10:
		if qa.has("voice-done"):return
		qa["voice-done"]=true
		await get_tree().process_frame
		var events:Array=qa["voice-events"]
		var valid:=dialogue.subtitle.is_empty() and not dialogue.spatial.playing and not dialogue.radio.playing
		valid=valid and events[5].id=="06_atlas" and dialogue.cues[5].take==2 and not hud.campaign_caption.visible
		for event in events:
			valid=valid and not str(event.subtitle).is_empty() and (event.spatial!=event.radio)
		save_json(artifact_dir()+"/campaign-voices-smoke.json",{"passed":valid,"events":events,"relay_take":dialogue.cues[5].take,"finished_cleanly":not dialogue.active,"exported":not OS.has_feature("editor"),"fixture":"Static combat simulation; ordinary real-time voice playback and subtitle HUD."})
		if valid:print("CAMPAIGN VOICES SMOKE PASS")
		else:push_error("Campaign voice playback smoke failed")
		safe_quit()
