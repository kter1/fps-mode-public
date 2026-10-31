extends Control

var world: MatchWorld
var actor: Combatant
var input_state: RefCounted
var replay: KillReplay
var seat := 0
var font := ThemeDB.fallback_font
const BLUE := Color("72c8e8")

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func line_text(value: String, at: Vector2, color := Color.WHITE, font_size := 15) -> void:
	draw_string_outline(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,3,Color(.015,.025,.04,.95))
	draw_string(font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _draw() -> void:
	if not is_instance_valid(actor) or not world.ready_for_play:return
	var width:=size.x;var height:=size.y
	draw_rect(Rect2(Vector2.ZERO,size),Color("72c8e8"),false,1)
	var device:String="CONNECT CONTROLLER" if input_state.device==-2 else "CONTROLLER %d"%(input_state.device+1)
	if input_state.device==-1:device="KEYBOARD + MOUSE"+(" + CONTROLLER %d"%(input_state.spare_pad+1) if input_state.spare_pad>=0 else "")
	line_text("P%d / %s  %s"%[seat+1,"BLUE" if actor.slot.team==0 else "RED",device],Vector2(12,20),BLUE if actor.slot.team==0 else Color("e6ab65"),13)
	var remaining:=ceili(world.mode.remaining)
	line_text("BLUE %d   /   RED %d     %d:%02d"%[world.mode.scores[0],world.mode.scores[1],remaining/60,remaining%60],Vector2(12,39),Color.WHITE,13)
	line_text("HP %d    K %d / D %d"%[ceili(actor.health),actor.slot.kills,actor.slot.deaths],Vector2(12,height-28),BLUE)
	var weapon:=actor.weapon()
	line_text("%s    %d / %d"%[weapon.definition.display_name,weapon.ammo,weapon.reserve],Vector2(12,height-9),Color.WHITE,13)
	var center:=size*.5
	if not actor.alive and replay!=null and replay.active:
		var killer:ActorSlot=world.slots[replay.killer]
		line_text("KILL CAM  /  %s"%killer.callsign,Vector2(width*.5-80,62),BLUE if killer.team==0 else Color("e6ab65"),16)
		line_text("REDEPLOYING IN %.1f    %s  SKIP"%[maxf(0,actor.slot.respawn_at-world.clock),"SPACE" if input_state.device==-1 else "X"],Vector2(width*.5-120,height-52),Color.WHITE,13)
	elif not actor.alive:
		line_text("REDEPLOYING IN %.1f"%maxf(0,actor.slot.respawn_at-world.clock),center+Vector2(-85,0),BLUE,18)
	elif world.countdown>0:
		line_text("DEPLOYING  %d"%ceili(world.countdown),center+Vector2(-65,0),BLUE,20)
	elif input_state.device==-2:
		line_text("Connect a controller to join this seat",center+Vector2(-120,0),BLUE,15)
	else:
		for side in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:draw_line(center+side*5,center+side*10,Color.WHITE,1)
		if actor.prone:line_text("PRONE",Vector2(width-70,height-28),BLUE,13)
		elif actor.crouched:line_text("CROUCHED",Vector2(width-95,height-28),BLUE,13)
		elif actor.sprinting:line_text("SPRINTING",Vector2(width-100,height-28),BLUE,13)
		if weapon.state=="RELOADING":line_text("RELOADING",center+Vector2(-40,32),BLUE,13)
		var candidate:=world.swap_candidate(actor)
		if not candidate.is_empty():line_text("%s  PICK UP"%("E" if input_state.device==-1 else "HOLD SQUARE"),center+Vector2(-70,55),BLUE,13)
	if input_state.down("scoreboard"):
		draw_rect(Rect2(8,52,width-16,height-110),Color(.02,.04,.06,.92))
		for i in world.local_player_count:
			var slot:=world.slots[i]
			line_text("%s     %d K / %d D"%[slot.callsign,slot.kills,slot.deaths],Vector2(20,80+i*22),BLUE,15)
