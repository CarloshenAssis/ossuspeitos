extends SceneTree

class ActionRecorder extends Node:
	var events: Array[String] = []

	func _unhandled_input(event: InputEvent) -> void:
		for action in [&"fire", &"jump"]:
			if event.is_action_pressed(action):
				events.append("%s pressed" % action)
			elif event.is_action_released(action):
				events.append("%s released" % action)

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var hidden := TouchControls.new()
	root.add_child(hidden)
	expect(not TouchControls.touch_device() and not hidden.visible, "headless hides touch controls")
	hidden.free()

	var recorder := ActionRecorder.new()
	root.add_child(recorder)
	var controls := TouchControls.new()
	controls.force_visible = true
	root.add_child(controls)
	await process_frame
	expect(controls.visible, "force enables touch controls")

	var stick := controls._stick.get_rect().get_center()
	var aim := Vector2(controls._surface.size.x * 0.75, controls._surface.size.y * 0.25)
	var fire := controls._fire.get_rect().get_center()
	var jump := controls._jump.get_rect().get_center()
	touch(0, stick, true)
	drag(0, stick + Vector2(48, -48), Vector2(48, -48))
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	expect(move.x > 0.6 and move.y < -0.6, "joystick drives the normal move vector")
	touch(1, aim, true)
	drag(1, aim + Vector2(40, -20), Vector2(40, -20))
	expect(controls.consume_look_delta().is_equal_approx(Vector2(-0.1, 0.05)), "look matches mouse signs and sensitivity")
	expect(controls.consume_look_delta() == Vector2.ZERO, "look is consumed once")

	touch(2, fire, true)
	touch(3, jump, true)
	expect(Input.is_action_pressed("fire") and Input.is_action_pressed("jump"), "buttons press actions")
	touch(2, fire, false)
	touch(3, jump, false)
	expect(recorder.events == ["fire pressed", "jump pressed", "fire released", "jump released"],
		"button edges reach unhandled input")
	expect(not Input.is_action_pressed("fire") and not Input.is_action_pressed("jump"), "button release clears actions")
	touch(0, stick, false)
	expect(Input.get_vector("move_left", "move_right", "move_forward", "move_backward") == Vector2.ZERO,
		"joystick releases movement")
	touch(0, stick + Vector2(48, 0), true)
	touch(2, fire, true)
	controls.hide()
	Input.flush_buffered_events()
	expect(not Input.is_action_pressed("move_right") and not Input.is_action_pressed("fire"),
		"hiding controls releases held actions")
	controls.free()
	recorder.free()

	for script in ["touch_controls", "arena_view", "visual_demo", "visual_demo_entry", "menu_settings"]:
		var source := FileAccess.get_file_as_string("res://client/%s.gd" % script)
		expect(not source.is_empty() and not source.contains("MenuTheme")
			and not source.contains("menu_theme.gd") and not source.contains("server/"),
			"%s is independent of menu and server scripts" % script)
	if failures == 0:
		print("TOUCH_CONTROLS_TEST_OK")
	quit(1 if failures else 0)

func touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	root.push_input(event, true)
	Input.flush_buffered_events()

func drag(index: int, position: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	root.push_input(event, true)
	Input.flush_buffered_events()

func expect(ok: bool, why: String) -> void:
	if not ok:
		failures += 1
		push_error(why)
