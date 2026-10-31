class_name RagdollDriver
extends Node

# Runs one corpse's physics from the moment of death: the joints start stiff (the
# soldier is still holding his pose for a heartbeat) and go slack as the damping fades
# to each body's resting value, which makes the legs buckle first and the trunk follow.
# The corpse freezes as soon as every body has been quiet for SETTLED_FOR, or at
# SoldierFactory.RAGDOLL_SETTLE at the latest. peak_speed and final_speed are kept
# for the tests.

const STIFF := 16.0
const STIFF_FOR := .12
const SLACK_BY := .5
const QUIET_SPEED := .12
const QUIET_TURN := 1.0
const SETTLED_FOR := .3
const MIN_RUN := .5

var simulator: PhysicalBoneSimulator3D
var bodies: Array[PhysicalBone3D] = []
var resting: Dictionary = {}
var age := 0.0
var quiet := 0.0
var peak_speed := 0.0
var final_speed := 0.0
var settled_at := -1.0

func start(source: PhysicalBoneSimulator3D) -> void:
	simulator = source
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			bodies.append(child)
			resting[child] = child.angular_damp

func _physics_process(delta: float) -> void:
	if not is_instance_valid(simulator) or settled_at >= 0:
		return
	age += delta
	var slack := smoothstep(STIFF_FOR, SLACK_BY, age)
	var fastest := 0.0
	var spinning := 0.0
	for body in bodies:
		body.angular_damp = lerpf(maxf(STIFF, resting[body]), resting[body], slack)
		fastest = maxf(fastest, body.linear_velocity.length())
		spinning = maxf(spinning, body.angular_velocity.length())
	peak_speed = maxf(peak_speed, fastest)
	final_speed = fastest
	quiet = quiet + delta if age > MIN_RUN and fastest < QUIET_SPEED and spinning < QUIET_TURN else 0.0
	if quiet >= SETTLED_FOR or age >= SoldierFactory.RAGDOLL_SETTLE:
		settled_at = age
		SoldierFactory.freeze(weakref(get_parent()))
