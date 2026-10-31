class_name ThrowTimeline
extends RefCounted

# One overarm grenade throw, shared by the simulation, the bots and both animations.
# Pin pull and pull-back take PULL seconds; holding the key keeps the hand cocked
# there (the frag fuse keeps burning); on release the arm whips through in
# RELEASE-PULL seconds, the grenade leaves the hand at RELEASE and the soldier is
# ready again at TOTAL.
const PULL := .25
const RELEASE := .45
const TOTAL := .85
const SPEED := 19.5
const LOFT := deg_to_rad(9.0)
const MAX_PITCH := deg_to_rad(70.0)
const GRAVITY := 9.8
const FRAG_FUSE := 2.5
const SMOKE_FUSE := 1.0
const MAX_COOK := 2.0
const INHERIT := .6
# Where the grenade leaves the hand, relative to the eye along the aim basis (right, up, forward).
const HAND := Vector3(.2, .12, -.45)

# Position on the animation timeline in seconds, or -1 when the soldier is not throwing.
static func seconds(actor: Object, now: float) -> float:
	if actor.action_kind != "throw" or now >= actor.action_until:
		return -1.0
	if actor.throw_holding:
		return clampf(now - actor.throw_started, 0.0, PULL)
	if actor.throw_at < 0:
		return -1.0
	return clampf(RELEASE - (actor.throw_at - now), 0.0, TOTAL)

# Launch elevation for an aim pitch: the aim plus a loft, as an overarm throw does.
static func launch_pitch(aim_pitch: float) -> float:
	return clampf(aim_pitch + LOFT, -MAX_PITCH, MAX_PITCH)

# Where a descent through `rise` (target height minus hand height) lands, for a launch elevation.
static func landing_distance(elevation: float, rise: float) -> float:
	var vertical := SPEED * sin(elevation)
	var disc := vertical * vertical - 2.0 * GRAVITY * rise
	if disc < 0:
		return 0.0
	return SPEED * cos(elevation) * (vertical + sqrt(disc)) / GRAVITY

# Flattest elevation that lands `distance` away on a target `rise` above the hand
# (the high arc is never wanted); falls back to the longest reach.
static func elevation_for(distance: float, rise: float) -> float:
	var best := deg_to_rad(45.0)
	var reach := 0.0
	for degrees in range(-10, 61):
		var landed := landing_distance(deg_to_rad(degrees), rise)
		if landed > reach:
			reach = landed
		if landed >= distance:
			return deg_to_rad(degrees)
		if landed < reach - 1.0:
			break
	return best

# Hermite path through [time, Vector3] keys with finite-difference tangents, so the
# hand keeps its speed through a key (the whip does not stop at the release point).
static func path(keys: Array, time: float) -> Vector3:
	if time <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if time <= keys[i][0]:
			var t0: float = keys[i - 1][0]
			var t1: float = keys[i][0]
			var span := t1 - t0
			var u := (time - t0) / span
			var p0: Vector3 = keys[i - 1][1]
			var p1: Vector3 = keys[i][1]
			var m0 := Vector3.ZERO
			if i > 1:
				m0 = (p1 - Vector3(keys[i - 2][1])) / (t1 - float(keys[i - 2][0])) * span
			var m1 := Vector3.ZERO
			if i < keys.size() - 1:
				m1 = (Vector3(keys[i + 1][1]) - p0) / (float(keys[i + 1][0]) - t0) * span
			var u2 := u * u
			var u3 := u2 * u
			return p0 * (2 * u3 - 3 * u2 + 1) + m0 * (u3 - 2 * u2 + u) + p1 * (-2 * u3 + 3 * u2) + m1 * (u3 - u2)
	return keys[keys.size() - 1][1]

# Share of the throw during which the weapon is out of the way (0 to 1).
static func lowered(time: float) -> float:
	if time < 0:
		return 0.0
	return smoothstep(0.0, .2, time) * (1.0 - smoothstep(.6, TOTAL, time))
