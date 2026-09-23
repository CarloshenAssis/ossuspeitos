extends SceneTree

## Verifica que o HUD é apresentação pura: ele só formata o que o servidor
## publicou e nunca mostra o papel de outro jogador durante a rodada. O modelo
## de tela é estático, portanto estes testes não dependem de renderização.

const OWN := 9
const ROSTER_ALIVE := [
	{"peer_id": 7, "label": "Ana", "connected": true, "participant": true, "alive": true},
	{"peer_id": 8, "label": "Beto", "connected": true, "participant": true, "alive": true},
	{"peer_id": 9, "label": "Caio", "connected": true, "participant": true, "alive": true},
	{"peer_id": 10, "label": "Duda", "connected": true, "participant": true, "alive": true},
]

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
	_test_role_from_another_round_is_hidden()
	_test_values_match_the_official_rules()
	_test_weapon_panel_follows_official_state()
	_test_full_round_transitions_and_cleanup()
	_test_spectator_target_changes()
	_test_reveal_only_for_the_same_round()
	if failures > 0:
		push_error("ROUND_HUD_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("ROUND_HUD_TEST_OK checks=%d" % checks)
	quit(0)

func _test_waiting_hides_the_role() -> void:
	# Mesmo que um papel residual chegue ao HUD, WAITING não pode exibi-lo.
	var model := _model(_public(RoundState.WAITING, {"connected": 2}), Role.ASSASSIN, _roster(true, true))
	var text := _join(model)
	_expect(model["mode"] == RoundHud.MODE_LOBBY, "WAITING is a lobby screen")
	_expect(text.contains("AGUARDANDO JOGADORES"), "WAITING shows the waiting phase")
	_expect(text.contains("Conectados 2/8"), "WAITING shows the connected count")
	_expect(text.contains("faltam 2 para começar"), "WAITING shows how many players are missing")
	_expect((model["role"] as Dictionary).is_empty(), "WAITING never shows a role")
	_expect(not _mentions_any_role(text), "WAITING leaks no role name")

func _test_countdown_shows_the_timer_without_the_role() -> void:
	var model := _model(_public(RoundState.COUNTDOWN, {"connected": 4, "countdown_msec": 2400}), Role.DETECTIVE, _roster(true, true))
	var text := _join(model)
	_expect(text.contains("RODADA COMEÇA EM 3s"), "COUNTDOWN shows the published remaining time")
	_expect((model["role"] as Dictionary).is_empty() and not _mentions_any_role(text), "COUNTDOWN never shows a role")

func _test_active_shows_only_the_local_role() -> void:
	var roster := [
		{"peer_id": 7, "label": "client-1", "connected": true, "participant": true, "alive": true},
		{"peer_id": 8, "label": "client-2", "connected": true, "participant": true, "alive": false},
	]
	var model := _model(_public(RoundState.ACTIVE, {"connected": 2, "participants": 2, "alive": 1}), Role.ASSASSIN, roster)
	var text := _join(model)
	_expect(model["mode"] == RoundHud.MODE_ALIVE, "a living participant gets the alive screen")
	_expect(text.contains("EM PARTIDA") and text.contains("1 de 2 vivos"), "ACTIVE shows the phase and the public alive count")
	_expect(text.contains("SÓ VOCÊ VÊ ◆ ASSASSINO"), "ACTIVE shows the local role marked as private")
	# O roster traz outro peer, mas o HUD não deduz nem exibe nada sobre ele.
	_expect(not text.contains("client-2"), "the HUD never shows another player's row")
	_expect(text.count("SÓ VOCÊ VÊ") == 1, "the HUD shows a single role")

func _test_alive_state_comes_from_the_roster() -> void:
	var dead := [{"peer_id": 7, "label": "client-1", "connected": true, "participant": true, "alive": false}]
	var model := _model(_public(RoundState.ACTIVE, {"connected": 4}), Role.VICTIM, dead)
	_expect(model["mode"] == RoundHud.MODE_SPECTATOR, "the HUD mirrors the official dead state")
	_expect(_join(model).contains("ELIMINADO"), "a dead participant is told so")
	_expect((model["role"] as Dictionary).is_empty() and (model["health"] as Dictionary).is_empty()
		and (model["weapon"] as Dictionary).is_empty(), "a dead participant sees no role or combat panel")

func _test_ended_shows_the_public_winner() -> void:
	var payload := _public(RoundState.ENDED, {"connected": 4, "winning_team": Role.TEAM_INNOCENTS, "winner_reason": "assassin_down"})
	var model := _model(payload, Role.VICTIM, _roster(true, true))
	var text := _join(model)
	_expect(model["mode"] == RoundHud.MODE_ENDED, "ENDED shows the end screen")
	_expect(text.contains("INOCENTES VENCEM"), "ENDED shows the winning team")
	_expect(text.contains("O assassino foi eliminado."), "ENDED explains the official reason")
	var assassin_payload := _public(RoundState.ENDED, {"connected": 4, "winning_team": Role.TEAM_ASSASSIN, "winner_reason": "innocents_down"})
	var assassin_text := _join(_model(assassin_payload, Role.VICTIM, _roster(true, true)))
	_expect(assassin_text.contains("ASSASSINO VENCE") and assassin_text.contains("Todos os inocentes foram eliminados."), "ENDED shows an assassin victory")

func _test_late_join_is_warned() -> void:
	var model := _model(_public(RoundState.ACTIVE, {"connected": 5}), Role.NONE, _roster(false, true))
	_expect(model["mode"] == RoundHud.MODE_NEXT_ROUND, "a non participant waits for the next round")
	_expect(_join(model).contains("VOCÊ ENTRA NA PRÓXIMA RODADA"), "a non participant is told to wait")
	_expect((model["role"] as Dictionary).is_empty(), "a non participant sees no role")
	var participant := _join(_model(_public(RoundState.ACTIVE, {"connected": 4}), Role.VICTIM, _roster(true, true)))
	_expect(not participant.contains("PRÓXIMA RODADA"), "a participant gets no waiting warning")

func _test_missing_fields_do_not_break_the_hud() -> void:
	var empty := RoundHud.compose_lines({}, Role.NONE, 0, [])
	_expect(empty.size() >= 1, "an empty payload still renders the phase")
	_expect(str(empty[0]).contains("AGUARDANDO"), "an empty payload falls back to WAITING")
	var garbage := RoundHud.compose_lines({"state": 99, "connected": -3}, 42, 7, [{"peer_id": "x"}, "not a dict"])
	_expect(garbage.size() >= 1, "an invalid payload still renders")
	_expect(not "\n".join(garbage).contains("SÓ VOCÊ VÊ"), "an invalid role is never shown")

func _test_role_from_another_round_is_hidden() -> void:
	# Papel guardado da rodada 1 não aparece quando o estado público já é da 2.
	var payload := _public(RoundState.ACTIVE, {"connected": 4})
	payload["round_id"] = 2
	var model := RoundHud.view_model(payload, Role.ASSASSIN, 1, 7, _roster(true, true))
	_expect((model["role"] as Dictionary).is_empty(), "a role from a previous round is never shown")

# --- Transições entre vivo, eliminado, espectador, ENDED e nova rodada ----------

func _test_values_match_the_official_rules() -> void:
	_expect(RoundHud.HEALTH_BAR_MAX == CombatAuthority.MAX_HEALTH, "health bar uses the server maximum")
	# Um acerto da pistola comum tira 34: a faixa "baixa" é "morre no próximo".
	var definition: WeaponDefinition = CombatAuthority.new(RoundAuthority.new(), AuthoritativeWorld.new()).inventory.definitions[CombatAuthority.COMMON_WEAPON_ID]
	_expect(RoundHud.LOW_HEALTH == int(definition.damage), "low health threshold is one official pistol hit")
	_expect(RoundHud.WEAPON_NAMES.has(CombatAuthority.COMMON_WEAPON_ID), "the official weapon id has a display name")
	_expect(RoundHud.REASON_TEXT.has(RoundRules.REASON_ASSASSIN_DOWN) and RoundHud.REASON_TEXT.has(RoundRules.REASON_INNOCENTS_DOWN), "every official win reason has a sentence")

func _test_weapon_panel_follows_official_state() -> void:
	var public := _pub(RoundState.ACTIVE, 1)
	var no_weapon := _alive_model(public, _combat(1, 100, "", 0, 0, false))
	_expect(no_weapon["weapon"]["name"] == "SEM ARMA" and str(no_weapon["weapon"]["hint"]).contains("E para pegar"), "no weapon asks to pick one up")
	var loaded := _alive_model(public, _combat(1, 100, "common_pistol", 6, 0, false))
	_expect(loaded["weapon"]["name"] == "PISTOLA" and loaded["weapon"]["ammo"] == "6 / 0" and loaded["weapon"]["hint"] == "", "a fresh pickup shows 6 / 0 with no warning")
	var empty := _alive_model(public, _combat(1, 100, "common_pistol", 0, 6, false))
	_expect(empty["weapon"]["hint"] == "R para recarregar", "empty magazine with reserve asks for R")
	var dry := _alive_model(public, _combat(1, 100, "common_pistol", 0, 0, false))
	_expect(str(dry["weapon"]["hint"]).contains("Sem munição"), "no ammo at all points to the map")
	var reloading := _alive_model(public, _combat(1, 100, "common_pistol", 0, 6, true))
	_expect(reloading["weapon"]["hint"] == "RECARREGANDO", "reloading comes from the official flag")
	var hurt := _alive_model(public, _combat(1, 32, "common_pistol", 3, 0, false))
	_expect(hurt["health"]["value"] == 32 and bool(hurt["health"]["low"]), "health and low state come from the official value")
	var weird := _alive_model(public, _combat(1, 250, "mystery_gun", -3, -1, false))
	_expect(weird["health"]["value"] == RoundHud.HEALTH_BAR_MAX and weird["weapon"]["ammo"] == "0 / 0" and weird["weapon"]["name"] == "MYSTERY_GUN", "out-of-range values are clamped, never invented")

func _test_full_round_transitions_and_cleanup() -> void:
	var combat := _combat(1, 100, "common_pistol", 6, 0, false)
	var reveal := {"round_id": 1, "winner": "INNOCENTS", "reason": "assassin_down", "players": [
		{"peer_id": 7, "role": "ASSASSIN"}, {"peer_id": 8, "role": "DETECTIVE"},
		{"peer_id": 9, "role": "VICTIM"}, {"peer_id": 10, "role": "VICTIM"}]}
	# Lobby: nada de papel, vida ou arma, mesmo com dados residuais.
	var lobby := RoundHud.view_model(_pub(RoundState.COUNTDOWN, 1), Role.VICTIM, 1, OWN, ROSTER_ALIVE, {}, reveal, combat)
	_expect(lobby["mode"] == RoundHud.MODE_LOBBY and _no_private_panels(lobby) and (lobby["ended"] as Dictionary).is_empty(), "countdown shows no private or revealed data")
	# Vivo.
	var alive := RoundHud.view_model(_pub(RoundState.ACTIVE, 1), Role.VICTIM, 1, OWN, ROSTER_ALIVE, {}, {}, combat)
	_expect(alive["mode"] == RoundHud.MODE_ALIVE and not (alive["health"] as Dictionary).is_empty() and not (alive["role"] as Dictionary).is_empty(), "alive shows role, health and weapon")
	# Eliminado pelo roster oficial, antes da lista privada de alvos chegar.
	var dead_roster := _roster_with_dead([9])
	var just_dead := RoundHud.view_model(_pub(RoundState.ACTIVE, 1), Role.VICTIM, 1, OWN, dead_roster, {}, {}, _combat(1, 0, "common_pistol", 6, 0, false))
	_expect(just_dead["mode"] == RoundHud.MODE_SPECTATOR and _no_private_panels(just_dead), "death hides role, health and weapon at once")
	_expect(bool(just_dead["spectator"]["waiting"]), "without authorized targets the spectator waits safely")
	# Espectador com alvo autorizado.
	var spectating := RoundHud.view_model(_pub(RoundState.ACTIVE, 1), Role.VICTIM, 1, OWN, dead_roster,
		{"eliminated": true, "targets": [8, 10], "target": 10}, {}, _combat(1, 0, "", 0, 0, false))
	_expect(spectating["spectator"]["target_name"] == "Duda" and spectating["spectator"]["index"] == "2/2", "spectator shows only the authorized target and its position")
	_expect(not "\n".join(RoundHud.model_lines(spectating)).contains("VIDA"), "spectator never shows combat data")
	# ENDED sem a revelação ainda: vencedor e motivo, papéis só depois.
	var ended_public := _pub(RoundState.ENDED, 1)
	ended_public["winning_team"] = Role.TEAM_INNOCENTS
	ended_public["winner_reason"] = RoundRules.REASON_ASSASSIN_DOWN
	var ended_pending := RoundHud.view_model(ended_public, Role.VICTIM, 1, OWN, dead_roster, {"eliminated": true, "targets": [], "target": 0}, {}, combat)
	_expect(ended_pending["mode"] == RoundHud.MODE_ENDED and not bool(ended_pending["ended"]["revealed"]), "ENDED waits for the official reveal")
	_expect(_no_private_panels(ended_pending) and (ended_pending["spectator"] as Dictionary).is_empty(), "ENDED leaves spectator and combat panels")
	var ended := RoundHud.view_model(ended_public, Role.VICTIM, 1, OWN, dead_roster, {"eliminated": true, "targets": [], "target": 0}, reveal, combat)
	_expect(bool(ended["ended"]["revealed"]) and (ended["ended"]["rows"] as Array).size() == 4, "ENDED lists every revealed participant")
	var own_row: Dictionary = (ended["ended"]["rows"] as Array)[2]
	_expect(bool(own_row["you"]) and own_row["status"] == "Eliminado" and own_row["name"] == "Caio", "own row is marked and uses the official alive state")
	# Nova rodada: revelação, combate e papel antigos não aparecem.
	var next_waiting := RoundHud.view_model(_pub(RoundState.WAITING, 1), Role.VICTIM, 1, OWN, ROSTER_ALIVE, {}, reveal, combat)
	_expect(_no_private_panels(next_waiting) and (next_waiting["ended"] as Dictionary).is_empty(), "WAITING after ENDED shows nothing from the previous round")
	var next_active := RoundHud.view_model(_pub(RoundState.ACTIVE, 2), Role.VICTIM, 1, OWN, ROSTER_ALIVE, {}, reveal, combat)
	_expect(next_active["mode"] == RoundHud.MODE_ALIVE and _no_private_panels(next_active), "round 2 ignores role and combat state from round 1")
	var fresh := RoundHud.view_model(_pub(RoundState.ACTIVE, 2), Role.DETECTIVE, 2, OWN, ROSTER_ALIVE, {}, {}, _combat(2, 100, "", 0, 0, false))
	_expect(fresh["role"]["name"] == "DETETIVE" and fresh["health"]["value"] == 100 and fresh["weapon"]["name"] == "SEM ARMA", "round 2 shows only its own official data")

func _test_spectator_target_changes() -> void:
	var dead_roster := _roster_with_dead([9, 8])
	var public := _pub(RoundState.ACTIVE, 1)
	var first := RoundHud.view_model(public, Role.VICTIM, 1, OWN, dead_roster, {"eliminated": true, "targets": [7, 10], "target": 7})
	var second := RoundHud.view_model(public, Role.VICTIM, 1, OWN, dead_roster, {"eliminated": true, "targets": [7, 10], "target": 10})
	_expect(first["spectator"]["target_name"] == "Ana" and second["spectator"]["target_name"] == "Duda", "Q/E changes only among authorized targets")
	var outsider := RoundHud.view_model(public, Role.VICTIM, 1, OWN, dead_roster, {"eliminated": true, "targets": [7, 10], "target": 8})
	_expect(bool(outsider["spectator"]["waiting"]), "a target outside the authorized list is never presented")
	var none := RoundHud.view_model(public, Role.VICTIM, 1, OWN, dead_roster, {"eliminated": true, "targets": [], "target": 0})
	_expect(none["spectator"]["waiting_title"] == "AGUARDANDO FIM DA RODADA", "no living target shows the waiting state")

func _test_reveal_only_for_the_same_round() -> void:
	var ended_public := _pub(RoundState.ENDED, 3)
	ended_public["winning_team"] = Role.TEAM_ASSASSIN
	ended_public["winner_reason"] = RoundRules.REASON_INNOCENTS_DOWN
	var stale := {"round_id": 2, "winner": "INNOCENTS", "reason": "assassin_down", "players": [{"peer_id": 7, "role": "ASSASSIN"}]}
	var model := RoundHud.view_model(ended_public, Role.VICTIM, 3, OWN, ROSTER_ALIVE, {}, stale)
	_expect(not bool(model["ended"]["revealed"]) and model["ended"]["title"] == "ASSASSINO VENCE", "a reveal from another round is never shown; the winner comes from the public state")
	var bad_roles := {"round_id": 3, "winner": "ASSASSIN", "reason": "innocents_down", "players": [{"peer_id": 7, "role": 1}, {"peer_id": 8, "role": "KING"}, "junk"]}
	var filtered := RoundHud.view_model(ended_public, Role.VICTIM, 3, OWN, ROSTER_ALIVE, {}, bad_roles)
	_expect((filtered["ended"]["rows"] as Array).is_empty(), "malformed reveal entries are dropped")
	var gone := {"round_id": 3, "winner": "ASSASSIN", "reason": "innocents_down", "players": [{"peer_id": 42, "role": "VICTIM"}]}
	var gone_model := RoundHud.view_model(ended_public, Role.VICTIM, 3, OWN, ROSTER_ALIVE, {}, gone)
	_expect(gone_model["ended"]["rows"][0]["name"] == "Jogador 42" and gone_model["ended"]["rows"][0]["status"] == "—", "a participant who left keeps a neutral row")

# --- Apoio -------------------------------------------------------------------

func _pub(state: int, round_id: int) -> Dictionary:
	return {"state": state, "round_id": round_id, "countdown_msec": 3000, "connected": 4, "participants": 4, "alive": 4,
		"winning_team": Role.TEAM_NONE, "winner_reason": "", "min_players": 4, "max_players": 8}

func _combat(round_id: int, health: int, weapon: String, magazine: int, reserve: int, reloading: bool) -> Dictionary:
	return {"round_id": round_id, "health": health, "weapon_id": weapon, "magazine": magazine, "reserve": reserve, "reloading": reloading}

func _alive_model(public: Dictionary, combat: Dictionary) -> Dictionary:
	return RoundHud.view_model(public, Role.VICTIM, int(public["round_id"]), OWN, ROSTER_ALIVE, {}, {}, combat)

func _roster_with_dead(dead: Array) -> Array:
	var roster: Array = []
	for entry in ROSTER_ALIVE:
		var copy: Dictionary = entry.duplicate()
		copy["alive"] = int(copy["peer_id"]) not in dead
		roster.append(copy)
	return roster

func _no_private_panels(model: Dictionary) -> bool:
	return (model["role"] as Dictionary).is_empty() and (model["health"] as Dictionary).is_empty() and (model["weapon"] as Dictionary).is_empty()


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

func _model(payload: Dictionary, role: int, roster: Array) -> Dictionary:
	return RoundHud.view_model(payload, role, int(payload.get("round_id", 0)), 7, roster)

func _join(model: Dictionary) -> String:
	return "\n".join(RoundHud.model_lines(model))

func _mentions_any_role(text: String) -> bool:
	for role in [Role.ASSASSIN, Role.DETECTIVE, Role.VICTIM]:
		if text.contains(str(HudStyle.ROLE_NAMES[role])):
			return true
	return false

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("ROUND_HUD_CHECK_FAILED %s" % description)
	print("ROUND_HUD_CHECK_FAILED %s" % description)
