#!/usr/bin/env bash
set -Eeuo pipefail

# Fase 10: robustez de sala com clientes Godot reais (headless), uma sala:
#   - 8 entram (código em minúsculas com espaços; três quase ao mesmo tempo);
#     o 9º recebe "sala cheia";
#   - um amigo fecha a aba no lobby: os 7 prontos começam sem ele;
#   - na rodada, o anfitrião e outro jogador caem: o posto passa adiante e a
#     rodada termina normalmente; quem caiu reabre e tenta voltar no meio da
#     rodada: "partida em andamento", sem ver nada da rodada;
#   - alguém sai na tela de resultado; na volta ao lobby quem caiu entra de
#     novo com o mesmo nome;
#   - todos saem: a sala vazia é removida; o servidor segue saudável (cria
#     outra sala) e encerra limpo.
# Mensagens de erro vistas pelo jogador ficam em PlayerMessages/RoomRules
# (teste player_messages_test.gd).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  GODOT_BIN="$(command -v godot4 || command -v godot || true)"
fi
PORT="${TEST_PORT:-$((24080 + RANDOM % 1000))}"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then
  TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE_TMP_DIR=false
else
  TMP_DIR="$(mktemp -d)"; REMOVE_TMP_DIR=true
fi
PIDS=()
WATCHDOG_PID=""
FAILED=0
declare -A PID_OF

cleanup() {
  local original_status=$?
  trap - EXIT
  [[ -n "$WATCHDOG_PID" ]] && kill "$WATCHDOG_PID" 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
  [[ "$REMOVE_TMP_DIR" == true ]] && rm -rf "$TMP_DIR"
  return "$original_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

dump_logs() {
  for file in "$TMP_DIR"/*.log; do echo "===== $(basename "$file")" >&2; tail -n 60 "$file" >&2; done
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
    grep -qE -- "$pattern" "$file" 2>/dev/null && return 0
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
# $1 = arquivo de log, $2 = nome do jogador.
start_client() {
  local log="$1" name="$2"; shift 2
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="$name" --url="$URL" \
    --transition-metrics=true "$@" >"$TMP_DIR/$log.log" 2>&1 &
  PIDS+=("$!")
  PID_OF[$log]="$!"
}
peer_of() { sed -n "s/.*CLIENT_JOINED id=$1 peer_id=\([0-9]*\) .*room=1.*/\1/p" "$S" | head -n1; }

S="$TMP_DIR/server.log"
# Contagem e resultado curtos; eliminações espaçadas para caber a queda e a
# tentativa de volta no meio da rodada; carência de sala vazia curta (teste).
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --rooms=true --rooms-test=true --countdown-seconds=2 --round-end-delay-seconds=3 \
  --rooms-target-rounds=99 --rooms-expect-peers=999 --rooms-step-gap-msec=5000 \
  --test-empty-room-grace-msec=1500 --transition-metrics=true >"$S" 2>&1 &
SERVER_PID="$!"
PIDS+=("$SERVER_PID")
wait_for_marker 'SERVER_READY' "$S" "$SERVER_PID"

(
  sleep 150
  echo "Timed out waiting for rooms resilience test" >"$TMP_DIR/timeout.log"
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
) &
WATCHDOG_PID=$!

# PRONTO automático só com os 8 na sala (o 8º pode conectar por último);
# depois que ele sai, os 7 prontos bastam.
READY=(--auto-ready-rounds=1 --auto-ready-min-players=8)
start_client R1 R1 --room-action=create "${READY[@]}"
wait_for_marker 'ROOM_JOINED id=R1 code=' "$TMP_DIR/R1.log" "${PID_OF[R1]}"
CODE="$(sed -n 's/.*ROOM_JOINED id=R1 code=\([A-Z0-9]*\).*/\1/p' "$TMP_DIR/R1.log" | head -n1)"
spaced="$(echo " ${CODE:0:2} ${CODE:2:2} ${CODE:4:2} " | tr 'A-Z' 'a-z')"
start_client R2 R2 --room-action=join --room-code="$spaced" "${READY[@]}"
wait_for_marker 'CLIENT_JOINED id=R2 ' "$S" "$SERVER_PID"
# Três quase juntos.
start_client R3 R3 --room-action=join --room-code="$CODE" "${READY[@]}"
start_client R4 R4 --room-action=join --room-code="$CODE" "${READY[@]}"
start_client R5 R5 --room-action=join --room-code="$CODE" "${READY[@]}"
start_client R6 R6 --room-action=join --room-code="$CODE" "${READY[@]}"
start_client R7 R7 --room-action=join --room-code="$CODE" "${READY[@]}"
# O oitavo nunca marca PRONTO: a sala espera por ele.
start_client R8 R8 --room-action=join --room-code="$CODE"
wait_for_marker 'CLIENT_JOINED id=R[1-8] peer_id=[0-9]+ count=8 room=1' "$S" "$SERVER_PID"
start_client R9 R9 --room-action=join --room-code="$CODE" --exit-on-room-error=true
wait "${PID_OF[R9]}" || true
wait_for_marker 'ROOM_READY room=1 .*ready_count=7 players=8' "$S" "$SERVER_PID"
sleep 1
assert_no_grep "waits-for-eighth" 'ROUND_STATE state=COUNTDOWN round_id=1 ' "$S"

# Amigo fecha a aba no lobby: os 7 prontos começam.
R8_PEER="$(peer_of R8)"
kill "${PID_OF[R8]}"
wait_for_marker "CLIENT_LEFT peer_id=$R8_PEER count=7 room=1" "$S" "$SERVER_PID"
wait_for_marker 'ROUND_STATE state=ACTIVE round_id=1 players=7 participants=7 room=1' "$S" "$SERVER_PID"

# Na rodada: anfitrião e mais um caem.
R1_PEER="$(peer_of R1)"; R7_PEER="$(peer_of R7)"
kill "${PID_OF[R1]}" "${PID_OF[R7]}"
wait_for_marker "CLIENT_LEFT peer_id=$R1_PEER " "$S" "$SERVER_PID"
wait_for_marker "CLIENT_LEFT peer_id=$R7_PEER " "$S" "$SERVER_PID"
# Reabre e tenta voltar com o mesmo nome no meio da rodada (ou no resultado).
start_client R7-reopen-1 R7 --room-action=join --room-code="$CODE" --exit-on-room-error=true
wait "${PID_OF[R7-reopen-1]}" || true

# Tela de resultado: alguém sai.
wait_for_marker 'ROUND_STATE state=ENDED round_id=1 .*room=1' "$S" "$SERVER_PID"
R4_PEER="$(peer_of R4)"
kill "${PID_OF[R4]}"
wait_for_marker "CLIENT_LEFT peer_id=$R4_PEER " "$S" "$SERVER_PID"

# De volta ao lobby: quem caiu entra de novo com o mesmo nome.
wait_for_marker 'ROOMS_TEST_ROUND_DONE room=1 round_id=1 ' "$S" "$SERVER_PID"
start_client R7-reopen-2 R7 --room-action=join --room-code="$CODE"
wait_for_marker 'ROOM_JOINED id=R7 ' "$TMP_DIR/R7-reopen-2.log" "${PID_OF[R7-reopen-2]}"
wait_for_marker 'CLIENT_ROOM_STATE id=R2 .*phase=lobby round_id=1 players=5 ' "$TMP_DIR/R2.log" "${PID_OF[R2]}"

# Todos saem: sala vazia removida depois da carência.
for name in R2 R3 R5 R6 R7-reopen-2; do kill "${PID_OF[$name]}"; done
wait_for_marker 'ROOM_DESTROYED room=1 reason=empty members=0 rooms=0' "$S" "$SERVER_PID"

# Servidor saudável: outra sala funciona.
start_client Z1 Z1 --room-action=create
wait_for_marker 'ROOM_JOINED id=Z1 code=' "$TMP_DIR/Z1.log" "${PID_OF[Z1]}"
assert_grep "new-room-after-cleanup" 'ROOM_CREATED room=2 rooms=1' "$S"
kill "${PID_OF[Z1]}"
wait_for_marker 'ROOM_DESTROYED room=2 reason=empty' "$S" "$SERVER_PID"
if kill -0 "$SERVER_PID" 2>/dev/null; then server_alive=yes; else server_alive=no; fi
kill "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""

# --- Verificações --------------------------------------------------------------
[[ -f "$TMP_DIR/timeout.log" ]] && check_failed "no-timeout" "watchdog fired" || check_ok "no-timeout"
assert_equal "server-alive-after-all-scenarios" "$server_alive" "yes"
assert_grep "spaced-lowercase-code" 'ROOM_JOINED id=R2 code='"$CODE" "$TMP_DIR/R2.log"
for name in R3 R4 R5; do assert_grep "simultaneous-$name" "ROOM_JOINED id=$name code=$CODE" "$TMP_DIR/$name.log"; done
assert_grep "eight-in-room" 'CLIENT_JOINED id=R[1-8] peer_id=[0-9]+ count=8 room=1' "$S"
assert_grep "full-room-refused" 'ROOM_REFUSED peer_id=[0-9]+ action=join reason=room_full' "$S"
assert_grep "full-room-client" 'ROOM_ERROR id=R9 reason=room_full' "$TMP_DIR/R9.log"
assert_no_grep "full-room-never-in" 'ROOM_JOINED|CLIENT_ROOM_STATE|CLIENT_SEEN_PEER' "$TMP_DIR/R9.log"
assert_grep "lobby-leave-starts-round" 'ROUND_STATE state=COUNTDOWN round_id=1 players=7 ' "$S"
R2_PEER="$(peer_of R2)"
assert_grep "host-passed-mid-round" "ROOM_HOST room=1 host=$R2_PEER previous=$R1_PEER" "$S"
assert_grep "round-ended" 'ROUND_STATE state=ENDED round_id=1 .*room=1' "$S"
assert_grep "reopen-mid-round-refused" 'ROOM_ERROR id=R7 reason=round_in_progress' "$TMP_DIR/R7-reopen-1.log"
assert_no_grep "reopen-mid-round-sees-nothing" 'ROOM_JOINED|CLIENT_ROOM_STATE|CLIENT_PRIVATE_ROLE|CLIENT_ROUND_STATE|CLIENT_BODY_SHOWN' "$TMP_DIR/R7-reopen-1.log"
assert_grep "reopen-after-round-joins" "ROOM_JOINED id=R7 code=$CODE" "$TMP_DIR/R7-reopen-2.log"
assert_grep "reopen-after-round-lobby" 'CLIENT_ROOM_STATE id=R7 .*phase=lobby round_id=1 players=5 ' "$TMP_DIR/R7-reopen-2.log"
assert_grep "result-leave-back-to-lobby" 'ROOMS_TEST_ROUND_DONE room=1 round_id=1 completed=1 ready=0 players=[0-9]+ result=true' "$S"
assert_grep "survivor-saw-result" 'CLIENT_ROOM_STATE id=R2 .*phase=lobby round_id=1 .*result=true' "$TMP_DIR/R2.log"
assert_grep "empty-room-removed" 'ROOM_DESTROYED room=1 reason=empty members=0 rooms=0' "$S"
assert_no_grep "coordinator-no-failure" 'ROOMS_TEST_FAILED' "$S"
assert_no_grep "no-script-errors" 'SCRIPT ERROR|Parse Error' "$TMP_DIR"/*.log
# Cinco processos fechados ao mesmo tempo: o socket de um deles pode ainda
# estar OPEN quando o estado da sala sai para os demais e fechar no meio do
# envio. O motor registra "ready_state != STATE_OPEN" (sem efeito: o peer já
# saiu). Mesma tolerância limitada do container_test; qualquer outro ERROR
# do servidor falha.
send_races="$(grep -c 'ready_state != STATE_OPEN' "$S" || true)"
if [[ "$send_races" -le 5 ]]; then check_ok "server-send-races-bounded count=$send_races"; else check_failed "server-send-races-bounded" "count=$send_races"; fi
assert_no_grep "server-no-other-errors" '^ERROR: ' <(grep -v 'ready_state != STATE_OPEN' "$S")

if [[ "$FAILED" -gt 0 ]]; then
  echo "ROOMS_RESILIENCE_TEST_FAILED failures=$FAILED" >&2
  dump_logs
  exit 1
fi
echo "ROOMS_RESILIENCE_TEST_OK"
