extends SceneTree

## Fase 7: menu principal e fluxo de conexão, sem rede. Usa o `DesktopMenu`
## real: botões acionados como um clique (`press`, que respeita visível e
## ativo), teclas (Tab, Enter, Esc) empurradas no viewport e os sinais
## emitidos para a `NetworkApp`. O fluxo com processos reais fica em
## `tests/menu_flow_test.sh`.

var failures := 0
var checks := 0
var _frame := 0
var _settings_path := ""
var menu: DesktopMenu
var emitted: Array = []

func _initialize() -> void:
	_settings_path = OS.get_user_data_dir().path_join("menu-test-%d.cfg" % OS.get_process_id())
	MenuSettings.path_override = _settings_path
	if FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(_settings_path)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_test_flow_model()
		_test_name_rules()
		_test_endpoint_rules()
		_test_settings_persistence()
		menu = _new_menu({})
		return false
	if _frame == 3:
		_test_main_screen()
		_test_navigation_and_escape()
		_test_focus_and_keys()
		return false
	if _frame == 5:
		_test_host_validation()
		_test_join_validation_duplicate_cancel_and_stale()
		_test_failure_and_retry()
		_test_return_messages()
		_test_online_not_configured()
		_test_controls_match_input_map()
		_test_settings_panel()
		_test_menu_builds_no_world()
		menu.queue_free()
		menu = null
		return false
	if _frame == 6:
		_test_online_configured_by_argument_and_setting()
		return false
	if _frame < 9:
		return false
	if FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(_settings_path)
	if failures > 0:
		push_error("MENU_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return true
	print("MENU_TEST_OK checks=%d" % checks)
	quit(0)
	return true

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("MENU_CHECK_FAILED %s" % message)

func _new_menu(arguments: Dictionary) -> DesktopMenu:
	var node := DesktopMenu.new()
	node.arguments = arguments
	root.add_child(node)
	node.host_requested.connect(func(n, p, l, a): emitted.append({"kind": "host", "name": n, "port": p, "lan": l, "attempt": a}))
	node.join_requested.connect(func(n, ad, p, a): emitted.append({"kind": "join", "name": n, "address": ad, "port": p, "attempt": a}))
	node.online_requested.connect(func(n, u, a): emitted.append({"kind": "online", "name": n, "url": u, "attempt": a}))
	node.cancel_requested.connect(func(a): emitted.append({"kind": "cancel", "attempt": a}))
	return node

func _key(code: int, shift: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.shift_pressed = shift
		event.pressed = pressed
		root.push_input(event)

func _focus() -> Control:
	return root.gui_get_focus_owner()

# --- Modelo, regras e persistência ---------------------------------------------------

func _test_flow_model() -> void:
	var flow := MenuFlow.new()
	_expect(flow.state == MenuFlow.State.IDLE and not flow.busy(), "flow starts idle")
	var first := flow.begin_attempt()
	_expect(first == 1 and flow.state == MenuFlow.State.VALIDATING, "attempt 1 validating")
	_expect(flow.go(MenuFlow.State.CONNECTING, "", first), "validating -> connecting")
	_expect(bool(flow.spec()["cancel"]) and bool(flow.spec()["spinner"]) and flow.busy(), "connecting: cancel + spinner, inputs locked")
	_expect(not flow.go(MenuFlow.State.CONNECTED, "", first), "connecting cannot skip to connected")
	_expect(flow.go(MenuFlow.State.FAILED, "x", first) and not flow.busy(), "failure is recoverable")
	var second := flow.begin_attempt()
	_expect(second == 2, "retry is a new attempt")
	_expect(not flow.go(MenuFlow.State.CONNECTING, "", first), "event of the old attempt is ignored")
	_expect(flow.ignored_events >= 2, "ignored events are counted")
	for state in MenuFlow.State.values():
		_expect(MenuFlow.SPEC.has(state) and MenuFlow.NEXT.has(state), "state %s fully specified" % MenuFlow.NAMES[state])
	_expect(MenuFlow.NEXT[MenuFlow.State.SHUTTING_DOWN].is_empty(), "shutting down is terminal")

func _test_name_rules() -> void:
	for good in ["Ana", "João Ninguém", "  Ana Clara  ", "x_y-z 2", "Çé"]:
		_expect(RoundRules.label_problem(good).is_empty(), "name '%s' valid" % good)
	var cases := {"": "empty", "   ": "empty", "x".repeat(RoundRules.MAX_LABEL_LENGTH + 1): "too_long", "a\nb": "characters", "a\tb": "characters", "a;b": "characters", "duas  vezes": "spaces"}
	for raw in cases:
		_expect(RoundRules.label_problem(raw) == cases[raw], "name '%s' -> %s" % [str(raw).c_escape(), cases[raw]])
	_expect(RoundRules.validate_label("João Ninguém").is_empty() and not RoundRules.validate_label("a\u0007b").is_empty(), "server applies the same rule")

func _test_endpoint_rules() -> void:
	var cases := [
		["ws://127.0.0.1:9080", false, true, ""], ["ws://192.168.0.10:9080", true, true, ""], ["wss://jogo.up.railway.app", true, true, ""],
		["wss://jogo.up.railway.app/ws", true, true, ""], ["ws://jogo.up.railway.app", true, false, "insecure"], ["ws://jogo.up.railway.app", false, true, ""],
		["http://jogo.up.railway.app", false, false, "scheme"], ["wss://user:senha@jogo.app", false, false, "forbidden_part"],
		["wss://jogo.app?token=abc", false, false, "forbidden_part"], ["wss://jogo.app:99999", false, false, "port"], ["", false, false, "not_configured"],
		["wss://", false, false, "host"],
	]
	for case in cases:
		var result := OnlineEndpoint.validate(case[0], case[1])
		_expect(bool(result["ok"]) == bool(case[2]) and str(result["reason"]) == str(case[3]), "endpoint %s production=%s -> %s (%s)" % [case[0], case[1], case[3], result["reason"]])
	_expect(OnlineEndpoint.configured({}).get("source") == "none" or not str(OnlineEndpoint.configured({})["url"]).is_empty(), "no source by default")
	_expect(OnlineEndpoint.configured({"online-url": "wss://a.b"})["source"] == "argument", "argument wins")

func _test_settings_persistence() -> void:
	var settings := MenuSettings.load_saved()
	_expect(settings.volume == MenuSettings.VOLUME_DEFAULT and settings.sensitivity == MenuSettings.SENSITIVITY_DEFAULT, "defaults without a file")
	_expect(not settings.display_saved and settings.resolution == Vector2i(960, 540), "without a file the window stays as the project opens it")
	settings.volume = 0.35
	settings.sensitivity = 2.5
	settings.player_name = "Ana Clara"
	settings.reduce_motion = true
	_expect(settings.save() == OK, "settings saved")
	var loaded := MenuSettings.load_saved()
	_expect(is_equal_approx(loaded.volume, 0.35) and is_equal_approx(loaded.sensitivity, 2.5) and loaded.player_name == "Ana Clara" and loaded.reduce_motion, "settings persisted")
	_expect(loaded.display_saved, "saved screen settings are applied when the game opens")
	_expect(MenuSettings.clamp_sensitivity(0.0) == MenuSettings.SENSITIVITY_MIN and MenuSettings.clamp_sensitivity(99.0) == MenuSettings.SENSITIVITY_MAX and MenuSettings.clamp_sensitivity(NAN) == MenuSettings.SENSITIVITY_DEFAULT, "sensitivity limits")
	loaded.apply_audio()
	_expect(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.35), "volume applied to the Master bus")
	var file := ConfigFile.new()
	file.load(_settings_path)
	for forbidden in ["address", "url", "port", "token"]:
		_expect(not file.has_section_key(MenuSettings.SECTION, forbidden), "settings never store %s" % forbidden)
	# Volta ao padrão para o resto do teste.
	DirAccess.remove_absolute(_settings_path)

# --- Telas -------------------------------------------------------------------------

func _test_main_screen() -> void:
	_expect(menu.panel_name == "main" and (menu.panels["main"] as Control).visible, "starts on the main screen")
	for id in ["online", "host", "join", "howto", "settings"]:
		_expect((menu.buttons[id] as Button).is_visible_in_tree(), "main shows %s" % id)
	_expect(menu.buttons.has("quit") == MenuSettings.supports_quit(), "quit only where it makes sense")
	_expect((menu.buttons["online"] as Button).text == "JOGAR ONLINE" and (menu.buttons["host"] as Button).text == "CRIAR PARTIDA LOCAL" and (menu.buttons["join"] as Button).text == "ENTRAR EM PARTIDA LAN", "button labels")
	# Sem URL online, a ação principal destacada é criar partida local.
	_expect((menu.buttons["host"] as Button).theme_type_variation == "PrimaryButton" and (menu.buttons["online"] as Button).theme_type_variation != "PrimaryButton", "primary action highlighted")
	for id in ["host_port", "join_address", "join_port"]:
		_expect(not (menu.fields[id] as LineEdit).is_visible_in_tree(), "technical field %s hidden on the main screen" % id)

func _test_navigation_and_escape() -> void:
	for pair in [["host", "host"], ["join", "join"], ["online", "online"], ["howto", "howto"], ["settings", "settings"]]:
		_expect(menu.press(pair[0]), "press %s" % pair[0])
		_expect(menu.panel_name == pair[1] and (menu.panels[pair[1]] as Control).visible and not (menu.panels["main"] as Control).visible, "panel %s opens alone" % pair[1])
		_key(KEY_ESCAPE)
		_expect(menu.panel_name == "main", "Esc returns from %s" % pair[1])
	for pair in [["host", "host_back"], ["join", "join_back"], ["online", "online_back"], ["howto", "howto_back"], ["settings", "settings_back"]]:
		menu.press(pair[0])
		_expect(menu.press(pair[1]) and menu.panel_name == "main", "%s returns to main" % pair[1])

func _test_focus_and_keys() -> void:
	menu._focus_first()
	_expect(_focus() == menu.fields["name"], "name field focused on the main screen")
	_key(KEY_TAB)
	_expect(_focus() == menu.buttons["online"], "Tab goes to the first button (%s)" % str(_focus()))
	_key(KEY_TAB)
	_expect(_focus() == menu.buttons["host"], "Tab order follows the screen")
	# Enter no campo de nome abre a ação principal (partida local).
	(menu.fields["name"] as LineEdit).grab_focus()
	_key(KEY_ENTER)
	_expect(menu.panel_name == "host", "Enter on the name opens the primary action")
	menu._focus_first()
	_expect(_focus() == menu.buttons["host_create"], "primary button focused on the host panel")
	var style := MenuTheme.theme().get_stylebox("focus", "Button") as StyleBoxFlat
	_expect(style != null and style.border_width_left >= 2 and style.border_color.a > 0.9, "keyboard focus is clearly visible")
	_key(KEY_ESCAPE)

func _test_host_validation() -> void:
	emitted.clear()
	menu.press("host")
	menu.set_field("host_name", "   ")
	menu.press("host_create")
	_expect(emitted.is_empty() and (menu.errors["host_name"] as Label).visible and (menu.errors["host_name"] as Label).text.begins_with("Digite seu nome"), "empty name refused with a clear message")
	menu.set_field("host_name", "x".repeat(40))
	_expect((menu.fields["host_name"] as LineEdit).text.length() == RoundRules.MAX_LABEL_LENGTH, "name field has a length limit")
	menu.set_field("host_name", "  Ana Clara  ")
	menu.set_field("host_port", "80")
	menu.press("host_create")
	_expect(emitted.is_empty() and (menu.errors["host_port"] as Label).visible, "port below range refused")
	menu.set_field("host_port", "abc")
	menu.press("host_create")
	_expect(emitted.is_empty(), "non-numeric port refused")
	menu.set_field("host_port", "9090")
	menu.lan_check.button_pressed = true
	menu.press("host_create")
	_expect(emitted.size() == 1 and emitted[0]["name"] == "Ana Clara" and emitted[0]["port"] == 9090 and emitted[0]["lan"] == true, "valid host request with trimmed name (%s)" % str(emitted))
	_expect(menu.flow.state == MenuFlow.State.VALIDATING, "menu waits for the network")
	# Criação duplicada: o botão já está desativado.
	_expect(not menu.press("host_create") and emitted.size() == 1, "duplicate create ignored")
	menu.enter(MenuFlow.State.STARTING_SERVER, "", int(emitted[0]["attempt"]))
	_expect((menu.buttons["cancel"] as Button).is_visible_in_tree() and menu.spinner.visible, "starting server: spinner and cancel")
	menu.press("cancel")
	_expect(emitted[-1]["kind"] == "cancel", "cancel while starting the server")
	menu.enter(MenuFlow.State.CANCELLING, "", int(emitted[0]["attempt"]))
	menu.enter(MenuFlow.State.IDLE, "", int(emitted[0]["attempt"]))
	_expect(not menu.flow.busy() and not menu.status_box.visible and menu.panel_name == "host", "back to the host panel after cancelling")
	menu.press("host_back")

func _test_join_validation_duplicate_cancel_and_stale() -> void:
	emitted.clear()
	menu.press("join")
	menu.set_field("join_name", "Bia")
	for bad in ["", "ws://192.168.0.10", "192.168.0.10:9080", "999.1.1.1"]:
		menu.set_field("join_address", bad)
		menu.press("join_enter")
		_expect(emitted.is_empty() and (menu.errors["join_address"] as Label).visible, "address '%s' refused" % bad)
	menu.set_field("join_address", "127.0.0.1")
	menu.set_field("join_port", "70000")
	menu.press("join_enter")
	_expect(emitted.is_empty(), "port out of range refused")
	menu.set_field("join_port", str(DesktopSession.DEFAULT_PORT))
	# Clique duplo: o segundo acionamento no mesmo quadro não passa.
	menu.press("join_enter")
	menu.press("join_enter")
	_expect(emitted.size() == 1 and emitted[0]["address"] == "127.0.0.1", "double click sends one request")
	var attempt := int(emitted[0]["attempt"])
	_expect(menu.enter(MenuFlow.State.CONNECTING, "Conectando…", attempt), "connecting")
	_expect(menu.status_box.visible and not (menu.panels["join"] as Control).is_visible_in_tree() and (menu.buttons["cancel"] as Button).is_visible_in_tree(), "connecting shows status with cancel")
	_expect(not menu.enter(MenuFlow.State.CONNECTED, "", attempt - 1), "stale callback ignored")
	_expect(menu.enter(MenuFlow.State.AWAITING_RESPONSE, "", attempt), "awaiting response")
	_key(KEY_ESCAPE)
	_expect(emitted[-1]["kind"] == "cancel" and int(emitted[-1]["attempt"]) == attempt, "Esc cancels while connecting")

func _test_failure_and_retry() -> void:
	var attempt := menu.flow.attempt
	menu.fail("Não foi possível conectar.", attempt)
	_expect(menu.flow.state == MenuFlow.State.FAILED and (menu.buttons["retry"] as Button).is_visible_in_tree() and (menu.buttons["status_back"] as Button).is_visible_in_tree(), "recoverable failure offers retry and back")
	_expect(menu.status_label.get_theme_color("font_color") == MenuTheme.ERROR, "failure uses the error color")
	emitted.clear()
	menu.press("retry")
	_expect(emitted.size() == 1 and emitted[0]["kind"] == "join" and emitted[0]["address"] == "127.0.0.1" and int(emitted[0]["attempt"]) == attempt + 1, "retry sends the same request as a new attempt")
	menu.fail("Tempo esgotado.", int(emitted[0]["attempt"]))
	menu.press("status_back")
	_expect(menu.flow.state == MenuFlow.State.IDLE and menu.panel_name == "join" and not menu.status_box.visible, "back from failure keeps the panel")
	menu.press("join_back")

func _test_return_messages() -> void:
	var request := {"kind": "join", "panel": "join", "name": "Bia", "address": "192.168.0.7", "port": 9081}
	menu.restore_after_return(request, "info", "O servidor encerrou a partida.")
	_expect(menu.panel_name == "join" and (menu.fields["join_address"] as LineEdit).text == "192.168.0.7", "return restores the panel and fields")
	_expect(menu.status_label.get_theme_color("font_color") != MenuTheme.ERROR, "normal shutdown is not shown as an error")
	menu.press("status_back")
	menu.restore_after_return(request, "cancelled", "")
	_expect(not menu.status_box.visible and menu.flow.state == MenuFlow.State.IDLE, "cancel returns without any message")
	menu.restore_after_return(request, "failure", "A sala está cheia (8 jogadores).")
	_expect(menu.flow.state == MenuFlow.State.FAILED and menu.status_label.text.begins_with("A sala está cheia"), "full room shown as a recoverable failure")
	menu.press("status_back")
	menu.press("join_back")

func _test_online_not_configured() -> void:
	emitted.clear()
	menu.press("online")
	var info := (menu.panels["online"] as Control).find_child("OnlineInfo", true, false) as Label
	_expect(info != null and info.text.begins_with("Servidor online ainda não configurado"), "online not configured message")
	_expect(not menu.buttons.has("online_connect") and emitted.is_empty(), "no connection attempt without a URL")
	_expect(menu.press("online_back") and menu.panel_name == "main", "back immediately")

func _test_controls_match_input_map() -> void:
	var labels := menu.key_labels()
	for entry in GameControls.ACTIONS:
		var action := str(entry["action"])
		var expected: Array = []
		for event in InputMap.action_get_events(action):
			expected.append(GameControls.event_text(event))
		_expect(labels.get(action, "") == " / ".join(PackedStringArray(expected)) and not str(labels.get(action, "")).is_empty(), "how-to shows %s = %s (%s)" % [action, str(expected), labels.get(action, "")])
	_expect(labels["reload"] == "R" and labels["fire"] == "Botão esquerdo do mouse" and labels["release_mouse"] == "Esc" and labels["leave_match"] == "F10", "known keys shown")
	# Trocar a tecla no InputMap muda o texto sem mexer na tela.
	InputMap.action_erase_events("reload")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_T
	InputMap.action_add_event("reload", key)
	_expect(GameControls.action_text("reload") == "T", "text follows the InputMap")
	InputMap.action_erase_events("reload")
	GameControls.ensure()
	_expect(GameControls.action_text("reload") == "R" and InputMap.action_get_events("move_forward").size() == 1, "ensure restores defaults without duplicating")

func _test_settings_panel() -> void:
	menu.press("settings")
	(menu.buttons["settings_volume"] as HSlider).value = 0.5
	(menu.buttons["settings_sensitivity"] as HSlider).value = 1.75
	var saved := MenuSettings.load_saved()
	_expect(is_equal_approx(saved.volume, 0.5) and is_equal_approx(saved.sensitivity, 1.75), "slider changes saved immediately")
	_expect(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5), "volume applied immediately")
	(menu.buttons["settings_sensitivity"] as HSlider).value = 0.0
	_expect(is_equal_approx(MenuSettings.load_saved().sensitivity, MenuSettings.SENSITIVITY_MIN), "sensitivity never reaches zero")
	(menu.buttons["settings_motion"] as CheckBox).button_pressed = true
	_expect(menu.backdrop.reduce_motion and MenuSettings.load_saved().reduce_motion, "reduce motion applied and saved")
	menu.press("settings_back")

func _test_menu_builds_no_world() -> void:
	_expect(root.find_children("*", "ArenaView", true, false).is_empty(), "menu never builds the mansion")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse free in the menu")

func _test_online_configured_by_argument_and_setting() -> void:
	var by_argument := _new_menu({"online-url": "wss://armed-mystery.up.railway.app"})
	await_ready(by_argument)
	emitted.clear()
	_expect(by_argument.buttons.has("online_connect") and (by_argument.buttons["online"] as Button).theme_type_variation == "PrimaryButton", "configured online becomes the primary action")
	by_argument.set_field("name", "Caio")
	by_argument.press("online")
	by_argument.press("online_connect")
	_expect(emitted.size() == 1 and emitted[0]["url"] == "wss://armed-mystery.up.railway.app" and emitted[0]["name"] == "Caio", "online request uses the configured URL")
	by_argument.queue_free()
	# Mesma tela, endereço vindo do ProjectSettings (override.cfg na build).
	ProjectSettings.set_setting(OnlineEndpoint.SETTING, "wss://outro-servico.up.railway.app")
	var by_setting := _new_menu({})
	await_ready(by_setting)
	_expect(str(by_setting.online["url"]) == "wss://outro-servico.up.railway.app" and by_setting.online["source"] == "project_settings", "endpoint read from the central setting")
	ProjectSettings.set_setting(OnlineEndpoint.SETTING, "")
	by_setting.queue_free()

func await_ready(_node: Node) -> void:
	pass
