class_name ZombieBarrier
extends Node3D

var boards := 6
var zone := 0
var outside := Vector3.ZERO
var inside := Vector3.ZERO
var attacker := -1
var traveller := -1
var occupants: Array[int] = []
var planks: Array[MeshInstance3D] = []
var pending_carpenter := false

func configure(data: Dictionary) -> void:
	name=str(data.id);zone=int(data.zone);global_position=MapCatalog.vec3(data.position);rotation.y=float(data.yaw)
	outside=global_position+global_basis*Vector3(0,0,2.5);inside=global_position+global_basis*Vector3(0,0,-2.0)
	for i in 6:
		var plank:=ZombieVisual.part(self,Vector3(2.35,.17,.11),Vector3(0,.4+i*.29,0),Color("79614b"));plank.rotation.z=(.1 if i%2==0 else -.08);planks.append(plank)
	# The window contains the human; enemy entry is an explicitly reserved traversal.
	var boundary:=ZombieObjects.solid(self,Vector3(2.4,2.6,.18),Vector3(0,1.3,.2));boundary.collision_layer=128

func reserve(id: int) -> bool:
	if occupants.size()>=3:return false
	occupants.append(id)
	if attacker<0:attacker=id
	return true

func release(id: int) -> void:
	occupants.erase(id)
	if traveller==id:traveller=-1
	attacker=occupants[0] if not occupants.is_empty() else -1
	if pending_carpenter and traveller<0:boards=6;pending_carpenter=false;refresh()

func refresh() -> void:
	for i in 6:planks[i].visible=i<boards

func tear(world: Object) -> void:
	if boards==0:return
	boards-=1;refresh();world.cue("board_tear",global_position,.45)

func repair(world: Object) -> bool:
	if boards>=6 or traveller>=0:return false
	boards+=1;refresh();world.cue("board_repair",global_position,.5)
	if world.mode.repair_earned<100:world.mode.award(10);world.mode.repair_earned+=10
	return true

func carpenter() -> void:
	if traveller>=0:pending_carpenter=true
	else:boards=6;refresh()
