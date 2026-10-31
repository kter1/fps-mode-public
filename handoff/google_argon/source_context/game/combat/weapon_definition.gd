class_name WeaponDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var category: String
@export var automatic := false
@export var damage := 28.0
@export var pellets := 1
@export var rpm := 700.0
@export var capacity := 30
@export var reload_seconds := 2.2
@export var shell_reload := false
@export var ads_seconds := 0.22
@export var range_start := 25.0
@export var range_end := 80.0
@export var min_damage := 0.6
@export var hip_spread := 2.0
@export var ads_spread := 0.12
@export var recoil := 1.0
@export var model_path := ""
@export var audio_path := ""

func damage_at(distance: float, head := false) -> float:
	var falloff := lerpf(1.0, min_damage, clampf((distance - range_start) / (range_end - range_start), 0.0, 1.0))
	return damage * falloff * ((1.25 if category == "shotgun" else 2.0) if head else 1.0)
