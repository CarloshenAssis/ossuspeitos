#!/usr/bin/env bash
set -eEuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot4 >/dev/null; then GODOT_BIN="$(command -v godot4)";
  elif command -v godot >/dev/null; then GODOT_BIN="$(command -v godot)"; fi
fi
PORT="${TEST_PORT:-$((24080 + RANDOM % 1000))}"
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
  local status="${1:-1}"; echo "COMBAT_HARNESS_ERROR status=$status" >&2
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

"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
  --countdown-seconds=0.2 --round-end-delay-seconds=30 --round-seed=20250915 --combat-test=true \
  >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!"); NAMES+=(server); SERVER_PID=$!
wait_marker 'SERVER_READY' "$TMP_DIR/server.log" "$SERVER_PID"
for id in 1 2 3 4; do
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" \
    --url="ws://127.0.0.1:$PORT" --combat-test=true >"$TMP_DIR/client-$id.log" 2>&1 &
  PIDS+=("$!"); NAMES+=("client-$id")
done
(
  sleep 60
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
JOINED="$(sed -n 's/.*CLIENT_JOINED.*peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u)"
assert_equal four-unique-peers "$(wc -l <<<"$JOINED" | tr -d ' ')" 4
for marker in \
 'COMBAT_ROUND_ACTIVE players=4' 'COMBAT_INITIAL_HEALTH_OK players=4 health=100' \
 'COMBAT_INITIAL_INVENTORY_OK players=4' 'COMBAT_PICKUP_CONTEST_OK accepted=1 rejected=1 owners=1' \
 'COMBAT_FIRE_OK shots=1 ammo_consumed=1 damage=34' 'COMBAT_REPLAY_REJECTED' \
 'COMBAT_RATE_LIMIT_REJECTED' 'COMBAT_FIRE_RATE_REJECTED' 'COMBAT_RELOAD_OK' \
 'COMBAT_WALL_BLOCKED' 'COMBAT_DAMAGE_OK health_sequence=100,66,32,0' \
 'COMBAT_ELIMINATION_OK count=1' 'COMBAT_WIN_CONDITION_OK winner=INNOCENTS' \
 'COMBAT_POST_END_ACTIONS_REJECTED' 'COMBAT_PRIVACY_OK clients=4 leaks=0' \
 'COMBAT_SERVER_TEST_OK clients=4' 'COMBAT_SHUTDOWN_READY clients=4' \
 'COMBAT_SHUTDOWN_COMPLETE clients=4'; do
  assert_grep "server-marker-${marker%% *}" "$marker" "$TMP_DIR/server.log"
done
for id in 1 2 3 4; do
  assert_grep "client-$id-private" "COMBAT_PRIVATE_STATE_OK id=client-$id updates=[1-9]" "$TMP_DIR/client-$id.log"
  assert_grep "client-$id-complete" "COMBAT_CLIENT_TEST_OK id=client-$id" "$TMP_DIR/client-$id.log"
  for rpc in combat_private_state pickup_public_state combat_public_shot combat_public_elimination combat_action_rejected; do
    assert_grep "client-$id-rpc-$rpc" "COMBAT_RPC_RECEIVED name=$rpc id=client-$id" "$TMP_DIR/client-$id.log"
  done
done
assert_equal three-hit-confirmations "$(grep -h -c 'COMBAT_RPC_RECEIVED name=combat_hit_confirmed' "$TMP_DIR"/client-*.log | awk '{s+=$1} END{print s}')" 3
assert_equal hit-confirm-only-one-client "$(grep -l 'COMBAT_RPC_RECEIVED name=combat_hit_confirmed' "$TMP_DIR"/client-*.log | wc -l | tr -d ' ')" 1
COMPLETED="$(sed -n 's/.*COMBAT_CLIENT_TEST_OK id=client-\([1-4]\).*/\1/p' "$TMP_DIR"/client-*.log | sort -u)"
assert_equal four-completed-clients "$(wc -l <<<"$COMPLETED" | tr -d ' ')" 4
assert_no_grep no-role-leak 'peer_id=[0-9]+.*role=|ASSASSIN|DETECTIVE|VICTIM' "$TMP_DIR"/*.log
assert_no_grep no-private-payload 'health.*weapon_id|magazine.*reserve' "$TMP_DIR"/client-*.log
assert_no_grep no-timeout-or-unexpected-runtime-error 'COMBAT_TEST_STAGE_TIMEOUT|COMBAT_NETWORK_TEST_FAILURE|ready_state != STATE_OPEN|The InputMap action .* doesn.t exist|Trying to call an RPC via a multiplayer peer which is not connected|SCRIPT ERROR' "$TMP_DIR"/*.log
cat "$TMP_DIR/server.log"
echo 'COMBAT_NETWORK_TEST_OK server=1 clients=4'
