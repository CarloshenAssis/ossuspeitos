class_name RoundHud
extends CanvasLayer

## HUD de partida. É apresentação pura: não calcula papel, vitória, contagem,
## vida, munição nem estado de espectador. `view_model()` transforma apenas o
## que o servidor publicou (estado público, roster, papel privado do próprio
## jogador, estado privado de combate, alvos autorizados e revelação final) no
## que aparece na tela; os nós só desenham esse modelo. Existe só no cliente
## gráfico e nunca cobre o centro da visão durante a partida.
##
## Layout em 960×540 (escala 2× em 1920×1080 com `canvas_items`):
## - canto superior direito: fase da rodada e informações da sala;
## - inferior esquerdo: papel próprio ("SÓ VOCÊ VÊ") e vida oficial;
## - inferior direito: arma, carregador/reserva e recarga oficiais;
## - eliminado: faixa no topo e alvo observado + Q/E embaixo, sem dados de combate;
## - fim da rodada: tela cheia com vencedor, motivo e papéis revelados.

const MODE_LOBBY := "lobby"
const MODE_ALIVE := "alive"
const MODE_SPECTATOR := "spectator"
const MODE_ENDED := "ended"
const MODE_NEXT_ROUND := "next_round"

## Mesmo valor de `CombatAuthority.MAX_HEALTH`; o teste do HUD confere que os
## dois não divergem. Serve só para a largura da barra.
const HEALTH_BAR_MAX := 100
## Um tiro da pistola comum tira 34: com 34 ou menos, o próximo acerto mata.
const LOW_HEALTH := 34
const WEAPON_NAMES := {"common_pistol": "PISTOLA"}
const REASON_TEXT := {
	RoundRules.REASON_ASSASSIN_DOWN: "O assassino foi eliminado.",
	RoundRules.REASON_INNOCENTS_DOWN: "Todos os inocentes foram eliminados.",
}
const ROLE_FROM_LABEL := {"ASSASSIN": Role.ASSASSIN, "DETECTIVE": Role.DETECTIVE, "VICTIM": Role.VICTIM}

var _public: Dictionary = {}
var _role := Role.NONE
var _round_id := 0
var _own_peer_id := 0
var _roster: Array = []
var _combat: Dictionary = {}
var _spectator := {"eliminated": false, "targets": [], "target": 0}
var _reveal: Dictionary = {}
var _session_info := ""
var _damage_tween: Tween
var _last_health := -1
var _last_health_round := 0
var model: Dictionary = {}

var _status_panel: PanelContainer
var _status_title: Label
var _status_detail: Label
var _session_label: Label
var _role_panel: PanelContainer
var _role_label: Label
var _health_panel: PanelContainer
var _health_title: Label
var _health_value: Label
var _health_bar: ProgressBar
var _weapon_panel: PanelContainer
var _weapon_title: Label
var _weapon_ammo: Label
var _weapon_hint: Label
var _eliminated_band: PanelContainer
var _observe_panel: PanelContainer
var _observe_caption: Label
var _observe_name: Label
var _observe_keys: HBoxContainer
var _ended_screen: Control
var _ended_title: Label
var _ended_reason: Label
var _ended_rows: VBoxContainer
var _ended_footer: Label
var _damage_vignette: Control

func _ready() -> void:
	layer = 5
	_build()
	_render()

# --- Entradas (sempre dados oficiais) ------------------------------------------

func apply_round_state(payload: Dictionary, role: int, round_id: int, own_peer_id: int) -> void:
	_public = payload
	_role = role
	_round_id = round_id
	_own_peer_id = own_peer_id
	_render()

func apply_roster(entries: Array) -> void:
	_roster = entries
	_render()

func apply_combat_state(payload: Dictionary) -> void:
	var previous_health := _last_health
	var previous_round := _last_health_round
	_combat = payload.duplicate(true)
	if _combat.is_empty() or int(_combat.get("round_id", 0)) != previous_round:
		_clear_damage_flash()
	if not _combat.is_empty():
		_last_health = int(_combat.get("health", 0))
		_last_health_round = int(_combat.get("round_id", 0))
		# Vinheta de dano só quando a vida oficial desce dentro da mesma rodada.
		if previous_round == _last_health_round and previous_health > _last_health and _last_health >= 0:
			flash_damage()
	_render()

func apply_spectator_state(eliminated: bool, targets: Array, target_peer_id: int) -> void:
	_spectator = {"eliminated": eliminated, "targets": targets.duplicate(), "target": target_peer_id}
	_render()

func apply_final_reveal(payload: Dictionary) -> void:
	_reveal = payload.duplicate(true)
	_render()

func set_session_info(text: String) -> void:
	_session_info = text
	_render()

# --- Modelo puro ----------------------------------------------------------------

## Tudo que o HUD mostra, derivado só dos dados recebidos. Estático e sem nó,
## portanto verificável sem renderização.
static func view_model(public_state: Dictionary, role: int, role_round_id: int, own_peer_id: int,
		roster: Array, spectator: Dictionary = {}, reveal: Dictionary = {}, combat: Dictionary = {}) -> Dictionary:
	var state := int(public_state.get("state", RoundState.WAITING))
	if not RoundState.is_valid(state):
		state = RoundState.WAITING
	var round_id := int(public_state.get("round_id", 0))
	var connected := maxi(0, int(public_state.get("connected", 0)))
	var max_players := int(public_state.get("max_players", RoundRules.MAX_PLAYERS))
	var min_players := int(public_state.get("min_players", RoundRules.MIN_PLAYERS))
	var entry := own_entry(roster, own_peer_id)
	var result := {"mode": MODE_LOBBY, "state": state, "status": "", "status_detail": "",
		"role": {}, "health": {}, "weapon": {}, "spectator": {}, "ended": {}}

	if state == RoundState.WAITING:
		result["status"] = "AGUARDANDO JOGADORES"
		var missing := maxi(0, min_players - connected)
		result["status_detail"] = "Conectados %d/%d · %s" % [connected, max_players,
			("faltam %d para começar" % missing) if missing > 0 else "começando"]
		return result
	if state == RoundState.COUNTDOWN:
		result["status"] = "RODADA COMEÇA EM %ds" % int(ceil(float(maxi(0, int(public_state.get("countdown_msec", 0)))) / 1000.0))
		result["status_detail"] = "Conectados %d/%d" % [connected, max_players]
		return result
	if state == RoundState.ENDED:
		result["mode"] = MODE_ENDED
		result["status"] = "FIM DA RODADA"
		result["ended"] = _ended_model(public_state, own_peer_id, roster, reveal)
		return result

	# ACTIVE
	var participants := int(public_state.get("participants", 0))
	var alive_count := int(public_state.get("alive", 0))
	result["status"] = "EM PARTIDA"
	result["status_detail"] = "%d de %d vivos" % [alive_count, participants] if participants > 0 else ""
	if not entry.is_empty() and not bool(entry.get("participant", false)):
		result["mode"] = MODE_NEXT_ROUND
		result["status"] = "VOCÊ ENTRA NA PRÓXIMA RODADA"
		result["status_detail"] = "Rodada em andamento"
		return result
	# Eliminado: pelo aviso privado do servidor ou pelo roster oficial.
	var eliminated := bool(spectator.get("eliminated", false)) \
		or (not entry.is_empty() and not bool(entry.get("alive", true)))
	if eliminated:
		result["mode"] = MODE_SPECTATOR
		result["spectator"] = _spectator_model(spectator, roster)
		return result
	result["mode"] = MODE_ALIVE
	# Papel próprio só se for desta rodada. Nunca o de outro jogador.
	if Role.is_valid(role) and role_round_id == round_id and round_id > 0:
		result["role"] = {"role": role, "glyph": str(HudStyle.ROLE_GLYPHS[role]), "name": str(HudStyle.ROLE_NAMES[role])}
	# Vida e arma só do estado privado oficial desta rodada.
	if not combat.is_empty() and int(combat.get("round_id", 0)) == round_id and round_id > 0:
		var health := clampi(int(combat.get("health", 0)), 0, HEALTH_BAR_MAX)
		result["health"] = {"value": health, "max": HEALTH_BAR_MAX, "low": health <= LOW_HEALTH}
		result["weapon"] = _weapon_model(combat)
	return result

static func _weapon_model(combat: Dictionary) -> Dictionary:
	var weapon_id := str(combat.get("weapon_id", ""))
	if weapon_id.is_empty():
		return {"armed": false, "name": "SEM ARMA", "ammo": "", "hint": "Procure uma pistola no mapa · E para pegar"}
	var magazine := maxi(0, int(combat.get("magazine", 0)))
	var reserve := maxi(0, int(combat.get("reserve", 0)))
	var reloading := bool(combat.get("reloading", false))
	var hint := ""
	if reloading:
		hint = "RECARREGANDO"
	elif magazine == 0 and reserve > 0:
		hint = "R para recarregar"
	elif magazine == 0:
		hint = "Sem munição · procure no mapa"
	return {"armed": true, "name": str(WEAPON_NAMES.get(weapon_id, weapon_id.to_upper())),
		"magazine": magazine, "reserve": reserve, "ammo": "%d / %d" % [magazine, reserve],
		"reloading": reloading, "hint": hint}

static func _spectator_model(spectator: Dictionary, roster: Array) -> Dictionary:
	var targets: Array = spectator.get("targets", [])
	var target := int(spectator.get("target", 0))
	var index := targets.find(target)
	if target <= 0 or index < 0:
		return {"title": "ELIMINADO", "subtitle": "Você não pode mais agir nesta rodada",
			"waiting": true, "target_name": "", "index": "",
			"waiting_title": "AGUARDANDO FIM DA RODADA", "waiting_detail": "Nenhum jogador vivo para observar"}
	return {"title": "ELIMINADO", "subtitle": "Você não pode mais agir nesta rodada",
		"waiting": false, "target_name": public_label(roster, target),
		"index": "%d/%d" % [index + 1, targets.size()], "controls": "Q / E trocar jogador"}

static func _ended_model(public_state: Dictionary, own_peer_id: int, roster: Array, reveal: Dictionary) -> Dictionary:
	var team := int(public_state.get("winning_team", Role.TEAM_NONE))
	var reason := str(public_state.get("winner_reason", ""))
	var ended := {
		"team": team,
		"title": "INOCENTES VENCEM" if team == Role.TEAM_INNOCENTS else ("ASSASSINO VENCE" if team == Role.TEAM_ASSASSIN else "RODADA ENCERRADA"),
		"reason": str(REASON_TEXT.get(reason, reason)),
		"rows": [],
		"revealed": false,
		"footer": "Nova rodada em instantes · retornando ao lobby",
	}
	# Papéis só da revelação oficial desta mesma rodada, recebida em ENDED.
	if int(reveal.get("round_id", -1)) != int(public_state.get("round_id", 0)) or int(reveal.get("round_id", 0)) <= 0:
		return ended
	var rows: Array = []
	for raw_player in reveal.get("players", []):
		if typeof(raw_player) != TYPE_DICTIONARY:
			continue
		var player: Dictionary = raw_player
		var peer_id := int(player.get("peer_id", 0))
		var revealed_role := int(ROLE_FROM_LABEL.get(str(player.get("role", "")), Role.NONE))
		if peer_id <= 0 or not Role.is_valid(revealed_role):
			continue
		var entry := own_entry(roster, peer_id)
		var status := "—" if entry.is_empty() else ("Vivo" if bool(entry.get("alive", true)) else "Eliminado")
		rows.append({"peer_id": peer_id, "name": public_label(roster, peer_id), "you": peer_id == own_peer_id,
			"role": revealed_role, "glyph": str(HudStyle.ROLE_GLYPHS[revealed_role]),
			"role_name": str(HudStyle.ROLE_NAMES[revealed_role]), "status": status})
	ended["rows"] = rows
	ended["revealed"] = true
	return ended

## Todas as linhas de texto visíveis para um modelo, na ordem da tela. Usado
## pelos testes e útil para depurar; não é o que desenha a interface.
static func compose_lines(public_state: Dictionary, role: int, own_peer_id: int, roster: Array,
		spectator: Dictionary = {}, reveal: Dictionary = {}, combat: Dictionary = {}, role_round_id: int = -1) -> Array:
	var round_for_role := role_round_id if role_round_id >= 0 else int(public_state.get("round_id", 0))
	return model_lines(view_model(public_state, role, round_for_role, own_peer_id, roster, spectator, reveal, combat))

static func model_lines(view: Dictionary) -> Array:
	var lines: Array = [str(view.get("status", ""))]
	if not str(view.get("status_detail", "")).is_empty():
		lines.append(str(view["status_detail"]))
	var role: Dictionary = view.get("role", {})
	if not role.is_empty():
		lines.append("SÓ VOCÊ VÊ %s %s" % [role["glyph"], role["name"]])
	var health: Dictionary = view.get("health", {})
	if not health.is_empty():
		lines.append("VIDA%s %d" % [" · BAIXA" if bool(health["low"]) else "", int(health["value"])])
	var weapon: Dictionary = view.get("weapon", {})
	if not weapon.is_empty():
		lines.append(str(weapon["name"]))
		if not str(weapon["ammo"]).is_empty(): lines.append(str(weapon["ammo"]))
		if not str(weapon["hint"]).is_empty(): lines.append(str(weapon["hint"]))
	var spectator: Dictionary = view.get("spectator", {})
	if not spectator.is_empty():
		lines.append(str(spectator["title"]))
		lines.append(str(spectator["subtitle"]))
		if bool(spectator["waiting"]):
			lines.append(str(spectator["waiting_title"]))
			lines.append(str(spectator["waiting_detail"]))
		else:
			lines.append("OBSERVANDO · %s" % spectator["index"])
			lines.append(str(spectator["target_name"]))
			lines.append(str(spectator["controls"]))
	var ended: Dictionary = view.get("ended", {})
	if not ended.is_empty():
		lines.append(str(ended["title"]))
		if not str(ended["reason"]).is_empty(): lines.append(str(ended["reason"]))
		if bool(ended["revealed"]):
			lines.append("PAPÉIS REVELADOS")
			for row in ended["rows"]:
				lines.append("%s%s  %s %s  %s" % [row["name"], " (VOCÊ)" if bool(row["you"]) else "", row["glyph"], row["role_name"], row["status"]])
		else:
			lines.append("Aguardando revelação dos papéis…")
		lines.append(str(ended["footer"]))
	return lines

static func public_label(roster: Array, peer_id: int) -> String:
	for raw_entry in roster:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		if int(entry.get("peer_id", 0)) == peer_id:
			return str(entry.get("label", "Jogador %d" % peer_id))
	return "Jogador %d" % peer_id

static func own_entry(roster: Array, own_peer_id: int) -> Dictionary:
	for raw_entry in roster:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		if typeof(entry.get("peer_id", 0)) == TYPE_INT and int(entry.get("peer_id", 0)) == own_peer_id:
			return entry
	return {}

# --- Desenho ----------------------------------------------------------------------

func _render() -> void:
	model = view_model(_public, _role, _round_id, _own_peer_id, _roster, _spectator, _reveal, _combat)
	if _status_panel == null:
		return
	var mode := str(model["mode"])
	_status_title.text = str(model["status"])
	_status_detail.text = str(model["status_detail"])
	_status_detail.visible = not _status_detail.text.is_empty()
	# Eliminado: a faixa central do topo precisa de espaço; mantém só a linha de
	# atalhos (Esc/F10) e esconde o endereço da sala.
	var session_text := _session_info
	if mode == MODE_SPECTATOR and session_text.contains("\n"):
		session_text = session_text.get_slice("\n", session_text.get_slice_count("\n") - 1)
	_session_label.text = session_text
	_session_label.visible = not session_text.is_empty()
	_status_panel.visible = mode != MODE_ENDED

	var role: Dictionary = model["role"]
	_role_panel.visible = mode == MODE_ALIVE and not role.is_empty()
	if not role.is_empty():
		_role_label.text = "%s %s" % [role["glyph"], role["name"]]
		_role_label.add_theme_color_override("font_color", HudStyle.ROLE_COLORS[int(role["role"])])

	var health: Dictionary = model["health"]
	_health_panel.visible = mode == MODE_ALIVE and not health.is_empty()
	if not health.is_empty():
		var low := bool(health["low"])
		var color := HudStyle.RED if low else HudStyle.BONE
		_health_title.text = "VIDA · BAIXA" if low else "VIDA"
		_health_value.text = str(int(health["value"]))
		_health_value.add_theme_color_override("font_color", color)
		_health_bar.max_value = float(health["max"])
		_health_bar.value = float(health["value"])
		(_health_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = color

	var weapon: Dictionary = model["weapon"]
	_weapon_panel.visible = mode == MODE_ALIVE and not weapon.is_empty()
	if not weapon.is_empty():
		_weapon_title.text = str(weapon["name"])
		_weapon_ammo.text = str(weapon["ammo"])
		_weapon_ammo.visible = bool(weapon["armed"])
		var empty_magazine: bool = bool(weapon["armed"]) and int(weapon.get("magazine", 0)) == 0
		_weapon_ammo.add_theme_color_override("font_color", HudStyle.AMBER if empty_magazine else HudStyle.BONE)
		_weapon_hint.text = str(weapon["hint"])
		_weapon_hint.visible = not _weapon_hint.text.is_empty()
		_weapon_hint.add_theme_color_override("font_color", HudStyle.AMBER if bool(weapon["armed"]) else HudStyle.MUTED)

	var spectator: Dictionary = model["spectator"]
	_eliminated_band.visible = mode == MODE_SPECTATOR
	_observe_panel.visible = mode == MODE_SPECTATOR
	if mode == MODE_SPECTATOR:
		var waiting := bool(spectator["waiting"])
		_observe_caption.text = str(spectator["waiting_detail"]) if waiting else "OBSERVANDO · %s" % spectator["index"]
		_observe_name.text = str(spectator["waiting_title"]) if waiting else str(spectator["target_name"])
		_observe_keys.visible = not waiting

	var ended: Dictionary = model["ended"]
	_ended_screen.visible = mode == MODE_ENDED
	if mode == MODE_ENDED:
		_ended_title.text = str(ended["title"])
		_ended_title.add_theme_color_override("font_color", HudStyle.RED if int(ended["team"]) == Role.TEAM_ASSASSIN else HudStyle.BONE)
		_ended_reason.text = str(ended["reason"])
		_ended_footer.text = str(ended["footer"])
		_render_reveal_rows(ended)

func _render_reveal_rows(ended: Dictionary) -> void:
	for child in _ended_rows.get_children():
		child.queue_free()
	if not bool(ended["revealed"]):
		_ended_rows.add_child(HudStyle.label("Aguardando revelação dos papéis…", 15, HudStyle.MUTED))
		return
	var compact := (ended["rows"] as Array).size() > 6
	for row in ended["rows"]:
		var line := PanelContainer.new()
		var style := HudStyle.panel_style(Color("#1A1E24") if bool(row["you"]) else Color(0, 0, 0, 0), HudStyle.LINE, 0)
		style.border_width_top = 1
		style.content_margin_top = 3.0 if compact else 6.0
		style.content_margin_bottom = 3.0 if compact else 6.0
		line.add_theme_stylebox_override("panel", style)
		var cells := HBoxContainer.new()
		cells.add_theme_constant_override("separation", 12)
		var name_label := HudStyle.label("%s%s" % [row["name"], "  VOCÊ" if bool(row["you"]) else ""], 15)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		cells.add_child(name_label)
		var role_label := HudStyle.label("%s %s" % [row["glyph"], row["role_name"]], 16, HudStyle.ROLE_COLORS[int(row["role"])])
		role_label.custom_minimum_size.x = 150
		cells.add_child(role_label)
		var status_label := HudStyle.label(str(row["status"]), 13, HudStyle.BONE if str(row["status"]) == "Vivo" else HudStyle.MUTED)
		status_label.custom_minimum_size.x = 90
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cells.add_child(status_label)
		line.add_child(cells)
		_ended_rows.add_child(line)

func flash_damage() -> void:
	if _damage_vignette == null:
		return
	_clear_damage_flash()
	_damage_vignette.modulate.a = 1.0
	_damage_tween = create_tween()
	_damage_tween.tween_property(_damage_vignette, "modulate:a", 0.0, 0.28)

## Estado limpo ou rodada nova: nenhum resto do flash de dano anterior.
func _clear_damage_flash() -> void:
	if _damage_tween != null:
		_damage_tween.kill()
		_damage_tween = null
	if _damage_vignette != null:
		_damage_vignette.modulate.a = 0.0

func _build() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_damage_vignette = _build_vignette()
	root.add_child(_damage_vignette)

	# Superior direito: fase + sala.
	_status_panel = HudStyle.panel()
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 0)
	_status_title = HudStyle.label("", 15)
	_status_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_detail = HudStyle.label("", 13, HudStyle.MUTED)
	_status_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_session_label = HudStyle.label("", 12, HudStyle.MUTED)
	_session_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_box.add_child(_status_title)
	status_box.add_child(_status_detail)
	status_box.add_child(_session_label)
	_status_panel.add_child(status_box)
	root.add_child(_status_panel)
	HudStyle.anchor_corner(_status_panel, Control.PRESET_TOP_RIGHT)

	# Inferior esquerdo: papel privado + vida.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size.x = 190
	_role_panel = HudStyle.panel()
	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 6)
	role_row.add_child(HudStyle.label("SÓ VOCÊ VÊ", 11, HudStyle.MUTED))
	_role_label = HudStyle.label("", 15)
	role_row.add_child(_role_label)
	_role_panel.add_child(role_row)
	_role_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(_role_panel)
	_health_panel = HudStyle.panel()
	var health_box := VBoxContainer.new()
	health_box.add_theme_constant_override("separation", 4)
	var health_row := HBoxContainer.new()
	_health_title = HudStyle.label("VIDA", 12, HudStyle.MUTED)
	_health_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_health_value = HudStyle.label("", 22)
	health_row.add_child(_health_title)
	health_row.add_child(_health_value)
	health_box.add_child(health_row)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.custom_minimum_size = Vector2(170, 6)
	var track := StyleBoxFlat.new()
	track.bg_color = HudStyle.LINE
	var fill := StyleBoxFlat.new()
	fill.bg_color = HudStyle.BONE
	_health_bar.add_theme_stylebox_override("background", track)
	_health_bar.add_theme_stylebox_override("fill", fill)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	health_box.add_child(_health_bar)
	_health_panel.add_child(health_box)
	left.add_child(_health_panel)
	root.add_child(left)
	HudStyle.anchor_corner(left, Control.PRESET_BOTTOM_LEFT)

	# Inferior direito: arma e munição oficiais.
	_weapon_panel = HudStyle.panel()
	_weapon_panel.custom_minimum_size.x = 170
	var weapon_box := VBoxContainer.new()
	weapon_box.add_theme_constant_override("separation", 2)
	_weapon_title = HudStyle.label("", 12, HudStyle.MUTED)
	_weapon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_ammo = HudStyle.label("", 28)
	_weapon_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weapon_hint = HudStyle.label("", 13, HudStyle.AMBER)
	_weapon_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_box.add_child(_weapon_title)
	weapon_box.add_child(_weapon_ammo)
	weapon_box.add_child(_weapon_hint)
	_weapon_panel.add_child(weapon_box)
	root.add_child(_weapon_panel)
	HudStyle.anchor_corner(_weapon_panel, Control.PRESET_BOTTOM_RIGHT)

	# Eliminado: faixa no topo e observação embaixo, ambas fora do centro.
	_eliminated_band = HudStyle.panel(Color(0.063, 0.071, 0.086, 0.85), HudStyle.RED, 2)
	var band := VBoxContainer.new()
	band.add_theme_constant_override("separation", 0)
	var band_title := HudStyle.label("✕  ELIMINADO", 28, HudStyle.RED)
	band_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var band_detail := HudStyle.label("Você não pode mais agir nesta rodada", 13)
	band_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	band.add_child(band_title)
	band.add_child(band_detail)
	_eliminated_band.add_child(band)
	root.add_child(_eliminated_band)
	HudStyle.anchor_corner(_eliminated_band, Control.PRESET_CENTER_TOP)

	_observe_panel = HudStyle.panel(Color(0.063, 0.071, 0.086, 0.85))
	var observe_row := HBoxContainer.new()
	observe_row.add_theme_constant_override("separation", 14)
	var observe_text := VBoxContainer.new()
	observe_text.add_theme_constant_override("separation", 0)
	_observe_caption = HudStyle.label("", 11, HudStyle.MUTED)
	_observe_name = HudStyle.label("", 20)
	observe_text.add_child(_observe_caption)
	observe_text.add_child(_observe_name)
	observe_row.add_child(observe_text)
	_observe_keys = HBoxContainer.new()
	_observe_keys.add_theme_constant_override("separation", 6)
	_observe_keys.alignment = BoxContainer.ALIGNMENT_CENTER
	_observe_keys.add_child(HudStyle.key_cap("Q"))
	_observe_keys.add_child(HudStyle.label("/", 14, HudStyle.MUTED))
	_observe_keys.add_child(HudStyle.key_cap("E"))
	_observe_keys.add_child(HudStyle.label("trocar jogador", 14))
	observe_row.add_child(_observe_keys)
	_observe_panel.add_child(observe_row)
	root.add_child(_observe_panel)
	HudStyle.anchor_corner(_observe_panel, Control.PRESET_CENTER_BOTTOM)

	# Fim da rodada: tela cheia (não há controle do personagem nesta fase).
	_ended_screen = ColorRect.new()
	(_ended_screen as ColorRect).color = Color(0.043, 0.051, 0.063, 0.88)
	_ended_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ended_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 520
	column.add_theme_constant_override("separation", 8)
	var caption := HudStyle.label("FIM DA RODADA", 12, HudStyle.MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ended_title = HudStyle.label("", 38)
	_ended_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ended_reason = HudStyle.label("", 15)
	_ended_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var revealed_caption := HudStyle.label("PAPÉIS REVELADOS", 12)
	revealed_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var table := HudStyle.panel(Color("#12151A"), HudStyle.LINE, 1)
	_ended_rows = VBoxContainer.new()
	_ended_rows.add_theme_constant_override("separation", 0)
	table.add_child(_ended_rows)
	_ended_footer = HudStyle.label("", 13, HudStyle.MUTED)
	_ended_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for node in [caption, _ended_title, _ended_reason, revealed_caption, table, _ended_footer]:
		column.add_child(node)
	center.add_child(column)
	_ended_screen.add_child(center)
	root.add_child(_ended_screen)

## Quatro faixas vermelhas nas bordas; o centro da visão fica livre.
func _build_vignette() -> Control:
	var vignette := Control.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.modulate.a = 0.0
	var edges := [
		[Control.PRESET_TOP_WIDE, Vector2(0, 36)], [Control.PRESET_BOTTOM_WIDE, Vector2(0, 36)],
		[Control.PRESET_LEFT_WIDE, Vector2(36, 0)], [Control.PRESET_RIGHT_WIDE, Vector2(36, 0)],
	]
	for edge in edges:
		var strip := ColorRect.new()
		strip.color = Color(HudStyle.RED, 0.45)
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.set_anchors_and_offsets_preset(edge[0])
		strip.custom_minimum_size = edge[1]
		if edge[0] == Control.PRESET_TOP_WIDE: strip.offset_bottom = 36
		elif edge[0] == Control.PRESET_BOTTOM_WIDE: strip.offset_top = -36
		elif edge[0] == Control.PRESET_LEFT_WIDE: strip.offset_right = 36
		else: strip.offset_left = -36
		vignette.add_child(strip)
	return vignette
