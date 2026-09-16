extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_valid_and_rate()
	_test_context_and_ownership()
	_test_geometry_sequence_and_payload()
	_test_cleanup()
	if failures:
		quit(1)
		return
	print("COMBAT_RULES_TEST_OK checks=%d" % checks)
	quit(0)

func _setup(magazine: int = 3) -> Array:
	var definition := WeaponDefinition.new("rifle", 20, 6, 18, 200, 50, 1000)
	var inventory := InventoryAuthority.new({"rifle": definition})
	inventory.register_player(1)
	inventory.add_ground_weapon("item", "rifle", Vector3.ZERO, magazine, 5)
	inventory.pickup_weapon(1, "item", true, true, Vector3.ZERO)
	return [inventory, CombatRules.new(inventory)]

func _intent(sequence: int, origin: Variant = Vector3.ZERO, direction: Variant = Vector3.FORWARD) -> Dictionary:
	return {"sequence": sequence, "origin": origin, "direction": direction}

func _context(alive: bool = true, active: bool = true) -> Dictionary:
	return {"alive": alive, "round_active": active, "eye_position": Vector3.ZERO, "yaw": 0.0}

func _test_valid_and_rate() -> void:
	var pair := _setup()
	var inventory: InventoryAuthority = pair[0]
	var combat: CombatRules = pair[1]
	var result := combat.request_shot(1, _intent(1), _context(), 1000)
	_expect(result["accepted"], "valid shot")
	_expect(inventory.get_inventory(1)["magazine"] == 2, "accepted shot consumes one round")
	var before: int = inventory.get_inventory(1)["magazine"]
	_expect(combat.request_shot(1, _intent(2), _context(), 1100)["reason"] == "fire_rate", "cadence spam")
	_expect(inventory.get_inventory(1)["magazine"] == before, "rejected shot consumes nothing")
	combat.request_shot(1, _intent(2), _context(), 1200)
	combat.request_shot(1, _intent(3), _context(), 1400)
	_expect(combat.request_shot(1, _intent(4), _context(), 1600)["reason"] == "empty_magazine", "empty magazine")

func _test_context_and_ownership() -> void:
	var pair := _setup()
	var inventory: InventoryAuthority = pair[0]
	var combat: CombatRules = pair[1]
	_expect(combat.request_shot(99, _intent(1), _context(), 1000)["reason"] == "unknown_peer", "missing session")
	_expect(combat.request_shot(1, _intent(1), _context(), -1)["reason"] == "invalid_time", "negative server time")
	_expect(combat.request_shot(1, _intent(1), _context(false), 1000)["reason"] == "player_dead", "dead player")
	_expect(combat.request_shot(1, _intent(1), _context(true, false), 1000)["reason"] == "round_not_active", "inactive round")
	inventory.register_player(2)
	_expect(combat.request_shot(2, _intent(1), _context(), 1000)["reason"] == "no_equipped_weapon", "no possession")
	inventory.inventories[1]["weapon_id"] = "missing"
	_expect(combat.request_shot(1, _intent(1), _context(), 1000)["reason"] == "no_equipped_weapon", "unknown weapon")
	pair = _setup()
	inventory = pair[0]
	combat = pair[1]
	inventory.start_reload(1, 900)
	_expect(combat.request_shot(1, _intent(1), _context(), 1000)["reason"] == "reloading", "shot during reload is rejected")

func _test_geometry_sequence_and_payload() -> void:
	var pair := _setup(6)
	var inventory: InventoryAuthority = pair[0]
	var combat: CombatRules = pair[1]
	_expect(combat.request_shot(1, _intent(1, Vector3(9, 0, 0)), _context(), 1000)["reason"] == "implausible_origin", "impossible origin")
	_expect(combat.request_shot(1, _intent(1, Vector3.ZERO, "bad"), _context(), 1000)["reason"] == "invalid_direction", "invalid direction type")
	_expect(combat.request_shot(1, _intent(1, Vector3.ZERO, Vector3(2, 0, 0)), _context(), 1000)["reason"] == "direction_not_normalized", "unnormalized direction")
	_expect(combat.request_shot(1, _intent(1, Vector3.ZERO, Vector3(NAN, 0, 0)), _context(), 1000)["reason"] == "non_finite", "non-finite value")
	var accepted := combat.request_shot(1, _intent(1), _context(), 1000)
	_expect(accepted["max_distance"] == 50.0, "range is official")
	_expect(accepted["damage"] == 20.0, "damage is official")
	_expect(not accepted.has("target") and not accepted.has("victim") and not accepted.has("hit"), "output has no victim or hit")
	_expect(combat.request_shot(1, _intent(1), _context(), 1300)["reason"] == "replay", "duplicate sequence and replay")
	_expect(combat.request_shot(1, _intent(0), _context(), 1300)["reason"] == "old_sequence", "old sequence")
	_expect(combat.request_shot(1, _intent(100), _context(), 1300)["reason"] == "sequence_jump", "excessive jump")
	var ammo_before: int = inventory.get_inventory(1)["magazine"]
	var forbidden := _intent(2)
	forbidden["damage"] = 999
	_expect(combat.request_shot(1, forbidden, _context(), 1300)["reason"] == "forbidden_field", "client gameplay result rejected")
	_expect(inventory.get_inventory(1)["magazine"] == ammo_before, "all rejected shots preserve ammo")

func _test_cleanup() -> void:
	var pair := _setup()
	var inventory: InventoryAuthority = pair[0]
	var combat: CombatRules = pair[1]
	combat.clear_player(1)
	_expect(not inventory.inventories.has(1), "combat player state cleanup")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
