class_name TeamDeathmatchMode
extends RefCounted

var scores := [0, 0]
var remaining := 600.0
var kill_limit := 100
var finished := false
var context: Object

func begin(match_context: Object) -> void:
	context = match_context
	scores = [0, 0]
	remaining = 600.0
	finished = false

func on_actor_died(event: Dictionary) -> void:
	if finished or event.source < 0 or event.source == event.victim:
		return
	var team: int = context.slots[event.source].team
	if team != context.slots[event.victim].team:
		scores[team] += 1

func tick(delta: float) -> void:
	if finished:
		return
	remaining = maxf(0, remaining - delta)
	finished = scores[0] >= kill_limit or scores[1] >= kill_limit or remaining <= 0

func get_result() -> Dictionary:
	return {"winner": -1 if scores[0] == scores[1] else (0 if scores[0] > scores[1] else 1), "scores": scores.duplicate()}
