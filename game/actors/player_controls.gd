class_name PlayerControls
extends RefCounted

const KEYS := {"forward":KEY_W,"back":KEY_S,"left":KEY_A,"right":KEY_D,"sprint":KEY_SHIFT,"aim_toggle":KEY_C,"fire_key":KEY_F,"prone":KEY_Z,"crouch":KEY_CTRL,"jump":KEY_SPACE,"reload":KEY_R,"primary":KEY_1,"secondary":KEY_2,"frag":KEY_G,"smoke":KEY_Q,"melee":KEY_V,"interact":KEY_E,"scoreboard":KEY_TAB,"pause":KEY_ESCAPE}
var aiming := false
var sprint_latched := false
var mouse_fire_held:=false
var key_fire_held:=false
# Controller (PS5 / any SDL gamepad): sprint latches on L3 until you stop, tap Circle crouches, hold Circle toggles prone.
var pad_sprint:=false
var pad_crouch:=false
var prone_latched:=false
var circle_started := -1
var circle_hold_used := false
const PRONE_HOLD_MS := 350
var last_was_pad:=false

# Buttons shared with the keyboard actions (added alongside the key binding).
const PAD_BUTTONS := {"jump":JOY_BUTTON_A,"reload":JOY_BUTTON_X,"melee":JOY_BUTTON_RIGHT_STICK,"frag":JOY_BUTTON_RIGHT_SHOULDER,"smoke":JOY_BUTTON_LEFT_SHOULDER,"pause":JOY_BUTTON_START,"scoreboard":JOY_BUTTON_TOUCHPAD}
# Menus: Cross accepts and Circle goes back (Godot's ui_accept / ui_cancel have no pad buttons).
const PAD_UI := {"ui_accept":JOY_BUTTON_A,"ui_cancel":JOY_BUTTON_B}
# Holding Square (the reload button) this long by a dropped weapon picks it up instead.
const PAD_PICKUP_HOLD := .35
# Controller-only actions with their own (hold) semantics.
const PAD_ONLY := {"pad_sprint":JOY_BUTTON_LEFT_STICK,"pad_crouch":JOY_BUTTON_B,"pad_switch":JOY_BUTTON_Y}

static func install(bindings: Dictionary) -> void:
	for action in KEYS:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var key := int(bindings.get(action,KEYS[action]))
		var event := InputEventKey.new()
		# Modifier-only key events on macOS may have no physical scan code.
		if key >= KEY_SPECIAL:event.keycode=key
		else:event.physical_keycode=key
		InputMap.action_add_event(action,event)
	for action in ["fire","aim"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var event := InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT if action=="fire" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action,event)
	for action in PAD_BUTTONS:
		var pad:=InputEventJoypadButton.new();pad.button_index=PAD_BUTTONS[action];InputMap.action_add_event(action,pad)
	for action in PAD_UI:
		var known:=false
		for event in InputMap.action_get_events(action):known=known or (event is InputEventJoypadButton and event.button_index==PAD_UI[action])
		if not known:
			var pad:=InputEventJoypadButton.new();pad.button_index=PAD_UI[action];InputMap.action_add_event(action,pad)
	for action in PAD_ONLY:
		if not InputMap.has_action(action):InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var pad:=InputEventJoypadButton.new();pad.button_index=PAD_ONLY[action];InputMap.action_add_event(action,pad)
	# Triggers: R2 fires, L2 aims (held, whatever the mouse toggle setting).
	for action in ["pad_fire","pad_aim"]:
		if not InputMap.has_action(action):InputMap.add_action(action,.35)
		InputMap.action_erase_events(action)
		var trigger:=InputEventJoypadMotion.new();trigger.axis=JOY_AXIS_TRIGGER_RIGHT if action=="pad_fire" else JOY_AXIS_TRIGGER_LEFT;trigger.axis_value=1.0
		InputMap.action_add_event(action,trigger)
	# Left stick moves (analog strength through Input.get_vector).
	for pair in [["forward",JOY_AXIS_LEFT_Y,-1.0],["back",JOY_AXIS_LEFT_Y,1.0],["left",JOY_AXIS_LEFT_X,-1.0],["right",JOY_AXIS_LEFT_X,1.0]]:
		var stick:=InputEventJoypadMotion.new();stick.axis=pair[1];stick.axis_value=pair[2]
		InputMap.action_add_event(pair[0],stick);InputMap.action_set_deadzone(pair[0],.18)

func handle(event: InputEvent, toggle_aim: bool, toggle_sprint: bool) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:last_was_pad=true
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:last_was_pad=false
	if event.is_action_pressed("prone"):
		prone_latched=not prone_latched;pad_crouch=false;pad_sprint=false;sprint_latched=false
	if event.is_action_pressed("jump") or event.is_action_pressed("crouch") or event.is_action_pressed("sprint") or event.is_action_pressed("pad_sprint"):prone_latched=false
	if event.is_action_pressed("pad_sprint"):pad_sprint=not pad_sprint;aiming=false;pad_crouch=false
	if event.is_action_pressed("pad_crouch"):
		circle_started=Time.get_ticks_msec();circle_hold_used=false;pad_sprint=false
	if event.is_action_released("pad_crouch"):
		update_circle_hold()
		if circle_started>=0 and not circle_hold_used:
			pad_crouch=not pad_crouch;prone_latched=false
		circle_started=-1
	if event.is_action_pressed("pad_aim") or event.is_action_pressed("jump"):pad_sprint=false
	if event.is_action_pressed("jump"):pad_crouch=false
	if event.is_action_pressed("fire"):mouse_fire_held=true
	elif event.is_action_released("fire"):mouse_fire_held=false
	if event.is_action_pressed("fire_key"):key_fire_held=true
	elif event.is_action_released("fire_key"):key_fire_held=false
	if event.is_action_pressed("aim_toggle") or (toggle_aim and event.is_action_pressed("aim")):
		aiming=not aiming;sprint_latched=false
	if event.is_action_pressed("sprint"):
		aiming=false
		if toggle_sprint:sprint_latched=not sprint_latched

func wants_aim(toggle_aim: bool) -> bool:
	return aiming or (not toggle_aim and Input.is_action_pressed("aim")) or Input.is_action_pressed("pad_aim")

func wants_sprint(toggle_sprint: bool) -> bool:
	# The controller's sprint latch ends when the stick comes back towards centre.
	if pad_sprint and Input.get_vector("left","right","forward","back").length()<.3:pad_sprint=false
	return pad_sprint or (sprint_latched if toggle_sprint else Input.is_action_pressed("sprint"))

func update_circle_hold(now := Time.get_ticks_msec()) -> void:
	if circle_started>=0 and not circle_hold_used and now-circle_started>=PRONE_HOLD_MS:
		circle_hold_used=true;prone_latched=not prone_latched;pad_crouch=false;pad_sprint=false;sprint_latched=false

func wants_prone() -> bool:
	update_circle_hold()
	return prone_latched

func wants_crouch() -> bool:
	update_circle_hold()
	return pad_crouch or Input.is_action_pressed("crouch")

func reset() -> void:
	circle_started=-1;circle_hold_used=false
	aiming=false;sprint_latched=false;mouse_fire_held=false;key_fire_held=false;pad_sprint=false;pad_crouch=false;prone_latched=false

func firing() -> bool:
	return mouse_fire_held or key_fire_held or Input.is_action_pressed("pad_fire")
