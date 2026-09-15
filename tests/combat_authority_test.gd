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
	# Fresh unobstructed lane on the east side of the central wall.
	world.states[1]["position"] = Vector3(6, 0, 6)
	world.states[1]["yaw"] = 0.0
	world.states[2]["position"] = Vector3(6, 0, 1)
	var eye: Vector3 = world.states[1]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
	_expect(authority.request_fire(1, 1, eye + Vector3(2, 0, 0), Vector3.FORWARD, 1000)["reason"] == "implausible_origin", "impossible origin")
	_expect(authority.request_fire(1, 1, eye, "bad", 1000)["reason"] == "invalid_direction", "invalid direction")
	_expect(authority.request_fire(1, 1, eye, Vector3.BACK, 1000)["reason"] == "direction_yaw_divergence", "yaw divergence")
	var first := authority.request_fire(1, 1, eye, Vector3.FORWARD, 1000)
	_expect(first["accepted"], "valid official shot")
	_expect(authority.health[2] == 66, "official 34 damage applied")
	_expect(authority.request_fire(1, 1, eye, Vector3.FORWARD, 1500)["reason"] == "replay", "sequence replay rejected")
	_expect(authority.health[2] == 66, "damage exactly once")
	_expect(authority.request_fire(1, 2, eye, Vector3.FORWARD, 1100)["reason"] == "rate_limited", "action rate limit")
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
	world.states[1]["position"] = Vector3(6, 0, 8)
	world.states[1]["yaw"] = 0.0
	world.states[2]["position"] = Vector3(6, 0, 5)
	world.states[3]["position"] = Vector3(6, 0, 2)
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
	# Central blocker wins before a target behind it.
	world.states[1]["position"] = Vector3(0, 0, 8)
	world.states[3]["position"] = Vector3(0, 0, -5)
	eye = world.states[1]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
	var before: int = authority.health[3]
	authority.request_fire(1, 4, eye, Vector3.FORWARD, 3800)
	_expect(authority.health[3] == before, "wall blocks shot")
	rounds.alive[1] = false
	_expect(authority.request_fire(1, 5, eye, Vector3.FORWARD, 4200)["reason"] == "player_dead", "dead player cannot fire")
	_expect(authority.request_pickup(1, "ammo_0", 3, 4200)["reason"] == "player_dead", "dead player cannot collect")
	_expect(authority.request_reload(1, 2, 4200)["reason"] == "player_dead", "dead player cannot reload")

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
