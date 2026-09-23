class_name VisualDemo
extends Node

const LOCAL_DEMO_PEER_ID := -1
const SIMULATED_PLAYER_COUNT := 4

var test_mode := false
var arena_view: ArenaView
var local_position := MovementRules.SPAWN_POINTS[0]
var local_yaw := MovementRules.spawn_yaw(MovementRules.SPAWN_POINTS[0])
var elapsed := 0.0
var test_frames := 0

## Patrulhas dos bonecos simulados: trechos livres saindo das salas de spawn.
## Apresentação apenas; nenhuma rede, rodada ou combate é simulado.
const PATROLS := [
	[Vector3(12.3, MovementRules.PLAYER_HEIGHT, 12.3), Vector3(9.2, MovementRules.PLAYER_HEIGHT, 9.2), Vector3(6.8, MovementRules.PLAYER_HEIGHT, 8.8)],
	[Vector3(12.3, MovementRules.PLAYER_HEIGHT, -12.3), Vector3(9.2, MovementRules.PLAYER_HEIGHT, -9.2), Vector3(8.8, MovementRules.PLAYER_HEIGHT, -6.8)],
	[Vector3(-12.3, MovementRules.PLAYER_HEIGHT, 12.3), Vector3(-9.2, MovementRules.PLAYER_HEIGHT, 9.2), Vector3(-8.8, MovementRules.PLAYER_HEIGHT, 6.8)],
	[Vector3(0.0, MovementRules.PLAYER_HEIGHT, -13.0), Vector3(-4.0, MovementRules.PLAYER_HEIGHT, -12.5), Vector3(-6.5, MovementRules.PLAYER_HEIGHT, -12.5)],
]
const PATROL_SPEED := 1.6

func _ready() -> void:
	arena_view = ArenaView.new()
	arena_view.local_peer_id = LOCAL_DEMO_PEER_ID
	# O banner OFFLINE ocupa o topo à esquerda; o chip de região fica logo abaixo.
	arena_view.region_chip_top = 100.0
	add_child(arena_view)
	_add_demo_banner()
	print("DEMO_READY simulated_players=%d network=disabled" % SIMULATED_PLAYER_COUNT)

func _process(delta: float) -> void:
	elapsed += delta
	if not test_mode:
		var move := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		var direction := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, local_yaw)
		# Mesma colisão da arena oficial, para a demo não atravessar paredes.
		local_position = MovementRules.resolve_step(local_position, direction * MovementRules.MAX_SPEED * delta)["position"]
	arena_view.apply_snapshot(_demo_snapshot())
	if test_mode:
		test_frames += 1
		if test_frames == 3:
			_validate_demo()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		local_yaw = wrapf(local_yaw - event.relative.x * 0.0025, -PI, PI)

func _demo_snapshot() -> Array:
	return _demo_snapshot_at(elapsed)

func _demo_snapshot_at(time: float) -> Array:
	var states: Array = [{
		"peer_id": LOCAL_DEMO_PEER_ID,
		"position": local_position,
		"velocity": Vector3.ZERO,
		"yaw": local_yaw,
		"spawn_index": 0,
	}]
	for index in SIMULATED_PLAYER_COUNT:
		var patrol: Array = PATROLS[index]
		var sample := _patrol_sample(patrol, time * PATROL_SPEED + float(index) * 1.3)
		states.append({
			"peer_id": index + 2,
			"position": sample["position"],
			"velocity": Vector3.ZERO,
			"yaw": float(sample["yaw"]),
			"spawn_index": index + 1,
		})
	return states

## Vai e volta ao longo da patrulha, com velocidade constante.
static func _patrol_sample(patrol: Array, distance: float) -> Dictionary:
	var total := 0.0
	for point in range(1, patrol.size()):
		total += (patrol[point] as Vector3).distance_to(patrol[point - 1])
	var travelled := fposmod(distance, total * 2.0)
	var forward := travelled <= total
	var along := travelled if forward else total * 2.0 - travelled
	for point in range(1, patrol.size()):
		var start: Vector3 = patrol[point - 1]
		var finish: Vector3 = patrol[point]
		var length := start.distance_to(finish)
		if along <= length or point == patrol.size() - 1:
			var heading := (finish - start) if forward else (start - finish)
			return {"position": start.lerp(finish, clampf(along / length, 0.0, 1.0)),
				"yaw": atan2(-heading.x, -heading.z)}
		along -= length
	return {"position": patrol[0], "yaw": 0.0}

func _validate_demo() -> void:
	var states := _demo_snapshot()
	if states.size() != SIMULATED_PLAYER_COUNT + 1:
		_fail_demo_test("unexpected simulated player count")
		return
	# Amostra 60 s de patrulha: nenhum boneco sai da arena ou entra num bloco.
	for step in 600:
		var sampled := _demo_snapshot_at(float(step) * 0.1)
		var positions: Dictionary = {}
		for index in range(1, sampled.size()):
			var position: Vector3 = sampled[index]["position"]
			if absf(position.x) > MovementRules.ARENA_HALF_EXTENT or absf(position.z) > MovementRules.ARENA_HALF_EXTENT:
				_fail_demo_test("simulated player escaped arena")
				return
			if ArenaRules.overlaps_blocker(position):
				_fail_demo_test("simulated player entered arena geometry")
				return
			positions["%.3f,%.3f" % [position.x, position.z]] = true
		if positions.size() != SIMULATED_PLAYER_COUNT:
			_fail_demo_test("simulated positions are not distinct")
			return
	if ArenaRules.overlaps_blocker(local_position):
		_fail_demo_test("local demo spawn is inside arena geometry")
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
