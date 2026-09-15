extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_pickups()
	_test_ammo_and_reload()
	_test_cleanup()
	if failures:
		quit(1)
		return
	print("INVENTORY_AUTHORITY_TEST_OK checks=%d" % checks)
	quit(0)

func _authority() -> InventoryAuthority:
	return InventoryAuthority.new({"rifle": WeaponDefinition.new("rifle", 20, 6, 18, 200, 50, 1000)})

func _test_pickups() -> void:
	var authority := _authority()
	_expect(authority.register_player(1), "known player registered")
	_expect(authority.pickup_weapon(99, "item", true, true, Vector3.ZERO) == "unknown_peer", "unknown player")
	_expect(authority.add_ground_weapon("item", "rifle", Vector3.ZERO, 4, 8), "ground item added")
	_expect(authority.pickup_weapon(1, "item", true, true, Vector3.ZERO).is_empty(), "valid pickup")
	var state := authority.get_inventory(1)
	_expect(state["magazine"] == 4 and state["reserve"] == 8, "initial ammo comes from server item")
	authority.register_player(2)
	_expect(authority.pickup_weapon(2, "item", true, true, Vector3.ZERO) == "item_unavailable", "duplicate pickup")
	authority.add_ground_weapon("far", "rifle", Vector3(10, 0, 0))
	_expect(authority.pickup_weapon(2, "far", true, true, Vector3.ZERO) == "out_of_range", "out of range")
	_expect(authority.pickup_weapon(2, "far", false, true, Vector3(10, 0, 0)) == "player_dead", "dead player")
	_expect(authority.pickup_weapon(2, "far", true, false, Vector3(10, 0, 0)) == "round_not_active", "inactive round")
	_expect(authority.pickup_weapon(2, "missing", true, true, Vector3.ZERO) == "item_not_found", "missing item")
	authority.add_ground_weapon("second", "rifle", Vector3.ZERO)
	_expect(authority.pickup_weapon(1, "second", true, true, Vector3.ZERO) == "inventory_full", "inventory capacity")

func _test_ammo_and_reload() -> void:
	var authority := _authority()
	authority.register_player(1)
	authority.add_ground_weapon("item", "rifle", Vector3.ZERO, 2, 10)
	authority.pickup_weapon(1, "item", true, true, Vector3.ZERO)
	_expect(authority.start_reload(1, 1000).is_empty(), "reload starts")
	_expect(authority.start_reload(1, 1000) == "already_reloading", "duplicate reload")
	_expect(authority.complete_reload(1, 1999) == "reload_pending", "old deadline")
	_expect(authority.complete_reload(1, 2000).is_empty(), "reload completes")
	var state := authority.get_inventory(1)
	_expect(state["magazine"] == 6 and state["reserve"] == 6, "reload transfers possible amount")
	_expect(authority.start_reload(1, 3000) == "magazine_full", "full magazine")
	state = authority.inventories[1]
	state["magazine"] = 0
	state["reserve"] = 0
	_expect(authority.start_reload(1, 3000) == "reserve_empty", "empty reserve")
	_expect(authority.start_reload(1, -1) == "invalid_time", "negative reload time")
	_expect(authority.add_ground_weapon("bounded", "rifle", Vector3.ZERO, 99, 99), "bounded item")
	authority.register_player(2)
	authority.pickup_weapon(2, "bounded", true, true, Vector3.ZERO)
	state = authority.get_inventory(2)
	_expect(state["magazine"] == 6 and state["reserve"] == 18, "ammo never exceeds official limits")

func _test_cleanup() -> void:
	var authority := _authority()
	authority.register_player(1)
	authority.register_player(2)
	authority.clear_player(1)
	_expect(not authority.inventories.has(1) and authority.inventories.has(2), "player cleanup")
	authority.add_ground_weapon("item", "rifle", Vector3.ZERO)
	authority.clear_session()
	_expect(authority.inventories.is_empty() and authority.ground_items.is_empty(), "session cleanup")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
