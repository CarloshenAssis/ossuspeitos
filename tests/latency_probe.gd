extends Node

## Sonda de resposta local e suavidade remota (fase 4). Só roda com
## `--latency-probe=observer|mover` num cliente gráfico de teste; mede pelo
## caminho normal de entrada (`Input.parse_input_event` / `Input.action_press`)
## e pela câmera/avatar realmente desenhados (`RenderingServer.frame_post_draw`).
##
## observer: (1) mouse → primeiro quadro desenhado com a câmera girada;
##           (2) tecla → primeiro quadro com a câmera deslocada;
##           (3) suavidade do avatar do "mover" (variação da velocidade
##               apresentada por quadro e quadros parados durante a caminhada).
## mover:    anda de um lado para o outro pelo caminho normal de teclas.
##
## Não é latência física mouse→monitor: mede do evento consumido pelo jogo até
## o fim do desenho do quadro que já mostra o efeito.

var app
var role := ""
var rng := RandomNumberGenerator.new()
var phase := "WAIT_ACTIVE"
var phase_started_usec := 0
var trial := 0
var trial_start_usec := 0
var trial_ref := 0.0
var trial_ref_pos := Vector3.ZERO
var trial_waiting := false
var next_trial_usec := 0
var mouse_samples: Array = []
var key_samples: Array = []
var remote_speeds: Array = []
var remote_moving_frames := 0
var remote_still_frames := 0
var remote_jumps := 0
var _last_remote_pos := Vector3.INF
var _last_official_speed := 0.0
var _last_frame_usec := 0
var frame_intervals: Array = []
var dump_rows: Array = []
var last_process_delta := 0.0
var steady_speeds: Array = []
var consumed_usec := 0
var consumed_frames := 0
var consumed_samples: Array = []
var consumed_frame_counts: Array = []
var mover_direction := 1
var mover_switch_usec := 0
var mover_until_usec := 0
const MOUSE_TRIALS := 24
const KEY_TRIALS := 12
const REMOTE_SECONDS := 8.0
const MOUSE_PIXELS := 40.0

func _ready() -> void:
	app = get_parent()
	role = str(app.arguments.get("latency-probe", ""))
	rng.seed = NetworkConfig.integer_argument(app.arguments, "latency-probe-seed", 7)
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	print("LATENCY_PROBE_READY role=%s" % role)

func _ready_for_gameplay() -> bool:
	return app.joined and app.arena_view != null and app._client_can_gameplay() \
		and not app.arena_view._local_state.is_empty()

## Momento em que o jogo consome o evento de mouse injetado (antes do
## `_unhandled_input` da rede), para medir consumo → quadro desenhado.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and phase == "MOUSE" and trial_waiting and consumed_usec == 0:
		consumed_usec = Time.get_ticks_usec()
		consumed_frames = 0

func _process(delta: float) -> void:
	last_process_delta = delta
	var now := Time.get_ticks_usec()
	if phase == "WAIT_ACTIVE":
		if _ready_for_gameplay():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			phase = "SETTLE"
			phase_started_usec = now
		return
	if role == "mover":
		_mover_tick(now)
		return
	if phase == "SETTLE" and now - phase_started_usec > 1_500_000:
		phase = "MOUSE"
		next_trial_usec = now
	elif phase == "MOUSE" and not trial_waiting and now >= next_trial_usec:
		if trial >= MOUSE_TRIALS:
			phase = "KEYS"; trial = 0; next_trial_usec = now + 500_000
			return
		var event := InputEventMouseMotion.new()
		var sign := 1.0 if trial % 2 == 0 else -1.0
		event.relative = Vector2(MOUSE_PIXELS * sign, 0.0)
		trial_ref = app.arena_view.camera.global_rotation.y
		trial_start_usec = Time.get_ticks_usec()
		trial_waiting = true
		Input.parse_input_event(event)
	elif phase == "KEYS" and not trial_waiting and now >= next_trial_usec:
		if trial >= KEY_TRIALS:
			phase = "REMOTE"; phase_started_usec = now
			return
		var action := "move_forward" if trial % 2 == 0 else "move_backward"
		trial_ref_pos = app.arena_view.camera.global_position
		trial_start_usec = Time.get_ticks_usec()
		trial_waiting = true
		Input.action_press(action)
	elif phase == "REMOTE" and now - phase_started_usec > int(REMOTE_SECONDS * 1_000_000):
		_report()
		phase = "DONE"

func _on_frame_drawn() -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0 and phase != "WAIT_ACTIVE":
		_record(frame_intervals, float(now - _last_frame_usec) / 1000.0)
	_last_frame_usec = now
	if role != "observer" or app.arena_view == null:
		return
	if phase == "MOUSE" and trial_waiting:
		if consumed_usec > 0:
			consumed_frames += 1
		if absf(angle_difference(trial_ref, app.arena_view.camera.global_rotation.y)) > 0.01:
			_record(mouse_samples, float(now - trial_start_usec) / 1000.0)
			if consumed_usec > 0:
				_record(consumed_samples, float(now - consumed_usec) / 1000.0)
				_record(consumed_frame_counts, float(consumed_frames))
			consumed_usec = 0
			trial_waiting = false
			trial += 1
			next_trial_usec = now + rng.randi_range(150_000, 320_000)
		elif now - trial_start_usec > 2_000_000:
			print("LATENCY_PROBE_TIMEOUT kind=mouse trial=%d" % trial)
			trial_waiting = false; trial += 1; next_trial_usec = now + 200_000
	elif phase == "KEYS" and trial_waiting:
		if app.arena_view.camera.global_position.distance_to(trial_ref_pos) > 0.005:
			_record(key_samples, float(now - trial_start_usec) / 1000.0)
			trial_waiting = false
			trial += 1
			Input.action_release("move_forward"); Input.action_release("move_backward")
			next_trial_usec = now + rng.randi_range(700_000, 900_000)
		elif now - trial_start_usec > 2_000_000:
			print("LATENCY_PROBE_TIMEOUT kind=key trial=%d" % trial)
			Input.action_release("move_forward"); Input.action_release("move_backward")
			trial_waiting = false; trial += 1; next_trial_usec = now + 700_000
	elif phase == "REMOTE":
		_sample_remote()

## Avatar do "mover": posição apresentada por quadro. Passo muito menor que a
## mediana durante a caminhada conta como quadro parado (engasgo); salto acima
## de 3x a velocidade máxima, como salto.
func _sample_remote() -> void:
	var mover := _mover_peer()
	if mover == 0 or not app.arena_view.avatars.has(mover):
		return
	var position: Vector3 = (app.arena_view.avatars[mover] as Node3D).global_position
	if _last_remote_pos != Vector3.INF and frame_intervals.size() > 0:
		var dt: float = float(frame_intervals[-1]) / 1000.0
		var speed := Vector2(position.x - _last_remote_pos.x, position.z - _last_remote_pos.z).length() / maxf(dt, 0.001)
		# Mesma medida pelo delta de processamento (o tempo que a apresentação
		# usa), sem o ruído do tempo de desenho do renderizador por software.
		var process_speed := Vector2(position.x - _last_remote_pos.x, position.z - _last_remote_pos.z).length() / maxf(last_process_delta, 0.001)
		var official: Dictionary = app.arena_view.targets.get(mover, {})
		var official_speed := (official.get("velocity", Vector3.ZERO) as Vector3).length()
		if dump_rows.size() < 4000:
			dump_rows.append("%d,%.4f,%.4f,%.4f,%.3f,%.3f,%.4f,%.4f" % [Time.get_ticks_usec(), dt, position.x, position.z, speed, official_speed,
				(official.get("position", Vector3.ZERO) as Vector3).x, (official.get("position", Vector3.ZERO) as Vector3).z])
		if official_speed > 4.99 and _last_official_speed > 4.99:
			_record(steady_speeds, process_speed)
		_last_official_speed = official_speed
		if official_speed > 3.0:
			remote_moving_frames += 1
			_record(remote_speeds, speed)
			if speed < 0.5:
				remote_still_frames += 1
			if speed > MovementRules.MAX_SPEED * 3.0:
				remote_jumps += 1
	_last_remote_pos = position

func _mover_peer() -> int:
	var labels := _labels()
	for peer_id in labels:
		if str(labels[peer_id]) == "mover" and app.arena_view.avatars.has(int(peer_id)):
			return int(peer_id)
	return 0

func _labels() -> Dictionary:
	var result := {}
	if app.round_hud == null:
		return result
	var roster: Variant = app.round_hud.get("_roster")
	if typeof(roster) == TYPE_ARRAY:
		for entry in roster:
			result[int(entry.get("peer_id", 0))] = str(entry.get("label", ""))
	return result

func _mover_tick(now: int) -> void:
	if phase == "SETTLE":
		phase = "WALK"
		mover_switch_usec = now
		mover_until_usec = now + 60_000_000
	if phase != "WALK":
		return
	if now >= mover_until_usec:
		Input.action_release("move_left"); Input.action_release("move_right")
		phase = "DONE"
		return
	if now >= mover_switch_usec:
		Input.action_release("move_left"); Input.action_release("move_right")
		Input.action_press("move_right" if mover_direction > 0 else "move_left")
		mover_direction = -mover_direction
		mover_switch_usec = now + 1_100_000

func _record(samples: Array, value: float) -> void:
	if samples.size() < 4096:
		samples.append(value)

static func stats(samples: Array) -> String:
	if samples.is_empty():
		return "n=0"
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for value in sorted: total += float(value)
	return "n=%d,p50=%.1f,p95=%.1f,max=%.1f,mean=%.1f" % [sorted.size(), float(sorted[int(sorted.size() * 0.5)]),
		float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]), float(sorted[-1]), total / sorted.size()]

static func coefficient_of_variation(samples: Array) -> float:
	if samples.size() < 2:
		return 0.0
	var mean := 0.0
	for value in samples: mean += float(value)
	mean /= samples.size()
	var variance := 0.0
	for value in samples: variance += pow(float(value) - mean, 2.0)
	variance /= samples.size() - 1
	return sqrt(variance) / maxf(mean, 0.0001)

func _report() -> void:
	var net := ""
	if app.test_net_peer != null:
		net = app.test_net_peer.call("summary")
	print("LATENCY_PROBE_RESULT kind=mouse_to_frame_ms %s" % stats(mouse_samples))
	print("LATENCY_PROBE_RESULT kind=mouse_consumed_to_frame_ms %s frames_until_visible=%s" % [stats(consumed_samples), stats(consumed_frame_counts)])
	print("LATENCY_PROBE_RESULT kind=key_to_frame_ms %s" % stats(key_samples))
	print("LATENCY_PROBE_RESULT kind=remote_steady_speed %s cv=%.3f" % [stats(steady_speeds), coefficient_of_variation(steady_speeds)])
	print("LATENCY_PROBE_RESULT kind=frame_interval_ms %s" % stats(frame_intervals))
	print("LATENCY_PROBE_RESULT kind=remote_speed %s cv=%.3f moving_frames=%d still_frames=%d jumps=%d" % [
		stats(remote_speeds), coefficient_of_variation(remote_speeds), remote_moving_frames, remote_still_frames, remote_jumps])
	print("LATENCY_PROBE_NET %s" % net)
	var dump_path := str(app.arguments.get("latency-probe-dump", ""))
	if not dump_path.is_empty():
		var file := FileAccess.open(dump_path, FileAccess.WRITE)
		if file != null:
			file.store_string("usec,dt,x,z,speed,official_speed,official_x,official_z\n" + "\n".join(dump_rows))
			file.close()
	print("LATENCY_PROBE_DONE role=observer")
