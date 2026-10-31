class_name Catalog
extends RefCounted

var weapons: Dictionary = {}
var attachments: Dictionary = {}
var weapon_ids: Array[String] = ["ar_a4", "ar_k47", "ar_b56", "smg_mp9", "smg_v45", "smg_p90", "sg_p12", "sg_a12", "lmg_l56", "lmg_l762", "dmr_d14", "sniper_s90", "pistol_p9", "pistol_p45", "pistol_r357"]
var attachment_ids: Array[String] = ["reflex", "holographic", "scope", "compensator", "suppressor", "extended", "fast", "vertical", "angled"]

func _init() -> void:
	for id in weapon_ids:
		weapons[id] = load("res://content/data/weapons/" + id + ".tres")
	for id in attachment_ids:
		attachments[id] = load("res://content/data/attachments/" + id + ".tres")

func valid_attachments(weapon: WeaponDefinition, selected: Array) -> bool:
	if selected.size() > 3:
		return false
	var used := {}
	for id in selected:
		if not attachments.has(id): return false
		var item: AttachmentDefinition = attachments[id]
		if used.has(item.slot) or not item.compatible(weapon): return false
		used[item.slot] = true
	return true

func starter_loadouts() -> Array[LoadoutDefinition]:
	var result: Array[LoadoutDefinition] = []
	var names := ["Assault", "Close Quarters", "Support", "Marksman", "Precision"]
	var primaries := ["ar_a4", "smg_mp9", "lmg_l56", "dmr_d14", "sniper_s90"]
	for i in 5:
		var item := LoadoutDefinition.new()
		item.display_name = names[i]
		item.primary = StringName(primaries[i])
		item.primary_attachments.assign(["reflex", "compensator"] if i < 3 else ["angled"])
		result.append(item)
	return result
