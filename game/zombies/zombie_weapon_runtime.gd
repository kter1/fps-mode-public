class_name ZombieWeaponRuntime
extends WeaponRuntime

var base_id := ""
var upgraded := false
var reserve_max := 0
var base_capacity := 0
var base_reserve := 0
var base_damage_scale := 2.0

func initialize(source: WeaponDefinition, starter := false, rules: Dictionary = {}) -> void:
	configure(source.duplicate(true),[])
	base_id=str(source.id)
	if starter:
		definition.capacity=int(rules.get("starting_ammo",[8,32])[0]);definition.damage=20;capacity=definition.capacity;ammo=capacity
		base_damage_scale=1.0;reserve=int(rules.get("starting_ammo",[8,32])[1])
	else:reserve=capacity*5
	if base_id.begins_with("z_"):
		base_damage_scale=1.0;reserve=int(ZombiesCatalog.WONDERS[base_id].reserve)
	base_capacity=capacity;base_reserve=reserve;reserve_max=reserve
	recompute([])

func recompute(perks: Array[String]) -> void:
	var old_capacity:=capacity
	capacity=roundi(base_capacity*(1.5 if upgraded else 1.0))
	reserve_max=roundi(base_reserve*(1.5 if upgraded else 1.0))
	if base_id.begins_with("z_") and upgraded:
		capacity=int(ZombiesCatalog.WONDERS[base_id].up_capacity);reserve_max=int(ZombiesCatalog.WONDERS[base_id].up_reserve)
	damage_scale=base_damage_scale*(3.0 if upgraded else 1.0)*(1.25 if "overdrive" in perks and not base_id.begins_with("z_") else 1.0)
	cadence_scale=1.25 if "overdrive" in perks and not base_id.begins_with("z_") else 1.0
	reload_scale=.65 if "hands" in perks else 1.0
	if old_capacity>capacity:ammo=mini(ammo,capacity)
	reserve=mini(reserve,reserve_max)

func refill(magazine := true) -> void:
	reserve=reserve_max
	if magazine:ammo=capacity
