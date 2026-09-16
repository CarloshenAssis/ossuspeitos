extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_correlated_history()
	_test_headless_input_policy()
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

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
