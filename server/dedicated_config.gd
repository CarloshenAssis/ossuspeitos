class_name DedicatedConfig
extends RefCounted

## Configuração do servidor dedicado de produção (fase 8, `--mode=dedicated`).
## Puro: recebe argumentos e ambiente, devolve a configuração ou os erros. Quem
## aplica é a `NetworkApp`.
##
## Porta, da mais forte para a mais fraca:
##   1. argumento `--port=N` (execução manual; o start de produção não passa);
##   2. variável de ambiente `PORT` (Railway injeta);
##   3. `NetworkConfig.DEFAULT_PORT` (9080), só quando nenhuma das duas existe.
## Valor fornecido e inválido (vazio, não inteiro, fora de 1–65535) é erro
## fatal: nunca há troca silenciosa de porta.
##
## Endereço de escuta: `--bind` > `ARMED_MYSTERY_BIND` > `0.0.0.0`. Só o modo
## dedicado escuta em todas as interfaces; o servidor do menu local continua
## em 127.0.0.1 (ou LAN, se o jogador escolher).
##
## Argumentos aceitos formam uma lista fechada. Qualquer outro (flags de
## teste, coordenadores, seed, tempos de rodada, `--hosted`) é recusado com
## erro fatal: produção nunca liga um modo de teste por engano.

const DEFAULT_BIND := "0.0.0.0"
const ALLOWED_ARGUMENTS := ["mode", "port", "bind", "shutdown-file"]
const EXIT_CONFIG_ERROR := 2
const EXIT_RUNTIME_ERROR := 1
## Conexão WebSocket que não entra na sala (request_join aceito) dentro deste
## prazo é derrubada: não ocupa recurso indefinidamente.
const JOIN_DEADLINE_MSEC := 15000
## Intervalo padrão da linha de status (0 desliga).
const STATUS_INTERVAL_SECONDS := 60

static func resolve(arguments: Dictionary, environment: Dictionary) -> Dictionary:
	var errors: Array = []
	var refused: Array = []
	for key in arguments.keys():
		if str(key) not in ALLOWED_ARGUMENTS:
			refused.append(str(key))
	refused.sort()
	if not refused.is_empty():
		errors.append("argumentos não permitidos no modo dedicado: %s" % ", ".join(PackedStringArray(refused)))
	var port := NetworkConfig.DEFAULT_PORT
	var port_source := "default"
	if arguments.has("port"):
		port_source = "argument"
		var parsed := parse_port(str(arguments["port"]))
		if parsed < 0:
			errors.append("--port inválida: \"%s\" (use um inteiro de 1 a 65535)" % str(arguments["port"]))
		else:
			port = parsed
	elif environment.has("PORT"):
		port_source = "env"
		var parsed := parse_port(str(environment["PORT"]))
		if parsed < 0:
			errors.append("PORT inválida: \"%s\" (use um inteiro de 1 a 65535)" % str(environment["PORT"]))
		else:
			port = parsed
	var bind := DEFAULT_BIND
	var bind_source := "default"
	if arguments.has("bind"):
		bind = str(arguments["bind"]).strip_edges()
		bind_source = "argument"
	elif environment.has("ARMED_MYSTERY_BIND"):
		bind = str(environment["ARMED_MYSTERY_BIND"]).strip_edges()
		bind_source = "env"
	if not is_bind_address(bind):
		errors.append("endereço de escuta inválido: \"%s\" (use um IP, como 0.0.0.0 ou ::)" % bind)
	var status_interval := STATUS_INTERVAL_SECONDS
	if environment.has("ARMED_MYSTERY_STATUS_SECONDS"):
		var text := str(environment["ARMED_MYSTERY_STATUS_SECONDS"]).strip_edges()
		if not text.is_valid_int() or text.to_int() < 0 or text.to_int() > 86400:
			errors.append("ARMED_MYSTERY_STATUS_SECONDS inválida: \"%s\" (0 a 86400)" % text)
		else:
			status_interval = text.to_int()
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"refused": refused,
		"port": port,
		"port_source": port_source,
		"bind": bind,
		"bind_source": bind_source,
		"shutdown_file": str(arguments.get("shutdown-file", "")).strip_edges(),
		"status_interval_seconds": status_interval,
		"commit": commit_from(environment),
	}

## Porta em texto -> inteiro 1–65535, ou -1 se inválida (inclui vazio, sinal,
## espaço, decimal e zero à esquerda com lixo).
static func parse_port(text: String) -> int:
	var value := text.strip_edges()
	if value.is_empty() or value != text or not value.is_valid_int() or value.begins_with("+") or value.begins_with("-"):
		return -1
	if value.length() > 5:
		return -1
	var number := value.to_int()
	return number if number >= 1 and number <= 65535 else -1

static func is_bind_address(value: String) -> bool:
	return value == "*" or value.is_valid_ip_address()

## Commit do build: `ARMED_MYSTERY_COMMIT` (gravado na imagem) ou o SHA que o
## Railway expõe em execução; "unknown" se nenhum.
static func commit_from(environment: Dictionary) -> String:
	for key in ["ARMED_MYSTERY_COMMIT", "RAILWAY_GIT_COMMIT_SHA"]:
		var value := str(environment.get(key, "")).strip_edges()
		if not value.is_empty() and value != "unknown" and value.length() <= 64 and value.is_valid_hex_number():
			return value.left(12)
	return "unknown"

## Ambiente relevante do processo (só as chaves que o modo dedicado lê).
static func process_environment() -> Dictionary:
	var values := {}
	for key in ["PORT", "ARMED_MYSTERY_BIND", "ARMED_MYSTERY_STATUS_SECONDS", "ARMED_MYSTERY_COMMIT", "RAILWAY_GIT_COMMIT_SHA"]:
		if OS.has_environment(key):
			values[key] = OS.get_environment(key)
	return values
