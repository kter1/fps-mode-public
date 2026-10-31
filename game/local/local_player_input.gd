extends RefCounted

# Each seat keeps its own event state. Input.get_vector/is_action_pressed merge
# all gamepads, so they must never be used for split-screen gameplay.
var device := -1 # -1 keyboard/mouse, -2 waiting for a controller.
# The keyboard seat can also take a controller no other seat owns.
var spare_pad := -3
# Set once this seat's controller sends anything. macOS can list a controller twice
# while it connects; a seat bound to the ghost never hears from it and can be reclaimed.
var heard := false
var look := Vector2.ZERO
var held: Dictionary = {}
var pressed: Dictionary = {}
var aim_toggle := false
var sprint_toggle := false
var crouch := false
var prone := false
var circle_time := 0.0
var circle_used := false
var pickup_time := -1.0
var pickup_used := false
var move_stick := Vector2.ZERO
var look_stick := Vector2.ZERO
var settings: Dictionary
const ACTIONS := ["forward","back","left","right","fire","fire_key","pad_fire","aim","aim_toggle","pad_aim","sprint","pad_sprint","crouch","pad_crouch","prone","jump","reload","primary","secondary","pad_switch","frag","smoke","melee","interact","scoreboard"]

func accepts(event: InputEvent) -> bool:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:return (device>=0 and event.device==device) or (device==-1 and event.device==spare_pad)
	return device==-1 and (event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion)

func handle(event: InputEvent, pickup_possible := false) -> void:
	if not accepts(event) or (event is InputEventKey and event.echo):return
	var pad:=event is InputEventJoypadButton or event is InputEventJoypadMotion
	if event is InputEventMouseMotion:
		look.x-=deg_to_rad(event.screen_relative.x*float(settings.get("sensitivity",.08)))
		look.y=clampf(look.y-deg_to_rad(event.screen_relative.y*float(settings.get("sensitivity",.08))),-1.48,1.48)
	if event is InputEventJoypadMotion:
		match event.axis:
			JOY_AXIS_LEFT_X:move_stick.x=event.axis_value
			JOY_AXIS_LEFT_Y:move_stick.y=event.axis_value
			JOY_AXIS_RIGHT_X:look_stick.x=event.axis_value
			JOY_AXIS_RIGHT_Y:look_stick.y=event.axis_value
	# InputMap's existing pad bindings target device 0. We already checked the
	# physical device above; normalize only this private copy for action matching.
	if pad:
		event=event.duplicate();event.device=0
	for action in ACTIONS:
		if event.is_action_pressed(action) and not down(action):
			held[action]=true;pressed[action]=true
			if action=="aim_toggle" or (action=="aim" and bool(settings.get("toggle_aim",true))):aim_toggle=not aim_toggle;sprint_toggle=false
			if action=="pad_sprint" or (action=="sprint" and bool(settings.get("toggle_sprint",false))):sprint_toggle=not sprint_toggle
			if action in ["sprint","pad_sprint"]:aim_toggle=false;crouch=false;prone=false
			if action in ["jump","crouch"]:prone=false;crouch=false;sprint_toggle=false
			if action=="prone":prone=not prone;crouch=false;sprint_toggle=false
			if action=="pad_crouch":circle_time=0;circle_used=false;sprint_toggle=false
			if action=="jump":crouch=false
			if action=="reload" and pad and pickup_possible:pickup_time=0;pickup_used=false;pressed.erase("reload")
		elif event.is_action_released(action) and down(action):
			held.erase(action)
			if action=="pad_crouch" and not circle_used:crouch=not crouch;prone=false
			if action=="reload" and pickup_time>=0:
				if not pickup_used:pressed["reload"]=true
				pickup_time=-1
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:pressed["pad_switch"]=true

# A press that skips this seat's kill cam (the pad bindings target device 0).
func skip_pressed(event: InputEvent) -> bool:
	if not accepts(event):return false
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		event=event.duplicate();event.device=0
	for action in ["jump","fire","fire_key","pad_fire","ui_accept"]:
		if event.is_action_pressed(action):return true
	return false

func down(action: String) -> bool:
	return bool(held.get(action,false))

func radial(stick: Vector2, deadzone: float) -> Vector2:
	var length:=stick.length()
	return Vector2.ZERO if length<=deadzone else stick/length*clampf((length-deadzone)/(1.0-deadzone),0,1)

func sample(delta: float, actor: Combatant) -> ActorCommand:
	var command:=ActorCommand.new()
	if device==-2:
		command.aim_yaw=actor.yaw;command.aim_pitch=actor.pitch;command.prone=actor.prone;command.crouch=actor.crouched
		return command
	if down("pad_crouch") and not circle_used:
		circle_time+=delta
		if circle_time>=.35:circle_used=true;prone=not prone;crouch=false;sprint_toggle=false
	if pickup_time>=0:
		pickup_time+=delta
		if pickup_time>=.35 and not pickup_used:pickup_used=true;pressed["interact"]=true
	var keys:=Vector2(float(down("right"))-float(down("left")),float(down("back"))-float(down("forward"))).limit_length(1) if device==-1 else Vector2.ZERO
	command.movement=keys if keys!=Vector2.ZERO else radial(move_stick,.18)
	var stick:=radial(look_stick,.14)
	if stick.length_squared()>0:
		var rate:=deg_to_rad(240.0)*float(settings.get("pad_sensitivity",1.0))*(.5 if actor.ads else 1.0)/maxf(1.0,actor.weapon().magnification*.75)
		var turn:=stick.normalized()*pow(stick.length(),1.7)*rate*delta
		look.x-=turn.x;look.y=clampf(look.y-turn.y*.8,-1.48,1.48)
	if (device>=0 or spare_pad>=0) and keys==Vector2.ZERO and command.movement.length()<.3:sprint_toggle=false
	command.aim_yaw=look.x;command.aim_pitch=look.y
	command.fire_held=down("fire") or down("fire_key") or down("pad_fire")
	command.fire_pressed=pressed.has("fire") or pressed.has("fire_key") or pressed.has("pad_fire")
	command.aim_down_sights=aim_toggle or down("pad_aim") or (down("aim") and not bool(settings.get("toggle_aim",true)))
	command.sprint=sprint_toggle or (down("sprint") and not bool(settings.get("toggle_sprint",false)))
	command.crouch=crouch or down("crouch");command.prone=prone
	command.jump_pressed=pressed.has("jump");command.reload_pressed=pressed.has("reload");command.melee_pressed=pressed.has("melee")
	command.interact_pressed=pressed.has("interact");command.interact_held=down("interact") or (pickup_used and down("reload"))
	if pressed.has("pad_switch"):command.requested_weapon_slot=1-actor.selected_weapon
	if pressed.has("primary"):command.requested_weapon_slot=0
	if pressed.has("secondary"):command.requested_weapon_slot=1
	if pressed.has("frag"):command.requested_throwable=0
	elif pressed.has("smoke"):command.requested_throwable=1
	command.throw_held=down("frag") or down("smoke")
	pressed.clear()
	return command

func reset(actor: Combatant) -> void:
	held.clear();pressed.clear();aim_toggle=false;sprint_toggle=false;crouch=false;prone=false
	circle_time=0;circle_used=false;pickup_time=-1;pickup_used=false;move_stick=Vector2.ZERO;look_stick=Vector2.ZERO
	look=Vector2(actor.yaw,actor.pitch)
