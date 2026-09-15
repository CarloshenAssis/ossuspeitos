extends Node

var arguments: Dictionary
var mode := ""
var sessions: Dictionary = {}
var client_label := ""
var expected_clients := 0
var joined := false
var started_at_msec := 0
var test_shutdown_scheduled := false

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
		publish_client_count()

func _on_connected_to_server() -> void:
	print("CLIENT_CONNECTED id=%s peer_id=%d" % [client_label, multiplayer.get_unique_id()])
	request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, client_label)

func _on_connection_failed() -> void:
	fail("CLIENT_CONNECTION_FAILED id=%s" % client_label)

func _on_server_disconnected() -> void:
	if not joined or (expected_clients > 0 and not test_shutdown_scheduled):
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
	var stop_after := NetworkConfig.integer_argument(arguments, "stop-after-clients", 0)
	if stop_after > 0 and sessions.size() >= stop_after and not test_shutdown_scheduled:
		test_shutdown_scheduled = true
		print("SERVER_CLIENT_COUNT_REACHED count=%d" % sessions.size())
		get_tree().create_timer(1.0).timeout.connect(_successful_server_shutdown)

@rpc("authority", "call_remote", "reliable")
func client_count_changed(count: int) -> void:
	print("CLIENT_COUNT id=%s count=%d" % [client_label, count])
	if expected_clients > 0 and count >= expected_clients:
		test_shutdown_scheduled = true
		get_tree().create_timer(0.2).timeout.connect(_successful_client_shutdown)

func _successful_client_shutdown() -> void:
	print("CLIENT_TEST_OK id=%s" % client_label)
	get_tree().quit(0)

func _successful_server_shutdown() -> void:
	print("SERVER_TEST_OK clients=%d" % sessions.size())
	get_tree().quit(0)

func fail(message: String) -> void:
	push_error(message)
	print(message)
	get_tree().quit(1)
