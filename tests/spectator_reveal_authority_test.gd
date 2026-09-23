extends SceneTree

const BASE := 1000
var failures := 0
var checks := 0

func _initialize() -> void:
	_test_reveal_lifecycle()
	_test_spectator_authorization()
	_test_no_targets_is_safe()
	_test_stale_reset_cannot_reveal()
	if failures:
		push_error("SPECTATOR_REVEAL_AUTHORITY_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("SPECTATOR_REVEAL_AUTHORITY_TEST_OK checks=%d" % checks)
	quit(0)

func _test_reveal_lifecycle() -> void:
	var authority := _authority()
	_expect(authority.get_final_reveal().is_empty(), "reveal is empty in WAITING")
	_join_four(authority)
	_expect(authority.state == RoundState.COUNTDOWN and authority.get_final_reveal().is_empty(), "reveal is empty in COUNTDOWN")
	authority.tick(BASE + 10)
	_expect(authority.state == RoundState.ACTIVE and authority.get_final_reveal().is_empty(), "reveal is empty in ACTIVE")
	var official := {}
	for peer_id in authority.participants: official[int(peer_id)] = authority.get_role_for_peer(int(peer_id))
	var reveal_events := [0]
	authority.reveal_ready.connect(func(_round_id: int, _result: Dictionary): reveal_events[0] += 1)
	var assassin := _role_peer(authority, Role.ASSASSIN)
	_expect(authority.eliminate_player(assassin, "test", 0, BASE + 20).is_empty(), "official elimination ends the round")
	var reveal := authority.get_final_reveal()
	_expect(authority.state == RoundState.ENDED and not reveal.is_empty(), "reveal exists only in ENDED")
	_expect(reveal.keys().size() == 4 and reveal.has("round_id") and reveal.has("winning_team") and reveal.has("reason") and reveal.has("players"), "reveal uses the exact public allowlist")
	_expect(not reveal.has("health") and not reveal.has("inventory") and not reveal.has("ammo") and not reveal.has("seed"), "reveal excludes private combat and seed data")
	var revealed := {}
	for player in reveal["players"]:
		_expect((player as Dictionary).keys().size() == 3, "participant reveal has only public identity and role")
		revealed[int(player["peer_id"])] = int(player["role"])
	_expect(revealed == official, "reveal contains exactly the server roles")
	_expect(reveal_events[0] == 1, "reveal is emitted once")
	authority.eliminate_player(101, "test", 0, BASE + 21)
	_expect(reveal_events[0] == 1, "ENDED cannot emit a duplicate reveal")
	authority.tick(BASE + 30)
	_expect(authority.get_final_reveal().is_empty(), "next round removes the previous reveal")
	_expect(not authority.has_roles(), "role map does not survive reset")

func _test_spectator_authorization() -> void:
	var authority := _active()
	var dead := _role_peer(authority, Role.DETECTIVE)
	var other_dead := _role_peer(authority, Role.VICTIM)
	_expect(authority.spectator_targets_for(dead).is_empty(), "living player receives no spectator targets")
	authority.eliminate_player(dead, "test", 0, BASE + 20)
	var targets := authority.spectator_targets_for(dead)
	_expect(targets.size() == 3, "eliminated player receives all living targets")
	_expect(dead not in targets, "dead player cannot observe self")
	_expect(authority.can_spectate(dead, int(targets[0])), "listed target is authorized")
	_expect(not authority.can_spectate(dead, dead) and not authority.can_spectate(dead, 9999), "self and arbitrary targets are rejected")
	_expect(authority.spectator_targets_for(int(targets[0])).is_empty(), "living player cannot enter spectator")
	authority.eliminate_player(other_dead, "test", 0, BASE + 21)
	_expect(other_dead not in authority.spectator_targets_for(dead), "eliminated target is removed")
	var disconnected := int(authority.spectator_targets_for(dead)[0])
	authority.leave(disconnected, BASE + 22)
	_expect(disconnected not in authority.spectator_targets_for(dead), "disconnected target is removed")
	_expect(not authority.can_spectate(dead, disconnected), "stale disconnected target is rejected")

func _test_no_targets_is_safe() -> void:
	var authority := _active()
	var assassin := _role_peer(authority, Role.ASSASSIN)
	for peer_id in authority.participants.keys():
		if int(peer_id) != assassin:
			authority.eliminate_player(int(peer_id), "test", assassin, BASE + 20)
	_expect(authority.spectator_targets_for(_role_peer(authority, Role.VICTIM)).is_empty(), "no living target produces a safe empty list")

func _test_stale_reset_cannot_reveal() -> void:
	var authority := _active()
	var first := authority.round_id
	authority.eliminate_player(_role_peer(authority, Role.ASSASSIN), "test", 0, BASE + 20)
	authority.tick(BASE + 30)
	_expect(authority.round_id == first + 1 and authority.get_final_reveal().is_empty(), "new round id starts without old reveal")
	authority.tick(BASE + 10000)
	_expect(authority.get_final_reveal().is_empty(), "stale callback cannot reveal an old round")

func _authority() -> RoundAuthority:
	var value := RoundAuthority.new(LobbyRegistry.new(), 12345)
	value.configure(0.001, 0.001)
	return value

func _join_four(authority: RoundAuthority) -> void:
	for index in 4: _expect(authority.join(101 + index, "client-%d" % (index + 1), BASE).is_empty(), "player joins")

func _active() -> RoundAuthority:
	var authority := _authority()
	_join_four(authority)
	authority.tick(BASE + 10)
	return authority

func _role_peer(authority: RoundAuthority, role: int) -> int:
	for peer_id in authority.participants:
		if authority.get_role_for_peer(int(peer_id)) == role: return int(peer_id)
	return 0

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error("SPECTATOR_REVEAL_AUTHORITY_CHECK_FAILED %s" % description)
