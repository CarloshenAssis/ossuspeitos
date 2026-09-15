class_name VisualDemo
extends Node

const LOCAL_DEMO_PEER_ID := -1
const SIMULATED_PLAYER_COUNT := 4

var test_mode := false
var arena_view: ArenaView
var local_position := MovementRules.SPAWN_POINTS[0]
var local_yaw := 0.0
var elapsed := 0.0
var test_frames := 0

func _ready() -> void:
	arena_view = ArenaView.new()
	arena_view.local_peer_id = LOCAL_DEMO_PEER_ID
	add_child(arena_view)
	_add_demo_banner()
	print("DEMO_READY simulated_players=%d network=disabled" % SIMULATED_PLAYER_COUNT)

func _process(delta: float) -> void:
	elapsed += delta
	if not test_mode:
		var move := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, local_yaw)
		local_position += direction * MovementRules.MAX_SPEED * delta
		local_position.x = clampf(local_position.x, -MovementRules.ARENA_HALF_EXTENT, MovementRules.ARENA_HALF_EXTENT)
		local_position.z = clampf(local_position.z, -MovementRules.ARENA_HALF_EXTENT, MovementRules.ARENA_HALF_EXTENT)
	arena_view.apply_snapshot(_demo_snapshot())
	if test_mode:
		test_frames += 1
		if test_frames == 3:
			_validate_demo()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		local_yaw = wrapf(local_yaw - event.relative.x * 0.0025, -PI, PI)

func _demo_snapshot() -> Array:
	var states: Array = [{
		"peer_id": LOCAL_DEMO_PEER_ID,
		"position": local_position,
		"velocity": Vector3.ZERO,
		"yaw": local_yaw,
		"spawn_index": 0,
	}]
	for index in SIMULATED_PLAYER_COUNT:
		var center := MovementRules.SPAWN_POINTS[index + 1]
		var phase := elapsed * (0.45 + index * 0.08) + float(index) * 1.4
		var position := center + Vector3(cos(phase), 0.0, sin(phase)) * 1.5
		position.x = clampf(position.x, -MovementRules.ARENA_HALF_EXTENT, MovementRules.ARENA_HALF_EXTENT)
		position.z = clampf(position.z, -MovementRules.ARENA_HALF_EXTENT, MovementRules.ARENA_HALF_EXTENT)
		states.append({
			"peer_id": index + 2,
			"position": position,
			"velocity": Vector3.ZERO,
			"yaw": -phase,
			"spawn_index": index + 1,
		})
	return states

func _validate_demo() -> void:
	var states := _demo_snapshot()
	var positions: Dictionary = {}
	if states.size() != SIMULATED_PLAYER_COUNT + 1:
		_fail_demo_test("unexpected simulated player count")
		return
	for index in range(1, states.size()):
		var position: Vector3 = states[index]["position"]
		if absf(position.x) > MovementRules.ARENA_HALF_EXTENT or absf(position.z) > MovementRules.ARENA_HALF_EXTENT:
			_fail_demo_test("simulated player escaped arena")
			return
		positions["%.3f,%.3f" % [position.x, position.z]] = true
	if positions.size() != SIMULATED_PLAYER_COUNT:
		_fail_demo_test("simulated positions are not distinct")
		return
	print("DEMO_TEST_OK simulated_players=%d network=disabled" % SIMULATED_PLAYER_COUNT)
	get_tree().quit(0)

func _fail_demo_test(message: String) -> void:
	push_error("DEMO_TEST_FAILED %s" % message)
	get_tree().quit(1)

func _add_demo_banner() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color(0.03, 0.04, 0.08, 0.9)
	background.position = Vector2(16.0, 16.0)
	background.size = Vector2(560.0, 72.0)
	layer.add_child(background)
	var label := Label.new()
	label.position = Vector2(28.0, 24.0)
	label.text = "MODO DEMONSTRAÇÃO — OFFLINE / SEM SERVIDOR\nWASD: mover · clique: capturar mouse · Esc: liberar"
	label.add_theme_font_size_override("font_size", 18)
	layer.add_child(label)
