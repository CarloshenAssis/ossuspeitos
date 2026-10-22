#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${GODOT_BIN:?Set GODOT_BIN to Godot4.4.1}"
CLIENTS="${PHASE2_CLIENTS:-4}"
ROUNDS="${PHASE2_ROUNDS:-1}"
PROFILE="${PROFILE:-local}"
NET_ARGS=()
if [[ "$PROFILE" != local ]]; then NET_ARGS=(--test-net-profile="$PROFILE" --test-net-seed=8); fi
PORT="${TEST_PORT:-$((42000 + RANDOM % 1000))}"
LOGS="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$LOGS"
PIDS=()
cleanup() {
  local code=$?
  trap - EXIT INT TERM
  for pid in "${PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
  for pid in "${PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
  exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ "$CLIENTS" == 4 || "$CLIENTS" == 8 ]]
[[ "$ROUNDS" =~ ^[1-3]$ ]]
SCENE="$ROOT/tests/scenes/phase2_network.tscn"
"$GODOT_BIN" --headless --path "$ROOT" "$SCENE" -- --mode=server --bind=127.0.0.1 --port="$PORT" \
 --countdown-seconds=3 --round-end-delay-seconds=2 --round-seed=8 --phase2-clients="$CLIENTS" --phase2-rounds="$ROUNDS" > "$LOGS/server.log" 2>&1 &
PIDS+=("$!")
for _ in {1..200}; do
  grep -q SERVER_READY "$LOGS/server.log" && break
  kill -0 "${PIDS[0]}" 2>/dev/null || { cat "$LOGS/server.log"; exit 1; }
  sleep 0.05
done
grep -q SERVER_READY "$LOGS/server.log"
for ((client=1;client<=CLIENTS;client++)); do
 "$GODOT_BIN" --headless --path "$ROOT" "$SCENE" -- --mode=client --client-id="phase2-$client" --url="ws://127.0.0.1:$PORT" \
  --phase2-clients="$CLIENTS" --phase2-rounds="$ROUNDS" "${NET_ARGS[@]}" > "$LOGS/client-$client.log" 2>&1 &
 PIDS+=("$!")
done
PENDING=("${PIDS[@]}")
while ((${#PENDING[@]})); do
  finished=""
  if wait -n -p finished "${PENDING[@]}"; then code=0; else code=$?; fi
  if [[ "$code" != 0 ]]; then
    tail -n 70 "$LOGS/server.log"
    exit "$code"
  fi
  remaining=()
  for pid in "${PENDING[@]}"; do [[ "$pid" == "$finished" ]] || remaining+=("$pid"); done
  PENDING=("${remaining[@]}")
done
if grep -Eq 'SCRIPT ERROR|Parse Error|^ERROR:|PHASE2_NETWORK_FAILED' "$LOGS"/*.log; then
  tail -n 70 "$LOGS/server.log"; exit 1
fi
grep -q "PHASE2_SERVER_OK clients=$CLIENTS rounds=$ROUNDS" "$LOGS/server.log"
[[ "$(grep -c PHASE2_ROUND_OK "$LOGS/server.log")" == "$ROUNDS" ]]
for ((client=1;client<=CLIENTS;client++)); do grep -q "PHASE2_CLIENT_OK id=phase2-$client rounds=$ROUNDS" "$LOGS/client-$client.log"; done
cat "$LOGS/server.log"
echo "PHASE2_NETWORK_TEST_OK clients=$CLIENTS rounds=$ROUNDS profile=$PROFILE logs=$LOGS"
