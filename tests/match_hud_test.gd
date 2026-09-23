extends SceneTree

## Nós reais do HUD numa rodada completa (vivo → eliminado → espectador →
## ENDED → nova rodada), alimentados só com dados no formato oficial. Confere
## avisos de combate, prompt de coleta, balas do pente, recarga e eliminações
## públicas, e que nada disso sobra em estados em que não deve aparecer.
## Roda em headless (sem medir layout; isso fica em `hud_presentation_test`).

const OWN := 9
const ROSTER := [
	{"peer_id": 7, "label": "Ana", "connected": true, "participant": true, "alive": true},
	{"peer_id": 8, "label": "Beto", "connected": true, "participant": true, "alive": true},
	{"peer_id": 9, "label": "Caio", "connected": true, "participant": true, "alive": true},
	{"peer_id": 10, "label": "Duda", "connected": true, "participant": true, "alive": true},
]

var failures := 0
var checks := 0
var _hud: RoundHud
var _frame := 0

func _initialize() -> void:
	_hud = RoundHud.new()
	root.add_child(_hud)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_test_alive_feedback()
	_test_eliminated_then_spectator()
	_test_ended_then_new_round()
	_test_notices_expire()
	if failures > 0:
		push_error("MATCH_HUD_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("MATCH_HUD_TEST_OK checks=%d" % checks)
	quit(0)
	return true

func _test_alive_feedback() -> void:
	_hud.apply_roster(ROSTER)
	_hud.apply_round_state(_pub(RoundState.ACTIVE, 1), Role.DETECTIVE, 1, OWN)
	_hud.apply_combat_state(_combat(1, 100, "", 0, 0, false))
	_expect(not _hud._ammo_pips.visible and not _hud._feedback_column.visible, "unarmed: no bullets, nothing at the bottom centre")
	_hud.set_nearby_pickup("weapon")
	_expect(_hud._prompt_panel.visible and _hud._prompt_key.visible and _hud._prompt_label.text == "PEGAR PISTOLA", "near a weapon: E prompt")
	_hud.apply_combat_state(_combat(1, 100, "common_pistol", 6, 0, false))
	_expect(_notice_texts().has("PISTOLA EQUIPADA"), "official pickup shows a notice")
	_expect(_hud._prompt_label.text == "Você já tem uma arma" and not _hud._prompt_key.visible, "armed near a weapon: no E")
	_expect(_hud._ammo_pips.visible and _loaded_pips() == 6, "six loaded bullets")
	_hud.set_nearby_pickup("")
	_hud.apply_combat_state(_combat(1, 100, "common_pistol", 2, 0, false))
	_expect(_loaded_pips() == 2 and (_hud._ammo_pips.get_child(0) as ColorRect).color == HudStyle.COPPER, "two bullets left turn copper")
	_hud.apply_combat_state(_combat(1, 100, "common_pistol", 0, 6, false))
	_hud.show_rejection("fire", "empty_magazine")
	_expect(_notice_texts().has("Pente vazio · R para recarregar"), "empty magazine rejection shows a notice")
	_hud.show_rejection("fire", "fire_rate")
	_expect(not _notice_texts().has(""), "silent reasons add nothing")
	_hud.apply_combat_state(_combat(1, 100, "common_pistol", 0, 6, true))
	_expect(_hud._reload_track.visible and _hud._weapon_hint.text == "RECARREGANDO", "official reloading shows the running bar")
	_expect(not _notice_texts().has("Pente vazio · R para recarregar"), "the empty-magazine notice goes away once the official reload starts")
	_hud.apply_combat_state(_combat(1, 100, "common_pistol", 6, 0, false))
	_expect(not _hud._reload_track.visible and _notice_texts().has("RECARREGADA"), "reload end hides the bar and confirms")
	_hud.apply_elimination(7)
	_expect(_hud._feed_box.visible and _feed_texts() == ["✕  Ana — fora da rodada"], "public elimination shows only the name")
	_hud.apply_elimination(OWN)
	_expect(_feed_texts().size() == 1, "own elimination is not in the feed (the band covers it)")
	for text in _feed_texts() + _notice_texts():
		_expect(not _mentions_role(text), "no role in '%s'" % text)

func _test_eliminated_then_spectator() -> void:
	_hud.set_nearby_pickup("ammo")
	_hud.apply_roster(_roster_with_dead([7, OWN]))
	_hud.apply_combat_state(_combat(1, 0, "common_pistol", 6, 0, false))
	_hud.apply_spectator_state(true, [8, 10], 8)
	_expect(_hud.model["mode"] == RoundHud.MODE_SPECTATOR, "eliminated player becomes a spectator")
	_expect(not _hud._weapon_panel.visible and not _hud._health_panel.visible and not _hud._role_panel.visible, "spectator: private combat panels hidden")
	_expect(not _hud._feedback_column.visible and not _hud._prompt_panel.visible and not _hud._notice_box.visible, "spectator: no notices or pickup prompt")
	_expect(_hud._observe_panel.visible and _hud._observe_name.text == "Beto" and _hud._observe_keys.visible, "spectator: authorised target and Q/E")
	_expect(_hud._feed_box.visible, "spectator still sees public eliminations")
	_hud.show_rejection("fire", "empty_magazine")
	_expect(not _hud._notice_box.visible, "a late rejection does not surface while spectating")

func _test_ended_then_new_round() -> void:
	var ended := _pub(RoundState.ENDED, 1)
	ended["winning_team"] = Role.TEAM_INNOCENTS
	ended["winner_reason"] = RoundRules.REASON_ASSASSIN_DOWN
	_hud.apply_round_state(ended, Role.DETECTIVE, 1, OWN)
	_expect(_hud._ended_screen.visible and not _hud._feed_box.visible and not _hud._observe_panel.visible and not _hud._feedback_column.visible, "ENDED: only the end screen")
	_expect(_hud._notices.is_empty() and _hud._feed.is_empty() and _hud._nearby_pickup.is_empty(), "ENDED clears notices, feed and prompt")
	_hud.apply_final_reveal({"round_id": 1, "winner": "INNOCENTS", "reason": "assassin_down", "players": [{"peer_id": 7, "role": "ASSASSIN"}, {"peer_id": 9, "role": "DETECTIVE"}]})
	_expect(_hud._ended_title.text == "INOCENTES VENCEM", "winner shown after ENDED")
	# Nova rodada: o cliente limpa os dados privados e o HUD começa do zero.
	_hud.apply_final_reveal({})
	_hud.apply_spectator_state(false, [], 0)
	_hud.apply_combat_state({})
	_hud.apply_roster(ROSTER)
	_hud.apply_round_state(_pub(RoundState.WAITING, 1), Role.NONE, 0, OWN)
	_hud.apply_round_state(_pub(RoundState.ACTIVE, 2), Role.VICTIM, 2, OWN)
	_hud.apply_combat_state(_combat(2, 100, "", 0, 0, false))
	_expect(_hud.model["mode"] == RoundHud.MODE_ALIVE and not _hud._ended_screen.visible, "round 2 starts alive")
	_expect(not _hud._feed_box.visible and not _hud._notice_box.visible and not _hud._prompt_panel.visible, "round 2 shows no old notice, feed or prompt")
	_expect(_hud._weapon_title.text == "SEM ARMA" and not _hud._ammo_pips.visible and not _hud._reload_track.visible, "round 2 weapon panel starts empty")
	_expect(_hud._role_label.text.contains("VÍTIMA"), "round 2 shows only the new private role")

func _test_notices_expire() -> void:
	_hud.show_rejection("reload", "reserve_empty")
	_expect(_notice_texts().has("Sem munição na reserva"), "notice shown")
	for notice in _hud._notices:
		notice["until"] = 0
	_hud._process(0.0)
	_expect(_hud._notices.is_empty() and not _hud._notice_box.visible, "notices expire")

func _notice_texts() -> Array:
	return _hud._notices.map(func(notice): return str(notice["text"]))

func _feed_texts() -> Array:
	return _hud._feed.map(func(entry): return str(entry["text"]))

func _loaded_pips() -> int:
	var count := 0
	for pip in _hud._ammo_pips.get_children():
		if (pip as ColorRect).color != HudStyle.LINE:
			count += 1
	return count

func _mentions_role(text: String) -> bool:
	for word in ["ASSASSINO", "DETETIVE", "VÍTIMA", "assassino", "detetive", "vítima"]:
		if text.contains(word):
			return true
	return false

func _pub(state: int, round_id: int) -> Dictionary:
	return {"state": state, "round_id": round_id, "countdown_msec": 0, "connected": 4, "participants": 4, "alive": 4,
		"winning_team": Role.TEAM_NONE, "winner_reason": "", "min_players": 4, "max_players": 8}

func _combat(round_id: int, health: int, weapon: String, magazine: int, reserve: int, reloading: bool) -> Dictionary:
	return {"round_id": round_id, "health": health, "weapon_id": weapon, "magazine": magazine, "reserve": reserve, "reloading": reloading}

func _roster_with_dead(dead: Array) -> Array:
	var result: Array = []
	for entry in ROSTER:
		var copy: Dictionary = entry.duplicate()
		copy["alive"] = not dead.has(int(copy["peer_id"]))
		result.append(copy)
	return result

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("MATCH_HUD_CHECK_FAILED %s" % description)
