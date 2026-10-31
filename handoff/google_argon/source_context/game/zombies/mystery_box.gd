class_name ZombieMysteryBox
extends Node3D

var world: Object
var sites: Array = []
var site := 0
var state := "IDLE"
var until := 0.0
var offer := ""
var spins := 0
var lid: Node3D
var display: Node3D
var sign: Label3D

func configure(context: Object, locations: Array) -> void:
	world=context;sites=locations;position=MapCatalog.vec3(sites[0].position)
	ZombieVisual.part(self,Vector3(1.8,.7,.75),Vector3(0,.4,0),Color("775a3e"))
	for x in [-.7,.7]:ZombieVisual.part(self,Vector3(.09,.75,.82),Vector3(x,.4,0),Color("6d7771"))
	lid=ZombieObjects.joint(self,"Lid",Vector3(0,.78,-.36))
	ZombieVisual.part(lid,Vector3(1.85,.12,.8),Vector3(0,0,.36),Color("9b784e"))
	sign=ZombieObjects.label(self,"?    ?    ?\n950",Vector3(0,1.1,.45),Color("efdca4"),50)
	# A visible column meshes the site's location without relying on bloom.
	ZombieVisual.part(self,Vector3(.1,12,.1),Vector3(0,7,0),Color("74a7c0"))

func roll() -> bool:
	if state!="IDLE" or not world.mode.spend(int(world.rules.box_cost)):return false
	spins+=1;state="ROLLING";until=world.clock+3
	if spins>=4 and sites.size()>1 and world.box_rng.randf()<.15:offer="relocate"
	else:
		var choices: Array[String]=[];var total:=0
		for id: String in world.catalog.weapons:
			if world.owns(id):continue
			var weight:=3 if id=="z_ray" else (2 if id.begins_with("z_") else 10)
			for i in weight:choices.append(id)
			total+=weight
		offer=choices[world.box_rng.randi_range(0,total-1)]
	world.cue("box_roll",global_position);return true

func claim() -> bool:
	if state!="OFFERED" or offer=="relocate":return false
	if not world.give_weapon(offer):return false
	close();world.cue("box_claim",global_position);return true

func close() -> void:
	if display!=null:display.queue_free();display=null
	state="CLOSING";until=world.clock+1;sign.text="?    ?    ?\n950"

func tick(delta: float) -> void:
	lid.rotation.x=move_toward(lid.rotation.x,-1.5 if state in ["ROLLING","OFFERED"] else 0,delta*2)
	if display!=null:display.rotation.y+=delta;display.position.y=1.35+sin(world.clock*2)*.07
	if world.clock<until:return
	match state:
		"ROLLING":
			if offer=="relocate":
				world.mode.points+=int(world.rules.box_cost);state="RELOCATING";until=world.clock+3;sign.text="BACK SOON!";world.cue("box_move",global_position)
			else:
				state="OFFERED";until=world.clock+10;display=ModelFactory.weapon(world.catalog.weapons[offer]);add_child(display);display.position.y=1.4
				sign.text=str(world.catalog.weapons[offer].display_name).to_upper()+"\nCLAIM"
		"OFFERED":close()
		"CLOSING":state="IDLE"
		"RELOCATING":
			site=(site+1+world.box_rng.randi_range(0,sites.size()-2))%sites.size();position=MapCatalog.vec3(sites[site].position);spins=0;state="IDLE";sign.text="?    ?    ?\n950"
