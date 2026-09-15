extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	var valid := WeaponDefinition.new("rifle_1", 25.0, 12, 48, 150, 80.0, 1200, 0.02)
	_expect(WeaponRules.validate_definition(valid).is_empty(), "valid definition")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("", 1, 1, 1, 1, 1, 1)) == "invalid_id", "empty identifier")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("Bad id", 1, 1, 1, 1, 1, 1)) == "invalid_id", "invalid identifier")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", -1, 1, 1, 1, 1, 1)) == "invalid_damage", "negative damage")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", WeaponRules.MAX_DAMAGE + 1.0, 1, 1, 1, 1, 1)) == "invalid_damage", "impossible damage")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", 1, -1, 1, 1, 1, 1)) == "invalid_capacity", "negative capacity")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", 1, 1, -1, 1, 1, 1)) == "invalid_reserve", "negative reserve capacity")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", 1, 1, 1, 0, 1, 1)) == "invalid_fire_rate", "invalid cadence")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", 1, 1, 1, 1, 0, 1)) == "invalid_range", "invalid range")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", 1, 1, 1, 1, 1, -1)) == "invalid_reload", "invalid reload")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", NAN, 1, 1, 1, 1, 1)) == "invalid_damage", "NaN rejected")
	_expect(WeaponRules.validate_definition(WeaponDefinition.new("gun", 1, 1, 1, 1, INF, 1)) == "invalid_range", "infinity rejected")
	_expect(WeaponRules.clamp_ammo(-2, 10) == 0 and WeaponRules.clamp_ammo(20, 10) == 10, "ammo clamps safely")
	_expect(WeaponRules.reload_transfer(8, 20, 10) == 2, "reload calculation")
	_expect(WeaponRules.validate_direction(Vector3.FORWARD).is_empty(), "valid direction")
	_expect(WeaponRules.validate_direction(Vector3(2, 0, 0)) == "direction_not_normalized", "unnormalized direction")
	_expect(WeaponRules.validate_direction(Vector3(NAN, 0, 0)) == "non_finite", "non-finite direction")
	_expect(WeaponRules.validate_direction("forward") == "invalid_direction", "wrong direction type")
	_expect(WeaponRules.validate_origin(Vector3(1, 0, 0), Vector3.ZERO).is_empty(), "plausible origin")
	_expect(WeaponRules.validate_origin(Vector3(5, 0, 0), Vector3.ZERO) == "implausible_origin", "impossible origin")
	_expect(WeaponRules.validate_origin(Vector3(INF, 0, 0), Vector3.ZERO) == "non_finite", "non-finite origin")
	_expect(WeaponRules.validate_direction_for_yaw(Vector3.FORWARD, 0.0).is_empty(), "direction follows official yaw")
	_expect(WeaponRules.validate_direction_for_yaw(Vector3.BACK, 0.0) == "direction_yaw_divergence", "direction diverging from yaw")
	_finish()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _finish() -> void:
	if failures:
		quit(1)
		return
	print("WEAPON_RULES_TEST_OK checks=%d" % checks)
	quit(0)
