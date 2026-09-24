class_name NetSync
extends RefCounted

## Parâmetros e formato do fluxo de comandos (protocolo 9, fase 4). Tabela e
## justificativas em `docs/netcode.md`. Aqui ficam apenas valores públicos e
## regras determinísticas usadas igualmente por servidor e cliente.

## Um comando vale exatamente um tick fixo. A duração é do servidor: não viaja
## no pacote, então o cliente não ganha tempo mandando dt maior.
const TICK_RATE := 60
const TICK_SECONDS := 1.0 / 60.0
## Envio: a cada 2 ticks (30 pacotes/s) e imediatamente quando há ação.
const SEND_INTERVAL_TICKS := 2
const MAX_COMMANDS_PER_PACKET := 8
## Servidor: fila por jogador, consumo por tick e orçamento de tempo.
const MAX_QUEUE_COMMANDS := 32
const TARGET_QUEUE_COMMANDS := 3
const MAX_SIMULATED_PER_TICK := 4
const MAX_BUDGET_TICKS := 12
const MAX_SEQUENCE_ADVANCE := 64
## Balde de pacotes (relógio do servidor): barra só inundação.
const MAX_PACKET_RATE := 60.0
const PACKET_BURST := 16.0
## Snapshot a cada 3 ticks (20 Hz), por destinatário, com tick e ACK.
const SNAPSHOT_INTERVAL_TICKS := 3
## Cliente: pendentes e correções.
const MAX_PENDING_COMMANDS := 90
const POSITION_SNAP_EPSILON := 0.01
const POSITION_SMOOTH_LIMIT := 1.0
const POSITION_SMOOTH_TAU := 0.1
const POSITION_SMOOTH_MAX := 0.25
const LOOK_SNAP_EPSILON := 0.002
const LOOK_SMOOTH_LIMIT := 0.1
const LOOK_SMOOTH_TAU := 0.05
const LOOK_SMOOTH_MAX := 0.15
## Folga da câmera contra parede ao aplicar offset visual de correção.
const CAMERA_CLEARANCE := 0.2
## Interpolação remota.
const INTERP_DELAY_TICKS := 6.0
const MAX_JITTER_DELAY_TICKS := 6.0
const CLOCK_ADJUST_RATE := 0.1
const CLOCK_RESYNC_TICKS := 30.0
const MAX_EXTRAPOLATION_TICKS := 6.0
const MAX_REMOTE_SAMPLES := 32
## Raio do corpo apresentado ao cortar quinas (menor que a hitbox de 0,45 m).
const PRESENTATION_BODY_RADIUS := 0.3
## Prazo máximo de convergência após o input parar (gate da fase 4).
const CONVERGENCE_DEADLINE_SECONDS := 1.0

const ACTION_FIRE := "fire"
const ACTION_RELOAD := "reload"
const ACTION_PICKUP := "pickup"
const ACTIONS := [ACTION_FIRE, ACTION_RELOAD, ACTION_PICKUP]

## Um comando no fio: [move_x, move_y, dyaw, dpitch, ação].
static func encode_command(move: Vector2, yaw_delta: float, pitch_delta: float, action: Array) -> Array:
	return [move.x, move.y, yaw_delta, pitch_delta, action]

static func encode_packet(epoch: int, first_seq: int, commands: Array) -> Array:
	return [epoch, first_seq, commands]

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT

## Lê um pacote recebido sem confiar em nada: tipos exatos antes de índices.
## Valores numéricos só são checados quanto ao tipo; finitude e limites são
## da simulação (`MovementRules.command_rejection`).
static func parse_packet(payload: Variant) -> Dictionary:
	if typeof(payload) != TYPE_ARRAY or (payload as Array).size() != 3:
		return {"reason": "malformed"}
	var packet: Array = payload
	if typeof(packet[0]) != TYPE_INT or typeof(packet[1]) != TYPE_INT or typeof(packet[2]) != TYPE_ARRAY:
		return {"reason": "malformed"}
	var raw_commands: Array = packet[2]
	if raw_commands.is_empty():
		return {"reason": "empty_batch"}
	if raw_commands.size() > MAX_COMMANDS_PER_PACKET:
		return {"reason": "batch_too_large"}
	if int(packet[1]) < 1:
		return {"reason": "invalid_sequence"}
	var commands: Array = []
	for raw in raw_commands:
		var command := parse_command(raw)
		if command.has("reason"):
			return {"reason": str(command["reason"])}
		commands.append(command)
	return {"reason": "", "epoch": int(packet[0]), "first_seq": int(packet[1]), "commands": commands}

static func parse_command(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != 5:
		return {"reason": "malformed"}
	var values: Array = raw
	for index in 4:
		if not _is_number(values[index]):
			return {"reason": "malformed"}
	var action := parse_action(values[4])
	if action.has("reason"):
		return {"reason": str(action["reason"])}
	return {"move": Vector2(float(values[0]), float(values[1])), "yaw_delta": float(values[2]),
		"pitch_delta": float(values[3]), "action": action}

## Ação vazia (`{}`) ou {kind, id[, pickup_id]} com tipos exatos.
static func parse_action(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY:
		return {"reason": "malformed_action"}
	var values: Array = raw
	if values.is_empty():
		return {}
	if typeof(values[0]) != TYPE_STRING or str(values[0]) not in ACTIONS:
		return {"reason": "malformed_action"}
	var kind := str(values[0])
	var expected_size := 3 if kind == ACTION_PICKUP else 2
	if values.size() != expected_size or typeof(values[1]) != TYPE_INT:
		return {"reason": "malformed_action"}
	var action := {"kind": kind, "id": int(values[1])}
	if kind == ACTION_PICKUP:
		if typeof(values[2]) != TYPE_STRING or str(values[2]).length() > 64:
			return {"reason": "malformed_action"}
		action["pickup_id"] = str(values[2])
	return action

static func encode_action(action: Dictionary) -> Array:
	if action.is_empty():
		return []
	if str(action["kind"]) == ACTION_PICKUP:
		return [ACTION_PICKUP, int(action["id"]), str(action.get("pickup_id", ""))]
	return [str(action["kind"]), int(action["id"])]
