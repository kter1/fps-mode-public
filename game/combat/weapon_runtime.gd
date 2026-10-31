class_name WeaponRuntime
extends RefCounted

# Bare iron sights (no optic attached) magnify the aimed view; optics and scopes set their own.
const IRON_MAGNIFICATION := 1.4

var definition: WeaponDefinition
var attachments: Array[String] = []
var damage_scale := 1.0
var cadence_scale := 1.0
var reload_scale := 1.0
var capacity := 30
var ammo := 30
var reserve := 90
var reload_time := 2.2
var ads_time := 0.22
var recoil_scale := 1.0
var hip_scale := 1.0
var range_scale := 1.0
var hearing_scale := 1.0
var magnification := IRON_MAGNIFICATION
var state := "READY"
var ready_at := 0.0
var next_shot_at := 0.0
var reload_at := -1.0
var last_shot_at := -100.0

func configure(source: WeaponDefinition, selected: Array[String] = []) -> void:
	damage_scale=1.0;cadence_scale=1.0;reload_scale=1.0
	definition = source
	attachments = selected.duplicate()
	capacity = source.capacity
	reload_time = source.reload_seconds
	ads_time = source.ads_seconds
	recoil_scale = 1.0
	hip_scale = 1.0
	range_scale = 1.0
	hearing_scale = 1.0
	magnification = 6.0 if source.category == "sniper" else IRON_MAGNIFICATION
	var ads_add := 0.0
	var capacity_factor := 1.0
	for item in attachments:
		var attachment:AttachmentDefinition=load("res://content/data/attachments/"+item+".tres")
		var modifiers:=attachment.modifiers
		capacity_factor*=float(modifiers.get("capacity",1.0))
		reload_time*=float(modifiers.get("reload",1.0))
		ads_time*=float(modifiers.get("ads",1.0))
		ads_add+=float(modifiers.get("ads_add",0.0))
		recoil_scale*=float(modifiers.get("recoil",1.0))
		hip_scale*=float(modifiers.get("hip",1.0))
		range_scale*=float(modifiers.get("range",1.0))
		hearing_scale*=float(modifiers.get("hearing",1.0))
		if modifiers.has("magnification"):magnification=float(modifiers.magnification)
	capacity=roundi(source.capacity*capacity_factor)
	ads_time += ads_add
	ammo = capacity
	reserve = capacity * 3
	state = "READY"
	reload_at = -1
	next_shot_at = 0
	last_shot_at = -100

func equip(now: float) -> void:
	cancel_reload()
	state = "EQUIPPING"
	ready_at = now + 0.35
	next_shot_at = maxf(next_shot_at, ready_at)

func cancel_reload() -> void:
	reload_at = -1
	state = "READY"

func start_reload(now: float) -> bool:
	if ammo >= capacity or reserve <= 0 or state != "READY":
		return false
	state = "RELOADING"
	reload_at = now + (0.6 if definition.shell_reload else reload_time + (0.35 if ammo == 0 else 0.0))*reload_scale
	return true

func tick(now: float) -> void:
	if state == "EQUIPPING" and now >= ready_at:
		state = "READY"
	if state != "RELOADING" or now < reload_at:
		return
	if definition.shell_reload:
		ammo += 1
		reserve -= 1
		if ammo < capacity and reserve > 0:
			reload_at += 0.6*reload_scale
		else:
			cancel_reload()
	else:
		var transferred := mini(capacity - ammo, reserve)
		ammo += transferred
		reserve -= transferred
		cancel_reload()

func try_fire(now: float, pressed: bool, held: bool) -> bool:
	if definition.shell_reload and state == "RELOADING" and pressed and ammo > 0:
		cancel_reload()
	if state != "READY" or ammo <= 0 or now + 0.00001 < next_shot_at:
		return false
	if not pressed and not (definition.automatic and held):
		return false
	ammo -= 1
	last_shot_at = now
	var interval := 60.0 / (definition.rpm*cadence_scale)
	next_shot_at = (next_shot_at + interval) if now - next_shot_at < 1.0 / 30.0 else now + interval
	return true
