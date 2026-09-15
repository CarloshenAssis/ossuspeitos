extends Node

var arguments: Dictionary
var mode := ""
var sessions: Dictionary = {}
var client_label := ""
var expected_clients := 0
var joined := false
var started_at_msec := 0
var completion_sent := false
var shutdown_prepare_received := false
var shutting_down := false
var completed_peers: Dictionary = {}
var authoritative_world: AuthoritativeWorld
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
	authoritative_world = AuthoritativeWorld.new()
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
	multiplayer.multiplayer_peer = peer
	print("SERVER_READY address=%s port=%d" % [bind_address, port])

func start_client() -> void:
	client_label = str(arguments.get("client-id", "client"))
	expected_clients = NetworkConfig.integer_argument(arguments, "expect-clients", 0)
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
	print("CLIENT_CONNECTING id=%s url=%s" % [client_label, url])

func configured_port() -> int:
	var fallback := NetworkConfig.DEFAULT_PORT
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		fallback = env_port.to_int()
	return NetworkConfig.integer_argument(arguments, "port", fallback)

func _process(_delta: float) -> void:
	if mode != "client":
		return
	if not joined and Time.get_ticks_msec() - started_at_msec > int(NetworkConfig.CONNECT_TIMEOUT_SECONDS * 1000.0):
		fail("CLIENT_TIMEOUT id=%s" % client_label)
	if joined and expected_clients == 0:
		input_accumulator += _delta
		if input_accumulator >= 0.05:
			input_accumulator = 0.0
			_send_input(Input.get_vector("move_left", "move_right", "move_forward", "move_backward"), pending_yaw_delta)
			pending_yaw_delta = 0.0

func _physics_process(delta: float) -> void:
	if mode != "server" or shutting_down or authoritative_world == null:
		return
	authoritative_world.step(delta, Time.get_ticks_msec())
	snapshot_accumulator += delta
	if snapshot_accumulator >= 0.05:
		snapshot_accumulator = 0.0
		world_snapshot.rpc(authoritative_world.snapshot())

func _unhandled_input(event: InputEvent) -> void:
	if mode == "client" and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pending_yaw_delta = clampf(pending_yaw_delta - event.relative.x * 0.0025, -MovementRules.MAX_YAW_DELTA, MovementRules.MAX_YAW_DELTA)

func _on_peer_connected(peer_id: int) -> void:
	print("PEER_CONNECTED peer_id=%d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if server_terminal:
		return
	if sessions.erase(peer_id):
		if authoritative_world != null:
			authoritative_world.remove_player(peer_id)
		print("CLIENT_LEFT peer_id=%d count=%d" % [peer_id, sessions.size()])
		if shutting_down:
			return
		completed_peers.erase(peer_id)
		publish_client_count()

func _on_connected_to_server() -> void:
	print("CLIENT_CONNECTED id=%s peer_id=%d" % [client_label, multiplayer.get_unique_id()])
	request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, client_label)

func _on_connection_failed() -> void:
	fail("CLIENT_CONNECTION_FAILED id=%s" % client_label)

func _on_server_disconnected() -> void:
	if shutdown_prepare_received:
		print("CLIENT_SHUTDOWN_COMPLETE id=%s" % client_label)
		get_tree().quit(0)
		return
	if not joined or expected_clients > 0:
		fail("CLIENT_SERVER_DISCONNECTED id=%s" % client_label)

@rpc("any_peer", "call_remote", "reliable")
func request_join(protocol_version: int, requested_label: String) -> void:
	if not multiplayer.is_server() or shutting_down:
		return
	var sender := multiplayer.get_remote_sender_id()
	var clean_label := requested_label.strip_edges()
	if protocol_version != NetworkConfig.PROTOCOL_VERSION:
		join_rejected.rpc_id(sender, "protocol_version")
		return
	if clean_label.is_empty() or clean_label.length() > 32 or not clean_label.replace("-", "_").is_valid_identifier() or sessions.has(sender):
		join_rejected.rpc_id(sender, "invalid_client")
		return
	if sessions.size() >= NetworkConfig.MAX_PLAYERS or sessions.values().has(clean_label):
		join_rejected.rpc_id(sender, "room_unavailable")
		return
	var state := authoritative_world.add_player(sender)
	if state.is_empty():
		join_rejected.rpc_id(sender, "room_unavailable")
		return
	sessions[sender] = clean_label
	print("CLIENT_JOINED id=%s peer_id=%d count=%d" % [clean_label, sender, sessions.size()])
	var spawn: Vector3 = state["position"]
	print("PLAYER_SPAWNED peer_id=%d position=%.2f,%.2f,%.2f" % [sender, spawn.x, spawn.y, spawn.z])
	join_accepted.rpc_id(sender, sender)
	publish_client_count()
	world_snapshot.rpc(authoritative_world.snapshot())

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
	client_count_changed.rpc(sessions.size())

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
	if shutdown_prepare_received:
		return
	input_sequence += 1
	submit_input.rpc_id(1, input_sequence, move, yaw_delta)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(sequence: int, move: Vector2, yaw_delta: float) -> void:
	if not multiplayer.is_server() or shutting_down:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not sessions.has(sender):
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
	if stop_after <= 0 or not sessions.has(sender) or completed_peers.has(sender):
		return
	if not authoritative_world.has_moved(sender):
		print("TEST_CONFIRMATION_REJECTED peer_id=%d reason=not_moved" % sender)
		return
	completed_peers[sender] = true
	print("CLIENT_TEST_CONFIRMED peer_id=%d count=%d" % [sender, completed_peers.size()])
	if completed_peers.size() >= stop_after and not impossible_input_rejected_peers.is_empty() and authoritative_world.all_positions_distinct(completed_peers.keys()):
		_begin_server_shutdown()

func _begin_server_shutdown() -> void:
	if shutting_down:
		return
	shutting_down = true
	for peer_id in completed_peers:
		shutdown_expected_peers[peer_id] = true
	var observed_max_speed := 0.0
	for peer_id in completed_peers:
		var state: Dictionary = authoritative_world.states[peer_id]
		var position: Vector3 = state["position"]
		var velocity: Vector3 = state["velocity"]
		var speed := velocity.length()
		observed_max_speed = maxf(observed_max_speed, speed)
		print("PLAYER_STATE peer_id=%d position=%.3f,%.3f,%.3f speed=%.3f" % [peer_id, position.x, position.y, position.z, speed])
	print("SERVER_MOVEMENT_TEST_OK players=%d max_speed=%.3f rejected_impossible=%d" % [completed_peers.size(), observed_max_speed, impossible_input_rejected_peers.size()])
	print("SERVER_TEST_OK clients=%d" % completed_peers.size())
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
	if not shutdown_expected_peers.has(sender) or not sessions.has(sender) or shutdown_ready_peers.has(sender):
		return
	shutdown_ready_peers[sender] = true
	print("CLIENT_SHUTDOWN_READY peer_id=%d count=%d" % [sender, shutdown_ready_peers.size()])
	if shutdown_ready_peers.size() >= shutdown_expected_peers.size():
		_cancel_shutdown_prepare_timeout()
		print("SERVER_SHUTDOWN_READY clients=%d" % shutdown_ready_peers.size())
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
	sessions.clear()
	if authoritative_world != null:
		authoritative_world.clear()
	completed_peers.clear()
	impossible_input_rejected_peers.clear()
	shutdown_ready_peers.clear()
	shutdown_expected_peers.clear()
	multiplayer.multiplayer_peer.close()
	print("SERVER_SHUTDOWN_COMPLETE closed=%d" % closed_session_count)
	get_tree().quit(0)

func _server_shutdown_timeout() -> void:
	if server_terminal or shutdown_ready_peers.size() >= shutdown_expected_peers.size():
		return
	print("SERVER_SHUTDOWN_TIMEOUT ready=%d remaining=%d" % [shutdown_ready_peers.size(), sessions.size()])
	get_tree().quit(1)

func fail(message: String) -> void:
	push_error(message)
	print(message)
	get_tree().quit(1)
