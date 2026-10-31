class_name KillReplay
extends Node3D

# Presentation-only reconstruction of recorded poses. It has no hurtboxes,
# physics bodies, damage events or access to current enemy target positions.
var frames:Array[Dictionary]=[]
var avatars:Array[Dictionary]=[]
var killer := -1
var elapsed := 0.0
var active := false
var skipped := false
var world:MatchWorld
var replay_actor:Combatant
var cursor:=0
var replay_time:=0.0
var source_weapon:=""
var shot_voice:AudioStreamPlayer
var last_replay_shot:=-100.0
# End-of-match kill cam: plays slower over the last SLOW_TAIL seconds into the kill, then
# holds on the final frame for HOLD seconds.
const SLOW_TAIL := .7
const SLOW_RATE := .35
const HOLD := 1.6
var final_cam:=false
var held:=0.0

func configure(source:MatchWorld) -> void:
	world=source;name="KillReplay";hide()
	for actor in world.actors:
		var model:=SoldierFactory.soldier(actor.slot.team);add_child(model);model.hide()
		var player:=ModelFactory.animation_player(model)
		if player!=null:player.get_parent().remove_child(player);player.free()
		var gun:=ModelFactory.weapon(actor.weapon().definition,actor.weapon().attachments);add_child(gun);gun.hide()
		avatars.append({"model":model,"skeleton":SoldierFactory.skeleton_of(model),"weapon":gun,"weapon_id":str(actor.weapon().definition.id),"attachments":actor.weapon().attachments.duplicate()})
	replay_actor=Combatant.new();add_child(replay_actor)
	shot_voice=AudioStreamPlayer.new();shot_voice.max_polyphony=4;shot_voice.volume_db=-4;add_child(shot_voice)
	var slot:=ActorSlot.new();slot.id=0;slot.is_human=true;slot.loadout=world.catalog.starter_loadouts()[0]
	replay_actor.slot=slot;replay_actor.alive=true
	var runtime:=WeaponRuntime.new();runtime.configure(world.catalog.weapons.ar_a4,[]);replay_actor.weapons.append(runtime)

func begin(source:int, death_time:float) -> bool:
	if source==0:return false
	return play(source,world.replay_history.preceding(death_time),false)

# The match's last kill, from frames MatchWorld kept when it happened (the player's own
# kills included).
func begin_final(source:int, recorded:Array) -> bool:
	var kept:Array[Dictionary]=[]
	kept.assign(recorded)
	return play(source,kept,true)

func play(source:int, recorded:Array[Dictionary], final:bool) -> bool:
	stop();skipped=false
	if source<0 or source>=world.actors.size():return false
	frames=recorded
	if frames.size()<2:return false
	killer=source;elapsed=0;cursor=0;replay_time=frames[0].time;active=true;final_cam=final;held=0.0
	replay_actor.slot.team=world.actors[source].slot.team
	show();world.effects.hide();world.effects.replay_muted=true;last_replay_shot=-100
	for voice in world.effects.voices:voice.stop()
	for voice in world.effects.player_voices:voice.stop()
	for grenade in world.grenades:
		if is_instance_valid(grenade.body_mesh):grenade.body_mesh.hide()
	for actor in world.actors:actor.visual.hide()
	for corpse in world.corpses:corpse.node.hide()
	for entry in world.pickups:
		if is_instance_valid(entry.node):entry.node.hide()
	return true

# The final kill cam has run to its end and held there.
func finished() -> bool:
	return not active or (final_cam and held>=HOLD)

func skip() -> void:
	skipped=true;stop()

func stop() -> void:
	if is_instance_valid(world):
		world.effects.show();world.effects.replay_muted=false
		for grenade in world.grenades:
			if is_instance_valid(grenade.body_mesh):grenade.body_mesh.show()
		for actor in world.actors:actor.visual.visible=actor.alive and not actor.slot.is_human
		for corpse in world.corpses:
			if is_instance_valid(corpse.node):corpse.node.show()
		for entry in world.pickups:
			if is_instance_valid(entry.node):entry.node.show()
	active=false;final_cam=false;hide();frames.clear();source_weapon=""
	if is_instance_valid(shot_voice):shot_voice.stop()

func advance(delta:float, camera:Camera3D, hands:ViewModel, base_fov:float) -> void:
	if not active:return
	var end:float=frames.back().time
	if final_cam and replay_time>=end:held+=delta
	# The final kill cam slows into the shot.
	var rate:=SLOW_RATE if final_cam and frames[0].time+elapsed>end-SLOW_TAIL else 1.0
	elapsed+=delta*rate
	replay_time=minf(frames[0].time+elapsed,end)
	while cursor<frames.size()-2 and frames[cursor+1].time<=replay_time:cursor+=1
	var a:Dictionary=frames[cursor];var b:Dictionary=frames[mini(cursor+1,frames.size()-1)]
	var blend:=clampf((replay_time-a.time)/maxf(.001,b.time-a.time),0,1)
	for i in avatars.size():
		var before:Dictionary=a.actors[i];var after:Dictionary=b.actors[i];var avatar:Dictionary=avatars[i]
		var weight:=blend if before.life==after.life else 0.0
		avatar.model.visible=before.alive and i!=killer
		avatar.model.position=Vector3(before.position).lerp(after.position,weight)
		avatar.model.rotation.y=lerp_angle(before.yaw,after.yaw,weight)
		var skeleton:Skeleton3D=avatar.skeleton
		for bone in before.poses.size():
			var pose:Transform3D=before.poses[bone]
			if bone<after.poses.size():pose=pose.interpolate_with(after.poses[bone],weight)
			skeleton.set_bone_pose(bone,pose)
		if avatar.weapon_id!=str(before.weapon) or avatar.attachments!=before.attachments:
			if is_instance_valid(avatar.weapon):avatar.weapon.free()
			avatar.weapon=ModelFactory.weapon(world.catalog.weapons[str(before.weapon)],before.attachments);add_child(avatar.weapon)
			avatar.weapon_id=str(before.weapon);avatar.attachments=before.attachments.duplicate()
		avatar.weapon.visible=avatar.model.visible
		avatar.weapon.global_transform=Transform3D(before.gun).interpolate_with(after.gun,weight)
		world.actors[i].visual.hide()
	for corpse in world.corpses:corpse.node.hide()
	var state:Dictionary=a.actors[killer];var next:Dictionary=b.actors[killer]
	var direction:=Vector2(lerp_angle(state.yaw,next.yaw,blend),lerpf(state.pitch,next.pitch,blend))
	camera.position=Vector3(state.position).lerp(next.position,blend)+Vector3.UP*lerpf(state.eye,next.eye,blend)
	camera.rotation=Vector3(direction.y+lerpf(state.recoil,next.recoil,blend),direction.x,0)
	replay_actor.yaw=direction.x;replay_actor.pitch=direction.y;replay_actor.ads=state.ads;replay_actor.velocity=state.velocity
	replay_actor.action_until=state.action_until;replay_actor.action_kind=state.action_kind;replay_actor.throw_at=state.throw_at;replay_actor.throw_kind=state.throw_kind;replay_actor.throw_started=state.throw_started;replay_actor.throw_holding=state.throw_holding
	if source_weapon!=str(state.weapon)+str(state.attachments):
		replay_actor.weapon().configure(world.catalog.weapons[str(state.weapon)],state.attachments)
		source_weapon=str(state.weapon)+str(state.attachments);hands.refresh(replay_actor)
	var runtime:=replay_actor.weapon();runtime.ammo=state.ammo;runtime.state=state.state;runtime.reload_at=state.reload_at;runtime.last_shot_at=state.last_shot_at
	if runtime.last_shot_at>last_replay_shot and runtime.last_shot_at>=frames[0].time:
		last_replay_shot=runtime.last_shot_at
		shot_voice.stream=load("res://content/audio/"+runtime.definition.category+"_0.wav");shot_voice.play()
	hands.shown=true;hands.tick(delta*rate,replay_time,.5)
	var aimed:=rad_to_deg(2*atan(tan(deg_to_rad(base_fov)*.5)/runtime.magnification))
	camera.fov=lerpf(base_fov,aimed,hands.blend)
