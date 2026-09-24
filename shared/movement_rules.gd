class_name MovementRules
extends RefCounted

const MAX_SPEED := 5.0
const ACCELERATION := 18.0
## Mira (protocolo 9): cada comando pode girar no máximo `MAX_YAW_DELTA`, e um
## balde por eixo (rajada `2 × MAX_YAW_DELTA`, reabastecido a `MAX_YAW_RATE`
## por segundo SIMULADO, isto é, por tick de comando) limita a taxa. Os valores
## são os do protocolo 8; só o relógio do balde passou a ser o da simulação,
## para que o cliente preveja exatamente o que o servidor aceita.
const MAX_YAW_DELTA := 0.35
const MAX_YAW_RATE := 3.0
## Mira vertical (pitch, radianos; positivo olha para cima). O limite evita
## olhar para os próprios pés ou para o zênite, onde a direção horizontal some.
const MAX_PITCH := deg_to_rad(75.0)
const MAX_PITCH_DELTA := 0.35
const MAX_PITCH_RATE := 3.0
const PLAYER_HEIGHT := 1.0
const MOVEMENT_EPSILON := 0.001
const TEST_MOVEMENT_DISTANCE := 0.2
## Limite de segurança do centro do corpo: o retângulo do piso livre da mansão.
## As paredes derivadas fecham a casa por dentro dele; o limite só existe para
## que um estado corrompido nunca saia para o vazio.
const MAP_MIN_X := -0.5
const MAP_MAX_X := 46.0
const MAP_MIN_Z := -1.0
const MAP_MAX_Z := 29.0
## Oito spawns candidatos da mansão (um por cômodo, fora o Salão). O servidor
## ocupa do primeiro livre em diante; os dados ficam em `MansionMap.SPAWNS`.
static var SPAWN_POINTS: Array[Vector3] = MansionMap.spawn_points()

## Yaw inicial do spawn: de frente para a porta do próprio cômodo.
## Com yaw 0 o jogador olha para -Z; `yaw` gira essa direção em torno de +Y.
static func spawn_yaw(spawn: Vector3) -> float:
	for index in SPAWN_POINTS.size():
		if SPAWN_POINTS[index].is_equal_approx(spawn):
			return MansionMap.spawn_yaw_at(index)
	return 0.0

static func validate_input(move: Vector2, yaw_delta: float, pitch_delta: float = 0.0) -> String:
	if not is_finite(move.x) or not is_finite(move.y) or not is_finite(yaw_delta) or not is_finite(pitch_delta):
		return "non_finite"
	if move.length_squared() > 1.0 + MOVEMENT_EPSILON:
		return "move_magnitude"
	if absf(yaw_delta) > MAX_YAW_DELTA:
		return "yaw_delta"
	if absf(pitch_delta) > MAX_PITCH_DELTA:
		return "pitch_delta"
	return ""

## Pitch oficial sempre finito e dentro do limite.
static func clamp_pitch(pitch: Variant) -> float:
	if typeof(pitch) != TYPE_FLOAT and typeof(pitch) != TYPE_INT:
		return 0.0
	if not is_finite(float(pitch)):
		return 0.0
	return clampf(float(pitch), -MAX_PITCH, MAX_PITCH)

## Direção da mira para um yaw e um pitch: a mesma base da câmera FPS
## (yaw em Y no corpo, pitch em X na câmera, frente -Z).
static func aim_direction(yaw: float, pitch: float) -> Vector3:
	var clamped := clamp_pitch(pitch)
	return Vector3(0.0, sin(clamped), -cos(clamped)).rotated(Vector3.UP, yaw).normalized()

## Recusa de um comando antes de simulá-lo (valores do cliente): vazio se ele
## pode ser aplicado ao estado atual. Não altera nada.
static func command_rejection(state: Dictionary, move: Vector2, yaw_delta: float, pitch_delta: float) -> String:
	var reason := validate_input(move, yaw_delta, pitch_delta)
	if not reason.is_empty():
		return reason
	if absf(yaw_delta) > _refilled(state, "yaw_tokens", MAX_YAW_DELTA, MAX_YAW_RATE) + 1e-9:
		return "yaw_rate"
	if absf(pitch_delta) > _refilled(state, "pitch_tokens", MAX_PITCH_DELTA, MAX_PITCH_RATE) + 1e-9:
		return "pitch_rate"
	return ""

static func _refilled(state: Dictionary, key: String, max_delta: float, rate: float) -> float:
	return minf(max_delta * 2.0, float(state.get(key, max_delta * 2.0)) + rate * NetSync.TICK_SECONDS)

## Primeira metade de um comando aceito: reabastece os baldes por um tick e
## aplica a mira. O pitch oficial é acumulado e preso ao limite.
static func apply_look(state: Dictionary, yaw_delta: float, pitch_delta: float) -> void:
	state["yaw_tokens"] = _refilled(state, "yaw_tokens", MAX_YAW_DELTA, MAX_YAW_RATE) - absf(yaw_delta)
	state["pitch_tokens"] = _refilled(state, "pitch_tokens", MAX_PITCH_DELTA, MAX_PITCH_RATE) - absf(pitch_delta)
	state["yaw"] = wrapf(float(state["yaw"]) + yaw_delta, -PI, PI)
	state["pitch"] = clamp_pitch(float(state.get("pitch", 0.0)) + pitch_delta)

## Maior mira que o próximo comando pode levar a partir de um pedido bruto do
## mouse: mesmos limites de `command_rejection`, e o pitch nunca pede além do
## limite oficial (o excesso não é transmitido nem acumulado).
static func look_intent(state: Dictionary, raw_yaw: float, raw_pitch: float) -> Vector2:
	var yaw_room := minf(MAX_YAW_DELTA, _refilled(state, "yaw_tokens", MAX_YAW_DELTA, MAX_YAW_RATE))
	var pitch_room := minf(MAX_PITCH_DELTA, _refilled(state, "pitch_tokens", MAX_PITCH_DELTA, MAX_PITCH_RATE))
	var yaw := clampf(raw_yaw if is_finite(raw_yaw) else 0.0, -yaw_room, yaw_room)
	var pitch := clampf(raw_pitch if is_finite(raw_pitch) else 0.0, -pitch_room, pitch_room)
	var current_pitch := float(state.get("pitch", 0.0))
	pitch = clamp_pitch(current_pitch + pitch) - current_pitch
	return Vector2(yaw, pitch)

## Segunda metade: um tick fixo de movimento com a entrada do comando, no yaw
## já atualizado. Sem relógio de parede: o servidor e o replay do cliente
## chegam ao mesmo resultado.
static func step_movement(state: Dictionary, move: Vector2, delta: float) -> void:
	var yaw := float(state["yaw"])
	var local_direction := Vector3(move.x, 0.0, move.y)
	var direction := local_direction.rotated(Vector3.UP, yaw)
	var target_velocity := direction * MAX_SPEED
	var velocity: Vector3 = state["velocity"]
	velocity = velocity.move_toward(target_velocity, ACCELERATION * delta)
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	var resolved := resolve_step(state["position"], velocity * delta)
	var position: Vector3 = resolved["position"]
	if bool(resolved["blocked_x"]):
		velocity.x = 0.0
	if bool(resolved["blocked_z"]):
		velocity.z = 0.0
	if (position.x <= MAP_MIN_X and velocity.x < 0.0) or (position.x >= MAP_MAX_X and velocity.x > 0.0):
		velocity.x = 0.0
	if (position.z <= MAP_MIN_Z and velocity.z < 0.0) or (position.z >= MAP_MAX_Z and velocity.z > 0.0):
		velocity.z = 0.0
	state["position"] = position
	state["velocity"] = velocity

## Comando completo sem ação (replay do cliente e testes): recusa ou aplica
## mira e movimento de um tick. Devolve o motivo da recusa ou vazio.
static func simulate_command(state: Dictionary, move: Vector2, yaw_delta: float, pitch_delta: float) -> String:
	var reason := command_rejection(state, move, yaw_delta, pitch_delta)
	if not reason.is_empty():
		return reason
	apply_look(state, yaw_delta, pitch_delta)
	step_movement(state, move, NetSync.TICK_SECONDS)
	return ""

## Aplica um deslocamento com colisão autoritativa contra `ArenaRules.BLOCKERS`.
## Cada eixo é resolvido separadamente, o que permite deslizar ao longo de uma
## parede. O passo é subdividido em trechos de no máximo `MAX_COLLISION_STEP`,
## menor que o diâmetro do corpo somado ao volume mais fino, então nenhum delta
## atravessa parede ou móvel.
## Um corpo que já esteja dentro de um bloco (teleporte de teste) não fica
## preso: só é barrado o trecho que entra num bloco a partir de posição livre.
const MAX_COLLISION_STEP := 0.2

static func resolve_step(from: Vector3, step: Vector3) -> Dictionary:
	var position := Vector3(from.x, PLAYER_HEIGHT, from.z)
	var remaining := Vector2(step.x, step.z)
	var chunks := maxi(1, int(ceil(remaining.length() / MAX_COLLISION_STEP)))
	var chunk := remaining / float(chunks)
	var blocked_x := false
	var blocked_z := false
	for _index in chunks:
		var started_inside := ArenaRules.overlaps_blocker(position)
		if not blocked_x and chunk.x != 0.0:
			var candidate := Vector3(clampf(position.x + chunk.x, MAP_MIN_X, MAP_MAX_X), PLAYER_HEIGHT, position.z)
			if not started_inside and ArenaRules.overlaps_blocker(candidate):
				blocked_x = true
			else:
				position = candidate
		if not blocked_z and chunk.y != 0.0:
			var candidate := Vector3(position.x, PLAYER_HEIGHT, clampf(position.z + chunk.y, MAP_MIN_Z, MAP_MAX_Z))
			if not started_inside and ArenaRules.overlaps_blocker(candidate):
				blocked_z = true
			else:
				position = candidate
	return {"position": position, "blocked_x": blocked_x, "blocked_z": blocked_z}

static func snapshot_state(peer_id: int, state: Dictionary) -> Dictionary:
	return {
		"peer_id": peer_id,
		"position": state["position"],
		"velocity": state["velocity"],
		"yaw": state["yaw"],
		"pitch": clamp_pitch(state.get("pitch", 0.0)),
		"spawn_index": state["spawn_index"],
		# Época pública: muda em reposicionamento, entrada da rodada e
		# eliminação (todos públicos). Quem apresenta trata como descontinuidade.
		"epoch": int(state.get("epoch", 0)),
	}
