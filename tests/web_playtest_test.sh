#!/usr/bin/env bash
set -Eeuo pipefail

# Fase 9 (PR2): cliente Web completo (export "Web Playtest") no Chromium
# headless (Playwright).
#   offline            menu pronto, JOGAR ONLINE apontando para o Railway,
#                      sem criar partida local nem LAN, nada conecta sozinho;
#   offline-injection  `?online-url=` fora de localhost é ignorado;
#   room               servidor local com salas + 3 clientes nativos; o
#                      navegador entra pelo menu com o código em minúsculas,
#                      marca PRONTO, joga a rodada (mansão em WebGL), vê o
#                      resultado na sala e sai.
# Uso: [GODOT_BIN=godot] [WEB_DIR=build/web-playtest] [TEST_LOG_DIR=...] tests/web_playtest_test.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 2>/dev/null || command -v godot 2>/dev/null || true)}"
WEB_DIR="${WEB_DIR:-$ROOT/build/web-playtest}"
PORT="${TEST_PORT:-$((25080 + RANDOM % 1000))}"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE=false
else TMP_DIR="$(mktemp -d)"; REMOVE=true; fi
PIDS=()
FAILED=0
cleanup() {
  local status=$?; trap - EXIT
  for pid in "${PIDS[@]:-}"; do [[ -z "$pid" ]] || kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
  [[ "$REMOVE" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT
ok() { echo "ASSERT_OK name=$1"; }
bad() { echo "ASSERT_FAILED name=$1 ${2:-}" >&2; FAILED=$((FAILED + 1)); }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || bad "$n" "pattern=$p"; }
wait_marker() { local p=$1 f=$2 pid=$3; for _ in {1..600}; do grep -qE -- "$p" "$f" 2>/dev/null && return 0; kill -0 "$pid" 2>/dev/null || return 1; sleep 0.1; done; return 1; }

[[ -x "$GODOT_BIN" ]] || { echo "Godot not found. Set GODOT_BIN." >&2; exit 127; }
[[ -s "$WEB_DIR/index.html" ]] || { echo "Web export not found in $WEB_DIR" >&2; exit 127; }
export WEB_SHOTS="$TMP_DIR"

for scenario in offline offline-injection; do
  if timeout 180 node "$ROOT/tests/web_playtest_browser.mjs" "$WEB_DIR" "$scenario" >"$TMP_DIR/web-$scenario.log" 2>&1; then
    ok "web-$scenario"
  else
    bad "web-$scenario" "$(grep -E 'WEB_TEST_FAILED' "$TMP_DIR/web-$scenario.log" | head -1)"
  fi
done
assert_no_connect() { if grep -q 'CLIENT_CONNECTING' "$1"; then bad "$2"; else ok "$2"; fi; }
assert_no_connect "$TMP_DIR/web-offline.log" offline-never-connects
assert_no_connect "$TMP_DIR/web-offline-injection.log" injected-url-ignored

# --- Sala local: 3 clientes nativos + o navegador ----------------------------
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --rooms=true --rooms-test=true --countdown-seconds=2 --round-end-delay-seconds=3 \
  --rooms-target-rounds=1 --rooms-expect-peers=99 --rooms-step-gap-msec=1500 >"$TMP_DIR/server.log" 2>&1 &
SERVER_PID=$!; PIDS+=("$SERVER_PID")
wait_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"
native() {
  local name=$1; shift
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="$name" --url="ws://127.0.0.1:$PORT" \
    --auto-ready-rounds=1 --auto-ready-min-players=4 "$@" >"$TMP_DIR/$name.log" 2>&1 &
  PIDS+=("$!"); LAST_PID=$!
}
native Nativo1 --room-action=create
wait_marker 'ROOM_JOINED id=Nativo1 code=' "$TMP_DIR/Nativo1.log" "$LAST_PID"
CODE="$(sed -n 's/.*ROOM_JOINED id=Nativo1 code=\([A-Z0-9]*\).*/\1/p' "$TMP_DIR/Nativo1.log" | head -n1)"
native Nativo2 --room-action=join --room-code="$CODE"
native Nativo3 --room-action=join --room-code="$CODE"
if timeout 240 node "$ROOT/tests/web_playtest_browser.mjs" "$WEB_DIR" room "$PORT" "$CODE" >"$TMP_DIR/web-room.log" 2>&1; then
  ok web-room
else
  bad web-room "$(grep -E 'WEB_TEST_FAILED' "$TMP_DIR/web-room.log" | head -1)"
fi
W="$TMP_DIR/web-room.log"
S="$TMP_DIR/server.log"
assert_grep browser-joined-by-code 'CLIENT_JOINED id=Navegador peer_id=[0-9]+ count=4 room=1' "$S"
assert_grep round-with-browser 'ROUND_STATE state=ACTIVE round_id=1 players=4 participants=4 room=1' "$S"
assert_grep browser-pressed-ready 'WEB_CONSOLE MENU_ROOM_READY value=true' "$W"
assert_grep browser-got-role 'WEB_CONSOLE CLIENT_PRIVATE_ROLE_RECEIVED id=Navegador count=1' "$W"
assert_grep browser-saw-result 'WEB_CONSOLE CLIENT_ROOM_STATE .* phase=lobby round_id=1 .*result=true' "$W"
assert_grep browser-left 'WEB_CONSOLE MENU_RETURNED reason=left' "$W"
assert_grep browser-protocol 'WEB_CONSOLE CLIENT_PROTOCOL id=Navegador version=11' "$W"
if grep -qE 'SCRIPT ERROR|WEB_PAGE_ERROR' "$TMP_DIR"/web-*.log; then bad no-web-script-errors; else ok no-web-script-errors; fi

if [[ "$FAILED" -gt 0 ]]; then
  echo "WEB_PLAYTEST_TEST_FAILED failures=$FAILED logs=$TMP_DIR" >&2
  for f in "$TMP_DIR"/*.log; do echo "===== $f" >&2; tail -n 40 "$f" >&2; done
  exit 1
fi
echo "WEB_PLAYTEST_TEST_OK"
