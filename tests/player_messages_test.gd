extends SceneTree

## Fase 10: toda mensagem de erro que o jogador vê (conexão, entrada, sala)
## é português simples, diz o que fazer e não expõe detalhe interno
## (endereço, IP, porta, protocolo, RPC, classe, stack trace).

const ACTIONS := ["Tente", "Confira", "Escolha", "Use", "Atualize", "Entre", "Peça", "Crie", "Espere", "Saia", "Conecte", "conecte"]
const FORBIDDEN := ["ws://", "wss://", "http", "RPC", "rpc", "protocol", "peer", "Peer", "Error", "error", "stack",
	"NetworkApp", "Node", "null", "railway", "Railway", "godot", "Godot", "%s", "%d"]

var failures := 0
var checks := 0

func _initialize() -> void:
	var messages: Dictionary = {}
	for reason in ["timeout", "connection_failed", "server_disconnected", "anything_else"]:
		for online in [true, false]:
			messages["connection:%s:%s" % [reason, str(online)]] = PlayerMessages.connection(reason, online)
	messages["connection:shutdown"] = PlayerMessages.connection("server_disconnected", true, true)
	for reason in ["protocol_version", "room_unavailable", "server_full", "name_taken", "invalid_client", "whatever"]:
		messages["join:%s" % reason] = PlayerMessages.join_rejected(reason)
	for reason in RoomRules.ERRORS.keys():
		messages["room:%s" % reason] = RoomRules.error_message(str(reason))
	messages["room:unknown"] = RoomRules.error_message("unknown")
	var ip := RegEx.create_from_string("\\d+\\.\\d+\\.\\d+\\.\\d+|:\\d{2,5}")
	for key in messages.keys():
		var text := str(messages[key])
		_expect(not text.is_empty(), "%s has text" % key)
		var has_action := false
		for verb in ACTIONS:
			if text.contains(verb):
				has_action = true
		_expect(has_action, "%s says what to do: %s" % [key, text])
		for word in FORBIDDEN:
			_expect(not text.contains(word), "%s hides internal detail '%s': %s" % [key, word, text])
		_expect(ip.search(text) == null, "%s has no address or port: %s" % [key, text])
	# As situações pedidas na fase 10 têm texto próprio (não o genérico).
	var generic := PlayerMessages.connection("anything_else", true)
	_expect(PlayerMessages.connection("connection_failed", true).begins_with("Servidor indisponível"), "server unavailable")
	_expect(PlayerMessages.join_rejected("protocol_version").begins_with("Versão incompatível do jogo"), "version incompatible")
	_expect(PlayerMessages.connection("server_disconnected", true).begins_with("A conexão caiu"), "connection dropped")
	_expect(PlayerMessages.connection("timeout", true) != generic, "timeout")
	for reason in ["room_not_found", "room_full", "round_in_progress", "invalid_code", "name_taken"]:
		_expect(RoomRules.error_message(reason) != RoomRules.error_message("unknown"), "room error %s has its own text" % reason)
	if failures > 0:
		push_error("PLAYER_MESSAGES_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("PLAYER_MESSAGES_TEST_OK checks=%d messages=%d" % [checks, messages.size()])
	quit(0)

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("PLAYER_MESSAGES_TEST_FAILED %s" % message)
