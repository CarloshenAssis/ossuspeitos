extends SceneTree

## Testes determinísticos do encerramento em duas fases. Reproduzem a corrida do
## atacante tardio (ready não solicitado aceito como legítimo) e fixam que só a
## confirmação de uma preparação efetivamente enviada, com geração e token
## corretos, avança a contagem.

var failures := 0
var checks := 0

func _initialize() -> void:
	_test_ready_before_shutdown_is_rejected()
	_test_late_attacker_unsolicited_ready_does_not_count()
	_test_ready_before_prepare_was_sent_is_rejected()
	_test_stale_generation_is_rejected()
	_test_duplicate_does_not_advance()
	_test_unexpected_peer_and_invalid_types()
	_test_tokens_are_per_peer_and_non_zero()
	_test_disconnect_during_shutdown_lets_the_rest_finish()
	_test_clear_resets_everything()
	if failures > 0:
		push_error("SHUTDOWN_HANDSHAKE_TEST_FAILED failures=%d checks=%d" % [failures, checks])
		quit(1)
		return
	print("SHUTDOWN_HANDSHAKE_TEST_OK checks=%d" % checks)
	quit(0)

func _test_ready_before_shutdown_is_rejected() -> void:
	var handshake := ShutdownHandshake.new(7)
	_expect(handshake.accept_ready(10, 1, 1) == ShutdownHandshake.REASON_NOT_SHUTTING_DOWN, "ready before any shutdown is rejected")
	handshake.begin([10])
	_expect(handshake.ready_count() == 0, "an early ready is not remembered for the next shutdown")

## Sequência real do CI: o join do atacante inicia o encerramento, o servidor já
## enviou a preparação a todos, e o atacante confirma sem ter lido a preparação.
func _test_late_attacker_unsolicited_ready_does_not_count() -> void:
	var handshake := ShutdownHandshake.new(11)
	var legit := [1, 2, 3, 4]
	var attacker := 99
	var generation := handshake.begin(legit + [attacker])
	var tokens := {}
	for peer_id in legit + [attacker]:
		tokens[peer_id] = handshake.prepare_token_for(peer_id)
	# Confirmação não solicitada: o atacante só pode adivinhar o token.
	_expect(handshake.accept_ready(attacker, generation, 0) == ShutdownHandshake.REASON_TOKEN_MISMATCH, "unsolicited ready with token 0 is rejected")
	_expect(handshake.accept_ready(attacker, generation, 123456789) == ShutdownHandshake.REASON_TOKEN_MISMATCH, "guessed token is rejected")
	for peer_id in legit:
		_expect(handshake.accept_ready(peer_id, generation, tokens[peer_id]).is_empty(), "legit peer %d confirms its own preparation" % peer_id)
	# O cenário que antes fechava o servidor cedo demais.
	_expect(not handshake.is_complete(), "four legit readies plus a forged one do not complete the shutdown")
	_expect(handshake.ready_count() == 4, "forged readies never advance the count")
	_expect(handshake.accept_ready(attacker, generation, tokens[attacker]).is_empty(), "attacker counts only after echoing its preparation")
	_expect(handshake.is_complete(), "shutdown completes once every prepared peer confirmed")

func _test_ready_before_prepare_was_sent_is_rejected() -> void:
	var handshake := ShutdownHandshake.new(13)
	var generation := handshake.begin([5, 6])
	var token := handshake.prepare_token_for(5)
	_expect(handshake.accept_ready(6, generation, token) == ShutdownHandshake.REASON_PREPARE_NOT_SENT, "a peer whose preparation was not sent yet cannot confirm")
	_expect(handshake.accept_ready(6, generation, token) != "", "another peer's token is useless")
	var own := handshake.prepare_token_for(6)
	_expect(handshake.accept_ready(6, generation, token) == ShutdownHandshake.REASON_TOKEN_MISMATCH, "another peer's token is rejected after own preparation")
	_expect(handshake.accept_ready(6, generation, own).is_empty(), "own token is accepted")

func _test_stale_generation_is_rejected() -> void:
	var handshake := ShutdownHandshake.new(17)
	var first := handshake.begin([3])
	var old_token := handshake.prepare_token_for(3)
	var second := handshake.begin([3])
	_expect(second == first + 1, "each attempt gets a new generation")
	_expect(handshake.accept_ready(3, first, old_token) == ShutdownHandshake.REASON_PREPARE_NOT_SENT, "old confirmation before the new preparation is rejected")
	var new_token := handshake.prepare_token_for(3)
	_expect(handshake.accept_ready(3, first, new_token) == ShutdownHandshake.REASON_STALE_GENERATION, "previous generation is rejected")
	_expect(handshake.accept_ready(3, second, old_token) == ShutdownHandshake.REASON_TOKEN_MISMATCH or old_token == new_token, "previous token is rejected")
	_expect(handshake.accept_ready(3, second, new_token).is_empty(), "current generation and token are accepted")

func _test_duplicate_does_not_advance() -> void:
	var handshake := ShutdownHandshake.new(19)
	var generation := handshake.begin([1, 2])
	var token := handshake.prepare_token_for(1)
	handshake.prepare_token_for(2)
	_expect(handshake.accept_ready(1, generation, token).is_empty(), "first confirmation accepted")
	_expect(handshake.accept_ready(1, generation, token) == ShutdownHandshake.REASON_DUPLICATE, "duplicate rejected")
	_expect(handshake.ready_count() == 1 and not handshake.is_complete(), "duplicate does not complete the shutdown")

func _test_unexpected_peer_and_invalid_types() -> void:
	var handshake := ShutdownHandshake.new(23)
	var generation := handshake.begin([1])
	var token := handshake.prepare_token_for(1)
	_expect(handshake.prepare_token_for(42) == 0, "no token for a peer outside the attempt")
	_expect(handshake.accept_ready(42, generation, token) == ShutdownHandshake.REASON_UNEXPECTED_PEER, "unexpected peer rejected even with a valid token")
	_expect(handshake.accept_ready(1, "1", token) == ShutdownHandshake.REASON_INVALID, "string generation rejected")
	_expect(handshake.accept_ready(1, generation, [token]) == ShutdownHandshake.REASON_INVALID, "array token rejected")
	_expect(handshake.accept_ready(1, generation, float(token)) == ShutdownHandshake.REASON_INVALID, "float token rejected")
	_expect(handshake.ready_count() == 0, "rejections leave the count untouched")

func _test_tokens_are_per_peer_and_non_zero() -> void:
	var handshake := ShutdownHandshake.new(29)
	handshake.begin(range(1, 9))
	var seen := {}
	for peer_id in range(1, 9):
		var token := handshake.prepare_token_for(peer_id)
		_expect(token != 0, "token for peer %d is non-zero" % peer_id)
		seen[token] = true
	_expect(seen.size() == 8, "each peer gets its own token")
	var unseeded := ShutdownHandshake.new()
	unseeded.begin([1])
	var other := ShutdownHandshake.new()
	other.begin([1])
	_expect(unseeded.prepare_token_for(1) != other.prepare_token_for(1), "production tokens are randomized")

func _test_disconnect_during_shutdown_lets_the_rest_finish() -> void:
	var handshake := ShutdownHandshake.new(31)
	var generation := handshake.begin([1, 2])
	var token := handshake.prepare_token_for(1)
	var gone := handshake.prepare_token_for(2)
	_expect(handshake.accept_ready(1, generation, token).is_empty(), "remaining peer confirms")
	_expect(not handshake.is_complete(), "still waiting for the second peer")
	handshake.forget_peer(2)
	_expect(handshake.is_complete(), "a disconnected peer is no longer awaited")
	_expect(handshake.accept_ready(2, generation, gone) == ShutdownHandshake.REASON_UNEXPECTED_PEER, "a forgotten peer cannot confirm later")

func _test_clear_resets_everything() -> void:
	var handshake := ShutdownHandshake.new(37)
	var generation := handshake.begin([1])
	var token := handshake.prepare_token_for(1)
	handshake.clear()
	_expect(not handshake.active and handshake.expected_count() == 0 and handshake.ready_count() == 0, "clear drops the attempt")
	_expect(handshake.accept_ready(1, generation, token) == ShutdownHandshake.REASON_NOT_SHUTTING_DOWN, "nothing is accepted after clear")
	_expect(not handshake.is_complete(), "a cleared handshake is never complete")

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("SHUTDOWN_HANDSHAKE_CHECK_FAILED %s" % message)
