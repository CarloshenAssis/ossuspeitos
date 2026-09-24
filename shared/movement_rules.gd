class_name MovementRules
extends RefCounted

const MAX_SPEED := 5.0
const ACCELERATION := 18.0
const INPUT_TIMEOUT_MSEC := 300
const MAX_YAW_DELTA := 0.35
const MAX_YAW_RATE := 3.0
## Mira vertical (pitch, radianos; positivo olha para cima). O limite evita
## olhar para os próprios pés ou para o zênite, onde a direção horizontal some.
const MAX_PITCH := deg_to_rad(75.0)
const MAX_PITCH_DELTA := 0.35
const MAX_PITCH_RATE := 3.0
const MAX_COMMAND_RATE := 30.0
const COMMAND_BURST := 4.0
const MAX_SEQUENCE_ADVANCE := 64
## Limite do centro do corpo. A face interna dos muros externos fica em
## `ArenaRules.INNER_HALF_EXTENT` (14,5 m), meio metro além deste limite.
const ARENA_HALF_EXTENT := 14.0
const PLAYER_HEIGHT := 1.0
const MOVEMENT_EPSILON := 0.001
const TEST_MOVEMENT_DISTANCE := 0.2
## Oito spawns, um por região de borda da arena graybox. Os quatro primeiros
## (usados numa sala de 4 jogadores) ficam dentro das salas dos cantos; os
## outros quatro atrás das coberturas das bordas. Nenhum spawn enxerga outro
## na altura do olho, nenhum toca um bloco e nenhum fica sobre um pickup.
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(-12.3, PLAYER_HEIGHT, -12.3),
	Vector3(12.3, PLAYER_HEIGHT, 12.3),
	Vector3(12.3, PLAYER_HEIGHT, -12.3),
	Vector3(-12.3, PLAYER_HEIGHT, 12.3),
	Vector3(0.0, PLAYER_HEIGHT, -13.0),
	Vector3(0.0, PLAYER_HEIGHT, 13.0),
	Vector3(-13.0, PLAYER_HEIGHT, 0.0),
	Vector3(13.0, PLAYER_HEIGHT, 0.0),
]

## Yaw inicial do spawn: de frente para o centro da arena (a porta da sala de
## canto ou a saída lateral da cobertura), nunca encarando o muro externo.
## Com yaw 0 o jogador olha para -Z; `yaw` gira essa direção em torno de +Y.
static func spawn_yaw(spawn: Vector3) -> float:
	return atan2(spawn.x, spawn.z)

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

static func integrate(state: Dictionary, delta: float, now_msec: int) -> void:
	var move: Vector2 = state["input"]
	if now_msec - int(state["last_input_msec"]) > INPUT_TIMEOUT_MSEC:
		move = Vector2.ZERO
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
	if absf(position.x) >= ARENA_HALF_EXTENT and signf(velocity.x) == signf(position.x):
		velocity.x = 0.0
	if absf(position.z) >= ARENA_HALF_EXTENT and signf(velocity.z) == signf(position.z):
		velocity.z = 0.0
	state["position"] = position
	state["velocity"] = velocity

## Aplica um deslocamento com colisão autoritativa contra `ArenaRules.BLOCKERS`.
## Cada eixo é resolvido separadamente, o que permite deslizar ao longo de uma
## parede. O passo é subdividido em trechos de no máximo `MAX_COLLISION_STEP`,
## menor que o bloco mais fino (0,5 m), então nenhum delta atravessa parede.
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
			var candidate := Vector3(clampf(position.x + chunk.x, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT), PLAYER_HEIGHT, position.z)
			if not started_inside and ArenaRules.overlaps_blocker(candidate):
				blocked_x = true
			else:
				position = candidate
		if not blocked_z and chunk.y != 0.0:
			var candidate := Vector3(position.x, PLAYER_HEIGHT, clampf(position.z + chunk.y, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT))
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
	}
