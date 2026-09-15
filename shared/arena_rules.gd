class_name ArenaRules
extends RefCounted

## The server and client use the same deterministic arena description. These
## boxes are authoritative bullet blockers; rendering them is presentation only.
const EYE_HEIGHT := 0.7
const PLAYER_HIT_RADIUS := 0.45
const PLAYER_HIT_HEIGHT := 2.0
const PICKUP_POSITIONS := [
	Vector3(-8.0, 0.25, -8.0), Vector3(8.0, 0.25, -8.0),
	Vector3(-8.0, 0.25, 8.0), Vector3(8.0, 0.25, 8.0),
	Vector3(-5.0, 0.25, 0.0), Vector3(5.0, 0.25, 0.0),
	Vector3(0.0, 0.25, -8.0), Vector3(0.0, 0.25, 8.0),
]
const BLOCKERS := [
	{"center": Vector3(-12.25, 1.5, 0.0), "size": Vector3(0.5, 3.5, 25.0)},
	{"center": Vector3(12.25, 1.5, 0.0), "size": Vector3(0.5, 3.5, 25.0)},
	{"center": Vector3(0.0, 1.5, -12.25), "size": Vector3(25.0, 3.5, 0.5)},
	{"center": Vector3(0.0, 1.5, 12.25), "size": Vector3(25.0, 3.5, 0.5)},
	{"center": Vector3(0.0, 1.0, 0.0), "size": Vector3(1.0, 2.0, 7.0)},
]

static func ray_aabb(origin: Vector3, direction: Vector3, max_distance: float, center: Vector3, size: Vector3) -> float:
	var minimum := center - size * 0.5
	var maximum := center + size * 0.5
	var near := 0.0
	var far := max_distance
	for axis in 3:
		var component := direction[axis]
		if absf(component) < 0.000001:
			if origin[axis] < minimum[axis] or origin[axis] > maximum[axis]:
				return -1.0
			continue
		var first := (minimum[axis] - origin[axis]) / component
		var second := (maximum[axis] - origin[axis]) / component
		if first > second:
			var swap := first
			first = second
			second = swap
		near = maxf(near, first)
		far = minf(far, second)
		if near > far:
			return -1.0
	return near if near <= max_distance else -1.0

static func ray_player(origin: Vector3, direction: Vector3, max_distance: float, position: Vector3) -> float:
	# A conservative authoritative body AABB; no headshot distinction.
	return ray_aabb(origin, direction, max_distance,
		position + Vector3.UP * PLAYER_HIT_HEIGHT * 0.5,
		Vector3(PLAYER_HIT_RADIUS * 2.0, PLAYER_HIT_HEIGHT, PLAYER_HIT_RADIUS * 2.0))
