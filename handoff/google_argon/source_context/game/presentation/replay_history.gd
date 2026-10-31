class_name ReplayHistory
extends RefCounted

const MAX_FRAMES := 72
const INTERVAL := .05
var frames: Array[Dictionary] = []
var next_sample := 0.0

func record(now:float, actors:Array[Combatant], force:=false) -> void:
	if not force and now+.00001<next_sample:return
	next_sample=now+INTERVAL
	var states:Array[Dictionary]=[]
	for actor in actors:
		var runtime:=actor.weapon()
		var poses:Array[Transform3D]=[]
		if actor.skeleton!=null and actor.alive:
			for bone in actor.skeleton.get_bone_count():poses.append(actor.skeleton.get_bone_pose(bone))
		states.append({"position":actor.global_position,"yaw":actor.yaw,"pitch":actor.pitch,"recoil":actor.recoil,"eye":actor.eye_height,"velocity":actor.velocity,"ads":actor.ads,"alive":actor.alive,"life":actor.slot.life_id,"weapon":runtime.definition.id,"attachments":runtime.attachments.duplicate(),"ammo":runtime.ammo,"state":runtime.state,"reload_at":runtime.reload_at,"last_shot_at":runtime.last_shot_at,"poses":poses,"gun":actor.gun_mount.global_transform})
		states.back().merge({"action_until":actor.action_until,"action_kind":actor.action_kind,"throw_at":actor.throw_at,"throw_kind":actor.throw_kind,"throw_started":actor.throw_started,"throw_holding":actor.throw_holding})
	frames.append({"time":now,"actors":states})
	if frames.size()>MAX_FRAMES:frames.pop_front()

func preceding(now:float, seconds:=2.6) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for frame in frames:
		if frame.time>=now-seconds and frame.time<=now:result.append(frame)
	return result

func clear() -> void:
	frames.clear();next_sample=0
