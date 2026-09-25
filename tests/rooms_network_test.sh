#!/usr/bin/env bash
set -Eeuo pipefail

# Fase 9: teste multiprocesso de salas online. Um servidor com salas e
# clientes Godot reais (headless):
#   sala A: 4 clientes, PRONTO automático, 2 rodadas completas (contagem,
#           partida, eliminações, fim, resultado, volta ao lobby);
#   sala B: 4 clientes, 3 prontos e um que entra depois (durante a rodada de
#           A) sem marcar PRONTO: a sala fica no lobby o tempo todo;
#   sala C: o anfitrião cai, o posto passa para o próximo e alguém entra
#           depois pelo código;
#   recusas: código inválido, código inexistente, rodada em andamento, nome
#           repetido na sala.
# Prova que estado e mensagens não se misturam entre salas: cada peer que um
# cliente vê em qualquer mensagem é da própria sala.

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
start_client() {
  local name="$1"; shift
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="$name" --url="$URL" "$@" \
    >"$TMP_DIR/$name.log" 2>&1 &
  PIDS+=("$!")
  PROCESS_NAMES+=("$name")
  LAST_PID="$!"
}
code_of() {
  sed -n "s/.*ROOM_JOINED id=$1 code=\([A-Z0-9]*\).*/\1/p" "$TMP_DIR/$1.log" | head -n1
}

# --- Servidor ----------------------------------------------------------------
# Rodadas curtas para o teste (a contagem real de 10 s é coberta pelo teste
# unitário); o intervalo entre eliminações deixa a rodada de A durar o
# bastante para os clientes que chegam no meio dela.
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --rooms=true --rooms-test=true --countdown-seconds=2 --round-end-delay-seconds=2 \
  --rooms-target-rounds=2 --rooms-expect-peers=10 --rooms-step-gap-msec=2500 \
  >"$TMP_DIR/server.log" 2>&1 &
SERVER_PID="$!"
PIDS+=("$SERVER_PID")
PROCESS_NAMES+=("server")
wait_for_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"
assert_grep "rooms-enabled" 'ROOMS_ENABLED max_rooms=12 room_capacity=8' "$TMP_DIR/server.log"

(
  sleep 150
  echo "Timed out waiting for rooms network test" >"$TMP_DIR/timeout.log"
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
) &
WATCHDOG_PID=$!

# Salas criadas em ordem (ids 1, 2, 3).
start_client A1 --room-action=create --auto-ready-rounds=2 --auto-ready-min-players=4
wait_for_marker 'ROOM_JOINED id=A1 code=' "$TMP_DIR/A1.log" "$LAST_PID"
CODE_A="$(code_of A1)"
start_client B1 --room-action=create --auto-ready-rounds=1 --auto-ready-min-players=1
wait_for_marker 'ROOM_JOINED id=B1 code=' "$TMP_DIR/B1.log" "$LAST_PID"
CODE_B="$(code_of B1)"
start_client C1 --room-action=create
C1_PID="$LAST_PID"
wait_for_marker 'ROOM_JOINED id=C1 code=' "$TMP_DIR/C1.log" "$C1_PID"
CODE_C="$(code_of C1)"
echo "ROOM_CODES A=$CODE_A B=$CODE_B C=$CODE_C"
assert_equal "three-distinct-codes" "$(printf '%s\n' "$CODE_A" "$CODE_B" "$CODE_C" | sort -u | wc -l | tr -d ' ')" "3"

# Código digitado em minúsculas e com hífen: o servidor normaliza.
typed_a="$(echo "${CODE_A:0:3}-${CODE_A:3:3}" | tr 'A-Z' 'a-z')"
start_client A2 --room-action=join --room-code="$typed_a" --auto-ready-rounds=2 --auto-ready-min-players=4
start_client A3 --room-action=join --room-code="$CODE_A" --auto-ready-rounds=2 --auto-ready-min-players=4
start_client B2 --room-action=join --room-code="$CODE_B" --auto-ready-rounds=1 --auto-ready-min-players=1
start_client B3 --room-action=join --room-code="$CODE_B" --auto-ready-rounds=1 --auto-ready-min-players=1
start_client C2 --room-action=join --room-code="$CODE_C"
C2_PID="$LAST_PID"
wait_for_marker 'CLIENT_JOINED id=A3 ' "$TMP_DIR/server.log" "$SERVER_PID"
wait_for_marker 'CLIENT_JOINED id=A2 ' "$TMP_DIR/server.log" "$SERVER_PID"
# A com 3 de 4: B e A seguem no lobby. O quarto de A dispara a contagem.
start_client A4 --room-action=join --room-code="$CODE_A" --auto-ready-rounds=2 --auto-ready-min-players=4

# Recusas antes da rodada: código inválido, inexistente, nome repetido.
start_client E-invalid --room-action=join --room-code="O0I1-XY" --exit-on-room-error=true
missing="ZZZZZ2"
for code in "$CODE_A" "$CODE_B" "$CODE_C"; do
  [[ "$code" == "$missing" ]] && missing="ZZZZZ3"
done
start_client E-missing --room-action=join --room-code="$missing" --exit-on-room-error=true
wait_for_marker 'CLIENT_JOINED id=B2 ' "$TMP_DIR/server.log" "$SERVER_PID"
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id=B2 --url="$URL" \
  --room-action=join --room-code="$CODE_B" --exit-on-room-error=true >"$TMP_DIR/E-dupname.log" 2>&1 &
PIDS+=("$!"); PROCESS_NAMES+=("E-dupname")

# Sala C: o anfitrião cai depois que C2 entrou.
wait_for_marker 'CLIENT_ROOM_STATE id=C2 .*players=2' "$TMP_DIR/C2.log" "$C2_PID"
kill "$C1_PID"
wait_for_marker 'ROOM_HOST room=3 ' "$TMP_DIR/server.log" "$SERVER_PID"

# Rodada de A em andamento: B4 entra em B, C3 entra em C, e um intruso tenta A.
wait_for_marker 'ROUND_STATE state=ACTIVE round_id=1 players=4 participants=4 room=1' "$TMP_DIR/server.log" "$SERVER_PID"
start_client E-inprogress --room-action=join --room-code="$CODE_A" --exit-on-room-error=true
start_client B4 --room-action=join --room-code="$CODE_B"
start_client C3 --room-action=join --room-code="$CODE_C"

# --- Espera: o servidor encerra sozinho quando as metas são cumpridas ---------
statuses=()
for index in "${!PIDS[@]}"; do
  pid="${PIDS[$index]}"
  if wait "$pid"; then status=0; else status=$?; fi
  echo "PROCESS_STATUS name=${PROCESS_NAMES[$index]} pid=$pid status=$status"
  statuses+=("$status")
done
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
WATCHDOG_PID=""
if [[ -f "$TMP_DIR/timeout.log" ]]; then
  check_failed "no-timeout" "watchdog fired"
else
  check_ok "no-timeout"
fi
for index in "${!statuses[@]}"; do
  name="${PROCESS_NAMES[$index]}"
  [[ "$name" == "C1" ]] && continue
  assert_equal "exit-$name" "${statuses[$index]}" "0"
done

S="$TMP_DIR/server.log"
# --- Servidor ----------------------------------------------------------------
assert_grep "coordinator-ok" 'ROOMS_TEST_OK rooms=3 peers=10 completed=2 failures=0' "$S"
assert_no_grep "coordinator-no-failure" 'ROOMS_TEST_FAILED' "$S"
assert_grep "shutdown-complete" 'SERVER_SHUTDOWN_COMPLETE closed=10' "$S"
assert_equal "three-rooms-created" "$(grep -c 'ROOM_CREATED room=' "$S")" "3"
assert_grep "room-a-countdown" 'ROUND_STATE state=COUNTDOWN round_id=1 players=4 participants=0 room=1' "$S"
assert_grep "room-a-round-1-active" 'ROUND_STATE state=ACTIVE round_id=1 players=4 participants=4 room=1' "$S"
assert_grep "room-a-round-2-active" 'ROUND_STATE state=ACTIVE round_id=2 players=4 participants=4 room=1' "$S"
assert_no_grep "room-a-no-third-round" 'ROUND_STATE state=(COUNTDOWN|ACTIVE) round_id=3 .*room=1' "$S"
assert_grep "room-a-round-1-done" 'ROOMS_TEST_ROUND_DONE room=1 round_id=1 completed=1 ready=0 players=4 result=true' "$S"
assert_grep "room-a-round-2-done" 'ROOMS_TEST_ROUND_DONE room=1 round_id=2 completed=2 ready=0 players=4 result=true' "$S"
assert_no_grep "room-b-never-counts-down" 'ROUND_STATE state=(COUNTDOWN|ACTIVE|ENDED).*room=2' "$S"
assert_no_grep "room-c-never-counts-down" 'ROUND_STATE state=(COUNTDOWN|ACTIVE|ENDED).*room=3' "$S"
assert_grep "room-b-final" 'ROOMS_TEST_ROOM room=2 code=[A-Z0-9]{6} phase=lobby round_id=0 players=4 ready=3 .*bodies=0' "$S"
assert_grep "room-c-final" 'ROOMS_TEST_ROOM room=3 code=[A-Z0-9]{6} phase=lobby round_id=0 players=2 ready=0 .*bodies=0' "$S"
assert_grep "room-a-final" 'ROOMS_TEST_ROOM room=1 code=[A-Z0-9]{6} phase=lobby round_id=2 players=4 ready=0 ' "$S"
assert_grep "refused-invalid-code" 'ROOM_REFUSED peer_id=[0-9]+ action=join reason=invalid_code' "$S"
assert_grep "refused-missing-room" 'ROOM_REFUSED peer_id=[0-9]+ action=join reason=room_not_found' "$S"
assert_grep "refused-in-progress" 'ROOM_REFUSED peer_id=[0-9]+ action=join reason=round_in_progress' "$S"
assert_grep "refused-name-taken" 'ROOM_REFUSED peer_id=[0-9]+ action=join reason=name_taken' "$S"
assert_grep "client-invalid-code" 'ROOM_ERROR id=E-invalid reason=invalid_code' "$TMP_DIR/E-invalid.log"
assert_grep "client-missing-room" 'ROOM_ERROR id=E-missing reason=room_not_found' "$TMP_DIR/E-missing.log"
assert_grep "client-in-progress" 'ROOM_ERROR id=E-inprogress reason=round_in_progress' "$TMP_DIR/E-inprogress.log"
assert_grep "client-name-taken" 'ROOM_ERROR id=B2 reason=name_taken' "$TMP_DIR/E-dupname.log"
for file in E-invalid E-missing E-inprogress E-dupname; do
  assert_no_grep "$file-never-in-room" 'ROOM_JOINED|CLIENT_ROOM_STATE|CLIENT_SEEN_PEER|CLIENT_ROUND_STATE' "$TMP_DIR/$file.log"
done

# Anfitrião: C1 criou, caiu; o posto passou para C2 (o próximo por ordem de entrada).
c2_peer="$(sed -n 's/.*CLIENT_JOINED id=C2 peer_id=\([0-9]*\).*/\1/p' "$S" | head -n1)"
c1_peer="$(sed -n 's/.*CLIENT_JOINED id=C1 peer_id=\([0-9]*\).*/\1/p' "$S" | head -n1)"
assert_grep "host-transferred" "ROOM_HOST room=3 host=$c2_peer previous=$c1_peer" "$S"
assert_grep "late-join-after-host-left" 'CLIENT_JOINED id=C3 peer_id=[0-9]+ count=2 room=3' "$S"
assert_grep "late-join-b4" 'CLIENT_JOINED id=B4 peer_id=[0-9]+ count=4 room=2' "$S"
assert_grep "room-c-host-flag" "CLIENT_ROOM_STATE id=C3 .*players=2" "$TMP_DIR/C3.log"

# --- Isolamento: peer -> sala oficial (log do servidor) ----------------------
declare -A PEER_ROOM
while read -r peer room; do
  PEER_ROOM[$peer]=$room
done < <(sed -n 's/.*CLIENT_JOINED id=[^ ]* peer_id=\([0-9]*\) count=[0-9]* room=\([0-9]*\).*/\1 \2/p' "$S")
assert_equal "eleven-room-joins" "${#PEER_ROOM[@]}" "11"

check_client_isolation() {
  local name="$1" room="$2" code="$3" labels_re="$4"
  local log="$TMP_DIR/$name.log" bad=0 seen=0
  while read -r peer; do
    seen=$((seen + 1))
    if [[ "${PEER_ROOM[$peer]:-none}" != "$room" ]]; then
      echo "FOREIGN_PEER client=$name peer=$peer room=${PEER_ROOM[$peer]:-none}" >&2
      bad=$((bad + 1))
    fi
  done < <(sed -n 's/.*CLIENT_SEEN_PEER id=[^ ]* peer=\([0-9]*\) via=.*/\1/p' "$log" | sort -u)
  assert_equal "$name-sees-only-own-room-peers" "$bad" "0"
  if [[ "$seen" -gt 0 ]]; then check_ok "$name-saw-peers"; else check_failed "$name-saw-peers" "none"; fi
  assert_equal "$name-only-own-code" "$(sed -n 's/.*CLIENT_ROOM_STATE id=[^ ]* code=\([^ ]*\) .*/\1/p' "$log" | sort -u | tr '\n' ' ')" "$code "
  local foreign
  foreign="$(sed -n 's/.*CLIENT_ROOM_STATE .* labels=\([^ ]*\) .*/\1/p' "$log" | tr ',' '\n' | grep -vE "^($labels_re)$" | sort -u | tr '\n' ' ' || true)"
  assert_equal "$name-only-own-labels" "$foreign" ""
}
for n in A1 A2 A3 A4; do check_client_isolation "$n" 1 "$CODE_A" "A1|A2|A3|A4"; done
for n in B1 B2 B3 B4; do check_client_isolation "$n" 2 "$CODE_B" "B1|B2|B3|B4"; done
for n in C2 C3; do check_client_isolation "$n" 3 "$CODE_C" "C1|C2|C3"; done

# Sala A jogou; B e C nunca receberam nada da rodada de A.
for n in A1 A2 A3 A4; do
  assert_grep "$n-countdown" "CLIENT_ROOM_STATE id=$n code=$CODE_A phase=countdown round_id=1 " "$TMP_DIR/$n.log"
  assert_grep "$n-played-round-2" "CLIENT_ROOM_STATE id=$n code=$CODE_A phase=playing round_id=2 " "$TMP_DIR/$n.log"
  assert_grep "$n-results" "CLIENT_ROOM_STATE id=$n code=$CODE_A phase=results round_id=2 .*result=true" "$TMP_DIR/$n.log"
  assert_grep "$n-back-to-lobby" "CLIENT_ROOM_STATE id=$n code=$CODE_A phase=lobby round_id=2 players=4 ready=0 .*result=true" "$TMP_DIR/$n.log"
  assert_equal "$n-two-private-roles" "$(grep -c 'CLIENT_PRIVATE_ROLE_RECEIVED' "$TMP_DIR/$n.log")" "2"
  assert_equal "$n-auto-ready-twice" "$(grep -c "ROOM_AUTO_READY id=$n " "$TMP_DIR/$n.log")" "2"
done
for n in B1 B2 B3 B4 C2 C3; do
  log="$TMP_DIR/$n.log"
  assert_no_grep "$n-no-round" 'phase=(countdown|playing|results)|round_id=[1-9]|result=true' <(grep 'CLIENT_ROOM_STATE' "$log")
  assert_no_grep "$n-no-private-role" 'CLIENT_PRIVATE_ROLE_RECEIVED|CLIENT_ROUND_RESULT|CLIENT_BODY_SHOWN|via=(elimination|reveal|body|spectator)' "$log"
  assert_no_grep "$n-no-role-names" 'ASSASSIN|DETECTIVE|VICTIM' "$log"
done
assert_grep "b4-sees-three-ready" 'CLIENT_ROOM_STATE id=B4 .*players=4 ready=3 ' "$TMP_DIR/B4.log"

if [[ "$FAILED" -gt 0 ]]; then
  echo "ROOMS_NETWORK_TEST_FAILED failures=$FAILED" >&2
  dump_logs
  exit 1
fi
echo "ROOMS_NETWORK_TEST_OK"
