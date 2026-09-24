#!/usr/bin/env bash
set -Eeuo pipefail

# Teste adversarial da auditoria. Uma rodada real com quatro participantes roda
# enquanto um quinto peer hostil, que chega depois do início, envia argumentos
# malformados, identidades forjadas, round_id falsificado e RPC fora de fase.
#
# O objetivo é provar três coisas: o servidor sobrevive, continua sendo a única
# autoridade, e o peer hostil nunca recebe papel algum.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot4 >/dev/null; then
    GODOT_BIN="$(command -v godot4)"
  elif command -v godot >/dev/null; then
    GODOT_BIN="$(command -v godot)"
  fi
fi
PORT="${TEST_PORT:-$((23080 + RANDOM % 1000))}"
ROUND_SEED="${TEST_ROUND_SEED:-20250915}"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then
  TMP_DIR="$TEST_LOG_DIR"
  mkdir -p "$TMP_DIR"
  REMOVE_TMP_DIR=false
else
  TMP_DIR="$(mktemp -d)"
  REMOVE_TMP_DIR=true
fi
PIDS=()
PROCESS_NAMES=()
PROCESS_STATUSES=()
WATCHDOG_PID=""
TEST_FINISHED=false

cleanup() {
	local original_status=$?
	trap - EXIT
	if [[ -n "$WATCHDOG_PID" ]]; then
		kill "$WATCHDOG_PID" 2>/dev/null || true
	fi
	for pid in "${PIDS[@]:-}"; do
		kill "$pid" 2>/dev/null || true
	done
	wait 2>/dev/null || true
	if [[ "$REMOVE_TMP_DIR" == true ]]; then
		rm -rf "$TMP_DIR"
	fi
	return "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

report_failure() {
	local status="$1"
	local line="$2"
	local command="$3"
	echo "HARNESS_ERROR line=$line status=$status command=$command" >&2
	echo "Adversarial round test failed (exit=$status). Logs:" >&2
	if compgen -G "$TMP_DIR/*.log" >/dev/null; then
		cat "$TMP_DIR"/*.log >&2
	fi
	exit "$status"
}
trap 'report_failure "$?" "$LINENO" "$BASH_COMMAND"' ERR

check_ok() { echo "ASSERT_OK name=$1"; }
check_failed() { echo "ASSERT_FAILED name=$1 detail=$2" >&2; return 1; }

assert_grep() {
	local name="$1" pattern="$2"; shift 2
	if grep -qE -- "$pattern" "$@"; then check_ok "$name"; else check_failed "$name" "pattern not found: $pattern"; fi
}

assert_no_grep() {
	local name="$1" pattern="$2"; shift 2
	if grep -qE -- "$pattern" "$@"; then check_failed "$name" "forbidden pattern found: $pattern"; else check_ok "$name"; fi
}

assert_equal() {
	local name="$1" actual="$2" expected="$3"
	if [[ "$actual" == "$expected" ]]; then check_ok "$name"; else check_failed "$name" "expected=$expected actual=$actual"; fi
}

wait_for_marker() {
	local pattern="$1" file="$2" guard_pid="$3"
	for _ in {1..600}; do
		if grep -qE -- "$pattern" "$file"; then return 0; fi
		kill -0 "$guard_pid" 2>/dev/null || { cat "$file" >&2; return 1; }
		sleep 0.05
	done
	cat "$file" >&2
	return 1
}

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Godot 4 not found. Set GODOT_BIN to the executable." >&2
  exit 127
fi

# --- Invariante estrutural: registros por peer precisam morrer com o peer -----
# Todo dicionário indexado por peer_id limpo no encerramento também precisa ser
# limpo na desconexão, senão um ciclo de reconexões cresce sem limite.
DISCONNECT_BLOCK="$(awk '/^func _on_peer_disconnected/,/^$/' "$ROOT/shared/network_app.gd")"
for registry in completed_peers impossible_input_rejected_peers round_ack_peers round_late_join_peers shutdown_ready_rejections_logged command_logs input_rejection_ticks; do
	if grep -q "${registry}\.erase(peer_id)" <<<"$DISCONNECT_BLOCK"; then
		check_ok "per-peer-registry-cleared-on-disconnect-$registry"
	else
		check_failed "per-peer-registry-cleared-on-disconnect-$registry" "$registry is never erased when a peer leaves"
	fi
done

# --- O atacante precisa falar exatamente o mesmo protocolo -------------------
# O Godot resolve cada RPC por índice na lista ordenada de métodos anotados do
# nó. Se a superfície do atacante divergir da do servidor, os ataques passariam
# a bater em outros métodos e o teste viraria teatro.
rpc_surface_of() {
	awk '
	  /^@rpc/ { pending = 1; next }
	  pending && /^func / { name = $2; sub(/\(.*/, "", name); print name; pending = 0; next }
	  pending && $0 !~ /^[[:space:]]*(#|$)/ { pending = 0 }
	' "$@" | sort -u | tr '\n' ' '
}
SERVER_SURFACE="$(rpc_surface_of "$ROOT"/shared/*.gd "$ROOT"/client/*.gd "$ROOT"/server/*.gd)"
ATTACKER_SURFACE="$(rpc_surface_of "$ROOT/tests/adversarial_peer.gd")"
echo "RPC_SURFACE server=[$SERVER_SURFACE]"
assert_equal "attacker-mirrors-the-server-rpc-surface" "$ATTACKER_SURFACE" "$SERVER_SURFACE"

# --- Servidor e rodada legítima ----------------------------------------------
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 \
  --port="$PORT" --countdown-seconds=1 --round-end-delay-seconds=30 \
  --round-seed="$ROUND_SEED" --stop-after-round-active=4 --expect-late-joins=1 \
  >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!")
PROCESS_NAMES+=("server")
SERVER_PID="${PIDS[0]}"

wait_for_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"
assert_grep "headless-server-has-no-ui" 'SERVER_UI hud=false arena=false display=headless' "$TMP_DIR/server.log"

for id in 1 2 3 4; do
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" \
    --url="ws://127.0.0.1:$PORT" --round-test=true >"$TMP_DIR/client-$id.log" 2>&1 &
	PIDS+=("$!")
	PROCESS_NAMES+=("client-$id")
done

(
  sleep 60
  if [[ "$TEST_FINISHED" != true ]]; then
    echo "Timed out waiting for adversarial round test" >"$TMP_DIR/timeout.log"
	for pid in "${PIDS[@]}"; do
		kill "$pid" 2>/dev/null && echo "WATCHDOG_KILL pid=$pid" || echo "WATCHDOG_KILL_FAILED pid=$pid"
	done
  fi
) &
WATCHDOG_PID=$!

# O peer hostil só entra com a rodada já ACTIVE: ele é um join tardio e não pode
# se tornar participante nem receber papel.
wait_for_marker 'ROUND_STATE state=ACTIVE' "$TMP_DIR/server.log" "$SERVER_PID"
# Ordem fixa: o atacante só entra depois das quatro confirmações de papel. Assim
# o próprio `request_join` dele dispara o shutdown e o `shutdown_ready` não
# solicitado que ele envia ao ser aceito sempre chega com o encerramento já em
# curso — exatamente a corrida que antes era intermitente no CI.
wait_for_marker 'CLIENT_PRIVATE_ROLE_ACK peer_id=[0-9]+ count=4' "$TMP_DIR/server.log" "$SERVER_PID"
"$GODOT_BIN" --headless --path "$ROOT" --script tests/adversarial_client.gd -- \
  --client-id=attacker --url="ws://127.0.0.1:$PORT" --quit-after-msec=45000 \
  >"$TMP_DIR/attacker.log" 2>&1 &
PIDS+=("$!")
PROCESS_NAMES+=("attacker")

for index in "${!PIDS[@]}"; do
	pid="${PIDS[$index]}"
	name="${PROCESS_NAMES[$index]}"
	if wait "$pid"; then process_status=0; else process_status=$?; fi
	echo "PROCESS_STATUS name=$name pid=$pid status=$process_status"
	PROCESS_STATUSES+=("$process_status")
done
for index in "${!PROCESS_STATUSES[@]}"; do
	assert_equal "process-${PROCESS_NAMES[$index]}-exit" "${PROCESS_STATUSES[$index]}" "0"
done
TEST_FINISHED=true
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
WATCHDOG_PID=""
if [[ ! -f "$TMP_DIR/timeout.log" ]]; then
	check_ok "watchdog-timeout-absent"
else
	check_failed "watchdog-timeout-absent" "timeout.log exists"
fi

# --- O servidor sobreviveu e continuou autoritativo --------------------------
# O peer hostil termina pelo shutdown coordenado do servidor, não pelo próprio
# timer: os dois desfechos são aceitos, mas ele precisa ter atacado e entrado.
assert_grep "attacker-terminated-cleanly" '(ATTACKER_SERVER_DISCONNECTED id=attacker attacks=[0-9]+|ATTACKER_DONE id=attacker attacks=[0-9]+)' "$TMP_DIR/attacker.log"
assert_grep "attacker-obtained-a-session" 'ATTACKER_JOIN_ACCEPTED id=attacker' "$TMP_DIR/attacker.log"
ATTACK_COUNT="$(sed -n 's/.*ATTACKER_SERVER_DISCONNECTED id=attacker attacks=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/attacker.log" | tail -1)"
if [[ -n "$ATTACK_COUNT" && "$ATTACK_COUNT" -ge 50 ]]; then
	check_ok "attacker-sent-its-full-attack-set"
else
	check_failed "attacker-sent-its-full-attack-set" "expected at least 50 attacks, got '${ATTACK_COUNT:-none}'"
fi
for attack in pickup_before_join fire_before_join reload_before_join pickup_wrong_types fire_wrong_types reload_wrong_type missing_pickup impossible_origin invalid_direction replayed_fire_sequence forge_combat_private_state forge_combat_hit forge_combat_elimination pickup_during_shutdown fire_during_shutdown reload_during_shutdown; do
	assert_grep "combat-probe-sent-$attack" "ATTACKER_SENT id=attacker attack=$attack" "$TMP_DIR/attacker.log"
done
# Encerramento correlacionado (antes o achado F7): cada `shutdown_prepare` leva
# geração e token por peer, e só a confirmação que devolve exatamente o que o
# servidor enviou àquele remetente conta. O atacante entra por último, é lento
# para processar a preparação e antes disso envia confirmações adivinhadas;
# nenhuma pode encerrar a sessão dele antes das sondas acima.
ATTACKER_PEER="$(sed -n 's/.*CLIENT_JOINED id=attacker peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | head -1)"
if [[ -n "$ATTACKER_PEER" ]]; then check_ok "attacker-peer-id-known"; else check_failed "attacker-peer-id-known" "no CLIENT_JOINED for attacker"; fi
assert_equal "attacker-processed-the-preparation-once" "$(grep -c 'ATTACKER_SHUTDOWN_PREPARE id=attacker' "$TMP_DIR/attacker.log")" "1"
assert_grep "shutdown-prepare-sent-to-everyone" 'SERVER_SHUTDOWN_PREPARE_SENT generation=1 peers=5' "$TMP_DIR/server.log"
# unexpected_peer: antes do join; token_mismatch: antecipada/adivinhada ou
# trocada; invalid: tipos errados; stale_generation: geração anterior;
# duplicate: repetição da confirmação já aceita.
for reason in unexpected_peer token_mismatch invalid stale_generation duplicate; do
	assert_grep "attacker-own-ready-rejected-$reason" "SHUTDOWN_READY_REJECTED peer_id=$ATTACKER_PEER reason=$reason" "$TMP_DIR/server.log"
done
assert_equal "exactly-five-accepted-readies" "$(grep -c 'CLIENT_SHUTDOWN_READY peer_id=' "$TMP_DIR/server.log")" "5"
assert_equal "attacker-ready-accepted-once" "$(grep -c "CLIENT_SHUTDOWN_READY peer_id=$ATTACKER_PEER " "$TMP_DIR/server.log")" "1"
# Ordem no log do servidor: a confirmação antecipada do atacante foi recusada
# antes da aceita, e a aceita só aparece depois da recusa da geração obsoleta
# (enviada já com a preparação em mãos).
EARLY_LINE="$(grep -n "SHUTDOWN_READY_REJECTED peer_id=$ATTACKER_PEER reason=token_mismatch" "$TMP_DIR/server.log" | head -1 | cut -d: -f1)"
STALE_LINE="$(grep -n "SHUTDOWN_READY_REJECTED peer_id=$ATTACKER_PEER reason=stale_generation" "$TMP_DIR/server.log" | head -1 | cut -d: -f1)"
ACCEPTED_LINE="$(grep -n "CLIENT_SHUTDOWN_READY peer_id=$ATTACKER_PEER " "$TMP_DIR/server.log" | head -1 | cut -d: -f1)"
if [[ -n "$EARLY_LINE" && -n "$STALE_LINE" && -n "$ACCEPTED_LINE" && "$EARLY_LINE" -lt "$STALE_LINE" && "$STALE_LINE" -lt "$ACCEPTED_LINE" ]]; then
	check_ok "attacker-ready-counted-only-after-its-preparation"
else
	check_failed "attacker-ready-counted-only-after-its-preparation" "early=$EARLY_LINE stale=$STALE_LINE accepted=$ACCEPTED_LINE"
fi
for id in 1 2 3 4; do
	assert_equal "legit-client-$id-single-shutdown-prepare" "$(grep -c "CLIENT_SHUTDOWN_PREPARE id=client-$id" "$TMP_DIR/client-$id.log")" "1"
	assert_equal "legit-client-$id-single-shutdown-complete" "$(grep -c "CLIENT_SHUTDOWN_COMPLETE id=client-$id" "$TMP_DIR/client-$id.log")" "1"
done
assert_grep "hostile-peer-did-not-degrade-the-handshake" 'SERVER_SHUTDOWN_READY clients=5' "$TMP_DIR/server.log"
assert_grep "server-completed-the-round" 'ROLE_PRIVACY_TEST_OK clients=4 assassin=1 detective=1 victim=2' "$TMP_DIR/server.log"
assert_grep "server-shut-down-cleanly" 'SERVER_SHUTDOWN_COMPLETE closed=5' "$TMP_DIR/server.log"
assert_no_grep "no-shutdown-timeout" 'SERVER_SHUTDOWN_TIMEOUT' "$TMP_DIR"/*.log
assert_no_grep "no-websocket-state-error" 'ready_state != STATE_OPEN' "$TMP_DIR"/*.log

# --- O peer hostil nunca recebeu papel ---------------------------------------
assert_no_grep "attacker-never-received-a-role" 'ATTACKER_RECEIVED_PRIVATE_ROLE' "$TMP_DIR/attacker.log"
assert_no_grep "attacker-roster-carries-no-role" 'ATTACKER_ROSTER_HAS_ROLE' "$TMP_DIR/attacker.log"
assert_no_grep "attacker-public-state-carries-no-role" 'ATTACKER_PUBLIC_STATE_HAS_ROLE' "$TMP_DIR/attacker.log"
assert_no_grep "attacker-never-received-private-combat-state" 'ATTACKER_UNEXPECTED_PRIVATE_COMBAT_STATE' "$TMP_DIR/attacker.log"
assert_no_grep "attacker-never-received-hit-confirm" 'ATTACKER_UNEXPECTED_HIT_CONFIRM' "$TMP_DIR/attacker.log"
assert_no_grep "attacker-log-carries-no-role-name" '(ASSASSIN|DETECTIVE|VICTIM)' "$TMP_DIR/attacker.log"
assert_grep "attacker-registered-as-late-join" 'ROUND_LATE_JOIN peer_id=[0-9]+ round_id=1 count=1' "$TMP_DIR/server.log"

# --- Argumentos malformados são recusados pela camada de RPC -----------------
# O Godot recusa a conversão antes de executar o corpo tipado do servidor.
assert_grep "wrong-typed-join-refused" "RPC - 'Node\(network_app.gd\)::request_join': Cannot convert argument" "$TMP_DIR/server.log"
# Protocolo 9: o atacante entra por último e o próprio join dispara o
# encerramento, então os pacotes de comando dele chegam com o servidor já em
# shutdown e são ignorados (como antes as RPCs de ação). A recusa de pacotes
# malformados com rodada ativa é coberta por `netcode_test.gd` e
# `netcode_network_test.sh`. Aqui: nenhum erro de script por eles.
assert_no_grep "no-script-error-from-hostile-commands" 'SCRIPT ERROR' "$TMP_DIR/server.log"
assert_no_grep "snapshot-carries-no-private-fields" 'ATTACKER_SNAPSHOT_HAS_PRIVATE' "$TMP_DIR/attacker.log"
assert_grep "huge-label-refused" 'JOIN_REJECTED|invalid_client' "$TMP_DIR/attacker.log"
assert_grep "duplicate-session-refused" 'ATTACKER_JOIN_REJECTED id=attacker reason=invalid_client' "$TMP_DIR/attacker.log"

# --- RPC de autoridade não pode ser chamada por um cliente -------------------
for rpc in round_private_role round_public_state round_roster combat_private_state combat_hit_confirmed combat_public_elimination combat_public_shot pickup_public_state combat_action_rejected; do
	assert_grep "authority-rpc-refused-$rpc" "RPC '$rpc' is not allowed on node .* Mode is 2, authority is 1" "$TMP_DIR/server.log"
done

# --- round_id forjado e ack de não participante são recusados ---------------
assert_grep "forged-ack-refused" 'ROUND_ACK_REJECTED peer_id=[0-9]+ reason=(stale_round|not_in_round)' "$TMP_DIR/server.log"
assert_equal "acknowledgements-stay-at-four" "$(grep -c 'CLIENT_PRIVATE_ROLE_ACK peer_id=' "$TMP_DIR/server.log")" "4"
assert_equal "four-unique-acknowledging-peers" "$(sed -n 's/.*CLIENT_PRIVATE_ROLE_ACK peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l | tr -d ' ')" "4"
assert_equal "exactly-four-roles-delivered" "$(grep -c 'ROUND_ROLES_DELIVERED round_id=1 peers=4' "$TMP_DIR/server.log")" "1"
assert_no_grep "no-extra-round-started" 'ROUND_STATE state=(COUNTDOWN|ACTIVE) round_id=[2-9]' "$TMP_DIR/server.log"
assert_no_grep "no-invalid-transition" 'ROUND_TRANSITION_REJECTED' "$TMP_DIR/server.log"

# --- Nenhum papel vazou para os clientes legítimos ---------------------------
assert_no_grep "client-logs-carry-no-role-names" '(ASSASSIN|DETECTIVE|VICTIM)' "$TMP_DIR"/client-*.log
assert_no_grep "server-log-carries-no-role-names" '(ASSASSIN|DETECTIVE|VICTIM)' "$TMP_DIR/server.log"
assert_no_grep "no-peer-to-role-association" 'peer_id=[0-9]+.*role=' "$TMP_DIR"/*.log

echo "FINAL_CHECKS status=0"
echo "ROUND_ADVERSARIAL_OK server=1 participants=4 hostile=1"
