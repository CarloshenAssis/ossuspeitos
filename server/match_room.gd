class_name MatchRoom
extends RefCounted

## Uma sala do servidor (fase 9): estado de partida totalmente isolado. Cada
## sala tem o próprio lobby, rodada (papéis, vivos, reveal), mundo oficial
## (posições, comandos, spawns), combate (armas, munição, pickups) e corpos.
## Nada aqui é compartilhado com outra sala; a camada de rede só envia o que
## sai de uma sala aos peers dessa mesma sala.
##
## O anfitrião é só organizador (rótulo "ANFITRIÃO"): não decide papel,
## combate, início nem resultado. Se ele sair, o posto passa para quem está
## conectado há mais tempo (ordem de entrada).
##
## Também usada, sem código e sem gate de PRONTO, como a sala única dos modos
## local/LAN/testes (comportamento anterior à fase 9).

var room_id := 0
var code := ""
var lobby := LobbyRegistry.new()
var round_authority: RoundAuthority
var world := AuthoritativeWorld.new()
var combat: CombatAuthority
var bodies := BodyRegistry.new()
var host_peer_id := 0
var created_msec := 0
var last_activity_msec := 0
## Desde quando está vazia (0 = tem gente).
var empty_since_msec := 0
## Resultado público da última rodada (vencedor, motivo, papéis por rótulo).
var last_result: Dictionary = {}

func _init(id: int, room_code: String, now_msec: int, ready_gate: bool,
		countdown_seconds: float, round_end_delay_seconds: float, seed_value: int = 0) -> void:
	room_id = id
	code = room_code
	created_msec = now_msec
	last_activity_msec = now_msec
	empty_since_msec = now_msec
	round_authority = RoundAuthority.new(lobby, seed_value)
	round_authority.configure(countdown_seconds, round_end_delay_seconds)
	round_authority.ready_gate = ready_gate
	combat = CombatAuthority.new(round_authority, world)

func member_count() -> int:
	return lobby.size()

func has_member(peer_id: int) -> bool:
	return lobby.has(peer_id)

func is_empty() -> bool:
	return lobby.is_empty()

func touch(now_msec: int) -> void:
	last_activity_msec = now_msec

## Pode receber alguém agora? "" ou motivo público. Com o gate (sala online),
## só no lobby ou na contagem: nunca no meio da rodada (nenhum dado privado
## vaza para quem chega) nem na tela de resultado.
func join_block_reason() -> String:
	if lobby.is_full():
		return "room_full"
	if round_authority.ready_gate and round_authority.state != RoundState.WAITING \
			and round_authority.state != RoundState.COUNTDOWN:
		return "round_in_progress"
	return ""

## Entra na sala. Devolve {reason} ou {reason: "", state: estado oficial no mundo}.
func add_member(peer_id: int, raw_label: String, now_msec: int) -> Dictionary:
	var blocked := join_block_reason()
	if not blocked.is_empty():
		return {"reason": blocked}
	var reason := lobby.validate_join(peer_id, raw_label)
	if not reason.is_empty():
		return {"reason": _public_reason(reason)}
	var state := world.add_player(peer_id)
	if state.is_empty():
		return {"reason": "room_full"}
	var join_reason := round_authority.join(peer_id, raw_label, now_msec)
	if not join_reason.is_empty():
		world.remove_player(peer_id)
		return {"reason": _public_reason(join_reason)}
	if host_peer_id == 0 or not lobby.has(host_peer_id):
		host_peer_id = peer_id
	empty_since_msec = 0
	touch(now_msec)
	return {"reason": "", "state": state}

## Sai da sala (desconexão). Aplica a política da rodada atual, passa o posto
## de anfitrião adiante e marca quando a sala esvaziou.
func remove_member(peer_id: int, now_msec: int) -> bool:
	if not lobby.has(peer_id):
		return false
	world.remove_player(peer_id)
	combat.clear_player(peer_id)
	round_authority.leave(peer_id, now_msec)
	if host_peer_id == peer_id:
		var remaining := lobby.peer_ids()
		host_peer_id = int(remaining[0]) if not remaining.is_empty() else 0
	if lobby.is_empty():
		empty_since_msec = now_msec
	touch(now_msec)
	return true

func set_ready(peer_id: int, value: bool, now_msec: int) -> String:
	var reason := round_authority.set_ready(peer_id, value, now_msec)
	if reason.is_empty():
		touch(now_msec)
	return reason

func phase() -> String:
	return RoomRules.phase_for_round_state(round_authority.state)

## Guarda o resultado da rodada em forma pública: papéis por rótulo, só
## depois do fim (o mesmo conteúdo do reveal que os participantes já recebem).
func record_result(reveal: Dictionary) -> void:
	var players: Array = []
	for raw_entry in reveal.get("players", []):
		var entry: Dictionary = raw_entry
		var label := lobby.label_for(int(entry.get("peer_id", 0)))
		if label.is_empty():
			label = "(saiu)"
		players.append({"label": label, "role": str(entry.get("role", ""))})
	last_result = {
		"round_id": int(reveal.get("round_id", 0)),
		"winner": str(reveal.get("winner", "")),
		"reason": str(reveal.get("reason", "")),
		"players": players,
	}

## DTO público da sala, igual para todos os membros. Sem papel (o resultado
## só existe depois do fim da rodada), sem posição, sem inventário.
func public_state(now_msec: int) -> Dictionary:
	var players: Array = []
	for entry in lobby.public_entries():
		var peer_id := int(entry["peer_id"])
		players.append({
			"peer_id": peer_id,
			"label": str(entry["label"]),
			"appearance": str(entry["appearance"]),
			"ready": round_authority.is_ready(peer_id),
			"host": peer_id == host_peer_id,
		})
	return {
		"code": code,
		"phase": phase(),
		"round_id": round_authority.round_id,
		"countdown_msec": round_authority.countdown_remaining_msec(now_msec),
		"min_players": RoundRules.MIN_PLAYERS,
		"max_players": RoundRules.MAX_PLAYERS,
		"players": players,
		"ready_count": round_authority.ready_count(),
		"result": last_result.duplicate(true),
	}

## "" se a sala deve continuar; senão o motivo da destruição. Sala vazia sai
## depois da carência; lobby parado expira; rodada em andamento com gente
## conectada nunca expira por inatividade.
func destroy_reason(now_msec: int, empty_grace_msec: int, lobby_idle_msec: int) -> String:
	if lobby.is_empty():
		return "empty" if now_msec - empty_since_msec >= empty_grace_msec else ""
	var in_lobby := round_authority.state == RoundState.WAITING or round_authority.state == RoundState.COUNTDOWN
	if in_lobby and now_msec - last_activity_msec >= lobby_idle_msec:
		return "idle"
	return ""

## Encerramento: apaga tudo desta sala.
func clear() -> void:
	combat.clear_round()
	round_authority.clear()
	world.clear()
	bodies.clear()
	lobby.clear()
	last_result.clear()
	host_peer_id = 0

static func _public_reason(reason: String) -> String:
	match reason:
		"room_unavailable": return "room_full"
		"name_taken": return "name_taken"
	return "invalid_name"
