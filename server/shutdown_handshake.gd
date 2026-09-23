class_name ShutdownHandshake
extends RefCounted

## Estado headless do encerramento em duas fases. Cada tentativa de encerramento
## tem uma geração; cada peer esperado recebe, na sua `shutdown_prepare`, um
## token aleatório próprio daquela geração. Um `shutdown_ready` só conta quando
## o servidor já registrou o envio da preparação para aquele remetente e a
## confirmação traz exatamente a geração corrente e o token entregue a ele.
##
## Assim um peer não consegue confirmar antes de receber a preparação (não
## conhece o token), nem reaproveitar uma confirmação antiga, nem confirmar por
## outro peer: o remetente vem sempre de `get_remote_sender_id()`.

const REASON_NOT_SHUTTING_DOWN := "not_shutting_down"
const REASON_UNEXPECTED_PEER := "unexpected_peer"
const REASON_PREPARE_NOT_SENT := "prepare_not_sent"
const REASON_STALE_GENERATION := "stale_generation"
const REASON_TOKEN_MISMATCH := "token_mismatch"
const REASON_DUPLICATE := "duplicate"
const REASON_INVALID := "invalid"

var generation := 0
var active := false
## peer_id -> true, fixado no início da tentativa.
var expected: Dictionary = {}
## peer_id -> token enviado nesta geração.
var sent_tokens: Dictionary = {}
## peer_id -> true, confirmações aceitas nesta geração.
var ready: Dictionary = {}
var _rng := RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value

## Abre uma nova tentativa. Tudo da geração anterior deixa de valer.
func begin(peer_ids: Array) -> int:
	generation += 1
	active = true
	expected.clear()
	sent_tokens.clear()
	ready.clear()
	for peer_id in peer_ids:
		expected[int(peer_id)] = true
	return generation

## Gera e registra o token da preparação que está sendo enviada a `peer_id`.
## Devolve 0 se o peer não faz parte desta tentativa.
func prepare_token_for(peer_id: int) -> int:
	if not active or not expected.has(peer_id):
		return 0
	var token := 0
	while token == 0:
		token = _rng.randi() << 31 | _rng.randi()
	sent_tokens[peer_id] = token
	return token

## Valida uma confirmação. Devolve "" quando aceita; qualquer outro valor é o
## motivo da recusa e não altera a contagem.
func accept_ready(sender: int, received_generation: Variant, received_token: Variant) -> String:
	if not active:
		return REASON_NOT_SHUTTING_DOWN
	if typeof(received_generation) != TYPE_INT or typeof(received_token) != TYPE_INT:
		return REASON_INVALID
	if not expected.has(sender):
		return REASON_UNEXPECTED_PEER
	if not sent_tokens.has(sender):
		return REASON_PREPARE_NOT_SENT
	if int(received_generation) != generation:
		return REASON_STALE_GENERATION
	if int(received_token) != int(sent_tokens[sender]):
		return REASON_TOKEN_MISMATCH
	if ready.has(sender):
		return REASON_DUPLICATE
	ready[sender] = true
	return ""

## Um peer esperado que se desconecta não pode mais confirmar: deixa de ser
## esperado, para o encerramento dos demais continuar limpo.
func forget_peer(peer_id: int) -> void:
	expected.erase(peer_id)
	sent_tokens.erase(peer_id)
	ready.erase(peer_id)

func ready_count() -> int:
	return ready.size()

func expected_count() -> int:
	return expected.size()

func is_complete() -> bool:
	return active and ready.size() >= expected.size()

func clear() -> void:
	active = false
	expected.clear()
	sent_tokens.clear()
	ready.clear()
