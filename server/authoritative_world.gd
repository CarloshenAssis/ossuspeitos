class_name AuthoritativeWorld
extends RefCounted

var states: Dictionary = {}
var occupied_spawns: Dictionary = {}

func add_player(peer_id: int) -> Dictionary:
	var spawn_index := _first_free_spawn()
	if spawn_index < 0:
		return {}
	occupied_spawns[spawn_index] = peer_id
	var spawn := MovementRules.SPAWN_POINTS[spawn_index]
	var state := {
		"position": spawn,
		"spawn_position": spawn,
		"velocity": Vector3.ZERO,
		"yaw": MovementRules.spawn_yaw(spawn),
		"input": Vector2.ZERO,
		"last_sequence": -1,
		"last_input_msec": 0,
		"last_command_msec": 0,
		"command_tokens": MovementRules.COMMAND_BURST,
		"yaw_tokens": MovementRules.MAX_YAW_DELTA * 2.0,
		"spawn_index": spawn_index,
		"movement_logged": false,
	}
	states[peer_id] = state
	return state

func remove_player(peer_id: int) -> void:
	if not states.has(peer_id):
		return
	occupied_spawns.erase(int(states[peer_id]["spawn_index"]))
	states.erase(peer_id)

func clear() -> void:
	states.clear()
	occupied_spawns.clear()

func accept_input(peer_id: int, sequence: int, move: Vector2, yaw_delta: float, now_msec: int) -> String:
	if not states.has(peer_id):
		return "unknown_peer"
	var state: Dictionary = states[peer_id]
	if sequence <= int(state["last_sequence"]):
		return "stale_sequence"
	if sequence - int(state["last_sequence"]) > MovementRules.MAX_SEQUENCE_ADVANCE:
		return "sequence_jump"
	var previous_msec := int(state["last_command_msec"])
	var elapsed_seconds := minf(maxf(float(now_msec - previous_msec) / 1000.0, 0.0), 1.0) if previous_msec > 0 else 1.0
	state["last_command_msec"] = now_msec
	state["command_tokens"] = minf(MovementRules.COMMAND_BURST, float(state["command_tokens"]) + elapsed_seconds * MovementRules.MAX_COMMAND_RATE)
	state["yaw_tokens"] = minf(MovementRules.MAX_YAW_DELTA * 2.0, float(state["yaw_tokens"]) + elapsed_seconds * MovementRules.MAX_YAW_RATE)
	if float(state["command_tokens"]) < 1.0:
		return "input_rate"
	state["command_tokens"] = float(state["command_tokens"]) - 1.0
	var reason := MovementRules.validate_input(move, yaw_delta)
	if not reason.is_empty():
		state["last_sequence"] = sequence
		return reason
	if absf(yaw_delta) > float(state["yaw_tokens"]):
		state["last_sequence"] = sequence
		return "yaw_rate"
	state["yaw_tokens"] = float(state["yaw_tokens"]) - absf(yaw_delta)
	state["last_sequence"] = sequence
	state["input"] = move
	state["yaw"] = wrapf(float(state["yaw"]) + yaw_delta, -PI, PI)
	state["last_input_msec"] = now_msec
	return ""

func step(delta: float, now_msec: int) -> void:
	for state in states.values():
		MovementRules.integrate(state, delta, now_msec)

func snapshot() -> Array:
	var result: Array = []
	for peer_id in states:
		result.append(MovementRules.snapshot_state(int(peer_id), states[peer_id]))
	return result

func has_moved(peer_id: int) -> bool:
	if not states.has(peer_id):
		return false
	var state: Dictionary = states[peer_id]
	return (state["position"] as Vector3).distance_to(state["spawn_position"]) >= MovementRules.TEST_MOVEMENT_DISTANCE

func all_positions_distinct(peer_ids: Array) -> bool:
	var positions: Dictionary = {}
	for peer_id in peer_ids:
		if not states.has(peer_id):
			return false
		var position: Vector3 = states[peer_id]["position"]
		var key := "%0.3f,%0.3f" % [position.x, position.z]
		positions[key] = true
	return positions.size() == peer_ids.size()

func _first_free_spawn() -> int:
	for index in MovementRules.SPAWN_POINTS.size():
		if not occupied_spawns.has(index):
			return index
	return -1
