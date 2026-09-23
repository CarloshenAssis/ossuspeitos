extends Node

var arguments: Dictionary
var mode := ""
var lobby := LobbyRegistry.new()
var round_authority: RoundAuthority
var client_label := ""
var expected_clients := 0
var joined := false
var client_connected := false
var started_at_msec := 0
var completion_sent := false
var shutdown_prepare_received := false
var shutting_down := false
var completed_peers: Dictionary = {}
var authoritative_world: AuthoritativeWorld
var combat_authority: CombatAuthority
var arena_view: ArenaView
var snapshot_accumulator := 0.0
var input_accumulator := 0.0
var input_sequence := 0
var pending_yaw_delta := 0.0
var client_spawn_known := false
var client_spawn_position := Vector3.ZERO
var client_movement_observed := false
var impossible_input_rejected_peers: Dictionary = {}
var test_direction := Vector2.ZERO
var test_roster_ready := false
var shutdown_expected_peers: Dictionary = {}
var shutdown_ready_peers: Dictionary = {}
var server_peer_closing := false
var server_terminal := false
var shutdown_prepare_timer: Timer
var closed_session_count := 0
var round_stop_after := 0
var round_expect_late_joins := 0
var round_ack_peers: Dictionary = {}
var round_late_join_peers: Dictionary = {}
var round_test_mode := false
var round_hud: Node
var local_role := Role.NONE
var local_round_id := 0
var local_role_receipts := 0
var local_round_public: Dictionary = {}
var local_roster_peers: Array = []
var local_result_round_id := 0
var role_spoof_attempted := false
var ack_replay_attempted := false
var combat_sequence := {"pickup": 0, "fire": 0, "reload": 0}
var local_combat_state: Dictionary = {}
var local_spectator_targets: Array = []
var local_spectator_index := -1
var local_eliminated := false
var local_final_reveal: Dictionary = {}
var combat_network_test: Node
var spectator_reveal_test_mode := false
var spectator_test_started := false
var spectator_test_dead_peer := 0
var spectator_test_observed := false
var spectator_test_movement_blocked := false
var spectator_test_follow_confirmed := false
var spectator_test_blocked: Dictionary = {}
var spectator_reveal_acks: Dictionary = {}

func _ready() -> void:
	arguments = NetworkConfig.user_arguments()
	mode = str(arguments.get("mode", ""))
	if mode.is_empty() and OS.has_feature("visual_demo"):
		mode = "demo"
	if mode == "server":
		start_server()
	elif mode == "client":
		start_client()
	elif mode == "demo":
		start_demo()
	else:
		fail("MODE_REQUIRED use -- --mode=server, -- --mode=client or -- --mode=demo")

func start_demo() -> void:
	var demo := VisualDemo.new()
	demo.test_mode = str(arguments.get("demo-test", "false")) == "true"
	add_child(demo)

func start_server() -> void:
	spectator_reveal_test_mode = NetworkConfig.bool_argument(arguments, "spectator-reveal-test")
	authoritative_world = AuthoritativeWorld.new()
	_start_round_authority()
	_start_combat_network_test()
	shutdown_prepare_timer = Timer.new()
	shutdown_prepare_timer.one_shot = true
	shutdown_prepare_timer.timeout.connect(_server_shutdown_timeout)
	add_child(shutdown_prepare_timer)
	var port := configured_port()
	var bind_address := str(arguments.get("bind", NetworkConfig.DEFAULT_BIND_ADDRESS))
	var peer := WebSocketServerTransport.listen(port, bind_address)
	if peer == null:
		fail("SERVER_ERROR unable_to_listen")
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	# Sem relay: um cliente não consegue endereçar RPC a outro cliente, portanto
	# não existe caminho para se passar pelo servidor e entregar um papel.
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).server_relay = false
	multiplayer.multiplayer_peer = peer
	# Marcador derivado do estado real: o servidor headless não cria HUD,
	# câmera, cápsulas nem qualquer outro nó de apresentação.
	print("SERVER_UI hud=%s arena=%s display=%s" % [
		str(round_hud != null), str(arena_view != null), DisplayServer.get_name()])
	print("SERVER_READY address=%s port=%d" % [bind_address, port])

func _start_round_authority() -> void:
	round_authority = RoundAuthority.new(lobby, NetworkConfig.integer_argument(arguments, "round-seed", 0))
	round_authority.configure(
		NetworkConfig.float_argument(arguments, "countdown-seconds", RoundRules.COUNTDOWN_SECONDS),
		NetworkConfig.float_argument(arguments, "round-end-delay-seconds", RoundRules.ROUND_END_DELAY_SECONDS))
	round_stop_after = NetworkConfig.integer_argument(arguments, "stop-after-round-active", 0)
	round_expect_late_joins = NetworkConfig.integer_argument(arguments, "expect-late-joins", 0)
	round_authority.state_changed.connect(_on_round_state_changed)
	round_authority.roles_ready.connect(_on_round_roles_ready)
	round_authority.alive_changed.connect(_on_round_alive_changed)
	round_authority.round_ended.connect(_on_round_ended)
	round_authority.reveal_ready.connect(_on_round_reveal_ready)
	round_authority.spectator_targets_changed.connect(_on_spectator_targets_changed)
	round_authority.round_reset.connect(_on_round_reset)
	round_authority.invalid_transition.connect(_on_round_invalid_transition)
	combat_authority = CombatAuthority.new(round_authority, authoritative_world)
	combat_authority.pickups_changed.connect(_on_pickups_changed)
	combat_authority.private_state_changed.connect(_on_combat_private_state_changed)
	combat_authority.shot_resolved.connect(_on_shot_resolved)
	combat_authority.player_eliminated.connect(_on_combat_player_eliminated)

func start_client() -> void:
	client_label = str(arguments.get("client-id", "client"))
	expected_clients = NetworkConfig.integer_argument(arguments, "expect-clients", 0)
	round_test_mode = NetworkConfig.bool_argument(arguments, "round-test")
	spectator_reveal_test_mode = NetworkConfig.bool_argument(arguments, "spectator-reveal-test")
	if spectator_reveal_test_mode: round_test_mode = true
	_start_combat_network_test()
	started_at_msec = Time.get_ticks_msec()
	var url := str(arguments.get("url", "ws://%s:%d" % [NetworkConfig.DEFAULT_HOST, configured_port()]))
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var peer := WebSocketClientTransport.connect_to_url(url)
	if peer == null:
		fail("CLIENT_ERROR id=%s unable_to_connect" % client_label)
		return
	multiplayer.multiplayer_peer = peer
	if DisplayServer.get_name() != "headless":
		arena_view = ArenaView.new()
		add_child(arena_view)
		_start_round_hud()
	print("CLIENT_UI id=%s hud=%s arena=%s display=%s" % [
		client_label, str(round_hud != null), str(arena_view != null), DisplayServer.get_name()])
	print("CLIENT_CONNECTING id=%s url=%s" % [client_label, url])

## O HUD só existe no cliente gráfico. A cena nem é carregada no headless,
## portanto o servidor nunca instancia interface.
func _start_round_hud() -> void:
	var scene := load("res://client/round_hud.tscn") as PackedScene
	if scene == null:
		return
	round_hud = scene.instantiate()
	add_child(round_hud)
	_update_round_hud()

func configured_port() -> int:
	var fallback := NetworkConfig.DEFAULT_PORT
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		fallback = env_port.to_int()
	return NetworkConfig.integer_argument(arguments, "port", fallback)

func _start_combat_network_test() -> void:
	if not NetworkConfig.bool_argument(arguments, "combat-test"):
		return
	var script := load("res://tests/combat_network_coordinator.gd") as GDScript
	if script == null:
		fail("COMBAT_TEST_ERROR coordinator_missing")
		return
	combat_network_test = script.new()
	combat_network_test.name = "CombatNetworkCoordinator"
	add_child(combat_network_test)

func _process(_delta: float) -> void:
	if mode != "client":
		return
	if not joined and Time.get_ticks_msec() - started_at_msec > int(NetworkConfig.CONNECT_TIMEOUT_SECONDS * 1000.0):
		fail("CLIENT_TIMEOUT id=%s" % client_label)
	if NetworkConfig.should_poll_human_input(
			joined, expected_clients, round_test_mode,
		combat_network_test != null, arena_view != null) and _client_can_gameplay():
		input_accumulator += _delta
		if input_accumulator >= 0.05:
			input_accumulator = 0.0
			_send_input(Input.get_vector("move_left", "move_right", "move_forward", "move_backward"), pending_yaw_delta)
			pending_yaw_delta = 0.0

func _physics_process(delta: float) -> void:
	if mode != "server" or shutting_down or authoritative_world == null:
		return
	var now_msec := Time.get_ticks_msec()
	authoritative_world.step(delta, now_msec)
	if combat_authority != null:
		combat_authority.tick(now_msec)
	if round_authority != null:
		round_authority.tick(now_msec)
		if round_authority.consume_countdown_tick(now_msec):
			_publish_round_state()
	snapshot_accumulator += delta
	if snapshot_accumulator >= 0.05:
		snapshot_accumulator = 0.0
		world_snapshot.rpc(authoritative_world.snapshot())

func _unhandled_input(event: InputEvent) -> void:
	if mode == "client" and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pending_yaw_delta = clampf(pending_yaw_delta - event.relative.x * 0.0025, -MovementRules.MAX_YAW_DELTA, MovementRules.MAX_YAW_DELTA)
	if mode != "client" or not joined or shutdown_prepare_received or arena_view == null:
		return
	if not _client_can_gameplay():
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_Q: _cycle_spectator(-1)
			elif event.keycode == KEY_E: _cycle_spectator(1)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		combat_sequence["fire"] += 1
		request_fire.rpc_id(1, combat_sequence["fire"], arena_view.camera_origin(), arena_view.camera_direction())
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		combat_sequence["reload"] += 1
		request_reload.rpc_id(1, combat_sequence["reload"])
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var pickup_id: String = arena_view.nearest_available_pickup()
		if not pickup_id.is_empty():
			combat_sequence["pickup"] += 1
			request_pickup.rpc_id(1, pickup_id, combat_sequence["pickup"])

func _on_peer_connected(peer_id: int) -> void:
	print("PEER_CONNECTED peer_id=%d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if server_terminal or not lobby.has(peer_id):
		return
	if authoritative_world != null:
		authoritative_world.remove_player(peer_id)
	if combat_authority != null:
		combat_authority.clear_player(peer_id)
	# A autoridade remove a sessão do lobby e aplica a política da fase atual:
	# cancelar o countdown, marcar o participante como eliminado ou apenas
	# atualizar o lobby. O papel do jogador que saiu nunca é anunciado.
	if round_authority != null:
		round_authority.leave(peer_id, Time.get_ticks_msec())
	else:
		lobby.remove(peer_id)
	print("CLIENT_LEFT peer_id=%d count=%d" % [peer_id, lobby.size()])
	if shutting_down:
		return
	completed_peers.erase(peer_id)
	impossible_input_rejected_peers.erase(peer_id)
	round_ack_peers.erase(peer_id)
	round_late_join_peers.erase(peer_id)
	publish_client_count()

func _on_connected_to_server() -> void:
	client_connected = true
	print("CLIENT_CONNECTED id=%s peer_id=%d" % [client_label, multiplayer.get_unique_id()])
	request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, client_label)

func _on_connection_failed() -> void:
	client_connected = false
	joined = false
	fail("CLIENT_CONNECTION_FAILED id=%s" % client_label)

func _on_server_disconnected() -> void:
	client_connected = false
	joined = false
	if shutdown_prepare_received:
		print("CLIENT_SHUTDOWN_COMPLETE id=%s" % client_label)
		get_tree().quit(0)
		return
	if combat_network_test != null:
		combat_network_test.call("cancel_pending", "server_disconnected")
		fail("CLIENT_SERVER_DISCONNECTED id=%s" % client_label)
		return
	if not joined or expected_clients > 0:
		fail("CLIENT_SERVER_DISCONNECTED id=%s" % client_label)

@rpc("any_peer", "call_remote", "reliable")
func request_join(protocol_version: int, requested_label: String) -> void:
	if not multiplayer.is_server() or shutting_down:
		return
	# A identidade de rede vem sempre do remetente da RPC, nunca de um argumento.
	var sender := multiplayer.get_remote_sender_id()
	if protocol_version != NetworkConfig.PROTOCOL_VERSION:
		join_rejected.rpc_id(sender, "protocol_version")
		return
	var reason := lobby.validate_join(sender, requested_label)
	if not reason.is_empty():
		join_rejected.rpc_id(sender, reason)
		return
	var state := authoritative_world.add_player(sender)
	if state.is_empty():
		join_rejected.rpc_id(sender, "room_unavailable")
		return
	var join_reason := round_authority.join(sender, requested_label, Time.get_ticks_msec())
	if not join_reason.is_empty():
		authoritative_world.remove_player(sender)
		join_rejected.rpc_id(sender, join_reason)
		return
	print("CLIENT_JOINED id=%s peer_id=%d count=%d" % [lobby.label_for(sender), sender, lobby.size()])
	var spawn: Vector3 = state["position"]
	print("PLAYER_SPAWNED peer_id=%d position=%.2f,%.2f,%.2f" % [sender, spawn.x, spawn.y, spawn.z])
	if round_authority.is_waiting_for_next_round(sender):
		round_late_join_peers[sender] = true
		print("ROUND_LATE_JOIN peer_id=%d round_id=%d count=%d" % [
			sender, round_authority.round_id, round_late_join_peers.size()])
	join_accepted.rpc_id(sender, sender)
	publish_client_count()
	world_snapshot.rpc(authoritative_world.snapshot())
	_publish_round_state(sender)
	_maybe_finish_round_privacy_test()

@rpc("authority", "call_remote", "reliable")
func join_accepted(peer_id: int) -> void:
	joined = true
	if arena_view != null:
		arena_view.local_peer_id = peer_id
	print("JOIN_ACCEPTED id=%s peer_id=%d" % [client_label, peer_id])

@rpc("authority", "call_remote", "reliable")
func join_rejected(reason: String) -> void:
	fail("JOIN_REJECTED id=%s reason=%s" % [client_label, reason])

func publish_client_count() -> void:
	if shutting_down:
		return
	client_count_changed.rpc(lobby.size())
	_publish_round_state()

@rpc("authority", "call_remote", "reliable")
func client_count_changed(count: int) -> void:
	print("CLIENT_COUNT id=%s count=%d" % [client_label, count])
	if expected_clients > 0 and count >= expected_clients:
		test_roster_ready = true
		_try_start_test_movement()

func _try_start_test_movement() -> void:
	if not test_roster_ready or not client_spawn_known or input_sequence != 0:
		return
	if expected_clients > 0:
		var client_number := int(client_label.trim_prefix("client-"))
		var directions := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
		test_direction = directions[(client_number - 1) % directions.size()]
		if client_label == "client-1":
			_send_input(Vector2(99.0, 0.0), 0.0)
		else:
			_send_input(test_direction, 0.0)

func _send_input(move: Vector2, yaw_delta: float) -> void:
	if shutdown_prepare_received or not client_connected:
		return
	input_sequence += 1
	submit_input.rpc_id(1, input_sequence, move, yaw_delta)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(sequence: int, move: Vector2, yaw_delta: float) -> void:
	if not multiplayer.is_server() or shutting_down:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not lobby.has(sender):
		return
	var movement_test := NetworkConfig.integer_argument(arguments, "stop-after-clients", 0) > 0
	if not movement_test and (round_authority.state != RoundState.ACTIVE or not round_authority.is_participant(sender) or not round_authority.is_alive(sender)):
		if spectator_reveal_test_mode and sender == spectator_test_dead_peer \
				and round_authority.state == RoundState.ACTIVE and not round_authority.is_alive(sender):
			spectator_test_movement_blocked = true
			_maybe_finish_spectator_probe()
		return
	var reason := authoritative_world.accept_input(sender, sequence, move, yaw_delta, Time.get_ticks_msec())
	if not reason.is_empty():
		print("INPUT_REJECTED peer_id=%d reason=%s" % [sender, reason])
		input_rejected.rpc_id(sender, reason, sequence)
		if reason == "move_magnitude":
			impossible_input_rejected_peers[sender] = true
		return
	var state: Dictionary = authoritative_world.states[sender]
	if not bool(state["movement_logged"]):
		state["movement_logged"] = true
		print("MOVEMENT_AUTHORIZED peer_id=%d" % sender)

@rpc("authority", "call_remote", "reliable")
func input_rejected(reason: String, _sequence: int) -> void:
	if expected_clients > 0 and client_label == "client-1" and reason == "move_magnitude" and not client_movement_observed:
		print("CLIENT_IMPOSSIBLE_INPUT_REJECTED id=%s" % client_label)
		_send_input(test_direction, 0.0)

@rpc("authority", "call_remote", "unreliable_ordered")
func world_snapshot(states: Array) -> void:
	if multiplayer.is_server() or shutdown_prepare_received:
		return
	if arena_view != null:
		arena_view.apply_snapshot(states)
	if spectator_reveal_test_mode and local_eliminated and not spectator_test_follow_confirmed:
		for raw_spectator_state in states:
			if int((raw_spectator_state as Dictionary).get("peer_id", 0)) == _spectator_target():
				spectator_test_follow_confirmed = true
				print("SPECTATOR_FOLLOW_OK id=%s" % client_label)
				_send_input(Vector2.RIGHT, 0.0)
				combat_sequence["pickup"] += 1
				request_pickup.rpc_id(1, "weapon_0", combat_sequence["pickup"])
				combat_sequence["fire"] += 1
				request_fire.rpc_id(1, combat_sequence["fire"], Vector3.ZERO, Vector3.FORWARD)
				combat_sequence["reload"] += 1
				request_reload.rpc_id(1, combat_sequence["reload"])
				spectator_test_followed.rpc_id(1)
				break
	var own_id := multiplayer.get_unique_id()
	for raw_state in states:
		var state: Dictionary = raw_state
		if int(state["peer_id"]) != own_id:
			continue
		var official_position: Vector3 = state["position"]
		if not client_spawn_known:
			client_spawn_known = true
			client_spawn_position = official_position
			print("CLIENT_SPAWN id=%s position=%.2f,%.2f,%.2f" % [client_label, official_position.x, official_position.y, official_position.z])
			_try_start_test_movement()
		elif expected_clients > 0 and not client_movement_observed and official_position.distance_to(client_spawn_position) >= MovementRules.TEST_MOVEMENT_DISTANCE:
			client_movement_observed = true
			_send_input(Vector2.ZERO, 0.0)
			print("CLIENT_MOVEMENT_OBSERVED id=%s" % client_label)
			completion_sent = true
			print("CLIENT_TEST_OK id=%s" % client_label)
			client_test_completed.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func client_test_completed() -> void:
	if not multiplayer.is_server() or shutting_down:
		return
	var sender := multiplayer.get_remote_sender_id()
	var stop_after := NetworkConfig.integer_argument(arguments, "stop-after-clients", 0)
	if stop_after <= 0 or not lobby.has(sender) or completed_peers.has(sender):
		return
	if not authoritative_world.has_moved(sender):
		print("TEST_CONFIRMATION_REJECTED peer_id=%d reason=not_moved" % sender)
		return
	completed_peers[sender] = true
	print("CLIENT_TEST_CONFIRMED peer_id=%d count=%d" % [sender, completed_peers.size()])
	if completed_peers.size() >= stop_after and not impossible_input_rejected_peers.is_empty() and authoritative_world.all_positions_distinct(completed_peers.keys()):
		_report_movement_test()
		_begin_server_shutdown(completed_peers.keys())

func _report_movement_test() -> void:
	var observed_max_speed := 0.0
	for peer_id in completed_peers:
		var state: Dictionary = authoritative_world.states[peer_id]
		var position: Vector3 = state["position"]
		var velocity: Vector3 = state["velocity"]
		var speed := velocity.length()
		observed_max_speed = maxf(observed_max_speed, speed)
		print("PLAYER_STATE peer_id=%d position=%.3f,%.3f,%.3f speed=%.3f" % [peer_id, position.x, position.y, position.z, speed])
	print("SERVER_MOVEMENT_TEST_OK players=%d max_speed=%.3f rejected_impossible=%d" % [completed_peers.size(), observed_max_speed, impossible_input_rejected_peers.size()])

func _begin_server_shutdown(peer_ids: Array) -> void:
	if shutting_down:
		return
	shutting_down = true
	for peer_id in peer_ids:
		shutdown_expected_peers[int(peer_id)] = true
	print("SERVER_TEST_OK clients=%d" % shutdown_expected_peers.size())
	for peer_id in shutdown_expected_peers:
		shutdown_prepare.rpc_id(peer_id)
	shutdown_prepare_timer.start(2.0)

@rpc("authority", "call_remote", "reliable")
func shutdown_prepare() -> void:
	if shutdown_prepare_received:
		return
	shutdown_prepare_received = true
	print("CLIENT_SHUTDOWN_PREPARE id=%s" % client_label)
	shutdown_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func shutdown_ready() -> void:
	if not multiplayer.is_server() or not shutting_down or server_peer_closing:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not shutdown_expected_peers.has(sender) or not lobby.has(sender) or shutdown_ready_peers.has(sender):
		return
	shutdown_ready_peers[sender] = true
	print("CLIENT_SHUTDOWN_READY peer_id=%d count=%d" % [sender, shutdown_ready_peers.size()])
	if shutdown_ready_peers.size() >= shutdown_expected_peers.size():
		_cancel_shutdown_prepare_timeout()
		print("SERVER_SHUTDOWN_READY clients=%d" % shutdown_ready_peers.size())
		if combat_network_test != null: print("COMBAT_SHUTDOWN_READY clients=%d" % shutdown_ready_peers.size())
		call_deferred("_close_server_peer")

func _cancel_shutdown_prepare_timeout() -> void:
	if shutdown_prepare_timer == null:
		return
	shutdown_prepare_timer.stop()

func _close_server_peer() -> void:
	if server_peer_closing or server_terminal:
		return
	server_peer_closing = true
	server_terminal = true
	closed_session_count = shutdown_expected_peers.size()
	if round_authority != null:
		round_authority.clear()
	lobby.clear()
	if authoritative_world != null:
		authoritative_world.clear()
	if combat_authority != null:
		combat_authority.clear_round()
	completed_peers.clear()
	impossible_input_rejected_peers.clear()
	shutdown_ready_peers.clear()
	shutdown_expected_peers.clear()
	round_ack_peers.clear()
	round_late_join_peers.clear()
	multiplayer.multiplayer_peer.close()
	print("SERVER_SHUTDOWN_COMPLETE closed=%d" % closed_session_count)
	if combat_network_test != null: print("COMBAT_SHUTDOWN_COMPLETE clients=%d" % closed_session_count)
	get_tree().quit(0)

func _server_shutdown_timeout() -> void:
	if server_terminal or shutdown_ready_peers.size() >= shutdown_expected_peers.size():
		return
	print("SERVER_SHUTDOWN_TIMEOUT ready=%d remaining=%d" % [shutdown_ready_peers.size(), lobby.size()])
	get_tree().quit(1)

# --- Ciclo de partida --------------------------------------------------------
#
# Mensagens públicas: `round_public_state` e `round_roster`, em broadcast.
# Mensagem privada: `round_private_role`, sempre por `rpc_id` ao próprio dono.
# Estado interno do servidor (mapa de papéis, seed, avaliação de vitória)
# jamais sai de `RoundAuthority`.

func _on_round_state_changed(state: int, round_id: int) -> void:
	print("ROUND_STATE state=%s round_id=%d players=%d participants=%d" % [
		RoundState.to_label(state), round_id, lobby.size(), round_authority.participants.size()])
	_publish_round_state()
	if spectator_reveal_test_mode and state == RoundState.COUNTDOWN \
			and spectator_reveal_acks.size() == round_stop_after:
		print("ROUND_REVEAL_CLEARED_OK")
		_begin_server_shutdown(lobby.peer_ids())

func _on_round_roles_ready(round_id: int, participant_ids: Array) -> void:
	combat_authority.begin_round(round_id, participant_ids)
	# Somente a contagem agregada vai para o log: nunca a associação peer/papel.
	var counts := round_authority.role_counts()
	print("ROUND_ROLE_COUNTS assassin=%d detective=%d victim=%d" % [
		int(counts["assassin"]), int(counts["detective"]), int(counts["victim"])])
	var delivered := 0
	for raw_peer_id in participant_ids:
		var peer_id := int(raw_peer_id)
		# O papel só sai se pertencer ao destinatário, ele estiver na rodada
		# ativa e a sessão continuar conectada.
		if not round_authority.can_deliver_role(peer_id):
			continue
		var role := round_authority.get_role_for_peer(peer_id)
		round_private_role.rpc_id(peer_id, round_id, role)
		delivered += 1
	print("ROUND_ROLES_DELIVERED round_id=%d peers=%d" % [round_id, delivered])

func _on_round_alive_changed(round_id: int, peer_id: int, alive: bool) -> void:
	if not alive and authoritative_world.states.has(peer_id):
		authoritative_world.states[peer_id]["input"] = Vector2.ZERO
		authoritative_world.states[peer_id]["velocity"] = Vector3.ZERO
	print("ROUND_ALIVE_CHANGED round_id=%d peer_id=%d alive=%s" % [round_id, peer_id, str(alive)])
	_publish_round_state()

func _on_spectator_targets_changed(changed_round_id: int) -> void:
	if not multiplayer.is_server() or shutting_down or round_authority == null \
			or round_authority.state != RoundState.ACTIVE or round_authority.round_id != changed_round_id:
		return
	for raw_peer_id in round_authority.participants.keys():
		var peer_id := int(raw_peer_id)
		if lobby.has(peer_id) and not round_authority.is_alive(peer_id):
			var spectator_state := round_authority.get_spectator_state(peer_id)
			if not spectator_state.is_empty():
				round_private_spectator_targets.rpc_id(peer_id, spectator_state)

func _on_round_ended(round_id: int, winning_team: int, reason: String) -> void:
	# `state_changed` já publicou o payload com o resultado; aqui só registramos.
	print("ROUND_RESULT round_id=%d team=%s reason=%s" % [
		round_id, Role.team_to_label(winning_team), reason])
	call_deferred("_clear_combat_round_if_ended", round_id)

func _on_round_reveal_ready(reveal_round_id: int, result: Dictionary) -> void:
	if not multiplayer.is_server() or shutting_down or round_authority.state != RoundState.ENDED \
			or round_authority.round_id != reveal_round_id:
		return
	var delivered := 0
	for raw_peer_id in round_authority.participants.keys():
		var peer_id := int(raw_peer_id)
		if not lobby.has(peer_id): continue
		round_final_reveal.rpc_id(peer_id, result)
		delivered += 1
	print("ROUND_REVEAL_SENT round_id=%d peers=%d" % [reveal_round_id, delivered])

func _clear_combat_round_if_ended(ended_round_id: int) -> void:
	if combat_authority != null and round_authority.state == RoundState.ENDED \
			and round_authority.round_id == ended_round_id and combat_authority.active_round_id == ended_round_id:
		combat_authority.clear_round()

func _on_round_reset(round_id: int) -> void:
	round_ack_peers.clear()
	round_late_join_peers.clear()
	print("ROUND_RESET round_id=%d players=%d" % [round_id, lobby.size()])

func _on_round_invalid_transition(from_state: int, to_state: int) -> void:
	print("ROUND_TRANSITION_REJECTED from=%s to=%s" % [
		RoundState.to_label(from_state), RoundState.to_label(to_state)])

## Publica estado público e roster seguro. `target_peer_id` > 0 envia apenas ao
## recém-chegado, para que ele receba a fase corrente sem esperar a próxima
## mudança.
func _publish_round_state(target_peer_id: int = 0) -> void:
	if not multiplayer.is_server() or shutting_down or round_authority == null:
		return
	var payload := round_authority.public_state(Time.get_ticks_msec())
	var roster := round_authority.public_roster()
	if target_peer_id > 0:
		round_public_state.rpc_id(target_peer_id, payload)
		round_roster.rpc_id(target_peer_id, roster)
		return
	round_public_state.rpc(payload)
	round_roster.rpc(roster)

@rpc("authority", "call_remote", "reliable")
func round_public_state(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	local_round_public = payload
	var state := int(payload.get("state", RoundState.WAITING))
	if state == RoundState.WAITING or state == RoundState.COUNTDOWN:
		local_role = Role.NONE
		local_round_id = 0
		local_final_reveal.clear()
		local_spectator_targets.clear()
		local_spectator_index = -1
		local_eliminated = false
		if arena_view != null: arena_view.set_spectator_target(0, false)
	print("CLIENT_ROUND_STATE id=%s state=%s round_id=%d players=%d countdown=%d" % [
		client_label, RoundState.to_label(state), int(payload.get("round_id", 0)),
		int(payload.get("connected", 0)), int(payload.get("countdown_msec", 0))])
	var announced_round := int(payload.get("round_id", 0))
	if state == RoundState.ENDED and local_result_round_id != announced_round:
		local_result_round_id = announced_round
		print("CLIENT_ROUND_RESULT id=%s round_id=%d team=%s reason=%s" % [
			client_label, announced_round,
			Role.team_to_label(int(payload.get("winning_team", Role.TEAM_NONE))),
			str(payload.get("winner_reason", ""))])
	_update_round_hud()

@rpc("authority", "call_remote", "reliable")
func round_private_spectator_targets(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if payload.keys().size() != 2 or not payload.has("round_id") or not payload.has("targets") \
			or typeof(payload["round_id"]) != TYPE_INT or typeof(payload["targets"]) != TYPE_ARRAY:
		return
	var target_round_id := int(payload["round_id"])
	var targets: Array = (payload["targets"] as Array).duplicate()
	if int(local_round_public.get("state", RoundState.WAITING)) != RoundState.ACTIVE \
			or target_round_id != int(local_round_public.get("round_id", 0)):
		return
	var safe: Array = []
	var own_id := multiplayer.get_unique_id()
	for raw_target in targets:
		if typeof(raw_target) != TYPE_INT or int(raw_target) == own_id \
				or int(raw_target) not in local_roster_peers or int(raw_target) in safe:
			continue
		safe.append(int(raw_target))
	local_spectator_targets = safe
	local_eliminated = true
	local_spectator_index = 0 if not safe.is_empty() else -1
	if arena_view != null:
		arena_view.set_spectator_target(int(safe[0]) if not safe.is_empty() else 0)
	print("SPECTATOR_TARGETS_PRIVATE_OK id=%s targets=%d" % [client_label, safe.size()])
	_update_round_hud()

@rpc("authority", "call_remote", "reliable")
func round_final_reveal(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	var expected_round := int(local_round_public.get("round_id", 0))
	if int(local_round_public.get("state", RoundState.WAITING)) != RoundState.ENDED \
			or int(payload.get("round_id", 0)) != expected_round or expected_round <= 0 \
			or local_final_reveal.has("round_id"):
		return
	var allowed := ["round_id", "winner", "reason", "players"]
	if payload.keys().size() != allowed.size():
		return
	for key in payload.keys():
		if str(key) not in allowed: return
	if typeof(payload.get("round_id")) != TYPE_INT:
		return
	var players: Variant = payload.get("players", [])
	if typeof(players) != TYPE_ARRAY: return
	for raw_player in players:
		if typeof(raw_player) != TYPE_DICTIONARY: return
		var player: Dictionary = raw_player
		if player.keys().size() != 2 or not player.has("peer_id") or not player.has("role") \
				or typeof(player["peer_id"]) != TYPE_INT or typeof(player["role"]) != TYPE_STRING \
				or str(player["role"]) not in ["ASSASSIN", "DETECTIVE", "VICTIM"]: return
	if typeof(payload.get("winner")) != TYPE_STRING \
			or str(payload["winner"]) not in ["ASSASSIN", "INNOCENTS"] \
			or typeof(payload.get("reason")) != TYPE_STRING:
		return
	local_final_reveal = payload.duplicate(true)
	print("ROUND_REVEAL_OK players=%d" % players.size())
	print("ROUND_REVEAL_PRIVACY_OK")
	if spectator_reveal_test_mode: spectator_reveal_received.rpc_id(1)
	_update_round_hud()

@rpc("any_peer", "call_remote", "reliable")
func spectator_test_followed() -> void:
	if not multiplayer.is_server() or not spectator_reveal_test_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if sender != spectator_test_dead_peer or round_authority.get_spectator_state(sender).is_empty(): return
	spectator_test_observed = true
	_maybe_finish_spectator_probe()

@rpc("any_peer", "call_remote", "reliable")
func spectator_reveal_received() -> void:
	if not multiplayer.is_server() or not spectator_reveal_test_mode or round_authority.state != RoundState.ENDED: return
	var sender := multiplayer.get_remote_sender_id()
	if round_authority.is_participant(sender) and lobby.has(sender): spectator_reveal_acks[sender] = true
	if spectator_reveal_acks.size() == round_authority.participants.size():
		print("ROUND_REVEAL_NETWORK_ACK_OK clients=%d" % spectator_reveal_acks.size())

@rpc("authority", "call_remote", "reliable")
func round_roster(entries: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	local_roster_peers.clear()
	for raw_entry in entries:
		var entry: Dictionary = raw_entry
		# O roster público nunca traz papel; se trouxesse, o cliente descartaria.
		if entry.has("role"):
			print("CLIENT_ROSTER_REJECTED id=%s reason=role_field" % client_label)
			return
		local_roster_peers.append(int(entry.get("peer_id", 0)))
	if round_hud != null:
		round_hud.call("apply_roster", entries)

## Entrega privada do papel. Só chega por `rpc_id` vinda do servidor.
@rpc("authority", "call_remote", "reliable")
func round_private_role(round_id: int, role: int) -> void:
	if multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != 1:
		print("ROLE_SPOOF_REJECTED id=%s" % client_label)
		return
	if round_id <= 0 or not Role.is_valid(role):
		return
	if local_round_id == round_id and local_role == role:
		return
	local_round_id = round_id
	local_role = role
	local_role_receipts += 1
	# O valor do papel nunca vai para o log; só a confirmação de recebimento.
	print("CLIENT_PRIVATE_ROLE_RECEIVED id=%s count=%d" % [client_label, local_role_receipts])
	_update_round_hud()
	if round_test_mode:
		_run_role_privacy_probes()
		round_role_acknowledged.rpc_id(1, round_id)

## Confirmação de recebimento. Carrega somente o identificador da rodada.
@rpc("any_peer", "call_remote", "reliable")
func round_role_acknowledged(acknowledged_round_id: int) -> void:
	if not multiplayer.is_server() or shutting_down or round_authority == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if round_stop_after <= 0:
		return
	var reason := ""
	if round_authority.state != RoundState.ACTIVE:
		reason = "round_not_active"
	elif acknowledged_round_id != round_authority.round_id:
		reason = "stale_round"
	elif not lobby.has(sender) or not round_authority.is_participant(sender):
		reason = "not_in_round"
	elif round_ack_peers.has(sender):
		reason = "duplicate"
	if not reason.is_empty():
		print("ROUND_ACK_REJECTED peer_id=%d reason=%s" % [sender, reason])
		return
	round_ack_peers[sender] = true
	print("CLIENT_PRIVATE_ROLE_ACK peer_id=%d count=%d" % [sender, round_ack_peers.size()])
	_maybe_finish_round_privacy_test()

## Encerramento do teste de sigilo. Roda apenas sob --stop-after-round-active,
## depois de todas as confirmações e dos join tardios esperados.
func _maybe_finish_round_privacy_test() -> void:
	if round_stop_after <= 0 or shutting_down or round_authority == null:
		return
	if round_authority.state != RoundState.ACTIVE:
		return
	if round_ack_peers.size() < round_stop_after:
		return
	if round_late_join_peers.size() < round_expect_late_joins:
		return
	if spectator_reveal_test_mode:
		if spectator_test_started: return
		spectator_test_started = true
		for peer_id in round_authority.participants:
			if round_authority.get_role_for_peer(int(peer_id)) == Role.DETECTIVE:
				spectator_test_dead_peer = int(peer_id)
				round_authority.eliminate_player(spectator_test_dead_peer, "test", 0, Time.get_ticks_msec())
				return
	var counts := round_authority.role_counts()
	print("ROLE_PRIVACY_TEST_OK clients=%d assassin=%d detective=%d victim=%d" % [
		round_ack_peers.size(), int(counts["assassin"]), int(counts["detective"]), int(counts["victim"])])
	print("ROUND_LATE_JOIN_TOTAL count=%d participants=%d" % [
		round_late_join_peers.size(), round_authority.participants.size()])
	_eliminate_assassin_for_test()
	# Encerra com todas as sessões conectadas, inclusive as que aguardam a
	# próxima rodada, para que ninguém perca o handshake de shutdown.
	_begin_server_shutdown(lobby.peer_ids())

## Gancho de teste do combate futuro: exercita a API interna de eliminação e a
## avaliação de vitória. Nenhuma RPC de cliente alcança este caminho.
func _eliminate_assassin_for_test() -> void:
	for peer_id in round_authority.participants:
		if round_authority.get_role_for_peer(peer_id) != Role.ASSASSIN:
			continue
		var reason := round_authority.eliminate_player(int(peer_id), "test", 0, Time.get_ticks_msec())
		print("ROUND_TEST_ELIMINATION accepted=%s repeated_rejected=%s" % [
			str(reason.is_empty()),
			str(round_authority.eliminate_player(int(peer_id), "test", 0, Time.get_ticks_msec()) != "")])
		return

## Sondas do teste de sigilo, executadas por um único cliente. Nenhuma delas
## pode alterar o estado oficial.
func _run_role_privacy_probes() -> void:
	if client_label == "client-1" and not role_spoof_attempted:
		role_spoof_attempted = true
		# Tenta se passar pelo servidor e entregar um papel a outro peer.
		var target := _first_remote_roster_peer()
		if target > 0:
			round_private_role.rpc_id(target, local_round_id, Role.ASSASSIN)
		print("CLIENT_ROLE_SPOOF_ATTEMPTED id=%s target=%d" % [client_label, target])
	if client_label == "client-2" and not ack_replay_attempted:
		ack_replay_attempted = true
		# Confirmação com identificador de rodada forjado: o servidor recusa.
		round_role_acknowledged.rpc_id(1, local_round_id + 4242)
		print("CLIENT_STALE_ACK_ATTEMPTED id=%s" % client_label)

func _first_remote_roster_peer() -> int:
	var own_id := multiplayer.get_unique_id()
	for peer_id in local_roster_peers:
		if int(peer_id) != own_id:
			return int(peer_id)
	return 0

func _update_round_hud() -> void:
	if round_hud == null:
		return
	round_hud.call("apply_round_state", local_round_public, local_role, local_round_id, multiplayer.get_unique_id())
	round_hud.call("apply_combat_state", local_combat_state)
	round_hud.call("apply_spectator_state", local_eliminated, local_spectator_targets, _spectator_target())
	round_hud.call("apply_final_reveal", local_final_reveal)

func _client_can_gameplay() -> bool:
	return int(local_round_public.get("state", RoundState.WAITING)) == RoundState.ACTIVE \
		and not local_eliminated and int(local_combat_state.get("health", 0)) > 0

func _spectator_target() -> int:
	if local_spectator_index < 0 or local_spectator_index >= local_spectator_targets.size(): return 0
	return int(local_spectator_targets[local_spectator_index])

func _cycle_spectator(direction: int) -> void:
	if local_spectator_targets.is_empty(): return
	local_spectator_index = posmod(local_spectator_index + direction, local_spectator_targets.size())
	if arena_view != null: arena_view.set_spectator_target(_spectator_target())
	_update_round_hud()

@rpc("any_peer", "call_remote", "reliable")
func request_pickup(pickup_id: Variant, sequence: Variant) -> void:
	if not multiplayer.is_server() or shutting_down or combat_authority == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not lobby.has(sender):
		return
	var result := combat_authority.request_pickup(sender, pickup_id, sequence, Time.get_ticks_msec())
	_observe_spectator_block(sender, "pickup", result)
	if combat_network_test != null: combat_network_test.call("observe_server_action", sender, "pickup", sequence, result)
	if not bool(result.get("accepted", false)):
		combat_action_rejected.rpc_id(sender, "pickup", int(sequence) if typeof(sequence) == TYPE_INT else -1, _safe_combat_reason(result.get("reason", "rejected")))

@rpc("any_peer", "call_remote", "reliable")
func request_fire(sequence: Variant, claimed_origin: Variant, claimed_direction: Variant) -> void:
	if not multiplayer.is_server() or shutting_down or combat_authority == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not lobby.has(sender):
		return
	var result := combat_authority.request_fire(sender, sequence, claimed_origin, claimed_direction, Time.get_ticks_msec())
	_observe_spectator_block(sender, "fire", result)
	if combat_network_test != null: combat_network_test.call("observe_server_action", sender, "fire", sequence, result)
	if not bool(result.get("accepted", false)):
		combat_action_rejected.rpc_id(sender, "fire", int(sequence) if typeof(sequence) == TYPE_INT else -1, _safe_combat_reason(result.get("reason", "rejected")))
	elif bool(result.get("hit", false)):
		combat_hit_confirmed.rpc_id(sender)

@rpc("any_peer", "call_remote", "reliable")
func request_reload(sequence: Variant) -> void:
	if not multiplayer.is_server() or shutting_down or combat_authority == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not lobby.has(sender):
		return
	var result := combat_authority.request_reload(sender, sequence, Time.get_ticks_msec())
	_observe_spectator_block(sender, "reload", result)
	if combat_network_test != null: combat_network_test.call("observe_server_action", sender, "reload", sequence, result)
	if not bool(result.get("accepted", false)):
		combat_action_rejected.rpc_id(sender, "reload", int(sequence) if typeof(sequence) == TYPE_INT else -1, _safe_combat_reason(result.get("reason", "rejected")))

func _observe_spectator_block(sender: int, action: String, result: Dictionary) -> void:
	if not spectator_reveal_test_mode or sender != spectator_test_dead_peer \
			or str(result.get("reason", "")) != "player_dead": return
	spectator_test_blocked[action] = true
	_maybe_finish_spectator_probe()

func _maybe_finish_spectator_probe() -> void:
	if not spectator_test_observed or not spectator_test_movement_blocked or spectator_test_blocked.size() < 3 \
			or round_authority.state != RoundState.ACTIVE: return
	print("SPECTATOR_ACTIONS_BLOCKED")
	for peer_id in round_authority.participants:
		if round_authority.get_role_for_peer(int(peer_id)) == Role.ASSASSIN:
			round_authority.eliminate_player(int(peer_id), "test", 0, Time.get_ticks_msec())
			return

@rpc("authority", "call_remote", "reliable")
func combat_private_state(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	local_combat_state = payload.duplicate(true)
	if combat_network_test != null: combat_network_test.call("observe_client_event", "private", payload)
	if arena_view != null:
		arena_view.apply_combat_state(local_combat_state)
	_update_round_hud()

@rpc("authority", "call_remote", "reliable")
func pickup_public_state(payload: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if combat_network_test != null: combat_network_test.call("observe_client_event", "pickups", payload)
	if arena_view != null:
		arena_view.apply_pickups(payload)

@rpc("authority", "call_remote", "reliable")
func combat_public_shot(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if combat_network_test != null: combat_network_test.call("observe_client_event", "shot", payload)
	if arena_view != null:
		arena_view.show_shot(payload)

@rpc("authority", "call_remote", "reliable")
func combat_public_elimination(peer_id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if combat_network_test != null: combat_network_test.call("observe_client_event", "elimination", peer_id)
	if arena_view != null:
		arena_view.set_player_alive(peer_id, false)

@rpc("authority", "call_remote", "reliable")
func combat_hit_confirmed() -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if combat_network_test != null: combat_network_test.call("observe_client_event", "hit", null)
	if arena_view != null: arena_view.show_hit_marker()

@rpc("authority", "call_remote", "reliable")
func combat_action_rejected(action: String, sequence: int, reason: String) -> void:
	if combat_network_test != null: combat_network_test.call("observe_client_event", "rejection", {"action": action, "sequence": sequence, "reason": reason})
	print("COMBAT_REJECTED id=%s action=%s sequence=%d reason=%s" % [client_label, action, sequence, reason])

func _on_pickups_changed(snapshot: Array) -> void:
	if multiplayer.is_server() and not shutting_down:
		pickup_public_state.rpc(snapshot)

func _on_combat_private_state_changed(peer_id: int, state: Dictionary) -> void:
	if combat_network_test != null: combat_network_test.call("observe_private_emission", peer_id, state)
	if multiplayer.is_server() and lobby.has(peer_id) and not shutting_down:
		combat_private_state.rpc_id(peer_id, state)

func _on_shot_resolved(event: Dictionary) -> void:
	if combat_network_test != null: combat_network_test.call("observe_server_shot", event)
	if multiplayer.is_server() and not shutting_down:
		combat_public_shot.rpc(event)

func _on_combat_player_eliminated(peer_id: int, _instigator_peer_id: int) -> void:
	if combat_network_test != null: combat_network_test.call("observe_server_elimination", peer_id)
	if multiplayer.is_server() and not shutting_down:
		combat_public_elimination.rpc(peer_id)

func _safe_combat_reason(raw_reason: Variant) -> String:
	var reason := str(raw_reason)
	var allowed := ["round_not_active", "unknown_peer", "player_dead", "invalid_sequence", "replay", "sequence_jump", "rate_limited", "invalid_pickup", "item_not_found", "item_unavailable", "out_of_range", "inventory_full", "incompatible_item", "no_equipped_weapon", "reserve_full", "empty_magazine", "reloading", "fire_rate", "invalid_origin", "non_finite", "implausible_origin", "invalid_direction", "direction_not_normalized", "direction_vertical", "direction_yaw_divergence", "magazine_full", "reserve_empty", "already_reloading"]
	return reason if reason in allowed else "rejected"

func fail(message: String) -> void:
	push_error(message)
	print(message)
	get_tree().quit(1)
