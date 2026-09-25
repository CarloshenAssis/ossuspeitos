#!/usr/bin/env bash
set -Eeuo pipefail

# Fase 9: ataques às RPCs de sala com um peer hostil real (WebSocket), e um
# servidor que continua saudável depois deles:
#   antes do handshake, no hall e dentro de uma sala: códigos e nomes
#   malformados, argumentos injetados (room_id, host, ready), PRONTO fora de
#   sala e com tipo errado, criar/entrar duas vezes, RPCs de autoridade
#   forjadas; força bruta de código até a conexão cair.
# Depois, dois clientes legítimos criam e entram numa sala sem ver nada do
# atacante.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot4 >/dev/null; then
    GODOT_BIN="$(command -v godot4)"
  elif command -v godot >/dev/null; then
    GODOT_BIN="$(command -v godot)"
  fi
fi
PORT="${TEST_PORT:-$((24080 + RANDOM % 1000))}"
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
WATCHDOG_PID=""
FAILED=0

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

dump_logs() {
  for file in "$TMP_DIR"/*.log; do
    echo "===== $(basename "$file")" >&2
    cat "$file" >&2
  done
}

report_failure() {
  echo "HARNESS_ERROR line=$2 status=$1 command=$3" >&2
  dump_logs
  exit "$1"
}
trap 'report_failure "$?" "$LINENO" "$BASH_COMMAND"' ERR

check_ok() { echo "ASSERT_OK name=$1"; }
check_failed() { echo "ASSERT_FAILED name=$1 detail=$2" >&2; FAILED=$((FAILED + 1)); }
assert_grep() {
  local name="$1" pattern="$2"; shift 2
  if grep -qE -- "$pattern" "$@"; then check_ok "$name"; else check_failed "$name" "pattern not found: $pattern"; fi
}
assert_no_grep() {
  local name="$1" pattern="$2"; shift 2
  if grep -qE -- "$pattern" "$@"; then check_failed "$name" "forbidden pattern found: $pattern"; else check_ok "$name"; fi
}
assert_equal() {
  if [[ "$2" == "$3" ]]; then check_ok "$1"; else check_failed "$1" "expected=$3 actual=$2"; fi
}

wait_for_marker() {
  local pattern="$1" file="$2" guard_pid="$3"
  for _ in {1..900}; do
    if grep -qE -- "$pattern" "$file" 2>/dev/null; then
      return 0
    fi
    kill -0 "$guard_pid" 2>/dev/null || { echo "WAIT_GUARD_EXITED pattern=$pattern file=$file" >&2; return 1; }
    sleep 0.1
  done
  echo "WAIT_TIMEOUT pattern=$pattern file=$file" >&2
  return 1
}

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Godot 4 not found. Set GODOT_BIN to the executable." >&2
  exit 127
fi

URL="ws://127.0.0.1:$PORT"
S="$TMP_DIR/server.log"
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --rooms=true --rooms-test=true --rooms-target-rounds=0 --rooms-expect-peers=2 \
  >"$S" 2>&1 &
SERVER_PID="$!"
PIDS+=("$SERVER_PID"); PROCESS_NAMES+=("server")
wait_for_marker 'SERVER_READY' "$S" "$SERVER_PID"

(
  sleep 90
  echo "Timed out waiting for rooms adversarial test" >"$TMP_DIR/timeout.log"
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
) &
WATCHDOG_PID=$!

attacker() {
  local name="$1" phase="$2"
  "$GODOT_BIN" --headless --path "$ROOT" --script tests/adversarial_client.gd -- \
    --client-id="$name" --url="$URL" --attack="$phase" --quit-after-msec=5000 >"$TMP_DIR/$name.log" 2>&1
}
attacker attacker-r rooms &
ATTACK_R=$!
attacker attacker-f rooms-flood &
ATTACK_F=$!
if wait "$ATTACK_R"; then r_status=0; else r_status=$?; fi
if wait "$ATTACK_F"; then f_status=0; else f_status=$?; fi
assert_equal "attacker-rooms-exit" "$r_status" "0"
assert_equal "attacker-flood-exit" "$f_status" "0"
kill -0 "$SERVER_PID" 2>/dev/null && check_ok "server-alive-after-attacks" || check_failed "server-alive-after-attacks" "server exited"

# Clientes legítimos depois dos ataques.
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id=N1 --url="$URL" --room-action=create \
  >"$TMP_DIR/N1.log" 2>&1 &
N1_PID=$!; PIDS+=("$N1_PID"); PROCESS_NAMES+=("N1")
wait_for_marker 'ROOM_JOINED id=N1 code=' "$TMP_DIR/N1.log" "$N1_PID"
CODE="$(sed -n 's/.*ROOM_JOINED id=N1 code=\([A-Z0-9]*\).*/\1/p' "$TMP_DIR/N1.log" | head -n1)"
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id=N2 --url="$URL" --room-action=join \
  --room-code="$CODE" >"$TMP_DIR/N2.log" 2>&1 &
PIDS+=("$!"); PROCESS_NAMES+=("N2")

statuses=()
for index in "${!PIDS[@]}"; do
  if wait "${PIDS[$index]}"; then status=0; else status=$?; fi
  echo "PROCESS_STATUS name=${PROCESS_NAMES[$index]} status=$status"
  assert_equal "exit-${PROCESS_NAMES[$index]}" "$status" "0"
done
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
WATCHDOG_PID=""
[[ -f "$TMP_DIR/timeout.log" ]] && check_failed "no-timeout" "watchdog fired" || check_ok "no-timeout"

A="$TMP_DIR/attacker-r.log"
F="$TMP_DIR/attacker-f.log"
r_peer="$(sed -n 's/.*ATTACKER_CONNECTED id=attacker-r peer_id=\([0-9]*\).*/\1/p' "$A")"
f_peer="$(sed -n 's/.*ATTACKER_CONNECTED id=attacker-f peer_id=\([0-9]*\).*/\1/p' "$F")"
echo "ATTACKER_PEERS rooms=$r_peer flood=$f_peer"
# Antes do handshake: nada entra nem é criado.
assert_grep "prehall-create-refused" "ROOM_REFUSED peer_id=$r_peer action=create reason=not_in_room" "$S"
assert_grep "prehall-join-refused" "ROOM_REFUSED peer_id=$r_peer action=join reason=not_in_room" "$S"
assert_grep "prehall-ready-refused" "ROOM_REFUSED peer_id=$r_peer action=ready reason=not_in_room" "$S"
# No hall.
for reason in invalid_code invalid_name already_in_room not_in_room not_ready_phase; do
  assert_grep "attacker-got-$reason" "ATTACKER_ROOM_ERROR id=attacker-r reason=$reason" "$A"
done
assert_no_grep "no-invalid-room-created" "ROOM_REFUSED peer_id=$r_peer action=create reason=(server_full|rooms_unavailable)" "$S"
assert_equal "attacker-created-one-room" "$(grep -c "CLIENT_JOINED id=attacker-r peer_id=$r_peer count=1 room=" "$S")" "1"
assert_grep "attacker-valid-ready-accepted" "ROOM_READY room=[0-9]+ peer_id=$r_peer ready=true ready_count=1 players=1" "$S"
assert_no_grep "attacker-room-never-counted-down" 'ROUND_STATE state=(COUNTDOWN|ACTIVE)' "$S"
# Dentro da sala o atacante também roda os ataques de sessão de sempre
# (join_accepted): um segundo request_join da mesma conexão é recusado.
assert_grep "rejoin-from-room-refused" "JOIN_REFUSED peer_id=$r_peer reason=invalid_client" "$S"
assert_no_grep "room-state-has-no-private-keys" 'role|inventory|health|position|spawn' <(grep 'ATTACKER_ROOM_STATE' "$A")
assert_no_grep "forged-rpcs-had-no-effect" 'ROOM_CREATED room=[0-9]+ rooms=[3-9]' "$S"
# Força bruta: a conexão cai no limite.
assert_grep "flood-limit" "ROOM_JOIN_ATTEMPTS_EXCEEDED peer_id=$f_peer failures=8" "$S"
assert_grep "flood-client-told" 'ATTACKER_ROOM_ERROR id=attacker-f reason=too_many_attempts' "$F"
assert_grep "flood-client-disconnected" 'ATTACKER_SERVER_DISCONNECTED id=attacker-f' "$F"
assert_no_grep "flood-never-in-room" "CLIENT_JOINED id=attacker-f" "$S"
# Log limitado por peer.
assert_equal "refusal-log-capped" "$(grep -c "ROOM_REFUSED peer_id=$f_peer " "$S")" "3"
# Servidor saudável: sala nova, entrada por código, encerramento combinado.
assert_grep "legit-room" 'CLIENT_JOINED id=N2 peer_id=[0-9]+ count=2 room=2' "$S"
assert_grep "coordinator-ok" 'ROOMS_TEST_OK rooms=2 peers=2 completed=0 failures=0' "$S"
assert_grep "shutdown-complete" 'SERVER_SHUTDOWN_COMPLETE closed=2' "$S"
for n in N1 N2; do
  assert_no_grep "$n-never-sees-attacker" "CLIENT_SEEN_PEER id=$n peer=($r_peer|$f_peer) " "$TMP_DIR/$n.log"
  assert_no_grep "$n-no-attacker-label" 'labels=.*attacker' "$TMP_DIR/$n.log"
done
assert_no_grep "no-script-errors" 'SCRIPT ERROR' "$S"

if [[ "$FAILED" -gt 0 ]]; then
  echo "ROOMS_ADVERSARIAL_TEST_FAILED failures=$FAILED" >&2
  dump_logs
  exit 1
fi
echo "ROOMS_ADVERSARIAL_TEST_OK"
