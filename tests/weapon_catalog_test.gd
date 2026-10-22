extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	# Dynamic load makes the missing factory an explicit red assertion.
	var factory = load("res://server/weapon_catalog.gd")
	_expect(factory != null, "server catalogue factory exists")
	if factory == null:
		quit(1)
		return
	var first: Dictionary = factory.defaults()
	var second: Dictionary = factory.defaults()
	_expect(first.keys() == ["common_pistol"], "only common pistol")
	var pistol: WeaponDefinition = first["common_pistol"]
	_expect(pistol.id == "common_pistol" and pistol.damage == 34 and pistol.magazine_capacity == 6 and pistol.max_reserve_ammo == 18, "exact identity damage and ammo")
	_expect(pistol.fire_interval_msec == 400 and pistol.range_meters == 20.0 and pistol.reload_time_msec == 1200 and pistol.spread_radians == 0.0, "exact cadence range reload spread")
	_expect(WeaponRules.validate_definition(pistol).is_empty(), "default validates")
	var owned := InventoryAuthority.new(first)
	var isolated := InventoryAuthority.new(first)
	pistol.damage = -1
	first.clear()
	_expect(second["common_pistol"].damage == 34, "factory definitions and dictionaries are fresh")
	_expect(owned.definitions["common_pistol"].damage == 34, "inventory owns validated copy")
	owned.definitions["common_pistol"].damage = 99
	_expect(isolated.definitions["common_pistol"].damage == 34, "caller cannot poison another catalogue")
	var invalid := InventoryAuthority.new({"wrong_id": second["common_pistol"], "bad": WeaponDefinition.new("bad", -1)})
	_expect(invalid.definitions.is_empty(), "invalid entries and key mismatch rejected")
	if failures: quit(1); return
	print("WEAPON_CATALOG_TEST_OK checks=%d" % checks)
	quit(0)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
