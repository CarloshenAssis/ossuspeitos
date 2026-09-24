class_name BodyRegistry
extends RefCounted

## Corpos oficiais da rodada corrente (servidor). Um por jogador eliminado por
## rodada; evento repetido não cria outro. Limpo no início da rodada seguinte.
## Desconectar depois de morrer não remove o corpo.

var bodies: Dictionary = {}
var _by_peer: Dictionary = {}
var _next_id := 1

## Registra o corpo e devolve o DTO público, ou vazio se já existe.
func add(round_id: int, peer_id: int, position: Vector3, yaw: float, appearance: String) -> Dictionary:
	var key := "%d:%d" % [round_id, peer_id]
	if round_id <= 0 or _by_peer.has(key):
		return {}
	var dto := BodyRules.make(_next_id, round_id, peer_id, position, yaw, appearance)
	bodies[_next_id] = dto
	_by_peer[key] = _next_id
	_next_id += 1
	return dto.duplicate()

func public_list() -> Array:
	var result: Array = []
	var ids := bodies.keys()
	ids.sort()
	for body_id in ids:
		result.append((bodies[body_id] as Dictionary).duplicate())
	return result

func size() -> int:
	return bodies.size()

func clear() -> void:
	bodies.clear()
	_by_peer.clear()
