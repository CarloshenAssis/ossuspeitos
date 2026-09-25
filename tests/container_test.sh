#!/usr/bin/env bash
# Fase 8: testes da imagem de PRODUÇÃO do servidor dedicado (Dockerfile,
# estágio runtime), com clientes Godot reais FORA do container.
#
# Cenas:
#   config        PORT inválida/vazia/fora da faixa, flag de teste, bind
#                 inválido: saída 2 com mensagem; sem PORT: porta padrão.
#   runtime       usuário sem privilégios; porta ocupada: saída 1 sem trocar
#                 de porta; nenhum modo de teste; build release.
#   idle          vivo além dos prazos antigos de teste; TCP sem handshake e
#                 WebSocket sem entrada são derrubados; sonda entra depois.
#   multiplayer   8 clientes entram, rodada ACTIVE com 8, papel privado para
#                 cada um, aparências iguais em todos; 9º recusado (sala
#                 cheia); protocolo 9 recusado; cliente adversarial não
#                 derruba nada; cliente morto sai do lobby; todos saem e uma
#                 nova turma joga a rodada seguinte.
#   stop          docker stop com jogadores: aviso coordenado, clientes saem
#                 com 0, container sai com 0 dentro do prazo.
#   restart       nova inicialização sem estado antigo (rodada volta a 1).
#   resources     docker stats vazio / 8 clientes / depois; log sem excesso.
#
# Uso: IMAGE=armed-mystery-server:dev [GODOT_BIN=godot] [TEST_LOG_DIR=...]
#      [IDLE_SECONDS=40] tests/container_test.sh
# Não constrói a imagem, não publica nada e só remove os próprios containers.
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:?defina IMAGE (ex.: armed-mystery-server:dev)}"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 2>/dev/null || command -v godot 2>/dev/null || true)}"
IDLE_SECONDS="${IDLE_SECONDS:-40}"
PORT="${TEST_PORT:-$((32080 + RANDOM % 900))}"
PREFIX="am-ct-$$"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE=false
else TMP_DIR="$(mktemp -d)"; REMOVE=true; fi
PIDS=(); CONTAINERS=(); WATCHDOG_PID=""; SCENE=none
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Godot não encontrado. Defina GODOT_BIN." >&2; exit 127; }
docker image inspect "$IMAGE" >/dev/null || { echo "Imagem $IMAGE não existe." >&2; exit 127; }

cleanup() {
  local status=$?; trap - EXIT
  [[ -z "$WATCHDOG_PID" ]] || kill "$WATCHDOG_PID" 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true; done
  for name in "${CONTAINERS[@]:-}"; do
    [[ -z "$name" ]] && continue
    docker logs "$name" >"$TMP_DIR/container-$name.log" 2>&1 || true
    docker rm -f "$name" >/dev/null 2>&1 || true
  done
  [[ "$REMOVE" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
fail() {
  local status="${1:-1}"
  echo "CONTAINER_HARNESS_ERROR status=$status scene=$SCENE logs=$TMP_DIR" >&2
  for name in "${CONTAINERS[@]:-}"; do [[ -z "$name" ]] || { echo "===== container $name (tail) =====" >&2; docker logs --tail 60 "$name" >&2 2>&1 || true; }; done
  for log in "$TMP_DIR"/*.log; do [[ ! -f "$log" ]] || { echo "===== $log (tail) =====" >&2; tail -n 25 "$log" >&2; }; done
  exit "$status"
}
trap 'fail $?' ERR
ok() { echo "ASSERT_OK scene=$SCENE name=$1"; }
bad() { echo "ASSERT_FAILED scene=$SCENE name=$1 ${2:-}" >&2; return 1; }
assert_equal() { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "expected=$3 actual=$2"; }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || bad "$n" "pattern=$p"; }
assert_no_grep() { local n=$1 p=$2; shift 2; if grep -qE -- "$p" "$@"; then bad "$n" "forbidden=$p observed=$(grep -hE -- "$p" "$@" | head -1)"; else ok "$n"; fi; }
clog() { docker logs "$1" 2>&1; }
# Espera um padrão no log do container (ou falha no prazo).
wait_clog() { local name=$1 pattern=$2 seconds=${3:-30}; for _ in $(seq 1 $((seconds * 10))); do clog "$name" | grep -qE -- "$pattern" && return 0; sleep 0.1; done; bad "wait-$pattern" "container=$name"; }
wait_count() { local name=$1 pattern=$2 count=$3 seconds=${4:-30}; for _ in $(seq 1 $((seconds * 10))); do [[ "$(clog "$name" | grep -cE -- "$pattern" || true)" -ge "$count" ]] && return 0; sleep 0.1; done; bad "wait-count-$pattern" "want=$count got=$(clog "$name" | grep -cE -- "$pattern" || true)"; }
running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == true ]]; }
exit_code() { docker inspect -f '{{.State.ExitCode}}' "$1"; }
start_container() { local name=$1; shift; CONTAINERS+=("$name"); docker run -d --name "$name" "$@" >/dev/null; }
client() { local name=$1; shift; "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="$name" --url="ws://127.0.0.1:$PORT" "$@" >"$TMP_DIR/client-$name.log" 2>&1 & PIDS+=("$!"); LAST_PID=$!; }
probe() { local name=$1; shift; timeout 40 "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --probe=true --client-id="$name" --url="ws://127.0.0.1:$PORT" "$@" >"$TMP_DIR/probe-$name.log" 2>&1; }
stats() { docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}} {{.NetIO}}' "$1" | tee -a "$TMP_DIR/stats.log" | sed "s/^/RESOURCE label=$2 /"; }
( trap 'kill "$sleep_pid" 2>/dev/null; exit 0' TERM; sleep 900 & sleep_pid=$!; wait "$sleep_pid"; echo "CONTAINER_TEST_WATCHDOG" >"$TMP_DIR/watchdog.log"; kill -TERM $$ 2>/dev/null ) >/dev/null 2>&1 & WATCHDOG_PID=$!

# --- config: erro explícito, saída 2, sem troca silenciosa -----------------------
SCENE=config
run_config() { # nome, esperado, args...
  local name=$1 expected=$2; shift 2
  local status=0
  timeout 60 docker run --rm --name "$PREFIX-$name" "$@" >"$TMP_DIR/config-$name.log" 2>&1 || status=$?
  assert_equal "$name-exit" "$status" "$expected"
}
run_config port-text 2 -e PORT=abc "$IMAGE"
assert_grep port-text-message 'DEDICATED_CONFIG_ERROR PORT inválida: "abc"' "$TMP_DIR/config-port-text.log"
run_config port-empty 2 -e PORT= "$IMAGE"
assert_grep port-empty-message 'DEDICATED_CONFIG_ERROR PORT inválida: ""' "$TMP_DIR/config-port-empty.log"
run_config port-range 2 -e PORT=70000 "$IMAGE"
run_config port-zero 2 -e PORT=0 "$IMAGE"
run_config test-flag 2 -e PORT=9080 "$IMAGE" --combat-test=true
assert_grep test-flag-message 'argumentos não permitidos no modo dedicado: combat-test' "$TMP_DIR/config-test-flag.log"
run_config bind-invalid 2 -e PORT=9080 -e ARMED_MYSTERY_BIND=nao-e-ip "$IMAGE"
for name in port-text port-empty port-range port-zero test-flag bind-invalid; do
  assert_no_grep "$name-never-ready" 'DEDICATED_READY' "$TMP_DIR/config-$name.log"
done
start_container "$PREFIX-default" "$IMAGE"
wait_clog "$PREFIX-default" 'DEDICATED_READY' 30
assert_grep default-port 'DEDICATED_READY bind=0.0.0.0 port=9080 port_source=default' <(clog "$PREFIX-default")
T0=$(date +%s%N); docker stop -t 20 "$PREFIX-default" >/dev/null; STOP_MS=$(( ($(date +%s%N) - T0) / 1000000 ))
assert_equal empty-stop-exit "$(exit_code "$PREFIX-default")" 0
[[ "$STOP_MS" -lt 8000 ]] && ok "empty-stop-fast ms=$STOP_MS" || bad empty-stop-fast "ms=$STOP_MS"
assert_grep empty-stop-coordinated 'DEDICATED_EXIT code=0 reason=operator' <(clog "$PREFIX-default")

# --- runtime: usuário, porta ocupada, nenhum modo de teste ----------------------
SCENE=runtime
MAIN="$PREFIX-main"
T0=$(date +%s%N)
start_container "$MAIN" -e PORT="$PORT" -e ARMED_MYSTERY_STATUS_SECONDS=5 -p "127.0.0.1:$PORT:$PORT" "$IMAGE"
wait_clog "$MAIN" 'DEDICATED_READY' 30
echo "STARTUP ready_ms=$(( ($(date +%s%N) - T0) / 1000000 ))"
assert_grep ready-line "DEDICATED_READY bind=0.0.0.0 port=$PORT port_source=env capacity=8 protocol=11 shutdown_file=on max_rooms=12" <(clog "$MAIN")
assert_grep release-build 'DEDICATED_START game=armed-mystery commit=[0-9a-f]+ godot=4\.4\.1-stable .*protocol=11 build=release display=headless capacity=8' <(clog "$MAIN")
assert_equal non-root-uid "$(docker exec "$MAIN" id -u)" 10001
assert_equal app-read-only "$(docker exec "$MAIN" sh -c 'touch /app/x 2>/dev/null && echo writable || echo read-only')" read-only
BUSY_STATUS=0
docker exec "$MAIN" /app/armed-mystery-server.x86_64 --headless -- --mode=dedicated --port="$PORT" >"$TMP_DIR/busy.log" 2>&1 || BUSY_STATUS=$?
assert_equal busy-port-exit "$BUSY_STATUS" 1
assert_grep busy-port-reason "DEDICATED_FATAL reason=listen_failed bind=0.0.0.0 port=$PORT" "$TMP_DIR/busy.log"
assert_no_grep busy-port-no-fallback 'DEDICATED_READY' "$TMP_DIR/busy.log"
assert_no_grep no-test-modes 'Coordinator|COMBAT_TEST|CAMPAIGN_|SYNC_TEST|TEST_NET_PROFILE|SERVER_TEST' <(clog "$MAIN")

# --- idle: vivo, conexões sem entrada derrubadas, sonda entra depois ------------
SCENE=idle
python3 - "$PORT" >"$TMP_DIR/stalled.log" 2>&1 <<'PY' &
import base64, os, socket, sys, time
port = int(sys.argv[1])
def closed_after(sock, limit):
    sock.settimeout(1.0)
    start = time.time()
    while time.time() - start < limit:
        try:
            data = sock.recv(4096)
            if data == b"":
                return time.time() - start
        except socket.timeout:
            pass
        except OSError:
            return time.time() - start
    return None
# 1) TCP sem handshake WebSocket.
raw = socket.create_connection(("127.0.0.1", port))
# 2) WebSocket aberto que nunca pede entrada na sala.
ws = socket.create_connection(("127.0.0.1", port))
key = base64.b64encode(os.urandom(16)).decode()
ws.sendall(("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % key).encode())
ws.settimeout(5.0)
head = ws.recv(4096)
print("WS_HANDSHAKE", head.split(b"\r\n")[0].decode(errors="replace"), flush=True)
raw_closed = closed_after(raw, 20)
print("RAW_CLOSED_AFTER", "none" if raw_closed is None else "%.1f" % raw_closed, flush=True)
ws_closed = closed_after(ws, 25)
print("WS_CLOSED_AFTER", "none" if ws_closed is None else "%.1f" % ws_closed, flush=True)
PY
STALLED_PID=$!; PIDS+=("$STALLED_PID")
sleep "$IDLE_SECONDS"
running "$MAIN" && ok "alive-after-${IDLE_SECONDS}s" || bad alive-after-idle
wait "$STALLED_PID" || true
assert_grep ws-handshake-accepted 'WS_HANDSHAKE HTTP/1.1 101' "$TMP_DIR/stalled.log"
assert_grep raw-tcp-dropped 'RAW_CLOSED_AFTER [0-9]' "$TMP_DIR/stalled.log"
assert_grep ws-without-join-dropped 'WS_CLOSED_AFTER [0-9]' "$TMP_DIR/stalled.log"
assert_grep join-deadline-logged 'DEDICATED_JOIN_DEADLINE peer_id=' <(clog "$MAIN")
assert_grep status-line 'DEDICATED_STATUS uptime_s=[0-9]+ peers=0 hall=0 pending=0 rooms=0 rooms_playing=0 room_members=0 ' <(clog "$MAIN")
stats "$MAIN" idle
probe after-idle && ok probe-after-idle || bad probe-after-idle
assert_grep probe-joined 'PROBE_OK .* result=joined .* round_state=WAITING room=lobby protocol=11' "$TMP_DIR/probe-after-idle.log"

# --- multiplayer: 8 clientes, sigilo, recusas, adversário, saídas ---------------
SCENE=multiplayer
CLIENT_PIDS=()
# Salas (fase 9): o primeiro cria, os outros entram pelo código; todos marcam
# PRONTO sozinhos quando a sala tem 8 e a contagem real (10 s) começa.
READY8=(--auto-ready-rounds=1 --auto-ready-min-players=8)
client "jogador-1" --room-action=create "${READY8[@]}"; CLIENT_PIDS+=("$LAST_PID")
for _ in $(seq 1 300); do grep -q 'ROOM_JOINED id=jogador-1 code=' "$TMP_DIR/client-jogador-1.log" && break; sleep 0.1; done
CODE="$(sed -n 's/.*ROOM_JOINED id=jogador-1 code=\([A-Z0-9]*\).*/\1/p' "$TMP_DIR/client-jogador-1.log" | head -n1)"
[[ -n "$CODE" ]] && ok room-created || bad room-created
for id in 2 3 4 5 6 7 8; do client "jogador-$id" --room-action=join --room-code="$CODE" "${READY8[@]}"; CLIENT_PIDS+=("$LAST_PID"); done
wait_count "$MAIN" 'CLIENT_JOINED id=jogador-' 8 60
wait_count "$MAIN" 'ROOM_READY room=[0-9]+ peer_id=[0-9]+ ready=true ready_count=8 players=8' 1 60
wait_clog "$MAIN" 'ROUND_STATE state=ACTIVE round_id=1 players=8 participants=8 room=' 60
ok eight-joined-round-active
sleep 2
stats "$MAIN" eight-clients
for id in 1 2 3 4 5 6 7 8; do
  log="$TMP_DIR/client-jogador-$id.log"
  assert_grep "client-$id-accepted" "JOIN_ACCEPTED id=jogador-$id " "$log"
  assert_equal "client-$id-one-private-role" "$(grep -c "CLIENT_PRIVATE_ROLE_RECEIVED id=jogador-$id " "$log")" 1
done
# Aparência pública igual para todos (último roster de cada cliente).
APPEARANCES="$(for id in 1 2 3 4 5 6 7 8; do grep 'CLIENT_ROSTER_APPEARANCES' "$TMP_DIR/client-jogador-$id.log" | tail -1 | sed 's/.* map=//'; done | sort -u | wc -l)"
assert_equal appearance-consistent "$APPEARANCES" 1
assert_no_grep server-log-no-roles 'ASSASSIN|DETECTIVE|VICTIM|assassino|detetive' <(clog "$MAIN")
assert_no_grep client-logs-no-roles 'ASSASSIN|DETECTIVE|VICTIM' "$TMP_DIR"/client-jogador-*.log
probe nono --room-action=join --room-code="$CODE" && ok ninth-probe-ran || bad ninth-probe-ran
assert_grep ninth-refused 'PROBE_OK .* result=refused detail=room_full' "$TMP_DIR/probe-nono.log"
VERSION_STATUS=0; probe versao-9 --test-protocol-version=9 || VERSION_STATUS=$?
assert_equal protocol-9-refused-exit "$VERSION_STATUS" 1
assert_grep protocol-9-reason 'PROBE_FAILED .* reason=join_rejected:protocol_version' "$TMP_DIR/probe-versao-9.log"
assert_grep protocol-9-server 'JOIN_PROTOCOL_MISMATCH peer_id=[0-9]+ client=9 server=11' <(clog "$MAIN")
# Cliente adversarial (payloads e RPCs hostis) contra o container.
timeout 60 "$GODOT_BIN" --headless --path "$ROOT" --script tests/adversarial_client.gd -- \
  --url="ws://127.0.0.1:$PORT" --client-id=invasor --attack=full --quit-after-msec=6000 >"$TMP_DIR/attacker.log" 2>&1 || true
sleep 1
running "$MAIN" && ok alive-after-attack || bad alive-after-attack
assert_equal eight-still-in-room "$(clog "$MAIN" | grep -cE 'CLIENT_LEFT peer_id=[0-9]+ count=[1-7] room=' || true)" 0
# Cliente derrubado (SIGKILL) sai do lobby.
kill -KILL "${CLIENT_PIDS[7]}"; wait "${CLIENT_PIDS[7]}" 2>/dev/null || true
wait_clog "$MAIN" 'CLIENT_LEFT peer_id=[0-9]+ count=7 room=' 30
ok killed-client-left
for index in 0 1 2 3 4 5 6; do kill -TERM "${CLIENT_PIDS[$index]}" 2>/dev/null || true; done
for index in 0 1 2 3 4 5 6; do wait "${CLIENT_PIDS[$index]}" 2>/dev/null || true; done
wait_clog "$MAIN" 'CLIENT_LEFT peer_id=[0-9]+ count=0 room=' 30
ok everyone-left
sleep 2
stats "$MAIN" after-leave
running "$MAIN" && ok alive-when-empty-again || bad alive-when-empty-again
# Nova turma na mesma sessão do servidor.
GROUP2=()
start_group() { # prefixo -> sala nova com 4, todos prontos
  local prefix=$1 code=""
  client "$prefix-1" --room-action=create --auto-ready-rounds=1 --auto-ready-min-players=4; GROUP+=("$LAST_PID")
  for _ in $(seq 1 300); do grep -q "ROOM_JOINED id=$prefix-1 code=" "$TMP_DIR/client-$prefix-1.log" && break; sleep 0.1; done
  code="$(sed -n "s/.*ROOM_JOINED id=$prefix-1 code=\([A-Z0-9]*\).*/\1/p" "$TMP_DIR/client-$prefix-1.log" | head -n1)"
  for id in 2 3 4; do client "$prefix-$id" --room-action=join --room-code="$code" --auto-ready-rounds=1 --auto-ready-min-players=4; GROUP+=("$LAST_PID"); done
}
GROUP=(); start_group turma2; GROUP2=("${GROUP[@]}")
# Sala nova: a rodada dela começa em 1, independente da sala anterior.
wait_clog "$MAIN" 'ROUND_STATE state=ACTIVE round_id=1 players=4 participants=4 room=' 60
ok new-group-plays-next-round

# --- stop: encerramento coordenado com jogadores conectados ---------------------
SCENE=stop
T0=$(date +%s%N); docker stop -t 20 "$MAIN" >/dev/null; STOP_MS=$(( ($(date +%s%N) - T0) / 1000000 ))
echo "SHUTDOWN stop_ms=$STOP_MS"
assert_equal container-exit "$(exit_code "$MAIN")" 0
[[ "$STOP_MS" -lt 10000 ]] && ok "stop-within-deadline ms=$STOP_MS" || bad stop-within-deadline "ms=$STOP_MS"
assert_grep shutdown-requested 'DEDICATED_SHUTDOWN_REQUESTED reason=signal lobby=4' <(clog "$MAIN")
assert_grep shutdown-complete 'SERVER_SHUTDOWN_COMPLETE closed=4' <(clog "$MAIN")
assert_grep wrapper-exit 'WRAPPER_EXIT code=0' <(clog "$MAIN")
for index in 0 1 2 3; do
  if wait "${GROUP2[$index]}"; then status=0; else status=$?; fi
  assert_equal "group2-$((index + 1))-exit" "$status" 0
  assert_grep "group2-$((index + 1))-informed" "CLIENT_SHUTDOWN_COMPLETE id=turma2-$((index + 1))" "$TMP_DIR/client-turma2-$((index + 1)).log"
done

# --- restart: sem estado antigo ------------------------------------------------
SCENE=restart
docker start "$MAIN" >/dev/null
wait_count "$MAIN" 'DEDICATED_READY' 2 30
GROUP3=()
GROUP=(); start_group turma3; GROUP3=("${GROUP[@]}")
wait_count "$MAIN" 'ROUND_STATE state=ACTIVE round_id=1 players=4 participants=4 room=1$' 1 60
# Sem persistência: as salas anteriores se perderam com o processo e a
# numeração recomeça (a primeira sala depois do reinício é a 1 de novo).
[[ "$(clog "$MAIN" | grep -c 'ROOM_CREATED room=1 rooms=1' || true)" -ge 2 ]] && ok fresh-state-after-restart || bad fresh-state-after-restart
docker stop -t 20 "$MAIN" >/dev/null
assert_equal restart-stop-exit "$(exit_code "$MAIN")" 0
for pid in "${GROUP3[@]}"; do wait "$pid" 2>/dev/null || true; done

# --- resources e higiene de log --------------------------------------------------
SCENE=resources
LINES="$(clog "$MAIN" | wc -l)"
echo "LOG_LINES total=$LINES"
[[ "$LINES" -lt 600 ]] && ok "log-volume-bounded lines=$LINES" || bad log-volume-bounded "lines=$LINES"
assert_no_grep no-snapshot-logs 'world_snapshot|SNAPSHOT ' <(clog "$MAIN")
ENGINE_SEND_ERRORS="$(clog "$MAIN" | grep -c 'ready_state != STATE_OPEN' || true)"
echo "ENGINE_SEND_ERRORS count=$ENGINE_SEND_ERRORS"
[[ "$ENGINE_SEND_ERRORS" -le 100 ]] && ok "engine-send-errors-bounded count=$ENGINE_SEND_ERRORS" || bad engine-send-errors-bounded "count=$ENGINE_SEND_ERRORS"
clog "$MAIN" | grep 'DEDICATED_STATUS' | tail -3
for pid in "${PIDS[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then bad no-orphan-client "pid=$pid"; fi
done
ok no-orphan-processes

SCENE=all
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""
[[ ! -f "$TMP_DIR/watchdog.log" ]] || fail 1
echo "CONTAINER_TEST_OK image=$IMAGE port=$PORT"
