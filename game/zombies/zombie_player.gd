class_name ZombiePlayer
extends Combatant

func set_loadout(source: Catalog) -> void:
	weapons.clear()
	var zcatalog:=source as ZombiesCatalog
	weapons.append(zcatalog.runtime("pistol_p9",true));selected_weapon=0
	refresh_gun()

func respawn(point: Vector3, now: float, source: Catalog) -> void:
	super(point,now,source)
	frags=2;smokes=0;protected_until=0;collision_mask=131

func apply_perks(perks: Array[String]) -> void:
	max_health=200 if "heart" in perks else 100
	health=minf(health,max_health);movement_scale=1.15 if "stride" in perks else 1.0
	for item: ZombieWeaponRuntime in weapons:item.recompute(perks)
