class_name GameGrenade
extends Node3D

signal bounced(position: Vector3, speed: float)
# A thrown grenade integrated by hand: ballistic flight swept with rays so it cannot
# tunnel through thin cover at throw speed, then bounce (restitution), glancing-blow
# friction and rolling resistance. MatchWorld steps it every physics tick.
const RADIUS := .07
const RESTITUTION := .36
const IMPACT_GRIP := .55
const ROLL_DECEL := 3.4
const MIN_BOUNCE := 1.3
const REST_SPEED := .3

var source := -1
var kind := 0
var detonate_at := 0.0
var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var body_mesh: Node3D
var bounces := 0
var first_impact := Vector3.INF
var grounded := false

func configure(owner_id: int, type: int, fuse_end: float, position: Vector3, launch: Vector3) -> void:
	source=owner_id;kind=type;detonate_at=fuse_end;velocity=launch
	global_position=position
	var side:=launch.cross(Vector3.UP)
	spin=side.normalized()*-14.0 if side.length_squared()>.0001 else Vector3(0,0,14)
	if DisplayServer.get_name()!="headless":body_mesh=ModelFactory.grenade(kind);add_child(body_mesh)

# The hand's release point, pulled back along the segment from the eye when cover is in the way.
static func clear_point(space: PhysicsDirectSpaceState3D, eye: Vector3, hand: Vector3) -> Vector3:
	var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,hand,1))
	if hit.is_empty():return hand
	return hit.position+hit.normal*RADIUS*1.5

func step(delta: float) -> void:
	var space:=get_world_3d().direct_space_state
	velocity.y-=ThrowTimeline.GRAVITY*delta
	var remaining:=delta
	grounded=false
	for pass_index in 3:
		var motion:=velocity*remaining
		var distance:=motion.length()
		if distance<.00001:break
		var direction:=motion/distance
		var hit:Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position,global_position+direction*(distance+RADIUS),1))
		if hit.is_empty():
			global_position+=motion;break
		var normal:Vector3=hit.normal
		if normal.length_squared()<.5:normal=-direction
		# Sphere against a plane: the centre stops RADIUS from the surface, measured along the path.
		var approach:=maxf(-direction.dot(normal),.2)
		var contact:Vector3=hit.position
		var travel:float=contact.distance_to(global_position)-RADIUS/approach
		if travel>=distance:
			global_position+=motion;break
		travel=maxf(travel,0.0)
		global_position+=direction*travel
		var separation:float=(global_position-contact).dot(normal)
		if separation<RADIUS:global_position+=normal*(RADIUS-separation)
		var inbound:=velocity.dot(normal)
		var along:=velocity-normal*inbound
		if inbound<0:
			if -inbound>=MIN_BOUNCE:
				velocity=along*(1.0-IMPACT_GRIP)+normal*(-inbound*RESTITUTION)
				bounces+=1
				bounced.emit(global_position,-inbound)
				if first_impact==Vector3.INF:first_impact=global_position
			else:
				velocity=along
				if normal.y>.7:
					grounded=true
					if first_impact==Vector3.INF:first_impact=global_position
		remaining*=1.0-travel/distance
	if grounded:
		var flat:=Vector3(velocity.x,0,velocity.z)
		var slowed:=flat.move_toward(Vector3.ZERO,ROLL_DECEL*delta)
		if slowed.length()<REST_SPEED:slowed=Vector3.ZERO
		velocity=Vector3(slowed.x,velocity.y,slowed.z)
		spin=Vector3.UP.cross(slowed)/RADIUS*.5
	if spin.length_squared()>.0001:global_rotate(spin.normalized(),spin.length()*delta)

func at_rest() -> bool:
	return grounded and velocity.length_squared()<.0001
