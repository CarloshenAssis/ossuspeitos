extends Node

## Fase 9: coordenador do teste de salas online (só no servidor de teste,
## `--rooms-test`). Não cria sala nem marca PRONTO: isso vem dos clientes reais.
## Em cada sala que chega a ACTIVE, elimina jogadores pela API interna do
## servidor (a mesma que o combate usa) para fechar a rodada sem roteiro de
## tiros, e confere que nada de uma sala aparece em outra.
##
## Rodada ímpar: uma vítima cai e depois o assassino (inocentes vencem).
## Rodada par: todos os inocentes caem (assassino vence).
##
## Encerra (handshake de encerramento) quando alguma sala completou
## `--rooms-target-rounds` rodadas e voltou ao lobby, e o servidor tem
## exatamente `--rooms-expect-peers` conexões, todas dentro de salas.

const DEFAULT_STEP_GAP_MSEC := 700

var app: Node
var target_rounds := 2
var step_gap_msec := DEFAULT_STEP_GAP_MSEC
var expect_peers := 0
var active_since: Dictionary = {}
var steps_done: Dictionary = {}
var completed_rounds: Dictionary = {}
var failures := 0
var finished := false
var last_wait_log_msec := 0

func _ready() -> void:
	app = get_parent()
	target_rounds = NetworkConfig.integer_argument(app.arguments, "rooms-target-rounds", 2)
	expect_peers = NetworkConfig.integer_argument(app.arguments, "rooms-expect-peers", 0)
	step_gap_msec = NetworkConfig.integer_argument(app.arguments, "rooms-step-gap-msec", DEFAULT_STEP_GAP_MSEC)
	print("ROOMS_TEST_START target_rounds=%d expect_peers=%d" % [target_rounds, expect_peers])

func _process(_delta: float) -> void:
	if app.mode != "server" or finished or app.shutting_down or app.room_registry == null:
		return
	var now := Time.get_ticks_msec()
	for raw_room in app.room_registry.rooms.values():
		var room: MatchRoom = raw_room
		_drive_room(room, now)
	_check_isolation()
	_maybe_finish(now)

## "sala:rodada" -> PRONTO no instante em que a sala voltou ao lobby.
var ready_at_reset_by_key: Dictionary = {}
var watched_rooms: Dictionary = {}

func _watch_room(room: MatchRoom) -> void:
	if watched_rooms.has(room.room_id):
		return
	watched_rooms[room.room_id] = true
	var ra := room.round_authority
	var last := {"state": ra.state}
	# Só ENDED -> WAITING é fim de rodada (contagem cancelada também volta a
	# WAITING, sem rodada jogada).
	ra.state_changed.connect(func(state: int, round_id: int):
		if state == RoundState.WAITING and int(last["state"]) == RoundState.ENDED:
			ready_at_reset_by_key["%d:%d" % [room.room_id, round_id]] = ra.ready_count()
		last["state"] = state)

func _drive_room(room: MatchRoom, now: int) -> void:
	_watch_room(room)
	var ra := room.round_authority
	var key := "%d:%d" % [room.room_id, ra.round_id]
	if ra.state != RoundState.ACTIVE or room.combat.active_round_id <= 0:
		if ready_at_reset_by_key.has(key) and not completed_rounds.has(key):
			completed_rounds[key] = true
			var count := _completed_for(room.room_id)
			# PRONTO medido no instante da volta ao lobby (sinal), não agora: um
			# cliente com PRONTO automático já pode ter marcado de novo.
			var ready_at_reset := int(ready_at_reset_by_key.get(key, -1))
			print("ROOMS_TEST_ROUND_DONE room=%d round_id=%d completed=%d ready=%d players=%d result=%s" % [
				room.room_id, ra.round_id, count, ready_at_reset, room.member_count(), str(not room.last_result.is_empty())])
			if ready_at_reset != 0:
				_fail("ready_not_reset room=%d ready=%d" % [room.room_id, ready_at_reset])
		return
	if not active_since.has(key):
		active_since[key] = now
		steps_done[key] = 0
		print("ROOMS_TEST_ROUND_ACTIVE room=%d round_id=%d participants=%d" % [room.room_id, ra.round_id, ra.participants.size()])
		_check_round_reset(room)
		_disturb_round(room)
		_official_pickup(room)
	var step := int(steps_done[key])
	if now - int(active_since[key]) < step_gap_msec * (step + 1):
		return
	var assassin := 0
	var innocents: Array = []
	for raw_peer in ra.participants.keys():
		var peer := int(raw_peer)
		if not ra.is_alive(peer):
			continue
		if ra.get_role_for_peer(peer) == Role.ASSASSIN:
			assassin = peer
		else:
			innocents.append(peer)
	innocents.sort()
	var target := 0
	var instigator := 0
	if ra.round_id % 2 == 1:
		# Inocentes vencem: primeiro uma vítima (pelo assassino), depois o assassino.
		if step == 0:
			for peer in innocents:
				if ra.get_role_for_peer(int(peer)) == Role.VICTIM:
					target = int(peer)
					break
			instigator = assassin
		else:
			target = assassin
			instigator = int(innocents[0]) if not innocents.is_empty() else 0
	else:
		if not innocents.is_empty():
			target = int(innocents[0])
			instigator = assassin
	steps_done[key] = step + 1
	if target == 0:
		return
	var reason := ra.eliminate_player(target, "shot", instigator, now)
	if not reason.is_empty():
		_fail("eliminate room=%d peer=%d reason=%s" % [room.room_id, target, reason])
		return
	print("ROOMS_TEST_ELIMINATED room=%d round_id=%d peer=%d" % [room.room_id, ra.round_id, target])
	# O mesmo sinal que o combate emite: corpo e aviso público só nesta sala.
	room.combat.player_eliminated.emit(target, instigator)

## Fase 10: começo de rodada = todos os participantes (vivos ou eliminados
## na rodada anterior) no ponto inicial oficial com época nova, sem corpos,
## sem espectador e com todos os itens de volta ao chão.
var last_epoch_by_peer: Dictionary = {}

func _check_round_reset(room: MatchRoom) -> void:
	var ra := room.round_authority
	var off_spawn := 0
	var stale_epoch := 0
	for raw_peer in ra.participants.keys():
		var peer := int(raw_peer)
		var state: Dictionary = room.world.states.get(peer, {})
		if state.is_empty():
			continue
		var spawn: Vector3 = MovementRules.SPAWN_POINTS[int(state["spawn_index"])]
		var position: Vector3 = state["position"]
		if Vector2(position.x - spawn.x, position.z - spawn.z).length() > 0.05:
			off_spawn += 1
		if last_epoch_by_peer.has(peer) and int(state["epoch"]) <= int(last_epoch_by_peer[peer]):
			stale_epoch += 1
		last_epoch_by_peer[peer] = int(state["epoch"])
		if not ra.get_spectator_state(peer).is_empty():
			_fail("spectator_after_reset room=%d peer=%d" % [room.room_id, peer])
			return
	var unavailable := 0
	for pickup in room.combat.public_pickups():
		if not bool(pickup["available"]) or int(pickup["round_id"]) != ra.round_id:
			unavailable += 1
	print("ROOMS_TEST_RESET room=%d round_id=%d off_spawn=%d stale_epoch=%d bodies=%d pickups_missing=%d" % [
		room.room_id, ra.round_id, off_spawn, stale_epoch, room.bodies.size(), unavailable])
	if off_spawn > 0 or stale_epoch > 0 or room.bodies.size() > 0 or unavailable > 0:
		_fail("round_reset room=%d round_id=%d off_spawn=%d stale_epoch=%d bodies=%d pickups_missing=%d" % [
			room.room_id, ra.round_id, off_spawn, stale_epoch, room.bodies.size(), unavailable])

## Tira todos do ponto inicial (como se tivessem andado: vão para o ponto de
## outro jogador) e some com um item, para a próxima rodada provar o reset.
func _disturb_round(room: MatchRoom) -> void:
	var count := MovementRules.SPAWN_POINTS.size()
	for raw_peer in room.round_authority.participants.keys():
		var state: Dictionary = room.world.states.get(int(raw_peer), {})
		if not state.is_empty():
			state["position"] = MovementRules.SPAWN_POINTS[(int(state["spawn_index"]) + 1) % count]
	for item in room.combat.inventory.ground_items.values():
		item["available"] = false
		break

## Fase 11: uma coleta oficial (pela API de combate, com a posição oficial no
## item) para a sala ter alguém publicamente armado; o teste confere que só os
## clientes desta sala veem essa pistola.
func _official_pickup(room: MatchRoom) -> void:
	var participants := room.round_authority.participants.keys()
	if participants.is_empty():
		return
	participants.sort()
	var peer := int(participants[0])
	# Um item ainda disponível (o `_disturb_round` acabou de sumir com o primeiro).
	var index := -1
	for candidate in MansionMap.PICKUPS.size():
		var item: Dictionary = room.combat.inventory.ground_items.get(str(MansionMap.PICKUPS[candidate]["id"]), {})
		if str(MansionMap.PICKUPS[candidate]["type"]) == "weapon" and bool(item.get("available", false)):
			index = candidate
			break
	if index < 0:
		_fail("official_pickup room=%d reason=no_weapon_left" % room.room_id)
		return
	room.world.states[peer]["position"] = ArenaRules.PICKUP_POSITIONS[index]
	var result := room.combat.request_pickup(peer, str(MansionMap.PICKUPS[index]["id"]), 1, Time.get_ticks_msec())
	print("ROOMS_TEST_PICKUP room=%d round_id=%d peer=%d accepted=%s" % [room.room_id, room.round_authority.round_id, peer, str(result.get("accepted", false))])
	if not bool(result.get("accepted", false)):
		_fail("official_pickup room=%d reason=%s" % [room.room_id, str(result.get("reason", ""))])

func _completed_for(room_id: int) -> int:
	var total := 0
	for key in completed_rounds.keys():
		if str(key).begins_with("%d:" % room_id):
			total += 1
	return total

## Estado oficial: nenhum peer em duas salas, vínculo peer -> sala coerente,
## corpos e rodadas de uma sala sem peers de outra.
func _check_isolation() -> void:
	var owner: Dictionary = {}
	for raw_room in app.room_registry.rooms.values():
		var room: MatchRoom = raw_room
		for raw_peer in room.lobby.peer_ids():
			var peer := int(raw_peer)
			if owner.has(peer):
				_fail("peer_in_two_rooms peer=%d rooms=%d,%d" % [peer, int(owner[peer]), room.room_id])
				return
			owner[peer] = room.room_id
			var bound: MatchRoom = app.room_registry.room_of(peer)
			if bound == null or bound.room_id != room.room_id:
				_fail("binding_mismatch peer=%d room=%d" % [peer, room.room_id])
				return
		for raw_peer in room.round_authority.participants.keys():
			if not room.lobby.has(int(raw_peer)) and owner.has(int(raw_peer)) and int(owner[int(raw_peer)]) != room.room_id:
				_fail("foreign_participant peer=%d room=%d" % [int(raw_peer), room.room_id])
				return
		for raw_peer in room.world.states.keys():
			if not room.lobby.has(int(raw_peer)):
				_fail("foreign_world_state peer=%d room=%d" % [int(raw_peer), room.room_id])
				return

func _maybe_finish(now: int) -> void:
	var best := 0
	var playing := false
	for raw_room in app.room_registry.rooms.values():
		var room: MatchRoom = raw_room
		best = maxi(best, _completed_for(room.room_id))
		if room.round_authority.state != RoundState.WAITING:
			playing = true
	var in_rooms: int = app.room_registry.total_members()
	var hall: int = app.hall_peers.size()
	var ready := best >= target_rounds and not playing and hall == expect_peers and in_rooms == hall
	if not ready:
		if now - last_wait_log_msec >= 5000:
			last_wait_log_msec = now
			print("ROOMS_TEST_WAIT completed=%d playing=%s hall=%d in_rooms=%d rooms=%d" % [
				best, str(playing), hall, in_rooms, app.room_registry.room_count()])
		return
	finished = true
	for raw_room in app.room_registry.rooms.values():
		var room: MatchRoom = raw_room
		print("ROOMS_TEST_ROOM room=%d code=%s phase=%s round_id=%d players=%d ready=%d host=%d bodies=%d" % [
			room.room_id, room.code, room.phase(), room.round_authority.round_id, room.member_count(),
			room.round_authority.ready_count(), room.host_peer_id, room.bodies.size()])
	print("ROOMS_TEST_OK rooms=%d peers=%d completed=%d failures=%d" % [app.room_registry.room_count(), hall, best, failures])
	app._begin_server_shutdown(app._session_peers())

func _fail(message: String) -> void:
	failures += 1
	push_error("ROOMS_TEST_FAILED %s" % message)
	print("ROOMS_TEST_FAILED %s" % message)
	finished = true
	app.get_tree().quit(1)

# Ganchos que a NetworkApp chama em qualquer coordenador de teste.
func observe_join_refused(_peer_id: int, _reason: String) -> void: pass
func observe_server_action(_peer_id: int, _action: String, _sequence: Variant, _result: Dictionary) -> void: pass
func observe_client_event(_kind: String, _payload: Variant = null) -> void: pass
func observe_private_emission(_peer_id: int, _state: Dictionary) -> void: pass
func observe_server_shot(_event: Dictionary) -> void: pass
func observe_server_elimination(_peer_id: int) -> void: pass
func observe_server_body(_dto: Dictionary) -> void: pass
func cancel_pending(_reason: String) -> void: pass
