#!/usr/bin/env bash
# Fase 4, camada B: servidor e 4 clientes reais pelo WebSocket (protocolo 9),
# mais um cliente com versão incompatível. PROFILE=local|rtt80|rtt150j aplica o
# atraso de aplicação só de teste (tests/net_delay_peer.gd) em todos os
# clientes; STALL=true interrompe o ator por 400 ms no meio do movimento.
# SEED fixa o jitter. Ver tests/sync_network_coordinator.gd.
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot4 >/dev/null; then GODOT_BIN="$(command -v godot4)";
  elif command -v godot >/dev/null; then GODOT_BIN="$(command -v godot)"; fi
fi
PROFILE="${PROFILE:-local}"
SEED="${SEED:-1}"
STALL="${STALL:-false}"
PORT="${TEST_PORT:-$((26080 + RANDOM % 1000))}"
if [[ -n "${TEST_LOG_DIR:-}" ]]; then
  TMP_DIR="$TEST_LOG_DIR"; mkdir -p "$TMP_DIR"; REMOVE_TMP_DIR=false
else
  TMP_DIR="$(mktemp -d)"; REMOVE_TMP_DIR=true
fi
PIDS=(); NAMES=(); STATUSES=(); WATCHDOG_PID=""

cleanup() {
  local status=$?
  trap - EXIT
  [[ -z "$WATCHDOG_PID" ]] || kill "$WATCHDOG_PID" 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]:-}"; do wait "$pid" 2>/dev/null || true; done
  [[ "$REMOVE_TMP_DIR" != true ]] || rm -rf "$TMP_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  local status="${1:-1}"; echo "SYNC_HARNESS_ERROR status=$status profile=$PROFILE seed=$SEED" >&2
  for log in "$TMP_DIR"/*.log; do [[ ! -f "$log" ]] || { echo "===== $log =====" >&2; cat "$log" >&2; }; done
  exit "$status"
}
trap 'fail $?' ERR
ok() { echo "ASSERT_OK name=$1"; }
assert_grep() { local n=$1 p=$2; shift 2; grep -qE -- "$p" "$@" && ok "$n" || { echo "ASSERT_FAILED name=$n pattern=$p" >&2; return 1; }; }
assert_no_grep() { local n=$1 p=$2; shift 2; if grep -qE -- "$p" "$@"; then echo "ASSERT_FAILED name=$n forbidden=$p" >&2; return 1; else ok "$n"; fi; }
assert_equal() { [[ "$2" == "$3" ]] && ok "$1" || { echo "ASSERT_FAILED name=$1 expected=$3 actual=$2" >&2; return 1; }; }
wait_marker() { local p=$1 f=$2 pid=$3; for _ in {1..600}; do grep -qE -- "$p" "$f" && return; kill -0 "$pid" 2>/dev/null || return 1; sleep 0.05; done; return 1; }

[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Godot 4 not found. Set GODOT_BIN." >&2; exit 127; }
echo "SYNC_TEST_START profile=$PROFILE seed=$SEED stall=$STALL commit=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --countdown-seconds=0.5 --round-end-delay-seconds=30 --round-seed="$SEED" --sync-test=true \
  --sync-profile="$PROFILE" --sync-stall="$STALL" >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!"); NAMES+=(server); SERVER_PID=$!
wait_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"

# Versão incompatível primeiro: recusada explicitamente, sem entrar na sala.
"$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id=old-build --url="ws://127.0.0.1:$PORT" \
  --test-protocol-version=8 >"$TMP_DIR/old-build.log" 2>&1 &
OLD_PID=$!
if wait "$OLD_PID"; then OLD_STATUS=0; else OLD_STATUS=$?; fi
echo "PROCESS_STATUS name=old-build pid=$OLD_PID status=$OLD_STATUS expected=1"
assert_equal old-build-exit-refused "$OLD_STATUS" 1
assert_grep old-build-refused-for-version 'JOIN_REJECTED id=old-build reason=protocol_version' "$TMP_DIR/old-build.log"

for id in 1 2 3 4; do
  NET_ARGS=()
  if [[ "$PROFILE" != "local" ]]; then NET_ARGS=(--test-net-profile="$PROFILE" --test-net-seed="$((SEED * 10 + id))"); fi
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" \
    --url="ws://127.0.0.1:$PORT" --sync-test=true "${NET_ARGS[@]}" >"$TMP_DIR/client-$id.log" 2>&1 &
  PIDS+=("$!"); NAMES+=("client-$id")
done
(
  sleep 150
  echo timeout >"$TMP_DIR/timeout.log"
  for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
) & WATCHDOG_PID=$!

for i in "${!PIDS[@]}"; do
  if wait "${PIDS[$i]}"; then status=0; else status=$?; fi
  STATUSES+=("$status"); echo "PROCESS_STATUS name=${NAMES[$i]} pid=${PIDS[$i]} status=$status"
done
kill "$WATCHDOG_PID" 2>/dev/null || true; wait "$WATCHDOG_PID" 2>/dev/null || true; WATCHDOG_PID=""
for i in "${!STATUSES[@]}"; do assert_equal "process-${NAMES[$i]}-exit" "${STATUSES[$i]}" 0; done
[[ ! -f "$TMP_DIR/timeout.log" ]] && ok watchdog-timeout-absent || fail 1

assert_equal four-joins "$(grep -c 'CLIENT_JOINED id=client-' "$TMP_DIR/server.log")" 4
assert_no_grep old-build-never-joined 'CLIENT_JOINED id=old-build' "$TMP_DIR/server.log"
for marker in SYNC_MOVE_OK SYNC_AIM_OK SYNC_VERTICAL_OK SYNC_DUPLICATE_OK SYNC_PRIVACY_OK \
    "SYNC_NETWORK_SERVER_OK clients=4 profile=$PROFILE" 'SERVER_SHUTDOWN_COMPLETE closed=4'; do
  assert_grep "server-${marker%% *}" "$marker" "$TMP_DIR/server.log"
done
if [[ "$PROFILE" != "local" ]]; then
  for id in 1 2 3 4; do assert_grep "client-$id-profile" "TEST_NET_PROFILE id=client-$id profile=$PROFILE" "$TMP_DIR/client-$id.log"; done
fi
if [[ "$STALL" == true ]]; then assert_grep stall-triggered 'SYNC_STALL_TRIGGERED' "$TMP_DIR"/client-*.log; fi
assert_no_grep no-role-leak 'peer_id=[0-9]+.*role=|ASSASSIN|DETECTIVE|VICTIM' "$TMP_DIR"/client-*.log
assert_no_grep no-failure-or-runtime-error 'SYNC_TEST_FAILED|ready_state != STATE_OPEN|SCRIPT ERROR|Trying to call an RPC via a multiplayer peer which is not connected' "$TMP_DIR"/*.log
grep -hE 'SYNC_(ROLES|MOVE|AIM|VERTICAL|DUPLICATE|PRIVACY)_RESULT|SYNC_STAGE_ENTER' "$TMP_DIR/server.log"
grep -hE 'NET_STATS|TEST_NET_APPLIED|SYNC_STALL' "$TMP_DIR"/client-*.log || true
echo "SYNC_NETWORK_TEST_OK profile=$PROFILE seed=$SEED stall=$STALL"
