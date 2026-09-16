class_name WeaponRules
extends RefCounted

const MAX_DAMAGE := 1_000_000.0
const MAX_CAPACITY := 10_000
const MAX_FIRE_INTERVAL_MSEC := 3_600_000
const MAX_RANGE_METERS := 100_000.0
const MAX_RELOAD_MSEC := 3_600_000
const MAX_SPREAD_RADIANS := PI
const DIRECTION_TOLERANCE := 0.01
const ORIGIN_TOLERANCE_METERS := 0.35
const MAX_AIM_YAW_RADIANS := deg_to_rad(70.0)

static func validate_definition(definition: Variant) -> String:
	if not definition is WeaponDefinition:
		return "invalid_definition"
	if not is_valid_identifier(definition.id):
		return "invalid_id"
	if not is_finite_number(definition.damage) or float(definition.damage) < 0.0 or float(definition.damage) > MAX_DAMAGE:
		return "invalid_damage"
	if typeof(definition.magazine_capacity) != TYPE_INT or definition.magazine_capacity < 0 or definition.magazine_capacity > MAX_CAPACITY:
		return "invalid_capacity"
	if typeof(definition.max_reserve_ammo) != TYPE_INT or definition.max_reserve_ammo < 0 or definition.max_reserve_ammo > MAX_CAPACITY:
		return "invalid_reserve"
	if typeof(definition.fire_interval_msec) != TYPE_INT or definition.fire_interval_msec <= 0 or definition.fire_interval_msec > MAX_FIRE_INTERVAL_MSEC:
		return "invalid_fire_rate"
	if not is_finite_number(definition.range_meters) or float(definition.range_meters) <= 0.0 or float(definition.range_meters) > MAX_RANGE_METERS:
		return "invalid_range"
	if typeof(definition.reload_time_msec) != TYPE_INT or definition.reload_time_msec < 0 or definition.reload_time_msec > MAX_RELOAD_MSEC:
		return "invalid_reload"
	if not is_finite_number(definition.spread_radians) or float(definition.spread_radians) < 0.0 or float(definition.spread_radians) > MAX_SPREAD_RADIANS:
		return "invalid_spread"
	return ""

static func is_valid_identifier(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identifier: String = value
	if identifier.is_empty() or identifier.length() > 64:
		return false
	for index in identifier.length():
		var code := identifier.unicode_at(index)
		var valid := code >= 97 and code <= 122
		valid = valid or (code >= 48 and code <= 57) or code == 95 or code == 45
		if not valid:
			return false
	return true

static func is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

static func clamp_ammo(value: Variant, maximum: int) -> int:
	if typeof(value) != TYPE_INT or maximum < 0:
		return 0
	return clampi(int(value), 0, maximum)

static func reload_transfer(magazine: Variant, reserve: Variant, capacity: int) -> int:
	if typeof(magazine) != TYPE_INT or typeof(reserve) != TYPE_INT or capacity < 0:
		return 0
	return mini(maxi(0, capacity - int(magazine)), maxi(0, int(reserve)))

static func validate_origin(claimed: Variant, official: Variant, tolerance: float = ORIGIN_TOLERANCE_METERS) -> String:
	if typeof(claimed) != TYPE_VECTOR3 or typeof(official) != TYPE_VECTOR3:
		return "invalid_origin"
	if not is_finite_vector3(claimed) or not is_finite_vector3(official) or not is_finite(tolerance) or tolerance < 0.0:
		return "non_finite"
	if claimed.distance_to(official) > tolerance:
		return "implausible_origin"
	return ""

static func validate_direction(direction: Variant) -> String:
	if typeof(direction) != TYPE_VECTOR3:
		return "invalid_direction"
	if not is_finite_vector3(direction):
		return "non_finite"
	if absf(direction.length_squared() - 1.0) > DIRECTION_TOLERANCE:
		return "direction_not_normalized"
	return ""

static func validate_direction_for_yaw(direction: Variant, official_yaw: Variant) -> String:
	var reason := validate_direction(direction)
	if not reason.is_empty():
		return reason
	if not is_finite_number(official_yaw):
		return "invalid_yaw"
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() < 0.01:
		return "direction_vertical"
	var official_forward := Vector3.FORWARD.rotated(Vector3.UP, float(official_yaw))
	if horizontal.normalized().dot(official_forward) < cos(MAX_AIM_YAW_RADIANS):
		return "direction_yaw_divergence"
	return ""

static func is_finite_vector3(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
