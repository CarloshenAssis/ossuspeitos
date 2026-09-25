extends SceneTree

## Fase 7: capturas do menu real numa resolução e verificação de corte.
## Para cada tela (principal, criar partida, entrar por LAN, online sem URL,
## conectando, erro recuperável, como jogar, configurações e, desde a fase 9,
## lobby online, sala e sala com resultado) grava um PNG e
## confere que todo controle visível cabe na janela (exceto conteúdo dentro de
## rolagem, que é conferido pela própria área de rolagem) e que nenhum texto
## de uma linha (rótulo, botão, campo) é mais largo que o próprio controle.
## Precisa de janela real (xvfb); não roda em --headless.
##
## Uso: xvfb-run -s "-screen 0 1920x1080x24" godot --rendering-driver opengl3 \
##   --resolution 1280x720 --path . --script tests/menu_capture.gd -- SAIDA_DIR

const SCREENS := ["main", "host", "join", "online", "connecting", "error", "howto", "settings", "hall", "room", "room_result"]

var out_dir := ""
var menu: DesktopMenu
var failures := 0
var checks := 0
var _index := -1
var _wait := 0
var _label := ""
var _images: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		printerr("MENU_CAPTURE_ERROR precisa de janela (xvfb) e de SAIDA_DIR")
		quit(2)
		return
	out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	MenuSettings.path_override = out_dir.path_join("capture-settings.cfg")
	if FileAccess.file_exists(MenuSettings.path_override):
		DirAccess.remove_absolute(MenuSettings.path_override)
	var size := DisplayServer.window_get_size()
	_label = "%dx%d" % [size.x, size.y]
	menu = DesktopMenu.new()
	root.add_child(menu)

func _process(_delta: float) -> bool:
	if menu == null:
		return false
	if _wait > 0:
		_wait -= 1
		return false
	if _index >= 0:
		_capture(SCREENS[_index])
	_index += 1
	if _index >= SCREENS.size():
		_finish()
		return true
	_prepare(SCREENS[_index])
	_wait = 8
	return false

func _prepare(screen: String) -> void:
	# Cada tela parte do painel principal, sem tentativa em curso.
	if menu.status_box.visible:
		if menu.flow.busy():
			menu.fail("", menu.flow.attempt)
		menu.press("status_back")
	if screen in ["hall", "room", "room_result"]:
		_prepare_online(screen)
		return
	if menu.panel_name != "main":
		menu._show_panel("main", false)
	match screen:
		"main":
			menu.fields["name"].text = "Ana Luísa"
			menu.buttons["online"].grab_focus()
		"host", "join", "online", "howto", "settings":
			menu.press(screen)
		"connecting":
			menu.press("join")
			menu.fields["join_address"].text = "192.168.0.10"
			menu.press("join_enter")
			menu.enter(MenuFlow.State.CONNECTING, "Conectando a 192.168.0.10:9080…", menu.flow.attempt)
		"error":
			menu.press("join")
			menu.press("join_enter")
			menu.enter(MenuFlow.State.CONNECTING, "", menu.flow.attempt)
			menu.fail("Não foi possível conectar a 192.168.0.10:9080. Confira o endereço, a porta e se o anfitrião está com a partida aberta.", menu.flow.attempt)

## Telas das salas online (fase 9) com dados de exemplo, pelo mesmo caminho
## que a rede usa: conectado -> lobby online -> estado da sala.
func _prepare_online(screen: String) -> void:
	menu.flow.state = MenuFlow.State.IDLE
	menu.room_view = {}
	var attempt := menu.flow.begin_attempt()
	menu.enter(MenuFlow.State.CONNECTING, "", attempt)
	menu.enter(MenuFlow.State.AWAITING_RESPONSE, "", attempt)
	menu.fields["name"].text = "Ana Luísa"
	menu.show_hall()
	if screen == "hall":
		menu.fields["room_code"].text = "k7m-2qx"
		menu.buttons["room_create"].grab_focus()
		return
	var players := [
		{"peer_id": 11, "label": "Ana Luísa", "appearance": "ember", "ready": screen == "room", "host": true},
		{"peer_id": 12, "label": "Beto", "appearance": "moss", "ready": screen == "room", "host": false},
		{"peer_id": 13, "label": "Caio", "appearance": "night", "ready": false, "host": false},
		{"peer_id": 14, "label": "Eduarda Maria", "appearance": "plum", "ready": screen == "room", "host": false},
		{"peer_id": 15, "label": "Duda", "appearance": "sand", "ready": false, "host": false},
	]
	var result := {}
	if screen == "room_result":
		result = {"round_id": 1, "winner": "INNOCENTS", "reason": "assassin_down", "players": [
			{"label": "Ana Luísa", "role": "VICTIM"}, {"label": "Beto", "role": "ASSASSIN"},
			{"label": "Caio", "role": "DETECTIVE"}, {"label": "Eduarda Maria", "role": "VICTIM"},
			{"label": "Duda", "role": "VICTIM"}]}
	var dto := RoomRules.sanitize_room_state({"code": "K7M2QX", "phase": "lobby", "round_id": 1 if screen == "room_result" else 0,
		"countdown_msec": 0, "min_players": 4, "max_players": 8, "players": players,
		"ready_count": 3 if screen == "room" else 0, "result": result})
	menu.show_room(dto, 11)
	menu.buttons["room_ready"].grab_focus()

func _capture(screen: String) -> void:
	var image := root.get_viewport().get_texture().get_image()
	var path := out_dir.path_join("menu_%s_%s.png" % [_label, screen])
	image.save_png(path)
	_images.append(image)
	var viewport := root.get_viewport().get_visible_rect()
	var problems := 0
	for node in menu.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control is MenuBackdrop or control.get_parent() is MenuBackdrop:
			continue
		if not _inside_scroll(control):
			var rect := control.get_global_rect()
			if not viewport.grow(1.0).encloses(rect):
				problems += _problem(screen, "outside", control, "rect=%s viewport=%s" % [rect, viewport.size])
		var text_width := _text_overflow(control)
		if text_width > 0.0:
			problems += _problem(screen, "clipped_text", control, "needs=%.0f has=%.0f" % [text_width, control.size.x])
	var focus := root.get_viewport().gui_get_focus_owner()
	checks += 1
	if screen not in ["main"] and focus == null:
		problems += _problem(screen, "no_focus", menu.card, "")
	print("MENU_CAPTURE screen=%s resolution=%s viewport=%.0fx%.0f focus=%s problems=%d file=%s" % [screen, _label, viewport.size.x, viewport.size.y, focus.name if focus != null else "none", problems, path])

func _inside_scroll(control: Control) -> bool:
	var parent := control.get_parent()
	while parent != null and parent != menu:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false

## Largura que o texto de uma linha precisaria, se não couber; 0 se couber.
func _text_overflow(control: Control) -> float:
	checks += 1
	var text := ""
	var margin := 0.0
	if control is Label:
		var label := control as Label
		if label.autowrap_mode != TextServer.AUTOWRAP_OFF or label.text.contains("\n"):
			return 0.0
		text = label.text
	elif control is Button and not (control is OptionButton or control is CheckBox):
		text = (control as Button).text
		var style := control.get_theme_stylebox("normal")
		margin = style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT) if style != null else 0.0
	elif control is LineEdit:
		text = (control as LineEdit).text
		var style := control.get_theme_stylebox("normal")
		margin = style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT) if style != null else 0.0
	else:
		return 0.0
	if text.is_empty():
		return 0.0
	var font := control.get_theme_font("font")
	var font_size := control.get_theme_font_size("font_size")
	var needed := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + margin
	return needed if needed > control.size.x + 1.0 else 0.0

func _problem(screen: String, kind: String, control: Control, detail: String) -> int:
	failures += 1
	printerr("MENU_CAPTURE_PROBLEM screen=%s resolution=%s kind=%s node=%s text=%s %s" % [screen, _label, kind, control.get_path(), str(control.get("text")).left(40), detail])
	return 1

## Prancha com 4 colunas e todas as telas, para revisão rápida.
func _save_sheet() -> void:
	if _images.size() != SCREENS.size():
		return
	var first: Image = _images[0]
	var tile_w := 640
	var tile_h := int(float(first.get_height()) * tile_w / first.get_width())
	var rows := int(ceil(_images.size() / 4.0))
	var sheet := Image.create(tile_w * 4, tile_h * rows, false, Image.FORMAT_RGB8)
	for i in _images.size():
		var tile: Image = (_images[i] as Image).duplicate()
		tile.convert(Image.FORMAT_RGB8)
		tile.resize(tile_w, tile_h, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(tile, Rect2i(0, 0, tile_w, tile_h), Vector2i((i % 4) * tile_w, (i / 4) * tile_h))
	sheet.save_png(out_dir.path_join("menu_%s_sheet.png" % _label))

func _finish() -> void:
	_save_sheet()
	if FileAccess.file_exists(MenuSettings.path_override):
		DirAccess.remove_absolute(MenuSettings.path_override)
	if failures > 0:
		printerr("MENU_CAPTURE_FAILED resolution=%s problems=%d checks=%d" % [_label, failures, checks])
		quit(1)
		return
	print("MENU_CAPTURE_OK resolution=%s screens=%d checks=%d" % [_label, SCREENS.size(), checks])
	quit(0)
