class_name DesktopMenu
extends CanvasLayer

## Menu principal (fase 7). Apresentação e navegação: painéis (principal,
## criar partida local, entrar por LAN, jogar online, como jogar,
## configurações) e o painel de status do fluxo de conexão (`MenuFlow`).
## Valida o que o jogador digita e emite pedidos; quem cria processos e
## conecta é a `NetworkApp` (com `DesktopSession`). O menu não decide regra de
## rodada, não usa o nome como identidade, não instancia a mansão e não envia
## RPC.

signal host_requested(player_name: String, port: int, lan: bool, attempt: int)
signal join_requested(player_name: String, address: String, port: int, attempt: int)
signal online_requested(player_name: String, url: String, attempt: int)
signal cancel_requested(attempt: int)
signal quit_requested
signal input_rejected(field: String)
signal settings_changed(settings: MenuSettings)
## Fase 9 (salas online): pedidos do lobby online e da sala. O menu só pede;
## quem cria, entra e decide PRONTO/início é o servidor.
signal room_create_requested(player_name: String)
signal room_join_requested(code: String, player_name: String)
signal room_ready_requested(ready: bool)
signal online_leave_requested

const PANELS := ["main", "host", "join", "online", "howto", "settings", "hall", "room"]
## Cor cosmética por aparência (só um ponto ao lado do nome na lista da sala).
const APPEARANCE_COLORS := {
	"ember": Color("#E0703A"), "moss": Color("#7FA35A"), "dawn": Color("#E3A0B0"), "night": Color("#5B6FB0"),
	"cedar": Color("#A8583C"), "ash": Color("#A8A8A8"), "sand": Color("#D9C08A"), "plum": Color("#9B5FA8"),
}
const CARD_WIDTH := 452.0

## Argumentos do processo (endpoint online, automação). Definir antes de
## adicionar o menu à árvore.
var arguments: Dictionary = {}
var flow := MenuFlow.new()
var settings: MenuSettings
var online: Dictionary = {}
var panel_name := "main"
var panels: Dictionary = {}
var buttons: Dictionary = {}
var fields: Dictionary = {}
var errors: Dictionary = {}
var lan_check: CheckBox
var status_box: VBoxContainer
var status_label: Label
var spinner: MenuSpinner
var backdrop: MenuBackdrop
var root: Control
var card: PanelContainer
var panel_stack: Control
var last_request: Dictionary = {}
var sounds_played: Dictionary = {}
var _player: AudioStreamPlayer
var _fade: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings = MenuSettings.load_saved()
	settings.apply_audio()
	settings.apply_saved_display_once()
	online = OnlineEndpoint.resolve(arguments)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuTheme.theme()
	add_child(root)
	backdrop = MenuBackdrop.new()
	backdrop.reduce_motion = settings.reduce_motion
	root.add_child(backdrop)
	_build_card()
	if DisplayServer.get_name() != "headless":
		_player = AudioStreamPlayer.new()
		add_child(_player)
	_show_panel("main", false)
	print("MENU_READY name=%s online=%s source=%s" % [fields["name"].text, "configured" if bool(online["ok"]) else str(online["reason"]), online["source"]])

# --- Construção ---------------------------------------------------------------------

func _build_card() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	margin.add_theme_constant_override("margin_left", 44)
	root.add_child(margin)
	var column := HBoxContainer.new()
	margin.add_child(column)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuTheme.card_style())
	card.custom_minimum_size.x = CARD_WIDTH
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	column.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	card.add_child(body)
	var title := MenuTheme.label("ARMED MYSTERY", MenuTheme.TITLE_SIZE, MenuTheme.CREAM)
	title.add_theme_font_override("font", MenuTheme.serif())
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var subtitle := MenuTheme.label("Alguém nesta mansão não é quem diz ser.", MenuTheme.SUBTITLE_SIZE, MenuTheme.GOLD)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(subtitle)
	body.add_child(HSeparator.new())
	panel_stack = VBoxContainer.new()
	body.add_child(panel_stack)
	panels["main"] = _build_main()
	panels["host"] = _build_host()
	panels["join"] = _build_join()
	panels["online"] = _build_online()
	panels["howto"] = _build_howto()
	panels["settings"] = _build_settings()
	panels["hall"] = _build_hall()
	panels["room"] = _build_room()
	for panel_id in PANELS:
		panel_stack.add_child(panels[panel_id])
	status_box = _build_status()
	body.add_child(status_box)
	# Versão/protocolo só discretamente em build de desenvolvimento.
	var footer := MenuTheme.label("Protocolo %d · build de desenvolvimento" % NetworkConfig.PROTOCOL_VERSION, MenuTheme.SMALL_SIZE - 1, Color(MenuTheme.MUTED, 0.7))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.visible = OS.is_debug_build() and not OS.has_feature("template")
	body.add_child(footer)

func _panel() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	box.visible = false
	return box

func _field(id: String, label_text: String, value: String, placeholder: String, parent: Container, max_length: int = 0) -> LineEdit:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.add_child(MenuTheme.label(label_text, MenuTheme.SMALL_SIZE, MenuTheme.PARCHMENT))
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.custom_minimum_size.y = 36
	edit.focus_mode = Control.FOCUS_ALL
	if max_length > 0:
		edit.max_length = max_length
	edit.text_submitted.connect(func(_text): _submit_current())
	row.add_child(edit)
	var error := MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.ERROR, true)
	error.visible = false
	row.add_child(error)
	parent.add_child(row)
	fields[id] = edit
	errors[id] = error
	return edit

func _button(id: String, text: String, parent: Container, primary: bool, action: Callable) -> Button:
	var node := MenuTheme.button(text, primary)
	node.pressed.connect(func():
		print("MENU_BUTTON id=%s panel=%s state=%s" % [id, panel_name, flow.state_name()])
		action.call())
	node.focus_entered.connect(func(): _sound("ui_move"))
	parent.add_child(node)
	buttons[id] = node
	return node

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	return row

func _build_main() -> VBoxContainer:
	var box := _panel()
	var saved_name := settings.player_name if not settings.player_name.is_empty() else DesktopSession.default_player_name()
	_field("name", "Seu nome", saved_name, "Como os outros vão te ver", box, RoundRules.MAX_LABEL_LENGTH)
	var online_primary := bool(online["ok"])
	# Com servidor configurado, JOGAR ONLINE conecta e abre o lobby online;
	# sem servidor, mostra o aviso (sem tentar conexão).
	_button("online", "JOGAR ONLINE", box, online_primary, func(): _submit_online() if bool(online["ok"]) else _show_panel("online"))
	_button("host", "CRIAR PARTIDA LOCAL", box, not online_primary, func(): _open_with_name("host"))
	_button("join", "ENTRAR EM PARTIDA LAN", box, false, func(): _open_with_name("join"))
	var row := _row()
	_button("howto", "COMO JOGAR", row, false, func(): _show_panel("howto"))
	_button("settings", "CONFIGURAÇÕES", row, false, func(): _show_panel("settings"))
	for id in ["howto", "settings"]:
		(buttons[id] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(row)
	if MenuSettings.supports_quit():
		_button("quit", "SAIR", box, false, _quit)
	return box

func _build_host() -> VBoxContainer:
	var box := _panel()
	box.add_child(MenuTheme.heading("Criar partida local"))
	_field("host_name", "Seu nome", "", "", box, RoundRules.MAX_LABEL_LENGTH)
	_field("host_port", "Porta", str(DesktopSession.DEFAULT_PORT), "ex.: %d" % DesktopSession.DEFAULT_PORT, box, 5)
	lan_check = CheckBox.new()
	lan_check.text = "Permitir jogadores da rede local"
	lan_check.focus_mode = Control.FOCUS_ALL
	box.add_child(lan_check)
	var hint := MenuTheme.label("Desmarcado: a partida fica só neste computador.\nMarcado: outros computadores da mesma rede entram pelo seu IP local.", MenuTheme.SMALL_SIZE, MenuTheme.MUTED, true)
	box.add_child(hint)
	var row := _row()
	_button("host_back", "VOLTAR", row, false, func(): _show_panel("main"))
	_button("host_create", "CRIAR PARTIDA", row, true, _submit_host)
	_expand(row)
	box.add_child(row)
	return box

func _build_join() -> VBoxContainer:
	var box := _panel()
	box.add_child(MenuTheme.heading("Entrar em partida LAN"))
	_field("join_name", "Seu nome", "", "", box, RoundRules.MAX_LABEL_LENGTH)
	var address_row := _row()
	var address_col := VBoxContainer.new()
	address_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	address_row.add_child(address_col)
	_field("join_address", "Endereço (IP do anfitrião)", DesktopSession.LOOPBACK_ADDRESS, "ex.: 192.168.0.10", address_col, 253)
	var port_col := VBoxContainer.new()
	port_col.custom_minimum_size.x = 110
	address_row.add_child(port_col)
	_field("join_port", "Porta", str(DesktopSession.DEFAULT_PORT), str(DesktopSession.DEFAULT_PORT), port_col, 5)
	box.add_child(address_row)
	box.add_child(MenuTheme.label("No mesmo computador, use 127.0.0.1.", MenuTheme.SMALL_SIZE, MenuTheme.MUTED, true))
	var row := _row()
	_button("join_back", "VOLTAR", row, false, func(): _show_panel("main"))
	_button("join_enter", "ENTRAR", row, true, _submit_join)
	_expand(row)
	box.add_child(row)
	return box

func _build_online() -> VBoxContainer:
	var box := _panel()
	box.add_child(MenuTheme.heading("Jogar online"))
	var text := ""
	if bool(online["ok"]):
		text = "Servidor: %s%s" % [online["host"], "" if bool(online["secure"]) else " (sem criptografia)"]
	else:
		text = str(online["message"])
	var info := MenuTheme.label(text, MenuTheme.BODY_SIZE, MenuTheme.PARCHMENT if bool(online["ok"]) else MenuTheme.ERROR, true)
	info.name = "OnlineInfo"
	box.add_child(info)
	var row := _row()
	_button("online_back", "VOLTAR", row, not bool(online["ok"]), func(): _show_panel("main"))
	if bool(online["ok"]):
		_button("online_connect", "CONECTAR", row, true, _submit_online)
	_expand(row)
	box.add_child(row)
	return box

# --- Salas online (fase 9) ------------------------------------------------------

var room_view: Dictionary = {}
var room_own_peer_id := 0
var room_request_pending := false
var room_ready_pending := false
var room_title: Label
var room_players: VBoxContainer
var room_status: Label
var room_result: Label
var room_copy_feedback: Label
var hall_info: Label

func _build_hall() -> VBoxContainer:
	var box := _panel()
	box.add_child(MenuTheme.heading("Lobby online"))
	hall_info = MenuTheme.label("Conectado. Crie uma sala e mande o código aos amigos, ou entre com o código de alguém.", MenuTheme.SMALL_SIZE, MenuTheme.PARCHMENT, true)
	box.add_child(hall_info)
	_field("hall_name", "Seu nome", "", "Como os outros vão te ver", box, RoundRules.MAX_LABEL_LENGTH)
	_button("room_create", "CRIAR SALA", box, true, _submit_room_create)
	var code_row := _row()
	var code_col := VBoxContainer.new()
	code_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_row.add_child(code_col)
	_field("room_code", "Código da sala", "", "ex.: ABC-234", code_col, RoomRules.MAX_RAW_CODE_LENGTH)
	var join_col := VBoxContainer.new()
	join_col.alignment = BoxContainer.ALIGNMENT_END
	code_row.add_child(join_col)
	_button("room_join", "ENTRAR EM SALA", join_col, false, _submit_room_join)
	box.add_child(code_row)
	_button("hall_back", "VOLTAR", box, false, _leave_online)
	return box

func _build_room() -> VBoxContainer:
	var box := _panel()
	var title_row := _row()
	room_title = MenuTheme.heading("Sala")
	room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(room_title)
	_button("room_copy", "COPIAR CÓDIGO", title_row, false, _copy_room_code)
	box.add_child(title_row)
	room_copy_feedback = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.MUTED, true)
	room_copy_feedback.visible = false
	box.add_child(room_copy_feedback)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)
	# O resultado da última rodada vem antes da lista: é o que o jogador quer
	# ver ao voltar da partida.
	room_result = MenuTheme.label("", MenuTheme.SMALL_SIZE, MenuTheme.PARCHMENT, true)
	room_result.visible = false
	content.add_child(room_result)
	room_players = VBoxContainer.new()
	room_players.add_theme_constant_override("separation", 2)
	content.add_child(room_players)
	room_status = MenuTheme.label("", MenuTheme.BODY_SIZE, MenuTheme.CREAM, true)
	box.add_child(room_status)
	var row := _row()
	_button("room_leave", "SAIR DA SALA", row, false, _leave_online)
	_button("room_ready", "PRONTO", row, true, _toggle_ready)
	_expand(row)
	box.add_child(row)
	return box

## Conectado ao servidor online: mostra o lobby online (criar/entrar).
func show_hall() -> void:
	if flow.state != MenuFlow.State.ONLINE:
		enter(MenuFlow.State.ONLINE, "", flow.attempt)
	room_request_pending = false
	(fields["hall_name"] as LineEdit).text = (fields["name"] as LineEdit).text
	_show_panel("hall")
	print("MENU_ONLINE_HALL")

## Estado da sala vindo do servidor (já sanitizado). Mostra/atualiza a sala.
func show_room(dto: Dictionary, own_peer_id: int) -> void:
	if dto.is_empty():
		return
	var first := room_view.is_empty()
	room_view = dto
	room_own_peer_id = own_peer_id
	room_request_pending = false
	room_ready_pending = false
	if flow.state != MenuFlow.State.ONLINE:
		enter(MenuFlow.State.ONLINE, "", flow.attempt)
	_render_room()
	if panel_name != "room":
		_show_panel("room", not first)
	if first:
		print("MENU_ROOM_SHOWN code=%s" % str(dto["code"]))

func own_ready() -> bool:
	for entry in room_view.get("players", []):
		if int(entry["peer_id"]) == room_own_peer_id:
			return bool(entry["ready"])
	return false

func _render_room() -> void:
	var code := str(room_view.get("code", ""))
	room_title.text = "Sala %s" % RoomRules.display_code(code)
	for child in room_players.get_children():
		child.queue_free()
	var players: Array = room_view.get("players", [])
	for entry in players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := MenuTheme.label("●", MenuTheme.BODY_SIZE, APPEARANCE_COLORS.get(str(entry["appearance"]), MenuTheme.CREAM))
		row.add_child(dot)
		var name_text := str(entry["label"])
		if int(entry["peer_id"]) == room_own_peer_id:
			name_text += " (você)"
		var name_label := MenuTheme.label(name_text, MenuTheme.BODY_SIZE, MenuTheme.CREAM)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		if bool(entry["host"]):
			row.add_child(MenuTheme.label("ANFITRIÃO", MenuTheme.SMALL_SIZE, MenuTheme.GOLD))
		var ready := bool(entry["ready"])
		row.add_child(MenuTheme.label("PRONTO" if ready else "AGUARDANDO", MenuTheme.SMALL_SIZE, MenuTheme.OK if ready else MenuTheme.MUTED))
		room_players.add_child(row)
	var total := players.size()
	var ready_count := int(room_view.get("ready_count", 0))
	var min_players := int(room_view.get("min_players", RoundRules.MIN_PLAYERS))
	var phase := str(room_view.get("phase", RoomRules.PHASE_LOBBY))
	var status := ""
	match phase:
		RoomRules.PHASE_COUNTDOWN:
			status = "Todos prontos! A partida começa em %d s…" % int(ceil(float(room_view.get("countdown_msec", 0)) / 1000.0))
		RoomRules.PHASE_PLAYING:
			status = "Partida em andamento."
		RoomRules.PHASE_RESULTS:
			status = "Rodada encerrada. Voltando ao lobby da sala…"
		_:
			status = "%d de %d jogadores prontos." % [ready_count, total]
			if total < min_players:
				status += " Mínimo de %d jogadores para começar." % min_players
			elif ready_count < total:
				status += " A partida começa quando todos marcarem PRONTO."
	room_status.text = status
	var result: Dictionary = room_view.get("result", {})
	room_result.visible = not result.is_empty()
	if not result.is_empty():
		room_result.text = _result_text(result)
	var ready_button := buttons["room_ready"] as Button
	ready_button.text = "CANCELAR PRONTO" if own_ready() else "PRONTO"
	ready_button.disabled = phase not in [RoomRules.PHASE_LOBBY, RoomRules.PHASE_COUNTDOWN]
	print("MENU_ROOM phase=%s players=%d ready=%d own_ready=%s" % [phase, total, ready_count, str(own_ready())])

static func _result_text(result: Dictionary) -> String:
	var winner := "Inocentes venceram" if str(result["winner"]) == "INNOCENTS" else "O assassino venceu"
	var reason: String = {"assassin_down": "o assassino caiu", "innocents_down": "todos os inocentes caíram"}.get(str(result["reason"]), "")
	var roles := {"ASSASSIN": "Assassino", "DETECTIVE": "Detetive", "VICTIM": "Vítima"}
	var lines: Array = ["RESULTADO DA RODADA %d: %s%s." % [int(result["round_id"]), winner, (" — " + reason) if not reason.is_empty() else ""]]
	var parts: Array = []
	for entry in result["players"]:
		parts.append("%s: %s" % [str(entry["label"]), roles.get(str(entry["role"]), "?")])
	if not parts.is_empty():
		lines.append("Papéis: " + ", ".join(PackedStringArray(parts)) + ".")
	return "\n".join(PackedStringArray(lines))

## Erro de sala vindo do servidor, em português, no painel atual.
func show_room_error(reason: String) -> void:
	room_request_pending = false
	room_ready_pending = false
	var message := RoomRules.error_message(reason)
	print("MENU_ROOM_ERROR reason=%s" % reason)
	_sound("ui_error")
	if panel_name == "hall":
		var field := "hall_name" if reason in ["invalid_name", "name_taken"] else "room_code"
		var label: Label = errors[field]
		label.text = message
		label.visible = true
		_refresh_status()
	elif panel_name == "room":
		room_status.text = message
	_refresh_room_buttons()

func _submit_room_create() -> void:
	if room_request_pending or flow.state != MenuFlow.State.ONLINE:
		print("MENU_DUPLICATE_IGNORED action=room_create")
		return
	_clear_errors()
	var player_name := _validated_name("hall_name")
	if player_name.is_empty():
		return
	room_request_pending = true
	_refresh_room_buttons()
	_sound("ui_confirm")
	print("MENU_ROOM_CREATE")
	room_create_requested.emit(player_name)

func _submit_room_join() -> void:
	if room_request_pending or flow.state != MenuFlow.State.ONLINE:
		print("MENU_DUPLICATE_IGNORED action=room_join")
		return
	_clear_errors()
	var player_name := _validated_name("hall_name")
	if player_name.is_empty():
		return
	var code := RoomRules.normalize_code((fields["room_code"] as LineEdit).text)
	if code.is_empty():
		_reject("room_code", "room_code", RoomRules.error_message("invalid_code"))
		return
	(fields["room_code"] as LineEdit).text = RoomRules.display_code(code)
	room_request_pending = true
	_refresh_room_buttons()
	_sound("ui_confirm")
	print("MENU_ROOM_JOIN")
	room_join_requested.emit(code, player_name)

func _toggle_ready() -> void:
	if room_ready_pending or room_view.is_empty() or (buttons["room_ready"] as Button).disabled:
		print("MENU_DUPLICATE_IGNORED action=room_ready")
		return
	room_ready_pending = true
	var value := not own_ready()
	_sound("ui_confirm")
	print("MENU_ROOM_READY value=%s" % str(value))
	room_ready_requested.emit(value)

func _refresh_room_buttons() -> void:
	for id in ["room_create", "room_join"]:
		(buttons[id] as Button).disabled = room_request_pending

func _copy_room_code() -> void:
	var code := RoomRules.display_code(str(room_view.get("code", "")))
	if code.is_empty():
		return
	room_copy_feedback.visible = true
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(code)
		room_copy_feedback.text = "Código %s copiado. Mande para os amigos." % code
	else:
		room_copy_feedback.text = "Anote e mande aos amigos: %s" % code
	print("MENU_ROOM_COPY")

func _leave_online() -> void:
	print("MENU_ONLINE_LEAVE panel=%s" % panel_name)
	online_leave_requested.emit()

func _build_howto() -> VBoxContainer:
	var box := _panel()
	box.add_child(MenuTheme.heading("Como jogar"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 222)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	box.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)
	for line in [
		"Cada jogador recebe um papel secreto: assassino, detetive ou vítima. Só você vê o seu durante a rodada.",
		"Pistolas e munição ficam espalhadas pela mansão: é preciso pegar.",
		"Quem é eliminado fica caído no chão até a rodada seguinte e passa a observar os sobreviventes.",
		"No fim da rodada, todos os papéis são revelados.",
	]:
		content.add_child(MenuTheme.label("• " + line, MenuTheme.SMALL_SIZE + 1, MenuTheme.PARCHMENT, true))
	var current_group := ""
	var grid: GridContainer
	for row in GameControls.help_rows():
		if str(row["group"]) != current_group:
			current_group = str(row["group"])
			var group_label := MenuTheme.label(current_group.to_upper(), MenuTheme.SMALL_SIZE, MenuTheme.GOLD)
			content.add_child(group_label)
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 12)
			content.add_child(grid)
		var key := MenuTheme.label(str(row["input"]), MenuTheme.SMALL_SIZE, MenuTheme.CREAM)
		key.custom_minimum_size.x = 150
		key.name = "Key_%s" % (str(row["action"]) if not str(row["action"]).is_empty() else str(grid.get_child_count()))
		key.set_meta("action", str(row["action"]))
		grid.add_child(key)
		var text := MenuTheme.label(str(row["text"]), MenuTheme.SMALL_SIZE, MenuTheme.MUTED, true)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(text)
	_button("howto_back", "VOLTAR", box, true, func(): _show_panel("main"))
	return box

func _build_settings() -> VBoxContainer:
	var box := _panel()
	box.add_child(MenuTheme.heading("Configurações"))
	var volume := _slider(box, "settings_volume", "Volume geral", MenuSettings.VOLUME_MIN, MenuSettings.VOLUME_MAX, 0.05, settings.volume,
		func(v): return "%d%%" % int(round(v * 100.0)))
	volume.value_changed.connect(func(v):
		settings.volume = v
		settings.apply_audio()
		_save_settings())
	var sensitivity := _slider(box, "settings_sensitivity", "Sensibilidade do mouse", MenuSettings.SENSITIVITY_MIN, MenuSettings.SENSITIVITY_MAX, 0.05, settings.sensitivity,
		func(v): return "%.2f×" % v)
	sensitivity.value_changed.connect(func(v):
		settings.sensitivity = MenuSettings.clamp_sensitivity(v)
		_save_settings())
	if MenuSettings.supports_display_settings():
		var fullscreen := CheckBox.new()
		fullscreen.text = "Tela cheia"
		fullscreen.button_pressed = settings.fullscreen
		fullscreen.focus_mode = Control.FOCUS_ALL
		box.add_child(fullscreen)
		buttons["settings_fullscreen"] = fullscreen
		var resolution := OptionButton.new()
		resolution.focus_mode = Control.FOCUS_ALL
		for size in MenuSettings.RESOLUTIONS:
			resolution.add_item("%d × %d" % [size.x, size.y])
		resolution.select(MenuSettings.RESOLUTIONS.find(settings.resolution))
		resolution.disabled = settings.fullscreen
		var resolution_row := _row()
		resolution_row.add_child(MenuTheme.label("Janela", MenuTheme.SMALL_SIZE, MenuTheme.PARCHMENT))
		resolution.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		resolution_row.add_child(resolution)
		box.add_child(resolution_row)
		buttons["settings_resolution"] = resolution
		fullscreen.toggled.connect(func(on):
			settings.fullscreen = on
			resolution.disabled = on
			settings.apply_display()
			_save_settings())
		resolution.item_selected.connect(func(index):
			settings.resolution = MenuSettings.RESOLUTIONS[index]
			settings.apply_display()
			_save_settings())
	var motion := CheckBox.new()
	motion.text = "Reduzir movimento da interface"
	motion.button_pressed = settings.reduce_motion
	motion.focus_mode = Control.FOCUS_ALL
	motion.toggled.connect(func(on):
		settings.reduce_motion = on
		backdrop.reduce_motion = on
		_save_settings())
	box.add_child(motion)
	buttons["settings_motion"] = motion
	_button("settings_back", "VOLTAR", box, true, func(): _show_panel("main"))
	return box

func _slider(parent: Container, id: String, text: String, minimum: float, maximum: float, step: float, value: float, format: Callable) -> HSlider:
	var header := _row()
	var name_label := MenuTheme.label(text, MenuTheme.SMALL_SIZE, MenuTheme.PARCHMENT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var value_label := MenuTheme.label(str(format.call(value)), MenuTheme.SMALL_SIZE, MenuTheme.CREAM)
	header.add_child(value_label)
	parent.add_child(header)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.focus_mode = Control.FOCUS_ALL
	slider.custom_minimum_size.y = 24
	slider.value_changed.connect(func(v): value_label.text = str(format.call(v)))
	parent.add_child(slider)
	buttons[id] = slider
	return slider

func _build_status() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.visible = false
	var row := _row()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	spinner = MenuSpinner.new()
	row.add_child(spinner)
	status_label = MenuTheme.label("", MenuTheme.BODY_SIZE + 1, MenuTheme.CREAM, true)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.custom_minimum_size.x = 320
	row.add_child(status_label)
	box.add_child(row)
	var actions := _row()
	_button("cancel", "CANCELAR", actions, false, _cancel)
	_button("status_back", "VOLTAR", actions, false, _dismiss_status)
	_button("retry", "TENTAR NOVAMENTE", actions, true, _retry)
	_expand(actions)
	box.add_child(actions)
	return box

func _expand(row: HBoxContainer) -> void:
	for child in row.get_children():
		if child is Control:
			(child as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL

# --- Navegação --------------------------------------------------------------------

func _open_with_name(panel_id: String) -> void:
	var name_text: String = fields["name"].text
	fields[panel_id + "_name"].text = name_text
	_show_panel(panel_id)

func _show_panel(panel_id: String, animate: bool = true) -> void:
	if flow.busy():
		return
	_clear_errors()
	panel_name = panel_id
	for id in PANELS:
		(panels[id] as Control).visible = id == panel_id
	_refresh_status()
	print("MENU_PANEL name=%s" % panel_id)
	if animate:
		_sound("ui_move")
		if not settings.reduce_motion:
			if _fade != null and _fade.is_valid():
				_fade.kill()
			panel_stack.modulate.a = 0.0
			_fade = create_tween()
			_fade.tween_property(panel_stack, "modulate:a", 1.0, 0.14)
	call_deferred("_focus_first")

func _focus_first() -> void:
	var target: Control = _first_focus_target()
	if target != null and target.is_visible_in_tree():
		target.grab_focus()

func _first_focus_target() -> Control:
	if status_box.visible:
		for id in ["cancel", "retry", "status_back"]:
			if (buttons[id] as Button).visible and not (buttons[id] as Button).disabled:
				return buttons[id]
		return null
	match panel_name:
		"main": return fields["name"]
		"host": return buttons["host_create"]
		"join": return fields["join_address"]
		"online": return buttons["online_connect"] if buttons.has("online_connect") else buttons["online_back"]
		"hall": return buttons["room_create"]
		"room": return buttons["room_ready"]
		"howto": return buttons["howto_back"]
		"settings": return buttons["settings_volume"]
	return null

## Enter: ação principal do painel (ou avançar do campo de nome).
func _submit_current() -> void:
	if flow.busy():
		return
	match panel_name:
		"main":
			if bool(online["ok"]): _submit_online()
			else: _open_with_name("host")
		"hall":
			if not (fields["room_code"] as LineEdit).text.strip_edges().is_empty(): _submit_room_join()
			else: _submit_room_create()
		"room": _toggle_ready()
		"host": _submit_host()
		"join": _submit_join()
		"online":
			if bool(online["ok"]): _submit_online()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_escape()

## Esc: cancela a conexão, fecha o aviso de falha ou volta ao painel principal.
func _escape() -> void:
	print("MENU_ESCAPE panel=%s state=%s" % [panel_name, flow.state_name()])
	if bool(flow.spec()["cancel"]):
		_cancel()
	elif status_box.visible and not flow.busy():
		_dismiss_status()
	elif panel_name in ["hall", "room"]:
		_leave_online()
	elif panel_name != "main" and not flow.busy():
		_show_panel("main")

# --- Pedidos ---------------------------------------------------------------------

func _validated_name(field_id: String) -> String:
	var clean := (fields[field_id] as LineEdit).text.strip_edges()
	var problem := RoundRules.label_problem(clean)
	if not problem.is_empty():
		_reject(field_id, "name", name_message(problem))
		return ""
	(fields[field_id] as LineEdit).text = clean
	fields["name"].text = clean
	settings.player_name = clean
	_save_settings()
	return clean

static func name_message(problem: String) -> String:
	match problem:
		"empty": return "Digite seu nome para entrar na mansão."
		"too_long": return "Nome muito longo: use até %d caracteres." % RoundRules.MAX_LABEL_LENGTH
		"spaces": return "Evite espaços seguidos no nome."
	return "Use só letras, números, espaço, hífen (-) ou sublinhado (_)."

func _validated_port(field_id: String) -> int:
	var port := DesktopSession.parse_port((fields[field_id] as LineEdit).text)
	if port < 0:
		_reject(field_id, "port", "Porta inválida: use um número de %d a %d." % [DesktopSession.MIN_PORT, DesktopSession.MAX_PORT])
	return port

func _submit_host() -> void:
	if flow.busy():
		print("MENU_DUPLICATE_IGNORED action=host source=menu")
		return
	var attempt := flow.begin_attempt()
	_refresh_status()
	_clear_errors()
	var player_name := _validated_name("host_name")
	var port := _validated_port("host_port") if not player_name.is_empty() else -1
	if player_name.is_empty() or port < 0:
		flow.go(MenuFlow.State.IDLE)
		_refresh_status()
		return
	last_request = {"kind": "host", "panel": "host", "name": player_name, "port": port, "lan": lan_check.button_pressed}
	DesktopSession.last_request = last_request.duplicate()
	_sound("ui_confirm")
	host_requested.emit(player_name, port, lan_check.button_pressed, attempt)

func _submit_join() -> void:
	if flow.busy():
		print("MENU_DUPLICATE_IGNORED action=join source=menu")
		return
	var attempt := flow.begin_attempt()
	_refresh_status()
	_clear_errors()
	var player_name := _validated_name("join_name")
	var address := ""
	var port := -1
	if not player_name.is_empty():
		address = (fields["join_address"] as LineEdit).text.strip_edges()
		var address_error := DesktopSession.validate_address(address)
		if not address_error.is_empty():
			_reject("join_address", "address", address_error)
			address = ""
		else:
			port = _validated_port("join_port")
	if player_name.is_empty() or address.is_empty() or port < 0:
		flow.go(MenuFlow.State.IDLE)
		_refresh_status()
		return
	last_request = {"kind": "join", "panel": "join", "name": player_name, "address": address, "port": port}
	DesktopSession.last_request = last_request.duplicate()
	_sound("ui_confirm")
	join_requested.emit(player_name, address, port, attempt)

func _submit_online() -> void:
	if flow.busy():
		print("MENU_DUPLICATE_IGNORED action=online source=menu")
		return
	if not bool(online["ok"]):
		return
	var attempt := flow.begin_attempt()
	_refresh_status()
	var player_name := _validated_name("name")
	if player_name.is_empty():
		flow.go(MenuFlow.State.IDLE)
		_show_panel("main", false)
		_reject("name", "name", name_message(RoundRules.label_problem((fields["name"] as LineEdit).text)))
		return
	last_request = {"kind": "online", "panel": "online", "name": player_name}
	DesktopSession.last_request = last_request.duplicate()
	_sound("ui_confirm")
	online_requested.emit(player_name, str(online["url"]), attempt)

func _reject(field_id: String, kind: String, message: String) -> void:
	print("MENU_INPUT_INVALID field=%s" % kind)
	var label: Label = errors[field_id]
	label.text = message
	label.visible = true
	_sound("ui_error")
	(fields[field_id] as LineEdit).grab_focus()
	input_rejected.emit(kind)

func _clear_errors() -> void:
	for id in errors:
		(errors[id] as Label).visible = false

func _cancel() -> void:
	if not bool(flow.spec()["cancel"]):
		return
	var attempt := flow.attempt
	print("MENU_CANCEL_REQUESTED attempt=%d state=%s" % [attempt, flow.state_name()])
	cancel_requested.emit(attempt)

func _retry() -> void:
	if flow.state != MenuFlow.State.FAILED and flow.state != MenuFlow.State.DISCONNECTED:
		return
	var request: Dictionary = last_request if not last_request.is_empty() else DesktopSession.last_request
	if request.is_empty():
		_dismiss_status()
		return
	print("MENU_RETRY kind=%s" % request["kind"])
	flow.go(MenuFlow.State.IDLE)
	_restore_request(request)
	_show_panel(str(request["panel"]), false)
	match str(request["kind"]):
		"host": _submit_host()
		"join": _submit_join()
		"online": _submit_online()

func _dismiss_status() -> void:
	if flow.state == MenuFlow.State.FAILED or flow.state == MenuFlow.State.DISCONNECTED:
		flow.go(MenuFlow.State.IDLE)
	_refresh_status()
	_focus_first()

func _quit() -> void:
	if flow.busy():
		return
	flow.go(MenuFlow.State.SHUTTING_DOWN)
	_refresh_status()
	quit_requested.emit()

func _save_settings() -> void:
	settings.save()
	settings_changed.emit(settings)

# --- Estado vindo da rede ----------------------------------------------------------

## Evento do fluxo de conexão. Ignorado se for de outra tentativa.
func enter(state: int, text: String = "", attempt: int = 0) -> bool:
	var previous := flow.state_name()
	if not flow.go(state, text, attempt):
		print("MENU_STALE_EVENT_IGNORED state=%s attempt=%d current=%d at=%s" % [MenuFlow.NAMES.get(state, "?"), attempt, flow.attempt, previous])
		return false
	print("MENU_STATE %s>%s attempt=%d" % [previous, flow.state_name(), flow.attempt])
	if state == MenuFlow.State.FAILED:
		_sound("ui_error")
	_refresh_status()
	return true

func fail(message: String, attempt: int = 0) -> bool:
	return enter(MenuFlow.State.FAILED, message, attempt)

func _refresh_status() -> void:
	var spec := flow.spec()
	var overlay := bool(spec["overlay"])
	status_box.visible = overlay
	panel_stack.visible = not overlay
	status_label.text = flow.message
	var failed := flow.state == MenuFlow.State.FAILED
	status_label.add_theme_color_override("font_color", MenuTheme.ERROR if failed else MenuTheme.CREAM)
	spinner.visible = bool(spec["spinner"])
	spinner.animate = not settings.reduce_motion
	(buttons["cancel"] as Button).visible = bool(spec["cancel"])
	var recoverable := flow.state in [MenuFlow.State.FAILED, MenuFlow.State.DISCONNECTED]
	(buttons["retry"] as Button).visible = recoverable and not (last_request.is_empty() and DesktopSession.last_request.is_empty())
	(buttons["status_back"] as Button).visible = recoverable
	var inputs := bool(spec["inputs"])
	for id in buttons:
		if buttons[id] is BaseButton and id not in ["cancel", "retry", "status_back"]:
			(buttons[id] as BaseButton).disabled = not inputs
	for id in fields:
		(fields[id] as LineEdit).editable = inputs
	if inputs:
		# Salas: pedido em curso e PRONTO só no lobby/contagem da sala.
		_refresh_room_buttons()
		if not room_view.is_empty():
			(buttons["room_ready"] as Button).disabled = str(room_view.get("phase", "")) not in [RoomRules.PHASE_LOBBY, RoomRules.PHASE_COUNTDOWN]
	if overlay:
		call_deferred("_focus_first")

## Depois de voltar ao menu (recarga da cena): o mesmo painel, com os campos
## da última tentativa e o resultado dela.
func restore_after_return(request: Dictionary, kind: String, message: String) -> void:
	if request.is_empty():
		if not message.is_empty():
			flow.go(MenuFlow.State.VALIDATING)
			enter(MenuFlow.State.FAILED if kind == "failure" else MenuFlow.State.IDLE, message)
			if kind == "info":
				_show_info(message)
		return
	last_request = request.duplicate()
	_restore_request(request)
	_show_panel(str(request["panel"]), false)
	if kind == "cancelled" or message.is_empty():
		return
	flow.begin_attempt()
	if kind == "info":
		flow.go(MenuFlow.State.FAILED)
		_show_info(message)
	else:
		enter(MenuFlow.State.FAILED, message)

func _show_info(message: String) -> void:
	# Aviso neutro (fim coordenado, saída voluntária): sem cor de erro.
	flow.message = message
	_refresh_status()
	status_label.add_theme_color_override("font_color", MenuTheme.PARCHMENT)

func _restore_request(request: Dictionary) -> void:
	var player_name := str(request.get("name", fields["name"].text))
	for id in ["name", "host_name", "join_name"]:
		(fields[id] as LineEdit).text = player_name
	if request.has("port"):
		(fields["host_port"] as LineEdit).text = str(request["port"])
		(fields["join_port"] as LineEdit).text = str(request["port"])
	if request.has("address"):
		(fields["join_address"] as LineEdit).text = str(request["address"])
	if request.has("lan"):
		lan_check.button_pressed = bool(request["lan"])

# --- Automação (testes e atalhos) -----------------------------------------------------

## Aciona um botão como um clique do jogador: só se estiver visível e ativo.
func press(id: String) -> bool:
	var node := buttons.get(id) as BaseButton
	if node == null or not node.is_visible_in_tree() or node.disabled:
		print("MENU_PRESS_IGNORED id=%s" % id)
		return false
	node.pressed.emit()
	return true

func set_field(id: String, text: String) -> void:
	if fields.has(id):
		(fields[id] as LineEdit).text = text

## Preenche os campos como o jogador faria (mantido para os testes antigos).
func fill(player_name: String, host_port: String, lan: bool, address: String, join_port: String) -> void:
	if not player_name.is_empty():
		for id in ["name", "host_name", "join_name"]:
			(fields[id] as LineEdit).text = player_name
	if not host_port.is_empty(): (fields["host_port"] as LineEdit).text = host_port
	lan_check.button_pressed = lan
	if not address.is_empty(): (fields["join_address"] as LineEdit).text = address
	if not join_port.is_empty(): (fields["join_port"] as LineEdit).text = join_port

## Compatível com o menu anterior: status simples fora do fluxo.
func set_status(text: String, is_error: bool = false) -> void:
	if is_error:
		if flow.state == MenuFlow.State.IDLE:
			flow.begin_attempt()
		enter(MenuFlow.State.FAILED, text)
	else:
		flow.message = text
		_refresh_status()

func key_labels() -> Dictionary:
	var result := {}
	for node in (panels["howto"] as Control).find_children("Key_*", "Label", true, false):
		var action := str(node.get_meta("action", ""))
		if not action.is_empty():
			result[action] = (node as Label).text
	return result

# --- Som --------------------------------------------------------------------------

## Um som por evento de interface; eventos repetidos no mesmo quadro tocam uma
## vez só. Nenhum som no headless.
func _sound(sound_name: String) -> void:
	var frame := Engine.get_process_frames()
	if int(sounds_played.get(sound_name, -1)) == frame:
		return
	sounds_played[sound_name] = frame
	if _player == null:
		return
	_player.stream = SfxBank.stream(sound_name)
	_player.play()
