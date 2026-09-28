#!/usr/bin/env bash
set -Euo pipefail

# Fase 10: prova por mutação que os testes pegam as falhas desta fase. Cada
# mutação (só em binário de desenvolvimento, `--test-mutation`) tem de fazer
# o teste correspondente falhar pelo motivo certo:
#   no_teleport          -> rooms_network_test: reset da rodada 2;
#   cross_room_leak      -> rooms_network_test: cliente vê outra sala;
#   slow_room_transition -> rooms_network_test: transição acima do limite;
#   no_round_banner      -> match_hud_test: aviso de nova rodada.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot4 || command -v godot)}"
OUT="${TEST_LOG_DIR:-$(mktemp -d)}"
mkdir -p "$OUT"
FAILED=0

expect_caught() {
  local name="$1" status="$2" pattern="$3"; shift 3
  if [[ "$status" -ne 0 ]] && grep -qE -- "$pattern" "$@" 2>/dev/null; then
    echo "MUTATION_CAUGHT name=$name"
  else
    echo "MUTATION_SURVIVED name=$name status=$status pattern=$pattern" >&2
    FAILED=$((FAILED + 1))
  fi
}

rooms_with() {
  local mutation="$1"
  mkdir -p "$OUT/$mutation"
  SERVER_EXTRA_ARGS="--test-mutation=$mutation" TEST_LOG_DIR="$OUT/$mutation" GODOT_BIN="$GODOT_BIN" \
    "$ROOT/tests/rooms_network_test.sh" >"$OUT/$mutation.out" 2>&1
}

rooms_with no_teleport; status=$?
expect_caught no_teleport "$status" 'ROOMS_TEST_FAILED round_reset room=1 round_id=2 off_spawn=[1-9]' "$OUT/no_teleport/server.log"

rooms_with cross_room_leak; status=$?
expect_caught cross_room_leak "$status" 'ASSERT_FAILED name=[A-C][0-9]-only-own-code' "$OUT/cross_room_leak.out"

rooms_with slow_room_transition; status=$?
expect_caught slow_room_transition "$status" 'TRANSITION_REPORT_SLOW limit_ms=750 .*(room_join|room_create|ready_ack)=' "$OUT/slow_room_transition.out"

"$GODOT_BIN" --headless --path "$ROOT" --script tests/match_hud_test.gd -- --test-mutation=no_round_banner \
  >"$OUT/no_round_banner.out" 2>&1; status=$?
expect_caught no_round_banner "$status" 'MATCH_HUD_CHECK_FAILED.*new-round banner|MATCH_HUD_TEST_FAILED.*banner' "$OUT/no_round_banner.out"

if [[ "$FAILED" -gt 0 ]]; then
  echo "PHASE10_MUTATION_TEST_FAILED survived=$FAILED" >&2
  exit 1
fi
echo "PHASE10_MUTATION_TEST_OK caught=4"
