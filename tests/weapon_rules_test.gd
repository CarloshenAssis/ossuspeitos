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
	_test_origin_boundaries()
	_expect(WeaponRules.validate_direction_for_yaw(Vector3.FORWARD, 0.0).is_empty(), "direction follows official yaw")
	_expect(WeaponRules.validate_direction_for_yaw(Vector3.BACK, 0.0) == "direction_yaw_divergence", "direction diverging from yaw")
	_finish()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _test_origin_boundaries() -> void:
	var official_eye := Vector3(4.0, 1.7, -3.0)
	var tolerance := WeaponRules.ORIGIN_TOLERANCE_METERS
	_expect_origin("exact official eye", official_eye, official_eye, tolerance, "")
	_expect_origin("inside tolerance", official_eye + Vector3(tolerance * 0.5, 0.0, 0.0), official_eye, tolerance, "")
	_expect_origin("exact tolerance", official_eye + Vector3(tolerance, 0.0, 0.0), official_eye, tolerance, "")
	_expect_origin("outside tolerance", official_eye + Vector3(tolerance + 0.001, 0.0, 0.0), official_eye, tolerance, "implausible_origin")
	_expect_origin("vertical-only tolerance", official_eye + Vector3(0.0, tolerance * 0.5, 0.0), official_eye, tolerance, "")
	_expect_origin("NaN origin", Vector3(NAN, official_eye.y, official_eye.z), official_eye, tolerance, "non_finite")
	_expect_origin("infinite origin", Vector3(INF, official_eye.y, official_eye.z), official_eye, tolerance, "non_finite")

func _expect_origin(label: String, claimed: Vector3, official: Vector3, tolerance: float, expected: String) -> void:
	var actual := WeaponRules.validate_origin(claimed, official, tolerance)
	var distance := claimed.distance_to(official) if WeaponRules.is_finite_vector3(claimed) else INF
	_expect(actual == expected,
		"%s expected=%s actual=%s distance=%.6f tolerance=%.6f claimed=%s official=%s" % [
			label, _safe_result(expected), _safe_result(actual), distance, tolerance,
			_safe_vector(claimed), _safe_vector(official)])

func _safe_result(value: String) -> String:
	return "accepted" if value.is_empty() else value

func _safe_vector(value: Vector3) -> String:
	return "(%.6f,%.6f,%.6f)" % [value.x, value.y, value.z]

func _finish() -> void:
	if failures:
		quit(1)
		return
	print("WEAPON_RULES_TEST_OK checks=%d" % checks)
	quit(0)
