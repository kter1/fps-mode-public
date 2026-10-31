class_name LoadoutDefinition
extends Resource

@export var display_name := "Assault"
@export var primary: StringName = &"ar_a4"
@export var sidearm: StringName = &"pistol_p9"
@export var primary_attachments: Array[String] = []
@export var sidearm_attachments: Array[String] = []
@export var frag_count := 1
@export var smoke_count := 1

func to_dict() -> Dictionary:
	return {"name": display_name, "primary": str(primary), "sidearm": str(sidearm), "primary_attachments": primary_attachments, "sidearm_attachments": sidearm_attachments}
