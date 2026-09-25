extends SceneTree

## Runner do cliente adversarial da auditoria. Ele conecta por WebSocket como um
## peer real e dispara os ataques declarados em `AdversarialPeer`.

var peer_node: AdversarialPeer
var started_msec := 0
var quit_after_msec := 6000
var label := "attacker"

func _initialize() -> void:
	var arguments := NetworkConfig.user_arguments()
	label = str(arguments.get("client-id", "attacker"))
	quit_after_msec = NetworkConfig.integer_argument(arguments, "quit-after-msec", 6000)
	var url := str(arguments.get("url", "ws://127.0.0.1:9080"))
	started_msec = Time.get_ticks_msec()

	peer_node = AdversarialPeer.new()
	peer_node.name = "NetworkApp"
	peer_node.label = label
	peer_node.attack_phase = str(arguments.get("attack", "full"))
	root.add_child(peer_node)

	var transport := WebSocketClientTransport.connect_to_url(url)
	if transport == null:
		print("ATTACKER_ERROR id=%s unable_to_connect" % label)
		quit(1)
		return
	# Num run com `--script` a SceneTree não cria a MultiplayerAPI padrão.
	var api := SceneMultiplayer.new()
	set_multiplayer(api)
	api.connected_to_server.connect(_on_connected)
	api.connection_failed.connect(_on_connection_failed)
	api.server_disconnected.connect(_on_server_disconnected)
	api.multiplayer_peer = transport
	print("ATTACKER_CONNECTING id=%s url=%s" % [label, url])

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_msec > quit_after_msec:
		print("ATTACKER_DONE id=%s attacks=%d joined=%s" % [label, peer_node.attacks_sent, str(peer_node.joined)])
		return true
	return false

func _on_connected() -> void:
	print("ATTACKER_CONNECTED id=%s peer_id=%d" % [label, peer_node.multiplayer.get_unique_id()])
	if peer_node.attack_phase.begins_with("rooms"):
		peer_node.run_room_prehall_attacks()
		peer_node.request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, label)
		return
	peer_node.run_preauth_attacks()
	if peer_node.attack_phase == "preauth":
		return
	peer_node.request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, label)

func _on_connection_failed() -> void:
	print("ATTACKER_ERROR id=%s connection_failed" % label)
	quit(1)

func _on_server_disconnected() -> void:
	print("ATTACKER_SERVER_DISCONNECTED id=%s attacks=%d" % [label, peer_node.attacks_sent])
	quit(0)
