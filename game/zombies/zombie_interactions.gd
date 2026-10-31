class_name ZombieInteractions
extends RefCounted

var world: ZombiesWorld
var candidate: Node3D
var prompt := ""
var progress := 0.0
var blocks_fire := false
var pending := false
var captured: Node3D
var held_weapon: WeaponRuntime
var started := 0.0
var hold_elapsed := 0.0
var last_held := false

func visible(node: Node3D, target: Vector3) -> bool:
	var query:=PhysicsRayQueryParameters3D.create(world.actors[0].eye(),target,1)
	var hit:=world.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or node.is_ancestor_of(hit.collider)

func select() -> Node3D:
	var player:=world.actors[0];var best: Node3D;var distance:=2.2
	var objects: Array=[];objects.append_array(world.barriers);objects.append_array(world.stations);objects.append(world.box)
	for node: Node3D in objects:
		if node is ZombieStation and node.opened:continue
		var target:=node.global_position+Vector3.UP*1.1
		var offset:=target-player.eye();var d:=offset.length()
		if d>=distance or player.aim_direction().dot(offset.normalized())<.55 or not visible(node,target):continue
		distance=d;best=node
	return best

func capture(delta: float) -> void:
	blocks_fire=false;pending=false;candidate=select();prompt=describe(candidate)
	var command:=world.player_command
	var held:=command.interact_held
	if not held or candidate!=captured or not world.actors[0].alive or world.clock<world.downed_until:
		captured=null;hold_elapsed=0;progress=0
	if candidate==null or not world.actors[0].alive or world.clock<world.downed_until:last_held=held;return
	var is_hold: bool=candidate is ZombieBarrier or (candidate is ZombieStation and candidate.kind=="upgrade")
	if is_hold:
		if held:
			if captured==null:captured=candidate;started=world.clock;held_weapon=world.actors[0].weapon()
			if candidate is ZombieStation and candidate.kind=="upgrade":blocks_fire=true
			hold_elapsed+=delta
			var duration: float=float(world.rules.repair_seconds) if candidate is ZombieBarrier else 2.0
			progress=clampf(hold_elapsed/duration,0,1);pending=hold_elapsed>=duration
	else:pending=command.interact_pressed
	last_held=held

func commit() -> void:
	if not pending or candidate==null or not world.actors[0].alive or world.clock<world.downed_until:return
	if select()!=candidate:return
	if candidate is ZombieBarrier or (candidate is ZombieStation and candidate.kind=="upgrade"):
		if world.actors[0].last_damage_at>=started or world.actors[0].weapon()!=held_weapon:
			hold_elapsed=0;progress=0;captured=null;return
		if candidate is ZombieBarrier:candidate.repair(world);hold_elapsed=0;progress=0;return
	perform(candidate);hold_elapsed=0;progress=0;captured=null

func owned_runtime(id: String) -> ZombieWeaponRuntime:
	for runtime: ZombieWeaponRuntime in world.actors[0].weapons:
		if runtime.base_id==id:return runtime
	return null

func describe(node: Node3D) -> String:
	if node==null:return ""
	if node is ZombieBarrier:return "HOLD — REBUILD WINDOW  %d / 6"%node.boards
	if node is ZombieMysteryBox:return "CLAIM "+str(world.catalog.weapons[node.offer].display_name) if node.state=="OFFERED" else ("MYSTERY BOX  [950]" if node.state=="IDLE" else "MYSTERY BOX — "+node.state)
	var station:=node as ZombieStation
	if station.kind=="wall":
		var runtime:=owned_runtime(station.item)
		if runtime!=null:return "AMMO — %s  [%d]"%[runtime.definition.display_name,2500 if runtime.upgraded else station.price/2]
		return "BUY %s  [%d]"%[world.catalog.weapons[station.item].display_name,station.price]
	if station.kind=="door":return "OPEN ROUTE  [%d]"%station.price
	if station.kind=="power":return "POWER ONLINE" if world.mode.power else "RESTORE MAIN POWER"
	if not world.mode.power and station.item!="revive":return "REQUIRES MAIN POWER"
	if station.kind=="upgrade":return "HOLD — OVERCHARGE WEAPON  [5,000]"
	if station.kind=="trap":return "TRAP COOLING DOWN" if world.clock<station.cooldown_until else "ACTIVATE TRAP  [1,000]"
	return "DRINK %s  [%d]"%[station.title,station.price]

func deny(message: String) -> bool:
	world.mode.say(message,1.5);world.cue("denied",world.actors[0].eye(),.3);return false

func perform(node: Node3D) -> bool:
	var player:=world.actors[0] as ZombiePlayer
	if node is ZombieMysteryBox:
		if node.state=="OFFERED":return node.claim()
		if node.state=="IDLE":return node.roll() or deny("NEED 950 POINTS")
		return false
	var station:=node as ZombieStation
	if station==null:return false
	match station.kind:
		"wall":
			var runtime:=owned_runtime(station.item)
			if runtime!=null:
				if runtime.reserve>=runtime.reserve_max:return deny("RESERVE AMMO FULL")
				var cost:=2500 if runtime.upgraded else station.price/2
				if not world.mode.spend(cost):return deny("NOT ENOUGH POINTS")
				runtime.refill(false)
			else:
				if not world.mode.spend(station.price):return deny("NOT ENOUGH POINTS")
				world.give_weapon(station.item)
		"door":
			if station.opened:return false
			if not world.mode.spend(station.price):return deny("NOT ENOUGH POINTS")
			station.open(world);world.mode.say("NEW ROUTE OPEN")
		"power":
			if world.mode.power:return false
			world.mode.power=true
			for machine in world.stations:machine.enable_power(true)
			world.mode.say("MAIN POWER RESTORED");world.cue("power",station.global_position)
		"perk":
			if not world.mode.power and station.item!="revive":return deny("RESTORE THE POWER")
			if station.item in world.mode.perks:return deny("PERK ALREADY OWNED")
			if world.mode.perks.size()>=int(world.rules.perk_limit):return deny("FOUR PERKS MAXIMUM")
			if station.item=="revive" and world.mode.revive_purchases>=3:return deny("SECOND WIND EXHAUSTED")
			if not world.mode.spend(station.price):return deny("NOT ENOUGH POINTS")
			world.mode.perks.append(station.item)
			if station.item=="revive":world.mode.revive_purchases+=1
			player.apply_perks(world.mode.perks)
			if station.item=="heart":player.health=minf(player.max_health,player.health+100)
			world.mode.say(station.title);world.cue("perk",station.global_position)
		"upgrade":
			if not world.mode.power:return deny("RESTORE THE POWER")
			var runtime:=player.weapon() as ZombieWeaponRuntime
			if runtime.upgraded:return deny("WEAPON ALREADY OVERCHARGED")
			if not world.mode.spend(int(world.rules.upgrade_cost)):return deny("NEED 5,000 POINTS")
			runtime.upgraded=true;runtime.recompute(world.mode.perks);runtime.refill();world.mode.say("WEAPON OVERCHARGED");world.cue("upgrade",station.global_position)
		"trap":
			if not world.mode.power:return deny("RESTORE THE POWER")
			if world.clock<station.cooldown_until:return deny("TRAP COOLING DOWN")
			if not world.mode.spend(1000):return deny("NEED 1,000 POINTS")
			station.active_until=world.clock+9;station.cooldown_until=world.clock+54;world.mode.say("ELECTRIC TRAP — STAND CLEAR");world.cue("trap",station.global_position)
		_:return false
	world.cue("purchase",node.global_position,.4);return true

func cancel() -> void:
	captured=null;held_weapon=null;hold_elapsed=0;progress=0;pending=false;blocks_fire=false
