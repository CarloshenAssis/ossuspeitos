class_name CombatAuthority
extends RefCounted

signal pickups_changed(snapshot: Array)
signal private_state_changed(peer_id: int, state: Dictionary)
signal shot_resolved(event: Dictionary)
signal player_eliminated(peer_id: int, instigator_peer_id: int)

const MAX_HEALTH := 100
const MAX_SEQUENCE_ADVANCE := 64
const ACTION_INTERVAL_MSEC := 80
const COMMON_WEAPON_ID := "common_pistol"
const AMMO_BOX_AMOUNT := 6

var round_authority: RoundAuthority
var world: AuthoritativeWorld
var inventory: InventoryAuthority
var combat_rules: CombatRules
var health: Dictionary = {}
var _sequences: Dictionary = {}
var _last_action_msec: Dictionary = {}
var active_round_id := 0

func _init(rounds: RoundAuthority, authoritative_world: AuthoritativeWorld) -> void:
	round_authority = rounds
	world = authoritative_world
	var definition := WeaponDefinition.new(COMMON_WEAPON_ID, 34, 6, 18, 400, 20.0, 1200, 0.0)
	inventory = InventoryAuthority.new({COMMON_WEAPON_ID: definition})
	combat_rules = CombatRules.new(inventory)

func begin_round(round_id: int, participant_ids: Array) -> void:
	clear_round()
	active_round_id = round_id
	for peer_id in participant_ids:
		var id := int(peer_id)
		inventory.register_player(id)
		health[id] = MAX_HEALTH
		_sequences[id] = {"pickup": -1, "fire": -1, "reload": -1}
		_last_action_msec[id] = {"pickup": -1, "fire": -1, "reload": -1}
		private_state_changed.emit(id, private_state(id))
	for index in 4:
		inventory.add_ground_weapon("weapon_%d" % index, COMMON_WEAPON_ID,
			ArenaRules.PICKUP_POSITIONS[index], 6, 0, round_id)
	for index in 4:
		inventory.add_ground_ammo("ammo_%d" % index, ArenaRules.PICKUP_POSITIONS[index + 4], AMMO_BOX_AMOUNT, round_id)
	pickups_changed.emit(public_pickups())

func clear_round() -> void:
	active_round_id = 0
	health.clear()
	_sequences.clear()
	_last_action_msec.clear()
	inventory.clear_session()
	pickups_changed.emit([])

func clear_player(peer_id: int) -> void:
	health.erase(peer_id)
	_sequences.erase(peer_id)
	_last_action_msec.erase(peer_id)
	inventory.clear_player(peer_id)

func tick(now_msec: int) -> void:
	if not _is_active_round():
		return
	for peer_id in inventory.inventories.keys():
		if not round_authority.is_alive(int(peer_id)):
			continue
		var state: Dictionary = inventory.inventories[peer_id]
		if bool(state["reloading"]) and now_msec >= int(state["reload_deadline_msec"]):
			inventory.complete_reload(int(peer_id), now_msec)
			private_state_changed.emit(int(peer_id), private_state(int(peer_id)))

func request_pickup(peer_id: int, pickup_id: Variant, sequence: Variant, now_msec: int) -> Dictionary:
	var rejection := _gate(peer_id, "pickup", sequence, now_msec)
	if not rejection.is_empty():
		return _rejected(rejection)
	if typeof(pickup_id) != TYPE_STRING or str(pickup_id).length() > 64:
		return _rejected("invalid_pickup")
	_commit_sequence(peer_id, "pickup", int(sequence), now_msec)
	var position: Variant = _official_position(peer_id)
	var reason := inventory.pickup(peer_id, pickup_id, true, true, position)
	if not reason.is_empty():
		return _rejected(reason)
	pickups_changed.emit(public_pickups())
	private_state_changed.emit(peer_id, private_state(peer_id))
	return {"accepted": true, "pickup_id": pickup_id}

func request_reload(peer_id: int, sequence: Variant, now_msec: int) -> Dictionary:
	var rejection := _gate(peer_id, "reload", sequence, now_msec)
	if not rejection.is_empty():
		return _rejected(rejection)
	_commit_sequence(peer_id, "reload", int(sequence), now_msec)
	var reason := inventory.start_reload(peer_id, now_msec, true, true)
	if not reason.is_empty():
		return _rejected(reason)
	private_state_changed.emit(peer_id, private_state(peer_id))
	return {"accepted": true}

func request_fire(peer_id: int, sequence: Variant, claimed_origin: Variant, claimed_direction: Variant, now_msec: int) -> Dictionary:
	var rejection := _gate(peer_id, "fire", sequence, now_msec)
	if not rejection.is_empty():
		return _rejected(rejection)
	var state: Dictionary = world.states[peer_id]
	var eye := (state["position"] as Vector3) + Vector3.UP * ArenaRules.EYE_HEIGHT
	var intent := {"sequence": sequence, "origin": claimed_origin, "direction": claimed_direction}
	var context := {"alive": true, "round_active": true, "eye_position": eye, "yaw": state["yaw"]}
	var shot := combat_rules.request_shot(peer_id, intent, context, now_msec)
	if not bool(shot.get("accepted", false)):
		return shot
	_commit_sequence(peer_id, "fire", int(sequence), now_msec)
	var shot_round_id := active_round_id
	var hit := _raycast(peer_id, shot["origin"], shot["direction"], shot["max_distance"])
	var endpoint: Vector3 = shot["origin"] + shot["direction"] * float(shot["max_distance"])
	if float(hit.get("distance", -1.0)) >= 0.0:
		endpoint = shot["origin"] + shot["direction"] * float(hit["distance"])
	if int(hit.get("peer_id", 0)) > 0:
		_apply_damage(int(hit["peer_id"]), peer_id, int(shot["damage"]), now_msec)
	var event := {"round_id": shot_round_id, "shooter_peer_id": peer_id,
		"origin": shot["origin"], "end": endpoint, "hit_player": int(hit.get("peer_id", 0)) > 0}
	shot_resolved.emit(event)
	private_state_changed.emit(peer_id, private_state(peer_id))
	# `hit_peer_id` remains inside the server process. NetworkApp only exposes the
	# boolean hit confirmation and sanitized public event to clients.
	return {"accepted": true, "hit": int(hit.get("peer_id", 0)) > 0,
		"hit_peer_id": int(hit.get("peer_id", 0))}

func private_state(peer_id: int) -> Dictionary:
	if not health.has(peer_id):
		return {"round_id": 0, "health": 0, "weapon_id": "", "magazine": 0, "reserve": 0, "reloading": false}
	var held := inventory.get_inventory(peer_id)
	return {"round_id": active_round_id, "health": int(health[peer_id]),
		"weapon_id": str(held.get("weapon_id", "")), "magazine": int(held.get("magazine", 0)),
		"reserve": int(held.get("reserve", 0)), "reloading": bool(held.get("reloading", false))}

func public_pickups() -> Array:
	return inventory.public_pickups()

func _apply_damage(target: int, shooter: int, damage: int, now_msec: int) -> void:
	if not health.has(target) or not round_authority.is_alive(target) or not _is_active_round():
		return
	health[target] = clampi(int(health[target]) - damage, 0, MAX_HEALTH)
	private_state_changed.emit(target, private_state(target))
	if int(health[target]) == 0:
		var reason := round_authority.eliminate_player(target, "shot", shooter, now_msec)
		if reason.is_empty():
			player_eliminated.emit(target, shooter)

func _raycast(shooter: int, origin: Vector3, direction: Vector3, max_distance: float) -> Dictionary:
	var closest := max_distance
	var result := {"distance": -1.0, "peer_id": 0}
	for blocker in ArenaRules.BLOCKERS:
		var distance := ArenaRules.ray_aabb(origin, direction, max_distance, blocker["center"], blocker["size"])
		if distance >= 0.0 and distance <= closest:
			closest = distance
			result = {"distance": distance, "peer_id": 0}
	for target in health:
		var peer_id := int(target)
		if peer_id == shooter or not round_authority.is_alive(peer_id) or not world.states.has(peer_id):
			continue
		var distance := ArenaRules.ray_player(origin, direction, max_distance, world.states[peer_id]["position"])
		if distance >= 0.0 and distance < closest:
			closest = distance
			result = {"distance": distance, "peer_id": peer_id}
	return result

func _gate(peer_id: int, action: String, sequence: Variant, now_msec: int) -> String:
	if not _is_active_round(): return "round_not_active"
	if not round_authority.is_participant(peer_id) or not inventory.inventories.has(peer_id): return "unknown_peer"
	if not round_authority.is_alive(peer_id): return "player_dead"
	if typeof(sequence) != TYPE_INT: return "invalid_sequence"
	var previous := int((_sequences[peer_id] as Dictionary)[action])
	if int(sequence) <= previous: return "replay"
	if int(sequence) - previous > MAX_SEQUENCE_ADVANCE: return "sequence_jump"
	var last := int((_last_action_msec[peer_id] as Dictionary)[action])
	if last >= 0 and now_msec - last < ACTION_INTERVAL_MSEC: return "rate_limited"
	return ""

func _commit_sequence(peer_id: int, action: String, sequence: int, now_msec: int) -> void:
	(_sequences[peer_id] as Dictionary)[action] = sequence
	(_last_action_msec[peer_id] as Dictionary)[action] = now_msec

func _official_position(peer_id: int) -> Variant:
	return world.states[peer_id]["position"] if world.states.has(peer_id) else null

func _is_active_round() -> bool:
	return active_round_id > 0 and round_authority.state == RoundState.ACTIVE and round_authority.round_id == active_round_id

func _rejected(reason: String) -> Dictionary:
	return {"accepted": false, "reason": reason}
