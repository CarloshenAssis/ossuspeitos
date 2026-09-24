#!/usr/bin/env bash
# Fase 5, casos adversos. Cada caso roda numa sessão própria (servidor e
# clientes reais) e tem expectativa de saída explícita por processo: 0 por
# padrão, 1 só para o cliente cuja entrada deve ser recusada (com o motivo no
# log) e 137 só para o processo que o próprio harness derrubou com kill -9.
# Nenhum outro status é aceito, nem 143 genérico.
#
# Uso: [CASES="ninth join_ended ..."] [SEED=1] [TEST_LOG_DIR=...] tests/adverse_cases_test.sh
# Casos de sessão: ninth join_ended drop_moving observed_leaves leave_rejoin
#                  invalid_actions phase4_delay
# Casos de processo: menu_errors version_and_crash busy_port double_click
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 2>/dev/null || command -v godot 2>/dev/null || true)}"
SEED="${SEED:-1}"
CASES="${CASES:-menu_errors protocol_mismatch version_and_crash busy_port double_click ninth join_ended drop_moving observed_leaves leave_rejoin invalid_actions phase4_delay protocol_bodies}"
BASE_PORT="${TEST_PORT:-$((30080 + RANDOM % 1000))}"
SHA="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
RUN_ID="adverse-s$SEED-$SHA-$$"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE_TMP_DIR=false
else TMP_DIR="$(mktemp -d)"; REMOVE_TMP_DIR=true; fi
ALL_PIDS=(); WATCHDOG_PID=""; OCCUPIER_PID=""

cleanup() {
  local status=$?
  trap - EXIT
  [[ -z "$WATCHDOG_PID" ]] || kill "$WATCHDOG_PID" 2>/dev/null || true
  [[ -z "$OCCUPIER_PID" ]] || kill "$OCCUPIER_PID" 2>/dev/null || true
  for pid in "${ALL_PIDS[@]:-}"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  for pid in "${ALL_PIDS[@]:-}"; do [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true; done
  [[ "$REMOVE_TMP_DIR" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fail() {
  local status="${1:-1}"
  echo "ADVERSE_HARNESS_ERROR status=$status case=${CASE:-none} run=$RUN_ID logs=$TMP_DIR" >&2
  for log in "${CASE_DIR:-$TMP_DIR}"/*.log; do [[ ! -f "$log" ]] || { echo "===== $log (tail) =====" >&2; tail -n 50 "$log" >&2; }; done
  exit "$status"
}
trap 'fail $?' ERR
ok() { echo "ASSERT_OK case=${CASE:-none} name=$1"; }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || { echo "ASSERT_FAILED case=$CASE name=$n expected_pattern=$p files=$*" >&2; return 1; }; }
assert_no_grep() { local n=$1 p=$2; shift 2; if grep -qE -- "$p" "$@"; then echo "ASSERT_FAILED case=$CASE name=$n forbidden=$p observed=$(grep -hE -- "$p" "$@" | head -1)" >&2; return 1; else ok "$n"; fi; }
assert_equal() { [[ "$2" == "$3" ]] && ok "$1" || { echo "ASSERT_FAILED case=$CASE name=$1 expected=$3 observed=$2" >&2; return 1; }; }
wait_marker() { local p=$1 f=$2 pid=$3; for _ in {1..600}; do grep -qE -- "$p" "$f" 2>/dev/null && return 0; kill -0 "$pid" 2>/dev/null || { grep -qE -- "$p" "$f" 2>/dev/null && return 0; return 1; }; sleep 0.05; done; return 1; }
stage() { echo "HARNESS_STAGE case=${CASE:-none} $1 run=$RUN_ID t=$(date +%s)"; }
status_of() { if wait "$1"; then LAST_STATUS=0; else LAST_STATUS=$?; fi; }
port_free() { python3 - "$1" <<'PY'
import socket, sys
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.close()
PY
}
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Godot 4 not found. Set GODOT_BIN." >&2; exit 127; }
# Salvaguarda: o `sleep` é filho do watchdog e morre com ele (não segura a
# saída do harness nem sobra como órfão).
(
  trap 'kill "$sleep_pid" 2>/dev/null; exit 0' TERM
  sleep "${ADVERSE_WATCHDOG_SECONDS:-900}" & sleep_pid=$!
  wait "$sleep_pid"
  echo "watchdog run=$RUN_ID" >"$TMP_DIR/timeout.log"; kill -TERM $$ 2>/dev/null
) >/dev/null 2>&1 & WATCHDOG_PID=$!

# --- Casos de sessão (coordenador tests/adverse_coordinator.gd) -----------------------
declare -A CASE_CLIENTS=([protocol_bodies]=4 [ninth]=8 [join_ended]=4 [drop_moving]=5 [observed_leaves]=5 [leave_rejoin]=5 [invalid_actions]=4 [phase4_delay]=4)
declare -A CASE_END_DELAY=([join_ended]=12)
declare -A CASE_PROFILE=([phase4_delay]=rtt150j)
declare -A CASE_REFUSED=([ninth]="client-9" [protocol_bodies]="old-9")
declare -A REFUSAL_REASON=([old-9]=protocol_version)

run_session_case() {
  local port=$1 clients=${CASE_CLIENTS[$CASE]} profile=${CASE_PROFILE[$CASE]:-local}
  local names=() pids=() expected=() handled=0 status name
  declare -A pid_by_label=()
  start_client() {
    local label=$1 log_name=$1 net_args=() protocol_args=()
    [[ -z "${2:-}" ]] || protocol_args=(--test-protocol-version="$2")
    if [[ -n "${pid_by_label[$label]:-}" ]] && kill -0 "${pid_by_label[$label]}" 2>/dev/null; then log_name="$label-duplicate"
    elif [[ -f "$CASE_DIR/$label.log" ]]; then log_name="$label-rejoin"; fi
    if [[ "$profile" != local ]]; then net_args=(--test-net-profile="$profile" --test-net-seed="$((SEED * 100 + ${#pids[@]}))"); fi
    "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="$label" --url="ws://127.0.0.1:$port" \
      --adverse-test=true "${net_args[@]}" "${protocol_args[@]}" >"$CASE_DIR/$log_name.log" 2>&1 &
    local pid=$!
    ALL_PIDS+=("$pid"); pids+=("$pid"); names+=("$log_name")
    # Nome já em uso por um processo vivo, ou recusa prevista pelo caso: status 1.
    if [[ -n "${pid_by_label[$label]:-}" ]] && kill -0 "${pid_by_label[$label]}" 2>/dev/null; then expected+=(1)
    elif [[ " ${CASE_REFUSED[$CASE]:-} " == *" $label "* ]]; then expected+=(1)
    else expected+=(0); pid_by_label[$label]=$pid; fi
    echo "HARNESS_CLIENT_STARTED case=$CASE name=$log_name pid=$pid expected_status=${expected[-1]}"
  }
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$port" \
    --countdown-seconds=3 --round-end-delay-seconds="${CASE_END_DELAY[$CASE]:-3}" --round-seed="$SEED" \
    --adverse-test=true --adverse-case="$CASE" --campaign-clients="$clients" --sync-profile="$profile" >"$CASE_DIR/server.log" 2>&1 &
  local server_pid=$!
  ALL_PIDS+=("$server_pid")
  wait_marker 'SERVER_READY' "$CASE_DIR/server.log" "$server_pid"
  for id in $(seq 1 "$clients"); do start_client "client-$id"; done
  stage "clients_started count=$clients profile=$profile"
  # Atende os pedidos do servidor, em ordem, até ele sair.
  local deadline=$((SECONDS + 240))
  while kill -0 "$server_pid" 2>/dev/null && (( SECONDS < deadline )); do
    mapfile -t requests < <(grep -E '^ADVERSE_REQUEST ' "$CASE_DIR/server.log" || true)
    while (( handled < ${#requests[@]} )); do
      local line="${requests[$handled]}" action label protocol
      action="$(sed -n 's/.*action=\([^ ]*\).*/\1/p' <<<"$line")"; label="$(sed -n 's/.*label=\([^ ]*\).*/\1/p' <<<"$line")"; protocol="$(sed -n 's/.*protocol=\([0-9]*\).*/\1/p' <<<"$line")"
      handled=$((handled + 1))
      case "$action" in
        start_client) start_client "$label" "$protocol" ;;
        kill_client)
          local victim="${pid_by_label[$label]}"
          for i in "${!pids[@]}"; do [[ "${pids[$i]}" != "$victim" ]] || expected[$i]=137; done
          kill -9 "$victim"; unset "pid_by_label[$label]"
          echo "HARNESS_KILLED case=$CASE label=$label pid=$victim signal=KILL" ;;
        *) echo "unknown request $line" >&2; fail 1 ;;
      esac
    done
    sleep 0.1
  done
  if kill -0 "$server_pid" 2>/dev/null; then echo "ASSERT_FAILED case=$CASE name=server-finished-in-time" >&2; fail 1; fi
  status_of "$server_pid"; assert_equal server-exit "$LAST_STATUS" 0
  for i in "${!pids[@]}"; do
    status_of "${pids[$i]}"
    echo "PROCESS_STATUS case=$CASE name=${names[$i]} status=$LAST_STATUS expected=${expected[$i]}"
    assert_equal "process-${names[$i]}-exit" "$LAST_STATUS" "${expected[$i]}"
    if [[ "${expected[$i]}" == 1 ]]; then
      assert_grep "${names[$i]}-refused-with-reason" "JOIN_REJECTED id=[^ ]+ reason=${REFUSAL_REASON[${names[$i]}]:-room_unavailable}" "$CASE_DIR/${names[$i]}.log"
      assert_no_grep "${names[$i]}-never-joined" 'JOIN_ACCEPTED|CLIENT_BODY_SHOWN|CLIENT_PRIVATE_ROLE_RECEIVED' "$CASE_DIR/${names[$i]}.log"
    elif [[ "${expected[$i]}" == 0 ]]; then
      assert_grep "${names[$i]}-coordinated-shutdown" 'CLIENT_SHUTDOWN_COMPLETE' "$CASE_DIR/${names[$i]}.log"
    fi
  done
  for pid in "${pids[@]}" "$server_pid"; do
    if kill -0 "$pid" 2>/dev/null; then echo "ASSERT_FAILED case=$CASE name=no-orphan pid=$pid" >&2; fail 1; fi
  done
  ok no-orphan-processes
  port_free "$port" && ok port-released || { echo "ASSERT_FAILED case=$CASE name=port-released" >&2; fail 1; }
  assert_grep server-case-ok "ADVERSE_SERVER_OK case=$CASE " "$CASE_DIR/server.log"
  assert_no_grep no-runtime-errors 'SCRIPT ERROR|SYNC_TEST_FAILED|Parse Error' "$CASE_DIR"/*.log
  if grep -hE 'ASSASSIN|DETECTIVE|VICTIM' "$CASE_DIR"/client-*.log | grep -vE '^CLIENT_ROUND_RESULT id=[^ ]+ round_id=[0-9]+ team=(ASSASSIN|INNOCENTS) reason=' | grep -q .; then
    echo "ASSERT_FAILED case=$CASE name=no-role-names-in-client-logs" >&2; fail 1
  fi
  ok no-role-names-in-client-logs
  assert_no_grep no-peer-role-association 'peer_id=[0-9]+.*role=' "$CASE_DIR"/*.log
  grep -hE '^(ADVERSE_|CAMPAIGN_STEP_OK|JOIN_REFUSED|CLIENT_LEFT|COMMANDS_REJECTED)' "$CASE_DIR/server.log" | head -60
}

# --- 1. Endereço inválido e servidor indisponível (menu) ---------------------------
case_menu_errors() {
  local port=$1 status
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-exit-on-return=true --menu-auto=join \
    --menu-address=999.1.1.1 --menu-port="$port" >"$CASE_DIR/invalid-address.log" 2>&1 && status=0 || status=$?
  assert_equal invalid-address-exit "$status" 0
  assert_grep invalid-address-message 'MENU_INPUT_INVALID field=address' "$CASE_DIR/invalid-address.log"
  assert_no_grep invalid-address-no-connect 'MENU_CONNECTING|CLIENT_CONNECTING' "$CASE_DIR/invalid-address.log"
  # Sem servidor: volta ao menu com mensagem (recarga real da cena) e não repete.
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-auto=join --menu-address=127.0.0.1 \
    --menu-port="$port" --menu-quit-after-reload=true >"$CASE_DIR/no-server.log" 2>&1 && status=0 || status=$?
  assert_equal no-server-exit "$status" 0
  assert_grep no-server-returned 'MENU_RETURNED reason=(connection_failed|timeout)' "$CASE_DIR/no-server.log"
  assert_grep no-server-message-shown 'MENU_SHOWING_MESSAGE after_return=true' "$CASE_DIR/no-server.log"
  assert_equal no-server-single-attempt "$(grep -c 'CLIENT_CONNECTING' "$CASE_DIR/no-server.log")" 1
  grep -q 'Não foi possível conectar\|Tempo esgotado' "$ROOT/shared/network_app.gd" && ok portuguese-message-source
}

# --- 3 e 9. Versão incompatível, depois queda do servidor com jogadores no menu ------
case_version_and_crash() {
  local port=$1 status
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$port" >"$CASE_DIR/server.log" 2>&1 &
  local server_pid=$!; ALL_PIDS+=("$server_pid")
  wait_marker 'SERVER_READY' "$CASE_DIR/server.log" "$server_pid"
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id=old-build --url="ws://127.0.0.1:$port" \
    --test-protocol-version=8 >"$CASE_DIR/old-build.log" 2>&1 && status=0 || status=$?
  assert_equal old-build-refused-exit "$status" 1
  assert_grep old-build-reason 'JOIN_REJECTED id=old-build reason=protocol_version' "$CASE_DIR/old-build.log"
  assert_grep server-refused-version 'JOIN_REFUSED peer_id=[0-9]+ reason=protocol_version count=0' "$CASE_DIR/server.log"
  local joiners=()
  for id in 1 2; do
    "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-exit-on-return=true --menu-auto=join \
      --menu-name="jogador$id" --menu-address=127.0.0.1 --menu-port="$port" >"$CASE_DIR/joiner-$id.log" 2>&1 &
    joiners+=("$!"); ALL_PIDS+=("$!")
  done
  for id in 1 2; do wait_marker 'JOIN_ACCEPTED' "$CASE_DIR/joiner-$id.log" "${joiners[$((id - 1))]}"; done
  kill -9 "$server_pid"; echo "HARNESS_KILLED case=$CASE name=server pid=$server_pid signal=KILL"
  status_of "$server_pid"; assert_equal crashed-server-exit "$LAST_STATUS" 137
  for id in 1 2; do
    status_of "${joiners[$((id - 1))]}"; assert_equal "joiner-$id-exit" "$LAST_STATUS" 0
    assert_grep "joiner-$id-sees-disconnect" 'CLIENT_SERVER_DISCONNECTED id=' "$CASE_DIR/joiner-$id.log"
    assert_grep "joiner-$id-back-to-menu" 'MENU_RETURNED reason=server_disconnected' "$CASE_DIR/joiner-$id.log"
    assert_equal "joiner-$id-no-retry" "$(grep -c 'CLIENT_CONNECTING' "$CASE_DIR/joiner-$id.log")" 1
  done
  port_free "$port" && ok port-released-after-crash || { echo "ASSERT_FAILED case=$CASE name=port-released" >&2; fail 1; }
}

# --- Protocolo 10: versões diferentes nos dois sentidos, pelo menu ----------------
case_protocol_mismatch() {
  local port=$1 status
  [[ "$(sed -n 's/^const PROTOCOL_VERSION := \([0-9]*\).*/\1/p' "$ROOT/shared/network_config.gd")" == 10 ]] && ok protocol-is-10
  # Servidor 10, cliente 9.
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$port" >"$CASE_DIR/server-10.log" 2>&1 &
  local server_pid=$!; ALL_PIDS+=("$server_pid")
  wait_marker 'SERVER_READY' "$CASE_DIR/server-10.log" "$server_pid"
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-exit-on-return=true --menu-auto=join --menu-name=antigo \
    --menu-address=127.0.0.1 --menu-port="$port" --test-protocol-version=9 >"$CASE_DIR/client-9.log" 2>&1 && status=0 || status=$?
  assert_equal client-9-exit "$status" 0
  assert_grep client-9-announces-9 'CLIENT_PROTOCOL id=antigo version=9' "$CASE_DIR/client-9.log"
  assert_grep client-9-refused 'JOIN_REJECTED id=antigo reason=protocol_version' "$CASE_DIR/client-9.log"
  assert_grep client-9-clear-message 'JOIN_REJECTED_MESSAGE id=antigo text=Versão incompatível do jogo \(este build usa o protocolo 9\)' "$CASE_DIR/client-9.log"
  assert_grep client-9-back-to-menu 'MENU_RETURNED reason=join_rejected' "$CASE_DIR/client-9.log"
  assert_no_grep client-9-no-entry 'JOIN_ACCEPTED|CLIENT_ROUND_STATE|CLIENT_ROSTER|CLIENT_BODY_SHOWN|CLIENT_PRIVATE_ROLE' "$CASE_DIR/client-9.log"
  assert_grep server-10-mismatch 'JOIN_PROTOCOL_MISMATCH peer_id=[0-9]+ client=9 server=10' "$CASE_DIR/server-10.log"
  assert_grep server-10-refused-empty 'JOIN_REFUSED peer_id=[0-9]+ reason=protocol_version count=0' "$CASE_DIR/server-10.log"
  assert_no_grep server-10-no-partial-entry 'CLIENT_JOINED|PLAYER_SPAWNED|ROUND_LATE_JOIN|ROUND_STATE' "$CASE_DIR/server-10.log"
  kill "$server_pid"; status_of "$server_pid"
  # Servidor 9 (build antiga simulada), cliente 10.
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$((port + 1))" --test-protocol-version=9 >"$CASE_DIR/server-9.log" 2>&1 &
  server_pid=$!; ALL_PIDS+=("$server_pid")
  wait_marker 'SERVER_READY' "$CASE_DIR/server-9.log" "$server_pid"
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-exit-on-return=true --menu-auto=join --menu-name=novo \
    --menu-address=127.0.0.1 --menu-port="$((port + 1))" >"$CASE_DIR/client-10.log" 2>&1 && status=0 || status=$?
  assert_equal client-10-exit "$status" 0
  assert_grep client-10-announces-10 'CLIENT_PROTOCOL id=novo version=10' "$CASE_DIR/client-10.log"
  assert_grep client-10-refused 'JOIN_REJECTED id=novo reason=protocol_version' "$CASE_DIR/client-10.log"
  assert_grep client-10-clear-message 'JOIN_REJECTED_MESSAGE id=novo text=Versão incompatível do jogo \(este build usa o protocolo 10\)' "$CASE_DIR/client-10.log"
  assert_no_grep client-10-no-entry 'JOIN_ACCEPTED|CLIENT_ROUND_STATE|CLIENT_ROSTER|CLIENT_BODY_SHOWN' "$CASE_DIR/client-10.log"
  assert_grep server-9-mismatch 'JOIN_PROTOCOL_MISMATCH peer_id=[0-9]+ client=10 server=9' "$CASE_DIR/server-9.log"
  assert_no_grep server-9-no-partial-entry 'CLIENT_JOINED|PLAYER_SPAWNED|ROUND_STATE' "$CASE_DIR/server-9.log"
  kill "$server_pid"; status_of "$server_pid"
}

# --- 2. Porta ocupada: falha clara sem derrubar quem ocupa ---------------------------
case_busy_port() {
  local port=$1 status
  python3 - "$port" >"$CASE_DIR/occupier.log" 2>&1 <<'PY' &
import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(4)
print("OCCUPIER_LISTENING", flush=True)
s.settimeout(60)
conn, _ = s.accept(); conn.sendall(b"alive"); conn.close()
print("OCCUPIER_ANSWERED", flush=True)
time.sleep(60)
PY
  OCCUPIER_PID=$!
  wait_marker 'OCCUPIER_LISTENING' "$CASE_DIR/occupier.log" "$OCCUPIER_PID"
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$port" >"$CASE_DIR/server.log" 2>&1 && status=0 || status=$?
  assert_equal busy-server-exit "$status" 1
  assert_grep busy-server-clear-error 'SERVER_ERROR unable_to_listen' "$CASE_DIR/server.log"
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-exit-on-return=true --menu-auto=host \
    --menu-port="$port" >"$CASE_DIR/menu-host.log" 2>&1 && status=0 || status=$?
  assert_equal busy-menu-exit "$status" 0
  assert_grep busy-menu-clear-error 'MENU_HOST_ERROR reason=port_in_use' "$CASE_DIR/menu-host.log"
  kill -0 "$OCCUPIER_PID" && ok occupier-still-running
  python3 - "$port" <<'PY' && ok occupier-still-serving
import socket, sys
c = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=5); assert c.recv(5) == b"alive"
PY
  kill "$OCCUPIER_PID" 2>/dev/null || true; wait "$OCCUPIER_PID" 2>/dev/null || true; OCCUPIER_PID=""
}

# --- 5. Clique duplo em Entrar e em Criar -------------------------------------------
case_double_click() {
  local port=$1 status
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$port" >"$CASE_DIR/server.log" 2>&1 &
  local server_pid=$!; ALL_PIDS+=("$server_pid")
  wait_marker 'SERVER_READY' "$CASE_DIR/server.log" "$server_pid"
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-exit-on-return=true --menu-auto=join-twice \
    --menu-address=127.0.0.1 --menu-port="$port" --menu-leave-on=joined >"$CASE_DIR/join-twice.log" 2>&1 && status=0 || status=$?
  assert_equal join-twice-exit "$status" 0
  assert_grep join-twice-ignored 'MENU_DUPLICATE_IGNORED action=join' "$CASE_DIR/join-twice.log"
  assert_equal join-twice-one-connection "$(grep -c 'CLIENT_CONNECTING' "$CASE_DIR/join-twice.log")" 1
  assert_no_grep join-twice-no-signal-errors 'already connected' "$CASE_DIR/join-twice.log"
  for _ in {1..40}; do grep -q 'CLIENT_LEFT' "$CASE_DIR/server.log" && break; sleep 0.05; done
  assert_equal server-saw-one-peer "$(grep -c 'PEER_CONNECTED' "$CASE_DIR/server.log")" 1
  kill "$server_pid"; status_of "$server_pid"
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=menu --menu-exit-on-return=true --menu-auto=host-twice \
    --menu-port="$((port + 1))" --menu-leave-on=joined >"$CASE_DIR/host-twice.log" 2>&1 && status=0 || status=$?
  assert_equal host-twice-exit "$status" 0
  assert_equal host-twice-one-server "$(grep -c 'MENU_HOST_SPAWNED' "$CASE_DIR/host-twice.log")" 1
  assert_grep host-twice-server-stopped 'MENU_HOSTED_SERVER_STOPPED pid=[0-9]+ reason=left' "$CASE_DIR/host-twice.log"
}

index=0
for CASE in $CASES; do
  CASE_DIR="$TMP_DIR/$CASE"; mkdir -p "$CASE_DIR"
  port=$((BASE_PORT + index * 3)); index=$((index + 1))
  stage "start port=$port seed=$SEED sha=$SHA"
  started=$SECONDS
  case "$CASE" in
    menu_errors|protocol_mismatch|version_and_crash|busy_port|double_click) "case_$CASE" "$port" ;;
    *) [[ -n "${CASE_CLIENTS[$CASE]:-}" ]] || { echo "unknown case $CASE" >&2; exit 2; }; run_session_case "$port" ;;
  esac
  echo "ADVERSE_CASE_OK case=$CASE seconds=$((SECONDS - started))"
done
CASE=""
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""
[[ ! -f "$TMP_DIR/timeout.log" ]] || fail 1
echo "ADVERSE_CASES_TEST_OK cases=$(wc -w <<<"$CASES") seed=$SEED run=$RUN_ID"
