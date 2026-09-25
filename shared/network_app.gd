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
## Corpos oficiais da rodada (servidor) e os aceitos pelo cliente (por id).
var body_registry := BodyRegistry.new()
var local_bodies: Dictionary = {}
var combat_authority: CombatAuthority
var arena_view: ArenaView
## Servidor: tick oficial e identidade desta execução (protocolo 9).
var server_tick := 0
var session_nonce := 0
## peer_id -> motivos de recusa de pacote já registrados (log limitado).
var command_logs: Dictionary = {}
## peer_id -> último tick em que um `input_rejected` saiu (no máximo um por tick).
var input_rejection_ticks: Dictionary = {}
## Cliente: previsão, fila de envio e identificadores de ação (fase 4).
var prediction := PlayerPrediction.new()
var outbox: Array = []
var ticks_since_send := 0
var action_ids := {"fire": 0, "reload": 0, "pickup": 0}
var action_round_id := -1
## Depois de entrar em ACTIVE, o cliente só comanda com a época que o
## servidor abriu para a rodada (o primeiro ACK recebido depois do aviso).
var awaiting_epoch_sync := true
var snapshot_session := 0
var last_snapshot_tick := -1
var test_move_intent := Vector2.ZERO
var test_movement_started := false
var window_focused := true
var net_stats := NetStats.new()
var net_stats_interval_msec := 0
var net_stats_last_msec := 0
const MOUSE_SENSITIVITY := 0.0025
var client_spawn_known := false
var client_spawn_position := Vector3.ZERO
var client_movement_observed := false
var impossible_input_rejected_peers: Dictionary = {}
var test_direction := Vector2.ZERO
var test_roster_ready := false
## Encerramento em duas fases, correlacionado por geração e token por peer.
var shutdown_handshake := ShutdownHandshake.new()
## peer_id -> motivos de recusa já registrados, para não repetir log por pacote.
var shutdown_ready_rejections_logged: Dictionary = {}
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
## Teste local no PC: menu inicial e cliente interativo que volta ao menu em vez
## de encerrar o processo quando a conexão falha ou termina.
var desktop_menu: DesktopMenu
var interactive_session := false
var hosting_pending := false
var hosting_deadline_msec := 0
var pending_player_name := ""
var returning_to_menu := false
var leave_trigger := ""
## Tentativa corrente do menu (fase 7): eventos de rede de outra tentativa
## são ignorados pelo `MenuFlow`.
var menu_attempt := 0
## Sensibilidade efetiva do mouse (base × preferência salva no menu).
var mouse_sensitivity := MOUSE_SENSITIVITY
## Servidor hospedado pelo menu: grava prontidão num arquivo e se encerra sozinho
## quando fica vazio, para nunca sobrar processo órfão.
var status_file_path := ""
var hosted_server := false
var hosted_empty_since_msec := 0
const HOSTED_IDLE_EXIT_MSEC := 20000
## Servidor dedicado de produção (fase 8, `--mode=dedicated`): configuração
## resolvida por `DedicatedConfig`, conexões ainda sem entrada (prazo de
## `request_join`), pedido de encerramento do operador e contadores de log.
var dedicated := false
var dedicated_config: Dictionary = {}
var pending_peers: Dictionary = {}
var operator_shutdown := false
var dedicated_started_msec := 0
var dedicated_next_status_msec := 0
var dedicated_next_poll_msec := 0
var dedicated_stats := {"connections": 0, "joins": 0, "refusals": 0, "deadline_drops": 0, "suppressed_logs": 0, "rounds": 0}
## peer_id -> recusas de entrada já registradas (log limitado por peer).
var refusal_logs: Dictionary = {}
const REFUSAL_LOGS_PER_PEER := 3
## Fase 9: salas privadas online. Com salas ligadas (servidor dedicado, ou
## `--rooms=true` em testes), cada sala tem o próprio estado de partida; os
## campos `lobby`, `round_authority`, `authoritative_world`, `combat_authority`
## e `body_registry` apontam para a sala do evento que está sendo tratado
## (`_use_room`). Sem salas (local/LAN/testes antigos), eles apontam sempre
## para a sala única `default_room`, como antes.
var rooms_enabled := false
var room_registry: RoomRegistry
var default_room: MatchRoom
var current_room: MatchRoom
## Salas online: conexões que fizeram o handshake (protocolo + nome válido).
## peer_id -> {"since": msec, "failures": tentativas de entrada recusadas}
var hall_peers: Dictionary = {}
## room_id -> [[sinal, Callable], ...] para desligar quando a sala sai.
var room_connections: Dictionary = {}
var rooms_next_housekeeping_msec := 0
## Capacidade de conexões em salas online além dos membros das salas.
const HALL_EXTRA_CAPACITY := 16

func _ready() -> void:
	GameControls.ensure()
	arguments = NetworkConfig.user_arguments()
	mode = str(arguments.get("mode", ""))
	if mode.is_empty() and OS.has_feature("visual_demo"):
		mode = "demo"
	# Build de PC ou execução gráfica sem argumentos: menu de teste local. A demo
	# Web entra antes (feature `visual_demo`) e continua OFFLINE / SEM SERVIDOR.
	if mode.is_empty() and (OS.has_feature("desktop_playtest") or DisplayServer.get_name() != "headless"):
		mode = "menu"
	if mode == "server":
		start_server()
	elif mode == "dedicated":
		start_dedicated()
	elif mode == "client":
		start_client()
	elif mode == "demo":
		start_demo()
	elif mode == "menu":
		start_menu()
	else:
		fail("MODE_REQUIRED use -- --mode=server, -- --mode=client, -- --mode=menu or -- --mode=demo")

func start_demo() -> void:
	var demo := VisualDemo.new()
	demo.test_mode = str(arguments.get("demo-test", "false")) == "true"
	add_child(demo)

## Servidor dedicado de produção: só a lista fechada de argumentos, porta de
## `PORT`, escuta em 0.0.0.0, nenhum coordenador de teste, nenhuma
## apresentação. Erro de configuração sai com 2; falha de bind, com 1.
func start_dedicated() -> void:
	dedicated = true
	dedicated_started_msec = Time.get_ticks_msec()
	dedicated_config = DedicatedConfig.resolve(arguments, DedicatedConfig.process_environment())
	print("DEDICATED_START game=armed-mystery commit=%s godot=%s protocol=%d build=%s display=%s capacity=%d" % [
		dedicated_config["commit"], str(Engine.get_version_info()["string"]), NetworkConfig.PROTOCOL_VERSION,
		"debug" if OS.is_debug_build() else "release", DisplayServer.get_name(), RoundRules.MAX_PLAYERS])
	if DisplayServer.get_name() != "headless":
		(dedicated_config["errors"] as Array).append("o modo dedicado exige --headless")
	if not (dedicated_config["errors"] as Array).is_empty():
		for error in dedicated_config["errors"]:
			printerr("DEDICATED_CONFIG_ERROR %s" % error)
			print("DEDICATED_CONFIG_ERROR %s" % error)
		print("DEDICATED_FATAL reason=config exit=%d" % DedicatedConfig.EXIT_CONFIG_ERROR)
		get_tree().quit(DedicatedConfig.EXIT_CONFIG_ERROR)
		return
	start_server(int(dedicated_config["port"]), str(dedicated_config["bind"]))

func start_server(port: int = -1, bind_address: String = "") -> void:
	spectator_reveal_test_mode = NetworkConfig.bool_argument(arguments, "spectator-reveal-test")
	rooms_enabled = dedicated or NetworkConfig.bool_argument(arguments, "rooms")
	if rooms_enabled:
		_start_room_registry()
	else:
		_start_round_authority()
	if not dedicated:
		_start_combat_network_test()
	shutdown_prepare_timer = Timer.new()
	shutdown_prepare_timer.one_shot = true
	shutdown_prepare_timer.timeout.connect(_server_shutdown_timeout)
	add_child(shutdown_prepare_timer)
	if port < 0:
		port = configured_port()
	if bind_address.is_empty():
		bind_address = str(arguments.get("bind", NetworkConfig.DEFAULT_BIND_ADDRESS))
	if not dedicated:
		status_file_path = str(arguments.get("status-file", ""))
		hosted_server = NetworkConfig.bool_argument(arguments, "hosted")
	# Identidade da execução: snapshots de outro servidor são descartados.
	session_nonce = (randi() & 0x3fffffff) | 1
	var opened := WebSocketServerTransport.open(port, bind_address)
	var peer: WebSocketMultiplayerPeer = opened["peer"]
	if peer == null:
		if dedicated:
			# Sem troca silenciosa de porta: a falha é fatal e explicada.
			printerr("DEDICATED_FATAL reason=listen_failed bind=%s port=%d error=%s" % [bind_address, port, error_string(int(opened["error"]))])
			print("DEDICATED_FATAL reason=listen_failed bind=%s port=%d error=%s exit=%d" % [bind_address, port, error_string(int(opened["error"])), DedicatedConfig.EXIT_RUNTIME_ERROR])
			get_tree().quit(DedicatedConfig.EXIT_RUNTIME_ERROR)
			return
		_write_status_file("error:unable_to_listen")
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
	_write_status_file(DesktopSession.STATUS_READY)
	if dedicated:
		# Pronto de verdade: mundo, autoridades e listener criados sem erro.
		print("DEDICATED_READY bind=%s port=%d port_source=%s capacity=%d protocol=%d shutdown_file=%s max_rooms=%d" % [
			bind_address, port, dedicated_config["port_source"], RoundRules.MAX_PLAYERS,
			NetworkConfig.PROTOCOL_VERSION, "on" if not str(dedicated_config["shutdown_file"]).is_empty() else "off",
			room_registry.max_rooms])
		dedicated_next_status_msec = Time.get_ticks_msec() + int(dedicated_config["status_interval_seconds"]) * 1000

## Sala única (local/LAN/testes antigos): sem código e sem gate de PRONTO.
func _start_round_authority() -> void:
	default_room = MatchRoom.new(0, "", Time.get_ticks_msec(), false,
		NetworkConfig.float_argument(arguments, "countdown-seconds", RoundRules.COUNTDOWN_SECONDS),
		NetworkConfig.float_argument(arguments, "round-end-delay-seconds", RoundRules.ROUND_END_DELAY_SECONDS),
		NetworkConfig.integer_argument(arguments, "round-seed", 0))
	round_stop_after = NetworkConfig.integer_argument(arguments, "stop-after-round-active", 0)
	round_expect_late_joins = NetworkConfig.integer_argument(arguments, "expect-late-joins", 0)
	_wire_room(default_room)
	_use_room(default_room)

## Salas online: registro vazio; as salas nascem por `room_create`.
func _start_room_registry() -> void:
	room_registry = RoomRegistry.new()
	if dedicated:
		room_registry.max_rooms = int(dedicated_config.get("max_rooms", RoomRegistry.DEFAULT_MAX_ROOMS))
	else:
		room_registry.max_rooms = clampi(NetworkConfig.integer_argument(arguments, "max-rooms", RoomRegistry.DEFAULT_MAX_ROOMS), 1, RoomRegistry.MAX_ROOMS_LIMIT)
		room_registry.countdown_seconds = NetworkConfig.float_argument(arguments, "countdown-seconds", RoomRules.COUNTDOWN_SECONDS)
		room_registry.results_seconds = NetworkConfig.float_argument(arguments, "round-end-delay-seconds", RoomRules.RESULTS_SECONDS)
	print("ROOMS_ENABLED max_rooms=%d room_capacity=%d countdown_s=%.1f results_s=%.1f" % [
		room_registry.max_rooms, RoundRules.MAX_PLAYERS, room_registry.countdown_seconds, room_registry.results_seconds])

## Aponta os campos de trabalho do servidor para a sala do evento corrente.
## Toda entrada do servidor (RPC de cliente, tick, sinal de autoridade,
## chamada adiada, desconexão) passa por aqui antes de ler ou enviar estado.
func _use_room(room: MatchRoom) -> void:
	current_room = room
	lobby = room.lobby
	round_authority = room.round_authority
	authoritative_world = room.world
	combat_authority = room.combat
	body_registry = room.bodies

## Liga os sinais das autoridades da sala; cada callback entra na própria sala
## antes de agir, então nada de uma sala é tratado no contexto de outra.
func _wire_room(room: MatchRoom) -> void:
	var links: Array = []
	var ra := room.round_authority
	links.append([ra.state_changed, func(s: int, r: int): _use_room(room); _on_round_state_changed(s, r)])
	links.append([ra.roles_ready, func(r: int, ids: Array): _use_room(room); _on_round_roles_ready(r, ids)])
	links.append([ra.alive_changed, func(r: int, p: int, a: bool): _use_room(room); _on_round_alive_changed(r, p, a)])
	links.append([ra.round_ended, func(r: int, t: int, why: String): _use_room(room); _on_round_ended(r, t, why)])
	links.append([ra.reveal_ready, func(r: int, result: Dictionary): _use_room(room); _on_round_reveal_ready(r, result)])
	links.append([ra.spectator_targets_changed, func(r: int): _use_room(room); _on_spectator_targets_changed(r)])
	links.append([ra.round_reset, func(r: int): _use_room(room); _on_round_reset(r)])
	links.append([ra.invalid_transition, func(a: int, b: int): _use_room(room); _on_round_invalid_transition(a, b)])
	var combat := room.combat
	links.append([combat.pickups_changed, func(snapshot: Array): _use_room(room); _on_pickups_changed(snapshot)])
	links.append([combat.private_state_changed, func(p: int, state: Dictionary): _use_room(room); _on_combat_private_state_changed(p, state)])
	links.append([combat.shot_resolved, func(event: Dictionary): _use_room(room); _on_shot_resolved(event)])
	links.append([combat.player_eliminated, func(p: int, i: int): _use_room(room); _on_combat_player_eliminated(p, i)])
	for link in links:
		(link[0] as Signal).connect(link[1])
	room_connections[room.room_id] = links

func _unwire_room(room: MatchRoom) -> void:
	for link in room_connections.get(room.room_id, []):
		if (link[0] as Signal).is_connected(link[1]):
			(link[0] as Signal).disconnect(link[1])
	room_connections.erase(room.room_id)

## Salas que o tick percorre.
func _active_rooms() -> Array:
	if rooms_enabled:
		return room_registry.rooms.values() if room_registry != null else []
	return [default_room] if default_room != null else []

## Entra na sala do remetente (salas online). Falso se ele não está em sala:
## o evento é ignorado, sem tocar estado de nenhuma sala.
func _enter_sender_room(sender: int) -> bool:
	if not rooms_enabled:
		return true
	var room := room_registry.room_of(sender) if room_registry != null else null
	if room == null:
		return false
	_use_room(room)
	return true

## Sessões com handshake feito: salas online (todas as conexões aceitas) ou a
## sala única.
func _session_peers() -> Array:
	if rooms_enabled:
		return hall_peers.keys()
	return lobby.peer_ids()

func _is_session_peer(peer_id: int) -> bool:
	return hall_peers.has(peer_id) if rooms_enabled else lobby.has(peer_id)

func start_client() -> void:
	client_label = str(arguments.get("client-id", "client"))
	expected_clients = NetworkConfig.integer_argument(arguments, "expect-clients", 0)
	round_test_mode = NetworkConfig.bool_argument(arguments, "round-test")
	spectator_reveal_test_mode = NetworkConfig.bool_argument(arguments, "spectator-reveal-test")
	if spectator_reveal_test_mode: round_test_mode = true
	_start_combat_network_test()
	_start_latency_probe()
	started_at_msec = Time.get_ticks_msec()
	var url := str(arguments.get("url", "ws://%s:%d" % [NetworkConfig.DEFAULT_HOST, configured_port()]))
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	var peer: MultiplayerPeer = WebSocketClientTransport.connect_to_url(url)
	if peer == null:
		fail("CLIENT_ERROR id=%s unable_to_connect" % client_label)
		return
	peer = _wrap_test_net_delay(peer)
	multiplayer.multiplayer_peer = peer
	net_stats_interval_msec = NetworkConfig.integer_argument(arguments, "net-stats", 0)
	# Pelo menu (fase 7), a mansão só é montada depois da entrada aceita; o
	# menu continua na tela mostrando o estado da conexão.
	if not interactive_session:
		_create_client_presentation()
	print("CLIENT_CONNECTING id=%s url=%s" % [client_label, url])

func _create_client_presentation() -> void:
	if DisplayServer.get_name() != "headless" and arena_view == null:
		arena_view = ArenaView.new()
		arena_view.local_view_provider = _local_presented
		add_child(arena_view)
		_start_round_hud()
	print("CLIENT_UI id=%s hud=%s arena=%s display=%s" % [
		client_label, str(round_hud != null), str(arena_view != null), DisplayServer.get_name()])

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

## Atraso de aplicação só de teste (`tests/net_delay_peer.gd`). Exige binário
## de desenvolvimento não exportado: a build de jogo nunca aceita o argumento.
var test_net_peer: MultiplayerPeer
func _wrap_test_net_delay(peer: MultiplayerPeer) -> MultiplayerPeer:
	var profile := str(arguments.get("test-net-profile", ""))
	if profile.is_empty():
		return peer
	if not OS.is_debug_build() or OS.has_feature("template"):
		print("TEST_NET_PROFILE_IGNORED id=%s reason=exported_build" % client_label)
		return peer
	var script := load("res://tests/net_delay_peer.gd") as GDScript
	if script == null or not script.call("is_known_profile", profile):
		fail("TEST_NET_PROFILE_ERROR id=%s profile=%s" % [client_label, profile])
		return peer
	test_net_peer = script.new(peer, profile, NetworkConfig.integer_argument(arguments, "test-net-seed", 1))
	print("TEST_NET_PROFILE id=%s profile=%s seed=%d" % [client_label, profile, NetworkConfig.integer_argument(arguments, "test-net-seed", 1)])
	return test_net_peer

## Sonda de latência/suavidade (fase 4), só em teste explícito.
var latency_probe: Node
func _start_latency_probe() -> void:
	var role := str(arguments.get("latency-probe", ""))
	if role.is_empty():
		return
	var script := load("res://tests/latency_probe.gd") as GDScript
	if script == null:
		fail("LATENCY_PROBE_ERROR missing")
		return
	latency_probe = script.new()
	latency_probe.name = "LatencyProbe"
	add_child(latency_probe)

func _start_combat_network_test() -> void:
	# Coordenadores de teste explícitos: combate (fase 1+) ou sincronização
	# (fase 4). Ambos observam pelos mesmos ganchos.
	var path := ""
	if NetworkConfig.bool_argument(arguments, "combat-test"):
		path = "res://tests/combat_network_coordinator.gd"
	elif NetworkConfig.bool_argument(arguments, "adverse-test"):
		path = "res://tests/adverse_coordinator.gd"
	elif NetworkConfig.bool_argument(arguments, "campaign-test"):
		path = "res://tests/campaign_coordinator.gd"
	elif NetworkConfig.bool_argument(arguments, "sync-test"):
		path = "res://tests/sync_network_coordinator.gd"
	elif NetworkConfig.bool_argument(arguments, "rooms-test"):
		path = "res://tests/rooms_coordinator.gd"
	if path.is_empty():
		return
	var script := load(path) as GDScript
	if script == null:
		fail("COMBAT_TEST_ERROR coordinator_missing")
		return
	combat_network_test = script.new()
	combat_network_test.name = "CombatNetworkCoordinator" if path.contains("combat") else ("CampaignCoordinator" if path.contains("campaign") or path.contains("adverse") else ("RoomsCoordinator" if path.contains("rooms") else "SyncNetworkCoordinator"))
	add_child(combat_network_test)

func _process(_delta: float) -> void:
	if mode == "menu":
		_poll_hosting()
		return
	if mode != "client":
		return
	# O prazo é de conexão: depois do encerramento combinado com o servidor
	# (`joined` volta a falso ao desconectar), ele não se aplica mais.
	if not joined and not returning_to_menu and not shutdown_prepare_received \
			and Time.get_ticks_msec() - started_at_msec > _connect_timeout_msec():
		if interactive_session:
			print("CLIENT_TIMEOUT id=%s" % client_label)
			_return_to_menu("Tempo esgotado ao conectar em %s." % str(arguments.get("url", "")), "timeout")
			return
		fail("CLIENT_TIMEOUT id=%s" % client_label)
	if probe_joined_msec > 0:
		_check_probe_traffic()
	if net_stats_interval_msec > 0 and joined and Time.get_ticks_msec() - net_stats_last_msec >= net_stats_interval_msec:
		net_stats_last_msec = Time.get_ticks_msec()
		print("NET_STATS id=%s %s" % [client_label, net_stats.summary(prediction, arena_view.interpolator if arena_view != null else null)])

## Teste (binário de desenvolvimento): encerramento coordenado N ms depois da
## primeira entrada, para provar que o fim combinado não vira mensagem de erro.
var _test_shutdown_from_msec := 0
func _maybe_test_shutdown(now_msec: int) -> void:
	if shutting_down or not arguments.has("test-shutdown-after-msec") or not OS.is_debug_build() or OS.has_feature("template"):
		return
	if lobby.is_empty():
		return
	if _test_shutdown_from_msec == 0:
		_test_shutdown_from_msec = now_msec
	if now_msec - _test_shutdown_from_msec >= NetworkConfig.integer_argument(arguments, "test-shutdown-after-msec", 0):
		print("SERVER_TEST_SHUTDOWN lobby=%d" % lobby.size())
		_begin_server_shutdown(lobby.peer_ids())

## Prazo de conexão; um binário de desenvolvimento pode encurtá-lo nos testes.
func _connect_timeout_msec() -> int:
	var seconds := NetworkConfig.CONNECT_TIMEOUT_SECONDS
	if arguments.has("test-connect-timeout-seconds") and OS.is_debug_build() and not OS.has_feature("template"):
		seconds = clampf(float(str(arguments["test-connect-timeout-seconds"])), 0.5, 60.0)
	return int(seconds * 1000.0)

func _physics_process(_delta: float) -> void:
	if mode == "client":
		_client_command_tick()
		return
	if mode != "server" and mode != "dedicated":
		return
	if not rooms_enabled and default_room == null:
		return
	var now_msec := Time.get_ticks_msec()
	if dedicated:
		_dedicated_housekeeping(now_msec)
	if shutting_down:
		return
	if hosted_server:
		_check_hosted_idle(now_msec)
	server_tick += 1
	_maybe_test_shutdown(now_msec)
	if rooms_enabled:
		_rooms_housekeeping(now_msec)
	# Cada sala avança isolada, com seus campos de trabalho.
	for room in _active_rooms():
		_use_room(room)
		_tick_room(now_msec)

func _tick_room(now_msec: int) -> void:
	authoritative_world.step(_command_gate, _run_command_action, _on_command_rejected)
	combat_authority.tick(now_msec)
	round_authority.tick(now_msec)
	if round_authority.consume_countdown_tick(now_msec):
		_publish_round_state()
		_publish_room_state()
	if server_tick % NetSync.SNAPSHOT_INTERVAL_TICKS == 0:
		_broadcast_snapshot()

## Snapshot por destinatário: estados públicos iguais para todos e o ACK
## privado do próprio jogador (sequência resolvida, época, baldes de mira).
func _broadcast_snapshot() -> void:
	if shutting_down or authoritative_world == null:
		return
	var players := authoritative_world.snapshot()
	for peer_id in lobby.peer_ids():
		# Conexão já fechando (o cliente caiu e o aviso de desconexão ainda não
		# chegou): enviar só gera erro do engine no log a cada snapshot.
		if not _peer_socket_open(int(peer_id)):
			continue
		world_snapshot.rpc_id(int(peer_id), {"tick": server_tick, "session": session_nonce,
			"players": players, "ack": authoritative_world.ack_for(int(peer_id))})

## Membros da sala corrente com o socket aberto. Um cliente que caiu fica
## no lobby até o aviso de desconexão chegar; enviar a ele só gera erro do
## engine no log a cada mensagem.
func _open_members() -> Array:
	var result: Array = []
	for peer_id in lobby.peer_ids():
		if _peer_socket_open(int(peer_id)):
			result.append(int(peer_id))
	return result

func _peer_socket_open(peer_id: int) -> bool:
	var transport := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
	if transport == null:
		return true
	if not multiplayer.get_peers().has(peer_id):
		return false
	var socket := transport.get_peer(peer_id)
	return socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func _unhandled_input(event: InputEvent) -> void:
	if interactive_session and event.is_action_pressed("leave_match"):
		_return_to_menu("Você saiu da partida.", "left")
		return
	if mode == "client" and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and _commands_enabled():
		# Mouse para a direita reduz o yaw; para cima (relative.y < 0) olha para
		# cima. O delta é consumido uma vez: a câmera o mostra no próximo quadro
		# e o próximo comando o leva (limitado como no servidor).
		prediction.add_look(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity, Time.get_ticks_usec())
	if mode != "client" or not joined or shutdown_prepare_received or arena_view == null:
		return
	if not _client_can_gameplay():
		if event.is_action_pressed("spectate_previous"): _cycle_spectator(-1)
		elif event.is_action_pressed("spectate_next"): _cycle_spectator(1)
		return
	if not _commands_enabled():
		return
	if event.is_action_pressed("fire"):
		_queue_local_action(NetSync.ACTION_FIRE)
	elif event.is_action_pressed("reload"):
		_queue_local_action(NetSync.ACTION_RELOAD)
	elif event.is_action_pressed("interact"):
		var pickup_id: String = arena_view.nearest_available_pickup()
		if not pickup_id.is_empty():
			_queue_local_action(NetSync.ACTION_PICKUP, pickup_id)

func _on_peer_connected(peer_id: int) -> void:
	print("PEER_CONNECTED peer_id=%d" % peer_id)
	if dedicated:
		dedicated_stats["connections"] = int(dedicated_stats["connections"]) + 1
		pending_peers[peer_id] = Time.get_ticks_msec()

func _on_peer_disconnected(peer_id: int) -> void:
	pending_peers.erase(peer_id)
	refusal_logs.erase(peer_id)
	var had_session := hall_peers.has(peer_id)
	hall_peers.erase(peer_id)
	if rooms_enabled:
		var room := room_registry.room_of(peer_id) if room_registry != null else null
		if room == null:
			if not server_terminal:
				print("PEER_DISCONNECTED peer_id=%d joined=false hall=%s" % [peer_id, str(had_session)])
			if shutting_down and had_session:
				shutdown_handshake.forget_peer(peer_id)
				shutdown_ready_rejections_logged.erase(peer_id)
				_maybe_close_after_shutdown_ready()
			return
		_use_room(room)
	if dedicated and not rooms_enabled and not lobby.has(peer_id) and not server_terminal:
		print("PEER_DISCONNECTED peer_id=%d joined=false" % peer_id)
	if server_terminal or not lobby.has(peer_id):
		return
	if rooms_enabled:
		# Mesma política da sala única (contagem cancelada, participante
		# eliminado sem anunciar papel), mais a passagem do posto de anfitrião.
		var host_before := current_room.host_peer_id
		current_room.remove_member(peer_id, Time.get_ticks_msec())
		room_registry.unassign(peer_id)
		if current_room.host_peer_id != host_before:
			print("ROOM_HOST room=%d host=%d previous=%d" % [current_room.room_id, current_room.host_peer_id, host_before])
	else:
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
	print("CLIENT_LEFT peer_id=%d count=%d%s" % [peer_id, lobby.size(), _room_log_suffix()])
	if shutting_down:
		# Quem sai durante o encerramento não vai mais confirmar: deixa de ser
		# esperado, e os demais podem concluir sem cair no timeout.
		shutdown_handshake.forget_peer(peer_id)
		shutdown_ready_rejections_logged.erase(peer_id)
		_maybe_close_after_shutdown_ready()
		return
	completed_peers.erase(peer_id)
	impossible_input_rejected_peers.erase(peer_id)
	command_logs.erase(peer_id)
	input_rejection_ticks.erase(peer_id)
	round_ack_peers.erase(peer_id)
	round_late_join_peers.erase(peer_id)
	publish_client_count()
	_publish_room_state()

func _on_connected_to_server() -> void:
	client_connected = true
	if interactive_session and desktop_menu != null:
		desktop_menu.enter(MenuFlow.State.AWAITING_RESPONSE, "", menu_attempt)
	print("CLIENT_CONNECTED id=%s peer_id=%d" % [client_label, multiplayer.get_unique_id()])
	# Teste de incompatibilidade: um binário de desenvolvimento pode se
	# anunciar com outra versão; a build exportada sempre usa a própria.
	var version := NetworkConfig.effective_protocol_version(arguments)
	print("CLIENT_PROTOCOL id=%s version=%d" % [client_label, version])
	request_join.rpc_id(1, version, client_label)

func _on_connection_failed() -> void:
	client_connected = false
	joined = false
	if interactive_session:
		print("CLIENT_CONNECTION_FAILED id=%s" % client_label)
		_return_to_menu("Não foi possível conectar a %s. Confira endereço, porta e se a partida foi criada." % str(arguments.get("url", "")), "connection_failed")
		return
	fail("CLIENT_CONNECTION_FAILED id=%s" % client_label)

func _on_server_disconnected() -> void:
	client_connected = false
	joined = false
	if interactive_session:
		print("CLIENT_SERVER_DISCONNECTED id=%s" % client_label)
		_return_to_menu("O servidor encerrou a partida." if shutdown_prepare_received else "Conexão com o servidor perdida. A partida pode ter sido fechada pelo anfitrião.", "server_disconnected")
		return
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
	# Versão diferente: recusa antes de qualquer registro (lobby, mundo,
	# rodada); nada de rodada ou corpo é enviado a quem não entrou.
	if protocol_version != NetworkConfig.effective_protocol_version(arguments):
		print("JOIN_PROTOCOL_MISMATCH peer_id=%d client=%d server=%d" % [sender, protocol_version, NetworkConfig.effective_protocol_version(arguments)])
		_refuse_join(sender, "protocol_version")
		return
	if rooms_enabled:
		_accept_into_hall(sender, requested_label)
		return
	var reason := lobby.validate_join(sender, requested_label)
	if not reason.is_empty():
		_refuse_join(sender, reason)
		return
	var state := authoritative_world.add_player(sender)
	if state.is_empty():
		_refuse_join(sender, "room_unavailable")
		return
	var join_reason := round_authority.join(sender, requested_label, Time.get_ticks_msec())
	if not join_reason.is_empty():
		authoritative_world.remove_player(sender)
		_refuse_join(sender, join_reason)
		return
	print("CLIENT_JOINED id=%s peer_id=%d count=%d" % [lobby.label_for(sender), sender, lobby.size()])
	if dedicated:
		pending_peers.erase(sender)
		dedicated_stats["joins"] = int(dedicated_stats["joins"]) + 1
	print("SERVER_APPEARANCE peer_id=%d appearance=%s" % [sender, lobby.appearance_for(sender)])
	var spawn: Vector3 = state["position"]
	print("PLAYER_SPAWNED peer_id=%d position=%.2f,%.2f,%.2f" % [sender, spawn.x, spawn.y, spawn.z])
	if round_authority.is_waiting_for_next_round(sender):
		round_late_join_peers[sender] = true
		print("ROUND_LATE_JOIN peer_id=%d round_id=%d count=%d" % [
			sender, round_authority.round_id, round_late_join_peers.size()])
	join_accepted.rpc_id(sender, sender)
	publish_client_count()
	_broadcast_snapshot()
	_publish_round_state(sender)
	if body_registry.size() > 0:
		round_bodies_state.rpc_id(sender, {"round_id": round_authority.round_id, "bodies": body_registry.public_list()})
	_maybe_finish_round_privacy_test()

## Salas online: o handshake só confirma protocolo e nome e põe a conexão no
## "hall" (sem sala). Nada de mundo, rodada ou sala é enviado até ela criar
## uma sala ou entrar por código.
func _accept_into_hall(sender: int, requested_label: String) -> void:
	if hall_peers.has(sender):
		_refuse_join(sender, "invalid_client")
		return
	var label_reason := RoundRules.validate_label(requested_label)
	if not label_reason.is_empty():
		_refuse_join(sender, label_reason)
		return
	# Capacidade: todas as salas cheias mais uma folga para quem ainda escolhe.
	if hall_peers.size() >= room_registry.max_rooms * RoundRules.MAX_PLAYERS + HALL_EXTRA_CAPACITY:
		_refuse_join(sender, "server_full")
		return
	hall_peers[sender] = {"since": Time.get_ticks_msec(), "failures": 0}
	pending_peers.erase(sender)
	if dedicated:
		dedicated_stats["joins"] = int(dedicated_stats["joins"]) + 1
	print("HALL_JOINED peer_id=%d hall=%d rooms=%d" % [sender, hall_peers.size(), room_registry.room_count()])
	room_welcome.rpc_id(sender, {"rooms": true, "min_players": RoundRules.MIN_PLAYERS, "max_players": RoundRules.MAX_PLAYERS})

func _room_log_suffix() -> String:
	return " room=%d" % current_room.room_id if rooms_enabled and current_room != null else ""

## Recusa pública (sem papel nem estado de rodada) e marcador para os testes.
func _refuse_join(sender: int, reason: String) -> void:
	if dedicated:
		# Log limitado por peer: repetir o pedido não inunda o log.
		dedicated_stats["refusals"] = int(dedicated_stats["refusals"]) + 1
		var logged := int(refusal_logs.get(sender, 0))
		refusal_logs[sender] = logged + 1
		if logged < REFUSAL_LOGS_PER_PEER:
			print("JOIN_REFUSED peer_id=%d reason=%s count=%d" % [sender, reason, lobby.size()])
		else:
			dedicated_stats["suppressed_logs"] = int(dedicated_stats["suppressed_logs"]) + 1
		join_rejected.rpc_id(sender, reason)
		return
	print("JOIN_REFUSED peer_id=%d reason=%s count=%d" % [sender, reason, lobby.size()])
	if combat_network_test != null and combat_network_test.has_method("observe_join_refused"):
		combat_network_test.call("observe_join_refused", sender, reason)
	join_rejected.rpc_id(sender, reason)

# --- Salas online (fase 9) -------------------------------------------------------
#
# Cliente -> servidor: `room_create`, `room_join`, `room_set_ready`. Argumentos
# sem tipo: um valor hostil vira recusa registrada, nunca erro de RPC. A sala
# vem sempre do vínculo peer -> sala do servidor, nunca de um id do cliente.
# Servidor -> cliente: `room_welcome`, `room_state` (só aos membros da sala),
# `room_error` (só ao remetente).

@rpc("any_peer", "call_remote", "reliable")
func room_create(requested_label: Variant) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var reason := _room_request_precheck(sender)
	if reason.is_empty() and (typeof(requested_label) != TYPE_STRING or not RoundRules.validate_label(str(requested_label)).is_empty()):
		reason = "invalid_name"
	if reason.is_empty() and not room_registry.can_create():
		reason = "server_full"
	if not reason.is_empty():
		_room_refuse(sender, "create", reason)
		return
	var now := Time.get_ticks_msec()
	var room := room_registry.create_room(now)
	if room == null:
		_room_refuse(sender, "create", "server_full")
		return
	_wire_room(room)
	_use_room(room)
	var result := room.add_member(sender, str(requested_label), now)
	if not str(result["reason"]).is_empty():
		_destroy_room(room, "create_failed")
		_room_refuse(sender, "create", str(result["reason"]))
		return
	room_registry.assign(sender, room)
	print("ROOM_CREATED room=%d rooms=%d" % [room.room_id, room_registry.room_count()])
	_after_room_join(sender, result["state"])

@rpc("any_peer", "call_remote", "reliable")
func room_join(raw_code: Variant, requested_label: Variant) -> void:
	var sender := multiplayer.get_remote_sender_id()
	var reason := _room_request_precheck(sender)
	if not reason.is_empty():
		_room_refuse(sender, "join", reason)
		return
	var code := RoomRules.normalize_code(raw_code)
	var room: MatchRoom = null
	if code.is_empty():
		reason = "invalid_code"
	else:
		room = room_registry.find_by_code(code)
		if room == null:
			reason = "room_not_found"
	if reason.is_empty() and (typeof(requested_label) != TYPE_STRING or not RoundRules.validate_label(str(requested_label)).is_empty()):
		reason = "invalid_name"
	var result := {}
	if reason.is_empty():
		_use_room(room)
		result = room.add_member(sender, str(requested_label), Time.get_ticks_msec())
		reason = str(result["reason"])
	if not reason.is_empty():
		_room_refuse(sender, "join", reason)
		_count_join_failure(sender)
		return
	room_registry.assign(sender, room)
	_after_room_join(sender, result["state"])

@rpc("any_peer", "call_remote", "reliable")
func room_set_ready(value: Variant) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not multiplayer.is_server() or shutting_down or not rooms_enabled:
		return
	if typeof(value) != TYPE_BOOL:
		_room_refuse(sender, "ready", "not_in_room" if room_registry.room_of(sender) == null else "not_ready_phase")
		return
	if not _enter_sender_room(sender):
		_room_refuse(sender, "ready", "not_in_room")
		return
	var reason := current_room.set_ready(sender, bool(value), Time.get_ticks_msec())
	if not reason.is_empty():
		_room_refuse(sender, "ready", reason)
		return
	print("ROOM_READY room=%d peer_id=%d ready=%s ready_count=%d players=%d" % [
		current_room.room_id, sender, str(bool(value)), round_authority.ready_count(), lobby.size()])
	_publish_room_state()

## Checagens comuns de criar/entrar: servidor com salas, handshake feito e
## ainda fora de qualquer sala.
func _room_request_precheck(sender: int) -> String:
	if not multiplayer.is_server() or shutting_down or not rooms_enabled:
		return "rooms_unavailable"
	if not hall_peers.has(sender):
		return "not_in_room"
	if room_registry.room_of(sender) != null:
		return "already_in_room"
	return ""

## Recusa: só ao remetente, com motivo público. Log limitado por peer.
func _room_refuse(sender: int, action: String, reason: String) -> void:
	var logged := int(refusal_logs.get(sender, 0))
	refusal_logs[sender] = logged + 1
	if logged < REFUSAL_LOGS_PER_PEER:
		print("ROOM_REFUSED peer_id=%d action=%s reason=%s" % [sender, action, reason])
	elif dedicated:
		dedicated_stats["suppressed_logs"] = int(dedicated_stats["suppressed_logs"]) + 1
	if sender > 0 and multiplayer.get_peers().has(sender):
		room_error.rpc_id(sender, reason)

## Tentativas de entrada recusadas por conexão: passou do limite, a conexão
## cai (código de convite não vira alvo de força bruta barata). Atrás do
## proxy do Railway o IP visto é o do proxy, então o limite é por conexão.
func _count_join_failure(sender: int) -> void:
	if not hall_peers.has(sender):
		return
	var entry: Dictionary = hall_peers[sender]
	entry["failures"] = int(entry["failures"]) + 1
	if int(entry["failures"]) >= RoomRegistry.MAX_JOIN_FAILURES:
		print("ROOM_JOIN_ATTEMPTS_EXCEEDED peer_id=%d failures=%d" % [sender, int(entry["failures"])])
		room_error.rpc_id(sender, "too_many_attempts")
		_disconnect_peer_later(sender)

func _disconnect_peer_later(peer_id: int) -> void:
	# Fora do callback de RPC: dá tempo de a última mensagem sair.
	get_tree().create_timer(0.2).timeout.connect(func():
		var transport := multiplayer.multiplayer_peer as WebSocketMultiplayerPeer
		if transport != null and multiplayer.get_peers().has(peer_id):
			transport.disconnect_peer(peer_id))

## Entrada aceita numa sala: o mesmo caminho da sala única (entrada, spawn,
## estado da rodada, corpos) mais o estado da sala, tudo só para esta sala.
func _after_room_join(sender: int, state: Dictionary) -> void:
	print("CLIENT_JOINED id=%s peer_id=%d count=%d%s" % [lobby.label_for(sender), sender, lobby.size(), _room_log_suffix()])
	print("SERVER_APPEARANCE peer_id=%d appearance=%s" % [sender, lobby.appearance_for(sender)])
	var spawn: Vector3 = state["position"]
	print("PLAYER_SPAWNED peer_id=%d position=%.2f,%.2f,%.2f" % [sender, spawn.x, spawn.y, spawn.z])
	join_accepted.rpc_id(sender, sender)
	publish_client_count()
	_broadcast_snapshot()
	_publish_round_state(sender)
	if body_registry.size() > 0:
		round_bodies_state.rpc_id(sender, {"round_id": round_authority.round_id, "bodies": body_registry.public_list()})
	_publish_room_state()

## Estado público da sala, a todos os membros da sala corrente e só a eles.
func _publish_room_state() -> void:
	if not rooms_enabled or current_room == null or shutting_down or not multiplayer.is_server():
		return
	var payload := current_room.public_state(Time.get_ticks_msec())
	for peer_id in _open_members():
		room_state.rpc_id(int(peer_id), payload)

func _destroy_room(room: MatchRoom, reason: String) -> Array:
	_unwire_room(room)
	var members := room_registry.destroy(room)
	if current_room == room:
		current_room = null
	print("ROOM_DESTROYED room=%d reason=%s members=%d rooms=%d" % [room.room_id, reason, members.size(), room_registry.room_count()])
	return members

## Uma vez por segundo: salas vazias depois da carência, lobbies parados e
## conexões esquecidas no hall.
func _rooms_housekeeping(now_msec: int) -> void:
	if now_msec < rooms_next_housekeeping_msec or room_registry == null:
		return
	rooms_next_housekeeping_msec = now_msec + 1000
	for due in room_registry.due_for_removal(now_msec):
		var members := _destroy_room(due["room"], str(due["reason"]))
		for peer_id in members:
			room_error.rpc_id(int(peer_id), "room_expired")
			_disconnect_peer_later(int(peer_id))
	for peer_id in hall_peers.keys():
		if room_registry.room_of(int(peer_id)) == null \
				and now_msec - int(hall_peers[peer_id]["since"]) >= RoomRegistry.HALL_IDLE_MSEC:
			print("HALL_IDLE_TIMEOUT peer_id=%d" % int(peer_id))
			hall_peers[peer_id]["since"] = now_msec
			_disconnect_peer_later(int(peer_id))

@rpc("authority", "call_remote", "reliable")
func room_welcome(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_on_room_welcome(payload)

@rpc("authority", "call_remote", "reliable")
func room_state(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_on_room_state(payload)

@rpc("authority", "call_remote", "reliable")
func room_error(reason: String) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	_on_room_error(reason)

@rpc("authority", "call_remote", "reliable")
func join_accepted(peer_id: int) -> void:
	joined = true
	if online_rooms:
		# Salas online: entrou numa sala. A mansão é montada agora, oculta; o
		# menu continua mostrando a sala até a rodada começar.
		if interactive_session and desktop_menu != null and arena_view == null:
			_create_client_presentation()
			_set_game_view(false)
	elif interactive_session and desktop_menu != null:
		desktop_menu.enter(MenuFlow.State.CONNECTED, "", menu_attempt)
		desktop_menu.queue_free()
		desktop_menu = null
		_create_client_presentation()
		_show_session_label(str(arguments.get("url", "")))
	if arena_view != null:
		arena_view.local_peer_id = peer_id
	print("JOIN_ACCEPTED id=%s peer_id=%d" % [client_label, peer_id])
	if NetworkConfig.bool_argument(arguments, "probe"):
		# Entrou: agora espera tráfego de jogo real (snapshots e estado público
		# da rodada) antes de sair.
		probe_joined_msec = Time.get_ticks_msec()
		probe_peer_id = peer_id
		return
	var leave_after := NetworkConfig.integer_argument(arguments, "menu-leave-after-msec", 0)
	if interactive_session and leave_after > 0:
		get_tree().create_timer(float(leave_after) / 1000.0).timeout.connect(func():
			if not returning_to_menu: _return_to_menu("Você saiu da partida.", "left"))
	if interactive_session and leave_trigger == "joined":
		call_deferred("_return_to_menu", "Você saiu da partida.", "left")

@rpc("authority", "call_remote", "reliable")
func join_rejected(reason: String) -> void:
	if interactive_session:
		print("JOIN_REJECTED id=%s reason=%s" % [client_label, reason])
		var messages := {
			"protocol_version": "Versão incompatível do jogo (este build usa o protocolo %d). Use o mesmo build do anfitrião." % NetworkConfig.effective_protocol_version(arguments),
			"room_unavailable": "A sala está cheia (8 jogadores). Tente mais tarde ou crie outra partida.",
			"name_taken": "Já existe alguém com esse nome nesta sala. Escolha outro nome.",
			"invalid_client": "Nome recusado pelo servidor.",
		}
		var message := str(messages.get(reason, "Entrada recusada pelo servidor."))
		print("JOIN_REJECTED_MESSAGE id=%s text=%s" % [client_label, message])
		_return_to_menu(message, "join_rejected")
		return
	if NetworkConfig.bool_argument(arguments, "probe"):
		# Sala cheia ou nome em uso ainda provam um servidor vivo falando o
		# mesmo protocolo; versão diferente não.
		if reason in ["room_unavailable", "name_taken"]:
			_finish_probe("refused", reason)
			return
		print("PROBE_FAILED url=%s reason=join_rejected:%s" % [str(arguments.get("url", "")), reason])
		get_tree().quit(1)
		return
	fail("JOIN_REJECTED id=%s reason=%s" % [client_label, reason])

## Sonda de prontidão (fase 8): um cliente Godot real conecta, faz o
## handshake do protocolo e sai. Não joga e não fica na sala.
var probe_finished := false
var probe_joined_msec := 0
var probe_peer_id := 0
var probe_snapshots := 0
const PROBE_GAME_TRAFFIC_MSEC := 10000
const PROBE_MIN_SNAPSHOTS := 3

func _check_probe_traffic() -> void:
	if probe_finished or probe_joined_msec == 0:
		return
	# Servidor com salas: a sonda também espera o estado da sala que criou (ou
	# em que entrou); ao sair, a sala vazia é destruída depois da carência.
	if probe_snapshots >= PROBE_MIN_SNAPSHOTS and not local_round_public.is_empty() \
			and (not online_rooms or not local_room_state.is_empty()):
		_finish_probe("joined", "peer_id=%d snapshots=%d round_state=%s%s" % [probe_peer_id, probe_snapshots,
			RoundState.to_label(int(local_round_public.get("state", RoundState.WAITING))),
			" room=%s" % str(local_room_state.get("phase", "")) if online_rooms else ""])
	elif Time.get_ticks_msec() - probe_joined_msec > PROBE_GAME_TRAFFIC_MSEC:
		probe_finished = true
		print("PROBE_FAILED url=%s reason=no_game_traffic snapshots=%d round_state_received=%s" % [
			str(arguments.get("url", "")), probe_snapshots, str(not local_round_public.is_empty())])
		get_tree().quit(1)

func _finish_probe(result: String, detail: String) -> void:
	if probe_finished:
		return
	probe_finished = true
	var elapsed := Time.get_ticks_msec() - started_at_msec
	print("PROBE_OK url=%s result=%s detail=%s protocol=%d elapsed_ms=%d" % [
		str(arguments.get("url", "")), result, detail, NetworkConfig.PROTOCOL_VERSION, elapsed])
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	get_tree().quit(0)

func publish_client_count() -> void:
	if shutting_down:
		return
	for peer_id in _open_members():
		client_count_changed.rpc_id(int(peer_id), lobby.size())
	_publish_round_state()

@rpc("authority", "call_remote", "reliable")
func client_count_changed(count: int) -> void:
	print("CLIENT_COUNT id=%s count=%d" % [client_label, count])
	if expected_clients > 0 and count >= expected_clients:
		test_roster_ready = true
		_try_start_test_movement()

func _try_start_test_movement() -> void:
	if not test_roster_ready or not client_spawn_known or test_movement_started:
		return
	if expected_clients > 0:
		test_movement_started = true
		var client_number := int(client_label.trim_prefix("client-"))
		var directions := [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]
		test_direction = directions[(client_number - 1) % directions.size()]
		if client_label == "client-1":
			_send_input(Vector2(99.0, 0.0), 0.0)
		else:
			_send_input(test_direction, 0.0, test_pitch_delta())

var _last_pitch_log := ""
## Teste de movimento: pitch oficial dos outros jogadores como chegou aqui.
func _log_observed_pitches(states: Array) -> void:
	var parts: Array = []
	for raw_state in states:
		if typeof(raw_state) != TYPE_DICTIONARY:
			continue
		var state: Dictionary = raw_state
		if int(state.get("peer_id", 0)) == multiplayer.get_unique_id():
			continue
		parts.append("%d:%.3f" % [int(state.get("peer_id", 0)), MovementRules.clamp_pitch(state.get("pitch", 0.0))])
	parts.sort()
	var line := ",".join(parts)
	if line != _last_pitch_log:
		_last_pitch_log = line
		print("CLIENT_OBSERVED_PITCHES id=%s map=%s" % [client_label, line])

## Pitch que cada cliente do teste de movimento pede (distinto por cliente),
## para provar que o servidor aplica e todos os outros clientes o recebem.
func test_pitch_delta() -> float:
	var client_number := int(client_label.trim_prefix("client-"))
	return [0.3, -0.2, -0.3, 0.2][(client_number - 1) % 4]

## Intenção de teste (clientes headless): vale até ser trocada e segue pelo
## mesmo fluxo de comandos do jogador humano, um comando por tick.
func _send_input(move: Vector2, yaw_delta: float, pitch_delta: float = 0.0) -> void:
	test_move_intent = move
	prediction.add_look(yaw_delta, pitch_delta)

# --- Comandos (protocolo 9) ---------------------------------------------------

func _movement_test_client() -> bool:
	return expected_clients > 0

## O cliente só comanda com estado previsto válido, na época aberta pelo
## servidor, e quando pode agir (ou no teste de movimento sem rodada).
func _commands_enabled() -> bool:
	return mode == "client" and joined and client_connected and not shutdown_prepare_received \
		and prediction.has_state and not awaiting_epoch_sync \
		and (_client_can_gameplay() or _movement_test_client())

func _sample_move() -> Vector2:
	if NetworkConfig.should_poll_human_input(joined, expected_clients, round_test_mode,
			combat_network_test != null, arena_view != null):
		# Sem foco não há movimento (e o mouse residual já foi descartado).
		if not window_focused:
			return Vector2.ZERO
		return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	return test_move_intent

## Um comando por tick fixo de física: amostra, simula localmente, guarda para
## replay e envia em lote (ou na hora, se carrega ação).
func _client_command_tick() -> void:
	if not _commands_enabled():
		if not outbox.is_empty():
			_flush_commands()
		return
	if not test_script.is_empty():
		_apply_test_script_tick()
	var command := prediction.build_command(_sample_move())
	outbox.append(command)
	ticks_since_send += 1
	net_stats.pending_observed(prediction.pending.size(), prediction.oldest_pending_age_usec())
	if ticks_since_send >= NetSync.SEND_INTERVAL_TICKS or not (command["action"] as Dictionary).is_empty() \
			or outbox.size() >= NetSync.MAX_COMMANDS_PER_PACKET:
		_flush_commands()

func _flush_commands() -> void:
	ticks_since_send = 0
	if shutdown_prepare_received or not client_connected:
		outbox.clear()
		return
	while not outbox.is_empty():
		var first: Dictionary = outbox[0]
		var encoded: Array = []
		var count := 0
		while count < outbox.size() and count < NetSync.MAX_COMMANDS_PER_PACKET \
				and int((outbox[count] as Dictionary)["epoch"]) == int(first["epoch"]) \
				and int((outbox[count] as Dictionary)["seq"]) == int(first["seq"]) + count:
			var command: Dictionary = outbox[count]
			encoded.append(NetSync.encode_command(command["move"], float(command["yaw_delta"]),
				float(command["pitch_delta"]), NetSync.encode_action(command["action"])))
			count += 1
		outbox = outbox.slice(count)
		submit_commands.rpc_id(1, NetSync.encode_packet(int(first["epoch"]), int(first["seq"]), encoded))
		net_stats.sent_commands += count
		net_stats.sent_packets += 1

## Roteiro de teste por tick (coordenador de sincronização): cada entrada
## define movimento e mira do tick e, opcionalmente, uma ação antes ou depois
## do giro do mesmo tick, pelo mesmo caminho do jogador humano.
var test_script: Array = []
func _apply_test_script_tick() -> void:
	var entry: Dictionary = test_script.pop_front()
	test_move_intent = entry.get("move", Vector2.ZERO)
	var look: Vector2 = entry.get("look", Vector2.ZERO)
	var action: Dictionary = entry.get("action", {})
	if str(entry.get("order", "look_then_action")) == "action_then_look":
		_queue_script_action(action)
		prediction.add_look(look.x, look.y)
	else:
		prediction.add_look(look.x, look.y)
		_queue_script_action(action)

func _queue_script_action(action: Dictionary) -> void:
	if not action.is_empty() and prediction.queue_action(action):
		net_stats.action_started(str(action["kind"]), int(action["id"]))

## Identificador de ação por rodada: recomeça em 1 quando a rodada privada
## muda (o servidor também zera por rodada).
func _next_action_id(kind: String) -> int:
	var round_id := int(local_combat_state.get("round_id", 0))
	if round_id != action_round_id:
		action_round_id = round_id
		action_ids = {"fire": 0, "reload": 0, "pickup": 0}
	return int(action_ids[kind]) + 1

func _queue_local_action(kind: String, pickup_id: String = "") -> bool:
	var id := _next_action_id(kind)
	var action := {"kind": kind, "id": id}
	if kind == NetSync.ACTION_PICKUP:
		action["pickup_id"] = pickup_id
	if not prediction.queue_action(action):
		return false
	action_ids[kind] = id
	net_stats.action_started(kind, id)
	if kind == NetSync.ACTION_FIRE and arena_view != null:
		arena_view.predict_local_shot(id)
	return true

## Teste: ação com identificador escolhido pelo coordenador, pelo mesmo fluxo.
func queue_test_action(kind: String, id: int, pickup_id: String = "") -> bool:
	var action := {"kind": kind, "id": id}
	if kind == NetSync.ACTION_PICKUP:
		action["pickup_id"] = pickup_id
	return prediction.queue_action(action)

## Teste: pacote montado à mão, fora da previsão (espectador ou rodada
## encerrada), com sequências novas desta conexão.
func send_test_packet(actions: Array, move: Vector2 = Vector2.ZERO) -> void:
	if shutdown_prepare_received or not client_connected:
		return
	var encoded: Array = []
	for action in actions:
		encoded.append(NetSync.encode_command(move, 0.0, 0.0, NetSync.encode_action(action)))
	var first_seq := prediction.next_seq
	prediction.next_seq += encoded.size()
	submit_commands.rpc_id(1, NetSync.encode_packet(prediction.epoch, first_seq, encoded))

func _local_presented(delta: float) -> Dictionary:
	if not _commands_enabled():
		return {}
	var presented := prediction.presented(Engine.get_physics_interpolation_fraction(), delta)
	if int(presented.get("look_latency_usec", 0)) > 0:
		net_stats.record(net_stats.look_latency_ms, float(presented["look_latency_usec"]) / 1000.0)
	return presented

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_commands(payload: Variant) -> void:
	if not multiplayer.is_server() or shutting_down:
		return
	# Remetente derivado da conexão; o pacote não carrega identidade.
	var sender := multiplayer.get_remote_sender_id()
	if not _enter_sender_room(sender):
		return
	if not lobby.has(sender) or authoritative_world == null:
		return
	var result := authoritative_world.receive_commands(sender, payload, Time.get_ticks_msec())
	var reason := str(result.get("reason", ""))
	if not reason.is_empty():
		_log_command_rejection(sender, reason)
	for dropped in result.get("dropped_actions", []):
		_reject_action(sender, dropped["action"], str(dropped["reason"]))
	if int(result.get("queued", 0)) > 0 and authoritative_world.states.has(sender):
		var state: Dictionary = authoritative_world.states[sender]
		if not bool(state["movement_logged"]):
			state["movement_logged"] = true
			print("MOVEMENT_AUTHORIZED peer_id=%d" % sender)

## Uma linha por peer e motivo: pacote hostil repetido não vira spam de log.
func _log_command_rejection(sender: int, reason: String) -> void:
	var logged: Dictionary = command_logs.get(sender, {})
	if logged.has(reason) or logged.size() >= 16:
		return
	logged[reason] = true
	command_logs[sender] = logged
	print("COMMANDS_REJECTED peer_id=%d reason=%s" % [sender, reason])

## Pode o jogador agir neste tick? Vazio se sim; senão o motivo.
func _command_gate(peer_id: int) -> String:
	if NetworkConfig.integer_argument(arguments, "stop-after-clients", 0) > 0:
		return ""
	if round_authority == null or round_authority.state != RoundState.ACTIVE:
		return "round_not_active"
	if not round_authority.is_participant(peer_id):
		return "not_participant"
	if not round_authority.is_alive(peer_id):
		return "player_dead"
	return ""

## Ação no ponto causal: mira do comando já aplicada, movimento do tick não.
func _run_command_action(peer_id: int, action: Dictionary, _seq: int) -> void:
	var kind := str(action["kind"])
	var id := int(action["id"])
	var now := Time.get_ticks_msec()
	var result: Dictionary
	if kind == NetSync.ACTION_FIRE:
		result = combat_authority.request_fire(peer_id, id, now)
	elif kind == NetSync.ACTION_RELOAD:
		result = combat_authority.request_reload(peer_id, id, now)
	else:
		result = combat_authority.request_pickup(peer_id, action.get("pickup_id", ""), id, now)
	_report_action_result(peer_id, kind, id, result)

func _report_action_result(peer_id: int, kind: String, id: int, result: Dictionary) -> void:
	_observe_spectator_block(peer_id, kind, result)
	if combat_network_test != null: combat_network_test.call("observe_server_action", peer_id, kind, id, result)
	if not lobby.has(peer_id) or shutting_down:
		return
	if not bool(result.get("accepted", false)):
		combat_action_rejected.rpc_id(peer_id, kind, id, _safe_combat_reason(result.get("reason", "rejected")))
	elif kind == NetSync.ACTION_FIRE and bool(result.get("hit", false)):
		combat_hit_confirmed.rpc_id(peer_id)

## Ação que não chegou a executar (comando recusado ou descartado): resultado
## explícito, pelo mesmo caminho das recusas de combate.
func _reject_action(peer_id: int, action: Dictionary, reason: String) -> void:
	if action.is_empty():
		return
	_report_action_result(peer_id, str(action["kind"]), int(action["id"]), {"accepted": false, "reason": reason})

func _on_command_rejected(peer_id: int, seq: int, action: Dictionary, reason: String) -> void:
	var gate_reasons := ["round_not_active", "not_participant", "player_dead", "stale_epoch"]
	if spectator_reveal_test_mode and peer_id == spectator_test_dead_peer and reason == "player_dead" \
			and round_authority.state == RoundState.ACTIVE:
		spectator_test_movement_blocked = true
		_maybe_finish_spectator_probe()
	if reason not in gate_reasons:
		# Comando inválido de verdade (magnitude, não finito, taxa de mira).
		if reason == "move_magnitude":
			impossible_input_rejected_peers[peer_id] = true
		if int(input_rejection_ticks.get(peer_id, -1)) != server_tick and lobby.has(peer_id) and not shutting_down:
			input_rejection_ticks[peer_id] = server_tick
			print("INPUT_REJECTED peer_id=%d reason=%s" % [peer_id, reason])
			input_rejected.rpc_id(peer_id, reason, seq)
	_reject_action(peer_id, action, reason if reason in gate_reasons else "input_rejected")

@rpc("authority", "call_remote", "reliable")
func input_rejected(reason: String, _sequence: int) -> void:
	net_stats.count_rejection("input_" + reason)
	# Teste de movimento: a intenção impossível vale até a primeira recusa; as
	# recusas seguintes dos comandos já em trânsito não repetem a troca.
	if expected_clients > 0 and client_label == "client-1" and reason == "move_magnitude" and not client_movement_observed \
			and test_move_intent.length() > 1.0:
		print("CLIENT_IMPOSSIBLE_INPUT_REJECTED id=%s" % client_label)
		_send_input(test_direction, 0.0, test_pitch_delta())

## Snapshot por destinatário. Descarta outra sessão de servidor e tick antigo
## ou repetido; reconcilia a previsão com o ACK privado.
@rpc("authority", "call_remote", "unreliable_ordered")
func world_snapshot(payload: Dictionary) -> void:
	if multiplayer.is_server() or shutdown_prepare_received:
		return
	if online_rooms:
		for raw_state in payload.get("players", []):
			if typeof(raw_state) == TYPE_DICTIONARY: _note_peer((raw_state as Dictionary).get("peer_id", 0), "snapshot")
	var rejection := snapshot_rejection(payload, snapshot_session, last_snapshot_tick)
	if rejection == "foreign_session":
		net_stats.foreign_session_snapshots += 1
	elif rejection == "stale_tick":
		net_stats.stale_snapshots += 1
	if not rejection.is_empty():
		return
	snapshot_session = int(payload["session"])
	var tick := int(payload["tick"])
	last_snapshot_tick = tick
	net_stats.snapshot_received()
	if probe_joined_msec > 0:
		probe_snapshots += 1
		_check_probe_traffic()
	var states: Array = []
	for raw_state in payload["players"]:
		if typeof(raw_state) == TYPE_DICTIONARY and typeof((raw_state as Dictionary).get("peer_id")) == TYPE_INT \
				and typeof((raw_state as Dictionary).get("position")) == TYPE_VECTOR3:
			states.append(raw_state)
	var ack: Dictionary = payload.get("ack", {})
	if combat_network_test != null: combat_network_test.call("observe_client_event", "snapshot", payload)
	var own_id := multiplayer.get_unique_id()
	for raw_state in states:
		var state: Dictionary = raw_state
		if int(state["peer_id"]) == own_id and not ack.is_empty():
			prediction.reconcile(ack, state)
			awaiting_epoch_sync = false
	if arena_view != null:
		arena_view.apply_snapshot(states, tick)
		_update_pickup_prompt()
	if expected_clients > 0:
		_log_observed_pitches(states)
	if spectator_reveal_test_mode and local_eliminated and not spectator_test_follow_confirmed:
		for raw_spectator_state in states:
			if int((raw_spectator_state as Dictionary).get("peer_id", 0)) == _spectator_target():
				spectator_test_follow_confirmed = true
				print("SPECTATOR_FOLLOW_OK id=%s" % client_label)
				# Morto tentando andar, coletar, atirar e recarregar pelo fluxo
				# normal de comandos: o servidor recusa cada um (player_dead).
				send_test_packet([
					{"kind": NetSync.ACTION_PICKUP, "id": 1, "pickup_id": "weapon_0"},
					{"kind": NetSync.ACTION_FIRE, "id": 1},
					{"kind": NetSync.ACTION_RELOAD, "id": 1}], Vector2.RIGHT)
				spectator_test_followed.rpc_id(1)
				break
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
	if not _enter_sender_room(sender):
		return
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
		print("PLAYER_STATE peer_id=%d position=%.3f,%.3f,%.3f speed=%.3f pitch=%.3f" % [peer_id, position.x, position.y, position.z, speed, float(state.get("pitch", 0.0))])
	print("SERVER_MOVEMENT_TEST_OK players=%d max_speed=%.3f rejected_impossible=%d" % [completed_peers.size(), observed_max_speed, impossible_input_rejected_peers.size()])

func _begin_server_shutdown(peer_ids: Array) -> void:
	if shutting_down:
		return
	shutting_down = true
	var generation := shutdown_handshake.begin(peer_ids)
	if not operator_shutdown:
		print("SERVER_TEST_OK clients=%d" % shutdown_handshake.expected_count())
	for peer_id in shutdown_handshake.expected.keys():
		# O token só existe depois de registrado o envio para este peer; nenhuma
		# confirmação anterior pode conhecê-lo.
		var token := shutdown_handshake.prepare_token_for(int(peer_id))
		shutdown_prepare.rpc_id(int(peer_id), generation, token)
	print("SERVER_SHUTDOWN_PREPARE_SENT generation=%d peers=%d" % [generation, shutdown_handshake.sent_tokens.size()])
	shutdown_prepare_timer.start(2.0)

## Preparação de encerramento. Só vem da autoridade; o cliente confirma uma única
## vez, devolvendo exatamente a geração e o token que recebeu.
@rpc("authority", "call_remote", "reliable")
func shutdown_prepare(generation: int, token: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if shutdown_prepare_received or generation <= 0 or token == 0 or not client_connected:
		return
	shutdown_prepare_received = true
	print("CLIENT_SHUTDOWN_PREPARE id=%s" % client_label)
	shutdown_ready.rpc_id(1, generation, token)

## Argumentos sem tipo: um valor hostil vira recusa registrada, não erro de RPC.
@rpc("any_peer", "call_remote", "reliable")
func shutdown_ready(generation: Variant, token: Variant) -> void:
	if not multiplayer.is_server() or server_peer_closing or server_terminal:
		return
	var sender := multiplayer.get_remote_sender_id()
	var reason := ShutdownHandshake.REASON_UNEXPECTED_PEER
	if _is_session_peer(sender):
		reason = shutdown_handshake.accept_ready(sender, generation, token)
	if not reason.is_empty():
		_log_shutdown_ready_rejection(sender, reason)
		return
	print("CLIENT_SHUTDOWN_READY peer_id=%d count=%d" % [sender, shutdown_handshake.ready_count()])
	_maybe_close_after_shutdown_ready()

func _maybe_close_after_shutdown_ready() -> void:
	if not shutting_down or server_peer_closing or not shutdown_handshake.is_complete():
		return
	_cancel_shutdown_prepare_timeout()
	print("SERVER_SHUTDOWN_READY clients=%d" % shutdown_handshake.ready_count())
	if combat_network_test != null: print("COMBAT_SHUTDOWN_READY clients=%d" % shutdown_handshake.ready_count())
	call_deferred("_close_server_peer")

## Uma linha por peer e motivo: um peer hostil não transforma spam em log.
func _log_shutdown_ready_rejection(sender: int, reason: String) -> void:
	var logged: Dictionary = shutdown_ready_rejections_logged.get(sender, {})
	if logged.has(reason) or shutdown_ready_rejections_logged.size() > RoundRules.MAX_PLAYERS * 4:
		return
	logged[reason] = true
	shutdown_ready_rejections_logged[sender] = logged
	print("SHUTDOWN_READY_REJECTED peer_id=%d reason=%s" % [sender, reason])

func _cancel_shutdown_prepare_timeout() -> void:
	if shutdown_prepare_timer == null:
		return
	shutdown_prepare_timer.stop()

func _close_server_peer() -> void:
	if server_peer_closing or server_terminal:
		return
	server_peer_closing = true
	server_terminal = true
	closed_session_count = shutdown_handshake.expected_count()
	if rooms_enabled:
		# Todas as salas saem junto com o processo (salas são efêmeras).
		for room in room_registry.rooms.values():
			_unwire_room(room)
		room_registry.clear()
		hall_peers.clear()
		current_room = null
	else:
		if round_authority != null:
			round_authority.clear()
		lobby.clear()
		if authoritative_world != null:
			authoritative_world.clear()
		if combat_authority != null:
			combat_authority.clear_round()
	completed_peers.clear()
	impossible_input_rejected_peers.clear()
	command_logs.clear()
	input_rejection_ticks.clear()
	shutdown_handshake.clear()
	shutdown_ready_rejections_logged.clear()
	round_ack_peers.clear()
	round_late_join_peers.clear()
	multiplayer.multiplayer_peer.close()
	print("SERVER_SHUTDOWN_COMPLETE closed=%d" % closed_session_count)
	if dedicated:
		print("DEDICATED_EXIT code=0 reason=%s" % ("operator" if operator_shutdown else "shutdown"))
	if combat_network_test != null: print("COMBAT_SHUTDOWN_COMPLETE clients=%d" % closed_session_count)
	get_tree().quit(0)

func _server_shutdown_timeout() -> void:
	if server_terminal or shutdown_handshake.is_complete():
		return
	print("SERVER_SHUTDOWN_TIMEOUT ready=%d remaining=%d" % [shutdown_handshake.ready_count(), _session_peers().size()])
	if operator_shutdown:
		# Encerramento pedido pelo operador: cliente que não confirmou a tempo
		# é desconectado e o processo sai normalmente (não é falha).
		print("DEDICATED_SHUTDOWN_DEADLINE ready=%d remaining=%d" % [shutdown_handshake.ready_count(), lobby.size()])
		_close_server_peer()
		return
	get_tree().quit(1)

# --- Servidor dedicado (fase 8) -------------------------------------------------

## Manutenção leve do servidor dedicado, a cada ~0,25 s: pedido de
## encerramento, prazo de entrada e linha de status periódica.
func _dedicated_housekeeping(now_msec: int) -> void:
	if now_msec < dedicated_next_poll_msec:
		return
	dedicated_next_poll_msec = now_msec + 250
	var stop_file := str(dedicated_config.get("shutdown_file", ""))
	if not operator_shutdown and not stop_file.is_empty() and FileAccess.file_exists(stop_file):
		_begin_operator_shutdown("signal")
		return
	if shutting_down:
		return
	for peer_id in pending_peers.keys():
		if now_msec - int(pending_peers[peer_id]) < DedicatedConfig.JOIN_DEADLINE_MSEC:
			continue
		pending_peers.erase(peer_id)
		dedicated_stats["deadline_drops"] = int(dedicated_stats["deadline_drops"]) + 1
		if int(dedicated_stats["deadline_drops"]) <= 20:
			print("DEDICATED_JOIN_DEADLINE peer_id=%d" % int(peer_id))
		else:
			dedicated_stats["suppressed_logs"] = int(dedicated_stats["suppressed_logs"]) + 1
		if multiplayer.multiplayer_peer != null:
			(multiplayer.multiplayer_peer as WebSocketMultiplayerPeer).disconnect_peer(int(peer_id))
	var interval := int(dedicated_config.get("status_interval_seconds", 0))
	if interval > 0 and now_msec >= dedicated_next_status_msec:
		dedicated_next_status_msec = now_msec + interval * 1000
		_print_dedicated_status(now_msec)

## Uma linha, sem nomes, papéis ou inventário: só contadores e recursos.
func _print_dedicated_status(now_msec: int) -> void:
	var peers := multiplayer.get_peers().size() if multiplayer.multiplayer_peer != null else 0
	var rooms := room_registry.room_count() if room_registry != null else 0
	var playing := 0
	if room_registry != null:
		for room in room_registry.rooms.values():
			if (room as MatchRoom).round_authority.state == RoundState.ACTIVE:
				playing += 1
	print("DEDICATED_STATUS uptime_s=%d peers=%d hall=%d pending=%d rooms=%d rooms_playing=%d room_members=%d connections=%d joins=%d refusals=%d deadline_drops=%d suppressed_logs=%d rss_mb=%.1f objects=%d nodes=%d" % [
		(now_msec - dedicated_started_msec) / 1000, peers, hall_peers.size(), pending_peers.size(),
		rooms, playing, room_registry.total_members() if room_registry != null else 0,
		int(dedicated_stats["connections"]), int(dedicated_stats["joins"]), int(dedicated_stats["refusals"]),
		int(dedicated_stats["deadline_drops"]), int(dedicated_stats["suppressed_logs"]),
		_process_rss_mb(),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])

## Memória residente do processo (Linux, /proc). Em build release o contador
## estático do Godot não é mantido; -1 onde /proc não existe.
func _process_rss_mb() -> float:
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	if file == null:
		return -1.0
	# Arquivos de /proc informam tamanho 0: lê linha a linha até o fim.
	while not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("VmRSS:"):
			return float(line.trim_prefix("VmRSS:").strip_edges().split(" ")[0]) / 1024.0
	return -1.0

## Encerramento pedido pelo operador (SIGTERM traduzido pelo wrapper do
## container): para de aceitar entradas, avisa os jogadores pelo handshake
## existente, fecha os peers e sai com 0 dentro de um prazo curto.
func _begin_operator_shutdown(reason: String) -> void:
	if operator_shutdown or server_terminal:
		return
	operator_shutdown = true
	print("DEDICATED_SHUTDOWN_REQUESTED reason=%s lobby=%d peers=%d" % [reason, _session_peers().size(), multiplayer.get_peers().size()])
	_print_dedicated_status(Time.get_ticks_msec())
	if _session_peers().is_empty():
		shutting_down = true
		_close_server_peer()
		return
	# Todas as sessões (hall e salas) recebem o aviso de encerramento.
	_begin_server_shutdown(_session_peers())

# --- Ciclo de partida --------------------------------------------------------
#
# Mensagens públicas: `round_public_state` e `round_roster`, em broadcast.
# Mensagem privada: `round_private_role`, sempre por `rpc_id` ao próprio dono.
# Estado interno do servidor (mapa de papéis, seed, avaliação de vitória)
# jamais sai de `RoundAuthority`.

func _on_round_state_changed(state: int, round_id: int) -> void:
	print("ROUND_STATE state=%s round_id=%d players=%d participants=%d%s" % [
		RoundState.to_label(state), round_id, lobby.size(), round_authority.participants.size(), _room_log_suffix()])
	_publish_round_state()
	if rooms_enabled and current_room != null:
		current_room.touch(Time.get_ticks_msec())
		_publish_room_state()
	if spectator_reveal_test_mode and state == RoundState.COUNTDOWN \
			and spectator_reveal_acks.size() == round_stop_after:
		print("ROUND_REVEAL_CLEARED_OK")
		_begin_server_shutdown(lobby.peer_ids())

func _on_round_roles_ready(round_id: int, participant_ids: Array) -> void:
	combat_authority.begin_round(round_id, participant_ids)
	# Nova época de controle: comandos da fase anterior (ainda em trânsito)
	# são recusados sem efeito, com resultado explícito para suas ações.
	# Fase 6: todos os participantes (vivos ou não na rodada anterior) voltam
	# ao spawn oficial, parados, com época nova. Corpos da rodada anterior saem
	# antes de os vivos aparecerem.
	body_registry.clear()
	for raw_peer_id in _open_members():
		round_bodies_state.rpc_id(int(raw_peer_id), {"round_id": round_id, "bodies": []})
	for raw_peer_id in participant_ids:
		authoritative_world.reset_to_spawn(int(raw_peer_id))
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
	if not alive:
		# Eliminado: nova época (fila antiga recusada) e velocidade zerada.
		authoritative_world.bump_epoch(peer_id)
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
	call_deferred("_clear_combat_round_if_ended", round_id, current_room)

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
	print("ROUND_REVEAL_SENT round_id=%d peers=%d%s" % [reveal_round_id, delivered, _room_log_suffix()])
	if rooms_enabled and current_room != null:
		# Resultado público da sala (papéis por nome), mostrado no lobby dela.
		current_room.record_result(result)
		_publish_room_state()

func _clear_combat_round_if_ended(ended_round_id: int, room: MatchRoom = null) -> void:
	if room != null:
		# Adiada: a sala pode ter saído do registro no meio tempo.
		if rooms_enabled and not room_registry.rooms.has(room.room_id):
			return
		_use_room(room)
	if combat_authority != null and round_authority.state == RoundState.ENDED \
			and round_authority.round_id == ended_round_id and combat_authority.active_round_id == ended_round_id:
		combat_authority.clear_round()

func _on_round_reset(round_id: int) -> void:
	round_ack_peers.clear()
	round_late_join_peers.clear()
	print("ROUND_RESET round_id=%d players=%d%s" % [round_id, lobby.size(), _room_log_suffix()])

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
	# Só os membros desta sala (nunca broadcast a todas as conexões).
	for peer_id in _open_members():
		round_public_state.rpc_id(int(peer_id), payload)
		round_roster.rpc_id(int(peer_id), roster)

@rpc("authority", "call_remote", "reliable")
func round_public_state(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	var previous_state := int(local_round_public.get("state", RoundState.WAITING))
	local_round_public = payload
	var state := int(payload.get("state", RoundState.WAITING))
	if state == RoundState.ACTIVE and previous_state != RoundState.ACTIVE:
		# A rodada abriu uma época nova no servidor: espera o próximo ACK.
		awaiting_epoch_sync = true
		prediction.clear_look()
		# Ações sem resultado da rodada anterior não atravessam rodadas.
		net_stats.clear_actions()
		# Corpos da rodada anterior saem antes de os vivos reaparecerem.
		var active_round := int(payload.get("round_id", 0))
		for body_id in local_bodies.keys():
			if int(local_bodies[body_id]["round_id"]) != active_round:
				local_bodies.erase(body_id)
		if arena_view != null:
			arena_view.clear_bodies(active_round)
	if interactive_session and leave_trigger == "active" and state == RoundState.ACTIVE:
		# Automação de teste: sai pouco depois, como um jogador faria, sem cortar
		# o servidor no mesmo quadro em que ele avisa os demais.
		leave_trigger = ""
		get_tree().create_timer(1.5).timeout.connect(_return_to_menu.bind("Você saiu da partida.", "left"))
	if state == RoundState.WAITING or state == RoundState.COUNTDOWN:
		local_role = Role.NONE
		local_round_id = 0
		local_final_reveal.clear()
		local_spectator_targets.clear()
		local_spectator_index = -1
		local_eliminated = false
		# Nova rodada: nada do combate anterior (vida, arma, munição) sobrevive
		# até o servidor mandar o estado privado desta rodada.
		local_combat_state.clear()
		if arena_view != null:
			arena_view.set_spectator_target(0, false)
			arena_view.apply_combat_state(local_combat_state)
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
	if online_rooms and typeof(payload.get("targets")) == TYPE_ARRAY:
		for target in payload["targets"]: _note_peer(target, "spectator")
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
	if combat_network_test != null: combat_network_test.call("observe_client_event", "spectator", safe)
	if arena_view != null:
		arena_view.set_spectator_target(int(safe[0]) if not safe.is_empty() else 0)
	print("SPECTATOR_TARGETS_PRIVATE_OK id=%s targets=%d" % [client_label, safe.size()])
	_update_round_hud()

@rpc("authority", "call_remote", "reliable")
func round_final_reveal(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if online_rooms:
		for raw_entry in payload.get("players", []):
			if typeof(raw_entry) == TYPE_DICTIONARY: _note_peer((raw_entry as Dictionary).get("peer_id", 0), "reveal")
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
	if spectator_reveal_test_mode and not shutdown_prepare_received: spectator_reveal_received.rpc_id(1)
	_update_round_hud()

@rpc("any_peer", "call_remote", "reliable")
func spectator_test_followed() -> void:
	if not multiplayer.is_server() or not spectator_reveal_test_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not _enter_sender_room(sender): return
	if sender != spectator_test_dead_peer or round_authority.get_spectator_state(sender).is_empty(): return
	spectator_test_observed = true
	_maybe_finish_spectator_probe()

@rpc("any_peer", "call_remote", "reliable")
func spectator_reveal_received() -> void:
	if not multiplayer.is_server() or not spectator_reveal_test_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not _enter_sender_room(sender) or round_authority.state != RoundState.ENDED: return
	if round_authority.is_participant(sender) and lobby.has(sender): spectator_reveal_acks[sender] = true
	if spectator_reveal_acks.size() == round_authority.participants.size():
		print("ROUND_REVEAL_NETWORK_ACK_OK clients=%d" % spectator_reveal_acks.size())

@rpc("authority", "call_remote", "reliable")
func round_roster(entries: Array) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if online_rooms:
		for raw_entry in entries:
			if typeof(raw_entry) == TYPE_DICTIONARY: _note_peer((raw_entry as Dictionary).get("peer_id", 0), "roster")
	local_roster_peers.clear()
	var clean_entries: Array = []
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		# O roster público nunca traz papel; se trouxesse, o cliente descartaria.
		if entry.has("role"):
			print("CLIENT_ROSTER_REJECTED id=%s reason=role_field" % client_label)
			return
		var clean := sanitize_roster_entry(entry)
		clean_entries.append(clean)
		local_roster_peers.append(int(clean["peer_id"]))
	_log_roster_appearances(clean_entries)
	if arena_view != null:
		arena_view.apply_roster_alive(clean_entries)
	if round_hud != null:
		round_hud.call("apply_roster", clean_entries)

## Filtro de snapshot (protocolo 9): tipos exatos, mesma sessão de servidor
## da conexão e tick estritamente crescente. Vazio se aceito.
static func snapshot_rejection(payload: Dictionary, known_session: int, last_tick: int) -> String:
	if typeof(payload.get("tick")) != TYPE_INT or typeof(payload.get("session")) != TYPE_INT \
			or typeof(payload.get("players")) != TYPE_ARRAY or typeof(payload.get("ack", {})) != TYPE_DICTIONARY:
		return "malformed"
	if known_session != 0 and int(payload["session"]) != known_session:
		return "foreign_session"
	if int(payload["tick"]) <= last_tick:
		return "stale_tick"
	return ""

## Allowlist do roster público (protocolo 7): só estas chaves chegam à arena e
## ao HUD, e a aparência só vale se for um dos oito ids conhecidos.
const ROSTER_KEYS := ["peer_id", "label", "connected", "participant", "alive", "appearance"]

static func sanitize_roster_entry(entry: Dictionary) -> Dictionary:
	var clean := {}
	for key in ROSTER_KEYS:
		if entry.has(key):
			clean[key] = entry[key]
	clean["peer_id"] = int(clean.get("peer_id", 0)) if typeof(clean.get("peer_id", 0)) == TYPE_INT else 0
	clean["appearance"] = CharacterAppearance.sanitize(clean.get("appearance", ""))
	return clean

var _last_appearance_log := ""
func _log_roster_appearances(entries: Array) -> void:
	var parts: Array = []
	for entry in entries:
		parts.append("%d:%s" % [int(entry["peer_id"]), str(entry["appearance"])])
	var line := ",".join(parts)
	if line != _last_appearance_log:
		_last_appearance_log = line
		print("CLIENT_ROSTER_APPEARANCES id=%s map=%s" % [client_label, line])

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
	if round_test_mode and not shutdown_prepare_received:
		_run_role_privacy_probes()
		round_role_acknowledged.rpc_id(1, round_id)

## Confirmação de recebimento. Carrega somente o identificador da rodada.
@rpc("any_peer", "call_remote", "reliable")
func round_role_acknowledged(acknowledged_round_id: int) -> void:
	if not multiplayer.is_server() or shutting_down or round_authority == null:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _enter_sender_room(sender):
		return
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
	if arena_view != null:
		arena_view.set_gameplay_visuals(_client_can_gameplay())
	if round_hud == null:
		return
	round_hud.call("apply_round_state", local_round_public, local_role, local_round_id, multiplayer.get_unique_id())
	round_hud.call("apply_combat_state", local_combat_state)
	round_hud.call("apply_spectator_state", local_eliminated, local_spectator_targets, _spectator_target())
	round_hud.call("apply_final_reveal", local_final_reveal)

## Prompt de coleta: o mesmo pickup que E pediria (posição oficial + estado
## público dos pickups). O HUD decide o texto com o inventário privado oficial.
func _update_pickup_prompt() -> void:
	if round_hud == null or arena_view == null:
		return
	var pickup_type := ""
	if _client_can_gameplay():
		var pickup_id: String = arena_view.nearest_available_pickup()
		if not pickup_id.is_empty():
			pickup_type = str((arena_view.pickup_states[pickup_id] as Dictionary).get("type", ""))
	round_hud.call("set_nearby_pickup", pickup_type)

func _client_can_gameplay() -> bool:
	return int(local_round_public.get("state", RoundState.WAITING)) == RoundState.ACTIVE \
		and not local_eliminated and int(local_combat_state.get("health", 0)) > 0 \
		and int(local_combat_state.get("round_id", 0)) == int(local_round_public.get("round_id", -1))

func _spectator_target() -> int:
	if local_spectator_index < 0 or local_spectator_index >= local_spectator_targets.size(): return 0
	return int(local_spectator_targets[local_spectator_index])

func _cycle_spectator(direction: int) -> void:
	if local_spectator_targets.is_empty(): return
	local_spectator_index = posmod(local_spectator_index + direction, local_spectator_targets.size())
	if arena_view != null: arena_view.set_spectator_target(_spectator_target())
	_update_round_hud()

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
		_update_pickup_prompt()

@rpc("authority", "call_remote", "reliable")
func combat_public_shot(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if combat_network_test != null: combat_network_test.call("observe_client_event", "shot", payload)
	if int(payload.get("shooter_peer_id", 0)) == multiplayer.get_unique_id():
		net_stats.action_resolved(NetSync.ACTION_FIRE, net_stats.oldest_action(NetSync.ACTION_FIRE))
	if arena_view != null:
		arena_view.show_shot(payload)

@rpc("authority", "call_remote", "reliable")
func combat_public_elimination(peer_id: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if online_rooms: _note_peer(peer_id, "elimination")
	if combat_network_test != null: combat_network_test.call("observe_client_event", "elimination", peer_id)
	if arena_view != null:
		arena_view.show_elimination(peer_id)
	if round_hud != null: round_hud.call("apply_elimination", peer_id)

@rpc("authority", "call_remote", "reliable")
func combat_hit_confirmed() -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1: return
	if combat_network_test != null: combat_network_test.call("observe_client_event", "hit", null)
	if arena_view != null: arena_view.show_hit_marker()

@rpc("authority", "call_remote", "reliable")
func combat_action_rejected(action: String, sequence: int, reason: String) -> void:
	if combat_network_test != null: combat_network_test.call("observe_client_event", "rejection", {"action": action, "sequence": sequence, "reason": reason})
	print("COMBAT_REJECTED id=%s action=%s sequence=%d reason=%s" % [client_label, action, sequence, reason])
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() == 1:
		net_stats.count_rejection("%s_%s" % [action, reason])
		net_stats.action_resolved(action, sequence)
		if round_hud != null: round_hud.call("show_rejection", action, reason)
		if arena_view != null:
			if action == NetSync.ACTION_FIRE: arena_view.discard_predicted_shot(sequence)
			arena_view.show_rejection(action, reason)

func _on_pickups_changed(snapshot: Array) -> void:
	if multiplayer.is_server() and not shutting_down:
		for peer_id in _open_members():
			pickup_public_state.rpc_id(int(peer_id), snapshot)

func _on_combat_private_state_changed(peer_id: int, state: Dictionary) -> void:
	if combat_network_test != null: combat_network_test.call("observe_private_emission", peer_id, state)
	if multiplayer.is_server() and lobby.has(peer_id) and not shutting_down:
		combat_private_state.rpc_id(peer_id, state)

func _on_shot_resolved(event: Dictionary) -> void:
	if combat_network_test != null: combat_network_test.call("observe_server_shot", event)
	if multiplayer.is_server() and not shutting_down:
		for peer_id in _open_members():
			combat_public_shot.rpc_id(int(peer_id), event)

func _on_combat_player_eliminated(peer_id: int, _instigator_peer_id: int) -> void:
	if combat_network_test != null: combat_network_test.call("observe_server_elimination", peer_id)
	if multiplayer.is_server() and not shutting_down:
		for member in _open_members():
			combat_public_elimination.rpc_id(int(member), peer_id)
		_register_body(peer_id)

## Corpo no ponto oficial da eliminação (fase 6). Só eliminação de combate
## aceita chega aqui; quem sai vivo não ganha corpo inventado.
func _register_body(peer_id: int) -> void:
	if not authoritative_world.states.has(peer_id) or not round_authority.is_participant(peer_id):
		return
	var state: Dictionary = authoritative_world.states[peer_id]
	var dto := body_registry.add(round_authority.round_id, peer_id, state["position"], float(state["yaw"]), str(lobby.appearance_for(peer_id)))
	if dto.is_empty():
		return
	print("ROUND_BODY_ADDED round_id=%d body_id=%d bodies=%d" % [int(dto["round_id"]), int(dto["body_id"]), body_registry.size()])
	if combat_network_test != null and combat_network_test.has_method("observe_server_body"):
		combat_network_test.call("observe_server_body", dto)
	# Só quem está na sala: um peer recusado (ou ainda sem entrada aceita)
	# nunca recebe corpo.
	var recipients := 0
	for raw_peer_id in lobby.peer_ids():
		round_body_added.rpc_id(int(raw_peer_id), dto)
		recipients += 1
	print("ROUND_BODY_SENT body_id=%d recipients=%d" % [int(dto["body_id"]), recipients])

@rpc("authority", "call_remote", "reliable")
func round_body_added(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if not joined:
		print("CLIENT_BODY_IGNORED id=%s reason=not_joined" % client_label)
		return
	var dto := BodyRules.sanitize(payload)
	# Callback de outra rodada (ou lixo) não cria corpo.
	if dto.is_empty() or int(dto["round_id"]) != int(local_round_public.get("round_id", 0)):
		print("CLIENT_BODY_IGNORED id=%s reason=%s" % [client_label, "invalid" if dto.is_empty() else "stale_round"])
		return
	_accept_body(dto)

## Estado completo dos corpos (entrada no meio da rodada) ou limpeza (nova rodada).
@rpc("authority", "call_remote", "reliable")
func round_bodies_state(payload: Dictionary) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id() != 1:
		return
	if not joined:
		print("CLIENT_BODY_IGNORED id=%s reason=not_joined" % client_label)
		return
	if payload.size() != 2 or typeof(payload.get("round_id")) != TYPE_INT or typeof(payload.get("bodies")) != TYPE_ARRAY:
		return
	var list: Array = payload["bodies"]
	if list.is_empty():
		_clear_local_bodies()
		return
	if int(payload["round_id"]) != int(local_round_public.get("round_id", 0)):
		print("CLIENT_BODY_IGNORED id=%s reason=stale_round" % client_label)
		return
	_clear_local_bodies()
	for raw in list:
		var dto := BodyRules.sanitize(raw)
		if not dto.is_empty() and int(dto["round_id"]) == int(payload["round_id"]):
			_accept_body(dto)

func _accept_body(dto: Dictionary) -> void:
	if online_rooms: _note_peer(dto.get("peer_id", 0), "body")
	for existing in local_bodies.values():
		if int(existing["body_id"]) == int(dto["body_id"]) or (int(existing["peer_id"]) == int(dto["peer_id"]) and int(existing["round_id"]) == int(dto["round_id"])):
			print("CLIENT_BODY_DUPLICATE_IGNORED id=%s" % client_label)
			return
	local_bodies[int(dto["body_id"])] = dto
	if arena_view != null:
		arena_view.add_body(dto)
	if combat_network_test != null: combat_network_test.call("observe_client_event", "body", dto)
	print("CLIENT_BODY_SHOWN id=%s round_id=%d bodies=%d" % [client_label, int(dto["round_id"]), local_bodies.size()])

func _clear_local_bodies() -> void:
	local_bodies.clear()
	if arena_view != null:
		arena_view.clear_bodies()

func _safe_combat_reason(raw_reason: Variant) -> String:
	var reason := str(raw_reason)
	var allowed := ["round_not_active", "unknown_peer", "player_dead", "invalid_sequence", "replay", "sequence_jump", "rate_limited", "invalid_pickup", "item_not_found", "item_unavailable", "out_of_range", "inventory_full", "incompatible_item", "no_equipped_weapon", "reserve_full", "empty_magazine", "reloading", "fire_rate", "invalid_origin", "non_finite", "implausible_origin", "invalid_direction", "direction_not_normalized", "direction_vertical", "direction_yaw_divergence", "direction_pitch_divergence", "invalid_pitch", "magazine_full", "reserve_empty", "already_reloading", "stale_epoch", "not_participant", "input_rejected", "queue_full"]
	return reason if reason in allowed else "rejected"

# --- Teste local no PC --------------------------------------------------------
#
# O menu só coleta dados. "Criar" inicia a autoridade num processo headless
# separado (mesmo executável) e, quando ele confirma que escuta a porta, este
# processo vira um cliente comum conectado em loopback. "Entrar" conecta direto.
# Nenhum caminho daqui instancia RoundAuthority, CombatAuthority ou o mundo.

# --- Cliente: salas online (fase 9) ------------------------------------------------

## O servidor respondeu ao handshake com o lobby online (servidor com salas).
var online_rooms := false
var local_room_state: Dictionary = {}
var room_seen_code := ""
var room_auto_ready_round := -1
var room_auto_ready_count := 0
## Teste de isolamento: peers e rótulos vistos em qualquer mensagem recebida.
var room_seen_peers: Dictionary = {}
var room_seen_labels: Dictionary = {}

func _on_room_welcome(payload: Dictionary) -> void:
	online_rooms = true
	print("HALL_WELCOME id=%s rooms=%s" % [client_label, str(payload.get("rooms", false) == true)])
	if interactive_session and desktop_menu != null:
		desktop_menu.enter(MenuFlow.State.ONLINE, "", menu_attempt)
		desktop_menu.show_hall()
		var automation := str(arguments.get("menu-room", ""))
		if not automation.is_empty():
			call_deferred("_run_room_automation", automation)
		return
	# Clientes de teste e sonda: criam sala ou entram pelo código.
	var action := str(arguments.get("room-action", ""))
	if NetworkConfig.bool_argument(arguments, "probe") and action.is_empty():
		action = "create"
	if action == "create":
		room_create.rpc_id(1, client_label)
	elif action == "join":
		room_join.rpc_id(1, str(arguments.get("room-code", "")), client_label)

## Automação do menu de sala (testes): usa os botões reais.
func _run_room_automation(automation: String) -> void:
	if desktop_menu == null:
		return
	if automation == "create":
		desktop_menu.press("room_create")
	elif automation == "join":
		desktop_menu.set_field("room_code", str(arguments.get("room-code", "")))
		desktop_menu.press("room_join")

func _on_room_state(payload: Dictionary) -> void:
	var dto := RoomRules.sanitize_room_state(payload)
	if dto.is_empty():
		print("ROOM_STATE_REJECTED id=%s" % client_label)
		return
	var previous_phase := str(local_room_state.get("phase", ""))
	local_room_state = dto
	var labels: Array = []
	for entry in dto["players"]:
		labels.append(str(entry["label"]))
		_note_peer(int(entry["peer_id"]), "room_state")
		room_seen_labels[str(entry["label"])] = true
	labels.sort()
	if room_seen_code.is_empty():
		room_seen_code = str(dto["code"])
		print("ROOM_JOINED id=%s code=%s" % [client_label, room_seen_code])
	elif room_seen_code != str(dto["code"]):
		print("ROOM_CODE_CHANGED id=%s from=%s to=%s" % [client_label, room_seen_code, str(dto["code"])])
	print("CLIENT_ROOM_STATE id=%s code=%s phase=%s round_id=%d players=%d ready=%d labels=%s result=%s" % [
		client_label, str(dto["code"]), str(dto["phase"]), int(dto["round_id"]), (dto["players"] as Array).size(),
		int(dto["ready_count"]), ",".join(PackedStringArray(labels)), str(not (dto["result"] as Dictionary).is_empty())])
	if NetworkConfig.bool_argument(arguments, "probe"):
		_check_probe_traffic()
	_maybe_auto_ready(dto)
	if not interactive_session or desktop_menu == null:
		return
	desktop_menu.show_room(dto, multiplayer.get_unique_id())
	_run_room_menu_automation(dto)
	var phase := str(dto["phase"])
	if phase == RoomRules.PHASE_PLAYING and previous_phase != RoomRules.PHASE_PLAYING:
		_set_game_view(true)
	elif phase in [RoomRules.PHASE_LOBBY, RoomRules.PHASE_COUNTDOWN] and previous_phase in [RoomRules.PHASE_PLAYING, RoomRules.PHASE_RESULTS]:
		# Fim da rodada: todos voltam ao lobby da sala com o resultado.
		_set_game_view(false)
	if round_hud != null:
		round_hud.call("set_session_info", "Sala %s\n%s: soltar mouse · %s: sair para o menu" % [
			RoomRules.display_code(str(dto["code"])), GameControls.action_text("release_mouse"), GameControls.action_text("leave_match")])

## Automação do menu na sala (testes): aperta os botões reais PRONTO (com a
## sala cheia o bastante) e SAIR DA SALA (depois de ver um resultado).
var menu_room_ready_round := -1
var menu_room_left := false
func _run_room_menu_automation(dto: Dictionary) -> void:
	if str(dto["phase"]) != RoomRules.PHASE_LOBBY:
		return
	if NetworkConfig.bool_argument(arguments, "menu-room-leave-after-result") and not (dto["result"] as Dictionary).is_empty():
		if not menu_room_left:
			menu_room_left = true
			desktop_menu.call_deferred("press", "room_leave")
		return
	var min_players := NetworkConfig.integer_argument(arguments, "menu-room-ready-min-players", 0)
	if min_players <= 0 or (dto["players"] as Array).size() < min_players:
		return
	if menu_room_ready_round == int(dto["round_id"]) or desktop_menu.own_ready():
		return
	menu_room_ready_round = int(dto["round_id"])
	desktop_menu.call_deferred("press", "room_ready")

## Testes: marca PRONTO sozinho a cada volta ao lobby, até N rodadas.
func _maybe_auto_ready(dto: Dictionary) -> void:
	var rounds := NetworkConfig.integer_argument(arguments, "auto-ready-rounds", 0)
	if rounds <= 0 or str(dto["phase"]) != RoomRules.PHASE_LOBBY:
		return
	var min_players := NetworkConfig.integer_argument(arguments, "auto-ready-min-players", 1)
	if (dto["players"] as Array).size() < min_players:
		return
	if room_auto_ready_round == int(dto["round_id"]) or room_auto_ready_count >= rounds:
		return
	for entry in dto["players"]:
		if int(entry["peer_id"]) == multiplayer.get_unique_id() and bool(entry["ready"]):
			return
	room_auto_ready_round = int(dto["round_id"])
	room_auto_ready_count += 1
	print("ROOM_AUTO_READY id=%s round_id=%d count=%d" % [client_label, int(dto["round_id"]), room_auto_ready_count])
	room_set_ready.rpc_id(1, true)

## Teste de isolamento (salas online): cada peer_id que aparece em qualquer
## mensagem recebida é registrado uma vez; o harness confere que todos são da
## mesma sala.
func _note_peer(raw_peer_id: Variant, via: String) -> void:
	if typeof(raw_peer_id) != TYPE_INT or int(raw_peer_id) <= 0:
		return
	var key := "%d:%s" % [int(raw_peer_id), via]
	if room_seen_peers.has(key):
		return
	room_seen_peers[key] = true
	print("CLIENT_SEEN_PEER id=%s peer=%d via=%s" % [client_label, int(raw_peer_id), via])

func _on_room_error(reason: String) -> void:
	var clean := reason if RoomRules.ERRORS.has(reason) else "unknown"
	print("ROOM_ERROR id=%s reason=%s" % [client_label, clean])
	if interactive_session and desktop_menu != null:
		desktop_menu.show_room_error(clean)
		return
	if NetworkConfig.bool_argument(arguments, "probe"):
		# Sala cheia, em rodada, nome em uso ou servidor lotado ainda provam um
		# servidor vivo com o mesmo protocolo.
		if clean in ["room_full", "round_in_progress", "name_taken", "server_full"]:
			_finish_probe("refused", clean)
			return
		print("PROBE_FAILED url=%s reason=room_error:%s" % [str(arguments.get("url", "")), clean])
		get_tree().quit(1)
		return
	if NetworkConfig.bool_argument(arguments, "exit-on-room-error"):
		get_tree().quit(0)

## Lobby da sala (menu) ou partida (mansão + HUD). O mouse só fica preso na
## partida; no lobby, a mansão fica oculta e não reage a cliques.
func _set_game_view(visible_game: bool) -> void:
	if arena_view != null:
		arena_view.visible = visible_game
	if round_hud != null:
		round_hud.visible = visible_game
	if desktop_menu != null:
		desktop_menu.visible = not visible_game
	if not visible_game:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("CLIENT_VIEW id=%s game=%s" % [client_label, str(visible_game)])

func _on_menu_room_create(player_name: String) -> void:
	if not online_rooms or joined:
		return
	client_label = player_name
	arguments["client-id"] = player_name
	room_create.rpc_id(1, player_name)

func _on_menu_room_join(code: String, player_name: String) -> void:
	if not online_rooms or joined:
		return
	client_label = player_name
	arguments["client-id"] = player_name
	room_join.rpc_id(1, code, player_name)

func _on_menu_room_ready(value: bool) -> void:
	if online_rooms and joined:
		room_set_ready.rpc_id(1, value)

func _on_menu_online_leave() -> void:
	_return_to_menu("Você saiu da sala." if joined else "", "left" if joined else "cancelled")

func start_menu() -> void:
	# Testes (e várias janelas no mesmo PC) podem isolar as preferências.
	MenuSettings.path_override = str(arguments.get("menu-settings-path", ""))
	desktop_menu = DesktopMenu.new()
	desktop_menu.arguments = arguments
	add_child(desktop_menu)
	desktop_menu.host_requested.connect(_on_menu_host)
	desktop_menu.join_requested.connect(_on_menu_join)
	desktop_menu.online_requested.connect(_on_menu_online)
	desktop_menu.cancel_requested.connect(_on_menu_cancel)
	desktop_menu.quit_requested.connect(_on_menu_quit)
	desktop_menu.settings_changed.connect(_apply_menu_settings)
	desktop_menu.room_create_requested.connect(_on_menu_room_create)
	desktop_menu.room_join_requested.connect(_on_menu_room_join)
	desktop_menu.room_ready_requested.connect(_on_menu_room_ready)
	desktop_menu.online_leave_requested.connect(_on_menu_online_leave)
	desktop_menu.input_rejected.connect(func(_field): _exit_if_menu_test())
	_apply_menu_settings(desktop_menu.settings)
	if not DesktopSession.pending_message.is_empty() or not DesktopSession.pending_kind.is_empty():
		print("MENU_SHOWING_MESSAGE after_return=true hosting=%s kind=%s" % [str(DesktopSession.is_hosting()), DesktopSession.pending_kind])
		desktop_menu.restore_after_return(DesktopSession.last_request, DesktopSession.pending_kind, DesktopSession.pending_message)
		DesktopSession.pending_message = ""
		DesktopSession.pending_kind = ""
		if NetworkConfig.bool_argument(arguments, "menu-quit-after-reload"):
			desktop_menu.call_deferred("emit_signal", "quit_requested")
			return
		var after := str(arguments.get("menu-after-return", ""))
		if not after.is_empty() and not DesktopSession.after_return_consumed:
			DesktopSession.after_return_consumed = true
			var delay := float(NetworkConfig.integer_argument(arguments, "menu-after-return-delay-msec", 0)) / 1000.0
			get_tree().create_timer(delay).timeout.connect(_run_menu_automation.bind(after))
		return
	# Automação para testes e atalhos: preenche os campos e aciona os botões
	# reais do menu (os mesmos de um clique). Só uma vez por processo.
	var auto := str(arguments.get("menu-auto", ""))
	if auto.is_empty() or DesktopSession.auto_action_consumed:
		return
	DesktopSession.auto_action_consumed = true
	desktop_menu.fill(str(arguments.get("menu-name", "")), str(arguments.get("menu-port", "")),
		NetworkConfig.bool_argument(arguments, "menu-lan"), str(arguments.get("menu-address", "")),
		str(arguments.get("menu-port", "")))
	call_deferred("_run_menu_automation", auto)

## Sequências de automação: navegam pelos botões visíveis do menu.
func _run_menu_automation(auto: String) -> void:
	if desktop_menu == null:
		return
	print("MENU_AUTOMATION action=%s" % auto)
	match auto:
		"host":
			_menu_open("host")
			desktop_menu.press("host_create")
		"join", "retry-join":
			_menu_open("join")
			desktop_menu.press("join_enter")
		# Clique duplo: dois acionamentos no mesmo quadro.
		"join-twice":
			_menu_open("join")
			desktop_menu.press("join_enter")
			desktop_menu.press("join_enter")
		"host-twice":
			_menu_open("host")
			desktop_menu.press("host_create")
			desktop_menu.press("host_create")
		"online":
			# JOGAR ONLINE com endereço configurado já conecta (fase 9); sem
			# endereço, abre o aviso.
			var configured := bool(desktop_menu.online["ok"])
			_menu_open("online")
			if not configured:
				print("MENU_ONLINE_UNAVAILABLE reason=%s" % desktop_menu.online["reason"])
				if NetworkConfig.bool_argument(arguments, "menu-exit-on-return"):
					get_tree().quit(0)
		"cancel-join":
			_menu_open("join")
			desktop_menu.press("join_enter")
			var delay := float(NetworkConfig.integer_argument(arguments, "menu-cancel-after-msec", 300)) / 1000.0
			get_tree().create_timer(delay).timeout.connect(func():
				if desktop_menu != null: desktop_menu.press("cancel"))
		"cancel-host":
			desktop_menu.press("host")
			desktop_menu.press("host_create")
			desktop_menu.call_deferred("press", "cancel")
		"retry":
			desktop_menu.press("retry")
		"quit":
			desktop_menu.press("quit")

## Como o jogador: fecha o aviso da volta ao menu (VOLTAR) e abre o painel,
## se ainda não estiver nele.
func _menu_open(panel_id: String) -> void:
	if desktop_menu.status_box.visible:
		desktop_menu.press("status_back")
	if desktop_menu.panel_name != panel_id:
		desktop_menu.press(panel_id)

func _apply_menu_settings(settings: MenuSettings) -> void:
	mouse_sensitivity = MOUSE_SENSITIVITY * MenuSettings.clamp_sensitivity(settings.sensitivity)
	print("MENU_SETTINGS_APPLIED volume=%.2f sensitivity=%.2f" % [settings.volume, settings.sensitivity])

func _on_menu_host(player_name: String, port: int, lan: bool, attempt: int = 0) -> void:
	if hosting_pending or interactive_session:
		print("MENU_DUPLICATE_IGNORED action=host")
		return
	menu_attempt = attempt
	var error := DesktopSession.start_hosted_server(port, lan)
	if not error.is_empty():
		print("MENU_HOST_ERROR reason=%s port=%d" % [error, port])
		desktop_menu.fail(DesktopSession.error_message(error, port), attempt)
		_exit_if_menu_test()
		return
	hosting_pending = true
	hosting_deadline_msec = Time.get_ticks_msec() + DesktopSession.SERVER_READY_TIMEOUT_MSEC
	pending_player_name = player_name
	desktop_menu.enter(MenuFlow.State.STARTING_SERVER, "Abrindo a mansão na porta %d…" % port, attempt)

func _poll_hosting() -> void:
	if not hosting_pending:
		return
	var status := DesktopSession.poll_hosted_server()
	if status.is_empty() and Time.get_ticks_msec() > hosting_deadline_msec:
		status = "server_timeout"
	if status.is_empty():
		return
	hosting_pending = false
	var port := DesktopSession.hosted_port
	if status != DesktopSession.STATUS_READY:
		DesktopSession.stop_hosted_server(status)
		print("MENU_HOST_ERROR reason=%s port=%d" % [status, port])
		desktop_menu.fail(DesktopSession.error_message(status, port), menu_attempt)
		_exit_if_menu_test()
		return
	print("MENU_HOST_READY port=%d lan=%s" % [port, str(DesktopSession.hosted_lan)])
	desktop_menu.enter(MenuFlow.State.CONNECTING, "", menu_attempt)
	_start_interactive_client(pending_player_name, DesktopSession.url_for(DesktopSession.LOOPBACK_ADDRESS, port))

func _on_menu_join(player_name: String, address: String, port: int, attempt: int = 0) -> void:
	# Clique duplo em "Entrar": o menu já bloqueia o segundo; esta guarda
	# continua valendo para qualquer outro caminho.
	if hosting_pending or interactive_session:
		print("MENU_DUPLICATE_IGNORED action=join")
		return
	menu_attempt = attempt
	desktop_menu.enter(MenuFlow.State.CONNECTING, "Conectando a %s:%d…" % [address, port], attempt)
	_start_interactive_client(player_name, DesktopSession.url_for(address, port))

func _on_menu_online(player_name: String, url: String, attempt: int = 0) -> void:
	if hosting_pending or interactive_session:
		print("MENU_DUPLICATE_IGNORED action=online")
		return
	menu_attempt = attempt
	desktop_menu.enter(MenuFlow.State.CONNECTING, "Conectando ao servidor online…", attempt)
	_start_interactive_client(player_name, url)

## Cancelar: antes do servidor local ficar pronto, só o encerra; conectando,
## fecha a conexão e volta ao mesmo painel, sem mensagem de erro.
func _on_menu_cancel(attempt: int) -> void:
	if attempt != menu_attempt:
		print("MENU_STALE_EVENT_IGNORED state=cancel attempt=%d current=%d" % [attempt, menu_attempt])
		return
	if hosting_pending:
		hosting_pending = false
		desktop_menu.enter(MenuFlow.State.CANCELLING, "", attempt)
		DesktopSession.stop_hosted_server("cancelled")
		desktop_menu.enter(MenuFlow.State.IDLE, "", attempt)
		print("MENU_CANCELLED stage=starting_server")
		if NetworkConfig.bool_argument(arguments, "menu-exit-on-return"):
			print("MENU_RETURNED reason=cancelled")
			get_tree().quit(0)
		return
	if interactive_session and not joined:
		desktop_menu.enter(MenuFlow.State.CANCELLING, "", attempt)
		print("MENU_CANCELLED stage=connecting")
		_return_to_menu("", "cancelled")

func _on_menu_quit() -> void:
	print("MENU_QUIT")
	DesktopSession.stop_hosted_server("quit")
	get_tree().quit(0)

func _start_interactive_client(player_name: String, url: String) -> void:
	interactive_session = true
	leave_trigger = str(arguments.get("menu-leave-on", ""))
	arguments["client-id"] = player_name
	arguments["url"] = url
	mode = "client"
	print("MENU_CONNECTING id=%s url=%s" % [player_name, url])
	start_client()

func _show_session_label(url: String) -> void:
	if DisplayServer.get_name() == "headless" or round_hud == null:
		return
	# Endereço da sala e atalhos ficam no painel de estado do HUD (canto
	# superior direito), longe do centro e dos painéis de vida e arma.
	var where := DesktopSession.hosted_address_text() if DesktopSession.is_hosting() else "Conectado a %s" % url.trim_prefix("ws://")
	round_hud.call("set_session_info", "%s\n%s: soltar mouse · %s: sair para o menu" % [where, GameControls.action_text("release_mouse"), GameControls.action_text("leave_match")])

## Volta ao menu com uma mensagem. Fecha a conexão, encerra o servidor que este
## processo hospeda (se houver) e recarrega a cena limpa.
func _return_to_menu(message: String, reason: String) -> void:
	if returning_to_menu:
		return
	returning_to_menu = true
	print("MENU_RETURNED reason=%s" % reason)
	DesktopSession.pending_message = message
	DesktopSession.pending_kind = _return_kind(reason)
	# Fora do callback de rede que disparou a volta (desconexão, falha, recusa).
	call_deferred("_finish_return_to_menu", reason)

## Como o menu mostra a volta: cancelamento (sem aviso), aviso neutro (saída
## voluntária, fim combinado com o servidor) ou falha recuperável.
func _return_kind(reason: String) -> String:
	if reason == "cancelled":
		return "cancelled"
	if reason == "left" or (reason == "server_disconnected" and shutdown_prepare_received):
		return "info"
	return "failure"

func _finish_return_to_menu(reason: String) -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	DesktopSession.stop_hosted_server(reason)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if NetworkConfig.bool_argument(arguments, "menu-exit-on-return"):
		get_tree().quit(0)
		return
	# Testes: encerra o processo na N-ésima volta ao menu.
	DesktopSession.returns += 1
	var exit_after := NetworkConfig.integer_argument(arguments, "menu-exit-after-returns", 0)
	if exit_after > 0 and DesktopSession.returns >= exit_after:
		print("MENU_EXIT_AFTER_RETURNS returns=%d" % DesktopSession.returns)
		get_tree().quit(0)
		return
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()

## Nos testes automatizados, um erro esperado no menu encerra o processo.
func _exit_if_menu_test() -> void:
	if NetworkConfig.bool_argument(arguments, "menu-exit-on-return"):
		print("MENU_RETURNED reason=menu_error")
		get_tree().quit(0)

func _write_status_file(status: String) -> void:
	if status_file_path.is_empty():
		return
	var file := FileAccess.open(status_file_path, FileAccess.WRITE)
	if file != null:
		file.store_string(status)
		file.close()

## Servidor hospedado sem ninguém por tempo demais encerra sozinho: cobre o caso
## de o jogo do anfitrião fechar sem conseguir derrubar o processo.
func _check_hosted_idle(now_msec: int) -> void:
	if not lobby.is_empty():
		hosted_empty_since_msec = 0
		return
	if hosted_empty_since_msec == 0:
		hosted_empty_since_msec = now_msec
		return
	if now_msec - hosted_empty_since_msec >= HOSTED_IDLE_EXIT_MSEC:
		print("SERVER_HOSTED_IDLE_EXIT")
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.close()
		get_tree().quit(0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		DesktopSession.stop_hosted_server("window_closed")
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Sem foco: sem movimento e sem giro residual ao voltar.
		window_focused = false
		prediction.clear_look()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		window_focused = true
		prediction.clear_look()

func _exit_tree() -> void:
	# Sair do jogo por qualquer caminho derruba o servidor hospedado; recarregar a
	# cena para voltar ao menu já o encerrou antes.
	if not returning_to_menu:
		DesktopSession.stop_hosted_server("exit")

func fail(message: String) -> void:
	# A sonda já concluída fecha a própria conexão: a desconexão que se segue
	# não é falha.
	if probe_finished:
		return
	push_error(message)
	print(message)
	if mode == "client" and NetworkConfig.bool_argument(arguments, "probe"):
		print("PROBE_FAILED url=%s reason=%s" % [str(arguments.get("url", "")), message.get_slice(" ", 0).to_lower()])
	get_tree().quit(1)
