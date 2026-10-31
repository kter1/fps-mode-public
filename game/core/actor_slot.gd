class_name ActorSlot
extends RefCounted

var id := 0
var team := 0
var is_human := false
var life_id := 0
var kills := 0
var deaths := 0
var callsign := ""
var loadout: LoadoutDefinition
var respawn_at := -1.0
var next_spawn_attempt := -1.0
var death_at := -1.0
var spawned_at := 0.0
