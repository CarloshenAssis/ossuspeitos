class_name CombatNetworkCoordinator
extends Node

## Explicit-only E2E coordinator. It controls barriers and official test setup;
## every gameplay action still crosses NetworkApp's real combat RPCs.

var app
var stage := "WAIT_FOR_ACTIVE"
var stage_started_msec := 0
var acknowledgements: Dictionary = {}
var action_results: Array = []
var action_history: Array = []
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
var previous_stage := "NONE"
var expected_round_id := 0
var command_id := 0
var expected_peers: Dictionary = {}
var sent_commands: Array = []
var last_rejection_by_peer: Dictionary = {}
var processed_commands: Dictionary = {}
var last_wait_log_msec := 0
var current_sequence := -1
var current_expected_action := ""
var last_fire_one_diagnostic := ""
var current_shot_events := 0
var current_shot_hit := false
var current_hit_peer_id := 0
var lane_prepared_msec := 0
var post_end_command_active := false

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
		_print_timeout_diagnostic()
		app.get_tree().quit(1)
		return
	if Time.get_ticks_msec() - last_wait_log_msec >= 1000:
		last_wait_log_msec = Time.get_ticks_msec()
		print("COMBAT_STAGE_WAIT stage=%s missing=%s state=actions:%d,acks:%d" % [stage, _missing_peers(), action_results.size(), acknowledgements.size()])
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
			action_results.clear(); _enter_wait("WAIT_ARM_READY")
		else: _prepare_ammo()
		return
	if stage == "WAIT_ARM_READY" and _pickup_action_ready():
		action_results.clear(); _enter("ARM", [shooter], {"actor": shooter, "pickup_id": "weapon_1", "sequence": 2}); return
	if stage == "ARM":
		if not str(app.combat_authority.inventory.get_inventory(shooter).get("weapon_id", "")).is_empty():
			print("COMBAT_STAGE_EXIT stage=ARM result=official_weapon_present")
			_prepare_ammo(); return
		if _has_rejection(): _fail("ARM rejected: %s" % _latest_reason()); return
	if stage == "AMMO":
		var ammo_state: Dictionary = app.combat_authority.inventory.get_inventory(shooter)
		if int(ammo_state.get("reserve", 0)) > 0 and not bool(app.combat_authority.inventory.ground_items["ammo_0"]["available"]):
			print("COMBAT_STAGE_EXIT stage=AMMO result=official_ammo_present")
			_prepare_lane(); _enter_wait("WAIT_FIRE_ONE_READY"); return
		if _has_rejection(): _fail("AMMO rejected: %s" % _latest_reason()); return
	if stage == "WAIT_AMMO_READY" and _pickup_action_ready():
		action_results.clear(); _enter("AMMO", [shooter], {"actor": shooter, "pickup_id": "ammo_0", "sequence": 3}); return
	if stage == "WAIT_FIRE_ONE_READY":
		var lane_error := validate_test_lane(app.authoritative_world.states, app.round_authority.alive, shooter, target)
		if lane_error.is_empty() and Time.get_ticks_msec() > lane_prepared_msec:
			print("COMBAT_STAGE_EXIT stage=WAIT_FIRE_ONE_READY result=official_positions_confirmed")
			action_results.clear(); _enter("FIRE_ONE", [shooter], _fire_payload(1)); return
	if stage == "FIRE_ONE" and _single_action_accepted():
		_log_fire_one_state()
		var fire_inventory: Dictionary = app.combat_authority.inventory.get_inventory(shooter)
		if current_shot_events != 1 or not current_shot_hit or current_hit_peer_id != target or int(fire_inventory.get("magazine", -1)) != 5 \
				or int(app.combat_authority.health.get(target, -1)) != 66:
			_fail("first fire official outcome mismatch"); return
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
	if stage == "POST_END" and post_end_complete(acknowledgements, action_results, peers, expected_round_id, command_id, current_sequence):
		print("COMBAT_POST_END_ACTIONS_REJECTED")
		print("COMBAT_PRIVACY_OK clients=4 leaks=0")
		print("COMBAT_SERVER_TEST_OK clients=4")
		app._begin_server_shutdown(peers)
		stage = "SHUTDOWN"

func observe_server_action(peer_id: int, action: String, sequence: Variant, result: Dictionary) -> void:
	if app.mode != "server": return
	var received_sequence := int(sequence) if typeof(sequence) == TYPE_INT else -1
	if received_sequence != current_sequence or not expected_peers.has(peer_id) \
			or (not current_expected_action.is_empty() and action != current_expected_action):
		print("COMBAT_STAGE_ACK stage=%s peer_id=%d event=stale_action_ignored count=%d expected=%d" % [stage, peer_id, action_results.size(), expected_peers.size()])
		return
	var entry := {"round_id": expected_round_id, "stage": stage, "command_id": command_id, "peer_id": peer_id, "action": action, "sequence": received_sequence, "accepted": bool(result.get("accepted", false)), "reason": str(result.get("reason", ""))}
	if stage == "FIRE_ONE" and action == "fire": current_hit_peer_id = int(result.get("hit_peer_id", 0))
	if not record_correlated_result(action_history, entry):
		print("COMBAT_STAGE_ACK stage=%s peer_id=%d event=duplicate_action_ignored count=%d expected=%d" % [stage, peer_id, action_results.size(), expected_peers.size()])
		return
	action_results.append(entry)
	if not bool(entry["accepted"]): last_rejection_by_peer[peer_id] = str(entry["reason"])
	print("COMBAT_STAGE_ACK stage=%s peer_id=%d event=action_%s count=%d expected=%d" % [stage, peer_id, action, action_results.size(), expected_peers.size()])
	if stage == "FIRE_ONE": _log_fire_one_state()

func observe_server_shot(event: Dictionary) -> void:
	if app.mode != "server" or stage != "FIRE_ONE": return
	if int(event.get("round_id", 0)) == expected_round_id and int(event.get("shooter_peer_id", 0)) == shooter:
		current_shot_events += 1
		current_shot_hit = bool(event.get("hit_player", false))
		_log_fire_one_state()

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
			if post_end_command_active:
				post_end_rejections += 1
				if post_end_rejections == 3 and privacy_leaks == 0:
					print("COMBAT_CLIENT_TEST_OK id=%s" % app.client_label)
					post_end_command_active = false

@rpc("authority", "call_remote", "reliable")
func combat_test_command(round_id: int, received_stage: String, received_command_id: int, payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if received_command_id <= 0 or processed_commands.has(received_command_id): return
	pending_command = {"round_id": round_id, "command": received_stage, "command_id": received_command_id, "payload": payload}

@rpc("any_peer", "call_remote", "reliable")
func combat_test_ack(round_id: int, received_stage: String, received_command_id: int, event: String) -> void:
	if not multiplayer.is_server() or app.mode != "server": return
	var sender := multiplayer.get_remote_sender_id()
	if sender not in peers or round_id != expected_round_id or received_stage != stage or received_command_id != command_id: return
	var expected_event := "ready" if stage == "INITIAL" else "command_received"
	if event != expected_event: return
	if not expected_peers.has(sender) or acknowledgements.has(sender): return
	acknowledgements[sender] = true
	print("COMBAT_STAGE_ACK stage=%s peer_id=%d event=%s count=%d expected=%d" % [stage, sender, event, acknowledgements.size(), expected_peers.size()])

func _try_run_client_command() -> void:
	if not app.client_connected or not app.joined or app.shutdown_prepare_received:
		return
	var command := str(pending_command["command"]); var payload: Dictionary = pending_command["payload"]
	var received_command_id := int(pending_command["command_id"]); var round_id := int(pending_command["round_id"])
	var own_id := multiplayer.get_unique_id()
	if command != "INITIAL":
		processed_commands[received_command_id] = true
		combat_test_ack.rpc_id(1, round_id, command, received_command_id, "command_received")
	if command == "INITIAL":
		if app.local_combat_state.is_empty() or pickup_entries.size() != 8 or privacy_leaks != 0: return
		print("COMBAT_PRIVATE_STATE_OK id=%s updates=%d" % [app.client_label, private_updates])
		processed_commands[received_command_id] = true
		combat_test_ack.rpc_id(1, round_id, command, received_command_id, "ready")
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
		post_end_command_active = true
		app.request_pickup.rpc_id(1, "weapon_0", payload["sequence"])
		app.request_fire.rpc_id(1, payload["sequence"], Vector3.ZERO, Vector3.FORWARD)
		app.request_reload.rpc_id(1, payload["sequence"])
	if command != "INITIAL" or processed_commands.has(received_command_id):
		processed_commands[received_command_id] = true
		pending_command.clear()

func _enter(next: String, recipients: Array, payload: Dictionary = {}) -> void:
	print("COMBAT_STAGE_EXIT stage=%s result=transition" % stage)
	previous_stage = stage; stage = next; stage_started_msec = Time.get_ticks_msec(); acknowledgements.clear(); expected_peers.clear(); action_results.clear()
	expected_round_id = app.round_authority.round_id; command_id += 1
	current_sequence = int(payload.get("sequence", -1))
	current_expected_action = _expected_action_for_stage(next)
	current_shot_events = 0
	current_shot_hit = false
	current_hit_peer_id = 0
	print("COMBAT_STAGE_ENTER stage=%s previous=%s round_id=%d now=%d" % [stage, previous_stage, expected_round_id, stage_started_msec])
	for peer_id in recipients:
		expected_peers[int(peer_id)] = true
		var sequence := int(payload.get("sequence", -1))
		sent_commands.append({"stage": stage, "target": int(peer_id), "command_id": command_id, "sequence": sequence})
		print("COMBAT_STAGE_COMMAND stage=%s target=%d command=%d sequence=%d" % [stage, int(peer_id), command_id, sequence])
		combat_test_command.rpc_id(int(peer_id), expected_round_id, next, command_id, payload)

func _enter_wait(next: String) -> void:
	print("COMBAT_STAGE_EXIT stage=%s result=wait_for_official_rate_window" % stage)
	previous_stage = stage; stage = next; stage_started_msec = Time.get_ticks_msec(); acknowledgements.clear(); expected_peers.clear()
	expected_round_id = app.round_authority.round_id
	current_sequence = -1
	current_expected_action = ""
	print("COMBAT_STAGE_ENTER stage=%s previous=%s round_id=%d now=%d" % [stage, previous_stage, expected_round_id, stage_started_msec])

func _single_action_accepted() -> bool:
	return action_results.size() == 1 and bool(action_results[0]["accepted"]) \
		and (current_expected_action.is_empty() or str(action_results[0]["action"]) == current_expected_action)

func _prepare_ammo() -> void:
	_set_position(shooter, ArenaRules.PICKUP_POSITIONS[4] + Vector3.UP * 0.75)
	action_results.clear(); _enter_wait("WAIT_AMMO_READY")

func _prepare_lane() -> void:
	var safe_positions := [Vector3(-8, 1, -8), Vector3(-8, 1, 8)]
	var safe_index := 0
	for peer_id in peers:
		if int(peer_id) == shooter or int(peer_id) == target: continue
		_set_position(int(peer_id), safe_positions[safe_index])
		safe_index += 1
	_set_position(shooter, Vector3(8, 1, 8))
	_set_position(target, Vector3(8, 1, 2))
	app.authoritative_world.states[shooter]["yaw"] = 0.0
	lane_prepared_msec = Time.get_ticks_msec()

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

func _pickup_action_ready() -> bool:
	var last := _last_action("pickup")
	return last < 0 or Time.get_ticks_msec() >= last + CombatAuthority.ACTION_INTERVAL_MSEC

func _expected_action_for_stage(value: String) -> String:
	if value in ["CONTEST", "ARM", "AMMO"]: return "pickup"
	if value in ["FIRE_ONE", "REPLAY", "RATE", "CADENCE", "WALL", "FIRE_TWO", "FIRE_THREE"]: return "fire"
	if value == "RELOAD": return "reload"
	return ""

func _fail(reason: String) -> void:
	push_error("COMBAT_NETWORK_TEST_FAILURE stage=%s reason=%s" % [stage, reason])
	app.get_tree().quit(1)

func cancel_pending(reason: String) -> void:
	pending_command.clear()
	set_process(false)
	print("COMBAT_TEST_CANCELLED reason=%s" % reason)

func _log_fire_one_state() -> void:
	if shooter <= 0 or target <= 0: return
	var inventory: Dictionary = app.combat_authority.inventory.get_inventory(shooter)
	var geometry := _ray_candidate_diagnostics()
	var state := "round=%d stage=%s command=%d peer=%d expected_target=%d actual_target=%d sequence=%d results=%d accepted=%s magazine=%d target_health=%d shot_events=%d hit=%s origin=%s direction=%s yaw=%.3f candidates=%s positions=%s" % [
		expected_round_id, stage, command_id, shooter, target, current_hit_peer_id, current_sequence, action_results.size(),
		str(_single_action_accepted()), int(inventory.get("magazine", -1)),
		int(app.combat_authority.health.get(target, -1)), current_shot_events, str(current_shot_hit),
		geometry["origin"], geometry["direction"], float(app.authoritative_world.states[shooter]["yaw"]), geometry["candidates"], geometry["positions"]]
	if state != last_fire_one_diagnostic:
		last_fire_one_diagnostic = state
		print("COMBAT_FIRE_ONE_STATE %s" % state)

static func record_correlated_result(history: Array, entry: Dictionary) -> bool:
	for existing in history:
		if int(existing.get("round_id", -1)) == int(entry.get("round_id", -2)) \
				and str(existing.get("stage", "")) == str(entry.get("stage", "!")) \
				and int(existing.get("command_id", -1)) == int(entry.get("command_id", -2)) \
				and int(existing.get("peer_id", -1)) == int(entry.get("peer_id", -2)) \
				and str(existing.get("action", "")) == str(entry.get("action", "!")) \
				and int(existing.get("sequence", -1)) == int(entry.get("sequence", -2)):
			return false
	history.append(entry.duplicate(true))
	return true

static func matching_results(history: Array, round_id: int, expected_stage: String, expected_command_id: int, peer_id: int, action: String, sequence: int) -> Array:
	var matches: Array = []
	for entry in history:
		if int(entry.get("round_id", -1)) == round_id and str(entry.get("stage", "")) == expected_stage \
				and int(entry.get("command_id", -1)) == expected_command_id and int(entry.get("peer_id", -1)) == peer_id \
				and str(entry.get("action", "")) == action and int(entry.get("sequence", -1)) == sequence:
			matches.append(entry)
	return matches

static func validate_test_lane(states: Dictionary, alive: Dictionary, shooter_id: int, target_id: int) -> String:
	if not states.has(shooter_id) or not states.has(target_id): return "missing_actor"
	var shooter_position: Vector3 = states[shooter_id]["position"]
	var target_position: Vector3 = states[target_id]["position"]
	if shooter_position != Vector3(8, 1, 8) or target_position != Vector3(8, 1, 2): return "position_not_applied"
	if absf(float(states[shooter_id]["yaw"])) > 0.0001: return "yaw_not_applied"
	var bystanders: Array = []
	for peer_id in states:
		if int(peer_id) != shooter_id and int(peer_id) != target_id: bystanders.append(int(peer_id))
	bystanders.sort()
	if bystanders.size() != 2: return "invalid_bystander_count"
	var expected_safe := [Vector3(-8, 1, -8), Vector3(-8, 1, 8)]
	for index in bystanders.size():
		if states[bystanders[index]]["position"] != expected_safe[index]: return "bystander_position_not_applied"
	for peer_id in states:
		if (states[peer_id]["velocity"] as Vector3).length_squared() > 0.000001: return "participant_moving"
		if (states[peer_id]["input"] as Vector2).length_squared() > 0.000001: return "participant_input_active"
	var origin := shooter_position + Vector3.UP * ArenaRules.EYE_HEIGHT
	var target_distance := ArenaRules.ray_player(origin, Vector3.FORWARD, 20.0, target_position)
	if target_distance < 0.0: return "target_not_intersected"
	for peer_id in states:
		if int(peer_id) == shooter_id or int(peer_id) == target_id or not bool(alive.get(peer_id, false)): continue
		var candidate_position: Vector3 = states[peer_id]["position"]
		if candidate_position == shooter_position or candidate_position == target_position: return "overlapping_participant"
		var distance := ArenaRules.ray_player(origin, Vector3.FORWARD, 20.0, candidate_position)
		if distance >= 0.0 and distance <= target_distance: return "intermediate_participant"
	return ""

static func post_end_complete(acks: Dictionary, results: Array, expected: Array, round_id: int, expected_command_id: int, sequence: int) -> bool:
	if acks.size() != expected.size(): return false
	for peer_id in expected:
		if not acks.has(peer_id): return false
	var seen := {}
	for result in results:
		if int(result.get("round_id", -1)) != round_id or str(result.get("stage", "")) != "POST_END" \
				or int(result.get("command_id", -1)) != expected_command_id or int(result.get("sequence", -1)) != sequence \
				or bool(result.get("accepted", true)) or str(result.get("reason", "")) != "round_not_active":
			return false
		var peer_id := int(result.get("peer_id", 0)); var action := str(result.get("action", ""))
		if peer_id not in expected or action not in ["pickup", "fire", "reload"]: return false
		var key := "%d:%s" % [peer_id, action]
		if seen.has(key): return false
		seen[key] = true
	return seen.size() == expected.size() * 3

func _ray_candidate_diagnostics() -> Dictionary:
	var origin: Vector3 = app.authoritative_world.states[shooter]["position"] + Vector3.UP * ArenaRules.EYE_HEIGHT
	var candidates := {}; var positions := {}
	for peer_id in peers:
		var position: Vector3 = app.authoritative_world.states[peer_id]["position"]
		positions[int(peer_id)] = position
		if int(peer_id) != shooter and app.round_authority.is_alive(int(peer_id)):
			candidates[int(peer_id)] = ArenaRules.ray_player(origin, Vector3.FORWARD, 20.0, position)
	return {"origin": origin, "direction": Vector3.FORWARD, "candidates": candidates, "positions": positions}

func _has_rejection() -> bool:
	for result in action_results:
		if not bool(result.get("accepted", false)): return true
	return false

func _latest_reason() -> String:
	return str(action_results.back().get("reason", "missing")) if not action_results.is_empty() else "missing"

func _missing_peers() -> Array:
	var missing: Array = []
	for peer_id in expected_peers:
		if not acknowledgements.has(peer_id): missing.append(peer_id)
	return missing

func _print_timeout_diagnostic() -> void:
	var inventories := {}; var positions := {}; var action_sequences := {}
	if app.combat_authority != null:
		for peer_id in peers:
			inventories[int(peer_id)] = app.combat_authority.inventory.get_inventory(int(peer_id)) if int(peer_id) == shooter else {"armed": not str(app.combat_authority.inventory.get_inventory(int(peer_id)).get("weapon_id", "")).is_empty()}
			if app.authoritative_world.states.has(peer_id): positions[int(peer_id)] = app.authoritative_world.states[peer_id]["position"]
			if app.combat_authority._sequences.has(peer_id):
				action_sequences[int(peer_id)] = {"sequences": app.combat_authority._sequences[peer_id], "timestamps": app.combat_authority._last_action_msec[peer_id]}
	var pickup_availability := {}
	for pickup_id in ["weapon_0", "weapon_1", "ammo_0"]:
		if app.combat_authority.inventory.ground_items.has(pickup_id): pickup_availability[pickup_id] = app.combat_authority.inventory.ground_items[pickup_id]["available"]
	push_error("COMBAT_TEST_STAGE_TIMEOUT stage=%s previous=%s expected_round=%d actual_round=%d expected_peers=%s confirmed=%s commands=%s actions=%s action_sequences=%s owner_count=%d shooter_selected=%s target_selected=%s weapon_pickup=weapon_1 ammo_pickup=ammo_0 availability=%s shooter_inventory=%s positions=%s last_rejections=%s deadline=%d now=%d" % [
		stage, previous_stage, expected_round_id, app.round_authority.round_id, expected_peers.keys(), acknowledgements.keys(), sent_commands, action_results,
		action_sequences, _count_weapon_owners(), str(shooter > 0), str(target > 0), pickup_availability, inventories.get(shooter, {}), positions,
		last_rejection_by_peer, stage_started_msec + 10000, Time.get_ticks_msec()])

func _count_weapon_owners() -> int:
	var owners := 0
	for peer_id in peers:
		if not str(app.combat_authority.inventory.get_inventory(peer_id).get("weapon_id", "")).is_empty(): owners += 1
	return owners

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
