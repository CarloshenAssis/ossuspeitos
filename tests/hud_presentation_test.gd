extends SceneTree

## Nós reais do HUD e da arena seguindo o modelo oficial (vivo → espectador →
## ENDED → nova rodada), mira e arma só quando o jogador pode agir, e layout
## fora do centro da visão. As regras de transição do modelo estão em
## `round_hud_test.gd`, que roda no CI.
##
## O layout só é medido com renderização real (fonte e tamanho de janela reais):
##   xvfb-run godot --path . --resolution 960x540 --script tests/hud_presentation_test.gd
##   xvfb-run godot --path . --resolution 1920x1080 --script tests/hud_presentation_test.gd
## Em modo headless o servidor de texto é fictício e a janela tem 100×100; ali a
## parte de layout é pulada e isso é impresso explicitamente.

const OWN := 9
const ROSTER_ALIVE := [
	{"peer_id": 7, "label": "Ana", "connected": true, "participant": true, "alive": true},
	{"peer_id": 8, "label": "Beto", "connected": true, "participant": true, "alive": true},
	{"peer_id": 9, "label": "Caio", "connected": true, "participant": true, "alive": true},
	{"peer_id": 10, "label": "Duda", "connected": true, "participant": true, "alive": true},
]
## Área central (300×240 no canvas base) que nunca recebe painel na partida.
var _center_free := Rect2()

var failures := 0
var checks := 0
var _hud: RoundHud
var _arena: ArenaView
var _frame := 0

func _initialize() -> void:
	_hud = RoundHud.new()
	root.add_child(_hud)
	_arena = ArenaView.new()
	root.add_child(_arena)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_test_nodes_follow_the_model()
		_test_gameplay_visuals()
	if _frame < 4:
		return false
	if _frame == 4:
		if DisplayServer.get_name() == "headless":
			print("HUD_LAYOUT_SKIPPED reason=headless_has_no_real_fonts_or_window")
		else:
			_test_layout_keeps_the_center_free()
		if failures > 0:
			push_error("HUD_PRESENTATION_TEST_FAILED failures=%d checks=%d" % [failures, checks])
			quit(1)
			return false
		print("HUD_PRESENTATION_TEST_OK checks=%d layout=%s" % [checks, "skipped" if DisplayServer.get_name() == "headless" else "checked %s" % str(root.size)])
		quit(0)
	return false

# --- Modelo -----------------------------------------------------------------------

# --- Nós reais --------------------------------------------------------------------

func _test_nodes_follow_the_model() -> void:
	_hud.apply_roster(ROSTER_ALIVE)
	_hud.apply_round_state(_public(RoundState.ACTIVE, 1), Role.ASSASSIN, 1, OWN)
	_hud.apply_combat_state(_combat(1, 100, "common_pistol", 6, 0, false))
	_expect(_hud._role_panel.visible and _hud._health_panel.visible and _hud._weapon_panel.visible, "alive: role, health and weapon panels visible")
	_expect(not _hud._eliminated_band.visible and not _hud._observe_panel.visible and not _hud._ended_screen.visible, "alive: no spectator or end screen")
	_expect(_hud._role_label.text == "◆ ASSASSINO" and _hud._health_value.text == "100" and _hud._weapon_ammo.text == "6 / 0", "alive: panels show the official values")
	_hud.apply_combat_state(_combat(1, 66, "common_pistol", 5, 0, false))
	_expect(_hud._damage_vignette.modulate.a > 0.5, "official health drop flashes the edge vignette")
	_hud.apply_roster(_roster_with_dead([OWN]))
	_hud.apply_combat_state(_combat(1, 0, "common_pistol", 5, 0, false))
	_hud.apply_spectator_state(true, [7, 8], 8)
	_expect(not _hud._role_panel.visible and not _hud._health_panel.visible and not _hud._weapon_panel.visible, "spectator: private combat panels hidden")
	_expect(_hud._eliminated_band.visible and _hud._observe_panel.visible and _hud._observe_name.text == "Beto" and _hud._observe_keys.visible, "spectator: band, authorized target and Q/E visible")
	var ended_public := _public(RoundState.ENDED, 1)
	ended_public["winning_team"] = Role.TEAM_INNOCENTS
	ended_public["winner_reason"] = RoundRules.REASON_ASSASSIN_DOWN
	_hud.apply_round_state(ended_public, Role.ASSASSIN, 1, OWN)
	_hud.apply_final_reveal({"round_id": 1, "winner": "INNOCENTS", "reason": "assassin_down", "players": [{"peer_id": 7, "role": "VICTIM"}, {"peer_id": 9, "role": "ASSASSIN"}]})
	_expect(_hud._ended_screen.visible and not _hud._status_panel.visible and not _hud._observe_panel.visible, "ENDED: only the end screen")
	_expect(_hud._ended_title.text == "INOCENTES VENCEM" and _hud._ended_reason.text == "O assassino foi eliminado.", "ENDED: winner and reason from the public state")
	# Nova rodada: o cliente limpa os dados; o HUD volta ao lobby sem nada antigo.
	_hud.apply_final_reveal({})
	_hud.apply_spectator_state(false, [], 0)
	_hud.apply_combat_state({})
	_hud.apply_roster(ROSTER_ALIVE)
	_hud.apply_round_state(_public(RoundState.WAITING, 1), Role.NONE, 0, OWN)
	_expect(not _hud._ended_screen.visible and not _hud._role_panel.visible and not _hud._health_panel.visible and not _hud._weapon_panel.visible and not _hud._eliminated_band.visible, "WAITING: every round panel is gone")
	_hud.apply_round_state(_public(RoundState.ACTIVE, 2), Role.VICTIM, 2, OWN)
	_hud.apply_combat_state(_combat(2, 100, "", 0, 0, false))
	_expect(is_zero_approx(_hud._damage_vignette.modulate.a), "a new round starts without a stale damage flash")
	_expect(_hud._weapon_title.text == "SEM ARMA" and _hud._health_value.text == "100", "round 2 shows only its own official state")
	_hud.set_session_info("Sala neste PC: 127.0.0.1:9080 (somente este computador)")
	_expect(_hud._session_label.visible and _hud._session_label.text.contains("9080"), "session address lives in the status panel")
	_hud.set_session_info("Sala neste PC: 127.0.0.1:9080\nEsc: soltar mouse · F10: sair para o menu")
	_hud.apply_roster(_roster_with_dead([OWN]))
	_hud.apply_spectator_state(true, [7], 7)
	_expect(_hud._session_label.text == "Esc: soltar mouse · F10: sair para o menu", "spectator keeps only the Esc/F10 line so the top band has room")
	_hud.apply_spectator_state(false, [], 0)
	_hud.apply_roster(ROSTER_ALIVE)

func _test_gameplay_visuals() -> void:
	_arena.apply_combat_state(_combat(1, 100, "common_pistol", 6, 0, false))
	_arena.set_gameplay_visuals(true)
	_expect(_arena.crosshair.visible and _arena.weapon_model.visible, "alive player sees crosshair and weapon")
	_arena.set_spectator_target(8)
	_expect(not _arena.crosshair.visible and not _arena.weapon_model.visible, "spectator hides crosshair and weapon")
	_arena.set_gameplay_visuals(false)
	_arena.set_spectator_target(0, false)
	_expect(not _arena.crosshair.visible and not _arena.weapon_model.visible, "lobby and end of round hide crosshair and weapon")
	_arena.apply_combat_state({})
	_arena.set_gameplay_visuals(true)
	_expect(_arena.crosshair.visible and not _arena.weapon_model.visible, "without an official weapon there is nothing in hand")
	_arena.local_peer_id = OWN
	_arena.apply_snapshot([{"peer_id": OWN, "position": Vector3(13.5, 1, 9), "yaw": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0}])
	_arena._process(0.0)
	_expect(_arena.region_chip.visible and _arena.region_side.text == "SC" and _arena.region_name.text == "SALÃO CENTRAL", "region chip names the official room with its initials")
	_arena.apply_snapshot([{"peer_id": OWN, "position": Vector3(10, 1, 2.5), "yaw": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0}])
	_arena._process(0.0)
	_expect(_arena.region_side.text == "CR" and _arena.region_name.text == "CORREDOR NORTE", "corridors are named too")

# --- Layout -----------------------------------------------------------------------

func _test_layout_keeps_the_center_free() -> void:
	# Coordenadas do canvas (base 960×540 esticada com `canvas_items`/`expand`).
	var viewport_rect := _hud._status_panel.get_viewport_rect()
	var center := viewport_rect.size * 0.5
	_center_free = Rect2(center - Vector2(150, 120), Vector2(300, 240))
	_hud.apply_roster(ROSTER_ALIVE)
	_hud.apply_round_state(_public(RoundState.ACTIVE, 2), Role.DETECTIVE, 2, OWN)
	_hud.apply_combat_state(_combat(2, 32, "common_pistol", 0, 6, true))
	var crosshair_center := _arena.crosshair.get_global_rect().get_center()
	_expect(crosshair_center.distance_to(viewport_rect.get_center()) < 1.0, "crosshair sits on the true screen centre (%s vs %s)" % [str(crosshair_center), str(viewport_rect.get_center())])
	# Avisos, prompt de coleta e eliminações também ficam fora do centro.
	_hud.set_nearby_pickup("ammo")
	_hud.show_rejection("reload", "reserve_empty")
	_hud.apply_elimination(7)
	var alive_panels := {"status": _hud._status_panel, "role": _hud._role_panel, "health": _hud._health_panel, "weapon": _hud._weapon_panel, "region": _arena.region_chip,
		"feedback": _hud._feedback_column, "feed": _hud._feed_box}
	_expect(_hud._feedback_column.visible and _hud._feed_box.visible, "feedback column and feed are on screen for the layout check")
	_check_panels(alive_panels, viewport_rect)
	# Conteúdo menor encolhe o painel (um Control não encolhe sozinho).
	_hud.apply_combat_state(_combat(2, 32, "", 0, 0, false))
	var tall := _hud._weapon_panel.size
	_hud.apply_combat_state(_combat(2, 32, "common_pistol", 6, 0, false))
	var short := _hud._weapon_panel.size
	_expect(short.x < tall.x and is_equal_approx(_hud._weapon_panel.get_global_rect().end.x, viewport_rect.end.x - HudStyle.MARGIN), "weapon panel shrinks back and stays on the right margin (%s -> %s)" % [str(tall), str(short)])
	_arena.apply_snapshot([{"peer_id": OWN, "position": Vector3(25, 1, 2.5), "yaw": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0}])
	var long_chip := _arena.region_chip.size.x
	_arena.apply_snapshot([{"peer_id": OWN, "position": Vector3(25, 1, 11.5), "yaw": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0}])
	_expect(_arena.region_chip.size.x < long_chip, "region chip shrinks for a shorter zone name (%s -> %s)" % [long_chip, _arena.region_chip.size.x])
	_hud.apply_roster(_roster_with_dead([OWN]))
	_hud.apply_spectator_state(true, [7, 8], 7)
	_check_panels({"eliminated": _hud._eliminated_band, "observe": _hud._observe_panel, "status": _hud._status_panel}, viewport_rect)

func _check_panels(panels: Dictionary, viewport_rect: Rect2) -> void:
	for panel_name in panels:
		var control: Control = panels[panel_name]
		var rect := control.get_global_rect()
		_expect(control.visible, "%s is visible" % panel_name)
		_expect(viewport_rect.encloses(rect), "%s stays on screen (%s)" % [panel_name, str(rect)])
		_expect(not rect.intersects(_center_free), "%s stays out of the central view (%s)" % [panel_name, str(rect)])
		_expect(rect.position.x >= HudStyle.MARGIN - 0.5 and rect.end.x <= viewport_rect.size.x - HudStyle.MARGIN + 0.5 and rect.position.y >= HudStyle.MARGIN - 0.5 and rect.end.y <= viewport_rect.size.y - HudStyle.MARGIN + 0.5,
			"%s respects the 16 px safe margin (%s)" % [panel_name, str(rect)])

# --- Apoio ------------------------------------------------------------------------

func _public(state: int, round_id: int) -> Dictionary:
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

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("HUD_PRESENTATION_CHECK_FAILED %s" % description)
