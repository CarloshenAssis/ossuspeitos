extends SceneTree

func _initialize() -> void:
	if MovementRules.validate_input(Vector2(99.0, 0.0), 0.0) != "move_magnitude":
		_fail("impossible movement was accepted")
		return
	if MovementRules.validate_input(Vector2(NAN, 0.0), 0.0) != "non_finite":
		_fail("non-finite movement was accepted")
		return
	var state := {
		"position": Vector3.ZERO,
		"velocity": Vector3.ZERO,
		"yaw": 0.0,
		"input": Vector2.RIGHT,
		"last_input_msec": 1000,
	}
	for step in 120:
		MovementRules.integrate(state, 1.0 / 60.0, 1000 + step * 16)
		var velocity: Vector3 = state["velocity"]
		if velocity.length() > MovementRules.MAX_SPEED + 0.001:
			_fail("authoritative speed exceeded the limit")
			return
	state["position"] = Vector3(MovementRules.MAP_MAX_X, MovementRules.PLAYER_HEIGHT, 0.0)
	state["velocity"] = Vector3(MovementRules.MAX_SPEED, 0.0, 0.0)
	state["last_input_msec"] = 3000
	MovementRules.integrate(state, 1.0 / 60.0, 3000)
	var bounded_position: Vector3 = state["position"]
	var bounded_velocity: Vector3 = state["velocity"]
	if bounded_position.x > MovementRules.MAP_MAX_X or bounded_velocity.x != 0.0:
		_fail("arena boundary did not stop outward movement")
		return
	print("MOVEMENT_RULES_TEST_OK")
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
