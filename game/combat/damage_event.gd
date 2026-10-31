class_name DamageEvent
extends RefCounted

var event_id := 0
var source_slot := -1
var victim_slot := -1
var victim_life := -1
var weapon_id: StringName
var amount := 0.0
var headshot := false

var leg_damage := 0.0
var reward := "normal"
