class_name ActorCommand
extends RefCounted

var movement := Vector2.ZERO
var aim_yaw := 0.0
var aim_pitch := 0.0
var fire_pressed := false
var fire_held := false
var aim_down_sights := false
var sprint := false
var crouch := false
var jump_pressed := false
var reload_pressed := false
var requested_weapon_slot := -1
var requested_throwable := -1
# Level of the grenade key: holding it cooks the grenade; releasing throws it.
var throw_held := false
# Bots: horizontal distance and height above the hand to land the throw on (-1 = aim-based).
var throw_range := -1.0
var throw_rise := 0.0
var melee_pressed := false
# Swap for the dropped weapon in reach (player only).
var interact_pressed := false

var interact_held := false
