class_name SpawnDirector
extends RefCounted

var recent_spawns:Array[Dictionary]=[]
var last_actor_spawns:Dictionary={}

func select(actor: Combatant, world: Object, allow_exposed := false) -> Variant:
	var points:Array[Vector3]=world.arena.definition.spawns_blue if actor.slot.team==0 else world.arena.definition.spawns_red
	if world.stress_mode:
		points=[]
		# The central cross-aisle stays clear of authored machinery. Keep extra
		# candidates and run the same capsule/occupancy checks as normal spawns.
		for distance in [2.0,3.5]:
			for i in 11:points.append(Vector3(-distance if actor.slot.team==0 else distance,.05,-10+i*2.0))
	var best := Vector3.ZERO
	var best_score := -INF
	var found := false
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new();shape.radius=.37;shape.height=1.8
	query.shape=shape;query.collision_mask=3;query.exclude=actor.excluded()
	for point in points:
		var nearest := 200.0
		var visible := 0
		var allies := 0
		var occupied := false
		for other in world.actors:
			if not other.alive or other==actor:continue
			var distance:float=other.global_position.distance_to(point)
			if distance<1.2:occupied=true
			if other.slot.team==actor.slot.team:
				if distance<15:allies+=1
			else:
				nearest=minf(nearest,distance)
		# Reject nearby enemies before doing physics queries. Unsafe respawns are
		# retried at 5 Hz by MatchWorld, without allocating dozens of shapes per tick.
		if occupied or (not allow_exposed and nearest<20):continue
		query.transform=Transform3D(Basis.IDENTITY,point+Vector3(0,.95,0))
		if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():continue
		for other in world.actors:
			if other==actor or not other.alive or other.slot.team==actor.slot.team:continue
			if other.global_position.distance_squared_to(point)<10000 and world.visible_between(point+Vector3.UP*1.62,other.eye(),false):visible+=1
		if not allow_exposed and (nearest<20 or visible>0):continue
		var score := minf(nearest,80)-visible*50+mini(allies,2)*8
		for recent in recent_spawns:
			if recent.team==actor.slot.team and world.clock-recent.time<8 and point.distance_to(recent.position)<7:
				score-=28*(1-(world.clock-recent.time)/8)
		if last_actor_spawns.has(actor.slot.id) and point.distance_to(last_actor_spawns[actor.slot.id])<8:score-=18
		for death in world.recent_deaths:
			if world.clock-death.time<5 and point.distance_to(death.position)<10:score-=30
		if not found or score>best_score:
			best=point;best_score=score;found=true
	if found:
		recent_spawns.append({"team":actor.slot.team,"position":best,"time":world.clock})
		if recent_spawns.size()>48:recent_spawns.pop_front()
		last_actor_spawns[actor.slot.id]=best
	return best if found else null
