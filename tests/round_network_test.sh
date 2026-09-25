#!/usr/bin/env bash
set -Eeuo pipefail

# Teste multiprocesso do sigilo dos papéis: um servidor autoritativo, quatro
# clientes que participam da rodada e um quinto que chega tarde e precisa
# aguardar a próxima. Nenhuma asserção depende de renderização.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot4 >/dev/null; then
    GODOT_BIN="$(command -v godot4)"
  elif command -v godot >/dev/null; then
    GODOT_BIN="$(command -v godot)"
  fi
fi
PORT="${TEST_PORT:-$((21080 + RANDOM % 1000))}"
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
	echo "Round network test failed (exit=$status). Logs:" >&2
	if compgen -G "$TMP_DIR/*.log" >/dev/null; then
		cat "$TMP_DIR"/*.log >&2
	fi
	exit "$status"
}
trap 'report_failure "$?" "$LINENO" "$BASH_COMMAND"' ERR

check_ok() {
	echo "ASSERT_OK name=$1"
}

check_failed() {
	echo "ASSERT_FAILED name=$1 detail=$2" >&2
	return 1
}

assert_grep() {
	local name="$1"
	local pattern="$2"
	shift 2
	if grep -qE -- "$pattern" "$@"; then
		check_ok "$name"
	else
		check_failed "$name" "pattern not found: $pattern"
	fi
}

assert_no_grep() {
	local name="$1"
	local pattern="$2"
	shift 2
	if grep -qE -- "$pattern" "$@"; then
		check_failed "$name" "forbidden pattern found: $pattern"
	else
		check_ok "$name"
	fi
}

assert_equal() {
	local name="$1"
	local actual="$2"
	local expected="$3"
	if [[ "$actual" == "$expected" ]]; then
		check_ok "$name"
	else
		check_failed "$name" "expected=$expected actual=$actual"
	fi
}

wait_for_marker() {
	local pattern="$1"
	local file="$2"
	local guard_pid="$3"
	for _ in {1..400}; do
		if grep -qE -- "$pattern" "$file"; then
			return 0
		fi
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

# --- Revisão estática do protocolo -------------------------------------------
# Nenhuma RPC pode permitir ao cliente escolher papel, consultar o papel alheio
# ou declarar morte.
# `get_role_for_peer` é consulta interna do servidor e continua permitida: a
# lista abaixo cobre nomes que só existiriam para dar poder ao cliente, e a
# asserção da superfície de RPC prova que nenhuma delas é exposta.
FORBIDDEN_RPC='func (kill_player|set_alive|report_death|eliminate_me|eliminate_peer|request_role|choose_role|set_role|select_role|peek_role|reveal_role|query_role|get_role_of)\('
assert_no_grep "no-client-facing-role-or-death-rpc" "$FORBIDDEN_RPC" \
  "$ROOT"/shared/*.gd "$ROOT"/client/*.gd "$ROOT"/server/*.gd
# Superfície de RPC declarada no projeto: qualquer função nova precisa entrar
# nesta lista conscientemente.
RPC_SURFACE="$(awk '
  /^@rpc/ { pending = 1; next }
  pending && /^func / { name = $2; sub(/\(.*/, "", name); print name; pending = 0; next }
  pending && $0 !~ /^[[:space:]]*(#|$)/ { pending = 0 }
' "$ROOT"/shared/*.gd "$ROOT"/client/*.gd "$ROOT"/server/*.gd | sort -u | tr '\n' ' ')"
echo "RPC_SURFACE $RPC_SURFACE"
# Fase 9 (protocolo 11): salas online. Cliente -> servidor: room_create,
# room_join, room_set_ready (só intenções; a sala vem do vínculo do servidor).
# Servidor -> cliente: room_welcome, room_state, room_error.
EXPECTED_RPC_SURFACE="client_count_changed client_test_completed combat_action_rejected combat_hit_confirmed combat_private_state combat_public_elimination combat_public_shot input_rejected join_accepted join_rejected pickup_public_state request_join room_create room_error room_join room_set_ready room_state room_welcome round_bodies_state round_body_added round_final_reveal round_private_role round_private_spectator_targets round_public_state round_role_acknowledged round_roster shutdown_prepare shutdown_ready spectator_reveal_received spectator_test_followed submit_commands world_snapshot "
assert_equal "declared-rpc-surface" "$RPC_SURFACE" "$EXPECTED_RPC_SURFACE"
# O Godot endereça RPC pelo índice na lista ordenada de nomes. O handshake
# (`request_join` e a recusa `join_rejected`) precisa manter o índice entre
# versões: assim uma build antiga recebe a recusa `protocol_version` legível
# em vez de uma RPC trocada. Nomes novos devem ordenar depois de
# `request_join` (desde o protocolo 10: join_rejected=9, request_join=11).
rpc_index() { local i=0; for name in $RPC_SURFACE; do [[ "$name" == "$1" ]] && { echo "$i"; return; }; i=$((i + 1)); done; echo -1; }
assert_equal "handshake-index-join-rejected" "$(rpc_index join_rejected)" "9"
assert_equal "handshake-index-request-join" "$(rpc_index request_join)" "11"
# Restringe a revisão estática ao construtor do roster público. O mesmo arquivo
# também contém o DTO de reveal pós-ENDED, onde `role` é legítimo e obrigatório.
assert_no_grep "public-roster-has-no-role-field" '"role"' \
  <(sed -n '/^func public_roster()/,/^# --- Transições/p' "$ROOT/server/round_authority.gd")
assert_no_grep "movement-snapshot-has-no-role-field" 'role' "$ROOT/shared/movement_rules.gd"
assert_no_grep "offline-demo-has-no-role" 'Role\.|role' "$ROOT/client/visual_demo.gd"

# --- Servidor ----------------------------------------------------------------
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 \
  --port="$PORT" --countdown-seconds=1 --round-end-delay-seconds=30 \
  --round-seed="$ROUND_SEED" --stop-after-round-active=4 --expect-late-joins=1 \
  >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!")
PROCESS_NAMES+=("server")
SERVER_PID="${PIDS[0]}"

wait_for_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"
assert_grep "server-ready" 'SERVER_READY' "$TMP_DIR/server.log"
# O marcador vem do estado real dos nós, não de um texto fixo.
assert_grep "headless-server-has-no-ui" 'SERVER_UI hud=false arena=false display=headless' "$TMP_DIR/server.log"

for id in 1 2 3 4; do
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" \
    --url="ws://127.0.0.1:$PORT" --round-test=true >"$TMP_DIR/client-$id.log" 2>&1 &
	PIDS+=("$!")
	PROCESS_NAMES+=("client-$id")
done

(
  sleep 40
  if [[ "$TEST_FINISHED" != true ]]; then
    echo "Timed out waiting for round network test" >"$TMP_DIR/timeout.log"
	for pid in "${PIDS[@]}"; do
		if kill "$pid" 2>/dev/null; then
			echo "WATCHDOG_KILL pid=$pid status=0"
		else
			echo "WATCHDOG_KILL pid=$pid status=$?"
		fi
	done
  fi
) &
WATCHDOG_PID=$!

# O quinto cliente só entra depois da rodada estar ACTIVE, para exercitar o
# join tardio. O servidor segura o encerramento até registrá-lo.
wait_for_marker 'ROUND_STATE state=ACTIVE' "$TMP_DIR/server.log" "$SERVER_PID"
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-5" \
  --url="ws://127.0.0.1:$PORT" --round-test=true >"$TMP_DIR/client-5.log" 2>&1 &
PIDS+=("$!")
PROCESS_NAMES+=("client-5")

for index in "${!PIDS[@]}"; do
	pid="${PIDS[$index]}"
	name="${PROCESS_NAMES[$index]}"
	if wait "$pid"; then
		process_status=0
	else
		process_status=$?
	fi
	echo "PROCESS_STATUS name=$name pid=$pid status=$process_status"
	PROCESS_STATUSES+=("$process_status")
done
for index in "${!PROCESS_STATUSES[@]}"; do
	assert_equal "process-${PROCESS_NAMES[$index]}-exit" "${PROCESS_STATUSES[$index]}" "0"
done
TEST_FINISHED=true
if kill "$WATCHDOG_PID" 2>/dev/null; then
	watchdog_kill_status=0
else
	watchdog_kill_status=$?
fi
echo "WATCHDOG_KILL status=$watchdog_kill_status"
if wait "$WATCHDOG_PID" 2>/dev/null; then
	watchdog_status=0
else
	watchdog_status=$?
fi
echo "WATCHDOG_STATUS status=$watchdog_status expected=143"
if [[ "$watchdog_status" == 0 || "$watchdog_status" == 143 ]]; then
	check_ok "watchdog-exit"
else
	check_failed "watchdog-exit" "expected 0 or 143, actual=$watchdog_status"
fi
WATCHDOG_PID=""
if [[ ! -f "$TMP_DIR/timeout.log" ]]; then
	check_ok "watchdog-timeout-absent"
else
	check_failed "watchdog-timeout-absent" "timeout.log exists"
fi

# --- Lobby e máquina de estados ----------------------------------------------
assert_equal "five-client-joins" "$(grep -c 'CLIENT_JOINED id=client-' "$TMP_DIR/server.log")" "5"
assert_equal "five-unique-join-peers" "$(sed -n 's/.*CLIENT_JOINED.*peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" "5"
assert_grep "countdown-started" 'ROUND_STATE state=COUNTDOWN round_id=1 players=4 participants=0' "$TMP_DIR/server.log"
assert_grep "round-active-with-four-participants" 'ROUND_STATE state=ACTIVE round_id=1 players=4 participants=4' "$TMP_DIR/server.log"
assert_no_grep "no-second-round-started" 'ROUND_STATE state=(COUNTDOWN|ACTIVE) round_id=[2-9]' "$TMP_DIR/server.log"
assert_no_grep "no-invalid-transition" 'ROUND_TRANSITION_REJECTED' "$TMP_DIR/server.log"

# --- Distribuição agregada dos papéis ----------------------------------------
assert_grep "aggregated-role-counts" 'ROLE_PRIVACY_TEST_OK clients=4 assassin=1 detective=1 victim=2' "$TMP_DIR/server.log"
assert_grep "four-private-role-deliveries" 'ROUND_ROLES_DELIVERED round_id=1 peers=4' "$TMP_DIR/server.log"
assert_equal "one-role-delivery-batch" "$(grep -c 'ROUND_ROLES_DELIVERED' "$TMP_DIR/server.log")" "1"
assert_equal "four-role-acknowledgements" "$(grep -c 'CLIENT_PRIVATE_ROLE_ACK peer_id=' "$TMP_DIR/server.log")" "4"
assert_equal "four-unique-acknowledging-peers" "$(sed -n 's/.*CLIENT_PRIVATE_ROLE_ACK peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" "4"

# --- Sigilo: cada cliente recebe exatamente um papel, e só o seu -------------
for id in 1 2 3 4; do
	assert_equal "client-$id-single-private-role" "$(grep -c "CLIENT_PRIVATE_ROLE_RECEIVED id=client-$id count=" "$TMP_DIR/client-$id.log")" "1"
	assert_grep "client-$id-first-role-receipt" "CLIENT_PRIVATE_ROLE_RECEIVED id=client-$id count=1" "$TMP_DIR/client-$id.log"
	assert_no_grep "client-$id-no-second-role" "CLIENT_PRIVATE_ROLE_RECEIVED id=client-$id count=[2-9]" "$TMP_DIR/client-$id.log"
	assert_equal "client-$id-only-own-role-marker" "$(grep -c 'CLIENT_PRIVATE_ROLE_RECEIVED' "$TMP_DIR/client-$id.log")" "1"
done
# Nenhum nome de papel pode aparecer em log de cliente. Nesta rodada o
# assassino é eliminado pelo servidor, portanto o time vencedor é INNOCENTS e
# nunca colide com estes três tokens.
assert_no_grep "client-logs-carry-no-role-names" '(ASSASSIN|DETECTIVE|VICTIM)' "$TMP_DIR"/client-*.log
assert_no_grep "server-log-carries-no-role-names" '(ASSASSIN|DETECTIVE|VICTIM)' "$TMP_DIR/server.log"
assert_no_grep "no-peer-to-role-association" 'peer_id=[0-9]+.*role=' "$TMP_DIR"/*.log
assert_no_grep "no-role-field-in-broadcast-payloads" 'CLIENT_ROSTER_REJECTED' "$TMP_DIR"/client-*.log
assert_grep "clients-received-public-state" 'CLIENT_ROUND_STATE id=client-1 state=ACTIVE' "$TMP_DIR/client-1.log"

# --- Tentativas de burlar o sigilo -------------------------------------------
# `target` diferente de zero prova que o roster público chegou e que a sonda
# endereçou um peer real, e não um alvo vazio.
assert_grep "role-spoof-attempted" 'CLIENT_ROLE_SPOOF_ATTEMPTED id=client-1 target=[1-9][0-9]*' "$TMP_DIR/client-1.log"
assert_no_grep "role-spoof-never-delivered" 'ROLE_SPOOF_REJECTED' "$TMP_DIR"/client-*.log
assert_grep "stale-ack-attempted" 'CLIENT_STALE_ACK_ATTEMPTED id=client-2' "$TMP_DIR/client-2.log"
assert_grep "stale-ack-rejected" 'ROUND_ACK_REJECTED peer_id=[0-9]+ reason=stale_round' "$TMP_DIR/server.log"

# --- Join tardio --------------------------------------------------------------
assert_grep "late-join-registered" 'ROUND_LATE_JOIN peer_id=[0-9]+ round_id=1 count=1' "$TMP_DIR/server.log"
assert_grep "late-join-total" 'ROUND_LATE_JOIN_TOTAL count=1 participants=4' "$TMP_DIR/server.log"
assert_no_grep "late-join-received-no-role" 'CLIENT_PRIVATE_ROLE_RECEIVED' "$TMP_DIR/client-5.log"
assert_grep "late-join-sees-active-round" 'CLIENT_ROUND_STATE id=client-5 state=ACTIVE' "$TMP_DIR/client-5.log"
assert_equal "headless-clients-have-no-ui" "$(grep -hc 'CLIENT_UI id=client-[0-9] hud=false arena=false display=headless' "$TMP_DIR"/client-*.log | tr -d ' ' | paste -sd, -)" "1,1,1,1,1"

# Aparência cosmética pública (protocolo 7): o servidor atribui na entrada; todo
# cliente, inclusive o que entrou tarde, vê o mesmo mapa, com variantes
# distintas, e nenhum par jogador:aparência diverge do servidor.
SERVER_APPEARANCES="$(sed -n 's/.*SERVER_APPEARANCE peer_id=\([0-9][0-9]*\) appearance=\([a-z][a-z]*\).*/\1:\2/p' "$TMP_DIR/server.log" | sort)"
assert_equal "five-server-appearances" "$(wc -l <<<"$SERVER_APPEARANCES" | tr -d ' ')" "5"
assert_equal "server-appearances-distinct" "$(cut -d: -f2 <<<"$SERVER_APPEARANCES" | sort -u | wc -l | tr -d ' ')" "5"
for id in 1 2 3 4 5; do
  CLIENT_MAPS="$(sed -n "s/.*CLIENT_ROSTER_APPEARANCES id=client-$id map=//p" "$TMP_DIR/client-$id.log")"
  FULL_SEEN=0
  while IFS= read -r map_line; do
    [[ -n "$map_line" ]] || continue
    SORTED="$(tr ',' '\n' <<<"$map_line" | sort)"
    [[ "$SORTED" == "$SERVER_APPEARANCES" ]] && FULL_SEEN=1
    UNKNOWN="$(comm -23 <(echo "$SORTED") <(echo "$SERVER_APPEARANCES") | wc -l | tr -d ' ')"
    [[ "$UNKNOWN" == "0" ]] || { echo "ASSERT_FAILED name=client-$id-appearance-diverges map=$map_line" >&2; exit 1; }
  done <<<"$CLIENT_MAPS"
  assert_equal "client-$id-saw-full-appearance-map" "$FULL_SEEN" "1"
done

# --- Vitória avaliada no servidor --------------------------------------------
assert_grep "server-evaluated-round-result" 'ROUND_RESULT round_id=1 team=INNOCENTS reason=assassin_down' "$TMP_DIR/server.log"
assert_grep "duplicate-elimination-rejected" 'ROUND_TEST_ELIMINATION accepted=true repeated_rejected=true' "$TMP_DIR/server.log"
assert_equal "public-result-reached-every-client" "$(grep -h 'CLIENT_ROUND_RESULT .* team=INNOCENTS reason=assassin_down' "$TMP_DIR"/client-*.log | wc -l | tr -d ' ')" "5"
assert_equal "public-result-announced-once-per-client" "$(grep -h 'CLIENT_ROUND_RESULT' "$TMP_DIR"/client-*.log | wc -l | tr -d ' ')" "5"

# --- Encerramento em duas fases ----------------------------------------------
assert_grep "server-shutdown-ready" 'SERVER_SHUTDOWN_READY clients=5' "$TMP_DIR/server.log"
assert_grep "server-shutdown-complete" 'SERVER_SHUTDOWN_COMPLETE closed=5' "$TMP_DIR/server.log"
assert_no_grep "server-shutdown-timeout-absent" 'SERVER_SHUTDOWN_TIMEOUT' "$TMP_DIR"/*.log
assert_no_grep "websocket-open-state-errors-absent" 'ready_state != STATE_OPEN' "$TMP_DIR"/*.log
for id in 1 2 3 4 5; do
	assert_equal "client-$id-single-shutdown-prepare" "$(grep -c "CLIENT_SHUTDOWN_PREPARE id=client-$id" "$TMP_DIR/client-$id.log")" "1"
	assert_equal "client-$id-single-shutdown-complete" "$(grep -c "CLIENT_SHUTDOWN_COMPLETE id=client-$id" "$TMP_DIR/client-$id.log")" "1"
done

echo "FINAL_CHECKS status=0"
echo "ROUND_NETWORK_OK server=1 clients=5 participants=4 late=1"
