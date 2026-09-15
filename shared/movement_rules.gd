class_name MovementRules
extends RefCounted

const MAX_SPEED := 5.0
const ACCELERATION := 18.0
const INPUT_TIMEOUT_MSEC := 300
const MAX_YAW_DELTA := 0.35
const MAX_YAW_RATE := 3.0
const MAX_COMMAND_RATE := 30.0
const COMMAND_BURST := 4.0
const MAX_SEQUENCE_ADVANCE := 64
const ARENA_HALF_EXTENT := 11.5
const PLAYER_HEIGHT := 1.0
const MOVEMENT_EPSILON := 0.001
const TEST_MOVEMENT_DISTANCE := 0.2
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-8.0, PLAYER_HEIGHT, -8.0),
	Vector3(8.0, PLAYER_HEIGHT, -8.0),
	Vector3(-8.0, PLAYER_HEIGHT, 8.0),
	Vector3(8.0, PLAYER_HEIGHT, 8.0),
	Vector3(-8.0, PLAYER_HEIGHT, 0.0),
	Vector3(8.0, PLAYER_HEIGHT, 0.0),
	Vector3(0.0, PLAYER_HEIGHT, -8.0),
	Vector3(0.0, PLAYER_HEIGHT, 8.0),
]

static func validate_input(move: Vector2, yaw_delta: float) -> String:
	if not is_finite(move.x) or not is_finite(move.y) or not is_finite(yaw_delta):
		return "non_finite"
	if move.length_squared() > 1.0 + MOVEMENT_EPSILON:
		return "move_magnitude"
	if absf(yaw_delta) > MAX_YAW_DELTA:
		return "yaw_delta"
	return ""

static func integrate(state: Dictionary, delta: float, now_msec: int) -> void:
	var move: Vector2 = state["input"]
	if now_msec - int(state["last_input_msec"]) > INPUT_TIMEOUT_MSEC:
		move = Vector2.ZERO
	var yaw := float(state["yaw"])
	var local_direction := Vector3(move.x, 0.0, move.y)
	var direction := local_direction.rotated(Vector3.UP, yaw)
	var target_velocity := direction * MAX_SPEED
	var velocity: Vector3 = state["velocity"]
	velocity = velocity.move_toward(target_velocity, ACCELERATION * delta)
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	var position: Vector3 = state["position"] + velocity * delta
	position.x = clampf(position.x, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT)
	position.z = clampf(position.z, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT)
	position.y = PLAYER_HEIGHT
	if absf(position.x) >= ARENA_HALF_EXTENT and signf(velocity.x) == signf(position.x):
		velocity.x = 0.0
	if absf(position.z) >= ARENA_HALF_EXTENT and signf(velocity.z) == signf(position.z):
		velocity.z = 0.0
	state["position"] = position
	state["velocity"] = velocity

static func snapshot_state(peer_id: int, state: Dictionary) -> Dictionary:
	return {
		"peer_id": peer_id,
		"position": state["position"],
		"velocity": state["velocity"],
		"yaw": state["yaw"],
		"spawn_index": state["spawn_index"],
	}
