class_name ZombiesHUD
extends GameHUD

func connect_world(source: MatchWorld, view: Camera3D) -> void:
	world=source;camera=view
	world.player_hit.connect(func(_head:bool,killed:bool):hit_flash=.18;kill_flash=.6 if killed else 0.0)
	world.player_damaged.connect(func(at:Vector3):damage_flash=.6;var offset:=at-world.actors[0].global_position;damage_angle=atan2(offset.x,-offset.z)+world.actors[0].yaw)

func _draw() -> void:
	if world==null or world.actors.is_empty():return
	var z:=world as ZombiesWorld;var player:=world.actors[0];var runtime:=player.weapon() as ZombieWeaponRuntime
	var center:=size*.5;var width:=size.x;var height:=size.y
	panel(Rect2(24,24,265,116));text("ROUND",Vector2(43,53),15,Color("d7a571"));text(str(z.mode.round_number),Vector2(42,110),56,Color("d5b086"))
	text("%d  POINTS"%z.mode.points,Vector2(124,76),23,white)
	text("%d LEFT"%[z.living_count()+z.mode.remaining_to_spawn],Vector2(126,110),15,Color("a4b6ab"))
	panel(Rect2(width-252,height-111,228,86));text(runtime.definition.display_name.to_upper(),Vector2(width-238,height-88),14,Color("d5b086"))
	text("%d / %d"%[runtime.ammo,runtime.reserve],Vector2(width-238,height-49),32)
	text("FRAGS %d   %s"%[player.frags,"OVERCHARGED" if runtime.upgraded else ""],Vector2(width-238,height-30),12,Color("a8b8b0"))
	panel(Rect2(24,height-102,225,77));text("HEALTH %d / %d"%[maxi(0,ceili(player.health)),int(player.max_health)],Vector2(40,height-72),20)
	draw_rect(Rect2(40,height-54,188,6),Color("283a32"));draw_rect(Rect2(40,height-54,188*clampf(player.health/player.max_health,0,1),6),Color("cb7663"))
	text("POWER "+("ONLINE" if z.mode.power else "OFFLINE"),Vector2(40,height-34),12,Color("afd1af"))
	for i in z.mode.perks.size():
		var perk: String=z.mode.perks[i];var info: Dictionary=ZombiesCatalog.PERKS[perk];var x: float=28+i*128
		panel(Rect2(x,height-145,122,30));draw_circle(Vector2(x+13,height-130),6,Color(str(info.color)));text(str(info.name),Vector2(x+24,height-126),11)
	var hint:="HOLD □ INTERACT / TAP RELOAD" if pad else "E INTERACT / HOLD REPAIR   R RELOAD   G FRAG   V KNIFE"
	text(hint,Vector2(center.x-font.get_string_size(hint,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x*.5,height-14),12,Color("a8b8b0"))
	if not z.interactions.prompt.is_empty() and player.alive:
		var line: String=z.interactions.prompt;var wide:=minf(width-40,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+32)
		panel(Rect2(center.x-wide*.5,center.y+80,wide,54));text(line,Vector2(center.x-wide*.5+16,center.y+103),16)
		if z.interactions.progress>0:draw_rect(Rect2(center.x-wide*.5+16,center.y+117,(wide-32)*z.interactions.progress,4),Color("c6ce8c"))
	if z.clock<z.mode.notice_until:
		var line: String=z.mode.notice;var length:=font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,23).x
		text(line,Vector2(center.x-length*.5,84),23,Color("e4d3aa"))
	var y:=175
	for item in [["DOUBLE POINTS",z.mode.double_until],["INSTA-KILL",z.mode.insta_until]]:
		if z.clock<float(item[1]):text("%s  %ds"%[item[0],ceili(float(item[1])-z.clock)],Vector2(28,y),15,Color("e8d08a"));y+=24
	if z.mode.intermission>0:text("NEXT ROUND IN %d"%ceili(z.mode.intermission),Vector2(28,166),14,Color("b9c5b3"))
	if z.clock<z.downed_until:text("SECOND WIND  %.1f"%(z.downed_until-z.clock),center-Vector2(110,10),26,Color("75b5c7"))
	if runtime.state=="RELOADING":text("RELOADING",center+Vector2(-48,60),14,Color("c8c8a3"))
	if player.alive and z.clock>=z.downed_until:
		for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:draw_line(center+direction*5,center+direction*10,Color("e3e1cc"),1.5,true)
	if hit_flash>0:
		for direction in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:draw_line(center+direction*7,center+direction*12,Color("ce7663") if kill_flash>0 else white,2,true)
	if show_scoreboard:
		panel(Rect2(center-Vector2(220,120),Vector2(440,240)));text("SURVIVAL RECORD",center-Vector2(185,78),24,Color("d5b086"))
		text("ROUND %d  /  %d CLEARED"%[z.mode.round_number,z.mode.completed_rounds],center-Vector2(185,28),19)
		text("%d KILLS   %d HEADSHOTS"%[z.mode.kills,z.mode.headshots],center+Vector2(-185,10),19)
		text("%d POINTS EARNED"%z.mode.earned,center+Vector2(-185,48),19)
