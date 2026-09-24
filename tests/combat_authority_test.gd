extends SceneTree

var failures := 0
var checks := 0
var rounds: RoundAuthority
var world: AuthoritativeWorld
var authority: CombatAuthority

func _initialize() -> void:
	_setup()
	_test_health_pickups_and_privacy()
	_test_fire_damage_and_validation()
	_test_raycast_and_death()
	_test_action_rate_limit_boundaries()
	_test_inactive_and_cleanup()
	if failures: quit(1); return
	print("COMBAT_AUTHORITY_TEST_OK checks=%d" % checks)
	quit(0)

func _setup() -> void:
	rounds = RoundAuthority.new()
	world = AuthoritativeWorld.new()
	for peer_id in range(1, 5):
		world.add_player(peer_id)
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	rounds.participants = {1: true, 2: true, 3: true, 4: true}
	rounds.alive = {1: true, 2: true, 3: true, 4: true}
	rounds._roles = {1: Role.ASSASSIN, 2: Role.DETECTIVE, 3: Role.VICTIM, 4: Role.VICTIM}
	authority = CombatAuthority.new(rounds, world)
	authority.begin_round(1, [1, 2, 3, 4])

func _arm(peer_id: int, position: Vector3, item := "weapon_0") -> void:
	world.states[peer_id]["position"] = position
	authority.inventory.ground_items[item]["position"] = position
	_expect(authority.request_pickup(peer_id, item, 1, 100)["accepted"], "pickup in range")

func _test_health_pickups_and_privacy() -> void:
	_expect(authority.health[1] == 100, "initial health is 100")
	_expect(authority.public_pickups().size() == 8, "four weapons and four ammo boxes")
	for pickup in authority.public_pickups():
		_expect(pickup.keys().size() == 5 and not pickup.has("weapon_id") and not pickup.has("reserve"), "pickup snapshot allowlist")
	world.states[1]["position"] = Vector3(100, 0, 100)
	_expect(authority.request_pickup(1, "weapon_0", 1, 100)["reason"] == "out_of_range", "pickup out of range")
	world.states[1]["position"] = ArenaRules.PICKUP_POSITIONS[0]
	_expect(authority.request_pickup(1, "weapon_0", 2, 200)["accepted"], "valid pickup")
	world.states[2]["position"] = ArenaRules.PICKUP_POSITIONS[0]
	_expect(authority.request_pickup(2, "weapon_0", 1, 200)["reason"] == "item_unavailable", "pickup contention first wins")
	var public_text := str(authority.public_pickups()).to_lower()
	_expect(not public_text.contains("role") and not public_text.contains("magazine"), "public snapshot keeps roles and inventory private")
	_expect(authority.request_pickup(2, [], 2, 300)["reason"] == "invalid_pickup", "invalid pickup type is safe")

func _test_fire_damage_and_validation() -> void:
	# Fresh unobstructed lane across the mansion hall (x = 12, clear of columns
	# and pedestal), shooting north.
	world.states[1]["position"] = Vector3(12, 0, 15.5)
	world.states[1]["yaw"] = 0.0
	world.states[2]["position"] = Vector3(12, 0, 10.5)
	var eye: Vector3 = world.states[1]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
	_expect(authority.request_fire(1, 1, eye + Vector3(2, 0, 0), Vector3.FORWARD, 1000)["reason"] == "implausible_origin", "impossible origin")
	_expect(authority.request_fire(1, 1, eye, "bad", 1000)["reason"] == "invalid_direction", "invalid direction")
	_expect(authority.request_fire(1, 1, eye, Vector3.BACK, 1000)["reason"] == "direction_yaw_divergence", "yaw divergence")
	var first := authority.request_fire(1, 1, eye, Vector3.FORWARD, 1000)
	_expect(first["accepted"], "valid official shot")
	_expect(authority.health[2] == 66, "official 34 damage applied")
	_expect(authority.request_fire(1, 1, eye, Vector3.FORWARD, 1500)["reason"] == "replay", "sequence replay rejected")
	_expect(authority.health[2] == 66, "damage exactly once")
	var inventory_before_rate_limit := authority.inventory.get_inventory(1)
	var rate_result := authority.request_fire(1, 2, eye, Vector3.FORWARD, 1050)
	_expect(rate_result.get("reason", "accepted") == "rate_limited",
		"action rate limit action=fire previous_timestamp=1000 current_timestamp=1050 interval=%d previous_sequence=1 current_sequence=2 expected=rate_limited actual=%s" % [
			CombatAuthority.ACTION_INTERVAL_MSEC, str(rate_result.get("reason", "accepted"))])
	_expect(authority.inventory.get_inventory(1) == inventory_before_rate_limit, "rate-limited action preserves inventory")
	_expect(authority.request_fire(1, 2, eye, Vector3.FORWARD, 1300)["reason"] == "fire_rate", "weapon cadence")
	_expect(authority.request_fire(1, {"damage": 999}, eye, Vector3.FORWARD, 1500)["reason"] == "invalid_sequence", "client cannot choose damage or victim")
	authority.inventory.inventories[1]["magazine"] = 0
	_expect(authority.request_fire(1, 2, eye, Vector3.FORWARD, 1500)["reason"] == "empty_magazine", "empty magazine")
	authority.inventory.inventories[1]["reserve"] = 6
	_expect(authority.request_reload(1, 1, 1600)["accepted"], "reload starts")
	authority.tick(2800)
	_expect(authority.private_state(1)["magazine"] == 6 and not authority.private_state(1)["reloading"], "reload completes authoritatively")

func _test_raycast_and_death() -> void:
	# Self is ignored; nearest target takes the shot, then dead target takes no more.
	world.states[1]["position"] = Vector3(12, 0, 16)
	world.states[1]["yaw"] = 0.0
	world.states[2]["position"] = Vector3(12, 0, 13)
	world.states[3]["position"] = Vector3(12, 0, 10)
	authority.health[2] = 34
	authority.inventory.inventories[1]["magazine"] = 6
	authority.inventory.inventories[1]["last_shot_msec"] = -1
	var eye: Vector3 = world.states[1]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
	_expect(authority.request_fire(1, 2, eye, Vector3.FORWARD, 3000)["accepted"], "raycast shot accepted")
	_expect(authority.health[2] == 0 and not rounds.is_alive(2), "nearest target eliminated through RoundAuthority")
	var dead_health: int = authority.health[2]
	# Ray now passes dead player and reaches the next live player.
	_expect(authority.request_fire(1, 3, eye, Vector3.FORWARD, 3400)["accepted"], "dead hitbox ignored")
	_expect(authority.health[2] == dead_health and authority.health[3] == 66, "dead target takes no new damage")
	# The wall between the dining room and the hall wins before a target behind it.
	world.states[1]["position"] = Vector3(10, 0, 20.3)
	world.states[3]["position"] = Vector3(10, 0, 15.5)
	eye = world.states[1]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
	var before: int = authority.health[3]
	authority.request_fire(1, 4, eye, Vector3.FORWARD, 3800)
	_expect(authority.health[3] == before, "wall blocks shot")
	rounds.alive[1] = false
	_expect(authority.request_fire(1, 5, eye, Vector3.FORWARD, 4200)["reason"] == "player_dead", "dead player cannot fire")
	_expect(authority.request_pickup(1, "ammo_0", 3, 4200)["reason"] == "player_dead", "dead player cannot collect")
	_expect(authority.request_reload(1, 2, 4200)["reason"] == "player_dead", "dead player cannot reload")

func _test_action_rate_limit_boundaries() -> void:
	var peer_id := 4
	var start := 6000
	var interval := CombatAuthority.ACTION_INTERVAL_MSEC
	_expect_gate(peer_id, "pickup", 1, start, "", "first action")
	authority._commit_sequence(peer_id, "pickup", 1, start)
	_expect_gate(peer_id, "pickup", 2, start, "rate_limited", "immediate second action")
	_expect_gate(peer_id, "pickup", 2, start + interval - 1, "rate_limited", "one millisecond before boundary")
	_expect_gate(peer_id, "pickup", 2, start + interval, "", "exact boundary")
	authority._commit_sequence(peer_id, "pickup", 2, start + interval)
	_expect_gate(peer_id, "pickup", 3, start + interval * 2 + 1, "", "one millisecond after boundary")
	_expect_gate(peer_id, "pickup", 3, start + interval - 1, "rate_limited", "clock rollback")
	_expect_gate(peer_id, "reload", 1, start + interval, "", "different action at same timestamp")
	_expect_gate(3, "pickup", 1, start + interval, "", "different peer at same timestamp")
	authority.clear_player(peer_id)
	_expect(not authority._sequences.has(peer_id) and not authority._last_action_msec.has(peer_id), "session removal clears action limits")
	rounds.round_id = 2
	rounds.alive[peer_id] = true
	authority.begin_round(2, [1, 2, 3, 4])
	_expect_gate(peer_id, "pickup", 1, start, "", "new round clears action limits")

func _expect_gate(peer_id: int, action: String, sequence: int, now_msec: int, expected: String, label: String) -> void:
	var previous_sequence := int((authority._sequences.get(peer_id, {}) as Dictionary).get(action, -1))
	var previous_timestamp := int((authority._last_action_msec.get(peer_id, {}) as Dictionary).get(action, -1))
	var actual := authority._gate(peer_id, action, sequence, now_msec)
	_expect(actual == expected,
		"%s action=%s peer=%d previous_timestamp=%d current_timestamp=%d interval=%d previous_sequence=%d current_sequence=%d expected=%s actual=%s" % [
			label, action, peer_id, previous_timestamp, now_msec, CombatAuthority.ACTION_INTERVAL_MSEC,
			previous_sequence, sequence, _safe_reason(expected), _safe_reason(actual)])

func _safe_reason(reason: String) -> String:
	return "accepted" if reason.is_empty() else reason

func _test_inactive_and_cleanup() -> void:
	rounds.state = RoundState.ENDED
	_expect(authority.request_pickup(4, "weapon_3", 1, 5000)["reason"] == "round_not_active", "inactive round rejects pickup")
	_expect(authority.request_fire(4, 1, Vector3.ZERO, Vector3.FORWARD, 5000)["reason"] == "round_not_active", "inactive round rejects fire")
	authority.clear_round()
	_expect(authority.health.is_empty() and authority.public_pickups().is_empty() and authority.inventory.inventories.is_empty(), "round cleanup removes health inventory pickups")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
