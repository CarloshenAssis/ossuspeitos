class_name CombatRules
extends RefCounted

const MAX_SEQUENCE_ADVANCE := 64

var inventory_authority: InventoryAuthority
var _rng: RandomNumberGenerator

func _init(authority: InventoryAuthority, rng: RandomNumberGenerator = null) -> void:
	inventory_authority = authority
	_rng = rng if rng != null else RandomNumberGenerator.new()

## Validates an authenticated peer's intent. Accepted output is only a safe input
## for a future server raycast; it never contains a selected target or hit result.
func request_shot(peer_id: int, intent: Variant, context: Variant, now_msec: int) -> Dictionary:
	var rejection := _validate_request(peer_id, intent, context, now_msec)
	if not rejection.is_empty():
		return {"accepted": false, "reason": rejection}
	var inventory: Dictionary = inventory_authority.inventories[peer_id]
	var definition: WeaponDefinition = inventory_authority.get_equipped_definition(peer_id)
	var sequence: int = intent["sequence"]
	var claimed_direction: Vector3 = intent["direction"]
	var previous_time: int = inventory["last_shot_msec"]
	var bloom := WeaponRules.recovered_bloom(float(inventory["shot_bloom_radians"]),
		0 if previous_time < 0 else now_msec - previous_time, float(definition.bloom_recovery_radians_per_second))
	var velocity: Vector3 = context.get("velocity", Vector3.ZERO)
	var movement_fraction := clampf(Vector2(velocity.x, velocity.z).length() / MovementRules.MAX_SPEED, 0.0, 1.0)
	var spread := float(definition.spread_radians) + float(definition.movement_spread_radians) * movement_fraction + bloom
	inventory["shot_bloom_radians"] = minf(float(definition.max_bloom_radians), bloom + float(definition.bloom_per_shot_radians))
	inventory["last_sequence"] = sequence
	inventory["last_shot_msec"] = now_msec
	inventory_authority.consume_round(peer_id)
	return {
		"accepted": true,
		"sequence": sequence,
		"origin": context["eye_position"],
		# Rumo horizontal validado com o pitch oficial; a componente vertical
		# declarada pelo cliente nunca é usada.
		"direction": _apply_server_spread(WeaponRules.official_shot_direction(claimed_direction, float(context.get("pitch", 0.0))), spread),
		"max_distance": float(definition.range_meters),
		"damage": float(definition.damage),
		"weapon_id": definition.id,
	}

func clear_player(peer_id: int) -> void:
	inventory_authority.clear_player(peer_id)

func _validate_request(peer_id: int, intent: Variant, context: Variant, now_msec: int) -> String:
	if now_msec < 0:
		return "invalid_time"
	if not inventory_authority.inventories.has(peer_id):
		return "unknown_peer"
	if typeof(context) != TYPE_DICTIONARY:
		return "invalid_context"
	if not context.has("alive") or typeof(context["alive"]) != TYPE_BOOL:
		return "invalid_context"
	if not context.has("round_active") or typeof(context["round_active"]) != TYPE_BOOL:
		return "invalid_context"
	if not context.has("eye_position") or not context.has("yaw"):
		return "invalid_context"
	if typeof(context.get("velocity", Vector3.ZERO)) != TYPE_VECTOR3 or not WeaponRules.is_finite_vector3(context.get("velocity", Vector3.ZERO)):
		return "invalid_velocity"
	if not bool(context["alive"]):
		return "player_dead"
	if not bool(context["round_active"]):
		return "round_not_active"
	if typeof(intent) != TYPE_DICTIONARY:
		return "invalid_intent"
	var allowed := {"sequence": true, "origin": true, "direction": true}
	for key in intent:
		if not allowed.has(key):
			return "forbidden_field"
	if not intent.has("sequence") or typeof(intent["sequence"]) != TYPE_INT:
		return "invalid_sequence"
	if not intent.has("origin") or not intent.has("direction"):
		return "invalid_intent"
	var inventory: Dictionary = inventory_authority.inventories[peer_id]
	var definition := inventory_authority.get_equipped_definition(peer_id)
	if definition == null:
		return "no_equipped_weapon"
	if int(inventory["magazine"]) <= 0:
		return "empty_magazine"
	if bool(inventory["reloading"]):
		return "reloading"
	var sequence: int = intent["sequence"]
	var previous: int = inventory["last_sequence"]
	if sequence <= previous:
		return "replay" if sequence == previous else "old_sequence"
	if sequence - previous > MAX_SEQUENCE_ADVANCE and previous >= 0:
		return "sequence_jump"
	if previous < 0 and sequence > MAX_SEQUENCE_ADVANCE:
		return "sequence_jump"
	if int(inventory["last_shot_msec"]) >= 0 and now_msec < int(inventory["last_shot_msec"]):
		return "time_rollback"
	if int(inventory["last_shot_msec"]) >= 0 and now_msec - int(inventory["last_shot_msec"]) < int(definition.fire_interval_msec):
		return "fire_rate"
	var origin_error := WeaponRules.validate_origin(intent["origin"], context["eye_position"])
	if not origin_error.is_empty():
		return origin_error
	return WeaponRules.validate_direction_for_aim(intent["direction"], context["yaw"], context.get("pitch", 0.0))

func _apply_server_spread(direction: Vector3, spread_radians: float) -> Vector3:
	if spread_radians <= 0.0:
		return direction
	var axis := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var tangent := direction.cross(axis).normalized()
	var bitangent := direction.cross(tangent).normalized()
	# Uniform spherical cap: cos(theta) is uniform on [cos(cone), 1].
	# This remains finite through PI/2 and supports a full sphere at PI.
	var axial := lerpf(1.0, cos(spread_radians), _rng.randf())
	var radius := sqrt(maxf(0.0, 1.0 - axial * axial))
	var angle := _rng.randf_range(0.0, TAU)
	return (direction * axial + tangent * cos(angle) * radius + bitangent * sin(angle) * radius).normalized()
