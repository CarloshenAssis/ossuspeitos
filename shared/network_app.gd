extends Node

var arguments: Dictionary
var mode := ""
var sessions: Dictionary = {}
var client_label := ""
var expected_clients := 0
var joined := false
var started_at_msec := 0
var completion_sent := false
var shutdown_authorized_received := false
var shutting_down := false
var completed_peers: Dictionary = {}
var shutdown_peer_count := 0

func _ready() -> void:
	arguments = NetworkConfig.user_arguments()
	mode = str(arguments.get("mode", ""))
	if mode == "server":
		start_server()
	elif mode == "client":
		start_client()
	else:
		fail("MODE_REQUIRED use -- --mode=server or -- --mode=client")

func start_server() -> void:
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
	print("CLIENT_CONNECTING id=%s url=%s" % [client_label, url])

func configured_port() -> int:
	var fallback := NetworkConfig.DEFAULT_PORT
	var env_port := OS.get_environment("PORT")
	if env_port.is_valid_int():
		fallback = env_port.to_int()
	return NetworkConfig.integer_argument(arguments, "port", fallback)

func _process(_delta: float) -> void:
	if mode != "client" or joined:
		return
	if Time.get_ticks_msec() - started_at_msec > int(NetworkConfig.CONNECT_TIMEOUT_SECONDS * 1000.0):
		fail("CLIENT_TIMEOUT id=%s" % client_label)

func _on_peer_connected(peer_id: int) -> void:
	print("PEER_CONNECTED peer_id=%d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if sessions.erase(peer_id):
		print("CLIENT_LEFT peer_id=%d count=%d" % [peer_id, sessions.size()])
		if shutting_down:
			if sessions.is_empty():
				call_deferred("_successful_server_shutdown")
			return
		completed_peers.erase(peer_id)
		publish_client_count()

func _on_connected_to_server() -> void:
	print("CLIENT_CONNECTED id=%s peer_id=%d" % [client_label, multiplayer.get_unique_id()])
	request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, client_label)

func _on_connection_failed() -> void:
	fail("CLIENT_CONNECTION_FAILED id=%s" % client_label)

func _on_server_disconnected() -> void:
	if not joined or (expected_clients > 0 and not shutdown_authorized_received):
		fail("CLIENT_SERVER_DISCONNECTED id=%s" % client_label)

@rpc("any_peer", "call_remote", "reliable")
func request_join(protocol_version: int, requested_label: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var clean_label := requested_label.strip_edges()
	if protocol_version != NetworkConfig.PROTOCOL_VERSION:
		join_rejected.rpc_id(sender, "protocol_version")
		return
	if clean_label.is_empty() or clean_label.length() > 32 or sessions.has(sender):
		join_rejected.rpc_id(sender, "invalid_client")
		return
	if sessions.size() >= NetworkConfig.MAX_PLAYERS or sessions.values().has(clean_label):
		join_rejected.rpc_id(sender, "room_unavailable")
		return
	sessions[sender] = clean_label
	print("CLIENT_JOINED id=%s peer_id=%d count=%d" % [clean_label, sender, sessions.size()])
	join_accepted.rpc_id(sender, sender)
	publish_client_count()

@rpc("authority", "call_remote", "reliable")
func join_accepted(peer_id: int) -> void:
	joined = true
	print("JOIN_ACCEPTED id=%s peer_id=%d" % [client_label, peer_id])

@rpc("authority", "call_remote", "reliable")
func join_rejected(reason: String) -> void:
	fail("JOIN_REJECTED id=%s reason=%s" % [client_label, reason])

func publish_client_count() -> void:
	client_count_changed.rpc(sessions.size())

@rpc("authority", "call_remote", "reliable")
func client_count_changed(count: int) -> void:
	print("CLIENT_COUNT id=%s count=%d" % [client_label, count])
	if expected_clients > 0 and count >= expected_clients and not completion_sent:
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
	completed_peers[sender] = true
	print("CLIENT_TEST_CONFIRMED peer_id=%d count=%d" % [sender, completed_peers.size()])
	if stop_after > 0 and completed_peers.size() >= stop_after:
		_begin_server_shutdown()

func _begin_server_shutdown() -> void:
	shutting_down = true
	shutdown_peer_count = completed_peers.size()
	print("SERVER_TEST_OK clients=%d" % completed_peers.size())
	for peer_id in completed_peers:
		shutdown_authorized.rpc_id(peer_id)
	get_tree().create_timer(1.0).timeout.connect(_server_shutdown_timeout)

@rpc("authority", "call_remote", "reliable")
func shutdown_authorized() -> void:
	shutdown_authorized_received = true
	print("CLIENT_SHUTDOWN_AUTHORIZED id=%s" % client_label)
	call_deferred("_successful_client_shutdown")

func _successful_client_shutdown() -> void:
	get_tree().quit(0)

func _successful_server_shutdown() -> void:
	print("SERVER_SHUTDOWN_COMPLETE disconnected=%d" % shutdown_peer_count)
	get_tree().quit(0)

func _server_shutdown_timeout() -> void:
	print("SERVER_SHUTDOWN_TIMEOUT remaining=%d" % sessions.size())
	get_tree().quit(0)

func fail(message: String) -> void:
	push_error(message)
	print(message)
	get_tree().quit(1)
