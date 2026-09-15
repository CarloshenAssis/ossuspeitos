class_name AdversarialPeer
extends Node

## Nó que fala o protocolo real da auditoria com argumentos hostis.
##
## A superfície de RPC precisa espelhar exatamente a de `shared/network_app.gd`:
## o Godot resolve cada RPC por índice na lista ordenada de métodos anotados do
## nó. `tests/round_network_test.sh` fixa essa lista, portanto qualquer
## divergência quebra o teste em vez de silenciar o ataque.
##
## Os argumentos são intencionalmente sem tipo, para que o servidor receba
## exatamente o Variant que o atacante escolheu enviar.

signal finished

var label := "attacker"
var attack_phase := "full"
var joined := false
var attacks_sent := 0
var session_attacks_done := false

func run_preauth_attacks() -> void:
	# RPC sensível antes de existir sessão para o remetente.
	_send("submit_input_before_join", func(): submit_input.rpc_id(1, 1, Vector2.ZERO, 0.0))
	_send("ack_before_join", func(): round_role_acknowledged.rpc_id(1, 1))
	_send("shutdown_ready_before_join", func(): shutdown_ready.rpc_id(1))
	_send("test_completed_before_join", func(): client_test_completed.rpc_id(1))

	# Tipos incorretos numa RPC que o servidor declara tipada.
	_send("join_wrong_types", func(): request_join.rpc_id(1, "not-an-int", 12345))
	_send("join_null_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, null))
	_send("join_array_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, ["a", "b"]))
	_send("join_dict_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, {"role": "ASSASSIN"}))
	_send("join_huge_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, "A".repeat(20000)))
	_send("join_extreme_protocol", func(): request_join.rpc_id(1, 9223372036854775807, label))

	# Entrada de movimento malformada antes de existir sessão.
	_send("input_non_finite", func(): submit_input.rpc_id(1, 2, Vector2(NAN, INF), NAN))
	_send("input_wrong_types", func(): submit_input.rpc_id(1, "seq", {"x": 1}, [1, 2, 3]))

	# Tentativa de se passar pelo servidor numa RPC de autoridade.
	_send("forge_public_state", func(): round_public_state.rpc_id(1, {"state": RoundState.ACTIVE, "winning_team": Role.TEAM_ASSASSIN}))
	_send("forge_private_role", func(): round_private_role.rpc_id(1, 1, Role.ASSASSIN))
	_send("forge_roster", func(): round_roster.rpc_id(1, [{"peer_id": 1, "role": Role.ASSASSIN}]))

func run_session_attacks() -> void:
	if session_attacks_done:
		return
	session_attacks_done = true
	_send("ack_forged_round_zero", func(): round_role_acknowledged.rpc_id(1, 0))
	_send("ack_forged_round_negative", func(): round_role_acknowledged.rpc_id(1, -1))
	_send("ack_forged_round_huge", func(): round_role_acknowledged.rpc_id(1, 9223372036854775807))
	_send("ack_wrong_type", func(): round_role_acknowledged.rpc_id(1, {"round_id": 1}))
	_send("rejoin_same_peer", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, "second-session"))
	_send("shutdown_ready_unsolicited", func(): shutdown_ready.rpc_id(1))
	_send("test_completed_unsolicited", func(): client_test_completed.rpc_id(1))
	for index in 40:
		round_role_acknowledged.rpc_id(1, index)
	attacks_sent += 40
	print("ATTACKER_SENT id=%s attack=ack_spam count=40" % label)
	finished.emit()

func _send(description: String, action: Callable) -> void:
	attacks_sent += 1
	action.call()
	print("ATTACKER_SENT id=%s attack=%s" % [label, description])

# --- Superfície de RPC espelhada --------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func client_count_changed(_count) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func client_test_completed() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func input_rejected(_reason, _sequence) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func join_accepted(_peer_id) -> void:
	joined = true
	print("ATTACKER_JOIN_ACCEPTED id=%s" % label)
	run_session_attacks()

@rpc("any_peer", "call_remote", "reliable")
func join_rejected(reason) -> void:
	print("ATTACKER_JOIN_REJECTED id=%s reason=%s" % [label, str(reason)])

@rpc("any_peer", "call_remote", "reliable")
func request_join(_protocol_version, _requested_label) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func round_private_role(_round_id, _role) -> void:
	# Um peer que não participa da rodada jamais deveria chegar aqui.
	print("ATTACKER_RECEIVED_PRIVATE_ROLE id=%s" % label)

@rpc("any_peer", "call_remote", "reliable")
func round_public_state(payload) -> void:
	if typeof(payload) == TYPE_DICTIONARY and (payload as Dictionary).has("role"):
		print("ATTACKER_PUBLIC_STATE_HAS_ROLE id=%s" % label)

@rpc("any_peer", "call_remote", "reliable")
func round_role_acknowledged(_round_id) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func round_roster(entries) -> void:
	if typeof(entries) != TYPE_ARRAY:
		return
	for raw_entry in entries:
		if typeof(raw_entry) == TYPE_DICTIONARY and (raw_entry as Dictionary).has("role"):
			print("ATTACKER_ROSTER_HAS_ROLE id=%s" % label)
			return

@rpc("any_peer", "call_remote", "reliable")
func shutdown_prepare() -> void:
	print("ATTACKER_SHUTDOWN_PREPARE id=%s" % label)
	shutdown_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func shutdown_ready() -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(_sequence, _move, _yaw_delta) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func world_snapshot(_states) -> void:
	pass
