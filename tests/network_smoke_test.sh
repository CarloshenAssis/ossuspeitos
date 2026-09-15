#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot || true)}"
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
WATCHDOG_PID=""
TEST_FINISHED=false

cleanup() {
  [[ -n "$WATCHDOG_PID" ]] && kill "$WATCHDOG_PID" 2>/dev/null || true
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
  [[ "$REMOVE_TMP_DIR" == true ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

report_failure() {
  local status=$?
  echo "Network smoke test failed (exit=$status). Logs:" >&2
  cat "$TMP_DIR"/*.log 2>/dev/null || true
  exit "$status"
}
trap report_failure ERR

if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Godot 4 not found. Set GODOT_BIN to the executable." >&2
  exit 127
fi

"$GODOT_BIN" --headless --path "$ROOT" -- --mode=server --bind=127.0.0.1 \
  --port="$PORT" --stop-after-clients=4 >"$TMP_DIR/server.log" 2>&1 &
PIDS+=("$!")

for _ in {1..100}; do
  grep -q 'SERVER_READY' "$TMP_DIR/server.log" && break
  kill -0 "${PIDS[0]}" 2>/dev/null || { cat "$TMP_DIR/server.log"; exit 1; }
  sleep 0.05
done
grep -q 'SERVER_READY' "$TMP_DIR/server.log" || { cat "$TMP_DIR/server.log"; exit 1; }

for id in 1 2 3 4; do
  "$GODOT_BIN" --headless --path "$ROOT" -- --mode=client --client-id="client-$id" \
    --url="ws://127.0.0.1:$PORT" --expect-clients=4 >"$TMP_DIR/client-$id.log" 2>&1 &
  PIDS+=("$!")
done

(
  sleep 15
  if [[ "$TEST_FINISHED" != true ]]; then
    echo "Timed out waiting for network smoke test" >"$TMP_DIR/timeout.log"
    for pid in "${PIDS[@]}"; do kill "$pid" 2>/dev/null || true; done
  fi
) &
WATCHDOG_PID=$!

for pid in "${PIDS[@]}"; do
  wait "$pid"
done
TEST_FINISHED=true
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true
WATCHDOG_PID=""
[[ ! -f "$TMP_DIR/timeout.log" ]]

grep -q 'SERVER_TEST_OK clients=4' "$TMP_DIR/server.log"
[[ "$(grep -c 'CLIENT_JOINED id=client-' "$TMP_DIR/server.log")" -eq 4 ]]
[[ "$(sed -n 's/.*CLIENT_JOINED.*peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" -eq 4 ]]
[[ "$(grep -c 'PLAYER_SPAWNED peer_id=' "$TMP_DIR/server.log")" -eq 4 ]]
[[ "$(sed -n 's/.*PLAYER_SPAWNED.*position=\([^ ]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" -eq 4 ]]
[[ "$(grep -c 'MOVEMENT_AUTHORIZED peer_id=' "$TMP_DIR/server.log")" -eq 4 ]]
[[ "$(sed -n 's/.*MOVEMENT_AUTHORIZED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" -eq 4 ]]
grep -q 'INPUT_REJECTED peer_id=.* reason=move_magnitude' "$TMP_DIR/server.log"
grep -q 'SERVER_MOVEMENT_TEST_OK players=4 .* rejected_impossible=1' "$TMP_DIR/server.log"
awk '
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
' "$TMP_DIR/server.log"
awk -F'[=, ]+' '
  /PLAYER_STATE/ {
    for (field = 1; field <= NF; field++) {
      if ($field == "position") {
        x = $(field + 1); y = $(field + 2); z = $(field + 3)
        if (x < -11.501 || x > 11.501 || y < 0.999 || y > 1.001 || z < -11.501 || z > 11.501) exit 1
        found++
      }
    }
  }
  END { if (found != 4) exit 1 }
' "$TMP_DIR/server.log"
[[ "$(grep -c 'CLIENT_TEST_CONFIRMED peer_id=' "$TMP_DIR/server.log")" -eq 4 ]]
[[ "$(sed -n 's/.*CLIENT_TEST_CONFIRMED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" -eq 4 ]]
diff -u \
  <(sed -n 's/.*CLIENT_JOINED.*peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u) \
  <(sed -n 's/.*CLIENT_TEST_CONFIRMED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u)
grep -q 'SERVER_SHUTDOWN_COMPLETE closed=4' "$TMP_DIR/server.log"
[[ "$(grep -c 'CLIENT_SHUTDOWN_READY peer_id=' "$TMP_DIR/server.log")" -eq 4 ]]
[[ "$(sed -n 's/.*CLIENT_SHUTDOWN_READY peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u | wc -l)" -eq 4 ]]
diff -u \
  <(sed -n 's/.*CLIENT_TEST_CONFIRMED peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u) \
  <(sed -n 's/.*CLIENT_SHUTDOWN_READY peer_id=\([0-9][0-9]*\).*/\1/p' "$TMP_DIR/server.log" | sort -u)
grep -q 'SERVER_SHUTDOWN_READY clients=4' "$TMP_DIR/server.log"
! grep -q 'SERVER_SHUTDOWN_TIMEOUT' "$TMP_DIR"/*.log
! grep -q 'ready_state != STATE_OPEN' "$TMP_DIR"/*.log
for id in 1 2 3 4; do
	grep -q "CLIENT_TEST_OK id=client-$id" "$TMP_DIR/client-$id.log"
	[[ "$(grep -c "CLIENT_SHUTDOWN_PREPARE id=client-$id" "$TMP_DIR/client-$id.log")" -eq 1 ]]
	[[ "$(grep -c "CLIENT_SHUTDOWN_COMPLETE id=client-$id" "$TMP_DIR/client-$id.log")" -eq 1 ]]
done
cat "$TMP_DIR/server.log"
echo "NETWORK_SMOKE_OK server=1 clients=4"
