extends SceneTree

const BASE := 1000
const COUNTDOWN_MSEC := 500
const END_DELAY_MSEC := 500
var failures := 0
var checks := 0

func _initialize() -> void:
	_test_reveal_lifecycle()
	_test_spectator_authorization()
	_test_no_targets_is_safe()
	_test_empty_target_list_is_safe()
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
	authority.tick(_active_msec())
	_expect(authority.state == RoundState.ACTIVE and authority.get_final_reveal().is_empty(), "reveal is empty in ACTIVE")
	var official: Dictionary = {}
	for peer_id in authority.participants:
		official[int(peer_id)] = Role.to_label(authority.get_role_for_peer(int(peer_id)))
	var reveal_events := [0]
	authority.reveal_ready.connect(func(_round_id: int, _result: Dictionary): reveal_events[0] += 1)
	var assassin := _role_peer(authority, Role.ASSASSIN)
	_expect(authority.eliminate_player(assassin, "test", 0, _active_msec() + 1).is_empty(), "official elimination ends the round")
	var reveal: Dictionary = authority.get_final_reveal()
	_expect(authority.state == RoundState.ENDED and not reveal.is_empty(), "reveal exists only in ENDED")
	_expect(reveal.keys().size() == 4 and reveal.has("round_id") and reveal.has("winner") and reveal.has("reason") and reveal.has("players"), "reveal uses the exact public allowlist")
	_expect(not reveal.has("health") and not reveal.has("inventory") and not reveal.has("ammo") and not reveal.has("seed"), "reveal excludes private combat and seed data")
	_expect(typeof(reveal.get("round_id")) == TYPE_INT and typeof(reveal.get("winner")) == TYPE_STRING \
		and typeof(reveal.get("reason")) == TYPE_STRING and typeof(reveal.get("players")) == TYPE_ARRAY,
		"reveal fields have public DTO types")
	var revealed: Dictionary = {}
	var players: Array = reveal.get("players", [])
	for raw_player in players:
		var player: Dictionary = raw_player
		_expect(player.keys().size() == 2 and player.has("peer_id") and player.has("role"), "participant reveal has only peer id and role")
		_expect(typeof(player.get("peer_id")) == TYPE_INT and typeof(player.get("role")) == TYPE_STRING, "participant reveal fields use public DTO types")
		revealed[int(player["peer_id"])] = str(player["role"])
	_expect(revealed == official, "reveal contains exactly the server roles")
	_expect(reveal_events[0] == 1, "reveal is emitted once")
	authority.eliminate_player(101, "test", 0, _active_msec() + 2)
	_expect(reveal_events[0] == 1, "ENDED cannot emit a duplicate reveal")
	authority.tick(_reset_msec())
	_expect(authority.get_final_reveal().is_empty(), "next round removes the previous reveal")
	_expect(not authority.has_roles(), "role map does not survive reset")

func _test_spectator_authorization() -> void:
	var authority := _active()
	var dead := _role_peer(authority, Role.DETECTIVE)
	var other_dead := _role_peer(authority, Role.VICTIM)
	_expect(authority.get_spectator_state(dead).is_empty(), "living player receives no spectator state")
	authority.eliminate_player(dead, "test", 0, _active_msec() + 1)
	var spectator_state: Dictionary = authority.get_spectator_state(dead)
	_expect(spectator_state.keys().size() == 2 and spectator_state.has("round_id") and spectator_state.has("targets"), "dead player receives the exact spectator DTO")
	_expect(int(spectator_state.get("round_id", 0)) == authority.round_id, "spectator DTO belongs to the active round")
	var targets: Array = spectator_state.get("targets", [])
	_expect(targets.size() == 3, "eliminated player receives all living targets")
	_expect(dead not in targets, "dead player cannot observe self")
	_expect(not targets.is_empty() and authority.can_spectate(dead, int(targets[0])), "listed target is authorized")
	_expect(not authority.can_spectate(dead, dead) and not authority.can_spectate(dead, 9999), "self and arbitrary targets are rejected")
	if not targets.is_empty():
		_expect(authority.get_spectator_state(int(targets[0])).is_empty(), "living player cannot enter spectator")
	authority.eliminate_player(other_dead, "test", 0, _active_msec() + 2)
	var after_elimination: Dictionary = authority.get_spectator_state(dead)
	var targets_after_elimination: Array = after_elimination.get("targets", [])
	_expect(other_dead not in targets_after_elimination, "eliminated target is removed")
	_expect(not targets_after_elimination.is_empty(), "a connected living target remains available")
	var disconnected := int(targets_after_elimination[0]) if not targets_after_elimination.is_empty() else 0
	if disconnected > 0:
		authority.leave(disconnected, _active_msec() + 3)
	var after_disconnect: Dictionary = authority.get_spectator_state(dead)
	var targets_after_disconnect: Array = after_disconnect.get("targets", [])
	_expect(disconnected <= 0 or disconnected not in targets_after_disconnect, "disconnected target is removed")
	_expect(not authority.can_spectate(dead, disconnected), "stale disconnected target is rejected")
	authority.leave(dead, _active_msec() + 4)
	_expect(authority.get_spectator_state(dead).is_empty(), "disconnected spectator receives no DTO")

func _test_no_targets_is_safe() -> void:
	var authority := _active()
	var assassin := _role_peer(authority, Role.ASSASSIN)
	for peer_id in authority.participants.keys():
		if int(peer_id) != assassin:
			authority.eliminate_player(int(peer_id), "test", assassin, _active_msec() + 1)
	_expect(authority.state == RoundState.ENDED, "removing every innocent ends the round")
	_expect(authority.get_spectator_state(_role_peer(authority, Role.VICTIM)).is_empty(), "ended round exposes no spectator DTO")

func _test_empty_target_list_is_safe() -> void:
	var authority := _active()
	var dead := _role_peer(authority, Role.DETECTIVE)
	authority.eliminate_player(dead, "test", 0, _active_msec() + 1)
	# Isola a filtragem do DTO sem disparar a transicao de vitoria, cobrindo o
	# contrato defensivo de lista vazia para um eliminado sem alvo elegivel.
	for peer_id in authority.participants:
		if int(peer_id) != dead:
			authority.alive[int(peer_id)] = false
	var spectator_state: Dictionary = authority.get_spectator_state(dead)
	_expect(not spectator_state.is_empty(), "eliminated player keeps a spectator DTO with no eligible targets")
	var targets: Array = spectator_state.get("targets", [])
	_expect(targets.is_empty(), "spectator DTO safely carries an empty target list")

func _test_stale_reset_cannot_reveal() -> void:
	var authority := _active()
	var first := authority.round_id
	authority.eliminate_player(_role_peer(authority, Role.ASSASSIN), "test", 0, _active_msec() + 1)
	authority.tick(_reset_msec())
	_expect(authority.round_id == first + 1 and authority.get_final_reveal().is_empty(), "new round id starts without old reveal")
	authority.tick(BASE + 10000)
	_expect(authority.get_final_reveal().is_empty(), "stale callback cannot reveal an old round")

func _authority() -> RoundAuthority:
	var value := RoundAuthority.new(LobbyRegistry.new(), 12345)
	value.configure(float(COUNTDOWN_MSEC) / 1000.0, float(END_DELAY_MSEC) / 1000.0)
	return value

func _join_four(authority: RoundAuthority) -> void:
	for index in 4: _expect(authority.join(101 + index, "client-%d" % (index + 1), BASE).is_empty(), "player joins")

func _active() -> RoundAuthority:
	var authority := _authority()
	_join_four(authority)
	authority.tick(_active_msec())
	return authority

func _active_msec() -> int:
	return BASE + COUNTDOWN_MSEC

func _reset_msec() -> int:
	return _active_msec() + 1 + END_DELAY_MSEC

func _role_peer(authority: RoundAuthority, role: int) -> int:
	for peer_id in authority.participants:
		if authority.get_role_for_peer(int(peer_id)) == role: return int(peer_id)
	return 0

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error("SPECTATOR_REVEAL_AUTHORITY_CHECK_FAILED %s" % description)
