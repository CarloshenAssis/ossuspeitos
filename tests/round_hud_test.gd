extends SceneTree

## Verifica que o HUD é apresentação pura: ele só formata o que o servidor
## publicou e nunca mostra o papel de outro jogador. A composição do texto é
## estática, portanto o teste não instancia nó nem depende de renderização.

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_waiting_hides_the_role()
	_test_countdown_shows_the_timer_without_the_role()
	_test_active_shows_only_the_local_role()
	_test_alive_state_comes_from_the_roster()
	_test_ended_shows_the_public_winner()
	_test_late_join_is_warned()
	_test_missing_fields_do_not_break_the_hud()
	if failures > 0:
		push_error("ROUND_HUD_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("ROUND_HUD_TEST_OK checks=%d" % checks)
	quit(0)

func _test_waiting_hides_the_role() -> void:
	# Mesmo que um papel residual chegue ao HUD, WAITING não pode exibi-lo.
	var text := _text(_public(RoundState.WAITING, {"connected": 2}), Role.ASSASSIN, _roster(true, true))
	_expect(text.contains("Aguardando"), "WAITING shows the waiting phase")
	_expect(text.contains("Jogadores conectados: 2/8"), "WAITING shows the connected count")
	_expect(text.contains("Faltam 2 jogadores"), "WAITING shows how many players are missing")
	_expect(not text.contains("Seu papel"), "WAITING never shows a role")
	_expect(not _mentions_any_role(text), "WAITING leaks no role name")

func _test_countdown_shows_the_timer_without_the_role() -> void:
	var text := _text(_public(RoundState.COUNTDOWN, {"connected": 4, "countdown_msec": 2400}), Role.DETECTIVE, _roster(true, true))
	_expect(text.contains("Contagem regressiva"), "COUNTDOWN shows the countdown phase")
	_expect(text.contains("Início em: 3s"), "COUNTDOWN shows the published remaining time")
	_expect(not text.contains("Seu papel"), "COUNTDOWN never shows a role")

func _test_active_shows_only_the_local_role() -> void:
	var roster := [
		{"peer_id": 7, "label": "client-1", "connected": true, "participant": true, "alive": true},
		{"peer_id": 8, "label": "client-2", "connected": true, "participant": true, "alive": false},
	]
	var text := _text(_public(RoundState.ACTIVE, {"connected": 2}), Role.ASSASSIN, roster)
	_expect(text.contains("Em partida"), "ACTIVE shows the active phase")
	_expect(text.contains("Seu papel: Assassino"), "ACTIVE shows the local role")
	_expect(text.contains("Você está: Vivo"), "ACTIVE shows the local alive state")
	# O roster traz outro peer, mas o HUD não deduz nem exibe nada sobre ele.
	_expect(not text.contains("client-2"), "the HUD never shows another player's row")
	_expect(text.count("Seu papel") == 1, "the HUD shows a single role")

func _test_alive_state_comes_from_the_roster() -> void:
	var dead := [{"peer_id": 7, "label": "client-1", "connected": true, "participant": true, "alive": false}]
	var text := _text(_public(RoundState.ACTIVE, {"connected": 4}), Role.VICTIM, dead)
	_expect(text.contains("Você está: Morto"), "the HUD mirrors the official dead state")
	_expect(text.contains("Seu papel: Vítima"), "the dead player still sees their own role")

func _test_ended_shows_the_public_winner() -> void:
	var payload := _public(RoundState.ENDED, {"connected": 4, "winning_team": Role.TEAM_INNOCENTS})
	var text := _text(payload, Role.VICTIM, _roster(true, true))
	_expect(text.contains("Encerrada"), "ENDED shows the ended phase")
	_expect(text.contains("Vencedor: Inocentes"), "ENDED shows the winning team")
	var assassin_payload := _public(RoundState.ENDED, {"connected": 4, "winning_team": Role.TEAM_ASSASSIN})
	_expect(_text(assassin_payload, Role.VICTIM, _roster(true, true)).contains("Vencedor: Assassino"), "ENDED shows an assassin victory")

func _test_late_join_is_warned() -> void:
	var text := _text(_public(RoundState.ACTIVE, {"connected": 5}), Role.NONE, _roster(false, true))
	_expect(text.contains("Você entra na próxima rodada"), "a non participant is told to wait")
	_expect(not text.contains("Seu papel"), "a non participant sees no role")
	var participant := _text(_public(RoundState.ACTIVE, {"connected": 4}), Role.VICTIM, _roster(true, true))
	_expect(not participant.contains("Você entra na próxima rodada"), "a participant gets no waiting warning")

func _test_missing_fields_do_not_break_the_hud() -> void:
	var empty := RoundHud.compose_lines({}, Role.NONE, 0, [])
	_expect(empty.size() >= 2, "an empty payload still renders the phase")
	_expect(str(empty[0]).contains("Aguardando"), "an empty payload falls back to WAITING")
	var garbage := RoundHud.compose_lines({"state": 99, "connected": -3}, 42, 7, [{"peer_id": "x"}])
	_expect(garbage.size() >= 2, "an invalid payload still renders")
	_expect(not "\n".join(garbage).contains("Seu papel"), "an invalid role is never shown")

# --- Apoio -------------------------------------------------------------------

func _public(state: int, extra: Dictionary) -> Dictionary:
	var payload := {
		"state": state,
		"round_id": 1,
		"countdown_msec": 0,
		"connected": 0,
		"participants": 0,
		"alive": 0,
		"winning_team": Role.TEAM_NONE,
		"winner_reason": "",
		"min_players": RoundRules.MIN_PLAYERS,
		"max_players": RoundRules.MAX_PLAYERS,
	}
	payload.merge(extra, true)
	return payload

func _roster(participant: bool, alive: bool) -> Array:
	return [{
		"peer_id": 7,
		"label": "client-1",
		"connected": true,
		"participant": participant,
		"alive": alive,
	}]

func _text(payload: Dictionary, role: int, roster: Array) -> String:
	return "\n".join(RoundHud.compose_lines(payload, role, 7, roster))

func _mentions_any_role(text: String) -> bool:
	for role in [Role.ASSASSIN, Role.DETECTIVE, Role.VICTIM]:
		if text.contains(str(RoundHud.ROLE_TEXT[role])):
			return true
	return false

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("ROUND_HUD_CHECK_FAILED %s" % description)
	print("ROUND_HUD_CHECK_FAILED %s" % description)
