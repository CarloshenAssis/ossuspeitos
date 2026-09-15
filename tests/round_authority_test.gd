extends SceneTree

## Testes headless da autoridade da rodada. Todo o tempo é injetado, portanto
## os resultados são determinísticos e independentes de rede e renderização.

const BASE_MSEC := 10_000
const COUNTDOWN_SECONDS := 1.0
const END_DELAY_SECONDS := 1.0
const SEED := 20_250_915

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_initial_state_is_waiting()
	_test_three_players_do_not_start()
	_test_four_players_start_countdown()
	_test_losing_a_player_during_countdown_returns_to_waiting()
	_test_invalid_transitions_are_rejected()
	_test_round_of_four_has_one_assassin_and_one_detective()
	_test_round_of_eight_has_one_assassin_and_one_detective()
	_test_everyone_starts_alive()
	_test_duplicate_elimination_is_rejected()
	_test_dead_assassin_gives_innocents_the_win()
	_test_dead_innocents_give_the_assassin_the_win()
	_test_dead_detective_alone_does_not_end_the_round()
	_test_assassin_disconnect_gives_innocents_the_win()
	_test_detective_disconnect_does_not_end_the_round()
	_test_late_join_waits_for_the_next_round()
	_test_reset_clears_roles_alive_winner_and_timers()
	_test_lobby_accepts_four_to_eight_players()
	_test_ninth_player_is_rejected()
	_test_invalid_values_do_not_corrupt_the_round()
	_test_public_payloads_never_carry_roles()
	_test_eliminations_are_recorded_sanitised()
	if failures > 0:
		push_error("ROUND_AUTHORITY_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("ROUND_AUTHORITY_TEST_OK checks=%d" % checks)
	quit(0)

# 1. Estado inicial é WAITING.
func _test_initial_state_is_waiting() -> void:
	var authority := _authority()
	_expect(authority.state == RoundState.WAITING, "initial state is WAITING")
	_expect(authority.round_id == 0, "initial round id is zero")
	_expect(authority.participants.is_empty(), "no participants before the first round")
	_expect(not authority.has_roles(), "no roles before the first round")
	_expect(authority.winning_team == Role.TEAM_NONE, "no winner before the first round")

# 2. Menos de 4 jogadores não inicia countdown.
func _test_three_players_do_not_start() -> void:
	var authority := _with_players(3)
	_expect(authority.state == RoundState.WAITING, "three players stay in WAITING")
	authority.tick(BASE_MSEC + 60_000)
	_expect(authority.state == RoundState.WAITING, "time alone does not start a short round")
	_expect(not authority.has_roles(), "three players get no roles")

# 3. Quatro jogadores permitem countdown.
func _test_four_players_start_countdown() -> void:
	var authority := _with_players(4)
	_expect(authority.state == RoundState.COUNTDOWN, "four players start the countdown")
	_expect(authority.round_id == 1, "countdown opens round 1")
	_expect(authority.countdown_remaining_msec(BASE_MSEC) == int(COUNTDOWN_SECONDS * 1000.0), "countdown publishes the remaining time")
	_expect(not authority.has_roles(), "roles are not drawn during the countdown")
	# Um quinto jogador não reinicia o countdown nem abre uma segunda rodada.
	var deadline_before := authority.countdown_remaining_msec(BASE_MSEC)
	authority.join(500, "client-5", BASE_MSEC + 100)
	_expect(authority.state == RoundState.COUNTDOWN, "a fifth player keeps the same countdown")
	_expect(authority.round_id == 1, "a fifth player does not open a second round")
	_expect(authority.countdown_remaining_msec(BASE_MSEC) == deadline_before, "the countdown deadline is untouched")
	authority.tick(_after_countdown())
	_expect(authority.state == RoundState.ACTIVE, "the countdown reaches ACTIVE")
	_expect(authority.participants.size() == 5, "everyone present at the start joins the round")

# 4. Perder um jogador no countdown volta para WAITING.
func _test_losing_a_player_during_countdown_returns_to_waiting() -> void:
	var authority := _with_players(4)
	_expect(authority.state == RoundState.COUNTDOWN, "countdown running before the disconnect")
	authority.leave(100, BASE_MSEC + 200)
	_expect(authority.state == RoundState.WAITING, "losing a player cancels the countdown")
	_expect(authority.countdown_remaining_msec(BASE_MSEC + 200) == 0, "the cancelled countdown publishes no time")
	authority.tick(_after_countdown())
	_expect(authority.state == RoundState.WAITING, "the cancelled deadline never starts the round")
	_expect(not authority.has_roles(), "a cancelled countdown draws no roles")
	# Recompor o lobby reabre o countdown com um novo identificador de rodada.
	authority.join(900, "client-9", BASE_MSEC + 300)
	_expect(authority.state == RoundState.COUNTDOWN, "the lobby restarts the countdown")
	_expect(authority.round_id == 2, "the restarted countdown renews the round id")

# 5. Transições inválidas são rejeitadas.
func _test_invalid_transitions_are_rejected() -> void:
	var authority := _authority()
	authority.reset_for_next_round(BASE_MSEC)
	_expect(authority.state == RoundState.WAITING, "WAITING->WAITING leaves the state untouched")
	_expect(authority.invalid_transition_count == 1, "WAITING->WAITING is recorded as invalid")

	var active := _active_round(4)
	var before := active.invalid_transition_count
	active.reset_for_next_round(_after_countdown())
	_expect(active.state == RoundState.ACTIVE, "ACTIVE->WAITING is refused")
	_expect(active.invalid_transition_count == before + 1, "ACTIVE->WAITING is recorded as invalid")
	_expect(active.participants.size() == 4, "the refused transition keeps the participants")
	_expect(active.has_roles(), "the refused transition keeps the roles")

# 6. Rodada com 4 jogadores contém 1 ASSASSIN, 1 DETECTIVE e 2 VICTIM.
func _test_round_of_four_has_one_assassin_and_one_detective() -> void:
	var authority := _active_round(4)
	var counts := authority.role_counts()
	_expect(int(counts["assassin"]) == 1, "four players: exactly one assassin")
	_expect(int(counts["detective"]) == 1, "four players: exactly one detective")
	_expect(int(counts["victim"]) == 2, "four players: exactly two victims")

# 7. Rodada com 8 jogadores contém 1 ASSASSIN, 1 DETECTIVE e 6 VICTIM.
func _test_round_of_eight_has_one_assassin_and_one_detective() -> void:
	var authority := _active_round(8)
	var counts := authority.role_counts()
	_expect(int(counts["assassin"]) == 1, "eight players: exactly one assassin")
	_expect(int(counts["detective"]) == 1, "eight players: exactly one detective")
	_expect(int(counts["victim"]) == 6, "eight players: exactly six victims")

# 10. Todos começam vivos.
func _test_everyone_starts_alive() -> void:
	var authority := _active_round(6)
	_expect(authority.alive_count() == 6, "every participant starts alive")
	for peer_id in authority.participants:
		if not authority.is_alive(peer_id):
			_expect(false, "participant %d started dead" % peer_id)
			return
	_expect(true, "no participant started dead")

# 11. Eliminação duplicada é rejeitada.
func _test_duplicate_elimination_is_rejected() -> void:
	var authority := _active_round(4)
	var victim := _peer_with_role(authority, Role.VICTIM)
	var now := _after_countdown()
	_expect(authority.eliminate_player(victim, "test", 0, now).is_empty(), "first elimination is accepted")
	_expect(authority.eliminate_player(victim, "test", 0, now) == "already_eliminated", "second elimination is rejected")
	_expect(authority.alive_count() == 3, "the duplicate elimination changed nothing")

# 12. Morte do assassino dá vitória aos inocentes.
func _test_dead_assassin_gives_innocents_the_win() -> void:
	var authority := _active_round(4)
	var assassin := _peer_with_role(authority, Role.ASSASSIN)
	var now := _after_countdown()
	_expect(authority.eliminate_player(assassin, "test", 0, now).is_empty(), "the assassin can be eliminated")
	_expect(authority.state == RoundState.ENDED, "the dead assassin ends the round")
	_expect(authority.winning_team == Role.TEAM_INNOCENTS, "the innocents win")
	_expect(authority.winner_reason == RoundRules.REASON_ASSASSIN_DOWN, "the public reason is the assassin being down")
	_expect(authority.eliminate_player(_peer_with_role(authority, Role.VICTIM), "test", 0, now) == "round_not_active", "ENDED refuses further eliminations")

# 13. Morte de todos os inocentes dá vitória ao assassino.
func _test_dead_innocents_give_the_assassin_the_win() -> void:
	var authority := _active_round(4)
	var assassin := _peer_with_role(authority, Role.ASSASSIN)
	var now := _after_countdown()
	var eliminated := 0
	for peer_id in authority.participants.keys():
		if peer_id == assassin:
			continue
		var reason := authority.eliminate_player(peer_id, "test", assassin, now)
		if reason.is_empty():
			eliminated += 1
	_expect(eliminated == 3, "the three innocents were eliminated")
	_expect(authority.state == RoundState.ENDED, "no living innocent ends the round")
	_expect(authority.winning_team == Role.TEAM_ASSASSIN, "the assassin wins")
	_expect(authority.winner_reason == RoundRules.REASON_INNOCENTS_DOWN, "the public reason is the innocents being down")
	_expect(authority.is_alive(assassin), "the assassin is still alive at the end")

# 14. Morte apenas do detetive não encerra a partida se houver vítima viva.
func _test_dead_detective_alone_does_not_end_the_round() -> void:
	var authority := _active_round(4)
	var detective := _peer_with_role(authority, Role.DETECTIVE)
	var now := _after_countdown()
	_expect(authority.eliminate_player(detective, "test", 0, now).is_empty(), "the detective can be eliminated")
	_expect(authority.state == RoundState.ACTIVE, "the dead detective alone does not end the round")
	_expect(authority.winning_team == Role.TEAM_NONE, "no winner while victims are alive")
	_expect(authority.alive_count() == 3, "only the detective died")

# 15. Desconexão do assassino dá vitória aos inocentes.
func _test_assassin_disconnect_gives_innocents_the_win() -> void:
	var authority := _active_round(4)
	var assassin := _peer_with_role(authority, Role.ASSASSIN)
	authority.leave(assassin, _after_countdown())
	_expect(authority.state == RoundState.ENDED, "the assassin leaving ends the round")
	_expect(authority.winning_team == Role.TEAM_INNOCENTS, "the assassin leaving gives the innocents the win")
	_expect(authority.winner_reason == RoundRules.REASON_ASSASSIN_DOWN, "the disconnect reuses the public reason")
	_expect(not authority.lobby.has(assassin), "the session was removed from the lobby")

## Desconexão do detetive é tratada como eliminação e não encerra a rodada.
func _test_detective_disconnect_does_not_end_the_round() -> void:
	var authority := _active_round(4)
	var detective := _peer_with_role(authority, Role.DETECTIVE)
	authority.leave(detective, _after_countdown())
	_expect(authority.state == RoundState.ACTIVE, "the detective leaving keeps the round running")
	_expect(not authority.is_alive(detective), "the detective who left counts as eliminated")
	_expect(authority.alive_count() == 3, "only the detective was lost")
	_expect(authority.is_participant(detective), "the participant list stays frozen")

# 16. Join tardio não participa da rodada ativa.
func _test_late_join_waits_for_the_next_round() -> void:
	var authority := _active_round(4)
	var now := _after_countdown()
	_expect(authority.join(700, "client-late", now).is_empty(), "the late player is accepted into the lobby")
	_expect(authority.state == RoundState.ACTIVE, "the late join does not disturb the round")
	_expect(authority.participants.size() == 4, "the late player is not a participant")
	_expect(not authority.is_participant(700), "the late player is outside the round")
	_expect(authority.get_role_for_peer(700) == Role.NONE, "the late player has no role")
	_expect(not authority.can_deliver_role(700), "no role is delivered to the late player")
	_expect(authority.is_waiting_for_next_round(700), "the late player waits for the next round")
	_expect(authority.waiting_peer_ids() == [700], "the waiting list holds only the late player")
	_expect(authority.eliminate_player(700, "test", 0, now) == "not_in_round", "the late player cannot be eliminated")

# 17. Reinício limpa papéis, vivos, vencedor e timers antigos.
func _test_reset_clears_roles_alive_winner_and_timers() -> void:
	var authority := _active_round(4)
	var now := _after_countdown()
	var first_round := authority.round_id
	var assassin := _peer_with_role(authority, Role.ASSASSIN)
	authority.eliminate_player(assassin, "test", 0, now)
	_expect(authority.state == RoundState.ENDED, "the round ended before the reset")

	# O atraso de encerramento é respeitado antes da limpeza.
	authority.tick(now + int(END_DELAY_SECONDS * 1000.0) - 1)
	_expect(authority.state == RoundState.ENDED, "the reset waits for the configured delay")

	authority.tick(now + int(END_DELAY_SECONDS * 1000.0))
	_expect(not authority.has_roles(), "the reset clears the role map")
	_expect(authority.participants.is_empty(), "the reset clears the participants")
	_expect(authority.alive.is_empty(), "the reset clears the alive states")
	_expect(authority.winning_team == Role.TEAM_NONE, "the reset clears the winner")
	_expect(authority.winner_reason.is_empty(), "the reset clears the public reason")
	_expect(authority.get_role_for_peer(assassin) == Role.NONE, "no role survives the reset")

	# Os quatro continuam conectados, portanto a rodada seguinte já é elegível.
	_expect(authority.state == RoundState.COUNTDOWN, "the still connected lobby opens the next round")
	_expect(authority.round_id == first_round + 1, "the next round renews the identifier")

	# O prazo de encerramento antigo não pode disparar sobre a rodada seguinte.
	authority.tick(now + int(END_DELAY_SECONDS * 1000.0) + 1)
	_expect(authority.state == RoundState.COUNTDOWN, "the stale end-of-round deadline does not fire")
	_expect(authority.round_id == first_round + 1, "the stale deadline did not renew the round id")

	# Com o lobby abaixo do mínimo, o reinício termina em WAITING.
	var shrinking := _active_round(4)
	var next_now := _after_countdown()
	var doomed := _peer_with_role(shrinking, Role.ASSASSIN)
	shrinking.eliminate_player(doomed, "test", 0, next_now)
	shrinking.leave(doomed, next_now)
	shrinking.tick(next_now + int(END_DELAY_SECONDS * 1000.0))
	_expect(shrinking.state == RoundState.WAITING, "a lobby below the minimum returns to WAITING")
	_expect(not shrinking.has_roles(), "the reset cleared the roles of the shrunken lobby")
	_expect(shrinking.participants.is_empty(), "the reset cleared the participants of the shrunken lobby")

# 18. O servidor aceita entre 4 e 8 jogadores.
func _test_lobby_accepts_four_to_eight_players() -> void:
	for count in range(RoundRules.MIN_PLAYERS, RoundRules.MAX_PLAYERS + 1):
		var authority := _active_round(count)
		_expect(authority.participants.size() == count, "a round of %d players starts" % count)
		_expect(RoundRules.is_valid_distribution(_roles_snapshot(authority)), "a round of %d players has a valid distribution" % count)

# 19. O nono jogador é rejeitado.
func _test_ninth_player_is_rejected() -> void:
	var authority := _with_players(8)
	_expect(authority.lobby.size() == 8, "eight sessions are registered")
	_expect(authority.join(999, "client-9", BASE_MSEC) == "room_unavailable", "the ninth player is rejected")
	_expect(authority.lobby.size() == 8, "the rejected player did not enter the lobby")
	authority.tick(_after_countdown())
	_expect(authority.participants.size() == 8, "the round still holds exactly eight participants")

# 20. Valores e estados inválidos não corrompem a rodada.
func _test_invalid_values_do_not_corrupt_the_round() -> void:
	var authority := _active_round(4)
	var now := _after_countdown()
	var alive_before := authority.alive_count()

	_expect(authority.eliminate_player(4242, "test", 0, now) == "unknown_peer", "an unknown peer cannot be eliminated")
	_expect(authority.eliminate_player(-1, "test", 0, now) == "unknown_peer", "a negative peer cannot be eliminated")
	_expect(authority.alive_count() == alive_before, "the refused eliminations changed no alive state")
	_expect(authority.state == RoundState.ACTIVE, "the refused eliminations kept the round active")

	var victim := _peer_with_role(authority, Role.VICTIM)
	_expect(authority.eliminate_player(victim, "peer_7_is_the_ASSASSIN", 0, now).is_empty(), "an unsanitised cause is still accepted")
	_expect(authority.alive_count() == alive_before - 1, "the sanitised elimination applied once")

	var lobby_authority := _authority()
	_expect(lobby_authority.join(0, "client-1", BASE_MSEC) == "invalid_client", "peer id zero is rejected")
	_expect(lobby_authority.join(101, "  ", BASE_MSEC) == "invalid_client", "a blank label is rejected")
	_expect(lobby_authority.join(101, "bad label!", BASE_MSEC) == "invalid_client", "a label with symbols is rejected")
	_expect(lobby_authority.join(101, "client-1", BASE_MSEC).is_empty(), "a valid session is accepted")
	_expect(lobby_authority.join(101, "client-other", BASE_MSEC) == "invalid_client", "a duplicated peer is rejected")
	_expect(lobby_authority.join(102, "client-1", BASE_MSEC) == "room_unavailable", "a duplicated label is rejected")
	_expect(lobby_authority.lobby.size() == 1, "the rejected sessions did not enter the lobby")
	lobby_authority.leave(4242, BASE_MSEC)
	_expect(lobby_authority.lobby.size() == 1, "leaving an unknown peer changes nothing")
	_expect(lobby_authority.eliminate_player(101, "test", 0, BASE_MSEC) == "round_not_active", "WAITING refuses eliminations")

## O estado público e o roster nunca podem carregar papel ou seed.
func _test_public_payloads_never_carry_roles() -> void:
	var authority := _active_round(4)
	var now := _after_countdown()
	var payload := authority.public_state(now)
	for key in payload:
		if str(key).to_lower().contains("role") or str(key).to_lower().contains("seed"):
			_expect(false, "public state exposes the key %s" % key)
			return
	_expect(payload.has("state") and payload.has("round_id"), "public state carries the round phase")
	_expect(int(payload["participants"]) == 4, "public state carries the participant count")

	var roster := authority.public_roster()
	_expect(roster.size() == 4, "the roster lists the connected sessions")
	for entry in roster:
		for key in (entry as Dictionary):
			if str(key).to_lower().contains("role"):
				_expect(false, "the roster exposes the key %s" % key)
				return
	_expect(true, "neither the public state nor the roster carries a role")

	var waiting := _authority()
	_expect(waiting.get_role_for_peer(1) == Role.NONE, "there is no role outside a round")

## A causa é sanitizada e o instigador validado antes de entrar no registro
## interno, que nunca é publicado.
func _test_eliminations_are_recorded_sanitised() -> void:
	var authority := _active_round(4)
	var now := _after_countdown()
	var assassin := _peer_with_role(authority, Role.ASSASSIN)
	var victim := _peer_with_role(authority, Role.VICTIM)

	_expect(authority.elimination_count() == 0, "no elimination is recorded at the start")
	_expect(authority.last_elimination(victim).is_empty(), "a living player has no record")

	_expect(authority.eliminate_player(victim, "peer_leak_ASSASSIN", assassin, now).is_empty(), "the elimination is accepted")
	var record := authority.last_elimination(victim)
	_expect(int(record.get("round_id", 0)) == authority.round_id, "the record carries the round id")
	_expect(str(record.get("cause", "")) == RoundRules.DEFAULT_CAUSE, "an unknown cause is stored sanitised")
	_expect(int(record.get("instigator", -1)) == assassin, "a participant instigator is kept")
	_expect(authority.elimination_count() == 1, "exactly one elimination is recorded")

	# Instigador fora da rodada é descartado, não propagado.
	var other := _peer_with_role(authority, Role.DETECTIVE)
	_expect(authority.eliminate_player(other, "test", 999_999, now).is_empty(), "the second elimination is accepted")
	_expect(int(authority.last_elimination(other).get("instigator", -1)) == 0, "an outside instigator is discarded")
	_expect(str(authority.last_elimination(other).get("cause", "")) == "test", "an allowed cause is kept")

	# A cópia devolvida não pode alterar o registro interno.
	var copy := authority.last_elimination(other)
	copy["cause"] = "tampered"
	_expect(str(authority.last_elimination(other).get("cause", "")) == "test", "the returned record is a copy")

	# Uma desconexão durante ACTIVE também registra a causa.
	var last_victim := 0
	for peer_id in authority.participants:
		if authority.is_alive(peer_id) and peer_id != assassin:
			last_victim = int(peer_id)
			break
	if last_victim > 0:
		authority.leave(last_victim, now)
		_expect(str(authority.last_elimination(last_victim).get("cause", "")) == "disconnect", "a disconnect is recorded as such")

	# O reinício apaga o registro junto com o resto do estado da rodada.
	authority.tick(now + int(END_DELAY_SECONDS * 1000.0) * 2)
	_expect(authority.elimination_count() == 0, "the reset clears the elimination records")

# --- Apoio -------------------------------------------------------------------

func _authority() -> RoundAuthority:
	var authority := RoundAuthority.new(LobbyRegistry.new(), SEED)
	authority.configure(COUNTDOWN_SECONDS, END_DELAY_SECONDS)
	return authority

func _with_players(count: int) -> RoundAuthority:
	var authority := _authority()
	for index in count:
		authority.join(100 + index, "client-%d" % (index + 1), BASE_MSEC)
	return authority

func _active_round(count: int) -> RoundAuthority:
	var authority := _with_players(count)
	authority.tick(_after_countdown())
	return authority

func _after_countdown() -> int:
	return BASE_MSEC + int(COUNTDOWN_SECONDS * 1000.0)

func _peer_with_role(authority: RoundAuthority, role: int) -> int:
	for peer_id in authority.participants:
		if authority.get_role_for_peer(peer_id) == role:
			return int(peer_id)
	_expect(false, "no participant holds the requested role")
	return 0

## Reconstrói o mapa de papéis pela consulta interna, apenas para verificar a
## distribuição no teste. Nada disso trafega para clientes.
func _roles_snapshot(authority: RoundAuthority) -> Dictionary:
	var roles: Dictionary = {}
	for peer_id in authority.participants:
		roles[int(peer_id)] = authority.get_role_for_peer(peer_id)
	return roles

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("ROUND_AUTHORITY_CHECK_FAILED %s" % description)
	print("ROUND_AUTHORITY_CHECK_FAILED %s" % description)
