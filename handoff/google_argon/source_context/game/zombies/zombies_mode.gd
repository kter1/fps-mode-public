class_name ZombiesMode
extends RefCounted

var finished := false
var context: Object
var round_number := 0
var completed_rounds := 0
var remaining_to_spawn := 0
var intermission := 5.0
var points := 500
var earned := 0
var kills := 0
var headshots := 0
var repair_earned := 0
var drops_this_round := 0
var perks: Array[String] = []
var revive_purchases := 0
var power := false
var double_until := 0.0
var insta_until := 0.0
var notice := "SURVIVE. REPAIR. EXPLORE."
var notice_until := 5.0

static func budget(r: int) -> int:
	return 6+3*(r-1)+floori(pow(r-1,2)/8.0)

static func enemy_health(r: int) -> float:
	return 150.0+50*(r-1) if r<10 else minf(100000000.0,550.0*pow(1.12,mini(r-9,100)))

func begin(source: Object) -> void:
	context=source

func tick(delta: float) -> void:
	if finished:return
	if intermission>0:
		intermission=maxf(0,intermission-delta)
		if intermission==0:
			round_number+=1;remaining_to_spawn=budget(round_number);repair_earned=0;drops_this_round=0
			context.actors[0].frags=mini(4,maxi(2,context.actors[0].frags))
			say("ROUND %d"%round_number);context.cue("round_start",context.actors[0].global_position)

func check_clear(living: int) -> void:
	if not finished and round_number>0 and intermission==0 and remaining_to_spawn==0 and living==0:
		completed_rounds=round_number;intermission=10.0
		say("ROUND CLEARED — REPAIR AND REARM");context.cue("round_end",context.actors[0].global_position)

func award(value: int) -> void:
	var actual:=value*(2 if context.clock<double_until else 1)
	points+=actual;earned+=actual

func spend(value: int) -> bool:
	if value<0 or points<value:return false
	points-=value;return true

func say(message: String, seconds := 3.0) -> void:
	notice=message;notice_until=context.clock+seconds

func on_actor_died(_event: Dictionary) -> void:
	pass

func get_result() -> Dictionary:
	return {"round":round_number,"completed":completed_rounds,"kills":kills,"headshots":headshots,"points_earned":earned,"seconds":context.clock}
