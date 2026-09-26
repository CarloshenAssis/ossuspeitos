class_name NetworkConfig
extends RefCounted

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_BIND_ADDRESS := "127.0.0.1"
const DEFAULT_PORT := 9080
## Os limites de sala vivem em `RoundRules`; aqui ficam apenas os apelidos
## usados pela camada de rede, para que não existam dois valores divergentes.
const MIN_PLAYERS := RoundRules.MIN_PLAYERS
const MAX_PLAYERS := RoundRules.MAX_PLAYERS
## 5: adds private spectator targets and the sanitized final role reveal.
## 6: shutdown_prepare/shutdown_ready carry the shutdown generation and a
## per-peer token, so only a confirmation of a received preparation counts.
## 7: round_roster entries carry the public cosmetic `appearance` id
## (allowlisted by CharacterAppearance); clients drop unknown roster keys.
## 8: submit_input carries pitch_delta and world snapshots carry the official
## pitch (vertical aim), which the server also uses for every shot.
## 9: tick commands (`submit_commands`: epoch, first sequence, one-tick
## commands with look deltas and an optional fire/reload/pickup action executed
## at that exact point). The separate request_fire/reload/pickup RPCs and
## `submit_input` are gone; fire carries no client origin or direction.
## `world_snapshot` is per recipient: {tick, session, players (+ public epoch),
## ack (own last resolved sequence, epoch, aim buckets)}.
## 10: corpos de jogadores eliminados (fase 6): `round_body_added` e
## `round_bodies_state` com DTO público (`BodyRules.PUBLIC_KEYS`). Comandos,
## snapshot e ACK iguais aos da versão 9, mas a superfície de RPC mudou: uma
## build 9 e uma 10 não podem jogar juntas.
## 11: salas privadas online (fase 9). RPCs novas `room_create`, `room_join`,
## `room_set_ready` (cliente -> servidor) e `room_welcome`, `room_state`,
## `room_error` (servidor -> cliente); no servidor online, `request_join` só
## faz o handshake (protocolo + nome) e a entrada numa sala vem depois. Os
## estados de rodada, roster, snapshots e combate passam a sair por sala.
## Os nomes novos ordenam depois de `request_join`: os índices de RPC do
## handshake (`join_rejected`, `request_join`) são os mesmos do protocolo 10,
## então 10 e 11 se recusam com `protocol_version` legível.
const PROTOCOL_VERSION := 11
const CONNECT_TIMEOUT_SECONDS := 10.0

## Versão anunciada/aceita por este processo. Só um binário de
## desenvolvimento (não exportado) pode simular outra com
## `--test-protocol-version`, para os testes de incompatibilidade; a build
## exportada sempre usa `PROTOCOL_VERSION`.
static func effective_protocol_version(arguments: Dictionary) -> int:
	if arguments.has("test-protocol-version") and OS.is_debug_build() and not OS.has_feature("template"):
		return integer_argument(arguments, "test-protocol-version", PROTOCOL_VERSION)
	return PROTOCOL_VERSION

static func user_arguments() -> Dictionary:
	var values := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--"):
			continue
		var parts := argument.trim_prefix("--").split("=", true, 1)
		values[parts[0]] = parts[1] if parts.size() == 2 else "true"
	if OS.has_feature("web"):
		values.merge(web_query_arguments(_web_query_string(), _web_hostname()))
	return values

## Chaves que a página Web aceita na URL (`?menu-auto=online&...`): só
## automação do menu (teste no navegador) e o código de convite. Nunca o
## endereço do servidor nem modos de teste: um link não pode apontar o jogo
## para outro servidor.
const WEB_QUERY_KEYS := ["menu-auto", "menu-room", "room-code", "menu-name",
	"menu-room-ready-min-players", "menu-room-leave-after-result"]

const LOOPBACK_HOSTS := ["localhost", "127.0.0.1"]

static func _web_query_string() -> String:
	var value: Variant = JavaScriptBridge.eval("window.location.search", true)
	return str(value) if value != null else ""

static func _web_hostname() -> String:
	var value: Variant = JavaScriptBridge.eval("window.location.hostname", true)
	return str(value) if value != null else ""

## Query string -> argumentos permitidos (valores curtos). Puro, para teste
## fora do navegador. `online-url` só vale numa página servida pelo próprio
## computador e apontando para ele (teste local no navegador); no GitHub
## Pages é ignorado.
static func web_query_arguments(query: String, page_host: String = "") -> Dictionary:
	var values := {}
	for pair in query.trim_prefix("?").split("&", false):
		var parts := pair.split("=", true, 1)
		var key := parts[0].uri_decode()
		var value := parts[1].uri_decode() if parts.size() == 2 else "true"
		if value.length() > 40:
			continue
		if key == "online-url":
			if page_host in LOOPBACK_HOSTS and (value.begins_with("ws://127.0.0.1:") or value.begins_with("ws://localhost:")):
				values[key] = value
			continue
		if key in WEB_QUERY_KEYS:
			values[key] = value
	return values

static func integer_argument(arguments: Dictionary, key: String, fallback: int) -> int:
	var value := str(arguments.get(key, fallback))
	return value.to_int() if value.is_valid_int() else fallback

static func float_argument(arguments: Dictionary, key: String, fallback: float) -> float:
	var value := str(arguments.get(key, fallback))
	return value.to_float() if value.is_valid_float() else fallback

static func bool_argument(arguments: Dictionary, key: String) -> bool:
	return str(arguments.get(key, "false")) == "true"

static func should_poll_human_input(
	is_joined: bool,
	expected_test_clients: int,
	is_round_test: bool,
	is_combat_test: bool,
	has_graphical_arena: bool
) -> bool:
	return is_joined and expected_test_clients == 0 and not is_round_test \
		and not is_combat_test and has_graphical_arena
