#!/usr/bin/env bash
# Mandatory production-class scene + actual server/four clients. Existing
# harnesses retain ownership of their processes and preserve their exit status.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
: "${GODOT_BIN:?Set GODOT_BIN to the approved Godot executable}"
BASE="${TEST_LOG_DIR:-${TMPDIR:-/tmp}}"
mkdir -p "$BASE"
RUN_DIR="$(mktemp -d "$BASE/gameplay-integration-XXXXXX")"
PORT="${TEST_PORT:-$((30000 + RANDOM % 10000))}"
CHILD_PID=""
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [[ -n "$CHILD_PID" ]]; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
run_owned() {
  "$@" &
  CHILD_PID=$!
  local status=0
  wait "$CHILD_PID" || status=$?
  CHILD_PID=""
  return "$status"
}
echo "GAMEPLAY_INTEGRATION_START logs=$RUN_DIR seed=8 profile=local port=$PORT"
run_owned "$GODOT_BIN" --headless --path "$ROOT" "$ROOT/tests/scenes/gameplay_integration.tscn" >"$RUN_DIR/scene.log" 2>&1
grep -q '^GAMEPLAY_INTEGRATION_SCENE_OK checks=' "$RUN_DIR/scene.log"
run_owned env TEST_PORT="$PORT" TEST_LOG_DIR="$RUN_DIR/combat" COMBAT_CLIENTS=4 COMBAT_EXTENDED=false \
  bash "$ROOT/tests/combat_network_test.sh" >"$RUN_DIR/combat.log" 2>&1
grep -q '^COMBAT_NETWORK_TEST_OK server=1 clients=4 extended=false$' "$RUN_DIR/combat.log"
if [[ "${RUN_CAMPAIGN:-false}" == true ]]; then
  run_owned env TEST_PORT="$PORT" TEST_LOG_DIR="$RUN_DIR/campaign" PROFILE=local SEED=8 \
    bash "$ROOT/tests/campaign_test.sh" >"$RUN_DIR/campaign.log" 2>&1
  grep -q '^CAMPAIGN_TEST_OK .*clients=8 rounds=3' "$RUN_DIR/campaign.log"
fi
cat "$RUN_DIR/scene.log"
echo "GAMEPLAY_INTEGRATION_TEST_OK clients=4 logs=$RUN_DIR"
