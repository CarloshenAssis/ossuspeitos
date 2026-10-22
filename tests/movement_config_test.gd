extends SceneTree

var failures := 0

func _initialize() -> void:
	# Runtime assertion, so the initial red is a missing feature, not a parser error.
	if not _check(ResourceLoader.exists("res://shared/movement_config.gd"), "MovementConfig Resource must exist"):
		quit(1)
		return
	var rules = load("res://shared/movement_rules.gd")
	var config_script = load("res://shared/movement_config.gd")
	var config = config_script.new()
	_check(config.validate() == "", "defaults valid")
	_check(config.walk_speed == 5.0 and config.ground_acceleration == 18.0 and config.ground_deceleration == 18.0, "compatible defaults")
	var state := _state()
	for tick in 10:
		MovementRules.step_movement(state, Vector2.RIGHT, NetSync.TICK_SECONDS)
		_check(absf(state.velocity.x - 0.3 * (tick + 1)) < 0.000002, "golden acceleration tick %d" % tick)
		_check(absf(state.position.x - (13.5 + 0.0025 * (tick + 1) * (tick + 2))) < 0.00001, "golden position tick %d" % tick)
	state = _state()
	for tick in 60:
		MovementRules.step_movement(state, Vector2.ONE.normalized() * sqrt(1.0005), NetSync.TICK_SECONDS)
		_check(state.velocity.length() <= 5.000001, "diagonal speed cap")
		_check(state.position.y == 1.0, "planar height")
	state = _state()
	state.velocity = Vector3(5, 0, 0)
	var previous := 5.0
	for tick in 17:
		MovementRules.step_movement(state, Vector2.ZERO, NetSync.TICK_SECONDS)
		_check(state.velocity.length() <= previous, "monotonic stopping")
		previous = state.velocity.length()
	_check(previous == 0.0, "stop in 17 ticks")
	_check(absf(state.position.x - 14.1533333333) < 0.00002, "golden stopping distance")
	var stopped: Vector3 = state.position
	MovementRules.step_movement(state, Vector2.ZERO, NetSync.TICK_SECONDS)
	_check(state.position == stopped, "no drift after stopping")
	config.ground_acceleration = 6.0
	config.ground_deceleration = 30.0
	state = _state()
	_check(rules.call("step_with_config", state, Vector2.RIGHT, NetSync.TICK_SECONDS, config) == "", "valid config applied")
	_check(absf(state.velocity.x - 0.1) < 0.000001, "distinct acceleration applied")
	state.velocity = Vector3(5, 0, 0)
	rules.call("step_with_config", state, Vector2.ZERO, NetSync.TICK_SECONDS, config)
	_check(absf(state.velocity.x - 4.5) < 0.000001, "distinct deceleration applied")
	state.velocity = Vector3(5, 0, 0)
	rules.call("step_with_config", state, Vector2.LEFT, NetSync.TICK_SECONDS, config)
	_check(absf(state.velocity.x - 4.9) < 0.000001, "reversing uses acceleration, not stopping deceleration")
	config.walk_speed = 2.0
	config.ground_acceleration = 60.0
	state = _state()
	for tick in 4:
		rules.call("step_with_config", state, Vector2.RIGHT, NetSync.TICK_SECONDS, config)
	_check(absf(state.velocity.x - 2.0) < 0.000001, "configured speed applied and capped")
	for field in ["walk_speed", "ground_acceleration", "ground_deceleration"]:
		for invalid in [NAN, INF, -INF, 0.0, -1.0, 5.01 if field == "walk_speed" else 60.01]:
			var bad = config_script.new()
			bad.set(field, invalid)
			_check(not bad.validate().is_empty(), "reject %s=%s" % [field, invalid])
			state = _state()
			var before := state.duplicate(true)
			_check(not str(rules.call("step_with_config", state, Vector2.RIGHT, NetSync.TICK_SECONDS, bad)).is_empty(), "explicit rejection")
			_check(state == before, "invalid config cannot change state")
	config = config_script.new()
	config.walk_speed = 5.0
	config.ground_acceleration = 60.0
	config.ground_deceleration = 60.0
	_check(config.validate() == "", "inclusive conservative upper bounds")
	var parameters: Dictionary = config.validated_parameters()
	_check(parameters.is_read_only(), "validated snapshot is immutable")
	config.walk_speed = 1.0
	_check(parameters.walk_speed == 5.0, "validated snapshot retains copied scalars")
	_check(rules.call("step_with_config", _state(), Vector2.RIGHT, NetSync.TICK_SECONDS, null) == "movement_config_missing", "missing config rejected")
	_check(rules.call("step_with_config", _state(), Vector2.RIGHT, NetSync.TICK_SECONDS, Resource.new()) == "movement_config_missing", "wrong Resource rejected")
	_test_golden_replay()
	_test_planar_collision()
	var external = load("res://shared/default_movement_config.tres")
	external.walk_speed = 1.0
	external.ground_acceleration = 1.0
	external.ground_deceleration = NAN
	state = _state()
	MovementRules.step_movement(state, Vector2.RIGHT, NetSync.TICK_SECONDS)
	_check(absf(state.velocity.x - 0.3) < 0.000001, "external Resource mutation cannot change active defaults")
	if failures == 0:
		print("MOVEMENT_CONFIG_TEST_OK")
	quit(0 if failures == 0 else 1)

func _state() -> Dictionary:
	return {"position": Vector3(13.5, 1, 12), "velocity": Vector3.ZERO, "yaw": 0.0}

func _check(condition: bool, message: String) -> bool:
	if not condition:
		failures += 1
		push_error(message)
	return condition

# Captured from audited ac4f0ed implementation, not a second integrator.
func _test_golden_replay() -> void:
	var positions := [Vector3(13.77453, 1, 11.98697), Vector3(13.99858, 1, 11.97134), Vector3(13.7321, 1, 12.03865), Vector3(13.5212, 1, 12.22052)]
	var velocities := [Vector3(2.98998, 0, -0.208599), Vector3.ZERO, Vector3(-2.888937, 0, 0.798458), Vector3(0.068883, 0, 1.294883)]
	var state := _state()
	var direct := _state()
	var inputs := [Vector2.RIGHT, Vector2.ZERO, Vector2.LEFT, Vector2.ONE.normalized()]
	for phase in inputs.size():
		for tick in 10:
			_check(MovementRules.simulate_command(state, inputs[phase], 0.01, -0.005) == "", "replay accepts valid command")
			MovementRules.apply_look(direct, 0.01, -0.005)
			MovementRules.step_movement(direct, inputs[phase], NetSync.TICK_SECONDS)
			_check(state == direct, "authority and command replay match per tick")
		_check(state.position.distance_to(positions[phase]) < 0.00002, "frozen baseline replay position")
		_check(state.velocity.distance_to(velocities[phase]) < 0.000002, "frozen baseline replay velocity")
		_check(absf(state.yaw - 0.1 * (phase + 1)) < 1e-10, "baseline yaw")
		_check(absf(state.pitch + 0.05 * (phase + 1)) < 1e-10, "baseline pitch")
		_check(absf(state.yaw_tokens - 0.69) < 1e-10 and absf(state.pitch_tokens - 0.695) < 1e-10, "baseline look tokens")

func _test_planar_collision() -> void:
	var state := {"position": Vector3(46, 1, 0), "velocity": Vector3(5, 0, 0), "yaw": 0.0}
	MovementRules.step_movement(state, Vector2.ONE.normalized(), NetSync.TICK_SECONDS)
	_check(state.position.distance_to(Vector3(46, 1, 0.004619)) < 0.000001, "frozen wall sliding position")
	_check(state.velocity.distance_to(Vector3(0, 0, 0.277164)) < 0.000001, "blocked outward velocity and preserved slide")
