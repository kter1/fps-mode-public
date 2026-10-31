class_name ZombiesCatalog
extends Catalog

var rules: Dictionary = {}

const WONDERS := {
	"z_ray":{"name":"Raycaster","capacity":20,"reserve":160,"rpm":180,"reload":2.4,"up_capacity":40,"up_reserve":240},
	"z_thunder":{"name":"Thunder Cannon","capacity":2,"reserve":12,"rpm":45,"reload":3.0,"up_capacity":4,"up_reserve":24},
	"z_arc":{"name":"Arc Rifle","capacity":3,"reserve":24,"rpm":60,"reload":2.8,"up_capacity":6,"up_reserve":36}}
const PERKS := {"heart":{"name":"IRONHEART","price":2500,"color":"d64c41"},"hands":{"name":"QUICK HANDS","price":3000,"color":"50bc70"},"stride":{"name":"LONG STRIDE","price":2000,"color":"e5b347"},"revive":{"name":"SECOND WIND","price":500,"color":"68badd"},"overdrive":{"name":"OVERDRIVE","price":2000,"color":"db8b32"}}
const WALLS := {"pistol_p9":500,"sg_p12":750,"smg_mp9":1000,"ar_a4":1500,"lmg_l56":2000}

func _init() -> void:
	super()
	rules=JSON.parse_string(FileAccess.get_file_as_string("res://content/data/zombies/rules.json"))
	for id: String in WONDERS:
		var info: Dictionary=WONDERS[id]
		var item:=WeaponDefinition.new();item.id=StringName(id);item.display_name=info.name;item.category="wonder"
		item.capacity=int(info.capacity);item.rpm=float(info.rpm);item.reload_seconds=float(info.reload);item.recoil=.8
		item.model_path="";item.ads_seconds=.25;weapons[id]=item

func runtime(id: String, starter := false) -> ZombieWeaponRuntime:
	var item:=ZombieWeaponRuntime.new();item.initialize(weapons[id],starter,rules);return item
