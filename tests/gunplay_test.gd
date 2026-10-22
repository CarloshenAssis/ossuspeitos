extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	_test_full_cone()
	_test_accuracy()
	_test_validation()
	_test_movement_and_lifecycle()
	_test_authority()
	_test_action_before_movement()
	if failures == 0: print("GUNPLAY_TEST_OK checks=%d" % checks)
	quit(1 if failures else 0)
func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _setup(definition: WeaponDefinition, seed_value: int = 481) -> Array:
	var inventory := InventoryAuthority.new({definition.id: definition})
	inventory.register_player(1)
	inventory.add_ground_weapon("gun", definition.id, Vector3.ZERO)
	inventory.pickup_weapon(1, "gun", true, true, Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return [inventory, CombatRules.new(inventory, rng), rng]
func _shot(pair: Array, sequence: int, time: int, velocity: Variant = Vector3.ZERO) -> Dictionary:
	return pair[1].request_shot(1, {"sequence": sequence, "origin": Vector3.ZERO, "direction": Vector3.FORWARD},
		{"alive": true, "round_active": true, "eye_position": Vector3.ZERO, "yaw": 0.0, "velocity": velocity}, time)
func _test_full_cone() -> void:
	for spread in [0.0, 0.1, PI / 2.0 - 0.00001, PI / 2.0 + 0.00001, PI]:
		var pair := _setup(WeaponDefinition.new("lab", 0, 1000, 0, 1, 20, 0, spread))
		var rng_state: int = pair[2].state
		var back_count := 0
		var mean_dot := 0.0
		for index in 512:
			var shot := _shot(pair, index, index)
			var direction: Vector3 = shot["direction"]
			var dot := Vector3.FORWARD.dot(direction)
			_expect(WeaponRules.is_finite_vector3(direction) and absf(direction.length() - 1.0) < 0.00001, "finite unit direction")
			_expect(dot >= cos(spread) - 0.00001, "declared cone bound")
			mean_dot += dot
			if dot < 0: back_count += 1
		_expect(absf(mean_dot / 512.0 - (1.0 + cos(spread)) / 2.0) < 0.06, "uniform solid angle mean")
		if spread == PI: _expect(back_count > 150, "full sphere includes rear hemisphere")
		if spread == 0: _expect(pair[2].state == rng_state, "zero cone consumes no RNG")
func _test_accuracy() -> void:
	# Dynamic fields accessed through set/get so pre-implementation tests still parse.
	var definition := WeaponDefinition.new("lab", 0, 100, 0, 400, 20, 0)
	definition.set("movement_spread_radians", 0.1)
	definition.set("bloom_per_shot_radians", 0.02)
	definition.set("max_bloom_radians", 0.05)
	definition.set("bloom_recovery_radians_per_second", 0.01)
	var pair := _setup(definition)
	var control := _setup(definition)
	var first := _shot(pair, 1, 1000)
	_expect(first["direction"] == Vector3.FORWARD, "first stationary shot precise")
	_expect(is_equal_approx(float(pair[0].get_inventory(1).get("shot_bloom_radians", -1)), 0.02), "first shot stores bloom")
	_shot(control, 1, 1000)
	var before: Dictionary = pair[0].get_inventory(1)
	var rng_before: int = pair[2].state
	for bad in ["client", Vector3(INF, 0, 0), Vector3(0, NAN, 0)]:
		_expect(not _shot(pair, 2, 1400, bad)["accepted"], "invalid velocity rejected")
	_expect(pair[0].get_inventory(1) == before and pair[2].state == rng_before, "rejection preserves all inventory and RNG")
	var next := _shot(pair, 2, 1400)
	_expect(next.get("direction") == _shot(control, 2, 1400).get("direction"), "same seed trajectory after rejection")
	_expect(is_equal_approx(float(pair[0].get_inventory(1).get("shot_bloom_radians", -1)), 0.036), "400ms exact recovery")

func _definition() -> WeaponDefinition:
	return WeaponDefinition.new("common_pistol", 0, 1000, 100, 400, 20, 1200, 0.0, 0.1, 0.02, 0.05, 0.01)

func _test_validation() -> void:
	for field in ["movement_spread_radians", "bloom_per_shot_radians", "max_bloom_radians", "bloom_recovery_radians_per_second"]:
		for invalid in [-0.1, NAN, INF, true, "0.1", null]:
			var definition := _definition()
			definition.set(field, invalid)
			_expect(WeaponRules.validate_definition(definition) == "invalid_" + field, "explicit invalid field " + field)
	var definition := _definition()
	definition.bloom_per_shot_radians = 0.06
	_expect(WeaponRules.validate_definition(definition) == "bloom_exceeds_cap", "increment exceeds cap")
	definition = _definition()
	definition.bloom_recovery_radians_per_second = 0.0
	_expect(WeaponRules.validate_definition(definition) == "bloom_requires_recovery", "positive recovery required")
	definition = _definition()
	definition.movement_spread_radians = PI / 4.0
	_expect(WeaponRules.validate_definition(definition) == "dynamic_spread_exceeds_limit", "combined envelope bounded")
	var pair := _setup(_definition())
	var owned: WeaponDefinition = pair[0].definitions["common_pistol"]
	definition = _definition()
	var inventory := InventoryAuthority.new({definition.id: definition})
	for field in ["movement_spread_radians", "bloom_per_shot_radians", "max_bloom_radians", "bloom_recovery_radians_per_second"]:
		definition.set(field, 99.0)
		_expect(inventory.definitions[definition.id].get(field) == owned.get(field), "catalogue owns " + field)
	var intent := {"sequence": 1, "origin": Vector3.ZERO, "direction": Vector3.FORWARD, "seed": 4}
	var context := {"alive": true, "round_active": true, "eye_position": Vector3.ZERO, "yaw": 0.0}
	var state: int = pair[2].state
	_expect(pair[1].request_shot(1, intent, context, 1000).get("reason") == "forbidden_field", "client seed rejected")
	_expect(pair[2].state == state and pair[0].get_inventory(1)["magazine"] == 1000, "client seed rejection pure")
	_expect(pair[1].request_shot(1, {"sequence": 1, "origin": Vector3.ZERO, "direction": Vector3.FORWARD}, context, 1000)["accepted"], "missing internal velocity remains compatible")
	_expect(WeaponRules.recovered_bloom(0.05, 5000, 0.01) == 0.0, "exact recovery boundary")

func _test_movement_and_lifecycle() -> void:
	var definition := _definition()
	definition.bloom_per_shot_radians = 0.0
	definition.max_bloom_radians = 0.0
	for fraction in [0.0, 0.5, 1.0, 2.0]:
		var pair := _setup(definition)
		var moving := _setup(definition)
		for index in 128:
			var shot := _shot(pair, index, index * 400, Vector3(MovementRules.MAX_SPEED * fraction, 123, 0))
			var angle := Vector3.FORWARD.angle_to(shot["direction"])
			_expect(angle <= 0.1 * minf(fraction, 1.0) + 0.00001, "horizontal movement cone bound")
			_expect(shot["direction"] == _shot(moving, index, index * 400, Vector3(MovementRules.MAX_SPEED * minf(fraction, 1.0), 0, 0))["direction"], "speed saturation and vertical independence")
	var pair := _setup(_definition())
	for index in 20: _shot(pair, index, index * 400)
	_expect(is_equal_approx(pair[0].get_inventory(1)["shot_bloom_radians"], 0.05), "bloom saturates at cap")
	var before: Dictionary = pair[0].get_inventory(1)
	var state: int = pair[2].state
	_expect(_shot(pair, 20, 7500).get("reason") == "time_rollback", "server rollback rejected")
	_expect(_shot(pair, 20, 7700).get("reason") == "fire_rate", "cooldown rejected")
	_expect(pair[0].get_inventory(1) == before and pair[2].state == state, "rollback and cooldown pure")
	pair[0].inventories[1]["reserve"] = 100
	_expect(pair[0].start_reload(1, 7700).is_empty(), "reload starts")
	pair[0].complete_reload(1, 8900)
	_shot(pair, 20, 12600)
	_expect(is_equal_approx(pair[0].get_inventory(1)["shot_bloom_radians"], 0.02), "reload and idle recover lazily to first shot")
	pair[0].register_player(2)
	_expect(pair[0].get_inventory(2)["shot_bloom_radians"] == 0.0, "peer isolated")
	var room := _setup(_definition())
	_expect(room[0].get_inventory(1)["shot_bloom_radians"] == 0.0, "room isolated")
	pair[0].reset_player(1)
	_expect(pair[0].get_inventory(1)["shot_bloom_radians"] == 0.0, "reset clears bloom")
	pair[0].clear_player(1)
	pair[0].register_player(1)
	_expect(pair[0].get_inventory(1)["shot_bloom_radians"] == 0.0, "rejoin clears bloom")
	pair[0].clear_session()
	_expect(pair[0].inventories.is_empty(), "session clears bloom owners")

func _authority_setup() -> Array:
	var rounds := RoundAuthority.new()
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	rounds.participants = {1: true, 2: true, 3: true, 4: true}
	rounds.alive = rounds.participants.duplicate()
	var world := AuthoritativeWorld.new()
	for peer in range(1, 5): world.add_player(peer)
	var rng := RandomNumberGenerator.new()
	rng.seed = 481
	var authority := CombatAuthority.new(rounds, world, {"common_pistol": _definition()}, rng)
	authority.begin_round(1, [1, 2, 3, 4])
	world.states[1]["position"] = Vector3(12, MovementRules.PLAYER_HEIGHT, 15.5)
	world.states[1]["yaw"] = 0.0
	authority.inventory.ground_items["weapon_0"]["position"] = world.states[1]["position"]
	authority.request_pickup(1, "weapon_0", 1, 100)
	return [authority, world]

func _test_authority() -> void:
	var pair := _authority_setup()
	var authority: CombatAuthority = pair[0]
	var world: AuthoritativeWorld = pair[1]
	var events: Array = []
	authority.shot_resolved.connect(func(event: Dictionary): events.append(event))
	world.states[1]["velocity"] = Vector3(MovementRules.MAX_SPEED, 0, 0)
	var aim_before := Vector2(world.states[1]["yaw"], world.states[1]["pitch"])
	_expect(authority.request_fire(1, 1, 1000)["accepted"], "authority moving shot accepted")
	var reference := _setup(_definition())
	var expected := _shot(reference, 1, 1000, world.states[1]["velocity"])
	var actual: Vector3 = (events[0]["end"] - events[0]["origin"]).normalized()
	_expect(actual.is_equal_approx(expected["direction"]), "authority supplies official velocity")
	_expect(Vector2(world.states[1]["yaw"], world.states[1]["pitch"]) == aim_before, "spread never writes official aim")
	var floor_hit := authority._raycast(1, Vector3(12, 1, 15), Vector3.DOWN, 20)
	_expect(is_equal_approx(floor_hit["distance"], 1.0), "floor bounds official ray")
	world.states[2]["position"] = Vector3(10, 0, 15.5)
	var wall := authority._raycast(1, Vector3(10, 1.5, 20.3), Vector3.FORWARD, 20)
	_expect(wall["peer_id"] == 0 and wall["distance"] >= 0.0 and wall["distance"] < 4, "wall before target")
	var range_hit := authority._raycast(1, Vector3(12, 1.5, 15.5), Vector3.FORWARD, 0.25)
	_expect(range_hit["distance"] == -1.0, "range endpoint limits official ray")
	authority.begin_round(2, [1, 2, 3, 4])
	_expect(authority.inventory.get_inventory(1)["shot_bloom_radians"] == 0.0, "new round clears bloom")

func _test_action_before_movement() -> void:
	var pair := _authority_setup()
	var authority: CombatAuthority = pair[0]
	var world: AuthoritativeWorld = pair[1]
	var events: Array = []
	authority.shot_resolved.connect(func(event: Dictionary): events.append(event))
	var epoch: int = world.states[1]["epoch"]
	var packet := NetSync.encode_packet(epoch, 1, [NetSync.encode_command(Vector2(1, 0), 0, 0, ["fire", 1])])
	_expect(world.receive_commands(1, packet, 1000).get("reason") == "", "move plus fire accepted into official queue")
	world.step(func(_peer): return "", func(peer, _action, _seq): authority.request_fire(peer, 1, 1000), func(_peer, _seq, _action, _reason): _expect(false, "unexpected queue rejection"))
	_expect(events.size() == 1, "queued action emits exactly once")
	if not events.is_empty():
		_expect((events[0]["end"] - events[0]["origin"]).normalized().is_equal_approx(Vector3.FORWARD), "starting movement fires with pre-movement stationary velocity")
	_expect((world.states[1]["velocity"] as Vector3).length() > 0, "movement follows the shot in same tick")
