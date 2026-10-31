class_name ZombieStation
extends Node3D

var kind := ""
var item := ""
var price := 0
var zone := 0
var title := ""
var powered := false
var glow: MeshInstance3D
var body: StaticBody3D
var link: NavigationLink3D
var zones: Array = []
var opened := false
var active_until := 0.0
var cooldown_until := 0.0

func configure(data: Dictionary) -> void:
	name=str(data.id);kind=str(data.kind);item=str(data.get("item",""));price=int(data.get("price",0));zone=int(data.get("zone",0));title=str(data.get("title",item.to_upper()))
	global_position=MapCatalog.vec3(data.position);rotation.y=float(data.get("yaw",0))
	var dark:=Color("25383c")
	match kind:
		"wall":
			ZombieVisual.part(self,Vector3(2.3,1.05,.08),Vector3(0,1.3,.1),Color("303c3d"))
			var drawing:=Node3D.new();add_child(drawing);drawing.position=Vector3(0,1.35,.16);ZombieObjects.chalk(drawing,item)
			ZombieObjects.label(self,title+"  [ %d ]"%price,Vector3(0,.67,.2),Color("e5e0cc"),30)
		"door":
			zones=data.zones
			var size:=Vector3(4,3.3,.32)
			glow=ZombieVisual.part(self,size,Vector3(0,1.65,0),Color("4a5958"));body=ZombieObjects.solid(self,size,Vector3(0,1.65,0))
			for y in [1.0,2.0]:ZombieVisual.part(self,Vector3(3.9,.13,.05),Vector3(0,y,.2),Color("caac50"))
			ZombieObjects.label(self,"QUARANTINE\n%d POINTS"%price,Vector3(0,1.8,.22),Color("eee1ad"),44)
		"power":
			ZombieVisual.part(self,Vector3(.75,1.4,.4),Vector3(0,.75,0),dark)
			glow=ZombieVisual.part(self,Vector3(.18,.18,.1),Vector3(0,1.2,.24),Color("c7b159"))
			ZombieVisual.part(self,Vector3(.12,.5,.13),Vector3(0,.85,.3),Color("b94b37"));ZombieObjects.label(self,"MAIN POWER",Vector3(0,1.65,.25),Color("e9d784"),38)
		"upgrade":
			ZombieVisual.part(self,Vector3(1.6,1.1,.9),Vector3(0,.55,0),dark);ZombieVisual.part(self,Vector3(1.8,.18,1),Vector3(0,1.18,0),Color("97977c"))
			glow=ZombieVisual.part(self,Vector3(1,.3,.1),Vector3(0,.86,.49),Color("776a43"));ZombieObjects.label(self,"OVERCHARGER\n5,000",Vector3(0,1.6,.3),Color("a0d8bd"),38)
		"trap":
			ZombieVisual.part(self,Vector3(.5,1.2,.35),Vector3(0,.65,0),dark);ZombieObjects.label(self,"DANGER\nELECTRIC FIELD",Vector3(0,1.65,.2),Color("e1af45"),35)
		_:
			var color:=Color(str(ZombiesCatalog.PERKS.get(item,{}).get("color","6c8b80")))
			ZombieVisual.part(self,Vector3(.9,1.75,.65),Vector3(0,.9,0),color)
			glow=ZombieVisual.part(self,Vector3(.65,.5,.06),Vector3(0,1.35,.36),color.lightened(.3))
			ZombieVisual.part(self,Vector3(.45,.25,.08),Vector3(0,.45,.37),dark)
			for x in [-.2,0.0,.2]:ZombieVisual.part(self,Vector3(.07,.2,.07),Vector3(x,.77,.38),color.lightened(.4),true)
			ZombieVisual.part(self,Vector3(.08,.08,.07),Vector3(.31,.82,.39),Color("d9cea8"),true)
			ZombieObjects.label(self,title+"\n%d"%price,Vector3(0,1.37,.42),Color("fff0c8"),31)
	if kind not in ["wall","door"]:ZombieObjects.solid(self,Vector3(.8,1.4,.6),Vector3(0,.7,0))

func enable_power(value: bool) -> void:
	powered=value
	if glow!=null:glow.material_override=ZombieVisual.finish(Color("a0dccb") if value else Color("666b58"))

func open(world: Object) -> void:
	opened=true;visible=false
	body.collision_layer=0
	if link!=null:link.enabled=true
	for index in zones:world.open_zones[int(index)]=true
	for actor: Combatant in world.actors:
		if actor is ZombieActor:actor.next_path_at=0
