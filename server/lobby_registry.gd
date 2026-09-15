class_name LobbyRegistry
extends RefCounted

## Registro oficial das sessões conectadas. Vive somente no servidor.
##
## A identidade de rede é sempre o `peer_id` obtido de
## `multiplayer.get_remote_sender_id()`; o rótulo enviado pelo cliente é
## metadado público e não confiável, apenas sanitizado e checado por colisão.

var _entries: Dictionary = {}
var _labels: Dictionary = {}
var _next_order := 0

func size() -> int:
	return _entries.size()

func is_empty() -> bool:
	return _entries.is_empty()

func is_full() -> bool:
	return _entries.size() >= RoundRules.MAX_PLAYERS

func has(peer_id: int) -> bool:
	return _entries.has(peer_id)

func label_for(peer_id: int) -> String:
	if not _entries.has(peer_id):
		return ""
	return str(_entries[peer_id]["label"])

func order_for(peer_id: int) -> int:
	if not _entries.has(peer_id):
		return -1
	return int(_entries[peer_id]["order"])

## Peers em ordem de entrada.
func peer_ids() -> Array:
	var ordered := _entries.keys()
	ordered.sort_custom(func(left, right): return int(_entries[left]["order"]) < int(_entries[right]["order"]))
	return ordered

## Devolve "" quando a entrada é aceitável ou o motivo público da recusa.
func validate_join(peer_id: int, raw_label: String) -> String:
	if peer_id <= 0:
		return "invalid_client"
	var label_reason := RoundRules.validate_label(raw_label)
	if not label_reason.is_empty():
		return label_reason
	if _entries.has(peer_id):
		return "invalid_client"
	var clean := RoundRules.sanitize_label(raw_label)
	if is_full() or _labels.has(clean):
		return "room_unavailable"
	return ""

## Registra a sessão. Devolve "" em caso de sucesso ou o motivo da recusa.
func add(peer_id: int, raw_label: String) -> String:
	var reason := validate_join(peer_id, raw_label)
	if not reason.is_empty():
		return reason
	var clean := RoundRules.sanitize_label(raw_label)
	_entries[peer_id] = {
		"label": clean,
		"order": _next_order,
		"connected": true,
	}
	_labels[clean] = peer_id
	_next_order += 1
	return ""

func remove(peer_id: int) -> bool:
	if not _entries.has(peer_id):
		return false
	_labels.erase(str(_entries[peer_id]["label"]))
	_entries.erase(peer_id)
	return true

func clear() -> void:
	_entries.clear()
	_labels.clear()
	_next_order = 0

## Entradas seguras para o roster público. Nunca contém papel.
func public_entries() -> Array:
	var result: Array = []
	for peer_id in peer_ids():
		result.append({
			"peer_id": int(peer_id),
			"label": str(_entries[peer_id]["label"]),
			"connected": bool(_entries[peer_id]["connected"]),
		})
	return result
