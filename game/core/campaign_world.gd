class_name CampaignWorld
extends MatchWorld

var dialogue:CampaignDialogue
var initial_stage := 0
var objective_beacon:MeshInstance3D

func configure(source: Catalog, map_id: String, loadout: LoadoutDefinition, level: int, random_seed: int, auto := false) -> void:
	mode=CampaignMode.new();mode_id="campaign"
	super.configure(source,map_id,loadout,level,random_seed,auto)

func finish_loading() -> void:
	await super.finish_loading()
	if not ready_for_play:return
	mode.stage=clampi(initial_stage,0,3)
	objective_beacon=MeshInstance3D.new()
	var mesh:=CylinderMesh.new();mesh.top_radius=.6;mesh.bottom_radius=.6;mesh.height=.08
	objective_beacon.mesh=mesh
	var material:=StandardMaterial3D.new();material.albedo_color=Color("72c8e8");material.emission_enabled=true;material.emission=Color("72c8e8")
	objective_beacon.material_override=material;add_child(objective_beacon)
	activate_encounter(true)
	dialogue=CampaignDialogue.new();add_child(dialogue);dialogue.configure(self)
	mode.activated=true

func deactivate_actor(actor:Combatant) -> void:
	actor.alive=false;actor.slot.respawn_at=-1
	actor.collision_layer=0;actor.collision_mask=0;actor.head.collision_layer=0;actor.torso.collision_layer=0
	actor.visual.visible=false

func activate_encounter(restarting:bool) -> void:
	if dialogue!=null:dialogue.stop()
	for actor in actors:
		if actor.slot.id>=3:deactivate_actor(actor)
	if restarting:
		for i in 3:
			actors[i].respawn(arena.closest(CampaignMode.STARTS[mode.stage]+Vector3(0,0,i*2)),clock,catalog)
			actors[i].yaw=-PI*.5
	for i in CampaignMode.COUNTS[mode.stage]:
		var actor:=actors[TEAM_SIZE+i]
		var offset:=Vector3(-9+i%4*6,0,8+i/4*5)
		actor.respawn(arena.closest(CampaignMode.TARGETS[mode.stage]+offset),clock,catalog)
		actor.bot.reset()
	objective_beacon.position=CampaignMode.TARGETS[mode.stage]+Vector3(0,.12,0)
	# Allies follow the player's path, while keeping their existing combat AI.
	for i in [1,2]:
		if not actors[i].alive:actors[i].respawn(arena.closest(actors[0].global_position+Vector3(i*2,0,2)),clock,catalog)

func _physics_process(delta:float) -> void:
	if ready_for_play and not mode.finished:
		if countdown<=0 and dialogue!=null:dialogue.start_intro()
		for i in [1,2]:
			var ally:=actors[i]
			if ally.alive and ally.global_position.distance_to(actors[0].global_position)>10:
				ally.bot.destination=arena.closest(actors[0].global_position+Vector3(i*2,0,2))
				ally.nav.target_position=ally.bot.destination;ally.bot.has_goal=true
	super._physics_process(delta)
	if mode.finished and dialogue!=null:dialogue.stop()
