class_name AuthoritativeWorld
extends RefCounted

## Estado oficial de movimento e mira (protocolo 9). Cada jogador tem uma
## fila de comandos de um tick. O servidor consome um por tick (até
## `MAX_SIMULATED_PER_TICK` quando a fila passa do alvo), dentro de um
## orçamento que cresce um tick por tick real: mandar mais pacotes ou dt maior
## não dá mais tempo de simulação. Sem comando na fila, o jogador não anda.
##
## `last_resolved` é o ACK cumulativo: todo comando com sequência ≤ ele foi
## aplicado, recusado ou declarado perdido (lacuna, fila cheia). A época de
## controle muda na entrada da rodada, na eliminação e em reposicionamento;
## comando de época antiga é recusado sem efeito.

var states: Dictionary = {}
var occupied_spawns: Dictionary = {}
## Contagem de recusas por motivo (instrumentação; sem dados de papel).
var rejection_counts: Dictionary = {}

func add_player(peer_id: int) -> Dictionary:
	var spawn_index := _first_free_spawn()
	if spawn_index < 0:
		return {}
	occupied_spawns[spawn_index] = peer_id
	var spawn := MovementRules.SPAWN_POINTS[spawn_index]
	var state := {
		"position": spawn,
		"spawn_position": spawn,
		"velocity": Vector3.ZERO,
		"yaw": MansionMap.spawn_yaw_at(spawn_index),
		"pitch": 0.0,
		"yaw_tokens": MovementRules.MAX_YAW_DELTA * 2.0,
		"pitch_tokens": MovementRules.MAX_PITCH_DELTA * 2.0,
		"epoch": 1,
		"last_received": 0,
		"last_resolved": 0,
		"queue": [],
		"budget": float(NetSync.MAX_BUDGET_TICKS),
		"packet_tokens": NetSync.PACKET_BURST,
		"last_packet_msec": -1,
		"spawn_index": spawn_index,
		"movement_logged": false,
		"simulated_commands": 0,
	}
	states[peer_id] = state
	return state

func remove_player(peer_id: int) -> void:
	if not states.has(peer_id):
		return
	occupied_spawns.erase(int(states[peer_id]["spawn_index"]))
	states.erase(peer_id)

func clear() -> void:
	states.clear()
	occupied_spawns.clear()

## Nova época: o que estava na fila passa a ser recusado quando chegar a vez
## (com resultado explícito para as ações) e a velocidade zera.
func bump_epoch(peer_id: int) -> int:
	if not states.has(peer_id):
		return 0
	var state: Dictionary = states[peer_id]
	state["epoch"] = int(state["epoch"]) + 1
	state["velocity"] = Vector3.ZERO
	return int(state["epoch"])

## Reposicionamento oficial (teste ou regra futura): descontinuidade explícita.
func teleport(peer_id: int, position: Vector3, yaw: Variant = null, pitch: Variant = null) -> void:
	if not states.has(peer_id):
		return
	var state: Dictionary = states[peer_id]
	state["position"] = position
	if yaw != null:
		state["yaw"] = wrapf(float(yaw), -PI, PI)
	if pitch != null:
		state["pitch"] = MovementRules.clamp_pitch(pitch)
	bump_epoch(peer_id)

## Recebe um pacote já com remetente derivado da conexão. Devolve o motivo de
## recusa do pacote inteiro (vazio se aceito) e as ações que já ficaram sem
## execução (comando descartado por fila cheia), para resultado explícito.
func receive_commands(peer_id: int, payload: Variant, now_msec: int) -> Dictionary:
	if not states.has(peer_id):
		return {"reason": "unknown_peer", "dropped_actions": []}
	var state: Dictionary = states[peer_id]
	var last_packet := int(state["last_packet_msec"])
	var elapsed := clampf(float(now_msec - last_packet) / 1000.0, 0.0, 1.0) if last_packet >= 0 else 1.0
	state["last_packet_msec"] = now_msec
	state["packet_tokens"] = minf(NetSync.PACKET_BURST, float(state["packet_tokens"]) + elapsed * NetSync.MAX_PACKET_RATE)
	if float(state["packet_tokens"]) < 1.0:
		return _packet_rejected("packet_rate")
	state["packet_tokens"] = float(state["packet_tokens"]) - 1.0
	var packet := NetSync.parse_packet(payload)
	if not str(packet["reason"]).is_empty():
		return _packet_rejected(str(packet["reason"]))
	var first_seq := int(packet["first_seq"])
	var commands: Array = packet["commands"]
	var dropped_actions: Array = []
	var queued := 0
	var duplicates := 0
	for index in commands.size():
		var seq := first_seq + index
		if seq <= int(state["last_received"]):
			duplicates += 1
			continue
		if seq - int(state["last_received"]) > NetSync.MAX_SEQUENCE_ADVANCE:
			_count("sequence_jump")
			return {"reason": "sequence_jump", "dropped_actions": dropped_actions, "queued": queued, "duplicates": duplicates}
		var command: Dictionary = commands[index]
		state["last_received"] = seq
		if (state["queue"] as Array).size() >= NetSync.MAX_QUEUE_COMMANDS:
			_count("queue_full")
			if not (command["action"] as Dictionary).is_empty():
				dropped_actions.append({"action": command["action"], "reason": "queue_full"})
			continue
		command["seq"] = seq
		command["epoch"] = int(packet["epoch"])
		(state["queue"] as Array).append(command)
		queued += 1
	if duplicates > 0:
		_count("duplicate", duplicates)
	return {"reason": "", "dropped_actions": dropped_actions, "queued": queued, "duplicates": duplicates}

func _packet_rejected(reason: String) -> Dictionary:
	_count(reason)
	return {"reason": reason, "dropped_actions": []}

## Um tick oficial. `gate(peer_id)` diz se o jogador pode agir agora (vazio) ou
## por que não; `run_action(peer_id, action, seq)` executa a ação no ponto
## causal (mira do comando já aplicada, movimento do tick ainda não);
## `reject(peer_id, seq, action, reason)` recebe cada recusa de comando.
func step(gate: Callable, run_action: Callable, reject: Callable) -> void:
	for peer_id in states.keys():
		if not states.has(peer_id):
			continue
		var state: Dictionary = states[peer_id]
		state["budget"] = minf(float(NetSync.MAX_BUDGET_TICKS), float(state["budget"]) + 1.0)
		var queue: Array = state["queue"]
		var allowed := _allowed_this_tick(state)
		var simulated := 0
		var examined := 0
		while not queue.is_empty() and simulated < allowed and examined < NetSync.MAX_QUEUE_COMMANDS \
				and float(state["budget"]) >= 1.0 and states.has(peer_id):
			var command: Dictionary = queue.pop_front()
			examined += 1
			state["last_resolved"] = int(command["seq"])
			var action: Dictionary = command["action"]
			# Primeiro o motivo de regra (rodada, participação, vida), que é o mais
			# informativo; depois a época. Os dois recusam sem efeito algum.
			var gate_reason := str(gate.call(int(peer_id)))
			if not gate_reason.is_empty():
				_reject(reject, int(peer_id), command, gate_reason)
				continue
			if int(command["epoch"]) != int(state["epoch"]):
				_reject(reject, int(peer_id), command, "stale_epoch")
				continue
			var reason := MovementRules.command_rejection(state, command["move"], float(command["yaw_delta"]), float(command["pitch_delta"]))
			state["budget"] = float(state["budget"]) - 1.0
			simulated += 1
			if not reason.is_empty():
				_reject(reject, int(peer_id), command, reason)
				continue
			MovementRules.apply_look(state, float(command["yaw_delta"]), float(command["pitch_delta"]))
			if not action.is_empty():
				run_action.call(int(peer_id), action, int(command["seq"]))
				# A ação pode ter eliminado alguém (inclusive mudado a época deste
				# jogador); o movimento do tick só segue na mesma época.
				if not states.has(peer_id) or int(state["epoch"]) != int(command["epoch"]):
					continue
			MovementRules.step_movement(state, command["move"], NetSync.TICK_SECONDS)
			state["simulated_commands"] = int(state["simulated_commands"]) + 1
		# Fila vazia: comandos descartados (fila cheia) já estão resolvidos.
		if states.has(peer_id) and queue.is_empty() and int(state["last_resolved"]) < int(state["last_received"]):
			state["last_resolved"] = int(state["last_received"])

## Quantos comandos simular neste tick (ver `NetSync.CATCH_UP_WINDOW_TICKS`).
func _allowed_this_tick(state: Dictionary) -> int:
	var depth := (state["queue"] as Array).size()
	state["queue_min"] = mini(int(state.get("queue_min", depth)), depth)
	state["queue_window"] = int(state.get("queue_window", 0)) + 1
	if int(state["queue_window"]) >= NetSync.CATCH_UP_WINDOW_TICKS:
		state["catch_up"] = int(state["queue_min"]) > NetSync.TARGET_QUEUE_COMMANDS
		state["queue_min"] = depth
		state["queue_window"] = 0
	if depth > NetSync.OVERLOAD_QUEUE_COMMANDS:
		return NetSync.MAX_SIMULATED_PER_TICK
	return 2 if bool(state.get("catch_up", false)) else 1

func _reject(reject: Callable, peer_id: int, command: Dictionary, reason: String) -> void:
	_count(reason)
	reject.call(peer_id, int(command["seq"]), command["action"], reason)

func _count(reason: String, amount: int = 1) -> void:
	rejection_counts[reason] = int(rejection_counts.get(reason, 0)) + amount

## Estados públicos (mesmo conteúdo para todos): sem fila, baldes ou ACK.
func snapshot() -> Array:
	var result: Array = []
	for peer_id in states:
		result.append(MovementRules.snapshot_state(int(peer_id), states[peer_id]))
	return result

## ACK privado do dono: último comando resolvido, época e baldes de mira
## oficiais daquele ponto (o necessário para o replay exato).
func ack_for(peer_id: int) -> Dictionary:
	if not states.has(peer_id):
		return {}
	var state: Dictionary = states[peer_id]
	return {"seq": int(state["last_resolved"]), "epoch": int(state["epoch"]),
		"yaw_tokens": float(state["yaw_tokens"]), "pitch_tokens": float(state["pitch_tokens"])}

func has_moved(peer_id: int) -> bool:
	if not states.has(peer_id):
		return false
	var state: Dictionary = states[peer_id]
	return (state["position"] as Vector3).distance_to(state["spawn_position"]) >= MovementRules.TEST_MOVEMENT_DISTANCE

func all_positions_distinct(peer_ids: Array) -> bool:
	var positions: Dictionary = {}
	for peer_id in peer_ids:
		if not states.has(peer_id):
			return false
		var position: Vector3 = states[peer_id]["position"]
		var key := "%0.3f,%0.3f" % [position.x, position.z]
		positions[key] = true
	return positions.size() == peer_ids.size()

func _first_free_spawn() -> int:
	for index in MovementRules.SPAWN_POINTS.size():
		if not occupied_spawns.has(index):
			return index
	return -1
