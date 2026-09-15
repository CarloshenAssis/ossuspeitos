class_name CombatNetworkCoordinator
extends Node

## Explicit-only E2E coordinator. It controls barriers and official test setup;
## every gameplay action still crosses NetworkApp's real combat RPCs.

var app
var stage := "WAIT_FOR_ACTIVE"
var stage_started_msec := 0
var acknowledgements: Dictionary = {}
var action_results: Array = []
var peers: Array = []
var shooter := 0
var target := 0
var pickup_entries: Array = []
var private_updates := 0
var public_shots := 0
var hit_confirms := 0
var eliminations := 0
var health_history: Array = []
var pending_command: Dictionary = {}
var privacy_leaks := 0
var post_end_rejections := 0

func _ready() -> void:
	app = get_parent()
	stage_started_msec = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	if app.mode == "server":
		_server_tick()
	elif not pending_command.is_empty():
		_try_run_client_command()

func _server_tick() -> void:
	if Time.get_ticks_msec() - stage_started_msec > 10000:
		push_error("COMBAT_TEST_STAGE_TIMEOUT stage=%s" % stage)
		app.get_tree().quit(1)
		return
	if stage == "WAIT_FOR_ACTIVE":
		if app.round_authority.state != RoundState.ACTIVE or app.combat_authority.active_round_id <= 0:
			return
		peers = app.round_authority.participants.keys()
		peers.sort()
		if peers.size() != 4: return
		print("COMBAT_ROUND_ACTIVE players=4")
		var health_ok := true
		var inventory_ok := true
		for peer_id in peers:
			health_ok = health_ok and int(app.combat_authority.health.get(peer_id, 0)) == 100
			inventory_ok = inventory_ok and str(app.combat_authority.inventory.get_inventory(peer_id).get("weapon_id", "")).is_empty()
		if not health_ok or not inventory_ok:
			_fail("invalid initial authoritative state"); return
		print("COMBAT_INITIAL_HEALTH_OK players=4 health=100")
		print("COMBAT_INITIAL_INVENTORY_OK players=4")
		_enter("INITIAL", peers)
		return
	if stage == "INITIAL" and acknowledgements.size() == 4:
		var first := int(peers[0]); var second := int(peers[1])
		_set_position(first, ArenaRules.PICKUP_POSITIONS[0] + Vector3.UP * 0.75)
		_set_position(second, ArenaRules.PICKUP_POSITIONS[0] + Vector3.UP * 0.75)
		action_results.clear()
		_enter("CONTEST", [first, second], {"actors": [first, second], "pickup_id": "weapon_0", "sequence": 1})
		return
	if stage == "CONTEST" and action_results.size() == 2:
		var accepted := 0
		for result in action_results: accepted += 1 if bool(result["accepted"]) else 0
		var owners := 0
		for peer_id in peers: owners += 1 if not str(app.combat_authority.inventory.get_inventory(peer_id).get("weapon_id", "")).is_empty() else 0
		if accepted != 1 or owners != 1 or bool(app.combat_authority.inventory.ground_items["weapon_0"]["available"]):
			_fail("pickup contest invariant"); return
		print("COMBAT_PICKUP_CONTEST_OK accepted=1 rejected=1 owners=1")
		for peer_id in peers:
			if app.round_authority.get_role_for_peer(peer_id) == Role.ASSASSIN: target = int(peer_id)
			elif shooter == 0: shooter = int(peer_id)
		if str(app.combat_authority.inventory.get_inventory(shooter).get("weapon_id", "")).is_empty():
			_set_position(shooter, ArenaRules.PICKUP_POSITIONS[1] + Vector3.UP * 0.75)
			action_results.clear(); _enter("ARM", [shooter], {"actor": shooter, "pickup_id": "weapon_1", "sequence": 2})
		else: _prepare_ammo()
		return
	if stage == "ARM" and _single_action_accepted(): _prepare_ammo(); return
	if stage == "AMMO" and _single_action_accepted():
		_prepare_lane(); _enter("FIRE_ONE", [shooter], _fire_payload(1)); return
	if stage == "FIRE_ONE" and _single_action_accepted():
		if int(app.combat_authority.health.get(target, -1)) != 66: _fail("first damage"); return
		print("COMBAT_FIRE_OK shots=1 ammo_consumed=1 damage=34")
		action_results.clear(); _enter("REPLAY", [shooter], _fire_payload(1)); return
	if stage == "REPLAY" and action_results.size() == 1:
		if str(action_results[0].get("reason", "")) != "replay": _fail("replay accepted"); return
		print("COMBAT_REPLAY_REJECTED")
		# Pin only the server-owned limiter clock so transport latency cannot turn
		# this <80 ms boundary probe into a cadence probe.
		(app.combat_authority._last_action_msec[shooter] as Dictionary)["fire"] = Time.get_ticks_msec()
		action_results.clear(); _enter("RATE", [shooter], _fire_payload(2)); return
	if stage == "RATE" and action_results.size() == 1:
		if str(action_results[0].get("reason", "")) != "rate_limited": _fail("rate probe missed window"); return
		print("COMBAT_RATE_LIMIT_REJECTED")
		stage = "WAIT_CADENCE_PROBE"; stage_started_msec = Time.get_ticks_msec(); return
	if stage == "WAIT_CADENCE_PROBE" and Time.get_ticks_msec() >= _last_action("fire") + CombatAuthority.ACTION_INTERVAL_MSEC:
		action_results.clear(); _enter("CADENCE", [shooter], _fire_payload(2)); return
	if stage == "CADENCE" and action_results.size() == 1:
		if str(action_results[0].get("reason", "")) != "fire_rate": _fail("cadence probe"); return
		print("COMBAT_FIRE_RATE_REJECTED")
		action_results.clear(); _enter("RELOAD", [shooter], {"actor": shooter, "sequence": 1}); return
	if stage == "RELOAD" and _single_action_accepted():
		stage = "WAIT_RELOAD"; stage_started_msec = Time.get_ticks_msec(); return
	if stage == "WAIT_RELOAD":
		var held: Dictionary = app.combat_authority.inventory.get_inventory(shooter)
		if not held.is_empty() and not bool(held["reloading"]) and int(held["magazine"]) == 6 and int(held["reserve"]) == 5:
			print("COMBAT_RELOAD_OK magazine_before=5 magazine_after=6 reserve_before=6 reserve_after=5")
			_prepare_wall(); action_results.clear(); _enter("WALL", [shooter], _fire_payload(2));
		return
	if stage == "WALL" and _single_action_accepted():
		if int(app.combat_authority.health.get(target, -1)) != 66: _fail("wall did not block"); return
		print("COMBAT_WALL_BLOCKED")
		stage = "WAIT_SECOND_HIT"; stage_started_msec = Time.get_ticks_msec(); return
	if stage == "WAIT_SECOND_HIT" and Time.get_ticks_msec() >= _last_shot() + 400:
		_prepare_lane(); action_results.clear(); _enter("FIRE_TWO", [shooter], _fire_payload(3)); return
	if stage == "FIRE_TWO" and _single_action_accepted():
		if int(app.combat_authority.health.get(target, -1)) != 32: _fail("second damage"); return
		stage = "WAIT_FINAL_HIT"; stage_started_msec = Time.get_ticks_msec(); return
	if stage == "WAIT_FINAL_HIT" and Time.get_ticks_msec() >= _last_shot() + 400:
		action_results.clear(); _enter("FIRE_THREE", [shooter], _fire_payload(4)); return
	if stage == "FIRE_THREE" and action_results.size() == 1:
		stage = "WAIT_ENDED"; stage_started_msec = Time.get_ticks_msec(); return
	if stage == "WAIT_ENDED" and app.round_authority.state == RoundState.ENDED:
		if health_history.count(66) < 1 or health_history.count(32) < 1 or health_history.count(0) < 1 or eliminations != 1:
			_fail("damage or elimination history"); return
		print("COMBAT_DAMAGE_OK health_sequence=100,66,32,0")
		print("COMBAT_ELIMINATION_OK count=1")
		if app.round_authority.winning_team != Role.TEAM_INNOCENTS: _fail("wrong winner"); return
		print("COMBAT_WIN_CONDITION_OK winner=INNOCENTS")
		action_results.clear()
		_enter("POST_END", peers, {"sequence": 63})
		return
	if stage == "POST_END" and acknowledgements.size() == 4 and action_results.size() == 12:
		for result in action_results:
			if str(result.get("reason", "")) != "round_not_active": _fail("post-end action accepted"); return
		print("COMBAT_POST_END_ACTIONS_REJECTED")
		print("COMBAT_PRIVACY_OK clients=4 leaks=0")
		print("COMBAT_SERVER_TEST_OK clients=4")
		app._begin_server_shutdown(peers)
		stage = "SHUTDOWN"

func observe_server_action(peer_id: int, action: String, result: Dictionary) -> void:
	if app.mode != "server": return
	action_results.append({"peer_id": peer_id, "action": action, "accepted": bool(result.get("accepted", false)), "reason": str(result.get("reason", ""))})

func observe_private_emission(peer_id: int, state: Dictionary) -> void:
	if app.mode == "server" and peer_id == target and state.has("health"):
		health_history.append(int(state["health"]))

func observe_server_elimination(_peer_id: int) -> void:
	if app.mode == "server": eliminations += 1

func observe_client_event(kind: String, payload: Variant = null) -> void:
	if app.mode == "server": return
	match kind:
		"private":
			private_updates += 1
			print("COMBAT_RPC_RECEIVED name=combat_private_state id=%s" % app.client_label)
			if typeof(payload) != TYPE_DICTIONARY or not _keys_equal(payload, ["round_id", "health", "weapon_id", "magazine", "reserve", "reloading"]): privacy_leaks += 1
		"pickups":
			pickup_entries = payload
			print("COMBAT_RPC_RECEIVED name=pickup_public_state id=%s" % app.client_label)
			if not payload.is_empty() and not _valid_pickups(payload): privacy_leaks += 1
		"shot":
			public_shots += 1
			print("COMBAT_RPC_RECEIVED name=combat_public_shot id=%s" % app.client_label)
			if typeof(payload) != TYPE_DICTIONARY or not _keys_equal(payload, ["round_id", "shooter_peer_id", "origin", "end", "hit_player"]): privacy_leaks += 1
		"hit":
			hit_confirms += 1
			print("COMBAT_RPC_RECEIVED name=combat_hit_confirmed id=%s" % app.client_label)
		"elimination":
			eliminations += 1
			if typeof(payload) != TYPE_INT: privacy_leaks += 1
			print("COMBAT_RPC_RECEIVED name=combat_public_elimination id=%s" % app.client_label)
		"rejection":
			print("COMBAT_RPC_RECEIVED name=combat_action_rejected id=%s" % app.client_label)
			if str(pending_command.get("command", "")) == "POST_END":
				post_end_rejections += 1
				if post_end_rejections == 3 and privacy_leaks == 0:
					print("COMBAT_CLIENT_TEST_OK id=%s" % app.client_label)
					pending_command.clear()
					combat_test_ack.rpc_id(1, "POST_END")

@rpc("authority", "call_remote", "reliable")
func combat_test_command(command: String, payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	pending_command = {"command": command, "payload": payload}

@rpc("any_peer", "call_remote", "reliable")
func combat_test_ack(command: String) -> void:
	if not multiplayer.is_server() or app.mode != "server": return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in peers or command != stage: return
	acknowledgements[sender] = true

func _try_run_client_command() -> void:
	var command := str(pending_command["command"]); var payload: Dictionary = pending_command["payload"]
	var own_id := multiplayer.get_unique_id()
	if command == "INITIAL":
		if app.local_combat_state.is_empty() or pickup_entries.size() != 8 or privacy_leaks != 0: return
		print("COMBAT_PRIVATE_STATE_OK id=%s updates=%d" % [app.client_label, private_updates])
		combat_test_ack.rpc_id(1, command)
	elif command == "CONTEST" and own_id in payload["actors"]:
		app.request_pickup.rpc_id(1, payload["pickup_id"], payload["sequence"])
	elif command == "ARM" and own_id == int(payload["actor"]):
		app.request_pickup.rpc_id(1, payload["pickup_id"], payload["sequence"])
	elif command == "AMMO" and own_id == int(payload["actor"]):
		app.request_pickup.rpc_id(1, payload["pickup_id"], payload["sequence"])
	elif command.begins_with("FIRE") or command == "REPLAY" or command == "RATE" or command == "CADENCE" or command == "WALL":
		if own_id == int(payload["actor"]): app.request_fire.rpc_id(1, payload["sequence"], payload["origin"], payload["direction"])
	elif command == "RELOAD" and own_id == int(payload["actor"]):
		app.request_reload.rpc_id(1, payload["sequence"])
	elif command == "POST_END":
		post_end_rejections = 0
		app.request_pickup.rpc_id(1, "weapon_0", payload["sequence"])
		app.request_fire.rpc_id(1, payload["sequence"], Vector3.ZERO, Vector3.FORWARD)
		app.request_reload.rpc_id(1, payload["sequence"])
	if command != "POST_END": pending_command.clear()

func _enter(next: String, recipients: Array, payload: Dictionary = {}) -> void:
	stage = next; stage_started_msec = Time.get_ticks_msec(); acknowledgements.clear()
	for peer_id in recipients: combat_test_command.rpc_id(int(peer_id), next, payload)

func _single_action_accepted() -> bool:
	return action_results.size() == 1 and bool(action_results[0]["accepted"])

func _prepare_ammo() -> void:
	_set_position(shooter, ArenaRules.PICKUP_POSITIONS[4] + Vector3.UP * 0.75)
	action_results.clear(); _enter("AMMO", [shooter], {"actor": shooter, "pickup_id": "ammo_0", "sequence": 3})

func _prepare_lane() -> void:
	_set_position(shooter, Vector3(8, 1, 8)); _set_position(target, Vector3(8, 1, 2)); app.authoritative_world.states[shooter]["yaw"] = 0.0

func _prepare_wall() -> void:
	_set_position(shooter, Vector3(0, 1, 5)); _set_position(target, Vector3(0, 1, -5)); app.authoritative_world.states[shooter]["yaw"] = 0.0

func _fire_payload(sequence: int) -> Dictionary:
	return {"actor": shooter, "sequence": sequence,
		"origin": app.authoritative_world.states[shooter]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT,
		"direction": Vector3.FORWARD}

func _set_position(peer_id: int, position: Vector3) -> void:
	var state: Dictionary = app.authoritative_world.states[peer_id]
	state["position"] = position; state["input"] = Vector2.ZERO; state["velocity"] = Vector3.ZERO

func _last_shot() -> int:
	return int(app.combat_authority.inventory.inventories[shooter]["last_shot_msec"])

func _last_action(action: String) -> int:
	return int((app.combat_authority._last_action_msec[shooter] as Dictionary)[action])

func _fail(reason: String) -> void:
	push_error("COMBAT_NETWORK_TEST_FAILURE stage=%s reason=%s" % [stage, reason])
	app.get_tree().quit(1)

func _keys_equal(value: Dictionary, expected: Array) -> bool:
	var actual := value.keys(); actual.sort(); expected.sort()
	return actual == expected

func _valid_pickups(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() != 8: return false
	var weapons := 0; var ammo := 0
	for raw in value:
		if typeof(raw) != TYPE_DICTIONARY or not _keys_equal(raw, ["pickup_id", "type", "position", "available", "round_id"]): return false
		if str(raw["type"]) == "weapon": weapons += 1
		elif str(raw["type"]) == "ammo": ammo += 1
		else: return false
	return weapons == 4 and ammo == 4
