extends SceneTree

## Testes determinísticos das regras puras da rodada. Não dependem de rede,
## de cenas nem de renderização.

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_state_machine_transitions()
	_test_capacity_rules()
	_test_role_distribution_four_players()
	_test_role_distribution_eight_players()
	_test_seed_determinism()
	_test_seed_variation()
	_test_assignment_ignores_connection_order()
	_test_win_conditions()
	_test_sanitizers_reject_invalid_values()
	if failures > 0:
		push_error("ROUND_RULES_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("ROUND_RULES_TEST_OK checks=%d" % checks)
	quit(0)

# 5. Transições inválidas são rejeitadas.
func _test_state_machine_transitions() -> void:
	_expect(RoundState.is_valid_transition(RoundState.WAITING, RoundState.COUNTDOWN), "waiting->countdown allowed")
	_expect(RoundState.is_valid_transition(RoundState.COUNTDOWN, RoundState.ACTIVE), "countdown->active allowed")
	_expect(RoundState.is_valid_transition(RoundState.COUNTDOWN, RoundState.WAITING), "countdown->waiting allowed")
	_expect(RoundState.is_valid_transition(RoundState.ACTIVE, RoundState.ENDED), "active->ended allowed")
	_expect(RoundState.is_valid_transition(RoundState.ENDED, RoundState.WAITING), "ended->waiting allowed")
	_expect(RoundState.is_valid_transition(RoundState.ENDED, RoundState.COUNTDOWN), "ended->countdown allowed")
	_expect(not RoundState.is_valid_transition(RoundState.WAITING, RoundState.ACTIVE), "waiting->active rejected")
	_expect(not RoundState.is_valid_transition(RoundState.WAITING, RoundState.ENDED), "waiting->ended rejected")
	_expect(not RoundState.is_valid_transition(RoundState.ACTIVE, RoundState.COUNTDOWN), "active->countdown rejected")
	_expect(not RoundState.is_valid_transition(RoundState.ACTIVE, RoundState.WAITING), "active->waiting rejected")
	_expect(not RoundState.is_valid_transition(RoundState.ENDED, RoundState.ACTIVE), "ended->active rejected")
	_expect(not RoundState.is_valid_transition(RoundState.ACTIVE, RoundState.ACTIVE), "active->active rejected")
	_expect(not RoundState.is_valid_transition(-1, RoundState.ACTIVE), "unknown source rejected")
	_expect(not RoundState.is_valid_transition(RoundState.WAITING, 99), "unknown target rejected")
	_expect(RoundState.reveals_alive(RoundState.ACTIVE), "active reveals alive")
	_expect(not RoundState.reveals_alive(RoundState.WAITING), "waiting hides alive")

# 2, 3 e 18. Limites de 4 a 8 jogadores.
func _test_capacity_rules() -> void:
	_expect(not RoundRules.can_start_countdown(0), "zero players cannot start")
	_expect(not RoundRules.can_start_countdown(3), "three players cannot start")
	_expect(RoundRules.can_start_countdown(4), "four players can start")
	_expect(RoundRules.can_start_countdown(8), "eight players can start")
	_expect(not RoundRules.can_start_countdown(9), "nine players cannot start")
	_expect(RoundRules.MIN_PLAYERS == 4 and RoundRules.MAX_PLAYERS == 8, "configured player bounds")

# 6. Rodada com 4 jogadores: 1 assassino, 1 detetive, 2 vítimas.
func _test_role_distribution_four_players() -> void:
	var roles := RoundRules.assign_roles([10, 11, 12, 13], _rng(1234))
	var counts := RoundRules.role_counts(roles)
	_expect(roles.size() == 4, "four roles assigned")
	_expect(int(counts["assassin"]) == 1, "four players: one assassin")
	_expect(int(counts["detective"]) == 1, "four players: one detective")
	_expect(int(counts["victim"]) == 2, "four players: two victims")
	_expect(RoundRules.is_valid_distribution(roles), "four player distribution is valid")

# 7. Rodada com 8 jogadores: 1 assassino, 1 detetive, 6 vítimas.
func _test_role_distribution_eight_players() -> void:
	var roles := RoundRules.assign_roles([1, 2, 3, 4, 5, 6, 7, 8], _rng(99))
	var counts := RoundRules.role_counts(roles)
	_expect(roles.size() == 8, "eight roles assigned")
	_expect(int(counts["assassin"]) == 1, "eight players: one assassin")
	_expect(int(counts["detective"]) == 1, "eight players: one detective")
	_expect(int(counts["victim"]) == 6, "eight players: six victims")
	_expect(RoundRules.is_valid_distribution(roles), "eight player distribution is valid")

# 8. A mesma seed gera a mesma distribuição.
func _test_seed_determinism() -> void:
	var peers := [21, 22, 23, 24, 25]
	var first := RoundRules.assign_roles(peers, _rng(4242))
	var second := RoundRules.assign_roles(peers, _rng(4242))
	_expect(first == second, "same seed produces the same distribution")

# 9. Seeds diferentes podem gerar distribuições diferentes.
func _test_seed_variation() -> void:
	var peers := [31, 32, 33, 34, 35, 36]
	var baseline := RoundRules.assign_roles(peers, _rng(1))
	var differs := false
	for seed_value in range(2, 40):
		if RoundRules.assign_roles(peers, _rng(seed_value)) != baseline:
			differs = true
			break
	_expect(differs, "different seeds can produce different distributions")

## O sorteio não pode favorecer a ordem de conexão: sobre muitas seeds, o
## primeiro peer a entrar não pode concentrar o papel de assassino.
func _test_assignment_ignores_connection_order() -> void:
	var peers := [41, 42, 43, 44]
	var first_peer_assassin := 0
	var samples := 400
	for seed_value in samples:
		var roles := RoundRules.assign_roles(peers, _rng(seed_value))
		if int(roles.get(41, Role.NONE)) == Role.ASSASSIN:
			first_peer_assassin += 1
	var share := float(first_peer_assassin) / float(samples)
	_expect(share > 0.15 and share < 0.35, "join order does not bias the draw (share=%.3f)" % share)

# 12, 13 e 14. Condições de vitória.
func _test_win_conditions() -> void:
	var roles := {1: Role.ASSASSIN, 2: Role.DETECTIVE, 3: Role.VICTIM, 4: Role.VICTIM}
	var all_alive := {1: true, 2: true, 3: true, 4: true}
	_expect(RoundRules.evaluate_winner(roles, all_alive).is_empty(), "no winner while everyone is alive")

	var assassin_dead := {1: false, 2: true, 3: true, 4: true}
	var innocents_win := RoundRules.evaluate_winner(roles, assassin_dead)
	_expect(int(innocents_win.get("team", Role.TEAM_NONE)) == Role.TEAM_INNOCENTS, "dead assassin gives innocents the win")
	_expect(str(innocents_win.get("reason", "")) == RoundRules.REASON_ASSASSIN_DOWN, "innocent win reason is public")

	var innocents_dead := {1: true, 2: false, 3: false, 4: false}
	var assassin_win := RoundRules.evaluate_winner(roles, innocents_dead)
	_expect(int(assassin_win.get("team", Role.TEAM_NONE)) == Role.TEAM_ASSASSIN, "no living innocent gives the assassin the win")
	_expect(str(assassin_win.get("reason", "")) == RoundRules.REASON_INNOCENTS_DOWN, "assassin win reason is public")

	var detective_dead := {1: true, 2: false, 3: true, 4: true}
	_expect(RoundRules.evaluate_winner(roles, detective_dead).is_empty(), "dead detective alone does not end the round")

	_expect(RoundRules.evaluate_winner({}, {}).is_empty(), "empty round has no winner")

# 20. Valores inválidos não corrompem o sorteio nem o resultado.
func _test_sanitizers_reject_invalid_values() -> void:
	_expect(RoundRules.assign_roles([1, 2, 3], _rng(7)).is_empty(), "three players are not enough to draw")
	_expect(RoundRules.assign_roles([1, 2, 3, 4, 5, 6, 7, 8, 9], _rng(7)).is_empty(), "nine players are too many to draw")
	_expect(RoundRules.assign_roles([1, 2, 3, 4], null).is_empty(), "missing rng aborts the draw")
	_expect(RoundRules.assign_roles([1, 1, 2, 3], _rng(7)).is_empty(), "duplicated peer aborts the draw")
	_expect(not RoundRules.is_valid_distribution({1: Role.ASSASSIN, 2: Role.ASSASSIN, 3: Role.VICTIM, 4: Role.VICTIM}), "two assassins is an invalid distribution")
	_expect(not RoundRules.is_valid_distribution({}), "empty distribution is invalid")

	_expect(RoundRules.sanitize_cause("TEST") == "test", "cause is normalised")
	_expect(RoundRules.sanitize_cause("  disconnect  ") == "disconnect", "cause is trimmed")
	_expect(RoundRules.sanitize_cause("peer_7_was_the_ASSASSIN") == RoundRules.DEFAULT_CAUSE, "unknown cause is discarded")
	_expect(RoundRules.sanitize_cause("") == RoundRules.DEFAULT_CAUSE, "empty cause is discarded")

	_expect(RoundRules.validate_label("client-1").is_empty(), "valid label accepted")
	_expect(not RoundRules.validate_label("").is_empty(), "empty label rejected")
	_expect(not RoundRules.validate_label("   ").is_empty(), "blank label rejected")
	_expect(not RoundRules.validate_label("bad label!").is_empty(), "label with symbols rejected")
	_expect(not RoundRules.validate_label("x".repeat(RoundRules.MAX_LABEL_LENGTH + 1)).is_empty(), "oversized label rejected")

	_expect(is_equal_approx(RoundRules.sanitize_countdown_seconds(NAN), RoundRules.COUNTDOWN_SECONDS), "non finite countdown falls back")
	_expect(is_equal_approx(RoundRules.sanitize_countdown_seconds(-5.0), RoundRules.MIN_COUNTDOWN_SECONDS), "negative countdown is clamped")
	_expect(is_equal_approx(RoundRules.sanitize_countdown_seconds(10000.0), RoundRules.MAX_COUNTDOWN_SECONDS), "huge countdown is clamped")

	_expect(Role.is_innocent(Role.DETECTIVE) and Role.is_innocent(Role.VICTIM), "detective and victim are innocents")
	_expect(not Role.is_innocent(Role.ASSASSIN) and not Role.is_innocent(Role.NONE), "assassin and none are not innocents")
	_expect(not Role.is_valid(Role.NONE) and not Role.is_valid(42), "invalid roles are rejected")

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("ROUND_RULES_CHECK_FAILED %s" % description)
	print("ROUND_RULES_CHECK_FAILED %s" % description)
