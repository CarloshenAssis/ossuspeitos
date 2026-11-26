class_name TouchControls
extends CanvasLayer

const LOOK_SENSITIVITY := 0.0025
const STICK_RADIUS := 64.0
const BUTTON_SIZE := Vector2(92, 56)
const MOVE_ACTIONS := [&"move_left", &"move_right", &"move_forward", &"move_backward"]

var force_visible := false
var _surface: Control
var _stick: PanelContainer
var _knob: PanelContainer
var _fire: PanelContainer
var _jump: PanelContainer
var _stick_finger := -1
var _look_finger := -1
var _button_fingers := {}
var _look_delta := Vector2.ZERO
var _previous_mouse_emulation := false
var _active := false

static func touch_device() -> bool:
	return DisplayServer.get_name() != "headless" and (
		DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
		or OS.has_feature("web_android") or OS.has_feature("web_ios"))

func _ready() -> void:
	layer = 2
	_surface = Control.new()
	add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick = _panel("", HudStyle.MUTED)
	_knob = _panel("", HudStyle.BONE)
	_fire = _panel("Atirar", HudStyle.AMBER)
	_jump = _panel("Pular", HudStyle.BONE)
	_surface.resized.connect(_layout)
	visibility_changed.connect(_sync_input)
	_layout()
	visible = force_visible or touch_device()
	_sync_input()

func _panel(caption: String, accent: Color) -> PanelContainer:
	var panel := HudStyle.panel(HudStyle.PANEL, accent, 2)
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.set_corner_radius_all(24)
	_surface.add_child(panel)
	if not caption.is_empty():
		var label := HudStyle.label(caption, 20, accent)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(label)
	return panel

func _layout() -> void:
	var margin := HudStyle.MARGIN * 1.5
	_stick.size = Vector2.ONE * STICK_RADIUS * 2.0
	_stick.position = Vector2(margin, _surface.size.y - _stick.size.y - margin)
	_knob.size = Vector2(48, 48)
	_knob.position = _stick.get_rect().get_center() - _knob.size * 0.5
	_fire.size = BUTTON_SIZE
	_jump.size = BUTTON_SIZE
	_jump.position = _surface.size - BUTTON_SIZE - Vector2.ONE * margin
	_fire.position = _jump.position - Vector2(0, BUTTON_SIZE.y + HudStyle.MARGIN)

func consume_look_delta() -> Vector2:
	var result := _look_delta
	_look_delta = Vector2.ZERO
	return result

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if _touch(event):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _stick_finger:
			_move_stick(event.position)
		elif event.index == _look_finger:
			_look_delta -= event.relative * LOOK_SENSITIVITY
		elif not _button_fingers.has(event.index):
			return
		get_viewport().set_input_as_handled()

func _touch(event: InputEventScreenTouch) -> bool:
	if not event.pressed or event.canceled:
		if event.index == _stick_finger:
			_stick_finger = -1
			_move_stick(_stick.get_rect().get_center())
		elif event.index == _look_finger:
			_look_finger = -1
		elif _button_fingers.has(event.index):
			_inject_action(_button_fingers[event.index], false)
			_button_fingers.erase(event.index)
		else:
			return false
		return true
	if _fire.get_rect().has_point(event.position):
		_press_button(event.index, &"fire")
	elif _jump.get_rect().has_point(event.position):
		_press_button(event.index, &"jump")
	elif _stick_finger == -1 and _stick.get_rect().has_point(event.position):
		_stick_finger = event.index
		_move_stick(event.position)
	elif _look_finger == -1 and event.position.x >= _surface.size.x * 0.5:
		_look_finger = event.index
	else:
		return false
	return true

func _move_stick(position: Vector2) -> void:
	var center := _stick.get_rect().get_center()
	var move := ((position - center) / STICK_RADIUS).limit_length()
	_knob.position = center + move * STICK_RADIUS - _knob.size * 0.5
	var strengths := [-move.x, move.x, -move.y, move.y]
	for index in MOVE_ACTIONS.size():
		if strengths[index] > 0.0:
			Input.action_press(MOVE_ACTIONS[index], strengths[index])
		else:
			Input.action_release(MOVE_ACTIONS[index])

func _press_button(index: int, action: StringName) -> void:
	if action not in _button_fingers.values():
		_button_fingers[index] = action
		_inject_action(action, true)

func _inject_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _sync_input() -> void:
	var active := visible and can_process()
	set_process_input(active)
	if active == _active:
		return
	_active = active
	if _active:
		GameControls.ensure()
		if not InputMap.has_action("jump"):
			InputMap.add_action("jump")
		_previous_mouse_emulation = Input.emulate_mouse_from_touch
		Input.emulate_mouse_from_touch = false
	else:
		_reset_touches()
		Input.emulate_mouse_from_touch = _previous_mouse_emulation

func _reset_touches() -> void:
	if _stick_finger != -1:
		_move_stick(_stick.get_rect().get_center())
	_stick_finger = -1
	_look_finger = -1
	_look_delta = Vector2.ZERO
	for action in _button_fingers.values():
		_inject_action(action, false)
	_button_fingers.clear()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _active:
		_reset_touches()
	elif what in [NOTIFICATION_DISABLED, NOTIFICATION_ENABLED] and is_node_ready():
		_sync_input()

func _exit_tree() -> void:
	if _active:
		_reset_touches()
		Input.emulate_mouse_from_touch = _previous_mouse_emulation
		_active = false
