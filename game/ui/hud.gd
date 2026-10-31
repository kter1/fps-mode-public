class_name GameHUD
extends Control

var campaign_caption:PanelContainer
var campaign_caption_text:Label
var world: MatchWorld
var camera: Camera3D
var font := ThemeDB.fallback_font
var hit_flash := 0.0
var kill_flash := 0.0
var damage_flash := 0.0
var damage_angle := 0.0
var feed: Array[Dictionary] = []
var minimap: Minimap
var show_scoreboard := false
var replaying:=false
var replay_killer:=""
var replay_actor:Combatant
# End-of-match kill cam: whose kill it is.
var final_kill:=false
var replay_victim:=""
var replay_team:=0
# Rounds just taken from a dropped weapon, shown briefly.
var ammo_note:=0
var ammo_note_left:=0.0
var vignette: ColorRect
var vignette_material: ShaderMaterial
var wound:=0.0
var blue := Color("70c9ed")
var red := Color("f39475")
var white := Color("edf2f6")

# True while the player is using a gamepad (hints show controller buttons).
var pad := false

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Drawn behind the HUD's own panels and text.
	vignette=ColorRect.new();vignette.name="DamageVignette";vignette.mouse_filter=Control.MOUSE_FILTER_IGNORE;vignette.show_behind_parent=true
	vignette_material=ShaderMaterial.new();vignette_material.shader=load("res://content/ui/damage_vignette.gdshader");vignette.material=vignette_material
	add_child(vignette);vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);vignette.visible=false

func connect_world(source: MatchWorld, view: Camera3D) -> void:
	world=source;camera=view
	if world.mode_id=="campaign":
		campaign_caption=PanelContainer.new();campaign_caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
		campaign_caption.add_theme_stylebox_override("panel",style(Color(.015,.025,.04,.9)))
		add_child(campaign_caption)
		campaign_caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		campaign_caption.offset_left=-390;campaign_caption.offset_right=390
		campaign_caption.offset_top=-205;campaign_caption.offset_bottom=-112
		campaign_caption_text=Label.new();campaign_caption_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		campaign_caption_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		campaign_caption_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		campaign_caption_text.add_theme_font_size_override("font_size",19)
		campaign_caption.add_child(campaign_caption_text);campaign_caption.hide()
	minimap=Minimap.new();add_child(minimap);minimap.bind(source)
	world.elimination.connect(func(message: String,team: int):
		feed.push_front({"text":message,"team":team,"remaining":5.0})
		if feed.size()>5:feed.pop_back())
	world.player_hit.connect(func(_head: bool,killed: bool):
		hit_flash=.18
		if killed:kill_flash=.65)
	world.ammo_scavenged.connect(func(rounds: int):ammo_note=rounds;ammo_note_left=1.6)
	world.player_damaged.connect(func(position: Vector3):
		damage_flash=.6
		var offset:=position-world.actors[0].global_position
		damage_angle=atan2(offset.x,-offset.z)+world.actors[0].yaw)

func _process(delta: float) -> void:
	if campaign_caption!=null:
		var dialogue:CampaignDialogue=world.dialogue
		campaign_caption_text.text=dialogue.subtitle if dialogue!=null else ""
		campaign_caption.visible=not campaign_caption_text.text.is_empty()
	hit_flash=maxf(0,hit_flash-delta);kill_flash=maxf(0,kill_flash-delta);damage_flash=maxf(0,damage_flash-delta);ammo_note_left=maxf(0,ammo_note_left-delta)
	update_vignette(delta)
	if minimap!=null:minimap.replaying=replaying
	for entry in feed:entry.remaining-=delta
	feed=feed.filter(func(entry: Dictionary):return entry.remaining>0)
	queue_redraw()

# Red at the screen edges: steady and closing in as health falls (pulsing when critical),
# plus a pulse on every hit. Health regenerates after six seconds, and the red fades with it.
func update_vignette(delta: float) -> void:
	if world==null or world.actors.is_empty():return
	var player:=world.actors[0]
	var missing:=clampf(1.0-player.health/player.max_health,0,1) if player.alive and not replaying else 0.0
	var target:=clampf((missing-.08)/.75,0,1)
	if player.alive and player.health<35:target=minf(1.0,target+.08*(1+sin(Time.get_ticks_msec()*.006)))
	wound=move_toward(wound,target,delta*(3.0 if target>wound else .9))
	var pulse:=clampf(damage_flash/.6,0,1) if not replaying else 0.0
	vignette.visible=wound>.002 or pulse>.002
	if vignette.visible:
		vignette_material.set_shader_parameter("wound",wound);vignette_material.set_shader_parameter("flash",pulse*pulse)

func text(value: String, position: Vector2, size_px := 20, color := Color("edf2f6")) -> void:
	draw_string(font,position,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_px,color)

func panel(rect: Rect2) -> void:
	draw_style_box(style(Color(.025,.045,.065,.85)),rect)

func style(color: Color) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.set_corner_radius_all(5);return box

func _draw() -> void:
	if world==null or world.actors.is_empty():return
	var player := world.actors[0]
	var width := size.x
	var height := size.y
	var center := size*.5
	var viewpoint:=replay_actor if replaying and is_instance_valid(replay_actor) else player
	var runtime:=viewpoint.weapon()
	if world.mode_id=="campaign":
		panel(Rect2(265,18,width-530,122))
		var mission:CampaignMode=world.mode
		text("DEAD CIRCUIT / %d OF 4"%(mission.stage+1),Vector2(280,40),14,blue)
		text(CampaignMode.TITLES[mission.stage],Vector2(280,66),20)
		text("%dm / %d HOSTILES / HOLD %.1f / 3s"%[world.actors[0].global_position.distance_to(CampaignMode.TARGETS[mission.stage]),mission.enemies_left(),mission.hold],Vector2(280,91),14)
		text(CampaignMode.RADIO[mission.stage],Vector2(280,116),12)
		var marker:Vector3=CampaignMode.TARGETS[mission.stage]+Vector3.UP
		if not camera.is_position_behind(marker):
			var point:=camera.unproject_position(marker)*size/Vector2(camera.get_viewport().get_visible_rect().size)
			draw_circle(point,7,blue)
	else:
		panel(Rect2(width*.5-195,18,390,66))
		draw_rect(Rect2(width*.5-195,18,190,3),blue)
		draw_rect(Rect2(width*.5+5,18,190,3),red)
		text("BLUE",Vector2(width*.5-176,48),15,blue)
		text(str(world.mode.scores[0]),Vector2(width*.5-111,65),34)
		text("RED",Vector2(width*.5+136,48),15,red)
		text(str(world.mode.scores[1]),Vector2(width*.5+74,65),34)
		var remaining := ceili(world.mode.remaining)
		text("%02d:%02d"%[remaining/60,remaining%60],Vector2(width*.5-30,50),20)
		text("%d / TDM"%world.mode.kill_limit,Vector2(width*.5-29,71),11,Color("9daebb"))
	var heading := posmod(roundi(rad_to_deg(-viewpoint.yaw)),360)
	if world.mode_id!="campaign":text("%03d°   %s"%[heading,["N","E","S","W"][int((heading+45)%360/90)]],Vector2(center.x-39,106),14,Color("c3d1db"))
	var critical:=player.alive and player.health<35
	# The final kill cam shows the killer's weapon, not the player's own status and controls.
	if not final_kill:
		panel(Rect2(28,height-100,245,72))
		text("+",Vector2(44,height-50),32,red if critical else blue)
		text(str(maxi(0,ceili(player.health))),Vector2(76,height-50),32,red if critical else white)
		text("VANGUARD // "+player.slot.callsign,Vector2(46,height-78),11,Color("a5b5c1"))
		draw_rect(Rect2(46,height-39,205,4),Color("33414b"))
		draw_rect(Rect2(46,height-39,205*maxf(0,player.health)/100,4),red if critical else blue)
	panel(Rect2(width-307,height-100,279,72))
	text(runtime.definition.display_name.to_upper(),Vector2(width-290,height-78),12,Color("bacbd6"))
	text("%02d"%runtime.ammo,Vector2(width-290,height-42),36)
	text("/ %03d"%runtime.reserve,Vector2(width-229,height-45),19,Color("a7bac7"))
	text("G  %d    Q  %d"%[player.frags,player.smokes],Vector2(width-128,height-44),15)
	text("1 / 2  SWITCH",Vector2(width-128,height-70),10,Color("9baebb"))
	# The radar takes the top-left corner; the key hints sit unobtrusively under it.
	var hint_top:=Minimap.MARGIN.y+minimap.diameter()+8.0
	var menu_hint:="TOUCHPAD  SCOREBOARD     OPTIONS  PAUSE" if pad else "TAB  SCOREBOARD     ESC  PAUSE"
	if not final_kill:
		panel(Rect2(Minimap.MARGIN.x,hint_top,font.get_string_size(menu_hint,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x+24,22))
		text(menu_hint,Vector2(Minimap.MARGIN.x+12,hint_top+15),10,Color("9baebb"))
		panel(Rect2(20,height-136,180,28))
		text("PRONE" if player.prone else ("SPRINTING" if player.sprinting else ("L3  SPRINT" if pad else "SHIFT + W  SPRINT")),Vector2(30,height-115),13,blue if player.sprinting else Color("bacbd6"))
		var keys:="L2  AIM     R2  FIRE     R1  FRAG     △  SWITCH     R3  KNIFE     HOLD ○  PRONE" if pad else "C / TWO-FINGER CLICK  AIM     F / CLICK  FIRE     V  KNIFE     Z  PRONE"
		var keys_wide:=font.get_string_size(keys,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
		panel(Rect2(center.x-keys_wide*.5-18,height-48,keys_wide+36,25))
		text(keys,Vector2(center.x-keys_wide*.5,height-31),11,Color("bacbd6"))
	for i in feed.size():
		var entry := feed[i]
		text(entry.text,Vector2(width-310,125+i*24),13,blue if entry.team==0 else red)
	if viewpoint.alive and world.countdown<=0:
		if not viewpoint.ads:
			var gap := 5.0+player.velocity.length()*.8
			for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:draw_line(center+direction*gap,center+direction*(gap+6),white,1.3,true)
		elif runtime.magnification>=3:
			# Red-dot and holographic reticles are lens surfaces on the optic models;
			# only magnified scopes, which hide the rig, draw an eyepiece here.
			var aimed:float=ViewModel.active.blend if ViewModel.active!=null else 1.0
			scope_overlay(center,clampf((aimed-.72)/.18,0,1),runtime.magnification)
	if hit_flash>0 and not replaying:
		for direction in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:draw_line(center+direction*7,center+direction*12,red if kill_flash>0 else white,2,true)
	if kill_flash>0:text("ELIMINATION  +1",center+Vector2(-63,43),14,blue)
	if damage_flash>0 and not replaying:
		# Where the shot came from: a red wedge on a ring round the crosshair.
		var bearing:=damage_angle-PI*.5;var fade:=clampf(damage_flash/.6,0,1)
		draw_arc(center,118,bearing-.34,bearing+.34,24,Color(1,.16,.1,.85*fade),9,true)
		draw_arc(center,108,bearing-.2,bearing+.2,16,Color(1,.35,.25,.6*fade),4,true)
	if world.countdown>0:
		panel(Rect2(center-Vector2(170,70),Vector2(340,140)))
		text("TEAM DEATHMATCH",center+Vector2(-117,-32),21)
		text(str(ceili(world.countdown)),center+Vector2(-14,25),56,blue)
		text("%d V %d  //  PREPARE TO DEPLOY"%[MatchWorld.TEAM_SIZE,MatchWorld.TEAM_SIZE],center+Vector2(-113,53),12,Color("9fb4c3"))
	if final_kill:
		panel(Rect2(center.x-260,121,520,62))
		draw_rect(Rect2(center.x-260,121,520,3),blue if replay_team==0 else red)
		text("FINAL KILL",Vector2(center.x-44,148),19,blue if replay_team==0 else red)
		var line:=replay_killer+"  ›  "+replay_victim
		text(line,Vector2(center.x-font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,15).x*.5,170),15)
		text("✕ / SPACE  SKIP" if pad else "SPACE / F  SKIP",Vector2(width-200,height-120),12,Color("afc1cd"))
	elif replaying:
		panel(Rect2(center.x-240,121,480,54))
		text("ELIMINATED BY "+replay_killer+"  /  KILL REPLAY",Vector2(center.x-218,145),17,red)
		text("SPACE / F  SKIP     RESPAWN IN %.1f"%maxf(0,player.slot.respawn_at-world.clock),Vector2(center.x-158,165),13)
	elif not player.alive:
		panel(Rect2(center-Vector2(215,60),Vector2(430,120)))
		text("REDEPLOYING",center+Vector2(-86,-16),23,red)
		text("%0.1f SECONDS"%maxf(0,player.slot.respawn_at-world.clock),center+Vector2(-63,18),20)
		text("ESC  CHANGE LOADOUT",center+Vector2(-77,43),13,Color("afc1cd"))
	elif runtime.state=="RELOADING":text("RELOADING",center+Vector2(-44,70),14,blue)
	if player.alive and not replaying and world.countdown<=0:
		var dropped:=world.swap_candidate(player)
		if not dropped.is_empty():
			var name:String=world.catalog.weapons[str(dropped.weapon)].display_name.to_upper()
			var prompt:=("HOLD □  PICK UP  " if pad else "E  PICK UP  ")+name
			var wide:=font.get_string_size(prompt,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x
			panel(Rect2(center.x-wide*.5-14,center.y+92,wide+28,28));text(prompt,Vector2(center.x-wide*.5,center.y+111),14)
		if ammo_note_left>0:text("+%d AMMO"%ammo_note,Vector2(width-290,height-108),14,Color(blue,clampf(ammo_note_left/.4,0,1)))
	if player.alive and world.clock<player.protected_until:
		panel(Rect2(20,height-170,180,26));text("SPAWN PROTECTION",Vector2(30,height-152),11,blue)
	if camera!=null and not replaying:
		for ally in world.actors:
			if ally==player or not ally.alive or ally.slot.team!=0:continue
			var point:=ally.global_position+Vector3.UP*2.1
			if camera.to_local(point).z>=-camera.near:continue
			var screen:=camera.unproject_position(point)
			# World render dimensions are independent of the presentation dimensions.
			screen*=size/Vector2(camera.get_viewport().size)
			if screen.x<15 or screen.x>width-15 or screen.y<110 or screen.y>height-120:continue
			draw_circle(screen,2.8,blue)
	if show_scoreboard:scoreboard()

func scoreboard() -> void:
	var rect:=Rect2(size*.5-Vector2(420,260),Vector2(840,520))
	panel(rect)
	text("MATCH SCOREBOARD",rect.position+Vector2(24,36),25)
	for team in 2:
		var x:=rect.position.x+24+team*420
		text("BLUE / VANGUARD" if team==0 else "RED / SENTINEL",Vector2(x,rect.position.y+75),16,blue if team==0 else red)
		text("K      D",Vector2(x+280,rect.position.y+75),14)
		for row in MatchWorld.TEAM_SIZE:
			var slot:=world.slots[team*MatchWorld.TEAM_SIZE+row]
			var y:=rect.position.y+108+row*29
			if slot.id==0:draw_rect(Rect2(x-8,y-20,385,27),Color(.2,.4,.55,.28))
			text(slot.callsign,Vector2(x,y),15)
			text("%02d     %02d"%[slot.kills,slot.deaths],Vector2(x+280,y),15)

# Eyepiece for 3x/6x scopes: tube shadow outside the lens, soft edge falloff, a
# duplex reticle (mil dots at 6x) and a faint illuminated centre.
func scope_overlay(center:Vector2,alpha:float,magnification:float) -> void:
	if alpha<=0:return
	var radius:=minf(size.x,size.y)*.46
	var outer:=size.length()
	draw_arc(center,(radius+outer)*.5,0,TAU,160,Color(0,0,0,alpha),outer-radius+2)
	for i in 7:draw_arc(center,radius-i*5-2.5,0,TAU,160,Color(0,0,0,alpha*(.55-i*.075)),5)
	draw_circle(center,radius,Color(.35,.5,.6,.035*alpha))
	var ink:=Color(0,0,0,.9*alpha)
	var inner:=radius*.3
	for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.DOWN,Vector2.UP]:
		draw_line(center+direction*inner,center+direction*radius,ink,4.5)
		draw_line(center+direction*2.5,center+direction*inner,ink,1.1,true)
		if magnification>=5:
			for i in range(1,5):draw_circle(center+direction*inner*i/5.0,1.7,ink)
	draw_circle(center,1.5,Color(.95,.2,.12,.85*alpha))
