#!/usr/bin/env bash
# Teste multiprocesso do fluxo de partida local no PC, pelo mesmo caminho do
# build: o menu cria o servidor headless em processo separado e os outros
# clientes entram pelo menu. Roda contra o projeto (GAME_PATH) ou contra um
# executável exportado (sem GAME_PATH), inclusive o .console.exe do Windows.
#
#   GAME_BIN=godot GAME_PATH=. ./tests/desktop_local_match_test.sh
#   GAME_BIN=build/windows/ArmedMystery.console.exe ./tests/desktop_local_match_test.sh
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_BIN="${GAME_BIN:-$(command -v godot4 2>/dev/null || command -v godot 2>/dev/null || true)}"
GAME_PATH="${GAME_PATH-$ROOT}"
PORT="${TEST_PORT:-$((27080 + RANDOM % 1000))}"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE=false
else TMP_DIR="$(mktemp -d)"; REMOVE=true; fi
PIDS=(); WATCHDOG_PID=""; HOSTED_PID=""

[[ -n "$GAME_BIN" && -x "$GAME_BIN" ]] || { echo "Game executable not found. Set GAME_BIN." >&2; exit 127; }
PATH_ARGS=()
[[ -z "$GAME_PATH" ]] || PATH_ARGS=(--path "$GAME_PATH")

# PID do Godot: no Windows é o PID nativo, que o `kill` do Git Bash não enxerga.
pid_alive() {
  local pid="$1"
  [[ -n "$pid" ]] || return 1
  if command -v tasklist >/dev/null 2>&1; then
    tasklist //FI "PID eq $pid" 2>/dev/null | grep -q " $pid "
  else
    kill -0 "$pid" 2>/dev/null
  fi
}
kill_native() {
  local pid="$1"
  if command -v taskkill >/dev/null 2>&1; then taskkill //F //PID "$pid" >/dev/null 2>&1 || true
  else kill "$pid" 2>/dev/null || true; fi
}

cleanup() {
  local status=$?; trap - EXIT
  [[ -z "$WATCHDOG_PID" ]] || kill "$WATCHDOG_PID" 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true; done
  if pid_alive "$HOSTED_PID"; then kill_native "$HOSTED_PID"; fi
  [[ "$REMOVE" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
fail() { local status="${1:-1}"; echo "DESKTOP_LOCAL_MATCH_HARNESS_ERROR status=$status" >&2; for log in "$TMP_DIR"/*.log; do [[ ! -f "$log" ]] || { echo "===== $log =====" >&2; cat "$log" >&2; }; done; exit "$status"; }
trap 'fail $?' ERR
ok() { echo "ASSERT_OK name=$1"; }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || { echo "ASSERT_FAILED name=$n pattern=$p" >&2; return 1; }; }
assert_no_grep() { local n=$1 p=$2; shift 2; if grep -qE -- "$p" "$@"; then echo "ASSERT_FAILED name=$n forbidden=$p" >&2; return 1; else ok "$n"; fi; }
assert_equal() { [[ "$2" == "$3" ]] && ok "$1" || { echo "ASSERT_FAILED name=$1 expected=$3 actual=$2" >&2; return 1; }; }
wait_marker() { local p=$1 f=$2 pid=$3; for _ in {1..900}; do grep -qE -- "$p" "$f" 2>/dev/null && return 0; kill -0 "$pid" 2>/dev/null || { grep -qE -- "$p" "$f" 2>/dev/null && return 0; return 1; }; sleep 0.05; done; return 1; }
# Cada processo com preferências próprias: o nome salvo de um não vira o
# nome padrão de outro (várias janelas no mesmo PC).
run_menu() { local name=$1; shift; "$GAME_BIN" --headless "${PATH_ARGS[@]}" -- --mode=menu --menu-exit-on-return=true --menu-settings-path="$TMP_DIR/settings-$name.cfg" "$@" >"$TMP_DIR/$name.log" 2>&1; }
# Sem subshell: `wait` só enxerga filhos do shell atual.
wait_status() { if wait "$1"; then LAST_STATUS=0; else LAST_STATUS=$?; fi; }

( sleep 120; echo timeout >"$TMP_DIR/timeout.log"; for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done ) & WATCHDOG_PID=$!

# --- 1. Endereço inválido: nada é conectado -----------------------------------
run_menu invalid-address --menu-auto=join --menu-address=999.1.1.1 --menu-port="$PORT" && status=0 || status=$?
assert_equal invalid-address-exit "$status" 0
assert_grep invalid-address-rejected 'MENU_INPUT_INVALID field=address' "$TMP_DIR/invalid-address.log"
assert_no_grep invalid-address-never-connects 'MENU_CONNECTING|CLIENT_CONNECTING' "$TMP_DIR/invalid-address.log"

# --- 2. Sair pelo menu ---------------------------------------------------------
run_menu quit --menu-auto=quit && status=0 || status=$?
assert_equal menu-quit-exit "$status" 0
assert_grep menu-quit 'MENU_QUIT' "$TMP_DIR/quit.log"

# --- 3. Entrar sem servidor: falha de conexão clara e volta ao menu -----------
run_menu no-server --menu-auto=join --menu-address=127.0.0.1 --menu-port="$PORT" && status=0 || status=$?
assert_equal no-server-exit "$status" 0
assert_grep no-server-connection-failed 'CLIENT_CONNECTION_FAILED|CLIENT_TIMEOUT' "$TMP_DIR/no-server.log"
assert_grep no-server-back-to-menu 'MENU_RETURNED reason=(connection_failed|timeout)' "$TMP_DIR/no-server.log"

# --- 3b. Volta real ao menu (recarga da cena) com a mensagem de erro ---------
"$GAME_BIN" --headless "${PATH_ARGS[@]}" -- --mode=menu --menu-settings-path="$TMP_DIR/settings-reload.cfg" --menu-auto=join --menu-address=127.0.0.1 \
  --menu-port="$PORT" --menu-quit-after-reload=true >"$TMP_DIR/reload.log" 2>&1 && status=0 || status=$?
assert_equal reload-exit "$status" 0
assert_grep reload-returned 'MENU_RETURNED reason=connection_failed' "$TMP_DIR/reload.log"
assert_equal reload-menu-built-twice "$(grep -c 'MENU_READY' "$TMP_DIR/reload.log")" 2
assert_grep reload-shows-message 'MENU_SHOWING_MESSAGE after_return=true hosting=false' "$TMP_DIR/reload.log"
assert_equal reload-auto-action-runs-once "$(grep -c 'MENU_CONNECTING' "$TMP_DIR/reload.log")" 1
assert_grep reload-quits-from-menu 'MENU_QUIT' "$TMP_DIR/reload.log"

# --- 4. Porta ocupada: erro claro, nenhum servidor duplicado ------------------
# Porta própria e servidor que se encerra sozinho quando vazio: no Windows o
# `kill` do Git Bash só alcança o wrapper de console, não o processo do jogo.
BUSY_PORT=$((PORT + 1))
"$GAME_BIN" --headless "${PATH_ARGS[@]}" -- --mode=server --bind=127.0.0.1 --port="$BUSY_PORT" --hosted=true >"$TMP_DIR/occupier.log" 2>&1 &
OCCUPIER=$!; PIDS+=("$OCCUPIER")
wait_marker 'SERVER_READY' "$TMP_DIR/occupier.log" "$OCCUPIER"
run_menu busy-port --menu-auto=host --menu-port="$BUSY_PORT" && status=0 || status=$?
assert_equal busy-port-exit "$status" 0
assert_grep busy-port-clear-error 'MENU_HOST_ERROR reason=port_in_use' "$TMP_DIR/busy-port.log"
assert_no_grep busy-port-no-room 'MENU_HOST_SPAWNED|MENU_HOST_READY|MENU_CONNECTING' "$TMP_DIR/busy-port.log"

# --- 5. Partida completa: anfitrião + três clientes pelo menu -----------------
PORT=$((PORT + 2))
run_menu host --menu-auto=host --menu-port="$PORT" --menu-name=anfitriao --menu-leave-on=active &
HOST=$!; PIDS+=("$HOST")
wait_marker 'MENU_HOST_READY port=' "$TMP_DIR/host.log" "$HOST"
HOSTED_PID="$(sed -n 's/.*MENU_HOST_SPAWNED pid=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/host.log" | head -1)"
pid_alive "$HOSTED_PID" && ok hosted-server-process-running || { echo "ASSERT_FAILED name=hosted-server-process-running pid=$HOSTED_PID" >&2; false; }
# Um segundo "Criar" na mesma porta enquanto a sala existe não duplica servidor.
run_menu second-host --menu-auto=host --menu-port="$PORT" && status=0 || status=$?
assert_grep second-host-refused 'MENU_HOST_ERROR reason=port_in_use' "$TMP_DIR/second-host.log"
assert_no_grep second-host-no-spawn 'MENU_HOST_SPAWNED' "$TMP_DIR/second-host.log"
JOINERS=()
for id in 1 2 3; do
  # Sem --menu-name: cada processo usa o nome padrão distinto do menu.
  run_menu "joiner-$id" --menu-auto=join --menu-address=127.0.0.1 --menu-port="$PORT" &
  JOINERS+=("$!"); PIDS+=("$!")
done
wait_status "$HOST"; HOST_STATUS=$LAST_STATUS
JOINER_STATUSES=()
for pid in "${JOINERS[@]}"; do wait_status "$pid"; JOINER_STATUSES+=("$LAST_STATUS"); done
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""
[[ ! -f "$TMP_DIR/timeout.log" ]] && ok watchdog-timeout-absent || fail 1

assert_equal host-exit "$HOST_STATUS" 0
for index in 0 1 2; do assert_equal "joiner-$((index + 1))-exit" "${JOINER_STATUSES[$index]}" 0; done
MATCH_LOGS=("$TMP_DIR/host.log" "$TMP_DIR"/joiner-*.log)
NAMES="$(sed -n 's/.*MENU_CONNECTING id=\([^ ]*\) .*/\1/p' "${MATCH_LOGS[@]}" | sort -u)"
assert_equal four-distinct-player-names "$(wc -l <<<"$NAMES" | tr -d ' ')" 4
for log in "${MATCH_LOGS[@]}"; do
  name="$(basename "$log" .log)"
  assert_grep "$name-joined" 'JOIN_ACCEPTED id=' "$log"
  assert_grep "$name-round-active" 'CLIENT_ROUND_STATE id=[^ ]+ state=ACTIVE' "$log"
  assert_equal "$name-exactly-one-private-role" "$(grep -c 'CLIENT_PRIVATE_ROLE_RECEIVED' "$log")" 1
done
# O anfitrião sai: o servidor hospedado é encerrado e os outros são avisados.
assert_grep host-left 'MENU_RETURNED reason=left' "$TMP_DIR/host.log"
assert_grep host-stopped-its-server "MENU_HOSTED_SERVER_STOPPED pid=$HOSTED_PID reason=left" "$TMP_DIR/host.log"
for id in 1 2 3; do
  assert_grep "joiner-$id-sees-disconnect" 'CLIENT_SERVER_DISCONNECTED id=' "$TMP_DIR/joiner-$id.log"
  assert_grep "joiner-$id-back-to-menu" 'MENU_RETURNED reason=server_disconnected' "$TMP_DIR/joiner-$id.log"
  assert_no_grep "joiner-$id-never-hosts" 'MENU_HOST_SPAWNED|SERVER_READY' "$TMP_DIR/joiner-$id.log"
done
for _ in {1..100}; do pid_alive "$HOSTED_PID" || break; sleep 0.1; done
if pid_alive "$HOSTED_PID"; then echo "ASSERT_FAILED name=no-orphan-server pid=$HOSTED_PID" >&2; false; else ok no-orphan-server; fi
assert_grep loopback-by-default "MENU_HOST_SPAWNED pid=$HOSTED_PID port=$PORT bind=127.0.0.1" "$TMP_DIR/host.log"
assert_equal single-spawned-server "$(grep -h -c 'MENU_HOST_SPAWNED' "$TMP_DIR"/*.log | awk '{s+=$1} END{print s}')" 1

# --- 6. LAN só por escolha explícita do anfitrião ----------------------------
LAN_PORT=$((PORT + 1))
run_menu lan-host --menu-auto=host --menu-port="$LAN_PORT" --menu-lan=true --menu-leave-on=joined && status=0 || status=$?
assert_equal lan-host-exit "$status" 0
assert_grep lan-host-binds-all-interfaces "MENU_HOST_SPAWNED pid=[0-9]+ port=$LAN_PORT bind=0.0.0.0" "$TMP_DIR/lan-host.log"
assert_grep lan-host-ready "MENU_HOST_READY port=$LAN_PORT lan=true" "$TMP_DIR/lan-host.log"
LAN_PID="$(sed -n 's/.*MENU_HOST_SPAWNED pid=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/lan-host.log" | head -1)"
assert_grep lan-host-stopped-its-server "MENU_HOSTED_SERVER_STOPPED pid=$LAN_PID reason=left" "$TMP_DIR/lan-host.log"
for _ in {1..100}; do pid_alive "$LAN_PID" || break; sleep 0.1; done
if pid_alive "$LAN_PID"; then echo "ASSERT_FAILED name=no-orphan-lan-server pid=$LAN_PID" >&2; false; else ok no-orphan-lan-server; fi
assert_no_grep no-role-name-in-client-markers '(CLIENT|MENU)_[A-Z_]+ .*(ASSASSIN|DETECTIVE|VICTIM)' "$TMP_DIR"/*.log
assert_no_grep no-script-error 'SCRIPT ERROR|Parse Error' "$TMP_DIR"/*.log
echo "DESKTOP_LOCAL_MATCH_TEST_OK clients=4 hosted_pid=$HOSTED_PID"
