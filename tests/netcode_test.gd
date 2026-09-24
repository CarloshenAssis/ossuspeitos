extends SceneTree

## Fase 4, camada A: algoritmos e contrato do protocolo 9, sem rede real.
## Servidor (`AuthoritativeWorld` + `CombatAuthority`) e cliente
## (`PlayerPrediction`, `RemoteInterpolator`, `ArenaView`) conversam por um laço
## em processo com filas FIFO atrasadas (perfis de 0, 80 e 150 ms com jitter e
## seed), o mesmo contrato de pacotes do fio.

const LOCAL := 1
const TARGET := 2
const DT := 1.0 / 60.0

var failures := 0
var checks := 0
var _arena: ArenaView
var _frame := 0
var _report: Array = []

func _initialize() -> void:
	_test_same_input_same_state()
	_test_partial_ack_and_replay()
	_test_rejected_command_is_retired()
	_test_duplicates_gaps_and_old_acks()
	_test_limits_and_abuse()
	_test_time_budget()
	_test_pitch_clamp_and_yaw_wrap()
	_test_replay_has_no_side_effects()
	_test_fire_causal_order()
	_test_fire_dependency_rejections()
	_test_action_idempotence()
	_test_epochs_elimination_and_reset()
	_test_snapshot_filter()
	_test_interpolation()
	_test_correction_smoothing()
	for profile in ["local", "rtt80", "rtt150j"]:
		_test_convergence_under_delay(profile, 7)
	_arena = ArenaView.new()
	_arena.local_peer_id = LOCAL
	root.add_child(_arena)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_test_camera_uses_local_look_immediately()
	_test_spectator_uses_interpolated_target()
	for line in _report:
		print(line)
	if failures > 0:
		push_error("NETCODE_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
	else:
		print("NETCODE_TEST_OK checks=%d" % checks)
		quit(0)
	return true

# --- Laço cliente/servidor em processo ----------------------------------------

## Um servidor com um jogador e um cliente previsor, ligados por filas com
## atraso (em ticks) que preservam a ordem, como o fluxo WebSocket.
class Loop:
	var world := AuthoritativeWorld.new()
	var client := PlayerPrediction.new()
	var up: Array = []
	var down: Array = []
	var outbox: Array = []
	var tick := 0
	var up_ticks := 0
	var down_ticks := 0
	var jitter_ticks := 0
	var rng := RandomNumberGenerator.new()
	var last_up := 0
	var last_down := 0
	var rejections: Array = []
	var actions: Array = []
	var gate_reason := ""
	var action_runner: Callable

	func _init(profile: String, seed_value: int) -> void:
		rng.seed = seed_value
		match profile:
			"rtt80": up_ticks = 2; down_ticks = 3
			"rtt150j": up_ticks = 4; down_ticks = 4; jitter_ticks = 2
		world.add_player(LOCAL)

	func _delay(base: int, last: int) -> int:
		return maxi(last, tick + base + (rng.randi_range(0, jitter_ticks) if jitter_ticks > 0 else 0))

	func flush() -> void:
		if outbox.is_empty():
			return
		var encoded: Array = []
		for command in outbox:
			encoded.append(NetSync.encode_command(command["move"], float(command["yaw_delta"]), float(command["pitch_delta"]), NetSync.encode_action(command["action"])))
		last_up = _delay(up_ticks, last_up)
		up.append([last_up, NetSync.encode_packet(int(outbox[0]["epoch"]), int(outbox[0]["seq"]), encoded)])
		outbox.clear()

	## Um tick: cliente comanda (se tem estado), servidor processa o que chegou e
	## publica a cada 3 ticks, cliente reconcilia o que chegou.
	func step(move: Vector2, look: Vector2 = Vector2.ZERO, action: Dictionary = {}) -> void:
		if client.has_state:
			if look != Vector2.ZERO:
				client.add_look(look.x, look.y)
			if not action.is_empty():
				client.queue_action(action)
			outbox.append(client.build_command(move))
			if tick % NetSync.SEND_INTERVAL_TICKS == 0 or not action.is_empty():
				flush()
		while not up.is_empty() and int(up[0][0]) <= tick:
			world.receive_commands(LOCAL, up.pop_front()[1], tick * 16)
		world.step(func(_peer): return gate_reason, _run_action, func(peer, seq, act, reason): rejections.append({"seq": seq, "action": act, "reason": reason}))
		if tick % NetSync.SNAPSHOT_INTERVAL_TICKS == 0:
			last_down = _delay(down_ticks, last_down)
			down.append([last_down, {"tick": tick, "players": world.snapshot(), "ack": world.ack_for(LOCAL)}])
		while not down.is_empty() and int(down[0][0]) <= tick:
			var snapshot: Dictionary = down.pop_front()[1]
			for player in snapshot["players"]:
				if int(player["peer_id"]) == LOCAL:
					client.reconcile(snapshot["ack"], player)
		tick += 1

	func _run_action(peer_id: int, action: Dictionary, seq: int) -> void:
		actions.append({"peer": peer_id, "action": action, "seq": seq})
		if action_runner.is_valid():
			action_runner.call(peer_id, action, seq)

	## Pacote montado à mão (hostil ou inválido), na ordem do fluxo: antes, o
	## que o cliente já formou sai; depois, sequências novas.
	func inject(epoch: int, commands: Array) -> int:
		flush()
		var seq := client.next_seq
		client.next_seq += commands.size()
		last_up = _delay(up_ticks, last_up)
		up.append([last_up, NetSync.encode_packet(epoch, seq, commands)])
		return seq

	func settle(ticks: int = 40) -> void:
		for i in ticks:
			step(Vector2.ZERO)

	func official() -> Dictionary:
		return world.states[LOCAL]

## Entradas de teste determinísticas por seed: anda, gira e para.
func _input_script(seed_value: int, length: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var inputs: Array = []
	var move := Vector2.ZERO
	for i in length:
		if i % 20 == 0:
			move = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1.0)
		inputs.append({"move": move, "look": Vector2(rng.randf_range(-0.03, 0.03), rng.randf_range(-0.02, 0.02))})
	return inputs

# --- Determinismo e ACK -------------------------------------------------------

func _test_same_input_same_state() -> void:
	for profile in ["local", "rtt150j"]:
		var loop := Loop.new(profile, 3)
		loop.world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0))
		loop.settle(20)
		_expect(loop.client.has_state, "%s: the client adopts the official state from the first ACK" % profile)
		for input in _input_script(11, 240):
			loop.step(input["move"], input["look"])
		loop.settle(60)
		var official := loop.official()
		var predicted := loop.client.state
		_expect((official["position"] as Vector3).distance_to(predicted["position"]) < 0.001,
			"%s: same inputs give the same position (%s vs %s)" % [profile, str(official["position"]), str(predicted["position"])])
		_expect(absf(angle_difference(float(official["yaw"]), float(predicted["yaw"]))) < 1e-6 and absf(float(official["pitch"]) - float(predicted["pitch"])) < 1e-6,
			"%s: same inputs give the same orientation" % profile)
		_expect((official["velocity"] as Vector3).distance_to(predicted["velocity"]) < 0.001, "%s: same inputs give the same velocity" % profile)
		var worst := 0.0
		for value in loop.client.ack_errors_position: worst = maxf(worst, float(value))
		_expect(worst < 0.001, "%s: the prediction matched the server at every ACK (worst %.6f m)" % [profile, worst])
		# Cada comando resolvido foi exatamente um tick simulado (nenhum
		# recusado aqui); os últimos ainda em trânsito ficam para depois.
		var resolved := int(loop.world.states[LOCAL]["last_resolved"])
		_expect(int(loop.world.states[LOCAL]["simulated_commands"]) == resolved and resolved >= loop.client.next_seq - 12,
			"%s: each resolved command is exactly one server tick (%d resolved, %d simulated, %d sent)" % [profile, resolved, int(loop.world.states[LOCAL]["simulated_commands"]), loop.client.next_seq - 1])
		_report.append("NETCODE_DETERMINISM profile=%s commands=%d ack_samples=%d worst_ack_error_m=%.6f" % [profile, loop.client.next_seq - 1, loop.client.ack_errors_position.size(), worst])

func _test_partial_ack_and_replay() -> void:
	var loop := Loop.new("local", 1)
	loop.world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0))
	loop.settle(6)
	# Servidor atrasa: nada chega por 20 ticks; o cliente acumula pendentes.
	loop.up_ticks = 20
	for i in 30:
		loop.step(Vector2(0, -1))
	var before_ack := loop.client.last_ack
	var pending_before := loop.client.pending.size()
	_expect(pending_before >= 20, "commands stay pending while the server has not resolved them (%d)" % pending_before)
	loop.up_ticks = 0
	loop.step(Vector2(0, -1))
	loop.step(Vector2(0, -1))
	loop.step(Vector2(0, -1))
	_expect(loop.client.last_ack > before_ack and loop.client.last_ack < loop.client.next_seq - 1,
		"a partial ACK resolves only a prefix (ack %d, sent %d)" % [loop.client.last_ack, loop.client.next_seq - 1])
	for command in loop.client.pending:
		_expect(int(command["seq"]) > loop.client.last_ack, "only commands after the ACK stay pending")
	# O atraso acumulado drena aos poucos (alcance limitado); em repouso os
	# dois lados chegam ao mesmo ponto.
	loop.settle(150)
	_expect((loop.official()["position"] as Vector3).distance_to(loop.client.state["position"]) < 0.001, "after the partial ACKs the replay converges on the official state")

func _test_rejected_command_is_retired() -> void:
	var loop := Loop.new("rtt80", 2)
	loop.world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0))
	loop.settle(10)
	# Comando impossível injetado no fio (o cliente honesto nunca o forma).
	var seq := loop.inject(loop.client.epoch, [[5.0, 0.0, 0.0, 0.0, ["fire", 1]]])
	loop.settle(20)
	var found := false
	for rejection in loop.rejections:
		if int(rejection["seq"]) == seq and str(rejection["reason"]) == "move_magnitude":
			found = true
	_expect(found, "the server rejects the impossible command explicitly")
	_expect(loop.client.last_ack >= seq, "the rejected command is covered by the cumulative ACK and never replayed")
	_expect(loop.actions.is_empty(), "the action inside a rejected command never runs")

func _test_duplicates_gaps_and_old_acks() -> void:
	var world := AuthoritativeWorld.new()
	world.add_player(LOCAL)
	world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0))
	var epoch := int(world.states[LOCAL]["epoch"])
	var packet := NetSync.encode_packet(epoch, 1, [[0.0, -1.0, 0.0, 0.0, []], [0.0, -1.0, 0.0, 0.0, []]])
	_expect(world.receive_commands(LOCAL, packet, 100)["queued"] == 2, "a valid packet queues its commands")
	var again := world.receive_commands(LOCAL, packet, 200)
	_expect(again["queued"] == 0 and again["duplicates"] == 2, "a duplicated packet is idempotent")
	_step(world, 6)
	var moved: Vector3 = world.states[LOCAL]["position"]
	_expect(int(world.states[LOCAL]["simulated_commands"]) == 2, "duplicates are never simulated twice")
	# Lacuna: 3..5 perdidos, 6 chega. O ACK cumulativo cobre a lacuna.
	world.receive_commands(LOCAL, NetSync.encode_packet(epoch, 6, [[0.0, 0.0, 0.0, 0.0, []]]), 300)
	_step(world, 4)
	_expect(int(world.states[LOCAL]["last_resolved"]) == 6, "a gap is resolved as lost by the cumulative ACK")
	_expect((world.states[LOCAL]["position"] as Vector3).distance_to(moved) < 0.2, "lost commands are not invented")
	# Cliente: ACK antigo ou repetido não retrocede nada.
	var prediction := PlayerPrediction.new()
	var player := MovementRules.snapshot_state(LOCAL, world.states[LOCAL])
	prediction.reconcile(world.ack_for(LOCAL), player)
	var ack_now := prediction.last_ack
	var stale := world.ack_for(LOCAL).duplicate()
	stale["seq"] = ack_now - 3
	_expect(prediction.reconcile(stale, player).has("stale"), "an older ACK is ignored")
	_expect(prediction.last_ack == ack_now, "an old ACK never moves the acknowledged sequence back")

func _test_limits_and_abuse() -> void:
	var world := AuthoritativeWorld.new()
	world.add_player(LOCAL)
	var epoch := int(world.states[LOCAL]["epoch"])
	var cases := [
		[null, "malformed"], ["text", "malformed"], [[epoch, 1], "malformed"], [[epoch, "1", []], "malformed"],
		[[epoch, 1, []], "empty_batch"], [[epoch, 0, [[0.0, 0.0, 0.0, 0.0, []]]], "invalid_sequence"],
		[[epoch, 1, [[0.0, 0.0, 0.0, []]]], "malformed"], [[epoch, 1, [["a", 0.0, 0.0, 0.0, []]]], "malformed"],
		[[epoch, 1, [[0.0, 0.0, 0.0, 0.0, ["teleport", 1]]]], "malformed_action"],
		[[epoch, 1, [[0.0, 0.0, 0.0, 0.0, ["fire", 1.0]]]], "malformed_action"],
		[[epoch, 1, [[0.0, 0.0, 0.0, 0.0, ["fire", 1, Vector3.ZERO, Vector3.FORWARD]]]], "malformed_action"],
		[[epoch, 1, [[0.0, 0.0, 0.0, 0.0, ["pickup", 1, "x".repeat(100)]]]], "malformed_action"],
	]
	var now := 1000
	for entry in cases:
		now += 100
		var result := world.receive_commands(LOCAL, entry[0], now)
		_expect(str(result["reason"]) == str(entry[1]), "hostile packet %s is refused as %s (got %s)" % [str(entry[0]).left(60), entry[1], result["reason"]])
	var batch: Array = []
	for i in NetSync.MAX_COMMANDS_PER_PACKET + 1:
		batch.append([0.0, 0.0, 0.0, 0.0, []])
	now += 100
	_expect(world.receive_commands(LOCAL, [epoch, 1, batch], now)["reason"] == "batch_too_large", "an oversized batch is refused whole")
	now += 100
	_expect(world.receive_commands(LOCAL, [epoch, NetSync.MAX_SEQUENCE_ADVANCE + 5, [[0.0, 0.0, 0.0, 0.0, []]]], now)["reason"] == "sequence_jump", "an excessive sequence advance is refused")
	# Valores não finitos passam o formato e são recusados na simulação.
	now += 100
	world.receive_commands(LOCAL, [epoch, 1, [[NAN, 0.0, 0.0, 0.0, []], [0.0, 0.0, INF, 0.0, []], [0.0, 0.0, 0.0, NAN, []]]], now)
	var reasons: Array = []
	for i in 8:
		world.step(func(_p): return "", func(_p, _a, _s): pass, func(_p, _s, _a, reason): reasons.append(reason))
	_expect(reasons == ["non_finite", "non_finite", "non_finite"], "non-finite values are refused without effect (%s)" % str(reasons))
	var position: Vector3 = world.states[LOCAL]["position"]
	_expect(position.is_finite() and is_finite(float(world.states[LOCAL]["yaw"])), "the official state stays finite")
	# Inundação de pacotes: o balde barra, e só a inundação.
	var flood := 0
	for i in 40:
		if str(world.receive_commands(LOCAL, [epoch, 100 + i, [[0.0, 0.0, 0.0, 0.0, []]]], now)["reason"]) == "packet_rate":
			flood += 1
	_expect(flood > 0 and flood < 40, "a packet flood in one instant is throttled (%d of 40 refused)" % flood)
	var legit := AuthoritativeWorld.new()
	legit.add_player(LOCAL)
	var refused := 0
	for i in 60:
		# 30 pacotes/s com jitter: rajadas de 3 no mesmo instante e pausas.
		var at := 1000 + int(i / 3) * 100
		if str(legit.receive_commands(LOCAL, [1, 1 + i * 2, [[0.0, 0.0, 0.0, 0.0, []], [0.0, 0.0, 0.0, 0.0, []]]], at)["reason"]) != "":
			refused += 1
	_expect(refused == 0, "legitimate batches bunched by jitter are never refused (%d refused)" % refused)

func _test_time_budget() -> void:
	# Um cliente manda o dobro de comandos por segundo: o servidor não simula
	# mais que o tempo real mais o orçamento, e o excesso vira fila cheia.
	var world := AuthoritativeWorld.new()
	world.add_player(LOCAL)
	world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0))
	var epoch := int(world.states[LOCAL]["epoch"])
	var seq := 1
	var dropped := 0
	for tick in 300:
		var batch: Array = []
		for i in 2:
			batch.append([0.0, -1.0, 0.0, 0.0, []])
		var result := world.receive_commands(LOCAL, [epoch, seq, batch], tick * 16)
		seq += 2
		dropped += (result.get("dropped_actions", []) as Array).size()
		world.step(func(_p): return "", func(_p, _a, _s): pass, func(_p, _s, _a, _r): pass)
	var simulated := int(world.states[LOCAL]["simulated_commands"])
	_expect(simulated <= 300 + NetSync.MAX_BUDGET_TICKS, "sending twice as many commands never buys simulation time (%d in 300 ticks)" % simulated)
	_expect((world.states[LOCAL]["queue"] as Array).size() <= NetSync.MAX_QUEUE_COMMANDS, "the command queue stays bounded")
	_expect(int(world.rejection_counts.get("queue_full", 0)) > 0, "the excess is refused explicitly (queue_full)")
	var speed := (world.states[LOCAL]["velocity"] as Vector3).length()
	_expect(speed <= MovementRules.MAX_SPEED + 0.001, "speed never exceeds the rule")

func _step(world: AuthoritativeWorld, ticks: int) -> void:
	for i in ticks:
		world.step(func(_p): return "", func(_p, _a, _s): pass, func(_p, _s, _a, _r): pass)

# --- Mira ----------------------------------------------------------------------

func _test_pitch_clamp_and_yaw_wrap() -> void:
	var loop := Loop.new("rtt80", 5)
	loop.world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0), PI - 0.05, 0.0)
	loop.settle(12)
	# Muito mouse para cima: o pitch para no limite e nada fica acumulado.
	for i in 120:
		loop.step(Vector2.ZERO, Vector2(0.0, 0.2))
	_expect(is_equal_approx(float(loop.client.state["pitch"]), MovementRules.MAX_PITCH), "looking up stops at the official pitch limit")
	loop.step(Vector2.ZERO, Vector2(0.0, -0.05))
	_expect(float(loop.client.state["pitch"]) < MovementRules.MAX_PITCH - 0.04, "moving the mouse back down responds at once (no stored excess)")
	# Yaw atravessa ±π pelo menor arco, igual no servidor.
	for i in 10:
		loop.step(Vector2.ZERO, Vector2(0.02, 0.0))
	loop.settle(30)
	var yaw := float(loop.client.state["yaw"])
	_expect(yaw < -PI + 0.2, "yaw wraps across +π to -π (%.3f)" % yaw)
	_expect(absf(angle_difference(yaw, float(loop.official()["yaw"]))) < 1e-6, "the wrapped yaw matches the server")
	var interp := RemoteInterpolator.new()
	var a := {"peer_id": 5, "position": Vector3(0, 1, 200), "yaw": PI - 0.05, "pitch": 0.0, "epoch": 1}
	var b := {"peer_id": 5, "position": Vector3(0, 1, 200), "yaw": -PI + 0.05, "pitch": 0.0, "epoch": 1}
	interp.push(100, [a])
	interp.push(103, [b])
	interp.render_tick = 101.5
	var mid := float(interp.sample(5)["yaw"])
	_expect(absf(absf(mid) - PI) < 0.02, "remote yaw interpolates the short way across ±π (%.3f)" % mid)
	# Mouse além do balde de taxa: o excesso é descartado, não vira giro atrasado.
	var prediction := PlayerPrediction.new()
	prediction.reconcile({"seq": 0, "epoch": 1}, {"position": Vector3(13.5, 1, 12), "yaw": 0.0, "pitch": 0.0})
	prediction.add_look(3.0, 0.0)
	var first := prediction.build_command(Vector2.ZERO)
	_expect(absf(float(first["yaw_delta"])) <= MovementRules.MAX_YAW_DELTA + 1e-9, "one command never carries more than the per-command limit")
	var second := prediction.build_command(Vector2.ZERO)
	_expect(float(second["yaw_delta"]) == 0.0, "the excess mouse beyond the limit is discarded, not replayed later")

func _test_replay_has_no_side_effects() -> void:
	var prediction := PlayerPrediction.new()
	prediction.reconcile({"seq": 0, "epoch": 1}, {"position": Vector3(13.5, 1, 12), "yaw": 0.0, "pitch": 0.0})
	prediction.queue_action({"kind": "fire", "id": 1})
	for i in 10:
		prediction.build_command(Vector2(0, -1))
	var next_seq := prediction.next_seq
	var pending := prediction.pending.size()
	var queued := prediction.queued_action.duplicate()
	var result := prediction.reconcile({"seq": 3, "epoch": 1, "yaw_tokens": 0.7, "pitch_tokens": 0.7}, {"position": Vector3(13.5, 1, 12), "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0})
	_expect(prediction.next_seq == next_seq, "replay never creates or sends commands")
	_expect(prediction.pending.size() == pending - 3 and int(result["replayed"]) == pending - 3, "replay reapplies only the commands after the ACK (%d)" % int(result["replayed"]))
	_expect(prediction.queued_action == queued and queued.is_empty(), "replay never queues the action again")
	# O resultado do replay é o mesmo de simular do zero só os pendentes.
	var reference := PlayerPrediction.official_from({"position": Vector3(13.5, 1, 12), "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0}, {"yaw_tokens": 0.7, "pitch_tokens": 0.7})
	for command in prediction.pending:
		MovementRules.simulate_command(reference, command["move"], float(command["yaw_delta"]), float(command["pitch_delta"]))
	_expect((reference["position"] as Vector3).is_equal_approx(prediction.state["position"]), "replay applies exactly the pending commands, never the acknowledged ones")

# --- Tiro causal -----------------------------------------------------------------

## Mundo de combate: atirador em (12,1,15.5) com o yaw dado; alvo a 5 m ao
## norte e outro a 3 m a oeste (faixas livres no Salão).
func _combat(yaw: float = 0.0) -> Dictionary:
	var rounds := RoundAuthority.new()
	var loop := Loop.new("local", 9)
	loop.world.add_player(TARGET)
	loop.world.add_player(3)
	loop.world.add_player(4)
	rounds.state = RoundState.ACTIVE
	rounds.round_id = 1
	rounds.participants = {1: true, 2: true, 3: true, 4: true}
	rounds.alive = {1: true, 2: true, 3: true, 4: true}
	rounds._roles = {1: Role.VICTIM, 2: Role.VICTIM, 3: Role.VICTIM, 4: Role.ASSASSIN}
	var combat := CombatAuthority.new(rounds, loop.world)
	combat.begin_round(1, [1, 2, 3, 4])
	combat.inventory.inventories[LOCAL]["weapon_id"] = CombatAuthority.COMMON_WEAPON_ID
	combat.inventory.inventories[LOCAL]["equipped"] = true
	combat.inventory.inventories[LOCAL]["magazine"] = 6
	loop.world.teleport(LOCAL, Vector3(12, 1, 15.5), yaw, 0.0)
	loop.world.states[TARGET]["position"] = Vector3(12, 1, 10.5)
	loop.world.states[3]["position"] = Vector3(9, 1, 15.5)
	loop.world.states[4]["position"] = Vector3(3, 1, 2.5)
	var shots: Array = []
	combat.shot_resolved.connect(func(event): shots.append(event))
	var results: Array = []
	loop.action_runner = func(peer_id: int, action: Dictionary, _seq: int):
		if str(action["kind"]) == "fire":
			results.append(combat.request_fire(peer_id, int(action["id"]), 100000 + loop.tick * 16))
	loop.settle(12)
	return {"loop": loop, "combat": combat, "shots": shots, "results": results}

func _test_fire_causal_order() -> void:
	# Mira oficial 0,2 rad antes do oeste; no mesmo quadro o mouse completa o
	# giro e o jogador clica. O tiro sai para oeste (acerta o alvo a 3 m) e
	# nunca com o yaw anterior (0,6 m de desvio lateral nesse alvo: erraria).
	var fixture := _combat(PI * 0.5 - 0.2)
	var loop: Loop = fixture["loop"]
	var combat: CombatAuthority = fixture["combat"]
	_expect(not ArenaRules.overlaps_blocker(loop.world.states[3]["position"]), "the west target stands on a valid official position")
	loop.client.add_look(0.2, 0.0)
	loop.client.queue_action({"kind": "fire", "id": 1})
	loop.step(Vector2.ZERO)
	loop.settle(10)
	var shots: Array = fixture["shots"]
	_expect(shots.size() == 1, "one click, one official shot")
	var end: Vector3 = shots[0]["end"] if not shots.is_empty() else Vector3.ZERO
	_expect(end.x < 9.5 and absf(end.z - 15.5) < 0.1, "aim and click in the same frame: the shot follows the new aim (end %s)" % str(end))
	_expect(int(combat.health[3]) == 66 and int(combat.health[TARGET]) == 100, "the target in the new aim is hit, the one in the old aim is not")
	# Tiro e, no mesmo tick depois do clique, mais giro: o tiro usa a mira do
	# clique; o giro posterior vai no comando seguinte.
	var second := _combat()
	var loop2: Loop = second["loop"]
	var combat2: CombatAuthority = second["combat"]
	loop2.client.queue_action({"kind": "fire", "id": 1})
	loop2.client.add_look(0.35, 0.0)
	var built := loop2.client.build_command(Vector2.ZERO)
	_expect(float(built["yaw_delta"]) == 0.0 and not (built["action"] as Dictionary).is_empty(), "the look after the click is not in the command of the shot")
	loop2.outbox.append(built)
	loop2.flush()
	loop2.settle(10)
	_expect(int(combat2.health[TARGET]) == 66 and int(combat2.health[3]) == 100, "a later aim never rewrites an earlier shot")
	_expect(absf(float(loop2.official()["yaw"]) - 0.35) < 1e-6, "the later aim is still applied, after the shot")

func _test_fire_dependency_rejections() -> void:
	var fixture := _combat()
	var loop: Loop = fixture["loop"]
	var combat: CombatAuthority = fixture["combat"]
	# Comando inválido que carregava o tiro: recusa explícita, sem disparo.
	var seq := loop.inject(loop.client.epoch, [[0.0, 0.0, NAN, 0.0, ["fire", 1]]])
	loop.settle(6)
	_expect((fixture["shots"] as Array).is_empty(), "a shot whose command is rejected never fires with the last aim")
	var explicit := false
	for rejection in loop.rejections:
		if int(rejection["seq"]) == seq and not (rejection["action"] as Dictionary).is_empty():
			explicit = true
	_expect(explicit, "the action of a rejected command gets an explicit result")
	# Época antiga (eliminação/nova rodada no meio): recusa sem efeito.
	var old_epoch := loop.client.epoch
	loop.world.bump_epoch(LOCAL)
	var stale_seq := loop.inject(old_epoch, [[0.0, 0.0, 0.0, 0.0, ["fire", 2]]])
	loop.settle(6)
	var stale := false
	for rejection in loop.rejections:
		if int(rejection["seq"]) == stale_seq and str(rejection["reason"]) == "stale_epoch":
			stale = true
	_expect(stale and (fixture["shots"] as Array).is_empty(), "a shot from an old epoch is refused explicitly")
	# Jogador morto: o portão de regra recusa antes de qualquer efeito.
	loop.gate_reason = "player_dead"
	loop.client.queue_action({"kind": "fire", "id": 3})
	loop.settle(8)
	_expect((fixture["shots"] as Array).is_empty() and int(combat.health[TARGET]) == 100, "a dead player's queued shot never fires")
	var dead := false
	for rejection in loop.rejections:
		if str(rejection["reason"]) == "player_dead" and not (rejection["action"] as Dictionary).is_empty():
			dead = true
	_expect(dead, "the dead player's action is refused with player_dead")

func _test_action_idempotence() -> void:
	var fixture := _combat()
	var loop: Loop = fixture["loop"]
	var combat: CombatAuthority = fixture["combat"]
	loop.client.queue_action({"kind": "fire", "id": 1})
	loop.step(Vector2.ZERO)
	loop.settle(30)
	loop.client.queue_action({"kind": "fire", "id": 1})
	loop.step(Vector2.ZERO)
	loop.settle(10)
	var results: Array = fixture["results"]
	_expect(results.size() == 2 and bool(results[0]["accepted"]) and str(results[1].get("reason", "")) == "replay",
		"the same action id twice: executed once, the repeat refused as replay (%s)" % str(results))
	_expect((fixture["shots"] as Array).size() == 1 and int(combat.health[TARGET]) == 66 and int(combat.inventory.get_inventory(LOCAL)["magazine"]) == 5,
		"one bullet, one damage, one public event")

# --- Épocas, eliminação e reset --------------------------------------------------

func _test_epochs_elimination_and_reset() -> void:
	var loop := Loop.new("rtt150j", 4)
	loop.world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0))
	loop.settle(20)
	for i in 20:
		loop.step(Vector2(1, 0))
	# Eliminação com comandos pendentes: nova época; a fila antiga é recusada.
	loop.world.bump_epoch(LOCAL)
	var bumped := int(loop.world.states[LOCAL]["epoch"])
	for i in 20:
		loop.step(Vector2(1, 0))
	loop.settle(30)
	_expect(loop.client.epoch == bumped, "the client adopts the new epoch from the ACK")
	_expect(loop.client.epoch_resets >= 1, "the epoch change resets the prediction instead of replaying old commands")
	_expect(int(loop.world.rejection_counts.get("stale_epoch", 0)) > 0, "commands of the old epoch were refused, not applied")
	_expect((loop.official()["position"] as Vector3).distance_to(loop.client.state["position"]) < 0.001, "after the reset the prediction is the official state")
	# Reposicionamento oficial com a mesma época ignorada: descontinuidade no
	# snapshot público e buffer remoto limpo.
	var interp := RemoteInterpolator.new()
	interp.push(10, [{"peer_id": 7, "position": Vector3(13, 1, 12), "epoch": 1}])
	interp.push(13, [{"peer_id": 7, "position": Vector3(13.2, 1, 12), "epoch": 1}])
	interp.push(16, [{"peer_id": 7, "position": Vector3(3, 1, 2.5), "epoch": 2}])
	var sample := interp.sample(7)
	_expect(bool(sample["discontinuity"]) and (sample["position"] as Vector3).is_equal_approx(Vector3(3, 1, 2.5)), "a new public epoch is an explicit discontinuity (no slide across the map)")
	_expect(not bool(interp.sample(7)["discontinuity"]), "the discontinuity is reported once")
	# Conexão nova com ids reutilizados: estado zerado.
	var prediction := loop.client
	prediction.reset_all()
	_expect(not prediction.has_state and prediction.pending.is_empty() and prediction.official.is_empty(), "a new session starts from nothing")
	interp.clear()
	_expect(interp.buffers.is_empty() and not interp.has_clock, "a new session clears remote buffers and the clock")

func _test_snapshot_filter() -> void:
	var app_script := load("res://shared/network_app.gd")
	var good := {"tick": 30, "session": 77, "players": [], "ack": {}}
	_expect(app_script.snapshot_rejection(good, 0, -1) == "", "the first snapshot defines the session")
	_expect(app_script.snapshot_rejection(good, 77, 29) == "", "a newer snapshot of the same session is accepted")
	_expect(app_script.snapshot_rejection(good, 78, 29) == "foreign_session", "a snapshot from another server session is dropped")
	_expect(app_script.snapshot_rejection(good, 77, 30) == "stale_tick", "a repeated tick is dropped")
	_expect(app_script.snapshot_rejection(good, 77, 40) == "stale_tick", "an older tick never goes back in time")
	_expect(app_script.snapshot_rejection({"tick": "30", "session": 77, "players": [], "ack": {}}, 77, 1) == "malformed", "wrong types are dropped")

# --- Interpolação ----------------------------------------------------------------

func _test_interpolation() -> void:
	# Quinas reais: porta estreita Salão/corredor da cozinha e canto do
	# Escritório. Com snapshots a cada 3 ticks (≤ 0,38 m) a reta entre duas
	# posições oficiais não chega a 0,3 m de um volume; depois de um stall as
	# amostras ficam ~1 m distantes e a reta cortaria a quina.
	for corner in [[Vector3(19.46081, 1.0, 12.53971), Vector3(18.74507, 1.0, 11.84135)], [Vector3(5.430946, 1.0, 1.283945), Vector3(6.159136, 1.0, 1.969321)]]:
		var corner_a: Vector3 = corner[0]
		var corner_b: Vector3 = corner[1]
		var straight_hits := false
		for i in 11:
			if ArenaRules.overlaps_blocker(corner_a.lerp(corner_b, i / 10.0), NetSync.PRESENTATION_BODY_RADIUS):
				straight_hits = true
		var overlaps := 0
		var interp := RemoteInterpolator.new()
		interp.push(0, [{"peer_id": 3, "position": corner_a, "epoch": 1}])
		interp.push(12, [{"peer_id": 3, "position": corner_b, "epoch": 1}])
		for i in 121:
			interp.render_tick = i * 0.1
			var point: Vector3 = interp.sample(3)["position"]
			if ArenaRules.overlaps_blocker(point, NetSync.PRESENTATION_BODY_RADIUS):
				overlaps += 1
		_report.append("NETCODE_CORNER zone=%s straight_line_hits=%s presented_overlaps=%d corner_paths=%d holds=%d" % [
			str(ArenaRules.zone_at(corner_a).get("id", "")), str(straight_hits), overlaps, interp.corner_paths, interp.corner_holds])
		_expect(not ArenaRules.overlaps_blocker(corner_a) and not ArenaRules.overlaps_blocker(corner_b), "both corner samples are valid official positions")
		_expect(straight_hits, "the straight line between the corner samples would cut the wall (the case is real)")
		_expect(overlaps == 0, "the presented body never enters the wall at the corner")
	# Stall: sem amostra nova, extrapola no máximo o limite e depois segura.
	var stall := RemoteInterpolator.new()
	var velocity := Vector3(0, 0, -5)
	for tick in range(0, 31, 3):
		stall.push(tick, [{"peer_id": 4, "position": Vector3(12, 1, 15.5) + velocity * tick / 60.0, "velocity": velocity, "epoch": 1}])
	stall.render_tick = 30.0 + NetSync.MAX_EXTRAPOLATION_TICKS * 0.5
	_expect(str(stall.sample(4)["mode"]) == "extrapolate", "a short stall extrapolates")
	stall.render_tick = 30.0 + NetSync.MAX_EXTRAPOLATION_TICKS * 5.0
	var held: Dictionary = stall.sample(4)
	var limit := Vector3(12, 1, 15.5) + velocity * (30.0 + NetSync.MAX_EXTRAPOLATION_TICKS) / 60.0
	_expect(str(held["mode"]) == "hold" and (held["position"] as Vector3).distance_to(limit) < 0.01, "a long stall holds at the extrapolation limit (no endless walking)")
	_expect((held["velocity"] as Vector3) == Vector3.ZERO, "a held body reports no walking speed to the animation")
	stall.push(40, [{"peer_id": 4, "position": Vector3(12, 1, 15.5) + velocity * 40 / 60.0, "velocity": velocity, "epoch": 1}])
	stall.render_tick = 38.0
	_expect(str(stall.sample(4)["mode"]) == "interpolate", "after the stall the interpolation resumes")
	# Relógio: monotônico com jitter e ressincroniza só com erro grande.
	var clock := RemoteInterpolator.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var last := -INF
	var went_back := false
	var tick := 0
	for frame in 600:
		clock.advance(DT)
		if frame % 3 == 0:
			clock.push(tick + rng.randi_range(-2, 2) if tick > 2 else tick, [{"peer_id": 9, "position": Vector3(0, 1, 200), "epoch": 1}])
			tick += 3
		if clock.render_tick < last:
			went_back = true
		last = clock.render_tick
	_expect(not went_back, "the presentation clock never goes back")
	_expect(clock.resyncs == 0, "jitter alone never forces a clock resync")
	var lead := (clock.local_ticks + clock.offset) - clock.render_tick
	_expect(lead >= NetSync.INTERP_DELAY_TICKS - 1.0 and lead <= NetSync.INTERP_DELAY_TICKS + NetSync.MAX_JITTER_DELAY_TICKS + 1.0, "the interpolation delay stays within its bounds (%.2f ticks)" % lead)
	# Snapshot antigo nunca retrocede o buffer.
	_expect(not clock.push(3, [{"peer_id": 9, "position": Vector3(50, 1, 200), "epoch": 1}]), "an old snapshot is ignored")
	# Buffer limitado.
	var bounded := RemoteInterpolator.new()
	for t in 200:
		bounded.push(t * 3, [{"peer_id": 1, "position": Vector3(0, 1, 200), "epoch": 1}])
	_expect((bounded.buffers[1] as Array).size() <= NetSync.MAX_REMOTE_SAMPLES, "the remote buffer is bounded")
	# Suavidade: velocidade apresentada de um remoto a 5 m/s com snapshots a
	# 20 Hz chegando com jitter e quadros irregulares.
	var smooth := RemoteInterpolator.new()
	var jitter_rng := RandomNumberGenerator.new()
	jitter_rng.seed = 21
	var pending: Array = []
	var server_tick := 0
	var time := 0.0
	var speeds: Array = []
	var previous := Vector3.INF
	for frame in 900:
		var dt := (16.7 + jitter_rng.randf_range(-4.0, 4.0)) / 1000.0
		time += dt
		while server_tick / 60.0 <= time:
			pending.append([server_tick / 60.0 + 0.04 + jitter_rng.randf() * 0.03, server_tick])
			server_tick += 3
		while not pending.is_empty() and float(pending[0][0]) <= time:
			var arrived: int = pending.pop_front()[1]
			smooth.push(arrived, [{"peer_id": 6, "position": Vector3(5.0 * arrived / 60.0, 1, 200), "velocity": Vector3(5, 0, 0), "epoch": 1}])
		smooth.advance(dt)
		var s := smooth.sample(6)
		if s.is_empty():
			continue
		var p: Vector3 = s["position"]
		if previous != Vector3.INF and frame > 120:
			speeds.append((p.x - previous.x) / dt)
		previous = p
	var cv := _cv(speeds)
	_report.append("NETCODE_REMOTE_SMOOTHNESS frames=%d cv=%.3f resyncs=%d" % [speeds.size(), cv, smooth.resyncs])
	_expect(cv < 0.1, "a steady remote walk is presented smoothly (speed CV %.3f)" % cv)

func _cv(values: Array) -> float:
	if values.size() < 2:
		return 0.0
	var mean := 0.0
	for v in values: mean += float(v)
	mean /= values.size()
	var variance := 0.0
	for v in values: variance += pow(float(v) - mean, 2.0)
	return sqrt(variance / (values.size() - 1)) / absf(mean)

# --- Correção e convergência -----------------------------------------------------

func _test_correction_smoothing() -> void:
	var prediction := PlayerPrediction.new()
	var player := {"position": Vector3(13.5, 1, 12), "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0}
	prediction.reconcile({"seq": 0, "epoch": 1}, player)
	for i in 6:
		prediction.build_command(Vector2(1, 0))
	# O servidor resolveu os 6 mas deixou o jogador 0,3 m atrás (correção
	# pequena): offset visual que some dentro do prazo.
	var corrected := player.duplicate()
	corrected["position"] = Vector3(13.5, 1, 12)
	prediction.reconcile({"seq": 6, "epoch": 1, "yaw_tokens": 0.7, "pitch_tokens": 0.7}, corrected)
	_expect(prediction.corrections_small == 1 and prediction.position_offset.length() > 0.01, "a small correction becomes a visual offset")
	var elapsed := 0.0
	while prediction.position_offset != Vector3.ZERO and elapsed < 1.0:
		prediction.presented(1.0, DT)
		elapsed += DT
	_expect(elapsed <= NetSync.POSITION_SMOOTH_MAX + DT, "the visual offset is gone within %.2f s (%.3f s)" % [NetSync.POSITION_SMOOTH_MAX, elapsed])
	# Correção grande: salto, sem varrer o cenário.
	for i in 3:
		prediction.build_command(Vector2(1, 0))
	var far := player.duplicate()
	far["position"] = Vector3(3, 1, 2.5)
	prediction.reconcile({"seq": 9, "epoch": 1, "yaw_tokens": 0.7, "pitch_tokens": 0.7}, far)
	_expect(prediction.corrections_large == 1 and prediction.position_offset == Vector3.ZERO, "a large correction snaps")
	# Offset nunca leva a câmera para dentro de um volume oficial.
	var wall := PlayerPrediction.new()
	var near_wall := {"position": Vector3(13.5, 1, 7.99), "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0}
	wall.reconcile({"seq": 0, "epoch": 1}, near_wall)
	wall.build_command(Vector2.ZERO)
	wall.position_offset = Vector3(0, 0, -0.6)
	var shown: Dictionary = wall.presented(1.0, DT)
	_expect(not ArenaRules.overlaps_blocker(shown["position"], NetSync.CAMERA_CLEARANCE), "a correction offset never pulls the camera into a wall")
	# Histórico limitado: ACK que não chega vira recuperação explícita.
	var starving := PlayerPrediction.new()
	starving.reconcile({"seq": 0, "epoch": 1}, player)
	for i in NetSync.MAX_PENDING_COMMANDS + 10:
		starving.build_command(Vector2(1, 0))
	_expect(starving.pending.size() <= NetSync.MAX_PENDING_COMMANDS and starving.recoveries >= 1, "pending history is bounded with an explicit recovery")

## Convergência: depois que o input para e a rede estabiliza, a apresentação
## chega ao estado oficial dentro do prazo (também com uma correção do servidor
## no meio). Mede também o erro da previsão em cada ACK.
func _test_convergence_under_delay(profile: String, seed_value: int) -> void:
	var loop := Loop.new(profile, seed_value)
	loop.world.teleport(LOCAL, Vector3(13.5, 1.0, 12.0))
	loop.settle(20)
	var inputs := _input_script(seed_value, 180)
	for index in inputs.size():
		loop.step(inputs[index]["move"], inputs[index]["look"])
		if index == 90:
			# Correção autoritativa pequena no meio (servidor empurra o corpo).
			(loop.world.states[LOCAL] as Dictionary)["position"] += Vector3(0.2, 0, 0)
		loop.client.presented(1.0, DT)
	var stop_tick := loop.tick
	var last_moving_seq := loop.client.next_seq - 1
	var converged_at := -1
	for i in 120:
		loop.step(Vector2.ZERO)
		var shown: Dictionary = loop.client.presented(1.0, DT)
		var error := (shown["position"] as Vector3).distance_to(loop.official()["position"])
		# Comandos ociosos seguem em trânsito (o cliente comanda todo tick); a
		# convergência é o oficial já com o último comando de movimento e a
		# apresentação sobre ele.
		if error < 0.001 and converged_at < 0 and loop.client.last_ack >= last_moving_seq:
			converged_at = loop.tick
	var seconds := float(converged_at - stop_tick) / 60.0 if converged_at >= 0 else INF
	_report.append("NETCODE_CONVERGENCE profile=%s seed=%d converged_s=%.3f corrections_small=%d large=%d max_pending=%d" % [
		profile, seed_value, seconds, loop.client.corrections_small, loop.client.corrections_large, loop.client.pending.size()])
	_expect(seconds <= NetSync.CONVERGENCE_DEADLINE_SECONDS, "%s: the presentation converges within %.1f s after input stops (%.3f s)" % [profile, NetSync.CONVERGENCE_DEADLINE_SECONDS, seconds])
	_expect(loop.client.corrections_small >= 1, "%s: the server correction was seen and smoothed" % profile)

# --- ArenaView -------------------------------------------------------------------

## Mouse → câmera no mesmo quadro, sem esperar snapshot (gate da fase 4).
func _test_camera_uses_local_look_immediately() -> void:
	var prediction := PlayerPrediction.new()
	prediction.reconcile({"seq": 0, "epoch": 1}, {"position": Vector3(13.5, 1, 12), "velocity": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0})
	_arena.local_view_provider = func(delta: float): return prediction.presented(1.0, delta)
	_arena.apply_snapshot([{"peer_id": LOCAL, "position": Vector3(13.5, 1, 12), "yaw": 0.0, "pitch": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0}], 3)
	_arena._process(DT)
	var before := _arena.player_rig.rotation.y
	prediction.add_look(0.2, 0.1)
	_arena._process(DT)
	_expect(absf(angle_difference(before + 0.2, _arena.player_rig.rotation.y)) < 1e-4, "the next frame shows the new yaw without any tick or snapshot")
	_expect(absf(_arena.camera.rotation.x - 0.1) < 1e-4, "the next frame shows the new pitch on the camera only")
	_expect(is_zero_approx(_arena.camera.rotation.y) and is_zero_approx(_arena.player_rig.rotation.x), "yaw lives only on the rig and pitch only on the camera")
	# Um snapshot oficial antigo não puxa a câmera de volta.
	_arena.apply_snapshot([{"peer_id": LOCAL, "position": Vector3(13.5, 1, 12), "yaw": 0.0, "pitch": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0}], 6)
	_arena._process(DT)
	_expect(absf(angle_difference(before + 0.2, _arena.player_rig.rotation.y)) < 1e-4, "an official snapshot does not force the camera back to an older yaw")
	_arena.local_view_provider = Callable()

func _test_spectator_uses_interpolated_target() -> void:
	var peer := 8
	_arena.apply_snapshot([_player(LOCAL, Vector3(13.5, 1, 12), 0.0), _player(peer, Vector3(4, 1, 12), 1.0)], 30)
	_arena.set_spectator_target(peer)
	_expect(_arena.player_rig.position.is_equal_approx(Vector3(4, 1, 12)), "switching the spectator target moves the camera at once (no sweep across walls)")
	_arena.apply_snapshot([_player(LOCAL, Vector3(13.5, 1, 12), 0.0), _player(peer, Vector3(4.25, 1, 12), 1.0)], 33)
	for i in 3:
		_arena._process(DT)
	var x := _arena.player_rig.position.x
	_expect(x >= 4.0 and x <= 4.25, "the spectator camera follows the target's interpolated presentation (x %.3f)" % x)
	_arena.set_spectator_target(0, false)
	_expect(_arena.player_rig.position.is_equal_approx(Vector3(13.5, 1, 12)), "leaving the spectator returns to the own official view at once")

func _player(peer_id: int, position: Vector3, yaw: float) -> Dictionary:
	return {"peer_id": peer_id, "position": position, "yaw": yaw, "pitch": 0.0, "velocity": Vector3.ZERO, "spawn_index": 0, "epoch": 1}

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		return
	failures += 1
	push_error("NETCODE_CHECK_FAILED %s" % description)
