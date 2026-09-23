#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-}"
if [[ -z "$GODOT_BIN" ]]; then
  if command -v godot4 >/dev/null; then
    GODOT_BIN="$(command -v godot4)"
  elif command -v godot >/dev/null; then
    GODOT_BIN="$(command -v godot)"
  fi
fi
PORT="${TEST_PORT:-$((19080 + RANDOM % 1000))}"
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
PROCESS_STATUSES=()
WATCHDOG_PID=""
TEST_FINISHED=false

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

report_failure() {
	local status="$1"
	local line="$2"
	local command="$3"
	echo "HARNESS_ERROR line=$line status=$status command=$command" >&2
	echo "Network smoke test failed (exit=$status). Logs:" >&2
	if compgen -G "$TMP_DIR/*.log" >/dev/null; then
		cat "$TMP_DIR"/*.log >&2
	fi
	exit "$status"
}
trap 'report_failure "$?" "$LINENO" "$BASH_COMMAND"' ERR

check_ok() {
	echo "ASSERT_OK name=$1"
}

check_failed() {
	echo "ASSERT_FAILED name=$1 detail=$2" >&2
	return 1
}

assert_grep() {
	local name="$1"
	local pattern="$2"
	shift 2
	if grep -q -- "$pattern" "$@"; then
		check_ok "$name"
	else
		check_failed "$name" "pattern not found: $pattern"
	fi
}

assert_no_grep() {
	local name="$1"
	local pattern="$2"
	shift 2
	if grep -q -- "$pattern" "$@"; then
		check_failed "$name" "forbidden pattern found: $pattern"
	else
		check_ok "$name"
	fi
}

assert_equal() {
	local name="$1"
	local actual="$2"
	local expected="$3"
	if [[ "$actual" == "$expected" ]]; then
		check_ok "$name"
	else
		check_failed "$name" "expected=$expected actual=$actual"
	fi
}

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Godot 4 not found. Set GODOT_BIN to the executable." >&2
  exit 127
fi

"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 \
  --port="$PORT" --stop-after-clients=4 >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!")
PROCESS_NAMES+=("server")

for _ in {1..100}; do
  grep -q 'SERVER_READY' "$TMP_DIR/server.log" && break
  kill -0 "${PIDS[0]}" 2>/dev/null || { cat "$TMP_DIR/server.log"; exit 1; }
  sleep 0.05
done
assert_grep "server-ready" 'SERVER_READY' "$TMP_DIR/server.log"

for id in 1 2 3 4; do
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" \
    --url="ws://127.0.0.1:$PORT" --expect-clients=4 >"$TMP_DIR/client-$id.log" 2>&1 &
	PIDS+=("$!")
	PROCESS_NAMES+=("client-$id")
done

(
  sleep 15
  if [[ "$TEST_FINISHED" != true ]]; then
    echo "Timed out waiting for network smoke test" >"$TMP_DIR/timeout.log"
	for pid in "${PIDS[@]}"; do
		if kill "$pid" 2>/dev/null; then
			echo "WATCHDOG_KILL pid=$pid status=0"
		else
			echo "WATCHDOG_KILL pid=$pid status=$?"
		fi
	done
  fi
) &
WATCHDOG_PID=$!

for index in "${!PIDS[@]}"; do
	pid="${PIDS[$index]}"
	name="${PROCESS_NAMES[$index]}"
	if wait "$pid"; then
		process_status=0
	else
		process_status=$?
	fi
	echo "PROCESS_STATUS name=$name pid=$pid status=$process_status"
	PROCESS_STATUSES+=("$process_status")
done
for index in "${!PROCESS_STATUSES[@]}"; do
	assert_equal "process-${PROCESS_NAMES[$index]}-exit" "${PROCESS_STATUSES[$index]}" "0"
done
TEST_FINISHED=true
if kill "$WATCHDOG_PID" 2>/dev/null; then
	watchdog_kill_status=0
else
	watchdog_kill_status=$?
fi
echo "WATCHDOG_KILL status=$watchdog_kill_status"
if wait "$WATCHDOG_PID" 2>/dev/null; then
	watchdog_status=0
else
	watchdog_status=$?
fi
echo "WATCHDOG_STATUS status=$watchdog_status expected=143"
if [[ "$watchdog_status" == 0 || "$watchdog_status" == 143 ]]; then
	check_ok "watchdog-exit"
else
	check_failed "watchdog-exit" "expected 0 or 143, actual=$watchdog_status"
fi
WATCHDOG_PID=""
if [[ ! -f "$TMP_DIR/timeout.log" ]]; then
	check_ok "watchdog-timeout-absent"
else
	check_failed "watchdog-timeout-absent" "timeout.log exists"
fi

assert_grep "server-test-ok" 'SERVER_TEST_OK clients=4' "$TMP_DIR/server.log"
assert_equal "four-client-joins" "$(grep -c 'CLIENT_JOINED id=client-' "$TMP_DIR/server.log")" "4"
assert_equal "four-unique-join-peers" "$(sed -n 's/.*CLIENT_JOINED.*peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" "4"
assert_equal "four-player-spawns" "$(grep -c 'PLAYER_SPAWNED peer_id=' "$TMP_DIR/server.log")" "4"
assert_equal "four-distinct-spawn-positions" "$(sed -n 's/.*PLAYER_SPAWNED.*position=\([^ ]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" "4"
assert_equal "four-movement-authorizations" "$(grep -c 'MOVEMENT_AUTHORIZED peer_id=' "$TMP_DIR/server.log")" "4"
assert_equal "four-unique-moving-peers" "$(sed -n 's/.*MOVEMENT_AUTHORIZED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" "4"
assert_grep "impossible-input-rejected" 'INPUT_REJECTED peer_id=.* reason=move_magnitude' "$TMP_DIR/server.log"
assert_grep "movement-test-ok" 'SERVER_MOVEMENT_TEST_OK players=4 .* rejected_impossible=1' "$TMP_DIR/server.log"
if awk '
  /SERVER_MOVEMENT_TEST_OK/ {
    for (field = 1; field <= NF; field++) {
      if ($field ~ /^max_speed=/) {
        split($field, value, "=")
        if (value[2] > 5.001) exit 1
        found = 1
      }
    }
  }
  END { if (!found) exit 1 }
' "$TMP_DIR/server.log"; then
	check_ok "authoritative-speed-limit"
else
	check_failed "authoritative-speed-limit" "max speed missing or greater than 5.001"
fi
# O limite vem da regra oficial, para o teste não divergir quando a arena muda.
ARENA_LIMIT="$(sed -n 's/^const ARENA_HALF_EXTENT := \([0-9.]*\).*/\1/p' "$ROOT/shared/movement_rules.gd")"
[[ -n "$ARENA_LIMIT" ]] || { echo "ARENA_HALF_EXTENT not found" >&2; exit 1; }
if awk -F'[=, ]+' -v limit="$ARENA_LIMIT" '
  /PLAYER_STATE/ {
    for (field = 1; field <= NF; field++) {
      if ($field == "position") {
        x = $(field + 1); y = $(field + 2); z = $(field + 3)
        bound = limit + 0.001
        if (x < -bound || x > bound || y < 0.999 || y > 1.001 || z < -bound || z > bound) exit 1
        found++
      }
    }
  }
  END { if (found != 4) exit 1 }
' "$TMP_DIR/server.log"; then
	check_ok "authoritative-arena-bounds"
else
	check_failed "authoritative-arena-bounds" "expected four bounded player states"
fi
assert_equal "four-test-confirmations" "$(grep -c 'CLIENT_TEST_CONFIRMED peer_id=' "$TMP_DIR/server.log")" "4"
assert_equal "four-unique-confirmed-peers" "$(sed -n 's/.*CLIENT_TEST_CONFIRMED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" "4"
if diff -u \
  <(sed -n 's/.*CLIENT_JOINED.*peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u) \
  <(sed -n 's/.*CLIENT_TEST_CONFIRMED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u); then
	check_ok "joined-peers-match-confirmed-peers"
else
	check_failed "joined-peers-match-confirmed-peers" "peer sets differ"
fi
assert_grep "server-shutdown-complete" 'SERVER_SHUTDOWN_COMPLETE closed=4' "$TMP_DIR/server.log"
assert_equal "four-shutdown-ready" "$(grep -c 'CLIENT_SHUTDOWN_READY peer_id=' "$TMP_DIR/server.log")" "4"
assert_equal "four-unique-shutdown-ready-peers" "$(sed -n 's/.*CLIENT_SHUTDOWN_READY peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" "4"
if diff -u \
  <(sed -n 's/.*CLIENT_TEST_CONFIRMED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u) \
  <(sed -n 's/.*CLIENT_SHUTDOWN_READY peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u); then
	check_ok "confirmed-peers-match-shutdown-ready-peers"
else
	check_failed "confirmed-peers-match-shutdown-ready-peers" "peer sets differ"
fi
assert_grep "server-shutdown-ready" 'SERVER_SHUTDOWN_READY clients=4' "$TMP_DIR/server.log"
assert_no_grep "server-shutdown-timeout-absent" 'SERVER_SHUTDOWN_TIMEOUT' "$TMP_DIR"/*.log
assert_no_grep "websocket-open-state-errors-absent" 'ready_state != STATE_OPEN' "$TMP_DIR"/*.log
for id in 1 2 3 4; do
	assert_grep "client-$id-test-ok" "CLIENT_TEST_OK id=client-$id" "$TMP_DIR/client-$id.log"
	assert_equal "client-$id-single-shutdown-prepare" "$(grep -c "CLIENT_SHUTDOWN_PREPARE id=client-$id" "$TMP_DIR/client-$id.log")" "1"
	assert_equal "client-$id-single-shutdown-complete" "$(grep -c "CLIENT_SHUTDOWN_COMPLETE id=client-$id" "$TMP_DIR/client-$id.log")" "1"
done
cat "$TMP_DIR/server.log"
echo "FINAL_CHECKS status=0"
echo "NETWORK_SMOKE_OK server=1 clients=4"
