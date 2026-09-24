extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_correlated_history()
	_test_headless_input_policy()
	_test_lane_validation()
	_test_post_end_correlation()
	if failures:
		quit(1)
		return
	print("COMBAT_NETWORK_COORDINATOR_TEST_OK checks=%d" % checks)
	quit(0)

func _entry(stage: String, command_id: int, peer_id: int, action: String, sequence: int, accepted: bool) -> Dictionary:
	return {"round_id": 1, "stage": stage, "command_id": command_id, "peer_id": peer_id,
		"action": action, "sequence": sequence, "accepted": accepted, "reason": ""}

func _test_correlated_history() -> void:
	var history: Array = []
	var ammo := _entry("AMMO", 3, 10, "pickup", 3, true)
	var fire := _entry("FIRE_ONE", 4, 10, "fire", 1, true)
	_expect(CombatNetworkCoordinator.record_correlated_result(history, ammo), "ammo result recorded")
	_expect(CombatNetworkCoordinator.record_correlated_result(history, fire), "fire result recorded")
	var matches := CombatNetworkCoordinator.matching_results(history, 1, "FIRE_ONE", 4, 10, "fire", 1)
	_expect(matches.size() == 1 and bool(matches[0]["accepted"]), "accepted ammo history cannot block accepted fire")
	_expect(not CombatNetworkCoordinator.record_correlated_result(history, fire), "duplicate callback deduplicated")
	_expect(CombatNetworkCoordinator.matching_results(history, 1, "AMMO", 4, 10, "fire", 1).is_empty(), "late prior-stage callback excluded")
	_expect(CombatNetworkCoordinator.matching_results(history, 1, "FIRE_ONE", 4, 11, "fire", 1).is_empty(), "other peer excluded")
	_expect(CombatNetworkCoordinator.matching_results(history, 1, "FIRE_ONE", 4, 10, "fire", 2).is_empty(), "other sequence excluded")
	var rejected := _entry("FIRE_ONE", 5, 10, "fire", 2, false)
	CombatNetworkCoordinator.record_correlated_result(history, rejected)
	matches = CombatNetworkCoordinator.matching_results(history, 1, "FIRE_ONE", 5, 10, "fire", 2)
	_expect(matches.size() == 1 and not bool(matches[0]["accepted"]), "rejected fire remains rejected after accepted pickup")

func _test_headless_input_policy() -> void:
	_expect(not NetworkConfig.should_poll_human_input(true, 0, false, true, false), "headless combat test never polls InputMap")
	_expect(not NetworkConfig.should_poll_human_input(true, 0, false, false, false), "headless normal client never polls InputMap")
	_expect(NetworkConfig.should_poll_human_input(true, 0, false, false, true), "graphical client preserves human input")
	_expect(not NetworkConfig.should_poll_human_input(false, 0, false, false, true), "disconnected graphical client stops input")

func _world_state(position: Vector3) -> Dictionary:
	return {"position": position, "velocity": Vector3.ZERO, "input": Vector2.ZERO, "yaw": 0.0}

func _test_lane_validation() -> void:
	var safe: Array = CombatNetworkCoordinator.SAFE_POSITIONS
	var states := {10: _world_state(CombatNetworkCoordinator.LANE_SHOOTER), 11: _world_state(CombatNetworkCoordinator.LANE_TARGET),
		12: _world_state(safe[0]), 13: _world_state(safe[1])}
	var alive := {10: true, 11: true, 12: true, 13: true}
	_expect(CombatNetworkCoordinator.validate_test_lane(states, alive, 10, 11).is_empty(), "distinct official lane accepted")
	states[10]["pitch"] = 0.3
	_expect(CombatNetworkCoordinator.validate_test_lane(states, alive, 10, 11) == "pitch_not_applied", "a tilted shooter is not a level lane")
	states[10]["pitch"] = 0.0
	states[12]["position"] = states[10]["position"]
	_expect(CombatNetworkCoordinator.validate_test_lane(states, alive, 10, 11) != "", "overlapping participant rejected")
	states[12]["position"] = CombatNetworkCoordinator.LANE_SHOOTER.lerp(CombatNetworkCoordinator.LANE_TARGET, 0.5)
	_expect(CombatNetworkCoordinator.validate_test_lane(states, alive, 10, 11) != "", "intermediate participant rejected")
	states[12]["position"] = safe[0]
	states[13]["velocity"] = Vector3.ONE
	_expect(CombatNetworkCoordinator.validate_test_lane(states, alive, 10, 11) == "participant_moving", "late position with residual movement rejected")
	states[13]["velocity"] = Vector3.ZERO
	states[11]["position"] = CombatNetworkCoordinator.LANE_TARGET + Vector3(0, 0, 1)
	_expect(CombatNetworkCoordinator.validate_test_lane(states, alive, 10, 11) == "position_not_applied", "unexpected target position rejected")

func _post_result(peer_id: int, action: String) -> Dictionary:
	return {"round_id": 2, "stage": "POST_END", "command_id": 12, "peer_id": peer_id,
		"action": action, "sequence": 63, "accepted": false, "reason": "round_not_active"}

func _test_post_end_correlation() -> void:
	var peers := [10, 11, 12, 13]
	var acks := {10: true, 11: true, 12: true, 13: true}
	var results: Array = []
	for action in ["reload", "pickup", "fire"]:
		for peer_id in peers: results.append(_post_result(peer_id, action))
	_expect(CombatNetworkCoordinator.post_end_complete(acks, results, peers, 2, 12, 63), "four same-command ACKs and shuffled rejections complete")
	var missing_ack := acks.duplicate(); missing_ack.erase(13)
	_expect(not CombatNetworkCoordinator.post_end_complete(missing_ack, results, peers, 2, 12, 63), "missing ACK blocks completion")
	var missing_result := results.duplicate(); missing_result.pop_back()
	_expect(not CombatNetworkCoordinator.post_end_complete(acks, missing_result, peers, 2, 12, 63), "missing rejection blocks completion")
	var duplicate := results.duplicate(); duplicate.append(results[0])
	_expect(not CombatNetworkCoordinator.post_end_complete(acks, duplicate, peers, 2, 12, 63), "duplicate result rejected")
	_expect(CombatNetworkCoordinator.post_end_complete(acks, results, peers, 2, 12, 63), "ACK before or after rejection order is equivalent")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
