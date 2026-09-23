class_name DesktopMenu
extends CanvasLayer

## Menu inicial do teste local no PC: criar partida, entrar em partida ou sair.
## Só coleta e valida o que o jogador digitou; quem cria processos e conecta é
## `NetworkApp` com `DesktopSession`.

signal host_requested(player_name: String, port: int, lan: bool)
signal join_requested(player_name: String, address: String, port: int)
signal quit_requested
signal input_rejected(field: String)

var name_edit: LineEdit
var host_port_edit: LineEdit
var lan_check: CheckBox
var join_address_edit: LineEdit
var join_port_edit: LineEdit
var host_button: Button
var join_button: Button
var quit_button: Button
var status_label: Label

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var background := ColorRect.new()
	background.color = Color(0.11, 0.12, 0.16)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_constant_override("separation", 6)
	center.add_child(panel)

	panel.add_child(_label("ARMED MYSTERY — TESTE LOCAL", 22))
	panel.add_child(_label("Abra o jogo 4 vezes neste PC (ou em PCs da mesma rede): um cria a partida, os outros entram.", 13, true))

	var name_row := HBoxContainer.new()
	name_row.add_child(_label("Seu nome", 14))
	name_edit = _line(DesktopSession.default_player_name(), "letras, números, - ou _")
	name_row.add_child(name_edit)
	panel.add_child(name_row)

	panel.add_child(HSeparator.new())
	panel.add_child(_label("1. Criar partida local", 16))
	var host_row := HBoxContainer.new()
	host_row.add_child(_label("Porta", 14))
	host_port_edit = _line(str(DesktopSession.DEFAULT_PORT), "porta")
	host_port_edit.custom_minimum_size.x = 100
	host_row.add_child(host_port_edit)
	lan_check = CheckBox.new()
	lan_check.text = "Permitir jogadores da rede local (LAN)"
	lan_check.button_pressed = false
	host_row.add_child(lan_check)
	panel.add_child(host_row)
	host_button = Button.new()
	host_button.text = "Criar partida local"
	host_button.pressed.connect(_on_host_pressed)
	panel.add_child(host_button)

	panel.add_child(HSeparator.new())
	panel.add_child(_label("2. Entrar em partida", 16))
	var join_row := HBoxContainer.new()
	join_row.add_child(_label("Endereço", 14))
	join_address_edit = _line(DesktopSession.LOOPBACK_ADDRESS, "ex.: 192.168.0.10")
	join_address_edit.custom_minimum_size.x = 200
	join_row.add_child(join_address_edit)
	join_row.add_child(_label("Porta", 14))
	join_port_edit = _line(str(DesktopSession.DEFAULT_PORT), "porta")
	join_port_edit.custom_minimum_size.x = 100
	join_row.add_child(join_port_edit)
	panel.add_child(join_row)
	join_button = Button.new()
	join_button.text = "Entrar em partida"
	join_button.pressed.connect(_on_join_pressed)
	panel.add_child(join_button)

	panel.add_child(HSeparator.new())
	quit_button = Button.new()
	quit_button.text = "3. Sair"
	quit_button.pressed.connect(func(): quit_requested.emit())
	panel.add_child(quit_button)

	status_label = _label("", 14, true)
	status_label.custom_minimum_size = Vector2(520, 40)
	panel.add_child(status_label)
	print("MENU_READY name=%s" % name_edit.text)

func set_status(text: String, is_error: bool = false) -> void:
	if status_label == null:
		return
	status_label.text = text
	status_label.modulate = Color(1.0, 0.55, 0.5) if is_error else Color(0.8, 0.95, 1.0)

func set_busy(busy: bool) -> void:
	for button in [host_button, join_button]:
		if button != null:
			button.disabled = busy

## Usado pelos testes automatizados e pela linha de comando para preencher os
## campos exatamente como um jogador faria.
func fill(player_name: String, host_port: String, lan: bool, address: String, join_port: String) -> void:
	if not player_name.is_empty(): name_edit.text = player_name
	if not host_port.is_empty(): host_port_edit.text = host_port
	lan_check.button_pressed = lan
	if not address.is_empty(): join_address_edit.text = address
	if not join_port.is_empty(): join_port_edit.text = join_port

func _on_host_pressed() -> void:
	var player_name := name_edit.text.strip_edges()
	var name_error := DesktopSession.validate_name(player_name)
	if not name_error.is_empty():
		_reject("name", name_error)
		return
	var port := DesktopSession.parse_port(host_port_edit.text)
	if port < 0:
		_reject("port", "Porta inválida: use um número de %d a %d." % [DesktopSession.MIN_PORT, DesktopSession.MAX_PORT])
		return
	host_requested.emit(player_name, port, lan_check.button_pressed)

func _on_join_pressed() -> void:
	var player_name := name_edit.text.strip_edges()
	var name_error := DesktopSession.validate_name(player_name)
	if not name_error.is_empty():
		_reject("name", name_error)
		return
	var address := join_address_edit.text.strip_edges()
	var address_error := DesktopSession.validate_address(address)
	if not address_error.is_empty():
		_reject("address", address_error)
		return
	var port := DesktopSession.parse_port(join_port_edit.text)
	if port < 0:
		_reject("port", "Porta inválida: use um número de %d a %d." % [DesktopSession.MIN_PORT, DesktopSession.MAX_PORT])
		return
	join_requested.emit(player_name, address, port)

func _reject(field: String, message: String) -> void:
	print("MENU_INPUT_INVALID field=%s" % field)
	set_status(message, true)
	input_rejected.emit(field)

func _label(text: String, size: int, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 520
	return label

func _line(text: String, placeholder: String) -> LineEdit:
	var line := LineEdit.new()
	line.text = text
	line.placeholder_text = placeholder
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line
