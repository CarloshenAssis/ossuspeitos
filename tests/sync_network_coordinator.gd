extends Node

## Fase 4, camada B: processos reais (servidor + 4 clientes pelo WebSocket)
## exercitando o protocolo 9. O servidor prepara posições e inventário
## (setup de teste isolado, documentado) e manda roteiros por tick ao ator;
## o ator os executa pelo caminho normal de comandos (mesma previsão e envio
## do jogador humano). Verificações:
## - MOVE: porta estreita, parede e quina; o previsto do ator e a visão do
##   observador batem com o oficial; nenhuma posição oficial dentro de volume;
##   com o perfil de stall, uma interrupção de 400 ms no meio.
## - AIM: girar e atirar no mesmo tick acerta o alvo da mira nova; atirar e
##   girar no mesmo tick usa a mira do clique; todos recebem os dois tiros.
## - VERTICAL: pitch oficial alto erra, baixo bate no piso, nivelado acerta.
## - DUPLICATE: mesmo id de ação duas vezes → um tiro, um dano, uma bala.
## - PRIVACY: snapshots só com chaves públicas; ACK só do próprio jogador.
##
## Modo visual (`--sync-visual=true`, camada C, clientes gráficos sob xvfb):
## ator e observador gravam quadros e telemetria por cena — caminhada, strafe,
## parada, giro de câmera e pitch (observador de fora e ator em primeira
## pessoa), espectador seguindo o ator e o retorno à própria visão na rodada
## seguinte. Os quadros viram vídeo fora do Godot (ver docs/netcode.md).

const MOVE_START := Vector3(17.2, 1.0, 11.5)
const LANE_SHOOTER := Vector3(12.0, 1.0, 15.5)
const WEST_TARGET := Vector3(9.0, 1.0, 15.5)
const NORTH_SHOOTER := Vector3(12.0, 1.0, 16.0)
const NORTH_TARGET := Vector3(12.0, 1.0, 11.0)
const SAFE_POSITIONS := [Vector3(3, 1, 2.5), Vector3(39.5, 1, 24.0), Vector3(26, 1, 2.5)]
const STAGE_TIMEOUT_MSEC := 20000
const SETTLE_MSEC := 900
const PUBLIC_SNAPSHOT_KEYS := ["peer_id", "position", "velocity", "yaw", "pitch", "spawn_index", "epoch"]
const ACK_KEYS := ["seq", "epoch", "yaw_tokens", "pitch_tokens"]

var app
var stage := "WAIT_ACTIVE"
var stage_started_msec := 0
var peers: Array = []
var actor := 0
var observer := 0
var target := 0
var idle := 0
var reports: Dictionary = {}
var shots: Array = []
var results: Array = []
var move_overlaps := 0
var move_zones: Dictionary = {}
var failures := 0
## Cliente.
var running_stage := ""
var script_done_msec := 0
var snapshot_violations := 0
var foreign_acks := 0
var shots_seen := 0
var last_views: Dictionary = {}
var visual := false
var visual_out := ""
var recording_stage := ""
var recording_until_msec := 0
var recording_frame := 0
var recording_rows: Array = []
var spectate_peer := 0
var graphical_peers: Dictionary = {}
var hello_sent := false

func _ready() -> void:
	app = get_parent()
	stage_started_msec = Time.get_ticks_msec()
	visual = NetworkConfig.bool_argument(app.arguments, "sync-visual")
	visual_out = str(app.arguments.get("sync-visual-out", ""))
	if visual and app.mode != "server":
		RenderingServer.frame_post_draw.connect(_on_frame_drawn)

func _process(_delta: float) -> void:
	if app.mode == "server":
		_server_tick()
	else:
		_client_tick()

# --- Servidor --------------------------------------------------------------------

func _enter(next: String) -> void:
	print("SYNC_STAGE_ENTER stage=%s previous=%s" % [next, stage])
	stage = next
	stage_started_msec = Time.get_ticks_msec()
	reports.clear()

func _fail(message: String) -> void:
	failures += 1
	push_error("SYNC_TEST_FAILED stage=%s %s" % [stage, message])
	print("SYNC_TEST_FAILED stage=%s %s" % [stage, message])
	app.get_tree().quit(1)

func _server_tick() -> void:
	if stage == "DONE" or stage == "SHUTDOWN":
		return
	if Time.get_ticks_msec() - stage_started_msec > STAGE_TIMEOUT_MSEC:
		_fail("timeout reports=%s shots=%d results=%s" % [str(reports.keys()), shots.size(), str(results)])
		return
	var world: AuthoritativeWorld = app.authoritative_world
	if stage == "MOVE" and world.states.has(actor):
		var position: Vector3 = world.states[actor]["position"]
		if ArenaRules.overlaps_blocker(position):
			move_overlaps += 1
		move_zones[str(ArenaRules.zone_at(position).get("id", ""))] = true
	match stage:
		"WAIT_ACTIVE":
			if app.round_authority.state != RoundState.ACTIVE or app.combat_authority.active_round_id <= 0:
				return
			peers = app.round_authority.participants.keys()
			if peers.size() != 4:
				return
			peers.sort()
			for peer_id in peers:
				if app.round_authority.get_role_for_peer(peer_id) == Role.ASSASSIN:
					target = int(peer_id)
			if visual:
				# Ator e observador precisam ser clientes gráficos e não o
				# assassino (a eliminação do observador não pode encerrar a rodada).
				if graphical_peers.size() < 3:
					return
				for peer_id in peers:
					if int(peer_id) == target or not graphical_peers.has(int(peer_id)):
						continue
					if actor == 0: actor = int(peer_id)
					elif observer == 0: observer = int(peer_id)
				for peer_id in peers:
					if int(peer_id) not in [actor, observer, target]: idle = int(peer_id)
				print("SYNC_ROLES_SELECTED actor=%d observer=%d target=%d idle=%d visual=true" % [actor, observer, target, idle])
				_enter("SYNC_WAIT")
				return
			for peer_id in peers:
				if int(peer_id) == target:
					continue
				if actor == 0 and app.round_authority.get_role_for_peer(peer_id) == Role.VICTIM:
					actor = int(peer_id)
				elif observer == 0:
					observer = int(peer_id)
				else:
					idle = int(peer_id)
			print("SYNC_ROLES_SELECTED actor=%d observer=%d target=%d idle=%d" % [actor, observer, target, idle])
			_enter("SYNC_WAIT")
		"SYNC_WAIT":
			# Clientes adotam a época da rodada no primeiro ACK depois do ACTIVE.
			if Time.get_ticks_msec() - stage_started_msec > 1500:
				if visual: _setup_visual_walk()
				else: _setup_move()
		"VISUAL_WALK", "VISUAL_SPECTATOR", "VISUAL_RETURN":
			if reports.has(actor) and reports.has(observer):
				_next_visual()
		"VISUAL_WAIT_ROUND":
			if app.round_authority.state == RoundState.ACTIVE and app.round_authority.round_id >= 2:
				if Time.get_ticks_msec() - stage_started_msec > 1500 or stage_started_msec == 0:
					_setup_visual_return()
		"MOVE":
			if reports.has(actor) and reports.has(observer):
				_check_move()
		"AIM":
			if reports.has(actor) and reports.has(observer) and reports.has(target):
				_check_aim()
		"VERTICAL":
			if reports.has(actor):
				_check_vertical()
		"DUPLICATE":
			if reports.has(actor):
				_check_duplicate()
		"PRIVACY":
			if reports.size() == peers.size():
				_check_privacy()

# --- Modo visual ---------------------------------------------------------------

static func _yaw_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))

func _visual_walk_script() -> Array:
	var script: Array = []
	for i in 30: script.append({})
	for i in 70: script.append({"move": Vector2(0, -1)})
	for i in 40: script.append({})
	for i in 60: script.append({"move": Vector2(-1, 0)})
	for i in 40: script.append({})
	for i in 60: script.append({"move": Vector2(0, 1)})
	for i in 40: script.append({})
	for i in 30: script.append({"look": Vector2(0.05, 0.0)})
	for i in 20: script.append({})
	for i in 30: script.append({"look": Vector2(0.0, 0.02)})
	for i in 30: script.append({"look": Vector2(0.0, -0.04)})
	for i in 30: script.append({"look": Vector2(-0.05, 0.02)})
	for i in 30: script.append({})
	return script

func _setup_visual_walk() -> void:
	_place_bystanders([actor, observer])
	var observer_at := Vector3(13.6, 1.0, 16.4)
	app.authoritative_world.teleport(actor, Vector3(10.4, 1.0, 13.3), -PI * 0.5, 0.0)
	app.authoritative_world.teleport(observer, observer_at, _yaw_to(observer_at, Vector3(12.0, 1.0, 13.0)), -0.05)
	_enter("VISUAL_WALK_WAIT")
	get_tree().create_timer(1.2).timeout.connect(func():
		_enter("VISUAL_WALK")
		sync_visual_record.rpc_id(observer, "walk_observer", 9.5, 0)
		sync_visual_record.rpc_id(actor, "walk_actor", 9.5, 0)
		_send_script(actor, "VISUAL_WALK", _visual_walk_script()))

func _next_visual() -> void:
	if stage == "VISUAL_WALK":
		print("SYNC_VISUAL_WALK_OK")
		# O observador é eliminado (teste) e passa a seguir o ator.
		app.round_authority.eliminate_player(observer, "test", 0, Time.get_ticks_msec())
		app.authoritative_world.teleport(actor, Vector3(10.4, 1.0, 13.3), -PI * 0.5, 0.0)
		_enter("VISUAL_SPECTATOR_WAIT")
		get_tree().create_timer(1.2).timeout.connect(func():
			_enter("VISUAL_SPECTATOR")
			sync_visual_record.rpc_id(observer, "spectator", 5.0, actor)
			sync_visual_record.rpc_id(actor, "spectated_actor", 5.0, 0)
			var script: Array = []
			for i in 20: script.append({})
			for i in 80: script.append({"move": Vector2(0, -1), "look": Vector2(0.01, 0.0)})
			for i in 30: script.append({})
			for i in 60: script.append({"move": Vector2(1, 0)})
			for i in 40: script.append({})
			_send_script(actor, "VISUAL_SPECTATOR", script))
	elif stage == "VISUAL_SPECTATOR":
		print("SYNC_VISUAL_SPECTATOR_OK")
		# Fim da rodada pelas regras (assassino eliminado) e retorno na próxima.
		app.round_authority.eliminate_player(target, "test", 0, Time.get_ticks_msec())
		_enter("VISUAL_WAIT_ROUND")
	elif stage == "VISUAL_RETURN":
		print("SYNC_VISUAL_RETURN_OK")
		print("SYNC_VISUAL_SERVER_OK")
		stage = "SHUTDOWN"
		app._begin_server_shutdown(app.lobby.peer_ids())

func _setup_visual_return() -> void:
	_place_bystanders([actor, observer])
	var observer_at := Vector3(13.6, 1.0, 16.4)
	app.authoritative_world.teleport(actor, Vector3(10.4, 1.0, 13.3), -PI * 0.5, 0.0)
	app.authoritative_world.teleport(observer, observer_at, _yaw_to(observer_at, Vector3(12.0, 1.0, 13.0)), -0.05)
	_enter("VISUAL_RETURN_WAIT")
	get_tree().create_timer(1.2).timeout.connect(func():
		_enter("VISUAL_RETURN")
		sync_visual_record.rpc_id(observer, "return_observer", 4.0, 0)
		sync_visual_record.rpc_id(actor, "return_actor", 4.0, 0)
		var script: Array = []
		for i in 30: script.append({})
		for i in 70: script.append({"move": Vector2(0, -1)})
		for i in 60: script.append({})
		_send_script(actor, "VISUAL_RETURN", script))

func _place_bystanders(except: Array) -> void:
	var index := 0
	for peer_id in peers:
		if int(peer_id) in except:
			continue
		app.authoritative_world.teleport(int(peer_id), SAFE_POSITIONS[index])
		index += 1

func _arm_actor() -> void:
	var held: Dictionary = app.combat_authority.inventory.inventories[actor]
	held["weapon_id"] = CombatAuthority.COMMON_WEAPON_ID
	held["equipped"] = true
	held["magazine"] = 6
	held["reserve"] = 0
	held["reloading"] = false

## Roteiro de movimento: atravessa a porta do Salão para o corredor da
## cozinha, raspa na parede em diagonal e contorna a quina.
func _move_script() -> Array:
	var script: Array = []
	for i in 50: script.append({"move": Vector2(0, -1)})
	for i in 30: script.append({"move": Vector2(1, -1).normalized(), "look": Vector2(-0.02, 0.0)})
	for i in 40: script.append({"move": Vector2(1, 0)})
	for i in 30: script.append({"move": Vector2(0, -1), "look": Vector2(0.03, 0.01)})
	for i in 30: script.append({"move": Vector2(-1, 1).normalized()})
	for i in 20: script.append({"move": Vector2.ZERO})
	return script

func _setup_move() -> void:
	_place_bystanders([actor, observer])
	# Porta leste do Salão (x = 18,5): de frente para leste.
	app.authoritative_world.teleport(actor, MOVE_START, -PI * 0.5, 0.0)
	app.authoritative_world.teleport(observer, Vector3(15.0, 1.0, 12.0), -PI * 0.5, 0.0)
	_enter("MOVE")
	_send_script(actor, "MOVE", _move_script(), NetworkConfig.bool_argument(app.arguments, "sync-stall"))
	sync_request_view.rpc_id(observer, "MOVE", actor)

func _send_script(peer_id: int, stage_name: String, script: Array, stall: bool = false) -> void:
	sync_run_script.rpc_id(peer_id, stage_name, script, stall)

func _check_move() -> void:
	var official: Dictionary = app.authoritative_world.states[actor]
	var report: Dictionary = reports[actor]
	var view: Dictionary = reports[observer]
	var position_error := (report["position"] as Vector3).distance_to(official["position"])
	var yaw_error := absf(angle_difference(float(report["yaw"]), float(official["yaw"])))
	var pitch_error := absf(float(report["pitch"]) - float(official["pitch"]))
	var view_error := (view["position"] as Vector3).distance_to(official["position"])
	print("SYNC_MOVE_RESULT position_error=%.6f yaw_error=%.6f pitch_error=%.6f observer_error=%.6f overlaps=%d zones=%s corrections_large=%d corrections_small=%d recoveries=%d epoch_resets=%d ack_error=%s" % [
		position_error, yaw_error, pitch_error, view_error, move_overlaps, ",".join(PackedStringArray(move_zones.keys())),
		int(report["corrections_large"]), int(report["corrections_small"]), int(report["recoveries"]), int(report["epoch_resets"]), str(report["ack_error"])])
	if position_error > 0.001 or yaw_error > 1e-4 or pitch_error > 1e-4:
		_fail("actor prediction differs from the official state"); return
	if view_error > 0.001 or absf(angle_difference(float(view["yaw"]), float(official["yaw"]))) > 1e-4:
		_fail("observer view differs from the official state"); return
	if move_overlaps > 0:
		_fail("official position inside a blocker"); return
	if move_zones.size() < 2:
		_fail("the route did not cross the door (%s)" % str(move_zones.keys())); return
	if int(report["recoveries"]) > 0 or int(report["corrections_large"]) > 0:
		_fail("unexpected large correction or recovery"); return
	print("SYNC_MOVE_OK")
	_setup_aim()

func _setup_aim() -> void:
	_place_bystanders([actor, target])
	_arm_actor()
	app.combat_authority.health[target] = 100
	app.authoritative_world.teleport(actor, LANE_SHOOTER, PI * 0.5 - 0.2, 0.0)
	app.authoritative_world.teleport(target, WEST_TARGET)
	shots.clear()
	results.clear()
	_enter("AIM_WAIT")
	# O ator adota a época nova antes do roteiro.
	get_tree().create_timer(1.0).timeout.connect(func():
		_enter("AIM")
		var script: Array = []
		script.append({"look": Vector2(0.2, 0.0), "action": {"kind": "fire", "id": 1}, "order": "look_then_action"})
		for i in 36: script.append({})
		script.append({"look": Vector2(0.35, 0.0), "action": {"kind": "fire", "id": 2}, "order": "action_then_look"})
		for i in 20: script.append({})
		_send_script(actor, "AIM", script)
		sync_request_shots.rpc_id(observer, "AIM", 2)
		sync_request_shots.rpc_id(target, "AIM", 2))

func _check_aim() -> void:
	if shots.size() != 2:
		_fail("expected 2 official shots, got %d" % shots.size()); return
	var first_end: Vector3 = shots[0]["end"]
	var second_end: Vector3 = shots[1]["end"]
	var official_yaw := float(app.authoritative_world.states[actor]["yaw"])
	print("SYNC_AIM_RESULT first_end=%s second_end=%s target_health=%d final_yaw=%.4f observer_shots=%d target_shots=%d" % [
		str(first_end), str(second_end), int(app.combat_authority.health[target]), official_yaw,
		int(reports[observer]["shots"]), int(reports[target]["shots"])])
	if not bool(shots[0]["hit_player"]) or first_end.x > 9.5 or absf(first_end.z - 15.5) > 0.1:
		_fail("turn-and-fire in the same tick did not use the new aim"); return
	if not bool(shots[1]["hit_player"]) or absf(second_end.z - 15.5) > 0.1:
		_fail("fire-then-turn used the later aim"); return
	if int(app.combat_authority.health[target]) != 32:
		_fail("damage mismatch"); return
	if absf(angle_difference(official_yaw, PI * 0.5 + 0.35)) > 1e-4:
		_fail("the look after the click was not applied after the shot"); return
	if int(reports[observer]["shots"]) != 2 or int(reports[target]["shots"]) != 2:
		_fail("public shot events were not delivered exactly twice"); return
	print("SYNC_AIM_OK")
	_setup_vertical()

func _setup_vertical() -> void:
	_place_bystanders([actor, target])
	_arm_actor()
	app.combat_authority.health[target] = 100
	app.authoritative_world.teleport(actor, NORTH_SHOOTER, 0.0, 0.0)
	app.authoritative_world.teleport(target, NORTH_TARGET)
	shots.clear()
	_enter("VERTICAL_WAIT")
	get_tree().create_timer(1.0).timeout.connect(func():
		_enter("VERTICAL")
		var script: Array = []
		# Sobe 0,5 rad (limitado por comando e pelo balde), atira, desce a -0,5,
		# atira, volta a 0, atira. 30 ticks entre tiros (cadência de 400 ms).
		# Ids de ação crescem na rodada (1 e 2 já foram usados no AIM).
		for delta in [0.25, 0.25]: script.append({"look": Vector2(0, delta)})
		script.append({"action": {"kind": "fire", "id": 3}})
		for i in 30: script.append({})
		for delta in [-0.25, -0.25, -0.25, -0.25]:
			script.append({"look": Vector2(0, delta)})
			for i in 6: script.append({})
		script.append({"action": {"kind": "fire", "id": 4}})
		for i in 30: script.append({})
		for delta in [0.25, 0.25]:
			script.append({"look": Vector2(0, delta)})
			for i in 6: script.append({})
		script.append({"action": {"kind": "fire", "id": 5}})
		for i in 20: script.append({})
		_send_script(actor, "VERTICAL", script))

func _check_vertical() -> void:
	if shots.size() != 3:
		_fail("expected 3 vertical shots, got %d" % shots.size()); return
	var up_end: Vector3 = shots[0]["end"]
	var down_end: Vector3 = shots[1]["end"]
	var level_end: Vector3 = shots[2]["end"]
	print("SYNC_VERTICAL_RESULT up=%s down=%s level=%s hits=%s,%s,%s health=%d" % [str(up_end), str(down_end), str(level_end),
		str(shots[0]["hit_player"]), str(shots[1]["hit_player"]), str(shots[2]["hit_player"]), int(app.combat_authority.health[target])])
	if bool(shots[0]["hit_player"]) or up_end.y < 3.0:
		_fail("a high aim should pass over the target"); return
	if bool(shots[1]["hit_player"]) or absf(down_end.y) > 0.01:
		_fail("a low aim should hit the floor before the target"); return
	if not bool(shots[2]["hit_player"]) or int(app.combat_authority.health[target]) != 66:
		_fail("the level shot should hit"); return
	print("SYNC_VERTICAL_OK")
	_setup_duplicate()

func _setup_duplicate() -> void:
	_arm_actor()
	app.combat_authority.health[target] = 100
	shots.clear()
	results.clear()
	_enter("DUPLICATE")
	var script: Array = []
	script.append({"action": {"kind": "fire", "id": 10}})
	script.append({"action": {"kind": "fire", "id": 10}})
	for i in 30: script.append({})
	_send_script(actor, "DUPLICATE", script)

func _check_duplicate() -> void:
	var fire_results: Array = results.filter(func(r): return str(r["action"]) == "fire" and int(r["id"]) == 10)
	var magazine := int(app.combat_authority.inventory.get_inventory(actor)["magazine"])
	print("SYNC_DUPLICATE_RESULT shots=%d results=%s magazine=%d health=%d" % [shots.size(), str(fire_results), magazine, int(app.combat_authority.health[target])])
	if shots.size() != 1 or int(app.combat_authority.health[target]) != 66 or magazine != 5:
		_fail("duplicated action changed the outcome twice"); return
	if fire_results.size() != 2 or not bool(fire_results[0]["accepted"]) or str(fire_results[1]["reason"]) != "replay":
		_fail("the repeated action was not refused as replay"); return
	print("SYNC_DUPLICATE_OK")
	_enter("PRIVACY")
	for peer_id in peers:
		sync_request_privacy.rpc_id(int(peer_id))

func _check_privacy() -> void:
	var violations := 0
	for peer_id in reports:
		violations += int(reports[peer_id]["violations"])
	print("SYNC_PRIVACY_RESULT clients=%d violations=%d" % [reports.size(), violations])
	if violations > 0:
		_fail("private data in snapshots"); return
	print("SYNC_PRIVACY_OK")
	print("SYNC_NETWORK_SERVER_OK clients=%d profile=%s" % [peers.size(), str(app.arguments.get("sync-profile", "local"))])
	stage = "SHUTDOWN"
	app._begin_server_shutdown(app.lobby.peer_ids())

## Observadores do NetworkApp (mesmos ganchos do coordenador de combate).
func observe_server_action(peer_id: int, action: String, sequence: Variant, result: Dictionary) -> void:
	if app.mode == "server" and peer_id == actor:
		results.append({"action": action, "id": int(sequence) if typeof(sequence) == TYPE_INT else -1,
			"accepted": bool(result.get("accepted", false)), "reason": str(result.get("reason", ""))})

func observe_server_shot(event: Dictionary) -> void:
	if app.mode == "server" and int(event.get("shooter_peer_id", 0)) == actor:
		shots.append(event)

func observe_private_emission(_peer_id: int, _state: Dictionary) -> void:
	pass

func observe_server_elimination(_peer_id: int) -> void:
	pass

func cancel_pending(_reason: String) -> void:
	pass

# --- Cliente ---------------------------------------------------------------------

var _view_peer := 0
var _view_stage := ""
var _shots_stage := ""
var _shots_expected := 0

func observe_client_event(kind: String, payload: Variant = null) -> void:
	if app.mode == "server":
		return
	if kind == "snapshot":
		var snapshot: Dictionary = payload
		for player in snapshot.get("players", []):
			for key in (player as Dictionary).keys():
				if str(key) not in PUBLIC_SNAPSHOT_KEYS:
					snapshot_violations += 1
			last_views[int((player as Dictionary).get("peer_id", 0))] = player
		var ack: Dictionary = snapshot.get("ack", {})
		if not ack.is_empty() and ack.keys() != ACK_KEYS:
			snapshot_violations += 1
	elif kind == "shot":
		shots_seen += 1

func _client_tick() -> void:
	if not hello_sent and app.joined and app.client_connected:
		hello_sent = true
		sync_hello.rpc_id(1, DisplayServer.get_name() != "headless")
	if not running_stage.is_empty() and app.test_script.is_empty():
		if script_done_msec == 0:
			script_done_msec = Time.get_ticks_msec()
			script_last_seq = app.prediction.next_seq - 1
		# O cliente comanda todo tick, então sempre há comandos ociosos em
		# trânsito: o relato espera o ACK do último comando do roteiro.
		elif Time.get_ticks_msec() - script_done_msec > SETTLE_MSEC and app.prediction.last_ack >= script_last_seq:
			var prediction: PlayerPrediction = app.prediction
			var worst := 0.0
			for value in prediction.ack_errors_position: worst = maxf(worst, float(value))
			sync_report.rpc_id(1, running_stage, {"position": prediction.state["position"], "yaw": float(prediction.state["yaw"]),
				"pitch": float(prediction.state["pitch"]), "corrections_small": prediction.corrections_small,
				"corrections_large": prediction.corrections_large, "recoveries": prediction.recoveries,
				"epoch_resets": prediction.epoch_resets, "ack_error": "%.6f" % worst})
			print("NET_STATS id=%s stage=%s %s" % [app.client_label, running_stage, app.net_stats.summary(prediction, app.arena_view.interpolator if app.arena_view != null else null)])
			if app.test_net_peer != null:
				print("TEST_NET_APPLIED id=%s %s" % [app.client_label, app.test_net_peer.call("summary")])
			running_stage = ""
	if not _view_stage.is_empty() and Time.get_ticks_msec() - script_done_msec > SETTLE_MSEC and script_done_msec > 0:
		pass
	if not _view_stage.is_empty() and _view_ready():
		var view: Dictionary = last_views[_view_peer]
		sync_report.rpc_id(1, _view_stage, {"position": view["position"], "yaw": float(view["yaw"]), "pitch": float(view.get("pitch", 0.0))})
		_view_stage = ""
	if not _shots_stage.is_empty() and shots_seen >= _shots_expected:
		# Espera um pouco por duplicatas antes de relatar.
		if _shots_stage_since == 0:
			_shots_stage_since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _shots_stage_since > 600:
			sync_report.rpc_id(1, _shots_stage, {"shots": shots_seen})
			_shots_stage = ""

var _shots_stage_since := 0
var script_last_seq := 0
var _view_started_msec := 0
var _view_last_change_msec := 0
var _view_last_position := Vector3.INF

## O observador relata a visão oficial do ator quando ela para de mudar.
func _view_ready() -> bool:
	if not last_views.has(_view_peer):
		return false
	var position: Vector3 = last_views[_view_peer]["position"]
	var now := Time.get_ticks_msec()
	if position != _view_last_position:
		_view_last_position = position
		_view_last_change_msec = now
		return false
	return now - _view_started_msec > 3000 and now - _view_last_change_msec > 1500

@rpc("authority", "call_remote", "reliable")
func sync_run_script(stage_name: String, script: Array, stall: bool) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	running_stage = stage_name
	script_done_msec = 0
	app.test_script = script.duplicate(true)
	if stall and app.test_net_peer != null:
		get_tree().create_timer(0.8).timeout.connect(func():
			app.test_net_peer.call("trigger_stall", 400.0)
			print("SYNC_STALL_TRIGGERED id=%s ms=400" % app.client_label))
	print("SYNC_SCRIPT_STARTED id=%s stage=%s ticks=%d" % [app.client_label, stage_name, script.size()])

## Cliente gráfico: grava cada quadro desenhado (PNG) e a telemetria da
## câmera e do corpo observado por `seconds`. Com `follow`, seleciona antes o
## alvo autorizado do espectador.
@rpc("authority", "call_remote", "reliable")
func sync_visual_record(stage_name: String, seconds: float, follow: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	spectate_peer = follow
	recording_stage = stage_name
	recording_until_msec = Time.get_ticks_msec() + int(seconds * 1000.0)
	recording_frame = 0
	recording_rows = ["usec,stage,cam_x,cam_y,cam_z,yaw,pitch,subject,subject_x,subject_z,subject_yaw,head"]
	print("SYNC_VISUAL_RECORD id=%s stage=%s seconds=%.1f" % [app.client_label, stage_name, seconds])

func _on_frame_drawn() -> void:
	if recording_stage.is_empty() or app.arena_view == null:
		return
	if spectate_peer != 0 and app.arena_view.spectator_target_peer_id != spectate_peer:
		var index: int = app.local_spectator_targets.find(spectate_peer)
		if index >= 0:
			app.local_spectator_index = index
			app.arena_view.set_spectator_target(spectate_peer)
			app._update_round_hud()
		else:
			return
	var arena: ArenaView = app.arena_view
	var subject := 0
	for peer_id in arena.avatars:
		if (arena.avatars[peer_id] as Node3D).visible and int(peer_id) != spectate_peer:
			if subject == 0 or (arena.avatars[peer_id] as Node3D).global_position.distance_to(arena.camera.global_position) < (arena.avatars[subject] as Node3D).global_position.distance_to(arena.camera.global_position):
				subject = int(peer_id)
	var subject_position := Vector3.ZERO
	var subject_yaw := 0.0
	var head := 0.0
	if subject != 0:
		subject_position = (arena.avatars[subject] as Node3D).global_position
		subject_yaw = (arena.avatars[subject] as Node3D).rotation.y
		var animator: CharacterAnimator = arena.animators.get(subject)
		if animator != null and animator.rig.get("head") != null:
			head = (animator.rig["head"] as Node3D).rotation.x
	var cam := arena.camera.global_position
	recording_rows.append("%d,%s,%.4f,%.4f,%.4f,%.5f,%.5f,%d,%.4f,%.4f,%.5f,%.4f" % [Time.get_ticks_usec(), recording_stage,
		cam.x, cam.y, cam.z, arena.player_rig.rotation.y, arena.camera.rotation.x, subject, subject_position.x, subject_position.z, subject_yaw, head])
	# `--sync-visual-every=N` grava um quadro a cada N; `--sync-visual-format=jpg`
	# economiza disco em sessões longas (a telemetria CSV continua quadro a quadro).
	var every := maxi(1, NetworkConfig.integer_argument(app.arguments, "sync-visual-every", 1))
	if not visual_out.is_empty() and recording_frame % every == 0:
		var image := get_viewport().get_texture().get_image()
		if str(app.arguments.get("sync-visual-format", "png")) == "jpg":
			image.save_jpg("%s/%s_%s_%04d.jpg" % [visual_out, app.client_label, recording_stage, recording_frame / every], 0.85)
		else:
			image.save_png("%s/%s_%s_%04d.png" % [visual_out, app.client_label, recording_stage, recording_frame])
	recording_frame += 1
	if Time.get_ticks_msec() >= recording_until_msec:
		if not visual_out.is_empty():
			var file := FileAccess.open("%s/%s_%s.csv" % [visual_out, app.client_label, recording_stage], FileAccess.WRITE)
			file.store_string("\n".join(recording_rows))
			file.close()
		print("SYNC_VISUAL_RECORDED id=%s stage=%s frames=%d" % [app.client_label, recording_stage, recording_frame])
		sync_report.rpc_id(1, _visual_stage_for(recording_stage), {"frames": recording_frame})
		recording_stage = ""
		spectate_peer = 0

static func _visual_stage_for(recording: String) -> String:
	if recording.begins_with("walk"): return "VISUAL_WALK"
	if recording.begins_with("spect"): return "VISUAL_SPECTATOR"
	return "VISUAL_RETURN"

@rpc("authority", "call_remote", "reliable")
func sync_request_view(stage_name: String, peer_id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_view_stage = stage_name
	_view_peer = peer_id
	_view_started_msec = Time.get_ticks_msec()

@rpc("authority", "call_remote", "reliable")
func sync_request_shots(stage_name: String, expected: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_shots_stage = stage_name
	_shots_expected = expected
	_shots_stage_since = 0
	shots_seen = 0

@rpc("authority", "call_remote", "reliable")
func sync_request_privacy() -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	sync_report.rpc_id(1, "PRIVACY", {"violations": snapshot_violations})

@rpc("any_peer", "call_remote", "reliable")
func sync_hello(graphical: bool) -> void:
	if multiplayer.is_server() and graphical:
		graphical_peers[multiplayer.get_remote_sender_id()] = true

@rpc("any_peer", "call_remote", "reliable")
func sync_report(stage_name: String, data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if stage_name != stage or sender not in peers:
		return
	reports[sender] = data
