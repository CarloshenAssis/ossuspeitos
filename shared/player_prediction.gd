class_name PlayerPrediction
extends RefCounted

## Previsão do jogador local (fase 4). Puro: não conhece rede, nós nem
## efeitos, então o replay nunca toca som, flash, munição ou RPC.
##
## Três domínios:
## - `official`: estado oficial do último ACK (posição, velocidade, mira e
##   baldes de mira daquele ponto);
## - `state`: previsto = oficial + replay dos comandos ainda pendentes;
## - apresentação (`presented`): previsto interpolado entre ticks, mais o mouse
##   ainda não comandado, mais o offset amortecido de uma correção.
##
## Cada comando vale um tick fixo e guarda a mira que carregou, então o replay
## reproduz a mesma linha do tempo do servidor (mesmo integrador, mesma ordem).

var epoch := 0
var next_seq := 1
var last_ack := 0
var pending: Array = []
var official: Dictionary = {}
var state: Dictionary = {}
var previous_position := Vector3.ZERO
var has_state := false
## Mouse ainda não comandado (radianos). Com uma ação na fila, a parte
## anterior ao clique fica em `split_*` e vai no comando da ação; o que chega
## depois do clique fica para o comando seguinte.
var raw_yaw := 0.0
var raw_pitch := 0.0
var split_yaw := 0.0
var split_pitch := 0.0
var queued_action: Dictionary = {}
## Instante (µs) do evento de mouse mais antigo ainda não apresentado.
var look_pending_since_usec := 0
## Offsets visuais de correção (apresentação apenas).
var position_offset := Vector3.ZERO
var position_offset_age := 0.0
var look_offset := Vector2.ZERO
var look_offset_age := 0.0
## Instrumentação.
var corrections_small := 0
var corrections_large := 0
var look_corrections := 0
var recoveries := 0
var epoch_resets := 0
var local_rejections := 0
var ack_errors_position: Array = []
var ack_errors_look: Array = []
const MAX_SAMPLES := 512

func reset_all() -> void:
	epoch = 0
	last_ack = 0
	pending.clear()
	official.clear()
	state.clear()
	has_state = false
	clear_look()
	queued_action = {}
	position_offset = Vector3.ZERO
	look_offset = Vector2.ZERO

## Foco perdido, UI, eliminação: nenhum giro residual sobrevive.
func clear_look() -> void:
	raw_yaw = 0.0
	raw_pitch = 0.0
	split_yaw = 0.0
	split_pitch = 0.0
	look_pending_since_usec = 0

func add_look(yaw_delta: float, pitch_delta: float, event_usec: int = 0) -> void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta):
		return
	raw_yaw += yaw_delta
	raw_pitch += pitch_delta
	if look_pending_since_usec == 0:
		look_pending_since_usec = event_usec if event_usec > 0 else Time.get_ticks_usec()

## Uma ação por tick. A mira até aqui vai com ela; recusa se já há uma na fila.
func queue_action(action: Dictionary) -> bool:
	if not queued_action.is_empty() or action.is_empty():
		return false
	queued_action = action
	split_yaw = raw_yaw
	split_pitch = raw_pitch
	raw_yaw = 0.0
	raw_pitch = 0.0
	return true

## Forma o comando do tick, simula-o localmente e guarda para replay.
## Mouse além do limite de mira oficial é descartado (não vira giro atrasado).
func build_command(move: Vector2) -> Dictionary:
	var has_action := not queued_action.is_empty()
	var want_yaw := split_yaw if has_action else raw_yaw
	var want_pitch := split_pitch if has_action else raw_pitch
	var look: Array = MovementRules.look_intent(state, want_yaw, want_pitch) if has_state else [0.0, 0.0]
	var look_yaw: float = look[0]
	var look_pitch: float = look[1]
	if has_action:
		split_yaw = 0.0
		split_pitch = 0.0
	else:
		raw_yaw = 0.0
		raw_pitch = 0.0
	var command := {"seq": next_seq, "epoch": epoch, "move": move, "yaw_delta": look_yaw,
		"pitch_delta": look_pitch, "action": queued_action, "built_usec": Time.get_ticks_usec()}
	next_seq += 1
	queued_action = {}
	if has_state:
		previous_position = state["position"]
		var reason := MovementRules.simulate_command(state, move, look_yaw, look_pitch)
		if not reason.is_empty():
			local_rejections += 1
		command["predicted_position"] = state["position"]
		command["predicted_yaw"] = float(state["yaw"])
		command["predicted_pitch"] = float(state["pitch"])
	pending.append(command)
	if pending.size() > NetSync.MAX_PENDING_COMMANDS:
		_recover()
	return command

## ACK muito atrasado: volta ao oficial e descarta o histórico local em vez
## de crescer sem limite. Os comandos já enviados continuam no servidor e o
## próximo ACK reconcilia.
func _recover() -> void:
	recoveries += 1
	pending.clear()
	if not official.is_empty():
		state = official.duplicate()
		previous_position = state["position"]
	position_offset = Vector3.ZERO
	look_offset = Vector2.ZERO

static func official_from(player: Dictionary, ack: Dictionary) -> Dictionary:
	return {"position": player["position"], "velocity": player.get("velocity", Vector3.ZERO),
		"yaw": float(player["yaw"]), "pitch": MovementRules.clamp_pitch(player.get("pitch", 0.0)),
		"yaw_tokens": float(ack.get("yaw_tokens", MovementRules.MAX_YAW_DELTA * 2.0)),
		"pitch_tokens": float(ack.get("pitch_tokens", MovementRules.MAX_PITCH_DELTA * 2.0))}

## Snapshot com ACK. Descarta o que o servidor resolveu, restaura o oficial
## daquele ponto e reaplica em ordem só o que continua pendente.
func reconcile(ack: Dictionary, player: Dictionary) -> Dictionary:
	var ack_seq := int(ack.get("seq", 0))
	var ack_epoch := int(ack.get("epoch", 0))
	if has_state and ack_seq < last_ack:
		return {"stale": true}
	official = official_from(player, ack)
	if not has_state or ack_epoch != epoch:
		if has_state:
			epoch_resets += 1
		epoch = ack_epoch
		last_ack = ack_seq
		pending.clear()
		state = official.duplicate()
		previous_position = state["position"]
		position_offset = Vector3.ZERO
		look_offset = Vector2.ZERO
		has_state = true
		return {"reset": true}
	last_ack = ack_seq
	var resolved_prediction: Dictionary = {}
	while not pending.is_empty() and int(pending[0]["seq"]) <= ack_seq:
		resolved_prediction = pending.pop_front()
	# Erro da previsão no ponto do ACK (antes de reconciliar).
	if resolved_prediction.has("predicted_position") and int(resolved_prediction["seq"]) == ack_seq:
		_sample(ack_errors_position, (resolved_prediction["predicted_position"] as Vector3).distance_to(official["position"]))
		_sample(ack_errors_look, maxf(absf(angle_difference(float(resolved_prediction["predicted_yaw"]), float(official["yaw"]))),
			absf(float(resolved_prediction["predicted_pitch"]) - float(official["pitch"]))))
	var old_position: Vector3 = state["position"]
	var old_yaw := float(state["yaw"])
	var old_pitch := float(state["pitch"])
	var replay := official.duplicate()
	for command in pending:
		MovementRules.simulate_command(replay, command["move"], float(command["yaw_delta"]), float(command["pitch_delta"]))
	var shift: Vector3 = (replay["position"] as Vector3) - old_position
	previous_position += shift
	state = replay
	var error := -shift
	var result := {"error_position": error.length(), "replayed": pending.size()}
	if error.length() >= NetSync.POSITION_SMOOTH_LIMIT:
		corrections_large += 1
		position_offset = Vector3.ZERO
	elif error.length() >= NetSync.POSITION_SNAP_EPSILON:
		corrections_small += 1
		position_offset += error
		position_offset_age = 0.0
	var look_error := Vector2(angle_difference(float(replay["yaw"]), old_yaw), old_pitch - float(replay["pitch"]))
	result["error_look"] = look_error.length()
	if look_error.length() >= NetSync.LOOK_SMOOTH_LIMIT:
		look_corrections += 1
		look_offset = Vector2.ZERO
	elif look_error.length() >= NetSync.LOOK_SNAP_EPSILON:
		look_corrections += 1
		look_offset += look_error
		look_offset_age = 0.0
	return result

## Estado de apresentação do quadro. Chamado uma vez por quadro: amortece os
## offsets de correção e nunca deixa o offset levar a câmera para dentro de
## um volume oficial.
func presented(fraction: float, delta: float) -> Dictionary:
	if not has_state:
		return {}
	position_offset_age += delta
	look_offset_age += delta
	if position_offset_age >= NetSync.POSITION_SMOOTH_MAX:
		position_offset = Vector3.ZERO
	else:
		position_offset *= exp(-delta / NetSync.POSITION_SMOOTH_TAU)
	if look_offset_age >= NetSync.LOOK_SMOOTH_MAX:
		look_offset = Vector2.ZERO
	else:
		look_offset *= exp(-delta / NetSync.LOOK_SMOOTH_TAU)
	var base := previous_position.lerp(state["position"], clampf(fraction, 0.0, 1.0))
	var position := base + position_offset
	if position_offset != Vector3.ZERO and ArenaRules.overlaps_blocker(position, NetSync.CAMERA_CLEARANCE):
		position_offset = Vector3.ZERO
		position = base
	var preview: Array = MovementRules.look_intent(state, split_yaw + raw_yaw, split_pitch + raw_pitch)
	var yaw := wrapf(float(state["yaw"]) + float(preview[0]) + look_offset.x, -PI, PI)
	var pitch := MovementRules.clamp_pitch(float(state["pitch"]) + float(preview[1]) + look_offset.y)
	var look_latency_usec := 0
	if look_pending_since_usec > 0:
		look_latency_usec = Time.get_ticks_usec() - look_pending_since_usec
		look_pending_since_usec = 0
	return {"position": position, "yaw": yaw, "pitch": pitch, "look_latency_usec": look_latency_usec}

func oldest_pending_age_usec() -> int:
	return Time.get_ticks_usec() - int(pending[0]["built_usec"]) if not pending.is_empty() else 0

func _sample(samples: Array, value: float) -> void:
	if samples.size() >= MAX_SAMPLES:
		samples.pop_front()
	samples.append(value)
