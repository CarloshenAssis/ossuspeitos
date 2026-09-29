#!/usr/bin/env bash
set -Euo pipefail

# Fase 11: prova por mutação que os testes pegam cada falha desta fase. As
# mutações só valem em binário de desenvolvimento (`--test-mutation`):
#   client_fake_armed    -> presence_test: pistola sem coleta oficial;
#   duplicate_hit_marker -> presence_test: marcador repetido;
#   step_on_reset        -> presence_test: passo no teleporte de reset;
#   dead_weapon_visible  -> presence_test: pistola própria de morto/espectador;
#   cross_room_armed     -> rooms_network_test: arma de uma sala em outra.

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

presence_with() {
  "$GODOT_BIN" --headless --path "$ROOT" --script tests/presence_test.gd -- --test-mutation="$1" >"$OUT/$1.out" 2>&1
}

presence_with client_fake_armed; status=$?
expect_caught client_fake_armed "$status" 'PRESENCE_TEST_FAILED unarmed remote shows no pistol' "$OUT/client_fake_armed.out"
presence_with duplicate_hit_marker; status=$?
expect_caught duplicate_hit_marker "$status" 'PRESENCE_TEST_FAILED (no marker without an own official hit|a repeated confirmation shows no second marker)' "$OUT/duplicate_hit_marker.out"
presence_with step_on_reset; status=$?
expect_caught step_on_reset "$status" 'PRESENCE_TEST_FAILED reset teleport plays no footstep' "$OUT/step_on_reset.out"
presence_with dead_weapon_visible; status=$?
expect_caught dead_weapon_visible "$status" 'PRESENCE_TEST_FAILED spectator: no own pistol' "$OUT/dead_weapon_visible.out"

mkdir -p "$OUT/cross_room_armed"
SERVER_EXTRA_ARGS="--test-mutation=cross_room_armed" TEST_LOG_DIR="$OUT/cross_room_armed" GODOT_BIN="$GODOT_BIN" \
  "$ROOT/tests/rooms_network_test.sh" >"$OUT/cross_room_armed.out" 2>&1; status=$?
expect_caught cross_room_armed "$status" 'ASSERT_FAILED name=([BC][0-9]-never-sees-armed|[BC][0-9]-sees-only-own-room-peers)' "$OUT/cross_room_armed.out"

if [[ "$FAILED" -gt 0 ]]; then
  echo "PHASE11_MUTATION_TEST_FAILED survived=$FAILED" >&2
  exit 1
fi
echo "PHASE11_MUTATION_TEST_OK caught=5"
