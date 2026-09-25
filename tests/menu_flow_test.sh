#!/usr/bin/env bash
# Fase 7: fluxo de conexão do menu com processos reais. Cada cenário aciona
# os botões reais do menu (automação `--menu-auto`, que só pressiona botões
# visíveis e ativos) e confere o estado por marcadores do próprio jogo. Todo
# processo precisa terminar com 0; nenhum `kill` conta como sucesso.
#
# Uso: [GAME_BIN=godot] [GAME_PATH=.] [TEST_LOG_DIR=...] tests/menu_flow_test.sh
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_BIN="${GAME_BIN:-$(command -v godot4 2>/dev/null || command -v godot 2>/dev/null || true)}"
GAME_PATH="${GAME_PATH-$ROOT}"
PORT="${TEST_PORT:-$((31080 + RANDOM % 1000))}"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE=false
else TMP_DIR="$(mktemp -d)"; REMOVE=true; fi
PIDS=(); WATCHDOG_PID=""
[[ -n "$GAME_BIN" && -x "$GAME_BIN" ]] || { echo "Game executable not found. Set GAME_BIN." >&2; exit 127; }
PATH_ARGS=()
[[ -z "$GAME_PATH" ]] || PATH_ARGS=(--path "$GAME_PATH")

cleanup() {
  local status=$?; trap - EXIT
  [[ -z "$WATCHDOG_PID" ]] || kill "$WATCHDOG_PID" 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true; done
  [[ "$REMOVE" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
fail() { local status="${1:-1}"; echo "MENU_FLOW_HARNESS_ERROR status=$status scene=${SCENE:-none} logs=$TMP_DIR" >&2; for log in "$TMP_DIR"/*.log; do [[ ! -f "$log" ]] || { echo "===== $log (tail) =====" >&2; tail -n 40 "$log" >&2; }; done; exit "$status"; }
trap 'fail $?' ERR
ok() { echo "ASSERT_OK scene=$SCENE name=$1"; }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || { echo "ASSERT_FAILED scene=$SCENE name=$n pattern=$p" >&2; return 1; }; }
assert_no_grep() { local n=$1 p=$2; shift 2; if grep -qE -- "$p" "$@"; then echo "ASSERT_FAILED scene=$SCENE name=$n forbidden=$p observed=$(grep -hE -- "$p" "$@" | head -1)" >&2; return 1; else ok "$n"; fi; }
assert_equal() { [[ "$2" == "$3" ]] && ok "$1" || { echo "ASSERT_FAILED scene=$SCENE name=$1 expected=$3 actual=$2" >&2; return 1; }; }
wait_marker() { local p=$1 f=$2 pid=$3; for _ in {1..600}; do grep -qE -- "$p" "$f" 2>/dev/null && return 0; kill -0 "$pid" 2>/dev/null || { grep -qE -- "$p" "$f" 2>/dev/null && return 0; return 1; }; sleep 0.05; done; return 1; }
status_of() { if wait "$1"; then LAST_STATUS=0; else LAST_STATUS=$?; fi; }
# Menu com preferências isoladas por processo.
menu() { local name=$1; shift; timeout 120 "$GAME_BIN" --headless "${PATH_ARGS[@]}" -- --mode=menu --menu-settings-path="$TMP_DIR/settings-$name.cfg" "$@" >"$TMP_DIR/$name.log" 2>&1; }
server() { local name=$1; shift; "$GAME_BIN" --headless "${PATH_ARGS[@]}" -- --mode=server --bind=127.0.0.1 "$@" >"$TMP_DIR/$name.log" 2>&1; }
# Porta que aceita TCP e nunca responde ao WebSocket (servidor travado).
blackhole() {
  python3 - "$1" >"$TMP_DIR/blackhole.log" 2>&1 <<'PY' &
import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(8)
print("BLACKHOLE_READY", flush=True)
conns = []
end = time.time() + 60
s.settimeout(1)
while time.time() < end:
    try:
        c, _ = s.accept(); conns.append(c)
    except socket.timeout:
        pass
PY
  BLACKHOLE_PID=$!; PIDS+=("$BLACKHOLE_PID")
  wait_marker 'BLACKHOLE_READY' "$TMP_DIR/blackhole.log" "$BLACKHOLE_PID"
}
( trap 'kill "$sleep_pid" 2>/dev/null; exit 0' TERM; sleep 600 & sleep_pid=$!; wait "$sleep_pid"; echo "MENU_FLOW_WATCHDOG_TIMEOUT" >"$TMP_DIR/watchdog.log"; kill -TERM $$ 2>/dev/null ) >/dev/null 2>&1 & WATCHDOG_PID=$!

# --- 1. Online sem URL configurada: aviso, nenhuma conexão --------------------
SCENE=online-unconfigured
# O projeto traz o servidor Railway como padrão; `--online-url=off` desliga o
# online nesta execução (nada de rede externa no teste).
menu online --menu-exit-on-return=true --menu-auto=online --online-url=off && status=0 || status=$?
assert_equal exit "$status" 0
assert_grep ready-reports-disabled 'MENU_READY name=[^ ]+ online=disabled source=disabled' "$TMP_DIR/online.log"
assert_grep online-unavailable 'MENU_ONLINE_UNAVAILABLE reason=disabled' "$TMP_DIR/online.log"
assert_no_grep online-no-connection 'CLIENT_CONNECTING|MENU_CONNECTING' "$TMP_DIR/online.log"
# Sem argumento, o menu lê o endereço padrão do projeto (sem conectar).
menu online-default --menu-auto=quit && status=0 || status=$?
assert_equal default-exit "$status" 0
assert_grep ready-reports-project-default 'MENU_READY name=[^ ]+ online=configured source=project_settings' "$TMP_DIR/online-default.log"
assert_no_grep default-no-connection 'CLIENT_CONNECTING|MENU_CONNECTING' "$TMP_DIR/online-default.log"

# --- 1b. Online com URL por argumento: tenta o endereço configurado ------------
SCENE=online-configured
menu online-url --menu-exit-on-return=true --menu-auto=online --online-url="ws://127.0.0.1:$((PORT + 9))" && status=0 || status=$?
assert_equal exit "$status" 0
assert_grep ready-reports-configured 'MENU_READY name=[^ ]+ online=configured source=argument' "$TMP_DIR/online-url.log"
assert_grep online-connects-configured-url "MENU_CONNECTING id=[^ ]+ url=ws://127.0.0.1:$((PORT + 9))" "$TMP_DIR/online-url.log"
assert_grep online-failure-recoverable 'MENU_RETURNED reason=connection_failed' "$TMP_DIR/online-url.log"
assert_equal online-single-attempt "$(grep -c 'CLIENT_CONNECTING' "$TMP_DIR/online-url.log")" 1

# --- 2. Timeout: servidor que não responde ------------------------------------
SCENE=timeout
blackhole "$PORT"
menu timeout --menu-auto=join --menu-address=127.0.0.1 --menu-port="$PORT" --test-connect-timeout-seconds=2 --menu-quit-after-reload=true && status=0 || status=$?
assert_equal exit "$status" 0
assert_grep state-connecting 'MENU_STATE validating>connecting attempt=1' "$TMP_DIR/timeout.log"
assert_grep timed-out 'MENU_RETURNED reason=timeout' "$TMP_DIR/timeout.log"
assert_grep failure-shown 'MENU_SHOWING_MESSAGE after_return=true hosting=false kind=failure' "$TMP_DIR/timeout.log"
assert_equal single-attempt "$(grep -c 'CLIENT_CONNECTING' "$TMP_DIR/timeout.log")" 1

# --- 3. Cancelar durante a conexão -------------------------------------------
SCENE=cancel-connecting
menu cancel --menu-auto=cancel-join --menu-address=127.0.0.1 --menu-port="$PORT" --menu-cancel-after-msec=700 --menu-quit-after-reload=true && status=0 || status=$?
assert_equal exit "$status" 0
assert_grep cancel-requested 'MENU_CANCEL_REQUESTED attempt=1 state=(connecting|awaiting_response)' "$TMP_DIR/cancel.log"
assert_grep cancelled 'MENU_CANCELLED stage=connecting' "$TMP_DIR/cancel.log"
assert_grep cancel-no-error 'MENU_SHOWING_MESSAGE after_return=true hosting=false kind=cancelled' "$TMP_DIR/cancel.log"
assert_no_grep cancel-no-timeout 'CLIENT_TIMEOUT|reason=timeout' "$TMP_DIR/cancel.log"
kill "$BLACKHOLE_PID" 2>/dev/null || true; status_of "$BLACKHOLE_PID"

# --- 4. Cancelar enquanto o servidor local inicia -----------------------------
SCENE=cancel-host
menu cancel-host --menu-exit-on-return=true --menu-auto=cancel-host --menu-port="$((PORT + 1))" && status=0 || status=$?
assert_equal exit "$status" 0
assert_grep host-spawned 'MENU_HOST_SPAWNED pid=[0-9]+' "$TMP_DIR/cancel-host.log"
assert_grep host-cancelled 'MENU_CANCELLED stage=starting_server' "$TMP_DIR/cancel-host.log"
HOSTED_PID="$(sed -n 's/.*MENU_HOST_SPAWNED pid=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/cancel-host.log" | head -1)"
assert_grep host-stopped "MENU_HOSTED_SERVER_STOPPED pid=$HOSTED_PID reason=cancelled" "$TMP_DIR/cancel-host.log"
for _ in {1..100}; do kill -0 "$HOSTED_PID" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$HOSTED_PID" 2>/dev/null; then echo "ASSERT_FAILED scene=$SCENE name=no-orphan-hosted-server" >&2; false; else ok no-orphan-hosted-server; fi

# --- 5. Falha e nova tentativa bem-sucedida (sessão nova) ---------------------
SCENE=retry
RETRY_PORT=$((PORT + 2))
menu retry --menu-auto=join --menu-name=Bia --menu-address=127.0.0.1 --menu-port="$RETRY_PORT" \
  --menu-after-return=retry --menu-after-return-delay-msec=2500 --menu-leave-after-msec=1200 --menu-exit-after-returns=2 &
RETRY_PID=$!; PIDS+=("$RETRY_PID")
wait_marker 'MENU_RETURNED reason=connection_failed' "$TMP_DIR/retry.log" "$RETRY_PID"
server retry-server --port="$RETRY_PORT" &
RETRY_SERVER=$!; PIDS+=("$RETRY_SERVER")
status_of "$RETRY_PID"; assert_equal exit "$LAST_STATUS" 0
assert_grep failure-restored 'MENU_SHOWING_MESSAGE after_return=true hosting=false kind=failure' "$TMP_DIR/retry.log"
assert_grep retry-pressed 'MENU_RETRY kind=join' "$TMP_DIR/retry.log"
assert_grep retry-joined 'JOIN_ACCEPTED id=Bia peer_id=[0-9]+' "$TMP_DIR/retry.log"
assert_equal two-attempts "$(grep -c 'CLIENT_CONNECTING' "$TMP_DIR/retry.log")" 2
assert_grep left-normally 'MENU_RETURNED reason=left' "$TMP_DIR/retry.log"
kill "$RETRY_SERVER" 2>/dev/null || true; status_of "$RETRY_SERVER"

# --- 6. Voltar ao menu e criar outra partida local ----------------------------
SCENE=host-again
menu host-again --menu-auto=host --menu-name=Anfitriã --menu-port="$((PORT + 3))" --menu-leave-after-msec=1200 \
  --menu-after-return=host --menu-after-return-delay-msec=300 --menu-exit-after-returns=2 && status=0 || status=$?
assert_equal exit "$status" 0
assert_equal two-hosted-servers "$(grep -c 'MENU_HOST_SPAWNED' "$TMP_DIR/host-again.log")" 2
assert_equal two-sessions "$(grep -c 'JOIN_ACCEPTED id=Anfitriã' "$TMP_DIR/host-again.log")" 2
assert_equal two-servers-stopped "$(grep -c 'MENU_HOSTED_SERVER_STOPPED pid=[0-9]* reason=left' "$TMP_DIR/host-again.log")" 2
for pid in $(sed -n 's/.*MENU_HOST_SPAWNED pid=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/host-again.log"); do
  for _ in {1..100}; do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then echo "ASSERT_FAILED scene=$SCENE name=no-orphan pid=$pid" >&2; false; fi
done
ok no-orphan-servers

# --- 7. Encerramento coordenado do servidor: aviso neutro, não erro -----------
SCENE=normal-shutdown
server shutdown-server --port="$((PORT + 4))" --test-shutdown-after-msec=1500 &
SHUTDOWN_SERVER=$!; PIDS+=("$SHUTDOWN_SERVER")
wait_marker 'SERVER_READY' "$TMP_DIR/shutdown-server.log" "$SHUTDOWN_SERVER"
menu shutdown --menu-auto=join --menu-address=127.0.0.1 --menu-port="$((PORT + 4))" --menu-quit-after-reload=true && status=0 || status=$?
assert_equal exit "$status" 0
assert_grep server-coordinated 'SERVER_TEST_SHUTDOWN lobby=1' "$TMP_DIR/shutdown-server.log"
assert_grep shutdown-info 'MENU_SHOWING_MESSAGE after_return=true hosting=false kind=info' "$TMP_DIR/shutdown.log"
assert_no_grep shutdown-no-failure 'kind=failure' "$TMP_DIR/shutdown.log"
status_of "$SHUTDOWN_SERVER"; assert_equal server-exit "$LAST_STATUS" 0

# --- 8. Sala cheia e nome em uso ---------------------------------------------
SCENE=full-room
FULL_PORT=$((PORT + 5))
server full-server --port="$FULL_PORT" &
FULL_SERVER=$!; PIDS+=("$FULL_SERVER")
wait_marker 'SERVER_READY' "$TMP_DIR/full-server.log" "$FULL_SERVER"
MEMBERS=()
for id in 1 2 3 4 5 6 7 8; do
  menu "member-$id" --menu-exit-on-return=true --menu-auto=join --menu-name="Convidado $id" --menu-address=127.0.0.1 --menu-port="$FULL_PORT" --menu-leave-after-msec=15000 &
  MEMBERS+=("$!"); PIDS+=("$!")
done
for id in 1 2 3 4 5 6 7 8; do wait_marker 'JOIN_ACCEPTED' "$TMP_DIR/member-$id.log" "${MEMBERS[$((id - 1))]}"; done
ok eight-joined-through-the-menu
menu ninth --menu-exit-on-return=true --menu-auto=join --menu-name=Nona --menu-address=127.0.0.1 --menu-port="$FULL_PORT" && status=0 || status=$?
assert_equal ninth-exit "$status" 0
assert_grep ninth-refused 'JOIN_REJECTED id=Nona reason=room_unavailable' "$TMP_DIR/ninth.log"
assert_grep ninth-message 'JOIN_REJECTED_MESSAGE id=Nona text=A sala está cheia' "$TMP_DIR/ninth.log"
menu same-name --menu-exit-on-return=true --menu-auto=join --menu-name="Convidado 1" --menu-address=127.0.0.1 --menu-port="$FULL_PORT" && status=0 || status=$?
assert_grep name-taken-or-full 'JOIN_REJECTED id=Convidado 1 reason=(room_unavailable|name_taken)' "$TMP_DIR/same-name.log"
for index in "${!MEMBERS[@]}"; do status_of "${MEMBERS[$index]}"; assert_equal "member-$((index + 1))-exit" "$LAST_STATUS" 0; done
kill "$FULL_SERVER" 2>/dev/null || true; status_of "$FULL_SERVER"

SCENE=name-taken
NAME_PORT=$((PORT + 6))
server name-server --port="$NAME_PORT" &
NAME_SERVER=$!; PIDS+=("$NAME_SERVER")
wait_marker 'SERVER_READY' "$TMP_DIR/name-server.log" "$NAME_SERVER"
menu first-ana --menu-exit-on-return=true --menu-auto=join --menu-name=Ana --menu-address=127.0.0.1 --menu-port="$NAME_PORT" --menu-leave-after-msec=6000 &
FIRST_ANA=$!; PIDS+=("$FIRST_ANA")
wait_marker 'JOIN_ACCEPTED' "$TMP_DIR/first-ana.log" "$FIRST_ANA"
menu second-ana --menu-exit-on-return=true --menu-auto=join --menu-name=Ana --menu-address=127.0.0.1 --menu-port="$NAME_PORT" && status=0 || status=$?
assert_equal second-exit "$status" 0
assert_grep name-taken 'JOIN_REJECTED id=Ana reason=name_taken' "$TMP_DIR/second-ana.log"
assert_grep name-taken-message 'JOIN_REJECTED_MESSAGE id=Ana text=Já existe alguém com esse nome' "$TMP_DIR/second-ana.log"
status_of "$FIRST_ANA"; assert_equal first-exit "$LAST_STATUS" 0
kill "$NAME_SERVER" 2>/dev/null || true; status_of "$NAME_SERVER"

# --- 10. Salas online pelo menu: criar, entrar pelo código, PRONTO, resultado --
# Servidor com salas; o coordenador de teste só fecha a rodada (elimina pela
# API interna). Tudo no menu é feito pelos botões reais: JOGAR ONLINE,
# CRIAR SALA, ENTRAR EM SALA, PRONTO e SAIR DA SALA.
SCENE=online-rooms
ROOMS_PORT=$((PORT + 7))
server rooms-server --port="$ROOMS_PORT" --rooms=true --rooms-test=true --countdown-seconds=2 \
  --round-end-delay-seconds=2 --rooms-target-rounds=1 --rooms-expect-peers=99 --rooms-step-gap-msec=800 &
ROOMS_SERVER=$!; PIDS+=("$ROOMS_SERVER")
wait_marker 'SERVER_READY' "$TMP_DIR/rooms-server.log" "$ROOMS_SERVER"
ROOM_ARGS=(--menu-exit-on-return=true --menu-auto=online --online-url="ws://127.0.0.1:$ROOMS_PORT" --menu-room-ready-min-players=4 --menu-room-leave-after-result=true)
menu room-host "${ROOM_ARGS[@]}" --menu-name=Dona --menu-room=create &
ROOM_MENUS=("$!"); PIDS+=("$!")
wait_marker 'ROOM_JOINED id=Dona code=' "$TMP_DIR/room-host.log" "${ROOM_MENUS[0]}"
ROOM_CODE="$(sed -n 's/.*ROOM_JOINED id=Dona code=\([A-Z0-9]*\).*/\1/p' "$TMP_DIR/room-host.log" | head -n1)"
TYPED_CODE="$(echo "${ROOM_CODE:0:3}-${ROOM_CODE:3:3}" | tr 'A-Z' 'a-z')"
for guest in Beto Caio Duda; do
  menu "room-$guest" "${ROOM_ARGS[@]}" --menu-name="$guest" --menu-room=join --room-code="$TYPED_CODE" &
  ROOM_MENUS+=("$!"); PIDS+=("$!")
done
for index in "${!ROOM_MENUS[@]}"; do status_of "${ROOM_MENUS[$index]}"; assert_equal "room-menu-$index-exit" "$LAST_STATUS" 0; done
for name in host Beto Caio Duda; do
  log="$TMP_DIR/room-$name.log"
  assert_grep "$name-hall" 'MENU_ONLINE_HALL' "$log"
  assert_grep "$name-room-shown" "MENU_ROOM_SHOWN code=$ROOM_CODE" "$log"
  assert_grep "$name-pressed-ready" 'MENU_ROOM_READY value=true' "$log"
  assert_grep "$name-countdown" 'MENU_ROOM phase=countdown players=4 ready=4' "$log"
  assert_grep "$name-played" 'CLIENT_VIEW id=[^ ]+ game=true' "$log"
  assert_grep "$name-back-in-room" 'MENU_ROOM phase=lobby players=[0-9] ready=0 own_ready=false' "$log"
  assert_grep "$name-result" 'CLIENT_ROOM_STATE .* phase=lobby round_id=1 .*result=true' "$log"
  assert_grep "$name-left" 'MENU_ONLINE_LEAVE panel=room' "$log"
  assert_grep "$name-returned" 'MENU_RETURNED reason=left' "$log"
done
assert_grep host-created 'MENU_ROOM_CREATE' "$TMP_DIR/room-host.log"
assert_grep guest-joined 'MENU_ROOM_JOIN' "$TMP_DIR/room-Beto.log"
assert_grep rooms-round 'ROUND_STATE state=ACTIVE round_id=1 players=4 participants=4 room=1' "$TMP_DIR/rooms-server.log"
assert_no_grep rooms-no-second-round 'ROUND_STATE state=(COUNTDOWN|ACTIVE) round_id=2' "$TMP_DIR/rooms-server.log"
kill "$ROOMS_SERVER" 2>/dev/null || true; status_of "$ROOMS_SERVER"

SCENE=all
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""
[[ ! -f "$TMP_DIR/watchdog.log" ]] || fail 1
assert_no_grep no-script-errors 'SCRIPT ERROR|Parse Error' "$TMP_DIR"/*.log
echo "MENU_FLOW_TEST_OK scenes=10"
