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
	_send("submit_input_before_join", func(): submit_commands.rpc_id(1, [1, 1, [[0.0, 0.0, 0.0, 0.0, []]]]))
	_send("ack_before_join", func(): round_role_acknowledged.rpc_id(1, 1))
	_send("shutdown_ready_before_join", func(): shutdown_ready.rpc_id(1, 1, 1))
	_send("test_completed_before_join", func(): client_test_completed.rpc_id(1))
	# Protocolo 9: ações só existem dentro de comandos.
	_send("pickup_before_join", func(): submit_commands.rpc_id(1, [1, 2, [[0.0, 0.0, 0.0, 0.0, ["pickup", 1, "weapon_0"]]]]))
	_send("fire_before_join", func(): submit_commands.rpc_id(1, [1, 3, [[0.0, 0.0, 0.0, 0.0, ["fire", 1]]]]))
	_send("reload_before_join", func(): submit_commands.rpc_id(1, [1, 4, [[0.0, 0.0, 0.0, 0.0, ["reload", 1]]]]))
	_send("pickup_wrong_types", func(): submit_commands.rpc_id(1, [1, 5, [[0.0, 0.0, 0.0, 0.0, ["pickup", "1", ["weapon_0"]]]]]))
	_send("fire_wrong_types", func(): submit_commands.rpc_id(1, [1, 6, [[0.0, 0.0, 0.0, 0.0, ["fire", {"sequence": 1}, Vector3.ZERO, Vector3.FORWARD]]]]))
	_send("reload_wrong_type", func(): submit_commands.rpc_id(1, [1, 7, [[0.0, 0.0, 0.0, 0.0, ["reload", 1.5]]]]))

	# Tipos incorretos numa RPC que o servidor declara tipada.
	_send("join_wrong_types", func(): request_join.rpc_id(1, "not-an-int", 12345))
	_send("join_null_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, null))
	_send("join_array_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, ["a", "b"]))
	_send("join_dict_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, {"role": "ASSASSIN"}))
	_send("join_huge_label", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, "A".repeat(20000)))
	_send("join_extreme_protocol", func(): request_join.rpc_id(1, 9223372036854775807, label))

	# Entrada de movimento malformada antes de existir sessão.
	_send("input_non_finite", func(): submit_commands.rpc_id(1, [1, 8, [[NAN, INF, NAN, INF, []]]]))
	_send("input_wrong_types", func(): submit_commands.rpc_id(1, ["epoch", "seq", {"x": 1}]))

	# Tentativa de se passar pelo servidor numa RPC de autoridade.
	_send("forge_public_state", func(): round_public_state.rpc_id(1, {"state": RoundState.ACTIVE, "winning_team": Role.TEAM_ASSASSIN}))
	_send("forge_private_role", func(): round_private_role.rpc_id(1, 1, Role.ASSASSIN))
	_send("forge_final_reveal", func(): round_final_reveal.rpc_id(1, {"round_id": 1, "players": []}))
	_send("forge_spectator_targets", func(): round_private_spectator_targets.rpc_id(1, 1, [1]))
	_send("forge_roster", func(): round_roster.rpc_id(1, [{"peer_id": 1, "role": Role.ASSASSIN}]))
	_send("forge_combat_private_state", func(): combat_private_state.rpc_id(1, {"health": 999}))
	_send("forge_combat_hit", func(): combat_hit_confirmed.rpc_id(1))
	_send("forge_combat_elimination", func(): combat_public_elimination.rpc_id(1, 2))
	_send("forge_combat_shot", func(): combat_public_shot.rpc_id(1, {"hit_player": true}))
	_send("forge_pickup_state", func(): pickup_public_state.rpc_id(1, [{"available": false}]))
	_send("forge_combat_rejection", func(): combat_action_rejected.rpc_id(1, "fire", 1, "accepted"))

func run_session_attacks() -> void:
	if session_attacks_done:
		return
	session_attacks_done = true
	_send("ack_forged_round_zero", func(): round_role_acknowledged.rpc_id(1, 0))
	_send("ack_forged_round_negative", func(): round_role_acknowledged.rpc_id(1, -1))
	_send("ack_forged_round_huge", func(): round_role_acknowledged.rpc_id(1, 9223372036854775807))
	_send("ack_wrong_type", func(): round_role_acknowledged.rpc_id(1, {"round_id": 1}))
	_send("rejoin_same_peer", func(): request_join.rpc_id(1, NetworkConfig.PROTOCOL_VERSION, "second-session"))
	# Confirmações antecipadas: o atacante ainda não recebeu a preparação, então
	# só pode adivinhar geração e token. Nenhuma delas pode contar.
	_send("shutdown_ready_unsolicited", func(): shutdown_ready.rpc_id(1, 1, 0))
	_send("shutdown_ready_guessed_token", func(): shutdown_ready.rpc_id(1, 1, 123456789))
	_send("shutdown_ready_wrong_types", func(): shutdown_ready.rpc_id(1, "1", [0]))
	_send("test_completed_unsolicited", func(): client_test_completed.rpc_id(1))
	# Sessão aceita, mas sem ser participante da rodada: comandos (inclusive com
	# ações) são resolvidos como recusados e nada muda no estado oficial.
	_send("missing_pickup", func(): submit_commands.rpc_id(1, [1, 1, [[0.0, 0.0, 0.0, 0.0, ["pickup", 2, "does_not_exist"]]]]))
	_send("impossible_origin", func(): submit_commands.rpc_id(1, [1, 2, [[0.0, 0.0, 0.0, 0.0, ["fire", 2, Vector3(999, 999, 999)]]]]))
	_send("invalid_direction", func(): submit_commands.rpc_id(1, [1, 3, [[99.0, 0.0, 9.0, NAN, ["fire", 3]]]]))
	_send("replayed_fire_sequence", func(): submit_commands.rpc_id(1, [1, 3, [[0.0, 0.0, 0.0, 0.0, ["fire", 3]]]]))
	_send("oversized_batch", func(): submit_commands.rpc_id(1, [1, 4, _batch(NetSync.MAX_COMMANDS_PER_PACKET + 1)]))
	_send("sequence_far_ahead", func(): submit_commands.rpc_id(1, [1, 100000, _batch(1)]))
	_send("stale_epoch_commands", func(): submit_commands.rpc_id(1, [999, 5, _batch(2)]))
	for index in 40:
		round_role_acknowledged.rpc_id(1, index)
	attacks_sent += 40
	print("ATTACKER_SENT id=%s attack=ack_spam count=40" % label)
	finished.emit()

func _batch(count: int) -> Array:
	var commands: Array = []
	for index in count:
		commands.append([1.0, 0.0, 0.0, 0.0, []])
	return commands

func _send(description: String, action: Callable) -> void:
	attacks_sent += 1
	action.call()
	print("ATTACKER_SENT id=%s attack=%s" % [label, description])

# --- Superfície de RPC espelhada --------------------------------------------

@rpc("authority", "call_remote", "reliable")
func combat_action_rejected(action: String, sequence: int, reason: String) -> void:
	# Somente campos sanitizados pelo servidor; nunca imprime payload hostil.
	print("ATTACKER_COMBAT_REJECTED action=%s sequence=%d reason=%s" % [action, sequence, reason])

@rpc("authority", "call_remote", "reliable")
func combat_hit_confirmed() -> void:
	print("ATTACKER_UNEXPECTED_HIT_CONFIRM")

@rpc("authority", "call_remote", "reliable")
func combat_private_state(_payload: Dictionary) -> void:
	print("ATTACKER_UNEXPECTED_PRIVATE_COMBAT_STATE")

@rpc("authority", "call_remote", "reliable")
func combat_public_elimination(_peer_id: int) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func combat_public_shot(_payload: Dictionary) -> void:
	pass

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

@rpc("authority", "call_remote", "reliable")
func pickup_public_state(_payload: Array) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func round_final_reveal(_payload: Dictionary) -> void:
	print("ATTACKER_UNEXPECTED_FINAL_REVEAL")

## Corpos (fase 6): públicos, mas o atacante não participa de rodada.
@rpc("authority", "call_remote", "reliable")
func round_body_added(_payload: Dictionary) -> void:
	pass

@rpc("authority", "call_remote", "reliable")
func round_bodies_state(_payload: Dictionary) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func round_private_role(_round_id, _role) -> void:
	# Um peer que não participa da rodada jamais deveria chegar aqui.
	print("ATTACKER_RECEIVED_PRIVATE_ROLE id=%s" % label)

@rpc("authority", "call_remote", "reliable")
func round_private_spectator_targets(_round_id: int, _targets: Array) -> void:
	print("ATTACKER_UNEXPECTED_SPECTATOR_TARGETS")

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
func shutdown_prepare(generation, token) -> void:
	# Peer lento: processa a preparação meio segundo depois. Um servidor que
	# aceitasse o ready não solicitado fecharia a sessão antes deste ponto.
	await get_tree().create_timer(0.5).timeout
	print("ATTACKER_SHUTDOWN_PREPARE id=%s" % label)
	_send("pickup_during_shutdown", func(): submit_commands.rpc_id(1, [1, 20, [[0.0, 0.0, 0.0, 0.0, ["pickup", 63, "weapon_0"]]]]))
	_send("fire_during_shutdown", func(): submit_commands.rpc_id(1, [1, 21, [[0.0, 0.0, 0.0, 0.0, ["fire", 63]]]]))
	_send("reload_during_shutdown", func(): submit_commands.rpc_id(1, [1, 22, [[0.0, 0.0, 0.0, 0.0, ["reload", 63]]]]))
	if typeof(generation) != TYPE_INT or typeof(token) != TYPE_INT:
		return
	# Geração obsoleta e token trocado, com o token real já em mãos.
	_send("shutdown_ready_stale_generation", func(): shutdown_ready.rpc_id(1, int(generation) - 1, token))
	_send("shutdown_ready_wrong_token", func(): shutdown_ready.rpc_id(1, generation, int(token) ^ 1))
	shutdown_ready.rpc_id(1, generation, token)
	# Duplicada no mesmo quadro: chega antes do fechamento adiado do servidor.
	_send("shutdown_ready_duplicate", func(): shutdown_ready.rpc_id(1, generation, token))

@rpc("any_peer", "call_remote", "reliable")
func shutdown_ready(_generation, _token) -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func spectator_reveal_received() -> void:
	pass

@rpc("any_peer", "call_remote", "reliable")
func spectator_test_followed() -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_commands(_payload) -> void:
	pass

@rpc("any_peer", "call_remote", "unreliable_ordered")
func world_snapshot(payload) -> void:
	# Snapshot público: só as chaves de movimento; vida, inventário ou papel de
	# outro jogador nunca aparecem. O ACK é só do próprio atacante.
	if typeof(payload) != TYPE_DICTIONARY or typeof((payload as Dictionary).get("players")) != TYPE_ARRAY:
		return
	var allowed := ["peer_id", "position", "velocity", "yaw", "pitch", "spawn_index", "epoch"]
	for player in (payload as Dictionary)["players"]:
		for key in (player as Dictionary).keys():
			if str(key) not in allowed:
				print("ATTACKER_SNAPSHOT_HAS_PRIVATE id=%s key=%s" % [label, str(key)])
	var ack: Variant = (payload as Dictionary).get("ack", {})
	if typeof(ack) == TYPE_DICTIONARY and (ack as Dictionary).keys().size() > 0 \
			and (ack as Dictionary).keys() != ["seq", "epoch", "yaw_tokens", "pitch_tokens"]:
		print("ATTACKER_SNAPSHOT_HAS_PRIVATE id=%s key=ack" % label)
