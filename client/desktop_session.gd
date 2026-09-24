class_name DesktopSession
extends RefCounted

## Sessão de teste local no PC. Valida o que o jogador digita no menu e controla
## o processo do servidor hospedado: a autoridade roda sempre num processo
## headless separado, iniciado com o mesmo executável; o menu nunca instancia
## autoridade de papéis, movimento, combate, vitória ou espectador.
##
## O estado é estático para sobreviver ao `reload_current_scene()` usado quando
## o jogador volta ao menu.

const DEFAULT_PORT := NetworkConfig.DEFAULT_PORT
const MIN_PORT := 1024
const MAX_PORT := 65535
const LOOPBACK_ADDRESS := "127.0.0.1"
const LAN_BIND_ADDRESS := "0.0.0.0"
const SERVER_READY_TIMEOUT_MSEC := 10000
const STATUS_READY := "ready"

static var hosted_pid := 0
static var hosted_port := 0
static var hosted_lan := false
static var hosted_status_path := ""
static var hosted_log_path := ""
static var pending_message := ""
## Tipo do resultado mostrado ao voltar ao menu: "failure" (falha
## recuperável), "info" (fim normal, saída) ou "cancelled".
static var pending_kind := ""
## Último pedido do menu (em memória, só nesta execução): refaz a tentativa.
static var last_request: Dictionary = {}
static var auto_action_consumed := false
static var after_return_consumed := false
static var returns := 0

# --- Validação ----------------------------------------------------------------

static func default_player_name() -> String:
	return "jogador-%04d" % (OS.get_process_id() % 10000)

## "" quando válido, senão a mensagem mostrada ao jogador.
## Mesma regra do servidor (`RoundRules.label_problem`), com a mensagem do menu.
static func validate_name(raw_name: String) -> String:
	var problem := RoundRules.label_problem(raw_name)
	return "" if problem.is_empty() else DesktopMenu.name_message(problem)

static func parse_port(raw_port: String) -> int:
	var clean := raw_port.strip_edges()
	if not clean.is_valid_int():
		return -1
	var port := clean.to_int()
	return port if port >= MIN_PORT and port <= MAX_PORT else -1

## Aceita IPv4 ou nome de host simples ("localhost", "meu-pc.lan"). Endereços
## IPv6 e URLs completas ficam de fora nesta fase de teste local.
static func validate_address(raw_address: String) -> String:
	var clean := raw_address.strip_edges()
	if clean.is_empty() or clean.length() > 253:
		return "Endereço inválido."
	if _is_ipv4(clean):
		return ""
	if clean.contains(":") or clean.contains("/"):
		return "Endereço inválido: informe só o IP (ex.: 192.168.0.10) e a porta no campo ao lado."
	var hostname := RegEx.create_from_string("^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$")
	if hostname.search(clean) == null or clean.replace(".", "").is_valid_int():
		return "Endereço inválido."
	return ""

static func _is_ipv4(value: String) -> bool:
	var parts := value.split(".")
	if parts.size() != 4:
		return false
	for part in parts:
		if part.is_empty() or part.length() > 3 or not part.is_valid_int():
			return false
		var number := part.to_int()
		if number < 0 or number > 255:
			return false
	return true

static func url_for(address: String, port: int) -> String:
	return "ws://%s:%d" % [address.strip_edges(), port]

## IPv4 da máquina utilizáveis na rede local, para mostrar aos amigos.
static func lan_addresses() -> Array:
	var result: Array = []
	for address in IP.get_local_addresses():
		var text := str(address)
		if not _is_ipv4(text) or text.begins_with("127.") or text.begins_with("169.254."):
			continue
		result.append(text)
	result.sort()
	return result

# --- Servidor hospedado -------------------------------------------------------

static func is_hosting() -> bool:
	return hosted_pid > 0 and OS.is_process_running(hosted_pid)

## Confere se a porta pode ser aberta agora. Não substitui o erro do próprio
## servidor (que também é lido), mas dá uma mensagem clara antes de iniciá-lo.
static func port_available(port: int, lan: bool) -> bool:
	var probe := TCPServer.new()
	var error := probe.listen(port, LAN_BIND_ADDRESS if lan else LOOPBACK_ADDRESS)
	probe.stop()
	return error == OK

## Inicia o servidor headless. Devolve "" ou o código do erro.
static func start_hosted_server(port: int, lan: bool) -> String:
	if is_hosting():
		return "already_hosting"
	if not port_available(port, lan):
		return "port_in_use"
	var stamp := "%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
	hosted_status_path = OS.get_user_data_dir().path_join("hosted-server-%s.status" % stamp)
	hosted_log_path = OS.get_user_data_dir().path_join("hosted-server.log")
	if FileAccess.file_exists(hosted_status_path):
		DirAccess.remove_absolute(hosted_status_path)
	var arguments := PackedStringArray(["--headless", "--log-file", hosted_log_path])
	# Rodando pelo editor ou por `godot --path`, o executável é o próprio Godot e
	# precisa do caminho do projeto; no jogo exportado, os dados já estão no pacote.
	if not OS.has_feature("template"):
		arguments.append_array(["--path", ProjectSettings.globalize_path("res://")])
	arguments.append_array(["--", "--mode=server",
		"--bind=%s" % (LAN_BIND_ADDRESS if lan else LOOPBACK_ADDRESS),
		"--port=%d" % port,
		"--status-file=%s" % hosted_status_path,
		"--hosted=true"])
	var pid := OS.create_process(OS.get_executable_path(), arguments)
	if pid <= 0:
		return "spawn_failed"
	hosted_pid = pid
	hosted_port = port
	hosted_lan = lan
	print("MENU_HOST_SPAWNED pid=%d port=%d bind=%s" % [pid, port, LAN_BIND_ADDRESS if lan else LOOPBACK_ADDRESS])
	return ""

## "ready", "" (ainda aguardando) ou o código do erro.
static func poll_hosted_server() -> String:
	var status := read_status(hosted_status_path)
	if status == STATUS_READY:
		return STATUS_READY
	if status.begins_with("error:"):
		return status.trim_prefix("error:")
	if not is_hosting():
		return "server_exited"
	return ""

static func read_status(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text().strip_edges()

## Encerra o servidor hospedado por este processo, se houver. Idempotente.
static func stop_hosted_server(reason: String) -> void:
	if hosted_pid > 0:
		var pid := hosted_pid
		if OS.is_process_running(pid):
			OS.kill(pid)
		print("MENU_HOSTED_SERVER_STOPPED pid=%d reason=%s" % [pid, reason])
	if not hosted_status_path.is_empty() and FileAccess.file_exists(hosted_status_path):
		DirAccess.remove_absolute(hosted_status_path)
	hosted_pid = 0
	hosted_port = 0
	hosted_lan = false
	hosted_status_path = ""

## Texto curto com os endereços para os outros jogadores.
static func hosted_address_text() -> String:
	if hosted_port <= 0:
		return ""
	if not hosted_lan:
		return "Sala neste PC: %s:%d (somente este computador)" % [LOOPBACK_ADDRESS, hosted_port]
	var lan := lan_addresses()
	if lan.is_empty():
		return "Sala na LAN, porta %d (nenhum IP de rede local encontrado; neste PC use %s)" % [hosted_port, LOOPBACK_ADDRESS]
	return "Sala na LAN: %s porta %d (neste PC: %s)" % [", ".join(lan), hosted_port, LOOPBACK_ADDRESS]

static func error_message(code: String, port: int) -> String:
	match code:
		"port_in_use":
			return "A porta %d já está em uso. Feche a outra partida ou escolha outra porta. Nenhuma sala foi criada." % port
		"already_hosting":
			return "Você já está hospedando uma partida."
		"spawn_failed":
			return "Não foi possível iniciar o servidor local."
		"server_exited":
			return "O servidor local fechou antes de ficar pronto. Nenhuma sala foi criada."
		"server_timeout":
			return "O servidor local não respondeu a tempo. Nenhuma sala foi criada."
		"unable_to_listen":
			return "O servidor não conseguiu abrir a porta %d. Nenhuma sala foi criada." % port
	return "Erro ao criar a partida (%s)." % code
