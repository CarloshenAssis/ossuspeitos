extends SceneTree

const SalaoMap = preload("res://shared/nocturna_salao_map.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_expect(SalaoMap.enabled, "Nocturna variant is enabled")
	for x in [5.0, 11.0]:
		_check_route(Vector2(x, 7), Vector2(x, 4), Vector2(x, 1))
		_expect(SalaoMap.floor_height(x, 2.0) == 3.5, "hall ramp meets gallery at full height")
	_check_route(Vector2(17.5, 6), Vector2(21.25, 6), Vector2(25.5, 6))
	_expect(SalaoMap.floor_height(24.5, 6.0) == 3.5, "service ramp meets landing at full height")

	var side := MovementRules.resolve_step(_at(Vector2(3, 4), 0.0), Vector3.RIGHT * 2)
	_expect(side["blocked_x"] and side["position"].x < 4.0
		and is_equal_approx(side["position"].y, MovementRules.PLAYER_HEIGHT), "west stair rail blocks lateral entry")

	var landing := _at(Vector2(8, 1), 3.5)
	var drop := MovementRules.resolve_step(landing, Vector3.BACK * 2)
	_expect(drop["position"].is_equal_approx(_at(Vector2(8, 3), 0.0)), "open gallery edge snaps to ground")

	var eye := landing + Vector3.UP * ArenaRules.EYE_HEIGHT
	var distance := ArenaRules.first_blocker_distance(eye, Vector3.DOWN, 10.0)
	_expect(is_equal_approx(eye.y - distance, 3.5), "downward shot hits gallery slab")

	if failures == 0:
		print("NOCTURNA_STAIR_TEST_OK checks=%d" % checks)
	quit(0 if failures == 0 else 1)

func _check_route(base: Vector2, middle: Vector2, top: Vector2) -> void:
	var position := _at(base, 0.0)
	for point in [middle, top, middle, base]:
		var result := MovementRules.resolve_step(position, _at(point, 0.0) - position)
		position = result["position"]
		var height := 0.0 if point == base else (3.5 if point == top else 1.75)
		_expect(not result["blocked_x"] and not result["blocked_z"]
			and position.is_equal_approx(_at(point, height)), "stair route %s to %s at height %s" % [base, point, height])

func _at(point: Vector2, height: float) -> Vector3:
	return Vector3(point.x, MovementRules.PLAYER_HEIGHT + height, point.y)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
