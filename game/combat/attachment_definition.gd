class_name AttachmentDefinition
extends Resource

@export var id: StringName
@export var slot: String
@export var display_name: String
@export var description: String
@export var modifiers: Dictionary

func compatible(weapon: WeaponDefinition) -> bool:
	return incompatibility_reason(weapon)==""

func incompatibility_reason(weapon:WeaponDefinition) -> String:
	if slot == "grip":
		return "primaries only" if weapon.category=="sidearm" else ""
	if slot == "magazine":
		return "detachable magazines only" if weapon.id in [&"sg_p12", &"pistol_r357"] else ""
	if id == &"suppressor":
		return "unavailable for this barrel" if weapon.category=="shotgun" or weapon.id==&"pistol_r357" else ""
	return ""
