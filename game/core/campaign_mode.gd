class_name CampaignMode
extends TeamDeathmatchMode

signal checkpoint_reached(stage: int)

const TITLES := ["SECURE THE PUMP HOUSE", "RESTORE EMERGENCY POWER", "RECOVER CONTROL RECORDS", "REACH SEAWALL EXTRACTION"]
const RADIO := ["ROOK: Intake route is compromised. Clear the pump house.", "CONTROL: Secure the switchyard relay. Stay beside it to restore the feed.", "CONTROL: The records are on the raised turbine control deck. Recover them.", "ROOK: Records secured. Get to the seawall. We're leaving together."]
const TARGETS := [Vector3(0,0,29), Vector3(0,0,-31), Vector3(0,3.4,-8.5), Vector3(-38,0,40)]
const STARTS := [Vector3(-46,0,18), Vector3(-20,0,29), Vector3(-25,0,-20), Vector3(-20,0,14)]
const COUNTS := [4,6,8,4]
var stage := 0
var hold := 0.0
var success := false
var activated := false

func begin(match_context: Object) -> void:
	super.begin(match_context)
	stage=0;hold=0;success=false;activated=false

func on_actor_died(event: Dictionary) -> void:
	if event.victim==0:
		finished=true;success=false
	# Campaign casualties never automatically respawn.
	context.slots[event.victim].respawn_at=-1

func enemies_left() -> int:
	var count:=0
	for actor in context.actors:
		if actor.slot.team==1 and actor.alive:count+=1
	return count

func tick(delta: float) -> void:
	if finished or not activated:return
	var player:Combatant=context.actors[0]
	if not player.alive:finished=true;return
	var near:=player.global_position.distance_to(TARGETS[stage])<4.0
	if near and enemies_left()==0:hold+=delta
	else:hold=0.0
	if hold<3.0:return
	if stage==3:
		success=true;finished=true
	else:
		stage+=1;hold=0.0
		context.activate_encounter(false)
		checkpoint_reached.emit(stage)

func get_result() -> Dictionary:
	return {"winner":0 if success else 1,"scores":scores.duplicate(),"success":success,"stage":stage,"mission":"Dead Circuit"}
