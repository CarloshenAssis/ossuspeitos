class_name RoomRegistry
extends RefCounted

## Salas ativas de um processo de servidor (fase 9). Tudo em memória: sem
## banco, sem Redis, uma única instância. Reiniciar o servidor encerra todas
## as salas.
##
## Cada peer está em no máximo uma sala; o vínculo peer -> sala é decidido
## aqui pelo servidor (nunca por um `room_id` enviado pelo cliente).

## Limite padrão conservador de salas por processo (8 jogadores cada); pode
## ser mudado por `ARMED_MYSTERY_MAX_ROOMS` (1 a 64) no servidor dedicado.
const DEFAULT_MAX_ROOMS := 12
const MAX_ROOMS_LIMIT := 64
## Sala vazia é destruída depois desta carência.
const EMPTY_ROOM_GRACE_MSEC := 30000
## Lobby de sala sem nenhuma atividade (entrada, saída, PRONTO) expira.
const LOBBY_IDLE_MSEC := 30 * 60 * 1000
## Conexão que fez o handshake mas não entrou em sala sai depois disto.
const HALL_IDLE_MSEC := 10 * 60 * 1000
## Falhas de entrada por código (código errado, sala cheia...) por conexão.
const MAX_JOIN_FAILURES := 8

var max_rooms := DEFAULT_MAX_ROOMS
var countdown_seconds := RoomRules.COUNTDOWN_SECONDS
var results_seconds := RoomRules.RESULTS_SECONDS
var rooms: Dictionary = {}
var _by_code: Dictionary = {}
var _peer_room: Dictionary = {}
var _next_room_id := 1
var _crypto := Crypto.new()

func room_count() -> int:
	return rooms.size()

func can_create() -> bool:
	return rooms.size() < max_rooms

## Nova sala com código único, ou null no limite. `code_source` permite
## injetar bytes nos testes; por padrão usa `Crypto` (aleatório seguro).
func create_room(now_msec: int, code_source: Callable = Callable()) -> MatchRoom:
	if not can_create():
		return null
	var code := ""
	for _attempt in 32:
		var bytes: PackedByteArray = code_source.call() if code_source.is_valid() else _crypto.generate_random_bytes(RoomRules.CODE_LENGTH)
		var candidate := RoomRules.code_from_bytes(bytes)
		if not _by_code.has(candidate):
			code = candidate
			break
	if code.is_empty():
		return null
	var room := MatchRoom.new(_next_room_id, code, now_msec, true, countdown_seconds, results_seconds)
	_next_room_id += 1
	rooms[room.room_id] = room
	_by_code[code] = room.room_id
	return room

## Sala pelo código de convite (já normalizado), ou null.
func find_by_code(code: String) -> MatchRoom:
	if not _by_code.has(code):
		return null
	return rooms.get(int(_by_code[code]), null)

func room_of(peer_id: int) -> MatchRoom:
	if not _peer_room.has(peer_id):
		return null
	return rooms.get(int(_peer_room[peer_id]), null)

func assign(peer_id: int, room: MatchRoom) -> void:
	_peer_room[peer_id] = room.room_id

func unassign(peer_id: int) -> void:
	_peer_room.erase(peer_id)

func destroy(room: MatchRoom) -> Array:
	var members := room.lobby.peer_ids()
	for peer_id in members:
		_peer_room.erase(int(peer_id))
	_by_code.erase(room.code)
	rooms.erase(room.room_id)
	room.clear()
	return members

## Salas que devem sair agora: [{room, reason}].
func due_for_removal(now_msec: int) -> Array:
	var result: Array = []
	for room in rooms.values():
		var reason: String = (room as MatchRoom).destroy_reason(now_msec, EMPTY_ROOM_GRACE_MSEC, LOBBY_IDLE_MSEC)
		if not reason.is_empty():
			result.append({"room": room, "reason": reason})
	return result

func total_members() -> int:
	var total := 0
	for room in rooms.values():
		total += (room as MatchRoom).member_count()
	return total

func clear() -> void:
	for room in rooms.values():
		(room as MatchRoom).clear()
	rooms.clear()
	_by_code.clear()
	_peer_room.clear()
